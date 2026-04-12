# 10. Runtime Feedback Loop

## Цель

Превратить реальные ошибки приложения в непрерывный источник улучшения датасета.

## Что нужно логировать

Для каждого runtime parse:
- raw prompt
- marked objects
- raw LLM output
- repaired LLM output
- accept / merge / reject decision
- reject reason
- final script used
- final script source
- correction tier
- contract version

## Failure taxonomy

Каждый runtime failure должен попадать в один или несколько buckets:
- `lost_marked_object`
- `beat_collapse`
- `action_missing`
- `ordinal_lost`
- `unsupported_action_lost`
- `dangling_target`
- `same_type_marker_conflict`

## Failure ingestion

Нужен автоматический экспорт в JSONL:
- `runtime_failures.jsonl`

Поля:
- `failure_id`
- `timestamp`
- `source`
- `marked_objects`
- `raw_llm_output`
- `repaired_llm_output`
- `diagnostics`
- `final_decision`
- `final_script_source`
- `reject_reason`
- `corrected_target_json`
- `correction_tier`
- `review_status`
- `train_eligibility`
- `contract_version`

## Corrected Target Provenance

`corrected_target_json` без provenance нельзя считать gold.

Минимально обязательные поля:
- `correction_tier`
- `gold_source`
- `final_script_source`
- `review_status`

Разрешённые tiers:
- `tier_a_human_gold`
- `tier_b_deterministic_canonical`
- `tier_c_reviewed_merge`
- `tier_d_auto_repair_only`

## Cluster-and-patch workflow

1. Кластеризуем похожие failures.
2. Для каждого кластера определяем pattern gap.
3. Генерируем synthetic near-neighbors.
4. Добавляем их в hard bucket следующей версии.

## Active learning rule

Каждый новый релиз модели должен:
- уменьшать частоту top-3 failure clusters
- не создавать новые крупные failure clusters

## Что вынести отдельному агенту

- runtime logging schema
- failure clustering strategy
- synthetic patch generation logic
- feedback loop automation
