---
capability: pane-polling-and-visibility
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.fleet.domain.pane_visibility_mixin.PaneVisibilityMixin@20f02d89c9
  - lupin-mobile:lib.features.fleet.domain.pane_polling_mixin.PanePollingMixin@96f1fe861f
  - lupin-mobile:lib.features.fleet.presentation.pane_host_screen.PaneHostScreen@1f6963acab
  - lupin-mobile:lib.features.fleet.domain.unsent_write.UnsentWrite@0b2cd7cedd
  - lupin-mobile:lib.features.fleet.domain.unsent_write.RetryOutcome@d30c79cff4
  - lupin-mobile:lib.features.fleet.domain.unsent_write.isTransportFailure@b8ae9f8800
  - lupin-mobile:lib.features.fleet.domain.unsent_write.retryUnsentWrites@1eb083c904
---
# Pane polling and visibility

Two bloc mixins make a screen poll only while it is on screen and the app is in front. `PaneHostScreen` supplies the Scaffold and the route-scoped bloc.

## What it does
- `PaneVisibilityMixin` tracks two flags: the route says visible, and the app lifecycle says foreground. It calls the host's `onActiveChanged( active:, refreshNow: )` on every change.
- `refreshNow` is true on pane-visible and on a return from the background, never when inactive. Only `resumed` counts as foreground, so a notification-shade pull also earns one refresh.
- It owns one in-flight request slot. `claimRequest` returns a fresh `CancelToken`, or null when a request is outstanding. `releaseRequest` clears the slot only if the token still holds it.
- Going hidden or backgrounded cancels the in-flight request. Stopping a timer does not cancel an HTTP call.
- `PanePollingMixin` adds a periodic timer on top. The host implements `pollOnce( CancelToken )` and calls `startPolling` once.
- The interval is 60 s on Wi-Fi and 180 s on mobile data. It is read when the timer is created, so a network change waits for the next hide/show or background trip.
- `PaneHostScreen<B>` takes a bloc factory, not an instance, so an unopened pane has no bloc and issues no requests.

## Don't
- Don't register a pane bloc at the app root. It outlives its route and keeps polling.
- Don't declare the mixins in the wrong order. `PanePollingMixin` is `on PaneVisibilityMixin`, so the compiler refuses it.
- Don't skip `onPaneVisible` and `onPaneHidden` in the route. The host stays inactive until the route calls them.

## Invariants
- At most one request is outstanding per pane. A tick that lands during a poll does nothing.
- `close` stops the timer, cancels the request and drops the lifecycle subscription.
- Users with both mixins: [[task-board-panes]] blocs and [[fleet-status]]. The transcript stream bloc uses visibility only, see [[live-transcript]].
