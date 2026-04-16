import 'package:dio/dio.dart';

import 'agentic_common_models.dart';
import 'bug_fix_expediter_models.dart';
import 'chained_models.dart';
import 'deep_research_models.dart';
import 'podcast_models.dart';
import 'presentation_models.dart';
import 'swe_team_models.dart';
import 'test_fix_expediter_models.dart';
import 'test_suite_models.dart';

/// Typed wrapper over all 10 agentic job endpoints.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
class AgenticRepository {
  final Dio _dio;
  const AgenticRepository( this._dio );

  // ─────────────────────────────────────────────
  // POST /api/deep-research/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitDeepResearch( DeepResearchRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/deep-research/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitDeepResearch failed' );
    }
  }

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
  // POST /api/podcast-generator/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitPodcast( PodcastGeneratorRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/podcast-generator/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitPodcast failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/presentation-generator/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitPresentation( PresentationGeneratorRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/presentation-generator/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitPresentation failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/swe-team/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitSweTeam( SweTeamRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/swe-team/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitSweTeam failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/bug-fix-expediter/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitBugFixExpediter( BugFixExpediterRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/bug-fix-expediter/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitBugFixExpediter failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/test-suite/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitTestSuite( TestSuiteRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/test-suite/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitTestSuite failed' );
    }
  }

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
  // POST /api/deep-research-to-podcast/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitResearchToPodcast( ResearchToPodcastRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/deep-research-to-podcast/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitResearchToPodcast failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/deep-research-to-presentation/submit
  // ─────────────────────────────────────────────

  Future<AgenticSubmitResponse> submitResearchToPresentation(
      ResearchToPresentationRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/deep-research-to-presentation/submit',
        data: req.toJson(),
      );
      return AgenticSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submitResearchToPresentation failed' );
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
