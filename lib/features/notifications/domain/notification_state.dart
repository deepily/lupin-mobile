import 'package:equatable/equatable.dart';

import '../data/notification_models.dart';

abstract class NotificationState extends Equatable {
  const NotificationState();

  @override
  List<Object?> get props => [];
}

class NotificationsInitial extends NotificationState {
  const NotificationsInitial();
}

class NotificationsLoading extends NotificationState {
  const NotificationsLoading();
}

class NotificationsInboxLoaded extends NotificationState {
  final List<SenderSummary> senders;
  final String userEmail;

  const NotificationsInboxLoaded( {
    required this.senders,
    required this.userEmail,
  } );

  @override
  List<Object?> get props => [ senders, userEmail ];
}

class NotificationsConversationLoaded extends NotificationState {
  final String                       senderId;
  final String                       userEmail;
  final List<ConversationMessage>    messages;

  const NotificationsConversationLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.messages,
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, messages ];
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
class NotificationsSenderDatesLoaded extends NotificationState {
  final String            senderId;
  final String            userEmail;
  final List<DateSummary> dates;

  const NotificationsSenderDatesLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.dates,
  } );

  @override
  List<Object?> get props => [
    senderId, userEmail,
    dates.length,
    dates.fold<int>( 0, ( s, d ) => s + d.count ),
  ];
}

/// Conversation grouped by date (YYYY-MM-DD → list of NotificationItem).
class NotificationsConversationByDateLoaded extends NotificationState {
  final String                              senderId;
  final String                              userEmail;
  final Map<String, List<NotificationItem>> byDate;

  const NotificationsConversationByDateLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.byDate,
  } );

  @override
  List<Object?> get props => [
    senderId, userEmail,
    byDate.keys.length,
    byDate.values.fold<int>( 0, ( s, l ) => s + l.length ),
  ];
}
