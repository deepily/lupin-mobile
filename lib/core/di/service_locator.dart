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
import '../../services/notification_audio/notification_preferences.dart';
import '../../services/quick_ask/quick_ask_preferences.dart';
import '../../services/notification_filter/notification_stop_list.dart';

// Agent-narration TTS (ElevenLabs primary, flutter_tts fallback)
import '../../services/tts/streaming_tts_player.dart';
import '../../services/tts/tts_orchestrator.dart';

// Voice-reply ASR (S4 — record pkg push-to-talk → parent Whisper endpoint)
import 'package:record/record.dart';
import '../../services/asr/asr_service.dart';
import '../../features/quick_ask/domain/quick_ask_bloc.dart';

// Legacy voice/audio/TTS/use-case-registry stack is disabled — the code in
// lib/core/repositories/impl/{voice,audio}_repository_impl.dart and
// lib/features/{voice,audio,session}/use_cases/ references symbols that don't
// exist (TtsService, interfaces/*.dart, model fields). Tree-shaker skips these
// files as long as nothing imports them from the active graph. If we ever need
// voice/TTS again, fix those files first, then re-import here.

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

  /// PRODUCTION construction of [FocusChatBloc], extracted from its
  /// registration so a test can exercise the real wiring without booting the
  /// whole locator — [init] needs `path_provider` platform channels, which is
  /// why the DI suite is quarantined and why bug 9adff476 survived so long
  /// unseen. This is the ONLY place `isQuickAskJob` is supplied.
  ///
  /// Requires:
  ///   - NotificationRepository, TtsOrchestrator and NotificationStopList are
  ///     registered; QuickAskBloc is registered before the returned bloc's
  ///     probe is CALLED (not before it is built)
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
    // Setter 1 of the two-setter verbatim contract (rnd 2026.08.29 §71).
    // Without it `_isQuickAskJob` is null, shouldSpeakVerbatim short-circuits
    // at speech_intent.dart:83, and the answer the user ASKED for is cut to
    // `ttsFraction` — or, with `speakSystemSenders` off, never spoken at all.
    // Resolved through a closure, NOT a tear-off: QuickAskBloc is registered
    // AFTER this one, so the lookup must defer to call time.
    isQuickAskJob : ( jobId ) => _getIt<QuickAskBloc>().isQuickAskJob( jobId ),
  );

  /// PRODUCTION construction of [FleetStatusBloc] — a NEW bloc every call, and
  /// that is the point.
  ///
  /// 🔴 DELIBERATELY NOT REGISTERED AS A SINGLETON, unlike every sibling bloc
  /// in [_initializeBLoCs]. A pane bloc registered at the app root outlives its
  /// route and keeps its 60-second poller running against a destination nobody
  /// is looking at; five panes built that way means five timers at once, and
  /// the obvious test — *"polling stops when backgrounded"* — passes with all
  /// five running. Route-scoping IS the zero-request guard: a pane the operator
  /// has not opened has no bloc and cannot issue a request, and a pane they
  /// left is disposed, which cancels the timer AND the in-flight request.
  ///
  /// Requires:
  ///   - FleetRepository is registered
  ///
  /// Ensures:
  ///   - returns a fresh FleetStatusBloc over the registered repository
  ///   - the caller owns closing it (the route's BlocProvider does)
  ///
  /// NOT `@visibleForTesting`, unlike [buildFocusChatBloc]: that one is called
  /// from inside this file and exposed only so a test can see it, while this one
  /// is PRODUCTION's construction path — the home screen's route calls it.
  static FleetStatusBloc buildFleetStatusBloc() =>
      FleetStatusBloc( _getIt<FleetRepository>() );

  /// PRODUCTION construction of the three remaining pane blocs — a NEW bloc every
  /// call, for the same reason [buildFleetStatusBloc] is.
  ///
  /// 🔴 ROUTE-SCOPED BECAUSE THEY POLL. `TaskListBloc` and `HoldingAreaBloc` carry
  /// `PanePollingMixin`; an app-root instance keeps its timer running against a
  /// destination nobody is looking at, and five panes built that way means five
  /// timers at once. Route-scoping IS the zero-request guard.
  ///
  /// ⚠️ NOTE THE CONTRAST WITH [BroadcastBloc], which IS app-root. That is not an
  /// inconsistency: Broadcast has no poller, and its acks arrive on a socket frame
  /// that only `app.dart` can route — so it must exist for `app.dart` to see, and
  /// its tally must survive leaving the pane. The rule is "scope a pane bloc to its
  /// route unless something outside the route must reach it", not "always route-scope".
  static TaskListBloc buildTaskListBloc() => TaskListBloc(
    _getIt<TaskListRepository>(),
    _getIt<TaskWriteRepository>(),
  );

  static HoldingAreaBloc buildHoldingAreaBloc() => HoldingAreaBloc(
    _getIt<HoldingAreaRepository>(),
    _getIt<TaskWriteRepository>(),
  );

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

  /// PRODUCTION construction + registration of the shared [Dio], extracted
  /// so a test can exercise the real wiring without booting the whole
  /// locator (see [buildFocusChatBloc] for why).
  ///
  /// HttpService stamps `options.baseUrl` once at start-up and AuthRepository
  /// posts relative paths ("/auth/login"), so without this listener a switch
  /// to LAN DEV would keep signing in against the old host while WebSocket
  /// code (reading AppConstants) followed the new one.
  ///
  /// The baseUrl is ALSO stamped here, at start-up. Waiting for HttpService's
  /// constructor to do it leaves this Dio on an empty baseUrl for the whole
  /// stretch of `_initializeServices` where AuthRepository and AuthInterceptor
  /// are already holding it — a relative "/auth/login" posted in that window
  /// goes nowhere. Cold start with LAN DEV saved must reach the LAN host
  /// without depending on registration order.
  ///
  /// Requires:
  ///   - no Dio is registered yet
  ///
  /// Ensures:
  ///   - a Dio is registered in GetIt and returned
  ///   - its `options.baseUrl` is the SAVED context's baseUrl before this
  ///     method returns
  ///   - its `options.baseUrl` is the new context's baseUrl after every
  ///     [ServerContextService.setActive] switch
  @visibleForTesting
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

    // Tier 2 data layer — typed repos over the shared Dio (auth interceptor
    // injects Bearer token automatically).
    _getIt.registerSingleton<NotificationRepository>(
      NotificationRepository(_getIt<Dio>()),
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
    _getIt.registerSingleton<NotificationAudioService>(
      NotificationAudioService(prefs: _getIt<NotificationPreferences>()),
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

  /// Initialize repositories (legacy user/session/job/voice/audio stack is
  /// disabled — see note on removed imports above).
  static Future<void> _initializeRepositories() async {
    // Tier 1-4 repositories are registered in _initializeServices() alongside
    // the Dio they depend on. Nothing left to do here.
  }

  /// Initialize use cases (legacy UseCaseRegistry disabled — broken).
  static Future<void> _initializeUseCases() async {
    // No active use cases. Legacy voice/session use-cases stay on disk but
    // are not compiled because nothing imports them.
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
        audio : _getIt<NotificationAudioService>(),
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

  /// Checks whether service of specified type is registered.
  /// 
  /// Requires:
  ///   - Type T must be a valid object type
  /// 
  /// Ensures:
  ///   - Returns true if service is registered, false otherwise
  ///   - Check is performed without side effects
  ///   - No exceptions are thrown for unregistered types
  /// 
  /// Raises:
  ///   - No exceptions are raised (always returns boolean)
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

  /// Retrieves comprehensive status of all registered services.
  /// 
  /// Requires:
  ///   - Service locator must be accessible (initialization not required)
  /// 
  /// Ensures:
  ///   - Returns map of service names to registration status
  ///   - Includes core services, network services, repositories, and BLoCs
  ///   - Status accurately reflects current registration state
  ///   - Useful for debugging and health monitoring
  /// 
  /// Raises:
  ///   - No exceptions are raised (always returns valid map)
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