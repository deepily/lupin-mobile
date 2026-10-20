---
capability: mobile-auth
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.auth.domain.auth_bloc.AuthBloc@c314acc263
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthEvent@eea7c6f5c7
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthState@4a1eedb089
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthBiometricRequired@ce20988a78
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthAuthenticated@06fb78bbd4
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthUnauthenticated@f34ccec8c7
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthError@6dc9c05cf2
  - lupin-mobile:lib.features.auth.presentation.auth_gate.AuthGate@8554f84720
  - lupin-mobile:lib.features.auth.presentation.login_screen.LoginScreen@4dd7b06120
  - lupin-mobile:lib.services.auth.auth_repository.AuthTokens@f6bf68fafa
  - lupin-mobile:lib.services.auth.auth_repository.AuthUser@ce21825053
  - lupin-mobile:lib.services.auth.auth_repository.AuthException@ae767b5f91
  - lupin-mobile:lib.services.auth.auth_repository.AuthRepository@e0de6ac91c
  - lupin-mobile:lib.services.auth.auth_token_provider.setAccessToken@779b5d3bb3
  - lupin-mobile:lib.services.auth.auth_token_provider.clearAccessToken@d9768429a6
  - lupin-mobile:lib.services.auth.session_persistence.SessionPersistence@70f73f9afa
  - lupin-mobile:lib.shared.models.user.User@ca46c0fa11
---
# Mobile auth

`AuthBloc` runs login, logout, biometric unlock, session checks and server switching over `AuthRepository`. `AuthGate` shows the login screen, the biometric prompt or the app from the bloc's state. See [[biometric-and-credential-store]], [[server-context]] and [[http-client]].

## What it does
- `AuthRepository` is the only client of `/auth/login`, `/auth/refresh`, `/auth/logout` and `/auth/me`. It returns `AuthTokens` and `AuthUser`, and throws `AuthException` with the HTTP status.
- The access token lives in memory. `setAccessToken`, `clearAccessToken` and `readAccessToken` are top-level functions, so transport code needs no import of the auth feature.
- The refresh token, last email and WebSocket session id are kept per server context. `SessionPersistence` fronts the session id.
- `AuthStarted` picks the first state. A stored refresh token plus a biometric gives `AuthBiometricRequired`. Anything else gives `AuthUnauthenticated`.
- Login stores both tokens and the email, calls `/auth/me`, and emits `AuthAuthenticated( userId, email, accessToken )`.
- Logout runs the `onBeforeSignOut` hook first, then the server logout with the refresh token, then clears local state. Neither failure stops the sign-out.
- `AuthServerContextSwitchRequested` signs out of the old server, clears its session, switches, and ends in `AuthUnauthenticated`.

## Don't
- Don't send a logout call without the refresh token. The server answers 422, so none is sent.
- Don't split a server switch into a logout event and a switch event. Handlers for different events run concurrently, and a logout could clear the new server's session.
- Don't rebuild `LoginScreen` on `AuthLoading`. That drops the typed password after a failed sign-in.
- Don't leave pushed routes above `AuthGate` on sign-out. The gate pops to the first route.
