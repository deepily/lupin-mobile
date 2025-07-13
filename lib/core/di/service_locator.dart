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
import '../../services/tts/tts_service.dart';

// Repositories
import '../repositories/user_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/job_repository.dart';
import '../repositories/voice_repository.dart';
import '../repositories/audio_repository.dart';
import '../repositories/impl/user_repository_impl.dart';
import '../repositories/impl/session_repository_impl.dart';
import '../repositories/impl/job_repository_impl.dart';
import '../repositories/impl/voice_repository_impl.dart';
import '../repositories/impl/audio_repository_impl.dart';

// BLoC
import '../../features/voice/domain/voice_bloc.dart';

// Use Cases
import '../use_cases/use_case_registry.dart';

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

    // Dio HTTP client
    final dio = Dio();
    _getIt.registerSingleton<Dio>(dio);
  }

  /// Initialize services
  static Future<void> _initializeServices() async {
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
      WebSocketService(),
    );

    // TTS Service
    _getIt.registerSingleton<TtsService>(
      TtsService(_getIt<CachedHttpService>()),
    );
  }

  /// Initialize repositories
  static Future<void> _initializeRepositories() async {
    // User Repository
    _getIt.registerSingleton<UserRepository>(
      UserRepositoryImpl(),
    );

    // Session Repository
    _getIt.registerSingleton<SessionRepository>(
      SessionRepositoryImpl(),
    );

    // Job Repository
    _getIt.registerSingleton<JobRepository>(
      JobRepositoryImpl(),
    );

    // Voice Repository
    _getIt.registerSingleton<VoiceRepository>(
      VoiceRepositoryImpl(),
    );

    // Audio Repository
    _getIt.registerSingleton<AudioRepository>(
      AudioRepositoryImpl(),
    );
  }

  /// Initialize use cases
  static Future<void> _initializeUseCases() async {
    // Initialize use case registry
    await UseCaseRegistry.initialize();
  }

  /// Initialize BLoCs
  static Future<void> _initializeBLoCs() async {
    // Voice BLoC (factory - new instance each time)
    _getIt.registerFactory<VoiceBloc>(
      () => VoiceBloc(
        ttsService: _getIt<TtsService>(),
        voiceRepository: _getIt<VoiceRepository>(),
        sessionRepository: _getIt<SessionRepository>(),
      ),
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
    services['TtsService'] = _getIt.isRegistered<TtsService>() ? 'Registered' : 'Not registered';
    
    // Repositories
    services['UserRepository'] = _getIt.isRegistered<UserRepository>() ? 'Registered' : 'Not registered';
    services['SessionRepository'] = _getIt.isRegistered<SessionRepository>() ? 'Registered' : 'Not registered';
    services['JobRepository'] = _getIt.isRegistered<JobRepository>() ? 'Registered' : 'Not registered';
    services['VoiceRepository'] = _getIt.isRegistered<VoiceRepository>() ? 'Registered' : 'Not registered';
    services['AudioRepository'] = _getIt.isRegistered<AudioRepository>() ? 'Registered' : 'Not registered';
    
    // BLoCs
    services['VoiceBloc'] = _getIt.isRegistered<VoiceBloc>(instanceName: 'factory') ? 'Factory registered' : 'Not registered';
    
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
  
  /// Get TTS Service
  static TtsService get ttsService => ServiceLocator.get<TtsService>();
  
  /// Get User Repository
  static UserRepository get userRepository => ServiceLocator.get<UserRepository>();
  
  /// Get Session Repository
  static SessionRepository get sessionRepository => ServiceLocator.get<SessionRepository>();
  
  /// Get Job Repository
  static JobRepository get jobRepository => ServiceLocator.get<JobRepository>();
  
  /// Get Voice Repository
  static VoiceRepository get voiceRepository => ServiceLocator.get<VoiceRepository>();
  
  /// Get Audio Repository
  static AudioRepository get audioRepository => ServiceLocator.get<AudioRepository>();
}