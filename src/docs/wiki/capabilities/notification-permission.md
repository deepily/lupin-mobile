---
capability: notification-permission
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.permissions.notification_permission.requestNotificationPermission@b09832f68a
---
# Notification permission

`requestNotificationPermission` asks Android for the right to post notifications and returns whether it was granted. It is the only place in the app that makes that request. The file also holds the `NotificationPermissionRequester` typedef (a test seam) and `kNotificationPermissionDeniedMarker`, a log line; neither is in the symbol index.

## What it does
- It calls `Permission.notification.request()` from `permission_handler` and returns `status.isGranted`.
- Below Android 13 the permission is implicit, so it returns true with no prompt.
- On Android 13 and later a fresh install starts denied. The manifest's `POST_NOTIFICATIONS` entry declares the permission but does not grant it.
- A single earlier denial is not permanent, so a later login may prompt again. Once permanently denied, `request()` returns the existing status with no prompt.
- `onWsAuthenticated` in `lib/app.dart` is the only caller. It runs the request on every login, after push registration, and reaches it through the `requestNotifications` parameter, which defaults to `requestNotificationPermission`.

## Don't
- Don't discard the result. A denial leaves the wake chain running end to end: it still logs `[FcmWake] shown` while the notification shade stays empty. That looks like a server fault or an APK built without push (see [[fcm-push-wake]]).
- Don't move the denied-log line inside `requestNotificationPermission`. It sits in `onWsAuthenticated`, behind the injectable seam, so a test can check it.
- Don't add a second request site. The prompt must run after push registration even if registration throws, so `onWsAuthenticated` wraps registration in a try block and carries on.

## Invariants
- When the result is false, `onWsAuthenticated` logs `kNotificationPermissionDeniedMarker` (`[Notifications] PERMISSION DENIED`) through its `logSink`, else `debugPrint`. Nothing else on the device reports a denial, so search for that text when pushes do not arrive.
- The function returns true if and only if notifications may be posted afterwards.

## When not to use it
- Microphone permission is a separate request; see [[asr-dictation]].
- Spoken-notification rules live in [[notification-audio-playback]] and the stop-list in [[notification-filtering]]. This page covers only the operating system gate.
