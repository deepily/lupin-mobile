import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import '../websocket/enhanced_websocket_service.dart';
import '../adaptive/adaptive_connection_manager.dart';
import '../lifecycle/app_lifecycle_service.dart';
import '../voice/voice_input_output_service.dart';
import '../../core/constants/app_constants.dart';

/// Legacy TTS service that adapts provider and quality to connection conditions.
///
/// App-wide singleton. It switches provider, picks a quality, buffers and caches audio, and works with
/// the voice input/output service. The slimmer `StreamingTtsPlayer` is the client the app uses today.
class EnhancedTTSService {
  static final EnhancedTTSService _instance = EnhancedTTSService._internal();
  /// Returns the shared instance.
  factory EnhancedTTSService() => _instance;
  EnhancedTTSService._internal();

  // Core dependencies
  final Dio _dio = Dio();
  AudioPlayer? _audioPlayer;
  
  // Service dependencies
  EnhancedWebSocketService? _webSocketService;
  AdaptiveConnectionManager? _adaptiveManager;
  AppLifecycleService? _lifecycleService;
  VoiceInputOutputService? _voiceService;
  
  // Stream controllers for TTS events
  final StreamController<TTSEvent> _ttsEventController =
      StreamController<TTSEvent>.broadcast();
  final StreamController<TTSStatusUpdate> _statusController =
      StreamController<TTSStatusUpdate>.broadcast();
  final StreamController<AudioBufferEvent> _bufferController =
      StreamController<AudioBufferEvent>.broadcast();
  
  // TTS state management
  bool _isInitialized = false;
  bool _isGenerating = false;
  bool _isPlaying = false;
  TTSProvider _currentProvider = TTSProvider.elevenlabs;
  TTSQuality _currentQuality = TTSQuality.standard;
  
  // Audio buffering and streaming
  final List<Uint8List> _audioBuffer = [];
  final Map<String, Uint8List> _audioCache = {};
  bool _isBuffering = false;
  Timer? _bufferTimer;
  int _currentBufferIndex = 0;
  
  // Adaptive configuration
  TTSConfig _currentConfig = TTSConfig.standard();
  
  // Performance metrics
  final Map<TTSProvider, TTSMetrics> _providerMetrics = {};
  DateTime? _requestStartTime;
  
  // Public getters
  /// True once [initialize] has succeeded.
  bool get isInitialized => _isInitialized;
  /// True while a speech request is in progress.
  bool get isGenerating => _isGenerating;
  /// True while audio is playing.
  bool get isPlaying => _isPlaying;
  /// Provider used for the current or next request.
  TTSProvider get currentProvider => _currentProvider;
  /// Quality used for the current or next request.
  TTSQuality get currentQuality => _currentQuality;
  /// Emits generation and playback events.
  Stream<TTSEvent> get eventStream => _ttsEventController.stream;
  /// Emits status updates.
  Stream<TTSStatusUpdate> get statusStream => _statusController.stream;
  /// Emits an event for each audio chunk added to the buffer.
  Stream<AudioBufferEvent> get bufferStream => _bufferController.stream;
  
  /// Stores the service references, opens the audio player and starts listening.
  ///
  /// Throws [TTSServiceException] when initialization fails.
  Future<void> initialize({
    EnhancedWebSocketService? webSocketService,
    AdaptiveConnectionManager? adaptiveManager,
    AppLifecycleService? lifecycleService,
    VoiceInputOutputService? voiceService,
  }) async {
    print('[EnhancedTTS] Initializing enhanced TTS service');
    
    try {
      // Store service references
      _webSocketService = webSocketService;
      _adaptiveManager = adaptiveManager;
      _lifecycleService = lifecycleService;
      _voiceService = voiceService;
      
      // Initialize audio player
      await _initializeAudioPlayer();
      
      // Set up adaptive configuration
      _updateTTSConfig();
      
      // Set up service listeners
      _setupAdaptiveListeners();
      _setupWebSocketHandling();
      
      // Initialize provider metrics
      _initializeProviderMetrics();
      
      _isInitialized = true;
      _statusController.add(TTSStatusUpdate.initialized(DateTime.now()));
      
      print('[EnhancedTTS] Enhanced TTS service initialized');
      
    } catch (e) {
      print('[EnhancedTTS] Initialization failed: $e');
      throw TTSServiceException('Enhanced TTS initialization failed: $e');
    }
  }
  
  /// Initialize audio player with optimal settings
  Future<void> _initializeAudioPlayer() async {
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setPlayerMode(PlayerMode.lowLatency);
    await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
    
    // Listen to player events
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      _handlePlayerStateChange(state);
    });
    
    _audioPlayer!.onDurationChanged.listen((duration) {
      _ttsEventController.add(TTSEvent.durationChanged(DateTime.now(), duration));
    });
    
    _audioPlayer!.onPositionChanged.listen((position) {
      _ttsEventController.add(TTSEvent.positionChanged(DateTime.now(), position));
    });
  }
  
  /// Set up adaptive configuration listeners
  void _setupAdaptiveListeners() {
    _adaptiveManager?.strategyStream.listen((strategy) {
      _updateTTSConfig();
      _adaptProviderBasedOnStrategy(strategy);
    });
    
    _lifecycleService?.usageStateStream.listen((state) {
      _handleAppStateChange(state);
    });
  }
  
  /// Set up WebSocket message handling
  void _setupWebSocketHandling() {
    _webSocketService?.eventStream.listen((event) {
      _handleWebSocketEvent(event);
    });
    
    _webSocketService?.messageStream.listen((message) {
      _handleWebSocketMessage(message);
    });
  }
  
  /// Initialize provider performance metrics
  void _initializeProviderMetrics() {
    for (final provider in TTSProvider.values) {
      _providerMetrics[provider] = TTSMetrics();
    }
  }
  
  /// Handle WebSocket events for TTS
  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event.toString().contains('audio') || event.toString().contains('tts')) {
      print('[EnhancedTTS] TTS WebSocket event: ${event.runtimeType}');
    }
  }
  
  /// Handle WebSocket messages for TTS audio
  void _handleWebSocketMessage(WebSocketMessage message) {
    switch (message.type) {
      case 'tts_start':
        _handleTTSStart(message.data);
        break;
      case 'tts_status':
        _handleTTSStatus(message.data);
        break;
      case 'audio_chunk':
        if (message.binaryData != null) {
          _handleAudioChunk(message.binaryData!);
        }
        break;
      case 'tts_complete':
        _handleTTSComplete(message.data);
        break;
      case 'tts_error':
        _handleTTSError(message.data);
        break;
    }
  }
  
  /// Generates speech for [text], picking the provider and quality when none is given.
  ///
  /// Stops a request still in progress first; requests are not queued.
  ///
  /// Throws [TTSServiceException] when the service is not initialized.
  Future<void> speak(
    String text, {
    TTSProvider? provider,
    TTSQuality? quality,
    String? voiceId,
    Map<String, dynamic>? options,
  }) async {
    if (!_isInitialized) {
      throw TTSServiceException('TTS service not initialized');
    }
    
    if (_isGenerating) {
      print('[EnhancedTTS] Previous TTS request still in progress, queuing...');
      // Could implement queuing logic here
      await stopSpeaking();
    }
    
    try {
      _isGenerating = true;
      _requestStartTime = DateTime.now();
      
      // Select optimal provider and quality
      final selectedProvider = provider ?? _selectOptimalProvider();
      final selectedQuality = quality ?? _selectOptimalQuality();
      
      _currentProvider = selectedProvider;
      _currentQuality = selectedQuality;
      
      // Clear previous audio state
      _clearAudioBuffer();
      
      // Emit TTS start event
      _ttsEventController.add(TTSEvent.generationStarted(
        DateTime.now(),
        text,
        selectedProvider,
        selectedQuality,
      ));
      
      // Send TTS request based on provider
      await _sendTTSRequest(text, selectedProvider, selectedQuality, voiceId, options);
      
      print('[EnhancedTTS] TTS request sent: ${text.length} chars, provider: $selectedProvider');
      
    } catch (e) {
      _isGenerating = false;
      _recordProviderError(_currentProvider, e.toString());
      _ttsEventController.add(TTSEvent.error(DateTime.now(), e.toString()));
      rethrow;
    }
  }
  
  /// Select optimal TTS provider based on current conditions
  TTSProvider _selectOptimalProvider() {
    final adaptiveConfig = _adaptiveManager?.getConnectionConfig();
    final appState = _lifecycleService?.currentUsageState;
    
    // Use provider with best recent performance
    var bestProvider = TTSProvider.elevenlabs;
    var bestScore = 0.0;
    
    for (final entry in _providerMetrics.entries) {
      final provider = entry.key;
      final metrics = entry.value;
      
      double score = _calculateProviderScore(provider, metrics, adaptiveConfig, appState);
      
      if (score > bestScore) {
        bestScore = score;
        bestProvider = provider;
      }
    }
    
    print('[EnhancedTTS] Selected provider: $bestProvider (score: ${bestScore.toStringAsFixed(2)})');
    return bestProvider;
  }
  
  /// Calculate provider performance score
  double _calculateProviderScore(
    TTSProvider provider,
    TTSMetrics metrics,
    AdaptiveConnectionConfig? config,
    AppUsageState? appState,
  ) {
    double score = 0.0;
    
    // Base score from success rate
    score += metrics.successRate * 50;
    
    // Latency score (lower is better)
    if (metrics.averageLatency > 0) {
      score += (5000 - metrics.averageLatency.clamp(0, 5000)) / 100;
    }
    
    // Quality score
    score += metrics.averageQuality * 20;
    
    // Adaptive adjustments
    if (config != null) {
      switch (config.strategy) {
        case AdaptiveStrategy.performance:
          // Prefer faster providers
          if (provider == TTSProvider.elevenlabs) score += 10;
          break;
        case AdaptiveStrategy.conservative:
        case AdaptiveStrategy.powerSaver:
          // Prefer more reliable providers
          if (provider == TTSProvider.openai) score += 10;
          break;
        default:
          break;
      }
    }
    
    // App state adjustments
    if (appState == AppUsageState.background) {
      // Prefer lighter providers in background
      if (provider == TTSProvider.openai) score += 5;
    }
    
    return score;
  }
  
  /// Select optimal TTS quality based on conditions
  TTSQuality _selectOptimalQuality() {
    final adaptiveConfig = _adaptiveManager?.getConnectionConfig();
    
    if (adaptiveConfig != null) {
      switch (adaptiveConfig.optimization) {
        case ConnectionOptimization.performance:
          return TTSQuality.high;
        case ConnectionOptimization.dataSaver:
          return TTSQuality.low;
        case ConnectionOptimization.batterySaver:
          return TTSQuality.low;
        case ConnectionOptimization.balanced:
          return TTSQuality.standard;
      }
    }
    
    return TTSQuality.standard;
  }
  
  /// Send TTS request to backend
  Future<void> _sendTTSRequest(
    String text,
    TTSProvider provider,
    TTSQuality quality,
    String? voiceId,
    Map<String, dynamic>? options,
  ) async {
    try {
      // Ensure WebSocket connection
      if (_webSocketService?.isConnected != true) {
        await _webSocketService?.connect();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      final sessionId = _webSocketService?.sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
      
      switch (provider) {
        case TTSProvider.elevenlabs:
          await _sendElevenLabsRequest(text, quality, voiceId, sessionId, options);
          break;
        case TTSProvider.openai:
          await _sendOpenAIRequest(text, quality, sessionId, options);
          break;
      }
      
      _statusController.add(TTSStatusUpdate.requestSent(
        DateTime.now(),
        provider,
        text.length,
      ));
      
    } catch (e) {
      print('[EnhancedTTS] TTS request failed: $e');
      throw TTSServiceException('TTS request failed: $e');
    }
  }
  
  /// Send ElevenLabs TTS request
  Future<void> _sendElevenLabsRequest(
    String text,
    TTSQuality quality,
    String? voiceId,
    String sessionId,
    Map<String, dynamic>? options,
  ) async {
    final response = await _dio.post(
      '${AppConstants.apiBaseUrl}/api/get-speech-elevenlabs',
      data: {
        'session_id': sessionId,
        'text': text,
        'voice_id': voiceId ?? _getDefaultVoiceId(quality),
        'model_id': _getElevenLabsModel(quality),
        'stability': options?['stability'] ?? _getQualityStability(quality),
        'similarity_boost': options?['similarity_boost'] ?? _getQualitySimilarity(quality),
        'style': options?['style'] ?? 0.0,
        'use_speaker_boost': options?['use_speaker_boost'] ?? true,
      },
      options: Options(
        sendTimeout: Duration(seconds: _currentConfig.requestTimeout),
        receiveTimeout: Duration(seconds: _currentConfig.requestTimeout * 2),
      ),
    );
    
    if (response.statusCode != 200) {
      throw Exception('ElevenLabs API error: ${response.statusCode}');
    }
  }
  
  /// Send OpenAI TTS request
  Future<void> _sendOpenAIRequest(
    String text,
    TTSQuality quality,
    String sessionId,
    Map<String, dynamic>? options,
  ) async {
    final response = await _dio.post(
      '${AppConstants.apiBaseUrl}${AppConstants.apiGetAudio}',
      data: {
        'session_id': sessionId,
        'text': text,
        'voice': options?['voice'] ?? _getOpenAIVoice(quality),
        'model': _getOpenAIModel(quality),
        'response_format': 'mp3',
        'speed': options?['speed'] ?? 1.0,
      },
      options: Options(
        sendTimeout: Duration(seconds: _currentConfig.requestTimeout),
        receiveTimeout: Duration(seconds: _currentConfig.requestTimeout * 2),
      ),
    );
    
    if (response.statusCode != 200) {
      throw Exception('OpenAI API error: ${response.statusCode}');
    }
  }
  
  /// Handle TTS start event
  void _handleTTSStart(Map<String, dynamic>? data) {
    print('[EnhancedTTS] TTS generation started');
    _clearAudioBuffer();
    
    _ttsEventController.add(TTSEvent.generationStarted(
      DateTime.now(),
      data?['text'] ?? '',
      _currentProvider,
      _currentQuality,
    ));
  }
  
  /// Handle TTS status updates
  void _handleTTSStatus(Map<String, dynamic>? data) {
    final status = data?['status'] ?? 'unknown';
    print('[EnhancedTTS] TTS status: $status');
    
    _statusController.add(TTSStatusUpdate.statusChanged(
      DateTime.now(),
      status,
      data,
    ));
  }
  
  /// Handle audio chunk from WebSocket
  void _handleAudioChunk(Uint8List audioData) {
    print('[EnhancedTTS] Received audio chunk: ${audioData.length} bytes');
    
    // Add to buffer
    _audioBuffer.add(audioData);
    
    // Cache if enabled
    if (_currentConfig.enableCaching) {
      _cacheAudioChunk(audioData);
    }
    
    // Start playback if buffering is ready
    if (!_isBuffering && _audioBuffer.length >= _currentConfig.bufferThreshold) {
      _startBufferedPlayback();
    }
    
    _bufferController.add(AudioBufferEvent.chunkAdded(
      DateTime.now(),
      audioData.length,
      _audioBuffer.length,
    ));
  }
  
  /// Handle TTS completion
  void _handleTTSComplete(Map<String, dynamic>? data) {
    print('[EnhancedTTS] TTS generation completed');
    
    _isGenerating = false;
    
    // Record metrics
    if (_requestStartTime != null) {
      final latency = DateTime.now().difference(_requestStartTime!).inMilliseconds;
      _recordProviderSuccess(_currentProvider, latency);
    }
    
    _ttsEventController.add(TTSEvent.generationCompleted(
      DateTime.now(),
      data?['text'] ?? '',
      _audioBuffer.length,
    ));
  }
  
  /// Handle TTS error
  void _handleTTSError(Map<String, dynamic>? data) {
    final error = data?['error'] ?? 'Unknown TTS error';
    print('[EnhancedTTS] TTS error: $error');
    
    _isGenerating = false;
    _recordProviderError(_currentProvider, error);
    
    _ttsEventController.add(TTSEvent.error(DateTime.now(), error));
  }
  
  /// Start buffered audio playback
  void _startBufferedPlayback() {
    if (_isBuffering || _audioBuffer.isEmpty) return;
    
    print('[EnhancedTTS] Starting buffered audio playback');
    _isBuffering = true;
    _isPlaying = true;
    _currentBufferIndex = 0;
    
    _bufferTimer = Timer.periodic(Duration(milliseconds: _currentConfig.playbackInterval), (timer) {
      if (_currentBufferIndex >= _audioBuffer.length) {
        timer.cancel();
        _isBuffering = false;
        _isPlaying = false;
        _ttsEventController.add(TTSEvent.playbackCompleted(DateTime.now()));
        return;
      }
      
      final chunk = _audioBuffer[_currentBufferIndex];
      _playAudioChunk(chunk);
      _currentBufferIndex++;
    });
  }
  
  /// Play individual audio chunk
  Future<void> _playAudioChunk(Uint8List audioData) async {
    try {
      await _audioPlayer?.play(BytesSource(audioData));
      
      _ttsEventController.add(TTSEvent.chunkPlayed(
        DateTime.now(),
        audioData.length,
      ));
      
    } catch (e) {
      print('[EnhancedTTS] Failed to play audio chunk: $e');
    }
  }
  
  /// Cache audio chunk for offline use
  void _cacheAudioChunk(Uint8List audioData) {
    final key = 'chunk_${DateTime.now().millisecondsSinceEpoch}';
    _audioCache[key] = audioData;
    
    // Limit cache size
    if (_audioCache.length > _currentConfig.maxCacheSize) {
      final oldestKey = _audioCache.keys.first;
      _audioCache.remove(oldestKey);
    }
  }
  
  /// Clear audio buffer
  void _clearAudioBuffer() {
    _audioBuffer.clear();
    _currentBufferIndex = 0;
    _isBuffering = false;
  }
  
  /// Stops speech generation and playback.
  Future<void> stopSpeaking() async {
    try {
      print('[EnhancedTTS] Stopping TTS playback');
      
      _isGenerating = false;
      _isPlaying = false;
      _isBuffering = false;
      
      _bufferTimer?.cancel();
      await _audioPlayer?.stop();
      _clearAudioBuffer();
      
      _ttsEventController.add(TTSEvent.stopped(DateTime.now()));
      
    } catch (e) {
      print('[EnhancedTTS] Failed to stop TTS: $e');
    }
  }
  
  /// Pauses playback.
  Future<void> pauseSpeaking() async {
    try {
      await _audioPlayer?.pause();
      _bufferTimer?.cancel();
      
      _ttsEventController.add(TTSEvent.paused(DateTime.now()));
      
    } catch (e) {
      print('[EnhancedTTS] Failed to pause TTS: $e');
    }
  }
  
  /// Resumes paused playback.
  Future<void> resumeSpeaking() async {
    try {
      await _audioPlayer?.resume();
      
      if (_audioBuffer.isNotEmpty && _currentBufferIndex < _audioBuffer.length) {
        _startBufferedPlayback();
      }
      
      _ttsEventController.add(TTSEvent.resumed(DateTime.now()));
      
    } catch (e) {
      print('[EnhancedTTS] Failed to resume TTS: $e');
    }
  }
  
  /// Handle audio player state changes
  void _handlePlayerStateChange(PlayerState state) {
    switch (state) {
      case PlayerState.playing:
        _ttsEventController.add(TTSEvent.playbackStarted(DateTime.now()));
        break;
      case PlayerState.paused:
        _ttsEventController.add(TTSEvent.paused(DateTime.now()));
        break;
      case PlayerState.stopped:
        _ttsEventController.add(TTSEvent.stopped(DateTime.now()));
        break;
      case PlayerState.completed:
        _ttsEventController.add(TTSEvent.playbackCompleted(DateTime.now()));
        break;
      case PlayerState.disposed:
        break;
    }
  }
  
  /// Rebuilds the TTS configuration from the adaptive connection config and the app state.
  void _updateTTSConfig() {
    final adaptiveConfig = _adaptiveManager?.getConnectionConfig();
    final appState = _lifecycleService?.currentUsageState;
    
    if (adaptiveConfig != null) {
      _currentConfig = TTSConfig.fromAdaptiveConfig(adaptiveConfig, appState);
      print('[EnhancedTTS] TTS config updated: ${_currentConfig.toString()}');
    }
  }
  
  /// Adapt provider selection based on strategy
  void _adaptProviderBasedOnStrategy(AdaptiveStrategy strategy) {
    switch (strategy) {
      case AdaptiveStrategy.performance:
        // Prefer fastest provider
        break;
      case AdaptiveStrategy.conservative:
      case AdaptiveStrategy.powerSaver:
        // Prefer most reliable provider
        break;
      case AdaptiveStrategy.offline:
        // Use cached audio only
        break;
      default:
        break;
    }
  }
  
  /// Handle app state changes
  void _handleAppStateChange(AppUsageState state) {
    switch (state) {
      case AppUsageState.background:
      case AppUsageState.backgroundLong:
        // Pause or stop TTS in background
        if (_isPlaying) {
          pauseSpeaking();
        }
        break;
      case AppUsageState.active:
        // Resume if paused
        _updateTTSConfig();
        break;
      default:
        break;
    }
  }
  
  /// Record successful provider interaction
  void _recordProviderSuccess(TTSProvider provider, int latency) {
    final metrics = _providerMetrics[provider]!;
    metrics.recordSuccess(latency);
    
    print('[EnhancedTTS] Provider $provider success: ${latency}ms latency');
  }
  
  /// Record provider error
  void _recordProviderError(TTSProvider provider, String error) {
    final metrics = _providerMetrics[provider]!;
    metrics.recordError(error);
    
    print('[EnhancedTTS] Provider $provider error: $error');
  }
  
  /// Snapshot of state, buffer sizes, the config and provider metrics, with snake_case keys.
  Map<String, dynamic> getTTSStatistics() {
    return {
      'is_initialized': _isInitialized,
      'is_generating': _isGenerating,
      'is_playing': _isPlaying,
      'current_provider': _currentProvider.toString(),
      'current_quality': _currentQuality.toString(),
      'audio_buffer_size': _audioBuffer.length,
      'cache_size': _audioCache.length,
      'current_config': _currentConfig.toMap(),
      'provider_metrics': _providerMetrics.map(
        (provider, metrics) => MapEntry(provider.toString(), metrics.toMap()),
      ),
    };
  }
  
  /// Helper methods for provider configuration
  String _getDefaultVoiceId(TTSQuality quality) {
    switch (quality) {
      case TTSQuality.high:
        return '21m00Tcm4TlvDq8ikWAM'; // Rachel
      case TTSQuality.standard:
        return 'EXAVITQu4vr4xnSDxMaL'; // Bella
      case TTSQuality.low:
        return 'ErXwobaYiN019PkySvjV'; // Antoni
    }
  }
  
  String _getElevenLabsModel(TTSQuality quality) {
    switch (quality) {
      case TTSQuality.high:
        return 'eleven_turbo_v2_5';
      case TTSQuality.standard:
        return 'eleven_turbo_v2';
      case TTSQuality.low:
        return 'eleven_flash_v2_5';
    }
  }
  
  double _getQualityStability(TTSQuality quality) {
    switch (quality) {
      case TTSQuality.high:
        return 0.8;
      case TTSQuality.standard:
        return 0.5;
      case TTSQuality.low:
        return 0.3;
    }
  }
  
  double _getQualitySimilarity(TTSQuality quality) {
    switch (quality) {
      case TTSQuality.high:
        return 0.9;
      case TTSQuality.standard:
        return 0.8;
      case TTSQuality.low:
        return 0.6;
    }
  }
  
  String _getOpenAIVoice(TTSQuality quality) {
    switch (quality) {
      case TTSQuality.high:
        return 'nova';
      case TTSQuality.standard:
        return 'alloy';
      case TTSQuality.low:
        return 'echo';
    }
  }
  
  String _getOpenAIModel(TTSQuality quality) {
    switch (quality) {
      case TTSQuality.high:
        return 'tts-1-hd';
      case TTSQuality.standard:
      case TTSQuality.low:
        return 'tts-1';
    }
  }
  
  /// Stops speech and releases the player, subscriptions and streams.
  Future<void> dispose() async {
    print('[EnhancedTTS] Disposing enhanced TTS service');
    
    await stopSpeaking();
    _bufferTimer?.cancel();
    
    await _audioPlayer?.dispose();
    
    _ttsEventController.close();
    _statusController.close();
    _bufferController.close();
    
    _audioCache.clear();
    _clearAudioBuffer();
    
    _isInitialized = false;
  }
}

/// Text-to-speech providers.
enum TTSProvider {
  /// OpenAI text-to-speech.
  openai,
  /// ElevenLabs text-to-speech.
  elevenlabs,
}

/// Quality levels, which choose the voice, model and voice settings.
enum TTSQuality {
  /// Lowest quality, for poor connections and background use.
  low,
  /// The default quality.
  standard,
  /// Highest quality, for good connections.
  high,
}

/// TTS settings chosen for the current adaptive strategy.
class TTSConfig {
  /// Request timeout, in seconds.
  final int requestTimeout;
  /// Number of buffered chunks before playback starts.
  final int bufferThreshold;
  /// Interval between playback ticks, in milliseconds.
  final int playbackInterval;
  /// Whether audio is cached.
  final bool enableCaching;
  /// Maximum number of cached entries.
  final int maxCacheSize;
  /// Quality used when a request gives none.
  final TTSQuality defaultQuality;
  /// Provider tried first.
  final TTSProvider preferredProvider;
  
  /// Creates a config; every field is required.
  const TTSConfig({
    required this.requestTimeout,
    required this.bufferThreshold,
    required this.playbackInterval,
    required this.enableCaching,
    required this.maxCacheSize,
    required this.defaultQuality,
    required this.preferredProvider,
  });
  
  /// Builds the default config: ElevenLabs at standard quality with caching on.
  factory TTSConfig.standard() {
    return const TTSConfig(
      requestTimeout: 30,
      bufferThreshold: 3,
      playbackInterval: 100,
      enableCaching: true,
      maxCacheSize: 50,
      defaultQuality: TTSQuality.standard,
      preferredProvider: TTSProvider.elevenlabs,
    );
  }
  
  /// Builds the config for an adaptive strategy.
  ///
  /// Performance gets faster timeouts and high quality. Conservative and power saver, and background, switch to OpenAI at low quality with caching off. Any other strategy gets [TTSConfig.standard].
  factory TTSConfig.fromAdaptiveConfig(
    AdaptiveConnectionConfig adaptiveConfig,
    AppUsageState? appState,
  ) {
    switch (adaptiveConfig.strategy) {
      case AdaptiveStrategy.performance:
        return const TTSConfig(
          requestTimeout: 20,
          bufferThreshold: 2,
          playbackInterval: 50,
          enableCaching: true,
          maxCacheSize: 100,
          defaultQuality: TTSQuality.high,
          preferredProvider: TTSProvider.elevenlabs,
        );
      case AdaptiveStrategy.conservative:
      case AdaptiveStrategy.powerSaver:
        return const TTSConfig(
          requestTimeout: 60,
          bufferThreshold: 5,
          playbackInterval: 200,
          enableCaching: false,
          maxCacheSize: 20,
          defaultQuality: TTSQuality.low,
          preferredProvider: TTSProvider.openai,
        );
      case AdaptiveStrategy.background:
        return const TTSConfig(
          requestTimeout: 90,
          bufferThreshold: 1,
          playbackInterval: 500,
          enableCaching: false,
          maxCacheSize: 10,
          defaultQuality: TTSQuality.low,
          preferredProvider: TTSProvider.openai,
        );
      default:
        return TTSConfig.standard();
    }
  }
  
  /// Serializes the config with snake_case keys.
  Map<String, dynamic> toMap() {
    return {
      'request_timeout': requestTimeout,
      'buffer_threshold': bufferThreshold,
      'playback_interval': playbackInterval,
      'enable_caching': enableCaching,
      'max_cache_size': maxCacheSize,
      'default_quality': defaultQuality.toString(),
      'preferred_provider': preferredProvider.toString(),
    };
  }
  
  @override
  String toString() {
    return 'TTSConfig(provider: $preferredProvider, quality: $defaultQuality, timeout: ${requestTimeout}s)';
  }
}

/// Rolling performance metrics for one TTS provider.
class TTSMetrics {
  int _totalRequests = 0;
  int _successfulRequests = 0;
  final List<int> _latencyHistory = [];
  final List<double> _qualityHistory = [];
  final List<String> _recentErrors = [];
  
  /// Share of requests that succeeded; 0 when there are none.
  double get successRate => _totalRequests > 0 ? _successfulRequests / _totalRequests : 0.0;
  /// Mean latency of the last 20 successes, in milliseconds.
  double get averageLatency => _latencyHistory.isEmpty ? 0.0 : 
      _latencyHistory.fold(0, (sum, latency) => sum + latency) / _latencyHistory.length;
  /// Mean quality score of the last 20 successes.
  double get averageQuality => _qualityHistory.isEmpty ? 0.0 :
      _qualityHistory.fold(0.0, (sum, quality) => sum + quality) / _qualityHistory.length;
  
  /// Records a success with its latency in milliseconds and a quality score from 0 to 1.
  void recordSuccess(int latency, [double quality = 1.0]) {
    _totalRequests++;
    _successfulRequests++;
    
    _latencyHistory.add(latency);
    if (_latencyHistory.length > 20) _latencyHistory.removeAt(0);
    
    _qualityHistory.add(quality);
    if (_qualityHistory.length > 20) _qualityHistory.removeAt(0);
  }
  
  /// Records a failed request and keeps the last 10 error messages.
  void recordError(String error) {
    _totalRequests++;
    
    _recentErrors.add(error);
    if (_recentErrors.length > 10) _recentErrors.removeAt(0);
  }
  
  /// Serializes the totals, rates and recent errors with snake_case keys.
  Map<String, dynamic> toMap() {
    return {
      'total_requests': _totalRequests,
      'successful_requests': _successfulRequests,
      'success_rate': successRate,
      'average_latency_ms': averageLatency,
      'average_quality': averageQuality,
      'recent_errors': List.from(_recentErrors),
    };
  }
}

/// Base type of the events [EnhancedTTSService.eventStream] emits for monitoring and UI.
abstract class TTSEvent {
  /// When the event happened.
  final DateTime timestamp;
  
  /// Base constructor for the event subclasses.
  const TTSEvent(this.timestamp);
  
  /// Builds a [GenerationStartedEvent].
  factory TTSEvent.generationStarted(DateTime timestamp, String text, TTSProvider provider, TTSQuality quality) = GenerationStartedEvent;
  /// Builds a [GenerationCompletedEvent].
  factory TTSEvent.generationCompleted(DateTime timestamp, String text, int chunks) = GenerationCompletedEvent;
  /// Builds a [PlaybackStartedEvent].
  factory TTSEvent.playbackStarted(DateTime timestamp) = PlaybackStartedEvent;
  /// Builds a [PlaybackCompletedEvent].
  factory TTSEvent.playbackCompleted(DateTime timestamp) = PlaybackCompletedEvent;
  /// Builds a [ChunkPlayedEvent].
  factory TTSEvent.chunkPlayed(DateTime timestamp, int bytes) = ChunkPlayedEvent;
  /// Builds a [PausedEvent].
  factory TTSEvent.paused(DateTime timestamp) = PausedEvent;
  /// Builds a [ResumedEvent].
  factory TTSEvent.resumed(DateTime timestamp) = ResumedEvent;
  /// Builds a [StoppedEvent].
  factory TTSEvent.stopped(DateTime timestamp) = StoppedEvent;
  /// Builds an [ErrorEvent].
  factory TTSEvent.error(DateTime timestamp, String error) = ErrorEvent;
  /// Builds a [DurationChangedEvent].
  factory TTSEvent.durationChanged(DateTime timestamp, Duration duration) = DurationChangedEvent;
  /// Builds a [PositionChangedEvent].
  factory TTSEvent.positionChanged(DateTime timestamp, Duration position) = PositionChangedEvent;
}

/// Emitted when speech generation starts.
class GenerationStartedEvent extends TTSEvent {
  /// Text being synthesized.
  final String text;
  /// Provider generating the speech.
  final TTSProvider provider;
  /// Quality of the generation.
  final TTSQuality quality;
  
  /// Creates the event.
  const GenerationStartedEvent(DateTime timestamp, this.text, this.provider, this.quality) : super(timestamp);
}

/// Emitted when generation finishes.
class GenerationCompletedEvent extends TTSEvent {
  /// Text that was synthesized.
  final String text;
  /// Number of audio chunks received.
  final int chunks;
  
  /// Creates the event.
  const GenerationCompletedEvent(DateTime timestamp, this.text, this.chunks) : super(timestamp);
}

/// Emitted when playback starts.
class PlaybackStartedEvent extends TTSEvent {
  /// Creates the event.
  const PlaybackStartedEvent(DateTime timestamp) : super(timestamp);
}

/// Emitted when playback finishes.
class PlaybackCompletedEvent extends TTSEvent {
  /// Creates the event.
  const PlaybackCompletedEvent(DateTime timestamp) : super(timestamp);
}

/// Emitted when an audio chunk is played.
class ChunkPlayedEvent extends TTSEvent {
  /// Size of the chunk, in bytes.
  final int bytes;
  
  /// Creates the event.
  const ChunkPlayedEvent(DateTime timestamp, this.bytes) : super(timestamp);
}

/// Emitted when playback is paused.
class PausedEvent extends TTSEvent {
  /// Creates the event.
  const PausedEvent(DateTime timestamp) : super(timestamp);
}

/// Emitted when playback resumes.
class ResumedEvent extends TTSEvent {
  /// Creates the event.
  const ResumedEvent(DateTime timestamp) : super(timestamp);
}

/// Emitted when speech is stopped.
class StoppedEvent extends TTSEvent {
  /// Creates the event.
  const StoppedEvent(DateTime timestamp) : super(timestamp);
}

/// Emitted when generation or playback fails.
class ErrorEvent extends TTSEvent {
  /// Description of the failure.
  final String error;
  
  /// Creates the event.
  const ErrorEvent(DateTime timestamp, this.error) : super(timestamp);
}

/// Emitted when the audio duration becomes known or changes.
class DurationChangedEvent extends TTSEvent {
  /// The new duration.
  final Duration duration;
  
  /// Creates the event.
  const DurationChangedEvent(DateTime timestamp, this.duration) : super(timestamp);
}

/// Emitted when the playback position changes.
class PositionChangedEvent extends TTSEvent {
  /// The new position.
  final Duration position;
  
  /// Creates the event.
  const PositionChangedEvent(DateTime timestamp, this.position) : super(timestamp);
}

/// Base type of the updates [EnhancedTTSService.statusStream] emits.
abstract class TTSStatusUpdate {
  /// When the update happened.
  final DateTime timestamp;
  
  /// Base constructor for the update subclasses.
  const TTSStatusUpdate(this.timestamp);
  
  /// Builds an [InitializedUpdate].
  factory TTSStatusUpdate.initialized(DateTime timestamp) = InitializedUpdate;
  /// Builds a [RequestSentUpdate].
  factory TTSStatusUpdate.requestSent(DateTime timestamp, TTSProvider provider, int textLength) = RequestSentUpdate;
  /// Builds a [StatusChangedUpdate].
  factory TTSStatusUpdate.statusChanged(DateTime timestamp, String status, Map<String, dynamic>? data) = StatusChangedUpdate;
}

/// Emitted once the service is initialized.
class InitializedUpdate extends TTSStatusUpdate {
  /// Creates the update.
  const InitializedUpdate(DateTime timestamp) : super(timestamp);
}

/// Emitted when a request is sent to the backend.
class RequestSentUpdate extends TTSStatusUpdate {
  /// Provider the request went to.
  final TTSProvider provider;
  /// Length of the text, in characters.
  final int textLength;
  
  /// Creates the update.
  const RequestSentUpdate(DateTime timestamp, this.provider, this.textLength) : super(timestamp);
}

/// Emitted when the backend reports a status.
class StatusChangedUpdate extends TTSStatusUpdate {
  /// Status reported by the backend.
  final String status;
  /// Payload sent with the status, or null.
  final Map<String, dynamic>? data;
  
  /// Creates the update.
  const StatusChangedUpdate(DateTime timestamp, this.status, this.data) : super(timestamp);
}

/// Base type of the events [EnhancedTTSService.bufferStream] emits.
abstract class AudioBufferEvent {
  /// When the event happened.
  final DateTime timestamp;
  
  /// Base constructor for the event subclasses.
  const AudioBufferEvent(this.timestamp);
  
  /// Builds a [ChunkAddedEvent].
  factory AudioBufferEvent.chunkAdded(DateTime timestamp, int bytes, int totalChunks) = ChunkAddedEvent;
}

/// Emitted when a chunk is added to the buffer.
class ChunkAddedEvent extends AudioBufferEvent {
  /// Size of the chunk, in bytes.
  final int bytes;
  /// Chunks in the buffer after this one was added.
  final int totalChunks;
  
  /// Creates the event.
  const ChunkAddedEvent(DateTime timestamp, this.bytes, this.totalChunks) : super(timestamp);
}

/// Failure raised by [EnhancedTTSService].
class TTSServiceException implements Exception {
  /// What failed.
  final String message;
  
  /// Creates the exception with [message].
  const TTSServiceException(this.message);
  
  @override
  String toString() => 'TTSServiceException: $message';
}