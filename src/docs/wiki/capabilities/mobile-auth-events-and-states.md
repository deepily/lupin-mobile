---
capability: mobile-auth-events-and-states
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthStarted@f21dd42527
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthLoginRequested@6da033305b
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthLogoutRequested@aa20b864b1
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthBiometricUnlockRequested@b403930168
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthSessionValidationRequested@aeeab1ff74
  - lupin-mobile:lib.features.auth.domain.auth_event.AuthServerContextSwitchRequested@9489f8cb14
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthInitial@f4624c26c1
  - lupin-mobile:lib.features.auth.domain.auth_state.AuthLoading@27db633d1d
  - lupin-mobile:lib.shared.models.user.UserRole@80d134db7a
  - lupin-mobile:lib.shared.models.user.UserStatus@a144babf60
---
# Auth events and quiet states

The six inputs `AuthBloc` accepts, the two states that carry no data, and the role and status enums of `User`. Part of [[mobile-auth]].

## What it does
- `AuthGate` sends `AuthStarted` once, when it is created. `AuthLoginRequested( email, password )` comes from `LoginScreen`.
- `AuthBiometricUnlockRequested` comes from `BiometricPromptScreen`. `AuthLogoutRequested` comes from there too, and from `LupinHomeScreen` and `FocusModeScreen`. `AuthServerContextSwitchRequested( contextId )` comes from `ServerContextToggle`.
- `AuthSessionValidationRequested` re-checks the held access token with `/auth/me`. With no token it ends in `AuthUnauthenticated`, and a rejected token ends in `AuthError`.
- `AuthInitial` is the state the bloc starts in. `AuthLoading` is emitted at the start of the start-up, login and biometric handlers.
- `UserRole` is `user`, `admin` or `moderator`. `UserStatus` is `active`, `inactive`, `suspended` or `pending`.
- `User.fromJson` turns an unknown role into `user` and an unknown status into `active`.

## Don't
- Don't look for a sender of `AuthSessionValidationRequested`. Only the bloc's handler uses it, and no widget or service sends it.
- Don't read `UserRole` or `UserStatus` as the signed-in user's rights. `AuthBloc` works with `AuthUser`, and no code in `lib/` outside `user.dart` uses `User` or these enums.

## Invariants
- `AuthLoginRequested` and `AuthServerContextSwitchRequested` compare by their fields. The four data-free events compare equal to another event of the same type.
