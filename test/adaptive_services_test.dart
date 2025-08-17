import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import '../lib/services/network/network_connectivity_service.dart';
import '../lib/services/lifecycle/app_lifecycle_service.dart';
import '../lib/services/adaptive/adaptive_connection_manager.dart';

void main() {
  group('Adaptive Services Tests', () {
    late NetworkConnectivityService networkService;
    late AppLifecycleService lifecycleService;
    late AdaptiveConnectionManager adaptiveManager;
    
    setUp(() {
      // Ensure Flutter binding is initialized for lifecycle service
      WidgetsFlutterBinding.ensureInitialized();
      
      networkService = NetworkConnectivityService();
      lifecycleService = AppLifecycleService();
      adaptiveManager = AdaptiveConnectionManager();
    });
    
    tearDown(() async {
      networkService.dispose();
      lifecycleService.dispose();
      adaptiveManager.dispose();
    });
    
    group('NetworkConnectivityService', () {
      test('should create service instance', () {
        expect(networkService, isNotNull);
        expect(networkService.currentState, equals(NetworkState.unknown));
        expect(networkService.currentQuality, equals(ConnectionQuality.unknown));
      });
      
      test('should provide network info', () {
        final info = networkService.getNetworkInfo();
        expect(info, isA<Map<String, dynamic>>());
        expect(info['state'], isNotNull);
        expect(info['quality'], isNotNull);
        expect(info['connectivity_type'], isNotNull);
      });
      
      test('should generate connection strategy', () {
        final strategy = networkService.getConnectionStrategy();
        expect(strategy, isA<WebSocketConnectionStrategy>());
        expect(strategy.reconnectDelay, isA<Duration>());
        expect(strategy.maxReconnectAttempts, isA<int>());
        expect(strategy.pingInterval, isA<Duration>());
      });
    });
    
    group('AppLifecycleService', () {
      test('should create service instance', () {
        expect(lifecycleService, isNotNull);
        expect(lifecycleService.currentLifecycleState, equals(AppLifecycleState.resumed));
        expect(lifecycleService.currentUsageState, equals(AppUsageState.active));
      });
      
      test('should track user interaction', () {
        expect(lifecycleService.isUserActive, isTrue);
        
        lifecycleService.recordUserInteraction();
        expect(lifecycleService.currentUsageState, equals(AppUsageState.active));
      });
      
      test('should provide usage statistics', () {
        final stats = lifecycleService.getUsageStatistics();
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['current_lifecycle_state'], isNotNull);
        expect(stats['current_usage_state'], isNotNull);
        expect(stats['session_duration_minutes'], isA<int>());
      });
      
      test('should generate app state connection strategy', () {
        final strategy = lifecycleService.getConnectionStrategy();
        expect(strategy, isA<AppStateConnectionStrategy>());
        expect(strategy.maintainConnection, isA<bool>());
        expect(strategy.enableHeartbeat, isA<bool>());
        expect(strategy.heartbeatInterval, isA<Duration>());
      });
    });
    
    group('AdaptiveConnectionManager', () {
      test('should create manager instance', () {
        expect(adaptiveManager, isNotNull);
        expect(adaptiveManager.currentStrategy, equals(AdaptiveStrategy.standard));
        expect(adaptiveManager.currentOptimization, equals(ConnectionOptimization.balanced));
      });
      
      test('should provide connection configuration', () {
        final config = adaptiveManager.getConnectionConfig();
        expect(config, isA<AdaptiveConnectionConfig>());
        expect(config.strategy, isA<AdaptiveStrategy>());
        expect(config.optimization, isA<ConnectionOptimization>());
        expect(config.reconnectDelay, isA<Duration>());
        expect(config.maxReconnectAttempts, isA<int>());
      });
      
      test('should provide adaptation analytics', () {
        final analytics = adaptiveManager.getAdaptationAnalytics();
        expect(analytics, isA<Map<String, dynamic>>());
        expect(analytics['current_strategy'], isNotNull);
        expect(analytics['current_optimization'], isNotNull);
        expect(analytics['network_info'], isA<Map<String, dynamic>>());
        expect(analytics['lifecycle_info'], isA<Map<String, dynamic>>());
      });
      
      test('should force strategy update', () {
        final initialStrategy = adaptiveManager.currentStrategy;
        adaptiveManager.forceStrategyUpdate();
        // Strategy might not change but method should not throw
        expect(adaptiveManager.currentStrategy, isA<AdaptiveStrategy>());
      });
    });
    
    group('Enums and Data Classes', () {
      test('should create WebSocketConnectionStrategy', () {
        const strategy = WebSocketConnectionStrategy(
          reconnectDelay: Duration(seconds: 2),
          maxReconnectAttempts: 5,
          pingInterval: Duration(seconds: 30),
          enableKeepalive: true,
          bufferSize: 8192,
          enableCompression: true,
        );
        
        expect(strategy.reconnectDelay, equals(const Duration(seconds: 2)));
        expect(strategy.maxReconnectAttempts, equals(5));
        expect(strategy.enableKeepalive, isTrue);
        expect(strategy.toString(), contains('WebSocketConnectionStrategy'));
      });
      
      test('should create AppStateConnectionStrategy', () {
        const strategy = AppStateConnectionStrategy(
          maintainConnection: true,
          enableHeartbeat: true,
          heartbeatInterval: Duration(minutes: 1),
          reconnectImmediately: true,
          maxConcurrentConnections: 2,
          enableAudioStreaming: true,
          bufferAudioInBackground: false,
        );
        
        expect(strategy.maintainConnection, isTrue);
        expect(strategy.enableHeartbeat, isTrue);
        expect(strategy.maxConcurrentConnections, equals(2));
        expect(strategy.toString(), contains('AppStateConnectionStrategy'));
      });
      
      test('should create AdaptiveConnectionConfig', () {
        final config = AdaptiveConnectionConfig(
          reconnectDelay: const Duration(seconds: 2),
          maxReconnectAttempts: 5,
          pingInterval: const Duration(seconds: 30),
          enableKeepalive: true,
          enableCompression: true,
          bufferSize: 8192,
          maintainConnection: true,
          enableAudioStreaming: true,
          bufferAudioInBackground: false,
          maxConcurrentConnections: 2,
          strategy: AdaptiveStrategy.standard,
          optimization: ConnectionOptimization.balanced,
          adaptationTimestamp: DateTime.now(),
        );
        
        expect(config.strategy, equals(AdaptiveStrategy.standard));
        expect(config.optimization, equals(ConnectionOptimization.balanced));
        expect(config.maintainConnection, isTrue);
        expect(config.toString(), contains('AdaptiveConnectionConfig'));
      });
      
      test('should handle NetworkState enum values', () {
        expect(NetworkState.values.length, equals(4));
        expect(NetworkState.unknown.toString(), contains('unknown'));
        expect(NetworkState.connected.toString(), contains('connected'));
      });
      
      test('should handle ConnectionQuality enum values', () {
        expect(ConnectionQuality.values.length, equals(6));
        expect(ConnectionQuality.excellent.toString(), contains('excellent'));
        expect(ConnectionQuality.poor.toString(), contains('poor'));
      });
      
      test('should handle AdaptiveStrategy enum values', () {
        expect(AdaptiveStrategy.values.length, equals(7));
        expect(AdaptiveStrategy.aggressive.toString(), contains('aggressive'));
        expect(AdaptiveStrategy.powerSaver.toString(), contains('powerSaver'));
      });
      
      test('should handle ConnectionOptimization enum values', () {
        expect(ConnectionOptimization.values.length, equals(4));
        expect(ConnectionOptimization.performance.toString(), contains('performance'));
        expect(ConnectionOptimization.batterySaver.toString(), contains('batterySaver'));
      });
      
      test('should handle AppUsageState enum values', () {
        expect(AppUsageState.values.length, equals(6));
        expect(AppUsageState.active.toString(), contains('active'));
        expect(AppUsageState.shutdown.toString(), contains('shutdown'));
      });
    });
  });
}