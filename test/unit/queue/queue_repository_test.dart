import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  _askTimeout();
  _resumeDoor();
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

// ─────────────────────────────────────────────────────────────────────────
// AC-S4.7 (landed in S1 per the plan's sequencing table) — the ask call gets
// its OWN receive budget; every other call keeps the global 30s.
// ─────────────────────────────────────────────────────────────────────────

void _askTimeout() {
  group( 'AC-S4.7 — per-request receiveTimeout on the ask call only', () {
    late StubAdapter adapter;
    late QueueRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = QueueRepository( makeDio( adapter ) );
    } );

    Map<String, dynamic> doneBody() => {
      'path' : 'agent', 'status' : 'done', 'route_reason' : 'r',
      'trace_id' : 't', 'answer' : 'ok',
    };

    test( 'ask carries >= 240s, covering the ~210s worst-case confirm ladder', () async {
      // Door C blocks the request thread while the server asks the user "is
      // that the same as …?" — 30s timeout, 3 attempts, 2.0 backoff. At the
      // shared Dio's global 30s the phone gives up at the instant the FIRST
      // attempt expires, the confirm defaults to "no", and the user never sees
      // the question.
      adapter.handlers[ 'POST /api/v2/ask' ] = ( _ ) => jsonBody( doneBody() );
      await repo.ask( const AskRequest( question: 'q' ) );

      final opts = adapter.captured.single;
      expect( opts.receiveTimeout, QueueRepository.askReceiveTimeout );
      expect( opts.receiveTimeout!.inSeconds, greaterThanOrEqualTo( 240 ) );
    } );

    test( 'every OTHER call is left on the global budget — 30s is right for them', () async {
      adapter.handlers[ 'GET /api/get-queue/done' ] =
          ( _ ) => jsonBody( { 'done_jobs_metadata': [] } );
      await repo.getQueue( 'done' );

      // Not widened: the request carries no per-request override at all.
      expect( adapter.captured.single.receiveTimeout, isNull );
    } );
  } );
}

// ─────────────────────────────────────────────────────────────────────────
// AC-S4.8 — the resume door. FOUR fields on the wire, and `websocket_id`
// asserted in the CAPTURED BODY rather than in the signature: a signature
// that accepts a parameter and never sends it compiles, type-checks, and
// silences the answer's TTS on every turn after the first.
// ─────────────────────────────────────────────────────────────────────────

void _resumeDoor() {
  group( 'AC-S4.8 — POST /api/v2/resume', () {
    late StubAdapter adapter;
    late QueueRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = QueueRepository( makeDio( adapter ) );
    } );

    Map<String, dynamic> parkedBody( { String? pendingId, List<String>? missing } ) => {
      'path' : 'agent', 'status' : 'parked', 'route_reason' : 'r',
      'trace_id' : 't', 'answer' : 'Which city?',
      'pending_id' : pendingId ?? 'pend-1',
      'args_missing' : missing ?? [ 'city', 'date' ],
    };

    test( 'posts to /api/v2/resume with ALL FOUR fields — websocket_id is in '
          'the BODY', () async {
      adapter.handlers[ 'POST /api/v2/resume' ] = ( _ ) => jsonBody( parkedBody() );

      await repo.resume( const ResumeRequest(
        pendingId   : 'pend-1',
        answer      : 'Boston',
        websocketId : 'wise penguin',
        speak       : true,
      ) );

      final req = adapter.captured.single;
      expect( req.path, '/api/v2/resume' );

      final body = req.data as Map<String, dynamic>;
      expect( body[ 'pending_id' ],   'pend-1' );
      expect( body[ 'answer' ],       'Boston' );
      expect( body[ 'websocket_id' ], 'wise penguin',
              reason: 'this is how the answer\'s TTS is routed — the ask turn '
                      'sets it and the resume turn must too, or the second '
                      'turn of one conversation speaks nowhere' );
      expect( body[ 'speak' ],        true );
      expect( body.keys.length, 4 );
    } );

    test( 'speak: false rides the wire too — it is a value, not an absence',
          () async {
      adapter.handlers[ 'POST /api/v2/resume' ] = ( _ ) => jsonBody( parkedBody() );
      await repo.resume( const ResumeRequest(
        pendingId: 'p', answer: 'a', websocketId: 'w', speak: false ) );

      expect( ( adapter.captured.single.data as Map )[ 'speak' ], false );
    } );

    test( 'the resume turn carries the SAME long budget as the ask turn — a '
          'resume re-enters the same blocking flow', () async {
      adapter.handlers[ 'POST /api/v2/resume' ] = ( _ ) => jsonBody( parkedBody() );
      await repo.resume( const ResumeRequest( pendingId: 'p', answer: 'a' ) );

      expect( adapter.captured.single.receiveTimeout,
              QueueRepository.askReceiveTimeout );
    } );

    test( 'AC-S4.12 — a second `parked` comes back on the SAME pending_id and '
          'args_missing has shrunk by one', () async {
      adapter.handlers[ 'POST /api/v2/resume' ] =
          ( _ ) => jsonBody( parkedBody( missing: [ 'date' ] ) );

      final next = await repo.resume( const ResumeRequest(
        pendingId: 'pend-1', answer: 'Boston', websocketId: 'w' ) );

      expect( next.isParked, isTrue,
              reason: 'the interview CONTINUES; treating turn one as terminal '
                      'is ruling 5 half-implemented' );
      expect( next.pendingId, 'pend-1', reason: 'same pending_id, next arg' );
      expect( next.argsMissing, [ 'date' ] );
    } );

    test( 'AC-S4.13 — the door\'s two endings arrive as distinct statuses, '
          'not as one generic failure', () async {
      for ( final ending in [ 'pending_expired', 'already_resumed' ] ) {
        adapter = StubAdapter();
        repo    = QueueRepository( makeDio( adapter ) );
        adapter.handlers[ 'POST /api/v2/resume' ] = ( _ ) => jsonBody( {
          'path' : 'agent', 'status' : ending, 'route_reason' : 'r',
          'trace_id' : 't',
        } );

        final res = await repo.resume(
          const ResumeRequest( pendingId: 'p', answer: 'a' ) );
        expect( res.status, ending,
                reason: 'the status must survive to the caller — collapsing '
                        'it here is where the generic error card comes from' );
      }
    } );

    test( 'AC-S4.1 / AC-S4.2 — parked and needs_input are DISTINCT: one has '
          'an id to answer to, the other has none', () {
      final parked = AskResponse.fromJson( parkedBody() );
      expect( parked.isParked, isTrue );
      expect( parked.isNeedsInput, isFalse );
      expect( parked.pendingId, isNotNull );

      final needsInput = AskResponse.fromJson( {
        'path' : 'agent', 'status' : 'needs_input', 'route_reason' : 'r',
        'trace_id' : 't', 'args_missing' : [ 'city' ],
      } );
      expect( needsInput.isNeedsInput, isTrue );
      expect( needsInput.isParked, isFalse );
      expect( needsInput.pendingId, isNull,
              reason: 'flow.py hard-codes interactive=False on submit, so it '
                      'never parks — an answer box here has nowhere to send' );
    } );
  } );
}
