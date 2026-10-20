---
capability: ws-connection
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.websocket.websocket_service.WebSocketService@7912da1f26
  - lupin-mobile:lib.services.websocket.ws_reconnect_coordinator.startReconnectServices@d2e5f409ea
  - lupin-mobile:lib.services.websocket.ws_reconnect_coordinator.WsReconnectTarget@62f2e15a59
  - lupin-mobile:lib.services.websocket.ws_reconnect_coordinator.WsReconnectCoordinator@83553baf72
  - lupin-mobile:lib.services.websocket.ws_resume_store.WsResumeStore@e121154c3f
  - lupin-mobile:lib.shared.models.session.SessionStatus@de2f0fe4c7
  - lupin-mobile:lib.shared.models.session.Session@caeb5b0fa6
---
# WebSocket connection

`WebSocketService` holds the one `/ws/queue` socket to the Lupin server, and `WsReconnectCoordinator` brings it back when it drops. `WsResumeStore` keeps the device id and the resume cursor so a reconnect replays only missed frames. See [[app-lifecycle]], [[offline-queue]] and [[app-bootstrap-and-di]].

## What it does
- `connect( userId )` fetches a session id over HTTP and opens the socket. It then sends `auth_request` with the device id, the last processed `seq` and `client_type: "mobile"`, which the push wake-up logic needs.
- Incoming frames arrive on `stream` as decoded JSON. A binary frame is wrapped as an audio chunk. A `sys_ping` is answered with a pong, and the service pings every 30 seconds.
- Every frame with a positive `seq` advances the cursor, which is saved and acknowledged only after the frame is handed on. `resume_complete.seq` ends a replay.
- `connectionStream` emits each change of connected state and replays the current value to a new listener. `_setConnected` is its only writer.
- After a drop the service retries up to 5 times, 5 seconds apart, then gives up. Close code 4004 means a newer socket took the device slot, and it stops reconnecting.
- `reconnectNow()` makes one guarded attempt and refuses when connected, connecting or signed out. The coordinator calls it on app resume, network restored (debounced 2 seconds), a push wake-up and a retry loop (30 seconds to 5 minutes, jittered).
- `startReconnectServices` initializes the lifecycle and connectivity services, pauses connectivity checks in the background, then starts the coordinator.

## Don't
- Don't reconnect on close code 4004. Two sockets of one install would bump each other in a loop.
- Don't start a second attempt while one runs. It would open a second channel for the same slot, and the server answers 4004.
- Don't use the `SharedPreferences` singleton for the device id or cursor. The push isolate and the UI isolate each cache their own copy, so `WsResumeStore` uses `SharedPreferencesAsync`.
- Don't rename `ws.device_id` or `ws.last_seq`. That resets every install.

## Invariants
- At most one channel is open, and a callback from a retired channel is ignored. `Session` and `SessionStatus` are unused models.
- The session id is exposed only after the socket is up, and its format is two lowercase words, such as "wise penguin".
