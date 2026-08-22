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

    // ── /api/v2/ask (replaces /api/push — 410 tombstone) ──────────────────
    // Fixture bodies are the §8 AskResponse shape from v2_ask.py, NOT the old
    // queue-and-poll PushJobResponse — a renamed mock key with the old body
    // would stay green while the app broke.

    test( 'ask POSTs /api/v2/ask with the AskRequest body and parses the synchronous answer', () async {
      adapter.handlers[ 'POST /api/v2/ask' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'question'     ], 'what is 2 + 2' );
        expect( body[ 'websocket_id' ], 'mobile' );
        expect( body[ 'speak'        ], isTrue );
        expect( body[ 'interactive'  ], isTrue );
        return jsonBody( {
          'path'         : 'agent',
          'status'       : 'done',
          'route_reason' : 'router:math',
          'answer'       : 'Four.',
          'answer_raw'   : '4',
          'command'      : 'agent router go to math',
          'args_known'   : [ 'expression' ],
          'args_missing' : [],
          'pending_id'   : null,
          'job_id'       : 'j-new',
          'snapshot_id'  : null,
          'similarity'   : 0.0,
          'wrote_snapshot': false,
          'cache_hit'    : false,
          'spoke'        : true,
          'timings_ms'   : { 'route': 12, 'total': 840 },
          'trace_id'     : 'tr-1',
          'error'        : null,
        } );
      };
      final r = await repo.ask( const AskRequest( question: 'what is 2 + 2', websocketId: 'mobile' ) );
      expect( r.path,     'agent' );
      expect( r.status,   'done' );
      expect( r.isDone,   isTrue );
      expect( r.answer,   'Four.' );
      expect( r.jobId,    'j-new' );
      expect( r.traceId,  'tr-1' );
      expect( r.argsKnown, [ 'expression' ] );
      expect( r.summary,  'Four.' );
      expect( adapter.captured.single.path, '/api/v2/ask' );
    } );

    // ── /api/v2/submit (wave 2 — the door beside ask) ──────────────────────
    test( 'submit POSTs /api/v2/submit with {command, args, question?, websocket_id?, speak} and parses AskResponse', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'command'      ], 'agent router go to weather' );
        expect( body[ 'args'         ], { 'location': 'Washington DC' } );
        expect( body[ 'question'     ], 'weather in DC' );
        expect( body[ 'websocket_id' ], 'mobile' );
        expect( body[ 'speak'        ], isFalse );
        expect( body.containsKey( 'interactive' ), isFalse, reason: 'submit has no interactive flag — it never parks' );
        return jsonBody( {
          'path'         : 'agent',
          'status'       : 'done',
          'route_reason' : 'submitted',
          'answer'       : 'Sunny.',
          'answer_raw'   : 'sunny',
          'command'      : 'agent router go to weather',
          'args_known'   : [ 'location' ],
          'args_missing' : [],
          'trace_id'     : 'tr-s1',
        } );
      };
      final r = await repo.submit( const SubmitRequest(
        command     : 'agent router go to weather',
        args        : { 'location': 'Washington DC' },
        question    : 'weather in DC',
        websocketId : 'mobile',
        speak       : false,
      ) );
      expect( r.status,   'done' );
      expect( r.isDone,   isTrue );
      expect( r.answer,   'Sunny.' );
      expect( r.command,  'agent router go to weather' );
      expect( adapter.captured.single.path, '/api/v2/submit' );
    } );

    test( 'submit omits question/websocket_id when null and surfaces needs_input WITHOUT a pending_id (never parked)', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body.containsKey( 'question' ),     isFalse );
        expect( body.containsKey( 'websocket_id' ), isFalse );
        expect( body[ 'args' ], isEmpty );
        expect( body[ 'speak' ], isTrue );
        return jsonBody( {
          'path'         : 'needs_input',
          'status'       : 'needs_input',
          'route_reason' : 'args_incomplete',
          'answer'       : 'location is required',
          'command'      : 'agent router go to weather',
          'args_known'   : [],
          'args_missing' : [ 'location' ],
          'pending_id'   : null,
          'trace_id'     : 'tr-s2',
        } );
      };
      final r = await repo.submit( const SubmitRequest( command: 'agent router go to weather' ) );
      expect( r.needsInput,  isTrue );
      expect( r.argsMissing, [ 'location' ] );
      expect( r.pendingId,   isNull );
    } );

    test( 'submit carries scheduled_at / monopolize TOP-LEVEL (never inside args) and only when set', () async {
      late Map<String, dynamic> body;
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        body = opts.data as Map<String, dynamic>;
        return jsonBody( { 'path': 'agent', 'status': 'waiting', 'route_reason': 'submitted', 'job_id': 'dr-1', 'trace_id': 'tr-s4' } );
      };
      await repo.submit( const SubmitRequest(
        command     : 'agent router go to deep research',
        args        : { 'query': 'q' },
        scheduledAt : '2026-08-22T10:00:00-04:00',
        monopolize  : true,
      ) );
      expect( body[ 'scheduled_at' ], '2026-08-22T10:00:00-04:00' );
      expect( body[ 'monopolize' ], isTrue );
      expect( ( body[ 'args' ] as Map ).containsKey( 'scheduled_at' ), isFalse, reason: 'queue directives are not agent args' );
      expect( ( body[ 'args' ] as Map ).containsKey( 'monopolize' ),   isFalse );

      await repo.submit( const SubmitRequest( command: 'agent router go to weather' ) );
      expect( body.containsKey( 'scheduled_at' ), isFalse, reason: 'unset → omitted, body unchanged for the server' );
      expect( body.containsKey( 'monopolize' ),   isFalse );
    } );

    // ── door 10: /api/push-agentic → /api/v2/submit (wave 2) ───────────────
    test( 'pushAgentic rides /api/v2/submit 1:1 (routing_command → command) and adapts waiting+job_id to PushJobResponse', () async {
      late Map<String, dynamic> body;
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        body = opts.data as Map<String, dynamic>;
        return jsonBody( { 'path': 'agent', 'status': 'waiting', 'route_reason': 'submitted', 'command': 'agent router go to deep research', 'job_id': 'dr-77', 'trace_id': 'tr-pa' } );
      };
      final r = await repo.pushAgentic( const PushAgenticRequest( routingCommand: 'agent router go to deep research', websocketId: 'mobile', args: { 'query': 'q' }, question: 'research q', scheduledAt: '2026-08-22T10:00:00-04:00' ) );
      expect( body[ 'command' ], 'agent router go to deep research' );
      expect( body[ 'args' ], { 'query': 'q' } );
      expect( body[ 'question' ], 'research q' );
      expect( body[ 'websocket_id' ], 'mobile' );
      expect( body[ 'scheduled_at' ], '2026-08-22T10:00:00-04:00' );
      expect( body.containsKey( 'routing_command' ), isFalse );
      expect( r.jobId, 'dr-77' );
      expect( r.status, 'waiting' );
      expect( r.routingCommand, 'agent router go to deep research' );
      expect( adapter.captured.single.path, '/api/v2/submit' );
    } );

    test( 'pushAgentic: a v2 body without a job is a QueueApiException, never "Job queued" with no id', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( { 'path': 'receptionist', 'status': 'done', 'route_reason': 'unknown_command', 'answer': 'not a command I know', 'trace_id': 'tr-rc' } );
      await expectLater(
        repo.pushAgentic( const PushAgenticRequest( routingCommand: 'nonsense', websocketId: 'mobile' ) ),
        throwsA( isA<QueueApiException>().having( ( e ) => e.message, 'message', contains( 'not a command' ) ) ),
      );
    } );

    test( 'submit maps a transport failure to QueueApiException', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( { 'detail': 'nope' }, status: 500 );
      expect( () => repo.submit( const SubmitRequest( command: 'x' ) ), throwsA( isA<QueueApiException>() ) );
    } );

    test( 'ask surfaces needs_input with pending_id (interactive park)', () async {
      adapter.handlers[ 'POST /api/v2/ask' ] = ( _ ) => jsonBody( {
        'path'         : 'needs_input',
        'status'       : 'parked',
        'route_reason' : 'missing:city',
        'answer'       : 'Which city?',
        'args_known'   : [],
        'args_missing' : [ 'city' ],
        'pending_id'   : 'pend-9',
        'trace_id'     : 'tr-2',
      } );
      final r = await repo.ask( const AskRequest( question: 'weather?' ) );
      expect( r.needsInput,  isTrue );
      expect( r.pendingId,   'pend-9' );
      expect( r.argsMissing, [ 'city' ] );
      expect( r.summary,     'Which city?' );
    } );

    test( 'ask never hits /api/push (the 410 tombstone)', () async {
      adapter.handlers[ 'POST /api/push' ] = ( _ ) => jsonBody(
        { 'detail': '/api/push is GONE. Every question now enters through /api/v2/ask.' }, status: 410 );
      adapter.handlers[ 'POST /api/v2/ask' ] = ( _ ) => jsonBody( {
          'path'         : 'agent',
          'status'       : 'done',
          'route_reason' : 'router:math',
          'answer'       : 'Four.',
          'answer_raw'   : '4',
          'command'      : 'agent router go to math',
          'args_known'   : [ 'expression' ],
          'args_missing' : [],
          'pending_id'   : null,
          'job_id'       : 'j-new',
          'snapshot_id'  : null,
          'similarity'   : 0.0,
          'wrote_snapshot': false,
          'cache_hit'    : false,
          'spoke'        : true,
          'timings_ms'   : { 'route': 12, 'total': 840 },
          'trace_id'     : 'tr-1',
          'error'        : null,
        } );
      final r = await repo.ask( const AskRequest( question: 'x' ) );
      expect( r.isDone, isTrue );
      expect( adapter.captured.map( ( o ) => o.path ), isNot( contains( '/api/push' ) ) );
    } );

    test( 'ask maps a server 410/4xx detail into QueueApiException', () async {
      adapter.handlers[ 'POST /api/v2/ask' ] = ( _ ) => jsonBody(
        { 'detail': 'CJ Flow v2 is disabled (v2 flow enabled = False).' }, status: 503 );
      expect(
        () => repo.ask( const AskRequest( question: 'x' ) ),
        throwsA( isA<QueueApiException>()
          .having( ( e ) => e.statusCode, 'statusCode', 503 )
          .having( ( e ) => e.message,    'message',    contains( 'v2 flow enabled' ) ) ),
      );
    } );

    // ── retry = re-ask via /api/v2/ask (replaces /api/job-history/{id}/retry) ──

    test( 'retryJob re-asks the stored question through /api/v2/ask (not the retired retry door)', () async {
      adapter.handlers[ 'POST /api/v2/ask' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'question'     ], 'original question?' );
        expect( body[ 'websocket_id' ], 'mobile' );
        return jsonBody( {
          'path'         : 'agent',
          'status'       : 'done',
          'route_reason' : 'router:math',
          'answer'       : 'Four.',
          'answer_raw'   : '4',
          'command'      : 'agent router go to math',
          'args_known'   : [ 'expression' ],
          'args_missing' : [],
          'pending_id'   : null,
          'job_id'       : 'j-new',
          'snapshot_id'  : null,
          'similarity'   : 0.0,
          'wrote_snapshot': false,
          'cache_hit'    : false,
          'spoke'        : true,
          'timings_ms'   : { 'route': 12, 'total': 840 },
          'trace_id'     : 'tr-1',
          'error'        : null,
        } );
      };
      final r = await repo.retryJob( jobId: 'j-old', questionText: 'original question?', websocketId: 'mobile' );
      expect( r.isDone, isTrue );
      expect( adapter.captured.single.path, '/api/v2/ask' );
      expect( adapter.captured.single.path, isNot( contains( 'job-history' ) ) );
    } );

    test( 'retryJob omits websocket_id when none is given', () async {
      adapter.handlers[ 'POST /api/v2/ask' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body.containsKey( 'websocket_id' ), isFalse );
        return jsonBody( {
          'path'         : 'agent',
          'status'       : 'done',
          'route_reason' : 'router:math',
          'answer'       : 'Four.',
          'answer_raw'   : '4',
          'command'      : 'agent router go to math',
          'args_known'   : [ 'expression' ],
          'args_missing' : [],
          'pending_id'   : null,
          'job_id'       : 'j-new',
          'snapshot_id'  : null,
          'similarity'   : 0.0,
          'wrote_snapshot': false,
          'cache_hit'    : false,
          'spoke'        : true,
          'timings_ms'   : { 'route': 12, 'total': 840 },
          'trace_id'     : 'tr-1',
          'error'        : null,
        } );
      };
      await repo.retryJob( jobId: 'j-old', questionText: 'q' );
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
