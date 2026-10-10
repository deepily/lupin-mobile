import 'dart:async';
import 'dart:collection';

import '../../core/logging/logger.dart';
import '../notification_audio/notification_audio_service.dart';
import '../notification_audio/notification_preferences.dart';
import '../notification_filter/notification_stop_list.dart';
import 'tts_preview_truncator.dart';
import '../websocket/websocket_service.dart';
import 'streaming_tts_player.dart';

/// Serializes speech through a FIFO queue, so only one voice plays at a time.
///
/// It adds a priority gate, urgent preempt and quota fallback. Two entry points feed the queue:
///   - [enqueueIfSpeakable] is the legacy gated path, kept for parity; its urgent branch ignores pause.
///   - [enqueueAlways] is the focus-surface ungated path, used only by `FocusChatBloc`. It speaks every
///     notification whatever its priority or the mute preferences. Legacy dispatch is withdrawn at the DI seam.
/// The legacy priority policy follows the web client (`notifications.js:5421`):
///   - low and medium are never spoken
///   - high is spoken if `prefs.speakOnHigh`
///   - urgent is spoken if `prefs.speakOnUrgent`, and flushes the queue
/// [pause] is a hold, not a mute. Nothing is dropped, the in-flight utterance finishes and arrivals accumulate.
/// [resume] drains the queue in arrival order. Pause gates the focus path and legacy non-urgent dispatch only.
/// Fallback: `StreamingTtsPlayer` (ElevenLabs) by default. A `quota_exceeded` error disables it for 5 minutes.
/// Utterances then go to `NotificationAudioService.flutterTtsSpeak(text)`. The window ignores pause.
/// Design: src/docs/decisions/README.md (R-TTS-ungated-focus, R-TTS-pause-hold)
class TtsOrchestrator {
  final StreamingTtsPlayer        _player;
  final NotificationAudioService  _fallback;
  final NotificationPreferences   _prefs;
  final WebSocketService          _ws;
  /// User stop-list; null means no filtering.
  ///
  /// A matched message is muted on both entry points, including the ungated focus path, because a checked
  /// pattern means hide and mute.
  final NotificationStopList?     _stopList;

  /// How long an utterance may sit with no audio event before it is given up on and spoken on-device.
  ///
  /// It is counted from the speak acknowledgement and restarts on each routed event. It does not apply while audio
  /// is playing. Without it a lost completion event leaves [_current] set for good, and every later notification
  /// queues silently behind it.
  /// Design: src/docs/decisions/README.md (R-TTS-watchdog)
  final Duration                  _speakWatchdog;

  /// Default for [_speakWatchdog].
  static const Duration defaultSpeakWatchdog = Duration( seconds: 20 );

  Timer?    _watchdog;
  DateTime? _dispatchedAt;

  final Queue<_Utterance> _fifo    = Queue();
  _Utterance?             _current;
  DateTime?               _elevenLabsDisabledUntil;

  bool _paused = false;

  /// True while the microphone is recording.
  ///
  /// Kept apart from [_paused] because it is not the user's toggle: the mic releasing must never un-pause a
  /// hold the user set by hand.
  /// Design: src/docs/decisions/README.md (R-TTS-capture-hold)
  bool _captureHeld = false;

  /// Tail of the serialized hold-transition chain (see [setCaptureHold]).
  Future<void> _holdChain = Future<void>.value();

  /// Either hold stops anything new from starting.
  bool get _held => _paused || _captureHeld;

  /// Utterance-epoch re-entry guard, incremented on every dispatch and every preempt-stop.
  ///
  /// The completion and error handlers do nothing when the epoch they were armed under is stale.
  /// The real `StreamingTtsPlayer.stop()` emits nothing on `completeStream`, so no completion-driven
  /// double-advance exists today. The guard is robustness against future player changes.
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

  /// Creates an orchestrator and subscribes to the player's completion and error streams.
  TtsOrchestrator( {
    required StreamingTtsPlayer       player,
    required NotificationAudioService fallback,
    required NotificationPreferences  prefs,
    required WebSocketService         ws,
    NotificationStopList?             stopList,
    Duration                          speakWatchdog = defaultSpeakWatchdog,
  } ) : _speakWatchdog = speakWatchdog,
       _player   = player,
       _fallback  = fallback,
       _prefs     = prefs,
       _ws        = ws,
       _stopList  = stopList {
    _completeSub = _player.completeStream.listen( ( _ )  => _onUtteranceFinished() );
    _errorSub    = _player.errorStream   .listen( _onElevenLabsError );
  }

  /// True while an utterance is in flight, audio is playing or a fallback speak runs.
  ///
  /// The fallback is a `flutter_tts` speak. Callers use this to suppress other speech.
  bool get isPlaying => _current != null || _player.isPlaying;

  /// Number of pending utterances, not counting the in-flight one.
  int get queueDepth => _fifo.length;

  /// True while the queue is held by the user's pause toggle.
  ///
  /// A synchronous read; the UI listens on [pausedStream] for changes.
  bool get isPaused => _paused;

  /// Emits on every pause-state transition, and replays the current value on subscribe.
  ///
  /// Idempotent [pause] and [resume] calls do not re-emit. A plain broadcast controller tells a new listener
  /// nothing until the next transition. A control mounted while speech is already held would then show
  /// "not paused" over a held queue until somebody toggles. The hold is global and Quick Ask mounts its own controls, so
  /// arriving mid-hold is the ordinary case.
  /// Consumers also seed from the synchronous [isPaused] getter through `initialData`. Keep that.
  /// `initialData` paints the first frame and the replay lands one microtask later. Dropping it trades
  /// a silent wrong state for a one-frame flash.
  /// It mirrors `connectionStream` in `websocket_service.dart`, which has the same three properties. The two are
  /// the same shape and could share one helper, to be extracted by whoever next owns both files.
  Stream<bool> get pausedStream {
    late StreamController<bool> out;
    StreamSubscription<bool>?   sub;
    out = StreamController<bool>(
      onListen: () {
        // Replay, then follow, in one synchronous block, so no transition can slip between the two and be missed.
        out.add( _paused );
        sub = _pausedCtrl.stream.listen( out.add, onError: out.addError );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return out.stream;
  }

  /// Emits whenever the stop-list (gate 1) suppresses an item on the [enqueueAlways] path.
  ///
  /// Suppression is observable: an early return with no signal looks like a hang. For a `response_requested`
  /// question the server is blocked while the user hears and sees nothing. The event carries the matched rule,
  /// so a caller can name it. It also carries enough of the original call to re-issue it through [speakAnyway].
  /// It is not emitted on the legacy [enqueueIfSpeakable] path. That path is pinned byte-identical, its production
  /// dispatch is withdrawn at the DI seam, and nothing the user must act on arrives through it.
  Stream<TtsSuppression> get suppressedStream => _suppressedCtrl.stream;

  /// Emits the new queue depth on every enqueue and dequeue, and on the destructive clears.
  ///
  /// The destructive clears are the legacy urgent flush and [stopAll]. It is the live held-count signal for the
  /// paused banner. The synchronous [queueDepth] getter stays for one-shot reads.
  Stream<int> get queueDepthStream => _depthCtrl.stream;

  /// Queue viewer feed: the in-flight utterance first, flagged, then the pending ones.
  ///
  /// The order is play order, and it matches the web `#tts-queue-section`. It emits on every change:
  /// enqueue, dequeue, clear, skip and a change of the current utterance.
  Stream<List<TtsQueueItem>> get queueStream => _queueCtrl.stream;

  /// One-shot read of what [queueStream] would emit now.
  List<TtsQueueItem> get queueSnapshot => [
    if ( _current != null ) _current!.toItem( isCurrent: true ),
    ..._fifo.map( ( u ) => u.toItem( isCurrent: false ) ),
  ];

  /// Viewer skip: stops the in-flight utterance and advances.
  ///
  /// It parks at the pause gate when held, and does nothing when nothing is playing. It is destructive for
  /// that utterance only; the queue is untouched.
  Future<void> skipCurrent() async {
    if ( _current == null ) return;
    ++_epoch;   // stale-guard the stopped utterance's completion/error events
    _current = null;
    await _player.stop();
    await _fallback.stopFallbackSpeech();
    _emitQueue();
    await _tryStartNext();
  }

  /// Viewer delete: drops one pending utterance by [id] and returns whether it existed.
  ///
  /// The in-flight utterance is not removable here; use [skipCurrent].
  bool removeQueued( int id ) {
    final before = _fifo.length;
    _fifo.removeWhere( ( u ) => u.id == id );
    final removed = _fifo.length != before;
    if ( removed ) _emitQueueDepth();
    return removed;
  }

  /// Viewer clear queue: drops every pending utterance.
  ///
  /// The in-flight utterance finishes; use [stopAll] to cut it too.
  void clearQueued() {
    if ( _fifo.isEmpty ) return;
    _fifo.clear();
    _emitQueueDepth();
  }

  /// Holds the queue until [resume]; nothing further dequeues.
  ///
  /// The in-flight utterance finishes naturally and is never cut mid-sentence. This is not a mute:
  /// arrivals keep accumulating.
  void pause() {
    if ( _paused ) return;
    _paused = true;
    _pausedCtrl.add( true );
  }

  /// Holds speech while the microphone records, so notifications do not land in the recording.
  ///
  /// `AsrService`'s capture transitions call it, so every composer that records is covered.
  /// Taking the hold requeues a playing utterance at the head; releasing drains the queue in arrival order.
  /// Design: src/docs/decisions/README.md (R-TTS-capture-hold)
  ///
  /// Ensures:
  ///   - transitions are serialized: `AsrService` reports capture start and end synchronously and the production
  ///     callback cannot await, so a release could otherwise arrive while the hold it undoes is still awaiting
  ///     `_player.stop()`. Its `_tryStartNext()` would dispatch the requeued utterance and the late stop would
  ///     cut it. Chaining each transition onto the previous one closes that window for every caller
  ///   - releasing does not drain while the user's own [pause] is on, and nothing is dropped either way
  ///   - the flag moves synchronously, because `enqueueAlways` and `enqueueIfSpeakable` read it on the same turn
  ///   - the returned future carries any error from the transition; the chain itself never carries one forward
  Future<void> setCaptureHold( bool capturing ) {
    if ( capturing == _captureHeld ) return _holdChain;
    // The flag moves synchronously: `enqueueAlways` and `enqueueIfSpeakable` read it on the same turn as
    // the mic transition. Only the stop and drain side-effects queue up behind their predecessor.
    _captureHeld = capturing;
    final next   = _holdChain.then( ( _ ) => _applyCaptureHold( capturing ) );
    // The chain itself must never carry an error forward, or one failed transition would wedge every later
    // hold. The caller still sees it on `next`, and the production call site logs it.
    _holdChain   = next.catchError( ( Object _ ) {} );
    return next;
  }

  /// Serialized tail of [setCaptureHold]; never call it directly.
  Future<void> _applyCaptureHold( bool capturing ) async {
    if ( !capturing ) {
      await _tryStartNext();
      return;
    }
    final interrupted = _current;
    if ( interrupted == null ) return;
    ++_epoch;   // stale-guard the stopped utterance's completion/error events
    _current = null;
    _fifo.addFirst( interrupted );
    _emitQueueDepth();
    _emitQueue();
    await _player.stop();
    await _fallback.stopFallbackSpeech();
  }

  /// True while the microphone hold from [setCaptureHold] is on.
  bool get isCaptureHeld => _captureHeld;

  /// Clears the user's hold and drains the accumulated queue in arrival order.
  void resume() {
    if ( !_paused ) return;
    _paused = false;
    _pausedCtrl.add( false );
    _tryStartNext();
  }

  /// Legacy gated entry point: gates, enqueues and dispatches if idle.
  ///
  /// `NotificationBloc._onExternalUpdate` calls it for every incoming notification. It is kept for parity,
  /// since the focus surface uses [enqueueAlways] and its production dispatch is withdrawn at the DI seam.
  /// Its urgent branch goes through `_preemptForUrgent()`, which dispatches directly. That never passes
  /// the `_tryStartNext()` pause gate, so the path ignores pause. The non-urgent step parks under pause.
  /// The [suppressDing] flag mirrors the web client: it silences the ding only, not speech, so it is ignored here.
  /// The [voiceId] is the persona voice id routed through `StreamingTtsPlayer.speak()` to the backend `voice_id` body key.
  /// The bloc passes `notification.voicePersona?.voiceId`, and null routes to the server's default voice.
  /// It is not piped to the `flutter_tts` fallback, which has a different voice space (see [_speakViaFallback]).
  /// Design: src/docs/decisions/README.md (R-TTS-voice-id)
  void enqueueIfSpeakable( {
    required String priority,
    required String message,
    String?         title,
    String?         voiceId,
    TtsSender?      sender,
  } ) {
    if ( _prefs.masterMute ) return;
    if ( _sliderAtZero ) return;                            // 0% is silence
    if ( _stopList?.matches( message ) ?? false ) return;   // stop-list: muted
    if ( _systemSenderMuted( sender ) ) return;             // system senders muted as a class
    if ( !_isSpeakable( priority ) ) return;

    final utter = _Utterance(
      priority : priority,
      text     : _formatSpeech( title: title, message: message ),
      voiceId  : voiceId,
      sender   : sender ?? const TtsSender(),
    );

    if ( priority == 'urgent' && !_captureHeld ) {
      _preemptForUrgent( utter );
    } else if ( priority == 'urgent' ) {
      // Recording: queue at the front instead of speaking.
      _insertBehindLeadingUrgents( utter );
    } else {
      _fifo.add( utter );
      _emitQueueDepth();
      if ( _current == null ) _tryStartNext();
    }
  }

  /// Focus-surface ungated entry point: every notification speaks.
  ///
  /// It bypasses `masterMute` and the priority gate. `FocusChatBloc` calls it for every inbound notification.
  /// Urgent items are non-destructive here, and nothing is ever dropped:
  ///   - Urgent while paused: no audio preempt, because pause is absolute. It inserts behind any leading urgents,
  ///     so the urgent block stays arrival-ordered ahead of non-urgents.
  ///   - Urgent while unpaused over a non-urgent: playback stops and the interrupted utterance re-queues
  ///     immediately behind the urgent. It replays from the start on its next turn.
  ///   - Urgent while unpaused over an urgent: no preempt. The newcomer queues behind earlier urgents.
  /// [verbatim] marks an item the user is expected to act on. It skips gate 2 ([_systemSenderMuted], a class
  /// preference about persona-less chatter) and gate 3 ([_formatSpeech]'s fraction cut), which are preferences.
  /// It does not bypass gate 1, the stop-list. The stop-list is a specific "never speak this" the user typed.
  /// Suppression is made visible through [suppressedStream] instead.
  /// Design: src/docs/decisions/README.md (R-TTS-verbatim-stoplist)
  /// Returns the [TtsSuppression] when gate 1 refused the item, else null. The stream carries the same object:
  /// the stream is for observers and the return is for the caller. A caller needs it to offer speak-anyway later.
  TtsSuppression? enqueueAlways( {
    required String priority,
    required String message,
    String?         title,
    String?         voiceId,
    TtsSender?      sender,
    bool            verbatim = false,
    String?         senderKey,
  } ) {
    // Gate M, the master switches ("off means off"): it outranks `verbatim` and the stop-list, like gate 0.
    // An item the switches silence is neither spoken nor offered as speak-anyway.
    // Design: src/docs/decisions/README.md (R-TTS-master-off)
    final silencedBy = _silencedReason( priority: priority, senderKey: senderKey );
    if ( silencedBy != null ) {
      Logger.info( "dispatch outcome=gated reason=$silencedBy priority=$priority", tag: "Tts" );
      return null;
    }

    // Gate 0, the slider at 0%: it outranks `verbatim` and runs before the stop-list, so a silenced item
    // is neither spoken nor offered back as speak-anyway.
    if ( _sliderAtZero ) {
      Logger.info( "dispatch outcome=gated reason=slider_zero priority=$priority", tag: "Tts" );
      return null;
    }

    // The only other gates on this path are the user's explicit "never speak this" rulings: a checked stop-list
    // pattern and the speak-system-senders switch, which mutes persona-less senders as a class.
    // Gate 1 fires first and is never bypassed; it reports instead of returning silently.
    final rule = _stopList?.matchFor( message );
    if ( rule != null ) {
      final suppression = TtsSuppression(
        priority : priority,
        message  : message,
        title    : title,
        voiceId  : voiceId,
        sender   : sender ?? const TtsSender(),
        rule      : rule.pattern,
        verbatim  : verbatim,
        senderKey : senderKey,
      );
      _emitSuppression( suppression );
      Logger.info( "dispatch outcome=gated reason=stop_list priority=$priority", tag: "Tts" );
      return suppression;
    }
    // Gate 2 — a preference; `verbatim` overrides it (ruling 4).
    if ( !verbatim && _systemSenderMuted( sender ) ) {
      Logger.info( "dispatch outcome=gated reason=system_senders_off priority=$priority", tag: "Tts" );
      return null;
    }

    _enqueueUngated(
      priority : priority,
      // Gate 3 — the fraction cut; `verbatim` overrides it (ruling 4).
      text     : _formatSpeech( title: title, message: message, verbatim: verbatim ),
      voiceId  : voiceId,
      sender   : sender,
    );
    return null;
  }

  /// One-tap escape from a stop-list suppression: speaks [s] after all.
  ///
  /// It speaks as if no rule had matched, and bypasses gates 1 and 2. This is an explicit user action on an item
  /// they can see. Re-applying either gate would drop it again with no signal, which is the failure the notice
  /// exists to remove. Gate 3 follows the original call's [TtsSuppression.verbatim], so the preview-fraction
  /// preference still governs ordinary chatter the user chose to unmute.
  void speakAnyway( TtsSuppression s ) {
    if ( _sliderAtZero ) return;   // 0% is silence, even on a tap
    if ( _masterSilenced( priority: s.priority, senderKey: s.senderKey ) ) return;   // off means off, even on a tap
    _enqueueUngated(
      priority : s.priority,
      text     : _formatSpeech( title: s.title, message: s.message, verbatim: s.verbatim ),
      voiceId  : s.voiceId,
      sender   : s.sender,
    );
  }

  /// Replays an already-delivered utterance from the start.
  ///
  /// Replay implies resume. An urgent enqueue only preempts when not paused (see [enqueueAlways]). While held it
  /// falls through to the queue and [_tryStartNext]'s pause gate, so a replay tapped while paused would enqueue
  /// and play nothing. The gesture is pause, then rewind, so [resume] is called first.
  /// Design: src/docs/decisions/README.md (R-TTS-replay-resume)
  ///
  /// [resume] is global: replaying one answer un-holds everything the pause was holding, on every screen.
  /// That is deliberate: nothing was dropped, so the backlog drains and does not disappear.
  /// [sender] defaults to a named sender. `isPersona` is then true, and the replay survives
  /// `speakSystemSenders` being off.
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

  /// Shared enqueue tail for the ungated path.
  ///
  /// It applies urgent-preempt semantics, else appends to the FIFO, then dispatches if idle. Callers own the gates.
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
      if ( !_held && current != null && current.priority != 'urgent' ) {
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

  /// User-invoked cancel, for example from a future "stop speaking" button.
  ///
  /// It is the only destructive queue control; pause never drops.
  Future<void> stopAll() async {
    ++_epoch;   // stale-guard any in-flight completion/error events
    _fifo.clear();
    _emitQueueDepth();
    _current = null;
    _emitQueue();
    await _player.stop();
    await _fallback.stopFallbackSpeech();
  }

  /// Cancels the player subscriptions and closes the streams.
  Future<void> dispose() async {
    _watchdog?.cancel();
    _watchdog = null;
    await _completeSub?.cancel();
    await _errorSub?.cancel();
    await _pausedCtrl.close();
    await _depthCtrl.close();
    await _queueCtrl.close();
    await _suppressedCtrl.close();
  }

  // ---------- private ----------

  /// System-sender gate: mutes a persona-less sender when `speakSystemSenders` is off.
  ///
  /// An unknown sender (null) counts as system, so the legacy path that passes nothing gets the same ruling.
  bool _systemSenderMuted( TtsSender? sender ) =>
      !_prefs.speakSystemSenders && !( sender?.isPersona ?? false );

  bool _isSpeakable( String priority ) {
    switch ( priority ) {
      case 'high'   : return _prefs.speakOnHigh;
      case 'urgent' : return _prefs.speakOnUrgent;
      default       : return false;
    }
  }

  /// The text to speak: the title whole, then the message cut to the preview fraction.
  ///
  /// The fraction is `prefs.ttsFraction`, set by the slider at the top of the focus pane (web
  /// `#cc-tts-fraction-slider` parity). The cut happens at enqueue time. The queue holds text, not audio.
  /// The player synthesizes one utterance at a time when it reaches the head. The cut is therefore
  /// upstream of any TTS spend. [verbatim] skips the cut only. The title still leads, because it was never the truncated part.
  bool get _sliderAtZero => TtsPreviewTruncator.silences( _prefs.ttsFraction );

  /// The focus path's master switches, which follow `NotificationDeliveryPolicy.allows`.
  ///
  /// The urgent bypasses are the same. The surface and per-priority checkboxes do not apply, because the focus
  /// path stays ungated by priority.
  bool _masterSilenced( { required String priority, String? senderKey } ) =>
      _silencedReason( priority: priority, senderKey: senderKey ) != null;

  /// Which master switch silences the item, or null when none does.
  ///
  /// Ensures:
  ///   - one of `notifications_off`, `master_mute`, `sender_muted`, `quiet_hours`, in that order
  ///   - the same decision [_masterSilenced] makes, so a log line can name the gate
  String? _silencedReason( { required String priority, String? senderKey } ) {
    if ( !_prefs.enabled ) return 'notifications_off';
    if ( _prefs.masterMute ) return 'master_mute';
    final urgent = priority == 'urgent';
    if ( _prefs.isSenderMuted( senderKey ) && !( urgent && _prefs.muteUrgentBypass ) ) return 'sender_muted';
    if ( _prefs.inQuietHours( DateTime.now() ) && !( urgent && _prefs.quietUrgentBypass ) ) return 'quiet_hours';
    return null;
  }

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

  /// Inserts [utter] behind the contiguous block of urgents at the queue front.
  ///
  /// That keeps the urgent block arrival-ordered ahead of non-urgents, with no `addFirst` LIFO inversion.
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

  /// Legacy urgent preempt: a destructive flush.
  ///
  /// The pending queue is cleared, current playback stops and the urgent dispatches immediately. It dispatches directly,
  /// never passing the `_tryStartNext()` pause gate, so it is exempt from pause. Behavior is pinned to the original.
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

  /// Focus-path urgent preempt, non-destructive.
  ///
  /// It stops current playback, re-queues the interrupted utterance at the queue front, immediately behind the
  /// urgent, and dispatches the urgent. The interrupted utterance replays from the start on its next turn:
  /// `StreamingTtsPlayer` exposes no mid-utterance position, so utterance-level replay is the only granularity.
  Future<void> _preemptNonDestructive( _Utterance urgent ) async {
    final interrupted = _current;
    ++_epoch;   // preempt-stop: stale-guard the stopped utterance's events
    // Claim the slot before the awaits. An enqueue arriving during the stop() window must see a busy orchestrator.
    // A nulled `_current` here would let it idle-dispatch the queue head and break one-voice-at-a-time with a
    // second concurrent speak.
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
    // Pause gate: the single choke point. It covers utterance completion, error continuation and the
    // dispatch-if-idle step in both enqueue entry points.
    if ( _held ) {
      if ( _current == null && _fifo.isNotEmpty ) {
        Logger.info( "dispatch outcome=held paused=$_paused capture=$_captureHeld queued=${_fifo.length}", tag: "Tts" );
      }
      return;
    }
    if ( _current != null ) return;
    if ( _fifo.isEmpty ) return;
    _current = _fifo.removeFirst();
    _emitQueueDepth();
    await _dispatchCurrent();
  }

  Future<void> _dispatchCurrent() async {
    final utter = _current;
    if ( utter == null ) return;

    _inFlightEpoch = ++_epoch;   // arm the completion/error handlers
    _watchdog?.cancel();

    final sessionId = _ws.sessionId;
    if ( sessionId == null ) {
      // WS not connected — can't do ElevenLabs. Fall back silently for
      // THIS utterance only (don't enter the 5-min quota window).
      Logger.info( "dispatch outcome=fallback reason=no_session chars=${utter.text.length}", tag: "Tts" );
      await _speakViaFallback( utter.text );
      _onUtteranceFinished();
      return;
    }

    if ( _isElevenLabsInFallbackWindow() ) {
      Logger.info( "dispatch outcome=fallback reason=quota_window chars=${utter.text.length}", tag: "Tts" );
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
      Logger.info( "dispatch outcome=posted chars=${utter.text.length}", tag: "Tts" );
      _armWatchdog( utter );
    } catch ( e ) {
      // Network/HTTP failure on POST — fall back for THIS utterance, do
      // not enter the 5-min quota window (this isn't a quota issue).
      Logger.warning( "dispatch outcome=fallback reason=post_failed chars=${utter.text.length}", tag: "Tts", error: e );
      await _speakViaFallback( utter.text );
      _onUtteranceFinished();
    }
  }

  /// Starts the silence timer for [utter], which has just been posted.
  void _armWatchdog( _Utterance utter ) {
    _dispatchedAt = DateTime.now();
    _watchdog?.cancel();
    final epoch = _inFlightEpoch;
    _watchdog = Timer( _speakWatchdog, () => _onWatchdog( utter, epoch ) );
  }

  /// Gives up on an utterance whose audio events stopped, and speaks it on-device.
  ///
  /// Requires:
  ///   - runs from the timer armed by [_armWatchdog]
  ///
  /// Ensures:
  ///   - does nothing when the utterance finished, was skipped or was preempted since the timer was armed
  ///   - re-arms, and does not fire, while audio is playing or an event arrived inside the window
  ///   - otherwise stops the player, speaks the utterance through the fallback once, then continues the queue
  Future<void> _onWatchdog( _Utterance utter, int epoch ) async {
    if ( epoch != _epoch || !identical( _current, utter ) ) return;   // finished, skipped or preempted

    final last  = _player.lastActivityAt;
    final since = DateTime.now().difference( last != null && last.isAfter( _dispatchedAt! ) ? last : _dispatchedAt! );
    if ( _player.isAudioPlaying || since < _speakWatchdog ) {
      _watchdog = Timer( _speakWatchdog, () => _onWatchdog( utter, epoch ) );
      return;
    }

    Logger.warning( "dispatch outcome=fallback reason=watchdog silent_ms=${since.inMilliseconds} chars=${utter.text.length}", tag: "Tts" );
    ++_epoch;   // stale-guard any late completion or error for the abandoned stream
    await _player.stop();
    if ( !identical( _current, utter ) ) return;   // skipped or stopped while stopping
    await _speakViaFallback( utter.text );
    if ( !identical( _current, utter ) ) return;
    _current = null;
    _emitQueue();
    await _tryStartNext();
  }

  Future<void> _speakViaFallback( String text ) async {
    // Intentional: `voiceId` is not piped through to the `flutter_tts` fallback.
    // ElevenLabs voice ids live in a different voice space than the on-device `flutter_tts` engine voices, and mapping
    // them would need a translation table that does not exist. The fallback uses the device default voice, so the
    // narration still happens without the per-session persona match. Before "fixing" this by passing `voiceId`
    // here, read the decision record.
    // Design: src/docs/decisions/README.md (R-TTS-voice-id)
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
    if ( _inFlightEpoch != _epoch ) return;   // stale event
    _watchdog?.cancel();
    Logger.info( "dispatch outcome=error code=${event.errorCode}", tag: "Tts" );

    final wasCurrent = _current;
    _current = null;
    _emitQueue();

    if ( event.errorCode == 'quota_exceeded' ) {
      _elevenLabsDisabledUntil = DateTime.now().add( _quotaFallbackWindow );
      // Re-speak the current utterance via fallback, then continue.
      // (Under pause this re-speak still runs — it is the in-flight
      // utterance finishing; the continuation then parks at the
      // `_tryStartNext()` gate.)
      if ( wasCurrent != null ) {
        _speakViaFallback( wasCurrent.text ).then( ( _ ) => _tryStartNext() );
        return;
      }
    }
    // Any other error: skip this utterance, continue queue (parks at the
    // pause gate when held).
    _tryStartNext();
  }

  void _onUtteranceFinished() {
    if ( _inFlightEpoch != _epoch ) return;   // stale event
    _watchdog?.cancel();
    _current = null;
    _emitQueue();
    _tryStartNext();
  }
}

/// Who a queued utterance comes from, for the queue viewer and the system-sender gate.
///
/// `name` and `icon` come from the voice persona; both null means a system sender with no persona.
class TtsSender {
  /// Sender id, such as `email#hash`, or null.
  final String? senderId;
  /// Persona name, or null for a system sender.
  final String? name;
  /// Persona icon, or null for a system sender.
  final String? icon;
  /// Creates a sender; all fields are optional.
  const TtsSender( { this.senderId, this.name, this.icon } );

  /// True when the sender has a persona name or icon.
  bool get isPersona => ( name ?? '' ).isNotEmpty || ( icon ?? '' ).isNotEmpty;

  /// Short label for the viewer: persona name, else sender id before `@` or `#`, else "system".
  String get label {
    final n = ( name ?? '' ).trim();
    if ( n.isNotEmpty ) return n;
    final local = ( senderId ?? '' ).split( RegExp( r'[@#]' ) ).first.trim();
    return local.isEmpty ? 'system' : local;
  }
}

/// An item the stop-list (gate 1) refused to speak, reported rather than dropped in silence.
///
/// [rule] is the pattern that matched, so the UI can name it ("not spoken, matches 'Done: Bash'").
/// The rest is enough of the original call for [TtsOrchestrator.speakAnyway] to re-issue it on one tap.
/// It is a plain value: the orchestrator decides to suppress and the UI decides how to show it.
class TtsSuppression {
  /// Server priority: `low`, `medium`, `high` or `urgent`.
  final String    priority;
  /// Message text as received, before any cut.
  final String    message;
  /// Title spoken before the message, or null.
  final String?   title;
  /// Persona voice id for ElevenLabs, or null for the default voice.
  final String?   voiceId;
  /// Who the item came from.
  final TtsSender sender;

  /// The matching stop-list pattern, exactly as the user typed it.
  final String    rule;

  /// Whether the suppressed call had asked for the `verbatim` treatment.
  ///
  /// Kept so speak-anyway reproduces the original intent and does not guess.
  final bool      verbatim;

  /// `notificationSenderKey` of the suppressed item, so speak-anyway can re-check the mute.
  final String?   senderKey;

  /// Creates a suppression record.
  const TtsSuppression( {
    required this.priority,
    required this.message,
    required this.rule,
    this.title,
    this.voiceId,
    this.sender   = const TtsSender(),
    this.verbatim = false,
    this.senderKey,
  } );
}

/// One row of the TTS queue viewer, in play order with the in-flight utterance first.
///
/// It matches the web `#tts-queue-section`. `id` is the handle for [TtsOrchestrator.removeQueued].
class TtsQueueItem {
  /// Handle for [TtsOrchestrator.removeQueued].
  final int       id;
  /// Server priority of the utterance.
  final String    priority;
  /// The text that will be spoken, after the title and any cut.
  final String    text;
  /// Who the utterance came from.
  final TtsSender sender;
  /// True for the in-flight utterance.
  final bool      isCurrent;
  /// Creates a row; every field is required.
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
