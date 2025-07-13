import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

/// HTTP service for making requests to the Lupin FastAPI backend.
/// 
/// Provides a centralized interface for all HTTP communications with
/// the backend server, including TTS requests, session management,
/// and file uploads.
class HttpService {
  final Dio _dio;
  
  /// Creates a new HTTP service instance.
  /// 
  /// Requires:
  ///   - dio must be a non-null, properly configured Dio instance
  /// 
  /// Ensures:
  ///   - Service is configured with appropriate timeouts and headers
  ///   - Logging interceptors are installed for debugging
  ///   - Base URL is set to the configured API endpoint
  HttpService(this._dio) {
    _configureDio();
  }
  
  void _configureDio() {
    // Configure base URL
    _dio.options.baseUrl = AppConstants.apiBaseUrl;
    
    // Configure timeouts
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 30);
    
    // Configure headers
    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    // Add interceptors for logging and error handling
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('[HTTP] $obj'),
    ));
    
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[HTTP] Request: ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        print('[HTTP] Response: ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (error, handler) {
        print('[HTTP] Error: ${error.message}');
        handler.next(error);
      },
    ));
  }
  
  /// Retrieves a new session ID from the FastAPI backend.
  /// 
  /// Requires:
  ///   - Backend server must be running and accessible
  ///   - Network connectivity must be available
  /// 
  /// Ensures:
  ///   - Returns a Map containing the session ID and related metadata
  ///   - Session ID can be used for WebSocket authentication
  /// 
  /// Raises:
  ///   - DioException if network request fails
  ///   - FormatException if response format is invalid
  Future<Map<String, dynamic>> getSessionId() async {
    try {
      final response = await _dio.get('/api/get-session-id');
      return response.data;
    } catch (e) {
      print('[HTTP] Session ID request failed: $e');
      rethrow;
    }
  }
  
  /// Requests text-to-speech generation using ElevenLabs provider.
  /// 
  /// Requires:
  ///   - sessionId must be a valid, non-empty session identifier
  ///   - text must be non-empty and contain valid characters for TTS
  ///   - voiceId must be a valid ElevenLabs voice identifier
  ///   - stability must be between 0.0 and 1.0
  ///   - similarityBoost must be between 0.0 and 1.0
  /// 
  /// Ensures:
  ///   - Returns HTTP response containing audio data or stream information
  ///   - Audio generation is initiated on the backend
  ///   - Response includes necessary metadata for audio playback
  /// 
  /// Raises:
  ///   - DioException if TTS request fails
  ///   - ArgumentError if parameters are invalid
  Future<Response> requestElevenLabsTTS({
    required String sessionId,
    required String text,
    String voiceId = '21m00Tcm4TlvDq8ikWAM',
    double stability = 0.5,
    double similarityBoost = 0.8,
  }) async {
    try {
      final response = await _dio.post(
        '/api/get-speech-elevenlabs',
        data: {
          'session_id': sessionId,
          'text': text,
          'voice_id': voiceId,
          'stability': stability,
          'similarity_boost': similarityBoost,
        },
      );
      return response;
    } catch (e) {
      print('[HTTP] ElevenLabs TTS request failed: $e');
      rethrow;
    }
  }
  
  /// Requests text-to-speech generation using OpenAI provider.
  /// 
  /// Requires:
  ///   - sessionId must be a valid, non-empty session identifier
  ///   - text must be non-empty and within OpenAI's character limits
  /// 
  /// Ensures:
  ///   - Returns HTTP response containing audio data
  ///   - Audio generation is completed on the backend
  ///   - Response format is compatible with audio playback
  /// 
  /// Raises:
  ///   - DioException if TTS request fails
  ///   - ArgumentError if sessionId or text is invalid
  Future<Response> requestOpenAITTS({
    required String sessionId,
    required String text,
  }) async {
    try {
      final response = await _dio.post(
        '/api/get-speech',
        data: {
          'session_id': sessionId,
          'text': text,
        },
      );
      return response;
    } catch (e) {
      print('[HTTP] OpenAI TTS request failed: $e');
      rethrow;
    }
  }
  
  /// Uploads an audio file and requests transcription.
  /// 
  /// Requires:
  ///   - filePath must point to a valid, readable audio file
  ///   - sessionId must be a valid session identifier
  ///   - File must be in a supported audio format (MP3, WAV, M4A)
  ///   - File size must be within backend limits
  /// 
  /// Ensures:
  ///   - Audio file is uploaded to the backend
  ///   - Transcription is processed and returned
  ///   - Returns transcription text with confidence scores
  /// 
  /// Raises:
  ///   - DioException if upload or transcription fails
  ///   - FileSystemException if file cannot be read
  ///   - ArgumentError if file format is unsupported
  Future<Map<String, dynamic>> uploadAndTranscribe({
    required String filePath,
    required String sessionId,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'session_id': sessionId,
      });
      
      final response = await _dio.post(
        '/api/upload-and-transcribe-mp3',
        data: formData,
      );
      
      return response.data;
    } catch (e) {
      print('[HTTP] Audio upload failed: $e');
      rethrow;
    }
  }
  
  /// Performs a health check on the backend server.
  /// 
  /// Requires:
  ///   - Network connectivity must be available
  /// 
  /// Ensures:
  ///   - Returns true if server is healthy and responsive
  ///   - Returns false if server is unreachable or unhealthy
  ///   - Does not throw exceptions for network failures
  /// 
  /// Raises:
  ///   - No exceptions are raised (all errors are caught and return false)
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      print('[HTTP] Health check failed: $e');
      return false;
    }
  }
  
  /// Performs a generic GET request to the specified path.
  /// 
  /// Requires:
  ///   - path must be a valid API endpoint path
  ///   - queryParameters (if provided) must contain valid key-value pairs
  /// 
  /// Ensures:
  ///   - Returns HTTP response with the requested data
  ///   - Response type T matches the expected response format
  ///   - Request is logged for debugging purposes
  /// 
  /// Raises:
  ///   - DioException if HTTP request fails
  ///   - FormatException if response cannot be parsed as type T
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      print('[HTTP] GET request failed: $e');
      rethrow;
    }
  }
  
  /// Performs a generic POST request to the specified path.
  /// 
  /// Requires:
  ///   - path must be a valid API endpoint path
  ///   - data (if provided) must be serializable to JSON or form data
  /// 
  /// Ensures:
  ///   - Returns HTTP response with the server's response data
  ///   - Request body is properly encoded and sent
  ///   - Response type T matches the expected response format
  /// 
  /// Raises:
  ///   - DioException if HTTP request fails
  ///   - FormatException if data cannot be serialized or response parsed
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      print('[HTTP] POST request failed: $e');
      rethrow;
    }
  }
  
  /// Performs a generic PUT request to the specified path.
  /// 
  /// Requires:
  ///   - path must be a valid API endpoint path
  ///   - data (if provided) must be serializable to JSON
  /// 
  /// Ensures:
  ///   - Returns HTTP response indicating update success or failure
  ///   - Resource at the specified path is updated with provided data
  ///   - Response type T matches the expected response format
  /// 
  /// Raises:
  ///   - DioException if HTTP request fails
  ///   - FormatException if data cannot be serialized
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      print('[HTTP] PUT request failed: $e');
      rethrow;
    }
  }
  
  /// Performs a generic DELETE request to the specified path.
  /// 
  /// Requires:
  ///   - path must be a valid API endpoint path
  ///   - User must have permission to delete the specified resource
  /// 
  /// Ensures:
  ///   - Returns HTTP response indicating deletion success or failure
  ///   - Resource at the specified path is removed (if successful)
  ///   - Response type T matches the expected response format
  /// 
  /// Raises:
  ///   - DioException if HTTP request fails
  ///   - UnauthorizedException if user lacks deletion permissions
  Future<Response<T>> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      print('[HTTP] DELETE request failed: $e');
      rethrow;
    }
  }
}