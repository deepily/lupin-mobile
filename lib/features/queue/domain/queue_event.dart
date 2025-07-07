import 'package:equatable/equatable.dart';
import '../../../shared/models/job.dart';

abstract class QueueEvent extends Equatable {
  const QueueEvent();

  @override
  List<Object?> get props => [];
}

class QueueStarted extends QueueEvent {}

class QueueJobAdded extends QueueEvent {
  final Job job;

  const QueueJobAdded({required this.job});

  @override
  List<Object?> get props => [job];
}

class QueueJobStatusChanged extends QueueEvent {
  final String jobId;
  final JobStatus newStatus;

  const QueueJobStatusChanged({
    required this.jobId,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [jobId, newStatus];
}

class QueueJobSubmitted extends QueueEvent {
  final String text;

  const QueueJobSubmitted({required this.text});

  @override
  List<Object?> get props => [text];
}

class QueueRefreshRequested extends QueueEvent {}

class QueueJobDeleted extends QueueEvent {
  final String jobId;

  const QueueJobDeleted({required this.jobId});

  @override
  List<Object?> get props => [jobId];
}