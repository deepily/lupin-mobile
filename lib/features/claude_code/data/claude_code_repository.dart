import 'package:dio/dio.dart';

import 'claude_code_models.dart';

/// Typed wrapper over the Claude Code submit endpoint.
///
/// This is the only Claude Code endpoint the app calls. It uses the shared
/// Dio, whose auth interceptor adds the bearer token automatically.
class ClaudeCodeRepository {
  final Dio _dio;
  /// Creates the repository over [_dio].
  const ClaudeCodeRepository( this._dio );

  /// Posts [req] to `/api/claude-code/submit` and returns the server's reply.
  ///
  /// Raises:
  ///   - [ClaudeCodeApiException] when the request fails
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
