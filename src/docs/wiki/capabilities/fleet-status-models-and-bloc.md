---
capability: fleet-status-models-and-bloc
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.FleetLiveness@c24d6fbf2d
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.FleetContextRecord@4b1677f2bd
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.formatWindowSize@c28eebf94f
  - lupin-mobile:lib.features.fleet_status.data.fleet_models.formatConsumptionPct@5dc9a6c17c
  - lupin-mobile:lib.features.fleet_status.data.fleet_repository.FleetApiException@9fd4e80013
  - lupin-mobile:lib.features.fleet_status.data.fleet_watchable_models.FleetWatchableRow@b64cc0b4fd
  - lupin-mobile:lib.features.fleet_status.domain.fleet_status_bloc.FleetStatusEvent@abbbf8be5a
  - lupin-mobile:lib.features.fleet_status.domain.fleet_status_bloc.FleetStatusLoaded@6453a683c1
  - lupin-mobile:lib.features.fleet_status.domain.fleet_status_bloc.FleetStatusFailed@a8b73eb1a5
  - lupin-mobile:lib.features.fleet_status.domain.fleet_status_bloc.FleetStatusRefreshRequested@65dbf3589c
  - lupin-mobile:lib.features.fleet_status.domain.fleet_status_bloc.FleetStatusState@053610a8fe
---
# Fleet status models and bloc

The liveness and context models, formatters, watchable row and bloc events behind [[fleet-status]].

## What it does
- `FleetLiveness` holds five ages in seconds and the arbiter's free-form verdict. Every field is nullable, and a non-numeric age becomes null. `livenessDetail` on a session joins five segments, with `n/a` for a null age.
- `FleetContextRecord` holds the percent of the window used and the window size. A non-map input gives an all-null record, which the columns show as an em dash.
- `formatWindowSize` prints `1M` or `200K` for exact millions and thousands, the plain integer otherwise, and an em dash for null, zero or negative. `formatConsumptionPct` prints the server's number untouched, `8%` for 8.0 and `32.8%`, and an em dash for null.
- `FleetApiException` carries the server's `detail` or a status fallback, with a null `statusCode` for a transport failure. It is distinct from a 200 whose composite says the arbiter is unreachable.
- `FleetWatchableRow` is one seat from the admin-gated projection. `transcriptWatchable` is true only for a real boolean `true`; any other type reads false. The phone does not display `lastTs` yet.
- `FleetStatusLoaded` carries a poll's composite, cap, ceiling, skeleton crew and watchable roster. A null roster keeps the set held, and `keepSkeletonCrew` keeps the held switch.
- `FleetStatusFailed` sets the error text and ends loading. `FleetStatusRefreshRequested` sets loading, then polls once.
- `FleetStatusState` holds the latest composite, cap, switch, error and watchable ids.

## Don't
- Don't send a cap-only `FleetStatusLoaded` with a roster. A null `watchable` is what stops a cap change from hiding every watch button.
- Don't give `FleetStatusBloc` to the app root. It is route-scoped.
