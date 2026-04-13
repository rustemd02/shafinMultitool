# SG v7 Pipeline

Этот набор документов описывает новый пайплайн подготовки датасета и дообучения локальной `qwen 1.5B` для Scene Generator.

Цель:
- повысить точность генерации JSON
- уменьшить схлопывание сцены в минимальный ответ
- улучшить `beats`, `marked objects`, `ordinal references` и `described_action`
- сделать пайплайн автоматизируемым и пригодным для параллельной проработки разными агентами

## Как читать

Если хочется общего понимания, начинайте с:
- [00-overview.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/00-overview.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/01-roadmap.md)
- [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)

Если хочется отдавать работу агентам по частям:
- агент по архитектуре пайплайна: [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/02-pipeline-architecture.md)
- агент по генерации canonical graph: [03-graph-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/03-graph-generation.md)
- pattern library spec для graph generator: [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md)
- pattern library executable artifacts: [pattern_library/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/pattern_library)
- canonical intermediate representation: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- deterministic graph generator design: [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)
- source generation design: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- source generation design review: [23-source-generation-design-review.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/23-source-generation-design-review.md)
- source generation design verify: [24-source-generation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/24-source-generation-design-verify.md)
- source generation implement verify: [25-source-generation-implement-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/25-source-generation-implement-verify.md)
- source generation implement verify final: [26-source-generation-implement-verify-final.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/26-source-generation-implement-verify-final.md)
- augmentation design: [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- augmentation design verify: [28-augmentation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/28-augmentation-design-verify.md)
- augmentation design verify final: [29-augmentation-design-verify-final.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/29-augmentation-design-verify-final.md)
- augmentation package: [augmentation/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/augmentation)
- augmentation CLI: [04_noise_and_morphology.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/augmentation/04_noise_and_morphology.py)
- source generation package: [source_generation/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation)
- source generation CLI: [02_generate_source_variants.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/02_generate_source_variants.py)
- deterministic graph generator package: [graph_generator/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/graph_generator)
- deterministic graph generator CLI: [01_build_pattern_graphs.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py)
- CIR executable artifacts (schema/types/validator/tests): [cir_contract/contracts/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts)
- SG v7 canonical dataset entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
- агент по source/paraphrase generation: [04-source-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/04-source-generation.md)
- design для source/paraphrase generation: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- design verify для source/paraphrase generation: [23-source-generation-design-review.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/23-source-generation-design-review.md)
- final design verify для source/paraphrase generation: [24-source-generation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/24-source-generation-design-verify.md)
- агент по morphology/noise augmentation: [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- design для morphology/noise augmentation: [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- design verify для morphology/noise augmentation: [28-augmentation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/28-augmentation-design-verify.md)
- final design verify для morphology/noise augmentation: [29-augmentation-design-verify-final.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/29-augmentation-design-verify-final.md)
- executable artifacts для morphology/noise augmentation: [augmentation/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/augmentation)
- CLI для morphology/noise augmentation: [04_noise_and_morphology.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/augmentation/04_noise_and_morphology.py)
- агент по validators/critics: [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
- агент по dataset assembly/splits: [07-dataset-assembly.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/07-dataset-assembly.md)
- агент по training strategy: [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)
- агент по eval и release gate: [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- агент по runtime feedback loop: [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- агент по implementation backlog: [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md)
- агентный prompt pack: [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)
- шаблон briefing-а: [13-agent-briefing-template.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/13-agent-briefing-template.md)
- фиксированные решения: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- реальные runtime failure examples: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- codebase map: [16-codebase-entry-points.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/16-codebase-entry-points.md)
- инструкция по работе с Codex: [17-how-to-operate-with-codex.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/17-how-to-operate-with-codex.md)
- source-of-truth для train/runtime alignment: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- canonical intermediate representation contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- pattern library contract: [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md)
- CIR validator CLI: [validate_cir_contract.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/scripts/validate_cir_contract.py)
- CIR -> SceneScript serializer and SG v7 entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)

## Главная идея

Для `qwen 1.5B` нельзя делать ставку на "очень умный teacher написал идеальный JSON". Нужен пайплайн, где:
- canonical JSON строится программно и детерминированно
- LLM используется в первую очередь как paraphraser и critic
- hard-cases покрывают реальные провалы из runtime
- все данные проходят строгую автоматическую валидацию
- train format совпадает с runtime prompt format
- exact runtime/train contract versioned и проверяется fixtures-ами

## Основные принципы

- `nano` не должен быть единственным источником ground-truth JSON
- synthetic data должна быть каноничной, а не креативной
- один и тот же смысл должен давать один и тот же target JSON
- canonical entrypoint должен fail-fast на contract drift, а не чинить `sample_id` молча
- model capacity 1.5B надо беречь: complexity budget важнее разнообразия ради разнообразия
- real runtime failures должны замыкаться обратно в dataset pipeline
