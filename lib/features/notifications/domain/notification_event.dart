import 'package:equatable/equatable.dart';

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
/// event lands on the wire.
class NotificationsExternalUpdate extends NotificationEvent {
  const NotificationsExternalUpdate();
}
