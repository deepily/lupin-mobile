import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../fleet_status/data/fleet_models.dart';
import '../../fleet_status/data/fleet_repository.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../../fleet/domain/pane_visibility_mixin.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/domain/unsent_write.dart';
import '../data/holding_area_models.dart';
import '../data/holding_area_repository.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

/// Base type of every event the Holding Area bloc handles.
sealed class HoldingAreaEvent {
  const HoldingAreaEvent();
}

/// A poll tick, a pull-to-refresh, or a resume.
class HoldingAreaRefreshRequested extends HoldingAreaEvent {
  /// Token that cancels the fetch, or null for a refresh that cannot be cancelled.
  final CancelToken? cancelToken;
  /// Creates a refresh request.
  const HoldingAreaRefreshRequested( { this.cancelToken } );
}

/// One row, one verb. The per-row control — the precise instrument.
class HoldingAreaRowVerbPressed extends HoldingAreaEvent {
  /// Id of the task the verb applies to.
  final String   id;
  /// The verb to apply.
  final TaskVerb verb;
  /// Creates a request to press [verb] on the task with id [id].
  const HoldingAreaRowVerbPressed( { required this.id, required this.verb } );
}

/// Approve every row one filer filed.
///
/// The confirm belongs to the pane: the operator has already answered it when this event
/// is added. A bloc that opened its own dialog could not be tested without a widget tree.
class HoldingAreaApproveAllPressed extends HoldingAreaEvent {
  /// The persona whose held rows are approved.
  final String filer;
  /// Creates an approve-all request for [filer].
  const HoldingAreaApproveAllPressed( this.filer );
}

/// Close every row one filer filed as won't-fix, under one reason.
class HoldingAreaWontFixAllPressed extends HoldingAreaEvent {
  /// The persona whose rows are closed.
  final String filer;
  /// The justification applied to every row; a blank one is refused.
  final String reason;
  /// Creates a won't-fix-all request for [filer].
  const HoldingAreaWontFixAllPressed( { required this.filer, required this.reason } );
}

/// An operator changed a held row's priority or owner, through the field door.
///
/// Separate from [HoldingAreaRowVerbPressed] because the server doors differ: fields go
/// to `PATCH /api/tasks/{id}` and status goes to `POST /api/tasks/{id}/transition`.
/// Sending a priority change to the transition endpoint is refused with a 422; the
/// transition body takes no `priority`.
class HoldingAreaFieldChanged extends HoldingAreaEvent {
  /// Id of the task being changed.
  final String  id;
  /// New priority, or null to leave it unchanged.
  final String? priority;
  /// New owner persona, or null to leave it unchanged.
  final String? ownerPersona;
  /// Creates a field change for the task with id [id].
  const HoldingAreaFieldChanged( {
    required this.id,
    this.priority,
    this.ownerPersona,
  } );
}

/// Fetch the live persona roster the owner control offers.
///
/// Every failure becomes an empty roster and none shows an error. An unreachable arbiter
/// means the owner dropdown offers less, not that the Holding Area is broken.
class HoldingAreaRosterRequested extends HoldingAreaEvent {
  /// Creates a roster request.
  const HoldingAreaRosterRequested();
}

/// The connection came back: resend what the network dropped.
///
/// A separate event from the refresh because one sends the operator's work to the
/// server and the other pulls the server's state back. A pull-to-refresh must never write.
class HoldingAreaUnsentRetryRequested extends HoldingAreaEvent {
  /// Creates a retry request.
  const HoldingAreaUnsentRetryRequested();
}

/// The operator folded or unfolded one persona's group.
///
/// The event carries the persona, not an index. Group positions move under a poll, so an
/// index could toggle a different persona by the time the tap lands.
class HoldingAreaGroupToggled extends HoldingAreaEvent {
  /// The persona whose group is toggled.
  final String filer;
  /// Creates a toggle for the group of [filer].
  const HoldingAreaGroupToggled( this.filer );
}

/// The operator typed in one group's batch reason box.
class HoldingAreaReasonChanged extends HoldingAreaEvent {
  /// The persona whose reason box changed.
  final String filer;
  /// The text now in the reason box.
  final String reason;
  /// Creates a reason edit for the group of [filer].
  const HoldingAreaReasonChanged( { required this.filer, required this.reason } );
}

// ─── State ───────────────────────────────────────────────────────────────────

/// What the Holding Area pane shows: held groups, notices and per-group control state.
class HoldingAreaState extends Equatable {
  /// Held rows grouped by filing persona, in persona order.
  final List<FilerGroup> groups;
  /// True while a fetch is in flight.
  final bool loading;
  /// Fetch error to show, or null.
  final String? error;

  /// True when the page is not the whole held set — surfaced as a visible banner.
  final bool incomplete;
  /// Number of rows the server reports as held.
  final int total;

  /// Per-group batch reason text, keyed by filer.
  ///
  /// It is the operator's typing and survives a poll, so a refresh never blanks a
  /// half-typed justification.
  final Map<String, String> reasons;

  /// Per-group complaint, keyed by filer, for an empty won't-fix-all reason.
  ///
  /// Set when won't-fix-all is pressed with an empty box, cleared when the operator types.
  final Map<String, String> reasonErrors;

  /// What the last batch or failed write did, shown above the rows.
  ///
  /// Kept apart from [error]. A batch ends with a refetch, which clears the fetch error
  /// and would wipe a partial-batch report almost at once.
  final String? batchNotice;

  /// Filers whose batch write is in flight.
  ///
  /// The pane disables both batch controls for them. A second press would double the
  /// writes without doubling the count the operator read.
  final Set<String> busyFilers;

  /// The personas a held row may be reassigned to, from the live fleet roster.
  ///
  /// Not the owners the board already shows, because that set omits seats that own no row.
  /// Empty when the arbiter is unreachable, which degrades the control, not the pane.
  final List<String> reassignTargets;

  /// Personas the operator has unfolded; the empty set means every group is folded.
  ///
  /// It is not persisted, so leaving the pane and returning folds everything again. A poll
  /// replaces `groups` and leaves this set alone, so the group being read stays open.
  /// Design: src/docs/decisions/README.md (R-HA-accordion)
  final Set<String> expanded;

  /// Writes the operator made that never reached the server, keyed by task id.
  ///
  /// Keyed per row even for a batch. Batch rows fail independently, so the rows that did
  /// not land are the rows that carry the mark.
  final Map<String, UnsentWrite> unsent;

  /// Creates a state; every field defaults to empty, folded and idle.
  const HoldingAreaState( {
    this.groups       = const <FilerGroup>[],
    this.loading      = false,
    this.error,
    this.incomplete   = false,
    this.total        = 0,
    this.reasons      = const <String, String>{},
    this.reasonErrors = const <String, String>{},
    this.busyFilers   = const <String>{},
    this.expanded     = const <String>{},
    this.reassignTargets = const <String>[],
    this.unsent          = const <String, UnsentWrite>{},
    this.batchNotice,
  } );

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing null for `error` or `batchNotice` keeps the old value; use [clearError] or
  /// [clearBatchNotice] to reset them to null.
  HoldingAreaState copyWith( {
    List<FilerGroup>? groups,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? incomplete,
    int? total,
    Map<String, String>? reasons,
    Map<String, String>? reasonErrors,
    Set<String>? busyFilers,
    Set<String>? expanded,
    List<String>? reassignTargets,
    Map<String, UnsentWrite>? unsent,
    String? batchNotice,
    bool clearBatchNotice = false,
  } ) =>
      HoldingAreaState(
        groups       : groups ?? this.groups,
        loading      : loading ?? this.loading,
        error        : clearError ? null : ( error ?? this.error ),
        incomplete   : incomplete ?? this.incomplete,
        total        : total ?? this.total,
        reasons      : reasons ?? this.reasons,
        reasonErrors : reasonErrors ?? this.reasonErrors,
        busyFilers   : busyFilers ?? this.busyFilers,
        expanded     : expanded ?? this.expanded,
        reassignTargets : reassignTargets ?? this.reassignTargets,
        unsent          : unsent ?? this.unsent,
        batchNotice  : clearBatchNotice ? null : ( batchNotice ?? this.batchNotice ),
      );

  /// The reason currently typed for one group, or the empty string.
  String reasonFor( String filer ) => reasons[ filer ] ?? '';

  /// What the operator did to this row that has not landed, if anything.
  String? unsentLabelFor( String taskId ) => unsent[ taskId ]?.label;

  /// Whether one persona's rows are on screen. Folded unless the operator said otherwise.
  bool isExpanded( String filer ) => expanded.contains( filer );

  @override
  List<Object?> get props =>
      [ groups, loading, error, incomplete, total, reasons, reasonErrors, busyFilers,
        expanded, reassignTargets, unsent, batchNotice ];
}

// ─── Bloc ────────────────────────────────────────────────────────────────────

/// State and events for the Holding Area pane.
///
/// Register it per route, not at the app root. A root-level bloc outlives its route, and
/// its poll timer then runs against whichever screen is showing. See [PanePollingMixin].
class HoldingAreaBloc extends Bloc<HoldingAreaEvent, HoldingAreaState>
    with PaneVisibilityMixin<HoldingAreaEvent, HoldingAreaState>,
        PanePollingMixin<HoldingAreaEvent, HoldingAreaState> {
  final HoldingAreaRepository _repo;
  final TaskWriteRepository   _writes;
  final NetworkConnectivityService _network;

  // Optional and used only for the reassignment roster, so the pane still shows held work
  // when the arbiter is unreachable or a test does not need the owner control.
  final FleetRepository? _fleet;

  StreamSubscription<NetworkState>? _connectivitySub;

  /// The network state before the latest edge; seeded from the service when [startConnectivityRefresh] first runs.
  NetworkState _previousNetworkState = NetworkState.unknown;

  /// Creates the bloc; [network] and [fleet] are optional.
  HoldingAreaBloc(
    this._repo,
    this._writes, {
    NetworkConnectivityService? network,
    FleetRepository? fleet,
  } )  : _network = network ?? NetworkConnectivityService(),
        _fleet   = fleet,
        super( const HoldingAreaState() ) {
    on<HoldingAreaRefreshRequested>( _onRefresh );
    on<HoldingAreaRowVerbPressed>( _onRowVerb );
    on<HoldingAreaApproveAllPressed>( _onApproveAll );
    on<HoldingAreaWontFixAllPressed>( _onWontFixAll );
    on<HoldingAreaReasonChanged>( _onReasonChanged );
    on<HoldingAreaGroupToggled>( _onGroupToggled );
    on<HoldingAreaFieldChanged>( _onField );
    on<HoldingAreaRosterRequested>( _onRoster );
    on<HoldingAreaUnsentRetryRequested>( _onRetryUnsent );
  }

  // Reports whether the connection is metered, from the injected network service so tests
  // can fake it. The interval itself comes from `PanePollingMixin.pollInterval`.
  @override
  bool get isMeteredConnection => _network.isMobile;

  @override
  Future<void> pollOnce( CancelToken token ) async {
    add( HoldingAreaRefreshRequested( cancelToken: token ) );
  }

  // Resends each unsent write once per connection-restored edge, before the refetch. A
  // refetch first would repaint from a server that lacks the write and the row would flicker
  // back to held. A write the server refuses is dropped from `unsent` and the server's words
  // go to `batchNotice`, which survives the refetch.
  Future<void> _onRetryUnsent(
    HoldingAreaUnsentRetryRequested event,
    Emitter<HoldingAreaState> emit,
  ) async {
    if ( state.unsent.isEmpty ) return;

    final outcome = await retryUnsentWrites( state.unsent, _send );

    emit( state.copyWith(
      unsent           : outcome.remaining,
      batchNotice      : outcome.refusals.isEmpty ? null : outcome.refusals.first,
      clearBatchNotice : outcome.refusals.isEmpty,
    ) );
  }

  // Sends one remembered write through the door it came from. The door follows what the
  // write changes: a PATCH carrying a status is refused with a 422.
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

  /// Refreshes on the connectivity-restored edge only (`connected` or `limited`), after retrying unsent writes.
  ///
  /// Firing on every state change would also refetch on the way down, into a connection
  /// that just failed.
  void startConnectivityRefresh() {
    // A pane opens after the service has settled, so its first edge is judged against the state it opened in.
    if ( _connectivitySub == null ) _previousNetworkState = _network.currentState;
    _connectivitySub ??= _network.networkStateStream.listen( ( state ) {
      final previous        = _previousNetworkState;
      _previousNetworkState = state;
      // The same rule as the task list; see `shouldRetryOnNetworkEdge`.
      if ( !shouldRetryOnNetworkEdge( previous, state ) ) return;
      // The retry goes first; see `_onRetryUnsent`.
      add( const HoldingAreaUnsentRetryRequested() );
      add( const HoldingAreaRefreshRequested() );
    } );
  }

  Future<void> _onRefresh(
    HoldingAreaRefreshRequested event,
    Emitter<HoldingAreaState> emit,
  ) async {
    emit( state.copyWith( loading: true, clearError: true ) );
    try {
      final page = await _repo.fetch( cancelToken: event.cancelToken );
      emit( state.copyWith(
        groups     : groupByFiler( page.rows ),
        loading    : false,
        incomplete : page.isIncomplete,
        total      : page.total,
      ) );
    } on DioException catch ( e ) {
      // A cancelled poll is the lifecycle rule working, not an error to show.
      if ( CancelToken.isCancel( e ) ) {
        emit( state.copyWith( loading: false ) );
        return;
      }
      emit( state.copyWith( loading: false, error: e.message ?? 'request failed' ) );
    } on HoldingAreaFetchException catch ( e ) {
      emit( state.copyWith( loading: false, error: e.message ) );
    }
  }

  Future<void> _onRowVerb(
    HoldingAreaRowVerbPressed event,
    Emitter<HoldingAreaState> emit,
  ) async {
    try {
      await _writes.transition( id: event.id, verb: event.verb );
    } on Object catch ( e ) {
      // The notice says the write failed and the mark says which row. Only a transport
      // failure is kept: a refusal from the server has its own words and would never clear.
      emit( state.copyWith(
        batchNotice : _writeError( e ),
        unsent      : isTransportFailure( e )
            ? _withUnsent( UnsentWrite(
                taskId : event.id,
                label  : verbLabel( event.verb.name ),
                verb   : event.verb,
              ) )
            : state.unsent,
      ) );
      return;
    }
    // The write landed, so whatever this row was carrying is no longer unsent.
    if ( state.unsent.containsKey( event.id ) ) {
      emit( state.copyWith( unsent: { ...state.unsent }..remove( event.id ) ) );
    }
    // Refetch rather than drop the row locally: an approved row leaves this pane, and the
    // server may have only queued it (a 202). The fetch proves the row left.
    add( const HoldingAreaRefreshRequested() );
  }

  Future<void> _onApproveAll(
    HoldingAreaApproveAllPressed event,
    Emitter<HoldingAreaState> emit,
  ) async {
    await _batch(
      filer : event.filer,
      emit  : emit,
      verb  : ( _ ) => TaskVerb.approve(),
    );
  }

  Future<void> _onWontFixAll(
    HoldingAreaWontFixAllPressed event,
    Emitter<HoldingAreaState> emit,
  ) async {
    // The blank check is repeated here, not only in the pane. The pane's check is what the
    // operator sees; this one holds for any other caller, which would otherwise send N
    // transitions that the server answers with N identical 422s.
    if ( event.reason.trim().isEmpty ) {
      // The complaint unfolds the group, because its reason box is hidden while folded.
      // Without this, pressing won't-fix-all on a folded group would set a complaint the
      // operator cannot see. Unfolding is chosen over disabling the button, which would
      // explain nothing.
      emit( state.copyWith(
        reasonErrors : { ...state.reasonErrors, event.filer: kHoldingWontFixReasonMissing },
        expanded     : { ...state.expanded, event.filer },
      ) );
      return;
    }

    await _batch(
      filer : event.filer,
      emit  : emit,
      verb  : ( _ ) => TaskVerb.wontFix( reason: event.reason.trim() ),
    );
  }

  // Runs one verb over every row in a group, one row at a time. Sequential, not
  // `Future.wait`: fifty concurrent transitions strain one store, and the first failure in
  // a `Future.wait` hides the outcome of the rest. The loop does not stop at the first
  // failure; it counts and reports how many of how many landed.
  Future<void> _batch( {
    required String filer,
    required Emitter<HoldingAreaState> emit,
    required TaskVerb Function( String id ) verb,
  } ) async {
    final group = state.groups.where( ( g ) => g.filer == filer ).firstOrNull;
    if ( group == null || group.rows.isEmpty ) return;

    emit( state.copyWith(
      busyFilers       : { ...state.busyFilers, filer },
      clearError       : true,
      clearBatchNotice : true,
      reasonErrors     : { ...state.reasonErrors }..remove( filer ),
    ) );

    final ids      = group.ids;
    var   applied  = 0;
    Object? firstFailure;

    // Rows that did not land carry a mark, because a batch fails per row.
    final marks = <String, UnsentWrite>{ ...state.unsent };

    for ( final id in ids ) {
      try {
        await _writes.transition( id: id, verb: verb( id ) );
        applied++;
        marks.remove( id );   // it landed; any older mark on this row is spent
      } on Object catch ( e ) {
        firstFailure ??= e;
        if ( isTransportFailure( e ) ) {
          marks[ id ] = UnsentWrite(
            taskId : id,
            label  : verbLabel( verb( id ).name ),
            verb   : verb( id ),
          );
        }
      }
    }

    final next     = { ...state.busyFilers }..remove( filer );
    final complete = applied == ids.length;

    emit( state.copyWith(
      busyFilers       : next,
      // Kept in `batchNotice` because `error` is cleared by the refresh this batch schedules.
      batchNotice      : complete
          ? null
          : '${ids.length - applied} of ${ids.length} rows did not move '
            '(${_writeError( firstFailure! )}) — the rest did',
      clearBatchNotice : complete,
      unsent           : marks,
      reasons          : complete
          ? ( { ...state.reasons }..remove( filer ) )
          : state.reasons,
    ) );

    add( const HoldingAreaRefreshRequested() );
  }

  // The field door: priority and owner only, never status (see `_onRowVerb`). It refetches
  // for the same reason as `_onRowVerb`: a refused or queued change must not look applied.
  Future<void> _onField(
    HoldingAreaFieldChanged event,
    Emitter<HoldingAreaState> emit,
  ) async {
    try {
      await _writes.patchFields(
        id           : event.id,
        priority     : event.priority,
        ownerPersona : event.ownerPersona,
      );
    } on Object catch ( e ) {
      // Uses `batchNotice`, as a failed row verb does, because the refetch about to be
      // scheduled would clear `error` before the operator read it. A field edit lost to a
      // dropped connection is remembered in `unsent` like a verb.
      emit( state.copyWith(
        batchNotice : _writeError( e ),
        unsent      : isTransportFailure( e )
            ? _withUnsent( UnsentWrite(
                taskId       : event.id,
                label        : event.priority != null ? 'Priority' : 'Owner',
                priority     : event.priority,
                ownerPersona : event.ownerPersona,
              ) )
            : state.unsent,
      ) );
      return;
    }
    if ( state.unsent.containsKey( event.id ) ) {
      emit( state.copyWith( unsent: { ...state.unsent }..remove( event.id ) ) );
    }
    add( const HoldingAreaRefreshRequested() );
  }

  // Loads the persona roster for the owner control. Every failure leaves the roster empty
  // and shows no error. It must not throw: an unhandled error in a handler can stop the
  // bloc, turning an unreachable arbiter into a pane that stopped polling.
  Future<void> _onRoster(
    HoldingAreaRosterRequested event,
    Emitter<HoldingAreaState> emit,
  ) async {
    final fleet = _fleet;
    if ( fleet == null ) return;

    try {
      final composite = await fleet.fetchState();
      emit( state.copyWith( reassignTargets: activeReassignTargets( composite ) ) );
    } on FleetApiException {
      // The phone cannot see the fleet. The held set is fine; the roster is empty.
    } on DioException {
      // Includes the cancelled case, which is the lifecycle rule working.
    }
  }

  // Folds or unfolds one persona's rows. Opening one group does not close the others, so
  // two personas' held work can be compared without scrolling back and forth.
  void _onGroupToggled( HoldingAreaGroupToggled event, Emitter<HoldingAreaState> emit ) {
    final next = Set<String>.from( state.expanded );
    if ( !next.remove( event.filer ) ) next.add( event.filer );
    emit( state.copyWith( expanded: next ) );
  }

  void _onReasonChanged( HoldingAreaReasonChanged event, Emitter<HoldingAreaState> emit ) {
    emit( state.copyWith(
      reasons      : { ...state.reasons, event.filer: event.reason },
      // Typing clears the complaint. Leaving it up while the box fills would make the
      // pane argue with what the operator can see.
      reasonErrors : { ...state.reasonErrors }..remove( event.filer ),
    ) );
  }

  // Operator-facing text for a failed write. The 202 case never says "failed": the server
  // accepted the request, and pressing again would file a second approval ticket.
  String _writeError( Object e ) {
    if ( e is TaskAwaitingApprovalException ) {
      return 'awaiting human approval — the request was accepted, the change has not '
             'happened yet, and pressing again files a second ticket';
    }
    if ( e is TaskWriteException ) return e.message;
    if ( e is DioException ) return e.message ?? 'write failed';
    return e.toString();
  }

  @override
  Future<void> close() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    return super.close();
  }
}
