# ML-004 — refresh data pin и починка human-gold gate Colab-бандла

Дата: **2026-09-27** · HEAD: `f148c43c` · Ветка: `store`
Задача: **ML-004** (bounded prep; строка остаётся `PARTIAL`: загрузка на Drive, прогон
на реальном Colab runtime и наполнение human-gold — за владельцем/человеком)

## 1. Найдено и исправлено (три факта, не гипотезы)

1. **Устаревший queue pin.** Слот `human_labels_dir_slot` в `data_manifest.jsonl`
   закреплял `queue.jsonl` (v1, sha `cbb55e63…`) — но пилот размечается
   `queue-v2-diverse.jsonl` (после ремонта идентичности 2026-09-27 sha `dd47f199…`).
   Pin обновлён на рабочую очередь с lineage-полем (repair-манифест, переименование
   `pilot23-composition-07` → `pilot23-composition-11`), исторический v1-pin сохранён
   как `prep_queue_pin_20260923`; добавлены пути raw-хранилищ (`fast_labels/fast_details`)
   и пометка, что envelope'ы приходят из `annotate_fast --export-out` после adjudication.
2. **Реальный дефект гейта (format mismatch):** `check_environment.py` считал
   `row["human_gold"]` на верхнем уровне строки, а экспорт аннотаций
   (`release_label_adapter.build_export_envelope`) кладёт gold в
   `release_label.provenance.human_gold`. Любой корректный adjudicated-конверт
   был бы навсегда отвергнут («N of N rows are not human_gold=true»). Теперь
   `human_gold_of()` envelope-aware и дополнительно требует
   `review_status=adjudicated` + `adjudicator_id` (DATA-011: raw review не gold);
   неизвестные формы строк не считаются gold.
3. **Реальный latent-дефект гейта (обрыв при первых метках):** валидация звала
   `validator.validate_release_label(...)`, которого в модуле
   `validate_camera_release_label` **нет** (реальный API —
   `validate_record(validator, record)`, тот же, что использует
   `release_label_adapter`). Вызов падал бы AttributeError в момент появления
   первых human-gold строк — то есть гейт был бы смертельно сломан именно тогда,
   когда нужен. Исправлено на реальный API; бюджет времени 120 c сохранён
   (`TimeoutError` → fail-closed), контракт читается из bundled
   `camera_release_label_v1.schema.json`.

## 2. Проверки

| Check | Результат |
|---|---|
| `pytest ml/camera_coach/tests/test_colab_bundle_gate.py` | **6 passed / 0 failed** (новый файл; в т.ч. регрессия на реальный API валидатора и отказ raw-review gold) |
| Пересборка бандла | `camera-coach-ml004-colab-bundle-20260927T102713+0000.tar.gz`, **SHA256 `d45e8ee245cd12b2435efb6d1f95a6dffb7da6765e27d18fb2dd870826f0707f`**, 12 449 rows, 18 code files, `HUMAN_GOLD awaiting_owner` |
| tar layout | 23 members, ожидаемая структура (bundle/, config.json, data_manifest.jsonl, check_environment.py, notebook, bundle-receipt.json, README_BUNDLE.md) |
| `check_environment.py --mode dry_run --sample 40` (Drive-зеркало из симлинков на local-data) | code hashes 18/18, contract PASS (7/7 heads), data 40/40 verified, **PREFLIGHT PASS, exit 0** |
| `--mode final_fit` без меток | **exit 3** `refused_no_human_labels` (fail-closed сохранён) |
| `--mode final_fit` c тестовой фикстурой гейта | **ADMITTED, exit 0**: `1 contract-valid adjudicated human_gold=true rows` |

Фикстура (`scratchpad/…/gate-test-fixture-NOT-LABELS.jsonl`) — синтетический
контракт-валидный конверт из `contracts/fixtures/camera_release_label_v1.valid.json`
с пометкой «NOT A LABEL»; это проверка логики гейта, **не разметка и не данные
для обучения**. Настоящих меток не создавалось.

## 3. Честные границы (что не сделано и почему)

- **Загрузка бандла на Drive и preflight на реальном Colab runtime** — за владельцем
  (нужен аккаунт/Drive/Colab Pro A100-T4); локально проверено только зеркало путей.
- **Наполнение human-gold** — DATA-008/010/011 (человек). Гейт останется закрытым,
  пока нет adjudicated `human_gold=true` строк: это и задумано (silver ≠ gold).
- Smoke-ячейка ноутбука на этот раз не перепрогонялась (код обучения не менялся);
  последний зелёный прогон — ресипт 2026-09-23.
- Сиблинги `colab_bundle/README.md` и `colab_training_template.ipynb` не менялись и
  остаются в рабочем дереве (uncommitted), как и остальной release-поток.

## 4. Environment

macOS arm64, python 3.11.9, torch 2.10.0 (CPU), jsonschema доступен. Все временные
артефакты (сборка, распаковка, Drive-зеркало, фикстура) — в session-scratchpad,
удаляются вместе с ним; в проектных каталогах и local-data ничего лишнего не создавалось.
