---
capability: fcm-wake-background-helpers
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.push.fcm_bootstrap.readWakeCredentials@75a64f9e84
  - lupin-mobile:lib.services.push.fcm_bootstrap.exchangeRefreshAndPersist@149ac00818
  - lupin-mobile:lib.services.push.fcm_bootstrap.userIdFromAccessToken@5c3a83846a
  - lupin-mobile:lib.services.push.fcm_bootstrap.fetchUnplayedForAccessToken@660557d190
  - lupin-mobile:lib.services.push.fcm_bootstrap.backgroundAllowedPriorities@606f47cfaa
  - lupin-mobile:lib.services.push.fcm_bootstrap.wakeNotificationDetails@102e61c5f7
  - lupin-mobile:lib.services.push.fcm_bootstrap.wakeNotificationId@a8d417e5e1
  - lupin-mobile:lib.services.push.fcm_bootstrap.deleteLegacyWakeChannel@5f1ba2c825
---
# Wake background helpers

The small functions in `fcm_bootstrap.dart` that `buildBackgroundWakeChain` hands to `FcmWakeChain`. Part of [[fcm-push-wake]]. All are `visibleForTesting`.

## What it does
- `readWakeCredentials` returns null when no refresh token is stored for the context. The email is optional and becomes an empty string.
- `exchangeRefreshAndPersist` refreshes through `AuthRepository`, writes the rotated refresh token, and returns the new access token. A 401 is retried once, and only when the stored token changed since it was read.
- The write is tried `kFcmRefreshWriteAttempts` times. If all fail it logs `kFcmRefreshWriteLostMarker` and the wake goes on.
- `userIdFromAccessToken` reads the `sub` claim of the JWT without verifying it. It throws `FormatException` for a malformed token or one with no `sub`.
- `backgroundAllowedPriorities` lists the priorities switched on for the `background` surface. `fetchUnplayedForAccessToken` sends them as the server-side `priorities` filter, with `sort=oldest` and `kFcmWakeUnplayedLimit`.
- `wakeNotificationDetails` posts on `kFcmWakeChannelId` at default importance. `deleteLegacyWakeChannel` removes `kFcmWakeChannelIdLegacy` and never throws.
- `wakeNotificationId` is a 31-bit FNV-1a hash of the item id in the tap payload. A payload with no item id gets the per-second id.

## Don't
- Don't fetch with an empty priority list. `fetchUnplayedForAccessToken` returns nothing without asking, so "none allowed" is never sent as "no filter".
- Don't address the fetch by email. The path takes the user id from the access token.
- Don't lower the channel importance in place. Android keeps a channel's importance, so a new channel id is needed.
