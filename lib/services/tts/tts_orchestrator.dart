import 'dart:async';
import 'dart:collection';

import '../notification_audio/notification_audio_service.dart';
import '../notification_audio/notification_preferences.dart';
import '../websocket/websocket_service.dart';
import 'streaming_tts_player.dart';

/// FIFO queue + priority gate + urgent-preempt + quota-fallback in front
/// of the TTS pipeline. One instance holds all in-flight + pending
/// utterances and serializes them so only one voice ever plays at a time.
///
/// Priority policy (aligned to Lupin web client `notifications.js:5421`):
///   - `low`    / `medium` → never spoken
///   - `high`   → spoken iff `prefs.speakOnHigh`
///   - `urgent` → spoken iff `prefs.speakOnUrgent`;
///                preempts any current utterance, flushes pending queue
///
/// Fallback policy:
///   - Default path: `StreamingTtsPlayer` (ElevenLabs).
///   - On `tts_error` with `error_code == "quota_exceeded"`, disable
///     ElevenLabs for 5 minutes; speak the current utterance and any
///     subsequent ones via `NotificationAudioService.flutterTtsSpeak(text)`.
///     After the window, retry ElevenLabs on the next utterance.
class TtsOrchestrator {
  final StreamingTtsPlayer        _player;
  final NotificationAudioService  _fallback;
  final NotificationPreferences   _prefs;
  final WebSocketService          _ws;

  final Queue<_Utterance> _fifo    = Queue();
  _Utterance?             _current;
  DateTime?               _elevenLabsDisabledUntil;

  static const _quotaFallbackWindow = Duration( minutes: 5 );

  StreamSubscription<TtsCompleteEvent>? _completeSub;
  StreamSubscription<TtsErrorEvent>?    _errorSub;

  TtsOrchestrator( {
    required StreamingTtsPlayer       player,
    required NotificationAudioService fallback,
    required NotificationPreferences  prefs,
    required WebSocketService         ws,
  } ) : _player   = player,
       _fallback  = fallback,
       _prefs     = prefs,
       _ws        = ws {
    _completeSub = _player.completeStream.listen( ( _ )  => _onUtteranceFinished() );
    _errorSub    = _player.errorStream   .listen( _onElevenLabsError );
  }

  /// True when either an utterance is in-flight (sent to backend, audio
  /// pending) OR audio is actively playing OR a fallback `flutter_tts`
  /// speak is in progress. Callers use this to suppress other speech.
  bool get isPlaying => _current != null || _player.isPlaying;

  int get queueDepth => _fifo.length;

  /// Hot path — called by `NotificationBloc._onExternalUpdate` on every
  /// incoming notification. Gate, enqueue, dispatch if idle.
  ///
  /// [suppressDing] mirrors the web client: it silences the ding only,
  /// NOT the speech (see notifications.js:5408). So we ignore it here.
  ///
  /// [voiceId] is the per-session persona voice ID that routes through
  /// `StreamingTtsPlayer.speak()` to the backend `voice_id` body key (per
  /// `Q3` of the voice-persona milestone). Bloc passes
  /// `notification.voicePersona?.voiceId`; null routes to the server's
  /// default Sam voice. NOT piped through to `flutter_tts` fallback per
  /// `Q4` (different voice space — see [_speakViaFallback] comment).
  void enqueueIfSpeakable( {
    required String priority,
    required String message,
    String?         title,
    String?         voiceId,
  } ) {
    if ( _prefs.masterMute ) return;
    if ( !_isSpeakable( priority ) ) return;

    final utter = _Utterance(
      priority : priority,
      text     : _formatSpeech( title: title, message: message ),
      voiceId  : voiceId,
    );

    if ( priority == 'urgent' ) {
      _preemptForUrgent( utter );
    } else {
      _fifo.add( utter );
      if ( _current == null ) _tryStartNext();
    }
  }

  /// User-invoked cancel (e.g. from a future "stop speaking" button).
  Future<void> stopAll() async {
    _fifo.clear();
    _current = null;
    await _player.stop();
    await _fallback.stopFallbackSpeech();
  }

  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _errorSub?.cancel();
  }

  // ---------- private ----------

  bool _isSpeakable( String priority ) {
    switch ( priority ) {
      case 'high'   : return _prefs.speakOnHigh;
      case 'urgent' : return _prefs.speakOnUrgent;
      default       : return false;
    }
  }

  String _formatSpeech( { required String message, String? title } ) {
    if ( title != null && title.isNotEmpty ) return '$title. $message';
    return message;
  }

  Future<void> _preemptForUrgent( _Utterance urgent ) async {
    _fifo.clear();
    await _player.stop();
    await _fallback.stopFallbackSpeech();
    _current = urgent;
    await _dispatchCurrent();
  }

  Future<void> _tryStartNext() async {
    if ( _current != null ) return;
    if ( _fifo.isEmpty ) return;
    _current = _fifo.removeFirst();
    await _dispatchCurrent();
  }

  Future<void> _dispatchCurrent() async {
    final utter = _current;
    if ( utter == null ) return;

    final sessionId = _ws.sessionId;
    if ( sessionId == null ) {
      // WS not connected — can't do ElevenLabs. Fall back silently for
      // THIS utterance only (don't enter the 5-min quota window).
      await _speakViaFallback( utter.text );
      _onUtteranceFinished();
      return;
    }

    if ( _isElevenLabsInFallbackWindow() ) {
      await _speakViaFallback( utter.text );
      _onUtteranceFinished();
      return;
    }

    try {
      await _player.speak(
        text      : utter.text,
        sessionId : sessionId,
        voiceId   : utter.voiceId,
      );
      // Audio events (status / chunk / complete / error) arrive via WS
      // and drive `_onUtteranceFinished` or `_onElevenLabsError`.
    } catch ( _ ) {
      // Network/HTTP failure on POST — fall back for THIS utterance, do
      // not enter the 5-min quota window (this isn't a quota issue).
      await _speakViaFallback( utter.text );
      _onUtteranceFinished();
    }
  }

  Future<void> _speakViaFallback( String text ) async {
    // INTENTIONAL: `voiceId` is NOT piped through to the `flutter_tts`
    // fallback per `Q4` (FROZEN 2026-05-06 — see
    // `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/03-decisions.md`).
    // ElevenLabs voice IDs (`pNInz6obpgDQGcFmaJgB` etc) live in a different
    // voice space than the on-device `flutter_tts` engine voices; mapping
    // would require a translation table that doesn't exist and isn't part
    // of this milestone. Fallback uses the device default voice — the
    // narration still happens, just without the per-session persona match.
    // Future maintainer: if you're tempted to "fix" this by passing
    // `voiceId` here, please check the milestone docs first.
    await _fallback.flutterTtsSpeak( text );
  }

  bool _isElevenLabsInFallbackWindow() {
    final until = _elevenLabsDisabledUntil;
    if ( until == null ) return false;
    if ( DateTime.now().isAfter( until ) ) {
      _elevenLabsDisabledUntil = null;
      return false;
    }
    return true;
  }

  void _onElevenLabsError( TtsErrorEvent event ) {
    final wasCurrent = _current;
    _current = null;

    if ( event.errorCode == 'quota_exceeded' ) {
      _elevenLabsDisabledUntil = DateTime.now().add( _quotaFallbackWindow );
      // Re-speak the current utterance via fallback, then continue.
      if ( wasCurrent != null ) {
        _speakViaFallback( wasCurrent.text ).then( ( _ ) => _tryStartNext() );
        return;
      }
    }
    // Any other error: skip this utterance, continue queue.
    _tryStartNext();
  }

  void _onUtteranceFinished() {
    _current = null;
    _tryStartNext();
  }
}

class _Utterance {
  final String  priority;
  final String  text;
  final String? voiceId;
  const _Utterance( {
    required this.priority,
    required this.text,
    this.voiceId,
  } );
}
