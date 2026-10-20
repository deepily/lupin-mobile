---
capability: fcm-push-wake
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.push.fcm_bootstrap.FirebaseTokenSource@8e6e22ba3e
  - lupin-mobile:lib.services.push.fcm_bootstrap.initFcmIfEnabled@4fb470a99e
  - lupin-mobile:lib.services.push.fcm_bootstrap.onForegroundDataMessage@687beb65fa
  - lupin-mobile:lib.services.push.fcm_bootstrap.fcmOnAuthenticated@3504ab2cb9
  - lupin-mobile:lib.services.push.fcm_bootstrap.fcmOnLoggedOut@bfcd093214
  - lupin-mobile:lib.services.push.fcm_bootstrap.fcmBackgroundHandler@41efe59048
  - lupin-mobile:lib.services.push.fcm_bootstrap.showWakeNotification@83bcfe40e6
  - lupin-mobile:lib.services.push.fcm_bootstrap.buildBackgroundWakeChain@219ae2eae1
  - lupin-mobile:lib.services.push.fcm_wake_chain.FcmWakeOutcome@afc7e164e9
  - lupin-mobile:lib.services.push.fcm_wake_chain.FcmWakeCredentials@c7f184e4d3
  - lupin-mobile:lib.services.push.fcm_wake_chain.FcmWakeChain@e273b48b0f
  - lupin-mobile:lib.services.push.fcm_wakeup_service.FcmTokenSource@7aa038a480
  - lupin-mobile:lib.services.push.fcm_wakeup_service.FcmWakeupService@604f551343
  - lupin-mobile:lib.services.push.notification_tap_binding.notificationTapSink@f9ae974d73
  - lupin-mobile:lib.services.push.notification_tap_binding.bindNotificationTaps@4df53dedf9
  - lupin-mobile:lib.services.push.notification_tap_payload.NotificationTapPayload@a69b9ae08c
  - lupin-mobile:lib.services.push.notification_tap_router.NotificationTapRouter@a187c060de
---
# Push wake-up

A Firebase message wakes the app so it can show unplayed notifications while no WebSocket is open. `FcmWakeupService` registers the device token, `FcmWakeChain` does the background work, and `NotificationTapRouter` holds a tap until the app can route it. See [[notification-audio-playback]] and [[ws-connection]].

## What it does
- The code flag `kEnableFcm` defaults to off. The build scripts pass `ENABLE_FCM=true` unless given `--no-fcm`. `initFcmIfEnabled` does nothing when it is off.
- `FcmWakeupService` posts the token to `/api/fcm/register-token` on sign-in, on token rotation and on every WebSocket reconnect. `/api/fcm/unregister-token` runs on sign-out. Both are idempotent.
- The push payload carries no content. The wake chain exchanges the stored refresh token, fetches the unplayed list, shows a notification, speaks one item and marks it played.
- It shows at most 5 items per wake (`kFcmWakeDrainMax`). The whole handler has 27 seconds, and the show step has 20.
- Every path that would end without a visible notification posts a fallback ("New activity. Open Lupin to see it."), so FCM keeps the high priority.
- `NotificationTapPayload` rides in the notification and decodes totally. A bad payload returns null and the tap becomes a plain launch.
- `NotificationTapRouter` keeps one pending tap and dedupes by notification id and drops a tap with no `senderId`. `takePending` hands it over after `AuthAuthenticated`.

## Don't
- Don't use `/next` to fetch unplayed items. It returns only the oldest, so a muted low item at the head hides every urgent one behind it.
- Don't speak more than one utterance per wake. A rapid repeat crashes `flutter_tts`.
- Don't touch the WebSocket or the service locator in the chain. It runs in a fresh isolate with only injected callbacks.
- Don't read the access token in the background isolate. It is memory-only and does not exist there.
