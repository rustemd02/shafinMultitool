# M5-006 / M5-010 / M5-012 Library actions receipt

Status: correction complete on `codex/set-os-m5-006-010-012` (base `7d1f995`; correction commit recorded below).

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
  `2`, delete `1`. The visual selected marker is hidden from accessibility;
  the row's `.isSelected` trait is the sole selected semantic. Open/rename/
  delete preserve the selected UUID by routing through `SETLibraryModel`, not
  by resolving a later selection by name.
- The production UI test measures all four hit regions (selection row, open,
  rename, delete), asserts every pair is disjoint, and checks the observed
  accessibility traversal order is exactly row → open → rename → delete.
  It also checks all three action labels/identifiers in the selected RU and EN
  fixture rows.

## M5-010 — confirmation and deletion boundary

- The existing confirmation panel now exposes the localized scene-detail text
  through `library_delete_detail`; the text names the exact scene before the
  destructive action. Cancel returns the model to idle without invoking the
  provider, changing selection, or changing the loaded rows.
- Deletion continues to use the accepted M5-003 typed UUID/snapshot API and
  M1-016 `ProjectLifecycleRegistry` lease fence. `DBService` now always stages
  the canonical project-ID directory through `RecordingArtifactStore` before
  removing project/map metadata, even when references are empty (promotion can
  precede metadata persistence), then commits or rolls back the staged bytes.
  No alternate deletion owner was introduced.
- The final DB suite proves successful deletion removes only the selected
  project and its owned artifact while retaining a sibling project's project
  and artifact bytes. Focused cases also prove active lease rejection,
  unexpected-store-entry failure, partial artifact-commit rollback, promoted-
  before-metadata deletion and rollback with no persisted reference, metadata
  rollback, and synchronous completion/reload safety. Pending and sibling
  media are asserted unchanged.

## M5-012 — truthful preview provenance

- `RecordingArtifactStore.resolve(_:ownedBy:)` requires the exact canonical
  `Recordings/Projects/<project UUID>/<recording UUID>.mov` binding before its
  existing safe-root/non-symlink/regular-file validation. `DBService` projects
  a reference only when that binding resolves to a non-empty, playable,
  readable AVFoundation movie with a finite video duration and video track.
  Foreign-project/Pending paths never become sources; missing, deleted,
  zero-byte, or nonzero corrupt media yields the catalogued fallback/health.
- A valid recording-only project is still projected as metadata-only preview
  metadata when screenplay/storyboard fields are empty; media validity is not
  incorrectly gated on unrelated metadata.
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
- Correction DB run (ordinary iPhone 17 simulator, iOS 26.5):
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-correction-db-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-correction-db.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests` — **22/22 passed**. The suite creates a real movie with `AVAssetWriterRecordingWriterFactory`, rejects valid foreign/Pending references, rejects nonzero corrupt bytes, accepts recording-only metadata, and proves promoted-artifact success/rollback.
- Correction model run:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-correction-model2-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-correction-model2.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/SETLibraryModelTests` — **19/19 passed**.
- Correction artifact/controller run:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-correction-artifact2-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-correction-artifact2.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/RecordingArtifactPromotionTests -only-testing:shafinMultitoolTests/SceneRecordingControllerTests` — **23/23 passed**.
- Correction targeted accessibility run:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-correction-ui-target-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-correction-ui-target.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolUITests/SETLibraryProductionUITests/testSelectedActionHitRegionsDoNotOverlapAndKeepOrder` — **1/1 passed**.
- Correction full production Library UI run:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/setos-m5-006-010-012-correction-ui-full-dd -resultBundlePath /private/tmp/setos-m5-006-010-012-correction-ui-full.xcresult -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -only-testing:shafinMultitoolUITests/SETLibraryProductionUITests` — **7/7 passed**. This includes RU/EN metadata fallback labels, named RU confirmation, EN cancel preservation, and the four-region/traversal assertion.
- `git diff --check` passed. The correction UI result bundle exported **19**
  landscape PNG attachments plus a manifest at
  `/private/tmp/setos-m5-006-010-012-correction-ui-attachments-1788572913/`;
  selected-action evidence is `m5-library-selected-en-landscape-actions` and
  cancel evidence is `m5-library-delete-cancel-en-landscape`. Existing copy
  coverage remains RU+EN and the full UI matrix exercised both locales.

## Evidence boundary / remaining risk

The Library route is intentionally landscape-only (`CommercialSceneNavigationController`);
the compact-width vertical fallback is covered by source layout and the
selected action frame check, but no portrait screenshot is claimed. All UI and
media checks are simulator evidence on ordinary iPhone 17/iOS 26.5. Physical
VoiceOver behavior and camera-produced media playback remain external acceptance
boundaries; no iPhone 17 Pro or physical iPhone 13 was used.

Correction commit: `bb5c1e04f96692eb9e4cf20a7d7e545da775fca9`.
