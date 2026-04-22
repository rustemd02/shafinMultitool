# 22. Offloading Contract (PR-H12)

Статус: design spec (source-of-truth)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md)
- [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md)

## Цель

Зафиксировать gated offloading design для `PR-H12` так, чтобы:
- `PR-H13` мог реализовать optional server/teacher critic без переоткрытия базовых privacy и fallback решений;
- offloading не ломал `offline-first` тезис и не становился обязательным runtime dependency;
- deep critique path оставался bounded, explainable и совместимым с уже замороженными local contracts;
- payload schema и trigger rules были достаточно точными для transport/client implementation без домысливания.

Этот документ закрывает design-часть `PR-H12` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Scope

`PR-H12` отвечает за:
- trigger policy для optional offloading;
- service-level abstraction `DeepCriticProvider`;
- privacy tiers и payload sanitation rules;
- transport-neutral request/response schema;
- bounded role of remote critic;
- fallback, timeout и validation policy.

`PR-H12` не отвечает за:
- конкретную server implementation;
- training/inference details remote model-а;
- изменение local deterministic critique semantics;
- обязательное UX-представление remote output;
- live offloading;
- замену `ReasoningProvider` или `NeuralEvidenceSnapshot` отдельными параллельными контрактами.

Граница ответственности:
- local deterministic critique, local neural evidence и bounded fusion уже формируются до offloading;
- `PR-H12` описывает только optional deep-analysis branch поверх уже полезного local pause result;
- `PR-H13` будет реализовывать concrete remote prototype внутри этих границ.

## Design Summary

Ключевая формула `PR-H12`:

`local pause baseline -> offloading gate -> privacy filter -> remote bounded review -> optional async augmentation`

Из нее следуют обязательные правила:
- offloading разрешен только после того, как локальный `pause` результат уже построен;
- local result публикуется первым и остается usable даже если offloading не стартовал, заблокирован или упал;
- remote critic не является source-of-truth для `IssueTypeV1`, `StrengthTypeV1`, `ActionTypeV1` и финального baseline verdict;
- automatic path по умолчанию использует `structured_only` payload без передачи изображения;
- передача redacted visual payload разрешена только при явном пользовательском intent на deeper analysis;
- remote output применяется только как advisory layer или text refinement поверх уже существующего local outcome;
- `live` offloading запрещен в `PR-H12`.

Короткая policy-формула:

`remote critic is a bounded reviewer, not the baseline judge.`

## Architectural Position

Последовательность для `pause` с optional offloading должна быть такой:

1. local deterministic pipeline
2. optional local neural evidence
3. bounded local fusion
4. immediate local pause presentation
5. optional offloading trigger evaluation
6. remote review in background
7. validated advisory application or silent drop

Почему sequencing именно такое:
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md) уже зафиксировал, что offloading не может подменить local baseline;
- [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md) заморозил deterministic critique как decision source-of-truth;
- этот порядок делает remote critic optional enhancement path, а не новый критический этап пайплайна.

## Runtime Roles

### 1. `DeepCriticOffloadingCoordinator`

Главный orchestration layer, который:
- получает уже готовый local `pause` bundle;
- оценивает trigger policy;
- выбирает privacy tier;
- собирает sanitized transport envelope;
- вызывает provider;
- валидирует ответ;
- отдает outcome в pipeline/UI/debug layer.

Этот слой не принимает решений о базовом `verdict` и не может отменить уже показанный local result.

### 2. `DeepCriticGatePolicy`

Отдельный policy object, который решает:
- есть ли вообще право запускать offloading для данного кадра;
- какой trigger сработал;
- допустим ли только `structured_only` или разрешен `redacted_visual`;
- нужен ли debounce/cache;
- должен ли запрос быть auto-triggered или только explicit.

### 3. `DeepCriticPrivacyFilter`

Слой, который:
- удаляет все transport-несовместимые и privacy-sensitive поля;
- гарантирует, что payload не содержит скрытых user identifiers;
- понижает payload до минимально достаточного privacy tier;
- формирует optional redacted visual attachment только по allow-list policy.

### 4. `DeepCriticProvider`

Transport-neutral abstraction для remote reviewer-а.

Канонический protocol-level смысл:

```text
DeepCriticProvider
- providerId: String
- capabilities: DeepCriticCapabilities
- review(request: DeepCriticTransportEnvelope) async throws -> DeepCriticResponse

DeepCriticCapabilities
- supportsStructuredOnly: Bool
- supportsRedactedVisual: Bool
- supportsRussian: Bool
- maxRequestBytes: Int
- maxResponseBytes: Int
- allowsTeacherEvidence: Bool
```

### 5. `DeepCriticResponseValidator`

Слой, который:
- проверяет `requestId/frameId/schemaVersion`;
- проверяет, что response не мутирует frozen taxonomy;
- отклоняет unsafe text patches и out-of-range deltas;
- проверяет privacy tier consistency;
- нормализует advisory output к contract-safe форме.

## Trigger Policy

### Hard preconditions

Offloading вообще нельзя рассматривать, если хотя бы одно условие не выполнено:
- `mode != pause`;
- local deterministic critique не построен;
- нет valid `frameId` и current pause state;
- offloading feature disabled/config missing;
- сеть недоступна или transport policy запрещает запрос;
- request относится к устаревшему кадру;
- privacy policy для выбранного tier не выполнена.

### Positive triggers

В `PR-H12` разрешены только следующие trigger reasons:

1. `explicit_user_request`
- пользователь явно запросил deeper analysis;
- единственный trigger, который может разрешить `redacted_visual`.

2. `ambiguous_local_case`
- local critique usable, но top findings находятся в неуверенной зоне;
- baseline heuristic: top issue/confidence или fused confidence в диапазоне `0.35 ... 0.65`.

3. `fusion_disagreement_probe`
- local deterministic and local neural paths дали заметно конфликтующий сигнал;
- пример: deterministic issue высокий при слабой нейронной поддержке или наоборот.

4. `partial_local_failure`
- local pause verdict построен, но часть optional hybrid layers недоступна;
- пример: several heads `unavailable`, timeout в local neural path, missing richer explanation path.

5. `eval_sampling`
- debug/eval-only sampling для research runs;
- не должен быть включен в production auto path по умолчанию.

### Blockers even after trigger

Даже если trigger сработал, offloading должен быть заблокирован, если:
- battery/network policy запрещает background remote work;
- provider не поддерживает выбранный privacy tier;
- тот же `frameId + localSummaryId + trigger` уже недавно offload-ился и cache policy запрещает повтор;
- требуется visual tier, но пользователь его не разрешил;
- payload sanitation не может гарантировать redaction requirements.

### Baseline trigger policy

Канонический baseline для automatic offloading:
- `pause` only;
- только `structured_only`;
- только при `ambiguous_local_case`, `fusion_disagreement_probe` или `partial_local_failure`;
- не чаще одного active request на текущий `frameId`;
- without blocking first paint local pause card.

Канонический baseline для explicit deeper analysis:
- `pause` only;
- можно использовать `structured_only` или `redacted_visual`;
- request запускается только по текущему кадру, а не по потоку кадров;
- response применяется только если пользователь все еще находится на этом pause state.

## Privacy Tiers

### `structured_only`

Разрешено:
- scene/subject context;
- structured critique;
- structured recommendation plan;
- selected explainability excerpt;
- optional `NeuralEvidenceSnapshot`;
- coarse affected-region semantics без исходного пиксельного кадра.

Запрещено:
- raw image bytes;
- video sequence;
- audio;
- full EXIF;
- account/user identifiers;
- stable face embeddings;
- GPS/location metadata;
- free-form device logs.

Policy:
- это default tier для automatic offloading;
- он не требует передачи изображения;
- он должен быть первым выбором, если задача решается без visual attachment.

### `redacted_visual`

Дополнительно разрешено:
- один still frame в downscaled/redacted виде;
- optional subject crop, если он уже существует локально и проходит redaction policy.

Обязательные ограничения:
- long edge не больше `1024 px`;
- без EXIF/original filename;
- только still image, не burst и не video;
- bystander areas должны быть скрыты, если redaction pipeline умеет это гарантировать;
- visual attachment передается только вместе со structured payload, а не вместо него.

Policy:
- разрешен только по `explicit_user_request`;
- должен быть clearly distinguishable в telemetry и consent state;
- если redaction невозможен, tier понижается до `structured_only` или запрос отменяется.

### Forbidden in `PR-H12`

Запрещено:
- continuous live streaming;
- background uploading без локально построенного baseline result;
- full-resolution original frame;
- history of previous frames;
- persistent user profile or preference history;
- любые raw prompt chains/hidden system prompts, не нужные remote critic-у.

## Service-Level Contract

```text
DeepCriticOffloadRequest
- requestId: String
- frameId: String
- mode: AnalysisMode                     // must be pause
- locale: String
- trigger: DeepCriticTrigger
- preferredPrivacyTier: DeepCriticPrivacyTier
- localBundle: DeepCriticLocalBundle
- constraints: DeepCriticConstraints
- correlation: DeepCriticCorrelation

DeepCriticTrigger
- explicit_user_request
- ambiguous_local_case
- fusion_disagreement_probe
- partial_local_failure
- eval_sampling

DeepCriticPrivacyTier
- structured_only
- redacted_visual

DeepCriticConstraints
- maxLatencyMs: Int                      // default 2500, hard cap 4000 for auto path
- allowTextRefinement: Bool             // default false for automatic offloading; may be true only under explicit policy
- allowTeacherEvidence: Bool            // false by default; debug/eval-only unless explicitly enabled by research build policy
- allowActionReorderingAdvice: Bool     // default false; action advice remains optional and non-authoritative

DeepCriticCorrelation
- localCritiqueSummaryId: String
- localPlanSummaryId: String?
- localNeuralBundleVersion: String?
- sessionEphemeralId: String

DeepCriticOffloadOutcome
- disabled
- notTriggered
- blocked
- completed(response)
- failed(failure)
```

Нормативные правила:
- `mode` всегда должен быть `pause`;
- `sessionEphemeralId` не может быть stable user identifier;
- request-side policy flags являются enforceable contract, а не best-effort hint:
  - если `allowTextRefinement == false`, response не имеет права materialize-ить `explanationPatch`;
  - если `allowTeacherEvidence == false`, response не имеет права materialize-ить `teacherEvidence` и `teacherEvidenceMetadata`;
  - если `allowActionReorderingAdvice == false`, response не имеет права materialize-ить non-empty `actionReviews`;
- `disabled` используется только для feature-level opt-out:
  - offloading build/profile выключен;
  - provider не сконфигурирован;
  - remote path глобально запрещен product/runtime policy;
- `notTriggered` используется только когда remote path еще не должен стартовать:
  - `mode != pause`;
  - local deterministic critique еще не построен;
  - нет valid `frameId` или current pause state missing;
  - current pause state уже устарел до начала trigger evaluation;
  - не сработал ни один positive trigger;
- `blocked` используется только когда trigger/request уже есть, но dispatch запрещен до provider call:
  - сеть недоступна;
  - privacy tier не разрешен;
  - visual consent отсутствует;
  - provider capability mismatch обнаружен до dispatch;
  - debounce/cache policy запрещает повтор;
- `blocked` означает, что trigger был или request был requested, но privacy/capability/policy не позволили старт;
- `failed` означает, что remote execution был начат, но transport/runtime/validation завершились неуспехом;
- `failed` используется для:
  - timeout;
  - transport/runtime error;
  - provider returned `refused` or `unavailable`;
  - validation failure after response receipt;
- ни `blocked`, ни `failed` не меняют уже опубликованный local result.

### Canonical Outcome Mapping

| Runtime case | Required outcome |
| --- | --- |
| offloading feature disabled / provider not configured | `disabled` |
| `mode != pause` | `notTriggered` |
| local deterministic critique not built yet | `notTriggered` |
| invalid `frameId` / current pause state missing | `notTriggered` |
| stale frame before trigger evaluation | `notTriggered` |
| no positive trigger matched | `notTriggered` |
| no network before dispatch | `blocked` |
| privacy tier denied / missing consent | `blocked` |
| provider cannot serve chosen tier before dispatch | `blocked` |
| cache/debounce veto | `blocked` |
| request dispatched, then timeout | `failed(timeout)` |
| request dispatched, then transport/runtime error | `failed(transport_error)` |
| request dispatched, response returned `refused` | `failed(policy_refused)` |
| request dispatched, response returned `unavailable` | `failed(capability_mismatch)` by default, otherwise `failed(unknown)` |
| request dispatched, response validation failed | `failed(validation_failed)` |
| request dispatched, validated advisory returned | `completed(response)` |

## Local Bundle Contract

`DeepCriticLocalBundle` описывает то, что orchestration layer может использовать до sanitation:

```text
DeepCriticLocalBundle
- semantics: SceneSemanticsReport
- critique: CritiqueReport
- plan: RecommendationPlan
- fusedNeuralEvidence: NeuralEvidenceSnapshot?
- neuralMetadata: NeuralEvidenceRuntimeMetadata?
- traceExcerpt: DeepCriticTraceExcerpt?
- visualAttachmentCandidate: DeepCriticVisualAttachmentCandidate?

DeepCriticTraceExcerpt
- observations: [DeepCriticTraceFact]
- interpretations: [DeepCriticTraceFact]
- recommendations: [DeepCriticTraceFact]

DeepCriticTraceFact
- refId: String
- kind: String
- message: String

DeepCriticVisualAttachmentCandidate
- kind: frame | subject_crop
- pixelWidth: Int
- pixelHeight: Int
- hasExif: Bool
- bytes: Binary
```

Нормативные правила:
- `DeepCriticLocalBundle` не является wire payload и не отправляется как есть;
- provider никогда не должен получать полный local object graph без privacy filter;
- `traceExcerpt` должен быть bounded и содержать только факты, полезные для review, а не весь debug dump.

## Transport Envelope

Wire contract для remote provider-а:

```text
DeepCriticTransportEnvelope
- schemaVersion: String                  // example: "h12.v1"
- requestId: String
- frameId: String
- locale: String
- trigger: DeepCriticTrigger
- privacyTier: DeepCriticPrivacyTier
- payload: DeepCriticStructuredPayload
- visualAttachment: DeepCriticVisualAttachment?
- constraints: DeepCriticConstraints

DeepCriticStructuredPayload
- sceneContext: DeepCriticSceneContext
- critiqueSummary: DeepCriticCritiqueSummary
- issues: [DeepCriticIssuePayload]
- strengths: [DeepCriticStrengthPayload]
- actions: [DeepCriticActionPayload]
- neuralEvidence: NeuralEvidenceSnapshot?
- traceExcerpt: DeepCriticTraceExcerpt?

DeepCriticSceneContext
- sceneTypeId: String
- primarySubjectKind: String
- primarySubjectConfidence: Double

DeepCriticCritiqueSummary
- verdict: String
- shortVerdict: String
- whyGood: [String]
- whyProblematic: [String]
- fallbackUsed: Bool

DeepCriticIssuePayload
- issueId: String
- issueType: String
- severity: String
- confidence: Double
- affectedRegionKind: String?

DeepCriticStrengthPayload
- strengthId: String
- strengthType: String
- confidence: Double

DeepCriticActionPayload
- actionId: String
- actionType: String
- priority: Int
- targetRegionKind: String?

DeepCriticVisualAttachment
- attachmentKind: redacted_frame | redacted_subject_crop
- mimeType: String
- width: Int
- height: Int
- redactionProfile: String
- payloadRef: Binary | URL-like transport handle
```

Нормативные правила:
- `payload.neuralEvidence`, если присутствует, обязан соответствовать [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md) без отдельного remote fork;
- transport envelope не может содержать `FrameFeatureSnapshot`, raw detector arrays или full device/runtime logs;
- `traceExcerpt.message` допускается только в пределах bounded local excerpt и не должен включать произвольные hidden prompts;
- `visualAttachment == nil` обязательно при `privacyTier = structured_only`;
- если `visualAttachment` присутствует, `privacyTier` обязан быть `redacted_visual`.

## Response Contract

Remote critic не возвращает новый canonical `CritiqueReport`. Он возвращает advisory response:

```text
DeepCriticResponse
- schemaVersion: String
- responseId: String
- requestId: String
- frameId: String
- status: DeepCriticResponseStatus
- advisory: DeepCriticAdvisory?
- failureReason: DeepCriticFailureReason?
- producedAt: Date

DeepCriticResponseStatus
- completed
- refused
- unavailable

DeepCriticFailureReason
- policy_refused
- capability_mismatch
- timeout
- transport_error
- validation_failed
- unknown

DeepCriticAdvisory
- disposition: DeepCriticDisposition
- issueReviews: [DeepCriticFindingReview]
- strengthReviews: [DeepCriticFindingReview]
- actionReviews: [DeepCriticActionReview]
- explanationPatch: DeepCriticExplanationPatch?
- teacherEvidence: NeuralEvidenceSnapshot?
- teacherEvidenceMetadata: NeuralEvidenceRuntimeMetadata?
- hardCaseTags: [String]
- confidence: Double

DeepCriticDisposition
- no_change
- advisory_refinement
- advisory_disagreement
- hard_case_flag

DeepCriticFindingReview
- targetId: String
- targetKind: issue | strength
- verdict: reinforce | soften | unclear
- suggestedDelta: Double?               // bounded range: -0.15 ... 0.15
- rationale: String
- evidenceRefs: [String]

DeepCriticActionReview
- actionId: String
- verdict: reinforce | deprioritize | unclear
- rationale: String
- evidenceRefs: [String]

DeepCriticExplanationPatch
- shortVerdictOverride: String?
- whyGoodByStrengthId: [ExplanationPatchEntry]
- whyProblematicByIssueId: [ExplanationPatchEntry]
- actionRationaleByActionId: [ExplanationPatchEntry]

ExplanationPatchEntry
- targetId: String
- text: String
```

Нормативные правила:
- `DeepCriticAdvisory` не может invent-ить новые taxonomy IDs;
- `targetId` и `actionId` обязаны ссылаться только на уже существующие local IDs;
- `teacherEvidence`, если присутствует, обязан использовать тот же `NeuralEvidenceSnapshot` contract, а не новый remote-only shape;
- `teacherEvidenceMetadata` обязательно, если присутствует `teacherEvidence`;
- `teacherEvidenceMetadata.providerKind == remote_teacher` и `inferenceTarget == offloaded` обязательны;
- `teacherEvidenceMetadata.frameId` и `mode` обязаны совпадать с request;
- `suggestedDelta` advisory-only и не может автоматически мутировать local critique без отдельного downstream policy;
- `shortVerdictOverride` не может менять verdict class `good/mixed/needs_fix`, только формулировку;
- при `status != completed` поле `advisory` обязано быть `nil`.
- если `request.constraints.allowTextRefinement == false`, `advisory.explanationPatch` обязан быть `nil`;
- если `request.constraints.allowTeacherEvidence == false`, `advisory.teacherEvidence` и `advisory.teacherEvidenceMetadata` обязаны быть `nil`;
- если `request.constraints.allowActionReorderingAdvice == false`, `advisory.actionReviews` обязан быть пустым.

## Remote Text Safety Contract

Если `explanationPatch` разрешен, он обязан проходить те же смысловые guardrails, что и text refinement из [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md):

1. ID integrity
- каждый patch entry может ссылаться только на уже существующие `strengthId`, `issueId` или `actionId` из request payload;
- `shortVerdictOverride` разрешен только при сохранении того же verdict class.

2. Length and shape limits
- максимум `1-2` предложения на элемент;
- hard limit `<= 180` символов на элемент;
- пустой после `trim` текст запрещен.

3. Supported evidence references
- `evidenceRefs` могут ссылаться только на:
  - `DeepCriticTraceFact.refId` из `traceExcerpt`;
  - существующие local `issueId`, `strengthId`, `actionId`;
  - canonical neural head refs вида `neural.<headId>` только если соответствующий head присутствует в `payload.neuralEvidence` со статусом `available`;
- любые неизвестные или synthetic refs должны приводить к validation failure.

4. Faithfulness
- нельзя вводить новую причинно-следственную связь, которой нет в local `critique/plan/traceExcerpt/neuralEvidence`;
- нельзя усиливать уверенность формулировки выше local `confidence`/`verdictConfidence` envelope;
- нельзя подменять deterministic rationale новым remote explanation, если она не поддержана `evidenceRefs`.

5. Reject policy
- `low_faithfulness` всегда ведет к full reject всего remote response;
- partial accept на уровне отдельных `ExplanationPatchEntry` запрещен;
- для non-faithfulness structural violations (`empty`, `too_long`, `unsupported_evidenceRefs`) validator обязан отбросить весь `explanationPatch` целиком, а не отдельные его элементы;
- никакой user-facing remote text не применяется без успешной ID-level и faithfulness validation.

## Role of Remote Critic

### Что remote critic может делать

- перепроверять already-built local findings;
- давать bounded advisory о том, какие existing issues/strengths выглядят более или менее убедительными;
- помогать с richer pause explanation text;
- возвращать optional `teacherEvidence` только для debug/eval/prototype flows;
- помечать hard-case scenarios для исследования и telemetry.

### Что remote critic не может делать

- быть единственным источником pause verdict;
- генерировать новый `CritiqueReport` как authoritative replacement;
- invent-ить новые issue/action types;
- silently удалять local findings;
- быть обязательным условием для полезного pause UX;
- участвовать в `live` path.

### `teacherEvidence` enablement policy

`teacherEvidence` в `PR-H12` считается non-baseline path:
- default: `allowTeacherEvidence = false`;
- automatic production offloading обязан держать `allowTeacherEvidence = false`;
- включение разрешено только для:
  - `eval_sampling`;
  - debug/research build profile;
  - explicit prototype flows в `PR-H13+`, где provenance logging уже реализован;
- `teacherEvidence` не должен напрямую попадать в user-facing pause UI в `PR-H12`;
- любой downstream, который сохраняет `teacherEvidence`, обязан сохранять рядом `teacherEvidenceMetadata` как provenance sidecar.

### Coexistence with `ReasoningProvider`

`PR-H12` не переоткрывает ownership pause text refinement из [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md):
- baseline owner user-facing pause text refinement: `ReasoningProvider`;
- baseline owner remote advisory/deep-review sidecar: `DeepCriticProvider`.

Каноническая precedence policy:
1. deterministic pause card публикуется первой;
2. если для текущего pause state активен `ReasoningProvider`, он остается единственным разрешенным mutator-ом user-facing pause text;
3. при активном `ReasoningProvider` offloading request обязан выставлять `allowTextRefinement = false`;
4. `DeepCriticProvider` в этом случае может возвращать только advisory review/debug sidecar;
5. `DeepCriticProvider` может refine-ить user-facing pause text только если:
   - `ReasoningProvider` отсутствует или policy-disabled для текущего `frameId`;
   - request явно выставляет `allowTextRefinement = true`;
   - response проходит весь `Remote Text Safety Contract`.

Нормативные следствия:
- два refine path-а не могут одновременно мутировать один и тот же pause text;
- stacking patches `ReasoningProvider -> DeepCriticProvider` в `PR-H12` запрещен;
- `DeepCriticProvider` не добавляет `optional_reasoning` items в primary explainability bundle `PR-H12`; его текстовый вклад остается presentation-level patch only.

### Application Policy

В `PR-H12` remote response разрешено применять только так:
- как async advisory panel;
- как optional text refinement поверх уже показанного local pause explanation только при `allowTextRefinement == true` и отсутствии активного `ReasoningProvider` для этого `frameId`;
- как debug/eval sidecar для disagreement analysis;
- как input для future `PR-H13`, но не как новый baseline contract.

Следствие:
- local `RecommendationPlan.primaryAction` остается authoritative;
- local `CritiqueReport.verdict` остается authoritative;
- если ответ пришел поздно или не прошел validation, он silently drop-ается без поломки UI state.

## Validation and Safety Policy

Validator использует двухуровневую политику:

1. `field drop`
- разрешен только для optional field-ов:
  - `explanationPatch`, если request прямо запрещал его через `allowTextRefinement == false`;
  - `explanationPatch`, если у него structural violations без `low_faithfulness`;
  - `teacherEvidence` + `teacherEvidenceMetadata`, если request прямо запрещал их через `allowTeacherEvidence == false`;
  - `actionReviews`, если request прямо запрещал их через `allowActionReorderingAdvice == false`;
- после `field drop` validator обязан проверить, что в response остается хотя бы один usable advisory field, иначе response становится `failed(validation_failed)`.

2. `full reject`
- обязателен для request/response mismatch, unknown IDs, out-of-range deltas, `low_faithfulness`, invalid `teacherEvidence` provenance и stale pause state;
- приводит к `failed(validation_failed)`.

Ответ remote critic-а должен быть rejected, если:
- `requestId` или `frameId` не совпадают;
- response пытается сослаться на неизвестные `issueId/strengthId/actionId`;
- `suggestedDelta` выходит за `-0.15 ... 0.15`;
- `teacherEvidence` нарушает `PR-H06` invariants;
- присутствует `teacherEvidence` без `teacherEvidenceMetadata`;
- `teacherEvidenceMetadata.providerKind != remote_teacher` или `inferenceTarget != offloaded`;
- explanation patch мутирует verdict class или invent-ит новый action;
- зафиксирован `low_faithfulness` explanation patch-а относительно local trace/evidence;
- response пришел для уже неактуального pause state.

Global guarantees:
- `failed(validation_failed)` используется только для full reject cases или если после разрешенного `field drop` не осталось usable advisory content;
- `field drop` не считается partial accept на уровне отдельных patch entries: optional field применяется целиком или отбрасывается целиком;
- никакой remote текст не должен попадать в UI без ID-level consistency checks;
- никакой remote текст не должен попадать в UI без faithfulness checks уровня `PR-012/013`;
- UX не обязан показывать пользователю transport/server error banner в baseline `PR-H12`.

## Timeout, Concurrency and Caching

Baseline policy:
- default timeout `2500 ms`;
- hard cap `4000 ms` для auto path;
- для `explicit_user_request` допустим cap `6000 ms`, если UX явно ждет deeper analysis;
- один active remote request на актуальный `frameId`;
- при выходе из pause state request отменяется или результат игнорируется;
- cache допускается по ключу:
  - `cacheKey = hash(frameId + localCritiqueSummaryId + trigger + privacyTier + providerId)`.

Нормативные правила:
- cache не может переживать schema-incompatible version bump;
- cached remote response нельзя применять к новому `frameId`, даже если визуально кадры похожи;
- timeout/failure не должны переводить local pipeline в legacy fallback.

## Fallback Policy

Для пользователя canonical behavior всегда такой:

1. local pause critique строится и показывается сразу;
2. offloading при необходимости запускается в фоне;
3. при `disabled`, `notTriggered` или `blocked` пользователь остается на local result;
4. при `failed` пользователь остается на local result;
5. при `completed` validated response может только дополнить текущий pause screen.

Следствие:
- отсутствие сети никогда не должно означать отсутствие pause verdict;
- regression в remote path не должен ломать deterministic/hybrid local baseline;
- offloading не имеет права стать hidden dependency для thesis demo.

## Payload Examples

### Example A. Automatic structured-only request

```text
DeepCriticTransportEnvelope
- schemaVersion: "h12.v1"
- requestId: "req_8F1C"
- frameId: "frame_247"
- locale: "ru-RU"
- trigger: ambiguous_local_case
- privacyTier: structured_only
- payload.sceneContext.sceneTypeId: "single_character_medium"
- payload.sceneContext.primarySubjectKind: "person"
- payload.critiqueSummary.verdict: "mixed"
- payload.issues:
  - { issueId: "issue_1", issueType: "subject_not_prominent_enough", severity: "medium", confidence: 0.54 }
  - { issueId: "issue_2", issueType: "background_competes_with_subject", severity: "medium", confidence: 0.51 }
- payload.actions:
  - { actionId: "action_1", actionType: "move_closer", priority: 0 }
- payload.neuralEvidence: present
- visualAttachment: nil
```

Ожидаемое применение:
- remote critic может вернуть `advisory_refinement` или `advisory_disagreement`;
- local pause card уже показан до ответа.

### Example B. Explicit deeper analysis with redacted visual

```text
DeepCriticTransportEnvelope
- schemaVersion: "h12.v1"
- requestId: "req_9A22"
- frameId: "frame_302"
- locale: "ru-RU"
- trigger: explicit_user_request
- privacyTier: redacted_visual
- payload.sceneContext.sceneTypeId: "moody_backlit_subject"
- payload.critiqueSummary.verdict: "needs_fix"
- payload.issues:
  - { issueId: "issue_5", issueType: "backlight_hides_subject", severity: "high", confidence: 0.72 }
- payload.actions:
  - { actionId: "action_3", actionType: "turn_subject_toward_light", priority: 0 }
- visualAttachment:
  - attachmentKind: redacted_frame
  - mimeType: "image/jpeg"
  - width: 1024
  - height: 576
  - redactionProfile: "subject_focus_v1"
```

Ожидаемое применение:
- remote critic может прислать richer rationale и optional text patch;
- verdict class и local action taxonomy остаются теми же.

## Invariants

- offloading никогда не стартует в `live`.
- local pause result всегда строится раньше remote path.
- `DeepCriticTransportEnvelope.visualAttachment == nil` при `structured_only`.
- `redacted_visual` невозможен без `explicit_user_request`.
- response не может ссылаться на local IDs, которых не было в request payload.
- remote critic не может вернуть новый canonical `CritiqueReport`.
- `teacherEvidence`, если присутствует, проходит те же invariants, что и local `NeuralEvidenceSnapshot`.
- timeout, capability mismatch и validation failure не меняют local verdict/action choice.
- `sessionEphemeralId` и `frameId` не должны быть persistent user identifiers.
- offloading transport не должен содержать GPS, EXIF, audio, video sequence или account identifiers.

## Minimal Test Matrix

1. `pause_only_gate`
Проверяет, что любой `live` request блокируется до transport stage.

2. `structured_only_sanitization`
Проверяет, что automatic request не содержит visual attachment и privacy-sensitive fields.

3. `explicit_visual_requires_consent`
Проверяет, что `redacted_visual` не может быть выбран без explicit trigger.

4. `response_id_alignment`
Проверяет совпадение `requestId/frameId` и drop чужих response.

5. `unknown_target_rejection`
Проверяет reject response с неизвестным `issueId/actionId`.

6. `delta_range_validation`
Проверяет reject response с `suggestedDelta` вне допустимого диапазона.

7. `local_fallback_on_timeout`
Проверяет, что timeout не ломает local pause presentation.

8. `teacher_evidence_contract_bridge`
Проверяет, что optional `teacherEvidence` валидируется по `PR-H06` и требует `teacherEvidenceMetadata` с `providerKind = remote_teacher`.

9. `stale_pause_state_drop`
Проверяет, что ответ для уже покинутого pause state не применяется.

10. `cache_key_safety`
Проверяет, что cached response не переиспользуется для другого `frameId` или privacy tier.

11. `outcome_mapping_consistency`
Проверяет canonical mapping для `mode != pause`, no network, capability mismatch, stale frame, timeout и validation failure.

12. `remote_text_faithfulness_reject`
Проверяет, что unsupported `evidenceRefs` или `low_faithfulness` приводят к full reject.

13. `request_constraint_enforcement`
Проверяет, что `explanationPatch`, `teacherEvidence` и `actionReviews` отбрасываются или reject-ятся согласно `allow*` flags из request.

14. `reasoning_provider_precedence`
Проверяет, что при активном `ReasoningProvider` offloading request всегда выставляет `allowTextRefinement = false`, а `DeepCriticProvider` не мутирует тот же pause text.

## Что это разблокирует дальше

После фиксации этого документа:
- `PR-H13` может реализовать server/teacher critic prototype без споров о trigger/privacy boundaries;
- `PR-H14` может мерить uplift и disagreement отдельно для `structured_only` и `redacted_visual` path;
- `PR-H15` может логировать offloading decisions и hard cases на стабильном outcome contract;
- thesis/demo narrative может честно показывать optional deep-analysis branch без подмены offline-first baseline.

## Definition of Done

`PR-H12` считается закрытым в `design` mode, если:
- trigger policy и blockers формализованы;
- payload schema достаточно точна для transport implementation;
- privacy boundaries и forbidden data перечислены явно;
- роль remote critic bounded и не конфликтует с local source-of-truth;
- fallback и validation policy сохраняют baseline UX при любом remote failure.
