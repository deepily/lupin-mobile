---
capability: local-caches-events
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.cache_manager.CacheEvent@7045b1d729
  - lupin-mobile:lib.core.cache.cache_manager.CachePutEvent@fc3330de03
  - lupin-mobile:lib.core.cache.cache_manager.CacheHitEvent@fdda524845
  - lupin-mobile:lib.core.cache.cache_manager.CacheMissEvent@3dae656c6e
  - lupin-mobile:lib.core.cache.cache_manager.CacheRemoveEvent@924bf6e74d
  - lupin-mobile:lib.core.cache.cache_manager.CacheExpiredEvent@0d31064ac3
  - lupin-mobile:lib.core.cache.cache_manager.CacheClearEvent@75c55d73a5
  - lupin-mobile:lib.core.cache.cache_manager.CacheCleanupEvent@c17b42c8c2
  - lupin-mobile:lib.core.cache.cache_manager.CacheInvalidateEvent@c7e93fb6cc
---
# Cache events

One family serves both caches: every event extends `CacheEvent`, which carries a `timestamp` and a `details` map. `CacheManager` and `NetworkCache` each publish on their own broadcast `events` stream, typed `Stream<CacheEvent>`. Part of [[local-caches]].

## What it does
- `CacheManager.get` emits `CacheMissEvent( key )` when no copy exists, `CacheExpiredEvent( key )` past `policy.maxAge`, and `CacheHitEvent( key )` otherwise.
- `put` emits `CachePutEvent( key, sizeBytes: n )`, `remove` emits `CacheRemoveEvent( key )` and `clear` emits `CacheClearEvent`. `cleanup` emits one `CacheCleanupEvent( itemsRemoved )`, and nothing when no key expired.
- `NetworkCache` emits the same classes, keyed `"<METHOD> <url>"`, with `details` of `method`, `url` and, when known, `status_code`.
- Its store is a `CachePutEvent` with `sizeBytes` null. An entry past its own TTL gives `CacheExpiredEvent`, and `clearExpired` always emits `CacheCleanupEvent( removedCount )`. `invalidateUrl` and `invalidateMethod` each emit one `CacheInvalidateEvent( pattern )`.

## Don't
- Don't count `CacheRemoveEvent` as a caller's delete. Eviction, expiry on read and `cleanup` all go through `remove`, so each emits one too.
- Don't wait for a cleanup event after an empty `CacheManager` sweep. `NetworkCache.clearExpired` is the exception and always sends one.
- Don't read an invalidate event as a count or a kind. It carries only `pattern`, and fires even when nothing matched.
- Don't add another event class for `NetworkCache`'s own fields. Put them in `details`.

## Invariants
- An expired read on `CacheManager` emits `CacheRemoveEvent` first and `CacheExpiredEvent` second.
- An eviction caused by `put` emits its `CacheRemoveEvent` before that `put`'s `CachePutEvent`.
- `NetworkCache`'s stream carries the response level only. The inner `CacheManager` events never appear on it.
- Nothing in `lib/` listens to any `events` stream. They are for monitoring and tests.
