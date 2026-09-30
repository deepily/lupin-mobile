import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_models.dart';

void main() {
  group( 'ClaudeCodeSubmitRequest.toJson', () {
    test( 'includes required fields with defaults', () {
      final r = ClaudeCodeSubmitRequest( prompt: 'do it' );
      final j = r.toJson();
      expect( j[ 'prompt'     ], 'do it' );
      expect( j[ 'project'    ], 'lupin' );
      expect( j[ 'task_type'  ], 'BOUNDED' );
      expect( j[ 'max_turns'  ], 50 );
      expect( j[ 'dry_run'    ], isFalse );
      expect( j[ 'monopolize' ], isFalse );
      expect( j.containsKey( 'websocket_id' ), isFalse );
      expect( j.containsKey( 'scheduled_at' ), isFalse );
    } );

    test( 'optional fields are included when set', () {
      final r = ClaudeCodeSubmitRequest(
        prompt       : 'p',
        websocketId  : 'ws-1',
        scheduledAt  : '2026-05-11T14:00:00',
        monopolize   : true,
      );
      final j = r.toJson();
      expect( j[ 'websocket_id' ], 'ws-1' );
      expect( j[ 'scheduled_at' ], '2026-05-11T14:00:00' );
      expect( j[ 'monopolize'   ], isTrue );
    } );
  } );

  group( 'ClaudeCodeSubmitResponse.fromJson', () {
    test( 'parses job_id and queue_position', () {
      final r = ClaudeCodeSubmitResponse.fromJson( {
        'status'        : 'queued',
        'job_id'        : 'cc-1',
        'queue_position': 3,
        'message'       : 'ok',
      } );
      expect( r.status,        'queued' );
      expect( r.jobId,         'cc-1' );
      expect( r.queuePosition, 3 );
      expect( r.message,       'ok' );
    } );

    test( 'defaults missing queue_position to 0 and message to empty', () {
      final r = ClaudeCodeSubmitResponse.fromJson( {
        'status' : 'queued',
        'job_id' : 'cc-2',
      } );
      expect( r.queuePosition, 0 );
      expect( r.message,       '' );
    } );
  } );
}
