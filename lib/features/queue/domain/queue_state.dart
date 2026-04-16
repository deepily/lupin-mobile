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

class QueueSubmitted extends QueueState {
  final PushJobResponse response;
  const QueueSubmitted( this.response );
  @override List<Object?> get props => [ response.jobId ];
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
