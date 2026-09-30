import 'package:dio/dio.dart';
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

/// A poll tick, or the return from a background trip.
///
/// 🔴 ITS OWN EVENT BECAUSE A POLL MUST NOT BLANK THE TABLE. `FinishedTasksRequested`
/// emits `FinishedTasksLoading`, and the screen renders that as a full-pane spinner — so
/// reusing it for the tick would replace the rows the operator is reading with a spinner
/// every sixty seconds, on a pane whose entire job is being read. The user-initiated
/// paths keep their spinner, because there the operator ASKED and expects to see the ask
/// acknowledged; a tick nobody pressed must be invisible until it has something new.
class FinishedTasksPolled extends FinishedTasksEvent {
  /// The mixin's token. Handed all the way down to Dio, or the cancellation buys
  /// nothing when the pane goes away mid-request.
  final CancelToken? cancelToken;

  const FinishedTasksPolled( { this.cancelToken } );

  // ⚠️ DELIBERATELY NOT IN `props`. Every tick carries a FRESH token, so including it
  // would make two otherwise-identical ticks unequal — harmless here, but it makes the
  // event's equality mean "same request" rather than "same intent", which is not what
  // any reader of an Equatable event expects.
  @override List<Object?> get props => [];
}
