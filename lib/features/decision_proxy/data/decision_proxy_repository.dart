import 'package:dio/dio.dart';

import 'decision_proxy_models.dart';

/// A failed decision-proxy request, carrying the server's message and HTTP status.
class DecisionProxyApiException implements Exception {
  /// The server's `detail` text, or a fallback describing the failed call.
  final String message;

  /// HTTP status code, or null when there was no response.
  final int?   statusCode;

  /// Creates an exception with [message] and an optional [statusCode].
  const DecisionProxyApiException( this.message, { this.statusCode } );
  @override
  String toString() => "DecisionProxyApiException($statusCode): $message";
}

// Percent-encodes one path segment so a value holding `/`, `@`, `+` or a space
// does not become extra path parameters.
String _enc( String s ) => Uri.encodeComponent( s );

/// Typed wrapper over the Lupin decision-proxy and trust API.
class DecisionProxyRepository {
  final Dio _dio;

  /// Creates a repository that sends its requests through [_dio].
  const DecisionProxyRepository( this._dio );

  /// Reads the trust mode from the server.
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
  Future<TrustModeStatus> getMode() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( "/api/proxy/mode" );
      return TrustModeStatus.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Get trust mode failed" );
    }
  }

  /// Changes the trust mode and returns the server's updated or queued answer.
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
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

  /// Lists the decisions awaiting ratification for [userEmail].
  ///
  /// [domain] and [category] narrow the list; [limit] caps it.
  /// Throws [DecisionProxyApiException] when the request fails.
  Future<PendingDecisionsResponse> pending(
    String userEmail, {
    String? domain,
    String? category,
    int     limit = 100,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/proxy/pending/${_enc( userEmail )}",
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

  /// Approves or rejects the decision [decisionId] for [userEmail].
  ///
  /// [feedback] is optional free text sent with the verdict.
  /// Throws [DecisionProxyApiException] when the request fails.
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

  /// Deletes the decision [decisionId] on behalf of [userEmail].
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
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

  /// Reads the per-domain trust states of [userEmail], optionally for one [domain].
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
  Future<TrustStateResponse> trustState(
    String userEmail, {
    String? domain,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/proxy/trust/${_enc( userEmail )}",
        queryParameters: { if ( domain != null ) "domain": domain },
      );
      return TrustStateResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch trust state failed" );
    }
  }

  /// Lists decisions in one [domain] and [category], capped at [limit].
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
  Future<DecisionsByCategoryResponse> decisionsByCategory(
    String domain,
    String category, {
    int limit = 50,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/proxy/decisions/${_enc( domain )}/${_enc( category )}",
        queryParameters: { "limit": limit },
      );
      return DecisionsByCategoryResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch decisions by category failed" );
    }
  }

  /// Reads the id of the current unacknowledged batch.
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
  Future<BatchIdResponse> batchId() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( "/api/proxy/batch-id" );
      return BatchIdResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch batch id failed" );
    }
  }

  /// Acknowledges the current batch; the server rotates to a new one.
  ///
  /// Throws [DecisionProxyApiException] when the request fails.
  Future<AcknowledgeResponse> acknowledge() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( "/api/proxy/acknowledge" );
      return AcknowledgeResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Acknowledge batch failed" );
    }
  }

  // Maps a failed request to an exception, preferring the server's `detail` text.
  DecisionProxyApiException _err( DioException e, String fallback ) {
    final sc  = e.response?.statusCode;
    final msg = e.response?.data is Map<String, dynamic>
        ? ( ( e.response!.data as Map )["detail"]?.toString() ?? fallback )
        : ( e.message ?? fallback );
    return DecisionProxyApiException( msg, statusCode: sc );
  }
}
