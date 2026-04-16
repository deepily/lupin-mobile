import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../../lib/core/constants/app_constants.dart';

/// Generates realistic mock WebSocket events for testing purposes.
/// 
/// Provides factory methods for creating various types of WebSocket events
/// that match the format expected by the Lupin mobile application.
class MockEventGenerators {
  static final Random _random = Random();
  
  // Static data for generating realistic content
  static const List<String> _adjectives = [
    'brave', 'clever', 'swift', 'gentle', 'wise', 'bold', 'calm', 'kind',
    'quick', 'bright', 'strong', 'smart', 'fast', 'cool', 'warm', 'nice'
  ];
  
  static const List<String> _nouns = [
    'lion', 'eagle', 'dolphin', 'tiger', 'falcon', 'wolf', 'bear', 'fox',
    'hawk', 'shark', 'panther', 'deer', 'owl', 'cat', 'dog', 'bird'
  ];
  
  static const List<String> _ttsTexts = [
    'Hello, how can I help you today?',
    'The weather is sunny and warm.',
    'Your task has been completed successfully.',
    'Please wait while I process your request.',
    'Thank you for using our service.',
    'The system is ready for your next command.',
    'Your data has been saved successfully.',
    'Would you like me to continue with the next step?',
  ];
  
  static const List<String> _taskNames = [
    'Process voice input',
    'Generate TTS audio',
    'Send notification',
    'Update user preferences',
    'Sync data to server',
    'Perform background cleanup',
    'Generate report',
    'Backup user data',
    'Analyze speech pattern',
    'Update voice model',
  ];
  
  static const List<String> _notificationMessages = [
    'New task completed',
    'Queue processing finished',
    'System update available',
    'Background job completed',
    'Voice processing ready',
    'Audio generation complete',
    'Data sync successful',
    'Performance optimization applied',
  ];
  
  /// Generate a random session ID in "adjective noun" format
  static String generateSessionId() {
    final adjective = _adjectives[_random.nextInt(_adjectives.length)];
    final noun = _nouns[_random.nextInt(_nouns.length)];
    return '$adjective $noun';
  }
  
  /// Generate a random user ID
  static String generateUserId() {
    return 'user_${_random.nextInt(10000)}';
  }
  
  /// Generate authentication request event
  static Map<String, dynamic> generateAuthRequest({
    String? sessionId,
    String? userId,
    List<String>? subscribedEvents,
  }) {
    return {
      'type': AppConstants.eventAuthRequest,
      'token': 'Bearer mock_token_email_${userId ?? generateUserId()}',
      'session_id': sessionId ?? generateSessionId(),
      'subscribed_events': subscribedEvents ?? [],
      'client_info': {
        'platform': 'flutter',
        'version': '1.0.0',
        'device_id': 'test_device_${_random.nextInt(1000)}',
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate authentication success event
  static Map<String, dynamic> generateAuthSuccess({
    String? sessionId,
    String? userId,
  }) {
    return {
      'type': AppConstants.eventAuthSuccess,
      'session_id': sessionId ?? generateSessionId(),
      'user_id': userId ?? generateUserId(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate authentication error event
  static Map<String, dynamic> generateAuthError({
    String? sessionId,
    String? errorMessage,
  }) {
    return {
      'type': AppConstants.eventAuthError,
      'session_id': sessionId ?? generateSessionId(),
      'message': errorMessage ?? 'Authentication failed',
      'error_code': 'AUTH_FAILED',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate connection event
  static Map<String, dynamic> generateConnect({
    String? sessionId,
  }) {
    return {
      'type': AppConstants.eventConnect,
      'session_id': sessionId ?? generateSessionId(),
      'server_version': '1.0.0',
      'supported_features': ['audio_streaming', 'voice_input', 'queue_management'],
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate queue update event
  static Map<String, dynamic> generateQueueUpdate({
    String? queueType,
    String? sessionId,
    int? itemCount,
  }) {
    final type = queueType ?? ['todo', 'running', 'done', 'dead'][_random.nextInt(4)];
    final count = itemCount ?? _random.nextInt(5) + 1;
    
    final items = List.generate(count, (index) => {
      'id': 'job_${_random.nextInt(100000)}',
      'name': _taskNames[_random.nextInt(_taskNames.length)],
      'status': type,
      'priority': ['low', 'medium', 'high', 'urgent'][_random.nextInt(4)],
      'created_at': DateTime.now()
          .subtract(Duration(minutes: _random.nextInt(120)))
          .toIso8601String(),
      'estimated_duration': _random.nextInt(300) + 30, // 30-330 seconds
      'progress': type == 'running' ? _random.nextDouble() : 
                  type == 'done' ? 1.0 : 0.0,
    });
    
    String eventType;
    switch (type) {
      case 'todo':
        eventType = AppConstants.eventQueueTodoUpdate;
        break;
      case 'running':
        eventType = AppConstants.eventQueueRunningUpdate;
        break;
      case 'done':
        eventType = AppConstants.eventQueueDoneUpdate;
        break;
      case 'dead':
        eventType = AppConstants.eventQueueDeadUpdate;
        break;
      default:
        eventType = AppConstants.eventQueueTodoUpdate;
    }
    
    return {
      'type': eventType,
      'session_id': sessionId ?? generateSessionId(),
      'queue_type': type,
      'items': items,
      'total_count': count,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate TTS job request event
  static Map<String, dynamic> generateTTSJobRequest({
    String? sessionId,
    String? text,
    String? provider,
  }) {
    return {
      'type': AppConstants.eventTtsJobRequest,
      'session_id': sessionId ?? generateSessionId(),
      'job_id': 'tts_${_random.nextInt(100000)}',
      'text': text ?? _ttsTexts[_random.nextInt(_ttsTexts.length)],
      'provider': provider ?? 'elevenlabs',
      'voice_id': 'voice_${_random.nextInt(10)}',
      'settings': {
        'speed': 1.0 + (_random.nextDouble() - 0.5) * 0.4, // 0.8 - 1.2
        'stability': 0.5 + _random.nextDouble() * 0.5, // 0.5 - 1.0
        'similarity_boost': 0.5 + _random.nextDouble() * 0.5,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate audio streaming chunk event
  static Map<String, dynamic> generateAudioStreamingChunk({
    String? sessionId,
    String? provider,
    int? sequenceNumber,
    int? totalChunks,
    bool? isLastChunk,
  }) {
    final seq = sequenceNumber ?? _random.nextInt(10);
    final total = totalChunks ?? (seq + _random.nextInt(5) + 1);
    
    return {
      'type': AppConstants.eventAudioStreamingChunk,
      'session_id': sessionId ?? generateSessionId(),
      'provider': provider ?? 'elevenlabs',
      'sequence_number': seq,
      'total_chunks': total,
      'is_last_chunk': isLastChunk ?? (seq >= total - 1),
      'chunk_size': 1024 + _random.nextInt(2048),
      'format': 'pcm',
      'sample_rate': 44100,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate audio streaming status event
  static Map<String, dynamic> generateAudioStreamingStatus({
    String? sessionId,
    String? status,
    String? provider,
  }) {
    final statuses = ['starting', 'streaming', 'complete', 'error'];
    
    return {
      'type': AppConstants.eventAudioStreamingStatus,
      'session_id': sessionId ?? generateSessionId(),
      'status': status ?? statuses[_random.nextInt(statuses.length)],
      'provider': provider ?? 'elevenlabs',
      'stream_id': 'stream_${_random.nextInt(100000)}',
      'quality': ['low', 'medium', 'high'][_random.nextInt(3)],
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate audio streaming complete event
  static Map<String, dynamic> generateAudioStreamingComplete({
    String? sessionId,
    String? provider,
  }) {
    return {
      'type': AppConstants.eventAudioStreamingComplete,
      'session_id': sessionId ?? generateSessionId(),
      'provider': provider ?? 'elevenlabs',
      'stream_id': 'stream_${_random.nextInt(100000)}',
      'total_chunks': _random.nextInt(20) + 5,
      'total_duration_ms': _random.nextInt(10000) + 1000,
      'total_bytes': _random.nextInt(50000) + 10000,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate notification queue update event
  static Map<String, dynamic> generateNotificationQueueUpdate({
    String? sessionId,
    String? message,
  }) {
    return {
      'type': AppConstants.eventNotificationQueueUpdate,
      'session_id': sessionId ?? generateSessionId(),
      'message': message ?? _notificationMessages[_random.nextInt(_notificationMessages.length)],
      'notification_id': 'notif_${_random.nextInt(100000)}',
      'priority': ['low', 'medium', 'high'][_random.nextInt(3)],
      'category': ['system', 'user', 'task'][_random.nextInt(3)],
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate notification play sound event
  static Map<String, dynamic> generateNotificationPlaySound({
    String? sessionId,
    String? soundType,
  }) {
    return {
      'type': AppConstants.eventNotificationPlaySound,
      'session_id': sessionId ?? generateSessionId(),
      'sound_type': soundType ?? ['chime', 'beep', 'notification', 'alert'][_random.nextInt(4)],
      'volume': 0.5 + _random.nextDouble() * 0.5, // 0.5 - 1.0
      'duration_ms': _random.nextInt(2000) + 500, // 500 - 2500 ms
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate system time update event
  static Map<String, dynamic> generateSystemTimeUpdate({
    String? sessionId,
  }) {
    return {
      'type': AppConstants.eventSysTimeUpdate,
      'session_id': sessionId ?? generateSessionId(),
      'server_time': DateTime.now().toIso8601String(),
      'timezone': 'UTC',
      'uptime_seconds': _random.nextInt(86400), // Up to 24 hours
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate system ping event
  static Map<String, dynamic> generateSystemPing({
    String? sessionId,
  }) {
    return {
      'type': AppConstants.eventSysPing,
      'session_id': sessionId ?? generateSessionId(),
      'ping_id': 'ping_${_random.nextInt(100000)}',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate system pong event
  static Map<String, dynamic> generateSystemPong({
    String? sessionId,
    String? pingId,
  }) {
    return {
      'type': AppConstants.eventSysPong,
      'session_id': sessionId ?? generateSessionId(),
      'ping_id': pingId ?? 'ping_${_random.nextInt(100000)}',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate subscription update event
  static Map<String, dynamic> generateSubscriptionUpdate({
    String? sessionId,
    bool? subscribeToAll,
    List<String>? subscribedEvents,
  }) {
    return {
      'type': AppConstants.eventSubscriptionUpdate,
      'session_id': sessionId ?? generateSessionId(),
      'subscribe_to_all': subscribeToAll ?? _random.nextBool(),
      'subscribed_events': subscribedEvents ?? _generateRandomEventList(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate update subscriptions request
  static Map<String, dynamic> generateUpdateSubscriptions({
    String? sessionId,
    bool? subscribeToAll,
    List<String>? subscribedEvents,
  }) {
    return {
      'type': AppConstants.eventUpdateSubscriptions,
      'session_id': sessionId ?? generateSessionId(),
      'subscribe_to_all': subscribeToAll ?? false,
      'subscribed_events': subscribedEvents ?? _generateRandomEventList(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Generate mock binary audio data
  static Uint8List generateMockAudioData({
    int? size,
    int? seed,
  }) {
    final dataSize = size ?? (1024 + _random.nextInt(2048)); // 1-3KB
    final dataSeed = seed ?? _random.nextInt(1000000);
    
    final data = Uint8List(dataSize);
    final random = Random(dataSeed);
    
    // Generate audio-like data with some patterns
    for (int i = 0; i < dataSize; i++) {
      // Create wave-like patterns for realistic audio data
      final wave = (sin(i * 0.1) * 127 + 128).round();
      final noise = random.nextInt(32) - 16; // Add some noise
      data[i] = (wave + noise).clamp(0, 255);
    }
    
    return data;
  }
  
  /// Generate a sequence of related events (e.g., TTS flow)
  static List<Map<String, dynamic>> generateTTSFlow({
    String? sessionId,
    String? text,
    String? provider,
  }) {
    final session = sessionId ?? generateSessionId();
    final ttsText = text ?? _ttsTexts[_random.nextInt(_ttsTexts.length)];
    final ttsProvider = provider ?? 'elevenlabs';
    
    final events = <Map<String, dynamic>>[];
    
    // 1. TTS job request
    events.add(generateTTSJobRequest(
      sessionId: session,
      text: ttsText,
      provider: ttsProvider,
    ));
    
    // 2. Audio streaming status (starting)
    events.add(generateAudioStreamingStatus(
      sessionId: session,
      status: 'starting',
      provider: ttsProvider,
    ));
    
    // 3. Multiple audio chunks
    final chunkCount = _random.nextInt(5) + 3; // 3-7 chunks
    for (int i = 0; i < chunkCount; i++) {
      events.add(generateAudioStreamingChunk(
        sessionId: session,
        provider: ttsProvider,
        sequenceNumber: i,
        totalChunks: chunkCount,
        isLastChunk: i == chunkCount - 1,
      ));
    }
    
    // 4. Audio streaming complete
    events.add(generateAudioStreamingComplete(
      sessionId: session,
      provider: ttsProvider,
    ));
    
    return events;
  }
  
  /// Generate a sequence of queue processing events
  static List<Map<String, dynamic>> generateQueueProcessingFlow({
    String? sessionId,
  }) {
    final session = sessionId ?? generateSessionId();
    final events = <Map<String, dynamic>>[];
    
    // 1. Job added to todo queue
    events.add(generateQueueUpdate(
      queueType: 'todo',
      sessionId: session,
      itemCount: 3,
    ));
    
    // 2. Job moved to running queue
    events.add(generateQueueUpdate(
      queueType: 'running',
      sessionId: session,
      itemCount: 1,
    ));
    
    // 3. Job completed and moved to done queue
    events.add(generateQueueUpdate(
      queueType: 'done',
      sessionId: session,
      itemCount: 1,
    ));
    
    // 4. Notification about completion
    events.add(generateNotificationQueueUpdate(
      sessionId: session,
      message: 'Job processing completed successfully',
    ));
    
    return events;
  }
  
  /// Generate a random list of event types for subscription testing
  static List<String> _generateRandomEventList() {
    final allEvents = [
      AppConstants.eventQueueTodoUpdate,
      AppConstants.eventQueueRunningUpdate,
      AppConstants.eventQueueDoneUpdate,
      AppConstants.eventAudioStreamingChunk,
      AppConstants.eventAudioStreamingStatus,
      AppConstants.eventNotificationQueueUpdate,
      AppConstants.eventSysTimeUpdate,
      AppConstants.eventSysPing,
    ];
    
    final count = _random.nextInt(allEvents.length) + 1;
    final shuffled = List.from(allEvents)..shuffle(_random);
    return shuffled.take(count).cast<String>().toList();
  }
  
  /// Generate a burst of events for performance testing
  static List<Map<String, dynamic>> generateEventBurst({
    String? sessionId,
    int? count,
    Duration? timeSpan,
  }) {
    final session = sessionId ?? generateSessionId();
    final eventCount = count ?? 50;
    final span = timeSpan ?? Duration(seconds: 10);
    
    final events = <Map<String, dynamic>>[];
    final startTime = DateTime.now();
    
    for (int i = 0; i < eventCount; i++) {
      final eventTime = startTime.add(Duration(
        milliseconds: (span.inMilliseconds * i / eventCount).round(),
      ));
      
      // Mix different event types
      final eventType = i % 4;
      Map<String, dynamic> event;
      
      switch (eventType) {
        case 0:
          event = generateQueueUpdate(sessionId: session);
          break;
        case 1:
          event = generateSystemTimeUpdate(sessionId: session);
          break;
        case 2:
          event = generateNotificationQueueUpdate(sessionId: session);
          break;
        case 3:
          event = generateAudioStreamingChunk(sessionId: session);
          break;
        default:
          event = generateSystemPing(sessionId: session);
      }
      
      // Update timestamp to spread events over time span
      event['timestamp'] = eventTime.toIso8601String();
      events.add(event);
    }
    
    return events;
  }
  
  /// Generate realistic session with mixed events
  static List<Map<String, dynamic>> generateSessionScenario({
    String? sessionId,
    Duration? duration,
  }) {
    final session = sessionId ?? generateSessionId();
    final sessionDuration = duration ?? Duration(minutes: 5);
    final events = <Map<String, dynamic>>[];
    
    // 1. Authentication flow
    events.add(generateAuthRequest(sessionId: session));
    events.add(generateAuthSuccess(sessionId: session));
    events.add(generateConnect(sessionId: session));
    
    // 2. Initial queue state
    events.add(generateQueueUpdate(queueType: 'todo', sessionId: session));
    
    // 3. System heartbeat
    events.add(generateSystemPing(sessionId: session));
    events.add(generateSystemPong(sessionId: session));
    
    // 4. TTS processing
    events.addAll(generateTTSFlow(sessionId: session));
    
    // 5. Queue processing
    events.addAll(generateQueueProcessingFlow(sessionId: session));
    
    // 6. Periodic system updates
    for (int i = 0; i < sessionDuration.inMinutes; i++) {
      events.add(generateSystemTimeUpdate(sessionId: session));
      if (i % 2 == 0) {
        events.add(generateNotificationQueueUpdate(sessionId: session));
      }
    }
    
    return events;
  }
}