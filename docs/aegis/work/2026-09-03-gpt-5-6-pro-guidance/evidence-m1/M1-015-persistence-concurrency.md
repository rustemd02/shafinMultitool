# M1-015 — Persistence concurrency contract

Task: Serialize scene/project mutation and define optimistic conflict behavior for simultaneous
save, rename, delete, and recording attach.
Owner boundary: `PersistenceOwner`. Rollback: revert DBService.swift + SceneGeneratorViewModel
snapshot-persistence diff + delete DBServiceConcurrencyTests.swift.

## Baseline hazards (pre-change)

`DBService` was a plain class: every file operation ran synchronously on the caller's thread with
no shared ordering. Overlapping operations could:

1. interleave a save between a delete's read and remove (project resurrection / dangling artifacts);
2. race two saves of the same project — last writer wins silently (lost update);
3. race `createUnifiedSceneProject`'s name check against a concurrent create (duplicate names);
4. expose a partially written multi-file state to `listUnifiedSceneProjects`.

## Change 1 — serialization

Private serial `persistenceQueue` (`DBService.persistenceQueue`); every public method body runs on
it via `queue.sync`. Public signatures unchanged (all were already synchronous). Internal
`*OnQueue` implementations call each other directly — `DispatchQueue.sync` is not reentrant, so
`createUnifiedSceneProject` → `listUnifiedSceneProjectsOnQueue` +
`saveUnifiedSceneProjectOnQueue`, `saveARWorldMap` → `saveLegacySceneOnQueue`,
`loadARWorldMap` → `loadLegacySceneFilesOnQueue` stay on one queue hop.

Completion-based APIs (`deleteMap`, `deleteUnifiedSceneProject`) now invoke their completion
synchronously from the queue — behavior-compatible with existing callers (SOInteractor treats it
as async, still fine).

## Change 2 — optimistic conflict behavior

Typed `DBServiceError.staleSnapshot(storedUpdatedAt: Date)` (Equatable, recoverable).

`saveUnifiedSceneProject(_:worldMap:expectedUpdatedAt:)`:
- `expectedUpdatedAt == nil` → no check (legacy call sites, initial writes).
- stored file exists for `project.id` and `stored.updatedAt != expectedUpdatedAt` → throw
  `staleSnapshot`; nothing is written (no lost update, no partial write).
- stored file missing → initial write, not a conflict.
- match → write proceeds atomically (single JSON envelope write, `.atomic`).

VM wiring (SceneGeneratorViewModel): the pre-bump `currentProject.updatedAt` is the stored version
the snapshot is based on:
- `persistProjectMetadata` (autosave): conflict → log and keep the stored version (a metadata
  autosave must never clobber a newer write);
- `persistProjectSnapshot` (teardown): both branches (fresh map / nil-map durable write) pass
  `expectedUpdatedAt`; conflict → `.failure(.persistenceFailed)`, which keeps teardown blocked and
  recoverable under the existing M1-009 retry semantics.

Recording attach flows through `recordingReferences` inside the same project envelope, so attach
is serialized and conflict-checked with every other mutation.

## Deliberate scope boundary

Save-after-delete can still recreate a project file (a save with no stored file is an initial
write). Coordinating deletion with an active workspace owner is M1-016 (ProjectLifecycleOwner),
which this unblocks.

## Narrow verification

`shafinMultitoolTests/DBServiceConcurrencyTests.swift` (5 tests, deterministic
`DispatchQueue.concurrentPerform` scheduling with lock-guarded result collection):
1. 8 concurrent creates of the same name → exactly one success, one stored project;
2. stale `expectedUpdatedAt` → typed `staleSnapshot(storedUpdatedAt:)`, stored write preserved,
   current writer proceeds;
3. missing stored file + expected value → initial write succeeds;
4. 16 overlapping saves → stored project is exactly one submitted snapshot, single project listed;
5. legacy-scene save/load consistency under concurrent writes.

Regression: SceneSaveLoadTests (persisted envelope compatibility) + SceneWorkspaceTeardownTests
(VM snapshot persistence path with the new expectedUpdatedAt wiring).
