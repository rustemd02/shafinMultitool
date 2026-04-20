# 09. Reasoning Provider and Pause LLM Layer (PR-012/PR-013)

Статус: design spec (source-of-truth)

Дата: 2026-04-20

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)

## Цель

Зафиксировать implement-ready дизайн для:
- `PR-012`: `ReasoningProvider` abstraction;
- `PR-013`: pause-only LLM explanation layer.

Ключевая цель `v1`:
- улучшить качество расширенного текста в `pause`;
- не менять deterministic source-of-truth по `issues/actions/verdict`;
- сохранить рабочий путь без provider и при любых сбоях provider.

## Scope и ограничения

В scope:
- protocol/adapter/coordinator для reasoning;
- input/output контракт между deterministic core и provider;
- pause-only integration policy;
- graceful degradation и failure handling;
- trace-совместимость с `04-explainability-contract.md`.

Вне scope:
- изменения taxonomy (`IssueTypeV1`, `StrengthTypeV1`, `FixTypeV1`, `ActionTypeV1`);
- изменения детекторов `FrameCritiqueEngine`;
- live LLM usage;
- UI redesign за пределами текущего pause card contract.

Ограничения `v1`:
- LLM не source-of-truth для raw issues/actions;
- `RecommendationPlanner` принимает решения только по deterministic ветке;
- provider не должен блокировать базовый pause UX;
- provider output не может ломать `TraceLink.refId` и runtime IDs.

## PR Boundary

### PR-012. Reasoning Provider Abstraction

Что вводим:
- `ReasoningProvider` protocol;
- `ReasoningProviderFactory`/registry;
- `PauseReasoningCoordinator` (orchestrator для timeout/cancel/cache/validation);
- no-op provider (`disabled` path) как baseline.

Что не вводим:
- тяжелая промпт-настройка;
- model-specific policies глубже базовой конфигурации.

### PR-013. Pause LLM Explanation

Что вводим:
- конкретный provider implementation (local/offloaded, зависит от environment);
- prompt pack для text refinement поверх structured payload;
- интеграция в `pause` flow с двухшаговым rendering policy.

Что не трогаем:
- deterministic critique/planner logic;
- live hint decision path.

## Integration Topology

Reasoning слой встраивается только после успешного deterministic пайплайна:

1. `snapshot -> semantics -> critique -> plan`.
2. Валидируем structured path по правилам `08-ui-integration.md`.
3. Сразу публикуем deterministic `PauseCritiquePresentation` (baseline).
4. Если `mode == pause` и provider доступен, асинхронно запрашиваем refinement.
5. При успехе применяем безопасный text patch к уже показанной pause card.
6. При ошибке/таймауте оставляем baseline без изменения.

Следствие:
- первый экран pause всегда deterministic и доступен без LLM;
- LLM только улучшает формулировки, не определяет решение.

## Provider Abstraction (source-of-truth)

```text
ReasoningProvider
- providerId: String
- capabilities: ReasoningCapabilities
- refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse

ReasoningCapabilities
- supportsOffline: Bool
- supportsRemote: Bool
- supportsRussian: Bool
- maxInputChars: Int
- maxOutputChars: Int

ReasoningRequest
- requestId: String
- frameId: String
- mode: AnalysisMode (must be pause)
- locale: String                    // например ru-RU
- critique: CritiqueReport
- plan: RecommendationPlan
- trace: ExplainabilityTraceBundle?
- pausePresentationDraft: PauseCritiquePresentation
- constraints: ReasoningConstraints
- correlation: ReasoningCorrelation

ReasoningConstraints
- maxLatencyMs: Int                 // default 900, hard cap 1500
- maxOutputTokens: Int              // provider-specific, bounded
- strictDeterministicGuard: Bool    // always true in v1
- allowSpeculativeTone: Bool        // default false

ReasoningCorrelation
- pipelineVersion: String
- contractVersion: String
- providerConfigVersion: String

ReasoningResponse
- requestId: String
- frameId: String
- providerId: String
- textPatch: PauseTextPatch
- optionalTraceItems: [ExplainabilityTraceItem]
- safety: ReasoningSafetyReport
- diagnostics: ReasoningDiagnostics

PauseTextPatch
- shortVerdictOverride: String?     // optional; смысл verdict не меняется
- whyGoodByStrengthId: [String: String]
- whyProblematicByIssueId: [String: String]
- actionRationaleByActionId: [String: String]
- noChangeRationaleOverride: String?

ReasoningSafetyReport
- passed: Bool
- violations: [ReasoningViolation]

ReasoningViolation
- mode_not_pause
- unknown_runtime_id
- attempts_to_change_verdict
- attempts_to_change_issue_taxonomy
- attempts_to_change_action_taxonomy
- unsupported_trace_links
- output_too_long
- empty_patch
- low_faithfulness

ReasoningDiagnostics
- latencyMs: Int
- tokenUsageIn: Int?
- tokenUsageOut: Int?
- fallbackReason: String?
```

## Pause-only Gate

Обязательное правило:
- `ReasoningProvider` вызывается только при `mode == pause`.

Если `mode == live`:
- вызов provider запрещен policy-level guard;
- telemetry событие фиксируется как policy violation кандидата вызова;
- deterministic live path продолжает работу.

## Allowed vs Forbidden Influence

Разрешено для provider:
- переформулировать `shortVerdict` в пределах того же класса verdict;
- уточнить текст по существующим `strengthId/issueId/actionId`;
- при `verdict == good && primaryAction == nil` уточнить `noChangeRationale` в рамках текущего смысла.

Запрещено для provider:
- менять `verdict`, `verdictConfidence`, `planConfidence`;
- добавлять/удалять/переупорядочивать issues/actions/strengths;
- вводить новые taxonomy keys;
- создавать action links, отсутствующие в deterministic plan;
- изменять runtime ID (`summaryId`, `issueId`, `strengthId`, `actionId`, `overlayHintId`).

Policy применения patch:
- patch применяем только к текстовым полям;
- структура pause card и порядок блоков остается deterministic;
- если patch частично невалиден, применяем только валидную подчасть (partial accept) и логируем нарушение.

## Explainability and Trace Rules

Совместимость с `04-explainability-contract.md` обязательна:

1. `optionalTraceItems` могут быть только:
- `stage = interpretation`;
- `sourceKind = optional_reasoning`;
- `certainty = probabilistic | speculative`.

2. Для `optional_reasoning` items:
- запрещен `TraceLink(kind: action, ...)`;
- разрешены `summary`, `issue`, `strength` links только на существующие runtime IDs.

3. Append-only:
- deterministic trace items не изменяются и не удаляются;
- optional items добавляются в bundle после deterministic ветки.

4. Root summary policy:
- deterministic summary root остается обязательным;
- optional summary item может быть добавлен дополнительным root только после successful validation.

5. Conflict policy:
- если optional reasoning противоречит deterministic interpretation, deterministic версия остается source-of-truth;
- конфликт маркируется в metadata optional item: `conflictWith=<traceId>`.

## Failure Handling Rules

Категории отказа:

1. `provider_unavailable`
- причина: provider nil/disabled/not configured;
- поведение: baseline pause text, без ошибок в UI;
- telemetry: `reasoning.skipped.unavailable`.

2. `timeout`
- причина: ответ дольше `maxLatencyMs`;
- поведение: baseline pause text;
- telemetry: `reasoning.fail.timeout`.

3. `transport_or_runtime_error`
- причина: сеть/инференс/исполнение;
- поведение: baseline pause text;
- telemetry: `reasoning.fail.runtime`.

4. `validation_failed`
- причина: нарушены guard rules (`unknown_runtime_id`, taxonomy mutation, links policy, `low_faithfulness`);
- поведение: baseline; partial accept допускается только для non-faithfulness нарушений, `low_faithfulness` всегда ведет к full reject;
- telemetry: `reasoning.fail.validation`.

5. `canceled_due_to_state_change`
- причина: пользователь вышел из pause/resume live;
- поведение: отмена task, ничего не применяем;
- telemetry: `reasoning.cancel.pause_exit`.

Global guarantees:
- ни один failure provider не переводит UI в hard legacy fallback сам по себе;
- hard fallback определяется только правилами structured path (`08-ui-integration.md`);
- degraded banner для provider-ошибок в `v1` не обязателен (debug-only logging достаточно).

## Timeout, Budget and Concurrency Policy

- default timeout `900 ms`, hard cap `1500 ms`;
- один активный reasoning task на `frameId`;
- при новом pause кадре старый task отменяется;
- response применяется только если `frameId` и `requestId` совпадают с актуальным pause state;
- optional cache допускается по ключу:
  - `cacheKey = hash(frameId + critique.summary.id + primaryAction.id? + providerConfigVersion)`.

## Prompt/Interface Sketch (PR-013)

Provider получает только структуру, без сырого пиксельного кадра в `v1`:

```text
System role:
"Ты улучшатель формулировок для camera critique. Не меняй структуру решения."

Input JSON:
- verdict, summary, strengths[], issues[], actions[], noChangeRationale
- trace roots (опционально)
- style constraints (neutral, concise, no hallucinations)

Output JSON:
- whyGoodByStrengthId
- whyProblematicByIssueId
- actionRationaleByActionId
- optional shortVerdictOverride

Hard rules:
- только существующие IDs
- без новых issues/actions
- без изменения verdict class
- максимум 1-2 предложения на элемент
```

Тон и length policy:
- `pause`: дружелюбный, предметный, без категоричных утверждений при низкой уверенности;
- избегать повторов одного и того же шаблона между элементами;
- ограничение длины на элемент: `<= 180` символов (рекомендовано).

## Validation Contract for Response

Перед применением response coordinator обязан проверить:

1. `requestId` и `frameId` совпадают с активным контекстом.
2. `mode == pause`.
3. Все ключи patch ссылаются только на существующие IDs текущего payload.
4. Нет попыток сменить taxonomy/verdict/структуру блоков.
5. Текст не пустой после trim и не превышает policy limits.
6. `optionalTraceItems` проходят `ExplainabilityTraceBundle.validate(...)` вместе с deterministic bundle.
7. Для каждого измененного текста сохраняется faithfulness к deterministic evidence:
   - нельзя вводить новую причинно-следственную связь, которой нет в текущих `issue/strength/action` и trace;
   - нельзя усиливать уверенность формулировки выше допустимой по текущему `confidence`/`verdictConfidence`.

Если зафиксирован `low_faithfulness`:
- это всегда трактуется как `validation_failed`;
- в `v1` применяется full reject ответа provider (без partial accept);
- обязательно пишется telemetry `reasoning.fail.validation` с причиной `low_faithfulness`.

Если хотя бы один hard-check провален:
- response отвергается полностью или частично (по patch-scope),
- deterministic state сохраняется.

## Minimal Test Matrix

### PR-012 tests

- provider gate test: `mode == live` никогда не вызывает provider;
- disabled provider test: no-op path возвращает baseline без ошибок;
- timeout test: fallback к baseline без изменения структуры pause card;
- cancellation test: при resume live response не применяется;
- id integrity test: patch с неизвестным `issueId/actionId` отклоняется;
- trace policy test: optional item с `TraceLink.kind == action` отклоняется.

### PR-013 tests

- success path: valid patch улучшает текст, структура не меняется;
- partial patch path: валидные поля применяются, невалидные отбрасываются;
- taxonomy mutation attempt: full reject;
- verdict mutation attempt: full reject;
- low-faithfulness attempt: full reject + `reasoning.fail.validation`;
- long output truncation/validation path;
- determinism safety: при одинаковом deterministic input без provider результат идентичен baseline.

Manual smoke:
- pause good frame: усиливается объяснение strengths/no-change;
- pause problematic frame: более читаемые why/action тексты;
- provider off: UX совпадает с deterministic baseline;
- provider fail during pause: UI остается стабильным, без blank state.

## Write Scope (implement)

Разрешенный scope для `PR-012/013`:
- `shafinMultitool/Multitool2Module/Services/Reasoning/*` (новые файлы)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (только integration points)
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/*` только при contract-safe расширениях
- `shafinMultitoolTests/*Reasoning*` и/или `shafinMultitoolTests/CameraAnalysis*`

Запрещено в этих PR:
- массовые правки UI вне pause text binding;
- изменения детекторов issues/strengths в `FrameCritiqueEngine`;
- изменения `RecommendationPlanner` decision policy.

## Definition of Done

`design` для Prompt 7 считается готовым, если:
- определен provider abstraction и coordinator behavior;
- зафиксирован I/O контракт provider-а и patch policy;
- pause-only gate формализован;
- сохранена explainability совместимость и append-only trace policy;
- failure handling/degradation rules конкретны и проверяемы;
- baseline path без provider полностью рабочий и описан.
