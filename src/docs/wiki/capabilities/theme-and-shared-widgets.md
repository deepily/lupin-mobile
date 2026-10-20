---
capability: theme-and-shared-widgets
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.core.build_info_footer.BuildInfoFooter@33e3e79d85
  - lupin-mobile:lib.core.constants.app_constants.AppConstants@ebe9cae664
  - lupin-mobile:lib.core.constants.app_themes.AppThemes@21c8ea0828
  - lupin-mobile:lib.shared.painters.dashed_border_painter.DashedBorderPainter@6099c7ce5c
---
# Theme, constants and shared widgets

`AppThemes` holds the two Material 3 themes. `AppConstants` holds server paths, WebSocket event names and tuning values. Two small widgets live here: `DashedBorderPainter` and `BuildInfoFooter`. See [[ws-connection]], [[server-context]] and [[app-bootstrap-and-di]].

## What it does
- `AppThemes.lightTheme` and `AppThemes.darkTheme` are seeded from blue. `app.dart` passes both to the app, so the device setting picks one.
- `AppConstants.apiBaseUrl` and `wsBaseUrl` are mutable. `ServerContextService` rewrites them when the user switches server. The defaults point at the emulator alias `10.0.2.2:7999`.
- `AppConstants` also names the WebSocket paths `/ws/queue` and `/ws/audio`, and every event name the client handles, for example `job_state_transition`, `notification_queue_update` and `cc_transcript_append`.
- The job-state event is the live status channel. The four `queue_*_update` constants are marked dead because the server never emits them.
- Ask lifecycle events `notification_expired` and `notification_responded` carry their payload at the top level of the frame, not under `notification`.
- `transcriptRingBytes` is 256 KB, counted in bytes because the server uses the same size function.
- `DashedBorderPainter` draws a dashed circular stroke. The persona badge uses it.
- `BuildInfoFooter` shows the branch line, cut with an ellipsis, over a detail line that shrinks and is never cut. The focus drawer shows it.

## Don't
- Don't hard-code an event name or endpoint path in a bloc. Add a constant here and use it.
- Don't use a `queue_*_update` event for status. Use `eventJobStateTransition`.
- Don't cache `apiBaseUrl` in a field. It changes when the server context changes.

## Invariants
- Payload keys of the ask events sit at the top level of the frame.
- A build made without the stamping script shows "unstamped" in the footer, never a blank line.
