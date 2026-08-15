# Camera Coach release checkpoint

Дата: 16 августа 2026 года.

## TaskStartSnapshot

- Root: `/Users/unterlantas/Documents/XCode/shafinMultitool`.
- Current branch/HEAD after the accepted bounded launch integration: `store` at `ff9ce3e02d0f5ec7eb3cedefe2c888a16e0c7b60`.
- Upstream: `origin/store`; the local product branch intentionally contains the accepted orchestration commits not yet pushed.
- Main worktree: no active Git operation; CC-011E remains committed and accepted at `6ff225d553ae654298dda70b9c779c1226c31800`, and the bounded CC-007/CC-010E integration is committed at `ff9ce3e02d0f5ec7eb3cedefe2c888a16e0c7b60`.
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
- Canonical release gate runs both provenance validators before Xcode and still reports five honest legal/provenance blockers.
- The earlier canonical clean release gate passed on `6ff225d553ae654298dda70b9c779c1226c31800`; all stages passed: Release 72,032 KiB, 2 privacy manifests, only `SnapKit.framework` and `llama.framework`, 5 material contributors, 5 blockers, 2 provenance validators and 6/6 contamination fixtures.
- The host-retry canonical release gate passed on clean HEAD `5e5dfef859c7db220864076aead9c0de44181a8d`: `scripts/run_release_gates.sh --derived-data-root /private/tmp/shafin-release-gate.20260816-host-retry`, exit 0, `dirty=false`; Debug build-for-testing, Release build, 2 provenance validators, privacy validation, bundle validation and 6 contamination fixtures passed. `manifest_count=2`, `TOTAL_APP_KIB=72104`, `KNOWN_BLOCKER_COUNT=5`. Logs: `/private/tmp/shafin-release-gate.20260816-host-retry/shafin-release-gates/{debug-build.log,release-build.log,release-validation.log,release-fixtures.log}`.
- The previous exit 66 was a sandbox/Xcode/CoreSimulator host restriction, not a repository failure; the host retry restored valid evidence. Five existing provenance/license blockers remain unresolved: `llama.framework`, two Core ML models and `Circle.usdz`/`Person.usdz`; this does not establish release readiness.
- Camera capture lifecycle and scheduler/pipeline release are awaitable, idempotent and covered by focused tests.
- Policy-neutral serialized recorder core is accepted after correction loops and 29/29 simulator tests.
- Policy-neutral permission foundation is accepted after Sol review, integrated build and 10/10 simulator tests.
- Coherent latest-frame evidence/session reset and atomic motion snapshot are accepted after two evidence-driven correction loops; 12/12 and 4/4 focused tests pass respectively.
- Failed camera starts now await a shared pipeline rollback before publishing failure; retry, stale-start and release races are accepted after a correction loop, generic build and 22/22 intersecting tests.
- CC-008 UX state specification is owner-accepted by the explicit instruction to launch the full autonomous implementation pipeline and the earlier affirmative product/UI decisions. CC-007A and CC-008A are accepted implementation slices with bounded evidence; they are not release-ready.
- CC-007 normal Camera Coach launch and bounded CC-010E lease integration are accepted at `ff9ce3e`: the normal non-benchmark `SceneDelegate` branch opens the commercial shell with Camera selected while benchmark remains first; Camera `stopAndWait` is awaited before route removal/next construction and repeated deactivation shares one task; the Scene library root can release to Camera, while deeper workspace/modal transitions block without constructing Camera. Generic workspace build-for-testing passed at `/private/tmp/shafin-cc010e-derived`; focused workspace tests passed 22/22 (11 `CommercialShellLaunchCompositionTests`, 11 `CommercialShellRoutingTests`). Full CC-010E/CC-010D and remaining product/UI evidence are not complete.

## Active slice

The accepted CC-011E baseline is `6ff225d553ae654298dda70b9c779c1226c31800`; current clean HEAD after the bounded CC-007/CC-010E launch integration is `ff9ce3e02d0f5ec7eb3cedefe2c888a16e0c7b60`. CC-011E test/contract hygiene is committed and accepted; CC-008, CC-007A, CC-008A and the bounded CC-007/CC-010E slice are accepted within their stated boundaries. CC-010D remains draft, CC-011C remains unverified, and CC-013B2 Core ML composition remains owner-gated.

Slice Card:

- Goal: continue the remaining CC-007 product/UI evidence and dependent CC-011C lane after accepting the bounded normal launch integration, without bypassing the separate model-composition gate.
- Parent plan/spec: `docs/app-store-product-plan.md`, `docs/implementation/STATUS.md`, `docs/implementation/BACKLOG.md`.
- Files: CC-011E code/tests and tracker evidence are accepted; CC-007A/CC-008A and the `ff9ce3e` CC-007/CC-010E implementation slices are accepted within their stated boundaries.
- Boundary: no third-party Core ML exclusion, asset/legal approval, provider, payment, push or publication decision.
- Verification: Luna / Max owns the integrated correction gate and task-level verification; the focused CC-007A/CC-008A evidence, bounded `ff9ce3e` launch evidence and the host-retry canonical release gate are recorded in `90-evidence.md`; no release-ready claim is made.
- Stop: accept and integrate one coherent slice; otherwise record the genuine gate and choose another independent slice.

## Blockers

- CC-013B2 owner acceptance blocks removal of DETR/NIMA/compact neural dependencies from the minimal RC.
- Full default test topology remains unresolved: unit-hosted pseudo-UI, Settings crashes and configured real-image evaluation are not fixed by CC-011E.
- CC-010D remains incomplete because Scene Mode AR/persistence teardown is not awaitable; the bounded CC-010E slice blocks deeper workspace and modal transitions rather than claiming release.
- Exact-binary llama redistribution/archive decision, Circle/Person/image rights, physical-device matrix, Apple credentials, server privacy/provider choices and paid infrastructure are external or owner-gated.
- These blockers do not authorize a narrower product or a false release-ready claim.

## Next

1. Continue CC-011C true UI target/default smoke and the remaining CC-007 product/UI evidence; do not claim real UI target, portrait/landscape or saved-project actual smoke from the bounded `ff9ce3e` tests.
2. Keep CC-010D awaitable Scene teardown, full test topology and real-image evaluation as separate unresolved lanes; obtain the independent CC-013B2 minimal-RC decision before changing Core ML composition.
3. Continue remaining production gates without claiming physical-device, beta, signing, provider, payment or legal evidence prematurely.

The next work remains the current `BACKLOG.md`; this checkpoint introduces no new implementation plan.

## Drift check

- Goal alignment: `continue`; full Camera Coach RC remains the goal.
- Scope: no replacement with a merely buildable or test-only subset.
- Baseline: product plan, STATUS, BACKLOG and accepted audits were re-read from current main.
- Compatibility: saved Scene Mode data and existing routes remain protected.
- Owner boundaries: CC-013B2 and legal/privacy/provider/payment decisions remain explicit; CC-008 is accepted.
- Evidence state: the earlier canonical full release gate passed on accepted commit `6ff225d553ae654298dda70b9c779c1226c31800`; the host-retry canonical gate passed on clean HEAD `5e5dfef859c7db220864076aead9c0de44181a8d` with exit 0, `dirty=false`, `manifest_count=2`, `TOTAL_APP_KIB=72104`, `KNOWN_BLOCKER_COUNT=5`, 2 provenance validators and 6/6 contamination fixtures. The previous exit 66 was a sandbox/Xcode/CoreSimulator host restriction, not a repository failure. Five existing provenance/license blockers remain unresolved, so release readiness is not established. The raw full unit target remains unresolved at 593 total / 496 passed / 94 failed / 3 skipped; do not claim it green. CC-011E integrated Luna evidence remains 104 executed / 102 passed / 2 intended skips / 0 failures at `/private/tmp/shafin-test-hygiene-final-luna/Logs/Test/Test-shafinMultitool-2026.08.15_22-52-30-+0300.xcresult`; CC-007A/CC-008A focused evidence is 19/19 on iPhone 17 Pro / iOS Simulator 26.5, with known non-fatal diagnostics retained in `90-evidence.md`. The bounded `ff9ce3e` launch evidence is generic workspace build-for-testing at `/private/tmp/shafin-cc010e-derived` plus 22/22 focused workspace tests at `/private/tmp/shafin-cc010e-workspace-derived/Logs/Test/Test-shafinMultitool-2026.08.16_00-55-36-+0300.xcresult`; this does not close CC-010D/CC-010E or the remaining UI evidence boundaries.
