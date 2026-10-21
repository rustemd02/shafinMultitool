# DATA-005 — Annotation tool → camera-release-label-v1 (bounded slice)

Дата: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`.

## Изменения

- Добавлен `tools/camera_annotation/release_label_adapter.py` — конвертация допущенного v1 review-record (`annotation_labels.build_label`) в структурированный `camera-release-label-v1` + export-конверт, хранящий raw opinion **рядом** с label (схема запрещает дополнительные свойства внутри label).
- Существующий путь разметки не изменён: `annotate_camera.py`, `annotate_gui.py`, `annotation_labels.py`, `review_pipeline.py`, очереди и журналы не тронуты. Natural-language UX сохранён: текст notes переносится в конверт дословно (`raw_opinion.text`).
- Enum'ы/консты берутся из `ml/camera_coach/contracts/camera_release_label_v1.schema.json` при импорте; при загрузке проверяется, что 8 issue-словарей v1 ⊂ 15 release-heads.

## Fail-closed правила (без фабрикации)

1. Present-issue требует явно заданных severity+confidence+evidence_refs (region опционален) — v1-запись сама их не несёт, export отказывает.
2. `needs_fix` требует ровно одно corrective-действие (назвать явно, если в записи несколько).
3. Frame identity перепроверяется хешем файла при экспорте; расхождение → отказ.
4. Abstain требует явных `abstention_reasons` (нет молчаливого дефолта); abstain ⇒ verdict=null, action=null.
5. `target` требует все факты (entity_ref/identity_status/kind/role/movability) — легального дефолта в контракте нет.
6. `review_ids` обязан быть непустым (требование provenance-схемы).
7. `model_proposal` origin отклоняется: инструмент экспортирует только human записи; контент proposal не копируется — путешествует только `proposal_id`.
8. `release_admissible=true` требует human_gold + adjudication + adjudicator_id.

## Round-trip evidence (raw → proposal → human edit → export → validate)

Фикстура в /tmp (создана и удалена в рамках проверки; файл-«jpeg» 24 байта, sha256 `7065ac8d43c3…`):

```
stage=raw     image_sha256=7065ac8d43c3 opinion="лампа справа отвлекает, подвину её левее"
stage=export  EXPORTED envelope record_id=cam-release-review-pilot-0042
stage=validate: RELEASE LABEL VALID          (validate_camera_release_label.validate_record:
                                              Draft202012 schema + semantic cross-record checks)
ROUNDTRIP OK: raw -> proposal(id only) -> human edit -> export -> contract-valid; identity preserved
```

Проверено: `provenance.proposal_id=teacher-prop-0042` присутствует; контент подсказки (`teacher-vision`) в label отсутствует; `source.content_sha256` == hash файла; raw opinion дословно в конверте.

## Негативные контроли (все отклонены)

| Контроль | Результат |
|---|---|
| present-issue без severity/confidence/evidence | `CONVERSION REJECTED` |
| два corrective-действия без явного выбора | `CONVERSION REJECTED` |
| расхождение hash файла и записи | `CONVERSION REJECTED` |
| unsure/abstain при improvement_needed=true | `CONVERSION REJECTED` |
| target без movability | `CONVERSION REJECTED` |
| пустой review_ids | `CONVERSION REJECTED` |
| ambiguous target + move_object (run 2, schema-уровень) | `schema target.identity_status: 'resolved' was expected` |
| good + неисправляющее действие (контракт good⇒keep-only) | покрыт DATA-001 validator fixtures |

## Честные ограничения (статус строки: PARTIAL)

- `annotate_gui` ещё не собирает новые элиcitации (severity/confidence/evidence/target/movability) — на этом слайсе они подаются через conversion config; встройка в GUI — вместе с DATA-008 pilot UX.
- Verdict `mixed` из v1-записи недостижим (v1 задаёт только improvement_needed true/false/unsure) — задокументировано, без молчаливого маппинга.
- `risk` по умолчанию `not_observed` (в v1-потоке нет risk-элиcitации); before_after в этом слайсе экспортируется только как `not_observed` (temporal-данные — DATA-013).
