# 12. Agent Prompts

Этот файл содержит готовые промпты для отдельных AI-агентов по `SG v7`.

## Важно

Одного только стратегического контекста обычно хватает для:
- исследования
- проектирования
- написания спецификаций
- предложений по архитектуре

Но для задач реализации агентам почти всегда нужно дополнительно дать:
- конкретную цель
- границы ответственности
- входные файлы
- ожидаемый артефакт
- критерий готовности

Поэтому ниже промпты уже составлены в таком формате.

## Общий режим работы

Для всех промптов ниже агент должен работать в одном из 4 режимов:
- `design` - спроектировать решение, не писать production code
- `design verify` - проверить design-результат, не переходить к реализации
- `implement` - реализовать код по уже существующему дизайну
- `implement verify` - проверить, что реализация соответствует дизайну, DoD и существующим артефактам

Если ты запускаешь новый чат, в начало конкретного промпта добавляй одну строку:
- `Режим: design`
- `Режим: design verify`
- `Режим: implement`
- `Режим: implement verify`

Ожидаемое поведение по режимам:
- в режиме `design` агент делает спецификацию, API, backlog, тест-план и конкретный implementation handoff
- в режиме `design verify` агент делает design review: ищет противоречия, пробелы, нереализуемые места, конфликт с `fixed decisions` и слабые места в DoD; код не пишет
- в режиме `implement` агент читает релевантные design docs и существующий код, затем вносит изменения в кодовую базу, добавляет тесты и пишет команды проверки
- в режиме `implement verify` агент не перепроектирует систему заново, а делает аудит уже существующей реализации против design docs, DoD и реальных артефактов

## Рекомендуемый порядок запуска

Для архитектурных, schema-level и contract-sensitive задач по умолчанию использовать:
- `design -> design verify -> implement -> implement verify`

Это обязательно рекомендуется для:
- canonical contract
- pattern library
- graph generator
- validator stack
- eval harness
- runtime/train contract

Для локальных и низкорисковых задач допустим укороченный цикл:
- `design -> implement -> implement verify`

Это обычно подходит для:
- узких augmentation-задач
- небольших utility scripts
- локальных prompt/template updates без смены contract-а

Обязательное правило интеграции результата:
- агент не должен оставлять результат в "висящем" новом файле без интеграции в пакет `SGv7pipeline`
- если создан новый артефакт, агент должен либо обновить существующий индексный файл, либо явно записать ссылку на новый артефакт в подходящий существующий документ
- минимум: обновить `docs/SGv7pipeline/README.md` или другой профильный index/overview/backlog/prompts файл, чтобы следующий агент мог подхватить результат
- в финальном ответе агент должен явно написать, где теперь зафиксирован результат и из какого существующего файла он доступен

Если задача касается:
- runtime prompts
- training prompts
- serializer
- grammar/GBNF
- eval fidelity metrics
- corrected runtime samples

то агент обязан дополнительно прочитать:
- docs/SGv7pipeline/18-runtime-train-contract.md

## Prompt 1. Canonical Contract Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/00-overview.md
- docs/SGv7pipeline/02-pipeline-architecture.md
- docs/SGv7pipeline/03-graph-generation.md

Задача:
Спроектируй canonical intermediate representation для SG v7, который будет стоять между pattern generator и final SFT JSON.

Что нужно сделать:
- описать schema intermediate graph
- перечислить обязательные поля
- перечислить optional поля
- определить, какие части должны быть детерминированными
- показать 3-5 example records
- указать, что должно совпадать с runtime SceneScript schema, а что может быть внутренним

Ограничения:
- модель назначения: qwen 1.5B
- schema должна уменьшать ambiguity
- schema должна хорошо поддерживать marked objects, ordinal references, described_action и beats

Результат:
- markdown design doc
- список invariants
- список open questions
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: по документу можно реализовать graph generator без домысливания
- `design verify`: агент проверил design-результат, перечислил противоречия, пробелы и риски, и явно указал, готов ли design к реализации
- `implement`: если по этому контракту уже существует код, агент обновил schema/типы/примеры/тесты так, что contract является исполнимым и непротиворечивым
- `implement verify`: агент проверил, что runtime и dataset pipeline используют один и тот же canonical contract, и перечислил все расхождения между design и реализацией
```

## Prompt 2. Pattern Library Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/00-overview.md
- docs/SGv7pipeline/03-graph-generation.md
- docs/SGv7pipeline/11-implementation-backlog.md

Задача:
Составь полную pattern library для SG v7.

Что нужно сделать:
- перечислить semantic pattern classes
- разбить их на core / hard
- указать target distribution по pattern classes
- указать failure modes, которые покрывает каждый pattern
- дать canonical examples

Особый фокус:
- toward_each_other
- stop/pass_by near marked object
- first/second actor
- unsupported actions -> described_action
- same-type marked objects
- 3-beat scenes

Результат:
- markdown spec
- таблица pattern -> coverage -> difficulty
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: pattern library можно использовать как вход для deterministic graph generator
- `design verify`: агент проверил, что pattern library покрывает critical runtime failures, не имеет логических дыр и действительно годится как вход для graph generator
- `implement`: если в репо уже есть pattern registry/library, агент реализовал или обновил её структуры данных, seedable pattern enumeration и тестовые examples
- `implement verify`: агент проверил, что все critical runtime failures покрыты уже реализованной pattern library и что нет дыр в core/hard buckets
```

## Prompt 3. Graph Generator Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/02-pipeline-architecture.md
- docs/SGv7pipeline/03-graph-generation.md
- docs/SGv7pipeline/07-dataset-assembly.md

Дополнительно изучи текущий код:
- generate_dataset_v6.py

Задача:
Предложи дизайн и implementation plan для deterministic graph generator для SG v7.

Что нужно сделать:
- описать модульную структуру генератора
- предложить API
- предложить data flow
- описать seed/reproducibility strategy
- описать complexity controls
- описать dedup strategy на уровне graph

Ограничения:
- не использовать LLM как source of truth для JSON
- все target ids должны быть программно гарантированы
- нужна возможность генерировать отдельно core и hard buckets

Результат:
- implementation design
- backlog по функциям/классам
- список unit tests
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: инженер может начать писать `01_build_pattern_graphs.py` без дополнительных архитектурных решений
- `design verify`: агент проверил, что design graph generator-а реализуем, детерминирован, не противоречит contract-у и покрывает core/hard separation
- `implement`: реализован `01_build_pattern_graphs.py` или эквивалентный модуль, есть CLI/API для генерации graph records, есть deterministic seed behavior, есть unit/smoke tests
- `implement verify`: агент проверил, что одинаковый seed даёт одинаковый output, графы валидны, ids гарантированно детерминированы, core/hard buckets реально разделяются
```

## Prompt 4. Source Generation Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/04-source-generation.md
- docs/SGv7pipeline/05-augmentation.md
- docs/SGv7pipeline/06-validation-and-critics.md

Дополнительно изучи текущий код:
- generate_dataset_v6.py

Задача:
Спроектируй pipeline graph-to-text generation для SG v7 с использованием GPT-5.4 nano как paraphraser, а не как teacher для JSON.

Что нужно сделать:
- предложить prompt templates
- описать style buckets
- предложить число variants на graph
- предложить anti-hallucination constraints
- описать reject criteria для source variants

Особый фокус:
- morphology around marked objects
- colloquial Russian user prompts
- preserving chronology and beats
- preserving ordinal references

Результат:
- prompt pack
- source generation policy
- quality checklist
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно реализовать `02_generate_source_variants.py` без дополнительных решений по prompt contract и reject policy
- `design verify`: агент проверил, что source-generation design сохраняет chronology, marked objects и ordinal references и не поощряет hallucination
- `implement`: реализован `02_generate_source_variants.py` или эквивалентный модуль, есть prompt templates, batching, traceable metadata, reject filters и smoke test на малом наборе graph inputs
- `implement verify`: агент проверил, что source generation не ломает chronology, ordinal references, marked-object mentions и style buckets
```

## Prompt 5. Augmentation Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/05-augmentation.md
- docs/SGv7pipeline/06-validation-and-critics.md

Задача:
Спроектируй controlled augmentation layer для SG v7.

Что нужно сделать:
- перечислить augmentation classes
- разделить safe vs risky transforms
- предложить morphology engine rules
- предложить user-noise transformations
- описать traceable metadata

Особый фокус:
- комп/компа/компу
- ноутбук/ноутбука
- первый/второй
- actor/актёр spelling variation
- whitespace/punctuation noise

Результат:
- augmentation spec
- transformation catalog
- post-augmentation validation plan
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно реализовать `04_noise_and_morphology.py` без дополнительных решений по transform catalog
- `design verify`: агент проверил, что augmentation design разделяет safe/risky transforms, не ломает semantics и пригоден для автоматической валидации
- `implement`: реализован `04_noise_and_morphology.py` или эквивалентный модуль, есть управляемые transforms, trace metadata и tests для morphology/noise cases
- `implement verify`: агент проверил, что safe transforms сохраняют semantics, а risky transforms либо валидируются, либо отбрасываются
```

## Prompt 6. Validator And Critic Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/06-validation-and-critics.md
- docs/SGv7pipeline/07-dataset-assembly.md
- docs/SGv7pipeline/09-eval-and-release.md

Дополнительно изучи текущий код:
- generate_dataset_v6.py

Задача:
Спроектируй validation stack и semantic critic для SG v7.

Что нужно сделать:
- описать layers validators
- определить hard reject vs manual review
- предложить critic prompts
- предложить recoverability scoring
- предложить error taxonomy

Особый фокус:
- object grounding
- beat collapse
- unsupported action loss
- dangling target
- same-type marker conflicts

Результат:
- validator architecture doc
- critic prompt pack
- reject taxonomy
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно реализовать `03_semantic_critic.py` и `05_validate_and_pack.py` без дополнительных решений по architecture
- `design verify`: агент проверил, что validator architecture полна, непротиворечива, покрывает provenance policy и не оставляет критичных semantic gaps
- `implement`: реализованы validator/critic модули, reject taxonomy, recoverability scoring и packaging checks; есть tests на known failure cases
- `implement verify`: агент проверил, что bad samples reliably reject, repairable samples маркируются отдельно, а accepted samples проходят schema и semantic validation
```

## Prompt 7. Dataset Assembly Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/07-dataset-assembly.md
- docs/SGv7pipeline/09-eval-and-release.md

Задача:
Спроектируй сборку train/val/test и preference sets для SG v7.

Что нужно сделать:
- определить структуру JSONL файлов
- определить split strategy
- определить metadata contract
- определить balancing policy
- определить dedup policy

Особый фокус:
- semantic-aware split
- family-level holdout
- hard bucket accounting

Результат:
- dataset packaging spec
- split builder design
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно реализовать dataset assembler без дополнительных решений
- `design verify`: агент проверил, что split policy, provenance policy и metadata contract совместимы между собой и не допускают leakage
- `implement`: реализован dataset assembler/split builder, генерируются train/val/test/preference artifacts с metadata и dedup guarantees
- `implement verify`: агент проверил, что split leakage отсутствует, family-level holdout соблюдается, а hard buckets корректно учтены в статистике
```

## Prompt 8. Training Strategy Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/08-training-plan.md
- docs/SGv7pipeline/09-eval-and-release.md

Задача:
Составь практический training recipe для qwen 1.5B на SG v7.

Что нужно сделать:
- расписать phases
- предложить oversampling strategy
- предложить core/hard mixing strategy
- предложить checkpoints comparison policy
- предложить критерии, когда нужен preference tuning

Ограничения:
- модель назначения: 1.5B
- задача: стабильный JSON, а не максимальная генеративная креативность

Результат:
- training playbook
- ablation plan
- risk list
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно запускать experiments по фазам и сравнивать результаты
- `design verify`: агент проверил, что training recipe соответствует ограничениям 1.5B, complexity budget и release logic
- `implement`: если в репо уже есть training scripts/configs, агент обновил их под SG v7 recipe, добавил конфиги запусков, чекпоинт-таблицы и reproducible experiment notes
- `implement verify`: агент проверил, что experiment matrix воспроизводим, сравнение checkpoint-ов консистентно, а метрики отражают именно стабильность JSON и semantic fidelity
```

## Prompt 9. Eval Harness Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/09-eval-and-release.md
- docs/SGv7pipeline/10-runtime-feedback-loop.md

Задача:
Спроектируй eval framework для SG v7 и локальной qwen 1.5B.

Что нужно сделать:
- определить metrics
- определить bucket metrics
- определить report format
- определить release gate
- определить A/B protocol

Результат:
- eval design doc
- metric definitions
- report template
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно реализовать `07_eval_local_model.py` без дополнительных решений по metrics и reporting
- `design verify`: агент проверил, что eval design действительно измеряет exact grounding, ordinal fidelity и release readiness, а не только syntax success
- `implement`: реализован `07_eval_local_model.py` или эквивалентный eval harness, есть metric computation, bucket reports и release-gate summary
- `implement verify`: агент проверил, что eval harness различает syntax success, grounding success, beat fidelity, ordinal fidelity и hard-bucket performance
```

## Prompt 10. Runtime Feedback Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md

Контекст:
Прочитай:
- docs/SGv7pipeline/10-runtime-feedback-loop.md
- docs/SGv7pipeline/11-implementation-backlog.md

Дополнительно изучи текущий код:
- LLMParserService.swift
- SceneParserService.swift

Задача:
Спроектируй runtime feedback loop, который будет автоматически собирать ошибки Scene Generator и возвращать их в SG v7 pipeline.

Что нужно сделать:
- определить logging schema
- определить failure taxonomy
- определить clustering strategy
- определить corrected-sample export flow
- определить privacy/safety constraints

Результат:
- runtime feedback design doc
- backlog на реализацию
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: можно реализовать failure ingestion и active learning loop без дополнительных решений
- `design verify`: агент проверил, что feedback-loop design покрывает provenance, clustering и обратную интеграцию в dataset pipeline без семантического drift
- `implement`: реализованы runtime logging schema, failure export/injest path и corrected-sample collection flow либо их минимальный end-to-end skeleton
- `implement verify`: агент проверил, что runtime failures можно трассировать до dataset bucket/pattern family и что feedback artifacts пригодны для следующего training cycle
```

## Prompt 11. Runtime / Train Contract Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/15-runtime-failure-examples.md
- docs/SGv7pipeline/18-runtime-train-contract.md
- docs/SGv7pipeline/40-runtime-train-contract-design.md (обязательно для `v2` design/design verify; `18` остаётся active source of truth для `v1`)

Контекст:
Прочитай:
- docs/SGv7pipeline/02-pipeline-architecture.md
- docs/SGv7pipeline/08-training-plan.md
- docs/SGv7pipeline/09-eval-and-release.md

Дополнительно изучи текущий код:
- generate_dataset_v7.py
- generate_dataset_v6.py (legacy reference only; не использовать как canonical SG v7 entrypoint)
- LLMParserService.swift
- SceneParserService.swift
- SceneScript.swift

Задача:
Зафиксируй и/или реализуй exact runtime/train contract для SG v7 так, чтобы training и runtime не расходились по prompt structure, serializer, grammar и decoding policy.

Что нужно сделать:
- описать или обновить exact prompt structure
- описать или обновить marked-object section contract
- описать или обновить canonical serializer rules
- описать или обновить grammar/GBNF contract
- описать frozen fixtures и mismatch checks
- описать change policy и versioning

Особый фокус:
- exact `object_marked_*` identity
- ordinal binding
- unsupported action mapping
- optional field policy
- train/inference drift detection

Результат:
- contract spec или code patch
- fixture plan или fixture implementation
- список drift checks
- интеграция результата в существующий индексный документ пакета

Definition of done:
- `design`: есть один исполнимый source-of-truth contract без двусмысленностей
- `design verify`: агент проверил, что contract полон, согласован с runtime schema и не оставляет drift-prone зон между train и runtime
- `implement`: runtime и training артефакты приведены к одному contract, добавлены fixtures и mismatch checks
- `implement verify`: агент проверил, что train/runtime alignment соблюдается по prompt, serializer, grammar и decoding settings
```
