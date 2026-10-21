# Storage cleanup — исполненное удаление по решению владельца

Дата: 2026-09-23. Основание: прямое разрешение владельца («удаляй») на пункт 1 плана `receipts/2026-09-22-gov-007-storage-audit.md` §6 + Xcode-кэши с явным исключением `Bonus_Exchange` («bonus_exchange не трогай»).

## Полная верификация перед удалением (content-level, не выборочная)

- Хешировано SHA-256: 85 880 файлов-кандидатов (`research/` + финальный v2) → 52 540 уникальных хешей-эталонов; 61 772 файла в шести удаляемых каталогах.
- Результат: **13.12 GB из 13.31 GB (98.59%) — байт-идентичные дубликаты** эталонов; уникальны 46 файлов на 187.6 MB — манифесты попыток и мелкие metadata ( ровно то, что план предписывал сохранить).
- Любой крупный недубликат вёл к автоматической отмене удаления (abort-ветка; срабатывала корректно на первом прогоне до перестройки порядка — список уникальных пишется до решения).

## Архив манифестов

`local-data/SETOS/verification/attempts-metadata-20260923.tar.gz`
- 14 MB, 46 файлов, gzip-целостность OK, SHA-256 `84baeb309f2a738414abe1bebc284e9def5fa3a65db6fac9d4c206f0a993d985`.
- Содержит: `manifest.jsonl` всех шести пакетов (v1 + attempts 1–5), package-receipt.json, README, deduplication/qc-exclusions/similarity-candidates/temporal.jsonl, скрипты verify_package.py / upload_to_drive.sh — исторические ресипты сохранены с исходными байтами и путями.

## Удалено

| Путь (под `local-data/SETOS/Datasets/camera-coach/`) | du до |
|---|---:|
| `colab_package/` (v1) | 756 MB |
| `colab_package_v2_20260914_attempt1_frame_name_collision_preserved/` | 1.4 GB |
| `…_attempt2_paired_dedup_preserved/` | 2.5 GB |
| `…_attempt3_sequence_qc_preserved/` | 2.6 GB |
| `…_attempt4_temporal_dedup_preserved/` | 2.6 GB |
| `…_attempt5_scenetrans_id_collision_preserved/` | 2.6 GB |
| **Итого media-дубликаты** | **≈ 12.4 GiB du / 13.31 GB logical (13.12 GB — дубликаты)** |

## Удалено вне local-data (по тому же разрешению, с исключением Bonus_Exchange)

- `~/Library/Developer/Xcode/iOS DeviceSupport/iPhone14,2 27.0 (24A5430a)/` — 6.3 GB символов beta-сборки iOS 27.0 (24A435 release-копия сохранена; при подключении устройства на beta символы пересоздадутся Xcode автоматически).

## Не тронуто (явные исключения)

- `~/Library/Developer/Xcode/DerivedData/Bonus_Exchange*` (8.0 GB) — **запрет владельца**.
- Симулятор `1F680A42…` (7.5 GB) — основной pinned-тестовый девайс (destination матрицы REL-001 и required_check).
- `bedroom1_shelf_sim_800.zip` (5.5 GB) — raw-источник, не дубликат; отдельное решение (п.3 плана GOV-007, требует проверки воспроизводимости загрузки).
- `Resources/Models/*.gguf` (1.0 GB), v2 package (3.1 GB, нужен для ML-004), `.git` history — по плану не входят в пункт 1.

## Итог

- Свободное место: **61 GiB → 80 GiB (+19 GiB)**.
- `local-data/SETOS`: 37 GB → **25 GB**.
- Все hash-bound ресипты нетронуты; GOV-007 ресипт не переписывался (это отдельная запись-дополнение).
