import 'package:equatable/equatable.dart';

import '../data/queue_models.dart';

abstract class QueueState extends Equatable {
  const QueueState();
  @override List<Object?> get props => [];
}

class QueueInitial extends QueueState {
  const QueueInitial();
}

class QueueLoading extends QueueState {
  const QueueLoading();
}

class QueueSnapshotLoaded extends QueueState {
  final QueueResponse snapshot;
  const QueueSnapshotLoaded( this.snapshot );
  @override List<Object?> get props => [ snapshot.queueName, snapshot.totalJobs ];
}

class QueueHistoryLoaded extends QueueState {
  final JobHistoryPage page;
  const QueueHistoryLoaded( this.page );
  @override List<Object?> get props => [ page.total, page.offset ];
}

class QueueInteractionsLoaded extends QueueState {
  final JobInteractionsResponse data;
  const QueueInteractionsLoaded( this.data );
  @override List<Object?> get props => [ data.jobId, data.interactionCount ];
}

class QueueSubmitting extends QueueState {
  const QueueSubmitting();
}

/// An agentic job was accepted onto the queue (POST /api/push-agentic).
class QueueSubmitted extends QueueState {
  final PushJobResponse response;
  const QueueSubmitted( this.response );
  @override List<Object?> get props => [ response.jobId ];
}

/// A v2 ask completed synchronously (POST /api/v2/ask) — the answer, or the
/// first clarifying question, is already in [response]. Nothing to poll.
class QueueAnswered extends QueueState {
  final AskResponse response;
  const QueueAnswered( this.response );
  @override List<Object?> get props => [ response.traceId, response.status ];
}

class QueueActionComplete extends QueueState {
  final String message;
  const QueueActionComplete( this.message );
  @override List<Object?> get props => [ message ];
}

class QueueError extends QueueState {
  final String message;
  const QueueError( this.message );
  @override List<Object?> get props => [ message ];
}
