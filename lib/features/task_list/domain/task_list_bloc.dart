import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../fleet_status/data/fleet_models.dart';
import '../../fleet_status/data/fleet_repository.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../data/task_list_model.dart';
import '../data/task_list_repository.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

sealed class TaskListEvent {
  const TaskListEvent();
}

/// A poll tick, a pull-to-refresh, or a resume.
class TaskListRefreshRequested extends TaskListEvent {
  final CancelToken? cancelToken;
  const TaskListRefreshRequested( { this.cancelToken } );
}

class TaskListGroupToggled extends TaskListEvent {
  final String groupLabel;
  const TaskListGroupToggled( this.groupLabel );
}

/// An operator pressed a status verb on a row. Goes through the TRANSITION door.
class TaskListVerbPressed extends TaskListEvent {
  final String taskId;
  final TaskVerb verb;
  const TaskListVerbPressed( { required this.taskId, required this.verb } );
}

/// Read the live fleet, for the reassignment roster.
///
/// ⚠️ ITS OWN EVENT RATHER THAN A LIMB OF THE POLL, BECAUSE IT IS A DIFFERENT SERVICE ON
/// A DIFFERENT CADENCE. The board polls every 60 s on Wi-Fi and 180 s on mobile data; the
/// roster changes when a seat is spawned or reaped, which is rare and is not worth a
/// second request on every tick of the first one.
class TaskListRosterRequested extends TaskListEvent {
  const TaskListRosterRequested();
}

/// An operator changed a row's priority or owner. Goes through the FIELD door.
class TaskListFieldChanged extends TaskListEvent {
  final String taskId;
  final String? priority;
  final String? ownerPersona;
  const TaskListFieldChanged( { required this.taskId, this.priority, this.ownerPersona } );
}

// ─── State ───────────────────────────────────────────────────────────────────

class TaskListState extends Equatable {
  final TaskListModel? model;
  final bool loading;
  final String? error;

  /// True when the page is not the whole board — surfaced as a visible banner.
  final bool incomplete;
  final int total;

  /// Group labels the operator has collapsed. Collapsed state is the OPERATOR's, so it
  /// survives a refresh — a poll that silently re-expanded every group would undo their
  /// work every sixty seconds.
  final Set<String> collapsed;

  /// The personas a row may be reassigned to — the LIVE fleet, alpha-sorted.
  ///
  /// ⚠️ EMPTY IS A LEGITIMATE STATE, NOT A LOADING ONE. It means the phone cannot see
  /// the fleet (pre-first-read, the arbiter unreachable, or nobody live), and the owner
  /// control degrades to showing the row's current owner. Treating it as "not ready yet"
  /// would hide the control forever on a handset that never reaches the arbiter.
  final List<String> reassignTargets;

  const TaskListState( {
    this.model,
    this.loading         = false,
    this.error,
    this.incomplete      = false,
    this.total           = 0,
    this.collapsed       = const <String>{},
    this.reassignTargets = const <String>[],
  } );

  TaskListState copyWith( {
    TaskListModel? model,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? incomplete,
    int? total,
    Set<String>? collapsed,
    List<String>? reassignTargets,
  } ) =>
      TaskListState(
        model           : model ?? this.model,
        loading         : loading ?? this.loading,
        error           : clearError ? null : ( error ?? this.error ),
        incomplete      : incomplete ?? this.incomplete,
        total           : total ?? this.total,
        collapsed       : collapsed ?? this.collapsed,
        reassignTargets : reassignTargets ?? this.reassignTargets,
      );

  @override
  List<Object?> get props =>
      [ model, loading, error, incomplete, total, collapsed, reassignTargets ];
}

// ─── Bloc ────────────────────────────────────────────────────────────────────

/// The Task List pane's bloc.
///
/// ⚠️ THIS IS ROUTE-SCOPED, NOT AN APP-ROOT SINGLETON, AND THAT IS A DELIBERATE
/// DEPARTURE. `app.dart:248-278` registers seven `BlocProvider`s at the app root, each a
/// `ServiceLocator` singleton, so a pane's bloc would otherwise outlive its route and its
/// timer would run whichever destination is showing. Foreground-pane-only polling has no
/// mechanism unless the pane blocs are route-scoped — see [PanePollingMixin].
class TaskListBloc extends Bloc<TaskListEvent, TaskListState>
    with PanePollingMixin<TaskListEvent, TaskListState> {
  final TaskListRepository _repo;
  final TaskWriteRepository _writes;
  final NetworkConnectivityService _network;

  /// The fleet read, for the reassignment roster ONLY.
  ///
  /// ⚠️ OPTIONAL, AND A NULL ONE IS NOT A BROKEN PANE. The Task List's job is tasks; the
  /// roster is a courtesy the owner control degrades without. Making it required would
  /// mean a pane that cannot render until a SECOND service answers, on a phone where the
  /// second service is the one most likely not to.
  final FleetRepository? _fleet;

  StreamSubscription<NetworkState>? _connectivitySub;

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
  }

  /// 🔴 THE POLL INTERVAL READS THE CONNECTION, AND THE NUMBERS ARE MEASURED.
  ///
  /// A full 500-row page is ~2.1 MB and a terse one ~107 KB (`tasks.py:739`). At 60 s
  /// that is ~6.4 MB per foreground hour on ONE pane even terse — fine on Wi-Fi, rude on
  /// a metered connection. Sixty seconds is the WEB's number and a phone is not a browser
  /// tab.
  ///
  /// `isWifi` / `isMobile` already exist (`network_connectivity_service.dart:52-53`) and
  /// nothing in the plan reached for them.
  @override
  Duration get pollInterval =>
      _network.isMobile ? const Duration( seconds: 180 ) : const Duration( seconds: 60 );

  /// The mixin's poll hook. The token is honoured all the way down to Dio, so a pane that
  /// disappears mid-request cancels the request rather than only the timer.
  @override
  Future<void> pollOnce( CancelToken token ) async {
    add( TaskListRefreshRequested( cancelToken: token ) );
  }

  /// 🔴 THE NAMED RETRY TRIGGER, RATHER THAN A DEFERRED ONE.
  ///
  /// Commit `a8c30b3` is the SHAPE for an unsent write, not a reusable capability — it is
  /// feature-local to `focus_chat_bloc.dart`. And its trigger does NOT carry: it fires on
  /// WS re-auth, and this pane rides no socket at all. So the trigger has to be named
  /// here, and it is connectivity-restored — `NetworkConnectivityService` already streams
  /// it, so this is wiring rather than new capability.
  void startConnectivityRefresh() {
    _connectivitySub ??= _network.networkStateStream.listen( ( state ) {
      // Only the RESTORED edge refreshes. Firing on every state change would refetch on
      // the way down as well, which is a request into a connection that just failed.
      if ( state == NetworkState.connected ) add( const TaskListRefreshRequested() );
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
      // A cancelled poll is the lifecycle rule working, NOT an error to paint. Showing
      // "request cancelled" every time the user leaves the pane would train them to
      // ignore the error line that matters.
      if ( CancelToken.isCancel( e ) ) {
        emit( state.copyWith( loading: false ) );
        return;
      }
      emit( state.copyWith( loading: false, error: e.message ?? 'request failed' ) );
    } on TaskListFetchException catch ( e ) {
      emit( state.copyWith( loading: false, error: e.message ) );
    }
  }

  /// 🔴 WRITES ARE OPTIMISTIC WITH ROLLBACK (§4.6). The view repaints immediately and the
  /// row goes back when the call rejects — `TaskListStore.ts:266-284` returns
  /// `{restoreState, done}` for exactly this shape.
  ///
  /// ⚠️ AND THE 202 IS ROUTED INTO THE SAME ROLLBACK. `TaskAwaitingApprovalException` is a
  /// DISTINCT type rather than a flag, so it cannot be caught as an ordinary failure and
  /// retried: the request SUCCEEDED, the change did not happen, and pressing again only
  /// files a second ticket. The operator is told the row is pending review — not that it
  /// failed, and not that it worked.
  ///
  /// ⚠️ AN OPEN TARGET UPDATES IN PLACE; A TERMINAL ONE LEAVES THE VIEW. Removing a row
  /// that merely moved would tell the operator their approved row had disappeared
  /// (`TaskListStore.ts:293-299`) — so the refetch, not the optimistic drop, is what
  /// settles the final shape.
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
      emit( state.copyWith( model: before, error: e.message ) );
    }
  }

  /// Read the fleet once, for the roster.
  ///
  /// 🔴 EVERY FAILURE COLLAPSES TO AN EMPTY ROSTER, AND NONE OF THEM PAINTS AN ERROR.
  /// This is a courtesy read on a pane about tasks: an arbiter that cannot be reached is
  /// a reason the owner dropdown offers only the current owner, and it is NOT a reason to
  /// tell the operator their task board is broken. Painting `state.error` here would put
  /// a fleet problem's text on a board whose own read succeeded.
  ///
  /// ⚠️ AND IT MUST NOT THROW PAST THE HANDLER EITHER. An unhandled error inside a bloc
  /// handler is not a silent no-op — it surfaces through `onError` and can take the bloc
  /// down, which would turn "the arbiter is unreachable" into "the Task List stopped
  /// polling".
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

  /// The FIELD door — priority and owner only, never status. Status is [_onVerb].
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
      emit( state.copyWith( model: before, error: e.message ) );
    }
  }

  /// Drop one row from the rendered model without refetching — the optimistic half.
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
