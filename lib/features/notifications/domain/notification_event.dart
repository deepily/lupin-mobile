import 'package:equatable/equatable.dart';

import '../data/notification_models.dart';

/// Base class of every input event of the notification bloc.
abstract class NotificationEvent extends Equatable {
  /// Creates an event.
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

/// Loads the multi-sender inbox for a user.
class NotificationsLoadInbox extends NotificationEvent {
  /// Account whose inbox is loaded.
  final String userEmail;

  /// Only senders active in the last this-many hours; null means no limit.
  final int?   hours;

  /// Whether senders the user has hidden are included.
  final bool   includeHidden;

  /// Whether senders that are the user's own jobs are left out.
  final bool   excludeOwnJobs;

  /// Creates a load-inbox request.
  const NotificationsLoadInbox( {
    required this.userEmail,
    this.hours,
    this.includeHidden  = false,
    this.excludeOwnJobs = false,
  } );

  @override
  List<Object?> get props => [ userEmail, hours, includeHidden, excludeOwnJobs ];
}

/// Opens one sender's conversation thread.
class NotificationsLoadConversation extends NotificationEvent {
  /// Sender whose thread is opened.
  final String senderId;

  /// Account that owns the thread.
  final String userEmail;

  /// Only messages from the last this-many hours; null means no limit.
  final int?   hours;

  /// Whether hidden messages are included; the repository call does not use it.
  final bool   includeHidden;

  /// Creates a load-conversation request.
  const NotificationsLoadConversation( {
    required this.senderId,
    required this.userEmail,
    this.hours,
    this.includeHidden = false,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, hours, includeHidden ];
}

/// Marks one notification as played and refreshes the current view.
class NotificationsMarkPlayed extends NotificationEvent {
  /// Notification to mark.
  final String notificationId;

  /// Creates a mark-played request for [notificationId].
  const NotificationsMarkPlayed( this.notificationId );

  @override
  List<Object?> get props => [ notificationId ];
}

/// Sends the user's answer to a notification that asked a question.
class NotificationsRespond extends NotificationEvent {
  /// Notification being answered.
  final String  notificationId;

  /// Answer the user chose or typed.
  final dynamic responseValue;

  /// Creates a response to [notificationId].
  const NotificationsRespond( {
    required this.notificationId,
    required this.responseValue,
  } );

  @override
  List<Object?> get props => [ notificationId, responseValue ];
}

/// Deletes a user's notifications in bulk, then reloads the inbox.
class NotificationsBulkDelete extends NotificationEvent {
  /// Account whose notifications are deleted.
  final String userEmail;

  /// Only notifications from the last this-many hours; null means all.
  final int?   hours;

  /// Whether notifications from the user's own jobs are kept.
  final bool   excludeOwnJobs;

  /// Creates a bulk-delete request.
  const NotificationsBulkDelete( {
    required this.userEmail,
    this.hours,
    this.excludeOwnJobs = false,
  } );

  @override
  List<Object?> get props => [ userEmail, hours, excludeOwnJobs ];
}

/// Deletes one sender's whole conversation, then reloads the inbox.
class NotificationsDeleteConversation extends NotificationEvent {
  /// Sender whose conversation is deleted.
  final String senderId;

  /// Account that owns the conversation.
  final String userEmail;

  /// Creates a delete-conversation request.
  const NotificationsDeleteConversation( {
    required this.senderId,
    required this.userEmail,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail ];
}

/// Tells the bloc that a queue update arrived over the WebSocket.
///
/// The backend update normally carries the full [notification]. The bloc then
/// routes it by type, plays audio for ordinary notifications, and refreshes
/// the current view.
class NotificationsExternalUpdate extends NotificationEvent {
  /// Payload of the update; null when the update carried none.
  final NotificationItem? notification;

  /// Creates an update event, with [notification] when the wire message had one.
  const NotificationsExternalUpdate( { this.notification } );

  @override
  List<Object?> get props => [ notification?.id ];
}

/// Requests an LLM summary of the conversation currently on screen.
///
/// Requires:
///   - the bloc state is a [NotificationsConversationLoaded] with messages
///
/// Ensures:
///   - the messages are read from that state, so the UI passes nothing
class NotificationsGenerateGistRequested extends NotificationEvent {
  /// Creates a gist request.
  const NotificationsGenerateGistRequested();
}

/// Lists the dates, with per-date counts, of one sender's conversation.
class NotificationsLoadSenderDates extends NotificationEvent {
  /// Sender whose dates are listed.
  final String senderId;

  /// Account that owns the conversation.
  final String userEmail;

  /// Whether hidden notifications are counted.
  final bool   includeHidden;

  /// Creates a load-dates request.
  const NotificationsLoadSenderDates( {
    required this.senderId,
    required this.userEmail,
    this.includeHidden = false,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, includeHidden ];
}

/// Loads one sender's conversation grouped by date, keyed YYYY-MM-DD.
class NotificationsLoadConversationByDate extends NotificationEvent {
  /// Sender whose conversation is loaded.
  final String  senderId;

  /// Account that owns the conversation.
  final String  userEmail;

  /// Only notifications from the last this-many hours; null means no limit.
  final int?    hours;

  /// Server-side anchor point for the time window; null means none.
  final String? anchor;

  /// Whether hidden notifications are included.
  final bool    includeHidden;

  /// Creates a load-by-date request.
  const NotificationsLoadConversationByDate( {
    required this.senderId,
    required this.userEmail,
    this.hours,
    this.anchor,
    this.includeHidden = false,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, hours, anchor, includeHidden ];
}

/// A voice persona was allocated to the session of [senderId].
///
/// The server bridge owns the allocation. The bloc mirrors the persona into
/// its state for header display only; speech reads the persona off each
/// notification instead. The event comes from a `voice_persona_assigned`
/// WebSocket notification, or directly from tests.
class NotificationsVoicePersonaAssigned extends NotificationEvent {
  /// Session the persona belongs to.
  final String       senderId;

  /// Persona allocated to that session.
  final VoicePersona persona;

  /// Creates an assignment of [persona] to [senderId].
  const NotificationsVoicePersonaAssigned( {
    required this.senderId,
    required this.persona,
  } );

  @override
  List<Object?> get props => [ senderId, persona.voiceId ];
}

/// The persona of [senderId] was released when its server session ended.
///
/// Ensures:
///   - the entry for [senderId] leaves the persona map
///   - a sender with no persona is a no-op and emits nothing
class NotificationsVoicePersonaReleased extends NotificationEvent {
  /// Session whose persona was released.
  final String  senderId;

  /// Name of the released persona; informational, the bloc removes by [senderId].
  final String? personaName;

  /// Creates a release for [senderId].
  const NotificationsVoicePersonaReleased( {
    required this.senderId,
    this.personaName,
  } );

  @override
  List<Object?> get props => [ senderId, personaName ];
}

/// The speakerphone state of the session [senderId] changed.
///
/// Carries only the on/off flag, so the resulting record has no displaced
/// fields. The WebSocket path reads those from the raw payload instead.
class NotificationsSpeakerphoneChanged extends NotificationEvent {
  /// Session whose speakerphone changed.
  final String senderId;

  /// Whether the speakerphone is now on.
  final bool   on;

  /// Creates a speakerphone change for [senderId].
  const NotificationsSpeakerphoneChanged( {
    required this.senderId,
    required this.on,
  } );

  @override
  List<Object?> get props => [ senderId, on ];
}
