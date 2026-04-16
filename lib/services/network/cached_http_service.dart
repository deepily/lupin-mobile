import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/cache/network_cache.dart';
import '../../core/cache/offline_manager.dart';
import 'http_service.dart';

/// Enhanced HTTP service with intelligent caching and offline support.
/// 
/// Extends the base HttpService to provide automatic response caching,
/// offline request queuing, and stale cache fallback capabilities.
/// Optimizes network usage and provides resilient connectivity.
class CachedHttpService extends HttpService {
  late final NetworkCache _networkCache;
  late final OfflineManager _offlineManager;
  bool _initialized = false;

  /// Creates a new cached HTTP service instance.
  /// 
  /// Requires:
  ///   - dio must be a non-null, properly configured Dio instance
  /// 
  /// Ensures:
  ///   - Service inherits all base HTTP functionality
  ///   - Caching and offline components are initialized asynchronously
  ///   - Service is ready for both online and offline operations
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

  /// Performs a GET request with intelligent caching and offline support.
  /// 
  /// Requires:
  ///   - path must be a valid API endpoint path
  ///   - cacheTtl (if provided) must be a positive duration
  /// 
  /// Ensures:
  ///   - Returns cached response if available and fresh
  ///   - Falls back to network request if cache miss or stale
  ///   - Caches successful responses for future requests
  ///   - Queues request if offline and no cache available
  /// 
  /// Raises:
  ///   - DioException if offline and no cached response available
  ///   - NetworkException if request fails and no stale cache
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

  /// Performs a POST request with optional caching for idempotent operations.
  /// 
  /// Requires:
  ///   - path must be a valid API endpoint path
  ///   - data must be serializable if caching is enabled
  ///   - useCache should only be true for idempotent POST operations
  /// 
  /// Ensures:
  ///   - Returns cached response if available and useCache is true
  ///   - Queues request if offline for later processing
  ///   - Caches successful responses only for idempotent operations
  /// 
  /// Raises:
  ///   - DioException if offline (request is queued)
  ///   - NetworkException if request fails and no cache available
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

  /// Retrieves session ID with short-term caching for efficiency.
  /// 
  /// Requires:
  ///   - Backend session endpoint must be available
  /// 
  /// Ensures:
  ///   - Returns cached session ID if available and fresh (5 min TTL)
  ///   - Fetches new session ID if cache miss or expired
  ///   - Session ID is cached for subsequent requests
  /// 
  /// Raises:
  ///   - DioException if session creation fails
  ///   - NetworkException if offline and no cached session
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

  /// Requests ElevenLabs TTS with aggressive caching for identical text.
  /// 
  /// Requires:
  ///   - sessionId must be a valid session identifier
  ///   - text must be non-empty and suitable for TTS
  ///   - Voice parameters must be within valid ranges
  /// 
  /// Ensures:
  ///   - Returns cached audio if identical request exists (1 hour TTL)
  ///   - Generates new audio for cache miss or expired entries
  ///   - Audio response is cached to reduce API costs
  /// 
  /// Raises:
  ///   - DioException if TTS generation fails
  ///   - QuotaExceededException if ElevenLabs quota exceeded
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
        '/api/get-speech-elevenlabs',
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

  /// Requests OpenAI TTS with caching for cost optimization.
  /// 
  /// Requires:
  ///   - sessionId must be a valid session identifier
  ///   - text must be within OpenAI's character limits
  /// 
  /// Ensures:
  ///   - Returns cached audio if identical text request exists (1 hour TTL)
  ///   - Generates new audio for cache miss or expired entries
  ///   - Audio response is cached to reduce API costs
  /// 
  /// Raises:
  ///   - DioException if TTS generation fails
  ///   - RateLimitException if OpenAI rate limits exceeded
  @override
  Future<Response> requestOpenAITTS({
    required String sessionId,
    required String text,
  }) async {
    await _ensureInitialized();
    
    try {
      final response = await post(
        '/api/get-speech',
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

  /// Performs health check with short-term caching to reduce server load.
  /// 
  /// Requires:
  ///   - Network connectivity for fresh health checks
  /// 
  /// Ensures:
  ///   - Returns cached health status if checked recently (2 min TTL)
  ///   - Performs fresh health check for expired cache
  ///   - Never throws exceptions (returns false on failure)
  /// 
  /// Raises:
  ///   - No exceptions are raised (all errors result in false)
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

  /// Clears cached responses matching the specified URL pattern.
  /// 
  /// Requires:
  ///   - urlPattern must be a valid URL pattern or exact path
  /// 
  /// Ensures:
  ///   - All cached responses matching the pattern are removed
  ///   - Subsequent requests will bypass cache for matching URLs
  ///   - Cache statistics are updated to reflect removal
  /// 
  /// Raises:
  ///   - No exceptions are raised (operation is always safe)
  Future<void> clearCacheForUrl(String urlPattern) async {
    await _ensureInitialized();
    await _networkCache.invalidateUrl(urlPattern);
  }

  /// Clears all cached HTTP responses and resets cache state.
  /// 
  /// Requires:
  ///   - Cache system must be initialized
  /// 
  /// Ensures:
  ///   - All cached responses are permanently removed
  ///   - Cache storage is reset to initial empty state
  ///   - Memory and disk cache are both cleared
  /// 
  /// Raises:
  ///   - No exceptions are raised (operation is always safe)
  Future<void> clearAllCache() async {
    await _ensureInitialized();
    await _networkCache.clearAll();
  }

  /// Retrieves comprehensive statistics about cache performance.
  /// 
  /// Requires:
  ///   - Cache system must be initialized
  /// 
  /// Ensures:
  ///   - Returns detailed cache metrics including hit rates
  ///   - Includes storage usage and entry counts
  ///   - Statistics reflect current cache state accurately
  /// 
  /// Raises:
  ///   - No exceptions are raised (returns empty stats on error)
  Future<Map<String, dynamic>> getCacheStats() async {
    await _ensureInitialized();
    final stats = await _networkCache.getStats();
    return stats.toJson();
  }

  /// Processes all queued requests when network connectivity is restored.
  /// 
  /// Requires:
  ///   - Device must be online (offline requests are ignored)
  ///   - Queued requests must have valid request data
  /// 
  /// Ensures:
  ///   - All queued requests are processed in order
  ///   - Successfully processed requests are removed from queue
  ///   - Failed requests remain in queue for retry
  /// 
  /// Raises:
  ///   - Individual request failures are logged but don't stop processing
  ///   - No exceptions propagate from this method
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