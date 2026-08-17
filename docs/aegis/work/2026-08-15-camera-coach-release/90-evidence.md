# Camera Coach release evidence

## Current orchestration evidence

- Sol Advisor logical profile `get_setup_status`: `ready` on 15 August 2026.
- Sol Advisor logical profile `validate_configuration`: `valid: true`.
- Codex project ID: `ac45e24e-80ce-4fad-803a-731a0a84ee27`; `isGitRepository: true`.
- Historical Luna app-task evidence records host support for `gpt-5.6-luna` / `max`; it is not a current hidden execution route.
- Saved logical profile: orchestrator inherits parent with a `gpt-5.6-sol` / `high` recommendation; routine, high and advisor profiles are `gpt-5.6-luna` / `max`; fallback policy is fail-closed.
- Current execution success criterion: every new executor, reviewer, correction-loop or verification worker appears as a separate user-visible Codex chat/thread using the project-local environment when continuing this checkout, explicit `model=gpt-5.6-luna` and `thinking=max`. A missing visible thread is a stop, not permission to use a hidden task or substitute model.
- The installed native adapter was not reinstalled/reloaded for this policy amendment; native role paths are not a valid execution path.
- Current accepted integration baseline: `store` at `f45377b`; CC-011E remains committed and accepted at its historical baseline, bounded CC-007/CC-010E launch evidence remains at `ff9ce3e`, bounded CC-011C UI evidence remains at `9f2f5f2`, bounded CC-010F orientation evidence is recorded at `277170d`, and bounded CC-010D/CC-010E awaitable Scene workspace teardown is recorded at `f45377b`.

## Accepted product and release evidence

- Product/research baseline: `docs/app-store-product-plan.md`, CC-000 accepted.
- Release inventory and isolation: CC-001/CC-002 accepted; Release excludes GGUF, DeviceBenchmark and development `Resources/Models` payloads.
- Privacy and permissions inventory: `docs/implementation/audits/privacy-permissions-inventory.md`, CC-003 accepted.
- Test topology and runtime entry: CC-005/CC-006 accepted; normal non-benchmark Camera Coach shell launch is covered by bounded `ff9ce3e` evidence, and the true UI-test target/root smoke is covered by bounded `9f2f5f2` evidence. Full portrait behavior, camera permission UX and saved-project/deeper Scene smoke remain future-gated work.
- Privacy manifest and bundle gate: CC-011A/CC-011B accepted.
- Earlier canonical clean release gate passed on `6ff225d553ae654298dda70b9c779c1226c31800`; all stages passed: Release 72,032 KiB, 2 privacy manifests, only `SnapKit.framework` and `llama.framework`, 5 material contributors, 5 blockers, 2 provenance validators and 6/6 contamination fixtures.
- Host-retry canonical release gate passed on clean HEAD `5e5dfef859c7db220864076aead9c0de44181a8d`: `scripts/run_release_gates.sh --derived-data-root /private/tmp/shafin-release-gate.20260816-host-retry` exited 0 with `dirty=false`. Passed: Debug build-for-testing, Release build, 2 provenance validators, privacy validation, bundle validation and 6 contamination fixtures. Values: `manifest_count=2`, `TOTAL_APP_KIB=72104`, `KNOWN_BLOCKER_COUNT=5`. Logs: `/private/tmp/shafin-release-gate.20260816-host-retry/shafin-release-gates/{debug-build.log,release-build.log,release-validation.log,release-fixtures.log}`.
- The previous exit 66 was a sandbox/Xcode/CoreSimulator host restriction, not a repository failure; the host retry restored valid evidence. The five existing provenance/license blockers remain unresolved: `llama.framework`, `DETRResnet50SemanticSegmentationF16P8.mlmodelc`, `aesthetic_nima_mobilenet_fp16.mlmodelc`, `Circle.usdz` and `Person.usdz`; this evidence does not establish release readiness.
- Dependency cleanup: ARVideoKit removed; SnapKit 5.7.1 privacy bundle retained and validated.
- llama record: worker `ac97f6e`, accepted `d7fff1b`; 15 fixtures and offline/optional-upstream checks passed. Traceability is proven, clean rebuild and legal approval are not.
- Circle record: worker `81f50c2`, accepted `c8601ba`; 10 fixtures and real offline validator passed. Repository correlation is proven, source-to-export causality and rights are not.

## Accepted camera foundation evidence

- CC-009 camera/session ownership audit accepted.
- CC-010A capture lifecycle: accepted `e0bd423`; generic build and 7/7 focused simulator tests passed.
- CC-010B scheduler/pipeline release: accepted `79f7d1d`; generic build and 23/23 focused simulator tests passed.
- CC-010C-A serialized recorder core: worker `d1277ca`, accepted `9b41adf`; canonical generic build-for-testing and 29/29 `SerializedMediaRecorderTests` passed on iPhone 17 Pro.
- CC-003A permission foundation: worker `322faeb`, accepted `f246ada`; exact three-file scope, integrated generic build and 10/10 `PermissionFoundationTests` passed.
- CC-010B1 latest-frame evidence: worker `b38ef12`, accepted `8b20380`; correction worker `772fe33`, accepted `ee019f0`. Integrated generic build and 12/12 focused release/store tests passed.
- CC-010A2 atomic motion snapshot: worker `9fb974e`, accepted `caef74b`; correction worker `f80e1a3`, accepted `b76f217`. Integrated generic build and 4/4 `MotionGateTests` passed, including concurrent tuple coherence.
- CC-010A1 failed-start rollback: worker `7169d85`, accepted `d7c4e98`; correction worker `f49953a`, accepted `9a63f69`. Sol source-reviewed the lifecycle identity/generation fence, independently passed the integrated generic build and 22/22 focused simulator tests across CameraViewModel, pipeline release and camera manager lifecycle suites.
- CC-010A3 transactional lens input: worker `85fc422`, accepted `15aa4e5`; one generic helper closes replace/restore/rollback mechanics, both manager APIs share one session-queue owner, worker generic build passed and Sol independently passed 16/16 focused simulator tests.
- CC-010A4 confirmed lens presentation: worker `993510e`, accepted `b38f9fb`; Sol reviewed the MainActor task/intent fence and result mapping, then independently passed 15/15 lens presentation, transaction and lifecycle simulator tests. Physical lens matrix and CC-008 feedback UI remain unclaimed.
- CC-010G stateless thermal budget: worker `3212923`, accepted `6bfd3a4`; `lastBudget` was removed without policy changes, immutable Sendable values were adopted and Sol independently passed 6/6 focused tests including bounded concurrent reads.
- CC-010F bounded orientation continuity: commit `277170d`. Camera Coach supports portrait/landscape; `CameraManager` maps and applies orientation on the existing session queue without reconfigure/restart; `Overlay` observes rotation; the AR container refreshes viewport/display transform in place. The target allows all orientations, while `CommercialShell` forwards active child policy: Camera Coach all, Scene navigation landscape-only, including the blocked deep Scene route.
- CC-010F evidence: workspace `build-for-testing` passed; CameraManager lifecycle/orientation tests passed 10/10; the UI portrait→landscape transition passed 1/1; shell tests passed 23/23 (12 launch composition + 11 routing).
- CC-010F boundary: this is a bounded acceptance only. It does not claim physical-device camera/AR behavior, `CameraService` writer metadata/transforms, deep Scene workspace rotation, recorder behavior, full-suite health, legal clearance or release readiness.
- Recorder evidence covers an isolated policy-neutral core only; production camera wiring, Photos export and retention/background behavior are not claimed.

## CC-007A/CC-008A integrated evidence (pre-`ff9ce3e` slice)

- Integrated Luna / Max run on iPhone 17 Pro / iOS Simulator 26.5: generic `build-for-testing` succeeded.
- One ordinary `xcodebuild test` run used no `EXCLUDED_SOURCE_FILE_NAMES` and `-parallel-testing-enabled NO`; 19/19 tests passed: `CommercialShellRoutingTests` 11/11 and `CameraOverlayUXPresentationTests` 8/8.
- DerivedData: `/private/tmp/shafin-cc007a-cc008a.F0EKEx`; result bundle: `/private/tmp/shafin-cc007a-cc008a.F0EKEx/cc-focused-tests.xcresult` (`cc-focused-tests.xcresult`).
- `git diff --check` passed for the integrated slice.
- Known non-fatal diagnostics are preserved: `appintentsmetadataprocessor` skipped metadata extraction because no `AppIntents.framework` dependency was found; Xcode reported no rule to process the `Resources/Circle.rcproject` folder for arm64; the app emitted the `UICollectionViewFlowLayoutBreakForInvalidSizes` symbolic-breakpoint diagnostic. These did not fail this focused run.
- Boundary: this is focused simulator/unit-target evidence. It does not prove production launch-graph/default-route integration, a true UI-test target, full-suite health, configured real-image evaluation, physical-device behavior or App Store/release readiness. The raw full unit-target audit and other unresolved gates below remain in force.

## Historical pre-`f45377b` CC-007 / CC-010E bounded launch integration evidence

- Commit `ff9ce3e` completes the normal Camera Coach launch portion of CC-007 and records a bounded CC-010E exclusive lease integration. In `SceneDelegate`, the DEBUG benchmark branch remains first when a benchmark configuration is present; the normal non-benchmark branch opens `CommercialShell` with Camera selected.
- The Camera route owns the existing `CameraViewModel` used by `ContentView` and awaits `stopAndWait` before the shell removes that route or constructs the next route. Repeated Camera deactivation calls share one idempotent task.
- At that pre-`f45377b` baseline, the Scene library root could release to Camera. A deeper Scene workspace or any presented modal returned blocked and did not construct Camera because the existing AR/persistence teardown boundary was not awaitable. The current awaitable deep-workspace contract is recorded below.
- Generic workspace `build-for-testing` passed with derived data at `/private/tmp/shafin-cc010e-derived`.
- Focused workspace tests passed 22/22 on iPhone 17 Pro / iOS Simulator 26.5: `CommercialShellLaunchCompositionTests` 11/11 and `CommercialShellRoutingTests` 11/11. Final result bundle: `/private/tmp/shafin-cc010e-workspace-derived/Logs/Test/Test-shafinMultitool-2026.08.16_00-55-36-+0300.xcresult`. The earlier 20/20 result is retained as historical evidence; this final 22/22 run is preferred.
- Historical boundary: full CC-010E and CC-010D were not complete at this baseline. This evidence did not establish a true UI-test target, portrait/landscape launch, saved-project actual smoke, physical-device behavior, full-suite health, legal/provenance clearance or release readiness; the bounded CC-011C evidence below is separate.

## CC-010D / CC-010E awaitable Scene workspace teardown evidence

- Commit `f45377b3b4ab39ee79782436afcfb8d644b6a300` (`Wire awaitable Scene workspace teardown`) is the bounded CC-010D1 implementation slice. `SceneGeneratorViewModel` is the real awaitable Scene workspace owner.
- One idempotent operation stops existing legacy recording if active and existing playback if active, awaits the unified project/world-map snapshot and pauses the AR session plus clears its delegate/detaches the AR view only after success. Repeated and concurrent callers share one task.
- Snapshot/world-map and persistence failures become typed blocked results. `CommercialSceneLibraryRoute` does not construct Camera and retains the deep Scene route on failure. The route finds its provider from the actual `LandscapeHostingController` created by `SORouter`; on success it reduces navigation to the Scene library root before returning release.
- A presented Scene modal blocks before teardown. `SceneGeneratorView.onDisappear`, the Scene `scenePhase` background hook and `CommercialSceneLibraryRoute.handleDidEnterBackground()` invoke the same awaitable operation; this does not claim that iOS grants enough background execution time for completion.
- Coordinator independent acceptance rerun command: `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/shafin-cc010d1-sol-accept -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -only-testing:shafinMultitoolTests/CommercialShellLaunchCompositionTests -only-testing:shafinMultitoolTests/CommercialShellRoutingTests`.
- Authoritative XCResult: `/private/tmp/shafin-cc010d1-sol-accept/Logs/Test/Test-shafinMultitool-2026.08.17_16-29-39-+0300.xcresult`; summary: 31 total, 31 passed, 0 failed, 0 skipped on iPhone 17 Pro / iOS Simulator 26.5. The 31 tests are 8 `SceneWorkspaceTeardownTests`, 12 `CommercialShellLaunchCompositionTests` and 11 `CommercialShellRoutingTests`.
- Worker evidence additionally records focused teardown/composition 20/20, existing `CommercialShellRoutingTests` 11/11 and generic iOS `build-for-testing` success across the 6-target dependency graph. Visible Luna / Max owns implementation, correction and primary tests; Sol remains limited to architecture, tracker and bounded risk-based acceptance, with no Sol subagent or task-level Sol worker added.
- State: CC-010D moves from `draft` to `partially_accepted`; CC-010E remains `partially_accepted`. A real deep Scene workspace can now release only under this tested awaitable contract. The slice is not fully accepted or RC-ready.
- Boundary: modal handling, physical-device AR/world-map behavior, actual OS background allowance, recorder finalization/media policy, the full Scene Mode user journey, UI physical evidence, full-suite health, legal/provenance, privacy and release readiness remain open. No true background completion, TestFlight/App Store readiness or full product release readiness is claimed.

## CC-011C bounded true UI target/root smoke evidence

- Commit `9f2f5f2` adds the `shafinMultitoolUITests` target, shared scheme membership and a real process XCTest replacement for the unit-hosted pseudo-UI test. The target has neither `TEST_HOST` nor `BUNDLE_LOADER`.
- DEBUG-only `SHAFIN_UI_TESTING=1` composes the real `CommercialShellComposition` / `ContentView` with the existing deterministic `CameraManager` failure `.noWideCamera`; the benchmark branch still comes first, so no permission/hardware prompt is requested. The root and analysis are not faked, and this path does not ship in Release.
- Workspace `build-for-testing` succeeded. True process evidence `/private/tmp/shafin-cc011c-ui-tests-20260816.xcresult` passed 4/4 with 0 failures on iPhone 17 Pro / iOS 26.5: normal Camera shell, real Scene library root → Camera return, portrait root no crash and landscape root no crash.
- Boundary: this bounded slice does not claim broader Camera Coach product behavior, camera permission UX, live capture continuity, completed analysis, deeper Scene workspace switching, full-suite health, physical-device behavior or release readiness. CC-011C remains partial for its broader acceptance, and remaining CC-007 product/UI evidence stays open; the bounded CC-010F orientation evidence is recorded separately above.

## Current test and contract evidence

- Pre-CC-011C raw full unit-target audit remains unresolved: 593 total, 496 passed, 94 failed and 3 skipped; XCResult `/private/tmp/shafin-main-complete-tests/Logs/Test/Test-shafinMultitool-2026.08.15_21-53-59-+0300.xcresult`. The failures included pseudo-UI without target app, default execution of opt-in model/physical benchmark lanes, Settings force unwraps, real-image Camera Coach evaluation with simulator Vision/Espresso plus absent never-tracked assets, and legacy parser/persistence/fixture failures. The full suite is not green.
- CC-011E accepted on `6ff225d553ae654298dda70b9c779c1226c31800`: integrated Luna gate 104 executed, 102 passed, 2 intended skips and 0 failures; XCResult `/private/tmp/shafin-test-hygiene-final-luna/Logs/Test/Test-shafinMultitool-2026.08.15_22-52-30-+0300.xcresult`. Repeated evidence: Scene 18/18 twice and DB performance 4/4; DeepCritic 20/20; subtitle/config 22 with one intended skip; Hybrid 7/7; Semantic 8/8. The earlier canonical clean release gate then passed all stages with Release 72,032 KiB, 2 privacy manifests, only `SnapKit.framework` and `llama.framework`, 5 material contributors, 5 blockers, 2 provenance validators and 6/6 contamination fixtures.
- E1 gates local-model and physical-device benchmark execution: absent configuration skips before work, while invalid benchmark configuration fails.
- E2 persists metadata for nil maps while preserving legacy `_map`, without claiming a transactional map/data pair; dialogue arrays remain parallel and subtitle presentation emits `Иван: Привет.`.
- E3 corrects canonical neural/domain fixture ordering and exact time relationships without changing production inference semantics.
- E4 makes certainty validation account for inflection and calibrated language, preserves suppression of non-whitelisted live semantic actions and leaves Hybrid production unchanged.
- CC-011E is accepted; full test topology and configured real-image evaluation remain separate unresolved lanes.

## Product decisions and remaining owner gates

- CC-008: `docs/implementation/ux/camera-coach-state-spec.md` is accepted based on the owner's explicit instruction to launch the full autonomous implementation pipeline and the earlier affirmative product/UI decisions.
- CC-007A/CC-008A: accepted implementation slices with the focused evidence above; the bounded parent shell/default-route integration and bounded CC-011C target/root smoke are recorded separately below, while unsupported product states remain outside the accepted slices. They are not release-ready.
- Historical pre-`f45377b` CC-007/CC-010E: the normal launch portion and bounded exclusive lease are accepted at `ff9ce3e` within the historical evidence above; the deeper Scene workspace remained blocked at that baseline because teardown was not awaitable.
- Current CC-010D/CC-010E: the `f45377b` awaitable Scene workspace teardown is partially accepted within the evidence above; deep workspace release is proven only under the tested provider/teardown contract, while the listed modal, physical-device, background, recorder/media, full-journey, UI, full-suite, legal/provenance, privacy and release boundaries remain open.
- CC-010F: the orientation-continuity slice is accepted at `277170d` within the bounded evidence above; writer metadata/transforms, deep Scene workspace rotation, recorder behavior, physical-device camera/AR behavior, full-suite health, legal clearance and release readiness remain unclaimed.
- CC-013B2: recommended minimal RC excludes DETR, NIMA and compact neural fusion while retaining Apple Vision/saliency and deterministic critique; implementation is gated by owner acceptance.

These records support continued execution. They do not prove App Store readiness, legal redistribution rights, physical-device behavior, external beta quality or completion of the full active goal.
