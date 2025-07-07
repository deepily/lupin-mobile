import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'main.dart';
import 'core/constants/app_constants.dart';
import 'core/constants/app_themes.dart';
import 'features/auth/domain/auth_bloc.dart';
import 'features/queue/domain/queue_bloc.dart';
import 'features/notifications/domain/notification_bloc.dart';
import 'features/home/home_screen.dart';

class LupinMobileApp extends StatelessWidget {
  const LupinMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>(),
        ),
        BlocProvider<QueueBloc>(
          create: (_) => getIt<QueueBloc>(),
        ),
        BlocProvider<NotificationBloc>(
          create: (_) => getIt<NotificationBloc>(),
        ),
        // TODO: Add additional BLoCs as they are implemented
        // BlocProvider(create: (_) => getIt<VoiceInputBloc>()),
        // BlocProvider(create: (_) => getIt<SettingsBloc>()),
        // BlocProvider(create: (_) => getIt<ConnectivityBloc>()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppThemes.lightTheme,
        darkTheme: AppThemes.darkTheme,
        home: const LupinHomeScreen(),
      ),
    );
  }
}