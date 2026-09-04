# M6-001 — AR Workspace product contract (correction)

Status: complete (contract-only correction)

Base: `6ecbb5acc8b3605d4ced5590ef0a0956363295a1`

Branch: `codex/set-os-m6-001`

Worktree: `/Users/unterlantas/.codex/worktrees/shafinMultitool/m6-001-ar-product-contract`

## Correction record

The prior attempt was integrated by the parent at `a058731` and verified at
`/tmp/setos-root-m6-001.xcresult`. That prior root result was green on the
ordinary iPhone 17e simulator: 30 passed, 0 failed.

The prior implementation was reconsidered because its 772-line AR addition
duplicated a schema/validator surface around the existing journey. This
correction replaces that surface from the prior local commit `9df6d52` with
the smallest honest projection:

- `ARWorkspaceContract.states` is the exact ordered 17-state list.
- `state(_:)` resolves every row directly through
  `SceneJourneyContract.production.state(_:)`.
- `allows(_:_:)` rejects non-AR origins before delegating the existing
  production graph; legal non-AR destinations remain available where that
  graph permits them.
- Orientation, ownership, identity, runtime-status, and teardown are compact
  immutable constants. There is no injected journey, copied graph, materialized
  per-row policy, compatibility alias, violation taxonomy, reducer, wrapper,
  service, or runtime mutation.
- Evidence joins the canonical state rows with global constants below instead
  of storing an AR evidence row for each state.

The production M6-001 section is now 332 lines versus 772 lines in the prior
commit: 440 fewer lines (57.0% reduction). The first correction diff was 522
deleted and 82 added production lines. The focused test file was 217 lines
versus 242 previously.

The follow-up reviewer found that the compact projection still retained
tautological ownership clauses, a recovery-subset check implied by the exact
state list, and generic per-row field validation already owned by
`SceneJourneyContract`. The second correction removes those 22 production
lines. It also makes the focused tests independent specification oracles: all
10 role-to-owner mappings and all 8 identity/fence rule sets are declared as
literal expected values rather than compared with production constants. The
current production section is 310 lines (462 fewer than the original 772,
59.8% reduction), and the focused test file is 288 lines.

## Canonical state matrix

The following display table is read from the existing typed
`SceneJourneyContract.production` rows. Artifact notation is
`artifact=status/requirement`. Global identity, orientation, runtime, and
physical-evidence policy is intentionally declared once after the table.

| State ID | Current availability | Behavior owner | Typed inputs/sources | Artifacts/outputs | Persistence | Allowed transitions |
|---|---|---|---|---|---|---|
| `ar.preparing` | pending | `SceneJourneyOwner.ar` | `workspaceGeneratedReady`, `arSession`, `plannedScene` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=optional`; `storyboard=optional` | `project` | `ar.ready`, `ar.surface-search`, `ar.relocalization`, `ar.error`, `ar.interruption`, `ar.teardown` |
| `ar.ready` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=optional` | `project` | `ar.surface-search`, `ar.relocalization`, `ar.reset`, `ar.preparing`, `ar.interruption`, `ar.error`, `ar.teardown` |
| `ar.surface-search` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=optional` | `project` | `ar.placement`, `ar.ready`, `ar.relocalization`, `ar.reset`, `ar.interruption`, `ar.error`, `ar.teardown` |
| `ar.placement` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=validated/required`; `storyboard=optional` | `project` | `ar.playback`, `ar.live-hints`, `storyboard.result`, `recording.preflight`, `ar.interruption`, `ar.error`, `ar.teardown` |
| `ar.playback` | pending | `SceneJourneyOwner.ar` | `workspacePreviewPlayback`, `arSession`, `plannedScene` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=validated/required`; `storyboard=optional` | `project` | `storyboard.result`, `ar.live-hints`, `recording.preflight`, `ar.placement`, `ar.interruption`, `ar.error`, `ar.teardown` |
| `ar.marking` | production | `SceneJourneyOwner.ar` | `workspaceMarking`, `arSession` | `project=promoted/required`; `arBindings=draft/required` | `project` | `sheet.marker-name`, `ar.placement`, `generator.input-marked-detected`, `ar.teardown` |
| `ar.live-hints` | pending | `SceneJourneyOwner.ar` | `workspaceShooting`, `arSession` | `project=promoted/required`; `arBindings=validated/required`; `decisionTrace=optional` | `project` | `ar.hint-pause`, `ar.hint-playback`, `ar.placement`, `ar.interruption`, `ar.teardown` |
| `ar.hint-pause` | production | `SceneJourneyOwner.ar` | `workspaceShooting` | `project=promoted/required`; `arBindings=validated/required`; `decisionTrace=optional` | `project` | `ar.live-hints`, `ar.hint-playback`, `ar.teardown` |
| `ar.hint-playback` | production | `SceneJourneyOwner.ar` | `workspacePreviewPlayback`, `decisionTrace` | `project=promoted/required`; `decisionTrace=validated/required`; `arBindings=validated/required` | `project` | `ar.live-hints`, `ar.placement`, `ar.interruption`, `ar.teardown` |
| `ar.recording` | pending | `SceneJourneyOwner.recording` | `workspaceRecording`, `recordingInProgress` | `project=promoted/required`; `arBindings=validated/required`; `recording=pending/required` | `artifact` | `recording.stopping`, `recording.failed`; interruption/teardown require safe-stop first |
| `ar.recording-review` | production | `SceneJourneyOwner.recordingStore` | `workspacePreviewPlayback`, `recordingCompleted`, `recordingArtifact` | `project=promoted/required`; `recording=promoted/required`; `recordingExport=optional` | `artifact` | `recording.playback`, `recording.share`, `recording.photos-exporting`, `storyboard.result`, `library.selected` |
| `ar.interruption` | pending | `SceneJourneyOwner.ar` | `arSession`, `workspaceShooting`, `recordingInProgress` | `project=promoted/required`; `arBindings=missing/required`; `worldMap=optional`; `recording=pending/optional` | `project` | `ar.relocalization`, `ar.reset`, `ar.preparing`, `ar.error`, `ar.teardown` |
| `ar.error` | pending | `SceneJourneyOwner.ar` | `arSession` | `project=promoted/required`; `arBindings=missing/required`; `worldMap=optional`; `recording=missing/optional` | `project` | `ar.reset`, `ar.relocalization`, `ar.preparing`, `library.selected`, `ar.teardown` |
| `ar.relocalization` | pending | `SceneJourneyOwner.arRecovery` | `arRelocalization`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=pending/optional` | `project` | `ar.world-map-recovery`, `ar.ready`, `ar.reset`, `ar.error`, `ar.teardown` |
| `ar.reset` | pending | `SceneJourneyOwner.arRecovery` | `arReset`, `arSession` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=missing/required`; `worldMap=optional` | `project` | `ar.preparing`, `ar.relocalization`, `ar.world-map-recovery`, `ar.error`, `ar.teardown` |
| `ar.world-map-recovery` | pending | `SceneJourneyOwner.arRecovery` | `arWorldMapRecovery`, `arSession`, `scenePersistence` | `project=promoted/required`; `plannedScene=validated/required`; `arBindings=pending/required`; `worldMap=pending/required` | `project` | `ar.ready`, `ar.relocalization`, `ar.reset`, `ar.error`, `ar.teardown` |
| `ar.teardown` | production | `SceneJourneyOwner.ar` | `arSession`, `scenePersistence` | `project=promoted/required`; `arBindings=missing/required`; `recording=optional` | `project` | `library.selected` only, after terminal teardown completes |

## Global immutable constants

### Ownership

`ARWorkspaceOwnershipContract` requires these exact role-to-owner mappings;
validation compares the complete mapping, so swapping any owner fails:

| Role | Existing typed owner |
|---|---|
| workspace lifecycle | `SceneGeneratorViewModel + SceneWorkspaceTeardownCoordinator` |
| AR session lifecycle | `ARSceneContainer` target boundary |
| presentation | CommercialShell routes + AR presentation |
| placement/anchors | SceneGeneratorViewModel placement/anchors owner |
| marking | SceneGeneratorViewModel marking owner |
| hints | SceneGeneratorViewModel live-hints owner |
| playback | SceneGeneratorViewModel + LegacySceneGeneratorCameraShell playback owners |
| recording | SceneRecordingController + RecordingLifecycleOwner |
| persistence | UnifiedSceneProject + existing world-map persistence owners |
| teardown | SceneWorkspaceTeardownCoordinator |

There is exactly one AR-session owner target, and its runtime conformance is
`pendingM6002` (pending M6-002 sole-`ARSession` ownership). No runtime
ownership was changed by this correction.

### Identity and generation fences

`ARWorkspaceIdentityContract` requires these exact immutable fence entries:

| Identity | Required rules |
|---|---|
| `workspace.id` | stable across frames; invalidated by teardown |
| `session.generation` | stable; reject stale generation; invalidated by interruption/reset/teardown; revalidated after relocalization/map restore |
| `project.id` | stable across frames |
| `planned-scene.id` | stable; bound to session generation; invalidated by reset; revalidated after map restore |
| `entity.id` | stable; bound to session generation; invalidated by reset; revalidated after map restore |
| `anchor.id` | stable; bound to session generation; invalidated by interruption/reset; revalidated after relocalization/map restore |
| `marker.id` | stable; bound to session generation; invalidated by reset; revalidated after map restore |
| `recording.id` | stable; bound to session generation; invalidated by interruption/teardown |

Removing an identity entry or rule makes the contract invalid. This records
stale-generation rejection, interruption/reset invalidation, and
relocalization/world-map revalidation without pretending to implement those
runtime operations.

### Orientation and evidence status

| Device | Supported orientations | Unsupported orientations |
|---|---|---|
| iPhone | exactly `landscapeLeft`, `landscapeRight` | `portrait`, `portraitUpsideDown` |
| iPad | exactly `landscapeLeft`, `landscapeRight` | `portrait`, `portraitUpsideDown` |

iPad portrait/adaptive AR remains deferred to M10-010. Runtime sole-session
conformance is pending M6-002. Physical AR evidence is not run at M6-001;
there is no physical-device or simulator-derived hardware claim.

### Teardown and recording stop

The immutable teardown order is:

~~~text
stop recording (safe-stop to recording.stopping; await)
→ stop playback
→ persist project/world-map state
→ release recording owner/source
→ pause and detach AR session
→ terminal ar.teardown
→ navigate to library.selected only after terminal teardown completes
~~~

The validator reads the canonical `recordingInProgress` row directly. It
requires the recover edge to `recording.stopping` with the safe-stop trigger
and rejects any direct active-recording edge to `ar.interruption` or
`ar.teardown`. It also requires the exact teardown order, terminal state,
terminal destination, and awaited navigation flag.

## Existing ARSession mutation sites

Required search:

~~~sh
rg -n 'session\.(run|pause)|session\.delegate' shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift
~~~

Actual output (unchanged by M6-001):

~~~text
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
~~~

These remain current runtime mutation sites: delegate attachment, released-view
cleanup, representable dismantling, coordinator configure/pause/resume, and
`SceneGeneratorViewModel.pauseAndDetachARSession()`. M6-002 owns consolidation.

## Verification receipt

The parent integration prior attempt was:

~~~text
commit: a058731/root
result: /tmp/setos-root-m6-001.xcresult
iPhone 17e simulator, 30 passed, 0 failed
~~~

Correction verification (fresh unique result path, exit code 0):

~~~sh
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:shafinMultitoolTests/ARWorkspaceContractTests -only-testing:shafinMultitoolTests/SceneJourneyContractTests -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -derivedDataPath /tmp/setos-m6-001-correction-v2/DerivedData -resultBundlePath /tmp/setos-m6-001-correction-v2/M6-001-correction.xcresult CODE_SIGNING_ALLOWED=NO
~~~

Result summary:

~~~text
device: iPhone 17e, iOS Simulator, OS 26.5
passedTests: 31
failedTests: 0
skippedTests: 0
expectedFailures: 0
result: Passed
~~~

Suite counts: `ARWorkspaceContractTests` 9/9,
`SceneJourneyContractTests` 6/6, and `SceneWorkspaceTeardownTests` 16/16.

Result bundle: `/tmp/setos-m6-001-correction-v2/M6-001-correction.xcresult`

Supplementary summary command (exit code 0):

~~~sh
xcrun xcresulttool get test-results summary --path /tmp/setos-m6-001-correction-v2/M6-001-correction.xcresult
~~~

`git diff --check` exited 0. The final `git status --short` after the
first correction commit was empty.

Second correction verification (fresh unique result path, exit code 0):

~~~sh
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:shafinMultitoolTests/ARWorkspaceContractTests -only-testing:shafinMultitoolTests/SceneJourneyContractTests -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -derivedDataPath /tmp/setos-m6-001-correction-v3/DerivedData -resultBundlePath /tmp/setos-m6-001-correction-v3/M6-001-correction.xcresult CODE_SIGNING_ALLOWED=NO
~~~

Result summary:

~~~text
device: iPhone 17e, iOS Simulator, OS 26.5
passedTests: 31
failedTests: 0
skippedTests: 0
expectedFailures: 0
result: Passed
~~~

Suite counts: `ARWorkspaceContractTests` 9/9,
`SceneJourneyContractTests` 6/6, and `SceneWorkspaceTeardownTests` 16/16.

Result bundle: `/tmp/setos-m6-001-correction-v3/M6-001-correction.xcresult`

Supplementary summary command (exit code 0):

~~~sh
xcrun xcresulttool get test-results summary --path /tmp/setos-m6-001-correction-v3/M6-001-correction.xcresult
~~~

`git diff --check` exited 0 before the second correction commit; the final
post-commit check and clean status are reported with the correction commit.

## Scope audit and limitations

Changed only the three owned paths: the compact contract in
`SceneBundleContracts.swift`, its focused tests, and this evidence file. No
ARSession call, runtime owner, route, UI, persistence migration, feature flag,
Visual Policy, M1/M5 historical evidence, protected thesis/litreview material,
EXECUTION_STATE, physical-device workflow, fake plane/anchor/readiness, timer
success, or simulator-derived hardware evidence was changed or added.

This correction verifies contract shape, canonical metadata, graph delegation,
orientation constants, owner/identity/teardown constants, and safe-stop
constraints on the iPhone 17e simulator build. It does not claim physical
ARKit tracking, planes, anchors, world-map restoration, camera recording
integrity, or sole runtime `ARSession` ownership. The latter remains the
explicit M6-002 follow-up.
