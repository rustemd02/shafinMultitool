# Fresh 262 strict refresh audit

## Main result

- Original `eval_bundle_v1`: retained `0` / `262` under strict matching.
- Fresh `eval_bundle_v2_fresh262_all_models`: retained `262` / `262` under strict matching.

## Original bundle overlap

- excluded: `262`
- by set: `{"synthetic_heldout": 109, "hard_heldout": 89, "real_runtime": 64}`
- reasons: `{"train_sample_id": 262, "train_source": 95, "train_normalized_source_hash": 89, "train_graph_family": 262}`

## Fresh bundle composition

- synthetic_heldout: `109`
- hard_heldout: `89`
- real_runtime (synthetic proxy): `64`

## Important note

Новый bundle готов для честного model-vs-model rerun, но старые prediction-файлы от `eval_bundle_v1` к нему неприменимы.
