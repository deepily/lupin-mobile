---
capability: decision-proxy-events-and-states
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxyEvent@bf99efc68f
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxyLoadDashboard@c2efbd68a9
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxySetMode@5cd202635b
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxyRatify@cadb365b0d
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxyDeleteDecision@2f2d029276
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxyAcknowledge@5385dd7d3b
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_event.DecisionProxyLoadTrust@77c94821e8
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_state.DecisionProxyState@8848659bb8
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_state.DecisionProxyInitial@0e0f1b9698
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_state.DecisionProxyLoading@99593dd4a9
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_state.DecisionProxyTrustLoaded@47f467669d
  - lupin-mobile:lib.features.decision_proxy.domain.decision_proxy_state.DecisionProxyError@ed91b6d8d0
---
# Decision proxy events and states

The inputs and outputs of `DecisionProxyBloc`. The bloc, repository and screens are on [[decision-proxy-client]]; the response classes are on [[decision-proxy-models]].

## What it does
- `DecisionProxyLoadDashboard` takes a user email, loads mode and pending decisions, then tries the batch id. A failed batch lookup leaves `batch` null.
- `DecisionProxySetMode`, `DecisionProxyRatify`, `DecisionProxyDeleteDecision` and `DecisionProxyAcknowledge` each call the server, then reload the dashboard. `DecisionProxySetMode` reloads only after a dashboard has been loaded.
- `DecisionProxyRatify` carries the decision id, the user, an approved flag and optional feedback. `DecisionProxySetMode` defaults its domain to `swe`.
- `DecisionProxyLoadTrust` loads per-domain trust states; a null domain loads every domain.
- `DecisionProxyInitial` and `DecisionProxyLoading` are the empty and in-flight states. `DecisionProxyTrustLoaded` holds the trust response. `DecisionProxyError` holds the server's message.
- A `DecisionProxyApiException` in any handler becomes `DecisionProxyError`.

## Don't
- Don't expect `DecisionProxyTrustLoaded` to re-emit when a row's counts change. It compares only the number of rows.
- Don't expect a reload after `DecisionProxyLoadTrust`. Only the dashboard events reload.
