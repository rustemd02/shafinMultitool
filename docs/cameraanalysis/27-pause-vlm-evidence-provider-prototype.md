# 27. Pause VLM Evidence Provider Prototype (PR-S03)

Статус: design verify (ready for implement)

Дата: 2026-05-05

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md)
- [22-offloading-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/22-offloading-contract.md)
- [23-hybrid-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/23-hybrid-eval-harness.md)
- [25-vlm-visual-semantic-evidence-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/25-vlm-visual-semantic-evidence-contract.md)
- [26-semantic-tip-fusion-and-planner.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/26-semantic-tip-fusion-and-planner.md)

## Цель PR-S03

Добавить отключаемый `pause-only` prototype provider для visual semantic evidence:

`deterministic pause bundle -> optional VLM provider -> strict validation -> semantic planner/fusion`

При любом сбое provider система обязана остаться на deterministic baseline без потери UX.

## Текущее состояние кода (design verify snapshot)

На момент проверки:
- контракты `VLMVisualEvidenceRequest/Response` и `VLMEvidenceValidationResult` уже реализованы в `CameraAnalysisDomainContracts.swift`;
- `SemanticTipPlanner` уже умеет принимать optional `validatedEvidence`;
- в `AnalysisPipeline` на `pause` путь сейчас передается только deterministic вход в planner;
- абстракции `VisualSemanticEvidenceProvider` и orchestration слоя для timeout/cancel/fallback пока нет;
- в кодовой базе есть паттерн `ReasoningProvider + PauseReasoningCoordinator`, который можно переиспользовать как reference orchestration.

Вывод: `PR-S03` логически блокирует полноценное подключение `PR-S02` контракта к runtime и должен быть выполнен до дальнейшего усиления `PR-S04` path.

## Implement-ready дизайн

### 1) Provider facade

Добавить отдельный слой, не смешивая с текстовым `ReasoningProvider`:

- `VisualSemanticEvidenceProvider` (protocol)
  - `providerId`
  - `capabilities` (поддержка privacy tiers, remote/local flags)
  - `fetchVisualEvidence(request:) async throws -> VLMVisualEvidenceResponse`

- `VisualEvidenceProviderFactory`
  - default: `nil` (disabled path)
  - `mock` для tests/demo
  - placeholder `remote` (explicitly optional, не mandatory dependency)

### 2) Coordinator (timeout/cancel/validation/fallback)

Добавить actor-координатор по паттерну `PauseReasoningCoordinator`:

- вход: `VLMVisualEvidenceRequest`, `mode`, `frameId`, correlation ids;
- выход: один из outcomes:
  - `skipped(provider_unavailable | mode_not_pause | policy_blocked)`
  - `accepted(validationResult)`
  - `rejected(violations)`
  - `failed(timeout | runtime_error | canceled_due_to_state_change)`
- timeout baseline: `<= 900 ms` (hard cap `1500 ms`);
- stale-guard: response применяется только при актуальном `pause` revision/frame.

### 3) Интеграция в `AnalysisPipeline`

В `pause` structured path:

1. построить `snapshot`, `semantics`, deterministic `critique`, `plan`;
2. собрать `VLMVisualEvidenceRequest` из local context;
3. асинхронно запросить provider через coordinator;
4. валидный результат передать в `SemanticTipPlannerInput.validatedEvidence`;
5. невалидный/timeout/unavailable результат -> `validatedEvidence = nil`;
6. сохранить telemetry и trace metadata без изменения deterministic source-of-truth.

`live` path не должен вызывать этот provider вообще.

### 4) Privacy + policy gate

Обязательные policy правила для prototype:
- только `mode == pause`;
- default tier: `structured_only`;
- `redacted_visual` разрешать только при явном config/trigger;
- без explicit config flag отправка реальных изображений запрещена;
- request должен быть fail-closed при policy mismatch.

### 5) Telemetry минимального набора

События (debug/eval):
- `visual_evidence.skipped.unavailable`
- `visual_evidence.skipped.policy_blocked`
- `visual_evidence.fail.timeout`
- `visual_evidence.fail.validation`
- `visual_evidence.fail.runtime`
- `visual_evidence.accepted`

Минимальные поля:
- `frameId`, `requestId`, `providerId`, `privacyTier`, `latencyMs`, `fallbackReason`, `violations[]`.

## Design verify findings

### Закрытые риски

- Контрактная часть (`PR-S02`) уже формализована и покрыта unit-level validation tests.
- Planner-слой уже готов принимать validated evidence без API-расширения.
- Existing deterministic fallback policy в pipeline уже соответствует fail-closed цели.

### Найденные gaps перед implement

1. Нет runtime provider abstraction для visual evidence.
2. Нет orchestration слоя для timeout/cancel/stale-drop.
3. Нет wiring между pause pipeline и `validatedEvidence` input planner-а.
4. В roadmap/backlog отсутствует явная `PR-S03` стадия, из-за чего теряется dependency chain между `PR-S02` и `PR-S04`.

### Конфликтов с frozen контрактами не найдено

- Дизайн совместим с `09`, `22`, `23`, `25`, `26`.
- Ownership не конфликтует с text refinement: `ReasoningProvider` остается отдельным контуром.

## Test matrix для `implement verify`

Минимальный набор:

1. `pause_success_with_mock_provider`
- accepted validated evidence доходит в planner без потери refs/confidence.

2. `pause_provider_timeout_fallback`
- при timeout результат детерминированный, без crash/blank pause state.

3. `pause_provider_validation_failed`
- invalid response -> full reject + deterministic fallback.

4. `pause_provider_unavailable`
- disabled/unconfigured path работает как no-op.

5. `live_never_calls_visual_provider`
- live mode не создает request и не обращается к provider.

6. `pause_stale_response_drop`
- при выходе из pause/revision shift поздний ответ игнорируется.

## Definition of done (PR-S03)

`PR-S03` считается закрытым, если:
- `pause` path может принять structured VLM evidence через mock provider;
- `live` path не вызывает visual provider;
- timeout/invalid/unavailable всегда дают deterministic fallback;
- entity-aware refs/labels/confidence доходят до planner без shape drift;
- tests доказывают, что provider не становится source-of-truth.
