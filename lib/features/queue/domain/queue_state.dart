import 'package:equatable/equatable.dart';
import '../../../shared/models/job.dart';

abstract class QueueState extends Equatable {
  final List<Job> todoJobs;
  final List<Job> runningJobs;
  final List<Job> completedJobs;
  final List<Job> deadJobs;
  final bool isConnected;
  final String? error;

  const QueueState({
    this.todoJobs = const [],
    this.runningJobs = const [],
    this.completedJobs = const [],
    this.deadJobs = const [],
    this.isConnected = false,
    this.error,
  });

  @override
  List<Object?> get props => [
        todoJobs,
        runningJobs,
        completedJobs,
        deadJobs,
        isConnected,
        error,
      ];
}

class QueueInitial extends QueueState {}

class QueueLoading extends QueueState {
  const QueueLoading({
    super.todoJobs,
    super.runningJobs,
    super.completedJobs,
    super.deadJobs,
    super.isConnected,
  });
}

class QueueLoaded extends QueueState {
  const QueueLoaded({
    required List<Job> todoJobs,
    required List<Job> runningJobs,
    required List<Job> completedJobs,
    required List<Job> deadJobs,
    required bool isConnected,
  }) : super(
          todoJobs: todoJobs,
          runningJobs: runningJobs,
          completedJobs: completedJobs,
          deadJobs: deadJobs,
          isConnected: isConnected,
        );
}

class QueueError extends QueueState {
  const QueueError({
    required String error,
    List<Job> todoJobs = const [],
    List<Job> runningJobs = const [],
    List<Job> completedJobs = const [],
    List<Job> deadJobs = const [],
    bool isConnected = false,
  }) : super(
          todoJobs: todoJobs,
          runningJobs: runningJobs,
          completedJobs: completedJobs,
          deadJobs: deadJobs,
          isConnected: isConnected,
          error: error,
        );
}