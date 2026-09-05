# M5-004, M5-005, M5-011 — Library state projections

Status: implementation and focused simulator verification complete on
`codex/set-os-m5-004-005-011`. This receipt covers Library empty/loaded/failure
state projections, persisted ordering/metadata, operation-scoped retry
identity, and the open-retry/localization correction. It does not claim
rename-sheet UI, new media previews, camera/AR qualification, or any
M5-006…M5-012 behavior.

## Contract implemented

- The empty hero is gated by a successful typed snapshot load of zero projects.
  Before the first result, after a failed load, and during a mutation failure
  with no rows, the surface does not invent an empty-store result. The empty
  fixture starts with no provider projects and performs one successful load;
  it exposes only the existing create action and no list/preview/media.
- Typed load projections retain persisted UUID, name, `updatedAt`, preview
  metadata, and artifact health. Model and legacy list ordering is
  `updatedAt` descending, then UUID string ascending, including timestamp ties
  and duplicate names. No fake thumbnail or media is derived.
- Create retry replays the captured trimmed name directly. Rename retry keeps
  the captured UUID, draft name, and `expectedUpdatedAt` across a reload.
  Delete retry keeps UUID and expected timestamp; completion matching also
  fences on the captured timestamp. Selection and applicable drafts remain
  attached to their operation while recovery is shown.
- An open failure captures the selected UUID; a successful open retry clears
  that operation and returns the model to `.idle`, so the recovery panel and
  retry action do not remain stale.
- Load failures remain typed recovery state and never render the empty hero.
  Mutation failures retain already-loaded rows and render the existing failure
  panel; the failure panel exposes title/detail/retry identifiers and the
  retry action remains the only recovery action.
- Preview and artifact-health accessibility phrases resolve through typed
  `SETCopyKey` entries with RU/EN String Catalog values. The compact values
  remain exactly the existing status phrases; no visible Package 3 copy or
  media derivation changed.
- Existing `SETLibrarySceneProviding → SOPresenter → SOInteractor → DBService`
  ownership and Package 3 SET visual components remain in place. DEBUG-only
  fixture IDs are deterministic projection metadata and never publish media.

## Changed files

- `shafinMultitool/ScenesOverviewModule/SETLibraryProductionView.swift` —
  successful-load gate, stable ordering, operation retry retention, row
  accessibility values, deterministic fixture metadata, and failure IDs.
- `shafinMultitool/Services/DBService.swift` — UUID tie-breaker for the legacy
  summary list; strict typed-load behavior was already the production path.
- `shafinMultitoolTests/SETLibraryModelTests.swift` — empty/load distinction,
  metadata/order projection, create retry isolation, rename identity/draft/
  timestamp retention, delete retry identity coverage, and open failure→retry
  success recovery coverage.
- `shafinMultitoolTests/DBServiceConcurrencyTests.swift` — real zero-project
  result, malformed-record load failure, and persisted duplicate-name/tie
  ordering coverage.
- `shafinMultitoolUITests/SETLibraryProductionUITests.swift` — required
  landscape RU/EN fixture matrix, failure/list accessibility assertions,
  Dynamic Type/Reduce Motion/Reduce Transparency evidence, and exact M5
  screenshot attachment names.
- `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m5/M5-004-005-011-library-states.md`
  — this receipt.
- `shafinMultitool/Multitool2Module/UI/DesignSystem/SETLocalization.swift` —
  typed preview/artifact-health copy keys.
- `shafinMultitool/Resources/Localizable.xcstrings` — exact RU/EN catalog
  values for those keys.

No `SOViewController.swift` edit was needed: its existing
`viewWillAppear`/`updateUI` reloads already route the runtime model through the
typed presenter contract. No routes, orientation forwarding, schema, lifecycle
leases, artifact deletion, project file, Visual Policy, or `EXECUTION_STATE.md`
changed.

## Verification

All required simulator commands used the ordinary iPhone 17 simulator on iOS
26.5 (device UUID `1F708A11-8262-4E09-9F3A-46C86381911D`), never iPhone 17 Pro
and never a physical device.

Focused unit/integration command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/setos-m5-004-005-011-dd -resultBundlePath /tmp/setos-m5-004-005-011-unit.xcresult -only-testing:shafinMultitoolTests/SETLibraryModelTests -only-testing:shafinMultitoolTests/SETLibraryInteractorOutcomeTests -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests
```

Result: `** TEST SUCCEEDED **`; xcresult summary reports 36/36 passed, 0
failed, 0 skipped:

- `DBServiceConcurrencyTests`: 17/17.
- `SETLibraryModelTests`: 17/17.
- `SETLibraryInteractorOutcomeTests`: 2/2.

Correction focused unit/integration command (with diagnostics disabled to
avoid the simulator diagnostic subprocess hanging after a failed test):

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/setos-m5-004-005-011-correction-dd -resultBundlePath /tmp/setos-m5-004-005-011-correction-unit-2.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/SETLibraryModelTests -only-testing:shafinMultitoolTests/SETLibraryInteractorOutcomeTests -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests
```

Result: `** TEST SUCCEEDED **`; xcresult summary reports 37/37 passed, 0
failed, 0 skipped on iPhone 17 iOS 26.5:

- `DBServiceConcurrencyTests`: 17/17.
- `SETLibraryModelTests`: 18/18, including
  `testOpenRetrySuccessReturnsToIdleAndClearsRetry`.
- `SETLibraryInteractorOutcomeTests`: 2/2.

The first correction run without `-collect-test-diagnostics never` reported
36 passed and one failure in the pre-existing random-UUID delete-test setup;
the failed test passed on its isolated rerun, and the final correction run
above passed all 37 selected tests. No delete production code was changed.

Production fixture UI command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/setos-m5-004-005-011-dd -resultBundlePath /tmp/setos-m5-004-005-011-ui.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolUITests/SETLibraryProductionUITests
```

Result: `** TEST SUCCEEDED **`; xcresult summary reports 5/5 passed, 0
failed, 0 skipped. The required screenshots were exported with:

```text
xcrun xcresulttool export attachments --path /tmp/setos-m5-004-005-011-ui.xcresult --output-path /tmp/setos-m5-004-005-011-attachments
```

The export contains 16 PNG attachments plus `manifest.json`; all 16 are
1206×2622 encoded pixels with screenshot orientation metadata, equivalent to
2622×1206 landscape presentation. The manifest records iPhone 17 for every
attachment. Required attachment stems are present:

- `m5-library-empty-ru-landscape`
- `m5-library-empty-en-landscape`
- `m5-library-contact-sheet-ru-landscape`
- `m5-library-contact-sheet-en-landscape`
- `m5-library-contact-sheet-en-landscape-xxl`
- `m5-library-contact-sheet-ru-landscape-reduce-transparency`
- `m5-library-persistence-failure-ru-landscape`
- `m5-library-persistence-failure-en-landscape`
- `m5-library-persistence-failure-en-landscape-reduce-motion`

Correction UI run used `/tmp/setos-m5-004-005-011-correction-ui.xcresult` and
exported to `/tmp/setos-m5-004-005-011-correction-attachments-2`. Its xcresult
summary reports 5/5 passed, 0 failed, 0 skipped on iPhone 17 iOS 26.5; the
export again contains 16 PNG attachments plus `manifest.json`, all 1206×2622
pixels (2622×1206 landscape presentation), with every required attachment stem
present. The built `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`
contain all nine new `set.library.preview.*`/`set.library.artifact.*` keys with
the preserved English/Russian values.

The UI assertions cover empty-state/list exclusivity, one reachable empty
create action, loaded title/count/list/row topology, persisted UUID and
localized media-health announcement, duplicate-name identity, >=44pt empty,
row, and retry actions, failure title/detail/retry order, mutation-failure
row retention, RU/EN stable IDs, landscape orientation, XXL readability, and
Reduce Motion/Transparency fixture overrides. No video attachment was added.

`git diff --check` passed. Scope inspection from base `bd2dd09` contains only
the eight changed paths listed above; `SOViewController.swift` was inspected
and did not need an edit.

## Judgment calls

- A pre-load model and a mutation failure with zero rows render a blank content
  area plus the typed recovery panel rather than the empty hero. This keeps
  “empty” reserved for `Result.success([])` without inventing a loading owner
  or a second recovery action.
- Existing localizable keys did not include preview/artifact-health phrases.
  The correction adds only typed `SETCopyKey` cases and their exact existing
  RU/EN String Catalog values; the row still leaves visible Package 3 copy
  unchanged.
- Existing row IDs are preserved as positional `library_scene_row_N` IDs; the
  accessible row value additionally announces the persisted UUID, so duplicate
  names remain distinguishable without adding a parallel identifier owner.
- The production action call sites retain the shared 44pt SET hit-target token;
  XCTest reported one exact 44pt frame as `43.99999999999997`, so UI assertions
  allow only a `0.0001` floating-point representation tolerance rather than
  weakening the hit-target contract.
- The prior live Unicode create-tap UI assertion was replaced by the existing
  deterministic duplicate-state fixture because the create panel is below the
  landscape viewport in this production fixture; the typed duplicate behavior
  remains covered by model tests and the fixture still exercises the same
  production surface/state.

## Gaps

- Physical camera/AR/media qualification, rename-sheet UI, and later M5 slices
  remain outside this batch.
- The generated xcresult/attachment artifacts are retained under `/tmp` for
  parent review and are not repository files.
