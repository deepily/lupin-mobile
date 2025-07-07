import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import '../../../shared/models/job.dart';
import '../../../services/websocket/websocket_service.dart';
import 'queue_event.dart';
import 'queue_state.dart';

class QueueBloc extends Bloc<QueueEvent, QueueState> {
  final WebSocketService _webSocketService;
  StreamSubscription<dynamic>? _webSocketSubscription;

  QueueBloc({
    required WebSocketService webSocketService,
  })  : _webSocketService = webSocketService,
        super(QueueInitial()) {
    on<QueueStarted>(_onQueueStarted);
    on<QueueJobAdded>(_onQueueJobAdded);
    on<QueueJobStatusChanged>(_onQueueJobStatusChanged);
    on<QueueJobSubmitted>(_onQueueJobSubmitted);
    on<QueueRefreshRequested>(_onQueueRefreshRequested);
    on<QueueJobDeleted>(_onQueueJobDeleted);
  }

  Future<void> _onQueueStarted(
    QueueStarted event,
    Emitter<QueueState> emit,
  ) async {
    emit(const QueueLoading());

    try {
      // TODO: Load initial data from API or local storage
      final jobs = <Job>[]; // Placeholder

      // Start WebSocket connection
      await _webSocketService.connect();

      // Listen to WebSocket messages
      _webSocketSubscription = _webSocketService.stream.listen(
        (message) => _handleWebSocketMessage(message),
      );

      emit(QueueLoaded(
        todoJobs: jobs.where((j) => j.status == JobStatus.todo).toList(),
        runningJobs: jobs.where((j) => j.status == JobStatus.running).toList(),
        completedJobs: jobs.where((j) => j.status == JobStatus.completed).toList(),
        deadJobs: jobs.where((j) => j.status == JobStatus.dead).toList(),
        isConnected: _webSocketService.isConnected,
      ));
    } catch (error) {
      emit(QueueError(error: error.toString()));
    }
  }

  Future<void> _onQueueJobAdded(
    QueueJobAdded event,
    Emitter<QueueState> emit,
  ) async {
    if (state is QueueLoaded) {
      final currentState = state as QueueLoaded;
      
      List<Job> updatedTodoJobs = List.from(currentState.todoJobs);
      List<Job> updatedRunningJobs = List.from(currentState.runningJobs);
      List<Job> updatedCompletedJobs = List.from(currentState.completedJobs);
      List<Job> updatedDeadJobs = List.from(currentState.deadJobs);

      switch (event.job.status) {
        case JobStatus.todo:
          updatedTodoJobs.add(event.job);
          break;
        case JobStatus.running:
          updatedRunningJobs.add(event.job);
          break;
        case JobStatus.completed:
          updatedCompletedJobs.add(event.job);
          break;
        case JobStatus.dead:
          updatedDeadJobs.add(event.job);
          break;
      }

      emit(QueueLoaded(
        todoJobs: updatedTodoJobs,
        runningJobs: updatedRunningJobs,
        completedJobs: updatedCompletedJobs,
        deadJobs: updatedDeadJobs,
        isConnected: currentState.isConnected,
      ));
    }
  }

  Future<void> _onQueueJobStatusChanged(
    QueueJobStatusChanged event,
    Emitter<QueueState> emit,
  ) async {
    if (state is QueueLoaded) {
      final currentState = state as QueueLoaded;
      
      // Find and update the job
      Job? jobToUpdate;
      List<Job> allJobs = [
        ...currentState.todoJobs,
        ...currentState.runningJobs,
        ...currentState.completedJobs,
        ...currentState.deadJobs,
      ];

      jobToUpdate = allJobs.firstWhere(
        (job) => job.id == event.jobId,
        orElse: () => throw Exception('Job not found'),
      );

      final updatedJob = jobToUpdate.copyWith(
        status: event.newStatus,
        updatedAt: DateTime.now(),
      );

      // Redistribute jobs by status
      final updatedJobs = allJobs.map((job) => 
        job.id == event.jobId ? updatedJob : job
      ).toList();

      emit(QueueLoaded(
        todoJobs: updatedJobs.where((j) => j.status == JobStatus.todo).toList(),
        runningJobs: updatedJobs.where((j) => j.status == JobStatus.running).toList(),
        completedJobs: updatedJobs.where((j) => j.status == JobStatus.completed).toList(),
        deadJobs: updatedJobs.where((j) => j.status == JobStatus.dead).toList(),
        isConnected: currentState.isConnected,
      ));
    }
  }

  Future<void> _onQueueJobSubmitted(
    QueueJobSubmitted event,
    Emitter<QueueState> emit,
  ) async {
    try {
      // Create new job
      final newJob = Job(
        id: 'job_${DateTime.now().millisecondsSinceEpoch}',
        text: event.text,
        status: JobStatus.todo,
        createdAt: DateTime.now(),
      );

      // TODO: Send job to backend API
      // For now, just add it locally
      add(QueueJobAdded(job: newJob));

      // Send via WebSocket if connected
      if (_webSocketService.isConnected) {
        _webSocketService.sendMessage({
          'type': 'job_submit',
          'job': newJob.toJson(),
        });
      }
    } catch (error) {
      emit(QueueError(
        error: 'Failed to submit job: ${error.toString()}',
        todoJobs: state.todoJobs,
        runningJobs: state.runningJobs,
        completedJobs: state.completedJobs,
        deadJobs: state.deadJobs,
        isConnected: state.isConnected,
      ));
    }
  }

  Future<void> _onQueueRefreshRequested(
    QueueRefreshRequested event,
    Emitter<QueueState> emit,
  ) async {
    // TODO: Refresh data from backend
    add(QueueStarted());
  }

  Future<void> _onQueueJobDeleted(
    QueueJobDeleted event,
    Emitter<QueueState> emit,
  ) async {
    if (state is QueueLoaded) {
      final currentState = state as QueueLoaded;
      
      // Remove job from all lists
      final updatedTodoJobs = currentState.todoJobs
          .where((job) => job.id != event.jobId)
          .toList();
      final updatedRunningJobs = currentState.runningJobs
          .where((job) => job.id != event.jobId)
          .toList();
      final updatedCompletedJobs = currentState.completedJobs
          .where((job) => job.id != event.jobId)
          .toList();
      final updatedDeadJobs = currentState.deadJobs
          .where((job) => job.id != event.jobId)
          .toList();

      emit(QueueLoaded(
        todoJobs: updatedTodoJobs,
        runningJobs: updatedRunningJobs,
        completedJobs: updatedCompletedJobs,
        deadJobs: updatedDeadJobs,
        isConnected: currentState.isConnected,
      ));
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      switch (message['type']) {
        case 'job_update':
          final job = Job.fromJson(message['job']);
          add(QueueJobStatusChanged(
            jobId: job.id,
            newStatus: job.status,
          ));
          break;
        case 'new_job':
          final job = Job.fromJson(message['job']);
          add(QueueJobAdded(job: job));
          break;
        // Handle other message types as needed
      }
    }
  }

  @override
  Future<void> close() {
    _webSocketSubscription?.cancel();
    return super.close();
  }
}