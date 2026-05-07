import 'package:equatable/equatable.dart';

import '../data/notification_models.dart';

abstract class NotificationState extends Equatable {
  const NotificationState();

  @override
  List<Object?> get props => [];
}

/// Mixin shared by every loaded state — exposes the persona snapshot that the
/// bloc keeps for header rendering across screens. Per Q1, this map is for
/// rendering only; TTS dispatch reads persona straight from each notification.
///
/// `personaFor(senderId)` is the canonical accessor used by tests
/// (Phase 1 Task 2.4 assertion shape) and by widget-tree consumers
/// (Phase 3 PersonaBadge wiring sites).
mixin PersonaSnapshotMixin {
  Map<String, VoicePersona> get personasBySender;
  VoicePersona? personaFor( String senderId ) => personasBySender[ senderId ];
}

class NotificationsInitial extends NotificationState {
  const NotificationsInitial();
}

class NotificationsLoading extends NotificationState {
  const NotificationsLoading();
}

class NotificationsInboxLoaded extends NotificationState
    with PersonaSnapshotMixin {
  final List<SenderSummary> senders;
  final String userEmail;
  @override
  final Map<String, VoicePersona> personasBySender;

  const NotificationsInboxLoaded( {
    required this.senders,
    required this.userEmail,
    this.personasBySender = const {},
  } );

  @override
  List<Object?> get props => [ senders, userEmail, personasBySender ];
}

class NotificationsConversationLoaded extends NotificationState
    with PersonaSnapshotMixin {
  final String                       senderId;
  final String                       userEmail;
  final List<ConversationMessage>    messages;
  @override
  final Map<String, VoicePersona>    personasBySender;

  const NotificationsConversationLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.messages,
    this.personasBySender = const {},
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, messages, personasBySender ];
}

class NotificationsResponding extends NotificationState {
  final String notificationId;
  const NotificationsResponding( this.notificationId );

  @override
  List<Object?> get props => [ notificationId ];
}

class NotificationsResponseAcked extends NotificationState {
  final NotificationResponseAck ack;
  const NotificationsResponseAcked( this.ack );

  @override
  List<Object?> get props => [ ack.notificationId, ack.status ];
}

class NotificationsError extends NotificationState {
  final String message;
  const NotificationsError( this.message );

  @override
  List<Object?> get props => [ message ];
}

/// Transient state: gist generation is in flight. Emitted in parallel with
/// the underlying [NotificationsConversationLoaded] (the UI uses a listener,
/// not a builder, so the conversation list stays visible).
class NotificationsGistLoading extends NotificationState {
  const NotificationsGistLoading();
}

/// Gist result — UI shows in a bottom sheet.
class NotificationsGistReady extends NotificationState {
  final String gist;
  const NotificationsGistReady( this.gist );

  @override
  List<Object?> get props => [ gist ];
}

/// Date list for a single sender (YYYY-MM-DD entries with counts).
class NotificationsSenderDatesLoaded extends NotificationState
    with PersonaSnapshotMixin {
  final String            senderId;
  final String            userEmail;
  final List<DateSummary> dates;
  @override
  final Map<String, VoicePersona> personasBySender;

  const NotificationsSenderDatesLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.dates,
    this.personasBySender = const {},
  } );

  @override
  List<Object?> get props => [
    senderId, userEmail,
    dates.length,
    dates.fold<int>( 0, ( s, d ) => s + d.count ),
    personasBySender,
  ];
}

/// Conversation grouped by date (YYYY-MM-DD → list of NotificationItem).
class NotificationsConversationByDateLoaded extends NotificationState
    with PersonaSnapshotMixin {
  final String                              senderId;
  final String                              userEmail;
  final Map<String, List<NotificationItem>> byDate;
  @override
  final Map<String, VoicePersona>           personasBySender;

  const NotificationsConversationByDateLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.byDate,
    this.personasBySender = const {},
  } );

  @override
  List<Object?> get props => [
    senderId, userEmail,
    byDate.keys.length,
    byDate.values.fold<int>( 0, ( s, l ) => s + l.length ),
    personasBySender,
  ];
}
