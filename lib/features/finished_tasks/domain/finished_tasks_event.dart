import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

/// The base of every event the Finished Tasks bloc handles.
abstract class FinishedTasksEvent extends Equatable {
  /// Creates an event.
  const FinishedTasksEvent();
  @override List<Object?> get props => [];
}

/// Loads (or reloads) the current window.
///
/// It is also the pull-to-refresh and the app-bar refresh action, one event so the
/// three paths cannot drift apart.
class FinishedTasksRequested extends FinishedTasksEvent {
  /// Creates the event.
  const FinishedTasksRequested();
}

/// Moves the window slider without fetching, the live preview while dragging.
class FinishedTasksWindowPreviewed extends FinishedTasksEvent {
  /// The previewed window, in days.
  final int days;

  /// Creates the event for a previewed window.
  const FinishedTasksWindowPreviewed( this.days );
  @override List<Object?> get props => [ days ];
}

/// Commits a window change and refetches, fired on slider release, not on every frame.
class FinishedTasksWindowChanged extends FinishedTasksEvent {
  /// The committed window, in days.
  final int days;

  /// Creates the event for a committed window.
  const FinishedTasksWindowChanged( this.days );
  @override List<Object?> get props => [ days ];
}

/// Lights or unlights one status pill.
///
/// It is purely local: the rows for every status are already held, so toggling never
/// refetches.
class FinishedTasksStatusToggled extends FinishedTasksEvent {
  /// The status whose pill was toggled.
  final String status;

  /// Creates the event for a toggled status.
  const FinishedTasksStatusToggled( this.status );
  @override List<Object?> get props => [ status ];
}

/// A poll tick, or the return from a background trip.
///
/// It is its own event because a poll must not blank the table.
/// `FinishedTasksRequested` emits `FinishedTasksLoading`, which the screen renders as a
/// full-pane spinner, so reusing it would replace the rows being read every sixty
/// seconds.
/// The user-initiated paths keep their spinner so the request is acknowledged; a tick
/// nobody pressed stays invisible until it has something new.
class FinishedTasksPolled extends FinishedTasksEvent {
  /// The mixin's cancel token, handed to Dio so the pane leaving cancels the request.
  final CancelToken? cancelToken;

  /// Creates a tick, optionally carrying a cancel token.
  const FinishedTasksPolled( { this.cancelToken } );

  // The token is left out of `props`: every tick carries a fresh one, and equality
  // should mean the same intent, not the same request.
  @override List<Object?> get props => [];
}
