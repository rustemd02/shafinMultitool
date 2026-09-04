# M1-006 — Lens replacement transaction fencing

Task: Fence lens replacement transactions against route teardown, repeated selection, and stale
AVCapture callbacks.
Owner boundary: `CameraSessionOwner`. No production change required — the fencing design is
complete and all three acceptance test categories exist and ran green this session.

## Mechanism

| Concern | Device |
|---|---|
| At most one transaction mutates the session | `CameraViewModel.switchLens` cancels the prior `lensSwitchTask` before starting a new one (single in-flight transaction); CameraManager serializes `switchLensAndWait` on its session queue behind the M1-003 session-generation fence (stale ops post-release rejected) |
| Stale completion cannot alter selected lens | reported-lens confirmation flow: only the newest confirmed result publishes; older completions are fenced by the operation identity (haptic fires only after successful physical change) |
| Released session cannot be resumed | release resets lens presentation and fences late completion; session generation bumps on stop/release |
| Failure rollback | `CameraInputReplacementTransaction.perform()`: remove old → canAdd(new)? add : (canAdd(old)? restore : .rollbackFailed) — no input is ever added without a preceding approval |

## Coverage (all executed green this session)

Overlapping switch: testNewestConfirmedLensWinsWhenOlderCompletionArrivesLate,
testRequestedLensWaitsForConfirmedSuccess, testNoOpPublishesReportedActiveLens.
Failure rollback: testRollbackFailureClearsPresentationAndSynchronizesManagerLifecycle,
testUnavailableAndReplacementRejectedKeepReportedActiveLens,
CameraLensSwitchTransactionTests 4/4 (rejected-restore, rollback-failure, remove-once invariant).
Teardown-during-switch: testReleaseResetsLensPresentationAndFencesLateCompletion.
Session-level fencing: CameraManagerLifecycleTests 18/18 (M1-003 evidence).

## Acceptance

At most one lens transaction mutates the session; stale completion cannot alter the selected lens
or resume a released session; overlapping switch, failure rollback, and teardown-during-switch
tests exist and pass — satisfied. No production change.
