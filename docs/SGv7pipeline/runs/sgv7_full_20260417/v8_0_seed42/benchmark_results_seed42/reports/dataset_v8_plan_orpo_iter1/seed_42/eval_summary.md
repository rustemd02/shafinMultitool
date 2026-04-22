# Eval Summary

## Run Metadata
- bundle_id: sgv7_eval_bundle_v1
- checkpoint_id: dataset_v8_plan_orpo_iter1_seed42
- contract_version: sg_v7_contract_v1
- decoding_config: f9779b62a87f9d0c163c51a41bf61e8c23e2223699acdbbf5f7ebba2bbc5d246
- grammar_snapshot: a1f2fc00a384faa69e8177cf9077b50b7e0086cba8f35abbf6fde9ad47af4945
- normalization_snapshot: 678bdc22303cae685242a0356ccfddcefb3207d99d05909f80199a6670cf9f71
- runtime_policy_snapshot: 75374ebdf4fa5bf39a9a21543ad6e96fa4d53318d07e25c6ce68411311c19335

## Set Metrics
| Set | json_valid_rate | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | runtime_fallback_rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| synthetic_heldout | 0.8532 | 0.0000 | 0.6433 | 0.4803 | 0.0917 | 1.0000 |
| hard_heldout | 0.2809 | 0.0000 | 0.2697 | 0.1100 | 0.0449 | 0.8539 |
| real_runtime | 0.9688 | 0.9881 | 0.9348 | 0.7115 | 0.3594 | 0.0312 |

## Critical Buckets
| Bucket | cases | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | chronology_phase_accuracy | runtime_fallback_rate | delta_vs_baseline |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinal_cases | 137 | 0.9881 | 0.4790 | 0.1971 | 0.5255 | 0.000 |
| marked_object_morphology | 54 | 0.9881 | 0.9444 | 0.3704 | 0.0185 | 0.000 |
| same_type_markers | 30 | 1.0000 | 0.9667 | 0.4667 | 0.0000 | 0.000 |
| unsupported_action_cases | 0 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.000 |
| three_beat_cases | 40 | 0.9583 | 0.7708 | 0.1500 | 0.1750 | 0.000 |
| exact_marker_identity_cases | 54 | 0.9881 | 0.9444 | 0.3704 | 0.0185 | 0.000 |
| reviewed_merge_cases | 0 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.000 |

## Release Gate
- status: fail
- blockers: gate1:floor_not_met:action_recall, gate1:floor_not_met:beat_count_accuracy, gate1:floor_not_met:chronology_phase_accuracy, gate1:floor_not_met:json_valid_rate, gate1:floor_not_met:ordinal_actor_binding_accuracy, gate1:floor_not_met:runtime_fallback_rate, gate1:floor_not_met:target_resolution_accuracy
- improvements: 
- recommended_action: do_not_promote

## Top Failure Clusters
- hard_heldout: hard_heldout::json_invalid::ordinal_cases (59), hard_heldout::schema_invalid::ordinal_cases (13), hard_heldout::target_resolution_fail::three_beat_cases (6)
- real_runtime: real_runtime::schema_invalid::exact_marker_identity_cases (30), real_runtime::chronology_phase_fail::exact_marker_identity_cases (14), real_runtime::pass::exact_marker_identity_cases (6)
