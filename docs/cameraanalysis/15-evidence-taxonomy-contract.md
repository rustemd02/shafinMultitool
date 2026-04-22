# 15. Evidence Taxonomy Contract (PR-H02)

Статус: design spec (source-of-truth)

Дата: 2026-04-21

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)

## Цель

Зафиксировать интерпретируемую evidence taxonomy для hybrid stage так, чтобы:
- `PR-H03` мог строить dataset schema и rubric без домысливания;
- `PR-H06` мог оформить runtime/domain contract для neural evidence;
- `PR-H09` мог строить bounded fusion layer без скатывания в black-box judge.

Этот документ не определяет архитектуру модели и не вводит новые user-facing verdict/action типы. Он определяет только:
- какие evidence heads разрешены;
- что означает score каждого head-а;
- как трактовать confidence и applicability;
- как heads связаны с существующей issue/action taxonomy.

## Scope и ограничения

В scope:
- scalar и categorical evidence heads для hybrid layer;
- scoring axes и polarity;
- `live`/`pause` split;
- mapping к `IssueTypeV1`, `StrengthTypeV1` и `ActionTypeV1`;
- confidence semantics и invariants.

Вне scope:
- конкретная neural architecture;
- loss functions и training pipeline;
- dataset schema;
- runtime fusion formula;
- offloading policy.

Нормативные ограничения:
- evidence head обязан быть интерпретируемым и воспроизводимым;
- evidence не может быть свободным текстом;
- neural outputs не вводят новые issue/action taxonomy мимо [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md);
- deterministic critique core остается source-of-truth для финального `CritiqueReport` и `RecommendationPlan`.

## Базовые термины

### Evidence head

`Evidence head` — это ограниченный предиктор одной заранее определенной визуальной оси, а не генератор объяснений.

Допустимые типы:
- scalar support axis: высокий score означает, что полезное качество выражено;
- scalar risk axis: высокий score означает, что риск/помеха выражены;
- categorical affinity family: набор score по заранее фиксированному каталогу классов.

### Generic output semantics

На уровне taxonomy используются две canonical output forms: одна для scalar heads, одна для categorical affinity family.

```text
ScalarEvidenceHeadOutput
- headId: EvidenceHeadId
- status: EvidenceHeadStatus
- score: Double?                      // 0...1, nil если status != available
- confidence: Double                  // 0...1
- mode: AnalysisMode                  // live | pause
- supportingSignals: [SupportingSignalTag]

CategoricalEvidenceHeadOutput
- headId: EvidenceHeadId              // в PR-H02 только shot_type_confidence
- status: EvidenceHeadStatus
- affinities: [EvidenceCategoryScore] // полный closed catalog в фиксированном порядке
- confidence: Double                  // 0...1, family-level reliability
- mode: AnalysisMode
- supportingSignals: [SupportingSignalTag]

EvidenceCategoryScore
- categoryId: EvidenceCategoryId
- score: Double                       // 0...1
```

Frame-level envelope для `PR-H06`/`PR-H09` тоже фиксируется уже здесь, чтобы runtime и dataset не расходились по shape:

```text
NeuralEvidenceSnapshot
- schemaVersion: String                  // required, example: "h1"
- frameId: String                        // required, must match deterministic frameId
- mode: AnalysisMode                     // required
- capturedAt: Date                       // required, UTC
- bundleVersion: String                  // required, model/runtime bundle identifier
- headOutputs: [NeuralEvidenceHeadEntry] // required, dense canonical list in fixed order

NeuralEvidenceHeadEntry
- headId: EvidenceHeadId
- payload: ScalarEvidenceHeadOutput | CategoricalEvidenceHeadOutput
```

`EvidenceHeadStatus`:
- `available`
- `not_applicable`
- `unavailable`

`SupportingSignalTag` в `PR-H02` является закрытым vocabulary, а не произвольной строкой.
`EvidenceCategoryId` в `PR-H02` является закрытым vocabulary и для `shot_type_confidence` совпадает с catalog affinity IDs, перечисленными ниже.

### Closed ID catalogs

`EvidenceHeadId` catalog:
- `subject_prominence`
- `background_clutter`
- `lighting_quality`
- `face_saliency`
- `balance_confidence`
- `depth_separation`
- `cinematic_expressiveness`
- `shot_type_confidence`

`EvidenceCategoryId` catalog for `shot_type_confidence`:
- `dialogue_closeup_affinity`
- `single_character_medium_affinity`
- `two_character_frame_affinity`
- `object_insert_affinity`
- `establishing_like_frame_affinity`
- `moody_backlit_subject_affinity`
- `unknown_affinity`

Смысл:
- `score` описывает силу конкретной visual axis, а не "насколько кадр хороший";
- `affinities` описывают независимые affinity scores по закрытому catalog, а не probability distribution;
- `confidence` описывает надежность этого score или family в текущем кадре и для текущего режима;
- `supportingSignals` нужны для explainability/fusion/debug, но остаются каталожными tag-ами.

### Frame-level serialization rules

- `NeuralEvidenceSnapshot` всегда dense, а не sparse: `headOutputs` обязан содержать все heads из текущего taxonomy ровно по одному разу.
- `headOutputs` сериализуются в canonical order:
  - `subject_prominence`
  - `background_clutter`
  - `lighting_quality`
  - `face_saliency`
  - `balance_confidence`
  - `depth_separation`
  - `cinematic_expressiveness`
  - `shot_type_confidence`
- keying выполняется по `headId`; порядок стабилен и не зависит от `status`.
- Для heads, которые не используются в текущем режиме, runtime обязан включать entry со статусом `not_applicable`, а не пропускать его.
- Для каждого `NeuralEvidenceHeadEntry` обязательно `payload.mode == NeuralEvidenceSnapshot.mode`; смешанные `live/pause` payload-ы внутри одного snapshot запрещены.
- `schemaVersion` меняется при любом breaking change формы snapshot-а, payload-ов, enum catalogs или canonical ordering.
- `frameId` и `mode` обязаны быть согласованы с deterministic snapshot/semantics/critique contracts.

### Canonical shape invariants

- Для scalar head-а при `status == available` `score` обязателен.
- Для scalar head-а при `status != available` `score == nil` и `confidence == 0.0`.
- Для categorical head-а при `status == available` `affinities` обязаны содержать весь closed catalog категорий ровно по одному разу и в фиксированном canonical order.
- Для categorical head-а при `status != available` `affinities == []` и `confidence == 0.0`.
- Для `shot_type_confidence` affinity scores трактуются как независимые compatibility/affinity scores; они не обязаны суммироваться в `1.0`.
- `unknown_affinity` обязателен во всех `available` output-ах `shot_type_confidence`.

### Closed `supportingSignals` vocabulary

В `PR-H02` разрешены только следующие `SupportingSignalTag`:
- `subject_scale`
- `subject_attention_pull`
- `subject_readability`
- `object_density`
- `texture_noise`
- `attention_competition`
- `subject_exposure_readability`
- `facial_light_support`
- `tonal_structure`
- `face_attention_pull`
- `eye_region_visibility`
- `facial_anchor_strength`
- `frame_balance`
- `subject_placement_stability`
- `negative_space_fit`
- `foreground_background_split`
- `subject_background_contrast`
- `layering_clarity`
- `stylistic_intent`
- `production_value_residual`
- `visual_harmony_residual`

Нормативные правила:
- head может использовать только подмножество tags, перечисленных для него в этом документе;
- новые tags не могут добавляться ad hoc в dataset/runtime/eval без обновления этого source-of-truth;
- отсутствие tag-а не считается missing data, если сам head `available`.
- внутри одного head-а теги не могут повторяться;
- если список не пустой, теги сериализуются в canonical order according to the global vocabulary order above;
- пустой список допустим только если это явно разрешено для конкретного head-а в per-head rules ниже.

### Per-head `supportingSignals` rules

| Head ID | Required tags | Optional tags | Forbidden tags | Empty list allowed |
|---|---|---|---|---|
| `subject_prominence` | none | `subject_scale`, `subject_attention_pull`, `subject_readability` | all others | yes |
| `background_clutter` | none | `object_density`, `texture_noise`, `attention_competition` | all others | yes |
| `lighting_quality` | none | `subject_exposure_readability`, `facial_light_support`, `tonal_structure` | all others | yes |
| `face_saliency` | none | `face_attention_pull`, `eye_region_visibility`, `facial_anchor_strength`, `facial_light_support` | all others | yes |
| `balance_confidence` | none | `frame_balance`, `subject_placement_stability`, `negative_space_fit` | all others | yes |
| `depth_separation` | none | `foreground_background_split`, `subject_background_contrast`, `layering_clarity` | all others | yes |
| `cinematic_expressiveness` | none | `stylistic_intent`, `production_value_residual`, `visual_harmony_residual` | all others | yes |
| `shot_type_confidence` | none | none | all tags | yes, must always be `[]` |

Нормативные правила:
- Для всех heads, кроме `shot_type_confidence`, `supportingSignals` может быть пустым или содержать любое подмножество разрешенных optional tags.
- Для `shot_type_confidence` `supportingSignals` всегда должен быть пустым.
- Required tags в `PR-H02` отсутствуют намеренно: taxonomy не заставляет модель всегда объяснять score одними и теми же tags, но ограничивает допустимый словарь и сериализацию.
- Dataset/runtime/eval не могут переставлять теги в произвольном порядке: используется canonical order глобального vocabulary.

### `supportingSignals` emission criteria

Общие правила эмиссии:
- `supportingSignals` не являются свободным summary; это короткие sparse markers главных факторов, которые materially contributed to current head output.
- Для scalar head-а разрешено эмитить `0...2` tags; для categorical head-а `shot_type_confidence` всегда `0`.
- Tag эмитится только если соответствующий фактор является одним из главных драйверов текущего score/confidence для этого head-а.
- Если ни один разрешенный фактор не выделяется как main driver, пустой список допустим.
- При наличии нескольких tag-ов runtime/dataset сначала выбирает наиболее релевантные факторы, а затем сериализует их в canonical vocabulary order.

Per-tag meaning for emission:
- `subject_scale`: эмитить, когда вклад в `subject_prominence` определяется главным образом относительным размером субъекта в кадре.
- `subject_attention_pull`: эмитить, когда вклад в `subject_prominence` определяется тем, что субъект визуально притягивает внимание сильнее фона.
- `subject_readability`: эмитить, когда вклад в `subject_prominence` определяется читаемостью формы/силуэта/распознаваемости субъекта.
- `object_density`: эмитить, когда `background_clutter` в основном объясняется числом конкурирующих объектов.
- `texture_noise`: эмитить, когда `background_clutter` в основном объясняется мелкой визуальной шумностью фона.
- `attention_competition`: эмитить, когда `background_clutter` в основном объясняется наличием выраженных competing attention anchors.
- `subject_exposure_readability`: эмитить, когда `lighting_quality` в основном объясняется общей читаемостью субъекта по экспозиции.
- `facial_light_support`: эмитить, когда `lighting_quality` или `face_saliency` сильно завязаны на освещенность лица/головы.
- `tonal_structure`: эмитить, когда `lighting_quality` в основном объясняется тональным разделением и light-shape, а не просто яркостью.
- `face_attention_pull`: эмитить, когда `face_saliency` определяется тем, что лицо само становится главным visual anchor.
- `eye_region_visibility`: эмитить, когда `face_saliency` определяется видимостью глаз/верхней части лица.
- `facial_anchor_strength`: эмитить, когда `face_saliency` определяется общей силой head-area как compositional anchor.
- `frame_balance`: эмитить, когда `balance_confidence` определяется общим ощущением compositional balance.
- `subject_placement_stability`: эмитить, когда `balance_confidence` определяется устойчивостью положения субъекта внутри кадра.
- `negative_space_fit`: эмитить, когда `balance_confidence` определяется тем, что свободное пространство соответствует shot intent.
- `foreground_background_split`: эмитить, когда `depth_separation` определяется общим разделением переднего и заднего плана.
- `subject_background_contrast`: эмитить, когда `depth_separation` определяется контрастом субъекта к фону.
- `layering_clarity`: эмитить, когда `depth_separation` определяется ясностью планов и layering cues.
- `stylistic_intent`: эмитить, когда `cinematic_expressiveness` определяется ощущением намеренной стилистической постановки.
- `production_value_residual`: эмитить, когда `cinematic_expressiveness` определяется residual cues высокого production value.
- `visual_harmony_residual`: эмитить, когда `cinematic_expressiveness` определяется общей гармоничностью кадра beyond technical adequacy.

## Taxonomy Overview

### Head catalog

| Head ID | Axis type | Polarity | Что измеряет | Режимы |
|---|---|---|---|---|
| `subject_prominence` | scalar | support | Насколько главный субъект визуально доминирует по масштабу, акценту и считываемости | `live`, `pause` |
| `background_clutter` | scalar | risk | Насколько фон конкурирует за внимание и создает шум | `live`, `pause` |
| `lighting_quality` | scalar | support | Насколько свет помогает читаемости субъекта и тональному разделению | `live`, `pause` |
| `face_saliency` | scalar | support | Насколько лицо/голова реально тянут визуальный фокус | `live`, `pause` |
| `balance_confidence` | scalar | support | Насколько композиция выглядит устойчивой для предполагаемого shot intent | `pause` |
| `depth_separation` | scalar | support | Насколько субъект отделяется от заднего плана по глубине и тону | `pause` |
| `cinematic_expressiveness` | scalar | support | Насколько кадр демонстрирует осмысленную stylistic coherence beyond basic technical adequacy | `pause` |
| `shot_type_confidence` | categorical affinity family | neutral | Насколько кадр согласуется с каждым `SceneTypeV1` из deterministic catalog | `pause` |

### Почему catalog именно такой

- `subject_prominence`, `background_clutter`, `lighting_quality` и `face_saliency` покрывают main ambiguous zones, где deterministic signals часто достаточно информативны, но не всегда устойчиво откалиброваны.
- `balance_confidence` и `depth_separation` полезны именно как pause-stage уточнение для спорных cinematic cases.
- `cinematic_expressiveness` разрешен только как bounded residual head и не может напрямую создавать issue/action.
- `shot_type_confidence` помогает fusion и calibration, но не заменяет `SceneTypeClassifier`.

## Scoring Axes

### 1. `subject_prominence`

Тип:
- scalar support axis

Смысл высокого score:
- субъект визуально достаточно крупный, считываемый и воспринимается как anchor кадра.

Что score не означает:
- не гарантирует автоматически хороший кадр;
- не заменяет deterministic `subjectAreaRatio` или `separationScore`.

Primary support tags:
- `subject_scale`
- `subject_attention_pull`
- `subject_readability`

### 2. `background_clutter`

Тип:
- scalar risk axis

Смысл высокого score:
- фон и вторичные элементы создают конкуренцию, дробят внимание или визуально перегружают сцену.

Primary support tags:
- `object_density`
- `texture_noise`
- `attention_competition`

### 3. `lighting_quality`

Тип:
- scalar support axis

Смысл высокого score:
- свет помогает чтению главного объекта, формы и тонального разделения.

Primary support tags:
- `subject_exposure_readability`
- `facial_light_support`
- `tonal_structure`

### 4. `face_saliency`

Тип:
- scalar support axis

Applicability:
- только когда scene plausibly person-centric: `SubjectKind in {face, person, group}`.
- вне person-centric scenes head не исполняется и сериализуется как `not_applicable` по mode/status policy.

Смысл высокого score:
- лицо или head-area выступает как сильный attention anchor.

Primary support tags:
- `face_attention_pull`
- `eye_region_visibility`
- `facial_anchor_strength`

### 5. `balance_confidence`

Тип:
- scalar support axis

Смысл высокого score:
- композиция выглядит устойчивой для ожидаемого shot intent, без ощущения случайной разбалансировки.

Primary support tags:
- `frame_balance`
- `subject_placement_stability`
- `negative_space_fit`

### 6. `depth_separation`

Тип:
- scalar support axis

Смысл высокого score:
- субъект хорошо отделен от фона по depth/tonal layering и легче читается.

Primary support tags:
- `foreground_background_split`
- `subject_background_contrast`
- `layering_clarity`

### 7. `cinematic_expressiveness`

Тип:
- scalar support axis

Смысл высокого score:
- кадр выглядит намеренно собранным и stylistically coherent сверх базовой технической нормы.

Ограничение:
- этот head не может в одиночку создавать issue или action;
- его допустимая роль: reranking, tie-break и strength-side enrichment в `pause`.

Primary support tags:
- `stylistic_intent`
- `production_value_residual`
- `visual_harmony_residual`

### 8. `shot_type_confidence`

Тип:
- categorical affinity family

Выходные оси:
- `dialogue_closeup_affinity`
- `single_character_medium_affinity`
- `two_character_frame_affinity`
- `object_insert_affinity`
- `establishing_like_frame_affinity`
- `moody_backlit_subject_affinity`
- `unknown_affinity`

Смысл:
- это не финальный scene label, а structured prior для fusion/calibration рядом с deterministic `SceneTypeClassifier`.

Ограничение:
- максимальный affinity не должен сам по себе переписывать `sceneType`;
- `unknown_affinity` обязателен, чтобы модель могла честно сигнализировать о domain mismatch или ambiguity.
- canonical output shape для этого head-а всегда `CategoricalEvidenceHeadOutput`, а не scalar record.
- `supportingSignals` для этого head-а всегда `[]`, потому что scene-affinity information уже полностью выражена через closed `affinities` catalog и не требует отдельного tag-layer.
- canonical order категорий фиксирован:
  - `dialogue_closeup_affinity`
  - `single_character_medium_affinity`
  - `two_character_frame_affinity`
  - `object_insert_affinity`
  - `establishing_like_frame_affinity`
  - `moody_backlit_subject_affinity`
  - `unknown_affinity`

Tie / ambiguity policy:
- несколько высоких affinity одновременно допустимы; это трактуется как ambiguity signal, а не как нарушение контракта;
- если top-2 non-unknown affinities отличаются менее чем на `0.10`, output считается `tie/ambiguous` для dataset/fusion purposes;
- если `unknown_affinity` является максимальным affinity или `unknown_affinity >= 0.60`, output считается `unknown-dominant`;
- `unknown-dominant` output не запрещает наличие других умеренно высоких affinities, но downstream должен трактовать такой head как weak scene prior;
- `shot_type_confidence` не выбирает winner-label самостоятельно; downstream использует affinities как calibration signal рядом с deterministic `SceneTypeClassifier`, а не как замену ему.

## `live` vs `pause` split

### Heads, разрешенные в `live`

`live` допускает только heads, которые:
- дешево считаются;
- достаточно стабильны на соседних кадрах;
- не требуют rich contextual interpretation;
- полезны для короткой corrective подсказки.

Разрешенный набор:
- `subject_prominence`
- `background_clutter`
- `lighting_quality`
- `face_saliency` (только при person-centric applicability)

### Heads, разрешенные только в `pause`

`pause` допускает richer heads, которые полезны для expanded critique и slower fusion:
- `balance_confidence`
- `depth_separation`
- `cinematic_expressiveness`
- `shot_type_confidence`

### Policy split rationale

- `live` должен усиливать current coaching, а не добавлять мерцающие taste-like verdict-ы.
- `pause` может позволить себе более сложную интерпретацию и richer confidence calibration.
- если head сначала появляется только в `pause`, это не считается пробелом taxonomy; это осознанное mobile-first ограничение.

### Per-head mode/status matrix

Нормативные правила для `status` по режимам:
- если head разрешен в текущем режиме и runtime реально исполнил его, `status == available`;
- если head разрешен в текущем режиме, но runtime не смог получить валидный output из-за деградации, ошибки или отсутствия результата, `status == unavailable`;
- если head не разрешен в текущем режиме по contract policy, `status == not_applicable`;
- `pause`-only heads в `live` всегда сериализуются как `not_applicable`, а не `unavailable`;
- `unavailable` нельзя использовать как замену policy decision "этот head не должен запускаться в этом режиме".

| Head ID | `live` status policy | `pause` status policy |
|---|---|---|
| `subject_prominence` | `available` или `unavailable` | `available` или `unavailable` |
| `background_clutter` | `available` или `unavailable` | `available` или `unavailable` |
| `lighting_quality` | `available` или `unavailable` | `available` или `unavailable` |
| `face_saliency` | `available`, `not_applicable` или `unavailable` | `available`, `not_applicable` или `unavailable` |
| `balance_confidence` | `not_applicable` | `available` или `unavailable` |
| `depth_separation` | `not_applicable` | `available` или `unavailable` |
| `cinematic_expressiveness` | `not_applicable` | `available` или `unavailable` |
| `shot_type_confidence` | `not_applicable` | `available` или `unavailable` |

Уточнение для `face_saliency`:
- `not_applicable`, если кадр не person-centric по contract semantics;
- `unavailable`, если head был допустим и должен был исполняться, но runtime не смог вернуть результат.

## Confidence semantics

### Общие правила

- Все `score` и `confidence` нормализованы в `0.0 ... 1.0`.
- `score` и `confidence` нельзя смешивать: высокий score при низком confidence означает "сигнал есть, но мы ему мало доверяем".
- `confidence` оценивает надежность head-а для текущего кадра, а не product importance.
- `not_applicable` и `unavailable` должны различаться явно; они не кодируются через `score = 0`.
- при `status == not_applicable` `confidence == 0.0`, потому что head не участвует в сравнении и fusion;
- при `status == unavailable` `confidence == 0.0`, потому что у runtime нет надежного head output-а для использования downstream.

### Интерпретация confidence по диапазонам

| Confidence | Семантика | Разрешенное downstream использование |
|---|---|---|
| `0.00 ... 0.24` | почти недоверяемый сигнал | логировать/debug only |
| `0.25 ... 0.44` | слабый сигнал | можно учитывать только как tie-break рядом с deterministic evidence |
| `0.45 ... 0.64` | рабочий pause-grade сигнал | допускается bounded fusion в `pause` |
| `0.65 ... 1.00` | strong usable signal | допускается normal fusion, а для `live` это минимально желательный уровень |

### Downstream confidence policy

- head не может в одиночку создавать новый `FrameIssue`, если deterministic path не видит хотя бы weakly compatible basis;
- low-confidence neural evidence может понизить уверенность рекомендаций, но не должен переопределять их тип;
- `cinematic_expressiveness` никогда не используется как sole driver для corrective action;
- `shot_type_confidence` используется только как calibration/context signal.

## Mapping к issue taxonomy

Ниже `primary heads` означают основные hybrid evidence inputs, а `secondary heads` допускаются как дополнительные факторы. `Mode scope` относится к neural support, а не к существованию самого issue в deterministic pipeline.

| IssueTypeV1 | Mode scope for neural support | Primary heads by mode | Secondary heads by mode | Комментарий |
|---|---|---|---|---|
| `subject_too_close_to_edge` | `live`, `pause` | `live`: `face_saliency`; `pause`: `balance_confidence` | `live`: `subject_prominence`; `pause`: `subject_prominence`, `shot_type_confidence` | В `live` issue остается разрешен deterministic core; neural support only calibrates confidence when face/head anchor helps confirm edge pressure |
| `subject_not_prominent_enough` | `live`, `pause` | `live`: `subject_prominence`; `pause`: `subject_prominence`, `depth_separation` | `live`: `face_saliency`, `background_clutter`; `pause`: `face_saliency`, `background_clutter` | Главная задача hybrid layer для ambiguous portrait/object frames |
| `background_competes_with_subject` | `live`, `pause` | `live`: `background_clutter`; `pause`: `background_clutter` | `live`: `subject_prominence`; `pause`: `subject_prominence`, `depth_separation` | High clutter сам по себе еще не action, но усиливает deterministic basis |
| `insufficient_look_space` | `live`, `pause` | `live`: `face_saliency`; `pause`: `balance_confidence` | `live`: `subject_prominence`; `pause`: `subject_prominence`, `shot_type_confidence` | Допустимо только для person-centric scenes; в `live` neural path only supports person-centric readability, not shot-intent reasoning |
| `backlight_hides_subject` | `live`, `pause` | `live`: `lighting_quality`; `pause`: `lighting_quality` | `live`: `face_saliency`; `pause`: `face_saliency`, `depth_separation`, `shot_type_confidence` | `moody_backlit_subject_affinity` помогает отличать stylistic intent от failure case только в `pause` |
| `scene_has_no_clear_focus` | `live`, `pause` | `live`: `subject_prominence`, `background_clutter`; `pause`: `subject_prominence`, `background_clutter` | `live`: none; `pause`: `balance_confidence` | Нейрослой полезен как confidence calibrator, не как единственный judge |
| `frame_visually_overloaded` | `live`, `pause` | `live`: `background_clutter`; `pause`: `background_clutter` | `live`: `subject_prominence`; `pause`: `subject_prominence`, `balance_confidence` | Особенно полезно на busy indoor/outdoor scenes |
| `horizon_distracts` | `pause` optional support | `pause`: none required | `pause`: `balance_confidence` | В `v1 hybrid` остается почти полностью deterministic issue |

## Mapping к strength taxonomy

| StrengthTypeV1 | Supporting heads |
|---|---|
| `good_subject_isolation` | `subject_prominence`, `depth_separation`, inverse `background_clutter` |
| `good_light_emphasis` | `lighting_quality`, `face_saliency` |
| `clear_focus_hierarchy` | `subject_prominence`, inverse `background_clutter` |
| `stable_horizon_supports_scene` | deterministic only, optional `balance_confidence` support |
| `balanced_composition_for_scene` | `balance_confidence`, `shot_type_confidence` |

## Mapping к action taxonomy

Нормативное правило:
- neural evidence в `PR-H02` может усиливать или ослаблять уверенность в action family, но не выбирает spatial direction самостоятельно;
- выбор между `left/right/up/down` остается в deterministic contract и должен опираться на уже существующие signed/geometric signals (`horizontalOffset`, `verticalOffset`, `lookSpaceAdequate`, `affectedRegion`, overlay geometry).
- если row использует pause-only heads, этот mapping относится только к `pause`;
- `live` implementation не может опираться на `balance_confidence`, `depth_separation`, `cinematic_expressiveness` или `shot_type_confidence`.
- `Mode scope` ниже описывает только availability neural support, а не availability самого `ActionTypeV1`; availability action-а по режимам по-прежнему задается deterministic `RecommendationPlan`.

| ActionTypeV1 | Mode scope | Head patterns that may strengthen action confidence | Direction rule |
|---|---|---|---|
| `move_frame_left` / `move_frame_right` | `live`, `pause` | `live`: low `face_saliency` when person-centric; `pause`: low `balance_confidence`, low `face_saliency`, person-centric `shot_type_confidence` | выбор `left` vs `right` только из deterministic spatial signals |
| `move_frame_up` / `move_frame_down` | `live`, `pause` | `live`: weak `subject_prominence`; `pause`: low `balance_confidence` plus weak `subject_prominence` | выбор `up` vs `down` только из deterministic spatial signals |
| `increase_subject_size` | `live`, `pause` | `live`: low `subject_prominence`, low `face_saliency`; `pause`: low `subject_prominence`, low `depth_separation`, low `face_saliency` | direction not applicable |
| `reduce_background_distractions` | `live`, `pause` | `live`: high `background_clutter`, low `subject_prominence`; `pause`: same, optionally strengthened by low `balance_confidence` | concrete crop/shift geometry only from deterministic path |
| `change_angle` | `live`, `pause` | `live`: high `background_clutter`, low `lighting_quality`; `pause`: same, optionally strengthened by low `depth_separation` | concrete angle choice only from deterministic path |
| `improve_front_light` | `live`, `pause` | low `lighting_quality`, low `face_saliency` | direction not applicable |
| `level_horizon` | `live`, `pause` | primarily deterministic only; neural support is optional and weak in `pause`, none required in `live` | rotation amount/direction only from deterministic path |
| `leave_frame_as_is` | `live`, `pause` | `live`: high `subject_prominence`, high `lighting_quality`, low `background_clutter`; `pause`: same, optionally strengthened by strong `balance_confidence` | direction not applicable |

## Mapping examples

### Example A. Small portrait lost in busy background

Observed hybrid evidence:
- `subject_prominence = 0.24`, `confidence = 0.83`
- `background_clutter = 0.78`, `confidence = 0.81`
- `depth_separation = 0.29`, `confidence = 0.67`
- `face_saliency = 0.34`, `confidence = 0.76`

Likely downstream effect:
- strengthens `subject_not_prominent_enough`
- strengthens `background_competes_with_subject`
- raises confidence for `increase_subject_size`
- raises confidence for `reduce_background_distractions`

### Example B. Backlit closeup with intentional mood but weak face readability

Observed hybrid evidence:
- `lighting_quality = 0.31`, `confidence = 0.79`
- `face_saliency = 0.28`, `confidence = 0.73`
- `shot_type_confidence.affinities = { moody_backlit_subject_affinity: 0.72, unknown_affinity: 0.11, ... }`, `confidence = 0.64`

Likely downstream effect:
- supports `backlight_hides_subject`
- keeps `moody_backlit_subject` as plausible scene intent
- makes `improve_front_light` stronger than generic `change_angle`, but does not suppress issue automatically

### Example C. Strong readable portrait in pause analysis

Observed hybrid evidence:
- `subject_prominence = 0.86`, `confidence = 0.88`
- `depth_separation = 0.81`, `confidence = 0.72`
- `lighting_quality = 0.79`, `confidence = 0.76`
- `background_clutter = 0.18`, `confidence = 0.83`

Likely downstream effect:
- supports `good_subject_isolation`
- supports `good_light_emphasis`
- keeps `leave_frame_as_is` credible if deterministic issues are absent

### Example D. Edge-pressure ambiguity in two-character frame

Observed hybrid evidence:
- `balance_confidence = 0.42`, `confidence = 0.58`
- `shot_type_confidence.affinities = { two_character_frame_affinity: 0.75, unknown_affinity: 0.09, ... }`, `confidence = 0.61`

Interpretation:
- signal weakly suggests compositional tension, but confidence is only pause-grade
- fusion may lower certainty of `subject_too_close_to_edge`, not create it by itself

### Example E. Rich stylistic frame with high expressiveness but mediocre corrective utility

Observed hybrid evidence:
- `cinematic_expressiveness = 0.90`, `confidence = 0.69`
- `subject_prominence = 0.44`, `confidence = 0.52`
- `background_clutter = 0.63`, `confidence = 0.66`

Interpretation:
- expressive style cannot cancel readability issues
- `cinematic_expressiveness` may enrich pause explanation or ranking, but cannot suppress corrective action if clutter/prominence remain problematic

## Invariants

- Каждый head имеет фиксированную семантику, независимую от конкретной модели, checkpoint-а или endpoint-а.
- Head output всегда structured; free-form text запрещен.
- `score = 0` означает реальное отсутствие свойства, а не missing data.
- `not_applicable` и `unavailable` должны быть различимы во всех runtime/data/eval представлениях.
- `not_applicable` и `unavailable` всегда сериализуются с `confidence == 0.0`; для scalar head-а `score == nil`, для categorical head-а `affinities == []`.
- Ни один head не может породить новый `IssueTypeV1`, `StrengthTypeV1` или `ActionTypeV1` вне существующих deterministic catalogs.
- `cinematic_expressiveness` не может быть sole driver для issue/action generation.
- `shot_type_confidence` не может единолично переписать `SceneTypeV1`.
- `shot_type_confidence` всегда сериализуется как `CategoricalEvidenceHeadOutput` с полным closed catalog affinities в canonical order.
- `live` runtime не использует pause-only heads.
- Для person-agnostic scenes `face_saliency` обязан быть `not_applicable`, а не "низким".
- Если neural head конфликтует с deterministic signal при низком confidence, приоритет у deterministic signal.
- Horizon-related critique не должен зависеть от обязательного neural head в `PR-H02`.

## Что это разблокирует дальше

После фиксации этого документа:
- `PR-H03` может строить dataset schema вокруг explicit axes, applicability и disagreement rules;
- `PR-H05` может выбирать model outputs только из разрешенного catalog;
- `PR-H06` может оформлять строгий runtime/domain contract без переизобретения названий и смыслов;
- `PR-H09` может проектировать fusion layer как bounded calibration system, а не как black-box critic.

## Definition of Done (design mode)

Этот design считается готовым, если:
- taxonomy покрывает разрешенные neural evidence heads без расползания scope;
- scoring axes и polarity каждого head-а зафиксированы;
- `live` и `pause` responsibilities разведены;
- confidence semantics пригодны для dataset, runtime и eval;
- mapping к issue/action taxonomy и examples позволяют запускать `PR-H03` без домысливания.
