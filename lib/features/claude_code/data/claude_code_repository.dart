import 'package:dio/dio.dart';

import 'claude_code_models.dart';

/// Submits Claude Code jobs through the server's `/api/v2/submit` door.
///
/// It uses the shared Dio, whose auth interceptor adds the bearer token.
/// The older `/api/claude-code/submit` route is retired and answers 410.
class ClaudeCodeRepository {
  /// The server path every submission goes to.
  static const String path = "/api/v2/submit";

  final Dio _dio;
  /// Creates the repository over [_dio].
  const ClaudeCodeRepository( this._dio );

  /// Queues [req] as a Claude Code job and returns the created job.
  ///
  /// Ensures:
  ///   - a reply with a job id and status `waiting` or `done` is a success
  ///
  /// Raises:
  ///   - [ClaudeCodeApiException] when the request fails
  ///   - [ClaudeCodeApiException] when the server answers 200 but created no job
  Future<ClaudeCodeSubmitResponse> submit( ClaudeCodeSubmitRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: req.toSubmitRequest().toJson(),
      );
      return ClaudeCodeSubmitResponse.fromAsk( res.data! );
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
