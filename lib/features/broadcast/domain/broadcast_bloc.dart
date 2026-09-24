import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../../services/lifecycle/app_lifecycle_service.dart';

import '../../../services/asr/voice_capture_session.dart';
import '../data/broadcast_models.dart';
import '../data/broadcast_repository.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

sealed class BroadcastEvent {
  const BroadcastEvent();
}

/// Read who is listening. Pane-visible, pull-to-refresh, or the ↻ beside "Sending to:".
class BroadcastRosterRequested extends BroadcastEvent {
  final CancelToken? cancelToken;
  const BroadcastRosterRequested( { this.cancelToken } );
}

/// The operator typed, or the mic filled the box.
class BroadcastBodyChanged extends BroadcastEvent {
  final String body;
  const BroadcastBodyChanged( this.body );
}

/// Mic pressed. Press again to stop and transcribe.
class BroadcastMicToggled extends BroadcastEvent {
  const BroadcastMicToggled();
}

/// Send, AFTER the confirm modal has been answered.
///
/// The confirm is the pane's, not the bloc's — same reasoning as the Holding Area's
/// batch gate. A bloc that popped its own dialog could not be tested without a widget
/// tree, and a pane that dispatched before confirming would put the gate somewhere a
/// later hand can skip.
class BroadcastSendConfirmed extends BroadcastEvent {
  const BroadcastSendConfirmed();
}

/// A `commons_broadcast_ack` frame arrived on the notification socket.
class BroadcastAckReceived extends BroadcastEvent {
  final BroadcastAck ack;
  const BroadcastAckReceived( this.ack );
}

/// 🔴 THE LISTENING WINDOW BROKE — backgrounded, or the socket dropped.
///
/// This is the event the whole acceptance clause hangs on. It does not fetch anything and
/// it cannot be undone for the broadcast it lands on.
class BroadcastListeningInterrupted extends BroadcastEvent {
  const BroadcastListeningInterrupted();
}

/// 🔴 THE LISTENING WINDOW CLOSED AGAIN — resumed, or the socket came back.
///
/// The counterpart to [BroadcastListeningInterrupted], and the reason that one is no
/// longer permanent. This DOES fetch: it reads the saved acks for the broadcast on
/// screen (`GET /api/notifications/broadcast-acks/{id}`) and folds them in.
class BroadcastAcksReconcileRequested extends BroadcastEvent {
  const BroadcastAcksReconcileRequested();
}

/// Recent commons traffic for the activity strip.
class BroadcastHistoryRequested extends BroadcastEvent {
  const BroadcastHistoryRequested();
}

// ─── State ───────────────────────────────────────────────────────────────────

enum MicState { idle, listening, transcribing }

class BroadcastState extends Equatable {
  final String body;
  final ActiveSessionRoster roster;
  final bool rosterLoading;

  /// 🔴 WHY THE ROSTER'S FAILURE IS ITS OWN FIELD. Send is disabled on
  /// `hasBody && hasRecipients`, so a failed roster fetch leaves Send dead. On the web
  /// the reason lives in `btn.title` — a tooltip, which a phone has no way to show. A
  /// stale fetch on flaky LTE would leave the operator holding a typed message and a
  /// dead button with no reachable explanation.
  final String? rosterError;

  final MicState mic;
  final String? micError;

  final bool sending;
  final String? sendError;

  /// Set when the server rate-limited us. Distinct from [sendError] because "wait 31
  /// seconds" and "that did not send" are different instructions.
  final int? rateLimitedForSeconds;

  /// The tally for the most recent broadcast, or null before anything was sent.
  final AckAggregate? aggregate;

  final List<Map<String, dynamic>> history;

  /// The server's kill switch is on — distinct from an empty [history].
  final bool historyDisabled;

  /// A history read has answered at least once, so an empty [history] means "quiet"
  /// rather than "not asked yet".
  final bool historyLoaded;

  const BroadcastState( {
    this.body                  = '',
    this.roster                = const ActiveSessionRoster.empty(),
    this.rosterLoading         = false,
    this.rosterError,
    this.mic                   = MicState.idle,
    this.micError,
    this.sending               = false,
    this.sendError,
    this.rateLimitedForSeconds,
    this.aggregate,
    this.history               = const [],
    this.historyDisabled       = false,
    this.historyLoaded         = false,
  } );

  bool get hasBody       => body.trim().isNotEmpty;
  bool get hasRecipients => roster.count > 0;

  /// 🔴 TWO CONDITIONS, NOT ONE (`broadcast-panel.js:228-238`). A Send built on the body
  /// alone is tappable with zero live sessions and the confirm silently no-ops.
  bool get canSend => hasBody && hasRecipients && !sending;

  /// Why Send is dead, in words, or null when it is alive.
  ///
  /// Ensures:
  ///   - returns null exactly when [canSend] is true
  ///   - never returns a tooltip-shaped fragment; this is rendered VISIBLY beside the
  ///     button, because a phone cannot hover
  String? get disabledReason {
    // 🔴 THE NULL ARM COMES FIRST, AND IT WAS MISSING. Without it this getter falls all
    // the way through to "Nobody is listening" on the HAPPY path — a live Send button
    // sitting beside a sentence saying it cannot send. Caught by the test that pins
    // "enabled produces no reason", which is the half of the contract easy to leave
    // untested because nothing looks wrong until both conditions are finally satisfied.
    if ( sending )  return 'Sending…';
    if ( canSend )  return null;

    if ( !hasBody && !hasRecipients ) {
      return 'Type a message — and nobody is listening right now.';
    }
    if ( !hasBody ) return 'Type a message first.';
    if ( rosterError != null ) {
      return 'Nobody to send to — the session list did not load. Tap ↻ to retry.';
    }
    return 'Nobody is listening right now. Tap ↻ to refresh.';
  }

  BroadcastState copyWith( {
    String? body,
    ActiveSessionRoster? roster,
    bool? rosterLoading,
    String? rosterError,
    bool clearRosterError = false,
    MicState? mic,
    String? micError,
    bool clearMicError = false,
    bool? sending,
    String? sendError,
    bool clearSendError = false,
    int? rateLimitedForSeconds,
    bool clearRateLimit = false,
    AckAggregate? aggregate,
    List<Map<String, dynamic>>? history,
    bool? historyDisabled,
    bool? historyLoaded,
  } ) {
    return BroadcastState(
      body                  : body ?? this.body,
      roster                : roster ?? this.roster,
      rosterLoading         : rosterLoading ?? this.rosterLoading,
      rosterError           : clearRosterError ? null : ( rosterError ?? this.rosterError ),
      mic                   : mic ?? this.mic,
      micError              : clearMicError ? null : ( micError ?? this.micError ),
      sending               : sending ?? this.sending,
      sendError             : clearSendError ? null : ( sendError ?? this.sendError ),
      rateLimitedForSeconds : clearRateLimit
          ? null
          : ( rateLimitedForSeconds ?? this.rateLimitedForSeconds ),
      aggregate             : aggregate ?? this.aggregate,
      history               : history ?? this.history,
      historyDisabled       : historyDisabled ?? this.historyDisabled,
      historyLoaded         : historyLoaded ?? this.historyLoaded,
    );
  }

  @override
  /// 🔴 THE WHOLE OBJECTS, NOT SUMMARIES OF THEM — AND THE SUMMARIES WERE A BUG.
  ///
  /// This list first read `roster.count`, `aggregate?.ackedCount` and `history.length`.
  /// Each is a NUMBER STANDING IN FOR A VALUE, and bloc skips an emit when the new state
  /// compares equal — so any change that kept the number identical was silently dropped
  /// and the pane never rebuilt. Three real cases, none of them exotic:
  ///
  ///   · a seat RE-acks with a `body_summary` it did not send the first time. Same
  ///     session, so the count stays 1, so no rebuild, so the summary never appears.
  ///   · one seat leaves and another joins between refreshes. Still 3, so no rebuild —
  ///     and the confirm modal then names the WRONG PEOPLE, which is the one screen whose
  ///     entire job is telling the operator who is about to be interrupted.
  ///   · five history entries replaced by five different ones. Still 5, so no rebuild.
  ///
  /// ⇒ The models carry value equality now, so the objects can be compared directly and
  /// a summary can no longer hide a change behind a matching integer.
  @override
  List<Object?> get props => [
    body, roster, rosterLoading, rosterError, mic, micError,
    sending, sendError, rateLimitedForSeconds,
    aggregate, history, historyDisabled, historyLoaded,
  ];
}

// ─── Bloc ────────────────────────────────────────────────────────────────────

/// Compose, mic, send, and a tally that refuses to lie about itself.
///
/// 🔴 THERE IS NO POLL TIMER IN THIS BLOC, AND ITS ABSENCE IS THE DESIGN. Acks ride the
/// `notification_queue_update` socket stream this client already holds open; for this one
/// pane socket-first is how the feature works rather than an optimisation. The pane still
/// needs the LIFECYCLE half of the usual story — not to stop a timer, but because a
/// socket that silently stops is indistinguishable from a quiet fleet, and on a phone it
/// stops routinely, by OS design, every time the app backgrounds.
class BroadcastBloc extends Bloc<BroadcastEvent, BroadcastState> {
  final BroadcastRepository _repo;
  final VoiceCaptureSession? _voice;

  StreamSubscription<AppLifecycleState>? _lifecycleSub;
  StreamSubscription<bool>?              _socketSub;

  /// Test seams. Default to the app-wide singletons, which is what production uses.
  Stream<AppLifecycleState> get lifecycleStream => AppLifecycleService().lifecycleStream;

  BroadcastBloc( this._repo, { VoiceCaptureSession? voice } )
      : _voice = voice,
        super( const BroadcastState() ) {
    on<BroadcastRosterRequested>( _onRoster );
    on<BroadcastBodyChanged>( _onBody );
    on<BroadcastMicToggled>( _onMic );
    on<BroadcastSendConfirmed>( _onSend );
    on<BroadcastAckReceived>( _onAck );
    on<BroadcastListeningInterrupted>( _onInterrupted );
    on<BroadcastAcksReconcileRequested>( _onReconcile );
    on<BroadcastHistoryRequested>( _onHistory );
  }

  /// 🔴 THE ACCEPTANCE CLAUSE IS DEAD CODE UNTIL SOMETHING FIRES IT.
  ///
  /// `AckConfidence.interrupted` is the whole point of this pane, and nothing in the
  /// pane itself can know the listening window broke. Two signals can:
  ///
  ///   · the app leaving the foreground — the OS suspends the socket, by design, and on
  ///     a phone this is the ordinary case rather than an edge one;
  ///   · the socket dropping while still foregrounded — a network blip.
  ///
  /// ⚠️ `inactive` IS DELIBERATELY NOT TREATED AS AN INTERRUPTION, and this is the one
  /// judgement call in here. Flutter delivers `inactive` for transient interruptions — a
  /// notification-shade pull, an incoming-call banner — which do NOT suspend the socket.
  /// Treating it as a break would make the pane cry wolf on every shade pull, and a guard
  /// that fires constantly is one people learn to ignore, which converts it into no guard
  /// at all. `paused`, `hidden` and `detached` are the states where delivery actually
  /// stops.
  ///
  /// ⇒ If that judgement is ever shown wrong, the failure is a FALSE NEGATIVE — a tally
  /// presented as exact when it is not — so it is worth re-checking against a real device
  /// rather than trusting this comment. Nobody has measured it on hardware.
  ///
  /// Idempotent: calling it twice replaces the subscriptions rather than doubling them.
  void startListeningWatch( { Stream<bool>? socketStream } ) {
    _lifecycleSub?.cancel();
    _lifecycleSub = lifecycleStream.listen( ( state ) {
      if ( state == AppLifecycleState.resumed ) {
        // Coming BACK is the other half, and for a phone it is the common half: the OS
        // suspended the socket, acks were pushed at nobody, and this is the first moment
        // anything can ask what was missed.
        add( const BroadcastAcksReconcileRequested() );
        return;
      }
      if ( state != AppLifecycleState.inactive ) {
        add( const BroadcastListeningInterrupted() );
      }
    } );

    if ( socketStream != null ) {
      _socketSub?.cancel();
      _socketSub = socketStream.listen( ( connected ) {
        add( connected
            ? const BroadcastAcksReconcileRequested()
            : const BroadcastListeningInterrupted() );
      } );
    }
  }

  @override
  Future<void> close() {
    _lifecycleSub?.cancel();
    _socketSub?.cancel();
    return super.close();
  }

  /// 🔴 THE ROSTER COMES FIRST AND THE HISTORY FOLLOWS IT — SEQUENCED, NOT CONCURRENT.
  ///
  /// On its merits: the roster gates the Send button and is the thing the operator is
  /// waiting for; the Recent Activity strip is decoration below the fold. Issuing both on
  /// first paint makes them compete for one scarce phone connection to render something
  /// nobody is looking at yet.
  ///
  /// ⚠️ BUT BE HONEST ABOUT WHAT SURFACED IT: a widget test, not a phone. Two bloc
  /// handlers each awaiting a Dio call, started in the same fake-async turn, NEVER
  /// COMPLETE — the pane sits on "Sending to: …" forever and the test dies with pending
  /// timers and a runner hang that reports *"the Dart compiler exited unexpectedly"*.
  /// Bounded by controls on both sides: ONE such handler completes fine, and TWO raw
  /// concurrent `dio.get` calls outside a bloc complete fine. I did not root-cause the
  /// bloc/Dio/fake-async interaction below that statement, and I am not claiming to have.
  ///
  /// ⇒ So this ordering is justified by the product argument above and merely REVEALED by
  /// the harness. If someone later removes the sequencing for a good reason, the widget
  /// tests will hang again and this paragraph is the map.
  Future<void> _onRoster( BroadcastRosterRequested e, Emitter<BroadcastState> emit ) async {
    emit( state.copyWith( rosterLoading: true, clearRosterError: true ) );
    try {
      final roster = await _repo.fetchActiveSessions( cancelToken: e.cancelToken );
      emit( state.copyWith( roster: roster, rosterLoading: false ) );
      add( const BroadcastHistoryRequested() );
    } on DioException catch ( err ) {
      // A cancellation is the lifecycle rule working. Silently drop it rather than
      // painting a banner every time the operator backgrounds the app.
      if ( CancelToken.isCancel( err ) ) {
        emit( state.copyWith( rosterLoading: false ) );
        return;
      }
      emit( state.copyWith( rosterLoading: false, rosterError: 'could not load sessions' ) );
    } on BroadcastException {
      emit( state.copyWith( rosterLoading: false, rosterError: 'could not load sessions' ) );
    }
  }

  void _onBody( BroadcastBodyChanged e, Emitter<BroadcastState> emit ) {
    emit( state.copyWith( body: e.body, clearSendError: true, clearRateLimit: true ) );
  }

  Future<void> _onMic( BroadcastMicToggled e, Emitter<BroadcastState> emit ) async {
    final voice = _voice;
    if ( voice == null ) {
      emit( state.copyWith( micError: 'voice input is not available' ) );
      return;
    }

    if ( state.mic == MicState.listening ) {
      emit( state.copyWith( mic: MicState.transcribing ) );
      final capture = await voice.stopAndTranscribe();

      if ( capture.wasHeard ) {
        // 🔴 APPEND, NEVER REPLACE. The operator may have typed a first line and then
        // reached for the mic; replacing would silently destroy it, and the destroyed
        // text is the half they bothered to type.
        final heard = capture.transcript!.trim();
        final next  = state.body.trim().isEmpty ? heard : '${state.body.trimRight()} $heard';
        emit( state.copyWith( body: next, mic: MicState.idle, clearMicError: true ) );
      } else {
        emit( state.copyWith(
          mic      : MicState.idle,
          micError : capture.errorMessage ?? 'nothing was heard',
        ) );
      }
      return;
    }

    final start = await voice.start();
    if ( start.started ) {
      emit( state.copyWith( mic: MicState.listening, clearMicError: true ) );
    } else {
      emit( state.copyWith(
        mic      : MicState.idle,
        micError : start.errorMessage ?? 'the microphone did not start',
      ) );
    }
  }

  Future<void> _onSend( BroadcastSendConfirmed e, Emitter<BroadcastState> emit ) async {
    if ( !state.canSend ) return;

    // Captured BEFORE the await: the roster can refresh mid-flight, and the tally must
    // be denominated in what we actually sent to.
    final recipientsAtSend = state.roster.count;

    emit( state.copyWith( sending: true, clearSendError: true, clearRateLimit: true ) );
    try {
      final result = await _repo.send( message: state.body.trim() );

      emit( state.copyWith(
        sending   : false,
        body      : '',
        aggregate : AckAggregate(
          broadcastId      : result.broadcastId,
          // The clock the expired-vs-partial decision runs on. Recorded at the moment
          // the server accepted the send, not at first paint.
          sentAt           : DateTime.now(),
          // 🔴 THE SERVER'S COUNT, NOT THE ROSTER'S. The roster is what we could see;
          // `recipients` is what the server actually enumerated, and they differ whenever
          // a seat went quiet between the refresh and the send.
          recipientsAtSend : result.recipients > 0 ? result.recipients : recipientsAtSend,
        ),
        // `queued` is not a delivery receipt. A partial fanout is reported here rather
        // than swallowed, because the status field alone would read as success.
        sendError : result.hasFailures
            ? '${result.failedRecipients.length} session(s) could not be reached.'
            : null,
      ) );
    } on BroadcastRateLimited catch ( err ) {
      emit( state.copyWith(
        sending               : false,
        rateLimitedForSeconds : err.retryAfterSeconds ?? 0,
      ) );
    } on BroadcastException {
      // The body is deliberately NOT cleared — the operator's words survive a failure.
      emit( state.copyWith( sending: false, sendError: 'the broadcast was not sent' ) );
    }
  }

  void _onAck( BroadcastAckReceived e, Emitter<BroadcastState> emit ) {
    final agg = state.aggregate;
    if ( agg == null ) return;
    emit( state.copyWith( aggregate: agg.fold( e.ack ) ) );
  }

  void _onInterrupted( BroadcastListeningInterrupted e, Emitter<BroadcastState> emit ) {
    final agg = state.aggregate;
    if ( agg == null ) return;
    emit( state.copyWith( aggregate: agg.interrupted() ) );
  }

  /// 🔴 THE FAILURE ARM IS THE ONE THAT MATTERS, AND IT IS WHY THIS DOES NOT SWALLOW.
  ///
  /// A read that fails must leave the tally EXACTLY as interrupted as it found it. The
  /// tempting shape — catch, log nothing, carry on — produces a pane that says "2 of 5
  /// acked" in the confident voice after a read that never answered, which is the same
  /// false precision [AckConfidence.interrupted] exists to prevent, arrived at by a new
  /// route. So the catch arms deliberately emit nothing: no state change IS the correct
  /// outcome of a failed recovery.
  ///
  /// Ensures:
  ///   - no aggregate on screen → does nothing (there is no broadcast to reconcile)
  ///   - a successful read folds the saved acks in and lifts confidence
  ///   - a server error, a transport failure or a cancellation leaves confidence alone
  Future<void> _onReconcile( BroadcastAcksReconcileRequested e, Emitter<BroadcastState> emit ) async {
    final agg = state.aggregate;
    if ( agg == null || agg.broadcastId.isEmpty ) return;

    try {
      final saved = await _repo.drainMissedAcks( agg.broadcastId );
      // Re-read from state: the fetch was awaited, and a live ack may have folded while
      // it was in flight.
      final current = state.aggregate;
      if ( current == null || current.broadcastId != agg.broadcastId ) return;

      emit( state.copyWith( aggregate: current.reconciled( saved ) ) );
    } on BroadcastException {
      // Stays interrupted. See the note above.
    } on DioException {
      // Same, including cancellation.
    }
  }

  Future<void> _onHistory( BroadcastHistoryRequested e, Emitter<BroadcastState> emit ) async {
    try {
      final read = await _repo.fetchHistory();
      emit( state.copyWith(
        history         : read.entries,
        historyDisabled : read.disabled,
        historyLoaded   : true,
      ) );
    } on BroadcastException {
      // The activity strip is decoration. A failure here must not disturb compose.
    } on DioException {
      // Same, including cancellation.
    }
  }
}
