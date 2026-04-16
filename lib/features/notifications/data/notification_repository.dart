import 'package:dio/dio.dart';

import 'notification_models.dart';

class NotificationApiException implements Exception {
  final String message;
  final int?   statusCode;
  const NotificationApiException( this.message, { this.statusCode } );
  @override
  String toString() => "NotificationApiException($statusCode): $message";
}

/// Typed wrapper over the 17-endpoint Lupin notifications API.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
class NotificationRepository {
  final Dio _dio;
  const NotificationRepository( this._dio );

  // ---------------------------------------------------------------------
  // POST /api/notify  (fire-and-forget; SSE mode requires a different call)
  // ---------------------------------------------------------------------
  Future<NotifyDispatchResponse> notify( NotifyRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/api/notify",
        queryParameters: req.toQuery(),
      );
      return NotifyDispatchResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Notify dispatch failed" );
    }
  }

  // ---------------------------------------------------------------------
  // POST /api/notify/response
  // ---------------------------------------------------------------------
  Future<NotificationResponseAck> respond( NotificationResponsePayload p ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/api/notify/response",
        data: p.toJson(),
      );
      return NotificationResponseAck.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Notify response failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/{user_id}
  // ---------------------------------------------------------------------
  Future<NotificationListResponse> list(
    String userId, {
    bool includePlayed = false,
    int? limit,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/$userId",
        queryParameters: {
          "include_played": includePlayed,
          if ( limit != null ) "limit": limit,
        },
      );
      return NotificationListResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "List notifications failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/{user_id}/next
  // ---------------------------------------------------------------------
  Future<NextNotificationResponse> next( String userId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/$userId/next",
      );
      return NextNotificationResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch next notification failed" );
    }
  }

  // ---------------------------------------------------------------------
  // POST /api/notifications/{notification_id}/played
  // ---------------------------------------------------------------------
  Future<StatusAckResponse> markPlayed( String notificationId ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/api/notifications/$notificationId/played",
      );
      return StatusAckResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Mark played failed" );
    }
  }

  // ---------------------------------------------------------------------
  // DELETE /api/notifications/{notification_id}
  // ---------------------------------------------------------------------
  Future<StatusAckResponse> deleteOne( String notificationId ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/$notificationId",
      );
      return StatusAckResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Delete notification failed" );
    }
  }

  // ---------------------------------------------------------------------
  // DELETE /api/notifications/bulk/{user_email}
  // ---------------------------------------------------------------------
  Future<BulkDeleteResponse> bulkDelete(
    String userEmail, {
    int?  hours,
    bool  excludeOwnJobs = false,
  } ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/bulk/$userEmail",
        queryParameters: {
          if ( hours != null ) "hours": hours,
          "exclude_own_jobs": excludeOwnJobs,
        },
      );
      return BulkDeleteResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Bulk delete failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/senders/{user_email}
  // ---------------------------------------------------------------------
  Future<List<SenderSummary>> senders(
    String userEmail, {
    int? hours,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/senders/$userEmail",
        queryParameters: { if ( hours != null ) "hours": hours },
      );
      return ( res.data ?? const [] )
          .whereType<Map>()
          .map( ( m ) => SenderSummary.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "List senders failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/senders-visible/{user_email}
  // ---------------------------------------------------------------------
  Future<List<SenderSummary>> sendersVisible(
    String userEmail, {
    int?  hours,
    bool  includeHidden  = false,
    bool  excludeOwnJobs = false,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/senders-visible/$userEmail",
        queryParameters: {
          if ( hours != null ) "hours": hours,
          "include_hidden"  : includeHidden,
          "exclude_own_jobs": excludeOwnJobs,
        },
      );
      return ( res.data ?? const [] )
          .whereType<Map>()
          .map( ( m ) => SenderSummary.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "List visible senders failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/conversation/{sender_id}/{user_email}
  // ---------------------------------------------------------------------
  Future<List<ConversationMessage>> conversation(
    String senderId,
    String userEmail, {
    int?    hours,
    String? anchor,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/conversation/$senderId/$userEmail",
        queryParameters: {
          if ( hours  != null ) "hours" : hours,
          if ( anchor != null ) "anchor": anchor,
        },
      );
      return ( res.data ?? const [] )
          .whereType<Map>()
          .map( ( m ) => ConversationMessage.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "Fetch conversation failed" );
    }
  }

  // ---------------------------------------------------------------------
  // DELETE /api/notifications/conversation/{sender_id}/{user_email}
  // ---------------------------------------------------------------------
  Future<ConversationDeleteResponse> deleteConversation(
    String senderId,
    String userEmail,
  ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/conversation/$senderId/$userEmail",
      );
      return ConversationDeleteResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Delete conversation failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/conversation-by-date/{sender_id}/{user_email}
  // ---------------------------------------------------------------------
  Future<Map<String, List<NotificationItem>>> conversationByDate(
    String senderId,
    String userEmail, {
    int?  hours,
    String? anchor,
    bool  includeHidden = false,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/conversation-by-date/$senderId/$userEmail",
        queryParameters: {
          if ( hours  != null ) "hours" : hours,
          if ( anchor != null ) "anchor": anchor,
          "include_hidden": includeHidden,
        },
      );
      final data = res.data ?? {};
      final out  = <String, List<NotificationItem>>{};
      data.forEach( ( date, items ) {
        if ( items is List ) {
          out[ date ] = items
              .whereType<Map>()
              .map( ( m ) => NotificationItem.fromJson( Map<String, dynamic>.from( m ) ) )
              .toList();
        }
      } );
      return out;
    } on DioException catch ( e ) {
      throw _err( e, "Fetch conversation-by-date failed" );
    }
  }

  // ---------------------------------------------------------------------
  // DELETE /api/notifications/date/{sender_id}/{user_email}/{date_string}
  // ---------------------------------------------------------------------
  Future<DateDeleteResponse> deleteDate(
    String senderId,
    String userEmail,
    String dateString,
  ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/date/$senderId/$userEmail/$dateString",
      );
      return DateDeleteResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Delete date failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/sender-dates/{sender_id}/{user_email}
  // ---------------------------------------------------------------------
  Future<List<DateSummary>> senderDates(
    String senderId,
    String userEmail, {
    bool includeHidden = false,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/sender-dates/$senderId/$userEmail",
        queryParameters: { "include_hidden": includeHidden },
      );
      return ( res.data ?? const [] )
          .whereType<Map>()
          .map( ( m ) => DateSummary.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "Fetch sender dates failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/active-conversation/{user_email}
  // ---------------------------------------------------------------------
  Future<ActiveConversationResponse> activeConversation( String userEmail ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/active-conversation/$userEmail",
      );
      return ActiveConversationResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch active conversation failed" );
    }
  }

  // ---------------------------------------------------------------------
  // GET /api/notifications/project-sessions/{project}/{user_email}
  // ---------------------------------------------------------------------
  Future<List<ProjectSession>> projectSessions(
    String project,
    String userEmail,
  ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/project-sessions/$project/$userEmail",
      );
      return ( res.data ?? const [] )
          .whereType<Map>()
          .map( ( m ) => ProjectSession.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "Fetch project sessions failed" );
    }
  }

  // ---------------------------------------------------------------------
  // POST /api/notifications/generate-gist
  // ---------------------------------------------------------------------
  Future<GistResponse> generateGist( GistRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/api/notifications/generate-gist",
        data: req.toJson(),
      );
      return GistResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Generate gist failed" );
    }
  }

  NotificationApiException _err( DioException e, String fallback ) {
    final sc  = e.response?.statusCode;
    final msg = e.response?.data is Map<String, dynamic>
        ? ( ( e.response!.data as Map )["detail"]?.toString() ?? fallback )
        : ( e.message ?? fallback );
    return NotificationApiException( msg, statusCode: sc );
  }
}
