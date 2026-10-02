import 'dart:async';
import '../../shared/models/models.dart';
import 'base_repository.dart';

/// Repository interface for Job entities
abstract class JobRepository extends PaginatedRepository<Job, String> 
    implements RealtimeRepository<Job, String> {
  /// Find jobs by status
  Future<List<Job>> findByStatus(JobStatus status);
  
  /// Find jobs by status with pagination
  Future<PaginatedResult<Job>> findByStatusPaginated(
    JobStatus status, {
    int page = 0,
    int size = 20,
  });
  
  /// Find jobs by user
  Future<List<Job>> findByUser(String userId);
  
  /// Find jobs by session
  Future<List<Job>> findBySession(String sessionId);
  
  /// Find jobs created within time range
  Future<List<Job>> findByTimeRange(DateTime start, DateTime end);
  
  /// Find jobs with text containing query
  Future<List<Job>> findByTextSearch(String query);
  
  /// Get job statistics
  Future<JobStats> getJobStats({String? userId, String? sessionId});
  
  /// Get jobs by priority (if metadata contains priority)
  Future<List<Job>> findByPriority(String priority);
  
  /// Sets a job's status
  Future<Job> updateStatus(String jobId, JobStatus status);
  
  /// Stores a job's result
  Future<Job> updateResult(String jobId, String result);
  
  /// Stores a job's error
  Future<Job> updateError(String jobId, String error);
  
  /// Get active jobs (todo + running)
  Future<List<Job>> getActiveJobs();
  
  /// Get completed jobs for user
  Future<List<Job>> getCompletedJobs(String userId, {int? limit});
  
  /// Get failed jobs for debugging
  Future<List<Job>> getFailedJobs({int? limit});
  
  /// Archive old completed jobs
  Future<void> archiveCompletedJobs({Duration? olderThan});
  
  /// Get job queue position
  Future<int> getQueuePosition(String jobId);
  
  /// Requeue failed job
  Future<Job> requeueJob(String jobId);
}

/// Job statistics
class JobStats {
  /// Number of jobs.
  final int totalJobs;
  /// Jobs waiting to run.
  final int todoJobs;
  /// Jobs currently running.
  final int runningJobs;
  /// Jobs that finished successfully.
  final int completedJobs;
  /// Jobs that failed for good.
  final int deadJobs;
  /// Mean time a job took to process.
  final Duration averageProcessingTime;
  /// Share of jobs that completed.
  final double successRate;
  /// Job counts by hour of day.
  final Map<String, int> jobsByHour;
  /// Error counts by error type.
  final Map<String, int> errorsByType;

  /// Creates the stats; every field is required.
  const JobStats({
    required this.totalJobs,
    required this.todoJobs,
    required this.runningJobs,
    required this.completedJobs,
    required this.deadJobs,
    required this.averageProcessingTime,
    required this.successRate,
    this.jobsByHour = const {},
    this.errorsByType = const {},
  });

  /// Serializes the stats.
  Map<String, dynamic> toJson() {
    return {
      'total_jobs': totalJobs,
      'todo_jobs': todoJobs,
      'running_jobs': runningJobs,
      'completed_jobs': completedJobs,
      'dead_jobs': deadJobs,
      'average_processing_time': averageProcessingTime.inMilliseconds,
      'success_rate': successRate,
      'jobs_by_hour': jobsByHour,
      'errors_by_type': errorsByType,
    };
  }
}