# M5-014 — Scene Generator request state machine

## Scope and owner

`SceneGeneratorViewModel` now owns one `SceneGenerationRequestState` for each
generation draft/request. The state is defined in
`SceneExecutionRuntimeContracts.swift`; `SceneChunkState.swift` was not
changed. Existing `isGenerating` and `generationStage` remain published for
compatibility, but are projections written only by the state publisher.

The state has stable `Codable`/`Equatable` payloads: phase, request UUID/epoch
identity where applicable, generation stage, typed failure kind, and a
clarification message. Editable `input`, `idle`, and the pre-request
`emptyInput` terminal validation state are identityless. Every post-submit
state—including every retryable or terminal failure—requires both request UUID
and epoch. Identity is checked alongside the existing `generationEpoch` fence
before every async publication.

## Contract and transitions

The finite phase vocabulary is:

`idle`, `input`, `validating`, `clarification`, `accepted`, `leader`,
`queued`, `generating`, `cancelling`, `paused`, `backgrounded`,
`retryableFailure`, `terminalFailure`, and `success`.

`SceneGenerationRequestState.transitionTable` is closed. `canTransition` /
`validateTransition` reject malformed payloads, mismatched request IDs or
epochs, and phases not listed in the table. `transition` returns no new state
for a rejected edge, so the ViewModel projections and domain state remain
unchanged. Same-phase updates are intentionally limited to editable `input`
and monotonic `generating` stage updates (`reading → planning → placing`),
plus idempotent `cancelling`. Teardown has an explicit owner-side idle
retirement escape only after a cancellation publication is rejected, so an
in-flight projection cannot remain active during release.
Codable round trips and every phase-pair in the matrix are covered by tests.
The independent matrix oracle constructs a well-formed payload pair for every
listed edge, rejects every well-formed variant of each distinct unlisted pair,
and checks same-state updates separately. The impossible `input →
retryableFailure` edge is intentionally absent.

`emptyInput` and `parse` are terminal/edit-required categories. Missing AR
readiness and camera position are retryable because the request can be
resubmitted after the environment recovers. User-facing copy remains the
existing localized generator copy; parser/transport diagnostics are not
inserted into that copy.

## Request traces and commit boundary

- New/loaded nonempty drafts enter `input`; submit creates a fresh UUID and
  epoch, then publishes `validating`.
- The current local request handoff publishes `accepted → queued → leader →
  generating(reading)`. These are state seams only; no backend queue, leader
  job, motion, or progress implementation was added.
- Parsing fallback/status updates, planning, and placing all publish through
  the owner. Parser clarification enters `clarification` and stops the local
  request rather than appearing as a generic terminal error.
- The success edge is published only after the existing model/AR replacement
  commit, `placeObjectsInAR`, and the synchronous metadata persistence handoff
  has been reached. This records ordering only; durable-save failure
  classification remains deferred to M5-022. A teardown epoch bump and request
  identity check prevent a cancelled or stale task from publishing success.
- Teardown publishes `cancelling` for an in-flight request, awaits the existing
  generation task, then returns the owner to `idle`. Existing background route
  teardown therefore remains cancellation/release behavior; background
  recovery is represented but intentionally deferred.

## Honest deferrals

M5-014 does not implement screenplay answer submission, accepted/leader
presentation effects, backend progress, network/retry policies, cancellation
inside parser/backend work, background recovery, chunk checkpointing, or the
distinct M5-022 error producers/localization. Future failure cases present in
the typed contract are classification-only and have no producers in this
slice. The existing bundle parser path currently returns accept/fallback
runtime traces; the test-only clarification seam exercises the owner’s typed
clarification edge without inventing parser reachability that belongs to
M5-017.

## Verification

Correction-pass verification used the permitted ordinary iPhone 17e
(`1F680A42-CEB3-43E8-9CED-52F874962A62`) because iPhone Air was unhealthy with
CoreSimulator Data Migration failure. No physical device or iPhone 17 Pro was
used.

- `git diff --check` — passed after the final graph/oracle correction.
- The exact seven-test command was:
  `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Debug -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -skip-testing:shafinMultitoolUITests -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testSceneGenerationRequestStateTransitionMatrixIsExhaustive -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testSceneGenerationRequestStateRejectsInvalidAndStaleIdentityTransitions -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testSceneGeneratorInputValidationIsScopedAndWhitespaceAware -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testSceneGeneratorPublishesReadingPlanningPlacingAndSuccessTrace -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testSceneGeneratorMapsMissingCameraTransformToRetryableState -only-testing:shafinMultitoolTests/SceneBundlePipelineTests/testSceneGeneratorClarificationTraceIsTypedAndNotTerminalError -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests/testTeardownCancelsGenerationAndPersistsExistingSceneOnce CODE_SIGNING_ALLOWED=NO`
  — `7 tests, 0 failures`, `** TEST SUCCEEDED **`; log:
  `/tmp/m5-014-final-seven-tests.log`; result:
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-bondejhxobdlpuespzxromfxnwgh/Logs/Test/Test-shafinMultitool-2026.09.05_16-38-56-+0300.xcresult`.
- The transition-matrix test was rerun independently after the final graph and
  oracle correction: `1 test, 0 failures`; log:
  `/tmp/m5-014-final-matrix.log`; result:
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-bondejhxobdlpuespzxromfxnwgh/Logs/Test/Test-shafinMultitool-2026.09.05_16-38-29-+0300.xcresult`.
- The prior correction-pass seven-test run (`/tmp/m5-014-correction-seven-tests.log`)
  is superseded: it failed only because its literal oracle still listed
  removed direct-to-idle edges. The next corrected run passed, and the final
  run above passes with the concrete-payload oracle.
- Earlier pre-correction Air artifacts are retained as superseded baseline
  evidence, not as proof of the corrected code. The earlier Air clarification
  launch was blocked by `NSMachErrorDomain -308`; the ordinary iPhone 17e
  runs above supersede that runner gap.
