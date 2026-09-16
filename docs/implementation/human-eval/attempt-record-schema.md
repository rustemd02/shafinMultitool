# Camera Coach human attempt record schema v1 (docs-level contract)

Status: **preparation / `needs_review`**. Samа оценка — `blocked_external`.
Дата: 2026-09-13. Задача: runbook Q02 (`docs/aegis/plans/2026-09-13-setos-release-execution.md`).
Дополняет существующие контракты, не заменяет их:

- `datasets/camera-coach/v1/episode-schema.json` v1.0.0 — before/action/after, `outcome`, `outcome_verifier`, `subject_continuity`;
- `datasets/camera-coach/v1/label-schema.json` v1.0.0 — `actionId`, `verifierId`, `styleIntent`, `review.vote_history` / `adjudication_history`;
- `datasets/camera-coach/v1/capture-protocol.md` — source/family/rights/provenance поля;
- `datasets/camera-coach/v1/annotation-guide.md` §9 — разногласия не усредняются.

Этот документ — **не новый инструмент и не JSON Schema в `tools/**`**. Это нормативное описание полей и
fail-closed правила; при появлении машинной схемы она должна быть согласована с уже существующими
episode/label контрактами, а не дублировать их.

## 1. Назначение

Одна запись = одна **реальная** попытка: приложение предложило действие, человек его понял/не понял,
смог/не смог/отказался выполнить, фактически что-то изменил, есть before/after, intent, target/protected,
latency. Оценка полезности — отдельными реальными голосами (раздел 4), а не самой записью.

## 2. Поля записи попытки

Тип `camera-human-attempt-v1`, `schema_version=1.0.0`. Обязательность: **R** = required, **C** = required
conditional (см. §3). Все ссылки на сущности — asset-local stable ID, не угаданные имена.

### 2.1. Идентичность и контекст

| Поле | Тип / значения | R | Комментарий |
|---|---|---|---|
| `attempt_id` | `^[a-z0-9][a-z0-9._-]*$` | R | уникален в батче |
| `case_id` | id | C | обязателен, если попытка входит в locked blind set |
| `shot_scenario_id` | `SL-01`…`SL-10` | R | из `shot-list-v1.md` |
| `matrix_class` | `single_person`, `two_people`, `object_or_food`, `interior`, `street_or_landscape`, `difficult_light`, `already_good_frame` | R | из `capture-protocol.md` |
| `split` | `train`,`calibration`,`holdout`,`quarantine` | R | назначает release owner, не оператор |
| `source_shoot_id`, `operator_id` | id | R | privacy-safe |
| `captured_at` | UTC `YYYY-MM-DDTHH:MM:SSZ` | R | начало сессии |
| `consent_record_id`, `rights_record_id`, `provenance_receipt_ref` | id/ref | R | неразрешённые → incomplete (§3) |

### 2.2. Предложенный совет (что выдало приложение)

| Поле | Тип / значения | R | Комментарий |
|---|---|---|---|
| `proposed_at` | UTC Z | R | момент показа |
| `advice_count` | целое = `1` | R | C05: одна допущенная команда; >1 → invalid |
| `proposed_action_id` | `actionId` enum | R | включая `keep_current_setup` |
| `proposed_action_text` | строка | R | фактически показанный локализованный текст |
| `proposed_target_refs` | массив id, ≥1 | R | кого/что улучшаем |
| `proposed_protected_refs` | массив id | C | обязателен для действий над сущностями; непуст, если есть защищаемая деталь |
| `proposal_generation_ref` | id | C | для отзыва/инвалидации при stale generation |

### 2.3. Выполнение человеком

| Поле | Тип / значения | R | Комментарий |
|---|---|---|---|
| `understood` | `yes`,`no`,`partial`,`not_asked` | R | понял ли человек совет |
| `executable` | `yes`,`no`,`partial`,`not_attempted` | R | смог ли выполнить |
| `status` | `completed`,`declined`,`cancelled`,`not_attempted`,`failed_attempt` | R | `declined`/`cancelled` — валидные записи, но не успех |
| `performed_change` | строка | C | **обязательна при `status=completed`**: что реально изменилось |
| `performed_action_id` | `actionId` / null | C | фактическое действие может отличаться от предложенного |
| `refusal_reason` | `not_provided`,`prefer_not_to_say`,`no_resource`,`physically_unable`,`unsafe`,`unclear_instruction`,`too_slow`,`other` | C | **причина отказа не истребуется**; `not_provided` — полноценное значение |
| `refusal_reason_source` | `human_reported`,`not_provided` | R | фиксирует, что объяснения не было принудительно |
| `self_report_author` | `operator_id` | R | эти поля — самоотчёт оператора с авторством, не независимая оценка |

`understood`/`executable` — это **самоотчёт оператора**, а не голос независимого оценщика. Для human-gold он
учитывается как один голос владельца (см. §4.4), а не как два.

### 2.4. Before / after

| Поле | Тип / значения | R | Комментарий |
|---|---|---|---|
| `before.asset_id`, `before.sha256`, `before.captured_at` | id / sha256 / UTC Z | R | оригинал, не derivative |
| `after.asset_id`, `after.sha256`, `after.captured_at` | id / sha256 / UTC Z | C | обязателен при `status=completed` (кроме KEEP) |
| `same_context` | `true` | R | один source/take family |
| `subject_continuity` | `same`,`changed`,`lost`,`unknown` | R | measurable outcome требует `same` |
| `derivation_kind` | `original_before_after_episode` | R | crops/burst-соседи не считаются независимыми (capture-protocol) |

Строгая хронология: `before.captured_at < proposed_at|performed_at < after.captured_at`.
`before.sha256 != after.sha256` (иначе это не эпизод).

### 2.5. Intent, target, protected

| Поле | Тип / значения | R | Комментарий |
|---|---|---|---|
| `intent.style_id` | `naturalistic`,`cinematic`,`documentary`,`commercial`,`stylized`,`already_good`,`unknown` | R | из `label-schema.styleIntent` |
| `intent.intentional` | bool | R | объявлено до съёмки |
| `intent.basis` | `capture_brief`,`annotator_observed`,`not_available` | R | `fixture` недопустим в реальной попытке |
| `target_refs` | массив id, ≥1, разрешимые | R | совпадает с `proposed_target_refs` либо расхождение объяснено |
| `protected_refs` | массив id, разрешимые | R | пустой допустим только если защищаемых деталей реально нет |

### 2.6. Latency

| Поле | Тип | R | Комментарий |
|---|---|---|---|
| `understood_at` | UTC Z / null | C | если зафиксировано |
| `performed_at` | UTC Z | C | при `completed`/`failed_attempt` |
| `action_latency_ms` | целое ≥0 / null | C | `performed_at - proposed_at`; неотрицательно |
| `result_latency_ms` | целое ≥0 / null | C | `after.captured_at - proposed_at`; для сверки с M13 p50≤3 s / p95≤8 s |

### 2.7. Outcome (машинный/верификаторный, не человеческий)

| Поле | Тип / значения | R | Комментарий |
|---|---|---|---|
| `outcome` | `correct`,`no_op`,`opposite`,`overshoot`,`track_loss`,`incomparable` | R | из `episode-schema.json` |
| `outcome_verifier` | `verifierId` enum | R | соответствующий предикат |
| `measurement` | `before_after` | C | обязателен для measurable outcome |
| `verification_result` | `pass`,`fail`,`inconclusive`,`not_run` | R | measurable outcome требует `pass` |

## 3. Fail-closed правило

`record_status = complete` **тогда и только тогда**, когда выполнены все условия:

1. присутствуют и не `null` все **R**-поля; условные **C**-поля заполнены, когда их условие истинно;
2. все enum-значения принадлежат закрытым множествам выше; неизвестное значение не приводится к дефолту;
3. `captured_at`, `proposed_at`, `performed_at`, `after.captured_at` — валидные UTC `Z` и строго возрастают;
4. `target_refs` и `protected_refs` **разрешаются** в реальные entity refs (не guessed);
5. `before.sha256`/`after.sha256` присутствуют, различны и совпадают с реальными ассетами;
6. `advice_count == 1` и есть реально показанный `proposed_action_text`;
7. если `outcome` ∈ {`correct`,`no_op`,`opposite`,`overshoot`} → `verification_result=pass`,
   `measurement=before_after`, `subject_continuity=same`;
8. если `status=completed` → есть `after` и непустой `performed_change`;
9. `consent_record_id`/`rights_record_id` разрешены и допускают использование.

Если **любое** условие нарушено (в т.ч. отсутствует одно поле): `record_status = incomplete`, запись
**исключается** из всех квот и gate-знаменателей, сохраняется как аудит, и **никогда не додумывается**
(нельзя подставить `naturalistic`, ноль, «нет изменений», «понял»).

Отдельно: `validity = valid | invalid` (нарушены правила валидности из `shot-list-v1.md` §2 — постановка,
кроп/правка after, повтор кадра, смена субъекта/cut/lens внутри эпизода, assisted blind vote). В анализ
входят только `complete AND valid`. KEEP-попытка не создаёт исполнительный эпизод и не требует `after`,
но требует явного `keep_decision` в последующей пометке.

## 4. Слепая оценка (реальные люди)

### 4.1. Голос ревьюера (append-only, как `review.vote_history`)

| Поле | Значения | Комментарий |
|---|---|---|
| `review_id`, `reviewer_id`, `voted_at` | id / id / UTC Z | хронология строго возрастает |
| `blind` | `true` | ревьюер не видит предложенный совет при оценке after, если протокол требует blind |
| `assisted` | `false` | `true` → голос **не** независимый, в κ/gates не входит |
| `assist_source` | null / строка | обязателен при `assisted=true`; источник-ИИ не является ревьюером |
| `visually_improved` | `yes`,`no`,`unsure` | только визуал |
| `useful_instruction` | `yes`,`no`,`unsure` | совет полезен как инструкция |
| `executable` | `yes`,`no`,`unsure` | выполнимо человеком |
| `harmful` | `none`,`minor`,`material`,`critical` | материал/критический вред |
| `intent_preserved` | `yes`,`no`,`unsure` | замысел сохранён |
| `attribution` | `action_caused`,`other_cause`,`unknown` | **причинная атрибуция улучшения** |
| `notes` | строка / null | свободно |

### 4.2. Правило «красивый after по другой причине — не доказательство»

Успешной совет считается **только** при одновременном:

- `visually_improved=yes` **и** `attribution=action_caused`,
- `intent_preserved=yes`,
- `harmful=none`,
- машинный `outcome=correct` с `verification_result=pass` и соответствующим verifier.

`visually_improved=yes` при `attribution=other_cause` или `unknown` **не** увеличивает ни helpful, ни
preference. Красивый after, вызванный сменой света/погоды/самого кадра, случайным движением или правкой
файла, не является доказательством успешного совета. `other_cause`/`unknown` фиксируются и входят в
знаменатели как non-success, а не выбрасываются.

### 4.3. Разногласия → adjudication, не большинство

- Любое расхождение хотя бы по одному из five dimensions или по `attribution` между двумя голосами —
  это disagreement.
- Hard disagreements (из `annotation-guide.md` §9): identity mismatch, acceptable↔forbidden, KEEP↔corrective,
  ABSTAIN↔forced action, `action_caused`↔`other_cause`, non-comparable before/after.
- Голоса **не усредняются**; арифметическое/модальное большинство не применяется.
- Адъюдикатор: отдельный реальный человек, который **не голосовал** по этому кейсу; видит оба голоса,
  before/after, предложение и verifier evidence.
- `adjudication_history` — отдельный append-only массив, событие строго после всех referenced vote,
  `outcome` ∈ `accepted`,`rejected`,`quarantined`; ссылка на vote ids.
- Неразрешённые разногласия → `quarantine`, не принудительный победитель.

### 4.4. Независимость (энфорсится)

- Один реальный человек = один аннотатор. Владелец может быть **одним** аннотатором.
- Подсказки ИИ (`assisted=true`, `assist_source=…`) **не** являются независимым оценщиком и исключаются из
  κ/hidden QC/согласия (реализовано в `tools/camera_annotation/pilot_agreement_report.py`).
- Голоса владельца **не** выдаются за двух независимых аннотаторов.
- Для human-gold нужен **второй реальный независимый человек**; его отсутствие — честный
  `blocked_external`, а не имитация.
- Один аннотатор даёт по записи **не более одного голоса**. Повторный голос — это ревизия: в согласии
  учитывается последний, а прежний попадает в счётчик повторных. Два `annotator_id` без ни одной записи,
  размеченной двумя разными людьми, — это ещё не независимая панель, и κ по таким данным измерял бы
  самосогласование одного человека, а не согласие между людьми
  (`tools/camera_annotation/pilot_agreement_report.py` печатает `НЕДОСТУПНО`, а не число).
- Blind-проход выполняется без видимых чужих ответов и без подсказок ИИ; если подсказка использована,
  факт фиксируется (`assisted=true`) и голос не считается слепым.

## 5. Что явно запрещено

- Заполнять карточки/опросы/оценки от лица реальных людей; выдумывать участников, оценки, квоты, κ.
- Считать ИИ независимым оценщиком или превращать owner + AI hints в двух независимых аннотаторов.
- Принуждать человека объяснять отказ; `not_provided` валиден.
- Помечать human gate пройденным по итогам подготовки.
- Импутировать пропущенные поля (intent, target, outcome, «понял») и повышать запись из `incomplete`.
- Усреднять разногласия голосованием большинства.
- Считать `visually_improved` без `action_caused` успехом совета.

## 6. Машинная проверка §3

`tools/human_eval/validate_attempt_record.py` выводит `record_status` из записи, а не принимает его на
слово: заявленный `record_status="complete"`, который деривация опровергает, — это exit 1 и отдельный
счётчик `overclaimed`. Проверяются 16 условий: обязательные и условные поля (§2.1–§2.6), форма
идентификаторов (`attempt_id`, `shot_scenario_id` ∈ SL-01…SL-10), закрытые перечисления из
`label-schema.json` (`actionId`, `verifierId`) и из §2.3, тип `intent.intentional`, `same_context = true`,
непустые `target_refs`/`proposed_target_refs`, строгая хронология (§3 условие 3 и §2.4 отдельно),
`advice_count == 1` с реально показанным текстом, требования measurable outcome, `status=completed`,
идентичность и совпадение ассетов, арифметика latency (§2.6) и разрешение refs/consent/rights.

Словари читаются из замороженных артефактов (`datasets/camera-coach/v1/label-schema.json`,
`docs/implementation/human-eval/shot-list-v1.md`), а не переписываются в коде. Если словарь не
читается, соответствующие проверки дают `unresolved` и запись **не** становится `complete` — пустой
список не должен превращаться в пройденную проверку.

**Что не проверяется записью** и объявлено в `conditions_not_enforced` выходного JSON: `case_id`
(принадлежность locked blind set), `proposed_protected_refs`, `proposal_generation_ref`, пустота
`protected_refs`, семантика `intent.intentional` как порядка во времени, наличие `refusal_reason`
(§2.3 — причина не истребуется, проверяется только значение) и ось `validity`.

**Открытый вопрос контракта:** KEEP-попытка не требует `after` (§2.4, последний абзац §3) и не является
исполнительным эпизодом, поэтому `is_success=false`; но какие `outcome`/`outcome_verifier` допустимы для
KEEP-записи, в контракте не зафиксировано — сейчас KEEP исключён из требования measurable-outcome.
Решение — за владельцем контракта, а не за инструментом.
