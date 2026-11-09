---
capability: local-caches
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.cache_manager.CacheManager@2aca9ec14d
  - lupin-mobile:lib.core.cache.cache_manager.CacheStats@0f232b67f8
  - lupin-mobile:lib.core.cache.cache_manager.CacheEvent@7045b1d729
  - lupin-mobile:lib.core.cache.cache_policy.CachePolicy@58c855b02b
  - lupin-mobile:lib.core.cache.cache_policy.CacheEvictionStrategy@e52bbfdbc9
  - lupin-mobile:lib.core.cache.cache_policy.CacheEntry@822692f56a
  - lupin-mobile:lib.core.cache.network_cache.NetworkCache@b6aa8876ad
  - lupin-mobile:lib.core.cache.network_cache.NetworkResponse@367a734a1c
  - lupin-mobile:lib.core.storage.storage_manager.StorageManager@5a7241a31f
  - lupin-mobile:lib.core.storage.storage_manager.StorageStats@fb5fbb2244
---
# Local caches

`CacheManager<T>` is the one generic cache: a memory map backed by `StorageManager`, governed by a `CachePolicy`. `NetworkCache` is a typed wrapper over it, and `StorageManager` is the key-value and file store under all of it. See [[offline-queue]] and [[http-client]]. The events both caches emit are on [[local-caches-events]].

## What it does
- `CacheManager` needs a `cacheKey`, `toJson`, `fromJson` and a `StorageManager`. `get` reads memory first, then persistent storage, and returns null for a missing or expired entry.
- `put` stores in memory, persists when `persistAcrossRestarts` is true, then enforces `maxItems` and `maxSizeBytes`. It evicts by `CacheEvictionStrategy`: `lru`, `fifo`, `lfu`, `ttl` or `size`.
- A periodic timer runs `cleanup()` every `autoCleanupInterval` when `enableAutoCleanup` is on. The presets are `defaultPolicy`, `shortLived`, `longLived`, `audio` and `offlineFirst`.
- `OfflineManager.getCacheManager<T>` hands out one `CacheManager` per cache key and type. `NetworkCache` gets its own from it.
- `NetworkCache` stores a `NetworkResponse` per method and URL, and `invalidateUrl` and `invalidateMethod` drop entries.
- `NetworkCache.getStats` returns a `CacheStats` with `method_stats` and `status_stats` in its `extras`. `toJson` merges `extras` after the standard keys.
- `StorageManager` wraps shared preferences with typed getters and setters, JSON helpers, `removeKeysWithPrefix` and `getStats`. It also appends to files under the documents folder for the log store.

## Don't
- Don't build a `CacheManager` directly. Go through `OfflineManager.getCacheManager`, or two managers will write the same persisted key.
- Don't add a second event family or stats class. `NetworkCache` emits `CacheEvent` and returns `CacheStats`, with its own fields in `CacheEvent.details` and `CacheStats.extras`.
- Don't read `StorageManager` before `getInstance()` completes. It is an async singleton.

## Invariants
- The memory map is the source for limits. The item and size caps are checked on every `put`.
- `remove` is idempotent. A missing key raises nothing.
- `CachedHttpService` uses `NetworkCache`, and `ServiceLocator` registers it.
