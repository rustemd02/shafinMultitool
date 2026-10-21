# ML-004 Colab bundle — Camera Coach production heads (human-gold gated)

Подготовительный слайс **ML-004** (reproducible Colab training bundle). Данные не финальны by design: human-gold разметки ещё нет (pilot-100 ждёт владельца, DATA-008), полный корпус — DATA-016. Бандл готов так, чтобы когда разметка появится, сборка → загрузка → preflight были минимальным числом команд.

Границы: бандл пиннит **код и метаданные**. Raw media, silver-деривативы и human labels в бандл **не копируются никогда** — они едут через Google Drive, а `data_manifest.jsonl` пиннит `content_sha256` каждого файла. Preflight на Colab сверяет хеши до старта обучения.

## 1. Когда разметка готова — как собрать бандл

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool
python3 ml/camera_coach/colab_bundle/build_bundle.py \
  --output-dir /tmp/setos-colab-bundle \
  --full-verify          # перед первым upload: хеширует ВСЕ данные (~3.3 ГБ); для быстрых пересборок уберите
```

Вывод: `/tmp/setos-colab-bundle/camera-coach-ml004-colab-bundle-<stamp>.tar.gz` + его SHA-256 (записать в receipt). Внутри:

- `bundle/` — хешируемое замыкание кода: `production_heads.py` (layout + masked losses), `losses.py`, `train_silver_actions.py` / `evaluate_silver_pairs.py` / `generate_camera_corruptions.py` (проверенный Colab-fit паттерн), контракты ML-002 (heads contract + label schema + capability mapping) с валидаторами и fixture;
- `config.json` — pinned: ширины голов (1/15/26/5/1/1), masked-loss параметры, seed 20260923 (+2 seeds для variance-check ML-009), resume-интервал 200 шагов на Drive;
- `data_manifest.jsonl` — построчные пины: v2-пакет (11 810 кадров), silver pairs (636 + деривативы), и **пустой слот `human_labels_dir`** (`status=awaiting_owner`; expected: pilot-100 `labels.jsonl`, queue sha `cbb55e63…`, + будущие DATA-013 episodes);
- `check_environment.py` — preflight (см. §4);
- `colab_training_template.ipynb`, `bundle-receipt.json` (все хеши сборки), `README_BUNDLE.md`.

Пересборка после изменения кода = новая сборка, не патч бандла: hash drift → rebuild.

## 2. Как загрузить на Drive

Целевая структура `MyDrive/SETOS/` (плейсхолдеры из `data_manifest.jsonl`):

```
MyDrive/SETOS/
  camera-coach/colab_package_v2_20260914/   # frames/ + manifest.jsonl + package-receipt.json
  camera-coach/silver-fit-20260918/pairs/   # pairs.jsonl + receipt.json + images/
  annotation/pilot-20260923-strata-v1/labels.jsonl   # когда появится
  runs/ml004/                               # создаст ноутбук: checkpoints, receipts.jsonl
```

Референс практик (из архива `local-data/SETOS/verification/attempts-metadata-20260923.tar.gz`, `colab_package/README.md`): **copy + check, без sync/delete/перезаписи различающихся файлов**.

- **rclone (рекомендуется для ~3.3 ГБ):** `rclone config` (remote `gdrive`, тип drive, OAuth в браузере, scope — осознанно подтвердить), затем
  `rclone copy --immutable <локальный каталог> gdrive:SETOS/camera-coach/<каталог>` и после — `rclone check --one-way`. Повторный запуск докачивает недостающее; различающиеся файлы не перезаписываются.
- **Вариант без rclone:** перетащить каталог в браузере Drive (медленнее, мелкие файлы) или `gdown`/Drive UI для единичного tar.gz. Крупные данные по-файлово не заливать браузером.
- Перед загрузкой запустить `build_bundle.py --full-verify`; после загрузки preflight на Colab (§4) повторно сверит хеши — это и есть защита от битого upload'а.

## 3. Colab Pro: что даёт и какие настройки

- Runtime → Change runtime type → **GPU**: A100 (40 ГБ, быстро) или T4 (16 ГБ, дешевле; достаточно для smoke и небольшого корпуса). High-RAM при работе с полным пакетом кадров.
- torch предустановлен в Colab — **не** ставить macOS `requirements.lock` в Colab (он pinит darwin/arm64). Preflight проверит `torch >= 2.4` и наличие GPU.
- Много мелких файлов с Drive читать медленно: после проверки хешей скопируйте кадры в локальный `/content` SSD (ячейка 3 содержит подсказку).
- Free-рантаймы отключаются: поэтому чекпоинты каждые 200 шагов атомарно пишутся на Drive (`runs/ml004/checkpoints`, keep_last_k=3) и обучение возобновляется с последнего чекпоинта.

## 4. Порядок работы на Colab

1. Распаковать tar.gz в `/content/camera-coach-ml004-colab-bundle`.
2. Открыть `colab_training_template.ipynb`, ячейки по порядку: preflight (`check_environment.py --mode dry_run`) → mount Drive → verify hashes (`--full`) → smoke (синтетический мини-батч, masked losses, backward — работает уже сейчас) → full train → eval → export → receipts.
3. Preflight **fail-closed**: без `human_gold=true` меток разрешены только `dry_run`/`smoke`; `final_fit` завершится exit 3. Gate также валидирует каждый envelope контрактом `camera_release_label_v1`.

## 5. Правила (не нарушать)

- **Locked test не трогать до ML-008.** В этом ноутбуке его нет и монтировать его нельзя; eval — только validation, метрики per-head (не средняя accuracy).
- **Silver ≠ gold.** Пакет v2 и silver pairs — `research_only=true`, `human_gold=false`. Финальный fit — только на adjudicated human-gold (DATA-010/011); ни одна proposal/teacher-подсказка не становится меткой.
- **Резюмируемость.** Никакого обучения без resume-чекпоинтов на Drive; ноутбук пишет прогресс в `runs/ml004/receipts.jsonl` (хеши бандла, конфиг, метрики).
- Temporal головы — `deferred_to_ML_011`; still-scorer экспорт (ML-012) от них не зависит.
- Старые attempt1…5/v1 пакеты удалены владельцем; их upload/verify практики сохранены в архиве `attempts-metadata-20260923.tar.gz` (метаданные + README), новых копий данных не создавать.

## Статус

`prepared_not_trained`: human-gold слот пуст; сборка, preflight и smoke-путь проверены локально (см. receipt `docs/implementation/receipts/2026-09-23-ml-004-colab-bundle-prep.md`).
