# M5-001 Scene journey contract

## Scope

`SceneJourneyContract.production` in `SceneBundleContracts.swift` is a
projection-only catalog for the fixed production journey:

`Library → Generator → AR → Storyboard → recording → Library`.

It enumerates 24 stable, unique states. Each state has a typed owner, entry
condition, primary action, recovery, exit, persistence effect, downstream
artifact list, and allowed next states. The source vocabulary is explicitly
mapped to `SETLibraryModel.FlowState`, `SceneGenerationStage`,
`SceneWorkspaceMode`, `RecordingLifecycleState`, `SceneScript`, and
`PlannedScene`.

## Ownership and persistence boundary

The contract does not own state, routes, persistence, or artifacts. Existing
owners remain authoritative. `SceneScript` is the validated generator result;
`PlannedScene` is the AR/Storyboard compilation result; project and recording
references are downstream links. Draft states are not project commits, and
recording review requires an owned regular file before it can return to the
library.

## Verification receipt

| Check | Result |
|---|---|
| `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:shafinMultitoolTests/SceneJourneyContractTests -derivedDataPath /private/tmp/shafin-m5-001-derived-3 -resultBundlePath /private/tmp/shafin-m5-001-3.xcresult CODE_SIGNING_ALLOWED=NO` | PASS; one test passed; `** TEST SUCCEEDED **` |
| `git diff --check` | PASS |
| unique IDs/completeness/owner/persistence/artifact assertions | PASS in `SceneJourneyContractTests` |
| forbidden shortcut scan | PASS by inspection: no routes, fake data, persisted fields, UI styling, database, `EXECUTION_STATE`, or `project.pbxproj` changes |

The test is simulator compilation/execution evidence only. It does not prove
physical AR, recording media integrity, backend quality, or end-to-end device
qualification; those belong to later milestone tasks.
