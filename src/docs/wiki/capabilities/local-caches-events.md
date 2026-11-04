---
capability: local-caches-events
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.cache_manager.CachePutEvent@1baf12f672
  - lupin-mobile:lib.core.cache.cache_manager.CacheHitEvent@79db901403
  - lupin-mobile:lib.core.cache.cache_manager.CacheMissEvent@8ab1be9e74
  - lupin-mobile:lib.core.cache.cache_manager.CacheRemoveEvent@3bdf2a09a9
  - lupin-mobile:lib.core.cache.cache_manager.CacheExpiredEvent@38a366c99b
  - lupin-mobile:lib.core.cache.cache_manager.CacheClearEvent@5b5f9685c1
  - lupin-mobile:lib.core.cache.cache_manager.CacheCleanupEvent@7bc925d52e
---
# Cache manager events

`CacheManager` publishes one event per operation on its broadcast `events` stream. Part of [[local-caches]]. The same idea is repeated in [[network-cache-events]] and [[audio-cache-events]].

## What it does
- Every event extends `CacheEvent` and carries a `timestamp` set when it is created.
- `get` emits `CacheMissEvent( key )` when neither memory nor storage holds the key. It emits `CacheExpiredEvent( key )` when the entry is older than `policy.maxAge`, and `CacheHitEvent( key )` otherwise.
- `put` emits `CachePutEvent( key, sizeBytes )` once the entry is stored. `remove` emits `CacheRemoveEvent( key )` and `clear` emits `CacheClearEvent`.
- `cleanup` removes each expired key through `remove`, then emits one `CacheCleanupEvent( itemsRemoved )`. It emits nothing when no key expired.
- `dispose` closes the stream.

## Don't
- Don't count `CacheRemoveEvent` as a caller's delete. Eviction, expiry on read and `cleanup` all go through `remove`, so each emits one too.
- Don't wait for a cleanup event after an empty sweep. None is sent.

## Invariants
- An expired read emits `CacheRemoveEvent` first and `CacheExpiredEvent` second.
- An eviction caused by `put` emits its `CacheRemoveEvent` before that `put`'s `CachePutEvent`.
- Nothing in `lib/` listens to `events`. The streams are for monitoring and tests.
