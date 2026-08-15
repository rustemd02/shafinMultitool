# Privacy, permissions, transmitted-data and stored-data inventory

Task: CC-003
Evidence snapshot: `HEAD faf3e12abd6443877c7e5072fd67c878cce68553` (`store`, detached worktree)
Scope: executable production Swift, app configuration, tests, and included dependency evidence. No source, project, permission timing, copy, storage, network, telemetry, or runtime behavior was changed by this audit.

## Reading rules and authority

- Product authority is `docs/app-store-product-plan.md`. It describes the intended `coach-first, local-first, server-deep` boundary, but it does not establish a provider, processor region, retention term, legal basis, tracking declaration, or final App Privacy answer.
- Execution authority is CC-003 in `docs/implementation/BACKLOG.md`; `docs/implementation/STATUS.md` records the current known gaps.
- “Observed” below means a symbol, path, configuration value, or test was found in the repository. “Unknown” means the repository does not establish it. Unknowns are not filled with legal or commercial assumptions.
- The normal launch path currently remains `SceneDelegate` → `SOModuleBuilder` → scene overview. Camera Coach is not the default product route according to `STATUS.md`; reachable legacy, modern, and benchmark paths are inventoried separately.

## Executive disposition

| Capability or data path | Current executable disposition | Main gap | Candidate follow-up owner |
| --- | --- | --- | --- |
| Camera / AR camera | Three production camera/session paths exist: AR scene, legacy `CameraService`, and modern `CameraManager`. | No app-owned authorization/status gate, permission-specific denied/restricted state, settings route, or permission test. | CC-009 audit; CC-010 implementation; `ARSceneContainer.Coordinator`, `CameraService`, and `CameraManager` are the exact owners to reconcile. |
| Microphone | `CameraService` activates an audio session and captures AAC samples for a `.mov`; Speech also consumes `AVAudioEngine` input. | No `recordPermission`/request flow; audio setup uses `try?`; no denied/restricted/retry UX. | CC-008 state specification; CC-009/CC-010 camera foundation; `CameraService` and `SpeechRecognitionService`. |
| Speech | `SFSpeechRecognizer(locale: "ru-RU")` is called from the legacy dialogue flow. | No Speech authorization request/status handling or user recovery path. | CC-008; `SpeechRecognitionService` with `CameraScreenInteractor` as trigger owner. |
| Photos | Recording completion writes the resulting video to the Photos library. | No authorization/status branch, read path, user result state, retry, or settings route. | CC-008; `CameraService.saveVideoToLibrary`. |
| Remote VLM evidence | Only an environment-configured `URLSession` POST provider can transmit; absent provider/endpoint returns `provider_unavailable`. | Provider, endpoint policy, consent boundary, payload approval, region, retention, and user-facing failure state are open. | Sol/privacy boundary, then CC-012; `VisualSemanticEvidenceCoordinator` and `RemoteVLMVisualEvidenceProvider`. |
| Deep Critic offloading | Contract and coordinator exist, with strong policy checks, but no production provider/caller was found. | Must not be treated as a live transmission path until a production owner is introduced. | Sol/privacy boundary; future CC-012/implementation packet. |
| Telemetry and analytics | Formal camera telemetry is in memory; performance diagnostics write a local Documents file; benchmark artifacts write local Caches files. No analytics SDK or telemetry URL was found. | No approved event schema, consent boundary, destination, retention, or raw-media/identifier policy. | CC-012 after CC-003/CC-008; `Telemetry`, `DiagnosticsLogger`, and benchmark owner. |
| Identifiers | UUIDs are used for local projects, frames, registrations, requests, cues, and benchmark runs. No vendor, advertising, install, Keychain, or DeviceCheck identifier API was found. | Correlation semantics and any future account/install binding remain open. | CC-012; do not add a hidden identifier by implication. |
| Privacy manifest | No `PrivacyInfo.xcprivacy` or other `.xcprivacy` file exists in the repository. | Required-Reason API and dependency review is incomplete; no declaration is selected here. | CC-011 release gates; CC-004 dependency audit. |

## Runtime and owner map

### Normal and reachable camera routes

1. `shafinMultitool/Resources/SceneDelegate.swift:15-34` creates `SOModuleBuilder` for the normal launch. `ScenesOverviewModule/SORouter.swift:18-35` can push `SceneGeneratorView`.
2. `SceneGeneratorModule/Views/SceneGeneratorView.swift:20-31` owns the SwiftUI lifecycle and embeds `LegacySceneGeneratorCameraShell`.
3. `SceneGeneratorModule/Views/LegacySceneGeneratorCameraShell.swift:111-120` embeds `ARSceneContainer`.
4. `SceneGeneratorModule/Views/ARSceneContainer.swift:19-34, 138-175` creates/configures `ARView` and calls `arView.session.run(configuration)` without an authorization preflight. `:202-242` forwards `ARFrame.capturedImage` to `SceneGeneratorViewModel`; `:249-254` converts any AR failure to the generic `"Ошибка AR: ..."` message.
5. `SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift:650-667` creates `ARWorldTrackingConfiguration`; `:577-625` sends captured frames to local analysis and recording; `:3403-3456` owns recording start/stop and error strings.
6. The legacy `SceneModules/CameraScreenModule` remains production source. `CameraScreenViewController.swift:91-101` calls `prepareRecorder()` and starts the AR view; `CameraScreenInteractor.swift:463-486` calls `arView.session.run(configuration)`.
7. The modern camera graph is `Multitool2Module/ContentView.swift:14-35` → `CameraManager` + `AnalysisPipeline` + `OverlayView`. `OverlayView.swift:19-23, 154-169` owns preview appearance and calls `CameraViewModel.start/stop`; `CameraManager.swift:62-71, 94-132` owns the `AVCaptureSession`.
8. `SceneDelegate` has a separate environment-gated benchmark route (`DEVICE_BENCHMARK_CONFIG_BASE64`) at `:20-24`; benchmark artifacts are handled by `Benchmark/DeviceBenchmarkCoordinator.swift` and `DeviceBenchmarkSupport.swift`.

The modern and legacy/AR routes are not silently collapsed in this inventory. Selecting one canonical owner is the purpose of CC-009, not an assumption made here.

## Permission inventory

### Camera and AR camera access

**Exact triggers and purpose**

- AR route: `ARSceneContainer.makeUIView` calls `updateSessionState`; `Coordinator.configureSessionIfNeeded` calls `ARSession.run` at `ARSceneContainer.swift:166-175`. `ARSessionDelegate.session(_:didUpdate:)` at `:202-242` exposes camera frames to the local scene generator. This happens when the scene camera shell is created, before recording is necessarily requested.
- Legacy recording route: `CameraScreenViewController.viewDidLoad` at `:91-101` calls `CameraService.prepareRecorder`; `CameraService.prepareRecorder` at `Services/CameraService.swift:55-104` creates `AVCaptureSession`, obtains `AVCaptureDevice.default(for: .video)`, and prepares an `AVAssetWriter`.
- Modern live route: `OverlayView.onAppear` at `Multitool2Module/UI/Overlay/OverlayView.swift:154-169` calls `CameraViewModel.start`; `CameraManager.start` at `Multitool2Module/Services/Camera/CameraManager.swift:62-71` configures and starts the session. `:94-142` discovers back-camera lenses, adds a device input and video output; `:189-208` turns sample buffers into local `FrameContext` values.

**Current behavior and UX**

- Authorized/usable behavior is the underlying ARKit/AVFoundation session path described above; frames feed local Vision/Core ML/analysis code. No camera frame file is written by `CameraManager` or `ARSceneContainer` itself.
- The app does not call `AVCaptureDevice.authorizationStatus`, `AVCaptureDevice.requestAccess`, or an equivalent app-owned camera preflight. There is no app-owned `denied` or `restricted` branch.
- `CameraManager.configureSession` returns after a failed device/input guard (`:102-107`) but publishes no permission-specific error. `ARSceneContainer` has a generic AR failure callback, not a permission classification, retry action, or Settings link.
- The legacy route has no permission-specific failure/retry/settings state. Recording exposes `SceneGeneratorViewModel`’s generic `"Не удалось подготовить запись"` at `:3411-3419` if the recorder is not prepared; the cause is not classified.
- No `UIApplication.openSettingsURLString`, `UIApplication.shared.open`, or permission-specific retry symbol was found in production Swift. There is no pre-permission explanation screen.

**Current usage copy**

The app target’s Debug and Release build settings in `shafinMultitool.xcodeproj/project.pbxproj:512-515,546-549` define:

> `Для съёмки видео "Шафин Мульитул" необходимы права на использование камеры`

The source `shafinMultitool/Info.plist:5-24` contains only the scene manifest; usage keys are generated from the project settings. The spelling and the video-specific framing are recorded as evidence, not corrected by this task.

**Denied/restricted/unavailable disposition**

| State | Observed app behavior | Missing executable state |
| --- | --- | --- |
| Not determined | No explicit request timing or rationale is owned by the app. Underlying framework behavior is not independently asserted. | Preflight, rationale, and request-result state. |
| Authorized | Session can run and frames can be consumed by local analysis/recording. | Explicit success state/metrics are not defined. |
| Denied | No app-owned status branch; modern input guard can return silently and AR can report only generic failure. | Explain, retry, and Settings recovery. |
| Restricted | No app-owned status branch found. | Explain and non-camera fallback. |
| Hardware/unavailable | `AVCaptureDevice`/input guard returns without a published reason; the target requires ARKit in build settings. | Distinguish unsupported hardware from privacy denial. |

**Tests and manifest/API impact**

- No production or test match exists for camera authorization/status/request symbols. Existing tests do not exercise authorized, denied, restricted, interrupted, or unavailable camera sessions on a device.
- The usage description key is present in both app configurations. No `PrivacyInfo.xcprivacy` exists. This audit does not select a privacy-manifest declaration or make an App Store compliance claim; the API/SDK Required-Reason review remains a CC-011/CC-004 follow-up.

**Exact owner candidate**: `ARSceneContainer.Coordinator` + `SceneGeneratorViewModel` for the current AR session lifecycle; `CameraManager` for the modern `AVCaptureSession`; `CameraService` and `CameraScreenInteractor` for the legacy recorder. CC-009 must select the canonical boundary before CC-010 changes behavior.

### Microphone and recorded audio

**Exact triggers and purpose**

- `CameraService.prepareRecorder` at `Services/CameraService.swift:55-104` obtains `AVAudioSession.sharedInstance()`, calls `setCategory(.playAndRecord)` and `setActive(true)`, creates an audio `AVCaptureSession`, adds the default audio device/input/output, and starts the session asynchronously.
- `CameraService.videoSettingsUpdate` at `:141-156` creates a one-channel, 48 kHz AAC `AVAssetWriterInput`. `captureOutput(_:didOutput:from:)` at `:230-255` appends audio sample buffers while recording.
- `CameraService.stopRecording` at `:168-191` finishes the audio/video writer and then calls `saveVideoToLibrary`. `SceneGeneratorViewModel.startRecording` at `:3411-3428` is the user-facing recording trigger for the modern scene shell; the legacy `CameraScreenViewController` prepares the recorder during `viewDidLoad`.
- Speech separately uses `AVAudioEngine` in `Services/SpeechRecognitionService.swift:14-51`; that audio is appended to `SFSpeechAudioBufferRecognitionRequest`, not to the video writer.

**Current behavior and UX**

- `CameraService` calls `try?` for audio category/activation and does not call `AVAudioSession.recordPermission`, `requestRecordPermission`, or an equivalent request API.
- `isRecorderPrepared` at `:103` checks writer/video/adaptor state but does not explicitly require a configured audio input. Audio failure can therefore collapse into generic recorder failure or a recording without a classified audio reason; the repository does not provide a more specific outcome.
- There is no microphone rationale, denied/restricted view, retry, or Settings route. The only configured copy is:

> `Для съёмки видео "Шафин Мульитул" необходимы права на запись звука с микрофона`

**State disposition**

- Not determined/authorized/denied/restricted: no app-owned status/request branch was found; underlying framework behavior is not treated as a product state.
- Failure: setup errors are ignored for category/activation and the recording owner eventually exposes only `"Не удалось подготовить запись"` when preparation is false.
- Retry/fallback: `stopRecording` re-prepares the recorder after finishing, but this is not a permission recovery flow and has no user-facing explanation.

**Tests and manifest/API impact**

- No microphone permission tests, audio-input failure tests, or recording-without-audio tests were found. `README_TESTS.md` lists CameraService tests as future work.
- `NSMicrophoneUsageDescription` is present in Debug/Release build settings. No privacy manifest exists; Required-Reason/dependency analysis remains open.

**Exact owner candidate**: `CameraService` for recorded audio and `SpeechRecognitionService` for recognition input, with `SceneGeneratorViewModel`/`CameraScreenInteractor` owning user-trigger timing after CC-008.

### Speech recognition

**Exact trigger, purpose, and data**

- `Services/SpeechRecognitionService.swift:14-23` creates `AVAudioEngine` and `SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))`.
- The user-facing legacy dialogue path is `CameraScreenViewController.swift:845` → `CameraScreenPresenter.swift:76-78` → `CameraScreenInteractor.swift:693-717` → `SpeechRecognitionService.recognise`.
- The service installs an audio tap at `:47-54`, appends buffers to `SFSpeechAudioBufferRecognitionRequest`, and returns `bestTranscription.formattedString` to the interactor. The interactor compares the last words with the scripted phrase at `:719-753`, advances the dialogue, and stops after the six-second work item at `:756-766`.

**Current behavior and UX**

- No `SFSpeechRecognizer.requestAuthorization`, `SFSpeechRecognizer.authorizationStatus`, or app-owned Speech permission state was found.
- Recognition errors are printed at `SpeechRecognitionService.swift:60-65` and stop the recognition task; there is no user-facing error, denied/restricted copy, retry, or Settings route.
- The configured usage string is:

> `Для распознавания речи сценария "Шафин Мультитул" необходимы права на отправку звука на сервера Apple`

This is current product configuration text only. The app source does not independently establish a processor, region, retention term, or final external-service behavior; this audit does not infer any of them from the sentence.

**State, tests, and manifest/API impact**

- Not determined/authorized/denied/restricted: no app-owned branch.
- Failure/timeout: internal task cleanup and a console error; phrase matching simply does not advance when no result arrives.
- No Speech authorization or audio-buffer test exists. The existing unit test topology has no permission UI target; `README_TESTS.md` recommends a future SpeechRecognitionService test.
- `NSSpeechRecognitionUsageDescription` is present in Debug/Release settings. No privacy manifest exists; Required-Reason/API and App Privacy review remain open.

**Exact owner candidate**: `SpeechRecognitionService` for authorization and recognition lifecycle; `CameraScreenInteractor.startDialogueRecogniotion` for the user-triggered phrase-matching flow.

### Photos library write

**Exact trigger, purpose, and fields**

- `CameraService.stopRecording` finishes the `.mov` at `Services/CameraService.swift:181-190`, then calls `saveVideoToLibrary`.
- `CameraService.saveVideoToLibrary` at `:376-385` calls `PHPhotoLibrary.shared().performChanges` with `PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:)`.
- The source file is created by `getVideoFileURL` at `:389-397` in the app Documents directory as `video_yyyy-MM-dd_HH-mm-ss.mov`. The writer contains HEVC video (`:124-139`) and optional AAC audio (`:141-147`).
- No Photos read API was found. The only Photos operation is the video creation request.

**Current behavior and UX**

- The configured copy is:

> `Для съёмки видео "Шафин Мульитул" необходимы права на сохранение файлов в галерею`

- There is no `PHPhotoLibrary.authorizationStatus`, `PHPhotoLibrary.requestAuthorization`, or equivalent preflight.
- Completion only prints `"Video saved to library!"` or `"Error saving video to library: ..."`; it does not update the view model, show a result, offer retry, or open Settings.
- Denied/restricted behavior is therefore an unclassified completion error. The source Documents file is not removed in this owner after a failed save; a separate retention/cleanup policy is not evidenced.

**Tests and manifest/API impact**

- No Photos authorization, save success, save denial, restricted-library, or cleanup test was found.
- `NSPhotoLibraryAddUsageDescription` is present; `NSPhotoLibraryUsageDescription` is not present in the project search. No privacy manifest exists. This audit does not decide whether a read permission is product-required.

**Exact owner candidate**: `CameraService.saveVideoToLibrary`, with `SceneGeneratorViewModel.stopRecording` as the UI state integration point after CC-008.

## Transmitted and stored data inventory

### Live camera frames and local analysis

- `ARSceneContainer.Coordinator.session(_:didUpdate:)` forwards `capturedImage` only when recording or hints are enabled (`ARSceneContainer.swift:202-242`). `SceneGeneratorViewModel.processARFrameSnapshot` (`:577-625`) sends it to local analysis and to `CameraService.appendCapturedPixelBuffer` during recording.
- `CameraManager.captureOutput` (`Multitool2Module/Services/Camera/CameraManager.swift:189-208`) creates a `FrameContext` with pixel buffer, timestamp, orientation, stability, shake level, and motion state for `RealtimeScheduler`/`AnalysisPipeline`.
- These owners do not write the live pixel buffer to a local file or call a network client. Local Vision/Core ML analysis is not a transmission path.
- A redacted visual may be represented in the VLM request only when both environment flags select it; the builder uses metadata (`redacted://<frame>`, 768 px, EXIF stripped, redaction applied) rather than encoding the raw pixel buffer in `VLMVisualEvidenceRequest`.
- Candidate owner: `ARSceneContainer`/`SceneGeneratorViewModel` for AR capture and `CameraManager`/`AnalysisPipeline` for the modern pipeline. Canonical ownership remains CC-009.

### Recorded video and audio

- `CameraService` writes HEVC/AAC `.mov` data to Documents (`video_*.mov`) through `AVAssetWriter`; audio sample buffers are captured by `AVCaptureAudioDataOutput`.
- On stop, the same file is passed to Photos. The repository does not define a retention term, deletion-after-export rule, backup behavior, encryption decision, or failed-save cleanup policy. Those are open decisions, not inferred facts.
- Candidate owner: `CameraService` for file creation and export; `SceneGeneratorViewModel` for recording UI/state.

### Speech audio and transcript

- `AVAudioEngine` buffers flow into `SFSpeechAudioBufferRecognitionRequest`; the returned transcript string is used in memory by `CameraScreenInteractor` for phrase matching.
- No app-owned audio file or transcript database write was found in the Speech path. The configured usage string mentions Apple servers, but source inspection cannot establish processor/region/retention details.
- Candidate owner: `SpeechRecognitionService` and `CameraScreenInteractor`.

### Legacy scene files and unified scene projects

`Services/DBService.swift` has two Documents-backed stores:

- Legacy `Documents/Scenes/<scene>_map` stores an archived `ARWorldMap`; `<scene>_data` stores JSON `SceneData` (`name`, `actors`, optional `script`) at `DBService.swift:33-44`.
- Unified `Documents/UnifiedSceneProjects/<UUID>_project.json` stores `UnifiedSceneProject` and `<UUID>_worldmap` stores the archived map at `DBService.swift:150-165`. `Entity/SceneData.swift:49-83` shows fields: project UUID/name/timestamps, `sceneDescription`, `markedObjects`, `parsedScript`, `plannedScene`, `sceneChunkState`, and `visualOverlays`.
- `SceneGeneratorViewModel.persistProjectSnapshot` at `:3656-3676` saves metadata and the current AR world map on workspace/recording lifecycle events.
- These files can contain user-entered scene descriptions, object/actor names, script/dialogue text, generated scene structure, overlay metadata, timestamps, and AR spatial/world-map data. No network call is attached to `DBService`.
- Deletion methods exist (`DBService.swift:88-106,190-211`), but no global retention policy or automatic cleanup policy is defined.
- Candidate owner: `DBService` plus `SceneGeneratorViewModel` persistence triggers.

### UserDefaults

Observed keys and owners:

- Camera settings: `resolutionWidth`, `resolutionHeight`, `resolutionDescription`, `framerate`, `whiteBalance`, `iso`, `speedMultiplier` in `DBService.swift:22-30`, `CameraScreenInteractor.swift:237-409`, and `LegacySceneGeneratorCameraShell.swift:492-565`.
- Scene generator flags/budgets: `scene_generator_v9_patch_retry_enabled`, `scene_generator_v9_runtime_mode`, `scene_generator_v9_enabled`, `scene_generator_v9_max_rows`, `scene_generator_v9_max_actors`, `scene_generator_v9_max_objects`, `scene_generator_v9_max_beats`, `scene_generator_v9_chunk_budget_ms` in `SceneParserService.swift:36-254` and `SceneBundlePipeline.swift:2491-3177`.
- Scene generator model/runtime overrides: `scene_generator_llm_model_path`, `device_benchmark_scene_runtime_gpu_layers`, `device_benchmark_scene_runtime_threads`, `device_benchmark_scene_runtime_context_tokens` in `LLMParserService.swift:16-25,218,2314`, `LlamaContext.swift:189-206`, and `DeviceBenchmarkCoordinator.swift:588-616`.
- LiDAR marking flag: `scene_generator_lidar_marking_enabled` in `SceneGeneratorViewModel.swift:646-665`.

The observed values are settings, feature flags, model paths, runtime budgets, and camera controls; no password, token, Keychain item, or device identifier is stored through these calls. They are persistent local defaults, so their retention/deletion behavior is the platform defaults behavior rather than an app-defined privacy policy. The product plan still requires a Required-Reason API review; this document does not choose a declaration.

### Formal telemetry and diagnostics

**In-memory telemetry** — `Multitool2Module/Services/Telemetry/Telemetry.swift:24-163` exposes `DebugMetrics` (`DebugOverlay.swift:10-21`): UI FPS, pipeline FPS, thermal state, battery level, heavy-models flag, latency map, camera-stable flag, shake level, active module names, and aesthetic score. `Telemetry` also counts frames and UI frames in memory. It uses `OSLog` but all formal metric state is `@Published` in memory; no URLSession, event queue, file writer, analytics SDK, consent toggle, or retention setting is present.

**OSLog/console diagnostics** — `Telemetry.recordSuggestion` would log suggestion text/type but is disabled by `CameraLog.suggestions = false`; `AnalysisPipeline` has debug `print`/`os_log` paths that can expose frame IDs, subject/object labels, confidence, regions/bounding boxes, selected hint/action, verdict/plan scores, reasons, latencies, and provider/fallback diagnostics. `SceneGeneratorDiagnosticsLogger` is explicitly console-only (`SceneGeneratorDiagnosticsLogger.swift:15-22`), but callers log AR state and scene-generator diagnostics; the console destination and OS logging retention are not an app-owned retention contract.

**Local performance log** — `Services/PerformanceMonitor.swift:145-173` aggregates FPS, frame time, CPU, memory, thermal state, GPU estimate, dropped frames, Vision latency, Speech latency, and overlay latency and calls `DiagnosticsLogger`. `Services/DiagnosticsLogger.swift:20-67` appends those formatted metrics to `Documents/preproduction-perf.log`. No cleanup, export, network upload, consent, or retention term is defined.

**Disposition**: this is local diagnostics/benchmark data, not an observed analytics provider. Before product analytics, CC-012 must define event names/properties, consent and disclosure boundary, destination, retention/deletion, and a no-raw-media/no-hidden-identifier rule. Candidate owners are `Telemetry`, `DiagnosticsLogger`, and the benchmark owner; no production analytics SDK was found.

### Device benchmark artifacts

- `DeviceBenchmarkArtifactStore` at `Benchmark/DeviceBenchmarkSupport.swift:306-489` writes JSON/JSONL/string artifacts under `Library/Caches/DeviceBenchmark/<runId>/`.
- Run IDs are generated as `device-benchmark-<UUID>` (`:92-114`). `deviceBenchmarkSnapshot()` (`:651-665`) stores timestamp, model identifier, system name/version, battery level, thermal state, app version, and build number. Performance samples store timestamps, module/phase/mode/note, FPS/frame time, dropped frames, CPU, memory, battery, thermal state, stage latencies, and optional notes (`:150-164,573-593`). Scene benchmark results/checkpoints can include source lengths, parsing results, document state, diagnostics, and text-derived scene artifacts; exact files are written by `DeviceBenchmarkCoordinator.swift:346-405,679-795,927-958`.
- The benchmark route is environment-gated by `DEVICE_BENCHMARK_CONFIG_BASE64` in `SceneDelegate.swift:20-24`. No benchmark network client was found. Caches are local, but no app-defined cleanup/retention contract is present.
- The model identifier and generated run UUID are benchmark metadata, not evidence of an install/device tracking identifier. Candidate owner: `DeviceBenchmarkCoordinator`/`DeviceBenchmarkArtifactStore`; release inclusion and privacy disposition belong to CC-001/CC-004/CC-011.

### Remote VLM visual evidence transport

**Exact configuration and destination evidence**

- `VisualSemanticEvidenceProviderFactory.makeDefaultProvider` at `Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift:16-30` selects `mock`, `remote`, or no provider from `CAMERA_VLM_VISUAL_EVIDENCE_PROVIDER`. The normal default is no provider when the variable is absent or unknown.
- `RemoteVLMVisualEvidenceProvider.makeFromEnvironment` at `:230-241` reads `CAMERA_VLM_VISUAL_EVIDENCE_ENDPOINT` and optional `CAMERA_VLM_VISUAL_EVIDENCE_API_KEY`; no literal provider URL or region is in source.
- `fetchVisualEvidence` at `:243-259` sends a JSON `POST` via `URLSession` with `Content-Type`/`Accept: application/json`, optional `Authorization: Bearer <api key>`, and the encoded request body. It accepts only HTTP 2xx and decodes `VLMVisualEvidenceResponse`.

**Request fields observable from the production builder**

`AnalysisPipeline.swift:8652-8723` creates a pause-only request containing:

- `schemaVersion`, `requestId` (`vlm_evd_<frameId>_<epoch-ms>`), `frameId`, `mode`, `locale`, `privacyTier`, and `trigger`;
- default `structuredOnly` privacy tier, or `redactedVisual` only when `CAMERA_VLM_VISUAL_EVIDENCE_ALLOW_VISUAL_INPUT` is enabled and `CAMERA_VLM_VISUAL_EVIDENCE_PRIVACY_TIER=redactedVisual`;
- optional visual metadata: `attachmentKind=redactedStill`, `mediaRef=redacted://<frameId>`, `longEdgePx=768`, `exifStripped=true`, `redactionApplied=true`, and `redactionNotes=[subject_only_redacted_still]`;
- `localContext`: frame-feature excerpt (`mode`, subject kind, subject-area ratio, edge pressure, backlight index, object count), scene semantics, critique, recommendation plan, semantic tip drafts, grounded entities, and local neural-evidence summary;
- `allowedCatalog`, constraints, and correlation (`localCritiqueSummaryId`, `localPlanSummaryId`, `semanticCatalogVersion`, `offloadingSchemaVersion=h12`, `providerConfigVersion`, and `sessionEphemeralId=pause-<frameId>`).

The source does not encode the raw pixel buffer in this request builder. The redacted visual value is metadata that a future/provider implementation may interpret; the configured endpoint and actual receiver are not identified in the repository.

**Timing, consent boundary, and failure behavior**

- `resolvePauseVisualEvidence` at `AnalysisPipeline.swift:8652-8665` is called for pause visual evidence. `VisualSemanticEvidenceCoordinator.fetchEvidence` at `:49-136` validates pause mode/request/policy, then returns `skipped(provider_unavailable|policy_blocked)`, `accepted`, `rejected`, or `failed` (`canceled_due_to_state_change`, `timeout`, or `runtime_error`). There is no retry loop in this coordinator.
- The request builder labels the redacted-visual trigger `.explicitUserRequest`, but the builder derives it from environment configuration; no UI call site proving a user consent action was found. This does not satisfy or disprove the product plan’s intended explicit-user-action boundary; it is an implementation gap for the owner to resolve.
- No provider, processor region, retention, account binding, cost, or legal basis is observable. No response persistence was found in the provider/coordinator. User-facing presentation of remote failure/consent is not established by these owners.
- Candidate owner: `VisualSemanticEvidenceCoordinator`/`RemoteVLMVisualEvidenceProvider` for transport and policy; Sol/CC-008/CC-012 for product consent and disclosure.

### Deep Critic offloading contract (not a live production transport)

- `Multitool2Module/Services/Offloading/DeepCriticOffloadingCoordinator.swift:102-210` defines a request/envelope carrying request/frame IDs, mode, locale, trigger, privacy tier, local scene/critique/plan/neural evidence/trace fields, constraints, and an optional visual attachment with MIME/dimensions/redaction/EXIF/payload data fields.
- `DeepCriticPolicyContext` and `makeTransportEnvelope` at `:114-131,535-658` gate feature enabled, pause mode, local bundle readiness, network availability, background-remote permission, positive trigger, provider capability, explicit user request, visual consent, visual size (maximum long edge 1,024 px), EXIF removal, and non-empty payload for redacted visuals.
- Exhaustive production call-site search found only the protocol/coordinator definitions and `MockDeepCriticProvider`; no production provider, URLSession implementation, or call to `offload` was found. `DeepCriticOffloadingCoordinatorTests` exercise the contract with mocks. Therefore no current Deep Critic payload is claimed to leave the device.
- Candidate owner: future offloading implementation after Sol approves the privacy/data boundary; do not treat this contract as a provider, region, retention, or legal decision.

## Identifiers and security-sensitive stores

- Negative production searches found no `identifierForVendor`, `advertisingIdentifier`, `ASIdentifierManager`, `DeviceCheck`, `Keychain`, `SecItem`, `kSec`, or equivalent identifier/storage API.
- UUIDs are present for local project IDs (`Entity/SceneData.swift:49-83`), scheduler registrations (`RealtimeScheduler.swift:57-60`), frame/request/pause tokens (`AnalysisPipeline.swift:3391-3394`, `SceneGeneratorViewModel.swift:3350-3354`), UI/model entities, and benchmark run IDs. These are process/local-domain correlation values; no code path maps them to a device/install identity.
- VLM `requestId`, `frameId`, and `sessionEphemeralId` can correlate a pause request and its local diagnostics. Their privacy/retention semantics are not finalized. No hidden identifier should be added under CC-012.
- UserDefaults contains configuration and benchmark/model override values listed above; no secret or credential storage was found. The remote VLM API key is read from the process environment and placed in an Authorization header when configured; the repository does not show how that environment value is provisioned or retained.

## Privacy manifest, usage descriptions, and dependency impact

### App configuration

- `shafinMultitool.xcodeproj/project.pbxproj:510-515,544-549` sets `GENERATE_INFOPLIST_FILE=YES`, points to `shafinMultitool/Info.plist`, and supplies camera, microphone, Photos-add, and Speech usage strings for Debug and Release.
- `shafinMultitool/Info.plist` itself has no usage keys beyond the scene manifest because the keys are generated by build settings. `NSPhotoLibraryUsageDescription` was not found.
- `find . -type f \( -name 'PrivacyInfo.xcprivacy' -o -name '*.xcprivacy' \) -print` returned no files. `rg` found no `NSPrivacy...` manifest content in app-owned source/configuration.
- Product-plan gates at `docs/app-store-product-plan.md:592-595` require a privacy manifest/Required-Reason and dependency audit, full permission flow, policy, and precise App Privacy answers. This artifact records the gap; it does not declare compliance or choose entries.

### Included dependencies

- `Podfile`/`Podfile.lock` include `ARVideoKit 1.5.51` and `SnapKit 5.6.0`. No app-owned `import ARVideoKit`, `RecordAR`, or ARVideoKit runtime call was found.
- ARVideoKit source contains its own microphone permission call (`Pods/ARVideoKit/ARVideoKit/Sources/RecordAR.swift:713-717` and related `WritAR.swift` code) and README usage-description guidance. This is dependency evidence, not proof that the app invokes that code. CC-004/CC-011 must determine whether the linked dependency contributes privacy/API obligations.
- SnapKit matches only UI layout usage in this audit. No Firebase, Sentry, Crashlytics, Alamofire, Moya, or analytics SDK client was found in the app/Pods search.

## Missing states, tests, and executable follow-up

1. **Permission state contract (CC-008, Sol-owned):** define not-determined, rationale, authorized, denied, restricted, unavailable, interrupted, and retry/Settings states for camera, microphone, Speech, and Photos. The contract must name user copy, timing, fallback, accessibility, and event boundaries before implementation.
2. **Camera/session ownership (CC-009 → CC-010):** select one canonical camera/session owner and explicitly classify the AR scene path, `CameraService`, `CameraManager`, and legacy `CameraScreen` route. Add permission preflight and typed failure ownership only after the decision.
3. **Physical permission matrix (CC-005/CC-009):** add a true UI-test/device gate for first launch, authorized, denied, restricted, unavailable, interruption, re-request after Settings, microphone-only failure, Speech failure, and Photos save failure. Current `UITests.swift` is in the unit-test target; benchmark UI tests contain conditional skips. No current test proves a permission state.
4. **Recording/Photos behavior:** test writer setup with unavailable audio input, successful/failed Photos save, file cleanup policy, repeated recording, and user-visible result. Decide retention/cleanup explicitly; do not infer it from the current Documents path.
5. **Speech behavior:** test authorization denial, recognizer unavailable, audio-engine start failure, six-second stop, cancellation, and transcript handling. Keep the processor/retention statement open until the product/privacy owner verifies it.
6. **Privacy manifest and dependency gate (CC-004/CC-011):** inspect the built app and linked frameworks, map Required-Reason/API usage, add/validate the manifest in the release work, and review the ARVideoKit capability evidence. No declaration is made in CC-003.
7. **Remote VLM boundary:** before enabling a production endpoint, approve the minimum payload, explicit user action/consent evidence, endpoint/provider, authentication, failure copy, cost/quota, processor region, retention, and App Privacy disclosure. The current environment flags are a test/configuration mechanism, not that approval.
8. **Telemetry contract (CC-012):** define event names and observable properties, consent/disclosure, destination, retention/deletion, and a raw-media/hidden-identifier prohibition. Separate local debug/performance logging from product analytics and decide whether benchmark artifacts can ship or leave the device.
9. **Identifier review:** document whether request/frame/project/run UUIDs are strictly ephemeral/local, and reject any future install-bound identifier unless explicitly approved and privacy-mapped.

## Exhaustive search log and dispositions

The following searches were run against production Swift and configuration. The matched owners are summarized below; supporting matches that only import a framework, expose a type, or forward state are not counted as independent permission owners.

```text
rg -n -C 2 'AVFoundation|AVKit|AVCaptureDevice|AVCaptureSession|AVCaptureVideoDataOutput|AVCaptureMovieFileOutput|AVAssetWriter|AVAudioSession|AVAudioRecorder|AVAudioEngine|recordPermission|startRunning|stopRunning|startRecording|finishWriting' shafinMultitool --glob '*.swift'
```

Matched production owners: `Services/CameraService.swift`; `Multitool2Module/Services/Camera/CameraManager.swift`; `Multitool2Module/UI/Overlay/OverlayView.swift`; `SceneGeneratorModule/Views/ARSceneContainer.swift`; `SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift`; `SceneModules/CameraScreenModule/View/CameraScreenViewController.swift`; `SceneModules/CameraScreenModule/Interactor/CameraScreenInteractor.swift`; `SceneModules/CameraScreenModule/Presenter/CameraScreenPresenter.swift`; `Multitool2Module/Services/Pipeline/RealtimeScheduler.swift`; `Services/SpeechRecognitionService.swift`; and `Services/PerformanceMonitor.swift`. The first two camera services, AR container, legacy interactor/view, and Speech service contain access/recording operations; the remaining matches are preview, delegate, orientation, lifecycle, or metrics support described above. `AVCaptureMovieFileOutput`, `AVAudioRecorder`, `recordPermission`, and permission request symbols did not match.

```text
rg -n -C 2 'SFSpeechRecognizer|SFSpeechAudioBufferRecognitionRequest|SFSpeechRecognitionTask|requestAuthorization|recognitionTask|recognise\(|stopRecognition' shafinMultitool --glob '*.swift'
```

Matched production owners: `Services/SpeechRecognitionService.swift` and `SceneModules/CameraScreenModule/Interactor/CameraScreenInteractor.swift`; `CameraScreenModule/Presenter` and `CameraScreenViewController` match only the trigger forwarding. `requestAuthorization` and `SFSpeechRecognizer.authorizationStatus` did not match.

```text
rg -n -C 2 'PHPhotoLibrary|PHAssetChangeRequest|creationRequestForAsset|UIImageWriteToSavedPhotosAlbum|UISaveVideoAtPathToSavedPhotosAlbum|PHPhotoLibrary\.authorizationStatus|requestAuthorization' shafinMultitool --glob '*.swift'
```

Matched production owner: `Services/CameraService.swift:376-385` only. It is a write-only video creation request; Photos status/request and read symbols did not match.

```text
rg -n -C 2 'URLSession|URLRequest|dataTask|uploadTask|downloadTask|HTTPURLResponse|NWConnection|WebSocket|Alamofire|Moya|Firebase|Sentry|Crashlytics|https?://' shafinMultitool --glob '*.swift'
```

Matched production owner: `Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift:210-259` only. It is the environment-configured remote VLM provider. No other app-owned URLSession/network client or named analytics/crash SDK matched. `DeepCriticOffloadingCoordinator` matched as a contract, not as a network client.

```text
rg -n -C 2 'Telemetry|OSLog|os_log|analytics|event|Crashlytics|Sentry|Firebase' shafinMultitool --glob '*.swift'
```

Matched telemetry/diagnostic owners include `Multitool2Module/Services/Telemetry/Telemetry.swift`, `Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`, `Multitool2Module/Services/Pipeline/RealtimeScheduler.swift`, `Multitool2Module/UI/Overlay/DebugOverlay.swift`, `Services/PerformanceMonitor.swift`, `Services/DiagnosticsLogger.swift`, `SceneGeneratorModule/Services/SceneGeneratorDiagnosticsLogger.swift`, and benchmark support/coordinator files. Their formal fields, file/console destinations, and exclusions are described in the telemetry sections above. No analytics transport or SDK matched.

```text
rg -n -C 2 'UserDefaults|@AppStorage|FileManager|NSKeyedArchiver|documentDirectory|cachesDirectory|Application Support|Keychain|SecItem|kSec|identifierForVendor|advertisingIdentifier|UUID\(' shafinMultitool --glob '*.swift'
```

Matched storage owners include `Services/DBService.swift`, `Services/CameraService.swift`, `Services/DiagnosticsLogger.swift`, `SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift`, `SceneGeneratorModule/Views/LegacySceneGeneratorCameraShell.swift`, `SceneGeneratorModule/Services/SceneParserService.swift`, `SceneGeneratorModule/Services/SceneBundlePipeline.swift`, `SceneGeneratorModule/Services/LLMParserService.swift`, `SceneGeneratorModule/Services/LlamaContext.swift`, `Benchmark/DeviceBenchmarkCoordinator.swift`, `Benchmark/DeviceBenchmarkSupport.swift`, and `CameraScreenInteractor.swift`. The exact key/file/data dispositions are above. UUID matches were classified as local object/request/project/run IDs; no device/install API matched.

```text
rg -n 'authorizationStatus|requestAccess|requestAuthorization|recordPermission|openSettingsURLString|UIApplication\.shared\.open|PHPhotoLibrary\.authorizationStatus|SFSpeechRecognizer\.authorizationStatus' shafinMultitool --glob '*.swift' || true
rg -n 'identifierForVendor|advertisingIdentifier|ASIdentifierManager|DeviceCheck|Keychain|SecItem|kSec' shafinMultitool --glob '*.swift' || true
find . -type f \( -name 'PrivacyInfo.xcprivacy' -o -name '*.xcprivacy' \) -print
rg -n 'PrivacyInfo|NSPrivacy' shafinMultitool shafinMultitool.xcodeproj --glob '!**/docs/**' || true
```

All four negative/manifest checks returned no production Swift matches/files. Project usage-string matches were separately found at `project.pbxproj:512-515,546-549`; they are not a privacy manifest.

## Judgment calls and open decisions

- The Speech usage string was not promoted into a provider/region/retention fact.
- The environment-gated VLM request was recorded as a real possible transport because it has a concrete `URLSession` implementation, but no endpoint/provider is assumed when configuration is absent.
- The Deep Critic envelope was recorded as a dormant contract, not as transmitted data, because no production provider/caller exists.
- ARVideoKit’s permission code was recorded as dependency evidence, not app runtime behavior, because no app-owned import or call was found.
- No server provider, processor region, retention term, legal basis, tracking declaration, App Privacy answer, privacy-manifest entry, or commercial consent decision was selected.

## Gaps

The artifact is complete for the repository evidence available at the snapshot. Remaining work is the executable follow-up listed above: product permission/consent state specification, canonical camera owner decision, physical/UI permission tests, privacy-manifest and dependency gate, and approved remote/analytics data contracts. No source or configuration fix is authorized by CC-003.
