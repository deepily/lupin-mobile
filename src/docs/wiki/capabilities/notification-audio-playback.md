---
capability: notification-audio-playback
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.notification_audio.notification_audio_service.NotificationAudioService@0d3fa81e0a
  - lupin-mobile:lib.services.notification_audio.notification_delivery_policy.NotificationSurface@1cecbeea7b
  - lupin-mobile:lib.services.notification_audio.notification_delivery_policy.NotificationDeliveryPolicy@ba9c0b1ccf
  - lupin-mobile:lib.services.notification_audio.notification_preferences.NotificationPreferences@b7be8ae7be
  - lupin-mobile:lib.services.push.notification_sender_label.notificationSenderLabel@d407325b9c
  - lupin-mobile:lib.services.push.notification_sender_label.projectOfSenderId@7a40914723
  - lupin-mobile:lib.services.push.notification_sender_label.notificationSenderKey@c4e2fa204f
  - lupin-mobile:lib.services.push.notification_sender_label.foldSenderName@7968be0cb8
  - lupin-mobile:lib.services.push.unplayed_queue_order.oldestFirst@f968460da2
---
# Notification audio and delivery policy

`NotificationDeliveryPolicy` decides whether a notification may be raised at all. `NotificationAudioService` plays the ding and owns the `flutter_tts` fallback engine. `NotificationPreferences` holds the user's switches. Speech itself is in [[tts-streaming]], and the wake path is in [[fcm-push-wake]].

## What it does
- `allows( surface, priority, senderKey, now )` returns true only when the master switch, the surface switch and that priority's checkbox are all on. A surface is `background` (the FCM wake chain) or `foreground` (the WebSocket path).
- It then denies a muted sender and quiet hours. Urgent items skip those two denials only when their bypass switches are on. An unknown priority is denied.
- `anyAllowedOn( surface )` is the cheap pre-flight the wake chain runs before it spends radio and battery.
- The policy only silences. It never hides a list item and never marks anything played.
- `NotificationAudioService.handleIncoming` plays one sound per tier on the Android channels `lupin_medium`, `lupin_high` and `lupin_urgent`. `low` and the master mute do nothing, and `suppress_ding` silences the ding only.
- `flutterTtsSpeak` speaks with `flutter_tts` when ElevenLabs is unavailable. It waits for completion, bounded by 30 seconds plus 8 characters a second of text.
- Preference defaults: `low` is silent, `medium` dings, and `high` and `urgent` ding and speak. The focus surface speaks every message anyway, through `TtsOrchestrator`.
- `oldestFirst` sorts the fetched unplayed list by parsed instant, because the server's order and its docstring disagree. `notificationSenderLabel` builds the title, and `notificationSenderKey` the mute key.

## Don't
- Don't build the service without the tap callback. `initialize()` assigns the plugin's handler, so a service built without the callback installs null. Taps then stop after the first ding.
- Don't compare timestamps as strings. Offsets differ across restarts and DST, so `oldestFirst` compares instants.
- Don't add a priority tier without a checkbox. Consent for it does not exist yet, so the policy denies it.

## Invariants
- The policy imports no Flutter code and no locator, because the background isolate has neither.
