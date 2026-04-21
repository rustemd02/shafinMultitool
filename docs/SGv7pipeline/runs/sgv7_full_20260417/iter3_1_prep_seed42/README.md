# Iter3.1 Prep Seed42

Этот каталог содержит локально собранные артефакты после Colab prep-export из:
- [colab_prep_export_seed42](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/colab_prep_export_seed42)

## Что было сделано

1. Прогнан benchmark prep для:
- `dataset_v7`
- `dataset_v7_orpo_iter1`
- `dataset_v7_orpo_iter2`

2. Собран honest `iter3.1` corpus build attempt на fresh dual-slice predictions.

## Структура каталога

- `colab_prep_export_seed42/`
  Сырые dual-slice predictions и manifest, привезённые из Colab.
- `benchmark_results_seed42/`
  Полный локально пересобранный benchmark prep run.
- `iter3_corpus_seed42/`
  Honest transfer-first corpus attempt и gate report.

## Ключевой результат

`iter3.1` **не готов к train** на этом входе.

Corpus build честно упал по transfer quality gate:
- `gold_chosen_share_overall = 0.948 > 0.550`
- `model_chosen_share_overall = 0.052 < 0.250`

Это значит, что текущие `model_only` predictions всё ещё слишком редко проходят canonical/family integrity gates, и builder вынужден почти полностью опираться на `gold_target_json`.

## Benchmark summary

По `model_only` slice:
- `dataset_v7`
  - `json_valid_rate = 0.9809`
  - `target_resolution_accuracy = 0.0564`
  - `chronology_phase_accuracy = 0.0420`
  - `case_strict_success_rate = 0.0191`
- `dataset_v7_orpo_iter1`
  - `json_valid_rate = 0.9656`
  - `target_resolution_accuracy = 0.0940`
  - `chronology_phase_accuracy = 0.0725`
  - `case_strict_success_rate = 0.0267`
- `dataset_v7_orpo_iter2`
  - `json_valid_rate = 0.9504`
  - `target_resolution_accuracy = 0.1128`
  - `chronology_phase_accuracy = 0.0840`
  - `case_strict_success_rate = 0.0344`

Вывод:
- `iter2` снова даёт semantic lift
- но structural/raw integrity всё ещё деградирует слишком сильно для honest transfer-first iter3.1

## Где смотреть артефакты

- benchmark aggregate:
  [runs_scored.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/runs_scored.csv)
- pairwise:
  [pairwise_compare.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv)
- slice summary:
  [model_slice_summary.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv)
- scientific report:
  [scientific_report.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/scientific_report.md)
- corpus gate:
  [iter3_manifest.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/iter3_corpus_seed42/iter3_manifest.json)
- manual review sample pack:
  [iter3_manual_review_samples.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/iter3_corpus_seed42/iter3_manual_review_samples.json)

## Практический next step

Не идти в `delta-SFT -> ORPO iter3` из этого corpus.

Следующий честный шаг:
- либо улучшать raw `model_only` generation contract / prompt / decoding и снова делать prep-export,
- либо переходить к проектированию `v8`, если хотим менять сам supervision contract, а не только добирать curated corpus.
