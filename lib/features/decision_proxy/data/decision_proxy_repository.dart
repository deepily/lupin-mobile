import 'package:dio/dio.dart';

import 'decision_proxy_models.dart';

class DecisionProxyApiException implements Exception {
  final String message;
  final int?   statusCode;
  const DecisionProxyApiException( this.message, { this.statusCode } );
  @override
  String toString() => "DecisionProxyApiException($statusCode): $message";
}

/// Typed wrapper over the 9-endpoint Lupin decision-proxy / trust API.
class DecisionProxyRepository {
  final Dio _dio;
  const DecisionProxyRepository( this._dio );

  // ---------------------------------------------------------------------
  // GET /api/proxy/mode
  // ---------------------------------------------------------------------
  Future<TrustModeStatus> getMode() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( "/api/proxy/mode" );
      return TrustModeStatus.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Get trust mode failed" );
    }
  }

  // ---------------------------------------------------------------------
  // PUT /api/proxy/mode
  // ---------------------------------------------------------------------
  Future<TrustModeUpdateResponse> setMode( TrustModeUpdateRequest req ) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        "/api/proxy/mode",
        data: req.toJson(),
      );
      return TrustModeUpdateResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Update trust mode failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/proxy/pending/{user_email}
  // ---------------------------------------------------------------------
  Future<PendingDecisionsResponse> pending(
    String userEmail, {
    String? domain,
    String? category,
    int     limit = 100,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/proxy/pending/$userEmail",
        queryParameters: {
          if ( domain   != null ) "domain"  : domain,
          if ( category != null ) "category": category,
          "limit": limit,
        },
      );
      return PendingDecisionsResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch pending decisions failed" );
    }
  }

  // ---------------------------------------------------------------------
  // POST /api/proxy/ratify/{decision_id}
  // ---------------------------------------------------------------------
  Future<RatifyResponse> ratify(
    String decisionId, {
    required String userEmail,
    required bool   approved,
    String? feedback,
  } ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/api/proxy/ratify/$decisionId",
        queryParameters: {
          "user_email": userEmail,
          "approved"  : approved,
          if ( feedback != null ) "feedback": feedback,
        },
      );
      return RatifyResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Ratify decision failed" );
    }
  }

  // ---------------------------------------------------------------------
  // DELETE /api/proxy/decision/{decision_id}
  // ---------------------------------------------------------------------
  Future<DeleteDecisionResponse> deleteDecision(
    String decisionId, {
    required String userEmail,
  } ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/proxy/decision/$decisionId",
        queryParameters: { "user_email": userEmail },
      );
      return DeleteDecisionResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Delete decision failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/proxy/trust/{user_email}
  // ---------------------------------------------------------------------
  Future<TrustStateResponse> trustState(
    String userEmail, {
    String? domain,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/proxy/trust/$userEmail",
        queryParameters: { if ( domain != null ) "domain": domain },
      );
      return TrustStateResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch trust state failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/proxy/decisions/{domain}/{category}
  // ---------------------------------------------------------------------
  Future<DecisionsByCategoryResponse> decisionsByCategory(
    String domain,
    String category, {
    int limit = 50,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/proxy/decisions/$domain/$category",
        queryParameters: { "limit": limit },
      );
      return DecisionsByCategoryResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch decisions by category failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/proxy/batch-id
  // ---------------------------------------------------------------------
  Future<BatchIdResponse> batchId() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( "/api/proxy/batch-id" );
      return BatchIdResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch batch id failed" );
    }
  }

  // ---------------------------------------------------------------------
  // POST /api/proxy/acknowledge
  // ---------------------------------------------------------------------
  Future<AcknowledgeResponse> acknowledge() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( "/api/proxy/acknowledge" );
      return AcknowledgeResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Acknowledge batch failed" );
    }
  }

  DecisionProxyApiException _err( DioException e, String fallback ) {
    final sc  = e.response?.statusCode;
    final msg = e.response?.data is Map<String, dynamic>
        ? ( ( e.response!.data as Map )["detail"]?.toString() ?? fallback )
        : ( e.message ?? fallback );
    return DecisionProxyApiException( msg, statusCode: sc );
  }
}
