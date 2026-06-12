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
/// Two entry points feed the queue (F-S1-1, USER-RULED 2026-06-12):
///   - [enqueueIfSpeakable] — LEGACY gated path (priority policy below).
///     Unchanged for parity; its urgent branch is pause-EXEMPT by design
///     (F-S1-S2-2).
///   - [enqueueAlways] — focus-surface UNGATED path: every notification
///     enqueues and speaks regardless of priority or mute prefs (Q6).
///     `FocusChatBloc` is the sole production caller (sole TTS dispatcher;
///     legacy dispatch is withdrawn at the DI seam, not here).
///
/// Priority policy (LEGACY path only, aligned to Lupin web client
/// `notifications.js:5421`):
///   - `low`    / `medium` → never spoken
///   - `high`   → spoken iff `prefs.speakOnHigh`
///   - `urgent` → spoken iff `prefs.speakOnUrgent`;
///                preempts any current utterance, flushes pending queue
///
/// Pause/hold semantics (Q6 + OSQ-5, cascade-ratified 2026-06-12):
///   - [pause] is a HOLD, not a mute: nothing is dropped; the in-flight
///     utterance finishes naturally (utterance-boundary — never cut
///     mid-sentence); arrivals keep accumulating.
///   - [resume] drains the accumulated queue in arrival order.
///   - Pause gates ONLY the focus path and legacy non-urgent dispatch;
///     the legacy urgent branch dispatches directly and is pause-exempt.
///
/// Fallback policy:
///   - Default path: `StreamingTtsPlayer` (ElevenLabs).
///   - On `tts_error` with `error_code == "quota_exceeded"`, disable
///     ElevenLabs for 5 minutes; speak the current utterance and any
///     subsequent ones via `NotificationAudioService.flutterTtsSpeak(text)`.
///     After the window, retry ElevenLabs on the next utterance. The
///     window clock is orthogonal to pause: pausing does not stop it, and
///     resumed utterances route per whatever the window says at dequeue.
class TtsOrchestrator {
  final StreamingTtsPlayer        _player;
  final NotificationAudioService  _fallback;
  final NotificationPreferences   _prefs;
  final WebSocketService          _ws;

  final Queue<_Utterance> _fifo    = Queue();
  _Utterance?             _current;
  DateTime?               _elevenLabsDisabledUntil;

  bool _paused = false;

  /// Utterance-epoch re-entry guard (F-S1-S3-1): incremented on every
  /// dispatch and every preempt-stop; the completion/error handlers no-op
  /// when the epoch they were armed under is stale. The real
  /// `StreamingTtsPlayer.stop()` emits NOTHING on `completeStream`
  /// (documented contract `streaming_tts_player.dart:162-165`; enforced by
  /// the completer-identity mechanism `:169-176` + `:242-249`), so no
  /// completion-driven double-advance exists at parity — this guard is
  /// robustness against future player changes.
  int _epoch         = 0;
  int _inFlightEpoch = 0;

  final StreamController<bool> _pausedCtrl = StreamController<bool>.broadcast();
  final StreamController<int>  _depthCtrl  = StreamController<int>.broadcast();

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

  /// True while the queue is held (Q6 pause toggle). Synchronous read;
  /// UI listens on [pausedStream] for changes.
  bool get isPaused => _paused;

  /// Emits on every pause-state TRANSITION (idempotent [pause]/[resume]
  /// calls do not re-emit). S3's hold toggle renders reactively off this.
  Stream<bool> get pausedStream => _pausedCtrl.stream;

  /// Emits the new depth on EVERY enqueue and dequeue (and on the
  /// destructive clears: legacy urgent flush, [stopAll]) — the live
  /// held-count signal for S3's paused banner (F-S1-S2-3). The
  /// synchronous [queueDepth] getter stays for one-shot reads.
  Stream<int> get queueDepthStream => _depthCtrl.stream;

  /// HOLD the queue (Q6; OSQ-5 utterance-boundary semantics): the
  /// in-flight utterance finishes naturally — never cut mid-sentence —
  /// and nothing further dequeues until [resume]. Not a mute: arrivals
  /// keep accumulating.
  void pause() {
    if ( _paused ) return;
    _paused = true;
    _pausedCtrl.add( true );
  }

  /// Clear the hold and drain the accumulated queue in arrival order.
  void resume() {
    if ( !_paused ) return;
    _paused = false;
    _pausedCtrl.add( false );
    _tryStartNext();
  }

  /// Hot path — called by `NotificationBloc._onExternalUpdate` on every
  /// incoming notification. Gate, enqueue, dispatch if idle.
  ///
  /// LEGACY gated path — unchanged for parity (F-S1-1: the focus surface
  /// uses [enqueueAlways]; this path's production dispatch is withdrawn
  /// at the DI seam, the gates here stay verbatim). Its urgent branch
  /// routes through `_preemptForUrgent()`, which dispatches DIRECTLY and
  /// never passes the `_tryStartNext()` pause gate — the legacy path is
  /// pause-EXEMPT BY DESIGN (F-S1-S2-2); its non-urgent dispatch-if-idle
  /// step parks under pause like any other `_tryStartNext()` caller.
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
      _emitQueueDepth();
      if ( _current == null ) _tryStartNext();
    }
  }

  /// Focus-surface UNGATED entry point (F-S1-1, USER-RULED "ungated path
  /// + sole dispatcher"): bypasses BOTH `masterMute` and the priority
  /// gate — every notification enqueues and speaks (Q6). `FocusChatBloc`
  /// calls this for EVERY inbound notification.
  ///
  /// Urgent semantics on this path (all non-destructive — nothing is
  /// ever dropped):
  ///   - urgent while PAUSED (F-S1-S2-1a): NO audio preempt — pause is
  ///     absolute (OSQ-5); the urgent inserts behind any leading urgents
  ///     so the urgent block stays arrival-ordered ahead of non-urgents.
  ///   - urgent while UNPAUSED over a NON-urgent (F-S1-2): non-destructive
  ///     preempt — current playback stops, the interrupted utterance
  ///     re-queues immediately behind the urgent and REPLAYS FROM THE
  ///     START on its next turn.
  ///   - urgent while UNPAUSED over an URGENT (F-S1-S2-1b): no preempt —
  ///     the newcomer queues behind earlier urgents and plays when the
  ///     in-flight one finishes.
  void enqueueAlways( {
    required String priority,
    required String message,
    String?         title,
    String?         voiceId,
  } ) {
    final utter = _Utterance(
      priority : priority,
      text     : _formatSpeech( title: title, message: message ),
      voiceId  : voiceId,
    );

    if ( priority == 'urgent' ) {
      final current = _current;
      if ( !_paused && current != null && current.priority != 'urgent' ) {
        _preemptNonDestructive( utter );
        return;
      }
      // Paused, idle, or the in-flight utterance is itself urgent: queue
      // into the arrival-ordered urgent block at the front.
      _insertBehindLeadingUrgents( utter );
      if ( _current == null ) _tryStartNext();
    } else {
      _fifo.add( utter );
      _emitQueueDepth();
      if ( _current == null ) _tryStartNext();
    }
  }

  /// User-invoked cancel (e.g. from a future "stop speaking" button).
  /// The only DESTRUCTIVE queue control (Q6: pause never drops).
  Future<void> stopAll() async {
    ++_epoch;   // stale-guard any in-flight completion/error events
    _fifo.clear();
    _emitQueueDepth();
    _current = null;
    await _player.stop();
    await _fallback.stopFallbackSpeech();
  }

  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _errorSub?.cancel();
    await _pausedCtrl.close();
    await _depthCtrl.close();
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

  void _emitQueueDepth() {
    if ( !_depthCtrl.isClosed ) _depthCtrl.add( _fifo.length );
  }

  /// Insert [utter] behind the contiguous block of urgents at the queue
  /// front, keeping the urgent block arrival-ordered ahead of non-urgents
  /// (F-S1-S2-1a — no `addFirst` LIFO inversion).
  void _insertBehindLeadingUrgents( _Utterance utter ) {
    final items    = _fifo.toList();
    var   insertAt = 0;
    while ( insertAt < items.length && items[ insertAt ].priority == 'urgent' ) {
      insertAt++;
    }
    items.insert( insertAt, utter );
    _fifo
      ..clear()
      ..addAll( items );
    _emitQueueDepth();
  }

  /// LEGACY urgent preempt — DESTRUCTIVE flush, verbatim parity pinned by
  /// AC-S1.9: pending queue cleared, current playback stopped, urgent
  /// dispatched immediately. Dispatches DIRECTLY (never passes the
  /// `_tryStartNext()` pause gate) — pause-EXEMPT BY DESIGN (F-S1-S2-2).
  Future<void> _preemptForUrgent( _Utterance urgent ) async {
    ++_epoch;   // preempt-stop: stale-guard the stopped utterance's events
    _fifo.clear();
    _emitQueueDepth();
    await _player.stop();
    await _fallback.stopFallbackSpeech();
    _current = urgent;
    await _dispatchCurrent();
  }

  /// Focus-path urgent preempt (F-S1-2) — NON-destructive: stop current
  /// playback, re-queue the interrupted utterance at the queue front
  /// (immediately behind the urgent), dispatch the urgent. The interrupted
  /// utterance REPLAYS FROM THE START on its next turn —
  /// `StreamingTtsPlayer` exposes no mid-utterance position, so
  /// utterance-level replay is the only implementable granularity (OSQ-5).
  Future<void> _preemptNonDestructive( _Utterance urgent ) async {
    final interrupted = _current;
    ++_epoch;   // preempt-stop: stale-guard the stopped utterance's events
    // Claim the slot BEFORE the awaits (F-S1-IMPL-1): an enqueue arriving
    // during the stop() window must see a busy orchestrator — a nulled
    // `_current` here would let it idle-dispatch the queue head and break
    // one-voice-at-a-time with a second concurrent speak.
    _current = urgent;
    await _player.stop();
    await _fallback.stopFallbackSpeech();
    if ( interrupted != null ) {
      _fifo.addFirst( interrupted );
      _emitQueueDepth();
    }
    await _dispatchCurrent();
  }

  Future<void> _tryStartNext() async {
    // Pause gate (F-S1-4): the single choke point — covers utterance
    // completion, error continuation, and the dispatch-if-idle step in
    // both enqueue entry points.
    if ( _paused ) return;
    if ( _current != null ) return;
    if ( _fifo.isEmpty ) return;
    _current = _fifo.removeFirst();
    _emitQueueDepth();
    await _dispatchCurrent();
  }

  Future<void> _dispatchCurrent() async {
    final utter = _current;
    if ( utter == null ) return;

    _inFlightEpoch = ++_epoch;   // arm the completion/error handlers (F-S1-S3-1)

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
    if ( _inFlightEpoch != _epoch ) return;   // stale event (F-S1-S3-1)

    final wasCurrent = _current;
    _current = null;

    if ( event.errorCode == 'quota_exceeded' ) {
      _elevenLabsDisabledUntil = DateTime.now().add( _quotaFallbackWindow );
      // Re-speak the current utterance via fallback, then continue.
      // (Under pause this re-speak still runs — it is the in-flight
      // utterance finishing, OSQ-5; the continuation then parks at the
      // `_tryStartNext()` gate.)
      if ( wasCurrent != null ) {
        _speakViaFallback( wasCurrent.text ).then( ( _ ) => _tryStartNext() );
        return;
      }
    }
    // Any other error: skip this utterance, continue queue (parks at the
    // pause gate when held — AC-S1.10).
    _tryStartNext();
  }

  void _onUtteranceFinished() {
    if ( _inFlightEpoch != _epoch ) return;   // stale event (F-S1-S3-1)
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
