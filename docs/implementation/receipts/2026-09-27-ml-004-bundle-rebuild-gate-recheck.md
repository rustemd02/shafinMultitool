# ML-004 — пересборка Colab-бандла и повторная проверка human-gold гейта (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `fc41e0e5` · Ветка: `store`
Задача: **ML-004** (закрытие строки; база — ресипты `2026-09-23-ml-004-colab-bundle-prep.md`
и `2026-09-27-ml-004-gate-and-pin-refresh.md`)

## 1. Пересборка бандла (реальный прогон этого запуска)

`python3 ml/camera_coach/colab_bundle/build_bundle.py --output-dir
local-data/SETOS/verification/colab-bundle-20260927 --full-verify`:

| Параметр | Значение |
|---|---|
| Артефакт | `camera-coach-ml004-colab-bundle-20260927T214125+0000.tar.gz` |
| SHA-256 | `3f5d554a69b932b7f93410144fb053eea7f8a7a1b9be52fe6fff5d9782617ec8` |
| data_manifest rows | **12 449** (pin `queue-v2-diverse` sha `dd47f199…` — сохранён с прошлого refresh) |
| Код (hash-pinned) | **18 файлов** |
| human-gold слот | **`awaiting_owner`** (пустой, fail-closed) |

Хранение — backend local-data (не Git и не Xcode bundle).

## 2. Гейты (команды и exit-коды этого запуска)

Preflight выполнялся локально с bridge-корнем
(`scratchpad/drive-root-bridge/SETOS/camera-coach → local-data/SETOS/Datasets/camera-coach`),
потому что pinned Drive-пути манифеста (`SETOS/camera-coach/…`) отличаются от
локального post-relocation layout (`SETOS/Datasets/camera-coach/…`) — сам
bridge сделан симлинком, данные не двигались.

| Check | Команда | Итог |
|---|---|---|
| Preflight data/code | `check_environment.py --mode dry_run --bundle-root <extracted> --drive-root <bridge>` | **EXIT=0**: code hashes 18/18 verified; data files 200 verified (sample 200 of 12 448 pinned rows), 0 missing / 0 hash mismatched |
| Human-gold gate | `check_environment.py --mode final_fit …` | **EXIT=3**, `decision: refused_no_human_labels` (rows 0, human_gold_rows 0) — silver никогда не проходит как gold |

## 3. Что осталось внешним (точно)

1. **Google Drive upload** — `rclone` в среде **не установлен**
   (`rclone: command not found`), remotes не настроены; загрузка требует
   входа в Google-аккаунт владельца (внешний аккаунт). Готовая команда —
   README бандла §2 (copy + check, без sync/delete); бандл лежит по пути §1.
2. **Colab runtime preflight/train** — требует входа в Colab (внешний аккаунт)
   и GPU-рантайма; ноутбук-шаблон `colab_training_template.ipynb` готов,
   последовательность ячеек preflight → verify → smoke → train описана в нём.
3. **Наполнение human-gold слота** — контракт-валидные adjudicated-записи
   (origin=`human_adjudication`, ≥2 review id, `adjudicator_id`,
   `human_gold=true`) появятся после разметки/адjudication DATA-008/010/011.
   **В этом запуске разметка не выполнена:** инструмент канала изображений
   начал отдавать устаревший образ вместо файлов (контрольные пробы:
   `probe-magenta` 300×200 → вернул UI-скриншот; `probe3-outline` → корректно;
   `sheet-01.png` ×5 → stale), и маркировать кадры вслепую запрещено правилами
   честности данных. Гейт остаётся fail-closed, что и проверено выше.

## 4. Статус

ML-004 → **`DONE`**: Done-when строки (reproducible training bundle: pinned
code/config/data hashes, resume, Drive paths, receipts) выполнен и
перепроверен в этом запуске; human-gold гейт доказан fail-closed на реальных
exit-кодах. Остатки строки — исполнение на внешних сервисах (Drive/Colab) и
данные human-разметки — перечислены в §3 и принадлежат строкам DATA-008/010/011
и внешнему доступу владельца.
