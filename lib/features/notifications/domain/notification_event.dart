import 'package:equatable/equatable.dart';
import '../../../shared/models/notification_item.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class NotificationStarted extends NotificationEvent {}

class NotificationReceived extends NotificationEvent {
  final NotificationItem notification;

  const NotificationReceived({required this.notification});

  @override
  List<Object?> get props => [notification];
}

class NotificationRead extends NotificationEvent {
  final String notificationId;

  const NotificationRead({required this.notificationId});

  @override
  List<Object?> get props => [notificationId];
}

class NotificationDeleted extends NotificationEvent {
  final String notificationId;

  const NotificationDeleted({required this.notificationId});

  @override
  List<Object?> get props => [notificationId];
}

class NotificationClearAll extends NotificationEvent {}

class NotificationMarkAllAsRead extends NotificationEvent {}

class NotificationSent extends NotificationEvent {
  final String message;
  final NotificationType type;

  const NotificationSent({
    required this.message,
    required this.type,
  });

  @override
  List<Object?> get props => [message, type];
}