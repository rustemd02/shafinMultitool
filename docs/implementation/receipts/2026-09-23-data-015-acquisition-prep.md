# DATA-015 — acquisition prep: подготовленные манифесты под 4 named coverage gaps

Дата: 2026-09-23. Статус: **`prepared_not_downloaded`** — по дизайну слайса ни один байт не скачан и не зарезервирован; никаких изменений в `setos-backend/local-data/**` (0 файлов, 0 байт).
Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (ветка `store`). Git commit/push не выполнялись (запрещены слайсом).

## Метод

1. Взяты 4 названных пробела напрямую из `docs/implementation/data-coverage-matrix-v1.md` (DATA-004 ✓): §2 строки «Фон/окклюзия», «Главный объект (группы-как-герой CC-I02)», «Техническое качество (dirty-lens/focus-miss органика)», «Формат/пересъёмка (9:16/1:1 + title-safe)» и §4 п.3 «DATA-015 докупка». Никаких дополнительных семейств сверх названных gap'ов не добавлялось (запрет «не накачивать ещё AVA-like MOS ради объёма» соблюдён: ни один кандидат не является MOS/aesthetic-score корпусом).
2. Прецеденты репо сверены: `docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md` (AVA — только изолированный Stage-1 prior; никакие кандидаты не расширяют AVA-роль), права/лейбл-поля `ml/camera_coach/contracts/camera_release_label_v1.schema.json` (`source`: `source_family_id`/`frame_id`/`content_sha256`/`captured_at`; `provenance`: `human_gold`/`release_admissible`/`review_status`), словарь R1–R6 и `metadata_sha256`-агрегат из `receipts/2026-09-22-data-003-local-data-inventory.md`, честное правило `captured_at` из DATA-005 («пустой captured_at не выдумывается»), commons-прецедент candidates/accepted-rights receipts, а также зафиксированный blocker «OpenImages intake blocked» в семье `research/photography` (тот же DATA-003 receipt).
3. Создан каталог `docs/implementation/acquisition/` (только текстовые манифесты, как предписано слайсом; медиа сюда не попадает никогда — raw media остаётся в backend `local-data` по AGENTS.md).

## Изменения (CHANGES)

| Файл | SHA-256 |
|---|---|
| `docs/implementation/acquisition/acquisition-manifests-v1.json` (new) | `fcd4cae5b0f1f34728c9fbb87b0773a7b303cf5fb1c9acad04730b29a51a3d84` |
| `docs/implementation/acquisition/README.md` (new) | `52272f5917ec6e006fba0b87bfd22b94fd6c00bd0574b102c5488956256cae5b` |
| `docs/implementation/receipts/2026-09-23-data-015-acquisition-prep.md` (new, этот файл) | — |

## Gap → кандидаты (сводка)

| Gap (named, coverage matrix) | Целевой план locked | Кандидаты (все `prepared_not_downloaded`) | Критерий «закрывает named gap» (кратко) |
|---|---:|---|---|
| GAP-A-occlusion — «occlusion-семейство почти пусто» | 40 stills | A1 Commons photobomb/occlusion (per-file CC, R2); A2 Flickr Commons (NKCR/R1-R2); A3 Open Images occlusion-flags (R1, **blocked**: прецедент OpenImages intake blocked, активация — решение владельца) | ≥1 принятая семья даёт ≥40 usable stills для human-разметки heads `occlusion`/`background_competes_with_subject`/`frame_visually_overloaded`, полный per-item rights receipt, вне synthetic buckets |
| GAP-B-groups-as-hero — «группы-как-герой (CC-I02): нет ни одного источника» | 40 stills | B1 Commons group photographs (R2); B2 Flickr Commons (R1/R2); B3 Open Images ≥3 person (R1, **blocked** тот же) | ≥40 usable stills, где 3+ людей — задуманный главный target; групповая target-идентичность разменивается по `camera_release_label_v1` |
| GAP-C-dirty-lens-focus-miss-organic — «синтетика ≠ organic, Gate C1: отдельные buckets» | 40 stills | C1 Commons technical-defect search (R2); C2 COCO blurry-attribute shortlist (R1); C3 residual owner shot-list (без действий в слайсе, честный учёт остатка) | ≥20 organic usable stills (`lens_smudge`/`defocus`, ≥3 severity), отдельный organic bucket; остаток честно уходит в уже запланированный shot-list, а не в синтетику |
| GAP-D-formats-9x16-1x1-title-safe — «9:16/1:1 и title-safe — 0 при cinematic 16:9» | 25 stills | D1 Openverse API (aspect_ratio=tall/square + license-фильтр, R1/R2); D2 Commons dimension-filtered (R2) | ≥25 usable stills с native tall/square аспектом из upstream dimension metadata; human-оценка edge-pressure/title-safe по контракту |

Сумма целевых планов: 145 stills — консистентна с рабочим распределением квоты 350 в coverage matrix (40+40+40+25, плюс межгрупповой резерв; пороги `PRODUCTION_ACCEPTANCE.md` не менялись).

## Обязательные права-поля (зафиксированы в JSON `rights_field_contract`)

- На семью: `source`+URL, `author_or_upstream`, `license_class`, `attribution_requirements`, `hash_method_at_download`, `rights_tier_expected` (коды R1–R6 словаря DATA-003), `label_tier_at_ingest`, `per_item_license_gate`.
- На элемент при загрузке: `source_family_id`, `frame_id`, `source_record_key`, `content_sha256` (per-file SHA-256 → `image_sha256` манифеста), `captured_at` (только реальный EXIF), per-item license/author/source_url/rights_receipt; family `metadata_sha256`-агрегат по определению DATA-003; `human_gold=false`, `release_admissible=false` до DATA-008…011.
- Политика в JSON: allowed license classes (CC0/PD/CC-BY/CC-BY-SA/NKCR с per-item gate), forbidden (AVA-like MOS, scrape соцсетей, Pexels/Unsplash-класс, источники без подтверждаемой per-item лицензии), Gate C1 organic/synthetic separation, cross-manifest dedup по `content_sha256`+`source_record_key` против существующих семей.

## CHECK (выполненный)

Read-only python-верификация (`/tmp/setos-data015-prep/verify_acquisition_manifests.py`, удалена после прогона): **120/120 PASS**. Проверено: статус/байтовые поля (`prepared_not_downloaded`, 0/0 байт); все 4 named gap'а присутствуют и ссылаются на coverage matrix; каждый gap имеет ≥1 полностью укомплектованного кандидата (все обязательные rights-поля, `per_item_license_gate=true` для всех внешних источников, rights tier в словаре R1–R6, метод SHA-256, min/max/unit объёма); нулевые вхождения запрещённых маркеров (ava/MOS/pexels/unsplash/соцсети/scrape) в идентификационных полях кандидатов; policy-блок декларирует AVA-запрет, scrape-запрет, `human_gold=false` ingest и Gate C1 separation. Промежуточный прогон поймал 11 FAIL (в `rights_tier_expected` были пояснения поверх кода) — исправлено на чистые коды, повторный прогон 120/120 PASS.

Ограничение проверки: это структурная верификация подготовленных манифестов. Юридические поля лицензий — заявленные ожидания с обязательным per-item подтверждением при загрузке; сами источники в этом слайсе не посещались и не скачивались (by design).

## Что остаётся владельцу

1. Одобрить подмножество кандидатов (сейчас все `prepared_not_downloaded`; достаточно одного решения по списку A1…D2).
2. Решить судьбу Open Images blocker'а для A3/B3 (прецедент «OpenImages intake blocked»).
3. После одобрения — отдельный слайс загрузки: только в `setos-backend/local-data/SETOS/Datasets/camera-coach/research/<source_family>/`, intake по `rights_field_contract`, с последующим receipt (counts/bytes/metadata_sha256), затем скрининг через DATA-008 pilot-путь.

## GAPS / отклонения

- Статус строки DATA-015 остаётся `TODO`/PARTIAL по обновлению трекера: загрузка не выполнялась **by design** (bounded prep-slice, экономия диска — требование владельца, см. `receipts/2026-09-22-gov-007-storage-audit.md`).
- Номенклатурное отклонение от строки трекера: `Own` там указан «acquisition manifests under backend local-data»; слайс по прямому указанию создаёт текстовые манифесты в `docs/implementation/acquisition/` (0 байт данных в local-data). Оркестратор при обновлении строки может либо изменить Own-указатель, либо перенести манифесты; содержательно путь загрузки остаётся local-data.
- Organic dirty-lens (GAP-C): внешние источники честно ограничены; критерий закрытия gap'а снижен до ≥20 usable stills + явный residual в owner shot-list (C3) вместо накачки объёма. Возможный остаток gap'а фиксируется, не скрывается.
- Временные файлы: `/tmp/setos-data015-prep/` (скрипт проверки + вывод) — удалены в конце слайса; в репозиторий и local-data не попадали.

## Acceptance

`DATA-015 (prep-slice) PARTIAL→prepared`: каждая новая source family в манифестах привязана к named gap из coverage matrix с критерием закрытия; manifest/rights-поля полны и проверены (120/120); bytes_downloaded=0. Полное `DONE` строки невозможно и не предпринималось без решения владельца на загрузку.
