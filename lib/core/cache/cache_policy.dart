import 'package:equatable/equatable.dart';

/// Cache policy configuration
class CachePolicy extends Equatable {
  /// Maximum age of cached data before it's considered stale
  final Duration maxAge;
  
  /// Maximum number of items to keep in cache
  final int maxItems;
  
  /// Maximum total size in bytes
  final int maxSizeBytes;
  
  /// Whether to persist cache across app restarts
  final bool persistAcrossRestarts;
  
  /// Cache eviction strategy
  final CacheEvictionStrategy evictionStrategy;
  
  /// Whether to enable automatic cleanup
  final bool enableAutoCleanup;
  
  /// Interval for automatic cleanup
  final Duration autoCleanupInterval;

  const CachePolicy({
    this.maxAge = const Duration(days: 7),
    this.maxItems = 1000,
    this.maxSizeBytes = 50 * 1024 * 1024, // 50MB
    this.persistAcrossRestarts = true,
    this.evictionStrategy = CacheEvictionStrategy.lru,
    this.enableAutoCleanup = true,
    this.autoCleanupInterval = const Duration(hours: 24),
  });

  /// Default cache policy
  static const CachePolicy defaultPolicy = CachePolicy();
  
  /// Short-lived cache policy (for temporary data)
  static const CachePolicy shortLived = CachePolicy(
    maxAge: Duration(minutes: 30),
    maxItems: 100,
    persistAcrossRestarts: false,
  );
  
  /// Long-lived cache policy (for stable data)
  static const CachePolicy longLived = CachePolicy(
    maxAge: Duration(days: 30),
    maxItems: 5000,
    persistAcrossRestarts: true,
  );
  
  /// Audio-specific cache policy
  static const CachePolicy audio = CachePolicy(
    maxAge: Duration(days: 14),
    maxItems: 500,
    maxSizeBytes: 200 * 1024 * 1024, // 200MB
    persistAcrossRestarts: true,
  );
  
  /// Offline-first cache policy (never expire)
  static const CachePolicy offlineFirst = CachePolicy(
    maxAge: Duration(days: 365),
    maxItems: 10000,
    persistAcrossRestarts: true,
    enableAutoCleanup: false,
  );

  CachePolicy copyWith({
    Duration? maxAge,
    int? maxItems,
    int? maxSizeBytes,
    bool? persistAcrossRestarts,
    CacheEvictionStrategy? evictionStrategy,
    bool? enableAutoCleanup,
    Duration? autoCleanupInterval,
  }) {
    return CachePolicy(
      maxAge: maxAge ?? this.maxAge,
      maxItems: maxItems ?? this.maxItems,
      maxSizeBytes: maxSizeBytes ?? this.maxSizeBytes,
      persistAcrossRestarts: persistAcrossRestarts ?? this.persistAcrossRestarts,
      evictionStrategy: evictionStrategy ?? this.evictionStrategy,
      enableAutoCleanup: enableAutoCleanup ?? this.enableAutoCleanup,
      autoCleanupInterval: autoCleanupInterval ?? this.autoCleanupInterval,
    );
  }

  @override
  List<Object?> get props => [
    maxAge,
    maxItems,
    maxSizeBytes,
    persistAcrossRestarts,
    evictionStrategy,
    enableAutoCleanup,
    autoCleanupInterval,
  ];
}

/// Cache eviction strategies
enum CacheEvictionStrategy {
  /// Least Recently Used
  lru,
  
  /// First In First Out
  fifo,
  
  /// Least Frequently Used
  lfu,
  
  /// Time-based (oldest first)
  ttl,
  
  /// Size-based (largest first)
  size,
}

/// Cache entry metadata
class CacheEntry<T> extends Equatable {
  final String key;
  final T value;
  final DateTime createdAt;
  final DateTime? lastAccessedAt;
  final int accessCount;
  final int sizeBytes;
  final Map<String, dynamic>? metadata;

  const CacheEntry({
    required this.key,
    required this.value,
    required this.createdAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    this.sizeBytes = 0,
    this.metadata,
  });

  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(createdAt) > maxAge;
  }

  CacheEntry<T> withAccess() {
    return CacheEntry<T>(
      key: key,
      value: value,
      createdAt: createdAt,
      lastAccessedAt: DateTime.now(),
      accessCount: accessCount + 1,
      sizeBytes: sizeBytes,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) valueToJson) {
    return {
      'key': key,
      'value': valueToJson(value),
      'created_at': createdAt.toIso8601String(),
      'last_accessed_at': lastAccessedAt?.toIso8601String(),
      'access_count': accessCount,
      'size_bytes': sizeBytes,
      'metadata': metadata,
    };
  }

  factory CacheEntry.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) valueFromJson,
  ) {
    return CacheEntry<T>(
      key: json['key'],
      value: valueFromJson(json['value']),
      createdAt: DateTime.parse(json['created_at']),
      lastAccessedAt: json['last_accessed_at'] != null 
          ? DateTime.parse(json['last_accessed_at']) 
          : null,
      accessCount: json['access_count'] ?? 0,
      sizeBytes: json['size_bytes'] ?? 0,
      metadata: json['metadata'],
    );
  }

  @override
  List<Object?> get props => [
    key,
    value,
    createdAt,
    lastAccessedAt,
    accessCount,
    sizeBytes,
    metadata,
  ];
}