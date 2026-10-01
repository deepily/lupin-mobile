import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/constants/app_constants.dart';

/// Test seam over the `audioplayers.AudioPlayer` methods that `StreamingTtsPlayer` uses.
///
/// It lets the player be unit-tested without the platform channels `audioplayers` requires.
/// Production uses [_RealStreamingTtsAudioPlayer]; tests pass a Mocktail implementation.
abstract class StreamingTtsAudioPlayer {
  /// Emits when the current playback finishes.
  Stream<void> get onComplete;
  /// Plays [wavBytes], a complete WAV file.
  Future<void> play( Uint8List wavBytes );
  /// Stops playback.
  Future<void> stop();
  /// Releases the player.
  Future<void> dispose();
}

class _RealStreamingTtsAudioPlayer implements StreamingTtsAudioPlayer {
  final AudioPlayer _p = AudioPlayer();

  @override Stream<void> get onComplete => _p.onPlayerComplete;

  @override
  Future<void> play( Uint8List wavBytes ) => _p.play( BytesSource( wavBytes ) );

  @override
  Future<void> stop() async {
    try { await _p.stop(); } catch ( _ ) {
      // audioplayers can throw on stop of an already-stopped player; ignore.
    }
  }

  @override
  Future<void> dispose() => _p.dispose();
}

/// Slim ElevenLabs TTS client for Lupin Mobile.
///
/// It is a purpose-built alternative to the legacy `EnhancedTTSService`, which stays on disk, tree-shaken,
/// with 2.7K lines of adaptive-strategy infrastructure that is not needed yet. This player:
///   1. Sends `speak(text)` to the backend `/api/get-speech-elevenlabs` through the shared Dio, whose auth
///      interceptor injects the Bearer token.
///   2. Consumes WebSocket events fed in by `app.dart _dispatchWsEvent`: status updates, binary audio chunks,
///      completion and error signals.
///   3. Plays the audio with `audioplayers` as a single PCM blob once the stream completes. Streaming while
///      receiving is a later optimization; ElevenLabs Flash latency and 1-2 s texts make waiting imperceptible.
///
/// `TtsCompleteEvent` fires only after playback has actually finished, not when the WebSocket stream signals done.
/// `TtsOrchestrator` treats complete as "safe to advance the FIFO". Firing it earlier makes the next `play()`
/// preempt the current utterance mid-sentence, because `audioplayers` has a single voice.
///
/// Event contract (matches backend `src/cosa/rest/routers/speech.py`):
///   - `audio_streaming_status`: `{status: "loading"|"streaming", text}`
///   - `audio_streaming_chunk`: binary PCM, wrapped by WebSocketService into `{type, data: List<int>}`
///   - `audio_streaming_complete`: `{status: "success", text}`
///   - `tts_error`: `{error_code: "quota_exceeded"|..., text, details}`
class StreamingTtsPlayer {
  final Dio                      _dio;
  final StreamingTtsAudioPlayer  _player;

  /// Dev-only: when true, `speak()` sends `debug_simulate_error: true` in the POST body.
  ///
  /// The backend (`/api/get-speech-elevenlabs`) then emits a `tts_error` WebSocket event with
  /// `error_code=quota_exceeded` instead of calling ElevenLabs. That checks the orchestrator's quota-fallback
  /// path on a device without an exhausted account. It comes from the `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define,
  /// is gated on `kDebugMode`, and is forced off in release builds.
  final bool _simulateTtsError;

  final StreamController<TtsStatusEvent>   _statusCtrl   = StreamController.broadcast();
  final StreamController<TtsCompleteEvent> _completeCtrl = StreamController.broadcast();
  final StreamController<TtsErrorEvent>    _errorCtrl    = StreamController.broadcast();

  StreamSubscription<void>? _playerCompleteSub;

  final List<int> _pcmBuffer = [];
  bool            _isActive            = false;  // true between speak() send and complete/error
  bool            _isPlaying           = false;  // true while audio is actually playing
  Completer<void>? _activePlaybackCompleter;     // signals end of current playback

  /// Creates a player that sends requests through [_dio].
  ///
  /// Tests pass [simulateTtsError] explicitly; production reads the `LUPIN_DEV_SIMULATE_TTS_ERROR`
  /// dart-define and requires `kDebugMode`.
  StreamingTtsPlayer(
    this._dio, {
    StreamingTtsAudioPlayer? player,
    bool?                    simulateTtsError,
  } ) : _player           = player ?? _RealStreamingTtsAudioPlayer(),
        _simulateTtsError = simulateTtsError ?? (
          kDebugMode && const bool.fromEnvironment(
            'LUPIN_DEV_SIMULATE_TTS_ERROR',
            defaultValue: false,
          )
        ) {
    _playerCompleteSub = _player.onComplete.listen( ( _ ) {
      _isPlaying = false;
      final c = _activePlaybackCompleter;
      if ( c != null && !c.isCompleted ) c.complete();
    } );
  }

  /// Emits status updates for the current request.
  Stream<TtsStatusEvent>   get statusStream   => _statusCtrl.stream;
  /// Emits once when playback of the current utterance has finished.
  Stream<TtsCompleteEvent> get completeStream => _completeCtrl.stream;
  /// Emits when the request or the playback fails.
  Stream<TtsErrorEvent>    get errorStream    => _errorCtrl.stream;

  /// True while a speak request is pending or audio is playing.
  ///
  /// Pending means a speak request was sent and no completion or error has arrived. The orchestrator uses this
  /// to decide when to advance the FIFO queue.
  bool get isPlaying => _isActive || _isPlaying;

  /// Sends a TTS request and returns when the HTTP POST is acknowledged.
  ///
  /// The backend then streams audio chunks on the WebSocket. Throws [DioException] on HTTP failure,
  /// and the orchestrator decides whether to fall back.
  ///
  /// [voiceId] is the persona pass-through. The body's `voice_id` tells the backend which per-session
  /// persona voice to render with. When null the key is omitted, not sent as null, so the server's
  /// "absent means the default voice" fallback holds.
  /// Design: src/docs/decisions/README.md (R-TTS-voice-id)
  Future<void> speak( {
    required String text,
    required String sessionId,
    String? voiceId,
  } ) async {
    _pcmBuffer.clear();
    _isActive = true;

    try {
      await _dio.post<Map<String, dynamic>>(
        AppConstants.apiGetAudioElevenLabs,
        data: {
          'session_id': sessionId,
          'text'      : text,
          if ( voiceId != null )  'voice_id'            : voiceId,
          if ( _simulateTtsError ) 'debug_simulate_error' : true,
        },
      );
    } catch ( _ ) {
      _isActive = false;
      _pcmBuffer.clear();
      rethrow;
    }
  }

  /// Stops any in-flight playback and clears buffered audio.
  ///
  /// The orchestrator calls it on urgent-preempt. A stopped utterance does not fire `TtsCompleteEvent`,
  /// because advancing the FIFO on behalf of an abandoned utterance would be wrong.
  Future<void> stop() async {
    _isActive = false;
    _pcmBuffer.clear();
    // Clear the field before waking the hung completer. The identity check inside `_playPcmBuffer`
    // then sees the field is no longer its completer and skips the complete emission.
    final stale = _activePlaybackCompleter;
    _activePlaybackCompleter = null;
    await _player.stop();
    _isPlaying = false;
    if ( stale != null && !stale.isCompleted ) stale.complete();
  }

  /// Handles one of the four relevant WebSocket event types.
  ///
  /// `app.dart _dispatchWsEvent` calls it, and the caller need not type-check: the player filters by [type].
  /// Events other than a status update are ignored when no speak request is active.
  void handleWsEvent( String type, Map<String, dynamic> payload ) {
    if ( !_isActive && type != AppConstants.eventAudioStreamingStatus ) {
      // Ignore stray events if we didn't initiate a speak request.
      return;
    }
    switch ( type ) {
      case AppConstants.eventAudioStreamingStatus:
        final status = payload[ 'status' ] as String? ?? 'unknown';
        _statusCtrl.add( TtsStatusEvent( status: status, detail: payload[ 'text' ] as String? ) );
        break;

      case AppConstants.eventAudioStreamingChunk:
        final data = payload[ 'data' ];
        if ( data is List<int> ) {
          _pcmBuffer.addAll( data );
        }
        break;

      case AppConstants.eventAudioStreamingComplete:
        // Play the accumulated PCM buffer. The backend sends 24 kHz PCM, so a minimal WAV header is wrapped
        // on for `audioplayers`. `_playPcmBuffer` fires `_completeCtrl` itself after playback finishes; firing here
        // would advance the orchestrator's FIFO while audio was still playing, causing overlap.
        _isActive = false;
        _playPcmBuffer();
        break;

      case 'tts_error':
        final code = payload[ 'error_code' ] as String? ?? 'unknown';
        final text = payload[ 'text' ] as String?;
        _pcmBuffer.clear();
        _isActive = false;
        _errorCtrl.add( TtsErrorEvent( errorCode: code, message: text ) );
        break;
    }
  }

  Future<void> _playPcmBuffer() async {
    if ( _pcmBuffer.isEmpty ) {
      // Defensive: no audio arrived but the WebSocket sent complete. Still signal complete so the orchestrator advances its FIFO.
      _completeCtrl.add( const TtsCompleteEvent() );
      return;
    }
    final wav = _wrapPcm24kAsWav( Uint8List.fromList( _pcmBuffer ) );
    _pcmBuffer.clear();
    _isPlaying = true;

    final myCompleter = Completer<void>();
    _activePlaybackCompleter = myCompleter;

    try {
      await _player.play( wav );
      // Wait for the onComplete listener (in the constructor) to complete `myCompleter` after audio finishes.
      // Without this gate, TtsCompleteEvent would fire during playback, the orchestrator would start the next
      // utterance and preempt the current one mid-sentence.
      await myCompleter.future;
      // Identity check: if `stop()` ran while we were awaiting, it cleared
      // the field (or a later speak replaced it). Only emit complete if
      // we're still the active utterance.
      if ( identical( _activePlaybackCompleter, myCompleter ) ) {
        _activePlaybackCompleter = null;
        _isPlaying               = false;
        _completeCtrl.add( const TtsCompleteEvent() );
      }
    } catch ( e ) {
      if ( identical( _activePlaybackCompleter, myCompleter ) ) {
        _activePlaybackCompleter = null;
      }
      _isPlaying = false;
      _errorCtrl.add( TtsErrorEvent( errorCode: 'playback_failed', message: e.toString() ) );
    }
  }

  /// Wraps raw 16-bit mono 24 kHz PCM in a minimal WAV header so `audioplayers` can decode it.
  ///
  /// ElevenLabs `output_format=pcm_24000` returns exactly this shape.
  Uint8List _wrapPcm24kAsWav( Uint8List pcm ) {
    const sampleRate  = 24000;
    const channels    = 1;
    const bitsPerSample = 16;
    final byteRate    = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign  = channels * bitsPerSample ~/ 8;
    final dataLen     = pcm.length;
    final totalLen    = 36 + dataLen;

    final header = BytesBuilder();
    // RIFF header
    header.add( 'RIFF'.codeUnits );
    header.add( _u32le( totalLen ) );
    header.add( 'WAVE'.codeUnits );
    // fmt chunk
    header.add( 'fmt '.codeUnits );
    header.add( _u32le( 16 ) );      // fmt chunk size
    header.add( _u16le( 1 ) );       // PCM format
    header.add( _u16le( channels ) );
    header.add( _u32le( sampleRate ) );
    header.add( _u32le( byteRate ) );
    header.add( _u16le( blockAlign ) );
    header.add( _u16le( bitsPerSample ) );
    // data chunk
    header.add( 'data'.codeUnits );
    header.add( _u32le( dataLen ) );
    header.add( pcm );

    return header.toBytes();
  }

  List<int> _u16le( int v ) => [ v & 0xff, ( v >> 8 ) & 0xff ];
  List<int> _u32le( int v ) => [
    v & 0xff,
    ( v >> 8  ) & 0xff,
    ( v >> 16 ) & 0xff,
    ( v >> 24 ) & 0xff,
  ];

  /// Cancels the player subscription and closes the player and all three streams.
  Future<void> dispose() async {
    await _playerCompleteSub?.cancel();
    await _player.dispose();
    await _statusCtrl.close();
    await _completeCtrl.close();
    await _errorCtrl.close();
  }
}

/// Non-terminal status event: `loading` or `streaming`.
///
/// `loading` means the backend received the request and the ElevenLabs handshake is in progress. `streaming`
/// means audio chunks are flowing.
class TtsStatusEvent {
  /// `loading` or `streaming`; `unknown` when the payload has none.
  final String  status;
  /// The text being synthesized, when the backend sends it.
  final String? detail;
  /// Creates a status event.
  const TtsStatusEvent( { required this.status, this.detail } );
}

/// Terminal event: the TTS stream finished cleanly.
class TtsCompleteEvent {
  /// Creates the event.
  const TtsCompleteEvent();
}

/// Terminal event: the TTS stream failed.
///
/// `errorCode` is one of the backend's codes `quota_exceeded`, `rate_limit`, `auth_error` or `unknown`,
/// or `playback_failed`, which is raised on the client.
class TtsErrorEvent {
  /// Machine-readable cause; see the class doc for the values.
  final String  errorCode;
  /// Human-readable detail, or null.
  final String? message;
  /// Creates an error event.
  const TtsErrorEvent( { required this.errorCode, this.message } );
}
