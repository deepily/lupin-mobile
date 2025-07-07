import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'services/websocket/websocket_service.dart';
import 'services/tts/tts_service.dart';
import 'features/auth/domain/auth_bloc.dart';
import 'features/queue/domain/queue_bloc.dart';
import 'features/notifications/domain/notification_bloc.dart';
import 'app.dart';

final GetIt getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize dependency injection
  await setupDependencies();
  
  // Run the app
  runApp(const LupinMobileApp());
}

Future<void> setupDependencies() async {
  // Register core services
  getIt.registerSingleton<Dio>(Dio());
  getIt.registerSingleton<WebSocketService>(WebSocketService(getIt<Dio>()));
  
  // Register TTS service with dependencies
  getIt.registerSingleton<TTSService>(
    TTSService(
      webSocketService: getIt<WebSocketService>(),
      dio: getIt<Dio>(),
    ),
  );
  
  // Register BLoCs
  getIt.registerFactory<AuthBloc>(() => AuthBloc());
  
  getIt.registerFactory<QueueBloc>(
    () => QueueBloc(
      webSocketService: getIt<WebSocketService>(),
    ),
  );
  
  getIt.registerFactory<NotificationBloc>(
    () => NotificationBloc(
      webSocketService: getIt<WebSocketService>(),
      ttsService: getIt<TTSService>(),
    ),
  );
}