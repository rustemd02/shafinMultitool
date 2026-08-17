# Camera Coach release checkpoint

Дата: 17 августа 2026 года.

## TaskStartSnapshot

- Root: `/Users/unterlantas/Documents/XCode/shafinMultitool`.
- Current branch/HEAD after the docs-only UI-authority decision and fresh release gate: `store` at `eac5b47d4ab5ab21975280ae3a9959b4f25c936b`; the accepted bounded CC-010D1 implementation baseline remains `f45377b3b4ab39ee79782436afcfb8d644b6a300`.
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

The accepted CC-011E baseline is `6ff225d553ae654298dda70b9c779c1226c31800`; the bounded CC-007/CC-010E launch integration is `ff9ce3e02d0f5ec7eb3cedefe2c888a16e0c7b60`, and current clean HEAD after the bounded CC-010D1 Scene workspace teardown slice is `f45377b3b4ab39ee79782436afcfb8d644b6a300`. CC-011E test/contract hygiene is committed and accepted; CC-008, CC-007A, CC-008A, the bounded CC-007/CC-010E slice, the bounded CC-011C real UI target/root smoke, bounded CC-010F orientation continuity and bounded CC-010D/CC-010E awaitable Scene teardown are accepted within their stated boundaries. The remaining CC-007 product/UI evidence remains open, and CC-013B2 Core ML composition remains owner-gated.

Slice Card:

- Goal: record the bounded CC-010D1 Scene workspace teardown and its CC-010E route integration after visible Luna / Max implementation and primary tests, without broadening the acceptance into full product or release readiness.
- Parent plan/spec: `docs/app-store-product-plan.md`, `docs/implementation/STATUS.md`, `docs/implementation/BACKLOG.md`.
- Files: the `f45377b` CC-010D1 code/tests and tracker evidence are accepted within a partial boundary; CC-011E, CC-007A/CC-008A, the `ff9ce3e` CC-007/CC-010E implementation slices, the `9f2f5f2` CC-011C target/root smoke and the `277170d` CC-010F orientation-continuity slice remain accepted within their stated boundaries.
- Boundary: no third-party Core ML exclusion, asset/legal approval, provider, payment, push or publication decision.
- Verification: visible Luna / Max owns implementation, correction and primary tests; the parent/main-chat Sol is limited to architecture, tracker and one bounded risk-based milestone acceptance. The coordinator's `f45377b` acceptance rerun, worker focused evidence, bounded `ff9ce3e` launch evidence, bounded `9f2f5f2` CC-011C UI evidence, bounded `277170d` CC-010F orientation evidence and the latest `eac5b47` local release gate are recorded in `90-evidence.md`; no release-ready claim is made.
- Stop: accept and integrate one coherent slice; otherwise record the genuine gate and choose another independent slice.

## Blockers

- CC-013B2 owner acceptance blocks removal of DETR/NIMA/compact neural dependencies from the minimal RC.
- Full default test topology remains unresolved: Settings crashes and configured real-image evaluation are not fixed by CC-011E; the pre-CC-011C raw audit remains historical evidence.
- CC-010D/CC-010E remain partial after `f45377b`: the tested awaitable deep-workspace route is recorded, but modal handling, physical-device AR/world-map behavior, actual OS background allowance, recorder finalization/media policy, the full Scene Mode user journey, UI physical evidence, full-suite health, legal/provenance and privacy/release readiness remain open.
- Exact-binary llama redistribution/archive decision, Circle/Person/image rights, physical-device matrix, Apple credentials, server privacy/provider choices and paid infrastructure are external or owner-gated.
- These blockers do not authorize a narrower product or a false release-ready claim.

## Next

1. Continue the remaining CC-007 product/UI evidence as listed in `BACKLOG.md`; the CC-011C target/root smoke, CC-010F orientation continuity and CC-010D/CC-010E awaitable teardown are accepted only within their bounded slices above.
2. Keep the remaining CC-010D/CC-010E modal/background/media/product boundaries, full test topology and real-image evaluation as separate unresolved lanes; obtain the independent CC-013B2 minimal-RC decision before changing Core ML composition.
3. Continue remaining production gates without claiming physical-device camera/AR behavior, CameraService writer metadata/transforms, deep Scene workspace rotation, recorder behavior, full-suite, beta, signing, provider, payment or legal/release evidence prematurely.

The next work remains the current `BACKLOG.md`; this checkpoint introduces no new implementation plan.

## Drift check

- Goal alignment: `continue`; full Camera Coach RC remains the goal.
- Scope: no replacement with a merely buildable or test-only subset.
- Baseline: product plan, STATUS, BACKLOG and accepted audits were re-read from current main.
- Compatibility: saved Scene Mode data and existing routes remain protected.
- Owner boundaries: CC-013B2 and legal/privacy/provider/payment decisions remain explicit; CC-008 is accepted.
- Evidence state: the latest authoritative local technical gate is the `eac5b47` run recorded above and in `90-evidence.md`: exit 0, `dirty=false`, `git diff --check` clean before/after, all eight listed stages passed, `TOTAL_APP_KIB=72868`, `MANIFEST_COUNT=2`, `MATERIAL_CONTRIBUTOR_COUNT=5`, `KNOWN_BLOCKER_COUNT=5`, 2 provenance validators and 6/6 contamination fixtures. Its +836 KiB drift versus `6ff225d` and +764 KiB drift versus `5e5dfef` is recorded with unchanged counts. Five `license_approved=false` owner/legal blockers remain; this technical pass does not establish legal, physical-device, App Store, product-release or full-suite readiness. The raw full unit target remains unresolved at 593 total / 496 passed / 94 failed / 3 skipped; do not claim it green. CC-011E integrated Luna evidence remains 104 executed / 102 passed / 2 intended skips / 0 failures at `/private/tmp/shafin-test-hygiene-final-luna/Logs/Test/Test-shafinMultitool-2026.08.15_22-52-30-+0300.xcresult`; CC-007A/CC-008A focused evidence is 19/19 on iPhone 17 Pro / iOS Simulator 26.5, with known non-fatal diagnostics retained in `90-evidence.md`. The bounded `ff9ce3e` launch evidence is historical pre-`f45377b`: generic workspace build-for-testing at `/private/tmp/shafin-cc010e-derived` plus 22/22 focused workspace tests at `/private/tmp/shafin-cc010e-workspace-derived/Logs/Test/Test-shafinMultitool-2026.08.16_00-55-36-+0300.xcresult`; the bounded CC-011C evidence is recorded in `90-evidence.md` with 4/4 true-process tests passed on iPhone 17 Pro / iOS 26.5 at `/private/tmp/shafin-cc011c-ui-tests-20260816.xcresult`; bounded CC-010F evidence at `277170d` is workspace build-for-testing, CameraManager lifecycle/orientation 10/10, UI portrait→landscape 1/1 and shell 23/23 (12 launch composition + 11 routing). Current CC-010D/CC-010E evidence at `f45377b` is 31/31 passed, 0 failed, 0 skipped on iPhone 17 Pro / iOS Simulator 26.5, with focused teardown/composition 20/20, routing 11/11 and generic iOS build-for-testing across 6 targets. This partially accepts the awaitable contract only; it does not establish modal handling, physical-device AR/world-map behavior, actual OS background allowance, recorder finalization/media policy, the full Scene Mode user journey, UI physical evidence, full-suite health, legal/provenance, privacy or release readiness.
