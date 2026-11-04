---
capability: network-cache-events
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheEvent@3153e11187
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheStoreEvent@0d23f8b487
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheHitEvent@9deced0763
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheMissEvent@dacfd86584
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheExpiredEvent@2f61615e18
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheInvalidateEvent@2fc39d8fb1
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheCleanupEvent@563f53530a
  - lupin-mobile:lib.core.cache.network_cache.NetworkCacheClearEvent@e10465416e
---
# Network cache events

`NetworkCache` publishes its own event family on a broadcast `events` stream, apart from the `CacheManager` one underneath it. Part of [[local-caches]]. Compare [[local-caches-events]].

## What it does
- Every event extends `NetworkCacheEvent` and carries a `timestamp` set when it is created.
- `cacheResponse` emits `NetworkCacheStoreEvent( method, url, statusCode )`. A missing status code is reported as 0.
- `getCachedResponse` emits `NetworkCacheHitEvent( method, url, statusCode )` for a live entry and `NetworkCacheMissEvent( method, url )` when none exists.
- An entry whose `isExpired` is true is removed and reported as `NetworkCacheExpiredEvent( method, url )`. The call returns null.
- `invalidateUrl` and `invalidateMethod` each emit one `NetworkCacheInvalidateEvent( pattern )`, with the URL fragment or the method name as the pattern.
- `clearExpired` emits `NetworkCacheCleanupEvent( removedCount )`, also when the count is 0. `clearAll` emits `NetworkCacheClearEvent`.

## Don't
- Don't tell an invalidate by URL from one by method with the event. Both carry only a string in `pattern`.
- Don't read an invalidate event as a count. `invalidateUrl` emits one event however many responses it removed, and one when none matched.

## Invariants
- Events describe the response layer only. The inner `CacheManager` sends its own events, which this stream never carries.
- Nothing in `lib/` listens to `events`.
