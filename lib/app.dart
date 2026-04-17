import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_themes.dart';
import 'core/di/service_locator.dart';
import 'features/auth/domain/auth_bloc.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/agentic/domain/agentic_submission_bloc.dart';
import 'features/claude_code/domain/claude_code_bloc.dart';
import 'features/claude_code/domain/claude_code_event.dart';
import 'features/decision_proxy/domain/decision_proxy_bloc.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/domain/notification_bloc.dart';
import 'features/queue/domain/queue_bloc.dart';
import 'features/queue/domain/queue_event.dart';
import 'services/auth/server_context_service.dart';
import 'services/websocket/websocket_service.dart';

class LupinMobileApp extends StatefulWidget {
  const LupinMobileApp( { super.key } );

  @override
  State<LupinMobileApp> createState() => _LupinMobileAppState();
}

class _LupinMobileAppState extends State<LupinMobileApp> {
  StreamSubscription<dynamic>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _connectWsToBlocs();
  }

  void _connectWsToBlocs() {
    final ws = ServiceLocator.get<WebSocketService>();
    _wsSubscription = ws.stream.listen( ( raw ) {
      try {
        final data = raw is String ? jsonDecode( raw ) as Map<String, dynamic> : raw as Map<String, dynamic>;
        final type = data['type'] as String? ?? '';
        _dispatchWsEvent( type, data );
      } catch ( _ ) {
        // Ignore non-JSON or malformed messages.
      }
    } );
  }

  void _dispatchWsEvent( String type, Map<String, dynamic> data ) {
    switch ( type ) {
      case AppConstants.eventQueueTodoUpdate:
        ServiceLocator.get<QueueBloc>().add( const QueueExternalUpdate( 'todo' ) );
        break;
      case AppConstants.eventQueueRunningUpdate:
        ServiceLocator.get<QueueBloc>().add( const QueueExternalUpdate( 'running' ) );
        break;
      case AppConstants.eventQueueDoneUpdate:
        ServiceLocator.get<QueueBloc>().add( const QueueExternalUpdate( 'done' ) );
        break;
      case AppConstants.eventQueueDeadUpdate:
        ServiceLocator.get<QueueBloc>().add( const QueueExternalUpdate( 'dead' ) );
        break;
      case AppConstants.eventClaudeCodeMessage:
      case AppConstants.eventClaudeCodeStateChange:
        final taskId = data['task_id'] as String?;
        if ( taskId != null ) {
          ServiceLocator.get<ClaudeCodeBloc>().add(
            ClaudeCodeExternalMessage( taskId: taskId, payload: data ),
          );
        }
        break;
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: ( _ ) => ServiceLocator.get<AuthBloc>(),
        ),
        BlocProvider<NotificationBloc>(
          create: ( _ ) => ServiceLocator.get<NotificationBloc>(),
        ),
        BlocProvider<DecisionProxyBloc>(
          create: ( _ ) => ServiceLocator.get<DecisionProxyBloc>(),
        ),
        BlocProvider<QueueBloc>(
          create: ( _ ) => ServiceLocator.get<QueueBloc>(),
        ),
        BlocProvider<ClaudeCodeBloc>(
          create: ( _ ) => ServiceLocator.get<ClaudeCodeBloc>(),
        ),
        BlocProvider<AgenticSubmissionBloc>(
          create: ( _ ) => ServiceLocator.get<AgenticSubmissionBloc>(),
        ),
      ],
      child: MaterialApp(
        title    : AppConstants.appName,
        theme    : AppThemes.lightTheme,
        darkTheme: AppThemes.darkTheme,
        home     : AuthGate(
          serverContext     : ServiceLocator.get<ServerContextService>(),
          authenticatedChild: const LupinHomeScreen(),
        ),
      ),
    );
  }
}
