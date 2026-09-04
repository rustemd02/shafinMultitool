# M1-001 Runtime Ownership Map (explicit behavior boundary)

Status: DESIGNATED by this doc. `*Owner` names below are behavior boundaries, not renames.
Existing generation fencing is adopted, not rewritten (CameraViewModel.generation,
AnalysisPipeline.lifecycleGeneration, SceneRecordingController snapshot.generation).

| # | Async resource | Sole owner type | Lifecycle state machine | Cancellation / release path |
|---|---|---|---|---|
| 1 | AVCapture session | `CameraManager` (CameraSessionOwner) | startAndWait/stopAndWait, session queue start/stop | `stopAndWait()` async; stale session callbacks fenced by generation (M1-003 hardens) |
| 2 | Camera route + analysis wiring | `CameraViewModel` (route-side session client) | start/startAndWait/stop/stopAndWait + FailedStartRollbackOperation(generation) | `stopAndWait()`; `CommercialCameraCoachRoute.deactivateAndWait()` → shared deactivationTask |
| 3 | Analysis frames/features | `AnalysisPipeline` (AnalysisPipelineOwner) | lifecycleGeneration; releaseTask/releaseInProgress; install*Task generation gates | generation check `isGenerationCurrent`; release op joins (M1-007 adds session boundary) |
| 4 | Lens replacement tx | `CameraSessionOwner` via CameraInputReplacementTransaction | single in-flight tx; rollback on failure | teardown-during-switch fence (M1-006) |
| 5 | ARSession + workspace | `SceneGeneratorViewModel` + `SceneWorkspaceTeardownCoordinator` (SceneWorkspaceOwner) | teardownAndWait → stopRec/stopPlay → persist snapshot → pauseAndDetach; .blocked retries, .released sets isWorkspaceReleased | idempotent teardownAndWait shared by 3 callers; route released only after AR/generation/playback/recording report released (M1-009) |
| 6 | Scene generation jobs | `SceneGeneratorViewModel` (SceneGenerationOwner) | request IDs + owner generation (M1-008) | cancel/retry/background fence; stale results dropped |
| 7 | Recording (video+audio+writer+timebase) | `SceneRecordingController` fronting `SerializedMediaRecorder` (RecordingOwner) | idle→…→completed/failed/cancelled single enum (M1-010); releaseTask joins stop callers | stop() joins one finalize op; late start after teardown cancelled (M1-011/012); stale-owner failures fenced by token+generation (M1-013) |
| 8 | Pending→final promotion | `RecordingArtifactStore` (MediaLifecycleOwner fs boundary) + in-memory dedup in ViewModel | makePendingURL → promoteFinalizedArtifact (renameatx_np RENAME_EXCL, idempotent) | retries cannot duplicate; failure never deletes source (M1-014) |
| 9 | Project mutation | `DBService` behind `SceneGeneratorViewModel` snapshot coalescing (PersistenceOwner) | projectSnapshotTask coalescing; persist-before/after world-map capture | overlapping ops serialized; conflict → recoverable error (M1-015) |
| 10 | Project deletion | `ProjectLifecycleOwner` (DBService + artifact store + route) | reject while ownership unreleasable; atomic-from-user delete | coordinated with workspace/job/recorder/playback (M1-016) |
| 11 | Playback | PlaybackOwner (M1-017): SceneGeneratorViewModel playback state machine (RealityKit takes; cancelAllAnimations boundary) + LegacySceneGeneratorCameraShell recordingPlayer (AVPlayer review) | one active playback; stops via teardown stopPlaybackIfNeeded before media delete/route release | all DispatchWorkItems tracked in animationWorkItems + cancelled + isPlaying double-guard; recording/playback mutually exclusive; artifact deletion only via coordinated project deletion (M1-016) |
| 12 | Shell routes/modals | `CommercialShellViewController` (NavigationOwner role) + `CommercialSceneLibraryRoute` specialization | performTransition (await old deactivateAndWait; blocked retains) / performRelease (shared releaseTask) | presented-modal → .blocked before workspace teardown (M1-019) |
| 13 | App/scene lifecycle events | LifecycleCoordinatorOwner: SceneDelegate → shell → active route only (M1-004) | each event forwarded exactly once | no duplicated recheck/teardown |
| 14 | Permissions | PermissionOwner coordinator (M1-005; today scattered clients) | coalesced concurrent requests; single completion | owner cancellation cannot publish stale state |
| 15 | Errors → UI | ErrorPresentationOwner typed taxonomy (M1-018) | every failure → localized recoverable state with request/generation context | stale errors fail generation checks; no raw framework strings |
| 16 | Memory/retention | MemorySafetyOwner audit (M1-020); pixel buffers bounded | weak/unowned/cancel ownership; deinit sentinels | — |

Rules: one owner per resource; stale callback with mismatched generation/token is dropped;
route visible while teardown blocked; Camera and AR camera owners never concurrent (shell precondition).
