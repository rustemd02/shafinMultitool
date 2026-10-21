# GOV-007 — Полная карта занятого проектом пространства + byte-level дубликаты (audit-only)

Дата: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (ветка `store`).
Метод: `du` по всем корням + content-hash (SHA-256, 8 процессов) всех файлов перечисленных семейств `local-data/SETOS` с размером ≤ 4 ГиБ, попавших в size-коллизии между семьями. Проектные данные **не удалялись и не перемещались**.

## 1. Карта занятого пространства (du, размещённые байты)

| Путь | Размер | Примечание |
|---|---:|---|
| `~/Documents/XCode/shafinMultitool` (iOS repo) | 4.9 GB | `.git` 2.2 GB; tracked-контент 1.42 GB (logical); ignored: `llama.cpp/` 335 MB, `shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf` 1.0 GB |
| `~/Documents/XCode/setos-backend` | 37 GB | код backend ≤ 1 MB; ≈ весь объём — `local-data/` |
| `setos-backend/local-data/SETOS/Datasets` | 37 GB | см. §2 |
| `local-data/SETOS/annotation` | 24 MB | |
| `local-data/SETOS/snapshots` | 3.4 MB | |
| `local-data/SETOS/verification` | 284 KB | зеркало из предварительной оценки 2026-09-20 («до 12 GB») **не существует** |
| `local-data/SETOS/inventory` | 108 KB | |
| `~/Library/Developer/Xcode/DerivedData` | 9.2 GB | `Bonus_Exchange` (чужой проект) 5.6+2.4 GB; `ModuleCache.noindex` 750 MB; `shafinMultitool-*` 20 KB |
| `~/Library/Developer/Xcode/iOS DeviceSupport` | 13 GB | `iPhone14,2 27.0 (24A435)` 6.4 GB + `iPhone14,2 27.0 (24A5430a)` 6.3 GB (beta-сборка) |
| `~/Library/Developer/Xcode/Archives` | 2.3 GB | инженерные архивы 2026-09-04…22 (крупнейшие 579 MB и 556 MB) — release evidence, не кандидат на удаление |
| `~/Library/Developer/CoreSimulator/Devices` | 9.0 GB | устройство `1F680A42…` 7.5 GB + `79E82949…` 1.3 GB |
| `/tmp` (артефакты трекера) | ~32 MB | `gov007` скретч 32 MB, `data002-validator.out`, `data003-receipt-diff` |

## 2. Семейства `Datasets/camera-coach` (37 GB)

| Семейство | du | Логических байт (receipts) | Дублируется с другими семьями (hash) |
|---|---:|---:|---:|
| `research/` (мастер-данные) | 21 GB | — | 4.475 GB его контента продублирован в пакетах; внутри самого `research/` 1.567 GB повторов |
| `colab_package_v2_20260914/` (финальный v2) | 3.1 GB | 3.343 GB | 3.308 GB — производное от `research/` |
| `…attempt1_frame_name_collision_preserved/` | 1.4 GB | 1.565 GB | 1.406 GB |
| `…attempt2_paired_dedup_preserved/` | 2.5 GB | 2.700 GB | 2.668 GB |
| `…attempt3_sequence_qc_preserved/` | 2.6 GB | 2.797 GB | 2.796 GB |
| `…attempt4_temporal_dedup_preserved/` | 2.6 GB | 2.797 GB | 2.797 GB |
| `…attempt5_scenetrans_id_collision_preserved/` | 2.6 GB | 2.798 GB | 2.764 GB |
| `colab_package/` (v1) | 756 MB | — | 765 MB |
| `silver-fit-20260918/` | 694 MB | — | 11 MB (практически уникален: чекпойнты/логи) |

`attempt3` vs `attempt4` расходятся на 323 логических байта (`package-receipt.json` bytes 2797447543 vs 2797447866) — фактически копии. `attempt5` повторяет счётчики финального v2 (11 810 frames / 84 clips / 31 dupes) при равном медиа-контенте.

## 3. Byte-level дубликаты (SHA-256)

- Перечислено 149 206 файлов; прошито 95 206 файлов = 21.091 GB (size-парность → hash только коллидирующих файлов).
- Дубликат-групп: 12 446, из них **кросс-семейных 12 066**.
- Крупнейшая группа: `research/temporal/tapvid_rgb_stacking_20260914/raw/tapvid_rgb_stacking.zip` 0.19 GB × 8 идентичных копий (research + v1 + v2 + attempts 1–5).
- Типовые группы: manifest/rights/frames-файлы, идентично повторяющиеся во всех пакетах; фреймы `scenetrans_bedroom_shelf_pairs` встречаются до ×16.
- **Консервативный reclaim: 13.197 GB** — байты в `attempt1…5` + `colab_package` (v1), каждый из которых имеет байт-идентичную копию в `research/` или финальном v2 пакете. Полное удаление шести директорий вернуло бы ≈ 12.5 GB (du) с сохранением всего уникального контента, кроме их собственных небольших манифестов/receipts.
- Внутри `research/`: 1.567 GB повторов (report-only; мастер-данные не трогаем).

## 4. Границы погрешности

- Не прошит 1 файл > 4 ГиБ: `research/synthetic/scenetrans_bedroom_shelf_pairs_20260914/raw/bedroom1_shelf_sim_800.zip` (5.54676 GiB); рядом лежит распакованный `frames/` 1.0 GB.
- `~/Library/**`, Archives, `.git` измерялись только `du`/git-статистикой, без content-hash (вне хеш-обязательства GOV-007 по local-data).
- Historical receipts/manifests не переписывались; старые абсолютные пути сохранены как есть.

## 5. Что удалено

- **Проектные данные: удалено ровно ничего.** Ни один файл `local-data/SETOS`, репозитория и `~/Library` не удалён, не перемещён и не изменён (GOV-007 запрещает удаление до owner decision, §19 п.8).
- Агентский `/tmp`-скретч (не проектные данные): удалены `gov007/` (32 MB, TSV-таблицы и скрипт этого аудита), `data002-validator.out` (4 KB), `data003-receipt-diff` (28 KB) — прямое разрешение владельца от 2026-09-22 («очищай временные файлы, включая файлы для бенчмарков»). Чужие `/tmp`-файлы (`godot_*`, `urman_*`, `kit_head.glb` и пр.) не атрибутированы проекту и **не** удалялись.

## 6. План архивации/удаления — на отдельное owner decision (§19 п.8)

Кандидаты в порядке выгоды; первые два не требуют git-операций:

| # | Действие | Reclaim | Риск/условие |
|---|---|---:|---|
| 1 | Удалить тела `colab_package_v2_20260914_attempt1…5` + `colab_package` (v1), предварительно сохранив их `package-receipt.json`, `manifest.jsonl` и README в единый `attempts-metadata-20260922.tar.gz` (< 50 MB) в `local-data/SETOS/verification/` | ≈ 13.2 GB | Весь медиа-контент байт-идентичен `research/`/v2 (проверено SHA-256); теряются только структуры каталогов попыток |
| 2 | Xcode-кэши (регенерируемые): `DerivedData/Bonus_Exchange*` 8.0 GB (чужой проект), `iOS DeviceSupport …(24A5430a)` 6.3 GB (beta-символы; пересоздадутся при подключении устройства), симулятор `1F680A42…` 7.5 GB (`xcrun simctl delete`) | ≈ 21 GB | Только потеря времени на пересборку/пересимволизацию;Evidence не затрагивается |
| 3 | `research/synthetic/.../raw/bedroom1_shelf_sim_800.zip` 5.5 GB — удалить, если `download.log` подтверждает воспроизводимую загрузку (проверить перед удалением) | ≈ 5.5 GB | Источник raw-архива; frames/ уже распакованы |
| 4 | `shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf` 1.0 GB (ignored, в bundle не входит) — перенести в `local-data/SETOS` либо удалить как пере-выводимый артефакт SGv9 | ≈ 1.0 GB | Исследовательский GGUF в iOS-репо противоречит политике; пересборка возможна из `docs/SGv9pipeline` |
| 5 | После ML-004 (загрузка v2 package на Drive): удалить локальный `colab_package_v2_20260914/` | ≈ 3.1 GB | Только после подтверждения загрузки и hash-сверки |
| 6 | `.git` 2.2 GB содержит исторические blob'ы (`qwen2.5-1.5b…gguf` 940 MB, SGv7 zip 620 MB, 64/58 MB jsonl) | до ≈ 1.6 GB | Требует rewrite истории — **запрещено без отдельного решения владельца** (hash-bound история); report-only |
| 7 | `docs/SGv7/8pipeline` дублирующиеся 64/58/27/25 MB jsonl-копии (tracked) | ≈ 0.2 GB | Архивация в local-data + git rm; отдельное решение (docs — evidence) |

Суммарный потенциал: ≈ 40 GB, из которых ≈ 13.2 GB (п.1) закрывается чисто и полностью подтверждён hash-группами.

## 7. Воспроизведение

```bash
SETOS=/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS
# 1) перечисление: find <семейства> -type f | xargs stat -f '%z|%N'
# 2) size-парность по семьям, затем SHA-256 коллидирующих файлов ≤ 4 ГиБ (python3 hashlib, Pool(8))
# 3) группировка по (size, sha256); сводка в §3
```
