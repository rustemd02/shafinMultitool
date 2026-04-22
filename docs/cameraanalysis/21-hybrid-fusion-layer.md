# 21. Hybrid Fusion Layer (PR-H09)

Статус: design spec + design verify (ready for implement)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md)
- [FrameCritiqueEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)

## Цель

Зафиксировать explainable fusion design для `PR-H09` так, чтобы:
- deterministic critique core оставался source-of-truth для `issues`, `strengths`, `verdict` label и fallback path;
- neural evidence мог ограниченно калибровать confidence и внутренний ranking уже материализованных finding-ов;
- влияние neural layer было повторяемым на тестах и объяснимым через trace;
- `PR-H10` мог затем отдельно заняться reranking действий, не переоткрывая базовый fusion contract.

Этот документ закрывает design-часть `PR-H09` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Scope

`PR-H09` отвечает за:
- service-level contract для bounded fusion между `CritiqueReport` и `NeuralEvidenceSnapshot`;
- weighting policy по mode, head confidence и target finding type;
- правила, когда neural evidence может менять `confidence` и порядок finding-ов;
- explainability bridge для fused interpretation;
- degraded и failure behavior;
- golden/degraded test matrix.

`PR-H09` не отвечает за:
- обучение модели и shape raw outputs;
- cadence policy и provider orchestration;
- изменение deterministic detector formulas из [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md);
- переписывание `SceneTypeClassifier`;
- финальный reranking `RecommendationPlan` actions из `PR-H10`;
- server/offloading path.

## Design Summary

Ключевая формула `PR-H09`:

`deterministic critique -> bounded neural calibration -> fused critique -> unchanged planner contract`

Из нее следуют обязательные правила:
- fusion применяется после deterministic `FrameCritiqueEngine`, а не вместо него;
- набор `IssueTypeV1` / `StrengthTypeV1` не расширяется;
- `verdict` label не меняется neural layer-ом в `PR-H09`;
- fusion может менять только:
  - `FrameIssue.confidence`
  - `FrameStrength.confidence`
  - порядок `issues` и `strengths` внутри отчета
  - `CritiqueSummary.whyGood` / `whyProblematic` через deterministic rebuild from fused findings
  - explainability metadata для fused findings
- `severity`, `affectedRegion`, `suggestedFixTypes`, `summary.id` и taxonomy IDs остаются deterministic;
- если neural evidence отсутствует, skipped или failed, downstream получает deterministic critique без shape drift;
- `cinematic_expressiveness` в `PR-H09` остается debug/eval-only observation и не участвует в decision path.

## Архитектурное положение

Высокоуровневая hybrid-схема из [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md) показывает fusion как отдельный слой. Для implementation scope `PR-H09` authoritative sequencing такое:

1. deterministic feature pipeline
2. scene semantics
3. deterministic `FrameCritiqueEngine`
4. `HybridFusionService`
5. existing `RecommendationPlanner`

Причина:
- к моменту `PR-H09` deterministic critique core уже заморожен и покрыт тестами;
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md) описывает роль neural layer как bounded calibration system;
- такой placement не размывает границу ответственности между `PR-007`, `PR-H09` и `PR-H10`.

## Runtime Roles

### 1. `HybridFusionService`

Главный orchestration layer, который:
- принимает deterministic critique и optional neural snapshot;
- фильтрует разрешенные heads по mode и degraded policy;
- считает bounded deltas для already-materialized findings;
- перестраивает ordering finding-ов;
- детерминированно пересобирает summary sections, если fused ordering реально изменился;
- выпускает explainable fusion decisions.

### 2. `FindingFusionScorer`

Чистая детерминированная логика, которая:
- знает mapping `finding type -> eligible heads`;
- нормализует polarity (`low score is bad` / `high score is bad`);
- применяет confidence multipliers и mode caps;
- выдает signed delta для конкретного finding-а.

### 3. `FusionTraceMaterializer`

Слой, который:
- переводит использованные head outputs в `neural_evidence` observation items;
- добавляет `deterministic_rule` interpretation items с fusion metadata;
- не позволяет recommendation item-ам зависеть напрямую от `neural_evidence`.

## Service-Level Contract

```text
HybridFusionInput
- snapshot: FrameFeatureSnapshot
- semantics: SceneSemanticsReport
- critique: CritiqueReport
- neuralSnapshot: NeuralEvidenceSnapshot?
- neuralMetadata: NeuralEvidenceRuntimeMetadata?

HybridFusionDecision
- decisionId: String
- targetKind: issue | strength
- targetId: String
- targetType: String
- outcome: unchanged | reinforced | softened | ignored
- delta: Double                       // signed, bounded by mode cap
- appliedHeadIds: [EvidenceHeadId]
- note: String

HybridFusionOutput
- critique: CritiqueReport
- decisions: [HybridFusionDecision]
```

Нормативные правила:
- `HybridFusionInput.critique` уже обязан проходить validation `PR-002/PR-007`;
- `HybridFusionOutput.critique.frameId == input.critique.frameId`;
- если `neuralSnapshot == nil`, output critique обязан быть byte-equivalent deterministic input report-у по всем полям, включая `traceRefs`;
- `HybridFusionDecision` materialize-ится только для реально рассмотренных targets;
- если delta не применен из-за gating, `outcome = ignored`, а `delta = 0`.

Следствие fallback invariants:
- debug/eval serialization для skipped/failed/missing neural path живет вне `CritiqueReport`, а не через мутацию `traceRefs` или других user-facing полей;
- exact deterministic fallback важнее convenience debug annotations inside critique object.

## Eligible Neural Heads

### By mode

`live` может использовать только:
- `subject_prominence`
- `background_clutter`
- `lighting_quality`
- `face_saliency`

`pause` дополнительно может использовать:
- `balance_confidence`
- `depth_separation`
- `shot_type_confidence`

`pause` не использует для decision path:
- `cinematic_expressiveness`

### By status

Head участвует во fusion только если:
- `status == available`
- head разрешен для текущего `mode`
- head не исключен degraded policy

При `status in {not_applicable, unavailable}`:
- head не участвует во fusion;
- для compact runtime path можно не materialize-ить trace item;
- debug/eval path должен оставаться восстановимым из `NeuralEvidenceSnapshot`.

## Confidence Gates

### Confidence bands

| Head confidence | Policy |
| --- | --- |
| `0.00 ... 0.24` | ignore |
| `0.25 ... 0.44` | tie-break only in `pause`; ignore in `live` |
| `0.45 ... 0.64` | bounded pause-grade fusion |
| `0.65 ... 1.00` | normal fusion; minimal level for `live` |

### Multipliers

`confidenceMultiplier`:
- `0.35` for `0.25 ... 0.44`
- `0.70` for `0.45 ... 0.64`
- `1.00` for `0.65 ... 1.00`

`roleWeight`:
- `1.00` for primary head
- `0.60` for secondary head
- `0.35` for contextual head

`modeCap`:
- `live`: `0.10`
- `pause`: `0.18`
- `degraded`: `0.08`

Контекстные heads:
- не могут в одиночку поменять sign delta;
- не могут дать абсолютный вклад больше `0.05` даже в `pause`.

## Delta Formula

Для каждого finding-а сначала считается `supportScore_i` в диапазоне `0...1`, где:
- `1.0` значит "head поддерживает finding";
- `0.0` значит "head спорит с finding";
- `0.5` значит "нейтрально".

Дальше:

```text
centered_i = (supportScore_i - 0.5) * 2.0      // -1 ... 1
weighted_i = centered_i * roleWeight_i * confidenceMultiplier_i
normalized = clamp(-1, 1, sum(weighted_i) / max(1.0, sum(abs(roleWeight_i))))
delta = modeCap * normalized
fusedConfidence = clamp01(deterministicConfidence + delta)
```

Нормативные правила:
- delta считается отдельно для каждого finding-а;
- если у finding-а нет ни одного eligible head, `delta = 0`;
- `live` допускает только bounded calibration, не promotion;
- `pause` в `PR-H09` тоже не materialize-ит новые issue/strength types: fusion работает только с уже существующими findings;
- deterministic finding не удаляется из отчета из-за отрицательного delta;
- если `abs(delta) < 0.03`, finding считается effectively unchanged для ranking и user-facing trace.

Это означает:
- neural layer может усиливать или ослаблять уже найденную проблему/силу;
- но не может незаметно превратить систему в новый critic.

## Finding-Level Mapping

### Issues

| `IssueTypeV1` | Primary heads | Secondary heads | Contextual heads | Support polarity |
| --- | --- | --- | --- | --- |
| `subject_too_close_to_edge` | `live`: `face_saliency` | `pause`: `subject_prominence` | `pause`: `balance_confidence`, `shot_type_confidence` | low `face_saliency` / low `subject_prominence` / low `balance_confidence` support issue; `two_character_frame` and `establishing_like_frame` affinities can only weakly soften |
| `subject_not_prominent_enough` | `subject_prominence` | `background_clutter`, `face_saliency` | `pause`: `depth_separation` | low prominence, high clutter, low saliency, low depth support issue |
| `background_competes_with_subject` | `background_clutter` | `subject_prominence` | `pause`: `depth_separation` | high clutter, low prominence, low depth support issue |
| `insufficient_look_space` | `live`: `face_saliency` | `pause`: `subject_prominence` | `pause`: `balance_confidence`, `shot_type_confidence` | low saliency / low prominence / low balance support issue; person-centric shot affinities weakly reinforce, object-centric affinities weakly soften |
| `backlight_hides_subject` | `lighting_quality` | `face_saliency` | `pause`: `depth_separation`, `shot_type_confidence` | low lighting, low saliency, low depth support issue; `moody_backlit_subject_affinity` can soften by at most `0.05` |
| `scene_has_no_clear_focus` | `subject_prominence`, `background_clutter` | none | `pause`: `balance_confidence` | low prominence, high clutter, low balance support issue |
| `frame_visually_overloaded` | `background_clutter` | `subject_prominence` | `pause`: `balance_confidence` | high clutter, low prominence, low balance support issue |
| `horizon_distracts` | none | none | `pause`: `balance_confidence` | low balance may only act as tie-break; max absolute delta `0.05` |

Дополнительные правила:
- `face_saliency` нельзя использовать, если head не person-centric по already-frozen applicability contract;
- `shot_type_confidence` не может перевыбрать `SceneTypeV1`, only weakly contextualize an already existing issue;
- для `subject_too_close_to_edge` и `insufficient_look_space` contextual shot affinities никогда не усиливают issue сильнее, чем геометрические deterministic сигналы уже сделали.

### Strengths

| `StrengthTypeV1` | Primary heads | Secondary heads | Contextual heads | Support polarity |
| --- | --- | --- | --- | --- |
| `good_subject_isolation` | `subject_prominence` | `background_clutter` | `pause`: `depth_separation` | high prominence, low clutter, high depth support strength |
| `good_light_emphasis` | `lighting_quality` | `face_saliency` | `pause`: `depth_separation` | high lighting, high saliency, high depth support strength |
| `clear_focus_hierarchy` | `subject_prominence` | `background_clutter` | `pause`: `balance_confidence` | high prominence, low clutter, high balance support strength |
| `stable_horizon_supports_scene` | none | none | `pause`: `balance_confidence` | high balance may only weakly reinforce; max absolute delta `0.05` |
| `balanced_composition_for_scene` | `pause`: `balance_confidence` | `live`: `face_saliency` | `pause`: `shot_type_confidence` | high balance and strong subject anchoring support strength; matching scene affinity is weak context only |

Ограничения по strengths:
- если deterministic critique находится в degraded mode (`fallbackUsed == true`), strengths всегда остаются пустыми;
- contextual heads не могут в одиночку сделать poor deterministic strength "хорошей";
- `cinematic_expressiveness` не участвует в strength generation в `PR-H09`.

## Ranking Policy

### Issues

Issue ordering после fusion:

```text
plannerEquivalentIssueSort = severity desc, then fusedConfidence desc, then IssueTypeV1.rawValue asc
```

Правила:
- severity остается primary ordering key exactly as in current `RecommendationPlanner`;
- fusion может менять relative order только внутри issues с одинаковой `severity`;
- внутри exact-severity tie issue с большей `fusedConfidence` поднимается выше;
- при полном tie сортировка остается по `IssueTypeV1.rawValue`.
- baseline `PR-H09` не вводит новый ranking formula, который расходится с current planner behavior.

### Strengths

Strength ordering после fusion:

```text
strengthRankScore = fusedConfidence
```

Правила:
- strengths можно переставлять только внутри уже существующего множества strengths;
- если `abs(delta) < 0.03`, relative order should stay deterministic.
- это влияет на critique summary / pause presentation / trace ordering, но не на `RecommendationPlanner`, который в текущем runtime не использует strengths order.

## Summary Consistency Policy

`verdict` label из deterministic critique не меняется.

Чтобы fusion не оставлял report во внутренне противоречивом состоянии:
- `summary.id` остается прежним deterministic ID;
- `summary.shortVerdict` остается тем же deterministic template для текущего `verdict`;
- `summary.whyGood` должен быть пересобран из top fused strengths по тому же deterministic template policy, что и в current `FrameCritiqueEngine`;
- `summary.whyProblematic` должен быть пересобран из top fused issues по тому же deterministic template policy;
- rebuild summary не добавляет новый neural prose: он только переиспользует уже существующие deterministic rationales finding-ов.

Нормативное следствие:
- issue reordering в `PR-H09` может влиять на planner только внутри exact-severity ties, потому что current `RecommendationPlanner` сортирует issues по `severity`, затем `confidence`;
- strength reordering в `PR-H09` не меняет planner behavior напрямую и остается critique/UI/trace concern.

## Verdict Confidence Policy

Baseline `PR-H09` не меняет `CritiqueReport.verdictConfidence`.

Причина verify:
- current deterministic calculator в [FrameCritiqueEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift) не использует per-finding confidences;
- значит формулировка "recalculate verdict confidence from fused finding confidences" была бы не implement-ready без скрытого redesign;
- чтобы не вводить неявный second judge, global verdict calibration выносится за рамки baseline `PR-H09`.

Следствия:
- calibration scope `PR-H09` = finding-level confidence calibration + ranking adaptation;
- `RecommendationPlan.planConfidence` в текущем runtime остается привязан к deterministic `verdictConfidence`;
- более широкий verdict-level calibration допустим только отдельным eval-backed follow-up после `PR-H09`.

## Degraded and Failure Policy

### Degraded mode

Если `critique.fallbackUsed == true` или active weak-signal degraded policy получен из deterministic path:
- `modeCap = 0.08`;
- pause-only heads `balance_confidence`, `depth_separation`, `shot_type_confidence` не участвуют в fused decision path;
- разрешены только live-grade heads:
  - `subject_prominence`
  - `background_clutter`
  - `lighting_quality`
  - `face_saliency`
- fusion может only calibrate these degraded-subset issues:
  - `backlight_hides_subject`
  - `subject_not_prominent_enough`
- `horizon_distracts` в degraded mode остается deterministic-only issue, потому что у baseline hybrid policy нет eligible degraded head для его calibration;
- strengths остаются пустыми;
- `verdict != good` и `verdictConfidence <= 0.55` сохраняются после fusion.

### Disabled / skipped / failed neural path

Если upstream outcome был `disabled`, `policySkipped` или `failed`:
- `HybridFusionService` не invent-ит synthetic neural disagreement;
- critique остается deterministic;
- можно записать debug decision с `outcome = ignored` и note explaining why nothing was applied;
- user-facing ranking и confidence не меняются.

## Explainability Policy

`PR-H09` обязан соблюдать bridge rules из [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md):

- каждый примененный head materialize-ится как `observation` item с `sourceKind = neural_evidence`;
- fused finding остается `interpretation` item с `sourceKind = deterministic_rule`;
- recommendation items продолжают зависеть только от interpretation items;
- raw neural observation не получает direct `TraceLink(kind: issue|strength|action)`.

### Required metadata for fused interpretation items

Если delta реально применен, interpretation item должен иметь metadata:
- `fusionApplied=true`
- `fusionDelta=<signed decimal>`
- `deterministicConfidenceBefore=<value>`
- `fusedConfidenceAfter=<value>`
- `appliedHeadIds=<comma-separated ids>`

### Canonical neural keys used by fusion

- `neural.<headId>.status`
- `neural.<headId>.score`
- `neural.<headId>.confidence`
- `neural.<headId>.supportingSignals`
- `neural.shot_type_confidence.affinities.<categoryId>`

### Live trace surface

Чтобы `PR-H09` не оставлял live path в неявном состоянии, baseline policy фиксируется так:
- `pause` обязан строить полноценный fused `ExplainabilityTraceBundle`;
- `live` не обязан публиковать отдельный expanded bundle в UI contract, но обязан уметь materialize-ить compact fused trace для debug/eval serialization;
- live compact fused trace строится только если хотя бы один neural delta реально применен;
- если live fusion ничего не изменил, runtime может оставить deterministic `traceRefs` без отдельного live fused bundle;
- live compact bundle должен оставаться в пределах current explainability guidance для `live` и содержать только:
  - использованные `neural_evidence` observations
  - fused deterministic interpretation items
  - summary item
  - recommendation item для текущего primary action, если action присутствует

Нормативное следствие:
- `PR-H09` не обязан перепроектировать live UI around full trace bundle;
- но implement обязан сохранить воспроизводимый debug/eval trail для всех реально примененных live fusion decisions.

## Before / After Examples

### Example A. Busy portrait in `pause`

Deterministic critique:
- issue `subject_not_prominent_enough`: `confidence = 0.58`
- issue `background_competes_with_subject`: `confidence = 0.61`

Neural evidence:
- `subject_prominence = 0.22`, `confidence = 0.84`
- `background_clutter = 0.81`, `confidence = 0.79`
- `depth_separation = 0.27`, `confidence = 0.68`

Fused result:
- `subject_not_prominent_enough.confidence: 0.58 -> 0.72`
- `background_competes_with_subject.confidence: 0.61 -> 0.70`
- ranking may swap only if these issues are tied on `severity`, because baseline planner-equivalent ordering still keeps `severity` as the primary key

Объяснение:
- neural heads reinforce an already existing readability failure;
- no new issue type is introduced.

### Example B. Moody backlit closeup in `pause`

Deterministic critique:
- issue `backlight_hides_subject`: `confidence = 0.69`

Neural evidence:
- `lighting_quality = 0.30`, `confidence = 0.82`
- `face_saliency = 0.32`, `confidence = 0.74`
- `shot_type_confidence.moody_backlit_subject_affinity = 0.76`, overall `confidence = 0.63`

Fused result:
- base evidence reinforces issue;
- contextual affinity softens it slightly;
- final confidence might become `0.69 -> 0.73`, but never `0.69 -> 0.40` or issue deletion

Объяснение:
- style prior is contextual only;
- it cannot erase a deterministic failure to read the face.

### Example C. Readable portrait with clean background in `pause`

Deterministic critique:
- strength `good_subject_isolation`: `confidence = 0.62`
- strength `clear_focus_hierarchy`: `confidence = 0.57`

Neural evidence:
- `subject_prominence = 0.87`, `confidence = 0.89`
- `background_clutter = 0.18`, `confidence = 0.80`
- `depth_separation = 0.79`, `confidence = 0.71`

Fused result:
- `good_subject_isolation.confidence: 0.62 -> 0.77`
- `clear_focus_hierarchy.confidence: 0.57 -> 0.69`
- `verdict` label stays `good`, while summary/trace may prefer these strengths more confidently

### Example D. Low-confidence live disagreement

Deterministic critique:
- issue `frame_visually_overloaded`: `confidence = 0.56`

Neural evidence:
- `background_clutter = 0.44`, `confidence = 0.39`

Fused result:
- no user-facing change
- optional debug decision: `ignored`

Объяснение:
- weak live-grade confidence is below fusion threshold for `live`.

### Example E. Degraded fallback frame

Deterministic critique:
- `fallbackUsed = true`
- issue `subject_not_prominent_enough`: `confidence = 0.43`
- strengths `[]`
- `verdict = mixed`, `verdictConfidence = 0.49`

Neural evidence:
- `depth_separation = 0.81`, `confidence = 0.72`
- `cinematic_expressiveness = 0.88`, `confidence = 0.69`

Fused result:
- both heads ignored for decision path
- strengths stay `[]`
- `verdict` stays `mixed`

Объяснение:
- degraded safety floor dominates stylistic pause-only evidence.

## Implementation Notes

### Integration point

`PR-H09` should insert `HybridFusionService` in [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift) after:
- deterministic `FrameCritiqueEngine.analyze(...)`

and before:
- `RecommendationPlanner.makePlan(...)`

Trace integration note:
- current `makeDeterministicPauseTraceBundle(...)` is deterministic-only and cannot stay the sole source for `pause` trace in fused cases;
- implementation should either replace it with a generalized trace builder or append a dedicated fusion materialization step before optional reasoning merge;
- fused trace must preserve the invariant `neural_evidence -> deterministic_rule -> recommendation`.
- if fusion reorders `critique.issues` or `critique.strengths`, implementation must also regenerate `critique.traceRefs` in the same fused order for all `_crit_i*` and `_crit_s*` refs, so current runtime positional lookups remain valid;
- if implementation chooses an ID-based trace builder instead, that builder becomes authoritative and all current positional assumptions in pause/live presentation must be removed within the same PR write scope.

### Deterministic code ownership

[FrameCritiqueEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift) should remain deterministic:
- no direct neural head knowledge inside detector formulas;
- no provider/runtime branching inside critique engine;
- fusion reads its output, not mutates rule definitions.

### Shared summary builder

Чтобы не дублировать summary logic между deterministic core и fusion layer, baseline implementation обязан вынести deterministic summary assembly в shared pure helper:

```text
DeterministicCritiqueSummaryBuilder
- makeSummary(summaryId: String, verdict: FrameVerdict, rankedStrengths: [FrameStrength], rankedIssues: [FrameIssue]) -> CritiqueSummary
```

Нормативные правила:
- helper должен воспроизводить текущую deterministic policy из `FrameCritiqueEngine` byte-equivalent способом when it receives the same ranked arrays as current deterministic runtime;
- `FrameCritiqueEngine` и `HybridFusionService` оба обязаны использовать один и тот же helper;
- helper не знает ничего о neural heads и принимает только already-materialized deterministic/fused findings;
- helper не делает внутренний re-sort `rankedStrengths` / `rankedIssues`; он берет top findings в уже переданном порядке;
- deterministic path обязан передавать свои current already-sorted arrays, чтобы сохранить byte-equivalent behavior;
- fusion path обязан передавать already-fused ranked arrays, чтобы summary отражал fused top findings;
- rebuild summary после fusion не должен менять wording templates, только выбор top findings.

### Suggested implementation surface

Baseline implementation can stay narrow:
- `HybridFusionService.swift`
- `HybridFusionPolicy.swift`
- `DeterministicCritiqueSummaryBuilder.swift`
- tests with fixed `NeuralEvidenceSnapshot` fixtures

Не нужно в `PR-H09`:
- переписывать planner logic;
- трогать UI builders;
- добавлять offloading abstractions.

## Test Matrix

Golden cases:
1. `pause` portrait clutter case increases confidence for existing readability issues.
2. `pause` clean portrait increases confidence for existing strengths.
3. `pause` moody backlight case shows bounded softening, not issue deletion.
4. `live` high-confidence `lighting_quality` can reinforce `backlight_hides_subject`.
5. `live` low-confidence neural head is ignored.
6. summary rebuild reflects fused top findings without changing rationale wording.

Degraded / failure cases:
1. degraded critique ignores pause-only heads.
2. degraded critique preserves `strengths == []`.
3. `policySkipped` live snapshot leaves critique byte-equivalent.
4. `failed` pause neural outcome leaves deterministic critique intact.
5. `shot_type_confidence` never changes `SceneTypeV1`.
6. `cinematic_expressiveness` never changes any finding in `PR-H09`.
7. `verdictConfidence` remains byte-equivalent to deterministic baseline.
8. degraded `horizon_distracts` remains deterministic-only and does not claim hybrid calibration.

Trace tests:
1. every applied fused delta creates at least one `neural_evidence` observation item.
2. fused interpretation remains `sourceKind = deterministic_rule`.
3. recommendation items still depend only on deterministic-rule interpretations.
4. metadata fields `fusionDelta`, `deterministicConfidenceBefore`, `fusedConfidenceAfter` are present when delta applied.
5. live fused delta materializes compact debug/eval trace without requiring a new live UI bundle contract.
6. when fused issue/strength order changes, `_crit_i*` / `_crit_s*` refs in `critique.traceRefs` are regenerated in the same order, or an ID-based builder replaces all positional assumptions.

## Invariants

- Fusion never changes taxonomy IDs or introduces new issue/strength kinds.
- Fusion never changes `verdict` label in `PR-H09`.
- Fusion never changes `verdictConfidence` in baseline `PR-H09`.
- Fusion never changes `severity`, `affectedRegion` or action geometry.
- Fusion never mutates `CritiqueReport` in skipped/failed/missing-neural cases.
- `live` requires `head.confidence >= 0.65`.
- `pause` may use `0.25 ... 0.44` only as tie-break, never as dominant signal.
- `cinematic_expressiveness` is observation-only in `PR-H09`.
- `shot_type_confidence` is contextual only and cannot rewrite deterministic scene semantics.
- Degraded mode cannot be upgraded out of fallback by neural evidence.
- Missing neural evidence must preserve deterministic fallback exactly.

## Design Verify (2026-04-22)

Источник независимой проверки:
- reviewer subagent + local cross-check против [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md), [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md), [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md), [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md), [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md) и текущего runtime в [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift) / [FrameCritiqueEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift).

Закрытые замечания:
- устранено противоречие с current `verdictConfidence` calculator: baseline `PR-H09` больше не обещает verdict-level recalibration, потому что текущий deterministic код не опирается на per-finding confidences;
- устранена двусмысленность planner impact: зафиксировано, что issue ranking может влиять на planner только внутри exact-severity ties, а strength ranking в baseline влияет только на summary / trace / pause presentation;
- устранен риск summary drift: добавлен обязательный deterministic rebuild `whyGood` / `whyProblematic` после fused reordering;
- устранена неявная зависимость от deterministic-only trace builder: добавлен explicit trace integration note и contract для fused `traceRefs` alignment;
- service-level contract сужен до реально поддерживаемых target kinds (`issue | strength`) и больше не притворяется verdict-level fusion API;
- стандартизован live trace surface: compact fused trace обязателен для debug/eval при реальном live delta, но не требует нового live UI bundle contract;
- выделен обязательный shared deterministic summary builder с canonical input-order semantics, чтобы implement не дублировал summary logic между `FrameCritiqueEngine` и fusion layer;
- устранено внутреннее противоречие degraded policy для `horizon_distracts`;
- усилен fallback invariant: missing/skipped/failed neural path обязан сохранять critique byte-equivalent, включая `traceRefs`.

Verdict readiness:
- **Ready for implement** -> документ implement-ready для `PR-H09`, если реализация сохраняет finding-level-only calibration, deterministic summary rebuild и fused trace bridge без verdict-level hidden judge.

## Definition of Done (design mode)

Этот design считается готовым, если:
- weighting policy зафиксирована формулой, caps и confidence bands;
- явно описано, когда neural evidence может менять confidence и ranking;
- explainability trace для fused findings не нарушает `observation -> interpretation -> recommendation`;
- degraded и failure behavior не позволяют превратить hybrid layer в black box;
- по документу можно реализовать `PR-H09` и покрыть golden/degraded cases без домысливания.
