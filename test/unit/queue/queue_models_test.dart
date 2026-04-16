import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';

void main() {
  group( 'PushJobRequest.toJson', () {
    test( 'maps fields to snake_case', () {
      final r = PushJobRequest( question: 'q1', websocketId: 'ws-1' );
      final j = r.toJson();
      expect( j[ 'question'     ], 'q1' );
      expect( j[ 'websocket_id' ], 'ws-1' );
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
