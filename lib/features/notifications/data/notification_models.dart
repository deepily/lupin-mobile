/// Data models for the Lupin notifications API (17 endpoints).
///
/// Field names match backend JSON exactly (snake_case) per
/// `cosa/rest/routers/notifications.py` and
/// `cosa/rest/notification_fifo_queue.NotificationItem.to_dict()`.
library;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

T? _as<T>( dynamic v ) => v is T ? v : null;

/// A single notification item — matches `NotificationItem.to_dict()`.
/// Returned by `GET /api/notifications/{user_id}` and `/next`, and by
/// `conversation` / `conversation-by-date` endpoints.
class NotificationItem {
  final String   id;
  final String?  idHash;
  final String   message;
  final String?  title;
  final String   type;       // task | progress | alert | custom | user_initiated_message | session_topic
  final String   priority;   // low | medium | high | urgent
  final String?  source;     // claude_code, etc.
  final String?  userId;
  final DateTime timestamp;
  final String?  timeDisplay;
  final bool     played;
  final int      playCount;
  final DateTime? lastPlayed;
  final bool     responseRequested;
  final String?  responseType;     // yes_no | open_ended | multiple_choice | open_ended_batch
  final String?  responseDefault;
  final Map<String, dynamic>? responseOptions;
  final int?     timeoutSeconds;
  final String?  senderId;
  final String?  abstractText;     // "abstract" is reserved-ish in some IDEs
  final bool     suppressDing;
  final String?  jobId;
  final String?  queueName;        // run | todo | done
  final String?  progressGroupId;  // pr-{8hex}-{N}
  final Map<String, dynamic>? predictionHint;
  final bool     displayQualifierWidget;
  final String?  sessionName;
  final Map<String, dynamic> raw;

  const NotificationItem( {
    required this.id,
    this.idHash,
    required this.message,
    this.title,
    required this.type,
    required this.priority,
    this.source,
    this.userId,
    required this.timestamp,
    this.timeDisplay,
    required this.played,
    required this.playCount,
    this.lastPlayed,
    required this.responseRequested,
    this.responseType,
    this.responseDefault,
    this.responseOptions,
    this.timeoutSeconds,
    this.senderId,
    this.abstractText,
    required this.suppressDing,
    this.jobId,
    this.queueName,
    this.progressGroupId,
    this.predictionHint,
    required this.displayQualifierWidget,
    this.sessionName,
    this.raw = const {},
  } );

  factory NotificationItem.fromJson( Map<String, dynamic> json ) {
    return NotificationItem(
      id                      : json["id"].toString(),
      idHash                  : _as<String>( json["id_hash"] ),
      message                 : ( json["message"] ?? "" ).toString(),
      title                   : _as<String>( json["title"] ),
      type                    : ( json["type"] ?? "custom" ).toString(),
      priority                : ( json["priority"] ?? "low" ).toString(),
      source                  : _as<String>( json["source"] ),
      userId                  : json["user_id"]?.toString(),
      timestamp               : _parseDt( json["timestamp"] ) ?? DateTime.now(),
      timeDisplay             : _as<String>( json["time_display"] ),
      played                  : json["played"] == true,
      playCount               : ( json["play_count"] as num? )?.toInt() ?? 0,
      lastPlayed              : _parseDt( json["last_played"] ),
      responseRequested       : json["response_requested"] == true,
      responseType            : _as<String>( json["response_type"] ),
      responseDefault         : _as<String>( json["response_default"] ),
      responseOptions         : _as<Map<String, dynamic>>( json["response_options"] ),
      timeoutSeconds          : ( json["timeout_seconds"] as num? )?.toInt(),
      senderId                : _as<String>( json["sender_id"] ),
      abstractText            : _as<String>( json["abstract"] ),
      suppressDing            : json["suppress_ding"] == true,
      jobId                   : _as<String>( json["job_id"] ),
      queueName               : _as<String>( json["queue_name"] ),
      progressGroupId         : _as<String>( json["progress_group_id"] ),
      predictionHint          : _as<Map<String, dynamic>>( json["prediction_hint"] ),
      displayQualifierWidget  : json["display_qualifier_widget"] == true,
      sessionName             : _as<String>( json["session_name"] ),
      raw                     : Map<String, dynamic>.from( json ),
    );
  }
}

/// Returned by `GET /api/notifications/conversation/{sender_id}/{user_email}` —
/// a flatter shape than NotificationItem with extra delivery/state fields.
class ConversationMessage {
  final String   id;
  final String?  senderId;
  final String   message;
  final String?  title;
  final String   type;
  final String   priority;
  final String?  state;       // pending | delivered | responded | expired
  final bool     isHidden;
  final String?  abstractText;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? respondedAt;
  final bool     responseRequested;
  final String?  responseType;
  final dynamic  responseValue;
  final String?  jobId;
  final String?  progressGroupId;
  final DateTime timestamp;
  final String?  timeDisplay;
  final Map<String, dynamic> raw;

  const ConversationMessage( {
    required this.id,
    this.senderId,
    required this.message,
    this.title,
    required this.type,
    required this.priority,
    this.state,
    required this.isHidden,
    this.abstractText,
    this.createdAt,
    this.deliveredAt,
    this.respondedAt,
    required this.responseRequested,
    this.responseType,
    this.responseValue,
    this.jobId,
    this.progressGroupId,
    required this.timestamp,
    this.timeDisplay,
    this.raw = const {},
  } );

  factory ConversationMessage.fromJson( Map<String, dynamic> json ) {
    return ConversationMessage(
      id                : json["id"].toString(),
      senderId          : _as<String>( json["sender_id"] ),
      message           : ( json["message"] ?? "" ).toString(),
      title             : _as<String>( json["title"] ),
      type              : ( json["type"] ?? "custom" ).toString(),
      priority          : ( json["priority"] ?? "low" ).toString(),
      state             : _as<String>( json["state"] ),
      isHidden          : json["is_hidden"] == true,
      abstractText      : _as<String>( json["abstract"] ),
      createdAt         : _parseDt( json["created_at"] ),
      deliveredAt       : _parseDt( json["delivered_at"] ),
      respondedAt       : _parseDt( json["responded_at"] ),
      responseRequested : json["response_requested"] == true,
      responseType      : _as<String>( json["response_type"] ),
      responseValue     : json["response_value"],
      jobId             : _as<String>( json["job_id"] ),
      progressGroupId   : _as<String>( json["progress_group_id"] ),
      timestamp         : _parseDt( json["timestamp"] ) ?? DateTime.now(),
      timeDisplay       : _as<String>( json["time_display"] ),
      raw               : Map<String, dynamic>.from( json ),
    );
  }
}

/// `GET /api/notifications/{user_id}` envelope.
class NotificationListResponse {
  final String status;
  final String userId;
  final int    notificationCount;
  final bool   includePlayed;
  final int    limit;
  final List<NotificationItem> notifications;
  final DateTime timestamp;

  const NotificationListResponse( {
    required this.status,
    required this.userId,
    required this.notificationCount,
    required this.includePlayed,
    required this.limit,
    required this.notifications,
    required this.timestamp,
  } );

  factory NotificationListResponse.fromJson( Map<String, dynamic> json ) {
    final raw = ( json["notifications"] as List? ) ?? const [];
    return NotificationListResponse(
      status            : ( json["status"] ?? "" ).toString(),
      userId            : ( json["user_id"] ?? "" ).toString(),
      notificationCount : ( json["notification_count"] as num? )?.toInt() ?? raw.length,
      includePlayed     : json["include_played"] == true,
      limit             : ( json["limit"] as num? )?.toInt() ?? 0,
      notifications     : raw
          .whereType<Map>()
          .map( ( m ) => NotificationItem.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList(),
      timestamp         : _parseDt( json["timestamp"] ) ?? DateTime.now(),
    );
  }
}

/// `GET /api/notifications/{user_id}/next` envelope.
class NextNotificationResponse {
  final String status;            // "found" | "none_available"
  final String userId;
  final NotificationItem? notification;
  final DateTime timestamp;

  const NextNotificationResponse( {
    required this.status,
    required this.userId,
    required this.notification,
    required this.timestamp,
  } );

  factory NextNotificationResponse.fromJson( Map<String, dynamic> json ) {
    final notif = json["notification"];
    return NextNotificationResponse(
      status       : ( json["status"] ?? "" ).toString(),
      userId       : ( json["user_id"] ?? "" ).toString(),
      notification : notif is Map
          ? NotificationItem.fromJson( Map<String, dynamic>.from( notif ) )
          : null,
      timestamp    : _parseDt( json["timestamp"] ) ?? DateTime.now(),
    );
  }
}

/// Generic ack envelope used by mark-played, single-delete, etc.
class StatusAckResponse {
  final String   status;
  final String?  message;
  final String?  notificationId;
  final DateTime? timestamp;
  final Map<String, dynamic> raw;

  const StatusAckResponse( {
    required this.status,
    this.message,
    this.notificationId,
    this.timestamp,
    this.raw = const {},
  } );

  factory StatusAckResponse.fromJson( Map<String, dynamic> json ) {
    return StatusAckResponse(
      status         : ( json["status"] ?? "" ).toString(),
      message        : _as<String>( json["message"] ),
      notificationId : _as<String>( json["notification_id"] ),
      timestamp      : _parseDt( json["timestamp"] ),
      raw            : Map<String, dynamic>.from( json ),
    );
  }
}

/// `DELETE /api/notifications/bulk/{user_email}` response.
class BulkDeleteResponse {
  final String  status;
  final String  userEmail;
  final int?    hoursFilter;
  final bool    excludeOwnJobs;
  final int     deletedCount;

  const BulkDeleteResponse( {
    required this.status,
    required this.userEmail,
    this.hoursFilter,
    required this.excludeOwnJobs,
    required this.deletedCount,
  } );

  factory BulkDeleteResponse.fromJson( Map<String, dynamic> json ) {
    return BulkDeleteResponse(
      status         : ( json["status"] ?? "" ).toString(),
      userEmail      : ( json["user_email"] ?? "" ).toString(),
      hoursFilter    : ( json["hours_filter"] as num? )?.toInt(),
      excludeOwnJobs : json["exclude_own_jobs"] == true,
      deletedCount   : ( json["deleted_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// Matches each entry from `GET /api/notifications/senders/{user_email}`
/// AND the `senders-visible` variant (which adds `new_count`).
class SenderSummary {
  final String   senderId;
  final DateTime? lastActivity;
  final int      count;
  final int?     newCount;       // only present in senders-visible

  const SenderSummary( {
    required this.senderId,
    this.lastActivity,
    required this.count,
    this.newCount,
  } );

  factory SenderSummary.fromJson( Map<String, dynamic> json ) {
    return SenderSummary(
      senderId     : ( json["sender_id"] ?? "" ).toString(),
      lastActivity : _parseDt( json["last_activity"] ),
      count        : ( json["count"] as num? )?.toInt() ?? 0,
      newCount     : ( json["new_count"] as num? )?.toInt(),
    );
  }
}

/// `GET /api/notifications/sender-dates/...` entry.
class DateSummary {
  final String date;     // YYYY-MM-DD
  final int    count;
  final int    newCount;

  const DateSummary( {
    required this.date,
    required this.count,
    required this.newCount,
  } );

  factory DateSummary.fromJson( Map<String, dynamic> json ) {
    return DateSummary(
      date     : ( json["date"] ?? "" ).toString(),
      count    : ( json["count"] as num? )?.toInt() ?? 0,
      newCount : ( json["new_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// `DELETE /api/notifications/conversation/...` response.
class ConversationDeleteResponse {
  final String status;
  final String senderId;
  final String userEmail;
  final int    deletedCount;

  const ConversationDeleteResponse( {
    required this.status,
    required this.senderId,
    required this.userEmail,
    required this.deletedCount,
  } );

  factory ConversationDeleteResponse.fromJson( Map<String, dynamic> json ) {
    return ConversationDeleteResponse(
      status       : ( json["status"] ?? "" ).toString(),
      senderId     : ( json["sender_id"] ?? "" ).toString(),
      userEmail    : ( json["user_email"] ?? "" ).toString(),
      deletedCount : ( json["deleted_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// `DELETE /api/notifications/date/...` response.
class DateDeleteResponse {
  final String status;
  final String senderId;
  final String userEmail;
  final String date;
  final int    hiddenCount;

  const DateDeleteResponse( {
    required this.status,
    required this.senderId,
    required this.userEmail,
    required this.date,
    required this.hiddenCount,
  } );

  factory DateDeleteResponse.fromJson( Map<String, dynamic> json ) {
    return DateDeleteResponse(
      status      : ( json["status"] ?? "" ).toString(),
      senderId    : ( json["sender_id"] ?? "" ).toString(),
      userEmail   : ( json["user_email"] ?? "" ).toString(),
      date        : ( json["date"] ?? "" ).toString(),
      hiddenCount : ( json["hidden_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// `GET /api/notifications/active-conversation/...` response.
class ActiveConversationResponse {
  final String? activeSenderId;
  final String  userEmail;

  const ActiveConversationResponse( {
    this.activeSenderId,
    required this.userEmail,
  } );

  factory ActiveConversationResponse.fromJson( Map<String, dynamic> json ) {
    return ActiveConversationResponse(
      activeSenderId : _as<String>( json["active_sender_id"] ),
      userEmail      : ( json["user_email"] ?? "" ).toString(),
    );
  }
}

/// `GET /api/notifications/project-sessions/...` entry.
class ProjectSession {
  final String   sessionId;
  final String   senderId;
  final DateTime? lastActivity;
  final int      count;
  final bool     isActive;

  const ProjectSession( {
    required this.sessionId,
    required this.senderId,
    this.lastActivity,
    required this.count,
    required this.isActive,
  } );

  factory ProjectSession.fromJson( Map<String, dynamic> json ) {
    return ProjectSession(
      sessionId    : ( json["session_id"] ?? "" ).toString(),
      senderId     : ( json["sender_id"] ?? "" ).toString(),
      lastActivity : _parseDt( json["last_activity"] ),
      count        : ( json["count"] as num? )?.toInt() ?? 0,
      isActive     : json["is_active"] == true,
    );
  }
}

/// `POST /api/notifications/generate-gist` response.
class GistResponse {
  final String gist;
  const GistResponse( { required this.gist } );

  factory GistResponse.fromJson( Map<String, dynamic> json ) =>
      GistResponse( gist: ( json["gist"] ?? "" ).toString() );
}

/// `POST /api/notify/response` request payload.
class NotificationResponsePayload {
  final String  notificationId;
  final dynamic responseValue;

  const NotificationResponsePayload( {
    required this.notificationId,
    required this.responseValue,
  } );

  Map<String, dynamic> toJson() => {
    "notification_id": notificationId,
    "response_value": responseValue,
  };
}

/// `POST /api/notify/response` response.
class NotificationResponseAck {
  final String   status;
  final String?  message;
  final String   notificationId;
  final dynamic  responseValue;
  final DateTime? timestamp;
  final String?  timeDisplay;
  final String?  dateDisplay;

  const NotificationResponseAck( {
    required this.status,
    this.message,
    required this.notificationId,
    this.responseValue,
    this.timestamp,
    this.timeDisplay,
    this.dateDisplay,
  } );

  factory NotificationResponseAck.fromJson( Map<String, dynamic> json ) {
    return NotificationResponseAck(
      status         : ( json["status"] ?? "" ).toString(),
      message        : _as<String>( json["message"] ),
      notificationId : ( json["notification_id"] ?? "" ).toString(),
      responseValue  : json["response_value"],
      timestamp      : _parseDt( json["timestamp"] ),
      timeDisplay    : _as<String>( json["time_display"] ),
      dateDisplay    : _as<String>( json["date_display"] ),
    );
  }
}

/// `POST /api/notify` (fire-and-forget) response.
class NotifyDispatchResponse {
  final String  status;          // queued | user_not_available
  final String? message;
  final String  targetUser;
  final String? targetSystemId;
  final int     connectionCount;

  const NotifyDispatchResponse( {
    required this.status,
    this.message,
    required this.targetUser,
    this.targetSystemId,
    required this.connectionCount,
  } );

  factory NotifyDispatchResponse.fromJson( Map<String, dynamic> json ) {
    return NotifyDispatchResponse(
      status          : ( json["status"] ?? "" ).toString(),
      message         : _as<String>( json["message"] ),
      targetUser      : ( json["target_user"] ?? "" ).toString(),
      targetSystemId  : _as<String>( json["target_system_id"] ),
      connectionCount : ( json["connection_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// Outbound `POST /api/notify` query-parameter bundle.
/// All params are query-string per backend spec.
class NotifyRequest {
  final String  message;
  final String  targetUser;
  final String? type;
  final String? priority;
  final bool?   responseRequested;
  final String? responseType;
  final int?    timeoutSeconds;
  final String? responseDefault;
  final String? title;
  final String? senderId;
  final String? responseOptions;   // JSON-encoded string per backend
  final String? abstractText;
  final String? jobId;
  final String? queueName;
  final bool?   suppressDing;
  final String? progressGroupId;
  final String? predictionHintOverride;
  final bool?   displayQualifierWidget;
  final String? sessionName;
  final String? idempotencyKey;

  const NotifyRequest( {
    required this.message,
    required this.targetUser,
    this.type,
    this.priority,
    this.responseRequested,
    this.responseType,
    this.timeoutSeconds,
    this.responseDefault,
    this.title,
    this.senderId,
    this.responseOptions,
    this.abstractText,
    this.jobId,
    this.queueName,
    this.suppressDing,
    this.progressGroupId,
    this.predictionHintOverride,
    this.displayQualifierWidget,
    this.sessionName,
    this.idempotencyKey,
  } );

  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{
      "message"     : message,
      "target_user" : targetUser,
    };
    void put( String k, Object? v ) { if ( v != null ) q[ k ] = v; }
    put( "type",                         type );
    put( "priority",                     priority );
    put( "response_requested",           responseRequested );
    put( "response_type",                responseType );
    put( "timeout_seconds",              timeoutSeconds );
    put( "response_default",             responseDefault );
    put( "title",                        title );
    put( "sender_id",                    senderId );
    put( "response_options",             responseOptions );
    put( "abstract",                     abstractText );
    put( "job_id",                       jobId );
    put( "queue_name",                   queueName );
    put( "suppress_ding",                suppressDing );
    put( "progress_group_id",            progressGroupId );
    put( "prediction_hint_override",     predictionHintOverride );
    put( "display_qualifier_widget",     displayQualifierWidget );
    put( "session_name",                 sessionName );
    put( "idempotency_key",              idempotencyKey );
    return q;
  }
}

/// `POST /api/notifications/generate-gist` request body.
class GistRequest {
  final List<String> messages;
  final List<String> abstracts;
  const GistRequest( { required this.messages, required this.abstracts } );

  Map<String, dynamic> toJson() => {
    "messages"  : messages,
    "abstracts" : abstracts,
  };
}
