---
capability: audio-cache-events
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.audio_cache.AudioCacheEvent@c68b185bdd
  - lupin-mobile:lib.core.cache.audio_cache.AudioCacheStoreEvent@6d4d62d0e4
  - lupin-mobile:lib.core.cache.audio_cache.AudioCacheHitEvent@5fbf3f0b28
  - lupin-mobile:lib.core.cache.audio_cache.AudioCacheMissEvent@2382701e1c
  - lupin-mobile:lib.core.cache.audio_cache.AudioPrecacheRequestEvent@0430a5ca88
  - lupin-mobile:lib.core.cache.audio_cache.AudioCacheClearEvent@4c4e312837
  - lupin-mobile:lib.core.cache.audio_cache.AudioCacheOptimizeEvent@c0a09f3ca0
---
# Audio cache events

`AudioCache` publishes its own event family on a broadcast `events` stream, one event per cached utterance operation. Part of [[local-caches]]. Compare [[local-caches-events]] and [[network-cache-events]].

## What it does
- Every event extends `AudioCacheEvent` and carries a `timestamp` set when it is created.
- `cacheAudioForText` emits `AudioCacheStoreEvent( text, provider, chunkCount )`.
- A lookup emits `AudioCacheHitEvent( text, provider, chunkCount )` when the metadata and every chunk are found. It emits `AudioCacheMissEvent( text, provider )` when the metadata is missing, or when any chunk is.
- `precacheCommonPhrases` looks each phrase up, so a missing one emits a miss and then `AudioPrecacheRequestEvent( text, provider )`.
- `clearProviderCache` emits `AudioCacheClearEvent( provider, removedCount )`. `optimize` emits `AudioCacheOptimizeEvent` after it cleans up both inner caches.

## Don't
- Don't expect a precache request to generate audio. The event only says the phrase was absent, and `precacheCommonPhrases` does nothing more.
- Don't read the count on `clearAll`. It emits `AudioCacheClearEvent( "all", 0 )` whatever was removed.

## Invariants
- Events cover the utterance level only. The inner chunk and metadata caches send their own `CacheManager` events, which this stream never carries.
- Nothing in `lib/` listens to `events`.
