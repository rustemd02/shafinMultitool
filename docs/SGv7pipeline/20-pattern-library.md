# 20. Pattern Library For SG v7

## Цель

Зафиксировать pattern library, которую deterministic graph generator может использовать как прямой вход для построения `CIR`-записей без дополнительных архитектурных решений.

Этот документ закрывает `Track 2` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md) и служит source-of-truth для:
- списка pattern classes
- разделения `core` / `hard`
- target distribution
- failure coverage
- canonical examples
- generator-facing invariants

## Scope

Pattern library для `SG v7` не пытается покрыть "все возможные сцены".
Она покрывает именно те semantic skeletons, которые:
- критичны для runtime quality
- соответствуют capacity budget `qwen 1.5B`
- программно сериализуемы в canonical `CIR`
- закрывают реальные провалы из [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)

Executable implementation lives in:
- [pattern_library/registry.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/pattern_library/registry.py)
- [pattern_library/tests/test_pattern_library.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/pattern_library/tests/test_pattern_library.py)

## Design Principles

- `pattern class` описывает semantic skeleton, а не surface wording.
- Один `pattern class` должен однозначно задавать actors, objects, beat phases и required semantics.
- `hard`-bucket нужен для stress coverage, но не должен становиться новой нормой для train mix.
- Core library должна в первую очередь покрывать high-frequency cinema chunks: `enter`, `open`, `pick_up`, `put_down`, short dialogue follow-up.
- Marked-object cases по умолчанию проектируются как `required_marked`, а не как "обычный объект, который потом как-нибудь сматчится".
- `first/second` считаются структурной semantics, а не стилистической вариацией.
- Unsupported actions всегда должны иметь явный path в `described_action`.
- 3-beat scenes допустимы и нужны, но в основном живут в `hard`.

## Canonical Naming Policy

Canonical names ниже являются source-of-truth для:
- `pattern_name` в `CIR`
- registry keys
- fixtures
- coverage reports

Правило именования:
- если exact marked-object grounding является primary named focus pattern-а, в имени используется `marked_object`
- в остальных случаях допускается более общий `object`, если это лучше сохраняет устойчивое canonical name без потери смысла

Canonical naming set:
- `dialogue_only`
- `dialogue_then_put_down_object`
- `dialogue_then_small_action`
- `enter_then_put_down_object`
- `open_then_pick_up_object`
- `pick_up_then_put_down_object`
- `toward_each_other`
- `toward_each_other_then_stop_near_marked_object`
- `toward_each_other_then_pass_by_marked_object`
- `ordinal_first_second`
- `unsupported_action_described_action`
- `stop_near_marked_object_then_first_described_action`
- `toward_each_other_then_pass_by_object_then_second_runs`
- `same_type_two_marked_objects`

## Registry Shape

Будущая pattern registry implementation должна хранить для каждого entry минимум такие поля:

- `pattern_name`
- `pattern_family`
- `difficulty_bucket`
- `default_complexity_class`
- `allowed_source_variant_keys`
- `required_actor_count`
- `required_object_mode`
- `beat_blueprint`
- `required_semantics`
- `forbidden_collapses`
- `semantic_tags`
- `canonical_source_template`

Рекомендуемый `required_object_mode`:
- `none`
- `required_generic`
- `optional_generic`
- `required_marked`
- `required_same_type_marked_pair`

Рекомендуемые `source_variant_key` должны совпадать с `CIR` enum из [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md):
- `base`
- `ordinal_stress`
- `morphology_stress`
- `same_type_marker_stress`
- `dialogue_mix`

`beat_blueprint` хранится как ordered list deterministic phase codes уровня registry.
Для `SG v7` использовать только этот набор:
- `dialogue_exchange`
- `single_small_followup_action`
- `single_action`
- `mutual_walk_toward_each_other`
- `dual_stop_near_marked_object`
- `dual_pass_by_marked_object`
- `ordinal_focus_action`
- `single_described_action`
- `first_actor_described_action`
- `second_actor_runs`
- `same_type_marker_resolution`
- `open_object`
- `pickup_object`
- `putdown_object`

Generator обязан детерминированно маппить эти registry-level codes в `CIR`:
- `dual_stop_near_marked_object` -> `stop_near_object`
- `dual_pass_by_marked_object` -> `pass_by_object`

## Bucket Policy

### Core

`Core` patterns:
- должны быть в основном `S/M`
- обычно имеют `1-2 beats`
- учат модель основному runtime behavior
- не должны перегружать target лишней combinatorial complexity

### Hard

`Hard` patterns:
- покрывают реальные runtime failures
- чаще всего имеют `3 beats`
- могут комбинировать motion + object grounding + ordinal shift + described action
- должны оставаться minority bucket

Рекомендуемый bucket split для default dataset build:
- `core`: 82%
- `hard`: 18%

## Semantic Pattern Classes

### Core Patterns

| Pattern | Family | Default share | Complexity | Beats | Main coverage |
| --- | --- | ---: | --- | ---: | --- |
| `dialogue_only` | dialogue | 8% | `S` | 1 | stable talk-only baseline, no invented objects/actions |
| `dialogue_then_put_down_object` | dialogue_object_followup | 5% | `M` | 2 | dialogue-conditioned object placement, common "say -> set down item" chunk |
| `dialogue_then_small_action` | dialogue_followup | 8% | `S` | 2 | preserves chronology after dialogue, avoids beat collapse into pure talk |
| `enter_then_put_down_object` | object_placement | 4% | `M` | 2 | frequent staging chunk: actor enters with item and places it |
| `open_then_pick_up_object` | container_interaction | 5% | `M` | 2 | cabinet/shelf interaction with explicit `open -> pick_up` chronology |
| `ordinal_first_second` | ordinal_binding | 10% | `S/M` | 1-2 | deterministic `first/second -> actor_1/actor_2` |
| `pick_up_then_put_down_object` | object_placement | 6% | `M` | 2 | pick/place object handling without collapsing to one generic action |
| `toward_each_other` | motion_symmetry | 9% | `S` | 1 | symmetric movement with `direction=toward_each_other` |
| `toward_each_other_then_stop_near_marked_object` | motion_object_grounding | 10% | `M` | 2 | stop near marked object without losing object grounding |
| `toward_each_other_then_pass_by_marked_object` | motion_object_grounding | 8% | `M` | 2 | pass-by semantics near marked object |
| `unsupported_action_described_action` | unsupported_action | 9% | `S` | 1 | preserves non-runtime action via `described_action` |

### Hard Patterns

| Pattern | Family | Default share | Complexity | Beats | Main coverage |
| --- | --- | ---: | --- | ---: | --- |
| `stop_near_marked_object_then_first_described_action` | composed_marked_action | 7% | `M` | 3 | stop near object + ordinal binding + unsupported action preservation |
| `toward_each_other_then_pass_by_object_then_second_runs` | role_shift_motion | 7% | `M` | 3 | role shift in final beat, no collapse to identical walks |
| `same_type_two_marked_objects` | marker_disambiguation | 4% | `M` | 1-2 | exact id preservation for same-type markers |

## Target Distribution By Semantic Family

Это второй, более устойчивый к future refactor, взгляд на distribution.

| Family | Includes | Target share |
| --- | --- | ---: |
| `dialogue` | `dialogue_only`, `dialogue_then_small_action`, `dialogue_then_put_down_object` | 21% |
| `object_placement` | `enter_then_put_down_object`, `pick_up_then_put_down_object` | 10% |
| `container_interaction` | `open_then_pick_up_object` | 5% |
| `motion_symmetry` | `toward_each_other` | 9% |
| `motion_object_grounding` | `toward_each_other_then_stop_near_marked_object`, `toward_each_other_then_pass_by_marked_object` | 18% |
| `ordinal_binding` | `ordinal_first_second` | 10% |
| `unsupported_action` | `unsupported_action_described_action` | 9% |
| `composed_marked_action` | `stop_near_marked_object_then_first_described_action` | 7% |
| `role_shift_motion` | `toward_each_other_then_pass_by_object_then_second_runs` | 7% |
| `marker_disambiguation` | `same_type_two_marked_objects` | 4% |

## Variant Overlay Policy

`Pattern class` и `source_variant_key` не одно и то же.
Pattern задаёт semantics skeleton, а variant overlay задаёт controlled surface stress.

Рекомендуемая политика:
- `base` обязателен для всех patterns, кроме `same_type_two_marked_objects`
- `ordinal_stress` разрешён только для двух-actor patterns, где ordinal semantics является отдельным surface stress, а не уже входит в сам pattern contract
- `morphology_stress` разрешён только для patterns с `required_marked`
- `dialogue_mix` разрешён только для dialogue families
- `same_type_marker_stress` используется только для `same_type_two_marked_objects`

Рекомендуемые default доли overlay среди eligible samples:
- `base`: 60%
- `ordinal_stress`: 20%
- `morphology_stress`: 15%
- `dialogue_mix`: 5%

Отдельное правило:
- для `same_type_two_marked_objects` всегда использовать `same_type_marker_stress`, а не обычный `base`

## Canonical Pattern Specs

### `dialogue_only`

Canonical source:
`АННА: Я уже отправила письмо. БОРИС: Тогда покажи вложение.`

Required semantics:
- 2 actors
- 1 beat
- только `talk`
- no invented object grounding

Failure modes covered:
- acceptability drift with semantically empty filler actions
- invented objects in talk-only prompts

### `dialogue_then_small_action`

Canonical source:
`АННА: Я уже отправила письмо. БОРИС: Тогда покажи вложение. Анна поворачивается к Борису.`

Required semantics:
- 2 beats
- first beat is dialogue exchange
- second beat is one small runtime-supported action

Failure modes covered:
- chronology collapse after dialogue
- tendency to serialize everything as one talk beat

### `dialogue_then_put_down_object`

Canonical source:
`АННА: Положи папку сюда, чтобы не потерять. Борис кладёт папку на стол.`

Required semantics:
- 2 beats
- first beat is dialogue instruction or request
- second beat is explicit `put_down` with preserved held object
- scene must keep target surface object

Failure modes covered:
- dialogue scenes collapsing into talk-only output
- object placement being rewritten as generic `stand` or `approach`

### `enter_then_put_down_object`

Canonical source:
`Актёр входит и ставит сумку на стол.`

Required semantics:
- 1 actor
- 2 beats: `enter -> put_down`
- held object must survive across beats
- target surface stays explicit

Failure modes covered:
- entry-stage choreography being flattened into one vague action
- loss of object continuity between beats

### `open_then_pick_up_object`

Canonical source:
`Актёр открывает шкаф и берёт папку.`

Required semantics:
- 1 actor
- 2 beats: `open -> pick_up`
- container object and picked object both remain explicit
- graph preserves `inside` relation

Failure modes covered:
- loss of container chronology
- pick-up emitted without opening the container first

### `pick_up_then_put_down_object`

Canonical source:
`Актёр берёт кружку и ставит на стол.`

Required semantics:
- 1 actor
- 2 beats: `pick_up -> put_down`
- same held object must flow through both beats
- target surface must remain grounded

Failure modes covered:
- object handling collapsing into one undifferentiated action
- dropped `holding_object` continuity

### `toward_each_other`

Canonical source:
`2 актёра идут навстречу друг другу.`

Required semantics:
- 2 actors
- symmetric movement
- `direction="toward_each_other"` on both sides

Failure modes covered:
- loss of symmetric motion semantics
- asymmetry where only one actor moves

### `toward_each_other_then_stop_near_marked_object`

Canonical source:
`2 актёра идут навстречу друг другу и останавливаются около ноутбука.`

Required semantics:
- 2 beats: movement -> stop near object
- marked object id must survive end-to-end
- canonical base blueprint always uses explicit `stop` actions in beat 2; `approach` is not an alternative inside this pattern
- no collapse into one beat

Failure modes covered:
- Example 2 from runtime failures
- morphology-sensitive marked object loss
- beat collapse around stop-near-object

### `toward_each_other_then_pass_by_marked_object`

Canonical source:
`2 актёра идут навстречу друг другу и проходят мимо ноутбука.`

Required semantics:
- 2 beats: movement -> pass_by object
- `pass_by` must target marked object
- object grounding survives the pass-by phase

Failure modes covered:
- pass-by semantics being rewritten as generic `walk`
- marked object loss during motion

### `ordinal_first_second`

Canonical source:
`Первый подходит к ноутбуку, второй смотрит на него.`

Required semantics:
- explicit ordinal map
- exactly 2 actors
- base profile uses 1 beat and 1 generic target object
- `first -> actor_1`, `second -> actor_2`
- no actor swap across serialization

Failure modes covered:
- `first/second` confusion
- actor role drift between beats

### `unsupported_action_described_action`

Canonical source:
`Актёр кивает у двери.`

Required semantics:
- 1 actor
- 1 required generic object (`door`)
- 1 beat
- unsupported surface action maps to `described_action`
- fallback/source text must preserve the action
- no ordinal semantics inside this pattern
- no downgrade to `talk`, `stand` or silent deletion

Failure modes covered:
- unsupported action loss
- minimal-valid-json fallback

### `stop_near_marked_object_then_first_described_action`

Canonical source:
`2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить сигарету.`

Required semantics:
- 3 beats: movement -> stop near object -> first actor described action
- exact marked object grounding
- explicit ordinal binding in terminal beat

Failure modes covered:
- Example 1 from runtime failures
- beat collapse
- unsupported action loss
- ordinal loss under multi-beat pressure

### `toward_each_other_then_pass_by_object_then_second_runs`

Canonical source:
`2 актёра идут навстречу друг другу, проходят мимо ноутбука, второй начинает бежать.`

Required semantics:
- 3 beats: movement -> pass_by -> actor_2 runs
- final beat changes only actor_2 behavior
- no rewrite where both actors stay in identical walk state

Failure modes covered:
- Example 3 from runtime failures
- role shift loss
- chronology simplification

### `same_type_two_marked_objects`

Canonical source:
`Первый подходит к правому стулу, второй остаётся у левого.`

Required semantics:
- 2 marked objects with same `type`
- exact target id must match source intent
- no resolution by type-only fallback

Failure modes covered:
- Example 4 from runtime failures
- marker identity collapse for same-type objects

## Coverage Matrix

| Pattern | Covered runtime failures | Difficulty |
| --- | --- | --- |
| `dialogue_only` | acceptability drift, invented semantic filler | `core` |
| `dialogue_then_put_down_object` | dialogue-to-object chronology loss, object placement collapse | `core` |
| `dialogue_then_small_action` | chronology loss after dialogue, beat flattening | `core` |
| `enter_then_put_down_object` | entry-stage flattening, held-object continuity loss | `core` |
| `open_then_pick_up_object` | skipped open step, container/object grounding loss | `core` |
| `pick_up_then_put_down_object` | object-handling collapse, missing hold continuity | `core` |
| `toward_each_other` | loss of symmetric motion | `core` |
| `toward_each_other_then_stop_near_marked_object` | beat collapse, marked object loss, morphology sensitivity | `core` |
| `toward_each_other_then_pass_by_marked_object` | `pass_by` rewritten as generic motion, object grounding loss | `core` |
| `ordinal_first_second` | ordinal confusion, actor swap | `core` |
| `unsupported_action_described_action` | unsupported action disappearance, fallback-to-talk | `core` |
| `stop_near_marked_object_then_first_described_action` | Example 1 full stack failure | `hard` |
| `toward_each_other_then_pass_by_object_then_second_runs` | Example 3 full stack failure | `hard` |
| `same_type_two_marked_objects` | Example 4 marker identity failure | `hard` |

## Cross-Pattern Anti-Collapse Policy

Example 5 from runtime failures не считается owning-responsibility одного отдельного pattern class.
Он покрывается комбинацией:
- pattern library
- cross-pattern semantic density invariants
- validator/eval policy

Обязательные cross-pattern invariants:
- любой non-dialogue pattern обязан содержать хотя бы одно non-talk action
- любой pattern с `required_generic`, `required_marked` или `required_same_type_marked_pair` обязан иметь хотя бы одну action или relation binding к объекту
- любой multi-beat pattern обязан менять semantic phase между соседними beats
- `described_action` pattern не может деградировать до `stand`, `talk` или empty beat

Следствие:
- pattern library частично снижает risk Example 5
- окончательное закрытие Example 5 лежит также на validator stack и eval harness

## Generator Registry Appendix

Это generator-ready слой, которого достаточно, чтобы implementation-агент не домысливал structure каждого pattern-а.

| Pattern | Actors | Object mode | Allowed variants | Beat blueprint | Deterministic action skeleton |
| --- | ---: | --- | --- | --- | --- |
| `dialogue_only` | 2 | `none` | `base`, `dialogue_mix` | `dialogue_exchange` | `beat_1`: `talk(actor_1->actor_2)` + `talk(actor_2->actor_1)` |
| `dialogue_then_put_down_object` | 2 | `required_generic` | `base`, `dialogue_mix` | `dialogue_exchange`, `putdown_object` | `beat_1`: one actor gives spoken instruction; `beat_2`: other actor `put_down(..., holding_object=item)` onto target surface |
| `dialogue_then_small_action` | 2 | `none` | `base`, `dialogue_mix` | `dialogue_exchange`, `single_small_followup_action` | `beat_1`: dialogue pair; `beat_2`: one runtime action by one actor targeting the other actor |
| `enter_then_put_down_object` | 1 | `required_generic` | `base` | `single_action`, `putdown_object` | `beat_1`: `enter(actor_1)`; `beat_2`: `put_down(actor_1->surface, holding_object=item)` |
| `open_then_pick_up_object` | 1 | `required_generic` | `base` | `open_object`, `pickup_object` | `beat_1`: `open(actor_1->container)`; `beat_2`: `pick_up(actor_1->item)` with preserved `inside(item, container)` relation |
| `toward_each_other` | 2 | `none` | `base`, `ordinal_stress` | `mutual_walk_toward_each_other` | `beat_1`: `walk(actor_1->actor_2)` + `walk(actor_2->actor_1)` with `direction=toward_each_other` |
| `toward_each_other_then_stop_near_marked_object` | 2 | `required_marked` | `base`, `ordinal_stress`, `morphology_stress` | `mutual_walk_toward_each_other`, `dual_stop_near_marked_object` | `beat_1`: symmetric walk; `beat_2`: `stop(actor_1->marked)` + `stop(actor_2->marked)` |
| `toward_each_other_then_pass_by_marked_object` | 2 | `required_marked` | `base`, `ordinal_stress`, `morphology_stress` | `mutual_walk_toward_each_other`, `dual_pass_by_marked_object` | `beat_1`: symmetric walk; `beat_2`: `pass_by(actor_1->marked)` + `pass_by(actor_2->marked)` |
| `ordinal_first_second` | 2 | `required_generic` | `base` | `ordinal_focus_action` | `beat_1`: primary action by `actor_1`; secondary reactive action by `actor_2`; `reference_bindings.ordinal_map` required |
| `pick_up_then_put_down_object` | 1 | `required_generic` | `base` | `pickup_object`, `putdown_object` | `beat_1`: `pick_up(actor_1->item)`; `beat_2`: `put_down(actor_1->surface, holding_object=item)` |
| `unsupported_action_described_action` | 1 | `required_generic` | `base` | `single_described_action` | `beat_1`: `described_action(actor_1->object_1)` with preserved source/fallback text |
| `stop_near_marked_object_then_first_described_action` | 2 | `required_marked` | `base`, `morphology_stress` | `mutual_walk_toward_each_other`, `dual_stop_near_marked_object`, `first_actor_described_action` | `beat_1`: symmetric walk; `beat_2`: dual stop near marked object; `beat_3`: `described_action(actor_1)` |
| `toward_each_other_then_pass_by_object_then_second_runs` | 2 | `required_marked` | `base`, `morphology_stress` | `mutual_walk_toward_each_other`, `dual_pass_by_marked_object`, `second_actor_runs` | `beat_1`: symmetric walk; `beat_2`: dual pass-by marked object; `beat_3`: `run(actor_2)` only |
| `same_type_two_marked_objects` | 2 | `required_same_type_marked_pair` | `same_type_marker_stress` | `same_type_marker_resolution` | `beat_1`: one actor targets exact marked object A or B; other actor stays/stands; exact marker id is mandatory |

Дополнительные per-pattern invariants:
- `dialogue_only`: objects array must stay empty in base build.
- `dialogue_then_put_down_object`: final beat must target a surface object and carry `holding_object`.
- `dialogue_then_small_action`: second beat cannot introduce marked objects.
- `enter_then_put_down_object`: `enter` cannot be merged into `approach`.
- `open_then_pick_up_object`: picked object must remain linked to the opened container.
- `ordinal_first_second`: exactly two actors, and both ordinals must be recoverable from source.
- `pick_up_then_put_down_object`: beat 2 must reuse the same held object from beat 1.
- `unsupported_action_described_action`: no `actor_2`, no ordinal tokens, no dialogue.
- `same_type_two_marked_objects`: exactly two marked objects of one runtime type and two distinct ids.

## Generator-Facing Invariants

- У каждого pattern есть ровно один canonical beat blueprint.
- `beat_count` и `phase order` должны быть заданы pattern-ом, а не вычисляться эвристикой из surface text.
- `ordinal_first_second` и composed patterns обязаны явно заполнять `reference_bindings.ordinal_map`.
- Любой pattern с marked object обязан заполнять `marked_object_ids` и `alias_to_object_id`.
- `same_type_two_marked_objects` не может деградировать до одного объекта даже при seed variation.
- `unsupported_action_described_action` и composed patterns обязаны ставить `must_preserve_in_source=true`.
- `hard` pattern разрешено комбинировать не более двух stress dimensions сверх базового skeleton.
- Один generated record не должен одновременно быть `same_type_two_marked_objects` и `dialogue_only`; pattern classes здесь взаимоисключающие.

## What The Graph Generator Should Implement Next

Минимальный handoff для `Track 3`:

1. Завести registry с 14 pattern entries из этого документа.
2. Для каждого pattern описать seedable enumerator, который возвращает deterministic `CIR-ready` blueprint.
3. Реализовать overlay application layer для `ordinal_stress`, `morphology_stress` и `dialogue_mix`.
4. Ввести distribution config, где pattern weights и overlay weights живут отдельно.
5. Добавить smoke fixtures по одному canonical sample на каждый pattern.

## Test Plan For Future Implementation

- unit test: каждый registry entry проходит schema-level self-check
- unit test: каждый pattern выдаёт ровно допустимый `difficulty_bucket`
- unit test: eligible overlays не выходят за разрешённый список для pattern-а
- unit test: `same_type_two_marked_objects` всегда содержит 2 distinct marked ids одного типа
- unit test: `stop_near_marked_object_then_first_described_action` всегда даёт `beat_count=3`
- unit test: `toward_each_other_then_pass_by_object_then_second_runs` всегда завершает `run` у `actor_2`
- smoke test: генерация по фиксированным seed даёт стабильные `sample_id`
- smoke test: coverage report подтверждает, что все critical runtime failures имеют хотя бы один owning pattern

## Open Questions

- Нужен ли отдельный hard-pattern для `dialogue + marked object + ordinal` или это лучше оставить overlay-комбинацией после появления eval-сигналов.
- Стоит ли в будущем разделить `unsupported_action_described_action` на `single_actor` и `two_actor` variants, если critic покажет систематическую разницу в recoverability.
- Если runtime логов станет больше, возможно появится новый hard family для chained object handoff; пока в library его рано делать обязательным.
