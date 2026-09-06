# M8-001 — Storyboard contract

Status: **verified on the current store against the canonical journey
contract; no production change required**.

## Coverage audit (every verify dimension → contract + tests)

| Verify dimension | Journey states | Behavior tests |
|---|---|---|
| tray collapsed/expanded | `storyboard.tray-collapsed`, `storyboard.tray-expanded` (typed entry/exit/persistence) | collapse without mutation (contract edge) |
| selection | `storyboard.selection-reflow` | `testStoryboardSelectionOwnerCancelsAndConsumesOneStableEvent`, `testStoryboardMutationOwnerRejectsDuplicateSubmits` |
| reflow | selection-reflow edges | `testStoryboardMoveAddAndDeleteReplans` |
| result | `storyboard.result` + `storyboard.saving` | success integration (M5-030 provenance) |
| inspector | `storyboard.inspector` | `testStoryboardBeatInspectorShowsActorsTargetsAndDuration`, `…WarnsAboutMissingTargetAndEmptyText` |
| editor medium/large | `storyboard.editor-medium`, `storyboard.editor-large` | `testStoryboardManualEditChangesActionAndReplans`, `testStoryboardManualEditRejectsSelfGive`, `testStoryboardBeatEditFailsBeforeMutationWhenObjectIdentityIsUnavailable` |
| save | saving state + persistence `.project` | save/load + concurrency suites |
| validation failure | `storyboard.validation`, `storyboard.validation-failure`, `storyboard.projection-validation-failure` | validation edit tests |
| delete | `storyboard.delete-confirmation`, `storyboard.reorder` | `testStoryboardMoveAddAndDeleteReplans` |
| marker naming | `sheet.marker-name` | marker name validation (`generatorErrorMarkerName`) |
| trace | owner `trace` (DecisionTraceView + VM) | Decision Trace presentation tests |
| media links | recording references on the persisted project (M7-020/M7-025) | artifact resolve/promotion/deletion suites |

The 96-state `SceneJourneyContract.production` validates (`validate()`
true, exact 96-state identity receipt, owner/persistence/artifact mappings,
reachability) — `SceneJourneyContractTests` 6/6.

## Verification

`SceneJourneyContractTests` 6/6 on permitted iPhone 17e
(`/private/tmp/m8-001-tests.xcresult`); the behavior legs are pinned by the
suites in the table (all green in their lanes).
