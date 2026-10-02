/// The Claude Code job models (bug bdd60a1b): the `/api/v2/submit` body they
/// build and how they read its answer.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_models.dart';

void main() {
  group( 'ClaudeCodeSubmitRequest.toSubmitRequest', () {
    test( 'names the Claude Code command and puts the job settings in args', () {
      final j = const ClaudeCodeSubmitRequest( prompt: 'do it' ).toSubmitRequest().toJson();
      expect( j[ 'command' ], 'agent router go to claude code' );
      expect( j[ 'args' ], {
        'prompt'    : 'do it',
        'project'   : 'lupin',
        'task_type' : 'BOUNDED',
        'max_turns' : 50,
        'dry_run'   : false,
      } );
      expect( j[ 'question' ], 'do it' );
    } );

    test( 'unset queue directives are left out of the body', () {
      final j = const ClaudeCodeSubmitRequest( prompt: 'p' ).toSubmitRequest().toJson();
      expect( j.containsKey( 'websocket_id' ), isFalse );
      expect( j.containsKey( 'scheduled_at' ), isFalse );
      expect( j.containsKey( 'monopolize' ),   isFalse );
    } );

    test( 'queue directives ride top-level, never inside args', () {
      final j = const ClaudeCodeSubmitRequest(
        prompt       : 'p',
        websocketId  : 'ws-1',
        scheduledAt  : '2026-05-11T14:00:00',
        monopolize   : true,
      ).toSubmitRequest().toJson();
      expect( j[ 'websocket_id' ], 'ws-1' );
      expect( j[ 'scheduled_at' ], '2026-05-11T14:00:00' );
      expect( j[ 'monopolize'   ], isTrue );
      final args = j[ 'args' ] as Map;
      for ( final k in [ 'websocket_id', 'scheduled_at', 'monopolize' ] ) {
        expect( args.containsKey( k ), isFalse, reason: k );
      }
    } );

    test( 'non-default job settings reach args', () {
      final args = const ClaudeCodeSubmitRequest(
        prompt: 'p', project: 'lupin-mobile', taskType: 'INTERACTIVE', maxTurns: 7, dryRun: true,
      ).toSubmitRequest().toJson()[ 'args' ] as Map;
      expect( args[ 'project'   ], 'lupin-mobile' );
      expect( args[ 'task_type' ], 'INTERACTIVE' );
      expect( args[ 'max_turns' ], 7 );
      expect( args[ 'dry_run'   ], isTrue );
    } );

    test( 'a prompt longer than the question limit is cut in question, whole in args', () {
      final long = 'x' * 4500;
      final j    = ClaudeCodeSubmitRequest( prompt: long ).toSubmitRequest().toJson();
      expect( ( j[ 'question' ] as String ).length, 4000 );
      expect( ( ( j[ 'args' ] as Map )[ 'prompt' ] as String ).length, 4500 );
    } );
  } );

  group( 'ClaudeCodeSubmitResponse.fromAsk', () {
    Map<String, dynamic> ask( Map<String, dynamic> over ) => {
      'path'         : 'agent',
      'status'       : 'waiting',
      'route_reason' : 'submit',
      'trace_id'     : 't-1',
      ...over,
    };

    test( 'waiting with a job id is a success; queue position and answer are read', () {
      final r = ClaudeCodeSubmitResponse.fromAsk(
          ask( { 'job_id': 'cc-1', 'queue_position': 3, 'answer': 'queued' } ) );
      expect( r.status,        'waiting' );
      expect( r.jobId,         'cc-1' );
      expect( r.queuePosition, 3 );
      expect( r.message,       'queued' );
    } );

    test( 'no queue position and no answer default to 0 and empty', () {
      final r = ClaudeCodeSubmitResponse.fromAsk( ask( { 'job_id': 'cc-2' } ) );
      expect( r.queuePosition, 0 );
      expect( r.message,       '' );
    } );

    test( 'needs_input names the missing arguments', () {
      expect(
        () => ClaudeCodeSubmitResponse.fromAsk(
            ask( { 'status': 'needs_input', 'args_missing': [ 'prompt' ] } ) ),
        throwsA( isA<ClaudeCodeApiException>()
            .having( ( e ) => e.message, 'message', 'Missing: prompt' ) ),
      );
    } );

    test( 'a 200 with no job is an error carrying the server\'s words', () {
      expect(
        () => ClaudeCodeSubmitResponse.fromAsk(
            ask( { 'status': 'failed', 'error': 'task_type must be BOUNDED or INTERACTIVE' } ) ),
        throwsA( isA<ClaudeCodeApiException>()
            .having( ( e ) => e.message, 'message', 'task_type must be BOUNDED or INTERACTIVE' ) ),
      );
    } );

    test( 'a job id with an unexpected status is not a success', () {
      expect(
        () => ClaudeCodeSubmitResponse.fromAsk( ask( { 'status': 'failed', 'job_id': 'cc-3' } ) ),
        throwsA( isA<ClaudeCodeApiException>() ),
      );
    } );
  } );
}
