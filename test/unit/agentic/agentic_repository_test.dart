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

// Shared fixture for a generic submit response.
Map<String, dynamic> _submitResp( String jobId ) => {
  'status'        : 'queued',
  'job_id'        : jobId,
  'queue_position': 1,
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
      adapter.handlers[ 'POST /api/deep-research/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'query' ], 'AI trends' );
        return jsonBody( _submitResp( 'dr-abc' ) );
      };
      final r = await repo.submitDeepResearch( DeepResearchRequest( query: 'AI trends' ) );
      expect( r.jobId, 'dr-abc' );
    } );

    test( 'submitDeepResearch throws AgenticApiException on 500', () async {
      adapter.handlers[ 'POST /api/deep-research/submit' ] = ( _ ) =>
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
      adapter.handlers[ 'POST /api/podcast-generator/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'research_source' ], '/reports/dr-1.md' );
        return jsonBody( _submitResp( 'pg-001' ) );
      };
      final r = await repo.submitPodcast(
        PodcastGeneratorRequest( researchSource: '/reports/dr-1.md' ),
      );
      expect( r.jobId, 'pg-001' );
    } );

    // ─── submitPresentation ─────────────────
    test( 'submitPresentation POSTs source_path', () async {
      adapter.handlers[ 'POST /api/presentation-generator/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'source_path' ], '/reports/dr-2.md' );
        return jsonBody( _submitResp( 'px-002' ) );
      };
      final r = await repo.submitPresentation(
        PresentationGeneratorRequest( sourcePath: '/reports/dr-2.md' ),
      );
      expect( r.jobId, 'px-002' );
    } );

    // ─── submitSweTeam ───────────────────────
    test( 'submitSweTeam POSTs task field', () async {
      adapter.handlers[ 'POST /api/swe-team/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'task' ], 'refactor auth' );
        return jsonBody( _submitResp( 'sw-003' ) );
      };
      final r = await repo.submitSweTeam( SweTeamRequest( task: 'refactor auth' ) );
      expect( r.jobId, 'sw-003' );
    } );

    // ─── submitBugFixExpediter ───────────────
    test( 'submitBugFixExpediter POSTs dead_job_id', () async {
      adapter.handlers[ 'POST /api/bug-fix-expediter/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'dead_job_id' ], 'bfe-dead' );
        return jsonBody( _submitResp( 'bfe-new' ) );
      };
      final r = await repo.submitBugFixExpediter(
        BugFixExpediterRequest( deadJobId: 'bfe-dead' ),
      );
      expect( r.jobId, 'bfe-new' );
    } );

    // ─── submitTestSuite ─────────────────────
    test( 'submitTestSuite POSTs to correct endpoint', () async {
      adapter.handlers[ 'POST /api/test-suite/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'test_types' ], 'unit' );
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
      adapter.handlers[ 'POST /api/deep-research-to-podcast/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'query' ], 'fusion energy' );
        return jsonBody( _submitResp( 'rp-005' ) );
      };
      final r = await repo.submitResearchToPodcast(
        ResearchToPodcastRequest( query: 'fusion energy' ),
      );
      expect( r.jobId, 'rp-005' );
    } );

    // ─── submitResearchToPresentation ────────
    test( 'submitResearchToPresentation POSTs to chained endpoint', () async {
      adapter.handlers[ 'POST /api/deep-research-to-presentation/submit' ] = ( opts ) {
        final body = opts.data as Map<String, dynamic>;
        expect( body[ 'query' ], 'climate data' );
        return jsonBody( _submitResp( 'rx-006' ) );
      };
      final r = await repo.submitResearchToPresentation(
        ResearchToPresentationRequest( query: 'climate data' ),
      );
      expect( r.jobId, 'rx-006' );
    } );
  } );
}
