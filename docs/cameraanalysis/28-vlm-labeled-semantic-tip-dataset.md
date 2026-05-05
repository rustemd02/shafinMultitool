# 28. VLM-Labeled Semantic Tip Dataset (PR-S06)

Статус: design spec (source-of-truth)

Дата: 2026-05-05

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md)
- [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [23-hybrid-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/23-hybrid-eval-harness.md)
- [24-semantic-tip-taxonomy-and-action-catalog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md)
- [25-vlm-visual-semantic-evidence-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/25-vlm-visual-semantic-evidence-contract.md)
- [26-semantic-tip-fusion-and-planner.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/26-semantic-tip-fusion-and-planner.md)
- [semantic_tip_dataset_demo_cases.jsonl](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl)

## Цель

Зафиксировать dataset loop для `PR-S06`, где `VLM` используется как teacher для semantic screen tips, но не становится runtime dependency и не получает статус gold source-of-truth.

Ключевая формула:

`pause frame + deterministic snapshot + validated VLM evidence + human review -> final semantic tip label bundle`

Этот документ нужен, чтобы:
- начать собирать пары `frame -> evidence -> semantic tip` без product/runtime drift;
- хранить entity-aware targets и human-corrected labels в одном repeatable schema;
- экспортировать hard cases для review/eval без хранения сырых приватных изображений по умолчанию;
- подготовить distillation-ready supervision для будущего `PR-S07`.

## Scope

`PR-S06` отвечает за:
- schema для dataset records, teacher submissions, reviewed tip labels и hard-case exchange;
- entity-aware поля для target/secondary entities, display labels и `actionFrame`;
- privacy/provenance policy для demo, curated и runtime hard cases;
- review workflow `VLM suggestion -> human accept/edit/reject`;
- eval compatibility with [23-hybrid-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/23-hybrid-eval-harness.md);
- starter fixtures `10...20` synthetic/demo cases.

`PR-S06` не отвечает за:
- runtime wiring inside app;
- offloading/provider implementation;
- замену `PR-S01/PR-S02/PR-S04` contracts;
- обучение модели и loss design;
- free-form prose labeling;
- хранение raw private user images as default dataset policy.

## Design Summary

Нормативные решения `PR-S06`:
- teacher supervision хранится отдельно от final reviewed label;
- `VLM` может предложить evidence, grounded labels и candidate actions только в closed catalogs `PR-S01/PR-S02`;
- финальный label bundle становится gold только после human review;
- dataset обязан хранить deterministic baseline рядом с teacher evidence, чтобы было видно:
  - что уже знал local pipeline;
  - что добавил `VLM`;
  - что принял, отредактировал или отклонил reviewer;
- privacy/provenance поля обязательны для каждого record, даже для synthetic/demo fixtures;
- entity display labels не хранятся как свободный текст без confidence/source metadata;
- hard-case export/import должен работать на redacted visuals или structured-only payloads.

## Relationship to Existing Dataset Contracts

`PR-S06` не заменяет [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md), а специализирует его под semantic tips.

Authoritative layering:
- `PR-H03` описывает общий rubric-driven hybrid dataset;
- `PR-S06` описывает teacher-review loop для semantic tip supervision;
- `PR-S06` может жить как отдельный bundle или как specialized overlay над `HybridDatasetRecord`, если implementation later решит объединить storage.

Нормативное правило:
- если команда хранит `PR-S06` поверх `PR-H03`, `recordId`, `frameId`, `crossDatasetLinkKey` и privacy/provenance identities должны совпадать;
- semantic-tip-specific sidecars не имеют права менять исходные deterministic/eval identities.

## Dataset Principles

### 1. Teacher is not gold

- `VLM` suggestion всегда provisional;
- `accepted` и `edited` reviewed labels допустимы как training/eval truth;
- `rejected` teacher outputs сохраняются для error analysis и calibration, но не становятся positive supervision.

### 2. Entity-aware, not prose-aware

Главная supervised цель — не красивый текст, а закрытый structured bundle:
- `tipType`
- `actionType`
- `actionFrame`
- `direction`
- `target entity`
- `secondary entity`
- `display label policy result`
- `review outcome`

Текст `live/pause` может добавляться как derived artifact, но не является source-of-truth target.

### 3. Privacy-first by default

- без явного consent/private export approval raw private stills не входят в dataset bundle;
- structured-only records разрешены даже без visual asset export;
- redacted visual exports допустимы только с явным provenance и redaction note.

### 4. Eval-compatible by construction

Каждый reviewed record должен быть проектируем в eval shape:
- tip correctness;
- action correctness;
- target grounding correctness;
- teacher-vs-human disagreement;
- deterministic-vs-reviewed delta;
- privacy/export availability.

### 5. Distillation-ready labels

Даже если `PR-S07` еще не реализован, `PR-S06` уже обязан хранить:
- entity kind;
- relation/conflict type;
- label confidence;
- `actionFrame`;
- semantic target ids;
- uncertainty/rejection reasons.

## Recommended Bundle Layout

```text
semantic_tip_dataset/
  manifest.json
  records.jsonl
  teacher_submissions.jsonl
  reviewed_labels.jsonl
  hard_case_exports/
  qa/
```

Минимальный design-ready starter bundle в репозитории:
- [semantic_tip_dataset_demo_cases.jsonl](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl)

## Entity Schema

### 1. `SemanticTipDatasetManifest`

```text
SemanticTipDatasetManifest
- datasetId: String
- schemaVersion: String                       // example: "s6.v1"
- createdAt: Date                            // UTC
- semanticTipCatalogVersion: String          // must match PR-S01 source-of-truth version
- vlmEvidenceSchemaVersion: String           // must match PR-S02, example: "s1"
- deterministicSnapshotVersion: String       // local snapshot/critique/planner contract version
- hybridDatasetSchemaVersion: String?        // optional bridge to PR-H03
- evalProfile: String                        // example: "semantic_tip_eval_v1"
- recordCount: Int
- teacherSubmissionCount: Int
- reviewedCount: Int
- sourceBucketStats: [SemanticTipBucketStat]
- notes: String?

SemanticTipBucketStat
- sourceBucket: SemanticTipSourceBucket
- recordCount: Int
- reviewedCount: Int
- structuredOnlyCount: Int
- redactedVisualCount: Int
```

### 2. `SemanticTipDatasetRecord`

Один record соответствует одному still frame или одной reviewable pause-case записи.

```text
SemanticTipDatasetRecord
- recordId: String
- frameId: String
- sourceBucket: SemanticTipSourceBucket
- split: DatasetSplit                        // train | validation | test | holdout
- modeTarget: ModeTarget                     // pause | live | both
- caseKind: SemanticTipCaseKind              // still_frame | structured_only_case | redacted_visual_case
- asset: SemanticTipAssetDescriptor
- provenance: SemanticTipProvenance
- privacy: SemanticTipPrivacyDescriptor
- deterministicBaseline: SemanticTipDeterministicBaseline
- teacherSubmissionIds: [String]
- reviewedLabelId: String?
- reviewStatus: SemanticTipReviewStatus
- tags: [String]
- createdAt: Date
```

```text
SemanticTipSourceBucket
- curated_demo
- curated_real
- runtime_hard_case
- public_relicensed_demo
```

Нормативные правила:
- `curated_demo` используется для synthetic/demo fixtures без приватных изображений;
- `runtime_hard_case` не может существовать без explicit provenance/export status;
- `modeTarget = live` разрешен только для dataset cases, где final supervision still materialize-ится в closed semantic tip contract, а не в sequence-level prose.

### 3. `SemanticTipAssetDescriptor`

```text
SemanticTipAssetDescriptor
- assetRef: String                           // stable opaque ref
- assetKind: SemanticTipAssetKind
- crossDatasetLinkKey: String                // required for dedup/eval bridging
- sceneBrief: String                         // short non-private synthetic or review note
- redactedVisualRef: String?                 // optional, only for redacted_visual_case
- visualAvailability: SemanticTipVisualAvailability
- width: Int?
- height: Int?
- sha256: String?                            // only if asset file exists

SemanticTipAssetKind
- synthetic_brief_only
- redacted_still
- redacted_subject_crop
- real_private_not_exported

SemanticTipVisualAvailability
- none_structured_only
- redacted_visual_available
- private_not_exported
```

Нормативные правила:
- `sceneBrief` обязателен всегда, even when visual asset unavailable;
- `synthetic_brief_only` используется для демо/fixtures и не требует image asset;
- `real_private_not_exported` разрешен только внутри internal review systems, но в repo fixtures должен отсутствовать.

### 4. `SemanticTipProvenance`

```text
SemanticTipProvenance
- sourceOrigin: SemanticTipSourceOrigin
- sourceSessionId: String?
- sourceCaptureId: String?
- annotatorNote: String?
- consentStatus: SemanticTipConsentStatus
- exportStatus: SemanticTipExportStatus
- licenseClass: String
- createdBy: String                          // human/team/tool id

SemanticTipSourceOrigin
- synthetic_demo
- internal_curated_capture
- runtime_feedback_export
- public_relicensed

SemanticTipConsentStatus
- not_required_synthetic
- granted_internal_review
- granted_redacted_export
- denied_export
- unknown

SemanticTipExportStatus
- repo_safe_structured_only
- repo_safe_redacted_visual
- internal_only
- blocked
```

Нормативные правила:
- `exportStatus` и `consentStatus` обязательны всегда;
- `blocked` records не попадают в shared dataset bundles;
- `runtime_feedback_export` cases без `granted_redacted_export` могут существовать только как structured-only records.

### 5. `SemanticTipPrivacyDescriptor`

```text
SemanticTipPrivacyDescriptor
- privacyTier: DeepCriticPrivacyTier         // structured_only | redacted_visual
- containsRealPerson: Bool
- containsReadableText: Bool
- containsBiometricSensitiveFace: Bool
- redactionApplied: Bool
- redactionNotes: [String]
- reviewerMayRequestVisual: Bool
```

Нормативные правила:
- если `privacyTier == structured_only`, `redactionApplied` может быть `false`, но `redactedVisualRef` обязан быть `nil`;
- если `privacyTier == redacted_visual`, `redactionApplied == true` обязателен для repo-safe exports;
- `containsBiometricSensitiveFace == true` не запрещает record автоматически, но требует structured-only or redacted export discipline.

### 6. `SemanticTipDeterministicBaseline`

Этот блок фиксирует, что локальный pipeline уже знал до teacher stage.

```text
SemanticTipDeterministicBaseline
- snapshotRef: String?                       // optional external fixture ref
- sceneType: String
- primarySubjectKind: String
- primarySubjectRef: String?
- issueTypes: [String]
- strengthTypes: [String]
- recommendedActionTypes: [String]
- baselineTipType: String?
- baselineActionType: String?
- eligibleHeadIds: [String]
- traceSummaryRef: String?
- deterministicConfidence: Double?
```

Нормативные правила:
- `issueTypes`, `strengthTypes` и `recommendedActionTypes` используют only frozen catalogs;
- `baselineTipType` и `baselineActionType` могут быть `nil`, если deterministic planner еще не materialize-ил final semantic tip;
- teacher/human review не должны переписывать этот baseline block post hoc.

### 7. `SemanticTipTeacherSubmission`

Teacher submission хранит машинную подсказку и evidence, но не gold truth.

```text
SemanticTipTeacherSubmission
- submissionId: String
- recordId: String
- providerKind: NeuralEvidenceProviderKind   // remote_teacher | mock
- requestSchemaVersion: String               // "s1"
- responseStatus: VLMResponseStatus
- privacyTier: DeepCriticPrivacyTier
- requestContextRef: String?                 // optional external JSON fixture ref
- evidenceDimensions: [VLMVisualEvidenceDimension]
- suggestedActionIds: [String]
- groundedTarget: SemanticTipGroundedEntity?
- groundedSecondary: SemanticTipGroundedEntity?
- relationType: String?
- teacherProposal: SemanticTipTeacherProposal?
- uncertaintyReasons: [String]
- teacherConfidence: Double?
- createdAt: Date
```

```text
SemanticTipGroundedEntity
- entityKind: String
- entityRole: String
- entityRef: String?
- displayLabelCandidate: String
- labelConfidence: Double
- labelSource: SemanticTipLabelSource

SemanticTipLabelSource
- deterministic_local
- vlm_visual
- vlm_structured_copy
- human_override
```

```text
SemanticTipTeacherProposal
- tipType: String?
- actionType: String?
- actionFrame: String?
- direction: String?
- visualProblemType: String?
- visualStrengthType: String?
- liveTextDraft: String?
- pauseTextDraft: String?
```

Нормативные правила:
- `teacherProposal` допускается только в closed `PR-S01` catalogs;
- `liveTextDraft` и `pauseTextDraft` являются debug-only material and never gold targets;
- `structured_only` teacher submission не может invent specific object label absent from local context;
- `labelConfidence` обязателен для любых concrete display labels.

### 8. `ReviewedSemanticTipLabel`

```text
ReviewedSemanticTipLabel
- reviewedLabelId: String
- recordId: String
- decision: SemanticTipReviewDecision
- finalTip: FinalSemanticTipLabel?
- override: SemanticTipHumanOverride?
- reviewerId: String
- reviewedAt: Date
- qaFlags: [String]
- notes: String?
```

```text
SemanticTipReviewDecision
- accepted_teacher_tip
- edited_teacher_tip
- rejected_teacher_tip
- deterministic_only
- no_tip_should_fire
- needs_followup
```

```text
FinalSemanticTipLabel
- tipType: String
- actionType: String
- actionFrame: String
- direction: String?
- problemType: String?
- strengthType: String?
- targetEntityKind: String
- targetEntityRole: String
- targetEntityRef: String?
- targetEntityLabelConfidence: Double?
- targetEntityDisplayLabel: String
- humanCorrectedTargetDisplayLabel: String?
- secondaryEntityKind: String?
- secondaryEntityRole: String?
- secondaryEntityRef: String?
- secondaryEntityLabelConfidence: Double?
- secondaryEntityDisplayLabel: String?
- humanCorrectedSecondaryDisplayLabel: String?
- linkedIssueTypes: [String]
- linkedStrengthTypes: [String]
- linkedSemanticActionTypes: [String]         // SemanticActionType ids from PR-S01
- linkedPlannerActionTypes: [String]?         // optional ActionTypeV1 ids from RecommendationPlan
- actionabilityScore: Double?
- labelConfidence: Double
```

```text
SemanticTipHumanOverride
- editedFields: [String]
- overrideReasonCodes: [SemanticTipOverrideReason]
- reviewerComment: String?

SemanticTipOverrideReason
- wrong_tip_family
- wrong_action_frame
- wrong_target_entity
- label_too_specific
- label_too_generic
- weak_grounding
- privacy_sensitive_label
- useful_but_not_best
- no_actionable_tip
- deterministic_better_than_teacher
```

Нормативные правила:
- `accepted_teacher_tip` допускает `override == nil`;
- `edited_teacher_tip` требует both `finalTip` and `override`;
- `rejected_teacher_tip` может сохранять `finalTip == nil`, если правильный outcome — no-tip or deterministic-only path;
- `humanCorrectedTargetDisplayLabel` и `humanCorrectedSecondaryDisplayLabel` заполняются только when reviewer реально исправил label, а не дублируют исходное значение.
- `linkedSemanticActionTypes` обязаны содержать только `SemanticActionType` ids;
- если нужен явный мост к planner-level действиям, используется optional `linkedPlannerActionTypes` с `ActionTypeV1` ids.

## Review Workflow

### Stage 1. Record capture

Сохраняется:
- stable `recordId` / `frameId`;
- deterministic baseline;
- privacy/provenance metadata;
- visual asset ref only if repo-safe.

### Stage 2. Teacher submission

`VLM` или mock-teacher возвращает:
- bounded evidence dimensions;
- allowed `suggestedActionIds`;
- optional grounded entity labels;
- optional closed-catalog proposal.

### Stage 3. Validation gate

Перед review сохраняются только contract-safe submissions:
- unknown ids => submission marked invalid;
- unsafe labels => stripped or downgraded;
- privacy mismatch => `responseStatus` preserved, proposal blocked from review acceptance.

### Stage 4. Human review

Reviewer выбирает один из исходов:
- accept;
- edit;
- reject;
- deterministic only;
- no tip;
- needs follow-up.

Обязательная проверка reviewer-а:
- полезно ли действие физически;
- корректен ли actor of change (`camera/subject/object/light/wait`);
- safe ли target label;
- не contradict-ит ли final tip deterministic finding chain.

### Stage 5. Eval projection

Reviewed label проецируется в eval-friendly fields:
- tip correctness;
- action correctness;
- target grounding correctness;
- teacher agreement;
- deterministic delta;
- privacy/export availability.

## Hard-Case Export / Import Contract

### Export bundle shape

```text
SemanticTipHardCaseExportBundle
- exportBundleId: String
- schemaVersion: String                    // "s6.v1"
- createdAt: Date
- exportPolicy: String
- records: [SemanticTipDatasetRecord]
- teacherSubmissions: [SemanticTipTeacherSubmission]
- reviewedLabels: [ReviewedSemanticTipLabel]
- includedVisualArtifacts: [String]        // redacted refs only
- notes: String?
```

### Export rules

- export uses only `repo_safe_structured_only` or `repo_safe_redacted_visual` records;
- raw private assets never leave internal storage via this bundle;
- `includedVisualArtifacts` may reference only redacted stills/crops;
- if no visual export allowed, record still remains useful through structured-only baseline + teacher + review metadata.

### Import rules

- imported record must preserve `recordId`, `frameId` and `crossDatasetLinkKey`;
- duplicate `recordId` with different provenance is hard error;
- imported labels cannot silently overwrite existing reviewed labels without explicit merge decision;
- `edited_teacher_tip` imported from external review keeps `overrideReasonCodes`.

## QA Checklist

Каждый review batch обязан проверить:
- `recordId`, `frameId`, `submissionId`, `reviewedLabelId` стабильны и уникальны;
- privacy/provenance fields non-empty;
- all `tipType`, `actionType`, `actionFrame`, `direction`, `problemType`, `strengthType` belong to closed catalogs;
- `structured_only` submissions do not invent new specific object labels;
- any specific object/prop label has `labelConfidence >= 0.75` or explicit human correction;
- `accepted_teacher_tip` without `finalTip` is forbidden;
- `edited_teacher_tip` without `overrideReasonCodes` is forbidden;
- `keep_current_setup` does not coexist with corrective action ids in final label;
- `actionFrame == wait` appears only with `wait_for_background_clearance`;
- `privacyTier == redacted_visual` implies redaction metadata and repo-safe export status.

## Eval Compatibility Note

`PR-S06` должен быть совместим с [23-hybrid-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/23-hybrid-eval-harness.md), но не обязан форкать его schema.

Минимальная projection strategy:
- `deterministicBaseline.issueTypes/strengthTypes/recommendedActionTypes` -> existing hybrid case anchors;
- `teacherSubmission.evidenceDimensions` -> hybrid teacher-support metadata;
- `reviewedLabel.finalTip.tipType/actionType/actionFrame/target labels` -> semantic-tip eval targets;
- `decision` and `overrideReasonCodes` -> disagreement/error-analysis metrics;
- `privacy.visualAvailability/exportStatus` -> offload-safe availability metrics.

Рекомендуемые новые semantic-tip metrics:
- `tip_exact_match_rate`
- `action_type_match_rate`
- `action_frame_match_rate`
- `target_role_match_rate`
- `target_label_accept_rate`
- `teacher_accept_rate`
- `teacher_edit_distance_rate`
- `deterministic_to_review_uplift_rate`

Нормативное правило:
- `teacher_accept_rate` не является standalone success metric;
- release or thesis claims опираются на human-reviewed final labels and downstream tip usefulness, а не на raw agreement с teacher.

## Starter Fixtures

`PR-S06` design считается incomplete без начального synthetic/demo seed.

В репозитории для этого добавлен:
- [semantic_tip_dataset_demo_cases.jsonl](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl)
- [semantic_tip_dataset_tools.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/semantic_tip_dataset_tools.py)

Требования к starter seed:
- `10...20` records;
- без реальных приватных изображений;
- покрытие camera / subject / object / light / wait action frames;
- mix of `accepted`, `edited`, `rejected`, `deterministic_only`;
- хотя бы `2` positive/good-frame examples;
- хотя бы `3` object-aware or prop-aware examples;
- хотя бы `2` structured-only cases.

## Implementation Hooks (PR-S06)

Для `implement`-этапа в `eval` каталоге поддерживаются команды:

```bash
python3 docs/cameraanalysis/eval/semantic_tip_dataset_tools.py validate \
  --input docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl
```

```bash
python3 docs/cameraanalysis/eval/semantic_tip_dataset_tools.py export-hard-cases \
  --input docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl \
  --output docs/cameraanalysis/eval/out_hybrid/semantic_tip_hard_cases.json \
  --source-bucket runtime_hard_case
```

```bash
python3 docs/cameraanalysis/eval/semantic_tip_dataset_tools.py import-hard-cases \
  --base docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl \
  --bundle docs/cameraanalysis/eval/out_hybrid/semantic_tip_hard_cases.json \
  --output /tmp/semantic_tip_dataset_merged.jsonl \
  --conflict-mode skip
```

## Example Reviewed Case

```json
{
  "recordId": "demo_tip_004",
  "frameId": "frame_demo_004",
  "sourceBucket": "curated_demo",
  "privacyTier": "structured_only",
  "deterministicBaseline": {
    "issueTypes": ["background_clutter", "object_conflicts_with_subject"],
    "recommendedActionTypes": ["remove_distracting_object"]
  },
  "teacherSubmission": {
    "suggestedActionIds": ["remove_distracting_object", "reposition_prop_for_balance"],
    "groundedTarget": {
      "entityKind": "prop",
      "entityRole": "distracting_object",
      "displayLabelCandidate": "ваза",
      "labelConfidence": 0.82,
      "labelSource": "deterministic_local"
    }
  },
  "reviewedLabel": {
    "decision": "edited_teacher_tip",
    "finalTip": {
      "tipType": "remove_distracting_prop",
      "actionType": "remove_distracting_object",
      "actionFrame": "move_object",
      "targetEntityKind": "prop",
      "targetEntityRole": "distracting_object",
      "targetEntityDisplayLabel": "предмет",
      "humanCorrectedTargetDisplayLabel": "ваза",
      "linkedIssueTypes": ["background_clutter", "object_conflicts_with_subject"],
      "linkedSemanticActionTypes": ["remove_distracting_object"],
      "linkedPlannerActionTypes": ["reduce_background_distractions"],
      "labelConfidence": 0.93
    },
    "override": {
      "editedFields": ["targetEntityDisplayLabel"],
      "overrideReasonCodes": ["useful_but_not_best"]
    }
  }
}
```

## Definition of Done for `design`

`PR-S06 design` считается готовым, когда:
- можно начать собирать пары `frame -> evidence -> semantic tip` без догадок о schema;
- records сохраняют deterministic baseline, VLM evidence, final reviewed tip and human override;
- entity-aware labels и `actionFrame` materialize-ятся в closed fields, а не в prose;
- privacy/provenance обязательны и проверяемы;
- hard-case export/import не требует raw private images by default;
- starter fixtures уже существуют и пригодны для eval/bootstrap.
