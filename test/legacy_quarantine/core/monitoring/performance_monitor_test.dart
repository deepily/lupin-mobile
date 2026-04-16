import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:lupin_mobile/core/monitoring/performance_monitor.dart';
import 'package:lupin_mobile/core/monitoring/monitoring_models.dart';
import 'package:lupin_mobile/core/storage/storage_manager.dart';

// Generate mocks
@GenerateMocks([StorageManager])
import 'performance_monitor_test.mocks.dart';

void main() {
  group('PerformanceMonitor Tests', () {
    late PerformanceMonitor monitor;
    late MockStorageManager mockStorage;

    setUp(() async {
      mockStorage = MockStorageManager();
      
      // Mock storage responses
      when(mockStorage.getString(any)).thenReturn(null);
      when(mockStorage.setString(any, any)).thenAnswer((_) async => true);
      
      monitor = await PerformanceMonitor.getInstance(
        config: PerformanceMonitorConfig.development(),
      );
    });

    tearDown(() {
      monitor.dispose();
    });

    group('Initialization and Lifecycle', () {
      test('should initialize with default configuration', () async {
        final defaultMonitor = await PerformanceMonitor.getInstance();
        expect(defaultMonitor, isNotNull);
      });

      test('should start monitoring successfully', () async {
        await monitor.startMonitoring();
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.isMonitoring, isTrue);
        expect(summary.uptime.inSeconds, greaterThan(0));
      });

      test('should stop monitoring successfully', () async {
        await monitor.startMonitoring();
        await monitor.stopMonitoring();
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.isMonitoring, isFalse);
      });

      test('should handle multiple start/stop cycles', () async {
        for (int i = 0; i < 3; i++) {
          await monitor.startMonitoring();
          expect(monitor.getPerformanceSummary().isMonitoring, isTrue);
          
          await monitor.stopMonitoring();
          expect(monitor.getPerformanceSummary().isMonitoring, isFalse);
        }
      });
    });

    group('Event Recording', () {
      test('should record performance events', () async {
        await monitor.startMonitoring();
        
        final event = PerformanceEvent(
          name: 'test_operation',
          category: 'test',
          duration: const Duration(milliseconds: 100),
          metadata: {'key': 'value'},
        );
        
        monitor.recordEvent(event);
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
      });

      test('should limit events per category', () async {
        await monitor.startMonitoring();
        
        // Record more events than the limit
        for (int i = 0; i < 2500; i++) {
          monitor.recordEvent(PerformanceEvent(
            name: 'test_$i',
            category: 'test',
          ));
        }
        
        final analytics = monitor.getAnalytics(categories: ['test']);
        expect(analytics.eventBreakdown['test']!.totalEvents, 
               lessThanOrEqualTo(2000));
      });

      test('should handle events with no duration', () async {
        await monitor.startMonitoring();
        
        final event = PerformanceEvent(
          name: 'instant_operation',
          category: 'test',
        );
        
        monitor.recordEvent(event);
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
      });

      test('should handle events with metadata', () async {
        await monitor.startMonitoring();
        
        final event = PerformanceEvent(
          name: 'complex_operation',
          category: 'test',
          metadata: {
            'user_id': 'test_user',
            'operation_type': 'sync',
            'data_size': 1024,
          },
        );
        
        monitor.recordEvent(event);
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
      });
    });

    group('Performance Timer', () {
      test('should create and use performance timer', () async {
        await monitor.startMonitoring();
        
        final timer = monitor.startTimer('timed_operation', category: 'test');
        
        // Simulate some work
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Monitor for the event
        monitor.getPerformanceSummary(); // This would show the event after stop()
        
        timer.stop();
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
      });

      test('should add metadata to timer', () async {
        await monitor.startMonitoring();
        
        final timer = monitor.startTimer('metadata_operation', category: 'test');
        timer.addMetadata('key1', 'value1');
        timer.addMetadata('key2', 42);
        
        await Future.delayed(const Duration(milliseconds: 5));
        timer.stop();
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
      });
    });

    group('Network Request Monitoring', () {
      test('should record successful network request', () async {
        await monitor.startMonitoring();
        
        monitor.recordNetworkRequest(
          url: 'https://api.example.com/data',
          method: 'GET',
          statusCode: 200,
          duration: const Duration(milliseconds: 150),
          requestBytes: 100,
          responseBytes: 500,
        );
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.networkRequests.totalRequests, equals(1));
        expect(summary.networkRequests.failedRequests, equals(0));
        expect(summary.networkRequests.successRate, equals(1.0));
      });

      test('should record failed network request', () async {
        await monitor.startMonitoring();
        
        monitor.recordNetworkRequest(
          url: 'https://api.example.com/data',
          method: 'POST',
          statusCode: 500,
          duration: const Duration(milliseconds: 200),
          error: 'Internal server error',
        );
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.networkRequests.totalRequests, equals(1));
        expect(summary.networkRequests.failedRequests, equals(1));
        expect(summary.networkRequests.successRate, equals(0.0));
      });

      test('should track multiple hosts separately', () async {
        await monitor.startMonitoring();
        
        monitor.recordNetworkRequest(
          url: 'https://api1.example.com/data',
          method: 'GET',
          statusCode: 200,
          duration: const Duration(milliseconds: 100),
        );
        
        monitor.recordNetworkRequest(
          url: 'https://api2.example.com/data',
          method: 'GET',
          statusCode: 200,
          duration: const Duration(milliseconds: 150),
        );
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.networkRequests.hosts, hasLength(2));
        expect(summary.networkRequests.hosts, contains('api1.example.com'));
        expect(summary.networkRequests.hosts, contains('api2.example.com'));
      });

      test('should generate slow network alert', () async {
        await monitor.startMonitoring();
        
        final alerts = <PerformanceAlert>[];
        monitor.alerts.listen(alerts.add);
        
        monitor.recordNetworkRequest(
          url: 'https://slow.example.com/data',
          method: 'GET',
          statusCode: 200,
          duration: const Duration(milliseconds: 5000), // Exceeds threshold
        );
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(alerts, isNotEmpty);
        expect(alerts.first.level, equals(AlertLevel.warning));
        expect(alerts.first.message, contains('Slow network request'));
      });
    });

    group('Memory and CPU Monitoring', () {
      test('should record memory usage', () async {
        await monitor.startMonitoring();
        
        monitor.recordMemoryUsage(100 * 1024 * 1024); // 100MB
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.memoryUsageMB, equals(100.0));
      });

      test('should record CPU usage', () async {
        await monitor.startMonitoring();
        
        monitor.recordCpuUsage(75.0);
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.cpuUsagePercent, equals(75.0));
      });

      test('should generate high memory alert', () async {
        await monitor.startMonitoring();
        
        final alerts = <PerformanceAlert>[];
        monitor.alerts.listen(alerts.add);
        
        monitor.recordMemoryUsage(600 * 1024 * 1024); // 600MB (exceeds threshold)
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(alerts, isNotEmpty);
        expect(alerts.first.level, equals(AlertLevel.warning));
        expect(alerts.first.message, contains('High memory usage'));
      });

      test('should generate high CPU alert', () async {
        await monitor.startMonitoring();
        
        final alerts = <PerformanceAlert>[];
        monitor.alerts.listen(alerts.add);
        
        monitor.recordCpuUsage(90.0); // Exceeds threshold
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(alerts, isNotEmpty);
        expect(alerts.first.level, equals(AlertLevel.warning));
        expect(alerts.first.message, contains('High CPU usage'));
      });
    });

    group('Custom Metrics', () {
      test('should add and track custom metrics', () async {
        await monitor.startMonitoring();
        
        monitor.addCustomMetric('cache_hit_rate', 85.5, unit: 'percent');
        monitor.addCustomMetric('queue_size', 10, unit: 'items');
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.customMetrics, hasLength(2));
        expect(summary.customMetrics['cache_hit_rate'], isNotNull);
        expect(summary.customMetrics['queue_size'], isNotNull);
      });

      test('should increment counter metrics', () async {
        await monitor.startMonitoring();
        
        monitor.incrementCounter('api_calls');
        monitor.incrementCounter('api_calls', value: 5);
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.customMetrics['api_calls'], isNotNull);
      });

      test('should record gauge metrics', () async {
        await monitor.startMonitoring();
        
        monitor.recordGauge('temperature', 72.5, unit: 'celsius');
        monitor.recordGauge('temperature', 73.0, unit: 'celsius');
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.customMetrics['temperature'], isNotNull);
      });
    });

    group('Analytics and Reporting', () {
      test('should generate performance analytics', () async {
        await monitor.startMonitoring();
        
        // Record some test events
        for (int i = 0; i < 10; i++) {
          monitor.recordEvent(PerformanceEvent(
            name: 'test_operation_$i',
            category: 'test',
            duration: Duration(milliseconds: 100 + i * 10),
          ));
        }
        
        final analytics = monitor.getAnalytics();
        
        expect(analytics.categories, contains('test'));
        expect(analytics.eventBreakdown['test']!.totalEvents, equals(10));
        expect(analytics.eventBreakdown['test']!.averageDurationMs, 
               greaterThan(100));
      });

      test('should filter analytics by time window', () async {
        await monitor.startMonitoring();
        
        // Record an old event
        monitor.recordEvent(PerformanceEvent(
          name: 'old_operation',
          category: 'test',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ));
        
        // Record a recent event
        monitor.recordEvent(PerformanceEvent(
          name: 'recent_operation',
          category: 'test',
        ));
        
        final analytics = monitor.getAnalytics(
          timeWindow: const Duration(minutes: 30),
        );
        
        // Should only include recent event
        expect(analytics.eventBreakdown['test']!.totalEvents, equals(1));
      });

      test('should filter analytics by categories', () async {
        await monitor.startMonitoring();
        
        monitor.recordEvent(PerformanceEvent(
          name: 'operation1',
          category: 'category1',
        ));
        
        monitor.recordEvent(PerformanceEvent(
          name: 'operation2',
          category: 'category2',
        ));
        
        final analytics = monitor.getAnalytics(
          categories: ['category1'],
        );
        
        expect(analytics.categories, equals(['category1']));
        expect(analytics.eventBreakdown, hasLength(1));
      });

      test('should export performance data', () async {
        await monitor.startMonitoring();
        
        monitor.recordEvent(PerformanceEvent(
          name: 'test_operation',
          category: 'test',
        ));
        
        final exportedData = await monitor.exportData();
        
        expect(exportedData, isNotEmpty);
        expect(exportedData, contains('export_timestamp'));
      });
    });

    group('Alert System', () {
      test('should emit alerts for slow operations', () async {
        await monitor.startMonitoring();
        
        final alerts = <PerformanceAlert>[];
        monitor.alerts.listen(alerts.add);
        
        monitor.recordEvent(PerformanceEvent(
          name: 'slow_operation',
          category: 'test',
          duration: const Duration(milliseconds: 2000), // Exceeds threshold
        ));
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(alerts, isNotEmpty);
        expect(alerts.first.level, equals(AlertLevel.warning));
        expect(alerts.first.message, contains('Slow operation'));
      });

      test('should emit alerts for error events', () async {
        await monitor.startMonitoring();
        
        final alerts = <PerformanceAlert>[];
        monitor.alerts.listen(alerts.add);
        
        monitor.recordEvent(PerformanceEvent(
          name: 'error_operation',
          category: 'test',
          metadata: {'error': 'Something went wrong'},
        ));
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(alerts, isNotEmpty);
        expect(alerts.first.level, equals(AlertLevel.error));
        expect(alerts.first.message, contains('Error event'));
      });
    });

    group('Data Management', () {
      test('should clear all performance data', () async {
        await monitor.startMonitoring();
        
        // Add some data
        monitor.recordEvent(PerformanceEvent(
          name: 'test_operation',
          category: 'test',
        ));
        monitor.addCustomMetric('test_metric', 42.0);
        
        // Clear data
        monitor.clearData();
        
        final summary = monitor.getPerformanceSummary();
        expect(summary.totalEvents, equals(0));
        expect(summary.customMetrics, isEmpty);
      });

      test('should get current system stats', () async {
        monitor.recordMemoryUsage(200 * 1024 * 1024); // 200MB
        monitor.recordCpuUsage(60.0);
        
        final systemStats = await monitor.getCurrentSystemStats();
        
        expect(systemStats.memoryUsageMB, equals(200.0));
        expect(systemStats.cpuUsagePercent, equals(60.0));
        expect(systemStats.platformInfo, isNotEmpty);
      });
    });

    group('Configuration', () {
      test('should use production configuration', () async {
        final prodMonitor = await PerformanceMonitor.getInstance(
          config: PerformanceMonitorConfig.production(),
        );
        
        expect(prodMonitor, isNotNull);
        prodMonitor.dispose();
      });

      test('should use development configuration', () async {
        final devMonitor = await PerformanceMonitor.getInstance(
          config: PerformanceMonitorConfig.development(),
        );
        
        expect(devMonitor, isNotNull);
        devMonitor.dispose();
      });

      test('should respect custom configuration', () async {
        const customConfig = PerformanceMonitorConfig(
          enableSystemMonitoring: false,
          slowOperationThresholdMs: 2000,
          maxEventsPerCategory: 500,
        );
        
        final customMonitor = await PerformanceMonitor.getInstance(
          config: customConfig,
        );
        
        expect(customMonitor, isNotNull);
        customMonitor.dispose();
      });
    });
  });

  group('PerformanceEvent Tests', () {
    test('should create event with default timestamp', () {
      final event = PerformanceEvent(
        name: 'test_event',
        category: 'test',
      );
      
      expect(event.name, equals('test_event'));
      expect(event.category, equals('test'));
      expect(event.timestamp, isNotNull);
    });

    test('should create event with custom timestamp', () {
      final customTime = DateTime.now().subtract(const Duration(minutes: 5));
      final event = PerformanceEvent(
        name: 'test_event',
        category: 'test',
        timestamp: customTime,
      );
      
      expect(event.timestamp, equals(customTime));
    });

    test('should serialize to JSON correctly', () {
      final event = PerformanceEvent(
        name: 'test_event',
        category: 'test',
        duration: const Duration(milliseconds: 100),
        metadata: {'key': 'value'},
      );
      
      final json = event.toJson();
      
      expect(json['name'], equals('test_event'));
      expect(json['category'], equals('test'));
      expect(json['duration_ms'], equals(100));
      expect(json['metadata']['key'], equals('value'));
    });
  });

  group('PerformanceTimer Tests', () {
    test('should measure operation duration', () async {
      final events = <PerformanceEvent>[];
      
      final timer = PerformanceTimer(
        operation: 'test_operation',
        category: 'test',
        onComplete: events.add,
      );
      
      await Future.delayed(const Duration(milliseconds: 10));
      timer.stop();
      
      expect(events, hasLength(1));
      expect(events.first.name, equals('test_operation'));
      expect(events.first.category, equals('test'));
      expect(events.first.duration!.inMilliseconds, greaterThanOrEqualTo(8));
    });

    test('should include metadata in event', () async {
      final events = <PerformanceEvent>[];
      
      final timer = PerformanceTimer(
        operation: 'test_operation',
        category: 'test',
        onComplete: events.add,
      );
      
      timer.addMetadata('key1', 'value1');
      timer.addMetadata('key2', 42);
      timer.stop();
      
      expect(events, hasLength(1));
      expect(events.first.metadata!['key1'], equals('value1'));
      expect(events.first.metadata!['key2'], equals(42));
    });
  });

  group('PerformanceMetrics Tests', () {
    test('should track events correctly', () {
      final metrics = PerformanceMetrics(category: 'test');
      
      metrics.addEvent(PerformanceEvent(
        name: 'event1',
        category: 'test',
        duration: const Duration(milliseconds: 100),
      ));
      
      metrics.addEvent(PerformanceEvent(
        name: 'event2',
        category: 'test',
        duration: const Duration(milliseconds: 200),
      ));
      
      expect(metrics.eventCount, equals(2));
      expect(metrics.averageDurationMs, equals(150.0));
      expect(metrics.minDurationMs, equals(100.0));
      expect(metrics.maxDurationMs, equals(200.0));
    });

    test('should track error events', () {
      final metrics = PerformanceMetrics(category: 'test');
      
      metrics.addEvent(PerformanceEvent(
        name: 'success_event',
        category: 'test',
      ));
      
      metrics.addEvent(PerformanceEvent(
        name: 'error_event',
        category: 'test',
        metadata: {'error': 'Something failed'},
      ));
      
      expect(metrics.eventCount, equals(2));
      expect(metrics.errorCount, equals(1));
      expect(metrics.errorRate, equals(0.5));
    });

    test('should serialize to JSON correctly', () {
      final metrics = PerformanceMetrics(category: 'test');
      
      metrics.addEvent(PerformanceEvent(
        name: 'event1',
        category: 'test',
        duration: const Duration(milliseconds: 100),
      ));
      
      final json = metrics.toJson();
      
      expect(json['category'], equals('test'));
      expect(json['event_count'], equals(1));
      expect(json['average_duration_ms'], equals(100.0));
    });
  });
}