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
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md) (active `v1` source of truth)
- [40-runtime-train-contract-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/40-runtime-train-contract-design.md) (draft `v2`, design/rollout plan)

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
- validator stack design: [30-validator-stack-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/30-validator-stack-design.md)
- dataset assembly design: [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)
- dataset assembly package: [dataset_builder/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/dataset_builder)
- dataset assembly CLI: [06_build_dataset_splits.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py)
- validator package: [validators/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/validators)
- semantic critic CLI: [03_semantic_critic.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/validators/03_semantic_critic.py)
- validate-and-pack CLI: [05_validate_and_pack.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/validators/05_validate_and_pack.py)
- augmentation package: [augmentation/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/augmentation)
- augmentation CLI: [04_noise_and_morphology.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/augmentation/04_noise_and_morphology.py)
- source generation package: [source_generation/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation)
- source generation CLI: [02_generate_source_variants.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/02_generate_source_variants.py)
- deterministic graph generator package: [graph_generator/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/graph_generator)
- deterministic graph generator CLI: [01_build_pattern_graphs.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py)
- CIR executable artifacts (schema/types/validator/tests): [cir_contract/contracts/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts)
- SG v7 canonical dataset entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
- pilot runner для малого end-to-end прогона: [run_sgv7_pilot.sh](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/run_sgv7_pilot.sh)
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
- design для validator stack: [30-validator-stack-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/30-validator-stack-design.md)
- executable artifacts для validator stack: [validators/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/validators)
- CLI для semantic critic: [03_semantic_critic.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/validators/03_semantic_critic.py)
- CLI для validate-and-pack: [05_validate_and_pack.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/validators/05_validate_and_pack.py)
- агент по dataset assembly/splits: [07-dataset-assembly.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/07-dataset-assembly.md)
- design для dataset assembly/splits: [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)
- executable artifacts для dataset assembly/splits: [dataset_builder/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/dataset_builder)
- CLI для dataset assembly/splits: [06_build_dataset_splits.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py)
- агент по training strategy: [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)
- design для training strategy: [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md)
- design verify для training strategy: [33-training-strategy-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/33-training-strategy-design-verify.md)
- final design verify для training strategy: [34-training-strategy-design-verify-final.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/34-training-strategy-design-verify-final.md)
- implement verify для training strategy: [35-training-strategy-implement-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/35-training-strategy-implement-verify.md)
- eval harness design: [36-eval-harness-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/36-eval-harness-design.md)
- eval harness design verify: [37-eval-harness-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/37-eval-harness-design-verify.md)
- eval harness design verify final: [38-eval-harness-design-verify-final.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/38-eval-harness-design-verify-final.md)
- eval harness package: [eval/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/eval)
- eval harness README: [eval/README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/eval/README.md)
- eval harness CLI: [07_eval_local_model.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/eval/07_eval_local_model.py)
- eval harness tests: [eval/tests/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/eval/tests)
- runtime/train contract design draft (`v2`): [40-runtime-train-contract-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/40-runtime-train-contract-design.md)
- training harness package: [training/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training)
- phase view builder CLI: [08_build_phase_view.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/08_build_phase_view.py)
- checkpoint compare CLI: [09_compare_checkpoints.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/09_compare_checkpoints.py)
- experiment registry CLI: [10_register_experiment.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/10_register_experiment.py)
- phase configs: [phase_configs/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/phase_configs)
- training harness tests: [tests/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/tests)
- агент по eval и release gate: [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- агент по runtime feedback loop: [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- design для runtime feedback loop: [39-runtime-feedback-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/39-runtime-feedback-design.md)
- runtime feedback contracts: [runtime_feedback/contracts/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback/contracts)
- runtime feedback package: [runtime_feedback/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback)
- runtime feedback normalize CLI: [normalize_runtime_feedback.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback/normalize_runtime_feedback.py)
- runtime feedback review/promote CLI: [review_and_promote_runtime_feedback.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback/review_and_promote_runtime_feedback.py)
- runtime feedback eval export CLI: [export_real_runtime_eval_cases.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback/export_real_runtime_eval_cases.py)
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
- full one-command orchestrator (tests + pipeline + audit): [run_sgv7_full.sh](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/run_sgv7_full.sh)
- post-run output auditor: [audit_sgv7_outputs.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/audit_sgv7_outputs.py)

## One-Command Automation

Полностью автоматический прогон (preflight tests -> pipeline -> audit):

```bash
/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/run_sgv7_full.sh \
  --output-dir /tmp/sgv7_build_auto \
  --seed 20260415 \
  --core-records 240 \
  --hard-records 240 \
  --paraphraser-backend openai \
  --critic-backend openai \
  --critic-disable-response-format \
  --paraphraser-workers 15 \
  --critic-workers 4 \
  --min-same-type-markers 1
```

Если хочешь, чтобы запуск падал при пустых `preference_*`:

```bash
/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/run_sgv7_full.sh \
  --output-dir /tmp/sgv7_build_auto \
  --seed 20260415 \
  --core-records 240 \
  --hard-records 240 \
  --paraphraser-backend openai \
  --critic-backend openai \
  --critic-disable-response-format \
  --require-preference \
  --require-runtime-preference-origin
```

Если нужен неофициальный endpoint:

```bash
/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/run_sgv7_full.sh \
  --openai-base-url "https://your-endpoint/v1" \
  --output-dir /tmp/sgv7_build_auto \
  --seed 20260415 \
  --core-records 240 \
  --hard-records 240 \
  --paraphraser-backend openai \
  --critic-backend openai \
  --critic-disable-response-format
```

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
