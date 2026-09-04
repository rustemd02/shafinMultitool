# M1-017 — Playback ownership and cancellation boundary

Task: Define one playback owner and cancellation boundary for route changes, artifact deletion,
and new recordings.
Owner boundary: `PlaybackOwner` (designated in runtime-ownership-map.md row 11).
Rollback: none required — no production code changed; ownership map row updated only.

## Designated ownership

| Playback kind | Owner | Cancellation boundary |
|---|---|---|
| Scene take playback (RealityKit entity animations, timeline timer, captions, screen text) | `SceneGeneratorViewModel` playback state machine (`isPlaying` + `currentPlaybackLogID`) | `cancelAllAnimations()`: cancels every tracked `DispatchWorkItem` in `animationWorkItems`, invalidates the timeline timer, stops all entity animations |
| Recorded-take review playback (AVPlayer) | `LegacySceneGeneratorCameraShell.recordingPlayer` | `releaseRecordingPlayer()` on `viewWillDisappear`(presented guard)/`viewDidDisappear`(dismiss/parent-move)/`deinit` pause |

## Trigger matrix (acceptance verification)

| Trigger | Path | Verified by |
|---|---|---|
| Route change | `deactivateAndWait`/`teardownAndWait` → `SceneWorkspaceTeardownCoordinator.stopPlaybackIfNeeded` → `stopScene()` → `cancelAllAnimations()` | SceneWorkspaceTeardownTests: testTeardownStopsRecordingAndPlaybackBeforePersistence, testTeardownAwaitsRecordingFinalizationBeforePlaybackAndPersistence, testConcurrentTeardownCallersShareOneOperation (16/16 PASS, M1-009 evidence) |
| App backgrounding | M1-004 adapter: shell → scenes route `handleDidEnterBackground` → awaited teardown (same stopPlaybackIfNeeded) | testRouteBackgroundHookUsesTheSameIdempotentWorkspaceTeardown |
| New recording take | mutual exclusion, not cancellation: `beginRecordingAfterMicrophonePermission` guards `!isPlaying`; `playScene` guards `!isRecording, !isRecordingFinalizing` — a take and a playback can never overlap | guard inspection (VM:4473, VM:1609) |
| Artifact deletion | artifact removal only exists via coordinated project deletion (M1-016): deletion rejected while the workspace lease is active; lease release requires teardown which stops playback first | ProjectLifecycleRegistryTests (M1-016 evidence) |
| Stale cues into next/stopped workspace (HAZ-03) | every playback DispatchWorkItem creation site appends to `animationWorkItems` (VM:1677, 2763, 2835, 2859, 4058, 4076, 4097, 4106) and closures double-guard `isPlaying`; `cancelAllAnimations` runs on playScene, stopScene, generation commit, and teardown | append-site sweep + existing suites |

## Conclusion

Acceptance ("playback stops/cancels on route change, artifact deletion, or a new take; stale
playback cues cannot affect a released workspace") is satisfied by the existing, already-tested
design. No production code change; the M1-017 deliverable is the formal PlaybackOwner
designation and this trigger-matrix evidence.
