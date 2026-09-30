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
import 'features/broadcast/data/broadcast_models.dart';
import 'features/broadcast/domain/broadcast_bloc.dart';
import 'features/queue/domain/queue_event.dart';
import 'features/transcript/data/transcript_models.dart';
import 'features/transcript/domain/transcript_frame_router.dart';
import 'shared/widgets/dictation_text_field.dart';
import 'services/asr/asr_service.dart';
import 'services/auth/server_context_service.dart';
import 'services/permissions/notification_permission.dart';
import 'services/push/fcm_bootstrap.dart';
import 'services/push/notification_tap_payload.dart';
import 'services/push/notification_tap_router.dart';
import 'services/tts/streaming_tts_player.dart';
import 'services/websocket/websocket_service.dart';

/// Login hook behind `WsLifecycleListener.onAuthenticated`, extracted so
/// the identity routing is testable: the UUID goes to the WebSocket (which
/// authenticates by bearer token and uses the id only as a connect gate),
/// the EMAIL goes to every email-keyed consumer.
///
/// Requires:
///   - userId is the account UUID and email the account email, both non-empty
///
/// Ensures:
///   - dispatcher.lastAuthenticatedEmail == email
///   - ws.connect( userId: userId ) is called iff ws is not connected
///   - registerPush receives email, never userId
///   - a throwing registerPush is logged and does not stop the rest of the hook
///   - requestNotifications is called once, AFTER registerPush, so a
///     system prompt the user has not answered yet never delays registration
///   - a notification tap held by [tapRouter] is routed to FocusChatBloc, ONCE,
///     with the email this login just supplied (row d9bc6f6c)
///   - a DENIED notification permission is logged via [logSink], because
///     nothing else on the device reports it (review F8)
Future<void> onWsAuthenticated( {
  required WsBlocDispatcher dispatcher,
  required WebSocketService ws,
  required String           userId,
  required String           email,
  Future<void> Function( String userEmail ) registerPush = fcmOnAuthenticated,
  NotificationPermissionRequester requestNotifications = requestNotificationPermission,
  NotificationTapRouter? tapRouter,
  void Function( String )? logSink,
} ) async {
  dispatcher.lastAuthenticatedEmail = email;
  // 🔴 DRAINED HERE, NOT ON `auth_success`, AND THE ORDER IS THE REASON. This is
  // the first moment the authenticated EMAIL exists, and the backfill that
  // populates the tapped conversation needs it. The WS `auth_success` frame
  // (which triggers cold start) arrives later and on a different path, and
  // bloc's default transformer runs handlers of different event types
  // CONCURRENTLY — so sequencing the reveal behind cold start would be a race,
  // not an ordering. The event carries the email instead, which removes the
  // dependency altogether.
  _routePendingTap( tapRouter, email );
  if ( !ws.isConnected ) await ws.connect( userId: userId );
  // S5 token-lifecycle writer 1 (login hook — the auth-state AUTHENTICATED
  // transition, Arnold residual #1). No-op unless built with
  // --dart-define=ENABLE_FCM=true. POST /api/fcm/register-token's body
  // field is `user_email`.
  //
  // 🔴 GUARDED, BECAUSE THE PERMISSION PROMPT SITS RIGHT BEHIND IT (row dfea49e7).
  // FCM token retrieval throws on a phone with no Play services, no route to
  // Google, or a failed Firebase init; unguarded, that exits this hook and the
  // prompt below never runs, so a fresh Android 13+ install drops every wake
  // notification silently. Registration is best-effort; the prompt is not.
  try {
    await registerPush( email );
  } catch ( e ) {
    ( logSink ?? debugPrint )( 'push registration failed at login (continuing): $e' );
  }
  // Row 8ff78c69: Android 13+ starts a fresh install with notifications
  // DENIED, and nothing else asks. Without this, wake notifications and the
  // ws_wake fallback are silently dropped by the OS.
  //
  // 🔴 AND THE ANSWER IS WORTH KEEPING, NOT DISCARDING (review F8). If the user
  // taps "Don't allow", the wake chain still runs end to end and still logs
  // "[FcmWake] shown" while the shade stays empty — the original bug's exact
  // symptom, with the fix installed. Logged here rather than inside
  // requestNotificationPermission() so it sits behind the injectable seam and a
  // test can prove it.
  if ( !await requestNotifications() ) {
    ( logSink ?? debugPrint )( '$kNotificationPermissionDeniedMarker — notifications will be '
        'dropped by the OS, silently, until it is granted in system settings' );
  }
}

/// Route one held notification tap into the focus surface.
///
/// Requires:
///   - email is the just-authenticated account email
///
/// Ensures:
///   - nothing happens when router is null or holds no tap
///   - a routable tap is dispatched as ONE [FocusMessageRevealRequested] and
///     marked handled, so a later drain cannot repeat it
void _routePendingTap( NotificationTapRouter? router, String email ) {
  final tap = router?.takePending();
  if ( tap == null ) return;
  final sender = tap.senderId;
  if ( sender == null ) return;   // a fallback notification: Focus mode, no target
  ServiceLocator.get<FocusChatBloc>().add( FocusMessageRevealRequested(
    senderId       : sender,
    notificationId : tap.notificationId,
    userEmail      : email,
  ) );
}

/// WS frame → bloc dispatch bridge. Extracted from the private app State so
/// the cross-bloc dispatch contracts (AC-S2.8 single-TTS-dispatch pin,
/// AC-S2.10 reconnect re-hydration) are testable against the REAL wiring
/// rather than a copy. Resolves blocs lazily via ServiceLocator at dispatch
/// time, matching the prior inline behavior.
class WsBlocDispatcher {
  /// Set by `onWsAuthenticated`; stamps `FocusColdStartRequested` on
  /// `auth_success` frames. Every successful (re)connection completes WS
  /// auth, so the auth_success frame doubles as the reconnect re-hydration
  /// trigger (S2 §3.3; the seam Stage 2's FCM wake path terminates into,
  /// F-S5-1c). It holds the EMAIL — it was once fed the account UUID, and
  /// senders-visible 404'd on every reconnect (row 588c8dc9).
  String? lastAuthenticatedEmail;

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
        // 🔴 BROADCAST ACKS RIDE THIS SAME FRAME, AND EVERYTHING THAT IDENTIFIES ONE IS
        // IN `payload` — `message` is an EMPTY STRING by design
        // (`commons_ack_watcher.py`, `_push_ack_event`). A reader following this app's
        // usual habit of looking in `message` sees blank frames, folds nothing, and the
        // pane renders what looks like a fleet that ignored the operator.
        //
        // `BroadcastAck.fromNotification` returns null for anything that is not an ack,
        // so this arm costs one type comparison on every other notification and cannot
        // throw on a malformed frame — a socket frame is untrusted input arriving at
        // arbitrary times, and this stream is shared with every other pane.
        if ( notif != null ) {
          final ack = BroadcastAck.fromNotification( notif.raw );
          if ( ack != null ) {
            ServiceLocator.get<BroadcastBloc>().add( BroadcastAckReceived( ack ) );
          }
        }
        break;
      case AppConstants.eventNotificationExpired:
        // AC-S4.3 — the ask TIMED OUT. These keys sit at the TOP level of
        // the frame (`notifications.py:1442`), not nested under
        // `notification` the way `notification_queue_update` nests them.
        // Both this case and the one below arrived and were dropped:
        // neither name appeared anywhere in `lib/`, so an expired ask sat
        // "pending" forever and poisoned `pendingPromptFor`.
        final expiredId = data[ 'notification_id' ]?.toString();
        if ( expiredId != null ) {
          ServiceLocator.get<FocusChatBloc>().add( FocusAskExpired(
            notificationId : expiredId,
            defaultUsed    : data[ 'default_used' ]?.toString(),
          ) );
        }
        break;
      case AppConstants.eventNotificationResponded:
        // AC-S4.3 — answered somewhere ELSE (another device, a proxy, the
        // browser). Retire the card as answered; `notifications.py:1636`.
        final respondedId = data[ 'notification_id' ]?.toString();
        if ( respondedId != null ) {
          ServiceLocator.get<FocusChatBloc>().add( FocusAskResponded(
            notificationId : respondedId,
            responseValue  : data[ 'response_value' ]?.toString(),
          ) );
        }
        break;
      case AppConstants.eventTranscriptAppend:
        // 🔴 THE LIVE CONSOLE'S ONLY ENTRY POINT, AND IT FORWARDS TO A ROUTER RATHER THAN A
        // BLOC ON PURPOSE. The console bloc is ROUTE-SCOPED (C1): an app-root instance would
        // keep watching a screen nobody can see, which is the build C5.11 fails. The router
        // is app-root, keyed by `cc_session_id`, and drops a frame for any seat with no open
        // route — the belt to the server's braces (C6), whose receipt is `droppedFrames`.
        //
        // ⚠️ THE FOUR `queue_*_update` ARMS ABOVE HAVE NEVER FIRED — no emit site exists in
        // the server. C9 exists so this does not become a fifth: it merges only after phase
        // 1's `cc_transcript_append` emit site lands, and C5.20's live arm is what proves a
        // real frame arrives here rather than assuming it.
        ServiceLocator.get<TranscriptFrameRouter>()
            .publishAppend( TranscriptAppend.fromJson( data ) );
        break;
      case AppConstants.eventTranscriptState:
        // `live | ended | rotated | epoch_mismatch | refused` (§3). The bloc drops its buffer
        // on an epoch change and treats `refused` as final (C5.21).
        ServiceLocator.get<TranscriptFrameRouter>()
            .publishState( TranscriptStateFrame.fromJson( data ) );
        break;
      case AppConstants.eventAuthSuccess:
        // An open console re-watches from its last offset and epoch (C5.8). Routed through
        // the router for the same reason the two arms above are: the dispatcher cannot reach
        // a route-scoped bloc. A closed console has no listener, so this costs nothing.
        ServiceLocator.get<TranscriptFrameRouter>().publishReconnected();
        // WS (re)connect re-hydration: cold start on first connect,
        // merge-refresh on reconnect — the bloc is mode-dependent.
        final email = lastAuthenticatedEmail;
        if ( email != null ) {
          ServiceLocator.get<FocusChatBloc>().add(
            FocusColdStartRequested( userEmail: email ),
          );
        }
        break;
      case AppConstants.eventResumeComplete:
        // Row 281a10d6: gap == true is the server saying it cannot prove the
        // replay was continuous, so re-fetch everything rather than assume we
        // are current. Same two paths a reconnect already uses.
        if ( data[ 'gap' ] == true ) {
          final gapEmail = lastAuthenticatedEmail;
          if ( gapEmail != null ) {
            ServiceLocator.get<FocusChatBloc>().add( FocusColdStartRequested( userEmail: gapEmail ) );
          }
          ServiceLocator.get<NotificationBloc>().add( const NotificationsExternalUpdate() );
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
  StreamSubscription<NotificationTapPayload>? _tapSubscription;
  final WsBlocDispatcher _dispatcher = WsBlocDispatcher();

  @override
  void initState() {
    super.initState();
    _connectWsToBlocs();
    _listenForTaps();
  }

  /// The WARM half of row d9bc6f6c: a tap while this process is ALREADY running
  /// and already signed in.
  ///
  /// `onWsAuthenticated` drains the router once, at login, which covers the cold
  /// start and the tap that arrives while the user is still at the lock screen.
  /// It does NOT fire again — so a tap on a notification received an hour into a
  /// session would sit in the router's slot forever without this. The two paths
  /// share the router's handle-once dedupe, so a tap cannot be routed twice.
  void _listenForTaps() {
    if ( !ServiceLocator.isRegistered<NotificationTapRouter>() ) return;
    final router = ServiceLocator.get<NotificationTapRouter>();
    _tapSubscription = router.taps.listen( ( tap ) {
      final email = _dispatcher.lastAuthenticatedEmail;
      // Not signed in yet: leave it in the slot for the login drain to pick up.
      // Dropping it here is the one thing that must not happen — that is the
      // exact case Rick hit, where the tap is what WOKE the app.
      if ( email == null ) return;
      final sender = tap.senderId;
      if ( sender == null ) return;
      router.markHandled( tap );
      ServiceLocator.get<FocusChatBloc>().add( FocusMessageRevealRequested(
        senderId       : sender,
        notificationId : tap.notificationId,
        userEmail      : email,
      ) );
    } );
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
    _tapSubscription?.cancel();
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
        // 🔴 ALSO LOAD-BEARING, and for a cousin of the reason above. Broadcast acks
        // arrive as `commons_broadcast_ack` frames on the notification stream, and the
        // dispatch below can only reach a bloc that exists. Constructing it here means
        // the ack tally also SURVIVES navigating away from the pane — losing ack
        // information on a screen change is the same defect as losing it on a
        // background, which is what that pane was built to prevent.
        BlocProvider<BroadcastBloc>(
          // 🔴 `startListeningWatch` IS THE HALF THAT MAKES THE GUARD REAL. Without it
          // `AckConfidence.interrupted` is never reached, the tally always claims to be
          // exact, and every test of the clause still passes — a control that cannot
          // fire, which is the shape this pane has been bitten by twice already.
          create: ( _ ) => ServiceLocator.get<BroadcastBloc>()
            ..startListeningWatch(
              socketStream: ServiceLocator.get<WebSocketService>().connectionStream,
            ),
        ),
      ],
      child: WsLifecycleListener(
        onAuthenticated: ( userId, email ) => onWsAuthenticated(
          dispatcher : _dispatcher,
          ws         : ServiceLocator.get<WebSocketService>(),
          userId     : userId,
          email      : email,
          tapRouter  : ServiceLocator.isRegistered<NotificationTapRouter>()
              ? ServiceLocator.get<NotificationTapRouter>()
              : null,
        ),
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
          // Above the Navigator, so sheets and dialogs see it too. No registered
          // recorder means no scope service, and every text box stays plain.
          builder  : ( context, child ) => DictationScope(
            asr   : ServiceLocator.isRegistered<AsrService>()
                ? ServiceLocator.get<AsrService>()
                : null,
            child : child!,
          ),
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
