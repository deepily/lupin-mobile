import 'package:equatable/equatable.dart';
import '../../../shared/models/notification_item.dart';

abstract class NotificationState extends Equatable {
  final List<NotificationItem> notifications;
  final int unreadCount;
  final String? error;

  const NotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.error,
  });

  @override
  List<Object?> get props => [notifications, unreadCount, error];
}

class NotificationInitial extends NotificationState {}

class NotificationLoading extends NotificationState {
  const NotificationLoading({
    super.notifications,
    super.unreadCount,
  });
}

class NotificationLoaded extends NotificationState {
  const NotificationLoaded({
    required List<NotificationItem> notifications,
    required int unreadCount,
  }) : super(
          notifications: notifications,
          unreadCount: unreadCount,
        );
}

class NotificationError extends NotificationState {
  const NotificationError({
    required String error,
    List<NotificationItem> notifications = const [],
    int unreadCount = 0,
  }) : super(
          notifications: notifications,
          unreadCount: unreadCount,
          error: error,
        );
}