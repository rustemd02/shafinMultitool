# 16. Dataset Schema and Labeling Guide (PR-H03)

Статус: design spec (source-of-truth)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)

## Цель

Зафиксировать dataset schema и labeling protocol для hybrid `camera analysis`, чтобы:
- `PR-H05` и `PR-H06` могли опираться на единый shape данных;
- `PR-H14` мог использовать те же сущности для eval и ablation;
- разметка была rubric-driven и совместима с explainable critique system, а не строилась как vague aesthetic voting.

Этот документ закрывает design-часть `PR-H03` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Scope

`PR-H03` отвечает за:
- entity schema для dataset bundle, records, annotations и adjudication;
- source buckets `public / curated / runtime_hard_case`;
- annotator guide и bounded rubric;
- disagreement resolution;
- minimal starter dataset;
- QA checklist.

`PR-H03` не отвечает за:
- выбор backbone и loss design;
- AVA/pretraining policy;
- raw aesthetic-only public pretraining corpus contract;
- runtime fusion formula;
- изменение deterministic issue/action taxonomy;
- замену eval harness полноценным dataset pipeline.

Граница ответственности:
- `PR-H03` описывает только rubric/eval-совместимый dataset, который хранится как `HybridDatasetRecord`;
- raw public aesthetic corpora без rubric labels не должны насильно маппиться в `HybridDatasetRecord`;
- contract для таких corpora задается отдельно в [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md).

## Design Summary

Ключевые решения:
- главный supervised target для hybrid stage это не free-form verdict text, а structured rubric вокруг evidence heads из [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md);
- dataset хранит не только image/video asset, но и provenance, label completeness tier, annotator submissions и adjudicated label bundle;
- `pause`-first политика сохраняется и в data strategy: full-rubric still frames важнее, чем большой noisy live dataset;
- labels делятся на primary и secondary:
  - primary: `SceneTypeV1`, shot intent affinity, evidence-head targets, applicability, ambiguity;
  - secondary: critique-compatibility anchors (`verdict/issues/strengths/actions`) для explainability/eval consistency;
- один и тот же dataset schema должен покрывать:
  - public partial supervision;
  - curated full rubric;
  - runtime hard cases;
  - limited live sequence QA.

Нормативное правило:
- если label нельзя объяснить через rubric и closed catalogs, его не должно быть в `PR-H03`.

## Dataset Principles

### 1. Rubric-first, not taste-first

Annotator не отвечает на вопрос "нравится ли кадр", а заполняет:
- какой shot intent наиболее совместим с кадром;
- насколько выражены конкретные evidence axes;
- где head не применим;
- какие deterministic issues/actions такой кадр должен поддерживать или не поддерживать.

### 2. Pause-first data bias

Поскольку первый полезный hybrid milestone из [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md) это `pause-only neural evidence`, минимальный dataset обязан быть:
- в первую очередь single-frame;
- богато размеченным;
- пригодным для ambiguity/calibration cases.

`live` sequence labels в `PR-H03` ограничены QA/stability нуждами и не становятся главным supervised target.

### 3. Runtime-compatibility by construction

Dataset shape обязан быть близок к runtime/eval contracts:
- `SceneTypeV1` и `IssueTypeV1` берутся только из уже frozen catalogs;
- evidence labels используют те же `EvidenceHeadId`, `EvidenceCategoryId` и `SupportingSignalTag`;
- `not_applicable` и `cannot_judge` не смешиваются;
- ambiguous / unknown cases хранятся явно, а не теряются в prose.

### 4. Bucket-aware completeness

Не каждый bucket должен иметь одинаковую глубину labels:
- `curated` и `runtime_hard_case` обязаны иметь full rubric;
- `public` может быть partial rubric, если это не ломает training/eval assumptions.

### 5. Provenance and privacy matter

Каждый record обязан хранить:
- источник происхождения;
- licensing/privacy class;
- consent/runtime-export status для real-world hard cases.

Ни один runtime hard case не должен попадать в dataset без явно сохраненного provenance и export permission status.

## Source Buckets

### Bucket 1. `public`

Роль:
- weak pretraining / auxiliary calibration / broad visual diversity.

Важно:
- в рамках `PR-H03` bucket `public` означает только public assets, которые уже вошли в rubric/eval dataset;
- raw aesthetic-only public corpora без `SceneRoutingLabel` и `EvidenceTargetLabel` не являются `HybridDatasetRecord` и не получают `labelTier` из этого документа;
- такие corpora должны описываться отдельным pretraining manifest из [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md).

Типичные источники:
- public datasets;
- research/demo assets с понятной лицензией;
- non-private still frames, где допустима derivative labeling.

Ограничения:
- не использовать `public` bucket как final truth для cinematic critique;
- partial rubric допустим;
- no private user content.

Обязательные поля:
- `licenseClass`;
- `sourceUrl` или стабильный provenance note;
- `asset.crossDatasetLinkKey`;
- `labelTier = public_partial_rubric` или `full_rubric`.

### Bucket 2. `curated`

Роль:
- main source-of-truth слой для hybrid evidence и critique-compatible supervision.

Типичные источники:
- собственные curated still frames;
- controlled cinematic captures;
- преподавательские/демо-сцены, где можно обеспечить стабильную rubric annotation.

Ограничения:
- требуется full rubric;
- желательно scene-balanced покрытие;
- near-duplicates должны группироваться по shoot/session.

### Bucket 3. `runtime_hard_case`

Роль:
- реальные borderline и failure cases из использования.

Типичные источники:
- false positive / false negative exports;
- ambiguous frames;
- кадры, где deterministic core и human rubric расходятся;
- тяжелые backlight / clutter / prominence / scene-intent cases.

Ограничения:
- provenance и consent обязательны;
- full rubric обязателен;
- bucket не должен silently протекать в `train` без QA и dedup against curated set;
- минимум половина starter runtime hard cases должна быть reserved для `val/test/holdout`, а не только для train.

## Dataset Artifact Model

Минимальный bundle `PR-H03` должен состоять из четырех логических сущностей:
- `DatasetManifest`
- `HybridDatasetRecord`
- `AnnotationSubmission`
- `AdjudicatedLabelBundle`

Рекомендуемый файловый layout:

```text
hybrid_dataset/
  manifest.json
  records.jsonl
  annotations.jsonl
  adjudications.jsonl
  assets/
  qa/
```

## Entity Schema

### 1. `DatasetManifest`

```text
DatasetManifest
- datasetId: String
- schemaVersion: String                  // example: "h03.v1"
- createdAt: Date                       // UTC
- labelPolicyVersion: String            // example: "rubric.v1"
- evidenceTaxonomyVersion: String       // must match PR-H02 source-of-truth version
- sceneCatalogVersion: String           // SceneTypeV1 contract version
- critiqueCatalogVersion: String        // IssueTypeV1 / StrengthTypeV1 / ActionTypeV1 version
- recordCount: Int
- annotationCount: Int
- adjudicatedCount: Int
- bucketStats: [BucketStat]
- splitPolicy: SplitPolicy
- notes: String?
```

```text
BucketStat
- sourceBucket: SourceBucket
- recordCount: Int
- fullRubricCount: Int
- partialRubricCount: Int
- sequenceCount: Int
```

```text
SplitPolicy
- groupBy: SplitGrouping                 // shoot_id | sequence_id | source_asset_group
- defaultTrainRatio: Double
- defaultValidationRatio: Double
- defaultTestRatio: Double
- hardCaseReservedRatio: Double
```

```text
SplitGrouping
- shoot_id
- sequence_id
- source_asset_group
```

### 2. `HybridDatasetRecord`

Одна запись соответствует одному still frame или одной live sequence внутри rubric/eval dataset.

Нормативное уточнение:
- `HybridDatasetRecord` не используется для raw aesthetic-only pretraining corpora;
- если public asset хранит только native aesthetic label source dataset-а, он должен идти через отдельный pretraining manifest из `PR-H04`, а не через этот entity.

```text
HybridDatasetRecord
- recordId: String
- sourceBucket: SourceBucket            // public | curated | runtime_hard_case
- split: DatasetSplit                  // train | validation | test | holdout
- labelTier: LabelTier                 // public_partial_rubric | full_rubric | live_sequence_qa
- caseKind: DatasetCaseKind            // still_frame | live_sequence
- modeTarget: ModeTarget               // pause | live | both
- asset: AssetDescriptor
- grouping: GroupingDescriptor
- sceneContext: SceneContextDescriptor
- qualityGate: QualityGateDescriptor
- tags: [String]
- exportStatus: ExportStatus
- createdAt: Date
```

```text
SourceBucket
- public
- curated
- runtime_hard_case

DatasetSplit
- train
- validation
- test
- holdout

LabelTier
- public_partial_rubric
- full_rubric
- live_sequence_qa

DatasetCaseKind
- still_frame
- live_sequence

ModeTarget
- pause
- live
- both
```

```text
AssetDescriptor
- assetId: String
- assetType: AssetType                  // image | video
- assetRef: String                      // repo/local/object-store pointer
- previewRef: String?                   // optional thumbnail or low-res preview
- assetSha256: String
- crossDatasetLinkKey: String?          // required for public; stable upstream identity hook across PR-H04/H03
- subjectProposalVersion: String?       // required when subject crop is materialized for PR-H05-style dual-view training
- cropRecipeVersion: String?            // required when subject crop is materialized for PR-H05-style dual-view training
- canonicalSubjectRoi: CanonicalSubjectRoi? // optional if no usable deterministic subject proposal exists
- width: Int
- height: Int
- frameCount: Int?                      // required for live_sequence video
- fps: Double?                          // optional for video
- sourceUrl: String?                    // required for public when available
- licenseClass: LicenseClass
- privacyClass: PrivacyClass
```

```text
AssetType
- image
- video

LicenseClass
- public_reusable
- restricted_research
- internal_only

PrivacyClass
- non_sensitive
- consented_runtime_export
- internal_private_do_not_share
```

```text
CanonicalSubjectRoi
- centerXNorm: Double                   // 0.0 ... 1.0
- centerYNorm: Double                   // 0.0 ... 1.0
- widthNorm: Double                     // 0.0 ... 1.0
- heightNorm: Double                    // 0.0 ... 1.0
```

Нормативные правила:
- `sourceBucket = public` требует `asset.crossDatasetLinkKey`;
- если record происходит из raw public pretraining corpus по [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md), `asset.crossDatasetLinkKey` обязан точно совпадать со значением `PublicAestheticPretrainingRecord.crossDatasetLinkKey`;
- `assetSha256` и `crossDatasetLinkKey` не взаимозаменяемы:
  - `assetSha256` идентифицирует конкретный файл/экспорт;
  - `crossDatasetLinkKey` идентифицирует один и тот же upstream public asset across manifests;
- crop/resize/frame-export variants одного и того же public asset могут иметь разные `assetSha256`, но обязаны сохранять общий `crossDatasetLinkKey`.
- если record используется в `PR-H05` dual-view training/eval, то `subjectProposalVersion` и `cropRecipeVersion` обязательны;
- если `canonicalSubjectRoi` присутствует, training/eval/runtime обязаны трактовать его как source-of-truth ROI before square expansion from `PR-H05`;
- если `canonicalSubjectRoi == nil`, это означает only one allowed interpretation:
  - deterministic proposal pipeline указанной `subjectProposalVersion` не нашла usable ROI;
  - downstream обязан использовать zero-crop fallback rather than inventing manual ROI.

```text
GroupingDescriptor
- shootId: String?                      // groups near-duplicates from same shoot
- sequenceId: String?                   // required for live_sequence
- sourceAssetGroup: String?             // groups variants/crops/adjacent frames
```

```text
SceneContextDescriptor
- expectedSceneFamily: SceneTypeV1?     // optional initial routing hint, not final label
- personCentricCandidate: Bool
- likelyAmbiguous: Bool
- runtimeFailureHint: RuntimeFailureHint?
```

```text
RuntimeFailureHint
- false_positive
- false_negative
- unstable_live_hint
- ambiguous_pause_verdict
- unknown
```

```text
QualityGateDescriptor
- assetUsable: Bool
- hasMajorCompressionDamage: Bool
- hasSevereMotionBlur: Bool
- duplicatedWithinGroup: Bool
- annotationPriority: AnnotationPriority
```

```text
AnnotationPriority
- low
- normal
- high
- must_review
```

```text
ExportStatus
- allowed_for_training
- allowed_for_eval_only
- blocked_pending_review
```

### 3. `AnnotationSubmission`

Это независимая разметка одного annotator-а по одному record.

```text
AnnotationSubmission
- submissionId: String
- recordId: String
- annotatorId: String
- rubricVersion: String
- submittedAt: Date
- labelBundle: LabelBundle
- reviewerFlags: [ReviewerFlag]
```

```text
ReviewerFlag
- low_confidence_label
- conflicting_scene_intent
- needs_adjudication
- privacy_question
- duplicate_suspected
```

### 4. `AdjudicatedLabelBundle`

Финальная запись, идущая в training/eval downstream.

```text
AdjudicatedLabelBundle
- adjudicationId: String
- recordId: String
- basedOnSubmissionIds: [String]
- adjudicatorId: String
- adjudicatedAt: Date
- finalLabelBundle: LabelBundle
- adjudicationOutcome: AdjudicationOutcome
- disagreementSummary: DisagreementSummary
- releaseGate: ReleaseGateState
```

```text
AdjudicationOutcome
- accepted_without_changes
- merged_from_multiple_submissions
- corrected_by_adjudicator
- moved_to_holdout
- rejected
```

```text
DisagreementSummary
- severity: DisagreementSeverity
- reasons: [DisagreementReason]
- notes: String?
```

```text
DisagreementSeverity
- none
- soft
- hard
 
CanonicalDisagreementAgreementScore
- none -> 1.00
- soft -> 0.65
- hard -> 0.25
```

Нормативное правило:
- `CanonicalDisagreementAgreementScore` обязателен для всех downstream consumers, которые обучают или оценивают confidence/reliability targets in `PR-H05` and later;
- локальные альтернативные remap tables для `DisagreementSeverity` запрещены.

```text
DisagreementReason
- scene_type_mismatch
- applicability_mismatch
- evidence_band_gap
- critique_anchor_conflict
- privacy_or_provenance_issue
- duplicate_or_split_leak_risk
```

```text
ReleaseGateState
- training_ready
- eval_only
- holdout_only
- blocked
```

## Label Bundle Contract

`LabelBundle` делится на 5 частей:
- case routing;
- evidence supervision;
- critique compatibility anchors;
- ambiguity metadata;
- annotation confidence.

```text
LabelBundle
- sceneRouting: SceneRoutingLabel
- evidenceTargets: [EvidenceTargetLabel]
- critiqueAnchors: CritiqueCompatibilityLabel?
- ambiguity: AmbiguityLabel
- sequenceQa: SequenceQaLabel?          // required for live_sequence_qa
- annotatorConfidence: AnnotatorConfidenceLabel
- notes: String?                         // optional, bounded to 160 chars
```

### 1. `SceneRoutingLabel`

```text
SceneRoutingLabel
- deterministicSceneType: SceneTypeV1
- shotTypeAffinities: [CategoryBandLabel]        // canonical order from PR-H02
- primarySubjectKind: SubjectKind
- personCentric: Bool
```

Нормативные правила:
- `deterministicSceneType` должен быть одним из catalog из [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md);
- `shotTypeAffinities` обязаны покрывать весь `EvidenceCategoryId` catalog в canonical order;
- `unknown_affinity` обязателен всегда;
- `personCentric == false` требует `face_saliency.applicability = not_applicable`.

### 2. `EvidenceTargetLabel`

Каждый allowed `EvidenceHeadId` должен иметь ровно одну dataset label entry.

```text
EvidenceTargetLabel
- headId: EvidenceHeadId
- applicability: LabelApplicability
- band: EvidenceBand?                   // required if applicability == applicable and scalar head
- targetScore: Double?                  // derived from band, not typed manually
- categoryBands: [CategoryBandLabel]    // required only for shot_type_confidence
- supportingSignals: [SupportingSignalTag]
- labelConfidence: LabelConfidenceBand
```

```text
LabelApplicability
- applicable
- not_applicable
- cannot_judge

EvidenceBand
- very_low
- low
- medium
- high
- very_high

LabelConfidenceBand
- low
- medium
- high
```

```text
CategoryBandLabel
- categoryId: EvidenceCategoryId
- band: AffinityBand

AffinityBand
- none
- weak
- plausible
- strong
```

Нормативные правила:
- для scalar heads при `applicability == applicable` annotator выбирает только `band`, а `targetScore` выводится автоматически;
- при `applicability != applicable` поля `band` и `targetScore` должны быть `nil`;
- для `shot_type_confidence` scalar `band` не используется;
- `supportingSignals` ограничены closed vocabulary из `PR-H02`;
- `shot_type_confidence.supportingSignals` всегда `[]`;
- `cannot_judge` разрешен только для asset-quality или extreme ambiguity случаев и всегда требует flag `needs_adjudication`.

### 3. Canonical band-to-score mapping

Чтобы не заставлять annotator-а вводить pseudo-precise числа, используется фиксированное отображение:

| `EvidenceBand` | Derived `targetScore` |
|---|---|
| `very_low` | `0.08` |
| `low` | `0.25` |
| `medium` | `0.50` |
| `high` | `0.75` |
| `very_high` | `0.92` |

Для `shot_type_confidence` используется отдельное canonical отображение:

| `AffinityBand` | Derived affinity score |
|---|---|
| `none` | `0.05` |
| `weak` | `0.25` |
| `plausible` | `0.55` |
| `strong` | `0.82` |

Важно:
- это dataset targets, а не runtime outputs;
- training может later smooth/augment targets, но source labels должны храниться в discrete rubric form.

### 4. `CritiqueCompatibilityLabel`

Это secondary supervision слой. Он обязателен для `full_rubric`, но опционален для `public_partial_rubric`.

```text
CritiqueCompatibilityLabel
- expectedVerdict: FrameVerdict
- likelyIssues: [IssueTypeV1]
- forbiddenIssues: [IssueTypeV1]
- likelyStrengths: [StrengthTypeV1]
- allowedPrimaryActions: [ActionTypeV1]
- goodFramePolicy: GoodFramePolicy
```

```text
GoodFramePolicy
- must_confirm_good_frame
- must_not_confirm_good_frame
- ambiguous
```

Нормативные правила:
- `likelyIssues` и `forbiddenIssues` не могут пересекаться;
- `allowedPrimaryActions` не обязаны содержать единственный winner, но должны оставаться внутри existing `ActionTypeV1` catalog;
- `expectedVerdict == good` несовместим с явным наличием severe readability failure в rubric;
- `cinematic_expressiveness` не может быть единственной причиной `expectedVerdict == good`, если prominence/clutter/lighting явно плохие.

### 5. `AmbiguityLabel`

```text
AmbiguityLabel
- ambiguityLevel: AmbiguityLevel
- reasons: [AmbiguityReason]
- shouldPreferHoldout: Bool
```

```text
AmbiguityLevel
- none
- mild
- moderate
- severe

AmbiguityReason
- multiple_valid_scene_reads
- subject_unclear
- shot_intent_unclear
- lighting_intent_ambiguous
- technical_quality_blocks_labeling
- critique_anchor_uncertain
```

```text
AnnotatorConfidenceLabel
- overall: LabelConfidenceBand
- hardestHeadIds: [EvidenceHeadId]
```

```text
SequenceQaLabel
- stablePrimaryAction: ActionTypeV1?
- expectedHintState: String             // exact closed vocabulary from PR-014 `expectedHintState`
- stabilityAnchorFrame: Int?
- maxFramesToStable: Int?
- frameExpectations: [SequenceFrameExpectation]

SequenceFrameExpectation
- frameOrdinal: Int
- countsTowardStability: Bool
- expectedHintState: String             // exact closed vocabulary from PR-014 `expectedHintState`
- expectedPrimaryAction: ActionTypeV1?
```

Нормативное правило:
- `PR-H03` намеренно не переопределяет отдельный enum для `expectedHintState`;
- поле `expectedHintState` обязано использовать exact closed vocabulary из [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md):
  - `visible_action`
  - `hidden_due_to_motion`
  - `hidden_due_to_low_confidence`
  - `confirm_good_frame`
- отдельный crosswalk layer между dataset и eval для этого поля запрещен.

## Label Tier Policy

Эти tiers применяются только к `HybridDatasetRecord` внутри rubric/eval dataset.
Они не применяются к raw public aesthetic corpora без rubric labels, описываемым в `PR-H04`.

### `full_rubric`

Обязателен для:
- `curated`
- `runtime_hard_case`

Минимальный required set:
- `SceneRoutingLabel`
- все heads из `PR-H02`
- `CritiqueCompatibilityLabel`
- `AmbiguityLabel`
- adjudication из минимум двух independent submissions

### `public_partial_rubric`

Допустим только для `public`.

Минимальный required set:
- `SceneRoutingLabel`
- все scalar heads, разрешенные для целевого mode
- `shot_type_confidence` можно оставлять unlabeled только если record идет исключительно как weak auxiliary pretraining asset и помечен `releaseGate = eval_only` или `training_ready` с explicit waiver in manifest notes
- `CritiqueCompatibilityLabel` опционален

Нормативное уточнение:
- `releaseGate = eval_only` означает, что record не используется ни в semantic, ни в auxiliary training objectives;
- любой `public_partial_rubric` record, который идет в training, обязан иметь `releaseGate = training_ready`.

### `live_sequence_qa`

Используется только для limited `live` bucket.

Минимальный required set:
- sequence-level scene routing;
- dominant issue/action anchors;
- frame-level `countsTowardStability` / `expectedHintState`;
- optional head labels только для anchor frames, а не для каждого frame автоматически.

Нормативные правила:
- для `live_sequence_qa` `sequenceQa` обязателен;
- `evidenceTargets` может быть пустым, если labels даны только на уровне sequence behavior;
- если head labels все же добавляются, они относятся только к anchor frame и должны быть явно отмечены в notes или через linked child record strategy.

## Annotator Guide

Ниже protocol, по которому другой человек должен уметь начать разметку без домысливания.

### Step 1. Быстрый gate перед разметкой

Annotator сначала отвечает только на 4 вопроса:
- asset вообще читаем и не битый?
- нет ли очевидной duplicate/near-duplicate утечки между splits?
- понятен ли provenance?
- нет ли privacy blocker?

Если хотя бы один ответ "нет":
- record не размечается как training-ready;
- ставится `ReviewerFlag` и `releaseGate = blocked` или `holdout_only`.

### Step 2. Определи case routing

Annotator фиксирует:
- это `still_frame` или `live_sequence`;
- для какого mode кейс прежде всего полезен: `pause`, `live`, `both`;
- какой `SceneTypeV1` лучший deterministic read;
- person-centric ли сцена.

Правило:
- если сцена plausibly person-centric, но лицо не читается, это не `not_applicable` для `face_saliency`; это обычно `applicable` с низким band.
- `face_saliency = not_applicable` только когда сцена сама не person-centric.

### Step 3. Проставь `shot_type_affinities`

Annotator не выбирает "единственно правильный жанр", а заполняет affinity rubric:
- `strong`: кадр явно читается как этот intent;
- `plausible`: чтение правдоподобно, но не единственное;
- `weak`: слабая совместимость;
- `none`: почти не похоже.

Правила:
- минимум один category может быть `strong` или `plausible`, но это не обязательно;
- `unknown_affinity` ставится:
  - `strong`, если intent реально неясен или кадр domain-mismatched;
  - `plausible`, если ambiguity умеренная;
  - `none/weak`, если intent достаточно читаем.

### Step 4. Оцени evidence heads по рубрике

Annotator работает не от "общего вкуса", а от конкретных вопросов.

#### `subject_prominence`

Вопрос:
- остается ли главный субъект визуально главным при быстром взгляде?

Подсказки:
- `very_low`: субъект теряется;
- `medium`: субъект заметен, но не доминирует;
- `very_high`: субъект сразу собирает внимание.

#### `background_clutter`

Вопрос:
- дробит ли фон внимание и мешает ли чтению сцены?

Подсказки:
- высокий band ставится, когда есть явная конкуренция объектов, текстур или ярких пятен;
- низкий band ставится, когда фон поддерживает, а не перебивает субъект.

#### `lighting_quality`

Вопрос:
- помогает ли свет читать форму, лицо и separation?

Подсказки:
- низкий band при потере формы, провале лица в тени, паразитном контровом провале;
- высокий band, когда свет делает субъект читаемым и объемным.

#### `face_saliency`

Вопрос:
- работает ли лицо/голова как attention anchor?

Использовать только для person-centric scenes.

Подсказки:
- `not_applicable` для object/establishing-like кадров;
- низкий band, если лицо мелкое, затемнено или не тянет взгляд;
- высокий band, если лицо легко считывается даже без пристального изучения.

#### `balance_confidence`

Вопрос:
- выглядит ли расположение субъекта intentional для предполагаемого shot intent?

Использовать только в `pause`.

Подсказки:
- низкий band, если кадр выглядит случайно смещенным;
- высокий band, если negative space и placement кажутся устойчивыми.

#### `depth_separation`

Вопрос:
- отделяется ли субъект от фона по тону, слоям и depth?

Подсказки:
- низкий band, когда субъект "слипается" с фоном;
- высокий band, когда субъект отчетливо отделен.

#### `cinematic_expressiveness`

Вопрос:
- выглядит ли кадр стилистически собранным сверх базовой нормы?

Ограничение:
- этот head не отменяет problems с readability;
- если prominence/clutter/lighting плохие, высокий expressiveness можно ставить, но нельзя на его основе делать `good` verdict.

### Step 5. Проставь critique anchors

Для `full_rubric` annotator обязан отметить:
- expected verdict;
- likely issues;
- forbidden issues;
- likely strengths;
- allowed primary actions.

Annotator не должен:
- придумывать новые issue/action types;
- писать свободный совет вместо catalog action;
- использовать AVA-style общий score как замену critique anchors.

### Step 6. Отметь ambiguity и сложные случаи

Если кадр допускает несколько чтений, annotator не выбирает произвольно одно из них.

Нужно:
- повысить `ambiguityLevel`;
- отметить `AmbiguityReason`;
- при необходимости поднять `unknown_affinity`;
- если конфликт слишком велик, поставить `shouldPreferHoldout = true`.

### Step 7. Финальная self-check

Перед отправкой annotator проверяет:
- person-centric consistency;
- applicability каждого head-а;
- закрытые vocabularies;
- нет ли противоречия между verdict и anchors;
- нет ли лишнего prose в structured fields.

## Disagreement Resolution

### Required annotation policy

Для `full_rubric`:
- минимум 2 независимые submissions;
- annotator-ы не видят labels друг друга до отправки;
- adjudication обязателен при hard conflict.

Для `public_partial_rubric`:
- допускается 1 annotator + sampling audit;
- второй annotator обязателен для record-ов, идущих в `validation/test`.

### Agreement thresholds

`soft disagreement`:
- difference в scalar head не больше 1 band;
- одинаковая applicability;
- один и тот же dominant scene read или shared top-2 affinity family;
- critique anchors отличаются только по optional strengths или одной secondary action family.

`hard disagreement`:
- applicability mismatch;
- gap по scalar head больше 1 band на любом из heads:
  - `subject_prominence`
  - `background_clutter`
  - `lighting_quality`
  - `face_saliency` (если applicable)
- scene routing conflict между `unknown` и конкретным strong scene read;
- `expectedVerdict` расходится как `good` vs `needs_fix`;
- один annotator ставит `shouldPreferHoldout = true`, второй нет, при `ambiguityLevel >= moderate`.

### Adjudication rules

Adjudicator обязан:
- просмотреть исходный asset, а не только submissions;
- сохранить финальный `LabelBundle` в том же schema;
- кратко отметить причину решения в `DisagreementSummary`;
- перевести record в `holdout` или `blocked`, если ambiguity или provenance не позволяют training-ready label.

Нормативные правила:
- unresolved hard conflict нельзя silently усреднять;
- `cannot_judge` не конвертируется автоматически в `not_applicable`;
- if in doubt between "train noisy label" and "holdout", выбирается `holdout`.

## Split and Dedup Policy

Обязательные правила:
- split делается group-aware, а не по отдельным кадрам;
- кадры из одного `shootId` или `sequenceId` не могут расползаться между `train` и `test`;
- runtime hard cases нельзя все отправлять в train;
- near-duplicates и соседние видеокадры считаются leakage risk.
- public-derived assets с одинаковым `asset.crossDatasetLinkKey` считаются одним upstream identity cluster для split/dedup review;
- если `PR-H03` record ссылается на public source, leakage check обязан учитывать `asset.crossDatasetLinkKey` наряду с `shootId/sequenceId/sourceAssetGroup`.

Рекомендуемая starter policy:
- curated/public: `70 / 15 / 15`
- runtime_hard_case: `50%` reserved to `validation/test/holdout`
- severe ambiguity records: `holdout`

## Minimal Starter Dataset

`PR-H03` не должен ждать большого корпуса. Достаточный starter set для начала hybrid track:

- `120` curated still frames с `full_rubric`
- `48` runtime hard-case still frames с `full_rubric`
- `72` public still frames с `public_partial_rubric`
- `12` live sequences по `6` кадров каждая с `live_sequence_qa`

Итого:
- `240` single-frame records
- `12` sequence records
- `312` размечаемых frame assets, если считать sequence frames отдельно для QA

Минимальное content coverage для `240` still frames:
- не меньше `24` examples для `single_character_medium`
- не меньше `24` examples для `dialogue_closeup`
- не меньше `18` examples для `two_character_frame`
- не меньше `18` examples для `object_insert`
- не меньше `18` examples для `establishing_like_frame`
- не меньше `18` examples для `moody_backlit_subject`
- минимум `36` ambiguity / unknown / borderline cases
- минимум `48` явно проблемных clutter/prominence cases
- минимум `36` good frames, которые не должны переучивать систему на over-coaching

Практический смысл:
- этого достаточно, чтобы начать `PR-H05` прототипирование, sanity-check `PR-H06` schema и первые ablations для `PR-H14`;
- этого недостаточно для финального thesis-grade claim, но достаточно для первой рабочей итерации.

## Example Records

Ниже приведены partial JSON-like examples.
Для реальных dataset artifacts использовать полный canonical набор required полей из schema выше.

### Example A. Curated full-rubric still frame

```json
{
  "recordId": "curated-pause-portrait-001",
  "sourceBucket": "curated",
  "split": "train",
  "labelTier": "full_rubric",
  "caseKind": "still_frame",
  "modeTarget": "pause",
  "asset": {
    "assetId": "asset-001",
    "assetType": "image",
    "assetRef": "assets/curated/portrait_001.jpg",
    "assetSha256": "9d5f...",
    "width": 3024,
    "height": 4032,
    "sourceUrl": null,
    "licenseClass": "internal_only",
    "privacyClass": "non_sensitive"
  },
  "sceneContext": {
    "expectedSceneFamily": "single_character_medium",
    "personCentricCandidate": true,
    "likelyAmbiguous": false,
    "runtimeFailureHint": "unknown"
  }
}
```

```json
{
  "submissionId": "sub-001-a",
  "recordId": "curated-pause-portrait-001",
  "annotatorId": "ann-01",
  "rubricVersion": "rubric.v1",
  "labelBundle": {
    "sceneRouting": {
      "deterministicSceneType": "single_character_medium",
      "shotTypeAffinities": [
        { "categoryId": "dialogue_closeup_affinity", "band": "weak" },
        { "categoryId": "single_character_medium_affinity", "band": "strong" },
        { "categoryId": "two_character_frame_affinity", "band": "none" },
        { "categoryId": "object_insert_affinity", "band": "none" },
        { "categoryId": "establishing_like_frame_affinity", "band": "none" },
        { "categoryId": "moody_backlit_subject_affinity", "band": "weak" },
        { "categoryId": "unknown_affinity", "band": "none" }
      ],
      "primarySubjectKind": "person",
      "personCentric": true
    },
    "evidenceTargets": [
      {
        "headId": "subject_prominence",
        "applicability": "applicable",
        "band": "high",
        "targetScore": 0.75,
        "supportingSignals": ["subject_scale", "subject_attention_pull"],
        "labelConfidence": "high"
      },
      {
        "headId": "background_clutter",
        "applicability": "applicable",
        "band": "low",
        "targetScore": 0.25,
        "supportingSignals": ["attention_competition"],
        "labelConfidence": "medium"
      },
      {
        "headId": "lighting_quality",
        "applicability": "applicable",
        "band": "high",
        "targetScore": 0.75,
        "supportingSignals": ["subject_exposure_readability", "tonal_structure"],
        "labelConfidence": "high"
      },
      {
        "headId": "face_saliency",
        "applicability": "applicable",
        "band": "high",
        "targetScore": 0.75,
        "supportingSignals": ["eye_region_visibility", "facial_anchor_strength"],
        "labelConfidence": "high"
      },
      {
        "headId": "balance_confidence",
        "applicability": "applicable",
        "band": "medium",
        "targetScore": 0.50,
        "supportingSignals": ["frame_balance", "negative_space_fit"],
        "labelConfidence": "medium"
      },
      {
        "headId": "depth_separation",
        "applicability": "applicable",
        "band": "high",
        "targetScore": 0.75,
        "supportingSignals": ["subject_background_contrast"],
        "labelConfidence": "medium"
      },
      {
        "headId": "cinematic_expressiveness",
        "applicability": "applicable",
        "band": "medium",
        "targetScore": 0.50,
        "supportingSignals": ["stylistic_intent"],
        "labelConfidence": "medium"
      },
      {
        "headId": "shot_type_confidence",
        "applicability": "applicable",
        "categoryBands": [
          { "categoryId": "dialogue_closeup_affinity", "band": "weak" },
          { "categoryId": "single_character_medium_affinity", "band": "strong" },
          { "categoryId": "two_character_frame_affinity", "band": "none" },
          { "categoryId": "object_insert_affinity", "band": "none" },
          { "categoryId": "establishing_like_frame_affinity", "band": "none" },
          { "categoryId": "moody_backlit_subject_affinity", "band": "weak" },
          { "categoryId": "unknown_affinity", "band": "none" }
        ],
        "supportingSignals": [],
        "labelConfidence": "medium"
      }
    ],
    "critiqueAnchors": {
      "expectedVerdict": "good",
      "likelyIssues": [],
      "forbiddenIssues": [
        "subject_not_prominent_enough",
        "background_competes_with_subject"
      ],
      "likelyStrengths": [
        "good_subject_isolation",
        "good_light_emphasis"
      ],
      "allowedPrimaryActions": ["leave_frame_as_is"],
      "goodFramePolicy": "must_confirm_good_frame"
    },
    "ambiguity": {
      "ambiguityLevel": "none",
      "reasons": [],
      "shouldPreferHoldout": false
    },
    "annotatorConfidence": {
      "overall": "high",
      "hardestHeadIds": ["balance_confidence"]
    }
  }
}
```

### Example B. Partial runtime hard-case adjudication excerpt

```json
{
  "recordId": "runtime-hard-002",
  "sourceBucket": "runtime_hard_case",
  "split": "validation",
  "labelTier": "full_rubric",
  "caseKind": "still_frame",
  "modeTarget": "pause",
  "sceneContext": {
    "expectedSceneFamily": "moody_backlit_subject",
    "personCentricCandidate": true,
    "likelyAmbiguous": true,
    "runtimeFailureHint": "ambiguous_pause_verdict"
  },
  "qualityGate": {
    "assetUsable": true,
    "hasMajorCompressionDamage": false,
    "hasSevereMotionBlur": false,
    "duplicatedWithinGroup": false,
    "annotationPriority": "must_review"
  }
}
```

```json
{
  "adjudicationId": "adj-002",
  "recordId": "runtime-hard-002",
  "basedOnSubmissionIds": ["sub-002-a", "sub-002-b"],
  "adjudicatorId": "lead-01",
  "finalLabelBundle": {
    "sceneRouting": {
      "deterministicSceneType": "moody_backlit_subject",
      "shotTypeAffinities": [
        { "categoryId": "dialogue_closeup_affinity", "band": "weak" },
        { "categoryId": "single_character_medium_affinity", "band": "plausible" },
        { "categoryId": "two_character_frame_affinity", "band": "none" },
        { "categoryId": "object_insert_affinity", "band": "none" },
        { "categoryId": "establishing_like_frame_affinity", "band": "none" },
        { "categoryId": "moody_backlit_subject_affinity", "band": "strong" },
        { "categoryId": "unknown_affinity", "band": "plausible" }
      ],
      "primarySubjectKind": "face",
      "personCentric": true
    },
    "evidenceTargets": [
      {
        "headId": "lighting_quality",
        "applicability": "applicable",
        "band": "low",
        "targetScore": 0.25,
        "supportingSignals": ["subject_exposure_readability", "facial_light_support"],
        "labelConfidence": "high"
      },
      {
        "headId": "face_saliency",
        "applicability": "applicable",
        "band": "low",
        "targetScore": 0.25,
        "supportingSignals": ["eye_region_visibility"],
        "labelConfidence": "medium"
      },
      {
        "headId": "cinematic_expressiveness",
        "applicability": "applicable",
        "band": "high",
        "targetScore": 0.75,
        "supportingSignals": ["stylistic_intent", "visual_harmony_residual"],
        "labelConfidence": "medium"
      }
    ],
    "critiqueAnchors": {
      "expectedVerdict": "mixed",
      "likelyIssues": ["backlight_hides_subject"],
      "forbiddenIssues": [],
      "likelyStrengths": [],
      "allowedPrimaryActions": ["improve_front_light", "change_angle"],
      "goodFramePolicy": "must_not_confirm_good_frame"
    },
    "ambiguity": {
      "ambiguityLevel": "moderate",
      "reasons": ["lighting_intent_ambiguous", "critique_anchor_uncertain"],
      "shouldPreferHoldout": false
    },
    "annotatorConfidence": {
      "overall": "medium",
      "hardestHeadIds": ["cinematic_expressiveness", "shot_type_confidence"]
    }
  },
  "adjudicationOutcome": "merged_from_multiple_submissions",
  "disagreementSummary": {
    "severity": "soft",
    "reasons": ["evidence_band_gap", "critique_anchor_conflict"],
    "notes": "Issue retained, but good verdict rejected because readability remains weak."
  },
  "releaseGate": "training_ready"
}
```

## QA Checklist

Перед тем как record попадет в `training_ready` или `eval_only`, нужно пройти checklist:

- provenance и licensing задокументированы
- privacy/export status разрешает выбранный use
- split leakage по `shootId/sequenceId/sourceAssetGroup/crossDatasetLinkKey` отсутствует
- для `sourceBucket = public` заполнен `asset.crossDatasetLinkKey`
- если record происходит из raw public pretraining corpus, `asset.crossDatasetLinkKey` совпадает с `PublicAestheticPretrainingRecord.crossDatasetLinkKey`
- `labelTier` соответствует bucket policy
- все required heads присутствуют ровно по одному разу
- `shot_type_confidence` содержит полный closed catalog и canonical order
- `face_saliency = not_applicable` только для non-person-centric cases
- `supportingSignals` лежат только в разрешенном vocabulary
- `cannot_judge` помечен флагом `needs_adjudication`
- `likelyIssues` / `forbiddenIssues` не пересекаются
- `allowedPrimaryActions` используют только existing `ActionTypeV1`
- `good` verdict не конфликтует с очевидно низкими prominence/lighting/clutter anchors
- ambiguous severe cases либо adjudicated, либо переведены в `holdout`
- runtime hard cases не попали в train без QA и provenance review

## Invariants

- Dataset labels не вводят новых user-facing issue/action types поверх frozen deterministic catalogs.
- `not_applicable` и `cannot_judge` различаются во всех artifacts.
- `public` bucket не может быть единственным источником labels для release-gating claims.
- `runtime_hard_case` без provenance/consent не может получить `training_ready`.
- `cinematic_expressiveness` не может быть sole reason for `good` verdict.
- `unknown_affinity` обязателен во всех `shot_type_confidence` labels.
- Полный `full_rubric` record обязан иметь critique-compatible anchors.
- Hard disagreement не усредняется автоматически.
- Holdout policy предпочтительнее noisy forced label.

## Что это разблокирует дальше

После фиксации этого документа:
- `PR-H04` может зафиксировать AVA/public pretraining policy уже против конкретных label tiers и отдельного raw-public pretraining manifest в [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md);
- `PR-H05` может выбирать outputs и losses под закрытый dataset shape;
- `PR-H06` может оформлять runtime/domain contract с максимальным shape match к dataset;
- `PR-H14` может строить hybrid eval buckets вокруг тех же ambiguity, bucket и critique-anchor сущностей.

## Definition of Done (design mode)

Этот design считается готовым, если:
- другой annotator может начать разметку без домысливания;
- schema различает bucket provenance, label tier и adjudication state;
- rubric совместима с `PR-H02` evidence taxonomy и `v1` critique catalogs;
- disagreement protocol отличает soft и hard conflicts;
- minimal starter dataset достаточно конкретен для запуска первой итерации hybrid stage.
