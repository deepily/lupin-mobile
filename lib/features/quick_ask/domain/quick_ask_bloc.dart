import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/asr/asr_service.dart';
import '../../../services/permissions/mic_permission.dart' as mic;
import '../../../services/websocket/websocket_service.dart';
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
/// A DEDICATED bloc, not an extension of `QueueBloc`: `QueueBloc`'s state is a
/// single-slot discriminated union whose members clobber each other, and its
/// `_onExternalUpdate` early-returns unless the dashboard is loaded — an
/// in-flight ask would be wiped by any dashboard refresh.
///
/// Correlation is a rank-monotonic reducer with a pre-attribution buffer and a
/// silence watchdog. The three mechanisms answer three different findings and
/// are kept separate on purpose.
class QuickAskBloc extends Bloc<QuickAskEvent, QuickAskState> {
  final QueueRepository  _repo;
  final AsrService       _asr;
  final WebSocketService _ws;

  /// Our identity, used as the buffer's insert-time filter keys. `userEmail`
  /// is the one that CLOSES the admin fan-out hole rather than narrowing it.
  final String? _userEmail;

  // ── Buffer sizing ────────────────────────────────────────────────────────
  // A memory bound, NOT the correctness mechanism. After insert-time filtering
  // our own job contributes at most three frames, so the cap is slack.
  static const int      bufferCap = 32;
  static const Duration bufferTtl = Duration( seconds: 60 );

  // ── Watchdog cadence ─────────────────────────────────────────────────────
  /// Probe cadence, not a verdict deadline. A probe is one cheap queue listing
  /// whose worst outcome is a single strike and whose best outcome resets the
  /// ladder, so probing early is nearly free. It sits BELOW the server's own
  /// 120s stall threshold deliberately — we want to notice a silent job sooner
  /// than the server does.
  static const List<Duration> watchdogLadder = [
    Duration( seconds: 45 ),
    Duration( seconds: 90 ),
    Duration( seconds: 180 ),
  ];

  /// `lost` is floored by the SERVER's own patience, not by a number we picked:
  /// `cj flow consumer stall threshold seconds` (`lupin-app.ini:1061`). Never
  /// tell the user a job is lost while the server still considers it healthy.
  static const Duration serverStallThreshold = Duration( seconds: 120 );

  /// Consecutive found-nowhere probes required for `lost`. BOUNDED — a
  /// watchdog that can never terminate spins the UI forever, which is worse
  /// than resolving wrongly.
  static const int lostAfterStrikes = 3;

  final List<_BufferedFrame> _buffer = [];

  Timer?    _watchdog;
  int       _strikes    = 0;
  int       _ladderStep = 0;
  DateTime? _firstStrikeAt;

  StreamSubscription<bool>? _connSub;

  /// Injectable clock so the TTL is testable without wall time.
  final DateTime Function() _now;

  /// AC-S2.7 — the mic permission REQUESTER, not a check. `AsrService` only
  /// checks and throws; without an actual request a first-run user is refused
  /// having never been asked, and the screen does not work at all on a fresh
  /// install. Shared with `VoiceReplyField` rather than copied — this would
  /// have been the third private copy in the tree.
  final mic.MicPermissionRequester _requestMic;

  QuickAskBloc(
    this._repo, {
    required AsrService       asr,
    required WebSocketService ws,
    String?                   userEmail,
    DateTime Function()?      now,
    mic.MicPermissionRequester? requestMicPermission,
  } )  : _asr        = asr,
        _ws         = ws,
        _userEmail  = userEmail,
        _now        = now ?? DateTime.now,
        _requestMic = requestMicPermission ?? mic.requestMicPermission,
        super( const QuickAskState() ) {

    on<QuickAskRecordPressed>( _onRecordPressed );
    on<QuickAskRecordReleased>( _onRecordReleased );
    on<QuickAskRecordCancelled>( _onRecordCancelled );
    on<QuickAskTransitionReceived>( _onTransition );
    on<QuickAskNotificationReceived>( _onNotification );
    on<QuickAskConnectionChanged>( _onConnectionChanged );
    on<QuickAskInterviewAnswered>( _onInterviewAnswered );
    on<QuickAskInterviewCancelled>( _onInterviewCancelled );
    on<QuickAskErrorDismissed>( _onErrorDismissed );
    on<QuickAskWatchdogFired>( _onWatchdogFired );

    // Seeded by the stream's replay-on-subscribe (AC-S1.8), so a bloc
    // constructed while already disconnected knows it immediately.
    _connSub = _ws.connectionStream.listen( ( c ) => add( QuickAskConnectionChanged( c ) ) );
  }

  /// Read-only probe for `FocusChatBloc`'s verbatim-speech decision (§6): does
  /// this notification belong to a live Quick Ask job? Keeps the enqueue in one
  /// place rather than giving a second bloc a reason to speak.
  bool isQuickAskJob( String? jobId ) =>
      jobId != null && jobId.isNotEmpty && jobId == state.liveJobId;

  /// Cancel guard, mirroring `voice_reply_field.dart`'s `_opEpoch` (`:59`,
  /// captured `:93`, compared `:97`/`:103`, bumped on cancel `:114`) rather
  /// than re-inventing it: a cancel bumps the epoch, and an in-flight
  /// `stopAndTranscribe()` whose epoch no longer matches is DROPPED. That is
  /// what makes "exactly one submit, including when cancelled mid-press" true.
  int _opEpoch = 0;

  // ── Capture ──────────────────────────────────────────────────────────────

  Future<void> _onRecordPressed( QuickAskRecordPressed e, Emitter<QuickAskState> emit ) async {
    // Re-entrancy guard. `canRecord` stays TRUE while the button is held —
    // it describes whether the control is live, and the control is live
    // precisely because a capture is running. The guard against a SECOND
    // start therefore belongs here, not in the predicate.
    if ( state.phase == QuickAskPhase.recording ) return;
    if ( !state.canRecord ) return;
    final epoch = ++_opEpoch;

    // AC-S2.7 — REQUEST before capturing. `AsrService.startRecording()` only
    // checks `hasPermission()` and throws; on a fresh install that produces
    // "Microphone permission denied" for a user who was never asked.
    final granted = await _requestMic();
    if ( epoch != _opEpoch ) return;
    if ( !granted ) {
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : 'Microphone permission needed — enable it in system settings.',
      ) );
      return;
    }

    try {
      await _asr.startRecording();
      if ( epoch != _opEpoch ) return;
      emit( state.copyWith( phase: QuickAskPhase.recording, clearError: true, capturing: _asr.isCapturing ) );
    } on AsrException catch ( ex ) {
      if ( epoch != _opEpoch ) return;
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : ex.message,
        capturing    : _asr.isCapturing,
      ) );
    }
  }

  Future<void> _onRecordReleased( QuickAskRecordReleased e, Emitter<QuickAskState> emit ) async {
    if ( state.phase != QuickAskPhase.recording ) return;
    final epoch = _opEpoch;
    emit( state.copyWith( phase: QuickAskPhase.transcribing ) );

    String transcript;
    try {
      transcript = await _asr.stopAndTranscribe();
    } on AsrException catch ( ex ) {
      if ( epoch != _opEpoch ) return;
      emit( state.copyWith(
        phase        : QuickAskPhase.idle,
        errorMessage : ex.message,
        capturing    : _asr.isCapturing,
      ) );
      return;
    }
    // The cancel landed while the upload was in flight — drop the result.
    if ( epoch != _opEpoch ) return;

    emit( state.copyWith(
      phase        : QuickAskPhase.submitting,
      liveQuestion : transcript,
      capturing    : _asr.isCapturing,
    ) );

    await _submit( transcript, emit );
  }

  Future<void> _onRecordCancelled( QuickAskRecordCancelled e, Emitter<QuickAskState> emit ) async {
    _opEpoch++;                       // anything in flight is now stale
    await _asr.cancelRecording();
    emit( state.copyWith(
      phase             : QuickAskPhase.idle,
      capturing         : _asr.isCapturing,
      clearLiveQuestion : true,
      clearError        : true,
    ) );
  }

  // ── Submission ───────────────────────────────────────────────────────────

  Future<void> _submit( String transcript, Emitter<QuickAskState> emit ) async {
    // Arm the buffer BEFORE the call: the `pending → queued` frame is emitted
    // synchronously inside `push()` and is on the wire before FastAPI has
    // serialized the response body. A client that starts listening after it
    // learns the job id routinely misses frames, and can miss the whole job.
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

  /// The six-outcome status table, applied to an ask OR a resume outcome —
  /// one implementation, so the second turn of an interview cannot drift from
  /// the first turn of an ask.
  Future<void> _applyResolvedAsk( AskResponse res, String transcript, Emitter<QuickAskState> emit ) async {

    // ── Branch on STATUS, never on which id happens to be present ────────
    // (María's ruling). There is a third case with NO id at all, and sniffing
    // for one would offer an answer box with nowhere to send it.
    if ( _applyStatusBranch( res, transcript, emit ) ) return;

    if ( res.isDone ) {
      // Served from cache or inline — the answer is already here, no
      // correlation needed and no watchdog to arm.
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

  /// The `parked` and `needs_input` arms of the six-outcome status table.
  /// Returns true when it has fully handled the response.
  ///
  /// 🔴 `parked` and `needs_input` are NOT the same thing wearing different
  /// ids. `parked` means the server is ASKING and is holding a `pending_id`
  /// open for the reply. `needs_input` means the server is TELLING: the submit
  /// path hard-codes `interactive=False` so it never parks, there is no id,
  /// and nothing exists to answer to (AC-S4.2).
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

    if ( res.status == 'needs_input' ) {
      // A TERMINAL card naming what was missing, and NO answer affordance —
      // there is nothing to answer to. The entry is `failed` so it renders in
      // the dead lane, which is already the lane with no reply controls.
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

  Future<void> _onInterviewAnswered( QuickAskInterviewAnswered e, Emitter<QuickAskState> emit ) async {
    final live = state.interview;
    if ( live == null ) return;

    emit( state.copyWith( phase: QuickAskPhase.submitting, clearError: true ) );

    AskResponse res;
    try {
      res = await _repo.resume( ResumeRequest(
        // 🔴 The SAME pending_id, every turn. The server holds one id open for
        // the whole interview and re-asks the next argument on it.
        pendingId   : live.pendingId,
        answer      : e.answer,
        websocketId : _ws.sessionId,
      ) );
    } on QueueApiException catch ( ex ) {
      emit( state.copyWith( phase: QuickAskPhase.idle, errorMessage: ex.message ) );
      return;
    }

    // A SECOND `parked` loops BACK to the prompt — it does not terminate.
    // Treating the first resume as terminal is ruling 5 half-implemented.
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

  // ── Buffer ───────────────────────────────────────────────────────────────

  /// 🔴 FILTER ON INSERT, not only on drain.
  ///
  /// A drain-time-only filter loses frames SILENTLY: the ring evicts on insert,
  /// so a burst of foreign frames can evict our own before the `jobId` filter
  /// is ever applied. Sizing the cap cannot fix that — transitions go out via
  /// `emit_to_user_and_admins_sync`, so on an admin account the fan-out is
  /// every other user's jobs, which is not a number any cap can be sized
  /// against.
  ///
  /// The `jobId` is unknowable here by construction — the buffer exists
  /// BECAUSE we do not have it yet — so the filter keys on what IS on all
  /// three frames: `user_email`, plus `question_text` or `session_id`.
  bool _shouldBuffer( Map<String, dynamic> frame ) {
    final live = state.liveQuestion;
    if ( live == null || live.isEmpty ) return false;   // no submission in flight

    final rawMeta = frame[ 'metadata' ];
    final meta    = rawMeta is Map ? Map<String, dynamic>.from( rawMeta ) : <String, dynamic>{};

    // The email key eliminates the identical-question-from-another-user case
    // outright. Round 1's one-live-question guard closes the remainder; round 2
    // lifts that guard and must re-open this question.
    final email = meta[ 'user_email' ] as String?;
    if ( _userEmail != null && email != null && email != _userEmail ) return false;

    final question  = meta[ 'question_text' ] as String?;
    final sessionId = meta[ 'session_id' ]    as String?;
    final mine      = ( question != null && question == live )
                   || ( sessionId != null && _ws.sessionId != null && sessionId == _ws.sessionId );
    return mine;
  }

  void _insertBuffered( Map<String, dynamic> frame ) {
    final now = _now();
    _buffer.removeWhere( ( b ) => now.difference( b.at ) > bufferTtl );
    _buffer.add( _BufferedFrame( frame, now ) );
    while ( _buffer.length > bufferCap ) {
      _buffer.removeAt( 0 );
    }
  }

  List<Map<String, dynamic>> _drainBufferFor( String jobId ) {
    final now  = _now();
    final mine = _buffer
        .where( ( b ) => now.difference( b.at ) <= bufferTtl )
        .map( ( b ) => b.frame )
        .where( ( f ) => f[ 'job_id' ] == jobId )
        .toList();
    _buffer.clear();

    // Fold in RANK order, not arrival order: the wire can reorder, and the
    // fold's monotonic guard would otherwise drop a late-arriving earlier
    // frame that carried metadata we want.
    mine.sort( ( a, b ) {
      final ra = JobLifecycleState.parse( a[ 'to_state' ] as String? )?.rank ?? -1;
      final rb = JobLifecycleState.parse( b[ 'to_state' ] as String? )?.rank ?? -1;
      return ra.compareTo( rb );
    } );
    return mine;
  }

  // ── Fold ─────────────────────────────────────────────────────────────────

  /// Rank-monotonic: apply a frame only when it outranks the current state.
  /// Terminals always apply. Duplicates and reorders become no-ops; a missed
  /// `running` is repaired by `completed` landing directly.
  QuickAskEntry _fold( QuickAskEntry current, QuickAskEntry incoming ) {
    if ( current.isTerminal ) return current;
    final advances = incoming.isTerminal || incoming.state.rank > current.state.rank;
    if ( !advances ) return current;
    return incoming.copyWith(
      // Keep the transcript we submitted; a frame's own question_text is the
      // server's echo and can be null on some paths.
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
    if ( jobId != live ) return;      // another user's job, or another of ours

    final incoming = QuickAskEntry.fromTransition( frame, questionText: state.liveQuestion ?? '' );
    if ( incoming == null ) return;   // unknown to_state ⇒ drop the frame

    final current = state.liveEntry;
    if ( current == null ) return;

    final folded = _fold( current, incoming );
    if ( identical( folded, current ) ) {
      // No advance — still proof of life, so the ladder resets.
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

  // ── Notifications: the belt channel + the watchdog reset ─────────────────

  Future<void> _onNotification( QuickAskNotificationReceived e, Emitter<QuickAskState> emit ) async {
    final n = e.notification;

    // AC-S1.4b — a question the server is waiting on is PROOF OF LIFE, and it
    // is the one thing that arrives in the window where no job id exists yet.
    // A watchdog armed at submission would fire into that silence with nothing
    // to reconcile: no job_id to look up, every probe "not found", and the UI
    // declaring `lost` on a request that is alive and waiting for the user.
    if ( n.responseRequested ) {
      emit( state.copyWith( pendingPromptId: n.id ) );
      _armWatchdog( reset: true );
      return;
    }

    // Belt channel — independent completion evidence whose `message` IS the
    // answer. One extra line rather than a second mechanism.
    final live = state.liveJobId;
    if ( live == null || n.jobId != live ) return;

    final current = state.liveEntry;
    if ( current == null || current.isTerminal ) return;

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

  // ── Watchdog ─────────────────────────────────────────────────────────────

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

    // 🔴 `getJobHistoryEntry` is the WRONG door and will 404: PostgreSQL
    // persistence is gated on `is_agentic_job_type()` against a 10-entry
    // allowlist, and a plain question is not an agentic type — no row is ever
    // written. The queue listings are the working door.
    final found = await _reconcile( jobId );

    if ( found == null ) {
      // ── found NOWHERE: decrement toward `lost` ──
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
      _armWatchdog();          // back off, rearm — NOT a reset
      return;
    }

    // ── found ALIVE or TERMINAL ──
    final current = state.liveEntry;

    if ( !found.isTerminal ) {
      // 🔴 POSITIVE PROOF OF LIFE. The server can SEE the job, so this RESETS
      // the ladder and clears the strike count. Running found-alive and
      // found-nowhere down one shared rearm path would declare a plainly
      // running job `lost` — they are opposite signals and cannot share a
      // branch.
      //
      // And a non-terminal reconcile NEVER overrides a terminal folded state:
      // a `completed` frame we actually received is not undone by a listing
      // that has not caught up.
      if ( current != null && !current.isTerminal ) emit( _replaceEntry( _fold( current, found ) ) );
      _armWatchdog( reset: true );
      return;
    }

    // A TERMINAL reconcile result WINS over a non-terminal folded state — the
    // listing is the server's own record, and we are only here because frames
    // went missing.
    if ( current != null && !current.isTerminal ) {
      emit( _replaceEntry( found.copyWith( questionText: current.questionText ) ) );
    }
    _cancelWatchdog();
  }

  /// done → dead → run → todo, stopping at the first hit.
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
        // A listing that errors tells us nothing either way — it is not
        // evidence of absence, so it must not become a strike here. Move on.
        continue;
      }
    }
    return null;
  }

  // ── Misc ─────────────────────────────────────────────────────────────────

  Future<void> _onConnectionChanged( QuickAskConnectionChanged e, Emitter<QuickAskState> emit ) async {
    emit( state.copyWith( connected: e.connected ) );
  }

  Future<void> _onErrorDismissed( QuickAskErrorDismissed e, Emitter<QuickAskState> emit ) async {
    emit( state.copyWith( clearError: true ) );
  }

  @override
  Future<void> close() {
    _watchdog?.cancel();
    _connSub?.cancel();
    return super.close();
  }
}
