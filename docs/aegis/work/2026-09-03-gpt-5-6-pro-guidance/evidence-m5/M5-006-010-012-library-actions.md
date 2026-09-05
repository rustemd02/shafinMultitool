# M5-006 / M5-010 / M5-012 Library actions receipt

Status: implementation complete on `codex/set-os-m5-006-010-012`.

This batch stays inside the existing Library presentation/provider/interactor/
DBService/RecordingArtifactStore owners. It does not add a repository, reducer,
preview cache, deletion transaction, route, or rename transaction system.

## M5-006 — selected-row actions

- `SETLibrarySceneRow` keeps the existing row selection button and now exposes
  sibling `OPEN`, `RENAME`, and `DELETE` buttons. Each action has its own
  stable identifier and at least the shared 44-point hit target; the selected
  content uses a horizontal layout when it fits and a vertical `ViewThatFits`
  fallback for compact widths, so sibling hit regions cannot overlap.
- VoiceOver order is explicit: selection row priority `4`, open `3`, rename
  `2`, delete `1`. Open/rename/delete preserve the selected UUID by routing
  through `SETLibraryModel`, not by resolving a later selection by name.
- The production UI test measures the three action frames and asserts every
  pair is disjoint. It also checks all three action labels/identifiers in the
  selected RU and EN fixture rows.

## M5-010 — confirmation and deletion boundary

- The existing confirmation panel now exposes the localized scene-detail text
  through `library_delete_detail`; the text names the exact scene before the
  destructive action. Cancel returns the model to idle without invoking the
  provider, changing selection, or changing the loaded rows.
- Deletion continues to use the accepted M5-003 typed UUID/snapshot API and
  M1-016 `ProjectLifecycleRegistry` lease fence. `DBService` stages owned
  `RecordingArtifactStore` entries, removes the project/map, commits artifacts,
  and rolls back metadata and staged artifacts on a failure. No alternate
  deletion owner was introduced.
- The final DB suite proves successful deletion removes only the selected
  project and its owned artifact while retaining a sibling project's project
  and artifact bytes. Existing focused cases in the same suite prove active
  lease rejection, unexpected-store-entry failure, partial artifact-commit
  rollback, metadata rollback, and synchronous completion/reload safety.

## M5-012 — truthful preview provenance

- `DBService.makeLibrarySnapshotOnQueue` projects the first recording reference
  only when `RecordingArtifactStore.resolve` accepts its safe relative path and
  the owned file exists with non-zero size. The reference remains tied to the
  persisted project UUID/path; missing, deleted, zero-byte, or corrupt media
  yields no preview source.
- `SETLibraryScenePreview` decodes a poster frame on demand only from that
  owned reference. Decode failure also falls back to a flat, deterministic
  metadata surface labelled `METADATA PLACEHOLDER` / `МЕТАДАННЫЕ —
  ЗАПОЛНИТЕЛЬ`, with beats/actors/objects/takes metadata. No bundled fixture
  image, inferred thumbnail, or synthetic media enters the production view.
- There is no existing persisted storyboard bitmap/media-reference field in
  `UnifiedSceneProject`; storyboard/planned-scene metadata therefore takes the
  honest labelled fallback unless a valid owned recording reference is present.
  Adding a new storyboard-media schema would exceed this slice.

## Localization and verification

- New copy is present in `Localizable.xcstrings` for both `en` and `ru`:
  rename action/a11y label, recording preview label, metadata placeholder
  label/detail. `jq` coverage check returned `true`; the xcstring also compiled
  in every UI/DB run.
- Focused model/DB/lease run (ordinary iPhone 17 simulator, iOS 26.5):
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-unit-final-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-unit-final.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/SETLibraryModelTests -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests -only-testing:shafinMultitoolTests/ProjectLifecycleRegistryTests` — **40/40 passed**.
- Final DB run after the success-path assertion:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-db-success-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-db-success.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests` — **19/19 passed**.
- Final focused production Library UI run:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-ui-final2-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-ui-final2.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolUITests/SETLibraryProductionUITests` — **7/7 passed**. This includes the RU/EN selected-row metadata label, named RU confirmation, EN cancel preservation, and the measured non-overlap action test.
- `git diff --check` passed. The UI result bundle exported **19** landscape PNG
  attachments plus a manifest at
  `/private/tmp/setos-m5-006-010-012-ui-attachments-final-1788571264/`; the
  selected-action evidence is `m5-library-selected-en-landscape-actions` and
  the cancel evidence is `m5-library-delete-cancel-en-landscape`.

## Evidence boundary / remaining risk

The Library route is intentionally landscape-only (`CommercialSceneNavigationController`);
the compact-width vertical fallback is covered by source layout and the
selected action frame check, but no portrait screenshot is claimed. All UI and
media checks are simulator evidence on ordinary iPhone 17/iOS 26.5. Physical
VoiceOver behavior and camera-produced media playback remain external acceptance
boundaries; no iPhone 17 Pro or physical iPhone 13 was used.
