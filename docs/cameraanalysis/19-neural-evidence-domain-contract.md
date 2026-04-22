# 19. Neural Evidence Domain Contract (PR-H06)

Статус: design spec (source-of-truth)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md)
- [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md)
- [18-hybrid-model-architecture-spec.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/18-hybrid-model-architecture-spec.md)

## Цель

Зафиксировать production/runtime contract для `NeuralEvidenceSnapshot` так, чтобы:
- `PR-H07` мог реализовать on-device wrapper с фиксированной формой output;
- `PR-H08` мог безопасно подмешивать neural evidence в `pause` без неявных статусов и shape drift;
- `PR-H09` мог строить fusion только на стабильных и сериализуемых semantics;
- `PR-H14` мог валидировать hybrid behavior на repeatable JSON fixtures;
- runtime API не зависел от конкретного backbone, `AVA`-специфичных сущностей или transport-specific полей.

Этот документ намеренно не переопределяет taxonomy из [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md) и не вводит fusion formulas. Он закрывает именно runtime handoff между model wrapper, domain layer, storage/debug и downstream critique/fusion.

## Scope

`PR-H06` отвечает за:
- canonical runtime envelope `NeuralEvidenceSnapshot`;
- fixed ordering и closed catalogs;
- status / applicability / confidence semantics на domain-слое;
- serialization rules для JSON/debug/eval fixtures;
- model provenance и failure surface;
- invariants и contract-test expectations.

`PR-H06` не отвечает за:
- выбор backbone;
- training losses;
- fusion formulas;
- cadence policy;
- server offloading payload;
- user-facing verdict/action semantics.

## Design Summary

Ключевая формула `PR-H06`:

`raw model tensors -> wrapper normalization -> NeuralEvidenceSnapshot -> bounded fusion`

Из нее следуют обязательные правила:
- runtime contract остается model-agnostic: он знает только heads, status, scores, confidence и provenance;
- snapshot всегда dense и mode-aware;
- `not_applicable` выражает policy, а не runtime error;
- `unavailable` выражает допустимый runtime failure, а не semantic low score;
- `score == 0` означает реальное значение оси, а не пропуск;
- все outputs пригодны для JSON serialization без догадок downstream-кода;
- никакой head не несет verdict/action/issue semantics напрямую.

## Canonical Runtime Contract

`NeuralEvidenceSnapshot` продолжает shape, уже замороженный в [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md), но `PR-H06` делает его полноценным runtime source-of-truth:

```text
NeuralEvidenceSnapshot
- schemaVersion: String                     // required, example: "h1"
- frameId: String                          // required, must match deterministic frameId
- mode: AnalysisMode                       // required, live | pause
- capturedAt: Date                         // required, UTC
- bundleVersion: String                    // required, model/runtime bundle identifier
- headOutputs: [NeuralEvidenceHeadEntry]   // required, dense canonical list in fixed order

NeuralEvidenceRuntimeMetadata
- metadataSchemaVersion: String             // required, canonical baseline: same value as snapshot.schemaVersion
- frameId: String                          // required, must match snapshot.frameId
- mode: AnalysisMode                       // required, must match snapshot.mode
- providerKind: NeuralEvidenceProviderKind // required
- inferenceTarget: InferenceTargetKind     // required
- modelFamily: String                      // required, stable family id, not marketing text
- modelVersion: String                     // required
- preprocessingVersion: String             // required
- thresholdProfile: String                 // required
- producedAt: Date                         // required, UTC
- latencyMs: Int?                          // optional
- roiStrategy: NeuralEvidenceROIStrategy   // optional
- failureReason: NeuralEvidenceFailureReason? // optional, snapshot-level failure summary

NeuralEvidenceProviderKind
- coreml_local
- mock
- remote_teacher

InferenceTargetKind
- on_device
- offloaded

NeuralEvidenceROIStrategy
- full_frame_only
- full_frame_plus_subject_crop
- subject_crop_only

NeuralEvidenceFailureReason
- model_not_loaded
- preprocessing_failed
- inference_failed
- postprocessing_failed
- policy_skipped
- runtime_timeout
- unknown

NeuralEvidenceHeadEntry
- headId: EvidenceHeadId
- payload: ScalarEvidenceHeadOutput | CategoricalEvidenceHeadOutput
```

Нормативные правила:
- canonical production snapshot shape не имеет права расходиться с envelope, зафиксированным в `PR-H02`;
- provenance/runtime diagnostics живут в `NeuralEvidenceRuntimeMetadata` sidecar, а не внутри canonical `NeuralEvidenceSnapshot`;
- `NeuralEvidenceRuntimeMetadata.failureReason` описывает snapshot-level degradation и не подменяет per-head `status`;
- `NeuralEvidenceRuntimeMetadata.metadataSchemaVersion` обязателен и в baseline `PR-H06` должен совпадать с `NeuralEvidenceSnapshot.schemaVersion`;
- sidecar не имеет права эволюционировать как отдельный wire contract без явного обновления этой spec;
- `failureReason` допустим даже если часть head-ов `available`, когда snapshot получен из partial/degraded path;
- `providerKind = remote_teacher` разрешен только для future-compatible transport neutrality и не делает offloading частью baseline UX;
- `bundleVersion` должен быть пригоден для stable fixture comparison и regression triage;
- `modelFamily`, `modelVersion`, `preprocessingVersion` и `thresholdProfile` обязательны, чтобы downstream мог объяснить изменение output без чтения wrapper-кода.
- если runtime metadata вообще не сохраняется, сам `NeuralEvidenceSnapshot` остается валидным и самодостаточным domain object.

## Head Payload Rules

Runtime использует только два канонических payload shape:

```text
ScalarEvidenceHeadOutput
- headId: EvidenceHeadId
- status: EvidenceHeadStatus
- score: Double?                      // 0...1, nil if status != available
- confidence: Double                  // 0...1
- mode: AnalysisMode
- supportingSignals: [SupportingSignalTag]

CategoricalEvidenceHeadOutput
- headId: EvidenceHeadId
- status: EvidenceHeadStatus
- affinities: [EvidenceCategoryScore] // closed catalog, fixed order
- confidence: Double                  // 0...1
- mode: AnalysisMode
- supportingSignals: [SupportingSignalTag]

EvidenceHeadStatus
- available
- not_applicable
- unavailable

EvidenceCategoryScore
- categoryId: EvidenceCategoryId
- score: Double                       // 0...1
```

`PR-H06` добавляет следующие runtime-обязательства:
- `payload.headId == NeuralEvidenceHeadEntry.headId`;
- `payload.mode == NeuralEvidenceSnapshot.mode`;
- scalar head не может сериализоваться как categorical payload;
- `shot_type_confidence` всегда categorical;
- все остальные heads всегда scalar;
- `supportingSignals` сериализуются уже after mask/filter/postprocess, а не как raw logits top-k;
- для любого scalar head-а `supportingSignals.count` обязан быть в диапазоне `0...2`;
- для `shot_type_confidence` `supportingSignals.count == 0`.

## Canonical Ordering

### Head order

`headOutputs` всегда сериализуются в одном порядке:
1. `subject_prominence`
2. `background_clutter`
3. `lighting_quality`
4. `face_saliency`
5. `balance_confidence`
6. `depth_separation`
7. `cinematic_expressiveness`
8. `shot_type_confidence`

### Category order for `shot_type_confidence`

`affinities` всегда сериализуются в одном порядке:
1. `dialogue_closeup_affinity`
2. `single_character_medium_affinity`
3. `two_character_frame_affinity`
4. `object_insert_affinity`
5. `establishing_like_frame_affinity`
6. `moody_backlit_subject_affinity`
7. `unknown_affinity`

### Supporting-signal order

Если список `supportingSignals` не пуст, он сериализуется в global canonical order из [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md), а не в порядке model confidence.

### Supporting-signal cardinality

`PR-H06` наследует sparse-emission policy из `PR-H02/PR-H05`:
- для scalar head-а разрешено сериализовать только `0`, `1` или `2` supporting tags;
- для `shot_type_confidence` supporting tags всегда запрещены и сериализуются как `[]`;
- wrapper не может сохранять более двух tag-ов даже если после mask/threshold их осталось больше;
- если кандидатов больше двух, runtime обязан выбрать не более двух material factors, а затем отсортировать их в canonical vocabulary order.

## Status Semantics

### `available`

Head считается `available`, если:
- head разрешен policy для текущего `mode`;
- wrapper получил валидный raw output;
- postprocessing успешно построил contract-safe payload;
- payload удовлетворяет всем range/mask/order invariants.

### `not_applicable`

Head считается `not_applicable`, если:
- head запрещен для текущего `mode` по frozen policy;
- или head семантически неприменим к кадру по уже собранному deterministic contract.

Нормативные правила:
- `not_applicable` не является ошибкой;
- `not_applicable` должен появляться детерминированно при одинаковом input policy;
- wrapper не имеет права кодировать `not_applicable` через `score = 0`.

### Applicability anchor for `face_saliency`

`PR-H06` фиксирует один authoritative source для person-centric applicability:
- runtime обязан использовать только `SceneSemanticsReport.primarySubject.kind` из deterministic semantics layer;
- кадр считается person-centric тогда и только тогда, когда `primarySubject.kind in {face, person, group}`;
- при `primarySubject.kind in {object, unknown}` head `face_saliency` обязан сериализоваться как `not_applicable`;
- raw detector outputs, `personDetected`, scene type guess или ad hoc wrapper heuristics не могут самостоятельно переопределять это решение.

Failure policy:
- если `face_saliency` разрешен по mode policy, но `SceneSemanticsReport` недоступен или `primarySubject.kind` отсутствует/невалиден, это не `not_applicable`, а `unavailable`;
- следовательно, `PR-H07/H08` обязаны получать deterministic semantics input до final applicability resolution для `face_saliency`.

### `unavailable`

Head считается `unavailable`, если:
- head должен был исполняться по policy;
- но runtime не смог получить валидный contract-safe output.

Типичные причины:
- локальная инференс-ошибка;
- timeout;
- corrupted tensor shape;
- postprocess mask failure;
- missing required deterministic applicability input.

Нормативные правила:
- `unavailable` не должен использоваться вместо `not_applicable`;
- при `unavailable` downstream видит отсутствие usable signal, а не низкий score;
- `unavailable` допустим как у отдельных head-ов, так и у всех head-ов snapshot-а.

## Range and Confidence Semantics

Обязательные правила:
- все `score`, `confidence` и category `score` нормализованы в диапазон `0.0 ... 1.0`;
- runtime хранит уже clamped postprocessed значения;
- raw logits и промежуточные thresholding values не сериализуются в domain contract;
- `confidence` описывает reliability head-а в текущем кадре, а не importance head-а в продукте;
- `confidence` никогда не заменяет `status`.

Per-status правила:
- scalar + `available`: `score != nil`, `confidence >= 0.0`
- scalar + `not_applicable`: `score == nil`, `confidence == 0.0`
- scalar + `unavailable`: `score == nil`, `confidence == 0.0`
- categorical + `available`: полный closed catalog affinities, `confidence >= 0.0`
- categorical + `not_applicable`: `affinities == []`, `confidence == 0.0`
- categorical + `unavailable`: `affinities == []`, `confidence == 0.0`

Нормативное уточнение:
- `available` + `confidence == 0.0` допустимо только как крайний случай полностью недоверяемого, но формально валидного output-а;
- для `live` practical target остается из `PR-H02`: usable signals ожидаются в основном от `confidence >= 0.65`;
- low-confidence available output остается валидным для serialization и eval, even if fusion later ignores it.

## Snapshot-Level Availability Policy

`PR-H06` фиксирует, что snapshot может быть валидным даже при частичной деградации.

Допустимые формы:
- fully populated snapshot: все ожидаемые heads `available`, кроме policy-driven `not_applicable`;
- partial snapshot: часть heads `available`, часть `unavailable`, часть `not_applicable`;
- hard-failure snapshot: все heads `unavailable` или `not_applicable`, но envelope и provenance все равно сериализуются.

Уточнение:
- если hard-failure snapshot сохраняется для debug/eval telemetry, corresponding `NeuralEvidenceRuntimeMetadata` sidecar тоже обязан быть сохранен;
- если sidecar не сохранен, snapshot все еще валиден для fallback/runtime decisions, но reason-level analytics unavailable by contract.

Hard-failure snapshot нужен, чтобы:
- `PR-H07` мог логировать обрывы без потери `frameId` и mode context;
- `PR-H08/H09` могли явно выбрать fallback path;
- `PR-H14` мог считать failure-rate по snapshot statuses даже без sidecar;
- `PR-H14` мог считать breakdown по `failureReason` только при наличии sidecar metadata.

## Serialization Rules

### Canonical JSON requirements

JSON serialization обязана быть:
- lossless относительно domain contract;
- стабильной по key names и ordering массивов;
- пригодной для fixture tests и cross-version diff.

Нормативные правила:
- `Date` сериализуется в UTC ISO-8601 с millisecond precision;
- `Double` сериализуется обычным JSON number;
- enum values сериализуются как canonical snake_case strings;
- `headOutputs` и `affinities` сохраняют canonical array order;
- `supportingSignals` сохраняют canonical vocabulary order;
- canonical JSON не использует key omission для optional fields;
- если optional поле есть в contract shape, но значения нет, encoder обязан сериализовать его как explicit `null`;
- decoder может быть tolerant к omitted optional fields в legacy fixtures, но canonical `PR-H06` encoding обязан использовать только `null`.

### Snapshot JSON example

```json
{
  "schemaVersion": "h1",
  "frameId": "frame-000184",
  "mode": "pause",
  "capturedAt": "2026-04-22T10:15:31.482Z",
  "bundleVersion": "hybrid-evidence-bundle.2026-04-22",
  "headOutputs": [
    {
      "headId": "subject_prominence",
      "payload": {
        "headId": "subject_prominence",
        "status": "available",
        "score": 0.82,
        "confidence": 0.87,
        "mode": "pause",
        "supportingSignals": [
          "subject_scale",
          "subject_readability"
        ]
      }
    },
    {
      "headId": "background_clutter",
      "payload": {
        "headId": "background_clutter",
        "status": "available",
        "score": 0.21,
        "confidence": 0.81,
        "mode": "pause",
        "supportingSignals": [
          "attention_competition"
        ]
      }
    },
    {
      "headId": "lighting_quality",
      "payload": {
        "headId": "lighting_quality",
        "status": "available",
        "score": 0.74,
        "confidence": 0.71,
        "mode": "pause",
        "supportingSignals": [
          "subject_exposure_readability",
          "tonal_structure"
        ]
      }
    },
    {
      "headId": "face_saliency",
      "payload": {
        "headId": "face_saliency",
        "status": "available",
        "score": 0.78,
        "confidence": 0.76,
        "mode": "pause",
        "supportingSignals": [
          "face_attention_pull",
          "eye_region_visibility"
        ]
      }
    },
    {
      "headId": "balance_confidence",
      "payload": {
        "headId": "balance_confidence",
        "status": "available",
        "score": 0.68,
        "confidence": 0.59,
        "mode": "pause",
        "supportingSignals": [
          "frame_balance"
        ]
      }
    },
    {
      "headId": "depth_separation",
      "payload": {
        "headId": "depth_separation",
        "status": "available",
        "score": 0.73,
        "confidence": 0.66,
        "mode": "pause",
        "supportingSignals": [
          "subject_background_contrast"
        ]
      }
    },
    {
      "headId": "cinematic_expressiveness",
      "payload": {
        "headId": "cinematic_expressiveness",
        "status": "available",
        "score": 0.63,
        "confidence": 0.52,
        "mode": "pause",
        "supportingSignals": [
          "visual_harmony_residual"
        ]
      }
    },
    {
      "headId": "shot_type_confidence",
      "payload": {
        "headId": "shot_type_confidence",
        "status": "available",
        "affinities": [
          { "categoryId": "dialogue_closeup_affinity", "score": 0.72 },
          { "categoryId": "single_character_medium_affinity", "score": 0.61 },
          { "categoryId": "two_character_frame_affinity", "score": 0.12 },
          { "categoryId": "object_insert_affinity", "score": 0.09 },
          { "categoryId": "establishing_like_frame_affinity", "score": 0.08 },
          { "categoryId": "moody_backlit_subject_affinity", "score": 0.18 },
          { "categoryId": "unknown_affinity", "score": 0.14 }
        ],
        "confidence": 0.64,
        "mode": "pause",
        "supportingSignals": []
      }
    }
  ]
}
```

Optional sidecar metadata for the same snapshot:

```json
{
  "metadataSchemaVersion": "h1",
  "frameId": "frame-000184",
  "mode": "pause",
  "providerKind": "coreml_local",
  "inferenceTarget": "on_device",
  "modelFamily": "compact_neural_evidence_net",
  "modelVersion": "h05.v1",
  "preprocessingVersion": "prep.v2",
  "thresholdProfile": "default_pause_v1",
  "producedAt": "2026-04-22T10:15:31.615Z",
  "latencyMs": 133,
  "roiStrategy": "full_frame_plus_subject_crop",
  "failureReason": null
}
```

### `live` example with policy-driven `not_applicable`

```json
{
  "schemaVersion": "h1",
  "frameId": "frame-000031",
  "mode": "live",
  "capturedAt": "2026-04-22T10:16:10.041Z",
  "bundleVersion": "hybrid-evidence-bundle.2026-04-22",
  "headOutputs": [
    { "headId": "subject_prominence", "payload": { "headId": "subject_prominence", "status": "available", "score": 0.55, "confidence": 0.69, "mode": "live", "supportingSignals": ["subject_attention_pull"] } },
    { "headId": "background_clutter", "payload": { "headId": "background_clutter", "status": "available", "score": 0.48, "confidence": 0.62, "mode": "live", "supportingSignals": ["texture_noise"] } },
    { "headId": "lighting_quality", "payload": { "headId": "lighting_quality", "status": "available", "score": 0.44, "confidence": 0.67, "mode": "live", "supportingSignals": ["subject_exposure_readability"] } },
    { "headId": "face_saliency", "payload": { "headId": "face_saliency", "status": "not_applicable", "score": null, "confidence": 0.0, "mode": "live", "supportingSignals": [] } },
    { "headId": "balance_confidence", "payload": { "headId": "balance_confidence", "status": "not_applicable", "score": null, "confidence": 0.0, "mode": "live", "supportingSignals": [] } },
    { "headId": "depth_separation", "payload": { "headId": "depth_separation", "status": "not_applicable", "score": null, "confidence": 0.0, "mode": "live", "supportingSignals": [] } },
    { "headId": "cinematic_expressiveness", "payload": { "headId": "cinematic_expressiveness", "status": "not_applicable", "score": null, "confidence": 0.0, "mode": "live", "supportingSignals": [] } },
    { "headId": "shot_type_confidence", "payload": { "headId": "shot_type_confidence", "status": "not_applicable", "affinities": [], "confidence": 0.0, "mode": "live", "supportingSignals": [] } }
  ]
}
```

### Hard-failure example

```json
{
  "schemaVersion": "h1",
  "frameId": "frame-000245",
  "mode": "pause",
  "capturedAt": "2026-04-22T10:17:42.102Z",
  "bundleVersion": "hybrid-evidence-bundle.2026-04-22",
  "headOutputs": [
    { "headId": "subject_prominence", "payload": { "headId": "subject_prominence", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "background_clutter", "payload": { "headId": "background_clutter", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "lighting_quality", "payload": { "headId": "lighting_quality", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "face_saliency", "payload": { "headId": "face_saliency", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "balance_confidence", "payload": { "headId": "balance_confidence", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "depth_separation", "payload": { "headId": "depth_separation", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "cinematic_expressiveness", "payload": { "headId": "cinematic_expressiveness", "status": "unavailable", "score": null, "confidence": 0.0, "mode": "pause", "supportingSignals": [] } },
    { "headId": "shot_type_confidence", "payload": { "headId": "shot_type_confidence", "status": "unavailable", "affinities": [], "confidence": 0.0, "mode": "pause", "supportingSignals": [] } }
  ]
}
```

Optional sidecar metadata for the same hard-failure snapshot:

```json
{
  "metadataSchemaVersion": "h1",
  "frameId": "frame-000245",
  "mode": "pause",
  "providerKind": "coreml_local",
  "inferenceTarget": "on_device",
  "modelFamily": "compact_neural_evidence_net",
  "modelVersion": "h05.v1",
  "preprocessingVersion": "prep.v2",
  "thresholdProfile": "default_pause_v1",
  "producedAt": "2026-04-22T10:17:42.231Z",
  "latencyMs": 129,
  "roiStrategy": "full_frame_plus_subject_crop",
  "failureReason": "inference_failed"
}
```

## Provenance and Explainability Bridge

Любой fused use of `NeuralEvidenceSnapshot` обязан быть traceable в existing explainability contracts.

Нормативные правила:
- `NeuralEvidenceSnapshot` сам по себе не является user-facing trace;
- downstream, который реально использовал head, обязан materialize-ить canonical `EvidenceRef(source = neural_evidence, ...)`;
- canonical keys остаются из `PR-H02`:
  - scalar heads:
    - `neural.<headId>.status`
    - `neural.<headId>.score`
    - `neural.<headId>.confidence`
    - `neural.<headId>.supportingSignals`
  - categorical head `shot_type_confidence`:
    - `neural.shot_type_confidence.status`
    - `neural.shot_type_confidence.confidence`
    - `neural.shot_type_confidence.affinities.<categoryId>`
- `NeuralEvidenceRuntimeMetadata.*` provenance не попадает в user-facing trace по умолчанию, но доступен для debug/eval telemetry;
- downstream не может ссылаться на head, которого нет в snapshot или который имеет `status != available`, как на положительное justification.

## Versioning Rules

`schemaVersion` обязан меняться при любом breaking change:
- изменение списка heads;
- изменение canonical ordering;
- изменение enum catalog;
- изменение payload shape;
- изменение serialization semantics для `available/not_applicable/unavailable`.

`metadataSchemaVersion` в baseline `PR-H06` versioned синхронно с `schemaVersion`:
- breaking change в sidecar metadata требует того же version bump;
- пока не появится отдельная metadata-only spec, `metadataSchemaVersion == schemaVersion` является обязательным правилом.

`bundleVersion` не заменяет `schemaVersion`:
- `schemaVersion` описывает contract shape;
- `bundleVersion` описывает конкретный runtime bundle;
- разные `bundleVersion` могут легально существовать под одним `schemaVersion`.

## Invariants

- `frameId` обязателен и должен совпадать с deterministic `FrameFeatureSnapshot.frameId`.
- `mode` обязан совпадать с deterministic pipeline mode.
- `capturedAt` должен описывать время исходного кадра, а не время инференса.
- `headOutputs.count == 8`.
- каждый `EvidenceHeadId` присутствует ровно один раз.
- ни один неизвестный head не допускается.
- если sidecar metadata сохраняется, `NeuralEvidenceRuntimeMetadata.frameId == NeuralEvidenceSnapshot.frameId` и `mode` совпадает.
- если sidecar metadata сохраняется, `metadataSchemaVersion == schemaVersion`.
- если sidecar metadata сохраняется, `producedAt >= capturedAt`.
- `face_saliency == not_applicable` для кадров, где `SceneSemanticsReport.primarySubject.kind in {object, unknown}`, а не "низкий score".
- `face_saliency` не может стать `not_applicable` на основании raw detector outputs вне deterministic semantics contract.
- pause-only heads в `live` всегда `not_applicable`.
- `shot_type_confidence.supportingSignals == []` при любом status.
- для scalar head-а `supportingSignals.count <= 2`.
- `supportingSignals` не могут нарушать per-head allowed-tag matrix из `PR-H02`.
- `unknown_affinity` обязателен во всех `available` categorical payload-ах.
- `NeuralEvidenceRuntimeMetadata.failureReason == policy_skipped` допустим только если snapshot целиком оформлен как policy-degraded path, а не для одиночного pause-only head в `live`.
- контракт не содержит `AVA` score, dataset label tier, training loss, logits или prompt text.
- snapshot валиден для both `on_device` and `offloaded` providers without changing payload semantics.

## Contract Tests

Минимальный test matrix для `PR-H06`:

1. Dense ordering test
   Проверяет, что все 8 heads всегда присутствуют и идут в canonical order.

2. Mode policy test
   Проверяет, что pause-only heads в `live` сериализуются как `not_applicable`.

3. Person-centric applicability test
   Проверяет, что `face_saliency` становится `not_applicable` только при `SceneSemanticsReport.primarySubject.kind in {object, unknown}`.

4. Scalar payload invariant test
   Проверяет `available -> score != nil`, `status != available -> score == nil`.

5. Categorical payload invariant test
   Проверяет fixed order и полноту `shot_type_confidence.affinities`.

6. Supporting-signal mask test
   Проверяет, что serialized tags принадлежат только разрешенному vocabulary для конкретного head-а и не превышают cardinality `0...2`.

7. Hard-failure snapshot test
   Проверяет, что all-`unavailable` snapshot остается валидным envelope-объектом.

8. JSON round-trip test
   Проверяет, что encode/decode не ломает enum values, ordering и optional fields.

9. Versioning regression test
   Проверяет, что fixture старого `schemaVersion` не принимается silently как новый shape.

10. Sidecar alignment test
   Проверяет, что optional `NeuralEvidenceRuntimeMetadata` не меняет canonical snapshot shape и при наличии совпадает с ним по `metadataSchemaVersion/frameId/mode`.

11. Explainability key bridge test
   Проверяет, что scalar heads используют `neural.<headId>.*`, а `shot_type_confidence` использует только `status`, `confidence` и `affinities.<categoryId>` keys без fictitious `.score`.

12. Canonical JSON optional encoding test
   Проверяет, что encoder сериализует отсутствующие optional values только как explicit `null`, а не через key omission.

## Что это разблокирует дальше

После фиксации этого документа:
- `PR-H07` может строить Swift/Core ML wrapper с фиксированным envelope и predictable failure handling;
- `PR-H08` может подключать pause-only evidence без shape branching внутри pipeline;
- `PR-H09` может использовать только `available` heads и различать policy vs failure semantics;
- `PR-H14` может считать failure rate, availability profile и hybrid uplift на стабильных fixtures;
- future offloaded path может переиспользовать тот же contract без отдельного domain fork.

## Definition of Done

`PR-H06` считается закрытым в design mode, если:
- runtime contract описан как self-sufficient source-of-truth;
- `NeuralEvidenceSnapshot` пригоден для on-device и offloaded providers без смены semantics;
- status, confidence и serialization rules исключают guesswork downstream;
- examples покрывают normal, live-policy и failure cases;
- invariants и test matrix достаточны для последующей кодовой реализации без домысливания.
