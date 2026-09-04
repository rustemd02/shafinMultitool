# M5-002 — Unified Scene project schema migration

Status: implementation and focused simulator verification complete on the task
branch, including the fresh Sol fix-first corrections. This receipt does not
claim physical-device, ARWorldMap, media, or App Store qualification.

## Contract implemented

- New `UnifiedSceneProjectFile` saves contain exactly the current envelope
  discriminator `schemaVersion: 1` alongside `project` and the optional
  `archivedWorldMap` payload.
- Raw `UnifiedSceneProject` JSON and an unversioned `{project,
  archivedWorldMap}` envelope are read as v0. Reads and list operations never
  rewrite them; the next successful legitimate save emits v1.
- Negative, fractional, null, string, unsupported-future, and versioned raw
  shapes fail closed before project decoding. A future file cannot be listed,
  deleted, or silently overwritten by a v1 save.
- Existing-file validation happens before the atomic project write, so a
  malformed/future record and an invalid recording reference leave the previous
  project bytes and recording references untouched.
- `SceneRecordingReference` uses one shared safe-relative-path validator on
  both decode and encode; persisted traversal/absolute/NUL paths are rejected
  before the aggregate can be returned to a caller.
- Filename UUID fencing, malformed-envelope no-fallback, corrupt-record
  isolation, legacy world-map sidecar behavior, optimistic stale snapshots,
  overlapping saves, and safe relative recording-path encoding remain covered.
- A manually authored frozen v0 fixture exercises nonempty marked objects,
  actors, objects, ordered beats/actions, cameras, spatial relations, planned
  actor paths/poses/cameras/annotations/beat IDs, planned objects, overlays,
  chunk continuity state, and recording references through both raw and
  unversioned-envelope migrations.
- A future-version fixture owns a promoted recording artifact; failed load,
  list, save, and delete paths preserve both the project bytes and artifact
  bytes.

## Changed files

- `shafinMultitool/Services/DBService.swift`
- `shafinMultitool/Entity/SceneData.swift`
- `shafinMultitoolTests/SceneProjectSchemaMigrationTests.swift`
- `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m5/M5-002-scene-schema-migration.md`

`SceneData.swift`, `SceneScript.swift`, and `ScenePlanning.swift` required no
schema-owner changes; their Codable aggregate data is carried by the single
DBService envelope.

## Verification

Source state before the task edit: `f8ada4d state: start scene schema migration`.

Command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:shafinMultitoolTests/SceneProjectSchemaMigrationTests -only-testing:shafinMultitoolTests/SceneSaveLoadTests -only-testing:shafinMultitoolTests/DBServiceConcurrencyTests -derivedDataPath /tmp/setos-m5-002-fix-full-VwfPXc/DerivedData -resultBundlePath /tmp/setos-m5-002-fix-full-VwfPXc/M5-002-fix.xcresult
```

Result: `** TEST SUCCEEDED **`; 41/41 test cases passed:

- `SceneProjectSchemaMigrationTests`: 8/8
- `SceneSaveLoadTests`: 28/28
- `DBServiceConcurrencyTests`: 5/5

Destination was an ordinary iPhone 17 simulator, not iPhone 17 Pro. Result
bundle: `/tmp/setos-m5-002-fix-full-VwfPXc/M5-002-fix.xcresult`.

Additional check: `git diff --check` passed.

## Known limits

- `archivedWorldMap` migration was exercised as envelope data/sidecar
  compatibility; creating and unarchiving a real `ARWorldMap` remains a
  hardware/runtime concern.
- Physical recording/media validation and future schema producers remain
  outside M5-002.
- The result bundle is task evidence under `/tmp` and must be retained until
  the parent integrates and records the final receipt; cleanup may then remove
  only this task's explicitly named temporary directory.
