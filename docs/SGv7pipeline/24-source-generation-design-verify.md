# 24. Source Generation Design Verify

## Цель

Повторно проверить [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md) после исправления замечаний из [23-source-generation-design-review.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/23-source-generation-design-review.md) и явно ответить:
- сохраняет ли design chronology, marked objects и ordinal references
- не поощряет ли design hallucination
- готов ли design к реализации `02_generate_source_variants.py`

Проверка выполнена против:
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)
- [04-source-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/04-source-generation.md)
- [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
- [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)

## Findings

Блокирующих findings не обнаружено.

Проверка подтвердила:
- ownership между Track 4 и Track 5 теперь однозначно разведен
- ownership semantic hard reject теперь однозначно назначен Track 6
- same-type marked object disambiguation описана исполнимо
- persisted `source_text` normalization policy зафиксирована отдельно от dedup normalization

## Verification Notes

### Chronology And Beat Preservation

Design явно не поощряет beat collapse:
- chronology вынесена в обязательный prompt payload через `beat_outline`
- anti-hallucination policy запрещает менять порядок beats и схлопывать критичные фазы
- semantic hard reject в Track 6 явно ловит потерю chronology

Ключевые ссылки:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L282)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L448)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L513)

### Marked Objects And Morphology

Design сохраняет exact marked-object grounding:
- prompt contract включает `marked_object_block`
- alias whitelist и surface-anchor checks не дают silently потерять object mention
- same-type disambiguation policy описывает обязательные distinguishing cues
- morphology-heavy surface stress не потеряна как pipeline requirement, а корректно вынесена в Track 5

Ключевые ссылки:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L292)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L305)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L454)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L377)

### Ordinal References

Design сохраняет ordinal bindings:
- `ordinal_bindings` входят в prompt payload
- hard constraints запрещают терять `first/second/third`, когда они нужны для recoverability
- lexical checks и Track 6 semantic hard reject together покрывают both surface-level and semantic ordinal loss

Ключевые ссылки:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L117)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L264)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L470)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L534)

### Anti-Hallucination Boundary

Design не поощряет hallucination, потому что:
- graph остаётся единственным semantic source of truth
- prompt templates содержат explicit `must_keep` и `must_not_introduce`
- Track 4 hard reject отсекает format/surface failures
- Track 6 semantic hard reject отсекает invented objects, invented beats, semantic replacement unsupported actions и invented dialogue

Ключевые ссылки:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L48)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L322)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L485)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L497)

### Implement Readiness

Документ теперь даёт implementer-у все ключевые решения для `02_generate_source_variants.py`:
- base scope
- prompt templates
- style policy
- variant counts
- reject ownership boundary
- normalization policy
- required functions
- smoke tests

Ключевые ссылки:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L160)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L216)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L411)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L553)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L672)

## Residual Risks

Неблокирующие риски остаются:
- Track 5 позже должен зафиксировать свою собственную normalization policy для noisy/stress variants без train/runtime drift
- при реализации стоит подтвердить smoke tests на real graph fixtures, особенно для same-type markers и unsupported actions

Эти риски не блокируют переход к `implement` для Track 4.

## Verdict

Текущий `Prompt 4 / design`:
- сохраняет chronology, marked objects и ordinal references
- не поощряет hallucination
- готов к реализации

Итог `design verify`:
- contradictions found: `no`
- implementation-blocking gaps found: `no`
- ready for implementation: `yes`
