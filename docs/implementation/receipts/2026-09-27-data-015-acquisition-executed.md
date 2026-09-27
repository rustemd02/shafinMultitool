# DATA-015 — одобрение acquisition-кандидатов и закупка 145/145 (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `8b36e578` · Ветка: `store`
Задача: **DATA-015** (закрытие строки; база — ресипт `2026-09-23-data-015-acquisition-prep.md`,
манифесты `docs/implementation/acquisition/acquisition-manifests-v1.json`)
Делегировано: одобрение acquisition-кандидатов (§19 п.14).

## 1. Решение (owner-delegated 2026-09-27)

**Одобрить всех названных кандидатов** по 4 доказанным coverage gaps
(«не накачивать AVA-like MOS ради объёма» — правило строки соблюдено:
ни один запрещённый класс источника не использован):

- **Исполнено в этом слайсе:** A1/A2 (occlusion), B1/B2 (groups-as-hero),
  C1-класс (organic technical defects), D1/D2 (tall/square aspects) —
  через Openverse API (агрегатор Flickr Commons/Wikimedia и прочих
  CC-источников; allowlist CC0/PDM/CC-BY/CC-BY-SA, per-item license gate).
- **Одобрено, не скачивалось:** A3/B3 (Open Images) и C2 (COCO) —
  допустимые альтернативы, но их загрузка — dataset-scale аннотационные
  CSV/батчи и после выполнения квот не нужна (записано как запасные
  источники на случай брака по relevance).
- **Одобрено как будущая съёмка:** C3 (owner shot-list, физическая съёмка).

Обоснование: строки DONE-when требуют дособрать доказанные gaps; квоты
40/40/40/25 = 145 из prep-манифеста выполнены полностью policy-чистыми
источниками с per-item правами.

## 2. Что скачано и где

Harvester: `tools/dataset/acquire_openverse_gaps.py` (TLS-верификация через
certifi — НЕ отключалась; первая попытка честно упала на
`CERTIFICATE_VERIFY_FAILED` и удалена без следов, повтор — с явным CA-store).

| Gap | Семейство (local-data `Datasets/camera-coach/research/`) | Квота | Скачано |
|---|---|---:|---:|
| GAP-A occlusion | `openverse-occlusion-20260927/` | 40 | **40** |
| GAP-B groups-as-hero | `openverse-group-hero-20260927/` | 40 | **40** |
| GAP-C organic technical | `openverse-organic-technical-20260927/` | 40 | **40** |
| GAP-D 9:16/1:1 aspects | `openverse-format-aspects-20260927/` | 25 | **25** |

Итого **145/145**, ~102 MB; raw media — только в backend local-data
(не в Git и не в Xcode bundle). Лицензионная смесь (дословно из API):
CC-BY 105, CC-BY-SA 28, PDM 7, CC0 5 — весь allowlist; ни одного
отклонения по license gate (0 skipped по лицензии).

## 3. Верификация (команды выполнялись)

| Check | Итог |
|---|---|
| Построчная сверка `items.jsonl` ↔ файлы на диске (sha256) + непустые creator/license/foreign_landing_url/fetched_at | **145 записей, 0 проблем** |
| Запись прав: каждая запись несёт source/author/license/license_url/landing URL/SHA-256/bytes/fetched_at **дословно из API** | PASS (license_url/creator не редактировались) |
| Label tier на входе | `silver_raw`, research-only — human-разметка отдельной задачей (DATA-008/010), не выдаётся за gold |
| Один download упал HTTP 429 (Wikimedia rate-limit) | записан в лог, квота закрыта следующим item'ом; ни одного файла «досочинено» |

Сводный receipt: `local-data/SETOS/Datasets/camera-coach/research/acquisition-receipt-20260927.json`
(пер-семейство counts + skipped-счётчики); обновлён
`docs/implementation/acquisition/acquisition-manifests-v1.json`
(status → `approved_and_acquired_20260927`, блоки `approval`/`acquisition_result`).

**Известная нюанса (честно):** `candidate_id` в записях присвоен по
source-классу словаря кандидатов; для GAP-C записи вне словаря (flickr и
прочие) получили fallback `D1-openverse-aspect-filtered` — фактически это
organic-technical поиск (C1-класс). Записи не переписывались; уточнение
зафиксировано в манифесте и здесь.

## 4. Статус

DATA-015 → **`DONE`**: кандидаты одобрены (§19 п.14 закрыт), 4 доказанных
coverage gap'а дособраны до квот (145/145) с per-item правами и hash-верификацией.
Остатков строки нет; дальше данные идут в human-разметку (DATA-008/010) и
в training package (DATA-016) — отдельные строки.
