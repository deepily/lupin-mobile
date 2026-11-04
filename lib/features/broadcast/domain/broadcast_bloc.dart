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

/// An input to [BroadcastBloc].
sealed class BroadcastEvent {
  /// Creates an event.
  const BroadcastEvent();
}

/// Read who is listening: on pane-visible, pull-to-refresh or the refresh button.
class BroadcastRosterRequested extends BroadcastEvent {
  /// The cancel token for the read, or null.
  final CancelToken? cancelToken;

  /// Creates the event.
  const BroadcastRosterRequested( { this.cancelToken } );
}

/// The operator typed, or the mic filled the box.
class BroadcastBodyChanged extends BroadcastEvent {
  /// The new body text.
  final String body;

  /// Creates the event.
  const BroadcastBodyChanged( this.body );
}

/// Mic pressed; pressing again stops and transcribes.
class BroadcastMicToggled extends BroadcastEvent {
  /// Creates the event.
  const BroadcastMicToggled();
}

/// Send, after the confirm modal has been answered.
///
/// The confirm belongs to the pane, not the bloc, as with the Holding Area's batch gate.
/// A bloc that popped its own dialog could not be tested without a widget tree. A pane that
/// dispatched before confirming would put the gate where a later hand can skip it.
class BroadcastSendConfirmed extends BroadcastEvent {
  /// Creates the event.
  const BroadcastSendConfirmed();
}

/// A `commons_broadcast_ack` frame arrived on the notification socket.
class BroadcastAckReceived extends BroadcastEvent {
  /// The ack.
  final BroadcastAck ack;

  /// Creates the event.
  const BroadcastAckReceived( this.ack );
}

/// The listening window broke: the app backgrounded or the socket dropped.
///
/// The whole acceptance clause hangs on this event. It fetches nothing, and it cannot be
/// undone for the broadcast it lands on, except by [BroadcastAcksReconcileRequested].
class BroadcastListeningInterrupted extends BroadcastEvent {
  /// Creates the event.
  const BroadcastListeningInterrupted();
}

/// The listening window closed again: the app resumed or the socket came back.
///
/// It is the counterpart to [BroadcastListeningInterrupted], and the reason that one is not
/// permanent. It fetches: it reads the saved acks for the broadcast on screen from
/// `GET /api/notifications/broadcast-acks/{id}` and folds them in.
class BroadcastAcksReconcileRequested extends BroadcastEvent {
  /// Creates the event.
  const BroadcastAcksReconcileRequested();
}

/// Recent commons traffic for the activity strip.
class BroadcastHistoryRequested extends BroadcastEvent {
  /// Creates the event.
  const BroadcastHistoryRequested();
}

// ─── State ───────────────────────────────────────────────────────────────────

/// What the mic is doing.
enum MicState {
  /// Not recording.
  idle,

  /// Recording.
  listening,

  /// Recording stopped and the transcription is pending.
  transcribing
}

/// The Broadcast pane's state.
class BroadcastState extends Equatable {
  /// The message being composed.
  final String body;

  /// Who is listening.
  final ActiveSessionRoster roster;

  /// True while the roster read is in flight.
  final bool rosterLoading;

  /// Why the roster read failed, or null.
  ///
  /// The failure is its own field because Send is disabled on `hasBody && hasRecipients`, so
  /// a failed read leaves Send dead. On the web the reason lives in a tooltip, which a phone
  /// cannot show. A stale fetch on flaky LTE would leave the operator holding a typed
  /// message and a dead button with no reachable explanation.
  final String? rosterError;

  /// What the mic is doing.
  final MicState mic;

  /// Why the mic failed, or null.
  final String? micError;

  /// True while a send is in flight.
  final bool sending;

  /// Why the send failed, or null.
  final String? sendError;

  /// Seconds the server asked us to wait, set when it rate-limited the send.
  ///
  /// It is distinct from [sendError] because "wait 31 seconds" and "that did not send" are
  /// different instructions.
  final int? rateLimitedForSeconds;

  /// The tally for the most recent broadcast, or null before anything was sent.
  final AckAggregate? aggregate;

  /// Recent commons traffic for the activity strip.
  final List<Map<String, dynamic>> history;

  /// True when the server's kill switch is on; distinct from an empty [history].
  final bool historyDisabled;

  /// True once a history read has answered.
  ///
  /// An empty [history] then means "quiet" and not "not asked yet".
  final bool historyLoaded;

  /// Creates the state; everything defaults to empty.
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

  /// True when the body has non-blank text.
  bool get hasBody       => body.trim().isNotEmpty;

  /// True when at least one session is live.
  bool get hasRecipients => roster.count > 0;

  /// True when Send is enabled.
  ///
  /// It needs two conditions, a body and a recipient, and no send in flight. A Send built
  /// on the body alone is tappable with zero live sessions and the confirm silently no-ops.
  bool get canSend => hasBody && hasRecipients && !sending;

  /// Why Send is dead, in words, or null when it is alive.
  ///
  /// Ensures:
  ///   - returns null exactly when [canSend] is true
  ///   - never returns a tooltip-shaped fragment; it is rendered visibly beside the button,
  ///     because a phone cannot hover
  String? get disabledReason {
    // The null arm comes before the explanations. Without it the getter falls through to
    // "Nobody is listening" on the happy path, a live Send button beside a sentence saying
    // it cannot send. A test pins "enabled produces no reason", the half of the contract
    // that is easy to leave untested because nothing looks wrong until both conditions hold.
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

  /// Copies the state with changes; the `clear...` flags drop a field to null.
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
  // Equality compares the whole objects, not summaries of them. The list once held
  // `roster.count`, `aggregate?.ackedCount` and `history.length`, each a number standing in
  // for a value, and bloc skips an emit when the new state compares equal. A change that
  // kept the number identical was silently dropped and the pane never rebuilt. Three cases:
  // a seat re-acks with a `body_summary` it did not send the first time (same session, same
  // count); one seat leaves and another joins between refreshes, so the confirm modal names
  // the wrong people; five history entries are replaced by five different ones. The models
  // carry value equality, so the objects compare directly.
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
/// There is no poll timer in this bloc, and that is the design. Acks ride the
/// `notification_queue_update` socket stream this client already holds open. The pane still
/// needs the lifecycle half of the usual story, not to stop a timer. A socket that silently
/// stops looks like a quiet fleet, and on a phone it stops every time the app backgrounds.
class BroadcastBloc extends Bloc<BroadcastEvent, BroadcastState> {
  final BroadcastRepository _repo;
  final VoiceCaptureSession? _voice;

  StreamSubscription<AppLifecycleState>? _lifecycleSub;
  StreamSubscription<bool>?              _socketSub;

  /// The app lifecycle stream; a test seam that defaults to the app-wide singleton.
  Stream<AppLifecycleState> get lifecycleStream => AppLifecycleService().lifecycleStream;

  /// Creates the bloc; [voice] is the mic, or null when voice input is not available.
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

  /// Starts watching for the listening window breaking and closing; idempotent.
  ///
  /// `AckConfidence.interrupted` is dead code until something fires it, and the pane itself
  /// cannot know the window broke. Two signals can. One is the app leaving the foreground,
  /// where the OS suspends the socket. The other is the socket dropping while foregrounded.
  /// Calling it twice replaces the subscriptions instead of doubling them.
  ///
  /// `inactive` is not treated as an interruption, which is the one judgement call here.
  /// Flutter sends `inactive` for transient interruptions such as a notification-shade pull
  /// or an incoming-call banner, and these do not suspend the socket. Treating it as a
  /// break would make the pane cry wolf on every shade pull, and a guard that fires
  /// constantly gets ignored. `paused`, `hidden` and `detached` are where delivery stops.
  /// If the judgement is wrong, the failure is a false negative, a tally presented as exact
  /// when it is not. Nobody has measured it on hardware, so check a real device.
  void startListeningWatch( { Stream<bool>? socketStream } ) {
    _lifecycleSub?.cancel();
    _lifecycleSub = lifecycleStream.listen( ( state ) {
      if ( state == AppLifecycleState.resumed ) {
        // Coming back is the other half, and on a phone the common half: the OS suspended
        // the socket, acks were pushed at nobody, and this is the first moment anything can
        // ask what was missed.
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

  // The roster comes first and the history follows it, sequenced and not concurrent. The
  // roster gates the Send button and is what the operator waits for, while the Recent
  // Activity strip is decoration below the fold, and issuing both on first paint makes them
  // compete for one scarce phone connection. A widget test surfaced the ordering: two bloc
  // handlers each awaiting a Dio call, started in the same fake-async turn, never complete.
  // The pane sits on "Sending to: ..." forever and the test dies with pending timers and a
  // runner hang. One such handler completes fine, and two raw concurrent `dio.get` calls
  // outside a bloc complete fine. The bloc/Dio/fake-async interaction below that is not
  // root-caused. If the sequencing is removed for a good reason, the widget tests will hang
  // again, and this comment is the map.
  Future<void> _onRoster( BroadcastRosterRequested e, Emitter<BroadcastState> emit ) async {
    emit( state.copyWith( rosterLoading: true, clearRosterError: true ) );
    try {
      final roster = await _repo.fetchActiveSessions( cancelToken: e.cancelToken );
      emit( state.copyWith( roster: roster, rosterLoading: false ) );
      add( const BroadcastHistoryRequested() );
    } on DioException catch ( err ) {
      // A cancellation is the lifecycle rule working: drop it silently, instead of painting
      // a banner every time the operator backgrounds the app.
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
        // Append, never replace. The operator may have typed a first line and then reached
        // for the mic, and replacing would silently destroy the half they typed.
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

    // Captured before the await: the roster can refresh mid-flight, and the tally must be
    // denominated in what was actually sent to.
    final recipientsAtSend = state.roster.count;

    emit( state.copyWith( sending: true, clearSendError: true, clearRateLimit: true ) );
    try {
      final result = await _repo.send( message: state.body.trim() );

      emit( state.copyWith(
        sending   : false,
        body      : '',
        aggregate : AckAggregate(
          broadcastId      : result.broadcastId,
          // The clock the expired-versus-partial decision runs on, recorded when the server
          // accepted the send and not at first paint.
          sentAt           : DateTime.now(),
          // The server's count, not the roster's. The roster is what we could see and
          // `recipients` is what the server enumerated, and they differ whenever a seat went
          // quiet between the refresh and the send.
          recipientsAtSend : result.recipients > 0 ? result.recipients : recipientsAtSend,
        ),
        // `queued` is not a delivery receipt. A partial fanout is reported here, not
        // swallowed, because the status field alone would read as success.
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
      // The body is not cleared: the operator's words survive a failure.
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

  // Reads the saved acks and folds them in. The failure arm is the one that matters, so it
  // does not swallow quietly. A failed read must leave the tally exactly as interrupted as
  // it found it. The tempting shape, catch and carry on, produces a pane saying "2 of 5
  // acked" in a confident voice after a read that never answered, the false precision
  // [AckConfidence.interrupted] exists to prevent. So the catch arms emit nothing: no state
  // change is the correct outcome of a failed recovery. With no aggregate on screen there is
  // no broadcast to reconcile and it does nothing. A server error, a transport failure or a
  // cancellation leaves confidence alone.
  Future<void> _onReconcile( BroadcastAcksReconcileRequested e, Emitter<BroadcastState> emit ) async {
    final agg = state.aggregate;
    if ( agg == null || agg.broadcastId.isEmpty ) return;

    try {
      final saved = await _repo.drainMissedAcks( agg.broadcastId );
      // Re-read from state: the fetch was awaited, and a live ack may have folded while it
      // was in flight.
      final current = state.aggregate;
      if ( current == null || current.broadcastId != agg.broadcastId ) return;

      // The seats that moved during the read keep what arrived, and this is the one place
      // that can know which those are. `agg` is the tally when the request went out and
      // `current` is the tally now, so anything that differs arrived while the server was
      // answering and is newer than the response. The ordinary saved-wins rule would roll it
      // back, turning a `completed` into the `pending` the server held when asked. The count
      // is the same either way, so nothing that counts acks would catch it.
      final arrivedDuringRead = <String>{
        for ( final seat in current.acksBySession.entries )
          if ( agg.acksBySession[ seat.key ] != seat.value ) seat.key,
      };

      emit( state.copyWith(
        aggregate: current.reconciled( saved, keepLive: arrivedDuringRead ),
      ) );
    } on BroadcastException {
      // Stays interrupted; see the comment above.
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
      // The activity strip is decoration, and a failure here must not disturb compose.
    } on DioException {
      // Same, including cancellation.
    }
  }
}
