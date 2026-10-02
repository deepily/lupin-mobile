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

    const ok = {
      'path'           : 'agent',
      'status'         : 'waiting',
      'route_reason'   : 'submit',
      'trace_id'       : 't-1',
      'job_id'         : 'cc-1',
      'queue_position' : 1,
    };

    test( 'submit POSTs the v2 body to /api/v2/submit and returns the job', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( ok );
      final r = await repo.submit(
        const ClaudeCodeSubmitRequest( prompt: 'run something' ),
      );
      final body = adapter.captured.single.data as Map<String, dynamic>;
      expect( body[ 'command' ], 'agent router go to claude code' );
      expect( ( body[ 'args' ] as Map )[ 'prompt'    ], 'run something' );
      expect( ( body[ 'args' ] as Map )[ 'task_type' ], 'BOUNDED' );
      expect( r.jobId,         'cc-1' );
      expect( r.status,        'waiting' );
      expect( r.queuePosition, 1 );
    } );

    test( 'nothing is sent to the retired /api/claude-code/submit route', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( ok );
      await repo.submit( const ClaudeCodeSubmitRequest( prompt: 'x' ) );
      expect( adapter.captured.map( ( o ) => o.path ), [ '/api/v2/submit' ] );
    } );

    test( 'submit throws ClaudeCodeApiException on HTTP 500', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) =>
          jsonBody( { 'detail': 'server crashed' }, status: 500 );
      await expectLater(
        repo.submit( const ClaudeCodeSubmitRequest( prompt: 'x' ) ),
        throwsA( isA<ClaudeCodeApiException>()
            .having( ( e ) => e.message,    'message',    'server crashed' )
            .having( ( e ) => e.statusCode, 'statusCode', 500 ) ),
      );
    } );

    test( 'a 200 that created no job is an error, not a success', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( {
        ...ok, 'status': 'failed', 'job_id': null, 'error': 'no worker',
      } );
      await expectLater(
        repo.submit( const ClaudeCodeSubmitRequest( prompt: 'x' ) ),
        throwsA( isA<ClaudeCodeApiException>().having( ( e ) => e.message, 'message', 'no worker' ) ),
      );
    } );
  } );
}
