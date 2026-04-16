import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_models.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  group( 'ClaudeCodeRepository', () {
    late StubAdapter adapter;
    late ClaudeCodeRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = ClaudeCodeRepository( makeDio( adapter ) );
    } );

    test( 'dispatch POSTs and returns session', () async {
      adapter.handlers[ 'POST /api/claude-code/dispatch' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'task_type' ], 'INTERACTIVE' );
        return jsonBody( { 'task_id': 't-1', 'status': 'running' } );
      };
      final session = await repo.dispatch(
        ClaudeCodeDispatchRequest( prompt: 'run', taskType: ClaudeCodeTaskType.interactive ),
      );
      expect( session.taskId, 't-1' );
      expect( session.status, 'running' );
    } );

    test( 'getStatus returns parsed session', () async {
      adapter.handlers[ 'GET /api/claude-code/t-2/status' ] = ( _ ) =>
          jsonBody( { 'task_id': 't-2', 'status': 'awaiting_input' } );
      final session = await repo.getStatus( 't-2' );
      expect( session.status, 'awaiting_input' );
    } );

    test( 'inject POSTs message to correct endpoint', () async {
      adapter.handlers[ 'POST /api/claude-code/t-3/inject' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'message' ], 'yes' );
        return jsonBody( { 'status': 'ok', 'task_id': 't-3' } );
      };
      await expectLater( repo.inject( 't-3', 'yes' ), completes );
    } );

    test( 'interrupt POSTs to correct endpoint', () async {
      adapter.handlers[ 'POST /api/claude-code/t-4/interrupt' ] = ( _ ) =>
          jsonBody( { 'status': 'interrupted' } );
      await expectLater( repo.interrupt( 't-4' ), completes );
    } );

    test( 'queueSubmit returns queue response', () async {
      adapter.handlers[ 'POST /api/claude-code/queue/submit' ] = ( _ ) => jsonBody( {
        'status'        : 'queued',
        'job_id'        : 'cj-5',
        'queue_position': 1,
        'message'       : 'ok',
      } );
      final r = await repo.queueSubmit(
        ClaudeCodeQueueRequest( prompt: 'bounded task' ),
      );
      expect( r.jobId, 'cj-5' );
    } );
  } );
}
