---
capability: fleet-status
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.fleet_status.data.fleet_repository.FleetRepository@385728dc8a
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.FleetComposite@8b5770a2c5
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.FleetSession@0ce1de855d
  - lupin-mobile:lib.features.fleet_status.data.fleet_watchable_models.FleetWatchableRoster@a5c00a5aad
  - lupin-mobile:lib.features.fleet_status.domain.fleet_status_bloc.FleetStatusBloc@757b011e76
  - lupin-mobile:lib.features.fleet_status.presentation.fleet_cap_dial.FleetCapDial@74957bb001
  - lupin-mobile:lib.features.fleet_status.presentation.fleet_row_card.FleetRowCard@7f0529e7f6
  - lupin-mobile:lib.features.fleet_status.presentation.fleet_status_pane.FleetStatusPane@d69a7cbd58
  - lupin-mobile:lib.features.fleet_status.presentation.fleet_status_screen.FleetStatusScreen@7e0fc46e4c
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.SkeletonCrew@60ca6ea4a5
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.activeReassignTargets@63717a65b8
---
# Fleet status

The Fleet Status destination: one card per seat, an offline toggle, the fleet-size cap dial and the skeleton crew switch. It reads the arbiter's state through the Lupin server.

## What it does
- `FleetRepository.fetchState` reads `/api/arbiter/fleet-state` into a `FleetComposite`. A 200 with `status: "unreachable"` means the arbiter is down, not that the fleet is empty. Check `isUnreachable`.
- `FleetSession` holds one seat. `whoLabel` falls back to the first 8 characters of the session id. `isOffline` is true only for the exact verdict `offline`, so a stale seat stays visible.
- `FleetRowCard` shows eight facts in three bands, with the raw liveness ages behind a tap. Context figures join on the exact persona string, with no case folding.
- `FleetStatusBloc` polls the state and the cap together, so the dial never drifts from the table. It follows [[pane-polling-and-visibility]].
- `FleetCapDial` writes through `setCap`, a PUT of `{"cap": n}`. The floor is 1. The ceiling is the server's setting, so the client has no upper clamp.
- `SkeletonCrew` is read from the cap body. `setSkeletonCrew` PUTs `{"on": bool}`, and only an administrator login may flip it.
- `fetchWatchable` reads the admin-gated roster. `FleetWatchableRoster.watchableSessionIds` decides which cards show a watch button, see [[live-transcript]].
- `activeReassignTargets` lists live personas, sorted, for the owner control in [[task-row-and-verbs]].

## Don't
- Don't show the number posted. Both writes adopt the server's re-read. A refusal re-reads live state, so the dial and switch snap back, and rethrows.
- Don't hide a seat because its verdict is not `LIVE`. Only `offline` is hidden.
- Don't read a failed watchable call as an error. It returns the empty roster and every button hides.

## Invariants
- A cancelled request is rethrown as a cancel, never as a failure.
- A missing `skeleton_crew` object (an older server) hides the switch.
- Open item: `watchableRosterEndpoint` is a provisional path, marked TODO in `FleetRepository`.
