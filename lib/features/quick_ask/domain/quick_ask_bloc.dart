import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/asr/asr_service.dart';
import '../../../services/asr/voice_capture_session.dart';
import '../../../services/permissions/mic_permission.dart' as mic;
import '../../../services/quick_ask/quick_ask_preferences.dart';
import '../../../services/websocket/websocket_service.dart';
import '../../notifications/data/ask_resolution.dart';
import '../../notifications/data/notification_models.dart';
import '../../notifications/data/notification_repository.dart';
import '../../queue/data/queue_models.dart';
import '../../queue/data/queue_repository.dart';
import '../../queue/domain/job_lifecycle.dart';
import '../data/quick_ask_models.dart';
import 'quick_ask_event.dart';
import 'quick_ask_state.dart';

/// A frame held before we know our job id, with the moment it arrived.
class _BufferedFrame {
  final Map<String, dynamic> frame;
  final DateTime             at;
  const _BufferedFrame( this.frame, this.at );
}

/// Quick Ask's state engine.
///
/// It is a dedicated bloc, not an extension of `QueueBloc`.
/// `QueueBloc`'s state is a single-slot union whose members clobber each other.
/// Its external-update handler returns early unless the dashboard is loaded,
/// so any dashboard refresh would wipe an in-flight ask.
///
/// Correlation is a rank-monotonic reducer with a pre-attribution buffer and a silence watchdog.
/// The three mechanisms answer three different problems and are kept separate.
class QuickAskBloc extends Bloc<QuickAskEvent, QuickAskState> {
  /// The `type` of a notification that reports an in-flight milestone.
  ///
  /// It is named rather than inlined because the completion channel's correctness turns on it.
  /// See the guard in [_onNotification].
  static const String progressNotificationType = 'progress';

  final QueueRepository  _repo;
  final AsrService       _asr;
  final WebSocketService _ws;

  /// The second channel: a near-match confirm is a notification.
  ///
  /// It is answered on `POST /api/notify/response`, never on `/api/v2/resume`, which belongs
  /// to the interview. Two endpoints, two repositories, one screen.
  final NotificationRepository _notifications;

  /// The user's email, one of the buffer's insert-time filter keys.
  ///
  /// It closes the admin fan-out hole rather than narrowing it.
  final String? _userEmail;

  /// The most frames the pre-attribution buffer holds.
  ///
  /// It is a memory bound, not the correctness mechanism.
  /// After insert-time filtering the ask's own job contributes at most three frames, so the cap is slack.
  static const int      bufferCap = 32;

  /// How long a buffered frame stays eligible for replay.
  static const Duration bufferTtl = Duration( seconds: 60 );

  /// The watchdog's probe delays, in order.
  ///
  /// This is a probe cadence, not a verdict deadline.
  /// A probe is one cheap queue listing.
  /// Its worst outcome is a single strike and its best outcome resets the ladder,
  /// so probing early is nearly free.
  /// The ladder starts below the server's own 120 s stall threshold to notice a silent job
  /// sooner than the server does.
  static const List<Duration> watchdogLadder = [
    Duration( seconds: 45 ),
    Duration( seconds: 90 ),
    Duration( seconds: 180 ),
  ];

  /// The server's own stall threshold, the floor for declaring a job lost.
  ///
  /// It mirrors the server setting `cj flow consumer stall threshold seconds`.
  /// The user is never told a job is lost while the server still considers it healthy.
  static const Duration serverStallThreshold = Duration( seconds: 120 );

  /// The consecutive found-nowhere probes required to declare a job lost.
  ///
  /// The count is bounded because a watchdog that never terminates spins the UI forever,
  /// which is worse than resolving wrongly.
  static const int lostAfterStrikes = 3;

  final List<_BufferedFrame> _buffer = [];

  Timer?    _watchdog;
  int       _strikes    = 0;
  int       _ladderStep = 0;
  DateTime? _firstStrikeAt;

  StreamSubscription<bool>? _connSub;

  /// Injectable clock so the TTL is testable without wall time.
  final DateTime Function() _now;

  /// The microphone permission requester, not a check.
  ///
  /// `AsrService` only checks and throws.
  /// Without a real request, a first-run user is refused without ever being asked,
  /// and the screen does not work at all on a fresh install.
  /// It is shared with `VoiceReplyField` rather than copied.
  final mic.MicPermissionRequester _requestMic;

  /// Review first or send immediately.
  ///
  /// It is a constructor dependency, not a locator lookup, so the unit harness can build the bloc
  /// without dependency injection.
  /// It is read at release time and never cached.
  final QuickAskPreferences _prefs;

  /// Creates the bloc; the clock and microphone requester default to the real ones.
  QuickAskBloc(
    this._repo, {
    required AsrService          asr,
    required WebSocketService    ws,
    required NotificationRepository notifications,
    required QuickAskPreferences prefs,
    String?                   userEmail,
    DateTime Function()?      now,
    mic.MicPermissionRequester? requestMicPermission,
  } )  : _asr           = asr,
        _ws            = ws,
        _notifications = notifications,
        _prefs         = prefs,
        _userEmail     = userEmail,
        _now           = now ?? DateTime.now,
        _requestMic    = requestMicPermission ?? mic.requestMicPermission,
        super( QuickAskState( sendImmediately: prefs.sendImmediately ) ) {

    on<QuickAskRecordPressed>( _onRecordPressed );
    on<QuickAskRecordReleased>( _onRecordReleased );
    on<QuickAskRecordCancelled>( _onRecordCancelled );
    on<QuickAskDraftSent>( _onDraftSent );
    on<QuickAskDraftCleared>( _onDraftCleared );
    on<QuickAskTransitionReceived>( _onTransition );
    on<QuickAskNotificationReceived>( _onNotification );
    on<QuickAskConnectionChanged>( _onConnectionChanged );
    on<QuickAskPromptAnswered>( _onPromptAnswered );
    on<QuickAskPromptDismissed>( _onPromptDismissed );
    on<QuickAskInterviewAnswered>( _onInterviewAnswered );
    on<QuickAskInterviewCancelled>( _onInterviewCancelled );
    on<QuickAskEntryDismissed>( _onEntryDismissed );
    on<QuickAskErrorDismissed>( _onErrorDismissed );
    on<QuickAskWatchdogFired>( _onWatchdogFired );
    on<QuickAskSendModeChanged>( _onSendModeChanged );
    on<QuickAskSpokenEventArrived>( _onSpokenEventArrived );

    // The stream replays its last value on subscribe, so a bloc constructed
    // while already disconnected knows it immediately.
    _connSub = _ws.connectionStream.listen( ( c ) => add( QuickAskConnectionChanged( c ) ) );
  }

  /// Whether [jobId] is the live Quick Ask job.
  ///
  /// `FocusChatBloc` probes it to decide on verbatim speech.
  /// That keeps the speech enqueue in one place rather than giving a second bloc a reason to speak.
  bool isQuickAskJob( String? jobId ) =>
      jobId != null && jobId.isNotEmpty && jobId == state.liveJobId;

  /// The shared record-then-transcribe core.
  ///
  /// This bloc and `VoiceReplyField` both call the one session.
  /// So the cancel guard behind "exactly one submit, including when cancelled mid-press"
  /// is a single implementation.
  /// The epoch is still read here, because the spoken-stream maps below are keyed by it.
  late final VoiceCaptureSession _session = VoiceCaptureSession(
    asr               : _asr,
    requestPermission : _requestMic,
  );

  int get _opEpoch => _session.epoch;

  Future<void> _onRecordPressed( QuickAskRecordPressed e, Emitter<QuickAskState> emit ) async {
    // Re-entrancy guard. `canRecord` stays true while a capture runs,
    // because it describes whether the control is live.
    // The guard against a second start therefore belongs here, not in the predicate.
    if ( state.phase == QuickAskPhase.recording ) return;
    if ( !state.canRecord ) return;

    // The session requests the microphone before capturing.
    // `AsrService.startRecording()` only checks permission and throws,
    // which on a fresh install would refuse a user who was never asked.
    final start = await _session.start();
    if ( start.isStale ) return;
    if ( !start.started ) {
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : start.errorMessage,
        capturing    : _asr.isCapturing,
      ) );
      return;
    }
    emit( state.copyWith(
      phase      : QuickAskPhase.recording,
      clearError : true,
      capturing  : _asr.isCapturing,
    ) );
  }

  /// Second tap: stop, transcribe and hold the draft.
  ///
  /// The submit lives behind the send button, not here.
  Future<void> _onRecordReleased( QuickAskRecordReleased e, Emitter<QuickAskState> emit ) async {
    if ( state.phase != QuickAskPhase.recording ) return;
    final epoch = _opEpoch;
    emit( state.copyWith( phase: QuickAskPhase.transcribing ) );

    // Read the preference now, never `state.sendImmediately` and never a value cached at construction.
    // The bloc lives for the whole app session, so a cached mode would ignore a flip until restart.
    if ( _prefs.sendImmediately ) {
      await _releaseSpoken( epoch, emit );
      return;
    }

    // The session handles the recorder's error, the cancel-in-flight drop and the blank transcript.
    // A held draft must never be blank, since that would put a live send button in front of nothing.
    final capture = await _session.stopAndTranscribe();
    if ( capture.isStale ) return;
    if ( !capture.wasHeard ) {
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : capture.errorMessage,
        capturing    : _asr.isCapturing,
        clearDraft   : true,
      ) );
      return;
    }

    emit( state.copyWith(
      phase           : QuickAskPhase.review,
      draftTranscript : capture.transcript,
      capturing       : _asr.isCapturing,
    ) );
  }

  /// Open spoken streams, keyed by the epoch they were released under.
  ///
  /// It is a map, never one shared handle.
  /// Cancel does not stop a read, and `canRecord` is true again straight after a cancel.
  /// So a second press can start a second stream while the first is unresolved.
  /// Each terminal event removes its own key. Nulling a single field would remove the live one.
  final Map<int, StreamSubscription<SpokenAskEvent>> _spokenSubs = {};

  /// Each spoken stream's recording, keyed by the same epoch.
  ///
  /// One shared path would let stream A's ending delete stream B's file after a cancel-then-press.
  final Map<int, String> _spokenPaths = {};

  /// The epoch keys of the open spoken streams, for tests.
  ///
  /// The map is library-private.
  /// Without this a test cannot see that two streams are tracked and that each terminal removes only its own.
  @visibleForTesting
  Set<int> get liveSpokenEpochs => Set.unmodifiable( _spokenSubs.keys );

  /// How many frames the pre-attribution buffer holds, for tests.
  ///
  /// The subscribe-time clear is not observable through behaviour.
  /// Past `bufferCap`, `_insertBuffered` evicts oldest-first,
  /// so a later stream's frames survive by how many frames arrive after them,
  /// whatever an earlier stream left behind.
  /// Its guard is therefore on the buffer itself.
  @visibleForTesting
  int get bufferedFrameCount => _buffer.length;

  /// Stops, posts the audio and subscribes.
  ///
  /// Everything after this re-enters through [QuickAskSpokenEventArrived].
  Future<void> _releaseSpoken( int epoch, Emitter<QuickAskState> emit ) async {
    // This is a `catch`, not a `finally`.
    // `.listen()` returns as soon as the subscription exists, so a `finally` would run
    // while the upload is still in flight and delete the recording out from under it.
    // The catch is the never-subscribed path, and it adds no key to the map.
    try {
      // Throws `AsrException` with nothing retained, so a throw here has no
      // recording to discard and no path is recorded.
      final path = await _asr.stopToFile();
      _spokenPaths[ epoch ] = path;

      // Cancelled while the recorder was stopped: nothing has been sent, so send nothing.
      // This is the same rule as the stale-transcript drop in `_onRecordReleased`.
      if ( epoch != _opEpoch ) {
        _discardRecording( epoch );
        return;
      }

      // `connected` only goes true after the session id is validated,
      // but `WebSocketService.disconnect()` nulls the id without stopping a capture under way.
      // Sending then would put an empty websocket_id on the query string,
      // and the server would route the answer to an address where nobody listens.
      // Send nothing and say so.
      final sessionId = _ws.sessionId;
      if ( sessionId == null || sessionId.isEmpty ) {
        _discardRecording( epoch );
        emit( state.copyWith(
          phase        : QuickAskPhase.idle,
          errorMessage : noSessionMessage,
          capturing    : _asr.isCapturing,
        ) );
        return;
      }

      // Arm the buffer here, at subscribe time.
      // The server starts the ask before the first reply line leaves it,
      // so the ask's first transitions can land before the transcript does.
      // `_shouldBuffer` keys on a live spoken stream for that window.
      // This is the spoken twin of `_submit` clearing before the call.
      // The transcript arm does not clear: that would drop the pre-transcript frames this arming keeps.
      _buffer.clear();

      _spokenSubs[ epoch ] = _repo
          .askSpoken( path, sessionId )
          .listen( ( ev ) => add( QuickAskSpokenEventArrived( epoch, ev ) ) );
    } catch ( ex ) {
      _discardRecording( epoch );
      if ( epoch != _opEpoch ) return;
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : ex is AsrException ? ex.message : 'Could not send that question: $ex',
        capturing    : _asr.isCapturing,
      ) );
    }
  }

  Future<void> _onSpokenEventArrived( QuickAskSpokenEventArrived e, Emitter<QuickAskState> emit ) async {
    final ev = e.event;

    // On every terminal, current epoch or stale, forget this stream's own key
    // and release its own recording before the stale return below, never after it.
    if ( ev.isTerminal ) {
      _spokenSubs.remove( e.epoch );
      _discardRecording( e.epoch );
    }

    // Stale: a cancel, a clear or a new press happened after release.
    // The server already started this work, so a result that names a job is cancelled on arrival.
    // No card, no state change.
    if ( e.epoch != _opEpoch ) {
      if ( ev is SpokenAskResult ) {
        final jobId = ev.response.jobId;
        if ( jobId != null && jobId.isNotEmpty ) {
          unawaited( _repo.cancelJob( jobId ).catchError( ( Object _ ) {} ) );
        }
      }
      return;
    }

    switch ( ev ) {
      case SpokenAskTranscript():
        emit( state.copyWith(
          phase        : QuickAskPhase.submitting,
          liveQuestion : ev.text,
          capturing    : _asr.isCapturing,
        ) );

      case SpokenAskResult():
        // The transcript arrived on a different event; `liveQuestion` carries it,
        // written by the transcript arm.
        // A cancel in between clears it, but that path is stale and never reaches here.
        await _applyResolvedAsk( ev.response, state.liveQuestion ?? '', emit );

      case SpokenAskFailed():
        emit( state.copyWith(
          phase             : QuickAskPhase.idle,
          errorMessage      : ev.detail,
          capturing         : _asr.isCapturing,
          clearLiveQuestion : true,
        ) );

      case SpokenAskCutOff():
        // The question was asked and its answer may still arrive as a notification.
        // Without a job id there is nothing to track or cancel, so the card says exactly that.
        emit( state.copyWith(
          phase   : QuickAskPhase.idle,
          entries : [ ...state.entries, QuickAskEntry(
            questionText : ev.transcript,
            state        : JobLifecycleState.failed,
            source       : QuickAskSource.askResponse,
            details      : JobSummary(
              jobId        : '',
              questionText : ev.transcript,
              status       : 'failed',
              error        : cutOffMessage,
            ),
          ) ],
          capturing         : _asr.isCapturing,
          clearLiveQuestion : true,
        ) );
    }
  }

  /// The error for a send-immediately release with no WebSocket session.
  static const String noSessionMessage = 'Not connected — your question was not sent. Try again once reconnected.';

  /// The card text for a reply that stopped after the transcript.
  static const String cutOffMessage = 'Sent, but the reply was cut off. The answer may still arrive.';

  /// Tells `AsrService` to let go of the recording belonging to [epoch].
  ///
  /// `AsrService` owns the recording. The bloc only names this epoch's file.
  void _discardRecording( int epoch ) {
    final path = _spokenPaths.remove( epoch );
    if ( path != null ) _asr.discardPendingUpload( path );
  }

  /// The send button, the only route from a held transcript to the server.
  Future<void> _onDraftSent( QuickAskDraftSent e, Emitter<QuickAskState> emit ) async {
    final transcript = state.draftTranscript;
    if ( state.phase != QuickAskPhase.review || transcript == null ) return;

    emit( state.copyWith(
      phase        : QuickAskPhase.submitting,
      liveQuestion : transcript,
      clearDraft   : true,
    ) );

    await _submit( transcript, emit );
  }

  /// The clear button: throws the held transcript away.
  Future<void> _onDraftCleared( QuickAskDraftCleared e, Emitter<QuickAskState> emit ) async {
    _session.invalidate();            // anything still in flight is now stale
    emit( state.copyWith(
      phase             : QuickAskPhase.idle,
      clearDraft        : true,
      clearLiveQuestion : true,
      clearError        : true,
    ) );
  }

  Future<void> _onRecordCancelled( QuickAskRecordCancelled e, Emitter<QuickAskState> emit ) async {
    await _session.cancelAwaiting();  // anything in flight is now stale
    emit( state.copyWith(
      phase             : QuickAskPhase.idle,
      capturing         : _asr.isCapturing,
      clearLiveQuestion : true,
      clearDraft        : true,
      clearError        : true,
    ) );
  }

  /// The X on a question card: cancels the job if it is still running, then removes the card.
  ///
  /// The cancel is required.
  /// A dismissed card whose job keeps running would still hold `liveJobId`, blocking the record button,
  /// and would still speak its answer on arrival.
  /// Clearing `liveJobId` here also makes late frames for that job drop instead of resurrecting the card.
  /// `_onTransition` returns early when `liveEntry` is null,
  /// and `_replaceEntry` only replaces a row it can already find.
  Future<void> _onEntryDismissed( QuickAskEntryDismissed e, Emitter<QuickAskState> emit ) async {
    final match = _findEntry( e.jobId );
    if ( match == null ) return;

    // Cancel before dropping the card locally: if the call throws, the user has not yet been told it is gone.
    if ( !match.isTerminal && match.jobId != null && match.jobId!.isNotEmpty ) {
      try {
        await _repo.cancelJob( match.jobId! );
      } on QueueApiException catch ( ex ) {
        emit( state.copyWith( errorMessage: 'Could not cancel that question: ${ex.message}' ) );
        return;
      }
    }

    final wasLive = match.jobId != null && match.jobId == state.liveJobId;
    if ( wasLive ) _cancelWatchdog();

    final remaining = state.entries
        .where( ( x ) => !identical( x, match ) )
        .toList( growable: false );

    emit( state.copyWith(
      entries           : remaining,
      // Only the live card's removal frees the button.
      // Dismissing an old answered card must not disturb a question in flight.
      phase             : wasLive ? QuickAskPhase.idle : state.phase,
      clearLiveJobId    : wasLive,
      clearLiveQuestion : wasLive,
      lost              : wasLive ? false : state.lost,
    ) );
  }

  /// Finds the newest entry matching [jobId].
  ///
  /// A null id addresses the one card with no job yet, the pre-attribution question,
  /// so that card stays dismissible.
  QuickAskEntry? _findEntry( String? jobId ) {
    for ( final e in state.entries.reversed ) {
      if ( jobId == null ) {
        if ( e.jobId == null || e.jobId!.isEmpty ) return e;
      } else if ( e.jobId == jobId ) {
        return e;
      }
    }
    return null;
  }

  Future<void> _submit( String transcript, Emitter<QuickAskState> emit ) async {
    // Arm the buffer before the call.
    // The `pending` to `queued` frame is emitted synchronously inside `push()`
    // and is on the wire before the server has serialized the response body.
    // A client that starts listening after it learns the job id routinely misses frames,
    // and can miss the whole job.
    _buffer.clear();

    AskResponse res;
    try {
      res = await _repo.ask( AskRequest(
        question    : transcript,
        websocketId : _ws.sessionId,
      ) );
    } on QueueApiException catch ( ex ) {
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : ex.message,
        clearLiveQuestion : true,
      ) );
      return;
    }

    await _applyResolvedAsk( res, transcript, emit );
  }

  /// Applies the six-outcome status table to an ask outcome or a resume outcome.
  ///
  /// There is one implementation, so the second turn of an interview cannot drift from
  /// the first turn of an ask.
  Future<void> _applyResolvedAsk( AskResponse res, String transcript, Emitter<QuickAskState> emit ) async {

    // Branch on status, never on which id happens to be present.
    // A third case has no id at all, and sniffing for one would offer an answer box with nowhere to send it.
    if ( _applyStatusBranch( res, transcript, emit ) ) return;

    if ( res.isDone ) {
      // Served from cache or inline: the answer is already here,
      // so there is no correlation to do and no watchdog to arm.
      emit( state.copyWith(
        phase   : QuickAskPhase.idle,
        entries : [ ...state.entries, QuickAskEntry(
          questionText : transcript,
          state        : JobLifecycleState.completed,
          source       : QuickAskSource.askResponse,
          jobId        : res.jobId,
          details      : res.jobId == null ? null : JobSummary(
            jobId        : res.jobId!,
            questionText : transcript,
            status       : 'completed',
            responseText : res.answer,
            isCacheHit   : res.cacheHit,
          ),
        ) ],
        clearLiveQuestion : true,
      ) );
      return;
    }

    if ( res.isFailed ) {
      emit( state.copyWith(
        phase             : QuickAskPhase.idle,
        errorMessage      : res.error ?? 'Request failed',
        clearLiveQuestion : true,
      ) );
      return;
    }

    final jobId = res.jobId;
    if ( jobId == null || jobId.isEmpty ) {
      emit( state.copyWith( phase: QuickAskPhase.idle, clearLiveQuestion: true ) );
      return;
    }

    // Attribution: seed the entry, then drain the buffer in rank order.
    var entry = QuickAskEntry(
      questionText : transcript,
      state        : JobLifecycleState.pending,
      source       : QuickAskSource.askResponse,
      jobId        : jobId,
    );

    final drained = _drainBufferFor( jobId );
    for ( final f in drained ) {
      final candidate = QuickAskEntry.fromTransition( f, questionText: transcript );
      if ( candidate != null ) entry = _fold( entry, candidate );
    }

    emit( state.copyWith(
      phase     : entry.isTerminal ? QuickAskPhase.idle : QuickAskPhase.waiting,
      liveJobId : entry.isTerminal ? null : jobId,
      clearLiveJobId : entry.isTerminal,
      entries   : [ ...state.entries, entry ],
    ) );

    if ( entry.isTerminal ) {
      _cancelWatchdog();
    } else {
      _armWatchdog( reset: true );
    }
  }

  /// Handles the status arms that resolve without correlation.
  ///
  /// Those are `parked`, `expired`, `rejected` and `needs_input`.
  ///
  /// Returns true when it has fully handled the response; `done`, `failed` and `waiting` are the caller's.
  /// Branching is on status, never on which id happens to be present.
  ///
  /// `parked` and `needs_input` are different things, not one thing with different ids.
  /// `parked` means the server is asking and holds a `pending_id` open for the reply.
  /// `needs_input` means the server is telling: the submit path never parks, there is no id,
  /// and nothing exists to answer to.
  bool _applyStatusBranch( AskResponse res, String transcript, Emitter<QuickAskState> emit ) {

    if ( res.status == 'parked' ) {
      final pendingId = res.pendingId;
      if ( pendingId == null || pendingId.isEmpty ) return false;   // malformed; fall through
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        liveQuestion : transcript,
        interview    : QuickAskInterview(
          pendingId   : pendingId,
          question    : res.answer ?? 'The server needs more information.',
          argsMissing : res.argsMissing,
        ),
      ) );
      _cancelWatchdog();
      return true;
    }

    // The resume endpoint has two endings, and both arrive as `status: expired`.
    // Only `route_reason` tells them apart.
    // They mean different things to the user: the question timed out and should be asked again,
    // or the turn was already answered, possibly on another device.
    // One shared "something went wrong" card would tell the user nothing they can act on.
    // Without this arm, `expired` would fall through to the no-job-id case and the turn would vanish in silence.
    if ( res.isExpired ) {
      final resolution = classifyResumeStatus( res.routeReason );
      emit( state.copyWith(
        phase   : QuickAskPhase.idle,
        entries : [ ...state.entries, QuickAskEntry(
          questionText : transcript,
          state        : JobLifecycleState.failed,
          source       : QuickAskSource.askResponse,
          details      : JobSummary(
            jobId        : '',
            questionText : transcript,
            status       : 'failed',
            error        : resolution.userMessage,
          ),
        ) ],
        clearLiveQuestion : true,
        clearInterview    : true,
      ) );
      _cancelWatchdog();
      return true;
    }

    // `rejected` is the fitness gate, applied before the cache, the router or the expeditor sees the question.
    // It is a status the response model's own docstring does not list.
    // It carries the refusal sentence in `answer`, the same sentence the server speaks.
    // A generic "Request failed" would throw away the one thing that tells the user why
    // and make a refusal indistinguishable from a crash.
    if ( res.status == 'rejected' ) {
      emit( state.copyWith(
        phase   : QuickAskPhase.idle,
        entries : [ ...state.entries, QuickAskEntry(
          questionText : transcript,
          state        : JobLifecycleState.failed,
          source       : QuickAskSource.askResponse,
          details      : JobSummary(
            jobId        : '',
            questionText : transcript,
            status       : 'failed',
            error        : res.answer ?? res.error ?? 'That question was refused.',
          ),
        ) ],
        clearLiveQuestion : true,
        clearInterview    : true,
      ) );
      _cancelWatchdog();
      return true;
    }

    if ( res.status == 'needs_input' ) {
      // A terminal card naming what was missing, with no answer control, because there is nothing to answer.
      // The entry is `failed` so it renders in the dead lane, which has no reply controls.
      emit( state.copyWith(
        phase   : QuickAskPhase.idle,
        entries : [ ...state.entries, QuickAskEntry(
          questionText : transcript,
          state        : JobLifecycleState.failed,
          source       : QuickAskSource.askResponse,
          details      : JobSummary(
            jobId        : '',
            questionText : transcript,
            status       : 'failed',
            error        : res.argsMissing.isEmpty
                ? 'The server needs more information to answer that.'
                : 'Missing: ${res.argsMissing.join( ", " )}',
          ),
        ) ],
        clearLiveQuestion : true,
        clearInterview    : true,
      ) );
      _cancelWatchdog();
      return true;
    }

    return false;
  }

  Future<void> _onPromptAnswered( QuickAskPromptAnswered e, Emitter<QuickAskState> emit ) =>
      _respondToPrompt( e.answer, emit );

  Future<void> _onPromptDismissed( QuickAskPromptDismissed e, Emitter<QuickAskState> emit ) {
    final prompt = state.pendingPrompt;
    if ( prompt == null ) return Future.value();
    return _respondToPrompt( prompt.defaultAnswer, emit );
  }

  /// Posts the answer to a prompt that arrived alongside an ask.
  ///
  /// Every emit here clears the prompt and nothing else:
  /// no phase change, no entry rewrite, no `liveJobId` change and no watchdog call.
  /// The ask this prompt is blocking is still in flight on its own 240 s socket,
  /// and disturbing it would break that ask.
  Future<void> _respondToPrompt( String answer, Emitter<QuickAskState> emit ) async {
    final prompt = state.pendingPrompt;
    if ( prompt == null ) return;

    try {
      await _notifications.respond( NotificationResponsePayload(
        notificationId : prompt.id,
        responseValue  : answer,
      ) );
    } on NotificationApiException catch ( ex ) {
      // "Already responded" and "grace period exceeded" are endings, not errors:
      // another device answered, or the window closed.
      // Either way the prompt is finished, and holding it open would block recording forever.
      final resolution = classifyRespondFailure( ex.message );
      emit( resolution.isResolved
          ? state.copyWith( clearPendingPrompt: true )
          : state.copyWith( errorMessage: ex.message ) );
      return;
    }

    emit( state.copyWith( clearPendingPrompt: true, clearError: true ) );
  }

  Future<void> _onInterviewAnswered( QuickAskInterviewAnswered e, Emitter<QuickAskState> emit ) async {
    final live = state.interview;
    if ( live == null ) return;

    emit( state.copyWith( phase: QuickAskPhase.submitting, clearError: true ) );

    AskResponse res;
    try {
      res = await _repo.resume( ResumeRequest(
        // The same pending id every turn: the server holds one id open for the whole interview
        // and re-asks the next argument on it.
        pendingId   : live.pendingId,
        answer      : e.answer,
        websocketId : _ws.sessionId,
      ) );
    } on QueueApiException catch ( ex ) {
      emit( state.copyWith( phase: QuickAskPhase.idle, errorMessage: ex.message ) );
      return;
    }

    // A second `parked` loops back to the prompt and does not terminate.
    // Treating the first resume as final would implement the interview by half.
    if ( res.status == 'parked' && ( res.pendingId?.isNotEmpty ?? false ) ) {
      emit( state.copyWith(
        phase     : QuickAskPhase.idle,
        interview : QuickAskInterview(
          pendingId   : res.pendingId!,
          question    : res.answer ?? 'One more thing…',
          argsMissing : res.argsMissing,
          turn        : live.turn + 1,
        ),
      ) );
      return;
    }

    // The interview is over — hand the outcome to the ordinary paths.
    emit( state.copyWith( clearInterview: true ) );
    await _applyResolvedAsk( res, state.liveQuestion ?? live.question, emit );
  }

  Future<void> _onInterviewCancelled( QuickAskInterviewCancelled e, Emitter<QuickAskState> emit ) async {
    emit( state.copyWith(
      phase             : QuickAskPhase.idle,
      clearInterview    : true,
      clearLiveQuestion : true,
    ) );
  }

  /// Whether [frame] belongs to the ask in flight and should enter the buffer.
  ///
  /// The filter runs on insert, not only on drain.
  /// A drain-time filter loses frames silently, because the buffer evicts on insert.
  /// A burst of foreign frames can evict the ask's own before the job id filter is applied.
  /// Sizing the cap cannot fix that.
  /// Transitions go out to the user and to admins.
  /// On an admin account the fan-out is every other user's jobs, which no cap can be sized against.
  ///
  /// The job id is unknown here, since the buffer exists because it is not yet known.
  /// So the filter keys on what every frame carries: `user_email`, plus `question_text` or `session_id`.
  bool _shouldBuffer( Map<String, dynamic> frame ) {
    final live = state.liveQuestion;
    // A send-immediately stream is a submission in flight before its transcript exists,
    // and its frames can arrive in that window.
    // Only the session branch below can match then, and it needs no text.
    final spokenLive = _spokenSubs.containsKey( _opEpoch );
    if ( ( live == null || live.isEmpty ) && !spokenLive ) return false;   // no submission in flight

    final rawMeta = frame[ 'metadata' ];
    final meta    = rawMeta is Map ? Map<String, dynamic>.from( rawMeta ) : <String, dynamic>{};

    // The email key rules out the same question asked by another user.
    // The one-live-question guard closes the remainder.
    // Allowing several live questions would have to re-open this.
    final email = meta[ 'user_email' ] as String?;
    if ( _userEmail != null && email != null && email != _userEmail ) return false;

    final question  = meta[ 'question_text' ] as String?;
    final sessionId = meta[ 'session_id' ]    as String?;
    final mine      = ( question != null && question == live )
                   || ( sessionId != null && _ws.sessionId != null && sessionId == _ws.sessionId );
    return mine;
  }

  /// Adds [frame] to the buffer, dropping expired frames.
  ///
  /// The oldest frames beyond the cap are evicted.
  void _insertBuffered( Map<String, dynamic> frame ) {
    final now = _now();
    _buffer.removeWhere( ( b ) => now.difference( b.at ) > bufferTtl );
    _buffer.add( _BufferedFrame( frame, now ) );
    while ( _buffer.length > bufferCap ) {
      _buffer.removeAt( 0 );
    }
  }

  /// Empties the buffer and returns the unexpired frames for [jobId], in lifecycle rank order.
  List<Map<String, dynamic>> _drainBufferFor( String jobId ) {
    final now  = _now();
    final mine = _buffer
        .where( ( b ) => now.difference( b.at ) <= bufferTtl )
        .map( ( b ) => b.frame )
        .where( ( f ) => f[ 'job_id' ] == jobId )
        .toList();
    _buffer.clear();

    // Fold in rank order, not arrival order.
    // The wire can reorder, and the fold's monotonic guard would otherwise drop
    // a late-arriving earlier frame that carried metadata we want.
    mine.sort( ( a, b ) {
      final ra = JobLifecycleState.parse( a[ 'to_state' ] as String? )?.rank ?? -1;
      final rb = JobLifecycleState.parse( b[ 'to_state' ] as String? )?.rank ?? -1;
      return ra.compareTo( rb );
    } );
    return mine;
  }

  /// Applies [incoming] to [current] only when it outranks the current state.
  ///
  /// Terminal states always apply.
  /// Duplicates and reorders become no-ops, and a missed `running` is repaired by `completed` landing directly.
  QuickAskEntry _fold( QuickAskEntry current, QuickAskEntry incoming ) {
    if ( current.isTerminal ) return current;
    final advances = incoming.isTerminal || incoming.state.rank > current.state.rank;
    if ( !advances ) return current;
    return incoming.copyWith(
      // Keep the transcript that was submitted.
      // A frame's own question_text is the server's echo and can be null on some paths.
      questionText : current.questionText.isNotEmpty ? current.questionText : incoming.questionText,
    );
  }

  Future<void> _onTransition( QuickAskTransitionReceived e, Emitter<QuickAskState> emit ) async {
    final frame = e.frame;
    final jobId = frame[ 'job_id' ] as String?;
    final live  = state.liveJobId;

    if ( live == null ) {
      if ( _shouldBuffer( frame ) ) _insertBuffered( frame );
      return;
    }
    if ( jobId != live ) return;      // another user's job, or another of this user's

    final incoming = QuickAskEntry.fromTransition( frame, questionText: state.liveQuestion ?? '' );
    if ( incoming == null ) return;   // unknown to_state ⇒ drop the frame

    final current = state.liveEntry;
    if ( current == null ) return;

    final folded = _fold( current, incoming );
    if ( identical( folded, current ) ) {
      // No advance, but it is still proof of life, so the ladder resets.
      _armWatchdog( reset: true );
      return;
    }

    emit( _replaceEntry( folded ) );

    if ( folded.isTerminal ) {
      _cancelWatchdog();
    } else {
      _armWatchdog( reset: true );
    }
  }

  /// Returns the state with [updated] replacing its entry.
  ///
  /// A terminal [updated] also releases the live job.
  QuickAskState _replaceEntry( QuickAskEntry updated ) {
    final list = [ ...state.entries ];
    for ( var i = list.length - 1; i >= 0; i-- ) {
      if ( list[ i ].jobId == updated.jobId ) { list[ i ] = updated; break; }
    }
    return state.copyWith(
      entries        : list,
      phase          : updated.isTerminal ? QuickAskPhase.idle : state.phase,
      liveJobId      : updated.isTerminal ? null : state.liveJobId,
      clearLiveJobId : updated.isTerminal,
      lost           : false,
    );
  }

  Future<void> _onNotification( QuickAskNotificationReceived e, Emitter<QuickAskState> emit ) async {
    final n = e.notification;

    // A question the server is waiting on is proof of life,
    // and it is the one thing that arrives in the window where no job id exists yet.
    // A watchdog armed at submission would fire into that silence with nothing to reconcile:
    // no job id to look up, every probe "not found",
    // and the UI declaring `lost` on a request that is alive and waiting for the user.
    if ( n.responseRequested ) {
      // Held whole, so it can be rendered and answered.
      // Holding the id alone blocked the record button on a question the user was never shown,
      // and the near-match confirm then timed out to its "no".
      emit( state.copyWith( pendingPrompt: QuickAskPrompt(
        id              : n.id,
        question        : n.message,
        responseType    : n.responseType,
        responseDefault : n.responseDefault,
        responseOptions : n.responseOptions,
      ) ) );
      _armWatchdog( reset: true );
      return;
    }

    // Completion channel: independent evidence whose `message` is the answer.
    // It is one extra line rather than a second mechanism.
    final live = state.liveJobId;
    if ( live == null || n.jobId != live ) return;

    final current = state.liveEntry;
    if ( current == null || current.isTerminal ) return;

    // The completion channel assumes "this message is the answer", which is false for a progress frame.
    // Without this guard a long-running job's first milestone would mark the card completed,
    // show "Fetching sources..." where the answer belongs, clear `liveJobId` and cancel the watchdog.
    // The real answer, arriving minutes later, would then be dropped by the test above.
    // That fails silently and shows a wrong answer rather than an error.
    //
    // Instead the card stays open and shows the milestone as a status line.
    // The progress text is stored beside the answer, never in it.
    // Design: src/docs/decisions/README.md (R-QA-progress-status-line)
    if ( n.type == progressNotificationType ) {
      emit( _replaceEntry( current.copyWith( progressText: n.message ) ) );
      // Progress is proof of life: a live job must not age toward `lost`.
      _armWatchdog( reset: true );
      return;
    }

    final completed = current.copyWith(
      state   : JobLifecycleState.completed,
      details : JobSummary(
        jobId        : live,
        questionText : current.questionText,
        status       : 'completed',
        responseText : n.message,
      ),
    );
    emit( _replaceEntry( completed ) );
    _cancelWatchdog();
  }

  /// Schedules the next watchdog probe, resetting the ladder first when [reset] is true.
  void _armWatchdog( { bool reset = false } ) {
    if ( reset ) {
      _ladderStep    = 0;
      _strikes       = 0;
      _firstStrikeAt = null;
    }
    _watchdog?.cancel();
    final step = _ladderStep.clamp( 0, watchdogLadder.length - 1 );
    _watchdog  = Timer( watchdogLadder[ step ], () => add( const QuickAskWatchdogFired() ) );
  }

  /// Stops the watchdog and clears its ladder and strike count.
  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog      = null;
    _ladderStep    = 0;
    _strikes       = 0;
    _firstStrikeAt = null;
  }

  Future<void> _onWatchdogFired( QuickAskWatchdogFired e, Emitter<QuickAskState> emit ) async {
    final jobId = state.liveJobId;
    if ( jobId == null ) return;

    // The job-history endpoint is the wrong one and would answer 404.
    // The server persists only agentic job types, and a plain question is not one, so no row is ever written.
    // The queue listings are the endpoint that works.
    final found = await _reconcile( jobId );

    if ( found == null ) {
      // Found nowhere: count a strike toward `lost`.
      _strikes    += 1;
      _firstStrikeAt ??= _now();
      _ladderStep  = ( _ladderStep + 1 ).clamp( 0, watchdogLadder.length - 1 );

      final elapsed  = _now().difference( _firstStrikeAt! );
      final giveUp   = _strikes >= lostAfterStrikes && elapsed > serverStallThreshold;

      if ( giveUp ) {
        _cancelWatchdog();
        emit( state.copyWith( lost: true, phase: QuickAskPhase.idle ) );
        return;
      }
      _armWatchdog();          // back off and rearm, without a reset
      return;
    }

    // Found alive or terminal.
    final current = state.liveEntry;

    if ( !found.isTerminal ) {
      // Positive proof of life: the server can see the job, so this resets the ladder
      // and clears the strike count.
      // Found-alive and found-nowhere are opposite signals and cannot share one rearm path,
      // or a plainly running job would be declared `lost`.
      //
      // A non-terminal reconcile never overrides a terminal folded state.
      // A `completed` frame that was actually received is not undone by a listing that has not caught up.
      if ( current != null && !current.isTerminal ) emit( _replaceEntry( _fold( current, found ) ) );
      _armWatchdog( reset: true );
      return;
    }

    // A terminal reconcile result wins over a non-terminal folded state.
    // The listing is the server's own record, and the watchdog only runs because frames went missing.
    if ( current != null && !current.isTerminal ) {
      emit( _replaceEntry( found.copyWith( questionText: current.questionText ) ) );
    }
    _cancelWatchdog();
  }

  /// Looks for [jobId] in the done, dead, run and todo queues, in that order.
  ///
  /// It stops at the first hit.
  Future<QuickAskEntry?> _reconcile( String jobId ) async {
    for ( final queue in const [ 'done', 'dead', 'run', 'todo' ] ) {
      try {
        final res = await _repo.getQueue( queue );
        for ( final row in res.jobs ) {
          if ( row.jobId == jobId ) {
            return QuickAskEntry.fromSummary( row, state: stateForQueue( queue ) );
          }
        }
      } on QueueApiException {
        // A listing that errors says nothing either way.
        // It is not evidence of absence, so it must not become a strike. Move on.
        continue;
      }
    }
    return null;
  }

  Future<void> _onConnectionChanged( QuickAskConnectionChanged e, Emitter<QuickAskState> emit ) async {
    emit( state.copyWith( connected: e.connected ) );
  }

  Future<void> _onErrorDismissed( QuickAskErrorDismissed e, Emitter<QuickAskState> emit ) async {
    emit( state.copyWith( clearError: true ) );
  }

  /// The send-mode control's only writer.
  ///
  /// It persists first, then emits the render-only state field.
  ///
  /// The release path reads the preference, so the write is what changes behaviour.
  /// The emit only redraws the control.
  Future<void> _onSendModeChanged( QuickAskSendModeChanged e, Emitter<QuickAskState> emit ) async {
    await _prefs.setSendImmediately( e.sendImmediately );
    emit( state.copyWith( sendImmediately: e.sendImmediately ) );
  }

  @override
  Future<void> close() {
    _watchdog?.cancel();
    _connSub?.cancel();
    // This runs at app teardown only, since the bloc is an app-root singleton.
    // A job whose second reply line was still in flight runs uncancelled,
    // and its answer still arrives as a notification with no card left to attach it to.
    // Its recording stays in the temp directory.
    // Both are accepted.
    for ( final sub in _spokenSubs.values ) {
      sub.cancel();
    }
    _spokenSubs.clear();
    return super.close();
  }
}
