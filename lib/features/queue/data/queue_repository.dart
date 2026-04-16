import 'package:dio/dio.dart';

import 'queue_models.dart';

/// Typed wrapper over the 14-endpoint Lupin CJ Flow queue API.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
class QueueRepository {
  final Dio _dio;
  const QueueRepository( this._dio );

  // ─────────────────────────────────────────────
  // POST /api/push
  // ─────────────────────────────────────────────

  Future<PushJobResponse> push( PushJobRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/push', data: req.toJson() );
      return PushJobResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'push failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/push-agentic
  // ─────────────────────────────────────────────

  Future<PushJobResponse> pushAgentic( PushAgenticRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/push-agentic', data: req.toJson() );
      return PushJobResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'push-agentic failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/get-queue/{queue_name}
  // ─────────────────────────────────────────────

  Future<QueueResponse> getQueue( String queueName ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/get-queue/$queueName' );
      return QueueResponse.fromJson( queueName, res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getQueue($queueName) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/jobs/{job_id}/cancel
  // ─────────────────────────────────────────────

  Future<void> cancelJob( String jobId ) async {
    try {
      await _dio.post<dynamic>( '/api/jobs/$jobId/cancel' );
    } on DioException catch ( e ) {
      throw _err( e, 'cancelJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/jobs/{job_id}/message
  // ─────────────────────────────────────────────

  Future<MessageDeliveredResponse> injectMessage(
    String jobId,
    String message, {
    String priority = 'normal',
  } ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/jobs/$jobId/message',
        data: { 'message': message, 'priority': priority },
      );
      return MessageDeliveredResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'injectMessage($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/job-history/{job_id}/retry
  // ─────────────────────────────────────────────

  Future<RetryJobResponse> retryJob( String jobId, String websocketId ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/job-history/$jobId/retry',
        data: { 'websocket_id': websocketId },
      );
      return RetryJobResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'retryJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/jobs/{id_hash}/resume-from-checkpoint
  // ─────────────────────────────────────────────

  Future<ResumeCheckpointResponse> resumeFromCheckpoint( String idHash ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/jobs/$idHash/resume-from-checkpoint' );
      return ResumeCheckpointResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeFromCheckpoint($idHash) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // PATCH /api/queue/todo/{job_id}/pause
  // ─────────────────────────────────────────────

  Future<void> pauseJob( String jobId ) async {
    try {
      await _dio.patch<dynamic>( '/api/queue/todo/$jobId/pause' );
    } on DioException catch ( e ) {
      throw _err( e, 'pauseJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // PATCH /api/queue/todo/{job_id}/resume
  // ─────────────────────────────────────────────

  Future<void> resumeJob( String jobId ) async {
    try {
      await _dio.patch<dynamic>( '/api/queue/todo/$jobId/resume' );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // DELETE /api/queue/{queue_name}/{job_id}
  // ─────────────────────────────────────────────

  Future<void> deleteJob( String queueName, String jobId ) async {
    try {
      await _dio.delete<dynamic>( '/api/queue/$queueName/$jobId' );
    } on DioException catch ( e ) {
      throw _err( e, 'deleteJob($queueName/$jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/job-history
  // ─────────────────────────────────────────────

  Future<JobHistoryPage> getJobHistory( {
    String? status,
    String? jobType,
    int     limit  = 20,
    int     offset = 0,
    int?    days,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/job-history',
        queryParameters: {
          if ( status  != null ) 'status'   : status,
          if ( jobType != null ) 'job_type' : jobType,
          'limit'  : limit,
          'offset' : offset,
          if ( days != null ) 'days' : days,
        },
      );
      return JobHistoryPage.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobHistory failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/job-history/{job_id}
  // ─────────────────────────────────────────────

  Future<JobHistoryEntry> getJobHistoryEntry( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/job-history/$jobId' );
      return JobHistoryEntry.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobHistoryEntry($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/reset-queues  (admin only)
  // ─────────────────────────────────────────────

  Future<Map<String, dynamic>> resetQueues() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/reset-queues' );
      return res.data!;
    } on DioException catch ( e ) {
      throw _err( e, 'resetQueues failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/get-job-interactions/{job_id}
  // ─────────────────────────────────────────────

  Future<JobInteractionsResponse> getJobInteractions( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/get-job-interactions/$jobId' );
      return JobInteractionsResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobInteractions($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // Error helper
  // ─────────────────────────────────────────────

  QueueApiException _err( DioException e, String fallback ) {
    final code   = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? ( e.response!.data as Map )[ 'detail' ]?.toString()
        : null;
    return QueueApiException( detail ?? e.message ?? fallback, statusCode: code );
  }
}
