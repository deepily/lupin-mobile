import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../../fleet/domain/pane_visibility_mixin.dart';
import '../data/finished_tasks_models.dart';
import '../data/finished_tasks_repository.dart';
import 'finished_tasks_event.dart';
import 'finished_tasks_state.dart';

/// Finished Tasks state, window and filter selection, and the poll loop.
///
/// The bloc gets its tick from [PanePollingMixin] and its visibility signal from
/// [PaneVisibilityMixin], so the timer runs only while the pane shows.
/// `buildFinishedTasksBloc()` is a factory used inside a route-scoped `BlocProvider`,
/// not an app-root singleton, so the bloc and its timer die with the route.
///
/// A tick is not a request the operator made.
/// See [FinishedTasksPolled]: the poll path does not emit `FinishedTasksLoading`,
/// because that renders as a full-pane spinner over rows somebody is reading.
class FinishedTasksBloc extends Bloc<FinishedTasksEvent, FinishedTasksState>
    with PaneVisibilityMixin<FinishedTasksEvent, FinishedTasksState>,
        PanePollingMixin<FinishedTasksEvent, FinishedTasksState> {
  final FinishedTasksRepository _repo;
  final DateTime Function()     _now;
  final NetworkConnectivityService _network;

  List<String> _shown = List.unmodifiable( kFinishedDefaultShown );
  int          _days  = kFinishedWindowDefaultDays;

  /// Creates the bloc over [_repo], with an injectable clock and connectivity service.
  FinishedTasksBloc(
    this._repo, {
    DateTime Function()? now,
    NetworkConnectivityService? network,
  } )  : _now     = now ?? DateTime.now,
        _network = network ?? NetworkConnectivityService(),
        super( const FinishedTasksInitial() ) {
    on<FinishedTasksRequested>( _onRequested );
    on<FinishedTasksPolled>( _onPolled );
    on<FinishedTasksWindowPreviewed>( _onWindowPreviewed );
    on<FinishedTasksWindowChanged>( _onWindowChanged );
    on<FinishedTasksStatusToggled>( _onStatusToggled );
  }

  /// Whether the connection is metered, which selects the poll interval.
  ///
  /// The interval itself is [PanePollingMixin.pollInterval], 60 seconds on Wi-Fi and 180
  /// on mobile data, and is not restated here.
  @override
  bool get isMeteredConnection => _network.isMobile;

  /// The mixin's poll hook.
  ///
  /// The token goes all the way down to Dio, so a pane that disappears mid-request
  /// cancels the request and not merely the timer.
  @override
  Future<void> pollOnce( CancelToken token ) async {
    add( FinishedTasksPolled( cancelToken: token ) );
  }

  /// The window currently selected, clamped. Exposed for the slider's initial value.
  int get days => _days;

  /// The lit statuses, in kFinishedStatuses order.
  List<String> get shown => _shown;

  Future<void> _onRequested(
    FinishedTasksRequested event,
    Emitter<FinishedTasksState> emit,
  ) async {
    emit( FinishedTasksLoading( _days ) );
    await _fetch( emit );
  }

  /// A poll tick. Fetches without emitting `FinishedTasksLoading`.
  ///
  /// A failed tick leaves the rows standing.
  /// An operator reading a table does not want it replaced by an error view because one
  /// poll lost the network.
  /// A user-initiated fetch still surfaces its error, because there somebody asked and
  /// silence would be the wrong answer.
  Future<void> _onPolled(
    FinishedTasksPolled event,
    Emitter<FinishedTasksState> emit,
  ) async {
    await _fetch(
      emit,
      cancelToken : event.cancelToken,
      // Silent only once there are rows to keep.
      // `onPaneVisible` fires a tick the moment the pane appears, so this is also the
      // pane's first load, and a silent first-load failure would leave
      // `FinishedTasksInitial` on screen, which renders as a spinner forever.
      // With no rows yet, an error is painted. With rows on screen, a failed tick keeps
      // them and a pull to refresh surfaces the error.
      silent      : state is FinishedTasksLoaded,
    );
  }

  void _onWindowPreviewed(
    FinishedTasksWindowPreviewed event,
    Emitter<FinishedTasksState> emit,
  ) {
    _days = clampWindowDays( event.days );
    final current = state;
    // A preview must not discard rows already on screen; the slider is a live label,
    // not a reload.
    if ( current is FinishedTasksLoaded ) {
      emit( current.copyWith( days: _days ) );
    }
  }

  Future<void> _onWindowChanged(
    FinishedTasksWindowChanged event,
    Emitter<FinishedTasksState> emit,
  ) async {
    _days = clampWindowDays( event.days );
    emit( FinishedTasksLoading( _days ) );
    await _fetch( emit );
  }

  void _onStatusToggled(
    FinishedTasksStatusToggled event,
    Emitter<FinishedTasksState> emit,
  ) {
    _shown = toggleShownStatus( _shown, event.status );
    final current = state;
    // Purely local: every status's rows are already held, so a toggle never refetches.
    if ( current is FinishedTasksLoaded ) {
      emit( current.copyWith( shown: _shown ) );
    }
  }

  /// One window fetch.
  ///
  /// Requires:
  ///     - silent is true only for a poll tick, because nobody pressed anything
  ///
  /// Ensures:
  ///     - a success always paints, silent or not; fresh rows are never withheld
  ///     - a silent failure paints nothing, leaving the rows already on screen
  ///     - a user-initiated failure paints the error view, because somebody asked
  ///     - a cancelled fetch paints nothing on either path, because the pane is going away
  Future<void> _fetch(
    Emitter<FinishedTasksState> emit, {
    CancelToken? cancelToken,
    bool silent = false,
  } ) async {
    try {
      final result = await _repo.fetchWindow(
        days        : _days,
        now         : _now(),
        cancelToken : cancelToken,
      );
      if ( result.isTotalFailure ) {
        if ( silent ) return;
        emit( FinishedTasksError(
          result.failures.values.first,
          _days,
        ) );
        return;
      }
      emit( FinishedTasksLoaded( result: result, shown: _shown, days: _days ) );
    } on DioException catch ( e ) {
      // The repository rethrows a cancel unflattened so it can be told apart here; the
      // pane went away, so nothing is painted.
      if ( e.type != DioExceptionType.cancel ) rethrow;
    } on FinishedTasksApiException catch ( e ) {
      if ( silent ) return;
      emit( FinishedTasksError( e.message, _days ) );
    }
  }
}
