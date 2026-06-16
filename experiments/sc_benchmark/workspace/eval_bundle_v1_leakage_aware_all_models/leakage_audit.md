# Leakage-aware eval bundle audit

## Setup
- source bundle: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1`
- output bundle: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1_leakage_aware_all_models`
- total eval cases: 262
- excluded eval cases: 122
- retained eval cases: 140

## Matching policy

A case is excluded if any compared training corpus links to it by explicit origin case id, exact `source_text`, or shared `graph_family_key`.

## Excluded / retained by set

| Eval set | Total | Excluded | Retained |
| --- | ---: | ---: | ---: |
| hard_heldout | 89 | 26 | 63 |
| real_runtime | 64 | 47 | 17 |
| synthetic_heldout | 109 | 49 | 60 |

## Corpus overlap summary

| Corpus | Rows | Matched eval cases | Direct origin hits | Exact source hits | Family hits |
| --- | ---: | ---: | ---: | ---: | ---: |
| v7_sft_train | 2090 | 42 | 0 | 5 | 37 |
| v7_pref_train | 1088 | 0 | 0 | 0 | 0 |
| v8_plan_sft_all | 5000 | 8 | 0 | 8 | 0 |
| v8_plan_pref_all | 52 | 52 | 0 | 52 | 52 |
| v9_0_event_sft_all | 5000 | 8 | 0 | 8 | 0 |
| v9_2_mixed_all | 5286 | 42 | 34 | 42 | 0 |
| v9_3_mixed_all | 5564 | 42 | 42 | 50 | 0 |

## Notes

- `v7_sft_train`: Shared SFT base for direct SceneScript v7/v7_orpo checkpoints.
- `v7_pref_train`: Checked for overlap because v7_orpo checkpoints depend on this corpus.
- `v8_plan_sft_all`: Core SFT data for v8 plan checkpoints.
- `v8_plan_pref_all`: Preference data used by v8 ORPO training.
- `v9_0_event_sft_all`: Initial slot/event training data for v9.0 event_sft.
- `v9_2_mixed_all`: Contains targeted hard cases and explicit origin links back to the eval bundle.
- `v9_3_mixed_all`: Fresh successor dataset; also checked for direct and family-level overlap.
