# 29. On-Device Semantic Evidence Distillation Plan (PR-S07)

Статус: design spec + design verify (ready for implement)

Дата: 2026-05-05

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md)
- [18-hybrid-model-architecture-spec.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/18-hybrid-model-architecture-spec.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md)
- [23-hybrid-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/23-hybrid-eval-harness.md)
- [24-semantic-tip-taxonomy-and-action-catalog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md)
- [25-vlm-visual-semantic-evidence-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/25-vlm-visual-semantic-evidence-contract.md)
- [26-semantic-tip-fusion-and-planner.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/26-semantic-tip-fusion-and-planner.md)
- [28-vlm-labeled-semantic-tip-dataset.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/28-vlm-labeled-semantic-tip-dataset.md)

## Цель

Зафиксировать реалистичный путь от heavy `VLM teacher` к компактной локальной модели, которая предсказывает semantic evidence для screen tips без постоянной зависимости от offloading.

Ключевая формула `PR-S07`:

`pause frame + deterministic context + reviewed VLM teacher signals -> compact on-device semantic evidence model -> deterministic semantic tip planner`

Этот документ нужен, чтобы:
- заменить часть `pause` VLM calls компактным локальным evidence path;
- сохранить template-based planner и не переносить free-form текст на устройство;
- связать thesis narrative в одну непрерывную цепочку:
  - `VLM teacher`
  - `reviewed dataset`
  - `distilled mobile evidence model`
  - `semantic screen tips`;
- не ломать уже зафиксированные user-facing contracts `PR-S01`, `PR-S02`, `PR-S04`.

## Scope

`PR-S07` отвечает за:
- выбор distillation targets из `PR-S01` и `PR-S02`;
- проекцию reviewed dataset labels в training targets;
- minimal model assumptions для iPhone-class runtime;
- loss design и target weighting;
- Core ML conversion path;
- latency / memory / fallback expectations;
- eval plan и staged rollout.

`PR-S07` не отвечает за:
- изменение UI contract;
- новый free-form planner или device-side text generation;
- giant on-device VLM;
- замену deterministic `RecommendationPlan` или `SemanticTipPlanner`;
- реальный runtime code patch внутри app;
- расширение закрытых catalogs `PR-S01` и `PR-S02`.

Граница ответственности:
- `PR-S01` фиксирует, какие tip/action ids вообще допустимы;
- `PR-S02` фиксирует, какие structured semantic evidence fields может вернуть teacher;
- `PR-S06` фиксирует reviewed dataset loop;
- `PR-S07` фиксирует, какие из этих структурированных полей стоит дистиллировать в компактную локальную модель и как их оценивать;
- финальный decision layer по-прежнему остается за deterministic planner из `PR-S04`.

## Design Summary

Нормативные решения `PR-S07`:
- локальная модель предсказывает не готовый совет, а компактный набор semantic evidence heads;
- runtime baseline для `PR-S07` — `pause-first`; live не является обязательной частью initial rollout;
- модель не предсказывает display label text, object names или финальный `SemanticActionType`;
- entity-aware часть ограничивается:
  - `primaryEntityKind`
  - `secondaryEntityPresence`
  - `relationType`
  - `labelConfidenceClass`
  - `actionFrameChoice`;
- конкретный текст вида `сдвинь цветок правее` materialize-ится только если локальный grounding уже дал safe label, иначе planner деградирует к `сдвинь предмет правее`;
- базовая модель должна переиспользовать mobile-friendly assumptions из `PR-H05/H07`, а не вводить отдельный тяжёлый стек;
- `VLM` после `PR-S07` остается teacher / fallback / hard-case escalator, а не обязательный runtime dependency.

## Почему нужен отдельный `PR-S07`

На момент начала `PR-S07` уже существуют:
- закрытый catalog semantic tips и actions в `PR-S01`;
- machine-validated teacher response contract в `PR-S02`;
- deterministic semantic planner в `PR-S04`;
- reviewed dataset loop в `PR-S06`;
- mobile model/runtime discipline в `PR-H05/H07/H14`.

Но отсутствует один design-layer, который фиксирует:
- какие именно semantic outputs teacher-а стоит дистиллировать;
- какие поля не нужно переносить в локальную модель;
- как совместить object-aware tips с mobile-first runtime;
- как считать успех не только по teacher agreement, но и по конечной tip accuracy;
- как откатываться обратно на deterministic path и optional VLM without UI drift.

Без этого implementation легко расползется в две крайности:
- либо device-side model начнет предсказывать слишком широкие и хрупкие semantics;
- либо distillation сведется к vague copy imitation, что ломает explainability thesis.

## Thesis Narrative

Authoritative narrative для дипломной линии:

1. deterministic critique + planner дают explainable baseline;
2. `VLM` используется только как bounded teacher для richer semantic observations в `pause`;
3. reviewed dataset из `PR-S06` превращает teacher suggestions в reproducible supervision;
4. компактная on-device модель учится предсказывать только structured semantic evidence;
5. planner снова materialize-ит финальный совет template-based способом.

Нормативный вывод:
- knowledge transfer идет не в prose, а в закрытые semantic heads;
- explainability не теряется, потому что mobile model не становится final judge;
- thesis показывает не black-box replacement, а cost-aware distillation into a bounded decision system.

## Distillation Targets

### Target selection principle

`PR-S07` дистиллирует только те teacher outputs, которые:
- уже живут в закрытых catalogs `PR-S01/S02`;
- прямо помогают planner-у выбрать actor of change, relation и safe localization;
- не требуют device-side свободной генерации текста;
- можно проверить по reviewed dataset и eval harness.

Запрещено дистиллировать как shipping runtime target:
- free-form explanation text;
- конкретные object names как vocabulary head;
- final `SemanticTipType`;
- final `SemanticActionType`;
- итоговый product verdict.

### Shipping target bundle

Минимальный shipping target bundle называется условно `DistilledSemanticEvidenceHeads`.

```text
DistilledSemanticEvidenceHeads
- dimensionState[8]                // per VLM dimension
- dimensionScore[8]                // 0...1, masked if not applicable
- dimensionConfidence[8]           // 0...1 reliability estimate
- primaryEntityKind                // one of VLMEntityKind
- secondaryEntityPresence          // Bool
- relationType                     // none | competes_with | merges_with | blocks | pulls_attention_from
- labelConfidenceClass             // generic_only | specific_low_confidence | specific_high_confidence
- actionFrameChoice                // camera | subject | object | light | wait
- keepCurrentSetupAffinity         // Bool / score
```

### `dimensionState`

Каждое из восьми измерений из `PR-S02` предсказывается как closed 4-way state:

```text
DimensionStateClass
- supports_problem
- supports_strength
- neutral_context
- not_applicable
```

Canonical dimension order:
1. `subject_readability`
2. `background_separation`
3. `lighting_relation`
4. `clutter`
5. `depth`
6. `face_visibility`
7. `frame_intent`
8. `mood_preservation`

Почему это shipping target:
- это точнее повторяет структуру teacher evidence, чем попытка сразу предсказывать tip ids;
- planner может использовать эти states как bounded support / soften / localize signals;
- `frame_intent` и `mood_preservation` позволяют не переучивать модель только на corrective bias и помогают не overcoach good or intentionally moody frames.

### `dimensionScore`

Для каждого dimension модель дополнительно предсказывает scalar `0...1`.

Смысл:
- не global frame quality;
- не final action confidence;
- а сила наблюдаемого semantic factor внутри конкретного dimension.

Использование:
- локальный rerank внутри уже существующих deterministic candidates;
- оценка confidence threshold и teacher agreement;
- case-level calibration в `PR-H14`.

### `dimensionConfidence`

Модель обязана предсказывать отдельную оценку reliability, а не только score.

Причины:
- distillation targets шумные и частично teacher-derived;
- planner должен уметь fail-soft, а не делать вид, что любой logits peak надежен;
- confidence нужен для решений:
  - применять ли distilled evidence вообще;
  - просить ли fallback на teacher path;
  - деградировать ли к deterministic-only.

### Entity-aware targets

#### `primaryEntityKind`

Дистиллируемый closed catalog:

```text
PrimaryEntityKindClass
- person
- face
- object
- prop
- background_area
- light_source
- frame
- unknown
```

Это не заменяет local grounding и не создает новый entity catalog.

#### `secondaryEntityPresence`

Binary target:
- `true`, если reviewed case требует relation-aware localization второго объекта/зоны;
- `false`, если advice однообъектный или frame-level.

Этот head нужен, чтобы runtime не пытался invent relation logic там, где case локально одноякорный.

#### `relationType`

Closed catalog:

```text
RelationTypeClass
- none
- competes_with
- merges_with
- blocks
- pulls_attention_from
```

Нормативное правило:
- если `secondaryEntityPresence == false`, `relationType` обязан быть `none`;
- relation head не создает новые entity refs, а только помогает planner-у выбрать conflict family при уже существующих local anchors.

#### `labelConfidenceClass`

Модель не предсказывает названия объектов. Она предсказывает только, насколько безопасно planner-у materialize-ить уже имеющийся локальный label.

Closed catalog:

```text
LabelConfidenceClass
- generic_only
- specific_low_confidence
- specific_high_confidence
```

Семантика:
- `generic_only`: planner обязан использовать `предмет`, `объект справа`, `фон`, `герой`;
- `specific_low_confidence`: можно логировать/debug-ить specific candidate, но UI обязан остаться generic;
- `specific_high_confidence`: planner может использовать локально grounded конкретный label только если local grounding тоже проходит свой порог (`>= 0.75` по `PR-S01/S02`).

То есть device model never invents the word `цветок`; она лишь помогает понять, safe ли materialize-ить уже известный локальный `цветок`.

#### `actionFrameChoice`

Closed catalog:

```text
ActionFrameChoice
- camera
- subject
- object
- light
- wait
```

Этот head обязателен, потому что именно выбор `кого двигать` дает большую часть практической ценности semantic tips.

Нормативное правило:
- `actionFrameChoice` coarse-grained и не заменяет planner-level `SemanticActionType`;
- `camera` / `subject` / `object` / `light` / `wait` достаточно, чтобы downstream выбрать правильную family, не обучая модель на десятки почти-дублирующихся action ids.

### `keepCurrentSetupAffinity`

Отдельный lightweight head для `do-not-overcoach`.

Причины:
- good-frame path в `PR-S01/S04` критичен для UX;
- distillation не должна быть corrective-only;
- явный keep-head снижает риск, что модель всегда будет проталкивать какую-то правку.

### Auxiliary training-only targets

Разрешены только как training stabilizers, но не как runtime contract:

```text
AuxiliaryActionFamily
- reframing
- subject_staging
- object_staging
- lighting
- cleanup
- keep
```

Также допустимы auxiliary heads:
- `shot_intent_affinity reuse` из `PR-H05`;
- `good_frame_gate`;
- `review_disagreement_risk`.

Они помогают обучению и ablation, но не становятся новым shipping API.

## Label Projection and Training Supervision

### Source hierarchy

`PR-S07` использует трёхслойную иерархию supervision.

#### Layer A. Gold reviewed supervision

Главный источник истины:
- `PR-S06 reviewed labels`
- human-edited target/secondary entity choices
- accepted/rejected/edited review outcome

Эти labels определяют:
- `actionFrameChoice`
- `labelConfidenceClass`
- `keepCurrentSetupAffinity`
- final relation family
- target applicability mask.

#### Layer B. Teacher soft supervision

Используется только если response `PR-S02` валиден и не rejected reviewer-ом.

Teacher soft targets допустимы для:
- `dimensionState`
- `dimensionScore`
- `dimensionConfidence`
- `primaryEntityKind`
- `relationType`

Вес teacher soft target зависит от review outcome:
- `accepted`: `1.0`
- `edited`: `0.35`
- `rejected`: `0.0`

#### Layer C. Deterministic baseline anchors

Используются как mask and consistency prior:
- local issue ids
- local action family
- local safe grounding availability
- person-vs-object applicability anchors
- do-not-overcoach baseline on clearly good frames

Deterministic anchors не должны silently перетирать reviewed labels, но обязаны:
- запрещать impossible states;
- помогать fail-closed learning;
- уменьшать шум в relation/light heads.

### Projection rules from dataset record

Для каждого `SemanticTipDatasetRecord`:

1. `primaryEntityKind`
- берется из reviewed label, иначе из accepted teacher entity kind;
- `unknown`, если reviewer специально не подтвердил объектность и local grounding слабый.

2. `secondaryEntityPresence` и `relationType`
- берутся из reviewed relation bundle;
- если teacher relation accepted и reviewer не редактировал, relation score можно использовать как soft target;
- если secondary entity отсутствует или unsafe, `relationType = none`.

3. `labelConfidenceClass`
- `specific_high_confidence`, только если:
  - reviewed label сохраняет конкретное имя;
  - local or reviewed grounding confidence `>= 0.75`;
  - объектный label входит в allowed bounded vocabulary.
- `specific_low_confidence`, если reviewer оставил uncertain object candidate только для анализа;
- `generic_only` во всех остальных случаях.

4. `actionFrameChoice`
- проектируется из reviewed `SemanticActionFrame`;
- если reviewed record positive/keep case, target = `wait`.

5. `dimensionState`
- проектируется из reviewed observations если они есть;
- иначе из accepted teacher observations;
- иначе из deterministic + reviewed tip family only for dimensions with unambiguous mapping;
- если mapping неоднозначен, ставится `not_applicable`, а не guessed label.

6. `dimensionScore`
- reviewer-edited numeric score предпочтителен;
- если reviewer не правил numeric severity, можно наследовать teacher score;
- если reliable scalar нет, dimension участвует только в state loss и маскируется для score regression.

### Structured-only record policy

Для `structured_only_case` без redacted visual:
- record разрешен для `actionFrameChoice`, `keepCurrentSetupAffinity`, coarse `primaryEntityKind`, `labelConfidenceClass`;
- relation-heavy и score-heavy heads получают reduced weight или mask;
- такие записи полезны для policy learning, но не должны доминировать visual localization heads.

### Training sampling policy

Нормативная sampling discipline:
- `good / keep` кадры не менее `20%` каждого train epoch;
- object-centric и prop-conflict buckets не менее `25%` от semantic subset;
- lighting-heavy cases oversample-ятся только после появления достаточного reviewed volume;
- `runtime_hard_case` должен иметь отдельный validation slice и не смешиваться целиком в train.

## Loss Design

Рекомендуемый baseline objective:

```text
L_total =
  1.00 * L_dimension_state
  0.50 * L_dimension_score
  0.25 * L_dimension_confidence
  0.60 * L_action_frame
  0.40 * L_primary_entity_kind
  0.35 * L_relation_type
  0.25 * L_label_confidence_class
  0.20 * L_keep_affinity
  0.15 * L_consistency
  0.20 * L_teacher_kl
```

### Recommended loss family

- `L_dimension_state`: masked cross-entropy or focal cross-entropy per dimension;
- `L_dimension_score`: masked Huber loss on `0...1` target;
- `L_dimension_confidence`: BCE or calibration-oriented regression on agreement-derived confidence target;
- `L_action_frame`: cross-entropy with class weighting;
- `L_primary_entity_kind`: cross-entropy with downweight for `unknown`;
- `L_relation_type`: focal loss because `none` dominates;
- `L_label_confidence_class`: ordinal cross-entropy;
- `L_keep_affinity`: BCE;
- `L_teacher_kl`: KL divergence only where trusted teacher soft distribution exists;
- `L_consistency`: lightweight rule penalty.

### Consistency constraints

`L_consistency` должен штрафовать минимум такие невозможные комбинации:
- `keepCurrentSetupAffinity high` одновременно с dominant corrective `actionFrameChoice != wait`;
- `actionFrameChoice = light` без evidence in `lighting_relation`;
- `relationType != none` при `secondaryEntityPresence = false`;
- `specific_high_confidence` при отсутствии local grounding-compatible entity;
- `face_visibility = supports_problem` в object-centric cases without person anchor.

Нормативное правило:
- impossible combinations должны решаться loss-ом и label masks, а не постфактум скрываться красивым report-ом.

## Minimal Model Assumptions

### Architecture choice

Baseline `PR-S07` должен переиспользовать mobile discipline из `PR-H05`:
- trunk family: `MobileNetV3-Large width 0.75`
- shared dual-view visual encoder
- small semantic head neck above pooled features
- no language decoder
- no text tokens
- no detector logic inside the model

Условное имя baseline:

`CompactSemanticEvidenceNet`

### Input strategy

Baseline input contract:

```text
CompactSemanticEvidenceInputs
- full_frame_rgb: 256 x 256 x 3
- primary_entity_crop_rgb: 160 x 160 x 3
- mode_flag_pause: scalar Float32
- crop_present_flag: scalar Float32
```

Ключевое отличие от `PR-H05`:
- crop трактуется не как strictly person subject crop, а как `primary_entity_crop`;
- если кадр object-centric, crop строится вокруг object/prop primary subject из deterministic semantics;
- если crop unavailable, используется zero-image fallback и `crop_present_flag = 0`.

Wrapper-compatibility rule:
- transport slot и tensor shape второго image branch должны остаться совместимыми с `PR-H05/H07`;
- в implementation допустимо сохранить wire-level имя вроде `subject_crop_rgb`, если semantic meaning versioned и явно задокументирован как `primary entity crop`;
- ROI policy обязана получить собственный version tag, чтобы object-centric crop semantics не маскировались под старый person-only recipe.

Причина:
- screen tips из `PR-S01` должны одинаково поддерживать person-centric и object-centric shots.

### Why not a larger multimodal model

Запрещено в baseline:
- брать giant VLM on-device;
- переносить prompt tokens или text encoder;
- делать object-name classifier на сотни слов;
- делать multi-frame temporal architecture как обязательную часть `v1`.

Причина:
- это ломает mobile-first thesis и резко усложняет Core ML/runtime without adding contract-safe value.

### Initialization policy

Рекомендуемая training инициализация:
1. warm-start trunk from `PR-H05` visual evidence backbone или совместимого mobile checkpoint;
2. semantic heads initialize randomly;
3. сначала обучить coarse semantic heads на reviewed subset;
4. затем включить teacher soft distillation и hard-case fine-tuning.

Это предпочтительнее, чем тренировать `PR-S07` completely from scratch, потому что:
- визуальные low-level priors уже полезны;
- semantic dataset будет меньше, чем generic visual evidence corpus;
- Core ML parity и deployment риск ниже при reuse знакомого backbone.

## Runtime Integration Assumptions

### Runtime handoff contract

`PR-S07` не должен притворяться, что локальная distilled модель вернула полноценный `VLMVisualEvidenceResponse`.

Для runtime handoff фиксируется отдельный bounded envelope:

```text
DistilledSemanticEvidenceSnapshot
- schemaVersion: String
- frameId: String
- mode: AnalysisMode                     // pause for initial rollout
- modelBundleVersion: String
- dimensions: [DistilledDimensionEntry]  // fixed 8-dimension order
- primaryEntityKind: VLMEntityKind
- secondaryEntityPresence: Bool
- relationType: RelationTypeClass
- labelConfidenceClass: LabelConfidenceClass
- actionFrameChoice: ActionFrameChoice
- keepCurrentSetupAffinity: Double       // 0...1
- overallConfidence: Double              // 0...1
- status: available | unavailable

DistilledDimensionEntry
- dimension: VLMVisualEvidenceDimension
- state: DimensionStateClass
- score: Double?
- confidence: Double
```

Нормативные правила:
- `DistilledSemanticEvidenceSnapshot` не содержит free-form explanation;
- snapshot не содержит entity refs и не invent-ит их;
- snapshot не содержит final `SemanticActionType` или `SemanticTipType`;
- planner использует snapshot как отдельный local evidence source alongside deterministic anchors, а не как fake-remote response;
- если позже понадобится унифицированный fusion input, это должен быть explicit adapter layer, а не молчаливое смешение `PR-S02` и `PR-S07` envelopes.

### Pause-first rollout

Initial runtime role `PR-S07`:
- only `pause`;
- optional feature flag;
- planner uses distilled evidence only as bounded support/rerank/localization, never as sole source of final tip;
- `live` support откладывается до отдельной performance validation.

### Planner handoff

Distilled model может влиять только на:
- candidate rerank внутри уже существующего deterministic set;
- actor-of-change choice between `camera / subject / object / light / wait`;
- safe localization between generic vs specific grounded label;
- relation-aware suppression or reinforcement.

Distilled model не может:
- invent new `SemanticTipType` or `SemanticActionType`;
- invent entity refs;
- invent display label text;
- override deterministic `good` frame into corrective path без local support.

### Safe label materialization

Planner materialize-ит concrete object label только если одновременно:
- `labelConfidenceClass == specific_high_confidence`;
- существует local grounded entity ref;
- local grounded label проходит bounded vocabulary rule;
- deterministic safety policy не запрещает эту materialization.

Иначе UI получает generic copy.

## Core ML Conversion Path

### Canonical export path

1. train baseline in PyTorch with fixed preprocessing recipe;
2. freeze semantic head ordering and target catalogs;
3. export to Core ML `mlprogram` through `coremltools`;
4. convert weights to `float16`;
5. validate numeric parity on fixture frames;
6. package with stable:
   - `modelFamily`
   - `modelVersion`
   - `preprocessingVersion`
   - `semanticTargetVersion`
   - `bundleVersion`.

### Allowed ops discipline

Conversion baseline must stay within operator families already safe for `PR-H05`:
- conv / depthwise conv
- pooling
- linear layers
- simple activations
- concat / reshape / elementwise ops

Запрещены:
- custom ops without proven Core ML path;
- dynamic text/token components;
- post-export graph surgery that changes semantics without version bump.

### Wrapper compatibility

`PR-S07` должен по возможности reuse-ить patterns из `PR-H07`:
- feature-gated provider abstraction;
- mode-aware outcome reporting;
- sidecar runtime metadata;
- policy distinction between `disabled`, `failed` and `executed`.

Но при initial rollout allowed narrower contract:
- `pause` only;
- no requirement to ship live cadence policy yet.

## Latency, Size, and Memory Targets

Primary target device class:
- `A15+` iPhone-class devices.

`PR-S07` не должен быть тяжелее настолько, чтобы ломать mobile envelope из `PR-H05/H07`.

### Preferred targets

- compressed Core ML package: `<= 18 MB`
- `pause` model inference p50: `<= 35 ms`
- `pause` model inference p95: `<= 50 ms`
- end-to-end `pause` semantic inference wrapper p95: `<= 220 ms`
- peak working memory p95: `<= 100 MB`

### Hard acceptance ceilings

- compressed Core ML package: `<= 20 MB`
- `pause` model inference p95: `<= 60 ms`
- end-to-end `pause` wrapper p95: `<= 300 ms`
- peak working memory p95: `<= 140 MB`

Если модель не укладывается в hard ceilings:
- first fallback: prune auxiliary heads;
- second fallback: reduce neck width / switch to width `0.50`;
- third fallback: keep dataset/eval work and defer runtime shipping.

Нормативный приоритет:
- better to keep a smaller reliable semantic model than to ship a wider model that breaks pause UX.

## Eval Plan

`PR-S07` обязан оцениваться в трех плоскостях, а не только по одной teacher metric.

### 1. Teacher agreement metrics

На validated reviewed subset считаются:
- `dimension_state_macro_f1`
- `dimension_score_mae`
- `dimension_confidence_ece`
- `primary_entity_kind_accuracy`
- `relation_type_macro_f1`
- `label_confidence_class_qwk` или accuracy
- `action_frame_top1_accuracy`
- `keep_current_setup_precision_recall`

Interpretation:
- teacher agreement нужен, чтобы понять, переносится ли semantic evidence structure;
- но он не является единственным release signal, because teacher is not gold.

### 2. Human-reviewed tip accuracy

Главная product-relevant оценка:

`distilled outputs -> deterministic semantic planner -> final tip candidate`

сравнивается с reviewed labels из `PR-S06`.

Минимальные report metrics:
- `tip_family_accuracy`
- `action_frame_accuracy`
- `target_role_accuracy`
- `relation_localization_accuracy`
- `safe_label_materialization_accuracy`
- `good_frame_no_overcoach_rate`
- `object_centric_tip_accuracy`
- `lighting_tip_precision`

Нормативное правило:
- release decision нельзя принимать только по agreement с teacher response, если конечный planner output не улучшается или начинает overcoach good frames.

### 3. Mobile/runtime metrics

Через `PR-H14` и runtime sidecars считаются:
- `pause_latency_p50_ms`
- `pause_latency_p95_ms`
- `peak_memory_p95_mb`
- `model_load_time_ms`
- `distilled_inference_failure_rate`
- `fallback_to_deterministic_rate`
- `fallback_to_vlm_rate`

### Required compare matrix

`PR-S07` не должен конфликтовать с canonical variant matrix из `PR-H14`.

Поэтому compare matrix фиксируется как:

1. `deterministic_only`
2. `hybrid_pause_local`                                // canonical `PR-H14` baseline
3. `semantic_pause_vlm_teacher`                        // `PR-S07` extension variant, parent = `deterministic_only`
4. `semantic_pause_distilled_local`                    // `PR-S07` extension variant, parent = `hybrid_pause_local`
5. `semantic_pause_distilled_local_with_vlm_fallback`  // `PR-S07` extension variant, parent = `semantic_pause_distilled_local`

Смысл:
- `hybrid_pause_local` остается общей hybrid baseline из `PR-H14`;
- `semantic_pause_vlm_teacher` показывает upper bound teacher path именно для semantic evidence;
- `semantic_pause_distilled_local` показывает реальную локальную замену части pause VLM calls;
- `semantic_pause_distilled_local_with_vlm_fallback` показывает practical deployment path with graceful escalation.

Нормативные правила:
- `PR-S07` extension variants должны объявлять `parentVariantId` и не переопределять canonical ids из `PR-H14`;
- если harness на текущем шаге поддерживает только canonical ids, `semantic_*` variants разрешено сначала materialize-ить как experiment profile aliases поверх `PR-H14` runner-а;
- design считается несовместимым, если реализация для `PR-S07` silently переименует или fork-нет canonical `PR-H14` variant ids.

### Suggested acceptance gates

Initial ship-readiness gates:
- `good_frame_no_overcoach_rate` не хуже deterministic baseline;
- `action_frame_accuracy` не ниже `0.80` на reviewed validation set;
- `object_centric_tip_accuracy` не ниже `0.70` на object-heavy reviewed slice;
- `lighting_tip_precision` не ниже deterministic + VLM-fallback hybrid baseline minus acceptable small delta;
- mobile metrics не выходят за hard ceilings;
- any regression on safe naming policy blocks rollout.

## Rollback and Fallback Policy

### Runtime fallback order

Authoritative fallback chain:

1. use distilled local semantic evidence if:
   - model available;
   - confidence passes threshold;
   - planner has deterministic candidate set to refine.
2. else use deterministic-only semantic planner.
3. optional explicit/deep-analysis path may call `VLM`, if policy allows.

Это означает:
- отсутствие distilled model never blocks pause critique;
- optional VLM остается усилителем, а не обязательной подпоркой;
- UI contract не меняется ни в одном fallback branch.

### Rollout stages

#### Stage 0. Offline only

- train/eval artifacts only;
- no app wiring;
- goal: prove label projection and offline utility.

#### Stage 1. Debug-gated pause inference

- local model runs in pause;
- output logged and compared to planner;
- no user-visible influence.

#### Stage 2. Bounded planner assist

- model may rerank/localize only high-confidence pause candidates;
- deterministic candidate set remains mandatory.

#### Stage 3. VLM budget reduction

- explicit rule-based fallback to `VLM` only on:
  - low distilled confidence;
  - hard ambiguous relation/object cases;
  - unavailable local model;
  - explicit user request for deeper analysis.

#### Stage 4. Optional future live exploration

- only after `PR-H14` proves mobile viability;
- out of scope for initial `PR-S07`.

### Hard rollback triggers

Immediate rollback to deterministic-only if any of the following is observed:
- good-frame overcoaching rises above accepted threshold;
- safe label policy violation appears in shipped planner path;
- distilled model causes planner to choose unsupported action families;
- pause latency exceeds hard ceilings on target devices;
- object-centric cases regress below deterministic baseline.

## Staged Implementation Backlog

`PR-S07` design assumes the following execution slices.

### Slice 1. Label projection and fixtures

Сделать:
- projection script from `PR-S06 reviewed_labels.jsonl` to `DistilledSemanticEvidenceHeads`;
- masking rules for structured-only vs redacted-visual records;
- starter offline fixtures for parity tests.

Артефакт:
- reproducible training table;
- unit tests for projection invariants.

### Slice 2. PyTorch distillation baseline

Сделать:
- baseline `CompactSemanticEvidenceNet`;
- hard + soft target multitask training;
- ablations:
  - no relation head
  - no action-frame head
  - no teacher KL
  - width `0.50` vs `0.75`.

Артефакт:
- offline checkpoints;
- validation report.

### Slice 3. Core ML export and parity

Сделать:
- stable export script;
- float16 conversion;
- parity suite on frozen validation frames.

Артефакт:
- `.mlpackage`
- conversion note
- parity report.

### Slice 4. Pause-only runtime prototype

Сделать:
- feature-gated local provider;
- sidecar metadata;
- planner integration in observe-only or bounded-assist mode.

Артефакт:
- app-level debug prototype without UI contract change.

### Slice 5. Eval and rollout gates

Сделать:
- add `semantic_pause_distilled_local` and `semantic_pause_distilled_local_with_vlm_fallback` experiment variants to `PR-H14`, preserving canonical parent ids;
- publish compare report;
- decide whether distilled path is:
  - `ship pause-only`
  - `keep debug-only`
  - `defer`.

## Definition of Done

`PR-S07 design` считается завершенным, если:
- понятно, какие teacher fields реально дистиллируются, а какие намеренно остаются вне локальной модели;
- есть closed target bundle без free-form text generation;
- entity-aware labels сведены к safe `kind / relation / label confidence / action frame` rather than object-name generation;
- есть реалистичный mobile backbone и Core ML path;
- eval считает и teacher agreement, и reviewed tip accuracy, и mobile metrics;
- fallback/rollback ясно сохраняют deterministic planner как final decision layer;
- план не требует менять пользовательский UI contract.

## Design Verify Summary

Проверка `design verify` для `PR-S07` фиксирует:
- устранен конфликт с `PR-H14` по variant naming: `PR-S07` теперь использует extension variants с `parentVariantId`, а не переопределяет canonical hybrid ids;
- устранен runtime ambiguity: distilled local path теперь имеет отдельный `DistilledSemanticEvidenceSnapshot`, а не маскируется под `VLMVisualEvidenceResponse`;
- устранен contract drift risk для crop branch: object-centric crop разрешен только при сохранении wrapper-compatible tensor slot и versioned ROI recipe;
- устранен documentation gap: `PR-S07` добавлен в roadmap semantic phase и рекомендованный порядок.

Неблокирующие допущения, оставленные осознанно для implement:
- exact Swift type names и file layout для runtime envelope;
- точные threshold values для `overallConfidence` rollout gate;
- окончательная форма experiment-profile wiring внутри `PR-H14`.

Итог `design verify`:
- blocking contradictions с `PR-S01`, `PR-S02`, `PR-S04`, `PR-S06`, `PR-H05`, `PR-H07`, `PR-H14` не обнаружены;
- документ готов как source-of-truth для следующего implementation/design-to-code шага.
