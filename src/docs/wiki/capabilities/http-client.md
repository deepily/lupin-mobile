---
capability: http-client
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.auth.auth_interceptor.AuthInterceptor@b447bb8eb5
  - lupin-mobile:lib.services.network.cached_http_service.CachedHttpService@4d3b4f837e
  - lupin-mobile:lib.services.network.http_service.requestLogContext@ca7e6c6d9d
  - lupin-mobile:lib.services.network.http_service.HttpService@0f6fe7a6e2
---
# HTTP client

One shared `Dio` carries every call to the Lupin FastAPI server. `AuthInterceptor` adds the bearer token and refreshes it on a 401, `HttpService` sets timeouts and debug logging, and `CachedHttpService` adds response caching and offline queueing. See [[mobile-auth]], [[local-caches]] and [[offline-queue]].

## What it does
- `ServiceLocator.registerSharedDio` creates the single `Dio` and keeps its base URL in step with the server context. Repositories take that `Dio` directly. `HttpService` and `CachedHttpService` wrap it.
- `HttpService` sets a 10 second connect timeout and 30 second receive and send timeouts. It wraps session id, text-to-speech and health calls.
- It marks the `Dio` as configured, so a second service on the same `Dio` does not add the logging interceptors twice.
- `AuthInterceptor.onRequest` adds `Authorization: Bearer <token>` unless the header exists or the path is `/auth/login`, `/auth/refresh` or `/api/get-session-id`.
- On a 401 the interceptor reads the stored refresh token, refreshes once, updates the access token and replays the request. A multipart body is cloned for the replay.
- If another writer rotated the refresh token first, it retries once with the new stored token. Any other failure calls `onRefreshFailed`, which signs the user out.
- `CachedHttpService.get` returns a fresh cached response if there is one, then goes to the network and caches the result. On a network error it falls back to a stale cached copy.
- Offline with no cached copy, `get` queues the request through `OfflineManager`. `processQueuedRequests` replays GET and POST entries.
- `requestLogContext( path )` gives log metadata with the path and no query string.

## Don't
- Don't log a query string. It can carry a token. Use `requestLogContext`.
- Don't replay a multipart request without cloning the `FormData`. The first attempt consumes it.
- Don't refresh on an `/auth/login` or `/auth/refresh` 401, on a request already retried, or while a refresh is running. The interceptor skips all three.
- Don't use `uploadAndTranscribe` for voice replies. It is deprecated, and `AsrService` posts to the synchronous endpoint. See [[asr-dictation]].

## Invariants
- One refresh runs at a time, and one request is retried at most once.
- The interceptor imports no bloc and no credential store. Token read and rotation are callbacks.
