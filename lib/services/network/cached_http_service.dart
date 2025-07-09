import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/cache/network_cache.dart';
import '../../core/cache/offline_manager.dart';
import 'http_service.dart';

/// Enhanced HTTP service with caching and offline support
class CachedHttpService extends HttpService {
  late final NetworkCache _networkCache;
  late final OfflineManager _offlineManager;
  bool _initialized = false;

  CachedHttpService(Dio dio) : super(dio) {
    _initialize();
  }

  /// Initialize caching components
  Future<void> _initialize() async {
    if (_initialized) return;
    
    _networkCache = await NetworkCache.getInstance();
    _offlineManager = await OfflineManager.getInstance();
    _initialized = true;
  }

  /// Ensure initialization is complete
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _initialize();
    }
  }

  /// Enhanced GET request with caching
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool useCache = true,
    Duration? cacheTtl,
  }) async {
    await _ensureInitialized();
    
    if (useCache) {
      // Try to get from cache first
      final cachedResponse = await _networkCache.getCachedGetResponse(
        path,
        queryParameters,
      );
      
      if (cachedResponse != null) {
        return cachedResponse.toDioResponse<T>();
      }
    }
    
    // If offline and no cache, queue request
    if (_offlineManager.isOffline) {
      await _offlineManager.queueRequest(
        'GET_${path}_${queryParameters?.toString() ?? ''}',
        {
          'method': 'GET',
          'path': path,
          'queryParameters': queryParameters,
          'options': options?.extra,
        },
      );
      
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'Device is offline and no cached response available',
        type: DioExceptionType.connectionError,
      );
    }
    
    try {
      // Make network request
      final response = await super.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      
      // Cache successful responses
      if (useCache && response.statusCode == 200) {
        await _networkCache.cacheGetResponse(
          path,
          queryParameters,
          response,
          ttl: cacheTtl,
        );
      }
      
      return response;
    } catch (e) {
      // On network error, try cache again with longer TTL tolerance
      if (useCache) {
        final cachedResponse = await _networkCache.getCachedGetResponse(
          path,
          queryParameters,
        );
        
        if (cachedResponse != null) {
          print('[HTTP] Using stale cache due to network error');
          return cachedResponse.toDioResponse<T>();
        }
      }
      
      rethrow;
    }
  }

  /// Enhanced POST request with optional caching
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool useCache = false,
    Duration? cacheTtl,
  }) async {
    await _ensureInitialized();
    
    if (useCache) {
      // Try to get from cache first (for idempotent POST operations)
      final cachedResponse = await _networkCache.getCachedPostResponse(
        path,
        data is Map<String, dynamic> ? data : null,
      );
      
      if (cachedResponse != null) {
        return cachedResponse.toDioResponse<T>();
      }
    }
    
    // If offline, queue request
    if (_offlineManager.isOffline) {
      await _offlineManager.queueRequest(
        'POST_${path}_${data.toString()}',
        {
          'method': 'POST',
          'path': path,
          'data': data,
          'queryParameters': queryParameters,
          'options': options?.extra,
        },
      );
      
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'Device is offline - request queued for later',
        type: DioExceptionType.connectionError,
      );
    }
    
    try {
      // Make network request
      final response = await super.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      
      // Cache successful responses (for idempotent operations)
      if (useCache && response.statusCode == 200) {
        await _networkCache.cachePostResponse(
          path,
          data is Map<String, dynamic> ? data : null,
          response,
          ttl: cacheTtl,
        );
      }
      
      return response;
    } catch (e) {
      // On network error, try cache if available
      if (useCache) {
        final cachedResponse = await _networkCache.getCachedPostResponse(
          path,
          data is Map<String, dynamic> ? data : null,
        );
        
        if (cachedResponse != null) {
          print('[HTTP] Using stale cache due to network error');
          return cachedResponse.toDioResponse<T>();
        }
      }
      
      rethrow;
    }
  }

  /// Session management with caching
  @override
  Future<Map<String, dynamic>> getSessionId() async {
    await _ensureInitialized();
    
    try {
      final response = await get<Map<String, dynamic>>(
        '/api/get-session-id',
        useCache: true,
        cacheTtl: Duration(minutes: 5),
      );
      return response.data ?? {};
    } catch (e) {
      print('[HTTP] Session ID request failed: $e');
      rethrow;
    }
  }

  /// TTS request with caching
  @override
  Future<Response> requestElevenLabsTTS({
    required String sessionId,
    required String text,
    String voiceId = '21m00Tcm4TlvDq8ikWAM',
    double stability = 0.5,
    double similarityBoost = 0.8,
  }) async {
    await _ensureInitialized();
    
    try {
      final response = await post(
        '/api/get-audio-elevenlabs',
        data: {
          'session_id': sessionId,
          'text': text,
          'voice_id': voiceId,
          'stability': stability,
          'similarity_boost': similarityBoost,
        },
        useCache: true,
        cacheTtl: Duration(hours: 1),
      );
      return response;
    } catch (e) {
      print('[HTTP] ElevenLabs TTS request failed: $e');
      rethrow;
    }
  }

  /// OpenAI TTS request with caching
  @override
  Future<Response> requestOpenAITTS({
    required String sessionId,
    required String text,
  }) async {
    await _ensureInitialized();
    
    try {
      final response = await post(
        '/api/get-audio',
        data: {
          'session_id': sessionId,
          'text': text,
        },
        useCache: true,
        cacheTtl: Duration(hours: 1),
      );
      return response;
    } catch (e) {
      print('[HTTP] OpenAI TTS request failed: $e');
      rethrow;
    }
  }

  /// Health check with caching
  @override
  Future<bool> checkHealth() async {
    await _ensureInitialized();
    
    try {
      final response = await get(
        '/health',
        useCache: true,
        cacheTtl: Duration(minutes: 2),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('[HTTP] Health check failed: $e');
      return false;
    }
  }

  /// Clear cache for specific URL pattern
  Future<void> clearCacheForUrl(String urlPattern) async {
    await _ensureInitialized();
    await _networkCache.invalidateUrl(urlPattern);
  }

  /// Clear all HTTP cache
  Future<void> clearAllCache() async {
    await _ensureInitialized();
    await _networkCache.clearAll();
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    await _ensureInitialized();
    final stats = await _networkCache.getStats();
    return stats.toJson();
  }

  /// Process queued requests when back online
  Future<void> processQueuedRequests() async {
    await _ensureInitialized();
    
    if (_offlineManager.isOffline) {
      print('[HTTP] Cannot process queued requests - still offline');
      return;
    }
    
    final queuedRequests = _offlineManager.getQueuedRequests();
    print('[HTTP] Processing ${queuedRequests.length} queued requests');
    
    for (final request in queuedRequests) {
      try {
        final data = request.data;
        final method = data['method'] as String;
        final path = data['path'] as String;
        
        switch (method) {
          case 'GET':
            await super.get(
              path,
              queryParameters: data['queryParameters'],
            );
            break;
          case 'POST':
            await super.post(
              path,
              data: data['data'],
              queryParameters: data['queryParameters'],
            );
            break;
          case 'PUT':
            await super.put(
              path,
              data: data['data'],
              queryParameters: data['queryParameters'],
            );
            break;
          case 'DELETE':
            await super.delete(
              path,
              queryParameters: data['queryParameters'],
            );
            break;
        }
        
        await _offlineManager.removeFromQueue(request.key);
        print('[HTTP] Successfully processed queued request: ${request.key}');
      } catch (e) {
        print('[HTTP] Failed to process queued request ${request.key}: $e');
      }
    }
  }
}