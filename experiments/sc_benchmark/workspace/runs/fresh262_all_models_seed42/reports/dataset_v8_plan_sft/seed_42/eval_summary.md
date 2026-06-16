# Eval Summary

## Run Metadata
- bundle_id: sg_fresh262_eval_bundle_v2
- checkpoint_id: dataset_v8_plan_sft_seed42
- contract_version: sg_v7_contract_v1
- decoding_config: 6349599b952d29a3c512f864c7c91421973bf7106272da23b80665cfd8fd2e57
- grammar_snapshot: db246071fe0fb256d283714e88d93f61d1b724619bc22b320372369d72095563
- normalization_snapshot: b43833ae7cc773510d24dfaa0e924fd6ed0d0c1bce698e12f4cb7db6215d41b4
- runtime_policy_snapshot: a27d06e7a30d1165f03f35023230d0740fdfaa5b6d2de0dbbcd1c22284e5a64b

## Set Metrics
| Set | json_valid_rate | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | runtime_fallback_rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| synthetic_heldout | 1.0000 | 1.0000 | 1.0000 | 0.8900 | 0.8440 | 0.0000 |
| hard_heldout | 1.0000 | 1.0000 | 1.0000 | 0.9829 | 0.9663 | 0.0000 |
| real_runtime | 1.0000 | 0.9897 | 1.0000 | 0.9915 | 0.9844 | 0.0156 |

## Critical Buckets
| Bucket | cases | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | chronology_phase_accuracy | runtime_fallback_rate | delta_vs_baseline |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinal_cases | 130 | 0.9949 | 1.0000 | 0.9923 | 0.0077 | 0.000 |
| marked_object_morphology | 140 | 0.9957 | 1.0000 | 0.9929 | 0.0071 | 0.000 |
| same_type_markers | 90 | 0.9944 | 1.0000 | 0.9889 | 0.0111 | 0.000 |
| unsupported_action_cases | 15 | 1.0000 | 1.0000 | 1.0000 | 0.0000 | 0.000 |
| three_beat_cases | 38 | 1.0000 | 1.0000 | 0.9211 | 0.0000 | 0.000 |
| exact_marker_identity_cases | 140 | 0.9957 | 1.0000 | 0.9929 | 0.0071 | 0.000 |
| reviewed_merge_cases | 0 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.000 |

## Release Gate
- status: pass_with_watchlist
- blockers: none
- improvements: 
- recommended_action: promote_with_watchlist

## Top Failure Clusters
- hard_heldout: hard_heldout::pass::exact_marker_identity_cases (49), hard_heldout::pass::three_beat_cases (20), hard_heldout::pass::ordinal_cases (17)
- real_runtime: real_runtime::pass::exact_marker_identity_cases (55), real_runtime::pass::ordinal_cases (8), real_runtime::exact_marker_id_fail::exact_marker_identity_cases (1)
