import 'package:dio/dio.dart';

import 'claude_code_models.dart';

/// Typed wrapper over `POST /api/claude-code/submit` — canonical Claude Code
/// job submission endpoint after the 2026-05-05 dispatch-cluster retirement.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
///
/// Retired endpoints: see <lupin>/src/rnd/v0.1.7/2026.05.05-claude-code-dispatch-retirement/01-plan.md
/// Mobile-side breadcrumbs: src/rnd/v0.1.6-migration/2026.04.15-{tier-3-queue-and-claude-code-plan,resync-mobile-with-lupin-api-v0.1.6}.md
/// Canonical successor: POST /api/claude-code/submit (this file)
class ClaudeCodeRepository {
  final Dio _dio;
  const ClaudeCodeRepository( this._dio );

  Future<ClaudeCodeSubmitResponse> submit( ClaudeCodeSubmitRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/api/claude-code/submit",
        data: req.toJson(),
      );
      return ClaudeCodeSubmitResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "submit failed" );
    }
  }

  ClaudeCodeApiException _err( DioException e, String fallback ) {
    final code   = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? ( e.response!.data as Map )[ "detail" ]?.toString()
        : null;
    return ClaudeCodeApiException( detail ?? e.message ?? fallback, statusCode: code );
  }
}
