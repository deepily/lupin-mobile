import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class HttpService {
  final Dio _dio;
  
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
  
  // Session management
  Future<Map<String, dynamic>> getSessionId() async {
    try {
      final response = await _dio.get('/api/get-session-id');
      return response.data;
    } catch (e) {
      print('[HTTP] Session ID request failed: $e');
      rethrow;
    }
  }
  
  // TTS endpoints
  Future<Response> requestElevenLabsTTS({
    required String sessionId,
    required String text,
    String voiceId = '21m00Tcm4TlvDq8ikWAM',
    double stability = 0.5,
    double similarityBoost = 0.8,
  }) async {
    try {
      final response = await _dio.post(
        '/api/get-audio-elevenlabs',
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
  
  Future<Response> requestOpenAITTS({
    required String sessionId,
    required String text,
  }) async {
    try {
      final response = await _dio.post(
        '/api/get-audio',
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
  
  // Audio upload and transcription
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
  
  // Health check
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      print('[HTTP] Health check failed: $e');
      return false;
    }
  }
  
  // Generic GET request
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
  
  // Generic POST request
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
  
  // Generic PUT request
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
  
  // Generic DELETE request
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