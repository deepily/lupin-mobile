import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/finished_tasks_models.dart';
import '../data/finished_tasks_repository.dart';
import 'finished_tasks_event.dart';
import 'finished_tasks_state.dart';

/// Finished Tasks — state, window and filter selection.
///
/// ⚠️ NO TIMER LIVES HERE YET, AND THAT IS ON PURPOSE. §6.3 of the plan requires
/// foreground-pane-only polling and records that this app's BLoCs are constructed at
/// the app root, alive for the process lifetime — so a timer started here would run
/// whichever pane is showing, which is the outcome the battery rule exists to
/// prevent. The visibility signal is Phase 0's to name; this bloc refetches on demand
/// (first load, window change, pull-to-refresh, app-bar refresh) and gains its tick
/// from that signal when it exists, in one place.
class FinishedTasksBloc extends Bloc<FinishedTasksEvent, FinishedTasksState> {
  final FinishedTasksRepository _repo;
  final DateTime Function()     _now;

  List<String> _shown = List.unmodifiable( kFinishedDefaultShown );
  int          _days  = kFinishedWindowDefaultDays;

  FinishedTasksBloc(
    this._repo, {
    DateTime Function()? now,
  } )  : _now = now ?? DateTime.now,
        super( const FinishedTasksInitial() ) {
    on<FinishedTasksRequested>( _onRequested );
    on<FinishedTasksWindowPreviewed>( _onWindowPreviewed );
    on<FinishedTasksWindowChanged>( _onWindowChanged );
    on<FinishedTasksStatusToggled>( _onStatusToggled );
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

  Future<void> _fetch( Emitter<FinishedTasksState> emit ) async {
    try {
      final result = await _repo.fetchWindow( days: _days, now: _now() );
      if ( result.isTotalFailure ) {
        emit( FinishedTasksError(
          result.failures.values.first,
          _days,
        ) );
        return;
      }
      emit( FinishedTasksLoaded( result: result, shown: _shown, days: _days ) );
    } on FinishedTasksApiException catch ( e ) {
      emit( FinishedTasksError( e.message, _days ) );
    }
  }
}
