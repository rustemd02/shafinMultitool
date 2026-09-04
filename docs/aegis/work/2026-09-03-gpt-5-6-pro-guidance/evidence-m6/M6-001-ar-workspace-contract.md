# M6-001 — AR Workspace product contract

Status: complete (contract-only)

Base: `6ecbb5acc8b3605d4ced5590ef0a0956363295a1`

Branch: `codex/set-os-m6-001`

Worktree: `/Users/unterlantas/.codex/worktrees/shafinMultitool/m6-001-ar-product-contract`

## Scope and architecture

M6-001 freezes the AR Workspace product contract as a thin, immutable,
non-owning projection over `SceneJourneyContract.production`. The projection
owns the ordered AR state identity set and typed policy declarations only.
State metadata and legal transitions are looked up from the existing
production journey; no reducer, copied transition graph, mutable runtime
state, ARSession wrapper, recorder, coordinator, feature flag, route change,
UI restyle, persistence migration, or runtime session rewiring was added.

The 17 canonical state IDs, in order, are:

```text
ar.preparing
ar.ready
ar.surface-search
ar.placement
ar.playback
ar.marking
ar.live-hints
ar.hint-pause
ar.hint-playback
ar.recording
ar.recording-review
ar.interruption
ar.error
ar.relocalization
ar.reset
ar.world-map-recovery
ar.teardown
```

The implementation is in
`shafinMultitool/SceneGeneratorModule/Models/SceneBundleContracts.swift`;
the focused contract checks are in
`shafinMultitoolTests/ARWorkspaceContractTests.swift`.

## Contract matrix

The `sources` and `artifacts` cells use the typed Swift enum case names from
`SceneJourneyContract.production`. Artifact notation is
`artifact=status/requirement`. `ID-ALL` is the canonical identity-fence
summary described below. Every row has the exact typed iPhone/iPad landscape
matrix, pending M6-002 runtime conformance, and deliberately absent physical
evidence.

| State ID | Current availability | Behavior owner | Typed inputs/sources | Artifacts/outputs | Persistence | Allowed transitions | Identity fence | Supported device/orientation | Runtime conformance | Physical evidence status |
|---|---|---|---|---|---|---|---|---|---|---|
| `ar.preparing` | pending | `SceneJourneyOwner.ar` | `workspaceGeneratedReady`, `arSession`, `plannedScene` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=optional`; `storyboard=optional` | `project` | `ar.ready`, `ar.surface-search`, `ar.relocalization`, `ar.error`, `ar.interruption`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.ready` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=optional` | `project` | `ar.surface-search`, `ar.relocalization`, `ar.reset`, `ar.preparing`, `ar.interruption`, `ar.error`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.surface-search` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=optional` | `project` | `ar.placement`, `ar.ready`, `ar.relocalization`, `ar.reset`, `ar.interruption`, `ar.error`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.placement` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=validated/required`; `storyboard=optional` | `project` | `ar.playback`, `ar.live-hints`, `storyboard.result`, `recording.preflight`, `ar.interruption`, `ar.error`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.playback` | pending | `SceneJourneyOwner.ar` | `workspacePreviewPlayback`, `arSession`, `plannedScene` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=validated/required`; `storyboard=optional` | `project` | `storyboard.result`, `ar.live-hints`, `recording.preflight`, `ar.placement`, `ar.interruption`, `ar.error`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.marking` | production | `SceneJourneyOwner.ar` | `workspaceMarking`, `arSession` | `project=promoted/required`; `arBindings=draft/required` | `project` | `sheet.marker-name`, `ar.placement`, `generator.input-marked-detected`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.live-hints` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `arBindings=validated/required`; `decisionTrace=optional` | `project` | `ar.hint-pause`, `ar.hint-playback`, `ar.placement`, `ar.interruption`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.hint-pause` | production | `SceneJourneyOwner.ar` | `workspaceShooting` | `project=promoted/required`; `arBindings=validated/required`; `decisionTrace=optional` | `project` | `ar.live-hints`, `ar.hint-playback`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.hint-playback` | production | `SceneJourneyOwner.ar` | `workspacePreviewPlayback`, `decisionTrace` | `project=promoted/required`; `decisionTrace=validated/required`; `arBindings=validated/required` | `project` | `ar.live-hints`, `ar.placement`, `ar.interruption`, `ar.teardown` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.recording` | pending | `SceneJourneyOwner.recording` | `workspaceRecording`, `recordingInProgress` | `project=promoted/required`; `arBindings=validated/required`; `recording=pending/required` | `artifact` | `recording.stopping`, `recording.failed`; interruption/teardown require the safe-stop edge first | `ID-ALL` + safe-stop fence | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.recording-review` | production | `SceneJourneyOwner.recordingStore` | `workspacePreviewPlayback`, `recordingCompleted`, `recordingArtifact` | `project=promoted/required`; `recording=promoted/required`; `recordingExport=optional` | `artifact` | `recording.playback`, `recording.share`, `recording.photos-exporting`, `storyboard.result`, `library.selected` | `ID-ALL` | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.interruption` | pending | `SceneJourneyOwner.ar` | `arSession`, `workspaceShooting`, `recordingInProgress` | `project=promoted/required`; `arBindings=missing/required`; `worldMap=optional`; `recording=pending/optional` | `project` | `ar.relocalization`, `ar.reset`, `ar.preparing`, `ar.error`, `ar.teardown` | `ID-ALL`; live anchors invalidated | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.error` | pending | `SceneJourneyOwner.ar` | `arSession` | `project=promoted/required`; `arBindings=missing/required`; `worldMap=optional`; `recording=missing/optional` | `project` | `ar.reset`, `ar.relocalization`, `ar.preparing`, `library.selected`, `ar.teardown` | `ID-ALL`; live anchors invalidated | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.relocalization` | pending | `SceneJourneyOwner.arRecovery` | `arRelocalization`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=pending/optional` | `project` | `ar.world-map-recovery`, `ar.ready`, `ar.reset`, `ar.error`, `ar.teardown` | `ID-ALL`; anchors revalidated after relocalization | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.reset` | pending | `SceneJourneyOwner.arRecovery` | `arReset`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=missing/required`; `worldMap=optional` | `project` | `ar.preparing`, `ar.relocalization`, `ar.world-map-recovery`, `ar.error`, `ar.teardown` | `ID-ALL`; live anchors invalidated | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.world-map-recovery` | pending | `SceneJourneyOwner.arRecovery` | `arWorldMapRecovery`, `arSession`, `scenePersistence` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=pending/required` | `project` | `ar.ready`, `ar.relocalization`, `ar.reset`, `ar.error`, `ar.teardown` | `ID-ALL`; map restore revalidates anchors | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |
| `ar.teardown` | production | `SceneJourneyOwner.ar` | `arSession`, `scenePersistence` | `project=promoted/required`; `arBindings=missing/required`; `recording=optional` | `project` | `library.selected` only, after teardown completes | `ID-ALL`; workspace/session/recording invalidated on release | iPhone/iPad: `landscapeLeft`, `landscapeRight` only | pending M6-002 | not run; fail closed |

## Typed ownership boundaries

`ARWorkspaceOwnershipContract` freezes one typed boundary for each role and
rejects duplicate roles or a second AR session owner:

| Role | Existing owner reference | M6-001 runtime status |
|---|---|---|
| workspace lifecycle | `SceneGeneratorViewModel + SceneWorkspaceTeardownCoordinator` | current |
| AR session lifecycle | `ARSceneContainer` / target ARSession owner boundary | pending M6-002 |
| presentation | CommercialShell routes + AR presentation | current |
| placement/anchors | SceneGeneratorViewModel placement/anchors owner | current |
| marking | SceneGeneratorViewModel marking owner | current |
| hints | SceneGeneratorViewModel live-hints owner | current |
| playback | SceneGeneratorViewModel + LegacySceneGeneratorCameraShell | current |
| recording | SceneRecordingController + RecordingLifecycleOwner | current |
| persistence | UnifiedSceneProject + existing world-map persistence owners | current |
| teardown | SceneWorkspaceTeardownCoordinator | current |

M6-001 records, but does not solve, the runtime sole-`ARSession` ownership
gap. M6-002 owns consolidation of the mutation paths below. Existing
CommercialShell routes, locked transitions, asynchronous teardown behavior,
and accessibility IDs remain unchanged.

## Current ARSession mutation sites

Required command:

```sh
rg -n 'session\.(run|pause)|session\.delegate' shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift
```

Actual output at the M6-001 verification baseline:

```text
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:31:        arView.session.delegate = context.coordinator
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:90:                uiView.session.pause()
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:91:                uiView.session.delegate = nil
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:111:        uiView.session.pause()
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:112:        uiView.session.delegate = nil
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:265:            arView.session.run(configuration)
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:274:            arView.session.pause()
shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:285:            arView.session.run(configuration)
shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift:1202:        arView.session.pause()
shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift:1203:        arView.session.delegate = nil
```

The sites are respectively the AR view delegate attachment, released-view
update cleanup, representable dismantling, coordinator configure/pause/resume
paths, and `SceneGeneratorViewModel.pauseAndDetachARSession()`. They are
reported as existing runtime debt; none was changed by M6-001.

## Identity and generation fences

`ARWorkspaceIdentityContract` declares the required typed identities:

- `workspace.id` is stable across frames and invalidated by teardown.
- `session.generation` is non-zero, rejects stale generations, and is
  invalidated by interruption, reset, and teardown; relocalization/map restore
  create a revalidation boundary.
- `project.id` is stable and remains the persistence identity.
- `planned-scene.id`, `entity.id`, `anchor.id`, `marker.id`, and `recording.id`
  are bound to the current session generation where transient AR identity is
  involved.
- Live anchors are invalidated by interruption and reset, then revalidated
  after relocalization or world-map restore. Stale-generation results are
  rejected before they can publish bindings, markers, hints, or recording
  artifacts.
- Teardown invalidates workspace/session/recording ownership after project
  persistence has completed; promoted project media is not implicitly deleted.

The validator fails closed for a missing or duplicate identity fence, a zero
generation, absent stale-generation rejection, un-fenced transient identities,
missing interruption/reset invalidation, or missing map-restore revalidation.

## Recording stop and teardown ordering

The contract preserves the required awaited sequence:

```text
stop recording (recording.stopping; await safe stop)
→ stop playback
→ persist project/world-map state
→ release recording owner/source
→ pause and detach AR session
→ terminal ar.teardown
→ navigate to library.selected only after terminal teardown completes
```

`ar.recording` has no direct transition to `ar.interruption` or `ar.teardown`.
Interruption and teardown requests first enter `recording.stopping`; only the
safe-stop outcome may continue to the requested recovery/teardown path. The
validator rejects a bypass, a reordered persist/release sequence, a
non-terminal teardown, or navigation that does not await terminal teardown.

## Fail-closed validation

`ARWorkspaceContract.validate()` / `validated()` reject:

- missing, duplicate, extra, or noncanonical AR state IDs;
- missing or empty typed metadata, missing production source rows, source-graph
  drift, transitions outside the production graph, or changed canonical exits;
- incomplete ownership roles or a second AR session-owner role;
- any orientation matrix other than exactly iPhone and iPad with
  `landscapeLeft` and `landscapeRight` supported and portrait/upside-down
  unsupported;
- enabling portrait before the declared `.deferredToM10010` policy;
- incomplete interruption/error/relocalization/reset/world-map recovery set;
- missing session-generation, stale-result, anchor, interruption/reset, or
  map-restore identity fencing;
- active-recording stop bypass, incorrect teardown order, nonterminal teardown,
  or non-awaited navigation; and
- claimed runtime or physical hardware conformance. Runtime sole-ARSession
  conformance remains explicitly `.pendingM6002`, and physical AR evidence is
  `.notRun` at this contract milestone.

## Orientation matrix

| Device class | Supported at M6-001 | Unsupported at M6-001 | Policy |
|---|---|---|---|
| iPhone | exactly `landscapeLeft`, `landscapeRight` | `portrait`, `portraitUpsideDown` | fixed landscape contract |
| iPad | exactly `landscapeLeft`, `landscapeRight` | `portrait`, `portraitUpsideDown` | iPad portrait/adaptive AR deferred to M10-010 |

The matrix is typed and immutable. No portrait or adaptive iPad support is
enabled early; no physical-device or simulator-derived ARKit readiness claim
is made.

## Verification receipt

All commands below were run from the owned worktree.

Focused verification command (exit code 0):

```sh
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:shafinMultitoolTests/ARWorkspaceContractTests -only-testing:shafinMultitoolTests/SceneJourneyContractTests -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -derivedDataPath /tmp/setos-m6-001/DerivedData -resultBundlePath /tmp/setos-m6-001/M6-001.xcresult CODE_SIGNING_ALLOWED=NO
```

Result summary:

```text
device: iPhone 17e, iOS Simulator, OS 26.5
passedTests: 30
failedTests: 0
skippedTests: 0
expectedFailures: 0
result: Passed
```

Suite counts: `ARWorkspaceContractTests` 8/8,
`SceneJourneyContractTests` 6/6, and `SceneWorkspaceTeardownTests` 16/16.

Result bundle: `/tmp/setos-m6-001/M6-001.xcresult`

Supplementary result command (exit code 0):

```sh
xcrun xcresulttool get test-results summary --path /tmp/setos-m6-001/M6-001.xcresult
```

The exact mutation-site `rg` command above exited 0 and returned the 10 lines
listed in the mutation-site section. `git diff --check` exited 0. The final
`git status --short` after the local checkpoint commit was empty.

## Scope audit and limitations

No Visual Policy, M1/M5 historical evidence, M12 scripts, Camera/Library
active files, thesis/litreview, History, Debug, Performance, Benchmark,
EXECUTION_STATE, route, UI, persistence migration, feature flag, ARSession
call, physical-device workflow, fake plane/anchor/readiness, timer success,
or simulator-derived hardware evidence was added or changed.

This milestone verifies the immutable contract and source graph on the
iPhone 17e simulator build. It does not claim physical ARKit tracking,
planes, anchors, world-map restoration, camera recording integrity, or sole
runtime ARSession ownership. Those remain runtime/conformance work for
M6-002 and later hardware evidence work.

Judgment calls: the source journey is injectable only as a validator test seam
so malformed graph input can be proven fail-closed; production construction
always defaults to `SceneJourneyContract.production`. No alternative owner or
state machine was introduced.
