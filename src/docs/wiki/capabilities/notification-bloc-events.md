---
capability: notification-bloc-events
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationEvent@c4073da3af
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsLoadInbox@8db668e077
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsLoadConversation@b47162232a
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsMarkPlayed@2191d276a6
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsRespond@68c0d13066
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsBulkDelete@21ed8fb608
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsDeleteConversation@3a3d0b9870
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsExternalUpdate@bfe28644b9
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsGenerateGistRequested@f10e742e2c
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsLoadSenderDates@6f5a94e0f9
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsLoadConversationByDate@4b64b557b4
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsVoicePersonaAssigned@f800d2c21e
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsVoicePersonaReleased@ebfd7d9386
  - lupin-mobile:lib.features.notifications.domain.notification_event.NotificationsSpeakerphoneChanged@32579a54d1
---
# Notification bloc events

The inputs `NotificationBloc` accepts, all subclasses of `NotificationEvent`. The bloc, repository and screens are in [[notification-inbox]]; the states they produce are in [[notification-bloc-states]].

## What it does
- `NotificationsLoadInbox` takes an email, an hours window and the `includeHidden` and `excludeOwnJobs` flags. `NotificationsLoadConversation`, `NotificationsLoadSenderDates` and `NotificationsLoadConversationByDate` open one sender's thread, its dates and its by-date view.
- `NotificationsRespond` sends an answer, then marks the notification played on a best-effort basis. `NotificationsMarkPlayed` marks one and refreshes the current view.
- `NotificationsBulkDelete` and `NotificationsDeleteConversation` each delete, then reload the inbox.
- `NotificationsExternalUpdate` is the WebSocket path and carries the item, or null when the frame had none.
- `NotificationsGenerateGistRequested` carries nothing. The bloc reads the messages from the conversation already on screen and ignores the event otherwise.
- `NotificationsVoicePersonaAssigned` and `NotificationsVoicePersonaReleased` update the persona map by `senderId`. Releasing a sender with no persona emits nothing.
- `NotificationsSpeakerphoneChanged` carries only the on flag, so its record has no displaced fields.

## Don't
- Don't set `includeHidden` on `NotificationsLoadConversation` expecting an effect. The repository call ignores it.
- Don't read the persona map to choose a voice. Speech takes the persona from each notification.

## Invariants
- Events compare by their fields, with two exceptions: `NotificationsExternalUpdate` compares by notification id alone, and `NotificationsVoicePersonaAssigned` by sender id and voice id.
