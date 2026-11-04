---
capability: decision-proxy-client
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_repository.DecisionProxyRepository@9fe9b843fe
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_repository.DecisionProxyApiException@487d577eb8
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_bloc.DecisionProxyBloc@ba7d99d97b
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_state.DecisionProxyDashboardLoaded@132614f210
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.TrustMode@1c73042ee2
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.trustModeFromString@a70f96be96
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.TrustModeStatus@985c2d5954
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.ProxyDecision@7338573901
  - lupin-mobile:lib.features.decision_proxy.presentation.trust_dashboard_screen.TrustDashboardScreen@6e5d13d489
  - lupin-mobile:lib.features.decision_proxy.presentation.trust_state_screen.TrustStateScreen@6bc111d192
---
# Decision proxy client

The trust dashboard and trust-state screens for the decision proxy. The server side is lupin's `decision-proxy` page. Detail pages: [[decision-proxy-models]], [[decision-proxy-events-and-states]].

## What it does
- `DecisionProxyRepository` wraps nine calls under `/api/proxy/`. Failures become `DecisionProxyApiException` with the server's `detail` text, else a fixed fallback.
- `DecisionProxyBloc` loads mode, pending decisions and batch id. A failed batch lookup is swallowed and leaves `batch` null.
- Ratify, delete and acknowledge call the server, then reload the dashboard. `DecisionProxySetMode` reloads only if a dashboard was loaded first.
- `TrustMode` has four modes plus `unknown`. `trustModeFromString` maps null or any unrecognized string to `unknown`.
- `TrustModeStatus` holds the INI mode, the running job's mode and the `effective` mode. The picker shows and edits `effective`.
- `TrustDashboardScreen` shows the picker, one `ProxyDecision` card each with approve, reject and delete, and a batch footer.
- `TrustStateScreen` groups per-domain rows by domain and marks an open circuit breaker.

## Don't
- Don't give the trust screen its own bloc. Both screens share one, so the dashboard reloads when the trust screen closes.
- Don't offer `unknown` as a mode choice. It only means the server sent a string this build does not know.

## Invariants
- Leaving `active` asks first in a "Downshift trust mode?" dialog. Other mode changes, approve, reject and delete do not ask.
- `TrustModeUpdateResponse` (`updated` or `queued`) is dropped by the bloc. A queued change appears only after the reload.
- `DecisionProxyDashboardLoaded` compares by mode, counts and batch id, so same-count loads with different decisions do not re-emit.

## When not to use it
- The feature has no WebSocket handler. It refreshes by pull-down or reload; see [[ws-connection]].
