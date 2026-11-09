import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'cache_manager.dart';
import 'cache_policy.dart';
import 'offline_manager.dart';

/// Network response cache for HTTP requests
class NetworkCache {
  static NetworkCache? _instance;
  late final CacheManager<NetworkResponse> _responseCache;
  late final OfflineManager _offlineManager;
  
  final StreamController<CacheEvent> _eventController = 
      StreamController<CacheEvent>.broadcast();

  NetworkCache._(OfflineManager offlineManager) : _offlineManager = offlineManager {
    _initialize();
  }

  /// Get singleton instance
  static Future<NetworkCache> getInstance() async {
    if (_instance == null) {
      final offlineManager = await OfflineManager.getInstance();
      _instance = NetworkCache._(offlineManager);
    }
    return _instance!;
  }

  /// Initialize network cache
  void _initialize() {
    _responseCache = _offlineManager.getCacheManager<NetworkResponse>(
      cacheKey: 'network_responses',
      toJson: (response) => response.toJson(),
      fromJson: (json) => NetworkResponse.fromJson(json),
      policy: CachePolicy.defaultPolicy,
      calculateSize: (response) => response.data.toString().length,
    );
  }

  /// Cache network response
  Future<void> cacheResponse(
    String method,
    String url,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
    Response response, {
    Duration? customTtl,
  }) async {
    final cacheKey = _generateCacheKey(method, url, queryParameters, data);
    
    final networkResponse = NetworkResponse(
      method: method,
      url: url,
      queryParameters: queryParameters,
      requestData: data,
      statusCode: response.statusCode ?? 0,
      data: response.data,
      headers: response.headers.map,
      timestamp: DateTime.now(),
      ttl: customTtl ?? const Duration(minutes: 30),
    );
    
    await _responseCache.put(
      cacheKey,
      networkResponse,
      metadata: {
        'request_method': method,
        'request_url': url,
        'status_code': response.statusCode,
        'content_type': response.headers.value('content-type'),
      },
    );
    
    _eventController.add( CachePutEvent( _eventKey( method, url ), details: _eventDetails( method, url, response.statusCode ?? 0 ) ) );
  }

  /// Get cached response
  Future<NetworkResponse?> getCachedResponse(
    String method,
    String url,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
  ) async {
    final cacheKey = _generateCacheKey(method, url, queryParameters, data);
    final cachedResponse = await _responseCache.get(cacheKey);
    
    if (cachedResponse != null) {
      // Check if still valid (additional TTL check)
      if (cachedResponse.isExpired) {
        await _responseCache.remove(cacheKey);
        _eventController.add(CacheExpiredEvent( _eventKey( method, url ), details: _eventDetails( method, url ) ));
        return null;
      }
      
      _eventController.add(CacheHitEvent( _eventKey( method, url ), details: _eventDetails( method, url, cachedResponse.statusCode ) ));
      return cachedResponse;
    }
    
    _eventController.add(CacheMissEvent( _eventKey( method, url ), details: _eventDetails( method, url ) ));
    return null;
  }

  /// Cache GET request response
  Future<void> cacheGetResponse(
    String url,
    Map<String, dynamic>? queryParameters,
    Response response, {
    Duration? ttl,
  }) async {
    await cacheResponse('GET', url, queryParameters, null, response, customTtl: ttl);
  }

  /// Get cached GET response
  Future<NetworkResponse?> getCachedGetResponse(
    String url,
    Map<String, dynamic>? queryParameters,
  ) async {
    return await getCachedResponse('GET', url, queryParameters, null);
  }

  /// Cache POST request response (for idempotent operations)
  Future<void> cachePostResponse(
    String url,
    Map<String, dynamic>? data,
    Response response, {
    Duration? ttl,
  }) async {
    await cacheResponse('POST', url, null, data, response, customTtl: ttl);
  }

  /// Get cached POST response
  Future<NetworkResponse?> getCachedPostResponse(
    String url,
    Map<String, dynamic>? data,
  ) async {
    return await getCachedResponse('POST', url, null, data);
  }

  /// Invalidate cache for URL pattern
  Future<void> invalidateUrl(String urlPattern) async {
    final allKeys = _responseCache.memoryCache.keys.toList();
    
    for (final key in allKeys) {
      final response = await _responseCache.get(key);
      if (response != null && response.url.contains(urlPattern)) {
        await _responseCache.remove(key);
      }
    }
    
    _eventController.add(CacheInvalidateEvent(urlPattern));
  }

  /// Invalidate cache for specific method
  Future<void> invalidateMethod(String method) async {
    final allKeys = _responseCache.memoryCache.keys.toList();
    
    for (final key in allKeys) {
      final response = await _responseCache.get(key);
      if (response != null && response.method == method) {
        await _responseCache.remove(key);
      }
    }
    
    _eventController.add(CacheInvalidateEvent(method));
  }

  /// Get cache statistics
  Future<CacheStats> getStats() async {
    final cacheStats = _responseCache.getStats();
    
    // Count by method and status code
    final methodStats = <String, int>{};
    final statusStats = <int, int>{};
    
    for (final entry in _responseCache.memoryCache.entries) {
      final response = entry.value.value;
      methodStats[response.method] = (methodStats[response.method] ?? 0) + 1;
      statusStats[response.statusCode] = (statusStats[response.statusCode] ?? 0) + 1;
    }
    
    return cacheStats.withExtras( {
      "method_stats" : methodStats,
      "status_stats" : statusStats.map( ( key, value ) => MapEntry( key.toString(), value ) ),
    } );
  }

  /// Clear expired responses
  Future<void> clearExpired() async {
    final allKeys = _responseCache.memoryCache.keys.toList();
    int removedCount = 0;
    
    for (final key in allKeys) {
      final response = await _responseCache.get(key);
      if (response != null && response.isExpired) {
        await _responseCache.remove(key);
        removedCount++;
      }
    }
    
    _eventController.add(CacheCleanupEvent( removedCount ));
  }

  /// Clear all network cache
  Future<void> clearAll() async {
    await _responseCache.clear();
    _eventController.add(CacheClearEvent());
  }

  /// Stream of network cache events
  Stream<CacheEvent> get events => _eventController.stream;

  /// Dispose resources
  void dispose() {
    _eventController.close();
  }

  // Private helper methods

  /// Key shown on this cache's events: the HTTP method and URL.
  String _eventKey( String method, String url ) => "$method $url";

  /// Fields this cache adds to its events; status code only when known.
  Map<String, Object?> _eventDetails( String method, String url, [ int? statusCode ] ) {
    return {
      "method" : method,
      "url"    : url,
      if ( statusCode != null ) "status_code" : statusCode,
    };
  }

  String _generateCacheKey(
    String method,
    String url,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
  ) {
    final keyData = {
      'method': method,
      'url': url,
      'query': queryParameters,
      'data': data,
    };
    
    final keyString = jsonEncode(keyData);
    final bytes = utf8.encode(keyString);
    final digest = sha256.convert(bytes);
    
    return digest.toString();
  }
}

/// Network response wrapper for caching
class NetworkResponse {
  /// HTTP method.
  final String method;
  /// Request URL.
  final String url;
  /// Query parameters, or null.
  final Map<String, dynamic>? queryParameters;
  /// Request body, or null.
  final Map<String, dynamic>? requestData;
  /// HTTP status code.
  final int statusCode;
  /// The data.
  final dynamic data;
  /// Response headers.
  final Map<String, List<String>> headers;
  /// When the object was created.
  final DateTime timestamp;
  /// How long the response stays valid.
  final Duration ttl;

  /// Creates a [NetworkResponse].
  const NetworkResponse({
    required this.method,
    required this.url,
    this.queryParameters,
    this.requestData,
    required this.statusCode,
    required this.data,
    required this.headers,
    required this.timestamp,
    required this.ttl,
  });

  /// Check if response is expired
  bool get isExpired => DateTime.now().difference(timestamp) > ttl;

  /// Convert to Dio Response
  Response<T> toDioResponse<T>() {
    return Response<T>(
      data: data,
      statusCode: statusCode,
      headers: Headers.fromMap(headers),
      requestOptions: RequestOptions(
        method: method,
        path: url,
        queryParameters: queryParameters,
        data: requestData,
      ),
    );
  }

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'url': url,
      'query_parameters': queryParameters,
      'request_data': requestData,
      'status_code': statusCode,
      'data': data,
      'headers': headers,
      'timestamp': timestamp.toIso8601String(),
      'ttl': ttl.inMilliseconds,
    };
  }

  /// Reads a [NetworkResponse] from the map [toJson] produces.
  factory NetworkResponse.fromJson(Map<String, dynamic> json) {
    return NetworkResponse(
      method: json['method'],
      url: json['url'],
      queryParameters: json['query_parameters']?.cast<String, dynamic>(),
      requestData: json['request_data']?.cast<String, dynamic>(),
      statusCode: json['status_code'],
      data: json['data'],
      headers: (json['headers'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as List).cast<String>()),
      ),
      timestamp: DateTime.parse(json['timestamp']),
      ttl: Duration(milliseconds: json['ttl']),
    );
  }
}
