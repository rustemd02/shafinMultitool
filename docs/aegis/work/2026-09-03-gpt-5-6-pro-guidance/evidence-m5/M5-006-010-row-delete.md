# M5-006 / M5-010 — selected row and scene deletion

Status: **verified on the current store; no production change required**.

## M5-006 — selected row

Select/open/rename/delete expose non-overlapping hit regions
(`testSelectedActionHitRegionsDoNotOverlapAndKeepOrder`); selection
requires the idle flow (`testSelectRequiresIdleFlow`); stale selections
drop on reload (`testReloadProjectsSummariesAndDropsStaleSelection`);
VoiceOver order is deterministic through the stable row/action identities.

## M5-010 — deletion

Confirmation names the scene and reloads only on success
(`testDeleteConfirmationReloadsOnlyOnSuccess`); cancel is a no-op without
mutating selection or invoking the provider
(`testCancelDeleteDoesNotMutateSelectionOrInvokeProvider`); failure keeps
the scene with retry (`testDeleteFailureKeepsSceneAndOffersRetry`,
`testDeleteSceneCompletionReportsMissingProject`); successful deletion
removes the project and its owned artifacts through the reversible
staging transaction (M7-025).

## Verification

19/19 unit (`SETLibraryModelTests`) + 7/7 UI
(`SETLibraryProductionUITests`) on permitted iPhone 17e, run as separate
batches per the one-batch-per-boot recipe
(`/private/tmp/m5-006-unit.xcresult`, `/private/tmp/m5-006-010-tests.xcresult`
— the combined run's single failure is the known parallel UI/unit
contention, both suites green in isolation).
