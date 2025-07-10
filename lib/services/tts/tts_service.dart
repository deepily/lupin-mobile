import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import '../websocket/websocket_service.dart';
import '../../core/constants/app_constants.dart';

/// Available TTS providers supported by the service.
enum TTSProvider {
  openai,
  elevenlabs,
}

/// Text-to-Speech service for converting text to audio.
/// 
/// Manages TTS requests through WebSocket connection and handles
/// audio playback using native audio players.
class TTSService {
  final WebSocketService _webSocketService;
  final Dio _dio;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  StreamController<String>? _statusController;
  StreamController<Uint8List>? _audioChunkController;
  
  bool _isInitialized = false;
  TTSProvider _currentProvider = TTSProvider.elevenlabs;

  // Public getters
  bool get isInitialized => _isInitialized;
  Stream<String> get statusStream => _statusController?.stream ?? const Stream.empty();
  Stream<Uint8List> get audioChunkStream => _audioChunkController?.stream ?? const Stream.empty();

  /// Creates a new TTS service instance.
  /// 
  /// Requires:
  ///   - webSocketService must be non-null and properly configured
  ///   - dio must be non-null HTTP client instance
  /// 
  /// Ensures:
  ///   - Service initialization starts automatically
  ///   - Audio player is configured for low latency
  ///   - WebSocket message listeners are established
  TTSService({
    required WebSocketService webSocketService,
    required Dio dio,
  })  : _webSocketService = webSocketService,
        _dio = dio {
    _initialize();
  }

  /// Initializes the TTS service components.
  /// 
  /// Ensures:
  ///   - Stream controllers are created and ready
  ///   - Audio player is configured for optimal TTS playback
  ///   - WebSocket message handlers are registered
  ///   - Service status is set to initialized on success
  /// 
  /// Note: Errors during initialization are caught and reported
  /// through the status stream rather than thrown.
  Future<void> _initialize() async {
    try {
      _statusController = StreamController<String>.broadcast();
      _audioChunkController = StreamController<Uint8List>.broadcast();
      
      // Configure audio player for low latency
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
      
      // Listen to WebSocket messages for audio chunks
      _webSocketService.stream.listen((message) {
        _handleWebSocketMessage(message);
      });
      
      _isInitialized = true;
      _statusController?.add('initialized');
      
      print('[TTS] Service initialized');
    } catch (e) {
      print('[TTS] Initialization failed: $e');
      _statusController?.add('error: $e');
    }
  }

  /// Handles incoming WebSocket messages for TTS operations.
  /// 
  /// Requires:
  ///   - message must be Map<String, dynamic> with 'type' field
  /// 
  /// Ensures:
  ///   - Audio chunks are forwarded to playback
  ///   - Status updates are sent to status stream
  ///   - Errors are propagated to listeners
  void _handleWebSocketMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      switch (message['type']) {
        case 'audio_chunk':
          if (message['data'] is List<int>) {
            final audioData = Uint8List.fromList(message['data']);
            playAudioChunk(audioData);
          }
          break;
        case 'status':
          _statusController?.add(message['text'] ?? 'status update');
          break;
        case 'audio_complete':
          _statusController?.add('complete');
          print('[TTS] ${message['text']}');
          break;
        case 'error':
          _statusController?.add('error: ${message['text']}');
          break;
      }
    }
  }

  /// Converts text to speech using the specified provider.
  /// 
  /// Requires:
  ///   - text must be non-empty string
  ///   - Service must be initialized
  ///   - WebSocket connection should be active
  /// 
  /// Ensures:
  ///   - TTS request is sent to backend
  ///   - Status stream is updated with progress
  ///   - Audio chunks will be received via WebSocket
  /// 
  /// Throws:
  ///   - [Exception] if service is not initialized
  ///   - [DioException] if HTTP request fails
  Future<void> speak(String text, {TTSProvider? provider}) async {
    if (!_isInitialized) {
      throw Exception('TTS Service not initialized');
    }

    final ttsProvider = provider ?? _currentProvider;
    
    try {
      _statusController?.add('generating');
      
      switch (ttsProvider) {
        case TTSProvider.elevenlabs:
          await _speakWithElevenLabs(text);
          break;
        case TTSProvider.openai:
          await _speakWithOpenAI(text);
          break;
      }
    } catch (e) {
      print('[TTS] Speech generation failed: $e');
      _statusController?.add('error: $e');
      rethrow;
    }
  }

  Future<void> _speakWithElevenLabs(String text) async {
    try {
      // Ensure WebSocket connection is established first
      if (!_webSocketService.isConnected) {
        await _webSocketService.connect();
        // Wait a brief moment for connection to stabilize
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      final sessionId = _webSocketService.sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
      
      // Use new parallel ElevenLabs endpoint
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/api/get-audio-elevenlabs',
        data: {
          'session_id': sessionId,
          'text': text,
          'voice_id': '21m00Tcm4TlvDq8ikWAM', // Default Rachel voice
          'stability': 0.5,
          'similarity_boost': 0.8,
        },
      );

      if (response.statusCode == 200) {
        _statusController?.add('requested');
        print('[TTS] ElevenLabs TTS request sent successfully');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.statusMessage}');
      }
    } catch (e) {
      print('[TTS] ElevenLabs request failed: $e');
      throw e;
    }
  }

  Future<void> _speakWithOpenAI(String text) async {
    try {
      final sessionId = _webSocketService.sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
      
      // Use existing OpenAI endpoint
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}${AppConstants.apiGetAudio}',
        data: {
          'session_id': sessionId,
          'text': text,
        },
      );

      if (response.statusCode == 200) {
        _statusController?.add('success');
        print('[TTS] OpenAI TTS request sent successfully');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.statusMessage}');
      }
    } catch (e) {
      print('[TTS] OpenAI request failed: $e');
      throw e;
    }
  }

  /// Plays an audio chunk received from TTS service.
  /// 
  /// Requires:
  ///   - audioData must be valid audio bytes
  ///   - Audio player must be initialized
  /// 
  /// Ensures:
  ///   - Audio chunk is played through device speakers
  ///   - Chunk is added to audio stream for listeners
  ///   - Errors are reported via status stream
  Future<void> playAudioChunk(Uint8List audioData) async {
    try {
      // Add chunk to stream for listeners
      _audioChunkController?.add(audioData);
      
      // Play the audio chunk using AudioPlayer
      await _audioPlayer.play(BytesSource(audioData));
      
      print('[TTS] Playing audio chunk: ${audioData.length} bytes');
      
    } catch (e) {
      print('[TTS] Audio playback failed: $e');
      _statusController?.add('playback_error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _audioPlayer.stop();
      _statusController?.add('stopped');
      print('[TTS] Playback stopped');
    } catch (e) {
      print('[TTS] Stop failed: $e');
    }
  }

  Future<void> pauseSpeaking() async {
    try {
      await _audioPlayer.pause();
      _statusController?.add('paused');
      print('[TTS] Playback paused');
    } catch (e) {
      print('[TTS] Pause failed: $e');
    }
  }

  Future<void> resumeSpeaking() async {
    try {
      await _audioPlayer.resume();
      _statusController?.add('resumed');
      print('[TTS] Playback resumed');
    } catch (e) {
      print('[TTS] Resume failed: $e');
    }
  }

  void setProvider(TTSProvider provider) {
    _currentProvider = provider;
    print('[TTS] Provider set to: ${provider.name}');
  }

  TTSProvider getCurrentProvider() {
    return _currentProvider;
  }

  void dispose() {
    _audioPlayer.dispose();
    _statusController?.close();
    _audioChunkController?.close();
    _statusController = null;
    _audioChunkController = null;
    _isInitialized = false;
  }
}