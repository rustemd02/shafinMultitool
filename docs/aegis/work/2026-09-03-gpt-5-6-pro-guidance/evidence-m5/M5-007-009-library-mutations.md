# M5-007 / M5-008 / M5-009 — scene creation, duplicate names, rename

Status: **verified on the current store; no production change required**.

## M5-007 — creation

Valid names create exactly one project and select it
(`testConfirmCreateTrimsDraftAndOpensSceneOnSuccess`); whitespace/empty
drafts are rejected (`testConfirmCreateReportsInvalidDraft`); a persistence
failure shows recovery without a partial row and retry succeeds
(`testCreatePersistenceFailureShowsRecoveryAndRetrySucceeds`).

## M5-008 — duplicates

Exact/case/normalized duplicates enter the typed duplicate flow without
touching persistence (`testLocalDuplicateEntersDuplicateFlowWithoutTouchingPersistence`,
`testProviderDuplicateMapsToDuplicateFlow`); project IDs stay distinct and
ordering is deterministic (`testReloadOrdersDuplicateNamesByUpdatedAtThenUUIDAndKeepsMetadata`).

## M5-009 — rename

Rename is transactional on the stable UUID with optimistic snapshot
(`testRenameUsesStableIDAndExpectedSnapshot`); duplicates are typed without
mutating the provider (`testRenameDuplicateIsTypedAndDoesNotMutateProvider`);
retry retains the ID draft and expected timestamp across reload
(`testRenameRetryRetainsIDDraftAndExpectedTimestampAfterReload`); failure
recovery is never erased by reload
(`testReloadDoesNotEraseMutationFailureRecovery`).

## Verification

41/41 (`SETLibraryModelTests` + `DBServiceConcurrencyTests`) on permitted
iPhone 17e (`/private/tmp/m5-007-009-tests.xcresult`).
