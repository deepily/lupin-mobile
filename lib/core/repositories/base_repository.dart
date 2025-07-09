import 'dart:async';

/// Base repository interface defining common CRUD operations
abstract class BaseRepository<T, ID> {
  /// Create a new entity
  Future<T> create(T entity);
  
  /// Get entity by ID
  Future<T?> findById(ID id);
  
  /// Get all entities
  Future<List<T>> findAll();
  
  /// Update existing entity
  Future<T> update(T entity);
  
  /// Delete entity by ID
  Future<void> deleteById(ID id);
  
  /// Delete entity
  Future<void> delete(T entity);
  
  /// Check if entity exists
  Future<bool> exists(ID id);
  
  /// Count total entities
  Future<int> count();
  
  /// Clear all entities
  Future<void> clear();
}

/// Repository interface for entities that support pagination
abstract class PaginatedRepository<T, ID> extends BaseRepository<T, ID> {
  /// Get paginated results
  Future<PaginatedResult<T>> findPaginated({
    int page = 0,
    int size = 20,
    String? sortBy,
    bool ascending = true,
    Map<String, dynamic>? filters,
  });
  
  /// Search entities with pagination
  Future<PaginatedResult<T>> search(
    String query, {
    int page = 0,
    int size = 20,
    List<String>? searchFields,
  });
}

/// Repository interface for entities that support caching
abstract class CachedRepository<T, ID> extends BaseRepository<T, ID> {
  /// Get entity from cache first, then from remote
  Future<T?> findByIdCached(ID id, {Duration? maxAge});
  
  /// Refresh cache for specific entity
  Future<void> refreshCache(ID id);
  
  /// Clear cache
  Future<void> clearCache();
  
  /// Get cache stats
  Future<CacheStats> getCacheStats();
}

/// Repository interface for entities that support real-time updates
abstract class RealtimeRepository<T, ID> extends BaseRepository<T, ID> {
  /// Stream of all entities
  Stream<List<T>> watchAll();
  
  /// Stream of specific entity
  Stream<T?> watchById(ID id);
  
  /// Stream of entities matching criteria
  Stream<List<T>> watchWhere(Map<String, dynamic> criteria);
}

/// Result class for paginated queries
class PaginatedResult<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int size;
  final bool hasNext;
  final bool hasPrevious;

  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.size,
    required this.hasNext,
    required this.hasPrevious,
  });

  int get totalPages => (totalCount / size).ceil();
  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}

/// Cache statistics
class CacheStats {
  final int hitCount;
  final int missCount;
  final int entryCount;
  final int maxSize;
  final DateTime lastAccess;

  const CacheStats({
    required this.hitCount,
    required this.missCount,
    required this.entryCount,
    required this.maxSize,
    required this.lastAccess,
  });

  double get hitRate => 
      (hitCount + missCount) > 0 ? hitCount / (hitCount + missCount) : 0.0;
}