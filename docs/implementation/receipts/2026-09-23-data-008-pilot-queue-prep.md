# DATA-008 — подготовка pilot-очереди 100 diverse items (prep-слайс)

Дата: 2026-09-23. Ветка `store`, HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`.
Задача: DATA-008 («Провести pilot 100 diverse items одним reviewer…»). Этот слайс — **только
подготовка очереди**: разметку выполняет владелец, статус задачи остаётся за оркестратором.

## Границы слайса

- Записи созданы только в новом каталоге
  `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/annotation/pilot-20260923-strata-v1/`
  (`queue.jsonl`, `README.md`). Ни один существующий файл local-data не модифицирован, не перемещён,
  не удалён (существующие очереди читались read-only).
- В iOS-репозитории создан единственный файл — этот receipt. Без commit/push. Без xcodebuild, без
  запуска ML/моделей. Лейблы/вердикты не ставились.

## Что подготовлено

- `queue.jsonl` — 100 строк, `record_id` вида `pilot23-<group>-<NN>`, поля: `package_record_id`
  (стабильная identity v2-пакета, DATA-007-совместимая), `source_family_id`, `frame_path`
  (относительно SETOS root), `image_path` (абсолютный текущий путь для annotate_gui),
  `content_sha256` == `image_sha256`, `pixel_sha256`, `strata_group`, `intentional_style_flag`,
  `status="pending_human_review"`, `review_mode="blind"`, размеры, сокращённый `provenance`
  (kind/title/author/license/origin/origin_url), `research_only=true`, `human_gold=false`,
  `release_admissible=false`, `source_manifest_sha256`.
- `queue.jsonl` sha256: `cbb55e6376cf4e2d560ba52426347f40d90a57f61419c3401a511ea839c3cbbe`.
- `README.md` — инструкция запуска (`tools/camera_annotation/annotate_gui.py` + экспорт
  `camera-release-label-v1` через `release_label_config` → `release_label_adapter convert/validate`),
  правила fail-closed элиситаций из `2026-09-22-data-005-annotation-release-label.md` и
  `2026-09-22-data-005-gui-elicitation.md`, целевые counts, правило «ни одна proposal не становится
  gold без human подтверждения», честные ограничения покрытия.

## Метод отбора (детерминированный, без случайности)

1. Источник — v2-пакет `Datasets/camera-coach/colab_package_v2_20260914/manifest.jsonl`
   (11 810 кадров, 12 семейств); `manifest.jsonl` sha256
   `2b0ad7f1bb459090b4afe4f4150dd90a4c9d06a8dc06455f48a331611c0b7e04` сверен с
   `package-receipt.json` → OK.
2. Исключены все кадры существующих очередей: union `record_id`/`image_sha256` из
   `queue-v1.jsonl` (320), `queue-v2-app-domain.jsonl` (174), `queue-v3-cinematic.jsonl` (547),
   `pilot-20260914-v4/*` (blind 100 / assisted 200 / assisted-with-proposals 200; union 1 086 id).
   Реально пересекаются с v2-пакетом только 300 кадров `commons_scenario_photo_candidates_20260914`
   из pilot-v4 — все исключены. Итоговое пересечение очереди с использованными кадрами: **0** —
   все 100 кадров свежие.
3. Пулы по семействам → сортировка по `content_sha256` (затем `package_record_id`) → первые N на
   группу (план DATA-004 §4: 8–12 stills на группу, ≥15 намеренно-стилевых). Глобально уникальный
   `content_sha256` (одно вхождение на хеш).
4. `temporal` — 5 A/B-вариантов scenetrans по 2 кадра, половины соседними строками
   (`pair_side`/`pair_with`/`temporal_pair_id`). Байт-идентичные варианты (`0_item`, A==B;
   в пакете 222 из 900 scenetrans-строк делят sha с соседом) исключены — выбраны только варианты
   с различающимися A/B.
5. Замены кадров не потребовались (`replacement_log` пуст; все выбранные файлы существовали и
   сошлись по хешу с первой попытки).

## Strata-таблица (группа → target → выбрано → источники)

| Группа §4 | target | выбрано | источники (кадров) |
|---|---:|---:|---|
| composition | 10 | 10 | scenetrans_bedroom_shelf_pairs (10) |
| subject (главный объект) | 10 | 10 | commons_quality_diverse (10) |
| light (свет/цвет) | 10 | 10 | mit_adobe_fivek (6), lasiesta (4) |
| background (фон/окклюзия) | 10 | 10 | commons_real_video_sequence (10) |
| technical (техкачество) | 10 | 10 | lasiesta (10) |
| people (люди) | 10 | 10 | lasiesta (10) |
| movable (объекты сцены) | 10 | 10 | scenetrans_bedroom_shelf_pairs (10) |
| format (формат/пересъёмка) | 10 | 10 | Blender open movies: sintel 3, tears_of_steel 3, bbb 2, spring 1, elephants_dream 1 |
| temporal (временное) | 10 | 10 | scenetrans A/B, 5 вариантов (pair_0000/0002/0004) |
| goodframe (хороший кадр) | 10 | 10 | met_open (5), Blender open movies (5) |
| **Итого** | **100** | **100** | 11 семейств |

`intentional_style_flag=true`: 20 строк (format 10 + goodframe 10) ≥ 15. Основание — тип семейства
(art-directed Blender open movies; курируемые музейные фото Met Open Access), семантика не
выдумывается; reviewer может переопределить intent.

## Hash-верификация

- `manifest.jsonl` == `package-receipt.json` → OK (см. выше).
- Каждый из 100 файлов: существует, `sha256(байтов) == content_sha256` манифеста → **100/100 OK**,
  суммарно 50 387 281 байт. Проверка выполнена 2026-09-23 скриптом-селектором (временный,
  `/tmp`, удалён после прогона; логика и числа зафиксированы здесь и в README).

## Честные ограничения (что остаётся за человеком и чего нет в пакете)

- Strata-отнесение — по семейству источника из таблицы §2 `data-coverage-matrix-v1.md`;
  per-frame меток пакет не несёт. Несоответствие кадра группе — валидный пилотный сигнал.
- technical: organic blur/focus-miss/dirty-lens в v2-пакете отсутствуют (paired-corruptions/tapvid
  вне пакета) — lasiesta-кадры слабое замещение, возможен дефицит реальных дефектов.
- people: AVA намеренно исключён (не release-admissible по правам); lasiesta не гарантирует людей.
- movable: только synthetic scenetrans-редакции; реальные movable-объекты — DATA-015/съёмка.
- temporal: синтетические A/B-пары — proxy для практики вердиктов; настоящие episodes — DATA-013.
- format: только 16:9; 9:16/1:1/title-safe — 0 источников в пакете.
- **Остаётся человеку (владельцу):** вся разметка 100 кадров через annotate_gui, измерение времени,
  фиксация disagreement с proposal и schema gaps (журнал DATA-008); обновление строки DATA-008 в
  трекере — оркестратором после завершения pilot labels.

## Команды проверки

```bash
python3 - <<'PY'
import json, hashlib
q='/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/annotation/pilot-20260923-strata-v1/queue.jsonl'
rows=[json.loads(l) for l in open(q)]
assert len(rows)==100 and all(r['status']=='pending_human_review' for r in rows)
print(hashlib.sha256(open(q,'rb').read()).hexdigest())
PY
# ожидаемо: cbb55e6376cf4e2d560ba52426347f40d90a57f61419c3401a511ea839c3cbbe
shasum -a 256 /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/colab_package_v2_20260914/manifest.jsonl
# ожидаемо: 2b0ad7f1bb459090b4afe4f4150dd90a4c9d06a8dc06455f48a331611c0b7e04
```
