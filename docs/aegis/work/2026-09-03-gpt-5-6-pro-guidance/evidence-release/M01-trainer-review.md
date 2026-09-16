# M01 — независимый review пакета production-trainer (маски / loss / augment / resume / честность)

**Дата ревью:** 2026-09-13 (UTC)
**Ревьюер:** независимый агент-ревьюер (read-only по репозиторию)
**Снимок репозитория:** рабочее дерево на момент ревью, ветка `store`.
**Важно:** во время ревью `ml/camera_coach/trainer_records.py` активно правился другим процессом (mtime `2026-09-13 17:20` локального времени). Все выводы ниже привязаны к хэшу, зафиксированному в таблице; см. дефект D3.

---

## Вердикт

**`major`** — ядро масок/loss и воспроизводимость подтверждены независимо, но `hflip` тихо портит horizon-супервизию (аугментация включена в единственном рабочем конфиге), multi-seed resume является тихим no-op, а заявленные хэши больше не соответствуют рабочему дереву. До `verified` требуется исправление D1 и D2 минимум.

Фактически зафиксированные хэши рабочего дерева:

| Файл | Хэш в дереве (ревью) | Хэш из заявления M01 | Совпадает |
|---|---|---|---|
| `ml/camera_coach/data/training_records.py` | `23be0c6896e52c4a72619391e6d7c01742d34a7890691e5d5decd59e53e5d5c9` | тот же | да |
| `ml/camera_coach/models/set_composition_net_v2.py` | `c2725c9e596babac8ed36e073bc9ed91cdbe560c49b5cb4e94a0e62634a654e7` | тот же | да |
| `ml/camera_coach/losses.py` | `c5235ffa3e6534dbbfc719fc8547f55ed985b8a89b96bb734be7b885fea871bd` | тот же | да |
| `ml/camera_coach/train.py` | `9033640f5648f9e007adbe8d7c604d86ed7c46187b9dd57f5b8f684a901d1a27` | тот же | да |
| `ml/camera_coach/tests/test_train_records_v2.py` | `c0dc3fb8d3de24b86402b58000ff954c511d301183d0091b0b01dc9ccd1bffcd` | тот же | да |
| `ml/camera_coach/configs/production_records_smoke.json` | `b27b36992d312dedbf0de6301f7ce38ffee6f58bb9a56a70fcf21e82693939b4` | тот же | да |
| `ml/camera_coach/configs/production_records_smoke.jsonl` | `7a78a80daed3d3d4c6b1ada9092c9abbe57521671af526542a0a3d49428fc384` | тот же | да |
| `ml/camera_coach/trainer_records.py` | `1bb3de9d4d56dcf594039623b4b089077d79af51a9b925425bd5dbd378589192` (1114 строк) | `e2666def32be7d2ca913850b79bd9e53c45370db9d82ca71cb2981d07b3aa7a6` (871 строка) | **нет** |

---

## Таблица проверок

| # | Что проверялось | Чем (команда / скрипт) | Фактический результат | Вывод |
|---|---|---|---|---|
| 1 | Тесты пакета | `python3 -m pytest ml/camera_coach/tests/ -q` | `24 passed` (19 с) на стабилизированном дереве | ok |
| 2 | v1-контракт заморожен | `git status --short` по `set_composition_net_v1.json`, `.schema.json`, `check_parity.py` | пусто; `git diff --stat` пусто | ok |
| 3 | Паритет v1 | `python3 ml/camera_coach/contracts/check_parity.py` | `status=pass`, `contract_version=setcompositionnet.v1` | ok |
| 4 | Smoke CLI и метрики | `python3 -m ml.camera_coach.train --config .../production_records_smoke.json --run-dir /tmp/...` | exit 0; `selected_seed=33`, `selected_validation_loss=4.990053653717041`, `admitted ranking pairs=2`, `data_admission.declared=non_admitted_research` | заявление M01 подтверждено |
| 5 | Детерминизм полного CLI | два независимых прогона, сравнение `model_state_sha256` по seeds | все `model_state_sha256` совпали; `receipt_sha256` различается только из-за абсолютных `run_dir` путей | ok |
| 6 | Запрещённое действие = свой смысл | свой `/tmp/m01-review/focused_probe.py`: `forbidden target 0 / mask 1`, `unknown target 0 / mask 0` | `step_closer 0.0/1.0`, `keep_current_setup 0.0/0.0` | ok |
| 7 | `acceptable ∩ forbidden` падает закрыто | свой `focused_probe.py` | `TrainingRecordError: marks actions both acceptable and forbidden` | ok |
| 8 | Unreviewed catalog ≠ негативы | свой `focused_probe.py`; оба поля `reviewed=false` | `mask sum 0.0`, `target sum 0.0` | ok |
| 9 | Полностью замаскированная голова → ровно 0 loss и 0 grad | свой `probe.py`, по очереди все 8 direct-голов | у каждой `per_head=0`, `count_nonzero(grad)=0` | ok |
| 10 | `null`-дельта не регрессирует к 0 | свой `probe.py`: подмена замаскированной цели на `-0.99` | `per_head delta=0`, `total` идентичен, grad = 0 | ok |
| 11 | Unknown intent глушит intent-головы | свой `probe.py`: `intent_mask=0` | все 4 головы `per_head=0`, `grad=0` | ok |
| 12 | `known=0` + ненулевой style-флаг отвергается | свой `probe.py` + fixture-тест | `ContractError` | ok |
| 13 | Метка intent-головы без intent/ROI падает | свои `probe.py` / `focused_probe.py` | `TrainingRecordError ... not admissible` | ok |
| 14 | hflip трансформирует ROI / направления / delta_x | свой `probe.py`, `focused_probe.py` | ROI зеркалится; `shift_frame_left↔right`, `move_subject_*`, `move_object_*` переразмечены; `delta_x` меняет знак; lateral-скаляры swap/negate/invert | частично ok (см. D1, D4) |
| 15 | Resume: прерывание vs непрерывный прогон | свой `/tmp/m01-review/resume_probe2.py` (ветка `train_one_seed` **и** CLI-путь `run_from_config`) | CLI-resume: `start_epoch=2`, history `[1,2]`, `max |continuous_best − resumed_best| = 0.0`, train/val loss эпох совпали точно | ok |
| 16 | Полнота чекпойнта | загрузка `checkpoint.pt` | есть `model/optimizer/scheduler/sampler`, `torch_rng_state`, `python_rng_state`, `cuda_rng_state_all`, `best`, `history` | ok |
| 17 | Атомарность записи чекпойнта | чтение `_atomic_save_checkpoint` | `torch.save` во временный файл + `os.replace`; `fsync` отсутствует | низкий риск (D6) |
| 18 | Модель/загрузчик готовы к `intent_features`, Swift — нет | `rg` по `shafinMultitool/**/*.swift`; парсинг `model.mlpackage` через coremltools | в Swift 0 вхождений `intent_features`/`CaptureIntent`; отгруженный Core ML артефакт — 6 входов (без intent); v2-модель имеет 7 входов | подтверждено, релиз-заявлений нет |
| 19 | Нет заявления об обучении на admitted | `rg` по receipt/отчёту/`INTEGRATION.md` | receipt: `non_admitted_research`; `INTEGRATION.md`: `research_only/human_gold/release_admissible = false`; отчёт: admitted = 0 | ok |
| 20 | v1-манифест нельзя выдать за v2 | тест `test_v1_checkpoint_cannot_be_declared_v2` | pass | ok |

---

## Найденные дефекты

### D1 — `major` (тихая порча супервизии): hflip не зеркалит `horizon_delta` и `horizon_angle`

- **Файлы/строки:**
  - `ml/camera_coach/data/training_records.py:86` — таблица `_LATERAL_SCALAR_TRANSFORMS` не содержит `horizon_angle`;
  - `ml/camera_coach/data/training_records.py:751-769` — `apply_horizontal_flip` меняет знак только у `delta_x` (`delta_names.index("delta_x")`), `horizon_delta` не трогает.
- **Почему это дефект:** замороженная семантика дельт задаёт `horizon_delta` как знаковый угол коррекции: `datasets/camera-coach/v1/silver-action-pair-schema.json` (`x-semantics.horizon_delta = "required scene correction degrees / 180; derivative +theta maps to -theta/180"`), тот же контракт в `tools/dataset/generate_camera_corruptions.py:87`, а генератор серебра пишет `horizon_delta = -actual_tilt / 180.0` (`generate_camera_corruptions.py:1233`). Горизонтальное зеркало меняет знак угла наклона (roll), следовательно `horizon_delta` обязан менять знак. То же для скалярного входа `horizon_angle` (нормализация `angle_degrees_to_unit`, знаковый).
- **Воспроизведение (реально выполнено):**
  ```bash
  cd /Users/unterlantas/Documents/XCode/shafinMultitool
  python3 - <<'PY'
  import sys; sys.path.insert(0,'.')
  from ml.camera_coach.data.training_records import load_records, apply_horizontal_flip
  from ml.camera_coach.models.set_composition_net_v2 import SETCompositionNetV2Manifest
  C=SETCompositionNetV2Manifest.load()
  D=list(C.output_head_specs['continuous_target_deltas']['ordered_names'])
  r=[x for x in load_records('ml/camera_coach/configs/production_records_smoke.jsonl') if x.record_id=='cam-smoke-t05'][0]
  f=apply_horizontal_flip(r,C); i=D.index('horizon_delta'); j=D.index('delta_x')
  print('delta_x      ', r.targets['continuous_target_deltas'][j].item(), '->', f.targets['continuous_target_deltas'][j].item())
  print('horizon_delta', r.targets['continuous_target_deltas'][i].item(), '->', f.targets['continuous_target_deltas'][i].item(), 'mask', f.masks['continuous_target_deltas'][i].item())
  PY
  ```
  Фактический вывод: `delta_x 0.0 -> -0.0`, но `horizon_delta 0.05 -> 0.05 (mask 1.0)`.
- **Серьёзность:** высокая. `augmentation.horizontal_flip=true` в `production_records_smoke.json`, то есть в единственном запускаемом production-конфиге. Для любого перевёрнутого сэмпла с меткой `horizon_delta` (и с ненулевым `horizon_angle`) модель обучается на неверном знаке; ошибка не видна ни в loss-логах, ни в тестах (в тестовом `_base_record` все дельты/скаляры `None`). Это ровно тот «тихий» класс ошибок маски/метки, ради которого делается ревью.

### D2 — `major` (тихий no-op): multi-seed + `resume_from` молча игнорируется

- **Файл/строки:** `ml/camera_coach/trainer_records.py:1020-1022`
  ```python
  resume_from = None
  if config.resume_from is not None and len(config.seeds) == 1:
      resume_from = Path(config.resume_from).expanduser().resolve()
  ```
- **Почему это дефект:** если конфиг задаёт `resume_from` и более одного seed, `run_records_training` не падает и не предупреждает — он просто запускает обучение с нуля. Receipt при этом возвращает `status="pass"`, а `config.resume_from` остаётся в `config.json`/receipt. Пользователь считает, что продолжил прерванный прогон, фактически получая другой прогон. Это нарушает заявленную воспроизводимость.
- **Воспроизведение (реально выполнено):** `/tmp/m01-review/resume_probe2.py`, конфиг с `seeds=[7,8]`, `epochs=1`, `resume_from=<checkpoint>`:
  ```
  multi-seed+resume_from: status pass start_epochs [1, 1] resume_lineages [None, None]
  ```
- **Серьёзность:** высокая. Достаточно `ConfigError`, если `resume_from` задан при `len(seeds) != 1` (fail-closed), либо честного per-seed resume. Сейчас — молчаливое расхождение с заявленным поведением.

### D3 — `medium` (непроверяемость / процесс): рабочее дерево разошлось с заявленными хэшами; файл под активной правкой

- **Файл/строка:** `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/EXECUTION_STATE.md:2637` приписывает `trainer_records.py` хэш `e2666def…` (871 строка). В дереве на ревью — `1bb3de9d…` (1114 строк). `ml/camera_coach/trainer_records.py` вообще **untracked** (`git status`: `??`), то есть заявленный хэш не соответствует ни одному закоммиченному артефакту.
- **Почему это дефект:** во время ревью файл менялся другим процессом (в 14:20 UTC в дереве были состояния `d4c844…`, `fddbea…`, `1bb3de9…` подряд; промежуточное состояние было **нерабочим** — `_batch_loss() missing 1 required keyword-only argument: 'device'`, и `pytest` давал 2 failed). Стабильная версия добавлена без обновления `tests/test_train_records_v2.py` (его хэш не менялся): новый код device/CUDA/Colab/resume-semantics не покрыт тестами пакета. Мой CLI-resume тест (D-таблица #15) — единственная проверка нового `resume_semantic_sha256`.
- **Воспроизведение:** `shasum -a 256 ml/camera_coach/trainer_records.py` (текущее значение не совпадёт с `e2666def…`); `git status --short ml/camera_coach/trainer_records.py` → `??`.
- **Серьёзность:** средняя как дефект кода, но **блокирующая для `verified`**: нельзя подтвердить пакет по изменяющемуся непокоммиченному файлу. Нужно закоммитить (или иначе заморозить) снимок и обновить хэш-таблицу отчёта.

### D4 — `medium/low`: `_flip_scalars` игнорирует `missing_feature_mask` и «оживляет» отсутствующие признаки

- **Файл/строки:** `ml/camera_coach/data/training_records.py:707-730` (`_flip_scalars` не читает `record.missing_feature_mask`).
- **Почему это дефект:** манифест v2 (`inputs.scalar_features.missing_mask`) требует `fill_value=0.0` для отсутствующих признаков. При маске «missing=1, value=0» flip инвертирует значение как присутствующее: `mirroring_flag 0→1` (`invert`), `subject_bbox_x 0→1` (`mirror_x = 1−x−w`). В модели скалярная ветка видит «отсутствующий» признак с ненулевым значением, что противоречит контракту trust boundary.
- **Воспроизведение (реально выполнено):** свой `probe`-скрипт с записью, где `missing_feature_mask` помечает `subject_bbox_x`/`mirroring_flag` отсутствующими:
  ```
  subject_bbox_x  value +0.0 mask 1 -> flipped value +1.0
  mirroring_flag  value +0.0 mask 1 -> flipped value +1.0
  ```
  (в smoke-записи `cam-smoke-t06` `scalar_features` есть, но `missing_feature_mask=None`, и все значения нулевые — flip даёт `subject_bbox_x 0→1.0` при `width 0`.)
- **Серьёзность:** средняя/низкая (условна на использование `missing_feature_mask` продюсером D02b; в текущем smoke-бандле маски отсутствуют). Исправление: не трансформировать признаки с `missing==1` либо принудительно обнулять их после flip.

### D5 — `low`: `output_root` входит в `resume_semantic_sha256`, хотя это оркестрация

- **Файл/строка:** `ml/camera_coach/trainer_records.py:494` (`"output_root": config.output_root` внутри `resume_semantic_sha256`).
- **Почему это дефект:** `output_root` не влияет на обучение (используется только когда не передан `--run-dir`), но смена `output_root` делает чекпойнт «несовместимым» для resume. Подтверждено: `resume with changed output_root FAILED: checkpoint semantics ... do not match`.
- **Серьёзность:** низкая (обход — не менять `output_root`).

### D6 — `low`: атомарная запись чекпойнта без `fsync`; проверка ROI-инволюции вакуумна

- `ml/camera_coach/trainer_records.py:437-440` — `torch.save` в `.tmp` + `os.replace` без `fsync`/`fsync` каталога. Целевой файл не бывает «половинчатым» (rename атомарен), но при потере питания результат rename/содержимое не гарантированы. `_atomic_write_json` (строки 427-434) `fsync` делает, чекпойнт — нет.
- `ml/camera_coach/data/training_records.py:701` — `abs(1.0 - mirrored_x - width - x) > 1e-9` алгебраически тождественно 0 при любом ROI, т.е. ветка «requires_reannotation» недостижима. Заявление в docstring о проверке инволюции не соответствует коду.
- **Серьёзность:** низкая.

### D7 — `low`: при early-stop чекпойнт не пишется для остановившейся эпохи

- **Файл/строки:** `ml/camera_coach/trainer_records.py:833-835` (`break` до `_atomic_save_checkpoint`).
- **Почему:** `checkpoint.pt` остаётся на предыдущей эпохе, хотя `history` уже содержит эпоху early-stop. На resume эпоха переиграется; так как всё детерминировано, результат тот же. Дефект косметический/надёжностный, не нарушает воспроизводимость.

---

## Что НЕ проверено и почему

- **Обучение на admitted-данных** — admitted-записей 0 (`data_admission.declared=non_admitted_research`); полный human fit невозможен по объективной причине, это `blocked_external`, а не дефект.
- **CUDA-путь** (`runtime_profile=colab_installed_runtime`, `device=cuda`, `_assert_actually_on_device`, `cuda_rng_state_all`) — на машине ревью нет GPU. Проверено только чтением кода; тестов пакета на этот путь нет (D3).
- **Core ML / on-device паритет v2** — v2 не экспортируется (`convert_coreml.py` не содержит `intent`/v2), в бандл отгружен 6-входовой research-артефакт. Паритетv2 не проверялся.
- **Качество/сходимость** — не является частью M01 (`no quality claim`), не проверялось.
- **Swift-сторона `CaptureIntent`** — её нет; проверено статически (`rg` = 0 вхождений), динамически подать intent из приложения невозможно.
- **Contrastive-пары** — поддержаны в loss, но продюсера пар нет; end-to-end не проверялись.
- **Финальность хэша `trainer_records.py`** — на момент отчёта хэш `1bb3de9d…` стабилен ~3 минуты, но другой процесс может продолжить правку; гарантий финальности нет.

---

## Какие заявления M01 подтверждены независимо, а какие остаются на слово

**Подтверждены независимо (моими прогонами/скриптами):**
- 24 теста проходят; `check_parity.py` → `status=pass`, v1-манифест/схема/скрипт не изменены (`git` пуст).
- Smoke CLI воспроизводит заявленные метрики: `selected_seed=33`, `val_loss=4.990053653717041`, `admitted ranking pairs=2`, `non_admitted_research`.
- Полная попрогонная детерминированность: два прогона дают одинаковые `model_state_sha256`.
- Resume «прерывание vs непрерывно»: максимум расхождения параметров `0.0`; чекпойнт несёт optimizer/scheduler/sampler/RNG; sampler state round-trip.
- Отсутствие меток не становится негативом; `forbidden` = `0/mask1`; `acceptable∩forbidden` падает закрыто; `unknown intent` глушит 4 головы (ровно 0 loss и 0 grad); `null`-дельта не регрессирует; полностью замаскированная голова даёт ровно 0 loss и нулевой градиент — **воспроизведено мной**, а не прочитано из теста.
- v2-модель/загрузчик принимают `intent_features` (7-й вход), Swift его не подаёт (0 вхождений), отгруженный Core ML — 6-входовой research-артефакт; релиз-заявлений нет.

**Остаются на слово исполнителя (не проверял):**
- Поведение на реальном admitted-корпусе и на CUDA/Colab (нет данных/железа).
- Будущая замена `dataset.*` на admitted и «меняются только dataset/seeds/epochs» — по коду правдоподобно, но не исполнялось.
- Заявления о `peak_vram_bytes`/device-профиле — не проверялись.
- Любые quality/benchmark-заявления — их M01 и не делает.

---

## Что требует исправления до `verified`

1. **D1 (обязательно):** добавить `horizon_angle` в `_LATERAL_SCALAR_TRANSFORMS` как `negate` и инвертировать знак `continuous_target_deltas[horizon_delta]` в `apply_horizontal_flip`; добавить регрессионный тест, который переворачивает запись с ненулевыми `horizon_delta`/`horizon_angle` и проверяет смену знака (сейчас такого теста нет — тестовые записи держат скаляры/дельты `None`).
2. **D2 (обязательно):** запретить (fail-closed) или корректно поддержать `resume_from` при `len(seeds) > 1`.
3. **D3 (обязательно для `verified`):** заморозить/закоммитить `trainer_records.py`, обновить хэш-таблицу отчёта M01 и добавить тесты на новый device/profile/resume-semantic путь (или явно вынести его в отдельный пакет).
4. **D4 (желательно):** уважать `missing_feature_mask` во flip (не оживлять отсутствующие признаки).
5. **D5–D7 (желательно):** убрать `output_root` из resume-semantics; добавить `fsync` чекпойнта; убрать/исправить вакуумную проверку ROI-инволюции; сохранять чекпойнт при early-stop.

---

## Точечная перепроверка D1–D5 (2026-09-13, после исправлений)

Снимок зафиксирован по хэшам; все заявленные хэши сверены `shasum -a 256` и совпали:
`training_records.py = 32fa1280…`, `trainer_records.py = f138aa3c…`, `tests/test_train_records_v2.py = 5cf2ff39…`, `train.py = 9033640f…` (**не менялся**). M02-файлы (`preflight_records_run.py e04bce73…`, `configs/production_records_colab.json de611e10…`, `colab/SET_OS_Camera_Coach_Records.ipynb 874b0115…`, `colab/README_RECORDS.md 4ff98b1f…`, `tools/dataset/package_camera_colab.py 09676155…`) — хэши совпали; это M02-объём, проверялся только на отсутствие регрессий M01.

| Пункт | Статус | Независимое подтверждение |
|---|---|---|
| **D1** horizon | **закрыт** | `training_records.py:86-97` — `horizon_angle: ("negate", None)`; `:773-790` — цикл негации `delta_x` **и** `horizon_delta`. На `cam-smoke-t05`: `horizon_delta 0.05 → -0.05`, маска `1→1`; `delta_y/scale_delta/light_delta` инвариантны; flip — инволюция по дельтам и по `horizon_angle`. |
| **D2** multi-seed resume | **закрыт** | `trainer_records.py:326-333` — `ConfigError` при `resume_from` и `len(seeds)!=1`. Проверено через `from_mapping` и через `run_from_config`; single-seed+`resume_from` по-прежнему принимается (over-blocking нет). |
| **D3** заморозка/тесты | **закрыт на уровне снимка** | 24→**31 passed**; добавлены 7 не-тавтологичных тестов: horizon-знак и инволюция, missing-скаляры, «swap только при присутствующем партнёре», multi-seed resume через entrypoint, `resume_semantic` игнорирует orchestration-поля, Colab-профиль/lock. Остаточное условие (ниже): файлы всё ещё untracked, коммита нет. |
| **D4** missing-скаляры | **закрыт** | `training_records.py:710-750` — `is_missing` пропускает отсутствующие; `mirror_x`/`swap` отказываются при отсутствующем партнёре; маска не меняется. Проверено на записи с `missing=1` на `subject_bbox_x`/`mirroring_flag`/`horizon_angle`: значения остаются `0.0`. |
| **D5** `output_root` | **закрыт** | `trainer_records.py:456-505` — `output_root`/`resume_from` исключены из `resume_semantic_sha256`, `device`/`runtime_profile`/`torch_version` остаются. Проверено равенством/неравенством хэшей и успешным resume в другой `output_root`. |

### Причина смены smoke-метрики (проверена каузально, регрессии нет)

`selected_validation_loss` изменился `4.990053653717041 → 4.990816116333008` **только из-за D1**, и это не регрессия loss/данных:
- перевёртыш `_stable_flip` для `seed 33` включает `cam-smoke-t05` (единственная train-запись с `horizon_delta=0.05`) в эпохах 1 и 2; для `seeds 11/22` t05 не переворачивается;
- новые метрики seed 11 `5.039989948272705` и seed 22 `5.011044979095459` **бит-в-бит совпадают** со старым прогоном; изменился только seed 33;
- обратный эксперимент: monkeypatch, возвращающий только старое поведение горизонта (в остальном код и данные новые), даёт `seed 33 = 4.990053653717041` и те же значения seeds 11/22. То есть старая цифра измерялась под багом знака, новая — корректная.

### Регрессии от правок

**Новых дефектов не найдено.** Повторно прогнаны прежние адверсариальные проверки на новом коде: полностью замаскированная голова даёт ровно `0` loss и `0` grad по всем 8 головам; `null`-дельта не регрессирует (подмена цели не меняет total); unknown intent глушит все 4 intent-головы; `forbidden` = `0/mask1`, `unreviewed` = все маски 0; `acceptable∩forbidden` падает закрыто; CLI-resume остаётся бит-точным (`max |Δ| = 0.0`, `start_epoch=2`), чекпойнт несёт optimizer/scheduler/sampler/оба RNG. Проверено, что негация горизонта не задела другие знаковые оси (вертикаль/крупность/свет инвариантны) и что `missing_feature_mask` не теряется ни в одной ветке flip (`replace` его не трогает).

Остаточные (не блокирующие) наблюдения:
- `_flip_scalars` при отсутствующем партнёре оставляет присутствующий латеральный признак непреобразованным (fail-safe, без фабрикации значения) — осознанный компромисс, тест на него есть;
- CUDA/Colab-путь (`_assert_actually_on_device`, `cuda_rng_state_all`, `CUBLAS_WORKSPACE_CONFIG`) по-прежнему не исполнялся: GPU на машине ревью нет; тесты пакета покрывают только парсинг профиля/конфига, не сам GPU-прогон.

### Ответы

1. **D1–D5 закрыты** (см. таблицу). Ни одного открытого пункта из D1–D5 не осталось; D3 закрыт в смысле «хэш-снимок совпадает», с оговоркой о коммите ниже.
2. **Новых дефектов от правок нет**; перечисленные регрессионные проверки пройдены.
3. **M01 можно переводить в `verified` для пути CPU/`pinned_local`.** Минимальное условие — закоммитить или иначе заархивировать ровно этот снимок: все M01/M02-файлы сейчас `??` (untracked), поэтому пинованные хэши не имеют durable-референта, а отчёт M01 всё ещё содержит старую строку `trainer_records.py = e2666def…` — её нужно заменить на `f138aa3c…`. GPU/Colab-путь остаётся **неверифицированным** и должен быть явно исключён из scope `verified` (это M02-предмет).
4. **D6/D7 остаются вне обязательного условия.** `os.replace` действительно не оставляет половинчатого `checkpoint.pt` (атомарность целевого файла), недостаёт лишь `fsync` (durability), а ранний early-stop компенсируется детерминированным replay — обе проблемы не влияют на воспроизводимость метрик и не блокируют `verified`. Обязательным из «желательного» не является ни один пункт; `fsync` чекпойнта — самый полезный из необязательных.
