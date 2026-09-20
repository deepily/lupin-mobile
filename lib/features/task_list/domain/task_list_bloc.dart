import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
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

  const TaskListState( {
    this.model,
    this.loading    = false,
    this.error,
    this.incomplete = false,
    this.total      = 0,
    this.collapsed  = const <String>{},
  } );

  TaskListState copyWith( {
    TaskListModel? model,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? incomplete,
    int? total,
    Set<String>? collapsed,
  } ) =>
      TaskListState(
        model      : model ?? this.model,
        loading    : loading ?? this.loading,
        error      : clearError ? null : ( error ?? this.error ),
        incomplete : incomplete ?? this.incomplete,
        total      : total ?? this.total,
        collapsed  : collapsed ?? this.collapsed,
      );

  @override
  List<Object?> get props => [ model, loading, error, incomplete, total, collapsed ];
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
  final NetworkConnectivityService _network;

  StreamSubscription<NetworkState>? _connectivitySub;

  TaskListBloc( this._repo, { NetworkConnectivityService? network } )
      : _network = network ?? NetworkConnectivityService(),
        super( const TaskListState() ) {
    on<TaskListRefreshRequested>( _onRefresh );
    on<TaskListGroupToggled>( _onToggle );
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
