import 'dart:async';
import '../../../shared/models/models.dart';
import '../job_repository.dart';
import '../base_repository.dart';
import 'shared_preferences_repository.dart';

class JobRepositoryImpl extends SharedPreferencesRepository<Job, String> 
    implements JobRepository {
  
  final StreamController<List<Job>> _jobStreamController = 
      StreamController<List<Job>>.broadcast();
  
  JobRepositoryImpl() : super('job');
  
  @override
  Map<String, dynamic> toJson(Job entity) => entity.toJson();
  
  @override
  Job fromJson(Map<String, dynamic> json) => Job.fromJson(json);
  
  @override
  String getId(Job entity) => entity.id;
  
  @override
  Future<Job> create(Job entity) async {
    final result = await super.create(entity);
    _notifyListeners();
    return result;
  }
  
  @override
  Future<Job> update(Job entity) async {
    final result = await super.update(entity);
    _notifyListeners();
    return result;
  }
  
  @override
  Future<void> deleteById(String id) async {
    await super.deleteById(id);
    _notifyListeners();
  }
  
  @override
  Future<List<Job>> findByStatus(JobStatus status) async {
    return await findWhere((job) => job.status == status);
  }
  
  @override
  Future<PaginatedResult<Job>> findByStatusPaginated(
    JobStatus status, {
    int page = 0,
    int size = 20,
  }) async {
    final allJobs = await findByStatus(status);
    final startIndex = page * size;
    final endIndex = (startIndex + size).clamp(0, allJobs.length);
    
    final pageItems = allJobs.sublist(startIndex, endIndex);
    
    return PaginatedResult(
      items: pageItems,
      totalCount: allJobs.length,
      page: page,
      size: size,
      hasNext: endIndex < allJobs.length,
      hasPrevious: page > 0,
    );
  }
  
  @override
  Future<List<Job>> findByUser(String userId) async {
    return await findWhere((job) => 
        job.metadata?['user_id'] == userId);
  }
  
  @override
  Future<List<Job>> findBySession(String sessionId) async {
    return await findWhere((job) => 
        job.metadata?['session_id'] == sessionId);
  }
  
  @override
  Future<List<Job>> findByTimeRange(DateTime start, DateTime end) async {
    return await findWhere((job) => 
        job.createdAt.isAfter(start) && job.createdAt.isBefore(end));
  }
  
  @override
  Future<List<Job>> findByTextSearch(String query) async {
    final lowercaseQuery = query.toLowerCase();
    return await findWhere((job) => 
        job.text.toLowerCase().contains(lowercaseQuery));
  }
  
  @override
  Future<JobStats> getJobStats({String? userId, String? sessionId}) async {
    List<Job> jobs = await findAll();
    
    // Filter by user or session if specified
    if (userId != null) {
      jobs = jobs.where((job) => job.metadata?['user_id'] == userId).toList();
    }
    if (sessionId != null) {
      jobs = jobs.where((job) => job.metadata?['session_id'] == sessionId).toList();
    }
    
    final todoJobs = jobs.where((job) => job.status == JobStatus.todo).length;
    final runningJobs = jobs.where((job) => job.status == JobStatus.running).length;
    final completedJobs = jobs.where((job) => job.status == JobStatus.completed).length;
    final deadJobs = jobs.where((job) => job.status == JobStatus.dead).length;
    
    // Calculate average processing time (mock)
    final averageProcessingTime = Duration(minutes: 2);
    
    // Calculate success rate
    final successRate = jobs.isNotEmpty 
        ? completedJobs / jobs.length 
        : 0.0;
    
    return JobStats(
      totalJobs: jobs.length,
      todoJobs: todoJobs,
      runningJobs: runningJobs,
      completedJobs: completedJobs,
      deadJobs: deadJobs,
      averageProcessingTime: averageProcessingTime,
      successRate: successRate,
    );
  }
  
  @override
  Future<List<Job>> findByPriority(String priority) async {
    return await findWhere((job) => 
        job.metadata?['priority'] == priority);
  }
  
  @override
  Future<Job> updateStatus(String jobId, JobStatus status) async {
    final job = await findById(jobId);
    if (job == null) {
      throw Exception('Job with id $jobId not found');
    }
    
    final updatedJob = job.copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    
    return await update(updatedJob);
  }
  
  @override
  Future<Job> updateResult(String jobId, String result) async {
    final job = await findById(jobId);
    if (job == null) {
      throw Exception('Job with id $jobId not found');
    }
    
    final updatedJob = job.copyWith(
      result: result,
      status: JobStatus.completed,
      updatedAt: DateTime.now(),
    );
    
    return await update(updatedJob);
  }
  
  @override
  Future<Job> updateError(String jobId, String error) async {
    final job = await findById(jobId);
    if (job == null) {
      throw Exception('Job with id $jobId not found');
    }
    
    final updatedJob = job.copyWith(
      error: error,
      status: JobStatus.dead,
      updatedAt: DateTime.now(),
    );
    
    return await update(updatedJob);
  }
  
  @override
  Future<List<Job>> getActiveJobs() async {
    return await findWhere((job) => 
        job.status == JobStatus.todo || job.status == JobStatus.running);
  }
  
  @override
  Future<List<Job>> getCompletedJobs(String userId, {int? limit}) async {
    List<Job> jobs = await findWhere((job) => 
        job.status == JobStatus.completed && 
        job.metadata?['user_id'] == userId);
    
    // Sort by completion time (newest first)
    jobs.sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    
    if (limit != null && jobs.length > limit) {
      jobs = jobs.sublist(0, limit);
    }
    
    return jobs;
  }
  
  @override
  Future<List<Job>> getFailedJobs({int? limit}) async {
    List<Job> jobs = await findByStatus(JobStatus.dead);
    
    // Sort by failure time (newest first)
    jobs.sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    
    if (limit != null && jobs.length > limit) {
      jobs = jobs.sublist(0, limit);
    }
    
    return jobs;
  }
  
  @override
  Future<void> archiveCompletedJobs({Duration? olderThan}) async {
    final cutoff = olderThan != null 
        ? DateTime.now().subtract(olderThan)
        : DateTime.now().subtract(Duration(days: 30));
    
    final oldJobs = await findWhere((job) => 
        job.status == JobStatus.completed && 
        job.updatedAt != null &&
        job.updatedAt!.isBefore(cutoff));
    
    for (final job in oldJobs) {
      await deleteById(job.id);
    }
  }
  
  @override
  Future<int> getQueuePosition(String jobId) async {
    final todoJobs = await findByStatus(JobStatus.todo);
    todoJobs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    for (int i = 0; i < todoJobs.length; i++) {
      if (todoJobs[i].id == jobId) {
        return i + 1; // 1-based position
      }
    }
    
    return -1; // Not found in queue
  }
  
  @override
  Future<Job> requeueJob(String jobId) async {
    return await updateStatus(jobId, JobStatus.todo);
  }
  
  // PaginatedRepository methods
  @override
  Future<PaginatedResult<Job>> findPaginated({
    int page = 0,
    int size = 20,
    String? sortBy,
    bool ascending = true,
    Map<String, dynamic>? filters,
  }) async {
    List<Job> allJobs = await findAll();
    
    // Apply filters
    if (filters != null) {
      allJobs = allJobs.where((job) {
        return filters.entries.every((entry) {
          final key = entry.key;
          final value = entry.value;
          
          switch (key) {
            case 'status':
              return job.status.name == value;
            case 'user_id':
              return job.metadata?['user_id'] == value;
            case 'session_id':
              return job.metadata?['session_id'] == value;
            default:
              return true;
          }
        });
      }).toList();
    }
    
    // Sort
    if (sortBy != null) {
      allJobs.sort((a, b) {
        dynamic aValue, bValue;
        
        switch (sortBy) {
          case 'createdAt':
            aValue = a.createdAt;
            bValue = b.createdAt;
            break;
          case 'updatedAt':
            aValue = a.updatedAt;
            bValue = b.updatedAt;
            break;
          case 'text':
            aValue = a.text;
            bValue = b.text;
            break;
          default:
            aValue = a.createdAt;
            bValue = b.createdAt;
        }
        
        if (aValue == null && bValue == null) return 0;
        if (aValue == null) return 1;
        if (bValue == null) return -1;
        
        final comparison = aValue.compareTo(bValue);
        return ascending ? comparison : -comparison;
      });
    }
    
    // Paginate
    final startIndex = page * size;
    final endIndex = (startIndex + size).clamp(0, allJobs.length);
    final pageItems = allJobs.sublist(startIndex, endIndex);
    
    return PaginatedResult(
      items: pageItems,
      totalCount: allJobs.length,
      page: page,
      size: size,
      hasNext: endIndex < allJobs.length,
      hasPrevious: page > 0,
    );
  }
  
  @override
  Future<PaginatedResult<Job>> search(
    String query, {
    int page = 0,
    int size = 20,
    List<String>? searchFields,
  }) async {
    final searchResults = await findByTextSearch(query);
    
    final startIndex = page * size;
    final endIndex = (startIndex + size).clamp(0, searchResults.length);
    final pageItems = searchResults.sublist(startIndex, endIndex);
    
    return PaginatedResult(
      items: pageItems,
      totalCount: searchResults.length,
      page: page,
      size: size,
      hasNext: endIndex < searchResults.length,
      hasPrevious: page > 0,
    );
  }
  
  // RealtimeRepository methods
  @override
  Stream<List<Job>> watchAll() {
    return _jobStreamController.stream;
  }
  
  @override
  Stream<Job?> watchById(String id) {
    return _jobStreamController.stream.map((jobs) {
      try {
        return jobs.firstWhere((job) => job.id == id);
      } catch (e) {
        return null;
      }
    });
  }
  
  @override
  Stream<List<Job>> watchWhere(Map<String, dynamic> criteria) {
    return _jobStreamController.stream.map((jobs) {
      return jobs.where((job) {
        return criteria.entries.every((entry) {
          final key = entry.key;
          final value = entry.value;
          
          switch (key) {
            case 'status':
              return job.status.name == value;
            case 'user_id':
              return job.metadata?['user_id'] == value;
            case 'session_id':
              return job.metadata?['session_id'] == value;
            default:
              return true;
          }
        });
      }).toList();
    });
  }
  
  Future<void> _notifyListeners() async {
    final allJobs = await findAll();
    _jobStreamController.add(allJobs);
  }
  
  void dispose() {
    _jobStreamController.close();
  }
}