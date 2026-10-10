/// Data models for the Lupin notifications API.
///
/// Dart field names are camelCase forms of the snake_case keys the backend sends.
library;

import 'package:equatable/equatable.dart';

import 'voice_persona.dart';

export 'voice_persona.dart' show VoicePersona;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

T? _as<T>( dynamic v ) => v is T ? v : null;

/// Speakerphone state of one session, kept for diagnostics only.
///
/// `NotificationBloc` stores one per `senderId` and updates it on `speakerphone_changed`.
/// No UI reads it, and the bloc never acts on `displaced` or `displacedBy`.
/// Value equality lets tests compare record maps directly.
class SpeakerphoneRecord extends Equatable {
  /// Whether the session's speakerphone is on.
  final bool    on;
  /// Wire value of `displaced`, stored verbatim and never acted on.
  final String? displaced;
  /// Wire value of `displaced_by`, stored verbatim and never acted on.
  final String? displacedBy;

  /// Builds a [SpeakerphoneRecord] from already-parsed fields.
  const SpeakerphoneRecord( {
    required this.on,
    this.displaced,
    this.displacedBy,
  } );

  /// Fields that define value equality.
  @override
  List<Object?> get props => [ on, displaced, displacedBy ];
}

/// One notification as returned by the item, next and conversation endpoints.
class NotificationItem {
  /// Server-assigned identifier.
  final String   id;
  /// Short hash form of the identifier.
  final String?  idHash;
  /// Text spoken or shown for the notification.
  final String   message;
  /// Optional heading.
  final String?  title;
  /// Kind of item: task, progress, alert, custom, user_initiated_message or session_topic.
  final String   type;
  /// Urgency: low, medium, high or urgent.
  final String   priority;
  /// Originating system, such as `claude_code`.
  final String?  source;
  /// Recipient user id.
  final String?  userId;
  /// When the server created the item.
  final DateTime timestamp;
  /// Server-formatted time label.
  final String?  timeDisplay;
  /// Whether the item has been played.
  final bool     played;
  /// How many times the item has been played.
  final int      playCount;
  /// When the item was last played.
  final DateTime? lastPlayed;
  /// Whether the sender is waiting for an answer.
  final bool     responseRequested;
  /// Answer format: yes_no, open_ended, multiple_choice or open_ended_batch.
  final String?  responseType;
  /// Value the server substitutes when the ask times out.
  final String?  responseDefault;
  /// Choices offered for a multiple-choice or batch ask.
  final Map<String, dynamic>? responseOptions;
  /// Seconds the sender waits before using the default answer.
  final int?     timeoutSeconds;
  /// Sending session key.
  final String?  senderId;
  /// Longer detail shown in the card, from the wire field `abstract`.
  final String?  abstractText;
  /// Whether the chime is skipped.
  final bool     suppressDing;
  /// Job the item belongs to.
  final String?  jobId;
  /// Queue the job is in: run, todo or done.
  final String?  queueName;
  /// Group key tying progress items together.
  final String?  progressGroupId;
  /// Server hint about the likely answer.
  final Map<String, dynamic>? predictionHint;
  /// Whether the UI shows the qualifier widget.
  final bool     displayQualifierWidget;
  /// Display name of the sending session.
  final String?  sessionName;
  /// Persona the server stamped on the item, or null when none was stamped.
  final VoicePersona? voicePersona;
  /// The unparsed JSON map this object came from.
  final Map<String, dynamic> raw;

  /// Builds a [NotificationItem] from already-parsed fields.
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
    this.voicePersona,
    this.raw = const {},
  } );

  /// Parses a [NotificationItem] from decoded JSON, tolerating missing fields.
  factory NotificationItem.fromJson( Map<String, dynamic> json ) {
    final personaRaw = json["voice_persona"];
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
      voicePersona            : personaRaw is Map
          ? VoicePersona.fromJson( Map<String, dynamic>.from( personaRaw ) )
          : null,
      raw                     : Map<String, dynamic>.from( json ),
    );
  }
}

/// One message from `GET /api/notifications/conversation/{sender_id}/{user_email}`.
///
/// Flatter than [NotificationItem], with extra delivery and state fields.
class ConversationMessage {
  /// Server-assigned identifier.
  final String   id;
  /// Sending session key.
  final String?  senderId;
  /// Message text.
  final String   message;
  /// Optional heading.
  final String?  title;
  /// Item kind.
  final String   type;
  /// Urgency level.
  final String   priority;
  /// Delivery state: pending, delivered, responded or expired.
  final String?  state;
  /// Whether the user has hidden the message.
  final bool     isHidden;
  /// Longer detail, from the wire field `abstract`.
  final String?  abstractText;
  /// When the message was created.
  final DateTime? createdAt;
  /// When the message was delivered.
  final DateTime? deliveredAt;
  /// When the user responded.
  final DateTime? respondedAt;
  /// Whether the sender is waiting for an answer.
  final bool     responseRequested;
  /// Answer format requested.
  final String?  responseType;
  /// The user's answer, when one exists.
  final dynamic  responseValue;
  /// Job the message belongs to.
  final String?  jobId;
  /// Group key for progress items.
  final String?  progressGroupId;
  /// When the message occurred.
  final DateTime timestamp;
  /// Server-formatted time label.
  final String?  timeDisplay;
  /// The unparsed JSON map this object came from.
  final Map<String, dynamic> raw;

  /// Builds a [ConversationMessage] from already-parsed fields.
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

  /// Parses a [ConversationMessage] from decoded JSON, tolerating missing fields.
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

/// Envelope returned by `GET /api/notifications/{user_id}`.
class NotificationListResponse {
  /// Status string returned by the server.
  final String status;
  /// Recipient user id.
  final String userId;
  /// Number of notifications the server reports.
  final int    notificationCount;
  /// Whether played items were included.
  final bool   includePlayed;
  /// Maximum items requested.
  final int    limit;
  /// The returned items.
  final List<NotificationItem> notifications;
  /// When the server built the response.
  final DateTime timestamp;

  /// Builds a [NotificationListResponse] from already-parsed fields.
  const NotificationListResponse( {
    required this.status,
    required this.userId,
    required this.notificationCount,
    required this.includePlayed,
    required this.limit,
    required this.notifications,
    required this.timestamp,
  } );

  /// Parses a [NotificationListResponse] from decoded JSON, tolerating missing fields.
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

/// Envelope returned by `GET /api/notifications/{user_id}/next`.
class NextNotificationResponse {
  /// Lookup result: found or none_available.
  final String status;
  /// Recipient user id.
  final String userId;
  /// The next item, or null when none is available.
  final NotificationItem? notification;
  /// When the server built the response.
  final DateTime timestamp;

  /// Builds a [NextNotificationResponse] from already-parsed fields.
  const NextNotificationResponse( {
    required this.status,
    required this.userId,
    required this.notification,
    required this.timestamp,
  } );

  /// Parses a [NextNotificationResponse] from decoded JSON, tolerating missing fields.
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

/// Generic acknowledgement used by mark-played and single-delete calls.
class StatusAckResponse {
  /// Status string returned by the server.
  final String   status;
  /// Optional detail from the server.
  final String?  message;
  /// Id of the notification concerned.
  final String?  notificationId;
  /// When the server built the response.
  final DateTime? timestamp;
  /// The unparsed JSON map this object came from.
  final Map<String, dynamic> raw;

  /// Builds a [StatusAckResponse] from already-parsed fields.
  const StatusAckResponse( {
    required this.status,
    this.message,
    this.notificationId,
    this.timestamp,
    this.raw = const {},
  } );

  /// Parses a [StatusAckResponse] from decoded JSON, tolerating missing fields.
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

/// Response from `DELETE /api/notifications/bulk/{user_email}`.
class BulkDeleteResponse {
  /// Status string returned by the server.
  final String  status;
  /// Email of the user the request concerned.
  final String  userEmail;
  /// Age filter in hours, when one was applied.
  final int?    hoursFilter;
  /// Whether the user's own jobs were kept.
  final bool    excludeOwnJobs;
  /// Number of items deleted.
  final int     deletedCount;

  /// Builds a [BulkDeleteResponse] from already-parsed fields.
  const BulkDeleteResponse( {
    required this.status,
    required this.userEmail,
    this.hoursFilter,
    required this.excludeOwnJobs,
    required this.deletedCount,
  } );

  /// Parses a [BulkDeleteResponse] from decoded JSON, tolerating missing fields.
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

/// One entry from the senders endpoint, or its senders-visible variant.
///
/// Only the senders-visible variant carries `new_count` and the persona fields.
class SenderSummary {
  /// Sending session key.
  final String   senderId;
  /// Time of the most recent activity.
  final DateTime? lastActivity;
  /// Number of items from the sender.
  final int      count;
  /// Unplayed count, present only in the senders-visible variant.
  final int?     newCount;
  /// Persona stamped from the session bridge for live sessions, senders-visible variant only.
  final VoicePersona? voicePersona;
  /// Persona of the spawning manager, senders-visible variant only.
  final VoicePersona? managerPersona;

  /// Builds a [SenderSummary] from already-parsed fields.
  const SenderSummary( {
    required this.senderId,
    this.lastActivity,
    required this.count,
    this.newCount,
    this.voicePersona,
    this.managerPersona,
  } );

  static VoicePersona? _persona( dynamic v ) =>
      v is Map ? VoicePersona.fromJson( Map<String, dynamic>.from( v ) ) : null;

  /// Parses a [SenderSummary] from decoded JSON, tolerating missing fields.
  factory SenderSummary.fromJson( Map<String, dynamic> json ) {
    return SenderSummary(
      senderId       : ( json["sender_id"] ?? "" ).toString(),
      lastActivity   : _parseDt( json["last_activity"] ),
      count          : ( json["count"] as num? )?.toInt() ?? 0,
      newCount       : ( json["new_count"] as num? )?.toInt(),
      voicePersona   : _persona( json["voice_persona"] ),
      managerPersona : _persona( json["manager_persona"] ),
    );
  }
}

/// One live Claude Code seat from `GET /api/commons/active-sessions`.
///
/// Lists every seat the session bridges know, including seats that never notified.
/// The mux broadcast card reads the same endpoint for its recipient chips.
/// A null `senderId` means an older server, so the seat is listed but not addressable.
/// Before the server projected the sender id, the roster carried only the session id.
class ActiveSession {
  /// Bridge session id.
  final String        sessionId;
  /// Rail key in `email#hash` form, or null from an older server.
  final String?       senderId;
  /// Persona assembled from the flat persona fields, or null when unnamed.
  final VoicePersona? persona;
  /// When the bridge last saw the session.
  final DateTime?     lastSeen;
  /// Whether the session's speakerphone is on.
  final bool          speakerphoneOn;

  /// Builds a [ActiveSession] from already-parsed fields.
  const ActiveSession( {
    required this.sessionId,
    this.senderId,
    this.persona,
    this.lastSeen,
    this.speakerphoneOn = false,
  } );

  /// Parses a seat, building the persona from the flat `persona_*` fields.
  ///
  /// This endpoint does not nest a `voice_persona` block.
  /// A seat with no persona name gets a null persona, not an empty badge.
  factory ActiveSession.fromJson( Map<String, dynamic> json ) {
    final name = _as<String>( json["persona_name"] );
    return ActiveSession(
      sessionId      : ( json["session_id"] ?? "" ).toString(),
      senderId       : _as<String>( json["sender_id"] ),
      persona        : ( name == null || name.isEmpty ) ? null : VoicePersona(
        name  : name,
        icon  : _as<String>( json["persona_icon"]  ),
        color : _as<String>( json["persona_color"] ),
      ),
      lastSeen       : _parseDt( json["last_seen_iso"] ),
      speakerphoneOn : json["speakerphone_on"] == true,
    );
  }
}

/// One entry from `GET /api/notifications/sender-dates/...`.
class DateSummary {
  /// Calendar date in YYYY-MM-DD form.
  final String date;
  /// Number of items on the date.
  final int    count;
  /// Number of unplayed items on the date.
  final int    newCount;

  /// Builds a [DateSummary] from already-parsed fields.
  const DateSummary( {
    required this.date,
    required this.count,
    required this.newCount,
  } );

  /// Parses a [DateSummary] from decoded JSON, tolerating missing fields.
  factory DateSummary.fromJson( Map<String, dynamic> json ) {
    return DateSummary(
      date     : ( json["date"] ?? "" ).toString(),
      count    : ( json["count"] as num? )?.toInt() ?? 0,
      newCount : ( json["new_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// Response from `DELETE /api/notifications/conversation/...`.
class ConversationDeleteResponse {
  /// Status string returned by the server.
  final String status;
  /// Sending session key.
  final String senderId;
  /// Email of the user the request concerned.
  final String userEmail;
  /// Number of items deleted.
  final int    deletedCount;

  /// Builds a [ConversationDeleteResponse] from already-parsed fields.
  const ConversationDeleteResponse( {
    required this.status,
    required this.senderId,
    required this.userEmail,
    required this.deletedCount,
  } );

  /// Parses a [ConversationDeleteResponse] from decoded JSON, tolerating missing fields.
  factory ConversationDeleteResponse.fromJson( Map<String, dynamic> json ) {
    return ConversationDeleteResponse(
      status       : ( json["status"] ?? "" ).toString(),
      senderId     : ( json["sender_id"] ?? "" ).toString(),
      userEmail    : ( json["user_email"] ?? "" ).toString(),
      deletedCount : ( json["deleted_count"] as num? )?.toInt() ?? 0,
    );
  }
}

/// Response from `DELETE /api/notifications/date/...`.
class DateDeleteResponse {
  /// Status string returned by the server.
  final String status;
  /// Sending session key.
  final String senderId;
  /// Email of the user the request concerned.
  final String userEmail;
  /// Date whose items were hidden.
  final String date;
  /// Number of items hidden.
  final int    hiddenCount;

  /// Builds a [DateDeleteResponse] from already-parsed fields.
  const DateDeleteResponse( {
    required this.status,
    required this.senderId,
    required this.userEmail,
    required this.date,
    required this.hiddenCount,
  } );

  /// Parses a [DateDeleteResponse] from decoded JSON, tolerating missing fields.
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

/// Response from `GET /api/notifications/active-conversation/...`.
class ActiveConversationResponse {
  /// Sender id of the active conversation, if any.
  final String? activeSenderId;
  /// Email of the user the request concerned.
  final String  userEmail;

  /// Builds a [ActiveConversationResponse] from already-parsed fields.
  const ActiveConversationResponse( {
    this.activeSenderId,
    required this.userEmail,
  } );

  /// Parses a [ActiveConversationResponse] from decoded JSON, tolerating missing fields.
  factory ActiveConversationResponse.fromJson( Map<String, dynamic> json ) {
    return ActiveConversationResponse(
      activeSenderId : _as<String>( json["active_sender_id"] ),
      userEmail      : ( json["user_email"] ?? "" ).toString(),
    );
  }
}

/// One entry from `GET /api/notifications/project-sessions/...`.
class ProjectSession {
  /// Bridge session id.
  final String   sessionId;
  /// Sending session key.
  final String   senderId;
  /// Time of the most recent activity.
  final DateTime? lastActivity;
  /// Number of items.
  final int      count;
  /// Whether the session is currently active.
  final bool     isActive;

  /// Builds a [ProjectSession] from already-parsed fields.
  const ProjectSession( {
    required this.sessionId,
    required this.senderId,
    this.lastActivity,
    required this.count,
    required this.isActive,
  } );

  /// Parses a [ProjectSession] from decoded JSON, tolerating missing fields.
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

/// Response from `POST /api/notifications/generate-gist`.
class GistResponse {
  /// Generated summary text.
  final String gist;
  /// Builds a [GistResponse] from the summary text.
  const GistResponse( { required this.gist } );

  /// Parses a [GistResponse] from decoded JSON, tolerating missing fields.
  factory GistResponse.fromJson( Map<String, dynamic> json ) =>
      GistResponse( gist: ( json["gist"] ?? "" ).toString() );
}

/// Request payload for `POST /api/notify/response`.
class NotificationResponsePayload {
  /// Id of the notification being answered.
  final String  notificationId;
  /// The answer being submitted.
  final dynamic responseValue;

  /// Builds a [NotificationResponsePayload] from already-parsed fields.
  const NotificationResponsePayload( {
    required this.notificationId,
    required this.responseValue,
  } );

  /// Serializes to the request JSON.
  Map<String, dynamic> toJson() => {
    "notification_id": notificationId,
    "response_value": responseValue,
  };
}

/// Response from `POST /api/notify/response`.
class NotificationResponseAck {
  /// Status string returned by the server.
  final String   status;
  /// Optional detail from the server.
  final String?  message;
  /// Id of the notification concerned.
  final String   notificationId;
  /// The answer the server recorded.
  final dynamic  responseValue;
  /// When the server recorded the answer.
  final DateTime? timestamp;
  /// Server-formatted time label.
  final String?  timeDisplay;
  /// Server-formatted date label.
  final String?  dateDisplay;

  /// Builds a [NotificationResponseAck] from already-parsed fields.
  const NotificationResponseAck( {
    required this.status,
    this.message,
    required this.notificationId,
    this.responseValue,
    this.timestamp,
    this.timeDisplay,
    this.dateDisplay,
  } );

  /// Parses a [NotificationResponseAck] from decoded JSON, tolerating missing fields.
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

/// Response from the fire-and-forget `POST /api/notify`.
class NotifyDispatchResponse {
  /// Dispatch result: queued or user_not_available.
  final String  status;
  /// Optional detail from the server.
  final String? message;
  /// User the notification is addressed to.
  final String  targetUser;
  /// System the notification is routed to.
  final String? targetSystemId;
  /// Number of live connections reached.
  final int     connectionCount;

  /// Builds a [NotifyDispatchResponse] from already-parsed fields.
  const NotifyDispatchResponse( {
    required this.status,
    this.message,
    required this.targetUser,
    this.targetSystemId,
    required this.connectionCount,
  } );

  /// Parses a [NotifyDispatchResponse] from decoded JSON, tolerating missing fields.
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

/// Query-parameter bundle for the outbound `POST /api/notify`.
///
/// The backend reads every parameter from the query string.
class NotifyRequest {
  /// Text to deliver.
  final String  message;
  /// User the notification is addressed to.
  final String  targetUser;
  /// Item kind.
  final String? type;
  /// Message direction, `human_to_ai` for a user message to a session.
  final String? direction;
  /// Urgency level.
  final String? priority;
  /// Whether to wait for an answer.
  final bool?   responseRequested;
  /// Answer format requested.
  final String? responseType;
  /// Seconds to wait before using the default answer.
  final int?    timeoutSeconds;
  /// Default answer used on timeout.
  final String? responseDefault;
  /// Optional heading.
  final String? title;
  /// Sending session key.
  final String? senderId;
  /// Answer choices as a JSON-encoded string.
  final String? responseOptions;
  /// Longer detail, sent as `abstract`.
  final String? abstractText;
  /// Job the item belongs to.
  final String? jobId;
  /// Queue the job is in.
  final String? queueName;
  /// Whether to skip the chime.
  final bool?   suppressDing;
  /// Group key for progress items.
  final String? progressGroupId;
  /// Overrides the server's prediction hint.
  final String? predictionHintOverride;
  /// Whether the UI shows the qualifier widget.
  final bool?   displayQualifierWidget;
  /// Display name of the sending session.
  final String? sessionName;
  /// Key that lets the server drop duplicate submissions.
  final String? idempotencyKey;

  /// Builds a [NotifyRequest] from already-parsed fields.
  const NotifyRequest( {
    required this.message,
    required this.targetUser,
    this.type,
    this.direction,
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

  /// Builds the query map, omitting every null field.
  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{
      "message"     : message,
      "target_user" : targetUser,
    };
    void put( String k, Object? v ) { if ( v != null ) q[ k ] = v; }
    put( "type",                         type );
    put( "direction",                    direction );
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

/// Request body for `POST /api/notifications/generate-gist`.
class GistRequest {
  /// Message texts to summarize.
  final List<String> messages;
  /// Abstract texts matching `messages`.
  final List<String> abstracts;
  /// Builds a [GistRequest] from parallel message and abstract lists.
  const GistRequest( { required this.messages, required this.abstracts } );

  /// Serializes to the request JSON.
  Map<String, dynamic> toJson() => {
    "messages"  : messages,
    "abstracts" : abstracts,
  };
}
