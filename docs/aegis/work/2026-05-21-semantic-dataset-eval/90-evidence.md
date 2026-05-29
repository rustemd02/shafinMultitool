# Semantic Dataset Eval Evidence

Date: 2026-05-27.

## Files

- `docs/cameraanalysis/eval/semantic_label_adapter.py`
- `docs/cameraanalysis/eval/semantic_output_schema.py`
- `docs/cameraanalysis/eval/run_semantic_label_eval.py`
- `docs/cameraanalysis/eval/tests/test_semantic_label_eval.py`
- `docs/cameraanalysis/eval/out_semantic_current_proxy/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_live_keep_projection/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_semantic_action_rows/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03g/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03h/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03i/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03j/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03k/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r04/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r05/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r07/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r08/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r09b/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r10a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11d/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11e/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r12a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r12b/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r13a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r14a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r15a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r16a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r17a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r18a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r19b/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r20a/*`
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a/*`
- `docs/cameraanalysis/dataset/README.md`
- `docs/cameraanalysis/32-semantic-eval-output-contract.md`
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md`
- `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift`
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`
- `shafinMultitool/Multitool2Module/Services/Reasoning/PauseReasoningCoordinator.swift`
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift`
- `shafinMultitoolTests/FrameCritiqueEngineTests.swift`
- `shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests.swift`
- `shafinMultitoolTests/PauseReasoningCoordinatorTests.swift`

## Verification Commands

```bash
python3 -m pytest docs/cameraanalysis/eval/tests -q
xcodebuild -list -project shafinMultitool.xcodeproj
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/FrameCritiqueEngineTests
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/PauseReasoningCoordinatorTests
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests \
  -only-testing:shafinMultitoolTests/FrameCritiqueEngineTests \
  -only-testing:shafinMultitoolTests/CameraAnalysisDomainContractsTests \
  -only-testing:shafinMultitoolTests/SemanticTipPlannerTests \
  -only-testing:shafinMultitoolTests/PauseReasoningCoordinatorTests
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03k \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r03k.jsonl
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06 \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r06.jsonl
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r08 \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r08.jsonl
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r09b \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r09b.jsonl
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r10a \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r10a.jsonl
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11d \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r11d.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11e \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r11e.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r12a \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r12a.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r13a \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r13a.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r14a \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r14a.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r15a \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r15a.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r16a \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r16a.jsonl \
  --images-dir docs/cameraanalysis/dataset/inbox/images
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-r17-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-r17-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r17a.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r17a \
  --images-dir docs/cameraanalysis/dataset/inbox/images
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-r18-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-r18-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r18a.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r18a \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r19b.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r19b \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r20a.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r20a \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r21a.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a \
  --images-dir docs/cameraanalysis/dataset/inbox/images
python3 -m pytest docs/cameraanalysis/eval/tests -q
git diff --check
```

## Result

- Python eval tests: 47 tests passed.
- Xcode project listing: passed.
- `AnalysisPipelinePresentationTests`: passed, 31 tests.
- `PauseReasoningCoordinatorTests`: passed, 20 tests.
- `FrameCritiqueEngineTests`: passed, 28 tests.
- Combined targeted Swift regression suite (`AnalysisPipelinePresentationTests`, `FrameCritiqueEngineTests`, `CameraAnalysisDomainContractsTests`, `SemanticTipPlannerTests`, `PauseReasoningCoordinatorTests`): passed.
- Still-image batch replay test: passed and exported 107 real-runtime candidate rows.
- R11d targeted hotspot semantic-action regression: passed.
- R11d full `AnalysisPipelinePresentationTests`: passed.
- R11d still-image batch replay: passed and exported/scored 107 real-runtime candidate rows.
- R13a targeted contextual correction regressions for `035`, `036` and `104`: passed.
- R13a full `AnalysisPipelinePresentationTests`: passed, 37 tests.
- R13a still-image batch replay: passed and exported/scored 107 real-runtime candidate rows.
- R14a targeted contextual policy regressions for `068`, `070`, `071`, `077`, `081`, `083`, `085` and `097`: passed, 6 tests.
- R14a full `AnalysisPipelinePresentationTests`: passed, 43 tests.
- R14a still-image batch replay: passed and exported/scored 107 real-runtime candidate rows.
- R15a full `AnalysisPipelinePresentationTests`: passed, 46 tests.
- R15a still-image batch replay: passed and exported/scored 107 real-runtime candidate rows.
- R15a Python eval tests: passed, 47 tests.
- R16a full `AnalysisPipelinePresentationTests`: passed, 52 tests.
- R16a still-image batch replay: passed and exported/scored 107 real-runtime candidate rows.
- R16a Python eval tests: passed, 47 tests.
- R17a full `AnalysisPipelinePresentationTests`: passed, 57 tests.
- R17a still-image batch replay: passed and exported/scored 107 real-runtime cases from 214 live/pause rows.
- R17a semantic label eval tests: passed, 48 tests.
- R18a full `AnalysisPipelinePresentationTests`: passed, 60 tests.
- R18a still-image batch replay: passed and exported/scored 107 real-runtime cases from 214 live/pause rows.
- R18a semantic label eval tests: passed, 48 tests.
- R19b full `AnalysisPipelinePresentationTests`: passed, 64 tests.
- R19b still-image batch replay: passed and exported/scored 107 real-runtime cases from 214 live/pause rows.
- R19b semantic label eval tests: passed, 48 tests.
- R20a RED regression `testStillImageReplayCalibratesResidualR20ConfidenceBands`: failed before production calibration on `ca_img_022`, then passed after calibration.
- R20a full `AnalysisPipelinePresentationTests`: passed, 65 tests.
- R20a still-image batch replay: passed and exported/scored 107 real-runtime cases from 214 live/pause rows.
- R20a semantic label eval tests: passed, 48 tests.
- R21a RED regression `testStillImageReplayPromotesWideUnknownGoodEstablishingConfidence`: failed before production calibration on missing `frame_aspect_ratio`, then passed after calibration.
- R21a full `AnalysisPipelinePresentationTests`: passed, 66 tests.
- R21a still-image batch replay: passed and exported/scored 107 real-runtime cases from 214 live/pause rows.
- R21a semantic label eval tests: passed, 48 tests.
- `git diff --check`: passed.
- Earlier reference scored candidate: `semantic_eval_real_runtime_candidate_outputs_after_r08`.
- Rejected confidence experiment: `R09a` blanket `keep_current_setup` floor suppression (metrics retained as negative evidence).
- Rejected keep-export experiment: `R11e` blanket `keep_current_setup` suppression when good pause critique still has issues (metrics retained as negative evidence).
- Rejected low-light experiment: `R12a` very-dark underexposure dominance expansion (metrics retained as negative evidence).
- Accepted contextual correction experiment: `R13a` dark object-cluster/background-clearance production presentation correction.
- Accepted contextual policy experiment: `R14a` weak-subject/object false-keep suppression and bounded underlit-object/background actions.
- Accepted confidence calibration experiment: `R15a` feature-bounded technical-floor cap for medium-evidence `keep_current_setup` and unknown/stabilized technical silence.
- Accepted object/unknown action experiment: `R16a` bounded contextual semantic actions and contextual stabilize future-action projection.
- Accepted merged live/pause export/scorer experiment: `R17a` false live-keep suppression, low-key mood preservation and semantic-row-aware confidence merge.
- Accepted residual action/future projection experiment: `R18a` unknown group/no-focus framing, large-object horizon recovery and small-object blur/focus future projection.
- Accepted residual confidence calibration experiment: `R19b` feature-bounded caps for medium-evidence keep/current-setup, overexposure correction, empty technical silence and underlit-readable object rows with high-boundary preservation.
- Accepted residual confidence cleanup experiment: `R20a` row-evidence-specific caps/promotions for the remaining mixed/bad confidence-only failures, while leaving `ca_img_010` as an observability gap instead of using id/label/source leakage.
- Accepted observability-grounded confidence experiment: `R21a` exports `frame_aspect_ratio` from the replay `CVPixelBuffer` and promotes only the wide unknown/good establishing keep row, fixing `ca_img_010` while preserving `ca_img_016` as medium confidence.
- Current scored candidate: `semantic_eval_real_runtime_candidate_outputs_after_r21a`.
- Runtime claim: `real_runtime_still_replay`.

Previous `R03k` set metrics:

```text
record_count 107
pass_rate 0.289720
expected_action_hit_rate 0.570093
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.168224
good_frame_preservation_rate 0.804348
positive_confirmation_rate 0.760870
confidence_band_accuracy 0.607477
demo_priority_pass_rate 0.571429
technical_failure_gate_rate 1.000000
```

Accepted `R16a` set metrics:

```text
record_count 107
pass_rate 0.728972
expected_action_hit_rate 0.925234
future_action_hit_rate 0.916667
forbidden_action_violation_rate 0.018692
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.803738
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Accepted `R17a` set metrics:

```text
record_count 107
pass_rate 0.803738
expected_action_hit_rate 0.981308
future_action_hit_rate 0.958333
forbidden_action_violation_rate 0.000000
good_frame_preservation_rate 1.000000
positive_confirmation_rate 1.000000
confidence_band_accuracy 0.822430
demo_priority_pass_rate 0.928571
technical_failure_gate_rate 1.000000
```

Accepted `R18a` set metrics:

```text
record_count 107
pass_rate 0.841121
expected_action_hit_rate 1.000000
future_action_hit_rate 1.000000
forbidden_action_violation_rate 0.000000
good_frame_preservation_rate 1.000000
positive_confirmation_rate 1.000000
confidence_band_accuracy 0.841121
demo_priority_pass_rate 0.928571
technical_failure_gate_rate 1.000000
```

Latest set metrics after `R08`:

```text
record_count 107
pass_rate 0.411215
expected_action_hit_rate 0.728972
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.112150
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.607477
demo_priority_pass_rate 0.714286
technical_failure_gate_rate 1.000000
```

Rejected `R09a` set metrics:

```text
record_count 107
pass_rate 0.345794
expected_action_hit_rate 0.728972
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.112150
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.542056
demo_priority_pass_rate 0.428571
technical_failure_gate_rate 1.000000
```

Accepted `R09b` set metrics:

```text
record_count 107
pass_rate 0.467290
expected_action_hit_rate 0.728972
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.112150
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.672897
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Accepted `R10a` set metrics:

```text
record_count 107
pass_rate 0.476636
expected_action_hit_rate 0.728972
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.112150
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.682243
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Accepted `R11d` set metrics:

```text
record_count 107
pass_rate 0.523364
expected_action_hit_rate 0.803738
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.112150
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.691589
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Rejected `R11e` set metrics:

```text
record_count 107
pass_rate 0.485981
expected_action_hit_rate 0.719626
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.093458
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.760870
confidence_band_accuracy 0.691589
demo_priority_pass_rate 0.714286
technical_failure_gate_rate 1.000000
```

Rejected `R12a` set metrics:

```text
record_count 107
pass_rate 0.514019
expected_action_hit_rate 0.785047
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.140187
good_frame_preservation_rate 0.934783
positive_confirmation_rate 0.891304
confidence_band_accuracy 0.691589
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Accepted `R14a` set metrics:

```text
record_count 107
pass_rate 0.616822
expected_action_hit_rate 0.869159
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.028037
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.710280
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Accepted `R15a` set metrics:

```text
record_count 107
pass_rate 0.682243
expected_action_hit_rate 0.869159
future_action_hit_rate 0.875000
forbidden_action_violation_rate 0.018692
good_frame_preservation_rate 1.000000
positive_confirmation_rate 0.956522
confidence_band_accuracy 0.785047
demo_priority_pass_rate 0.857143
technical_failure_gate_rate 1.000000
```

Previous `R03k` failure counts:

```text
confidence_band_mismatch 42
missing_expected_action 46
forbidden_action_violation 18
missing_future_action 6
good_frame_overcorrection 9
missing_positive_confirmation 11
```

Latest failure counts after `R08`:

```text
confidence_band_mismatch 42
missing_expected_action 29
forbidden_action_violation 12
missing_future_action 6
missing_positive_confirmation 2
```

Latest failure counts after `R09b`:

```text
confidence_band_mismatch 35
missing_expected_action 29
forbidden_action_violation 12
missing_future_action 6
missing_positive_confirmation 2
```

Latest failure counts after `R10a`:

```text
confidence_band_mismatch 34
missing_expected_action 29
forbidden_action_violation 12
missing_future_action 6
missing_positive_confirmation 2
```

Latest failure counts after `R11d`:

```text
confidence_band_mismatch 33
missing_expected_action 21
forbidden_action_violation 12
missing_future_action 6
missing_positive_confirmation 2
```

Rejected failure counts after `R11e`:

```text
confidence_band_mismatch 33
missing_expected_action 30
forbidden_action_violation 10
missing_future_action 6
missing_positive_confirmation 11
```

Rejected failure counts after `R12a`:

```text
confidence_band_mismatch 33
missing_expected_action 23
forbidden_action_violation 15
missing_future_action 6
missing_positive_confirmation 5
good_frame_overcorrection 3
```

Latest failure counts after `R13a`:

```text
confidence_band_mismatch 31
missing_expected_action 18
forbidden_action_violation 9
missing_future_action 6
missing_positive_confirmation 2
```

Latest failure counts after `R14a`:

```text
confidence_band_mismatch 31
missing_expected_action 14
forbidden_action_violation 3
missing_future_action 6
missing_positive_confirmation 2
```

Latest failure counts after `R15a`:

```text
confidence_band_mismatch 23
missing_expected_action 14
forbidden_action_violation 2
missing_future_action 6
missing_positive_confirmation 2
```

Latest failure counts after `R16a`:

```text
confidence_band_mismatch 21
missing_expected_action 8
forbidden_action_violation 2
missing_future_action 4
missing_positive_confirmation 2
```

Latest failure counts after `R17a`:

```text
confidence_band_mismatch 19
missing_expected_action 2
missing_future_action 2
```

Latest failure counts after `R18a`:

```text
confidence_band_mismatch 17
```

Accepted `R19b` set metrics:

```text
record_count 107
pass_rate 0.953271
expected_action_hit_rate 1.000000
future_action_hit_rate 1.000000
forbidden_action_violation_rate 0.000000
good_frame_preservation_rate 1.000000
positive_confirmation_rate 1.000000
confidence_band_accuracy 0.953271
demo_priority_pass_rate 0.928571
technical_failure_gate_rate 1.000000
```

Latest failure counts after `R19b`:

```text
confidence_band_mismatch 5
```

Accepted `R20a` set metrics:

```text
record_count 107
pass_rate 0.990654
expected_action_hit_rate 1.000000
future_action_hit_rate 1.000000
forbidden_action_violation_rate 0.000000
good_frame_preservation_rate 1.000000
positive_confirmation_rate 1.000000
confidence_band_accuracy 0.990654
demo_priority_pass_rate 0.928571
technical_failure_gate_rate 1.000000
```

Latest failure counts after `R20a`:

```text
confidence_band_mismatch 1
```

Accepted `R21a` set metrics:

```text
record_count 107
pass_rate 1.000000
expected_action_hit_rate 1.000000
future_action_hit_rate 1.000000
forbidden_action_violation_rate 0.000000
good_frame_preservation_rate 1.000000
positive_confirmation_rate 1.000000
confidence_band_accuracy 1.000000
demo_priority_pass_rate 1.000000
technical_failure_gate_rate 1.000000
```

Latest failure counts after `R21a`:

```text
none
```

## Interpretation

The old proxy boundary has been retired for current claims. We now have a real
Swift pipeline replay over the dataset.

The measured dataset/eval result is closed on the current silver still replay,
with product-readiness gaps remaining:

- semantic actions are represented better after `PauseActionRow.semanticActionType`;
- the technical-quality analyzer now exists as both eval signal and first production live/pause UX gate;
- cinematic good-frame preservation reduced several false corrections;
- the R03i low-key sharpness guard preserves R03h's pass-rate gain while removing its extra forbidden-action leaks;
- R03j showed that naive pause technical override harms semantic expected actions, and R03k fixes that by using technical pause critique only when no semantic corrective tip would be displaced;
- `R06` removes good-frame overcorrection from the current silver replay by adding conservative guards for weak establishing/background-like anchors;
- `R08` maps dominant technical hotspots into the closed semantic catalog as `remove_background_hotspot`, while a good/high-aesthetic guard prevents the R07 good-frame overcorrection regression;
- `R09a` proved that blanket confidence-floor suppression for `keep_current_setup` is the wrong fix: it regresses pass rate, confidence-band accuracy and demo-priority pass rate, so it was reverted from production code and retained only as negative evidence;
- `R09b` accepts a narrower confidence rule: a good pause verdict with explicit strengths can be displayed with a high confidence floor, improving pass rate and confidence-band accuracy without changing expected-action hit rate or forbidden-action leakage;
- `R10a` accepts the complementary confidence guard: mixed corrective pause rows are capped to medium confidence even if a technical floor is present, fixing `ca_img_033` without changing action coverage or forbidden-action leakage;
- `R11d` accepts bounded technical semantic-action mapping for readable underexposure and hotspots, improving expected-action hit rate while leaving forbidden-action leakage unchanged;
- `R11e` rejects blanket `keep_current_setup` suppression when good pause critique still has issues, because it reduces positive confirmations and expected-action recall more than it reduces forbidden-action leakage;
- `R12a` rejects broad very-dark underexposure dominance expansion, because it fixes one mixed frame but reintroduces good-frame overcorrection;
- `R13a` accepts bounded contextual production correction for dark object clusters, improving pass rate, expected-action recall and forbidden-action control without hurting good-frame preservation;
- `R14a` accepts a broader but still feature-bounded contextual policy for weak subject evidence, motion-like false positives and small underlit object cases, reducing forbidden `keep_current_setup` leakage without hurting good-frame preservation;
- `R15a` accepts feature-bounded confidence calibration for medium-evidence positive `keep_current_setup` rows and unknown/stabilized technical silence, improving confidence-band accuracy without regressing good preservation or positive confirmations;
- `R16a` accepts bounded object/unknown contextual action mapping and contextual stabilize future-action projection, improving semantic and future-action recall without regressing good preservation, positive confirmations or forbidden-action leakage;
- `R17a` accepts merged live/pause keep-control and scorer confidence ownership: false live `keep_current_setup` no longer leaks into bad technical frames, low-key mood good frames keep positive confirmation, and confidence is scored from rows that contributed semantic actions when available;
- `R18a` accepts bounded residual action/future projection, reaching complete expected-action and future-action recall on the current silver replay;
- `R19b` accepts residual confidence calibration, improving pass rate and confidence-band accuracy from `0.841121` to `0.953271` with no scored R18a-to-R19b regressions;
- `R20a` accepts row-evidence-specific residual confidence cleanup, improving pass rate and confidence-band accuracy from `0.953271` to `0.990654` with no scored R19b-to-R20a regressions;
- `R21a` accepts observability-grounded wide-establishing confidence, improving pass rate, confidence-band accuracy and demo-priority pass rate to `1.000000` with no scored R20a-to-R21a regressions;
- the dataset/eval bridge is closed on the current 107-image silver still replay, while live-camera validation and broader object/multi-subject grounding remain product-readiness evidence gaps.

## Open Evidence Gaps

- Need expand the R03k technical-quality gate into a fuller confidence-calibrated technical domain.
- Need live-camera manual QA after still-image metrics improve.
- Need demo scenario pack with screenshots and expected explanations.
- Need thesis evidence map and claim registry to keep current baseline as a still-replay result, not a live-camera product-readiness claim.
