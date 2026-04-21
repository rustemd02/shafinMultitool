# 42. Colab Iter3 Agent Workflow

Этот файл нужен как agent-memory для `iter3 / iter3.1`, чтобы не забывать, как именно мы работаем с Colab в этом проекте.

Документ описывает не абстрактный пайплайн, а тот practical workflow, который уже использовался в этом репозитории.

## Главный принцип

Для `iter1/iter2` Colab использовался как место, где:
- лежат адаптеры на Google Drive
- есть GPU для training / inference
- ноутбук делает export predictions и benchmark artifacts

Для `iter3.1` нельзя просто "сразу пойти в train", если честный curated corpus ещё не собран.

Поэтому есть два режима:
- `prep-export mode`: Colab только генерирует свежие dual-slice predictions для `dataset_v7 / iter1 / iter2`
- `train mode`: Colab уже обучает `iter3`, но только после того, как готов честный `iter3` corpus

Если corpus ещё не готов, **не надо тащить весь репозиторий в Colab по умолчанию**.

## Что уже выяснено про iter3.1

По текущим локальным артефактам `iter3.1` corpus builder честно валится по quality gate:
- `gate_status = fail`
- `gold_chosen_share_overall` слишком высокий
- `model_chosen_share_overall` слишком низкий

Это означает:
- старых prediction artifacts недостаточно для честного transfer-first `iter3.1`
- сначала нужно получить свежий prep-export
- потом уже строить curated corpus

Именно поэтому текущий рекомендуемый workflow разделён на два этапа.

## Рекомендуемый workflow

### Stage A. Colab prep-export

Цель:
- не обучать ничего нового
- получить свежие dual-slice prediction files для:
  - `dataset_v7`
  - `dataset_v7_orpo_iter1`
  - `dataset_v7_orpo_iter2`

Эти prediction rows обязательно должны содержать:
- `model_only_predicted_script`
- `end_to_end_predicted_script`
- `raw_output_json`

Именно этот prep-export потом используется для сборки честного `iter3.1` corpus.

### Stage B. Local corpus build

После prep-export из Colab агент локально собирает:
- `iter3_delta_sft_train.jsonl`
- `iter3_delta_sft_val.jsonl`
- `iter3_preference_train.jsonl`
- `iter3_preference_val.jsonl`
- `iter3_manifest.json`

Только если `iter3_manifest.json` показывает нормальный corpus, можно переходить к training.

### Stage C. Colab train/eval

После того как corpus уже готов:
- `delta-SFT iter3`
- `ORPO iter3`
- final dual-slice predictions
- final benchmark
- release gate

## Почему не надо сразу тащить repo в Colab

По умолчанию не надо грузить весь репозиторий в Colab, если цель сейчас только:
- получить prep predictions
- потом локально собрать corpus
- потом вернуться в Colab уже с готовыми `jsonl`

Это лучше потому что:
- Colab остаётся простым и предсказуемым
- меньше шансов сломать workflow из-за несовпадения локального кода и ячеек
- build-логика для iter3.1 остаётся в кодовой базе, а не размазывается по notebook

## Что загружать в Google Drive для prep-export

Для текущего prep workflow нужны:
- `sgv7_qwen3_sft_lora`
- `sgv7_eval_runs/adapters/sgv7_qwen3_orpo_lora_iter1`
- `sgv7_eval_runs/adapters/sgv7_qwen3_orpo_lora_iter2`
- `sgv7_eval_runs/eval_bundle_v1`

Для этого этапа не нужен:
- весь репозиторий
- `sgv7_dataset`
- старые train jsonl

## Какие ячейки запускать в qwen_shafin.ipynb для prep-export

Это относится к обновлённому notebook, где уже заменены data / inference / zip-export cells под `iter3 prep`.

Запускать только:
1. `Cell 27`
   Это новый блок `# Данные` с путями:
   - `V7_SFT_ADAPTER_DIR`
   - `V7_ORPO_ITER1_ADAPTER_DIR`
   - `V7_ORPO_ITER2_ADAPTER_DIR`
   - `ITER3_PREP_DIR`
2. `Cell 28`
   Это новый `# Cell 20` с проверкой входных файлов под prep-export.
3. `Cell 29`
   Это `# Cell 21 (self-contained)` с helper functions.
4. `Cell 42`
   Это `# Cell 29`, который грузит eval cases и prompt rendering.
5. `Cell 43`
   Это `# Compat cell for PEFT adapters used at inference`.
6. `Cell 44`
   Это `# Cell 30 (FAST INFERENCE HELPERS, dual-slice prep export)`.
7. `Cell 45`
   Это `# Cell 31 (ITER3 PREP FAST RUN)`.
8. `Cell 46`
   Это `# Cell 32 (CHECK PREP EXPORT)`.
9. `Cell 47`
   Это `# Cell 33 (ZIP PREP EXPORT FOR ITER3.1)`.

Не запускать на этом этапе:
- старый `v6` prep
- старый SFT training
- старый ORPO training
- финальный benchmark config

## Что должно получиться после prep-export

Итоговый артефакт:
- `iter3_prep_pack_seed42.zip`

Внутри него должны быть:
- dual-slice prediction files для `dataset_v7`, `iter1`, `iter2`
- manifest по export

Это **не** готовый `iter3` adapter и **не** готовый `iter3` corpus.

Это только вход для следующего шага: локальной сборки honest `iter3.1` corpus.

## Что делать после prep-export

После получения `iter3_prep_pack_seed42.zip`:
1. передать zip агенту / положить его в workspace
2. локально собрать `iter3` corpus
3. проверить `iter3_manifest.json`
4. только потом идти в Colab для training

Если после prep-export corpus снова fail-closed по quality gate, это не "баг workflow", а сигнал, что текущий transfer signal всё ещё недостаточно хороший.

## Какой GPU выбирать в Colab

Для prep-export:
- `T4` — лучший дешёвый вариант
- `L4` — лучший баланс speed/comfort
- `A100` — обычно избыточен для prep-export

Практическое правило:
- если делаем только export: брать `T4`
- если после этого на той же сессии вероятно будем учить model: брать `L4`

## Известная ловушка в notebook

В notebook уже встречался конфликт сигнатур `write_jsonl`:
- в одной ячейке `write_jsonl(path, rows)`
- в другой фактически использовался вариант `write_jsonl(rows, path)`

Из-за этого `Cell 45` падал с ошибкой:
- `TypeError: expected str, bytes or os.PathLike object, not list`

Правильный фикс:
- в prep inference cell использовать локальный writer, например `write_jsonl_safe(path, rows)`
- не полагаться на глобальный `write_jsonl`, если notebook уже переопределял его в разных ячейках

## Важное правило для будущих итераций

Если снова появляется задача "сделать как раньше в Colab", сначала надо ответить на вопрос:

`У нас уже есть готовый train corpus, или его ещё нужно честно собрать?`

Если corpus уже готов:
- можно идти straight to Colab train/eval

Если corpus ещё не готов:
- сначала prep-export
- потом corpus build
- потом train/eval

Не путать эти два режима.

## Мини-чеклист для агента

Перед тем как советовать пользователю "просто запускай Colab":
- проверить, есть ли уже `iter3_*train/val.jsonl`
- проверить, есть ли валидный `iter3_manifest.json`
- проверить, что prediction files реально dual-slice-aware
- не тянуть repo в Colab без необходимости
- не отправлять пользователя в training, если corpus gate ещё fail

## Связанные файлы

- [training README](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/README.md)
- [iter3 corpus builder](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/11_build_iter3_corpus.py)
- [iter3 release gate](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/12_evaluate_iter3_release_gate.py)
- [benchmark runner](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/run_scientific_benchmark.py)
