import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../lib/services/websocket/enhanced_websocket_service.dart';
import '../../lib/services/websocket/websocket_connection_manager.dart';
import '../../lib/services/websocket/websocket_message_router.dart';
import '../../lib/services/websocket/websocket_debug_monitor.dart';
import '../../lib/core/constants/app_constants.dart';
import '../mocks/mock_websocket_server.dart';
import '../helpers/mock_event_generators.dart';

void main() {
  group('WebSocket Performance Tests', () {
    late MockWebSocketServer mockServer;
    late WebSocketConnectionManager connectionManager;
    late WebSocketDebugMonitor debugMonitor;
    
    const String testUserId = 'perf_test_user';
    late String testSessionId;
    
    setUpAll(() async {
      // Start mock server with optimized settings
      mockServer = MockWebSocketServer(
        config: MockServerConfig(
          port: 8082,
          enableAutoEventGeneration: false, // Manual control for performance tests
          ttsGenerationDelay: 50, // Faster for testing
          audioChunkDelay: 10,
          enableAudioEcho: true,
        ),
      );
      await mockServer.start();
      print('[PerfTest] Mock server started on port 8082');
    });
    
    tearDownAll(() async {
      await mockServer.stop();
    });
    
    setUp(() async {
      testSessionId = MockEventGenerators.generateSessionId();
      
      // Create optimized connection for performance testing
      final webSocketService = EnhancedWebSocketService(Dio());
      final messageRouter = WebSocketMessageRouter();
      
      connectionManager = WebSocketConnectionManager(
        webSocketService: webSocketService,
        messageRouter: messageRouter,
        config: ConnectionManagerConfig(
          enableLogging: false, // Reduce overhead
          enableAnalytics: true,
          enableHealthChecks: false,
          maxMessagesPerMinute: 1000, // High limit for testing
        ),
      );
      
      debugMonitor = WebSocketDebugMonitor(
        connectionManager: connectionManager,
        config: DebugConfig(
          enableEventLogging: true,
          enablePerformanceMonitoring: true,
          enableConsoleLogging: false, // Reduce test output
          maxEventLogSize: 50000,
          eventBurstThreshold: 50,
        ),
      );
      
      webSocketService.setBaseUrl('ws://localhost:8082');
      await connectionManager.connect(userId: testUserId);
    });
    
    tearDown(() async {
      await connectionManager.disconnect();
      debugMonitor.dispose();
    });
    
    group('High-Frequency Event Handling', () {
      test('should handle 100+ events per second without degradation', () async {
        final receivedEvents = <dynamic>[];
        final processingTimes = <Duration>[];
        
        // Listen to all event streams
        final subscriptions = [
          connectionManager.queueUpdates.listen((event) {
            receivedEvents.add(event);
          }),
          connectionManager.notifications.listen((event) {
            receivedEvents.add(event);
          }),
          connectionManager.systemMessages.listen((event) {
            receivedEvents.add(event);
          }),
        ];
        
        const eventsPerSecond = 120;
        const testDurationSeconds = 5;
        const totalEvents = eventsPerSecond * testDurationSeconds;
        
        print('[PerfTest] Sending $totalEvents events over ${testDurationSeconds}s');
        
        final startTime = DateTime.now();
        var sentEvents = 0;
        
        // Send events at specified rate
        final timer = Timer.periodic(
          Duration(milliseconds: 1000 ~/ eventsPerSecond), 
          (timer) async {
            if (sentEvents >= totalEvents) {
              timer.cancel();
              return;
            }
            
            final eventStartTime = DateTime.now();
            
            // Alternate between different event types
            late Map<String, dynamic> event;
            switch (sentEvents % 3) {
              case 0:
                event = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
                break;
              case 1:
                event = MockEventGenerators.generateNotificationQueueUpdate(sessionId: testSessionId);
                break;
              case 2:
                event = MockEventGenerators.generateSystemTimeUpdate(sessionId: testSessionId);
                break;
            }
            
            await mockServer.sendToQueue(testSessionId, event);
            
            final eventEndTime = DateTime.now();
            processingTimes.add(eventEndTime.difference(eventStartTime));
            
            sentEvents++;
          },
        );
        
        // Wait for all events to be sent and processed
        await Future.delayed(Duration(seconds: testDurationSeconds + 2));
        
        final endTime = DateTime.now();
        final totalTime = endTime.difference(startTime);
        
        // Performance assertions
        expect(receivedEvents.length, greaterThanOrEqualTo(totalEvents * 0.95)); // 95% delivery rate
        expect(totalTime.inSeconds, lessThanOrEqualTo(testDurationSeconds + 3)); // Processing overhead
        
        // Calculate performance metrics
        final actualEventsPerSecond = receivedEvents.length / totalTime.inSeconds;
        final averageProcessingTime = processingTimes.isNotEmpty
            ? Duration(microseconds: 
                processingTimes.fold(0, (sum, dur) => sum + dur.inMicroseconds) ~/ processingTimes.length)
            : Duration.zero;
        
        print('[PerfTest] Actual events/sec: ${actualEventsPerSecond.toStringAsFixed(1)}');
        print('[PerfTest] Average processing time: ${averageProcessingTime.inMicroseconds}μs');
        print('[PerfTest] Total events received: ${receivedEvents.length}/$totalEvents');
        
        // Performance requirements
        expect(actualEventsPerSecond, greaterThanOrEqualTo(eventsPerSecond * 0.9));
        expect(averageProcessingTime.inMilliseconds, lessThan(10)); // < 10ms per event
        
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      });
      
      test('should handle sustained load over extended period', () async {
        final receivedEvents = <dynamic>[];
        final memorySnapshots = <int>[];
        
        // Monitor memory usage (simplified - would need actual memory profiling in real scenario)
        var eventCount = 0;
        
        final subscription = connectionManager.queueUpdates.listen((event) {
          receivedEvents.add(event);
          eventCount++;
          
          // Take memory snapshot every 100 events
          if (eventCount % 100 == 0) {
            memorySnapshots.add(debugMonitor.getDebugStatistics()['log_sizes']['event_log']);
          }
        });
        
        const eventsPerSecond = 50;
        const testDurationSeconds = 10; // Extended test
        const totalEvents = eventsPerSecond * testDurationSeconds;
        
        print('[PerfTest] Sustained load test: $totalEvents events over ${testDurationSeconds}s');
        
        final startTime = DateTime.now();
        
        // Generate sustained load
        for (int i = 0; i < totalEvents; i++) {
          final event = MockEventGenerators.generateQueueUpdate(
            sessionId: testSessionId,
            itemCount: 1,
          );
          
          await mockServer.sendToQueue(testSessionId, event);
          
          // Controlled rate
          if (i % eventsPerSecond == 0) {
            await Future.delayed(Duration(milliseconds: 1000));
          }
        }
        
        // Wait for processing to complete
        await Future.delayed(Duration(seconds: 2));
        
        final endTime = DateTime.now();
        final totalTime = endTime.difference(startTime);
        
        // Check for memory leaks (log size shouldn't grow unbounded)
        if (memorySnapshots.length > 1) {
          final memoryGrowth = memorySnapshots.last - memorySnapshots.first;
          final maxAllowedGrowth = totalEvents * 2; // Reasonable growth limit
          
          expect(memoryGrowth, lessThan(maxAllowedGrowth));
        }
        
        // Performance assertions
        expect(receivedEvents.length, greaterThanOrEqualTo(totalEvents * 0.95));
        expect(totalTime.inSeconds, lessThanOrEqualTo(testDurationSeconds + 5));
        
        print('[PerfTest] Sustained test completed: ${receivedEvents.length} events processed');
        print('[PerfTest] Memory growth: ${memorySnapshots.isNotEmpty ? memorySnapshots.last - memorySnapshots.first : 0} log entries');
        
        await subscription.cancel();
      });
    });
    
    group('Large Binary Data Transmission', () {
      test('should handle large audio chunks efficiently', () async {
        final audioChunks = <AudioChunkMessage>[];
        final transmissionTimes = <Duration>[];
        
        final subscription = connectionManager.audioChunks.listen((chunk) {
          audioChunks.add(chunk);
        });
        
        final largeSizes = [
          1024,   // 1KB
          4096,   // 4KB
          16384,  // 16KB
          65536,  // 64KB
          131072, // 128KB
        ];
        
        print('[PerfTest] Testing large binary data transmission');
        
        for (final size in largeSizes) {
          final startTime = DateTime.now();
          
          // Generate large audio chunk
          final audioData = MockEventGenerators.generateMockAudioData(size: size);
          
          // Send chunk metadata
          final chunkEvent = MockEventGenerators.generateAudioStreamingChunk(
            sessionId: testSessionId,
            sequenceNumber: 0,
            totalChunks: 1,
            isLastChunk: true,
          );
          
          await mockServer.sendToAudio(testSessionId, chunkEvent);
          await mockServer.sendBinaryToAudio(testSessionId, audioData);
          
          // Wait for transmission
          await Future.delayed(Duration(milliseconds: 100));
          
          final endTime = DateTime.now();
          transmissionTimes.add(endTime.difference(startTime));
          
          print('[PerfTest] Transmitted ${size} bytes in ${transmissionTimes.last.inMilliseconds}ms');
        }
        
        // Wait for all chunks to be processed
        await Future.delayed(Duration(milliseconds: 500));
        
        // Performance assertions
        expect(audioChunks.length, equals(largeSizes.length));
        
        // Transmission time should scale reasonably with size
        for (int i = 0; i < transmissionTimes.length; i++) {
          expect(transmissionTimes[i].inMilliseconds, lessThan(1000)); // < 1s per chunk
        }
        
        await subscription.cancel();
      });
      
      test('should handle concurrent audio streams', () async {
        final audioChunks = <AudioChunkMessage>[];
        final streamProviders = ['elevenlabs', 'openai', 'custom1', 'custom2'];
        
        final subscription = connectionManager.audioChunks.listen((chunk) {
          audioChunks.add(chunk);
        });
        
        print('[PerfTest] Testing concurrent audio streams');
        
        final startTime = DateTime.now();
        
        // Start multiple concurrent streams
        final streamFutures = streamProviders.map((provider) async {
          final chunkCount = 10;
          
          for (int i = 0; i < chunkCount; i++) {
            final chunkEvent = MockEventGenerators.generateAudioStreamingChunk(
              sessionId: testSessionId,
              provider: provider,
              sequenceNumber: i,
              totalChunks: chunkCount,
              isLastChunk: i == chunkCount - 1,
            );
            
            await mockServer.sendToAudio(testSessionId, chunkEvent);
            
            // Send binary data
            final audioData = MockEventGenerators.generateMockAudioData(size: 2048);
            await mockServer.sendBinaryToAudio(testSessionId, audioData);
            
            // Small delay between chunks
            await Future.delayed(Duration(milliseconds: 50));
          }
        });
        
        // Wait for all streams to complete
        await Future.wait(streamFutures);
        await Future.delayed(Duration(milliseconds: 500));
        
        final endTime = DateTime.now();
        final totalTime = endTime.difference(startTime);
        
        // Verify all chunks were received
        final expectedChunks = streamProviders.length * 10;
        expect(audioChunks.length, greaterThanOrEqualTo(expectedChunks * 0.95)); // 95% delivery
        
        // Check chunks from all providers were received
        for (final provider in streamProviders) {
          final providerChunks = audioChunks.where((chunk) => chunk.provider == provider).length;
          expect(providerChunks, greaterThanOrEqualTo(8)); // At least 80% of chunks
        }
        
        print('[PerfTest] Concurrent streams completed in ${totalTime.inSeconds}s');
        print('[PerfTest] Received ${audioChunks.length}/$expectedChunks chunks');
        
        await subscription.cancel();
      });
    });
    
    group('Connection Stress Testing', () {
      test('should handle rapid connect/disconnect cycles', () async {
        const cycleCount = 10;
        final connectionTimes = <Duration>[];
        final disconnectionTimes = <Duration>[];
        
        print('[PerfTest] Testing rapid connect/disconnect cycles');
        
        for (int i = 0; i < cycleCount; i++) {
          // Disconnect current connection
          final disconnectStart = DateTime.now();
          await connectionManager.disconnect();
          final disconnectEnd = DateTime.now();
          disconnectionTimes.add(disconnectEnd.difference(disconnectStart));
          
          // Small delay
          await Future.delayed(Duration(milliseconds: 100));
          
          // Reconnect
          final connectStart = DateTime.now();
          await connectionManager.connect(userId: testUserId);
          final connectEnd = DateTime.now();
          connectionTimes.add(connectEnd.difference(connectStart));
          
          // Verify connection
          expect(connectionManager.isBothConnected, isTrue);
          
          print('[PerfTest] Cycle $i: Connect ${connectionTimes.last.inMilliseconds}ms, Disconnect ${disconnectionTimes.last.inMilliseconds}ms');
        }
        
        // Performance assertions
        final avgConnectionTime = Duration(milliseconds: 
            connectionTimes.fold(0, (sum, dur) => sum + dur.inMilliseconds) ~/ connectionTimes.length);
        final avgDisconnectionTime = Duration(milliseconds: 
            disconnectionTimes.fold(0, (sum, dur) => sum + dur.inMilliseconds) ~/ disconnectionTimes.length);
        
        expect(avgConnectionTime.inSeconds, lessThan(5)); // < 5s average connection time
        expect(avgDisconnectionTime.inSeconds, lessThan(2)); // < 2s average disconnection time
        
        print('[PerfTest] Average connection time: ${avgConnectionTime.inMilliseconds}ms');
        print('[PerfTest] Average disconnection time: ${avgDisconnectionTime.inMilliseconds}ms');
      });
      
      test('should handle connection under load', () async {
        final receivedEvents = <dynamic>[];
        
        // Start event listeners
        final subscriptions = [
          connectionManager.queueUpdates.listen(receivedEvents.add),
          connectionManager.notifications.listen(receivedEvents.add),
          connectionManager.audioChunks.listen(receivedEvents.add),
        ];
        
        // Create background load while testing connection stability
        const loadEventsPerSecond = 30;
        const loadDurationSeconds = 10;
        
        print('[PerfTest] Testing connection stability under load');
        
        // Start background load
        final loadTimer = Timer.periodic(
          Duration(milliseconds: 1000 ~/ loadEventsPerSecond),
          (timer) async {
            if (timer.tick > loadEventsPerSecond * loadDurationSeconds) {
              timer.cancel();
              return;
            }
            
            final event = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
            await mockServer.sendToQueue(testSessionId, event);
          },
        );
        
        // Perform connection operations during load
        await Future.delayed(Duration(seconds: 2));
        
        // Test health check during load
        final healthResult = await connectionManager.performHealthCheck();
        expect(healthResult.isHealthy, isTrue);
        
        await Future.delayed(Duration(seconds: 2));
        
        // Test subscription changes during load
        await connectionManager.subscribeToEventCategories({'audio', 'queue'});
        
        await Future.delayed(Duration(seconds: 2));
        
        // Test message sending during load
        await connectionManager.sendTTSRequest(
          text: 'Test message during load',
          provider: 'elevenlabs',
        );
        
        // Wait for load test to complete
        await Future.delayed(Duration(seconds: loadDurationSeconds - 6));
        
        // Verify system remained stable
        expect(connectionManager.isBothConnected, isTrue);
        expect(receivedEvents.length, greaterThan(loadEventsPerSecond * loadDurationSeconds * 0.8));
        
        print('[PerfTest] Received ${receivedEvents.length} events during load test');
        
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      });
    });
    
    group('Memory and Resource Management', () {
      test('should manage memory efficiently during long sessions', () async {
        final receivedEvents = <dynamic>[];
        var maxLogSize = 0;
        
        final subscription = connectionManager.queueUpdates.listen((event) {
          receivedEvents.add(event);
          
          // Monitor log size growth
          final stats = debugMonitor.getDebugStatistics();
          final currentLogSize = stats['log_sizes']['event_log'] as int;
          maxLogSize = max(maxLogSize, currentLogSize);
        });
        
        print('[PerfTest] Testing memory management during long session');
        
        // Generate events over extended period to test log cleanup
        const eventsPerBatch = 50;
        const batchCount = 10;
        const totalEvents = eventsPerBatch * batchCount;
        
        for (int batch = 0; batch < batchCount; batch++) {
          print('[PerfTest] Batch ${batch + 1}/$batchCount');
          
          // Send batch of events
          for (int i = 0; i < eventsPerBatch; i++) {
            final event = MockEventGenerators.generateQueueUpdate(
              sessionId: testSessionId,
              itemCount: Random().nextInt(3) + 1,
            );
            await mockServer.sendToQueue(testSessionId, event);
          }
          
          // Allow processing and cleanup
          await Future.delayed(Duration(seconds: 1));
        }
        
        // Wait for final cleanup
        await Future.delayed(Duration(seconds: 2));
        
        // Verify memory management
        final finalStats = debugMonitor.getDebugStatistics();
        final finalLogSize = finalStats['log_sizes']['event_log'] as int;
        
        // Log size should be managed (not grow unbounded)
        expect(finalLogSize, lessThan(totalEvents)); // Cleanup should have occurred
        expect(maxLogSize, lessThan(totalEvents * 1.5)); // Reasonable peak usage
        
        print('[PerfTest] Final log size: $finalLogSize (max: $maxLogSize)');
        print('[PerfTest] Total events processed: ${receivedEvents.length}');
        
        await subscription.cancel();
      });
      
      test('should handle subscription churn efficiently', () async {
        final subscriptionChanges = <dynamic>[];
        
        final subscription = connectionManager.subscriptionChanges.listen((change) {
          subscriptionChanges.add(change);
        });
        
        print('[PerfTest] Testing subscription churn performance');
        
        final startTime = DateTime.now();
        const changeCount = 50;
        
        // Rapid subscription changes
        for (int i = 0; i < changeCount; i++) {
          if (i % 4 == 0) {
            await connectionManager.subscribeToAllEvents();
          } else if (i % 4 == 1) {
            await connectionManager.subscribeToEventCategories({'audio'});
          } else if (i % 4 == 2) {
            await connectionManager.subscribeToEventCategories({'queue', 'system'});
          } else {
            await connectionManager.subscribeToSpecificEvents({
              AppConstants.eventQueueTodoUpdate,
              AppConstants.eventAudioStreamingChunk,
            });
          }
          
          // Small delay between changes
          await Future.delayed(Duration(milliseconds: 50));
        }
        
        final endTime = DateTime.now();
        final totalTime = endTime.difference(startTime);
        
        // Performance assertions
        expect(subscriptionChanges.length, greaterThanOrEqualTo(changeCount * 0.9));
        expect(totalTime.inSeconds, lessThan(changeCount * 0.1)); // Reasonable time per change
        
        print('[PerfTest] Subscription churn completed in ${totalTime.inSeconds}s');
        print('[PerfTest] Average time per change: ${totalTime.inMilliseconds / changeCount}ms');
        
        await subscription.cancel();
      });
    });
    
    group('Throughput Benchmarks', () {
      test('should measure maximum sustainable throughput', () async {
        final receivedEvents = <dynamic>[];
        final throughputSamples = <double>[];
        
        final subscription = connectionManager.queueUpdates.listen((event) {
          receivedEvents.add(event);
        });
        
        print('[PerfTest] Measuring maximum sustainable throughput');
        
        // Test increasing event rates to find maximum
        final eventRates = [10, 25, 50, 75, 100, 150, 200];
        
        for (final rate in eventRates) {
          receivedEvents.clear();
          
          print('[PerfTest] Testing ${rate} events/second');
          
          final testStart = DateTime.now();
          const testDuration = 3; // seconds
          final expectedEvents = rate * testDuration;
          
          // Send events at specified rate
          final timer = Timer.periodic(
            Duration(milliseconds: 1000 ~/ rate),
            (timer) async {
              if (timer.tick >= expectedEvents) {
                timer.cancel();
                return;
              }
              
              final event = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
              await mockServer.sendToQueue(testSessionId, event);
            },
          );
          
          // Wait for test to complete
          await Future.delayed(Duration(seconds: testDuration + 1));
          
          final testEnd = DateTime.now();
          final actualDuration = testEnd.difference(testStart).inSeconds;
          final actualThroughput = receivedEvents.length / actualDuration;
          
          throughputSamples.add(actualThroughput);
          
          print('[PerfTest] Rate: $rate/s, Actual: ${actualThroughput.toStringAsFixed(1)}/s, Efficiency: ${(actualThroughput / rate * 100).toStringAsFixed(1)}%');
          
          // If efficiency drops below 90%, we've found the limit
          if (actualThroughput / rate < 0.9) {
            print('[PerfTest] Maximum sustainable rate: ~${(rate * 0.9).round()} events/second');
            break;
          }
        }
        
        // Find maximum achieved throughput
        final maxThroughput = throughputSamples.reduce(max);
        expect(maxThroughput, greaterThan(50)); // Should handle at least 50 events/second
        
        print('[PerfTest] Maximum measured throughput: ${maxThroughput.toStringAsFixed(1)} events/second');
        
        await subscription.cancel();
      });
    });
  });
}