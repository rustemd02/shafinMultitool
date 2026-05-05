# 26. Semantic Tip Fusion and Planner (PR-S04)

Статус: design spec + design verify (ready for implement)

Дата: 2026-05-05

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md)
- [23-hybrid-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/23-hybrid-eval-harness.md)
- [24-semantic-tip-taxonomy-and-action-catalog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md)
- [25-vlm-visual-semantic-evidence-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/25-vlm-visual-semantic-evidence-contract.md)
- [CameraAnalysisDomainContracts.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)

## Цель

Зафиксировать source-of-truth для `PR-S04`, который связывает:

`deterministic critique + deterministic recommendation plan + scene semantics + optional validated VLM evidence`

в финальный список коротких экранных semantic tips.

Ключевая формула `PR-S04`:

`CritiqueReport -> RecommendationPlan -> deterministic semantic candidates -> bounded VLM rerank/localization -> live/pause tip selection`

Из нее следуют обязательные правила:
- deterministic `CritiqueReport` и `RecommendationPlan` остаются source-of-truth для baseline UX;
- `VLM` и hybrid evidence могут reinforce, soften, localize или rerank только уже допустимые кандидаты;
- planner не invent-ит новый `IssueTypeV1`, `ActionTypeV1`, `SemanticActionType`, `SemanticTipType` или object ref;
- live и pause используют один и тот же semantic contract, но разный selection budget;
- каждая user-facing tip обязана быть объяснима через существующий trace chain и локальные anchors.

## Почему нужен отдельный `PR-S04`

На момент design verify уже существуют:
- deterministic `RecommendationPlan`;
- `SemanticTipCatalog` и `SemanticTipCandidate`;
- `VLMVisualEvidenceRequest/Response` и safe-label policy;
- live anti-flicker policy в UI слое.

Но отсутствует один planner-level contract, который фиксирует:
- где именно semantic tip planning стоит в pipeline;
- как `RecommendationAction` переводится в `SemanticTipType`;
- как безопасно учитывать optional `VLM` evidence без нарушения explainability invariants;
- как выбирать 1 live tip и repeatable pause budget (`2...4` corrective or `1...2` positive);
- как materialize-ить entity-aware labels, refs и fallback copy.

Без этого implementation легко уйдет в ad hoc mapping внутри UI или provider layer, что противоречит `PR-S01`, `PR-S02` и `PR-H09`.

## Scope

`PR-S04` отвечает за:
- runtime/service contract `SemanticTipPlanner`;
- deterministic candidate generation из `CritiqueReport`, `RecommendationPlan` и `SceneSemanticsReport`;
- bounded use of optional validated `VLMVisualEvidenceResponse`;
- stable ranking, tie-break и candidate suppression policy;
- materialization `SemanticTipCandidate` с entity-aware fields и safe fallback labels;
- выбор `1` primary live tip и bounded expanded pause tips;
- positive tip path для good frame;
- trace-link invariants и golden/test matrix.

`PR-S04` не отвечает за:
- UI rendering/layout;
- network/provider/offloading implementation;
- изменение deterministic critique taxonomy;
- изменение `PR-S01` catalog;
- free-form prose generation;
- новый object detector или новый entity-grounding механизм.

## Архитектурное положение

Authoritative sequencing для semantic tips:

1. `FrameFeatureSnapshot`
2. `SceneSemanticsReport`
3. `FrameCritiqueEngine`
4. `RecommendationPlanner`
5. optional `HybridFusionService` for critique confidence/ranking
6. optional validated `VLMVisualEvidenceResponse`
7. `SemanticTipPlanner`
8. UI presentation mapping from semantic tips

Нормативные следствия:
- `SemanticTipPlanner` работает после `RecommendationPlan`, а не вместо него;
- planner принимает уже materialized issue/action anchors и не решает заново, "есть ли проблема";
- `VLM` path не обходит steps `3-4`;
- если `VLM` evidence отсутствует, semantic tips все равно должны строиться repeatable способом.

## Service-Level Contract

```text
SemanticTipPlannerInput
- frameId: String
- mode: AnalysisMode
- critique: CritiqueReport
- recommendationPlan: RecommendationPlan
- semantics: SceneSemanticsReport
- validatedVLMResponse: VLMVisualEvidenceResponse?     // only after local validation
- currentLiveTipKey: String?                           // optional, for sticky live rerank

SemanticTipPlannerOutput
- livePrimaryTip: SemanticTipCandidate?
- pauseExpandedTips: [SemanticTipCandidate]            // 0...4, empty in live
- allRankedCandidates: [SemanticTipCandidate]
- selectionTraceNotes: [String]                        // debug/eval only
- fallbackUsed: Bool
```

Нормативные правила:
- `input.frameId`, `critique.frameId`, `recommendationPlan.frameId` и `semantics.frameId` обязаны совпадать;
- `mode == live` допускает максимум `1` selected tip;
- `mode == pause` допускает:
  - `2...4` tips для problem-oriented pause path;
  - `1...2` positive tips для `good` frame path;
- `allRankedCandidates` сортируются детерминированно и одинаково для одинакового input;
- `validatedVLMResponse == nil` не меняет shape output и не включает fallback сам по себе;
- `fallbackUsed == true` только если planner был вынужден деградировать copy/labels или suppress-ить более конкретный candidate.

## Candidate Generation

### Stage A. Deterministic anchors

Planner сначала строит локальные anchors:
- `issue anchors` из `CritiqueReport.issues`;
- `strength anchors` из `CritiqueReport.strengths`;
- `action anchors` из `RecommendationPlan.primaryAction`, `secondaryActions`, `deferredActions`;
- `subject/entity context` из `SceneSemanticsReport.primarySubject` и validated local/VLM grounded entities.

Важное правило:
- любой corrective semantic candidate обязан ссылаться минимум на один `linkedIssueId`;
- любой actionable candidate обязан ссылаться на `RecommendationAction.id` напрямую или через `linkedActionIds`;
- positive candidate обязан ссылаться на `summaryId` и `linkedStrengthIds` или `good` verdict path.

### Stage B. Catalog expansion

Для каждого issue/action planner строит только те `SemanticTipType`, которые проходят все фильтры:
- tip есть в `SemanticTipCatalog.issueTipCoverage` для данного `IssueTypeV1`;
- tip совместим с `RecommendationAction.actionType` через mapping matrix ниже;
- tip поддерживает текущий `mode`;
- tip не конфликтует с guardrails/motion policy;
- tip можно materialize-ить без unsafe entity naming.

### `ActionTypeV1 -> SemanticActionType` compatibility

`PR-S04` фиксирует не один-к-одному mapping, а closed compatible families:

- `move_frame_left` -> `shift_frame_left`
- `move_frame_right` -> `shift_frame_right`
- `move_frame_up` -> `shift_frame_up`, `raise_camera`
- `move_frame_down` -> `shift_frame_down`, `lower_camera`
- `increase_subject_size` -> `step_closer`
- `reduce_background_distractions` -> `simplify_background`, `remove_distracting_object`, `reposition_prop_for_balance`
- `change_angle` -> `change_camera_angle`, `move_subject_left`, `move_subject_right`, `move_object_left`, `move_object_right`, `move_object_back`
- `improve_front_light` -> `rotate_subject_toward_light`, `add_front_fill_light`, `add_background_light`, `remove_background_hotspot`
- `level_horizon` -> `level_horizon`
- `leave_frame_as_is` -> `keep_current_setup`

Нормативные ограничения:
- planner не materialize-ит semantic action, если она не совместима с исходным `ActionTypeV1`;
- `VLM` не может расширить этот compatibility set;
- если у одного `ActionTypeV1` есть несколько semantic candidates, выбор делается на следующем ranking stage.

## Entity-Aware Materialization

### Target selection priority

`targetEntityRef` выбирается строго в таком порядке:

1. stable local subject ref из `SceneSemanticsReport` для person/face-oriented tips;
2. validated `VLMGroundedEntity.entityRef`, если tip object-aware, mode `pause` и grounding high-confidence;
3. `nil`, если ни один source не проходит grounding policy.

`secondaryEntityRef` разрешен только если relation уже подтверждена:
- local contract-safe anchor;
- или validated `VLM` relation/entity pair из `PR-S02`.

### Safe labels

`targetEntityDisplayLabel` и `secondaryEntityDisplayLabel` строятся только через `SemanticDisplayLabelPolicy`.

Нормативные правила:
- person/face tips никогда не используют personal names или provider text;
- object-specific labels (`цветок`, `ваза`, `книга` и т.д.) разрешены только при `groundingConfidence >= 0.75`;
- если grounding слабый, planner деградирует к generic label, а не suppress-ит весь candidate автоматически;
- `structured_only` VLM request не может впервые принести конкретный object label; в таком режиме allowed only local grounded labels.

### Camera vs subject vs object decision

Planner обязан различать actor of change:
- `move_camera`, если проблема описывается framing/look space/horizon/camera height и anchor уже выражен `move_frame_*`, `step_*`, `change_angle`, `level_horizon`;
- `move_subject`, если deterministic action совместим с subject staging и target = primary subject;
- `move_object`, если conflict создается prop/object и есть grounded or safe-generic object target;
- `adjust_light`, только если lighting advice разрешен confidence policy below;
- `wait`, только для `timingBlockerInFrame`.

## VLM Conflict Policy

`VLM` может только:
- `reinforce`: поднять rank кандидата;
- `soften`: понизить rank кандидата;
- `localize`: помочь выбрать object-aware vs generic copy;
- `rerank`: переставить местами кандидатов с одинаковым deterministic priority band.

`VLM` не может:
- invent new tip/action ids;
- invent new linked issue ids;
- invent new target refs без валидного grounding;
- materialize positive tip при non-good deterministic verdict;
- продвигать lighting tip против явного deterministic contradiction.

### Tip-level evidence gating

Для применения `VLM` influence одновременно нужны:
- `validatedVLMResponse.status == completed`;
- observation / relation / suggestedActionId прошли local validation;
- `visualProblemType` или `visualStrengthType` совпадает с catalog-supported type кандидата;
- candidate уже существует в deterministic set;
- no deterministic contradiction from rules below.

### Lighting contradiction rule

Lighting semantic tip (`rotate_subject_toward_light`, `add_front_fill_light`, `add_background_light`, `remove_background_hotspot`) suppress-ится или не усиливается, если:
- corresponding deterministic issue отсутствует;
- или deterministic issue confidence `< 0.45`;
- или local signals прямо спорят с lighting claim;
- или `VLM` confidence low/uncertain.

Следствие:
- `VLM` не может впервые придумать light advice на чисто локально-хорошем кадре;
- live lighting advice особенно conservative и допускает только reinforced deterministic issue.

## Ranking and Selection

### Base score

Каждому candidate присваивается deterministic base score:

```text
baseScore =
  priorityBandWeight
  + issueSeverityWeight
  + issueConfidenceWeight
  + actionPriorityWeight
  + entityGroundingBonus
```

Recommended weights:
- `priorityBandWeight`: `1.00 / 0.80 / 0.60 / 0.50 / 0.40`
- `issueSeverityWeight`: `0...0.35`
- `issueConfidenceWeight`: `0...0.25`
- `actionPriorityWeight`: `0.20` for primary, `0.10` for secondary, `0.00` for deferred
- `entityGroundingBonus`: max `0.08`, never enough to outrank a stronger deterministic issue alone

### VLM adjustment

`vlmAdjustment` bounded:
- `live`: `[-0.06, +0.06]`
- `pause`: `[-0.10, +0.10]`

Он может применяться только как delta to existing candidate and never changes:
- candidate taxonomy;
- action frame;
- linked issue/action ids.

### Stable tie-break order

При равном effective score planner обязан сортировать по:
1. higher `priorityBand`
2. higher linked issue severity
3. higher action priority
4. higher entity grounding confidence
5. lexicographic `tipType.rawValue`
6. lexicographic `primaryActionId`

Это canonical ordering rule для tests и golden fixtures.

## Live vs Pause Selection

### Live

`livePrimaryTip`:
- максимум `1`;
- только из candidates, поддерживающих `mode == live`;
- только из `primary_corrective`, `secondary_corrective` или `positive_confirmation`;
- не использует pause-only object/light nuance tips;
- при `good` verdict выбирает positive tip `keep_current_setup`, а не silent nil, если есть валидный positive candidate.

### Pause

`pauseExpandedTips`:
- `2...4` items для non-good frame;
- `1...2` items для `good` frame;
- минимум `1` primary corrective tip для non-good frame, если такой candidate существует;
- максимум `1` timing tip;
- максимум `1` positive confirmation tip, и только если он не конфликтует с corrective headline;
- object/light nuance tips разрешены, если они не дублируют live primary semantics.

### Duplicate suppression

Planner обязан suppress-ить кандидаты, если:
- same `SemanticActionType` + same `targetEntityRef/DisplayLabel` + same linked issue set;
- candidate copy отличается только степенью конкретности без нового полезного действия;
- positive tip повторяет corrective headline.

## Anti-Flicker Boundary

Owner hysteresis/time-based anti-flicker остается `AnalysisPipeline` по [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md).

Но `PR-S04` обязан дать stable semantic identity:

```text
stableTipKey =
  "\(tipType.rawValue)|\(actionType.rawValue)|\(problemOrStrengthKey)|\(targetEntityKey)|\(secondaryEntityKey)"
```

Нормативные правила:
- одинаковый semantic input обязан давать одинаковый `stableTipKey`;
- `stableTipKey` не включает `frameId`;
- object-specific label входит в key только если прошел grounding policy, иначе используется generic label key;
- UI слой строит `LiveHintPresentation.id` и sticky behavior поверх этого stable key, а не поверх случайного текста.

## Explainability and Trace

Каждый selected semantic tip обязан:
- ссылаться на существующие `linkedTraceIds` из deterministic trace chain;
- не создавать прямую recommendation dependency на raw `neural_evidence`;
- сохранять `summaryId` для positive path;
- сохранять `linkedIssueIds` / `linkedStrengthIds` / `linkedActionIds`.

Нормативное правило:
- если `VLM` помог локализовать или rerank candidate, это отражается в debug/eval metadata и `selectionTraceNotes`, но user-facing recommendation trace все равно опирается на deterministic interpretation/recommendation items, совместимо с [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md).

## Golden Mapping Examples

### 1. Live portrait, issue `insufficient_look_space`

- deterministic anchor: `move_frame_left`
- semantic tip: `createLookSpaceLeft`
- live text: `Смести камеру чуть левее.`
- pause text: `Слева не хватает пространства взгляда. Смести камеру чуть левее.`
- `VLM` may reinforce if it agrees on `frame_intent`, but cannot replace with object tip.

### 2. Pause object shot, weak grounding

- deterministic anchor: `change_angle`
- `VLM` notices competing object but grounding confidence `0.58`
- planner output: generic candidate `moveObjectRightForBalance`
- text: `Сдвинь предмет правее.`
- forbidden output: `Сдвинь вазу правее.`

### 3. Pause face contour conflict, strong grounding

- deterministic anchor: `reduce_background_distractions`
- validated relation: `vase` blocks `face`
- planner output: `removeObjectFromFaceContour`
- live text: `Убери вазу из-за лица.`
- pause text: `Ваза заходит на контур лица. Убери ее в сторону, чтобы лицо читалось чище.`

### 4. Good frame

- deterministic verdict: `good`
- strengths: `good_subject_isolation`, `balanced_composition_for_scene`
- planner output: positive `keepFrameAsIs`
- live text: `Кадр уже читается хорошо.`
- pause text: `Кадр уже читается хорошо: герой отделен от фона и композиция держится.`

## Test Plan

`PR-S04` implementation/tests должны покрыть:
- deterministic-only candidate generation for all `IssueTypeV1`;
- positive tip selection for `good` frames;
- stable sorting when severity/confidence tie;
- live budget = exactly `0...1` tip;
- pause budget = `0...4` tips with duplicate suppression;
- `VLM` rerank within allowed candidate set only;
- rejection of VLM-invented action/label/ref;
- object label degradation from specific to generic;
- lighting contradiction suppression;
- anti-flicker stable key repeatability across adjacent frames;
- trace-link preservation for every selected tip.

## Design Verify Notes

Resolved findings:
- `PR-S04` is a new service after `RecommendationPlan`, not an implicit extension buried inside UI mapping;
- `SemanticTipDraftContext` stays request-side for `PR-S02`; runtime source-of-truth remains `SemanticTipCandidate` plus planner output;
- `VLM` influence is now explicitly bounded to rerank/localization and cannot violate explainability invariant that recommendation depends on deterministic interpretations;
- anti-flicker responsibility is split cleanly: planner provides stable semantic identity, pipeline keeps time-based hysteresis;
- positive tip path is explicit and no longer depends on ad hoc `nil` action handling.

No blocking contradictions remain against:
- `PR-S01` catalog and safe label policy;
- `PR-S02` validated VLM evidence shape;
- `PR-H09` bounded critique fusion;
- `PR-009/PR-010` live/pause UI integration rules.

Known implementation risks:
- current `RecommendationPlanner` in `AnalysisPipeline.swift` is still legacy action-oriented and will need extraction or extension rather than direct mutation in UI code;
- object-aware tips in `live` may stay generic until a stable local grounding source exists;
- trace augmentation should avoid creating a second parallel recommendation graph.

## Definition of Done

`PR-S04` is design-ready when:
- implementer can build `SemanticTipPlanner` without guessing planner placement or VLM boundaries;
- every selected tip can be derived from deterministic anchors and optional bounded evidence;
- live and pause share one semantic contract but produce different selection budgets;
- entity-aware copy, safe fallback labels and trace links are formal enough for unit tests and golden fixtures;
- `VLM` can improve priority/localization without becoming source-of-truth for baseline UX.
