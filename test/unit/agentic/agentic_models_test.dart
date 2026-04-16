import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/bug_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/chained_models.dart';
import 'package:lupin_mobile/features/agentic/data/deep_research_models.dart';
import 'package:lupin_mobile/features/agentic/data/podcast_models.dart';
import 'package:lupin_mobile/features/agentic/data/presentation_models.dart';
import 'package:lupin_mobile/features/agentic/data/swe_team_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_suite_models.dart';

void main() {
  // ─────────────────────────────────────────────
  // AgenticSubmitResponse
  // ─────────────────────────────────────────────
  group( 'AgenticSubmitResponse', () {
    test( 'fromJson parses required fields', () {
      final r = AgenticSubmitResponse.fromJson( {
        'status'        : 'queued',
        'job_id'        : 'dr-abc123',
        'queue_position': 2,
      } );
      expect( r.status,        'queued'   );
      expect( r.jobId,         'dr-abc123' );
      expect( r.queuePosition, 2          );
      expect( r.message,       isNull     );
    } );

    test( 'fromJson defaults queuePosition to 0 when absent', () {
      final r = AgenticSubmitResponse.fromJson( {
        'status': 'queued',
        'job_id': 'pg-xyz',
      } );
      expect( r.queuePosition, 0      );
      expect( r.message,       isNull );
    } );
  } );

  // ─────────────────────────────────────────────
  // TfeResumeResponse
  // ─────────────────────────────────────────────
  group( 'TfeResumeResponse', () {
    test( 'fromJson parses all fields', () {
      final r = TfeResumeResponse.fromJson( {
        'status'          : 'queued',
        'resumed_job_id'  : 'tfe-001',
        'original_job_id' : 'tfe-000',
        'resume_from_phase': 3,
        'phase_name'      : 'fix_apply',
        'resume_count'    : 1,
      } );
      expect( r.status,           'queued'    );
      expect( r.resumedJobId,     'tfe-001'   );
      expect( r.originalJobId,    'tfe-000'   );
      expect( r.resumeFromPhase,  3           );
      expect( r.phaseName,        'fix_apply' );
      expect( r.resumeCount,      1           );
    } );
  } );

  // ─────────────────────────────────────────────
  // DeepResearchRequest
  // ─────────────────────────────────────────────
  group( 'DeepResearchRequest', () {
    test( 'toJson includes required query only when optionals absent', () {
      final j = DeepResearchRequest( query: 'AI trends' ).toJson();
      expect( j[ 'query'    ], 'AI trends' );
      expect( j.containsKey( 'budget'   ), isFalse );
      expect( j.containsKey( 'dry_run'  ), isFalse );
    } );

    test( 'toJson includes optionals when set', () {
      final j = DeepResearchRequest(
        query   : 'test',
        budget  : 5.0,
        dryRun  : true,
        audience: 'expert',
      ).toJson();
      expect( j[ 'budget'   ], 5.0     );
      expect( j[ 'dry_run'  ], true    );
      expect( j[ 'audience' ], 'expert' );
    } );
  } );

  // ─────────────────────────────────────────────
  // DeepResearchReport
  // ─────────────────────────────────────────────
  group( 'DeepResearchReport', () {
    test( 'fromJson reads markdownText from report key', () {
      final r = DeepResearchReport.fromJson( {
        'job_id': 'dr-1',
        'report': '# Title\ncontent',
      } );
      expect( r.markdownText, '# Title\ncontent' );
    } );

    test( 'fromJson falls back to content key', () {
      final r = DeepResearchReport.fromJson( {
        'job_id' : 'dr-2',
        'content': 'fallback text',
      } );
      expect( r.markdownText, 'fallback text' );
    } );
  } );

  // ─────────────────────────────────────────────
  // PodcastGeneratorRequest
  // ─────────────────────────────────────────────
  group( 'PodcastGeneratorRequest', () {
    test( 'toJson serialises researchSource', () {
      final j = PodcastGeneratorRequest( researchSource: '/reports/dr-1.md' ).toJson();
      expect( j[ 'research_source' ], '/reports/dr-1.md' );
      expect( j.containsKey( 'target_languages' ), isFalse );
    } );

    test( 'toJson includes target_languages when non-empty', () {
      final j = PodcastGeneratorRequest(
        researchSource : 'src',
        targetLanguages: [ 'en', 'es' ],
      ).toJson();
      expect( j[ 'target_languages' ], [ 'en', 'es' ] );
    } );
  } );

  // ─────────────────────────────────────────────
  // PresentationGeneratorRequest
  // ─────────────────────────────────────────────
  group( 'PresentationGeneratorRequest', () {
    test( 'toJson serialises sourcePath', () {
      final j = PresentationGeneratorRequest( sourcePath: '/reports/dr-1.md' ).toJson();
      expect( j[ 'source_path' ], '/reports/dr-1.md' );
      expect( j.containsKey( 'theme'       ), isFalse );
      expect( j.containsKey( 'render_only' ), isFalse );
    } );

    test( 'toJson includes render_only when true', () {
      final j = PresentationGeneratorRequest(
        sourcePath : 'src',
        renderOnly : true,
        theme      : 'dark',
      ).toJson();
      expect( j[ 'render_only' ], true   );
      expect( j[ 'theme'       ], 'dark' );
    } );
  } );

  // ─────────────────────────────────────────────
  // SweTeamRequest
  // ─────────────────────────────────────────────
  group( 'SweTeamRequest', () {
    test( 'toJson serialises task', () {
      final j = SweTeamRequest( task: 'fix the bug' ).toJson();
      expect( j[ 'task' ], 'fix the bug' );
      expect( j.containsKey( 'trust_mode' ), isFalse );
    } );

    test( 'toJson includes trust_mode when set', () {
      final j = SweTeamRequest( task: 't', trustMode: 'active' ).toJson();
      expect( j[ 'trust_mode' ], 'active' );
    } );
  } );

  // ─────────────────────────────────────────────
  // BugFixExpediterRequest
  // ─────────────────────────────────────────────
  group( 'BugFixExpediterRequest', () {
    test( 'toJson serialises deadJobId', () {
      final j = BugFixExpediterRequest( deadJobId: 'bfe-xyz' ).toJson();
      expect( j[ 'dead_job_id' ], 'bfe-xyz' );
      expect( j.containsKey( 'extra_context' ), isFalse );
    } );

    test( 'toJson includes extra_context when set', () {
      final j = BugFixExpediterRequest(
        deadJobId   : 'bfe-1',
        extraContext: 'timeout in phase 3',
      ).toJson();
      expect( j[ 'extra_context' ], 'timeout in phase 3' );
    } );
  } );

  // ─────────────────────────────────────────────
  // TestSuiteRequest
  // ─────────────────────────────────────────────
  group( 'TestSuiteRequest', () {
    test( 'toJson includes default test_types', () {
      final j = TestSuiteRequest().toJson();
      expect( j[ 'test_types' ], 'integration,e2e' );
      expect( j.containsKey( 'dry_run' ), isFalse );
    } );

    test( 'toJson includes testTypes and autoFixOnFailure when set', () {
      final j = TestSuiteRequest(
        testTypes      : 'unit,integration',
        autoFixOnFailure: true,
        dryRun         : true,
      ).toJson();
      expect( j[ 'test_types'         ], 'unit,integration' );
      expect( j[ 'auto_fix_on_failure' ], true              );
      expect( j[ 'dry_run'            ], true               );
    } );
  } );

  // ─────────────────────────────────────────────
  // TfeResumeFromRequest
  // ─────────────────────────────────────────────
  group( 'TfeResumeFromRequest', () {
    test( 'toJson serialises resume_from', () {
      final j = TfeResumeFromRequest( resumeFrom: 'tfe-abc' ).toJson();
      expect( j[ 'resume_from' ], 'tfe-abc' );
    } );
  } );

  // ─────────────────────────────────────────────
  // ResearchToPodcastRequest
  // ─────────────────────────────────────────────
  group( 'ResearchToPodcastRequest', () {
    test( 'toJson serialises query', () {
      final j = ResearchToPodcastRequest( query: 'quantum computing' ).toJson();
      expect( j[ 'query' ], 'quantum computing' );
      expect( j.containsKey( 'budget' ), isFalse );
    } );
  } );

  // ─────────────────────────────────────────────
  // ResearchToPresentationRequest
  // ─────────────────────────────────────────────
  group( 'ResearchToPresentationRequest', () {
    test( 'toJson serialises query and theme', () {
      final j = ResearchToPresentationRequest(
        query : 'machine learning',
        theme : 'minimal',
        dryRun: true,
      ).toJson();
      expect( j[ 'query'   ], 'machine learning' );
      expect( j[ 'theme'   ], 'minimal'          );
      expect( j[ 'dry_run' ], true               );
    } );
  } );
}
