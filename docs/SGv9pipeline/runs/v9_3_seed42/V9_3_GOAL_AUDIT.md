# V9.3 Goal Audit

## Objective

Investigate why `dataset_v9_2_event_sft` falls back at runtime, separate real runtime/model failures from false fallback triggers, fix/design scorer/runtime policy and targeted data so the next successor can reach:

| Metric | Target |
|---|---:|
| `case_strict_success_rate` | `>= 0.65` |
| `target_resolution_accuracy` | `>= 0.99` |
| `chronology_phase_accuracy` | `>= 0.985` |
| `action_recall` | `>= 0.99` |
| `runtime_fallback_rate` | `<= 0.25` |

Also record audit, hard-case mining, demo-parity validation and runbook for next train/benchmark.

## Checklist

| Requirement | Status | Evidence |
|---|---|---|
| Identify why V9.2 falls back | done | `from_user_predictions_policy_v93/fallback_audit/v9_2_to_v9_3_policy_audit.md` |
| Separate false fallback from real failures | done | audit shows 108 semantically passing cases rejected by confidence policy, 103 schema invalid from targetless `stand`, 8 real semantic misses |
| Fix scorer/runtime mirror policy | done | `docs/SGv7pipeline/eval/runtime_policy.py`, `experiments/sc_benchmark/generate_predictions_from_endpoint.py` |
| Align Swift fallback target policy | done | `shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift`; V9 native services already excluded `stand` from target-required sets |
| Regression tests for policy fixes | done | `docs/SGv7pipeline/eval/tests/test_eval_harness.py`; command: `python3 -m unittest docs.SGv7pipeline.eval.tests.test_eval_harness docs.SGv7pipeline.eval.tests.test_prediction_export docs.SGv9pipeline.v9.tests.test_v9_datasets_eval docs.SGv9pipeline.v9.tests.test_v9_projection` |
| Policy-corrected frozen replay benchmark | done | `from_user_predictions_policy_v93/benchmark_results_seed42/aggregate/scientific_report.md` |
| Hard-case mining after policy correction | done | `docs/SGv9pipeline/runs/v9_3_seed42/failure_mining/v9_hard_cases.jsonl` |
| Targeted data for remaining failures | done | exact: `exact_targeted_sft/`; synthetic: `augmented_targeted/` |
| Mixed next-train dataset | done | `mixed_event_sft/v9_3_event_sft_mixed_manifest.json`, all rows `5564` |
| Colab upload artifact | done | `colab_upload/v9_3_event_sft_mixed_upload.zip` |
| Colab upload checksum manifest | done | `colab_upload/v9_3_event_sft_mixed_upload_manifest.json`; zip SHA-256 `c57e83c839e3ce84a5963e91a141801ab0506f7c00d3b856e5732699e617b297` |
| Pretrain artifact verifier | done | `docs/SGv9pipeline/v9/14_verify_v9_3_pretrain_artifacts.py`; output `v9_3_pretrain_artifact_verification.json` has `"pass": true` |
| Runbook for next train/benchmark | done | `V9_3_TRAIN_BENCH_RUNBOOK.md` |
| One-command post-train benchmark wrapper | done | `docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py`; includes benchmark, mining, demo-parity and metric acceptance gate |
| Acceptance gate tests | done | `docs/SGv9pipeline/v9/tests/test_v9_post_train_eval.py`; fast suite: `26 tests OK` |
| Demo-parity validation procedure | done | `docs/SGv9pipeline/v9/12_validate_v9_demo_parity.py`; fresh V9.3 evidence: `from_user_predictions/demo_parity_validation/demo_parity_results.json` passes `3/3` canonical non-AR intent checks |
| Successor reaches target metrics | done | `from_user_predictions/v9_3_post_train_eval_summary.json`; all acceptance checks pass on fresh `dataset_v9_3_event_sft_seed42.event_predictions.jsonl` |

## Current Best Evidence

Fresh V9.3 successor predictions on the frozen eval bundle:

| Metric | Value |
|---|---:|
| `case_strict_success_rate` | `0.9962` |
| `target_resolution_accuracy` | `0.9983` |
| `chronology_phase_accuracy` | `0.9962` |
| `action_recall` | `0.9986` |
| `runtime_fallback_rate` | `0.0000` |

Additional gate evidence:

- post-train wrapper summary: `from_user_predictions/v9_3_post_train_eval_summary.json`
- scientific benchmark report: `from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`
- post-benchmark failure mining: `from_user_predictions/post_benchmark_failure_mining/v9_hard_case_manifest.json` (`1` remaining `dialogue_action` case)
- demo-parity: `from_user_predictions/demo_parity_validation/demo_parity_results.json` (`3/3` passed)

## Completion Audit

1. V9.3 was trained externally and fresh predictions were placed at `experiments/sc_benchmark/dataset_v9_3_event_sft_seed42.event_predictions.jsonl`.
2. The post-train command was run: `python3 docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py`.
3. The resulting metrics exceed every successor target.
4. Demo-parity/non-AR intent checks pass on the canonical dialogue/put-down, pick-up/give-to-third and three-actor ordinal scenarios.
5. Fast regression tests pass: `python3 -m unittest docs.SGv7pipeline.eval.tests.test_eval_harness docs.SGv7pipeline.eval.tests.test_prediction_export docs.SGv9pipeline.v9.tests.test_v9_datasets_eval docs.SGv9pipeline.v9.tests.test_v9_projection docs.SGv9pipeline.v9.tests.test_v9_post_train_eval` (`26 tests OK`).
