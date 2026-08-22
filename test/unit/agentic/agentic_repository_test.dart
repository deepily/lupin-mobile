import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_repository.dart';
import 'package:lupin_mobile/features/agentic/data/bug_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/chained_models.dart';
import 'package:lupin_mobile/features/agentic/data/deep_research_models.dart';
import 'package:lupin_mobile/features/agentic/data/podcast_models.dart';
import 'package:lupin_mobile/features/agentic/data/presentation_models.dart';
import 'package:lupin_mobile/features/agentic/data/swe_team_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_suite_models.dart';

import '../_helpers/stub_dio.dart';

// Shared fixture: the synchronous /api/v2/submit body for an accepted long job.
// `status: 'waiting'` + job_id IS the success (the work runs behind the queue).
Map<String, dynamic> _submitResp( String jobId, { String command = 'agent router go to deep research' } ) => {
  'path'         : 'agent',
  'status'       : 'waiting',
  'route_reason' : 'submitted',
  'command'      : command,
  'job_id'       : jobId,
  'trace_id'     : 'tr-$jobId',
};

void main() {
  group( 'AgenticRepository', () {
    late StubAdapter    adapter;
    late AgenticRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = AgenticRepository( makeDio( adapter ) );
    } );

    // ─── submitDeepResearch ───────────────────
    test( 'submitDeepResearch POSTs to correct endpoint and returns jobId', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'command' ], 'agent router go to deep research' );
        expect( body[ 'args' ][ 'query' ], 'AI trends' );
        expect( body[ 'question' ], 'AI trends' );
        return jsonBody( _submitResp( 'dr-abc' ) );
      };
      final r = await repo.submitDeepResearch( DeepResearchRequest( query: 'AI trends' ) );
      expect( r.jobId, 'dr-abc' );
    } );

    test( 'submitDeepResearch throws AgenticApiException on 500', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) =>
          jsonBody( { 'detail': 'server error' }, status: 500 );
      await expectLater(
        repo.submitDeepResearch( DeepResearchRequest( query: 'q' ) ),
        throwsA( isA<AgenticApiException>() ),
      );
    } );

    // ─── fetchDeepResearchReport ─────────────
    test( 'fetchDeepResearchReport GETs with job_id query param', () async {
      adapter.handlers[ 'GET /api/deep-research/report' ] = ( opts ) {
        expect( opts.queryParameters[ 'job_id' ], 'dr-1' );
        return jsonBody( { 'job_id': 'dr-1', 'report': '# Hello' } );
      };
      final r = await repo.fetchDeepResearchReport( 'dr-1' );
      expect( r.markdownText, '# Hello' );
    } );

    // ─── submitPodcast ───────────────────────
    test( 'submitPodcast POSTs to correct endpoint', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'command' ], 'agent router go to podcast generator' );
        expect( body[ 'args' ][ 'research' ], '/reports/dr-1.md', reason: 'research_source → research (contract key)' );
        expect( body[ 'args' ].containsKey( 'research_source' ), isFalse );
        return jsonBody( _submitResp( 'pg-001' ) );
      };
      final r = await repo.submitPodcast(
        PodcastGeneratorRequest( researchSource: '/reports/dr-1.md' ),
      );
      expect( r.jobId, 'pg-001' );
    } );

    // ─── submitPresentation ─────────────────
    test( 'submitPresentation POSTs source_path', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'command' ], 'agent router go to presentation generator' );
        expect( body[ 'args' ][ 'source' ], '/reports/dr-2.md', reason: 'source_path → source (contract key)' );
        return jsonBody( _submitResp( 'px-002' ) );
      };
      final r = await repo.submitPresentation(
        PresentationGeneratorRequest( sourcePath: '/reports/dr-2.md' ),
      );
      expect( r.jobId, 'px-002' );
    } );

    // ─── submitSweTeam ───────────────────────
    test( 'submitSweTeam POSTs task field', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'args' ][ 'task' ], 'refactor auth' );
        return jsonBody( _submitResp( 'sw-003' ) );
      };
      final r = await repo.submitSweTeam( SweTeamRequest( task: 'refactor auth' ) );
      expect( r.jobId, 'sw-003' );
    } );

    // ─── submitBugFixExpediter ───────────────
    test( 'submitBugFixExpediter POSTs dead_job_id', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'args' ][ 'dead_job_id' ], 'bfe-dead' );
        return jsonBody( _submitResp( 'bfe-new' ) );
      };
      final r = await repo.submitBugFixExpediter(
        BugFixExpediterRequest( deadJobId: 'bfe-dead' ),
      );
      expect( r.jobId, 'bfe-new' );
    } );

    // ─── submitTestSuite ─────────────────────
    test( 'submitTestSuite POSTs to correct endpoint', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'args' ][ 'test_types' ], 'unit' );
        return jsonBody( _submitResp( 'ts-004' ) );
      };
      final r = await repo.submitTestSuite( TestSuiteRequest( testTypes: 'unit' ) );
      expect( r.jobId, 'ts-004' );
    } );

    // ─── resumeTestFixExpediter ──────────────
    test( 'resumeTestFixExpediter POSTs to resume-from and returns TfeResumeResponse', () async {
      adapter.handlers[ 'POST /api/test-fix-expediter/resume-from' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'resume_from' ], 'tfe-old' );
        return jsonBody( {
          'status'           : 'queued',
          'resumed_job_id'   : 'tfe-new',
          'original_job_id'  : 'tfe-old',
          'resume_from_phase': 2,
          'phase_name'       : 'run_tests',
          'resume_count'     : 1,
        } );
      };
      final r = await repo.resumeTestFixExpediter(
        TfeResumeFromRequest( resumeFrom: 'tfe-old' ),
      );
      expect( r.resumedJobId, 'tfe-new' );
      expect( r.phaseName,    'run_tests' );
    } );

    // ─── submitResearchToPodcast ─────────────
    test( 'submitResearchToPodcast POSTs to chained endpoint', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'args' ][ 'query' ], 'fusion energy' );
        return jsonBody( _submitResp( 'rp-005' ) );
      };
      final r = await repo.submitResearchToPodcast(
        ResearchToPodcastRequest( query: 'fusion energy' ),
      );
      expect( r.jobId, 'rp-005' );
    } );

    // ─── submitResearchToPresentation ────────
    test( 'submitResearchToPresentation POSTs to chained endpoint', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'args' ][ 'query' ], 'climate data' );
        return jsonBody( _submitResp( 'rx-006' ) );
      };
      final r = await repo.submitResearchToPresentation(
        ResearchToPresentationRequest( query: 'climate data' ),
      );
      expect( r.jobId, 'rx-006' );
    } );
    // ─── v2 wave 2: the door's own semantics ──
    test( 'queue directives ride TOP-LEVEL on /api/v2/submit, never inside args', () async {
      late Map<String, dynamic> body;
      adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
        body = opts.data as Map<String, dynamic>;
        return jsonBody( _submitResp( 'dr-sched' ) );
      };
      await repo.submitDeepResearch( const DeepResearchRequest( query: 'q', scheduledAt: '2026-08-22T10:00:00-04:00', monopolize: true, websocketId: 'mobile' ) );
      expect( body[ 'scheduled_at' ], '2026-08-22T10:00:00-04:00' );
      expect( body[ 'monopolize' ], isTrue );
      expect( body[ 'websocket_id' ], 'mobile' );
      for ( final k in [ 'scheduled_at', 'monopolize', 'websocket_id' ] ) {
        expect( ( body[ 'args' ] as Map ).containsKey( k ), isFalse, reason: '$k is a queue directive, not an agent arg' );
      }
      final plain = await _capture( adapter, repo );
      expect( plain.containsKey( 'scheduled_at' ), isFalse );
      expect( plain.containsKey( 'monopolize' ),   isFalse, reason: 'unset → omitted (server default false)' );
    } );

    test( 'needs_input from /api/v2/submit surfaces as AgenticApiException naming the missing args', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( {
        'path': 'needs_input', 'status': 'needs_input', 'route_reason': 'args_incomplete_no_park',
        'command': 'agent router go to deep research', 'args_missing': [ 'query' ], 'trace_id': 'tr-ni',
      } );
      await expectLater(
        repo.submitDeepResearch( const DeepResearchRequest( query: '' ) ),
        throwsA( isA<AgenticApiException>().having( ( e ) => e.message, 'message', contains( 'query' ) ) ),
      );
    } );

    test( 'a receptionist / no-job body never reads as a submitted job', () async {
      adapter.handlers[ 'POST /api/v2/submit' ] = ( _ ) => jsonBody( {
        'path': 'receptionist', 'status': 'done', 'route_reason': 'unknown_command',
        'answer': "I don't know that command", 'job_id': null, 'trace_id': 'tr-rc',
      } );
      await expectLater(
        repo.submitSweTeam( const SweTeamRequest( task: 't' ) ),
        throwsA( isA<AgenticApiException>().having( ( e ) => e.message, 'message', contains( "don't know" ) ) ),
      );
    } );
  } );
}

Future<Map<String, dynamic>> _capture( StubAdapter adapter, AgenticRepository repo ) async {
  late Map<String, dynamic> body;
  adapter.handlers[ 'POST /api/v2/submit' ] = ( opts ) {
    body = opts.data as Map<String, dynamic>;
    return jsonBody( _submitResp( 'dr-plain' ) );
  };
  await repo.submitDeepResearch( const DeepResearchRequest( query: 'q' ) );
  return body;
}
