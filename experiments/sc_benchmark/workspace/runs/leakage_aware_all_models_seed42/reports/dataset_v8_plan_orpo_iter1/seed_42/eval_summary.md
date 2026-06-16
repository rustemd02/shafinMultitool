# Eval Summary

## Run Metadata
- bundle_id: sgv7_eval_bundle_v1__leakage_aware_all_models
- checkpoint_id: dataset_v8_plan_orpo_iter1_seed42
- contract_version: sg_v7_contract_v1
- decoding_config: f9779b62a87f9d0c163c51a41bf61e8c23e2223699acdbbf5f7ebba2bbc5d246
- grammar_snapshot: a1f2fc00a384faa69e8177cf9077b50b7e0086cba8f35abbf6fde9ad47af4945
- normalization_snapshot: 678bdc22303cae685242a0356ccfddcefb3207d99d05909f80199a6670cf9f71
- runtime_policy_snapshot: 75374ebdf4fa5bf39a9a21543ad6e96fa4d53318d07e25c6ce68411311c19335

## Set Metrics
| Set | json_valid_rate | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | runtime_fallback_rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| synthetic_heldout | 0.9500 | 0.0000 | 0.6702 | 0.4841 | 0.1333 | 0.2167 |
| hard_heldout | 0.9206 | 0.0000 | 0.8889 | 0.3099 | 0.0476 | 0.8413 |
| real_runtime | 1.0000 | 1.0000 | 1.0000 | 0.6364 | 0.5294 | 0.0000 |

## Critical Buckets
| Bucket | cases | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | chronology_phase_accuracy | runtime_fallback_rate | delta_vs_baseline |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinal_cases | 72 | 1.0000 | 0.9559 | 0.1667 | 0.6806 | 0.000 |
| marked_object_morphology | 12 | 1.0000 | 1.0000 | 0.5000 | 0.0000 | 0.000 |
| same_type_markers | 12 | 1.0000 | 1.0000 | 0.5000 | 0.0000 | 0.000 |
| unsupported_action_cases | 0 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.000 |
| three_beat_cases | 8 | 0.0000 | 0.5000 | 0.0000 | 0.5000 | 0.000 |
| exact_marker_identity_cases | 12 | 1.0000 | 1.0000 | 0.5000 | 0.0000 | 0.000 |
| reviewed_merge_cases | 0 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.000 |

## Release Gate
- status: fail
- blockers: gate1:floor_not_met:action_recall, gate1:floor_not_met:beat_count_accuracy, gate1:floor_not_met:chronology_phase_accuracy, gate1:floor_not_met:json_valid_rate, gate1:floor_not_met:ordinal_actor_binding_accuracy, gate1:floor_not_met:runtime_fallback_rate, gate1:floor_not_met:target_resolution_accuracy
- improvements: 
- recommended_action: do_not_promote

## Top Failure Clusters
- hard_heldout: hard_heldout::target_resolution_fail::ordinal_cases (48), hard_heldout::json_invalid::three_beat_cases (4), hard_heldout::target_resolution_fail::three_beat_cases (4)
- real_runtime: real_runtime::beat_count_fail::exact_marker_identity_cases (6), real_runtime::target_resolution_fail::exact_marker_identity_cases (6), real_runtime::pass::ordinal_cases (3)
