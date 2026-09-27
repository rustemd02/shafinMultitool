# Adjudication guide v1 — спорные оси pilot-100 (DATA-009, подготовка)

Дата: 2026-09-27 · Задача: **DATA-009** (подготовка; финализация — после пилота и второго прохода)
Связанное: `data-coverage-matrix-v1.md`, `data-quality-analysis-v1.md`, `receipts/2026-09-27-data-008-queue-v2-identity-repair.md`, `receipts/2026-09-23-annotate-fast-tool.md`

## 0. Границы документа

- Это **подготовленный** гайд: примеры ниже взяты из реальных записей пилота
  (`fast_labels.jsonl`/`fast_details.jsonl`, пилотная очередь v2) и не содержат
  выдуманных меток. После завершения пилота список споров дополняется фактическими
  расхождениями второго прохода.
- **`human_gold=true` не поднимается этим документом и не поднимается сырым review.**
  Gold появляется только adjudication'ом (DATA-011); до этого все записи остаются
  `human_gold=false`, `release_admissible=false`.
- Примеры фиксируют СПОР, а не решение: где решение принимает человек (владелец/
  adjudicator), это указано явно.

## 1. Оси споров

| Ось | Что спорится | Где хранится | Кто решает |
|---|---|---|---|
| verdict | `1` good («хороший») / `2` borderline («норм, но улучшить») / `3` ugly_fix («плохой») / `U` unsure / `S` skip | `fast_details.verdict_key` + `verdict` | adjudicator |
| action | одно приоритетное действие из mapped (DATA-002) или отсутствие действия | `fast_details.action`, `action_issue_ids` | adjudicator + sanity-гейт |
| issue-set | какие из 15 heads присутствуют (порядок не важен) | `fast_details.selected_issues`, `v1_issues` | adjudicator |
| target | identity_status / role / rect / movability | `fast_details.target`, `subject_rect` | adjudicator |
| risk / magnitude / before-after | v1-словарь не выражает (экспортируется `not_observed`) | элиcitации DATA-005 | решение владельца (ML-007/DATA-013) |
| contract-gap | наблюдение не выражается 15 heads → `[A]` «контрактом не выразить» | `fast_details.contract_gap`, `gap_note` | решение владельца (контракт v2) |

## 2. Правила разрешения (fail-closed)

1. **Контракт не выражает наблюдение → гэп, а не подгонка.** Не выбирать «ближайший»
   head и не переформулировать замысел автора. Запись `[A]` + заметка, она же едет
   в `--report-gaps` как вход в контракт v2.
2. **Sanity-warning инструмента (issue↔action mismatch) — сигнал к пересмотру, не
   автоперевод.** Менять ответ может только человек.
3. **Повторная запись того же ратера = ревизия решения** (append-only, latest wins),
   это НЕ два голоса и НЕ мера согласия.
4. **Assisted-запись не является независимым ратером** (M3-022) — в согласие не входит.
5. **Независимость проходов**: второй проход — blind, отдельные store/details/session,
   без показа ответов первого. Согласие одного человека с самим собой не измеряется.
6. **Идентичность по контенту.** Споря о записи, ссылаться на `package_record_id` /
   `image_sha256`, не на `record_id` (2026-09-27 показал, что alias может сдвоиться;
  см. repair-ресипт).
7. Одна проблема → одна приоритетная команда (принцип CAM-007); несколько причин не
   порождают нескольких конкурирующих действий в одной записи.

## 3. Короткие примеры спорных случаев (реальные записи пилота)

### Пример 1 — спор action и issue-set (ревизия одного ратера)
`pilot23-composition-01` · `photo__scenetrans_…__0_item__pair_0101__A` · sha `001f0087e9…`

- проход 2026-09-23T15:41:35Z: verdict `3`, action `change_camera_angle`, issues
  `[horizon_distracts, subject_too_close_to_edge, insufficient_look_space]`,
  severity 0.6 / confidence 0.9, rect `[0.1367, 0, 0.8235, 0.895]`;
  sanity-warning: «действие „изменить ракурс“ не относится к: субъект у края…».
- проход 2026-09-24T15:04:00Z: verdict `3`, action `step_back`, issues
  `[subject_too_close_to_edge, horizon_distracts, defocus, motion_blur]`, rect
  `[0.0969, 0, 0.8979, 0.9919]`, `v1_incomplete=true` (defocus/motion_blur —
  технические heads, v1-словарь их не кодирует); sanity-warning: «шаг назад не
  относится к: горизонт / расфокус / смаз…».

Спор: два разных действия и два разных issue-set на один кадр. Как разрешать:
(а) выбрать ОДНО приоритетное действие на группу причин (правило CAM-007);
(б) выяснить, действительно ли присутствуют технические heads (расширение v1 —
решение владельца, пока запись остаётся невыразимой для release-экспорта);
(в) rect субъекта разошёлся — отдельная target-элиситация.
**Статус спора: открыт** (решение — adjudication, DATA-011).

### Пример 2 — contract-gap «симметрия» vs verdict borderline
`pilot23-composition-03` · `photo__commons_…__100002749` · sha `f54368b99a…`

verdict_key `2` → запись сохранена как `contract_gap` с заметкой «хочется чуть правее
камеру сделать чтобы была симметрия, скорее всего человек хотел сделать симметричный
кадр»; issues пусты. Спор: «норм, но улучшить» (что требует выразимого action) vs
наблюдение вне контракта (главы «симметрия/баланс» в 15 heads нет, в CC-C05 есть).
Как разрешать: оставить гэп; не подгонять под `level_horizon`/`change_camera_angle`.
Кандидат №1 в контракт v2 — **решение владельца**.

### Пример 3 — субъективная эстетика без выразимого действия
`pilot23-composition-06` · `photo__commons_…__100877095` · sha `37dd778efd…`

verdict_key `2` → `contract_gap`, заметка: «с одной стороны прикольно да, отражение,
задумка ясна, но выглядит не оч красиво. хз даже как сделать красивее».
Спор: эстетическая оценка не выражается действием/issue; возможен intentional-style.
Как разрешать: гэп + вопрос про намеренность стиля (intentional_style-элиситация);
никакого выдуманного action.

### Пример 4 — target-ось на good-кадре
`pilot23-composition-07` · `photo__commons_…__101220534` · sha `c9b2b39a9d…`

Два прохода (2026-09-24, dwell 13.7 c и 38.9 c): оба verdict `1` good /
`keep_current_setup`; target: `identity_status=unknown`, `role=context`, `rect=null`.
Спор: при good-вердикте цель не выбирается (контекст) — но для обучения это маска,
а не «цель = 0» (правило ML-003: отсутствие label ≠ zero target). Внимание: это тот
самый кадр, который показывался дважды из-за дубля record_id (ремонт 2026-09-27);
спорить по контент-identity (sha выше), не по alias.

### Пример 5 — оси risk/magnitude/movable в пилоте не покрыты
Все 9 текущих записей: `movability_key=null`, `movability_status=not_applicable`;
risk/before_after экспортируются `not_observed` (элиcitации — ML-007/DATA-013).
Спорные movable/wrong-direction случаи пилотом не представлены (coverage gap,
DATA-015/shot-list) — для их adjudication нужны отдельные кадры, не выдуманные
ответы на существующие.

## 4. Calibration subset и второй проход

Манифест: `local-data/SETOS/annotation/pilot-20260923-strata-v1/calibration-subset-v1.json`
(23 записи: по 2 детерминированных кадра на каждую из 10 групп §4 + 3 именованных
спорных — composition-03/06/07; composition-01 уже вошёл как групповой).
Подбор контент-связанный (`package_record_id`+`image_sha256`) и байт-детерминированный
(builder: `tools/camera_annotation/build_calibration_subset.py`).

Команда второго blind-прохода (отдельные store/details/session, свой annotator-id):

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool
SUBSET=/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/annotation/pilot-20260923-strata-v1
python3 -c "import json; m=json.load(open('$SUBSET/calibration-subset-v1.json')); \
print('\n'.join(r['record_id'] for r in m['records']))" > "$SUBSET/calibration-subset-v1.ids"
python3 tools/camera_annotation/annotate_fast.py \
  --queue "$SUBSET/queue-v2-diverse.jsonl" \
  --only-ids "$SUBSET/calibration-subset-v1.ids" \
  --store "$SUBSET/fast_labels.r2.jsonl" --details "$SUBSET/fast_details.r2.jsonl" \
  --session "$SUBSET/session.r2.json" --annotator-id "r2"
```

Отчёт согласия (механика, не качество и не gold):

```bash
python3 tools/camera_annotation/annotate_fast.py \
  --queue "$SUBSET/queue-v2-diverse.jsonl" \
  --report-agreement "$SUBSET/fast_labels.r2.jsonl"
```

Правила отчёта: assisted исключаются; повторная запись одного ратера = ревизия
(берётся последняя); считаются verdict (точное совпадение + Cohen kappa), action
(по кадрам, где хоть один выбрал действие), issue-set (точное совпадение + Jaccard);
расхождения перечисляются построчно.

## 5. Форма протокола adjudication (заполняет человек)

| # | record_id | package_record_id | ось спора | решение adjudicator | обоснование | согласны оба ратера? |
|---|---|---|---|---|---|---|
| 1 | pilot23-composition-01 | photo__scenetrans_…_0_item__pair_0101__A | action+issues | (заполнить) | (заполнить) | (заполнить) |
| 2 | pilot23-composition-03 | photo__commons_…_100002749 | contract-gap | (заполнить) | | |
| 3 | pilot23-composition-06 | photo__commons_…_100877095 | contract-gap | (заполнить) | | |
| 4 | pilot23-composition-07 | photo__commons_…_101220534 | target на good | (заполнить) | | |

Статус после заполнения: human_gold поднимается только для строк с решением
adjudicator и полными элиcitациями (DATA-011); остальное остаётся research-only.
