import 'package:equatable/equatable.dart';

abstract class FinishedTasksEvent extends Equatable {
  const FinishedTasksEvent();
  @override List<Object?> get props => [];
}

/// Load (or reload) the current window. Also the pull-to-refresh and the app-bar
/// refresh action — one event, so the three paths cannot drift apart.
class FinishedTasksRequested extends FinishedTasksEvent {
  const FinishedTasksRequested();
}

/// Move the window slider WITHOUT fetching — the live preview while dragging.
class FinishedTasksWindowPreviewed extends FinishedTasksEvent {
  final int days;
  const FinishedTasksWindowPreviewed( this.days );
  @override List<Object?> get props => [ days ];
}

/// Commit a window change and refetch. Fired on slider release, not on every frame.
class FinishedTasksWindowChanged extends FinishedTasksEvent {
  final int days;
  const FinishedTasksWindowChanged( this.days );
  @override List<Object?> get props => [ days ];
}

/// Light or unlight one status pill. Purely local — the rows for every status are
/// already held, so toggling never refetches.
class FinishedTasksStatusToggled extends FinishedTasksEvent {
  final String status;
  const FinishedTasksStatusToggled( this.status );
  @override List<Object?> get props => [ status ];
}
