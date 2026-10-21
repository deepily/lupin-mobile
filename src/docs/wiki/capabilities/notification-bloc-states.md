---
capability: notification-bloc-states
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationState@2d3ddb594e
  - lupin-mobile:lib.features.notifications.domain.notification_state.SpeakerphoneSnapshotMixin@ac604106e0
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsInitial@5d7b841f85
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsLoading@771bdecd43
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsInboxLoaded@beaf4e6469
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsConversationLoaded@dcab4a4843
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsResponding@d8f6edb9f1
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsResponseAcked@336134a4fc
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsError@8154fde4b6
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsGistLoading@7171c7b934
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsGistReady@6e8bf8bfd1
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsSenderDatesLoaded@ede880f78d
  - lupin-mobile:lib.features.notifications.domain.notification_state.NotificationsConversationByDateLoaded@2a1ae51b6b
  - lupin-mobile:lib.features.notifications.presentation.conversation_by_date_screen.ConversationByDateScreen@a311e0d89e
  - lupin-mobile:lib.features.notifications.presentation.sender_dates_screen.SenderDatesScreen@842d7082e3
---
# Notification bloc states

The states `NotificationBloc` emits, all subclasses of `NotificationState`, and the two by-date screens that show them. The bloc, repository and inbox are in [[notification-inbox]]; the inputs are in [[notification-bloc-events]].

## What it does
- `NotificationsInitial` and `NotificationsLoading` are the empty and in-flight states. `NotificationsError` carries one message for the user.
- The four loaded states are `NotificationsInboxLoaded`, `NotificationsConversationLoaded`, `NotificationsSenderDatesLoaded` and `NotificationsConversationByDateLoaded`. Each carries the persona map and the `SpeakerphoneSnapshotMixin` map.
- `NotificationsResponding` holds the id being answered. `NotificationsResponseAcked` holds the server's ack.
- `NotificationsGistLoading` and `NotificationsGistReady` bracket a summary request. The bloc re-emits the loaded conversation afterwards, on success and on failure, so the list stays visible.
- `SenderDatesScreen` lists a sender's dates with counts and opens `ConversationByDateScreen` for the tapped date. That screen shows the dates newest first.

## Don't
- Don't read `speakerphoneFor` in a screen to change behavior. Nothing reads the snapshot yet; it is diagnostic.
- Don't compare dates or by-date states by content. Their equality uses the number of dates, the total count and the two maps.
