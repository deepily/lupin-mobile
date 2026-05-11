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

    test( 'submit POSTs to canonical URL and returns parsed response', () async {
      adapter.handlers[ 'POST /api/claude-code/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'prompt'    ], 'run something' );
        expect( body[ 'task_type' ], 'BOUNDED' );
        return jsonBody( {
          'status'        : 'queued',
          'job_id'        : 'cc-1',
          'queue_position': 1,
          'message'       : 'ok',
        } );
      };
      final r = await repo.submit(
        ClaudeCodeSubmitRequest( prompt: 'run something' ),
      );
      expect( r.jobId,  'cc-1' );
      expect( r.status, 'queued' );
    } );

    test( 'submit throws ClaudeCodeApiException on HTTP 500', () async {
      adapter.handlers[ 'POST /api/claude-code/submit' ] = ( _ ) =>
          jsonBody( { 'detail': 'server crashed' }, status: 500 );
      await expectLater(
        repo.submit( ClaudeCodeSubmitRequest( prompt: 'x' ) ),
        throwsA( isA<ClaudeCodeApiException>()
            .having( ( e ) => e.message,    'message',    'server crashed' )
            .having( ( e ) => e.statusCode, 'statusCode', 500 ) ),
      );
    } );
  } );
}
