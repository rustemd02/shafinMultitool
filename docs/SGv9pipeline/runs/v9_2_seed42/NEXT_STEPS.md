# V9.2 Mixed Dataset Next Steps

Готовый mixed dataset для следующего дообучения:

- `docs/SGv9pipeline/runs/v9_2_seed42/mixed_event_sft/v9_2_event_sft_mixed_all.jsonl`
- `docs/SGv9pipeline/runs/v9_2_seed42/mixed_event_sft/v9_2_event_sft_mixed_train.jsonl`
- `docs/SGv9pipeline/runs/v9_2_seed42/mixed_event_sft/v9_2_event_sft_mixed_val.jsonl`

Ключевые counts:

- `all=5286`
- `train=4744`
- `val=542`
- `targeted rows in mixed=286`

Что подставлять в следующий train:

- в текущем V9 Colab/runbook использовать `mixed_event_sft` как новый `EVENT_DIR`
- train file: `v9_2_event_sft_mixed_train.jsonl`
- val file: `v9_2_event_sft_mixed_val.jsonl`
- all file: `v9_2_event_sft_mixed_all.jsonl`

Что benchmarking сравнивает после обучения:

- новый checkpoint против `dataset_v9_event_sft`
- затем против `dataset_v8_plan_orpo_iter1`
- отдельно прогнать `demo_parity_slice`

Связанные артефакты:

- exact benchmark failures: `docs/SGv9pipeline/runs/v9_2_seed42/targeted_sft/v9_2_hard_cases.jsonl`
- gold-derived targeted SFT: `docs/SGv9pipeline/runs/v9_2_seed42/targeted_sft/v9_2_event_sft_targeted_all.jsonl`
- synthetic targeted SFT: `docs/SGv9pipeline/runs/v9_2_seed42/augmented_targeted/v9_2_augmented_event_sft_all.jsonl`
- mixed manifest: `docs/SGv9pipeline/runs/v9_2_seed42/mixed_event_sft/v9_2_event_sft_mixed_manifest.json`
