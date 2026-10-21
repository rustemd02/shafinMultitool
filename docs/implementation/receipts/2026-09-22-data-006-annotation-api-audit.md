# DATA-006 — Annotation API audit: vision payload, structured output, retries/backoff, ZDR, secrets

Дата: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`.
Границы: только сторона репо (`tools/camera_annotation/**`, кроме `release_label_adapter.py`).
Каталог `commandcode/` (локальная утилита, в .gitignore) не открывался и не запускался — зафиксировано только поведение со стороны вызова (`language_review.command_api` → `https://api.commandcode.ai/provider/v1/`). Сетевых вызовов в задаче не было; весь транспорт в тестах замокан.

## Аудит по 4 пунктам

### (a) Vision payload / structured output validation — invalid/partial JSON не записывается

- **Command Code (`language_review.py`, visual + language пути)** — PASS. `json.loads(content)` → `validate_visual` / `validate` (структурная проверка по живому `output_schema()`: точное множество ключей, enum-словари, maxItems, null-допустимость; семантика; quote-binding к human-тексту) выполняются **до** записи `visual_proposal`/`proposal` в журнал. `confirm`/`confirm_visual` ревалидируют перед подтверждением. Ошибка → только `visual_error`/`error`-событие (имя класса исключения + public-текст), `interpretation` не персистится. Валидный JSON проходит путь (негативные + позитивный контроль в тестах).
- **Teacher/Polza (`review_pipeline.py`)** — GAP, исправлен. `validate_proposal` был рукописным и не сверялся с wire-схемой `proposal_schema()` (та же схема, что отправляется провайдеру и чей sha256 пишется в `config.json`). Конкретный дрейф: `actions maxItems=2` из схемы локально не проверялся — 3 различных допустимых действия с subject-ROI проходили все hand-checks и `validate_label`. Исправление: `schema_violation(value, schema)` — строгий локальный валидатор по JSON-Schema-подмножеству схемы (типы без bool-as-number, enum, required, additionalProperties=false, min/maxItems, min/maximum, отказ NaN/Infinity, которые `json.loads` допускает по умолчанию), вызывается **первым** в `validate_proposal` — покрывает и `teacher` (до `accepted=True`), и `assemble` (ревалидация перед сборкой очереди).

Инвариант «invalid/partial не становится gold» выполнён на обоих путях: proposal-события пишутся только после валидации; все артефакты несут `research_only=true, human_gold=false, release_admissible=false`; подтверждение — только человеком.

### (b) Retries/backoff — существуют и ограничены

- Платные вызовы (`chat/completions`) на обоих транспортах **намеренно не ретраятся** (после транспортного сбоя billing state неизвестен; повторная отправка может списать бюджет дважды; у Polza это прямо закомментировано в `run_polza_probe`). Сохранено как есть — тесты фиксируют «ровно одна платная попытка».
- **Command Code** — GAP, исправлен: бесплатный идемпотентный вызов каталога (`models` в `connect`) падал без ретрая; `subprocess.TimeoutExpired` покидал `command_api` нетипизированным исключением (его `str()` содержит полный argv). Исправление: таймаут конвертируется в типизированный `RuntimeError("command_transport_timeout; billing_unknown")` без содержимого; добавлен `command_api_free` — allowlist только `("models",)`, максимум 3 попытки, backoff 1s→2s, ретрай только на `command_transport_exit_*`/`command_http_5*`.
- **Teacher/Polza** — GAP, исправлен: `models?type=chat` и per-row `balance` не имели ретрая; сбой balance внутри цикла прерывал прогон без `summary.json`. Исправление: `api_free` — allowlist только `("models?type=chat", "balance")`, те же 3 попытки/1s→2s, только transient-классы; таймауты не ретраятся. Транспорт `run_polza_probe.api` (вне Own) не менялся — обёртка на стороне вызова.

### (c) ZDR / zero-retention header

- **Command Code**: выбранная владельцем модель `meta/muse-spark-1.3-contributor` **отклоняет ZDR** (`cmd_zdr_no_providers` — комментарий в коде; дисклеймер в `language_review.html`). Header не передаётся — подставлять провайдера/модель молча запрещено контрактом. Код не имитирует ZDR: `zdr_enforced=False` явно записывается в journal-события `connection`, `dispatch`, `visual_dispatch`, и разметчик предупреждён в UI. **GAP вне нашего контроля** (решение владельца: другая модель/провайдер с ZDR).
- **Teacher/Polza**: транспорт `docs/cameraanalysis/eval/run_polza_probe.py` (вне Own) не передаёт zero-retention header. **GAP зафиксирован, не исправляем в этом слайсе.**

### (d) Secret handling — ключ только env/keychain, не repo/log

- PASS по существу: `CMD_API_KEY` / `POLZA_API_KEY` только из env или скрытого ввода (getpass / password-field в UI); ключ живёт только в памяти процесса (`key_persisted=False` в журнале), в репо и артефактах его нет (скан: только чтение env, литералов нет); в curl ключ передаётся через `--config -` на stdin, не в argv; charset-валидация блокирует header-injection; HTTP-логирование локального сервера отключено (`log_message` no-op).
- Уточнение: keychain-хранилище не используется — env/getpass покрывают требование «не repo/log»; отдельный keychain — за пределами слайса.
- GAP (defense in depth), исправлен: строки ошибок персистились/отдавались как сырой `str(exc)` (у `TimeoutExpired` он содержит argv; «протекающий» транспорт попал бы в журнал). Исправление: `redact()` затирает активный ключ во всех путях — `result["error"]` в teacher-цикле, `public_error` в `analyze_visual`, возвращаемый текст в `interpret`, echo в `Handler.do_POST`.

## Изменения (Own-файлы)

- `tools/camera_annotation/review_pipeline.py`: `redact`, `api_free` (+`_polza_api`), `schema_violation`, schema-gate в `validate_proposal`, redacted error в teacher-цикле, расширение `self-check`.
- `tools/camera_annotation/language_review.py`: typed timeout в `command_api`, `command_api_free` + `redact`, `connect` через bounded retry, redaction в трёх error-путях, расширение `--self-check`.
- `tools/camera_annotation/language_labels.py`, `release_label_adapter.py`, `annotate_gui.py`: не тронуты (изменение `annotate_gui.py` в рабочем дереве — чужой DATA-005 GUI-слайс).
- Новое: `tools/camera_annotation/tests/test_data_006_annotation_api.py` (19 тестов, сеть не используется).

## Check

```
python3 -m pytest tools/camera_annotation/tests/test_data_006_annotation_api.py -q
  → 19 passed in 0.08s
python3 tools/camera_annotation/review_pipeline.py self-check
  → SELF-CHECK PASS: masks, uncertainty, vocabulary, research review projection
python3 tools/camera_annotation/language_labels.py
  → LANGUAGE LABELS SELF-CHECK PASS: quotes, visual evidence, spatial preservation, temporal boundary
python3 tools/camera_annotation/language_review.py --self-check
  → LANGUAGE REVIEW SELF-CHECK PASS: derivative, allowlist, lookahead, worker shutdown, retry allowlist, redaction
```

Покрытие тестами: (a) invalid JSON → `visual_error` без `interpretation`, ровно одна платная попытка; partial (8 отсутствующих ключей) и enum-drift → не записаны; (a-teacher) actions=3 c subject-ROI (проходило старые проверки) → отвергнуто схемой; partial без `notes`; NaN-rect; `assemble` отказывается от schema-invalid accepted-строки и не создаёт очередь; (b) каталог: 2 сбоя → успех, sleep ровно [1.0, 2.0]; постоянный сбой → ровно 3 попытки; платный путь: 1 попытка, 0 sleep, `billing_unknown=true`; таймаут не ретраится, типизирован; (d) ключ из «протекающего» транспорта отсутствует в журнале, `[redacted]` в public_error; echo обработчика затёрт.

## Gaps (честные ограничения)

1. ZDR недостижим для выбранной Command Code-модели (провайдер отвечает `cmd_zdr_no_providers`); журнал честно пишет `zdr_enforced=False`. Решение о другой модели/провайдере — владельца.
2. Транспорт Polza (`run_polza_probe.py`, вне Own) не передаёт ZDR-header и не имеет собственных ретраёв; здесь добавлен только call-side bounded retry для бесплатных эндпоинтов.
3. Keychain-интеграция отсутствует (env/getpass достаточно для «не repo/log»; нативный keychain — отдельное решение).
4. Command Code не отдаёт денежную телеметрию (`monetary_usage_available=False`); бюджет контролируется счётчиком запросов (`max_requests`), а не суммой — учтено в аудите, не менялось.
5. Поведение самой утилиты Command Code (каталог `commandcode/`) не проверялось по явному запрету владельца; зафиксирована только сторона вызова.
