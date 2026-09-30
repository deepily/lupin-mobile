import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';

void main() {
  _acS15();
  group( 'AskRequest.toJson', () {
    test( 'maps fields to snake_case with speak/interactive defaults true', () {
      const r = AskRequest( question: 'q1', websocketId: 'ws-1' );
      final j = r.toJson();
      expect( j[ 'question'     ], 'q1' );
      expect( j[ 'websocket_id' ], 'ws-1' );
      expect( j[ 'speak'        ], isTrue );
      expect( j[ 'interactive'  ], isTrue );
    } );

    test( 'omits websocket_id when null and honours speak/interactive overrides', () {
      final j = const AskRequest( question: 'q', speak: false, interactive: false ).toJson();
      expect( j.containsKey( 'websocket_id' ), isFalse );
      expect( j[ 'speak'       ], isFalse );
      expect( j[ 'interactive' ], isFalse );
    } );
  } );

  group( 'AskResponse.fromJson', () {
    test( 'parses the full §8 result dict', () {
      final r = AskResponse.fromJson( {
        'path'          : 'replay',
        'status'        : 'done',
        'route_reason'  : 'cache:exact',
        'answer'        : 'It is 3pm.',
        'answer_raw'    : '15:00',
        'command'       : 'agent router go to date and time',
        'args_known'    : [ 'tz' ],
        'args_missing'  : [],
        'pending_id'    : null,
        'job_id'        : 'h-1',
        'snapshot_id'   : 'snap-1',
        'similarity'    : 100,
        'wrote_snapshot': false,
        'cache_hit'     : true,
        'spoke'         : true,
        'timings_ms'    : { 'total': 42 },
        'trace_id'      : 'tr-9',
        'error'         : null,
      } );
      expect( r.path,          'replay' );
      expect( r.isDone,        isTrue );
      expect( r.cacheHit,      isTrue );
      expect( r.similarity,    100.0 );
      expect( r.argsKnown,     [ 'tz' ] );
      expect( r.timingsMs[ 'total' ], 42 );
      expect( r.summary,       'It is 3pm.' );
    } );

    test( 'tolerates a minimal body and derives needsInput / isFailed / summary', () {
      final parked = AskResponse.fromJson( {
        'path': 'needs_input', 'status': 'needs_input', 'trace_id': 't',
        'args_missing': [ 'city', 'date' ],
      } );
      expect( parked.needsInput, isTrue );
      expect( parked.answer,     isNull );
      expect( parked.summary,    'Needs input: city, date' );

      final failed = AskResponse.fromJson( {
        'path': 'receptionist', 'status': 'failed', 'trace_id': 't', 'error': 'router down',
      } );
      expect( failed.isFailed, isTrue );
      expect( failed.summary,  'router down' );
    } );
  } );

  group( 'PushJobResponse.fromJson', () {
    test( 'parses required fields', () {
      final r = PushJobResponse.fromJson( {
        'status'          : 'queued',
        'websocket_id'    : 'ws-1',
        'user_id'         : 'u-1',
        'job_id'          : 'j-1',
        'routing_command' : 'math',
      } );
      expect( r.status,         'queued' );
      expect( r.jobId,          'j-1' );
      expect( r.routingCommand, 'math' );
    } );

    test( 'tolerates missing optional fields', () {
      final r = PushJobResponse.fromJson( {
        'status'      : 'queued',
        'websocket_id': 'ws-x',
        'user_id'     : 'u-x',
      } );
      expect( r.jobId,  isNull );
      expect( r.result, isNull );
    } );
  } );

  group( 'JobSummary.fromJson', () {
    test( 'parses a running job', () {
      final j = JobSummary.fromJson( {
        'job_id'       : 'j-2',
        'question_text': 'What is 2+2?',
        'agent_type'   : 'MathAgent',
        'status'       : 'running',
        'paused'       : false,
      } );
      expect( j.jobId,        'j-2' );
      expect( j.agentType,    'MathAgent' );
      expect( j.status,       'running' );
      expect( j.paused,       isFalse );
      expect( j.hasInteractions, isFalse );
    } );

    test( 'parses a done job with response_text', () {
      final j = JobSummary.fromJson( {
        'job_id'          : 'j-3',
        'question_text'   : 'x',
        'agent_type'      : 'Bot',
        'status'          : 'done',
        'response_text'   : 'The answer is 4',
        'has_interactions': true,
        'duration_seconds': 2.5,
        'paused'          : false,
      } );
      expect( j.responseText,     'The answer is 4' );
      expect( j.hasInteractions,  isTrue );
      expect( j.durationSeconds,  2.5 );
    } );
  } );

  group( 'QueueResponse.fromJson', () {
    test( 'reads jobs from queueName_jobs_metadata key', () {
      final qr = QueueResponse.fromJson( 'todo', {
        'todo_jobs_metadata': [
          { 'job_id': 'j-1', 'question_text': 'hi', 'agent_type': 'A', 'status': 'todo', 'paused': false },
          { 'job_id': 'j-2', 'question_text': 'by', 'agent_type': 'B', 'status': 'todo', 'paused': false },
        ],
      } );
      expect( qr.queueName,  'todo' );
      expect( qr.jobs.length, 2 );
      expect( qr.jobs.first.jobId, 'j-1' );
    } );

    test( 'returns empty list when key missing', () {
      final qr = QueueResponse.fromJson( 'done', {} );
      expect( qr.jobs, isEmpty );
    } );
  } );

  group( 'JobInteraction.fromJson', () {
    test( 'parses all fields', () {
      final i = JobInteraction.fromJson( {
        'id'                : 'i-1',
        'type'              : 'ask_yes_no',
        'message'           : 'Continue?',
        'timestamp'         : '2026-04-15T12:00:00Z',
        'response_requested': true,
        'response_value'    : 'yes',
        'priority'          : 'high',
        'abstract'          : 'some context',
      } );
      expect( i.type,            'ask_yes_no' );
      expect( i.responseValue,   'yes' );
      expect( i.priority,        'high' );
    } );
  } );

  group( 'JobHistoryEntry.fromJson', () {
    test( 'parses core fields', () {
      final e = JobHistoryEntry.fromJson( {
        'id_hash'         : 'h-1',
        'job_type'        : 'MathAgent',
        'user_id'         : 'u-1',
        'user_email'      : 'u@x.y',
        'session_id'      : 's-1',
        'routing_command' : 'math',
        'status'          : 'done',
        'question_text'   : 'q?',
        'is_cache_hit'    : false,
        'duration_seconds': 1.0,
        'metadata_json'   : '{}',
        'submitted_at'    : '2026-04-15T10:00:00Z',
        'completed_at'    : '2026-04-15T10:01:00Z',
      } );
      expect( e.idHash,    'h-1' );
      expect( e.jobType,   'MathAgent' );
      expect( e.status,    'done' );
    } );
  } );
}

// ─────────────────────────────────────────────────────────────────────────
// AC-S1.5 — `AskResponse` reports `waiting` distinctly.
// ─────────────────────────────────────────────────────────────────────────

void _acS15() {
  group( 'AC-S1.5 — the waiting branch', () {
    AskResponse waiting() => AskResponse.fromJson( const {
      'path'         : 'agent',
      'status'       : 'waiting',
      'route_reason' : 'router:weather',
      'answer'       : null,
      'job_id'       : 'j-1',
      'trace_id'     : 'tr-1',
    } );

    test( 'isWaiting is true, and the other three predicates stay false', () {
      final r = waiting();
      expect( r.isWaiting,  isTrue );
      expect( r.isDone,     isFalse );
      expect( r.needsInput, isFalse );
      expect( r.isFailed,   isFalse );
    } );

    test( 'summary does NOT say "Done" for queued work', () {
      // The live bug: all three predicates were false for `waiting`, so
      // `summary` fell through to `'Done ($path)'` and `submit_job_sheet.dart`
      // popped its sheet reporting success for work that had not started.
      final s = waiting().summary;
      expect( s, isNot( contains( 'Done' ) ) );
      expect( s, contains( 'Queued' ) );
    } );

    test( 'a genuinely done response still summarises as before — no regression', () {
      final r = AskResponse.fromJson( const {
        'path'         : 'replay',
        'status'       : 'done',
        'route_reason' : 'exact_hit',
        'answer'       : 'Four.',
        'trace_id'     : 'tr-2',
      } );
      expect( r.isWaiting, isFalse );
      expect( r.summary,   'Four.' );
    } );

    test( 'a done response with a null answer keeps the "Done (path)" fallback', () {
      final r = AskResponse.fromJson( const {
        'path'         : 'agent',
        'status'       : 'done',
        'route_reason' : 'router:x',
        'trace_id'     : 'tr-3',
      } );
      expect( r.summary, 'Done (agent)' );
    } );
  } );
}
