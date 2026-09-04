# Camera Coach release checkpoint

Дата: 17 августа 2026 года.

## TaskStartSnapshot

- CC-008 Camera Coach first-launch permission packet start: root
  `/Users/unterlantas/Documents/XCode/shafinMultitool`; branch `store`; HEAD
  `a01fed1c1a75d22189852f1c984a56a657f66720`; upstream `origin/store`, ahead
  85 / behind 0. Worktree was clean with no staged, unstaged or untracked
  paths, no active merge/cherry-pick/revert operation, and only the main
  worktree listed. This snapshot preserves the older historical snapshots
  below; it is the baseline for Tasks 1–3 in the approved
  `2026-08-17-camera-coach-first-launch-permission.md` packet.

- Root: `/Users/unterlantas/Documents/XCode/shafinMultitool`.
- Current branch/HEAD at CC-007B start: `store` at `a2eec22f4d1a58a0a8f0639d8462514459b97cfc`; the accepted bounded CC-010D1 implementation baseline remains `f45377b3b4ab39ee79782436afcfb8d644b6a300`.
- Upstream: `origin/store`; the local product branch intentionally contains the accepted orchestration commits not yet pushed.
- Main worktree: no active Git operation; CC-011E remains committed and accepted at `6ff225d553ae654298dda70b9c779c1226c31800`, the bounded CC-007/CC-010E integration is committed at `ff9ce3e02d0f5ec7eb3cedefe2c888a16e0c7b60`, the bounded CC-011C UI slice is committed at `9f2f5f2b9dbd320bc7dc074ef5f66e1334e3496e`, bounded CC-010F orientation continuity is committed at `277170d846fd02ec5740108fc163e2e7c78b8e52`, and the bounded CC-010D1 Scene workspace teardown is committed at `f45377b3b4ab39ee79782436afcfb8d644b6a300`.
- Additional detached Codex worktrees are retained as historical execution evidence; they are not current worker routing or integration owners. A new thread continuing this checkout must use the project-local environment.
- Push, PR, TestFlight/App Store submission, paid actions and legal decisions remain outside automatic authority.

## Durable goal-policy amendment

The active system goal text is immutable through the goal API while it is active. This checkpoint and `10-intent.md` are the durable amendment to that active goal.

- Every new executor, reviewer, correction-loop or verification worker MUST be a separate USER-VISIBLE Codex chat/thread, never a hidden collaboration subagent.
- When continuing the current checkout, create the thread with `environment.type=local`, explicit `model=gpt-5.6-luna` and `thinking=max`; do not use hidden collaboration spawning.
- The main chat is the sole Sol orchestrator.
- Visible Luna / Max threads own all implementation, testing, correction loops, task-level independent review and verification.
- The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only. It may create/manage visible Luna / Max threads, but MUST NOT create hidden workers or any Sol, Terra or inherited-model worker thread.
- If a visible Luna / Max thread cannot be created, fail closed. The installed native adapter is not reinstalled/reloaded, so native Sol Advisor roles are not a valid execution path; never silently substitute a hidden task or another model.
- Past Sol-review or Sol-verification statements below remain historical evidence and are preserved as historical evidence; they do not authorize current task-level Sol review or routing.

## Completed

- Sol Advisor logical project profile is `ready`; its Luna / Max app-task setting is descriptive configuration evidence, not the current hidden execution route.
- Product/Deep Research baseline and M0 tracker are accepted.
- Release research contamination is excluded: GGUF and DeviceBenchmark remain available to development paths but absent from Release.
- Privacy manifest, deterministic clean-HEAD Debug/Release bundle gate and six contamination fixtures are accepted.
- ARVideoKit is removed; SnapKit privacy evidence is accepted.
- llama artifact traceability and Circle repository correlation have machine-checkable offline validators; neither record is a legal approval.
- The local release gate runs both provenance validators before Xcode and still reports five honest legal/provenance blockers.
- Latest authoritative local technical release gate: current `store` HEAD `eac5b47d4ab5ab21975280ae3a9959b4f25c936b`, after the docs-only UI-authority decision. The rejected system `UITabBar` was not changed in code; no replacement UI is claimed implemented or validated. Command: `scripts/run_release_gates.sh --derived-data-root /private/tmp/shafin-release-gate-luna-p74j9XMN`; exit 0, `dirty=false`; `git diff --check` was clean before and after. Stages 1–8 all passed: preflight, llama provenance, Circle provenance, privacy self-test, Debug build-for-testing, Release build, bundle validation and contamination fixtures. Logs/report root: `/private/tmp/shafin-release-gate-luna-p74j9XMN/shafin-release-gates`.
- Latest gate values: `TOTAL_APP_KIB=72868`, `MANIFEST_COUNT=2`, `MATERIAL_CONTRIBUTOR_COUNT=5`, `KNOWN_BLOCKER_COUNT=5`; 2 provenance validators passed and contamination fixtures passed 6/6. Material contributors: `Assets.car` 2,296 KiB; DETR weights 41,748 KiB; `llama.framework/llama` 4,420 KiB; NIMA weights 6,268 KiB; app executable 16,508 KiB.
- Drift versus retained baselines is +836 KiB versus `6ff225d553ae654298dda70b9c779c1226c31800` (72,032 KiB) and +764 KiB versus historical host-retry `5e5dfef859c7db220864076aead9c0de44181a8d` (72,104 KiB); counts are otherwise unchanged. A technical gate pass does not establish legal, physical-device, App Store or product-release readiness.
- The latest gate still reports five hard blockers, all `license_approved=false`: `llama.framework` redistribution approval/archive-notice scope; DETR model provenance; NIMA model provenance; `Circle.usdz` creator-rights/export causality; and `Person.usdz` provenance. These remain owner/legal/product gates.
- Historical release evidence remains retained: the earlier clean gate passed on `6ff225d553ae654298dda70b9c779c1226c31800`, and the host-retry gate passed on clean HEAD `5e5dfef859c7db220864076aead9c0de44181a8d` with `TOTAL_APP_KIB=72104`; the previously documented exit 66 was a sandbox/Xcode/CoreSimulator host restriction, not a repository failure.
- Camera capture lifecycle and scheduler/pipeline release are awaitable, idempotent and covered by focused tests.
- Policy-neutral serialized recorder core is accepted after correction loops and 29/29 simulator tests.
- Policy-neutral permission foundation is accepted after Sol review, integrated build and 10/10 simulator tests.
- Coherent latest-frame evidence/session reset and atomic motion snapshot are accepted after two evidence-driven correction loops; 12/12 and 4/4 focused tests pass respectively.
- Failed camera starts now await a shared pipeline rollback before publishing failure; retry, stale-start and release races are accepted after a correction loop, generic build and 22/22 intersecting tests.
- CC-008 UX state specification is owner-accepted by the explicit instruction to launch the full autonomous implementation pipeline and the earlier affirmative product/UI decisions. CC-007A and CC-008A are accepted implementation slices with bounded evidence; they are not release-ready.
- Historical pre-`f45377b` CC-007 normal Camera Coach launch and bounded CC-010E lease integration are accepted at `ff9ce3e`: the normal non-benchmark `SceneDelegate` branch opens the commercial shell with Camera selected while benchmark remains first; Camera `stopAndWait` is awaited before route removal/next construction and repeated deactivation shares one task; at that baseline deeper Scene workspace/modal transitions blocked without constructing Camera because no awaitable Scene teardown existed. Generic workspace build-for-testing passed at `/private/tmp/shafin-cc010e-derived`; focused workspace tests passed 22/22 (11 `CommercialShellLaunchCompositionTests`, 11 `CommercialShellRoutingTests`). The current deep-workspace evidence is recorded below.
- CC-011C bounded true-process UI evidence is accepted at `9f2f5f2`: the new `shafinMultitoolUITests` target is a shared-scheme member with neither `TEST_HOST` nor `BUNDLE_LOADER`, replacing the unit-hosted pseudo-UI test. DEBUG-only `SHAFIN_UI_TESTING=1` composes the real `CommercialShellComposition` / `ContentView` with the existing deterministic `CameraManager` failure `.noWideCamera`; the benchmark branch remains first, no permission/hardware prompt is requested, root/analysis are not faked and the path is absent from Release. Workspace `build-for-testing` succeeded. `/private/tmp/shafin-cc011c-ui-tests-20260816.xcresult` records 4/4 passed with 0 failures on iPhone 17 Pro / iOS 26.5: normal Camera shell, real Scene library root → Camera return, portrait root no crash and landscape root no crash. This does not claim full portrait behavior, camera permission UX, live capture continuity, completed analysis, deeper Scene workspace switching, full-suite health, physical-device behavior or release readiness.
- CC-010F bounded orientation continuity is accepted at `277170d`: Camera Coach supports portrait/landscape; `CameraManager` maps and applies orientation on the existing session queue without reconfigure/restart; `Overlay` observes rotation; the AR container refreshes viewport/display transform in place. The target allows all orientations, while `CommercialShell` forwards active child policy: Camera Coach all, Scene navigation landscape-only, including the blocked deep Scene route. Workspace `build-for-testing` passed; CameraManager lifecycle/orientation tests passed 10/10; the UI portrait→landscape transition passed 1/1; shell tests passed 23/23 (12 launch composition + 11 routing). This does not claim physical-device camera/AR behavior, `CameraService` writer metadata/transforms, deep Scene workspace rotation, recorder behavior, full-suite health, legal clearance or release readiness.
- CC-010D/CC-010E bounded awaitable Scene teardown is partially accepted at `f45377b`: `SceneGeneratorViewModel` is the real workspace owner; one idempotent operation stops active legacy recording/playback, awaits the unified project/world-map snapshot and pauses AR plus clears the delegate/detaches the AR view only after success; repeated/concurrent callers share one task. Typed snapshot/persistence failures block without constructing Camera and retain the deep Scene route. The actual `LandscapeHostingController` created by `SORouter` supplies the provider; successful route teardown reduces navigation to the Scene library root before release. Presented Scene modals block before teardown; `SceneGeneratorView.onDisappear`, scenePhase background and the route background hook invoke the same operation, without a guarantee of background execution time. Coordinator acceptance evidence is 31/31 passed, 0 failed, 0 skipped; worker focused teardown/composition evidence is 20/20, existing routing is 11/11 and generic iOS build-for-testing passed across 6 targets. CC-010D/CC-010E remain partial.

## Active slice

The accepted CC-011E baseline is `6ff225d553ae654298dda70b9c779c1226c31800`; the bounded CC-007/CC-010E launch integration is `ff9ce3e02d0f5ec7eb3cedefe2c888a16e0c7b60`, and current clean HEAD at CC-007B start was `a2eec22f4d1a58a0a8f0639d8462514459b97cfc`. CC-011E test/contract hygiene is committed and accepted; CC-008, CC-007A, CC-008A, the bounded CC-007/CC-010E slice, the bounded CC-011C real UI target/root smoke, bounded CC-010F orientation continuity and bounded CC-010D/CC-010E awaitable teardown are accepted within their stated boundaries. CC-007B rail acceptance is invalidated by the owner; its implementation and evidence remain historical. The fullscreen CC-007C candidate slice is present in the current handoff but remains blocked pending upright iOS 26.5 UI artifacts; CC-013B2 Core ML composition remains owner-gated.

Slice Card:

- Goal: implement CC-007B Tasks 1–3 as one bounded SnapKit/UIKit commercial-shell visual restoration, preserve route ownership and awaited teardown, and reconcile evidence without claiming release readiness.
- Parent plan/spec: `docs/aegis/plans/2026-08-17-camera-coach-snapkit-shell.md`.
- Files: the plan-owned switcher, shell, focused/unit/UI tests, History composition and five tracker/evidence files only.
- Boundary: no Camera Coach SwiftUI redesign, permissions, Scene Mode redesign, recorder, persistence, backend, monetisation, legal/provenance, physical-device or App Store work.
- Verification: exact focused shell command passed 30/30 (7 switcher, 11 routing, 12 launch composition), exact production UI smoke passed 6/6, exact generic workspace `build-for-testing` passed, `git diff --check` is clean, and four final XCTest screenshot attachments were exported and inspected on iPhone 17 Pro / iOS Simulator 26.5. XCResults and attachment paths are recorded in `90-evidence.md`.
- Stop: CC-007B bounded implementation/evidence is complete; keep full-suite, physical-device, legal/provenance, privacy, monetisation, provider and release gates separate and unresolved.

## Blockers

- CC-013B2 owner acceptance blocks removal of DETR/NIMA/compact neural dependencies from the minimal RC.
- Full default test topology remains unresolved: Settings crashes and configured real-image evaluation are not fixed by CC-011E; the pre-CC-011C raw audit remains historical evidence.
- CC-010D/CC-010E remain partial after `f45377b`: the tested awaitable deep-workspace route is recorded, but modal handling, physical-device AR/world-map behavior, actual OS background allowance, recorder finalization/media policy, the full Scene Mode user journey, UI physical evidence, full-suite health, legal/provenance and privacy/release readiness remain open.
- Exact-binary llama redistribution/archive decision, Circle/Person/image rights, physical-device matrix, Apple credentials, server privacy/provider choices and paid infrastructure are external or owner-gated.
- These blockers do not authorize a narrower product or a false release-ready claim.

## Next

1. Keep CC-007B bounded; its implementation, focused/UI/build verification and visual evidence are recorded in `90-evidence.md` and the final Git receipt. Continue only independent release/product gates without broadening this slice.
2. Keep the remaining CC-010D/CC-010E modal/background/media/product boundaries, full test topology and real-image evaluation as separate unresolved lanes; obtain the independent CC-013B2 minimal-RC decision before changing Core ML composition.
3. Continue remaining production gates without claiming physical-device camera/AR behavior, CameraService writer metadata/transforms, deep Scene workspace rotation, recorder behavior, full-suite, beta, signing, provider, payment or legal/release evidence prematurely.

The next work remains the current `BACKLOG.md`; this checkpoint introduces no new implementation plan.

## CC-008 first-launch permission packet — Task 1 checkpoint

- Task 1 is complete: `CameraCoachEntryFlowModel` owns only entry phase and
  intro persistence, reuses `PermissionClient`, maps camera availability and
  authorization deterministically, and coalesces concurrent explicit camera
  requests. No camera/session or other-permission owner changed.
- Evidence: the packet command for
  `CameraCoachEntryFlowModelTests` passed 7/7, 0 failures and 0 skips on iPhone
  17 Pro / iOS Simulator 26.5; XCResult
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-ggusvwzgvdkcfbfwrnkapympkreb/Logs/Test/Test-shafinMultitool-2026.08.17_19-54-46-+0300.xcresult`.
- Drift check: intent lock, camera-only scope fence, single permission adapter,
  one intro key and no automatic request remain intact. New owner count is one;
  no fallback, route, lifecycle or Release test seam was added.
- Next: implement S01/S02/S03 presentation and gate `OverlayView` on `.ready`.

## CC-008 first-launch permission packet — Task 2 checkpoint

- Task 2 is complete: `CameraCoachEntryView` renders restrained S01/S02/S03
  states with stable accessibility IDs, honest blocker copy, Settings fallback
  handling and no camera-preview/live-control surface. `ContentView` owns one
  entry model and only renders the existing `OverlayView` for `.ready`.
- Evidence: the exact parallel focused command reached the known iOS 26.5
  `simctl diagnose` host stall before test output. The bounded serial rerun
  with `-parallel-testing-enabled NO` passed 19/19, 0 failures and 0 skips on
  iPhone 17 Pro / iOS Simulator 26.5: 7 entry-model, 7 presentation and 5
  CameraViewModel lifecycle tests; XCResult
  `/tmp/shafin-cc-task2-derived/Logs/Test/Test-shafinMultitool-2026.08.17_20-05-34-+0300.xcresult`.
- Drift check: only ContentView and the new entry presentation/test owners
  changed; permission foundation, camera/session owners, route ownership and
  Release composition remain untouched. No fake preview, card/pill/material
  surface, extra permission or fallback camera start was introduced.
- Next: add deterministic DEBUG/UI-test launch state injection, real process
  state assertions and screenshot evidence.

## CC-008 first-launch permission packet — Task 3 checkpoint

- Task 3 is complete within the approved packet: the existing DEBUG
  `SHAFIN_UI_TESTING=1` composition now accepts explicit camera snapshot and
  intro-seen launch arguments through a DEBUG-only test client/store. Release
  composition is unchanged. The real process UI class covers S01 → S02,
  authorized returning users and denied/restricted/unavailable recovery; no
  Settings app, system alert or real hardware permission is automated.
- Host history is retained honestly: the initial UI invocation built but the
  iOS 26.5 XCTest runner failed to launch with
  `FBSOpenApplicationServiceErrorDomain`/`RequestDenied` and produced no test
  result. The first bounded serial run reached the app and exposed a real S03
  layout assertion because Recheck was outside the scroll surface; it was
  stopped by the deliberate timeout after incomplete execution. The narrow
  denied rerun then passed 1/1 after moving both recovery actions into the
  same entry layout.
- Evidence: the final bounded serial UI command passed 6/6, 0 failures and 0
  skips on iPhone 17 Pro / iOS Simulator 26.5; XCResult
  `/tmp/shafin-cc-task3-ui-full/Logs/Test/Test-shafinMultitool-2026.08.17_20-18-50-+0300.xcresult`.
  Generic no-sign `build-for-testing` passed with
  `CODE_SIGNING_ALLOWED=NO`; log `/private/tmp/shafin-cc-task3-build.log`.
  Five PNG attachments were exported to
  `/private/tmp/shafin-cc-task3-ui-full-attachments` and inspected.
- Visual result: S01, S02 and denied S03 are portrait `1206×2622`, readable,
  neutral and free of cards, pills, material/blur, gradients, shadows, fake
  camera preview and dashboard/navigation chrome. The ready attachment is
  existing Overlay evidence only. Landscape is `2622×1206` but rotated and
  vertical on black, reproducing the known iOS 26.5 capture defect; it is
  `blocked_by_host_capture`, never accepted as landscape UI evidence.
- Drift check: only the packet-owned entry files, `ContentView`, the DEBUG
  `SceneDelegate` seam, focused tests and named tracker/evidence documents
  changed. Camera/session owners, permission foundation, routes, Scene Mode,
  Release composition and other permissions remain outside scope.
- Next: keep the landscape host/device visual gate, physical-device camera and
  permission behavior, full-suite health, provenance/privacy and release
  acceptance as separate unresolved gates.

## CC-008 correction loop — TaskStartSnapshot

- Scope: P1 foreground recovery after Settings; root `/Users/unterlantas/Documents/XCode/shafinMultitool`; branch `store`; HEAD `ec364154e56268619cd3a9f48b7efb0044f0d4b3`; upstream `origin/store`, ahead 86 / behind 0.
- Baseline state: worktree clean with no staged, unstaged or untracked paths; no active merge/cherry-pick/revert operation; only the main worktree listed. This correction owns `ContentView` lifecycle wiring plus minimal focused/UI proof and evidence updates; it does not add a permission or camera owner.
- Symptom/root: after Settings changes denied camera access, the one-shot initial `.task` never re-runs and the existing `recheckCameraAccess()` is reachable only through manual Recheck. The canonical repair boundary is an app-active transition observed by `ContentView` while the entry phase is not `.ready`.
- Next: implement and verify one non-ready active-transition recheck with no render-driven duplicate requests.

## Drift check

- Goal alignment: `continue`; full Camera Coach RC remains the goal.
- Scope: no replacement with a merely buildable or test-only subset.
- Baseline: product plan, STATUS, BACKLOG and accepted audits were re-read from current main.
- Compatibility: saved Scene Mode data and existing routes remain protected.
- Owner boundaries: CC-013B2 and legal/privacy/provider/payment decisions remain explicit; CC-008 is accepted.
- CC-007B evidence is historical only: its focused tests, UI smoke and attachments are retained but the rail and claimed landscape visuals are invalidated. CC-007C focused control/routing/composition tests pass 31/31, while the required true UI class has not produced an accepted upright landscape artifact; full-suite, physical-device, legal/provenance, privacy, monetisation, provider and release readiness remain unclaimed.
- Evidence state: the latest authoritative local technical gate is the `eac5b47` run recorded above and in `90-evidence.md`: exit 0, `dirty=false`, `git diff --check` clean before/after, all eight listed stages passed, `TOTAL_APP_KIB=72868`, `MANIFEST_COUNT=2`, `MATERIAL_CONTRIBUTOR_COUNT=5`, `KNOWN_BLOCKER_COUNT=5`, 2 provenance validators and 6/6 contamination fixtures. Its +836 KiB drift versus `6ff225d` and +764 KiB drift versus `5e5dfef` is recorded with unchanged counts. Five `license_approved=false` owner/legal blockers remain; this technical pass does not establish legal, physical-device, App Store, product-release or full-suite readiness. The raw full unit target remains unresolved at 593 total / 496 passed / 94 failed / 3 skipped; do not claim it green. CC-011E integrated Luna evidence remains 104 executed / 102 passed / 2 intended skips / 0 failures at `/private/tmp/shafin-test-hygiene-final-luna/Logs/Test/Test-shafinMultitool-2026.08.15_22-52-30-+0300.xcresult`; CC-007A/CC-008A focused evidence is 19/19 on iPhone 17 Pro / iOS Simulator 26.5, with known non-fatal diagnostics retained in `90-evidence.md`. The bounded `ff9ce3e` launch evidence is historical pre-`f45377b`: generic workspace build-for-testing at `/private/tmp/shafin-cc010e-derived` plus 22/22 focused workspace tests at `/private/tmp/shafin-cc010e-workspace-derived/Logs/Test/Test-shafinMultitool-2026.08.16_00-55-36-+0300.xcresult`; the bounded CC-011C evidence is recorded in `90-evidence.md` with 4/4 true-process tests passed on iPhone 17 Pro / iOS 26.5 at `/private/tmp/shafin-cc011c-ui-tests-20260816.xcresult`; bounded CC-010F evidence at `277170d` is workspace build-for-testing, CameraManager lifecycle/orientation 10/10, UI portrait→landscape 1/1 and shell 23/23 (12 launch composition + 11 routing). Current CC-010D/CC-010E evidence at `f45377b` is 31/31 passed, 0 failed, 0 skipped on iPhone 17 Pro / iOS Simulator 26.5, with focused teardown/composition 20/20, routing 11/11 and generic iOS build-for-testing across 6 targets. This partially accepts the awaitable contract only; it does not establish modal handling, physical-device AR/world-map behavior, actual OS background allowance, recorder finalization/media policy, the full Scene Mode user journey, UI physical evidence, full-suite health, legal/provenance, privacy or release readiness.

## 2026-08-26 autonomous continuation — camera interruption/retry

- Scope: exact-session `AVCaptureSession` interruption/runtime-error recovery,
  atomic start/failure transitions, shared release identity and stale-intent
  fencing. No route, accessibility identifier, Visual Policy owner, recorder,
  persistence schema or Git lifecycle changed in this slice.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: `CameraManagerLifecycleTests` plus
  `CameraViewModelLifecycleTests` exited 0 with 27/27 listed tests passed.
- Release simulator build with `CODE_SIGNING_ALLOWED=NO` exited 0. Existing
  deprecation, launch-storyboard and `Circle.rcproject` warnings remain
  non-fatal and are not treated as resolved.
- A fresh Sol / High reviewer returned `ship` after inspecting the corrected
  atomic claim/final-start boundary and release-operation identity. The five
  reviewed file hashes were unchanged across the review; host-enforced
  read-only isolation was not observable, so before/after hashes are the
  isolation evidence.
- Drift decision: `continue`. The next slice reuses the accepted
  `SerializedMediaRecorder` and permission foundation; it must not introduce a
  second recorder owner. Physical-device interruption timing remains unproved.

## 2026-08-26 autonomous continuation — native REC foundation

- Added the concrete Apple adapters behind the existing
  `SerializedMediaRecorder`: H.264 video, optional mono AAC audio, unique local
  Pending `.mov` artifacts and explicit tri-state append handling. Recording
  remains local; this layer never requests Photos or exports automatically.
- AVCapture audio timing is converted from the session synchronization clock to
  the host clock before writer normalization. Reentrant stop from the capture
  queue avoids synchronous self-dispatch. Recorder generation fences reject
  stale video/audio callbacks after stop or release.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 40/40 focused recorder/Apple-adapter
  tests passed; a no-sign Release simulator build exited 0; `git diff --check`
  passed. iPhone 17 Pro and physical devices were not used.
- Fresh Sol / High audit verdict: `ship`, findings none. The six reviewed file
  hashes matched before and after review. Physical microphone startup, A/V
  alignment, interruptions and hardware timing remain an explicit device gate.
- Drift decision: `continue`. The next package must replace `CameraService`
  only in the reachable Scene/AR recording path, feed frames before the
  analysis throttle and await finalization before workspace persistence.

## 2026-08-26 autonomous continuation — reachable Scene/AR REC integration

- `SceneRecordingController` is now the sole reachable raw-camera recorder
  owner in the Scene/AR workspace. Explicit REC requests microphone access,
  denial creates no recorder, and raw AR buffers enter the recorder before the
  analysis throttle without a per-frame MainActor hop.
- Start publishes `.recording` only after submitting the initial video frame.
  Ordinary stop remains reusable; route teardown awaits stop, terminal release,
  playback stop, persistence and AR detach in that order. Concurrent
  stop/release callers share the same identities.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 16/16 focused controller, teardown and
  AR interruption tests passed; the no-sign Release simulator build exited 0;
  `git diff --check` passed.
- The first fresh Sol / High review returned `fix-first` for initial-frame
  publication and non-terminal route teardown. Luna / Max corrected both,
  verification was repeated, and a new fresh Sol / High reviewer returned
  `ship` with no findings. Reviewed hashes were unchanged after the final
  review.
- Visual Policy recorder ownership was synchronized from legacy
  `CameraService` wording to `SceneRecordingController` backed by
  `SerializedMediaRecorder` and the Apple adapters. No ADR was required.
- Drift decision: `continue`. Physical microphone capture, A/V sync,
  orientation, interruption timing, thermal behavior, Photos export and HUD
  compositing remain outside simulator proof. The next slice corrects the
  Camera Coach presentation boundary so validated object/technical instructions
  are not replaced or hidden by UI mapping.

## 2026-08-26 autonomous continuation — truthful Camera Coach live copy

- The live UI no longer rebuilds physical instructions from `ActionTypeV1`.
  Sanitized `LiveHintPresentation.text` now remains authoritative through
  `CameraOverlayUXPresentation` and the production SET command band, so an
  object-motion instruction cannot become a camera-motion instruction.
- Technical hints with `actionType == nil` render as text-only stable tips.
  Optional explanation fields add Why only when present; every present unsafe
  expanded string invalidates the whole hint. Nil-action hints never receive
  ungrounded marker geometry.
- Seeking, keep and fallback copy is selected only from validated presentation
  state and continues through String Catalog. Runtime action/explanation uses
  `Text(verbatim:)`; the enum-copy mapper remains only in the pause-summary
  path.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 13/13 focused presentation tests
  passed; a clean-derived-data no-sign Release build exited 0; `git diff
  --check` passed.
- Two fresh Sol reviews returned `fix-first` for absent-vs-unsafe expanded copy
  handling; Luna / Max corrected both contracts, parent verification was
  repeated after each correction, and the final fresh Sol / High reviewer
  returned `ship` with no findings. Final hashes were unchanged after review.
- Drift decision: `continue`. Upstream producer domain copy remains Russian in
  an English UI and is an explicit localization release blocker; reintroducing
  enum rewriting is not an acceptable workaround. The next slice moves to
  teardown/persistence data safety.

## 2026-08-26 autonomous continuation — retryable workspace teardown

- A blocked workspace teardown no longer poisons its coordinator cache. All
  concurrent callers still share one in-flight attempt, but the next route
  request may retry persistence; a released teardown remains cached and
  idempotent.
- `SceneGeneratorViewModel` restores automatic-persistence suppression after a
  blocked teardown, so retaining the workspace cannot silently disable later
  user saves.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 11/11 focused teardown tests passed;
  a no-sign Release simulator app was produced; `git diff --check` passed.
  iPhone 17 Pro and physical devices were not used.
- Fresh Sol / High audit verdict: `ship`, findings none. The reviewed hashes
  were unchanged after review.
- Drift decision: `continue`. A failed route persistence attempt still leaves
  the recording controller terminal while the workspace remains visible. The
  next data-safety slice makes project and world-map persistence one atomic
  write; recorder reinitialization remains a separate lifecycle follow-up.

## 2026-08-26 autonomous continuation — atomic scene persistence

- Unified scene metadata and an optional archived `ARWorldMap` now live in one
  authoritative JSON envelope written with a single atomic replacement. A
  successfully written envelope retires the legacy sidecar best-effort.
- Legacy raw-project JSON and its sidecar remain readable until the next save.
  New nil-map envelopes never consult a stale sidecar. Format selection is
  explicit, and the embedded project UUID must match `<UUID>_project.json`
  before load or deletion can touch a sidecar.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 6/6 focused persistence tests passed;
  a no-sign Release simulator app was produced; `git diff --check` passed.
- The first fresh Sol / High audit returned `fix-first` for permissive format
  fallback and missing filename-ID validation. A fresh Luna / Max correction,
  repeated parent verification and a new fresh Sol / High audit closed both;
  final verdict `ship`, findings none.
- Drift decision: `continue`. A real non-nil `ARWorldMap` archive/unarchive
  remains physical-device evidence. The next autonomous blocker is sensitive
  screenplay/marker/live-decision output in Release logging.

## 2026-08-26 autonomous continuation — Release print privacy gate

- A Release-only module-level overload now suppresses every current
  unqualified Swift `print` emission in the app target. Debug does not compile
  the overload and retains native console behavior.
- `SceneGeneratorDiagnosticsLogger.log` now takes an autoclosure and constructs
  timestamped user/model diagnostics only in Debug. No mass call-site rewrite
  or parallel logger was introduced.
- Parent Debug and Release simulator builds succeeded. The Release executable
  has no unresolved standard Swift-print symbol and the source has no explicit
  `Swift.print` bypass. The release-bundle validator reached exactly the five
  existing provenance blockers; all six contamination fixtures passed.
- Fresh Sol / High audit verdict: `ship`, findings none. The reviewed file hash
  remained unchanged after review.
- Drift decision: `continue`. Ordinary print arguments outside the shared
  autoclosure owner may still be evaluated, while `os_log`/`NSLog` are separate
  transports. The next package gates live semantic unified logging.

## 2026-08-26 autonomous continuation — Release unified-log privacy

- `CameraLog` is now a compile-time owner: Debug preserves its diagnostic
  values, while all seven Release flags are false. Suggestion text, live
  decisions, feature vectors, DETR labels, vision geometry, saliency and motion
  diagnostics are therefore absent from the Release executable.
- Remaining AnalysisPipeline event codes stay public only when bounded and
  operational. Frame IDs, fallback reasons, violations and dynamic Vision/DETR
  errors use unified-log private substitution. `recordSuggestion` is compiled
  only in Debug because constant folding did not remove its format string.
- Parent no-sign Release build on the dedicated iPhone 17e passed. Exact
  sensitive-format scans returned zero; the bundle validator reached only the
  five existing provenance blockers and all six contamination fixtures passed.
- Fresh Sol / High audit verdict: `ship`, findings none. Reviewed hashes were
  unchanged after review.
- Drift decision: `continue`. Static AppDelegate lifecycle logging and bounded
  operational event codes remain. The next truth-critical package corrects
  DETR output parsing, components and coordinate orientation.

## 2026-08-26 autonomous continuation — truthful DETR component extraction

- DETR now selects the named `semanticPredictions` feature, validates the
  rank, Int32 type, dimensions, strides and offset arithmetic, and reads the
  actual row and column strides instead of assuming contiguous storage.
- Hard-label masks are split into deterministic 8-connected components per
  class. Disconnected objects no longer collapse into one scene-spanning box;
  noise is filtered per component and top-origin model rows are converted to
  Vision lower-left coordinates exactly once.
- The exported score remains a legacy geometric-support value and is explicitly
  not described as calibrated model probability. Detailed label, support and
  geometry diagnostics are compiled only in Debug.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 6/6 focused DETR tests passed,
  including production fixture 019 with two distinct chair components; a
  no-sign Release simulator build exited 0; `git diff --check` passed.
- The first fresh Sol / High audit returned `fix-first` for pixel-exact fixture
  assertions and Release-visible diagnostic geometry. Fresh Luna / Max fixed
  both and added non-unit column-stride coverage; repeated parent verification
  and a new fresh Sol / High review returned `ship` with no findings.
- Drift decision: `continue`. Touching same-class regions remain one connected
  component, and downstream interpretation of the legacy `confidence` field
  still requires a separate truth audit. The next package corrects physical
  Camera Coach movement directions and suppresses unsupported look-space
  claims.

## 2026-08-26 autonomous continuation — physical Camera Coach action truth

- Horizontal composition now follows physical rear-camera movement: a subject
  right of center requests camera-right, and a subject left of center requests
  camera-left, in both the structured planner and fallback owner.
- All active composition producers convert Vision lower-left Y into display
  semantics before calculating the upper-third offset. Region storage and the
  preview mapper remain unchanged, so the conversion still occurs exactly once.
- Semantic object correction stays distinct from camera movement: a right-edge
  object may be moved left while the physical camera command is right. Both
  edge directions now have explicit contract coverage.
- `lookSpaceAdequate` remains unknown because the current evidence contract has
  no gaze, head-pose or movement-direction signal. The critique engine therefore
  cannot publish a fabricated look-space claim.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: the broad direction/critique/semantic
  set passed 67/67; post-review focused mapping plus display-Y coverage passed
  20/20; no-sign Release simulator builds succeeded; `git diff --check` passed.
- The first fresh Sol / High audit returned `fix-first` for a reversed semantic
  look-space text mapping. A fresh Luna / Max correction, repeated parent
  verification and a new fresh Sol / High audit closed it; final verdict
  `ship`, findings none.
- Drift decision: `continue`. The fallback direction helper is code-inspected
  rather than isolated by a dedicated test. The next truth package guarantees
  exact-once completion for aesthetic scoring failures.

## 2026-08-26 autonomous continuation — exact-once aesthetic scoring

- `AestheticScorer` now owns one invocation-local completion gate. Vision
  request errors, thrown handler errors, missing feature output and malformed
  distributions all finish exactly once with unavailable evidence.
- Only a ten-bin NIMA distribution produces the weighted 1...10 score. The old
  classification-confidence fallback and malformed-output score zero were
  removed because neither represented the model contract.
- Missing-model completion remains synchronous; model-backed completion stays
  on the scorer's private serial queue. Production callers and their timeout
  behavior did not change.
- Parent no-sign Release simulator build succeeded and `git diff --check`
  passed. The targeted replay executed on iPhone 17e but Vision failed to create
  an Espresso context before inference; its four existing assertions therefore
  failed and were not weakened or counted as package success.
- Fresh Sol / High audit verdict: `ship`, findings none. The exact-once and
  queue contracts were verified by code inspection against Vision's synchronous
  `perform` semantics.
- Drift decision: `continue`. Successful NIMA inference on simulator and
  physical Neural Engine remain unproven. The next package addresses repeated
  confidence discounting that currently makes real spatial coaching
  mathematically unreachable.

## 2026-08-26 autonomous continuation — confidence single ownership and person-edge direction

- Vision and DETR subject evidence now receive the source freshness discount
  exactly once. Source health remains separately observable, while kind,
  region and label priors affect candidate ranking only and never masquerade as
  published confidence.
- The unchanged live safety gates are reachable with production-shaped input:
  fresh, coherent detector evidence produces a directional hint only after
  three consecutive frames; stale, unavailable, ambiguous and region-mismatch
  inputs remain silent.
- Person edge-pressure now uses physical rear-camera motion consistently. A
  person on the visual left requests camera-left while copy describes the
  resulting visual correction (the hero moves right); the right side is
  symmetric. Look-space and physical object-motion contracts remain separate.
- Parent verification on the dedicated iPhone 17e Simulator
  `1F680A42-CEB3-43E8-9CED-52F874962A62`: 36/36 focused domain and semantic-tip
  tests passed; a fresh generic no-sign Release simulator build succeeded;
  `git diff --check` passed. iPhone 17 Pro and physical devices were not used.
- The first fresh Sol / High review returned `fix-first` for a suspected
  look-space regression. Evidence showed that production owns no gaze/head-pose
  signal, sets `lookSpaceAdequate=nil`, and cannot create that issue; the same
  reviewer revised the verdict to `ship`. The opposite-side region-only
  fallback is recorded as future-contract debt and must not be activated when
  gaze evidence is introduced.
- Drift decision: `continue`. The next release-critical UI/data truth gap is
  AR hint-pause, which still lacks an immutable display-exact accepted frame.

## 2026-08-26 autonomous continuation — immutable AR hint-pause frame

- Scene Generator now accepts one current AnalysisPipeline snapshot before any
  asynchronous work, renders that same envelope for display, and passes the
  rendered snapshot to the typed pause-analysis entry point. Snapshot ID,
  source frame and orientation therefore remain identical through acceptance,
  display and analysis.
- Request token, AR generation and snapshot ID fence every render and analysis
  completion. Resume, hint disable, interruption and workspace release cancel
  the render task and clear the owner projection, so late work cannot republish.
- While the pause is active the immutable frame replaces the live AR image and
  live hints, grid, object labels, beat HUD and storyboard controls are hidden.
  Missing or unrenderable evidence remains a visible localized failure with a
  recovery action; no fake still or critique is created.
- Parent verification on the dedicated iPhone 17e Simulator passed both focused
  lifecycle/exact-frame tests; a generic Release simulator build succeeded and
  `git diff --check` passed. iPhone 17 Pro and physical devices were not used.
- Fresh Sol / High audit verdict: `ship`, findings none.
- Drift decision: `continue`. Physical AR camera/display validation remains
  required. The next reachable product gap is exposing already-grounded
  semantic beginner actions on the production pause surfaces.

## 2026-08-26 autonomous continuation — semantic pause review surfaces

- Camera Coach and reachable AR pause now share one flat SET review band built
  from existing palette, typography, spacing, hairline and action owners. The
  stable surface adds no card/material/blur/shadow/gradient language.
- Camera pause copy prefers the grounded non-empty `expectedOutcome` emitted by
  the recommendation pipeline and falls back to the existing localized semantic
  action only when that evidence is blank. Raw model verdicts remain hidden.
- The Camera Coach action keeps `camera_coach_pause_action`; AR does not borrow
  that camera accessibility ID. Existing accepted-frame identity, pause
  lifecycle, event-ledger loading motion and Reduce Motion behavior are intact.
- Parent verification confirmed 4/4 focused tests on the dedicated iPhone 17e,
  a no-sign Release device build, matching implementation hashes and a clean
  `git diff --check`. iPhone 17 Pro and physical devices were not used.
- Fresh Sol / High audit verdict: `ship`, findings none.
- Drift decision: `continue`. The next release-critical package is bounded
  world-map capture so AR teardown cannot suspend forever or persist stale
  state.

## 2026-08-26 autonomous continuation — bounded AR world-map persistence

- Callback-only AR world-map capture now resolves through one exact-once owner:
  framework callback, three-second timeout and task cancellation race to one
  terminal result; late callbacks are ignored.
- The complete capture-and-save operation is coalesced, so concurrent teardown
  and background callers share one capture and one persistence. Project state
  is built after capture, preserving edits made while ARKit is pending.
- Timeout/cancellation/capture failure durably saves the latest metadata with a
  nil map and returns the existing typed failure for retry. A successful nil-map
  write retires the in-memory stale map; a persistence failure retains it.
- Parent verification passed 4/4 focused tests on the dedicated iPhone 17e and
  a generic no-sign Release device build. The post-review stale-map fix passed
  its focused test 1/1; `git diff --check` is clean.
- First Sol / High audit found stale in-memory map resurrection and returned
  `fix-first`. Luna / Max fixed it; fresh final Sol / High verdict: `ship`, no
  blocking findings.
- Drift decision: `continue`. Real non-nil `ARWorldMap` payload retirement and
  ARKit timing remain hardware-only evidence. The next simulator-verifiable
  beginner-safety gap is temporal confirmation of technical live alerts.

## 2026-08-26 autonomous continuation — technical live-alert confirmation

- Pixel-buffer technical alerts now require three consecutive matching live,
  still frames before publication. Issue/action changes, non-positive or over-
  cadence gaps, motion, frame mismatch and live lifecycle changes reset the
  counter.
- The gate does not depend on Vision availability: exposure, focus and lens
  signals retain their actual technical analyzer ownership. Pending frames flow
  through normal hint hold/expiry behavior; pause analysis is unchanged.
- First Sol / High audit found that the real moving-frame early return and
  release/register/clear paths bypassed the new reset. Luna / Max fixed those
  production paths and added regressions through `ingestHigh` and presentation
  clear. Fresh final Sol / High verdict: `ship`, findings none.
- Parent evidence confirms 4/4 focused tests on the dedicated iPhone 17e,
  matching source hashes and clean `git diff --check`. iPhone 17 Pro and
  physical devices were not used.
- Drift decision: `continue`. Hardware calibration and false-positive rates
  remain physical/model-eval evidence. The next release blocker is bundle
  identity/scene/localization metadata, followed by EN Camera Coach projection.

## 2026-08-26 autonomous continuation — App Store bundle metadata gate

- The built app now has exact `Shafin Multitool` EN/RU display names and a valid
  `UIWindowScene` scene class. Six Russian permission fallback typos were fixed
  without changing the localized permission catalog.
- Release validation now requires non-empty bundle identity/version/display
  fields, every declared root font, EN/RU InfoPlist and Localizable resources,
  the exact scene class and compiled AppIcon evidence from `Assets.car`.
- The existing validation-only source of truth remains read-only for the app.
  Its self-test preserves the six contamination cases and adds five metadata
  fixtures through a deterministic assetutil seam.
- Parent fresh no-sign Release device build succeeded. The clean artifact passed
  all new metadata/resource stages and remained blocked by the five known model/
  provenance blockers; all 11 negative fixtures passed. Fresh Sol / High audit
  verdict: `ship`, findings none.
- Drift decision: `continue`. Signing, archive/export, App Store Connect and the
  five provenance records remain external release blockers. The next reachable
  defect is Russian core copy leaking into the English Camera Coach UI.

## 2026-08-26 autonomous continuation — Camera Coach RU/EN projection

- Live hints now carry optional typed semantic/technical provenance. Core text
  remains evidence; the production UI resolves seeking, fallback, keep, coarse,
  all semantic actions and seven technical actions through the existing SET
  String Catalog at the locale-aware presentation boundary.
- Locale does not enter the analysis/ML pipeline. SwiftUI's injected locale is
  passed to both live-overlay projections; text-only refresh preserves typed
  provenance. Invalid raw payloads still collapse to the safe fallback.
- Pause review now renders the typed semantic catalog action and never uses raw
  `expectedOutcome` as the primary visible string.
- Parent evidence confirms 32/32 focused RU/EN/presentation/design-system tests
  on the dedicated iPhone 17e, catalog JSON validity, exactly seven new technical
  keys and clean `git diff --check`. Fresh Sol / High verdict: `ship`, findings
  none.
- Drift decision: `continue`. Object-aware wording remains intentionally generic
  until language-tagged grounded evidence exists. Physical display/readability
  and real-camera behavior remain hardware evidence.

## 2026-08-26 autonomous continuation — Generator microphone recovery

- Reachable Generator REC now distinguishes microphone `.denied` from
  `.restricted`: denied offers the native Settings route; restricted offers an
  in-flow recheck. Unavailable/unknown permission and recorder failures retain
  the generic recorder error and never expose a misleading Settings action.
- The existing close action and accessibility ID remain unchanged. New stable
  IDs are `generator_microphone_open_settings` and
  `generator_microphone_recheck`; copy is catalog-backed in RU and EN.
- A single `errorMessage` owner clears stale microphone recovery whenever any
  later generator error replaces the copy. Denied/restricted branches attach
  their typed recovery only after publishing their own message.
- Final focused evidence is 9/9 on the dedicated iPhone 17e with clean
  `git diff --check`. The first Sol / High review found stale recovery after a
  non-recording error; Luna / Max fixed the owner boundary and the fresh final
  Sol / High verdict is `ship`.
- Drift decision: `continue`. Physical microphone/route-interruption behavior
  remains hardware evidence. The next autonomous P1 is retry-safe workspace
  teardown ordering after a persistence failure.

## 2026-08-26 autonomous continuation — retry-safe workspace teardown

- Scene workspace teardown now separates per-take stop/finalization from the
  terminal recording-controller release. The production order is awaited
  recording stop, playback stop, persistence, controller release, then AR
  pause/detach.
- A failed persistence attempt neither terminally releases REC nor detaches AR.
  The retained CommercialShell child can retry; concurrent callers still share
  one attempt, and a later successful retry releases/detaches exactly once.
- Focused evidence is 15/15 on the dedicated iPhone 17e with clean
  `git diff --check`. Fresh Sol / High inspected the controller lifecycle and
  confirmed that per-take finalization leaves the controller reusable; verdict
  `ship`, findings none.
- Drift decision: `continue`. Real background allowance and physical recorder/
  AR timing remain hardware evidence. The next autonomous P1 is corrupt-file
  isolation in the reachable Scene Library.

## 2026-08-26 autonomous continuation — Scene Library corrupt-file isolation

- Unified project listing and name lookup now isolate decode/UUID-validation
  failures per file. One malformed or legacy-incompatible JSON no longer hides
  healthy scenes or blocks opening/deleting a valid named project.
- Corrupt files are retained untouched for recovery; directory enumeration
  failures keep the prior contract. Public APIs, ordering, schema and atomic
  save behavior are unchanged.
- Focused evidence is 24/24 on the dedicated iPhone 17e; reviewed-file
  `git diff --check` passed. Fresh Sol / High checked filename-ID mismatch,
  sidecar deletion and same-name corrupt entries; verdict `ship`, findings none.
- Drift decision: `continue`. Duplicate healthy names remain an existing
  public-API-unreachable ambiguity. The next autonomous P1 is publishing a
  finalized REC artifact into a reachable playback/share/persistence flow.

## 2026-08-26 09:52 MSK final autonomous compile checkpoint

- The current full dirty working tree builds successfully in Release for arm64
  iOS Simulator on the dedicated iPhone 17e with signing disabled. Product:
  `/private/tmp/set-os-final-release-arm64/Build/Products/Release-iphonesimulator/shafinMultitool.app`.
- The release-bundle validator passes privacy, framework allowlist, required
  structure, bundle identity/version/display name, `UIWindowScene`, five fonts,
  RU/EN resources, AppIcon, forbidden-payload scan and acknowledgements. It
  stops only at the exact five existing `license_approved=false` provenance
  records; that non-zero exit is the intended legal release gate.
- Final parent re-read confirms focused XCResults 9/9 microphone, 15/15 teardown
  and 24/24 library, valid String Catalog JSON and clean full-tree
  `git diff --check`. No iPhone 17 Pro or physical device was used.
- This is not App Store readiness: signed archive/export/ASC, the five rights
  decisions, physical AR/camera/microphone/REC/playback/A/V/thermal evidence,
  field coaching calibration and the reachable finalized-recording playback/
  share/persistence P1 remain open.
- A final low-disk fixture run exposed that `copy_fixture` could print an app
  path after `cp -R` failed, allowing a partial-copy false positive. The release
  self-test now fails closed on copy failure. `bash -n`, full-tree
  `git diff --check` and fresh Sol / High review passed; the ENOSPC-affected run
  is not counted as 11/11 fixture evidence.

### Completed bounded production package — finalized REC ownership

- `UnifiedSceneProject` now owns a backward-compatible ordered Codable
  recording ledger containing recording ID, safe relative artifact path,
  duration and audio flag; legacy JSON decodes an empty ledger. Absolute
  sandbox URLs are never persisted.
- Only `.finalized(RecordingArtifact)` enters the ledger. Pending promotion is
  descriptor-bound (`openat`/`fstatat`/`renameatx_np(RENAME_EXCL)`),
  symlink-fenced, no-overwrite and inode-validated. Failed promotion remains
  unpublished and retries in strict FIFO order before each persistence attempt;
  route/background teardown does not present UI after detachment.
- The reachable SET workspace exposes the newest resolvable take through native
  AVPlayer playback and system share. Stable IDs are
  `generator_recording_review_band`, `generator_recording_playback_button` and
  `generator_recording_share_button`; missing media is visible but disabled.
- iPhone 17e build succeeded and the final focused storage/schema run passed
  4/4. Two Sol correction rounds closed TOCTOU, player-lifecycle and retry-order
  findings; the final fresh Sol/High verdict is `SHIP`.
- Boundary: a permanent promotion failure followed by OS termination may leave
  an unpublished orphan in Pending; retention/orphan cleanup is the next
  bounded P1. Real media/audio playback, A/V sync, system share destinations
  and export timing remain physical-device evidence.

### Completed bounded production package — recording retention and project deletion

- `RecordingArtifactStore` now owns idempotent project cleanup and traverses
  only descriptor-opened `Application Support/Recordings/Projects/<UUID>`.
  The configured root and every descendant use `O_NOFOLLOW`/`openat`; only
  canonical UUID `.mov` regular files are accepted. Symlinks, nested entries
  and non-regular files fail closed without touching their external targets or
  sibling projects.
- `DBService` derives the cleanup UUID only from decoded, filename-fenced
  metadata. It removes the legacy sidecar first and authoritative JSON last,
  then runs recording cleanup. The existing Bool remains the metadata outcome;
  cleanup/store-initialization failure is logged rather than presenting an
  impossible Library retry after the project is gone.
- Exact iPhone 17e build-for-testing succeeded. The focused run passed 6/6,
  including root/project symlink fencing, sibling isolation, idempotency,
  cleanup-failure semantics and corrupt UUID preservation. The first fresh
  Sol/High audit returned `FIX-FIRST`; the corrected re-audit returned `SHIP`.
- Pending cleanup is not implemented: current Pending filenames contain no
  persisted project owner, lease or retry state. An age scan could delete an
  active failed promotion and is therefore prohibited.

### Completed bounded production package — generation/teardown data safety

- `SceneGeneratorViewModel` now owns one generation task. Concurrent callers
  join it, and the last committed parsed/planned/storyboard state remains
  authoritative while parsing and planning are suspended. Empty, canceled and
  failed generation therefore cannot erase the prior scene.
- Destructive model and AR replacement is one non-suspending MainActor commit
  after parse + plan succeed. Epoch/cancellation checks fence every earlier
  suspension; a canceled or stale task cannot persist, close the sheet or
  mutate a released workspace.
- The complete ViewModel teardown is assigned before its first suspension.
  Concurrent teardown callers join it; generation is rejected while snapshot
  capture/persistence is in flight; released completion remains cached, while
  a blocked attempt is cleared by identity only after result consumption so a
  retry cannot race stale cleanup.
- Exact iPhone 17e build/test execution passed the focused regression 1/1 and
  the complete `SceneWorkspaceTeardownTests` class 16/16. The first fresh
  Sol/High audit found a generation-admission race during snapshot capture;
  Luna/Max added the complete teardown owner and gated regression. The final
  fresh re-audit returned `SHIP`.

### Next bounded production package — Pending take ownership and cold-launch recovery

- Persist the minimum owner/created-at/lease evidence required to distinguish
  an active retryable Pending take from an abandoned take; do not infer
  ownership from filenames or view lifetime.
- Cleanup may run only at a cold-launch boundary before recording owners are
  created, must be descriptor-bound, and must preserve recent/leased takes.
- Preserve finalized FIFO promotion, project deletion, routes, async teardown
  and playback/share behavior. No background timer or view-triggered scan.
