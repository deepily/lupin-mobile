import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_themes.dart';
import 'core/di/service_locator.dart';
import 'features/auth/domain/auth_bloc.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/decision_proxy/domain/decision_proxy_bloc.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/domain/notification_bloc.dart';
import 'features/voice/domain/voice_bloc.dart';
import 'services/auth/server_context_service.dart';

class LupinMobileApp extends StatelessWidget {
  const LupinMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<VoiceBloc>(
          create: (_) => ServiceLocator.get<VoiceBloc>(),
        ),
        BlocProvider<AuthBloc>(
          create: (_) => ServiceLocator.get<AuthBloc>(),
        ),
        BlocProvider<NotificationBloc>(
          create: (_) => ServiceLocator.get<NotificationBloc>(),
        ),
        BlocProvider<DecisionProxyBloc>(
          create: (_) => ServiceLocator.get<DecisionProxyBloc>(),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppThemes.lightTheme,
        darkTheme: AppThemes.darkTheme,
        home: AuthGate(
          serverContext     : ServiceLocator.get<ServerContextService>(),
          authenticatedChild: const LupinHomeScreen(),
        ),
      ),
    );
  }
}
