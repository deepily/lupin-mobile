---
capability: holding-area-pane
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.FilerGroup@40205c90a1
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.holdingApproveAllHint@0a59c39cc2
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.holdingWontFixAllHint@63eba7c605
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.batchLabel@46c7d6401b
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.holdingApproveAllConfirmBody@88aad07d9a
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.holdingApproveAllConfirmAccept@14724455a3
  - lupin-mobile:lib.features.holding_area.data.holding_area_repository.HoldingAreaFetchException@35d75f2177
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaEvent@5bdf95d30e
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaRefreshRequested@a3da7cc28b
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaRowVerbPressed@a7da8b43fa
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaApproveAllPressed@c9341ec71a
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaWontFixAllPressed@977245a961
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaFieldChanged@0574ddf7f7
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaRosterRequested@37e7e5ddbe
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaUnsentRetryRequested@12c81fb890
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaGroupToggled@52d058a698
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaReasonChanged@2e7096c0a2
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaState@ffb2cd2231
  - lupin-mobile:lib.features.holding_area.presentation.filer_group_header.FilerGroupHeader@5b3e6b84fe
  - lupin-mobile:lib.features.holding_area.presentation.holding_area_pane.HoldingAreaPane@7cc4269035
---
# Holding area pane

The group model, batch wording, events and state of the pane described on [[task-board-panes]]. Rows are the shared `TaskRow` from [[task-row-and-verbs]]; the batch controls live in the group header.

## What it does
- `FilerGroup` is one persona's held rows; its `ids` and `count` read the same rows, so a batch label and a batch send agree. `HoldingAreaFetchException` wraps a failed fetch.
- `holdingApproveAllHint` and `holdingWontFixAllHint` are the controls' accessible hints: approving is reversible, won't-fix-all is terminal with one shared reason. `batchLabel` makes `Approve (3)`.
- `holdingApproveAllConfirmBody` names the filer and count, and `holdingApproveAllConfirmAccept` repeats the verb. Won't-fix-all has no confirm; its reason box is the gate.
- `FilerGroupHeader` keeps the persona, count and both batch controls on screen while a group is folded. `HoldingAreaPane` lists the groups, folded until opened.
- `HoldingAreaRefreshRequested` is a poll, a pull or a resume. `HoldingAreaRowVerbPressed` applies one verb to one row.
- `HoldingAreaApproveAllPressed` runs after the pane has already confirmed. `HoldingAreaWontFixAllPressed` with a blank reason sets a complaint and unfolds the group.
- `HoldingAreaFieldChanged` sends priority or owner through the field door, not the transition door. `HoldingAreaRosterRequested` loads the owner choices and gives an empty list on any failure.
- `HoldingAreaUnsentRetryRequested` resends writes the network dropped, before any refetch.
- `HoldingAreaGroupToggled` and `HoldingAreaReasonChanged` carry the persona, not a position.
- `HoldingAreaState` keeps the typed reasons, the unfolded set and unsent writes across polls. The unfolded set is not persisted.
