# DATA-007 — Import identity: reject colliding raw record_id, keep stable source/frame/content identity

Дата: 2026-09-22 · HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (ветка `store`; в рабочем дереве присутствуют чужие параллельные diff CAM-009/DATA-005/008 — `annotate_gui.py`, `language_review.py`, `review_pipeline.py`, `release_label_*`; ими задача не пользовалась и их не меняла)

Задача (трекер §10): запретить import по коллидирующему raw `record_id`; использовать stable source/frame/content identity. Check: known 900 rows/450 links сохраняются; collision fixture отклонён или disambiguated.

## Вердикт

Существующий владелец/паттерн уже реализован (правило трекера «расширять существующий путь, не создавать параллельный» соблюдено): **нового механизма не добавлено**. Import guard — fail-closed reject по raw `record_id` с полным сравнением содержимого (включая `image_sha256`/`media_sha256`); идентичность записи обеспечивается композитным normalized ID (source_family + group + pair + role) + контентным SHA, перепроверяемым на экспорте (DATA-005 `release_label_adapter.py`, `language_intake.image_pixels`). Дизамбигуация суффиксом не вводилась сознательно: она создала бы параллельные identity для одного raw ID; трекер допускает «отклонён ИЛИ disambiguated» — выбран reject.

Поведение **до** (уже в baseline, но без свежего evidence на текущем дереве):

- `tools/camera_annotation/build_annotation_queue.py:165-186` — дубликат внутри sampled source → `Duplicate source record ID`; повторный import с тем же ID: байт-идентичная строка → идемпотентный skip, любое отличие (media sha, pair membership, provenance) → `Conflicting record ID` **до** записи output.
- `tools/camera_annotation/language_review.py:96-105,108-143,160` — `unique_record_index` отклоняет invalid/duplicate ID в reopened queue, direct queue и frame manifest до любых journal/media/worker обращений.
- `tools/camera_annotation/language_intake.py:157-159` — intake-экспорт отклоняет очередь с коллидирующим raw ID (`Duplicate queue record IDs`) до интерпретации журнала.

Поведение **после**: то же самое, но зафиксировано свежим evidence на текущем рабочем дереве + 2 недостающих focused-негатива.

## Изменения

- `tools/tests/test_annotation_record_identity.py` (+28 строк, единственный изменённый задачей файл): добавлены
  1. `test_content_hash_collision_under_stable_id_rejects` — тот же `record_id`, та же source/pair identity, отличается только `image_sha256` → `Conflicting record ID`, output не создан (точный fixture из строки трекера «same record_id, другой content_sha256»);
  2. `test_intake_queue_collision_rejects_before_any_review_or_output` — intake-путь (`language_intake.export_language_review`) отклоняет очередь с коллидирующим raw ID до записи output и без модификации журнала.
- Код `language_intake.py` / `build_annotation_queue.py` / `review_pipeline.py` НЕ менялся. Идемпотентность «identical content + same id» уже покрыта существующим `test_exact_repeat_remains_idempotent_and_distinct_ids_keep_identical_pixels`.

## Проверки (команды и результаты)

1. Focused suite на текущем рабочем дереве (включая чужие параллельные diff):
   `python3 -m pytest tools/tests/test_annotation_record_identity.py -q` → **11 passed** (0.16s).
2. READ-ONLY collision fixture на реальных данных (запись только в `/tmp/data007-import-identity`, удалено):
   `build_annotation_queue.py --output /tmp/.../raw-collision-queue.jsonl --per-source benchmark=0 ava=0 aadb=0 --extra-manifest <raw research manifest>` →
   exit=1, `ValueError: Conflicting record ID in .../scenetrans_bedroom_shelf_pairs_20260914/manifest.jsonl: photo__scenetrans_bedroom_shelf_pairs_20260914__pair_0000__A` (build_annotation_queue.py:183), **output-файл не создан**.
3. READ-ONLY сохранность known package (тот же CLI, normalized package manifest):
   exit=0, `queue: 11810 records`; импортированный порядок/содержимое байт-равны источнику (`rows == src`); **SceneTrans: 900 rows, 900 unique record_ids**.

## Counts (READ-ONLY, только grep/wc/python-чтение; ни один файл local-data не модифицирован)

| Файл | Rows | Unique | Примечание |
|---|---:|---:|---|
| `research/synthetic/scenetrans_bedroom_shelf_pairs_20260914/manifest.jsonl` (RAW) | 900 | 450 | raw-коллизия: pair_0000 повторяется в группах, ID без префикса группы; дубли строк неидентичны → import обязан отклонять (проверка 2) |
| `research/.../scene-change-pairs.jsonl` (RAW) | 450 | 225 pair_id | raw relation, сохранена как provenance |
| `colab_package_v2_20260914/manifest.jsonl` (production) | 11810 (всего) / 900 SceneTrans | 900 SceneTrans unique | нормализация ID префиксом группы (`photo__<family>__<group>__<pair>__A/B`) |
| `colab_package_v2_20260914/provenance/scenetrans_bedroom_shelf_pairs_20260914/scene-change-pairs.jsonl` | 450 | 450 before + 450 after | **450 pair links сохранены**; все 900 endpoint-ID резолвятся в package manifest |
| `annotation/language-review-20260915/queue.jsonl` / `opinions.jsonl` | 384 / 85 | — | текущие review-входы без SceneTrans; не менялись |
| `annotation/queue-v1.jsonl` (320) / `queue-v3-cinematic.jsonl` (547) | — | — | не менялись |

SHA-256 (после всех прогонов, без изменений): raw manifest `5f0a010cf1440e47874915e405e8b4a1eb73a3716f0faa973f5886be02033725`; raw pairs `0bf93a6f6ce5804adffca5b4608963b405f2c9987313a36b875be1cc3d2f24c7`; package manifest `2b0ad7f1bb459090b4afe4f4150dd90a4c9d06a8dc06455f48a331611c0b7e04`; package pairs `2d878c5f8e2d69996ceb83d046242de63da0ef9ded4fda58b36c6446a9d441f4`; language queue `fe0a15ca7b25e1bff4a610c2d7a1e726db5469b2250c1cad51ccc55c00a4a582`; language opinions `76d7e883d9409481f7d5f8ebeace032ea7bb51e1c2d22917b7158c21aba09399`.

## Gaps / ограничения

- Пакет верификации 2026-09-17 `local-data/SETOS/verification/annotation-record-identity-s2y7d7p6/` (referenced из `docs/thesis/03_evidence_map.md` EV-CA-ANNOTATION-IDENTITY-20260917) **отсутствует** на диске; ссылки thesis stale. Данный receipt заменяет свежим evidence; обновление evidence map/claim registry — за оркестратором.
- Reject вместо suffix-disambiguation: выбран сознательно (см. вердикт); историческая починка raw-коллизии — нормализация в package build (`research/webresearch-2026-09-14/scenetrans_subset.py`), вне границ этой задачи.
- Suite прогнан на рабочем дереве с параллельными чужими diff (не на чистом HEAD); изоляция моего изменения — diff одного тест-файла (+28).
- Ресипт подтверждает только data-tool identity-гварды: никаких dataset/journal writes, provider/model runs, human-gold/rights/model admission.
