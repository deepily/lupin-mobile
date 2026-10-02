import 'package:dio/dio.dart';

import 'notification_models.dart';

/// Failure of a notifications API call, carrying the server's message.
class NotificationApiException implements Exception {
  /// Server `detail` text, or a fallback describing the failed call.
  final String message;

  /// HTTP status, or null when the request got no response.
  final int?   statusCode;

  /// Builds an exception from a [message] and optional [statusCode].
  const NotificationApiException( this.message, { this.statusCode } );
  @override
  String toString() => "NotificationApiException($statusCode): $message";
}

// Percent-encodes one path segment so `/`, `@`, `+` and spaces do not split it
// into extra path parameters. "a/b" becomes "a%2Fb".
String _enc( String s ) => Uri.encodeComponent( s );

/// Typed wrapper over the Lupin notifications API.
///
/// Uses the shared Dio, whose auth interceptor adds the bearer token.
/// Every method throws [NotificationApiException] on a failed request.
class NotificationRepository {
  final Dio _dio;

  /// Creates a repository that sends requests through [_dio].
  const NotificationRepository( this._dio );

  /// Dispatches a notification through the server and does not wait for a reply.
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

  /// Sends the user's answer to a notification that asked a question.
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

  /// Lists a user's notifications, optionally including ones already played.
  Future<NotificationListResponse> list(
    String userId, {
    bool includePlayed = false,
    int? limit,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/${_enc( userId )}",
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

  /// Fetches the next unplayed notification for a user.
  Future<NextNotificationResponse> next( String userId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/${_enc( userId )}/next",
      );
      return NextNotificationResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch next notification failed" );
    }
  }

  /// Marks one notification as played.
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

  /// Deletes one notification.
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

  /// Deletes a user's notifications in bulk, optionally limited to the last [hours].
  Future<BulkDeleteResponse> bulkDelete(
    String userEmail, {
    int?  hours,
    bool  excludeOwnJobs = false,
  } ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/bulk/${_enc( userEmail )}",
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

  /// Lists every sender who has notified the user.
  Future<List<SenderSummary>> senders(
    String userEmail, {
    int? hours,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/senders/${_enc( userEmail )}",
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

  /// Lists senders for the inbox, hiding hidden ones unless [includeHidden] is set.
  Future<List<SenderSummary>> sendersVisible(
    String userEmail, {
    int?  hours,
    bool  includeHidden  = false,
    bool  excludeOwnJobs = false,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/senders-visible/${_enc( userEmail )}",
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

  /// Fetches the messages one sender has exchanged with the user.
  Future<List<ConversationMessage>> conversation(
    String senderId,
    String userEmail, {
    int?    hours,
    String? anchor,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/conversation/${_enc( senderId )}/${_enc( userEmail )}",
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

  /// Deletes the whole conversation with one sender.
  Future<ConversationDeleteResponse> deleteConversation(
    String senderId,
    String userEmail,
  ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/conversation/${_enc( senderId )}/${_enc( userEmail )}",
      );
      return ConversationDeleteResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Delete conversation failed" );
    }
  }

  /// Fetches one sender's conversation grouped by date, keyed by YYYY-MM-DD.
  Future<Map<String, List<NotificationItem>>> conversationByDate(
    String senderId,
    String userEmail, {
    int?  hours,
    String? anchor,
    bool  includeHidden = false,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/conversation-by-date/${_enc( senderId )}/${_enc( userEmail )}",
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

  /// Deletes one sender's notifications for a single date.
  Future<DateDeleteResponse> deleteDate(
    String senderId,
    String userEmail,
    String dateString,
  ) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        "/api/notifications/date/${_enc( senderId )}/${_enc( userEmail )}/${_enc( dateString )}",
      );
      return DateDeleteResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Delete date failed" );
    }
  }

  /// Lists the dates on which one sender has notifications, with counts.
  Future<List<DateSummary>> senderDates(
    String senderId,
    String userEmail, {
    bool includeHidden = false,
  } ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/sender-dates/${_enc( senderId )}/${_enc( userEmail )}",
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

  /// Fetches the conversation the user is currently active in.
  Future<ActiveConversationResponse> activeConversation( String userEmail ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/notifications/active-conversation/${_enc( userEmail )}",
      );
      return ActiveConversationResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Fetch active conversation failed" );
    }
  }

  /// Lists the sessions of one project for the user.
  Future<List<ProjectSession>> projectSessions(
    String project,
    String userEmail,
  ) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        "/api/notifications/project-sessions/${_enc( project )}/${_enc( userEmail )}",
      );
      return ( res.data ?? const [] )
          .whereType<Map>()
          .map( ( m ) => ProjectSession.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "Fetch project sessions failed" );
    }
  }

  /// Asks the server for a summary of a set of messages.
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

  /// Lists every live seat of the authenticated user, from the session bridges.
  ///
  /// A seat appears here even if it has never sent the user a notification,
  /// unlike [sendersVisible]. The server wraps the list as `{"sessions": []}`.
  Future<List<ActiveSession>> activeSessions() async {
    try {
      final res  = await _dio.get<Map<String, dynamic>>( "/api/commons/active-sessions" );
      final list = res.data?["sessions"];
      if ( list is! List ) return const [];
      return list
          .whereType<Map>()
          .map( ( m ) => ActiveSession.fromJson( Map<String, dynamic>.from( m ) ) )
          .where( ( s ) => s.sessionId.isNotEmpty )
          .toList();
    } on DioException catch ( e ) {
      throw _err( e, "List active sessions failed" );
    }
  }

  // Maps a failed request to an exception, preferring the server's `detail`.
  NotificationApiException _err( DioException e, String fallback ) {
    final sc  = e.response?.statusCode;
    final msg = e.response?.data is Map<String, dynamic>
        ? ( ( e.response!.data as Map )["detail"]?.toString() ?? fallback )
        : ( e.message ?? fallback );
    return NotificationApiException( msg, statusCode: sc );
  }
}
