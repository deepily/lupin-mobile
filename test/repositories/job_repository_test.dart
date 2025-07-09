import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/repositories/impl/job_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('JobRepository Tests', () {
    late JobRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = JobRepositoryImpl();
    });

    tearDown(() {
      repository.dispose();
    });

    group('Basic CRUD Operations', () {
      test('should create and retrieve job', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
          metadata: {'user_id': 'user_1', 'priority': 'high'},
        );

        final createdJob = await repository.create(job);
        expect(createdJob.id, equals('job_1'));
        expect(createdJob.text, equals('Test job text'));
        expect(createdJob.status, equals(JobStatus.todo));

        final retrievedJob = await repository.findById('job_1');
        expect(retrievedJob, isNotNull);
        expect(retrievedJob!.text, equals('Test job text'));
        expect(retrievedJob.metadata?['user_id'], equals('user_1'));
      });

      test('should update job', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );

        await repository.create(job);

        final updatedJob = job.copyWith(
          status: JobStatus.running,
          updatedAt: DateTime.now(),
        );
        
        await repository.update(updatedJob);

        final retrievedJob = await repository.findById('job_1');
        expect(retrievedJob!.status, equals(JobStatus.running));
        expect(retrievedJob.updatedAt, isNotNull);
      });

      test('should delete job', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );

        await repository.create(job);
        expect(await repository.exists('job_1'), isTrue);

        await repository.deleteById('job_1');
        expect(await repository.exists('job_1'), isFalse);
      });
    });

    group('Job Status Management', () {
      test('should update job status', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );

        await repository.create(job);

        final updatedJob = await repository.updateStatus('job_1', JobStatus.running);
        expect(updatedJob.status, equals(JobStatus.running));
        expect(updatedJob.updatedAt, isNotNull);

        final retrievedJob = await repository.findById('job_1');
        expect(retrievedJob!.status, equals(JobStatus.running));
      });

      test('should update job result', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.running,
          createdAt: DateTime.now(),
        );

        await repository.create(job);

        final updatedJob = await repository.updateResult('job_1', 'Job completed successfully');
        expect(updatedJob.result, equals('Job completed successfully'));
        expect(updatedJob.status, equals(JobStatus.completed));
        expect(updatedJob.updatedAt, isNotNull);
      });

      test('should update job error', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.running,
          createdAt: DateTime.now(),
        );

        await repository.create(job);

        final updatedJob = await repository.updateError('job_1', 'Network error occurred');
        expect(updatedJob.error, equals('Network error occurred'));
        expect(updatedJob.status, equals(JobStatus.dead));
        expect(updatedJob.updatedAt, isNotNull);
      });

      test('should requeue job', () async {
        final job = Job(
          id: 'job_1',
          text: 'Test job text',
          status: JobStatus.dead,
          createdAt: DateTime.now(),
        );

        await repository.create(job);

        final requeuedJob = await repository.requeueJob('job_1');
        expect(requeuedJob.status, equals(JobStatus.todo));
      });
    });

    group('Job Queries', () {
      late List<Job> testJobs;

      setUp(() async {
        final now = DateTime.now();
        testJobs = [
          Job(
            id: 'job_1',
            text: 'First job',
            status: JobStatus.todo,
            createdAt: now.subtract(Duration(hours: 3)),
            metadata: {'user_id': 'user_1', 'priority': 'high'},
          ),
          Job(
            id: 'job_2',
            text: 'Second job',
            status: JobStatus.running,
            createdAt: now.subtract(Duration(hours: 2)),
            updatedAt: now.subtract(Duration(hours: 1)),
            metadata: {'user_id': 'user_1', 'priority': 'medium'},
          ),
          Job(
            id: 'job_3',
            text: 'Third job',
            status: JobStatus.completed,
            createdAt: now.subtract(Duration(hours: 4)),
            updatedAt: now.subtract(Duration(hours: 1)),
            result: 'Job completed',
            metadata: {'user_id': 'user_2', 'priority': 'low'},
          ),
          Job(
            id: 'job_4',
            text: 'Fourth job',
            status: JobStatus.dead,
            createdAt: now.subtract(Duration(hours: 1)),
            updatedAt: now.subtract(Duration(minutes: 30)),
            error: 'Processing failed',
            metadata: {'user_id': 'user_1', 'priority': 'high'},
          ),
        ];

        for (final job in testJobs) {
          await repository.create(job);
        }
      });

      test('should find jobs by status', () async {
        final todoJobs = await repository.findByStatus(JobStatus.todo);
        expect(todoJobs, hasLength(1));
        expect(todoJobs.first.id, equals('job_1'));

        final runningJobs = await repository.findByStatus(JobStatus.running);
        expect(runningJobs, hasLength(1));
        expect(runningJobs.first.id, equals('job_2'));

        final completedJobs = await repository.findByStatus(JobStatus.completed);
        expect(completedJobs, hasLength(1));
        expect(completedJobs.first.id, equals('job_3'));

        final deadJobs = await repository.findByStatus(JobStatus.dead);
        expect(deadJobs, hasLength(1));
        expect(deadJobs.first.id, equals('job_4'));
      });

      test('should find jobs by user', () async {
        final user1Jobs = await repository.findByUser('user_1');
        expect(user1Jobs, hasLength(3));
        expect(user1Jobs.map((j) => j.id), containsAll(['job_1', 'job_2', 'job_4']));

        final user2Jobs = await repository.findByUser('user_2');
        expect(user2Jobs, hasLength(1));
        expect(user2Jobs.first.id, equals('job_3'));
      });

      test('should find jobs by session', () async {
        // Add session metadata to a job
        final jobWithSession = testJobs[0].copyWith(
          metadata: {'session_id': 'session_1', 'user_id': 'user_1'},
        );
        await repository.update(jobWithSession);

        final sessionJobs = await repository.findBySession('session_1');
        expect(sessionJobs, hasLength(1));
        expect(sessionJobs.first.id, equals('job_1'));
      });

      test('should find jobs by time range', () async {
        final now = DateTime.now();
        final start = now.subtract(Duration(hours: 3, minutes: 30));
        final end = now.subtract(Duration(hours: 1, minutes: 30));

        final jobsInRange = await repository.findByTimeRange(start, end);
        expect(jobsInRange, hasLength(2));
        expect(jobsInRange.map((j) => j.id), containsAll(['job_1', 'job_2']));
      });

      test('should find jobs by text search', () async {
        final searchResults = await repository.findByTextSearch('First');
        expect(searchResults, hasLength(1));
        expect(searchResults.first.id, equals('job_1'));

        final multipleResults = await repository.findByTextSearch('job');
        expect(multipleResults, hasLength(4));
      });

      test('should find jobs by priority', () async {
        final highPriorityJobs = await repository.findByPriority('high');
        expect(highPriorityJobs, hasLength(2));
        expect(highPriorityJobs.map((j) => j.id), containsAll(['job_1', 'job_4']));

        final mediumPriorityJobs = await repository.findByPriority('medium');
        expect(mediumPriorityJobs, hasLength(1));
        expect(mediumPriorityJobs.first.id, equals('job_2'));
      });

      test('should get active jobs', () async {
        final activeJobs = await repository.getActiveJobs();
        expect(activeJobs, hasLength(2));
        expect(activeJobs.map((j) => j.id), containsAll(['job_1', 'job_2']));
      });

      test('should get completed jobs for user', () async {
        final completedJobs = await repository.getCompletedJobs('user_2');
        expect(completedJobs, hasLength(1));
        expect(completedJobs.first.id, equals('job_3'));

        final noCompletedJobs = await repository.getCompletedJobs('user_1');
        expect(noCompletedJobs, hasLength(0));
      });

      test('should get failed jobs', () async {
        final failedJobs = await repository.getFailedJobs();
        expect(failedJobs, hasLength(1));
        expect(failedJobs.first.id, equals('job_4'));
        expect(failedJobs.first.error, equals('Processing failed'));
      });

      test('should get queue position', () async {
        final position = await repository.getQueuePosition('job_1');
        expect(position, equals(1)); // Should be first in queue (oldest todo)
      });
    });

    group('Job Statistics', () {
      test('should get job statistics', () async {
        final now = DateTime.now();
        final jobs = [
          Job(
            id: 'job_1',
            text: 'Job 1',
            status: JobStatus.todo,
            createdAt: now,
            metadata: {'user_id': 'user_1'},
          ),
          Job(
            id: 'job_2',
            text: 'Job 2',
            status: JobStatus.running,
            createdAt: now,
            metadata: {'user_id': 'user_1'},
          ),
          Job(
            id: 'job_3',
            text: 'Job 3',
            status: JobStatus.completed,
            createdAt: now,
            metadata: {'user_id': 'user_2'},
          ),
          Job(
            id: 'job_4',
            text: 'Job 4',
            status: JobStatus.dead,
            createdAt: now,
            metadata: {'user_id': 'user_1'},
          ),
        ];

        for (final job in jobs) {
          await repository.create(job);
        }

        final stats = await repository.getJobStats();
        expect(stats.totalJobs, equals(4));
        expect(stats.todoJobs, equals(1));
        expect(stats.runningJobs, equals(1));
        expect(stats.completedJobs, equals(1));
        expect(stats.deadJobs, equals(1));
        expect(stats.averageProcessingTime, isA<Duration>());
        expect(stats.successRate, equals(0.25)); // 1 completed out of 4 total

        // Test user-specific stats
        final userStats = await repository.getJobStats(userId: 'user_1');
        expect(userStats.totalJobs, equals(3));
        expect(userStats.completedJobs, equals(0));
      });
    });

    group('Pagination', () {
      test('should find jobs with pagination', () async {
        // Create 25 jobs for pagination testing
        for (int i = 1; i <= 25; i++) {
          final job = Job(
            id: 'job_$i',
            text: 'Job $i',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: i)),
          );
          await repository.create(job);
        }

        // Test first page
        final firstPage = await repository.findPaginated(page: 0, size: 10);
        expect(firstPage.items, hasLength(10));
        expect(firstPage.page, equals(0));
        expect(firstPage.size, equals(10));
        expect(firstPage.totalCount, equals(25));
        expect(firstPage.hasNext, isTrue);
        expect(firstPage.hasPrevious, isFalse);

        // Test second page
        final secondPage = await repository.findPaginated(page: 1, size: 10);
        expect(secondPage.items, hasLength(10));
        expect(secondPage.page, equals(1));
        expect(secondPage.hasNext, isTrue);
        expect(secondPage.hasPrevious, isTrue);

        // Test last page
        final lastPage = await repository.findPaginated(page: 2, size: 10);
        expect(lastPage.items, hasLength(5));
        expect(lastPage.hasNext, isFalse);
        expect(lastPage.hasPrevious, isTrue);
      });

      test('should search jobs with pagination', () async {
        // Create jobs with searchable text
        for (int i = 1; i <= 15; i++) {
          final job = Job(
            id: 'job_$i',
            text: i <= 10 ? 'Important job $i' : 'Regular job $i',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: i)),
          );
          await repository.create(job);
        }

        final searchResults = await repository.search(
          'Important',
          page: 0,
          size: 5,
        );

        expect(searchResults.items, hasLength(5));
        expect(searchResults.totalCount, equals(10));
        expect(searchResults.hasNext, isTrue);
      });

      test('should filter jobs with pagination', () async {
        // Create jobs with different statuses
        for (int i = 1; i <= 20; i++) {
          final job = Job(
            id: 'job_$i',
            text: 'Job $i',
            status: i <= 10 ? JobStatus.todo : JobStatus.completed,
            createdAt: DateTime.now().subtract(Duration(minutes: i)),
          );
          await repository.create(job);
        }

        final filteredResults = await repository.findPaginated(
          page: 0,
          size: 5,
          filters: {'status': 'todo'},
        );

        expect(filteredResults.items, hasLength(5));
        expect(filteredResults.totalCount, equals(10));
        expect(filteredResults.items.every((job) => job.status == JobStatus.todo), isTrue);
      });
    });

    group('Real-time Updates', () {
      test('should stream job updates', () async {
        final streamEvents = <List<Job>>[];
        final subscription = repository.watchAll().listen((jobs) {
          streamEvents.add(jobs);
        });

        // Create a job
        final job = Job(
          id: 'job_1',
          text: 'Test job',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );

        await repository.create(job);

        // Update the job
        await repository.updateStatus('job_1', JobStatus.running);

        // Delete the job
        await repository.deleteById('job_1');

        // Wait for stream updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(streamEvents, hasLength(3));
        expect(streamEvents[0], hasLength(1));
        expect(streamEvents[1], hasLength(1));
        expect(streamEvents[2], hasLength(0));

        await subscription.cancel();
      });

      test('should watch specific job by ID', () async {
        final jobUpdates = <Job?>[];
        
        // Create initial job
        final job = Job(
          id: 'job_1',
          text: 'Test job',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );
        await repository.create(job);

        final subscription = repository.watchById('job_1').listen((job) {
          jobUpdates.add(job);
        });

        // Update job status
        await repository.updateStatus('job_1', JobStatus.running);

        // Delete job
        await repository.deleteById('job_1');

        // Wait for stream updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(jobUpdates, hasLength(3));
        expect(jobUpdates[0]?.status, equals(JobStatus.todo));
        expect(jobUpdates[1]?.status, equals(JobStatus.running));
        expect(jobUpdates[2], isNull);

        await subscription.cancel();
      });
    });

    group('Job Archiving', () {
      test('should archive old completed jobs', () async {
        final now = DateTime.now();
        
        // Create old completed jobs
        final oldJob1 = Job(
          id: 'old_job_1',
          text: 'Old job 1',
          status: JobStatus.completed,
          createdAt: now.subtract(Duration(days: 40)),
          updatedAt: now.subtract(Duration(days: 40)),
        );
        
        final oldJob2 = Job(
          id: 'old_job_2',
          text: 'Old job 2',
          status: JobStatus.completed,
          createdAt: now.subtract(Duration(days: 35)),
          updatedAt: now.subtract(Duration(days: 35)),
        );
        
        // Create recent completed job
        final recentJob = Job(
          id: 'recent_job',
          text: 'Recent job',
          status: JobStatus.completed,
          createdAt: now.subtract(Duration(days: 1)),
          updatedAt: now.subtract(Duration(days: 1)),
        );
        
        await repository.create(oldJob1);
        await repository.create(oldJob2);
        await repository.create(recentJob);
        
        expect(await repository.count(), equals(3));
        
        // Archive jobs older than 30 days
        await repository.archiveCompletedJobs(olderThan: Duration(days: 30));
        
        expect(await repository.count(), equals(1));
        
        final remainingJob = await repository.findById('recent_job');
        expect(remainingJob, isNotNull);
      });
    });

    group('Error Handling', () {
      test('should handle operations on non-existent jobs', () async {
        expect(
          () => repository.updateStatus('nonexistent', JobStatus.running),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Job with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.updateResult('nonexistent', 'result'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Job with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.updateError('nonexistent', 'error'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Job with id nonexistent not found'),
          )),
        );
      });
    });
  });
}