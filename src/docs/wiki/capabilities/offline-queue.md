---
capability: offline-queue
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.cache.offline_manager.OfflineManager@1cfb96d19f
  - lupin-mobile:lib.core.cache.offline_manager.QueuedRequest@ba0c50b03f
  - lupin-mobile:lib.core.cache.offline_manager.OfflineStats@4cc884f65d
  - lupin-mobile:lib.core.cache.offline_manager.OfflineEvent@26c227dbb0
  - lupin-mobile:lib.core.cache.offline_manager.OfflineStatusEvent@c86112434e
  - lupin-mobile:lib.core.cache.offline_manager.OfflineCacheEvent@a564e4f673
  - lupin-mobile:lib.core.cache.offline_manager.OfflineQueueEvent@6ed4dc6375
  - lupin-mobile:lib.core.cache.offline_manager.OfflineRequestProcessedEvent@f9065a521c
  - lupin-mobile:lib.core.cache.offline_manager.OfflineClearEvent@46e772ef37
  - lupin-mobile:lib.services.network.network_connectivity_service.NetworkConnectivityService@1fb67baa23
  - lupin-mobile:lib.services.network.network_connectivity_service.NetworkState@d017df0aae
  - lupin-mobile:lib.services.network.network_connectivity_service.shouldRetryOnNetworkEdge@3be321f976
  - lupin-mobile:lib.services.network.network_connectivity_service.ConnectionQuality@45f3ada920
  - lupin-mobile:lib.services.network.network_connectivity_service.WebSocketConnectionStrategy@032b4c36a4
---
# Offline queue and connectivity

`OfflineManager` keeps the device's online flag and a persisted queue of requests made while offline. `NetworkConnectivityService` decides what "online" means by asking the Lupin server. See [[local-caches]], [[http-client]] and [[ws-connection]].

## What it does
- `OfflineManager` follows the platform connectivity stream. On a change to online it calls `processQueuedRequests`.
- `queueRequest( key, data )` and `removeFromQueue` keep the queue in storage under `offline_queue` and emit an `OfflineQueueEvent`.
- Its own `processQueuedRequests` sends nothing. It emits `OfflineRequestProcessedEvent` and removes each entry. `CachedHttpService.processQueuedRequests` is the one that replays GET and POST requests.
- `NetworkConnectivityService` is a singleton. A network interface counts as `connected` only when `GET /health` answers 200 within 5 seconds, otherwise `limited`.
- It tests latency every 2 minutes and checks connectivity every 30 seconds. `pauseMonitoring` stops both timers while the app is in the background.
- `getConnectionStrategy` maps a `ConnectionQuality` to a `WebSocketConnectionStrategy`: reconnect delay 1 second when excellent, up to 30 seconds when offline or unknown.
- `shouldRetryOnNetworkEdge( previous, next )` is the one rule the task panes use to refetch and retry unsent writes.

## Don't
- Don't treat `OfflineManager.processQueuedRequests` as a sender. A caller must replay the request itself.
- Don't use the app's authenticated client for the health check. It uses a plain client so a sign-in problem cannot read as no network.

## Invariants
- A `connected` to `limited` edge never retries, because the server just stopped answering. A repeat of one state never acts.
- The base URL for `/health` is read on every call, so a server switch takes effect on the next check.
- The queue survives a restart, because it is loaded from storage at start.
