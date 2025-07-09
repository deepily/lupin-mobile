import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/service_locator.dart';
import 'core/constants/app_constants.dart';
import 'core/constants/app_themes.dart';
import 'features/voice/domain/voice_bloc.dart';
import 'features/home/home_screen.dart';

class LupinMobileApp extends StatelessWidget {
  const LupinMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<VoiceBloc>(
          create: (_) => ServiceLocator.get<VoiceBloc>(),
        ),
        // TODO: Add additional BLoCs as they are implemented
        // BlocProvider(create: (_) => ServiceLocator.get<AuthBloc>()),
        // BlocProvider(create: (_) => ServiceLocator.get<QueueBloc>()),
        // BlocProvider(create: (_) => ServiceLocator.get<NotificationBloc>()),
        // BlocProvider(create: (_) => ServiceLocator.get<SettingsBloc>()),
        // BlocProvider(create: (_) => ServiceLocator.get<ConnectivityBloc>()),
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