# DATA-009 — подготовка adjudication guide, calibration subset и отчёта согласия

Дата: **2026-09-27** · HEAD: `ca986a9` · Ветка: `store`
Задача: **DATA-009** (bounded prep; строка → `PARTIAL`: финализация — после пилота и
второго прохода; оба за владельцем — DATA-008/010/011)

## 1. Что сделано

1. **`docs/implementation/human-eval/adjudication-guide-v1.md`** — оси споров
   (verdict/action/issue-set/target/risk-magnitude/contract-gap), 7 fail-closed правил
   разрешения и **4 коротких примера спорных случаев из реальных записей пилота** +
   1 покрытый gap (risk/movable не представлены): composition-01 (ревизия с другим
   action/issue-set + два sanity-warning), composition-03 (гэп «симметрия» vs
   borderline), composition-06 (субъективная эстетика), composition-07 (target-ось на
   good-кадре; тот самый кадр из ремонта идентичности 2026-09-27). Ничего не выдумано:
   все поля/хеши/времена сверены с `fast_labels.jsonl`/`fast_details.jsonl`.
2. **Calibration subset** — `local-data/…/calibration-subset-v1.json` (23 записи:
   2 детерминированных кадра на каждую из 10 групп §4 + 3 именованных спорных;
   composition-01 вошёл как групповой) + `calibration-subset-v1.ids` (23 id) для
   `--only-ids`. Манифест контент-связанный (package_record_id + image_sha256),
   поэтому ремонт record_id его не ломает; human-метки не создаются.
3. **`tools/camera_annotation/build_calibration_subset.py`** — детерминированный
   builder (байт-детерминизм доказан тестом), отказ на отсутствующем `--extra` id.
4. **`annotate_fast.py`: `--report-agreement SECOND_STORE`** — механика согласия двух
   независимых blind-проходов: assisted исключаются (M3-022), повтор одной записи =
   ревизия (latest wins), verdict (exact + Cohen kappa), action, issue-set (exact +
   Jaccard), построчный список расхождений. Заголовок честно говорит: механика — не
   качество и не human-gold.
5. **`annotate_fast.py`: `--only-ids FILE`** — обход только выбранных записей
   (нужен, чтобы второй reviewer прошёл subset, а не всю очередь); отсутствующий id —
   отказ, не тихий пропуск.

## 2. Проверки

| Check | Результат |
|---|---|
| `pytest tools/camera_annotation/tests/` | **88 passed / 0 failed** (новых 8: 4 builder, 3 agreement/CLI, 1 only-ids) |
| Builder на реальной очереди | 23 записи (groups: composition 5 — 2 групповых + 3 именованных; остальные по 2), queue pin `dd47f199…` |
| Байт-детерминизм builder | тест `test_cli_writes_byte_identical_manifest` |
| `filter_only_ids` по реальному subset | 23 id → 23 строки очереди, missing=0 |
| Контент-связность subset при смене record_id | тест `test_subset_survives_record_id_rename` |
| Отчёт согласия (CLI) | тест `test_report_agreement_cli_reads_second_store` (1 расхождение вердикта найдено и перечислено) |

## 3. Честные границы

- **Второй reviewer — за владельцем** (DATA-010/011 `BLOCKED_OWNER`): сама проверка
  «второй reviewer одинаково размечает calibration subset» не выполнена и не могла
  быть выполнена без людей. Готов весь инструментированный путь (subset → blind-проход
  → отчёт → протокол adjudication).
- Финализация примеров гайда — после полного пилота: расхождения второго прохода
  дополнят §3, спорные вердикты решит adjudicator.
- risk/magnitude/movable/temporal-оси в текущем пилоте фактически не представлены
  (coverage gap DATA-004/015): гайд это фиксирует, ответы не выдумываются.
- Отчёт считает механику согласия; интерпретация (stale oracle vs реальный спор) —
  задача adjudication, не скрипта.

## 4. Что дальше (человек/владелец)

1. Завершить pilot-100 (инструмент продолжает сессию; пропущенный кадр
   `pilot23-composition-11` — последним в обходе).
2. Назначить второго reviewer: blind-проход по `calibration-subset-v1.ids`.
3. Прогнать `--report-agreement`, заполнить протокол §5 гайда, решить споры
   (DATA-009 финализация → DATA-011 adjudication).
