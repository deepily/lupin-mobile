import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../data/holding_area_models.dart';
import '../data/holding_area_repository.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

sealed class HoldingAreaEvent {
  const HoldingAreaEvent();
}

/// A poll tick, a pull-to-refresh, or a resume.
class HoldingAreaRefreshRequested extends HoldingAreaEvent {
  final CancelToken? cancelToken;
  const HoldingAreaRefreshRequested( { this.cancelToken } );
}

/// One row, one verb. The per-row control — the precise instrument.
class HoldingAreaRowVerbPressed extends HoldingAreaEvent {
  final String   id;
  final TaskVerb verb;
  const HoldingAreaRowVerbPressed( { required this.id, required this.verb } );
}

/// Approve every row one filer filed.
///
/// The CONFIRM is the pane's, not the bloc's: by the time this event is added the
/// operator has already answered it. A bloc that popped its own dialog could not be
/// tested without a widget tree, and a pane that dispatched before confirming would put
/// the gate somewhere a later hand can skip.
class HoldingAreaApproveAllPressed extends HoldingAreaEvent {
  final String filer;
  const HoldingAreaApproveAllPressed( this.filer );
}

/// Close every row one filer filed as won't-fix, under ONE reason.
class HoldingAreaWontFixAllPressed extends HoldingAreaEvent {
  final String filer;
  final String reason;
  const HoldingAreaWontFixAllPressed( { required this.filer, required this.reason } );
}

/// The operator typed in one group's batch reason box.
class HoldingAreaReasonChanged extends HoldingAreaEvent {
  final String filer;
  final String reason;
  const HoldingAreaReasonChanged( { required this.filer, required this.reason } );
}

// ─── State ───────────────────────────────────────────────────────────────────

class HoldingAreaState extends Equatable {
  final List<FilerGroup> groups;
  final bool loading;
  final String? error;

  /// True when the page is not the whole held set — surfaced as a visible banner.
  final bool incomplete;
  final int total;

  /// Per-group batch reason text, keyed by filer. The OPERATOR's typing, so it survives
  /// a poll — a refresh that blanked a half-typed justification every sixty seconds
  /// would make the batch control unusable on exactly the groups big enough to need it.
  final Map<String, String> reasons;

  /// Per-group validation complaint, keyed by filer. Set when won't-fix-all is pressed
  /// with an empty box, cleared as soon as the operator types.
  final Map<String, String> reasonErrors;

  /// What the last batch actually did.
  ///
  /// 🔴 A SEPARATE FIELD FROM [error], BECAUSE THE TWO HAVE DIFFERENT LIFETIMES AND THE
  /// SHORTER ONE WAS EATING THE LONGER. A batch ends by refetching, the refetch clears
  /// the fetch error, and a partial-batch report parked in `error` was therefore wiped
  /// about eighty milliseconds after it appeared — the operator saw nothing, in the one
  /// case where some of their rows moved and some did not. A fetch error is answered by
  /// the next fetch; a report about what a press DID is answered only by the operator
  /// reading it.
  final String? batchNotice;

  /// Filers whose batch write is in flight. The pane disables both batch controls for
  /// that group — a second press while N transitions are still landing would double the
  /// writes without doubling the count the operator read.
  final Set<String> busyFilers;

  const HoldingAreaState( {
    this.groups       = const <FilerGroup>[],
    this.loading      = false,
    this.error,
    this.incomplete   = false,
    this.total        = 0,
    this.reasons      = const <String, String>{},
    this.reasonErrors = const <String, String>{},
    this.busyFilers   = const <String>{},
    this.batchNotice,
  } );

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
        batchNotice  : clearBatchNotice ? null : ( batchNotice ?? this.batchNotice ),
      );

  /// The reason currently typed for one group, or the empty string.
  String reasonFor( String filer ) => reasons[ filer ] ?? '';

  @override
  List<Object?> get props =>
      [ groups, loading, error, incomplete, total, reasons, reasonErrors, busyFilers,
        batchNotice ];
}

// ─── Bloc ────────────────────────────────────────────────────────────────────

/// The Holding Area pane's bloc.
///
/// ⚠️ ROUTE-SCOPED, NOT AN APP-ROOT SINGLETON, for the reason the Task List's bloc
/// records: a pane bloc registered at the app root outlives its route and its poll timer
/// then runs against whichever destination is showing. See [PanePollingMixin].
class HoldingAreaBloc extends Bloc<HoldingAreaEvent, HoldingAreaState>
    with PanePollingMixin<HoldingAreaEvent, HoldingAreaState> {
  final HoldingAreaRepository _repo;
  final TaskWriteRepository   _writes;
  final NetworkConnectivityService _network;

  StreamSubscription<NetworkState>? _connectivitySub;

  HoldingAreaBloc(
    this._repo,
    this._writes, {
    NetworkConnectivityService? network,
  } )  : _network = network ?? NetworkConnectivityService(),
        super( const HoldingAreaState() ) {
    on<HoldingAreaRefreshRequested>( _onRefresh );
    on<HoldingAreaRowVerbPressed>( _onRowVerb );
    on<HoldingAreaApproveAllPressed>( _onApproveAll );
    on<HoldingAreaWontFixAllPressed>( _onWontFixAll );
    on<HoldingAreaReasonChanged>( _onReasonChanged );
  }

  /// The poll interval reads the connection, same measurement as the Task List: a full
  /// page is ~2.1 MB and a terse one ~107 KB, so sixty seconds on a metered connection
  /// is rude even terse.
  @override
  Duration get pollInterval =>
      _network.isMobile ? const Duration( seconds: 180 ) : const Duration( seconds: 60 );

  @override
  Future<void> pollOnce( CancelToken token ) async {
    add( HoldingAreaRefreshRequested( cancelToken: token ) );
  }

  /// Refresh on the connectivity-RESTORED edge only. Firing on every state change would
  /// refetch on the way down too, which is a request into a connection that just failed.
  void startConnectivityRefresh() {
    _connectivitySub ??= _network.networkStateStream.listen( ( state ) {
      if ( state == NetworkState.connected ) add( const HoldingAreaRefreshRequested() );
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
      // A cancelled poll is the lifecycle rule working, NOT an error to paint.
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
      emit( state.copyWith( batchNotice: _writeError( e ) ) );
      return;
    }
    // 🔴 REFETCH RATHER THAN DROP THE ROW LOCALLY. An approved row leaves this pane, and
    // removing it here would paint a write as applied that the server may have only
    // queued — the 202 case. The fetch is what proves it left.
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
    // 🔴 THE BLANK CHECK IS HERE AS WELL AS IN THE PANE, AND THE DUPLICATION IS THE
    // POINT. The pane's check is what the operator sees; this one is what makes the rule
    // true. A batch dispatched from anywhere else — a test, a later caller, a keyboard
    // shortcut nobody wired to the button — would otherwise send N transitions the
    // server answers with N identical 422s.
    if ( event.reason.trim().isEmpty ) {
      emit( state.copyWith(
        reasonErrors : { ...state.reasonErrors, event.filer: kHoldingWontFixReasonMissing },
      ) );
      return;
    }

    await _batch(
      filer : event.filer,
      emit  : emit,
      verb  : ( _ ) => TaskVerb.wontFix( reason: event.reason.trim() ),
    );
  }

  /// Run one verb over every row in a group.
  ///
  /// ⚠️ SEQUENTIAL, NOT `Future.wait`. Fifty concurrent transitions against one store is
  /// a self-inflicted thundering herd, and the first failure in a `Future.wait` discards
  /// the outcomes of everything racing alongside it — the operator would learn that
  /// "something failed" with no way to know which rows moved.
  ///
  /// 🔴 A PARTIAL BATCH IS REPORTED AS PARTIAL. The loop does not stop at the first
  /// failure and does not pretend the rest succeeded: it counts, then says how many of
  /// how many landed. A batch that silently half-applied is the failure this pane can
  /// least afford, because the pane it half-applied in is the one the operator uses to
  /// see what is still held.
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

    for ( final id in ids ) {
      try {
        await _writes.transition( id: id, verb: verb( id ) );
        applied++;
      } on Object catch ( e ) {
        firstFailure ??= e;
      }
    }

    final next     = { ...state.busyFilers }..remove( filer );
    final complete = applied == ids.length;

    emit( state.copyWith(
      busyFilers       : next,
      // ⚠️ THE NOTICE SURVIVES THE REFETCH BELOW. Parking it in `error` would have it
      // cleared by the very refresh this batch schedules.
      batchNotice      : complete
          ? null
          : '${ids.length - applied} of ${ids.length} rows did not move '
            '(${_writeError( firstFailure! )}) — the rest did',
      clearBatchNotice : complete,
      reasons          : complete
          ? ( { ...state.reasons }..remove( filer ) )
          : state.reasons,
    ) );

    add( const HoldingAreaRefreshRequested() );
  }

  void _onReasonChanged( HoldingAreaReasonChanged event, Emitter<HoldingAreaState> emit ) {
    emit( state.copyWith(
      reasons      : { ...state.reasons, event.filer: event.reason },
      // Typing clears the complaint. Leaving it up while the box fills would make the
      // pane argue with what the operator can see.
      reasonErrors : { ...state.reasonErrors }..remove( event.filer ),
    ) );
  }

  /// The operator-facing text for a failed write.
  ///
  /// 🔴 THE 202 CASE GETS ITS OWN SENTENCE, AND IT MUST NOT SAY "FAILED".
  /// [TaskAwaitingApprovalException] means the server ACCEPTED the request and did not
  /// apply it. Reporting that as a failure would be wrong in the one direction that
  /// causes harm: the natural response to a failure is to press again, and pressing
  /// again files a second approval ticket for a change already waiting on one.
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
