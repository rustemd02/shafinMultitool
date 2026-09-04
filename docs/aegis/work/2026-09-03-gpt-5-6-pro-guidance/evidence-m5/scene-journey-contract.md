# M5-001 Scene journey contract

## Scope

`SceneJourneyContract.production` in `SceneBundleContracts.swift` is a
non-owning, typed catalog for the fixed production journey:

`Library → Generator → AR → Storyboard → recording → Library`.

It freezes 84 stable, unique state IDs. The catalog covers every relevant
Visual Policy v2.6 row for Library, Generator input/execution, AR, Storyboard,
the scene/marker/screenplay/decision-trace sheets, and recording lifecycle and
export. Library rename and missing-preview outcomes are explicit, with a
rename-duplicate state that retains the validated existing project. Generator
validation, queueing, pause/cancel, quota/malformed/persistence failures, and
storyboard planning/validation/reorder are also explicit contract states.

Each state carries a typed owner and typed source vocabulary, explicit entry,
action, recovery, exit, persistence, artifact relations, and typed transitions.
Artifact relations distinguish `draft`, `validated`, `optional`, `missing`,
`pending`, and `promoted`, with required/optional semantics. The canonical ID
set is an explicit list and is validated independently of `allCases`.

## Ownership and persistence boundary

The contract does not own state, routes, persistence, or artifacts. Existing
owners remain authoritative: `SETLibraryModel.FlowState`,
`SceneGenerationStage`, `SceneWorkspaceMode`, `RecordingLifecycleState`,
`SceneScript`, `PlannedScene`, `RecordingArtifact`, and the existing AR,
storyboard, keyboard, persistence, trace, and export owners are represented by
`SceneJourneySourceState` and `SceneJourneyOwner`.

No downstream artifact is implied by entering a later state. For example,
generator success has a validated script and plan but a pending storyboard;
`generator.success` reaches `storyboard.planning`, then
`storyboard.validation`, and only a validated relation reaches the result. AR
recording is pending until its owner publishes media, and review requires a
promoted/resolvable recording. Preflight, permission, playback, recovery, and
recording export-cancel/export-failure are explicit. Export is owned by
`LegacySceneGeneratorCameraShell/UIActivityViewController` (Photos is future),
while both export failures preserve the promoted source recording.
`recording.released` retains project-owned media as an optional relation and
project persistence; it is not encoded as artifact deletion. This preserves
the same terminal owner state for both cancelled/no-artifact and
completed/promoted paths without making a false cleanup claim.

The catalog declares `library.empty` and `library.contact-sheet` as real entry
states and validates graph reachability from those entries. Every non-
`.unreachable` state is reachable, including live-hint pause/playback,
recording idle/preparing, scene-name/marker-name sheets, and the pending typed
clarification path. Recorder-backed states map to `RecordingLifecycleState`;
cross-owner review/export/recovery edges use the explicit
`.outer-navigation` classification. The illegal promoting→released and
failed→ready edges are absent.

This is contract-only work. It adds no runtime reducer, route, persisted field,
schema migration, UI styling, fake data, database behavior, or simulator/device
qualification. Pending/unreachable availability marks policy states whose
runtime ownership is a later task rather than claiming they already exist.

## Verification receipt

| Check | Result |
|---|---|
| `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:shafinMultitoolTests/SceneJourneyContractTests -derivedDataPath /tmp/setos-m5-001-correction2-kigyvT/DerivedData-fix1 -resultBundlePath /tmp/setos-m5-001-correction2-kigyvT/SceneJourneyContractTests-fix1.xcresult CODE_SIGNING_ALLOWED=NO` | PASS; 6 focused cases passed on iPhone 17e; `** TEST SUCCEEDED **` |
| `git diff --check` | PASS after correction and evidence update |
| canonical ID set, graph reachability, typed source/owner/persistence/artifact mappings | PASS in `testProductionContractIsCompleteAndTyped` and `testExpectedOwnerPersistenceAndArtifactMappings` |
| full success/export route, storyboard validation route, and failure/recovery/teardown traces | PASS in `testSuccessExportTraceUsesLegalTypedEdges` and `testFailureRecoveryAndTeardownTraces` |
| exhaustive recorder lifecycle edge classification and legal transition check | PASS in `testRecordingTransitionsAreExhaustiveAndTyped`; outer navigation is explicit and no illegal promoting→released or failed→ready edge exists |
| truncated/malformed custom contracts fail closed | PASS in `testCustomContractValidationFailsClosed` |
| completed → released does not imply recording cleanup | PASS: `recording.completed → recording.released` is legal while released recording status is `.optional` and persistence remains `.project` |
| forbidden shortcut/scope scan | PASS by inspection: only the owned contract, focused test, and this evidence changed; no `EXECUTION_STATE`, project file, runtime route, reducer, persisted field, database, fake data, or UI styling changes |

The first correction build exposed and fixed one Swift `guard` closure syntax
error before the final receipt above. The final test emitted pre-existing Xcode
warnings (including device build-number metadata and an unprocessed
`Circle.rcproject` folder); none failed the focused target. The receipt is
simulator compilation/execution evidence only. It does not prove physical AR,
recording media integrity, backend quality, or end-to-end device
qualification; those belong to later milestone tasks.
