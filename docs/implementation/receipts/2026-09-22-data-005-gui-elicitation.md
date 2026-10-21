# DATA-005 — GUI-элиситация и export release label из annotate_gui (завершение остатка)

Дата: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`, ветка `store`.
Предыдущий принятый слайс: `receipts/2026-09-22-data-005-annotation-release-label.md` (adapter, PARTIAL).

## Что добавлено

- `tools/camera_annotation/release_label_config.py` (новый, pure, без tkinter) — сборка conversion-config для
  `release_label_adapter.py convert --config` из плоских dict'ов состояния GUI:
  - `build_conversion_config(review, ...)` — единственная точка сборки; на входе валидирует v1-запись
    (`annotation_labels.validate_label`), требует non-empty `notes` (raw opinion конверта — fail-fast правила адаптера,
    сам adapter не менялся); для unsure требует явный `abstention_reason` из enum'а схемы; для needs_fix требует
    единственный corrective или явный выбор; для каждого present-issue требует severity/confidence (0..1) и
    evidence-ref (stable id); target требует все факты (entity_ref/identity_status/kind/role/movability), enum'ы и
    паттерны (`recordID` `^cam-release-[a-z0-9][a-z0-9._-]*$`, `stableID`, формат `captured_at`) читаются из
    `ml/camera_coach/contracts/camera_release_label_v1.schema.json` при импорте — без дублирования словаря.
  - `sanitize_release_record_id` — `cam-release-` + санитизация record_id (пункт (d) задачи).
  - `sanitize_stable_id`, `parse_unit_interval`, `derive_source_fields` (source_family_id/frame_id/captured_at из
    записи; пустой captured_at НЕ выдумывается), `_parse_rect` (нормализованный rect внутри кадра).
  - Любой отказ — `ReleaseConfigError` ДО записи файлов и ДО запуска адаптера: GUI показывает сообщение и не
    создаёт ни записи, ни файла.
- `tools/camera_annotation/annotate_gui.py` (Own-файл слайса):
  - (a) у каждого issue — поля severity/confidence (текст, парсинг 0..1) и evidence-ref (через запятую → refs);
  - (b) блок Target: entity_ref, identity_status/kind/role/movability/permission (combobox'ы со значениями контракта),
    чекбокс «rect = выбранная область» (rect берётся из выбранного региона; включён без региона → отказ);
  - (c) source-поля family/frame/captured_at предзаполняются из записи очереди (`derive_source_fields`), captured_at
    при отсутствии в записи остаётся пустым до ручного ввода;
  - (d) `release_record_id = cam-release- + record_id` с санитизацией, показывается в панели до экспорта;
  - (e) кнопка «Экспортировать release label»: те же human-gates, что и сохранение (рефакторинг `save_current` →
    общий `_build_review_record`, гейты и сообщения сохранены), затем сборка config'а → `asksaveasfilename`
    (default dir `local-data/SETOS/annotation/release-labels/`) → subprocess `release_label_adapter.py convert`
    (временные JSON только в `/tmp`, `TemporaryDirectory(dir="/tmp")`, автоудаление) → при REJECTED показывается
    stderr адаптера и НЕ пишется ничего (адаптер сам пишет `--out` только на успехе) → на успехе сразу
    `validate --label` и показ `EXPORTED`/`RELEASE LABEL VALID`.
  - Экспорт всегда `origin=human_review`, `human_gold=false`, `release_admissible=false` — adjudication/gold это
    отдельные человеческие шаги (DATA-009/011), дефолта в GUI нет. Экспорт не пишет в v1-store.

## Проверки (команды и результат)

```
python3 -m pytest tools/camera_annotation/tests/test_release_label_config.py -q
  → 13 passed
python3 -m pytest tools/tests/test_annotation_independence.py tools/tests/test_annotation_labels.py \
  tools/tests/test_annotation_roundtrip.py tools/camera_annotation/tests/test_release_label_config.py -q
  → 1 failed, 49 passed (см. «Пред-существующее окружение» ниже)
/tmp smoke (headless Tk, monkeypatched dialogs): построение панели с новыми виджетами, префиллы,
сбор состояний → config; полный export_release_label: EXPORTED+VALID; очистка severity → error-диалог
«Экспорт отклонён — запись не создана», байты выходного файла не изменились, v1-store не создан.
Временные скрипты/директории смоука в /tmp удалены после проверки.
```

Покрытие тестов (`tools/camera_annotation/tests/test_release_label_config.py`):

- happy path: fixture-review + элиситации → адаптер `convert` → envelope с raw opinion → `validate` →
  **RELEASE LABEL VALID**; плюс abstain-путь (unsure + явная причина) и good-путь (keep без issue-эвиденции) → VALID;
- пропущенная элиситация (пустой severity / пустой evidence-ref / неполный target / пустой captured_at /
  несколько corrective без выбора / пустой notes) → `ReleaseConfigError` у билдера, т.е. GUI не экспортирует;
- независимый boundary: config без issue-эвиденции, скормленный адаптеру напрямую (в обход GUI) →
  `CONVERSION REJECTED`, exit 1, выходной файл не создан;
- санитизация id (`benchmark__Frame 001.JPG` → `cam-release-benchmark__frame-001.jpg`; кириллический entity_ref
  отказывается, а не транслитерируется молча), парсинг 0..1 («0,8» → 0.8; «1.5» → отказ), derive source-полей.

## Пред-существующее окружение (не результат этого слайса)

- `tools/tests/test_annotation_roundtrip.py::test_queue_hashes_still_match_the_files_on_disk` падает: очередь
  `queue-v3-cinematic.jsonl` хранит старые абсолютные пути `~/Library/Application Support/SETOS/...`, а медиа после
  релокации лежит в `setos-backend/local-data/SETOS/...` (зафиксировано в AGENTS.md/LOCAL_DATA.md; исторические
  манифесты не переписываются). Тест не импортирует `annotate_gui` и не затронут моими изменениями.

## Границы соблюдены

- Изменены только `tools/camera_annotation/annotate_gui.py` (M), новые `release_label_config.py` и
  `tests/test_release_label_config.py` (в tests/ также лежит чужой `test_data_006_annotation_api.py` — не тронут).
- `release_label_adapter.py`, `annotate_camera.py`, `annotation_labels.py`, `review_pipeline.py` — не менялись
  (чужие M в `review_pipeline.py`/`language_review.py` остались чужими). CAM-009 diff не тронут. Без commit/push.

## Честные ограничения

- Реальный визуальный QA GUI (скролл панели 450px, клавиатура, RU-копирайтинг, Dynamic Type не применим — desktop
  tool) — при pilot-UX DATA-008; здесь smoke только headless-проверка логики и полного export-потока.
- `captured_at` не выводится из EXIF/времени файла: EXIF без таймзоны, авто-вывод `…Z` фабриковал бы provenance —
  поле ручное с префиллом из записи, когда запись его несёт.
- evidence-ref по умолчанию не генерируется из регионов автоматически (аннотатор вводит, напр.
  `record_id.region0`); rect подставляется только по явному чекбоксу выбранной области.
- Verdict `mixed`, risk-элиситация, before_after и adjudication — вне этого остатка (как и в предыдущем слайсе).
