import 'package:equatable/equatable.dart';

import '../data/queue_models.dart';

/// Base class for states emitted by `QueueBloc`.
abstract class QueueState extends Equatable {
  /// Creates a state.
  const QueueState();
  @override List<Object?> get props => [];
}

/// Nothing has been loaded yet.
class QueueInitial extends QueueState {
  /// Creates the state.
  const QueueInitial();
}

/// A load is in progress.
class QueueLoading extends QueueState {
  /// Creates the state.
  const QueueLoading();
}

/// A queue snapshot was loaded.
class QueueSnapshotLoaded extends QueueState {
  /// The loaded snapshot.
  final QueueResponse snapshot;

  /// Creates the state.
  const QueueSnapshotLoaded( this.snapshot );
  @override List<Object?> get props => [ snapshot.queueName, snapshot.totalJobs ];
}

/// A page of job history was loaded.
class QueueHistoryLoaded extends QueueState {
  /// The loaded page.
  final JobHistoryPage page;

  /// Creates the state.
  const QueueHistoryLoaded( this.page );
  @override List<Object?> get props => [ page.total, page.offset ];
}

/// A job's interactions were loaded.
class QueueInteractionsLoaded extends QueueState {
  /// The loaded interactions.
  final JobInteractionsResponse data;

  /// Creates the state.
  const QueueInteractionsLoaded( this.data );
  @override List<Object?> get props => [ data.jobId, data.interactionCount ];
}

/// A submission is in flight.
class QueueSubmitting extends QueueState {
  /// Creates the state.
  const QueueSubmitting();
}

/// An agentic job was accepted onto the queue.
class QueueSubmitted extends QueueState {
  /// The server's reply.
  final PushJobResponse response;

  /// Creates the state.
  const QueueSubmitted( this.response );
  @override List<Object?> get props => [ response.jobId ];
}

/// A v2 ask completed synchronously, so there is nothing to poll.
///
/// The answer, or the first clarifying question, is already in [response].
class QueueAnswered extends QueueState {
  /// The server's reply.
  final AskResponse response;

  /// Creates the state.
  const QueueAnswered( this.response );
  @override List<Object?> get props => [ response.traceId, response.status ];
}

/// A job action finished.
class QueueActionComplete extends QueueState {
  /// Confirmation text for the user.
  final String message;

  /// Creates the state.
  const QueueActionComplete( this.message );
  @override List<Object?> get props => [ message ];
}

/// A request failed.
class QueueError extends QueueState {
  /// Failure text for the user.
  final String message;

  /// Creates the state.
  const QueueError( this.message );
  @override List<Object?> get props => [ message ];
}
