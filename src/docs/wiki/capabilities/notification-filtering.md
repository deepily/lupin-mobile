---
capability: notification-filtering
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.notifications.presentation.mute_sender_action.senderItemFor@e0bd039c06
  - lupin-mobile:lib.features.notifications.presentation.mute_sender_action.showMuteSenderMenu@fe6184cae5
  - lupin-mobile:lib.features.settings.presentation.notification_filter_settings_screen.NotificationFilterSettingsScreen@90850abb82
  - lupin-mobile:lib.services.notification_filter.notification_stop_list.StopPattern@1de1315e58
  - lupin-mobile:lib.services.notification_filter.notification_stop_list.NotificationStopList@a49a38dcb0
  - lupin-mobile:lib.services.notification_filter.progress_group_collapse.MessageGroup@713929f277
  - lupin-mobile:lib.services.notification_filter.progress_group_collapse.collapseByProgressGroup@ec06c030f0
---
# Notification filtering

Three user controls decide what the phone shows and says: a stop-list of message prefixes, per-sender mutes, and collapsing of progress chatter. `NotificationStopList` and `collapseByProgressGroup` live in `services/notification_filter`. Mutes are stored by `NotificationPreferences`. See [[notification-audio-playback]], [[tts-streaming]] and [[notification-inbox]].

## What it does
- A `StopPattern` is a case-insensitive prefix of a trimmed `message`. A checked entry both hides and mutes the message, with one checkbox for both.
- `NotificationStopList.matches( message )` is the one predicate. It is applied in three places: focus ingest and backfill, the conversation list, and the TTS gate. `matchFor` names the rule, so a suppressed message is not mistaken for a hang.
- The list is saved as JSON. With nothing stored it seeds `Done:` patterns for the tool-call chatter (`mcp`, `Bash`, `ToolSearch`, `Read`, `Edit`, `Write`, `Grep`, `Glob`).
- `add` and `editAt` refuse a blank or duplicate pattern, ignoring case. `insertAt` restores a deleted entry at its old position with its old checked state.
- `collapseByProgressGroup( items, keyOf, enabled )` groups consecutive items with the same `progress_group_id` into a `MessageGroup`. It changes only what is drawn, never the list. The preference defaults to on.
- `showMuteSenderMenu` opens a long-press sheet that mutes or unmutes a sender and shows a SnackBar with Undo. The key and label come from `notificationSenderKey` and `notificationSenderLabel`, the same ones the delivery policy reads.
- A muted sender is let through for urgent items when the bypass preference is on, and it is on by default. `NotificationFilterSettingsScreen` edits the stop-list.

## Don't
- Don't hide an item by a rule of your own. Add a pattern, so the three call sites agree.
- Don't give a pending ask a progress-group key. Return null from `keyOf`, so it keeps its own row.
- Don't undo a delete with `add`. It appends at the end and forces the entry on.

## Invariants
- A null or blank message never matches. An out-of-range index is ignored, not clamped.
