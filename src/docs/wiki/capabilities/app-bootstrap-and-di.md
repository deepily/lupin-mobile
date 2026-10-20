---
capability: app-bootstrap-and-di
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.app.onWsAuthenticated@edf8811245
  - lupin-mobile:lib.app.WsBlocDispatcher@a31c4dcae1
  - lupin-mobile:lib.app.LupinMobileApp@5beacad5a8
  - lupin-mobile:lib.core.app_initialization.AppInitialization@f25253c2a9
  - lupin-mobile:lib.core.build_info.BuildInfo@dc9837bc60
  - lupin-mobile:lib.core.di.service_locator.ServiceLocator@631f71a377
  - lupin-mobile:lib.core.di.service_locator.ServiceLocatorExtensions@bf57d05259
  - lupin-mobile:lib.main.main@deade07f48
---
# App bootstrap and dependency injection

`main` starts the app in a fixed order, `ServiceLocator` builds every service, repository and bloc, and `LupinMobileApp` wires the WebSocket to the blocs at sign-in. See [[mobile-auth]], [[ws-connection]] and [[fcm-push-wake]].

## What it does
- `main` calls `AppInitialization.initialize`, `startReconnectServices`, `initFcmIfEnabled` and `bindNotificationTaps`, then `runApp`.
- `initialize` runs logging, error handling, storage, dependency injection and the log context in that order. A second call only logs a warning.
- A failed `initialize` is logged as critical and rethrown. `main` then shows an "App Initialization Failed" screen, not the app.
- `ServiceLocator.init` registers core, services, repositories, use cases and blocs, in that order, and is a no-op once it has run.
- `WsBlocDispatcher.dispatch( type, data )` routes one frame to the blocs that handle it and ignores a type no case names.
- `onWsAuthenticated( userId, email )` connects the socket with the user id, only when it is not connected. Everything else, push registration included, gets the email.
- It asks for notification permission once, after push registration. A throwing `registerPush` is logged and the rest of the hook still runs.
- `BuildInfo.current` reads the build stamp from `--dart-define` values. An unstamped build reads as unstamped, never blank.

## Don't
- Don't register a pane bloc as a singleton. `buildFleetStatusBloc`, `buildTaskListBloc` and the other `build*` methods make a new one per call, and the route's `BlocProvider` closes it.
- Don't build `NotificationAudioService` without the tap router. The plugin is a singleton, so taps stop working after the first notification.
- Don't pass the account UUID where an email is wanted. The senders-visible request answers 404 for a UUID.

## Invariants
- Logging is initialized first, and `isInitialized` is true only after every step has finished.
- One frame causes one speech dispatch, and the `auth_success` frame re-hydrates the blocs after a reconnect.
- A broadcast acknowledgement rides the notification frame with its identity in `payload` and an empty `message`.
