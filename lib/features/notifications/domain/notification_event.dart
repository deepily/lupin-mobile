import 'package:equatable/equatable.dart';

import '../data/notification_models.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

/// Load the multi-sender inbox for the given user.
class NotificationsLoadInbox extends NotificationEvent {
  final String userEmail;
  final int?   hours;
  final bool   includeHidden;
  final bool   excludeOwnJobs;

  const NotificationsLoadInbox( {
    required this.userEmail,
    this.hours,
    this.includeHidden  = false,
    this.excludeOwnJobs = false,
  } );

  @override
  List<Object?> get props => [ userEmail, hours, includeHidden, excludeOwnJobs ];
}

/// Open a single sender's conversation thread.
class NotificationsLoadConversation extends NotificationEvent {
  final String senderId;
  final String userEmail;
  final int?   hours;
  final bool   includeHidden;

  const NotificationsLoadConversation( {
    required this.senderId,
    required this.userEmail,
    this.hours,
    this.includeHidden = false,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, hours, includeHidden ];
}

class NotificationsMarkPlayed extends NotificationEvent {
  final String notificationId;
  const NotificationsMarkPlayed( this.notificationId );

  @override
  List<Object?> get props => [ notificationId ];
}

class NotificationsRespond extends NotificationEvent {
  final String  notificationId;
  final dynamic responseValue;

  const NotificationsRespond( {
    required this.notificationId,
    required this.responseValue,
  } );

  @override
  List<Object?> get props => [ notificationId, responseValue ];
}

class NotificationsBulkDelete extends NotificationEvent {
  final String userEmail;
  final int?   hours;
  final bool   excludeOwnJobs;

  const NotificationsBulkDelete( {
    required this.userEmail,
    this.hours,
    this.excludeOwnJobs = false,
  } );

  @override
  List<Object?> get props => [ userEmail, hours, excludeOwnJobs ];
}

class NotificationsDeleteConversation extends NotificationEvent {
  final String senderId;
  final String userEmail;

  const NotificationsDeleteConversation( {
    required this.senderId,
    required this.userEmail,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail ];
}

/// Used by the WebSocket bridge to nudge a refresh when a queue update
/// event lands on the wire. When the event carries a full notification
/// payload (the common case — backend `notification_queue_update` always
/// includes the NotificationItem), the [notification] field is populated
/// and the bloc dispatches audio on top of the standard refresh path.
class NotificationsExternalUpdate extends NotificationEvent {
  final NotificationItem? notification;
  const NotificationsExternalUpdate( { this.notification } );

  @override
  List<Object?> get props => [ notification?.id ];
}

/// Request a LLM-generated gist/summary of the currently-loaded conversation.
/// Only valid while a [NotificationsConversationLoaded] state holds messages;
/// the bloc pulls messages straight from that state so the UI doesn't have to
/// pass them in.
class NotificationsGenerateGistRequested extends NotificationEvent {
  const NotificationsGenerateGistRequested();
}

/// List dates (with per-date counts) for a single sender's conversation.
class NotificationsLoadSenderDates extends NotificationEvent {
  final String senderId;
  final String userEmail;
  final bool   includeHidden;

  const NotificationsLoadSenderDates( {
    required this.senderId,
    required this.userEmail,
    this.includeHidden = false,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, includeHidden ];
}

/// Load a sender's conversation grouped by date (YYYY-MM-DD keys).
class NotificationsLoadConversationByDate extends NotificationEvent {
  final String  senderId;
  final String  userEmail;
  final int?    hours;
  final String? anchor;
  final bool    includeHidden;

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

/// Per-session voice/persona allocation arrived for [senderId]. Source of
/// truth is the server bridge; mobile mirrors the persona into bloc state
/// for header rendering only (per Q1 — TTS reads persona straight off the
/// originating notification, not from this map).
///
/// Triggered via two paths:
/// 1. Real WS: `notification_queue_update` envelope with inner
///    `notification.type == "voice_persona_assigned"` — `_onExternalUpdate`
///    dispatch routes here.
/// 2. Test/programmatic: blocTest fires this event directly to verify the
///    persona-map mutation contract (Phase 1 Task 2.4 cases).
class NotificationsVoicePersonaAssigned extends NotificationEvent {
  final String       senderId;
  final VoicePersona persona;

  const NotificationsVoicePersonaAssigned( {
    required this.senderId,
    required this.persona,
  } );

  @override
  List<Object?> get props => [ senderId, persona.voiceId ];
}

/// Per-session persona was released (server-side SessionEnd cleared the
/// bridge for this sender). Removes the entry from the bloc's persona map.
/// Idempotent — released for a sender with no current persona is a no-op.
class NotificationsVoicePersonaReleased extends NotificationEvent {
  final String  senderId;
  final String? personaName;  // informational only; bloc keys removal by senderId

  const NotificationsVoicePersonaReleased( {
    required this.senderId,
    this.personaName,
  } );

  @override
  List<Object?> get props => [ senderId, personaName ];
}
