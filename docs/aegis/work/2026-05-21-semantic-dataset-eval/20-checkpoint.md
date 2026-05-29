# Semantic Dataset Eval Checkpoint

Date: 2026-05-27.

## Completed

- Created semantic label loader, validator, candidate schema and scorer.
- Created CLI runner `run_semantic_label_eval.py`.
- Added eval tests for loader, invalid labels, scoring failures, oracle, bad candidate and proxy baseline.
- Added dataset README and raw ChallengeDB ignore policy.
- Added semantic output contract doc.
- Added Swift-side `SemanticEvalCandidateOutput` and `SemanticEvalRuntimeClaim`.
- Added DEBUG-only `AnalysisPipeline.testingReplayStillImageForSemanticEval(...)`.
- Added batch still-image replay test that reads `semantic_labels_v1.jsonl` and exports real runtime candidate rows.
- Added Python scorer support for separate `live` and `pause` rows for the same image.
- Fixed live hint fallback state so unavailable structured path does not keep stale expanded context.
- Fixed presentation/export tests after action-row confidence and semantic action export changes.
- Added `PauseActionRow.semanticActionType` so pause eval exports the semantic action represented by `SemanticTipCandidate`, not only coarse transport action.
- Tightened pause reasoning safety: absolute certainty language such as "guaranteed ideal frame" is rejected for non-good deterministic verdicts.
- Generated and scored measured real-runtime outputs for 107 labeled images.
- Added a DEBUG still-image technical-quality probe that exports future technical actions for focus/exposure/noise/stability eval checks.
- Added a first cinematic-preservation calibration in `FrameCritiqueEngine` so readable anchored subjects and soft style findings are less likely to become unnecessary corrections.
- Added regression tests for readable cinematic clutter, low-key/backlight style, false horizon confidence and multi-person visual overload.
- Generated and scored `R03g`, the first measured replay after cinematic-preservation calibration.
- Added `R03i` technical-quality calibration: very dark low-key frames no longer become dominant blur/focus failures, while moderately dark soft frames still do.
- Generated and scored `R03i`, the measured replay after narrowing the low-key sharpness guard.
- Promoted the technical-quality analyzer into a first production live/pause UX gate.
- Generated and scored `R03j` and `R03k`: `R03j` proved that naive pause technical override hurts semantic expected actions, while `R03k` restores the `R03i` metrics by only using pause technical critique when no semantic corrective tip would be displaced.
- Added `R04`-`R06` cinematic/good-frame preservation calibration for weak establishing anchors, readable aesthetic object-edge compositions and readable background-like anchors.
- Generated and scored `R06`, where silver-replay `good_frame_overcorrection` is reduced from 9 to 0 and `good_frame_preservation_rate` reaches `1.000000`.
- Added `R07`/`R08` dominant hotspot semantic mapping: overexposure technical issues can now export `remove_background_hotspot`, while good/high-aesthetic deterministic frames are guarded from overcorrection.
- Generated and scored `R08`, improving `pass_rate` to `0.411215` and `expected_action_hit_rate` to `0.728972` while preserving `good_frame_preservation_rate=1.000000`.
- Tested and rejected `R09a`, a broad confidence-floor suppression for `keep_current_setup`: real replay regressed, so the production code was restored to the safer `R08` confidence behavior.
- Added and accepted `R09b`, a narrower pause confidence calibration: good pause verdicts with explicit strengths can use a high confidence floor, while weak/empty good verdicts stay conservative.
- Added and accepted `R10a`, the complementary pause export calibration: mixed corrective pause rows are capped to medium confidence even when a technical-quality floor is present.
- Added and accepted `R11d`, a bounded technical semantic-action calibration: underexposure can map to `add_front_fill_light`, and hotspot/overexposure pause fallback can also export `simplify_background`.
- Tested and rejected `R11e`, a blanket rule that suppressed `keep_current_setup` whenever a good pause critique still had issues. It reduced forbidden `keep_current_setup` leaks but regressed pass rate, expected-action recall and positive confirmations, so production code was restored to accepted `R11d`.
- Tested and rejected `R12a`, a very-dark underexposure dominance expansion. It fixed local `ca_img_035`, but full replay overcorrected good low-key frames and regressed overall metrics, so production code and the RED test were removed.
- Added and accepted `R12b`/`R13a`: ambiguous no-subject motion-blur silence can stay low confidence, and dark object-cluster/background-clearance failures can override false `keep_current_setup` through production live/pause contextual correction.
- Added and accepted `R19b`: residual confidence calibration fixes 12 R18a confidence failures without scored R18a-to-R19b regressions.
- Added and accepted `R20a`: row-evidence-specific residual confidence calibration fixes four more R19b confidence failures (`ca_img_022`, `ca_img_078`, `ca_img_082`, `ca_img_090`) without scored R19b-to-R20a regressions; `ca_img_010` remains an honest observability gap.
- Added and accepted `R21a`: runtime-observable `frame_aspect_ratio` evidence fixes `ca_img_010` while preserving medium confidence for near-neighbor `ca_img_016`; the current 107-case silver replay now has no strict failures.

## Active Slice

The real dataset replay bridge is now working. The active work is no longer
"make eval run"; it is "make the system good enough against measured failures".

Current dataset/eval state:

- real replay exists;
- metrics are reproducible;
- metrics are closed on the current 107-image silver still replay; live-camera behavior remains a separate product-readiness gap, not a contradiction of the dataset/eval result.

## Evidence

- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests -only-testing:shafinMultitoolTests/FrameCritiqueEngineTests -only-testing:shafinMultitoolTests/CameraAnalysisDomainContractsTests -only-testing:shafinMultitoolTests/SemanticTipPlannerTests -only-testing:shafinMultitoolTests/PauseReasoningCoordinatorTests` -> passed.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and wrote `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r03k.jsonl`.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and wrote `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r06.jsonl`.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R08 hotspot/good-frame guard changes.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and wrote `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r08.jsonl`.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after removing the rejected `R09a` confidence-floor experiment.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03k --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r03k.jsonl` -> scored 107 cases.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06 --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r06.jsonl` -> scored 107 cases.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r08 --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r08.jsonl` -> scored 107 cases.
- `R09a` was scored before revert and kept as negative evidence in this checkpoint; the production code does not retain the rejected blanket suppression.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor ...` -> passed after the accepted `R09b` confidence calibration.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after `R09b` and wrote 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r09b --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r09b.jsonl` -> scored 107 cases.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testSemanticEvalPauseMixedCorrectiveConfidenceIsNotRaisedByTechnicalFloor ...` -> passed after the accepted `R10a` export confidence cap.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after `R10a`, 31 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after `R10a` and wrote `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r10a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r10a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r10a.jsonl` -> scored 107 cases.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsDominantHotspotToSemanticAction` -> passed after the accepted `R11d` hotspot semantic-action mapping.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after `R11d`.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after `R11d` and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11d --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r11d.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed for rejected `R11e` and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11e --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r11e.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases and showed regression.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after reverting rejected `R11e` production/test changes back to accepted `R11d` behavior.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsVeryDarkMixedFrameToFrontFill ...` -> failed before `R12a`, then passed locally with `006`/`036` guards after the candidate change.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after the candidate `R12a` change.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed for rejected `R12a` and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r12a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r12a.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases and showed regression.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after reverting rejected `R12a` production/test changes back to accepted `R11d` behavior.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 47 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsDarkObjectClusterToBackgroundClearance -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsStrongUnderexposedObjectToMediumFrontFill -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectGoodLowKeyBookWithFrontFill` -> passed after R13a.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R13a, 37 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R13a and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r13a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r13a.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplaySuppressesKeepForUnknownDarkTechnicalFrame ... testStillImageReplayDoesNotMapExtremeTechnicalObjectFailureToFrontFill` -> passed after R14a, 6 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R14a, 43 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R14a and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r14a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r14a.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R15a, 46 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R15a and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r15a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r15a.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after R15a, 47 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R16a, 52 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R16a and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r16a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r16a.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after R16a, 47 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r17-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R17a, 57 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r17-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R17a and exported 214 live/pause real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r17a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r17a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after semantic-row-aware live/pause merge scorer update, 48 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r18-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R18a, 60 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r18-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R18a and exported 214 live/pause real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r18a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r18a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after R18a, 48 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r19-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R19b, 64 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r19-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R19b and exported 214 live/pause real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r19b.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r19b --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after R19b, 48 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r20-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayCalibratesResidualR20ConfidenceBands` -> failed before R20a production calibration on `ca_img_022` confidence band, then passed after calibration.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r20-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R20a, 65 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r20-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R20a and exported 214 live/pause real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r20a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r20a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after R20a, 48 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r21-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPromotesWideUnknownGoodEstablishingConfidence` -> failed before R21a production calibration on missing `frame_aspect_ratio`, then passed after calibration.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r21-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after R21a, 66 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r21-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed after R21a and exported 214 live/pause real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r21a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed after R21a, 48 tests.
- `xcodebuild -list -project shafinMultitool.xcodeproj` -> passed.
- `git diff --check` -> passed.

Latest measured metrics after accepted `R21a`:

- `pass_rate`: 1.000000
- `expected_action_hit_rate`: 1.000000
- `future_action_hit_rate`: 1.000000
- `forbidden_action_violation_rate`: 0.000000
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 1.000000
- `confidence_band_accuracy`: 1.000000
- `demo_priority_pass_rate`: 1.000000
- `technical_failure_gate_rate`: 1.000000

Main failures:

- none

Rejected `R09a` metrics:

- `pass_rate`: 0.345794
- `expected_action_hit_rate`: 0.728972
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.112150
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.542056
- `demo_priority_pass_rate`: 0.428571

Interpretation:

The broad hypothesis "do not raise `keep_current_setup` confidence with
technical floor" was false. It fixed a few medium/low cases, but broke more
high-confidence good frames where deterministic verdict confidence is
conservative and the technical floor currently preserves the intended high
band. The accepted R09b attempt therefore uses a narrower evidence-specific
rule instead of applying a blanket `keep_current_setup` rule.

Accepted `R09b` metrics:

- `pass_rate`: 0.467290
- `expected_action_hit_rate`: 0.728972
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.112150
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.672897
- `demo_priority_pass_rate`: 0.857143

Interpretation:

The narrower R09b hypothesis is accepted: a good pause verdict with explicit
positive strengths may use a high confidence floor (`0.75`) even when the raw
deterministic verdict confidence is conservative. This preserves empty/weak
good verdicts as conservative, improves confidence-band agreement, and does not
change action coverage or forbidden-action leakage. It is not a general
confidence solution.

Accepted `R10a` metrics:

- `pass_rate`: 0.476636
- `expected_action_hit_rate`: 0.728972
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.112150
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.682243
- `demo_priority_pass_rate`: 0.857143

Interpretation:

The R10a hypothesis is accepted: a mixed pause verdict that exports a corrective
semantic action should not be promoted into a high confidence band by an
unrelated technical floor. This fixed `ca_img_033` from
`confidence_band_mismatch` to pass, but it did not improve expected-action hit
rate, forbidden-action leakage or object/multi-subject grounding.

Accepted `R11d` metrics:

- `pass_rate`: 0.523364
- `expected_action_hit_rate`: 0.803738
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.112150
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.691589
- `demo_priority_pass_rate`: 0.857143

Interpretation:

The R11d hypothesis is accepted: dominant technical underexposure/hotspot
fallbacks can map to closed semantic actions (`add_front_fill_light`,
`remove_background_hotspot`, `change_camera_angle`, `simplify_background`)
without increasing forbidden-action leakage. This improved expected-action hit
rate and made two mixed cases pass, but it is still a technical fallback
calibration, not robust object/person grounding.

Rejected `R11e` metrics:

- `pass_rate`: 0.485981
- `expected_action_hit_rate`: 0.719626
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.093458
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.760870
- `confidence_band_accuracy`: 0.691589
- `demo_priority_pass_rate`: 0.714286

Interpretation:

The R11e hypothesis is rejected: suppressing `keep_current_setup` whenever a
good pause critique still has issues is too broad. It reduced forbidden-action
violations from 12 to 10, but increased missing expected actions from 21 to 30
and missing positive confirmations from 2 to 11. This proves the next fix must
produce better grounded corrective actions for bad/mixed frames instead of
removing positive confirmations globally.

Rejected `R12a` metrics:

- `pass_rate`: 0.514019
- `expected_action_hit_rate`: 0.785047
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.140187
- `good_frame_preservation_rate`: 0.934783
- `positive_confirmation_rate`: 0.891304
- `confidence_band_accuracy`: 0.691589
- `demo_priority_pass_rate`: 0.857143

Interpretation:

The R12a hypothesis is rejected: making very dark frames dominant
underexposure fixed `ca_img_035`, but regressed `ca_img_025`, `ca_img_034` and
`ca_img_039` into good-frame overcorrections. This proves the next low-light fix
must distinguish technical failure from intentional low-key/aesthetic darkness,
not just widen a pixel darkness threshold.

Accepted `R14a` metrics:

- `pass_rate`: 0.616822
- `expected_action_hit_rate`: 0.869159
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.028037
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.710280
- `demo_priority_pass_rate`: 0.857143

Interpretation:

R14a is accepted: the contextual production policy now suppresses false
`keep_current_setup` for unknown dark technical frames and motion-like object
false positives, maps weak-subject unknown scenes to `simplify_background`, and
maps a small underlit object case to `add_front_fill_light`. It turns
`ca_img_068`, `ca_img_070`, `ca_img_071`, `ca_img_083` and `ca_img_085` into
passing cases without regressing good-frame preservation.

Accepted `R15a` metrics:

- `pass_rate`: 0.682243
- `expected_action_hit_rate`: 0.869159
- `future_action_hit_rate`: 0.875000
- `forbidden_action_violation_rate`: 0.018692
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.785047
- `demo_priority_pass_rate`: 0.857143

Interpretation:

R15a is accepted: feature-bounded confidence calibration caps technical-floor
boosts for medium-evidence `keep_current_setup` rows and the
`contextual_unknown_stabilized_technical_silence` path. It turns the R14a
confidence-only failures `ca_img_023`, `ca_img_028`, `ca_img_034`,
`ca_img_036`, `ca_img_039`, `ca_img_055` and `ca_img_057` into passing cases,
and removes the forbidden `keep_current_setup` leak from `ca_img_095`; ca095
still correctly remains failed on missing semantic `step_back`.

Accepted `R16a` metrics:

- `pass_rate`: 0.728972
- `expected_action_hit_rate`: 0.925234
- `future_action_hit_rate`: 0.916667
- `forbidden_action_violation_rate`: 0.018692
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.803738
- `demo_priority_pass_rate`: 0.857143

Interpretation:

R16a is accepted: bounded contextual object/unknown action mapping adds
`add_front_fill_light`, `simplify_background`,
`wait_for_background_clearance`, `step_closer` and contextual
`stabilize_camera` future projection only under feature conditions. It turns
`ca_img_007`, `ca_img_014`, `ca_img_076`, `ca_img_084` and `ca_img_093` into
passing cases, and narrows `ca_img_074` / `ca_img_082` to remaining action or
confidence failures without regressing good-frame preservation.

## Current Baseline

Primary measured baseline:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03k/
runtime_claim = real_runtime_still_replay
record_count = 107
```

Previous measured baseline:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06/
runtime_claim = real_runtime_still_replay
record_count = 107
```

Previous accepted confidence baseline:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_after_r09b/
runtime_claim = real_runtime_still_replay
record_count = 107
```

Latest measured baseline:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a/
runtime_claim = real_runtime_still_replay
record_count = 107
```

Previous measured projection for comparison:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03d/
```

`R03k` preserves the `R03i` metrics while making dominant technical quality
issues visible in production live/pause UX. The failed `R03j` experiment is
important evidence: a naive pause technical override reduced pass rate to
`0.271028` by hiding semantic corrective actions on cases like `ca_img_088` and
`ca_img_093`. The corrected `R03k` gate is safe, but still not enough for
product-quality behavior. `R06` improves good-frame preservation and reduces
forbidden correction leakage. `R08` adds bounded hotspot-to-semantic mapping and
raises pass/expected-action metrics, but confidence calibration, mixed frames and
object/multi-subject grounding remain below product target. `R09b` improves
confidence-band agreement for good pause frames with explicit strengths, but it
does not improve missing semantic actions, forbidden violations, mixed-frame
reasoning or object/multi-subject grounding. `R10a` improves confidence honesty
for mixed corrective pause rows. `R11d` improves technical semantic-action
mapping. `R11e` was rejected because a blanket "issues mean no keep" rule
regressed positive confirmations. `R12a` was rejected because a very-dark
underexposure threshold overcorrected good low-key frames. `R13a` adds a
bounded production contextual correction for dark object clusters. `R14a`
extends that policy to weak-subject/object false-keep suppression. `R15a`
adds feature-bounded confidence calibration. `R16a` adds bounded object/unknown
action mapping. `R17a` fixes merged live/pause keep leakage, `R18a` reaches
complete expected/future action recall on the current silver replay, `R19b`
raises pass rate to `0.953271`, `R20a` raises it to `0.990654`, and `R21a`
raises it to `1.000000` with no R20a-to-R21a scored regressions.

## Blockers / Unknowns

- Technical/IQA actions have a first production UX gate, but not a complete confidence-calibrated domain yet.
- Good cinematic frames are no longer overcorrected on the current silver replay, but this is partly a conservative guard and not proof of full scene understanding.
- Confidence is closed on the silver replay; broader live-camera confidence remains unproven outside still-image eval.
- Multi-subject and object-distraction grounding is not strong enough.
- Still-image replay is not the same as live UX stability; it does not prove on-device camera behavior under motion.

## Next

Implement the next production slice from
`docs/cameraanalysis/33-semantic-current-baseline-findings.md`:

- `R21 Object/Multi-Subject Grounding`: handle object distractions and group
  subjects without collapsing the frame to one wrong person/object.
- `R22 Live Stability Recheck`: after the still-image metrics improve, rerun
  live-camera QA because still replay does not prove anti-flicker behavior.

Do not mark the goal complete until the system produces useful semantic tips,
pause explanations and confidence on real dataset cases, not only on handcrafted
fixtures.

## Drift Check

- Still serves original goal: yes.
- Stayed inside compatibility boundary: yes.
- New adapter appeared: yes, real still-image replay now exists and replaces the old proxy baseline for current claims.
- Goal status: dataset/eval objective appears satisfied by current evidence; live-camera product proof remains out of scope for this checkpoint unless explicitly added as a goal.
- Remaining risk: medium-low for the silver still replay, medium for product readiness. The current app is measurable and closed on the 107-image silver still replay after `R21a`, but rejected `R11e`/`R12a` confirm that broad shortcut rules are still the wrong path. It is not yet live-camera product proof.
