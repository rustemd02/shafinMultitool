# M5-003 — Library provider contract

Status: correction implementation and focused simulator verification complete
on `codex/set-os-m5-003-fix1`. This receipt covers the Library
ownership/CRUD contract only; it does not claim completion of the later Library
visual slices, physical-device camera/AR verification, media capture, or App
Store qualification.

## Contract implemented

- `SETLibraryFailure` is the typed failure vocabulary across the existing
  `SETLibrarySceneProviding → SOPresenter → SOInteractor → DBService` chain.
  Load, invalid/duplicate names, missing identity, stale snapshots, active
  leases, persistence, artifact cleanup, preview availability, and unsupported
  legacy operations remain distinguishable.
- Production Library reads now use strict decoding of persisted
  `UnifiedSceneProject` records. A malformed record is a load failure and is
  never presented as an empty Library.
- `SETLibrarySceneSnapshot` carries UUID, name, update timestamp, truthful
  preview metadata, and typed artifact health. Metadata-only and unavailable
  previews are explicit; a recording reference alone never reports a healthy
  artifact.
- Create duplicate detection and persistence share the existing serial
  `DBService.persistenceQueue`, so concurrent callers produce one winner and
  typed duplicate outcomes for the rest.
- Rename is UUID- and `expectedUpdatedAt`-based. It changes only name and
  timestamp, keeps the full project aggregate and legacy world-map bytes, and
  returns typed missing/duplicate/stale/persistence outcomes.
- Delete is UUID- and snapshot-based, checks the existing lifecycle lease, and
  stages owned recording artifacts before removing project/map metadata. The
  artifact owner commits only after metadata mutations succeed and restores
  partial unlink failures; DBService restores the exact project/map bytes on
  any later failure. Typed artifact-cleanup/persistence failures are returned
  without claiming deletion success. The legacy name-based API remains
  available and now maps the typed outcome to its original Bool completion.
- Model retry stores an immutable operation (including UUID and expected
  timestamp) rather than resolving a later selection by name. Load failures,
  create/rename/delete/open failures, duplicate flows, and cancellation remain
  separate presentation states.
- The selected scene row no longer contains nested interactive controls: the
  selection button, open action, and delete action are siblings. Existing
  routes and `sceneRow`/`sceneOpen`/`sceneDelete` accessibility identifiers are
  preserved.

## Changed files

- `shafinMultitool/ScenesOverviewModule/SETLibraryProductionView.swift`
  — typed projection, model state/retry contract, fixture bridge, and
  nested-control removal.
- `shafinMultitool/ScenesOverviewModule/SOInteractor.swift` — typed Library
  interactor methods over the existing DB owner.
- `shafinMultitool/ScenesOverviewModule/SOPresenter.swift` — typed projection
  and existing-name router bridge.
- `shafinMultitool/Services/DBService.swift` — serialized typed snapshot,
  create, rename, delete, artifact health, and strict-load paths.
- `shafinMultitoolTests/SETLibraryModelTests.swift` — typed load/CRUD/retry,
  duplicate, rename, cancellation, and stale presentation coverage.
- `shafinMultitoolTests/DBServiceConcurrencyTests.swift` — typed serialization,
  metadata/artifact health, aggregate-preserving rename, stale no-mutation,
  and artifact-cleanup no-mutation coverage.
- `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m5/M5-003-library-provider-contract.md`
  — this receipt.

No project file, router, teardown owner, schema model, or execution-state file
was changed. `RecordingArtifactStore` changed only to add the reversible
staging/commit/rollback seam; no M5-004…M5-012 visual work is included.

## Verification

Baseline: `24b0d18 state: close scene schema migration`; implementation branch
`codex/set-os-m5-003` in the isolated M5-003 worktree.

Focused command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:shafinMultitoolTests/SETLibraryModelTests -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests -derivedDataPath /tmp/setos-m5-003-dd-9 -resultBundlePath /tmp/setos-m5-003-tests-9.xcresult
```

Result: `** TEST SUCCEEDED **`; 24/24 test cases passed:

- `SETLibraryModelTests`: 14/14.
- `DBServiceConcurrencyTests`: 10/10.

Schema compatibility command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:shafinMultitoolTests/SceneProjectSchemaMigrationTests -derivedDataPath /tmp/setos-m5-003-dd-7 -resultBundlePath /tmp/setos-m5-003-tests-7.xcresult
```

Result: `** TEST SUCCEEDED **`.

`git diff --check` passed before staging. All simulator runs used an ordinary
iPhone 17 simulator, never iPhone 17 Pro and never a physical device. No
screenshots or motion video were produced because this contract slice does not
change the production visual surface; later visual packages own that evidence.

## Known limits and deferrals

- Rename and delete are now behaviorally typed, but rename-specific UI sheets
  remain owned by the later Library visual package; the model states already
  exist for that integration.
- The existing legacy summary APIs are retained for compatibility and their
  default typed adapters cannot infer artifact health beyond the data they are
  given. The production `DBService` adapter is the authoritative path.
- Real ARWorldMap decode, camera/recording hardware timing, physical-device
  permissions, and App Store release checks remain outside M5-003.
- Result bundles are task evidence under `/tmp`; cleanup may remove only the
  explicitly named M5-003 temporary directories after parent integration.

## Correction round — `codex/set-os-m5-003-fix1`

Root causes closed:

- Artifact deletion unlinked source files directly, so a later unlink or
  metadata failure could leave a partial project. The store now creates
  identity-checked same-volume hard-link staging, commits only after all
  metadata mutations succeed, and rolls back missing source links on failure.
- Typed and legacy delete completions were invoked inside
  `persistenceQueue.sync`; a callback that synchronously queried DBService
  could deadlock. Each API now captures its result inside the queue and calls
  back after leaving it.
- The Library contact sheet independently rendered `scenes.isEmpty` and the
  failure panel, allowing a load failure to masquerade as an empty Library.
  A typed load failure now owns the hero branch and suppresses empty-state
  content and mutation controls.

Direct regression coverage:

- `testStagedArtifactCommitRollsBackAfterInjectedPartialUnlink` proves an
  injected second-unlink fault restores both artifacts.
- `testTypedDeleteRollsBackMetadataWhenArtifactCommitFailsPartway` proves the
  DB path returns `.artifactCleanup` and restores project JSON, world-map
  sidecar, and both artifacts.
- `testStagedDeleteRollsBackAfterWorldMapFailure` and
  `testStagedDeleteRollsBackAfterProjectFailure` prove staged artifacts and
  both metadata roots are restored after injected post-mutation faults.
- `testTypedDeleteCompletionCanSynchronouslyReloadWithoutDeadlock` exercises
  a reentrant completion callback with a bounded XCTest expectation.
- `testTypedLoadFailureIsNotPresentedAsEmptyLibrary` proves the model's
  rendering decision suppresses the empty-state hero on load failure.

Final focused command (ordinary iPhone 17 Simulator UUID
`1F708A11-8262-4E09-9F3A-46C86381911D`; never iPhone 17 Pro or physical
device):

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,id=1F708A11-8262-4E09-9F3A-46C86381911D' -derivedDataPath /tmp/setos-m5-003-fix1-final-dd -resultBundlePath /tmp/setos-m5-003-fix1-final.xcresult -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests -only-testing:shafinMultitoolTests/SETLibraryModelTests -only-testing:shafinMultitoolTests/SceneProjectSchemaMigrationTests -only-testing:shafinMultitoolTests/SceneRecordingControllerTests/testFinalizedArtifactPromotionIsIdempotentAndResolvesProjectFile -only-testing:shafinMultitoolTests/SceneRecordingControllerTests/testRecordingArtifactStoreRejectsOutsideAndSymlinkPaths -only-testing:shafinMultitoolTests/SceneRecordingControllerTests/testRecordingArtifactStoreRemovesOnlyChosenProjectAndIsIdempotent -only-testing:shafinMultitoolTests/SceneRecordingControllerTests/testStagedArtifactCommitRollsBackAfterInjectedPartialUnlink -only-testing:shafinMultitoolTests/SceneRecordingControllerTests/testRecordingArtifactStoreFailsClosedForUnexpectedEntryWithoutTouchingExternalTarget -only-testing:shafinMultitoolTests/SceneRecordingControllerTests/testRecordingArtifactStoreRejectsSymlinkedRootAndProjectDirectory
```

Result: `** TEST SUCCEEDED **`; 42/42 test cases passed:

- `DBServiceConcurrencyTests`: 14/14.
- `SETLibraryModelTests`: 14/14.
- `SceneProjectSchemaMigrationTests`: 8/8.
- RecordingArtifactStore-focused `SceneRecordingControllerTests`: 6/6.

Evidence paths: `/tmp/setos-m5-003-fix1-final.xcresult` and
`/tmp/setos-m5-003-fix1-final.log`. `git diff --check` passed after the
correction edits; scope audit contains only the three owned production/test
paths plus this receipt.

Known correction risk: a post-commit tombstone cleanup interruption retains a
hidden staging directory for safety; it is not reported as a rollback failure
after the authoritative deletion has already committed. Physical filesystem,
camera/AR timing, and App Store release behavior remain outside this slice.
