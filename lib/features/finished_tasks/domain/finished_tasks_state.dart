import 'package:equatable/equatable.dart';

import '../data/finished_tasks_models.dart';
import '../data/finished_tasks_repository.dart';

/// The base of every state the Finished Tasks bloc emits.
abstract class FinishedTasksState extends Equatable {
  /// Creates a state.
  const FinishedTasksState();
  @override List<Object?> get props => [];
}

/// Nothing has been requested yet.
class FinishedTasksInitial extends FinishedTasksState {
  /// Creates the initial state.
  const FinishedTasksInitial();
}

/// A fetch is in flight.
class FinishedTasksLoading extends FinishedTasksState {
  /// The window being loaded, so the slider does not jump back while a fetch runs.
  final int days;

  /// Creates a loading state for a window.
  const FinishedTasksLoading( this.days );
  @override List<Object?> get props => [ days ];
}

/// A window came back, wholly or partly.
///
/// A partial result is a first-class outcome, not an error.
/// One status failing while the others answered is a pane that can still do its job.
/// A blank error screen would throw away rows we hold, and a silent omission would
/// render a failed fetch as "nothing was closed".
class FinishedTasksLoaded extends FinishedTasksState {
  /// The fetch outcome, keeping "none" and "unknown" apart.
  final FinishedFetchResult result;
  /// The statuses currently lit.
  final List<String>        shown;
  /// The window, in days.
  final int                 days;

  /// Creates a loaded state.
  const FinishedTasksLoaded( {
    required this.result,
    required this.shown,
    required this.days,
  } );

  /// The rows to render: lit statuses only, newest first.
  List<FinishedTaskEvent> get rows => mergeShownEvents( result.eventsByStatus, shown );

  /// True when some statuses came back and others did not.
  bool get isPartial => result.isPartial;

  /// Returns a copy with the given fields replaced.
  FinishedTasksLoaded copyWith( {
    FinishedFetchResult? result,
    List<String>?        shown,
    int?                 days,
  } ) {
    return FinishedTasksLoaded(
      result : result ?? this.result,
      shown  : shown  ?? this.shown,
      days   : days   ?? this.days,
    );
  }

  @override
  List<Object?> get props => [
    days,
    shown,
    result.eventsByStatus.length,
    result.failures.length,
    // The row identity, so a repaint after a refetch is not mistaken for a no-op.
    rows.map( ( e ) => e.id ).join( "," ),
  ];
}

/// Every status failed to load.
class FinishedTasksError extends FinishedTasksState {
  /// The message to show.
  final String message;
  /// The window that failed, in days.
  final int    days;

  /// Creates an error state.
  const FinishedTasksError( this.message, this.days );
  @override List<Object?> get props => [ message, days ];
}
