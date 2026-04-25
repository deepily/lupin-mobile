import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/constants/app_constants.dart';

/// Test seam — wraps the methods of `audioplayers.AudioPlayer` we use so
/// that `StreamingTtsPlayer` can be unit-tested without the platform
/// channels `audioplayers` requires. Production uses
/// [_RealStreamingTtsAudioPlayer]; tests pass a Mocktail implementation.
abstract class StreamingTtsAudioPlayer {
  Stream<void> get onComplete;
  Future<void> play( Uint8List wavBytes );
  Future<void> stop();
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
/// Purpose-built alternative to the legacy `EnhancedTTSService` (which
/// remains tree-shaken on disk with 2.7K lines of adaptive-strategy
/// infrastructure we don't need yet). This player:
///
///   1. Sends `speak(text)` requests to the backend `/api/get-speech-elevenlabs`
///      endpoint via the shared Dio (auth interceptor injects Bearer token).
///   2. Consumes WS events fed in by the top-level dispatcher
///      (`app.dart _dispatchWsEvent`) — status updates, binary audio
///      chunks, completion and error signals.
///   3. Plays audio via `audioplayers` as a single PCM blob once the stream
///      completes. (Streaming-while-receiving is a later optimization; for
///      now we accumulate and play — ElevenLabs Flash latency + ~1-2s
///      text lengths make this imperceptible.)
///
/// The `TtsCompleteEvent` broadcast fires ONLY after audio playback has
/// actually finished (not when the WS stream signals done). The
/// `TtsOrchestrator` treats complete as "safe to advance FIFO" — firing
/// it before playback ends causes the next utterance's `play()` call to
/// preempt the current one mid-sentence (audioplayers is a single voice).
///
/// Event contract (matches backend `src/cosa/rest/routers/speech.py`):
///   - `audio_streaming_status`  — `{status: "loading"|"streaming", text}`
///   - `audio_streaming_chunk`   — binary PCM (wrapped by WebSocketService
///                                 into `{type, data: List<int>}`)
///   - `audio_streaming_complete` — `{status: "success", text}`
///   - `tts_error`               — `{error_code: "quota_exceeded"|...,
///                                   text, details}`
class StreamingTtsPlayer {
  final Dio                      _dio;
  final StreamingTtsAudioPlayer  _player;

  /// Dev-only: when true, `speak()` includes `debug_simulate_error: true`
  /// in the POST body. Backend (`/api/get-speech-elevenlabs`) sees the flag
  /// and emits a `tts_error` WS event with `error_code=quota_exceeded`
  /// instead of calling ElevenLabs. Used to verify the orchestrator's
  /// quota-fallback path on-device without needing an exhausted account.
  /// Sourced from the `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define and
  /// gated on `kDebugMode`; forced off in release builds.
  final bool _simulateTtsError;

  final StreamController<TtsStatusEvent>   _statusCtrl   = StreamController.broadcast();
  final StreamController<TtsCompleteEvent> _completeCtrl = StreamController.broadcast();
  final StreamController<TtsErrorEvent>    _errorCtrl    = StreamController.broadcast();

  StreamSubscription<void>? _playerCompleteSub;

  final List<int> _pcmBuffer = [];
  bool            _isActive            = false;  // true between speak() send and complete/error
  bool            _isPlaying           = false;  // true while audio is actually playing
  Completer<void>? _activePlaybackCompleter;     // signals end of current playback

  /// Tests pass [simulateTtsError] explicitly; production reads the
  /// `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define and requires `kDebugMode`.
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

  Stream<TtsStatusEvent>   get statusStream   => _statusCtrl.stream;
  Stream<TtsCompleteEvent> get completeStream => _completeCtrl.stream;
  Stream<TtsErrorEvent>    get errorStream    => _errorCtrl.stream;

  /// True while either (a) we've sent a speak request and haven't seen
  /// completion/error yet, OR (b) audio is actively playing out of the
  /// player. The orchestrator uses this to decide when to advance the
  /// FIFO queue.
  bool get isPlaying => _isActive || _isPlaying;

  /// Send a TTS request. Returns when the HTTP POST is acknowledged
  /// (backend will then start streaming audio chunks on the WS). Throws
  /// [DioException] on HTTP failure — caller (orchestrator) decides
  /// whether to fall back.
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

  /// Stop any in-flight playback and clear buffered audio. Called by the
  /// orchestrator's urgent-preempt path. A stopped utterance does NOT
  /// fire `TtsCompleteEvent` — the caller invoked this precisely to
  /// abandon it, so advancing the FIFO on its behalf would be wrong.
  Future<void> stop() async {
    _isActive = false;
    _pcmBuffer.clear();
    // Clear the field BEFORE awakening the hung completer; the identity
    // check inside `_playPcmBuffer` will then see the field is no longer
    // its completer and skip the complete emission.
    final stale = _activePlaybackCompleter;
    _activePlaybackCompleter = null;
    await _player.stop();
    _isPlaying = false;
    if ( stale != null && !stale.isCompleted ) stale.complete();
  }

  /// Called by `app.dart _dispatchWsEvent` when any of the four relevant
  /// event types arrive. Consumer does NOT need to type-check — the
  /// player filters by [type] internally.
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
        // Play the accumulated PCM buffer. Backend sends PCM 24kHz; wrap
        // a minimal WAV header so audioplayers can interpret it.
        // `_playPcmBuffer` fires `_completeCtrl` itself AFTER playback
        // actually finishes — firing here would advance the orchestrator's
        // FIFO while audio was still playing, causing overlap.
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
      // Defensive: no audio arrived but we got WS complete. Still signal
      // complete so the orchestrator advances its FIFO.
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
      // Wait for the onComplete listener (in the constructor) to fire
      // `myCompleter.complete()` after audio actually finishes. Without
      // this gate, TtsCompleteEvent would fire while audio was still
      // playing, causing the orchestrator to start the next utterance
      // and preempt the current one mid-sentence.
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

  /// Wrap raw 16-bit mono PCM at 24kHz with a minimal RIFF/WAVE header
  /// so `audioplayers` can decode it. ElevenLabs `output_format=pcm_24000`
  /// returns exactly this shape.
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

  Future<void> dispose() async {
    await _playerCompleteSub?.cancel();
    await _player.dispose();
    await _statusCtrl.close();
    await _completeCtrl.close();
    await _errorCtrl.close();
  }
}

/// Status event — either 'loading' (TTS request received by backend,
/// ElevenLabs handshake in progress) or 'streaming' (audio chunks are
/// flowing). Non-terminal.
class TtsStatusEvent {
  final String  status;
  final String? detail;
  const TtsStatusEvent( { required this.status, this.detail } );
}

/// Terminal event — TTS stream finished cleanly.
class TtsCompleteEvent {
  const TtsCompleteEvent();
}

/// Terminal event — TTS stream failed. `errorCode` is one of the backend's
/// documented codes: `quota_exceeded`, `rate_limit`, `auth_error`,
/// `unknown`, or `playback_failed` (client-side).
class TtsErrorEvent {
  final String  errorCode;
  final String? message;
  const TtsErrorEvent( { required this.errorCode, this.message } );
}
