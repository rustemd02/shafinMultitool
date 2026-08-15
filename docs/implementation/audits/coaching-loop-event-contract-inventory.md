# Camera Coach coaching-loop event contract inventory

Status: repository-evidence audit; proposed contract for Sol decision; no production implementation is included.

This inventory is intentionally narrower than an analytics implementation. It names observable facts, identifies the current source seams, and marks missing evidence rather than filling gaps with inferred product behavior.

## 1. Evidence snapshot

The audit started from the following repository state:

| Item | Evidence |
|---|---|
| Start commit | 605ae923aa12dbaa7366515abd7ecd5c824c2616 |
| Branch state | Detached HEAD; git branch --show-current returned an empty string. |
| Starting status | Clean: git status --short and git status --porcelain=v1 -uno returned no lines. |
| Owned path | docs/implementation/audits/coaching-loop-event-contract-inventory.md did not exist at the start. |
| Change boundary | This audit owns exactly the path above. It must be the only path changed relative to the start commit. |

Post-baseline accepted-main correction: CC-010A landed at e0bd423 (camera: serialize coach capture lifecycle). Its CameraManager exposes awaitable startAndWait(), stopAndWait(), and releaseAndWait() operations serialized on the session queue; it disables/detaches frame delivery and drains the video-output queue on stop/release. CameraManagerLifecycleTests cover concurrent lifecycle calls, idempotent release, stale start completion, and the frame-delivery fence. This later accepted-main evidence does not change the exact audit start commit; the seam statements below use the corrected state.

The authority documents read in full were docs/app-store-product-plan.md, docs/implementation/STATUS.md, docs/implementation/BACKLOG.md, docs/implementation/ux/camera-coach-state-spec.md, docs/implementation/audits/privacy-permissions-inventory.md, and docs/implementation/audits/camera-session-ownership.md. The state specification is still marked proposed_for_owner_acceptance; its analytics labels are therefore source evidence and naming input, not an already-shipped contract.

## 2. Executive finding

The repository has useful local diagnostics and a small amount of structured execution tracing, but it does not have a production product-analytics event sink for the Camera Coach loop. Telemetry publishes in-memory debug metrics and writes selected values to OSLog; PerformanceMonitor aggregates local performance metrics into DiagnosticsLogger, which appends to Documents/preproduction-perf.log; scene execution traces and device benchmark artifacts are local operational data. None of these owners is a durable, consent-mapped, product-event pipeline, and no analytics SDK, event queue, crash reporter, or approved remote analytics endpoint was found.

The current Camera Coach pipeline can expose candidate evidence for live hints, tip stability, pause critique, thermal state, frame timing, and model diagnostics. It does not currently expose a complete observable chain of:

1. a recommendation made visible and stable to the user;
2. a user or camera change that follows that recommendation; and
3. an independent before/after verification result.

In particular, action detection and verification are state-spec requirements, not existing production event seams. The proposed first-helpful-loop event must remain unavailable until those seams are implemented and tested. A tip near an improved frame is not evidence that the tip caused the improvement.

The product documents contain a KPI tension that needs an owner decision: the product plan describes activation as a completed coaching loop or justified “keep as is” in a first session, while CC-012 and this inventory require the primary activation metric to be the first verified helpful loop. This inventory uses the stricter definition for first_helpful_loop_completed and records coach_keep_as_is separately until Product resolves the KPI definition.

## 3. Product outcome hierarchy

### 3.1 Primary outcome

Activation = first verified helpful loop. The event is derivable only when the same eligible Coach session has all of these observable facts, in order:

coach_tip_stabilized → coach_action_detected → coach_verification_completed(result = improved).

The chain is a measurement definition, not a causal claim. It says that an observed recommendation, an observed change, and an observed positive verification occurred in sequence. It does not say the recommendation caused the change or improvement.

### 3.2 Supporting outcomes

| Outcome | Observable fact to capture | What it must not claim |
|---|---|---|
| Tip shown | A user-visible tip crossed the presentation seam. | That the user read, accepted, or benefited from it. |
| Tip stabilized | The existing live-hint stability gate accepted a tip for display; current implementation has a 2.0-second minimum hold seam in AnalysisPipeline. | That the tip was correct or useful. |
| Tip dismissed/rejected | A user dismissal or explicit rejection was observed. | Why the user rejected it unless a closed reason is explicitly captured. |
| Subject clarification | Ambiguity was shown and a selection, dismissal, or unresolved timeout occurred. | The selected subject’s identity or visual content. |
| Action detected | A closed-catalog camera/user action was observed after a tip. | That the tip caused the action. |
| Verification result | A before/after comparison produced improved, not_improved, worse, uncertain, or abstained. | That a recommendation caused the result. |
| Keep as is | The product displayed or the user accepted the valid no-change action. | That this is a verified improvement. |
| Abstention | The coach refused to recommend or verify because evidence was insufficient, conflicting, unavailable, or unsafe. | A failure of the user or a model-quality diagnosis without evidence. |
| Recording | Capture started, stopped, completed, failed, or was interrupted; save outcome was observed. | That the saved media contains a particular subject or scene. |
| Pause summary | A summary view was shown after pause analysis. | That the user acted on it. |
| Deep Review | Disclosure, decision, request, result, error, or quota state was observed. | Any provider, endpoint, region, retention, cost, or consent conclusion not implemented and approved. |
| Crash/termination | Only an explicitly observable lifecycle/diagnostic signal may be recorded. | Crash attribution from a missing next event or a normal termination callback. |
| Thermal/performance | OS thermal state or local performance degradation was observed. | That thermal state caused a user outcome without a measured linkage. |

### 3.3 Activation eligibility

An eligible session needs camera permission and a live Coach route with a valid local analysis source. Permission denial, camera unavailability, an unresolved subject clarification, Deep Review-only work, a recording-only flow, and a session interrupted before verification are not silently counted as activation failures; they are separately classified outcomes.

## 4. Existing instrumentation map

### 4.1 Inventory boundary

The following are the existing telemetry, logging, diagnostics, structured execution, benchmark, and remote-analysis owners found in the repository. print, OSLog, and local files are not called production product analytics in this document. They are included because they are possible source seams or privacy hazards.

The owner count used in this audit is 12 instrumentation owner families. A family groups a directly related owner and its call sites; the count is not a count of every class or every print statement.

### 4.2 Owner table

| # | Existing owner and exact source/call sites | Destination, persistence, transmission, fields, lifecycle | Privacy/risk and test coverage | Disposition |
|---:|---|---|---|---|
| 1 | Telemetry / CameraLog / DebugMetrics in shafinMultitool/Multitool2Module/Services/Telemetry/Telemetry.swift:14-163 and shafinMultitool/Multitool2Module/UI/Overlay/DebugOverlay.swift:10-21; calls from shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift, shafinMultitool/Multitool2Module/Services/Pipeline/RealtimeScheduler.swift:95, shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift:3471, shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift:256, and shafinMultitool/Benchmark/DeviceBenchmarkSupport.swift:574. | Telemetry.shared is an in-memory ObservableObject; DebugMetrics contains UI/pipeline FPS, thermal state, battery level, heavy-model flag, latency map, camera-stable flag, shake level, active modules, and aesthetic score. Selected messages go to OSLog under com.multitool2.camera. A 0.5-second system-monitoring timer updates thermal/battery while the debug overlay is active. No event queue, file sink, URLSession, analytics SDK, consent state, retention policy, or remote transmission exists. | Battery level, thermal state, timing, model state, and active module names are operational data; suggestion logging can include text when its flag is enabled. No direct Telemetry tests were found. | Exclude as product sink; reuse only as a read-only source for thermal/performance fields after privacy and lifecycle review. |
| 2 | PerformanceMonitor, PerformanceMetrics in shafinMultitool/Services/PerformanceMonitor.swift:12-282; calls from shafinMultitool/SceneModules/CameraScreenModule/View/CameraScreenViewController.swift:121,143,149,488-491,1048-1084 and shafinMultitool/Services/SpeechRecognitionService.swift:42,56,61,63. | Aggregates FPS, frame time, CPU/memory, thermal, estimated GPU, dropped frames, and Vision/Speech/overlay latency. A display link and 5-second timer feed the aggregate; thermal notifications update state. It calls DiagnosticsLogger.shared.log periodically. No network transmission. No direct monitor tests were found. | Device resource state and timing can be identifying in combination; Speech error paths must not become transcript analytics. | Development/operational-only; reuse only for bounded performance diagnostics. |
| 3 | DiagnosticsLogger in shafinMultitool/Services/DiagnosticsLogger.swift:20-67; called by shafinMultitool/Services/PerformanceMonitor.swift:169 and flushed by shafinMultitool/SceneModules/CameraScreenModule/View/CameraScreenViewController.swift:172. | Formats time, FPS, CPU, memory, thermal state, Vision latency, and Speech latency into a buffer; writes to Documents/preproduction-perf.log after 20 entries or more than 120 seconds. No cleanup, upload, consent, or retention owner was found. | Local file persistence conflicts with a default product-event boundary; paths and raw diagnostic text must never enter the event schema. No direct tests found. | Exclude from product analytics; development-only until a privacy/retention decision exists. |
| 4 | SceneGeneratorDiagnosticsLogger in shafinMultitool/SceneGeneratorModule/Services/SceneGeneratorDiagnosticsLogger.swift:15-22; call sites include shafinMultitool/SceneGeneratorModule/Views/LegacySceneGeneratorCameraShell.swift:557,567,597,606,626,640,655, shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift:705,717,768-769,833-834,870,886,928,992,2095,2544,2659,2717, shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift:184,197,250,257,261,279,309,317,415,435,442, and shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift:214. | Timestamped console print; flush() is a no-op. No durable or remote sink. | Messages may include raw scene/LLM/model context depending on caller. No direct tests. | Exclude from product analytics; keep development-only. |
| 5 | Direct live-pipeline diagnostics in shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift and shafinMultitool/Multitool2Module/Services/Suggestion/SuggestionEngine.swift:78,142,192,199,207,213,225,241. | OSLog/print records model decisions, frame identifiers, confidence, motion state, candidate and selected suggestion details. CameraLog.liveHintDecisions is enabled; other suggestion flags are disabled by default. No durable product-event storage. | High risk: selected text, frame IDs, candidate labels, confidence, regions, and decision traces may reveal scene content. The proximity of a log to an improved frame does not establish causality. Tests cover domain/presentation behavior, not a durable event sink. | Exclude raw diagnostics; map only approved low-cardinality outcomes through a new event adapter. |
| 6 | Vision/model/motion logs in shafinMultitool/Multitool2Module/Models/Vision/VisionTracking.swift, shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift, and shafinMultitool/Multitool2Module/Utilities/Filters/MotionGate.swift. | OSLog/print includes or can include face/object counts, labels, confidence, bounding boxes, saliency, pixel/model errors, and motion/gyro/accelerometer values. No product persistence/transmission. | Bounding boxes, labels, face data, pixels, and sensor detail are expressly outside this contract. Direct logging is a negative-test target. | Exclude from product analytics; development-only, with privacy cleanup deferred to the relevant owners. |
| 7 | Legacy camera and speech diagnostics in shafinMultitool/Services/CameraService.swift and shafinMultitool/Services/SpeechRecognitionService.swift. | Console messages report camera/Vision/save errors and Speech timing/errors. PerformanceMonitor receives Speech latency. No product sink. | Do not transmit audio, speech text, transcripts, file paths, or raw errors. CameraService is a separate legacy contour from Camera Coach. | Exclude; do not treat legacy logs as Coach events. |
| 8 | Scene-generator diagnostic family: shafinMultitool/SceneGeneratorModule/Services/DiagnosticsCalculator.swift, LLMParserService.swift, LlamaContext.swift, MarkedObjectMatcher.swift, ObjectDetectionBridge.swift, SceneBundlePipeline.swift, SceneParserService.swift, SpatialPlannerService.swift, shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift, shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift, shafinMultitool/ScenesOverviewModule/SORouter.swift, shafinMultitool/Services/DBService.swift, and shafinMultitool/Services/PreProductionThermalGovernor.swift. | Mostly console output; some database/scene-generation operational paths. DiagnosticsCalculator prints scene actors/objects/actions/notes; LLMParserService may print model output and paths. No approved product analytics destination. | Raw scene descriptions, model output, object data, local paths, and free-form user text are prohibited from the Coach event boundary. | Exclude from Coach product analytics; preserve existing behavior for this audit. |
| 9 | Structured execution trace SceneExecutionEventKind, SceneExecutionEvent, SceneExecutionTrace in shafinMultitool/SceneGeneratorModule/Models/SceneExecutionRuntimeContracts.swift:71-157; emitted by SceneBundlePipeline.swift:2571-2645,4603-4629. | In-memory Codable execution events contain scene/chunk IDs, thermal/battery/memory, cooldown, checkpoint file name, and notes; benchmark orchestration can write the trace. Tests in SceneBundlePipelineTests.swift:300-356 cover event counts and telemetry-only critical state. | Scene/chunk/checkpoint identifiers, memory, paths, and notes are operational data, not Coach product properties. | Development/operational-only; do not reuse event names or payloads. |
| 10 | Benchmark owners DeviceBenchmarkArtifactStore, DeviceBenchmarkMetricsCollector, DeviceBenchmarkCoordinator, and DeviceBenchmarkConfig in shafinMultitool/Benchmark/DeviceBenchmarkSupport.swift and shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift. | Uses a UUID run ID and writes JSON/JSONL/markdown under Library/Caches/DeviceBenchmark/<runId>. Fields include device model, OS/app/build, battery, thermal, FPS, CPU/memory, dropped frames, stage latencies, camera/scene summaries, and artifacts. Tests: DeviceBenchmarkSupportTests.swift:12-158, DeviceBenchmarkHarnessTests.swift:13-42, DeviceBenchmarkUITests.swift:12. | Raw device model, build, run IDs, artifacts, local paths, and performance samples must not become default analytics properties. | Development-only; may supply test fixtures, never a product sink. |
| 11 | Remote evidence factory/provider VisualSemanticEvidenceProviderFactory and RemoteVLMVisualEvidenceProvider in shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift:16-30,210-259; caller in AnalysisPipeline.swift:8652-8723. | Environment configuration can select a remote provider, endpoint, and API key; URLSession can transmit a provider request. The default absent-provider path is unavailable. The request contract contains a request UUID, frame ID, mode, locale, privacy tier, trigger, optional redacted visual metadata, local context, allowed catalog, and optional ephemeral correlation/session field. No fixed provider, endpoint, processor, region, retention, payload approval, or consent implementation is established. Tests in VisualSemanticEvidenceCoordinatorTests.swift:5-110 cover unavailable, live rejection, valid, invalid, timeout, and integration behavior. | Highest transmission risk. Raw visual data, free-form context, frame IDs, keys, endpoints, and provider-specific payloads are not allowed in the product event contract. | Keep as a separately gated analysis seam; do not use it as analytics transport. |
| 12 | Deep Critic contract DeepCriticOffloadingCoordinator and MockDeepCriticProvider in shafinMultitool/Multitool2Module/Services/Offloading/DeepCriticOffloadingCoordinator.swift; tests in DeepCriticOffloadingCoordinatorTests.swift:21-1005. | Actor/policy/sanitization/validation contract and mocks exist. Tests cover disabled, outside-pause, network-unavailable, sanitization, validation, and a pause-state change before completion. No production provider/caller/network delivery was found. | Consent, payload, provider, quota, retention, and legal basis remain unknown. | Instrument only explicit product state once a real UI/provider owner exists; otherwise emit no Deep Review success event. |

### 4.3 Missing instrumentation

The following are not available as current production seams and must remain explicit gaps:

- a central CoachEventSink or analytics protocol;
- a product-level Coach session UUID/epoch with documented lifetime;
- a stable user-visible-tip emission seam distinct from candidate generation;
- subject clarification resolution events;
- an action detector that proves a user/camera change followed a tip;
- a before/after verification result tied to that action;
- recording outcome events at the modern Coach route;
- Deep Review consent/request/result/quota UI and production provider ownership;
- approved offline persistence/transmission semantics;
- crash evidence and a crash/termination processor;
- an app privacy manifest (PrivacyInfo.xcprivacy was not found in the audited tree).

## 5. UX-state-to-event matrix

The matrix covers every state S00–S25a in docs/implementation/ux/camera-coach-state-spec.md and the state-machine transitions listed there. Existing state-spec names are normalized to the proposed coach_/domain taxonomy below. E means the five shared envelope properties defined in section 7.

Global rules for every row:

- Forbidden properties are always raw frames/photos/video/audio, transcripts, free-form scene/user text, reconstructive bounding boxes, API keys, endpoint URLs, provider/processor/region fields, local file paths, persistent hidden identifiers, and unbounded diagnostic traces.
- Deduplication is local to (session_token, event_name, semantic_signature, lifecycle_epoch); event_sequence is monotonic per ephemeral session. A UI re-render is not a new trigger.
- Offline means emit to the local in-memory/no-op sink and derive locally; do not silently retry to a future remote endpoint and do not claim durable delivery.
- Current seams may be missing; a missing seam is a blocker, not permission to infer an event from a nearby log.

| State/transition | Candidate event name | Exact observable trigger | Required properties | Deduplication key/rule | Ordering/precondition | Offline behavior | Current source seam | Test seam | Unresolved owner decision |
|---|---|---|---|---|---|---|---|---|---|
| S00 Launch routing → S01/S02/S23 | app_route_resolved | Commercial route resolver commits the visible destination. | E, route_state, route_source, route_destination | Once per committed route transition. | First event for a route lifecycle. | Local only. | Resources/SceneDelegate.swift; route/view composition in ContentView.swift. | Existing route/UI tests; add sink spy. | Product route-state enum and whether S00 is a Coach session. |
| S01 First-value intro → S02 or S04 | onboarding_value_viewed, camera_open_intent | Intro is actually visible; camera-open control receives an action. | E + route_state; E + entry_reason. | View once per presentation generation; intent once per user action. | onboarding_value_viewed precedes intent when intro is shown. | Local only. | Product plan/state spec; current commercial shell seam needs confirmation. | CameraOverlayUXPresentationTests or route UI test. | Is intro optional and does an intent start a session? |
| S02 Permission context → S03/S04 | camera_permission_context_viewed, camera_permission_result | Permission explainer visible; system request completion returns an observable status. | E + permission_type; E + permission_type, permission_status, permission_trigger. | Context once per generation; result once per request completion. | Context before request/result. | Local only; no permission request retry queue. | CameraManager.configureSession; AVCaptureSession/permission seam is incomplete; no app-owned authorization gate found. | Camera permission tests must inject status/result. | Product/privacy owner must define request timing and status enum. |
| S03 Unavailable/denied/restricted → S02 or S00 | camera_unavailable_viewed, settings_open_requested, permission_recovered | Unavailable UI visible; settings action tapped; a later status check changes to authorized. | E + permission_status; E + permission_type; E + permission_type. | Once per visible error generation; settings once per tap; recovery once per status edge. | Result/unavailable before settings; recovery after a new status read. | Local only. | CameraManager; SceneDelegate; no UIApplication.openSettingsURLString owner found. | Permission and lifecycle tests. | Exact handling of restricted vs denied and recovery after re-entry. |
| S04 Live seeking/acquiring evidence → S05/S06/S11/S19/S20 | coach_session_started, coach_live_started, analysis_seeking_started | Coach route/session lease is acquired; camera live processing starts; pipeline enters seeking. | Session: E + session_start_reason, route_state, analysis_mode, orientation; live: E + analysis_mode; seeking: E + analysis_mode. | Session once per session token; live/seeking once per lifecycle epoch. | Permission authorized and route ownership acquired before live. | Local in-memory/no-op; no remote assumption. | CameraViewModel.startAndWait; CameraManager.startAndWait; AnalysisPipeline registration; deterministic scheduler/pipeline unregister/release and route lease remain missing. | CameraManagerLifecycleTests, camera ownership tests, and AnalysisPipelinePresentationTests. | Session boundary, mode enum, route lease owner, and CC-010B scheduler/pipeline release semantics. |
| S04 evidence becomes ambiguous → S05 | coach_subject_clarification_requested | Clarification UI is shown because the current subject is ambiguous. | E + subject_clarification_reason, candidate_count_bucket. | Once per ambiguity signature per analysis epoch; signature must be enum/bucket, not labels. | Live seeking before tip. | Local only. | SceneSemanticsReport, AnalysisPipeline subject ambiguity/presentation seam. | CameraAnalysisDomainContractsTests subject ambiguity; add event spy. | Candidate count/privacy-safe ambiguity enum and timeout. |
| S05 subject selected → S06 | coach_subject_clarification_resolved | User selection or an approved deterministic resolution is committed. | E + subject_resolution_method, subject_kind. | Once per clarification generation. | After request; before stable tip. | Local only. | No product event owner; domain SceneSemanticsReport.PrimarySubject. | Domain contract tests; add view-model test. | Whether subject_kind is safe and which resolution methods are allowed. |
| S05 dismissed/timeout → S04/S11 | coach_subject_clarification_dismissed or coach_abstained | User dismisses or timeout closes clarification; coach abstains only when abstention UI/state is committed. | Dismiss: E + subject_clarification_reason; abstain: E + abstention_reason, analysis_source. | Once per generation; no abstention on every failed frame. | Request precedes dismissal/abstention. | Local only. | AnalysisPipeline ambiguity/fallback presentation; no explicit UI owner. | CameraAnalysisDomainContractsTests; CameraOverlayUXPresentationTests. | Distinguish dismissal from evidence-based abstention. |
| S06 stable tip active → S07/S08/S09/S11 | coach_tip_shown, coach_tip_stabilized | Tip presentation crosses the visible overlay seam; stability gate accepts the same semantic tip after its hold. | E + tip_surface, tip_category, action_type, tip_confidence_band, fallback_used. | Shown once per visible presentation; stabilized once per (tip category, action type, lifecycle epoch) after stable gate. | Seeking/live before recommendation; no event from candidate generation alone. | Local only; no delivery claim. | AnalysisPipeline.applyLiveHint and makeLiveHintPresentation; OverlayView renders liveHint. Current visible-emission callback is missing. | AnalysisPipelinePresentationTests stable identity/hold tests; overlay presentation tests. | Exact visual boundary and stability interval; state spec calls for a benchmark, current code has 2.0 s minimum hold and 4.0 s display duration. |
| S06 tip explanation → S07 | coach_tip_explanation_opened | Explanation control is tapped and expanded UI commits. | E + tip_category. | Once per tip presentation generation. | A shown/stable tip must exist. | Local only. | OverlayView.swift; exact control seam needs confirmation. | Overlay UX tests. | Whether opening before stabilization is allowed. |
| S07 explanation closes → S06/S08 | coach_tip_explanation_closed | Expanded explanation is dismissed or closed. | E + tip_category. | Once per expansion. | Open before close. | Local only. | OverlayView.swift; control seam needs confirmation. | Overlay UX tests. | Close reason is intentionally not free-form; decide whether a closed enum is needed. |
| S06/S07 tip rejected → S04/S05 | coach_tip_rejected | User explicitly rejects the recommendation. | E + tip_rejection_reason. | Once per tip generation; ignore repeated taps after terminal rejection. | Tip shown/stable before rejection. | Local only. | No explicit rejection owner in current pipeline; Suggestion/overlay is a candidate seam. | Overlay/domain tests. | Rejection control and closed reason vocabulary. |
| S06/S07 tip disappears without rejection → S04 | coach_tip_dismissed | Tip leaves the visible surface because of user dismissal or an explicit lifecycle/UI dismissal, not merely candidate replacement. | E + tip_dismissal_reason. | Once per tip presentation; expiry is not a user dismissal. | Shown before dismissal. | Local only. | AnalysisPipeline expiry/hold state; user dismissal seam missing. | Presentation tests. | Separate user dismiss from expiry, replacement, interruption. |
| S08 relevant action observed → S09 | coach_action_detected | A closed-catalog user/camera change is observed after the active stable tip and passes action evidence validation. | E + action_type, action_frame, elapsed_bucket, analysis_source. | Once per action signature per tip generation; frame IDs are not emitted. | Stable tip before action; reject stale action after tip expiry. | Local only. | Missing: current CameraManager/FrameContext exposes frames, but no action detector or user-action observation owner exists. | New injected action detector test plus pipeline presentation tests. | Product/implementation definition of observable change and false-positive threshold. |
| S09 verification starts → S10a/S10b/S10c/S11 | coach_verification_started | Verification state enters with a before/after evidence pair or a user-visible verification workflow. | E + verification_window_bucket. | Once per action generation. | Action detected; valid before evidence required. | Local only. | Missing: AnalysisPipeline.runPauseAnalysis produces critique but not action-linked verification. | New verification state-machine tests. | Window and evidence source. |
| S09 → S10a | coach_verification_completed | Verification commits result improved. | E + verification_result, verification_evidence_status, verification_window_bucket. | Once per verification generation; ignore late duplicate result. | After action and verification start. | Local only. | Missing: no production before/after verifier. | New verifier tests; domain verdict tests are not sufficient. | What constitutes improved and whether user confirmation is required. |
| S09 → S10b | coach_verification_completed plus coach_tip_refined | Verification commits not_improved or worse; refined advice becomes visible. | Completion as above; refine adds tip_category, action_type, verification_result. | One completion and one refinement per generation. | Refinement only after non-improvement/worse result. | Local only. | AnalysisPipeline can publish updated live/pause presentations; no linked verifier. | AnalysisPipelinePresentationTests correction cases; add event assertions. | Whether worse is independently observable or folded into not-improved. |
| S09 → S10c | coach_keep_as_is | Valid no-change result is shown/accepted. | E + case_result (keep_as_is). | Once per case. | Must follow valid good verdict/no-change rationale, not a missing result. | Local only. | RecommendationPlan/FrameVerdict.good and PauseCritiquePresentation.noChangeRationale; user acceptance seam missing. | CameraAnalysisDomainContractsTests keep-current cases. | Product KPI treatment vs strict first-helpful-loop activation. |
| Any analysis → S11 | coach_abstained | Abstention UI/state commits for insufficient, conflicting, unavailable, or unsafe evidence. | E + abstention_reason, analysis_source. | Once per abstention episode; no per-frame repeats. | No success event may follow without a new recommendation/action chain. | Local only. | AnalysisPipeline fallback/ambiguity states; VisualSemanticEvidenceCoordinator unavailable path. | Domain contracts and coordinator tests. | Closed reason list and whether fallback is an abstention or a valid recommendation. |
| S10a → session/history | first_helpful_loop_completed (derived) | Deterministic derivation in section 10 reaches improved verification after stable tip and action. | E + verification_window_bucket, case_result, derivation_version. | Once per session token, first qualifying chain only. | Strict ordered preconditions; no causal wording. | Derive locally; do not backfill from future network delivery. | Missing until action/verifier seams exist; derivation adapter should sit above event sink. | Pure reducer/state-machine tests with duplicate/stale/interruption fixtures. | Owner approval of algorithm/window and whether it can be a release KPI. |
| S12 pause requested → summary | coach_analysis_paused, coach_pause_summary_shown | Pause commits; summary UI is visible. | Paused: E + interruption_reason; summary: E + pause_summary_kind. | One per pause generation; summary once per visible generation. | Pause before summary. | Local only; Deep Review remains separate. | CameraViewModel.togglePause; AnalysisPipeline.runPauseAnalysis; OverlayView pause panel. | CameraOverlayUXPresentationTests; AnalysisPipelinePresentationTests. | Pause reason enum and what qualifies as summary visible. |
| S12 → S04/S06 | coach_analysis_resumed | Resume commits and live processing restarts. | E + recovery_action. | Once per pause generation. | Paused before resume; old async pause results invalidated. | Local only. | CameraViewModel.togglePause invokes the awaitable CameraManager lifecycle boundary through startAndWait/stopAndWait; deterministic scheduler/pipeline unregister/release remains missing. | Pause/resume, CameraManagerLifecycleTests, and stale-result tests. | Whether resume continues same session token or opens a lifecycle epoch; CC-010B release ownership. |
| S13 Pro Controls opened → S04 | coach_pro_controls_opened | Controls panel is visibly expanded. | E + section. | Once per expansion. | Coach route active. | Local only. | OverlayView/Camera Coach control surface; exact owner needs confirmation. | Overlay UX tests. | Control list and whether these controls belong to Coach analytics. |
| S13 control changed → S04 | camera_control_changed | A supported control commits a new value. | E + control_name, control_value_bucket. | Once per committed value edge; no continuous slider samples. | Controls open or explicit control action. | Local only. | CameraManager camera configuration and OverlayView; exact controls vary. | Camera manager tests. | Safe closed control/value vocabulary. |
| S14 recording active → S15 | recording_started, recording_stopped, recording_interrupted | Recorder confirms start/stop/interruption. | Started/stopped: E + recording_stage; interrupted: E + recording_interruption_reason. | Once per recorder state edge and recording generation. | recording_started before stop/interrupt. | Local only; no upload. | Legacy CameraService/CameraScreenViewController owns known recorder seams; modern Coach recorder owner is not established. | UITests.swift recording controls; add recorder unit tests. | Which recorder is in Coach scope and exact start confirmation. |
| S15 save result | recording_completed, recording_failed, recording_save_result | Writer/save callback returns success/failure and destination result. | Completed: duration, destination, artifact; failed: stage/failure/artifact; save: destination/result/artifact. | Once per recording generation and save callback. | Stop before save; failed callbacks terminal. | Local only; no retry upload. | CameraService save paths and CameraScreenViewController; modern route seam missing. | Recording/save tests and failure injection. | Photo-library authorization/result taxonomy; no current app-owned permission gate found. |
| S16 failure → recovery | recording_recovery_attempted | User chooses a supported recovery action. | E + recovery_action. | Once per user action. | Failure viewed before recovery. | Local only. | CameraScreenViewController/legacy UI; Coach owner missing. | Recording failure UI tests. | Recovery action vocabulary and artifact policy. |
| S17 Deep Review disclosure → S18/return | deep_review_consent_shown, deep_review_accepted, deep_review_declined | Disclosure visible; explicit accept/decline commits. | Shown: trigger + payload class; decision: consent_decision. | Disclosure once per request generation; decision once. | Shown before decision; no request before accept. | Local only; never infer consent from provider availability. | Missing product UI owner; coordinator policy/contracts only. | DeepCriticOffloadingCoordinatorTests; new consent UI tests. | Legal/privacy wording, consent scope, and whether remote VLM is in this flow. |
| S18 request → S18a/S18b | deep_review_requested, deep_review_cancelled | Approved request is submitted; user cancellation commits. | Request: trigger + payload class; cancel: failure reason user_cancelled. | One request/cancel per request UUID; request UUID is internal only and not event property. | Acceptance before request; cancellation only while pending. | Local no-op/unavailable; no automatic remote retry. | VisualSemanticEvidenceCoordinator pause-only request seam; Deep Critic production caller missing. | Coordinator timeout/disabled/network tests. | Provider, endpoint, payload, quota, and cancellation owner. |
| S18 → S18a | deep_review_completed | Approved response validates and completes. | E + latency bucket, case result. | Once per request; stale completion ignored. | Request accepted; matching request generation. | Local result only; transmission unknown. | Remote VLM coordinator can return evidence; no product result owner. | Valid/timeout/late-result coordinator tests. | Result contract and latency clock. |
| S18 → S18b | deep_review_failed, deep_review_quota_exhausted | Request returns an error or explicit exhausted allowance. | Failed: failure reason + latency; quota: quota outcome. | Once per request; quota edge deduped by allowance generation. | Request accepted; no result after terminal failure. | Offline maps to network_unavailable/offline only if observed. | VisualSemanticEvidenceCoordinator unavailable/timeout; Deep Critic policy tests. | Disabled/network/quota/error injection tests. | Quota owner and user-visible allowance semantics. |
| S18a result viewed/applied | deep_review_result_viewed, deep_review_action_applied | Result UI visible; user applies a closed-catalog action. | Viewed: case result; applied: action type + case result. | Once viewed per result; apply once per action. | Completion before view/apply. | Local only. | Product UI owner missing; RecommendationAction is a domain candidate. | New result UI tests. | Whether Deep Review actions can enter the same helpful-loop chain. |
| S19 interruption → recovery | camera_interrupted, camera_recovery_result | Capture session interruption notification/state is observed; restart result commits. | Interrupted: interruption_reason; recovery: recovery_result. | Once per interruption epoch and recovery attempt. | Active session before interruption; recovery after restart attempt. | Local only; do not queue frames. | CC-010A CameraManager startAndWait/stopAndWait/releaseAndWait serializes capture lifecycle and fences late camera frames; scheduler/pipeline unregister/release and route ownership remain incomplete. CameraService is a separate legacy contour. | CameraManagerLifecycleTests and camera ownership/lifecycle tests. | Recovery/re-entry policy, session epoch boundary, and CC-010B downstream release. |
| S20 thermal/memory pressure → degraded/restore | app_thermal_state_changed, performance_degraded | ProcessInfo.thermalState changes; a defined performance threshold/feature degradation commits. | Thermal: thermal_state, thermal_change; performance: signal + thermal. | Emit only state edge; performance once per degradation episode. | System signal before related feature change. | Local only; no high-frequency samples. | Telemetry.updateSystemMetrics, PerformanceMonitor, ThermalGovernor. | Performance/thermal tests; Telemetry seam injection needed. | Thresholds, sampling interval, memory policy, and user-visible meaning. |
| S21 Offline → local loop/Deep Review unavailable | no continuous reachability event; reuse deep_review_failed when a request outcome is observed | A network-dependent request returns offline/unavailable. | deep_review_failed with closed failure reason if request exists. | One terminal request outcome. | Request before outcome. | Local Coach path continues; no connectivity polling event. | VisualSemanticEvidenceCoordinator provider-unavailable path. | Offline coordinator tests. | Whether app reachability itself is a product signal. |
| S22 Rotation → same state | no product event; diagnostics only | Orientation changes without a product-state transition. | None. | N/A. | Preserve session/event sequence; do not re-emit tip. | Local only. | CameraManager/OverlayView orientation seams; state spec says no event every rotation. | Rotation ownership tests. | Whether an orientation bucket belongs on session start only. |
| S23 Enter Scene Mode → S24 | section_selected, media_owner_transition_result | Scene section selection commits; camera owner release/transition result commits. | Section + transition result. | Once per user selection and transition. | Coach session ends/pauses before owner handoff. | Local only; no shared camera lease assumption. | SceneDelegate, SORouter, ARSceneContainer, SceneGeneratorViewModel; route lease missing. | Ownership handoff tests. | Cross-section session boundary and whether to include Scene Mode in Coach funnel. |
| S24 Return Camera → S04 | section_selected, media_owner_transition_result, coach_session_started (new session) | Camera section selected and ownership reacquired; new Coach lifecycle starts. | Section + transition; session start properties. | New session token after re-entry under recommended policy. | Scene owner releases before Camera Coach starts. | Local only. | SceneDelegate/commercial shell; CameraManager.releaseAndWait/startAndWait provide the accepted camera lifecycle boundary, while deterministic scheduler/pipeline release and the route lease remain incomplete. CameraService is a separate legacy contour. | Handoff/re-entry and CameraManagerLifecycleTests. | Resume vs new session semantics and CC-010B downstream release. |
| S25 Current session history → S25a | history_viewed, history_case_opened | History view/case detail becomes visible. | History view: section; case: history_case_source. | Once per visible view/case generation. | Session/history owner must have a case identifier internally; do not emit it. | Local only. | No confirmed Coach history owner; DBService is not an approved analytics sink. | New history presentation tests. | Persistence model and whether history is in scope for activation. |
| S25a case action reused → S04/S06 | history_action_reused | User reuses a closed-catalog prior action in a new live flow. | action_type, reuse_result. | Once per user reuse action. | Case opened before reuse; no raw case ID. | Local only. | Product/history owner missing; RecommendationAction candidate. | New history action tests. | Whether reuse starts a new helpful-loop chain. |
| Any active state → end/background/termination | coach_session_ended | Explicit session owner release, background policy, route exit, or confirmed user end commits. | session_end_reason, session_duration_bucket. | Once per session token; late callbacks cannot reopen it. | All in-flight generations invalidated before/with end. | Local only; no crash inference. | Route owner missing; CameraViewModel.stop/stopAndWait and CameraManager.stopAndWait/releaseAndWait are lifecycle seams. The remaining gap is deterministic scheduler/pipeline unregister/release, not CameraManager stop fencing. | Session lifecycle, CameraManagerLifecycleTests, and stale-result tests. | Background grace period, downstream release ownership, and whether re-entry gets a new token. |

## 6. Versioned event taxonomy proposal

### 6.1 Contract identity

Proposed contract identifier: camera_coach_events, semantic version 0.1.0, status proposed_for_Sol_decision. schema_version is an explicit envelope property and must be incremented for incompatible changes. Event names are stable lower-snake-case. Names below describe product facts, not current implementation availability.

E in the table means the shared envelope: schema_version, session_token, event_sequence, event_time_ms, and route. session_token is proposed and ephemeral; see section 9. Properties listed after E are the complete event-specific property set.

| Event name | Kind | Exact event-specific properties | Current availability |
|---|---|---|---|
| app_route_resolved | fact | route_state, route_source, route_destination | Partial route seam |
| onboarding_value_viewed | fact | route_state | Missing commercial UI seam |
| camera_open_intent | fact | entry_reason | Missing/route seam |
| camera_permission_context_viewed | fact | permission_type | Missing app-owned gate |
| camera_permission_result | fact | permission_type, permission_status, permission_trigger | Missing app-owned gate |
| camera_unavailable_viewed | fact | permission_status | Partial camera seam |
| settings_open_requested | fact | permission_type | Missing settings owner |
| permission_recovered | fact | permission_type | Missing lifecycle/status gate |
| coach_session_started | fact | session_start_reason, route_state, analysis_mode, orientation | Missing session owner |
| coach_session_ended | fact | session_end_reason, session_duration_bucket | Missing session owner |
| coach_live_started | fact | analysis_mode | Partial CameraViewModel seam |
| analysis_seeking_started | fact | analysis_mode | Partial pipeline seam |
| coach_subject_clarification_requested | fact | subject_clarification_reason, candidate_count_bucket | Domain evidence; UI event missing |
| coach_subject_clarification_resolved | fact | subject_resolution_method, subject_kind | Missing |
| coach_subject_clarification_dismissed | fact | subject_clarification_reason | Missing |
| coach_tip_shown | fact | tip_surface, tip_category, action_type, tip_confidence_band, fallback_used | Visible boundary missing |
| coach_tip_stabilized | fact | tip_surface, tip_category, action_type, tip_confidence_band, fallback_used | Stability gate exists; event seam missing |
| coach_tip_explanation_opened | fact | tip_category | UI seam missing |
| coach_tip_explanation_closed | fact | tip_category | UI seam missing |
| coach_tip_rejected | fact | tip_rejection_reason | UI seam missing |
| coach_tip_dismissed | fact | tip_dismissal_reason | UI seam missing |
| coach_action_detected | fact | action_type, action_frame, elapsed_bucket, analysis_source | Missing detector |
| coach_verification_started | fact | verification_window_bucket | Missing verifier |
| coach_verification_completed | fact | verification_result, verification_evidence_status, verification_window_bucket | Missing verifier |
| coach_tip_refined | fact | tip_category, action_type, verification_result | Partial presentation seam |
| coach_keep_as_is | fact | case_result | Domain rationale exists; acceptance seam missing |
| coach_abstained | fact | abstention_reason, analysis_source | Partial fallback seam |
| first_helpful_loop_completed | derived fact | verification_window_bucket, case_result, derivation_version | Not derivable today |
| coach_analysis_paused | fact | interruption_reason | CameraViewModel.togglePause seam |
| coach_pause_summary_shown | fact | pause_summary_kind | Pause presentation seam |
| coach_analysis_resumed | fact | recovery_action | CameraViewModel.togglePause seam |
| coach_pro_controls_opened | fact | section | UI seam missing |
| camera_control_changed | fact | control_name, control_value_bucket | Camera/control seam partial |
| recording_started | fact | recording_stage | Legacy recorder only |
| recording_stopped | fact | recording_stage | Legacy recorder only |
| recording_interrupted | fact | recording_interruption_reason | Legacy recorder only |
| recording_completed | fact | recording_duration_bucket, save_destination, recoverable_artifact | Modern Coach seam missing |
| recording_failed | fact | recording_stage, recording_failure_class, recoverable_artifact | Legacy save seam |
| recording_save_result | fact | save_destination, save_result, recoverable_artifact | Legacy save seam |
| recording_recovery_attempted | fact | recovery_action | UI seam missing |
| deep_review_consent_shown | fact | deep_review_trigger, deep_review_payload_class | Contract only |
| deep_review_accepted | fact | consent_decision | Contract only |
| deep_review_declined | fact | consent_decision | Contract only |
| deep_review_requested | fact | deep_review_trigger, deep_review_payload_class | Gated analysis seam |
| deep_review_cancelled | fact | deep_review_failure_reason | Contract only |
| deep_review_completed | fact | deep_review_latency_bucket, case_result | Provider/result UI missing |
| deep_review_failed | fact | deep_review_failure_reason, deep_review_latency_bucket | Partial unavailable/timeout seam |
| deep_review_quota_exhausted | fact | deep_review_quota_outcome | No quota owner |
| deep_review_result_viewed | fact | case_result | UI missing |
| deep_review_action_applied | fact | action_type, case_result | UI missing |
| camera_interrupted | fact | interruption_reason | Lifecycle seam partial |
| camera_recovery_result | fact | recovery_result | Lifecycle seam partial |
| app_thermal_state_changed | fact | thermal_state, thermal_change | Local source exists |
| performance_degraded | fact | performance_signal, thermal_state | Threshold/event seam missing |
| section_selected | fact | section | Route seam partial |
| media_owner_transition_result | fact | transition_result | Route lease missing |
| history_viewed | fact | section | History owner missing |
| history_case_opened | fact | history_case_source | History owner missing |
| history_action_reused | fact | action_type, reuse_result | History owner missing |

Count: 59 active proposed events, including one derived event (first_helpful_loop_completed); one reserved-but-not-emitted event, app_crash_or_termination, is discussed in section 8. There is no current implementation commitment to emit all 59.

### 6.2 Names deliberately split or renamed

- The state spec’s tip_stabilized becomes coach_tip_stabilized, distinct from coach_tip_shown and from a generated candidate.
- The state spec’s tip_action_observed becomes coach_action_detected; “detected” is a fact and does not imply user intent or tip causality.
- record_save_result is split into recording_completed, recording_failed, and recording_save_result so a writer result is not confused with a library-save result.
- Deep Review consented/cancelled is normalized to explicit deep_review_accepted, deep_review_declined, and deep_review_cancelled; no request is implied by consent.
- tip_verification_completed(result: ...) is represented as one stable event with a closed verification_result value, not multiple event names.
- app_crash_or_termination is reserved only; absence of a session-end event is not emitted as crash evidence.

## 7. Exact property dictionary

The dictionary contains 63 unique properties: five shared envelope properties and 58 event-specific properties. Every event uses the shared envelope; section 6 lists the exact event-specific set.

### 7.1 Shared envelope properties

These five properties are required on every emitted event. event_name is the event key, not a free-form property. There is no payload field for arbitrary metadata.

| Property | Type | Allowed values/cardinality | Source symbol | Required | Privacy classification / raw-media or identifier risk | Retention/transmission status | Validation |
|---|---|---|---|---|---|---|---|
| schema_version | string | Exact contract version, initially 0.1.0; one value per event | Contract constant; no current symbol | Yes | Public schema metadata; no media/identifier risk | Proposed; no retention or transmission decision | ASCII semantic-version format; reject unknown major versions. |
| session_token | opaque string | One random UUID-shaped token per in-memory Coach session; not persistent | Proposed session owner; existing code uses UUID() for local suggestion/request/benchmark IDs but has no Coach session token | Yes in proposed contract | Ephemeral pseudonymous identifier; not a device/install/account identifier | proposed_for_Sol_decision; memory only by default; no transmission/retention/provider decision | Generate at session creation; never reuse across re-entry; reject empty, persistent, or externally supplied values. |
| event_sequence | integer | Non-negative, strictly increasing per session_token | Proposed sink; no current sequence owner | Yes | Local ordering metadata; low risk | Proposed local only; no retention/transmission decision | Start at 0 or 1 consistently; reject duplicates and regressions. |
| event_time_ms | integer | Monotonic wall-clock timestamp in milliseconds; one value per event | Proposed sink; current code uses Date/timestamps in diagnostics | Yes | Timing metadata; may support session correlation | Proposed; no retention/transmission decision | Must be present, non-negative, and not a media/file timestamp; ordering uses sequence, not wall clock. |
| route | enum string | camera_coach, scene_mode, history, unknown | Proposed route adapter; route composition in SceneDelegate/ContentView | Yes | Low-cardinality product context | Proposed local only | Closed enum; no view names, URLs, or paths. |

### 7.2 Event-specific properties

“Required” means required when the property is listed for an event in section 6. A property never carries a raw fallback. “Unavailable” is a valid audit result and is not replaced with a guessed value.

| Property | Type | Allowed values/cardinality | Source symbol | Required | Privacy classification / raw-media or identifier risk | Retention/transmission status | Validation |
|---|---|---|---|---|---|---|---|
| route_state | enum | intro, permission, unavailable, live, pause, recording, deep_review, history, scene, unknown | State spec S00-S25a; proposed route adapter | When listed | Low-cardinality UI state | Proposed local only | Closed enum; reject class names and free-form strings. |
| entry_reason | enum | user_tap, route_restore, deep_link, test, unknown | Route/UI action seam; currently missing | When listed | Low-risk product context | Proposed local only | Closed enum; no URL/deep-link value. |
| route_source | enum | launch, camera_button, history, scene_mode, system_return, unknown | SceneDelegate/router candidate | When listed | Low-cardinality | Proposed local only | Closed enum. |
| route_destination | enum | camera_coach, scene_mode, history, settings, unknown | Router candidate | When listed | Low-cardinality | Proposed local only | Closed enum. |
| orientation | enum | portrait, landscape, unknown | CameraManager/overlay orientation seam | When listed | Low-cardinality device context | Proposed local only | No dimensions or device model. |
| session_start_reason | enum | camera_open, reentry, permission_recovered, test, unknown | Proposed session owner | When listed | Low-cardinality | Proposed local only | Closed enum. |
| session_end_reason | enum | user_exit, route_change, background, interrupted, permission_lost, completed, unknown | Proposed route/camera owner | When listed | Lifecycle fact; no crash inference | Proposed local only | background is not crash; close once. |
| session_duration_bucket | enum | 0_5s, 5_15s, 15_30s, 30_60s, 60_180s, 180s_plus, unknown | Derived from event times | When listed | Coarse timing | Proposed local only | Compute only from same session; no exact duration property. |
| analysis_mode | enum | live, pause, unknown | AnalysisMode in CameraAnalysisDomainContracts.swift | When listed | Low-cardinality | Proposed local only | Closed enum. |
| tip_surface | enum | live_overlay, pause_summary, deep_review, unknown | LiveHintPresentation, PauseCritiquePresentation | When listed | Low-cardinality; raw text excluded | Proposed local only | Closed enum. |
| tip_category | enum | horizon, exposure, composition, lighting, lens, subject_framing, background, keep_current_setup, other, unknown | SuggestionType, ActionTypeV1, SemanticActionType | When listed | Low-cardinality semantic category; no label/text | Proposed local only | Map only closed catalog; unknown if no safe mapping. |
| action_type | enum | move_frame_left, move_frame_right, move_frame_up, move_frame_down, increase_subject_size, reduce_background_distractions, change_angle, improve_front_light, level_horizon, leave_frame_as_is, shift_frame, step, adjust_camera, adjust_light, adjust_subject, clean_background, wait, keep_current_setup, unknown | ActionTypeV1 and SemanticActionType in CameraAnalysisDomainContracts.swift | When listed | Closed semantic enum; no target labels/regions | Proposed local only | Reject any action not in versioned catalog; do not send action IDs. |
| action_frame | enum | camera_observed, user_control, unknown | Proposed action detector | When listed | Low-cardinality provenance; no frame ID | Proposed local only | Must not contain FrameContext, pixel buffer, or source frame ID. |
| tip_confidence_band | enum | low, medium, high, unknown | LiveHintPresentation.confidence / domain confidence | When listed | Coarse model output | Proposed local only | Fixed thresholds owned by Product/ML; no raw score. |
| fallback_used | boolean | true/false | LiveHintPresentation.isFallback, PauseCritiquePresentation.fallbackUsed | When listed | Low-risk outcome flag | Proposed local only | Must be a Boolean; absence is not false. |
| tip_rejection_reason | enum | wrong_subject, not_relevant, already_done, too_many_tips, user_unknown, unknown | New UI action seam | When listed | Closed UX reason; no free text | Proposed local only | User may choose only closed values; no inferred reason. |
| tip_dismissal_reason | enum | user, expired, replaced, interrupted, unknown | Proposed overlay/pipeline seam | When listed | Closed lifecycle reason | Proposed local only | expired/replaced are not user rejection. |
| subject_clarification_reason | enum | ambiguous, competing_candidates, low_confidence, user_requested, timeout, dismissed, unknown | SceneSemanticsReport ambiguity fields; new UI seam | When listed | Closed semantic state; no labels/regions | Proposed local only | No candidate labels or coordinates. |
| candidate_count_bucket | enum | 0, 1, 2, 3_plus, unknown | PrimarySubject.competingCandidates | When listed | Coarse count; no candidate identity | Proposed local only | Bucket before emission; no candidate array. |
| subject_resolution_method | enum | user_selection, automatic, single_candidate, timeout, unknown | New clarification owner | When listed | Low-cardinality | Proposed local only | automatic requires deterministic source documentation. |
| subject_kind | enum | person, object, scene, unknown | SceneSemanticsReport.PrimarySubject.kind | When listed | Coarse semantic category; no label/face data | Proposed local only | Never emit label, embedding, face attribute, or region. |
| abstention_reason | enum | insufficient_evidence, ambiguous_subject, conflicting_evidence, unsafe_action, provider_unavailable, thermal_budget, offline_dependency, stale_result, unknown | Domain fallback/coordinator status; proposed closed mapping | When listed | Low-cardinality model/system state | Proposed local only | Must be directly observed; no inference from missing event. |
| elapsed_bucket | enum | 0_1s, 1_3s, 3_10s, 10_30s, 30_60s, 60s_plus, unknown | Derived from event times | When listed | Coarse timing | Proposed local only | Same session and chain only; no exact user timeline. |
| verification_result | enum | improved, not_improved, worse, uncertain, abstained, unknown | Missing verifier; domain FrameVerdict is only good/mixed/needs_fix | When listed | Outcome category; no image/content | Proposed local only | Must be produced by an approved before/after verifier; good alone cannot map to improved. |
| verification_evidence_status | enum | before_after_valid, before_missing, after_missing, ambiguous, stale, unavailable, unknown | New verifier | When listed | Evidence status; raw evidence excluded | Proposed local only | improved requires before_after_valid. |
| verification_window_bucket | enum | 0_5s, 5_15s, 15_30s, 30_60s, 60s_plus, unknown | Derived verifier timing | When listed | Coarse timing | Proposed local only | Use proposed algorithm windows; exact window requires owner acceptance. |
| pause_summary_kind | enum | critique, verification, abstention, recording, unknown | PauseCritiquePresentation / pause UI | When listed | Low-cardinality | Proposed local only | No whyGood, whyProblematic, text, labels, or regions. |
| control_name | enum | zoom, focus, exposure, torch, grid, orientation_lock, unknown | New control adapter; camera controls vary | When listed | Low-cardinality | Proposed local only | Version catalog before implementation; no arbitrary key. |
| control_value_bucket | enum | decreased, unchanged, increased, enabled, disabled, unknown | New control adapter | When listed | Coarse value change; no exact settings | Proposed local only | No raw numeric slider or device setting. |
| recording_duration_bucket | enum | 0_5s, 5_15s, 15_60s, 60_180s, 180s_plus, unknown | Recorder result callback | When listed | Coarse timing | Proposed local only | Compute locally; no file duration/path. |
| recording_stage | enum | preflight, capture, writer, save, unknown | Recorder owner; legacy CameraService/CameraScreenViewController candidates | When listed | Low-cardinality operational state | Proposed local only | Closed enum. |
| recording_failure_class | enum | permission, configuration, writer, storage, photo_library, interrupted, timeout, unknown | Recorder result callback | When listed | Closed operational class; no raw error | Proposed local only | Map error to class with no message/file path. |
| recording_interruption_reason | enum | background, camera_interrupted, thermal, user_stop, system, unknown | Recorder/lifecycle owner | When listed | Low-cardinality | Proposed local only | No notification payload or raw error. |
| save_destination | enum | photo_library, local_only, discarded, unknown | Save result owner | When listed | Destination category; no path | Proposed local only | Permission/result must be separate from media content. |
| save_result | enum | success, failure, cancelled, unavailable, unknown | Save callback | When listed | Low-cardinality | Proposed local only | Direct callback only; no inferred success from UI disappearance. |
| recoverable_artifact | boolean/enum | true, false, unknown | Recorder recovery owner | When listed | Operational flag; no file identifier | Proposed local only | Only set when writer/save owner can prove it. |
| recovery_action | enum | restart_camera, retry_save, discard, return_to_live, open_settings, none, unknown | Lifecycle/recording UI owner | When listed | Closed user/system action | Proposed local only | No settings URL or file path. |
| permission_type | enum | camera, microphone, photo_library, speech, unknown | System permission owner; current app gate incomplete | When listed | Sensitive capability category, no status detail beyond enum | Proposed local only; consent/legal treatment unknown | Do not emit a permission event without an actual status/request result. |
| permission_status | enum | authorized, denied, restricted, not_determined, unavailable, unknown | AVCaptureDevice/photo/audio permission APIs if added | When listed | Capability state | Proposed local only | Direct system result only; no device/account identifier. |
| permission_trigger | enum | system_request, settings_return, status_check, unknown | Permission owner | When listed | Low-cardinality | Proposed local only | Closed enum. |
| consent_decision | enum | accepted, declined, cancelled, unknown | New Deep Review UI owner | When listed | Sensitive consent fact; no legal-basis claim | Retention/transmission/consent scope undecided; proposed local only | Only explicit user action; never provider availability. |
| deep_review_trigger | enum | pause_summary, user_request, verification_uncertain, unknown | State spec S17/S18; coordinator request context | When listed | Low-cardinality product trigger | Provider/endpoint/processor/region/retention unknown; proposed local only | Closed enum. |
| deep_review_payload_class | enum | redacted_visual_metadata, local_semantic_context, unknown | VLMVisualEvidenceRequest privacy tier/context | When listed | Sensitive payload class; deliberately no payload | Transmission and legal approval undecided | Must be a policy-approved class; never serialize the payload into event. |
| deep_review_failure_reason | enum | disabled, offline, network_unavailable, timeout, invalid_response, cancelled, quota_exhausted, provider_unavailable, unknown | VisualSemanticEvidenceCoordinator/Deep Critic status | When listed | Coarse operational reason | Provider/retention/region unknown; proposed local only | Direct status only; no provider error text. |
| deep_review_latency_bucket | enum | 0_1s, 1_3s, 3_10s, 10_30s, 30s_plus, unknown | Coordinator request timestamps | When listed | Coarse timing | Proposed local only | Compute without request ID in event. |
| deep_review_quota_outcome | enum | exhausted, not_available, remaining, unknown | Future allowance owner; no current quota symbol | When listed | Product allowance state | No retention/transmission decision | Do not emit remaining count or credits amount. |
| thermal_state | enum | nominal, fair, serious, critical, unknown | Telemetry.thermalStateString, PerformanceMonitor, ProcessInfo.thermalState | When listed | Coarse device state | Proposed local only | Map directly to OS enum; no hardware model. |
| thermal_change | enum | entered, exited, unchanged, unknown | New edge detector over thermal state | When listed | Low-cardinality | Proposed local only | Emit only on actual state edge. |
| performance_signal | enum | low_fps, high_frame_time, dropped_frames, high_cpu, high_memory, high_latency, feature_degraded, unknown | PerformanceMetrics and approved thresholds | When listed | Coarse operational state | Proposed local only | Thresholds must be versioned; no raw samples. |
| interruption_reason | enum | background, route_change, camera_inactive, permission_lost, system, thermal, memory, unknown | Camera/lifecycle owner | When listed | Lifecycle/system fact | Proposed local only | Direct interruption/status only; no notification payload. |
| recovery_result | enum | recovered, failed, not_attempted, unknown | Camera restart callback | When listed | Low-cardinality | Proposed local only | Match the current lifecycle epoch. |
| section | enum | camera_coach, scene_mode, history, pro_controls, unknown | Router/UI owner | When listed | Low-cardinality | Proposed local only | Closed enum. |
| transition_result | enum | owner_released, owner_acquired, failed, not_attempted, unknown | Future CameraRouteOwner/route lease | When listed | Operational state | Proposed local only | Require explicit owner callback; no inference from view disappearance. |
| history_case_source | enum | current_session, saved_case, deep_review, unknown | Future history owner | When listed | Low-cardinality; no case ID | Persistence model undecided; proposed local only | Closed enum. |
| analysis_source | enum | local_vision, local_semantics, remote_evidence, user_control, unknown | Pipeline/provider/action adapter | When listed | Source category; provider identity excluded | Provider/endpoint/region unknown; proposed local only | Use only when source is directly known; no provider name. |
| case_result | enum | improved, not_improved, worse, keep_as_is, uncertain, result_available, unknown | Verifier/Deep Review/history owner | When listed | Closed result category | Proposed local only | No raw rationale/text. |
| reuse_result | enum | applied, cancelled, unavailable, unknown | Future history action owner | When listed | Low-cardinality | Proposed local only | Direct user action only. |
| derivation_version | string | Exact algorithm version, initially fhll-0.1 | Proposed reducer constant | Required on derived event | Algorithm metadata; no identifier risk | Proposed local only | Reject unknown algorithm version when comparing metrics. |

### 7.3 Explicit unavailable fields

The following are currently unavailable and must not be invented: stable user identity; account identity; install/device identifier; persistent session identity; explicit Coach route lease; user-readable tip impression/read/acceptance; subject choice owner; observable action detector; before/after evidence pair; verification result; exact stability benchmark; recording owner on modern Coach route; photo-library status gate; Deep Review consent UI; Deep Review quota; approved remote provider/endpoint/processor/region; event transport; offline durable queue; retention period; legal basis; App Privacy answers; crash evidence; causal attribution; exact server latency/cost. If an implementation needs one, it needs a new source seam and owner decision.

## 8. Privacy boundary

### 8.1 Hard negative rules

The event contract forbids:

- raw frames, pixels, photos, videos, audio, speech, transcripts, or encoded media;
- free-form scene descriptions, user text, model text, tip copy, explanation text, reasoning traces, or raw error messages;
- bounding boxes, target regions, face data, embeddings, coordinates, labels, or any structure that can reconstruct visual content;
- API keys, authorization headers, endpoint URLs, provider names, processor names, region names, request payloads, or local file paths;
- persistent hidden device/install/account identifiers, identifierForVendor, advertising identifiers, DeviceCheck identifiers, Keychain identifiers, or benchmark run IDs;
- exact GPS, exact hardware model, build paths, high-frequency sensor streams, exact resource samples, or unbounded timing traces;
- assuming that a UUID already present in a local request, suggestion, frame, scene, or benchmark artifact is safe as a product analytics identity.

The proposed session_token is an ephemeral, per-Coach-session UUID only. It is not an account/device/install identifier, is not persisted, is not reused after re-entry, and has no approved transmission or retention policy. Its use remains proposed_for_Sol_decision.

### 8.2 Unknowns deliberately preserved

This audit does not invent a provider, endpoint, processor, region, retention period, legal basis, consent scope, transport, App Privacy declaration, or server cost model. The environment-gated remote VLM path proves that network transmission is technically possible, not that it is a product backend or an approved analytics sink. DeepCriticOffloadingCoordinator proves a contract and tests, not a production provider.

app_crash_or_termination is therefore reserved and not emitted. A missing coach_session_ended, an applicationWillTerminate-style lifecycle callback, or a next-launch flag would not by itself distinguish crash, kill, background eviction, or normal termination. A crash event may be added only after a real crash-evidence owner and privacy-approved destination exist.

## 9. Session and event identity options

The repository already uses UUIDs for local concepts: Suggestion.id, request/correlation values in the visual-evidence contract, source/frame-derived IDs, and device-benchmark-<UUID> run IDs. These UUIDs have different lifetimes and purposes. Reusing any of them would either leak content/operational identity or couple product analytics to a benchmark/request lifecycle.

| Option | Description | Risk | Decision status |
|---|---|---|---|
| A. No identity, sequence only | Events are ordered only within one sink instance. | Cannot safely join a tip/action/verification chain across asynchronous components. | Viable local test sink, insufficient for a production derivation unless the sink is single-owner. |
| B. Ephemeral in-memory session token + sequence | Generate one random UUID on Coach-session acquisition; keep only in memory; pair with monotonic event_sequence; create a new token on re-entry. | Still a pseudonymous identifier if transmitted; requires explicit non-persistence and transmission policy. | proposed_for_Sol_decision; recommended narrowest implementation design. |
| C. Request/frame/suggestion UUID reuse | Reuse existing IDs to correlate events. | Can identify request/frame/scene content, crosses intended lifetimes, and is not a user session identity. | Exclude. |
| D. Persistent install/device/account identity | Add or reuse a stable identifier. | Violates no-persistent-identifier-by-default boundary and expands privacy scope. | Exclude. |

Recommended design: Option B, but initially implement it only in an in-memory/no-op/test sink. The sink must not persist or transmit it until Product, Privacy/Legal, and Infrastructure decide whether any event destination exists. The token lifetime ends on explicit session end, route handoff, permission loss, or background policy termination. The first implementation should not add a new persistent store.

## 10. First-helpful-loop derivation algorithm

### 10.1 Preconditions and missing seams

The reducer consumes normalized events, not raw pipeline logs. It requires:

- coach_tip_stabilized from the actual user-visible stable-tip seam;
- coach_action_detected from an approved closed-catalog action detector or explicit control event;
- coach_verification_completed from an action-linked before/after verifier with verification_evidence_status = before_after_valid and verification_result = improved.

The current repository provides neither the action detector nor the verifier. AnalysisPipeline has live-hint hold/dedup state and pause critique presentation, but those are not sufficient. This algorithm cannot produce a trustworthy activation event until the missing seams are implemented.

### 10.2 Proposed constants

These values are a deterministic proposal, not an accepted product policy:

- STABLE_HOLD = 2.0 s, matching the current AnalysisPipeline.minLiveHintHold seam; the state spec says the product stability interval still needs benchmarking.
- ACTION_WINDOW = 30 s after a stable tip.
- VERIFICATION_WINDOW = 15 s after action detection.
- SESSION_GAP = 0 s across an explicit end/background policy boundary; re-entry creates a new token.
- EVENT_DEDUP_WINDOW = same lifecycle epoch and semantic signature; no wall-clock-only dedup.

ACTION_WINDOW, VERIFICATION_WINDOW, and the interpretation of STABLE_HOLD are proposed_for_Sol_decision and must be versioned in derivation_version when accepted.

### 10.3 Deterministic pseudocode

~~~
state = IDLE
session = nil
candidate = nil
action = nil
verification = nil
completed = false

on event(e):
  reject if e.schema_version is unsupported
  reject if e.event_sequence <= last_sequence for e.session_token
  ignore if e.session_token is closed or lifecycle_epoch is stale
  last_sequence = e.event_sequence

  if e.name == coach_session_started:
    session = new session(e.session_token, e.event_time_ms)
    state = SEEKING
    candidate = nil; action = nil; verification = nil; completed = false

  if e.name in {coach_session_ended, camera_interrupted}:
    close candidate/action/verification
    state = ENDED
    return

  if e.name == coach_analysis_paused:
    invalidate in-flight async generations
    state = PAUSED
    return

  if e.name == coach_analysis_resumed:
    candidate = nil; action = nil; verification = nil
    state = SEEKING
    return

  if e.name == coach_abstained:
    close candidate/action/verification
    state = ABSTAINED
    return

  if e.name == coach_tip_rejected or e.name == coach_tip_dismissed:
    close candidate/action/verification
    state = SEEKING
    return

  if e.name == coach_tip_stabilized:
    if e.tip_category == unknown or e.action_type == unknown:
      return  // not an actionable recommendation
    if duplicate_stable_signature(e):
      return
    candidate = {signature: privacy_safe_signature(e), at: e.event_time_ms,
                 action_type: e.action_type, epoch: e.lifecycle_epoch}
    action = nil; verification = nil
    state = RECOMMENDATION_ACTIVE
    return

  if e.name == coach_action_detected and state == RECOMMENDATION_ACTIVE:
    if e.event_time_ms - candidate.at > ACTION_WINDOW:
      close candidate; state = SEEKING; return
    if e.action_type != candidate.action_type and not approved_equivalent(e):
      state = AMBIGUOUS; return
    if duplicate_action_signature(e):
      return
    action = {at: e.event_time_ms, action_type: e.action_type,
              source: e.action_frame, epoch: e.lifecycle_epoch}
    state = ACTION_OBSERVED
    return

  if e.name == coach_verification_completed and state == ACTION_OBSERVED:
    if e.event_time_ms - action.at > VERIFICATION_WINDOW:
      close candidate/action; state = SEEKING; return
    if e.verification_evidence_status != before_after_valid:
      state = AMBIGUOUS; return
    if e.verification_result in {uncertain, abstained, unknown}:
      state = ABSTAINED; return
    if e.verification_result in {not_improved, worse}:
      state = VERIFIED_NOT_HELPFUL; return
    if e.verification_result == improved and not completed:
      emit first_helpful_loop_completed(
        same_session_token,
        case_result=improved,
        verification_window_bucket=bucket(e.event_time_ms - action.at),
        derivation_version=fhll-0.1)
      completed = true
      state = COMPLETED
      return

  if e.name == coach_keep_as_is:
    close candidate/action/verification
    state = KEEP_AS_IS  // supporting fact, not first_helpful_loop_completed

  if e.name in {deep_review_completed, deep_review_failed,
                deep_review_quota_exhausted}:
    do not change the local helpful-loop state unless an owner explicitly
    maps a validated Deep Review action into coach_action_detected.
~~~

### 10.4 Edge rules

- Ambiguity and abstention: unresolved subject clarification, unknown action, invalid before/after evidence, uncertain, abstained, or unknown cannot complete the loop. A later new stable tip starts a new chain.
- Duplicates: a repeated callback with the same session, lifecycle epoch, event sequence, and semantic signature is ignored. Re-rendering the same SwiftUI value is not an event.
- Interruption: camera interruption, route change, explicit end, permission loss, or a policy-defined background termination closes the chain. No chain crosses a new session token.
- Pause/resume: a pause invalidates pending async generations. Resume starts a new lifecycle epoch; a stale pause result cannot become a tip, action, or verification event.
- Offline: local Coach derivation continues. Deep Review request failure is classified only if a request was actually made. No future retry is counted as the original event and no remote delivery is assumed.
- Causality: the reducer names temporal adjacency only. It must not expose a “tip caused improvement” property.
- Keep as is: coach_keep_as_is is independently measurable. Whether it is a second activation definition is an owner decision, not a reducer side effect.

## 11. Funnel and diagnostic metrics

All metrics must be computed from the normalized event set, at the session-token level, with event/schema/derivation versions fixed. Denominators must be reported with the metric; do not report raw view counts as success.

| Metric | Formula | Interpretation and anti-misinterpretation note |
|---|---|---|
| Permission eligibility | sessions with camera_permission_result = authorized / sessions with a permission result | Measures access, not product value; split denied/restricted/not-determined. |
| Live-entry rate | sessions with coach_live_started / authorized sessions | Does not prove camera quality or user engagement. |
| Stable-tip coverage | sessions with at least one coach_tip_stabilized / live sessions | A missing visible seam makes this unavailable; candidate logs are not a substitute. |
| Tip rejection rate | sessions with coach_tip_rejected / sessions with stable tip | Rejection is not model error without a reason and adjudication. |
| Action follow-through | sessions with coach_action_detected after a stable tip / sessions with stable tip | Temporal sequence only; not proof the tip caused the action. |
| Verification completion | sessions with coach_verification_completed / sessions with action detected | Exclude invalid/stale evidence separately. |
| Verified improvement rate | sessions with valid verification_result = improved / sessions with valid verification result | Does not estimate causal lift or counterfactual benefit. |
| First-helpful-loop activation | sessions with first_helpful_loop_completed / eligible live sessions | Primary KPI proposed here; only valid after action/verifier seams and reducer tests ship. |
| Time to first helpful loop | median bucketed time from coach_session_started to derived event among completed sessions | Report only among completed sessions; missing/aborted sessions are a separate cohort. |
| Abstention rate | sessions with coach_abstained / live sessions | Can be healthy safety behavior; do not optimize down without quality review. |
| Subject clarification burden | sessions with clarification request / sessions with live seeking | Indicates ambiguity; not a user failure or model error by itself. |
| Pause-to-summary rate | sessions with summary shown / sessions paused | Measures state completion, not summary usefulness. |
| Recording completion | recording generations with recording_completed / recording generations with recording_started | Split writer failure, save failure, interruption, and permission; do not infer media quality. |
| Deep Review consent | accepted decisions / consent disclosures | No consent event can be emitted from a provider response; payload and legal scope remain unknown. |
| Deep Review success | completed / requested | Include disabled/offline/timeout/quota denominators; not evidence of user benefit. |
| Deep Review quota exhaustion | exhausted requests / requests reaching allowance decision | Do not expose remaining credits or infer monetization demand. |
| Thermal degradation | sessions with performance_degraded within a thermal episode / sessions with sampled thermal state | Correlation only; report thermal state and feature changes separately. |
| Interruption recovery | recovered camera interruptions / interruptions with a recovery attempt | Not equivalent to session retention or user satisfaction. |
| Stale-result suppression | stale callbacks ignored / async callbacks observed in tests | A reliability diagnostic, not a user outcome. |

## 12. Implementation seam map

This section is a bounded implementation map only. No listed file is modified by this audit.

### 12.1 Candidate emitters and adapter

| Slice | Candidate files/types | Responsibility |
|---|---|---|
| Contract/sink | New analytics-domain types adjacent to Multitool2Module/Services/Telemetry/Telemetry.swift, following project naming; CoachEvent, CoachEventSink, InMemoryCoachEventSink, NoopCoachEventSink | Validate closed enums, event envelope, sequence, dedup, and local-only default. Do not turn Telemetry/OSLog into the sink. |
| Session/route | Resources/SceneDelegate.swift, ContentView.swift, CameraViewModel.swift, CameraManager.startAndWait/stopAndWait/releaseAndWait, future route lease from camera-session-ownership.md | Create/end ephemeral token, route/permission events, lifecycle epoch, consume the accepted serialized CameraManager lifecycle boundary, and close the remaining scheduler/pipeline release gap. |
| Live tip | AnalysisPipeline.swift, CameraViewModel.swift, OverlayView.swift, SemanticTipPlanner.swift | Emit only at visible/stable seam; map action/category enums; never send text/regions/IDs. |
| Action/verification | New reducer/verifier adjacent to Camera Coach domain; inputs from CameraManager.FrameContext, AnalysisPipeline, and explicit controls | Add missing observable change and before/after evidence; reject stale/ambiguous results. |
| Pause/recording | CameraViewModel.togglePause, AnalysisPipeline.runPauseAnalysis, CameraScreenViewController.swift, CameraService.swift, future modern recorder owner | Separate pause summary, writer, save, and failure events; do not mix legacy CameraService with modern Camera Coach without ownership decision. |
| Deep Review | VisualSemanticEvidenceCoordinator.swift, DeepCriticOffloadingCoordinator.swift, future consent/result UI | Emit product state only after an actual UI/provider owner exists; keep provider data out of events. |
| System signals | Telemetry.updateSystemMetrics, PerformanceMonitor, ThermalGovernor | Emit thermal edges and thresholded degradation at low frequency; no raw performance stream. |
| History/sections | SceneDelegate.swift, SORouter.swift, future history owner | Emit section/transition facts only after explicit owner acquire/release callbacks. |

### 12.2 Tests and hazards

Relevant existing tests are CameraOverlayUXPresentationTests.swift, AnalysisPipelinePresentationTests.swift, CameraAnalysisDomainContractsTests.swift, VisualSemanticEvidenceCoordinatorTests.swift, DeepCriticOffloadingCoordinatorTests.swift, DeviceBenchmarkSupportTests.swift, DeviceBenchmarkHarnessTests.swift, and the recording/route coverage in UITests.swift. They need injected sinks or pure reducer fixtures; existing debug/benchmark tests are not analytics acceptance tests.

Concurrency and ordering hazards:

- CC-010A at e0bd423 makes CameraManager.startAndWait(), stopAndWait(), and releaseAndWait() awaitable and serialized; stop/release disable and detach frame delivery and drain the video-output queue, superseding the prior audit wording.
- RealtimeScheduler has register/unregister primitives, but the active AnalysisPipeline registration/release path is not yet deterministic at Coach lifecycle end. CC-010B is in progress; downstream scheduler/pipeline work still needs an explicit unregister/release fence even though CameraManager now fences late camera-frame delivery.
- CameraViewModel.togglePause already has a pauseRequestToken; the event reducer must use the same generation concept or a bridge, never wall-clock proximity alone.
- AnalysisPipeline live-hint stability/expiry state is queue-sensitive; minLiveHintHold = 2.0, liveHintDisplayDuration = 4.0, and motion grace 0.8 seconds are implementation seams, not yet product-approved analytics constants.
- SwiftUI onAppear/onDisappear can repeat without a new product state transition; emission must be at explicit state commits.
- camera interruption, backgrounding, rotation, thermal degradation, and route handoff can overlap; event sequence and lifecycle epoch must serialize them.
- Deep Review results can complete after cancellation, pause, or session end; request generation must fence stale results.
- A local file logger must not be accidentally used as an analytics queue; offline behavior is local no-op/in-memory until a destination is approved.

### 12.3 Bounded implementation slices

1. Contract foundation: closed enums, event validation, ephemeral token, monotonic sequence, dedup, in-memory/no-op sinks, privacy-negative tests.
2. Session and route: explicit Coach session owner, permission result seams, end/background/re-entry policy, lifecycle epoch, and integration with CC-010A’s awaitable CameraManager boundary while CC-010B closes scheduler/pipeline unregister/release.
3. Live coaching: visible tip/stability emission and subject clarification; no action/verification success yet.
4. Action and verification: implement observable action source, before/after verifier, deterministic reducer, and first-helpful-loop derivation tests.
5. Pause/recording: pause summary/resume and recorder writer/save result seams, with legacy/modern ownership separated.
6. Deep Review/system signals: consent/request/result/quota state once product/provider owners exist; low-cardinality thermal/performance edges.
7. Release hardening: route/async race tests, offline/no-remote tests, privacy negative tests, schema fixtures, and acceptance evidence.

## 13. Exact acceptance tests

These are implementation-ready Given/When/Then tests; none is claimed as executed by this analysis-only slice.

1. First verified helpful loop

   Given an authorized live session, a stable closed-catalog tip, a matching observed action within the accepted window, and a valid before/after verification with improved
   When the reducer consumes events in sequence
   Then it emits exactly one first_helpful_loop_completed with case_result = improved, the accepted derivation_version, and no causal property.

2. Candidate is not a tip

   Given repeated SemanticTipPlanner candidates that never cross the visible/stable presentation seam
   When pipeline processing runs
   Then no coach_tip_shown, coach_tip_stabilized, or activation event is emitted.

3. Duplicate emission

   Given the same tip, action, or verification callback is delivered twice with the same lifecycle generation/signature
   When the sink/reducer processes both
   Then it stores/emits one fact and preserves a strictly increasing sequence for distinct facts only.

4. Stale async result

   Given pause analysis or Deep Review request A is superseded by pause/resume, cancellation, or session end
   When result A arrives after generation B is current
   Then result A emits no tip/action/verification/completion event and is recorded only as an internal test diagnostic if such a diagnostic is explicitly allowed.

5. Pause/resume

   Given a live session with a pending recommendation
   When pause commits and later resume commits
   Then coach_analysis_paused precedes coach_analysis_resumed, in-flight chains are invalidated, and a pre-pause tip cannot complete a post-resume loop.

6. No permission

   Given camera permission is denied or restricted
   When the Coach route opens
   Then it emits the permission/unavailable facts only, does not emit coach_live_started, coach_tip_stabilized, action, verification, recording success, or activation events, and emits no permission token or system message text.

7. Offline local loop

   Given no network and no remote provider
   When local Coach evidence produces a valid tip/action/verification chain
   Then local events and derivation are possible in the in-memory/no-op sink; no remote event is queued, retried, or implied. A Deep Review request, if made, emits only its observed unavailable/failure outcome.

8. Thermal state

   Given ProcessInfo.thermalState changes from nominal to serious
   When the edge detector samples the change
   Then it emits one app_thermal_state_changed with the closed enum and emits performance_degraded only after an approved threshold/feature transition; it does not emit raw temperature, device model, or high-frequency samples.

9. Deep Review disabled

   Given Deep Review policy is disabled or provider unavailable and no disclosure/request occurred
   When the user views a local pause summary
   Then no deep_review_completed or quota event is emitted; a failure/unavailable event is allowed only for an actually attempted request.

10. Deep Review consent

    Given the disclosure is visible
    When the user declines
    Then exactly one deep_review_declined is emitted, no request follows, and the event has no provider, endpoint, payload, or legal-basis property.

11. Recording failure

    Given recording starts and the writer or save callback fails
    When failure is committed
    Then recording_failed and, where applicable, recording_save_result(save_result = failure) are emitted once with a closed failure class; no recording_completed or media path is emitted.

12. Interruption and re-entry

    Given a session is live and camera interruption/background causes route release
    When the user re-enters Camera Coach
    Then the old session closes, old async callbacks are ignored, and the new session has a new ephemeral token; no chain crosses the boundary.

13. Keep as is

    Given a valid no-change rationale is visible
    When the user accepts keep-as-is
    Then one coach_keep_as_is is emitted and no first_helpful_loop_completed is emitted unless a separate approved KPI explicitly maps keep-as-is to activation.

14. Privacy negative payloads

    Given a candidate event source contains tip text, labels, a target region, a frame/pixel buffer, transcript, API key, endpoint, file path, benchmark run ID, or persistent identifier
    When the event is validated
    Then validation rejects or strips the event, reports a test failure, and never serializes the forbidden value.

15. No crash inference

    Given a session has no end event before the next launch
    When the app starts again
    Then no app_crash_or_termination event is synthesized and the prior session is not counted as a crash without a real crash-evidence owner.

## 14. Release blockers and owner decisions

| Owner area | Blocker/decision | Why it blocks a trustworthy release metric |
|---|---|---|
| Product | Resolve strict first-helpful-loop activation versus product-plan keep-as-is activation. | Denominator and headline KPI otherwise change by interpretation. |
| Product | Approve exact stable-tip visibility boundary, stability benchmark, action catalog, action evidence, verification semantics, windows, and re-entry policy. | Current pipeline presentation is not enough to prove the loop. |
| Product | Decide whether Deep Review actions can enter the local helpful-loop chain or remain a separate funnel. | Avoids mixing local and remote outcomes. |
| Product | Decide whether History and Scene Mode are part of the Coach session funnel. | Prevents cross-route denominator contamination. |
| Privacy/Legal | Approve whether any event leaves the device; if yes, define provider, endpoint, processor, region, payload class, consent, legal basis, retention, deletion, and App Privacy answers. | None is established by the repository. |
| Privacy/Legal | Approve ephemeral session-token use and explicitly reject persistent identifiers. | Even a random UUID becomes a privacy-relevant correlation key if transmitted. |
| Privacy/Legal | Review existing console/file/model logs for raw media-adjacent content separately. | Excluding logs from analytics does not erase their existing privacy risk. |
| Infrastructure | Choose in-memory/no-op/test sink for first implementation versus an approved durable sink; define offline behavior and delivery guarantees. | Without a sink, metrics are not durable; with an unapproved sink, privacy/retention is unknown. |
| Infrastructure | Define monotonic sequencing, schema storage, clock handling, and stale-event policy. | Async camera/pause/Deep Review callbacks can reorder facts. |
| Infrastructure | Provide a real crash-evidence owner or explicitly keep crash measurement out of this release. | Missing events cannot distinguish crash from termination/background eviction. |
| Implementation | Add route/session lease and lifecycle epoch; use CC-010A’s CameraManager fence and add deterministic scheduler/pipeline unregister/release for recorder and Deep Review callback ownership. | Otherwise duplicate/stale downstream events can corrupt the loop even though camera-frame delivery is fenced. |
| Implementation | Add explicit action detector and before/after verifier seams with test fixtures. | Required primary outcome is otherwise unobservable. |
| Implementation | Add permission/status and recording ownership at the actual modern Coach route. | Existing legacy seams cannot safely be projected onto Coach. |
| Implementation | Add sink injection and privacy-negative tests before any event is enabled. | Prevents accidental raw field or log reuse. |

Until the first four Product decisions, the Privacy/Legal transmission boundary, and the action/verifier implementation seams are resolved, first_helpful_loop_completed is a proposed schema entry only and should not be used for release or subscription/credits decisions.

## 15. Reproducible command appendix

The following command families were used to establish the baseline, locate authority documents, find instrumentation, inspect call sites, and verify source seams. They are reproducible from the repository root; output is intentionally summarized rather than copied into this document.

### Baseline and file inventory

~~~bash
git rev-parse HEAD
git branch --show-current
git status --short
git status --porcelain=v1 -uno
find docs/implementation -maxdepth 3 -type f | sort
wc -l docs/app-store-product-plan.md docs/implementation/STATUS.md docs/implementation/BACKLOG.md docs/implementation/ux/camera-coach-state-spec.md docs/implementation/audits/privacy-permissions-inventory.md docs/implementation/audits/camera-session-ownership.md
~~~

### Authority and state-spec discovery

~~~bash
rg -n 'CC-012|Camera Coach|activation|first.*loop|Deep Review|analytics|telemetry|crash|thermal|record' docs/app-store-product-plan.md docs/implementation/STATUS.md docs/implementation/BACKLOG.md
rg -n '^### S|^## |analytics|tip_stabilized|tip_action_observed|verification|record|Deep Review|thermal|History|section_selected' docs/implementation/ux/camera-coach-state-spec.md
rg -n 'raw|media|frame|photo|video|audio|transcript|identifier|provider|endpoint|region|retention|consent|PrivacyInfo|analytics|telemetry' docs/implementation/audits/privacy-permissions-inventory.md docs/implementation/audits/camera-session-ownership.md
~~~

### Instrumentation and source-seam discovery

~~~bash
rg -n 'Telemetry|CameraLog|DebugMetrics|recordFrameProcessed|recordUIFrame|recordLatency|setCameraStable|thermalStateString' shafinMultitool
rg -n 'PerformanceMonitor|PerformanceMetrics|DiagnosticsLogger|SceneGeneratorDiagnosticsLogger' shafinMultitool
rg -l 'os_log|OSLog|print\(' shafinMultitool
rg -n 'SceneExecutionEventKind|SceneExecutionEvent|SceneExecutionTrace|appendExecutionEvent|DeviceBenchmarkArtifactStore|DeviceBenchmarkMetricsCollector|DeviceBenchmarkCoordinator' shafinMultitool
rg -n 'VisualSemanticEvidenceProviderFactory|RemoteVLMVisualEvidenceProvider|VLMVisualEvidenceRequest|DeepCriticOffloadingCoordinator|MockDeepCriticProvider' shafinMultitool
rg -n 'minLiveHintHold|liveHintDisplayDuration|liveHintMotionHideGrace|liveHintConfidenceDelta|liveHintTextOnlyConfidenceDelta|suggestionExpiry|liveHintShownAt' shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
rg -n 'coach_live_started|analysis_seeking_started|subject_clarification|tip_stabilized|tip_action_observed|tip_verification|keep_as_is|coach_abstained|analysis_paused|record_|deep_review|camera_interrupted|performance_degraded|section_selected|history_' docs/implementation/ux/camera-coach-state-spec.md
rg -n 'UUID\(|identifierForVendor|advertisingIdentifier|DeviceCheck|SecItem|Keychain|PrivacyInfo|Crashlytics|Sentry|Firebase|URLSession|analytics' shafinMultitool
git show e0bd423 -- shafinMultitool/Multitool2Module/Services/Camera/CameraManager.swift shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift shafinMultitool/Multitool2Module/Services/Pipeline/RealtimeScheduler.swift shafinMultitoolTests/CameraManagerLifecycleTests.swift
rg -n 'CameraViewModel|CameraManager|RealtimeScheduler|FrameContext|runPauseAnalysis|applyLiveHint|makeLiveHintPresentation|PauseCritiquePresentation|LiveHintPresentation' shafinMultitool/Multitool2Module
rg -n 'CameraScreenViewController|CameraService|record|save|photoLibrary' shafinMultitool/Services shafinMultitool/SceneGeneratorModule
rg -n 'CameraOverlayUXPresentationTests|AnalysisPipelinePresentationTests|CameraAnalysisDomainContractsTests|VisualSemanticEvidenceCoordinatorTests|DeepCriticOffloadingCoordinatorTests|DeviceBenchmarkSupportTests|DeviceBenchmarkHarnessTests|UITests' shafinMultitool
~~~

The final verification commands required for the worker handoff are:

~~~bash
git diff --check
git diff --name-only 605ae923aa12dbaa7366515abd7ecd5c824c2616 HEAD
git status --short
~~~

The expected post-commit result is exactly one changed path, this file, and a clean worktree.
