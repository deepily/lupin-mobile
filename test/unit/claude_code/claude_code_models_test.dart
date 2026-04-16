import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_models.dart';

void main() {
  group( 'ClaudeCodeDispatchRequest.toJson', () {
    test( 'interactive task_type serialises as INTERACTIVE', () {
      final r = ClaudeCodeDispatchRequest(
        prompt   : 'hello',
        taskType : ClaudeCodeTaskType.interactive,
      );
      final j = r.toJson();
      expect( j[ 'prompt'    ], 'hello' );
      expect( j[ 'task_type' ], 'INTERACTIVE' );
    } );

    test( 'bounded task_type serialises as BOUNDED', () {
      final r = ClaudeCodeDispatchRequest(
        prompt   : 'run it',
        taskType : ClaudeCodeTaskType.bounded,
        project  : '/tmp/proj',
      );
      final j = r.toJson();
      expect( j[ 'task_type' ], 'BOUNDED' );
      expect( j[ 'project'   ], '/tmp/proj' );
    } );
  } );

  group( 'ClaudeCodeSession.fromJson', () {
    test( 'parses running session', () {
      final s = ClaudeCodeSession.fromJson( {
        'task_id': 't-1',
        'status' : 'running',
      } );
      expect( s.taskId, 't-1' );
      expect( s.status, 'running' );
      expect( s.costUsd, isNull );
    } );

    test( 'parses completed session with cost', () {
      final s = ClaudeCodeSession.fromJson( {
        'task_id' : 't-2',
        'status'  : 'complete',
        'cost_usd': 0.025,
      } );
      expect( s.status,  'complete' );
      expect( s.costUsd, 0.025 );
    } );

    test( 'copyWith overrides status', () {
      final s   = ClaudeCodeSession.fromJson( { 'task_id': 't-3', 'status': 'running' } );
      final s2  = s.copyWith( status: 'ended' );
      expect( s2.status, 'ended' );
      expect( s2.taskId, 't-3' );
    } );
  } );

  group( 'ClaudeCodeQueueResponse.fromJson', () {
    test( 'parses job_id and queue_position', () {
      final r = ClaudeCodeQueueResponse.fromJson( {
        'status'        : 'queued',
        'job_id'        : 'cj-1',
        'queue_position': 3,
        'message'       : 'ok',
      } );
      expect( r.jobId,         'cj-1' );
      expect( r.queuePosition, 3 );
    } );
  } );

  group( 'ClaudeCodeQueueRequest.toJson', () {
    test( 'includes required fields', () {
      final r = ClaudeCodeQueueRequest( prompt: 'do it' );
      final j = r.toJson();
      expect( j[ 'prompt'   ], 'do it' );
      expect( j[ 'dry_run'  ], isFalse );
      expect( j[ 'monopolize'], isFalse );
    } );
  } );
}
