import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Core
import '../storage/storage_manager.dart';
import '../cache/cache_exports.dart';

// Services
import '../../services/network/http_service.dart';
import '../../services/network/cached_http_service.dart';
import '../../services/websocket/websocket_service.dart';
import '../../services/auth/auth_interceptor.dart';
import '../../services/auth/auth_repository.dart';
import '../../services/auth/auth_token_provider.dart';
import '../../services/auth/biometric_gate.dart';
import '../../services/auth/secure_credential_store.dart';
import '../../services/auth/server_context_service.dart';
import '../../services/auth/session_persistence.dart';

// Auth feature
import '../../features/auth/domain/auth_bloc.dart';

// Tier 2 data layer
import '../../features/docs/data/doc_repository.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/settings/data/heartbeat_poke_repository.dart';
import '../../features/settings/data/push_pause_repository.dart';
import '../../features/decision_proxy/data/decision_proxy_repository.dart';

// Tier 2 BLoCs
import '../../features/notifications/domain/notification_bloc.dart';
import '../../features/decision_proxy/domain/decision_proxy_bloc.dart';

// Focus-mode surface (focus-mode-voice-chat milestone, S2)
import '../../features/focus_mode/domain/focus_chat_bloc.dart';

// Tier 3 data layer
import '../../features/queue/data/queue_repository.dart';
import '../../features/claude_code/data/claude_code_repository.dart';

// Tier 3 BLoCs
import '../../features/queue/domain/queue_bloc.dart';
import '../../features/claude_code/domain/claude_code_bloc.dart';

// Tier 4 data layer
import '../../features/agentic/data/agentic_repository.dart';

// Fleet Status (fleet-panes plan Phase 1, row a1962a5b) — the repository is a
// singleton like every other; its BLOC deliberately is NOT (see
// [buildFleetStatusBloc]).
import '../../features/fleet_status/data/fleet_repository.dart';
import '../../features/fleet_status/domain/fleet_status_bloc.dart';

// Live Console (console-tee plan §5). The REPOSITORY and the FRAME ROUTER are app-root
// singletons; the BLOC is route-scoped, like the four pane blocs and for a sharper reason —
// see buildTranscriptStreamBloc.
import '../../features/transcript/data/transcript_repository.dart';
import '../../features/transcript/domain/transcript_frame_router.dart';
import '../../features/transcript/domain/transcript_stream_bloc.dart';

// Broadcast (fleet-panes plan Phase 5, row 384591dd) — repository AND bloc are both
// app-root singletons. The bloc's scope is Rick's ruling of 2026-09-22 and is explained
// at its registration; it is the opposite of Fleet Status above, for a stated reason.
import '../../features/broadcast/data/broadcast_repository.dart';
import '../../features/broadcast/domain/broadcast_bloc.dart';

// The remaining fleet panes (plan Phases 2-4) — repositories are singletons, blocs
// are route-scoped factories. See buildTaskListBloc and its siblings.
import '../../features/fleet/data/task_write_repository.dart';
import '../../features/task_list/data/task_list_repository.dart';
import '../../features/task_list/domain/task_list_bloc.dart';
import '../../features/holding_area/data/holding_area_repository.dart';
import '../../features/holding_area/domain/holding_area_bloc.dart';
import '../../features/finished_tasks/data/finished_tasks_repository.dart';
import '../../features/finished_tasks/domain/finished_tasks_bloc.dart';

import '../../services/artifacts/io_file_service.dart';
import '../../services/asr/voice_capture_session.dart';

// Tier 4 BLoCs
import '../../features/agentic/domain/agentic_submission_bloc.dart';

// Notification audio (ding + TTS on high/urgent)
import '../../services/notification_audio/notification_audio_service.dart';
import '../../services/push/fcm_bootstrap.dart' show fcmOnLoggedOut;
import '../../services/push/notification_tap_binding.dart';
import '../../services/push/notification_tap_router.dart';
import '../../services/notification_audio/notification_delivery_policy.dart';
import '../../services/notification_audio/notification_preferences.dart';
import '../../services/quick_ask/quick_ask_preferences.dart';
import '../../services/notification_filter/notification_stop_list.dart';

// Agent-narration TTS (ElevenLabs primary, flutter_tts fallback)
import '../../services/tts/streaming_tts_player.dart';
import '../../services/tts/tts_orchestrator.dart';

// Voice-reply ASR (S4 — record pkg push-to-talk → parent Whisper endpoint)
import 'package:record/record.dart';
import '../../services/websocket/ws_reconnect_coordinator.dart';
import '../../services/asr/asr_service.dart';
import '../../features/quick_ask/domain/quick_ask_bloc.dart';

// The legacy voice/audio/TTS/use-case-registry stack is not part of the app: its
// repository, use-case and enhanced-service files are deleted from lib/.
// Voice reply uses the ASR and streaming TTS services registered in this file.
// If voice or TTS needs more than they offer, add new code and register it here.

// Settings
import '../settings/settings_manager.dart';
import '../settings/settings_service.dart';

/// Centralized service locator providing dependency injection and lifecycle management.
/// 
/// Manages registration, initialization, and access to all application dependencies
/// with proper dependency ordering and singleton/factory patterns.
/// Ensures clean separation of concerns and testable architecture.
class ServiceLocator {
  static final GetIt _getIt = GetIt.instance;
  static bool _isInitialized = false;

  /// Get instance of GetIt
  static GetIt get instance => _getIt;

  /// Initializes all application dependencies in correct dependency order.
  /// 
  /// Requires:
  ///   - Device must have sufficient resources for dependency initialization
  ///   - Network connectivity for remote service initialization
  ///   - Storage access permissions for cache and persistence services
  /// 
  /// Ensures:
  ///   - All dependencies are initialized in proper dependency order
  ///   - Core services are initialized before dependent services
  ///   - Singleton instances are properly registered and accessible
  ///   - Factory methods are configured for stateful components
  /// 
  /// Raises:
  ///   - InitializationException if any dependency fails to initialize
  ///   - PermissionException if storage access is denied
  ///   - NetworkException if remote services cannot be configured
  static Future<void> init() async {
    if (_isInitialized) return;

    // Initialize in dependency order
    await _initializeCore();
    await _initializeServices();
    await _initializeRepositories();
    await _initializeUseCases();
    await _initializeBLoCs();

    _isInitialized = true;
  }

  /// Builds the [FocusChatBloc] that the locator registers.
  ///
  /// Split out so a test can exercise the real wiring without booting [init], which
  /// needs platform channels. This is the only place `isQuickAskJob` is supplied.
  ///
  /// Requires:
  ///   - NotificationRepository, TtsOrchestrator and NotificationStopList are
  ///     registered
  ///   - QuickAskBloc is registered before the probe is called
  ///
  /// Ensures:
  ///   - returns a FocusChatBloc whose `isQuickAskJob` probe is non-null
  @visibleForTesting
  static FocusChatBloc buildFocusChatBloc() => FocusChatBloc(
    _getIt<NotificationRepository>(),
    tts          : _getIt<TtsOrchestrator>(),
    // Recency-band aging tick (plan 2026.06.25 §4.4) — production only;
    // tests construct the bloc without one so pumpAndSettle can settle.
    tickInterval : const Duration( seconds: 30 ),
    stopList     : _getIt<NotificationStopList>(),
    // Setter 1 of the two-setter verbatim contract. Without it `_isQuickAskJob`
    // is null, shouldSpeakVerbatim short-circuits at speech_intent.dart:83, and the
    // answer the user asked for is cut to `ttsFraction`, or never spoken at all
    // when `speakSystemSenders` is off. It is a closure, not a tear-off, because
    // QuickAskBloc is registered after this bloc, so the lookup must wait for call time.
    isQuickAskJob : ( jobId ) => _getIt<QuickAskBloc>().isQuickAskJob( jobId ),
  );

  /// Builds the [NotificationAudioService] with the notification-tap callback.
  ///
  /// Split out so a test can see the callback go in, since [init] cannot run under test.
  /// The plugin is a singleton, so a service built without the callback clears the one
  /// `main()` installed, and taps stop working after the first notification.
  ///
  /// Requires:
  ///   - NotificationPreferences and NotificationTapRouter are registered
  ///
  /// Ensures:
  ///   - returns a service wired to the tap router
  @visibleForTesting
  static NotificationAudioService buildNotificationAudioService() =>
      NotificationAudioService(
        prefs             : _getIt<NotificationPreferences>(),
        onNotificationTap : notificationTapSink( _getIt<NotificationTapRouter>() ),
      );

  /// Builds a new [FleetStatusBloc] on every call; it is never a singleton.
  ///
  /// An app-root pane bloc outlives its route and keeps polling a screen nobody
  /// is looking at. Scoping the bloc to its route is what stops the requests.
  ///
  /// Requires:
  ///   - FleetRepository is registered
  ///
  /// Ensures:
  ///   - returns a fresh bloc over the registered repository
  ///   - the caller closes it, which the route's BlocProvider does
  ///
  /// Unlike [buildFocusChatBloc], this is not test-only: the home screen route calls it.
  // Not a registered singleton, unlike the other blocs in [_initializeBLoCs]. Five
  // app-root pane blocs would run five 60-second timers at once, and a test that
  // asks whether polling stops when backgrounded passes with all five running.
  // A route-scoped bloc is disposed on leaving, which cancels the timer and the
  // in-flight request, and an unopened pane cannot issue a request at all.
  static FleetStatusBloc buildFleetStatusBloc() =>
      FleetStatusBloc( _getIt<FleetRepository>() );

  /// Builds a new Live Console bloc for one seat on every call.
  ///
  /// It is route-scoped because it holds a server-side watch, not just a poller. An
  /// app-root instance would keep the server streaming a seat's console to a phone
  /// nobody is using.
  ///
  /// Requires:
  ///   - TranscriptRepository, TranscriptFrameRouter and WebSocketService are registered
  ///   - [ccSessionId] is the seat's full stable session id, not the 8-hex form
  ///
  /// Ensures:
  ///   - returns a fresh bloc bound to that one seat
  ///   - watch and unwatch go over the live WebSocketService.sendMessage
  ///   - closing the bloc sends the unwatch frame
  // Pop the route, emit a frame, and the router must drop it: that is the check
  // that fails when the watch stays open, because nothing on screen asks for it.
  // No new transport is added, and the enhanced WebSocket service stays untouched.
  static TranscriptStreamBloc buildTranscriptStreamBloc( String ccSessionId ) =>
      TranscriptStreamBloc(
        ccSessionId : ccSessionId,
        repository  : _getIt<TranscriptRepository>(),
        router      : _getIt<TranscriptFrameRouter>(),
        send        : _getIt<WebSocketService>().sendMessage,
      );

  /// Builds a new [TaskListBloc] on every call, like [buildFleetStatusBloc].
  ///
  /// Pane blocs that poll are route-scoped, so an unopened pane has no timer.
  /// [BroadcastBloc] is the exception. It has no poller, and only the app root
  /// can route the socket frame that carries its acks.
  ///
  /// Requires:
  ///   - TaskListRepository, TaskWriteRepository and FleetRepository are registered
  ///
  /// Ensures:
  ///   - returns a fresh bloc; the caller closes it
  // `fleet` is the reassignment roster and nothing else. The owner control needs the
  // live personas, which only the arbiter knows. The board's own read lists only the
  // owners that already have rows, so it cannot hand work to a seat that owns none yet.
  // It is optional so the pane still renders when the arbiter is unreachable.
  static TaskListBloc buildTaskListBloc() => TaskListBloc(
    _getIt<TaskListRepository>(),
    _getIt<TaskWriteRepository>(),
    fleet : _getIt<FleetRepository>(),
  );

  /// Builds a new [HoldingAreaBloc] on every call, like [buildTaskListBloc].
  ///
  /// Requires:
  ///   - HoldingAreaRepository, TaskWriteRepository and FleetRepository are registered
  ///
  /// Ensures:
  ///   - returns a fresh bloc; the caller closes it
  // `fleet` is the reassignment roster here too, for the reason given on
  // [buildTaskListBloc]. Both task panes offer the owner control, so both need it.
  static HoldingAreaBloc buildHoldingAreaBloc() => HoldingAreaBloc(
    _getIt<HoldingAreaRepository>(),
    _getIt<TaskWriteRepository>(),
    fleet : _getIt<FleetRepository>(),
  );

  /// Builds a new [FinishedTasksBloc] on every call, like the other pane blocs.
  ///
  /// Requires:
  ///   - FinishedTasksRepository is registered
  ///
  /// Ensures:
  ///   - returns a fresh bloc; the caller closes it
  static FinishedTasksBloc buildFinishedTasksBloc() =>
      FinishedTasksBloc( _getIt<FinishedTasksRepository>() );

  /// Initialize core dependencies
  static Future<void> _initializeCore() async {
    // SharedPreferences
    final sharedPreferences = await SharedPreferences.getInstance();
    _getIt.registerSingleton<SharedPreferences>(sharedPreferences);

    // Storage Manager
    final storageManager = await StorageManager.getInstance();
    _getIt.registerSingleton<StorageManager>(storageManager);

    // Offline Manager
    final offlineManager = await OfflineManager.getInstance();
    _getIt.registerSingleton<OfflineManager>(offlineManager);

    // Audio Cache
    final audioCache = await AudioCache.getInstance();
    _getIt.registerSingleton<AudioCache>(audioCache);

    // Network Cache
    final networkCache = await NetworkCache.getInstance();
    _getIt.registerSingleton<NetworkCache>(networkCache);

    // Settings Manager
    final settingsManager = await SettingsManager.getInstance();
    _getIt.registerSingleton<SettingsManager>(settingsManager);

    // Settings Service
    final settingsService = await SettingsService.getInstance();
    _getIt.registerSingleton<SettingsService>(settingsService);

    // Server context (Dev ↔ Test) — loaded from bundled asset,
    // updates AppConstants.apiBaseUrl / wsBaseUrl before Dio is configured.
    final serverContext = await ServerContextService.load(sharedPreferences);
    _getIt.registerSingleton<ServerContextService>(serverContext);

    // Secure credential store (per-context refresh tokens, last-used email,
    // WS session IDs). Kept as a singleton — contextId is passed per call.
    _getIt.registerSingleton<SecureCredentialStore>(SecureCredentialStore());

    // Biometric gate
    _getIt.registerSingleton<BiometricGate>(BiometricGate());

    // Session persistence for WS "wise penguin" IDs
    _getIt.registerSingleton<SessionPersistence>(
      SessionPersistence(_getIt<SecureCredentialStore>()),
    );

    // Dio HTTP client — its base URL follows the server switch.
    registerSharedDio(serverContext);
  }

  /// Creates the shared [Dio], registers it, and keeps its base URL current.
  ///
  /// Split out so a test can exercise the real wiring without booting [init].
  /// The base URL is set here because HttpService sets it only later.
  /// A listener follows every later server switch.
  ///
  /// Requires:
  ///   - no Dio is registered yet
  ///
  /// Ensures:
  ///   - a Dio is registered in GetIt and returned
  ///   - its baseUrl is the saved context's baseUrl before this method returns
  ///   - its baseUrl is the new context's baseUrl after every
  ///     [ServerContextService.setActive] switch
  @visibleForTesting
  // AuthRepository posts relative paths such as "/auth/login". Without the base URL
  // set here, the Dio has an empty one while _initializeServices builds the auth
  // classes, and a switch to LAN DEV would keep signing in against the old host.
  static Dio registerSharedDio(ServerContextService serverContext) {
    final dio = Dio();
    dio.options.baseUrl = serverContext.baseUrl;
    serverContext.addListener((config) => dio.options.baseUrl = config.baseUrl);
    _getIt.registerSingleton<Dio>(dio);
    return dio;
  }

  /// Initialize services
  static Future<void> _initializeServices() async {
    // Auth repository — uses the shared Dio. Constructed before HttpService
    // so the auth interceptor (below) can reference it.
    _getIt.registerSingleton<AuthRepository>(
      AuthRepository(_getIt<Dio>()),
    );

    // Auth interceptor: injects Bearer token, refreshes on 401, persists
    // rotated tokens via SecureCredentialStore.
    final store   = _getIt<SecureCredentialStore>();
    final context = _getIt<ServerContextService>();
    _getIt<Dio>().interceptors.add(AuthInterceptor(
      dio  : _getIt<Dio>(),
      repo : _getIt<AuthRepository>(),
      readRefreshToken: () => store.readRefreshToken(context.activeConfig.id),
      onTokensRotated: (tokens) async {
        await store.writeRefreshToken(context.activeConfig.id, tokens.refreshToken);
      },
      onRefreshFailed: () async {
        clearAccessToken();
      },
    ));

    // HTTP Service
    _getIt.registerSingleton<HttpService>(
      HttpService(_getIt<Dio>()),
    );

    // Cached HTTP Service
    _getIt.registerSingleton<CachedHttpService>(
      CachedHttpService(_getIt<Dio>()),
    );

    // WebSocket Service
    _getIt.registerSingleton<WebSocketService>(
      WebSocketService(_getIt<Dio>()),
    );
    // Reconnect triggers for the socket above; main() starts it.
    _getIt.registerSingleton<WsReconnectCoordinator>(
      WsReconnectCoordinator.forApp( _getIt<WebSocketService>() ),
    );

    // Tier 2 data layer — typed repos over the shared Dio (auth interceptor
    // injects Bearer token automatically).
    _getIt.registerSingleton<NotificationRepository>(
      NotificationRepository(_getIt<Dio>()),
    );

    _getIt.registerSingleton<PushPauseRepository>(
      PushPauseRepository(_getIt<Dio>()),
    );

    _getIt.registerSingleton<HeartbeatPokeRepository>(
      HeartbeatPokeRepository(_getIt<Dio>()),
    );

    // Doc-viewer fetches for links found in notification abstracts. Same shared
    // Dio, so the auth interceptor supplies the Bearer token.
    _getIt.registerSingleton<DocRepository>(
      DocRepository(_getIt<Dio>()),
    );
    _getIt.registerSingleton<DecisionProxyRepository>(
      DecisionProxyRepository(_getIt<Dio>()),
    );

    // Tier 3 data layer — queue + claude code repos over the same shared Dio.
    _getIt.registerSingleton<QueueRepository>(
      QueueRepository(_getIt<Dio>()),
    );
    _getIt.registerSingleton<ClaudeCodeRepository>(
      ClaudeCodeRepository(_getIt<Dio>()),
    );

    // Tier 4 data layer — agentic job repo + IO file service.
    _getIt.registerSingleton<AgenticRepository>(
      AgenticRepository(_getIt<Dio>()),
    );
    _getIt.registerSingleton<IoFileService>(
      IoFileService(_getIt<Dio>()),
    );

    // Fleet Status — read of /api/arbiter/fleet-state plus the one write this
    // pane owns, PUT /api/arbiter/fleet-size-cap. Stateless over the shared
    // Dio, so a singleton is right here; the BLOC is route-scoped instead.
    _getIt.registerSingleton<FleetRepository>(
      FleetRepository(_getIt<Dio>()),
    );

    // Live Console — the Claude Code transcript stream. Stateless over the shared Dio,
    // so a singleton is right; the BLOC is route-scoped instead.
    _getIt.registerSingleton<TranscriptRepository>(
      TranscriptRepository(_getIt<Dio>()),
    );

    // 🔴 THE FRAME ROUTER IS APP-ROOT **BECAUSE THE BLOC IS NOT**, which is the whole
    // point of it existing. `WsBlocDispatcher.dispatch` can only reach app-root objects
    // through this locator, and a route-scoped console bloc is by definition not one. So
    // the dispatcher hands frames to this router, and the bloc subscribes to it for its one
    // seat while its route is alive. It also drops frames for seats with no open route,
    // which is §5's first belt (C6) against the server ever fanning out more widely than
    // its watcher set.
    _getIt.registerSingleton<TranscriptFrameRouter>(
      TranscriptFrameRouter(),
    );

    // Broadcast — the recipient roster, the fan-out door, and recent activity.
    // Stateless over the shared Dio, same as FleetRepository.
    _getIt.registerSingleton<BroadcastRepository>(
      BroadcastRepository(_getIt<Dio>()),
    );

    // The remaining fleet panes (plan Phases 2-4). Repositories are stateless
    // singletons over the shared Dio; the BLOCS are route-scoped factories below,
    // because these three poll and an app-root instance would keep polling a
    // destination nobody is looking at.
    //
    // ⚠️ TaskWriteRepository is SHARED BY BOTH TASK PANES ON PURPOSE. Both press the
    // same seven verbs through the same two doors, and a per-pane copy of the 202
    // check is the one defect that is completely silent — the pane paints a row
    // approved that the server only queued.
    _getIt.registerSingleton<TaskWriteRepository>(
      TaskWriteRepository(_getIt<Dio>()),
    );
    _getIt.registerSingleton<TaskListRepository>(
      TaskListRepository(_getIt<Dio>()),
    );
    _getIt.registerSingleton<HoldingAreaRepository>(
      HoldingAreaRepository(_getIt<Dio>()),
    );
    _getIt.registerSingleton<FinishedTasksRepository>(
      FinishedTasksRepository(_getIt<Dio>()),
    );

    // Notification audio — preferences backed by SharedPreferences, service
    // wraps flutter_local_notifications + flutter_tts. Channels register
    // lazily on first handleIncoming() via initialize(); app startup also
    // pre-warms the service (see main.dart).
    // Notification stop-list (plan 2026.08.21 §3) — ONE predicate shared
    // by the TTS gate, the focus bloc and the conversation list.
    _getIt.registerSingleton<NotificationStopList>(
      NotificationStopList( _getIt<SharedPreferences>() ),
    );
    _getIt.registerSingleton<NotificationPreferences>(
      NotificationPreferences(_getIt<SharedPreferences>()),
    );
    // Quick Ask send mode — review first (default) or send immediately.
    _getIt.registerSingleton<QuickAskPreferences>(
      QuickAskPreferences(_getIt<SharedPreferences>()),
    );
    // Row d9bc6f6c — the notification-TAP holder. Registered BEFORE the audio
    // service, because that service's constructor needs the tap callback built
    // from it: whichever of the two `initialize()` calls runs last must install
    // the SAME callback, or the plugin singleton's handler is left null.
    _getIt.registerSingleton<NotificationTapRouter>( NotificationTapRouter() );
    _getIt.registerSingleton<NotificationAudioService>(
      buildNotificationAudioService(),
    );

    // Agent-narration TTS — slim ElevenLabs streaming player built against
    // the shared Dio + WebSocket stream. Orchestrator (TtsOrchestrator,
    // registered separately) decides when to call speak().
    _getIt.registerSingleton<StreamingTtsPlayer>(
      StreamingTtsPlayer(_getIt<Dio>()),
    );

    // FIFO queue + priority gate + urgent preempt + quota fallback in
    // front of the TTS pipeline. NotificationBloc calls
    // enqueueIfSpeakable() on every incoming notification; the
    // orchestrator decides speech-worthiness and dispatches via either
    // StreamingTtsPlayer (ElevenLabs) or NotificationAudioService
    // (flutter_tts fallback).
    _getIt.registerSingleton<TtsOrchestrator>(
      TtsOrchestrator(
        player   : _getIt<StreamingTtsPlayer>(),
        fallback : _getIt<NotificationAudioService>(),
        prefs    : _getIt<NotificationPreferences>(),
        ws       : _getIt<WebSocketService>(),
        stopList : _getIt<NotificationStopList>(),
      ),
    );
  }

  /// Registers repositories; the legacy stack is disabled, so there is nothing to do.
  ///
  /// The active repositories are registered in [_initializeServices] next to the Dio
  /// they depend on.
  static Future<void> _initializeRepositories() async {
    // Tier 1-4 repositories are registered in _initializeServices() alongside
    // the Dio they depend on. Nothing left to do here.
  }

  /// Registers use cases; there are none, so there is nothing to do.
  static Future<void> _initializeUseCases() async {
    // No active use cases. The legacy registry and the voice use cases were deleted.
  }

  /// Initialize BLoCs
  static Future<void> _initializeBLoCs() async {
    // Auth BLoC — singleton so auth state survives widget rebuilds
    _getIt.registerLazySingleton<AuthBloc>(
      () => AuthBloc(
        repo      : _getIt<AuthRepository>(),
        store     : _getIt<SecureCredentialStore>(),
        context   : _getIt<ServerContextService>(),
        biometric : _getIt<BiometricGate>(),
        // The push token is unregistered with the JWT still set; after the token is cleared it is a 401.
        onBeforeSignOut : fcmOnLoggedOut,
      ),
    );

    // Tier 2 BLoCs — lazy singletons so state survives navigation.
    //
    // F-S1-1 USER RULING (mechanism F-S2-1, 2026-06-12): the legacy bloc's
    // Optional `tts` dependency is NO LONGER injected — its TTS dispatch
    // goes dead and FocusChatBloc (below) becomes the SOLE TTS dispatcher
    // via TtsOrchestrator.enqueueAlways(). The bloc FILE is untouched
    // (Q2 literal); ding/audio routing stays with the legacy bloc.
    // Re-injecting `tts:` here would double-speak every high/urgent frame.
    _getIt.registerLazySingleton<NotificationBloc>(
      () => NotificationBloc(
        _getIt<NotificationRepository>(),
        audio  : _getIt<NotificationAudioService>(),
        // Row 7cac3a17's foreground gate. Same policy object the background
        // isolate rebuilds for itself from the same SharedPreferences, so the
        // two surfaces cannot drift apart in what they think is switched on.
        policy : NotificationDeliveryPolicy( _getIt<NotificationPreferences>() ),
      ),
    );

    // Focus-mode state engine (S2) — the sole TTS dispatcher per above.
    _getIt.registerLazySingleton<FocusChatBloc>( buildFocusChatBloc );

    // Voice-reply ASR (S4): record-pkg push-to-talk → parent Whisper WAV
    // endpoint. Rides the SHARED auth-wired Dio (endpoint needs no auth per
    // OSQ-1; the bearer is harmless).
    // Quick Ask (S1). Eager-ish by way of the MultiBlocProvider in `app.dart`,
    // which constructs it at app start so the pre-attribution buffer exists
    // before the first `job_state_transition` frame can arrive.
    _getIt.registerLazySingleton<QuickAskBloc>(
      () => QuickAskBloc(
        _getIt<QueueRepository>(),
        asr           : _getIt<AsrService>(),
        ws            : _getIt<WebSocketService>(),
        // AC-S4.6 — the second door. Door C's near-match confirm is a
        // notification, and the ask it blocks cannot proceed until it is
        // answered on `POST /api/notify/response`.
        notifications : _getIt<NotificationRepository>(),
        prefs         : _getIt<QuickAskPreferences>(),
      ),
    );

    // 🔴 APP-ROOT, NOT ROUTE-SCOPED — Rick's ruling, 2026-09-22, and the reason is the
    // ACK TALLY rather than symmetry with the other blocs. Broadcast acks arrive on the
    // socket and `app.dart` is the only router for those frames, so it can only dispatch
    // to a bloc it can see. A route-scoped bloc would also be DESTROYED on navigating
    // away, taking the tally with it — and losing ack information silently is the exact
    // defect this whole pane was built to prevent.
    //
    // ⚠️ The Fleet Status precedent points the other way and does NOT apply here: that
    // bloc is route-scoped because it polls on a 60-second timer, so an app-root instance
    // would keep polling whichever pane the operator is actually looking at. This pane has
    // NO poller by design, and its roster is fetched only when the pane mounts.
    _getIt.registerLazySingleton<BroadcastBloc>(
      () => BroadcastBloc(
        _getIt<BroadcastRepository>(),
        voice : VoiceCaptureSession( asr: _getIt<AsrService>() ),
      ),
    );

    _getIt.registerLazySingleton<AsrService>(
      () => AsrService(
        dio            : _getIt<Dio>(),
        recorder       : AudioRecorder(),
        // Debug "Keep voice recordings" (row 9b1f7701), read per discard.
        keepRecordings : () => _getIt<NotificationPreferences>().keepVoiceRecordings,
        // Row a1c12c6e: no spoken notification while the mic records.
        onCapturingChanged : _dispatchCaptureHold,
      ),
    );
    _getIt.registerLazySingleton<DecisionProxyBloc>(
      () => DecisionProxyBloc(_getIt<DecisionProxyRepository>()),
    );

    // Tier 3 BLoCs — lazy singletons.
    _getIt.registerLazySingleton<QueueBloc>(
      () => QueueBloc(_getIt<QueueRepository>()),
    );
    _getIt.registerLazySingleton<ClaudeCodeBloc>(
      () => ClaudeCodeBloc(_getIt<ClaudeCodeRepository>()),
    );

    // Tier 4 BLoC — lazy singleton shared across all agentic submission forms.
    _getIt.registerLazySingleton<AgenticSubmissionBloc>(
      () => AgenticSubmissionBloc(_getIt<AgenticRepository>()),
    );
  }

  /// Hands a capture transition to the TTS orchestrator and observes its future.
  ///
  /// `AsrService.onCapturingChanged` returns void, so the future from `setCaptureHold`
  /// used to be dropped, and a player error became an unhandled async error. The
  /// orchestrator orders overlapping transitions; this method handles the error.
  ///
  /// Requires:
  ///   - nothing; a missing [TtsOrchestrator] registration is a no-op
  ///
  /// Ensures:
  ///   - the returned future is always observed
  ///   - a failed transition is logged, never rethrown into the recorder
  static void _dispatchCaptureHold( bool capturing ) {
    if ( !_getIt.isRegistered<TtsOrchestrator>() ) return;
    _getIt<TtsOrchestrator>().setCaptureHold( capturing ).catchError(
      ( Object error, StackTrace stack ) {
        debugPrint( '[tts] capture hold -> $capturing failed: $error' );
      },
    );
  }

  /// Retrieves registered service instance of specified type.
  /// 
  /// Requires:
  ///   - Type T must be a registered service type
  ///   - Service locator must be initialized
  /// 
  /// Ensures:
  ///   - Returns the correctly typed service instance
  ///   - Singleton services return the same instance
  ///   - Factory services create new instances as configured
  /// 
  /// Raises:
  ///   - ServiceNotRegisteredException if type T is not registered
  ///   - InitializationException if service locator not initialized
  static T get<T extends Object>() => _getIt<T>();

  /// Checks whether a service of type T is registered.
  ///
  /// Requires:
  ///   - Type T is a valid object type
  ///
  /// Ensures:
  ///   - returns true if registered, false otherwise
  ///   - has no side effects and never throws for unregistered types
  static bool isRegistered<T extends Object>() => _getIt.isRegistered<T>();

  /// Resets all registered dependencies for testing or reinitialization.
  /// 
  /// Requires:
  ///   - Should only be used in testing or controlled reinitialization scenarios
  /// 
  /// Ensures:
  ///   - All registered services are unregistered and disposed
  ///   - Service locator state is reset to uninitialized
  ///   - Memory resources are properly released
  ///   - Fresh initialization can be performed after reset
  /// 
  /// Raises:
  ///   - DisposeException if some services fail to dispose properly
  static Future<void> reset() async {
    await _getIt.reset();
    _isInitialized = false;
  }

  /// Reports the registration status of the core and network services.
  ///
  /// Requires:
  ///   - the locator is accessible; initialization is not required
  ///
  /// Ensures:
  ///   - returns a map of service names to a status string
  ///   - the status reflects the current registration state
  static Map<String, String> getRegisteredServices() {
    final services = <String, String>{};
    
    // Core services
    services['SharedPreferences'] = _getIt.isRegistered<SharedPreferences>() ? 'Registered' : 'Not registered';
    services['StorageManager'] = _getIt.isRegistered<StorageManager>() ? 'Registered' : 'Not registered';
    services['OfflineManager'] = _getIt.isRegistered<OfflineManager>() ? 'Registered' : 'Not registered';
    services['AudioCache'] = _getIt.isRegistered<AudioCache>() ? 'Registered' : 'Not registered';
    services['NetworkCache'] = _getIt.isRegistered<NetworkCache>() ? 'Registered' : 'Not registered';
    services['Dio'] = _getIt.isRegistered<Dio>() ? 'Registered' : 'Not registered';
    
    // Network services
    services['HttpService'] = _getIt.isRegistered<HttpService>() ? 'Registered' : 'Not registered';
    services['CachedHttpService'] = _getIt.isRegistered<CachedHttpService>() ? 'Registered' : 'Not registered';
    services['WebSocketService'] = _getIt.isRegistered<WebSocketService>() ? 'Registered' : 'Not registered';

    return services;
  }
}

/// Convenience methods for accessing services
extension ServiceLocatorExtensions on ServiceLocator {
  /// Get StorageManager
  static StorageManager get storageManager => ServiceLocator.get<StorageManager>();
  
  /// Get OfflineManager
  static OfflineManager get offlineManager => ServiceLocator.get<OfflineManager>();
  
  /// Get AudioCache
  static AudioCache get audioCache => ServiceLocator.get<AudioCache>();
  
  /// Get NetworkCache
  static NetworkCache get networkCache => ServiceLocator.get<NetworkCache>();
  
  /// Get HTTP Service
  static CachedHttpService get httpService => ServiceLocator.get<CachedHttpService>();
  
  /// Get WebSocket Service
  static WebSocketService get webSocketService => ServiceLocator.get<WebSocketService>();
}