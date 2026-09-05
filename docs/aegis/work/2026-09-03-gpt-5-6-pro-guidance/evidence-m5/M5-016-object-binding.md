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

The review-correction pass keeps the parser object context collision-safe for
same-name markers, requires exact object-type agreement for explicit IDs and
aliases, and only converges marked plus detected observations when both have
finite world positions within the existing 0.20 m binding tolerance. Detection
bounding boxes, confidence, and world positions are validated before a candidate
is created; signed zero is normalized in its deterministic representation. The
generation path consumes the returned immutable parse output instead of the
mutable parser side channel. Storyboard beat edits validate the accepted binding
and its current request identity, or preserve the already planned identity before
any playback/model mutation; stale binding results fail before mutation.

The ViewModel publishes binding only for the current request identity. Any
missing or ambiguous physical reference transitions the existing request to
clarification before planning, AR placement, persistence, or success. Planner
calls receive no raw marked/detection arrays after binding, preventing the old
first-same-type fallback. Alias construction in the existing plan pipeline was
made collision-safe and duplicate marker hydration fails closed without
changing the persistence schema.

## Verification

All commands ran in the M5-016 worktree. Correction verification used the
permitted ordinary iPhone Air (`A6E7238C-B4C6-4988-B399-8E127CA8683B`). Earlier
baseline checks used the permitted ordinary iPhone 17e
(`1F680A42-CEB3-43E8-9CED-52F874962A62`). No physical device and no iPhone 17
Pro were used.

- `git diff --check` — passed.
- Review-correction focused attempt on iPhone 17e:

  ```text
  xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -derivedDataPath /private/tmp/m5-016-binding-dd -resultBundlePath /private/tmp/m5-016-binding-correction-focused.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingMatrixUsesExplicitIdentityAndTypedFailures -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingCanonicalIDsSurviveDetectionReloadRepresentation -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingDoesNotConvergeSpatiallyDistinctOrUnpositionedObservations -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsTypeMismatchedExplicitAndAliasCandidates -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsInvalidDetectionGeometryAndNormalizesSignedZero -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testUnresolvedObjectBindingStopsBeforeSceneCommitOrSuccess -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testRealGenerationPathStopsBeforeCommitForUnresolvedObjectBinding -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardManualEditChangesActionAndReplans -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardBeatEditFailsBeforeMutationWhenObjectIdentityIsUnavailable -only-testing:shafinMultitoolTests/SceneParserServiceTests/testSameNameMarkedObjectsAreCollisionSafeAndTypedAmbiguous -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testCompilerPreservesMarkedObjectIdentityAndSymbolicActors -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testAnchorExtractorFlagsSameTypeMarkerConflict
  ```

  Result bundle `/private/tmp/m5-016-binding-correction-focused.xcresult`:
  exit code 0 from xcodebuild, but the simulator runner reported `Busy /
  Application failed preflight checks`; 0 tests ran and the result summary was
  `passedTests: 0`, `failedTests: 1`, `skippedTests: 0`, `totalTestCount: 1`.
  This was an infrastructure failure before test execution, not a product
  assertion.

- The same correction matrix rerun on the permitted iPhone Air:

  ```text
  xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' -derivedDataPath /private/tmp/m5-016-binding-dd -resultBundlePath /private/tmp/m5-016-binding-correction-focused-air.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingMatrixUsesExplicitIdentityAndTypedFailures -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingCanonicalIDsSurviveDetectionReloadRepresentation -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingDoesNotConvergeSpatiallyDistinctOrUnpositionedObservations -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsTypeMismatchedExplicitAndAliasCandidates -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsInvalidDetectionGeometryAndNormalizesSignedZero -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingAliasesRemainScopedToSubmittedRequestSnapshot -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testUnresolvedObjectBindingStopsBeforeSceneCommitOrSuccess -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testRealGenerationPathStopsBeforeCommitForUnresolvedObjectBinding -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardManualEditChangesActionAndReplans -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardBeatEditFailsBeforeMutationWhenObjectIdentityIsUnavailable -only-testing:shafinMultitoolTests/SceneParserServiceTests/testSameNameMarkedObjectsAreCollisionSafeAndTypedAmbiguous -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testCompilerPreservesMarkedObjectIdentityAndSymbolicActors -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testAnchorExtractorFlagsSameTypeMarkerConflict
  ```

  Result bundle `/private/tmp/m5-016-binding-correction-focused-air.xcresult`:
  `passedTests: 12`, `failedTests: 0`, `skippedTests: 0`, `result: Passed`,
  `totalTestCount: 12`.

- Final correction matrix, including request-scoped alias isolation:

  ```text
  xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' -derivedDataPath /private/tmp/m5-016-binding-dd -resultBundlePath /private/tmp/m5-016-binding-correction-final.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingMatrixUsesExplicitIdentityAndTypedFailures -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingCanonicalIDsSurviveDetectionReloadRepresentation -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingDoesNotConvergeSpatiallyDistinctOrUnpositionedObservations -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsTypeMismatchedExplicitAndAliasCandidates -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsInvalidDetectionGeometryAndNormalizesSignedZero -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingAliasesRemainScopedToSubmittedRequestSnapshot -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testUnresolvedObjectBindingStopsBeforeSceneCommitOrSuccess -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testRealGenerationPathStopsBeforeCommitForUnresolvedObjectBinding -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardManualEditChangesActionAndReplans -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardBeatEditFailsBeforeMutationWhenObjectIdentityIsUnavailable -only-testing:shafinMultitoolTests/SceneParserServiceTests/testSameNameMarkedObjectsAreCollisionSafeAndTypedAmbiguous -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testCompilerPreservesMarkedObjectIdentityAndSymbolicActors -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testAnchorExtractorFlagsSameTypeMarkerConflict
  ```

  Result bundle `/private/tmp/m5-016-binding-correction-final.xcresult`:
  xcodebuild exit code 0; `passedTests: 13`, `failedTests: 0`,
  `skippedTests: 0`, `result: Passed`, `totalTestCount: 13` on iPhone Air.
  The 13 tests cover the manual/detected/alias/numbered/repeated/missing/
  ambiguous matrix, reload representation and duplicate-ID stability,
  colocated versus distinct marked+detected observations, type mismatch,
  invalid geometry and signed zero, request-scoped aliases, ViewModel stale
  publication and production zero-commit failure, storyboard success/failure
  mutation ordering, same-name parser collision safety, and two existing
  compiler/anchor-owner compatibility cases.

- Final identity-fencing rerun of the same 13 selectors (result path changed
  only to preserve the preceding bundle):

  ```text
  xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' -derivedDataPath /private/tmp/m5-016-binding-dd -resultBundlePath /private/tmp/m5-016-binding-correction-final2.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingMatrixUsesExplicitIdentityAndTypedFailures -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingCanonicalIDsSurviveDetectionReloadRepresentation -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingDoesNotConvergeSpatiallyDistinctOrUnpositionedObservations -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsTypeMismatchedExplicitAndAliasCandidates -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingRejectsInvalidDetectionGeometryAndNormalizesSignedZero -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testObjectBindingAliasesRemainScopedToSubmittedRequestSnapshot -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testUnresolvedObjectBindingStopsBeforeSceneCommitOrSuccess -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testRealGenerationPathStopsBeforeCommitForUnresolvedObjectBinding -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardManualEditChangesActionAndReplans -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testStoryboardBeatEditFailsBeforeMutationWhenObjectIdentityIsUnavailable -only-testing:shafinMultitoolTests/SceneParserServiceTests/testSameNameMarkedObjectsAreCollisionSafeAndTypedAmbiguous -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testCompilerPreservesMarkedObjectIdentityAndSymbolicActors -only-testing:shafinMultitoolTests/SceneV8PipelineTests/testAnchorExtractorFlagsSameTypeMarkerConflict
  ```

  Result bundle `/private/tmp/m5-016-binding-correction-final2.xcresult`:
  xcodebuild exit code 0; `passedTests: 13`, `failedTests: 0`,
  `skippedTests: 0`, `result: Passed`, `totalTestCount: 13` on iPhone Air.

- Baseline result bundles remain available for comparison:
  `/private/tmp/m5-016-binding-final3.xcresult` (3/3),
  `/private/tmp/m5-016-binding-existing.xcresult` (2/2), and the review
  correction rerun `/private/tmp/m5-016-binding-correction-focused-air.xcresult`
  (12/12). The pre-fencing 13-test bundle is
  `/private/tmp/m5-016-binding-correction-final.xcresult` (13/13).
- Final `git diff --check` — passed after the correction/evidence update.

## Limitations

Detector representation keys are stable for equivalent rounded label,
bounding-box, and world-position data; substantially changed observations are
new candidates by design. This slice does not implement M5-017 clarification
answer UI, compiler completeness, physical-device AR behavior, or release
readiness. The failed 17e correction attempt was a simulator preflight Busy
failure before tests and is superseded by the Air rerun. Existing unrelated
deprecation and Swift concurrency warnings remain outside this task.
