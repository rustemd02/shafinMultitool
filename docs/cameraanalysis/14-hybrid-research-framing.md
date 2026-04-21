# 14. Hybrid Research Framing (PR-H01)

Статус: design spec (source-of-truth)

Дата: 2026-04-21

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md)
- [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)

## Цель

Зафиксировать research framing для hybrid stage так, чтобы было однозначно понятно:
- зачем нужен следующий этап после deterministic `v1`;
- какую роль сохраняет deterministic core;
- что именно разрешено усиливать neural layer-ом;
- какие гипотезы и риски проверяются в thesis/demo контуре;
- какие границы нельзя нарушать ради качества.

`PR-H01` не вводит модель, датасет или fusion policy. Он фиксирует thesis и scope boundaries, от которых затем зависят `PR-H02 ... PR-H16`.

## Thesis-ready Summary

Hybrid stage нужен не для замены explainable camera analysis на black-box aesthetic judge, а для усиления deterministic cinematic critique интерпретируемым neural evidence там, где rule-based сигналы системно слабы: мягкие lighting cues, depth separation, holistic harmony, borderline cases и confidence calibration. Целевая архитектура остается mobile-first, offline-first и explainable-by-construction: deterministic core продолжает быть source-of-truth для `issues`, `actions`, `trace` и fallback UX, а neural layer поставляет только структурированные evidence factors с измеримым вкладом в `pause` и ограниченным, строго guarded использованием в `live`.

## Почему deterministic `v1` недостаточен

Deterministic pipeline уже закрывает:
- geometry-driven composition checks;
- subject placement and readability;
- scene-aware rule application;
- explainable issue/action planning;
- стабильный baseline для `live` и `pause`.

Но даже хороший deterministic core будет ограничен в зонах, где полезный сигнал:
- мягкий, распределенный и плохо формализуемый простыми порогами;
- зависит от глобального визуального паттерна, а не от одной геометрической метрики;
- проявляется как "borderline quality prior", а не как бинарное нарушение;
- требует confidence calibration при конфликтующих evidence sources.

Следовательно, hybrid stage нужен не для переписывания core-логики, а для controlled augmentation поверх уже зафиксированных contracts.

## Core Thesis

Целевая исследовательская формула для ближайшего hybrid stage:

`deterministic cinematic grammar + interpretable neural evidence`

Долгосрочное расширение этой формулы:

`deterministic cinematic grammar + interpretable neural evidence + optional gated offloading`

Из нее следуют 5 обязательных утверждений:

1. Deterministic grammar остается source-of-truth для `issue/action/verdict` semantics.
2. Neural model не генерирует свободный совет как главный output, а предсказывает структурированные evidence axes.
3. Любой полезный вклад neural layer должен быть объясним через mapping `evidence -> fusion -> issue/action/trace`.
4. Mobile runtime не должен становиться зависимым от сети, heavy model или remote judge.
5. Hybrid success измеряется не только ростом "quality score", но и сохранением explainability, fallback safety и mobile viability.

Важно для `PR-H01`:
- scope freeze фиксирует только локальный hybrid baseline;
- offloading признается допустимым только как более позднее optional extension из `PR-H12+`, а не как часть initial hybrid core.

## Architectural Position

### Deterministic layer обязателен для

- `FrameFeatureSnapshot` и fast feature aggregation;
- `SceneSemanticsReport`;
- issue/strength taxonomy и их пороговой логики;
- `RecommendationPlan` и final action ranking;
- базового explainability trace;
- baseline `live` и `pause` UX при любом degraded path;
- safety/fallback policy и final release gate.

### Neural layer разрешен для

- evidence heads с интерпретируемыми axis-ами;
- holistic priors в спорных cinematic cases;
- soft quality cues, плохо покрываемых simple rules;
- reranking и confidence calibration в пределах разрешенной fusion policy;
- улучшения `pause`-анализа раньше, чем `live`;
- optional support для dataset mining и hard-case clustering.

### Neural layer запрещено использовать как

- end-to-end black-box judge, который сразу выдает итоговый совет;
- источник истины для новых issue types вне frozen taxonomy;
- единственный путь для useful `pause` verdict;
- обязательную зависимость `live` path;
- замену explainability trace свободным текстом;
- оправдание для снятия deterministic fallback.

## Responsibility Split

### Deterministic responsibilities

- hard geometry: horizon, tilt, headroom, lead room, edge pressure;
- explicit subject placement and framing balance;
- obvious clutter and technical-failure heuristics;
- scene-type-aware rule activation;
- stable `issue -> action` planning;
- contract-safe trace assembly;
- conservative default behavior при low confidence или unavailable neural path.

### Neural responsibilities

- soft evidence о visual harmony, production-value-like coherence и holistic composition prior;
- lighting quality как graded signal, а не только crude exposure heuristic;
- depth / tonal separation cues;
- subject prominence priors в ambiguous scenes;
- confidence calibration для borderline critique decisions;
- reranking между несколькими допустимыми structured candidates.

### Shared but with asymmetric ownership

- `subject readability`:
  - deterministic owns base measurement;
  - neural may add soft confidence modifier.
- `background competition`:
  - deterministic owns obvious clutter rules;
  - neural may estimate residual distraction intensity.
- `pause explanation quality`:
  - deterministic owns semantic correctness;
  - neural may improve evidence richness только через bounded structured outputs или controlled text refinement.

## Scope Boundaries

### В scope hybrid stage

- усиление existing explainable pipeline, а не второй параллельный стек;
- evidence taxonomy, dataset rubric, compact mobile model, fusion, eval и optional offloading;
- сначала `pause`, затем осторожный `live`;
- measurable ablations: `deterministic-only` vs `hybrid`.

### Вне scope hybrid stage

- полная замена `FrameCritiqueEngine` нейросетью;
- free-form LLM critique вместо structured contracts;
- mandatory cloud inference;
- расширение жанров далеко за `cinematic framing v1`;
- попытка решать "общую художественную ценность" без связи с actionable framing critique;
- изменение frozen domain contracts без отдельного обоснованного PR.

### PR-H01 boundary

Этот PR фиксирует только:
- thesis;
- role split;
- target hypotheses;
- risk register;
- explicit research boundaries.

Этот PR не фиксирует:
- конкретную final taxonomy of evidence heads;
- dataset schema;
- model backbone;
- loss design;
- runtime fusion formulas.
- offloading contract, trigger rules или payload schema.

## Testable Hypotheses

Ниже перечислены гипотезы, которые должны быть проверяемы в `PR-H02 ... PR-H16`.

### H1. Structured neural evidence improves ambiguous critique quality

Если добавить интерпретируемые evidence heads поверх deterministic core, то на ambiguous cinematic frames система точнее различает:
- `good but subtle`;
- `borderline`;
- `needs_fix`.

Проверяемость:
- сравнение `deterministic-only` vs `hybrid` на curated eval buckets;
- рост по verdict calibration и issue precision без роста hallucinated issues.

### H2. Hybrid gains are strongest in `pause`, not in `live`

Основная практическая польза neural layer сначала проявится в `pause`, где допустим richer pass и больше latency budget.

Проверяемость:
- отдельные метрики для `pause critique usefulness`;
- отсутствие обязательного выигрыша в `live` как критерий допустимости первого релиза hybrid stage.

### H3. Interpretable evidence is enough; black-box text is not required

Большая часть полезного вклада neural stage достижима через structured evidence heads и fusion, без превращения модели в end-to-end text judge.

Проверяемость:
- ablation `structured evidence only` vs `free-form judge proxy`;
- сравнение explanation faithfulness и controllability.

### H4. Mobile-capable on-device model can produce useful evidence within budget

Compact model может дать practically useful gains без нарушения latency/thermal budget, если outputs ограничены structured evidence и cadence зависит от mode.

Проверяемость:
- замеры latency, memory, thermal pressure;
- сравнение `pause-only neural` и `pause + guarded live`.

### H5. Hybrid layer can improve calibration without mutating core taxonomy

Neural evidence должен повышать confidence calibration и reranking quality, не создавая новые непредусмотренные issue classes.

Проверяемость:
- paired compare на frozen issue/action taxonomy;
- analysis low-confidence bucket и conflict bucket.

### H6. Runtime hard cases are essential for continued gains

Static curated dataset сам по себе не покроет реальные hybrid failure modes; runtime hard-case loop обязателен для устойчивого улучшения.

Проверяемость:
- отдельный bucket runtime disagreements;
- measurable uplift после добавления hard cases в eval/data loop.

## Main Risks

### R1. Domain gap masquerading as intelligence

Модель может хорошо учиться на photo-aesthetic priors и плохо переноситься на mobile cinematic coaching.

Почему важно:
- легко получить красивый score без actionable critique.

Следствие:
- `AVA` и похожие датасеты допустимы только как auxiliary/pretraining layer.

### R2. Evidence heads become pseudo-explainable labels

Есть риск назвать outputs "evidence", но по факту не иметь устойчивой интерпретации и воспроизводимого mapping к issues/actions.

Следствие:
- `PR-H02` обязан зафиксировать строгую taxonomy, confidence semantics и examples.

### R3. Fusion silently overrides deterministic logic

Даже при structured outputs плохо спроектированный fusion layer может фактически превратить систему в black-box reranker.

Следствие:
- fusion должен быть explainable, bounded и eval-driven.

### R4. Dataset labels are too subjective

Cinematic framing допускает разные вкусы, поэтому без rubric и adjudication labels будут шумными и спорными.

Следствие:
- `PR-H03` обязан задавать rubric, annotator guide и disagreement protocol.

### R5. Mobile budget erosion

Даже полезная модель бесполезна, если она перегревает устройство, вносит лаги или ломает cadence `live`.

Следствие:
- сначала `pause-only`, затем guarded `live`, затем optional gating.

### R6. Explainability regression

Качество рекомендаций может субъективно вырасти, но traceability и user trust снизятся, если chain-of-evidence станет непрозрачной.

Следствие:
- explainability faithfulness входит в release gate наравне с quality uplift.

### R7. Scope creep into "AI does everything"

Hybrid stage легко расползается в сторону общего visual assistant, server judge, prompt engineering и несвязанных UX-экспериментов.

Следствие:
- каждый следующий PR должен усиливать одну bounded часть существующего pipeline.

### R8. Offloading undermines offline-first thesis

Remote critic может стать слишком привлекательным shortcut и незаметно заменить локальную архитектуру.

Следствие:
- offloading остается optional deep-analysis branch только после локального hybrid baseline.

## Mobile-First Policy

Hybrid stage совместим с mobile-first thesis только если соблюдаются все правила:
- baseline critique существует и полезен без neural path;
- `live` не зависит от rich neural inference;
- cadence и compute policy различаются для `live` и `pause`;
- thermal/latency degradation приводит к soft disable neural layer, а не к потере основного UX;
- размер модели, память и inference strategy рассматриваются как research constraints, а не как постфактум optimization.

Практическое следствие:
- первый полезный milestone hybrid stage должен быть `pause-only neural evidence`.

## Explainability Policy

Hybrid stage совместим с explainability-by-construction только если:
- каждый neural output принадлежит к заранее определенной evidence taxonomy;
- fusion объясним и воспроизводим;
- final `issue/action` можно связать как минимум с одним deterministic или fused evidence path;
- optional text refinement не подменяет structured basis;
- eval измеряет faithfulness, а не только human preference.

Нормативное правило:
- если компонент невозможно объяснить через contracts, examples и repeatable eval, он еще не готов для integration в main pipeline.

## What Exactly Will Be Evaluated

Hybrid stage проверяет не абстрактное "стало ли умнее", а конкретные свойства:
- better verdict calibration on ambiguous frames;
- fewer bad recommendations in borderline cinematic cases;
- better pause usefulness without breaking baseline fallback;
- preserved traceability from evidence to action;
- mobile viability on device;
- controlled gains from optional offloading over already-working local path.

## Downstream PR Guidance

Из этого документа следуют обязательные требования к следующим PR:

- `PR-H02` должен зафиксировать only-interpretable evidence taxonomy.
- `PR-H03` должен зафиксировать rubric-driven labeling, а не vague aesthetic voting.
- `PR-H04` должен ограничить роль `AVA` и явно описать domain gap.
- `PR-H05` должен выбирать mobile-capable model only under structured outputs policy.
- `PR-H06 ... PR-H11` не могут ломать deterministic contracts и fallback UX.
- `PR-H12 ... PR-H15` не могут превращать offloading в обязательную зависимость.
- `PR-H14` обязан мерить hybrid uplift вместе с explainability и mobile constraints.

## Non-Goals

- не доказывать, что neural подход всегда лучше deterministic;
- не строить один универсальный score "cinematic quality";
- не делать human-like essay explanation главным продуктовым output;
- не оптимизировать только под offline benchmark без runtime realism;
- не оправдывать регрессии explainability ради субъективно более красивых verdict texts.

## Definition of Done (design mode)

Этот design считается готовым, если:
- hybrid thesis сформулирован в одной устойчивой архитектурной формуле;
- deterministic и neural responsibilities разделены без конфликтов;
- перечислены проверяемые гипотезы для следующих PR;
- risk register покрывает mobile, data, explainability и scope risks;
- явно зафиксировано, что black-box judge не является target architecture;
- по документу можно без домысливания запускать `PR-H02`;
- для `PR-H03` и `PR-H04` заданы framing constraints, но их полная implement-ready постановка зависит от результатов `PR-H02`.
