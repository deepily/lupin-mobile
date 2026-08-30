import 'dart:async';
import 'dart:collection';

import '../notification_audio/notification_audio_service.dart';
import '../notification_audio/notification_preferences.dart';
import '../notification_filter/notification_stop_list.dart';
import 'tts_preview_truncator.dart';
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
  /// User stop-list (plan 2026.08.21 §3): a matched message is MUTED on
  /// BOTH entry points — including the ungated focus path — because a
  /// checked pattern means "hide AND mute". Null ⇒ no filtering.
  final NotificationStopList?     _stopList;

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
  final StreamController<TtsSuppression> _suppressedCtrl =
      StreamController<TtsSuppression>.broadcast();
  final StreamController<int>  _depthCtrl  = StreamController<int>.broadcast();
  final StreamController<List<TtsQueueItem>> _queueCtrl = StreamController<List<TtsQueueItem>>.broadcast();

  static const _quotaFallbackWindow = Duration( minutes: 5 );

  StreamSubscription<TtsCompleteEvent>? _completeSub;
  StreamSubscription<TtsErrorEvent>?    _errorSub;

  TtsOrchestrator( {
    required StreamingTtsPlayer       player,
    required NotificationAudioService fallback,
    required NotificationPreferences  prefs,
    required WebSocketService         ws,
    NotificationStopList?             stopList,
  } ) : _player   = player,
       _fallback  = fallback,
       _prefs     = prefs,
       _ws        = ws,
       _stopList  = stopList {
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

  /// Emits whenever the stop-list (gate 1) suppresses an item on the
  /// [enqueueAlways] path — AC-S3.7. **The point is that suppression is
  /// OBSERVABLE**: an early `return` with no signal is indistinguishable
  /// from a hang, and for a `response_requested` question the server is
  /// blocked while the user hears nothing and is shown nothing.
  ///
  /// Carries the matched rule so a caller can name it, and enough of the
  /// original call to re-issue it via [speakAnyway] on one tap. The UI
  /// claims live where a widget test can see them (AC-S4.14 / AC-S4.15);
  /// this stream is the seam between the two halves.
  ///
  /// NOT emitted on the legacy [enqueueIfSpeakable] path: AC-S3.3 pins
  /// that path byte-identical, its production dispatch is withdrawn at
  /// the DI seam, and no answer or question the user must act on arrives
  /// through it.
  Stream<TtsSuppression> get suppressedStream => _suppressedCtrl.stream;

  /// Emits the new depth on EVERY enqueue and dequeue (and on the
  /// destructive clears: legacy urgent flush, [stopAll]) — the live
  /// held-count signal for S3's paused banner (F-S1-S2-3). The
  /// synchronous [queueDepth] getter stays for one-shot reads.
  Stream<int> get queueDepthStream => _depthCtrl.stream;

  /// Queue viewer feed (Rick 2026-08-21, web `#tts-queue-section` parity):
  /// the in-flight utterance first (flagged), then pending in play order.
  /// Emits on every change (enqueue, dequeue, clear, skip, current change).
  Stream<List<TtsQueueItem>> get queueStream => _queueCtrl.stream;

  /// One-shot read of what [queueStream] would emit now.
  List<TtsQueueItem> get queueSnapshot => [
    if ( _current != null ) _current!.toItem( isCurrent: true ),
    ..._fifo.map( ( u ) => u.toItem( isCurrent: false ) ),
  ];

  /// Viewer "skip": stop the in-flight utterance and advance (parks at the
  /// pause gate when held). No-op when nothing is playing. Destructive for
  /// THAT utterance only — the queue is untouched.
  Future<void> skipCurrent() async {
    if ( _current == null ) return;
    ++_epoch;   // stale-guard the stopped utterance's completion/error events
    _current = null;
    await _player.stop();
    await _fallback.stopFallbackSpeech();
    _emitQueue();
    await _tryStartNext();
  }

  /// Viewer "delete": drop one PENDING utterance by id. The in-flight one
  /// is not removable here — use [skipCurrent]. Returns whether it existed.
  bool removeQueued( int id ) {
    final before = _fifo.length;
    _fifo.removeWhere( ( u ) => u.id == id );
    final removed = _fifo.length != before;
    if ( removed ) _emitQueueDepth();
    return removed;
  }

  /// Viewer "clear queue": drop every PENDING utterance; the in-flight one
  /// finishes (use [stopAll] to cut it too).
  void clearQueued() {
    if ( _fifo.isEmpty ) return;
    _fifo.clear();
    _emitQueueDepth();
  }

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
    TtsSender?      sender,
  } ) {
    if ( _prefs.masterMute ) return;
    if ( _stopList?.matches( message ) ?? false ) return;   // stop-list: muted
    if ( _systemSenderMuted( sender ) ) return;             // Rick 2026-08-21
    if ( !_isSpeakable( priority ) ) return;

    final utter = _Utterance(
      priority : priority,
      text     : _formatSpeech( title: title, message: message ),
      voiceId  : voiceId,
      sender   : sender ?? const TtsSender(),
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
  /// [verbatim] (Rick's ruling 4, plan 2026.08.29 §6): the item is one the
  /// user is EXPECTED TO ACT ON — an answer they deliberately asked for,
  /// or a question something is blocked waiting on — so the two
  /// *preference* gates are overridden. It skips gate 2
  /// ([_systemSenderMuted], a class preference about persona-less chatter)
  /// and gate 3 ([_formatSpeech]'s fraction cut, a preview preference).
  ///
  /// 🔴 **`verbatim` does NOT bypass gate 1, the stop-list** (OSQ3, CLOSED
  /// by Rick 2026-08-29). Gates 2 and 3 are preferences about chatter the
  /// user did not ask for; the stop-list is a specific "never speak this"
  /// the user typed, and silently overriding it would be worse than the
  /// bug. Suppression is made VISIBLE instead — see [suppressedStream].
  /// Returns the [TtsSuppression] when gate 1 refused the item, else null.
  ///
  /// Same object the stream carries — one source, two deliveries: the
  /// stream is for OBSERVERS, this return is for the CALLER that caused
  /// it. A caller needs the object to offer speak-anyway later, and
  /// correlating a stream event back to the item that produced it means
  /// guessing on message text. Returning it removes the guess without
  /// putting state in the orchestrator.
  TtsSuppression? enqueueAlways( {
    required String priority,
    required String message,
    String?         title,
    String?         voiceId,
    TtsSender?      sender,
    bool            verbatim = false,
  } ) {
    // The ONLY gates on this path (F-S1-1 keeps it ungated by priority and
    // master-mute) are the user's explicit "never speak this" rulings: a
    // checked stop-list pattern, and — since 2026-08-21 — the
    // speak-system-senders switch (persona-less senders muted as a class).
    //
    // Gate 1 fires FIRST and is never bypassed; it reports instead of
    // returning silently (AC-S3.7).
    final rule = _stopList?.matchFor( message );
    if ( rule != null ) {
      final suppression = TtsSuppression(
        priority : priority,
        message  : message,
        title    : title,
        voiceId  : voiceId,
        sender   : sender ?? const TtsSender(),
        rule     : rule.pattern,
        verbatim : verbatim,
      );
      _emitSuppression( suppression );
      return suppression;
    }
    // Gate 2 — a preference; `verbatim` overrides it (ruling 4).
    if ( !verbatim && _systemSenderMuted( sender ) ) return null;

    _enqueueUngated(
      priority : priority,
      // Gate 3 — the fraction cut; `verbatim` overrides it (ruling 4).
      text     : _formatSpeech( title: title, message: message, verbatim: verbatim ),
      voiceId  : voiceId,
      sender   : sender,
    );
    return null;
  }

  /// The one-tap escape from a stop-list suppression (AC-S3.7 / AC-S4.14):
  /// speak [s] after all, exactly as it would have been spoken had no rule
  /// matched.
  ///
  /// Bypasses gates 1 AND 2 — this is an explicit user action on an item
  /// they can see, so re-applying either would drop it a second time with
  /// no signal, which is the very failure the notice exists to remove.
  /// Gate 3 is honored per the ORIGINAL call's [TtsSuppression.verbatim],
  /// so the preview-fraction preference still governs ordinary chatter the
  /// user chose to unmute.
  void speakAnyway( TtsSuppression s ) {
    _enqueueUngated(
      priority : s.priority,
      text     : _formatSpeech( title: s.title, message: s.message, verbatim: s.verbatim ),
      voiceId  : s.voiceId,
      sender   : s.sender,
    );
  }

  /// Replay an already-delivered utterance from the START (Rick's ruling 2;
  /// AC-S3.4 / AC-S3.4b / AC-S3.9).
  ///
  /// 🔴 **Replay implies RESUME, and that is the whole point.** An urgent
  /// enqueue only preempts when `!_paused` (see [enqueueAlways]); while
  /// held it falls through to the queue and [_tryStartNext]'s own pause
  /// gate, so a replay tapped while paused would enqueue and play
  /// NOTHING. Rick's gesture is *pause, then rewind* — exactly the
  /// sequence that is silent today — so [resume] is called first.
  ///
  /// ⚠️ [resume] is GLOBAL: replaying one answer un-holds everything the
  /// pause was holding, across every screen (AC-S3.9). Ratified and
  /// deliberate — one hold, one truth, and nothing was ever dropped, so
  /// the backlog drains rather than disappears.
  ///
  /// [sender] defaults to a NAMED sender so `isPersona` is true and the
  /// replay survives `speakSystemSenders` being off (AC-S3.4).
  void replay( {
    required String message,
    String?         title,
    String?         voiceId,
    TtsSender       sender = const TtsSender( name: 'Replay' ),
  } ) {
    resume();
    enqueueAlways(
      priority : 'urgent',
      message  : message,
      title    : title,
      voiceId  : voiceId,
      sender   : sender,
      verbatim : true,
    );
  }

  /// Shared enqueue tail for the ungated path: urgent-preempt semantics,
  /// else FIFO append, then dispatch if idle. Callers own the gates.
  void _enqueueUngated( {
    required String priority,
    required String text,
    String?         voiceId,
    TtsSender?      sender,
  } ) {
    final utter = _Utterance(
      priority : priority,
      text     : text,
      voiceId  : voiceId,
      sender   : sender ?? const TtsSender(),
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

  void _emitSuppression( TtsSuppression s ) {
    if ( !_suppressedCtrl.isClosed ) _suppressedCtrl.add( s );
  }

  /// User-invoked cancel (e.g. from a future "stop speaking" button).
  /// The only DESTRUCTIVE queue control (Q6: pause never drops).
  Future<void> stopAll() async {
    ++_epoch;   // stale-guard any in-flight completion/error events
    _fifo.clear();
    _emitQueueDepth();
    _current = null;
    _emitQueue();
    await _player.stop();
    await _fallback.stopFallbackSpeech();
  }

  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _errorSub?.cancel();
    await _pausedCtrl.close();
    await _depthCtrl.close();
    await _queueCtrl.close();
    await _suppressedCtrl.close();
  }

  // ---------- private ----------

  /// System-sender gate: a sender with NO persona is muted when the
  /// `speakSystemSenders` pref is off. Unknown sender (null) counts as
  /// system — the legacy path that passes nothing gets the same ruling.
  bool _systemSenderMuted( TtsSender? sender ) =>
      !_prefs.speakSystemSenders && !( sender?.isPersona ?? false );

  bool _isSpeakable( String priority ) {
    switch ( priority ) {
      case 'high'   : return _prefs.speakOnHigh;
      case 'urgent' : return _prefs.speakOnUrgent;
      default       : return false;
    }
  }

  /// Title is spoken whole (it is short); the MESSAGE is cut to the user's
  /// TTS preview fraction (`prefs.ttsFraction`, slider at the top of the
  /// focus pane -- web `#cc-tts-fraction-slider` parity, Rick 2026-08-21).
  /// Applied HERE, at enqueue time: the queue holds text, not audio, and the
  /// player synthesizes one utterance at a time when it reaches the head --
  /// so the cut is upstream of any TTS spend.
  ///
  /// [verbatim] skips the cut ONLY (ruling 4) — the title still leads, as
  /// it always has, because it was never the truncated part.
  String _formatSpeech( { required String message, String? title, bool verbatim = false } ) {
    final spoken = verbatim
        ? message
        : TtsPreviewTruncator.previewFor( message, _prefs.ttsFraction );
    if ( title != null && title.isNotEmpty ) return '$title. $spoken';
    return spoken;
  }

  void _emitQueueDepth() {
    if ( !_depthCtrl.isClosed ) _depthCtrl.add( _fifo.length );
    _emitQueue();
  }

  void _emitQueue() {
    if ( !_queueCtrl.isClosed ) _queueCtrl.add( queueSnapshot );
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
    _emitQueue();
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
    _emitQueue();
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
    _emitQueue();

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
    _emitQueue();
    _tryStartNext();
  }
}

/// Who a queued utterance comes from — for the queue viewer and the
/// system-sender gate (Rick 2026-08-21). `name`/`icon` come from the
/// voice persona; both null ⇒ a SYSTEM sender (no persona).
class TtsSender {
  final String? senderId;
  final String? name;
  final String? icon;
  const TtsSender( { this.senderId, this.name, this.icon } );

  bool get isPersona => ( name ?? '' ).isNotEmpty || ( icon ?? '' ).isNotEmpty;

  /// Short label for the viewer: persona name, else the sender-id local
  /// part before `@`/`#`, else "system".
  String get label {
    final n = ( name ?? '' ).trim();
    if ( n.isNotEmpty ) return n;
    final local = ( senderId ?? '' ).split( RegExp( r'[@#]' ) ).first.trim();
    return local.isEmpty ? 'system' : local;
  }
}

/// An item the stop-list (gate 1) refused to speak, reported rather than
/// dropped in silence (AC-S3.7).
///
/// Carries [rule] — the pattern that matched, so the UI can name it
/// ("not spoken — matches 'Done: Bash'") — plus enough of the original
/// call for [TtsOrchestrator.speakAnyway] to re-issue it verbatim on one
/// tap. It is a plain value: the orchestrator decides to suppress, the UI
/// decides how to show it, and neither knows the other's shape.
class TtsSuppression {
  final String    priority;
  final String    message;
  final String?   title;
  final String?   voiceId;
  final TtsSender sender;

  /// The matching stop-list pattern, verbatim as the user typed it.
  final String    rule;

  /// Whether the suppressed call had asked for [TtsOrchestrator]'s
  /// `verbatim` treatment — preserved so speak-anyway reproduces the
  /// original intent rather than guessing.
  final bool      verbatim;

  const TtsSuppression( {
    required this.priority,
    required this.message,
    required this.rule,
    this.title,
    this.voiceId,
    this.sender   = const TtsSender(),
    this.verbatim = false,
  } );
}

/// One row of the TTS queue viewer (web `#tts-queue-section` parity):
/// the in-flight utterance first (`isCurrent`), then the pending ones in
/// play order. `id` is the handle for [TtsOrchestrator.removeQueued].
class TtsQueueItem {
  final int       id;
  final String    priority;
  final String    text;
  final TtsSender sender;
  final bool      isCurrent;
  const TtsQueueItem( {
    required this.id,
    required this.priority,
    required this.text,
    required this.sender,
    required this.isCurrent,
  } );
}

class _Utterance {
  static int _nextId = 0;
  final int       id;
  final String    priority;
  final String    text;
  final String?   voiceId;
  final TtsSender sender;
  _Utterance( {
    required this.priority,
    required this.text,
    this.voiceId,
    this.sender = const TtsSender(),
  } ) : id = ++_nextId;

  TtsQueueItem toItem( { required bool isCurrent } ) => TtsQueueItem(
    id: id, priority: priority, text: text, sender: sender, isCurrent: isCurrent );
}
