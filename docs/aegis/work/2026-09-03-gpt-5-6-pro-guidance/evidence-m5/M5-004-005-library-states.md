# M5-004 / M5-005 — library empty and loaded states

Status: **verified on the current store; no production change required**.

## M5-004 — empty state

Empty appears only after a successful zero-project load
(`testEmptyStateRequiresSuccessfulZeroProjectLoad`); a typed load failure
is never presented as empty (`testTypedLoadFailureIsNotPresentedAsEmptyLibrary`).
The create action is accessible in both locales/landscape
(`testLibraryEmptyStateBothLocalesLandscape`); no fake thumbnail or
placeholder project exists anywhere in the empty path.

## M5-005 — loaded state

Rows carry project UUID, name, updated date, preview status, and artifact
health (`testReloadProjectsSummariesAndDropsStaleSelection` and the
contact-sheet matrix); ordering is stable under reload
(`testReloadOrdersDuplicateNamesByUpdatedAtThenUUIDAndKeepsMetadata`);
selection/hit-regions and reduce-motion readability are pinned by the UI
matrix.

## Verification

26/26 (`SETLibraryModelTests` + `SETLibraryProductionUITests`) on
permitted iPhone 17e (`/private/tmp/m5-004-005-tests.xcresult`).
