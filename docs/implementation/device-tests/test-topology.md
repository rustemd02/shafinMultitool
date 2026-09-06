# test-topology — M13-001 locked lane contract

Status: **locked topology (v1).**

## Default production lane

`xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool`
on one permitted simulator (iPhone 17 / 17e / Air, iOS 26.5), single batch
per fresh boot (`-parallel-testing-enabled NO`), one
`-derivedDataPath` per lane, durable `.xcresult` per run. The lane includes
all `shafinMultitoolTests/**` unit/integration suites and
`shafinMultitoolUITests/**` production UI suites.

## Explicit lanes with documented prerequisites

| Lane | Entry | Prerequisite |
|---|---|---|
| recording/media regression (M7-031) | 17 named suites (see `evidence-m7/M7-031-lane-summary.txt`) | permitted simulator, fresh boot |
| device benchmark harness | `DEVICE_BENCHMARK_CONFIG_BASE64` set + physical device | real hardware (M13) |
| semantic replay export | `semantic_eval_replay_config.json` or env config | eval corpus present (M4) |
| release bundle gate | `scripts/tests/test_release_bundle_gate.sh --release-app <fresh Release .app>` | fresh signed Release build |
| release provenance gate | `scripts/tests/test_release_provenance_gate.sh` | release manifests |
| Python validators | `python3 <validator> --self-test` | stdlib + pinned deps |

## Skipped tests are reported

Every `XCTSkip` carries its prerequisite in the message
(benchmark config, fixture 019 availability, iOS 18 strides, replay
config). Skips surface in the xcresult summary (`skippedTests`) and are
never silently converted to passes. Current known skips live in:
`DETRDetectorTests`, `DeviceBenchmarkHarnessTests`,
`DeviceBenchmarkUITests`, `AnalysisPipelinePresentationTests`,
`SceneV8PipelineTests`, `SceneScriptsMarkdownSmokeTests`,
`HorizonEstimatorTests`, `CommercialShellModeControlTests`,
`RecordingLifecycleTransitionTests`.
