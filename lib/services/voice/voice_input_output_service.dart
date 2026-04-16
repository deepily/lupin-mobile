import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../websocket/enhanced_websocket_service.dart';
import '../adaptive/adaptive_connection_manager.dart';
import '../lifecycle/app_lifecycle_service.dart';

/// Comprehensive voice input/output service for real-time audio processing.
/// 
/// Provides high-quality audio recording, streaming to server, TTS playback,
/// voice activity detection, and adaptive behavior based on network conditions
/// and app lifecycle state. Optimized for mobile environments.
class VoiceInputOutputService {
  static final VoiceInputOutputService _instance = VoiceInputOutputService._internal();
  factory VoiceInputOutputService() => _instance;
  VoiceInputOutputService._internal();

  // Audio recording and playback
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  AudioPlayer? _streamPlayer;
  
  // WebSocket and adaptive services
  EnhancedWebSocketService? _webSocketService;
  AdaptiveConnectionManager? _adaptiveManager;
  AppLifecycleService? _lifecycleService;
  
  // Stream controllers for voice events
  final StreamController<VoiceInputEvent> _voiceInputController =
      StreamController<VoiceInputEvent>.broadcast();
  final StreamController<VoiceOutputEvent> _voiceOutputController =
      StreamController<VoiceOutputEvent>.broadcast();
  final StreamController<VoiceActivityEvent> _activityController =
      StreamController<VoiceActivityEvent>.broadcast();
  
  // Recording state
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isInitialized = false;
  DateTime? _recordingStartTime;
  int _recordingDuration = 0;
  
  // Voice activity detection
  Timer? _vadTimer;
  List<double> _amplitudeHistory = [];
  bool _voiceDetected = false;
  double _noiseThreshold = 0.1;
  
  // Audio buffering for TTS
  final List<Uint8List> _audioBuffer = [];
  bool _isBuffering = false;
  Timer? _playbackTimer;
  
  // Configuration based on adaptive conditions
  VoiceConfig _currentConfig = VoiceConfig.standard();
  
  // Public getters
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  bool get voiceDetected => _voiceDetected;
  int get recordingDuration => _recordingDuration;
  Stream<VoiceInputEvent> get voiceInputStream => _voiceInputController.stream;
  Stream<VoiceOutputEvent> get voiceOutputStream => _voiceOutputController.stream;
  Stream<VoiceActivityEvent> get activityStream => _activityController.stream;
  
  /// Initialize voice input/output service
  Future<void> initialize({
    EnhancedWebSocketService? webSocketService,
    AdaptiveConnectionManager? adaptiveManager,
    AppLifecycleService? lifecycleService,
  }) async {
    print('[VoiceService] Initializing voice input/output service');
    
    try {
      // Store service references
      _webSocketService = webSocketService;
      _adaptiveManager = adaptiveManager;
      _lifecycleService = lifecycleService;
      
      // Request microphone permission
      await _requestPermissions();
      
      // Initialize audio components
      await _initializeRecorder();
      await _initializePlayer();
      
      // Set up adaptive configuration
      _updateVoiceConfig();
      
      // Listen to adaptive and lifecycle changes
      _setupAdaptiveListeners();
      
      // Set up WebSocket message handling
      _setupWebSocketHandling();
      
      _isInitialized = true;
      print('[VoiceService] Voice service initialized successfully');
      
    } catch (e) {
      print('[VoiceService] Initialization failed: $e');
      throw VoiceServiceException('Initialization failed: $e');
    }
  }
  
  /// Request necessary permissions for audio recording
  Future<void> _requestPermissions() async {
    print('[VoiceService] Requesting audio permissions');
    
    final micPermission = await Permission.microphone.request();
    if (micPermission != PermissionStatus.granted) {
      throw VoiceServiceException('Microphone permission denied');
    }
    
    // Request storage permission for audio caching
    if (Platform.isAndroid) {
      final storagePermission = await Permission.storage.request();
      if (storagePermission != PermissionStatus.granted) {
        print('[VoiceService] Storage permission denied - caching may be limited');
      }
    }
  }
  
  /// Initialize audio recorder
  Future<void> _initializeRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
    
    // Configure recorder for optimal voice capture
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 100));
    
    print('[VoiceService] Audio recorder initialized');
  }
  
  /// Initialize audio player
  Future<void> _initializePlayer() async {
    _player = FlutterSoundPlayer();
    await _player!.openPlayer();
    
    _streamPlayer = AudioPlayer();
    await _streamPlayer!.setPlayerMode(PlayerMode.lowLatency);
    await _streamPlayer!.setReleaseMode(ReleaseMode.stop);
    
    print('[VoiceService] Audio players initialized');
  }
  
  /// Set up adaptive configuration listeners
  void _setupAdaptiveListeners() {
    _adaptiveManager?.strategyStream.listen((strategy) {
      _updateVoiceConfig();
    });
    
    _lifecycleService?.usageStateStream.listen((state) {
      _handleAppStateChange(state);
    });
  }
  
  /// Set up WebSocket message handling for audio streaming
  void _setupWebSocketHandling() {
    _webSocketService?.eventStream.listen((event) {
      if (event is WebSocketEvent) {
        _handleWebSocketEvent(event);
      }
    });
    
    _webSocketService?.messageStream.listen((message) {
      _handleWebSocketMessage(message);
    });
  }
  
  /// Handle WebSocket events for audio streaming
  void _handleWebSocketEvent(WebSocketEvent event) {
    // Handle audio-related WebSocket events
    if (event.toString().contains('audio')) {
      print('[VoiceService] Audio WebSocket event: ${event.runtimeType}');
    }
  }
  
  /// Handle WebSocket messages for TTS audio chunks
  void _handleWebSocketMessage(WebSocketMessage message) {
    switch (message.type) {
      case 'audio_chunk':
        if (message.binaryData != null) {
          _handleTTSAudioChunk(message.binaryData!);
        }
        break;
      case 'tts_start':
        _handleTTSStart(message.data);
        break;
      case 'tts_complete':
        _handleTTSComplete(message.data);
        break;
      case 'voice_input_ready':
        _handleVoiceInputReady(message.data);
        break;
    }
  }
  
  /// Start voice recording with streaming to server
  Future<void> startRecording() async {
    if (!_isInitialized || _isRecording) {
      throw VoiceServiceException('Cannot start recording: service not ready or already recording');
    }
    
    try {
      print('[VoiceService] Starting voice recording');
      
      // Get temporary file for recording
      final tempDir = await getTemporaryDirectory();
      final recordingPath = '${tempDir.path}/voice_input_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      // Configure recording based on current conditions
      final codec = _currentConfig.recordingCodec;
      final sampleRate = _currentConfig.sampleRate;
      
      // Start recording
      await _recorder!.startRecorder(
        toFile: recordingPath,
        codec: codec,
        sampleRate: sampleRate,
        bitRate: _currentConfig.bitRate,
        numChannels: 1, // Mono for voice
      );
      
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingDuration = 0;
      
      // Start voice activity detection
      _startVoiceActivityDetection();
      
      // Start streaming if enabled
      if (_currentConfig.enableStreaming && _webSocketService?.isConnected == true) {
        _startAudioStreaming();
      }
      
      // Emit recording started event
      _voiceInputController.add(VoiceInputEvent.recordingStarted(DateTime.now()));
      
      print('[VoiceService] Voice recording started');
      
    } catch (e) {
      print('[VoiceService] Failed to start recording: $e');
      _isRecording = false;
      throw VoiceServiceException('Failed to start recording: $e');
    }
  }
  
  /// Stop voice recording
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      return null;
    }
    
    try {
      print('[VoiceService] Stopping voice recording');
      
      // Stop recording
      final recordingPath = await _recorder!.stopRecorder();
      
      _isRecording = false;
      _recordingDuration = _recordingStartTime != null 
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
          : 0;
      
      // Stop voice activity detection
      _stopVoiceActivityDetection();
      
      // Process recorded audio
      if (recordingPath != null) {
        await _processRecordedAudio(recordingPath);
      }
      
      // Emit recording stopped event
      _voiceInputController.add(VoiceInputEvent.recordingStopped(
        DateTime.now(), 
        Duration(milliseconds: _recordingDuration),
        recordingPath,
      ));
      
      print('[VoiceService] Voice recording stopped');
      return recordingPath;
      
    } catch (e) {
      print('[VoiceService] Failed to stop recording: $e');
      _isRecording = false;
      throw VoiceServiceException('Failed to stop recording: $e');
    }
  }
  
  /// Start voice activity detection during recording
  void _startVoiceActivityDetection() {
    _vadTimer?.cancel();
    _amplitudeHistory.clear();
    _voiceDetected = false;
    
    _vadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      
      // Get current amplitude from recorder
      final subscription = _recorder!.onProgress!.listen((event) {
        final amplitude = event.decibels ?? -120.0;
        _processAmplitudeForVAD(amplitude);
      });
      
      // Cancel subscription after brief listen
      Timer(const Duration(milliseconds: 50), () {
        subscription.cancel();
      });
    });
  }
  
  /// Process amplitude for voice activity detection
  void _processAmplitudeForVAD(double amplitude) {
    // Convert decibels to linear scale (0-1)
    final normalizedAmplitude = (amplitude + 120) / 120;
    _amplitudeHistory.add(normalizedAmplitude.clamp(0.0, 1.0));
    
    // Keep only recent history
    if (_amplitudeHistory.length > 10) {
      _amplitudeHistory.removeAt(0);
    }
    
    // Detect voice activity
    final avgAmplitude = _amplitudeHistory.fold(0.0, (sum, amp) => sum + amp) / _amplitudeHistory.length;
    final previousVoiceDetected = _voiceDetected;
    _voiceDetected = avgAmplitude > _noiseThreshold;
    
    // Emit voice activity events
    if (_voiceDetected != previousVoiceDetected) {
      _activityController.add(VoiceActivityEvent(
        timestamp: DateTime.now(),
        voiceDetected: _voiceDetected,
        amplitude: avgAmplitude,
        confidence: _calculateVoiceConfidence(avgAmplitude),
      ));
    }
  }
  
  /// Calculate voice detection confidence
  double _calculateVoiceConfidence(double amplitude) {
    if (amplitude < _noiseThreshold) return 0.0;
    return ((amplitude - _noiseThreshold) / (1.0 - _noiseThreshold)).clamp(0.0, 1.0);
  }
  
  /// Stop voice activity detection
  void _stopVoiceActivityDetection() {
    _vadTimer?.cancel();
    _vadTimer = null;
  }
  
  /// Start real-time audio streaming to server
  void _startAudioStreaming() {
    if (_webSocketService?.isConnected != true) {
      print('[VoiceService] Cannot start streaming: WebSocket not connected');
      return;
    }
    
    print('[VoiceService] Starting real-time audio streaming');
    
    // Set up periodic audio chunk streaming
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      
      // This would stream audio chunks in a real implementation
      // For now, we'll simulate by sending voice input events
      _sendVoiceInputEvent();
    });
  }
  
  /// Send voice input event to server
  void _sendVoiceInputEvent() {
    if (_webSocketService?.isConnected == true) {
      final event = WebSocketMessage.custom(
        type: 'voice_input',
        data: {
          'timestamp': DateTime.now().toIso8601String(),
          'session_id': _webSocketService!.sessionId,
          'voice_detected': _voiceDetected,
          'recording_duration': _recordingDuration,
        },
      );
      
      // Send through WebSocket (this would need to be implemented in EnhancedWebSocketService)
      // _webSocketService!.sendMessage(event);
      print('[VoiceService] Would send voice input event: ${event.type}');
    }
  }
  
  /// Process recorded audio file
  Future<void> _processRecordedAudio(String filePath) async {
    try {
      print('[VoiceService] Processing recorded audio: $filePath');
      
      // Read audio file
      final audioFile = File(filePath);
      final audioBytes = await audioFile.readAsBytes();
      
      // Send to server for processing if connected
      if (_webSocketService?.isConnected == true) {
        await _sendAudioToServer(audioBytes);
      }
      
      // Cache audio if enabled
      if (_currentConfig.enableCaching) {
        await _cacheAudioFile(filePath, audioBytes);
      }
      
    } catch (e) {
      print('[VoiceService] Failed to process recorded audio: $e');
    }
  }
  
  /// Send audio data to server for processing
  Future<void> _sendAudioToServer(Uint8List audioData) async {
    try {
      final message = WebSocketMessage.custom(
        type: 'voice_audio_data',
        data: {
          'session_id': _webSocketService!.sessionId,
          'timestamp': DateTime.now().toIso8601String(),
          'audio_format': 'wav',
          'sample_rate': _currentConfig.sampleRate,
          'duration_ms': _recordingDuration,
        },
      );
      
      // Send metadata message first (this would need to be implemented)
      // _webSocketService!.sendMessage(message);
      
      // Send binary audio data (this would need to be implemented)
      // _webSocketService!.sendBinaryData(audioData);
      
      print('[VoiceService] Would send audio data to server: ${audioData.length} bytes');
      
    } catch (e) {
      print('[VoiceService] Failed to send audio to server: $e');
    }
  }
  
  /// Cache audio file for offline use
  Future<void> _cacheAudioFile(String filePath, Uint8List audioData) async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final cacheFile = File('${cacheDir.path}/voice_cache_${DateTime.now().millisecondsSinceEpoch}.wav');
      await cacheFile.writeAsBytes(audioData);
      
      print('[VoiceService] Audio cached: ${cacheFile.path}');
      
    } catch (e) {
      print('[VoiceService] Failed to cache audio: $e');
    }
  }
  
  /// Handle TTS audio chunk from server
  void _handleTTSAudioChunk(Uint8List audioData) {
    print('[VoiceService] Received TTS audio chunk: ${audioData.length} bytes');
    
    if (_currentConfig.enableBuffering) {
      // Add to buffer for smooth playback
      _audioBuffer.add(audioData);
      if (!_isBuffering) {
        _startBufferedPlayback();
      }
    } else {
      // Play immediately
      _playAudioChunk(audioData);
    }
    
    _voiceOutputController.add(VoiceOutputEvent.audioChunkReceived(
      DateTime.now(),
      audioData.length,
    ));
  }
  
  /// Start buffered audio playback
  void _startBufferedPlayback() {
    if (_isBuffering || _audioBuffer.isEmpty) return;
    
    _isBuffering = true;
    
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_audioBuffer.isEmpty) {
        timer.cancel();
        _isBuffering = false;
        return;
      }
      
      final chunk = _audioBuffer.removeAt(0);
      _playAudioChunk(chunk);
    });
  }
  
  /// Play individual audio chunk
  Future<void> _playAudioChunk(Uint8List audioData) async {
    try {
      if (_streamPlayer != null) {
        await _streamPlayer!.play(BytesSource(audioData));
        
        _voiceOutputController.add(VoiceOutputEvent.audioChunkPlayed(
          DateTime.now(),
          audioData.length,
        ));
      }
    } catch (e) {
      print('[VoiceService] Failed to play audio chunk: $e');
    }
  }
  
  /// Handle TTS start event
  void _handleTTSStart(Map<String, dynamic>? data) {
    print('[VoiceService] TTS generation started');
    _isPlaying = true;
    _audioBuffer.clear();
    
    _voiceOutputController.add(VoiceOutputEvent.ttsStarted(
      DateTime.now(),
      data?['text'] ?? '',
    ));
  }
  
  /// Handle TTS complete event
  void _handleTTSComplete(Map<String, dynamic>? data) {
    print('[VoiceService] TTS generation completed');
    _isPlaying = false;
    
    _voiceOutputController.add(VoiceOutputEvent.ttsCompleted(
      DateTime.now(),
      data?['text'] ?? '',
    ));
  }
  
  /// Handle voice input ready event
  void _handleVoiceInputReady(Map<String, dynamic>? data) {
    print('[VoiceService] Voice input ready for processing');
    
    _voiceInputController.add(VoiceInputEvent.processingStarted(
      DateTime.now(),
      data?['input_id'] ?? '',
    ));
  }
  
  /// Update voice configuration based on adaptive conditions
  void _updateVoiceConfig() {
    final adaptiveConfig = _adaptiveManager?.getConnectionConfig();
    final appState = _lifecycleService?.currentUsageState;
    
    if (adaptiveConfig != null) {
      _currentConfig = VoiceConfig.fromAdaptiveConfig(adaptiveConfig, appState);
      print('[VoiceService] Voice config updated: ${_currentConfig.toString()}');
    }
  }
  
  /// Handle app state changes
  void _handleAppStateChange(AppUsageState state) {
    switch (state) {
      case AppUsageState.background:
      case AppUsageState.backgroundLong:
        if (_isRecording) {
          stopRecording(); // Stop recording when app goes to background
        }
        break;
      case AppUsageState.active:
        _updateVoiceConfig(); // Refresh config when app becomes active
        break;
      default:
        break;
    }
  }
  
  /// Stop all audio playback
  Future<void> stopPlayback() async {
    try {
      _isPlaying = false;
      _isBuffering = false;
      _audioBuffer.clear();
      _playbackTimer?.cancel();
      
      await _streamPlayer?.stop();
      await _player?.stopPlayer();
      
      _voiceOutputController.add(VoiceOutputEvent.playbackStopped(DateTime.now()));
      
      print('[VoiceService] Audio playback stopped');
      
    } catch (e) {
      print('[VoiceService] Failed to stop playback: $e');
    }
  }
  
  /// Get voice service statistics
  Map<String, dynamic> getVoiceStatistics() {
    return {
      'is_initialized': _isInitialized,
      'is_recording': _isRecording,
      'is_playing': _isPlaying,
      'voice_detected': _voiceDetected,
      'recording_duration_ms': _recordingDuration,
      'audio_buffer_size': _audioBuffer.length,
      'current_config': _currentConfig.toMap(),
      'noise_threshold': _noiseThreshold,
      'amplitude_history': List.from(_amplitudeHistory),
    };
  }
  
  /// Dispose of resources
  Future<void> dispose() async {
    print('[VoiceService] Disposing voice input/output service');
    
    if (_isRecording) {
      await stopRecording();
    }
    
    if (_isPlaying) {
      await stopPlayback();
    }
    
    _vadTimer?.cancel();
    _playbackTimer?.cancel();
    
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
    await _streamPlayer?.dispose();
    
    _voiceInputController.close();
    _voiceOutputController.close();
    _activityController.close();
    
    _isInitialized = false;
  }
}

/// Voice service configuration based on adaptive conditions
class VoiceConfig {
  final Codec recordingCodec;
  final int sampleRate;
  final int bitRate;
  final bool enableStreaming;
  final bool enableBuffering;
  final bool enableCaching;
  final bool enableVAD;
  
  const VoiceConfig({
    required this.recordingCodec,
    required this.sampleRate,
    required this.bitRate,
    required this.enableStreaming,
    required this.enableBuffering,
    required this.enableCaching,
    required this.enableVAD,
  });
  
  factory VoiceConfig.standard() {
    return const VoiceConfig(
      recordingCodec: Codec.pcm16WAV,
      sampleRate: 16000,
      bitRate: 32000,
      enableStreaming: true,
      enableBuffering: true,
      enableCaching: true,
      enableVAD: true,
    );
  }
  
  factory VoiceConfig.fromAdaptiveConfig(
    AdaptiveConnectionConfig adaptiveConfig,
    AppUsageState? appState,
  ) {
    // Optimize based on connection strategy and app state
    switch (adaptiveConfig.strategy) {
      case AdaptiveStrategy.performance:
        return const VoiceConfig(
          recordingCodec: Codec.pcm16WAV,
          sampleRate: 22050,
          bitRate: 44100,
          enableStreaming: true,
          enableBuffering: true,
          enableCaching: true,
          enableVAD: true,
        );
      case AdaptiveStrategy.conservative:
      case AdaptiveStrategy.powerSaver:
        return const VoiceConfig(
          recordingCodec: Codec.aacADTS,
          sampleRate: 8000,
          bitRate: 16000,
          enableStreaming: false,
          enableBuffering: false,
          enableCaching: true,
          enableVAD: false,
        );
      case AdaptiveStrategy.background:
        return const VoiceConfig(
          recordingCodec: Codec.aacADTS,
          sampleRate: 8000,
          bitRate: 12000,
          enableStreaming: false,
          enableBuffering: false,
          enableCaching: false,
          enableVAD: false,
        );
      default:
        return VoiceConfig.standard();
    }
  }
  
  Map<String, dynamic> toMap() {
    return {
      'recording_codec': recordingCodec.toString(),
      'sample_rate': sampleRate,
      'bit_rate': bitRate,
      'enable_streaming': enableStreaming,
      'enable_buffering': enableBuffering,
      'enable_caching': enableCaching,
      'enable_vad': enableVAD,
    };
  }
  
  @override
  String toString() {
    return 'VoiceConfig(codec: $recordingCodec, sampleRate: $sampleRate, streaming: $enableStreaming)';
  }
}

/// Voice input events
abstract class VoiceInputEvent {
  final DateTime timestamp;
  
  const VoiceInputEvent(this.timestamp);
  
  factory VoiceInputEvent.recordingStarted(DateTime timestamp) = RecordingStartedEvent;
  factory VoiceInputEvent.recordingStopped(DateTime timestamp, Duration duration, String? filePath) = RecordingStoppedEvent;
  factory VoiceInputEvent.processingStarted(DateTime timestamp, String inputId) = ProcessingStartedEvent;
}

class RecordingStartedEvent extends VoiceInputEvent {
  const RecordingStartedEvent(DateTime timestamp) : super(timestamp);
}

class RecordingStoppedEvent extends VoiceInputEvent {
  final Duration duration;
  final String? filePath;
  
  const RecordingStoppedEvent(DateTime timestamp, this.duration, this.filePath) : super(timestamp);
}

class ProcessingStartedEvent extends VoiceInputEvent {
  final String inputId;
  
  const ProcessingStartedEvent(DateTime timestamp, this.inputId) : super(timestamp);
}

/// Voice output events
abstract class VoiceOutputEvent {
  final DateTime timestamp;
  
  const VoiceOutputEvent(this.timestamp);
  
  factory VoiceOutputEvent.ttsStarted(DateTime timestamp, String text) = TTSStartedEvent;
  factory VoiceOutputEvent.ttsCompleted(DateTime timestamp, String text) = TTSCompletedEvent;
  factory VoiceOutputEvent.audioChunkReceived(DateTime timestamp, int bytes) = AudioChunkReceivedEvent;
  factory VoiceOutputEvent.audioChunkPlayed(DateTime timestamp, int bytes) = AudioChunkPlayedEvent;
  factory VoiceOutputEvent.playbackStopped(DateTime timestamp) = PlaybackStoppedEvent;
}

class TTSStartedEvent extends VoiceOutputEvent {
  final String text;
  
  const TTSStartedEvent(DateTime timestamp, this.text) : super(timestamp);
}

class TTSCompletedEvent extends VoiceOutputEvent {
  final String text;
  
  const TTSCompletedEvent(DateTime timestamp, this.text) : super(timestamp);
}

class AudioChunkReceivedEvent extends VoiceOutputEvent {
  final int bytes;
  
  const AudioChunkReceivedEvent(DateTime timestamp, this.bytes) : super(timestamp);
}

class AudioChunkPlayedEvent extends VoiceOutputEvent {
  final int bytes;
  
  const AudioChunkPlayedEvent(DateTime timestamp, this.bytes) : super(timestamp);
}

class PlaybackStoppedEvent extends VoiceOutputEvent {
  const PlaybackStoppedEvent(DateTime timestamp) : super(timestamp);
}

/// Voice activity detection event
class VoiceActivityEvent {
  final DateTime timestamp;
  final bool voiceDetected;
  final double amplitude;
  final double confidence;
  
  const VoiceActivityEvent({
    required this.timestamp,
    required this.voiceDetected,
    required this.amplitude,
    required this.confidence,
  });
}

/// Voice service exception
class VoiceServiceException implements Exception {
  final String message;
  
  const VoiceServiceException(this.message);
  
  @override
  String toString() => 'VoiceServiceException: $message';
}