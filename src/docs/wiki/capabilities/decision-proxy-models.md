---
capability: decision-proxy-models
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.trustModeToString@8e0b328e7a
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.PendingSummary@b6f04867fe
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.PendingDecisionsResponse@427dacbbd0
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.RatifyResponse@7ff2c24fbd
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.DeleteDecisionResponse@e26bac4fe5
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.TrustStateItem@57504b9443
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.TrustStateResponse@887cd922e3
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.DecisionsByCategoryResponse@a84084735d
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.BatchIdResponse@a4dccaeec6
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.AcknowledgeResponse@6ed07f5fd5
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.TrustModeUpdateRequest@61c1a3eb15
  - lupin-mobile:lib.features.decision_proxy.data.decision_proxy_models.TrustModeUpdateResponse@65b81996eb
---
# Decision proxy models

The response and request classes for the `/api/proxy/` calls, beyond the four pinned on [[decision-proxy-client]]. Their events and states are on [[decision-proxy-events-and-states]].

## What it does
- `PendingDecisionsResponse` holds a list of `ProxyDecision` and a `PendingSummary` with the total, counts by category, counts by trust level and the oldest pending time. List entries that are not maps are skipped.
- `RatifyResponse` and `DeleteDecisionResponse` echo the decision id and who acted. `RatifyResponse` adds the resulting state and any feedback.
- `BatchIdResponse` names the current batch. `AcknowledgeResponse` names the batch retired and the one that replaced it; the request has no body.
- `TrustStateItem` is one domain and category row with total, approved and rejected counts and an optional circuit-breaker state. `TrustStateResponse` wraps the list.
- `DecisionsByCategoryResponse` wraps decisions for one domain and category. Only the repository builds it; no bloc or screen asks for it.
- `TrustModeUpdateRequest` sends the mode and a domain that defaults to `swe`. `TrustModeUpdateResponse` carries status `updated` or `queued`, both modes and the target.
- `trustModeToString` returns the wire word and gives `"unknown"` for `TrustMode.unknown`.

## Don't
- Don't build a `TrustModeUpdateRequest` with `TrustMode.unknown`. Its wire string is `"unknown"`, which is not one of the four modes.
- Don't read `TrustModeUpdateResponse.jobId` on a queued change. It is present only when status is `updated`.
