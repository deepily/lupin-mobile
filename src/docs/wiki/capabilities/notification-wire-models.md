---
capability: notification-wire-models
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.notifications.data.ask_resolution.classifyRespondFailure@f1c7b8055f
  - lupin-mobile:lib.features.notifications.data.ask_resolution.classifyResumeStatus@a3fcafd949
  - lupin-mobile:lib.features.notifications.data.notification_models.SpeakerphoneRecord@54eb777ac2
  - lupin-mobile:lib.features.notifications.data.notification_models.NotificationListResponse@bae9755c4a
  - lupin-mobile:lib.features.notifications.data.notification_models.NextNotificationResponse@28625a8cbc
  - lupin-mobile:lib.features.notifications.data.notification_models.StatusAckResponse@50c32d2db8
  - lupin-mobile:lib.features.notifications.data.notification_models.BulkDeleteResponse@11252f447b
  - lupin-mobile:lib.features.notifications.data.notification_models.ActiveSession@7f80c933d1
  - lupin-mobile:lib.features.notifications.data.notification_models.DateSummary@f9ff4d8c6b
  - lupin-mobile:lib.features.notifications.data.notification_models.ConversationDeleteResponse@4fc31fae4d
  - lupin-mobile:lib.features.notifications.data.notification_models.DateDeleteResponse@7749af8053
  - lupin-mobile:lib.features.notifications.data.notification_models.ActiveConversationResponse@040cc0cd18
  - lupin-mobile:lib.features.notifications.data.notification_models.ProjectSession@222d4bf053
  - lupin-mobile:lib.features.notifications.data.notification_models.GistResponse@02bdafdbcb
  - lupin-mobile:lib.features.notifications.data.notification_models.NotificationResponsePayload@df3990c826
  - lupin-mobile:lib.features.notifications.data.notification_models.NotificationResponseAck@02d5c1c033
  - lupin-mobile:lib.features.notifications.data.notification_models.NotifyDispatchResponse@26fed753b7
  - lupin-mobile:lib.features.notifications.data.notification_models.NotifyRequest@ac12198218
  - lupin-mobile:lib.features.notifications.data.notification_models.GistRequest@2de1a0b0a1
  - lupin-mobile:lib.shared.models.notification_item.NotificationType@25dd083a07
---
# Notification wire models

The response and request models behind the `/api/notifications/...` and `/api/notify/...` routes. The repository and bloc that use them are in [[notification-inbox]]; the bloc halves are [[notification-bloc-events]] and [[notification-bloc-states]].

## What it does
- Each response class has a `fromJson` that fills defaults for missing keys. `NotificationListResponse`, `NextNotificationResponse`, `StatusAckResponse`, `BulkDeleteResponse` and the two delete responses mirror one route each.
- `NotificationResponsePayload` serializes the answer to `POST /api/notify/response`; `NotificationResponseAck` is its reply. `NotifyRequest.toQuery` omits null fields because the backend reads the query string.
- `ActiveSession` here is one seat from the commons active-sessions route. Its persona is built from flat `persona_*` keys; a seat with no persona name gets no persona.
- `classifyRespondFailure` and `classifyResumeStatus` turn "already responded", "grace period exceeded", `already_resumed` and `pending_expired` into `AskResolution` values.

## Don't
- Don't rely on `NotificationType`. Nothing outside its own file refers to it.
- Don't expect `ActiveConversationResponse`, `ProjectSession` or `DateDeleteResponse` to be called by a screen; only the repository uses them.
- Don't read `SpeakerphoneRecord.displaced` to decide anything. The bloc stores it and never acts on it.
