# Camera Coach backlog — wave M0

Волна создаёт проверяемую производственную базу. Она не реализует StoreKit, backend или массовый UI-рефакторинг до закрытия соответствующих evidence gates.

## Current orchestration amendment

- Every new executor, reviewer, correction-loop or verification worker MUST be a separate USER-VISIBLE Codex chat/thread, never a hidden collaboration subagent.
- When continuing the current checkout, create the thread in the project-local environment (`environment.type=local`) with explicit `model=gpt-5.6-luna` and `thinking=max`; hidden collaboration spawning is forbidden. If the visible Luna / Max thread cannot be created, fail closed rather than substituting a hidden task or another model.
- The main chat is the sole Sol orchestrator.
- Visible Luna / Max threads own all implementation, testing, correction loops, task-level independent review and verification.
- The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only. It may create/manage visible Luna / Max threads, but MUST NOT create hidden workers or any Sol, Terra or inherited-model worker thread. The installed native adapter is not reinstalled/reloaded, so native roles are not a valid execution path.
- Historical lane labels and evidence below are preserved for traceability. Past references to Sol review/verification or Terra routing are historical evidence only and are not current authorization for a Sol/Terra worker thread.
- The active system goal text is immutable through the goal API while active; the durable amendment is recorded in `docs/aegis/work/2026-08-15-camera-coach-release/10-intent.md` and `20-checkpoint.md`.

## CC-000 — синхронизировать Product и Deep Research

- Lane: Sol.
- State: `accepted`.
- Ownership: `docs/app-store-product-plan.md`, orchestration/tracker docs.
- Result: beachhead narrowed; local core free; public paid model deferred; subscription/credits conditioned on beta; Scene Mode secondary.
- Acceptance: current sections do not require subscription, paid history or paid Scene Mode before evidence.

## CC-001 — Release bundle inventory

- Lane: Luna / Max.
- State: `accepted`.
- Dependencies: bootstrap commit.
- Ownership: create only `docs/implementation/audits/release-bundle-inventory.md`.
- Read: `project.pbxproj`, build phases, asset catalogs, model/resource references, current built app under a fresh worker-derived directory.
- Must report: every file/class over 1 МБ; source path; reason it enters bundle; Debug/Release necessity; license/provenance state; keep/exclude/on-demand/download candidate; exact owning build setting or project reference.
- Must not edit: Xcode project, source, resources or product plan.
- Verification: clean generic Release build with signing disabled if buildable; `du`/bundle inventory commands; `git diff --check`.
- Acceptance: report explains the 1,0 ГБ GGUF, benchmark packs and all material bundle contributors and provides an exact implementation sequence without deleting files.
- Evidence: `docs/implementation/audits/release-bundle-inventory.md`; accepted after correction loop and independent clean/contaminated Release partial-product reconciliation.

## CC-002 — Exclude research assets from Release

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: exact project/resource files named by accepted CC-001; focused regression tests if needed.
- Objective: Release contains only explicitly allowed production resources while DEBUG/device benchmark flows remain reproducible.
- Constraints: no deletion of datasets or models; no loss of test/eval evidence; no change to product behavior beyond resource availability by configuration.
- Verification: Debug build-for-testing; Release build/archive-equivalent; bundle inventory asserts forbidden assets absent and required assets present.
- Acceptance: Release bundle size reduction is measured, resource access fails explicitly outside supported configurations, tests pass.
- Evidence: worker commit `c2b8d4c`, accepted commit `2d7c26e`; parent Release build produced a 72 728 КБ app without `DeviceBenchmark`, `Models` or GGUF, and parent Debug test build retained both nested benchmark manifests plus the Debug marker.

## CC-003 — Privacy and permissions inventory

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/privacy-permissions-inventory.md`.
- Read: usage descriptions, camera/microphone/Speech/Photos call sites, telemetry/offloading code, dependencies and App Store privacy requirements already cited in product docs.
- Must report per permission/data type: trigger, purpose, timing, allowed/denied/restricted behavior, stored/transmitted fields, current user-facing copy, missing tests, privacy manifest/API-reason impact, and exact production owner candidate.
- Must not invent processor, region, retention or legal claims.
- Verification: exhaustive `rg` call-site queries recorded; plist validation; `git diff --check`.
- Acceptance: every permission and external-data path has a disposition and executable follow-up; unknowns are explicit.
- Evidence: `docs/implementation/audits/privacy-permissions-inventory.md`; accepted after path-only diff, plist validation and parent negative/call-site checks.

### CC-003A — Policy-neutral permission capability foundation

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Dependencies: accepted CC-003 audit and CC-008; runtime/UI integration still requires canonical route ownership.
- Ownership: create only `shafinMultitool/Services/Permissions/PermissionContracts.swift`, `shafinMultitool/Services/Permissions/SystemPermissionClient.swift` and `shafinMultitoolTests/PermissionFoundationTests.swift`.
- Objective: provide a deterministic typed boundary for camera, microphone, Speech and Photos add-only authorization/availability without choosing user copy, request timing or fallback UX.
- Contract: `AppPermission` has camera/microphone/speechRecognition/photosAddOnly; authorization preserves notDetermined/authorized/limited/denied/restricted and unknown future status; availability distinguishes available from concrete camera hardware, microphone hardware and Speech service unavailability. Public values are Equatable/Sendable and each snapshot names its permission.
- System behavior: use current iOS 17+ `AVAudioApplication` microphone APIs, `AVCaptureDevice`, `SFSpeechRecognizer` and `PHPhotoLibrary` strictly with `.addOnly`; prompt only from notDetermined; never reprompt denied/restricted/authorized/limited/unknown; return a post-request typed snapshot; keep permissions independent; coalesce concurrent requests for the same permission so one system prompt resolves all waiters; map unknown SDK states honestly.
- Test seam: injectable internal platform boundary with no physical device or real prompt. Tests cover every platform mapping, Photos add-only scope, hardware/service availability independent of authorization, no-prompt terminal states, post-callback result, same-permission coalescing, cross-permission independence and duplicate/late callback safety.
- Non-edits: Camera/CameraViewModel/CameraService/Speech/AR/Scene owners, Overlay/Content/SceneDelegate, UI copy, Settings route, analytics, Info/Privacy manifests, Xcode project, runtime launch and recording/export behavior.
- TDD Route: mode off; decision skipped; normal focused-test verification, no strict RED/GREEN authority inferred.
- Acceptance: generic iOS `build-for-testing` and focused `PermissionFoundationTests` pass; exact three-file diff contains no runtime/UI wiring and makes no claim that the end-to-end permission gate is complete.
- Evidence: worker commit `322faeb`, accepted commit `f246ada`; Sol reviewed the exact three-file diff, passed the integrated generic build and 10/10 `PermissionFoundationTests` on iPhone 17 Pro Max.

## CC-004 — Dependency, model and media provenance inventory

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/dependency-provenance-inventory.md`.
- Read: `Podfile`, `Podfile.lock`, vendored frameworks/packages, Core ML packages, GGUF, images, USDZ/Reality Composer assets and acknowledgements.
- Must report: component, version/hash where observable, runtime role, source, license evidence path, redistribution status, privacy/network behavior, bundle impact and disposition `verified / missing / replace / exclude`.
- Must not assert a license from filename or memory.
- Verification: filesystem/hash/package metadata commands and `git diff --check`.
- Acceptance: every shipped third-party binary/model/media family is covered; missing provenance becomes a blocking follow-up rather than guessed approval.
- Evidence: `docs/implementation/audits/dependency-provenance-inventory.md`; accepted after path-only diff inspection, independent SHA-256 spot checks and explicit separation of repository evidence from legal approval.

## CC-005 — Test topology and UI-test target plan

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/test-topology.md`.
- Read: Xcode targets/schemes, all test files, test host settings, benchmark/UI-labelled tests and existing test documentation.
- Must report: which tests compile/run under which target; UI tests incorrectly living in unit target; conditional skips/false-green risks; simulator/device requirements; exact new UI-test target/file membership/scheme plan; minimal CI matrix.
- Verification: `xcodebuild -list`; build-for-testing; targeted dry enumeration where supported; `git diff --check`.
- Acceptance: report provides a mechanical implementation packet for a true UI-test target and separates unit, integration, benchmark and device-only gates.
- Evidence: `docs/implementation/audits/test-topology.md`; accepted after path-only diff, generic iOS test build and parent workspace enumeration.

## CC-006 — Runtime entry and legacy route audit

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/runtime-entry-routing.md`.
- Read: `AppDelegate`, `SceneDelegate`, `SOModuleBuilder`, scene overview/stage selection, `ContentView`, camera shell entry points and benchmark environment route.
- Must report: launch graph, navigation owners, orientation assumptions, camera owners created per route, persistent-state dependencies, candidate commercial shell seam, routes safe to retire later and required negative tests.
- Must not change navigation or delete legacy code.
- Verification: call graph searches, compile baseline reference and `git diff --check`.
- Acceptance: one lowest-risk seam for Camera Coach default entry is recommended with explicit compatibility and retirement boundaries.
- Evidence: `docs/implementation/audits/runtime-entry-routing.md`; accepted after `git diff --check`, source-citation spot checks and generic iOS `build-for-testing` (`** TEST BUILD SUCCEEDED **`).

## CC-007 — Commercial shell and Camera Coach default route

- Lane: Luna / Max after Sol architecture packet.
- State: `draft`.
- Dependencies: CC-006 and CC-008.
- Ownership: exact shell/entry files selected after audit; no camera/session internals.
- Objective: app opens Camera Coach by default and exposes secondary Scene Mode without duplicating camera ownership.
- Verification: unit/navigation tests, true UI smoke when target exists, portrait/landscape launch checks and Scene Mode saved-project access.
- Acceptance: no scene-first onboarding, no dead end, no regression in opening existing scenes, no vibe-code navigation patterns.

### CC-007A — Single-active-route shell contract

- Lane: Luna / Max.
- State: `accepted`.
- Dependencies: CC-006, CC-008.
- Ownership: create only `shafinMultitool/CommercialShell/CommercialShellViewController.swift` and `shafinMultitoolTests/CommercialShellRoutingTests.swift`.
- Non-edits: `SceneDelegate`, `ContentView`, camera/session internals, Scene Mode routers, recorder, project file and existing UI. This slice does not change the launch graph.
- Contract: `CommercialSection` has exactly `camera`, `scenes`, `history`; `CommercialRoute` exposes one `viewController` and awaited `deactivateAndWait()` returning a typed released/blocked result.
- Behavior: custom single-child container with a system `UITabBar`; Camera selected by default; Scenes and History are lazy; exactly one active child and retained route; selection is disabled during teardown; a blocked teardown retains the current child and selection; rapid taps coalesce to the last pending section; repeated current selection is a no-op.
- Focused tests: default selection, lazy construction, one-child invariant, teardown-before-create ordering, blocked rollback, interaction lock, rapid-tap coalescing, repeat-selection no-op, child containment lifecycle and route release on container teardown.
- Acceptance: deterministic routing contract passes focused tests and generic iOS build-for-testing without changing runtime launch behavior.
- Evidence: integrated Luna / Max run on iPhone 17 Pro / iOS Simulator 26.5 passed generic `build-for-testing`; the ordinary `xcodebuild test` run passed `CommercialShellRoutingTests` 11/11 as part of 19/19. Full evidence and retained diagnostics: `docs/aegis/work/2026-08-15-camera-coach-release/90-evidence.md`.
- Boundary: accepted slice only, not release-ready. The production launch graph/default-route integration and dependent true UI target/default smoke remain outside this slice; full test topology and real-image evaluation remain separate unresolved lanes.
- Rollback: remove the two owned files; no production route is connected by this slice.

## CC-008 — UI/UX state specification

- Lane: Sol owns decisions; bounded Luna tasks may produce artifacts after specification.
- State: `accepted`.
- Ownership: `docs/implementation/ux/**` only until implementation packets are approved.
- Must specify: onboarding, permissions, live Coach, one-tip lifecycle, tap-to-clarify, action detected, before/after verification, keep-as-is, abstention, pause summary, recording, offline, thermal, server consent/timeout/quota, History if retained, Scene Mode entry and both orientations.
- Visual constraints: native hierarchy, semantic system materials/colors, restrained motion/haptics, no dashboard-card grid, gradient-everything, fake AI glow, oversized marketing hero inside tools, decorative glass stacks or arbitrary pill overload.
- Acceptance: every state has entry/exit, primary action, recovery, accessibility, analytics event and screenshot acceptance criteria; no open decision is delegated to Luna.
- Evidence: `docs/implementation/ux/camera-coach-state-spec.md`, commit `c1f6920`; owner acceptance следует из явного поручения запустить полный автономный implementation pipeline и предшествующей серии подтверждённых product/UI решений.

### CC-008A — Truthful production live coaching surface

- Lane: Luna / Max.
- State: `accepted`.
- Dependencies: CC-008, CC-010B.
- Ownership: `CameraOverlayUXPresentation.swift`, `SuggestionChip.swift`, `OverlayView.swift`, `ZoomControlView.swift`, `CameraOverlayUXPresentationTests.swift` and at most one narrow rendering test under existing target membership.
- Non-edits: `ContentView`, `CameraViewModel`, `CameraManager`, `AnalysisPipeline`, `RealtimeScheduler`, `SuggestionListView`, `SceneDelegate`, Scene Mode, recorder, Deep Review, persistence and `project.pbxproj`.
- Supported product states: only live seeking S04, stable tip S06, explanation S07 and keep-as-is S10c, mapped from existing `LiveHint` data. Incomplete payload degrades to one safe line.
- Explicitly unsupported in this slice: onboarding/permissions, subject clarification, action observation, before/after verification, pause summary, recording/save, Deep Review, thermal/offline policy, shell/history and paid state. UI and copy must not imply these exist.
- Surface: one lower-third hierarchy with observation, one physical action and inline `Почему?`; no permanent grid/bounding box, confidence percentage, reserve badge, raw trace/pipeline terms, GOOD/REVIEW labels, card stack, fake AI glow or decorative gradients. Guides appear only when tied to the current action. Debug UI is compiled only under `#if DEBUG`.
- Accessibility: stable identifiers, preview hidden from VoiceOver, icon controls labelled, 44×44 pt targets, Dynamic Type, Reduce Motion and Reduce Transparency behavior.
- Tests: exhaustive presentation mapping, incomplete-payload fallback, negative forbidden-copy assertions (`%`, trace, semantic, reserve, GOOD/REVIEW), deterministic portrait/landscape rendering attachments and focused build/test verification.
- Acceptance: the live surface communicates only evidence the current pipeline actually owns, remains legible in both orientations and passes the banned-pattern/screenshot gates from CC-008.
- Evidence: the same integrated Luna / Max run on iPhone 17 Pro / iOS Simulator 26.5 passed `CameraOverlayUXPresentationTests` 8/8 as part of 19/19; full evidence and retained diagnostics: `docs/aegis/work/2026-08-15-camera-coach-release/90-evidence.md`.
- Boundary: accepted slice only, not release-ready. Unsupported states above, production shell/default-route integration, true UI launch smoke, full test topology and configured real-image evaluation remain outside this slice.
- Rollback: revert only the owned presentation/UI files and focused tests; no camera lifecycle rollback is required.

## CC-009 — Camera/session owner and lifecycle audit

- Lane: Luna / Max audit; implementation remains Luna / Max under the current hard policy. The former Terra / High classification is historical/disabled and is not a current visible-thread route.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/camera-session-ownership.md`.
- Read: `CameraManager`, `CameraViewModel`, recording service, AR camera shell/container, overlays and app lifecycle/orientation hooks.
- Must report: session creation/destruction, queues/actors, frame consumers, record/save owner, background/foreground behavior, rotation path, permission assumptions, thermal/memory controls, duplicated ownership and concurrency risks.
- Verification: call-site graph with exact paths/symbols, current build evidence and `git diff --check`.
- Acceptance: identifies canonical owner candidate and separates mechanical fixes from high-complexity migration work.
- Evidence: `docs/implementation/audits/camera-session-ownership.md`; accepted after path-only diff inspection and parent generic iOS `build-for-testing` (`** TEST BUILD SUCCEEDED **`).

## CC-010 — Camera foundation migration program

- Lane: Luna / Max for bounded mechanics and all current worker threads. The former Terra / High recorder/route-integration route is historical/disabled; no Terra worker thread may be created under the current hard policy.
- State: `decomposed`.
- Dependencies: CC-009; individual slices below add their own gates.
- Objective: one camera/session owner with reliable lifecycle, recording, rotation and resource cleanup.
- Boundary: saved Scene Mode data remains compatible; no StoreKit/backend/UI redesign.
- Verification: focused unit/integration tests, simulator lifecycle tests and required physical-device smoke matrix.

### CC-010A — Awaitable Coach capture lifecycle

- Lane: Luna / Max.
- State: `accepted`.
- Ownership candidate: `CameraManager.swift`, `CameraViewModel.swift`, minimal `OverlayView.swift` call-site changes and focused lifecycle tests selected in the task packet.
- Objective: serialize capture start/stop, make completion awaitable and idempotent, publish typed failure/state, drain/detach the video delegate before stop returns, and prevent post-release frames from reaching the scheduler.
- Non-goals: permissions UI, recording, Scene Mode, route shell, orientation redesign and scheduler/pipeline unregister.
- Acceptance: repeated/racing start-stop tests pass; generic iOS test build passes; existing Camera Coach frame flow remains intact.
- Evidence: worker commit `b93e4aa`, accepted commit `e0bd423`; generic build-for-testing passed, and Sol independently reran `CameraManagerLifecycleTests` on iPhone 17 Pro simulator with 7/7 passing.

#### CC-010A1 — Failed-start registration rollback

- Lane: Luna / Max after CC-010B1 acceptance; Sol verification and acceptance.
- State: `accepted`.
- Task: `01a00683-dd24-72b1-a914-302c7b59db9f`.
- Ownership: `CameraViewModel.swift` and a new isolated `CameraViewModelLifecycleTests.swift`; no `AnalysisPipeline`, `CameraManager`, UI or route edits.
- Objective: when an actual current camera start fails after pipeline registration, await a cleanup boundary that releases those registrations and session-local presentation/evidence before publishing the typed failure; a superseded start must not release a newer retry registration.
- Contract: retries and `releaseAndWait` wait any failed-start rollback; successful start semantics and ordinary pause/stop behavior remain unchanged; failed start leaves zero scheduler registrations; one retry creates exactly three fresh registrations.
- Acceptance: focused failed/superseded/retry/release races and generic build pass. This slice does not add permission UI or classify a system permission itself.
- Evidence: worker `7169d85`, accepted `d7c4e98`; test correction `f49953a`, accepted `9a63f69`. Sol found and corrected one deterministic gated-queue test deadlock plus one scheduler-dependent legacy poll, then independently passed the integrated generic build and 22/22 focused simulator tests: 5 `CameraViewModelLifecycleTests`, 10 `AnalysisPipelineReleaseTests` and 7 `CameraManagerLifecycleTests`.

#### CC-010A2 — Atomic motion snapshot

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a0064f-d087-7b92-9424-8a90cebb989e`.
- Ownership: `MotionGate.swift`, the single `CameraManager.captureOutput` read seam, and new `MotionGateTests.swift` only.
- Objective: every `FrameContext` receives one coherent `{state, shakeLevel, isStable}` snapshot instead of three unsynchronized reads across Core Motion and camera-output queues.
- Contract: immutable Equatable/Sendable `MotionSnapshot`; one lock/serialized publication boundary; `CameraManager` reads exactly once per frame. Preserve current EMA, thresholds, hysteresis, logs and production start/stop behavior. Add an internal deterministic sample seam rather than a second estimator.
- Tests: initial snapshot; exact still/moving/panning hysteresis; coherence invariant; concurrent synthetic updates/reads; CameraManager source check or injectable assertion proving one snapshot read. No physical motion sensor dependency.
- Non-goals: threshold tuning, orientation, permission UI, session lifecycle redesign, new analytics or advice changes.
- Acceptance: focused tests and generic iOS build-for-testing pass; existing lifecycle/scheduler tests remain green.
- Evidence: worker commit `9fb974e`, accepted commit `caef74b`; correction worker `f80e1a3`, accepted correction `b76f217`. Sol independently passed the generic integrated build and 4/4 `MotionGateTests`. The correction preserved production code and replaced a floating-point-unstable exact-`0.40` test input with `0.4001` after proving the inherited EMA rounding path.

#### CC-010A3 — Transactional camera input replacement

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a006a4-5560-7851-acfc-730223da26e8`.
- Ownership: `CameraManager.swift`, new `CameraInputReplacementTransaction.swift` and new `CameraLensSwitchTransactionTests.swift` only.
- Objective: a rejected lens replacement restores the prior active input instead of leaving the capture graph inputless while state still claims the old lens.
- Contract: one session-queue owner; typed async result plus compatibility wrapper; remove/can-add/add/restore transaction commits exactly once; ordinary unavailable/rejected lenses preserve lifecycle and prior input/lens; catastrophic rollback loss is explicit and releases the broken configuration.
- Tests: pure generic operation-order fixtures for replace/restore/rollback failure plus generic iOS build; no fake `AVCaptureDeviceInput`, physical-device claim, UI state or lens matrix.
- Follow-up: CC-010A4 will consume the typed result so `CameraViewModel.currentLens` changes only after confirmed success and rapid taps cannot publish stale state.
- Evidence: worker `85fc422`, accepted `15aa4e5`; exact three-file source review, worker generic build and Sol 16/16 simulator tests across transaction, manager lifecycle and view-model lifecycle suites.

#### CC-010A4 — Confirmed lens presentation state

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a006af-8d1a-7941-a294-84a330bb1e01`.
- Ownership: `CameraViewModel.swift` and new `CameraViewModelLensSwitchTests.swift` only.
- Objective: lens UI state changes only after CC-010A3 confirms the actual active lens; rejected or stale results never highlight an inactive lens.
- Contract: one in-flight waiter plus lifecycle/intent fence; success/no-op use reported active lens; ordinary failure retains reported active lens; nil-active/catastrophic result resets presentation; start/release define wide/empty presentation boundaries; no UI copy before CC-008.
- Tests: no optimistic update, failure retains actual lens, out-of-order rapid requests, release late-result fence, no-op and nil-active mapping; deterministic async operation injection, no physical camera.
- Evidence: worker `993510e`, accepted `b38f9fb`; Sol source-reviewed the exact two-file diff and independently passed 15/15 simulator tests across lens presentation, lens transaction and view-model lifecycle suites.

### CC-010B — Scheduler and pipeline release

- Lane: Luna / Max.
- State: `accepted`.
- Objective: own registration tokens, unregister deterministically, cancel/await outstanding analysis work and fence stale presentation updates.
- Acceptance: register/release/re-register and stale-result tests pass without changing recommendation semantics.
- Evidence: worker commit `1926988`, accepted commit `79f7d1d`. `AnalysisPipeline` owns the three scheduler tokens; registration is rejected during release; unregister, queue/task draining and generation fences make release terminal. Sol independently passed generic simulator `build-for-testing` and 23/23 focused tests across `AnalysisPipelineReleaseTests`, `RealtimeSchedulerTests` and `CameraManagerLifecycleTests`.

#### CC-010B1 — Coherent latest-frame evidence and release reset

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a0064f-3d5a-7452-a196-5ce39f1fae8b`.
- Ownership: `AnalysisPipeline.swift`, new `LatestFrameEvidenceStore.swift`, `LatestFrameEvidenceStoreTests.swift` and narrow additions to `AnalysisPipelineReleaseTests.swift` only.
- Objective: live/pause work consumes one coherent latest-frame envelope and a released/re-registered pipeline cannot emit advice or critique from retained pixels, frame IDs or feature samples of the prior session.
- Envelope: one lock-confined immutable snapshot containing `CVPixelBuffer`, orientation, source frame ID, capture time and stability. High analysis publishes the tuple once; live emit and pause analysis each read one snapshot once; current test replay uses the same seam.
- Release boundary: after unregister and queue/task drain, clear the envelope and reset session-local feature/debug/sample/neural outcomes before marking release finished. Re-register starts empty; no suggestion is emitted until new-session frame evidence exists. Keep generation fences and presentation clearing intact.
- Tests: concurrent tuple writes/reads never mix frame ID/orientation/stability; clear releases the retained buffer and returns nil; release clears evidence and feature samples; re-register/poll before a new frame cannot reuse old evidence; new frame after re-register is accepted; existing 23 focused release/scheduler/camera tests remain green.
- Non-goals: advice thresholds/semantics, Core ML composition, UI, camera ownership, recording, orientation or analytics.
- TDD Route: mode off; decision skipped; normal focused verification only.
- Acceptance: focused store/release suites and generic iOS build-for-testing pass with no stale-frame behavior and no changes outside the owned four files.
- Evidence: worker commit `b38ef12`, accepted commit `8b20380`; correction worker `772fe33`, accepted correction `ee019f0`. Sol independently passed the generic integrated build and 12/12 focused tests: 10 `AnalysisPipelineReleaseTests` plus 2 `LatestFrameEvidenceStoreTests`. The correction changed only the async test poll from a scheduler-dependent yield budget to a bounded three-second wall-clock deadline.

### CC-010C — Serialized recorder ownership

- Lane: Sol decomposes; Luna / Max owns isolated mechanics; one-time production migration remains high-complexity review because `CameraService.shared` crosses current Scene Mode, legacy CameraScreen, audio capture, AR pixel buffers, `AVAssetWriter` and Photos.
- State: `partially_accepted`; policy-neutral core принят, production wiring waits for recording/save/retention policy accepted from CC-008/CC-003.
- Objective: one serialized recorder state machine, awaited finalization, stopped audio capture, typed local-file/Photos result and deterministic cleanup.

#### CC-010C-A — Policy-neutral serialized recorder core

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a00609-a689-7373-b2d4-d0eb245a6c66`.
- Ownership: create only `shafinMultitool/Services/Recording/RecorderContracts.swift`, `shafinMultitool/Services/Recording/SerializedMediaRecorder.swift` and `shafinMultitoolTests/SerializedMediaRecorderTests.swift`.
- Non-edits: current `CameraService`, Scene/legacy Camera call sites, AR container, Camera Coach, lifecycle delegates, project/plist/privacy files, Photos and permissions.
- Contract: typed idle/prepared/recording/finishing/finished/failed/released state; caller-supplied UUID/output URL/audio policy; one serial queue; generation fence for late frames; shared in-flight awaited finish; idempotent release; separate export protocol with no Photos implementation.
- Focused tests: transition validity, writer/audio single start, required/disabled audio, queue confinement, late-frame fence, concurrent/repeated stop, finish failure, no-video result, prepared/recording release, waiter cancellation and absence of automatic re-prepare/export.
- Acceptance: focused tests and generic iOS build-for-testing pass; the owned files have no dependency on current recorder/call sites or Photos; no runtime behavior changes.
- Evidence: worker twice-amended commit `d1277ca`, accepted commit `9b41adf`. Fresh Sol-review found no blocking findings after corrections. Sol independently passed canonical generic iOS Simulator `build-for-testing` and 29/29 focused `SerializedMediaRecorderTests` on iPhone 17 Pro; production app wiring remains intentionally unchanged.
- Boundary: this foundation is not production recording. CC-010C remains incomplete until owner-approved save/retention/background/route-exit policy and a separately reviewed production migration.

### CC-010D — Scene route teardown

- Lane: Luna / Max after CC-010C exposes a stable interface.
- State: `draft`.
- Objective: Scene back/disappear/background awaits recorder policy, pauses/releases AR, then persists through the existing unified project/world-map path.

### CC-010E — Exclusive route lease integration

- Lane: disabled historical Terra / High classification for the one-time cross-route migration; current and subsequent shell slices remain visible Luna / Max threads, with no Terra worker-thread route.
- State: `blocked_by_CC-007`.
- Objective: commercial shell owns a serialized `none / cameraCoach / sceneMode` lease and never activates a new route before the previous owner releases.

### CC-010F — Orientation continuity

- Lane: Luna / Max.
- State: `ready`.
- Dependencies: accepted CC-008 and CC-010A.
- Objective: portrait/landscape reflow and capture/writer/AR transforms change in place without session, analysis, recording or settings reset.

### CC-010G — Stateless thermal budget

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a006b4-a0bf-7e52-b870-bb3c77505063`.
- Ownership: `ThermalGovernor.swift` and `ThermalGovernorTests.swift` only.
- Objective: remove the unused unsynchronized `lastBudget` state so concurrent camera/pipeline/scene budget reads do not race inside the governor.
- Contract: preserve every thermal/battery threshold and frequency exactly; return a fresh immutable budget value; no locks, caches, new owner or product-policy change.
- Tests: exact policy matrix plus bounded deterministic concurrent fixed-provider stress; generic iOS build and focused suite.
- Evidence: worker `3212923`, accepted `6bfd3a4`; exact two-file review and Sol 6/6 focused simulator tests passed, including 2,560 concurrent fixed-provider reads.

## CC-011 — Reproducible release gates

- Lane: Luna / Max.
- State: `decomposed`.
- Dependencies: CC-001, CC-005.
- Objective: documented local commands and CI-ready scripts for Debug test build, focused unit suites, Release build, bundle allowlist, privacy manifest and true UI smoke.
- Ownership: new scripts/config/docs selected after audits; no product behavior.
- Acceptance: a clean checkout can run gates with deterministic pass/fail and without relying on generated files in the developer's home directory.

### CC-011A — App privacy manifest and validation

- Lane: Luna / Max after CC-013A.
- State: `accepted`.
- Ownership candidate: one app-owned `PrivacyInfo.xcprivacy`, focused validation script/tests and exact target membership only.
- Repository evidence: production code uses app-local `UserDefaults`; no app manifest exists; no active analytics SDK, tracking domain or production remote endpoint is configured.
- Required baseline: `NSPrivacyTracking=false`, no tracking domains, app-local UserDefaults category with approved reason `CA92.1`; collected-data declarations must remain evidence-based and must not guess server/provider retention.
- Apple authority: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [required-reason APIs](https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api), [adding a manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).
- Acceptance: `plutil` validation, Release bundle contains exactly the intended app manifest at its root, UserDefaults reason matches executable use, unknown provider/retention decisions remain blocked rather than encoded as false facts.
- Evidence: worker commit `a49c234`, accepted commit `c1e6646`; app manifest declares tracking false, empty tracking domains/collected data and only UserDefaults `CA92.1`. Sol independently rebuilt Release, validated exactly the root app manifest plus SnapKit nested manifest, and passed positive plus missing-root/wrong-reason/unexpected-extra fixtures.

### CC-011B — Deterministic build and bundle gate script

- Lane: Luna / Max after CC-002 and CC-011A.
- State: `accepted`.
- Objective: one documented command produces Debug test build and Release build, validates privacy manifests, checks the release allowlist/denylist, reports material size contributors and fails on DeviceBenchmark, GGUF, unknown model/media families or missing acknowledgements.
- Acceptance: a clean checkout and a deliberately contaminated checkout produce deterministic pass/fail; output paths stay under an explicit derived-data root.
- Evidence: worker commit `1223e01`, accepted commit `f56b7b7`. Public command `scripts/run_release_gates.sh --derived-data-root <explicit-root>` owns only a validated child and runs privacy self-tests, Debug `build-for-testing`, Release build, exact bundle/acknowledgement/provenance/size validation and six copied-app contamination fixtures. Sol independently passed the full command on clean HEAD: Release 71 900 КБ, exactly two privacy manifests, five material contributors, five explicit unresolved provenance blockers and all six negative fixtures.

### CC-011C — Real UI-test target and launch smoke

- Lane: Luna / Max after the CC-007 commercial shell.
- State: `blocked_by_CC-007`.
- Dependencies: implemented CC-007 commercial shell; CC-008 is already accepted.
- Objective: implement the target/file-membership/scheme packet from CC-005 and replace the unit-hosted pseudo-UI smoke with true process-launch tests.
- Acceptance: Camera Coach default launch, permission-state launch arguments, both orientations and Scene Mode entry run in a separate UI-test process.

### CC-011D — Gate accepted provenance records

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a00631-d259-7c22-aa35-7e6ef95e8e1b`.
- Ownership: `scripts/run_release_gates.sh`, `scripts/validate_release_bundle.sh` and at most one narrow shell orchestration test.
- Objective: run the accepted llama artifact-traceability and Circle repository-correlation validators offline before any Xcode build; no ignored checkout, network or legal inference.
- Reporting: llama and Circle remain among the five release blockers, but their technical status is no longer generically unresolved; final summary reports two provenance validators and preserves six contamination fixtures.
- Acceptance: syntax/orchestration tests and canonical full release gate pass on main; a drift in either accepted record stops before Xcode build; existing privacy/build/bundle/safety behavior is unchanged.
- Evidence: worker commit `4802b9c`, accepted commit `7891fec`; fresh Sol-review verdict `ship`. Sol independently passed orchestration fixtures, 15/15 llama tests, 10/10 Circle tests, both real offline validators and the canonical clean-main release gate with 2 validators, 2 privacy manifests, 5 blockers and all 6 contamination fixtures.

### CC-011E — Test and contract hygiene correction wave

- Lane: Luna / Max owns implementation, testing, correction and task-level review/verification; parent/main-chat Sol performs no task-level review and may perform only the one bounded risk-based milestone acceptance.
- State: `accepted`.
- Baseline: `store` at `6ff225d553ae654298dda70b9c779c1226c31800`; CC-011E is committed and accepted after the canonical clean release gate.
- Trigger evidence: the raw full unit target ran 593 tests: 496 passed, 94 failed and 3 skipped. XCResult: `/private/tmp/shafin-main-complete-tests/Logs/Test/Test-shafinMultitool-2026.08.15_21-53-59-+0300.xcresult`. This is an audit result, not a green gate.
- Failure taxonomy: pseudo-UI tests have no target application; opt-in local-model and physical benchmark suites execute by default; Settings fixtures hit force unwraps; real-image Camera Coach evaluation depends on simulator Vision/Espresso and absent never-tracked assets; legacy parser, persistence and fixtures fail independently.
- Integrated evidence: 104 executed, 102 passed, 2 intended skips, 0 failures; XCResult `/private/tmp/shafin-test-hygiene-final-luna/Logs/Test/Test-shafinMultitool-2026.08.15_22-52-30-+0300.xcresult`. Additional repetitions: Scene 18/18 twice plus DB performance 4/4; DeepCritic 20/20; subtitle/config 22 with 1 intended skip; Hybrid 7/7; Semantic 8/8.
- Canonical clean release gate passed all stages on `6ff225d553ae654298dda70b9c779c1226c31800`: Release 72,032 KiB; 2 privacy manifests; only `SnapKit.framework` and `llama.framework`; 5 material contributors; 5 blockers; 2 provenance validators; 6/6 contamination fixtures.
- Next: CC-007A and CC-008A are accepted slices. Continue the remaining parent CC-007 commercial-shell/default-route work and dependent CC-011C true UI target/default smoke as listed in this backlog; full test topology and configured real-image evaluation remain separate unresolved lanes.

#### CC-011E1 — Opt-in execution gates

- State: `accepted`.
- Contract: absent local-model or device-benchmark configuration skips before work begins; explicitly invalid benchmark environment fails rather than silently falling back; configured runs retain their prior semantics.

#### CC-011E2 — Metadata persistence and dialogue presentation

- State: `accepted`.
- Contract: a nil AR map still writes scene metadata while preserving any legacy `_map`; this does not claim an atomic map/data pair transaction. Parser name/phrase arrays are parallel, and presentation renders `Иван: Привет.` rather than exposing the structural colon as content.

#### CC-011E3 — Neural/domain fixture correction

- State: `accepted`.
- Contract: fixtures use canonical signal ordering and exact timestamp relationships; production neural inference semantics are unchanged.

#### CC-011E4 — DeepCritic, Hybrid and Semantic truth

- State: `accepted`.
- Contract: Russian certainty validation catches inflected absolute language while allowing calibrated phrasing; semantic actions outside the live whitelist remain suppressed; Hybrid production remains unchanged and the ranking fixture is made unambiguous.

## CC-012 — Coaching-loop analytics contract

- Lane: Sol defines semantics, Luna / Max implements after UX spec.
- State: `decomposed`.
- Dependencies: CC-008, privacy boundary from CC-003.
- Required events: first verified helpful loop, tip shown/stable/rejected, subject clarification, action detected, verification result, keep-as-is, abstention, record success/failure, Deep Review consent/request/lift/exhaustion, server latency/error/cost and crash/thermal signals.
- Constraints: no raw media or hidden identifier by default; event properties must not claim causality the client cannot observe.
- Acceptance: schema is versioned, testable, privacy-mapped and sufficient for subscription-versus-credits decision after beta.

### CC-012A — Coaching-loop event contract inventory

- Lane: Luna / Max audit; Sol accepts semantics before source implementation.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/coaching-loop-event-contract-inventory.md`.
- Objective: map every accepted/proposed Coach state and observable transition to a low-cardinality, privacy-safe event contract centered on the first verified helpful loop.
- Constraints: no raw media, transcript, free-form user text, hidden persistent identifier, provider/region/retention/legal invention or causal overclaim.
- Acceptance: exact event/property dictionary, deterministic activation derivation, source/test seams, negative privacy tests and bounded Luna implementation slices are all repository-grounded.
- Evidence: worker commit `2c75c53`, accepted commit `7a7c55b`, `docs/implementation/audits/coaching-loop-event-contract-inventory.md`; 12 existing instrumentation owner families, 59 active proposed events, 63 properties and 14 explicit blocker/decision rows. The derived activation event remains unavailable until an observable action seam and independent before/after verifier exist.

## CC-013 — Dependency and provenance remediation

- Lane: Luna / Max for bounded dependency mechanics; Sol/owner for provenance and keep/replace decisions.
- State: `decomposed`.
- Dependencies: CC-004.
- Objective: every executable third-party SDK/framework/model/media family is either supported by concrete release evidence or excluded/replaced.

### CC-013A — Remove ARVideoKit and update SnapKit privacy support

- Lane: Luna / Max.
- State: `accepted`.
- Repository evidence: no production `import ARVideoKit`, `RecordAR` or `RenderAR` call site exists; current SnapKit 5.6.0 has no `PrivacyInfo.xcprivacy`.
- Decision: remove unused ARVideoKit from app dependency graph; update both SnapKit declarations to 5.7.1, whose official release states CocoaPods privacy-manifest support.
- Apple authority: SnapKit appears in Apple’s [SDKs requiring a privacy manifest and signature](https://developer.apple.com/support/third-party-SDK-requirements/).
- Ownership: `Podfile`, `Podfile.lock`, generated CocoaPods workspace/project/support/acknowledgement state only; no app feature source.
- Acceptance: no ARVideoKit link/embed/copy input remains; SnapKit 5.7.1 manifest is present in the built framework/bundle privacy report surface; acknowledgements match; Debug/Release builds and focused camera tests pass.
- Evidence: worker commit `3a7731f`, accepted commit `c4275da`. Debug build-for-testing, Release build and 7/7 `CameraManagerLifecycleTests` passed; Sol independently rebuilt Release on main (71 848 КБ) and confirmed `Frameworks/SnapKit.framework/SnapKit_Privacy.bundle/PrivacyInfo.xcprivacy` plus the absence of ARVideoKit, DeviceBenchmark, Models and GGUF.

### CC-013B — Model/framework provenance decisions

- Lane: Sol/owner decision, then bounded implementation.
- State: `blocked_by_provenance_owner_decisions`.
- Scope: `llama.xcframework`, GGUF release candidate, `compact_neural_evidence_net`, DETR and NIMA.
- Acceptance: each retained component has exact upstream source/checkpoint, conversion/build recipe, checksum and applicable licence/NOTICE evidence; otherwise its consumer and bundle payload are excluded or replaced.

#### CC-013B1 — llama framework technical provenance

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a00603-9514-7ea0-81f3-21361862bc87`.
- Scope: exact upstream URL/commit, preserved verbatim build recipe, historical/current tool metadata, sorted 25-file hash record, MIT notice evidence, offline validator and optional explicit-checkout comparison for `Frameworks/llama.xcframework`.
- Boundary: exact artifact traceability and equality with an existing local build output are proven; a clean deterministic rebuild is not. Legal/redistribution owner approval, archive proof, GGUF selection and all Core ML keep/replace decisions remain open.
- Evidence: worker twice-amended commit `ac97f6e`, accepted commit `d7fff1b`; two independent Sol correction loops removed reproducibility overclaim and a Git-rename false-green. Main passed 15 llama fixtures, both validator modes and 25 combined provenance tests.

#### CC-013B2 — Exclude unproven third-party Core ML from minimal RC

- Lane: Sol decision packet, owner acceptance, then Luna / Max implementation.
- State: `proposed_for_owner_acceptance`.
- Decision: Camera Coach RC ships without DETR object-aware labels, NIMA aesthetic score and compact neural fusion. Apple Vision subject/saliency and deterministic critique remain production signals; absence is represented as unavailable, never fabricated zero/positive confidence.
- Evidence: `docs/implementation/provenance/coreml-model-replacement-research.md`; DETR and NIMA live below `Multitool2Module/Models/CoreML`, compile to app-root `.mlmodelc` and are currently required by the Release validator. The absent compact model already defaults unavailable. Exact-byte Apple-package evidence strengthens DETR provenance but does not validate its pseudo-confidence product contract. NIMA nil/zero/fallback semantics can change preserve/correct decisions inconsistently, and a thrown Vision request can omit its callback and leave pause analysis waiting indefinitely.
- Ownership after acceptance: exact two model exclusions in `project.pbxproj`; explicit nil/off production dependencies in `AnalysisPipeline.swift`; zero-Core-ML Release allowlist and DETR/NIMA/compact contamination fixtures; focused presentation/domain/neural/fusion/critique tests.
- Non-goals: replacement model search, network inference, provenance/legal approval, new advice semantics or removal of Apple Vision/saliency.
- Acceptance: default pipeline requests none of the three models; missing aesthetic/object/neural signals remain unavailable; hard deterministic technical advice is not suppressed by fake scores; Vision subject/saliency paths survive; Release contains zero `.mlmodelc`/`.mlpackage`; focused suites and full release gate pass.
- Owner gate: accept the trade-off that minimal RC has no object-aware DETR labels, no model aesthetic score and no neural fusion. If object-aware coaching is mandatory, DETR needs a separate provenance, output-contract and calibration program instead of this slice.

### CC-013C — Product media provenance or replacement

- Lane: Sol design packet, Luna implementation, owner approval.
- State: `blocked_by_asset_owner_decisions`.
- Scope: material app icon/logo/background images and Person/Circle USDZ assets.
- Acceptance: source/creation/export and permission record per retained asset, or provenance-cleared replacement plus archive allowlist proof.

#### CC-013C1 — Circle source/export technical linkage

- Lane: Luna / Max, Sol verification and acceptance.
- State: `accepted`.
- Task: `01a00603-9514-7ea0-81f3-2140ad032657`.
- Scope: machine-checkable hashes, member sets, metadata predicates and shared UUID establish repository correlation between tracked `Circle.rcproject` and runtime `Circle.usdz`; offline validator and 10 fixtures protect those exact bytes and the evidence boundary.
- Boundary: repository correlation does not prove source-to-export causality. Deterministic export command, author/rights/legal approval, Person provenance and image-family provenance remain open.
- Evidence: worker amended commit `81f50c2`, accepted commit `c8601ba`; Sol reviewer returned no remaining findings after correction, and main repeated 10/10 pytest plus the real validator.
