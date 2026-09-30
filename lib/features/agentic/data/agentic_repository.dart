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

/// Typed wrapper over the agentic job doors.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
///
/// v2 cutover wave 2 (2026-08-21, server sha 799e43d0): the eight submit-shaped
/// doors POST `/api/v2/submit` — `{command, args, question?, websocket_id?,
/// scheduled_at?, monopolize?}` — and read the synchronous `AskResponse`
/// (`status == 'waiting'` + `job_id` is the success). The per-door request
/// models stay the UI's input; `toSubmitArgs()` produces the contract keys.
/// `/api/test-fix-expediter/resume-from` stays v1 (a checkpoint-built job the
/// submit body cannot express) and `/api/deep-research/report` is a READ.
class AgenticRepository {
  final Dio _dio;
  const AgenticRepository( this._dio );

  // ─────────────────────────────────────────────
  // DeepResearchRequest → POST /api/v2/submit   (was /api/deep-research/submit)
  // ─────────────────────────────────────────────

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
