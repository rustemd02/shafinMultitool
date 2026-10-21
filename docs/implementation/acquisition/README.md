# DATA-015 acquisition prep — prepared manifests (v1)

Дата: 2026-09-23. Статус: **`prepared_not_downloaded`** — 0 байт скачано, 0 байт зарезервировано.
Задача: DATA-015 (`TODO` → исполненный prep-слайс), Depends: DATA-003 ✓, DATA-004 ✓.
Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (ветка `store`).

## Что это

`acquisition-manifests-v1.json` — подготовительные acquisition-манифесты ровно под **4 названных пробела** из `docs/implementation/data-coverage-matrix-v1.md` (§2/§4 «DATA-015 докупка»). Каждый gap содержит: целевые counts из coverage matrix, 2–3 кандидата-источника с лицензией/ожидаемым объёмом/методом хеширования, обязательные rights-поля и явный критерий «закрывает named gap».

Никаких загрузок здесь нет и не будет: слайс — подготовка решения владельца. Скачивание выполняется **отдельным слайсом** после того, как владелец одним решением утвердит подмножество кандидатов.

## 4 named gap → кандидаты

| Gap | Coverage matrix | Целевой план (locked) | Кандидаты |
|---|---|---:|---|
| GAP-A-occlusion | «Фон/окклюзия»: occlusion-семейство почти пусто | 40 stills | A1 Commons photobomb/occlusion; A2 Flickr Commons; A3 Open Images occlusion-flags (blocked*) |
| GAP-B-groups-as-hero | «Главный объект»: группы-как-герой (CC-I02) — 0 источников | 40 stills | B1 Commons group photographs; B2 Flickr Commons; B3 Open Images multi-person (blocked*) |
| GAP-C-dirty-lens-focus-miss-organic | «Техническое качество»: только синтетика, Gate C1 требует отдельные organic buckets | 40 stills | C1 Commons technical-defect search; C2 COCO blurry-attribute; C3 residual owner shot-list (без действий в этом слайсе) |
| GAP-D-formats-9x16-1x1-title-safe | «Формат»: 9:16/1:1 и title-safe — 0 при cinematic 16:9 | 25 stills | D1 Openverse aspect-filtered; D2 Commons dimension-filtered |

\* A3/B3 заблокированы прецедентом «OpenImages intake blocked» в семье `research/photography` (DATA-003 receipt); активируются только явным решением владельца.

## Юридическая рамка

- Разрешено: `CC0`, `public domain`, `CC-BY-*` и `CC-BY-SA-*` с per-item атрибуцией и receipt, `no_known_copyright_restrictions` (Flickr Commons). Per-item license gate обязателен: элемент без подтверждённой лицензии отклоняется (прецедент commons candidates/accepted-rights).
- Запрещено: AVA-подобные MOS-корпуса ради объёма (запрет строки DATA-015 + политика `docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md`), scrape соцсетей, источники без явных dataset-redistribution условий (Pexels/Unsplash-класс).
- Все семьи на входе: `silver/unlabeled · human_gold=false · release_admissible=false`. Продвижение — только через human-путь DATA-008…011.
- Gate C1: organic и synthetic/adversarial остаются раздельными buckets; новое organic-семейство (GAP-C) не смешивается с `paired-corruptions`.

## Поля (контракт прав)

Обязательные поля на семью и на элемент — в JSON `rights_field_contract`: `source`, `author_or_upstream`, `license_class`, `attribution_requirements`, `hash_method_at_download` (per-file SHA-256 → `image_sha256` + family `metadata_sha256` по определению DATA-003), `rights_tier_expected` (словарь R1–R6 из DATA-003), `label_tier_at_ingest`, `per_item_license_gate`; на элемент также `source_family_id`, `frame_id`, `source_record_key`, `content_sha256`, `captured_at` (только реальный EXIF — «пустой captured_at не выдумывается», прецедент DATA-005), per-item license/author/source_url/rights_receipt; `human_gold=false`, `release_admissible=false` до adjudication.

## Что остаётся владельцу

1. Прочитать `acquisition-manifests-v1.json` и пометить утверждённых кандидатов (все — `prepared_not_downloaded`).
2. Решить судьбу Open Images blocker'а (A3/B3).
3. После одобрения — отдельный слайс: загрузка строго в `setos-backend/local-data/SETOS/Datasets/camera-coach/research/<source_family>/` (никогда в этот iOS-репозиторий и Xcode bundle; экономия диска — GOV-007), с приёмкой по `rights_field_contract` и receipt.

## Проверка

`verification.method` в JSON: read-only python-чек структуры — каждый из 4 named gap'ов покрыт ≥1 кандидатом с полными rights-полями; статус и байтовые поля; скан allowed/forbidden лицензий. Результат зафиксирован в `../receipts/2026-09-23-data-015-acquisition-prep.md`.
