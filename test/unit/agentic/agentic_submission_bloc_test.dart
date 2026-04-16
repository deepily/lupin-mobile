import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_repository.dart';
import 'package:lupin_mobile/features/agentic/data/bug_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/chained_models.dart';
import 'package:lupin_mobile/features/agentic/data/deep_research_models.dart';
import 'package:lupin_mobile/features/agentic/data/podcast_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_suite_models.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_event.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';

import '../_helpers/stub_dio.dart';

Map<String, dynamic> _submitResp( String jobId ) => {
  'status'        : 'queued',
  'job_id'        : jobId,
  'queue_position': 1,
};

void main() {
  group( 'AgenticSubmissionBloc', () {
    late StubAdapter          adapter;
    late AgenticRepository    repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = AgenticRepository( makeDio( adapter ) );
    } );

    // ─── AgenticFormReset ────────────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'AgenticFormReset returns to Initial',
      build: () => AgenticSubmissionBloc( repo ),
      act  : ( b ) => b.add( const AgenticFormReset() ),
      expect: () => [ isA<AgenticSubmissionInitial>() ],
    );

    // ─── DeepResearch success ─────────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'deepResearch submit emits InProgress → Success',
      setUp: () {
        adapter.handlers[ 'POST /api/deep-research/submit' ] = ( _ ) =>
            jsonBody( _submitResp( 'dr-aaa' ) );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.deepResearch,
        request: DeepResearchRequest( query: 'q' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionSuccess>()
          .having( ( s ) => s.jobId, 'jobId', 'dr-aaa' )
          .having( ( s ) => s.type,  'type',  AgenticJobType.deepResearch ),
      ],
    );

    // ─── Podcast success ──────────────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'podcast submit emits InProgress → Success',
      setUp: () {
        adapter.handlers[ 'POST /api/podcast-generator/submit' ] = ( _ ) =>
            jsonBody( _submitResp( 'pg-bbb' ) );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.podcast,
        request: PodcastGeneratorRequest( researchSource: 'src' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionSuccess>().having( ( s ) => s.jobId, 'jobId', 'pg-bbb' ),
      ],
    );

    // ─── TestFixExpediter TFE resume path ────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'testFixExpediter submit emits InProgress → TfeResumeSuccess',
      setUp: () {
        adapter.handlers[ 'POST /api/test-fix-expediter/resume-from' ] = ( _ ) =>
            jsonBody( {
              'status'           : 'queued',
              'resumed_job_id'   : 'tfe-new',
              'original_job_id'  : 'tfe-old',
              'resume_from_phase': 1,
              'phase_name'       : 'setup',
              'resume_count'     : 1,
            } );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.testFixExpediter,
        request: TfeResumeFromRequest( resumeFrom: 'tfe-old' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<TfeResumeSuccess>()
          .having( ( s ) => s.response.resumedJobId, 'resumedJobId', 'tfe-new' )
          .having( ( s ) => s.response.phaseName,    'phaseName',    'setup'   ),
      ],
    );

    // ─── TestSuite success ────────────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'testSuite submit emits InProgress → Success',
      setUp: () {
        adapter.handlers[ 'POST /api/test-suite/submit' ] = ( _ ) =>
            jsonBody( _submitResp( 'ts-ccc' ) );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.testSuite,
        request: TestSuiteRequest( testTypes: 'integration' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionSuccess>().having( ( s ) => s.jobId, 'jobId', 'ts-ccc' ),
      ],
    );

    // ─── BugFixExpediter success ──────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'bugFixExpediter submit emits InProgress → Success',
      setUp: () {
        adapter.handlers[ 'POST /api/bug-fix-expediter/submit' ] = ( _ ) =>
            jsonBody( _submitResp( 'bfe-ddd' ) );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.bugFixExpediter,
        request: BugFixExpediterRequest( deadJobId: 'bfe-dead' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionSuccess>().having( ( s ) => s.jobId, 'jobId', 'bfe-ddd' ),
      ],
    );

    // ─── ResearchToPodcast success ────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'researchToPodcast submit emits InProgress → Success',
      setUp: () {
        adapter.handlers[ 'POST /api/deep-research-to-podcast/submit' ] = ( _ ) =>
            jsonBody( _submitResp( 'rp-eee' ) );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.researchToPodcast,
        request: ResearchToPodcastRequest( query: 'q' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionSuccess>().having( ( s ) => s.jobId, 'jobId', 'rp-eee' ),
      ],
    );

    // ─── ResearchToPresentation success ───────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'researchToPresentation submit emits InProgress → Success',
      setUp: () {
        adapter.handlers[ 'POST /api/deep-research-to-presentation/submit' ] = ( _ ) =>
            jsonBody( _submitResp( 'rx-fff' ) );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.researchToPresentation,
        request: ResearchToPresentationRequest( query: 'q' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionSuccess>().having( ( s ) => s.jobId, 'jobId', 'rx-fff' ),
      ],
    );

    // ─── API error → Failure ──────────────────
    blocTest<AgenticSubmissionBloc, AgenticSubmissionState>(
      'submit emits InProgress → Failure on 500',
      setUp: () {
        adapter.handlers[ 'POST /api/deep-research/submit' ] = ( _ ) =>
            jsonBody( { 'detail': 'server error' }, status: 500 );
      },
      build : () => AgenticSubmissionBloc( repo ),
      act   : ( b ) => b.add( AgenticSubmitRequested(
        type   : AgenticJobType.deepResearch,
        request: DeepResearchRequest( query: 'q' ),
      ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<AgenticSubmissionInProgress>(),
        isA<AgenticSubmissionFailure>()
          .having( ( s ) => s.error, 'error', isNotEmpty ),
      ],
    );
  } );
}
