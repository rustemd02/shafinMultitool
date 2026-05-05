# 24. Semantic Tip Taxonomy and Action Catalog (PR-S01)

Статус: implement + verify

Дата: 2026-05-04

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md)
- [CameraAnalysisDomainContracts.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift)

## Цель

Зафиксировать закрытый и entity-aware каталог экранных семантических подсказок так, чтобы система детерминированно проходила путь:

`observation/evidence -> issue/strength -> semantic tip -> short screen action`

и выдавала не абстрактную оценку, а понятное физическое действие:
- `Смести камеру чуть правее.`
- `Опусти камеру ниже.`
- `Отодвинь героя от фона.`
- `Сдвинь цветок правее.`
- `Убери вазу из-за лица.`
- `Добавь слабый фоновый свет.`
- `Оставь кадр как есть.`

Этот документ нужен, чтобы:
- `PR-S01` мог безопасно ввести entity-aware semantic tip layer;
- `PR-S02` принимал только разрешенные semantic action ids и entity fields;
- будущие `PR-S04` и `PR-S05` могли развивать planner/materializer и object-aware mappings без перепридумывания taxonomy;
- `live` и `pause` UI получали краткие, actionable и explainable screen tips;
- deterministic critique core оставался source-of-truth для problems, strengths и planner anchors.

## Что расширено относительно предыдущей версии `PR-S01`

По сравнению с предыдущей версией этот source-of-truth теперь:
- добавляет entity-aware слой (`targetEntityKind`, `targetEntityRole`, `targetEntityRef`, display labels, `actionFrame`, `direction`);
- расширяет покрытие beyond framing/light в сторону composition, camera height, perspective, depth/separation, subject staging, object/prop staging и timing cues;
- вводит object-centric и prop-centric cases как first-class screen-tip scenarios;
- фиксирует safe display label policy без свободной галлюцинации названий;
- разделяет `v1 included` и `deferred` action families, чтобы implementer не гадал, что реально поддерживается первой версией;
- добавляет golden examples не только для portrait, но и для dialogue и object-centric shots.

## Scope и ограничения

В scope:
- `SemanticTipType` и `SemanticActionType`;
- `VisualProblemType` и `VisualStrengthType`;
- entity-aware fields для materialized semantic tips;
- closed live/pause copy contract;
- mapping к `IssueTypeV1`, `StrengthTypeV1`, `FixTypeV1`, `ActionTypeV1`;
- priority / merge / suppress / fallback rules;
- `v1` vs deferred boundary;
- golden examples и implement test plan.

Вне scope:
- UI wiring;
- VLM/provider/network implementation;
- изменение semantic cases `IssueTypeV1`, `StrengthTypeV1`, `ActionTypeV1` за пределы contract-safe compile/test conformance;
- свободный prose-generator как decision source;
- расширение deterministic critique taxonomy за пределы `PR-007`.

Нормативные ограничения:
- tip materialize-ится только из существующих findings, deterministic semantics, planner anchors и bounded semantic mapping;
- tip должна быть actionable и physically meaningful;
- каждая tip обязана иметь explainability chain `observation -> interpretation -> recommendation`;
- каталог не должен разрастаться до сотен cases, но не может оставаться слишком бедным для реальных cinematic prompts;
- future VLM path не может invent-ить новые ids мимо этого документа.

## `v1` boundary

### Входит в `v1`

`v1` обязан поддерживать:
- camera reframing:
  - `shift_frame_left`
  - `shift_frame_right`
  - `shift_frame_up`
  - `shift_frame_down`
  - `step_back`
  - `step_closer`
  - `lower_camera`
  - `raise_camera`
  - `change_camera_angle`
  - `level_horizon`
- subject staging:
  - `rotate_subject_toward_light`
  - `move_subject_left`
  - `move_subject_right`
  - `move_subject_away_from_background`
- object / prop staging:
  - `move_object_left`
  - `move_object_right`
  - `move_object_forward`
  - `move_object_back`
  - `remove_distracting_object`
  - `reposition_prop_for_balance`
- lighting:
  - `add_front_fill_light`
  - `add_background_light`
  - `remove_background_hotspot`
- timing / cleanup:
  - `simplify_background`
  - `wait_for_background_clearance`
  - `keep_current_setup`

### Отложено после `v1`

Осознанно откладываются:
- `add_rim_light`
- `add_side_light`
- `turn_subject_for_cleaner_profile`

Причина defer:
- для них нужен более надежный deterministic signal о light placement, profile angle и 3D spatial relation;
- существующие `PR-007`, `PR-H02`, `PR-H06`, `PR-H09` пока дают достаточную основу для `background light`, `front fill`, `camera angle`, `subject/background separation`, но не для узких lighting/profile nuances;
- их отсутствие не ломает исходную продуктовую цель, потому что базовые screen tips уже покрывают основные пользовательские действия: камера, свет, staging субъекта, staging предметов и timing.

## Contract position в pipeline

`PR-S01` не заменяет `RecommendationPlan`, а добавляет bounded presentation/domain bridge:

`FrameFeatureSnapshot / SceneSemanticsReport / CritiqueReport / RecommendationPlan -> SemanticTipMapper -> LiveHintPresentation / PauseCritiquePresentation`

Роли:
- `IssueTypeV1` / `StrengthTypeV1` отвечают за domain findings;
- `ActionTypeV1` отвечает за planner-level transport action;
- `SemanticActionType` отвечает за понятное человеку физическое действие;
- `SemanticTipType` отвечает за closed user-facing semantic intent и copy template;
- entity-aware fields говорят, кого именно и чем нужно двигать;
- `VisualProblemType` / `VisualStrengthType` обеспечивают compact semantic reasoning и future-compatible bridge для `PR-S02`, `PR-S04`, `PR-S05`.

## Entity-aware contract

### `TargetEntityKind`

```text
TargetEntityKind
- person
- face
- object
- prop
- background_area
- light_source
- frame
- unknown
```

### `TargetEntityRole`

```text
TargetEntityRole
- primary_subject
- secondary_subject
- foreground_object
- background_object
- distracting_object
- prop
- face_contour_occluder
- light_target
- background_zone
- whole_frame
```

### `SemanticActionFrame`

```text
SemanticActionFrame
- move_camera
- move_subject
- move_object
- adjust_light
- wait
```

### `SemanticDirection`

```text
SemanticDirection
- left
- right
- up
- down
- forward
- back
- none
```

`none` используется только когда действие не directional по смыслу (`simplify_background`, `keep_current_setup`).

### Suggested runtime shape

```text
SemanticTipCandidate
- tipType: SemanticTipType
- actionType: SemanticActionType
- actionFrame: SemanticActionFrame
- direction: SemanticDirection?
- problemType: VisualProblemType?             // required for corrective tips
- strengthType: VisualStrengthType?           // required for positive tips
- targetEntityKind: TargetEntityKind          // required
- targetEntityRole: TargetEntityRole          // required
- targetEntityRef: String?                    // stable id within frame if grounded
- targetEntityGroundingConfidence: Double?    // required for concrete object labels
- targetEntityDisplayLabel: String            // safe display label
- secondaryEntityRef: String?                 // optional relation target
- secondaryEntityGroundingConfidence: Double? // required for concrete secondary object labels
- secondaryEntityDisplayLabel: String?        // optional safe display label
- primaryActionId: String?
- linkedActionIds: [String]
- linkedIssueIds: [String]
- linkedStrengthIds: [String]
- linkedTraceIds: [String]
- summaryId: String?
- supportedModes: [AnalysisMode]
- priorityBand: SemanticTipPriorityBand
- liveText: String
- pauseText: String
- fallbackBehavior: SemanticTipFallback
```

### `SemanticTipPriorityBand`

```text
SemanticTipPriorityBand
- primary_corrective
- secondary_corrective
- contextual_corrective
- timing_corrective
- positive_confirmation
```

### `SemanticTipFallback`

```text
SemanticTipFallback
- suppress
- degrade_to_generic_label
- degrade_to_generic_action_copy
- replace_with_keep_frame_as_is
- use_legacy_suggestion
```

### Invariants

- corrective tip обязана иметь `problemType`, `linkedIssueIds` и `primaryActionId` либо documented aggregated bundle;
- positive tip обязана иметь `strengthType` или `inputVerdict == good`;
- positive tip обязана иметь `summaryId`;
- `targetEntityDisplayLabel` и `secondaryEntityDisplayLabel` обязаны следовать safe label policy;
- `targetEntityDisplayLabel` обязан быть совместим с `targetEntityKind`: object vocabulary нельзя использовать для person / face tips;
- конкретные object / prop labels требуют non-empty entity ref и high-confidence grounding (`>= 0.75`);
- `liveText` и `pauseText` строятся только из closed templates;
- `linkedTraceIds` обязаны резолвиться к `recommendation` trace item и его supporting `interpretation` chain;
- `targetEntityRef` и `secondaryEntityRef` never invent ids: если grounding нет, они `nil`, а текст деградирует до generic label;
- `wait` actions запрещены в `live` при `motion.state != still` only if underlying planner already suppresses usable hint; иначе wait cue разрешен как компактная подсказка;
- `keep_current_setup` не может coexist-ить в одном output с corrective tip на тот же `frameId + mode`.

## Safe display label policy

Display labels обязаны быть bounded и confidence-aware.

Policy применяется kind-aware: `person` / `face` labels не могут брать object vocabulary, даже если есть object-like ref или confidence; object vocabulary допустим только для `object` / `prop` targets.

### Person / face

- high confidence person / face:
  - `герой`
  - `человек`
  - `лицо`
  - `персонаж`
- нельзя invent-ить конкретные имена (`Алексей`, `девушка с гитарой`) без явного grounded metadata source, которого в `v1` нет.

### Object / prop

- high-confidence grounded object:
  - конкретное имя объекта допускается только если:
    - detection/semantics label стабилен;
    - confidence достаточно высокий (`>= 0.75`);
    - label входит в allowed grounded object vocabulary;
    - label не конфликтует с ambiguity policy.
  - примеры: `цветок`, `ваза`, `книга`, `чашка`.
- medium / low confidence object:
  - `предмет`
  - `объект справа`
  - `яркий объект на фоне`
  - `предмет у лица`

### Allowed grounded object vocabulary for `v1`

```text
GroundedObjectDisplayLabelV1
- цветок
- ваза
- книга
- чашка
- бутылка
- лампа
- стул
- телефон
```

Если label вне словаря или grounding нестабилен:
- использовать generic label;
- не апгрейдить generic label в более конкретный в рамках одного frame без confidence jump policy;
- `PR-S02` и future VLM paths обязаны уважать эту же политику.

## Type definitions

### `VisualProblemType`

```text
VisualProblemType
- subject_edge_pressure
- object_edge_pressure
- tight_framing
- insufficient_look_space
- weak_subject_prominence
- weak_object_prominence
- background_competition
- background_clutter
- front_light_deficit
- subject_blends_into_dark_background
- bright_background_pull
- flat_depth
- weak_subject_background_separation
- camera_height_mismatch
- perspective_mismatch
- unclear_focus_hierarchy
- prop_breaks_balance
- object_conflicts_with_subject
- face_contour_occlusion
- tilted_horizon
- timing_blocker_in_frame
```

Нормативные правила:
- это user-facing semantic grouping, а не замена `IssueTypeV1`;
- один `FrameIssue` может materialize-ить один dominant `VisualProblemType` при наличии selector rules;
- object/prop-specific problem type обязан иметь grounded or safely-generic target entity.

### `VisualStrengthType`

```text
VisualStrengthType
- clean_subject_separation
- flattering_light_direction
- clear_focus_hierarchy
- balanced_scene_composition
- stable_horizon
- readable_depth_layers
- object_balance_holds
- frame_ready
```

### `SemanticActionType`

```text
SemanticActionType
- shift_frame_left
- shift_frame_right
- shift_frame_up
- shift_frame_down
- step_back
- step_closer
- lower_camera
- raise_camera
- change_camera_angle
- level_horizon
- rotate_subject_toward_light
- move_subject_left
- move_subject_right
- move_subject_away_from_background
- move_object_left
- move_object_right
- move_object_forward
- move_object_back
- remove_distracting_object
- reposition_prop_for_balance
- add_front_fill_light
- add_background_light
- remove_background_hotspot
- simplify_background
- wait_for_background_clearance
- keep_current_setup
```

### `SemanticTipType`

```text
SemanticTipType
- create_look_space_left
- create_look_space_right
- move_subject_off_left_edge
- move_subject_off_right_edge
- move_object_off_left_edge
- move_object_off_right_edge
- add_headroom
- show_more_lower_frame
- step_back_for_breathing_room
- step_closer_for_subject_prominence
- step_closer_for_object_prominence
- lower_camera_for_subject
- raise_camera_for_subject
- change_angle_for_cleaner_background
- add_depth_by_moving_subject_from_background
- add_depth_by_moving_object_forward
- move_object_back_for_balance
- move_subject_left_for_balance
- move_subject_right_for_balance
- move_object_left_for_balance
- move_object_right_for_balance
- remove_object_from_face_contour
- remove_distracting_prop
- rebalance_prop_layout
- turn_subject_toward_light
- add_front_fill_on_subject
- add_background_light_for_separation
- remove_bright_spot_behind_subject
- clarify_main_subject_focus
- simplify_busy_background
- wait_for_background_clearance
- level_horizon_for_stability
- keep_subject_separation
- keep_light_direction
- keep_focus_hierarchy
- keep_horizon_stability
- keep_depth_readability
- keep_object_balance
- keep_frame_as_is
```

## Materialization anchors

`SemanticTipMapper` обязан materialize-ить tip только из frozen anchor patterns:

1. `direct planner action anchor`
   - есть `RecommendationAction.id`;
   - есть `ActionTypeV1`, который 1:1 или bounded-many:1 маппится в `SemanticActionType`;
   - tip наследует этот action как `primaryActionId`.

2. `aggregated planner bundle`
   - semantic tip объединяет несколько planner actions или несколько findings;
   - используется только для bounded merge cases;
   - `primaryActionId == nil`, но `linkedActionIds` непустой и детерминированно отсортирован.

3. `good frame anchor`
   - `RecommendationPlan.primaryAction.actionType == leave_frame_as_is`;
   - либо `primaryAction == nil` и `noChangeRationale` непустой;
   - используется только для positive tips.

Нормативные правила:
- semantic tip never materialize-ится напрямую из free-form `expectedOutcome`;
- если anchor отсутствует, tip suppress-ится или деградирует по documented fallback;
- entity-aware layer не invent-ит новые entities: он только materialize-ит существующие grounded refs или generic labels.

## Deterministic selector rules

Запрещены правила вида `or maybe` / `derived somehow`.

Обязательные selector rules:
- `step_back_for_breathing_room`
  - aggregated bundle;
  - `2+` linked corrective actions;
  - merged framing evidence (`tight_framing`, multi-edge pressure, subject too large).
- `step_closer_for_object_prominence`
  - только если `primarySubject.kind in {object, unknown}` и object-centric readability доминирует;
  - person-centric case сюда не попадает.
- `lower_camera_for_subject` / `raise_camera_for_subject`
  - только если `camera_height_mismatch` dominant problem;
  - не используются для simple edge pressure without perspective mismatch.
- `add_depth_by_moving_subject_from_background`
  - только если `weak_subject_background_separation` или `flat_depth` dominant;
  - требует person-centric subject.
- `add_depth_by_moving_object_forward`
  - только если `weak_object_prominence` или `flat_depth` dominant в object-centric frame.
- `remove_object_from_face_contour`
  - требует grounded `secondaryEntityRef` с ролью `face_contour_occluder`;
  - без grounding деградирует до `remove_distracting_prop`.
- `remove_distracting_prop`
  - требует secondary object/prop, который конфликтует с контуром субъекта или центром внимания;
  - если secondary object не grounded, label деградирует до generic.
- `rebalance_prop_layout`
  - только для object/prop-centric composition imbalance;
  - не используется для person framing.
- `turn_subject_toward_light`
  - только если dominant `VisualProblemType == front_light_deficit`;
  - localized hotspot behind subject не должен быть dominant cause.
- `add_front_fill_on_subject`
  - только если front-light deficit есть, но turn/reposition не является preferred first action;
  - допустим mostly in `pause`, `live` only when cue extremely stable.
- `add_background_light_for_separation`
  - только если subject readable enough, но separation against dark background still weak;
  - не подменяет `remove_background_hotspot`.
- `wait_for_background_clearance`
  - только если blocker transient by semantics;
  - не подменяет `simplify_background` при стабильном clutter.

## Mapping к существующим contracts

### `VisualProblemType -> primary IssueTypeV1`

| `VisualProblemType` | Primary `IssueTypeV1` | Secondary evidence / issue context |
| --- | --- | --- |
| `subject_edge_pressure` | `subject_too_close_to_edge` | `insufficient_look_space` |
| `object_edge_pressure` | `subject_too_close_to_edge` | object-centric subject evidence |
| `tight_framing` | `subject_too_close_to_edge` | `subject_not_prominent_enough` |
| `insufficient_look_space` | `insufficient_look_space` | `subject_too_close_to_edge` |
| `weak_subject_prominence` | `subject_not_prominent_enough` | `scene_has_no_clear_focus` |
| `weak_object_prominence` | `subject_not_prominent_enough` | object-centric evidence |
| `background_competition` | `background_competes_with_subject` | `scene_has_no_clear_focus` |
| `background_clutter` | `frame_visually_overloaded` | `background_competes_with_subject` |
| `front_light_deficit` | `backlight_hides_subject` | `subject_not_prominent_enough` |
| `subject_blends_into_dark_background` | `subject_not_prominent_enough` | `backlight_hides_subject` |
| `bright_background_pull` | `background_competes_with_subject` | `backlight_hides_subject` |
| `flat_depth` | `subject_not_prominent_enough` | `background_competes_with_subject` |
| `weak_subject_background_separation` | `subject_not_prominent_enough` | `backlight_hides_subject` |
| `camera_height_mismatch` | `subject_too_close_to_edge` | perspective evidence |
| `perspective_mismatch` | `background_competes_with_subject` | `scene_has_no_clear_focus` |
| `unclear_focus_hierarchy` | `scene_has_no_clear_focus` | `background_competes_with_subject` |
| `prop_breaks_balance` | `background_competes_with_subject` | object-centric balance evidence |
| `object_conflicts_with_subject` | `background_competes_with_subject` | `scene_has_no_clear_focus` |
| `face_contour_occlusion` | `background_competes_with_subject` | person-centric occlusion evidence |
| `tilted_horizon` | `horizon_distracts` | none |
| `timing_blocker_in_frame` | `frame_visually_overloaded` | transient blocker evidence |

### `VisualStrengthType -> StrengthTypeV1`

| `VisualStrengthType` | Backing `StrengthTypeV1` |
| --- | --- |
| `clean_subject_separation` | `good_subject_isolation` |
| `flattering_light_direction` | `good_light_emphasis` |
| `clear_focus_hierarchy` | `clear_focus_hierarchy` |
| `balanced_scene_composition` | `balanced_composition_for_scene` |
| `stable_horizon` | `stable_horizon_supports_scene` |
| `readable_depth_layers` | `good_subject_isolation` + `clear_focus_hierarchy` |
| `object_balance_holds` | `balanced_composition_for_scene` |
| `frame_ready` | one or more strengths + `inputVerdict == good` |

### `SemanticActionType -> transport ActionTypeV1 / FixTypeV1`

`SemanticActionType` богаче transport taxonomy и допускает many-to-one mapping:

| `SemanticActionType` | Primary `ActionTypeV1` | Main `FixTypeV1` | Notes |
| --- | --- | --- | --- |
| `shift_frame_left` | `move_frame_left` | `reframing` | direct |
| `shift_frame_right` | `move_frame_right` | `reframing` | direct |
| `shift_frame_up` | `move_frame_up` | `reframing` | direct |
| `shift_frame_down` | `move_frame_down` | `reframing` | direct |
| `step_back` | no direct `1:1`; aggregated reframing bundle | `reframing` | bounded merge |
| `step_closer` | `increase_subject_size` | `reframing` | direct |
| `lower_camera` | `move_frame_down` or `change_angle` | `reframing` | selector-based |
| `raise_camera` | `move_frame_up` or `change_angle` | `reframing` | selector-based |
| `change_camera_angle` | `change_angle` | `angle_adjustment` | direct |
| `level_horizon` | `level_horizon` | `horizon_correction` | direct |
| `rotate_subject_toward_light` | `improve_front_light` | `lighting_adjustment` | subject staging |
| `move_subject_left` | `move_frame_right` or aggregated reframing bundle | `reframing` | semantic-only staging label |
| `move_subject_right` | `move_frame_left` or aggregated reframing bundle | `reframing` | semantic-only staging label |
| `move_subject_away_from_background` | `change_angle` | `angle_adjustment` | depth/separation cue |
| `move_object_left` | `change_angle` or aggregated bundle | `reframing` | object-centric |
| `move_object_right` | `change_angle` or aggregated bundle | `reframing` | object-centric |
| `move_object_forward` | `increase_subject_size` or `change_angle` | `reframing` | object-centric |
| `move_object_back` | aggregated reframing bundle | `reframing` | object-centric |
| `remove_distracting_object` | `reduce_background_distractions` | `angle_adjustment` | direct semantic bridge |
| `reposition_prop_for_balance` | `change_angle` or `reduce_background_distractions` | `angle_adjustment` | selector-based |
| `add_front_fill_light` | `improve_front_light` | `lighting_adjustment` | direct |
| `add_background_light` | `improve_front_light` or `change_angle` | `lighting_adjustment` | selector-based |
| `remove_background_hotspot` | `change_angle` or `improve_front_light` | `lighting_adjustment` | selector-based |
| `simplify_background` | `reduce_background_distractions` | `angle_adjustment` | direct |
| `wait_for_background_clearance` | `reduce_background_distractions` semantic bridge only | `angle_adjustment` | timing-only cue |
| `keep_current_setup` | `leave_frame_as_is` | `leave_frame_as_is` | direct |

Нормативная оговорка:
- `ActionTypeV1` остается planner transport contract;
- `SemanticActionType` richer and entity-aware;
- implementer не должен расширять `ActionTypeV1` в рамках `PR-S01`, если semantic action можно безопасно materialize-ить поверх существующих planner anchors.

## Object / entity-aware rules

### `targetEntityRef`

- если target grounded: использовать stable ref from semantics / detection / planner support layer;
- если grounding нет: `nil`, но `targetEntityDisplayLabel` остается safe/generic;
- если используется конкретный object label (`цветок`, `ваза`), `targetEntityRef` non-empty и `targetEntityGroundingConfidence >= 0.75`;
- runtime ids из других frames не переиспользуются.

### `secondaryEntityRef`

Используется только для relation-based tips:
- `убери вазу из-за лица`
- `сдвинь цветок правее относительно героя`
- `подожди, пока человек сзади выйдет из кадра`

Если `secondaryEntityDisplayLabel` является конкретным object label, `secondaryEntityRef` non-empty и `secondaryEntityGroundingConfidence >= 0.75`.

Если relation не grounded:
- `secondaryEntityRef = nil`
- `secondaryEntityDisplayLabel` generic or omitted
- copy деградирует к generic tip (`убери отвлекающий объект` / `подожди, пока фон очистится`).

### `actionFrame`

- `move_camera`: move only camera viewpoint or framing;
- `move_subject`: physically move/turn hero/person;
- `move_object`: physically move object/prop;
- `adjust_light`: add/remove/reposition lighting contribution;
- `wait`: no movement now, wait for transient cleanup.

`actionFrame` обязателен для all tips and is source-of-truth for future UI icons / prompt conditioning.

## Copy contract

### `live`

`live` text:
- максимум `90` символов;
- одна доминирующая инструкция;
- императив + краткая причина;
- без подчиненных clauses beyond one short reason.

Шаблон:

`<action phrase>: <reason phrase>.`

Примеры:
- `Смести камеру чуть правее: герою тесно у края.`
- `Опусти камеру ниже: ракурс сверху сплющивает сцену.`
- `Сдвинь цветок правее: предмет зажат у края.`
- `Убери объект у лица: контур героя ломается.`
- `Подожди секунду: фон скоро очистится.`

### `pause`

`pause` text:
- `1-3` коротких предложения;
- `reason -> physical action -> expected outcome`;
- relation labels только через safe display label policy.

Шаблон:

`<why>. <what to move/adjust/wait>. <what improves>.`

### Allowed generic phrases

Разрешенные generic phrases для `v1`:
- people: `герой`, `человек`, `персонаж`, `лицо`
- object: `предмет`, `объект`, `объект справа`, `яркий объект на фоне`
- relation: `у лица`, `на фоне`, `за героем`, `у края кадра`
- outcome: `кадр станет чище`, `объект читается лучше`, `силуэт отделится`, `баланс станет спокойнее`

Новые phrases нельзя добавлять ad hoc без обновления этого source-of-truth.

## Catalog of semantic tips

### A. Camera reframing and perspective

| `SemanticTipType` | `SemanticActionType` | `actionFrame` | `targetEntityRole` | `direction` | Problem anchors | Modes | Fallback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `create_look_space_left` | `shift_frame_left` | `move_camera` | `whole_frame` | `left` | `insufficient_look_space` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `create_look_space_right` | `shift_frame_right` | `move_camera` | `whole_frame` | `right` | `insufficient_look_space` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `move_subject_off_left_edge` | `shift_frame_right` | `move_camera` | `primary_subject` | `right` | `subject_edge_pressure` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `move_subject_off_right_edge` | `shift_frame_left` | `move_camera` | `primary_subject` | `left` | `subject_edge_pressure` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `move_object_off_left_edge` | `move_object_right` | `move_object` | `foreground_object` | `right` | `object_edge_pressure` | `live`, `pause` | `degrade_to_generic_label` |
| `move_object_off_right_edge` | `move_object_left` | `move_object` | `foreground_object` | `left` | `object_edge_pressure` | `live`, `pause` | `degrade_to_generic_label` |
| `add_headroom` | `shift_frame_up` | `move_camera` | `primary_subject` | `up` | `tight_framing` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `show_more_lower_frame` | `shift_frame_down` | `move_camera` | `primary_subject` | `down` | `tight_framing` | `pause` | `suppress` |
| `step_back_for_breathing_room` | `step_back` | `move_camera` | `whole_frame` | `back` | `tight_framing` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `step_closer_for_subject_prominence` | `step_closer` | `move_camera` | `primary_subject` | `forward` | `weak_subject_prominence` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `step_closer_for_object_prominence` | `step_closer` | `move_camera` | `foreground_object` | `forward` | `weak_object_prominence` | `live`, `pause` | `degrade_to_generic_label` |
| `lower_camera_for_subject` | `lower_camera` | `move_camera` | `primary_subject` | `down` | `camera_height_mismatch`, `perspective_mismatch` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `raise_camera_for_subject` | `raise_camera` | `move_camera` | `primary_subject` | `up` | `camera_height_mismatch`, `perspective_mismatch` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `change_angle_for_cleaner_background` | `change_camera_angle` | `move_camera` | `whole_frame` | `none` | `background_competition`, `perspective_mismatch` | `live`, `pause` | `use_legacy_suggestion` |
| `level_horizon_for_stability` | `level_horizon` | `move_camera` | `whole_frame` | `none` | `tilted_horizon` | `live`, `pause` | `degrade_to_generic_action_copy` |

### B. Subject staging and depth

| `SemanticTipType` | `SemanticActionType` | `actionFrame` | `targetEntityRole` | `direction` | Problem anchors | Modes | Fallback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `move_subject_left_for_balance` | `move_subject_left` | `move_subject` | `primary_subject` | `left` | `background_competition`, `unclear_focus_hierarchy` | `pause` | `degrade_to_generic_action_copy` |
| `move_subject_right_for_balance` | `move_subject_right` | `move_subject` | `primary_subject` | `right` | `background_competition`, `unclear_focus_hierarchy` | `pause` | `degrade_to_generic_action_copy` |
| `add_depth_by_moving_subject_from_background` | `move_subject_away_from_background` | `move_subject` | `primary_subject` | `back` | `weak_subject_background_separation`, `flat_depth` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `turn_subject_toward_light` | `rotate_subject_toward_light` | `move_subject` | `primary_subject` | `none` | `front_light_deficit` | `live`, `pause` | `degrade_to_generic_action_copy` |

### C. Object / prop staging

| `SemanticTipType` | `SemanticActionType` | `actionFrame` | `targetEntityRole` | `direction` | Problem anchors | Modes | Fallback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `move_object_left_for_balance` | `move_object_left` | `move_object` | `foreground_object` | `left` | `prop_breaks_balance`, `object_conflicts_with_subject` | `live`, `pause` | `degrade_to_generic_label` |
| `move_object_right_for_balance` | `move_object_right` | `move_object` | `foreground_object` | `right` | `prop_breaks_balance`, `object_conflicts_with_subject` | `live`, `pause` | `degrade_to_generic_label` |
| `add_depth_by_moving_object_forward` | `move_object_forward` | `move_object` | `foreground_object` | `forward` | `weak_object_prominence`, `flat_depth` | `pause` | `degrade_to_generic_label` |
| `move_object_back_for_balance` | `move_object_back` | `move_object` | `foreground_object` | `back` | `object_conflicts_with_subject`, `prop_breaks_balance` | `pause` | `degrade_to_generic_label` |
| `remove_object_from_face_contour` | `remove_distracting_object` | `move_object` | `face_contour_occluder` | `none` | `face_contour_occlusion`, `object_conflicts_with_subject` | `live`, `pause` | `degrade_to_generic_label` |
| `remove_distracting_prop` | `remove_distracting_object` | `move_object` | `distracting_object` | `none` | `object_conflicts_with_subject`, `background_competition` | `live`, `pause` | `degrade_to_generic_label` |
| `rebalance_prop_layout` | `reposition_prop_for_balance` | `move_object` | `prop` | `none` | `prop_breaks_balance`, `weak_object_prominence` | `pause` | `degrade_to_generic_label` |

### D. Lighting

| `SemanticTipType` | `SemanticActionType` | `actionFrame` | `targetEntityRole` | `direction` | Problem anchors | Modes | Fallback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `add_front_fill_on_subject` | `add_front_fill_light` | `adjust_light` | `light_target` | `none` | `front_light_deficit` | `pause` | `degrade_to_generic_action_copy` |
| `add_background_light_for_separation` | `add_background_light` | `adjust_light` | `background_zone` | `none` | `subject_blends_into_dark_background`, `weak_subject_background_separation` | `pause` | `degrade_to_generic_action_copy` |
| `remove_bright_spot_behind_subject` | `remove_background_hotspot` | `adjust_light` | `background_zone` | `none` | `bright_background_pull` | `live`, `pause` | `degrade_to_generic_action_copy` |

### E. Timing / cleanup

| `SemanticTipType` | `SemanticActionType` | `actionFrame` | `targetEntityRole` | `direction` | Problem anchors | Modes | Fallback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clarify_main_subject_focus` | `step_closer` | `move_camera` | `primary_subject` | `forward` | `unclear_focus_hierarchy` | `live`, `pause` | `degrade_to_generic_action_copy` |
| `simplify_busy_background` | `simplify_background` | `move_object` | `background_zone` | `none` | `background_clutter` | `live`, `pause` | `use_legacy_suggestion` |
| `wait_for_background_clearance` | `wait_for_background_clearance` | `wait` | `background_object` | `none` | `timing_blocker_in_frame` | `live`, `pause` | `degrade_to_generic_action_copy` |

### F. Positive tips

| `SemanticTipType` | `SemanticActionType` | `actionFrame` | Strength anchors | Modes | Fallback |
| --- | --- | --- | --- | --- | --- |
| `keep_subject_separation` | `keep_current_setup` | `move_camera` | `clean_subject_separation` | `live`, `pause` | `replace_with_keep_frame_as_is` |
| `keep_light_direction` | `keep_current_setup` | `adjust_light` | `flattering_light_direction` | `live`, `pause` | `replace_with_keep_frame_as_is` |
| `keep_focus_hierarchy` | `keep_current_setup` | `move_camera` | `clear_focus_hierarchy` | `live`, `pause` | `replace_with_keep_frame_as_is` |
| `keep_horizon_stability` | `keep_current_setup` | `move_camera` | `stable_horizon` | `live`, `pause` | `replace_with_keep_frame_as_is` |
| `keep_depth_readability` | `keep_current_setup` | `move_camera` | `readable_depth_layers` | `live`, `pause` | `replace_with_keep_frame_as_is` |
| `keep_object_balance` | `keep_current_setup` | `move_object` | `object_balance_holds` | `live`, `pause` | `replace_with_keep_frame_as_is` |
| `keep_frame_as_is` | `keep_current_setup` | `move_camera` | `frame_ready` | `live`, `pause` | `use_legacy_suggestion` |

## Merge rules

Обязательные merge cases:
- `subject_edge_pressure` + `insufficient_look_space` на одной стороне -> показывать только `create_look_space_left/right`;
- multiple edge pressures + subject too large -> `step_back_for_breathing_room`;
- object edge pressure + weak object prominence -> `move_object_off_left/right_edge` важнее generic `step_closer_for_object_prominence`;
- `background_competition` + `background_clutter` -> `simplify_busy_background`, если clutter сильнее angle-specific причины;
- `background_competition` без clutter, но с clean alternative angle -> `change_angle_for_cleaner_background`;
- `weak_subject_background_separation` + person-centric subject -> `add_depth_by_moving_subject_from_background` before lighting-only tip;
- `subject_blends_into_dark_background` + readable face -> `add_background_light_for_separation` only in `pause`;
- `face_contour_occlusion` + grounded prop/object -> `remove_object_from_face_contour`;
- `object_conflicts_with_subject` without contour overlap -> `remove_distracting_prop`;
- `timing_blocker_in_frame` -> `wait_for_background_clearance`, если blocker transient; otherwise `simplify_busy_background`.

## Suppression rules

- conflicting directional tips (`left/right`, `up/down`) never coexist in the same `live` output;
- `show_more_lower_frame`, `move_subject_left/right_for_balance`, `rebalance_prop_layout`, `add_front_fill_on_subject`, `add_background_light_for_separation`, `add_depth_by_moving_object_forward`, `move_object_back_for_balance` are `pause`-only;
- object/prop tips suppress-ятся, если target entity neither grounded nor safely generically localizable;
- person-centric tips suppress-ятся, если `primarySubject.kind` не входит в `{face, person, group}`;
- `wait_for_background_clearance` suppress-ится, если blocker stable/non-transient;
- positive tip suppress-ится, если есть corrective issue with `severity >= 0.40`;
- tip suppress-ится, если нет валидной trace chain или selector rule не сработал.

## Good-frame policy

Positive path валиден, если:
- `CritiqueReport.verdict == good` и `primaryAction.actionType == leave_frame_as_is`;
- либо `primaryAction == nil` и `noChangeRationale` непустой.

Правила:
- если одна strength доминирует, materialize specific positive tip;
- если object-centric frame good and balanced, prefer `keep_object_balance`;
- если depth читается особенно хорошо, prefer `keep_depth_readability`;
- если нет одной dominant strength, materialize `keep_frame_as_is`;
- positive path never invents corrective subtext.

## Explainability requirements

Для каждой tip обязана существовать полная цепочка:

1. `observation`
   - `snapshot.*`
   - `semantics.*`
   - optional `neural.*` only as bounded evidence from `PR-H02/H06/H09`
2. `interpretation`
   - backing `FrameIssue` или `FrameStrength`
   - plus deterministic selector rationale if needed
3. `recommendation`
   - planner action(s)
   - semantic tip materialization

Нормативные правила:
- `SemanticTipType` не является новым verdict;
- `TraceLink(kind: action)` всегда резолвится к planner/runtime action ids, а semantic tip лишь materialize-ит screen wording;
- neural evidence никогда не invent-ит tip ids, entity labels или actions вне этого документа.

## Golden examples

### Portrait

1. **Dark background, poor separation**
   - issue: `subject_not_prominent_enough`
   - problem: `weak_subject_background_separation`
   - tip: `add_depth_by_moving_subject_from_background`
   - live: `Отодвинь героя от фона: силуэт сливается.`

2. **Overexposed background behind head**
   - issue: `background_competes_with_subject`
   - problem: `bright_background_pull`
   - tip: `remove_bright_spot_behind_subject`
   - live: `Убери яркое пятно сзади: фон спорит с лицом.`

3. **Wrong camera height**
   - issue: `subject_too_close_to_edge`
   - problem: `camera_height_mismatch`
   - tip: `lower_camera_for_subject`
   - live: `Опусти камеру ниже: ракурс сверху сплющивает лицо.`

4. **Distracting prop near face contour**
   - issue: `background_competes_with_subject`
   - problem: `face_contour_occlusion`
   - tip: `remove_object_from_face_contour`
   - live: `Убери вазу у лица: контур героя ломается.`

### Dialogue

5. **Missing look space**
   - issue: `insufficient_look_space`
   - tip: `create_look_space_right`
   - live: `Смести камеру правее: по взгляду мало воздуха.`

6. **No clear focus between two people**
   - issue: `scene_has_no_clear_focus`
   - problem: `unclear_focus_hierarchy`
   - tip: `clarify_main_subject_focus`
   - live: `Выдели главного героя: сейчас фокус сцены размыт.`

7. **Background passerby blocks frame transiently**
   - issue: `frame_visually_overloaded`
   - problem: `timing_blocker_in_frame`
   - tip: `wait_for_background_clearance`
   - live: `Подожди секунду: фон скоро очистится.`

### Object-centric

8. **Flower too close to edge**
   - issue: `subject_too_close_to_edge`
   - problem: `object_edge_pressure`
   - target label: `цветок`
   - tip: `move_object_off_left_edge`
   - live: `Сдвинь цветок правее: предмет зажат у края.`

9. **Object competes with another object**
   - issue: `background_competes_with_subject`
   - problem: `object_conflicts_with_subject`
   - target label: `предмет`
   - secondary label: `яркий объект на фоне`
   - tip: `remove_distracting_prop`
   - live: `Убери лишний предмет: он спорит с главным объектом.`

10. **Flat product shot**
   - issue: `subject_not_prominent_enough`
   - problem: `flat_depth`
   - tip: `add_depth_by_moving_object_forward`
   - pause: `Предмет читается слишком плоско. Подвинь объект чуть вперед относительно фона. Тогда слои кадра станут заметнее.`

11. **Object fights another prop**
   - issue: `background_competes_with_subject`
   - problem: `object_conflicts_with_subject`
   - tip: `move_object_back_for_balance`
   - pause: `Предмет спорит с другим объектом. Отодвинь его чуть назад, чтобы главный объект читался спокойнее.`

12. **Prop layout breaks balance**
   - issue: `background_competes_with_subject`
   - problem: `prop_breaks_balance`
   - tip: `rebalance_prop_layout`
   - pause: `Композицию ломает расположение реквизита. Переставь предметы так, чтобы вес кадра распределился спокойнее. Тогда предметный кадр станет устойчивее.`

### Good frames

13. **Good portrait**
   - strengths: `good_subject_isolation`, `good_light_emphasis`
   - tip: `keep_subject_separation`

14. **Good object shot**
   - strengths: `balanced_composition_for_scene`
   - tip: `keep_object_balance`

## Test plan for `implement`

Минимальный suite:
- coverage test: каждая `IssueTypeV1` materialize-ит минимум одну corrective tip;
- coverage test: каждая `StrengthTypeV1` materialize-ит минимум одну positive tip;
- coverage test: camera / light / subject staging / object staging / timing families all have at least one `v1` tip;
- entity test: person-centric label never invents proper names;
- entity test: grounded object label outside allowed vocabulary degrades to generic label;
- entity test: missing `targetEntityRef` still allows safe generic copy when allowed;
- relation test: `remove_object_from_face_contour` requires `secondaryEntityRef` or degrades to `remove_distracting_prop`;
- selector test: `front_light_deficit` chooses `turn_subject_toward_light` vs `add_front_fill_on_subject` deterministically;
- selector test: transient blocker yields `wait_for_background_clearance`, stable clutter yields `simplify_busy_background`;
- selector test: object-centric edge pressure yields object move tip, not person framing tip;
- merge test: edge pressure + look-space same side -> one merged tip;
- merge test: multi-edge tight framing -> `step_back_for_breathing_room`;
- suppression test: unsupported pause-only tips never appear in `live`;
- trace linkage test: every materialized tip has valid recommendation root;
- copy test: all labels and phrases come from closed template vocabulary;
- good-path test: `keep_object_balance`, `keep_depth_readability`, `keep_frame_as_is` materialize deterministically.

## Why this is enough for `v1`

Этого достаточно для первой версии screen tips, потому что:
- пользователь уже получает конкретные instructions про камеру, свет, героя, предметы и timing;
- object-centric и portrait/dialogue flows закрыты без расширения critique taxonomy;
- entity-aware layer уже bounded и safe for `PR-S02`, `PR-S04`, `PR-S05`;
- deferred cases (`rim light`, `side light`, `cleaner profile`) важны, но не блокируют базовый UX semantic screen tips.

## Residual gaps after `design verify`

Осознанно остаются:
- нет полного runtime object vocabulary beyond `GroundedObjectDisplayLabelV1`;
- `turn_subject_for_cleaner_profile`, `add_rim_light`, `add_side_light` deferred;
- для некоторых object moves transport mapping many-to-one поверх current `ActionTypeV1`, поэтому implement phase должна аккуратно ввести contract-safe mapper/types without mutating planner contract;
- deterministic transient/stable blocker detection для `wait_for_background_clearance` еще needs implementation evidence rule in future code/tests.

## Definition of done for `design verify`

`PR-S01` готов к implement, если:
- по этому документу можно реализовать entity-aware semantic screen tips без домысливания;
- planner может безопасно materialize-ить тексты вида `сдвинь цветок правее`, `убери вазу из-за лица`, `смести героя левее`, `отодвинь героя от фона`, `оставь кадр как есть`;
- low-confidence entity grounding корректно деградирует до generic labels;
- catalog покрывает camera, light, subject staging, object/prop staging и timing, а не только framing/light.
