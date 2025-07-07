import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import '../../../shared/models/notification_item.dart';
import '../../../services/websocket/websocket_service.dart';
import '../../../services/tts/tts_service.dart';
import 'notification_event.dart';
import 'notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final WebSocketService _webSocketService;
  final TTSService _ttsService;
  StreamSubscription<dynamic>? _webSocketSubscription;

  NotificationBloc({
    required WebSocketService webSocketService,
    required TTSService ttsService,
  })  : _webSocketService = webSocketService,
        _ttsService = ttsService,
        super(NotificationInitial()) {
    on<NotificationStarted>(_onNotificationStarted);
    on<NotificationReceived>(_onNotificationReceived);
    on<NotificationRead>(_onNotificationRead);
    on<NotificationDeleted>(_onNotificationDeleted);
    on<NotificationClearAll>(_onNotificationClearAll);
    on<NotificationMarkAllAsRead>(_onNotificationMarkAllAsRead);
    on<NotificationSent>(_onNotificationSent);
  }

  Future<void> _onNotificationStarted(
    NotificationStarted event,
    Emitter<NotificationState> emit,
  ) async {
    emit(const NotificationLoading());

    try {
      // TODO: Load notifications from local storage or API
      final notifications = <NotificationItem>[];

      // Start WebSocket connection for real-time notifications
      await _webSocketService.connect();

      // Listen to WebSocket messages
      _webSocketSubscription = _webSocketService.stream.listen(
        (message) => _handleWebSocketMessage(message),
      );

      final unreadCount = notifications.where((n) => !n.isRead).length;

      emit(NotificationLoaded(
        notifications: notifications,
        unreadCount: unreadCount,
      ));
    } catch (error) {
      emit(NotificationError(error: error.toString()));
    }
  }

  Future<void> _onNotificationReceived(
    NotificationReceived event,
    Emitter<NotificationState> emit,
  ) async {
    if (state is NotificationLoaded) {
      final currentState = state as NotificationLoaded;
      
      final updatedNotifications = [
        event.notification,
        ...currentState.notifications,
      ];

      final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

      emit(NotificationLoaded(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      ));

      // Handle audio notification if needed
      if (event.notification.hasAudio && event.notification.audioText != null) {
        await _ttsService.speak(event.notification.audioText!);
      }

      // TODO: Show system notification
      await _showSystemNotification(event.notification);
    }
  }

  Future<void> _onNotificationRead(
    NotificationRead event,
    Emitter<NotificationState> emit,
  ) async {
    if (state is NotificationLoaded) {
      final currentState = state as NotificationLoaded;
      
      final updatedNotifications = currentState.notifications.map((notification) {
        if (notification.id == event.notificationId) {
          return notification.copyWith(isRead: true);
        }
        return notification;
      }).toList();

      final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

      emit(NotificationLoaded(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      ));
    }
  }

  Future<void> _onNotificationDeleted(
    NotificationDeleted event,
    Emitter<NotificationState> emit,
  ) async {
    if (state is NotificationLoaded) {
      final currentState = state as NotificationLoaded;
      
      final updatedNotifications = currentState.notifications
          .where((notification) => notification.id != event.notificationId)
          .toList();

      final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

      emit(NotificationLoaded(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      ));
    }
  }

  Future<void> _onNotificationClearAll(
    NotificationClearAll event,
    Emitter<NotificationState> emit,
  ) async {
    emit(const NotificationLoaded(
      notifications: [],
      unreadCount: 0,
    ));
  }

  Future<void> _onNotificationMarkAllAsRead(
    NotificationMarkAllAsRead event,
    Emitter<NotificationState> emit,
  ) async {
    if (state is NotificationLoaded) {
      final currentState = state as NotificationLoaded;
      
      final updatedNotifications = currentState.notifications
          .map((notification) => notification.copyWith(isRead: true))
          .toList();

      emit(NotificationLoaded(
        notifications: updatedNotifications,
        unreadCount: 0,
      ));
    }
  }

  Future<void> _onNotificationSent(
    NotificationSent event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      final notification = NotificationItem(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        title: _getTitleForType(event.type),
        message: event.message,
        type: event.type,
        timestamp: DateTime.now(),
      );

      // Send notification to backend via WebSocket
      if (_webSocketService.isConnected) {
        _webSocketService.sendMessage({
          'type': 'send_notification',
          'notification': notification.toJson(),
        });
      }
    } catch (error) {
      emit(NotificationError(
        error: 'Failed to send notification: ${error.toString()}',
        notifications: state.notifications,
        unreadCount: state.unreadCount,
      ));
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      switch (message['type']) {
        case 'notification':
          final notification = NotificationItem.fromJson(message['notification']);
          add(NotificationReceived(notification: notification));
          break;
        // Handle other message types as needed
      }
    }
  }

  Future<void> _showSystemNotification(NotificationItem notification) async {
    // TODO: Implement platform-specific system notifications
    // This could use flutter_local_notifications package
  }

  String _getTitleForType(NotificationType type) {
    switch (type) {
      case NotificationType.info:
        return 'Information';
      case NotificationType.warning:
        return 'Warning';
      case NotificationType.error:
        return 'Error';
      case NotificationType.success:
        return 'Success';
      case NotificationType.jobStarted:
        return 'Job Started';
      case NotificationType.jobCompleted:
        return 'Job Completed';
      case NotificationType.jobFailed:
        return 'Job Failed';
      case NotificationType.audioResponse:
        return 'Audio Response';
      default:
        return 'Notification';
    }
  }

  @override
  Future<void> close() {
    _webSocketSubscription?.cancel();
    return super.close();
  }
}