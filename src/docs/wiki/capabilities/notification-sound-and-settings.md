---
capability: notification-sound-and-settings
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.notification_audio.notification_audio_service.InAppDingPlayer@008cbd6055
  - lupin-mobile:lib.services.notification_audio.notification_audio_service.appIsInForeground@52ff30b430
  - lupin-mobile:lib.features.settings.presentation.notification_audio_settings_screen.NotificationAudioSettingsScreen@ed036741ed
  - lupin-mobile:lib.features.settings.presentation.notification_management_screen.NotificationManagementScreen@31b0bd6d92
  - lupin-mobile:lib.features.settings.presentation.notification_management_screen.MutableSender@5a82460364
  - lupin-mobile:lib.features.settings.presentation.notification_management_screen.formatMinutes@e8c5546a37
---
# Notification sound and settings

Two settings screens and the in-app ding. The management screen owns whether a notification is raised; the sound screen owns how a raised one sounds. The policy and service behind them are in [[notification-audio-playback]].

## What it does
- `NotificationManagementScreen` has three levels: a master switch, one switch per surface, and one checkbox per priority under each. The surfaces are app closed (the FCM wake path) and app open.
- Off means silence, never deletion. A suppressed notification stays in every list and is not marked played, so it waits for the next open.
- It also holds the muted senders, the quiet-hours start and end, and the optional push pause section. `formatMinutes` shows quiet hours as 24-hour `HH:MM`, so `1320` reads `22:00`.
- `MutableSender.fromRoster` collapses the server's sender roster to one row per mute key. It uses the same key and label functions as the notification shade.
- `NotificationAudioSettingsScreen` holds the sound switches. Medium dings, high dings and speaks, urgent has its own ding and speaks, and master mute overrides all.
- `InAppDingPlayer` plays a priority's ding inside the app, with no system notification, and cuts off one still playing. `appIsInForeground` is true when the app is resumed, or inactive under the shade or a system dialog.

## Don't
- Don't wait on the disk before redrawing. Both screens rebuild at once and write in parallel.
- Don't show a route to the stop-list screen when no stop list is registered. A null dependency hides the row.

## Invariants
- A suppressed notification is never hidden from a list and never marked played.
