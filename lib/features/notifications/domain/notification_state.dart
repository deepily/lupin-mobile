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
