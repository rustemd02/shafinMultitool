# M5-016 — Canonical object binding

## Scope and contract

The generator now snapshots marked objects and detections at submit time under
the existing request UUID/epoch. `SceneObjectBindingResult` carries one typed
resolution per submitted `SceneObject`: `bound`, `missing`, or `ambiguous`.
Bound metadata includes a stable canonical ID, source (`marked`, `detected`,
or `virtual`), confidence, name, aliases, and physical position/provenance
when available. Existing `SceneObject` persistence fields and marker short-ID
format remain unchanged.

Marked IDs remain `object_marked_<short-id>`. DETR UUIDs are observation IDs and
are not used as reload-stable entity IDs; detector candidate keys use stable
label/geometry/position representation data, then a successful submitted
object is keyed by its immutable `SceneObject` reference. Conflicting aliases,
duplicate canonical IDs, repeated same-type candidates, and repeated candidate
reuse fail closed with typed ambiguity/missing diagnostics. Parser aliases are
lookup hints only and cannot replace a submitted physical candidate.

The ViewModel publishes binding only for the current request identity. Any
missing or ambiguous physical reference transitions the existing request to
clarification before planning, AR placement, persistence, or success. Planner
calls receive no raw marked/detection arrays after binding, preventing the old
first-same-type fallback. Alias construction in the existing plan pipeline was
made collision-safe and duplicate marker hydration fails closed without
changing the persistence schema.

## Verification

All commands ran in the M5-016 worktree. The only simulator destination was the
permitted ordinary iPhone 17e (`1F680A42-CEB3-43E8-9CED-52F874962A62`). No
physical device and no iPhone 17 Pro were used.

- `git diff --check` — passed.
- Focused command:

  ```text
  xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -derivedDataPath /private/tmp/m5-016-binding-dd -resultBundlePath /private/tmp/m5-016-binding-final3.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingMatrixUsesExplicitIdentityAndTypedFailures -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingCanonicalIDsSurviveDetectionReloadRepresentation -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testUnresolvedObjectBindingStopsBeforeSceneCommitOrSuccess
  ```

  Result: exit code 0; 3 tests passed, 0 failed, 0 skipped. Result bundle:
  `/private/tmp/m5-016-binding-final3.xcresult`. The matrix covers a manual
  marker, detection, marker alias, repeated same-type detections, numbered
  markers with reversed input order, missing and ambiguous references,
  detected+marked convergence, no duplicate candidate IDs, and a parser alias
  pointing at a virtual ref while a physical detection is available. The
  reload case uses different detector UUIDs for identical observations and
  proves the canonical candidate/result identity remains stable while
  observation provenance changes. The ViewModel case rejects a stale request
  result and proves unresolved binding reaches clarification without a scene
  commit or success publication.
- `xcrun xcresulttool get test-results summary --path /private/tmp/m5-016-binding-final3.xcresult` — reports `passedTests: 3`, `failedTests: 0`,
  `skippedTests: 0`, `result: Passed`, `totalTestCount: 3`.
- Existing-owner compatibility checks used the same derived data path:
  `xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -derivedDataPath /private/tmp/m5-016-binding-dd -resultBundlePath /private/tmp/m5-016-binding-existing.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testCompilerPreservesMarkedObjectIdentityAndSymbolicActors -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testAnchorExtractorFlagsSameTypeMarkerConflict` — 2 tests passed, 0 failed, 0 skipped. Result bundle: `/private/tmp/m5-016-binding-existing.xcresult`.

## Limitations

Detector representation keys are stable for equivalent rounded label,
bounding-box, and world-position data; substantially changed observations are
new candidates by design. This slice does not implement M5-017 clarification
answer UI, compiler completeness, physical-device AR behavior, or release
readiness. Existing unrelated deprecation and Swift concurrency warnings remain
outside this task.
