# M6-019 — AR teardown evidence

Status: CLOSED on the current store (verify-and-close; no production
change).

## Acceptance → existing proof (SceneWorkspaceTeardownTests, 16 tests)

- "Concurrent teardown callers await one operation":
  `testConcurrentTeardownCallersShareOneOperation`,
  `testConcurrentPersistenceFailureCallersShareAttemptAndLaterRetry`,
  `testConcurrentProjectSnapshotsShareCaptureAndPersistLatestState`.
- "Release occurs only after all owners are terminal" (owner order
  recording → playback → persistence → release → detach):
  `testTeardownStopsRecordingAndPlaybackBeforePersistence`,
  `testTeardownAwaitsRecordingFinalizationBeforePlaybackAndPersistence`,
  `testTeardownAwaitsPersistenceBeforeTerminalRecordingReleaseAndDetach`.
- World-map capture inside the awaited teardown with exactly-once
  resume and late-callback immunity (M6-016 integration):
  `testWorldMapCaptureTimeoutResumesExactlyOnceAndIgnoresLateCallback`,
  `testWorldMapCaptureCancellationResumesExactlyOnceAndIgnoresLateCallback`,
  `testWorldMapTimeoutUnblocksTeardownAndLateCallbackCannotOverwriteRetry`.
- "Blocked result names the owner" + retry semantics:
  `testPersistenceFailureCanRetryAndDetachExactlyOnce`,
  `testTeardownCancelsGenerationAndPersistsExistingSceneOnce`.
- Route integration (background hook idempotence, awaited workspace
  before camera construction, failure retains route, presented-modal
  block): `testRouteBackgroundHookUsesTheSameIdempotentWorkspaceTeardown`,
  `testSceneRouteAwaitsInjectedWorkspaceBeforeConstructingCamera`,
  `testSceneWorkspaceFailureRetainsRouteAndDoesNotConstructCamera`,
  `testPresentedSceneModalBlocksWithoutStartingWorkspaceTeardown`.

The M7-015 background lease wraps the same idempotent teardown
(one UIKit lease per background event), and M6-015 proved the
background/foreground policy on top of it.

## Boundary

Physical interruption/thermal teardown timing remains M13.
