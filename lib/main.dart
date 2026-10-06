import 'package:flutter/material.dart';
import 'core/app_initialization.dart';
import 'core/logging/logger.dart';
import 'core/di/service_locator.dart';
import 'services/push/fcm_bootstrap.dart';
import 'services/push/notification_tap_binding.dart';
import 'services/push/notification_tap_router.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/websocket/ws_reconnect_coordinator.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize core systems (logging, error handling, storage, DI)
    await AppInitialization.initialize(
      enableDebugLogging: true,
      enableFileLogging: true,
      enableRemoteLogging: false,
    );

    Logger.info('Lupin Mobile app starting...');

    // Row b69dbf0b: the socket's reconnect triggers. The lifecycle and connectivity services must be running for
    // them to see anything; the connectivity check does DNS lookups, so it is not awaited.
    startReconnectServices( ServiceLocator.get<WsReconnectCoordinator>() );

    // S5 FCM silent-relay wake-up. No-op unless built with
    // --dart-define=ENABLE_FCM=true (default OFF — Stage-1 builds carry
    // no google-services.json dependency, AC-S5.4).
    await initFcmIfEnabled();

    // Row d9bc6f6c — capture the tap that LAUNCHED this process, before the
    // first frame. The app was swiped away when the notification arrived, so
    // `onDidReceiveNotificationResponse` never fires for it; the launch intent
    // is the only place the payload exists, and `AuthGate` is about to send the
    // user through a fingerprint unlock before anything can act on it. The
    // router holds it across that wait.
    final tapRouter = ServiceLocator.get<NotificationTapRouter>();
    final launch    = await bindNotificationTaps(
      plugin : FlutterLocalNotificationsPlugin(),
      router : tapRouter,
    );
    Logger.info( 'Notification tap binding ready '
        '(launched by notification: ${ launch?.didNotificationLaunchApp ?? false }, '
        'pending tap: ${ tapRouter.hasPending })' );

    // Run the app
    runApp(const LupinMobileApp());
    
  } catch (error, stackTrace) {
    // Critical initialization error - log and show error screen
    Logger.critical(
      'Failed to initialize application',
      error: error,
      stackTrace: stackTrace,
    );
    
    // Show minimal error app
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Please restart the app',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}