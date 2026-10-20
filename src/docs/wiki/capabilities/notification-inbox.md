---
capability: notification-inbox
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.notifications.data.notification_models.NotificationItem@a078f35921
  - lupin-mobile:lib.features.notifications.data.notification_models.ConversationMessage@e3af2e0557
  - lupin-mobile:lib.features.notifications.data.notification_models.SenderSummary@624770ccec
  - lupin-mobile:lib.features.notifications.data.notification_repository.NotificationRepository@2764e17baf
  - lupin-mobile:lib.features.notifications.data.notification_repository.NotificationApiException@d862b3eab6
  - lupin-mobile:lib.features.notifications.domain.notification_bloc.NotificationBloc@55d846a326
  - lupin-mobile:lib.features.notifications.presentation.inbox_screen.InboxScreen@c1b75acb05
  - lupin-mobile:lib.features.notifications.presentation.conversation_screen.ConversationScreen@e4ceb036c8
  - lupin-mobile:lib.features.notifications.presentation.message_stamp.MessageStamp@2c4e251136
  - lupin-mobile:lib.shared.models.notification_item.NotificationItem@1d49a35e14
---
# Notification inbox

The inbox lists the senders who notified the user, opens one sender's conversation and stays fresh from WebSocket frames. Card answers are [[interactive-prompts]]; badges are [[voice-personas]]. The server half is lupin's `notification-delivery` page.

## What it does
- `NotificationRepository` wraps the `/api/notifications/...` routes on the shared Dio. Every failure becomes `NotificationApiException` with the server's `detail` text. Path segments are percent-encoded.
- `NotificationBloc` loads four views: the sender list, one flat conversation, a sender's dates and a conversation grouped by date. Each emits `NotificationsLoading`, then a loaded state or `NotificationsError`.
- `NotificationsExternalUpdate` is the WebSocket path. It routes by type, then refetches the current view. A failed refresh keeps the last good state.
- Ordinary types pass the foreground delivery gate and ding through `NotificationAudioService.handleIncoming`; see [[notification-audio-playback]]. The three commons types do nothing here.
- `InboxScreen` shows one tile per sender. Swiping a tile deletes that sender's conversation with no confirmation. A long press offers mute; see [[notification-filtering]].
- `ConversationScreen` shows messages newest first, hides stop-list matches behind a chip and collapses a progress group into one card. An open question never collapses.
- `MessageStamp` draws the local `HH:mm:ss` stamp, with an `MM-dd` prefix for another day.

## Don't
- Don't import `lib/shared/models/notification_item.dart`. It duplicates `NotificationItem` in `notification_models.dart`, and nothing imports it.
- Don't pass a TTS orchestrator to `NotificationBloc`. `FocusChatBloc` is the only speaker; a second one would speak every frame twice.
- Don't expect a screen to call `deleteOne`, `deleteDate`, `activeConversation` or `projectSessions`. Nothing calls them.

## Invariants
- A refresh before any view has loaded does nothing. Each model's `fromJson` fills defaults and does not throw.
