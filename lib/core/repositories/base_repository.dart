import 'dart:async';

/// Base repository interface defining common CRUD operations.
/// 
/// Provides standard data access patterns with type safety and consistent
/// error handling across all repository implementations.
abstract class BaseRepository<T, ID> {
  /// Creates a new entity in the repository.
  /// 
  /// Requires:
  ///   - entity must be a valid, non-null instance of type T
  ///   - entity must not already exist (enforced by implementation)
  /// 
  /// Ensures:
  ///   - Entity is persisted to storage
  ///   - Returns the created entity with any generated fields
  ///   - Entity can be retrieved using findById with the returned ID
  /// 
  /// Raises:
  ///   - ValidationException if entity data is invalid
  ///   - DuplicateEntityException if entity already exists
  ///   - RepositoryException if storage operation fails
  Future<T> create(T entity);
  
  /// Retrieves entity by its unique identifier.
  /// 
  /// Requires:
  ///   - id must be a valid, non-null identifier of type ID
  /// 
  /// Ensures:
  ///   - Returns entity if found, null if not found
  ///   - Returned entity is complete and valid
  ///   - No side effects on storage
  /// 
  /// Raises:
  ///   - ArgumentError if id is invalid
  ///   - RepositoryException if storage access fails
  Future<T?> findById(ID id);
  
  /// Retrieves all entities from the repository.
  /// 
  /// Requires:
  ///   - Repository must be accessible
  /// 
  /// Ensures:
  ///   - Returns list of all entities (may be empty)
  ///   - Entities are returned in consistent order
  ///   - No side effects on storage
  /// 
  /// Raises:
  ///   - RepositoryException if storage access fails
  Future<List<T>> findAll();
  
  /// Updates an existing entity in the repository.
  /// 
  /// Requires:
  ///   - entity must be a valid, non-null instance of type T
  ///   - entity must already exist in the repository
  /// 
  /// Ensures:
  ///   - Entity is updated in storage
  ///   - Returns the updated entity
  ///   - All changes are persisted
  /// 
  /// Raises:
  ///   - ValidationException if entity data is invalid
  ///   - EntityNotFoundException if entity does not exist
  ///   - RepositoryException if storage operation fails
  Future<T> update(T entity);
  
  /// Deletes entity by its unique identifier.
  /// 
  /// Requires:
  ///   - id must be a valid identifier of an existing entity
  /// 
  /// Ensures:
  ///   - Entity is permanently removed from storage
  ///   - Subsequent findById calls will return null
  ///   - Operation is idempotent (no error if already deleted)
  /// 
  /// Raises:
  ///   - ArgumentError if id is invalid
  ///   - RepositoryException if storage operation fails
  Future<void> deleteById(ID id);
  
  /// Deletes the specified entity from the repository.
  /// 
  /// Requires:
  ///   - entity must be a valid, non-null instance of type T
  ///   - entity must have a valid identifier
  /// 
  /// Ensures:
  ///   - Entity is permanently removed from storage
  ///   - Operation is idempotent (no error if already deleted)
  /// 
  /// Raises:
  ///   - ArgumentError if entity is invalid
  ///   - RepositoryException if storage operation fails
  Future<void> delete(T entity);
  
  /// Checks whether entity with given ID exists in the repository.
  /// 
  /// Requires:
  ///   - id must be a valid, non-null identifier of type ID
  /// 
  /// Ensures:
  ///   - Returns true if entity exists, false otherwise
  ///   - No side effects on storage
  ///   - Operation is fast and lightweight
  /// 
  /// Raises:
  ///   - ArgumentError if id is invalid
  ///   - RepositoryException if storage access fails
  Future<bool> exists(ID id);
  
  /// Returns the total count of entities in the repository.
  /// 
  /// Requires:
  ///   - Repository must be accessible
  /// 
  /// Ensures:
  ///   - Returns accurate count of all entities
  ///   - Count reflects current state of repository
  ///   - No side effects on storage
  /// 
  /// Raises:
  ///   - RepositoryException if storage access fails
  Future<int> count();
  
  /// Removes all entities from the repository.
  /// 
  /// Requires:
  ///   - Repository must be accessible
  ///   - User must have appropriate permissions
  /// 
  /// Ensures:
  ///   - All entities are permanently removed
  ///   - Repository is empty after operation
  ///   - Subsequent findAll will return empty list
  /// 
  /// Raises:
  ///   - PermissionException if user lacks clearance
  ///   - RepositoryException if storage operation fails
  Future<void> clear();
}

/// Repository interface for entities that support pagination.
/// 
/// Extends base repository with efficient pagination and search capabilities
/// for handling large datasets.
abstract class PaginatedRepository<T, ID> extends BaseRepository<T, ID> {
  /// Retrieves entities with pagination, sorting, and filtering.
  /// 
  /// Requires:
  ///   - page must be non-negative
  ///   - size must be positive and reasonable (< 1000)
  ///   - sortBy (if provided) must be a valid entity field
  ///   - filters must contain valid field names and values
  /// 
  /// Ensures:
  ///   - Returns paginated result with correct page metadata
  ///   - Results are sorted according to specified criteria
  ///   - Filters are applied before pagination
  ///   - Performance is optimized for large datasets
  /// 
  /// Raises:
  ///   - ArgumentError if pagination parameters are invalid
  ///   - ValidationException if sort or filter fields are invalid
  ///   - RepositoryException if storage query fails
  Future<PaginatedResult<T>> findPaginated({
    int page = 0,
    int size = 20,
    String? sortBy,
    bool ascending = true,
    Map<String, dynamic>? filters,
  });
  
  /// Searches entities with text query and pagination.
  /// 
  /// Requires:
  ///   - query must be non-empty and meaningful
  ///   - page must be non-negative
  ///   - size must be positive and reasonable
  ///   - searchFields (if provided) must be valid entity fields
  /// 
  /// Ensures:
  ///   - Returns entities matching the search query
  ///   - Search is performed across specified or default fields
  ///   - Results are paginated for performance
  ///   - Search is case-insensitive by default
  /// 
  /// Raises:
  ///   - ArgumentError if search parameters are invalid
  ///   - ValidationException if search fields are invalid
  ///   - RepositoryException if search operation fails
  Future<PaginatedResult<T>> search(
    String query, {
    int page = 0,
    int size = 20,
    List<String>? searchFields,
  });
}

/// Repository interface for entities that support caching.
/// 
/// Extends base repository with intelligent caching for improved performance
/// and reduced network/storage operations.
abstract class CachedRepository<T, ID> extends BaseRepository<T, ID> {
  /// Retrieves entity with cache-first strategy.
  /// 
  /// Requires:
  ///   - id must be a valid, non-null identifier
  ///   - maxAge (if provided) must be a positive duration
  /// 
  /// Ensures:
  ///   - Returns cached entity if available and fresh
  ///   - Falls back to storage if cache miss or stale
  ///   - Caches fetched entity for future requests
  ///   - Cache expiration is respected
  /// 
  /// Raises:
  ///   - ArgumentError if id is invalid
  ///   - RepositoryException if both cache and storage fail
  Future<T?> findByIdCached(ID id, {Duration? maxAge});
  
  /// Forces cache refresh for a specific entity.
  /// 
  /// Requires:
  ///   - id must be a valid identifier
  ///   - Entity should exist in storage
  /// 
  /// Ensures:
  ///   - Cache entry is removed if exists
  ///   - Fresh data is fetched from storage
  ///   - New data is cached for future requests
  /// 
  /// Raises:
  ///   - ArgumentError if id is invalid
  ///   - RepositoryException if storage access fails
  Future<void> refreshCache(ID id);
  
  /// Clears all cached entities.
  /// 
  /// Requires:
  ///   - Cache system must be accessible
  /// 
  /// Ensures:
  ///   - All cache entries are removed
  ///   - Memory is freed
  ///   - Subsequent requests will fetch from storage
  /// 
  /// Raises:
  ///   - CacheException if cache clearing fails
  Future<void> clearCache();
  
  /// Retrieves cache performance statistics.
  /// 
  /// Requires:
  ///   - Cache system must be accessible
  /// 
  /// Ensures:
  ///   - Returns current cache statistics
  ///   - Statistics include hit/miss rates and entry counts
  ///   - Data reflects real-time cache state
  /// 
  /// Raises:
  ///   - CacheException if statistics cannot be retrieved
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