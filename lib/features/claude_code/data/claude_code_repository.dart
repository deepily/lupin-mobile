import 'package:dio/dio.dart';

import 'claude_code_models.dart';

/// Typed wrapper over the 6-endpoint Lupin Claude Code session API.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
class ClaudeCodeRepository {
  final Dio _dio;
  const ClaudeCodeRepository( this._dio );

  // ─────────────────────────────────────────────
  // POST /api/claude-code/dispatch
  // ─────────────────────────────────────────────

  Future<ClaudeCodeSession> dispatch( ClaudeCodeDispatchRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/claude-code/dispatch',
        data: req.toJson(),
      );
      return ClaudeCodeSession.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'dispatch failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/claude-code/{task_id}/status
  // ─────────────────────────────────────────────

  Future<ClaudeCodeSession> getStatus( String taskId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/claude-code/$taskId/status' );
      return ClaudeCodeSession.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getStatus($taskId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/claude-code/{task_id}/inject
  // ─────────────────────────────────────────────

  Future<ClaudeCodeInjectResponse> inject( String taskId, String message ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/claude-code/$taskId/inject',
        data: { 'message': message },
      );
      return ClaudeCodeInjectResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'inject($taskId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/claude-code/{task_id}/interrupt
  // ─────────────────────────────────────────────

  Future<void> interrupt( String taskId ) async {
    try {
      await _dio.post<dynamic>( '/api/claude-code/$taskId/interrupt' );
    } on DioException catch ( e ) {
      throw _err( e, 'interrupt($taskId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/claude-code/{task_id}/end
  // ─────────────────────────────────────────────

  Future<void> endSession( String taskId ) async {
    try {
      await _dio.post<dynamic>( '/api/claude-code/$taskId/end' );
    } on DioException catch ( e ) {
      throw _err( e, 'endSession($taskId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/claude-code/queue/submit  (BOUNDED via CJ Flow)
  // ─────────────────────────────────────────────

  Future<ClaudeCodeQueueResponse> queueSubmit( ClaudeCodeQueueRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/claude-code/queue/submit',
        data: req.toJson(),
      );
      return ClaudeCodeQueueResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'queueSubmit failed' );
    }
  }

  // ─────────────────────────────────────────────
  // Error helper
  // ─────────────────────────────────────────────

  ClaudeCodeApiException _err( DioException e, String fallback ) {
    final code   = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? ( e.response!.data as Map )[ 'detail' ]?.toString()
        : null;
    return ClaudeCodeApiException( detail ?? e.message ?? fallback, statusCode: code );
  }
}
