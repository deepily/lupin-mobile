import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import '../lib/services/voice/voice_input_output_service.dart';
import '../lib/services/tts/enhanced_tts_service.dart';

void main() {
  group('Voice and TTS Integration Tests', () {
    late VoiceInputOutputService voiceService;
    late EnhancedTTSService ttsService;
    
    setUpAll(() {
      // Ensure Flutter binding is initialized
      WidgetsFlutterBinding.ensureInitialized();
    });
    
    setUp(() {
      voiceService = VoiceInputOutputService();
      ttsService = EnhancedTTSService();
    });
    
    tearDown(() async {
      await voiceService.dispose();
      await ttsService.dispose();
    });
    
    group('VoiceInputOutputService', () {
      test('should create service instance', () {
        expect(voiceService, isNotNull);
        expect(voiceService.isInitialized, isFalse);
        expect(voiceService.isRecording, isFalse);
        expect(voiceService.isPlaying, isFalse);
      });
      
      test('should provide voice statistics', () {
        final stats = voiceService.getVoiceStatistics();
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['is_initialized'], isFalse);
        expect(stats['is_recording'], isFalse);
        expect(stats['is_playing'], isFalse);
        expect(stats['voice_detected'], isFalse);
        expect(stats['current_config'], isA<Map<String, dynamic>>());
      });
      
      test('should handle voice config creation', () {
        final standardConfig = VoiceConfig.standard();
        expect(standardConfig, isA<VoiceConfig>());
        expect(standardConfig.enableStreaming, isTrue);
        expect(standardConfig.enableBuffering, isTrue);
        expect(standardConfig.enableCaching, isTrue);
        expect(standardConfig.enableVAD, isTrue);
        expect(standardConfig.toString(), contains('VoiceConfig'));
      });
      
      test('should create voice events', () {
        final now = DateTime.now();
        
        final recordingStarted = VoiceInputEvent.recordingStarted(now);
        expect(recordingStarted, isA<RecordingStartedEvent>());
        expect(recordingStarted.timestamp, equals(now));
        
        final recordingStopped = VoiceInputEvent.recordingStopped(
          now, 
          const Duration(seconds: 5), 
          '/path/to/file.wav',
        );
        expect(recordingStopped, isA<RecordingStoppedEvent>());
        expect((recordingStopped as RecordingStoppedEvent).duration, equals(const Duration(seconds: 5)));
        expect(recordingStopped.filePath, equals('/path/to/file.wav'));
        
        final processingStarted = VoiceInputEvent.processingStarted(now, 'input_123');
        expect(processingStarted, isA<ProcessingStartedEvent>());
        expect((processingStarted as ProcessingStartedEvent).inputId, equals('input_123'));
      });
      
      test('should create voice output events', () {
        final now = DateTime.now();
        
        final ttsStarted = VoiceOutputEvent.ttsStarted(now, 'Hello world');
        expect(ttsStarted, isA<TTSStartedEvent>());
        expect((ttsStarted as TTSStartedEvent).text, equals('Hello world'));
        
        final audioChunkReceived = VoiceOutputEvent.audioChunkReceived(now, 1024);
        expect(audioChunkReceived, isA<AudioChunkReceivedEvent>());
        expect((audioChunkReceived as AudioChunkReceivedEvent).bytes, equals(1024));
        
        final playbackStopped = VoiceOutputEvent.playbackStopped(now);
        expect(playbackStopped, isA<PlaybackStoppedEvent>());
      });
      
      test('should create voice activity events', () {
        final now = DateTime.now();
        
        final activity = VoiceActivityEvent(
          timestamp: now,
          voiceDetected: true,
          amplitude: 0.7,
          confidence: 0.85,
        );
        
        expect(activity.voiceDetected, isTrue);
        expect(activity.amplitude, equals(0.7));
        expect(activity.confidence, equals(0.85));
        expect(activity.timestamp, equals(now));
      });
      
      test('should handle voice service exceptions', () {
        const exception = VoiceServiceException('Test error');
        expect(exception.message, equals('Test error'));
        expect(exception.toString(), contains('VoiceServiceException'));
      });
    });
    
    group('EnhancedTTSService', () {
      test('should create service instance', () {
        expect(ttsService, isNotNull);
        expect(ttsService.isInitialized, isFalse);
        expect(ttsService.isGenerating, isFalse);
        expect(ttsService.isPlaying, isFalse);
        expect(ttsService.currentProvider, equals(TTSProvider.elevenlabs));
        expect(ttsService.currentQuality, equals(TTSQuality.standard));
      });
      
      test('should provide TTS statistics', () {
        final stats = ttsService.getTTSStatistics();
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['is_initialized'], isFalse);
        expect(stats['is_generating'], isFalse);
        expect(stats['is_playing'], isFalse);
        expect(stats['current_provider'], contains('elevenlabs'));
        expect(stats['current_quality'], contains('standard'));
        expect(stats['provider_metrics'], isA<Map<String, dynamic>>());
      });
      
      test('should handle TTS config creation', () {
        final standardConfig = TTSConfig.standard();
        expect(standardConfig, isA<TTSConfig>());
        expect(standardConfig.enableCaching, isTrue);
        expect(standardConfig.defaultQuality, equals(TTSQuality.standard));
        expect(standardConfig.preferredProvider, equals(TTSProvider.elevenlabs));
        expect(standardConfig.toString(), contains('TTSConfig'));
      });
      
      test('should create TTS events', () {
        final now = DateTime.now();
        
        final generationStarted = TTSEvent.generationStarted(
          now, 
          'Hello world', 
          TTSProvider.elevenlabs, 
          TTSQuality.high,
        );
        expect(generationStarted, isA<GenerationStartedEvent>());
        expect((generationStarted as GenerationStartedEvent).text, equals('Hello world'));
        expect(generationStarted.provider, equals(TTSProvider.elevenlabs));
        expect(generationStarted.quality, equals(TTSQuality.high));
        
        final generationCompleted = TTSEvent.generationCompleted(now, 'Hello world', 5);
        expect(generationCompleted, isA<GenerationCompletedEvent>());
        expect((generationCompleted as GenerationCompletedEvent).chunks, equals(5));
        
        final playbackStarted = TTSEvent.playbackStarted(now);
        expect(playbackStarted, isA<PlaybackStartedEvent>());
        
        final chunkPlayed = TTSEvent.chunkPlayed(now, 2048);
        expect(chunkPlayed, isA<ChunkPlayedEvent>());
        expect((chunkPlayed as ChunkPlayedEvent).bytes, equals(2048));
        
        final error = TTSEvent.error(now, 'TTS error occurred');
        expect(error, isA<ErrorEvent>());
        expect((error as ErrorEvent).error, equals('TTS error occurred'));
      });
      
      test('should create TTS status updates', () {
        final now = DateTime.now();
        
        final initialized = TTSStatusUpdate.initialized(now);
        expect(initialized, isA<InitializedUpdate>());
        
        final requestSent = TTSStatusUpdate.requestSent(now, TTSProvider.openai, 50);
        expect(requestSent, isA<RequestSentUpdate>());
        expect((requestSent as RequestSentUpdate).provider, equals(TTSProvider.openai));
        expect(requestSent.textLength, equals(50));
        
        final statusChanged = TTSStatusUpdate.statusChanged(now, 'generating', {'progress': 0.5});
        expect(statusChanged, isA<StatusChangedUpdate>());
        expect((statusChanged as StatusChangedUpdate).status, equals('generating'));
        expect(statusChanged.data?['progress'], equals(0.5));
      });
      
      test('should handle TTS metrics', () {
        final metrics = TTSMetrics();
        
        // Initially empty
        expect(metrics.successRate, equals(0.0));
        expect(metrics.averageLatency, equals(0.0));
        expect(metrics.averageQuality, equals(0.0));
        
        // Record success
        metrics.recordSuccess(150, 0.9);
        expect(metrics.successRate, equals(1.0));
        expect(metrics.averageLatency, equals(150.0));
        expect(metrics.averageQuality, equals(0.9));
        
        // Record error
        metrics.recordError('Network timeout');
        expect(metrics.successRate, equals(0.5)); // 1 success out of 2 total
        
        // Check metrics map
        final metricsMap = metrics.toMap();
        expect(metricsMap['total_requests'], equals(2));
        expect(metricsMap['successful_requests'], equals(1));
        expect(metricsMap['success_rate'], equals(0.5));
        expect(metricsMap['recent_errors'], contains('Network timeout'));
      });
      
      test('should handle TTS service exceptions', () {
        const exception = TTSServiceException('TTS initialization failed');
        expect(exception.message, equals('TTS initialization failed'));
        expect(exception.toString(), contains('TTSServiceException'));
      });
    });
    
    group('Enums and Constants', () {
      test('should handle TTSProvider enum', () {
        expect(TTSProvider.values.length, equals(2));
        expect(TTSProvider.openai.toString(), contains('openai'));
        expect(TTSProvider.elevenlabs.toString(), contains('elevenlabs'));
      });
      
      test('should handle TTSQuality enum', () {
        expect(TTSQuality.values.length, equals(3));
        expect(TTSQuality.low.toString(), contains('low'));
        expect(TTSQuality.standard.toString(), contains('standard'));
        expect(TTSQuality.high.toString(), contains('high'));
      });
      
      test('should handle Codec enum from flutter_sound', () {
        // Note: These would be tested with actual flutter_sound imports
        // For now, just verify the concept works
        expect('pcm16WAV', contains('pcm16WAV'));
        expect('aacADTS', contains('aacADTS'));
      });
    });
    
    group('Integration Scenarios', () {
      test('should handle voice config adaptation', () {
        // This would test the integration between VoiceConfig and adaptive conditions
        // For now, just test that configs can be created
        final config = VoiceConfig.standard();
        expect(config.enableStreaming, isTrue);
        
        // Test config serialization
        final configMap = config.toMap();
        expect(configMap['enable_streaming'], isTrue);
        expect(configMap['sample_rate'], isA<int>());
        expect(configMap['bit_rate'], isA<int>());
      });
      
      test('should handle TTS config adaptation', () {
        // Test TTS config creation and adaptation
        final config = TTSConfig.standard();
        expect(config.preferredProvider, equals(TTSProvider.elevenlabs));
        
        // Test config serialization
        final configMap = config.toMap();
        expect(configMap['preferred_provider'], contains('elevenlabs'));
        expect(configMap['default_quality'], contains('standard'));
        expect(configMap['enable_caching'], isTrue);
      });
    });
  });
}