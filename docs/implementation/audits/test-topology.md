# CC-005 — Test topology and UI-test target plan

Observed 2026-08-15 from base `faf3e12abd6443877c7e5072fd67c878cce68553` (`store` bootstrap commit). This is an implementation audit, not a product, signing, privacy, or architecture decision. Product behavior remains governed by `docs/app-store-product-plan.md`; execution state remains governed by `docs/implementation/STATUS.md` and `docs/implementation/BACKLOG.md`.

## Executive result

The repository currently has one application target and one app-hosted XCTest bundle:

- `shafinMultitool` — `com.apple.product-type.application`.
- `shafinMultitoolTests` — `com.apple.product-type.bundle.unit-test`, with `TEST_HOST` and `BUNDLE_LOADER` pointing at `shafinMultitool.app`.
- No `com.apple.product-type.bundle.ui-testing` target exists.
- The only shared scheme is `shafinMultitool`; its `TestAction` contains one testable reference, `shafinMultitoolTests.xctest`, and uses an autocreated test plan.

The filesystem-synchronized test root currently contributes 29 Swift files, 39 `XCTestCase` classes, and 513 active `func test...` declarations to the app-hosted bundle. The successful build-for-testing produced an app-hosted test bundle at `shafinMultitool.app/PlugIns/shafinMultitoolTests.xctest`. That proves target membership and compilation, not that the tests passed at runtime.

`shafinMultitoolTests/UITests.swift` is the only source using `XCUIApplication`. It is therefore pseudo-UI automation incorrectly living in the unit-test target. `DeviceBenchmarkUITests.swift` is not a runnable UI test: it deliberately throws `XCTSkip` because the current benchmark harness is app-hosted. A real UI target should initially contain only the migrated `UITests.swift` source after it is made deterministic and assertion-complete.

The required generic build-for-testing passed. Runtime test execution and test-name enumeration were not proven on this host because CoreSimulatorService was unavailable; that environment limitation is recorded below rather than treated as a passing UI gate.

## Evidence ledger

### Repository and project state

| Check | Result |
| --- | --- |
| `git status --short --branch` before audit | `## HEAD (no branch)`; no pre-existing worktree changes were present. |
| `git rev-parse HEAD` | `faf3e12abd6443877c7e5072fd67c878cce68553`. |
| `xcodebuild -list -workspace shafinMultitool.xcworkspace` | Environment-blocked. Attempts reported `CoreSimulatorService connection became invalid`, `Connection refused`, and inability to discover simulator runtimes; a retry ended with exit 66 and `xcodebuild: error: 'shafinMultitool.xcworkspace' is not a workspace file.` The workspace XML itself is valid and references `Pods/Pods.xcodeproj` and `shafinMultitool.xcodeproj` (`shafinMultitool.xcworkspace/contents.xcworkspacedata:1-10`). |
| `xcodebuild -list -project shafinMultitool.xcodeproj` fallback | Exit 0. Targets: `shafinMultitool`, `shafinMultitoolTests`. Schemes: `shafinMultitool`. |
| Xcode version | Xcode 26.6, build 17F113. |

The workspace-list failure is a host/tooling preflight blocker, not evidence that the checked-in workspace XML is malformed. It must be rerun on a host with a healthy CoreSimulator/Xcode environment before using the workspace command as a CI gate.

### Build and target membership

Required command:

```bash
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/cc005-build-derived CODE_SIGNING_ALLOWED=NO build-for-testing
```

Result: exit 0, `** TEST BUILD SUCCEEDED **`. The build emitted a warning for `Resources/Circle.rcproject` having no processing rule, plus existing Swift warnings, but no compile or link errors.

The generated xctestrun file was:

```text
/private/tmp/cc005-build-derived/Build/Products/shafinMultitool_shafinMultitool_iphoneos26.5-arm64.xctestrun
```

Its `shafinMultitoolTests.xctest` entry records:

- `IsAppHostedTestBundle = true`;
- `ProductModuleName = shafinMultitoolTests`;
- `TestHostBundleIdentifier = com.vigvamcev-media.shafinMultitool`;
- `TestHostPath = __TESTROOT__/Debug-iphoneos/shafinMultitool.app`;
- `TestBundlePath = __TESTHOST__/PlugIns/shafinMultitoolTests.xctest`;
- 29 source files, matching the synchronized test root.

Project evidence is in `shafinMultitool.xcodeproj/project.pbxproj:75-93,161-239,333-380`. The test target is a filesystem-synchronized root at `shafinMultitoolTests`, has no source/resource exceptions, depends on the app target, and has `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/shafinMultitool.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/shafinMultitool"` plus `BUNDLE_LOADER = "$(TEST_HOST)"` in both Debug and Release.

The shared scheme is `shafinMultitool.xcodeproj/xcshareddata/xcschemes/shafinMultitool.xcscheme:25-44`: its only testable reference is `shafinMultitoolTests.xctest`, and `shouldAutocreateTestPlan = "YES"`. No checked-in `.xctestplan` file was found.

`xcodebuild -enumerate-tests` against a generic iOS destination completed only an app build and did not emit test names. Direct xctestrun enumeration could not run because CoreSimulatorService was unavailable. Therefore this audit uses the source list from the successful xctestrun and the project membership graph, not an unverified runtime enumeration.

## Complete current-source classification

All files below currently compile in `shafinMultitoolTests.xctest`. “Default” describes the proposed normal simulator unit/integration gate; it does not claim that runtime execution passed on this host.

### Keep in the unit/integration bundle and default gate

These 24 files are deterministic unit, contract, persistence, parser, presentation, or mocked-pipeline coverage. They must remain out of the future UI target:

- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` — deterministic analysis/presentation/replay contracts. Keep the opt-in still-image export method out of the default gate; see the opt-in list below.
- `shafinMultitoolTests/CameraAnalysisDomainContractsTests.swift` — domain contracts, serialization, aggregators, and golden fixtures.
- `shafinMultitoolTests/CameraOverlayUXPresentationTests.swift` — pure overlay/presentation state tests; no `XCUIApplication`.
- `shafinMultitoolTests/ConverterTests.swift` — pure conversion tests.
- `shafinMultitoolTests/DecisionTracePresentationTests.swift` — pure decision-trace presentation tests.
- `shafinMultitoolTests/DeepCriticOffloadingCoordinatorTests.swift` — provider/validation/offload contract tests with controlled providers; no UI.
- `shafinMultitoolTests/DeviceBenchmarkSupportTests.swift` — pure benchmark configuration and aggregate-metric tests; keep in the default unit gate. It does not execute a device benchmark.
- `shafinMultitoolTests/FrameCritiqueEngineTests.swift` — deterministic frame-critique rules and issue tests.
- `shafinMultitoolTests/HybridFusionServiceTests.swift` — pure fusion and trace tests.
- `shafinMultitoolTests/LemmatizerTests.swift` — pure language-processing unit tests.
- `shafinMultitoolTests/NeuralEvidenceInferenceServiceTests.swift` — fixture/mocked inference-pipeline tests; no live model or UI requirement in the inspected source.
- `shafinMultitoolTests/PauseReasoningCoordinatorTests.swift` — async provider, cancellation, validation, and trace contracts.
- `shafinMultitoolTests/RealtimeSchedulerTests.swift` — deterministic scheduler and media-fixture tests.
- `shafinMultitoolTests/SceneBundlePipelineTests.swift` — parser/planner/thermal/chunking/presentation integration tests; references AR-related types but does not create a live AR session or `XCUIApplication`.
- `shafinMultitoolTests/SceneParserServiceTests.swift` — parser and diagnostics tests with local controlled inputs.
- `shafinMultitoolTests/SceneSaveLoadTests.swift` — persistence integration tests. The inspected cases use nil/synthetic `ARWorldMap` values rather than a live AR session, so they are not device-only; several optional-load branches need stronger failure assertions.
- `shafinMultitoolTests/SceneV8PipelineTests.swift` — deterministic scene-pipeline contracts. Its two live-model methods are opt-in and must be excluded from the normal gate.
- `shafinMultitoolTests/ScriptParsingTests.swift` — pure script parsing tests.
- `shafinMultitoolTests/SemanticTipPlannerTests.swift` — planner and presentation integration tests without UI automation.
- `shafinMultitoolTests/SettingsTests.swift` — settings/UserDefaults state tests.
- `shafinMultitoolTests/ThermalGovernorTests.swift` — thermal policy tests using `ProcessInfo.ThermalState`, not a device benchmark.
- `shafinMultitoolTests/UserDefaultsTests.swift` — persistence tests; isolate shared `UserDefaults.standard` state before enabling high parallelism.
- `shafinMultitoolTests/VisualSemanticEvidenceCoordinatorTests.swift` — provider/pipeline validation contracts.
- `shafinMultitoolTests/shafinMultitoolTests.swift` — template smoke test plus an empty `measure` example. Preserve compilation, but replace or exclude the empty performance example from any meaningful release gate.

### Keep source-compatible but execute only in explicit opt-in gates

These files are not UI tests and should not be moved to the UI target:

- `shafinMultitoolTests/DeviceBenchmarkHarnessTests.swift` — device benchmark harness. It builds a `DeviceBenchmarkCoordinator`, runs with `interactive: false`, and asserts benchmark artifacts. Classify as physical-device-only and run only with an explicit benchmark configuration.
- `shafinMultitoolTests/PerformanceTests.swift` — synthetic persistence/encoding/performance tests. Run in a separate performance lane with result metrics; do not include in the normal unit gate. It is not device-only based on the inspected implementation.
- `shafinMultitoolTests/SceneScriptsMarkdownSmokeTests.swift` — local GGUF/model integration smoke. It hard-codes `/Users/unterlantas/Documents/XCode/shafinMultitool/...` paths and writes to `/private/tmp`; it is not a portable default CI test until paths and model provisioning are made runner-relative. Its output persistence also uses `try?`, so output-write failure can be silent.

Opt-in methods inside otherwise default-bundle files:

- `AnalysisPipelinePresentationTests.swift::SemanticEvalStillImageBatchReplayTests.testExportSemanticEvalCandidateOutputsFromStillImages` — skips unless semantic-eval configuration is supplied through environment/config.
- `SceneV8PipelineTests.swift::SceneV8PipelineTests.testLiveLocalModelSmokeCases` — skips unless `SG_RUN_LIVE_MODEL_SMOKE=1` or `/tmp/scene_live_model_smoke.enabled` exists.
- `SceneV8PipelineTests.swift::SceneV8PipelineTests.testLiveLocalModelDatasetSampledCases` — skips unless `SG_RUN_LIVE_MODEL_DATASET_SMOKE=1` or `/tmp/scene_live_dataset_smoke.enabled` exists.

### Move to the future UI-test target

- `shafinMultitoolTests/UITests.swift` — the only source that creates `XCUIApplication`. It currently launches the app-hosted unit bundle, assumes a pre-existing scene list, and contains guarded paths that can do no work without failing. It is a pseudo-UI suite, not a reliable UI gate.

### Do not count as a current UI test

- `shafinMultitoolTests/DeviceBenchmarkUITests.swift` — one test that unconditionally throws `XCTSkip` with the message that a dedicated UI target is required. Do not copy it into the new UI target. Either retire it or replace it with a real benchmark-mode UI test in a separately authorized source change; an expected skip must not be reported as a passing UI check.

## API, environment, and false-green audit

The complete special-API scan found:

```text
XCUIApplication: shafinMultitoolTests/UITests.swift:13,17
XCTSkip: DeviceBenchmarkUITests.swift:13-15; AnalysisPipelinePresentationTests.swift:4411; SceneV8PipelineTests.swift:1079,1131
ProcessInfo.processInfo.environment: AnalysisPipelinePresentationTests.swift:4462; SceneV8PipelineTests.swift:224
ProcessInfo.ThermalState: ThermalGovernorTests.swift:57 (type-level test input, not an environment gate)
```

The app contains only unrelated identifiers found during the audit (`deviceBenchmarkStatusLabel`, `deviceBenchmarkStartButton`, `deviceBenchmarkCompleteButton`, `deviceBenchmarkGuidedOverlay`, and `decision_trace_sheet`). The legacy UI suite’s expected identifiers such as `recordButton`, `stopButton`, `addActorButton`, and camera-setting controls are not present in the inspected app source. The suite itself comments that accessibility identifiers are still needed (`UITests.swift:32,107,121,140`).

False-green or misleading-pass risks that must be handled before relying on a UI/release gate:

| Location | Risk | Required treatment |
| --- | --- | --- |
| `UITests.swift:64-82,86-100,102-131,135-392` | Many tests execute their body only when `sceneCells.count > 1`; nested controls are often guarded by `waitForExistence` without an `else` failure. A missing/empty fixture can therefore pass without testing the intended flow. | Seed an isolated fixture, assert preconditions, use stable accessibility identifiers, and fail explicitly when a required control or transition is absent. |
| `UITests.swift:268,295` | Resolution/FPS assertions are commented out. | Restore observable state assertions in the migrated UI source. |
| `UITests.swift:401-403` | The file defines an `XCUIElement.waitForExistence(timeout:)` extension whose body calls the same signature. Treat this as a migration-time compile/behavior check rather than relying on it as a custom helper. | Remove the wrapper and call XCTest’s API directly, or give any helper a distinct name. |
| `DeviceBenchmarkUITests.swift:12-15` | Unconditional `XCTSkip`; a green test command can still contain no benchmark validation. | Keep out of the default gate and require zero unexpected skips in the device/UI lane. |
| `AnalysisPipelinePresentationTests.swift:4409-4411` and `SceneV8PipelineTests.swift:1077-1131` | Optional evaluation/model tests skip when configuration is absent. | Select them only in configured lanes and report skips separately from passes. |
| `PerformanceTests.swift:333-352` | `testNoMemoryLeaksDuringLongRecording` is synthetic JSON encoding and ends with `XCTAssertTrue(true)`; it is not a memory-leak measurement. | Keep as low-signal legacy coverage only; replace with an instrumented performance/memory test before using it as a threshold gate. |
| `SceneSaveLoadTests.swift:74-78` and similar optional-load branches | Some load assertions are inside `if let` with no failure branch. | Add explicit `XCTFail` for an absent expected record in the implementation slice that changes tests. |
| `SceneScriptsMarkdownSmokeTests.swift:7-8,402-406` | Absolute developer paths and silent `try?` output persistence make the result non-portable and potentially incomplete. | Move paths to test-bundle/repository configuration and fail on output-write errors before enabling CI. |
| `README_TESTS.md` | Documents a `shafinMultitoolTests` scheme, but the project exposes only the `shafinMultitool` scheme. | Treat README commands as stale documentation evidence; use the checked-in project/scheme graph until documentation is updated by its owner. |

## Simulator, device, and resource boundaries

The built app declares iOS 17.0, `arm64`, and `arkit` requirements and supports iPhone/iPad families. `shafinMultitool/Resources/SceneDelegate.swift:20-32` selects `DeviceBenchmarkRootView` when `DeviceBenchmarkConfig.fromEnvironment()` resolves; otherwise it launches `SOModuleBuilder`. This is why the benchmark harness and live camera/AR behavior must not be inferred from ordinary unit execution.

`shafinMultitool/Resources/DeviceBenchmark` contains 182 files and is approximately 51 MB. The resources are currently app resources, not UI-test resources; the successful build copied benchmark manifests/JSONL and model artifacts into the app bundle. Keep that app-side resource ownership for the benchmark gate. A future Release-resource policy is outside CC-005.

| Lane | Host requirement | Current evidence/classification |
| --- | --- | --- |
| Unit/contract/persistence | Simulator or device; no live camera/AR required for the inspected default files | 24 files above; runtime not executed on this host. |
| UI smoke | A booted simulator is sufficient only for deterministic shell/navigation assertions; live camera/AR/thermal behavior requires physical hardware | `UITests.swift` currently assumes the legacy scene UI and is not reliable until migrated. |
| Model/evaluation smoke | Configured local/CI runner with the model/data paths and environment variables | Semantic replay, Scene V8 live tests, and `SceneScriptsMarkdownSmokeTests`. |
| Device benchmark | Physical iOS device with camera/AR/thermal/Metal/runtime capabilities and benchmark configuration | `DeviceBenchmarkHarnessTests`; artifacts must be inspected, not just the XCTest exit code. |

## Mechanical implementation plan for a true UI target

This is the exact plan for the next implementation slice. It is intentionally not applied by this audit.

### Target definition

Create:

- Target name: `shafinMultitoolUITests`.
- Product type: `com.apple.product-type.bundle.ui-testing`.
- Bundle identifier shape: `com.vigvamcev-media.shafinMultitoolUITests`. This is an identifier shape only; signing, provisioning, and final entitlements are not claimed here.
- Deployment target: iOS 17.0 to match the app’s minimum deployment target.
- Targeted device family: `1,2` to match the current app/test target declarations; the initial CI smoke destination should still pin one supported iPhone simulator.
- Test target relationship: `TEST_TARGET_NAME = shafinMultitool`; do not copy the unit target’s `TEST_HOST`/`BUNDLE_LOADER` settings into the UI target.

### Exact initial source membership

The new target should initially contain exactly one source:

```text
shafinMultitoolTests/UITests.swift
```

The implementation may move/rename it to `shafinMultitoolUITests/UITests.swift` as part of the project edit, but no other current test source belongs in the initial UI target. Remove `@testable import shafinMultitool` if the migrated file only uses `XCTest`/`XCUIApplication`; retain it only if the compiler proves an app-module symbol is actually needed.

Do not add `DeviceBenchmarkUITests.swift` to this target. It is a skipped placeholder, not UI coverage. Do not add `DeviceBenchmarkHarnessTests.swift`, `PerformanceTests.swift`, model smoke tests, or any of the 24 unit/integration files.

The existing `shafinMultitoolTests` target should retain all non-UI source files for coverage continuity. Execution selection, not a broad source deletion, separates its default unit gate from the explicit performance, model, and device benchmark gates. The placeholder `DeviceBenchmarkUITests.swift` must be excluded from default execution and separately retired or replaced; its current skip is not meaningful coverage.

### UI source hardening required before enabling the gate

1. Replace pre-existing-scene assumptions with a deterministic launch fixture and cleanup/reset path.
2. Add stable production accessibility identifiers for the controls actually covered, or use a dedicated test-only deterministic surface if product code ownership chooses that route. The audit does not decide the product UI contract.
3. Assert every required precondition and transition; no `if` branch may silently bypass the test body.
4. Replace commented assertions and coordinate/label guesses with observable state assertions.
5. Use XCTest expectations and element waits, not fixed sleeps. Ensure each test can run from a clean app state and does not depend on ordering or shared UserDefaults.
6. Keep live camera/AR recording and thermal claims out of the simulator UI smoke lane; those belong to the device benchmark lane.

### Scheme and test-plan changes

The minimum project change is to keep the shared `shafinMultitool` scheme and add a second `TestableReference` for `shafinMultitoolUITests.xctest` to its `TestAction`, alongside the existing `shafinMultitoolTests.xctest` reference.

For reproducible local/CI selection, replace `shouldAutocreateTestPlan = "YES"` with a checked-in shared test plan named `shafinMultitool.xctestplan`. Its configurations should be:

- `Unit`: `shafinMultitoolTests` with the opt-in model/eval, performance, device benchmark, and placeholder tests disabled.
- `UISmoke`: `shafinMultitoolUITests` only.
- `Performance`: `shafinMultitoolTests/PerformanceTests` only, with result metrics retained.
- `DeviceBenchmark`: `shafinMultitoolTests/DeviceBenchmarkHarnessTests` only, with `DEVICE_BENCHMARK_CONFIG_BASE64` supplied by the runner and a physical-device destination.

The existing benchmark resources remain app resources. No new CocoaPod is required for a UI target that imports only XCTest/XCUI; if CocoaPods requires a target stanza for generated support, add it only during the project implementation and verify the generated workspace rather than assuming it.

## Proportional local/CI gates

The commands below are the proposed gates after the target/scheme implementation. The simulator name/OS must be pinned to an actually installed runtime; this host could not discover one. `iPhone 15` is the current README example, not a verified installed destination.

### 1. Topology and compile preflight

```bash
xcodebuild -list -workspace shafinMultitool.xcworkspace
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build-for-testing
```

Expected result: workspace lists `shafinMultitool` and `shafinMultitoolTests` plus the new `shafinMultitoolUITests` target/scheme membership; build-for-testing exits 0. This gate does not claim runtime test success.

### 2. Default unit/integration simulator gate

```bash
xcodebuild test \
  -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=<pinned-installed-OS>' \
  -only-testing:shafinMultitoolTests \
  -skip-testing:shafinMultitoolTests/DeviceBenchmarkHarnessTests \
  -skip-testing:shafinMultitoolTests/DeviceBenchmarkUITests \
  -skip-testing:shafinMultitoolTests/PerformanceTests \
  -skip-testing:shafinMultitoolTests/SceneScriptsMarkdownSmokeTests \
  -skip-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testExportSemanticEvalCandidateOutputsFromStillImages \
  -skip-testing:shafinMultitoolTests/SceneV8PipelineTests/testLiveLocalModelSmokeCases \
  -skip-testing:shafinMultitoolTests/SceneV8PipelineTests/testLiveLocalModelDatasetSampledCases \
  -resultBundlePath "$RESULTS/unit.xcresult"
```

Expected result: exit 0, no unexpected failures, and no skipped test silently accepted as a required result. If the test plan is used instead, select the `Unit` configuration rather than duplicating the skip list in CI.

### 3. UI smoke simulator gate

```bash
xcodebuild test \
  -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=<pinned-installed-OS>' \
  -only-testing:shafinMultitoolUITests/UITests \
  -resultBundlePath "$RESULTS/ui-smoke.xcresult"
```

Expected result: the migrated UI suite launches a clean fixture, exercises only deterministic shell/navigation behavior, and exits 0 with no skipped UI tests. Do not use this result to claim camera capture, AR tracking, thermal behavior, or device performance.

### 4. Explicit performance gate

```bash
xcodebuild test \
  -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=<pinned-installed-OS>' \
  -only-testing:shafinMultitoolTests/PerformanceTests \
  -resultBundlePath "$RESULTS/performance.xcresult"
```

Expected result: metrics are retained and compared by the performance lane. The synthetic memory test must not be interpreted as a leak-proof result.

### 5. Explicit physical-device benchmark gate

```bash
DEVICE_BENCHMARK_CONFIG_BASE64="$DEVICE_BENCHMARK_CONFIG_BASE64" \
xcodebuild test \
  -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'id=<pinned-physical-device-UDID>' \
  -only-testing:shafinMultitoolTests/DeviceBenchmarkHarnessTests \
  -resultBundlePath "$RESULTS/device-benchmark.xcresult"
```

Expected result: the benchmark test completes on physical hardware and the runner validates the emitted `combined_summary.json`, run manifest, device information, performance samples, and archive. XCTest exit 0 alone is insufficient evidence for the benchmark outcome. This lane should be manual/nightly or release-candidate scoped, not part of the ordinary simulator PR gate.

### 6. Configured model/evaluation lanes

Run semantic replay only with `SEMANTIC_EVAL_*` inputs and run Scene V8 live tests only with their explicit `SG_*` configuration and model path. Run `SceneScriptsMarkdownSmokeTests` only on a runner that provides portable script/model paths after the path dependency is corrected. These are integration/evaluation lanes, not UI tests and not default unit coverage.

## Migration order

1. Re-run workspace discovery and simulator preflight on a healthy Xcode/CoreSimulator host; pin the CI destination.
2. Add `shafinMultitoolUITests` with the exact product/build settings above and link it to `shafinMultitool` through `TEST_TARGET_NAME`.
3. Move only `UITests.swift` to the new target; leave all unit/integration/benchmark sources in their current target until each gate is verified.
4. Harden the migrated UI suite with deterministic fixture/reset behavior, identifiers, explicit failures, and no-op-path removal.
5. Add the UI testable reference and checked-in test-plan configurations; keep the existing unit bundle reference.
6. Verify the default unit gate with explicit exclusions for model/eval, performance, device benchmark, and skipped placeholder tests.
7. Verify the UI smoke gate independently on the pinned simulator.
8. Verify the physical-device benchmark gate and its artifact summary separately. Do not promote a skipped `DeviceBenchmarkUITests` placeholder into a green result.
9. Only after these gates are independently reproducible, retire or replace the placeholder and update stale test documentation in its owning task.

## Open judgments and gaps

- The current UI suite targets the legacy scene-list/camera flow. The product plan identifies Camera Coach as the intended primary experience, but this audit does not choose a product route or rewrite the suite around that product decision. The implementation owner must confirm which currently supported shell is the deterministic UI fixture.
- The workspace-list command and runtime enumeration remain unverified on this host because CoreSimulatorService was unavailable. The project-list fallback and successful generic build provide target/membership evidence, but they are not a substitute for a healthy simulator test run.
- The bundle identifier above is a planned shape only. Signing, provisioning, entitlements, and device registration remain implementation/release concerns.
- A separate benchmark target was not invented here. The current plan separates benchmark execution through explicit test-plan/CI gates while preserving source membership; creating a dedicated benchmark target would be a separate project-scope decision.
- No source, project, scheme, product-plan, status, backlog, or other audit file was changed by this audit. The only intended artifact is this file.
