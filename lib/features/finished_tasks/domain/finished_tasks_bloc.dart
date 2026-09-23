import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../data/finished_tasks_models.dart';
import '../data/finished_tasks_repository.dart';
import 'finished_tasks_event.dart';
import 'finished_tasks_state.dart';

/// Finished Tasks — state, window and filter selection, and now the poll loop.
///
/// 🔴 THIS BLOC USED TO SAY "NO TIMER LIVES HERE YET, AND THAT IS ON PURPOSE." It was
/// right at the time and the reason it gave has since been answered: *"a timer started
/// here would run whichever pane is showing … The visibility signal is Phase 0's to name;
/// this bloc gains its tick from that signal when it exists."* [PanePollingMixin] is that
/// signal, and `buildFinishedTasksBloc()` is a FACTORY used inside a route-scoped
/// `BlocProvider` (`home_screen.dart:216`), not an app-root singleton — so the premise
/// that made a timer dangerous no longer holds either.
///
/// ⇒ Gap G7 closes by connecting the two, not by writing a timer. The old comment is
/// quoted rather than deleted because a reader who remembers it deserves to know it was
/// satisfied rather than overruled.
///
/// ⚠️ A TICK IS NOT A REQUEST THE OPERATOR MADE. See [FinishedTasksPolled] — the poll
/// path deliberately does not emit `FinishedTasksLoading`, because that renders as a
/// full-pane spinner over rows somebody is reading.
class FinishedTasksBloc extends Bloc<FinishedTasksEvent, FinishedTasksState>
    with PanePollingMixin<FinishedTasksEvent, FinishedTasksState> {
  final FinishedTasksRepository _repo;
  final DateTime Function()     _now;
  final NetworkConnectivityService _network;

  List<String> _shown = List.unmodifiable( kFinishedDefaultShown );
  int          _days  = kFinishedWindowDefaultDays;

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

  /// Which service answers "is this connection metered". The interval itself is
  /// [PanePollingMixin.pollInterval] — 60 s on Wi-Fi, 180 s on mobile data — and is not
  /// restated here, because four hand-written copies of one rule is how two of them end
  /// up disagreeing.
  @override
  bool get isMeteredConnection => _network.isMobile;

  /// The mixin's poll hook. The token goes all the way down to Dio, so a pane that
  /// disappears mid-request cancels the REQUEST and not merely the timer.
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

  /// A poll tick. Fetches WITHOUT emitting `FinishedTasksLoading`.
  ///
  /// 🔴 AND A FAILED TICK LEAVES THE ROWS STANDING. An operator reading a table does not
  /// want it replaced by an error view because one poll lost the network — they want the
  /// rows they were reading, and the next tick will either fix it or the pane will still
  /// be wrong when they pull to refresh. A user-initiated fetch still surfaces its error,
  /// because there somebody asked and silence would be the wrong answer.
  Future<void> _onPolled(
    FinishedTasksPolled event,
    Emitter<FinishedTasksState> emit,
  ) async {
    await _fetch(
      emit,
      cancelToken : event.cancelToken,
      // 🔴 SILENT ONLY ONCE THERE ARE ROWS TO KEEP, AND THE CONDITION IS LOAD-BEARING.
      // `onPaneVisible` fires a tick the moment the pane appears, so THIS is also the
      // pane's first load — and a first load that failed silently would leave
      // `FinishedTasksInitial` on screen, which renders as a spinner forever. That is
      // exactly the hardware bug Rick found on 2026-09-22, re-entered through the back
      // door of a well-meant "polls should be quiet" rule, and it would be worse than
      // the original because the original had no test claiming it was fixed.
      //
      // ⇒ No rows yet → an error is REAL NEWS and is painted. Rows already on screen →
      // a failed tick keeps them; the next tick fixes it, or the operator pulls to
      // refresh and asks properly, and then they are told.
      silent      : state is FinishedTasksLoaded,
    );
  }

  void _onWindowPreviewed(
    FinishedTasksWindowPreviewed event,
    Emitter<FinishedTasksState> emit,
  ) {
    _days = clampWindowDays( event.days );
    final current = state;
    // A preview must not discard rows already on screen — the slider is a live
    // label, not a reload.
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
    // Purely local: every status's rows are already held, so a toggle never
    // refetches and never costs the phone a request.
    if ( current is FinishedTasksLoaded ) {
      emit( current.copyWith( shown: _shown ) );
    }
  }

  /// One window fetch.
  ///
  /// Requires:
  ///     - silent is true ONLY for a poll tick — nobody pressed anything
  ///
  /// Ensures:
  ///     - a success always paints, silent or not; fresh rows are never withheld
  ///     - a silent FAILURE paints nothing, leaving the rows already on screen
  ///     - a user-initiated failure paints the error view, because somebody asked
  ///     - a CANCELLED fetch paints nothing on either path: the pane is going away
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
      // The repository rethrows a cancel unflattened precisely so it can be told apart
      // here. The pane went away; painting anything would paint it on the way out.
      if ( e.type != DioExceptionType.cancel ) rethrow;
    } on FinishedTasksApiException catch ( e ) {
      if ( silent ) return;
      emit( FinishedTasksError( e.message, _days ) );
    }
  }
}
