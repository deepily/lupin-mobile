import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
import '../cache/cache_exports.dart';

/// Application class for managing app lifecycle and initialization
class Application {
  static bool _isInitialized = false;
  
  /// Initialize the application
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize dependency injection
      await ServiceLocator.init();
      
      // Initialize background services
      await _initializeBackgroundServices();
      
      // Setup global error handling
      _setupErrorHandling();
      
      _isInitialized = true;
      
      if (kDebugMode) {
        print('[Application] Initialization completed successfully');
        _printRegisteredServices();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Application] Initialization failed: $e');
      }
      rethrow;
    }
  }
  
  /// Initialize background services
  static Future<void> _initializeBackgroundServices() async {
    // Start listening to offline events
    final offlineManager = ServiceLocator.get<OfflineManager>();
    offlineManager.events.listen((event) {
      if (kDebugMode) {
        print('[Application] Offline event: ${event.runtimeType}');
      }
    });
    
    // Start listening to audio cache events
    final audioCache = ServiceLocator.get<AudioCache>();
    audioCache.events.listen((event) {
      if (kDebugMode) {
        print('[Application] Audio cache event: ${event.runtimeType}');
      }
    });
    
    // Start listening to network cache events  
    final networkCache = ServiceLocator.get<NetworkCache>();
    networkCache.events.listen((event) {
      if (kDebugMode) {
        print('[Application] Network cache event: ${event.runtimeType}');
      }
    });
  }
  
  /// Setup global error handling
  static void _setupErrorHandling() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        print('[Application] Flutter error: ${details.exception}');
        print('[Application] Stack trace: ${details.stack}');
      }
      // In production, you might want to send this to a crash reporting service
    };
    
    // Handle other errors
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        print('[Application] Platform error: $error');
        print('[Application] Stack trace: $stack');
      }
      // In production, you might want to send this to a crash reporting service
      return true;
    };
  }
  
  /// Print registered services (debug only)
  static void _printRegisteredServices() {
    if (!kDebugMode) return;
    
    print('[Application] Registered services:');
    final services = ServiceLocator.getRegisteredServices();
    services.forEach((name, status) {
      print('  $name: $status');
    });
  }
  
  /// Check if application is initialized
  static bool get isInitialized => _isInitialized;
  
  /// Dispose application resources
  static Future<void> dispose() async {
    try {
      // Dispose cache managers
      final audioCache = ServiceLocator.get<AudioCache>();
      audioCache.dispose();
      
      // Reset service locator
      await ServiceLocator.reset();
      
      _isInitialized = false;
      
      if (kDebugMode) {
        print('[Application] Resources disposed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Application] Error disposing resources: $e');
      }
    }
  }
  
  /// Get application statistics
  static Future<Map<String, dynamic>> getStats() async {
    if (!_isInitialized) {
      return {'error': 'Application not initialized'};
    }
    
    try {
      final offlineManager = ServiceLocator.get<OfflineManager>();
      final audioCache = ServiceLocator.get<AudioCache>();
      final networkCache = ServiceLocator.get<NetworkCache>();
      
      final offlineStats = await offlineManager.getOfflineStats();
      final audioStats = await audioCache.getStats();
      final networkStats = await networkCache.getStats();
      
      return {
        'initialized': _isInitialized,
        'offline_stats': offlineStats.toJson(),
        'audio_cache_stats': audioStats.toJson(),
        'network_cache_stats': networkStats.toJson(),
        'registered_services': ServiceLocator.getRegisteredServices(),
      };
    } catch (e) {
      return {'error': 'Failed to get stats: $e'};
    }
  }
  
  /// Health check
  static Future<Map<String, dynamic>> healthCheck() async {
    final health = <String, dynamic>{
      'initialized': _isInitialized,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    if (!_isInitialized) {
      health['status'] = 'not_initialized';
      return health;
    }
    
    try {
      // Check core services
      final storageManager = ServiceLocator.get<StorageManager>();
      final offlineManager = ServiceLocator.get<OfflineManager>();
      
      health['storage_keys'] = storageManager.getKeys().length;
      health['offline_status'] = offlineManager.isOnline ? 'online' : 'offline';
      health['queued_requests'] = offlineManager.getQueuedRequests().length;
      
      // Check HTTP service
      final httpService = ServiceLocator.get<CachedHttpService>();
      health['http_service'] = 'available';
      
      health['status'] = 'healthy';
    } catch (e) {
      health['status'] = 'error';
      health['error'] = e.toString();
    }
    
    return health;
  }
}