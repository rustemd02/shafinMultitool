# ML/LLM Senior Agent

## proposal
- По ownership-файлам ML-path уже поднят до рабочего каркаса: в `LocalScenePlanProvider` есть event-table API (`generateEventTable*`) и patch API (`generateEventPatchOps*`), а в `LLMParserService` реализованы model-native prompt+parse для `sg_v9_event_table_v1` и `sg_v9_patch_ops_v1`, отдельные grammar-контексты и retry budget (`max_retry=1`, patch `max_tokens=512`, wall-clock budget).
- Для завершения `V9-Full` рекомендую сделать event-table path primary в `SceneBundlePipeline`: `sourceText + slotCatalog + anchors/state -> generateEventTableAsync -> verifier -> optional patch retry -> compile`. Текущий bridge (`plan -> buildEventTable`) оставить как fallback/A-B mode.
- Зафиксировать `fixable-only` policy формально: patch retry запускать только для issue-классов `{unknown_target_slot, target_required_missing, unknown_holding_slot, unknown_beat_slot}`; для `unknown_actor_slot` не делать автоматический silent repair, только drop/block с reason code.
- Уточнить grammar/prompt контракт patch ops: сейчас `value` в grammar — строка, что ограничивает структурные add-операции и повышает шанс невалидных JSON-в-строке. Для production лучше разрешить `value` как JSON object для `op=add`, либо явно запретить `add` в runtime и оставить только `replace/delete`.
- Для локальной модели (1.5B/квантизация) реалистичный режим: короткие slot catalogs, строгий max rows cap и агрессивное early-stop на patch path. Основной выигрыш даст не “умность” модели, а снижение свободы выхода: closed slots + deterministic verifier.
- В метриках отчёта разделить два независимых блока:
  - `Structural Recovery` (schema/pass/repair rates),
  - `Semantic Fidelity` (actor/target/beat gold accuracy + strict success).
  Это обязательно, иначе repair будет скрывать семантические потери.

## risks
- Главный риск — semantic regression под видом стабильности JSON: `targetless -> stand`, `unknown_slot -> drop` поднимут structural pass, но могут уронить `chronology` и `case_strict_success_rate`.
- Риск неверной patch-операции из-за grammar-ограничения `value: string`: модель может вернуть строку, не восстанавливаемую в корректный row object (особенно для `add`), и retry будет шуметь без пользы.
- Риск latency/local OOM на длинных сценах: 3 event попытки + patch retry на мобильном CPU/GPU могут выйти за UX-бюджет, даже при `max_retry=1`, если не ограничить rows/beats и prompt size.
- Риск ложной уверенности в оффлайн-оценке: projection-based eval не равен live-model behavior; без обязательного live-vs-offline gap report gate может пройти преждевременно.
- Риск policy drift: если `fixable-only` не закреплён в коде и тестах, runtime начнет “лечить всё”, что делает output менее предсказуемым и хуже для дипломной валидации.

## required_tests
- Contract tests:
  - `sg_v9_event_table_v1`: duplicate/empty `rowID`, unknown enums, invalid slot ids.
  - `sg_v9_patch_ops_v1`: whitelist `op/field`, and отдельный тест на `add` value decoding policy (string vs object).
- Runtime ML-path tests:
  - e2e через model-native `generateEventTableAsync` (не bridge), затем verifier -> optional patch -> compile.
  - budget тесты: `max_retry=1`, patch `max_tokens<=512`, patch wall-clock <= configured budget.
  - deterministic reason codes: `v9.event_table_*` и `v9.patch_retry_*` появляются в ожидаемых ветках.
- Fixable-only tests:
  - `unknown_actor_slot` => no patch, block/drop + reason.
  - `target_required_missing` => patch attempt allowed, deterministic fallback only after patch failure.
  - `unknown_target_slot` и `unknown_holding_slot` => patch eligible.
- Semantic integrity tests:
  - regression набор на `navstrechu`, `collective stop near object`, `dialogue + described_action`.
  - assert: structural pass рост не должен сопровождаться падением strict/chronology ниже agreed floor.
- Eval realism tests:
  - обязательный live-vs-offline gap report по actor/target/beat accuracy и strict success.
  - confusion matrix по verifier issues и post-patch outcomes.

## open_conflicts
- Архитектурный конфликт остаётся: runtime primary path всё ещё bridge-first, хотя ML API уже готовы для model-native V9.
- Patch policy конфликт: реализован технический retry path, но не зафиксирован в pipeline как strict `fixable-only` с issue-class gating.
- Grammar конфликт patch ops: текущий `value`-as-string не идеально совместим с надёжным `add` rows; нужно решение до demo gate.
- Eval конфликт: acceptance цели должны считаться от live-model path; projection-only отчёты не могут быть official evidence.

## gate votes
- `contract_gate`: **APPROVE (conditional)**  
  Контракты и API готовы, но требуется зафиксировать patch `value` policy (`add` semantics) в спеках и тестах.
- `runtime_gate`: **CONDITIONAL**  
  ML runtime компоненты готовы (event/patch generation, budgets, reason codes), но primary pipeline ещё не переключён на model-native path.
- `eval_gate`: **BLOCK**  
  Пока нет обязательного live-vs-offline gap evidence и semantic-vs-structural разделения в финальных release метриках.
- `demo_gate`: **BLOCK**  
  До закрытия runtime/eval конфликтов и parity regression suite sign-off преждевременен.
