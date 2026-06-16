# Eval Summary

## Run Metadata
- bundle_id: sg_fresh262_eval_bundle_v2
- checkpoint_id: dataset_v7_seed42
- contract_version: sg_v7_contract_v1
- decoding_config: 6349599b952d29a3c512f864c7c91421973bf7106272da23b80665cfd8fd2e57
- grammar_snapshot: db246071fe0fb256d283714e88d93f61d1b724619bc22b320372369d72095563
- normalization_snapshot: b43833ae7cc773510d24dfaa0e924fd6ed0d0c1bce698e12f4cb7db6215d41b4
- runtime_policy_snapshot: a27d06e7a30d1165f03f35023230d0740fdfaa5b6d2de0dbbcd1c22284e5a64b

## Set Metrics
| Set | json_valid_rate | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | runtime_fallback_rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| synthetic_heldout | 1.0000 | 1.0000 | 1.0000 | 0.8188 | 0.6789 | 0.0642 |
| hard_heldout | 0.7416 | 1.0000 | 0.6835 | 0.3886 | 0.5730 | 0.2809 |
| real_runtime | 0.9844 | 0.9897 | 0.9779 | 0.8632 | 0.5938 | 0.0312 |

## Critical Buckets
| Bucket | cases | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | chronology_phase_accuracy | runtime_fallback_rate | delta_vs_baseline |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinal_cases | 130 | 0.9949 | 0.9895 | 0.6846 | 0.0308 | 0.000 |
| marked_object_morphology | 140 | 0.9957 | 0.9929 | 0.8214 | 0.0214 | 0.000 |
| same_type_markers | 90 | 1.0000 | 1.0000 | 0.9000 | 0.0000 | 0.000 |
| unsupported_action_cases | 15 | 0.9333 | 0.9333 | 0.0000 | 0.1333 | 0.000 |
| three_beat_cases | 38 | 0.9333 | 0.2828 | 0.0000 | 0.6579 | 0.000 |
| exact_marker_identity_cases | 140 | 0.9957 | 0.9929 | 0.8214 | 0.0214 | 0.000 |
| reviewed_merge_cases | 0 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.000 |

## Release Gate
- status: fail
- blockers: gate1:floor_not_met:action_recall, gate1:floor_not_met:beat_count_accuracy, gate1:floor_not_met:chronology_phase_accuracy, gate1:floor_not_met:described_action_precision, gate1:floor_not_met:json_valid_rate, gate1:floor_not_met:ordinal_actor_binding_accuracy, gate1:floor_not_met:target_resolution_accuracy
- improvements: 
- recommended_action: do_not_promote

## Top Failure Clusters
- hard_heldout: hard_heldout::pass::exact_marker_identity_cases (42), hard_heldout::json_invalid::three_beat_cases (23), hard_heldout::target_resolution_fail::ordinal_cases (11)
- real_runtime: real_runtime::pass::exact_marker_identity_cases (30), real_runtime::chronology_phase_fail::exact_marker_identity_cases (13), real_runtime::beat_count_fail::exact_marker_identity_cases (6)
