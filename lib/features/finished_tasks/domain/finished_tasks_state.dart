import 'package:equatable/equatable.dart';

import '../data/finished_tasks_models.dart';
import '../data/finished_tasks_repository.dart';

abstract class FinishedTasksState extends Equatable {
  const FinishedTasksState();
  @override List<Object?> get props => [];
}

class FinishedTasksInitial extends FinishedTasksState {
  const FinishedTasksInitial();
}

class FinishedTasksLoading extends FinishedTasksState {
  /// The window being loaded, so the slider does not jump back while a fetch runs.
  final int days;
  const FinishedTasksLoading( this.days );
  @override List<Object?> get props => [ days ];
}

/// A window came back — wholly or partly.
///
/// ⚠️ PARTLY IS A FIRST-CLASS OUTCOME, not an error. One status failing while the
/// others answered is a pane that can still do its job, and saying so beats both
/// alternatives: a blank error screen throws away rows we hold, and a silent
/// omission renders a failed fetch as "nothing was closed".
class FinishedTasksLoaded extends FinishedTasksState {
  final FinishedFetchResult result;
  final List<String>        shown;
  final int                 days;

  const FinishedTasksLoaded( {
    required this.result,
    required this.shown,
    required this.days,
  } );

  /// The rows to render: lit statuses only, newest first.
  List<FinishedTaskEvent> get rows => mergeShownEvents( result.eventsByStatus, shown );

  bool get isPartial => result.isPartial;

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

class FinishedTasksError extends FinishedTasksState {
  final String message;
  final int    days;
  const FinishedTasksError( this.message, this.days );
  @override List<Object?> get props => [ message, days ];
}
