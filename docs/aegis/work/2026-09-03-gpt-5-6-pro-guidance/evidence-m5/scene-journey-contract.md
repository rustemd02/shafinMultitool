# M5-001 Scene journey contract

## Scope

`SceneJourneyContract.production` in `SceneBundleContracts.swift` is a
non-owning, typed catalog for the fixed production journey:

`Library → Generator → AR → Storyboard → recording → Library`.

It freezes 96 stable, unique state IDs. The catalog covers every relevant
Visual Policy v2.6 row for Library, Generator input/execution, AR, Storyboard,
the scene/marker/screenplay/decision-trace sheets, and recording lifecycle and
export. Library rename and missing-preview outcomes are explicit, with a
rename-duplicate state that retains the validated existing project. Generator
validation, queueing, pause/cancel, background recovery, timeout, compilation,
quota/malformed/persistence failures, and storyboard planning/validation/reorder
are also explicit contract states. Generator parse/compilation correction paths
return through validation before acceptance, and compilation retains the
validated script. AR relocalization, reset, and world-map recovery are explicit
rather than inferred from a generic error row.

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
`storyboard.validation`, and only a validated relation reaches the result. Its
projection-validation failure is distinct from editor draft validation, so a
projection failure cannot claim an editor draft. AR
recording is pending until its owner publishes media, and review requires a
promoted/resolvable recording. Preflight, permission, playback, recovery, and
recording share/Photos export-cancel/export-failure are explicit. The current
share path is owned by
`LegacySceneGeneratorCameraShell/UIActivityViewController`; Photos export is a
separate future `PHPhotoLibrary` owner (M7-028). Share and Photos failure/cancel outcomes
preserve the promoted source recording.
Photos success uses `project + retained recording source + external export receipt`
persistence: the project-owned source remains available while the external Photos
copy is recorded separately. Photos export states use the distinct typed
`SceneJourneyArtifact.photosExportReceipt` relation; the generic
`recordingExport` relation remains reserved for the current share hand-off.
`recording.released` retains project-owned media as an optional relation and
project persistence; it is not encoded as artifact deletion. This preserves
the same terminal owner state for both cancelled/no-artifact and
completed/promoted paths without making a false cleanup claim.

The catalog declares `library.empty` and `library.contact-sheet` as real entry
states and validates graph reachability from those entries. Every non-
`.unreachable` state is reachable, including live-hint pause/playback,
recording idle/preparing, scene-name/marker-name sheets, and the pending typed
clarification path. An active recording interruption or teardown first enters
`recording.stopping`, then a terminal recording outcome; it has no direct
active-recording→AR interruption/teardown edge. Recorder-backed states map to
`RecordingLifecycleState`; cross-owner review/share/Photos/recovery edges use
the explicit `.outer-navigation` classification, and the validator accepts
only the closed allowlist. The illegal promoting→released and failed→ready
edges are absent. A failed promotion remains in `recording.promoting` with a
pending relation and is never represented as a project-owned/promoted recording.
The owner retains the same finalized source in `pendingRecordingArtifacts` and retries
`recording.promoting` through an explicit typed `.retry` self-edge; the validator
allows only that self-edge when the required recording relation is `.pending` and
the trigger identifies `pendingRecordingArtifacts`. It does not mark that source
missing or retry finalization.
Only `recording.completed` exposes review/share/Photos edges. Capture/finalization
failure remains the separate missing-artifact `recording.failed` path.

This is contract-only work. It adds no runtime reducer, route, persisted field,
schema migration, UI styling, fake data, database behavior, or simulator/device
qualification. Pending/unreachable availability marks policy states whose
runtime ownership is a later task rather than claiming they already exist.

## Verification receipt

| Check | Result |
|---|---|
| `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:shafinMultitoolTests/SceneJourneyContractTests -derivedDataPath /tmp/setos-m5-001-correction6-20260904/DerivedData -resultBundlePath /tmp/setos-m5-001-correction6-20260904/SceneJourneyContractTests.xcresult CODE_SIGNING_ALLOWED=NO` | PASS; 6/6 focused cases passed on iPhone 17e (simulator, OS 26.5), exit 0 |
| `git diff --check` | PASS after correction and evidence update |
| canonical 96-ID set, graph reachability from both Library entries, typed source/owner/persistence/artifact mappings | PASS in `testProductionContractIsCompleteAndTyped` and `testExpectedOwnerPersistenceAndArtifactMappings`; Photos uses typed `photosExportReceipt`, separate from share `recordingExport` |
| full success/current-share/Photos route, storyboard validation route, and generator/AR/recording failure/recovery/teardown traces | PASS in `testSuccessExportTraceUsesLegalTypedEdges` and `testFailureRecoveryAndTeardownTraces` |
| exhaustive recorder lifecycle edge classification and legal transition check | PASS in `testRecordingTransitionsAreExhaustiveAndTyped`; outer navigation is explicit and allowlisted, promotion retry is the only invariant-backed lifecycle self-edge, with no active-recording→AR shortcut or illegal promoting→released/failed→ready edge |
| truncated/malformed custom contracts fail closed | PASS in `testCustomContractValidationFailsClosed` |
| completed → released does not imply recording cleanup | PASS: `recording.completed → recording.released` is legal while released recording status is `.optional` and persistence remains `.project`; Photos completion uses retained-source + external-export-receipt semantics |
| future state ownership does not overclaim production | PASS: generator/AR/recording future states carry `.pending` availability and explicit `planned:` source/owner labels where downstream ownership is not proven; current share owner remains the only claimed external export owner |
| forbidden shortcut/scope scan | PASS by inspection: only the owned contract, focused test, and this evidence changed; no `EXECUTION_STATE`, project file, runtime route, reducer, persisted field, database, fake data, or UI styling changes |

The correction3 validation runs also exposed a canonical-ID spelling mismatch
in the closed outer-navigation allowlist; it was corrected to the existing
`ar.recording-review` ID before the passing receipt above. A separate earlier
run hung in Xcode/CoreSimulator diagnostics while concurrent simulator work was
active; it was terminated as infrastructure-only and is not counted as a
product result. The final test emitted pre-existing Xcode warnings (including
device build-number metadata and an unprocessed `Circle.rcproject` folder);
none failed the focused target. The receipt is simulator
compilation/execution evidence only. It does not prove physical AR, recording
media integrity, backend quality, Photos integration, or end-to-end device
qualification; those belong to later milestone tasks.
