import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_themes.dart';
import 'core/di/service_locator.dart';
import 'features/auth/domain/auth_bloc.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/auth/presentation/ws_lifecycle_listener.dart';
import 'features/agentic/domain/agentic_submission_bloc.dart';
import 'features/claude_code/domain/claude_code_bloc.dart';
import 'features/claude_code/domain/claude_code_event.dart';
import 'features/decision_proxy/domain/decision_proxy_bloc.dart';
import 'features/focus_mode/domain/focus_chat_bloc.dart';
import 'features/focus_mode/domain/focus_chat_event.dart';
import 'features/focus_mode/presentation/focus_mode_screen.dart';
import 'features/notifications/data/notification_models.dart';
import 'features/notifications/domain/notification_bloc.dart';
import 'features/notifications/domain/notification_event.dart';
import 'features/queue/domain/queue_bloc.dart';
import 'features/quick_ask/domain/quick_ask_bloc.dart';
import 'features/quick_ask/domain/quick_ask_event.dart';
import 'features/queue/domain/queue_event.dart';
import 'services/auth/server_context_service.dart';
import 'services/push/fcm_bootstrap.dart';
import 'services/tts/streaming_tts_player.dart';
import 'services/websocket/websocket_service.dart';

/// WS frame → bloc dispatch bridge. Extracted from the private app State so
/// the cross-bloc dispatch contracts (AC-S2.8 single-TTS-dispatch pin,
/// AC-S2.10 reconnect re-hydration) are testable against the REAL wiring
/// rather than a copy. Resolves blocs lazily via ServiceLocator at dispatch
/// time, matching the prior inline behavior.
class WsBlocDispatcher {
  /// Set by `WsLifecycleListener.onAuthenticated`; stamps
  /// `FocusColdStartRequested` on `auth_success` frames. Every successful
  /// (re)connection completes WS auth, so the auth_success frame doubles as
  /// the reconnect re-hydration trigger (S2 §3.3; the seam Stage 2's FCM
  /// wake path terminates into, F-S5-1c).
  String? lastAuthenticatedUserId;

  void dispatch( String type, Map<String, dynamic> data ) {
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
      case AppConstants.eventJobStateTransition:
        // The LIVE job-status channel. The four `queue_*_update` arms above
        // have never fired — no emit site exists in the server — so this is
        // the case that actually carries status, and the completed frame
        // carries the answer with it (`metadata.response_text`).
        ServiceLocator.get<QuickAskBloc>().add( QuickAskTransitionReceived( data ) );
        break;
      case AppConstants.eventNotificationQueueUpdate:
        // Backend emits `{"type": "notification_queue_update", "notification": {...}}`
        // (see src/cosa/rest/websocket_manager.py `async_emit` / `emit_to_user`).
        // Parse the payload so NotificationBloc can drive audio on top of the
        // standard refetch path.
        final rawNotif = data['notification'];
        final notif = rawNotif is Map<String, dynamic>
            ? NotificationItem.fromJson( rawNotif )
            : ( rawNotif is Map
                ? NotificationItem.fromJson( Map<String, dynamic>.from( rawNotif ) )
                : null );
        ServiceLocator.get<NotificationBloc>().add(
          NotificationsExternalUpdate( notification: notif ),
        );
        // Parallel focus-surface dispatch (S2 §3.3): both blocs receive the
        // same frames; speech ownership lives with FocusChatBloc alone (the
        // legacy bloc's `tts` is not injected — F-S2-1 DI withdrawal).
        if ( notif != null ) _dispatchToFocus( notif );
        // Belt channel (S1 §3): a notification whose `jobId` matches the live
        // Quick Ask job is independent completion evidence, and a
        // `response_requested` one is proof of life in the pre-job-id window
        // where a reconcile has nothing to look up (AC-S1.4b).
        if ( notif != null ) {
          ServiceLocator.get<QuickAskBloc>().add( QuickAskNotificationReceived( notif ) );
        }
        break;
      case AppConstants.eventAuthSuccess:
        // WS (re)connect re-hydration: cold start on first connect,
        // merge-refresh on reconnect — the bloc is mode-dependent.
        final email = lastAuthenticatedUserId;
        if ( email != null ) {
          ServiceLocator.get<FocusChatBloc>().add(
            FocusColdStartRequested( userEmail: email ),
          );
        }
        break;
      case AppConstants.eventAudioStreamingStatus:
      case AppConstants.eventAudioStreamingChunk:
      case AppConstants.eventAudioStreamingComplete:
      case 'tts_error':
        // Route ElevenLabs TTS audio pipeline events to the streaming
        // player. Binary chunks arrive wrapped by WebSocketService as
        // `{type: audio_streaming_chunk, data: List<int>}`.
        ServiceLocator.get<StreamingTtsPlayer>().handleWsEvent( type, data );
        break;
    }
  }

  /// Inner-type discrimination for the focus surface — same `valid_types`
  /// whitelist the legacy dispatch pivots on (S2 §3.3): user-facing types
  /// become inbound chat items; persona events update badge data; admin
  /// types (speakerphone, commons-*) are not focus events.
  void _dispatchToFocus( NotificationItem notif ) {
    final focus = ServiceLocator.get<FocusChatBloc>();
    switch ( notif.type ) {
      case 'task':
      case 'progress':
      case 'alert':
      case 'custom':
      case 'user_initiated_message':
      case 'session_topic':
        focus.add( FocusInboundNotification( notif ) );
        break;
      case 'voice_persona_assigned':
        final sid = notif.senderId;
        if ( sid != null ) {
          focus.add( FocusPersonaUpdated(
            senderId : sid,
            persona  : notif.voicePersona,
          ) );
        }
        break;
      case 'voice_persona_released':
        final sid = notif.senderId;
        if ( sid != null ) focus.add( FocusPersonaUpdated( senderId: sid ) );
        break;
      case 'session_reaped':
        // Unambiguous worker exit (dismiss_sessions) — no debounce needed;
        // the rail hides it in Live, History still shows it (plan §4.8 #5).
        final sid = notif.senderId;
        if ( sid != null ) focus.add( FocusSenderExited( sid ) );
        break;
    }
  }
}

class LupinMobileApp extends StatefulWidget {
  const LupinMobileApp( { super.key } );

  @override
  State<LupinMobileApp> createState() => _LupinMobileAppState();
}

class _LupinMobileAppState extends State<LupinMobileApp> {
  StreamSubscription<dynamic>? _wsSubscription;
  final WsBlocDispatcher _dispatcher = WsBlocDispatcher();

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
        _dispatcher.dispatch( type, data );
      } catch ( _ ) {
        // Ignore non-JSON or malformed messages.
      }
    } );
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
        BlocProvider<FocusChatBloc>(
          create: ( _ ) => ServiceLocator.get<FocusChatBloc>(),
        ),
        // LOAD-BEARING, not boilerplate: this forces construction at app
        // start, so the pre-attribution buffer and the connection-stream
        // subscription exist BEFORE the first frame can arrive. The
        // `pending → queued` frame is emitted synchronously inside the
        // server's `push()`, before the ask response is even serialized.
        BlocProvider<QuickAskBloc>(
          create: ( _ ) => ServiceLocator.get<QuickAskBloc>(),
        ),
      ],
      child: WsLifecycleListener(
        onAuthenticated: ( userId ) async {
          _dispatcher.lastAuthenticatedUserId = userId;
          final ws = ServiceLocator.get<WebSocketService>();
          if ( !ws.isConnected ) await ws.connect( userId: userId );
          // S5 token-lifecycle writer 1 (login hook — the auth-state
          // AUTHENTICATED transition, Arnold residual #1). No-op unless
          // built with --dart-define=ENABLE_FCM=true.
          await fcmOnAuthenticated( userId );
        },
        onSignedOut: () async {
          final ws = ServiceLocator.get<WebSocketService>();
          if ( ws.isConnected ) await ws.disconnect();
          // S5 best-effort unregister (POST /api/fcm/unregister-token).
          await fcmOnLoggedOut();
        },
        child: MaterialApp(
          title    : AppConstants.appName,
          theme    : AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          home     : AuthGate(
            serverContext     : ServiceLocator.get<ServerContextService>(),
            // Q1 default-route swap (F-S3-3 seam): the focus surface is the
            // post-auth landing; legacy screens ride FocusModeScreen's drawer.
            authenticatedChild: const FocusModeScreen(),
          ),
        ),
      ),
    );
  }
}
