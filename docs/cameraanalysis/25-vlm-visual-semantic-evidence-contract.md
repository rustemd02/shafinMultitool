# 25. VLM Visual Semantic Evidence Contract (PR-S02)

Статус: design spec + design verify (ready for implement)

Дата: 2026-05-04

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md)
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/12-agent-prompts.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md)
- [22-offloading-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/22-offloading-contract.md)
- [24-semantic-tip-taxonomy-and-action-catalog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md)

## Цель

Зафиксировать контракт, по которому `VLM` или remote critic возвращает не финальный совет и не product verdict, а machine-validated визуальные evidence для semantic screen tips.

Ключевая формула `PR-S02`:

`pause frame/context -> VLM visual observations -> validated semantic evidence -> deterministic semantic tip planner`

Из нее следуют обязательные правила:
- `VLM` работает только в `pause` или optional offloaded deep analysis;
- `live` path не зависит от `VLM`;
- `VLM` не добавляет новые `IssueTypeV1`, `ActionTypeV1`, `SemanticActionType` или `SemanticTipType`;
- response может подсказать допустимые `SemanticActionType`, но финальный выбор tip/action остается за deterministic planner/fusion layer;
- свободный текст разрешен только как secondary explanation/debug, не как decision source;
- entity labels допустимы только при confidence-aware grounding и safe naming policy из `PR-S01`.

## Scope

В scope:
- request/response shape для `VLMVisualEvidenceRequest` и `VLMVisualEvidenceResponse`;
- closed visual evidence dimensions;
- entity-aware fields и relation semantics;
- allowed `suggestedActionIds`, совместимые с `PR-S01`;
- confidence, uncertainty и validation semantics;
- privacy/offloading compatibility;
- prompt skeleton для provider-а;
- JSON examples и failure matrix.

Вне scope:
- реальный network client/provider;
- UI wiring;
- prompt tuning под конкретную модель;
- изменение deterministic critique taxonomy;
- расширение `PR-S01` catalog.

## Contract Position

`PR-S02` sits after local pause baseline and before semantic tip planning:

1. local deterministic `FrameFeatureSnapshot`;
2. local deterministic `SceneSemanticsReport`;
3. local deterministic `CritiqueReport`;
4. local `RecommendationPlan`;
5. optional `VLMVisualEvidenceRequest` when policy allows `pause`/offloading;
6. validation of `VLMVisualEvidenceResponse`;
7. deterministic `SemanticTipPlanner` uses valid evidence as bounded support/rerank/context.

Нормативные следствия:
- invalid response must fail closed into deterministic-only critique/tips;
- no baseline pause card waits for VLM;
- VLM evidence can reinforce, soften or localize a semantic tip, but cannot become final verdict by itself.

## Relationship to Other Provider Layers

`VLMVisualEvidenceProvider` is intentionally separate from `ReasoningProvider` in [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md):
- `ReasoningProvider` refines pause prose over already built deterministic output;
- `VLMVisualEvidenceProvider` extracts bounded visual evidence before semantic tip planning;
- neither provider can mutate deterministic issue/action taxonomy;
- if both providers exist, semantic evidence must validate before text refinement sees any derived tip copy.

## Closed Catalogs

### `VLMEvidenceSchemaVersion`

```text
VLMEvidenceSchemaVersion
- s1
```

### `VLMVisualEvidenceDimension`

Разрешены только эти dimensions:

```text
VLMVisualEvidenceDimension
- subject_readability
- background_separation
- lighting_relation
- clutter
- depth
- face_visibility
- frame_intent
- mood_preservation
```

Смысл dimensions:
- `subject_readability`: насколько главный субъект читается как визуальный anchor;
- `background_separation`: отделяется ли субъект/объект от фона по тону, силуэту, глубине или overlap;
- `lighting_relation`: помогает ли свет читаемости, не сливает ли субъект с фоном, нет ли hotspot behind subject;
- `clutter`: конкурируют ли предметы/фоновые элементы за внимание;
- `depth`: есть ли читаемые планы, layering и ощущение пространства;
- `face_visibility`: видно ли лицо/глаза/контур головы, если кадр person-centric;
- `frame_intent`: похоже ли кадр на намеренную композицию/shot intent из локального catalog;
- `mood_preservation`: является ли спорный свет/темнота намеренным mood, который надо сохранить, а не "исправить".

### `VLMEntityKind`

```text
VLMEntityKind
- person
- face
- object
- prop
- background_area
- light_source
- frame
- unknown
```

Catalog должен оставаться совместимым с `TargetEntityKind` из `PR-S01`.

### `VLMEntityRelationType`

```text
VLMEntityRelationType
- competes_with
- merges_with
- blocks
- pulls_attention_from
```

Relation используется только для visual evidence, а не для нового action taxonomy.

### `VLMEvidencePolarity`

```text
VLMEvidencePolarity
- supports_problem
- supports_strength
- neutral_context
```

### `VLMUncertaintyReason`

```text
VLMUncertaintyReason
- low_visual_confidence
- occluded_entity
- ambiguous_subject
- ambiguous_object_label
- weak_grounding
- privacy_redaction
- insufficient_resolution
- conflicting_local_context
- mood_intent_ambiguous
```

### `VLMResponseStatus`

```text
VLMResponseStatus
- completed
- refused
- unavailable
```

`completed` не означает "валидно применить все": validation layer все равно проверяет каждое поле.

## Allowed `suggestedActionIds`

`suggestedActionIds` в response может содержать только `SemanticActionType` из `PR-S01 v1`:

```text
shift_frame_left
shift_frame_right
shift_frame_up
shift_frame_down
step_back
step_closer
lower_camera
raise_camera
change_camera_angle
level_horizon
rotate_subject_toward_light
move_subject_left
move_subject_right
move_subject_away_from_background
move_object_left
move_object_right
move_object_forward
move_object_back
remove_distracting_object
reposition_prop_for_balance
add_front_fill_light
add_background_light
remove_background_hotspot
simplify_background
wait_for_background_clearance
keep_current_setup
```

Нормативные правила:
- `suggestedActionIds` are hints, not final actions;
- order expresses VLM preference but planner may ignore/rerank;
- unknown action id is hard validation error;
- `keep_current_setup` cannot coexist with corrective action ids in the same response;
- actions outside `PR-S01`, including deferred actions like `add_rim_light`, are forbidden until catalog update.

## Request Contract

```text
VLMVisualEvidenceRequest
- schemaVersion: VLMEvidenceSchemaVersion       // required, "s1"
- requestId: String                            // required, stable for request
- frameId: String                              // required, matches local pause frame
- mode: AnalysisMode                           // required, must be pause
- locale: String                               // required, example: ru-RU
- privacyTier: DeepCriticPrivacyTier           // required, structured_only | redacted_visual
- trigger: DeepCriticTrigger?                  // optional if routed through offloading
- visualInput: VLMVisualInput?                 // required only for redacted_visual
- localContext: VLMVisualEvidenceLocalContext  // required
- allowedCatalog: VLMAllowedSemanticCatalog    // required
- constraints: VLMVisualEvidenceConstraints    // required
- correlation: VLMVisualEvidenceCorrelation    // required
```

### `VLMVisualInput`

```text
VLMVisualInput
- attachmentKind: redacted_still | redacted_subject_crop
- mediaRef: String                             // provider-local opaque ref, not raw bytes in domain fixture
- longEdgePx: Int                              // <= 1024
- exifStripped: Bool                           // must be true
- redactionApplied: Bool
- redactionNotes: [String]
```

Rules:
- `visualInput == nil` for `structured_only`;
- `visualInput != nil` only when `privacyTier == redacted_visual`;
- no raw image bytes, filenames, EXIF, GPS or user identifiers are part of this domain contract.

### Privacy tier evidence rules

`structured_only`:
- provider sees only sanitized local structured context and no image;
- response may review, reinforce, soften or rank already-grounded local evidence;
- response cannot introduce newly observed entity refs, newly specific object labels or relation claims that are absent from `localContext`;
- any specific label in `structured_only` must come from `groundedEntities.displayLabelCandidate`, not from provider visual recognition.

`redacted_visual`:
- provider may inspect one redacted still/crop and emit visual observations inside the same closed catalogs;
- provider still cannot invent frame-stable entity refs;
- if it sees an entity not present in `groundedEntities`, it must describe it through generic labels and `targetEntityRef == nil`;
- specific labels remain gated by safe naming policy and allowed vocabulary.

### `VLMVisualEvidenceLocalContext`

```text
VLMVisualEvidenceLocalContext
- frameFeatureSnapshotExcerpt: Object          // sanitized bounded excerpt, not full raw image data
- sceneSemantics: SceneSemanticsReport
- critique: CritiqueReport
- recommendationPlan: RecommendationPlan
- semanticTipDrafts: [SemanticTipDraftContext] // optional candidates from deterministic mapper
- groundedEntities: [VLMGroundedEntity]
- localNeuralEvidenceSummary: NeuralEvidenceSummary?
```

Rules:
- local context is read-only for VLM;
- VLM must refer to known `frameId`, known entity refs, known issue/action IDs;
- `semanticTipDrafts` are candidates, not instructions to rubber-stamp.

### `SemanticTipDraftContext`

This is a request-side compact excerpt, not a new runtime contract:

```text
SemanticTipDraftContext
- draftId: String
- tipType: SemanticTipType?
- actionType: SemanticActionType
- actionFrame: SemanticActionFrame
- targetEntityRef: String?
- targetEntityKind: VLMEntityKind
- targetEntityDisplayLabel: String
- linkedIssueIds: [String]
- linkedStrengthIds: [String]
- linkedActionIds: [String]
- priorityBand: SemanticTipPriorityBand?
```

Rules:
- every id must come from local `CritiqueReport`, `RecommendationPlan` or deterministic semantic tip mapper;
- VLM can support or question a draft through observations, but cannot create a final tip from draft text alone;
- omitted `tipType` means the local mapper has only a semantic action candidate, not a materialized tip.

### `NeuralEvidenceSummary`

This is a lossy optional request-side summary over `NeuralEvidenceSnapshot`, not a replacement for `PR-H06`:

```text
NeuralEvidenceSummary
- schemaVersion: String
- availableHeadIds: [EvidenceHeadId]
- unavailableHeadIds: [EvidenceHeadId]
- notableScores: [NeuralEvidenceScoreSummary]
```

```text
NeuralEvidenceScoreSummary
- headId: EvidenceHeadId
- score: Double?
- confidence: Double
- status: EvidenceHeadStatus
```

Rules:
- `NeuralEvidenceSummary` is debug/context only;
- VLM cannot cite neural heads as visual facts unless those heads are present here;
- canonical neural evidence remains `NeuralEvidenceSnapshot` from `PR-H06`.

### `VLMGroundedEntity`

```text
VLMGroundedEntity
- entityRef: String                            // stable within frame
- kind: VLMEntityKind
- role: TargetEntityRole
- region: NormalizedRect?
- detectorLabel: String?
- detectorConfidence: Double?
- displayLabelCandidate: String
- displayLabelConfidence: Double
```

Rules:
- `entityRef` must be frame-local and must not be reused across frames;
- `displayLabelCandidate` already follows local safe label fallback when available;
- VLM may lower confidence or choose generic label, but may not invent stable refs.

### `VLMAllowedSemanticCatalog`

```text
VLMAllowedSemanticCatalog
- catalogVersion: String                       // example: "PR-S01-2026-05-04"
- allowedEvidenceDimensions: [VLMVisualEvidenceDimension]
- allowedVisualProblemTypes: [VisualProblemType]
- allowedVisualStrengthTypes: [VisualStrengthType]
- allowedSemanticActionTypes: [SemanticActionType]
- allowedGroundedObjectDisplayLabels: [String]
- allowedGenericDisplayLabels: [String]
```

Rules:
- request must include dense allowed catalogs, even if provider prompt also embeds them;
- validator rejects any response value absent from these lists.

### `VLMVisualEvidenceConstraints`

```text
VLMVisualEvidenceConstraints
- maxObservations: Int                         // default 8, hard cap 12
- maxRelations: Int                            // default 6, hard cap 10
- maxSuggestedActionIds: Int                   // default 4, hard cap 6
- maxExplanationChars: Int                     // default 600, hard cap 1000
- allowMoodPreservation: Bool                  // default true in pause
- requireEntityGroundingForSpecificLabels: Bool // always true in v1
- failClosedOnUnknownIds: Bool                 // always true in v1
```

### `VLMVisualEvidenceCorrelation`

```text
VLMVisualEvidenceCorrelation
- localCritiqueSummaryId: String
- localPlanSummaryId: String?
- semanticCatalogVersion: String
- offloadingSchemaVersion: String?
- providerConfigVersion: String
- sessionEphemeralId: String?
```

Rules:
- `sessionEphemeralId` can only be ephemeral and must not be a stable user identifier;
- correlation is for debugging/cache only, not for provider personalization.

## Response Contract

```text
VLMVisualEvidenceResponse
- schemaVersion: VLMEvidenceSchemaVersion       // required, "s1"
- requestId: String                            // required, must match request
- frameId: String                              // required, must match request
- mode: AnalysisMode                           // required, must be pause
- providerId: String                           // required
- status: VLMResponseStatus                    // required
- primaryEntityRef: String?                    // required when primary entity is grounded
- primaryEntityKind: VLMEntityKind             // required
- primaryEntityDisplayLabelCandidate: String   // required, safe label candidate
- primaryEntityLabelConfidence: Double         // required, 0...1
- secondaryEntityRef: String?
- secondaryEntityKind: VLMEntityKind?
- secondaryEntityDisplayLabelCandidate: String?
- secondaryEntityLabelConfidence: Double?
- observations: [VLMVisualEvidenceObservation]
- relations: [VLMEntityRelation]
- suggestedActionIds: [SemanticActionType]
- explanation: VLMSecondaryExplanation?
- safety: VLMEvidenceSafetyReport
- diagnostics: VLMEvidenceDiagnostics
```

Status-specific rules:
- when `status == completed`, all required entity fields, observations and diagnostics must validate normally;
- when `status in {refused, unavailable}`, `observations`, `relations` and `suggestedActionIds` must be empty, entity labels must be generic, and `diagnostics.fallbackReason` is required;
- refused/unavailable responses are never applied to planner input.

### `VLMVisualEvidenceObservation`

```text
VLMVisualEvidenceObservation
- observationId: String
- dimension: VLMVisualEvidenceDimension
- polarity: VLMEvidencePolarity
- score: Double                                // 0...1; strength of observed axis/problem/strength
- confidence: Double                           // 0...1; reliability of this observation
- uncertaintyReasons: [VLMUncertaintyReason]
- primaryEntityRef: String?
- secondaryEntityRef: String?
- visualProblemType: VisualProblemType?
- visualStrengthType: VisualStrengthType?
- supportedIssueIds: [String]
- supportedStrengthIds: [String]
- suggestedActionIds: [SemanticActionType]
- evidenceNote: String?                        // short secondary explanation, not decision source
```

Rules:
- `observationId` must be unique within response and stable enough for validation logs;
- `score` describes observed strength of this dimension, not global frame quality;
- `visualProblemType` is required when `polarity == supports_problem`;
- `visualStrengthType` is required when `polarity == supports_strength`;
- `supportedIssueIds` and `supportedStrengthIds` must reference local deterministic runtime IDs;
- observation-level `suggestedActionIds` must be a subset of response-level `suggestedActionIds`;
- `evidenceNote` may explain why, but downstream must use structured fields for decisions.

### `VLMEntityRelation`

```text
VLMEntityRelation
- relationId: String
- sourceEntityRef: String
- targetEntityRef: String?
- relationType: VLMEntityRelationType
- dimension: VLMVisualEvidenceDimension
- score: Double                                // 0...1
- confidence: Double                           // 0...1
- uncertaintyReasons: [VLMUncertaintyReason]
- supportedObservationIds: [String]
```

Rules:
- relation without `sourceEntityRef` is invalid;
- `targetEntityRef == nil` allowed only when relation target is safely generic, such as "background area";
- relation cannot introduce new entities;
- `supportedObservationIds` must resolve to observations in the same response.

### `VLMSecondaryExplanation`

```text
VLMSecondaryExplanation
- language: String                             // must match request.locale or supported fallback
- summary: String                              // <= maxExplanationChars
- caveats: [String]
```

Rules:
- explanation cannot contain action IDs absent from `suggestedActionIds`;
- explanation cannot override local verdict;
- explanation cannot use specific object label rejected by safe naming validator.

### `VLMEvidenceSafetyReport`

```text
VLMEvidenceSafetyReport
- passed: Bool
- violations: [VLMEvidenceViolation]
```

```text
VLMEvidenceViolation
- mode_not_pause
- request_mismatch
- unknown_entity_ref
- unknown_issue_id
- unknown_strength_id
- unknown_action_id
- unknown_problem_type
- unknown_strength_type
- unknown_dimension
- unsafe_specific_label
- label_without_grounding
- contradictory_keep_and_correct
- attempts_to_change_verdict
- attempts_to_change_taxonomy
- output_too_long
- privacy_tier_mismatch
- malformed_json
```

Rules:
- this is provider-claimed self-check metadata only;
- local validation is authoritative and must not trust `safety.passed`;
- if `safety.passed == false`, local validator may hard reject immediately, but `safety.passed == true` never skips local checks.

### `VLMEvidenceValidationResult`

Local validator output is the only object downstream planner can consume:

```text
VLMEvidenceValidationResult
- requestId: String
- frameId: String
- accepted: Bool
- acceptedObservations: [VLMVisualEvidenceObservation]
- acceptedRelations: [VLMEntityRelation]
- acceptedSuggestedActionIds: [SemanticActionType]
- acceptedPrimaryLabel: String
- acceptedSecondaryLabel: String?
- violations: [VLMEvidenceViolation]
- fallback: VLMEvidenceFallback
```

```text
VLMEvidenceFallback
- use_validated_evidence
- deterministic_only
- deterministic_with_generic_labels
```

Rules:
- planner receives `VLMEvidenceValidationResult`, not raw provider response;
- `accepted == false` requires `fallback == deterministic_only`;
- `deterministic_with_generic_labels` is allowed only after safe naming downgrade with at least one accepted structured observation;
- accepted arrays must preserve provider order after invalid entries are removed.

### `VLMEvidenceDiagnostics`

```text
VLMEvidenceDiagnostics
- latencyMs: Int?
- providerModelFamily: String?
- providerModelVersion: String?
- promptVersion: String
- privacyTier: DeepCriticPrivacyTier
- fallbackReason: String?
```

Diagnostics are debug/eval metadata and must not influence product decisions directly.

## Entity-Aware Field Semantics

### Primary entity

`primaryEntityRef` should reference the local primary subject/entity when available:
- person-centric frame: local primary person/face ref;
- object-centric frame: local object/prop ref;
- unknown frame: `nil`, `primaryEntityKind = unknown`, generic label only.

Rules:
- response cannot promote a secondary object to primary if local `SceneSemanticsReport` has high-confidence person primary, unless it marks `conflicting_local_context` uncertainty;
- planner may use conflict as debug/rerank signal, not as hard subject reassignment.

### Secondary entity

`secondaryEntityRef` is used for competing/occluding/attention-pulling objects:
- flower behind face;
- bright hotspot behind subject;
- background passerby;
- prop near object contour.

Rules:
- secondary entity can be nil for generic background zones;
- if secondary label is specific, grounding and safe naming rules apply.

## Safe Naming Policy

VLM may propose a specific display label only when all conditions hold:
- `entityRef` resolves to a local grounded entity or a clearly visible entity in `redacted_visual`;
- `primaryEntityLabelConfidence` or `secondaryEntityLabelConfidence >= 0.75`;
- label belongs to `allowedGroundedObjectDisplayLabels` or allowed person/face labels;
- label does not conflict with local detector/semantics label at confidence `>= 0.70`;
- no `ambiguous_object_label`, `weak_grounding`, `privacy_redaction` or `insufficient_resolution` uncertainty applies to that label.

Allowed specific object labels inherit `PR-S01`:
- `цветок`
- `ваза`
- `книга`
- `чашка`
- `бутылка`
- `лампа`
- `стул`
- `телефон`

Allowed person/face labels:
- `герой`
- `человек`
- `лицо`
- `персонаж`

If any condition fails:
- use generic label: `предмет`, `объект справа`, `яркий объект на фоне`, `предмет у лица`, `фон`, `герой`;
- set label confidence to the actual lower value;
- include uncertainty reason when useful.

Forbidden:
- proper names;
- identity, age, gender, ethnicity, emotion diagnosis or sensitive attributes;
- object labels outside the allowed vocabulary;
- upgrading generic label to specific label without grounding/confidence.

## Confidence and Uncertainty Semantics

### Confidence bands

| Confidence | Meaning | Planner policy |
| --- | --- | --- |
| `0.00 ... 0.24` | unusable/mostly uncertain | ignore except debug |
| `0.25 ... 0.44` | weak support | tie-break only in pause |
| `0.45 ... 0.64` | usable contextual support | bounded pause evidence |
| `0.65 ... 0.84` | strong support | normal pause evidence |
| `0.85 ... 1.00` | very strong visual support | can reinforce/rerank, still cannot invent |

Rules:
- confidence is reliability, not severity;
- `score` is visual strength of the axis, not confidence;
- `uncertaintyReasons` must be non-empty when `confidence < 0.45`;
- `confidence >= 0.75` is required for specific object naming.

### Mood preservation

`mood_preservation` exists to avoid overcorrecting intentional low-key/backlit frames.

Rules:
- it can soften a corrective lighting/separation tip;
- it cannot erase deterministic safety/readability issue alone;
- it cannot recommend "do nothing" if local plan has high-severity corrective issue;
- it may support positive `keep_light_direction` or `keep_frame_as_is` only through deterministic good-frame policy.

## Forbidden Behavior

VLM response is invalid if it:
- claims final product verdict changed;
- adds unknown issue/action/tip/problem/strength IDs;
- invents new entity refs;
- emits final user copy as source-of-truth;
- asks to use `live` path or continuous upload;
- sends `mode != pause`;
- outputs specific labels without grounding/confidence;
- uses raw pixels/EXIF/user identifiers in structured fields;
- contradicts request privacy tier;
- suggests deferred `PR-S01` actions such as `add_rim_light`;
- returns unbounded prose instead of JSON.

## Validation Rules

Validator must run before planner sees the response.

Hard reject whole response:
- malformed JSON;
- schemaVersion mismatch;
- requestId/frameId/mode mismatch;
- `mode != pause`;
- unknown enum/id in any required field;
- privacy tier mismatch;
- `status in {refused, unavailable}`;
- response attempts to mutate verdict/taxonomy;
- `keep_current_setup` coexists with corrective action ids.

Partial reject invalid observation/relation:
- unknown observation id reference;
- unknown entity ref;
- label confidence below naming threshold;
- unsupported issue/strength id;
- observation has missing problem/strength type for its polarity;
- confidence/score outside `0...1`;
- explanation too long.

Structured-only-specific reject/downgrade:
- relation absent from local `groundedEntities` or `semanticTipDrafts` -> partial reject;
- specific object label not already present in `groundedEntities` -> downgrade to generic or partial reject;
- new entity-localization claim without local region/ref -> partial reject;
- visual assertion that contradicts high-confidence local semantics without `conflicting_local_context` -> partial reject.

Fallback behavior:
- hard reject -> deterministic-only critique/tips;
- partial reject -> remove invalid parts, then revalidate remaining response;
- after partial filtering, if no valid observations remain -> deterministic-only critique/tips;
- validation failure must not alter already published pause result.

## Prompt Skeleton for VLM Provider

```text
You are a bounded visual semantic evidence extractor for a camera composition assistant.

Return ONLY valid JSON matching VLMVisualEvidenceResponse schemaVersion "s1".

You may inspect the provided pause frame/context and emit structured visual evidence for these dimensions only:
subject_readability, background_separation, lighting_relation, clutter, depth, face_visibility, frame_intent, mood_preservation.

You must not decide the final product verdict, invent issue/action/tip ids, or create new taxonomy.
Use only the allowed SemanticActionType ids from the request.
Use only entity refs from groundedEntities. If a specific object label is uncertain, use a generic label.
Specific object labels are allowed only from the allowed grounded object vocabulary and only with confidence >= 0.75.

Free text is allowed only inside explanation.summary or evidenceNote and must not be the decision source.
If you are unsure, lower confidence and include uncertaintyReasons.
If the request is not pause mode or violates privacy constraints, return status "refused".
```

## JSON Example: Good Frame

```json
{
  "schemaVersion": "s1",
  "requestId": "vlm-req-001",
  "frameId": "pause-frame-042",
  "mode": "pause",
  "providerId": "mock-vlm-semantic-v1",
  "status": "completed",
  "primaryEntityRef": "ent-person-1",
  "primaryEntityKind": "person",
  "primaryEntityDisplayLabelCandidate": "герой",
  "primaryEntityLabelConfidence": 0.86,
  "secondaryEntityRef": null,
  "secondaryEntityKind": null,
  "secondaryEntityDisplayLabelCandidate": null,
  "secondaryEntityLabelConfidence": null,
  "observations": [
    {
      "observationId": "obs-separation-1",
      "dimension": "background_separation",
      "polarity": "supports_strength",
      "score": 0.82,
      "confidence": 0.78,
      "uncertaintyReasons": [],
      "primaryEntityRef": "ent-person-1",
      "secondaryEntityRef": null,
      "visualProblemType": null,
      "visualStrengthType": "clean_subject_separation",
      "supportedIssueIds": [],
      "supportedStrengthIds": ["strength-good-subject-isolation"],
      "suggestedActionIds": ["keep_current_setup"],
      "evidenceNote": "Силуэт читается отдельно от спокойного фона."
    },
    {
      "observationId": "obs-light-1",
      "dimension": "lighting_relation",
      "polarity": "supports_strength",
      "score": 0.76,
      "confidence": 0.72,
      "uncertaintyReasons": [],
      "primaryEntityRef": "ent-person-1",
      "secondaryEntityRef": null,
      "visualProblemType": null,
      "visualStrengthType": "flattering_light_direction",
      "supportedIssueIds": [],
      "supportedStrengthIds": ["strength-good-light-emphasis"],
      "suggestedActionIds": ["keep_current_setup"],
      "evidenceNote": "Свет поддерживает лицо и не спорит с фоном."
    }
  ],
  "relations": [],
  "suggestedActionIds": ["keep_current_setup"],
  "explanation": {
    "language": "ru-RU",
    "summary": "Кадр уже собран: герой читается, фон не конкурирует, свет поддерживает лицо.",
    "caveats": []
  },
  "safety": {
    "passed": true,
    "violations": []
  },
  "diagnostics": {
    "latencyMs": 620,
    "providerModelFamily": "mock-vlm",
    "providerModelVersion": "s1-dev",
    "promptVersion": "vlm-evidence-s1",
    "privacyTier": "redacted_visual",
    "fallbackReason": null
  }
}
```

## JSON Example: Problem Frame

```json
{
  "schemaVersion": "s1",
  "requestId": "vlm-req-002",
  "frameId": "pause-frame-077",
  "mode": "pause",
  "providerId": "mock-vlm-semantic-v1",
  "status": "completed",
  "primaryEntityRef": "ent-person-1",
  "primaryEntityKind": "person",
  "primaryEntityDisplayLabelCandidate": "герой",
  "primaryEntityLabelConfidence": 0.88,
  "secondaryEntityRef": "ent-vase-1",
  "secondaryEntityKind": "prop",
  "secondaryEntityDisplayLabelCandidate": "ваза",
  "secondaryEntityLabelConfidence": 0.81,
  "observations": [
    {
      "observationId": "obs-face-block-1",
      "dimension": "face_visibility",
      "polarity": "supports_problem",
      "score": 0.74,
      "confidence": 0.79,
      "uncertaintyReasons": [],
      "primaryEntityRef": "ent-person-1",
      "secondaryEntityRef": "ent-vase-1",
      "visualProblemType": "face_contour_occlusion",
      "visualStrengthType": null,
      "supportedIssueIds": ["issue-background-competes"],
      "supportedStrengthIds": [],
      "suggestedActionIds": ["remove_distracting_object"],
      "evidenceNote": "Предмет пересекает контур лица и забирает внимание."
    },
    {
      "observationId": "obs-clutter-1",
      "dimension": "clutter",
      "polarity": "supports_problem",
      "score": 0.68,
      "confidence": 0.66,
      "uncertaintyReasons": [],
      "primaryEntityRef": "ent-person-1",
      "secondaryEntityRef": "ent-vase-1",
      "visualProblemType": "object_conflicts_with_subject",
      "visualStrengthType": null,
      "supportedIssueIds": ["issue-background-competes"],
      "supportedStrengthIds": [],
      "suggestedActionIds": ["remove_distracting_object", "reposition_prop_for_balance"],
      "evidenceNote": "Ваза выглядит как конкурирующий foreground prop."
    }
  ],
  "relations": [
    {
      "relationId": "rel-vase-blocks-face",
      "sourceEntityRef": "ent-vase-1",
      "targetEntityRef": "ent-person-1",
      "relationType": "blocks",
      "dimension": "face_visibility",
      "score": 0.74,
      "confidence": 0.79,
      "uncertaintyReasons": [],
      "supportedObservationIds": ["obs-face-block-1"]
    }
  ],
  "suggestedActionIds": ["remove_distracting_object", "reposition_prop_for_balance"],
  "explanation": {
    "language": "ru-RU",
    "summary": "Главная проблема не в общей экспозиции, а в предмете у лица: он ломает контур героя.",
    "caveats": []
  },
  "safety": {
    "passed": true,
    "violations": []
  },
  "diagnostics": {
    "latencyMs": 740,
    "providerModelFamily": "mock-vlm",
    "providerModelVersion": "s1-dev",
    "promptVersion": "vlm-evidence-s1",
    "privacyTier": "redacted_visual",
    "fallbackReason": null
  }
}
```

## Failure Matrix

| Case | Validator outcome | Runtime fallback |
| --- | --- | --- |
| `mode = live` | hard reject `mode_not_pause` | deterministic live path only |
| request/frame mismatch | hard reject `request_mismatch` | keep local pause result |
| unknown `suggestedActionId` | hard reject `unknown_action_id` | deterministic-only semantic tips |
| unknown entity ref in relation | partial reject relation/observation | use remaining valid evidence or deterministic-only |
| specific label below confidence threshold | partial reject label, degrade to generic | planner may use generic target copy |
| `keep_current_setup` with corrective action | hard reject `contradictory_keep_and_correct` | deterministic-only semantic tips |
| provider refused/unavailable | hard reject as non-applicable response | deterministic-only semantic tips |
| privacy tier mismatch | hard reject `privacy_tier_mismatch` | no remote evidence applied |
| malformed JSON | hard reject `malformed_json` | deterministic-only semantic tips |
| explanation too long | partial reject explanation | structured evidence may still apply |

## Test Plan

Contract tests for `PR-S02` should cover:
- decoding valid good-frame and problem-frame examples;
- hard rejection for unknown action ids;
- hard rejection for `mode != pause`;
- safe naming downgrade for low-confidence `ваза`/`цветок`;
- relation validation with unknown `targetEntityRef`;
- `keep_current_setup` conflict rejection;
- structured-only request with no visual input;
- structured-only response attempting a newly specific object label;
- provider `safety.passed == true` with unknown IDs still rejected by local validation;
- redacted-visual request with valid privacy metadata;
- deterministic-only fallback when all observations are filtered out.

## Design Verify Notes

Resolved verification findings:
- request-side sketch types `SemanticTipDraftContext` and `NeuralEvidenceSummary` are now defined enough for provider implementation without hidden schema guesses;
- `structured_only` no-image behavior is bounded: it can review local structured evidence, but cannot invent new visual entities, labels or relations;
- provider `safety` is explicitly non-authoritative; downstream consumes only local `VLMEvidenceValidationResult`;
- offloading privacy tiers remain compatible with `PR-H12`, including `redacted_visual` consent boundaries and deterministic fallback.

No blocking contradictions found against:
- `PR-S01` action and safe-label catalog;
- `PR-H02/PR-H06` neural evidence roles;
- `PR-H09` bounded fusion policy;
- `PR-H12` offloading/privacy fallback policy.

Known implementation risks:
- future Swift/Python schema implementer must choose whether `frameFeatureSnapshotExcerpt` is a typed subset or generic sanitized dictionary;
- `SemanticTipDraftContext` should remain request-side only unless `PR-S04` promotes it to a runtime type;
- redacted visual entity discovery must stay generic unless a later PR defines a safe new-entity grounding mechanism.

## Definition of Done

`PR-S02` is design-ready when:
- provider agent can implement mock/remote VLM evidence without extra taxonomy questions;
- invalid VLM output fails closed into deterministic-only critique/tips;
- entity refs, relation types and label confidence rules are formal enough for template-based copy like `сдвинь {target}` / `убери {secondary}` / `отодвинь {target} от фона`;
- response explains visual reasons while remaining bounded evidence, not final product verdict.
