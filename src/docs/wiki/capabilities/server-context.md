---
capability: server-context
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.settings.presentation.server_context_toggle.serverContextColor@3d858e0289
  - lupin-mobile:lib.features.settings.presentation.server_context_toggle.ServerContextToggle@d7376c9937
  - lupin-mobile:lib.services.auth.server_context_service.ServerContextConfig@eb6d783346
  - lupin-mobile:lib.services.auth.server_context_service.ServerContextService@48a798a13a
---
# Server context

`ServerContextService` decides which Lupin server the app talks to. Contexts come from `assets/config/server-contexts.json`, so adding a server is a JSON edit. `ServerContextToggle` is the picker. See [[mobile-auth]], [[http-client]] and [[theme-and-shared-widgets]].

## What it does
- `ServerContextService.load( prefs )` reads the bundled JSON, picks the stored context or the file's declared default, and copies its URLs into `AppConstants.apiBaseUrl` and `wsBaseUrl`.
- A stored id that is no longer in the JSON falls back to the default. A missing default falls back to the first context.
- Each `ServerContextConfig` has an `id`, a `label`, a `baseUrl` and a `wsUrl`. `active`, `activeConfig`, `configFor( id )` and `all` read them.
- `setActive( id )` throws `ArgumentError` for an unknown id and does nothing for the active one. Otherwise it updates `AppConstants`, calls every listener, then saves the choice.
- Anything that captured a base URL at start-up registers with `addListener`. The shared `Dio` and any screen showing the active server do.
- `ServerContextToggle` asks for confirmation, then sends `AuthServerContextSwitchRequested` so `AuthBloc` signs out before the switch. `serverContextColor` is green for ids ending in `dev` and orange otherwise.

## Don't
- Don't call `setActive` without clearing the old context's session first. The service owns only the URL selection.
- Don't hide the toggle in release builds. A handset cannot reach the emulator alias the default points at, so the picker is its only way to another server before sign-in.
- Don't cache a base URL. Register a listener instead, or requests keep going to the old host.

## Invariants
- Listeners run synchronously, before the first await in `setActive`.
- The login screen is the toggle's only mount.
