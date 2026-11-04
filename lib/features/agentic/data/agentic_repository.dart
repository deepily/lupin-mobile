import 'package:dio/dio.dart';

import '../../queue/data/queue_models.dart';
import 'agentic_common_models.dart';
import 'bug_fix_expediter_models.dart';
import 'chained_models.dart';
import 'deep_research_models.dart';
import 'podcast_models.dart';
import 'presentation_models.dart';
import 'swe_team_models.dart';
import 'test_fix_expediter_models.dart';
import 'test_suite_models.dart';

/// Typed wrapper over the agentic job endpoints, using the shared authenticated Dio.
///
/// Eight submit calls post to `/api/v2/submit` and read the synchronous answer.
/// Status `waiting` with a job id is the success case.
/// Each request model supplies the contract keys through `toSubmitArgs()`.
/// The test-fix-expediter resume call keeps its own endpoint, because a job built
/// from a checkpoint cannot be expressed in the submit body.
/// The deep research report call is a read.
class AgenticRepository {
  final Dio _dio;
  /// Creates a repository over [_dio].
  const AgenticRepository( this._dio );

  // ─────────────────────────────────────────────
  // DeepResearchRequest → POST /api/v2/submit   (was /api/deep-research/submit)
  // ─────────────────────────────────────────────

  /// Submits a deep research job and returns the created job.
  Future<AgenticSubmitResponse> submitDeepResearch( DeepResearchRequest req ) =>
      _submit( 'submitDeepResearch', SubmitRequest(
        command     : DeepResearchRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : req.query,
        websocketId : req.websocketId,
        scheduledAt : req.scheduledAt,
        monopolize  : req.monopolize ? true : null,
      ) );

  // ─────────────────────────────────────────────
  // GET /api/deep-research/report?job_id=...
  // ─────────────────────────────────────────────

  /// Fetches the finished markdown report for [jobId].
  ///
  /// Raises [AgenticApiException] when the request fails.
  Future<DeepResearchReport> fetchDeepResearchReport( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/deep-research/report',
        queryParameters: { 'job_id': jobId },
      );
      return DeepResearchReport.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'fetchDeepResearchReport($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // PodcastGeneratorRequest → POST /api/v2/submit   (was /api/podcast-generator/submit)
  // ─────────────────────────────────────────────

  /// Submits a podcast generation job and returns the created job.
  Future<AgenticSubmitResponse> submitPodcast( PodcastGeneratorRequest req ) =>
      _submit( 'submitPodcast', SubmitRequest(
        command     : PodcastGeneratorRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : 'podcast from ${req.researchSource}',
        websocketId : null,
        scheduledAt : req.scheduledAt,
        monopolize  : req.monopolize ? true : null,
      ) );

  // ─────────────────────────────────────────────
  // PresentationGeneratorRequest → POST /api/v2/submit   (was /api/presentation-generator/submit)
  // ─────────────────────────────────────────────

  /// Submits a presentation generation job and returns the created job.
  Future<AgenticSubmitResponse> submitPresentation( PresentationGeneratorRequest req ) =>
      _submit( 'submitPresentation', SubmitRequest(
        command     : PresentationGeneratorRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : 'presentation from ${req.sourcePath}',
        websocketId : null,
        scheduledAt : req.scheduledAt,
        monopolize  : req.monopolize ? true : null,
      ) );

  // ─────────────────────────────────────────────
  // SweTeamRequest → POST /api/v2/submit   (was /api/swe-team/submit)
  // ─────────────────────────────────────────────

  /// Submits a software-engineering team job and returns the created job.
  Future<AgenticSubmitResponse> submitSweTeam( SweTeamRequest req ) =>
      _submit( 'submitSweTeam', SubmitRequest(
        command     : SweTeamRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : req.task,
        websocketId : req.websocketId,
        scheduledAt : req.scheduledAt,
        monopolize  : req.monopolize ? true : null,
      ) );

  // ─────────────────────────────────────────────
  // BugFixExpediterRequest → POST /api/v2/submit   (was /api/bug-fix-expediter/submit)
  // ─────────────────────────────────────────────

  /// Submits a job that fixes a dead job's bug and returns the created job.
  Future<AgenticSubmitResponse> submitBugFixExpediter( BugFixExpediterRequest req ) =>
      _submit( 'submitBugFixExpediter', SubmitRequest(
        command     : BugFixExpediterRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : 'fix dead job ${req.deadJobId}',
        websocketId : req.websocketId,
        scheduledAt : req.scheduledAt,
        monopolize  : req.monopolize ? true : null,
      ) );

  // ─────────────────────────────────────────────
  // TestSuiteRequest → POST /api/v2/submit   (was /api/test-suite/submit)
  // ─────────────────────────────────────────────

  /// Submits a test suite run and returns the created job.
  Future<AgenticSubmitResponse> submitTestSuite( TestSuiteRequest req ) =>
      _submit( 'submitTestSuite', SubmitRequest(
        command     : TestSuiteRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : 'run ${req.testTypes} tests',
        websocketId : req.websocketId,
        scheduledAt : req.scheduledAt,
        monopolize  : null,
      ) );

  // ─────────────────────────────────────────────
  // POST /api/test-fix-expediter/resume-from
  // ─────────────────────────────────────────────

  /// Resumes a test-fix-expediter job from a job id, plan file or description.
  ///
  /// Raises [AgenticApiException] when the request fails.
  Future<TfeResumeResponse> resumeTestFixExpediter( TfeResumeFromRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/test-fix-expediter/resume-from',
        data: req.toJson(),
      );
      return TfeResumeResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeTestFixExpediter failed' );
    }
  }

  // ─────────────────────────────────────────────
  // ResearchToPodcastRequest → POST /api/v2/submit   (was /api/deep-research-to-podcast/submit)
  // ─────────────────────────────────────────────

  /// Submits deep research chained into a podcast and returns the created job.
  Future<AgenticSubmitResponse> submitResearchToPodcast( ResearchToPodcastRequest req ) =>
      _submit( 'submitResearchToPodcast', SubmitRequest(
        command     : ResearchToPodcastRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : req.query,
        websocketId : null,
        scheduledAt : null,
        monopolize  : null,
      ) );

  // ─────────────────────────────────────────────
  // ResearchToPresentationRequest → POST /api/v2/submit   (was /api/deep-research-to-presentation/submit)
  // ─────────────────────────────────────────────

  /// Submits deep research chained into a presentation and returns the created job.
  Future<AgenticSubmitResponse> submitResearchToPresentation( ResearchToPresentationRequest req ) =>
      _submit( 'submitResearchToPresentation', SubmitRequest(
        command     : ResearchToPresentationRequest.submitCommand,
        args        : req.toSubmitArgs(),
        question    : req.query,
        websocketId : null,
        scheduledAt : null,
        monopolize  : null,
      ) );

  // ─────────────────────────────────────────────
  // The one v2 door the eight submits share
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> _submit( String label, SubmitRequest sr ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/v2/submit', data: sr.toJson() );
      return AgenticSubmitResponse.fromAsk( AskResponse.fromJson( res.data! ) );
    } on DioException catch ( e ) {
      throw _err( e, '$label failed' );
    }
  }

  // ─────────────────────────────────────────────
  // Error helper
  // ─────────────────────────────────────────────

  AgenticApiException _err( DioException e, String fallback ) {
    final code   = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? ( e.response!.data as Map )[ 'detail' ]?.toString()
        : null;
    return AgenticApiException( detail ?? e.message ?? fallback, statusCode: code );
  }
}
