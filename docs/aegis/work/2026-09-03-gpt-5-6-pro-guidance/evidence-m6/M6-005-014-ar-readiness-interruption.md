# M6-005 / M6-014 — AR readiness and interruption handling

Status: **integration verified on the current store; one M7-014 test added**.

## M6-005 — preparing/ready

Production readiness gate (`SceneGeneratorViewModel` frame path): ready is
set only from a real AR frame with detected planes while the session is not
interrupted — i.e. a running, supported configuration plus an initial valid
frame. Failure (`didFailWithError`), interruption (`sessionWasInterrupted`)
and interruption-ended all clear `isARSessionReady`; ended enters a
recovering state that only a subsequent real frame can promote. The
`testing*` helpers are explicit, named test seams and are never called from
production flows.

## M6-014 — AR interruption

`handleARSessionInterruption` (generation-fenced): clears planes/transforms
(stops new placements), clears hint presentation, stops scene playback,
stops an active recording through the single-flight
`requestStopRecording(.interruption)`, and preserves the persisted project
state untouched. Recovery is honest: `sessionInterruptionEnded` only marks
recovering; a real frame completes it. Reset remains the explicit route
exit. `ARSessionOwner` applies interruption safety once per generation
(`interruptionSafetyApplicationCount == 1`).

## M7-014 — interruption recovery for the recording

New controller test `testInterruptionStopsTakeOnceAndRecoveryCannotCreateHiddenClip`:
an interruption stop finalizes the partial take exactly once
(`stopCount == 1`), post-interruption frames are rejected by the closed
take fence, and recovery cannot start a hidden second take on the same
owner (a fresh take requires a new generation). The finalize itself is the
M7-012/M7-013 single-shot path, so the partial clip is a valid finalized
artifact or a typed failure with cleanup — never a silent partial.

## Verification

23/23 PASS on permitted iPhone 17e
(`/private/tmp/m7-014-verify.xcresult`): the new M7-014 test +
ARSessionOwnershipTests (6) + SceneWorkspaceTeardownTests (16).

## Honest boundary

Real ARKit interruption behavior (sensor suspension, relocalization) is
physical-device acceptance (M13); simulator work is contract evidence.
