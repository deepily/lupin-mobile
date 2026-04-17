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
import '../../features/notifications/data/notification_repository.dart';
import '../../features/decision_proxy/data/decision_proxy_repository.dart';

// Tier 2 BLoCs
import '../../features/notifications/domain/notification_bloc.dart';
import '../../features/decision_proxy/domain/decision_proxy_bloc.dart';

// Tier 3 data layer
import '../../features/queue/data/queue_repository.dart';
import '../../features/claude_code/data/claude_code_repository.dart';

// Tier 3 BLoCs
import '../../features/queue/domain/queue_bloc.dart';
import '../../features/claude_code/domain/claude_code_bloc.dart';

// Tier 4 data layer
import '../../features/agentic/data/agentic_repository.dart';
import '../../services/artifacts/io_file_service.dart';

// Tier 4 BLoCs
import '../../features/agentic/domain/agentic_submission_bloc.dart';

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

    // Dio HTTP client
    final dio = Dio();
    _getIt.registerSingleton<Dio>(dio);
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
    _getIt.registerLazySingleton<NotificationBloc>(
      () => NotificationBloc(_getIt<NotificationRepository>()),
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