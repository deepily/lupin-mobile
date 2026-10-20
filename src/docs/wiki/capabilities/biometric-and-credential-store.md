---
capability: biometric-and-credential-store
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.auth.presentation.biometric_prompt_screen.BiometricPromptScreen@2b55479722
  - lupin-mobile:lib.services.auth.biometric_gate.BiometricOutcome@85a275b55e
  - lupin-mobile:lib.services.auth.biometric_gate.BiometricGate@d070ab0f0c
  - lupin-mobile:lib.services.auth.secure_credential_store.SecureCredentialStore@fb8818b446
---
# Biometric unlock and credential store

`BiometricGate` wraps the device biometric check. `SecureCredentialStore` keeps the refresh token, the last email and the WebSocket session id in encrypted storage, one set per server context. `AuthBloc` drives both. See [[mobile-auth]] and [[server-context]].

## What it does
- `BiometricGate.isAvailable()` is true only when the device supports biometrics and can check them. Any error gives false.
- `authenticate( reason )` returns a `BiometricOutcome`: `authenticated`, `cancelled`, `unavailable` when none is enrolled, or `failed` on an error. It asks for a biometric only, with sticky authentication.
- `SecureCredentialStore` uses `flutter_secure_storage` with encrypted shared preferences on Android. A key is `auth.<contextId>.refresh_token`, `auth.<contextId>.last_email` or `auth.<contextId>.session.<email>`.
- The email in a session key is lowercased, so two spellings of one address share a session id.
- `clearContextSession( contextId )` deletes the refresh token and every session id for that context and keeps the last email, which pre-fills the next login.
- `BiometricPromptScreen` is what `AuthGate` shows for `AuthBiometricRequired`. A failed or declined check leads to the password login.

## Don't
- Don't keep a token in shared preferences. Only the server context choice lives there, because URLs are not secret.
- Don't surface `unavailable` as an error. The caller falls back to the password login.
- Don't clear a context's session by deleting keys one at a time. `clearContextSession` snapshots the keys first, because a platform can hand back a live map.
- Don't pass one context's id for another. The same store serves every context, and the id is the only separation.

## Invariants
- One store instance serves the app. Callers pass the context id on every call.
- A stored refresh token with no biometric available means a password login, not an automatic unlock.
