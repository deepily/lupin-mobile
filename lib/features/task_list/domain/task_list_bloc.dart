import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../fleet_status/data/fleet_models.dart';
import '../../fleet_status/data/fleet_repository.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../../fleet/domain/pane_visibility_mixin.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/domain/unsent_write.dart';
import '../data/new_ticket.dart';
import '../data/task_list_model.dart';
import '../data/task_list_repository.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

/// An input to [TaskListBloc].
sealed class TaskListEvent {
  /// Creates an event.
  const TaskListEvent();
}

/// A poll tick, a pull-to-refresh, or a resume.
class TaskListRefreshRequested extends TaskListEvent {
  /// The poll's cancel token, or null for a manual refresh.
  final CancelToken? cancelToken;

  /// Creates the event.
  const TaskListRefreshRequested( { this.cancelToken } );
}

/// The operator folded or unfolded a group.
class TaskListGroupToggled extends TaskListEvent {
  /// The label of the toggled group.
  final String groupLabel;

  /// Creates the event.
  const TaskListGroupToggled( this.groupLabel );
}

/// An operator pressed a status verb on a row; it goes through the transition door.
class TaskListVerbPressed extends TaskListEvent {
  /// The row the verb applies to.
  final String taskId;

  /// The built verb payload.
  final TaskVerb verb;

  /// Creates the event.
  const TaskListVerbPressed( { required this.taskId, required this.verb } );
}

/// The connection came back; resend what the network ate.
///
/// It is its own event, not a limb of the refresh, because the two do opposite things.
/// One sends the operator's work to the server and the other pulls the server's state
/// back. Folding them together would make a pull-to-refresh also write.
class TaskListUnsentRetryRequested extends TaskListEvent {
  /// Creates the event.
  const TaskListUnsentRetryRequested();
}

/// Reads the live fleet, for the reassignment roster.
///
/// It is its own event, not a limb of the poll, because it is a different service on a
/// different cadence. The board polls every 60 s on Wi-Fi and 180 s on mobile data. The
/// roster changes only when a seat is spawned or reaped, which is rare.
class TaskListRosterRequested extends TaskListEvent {
  /// Creates the event.
  const TaskListRosterRequested();
}

/// An operator changed a row's priority or owner; it goes through the field door.
class TaskListFieldChanged extends TaskListEvent {
  /// The row that changed.
  final String taskId;

  /// The new priority, or null when the owner changed.
  final String? priority;

  /// The new owner, or null when the priority changed.
  final String? ownerPersona;

  /// Creates the event.
  const TaskListFieldChanged( { required this.taskId, this.priority, this.ownerPersona } );
}

// ─── State ───────────────────────────────────────────────────────────────────

/// The Task List pane's state.
class TaskListState extends Equatable {
  /// The grouped rows, or null before the first fetch lands.
  final TaskListModel? model;

  /// True while a fetch is in flight.
  final bool loading;

  /// The latest failure text, or null.
  final String? error;

  /// True when the page is not the whole board; surfaced as a visible banner.
  final bool incomplete;

  /// The server's true row count for the query.
  final int total;

  /// Group labels the operator has collapsed.
  ///
  /// Collapsed state belongs to the operator and survives a refresh. A poll that
  /// re-expanded every group would undo their work every sixty seconds.
  final Set<String> collapsed;

  /// Writes the operator made that never reached the server, keyed by task id.
  ///
  /// A failed transport write rolls the row back and also remembers the act, so the
  /// operator does not lose what they did. A second write on the same row replaces the
  /// first instead of queueing behind it, because there is no ordering guarantee.
  final Map<String, UnsentWrite> unsent;

  /// The personas a row may be reassigned to: the live fleet, alpha-sorted.
  ///
  /// Empty is a legitimate state, not a loading one. It means the phone cannot see the
  /// fleet (pre-first-read, unreachable arbiter, or nobody live), and the owner control
  /// shows only the row's current owner. Treating it as "not ready" would hide the control
  /// forever on a handset that never reaches the arbiter.
  final List<String> reassignTargets;

  /// Creates the state; everything defaults to empty.
  const TaskListState( {
    this.model,
    this.loading         = false,
    this.error,
    this.incomplete      = false,
    this.total           = 0,
    this.collapsed       = const <String>{},
    this.reassignTargets = const <String>[],
    this.unsent          = const <String, UnsentWrite>{},
  } );

  /// What the operator did to this row that has not landed, if anything.
  String? unsentLabelFor( String taskId ) => unsent[ taskId ]?.label;

  /// Copies the state with changes; [clearError] drops the error.
  TaskListState copyWith( {
    TaskListModel? model,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? incomplete,
    int? total,
    Set<String>? collapsed,
    List<String>? reassignTargets,
    Map<String, UnsentWrite>? unsent,
  } ) =>
      TaskListState(
        model           : model ?? this.model,
        loading         : loading ?? this.loading,
        error           : clearError ? null : ( error ?? this.error ),
        incomplete      : incomplete ?? this.incomplete,
        total           : total ?? this.total,
        collapsed       : collapsed ?? this.collapsed,
        reassignTargets : reassignTargets ?? this.reassignTargets,
        unsent          : unsent ?? this.unsent,
      );

  @override
  List<Object?> get props =>
      [ model, loading, error, incomplete, total, collapsed, reassignTargets, unsent ];
}

// ─── Bloc ────────────────────────────────────────────────────────────────────

/// The Task List pane's bloc.
///
/// Register it per route, not at the app root. Root-level blocs are `ServiceLocator`
/// singletons that outlive their route, so the timer would run whichever destination is
/// showing. Foreground-pane-only polling has no mechanism unless pane blocs are
/// route-scoped; see [PanePollingMixin].
class TaskListBloc extends Bloc<TaskListEvent, TaskListState>
    with PaneVisibilityMixin<TaskListEvent, TaskListState>,
        PanePollingMixin<TaskListEvent, TaskListState> {
  final TaskListRepository _repo;
  final TaskWriteRepository _writes;
  final NetworkConnectivityService _network;

  // The fleet read, for the reassignment roster only. It is optional, and a null one is
  // not a broken pane: the Task List's job is tasks, and the owner control degrades
  // without the roster. Requiring it would stop the pane rendering until a second service
  // answers, on a phone where that service is the likeliest to be unreachable.
  final FleetRepository? _fleet;

  StreamSubscription<NetworkState>? _connectivitySub;

  /// The network state before the latest edge; seeded from the service when [startConnectivityRefresh] first runs.
  NetworkState _previousNetworkState = NetworkState.unknown;

  /// Creates the bloc; [fleet] feeds the reassignment roster and may be null.
  TaskListBloc(
    this._repo,
    this._writes, {
    NetworkConnectivityService? network,
    FleetRepository? fleet,
  } )  : _network = network ?? NetworkConnectivityService(),
        _fleet   = fleet,
        super( const TaskListState() ) {
    on<TaskListRefreshRequested>( _onRefresh );
    on<TaskListGroupToggled>( _onToggle );
    on<TaskListVerbPressed>( _onVerb );
    on<TaskListFieldChanged>( _onField );
    on<TaskListRosterRequested>( _onRoster );
    on<TaskListUnsentRetryRequested>( _onRetryUnsent );
  }

  // The poll interval reads the connection, and the rule lives in [PanePollingMixin]. A
  // full 500-row page is about 2.1 MB and a terse one about 107 KB, so even terse at 60 s a
  // foreground hour is about 6.4 MB on one pane: fine on Wi-Fi, rude on a metered
  // connection. This bloc overrides only which network service to ask, because it already
  // holds an injected one for its connectivity-restored trigger and its tests fake it.
  @override
  bool get isMeteredConnection => _network.isMobile;

  /// Looks up one ticket by a path from `taskLookupPath`.
  ///
  /// It is a pass-through, not an event. The result belongs to the lookup box and never
  /// touches the board. Looked-up rows are usually not on it, and folding the answer into
  /// board state would make a held row look owed.
  Future<TaskRowModel> lookupTask( String path ) => _repo.lookup( path );

  /// Files one ticket from the New Ticket card, then refreshes the board.
  ///
  /// It is a pass-through like [lookupTask]: the outcome sentence belongs to the card. The
  /// refresh runs only on `created`, because a petition or a held row is not on the board.
  Future<NewTicketOutcome> createTicket( Map<String, String> payload ) async {
    final res     = await _repo.createTicket( payload );
    final outcome = describeNewTicketResult( res.status, res.body );
    if ( outcome.state == NewTicketState.created && !isClosed ) {
      add( const TaskListRefreshRequested() );
    }
    return outcome;
  }

  /// Who the card offers under "Assigned to", read when the card opens.
  ///
  /// That is the live fleet plus everyone who already owns a row.
  List<String> newTicketAssignees() => newTicketAssigneeOptions( [
    state.reassignTargets,
    ...( state.model?.groups ?? const <TaskGroup>[] ).map( ( g ) => [ g.ownerPersona ] ),
  ] );

  /// The mixin's poll hook.
  ///
  /// The token reaches Dio, so a pane that disappears mid-request cancels the request and
  /// not only the timer.
  @override
  Future<void> pollOnce( CancelToken token ) async {
    add( TaskListRefreshRequested( cancelToken: token ) );
  }

  /// Starts retrying unsent writes and refreshing when the connection is restored, `connected` or `limited`.
  ///
  /// The retry trigger is connectivity-restored, which `NetworkConnectivityService` already
  /// streams. The focus chat bloc's unsent-write shape fires on WebSocket re-auth, and this
  /// pane rides no socket, so its trigger does not carry over.
  void startConnectivityRefresh() {
    // A pane opens after the service has settled, so its first edge is judged against the state it opened in.
    if ( _connectivitySub == null ) _previousNetworkState = _network.currentState;
    _connectivitySub ??= _network.networkStateStream.listen( ( state ) {
      final previous        = _previousNetworkState;
      _previousNetworkState = state;
      // Only an edge to a usable network acts, and a repeat of the same state is not an edge. `limited` is
      // usable (Rick, 2026-10-09): the server may sit on a LAN with no internet. connected -> limited does
      // not act: that is the moment the server stopped answering, and a request would go into it.
      if ( !shouldRetryOnNetworkEdge( previous, state ) ) return;

      // The retry goes first. A refetch that lands before it repaints the board from the
      // server, which lacks the operator's write, so the row flickers back to its old value
      // and then changes again. Sending first makes the refetch include their action.
      add( const TaskListUnsentRetryRequested() );
      add( const TaskListRefreshRequested() );
    } );
  }

  Future<void> _onRefresh(
    TaskListRefreshRequested event,
    Emitter<TaskListState> emit,
  ) async {
    emit( state.copyWith( loading: true, clearError: true ) );
    try {
      final page = await _repo.fetch( cancelToken: event.cancelToken );
      emit( state.copyWith(
        model      : groupTasksByOwner( page.rows ),
        loading    : false,
        incomplete : page.isIncomplete,
        total      : page.total,
      ) );
    } on DioException catch ( e ) {
      // A cancelled poll is the lifecycle rule working, not an error to paint; showing
      // "request cancelled" on every exit would train users to ignore the error line.
      if ( CancelToken.isCancel( e ) ) {
        emit( state.copyWith( loading: false ) );
        return;
      }
      emit( state.copyWith( loading: false, error: e.message ?? 'request failed' ) );
    } on TaskListFetchException catch ( e ) {
      emit( state.copyWith( loading: false, error: e.message ) );
    }
  }

  // Writes are optimistic with rollback: the view repaints immediately and the row goes
  // back when the call rejects. A 202 is routed into the same rollback.
  // `TaskAwaitingApprovalException` is its own type, so it cannot be caught as an ordinary
  // failure and retried; the request succeeded, the change did not happen, and pressing
  // again files a second ticket. The operator is told the row is pending review, neither
  // failed nor done. An open target updates in place and a terminal one leaves the view,
  // because removing a row that only moved would suggest an approved row vanished; the
  // refetch, not the optimistic drop, settles the final shape.
  Future<void> _onVerb( TaskListVerbPressed event, Emitter<TaskListState> emit ) async {
    final before = state.model;
    emit( state.copyWith( model: _withoutRow( before, event.taskId ), clearError: true ) );

    try {
      await _writes.transition( id: event.taskId, verb: event.verb );
      add( const TaskListRefreshRequested() );
    } on TaskAwaitingApprovalException catch ( e ) {
      emit( state.copyWith(
        model : before,
        error : '${event.verb.name} is awaiting approval'
                '${e.ticketId == null ? '' : ' (ticket ${e.ticketId})'}',
      ) );
    } on TaskWriteException catch ( e ) {
      // Roll back and remember. The row goes back because the change did not happen, and
      // the act is kept because the operator made it. Only a transport failure is kept: a
      // server that answered and refused is an error with its own words, and a mark for it
      // would never clear.
      emit( state.copyWith(
        model  : before,
        error  : e.message,
        unsent : isTransportFailure( e )
            ? _withUnsent( UnsentWrite(
                taskId : event.taskId,
                label  : verbLabel( event.verb.name ),
                verb   : event.verb,
              ) )
            : state.unsent,
      ) );
    }
  }

  // Reads the fleet once, for the roster. Every failure collapses to an empty roster and
  // none paints an error: this is a courtesy read on a pane about tasks, and an
  // unreachable arbiter means only that the owner dropdown offers the current owner.
  // Painting `state.error` would put a fleet problem's text on a board whose own read
  // succeeded. It must not throw past the handler either, because an unhandled error in a
  // bloc handler surfaces through `onError` and can take the bloc down, turning "arbiter
  // unreachable" into "the Task List stopped polling".
  Future<void> _onRoster( TaskListRosterRequested event, Emitter<TaskListState> emit ) async {
    final fleet = _fleet;
    if ( fleet == null ) return;

    try {
      final composite = await fleet.fetchState();
      emit( state.copyWith( reassignTargets: activeReassignTargets( composite ) ) );
    } on FleetApiException {
      // The phone cannot see the fleet. The board is fine; the roster is empty.
    } on DioException {
      // Includes the cancelled case, which is the lifecycle rule working.
    }
  }

  // The field door: priority and owner only, never status. Status goes through _onVerb.
  Future<void> _onField( TaskListFieldChanged event, Emitter<TaskListState> emit ) async {
    final before = state.model;
    try {
      await _writes.patchFields(
        id           : event.taskId,
        priority     : event.priority,
        ownerPersona : event.ownerPersona,
      );
      add( const TaskListRefreshRequested() );
    } on TaskWriteException catch ( e ) {
      emit( state.copyWith(
        model  : before,
        error  : e.message,
        unsent : isTransportFailure( e )
            ? _withUnsent( UnsentWrite(
                taskId       : event.taskId,
                label        : event.priority != null ? 'Priority' : 'Owner',
                priority     : event.priority,
                ownerPersona : event.ownerPersona,
              ) )
            : state.unsent,
      ) );
    }
  }

  // The connection came back: resend what the network ate, once each. One attempt per
  // write per restored connection, not a loop within this pass. A write that fails on
  // transport again is kept until the next restored edge. A retry that meets a refusal
  // stops being unsent: the connection is fine, so the mark would never clear. The record
  // is dropped and the server's own words go in front of the operator, who is the only one
  // who can change a write that will never succeed as written.
  Future<void> _onRetryUnsent(
    TaskListUnsentRetryRequested event,
    Emitter<TaskListState> emit,
  ) async {
    if ( state.unsent.isEmpty ) return;

    final outcome = await retryUnsentWrites( state.unsent, _send );

    emit( state.copyWith(
      unsent     : outcome.remaining,
      error      : outcome.refusals.isEmpty ? null : outcome.refusals.first,
      clearError : outcome.refusals.isEmpty,
    ) );
  }

  // Sends one remembered write back through the door it came from. The door is decided by
  // what the write changes, as for a fresh write: a PATCH carrying a status is ignored, and
  // a transition carrying a priority is not a request the endpoint understands.
  Future<void> _send( UnsentWrite write ) {
    final verb = write.verb;
    if ( verb != null ) {
      return _writes.transition( id: write.taskId, verb: verb );
    }
    return _writes.patchFields(
      id           : write.taskId,
      priority     : write.priority,
      ownerPersona : write.ownerPersona,
    );
  }

  Map<String, UnsentWrite> _withUnsent( UnsentWrite write ) =>
      <String, UnsentWrite>{ ...state.unsent, write.taskId : write };

  // Drops one row from the rendered model without refetching: the optimistic half.
  TaskListModel? _withoutRow( TaskListModel? model, String taskId ) {
    if ( model == null ) return null;
    final groups = model.groups
        .map( ( g ) => TaskGroup(
              ownerPersona : g.ownerPersona,
              tasks        : g.tasks.where( ( t ) => t.id != taskId ).toList(),
            ) )
        .where( ( g ) => g.tasks.isNotEmpty )
        .toList();
    return TaskListModel( totalCount: model.totalCount - 1, groups: groups );
  }

  void _onToggle( TaskListGroupToggled event, Emitter<TaskListState> emit ) {
    final next = Set<String>.from( state.collapsed );
    if ( !next.remove( event.groupLabel ) ) next.add( event.groupLabel );
    emit( state.copyWith( collapsed: next ) );
  }

  @override
  Future<void> close() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    return super.close();
  }
}
