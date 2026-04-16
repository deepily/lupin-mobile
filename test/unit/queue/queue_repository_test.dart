import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  group( 'QueueRepository', () {
    late StubAdapter adapter;
    late QueueRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = QueueRepository( makeDio( adapter ) );
    } );

    test( 'push sends question and websocket_id', () async {
      adapter.handlers[ 'POST /api/push' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'question'     ], 'hello' );
        expect( body[ 'websocket_id' ], 'mobile' );
        return jsonBody( {
          'status'      : 'queued',
          'websocket_id': 'mobile',
          'user_id'     : 'u-1',
          'job_id'      : 'j-1',
        } );
      };
      final r = await repo.push( PushJobRequest( question: 'hello', websocketId: 'mobile' ) );
      expect( r.jobId, 'j-1' );
    } );

    test( 'getQueue parses snapshot for todo queue', () async {
      adapter.handlers[ 'GET /api/get-queue/todo' ] = ( _ ) => jsonBody( {
        'todo_jobs_metadata': [
          { 'job_id': 'j-a', 'question_text': 'q', 'agent_type': 'Bot', 'status': 'todo', 'paused': false },
        ],
      } );
      final snap = await repo.getQueue( 'todo' );
      expect( snap.queueName,       'todo' );
      expect( snap.jobs.length,     1 );
      expect( snap.jobs.first.jobId, 'j-a' );
    } );

    test( 'cancelJob POSTs to correct endpoint', () async {
      adapter.handlers[ 'POST /api/jobs/j-1/cancel' ] = ( _ ) =>
          jsonBody( { 'status': 'cancelled' } );
      await expectLater( repo.cancelJob( 'j-1' ), completes );
    } );

    test( 'getJobHistory parses page', () async {
      adapter.handlers[ 'GET /api/job-history' ] = ( _ ) => jsonBody( {
        'jobs': [
          {
            'id_hash': 'h-1', 'job_type': 'MathAgent', 'user_id': 'u-1',
            'user_email': 'u@x.y', 'session_id': 's-1', 'routing_command': 'math',
            'status': 'done', 'question_text': 'q?', 'is_cache_hit': false,
            'duration_seconds': 1.0, 'metadata_json': '{}',
            'submitted_at': '2026-04-15T10:00:00Z',
          },
        ],
        'total': 1, 'filtered_by': 'all', 'limit': 50, 'offset': 0,
      } );
      final page = await repo.getJobHistory();
      expect( page.total,              1 );
      expect( page.jobs.first.idHash, 'h-1' );
    } );

    test( 'getJobInteractions parses interactions', () async {
      adapter.handlers[ 'GET /api/get-job-interactions/j-2' ] = ( _ ) => jsonBody( {
        'job_id'           : 'j-2',
        'session_id'       : 's-1',
        'job_metadata'     : {},
        'interactions'     : [
          {
            'id': 'i-1', 'type': 'ask_yes_no', 'message': 'Go?',
            'timestamp': '2026-04-15T12:00:00Z', 'response_requested': true,
          },
        ],
        'interaction_count': 1,
      } );
      final result = await repo.getJobInteractions( 'j-2' );
      expect( result.interactionCount,              1 );
      expect( result.interactions.first.message, 'Go?' );
    } );
  } );
}
