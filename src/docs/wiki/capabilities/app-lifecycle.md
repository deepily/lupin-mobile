---
capability: app-lifecycle
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.auth.presentation.ws_lifecycle_listener.WsLifecycleListener@456685887f
  - lupin-mobile:lib.services.lifecycle.app_lifecycle_service.AppLifecycleService@54e5a34fec
  - lupin-mobile:lib.services.lifecycle.app_lifecycle_service.AppUsageState@d479f5dafc
  - lupin-mobile:lib.services.lifecycle.app_lifecycle_service.AppStateConnectionStrategy@16d208cc09
---
# App lifecycle

`AppLifecycleService` watches whether the app is in the foreground or background and for how long, and turns that into an `AppUsageState`. `WsLifecycleListener` connects the WebSocket when the user signs in and disconnects it when they sign out. See [[ws-connection]], [[offline-queue]] and [[mobile-auth]].

## What it does
- `AppLifecycleService` is a singleton and a `WidgetsBindingObserver`. `initialize()` registers it, and `ws_reconnect_coordinator.dart` calls that at start.
- `lifecycleStream` emits each framework `AppLifecycleState`. `usageStateStream` emits each change of `AppUsageState`: `active`, `inactive`, `background`, `backgroundLong`, `recovering` or `shutdown`.
- Thresholds: 2 minutes without interaction makes the app inactive, 5 minutes in the background is a short stay, and 30 minutes is a long one.
- Resuming after more than 5 minutes triggers short-background recovery, and after more than 30 minutes a full recovery.
- A pause or detach starts a log flush, bounded by `logFlushTimeout` (3 seconds), because a background kill gives no later chance to write buffered entries.
- Each `AppUsageState` maps to an `AppStateConnectionStrategy`: whether to keep the connection open, send pings, buffer audio, and how many connections are allowed.
- The reconnect coordinator pauses `NetworkConnectivityService` monitoring in the background. Pane blocs and `BroadcastBloc` read `lifecycleStream` to stop polling.
- `WsLifecycleListener` listens to `AuthBloc` and acts only when the state type changes. A token refresh while authenticated does not reconnect.
- On sign-in it calls `onAuthenticated( userId, email )`. On `AuthUnauthenticated` or `AuthError` it calls `onSignedOut`.

## Don't
- Don't create a second observer. Use `AppLifecycleService()`, the one shared instance.
- Don't pass the user id where the email is wanted. Email-keyed routes fail or mis-key on an id.

## Invariants
- `recordUserInteraction()` is what keeps the state `active`. No file outside the service calls it today.
- A state change to the same type never reaches `WsLifecycleListener`'s callbacks.
