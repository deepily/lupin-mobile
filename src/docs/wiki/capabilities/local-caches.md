---
capability: local-caches
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.audio_cache.AudioCache@c9b4717f38
  - lupin-mobile:lib.core.cache.audio_cache.AudioMetadata@6ded3c1a9c
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

`CacheManager<T>` is the one generic cache: a memory map backed by `StorageManager`, governed by a `CachePolicy`. `NetworkCache` and `AudioCache` are typed wrappers over it, and `StorageManager` is the key-value and file store under all of it. See [[offline-queue]] and [[http-client]]. The events all three caches emit are on [[local-caches-events]].

## What it does
- `CacheManager` needs a `cacheKey`, `toJson`, `fromJson` and a `StorageManager`. `get` reads memory first, then persistent storage, and returns null for a missing or expired entry.
- `put` stores in memory, persists when `persistAcrossRestarts` is true, then enforces `maxItems` and `maxSizeBytes`. It evicts by `CacheEvictionStrategy`: `lru`, `fifo`, `lfu`, `ttl` or `size`.
- A periodic timer runs `cleanup()` every `autoCleanupInterval` when `enableAutoCleanup` is on. The presets are `defaultPolicy`, `shortLived`, `longLived`, `audio` and `offlineFirst`.
- `OfflineManager.getCacheManager<T>` hands out one `CacheManager` per cache key and type. `NetworkCache` and `AudioCache` get theirs from it.
- `NetworkCache` stores a `NetworkResponse` per method and URL, and `invalidateUrl` and `invalidateMethod` drop entries. `AudioCache` stores audio chunks per text and provider, plus `AudioMetadata`.
- `getStats` on either wrapper returns a `CacheStats`. `NetworkCache` adds `method_stats` and `status_stats` to its `extras`, and `AudioCache` adds `total_metadata`, `provider_stats` and `metadata_hit_rate`. `toJson` merges `extras` after the standard keys.
- `StorageManager` wraps shared preferences with typed getters and setters, JSON helpers, `removeKeysWithPrefix` and `getStats`. It also appends to files under the documents folder for the log store.

## Don't
- Don't build a `CacheManager` directly. Go through `OfflineManager.getCacheManager`, or two managers will write the same persisted key.
- Don't add a second event family or stats class. `NetworkCache` and `AudioCache` emit `CacheEvent` and return `CacheStats`, with their own fields in `CacheEvent.details` and `CacheStats.extras`.
- Don't read `StorageManager` before `getInstance()` completes. It is an async singleton.

## Invariants
- The memory map is the source for limits. The item and size caps are checked on every `put`.
- `remove` is idempotent. A missing key raises nothing.
- `CachedHttpService` uses `NetworkCache`. `AudioCache` is registered by `ServiceLocator`, and no other file in `lib/` calls it.
