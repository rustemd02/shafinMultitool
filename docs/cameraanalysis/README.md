# Camera Analysis Pipeline

Этот набор документов описывает roadmap и PR pipeline для нового функционала `Анализ картинки с семантическими подсказками`.

Цель:
- превратить текущий camera coach из набора эвристических подсказок в explainable AI-систему;
- сохранить mobile-first архитектуру;
- показать технологическую сложность, достаточную для диплома и диссертации;
- разложить работу на детерминированные PR, которые можно безопасно отдавать разным AI-агентам.

## Как читать

Если хочется общего понимания, начинайте с:
- [00-overview.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/00-overview.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [camera-analysis-requirements-draft.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-requirements-draft.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)

Если хочется отдавать работу агентам по частям:
- roadmap по фазам: [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- implementation backlog и детерминированные PR: [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- готовые промпты для агентов: [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/12-agent-prompts.md)
- шаблон briefing-а: [13-agent-briefing-template.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/13-agent-briefing-template.md)

Если хочется перейти к следующему этапу `hybrid deterministic + neural`:
- архитектурное направление встроено в [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- roadmap расширен в [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- backlog, PR и подробный DoD добавлены в [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- research framing и границы hybrid stage зафиксированы в [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- evidence taxonomy для `PR-H02` зафиксирована в [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- dataset schema и labeling protocol для `PR-H03` зафиксированы в [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md)
- AVA usage policy и pretraining boundaries для `PR-H04` зафиксированы в [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md)
- agent prompts для hybrid stage добавлены в [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/12-agent-prompts.md)

## Главная идея

Для `camera analysis v1` нельзя делать ставку только на:
- набор коротких эвристик;
- или один черный ящик, который "смотрит на кадр" и сразу пишет текст.

Нужен каскадный pipeline, где:
- fast low-level сигналы работают локально и часто;
- semantic critique строится поверх структурированных признаков;
- explanation всегда восстанавливается до цепочки `observation -> interpretation -> recommendation`;
- тяжелый reasoning включается в первую очередь в `pause`;
- live остается быстрым, стабильным и пригодным для мобильного устройства.

## Основные принципы

- `offline-first`: базовый путь должен работать локально.
- `cascade-by-cost`: самые дорогие вычисления должны запускаться реже.
- `explainability-by-construction`: любой совет должен быть обоснован внутренним trace.
- `scene-aware`: критика зависит от типа cinematic-сцены.
- `deterministic PR units`: каждый PR должен иметь узкие границы и проверяемый DoD.

## Ключевые артефакты пакета

- [00-overview.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/00-overview.md): зачем вообще нужен новый pipeline
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md): фазы проекта
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md): сжатая схема модулей и потоков
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md): source-of-truth контракты `PR-002`
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md): source-of-truth traceability contract `PR-003`
- [05-feature-snapshot-aggregator.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/05-feature-snapshot-aggregator.md): source-of-truth дизайн `Feature Snapshot Aggregator` `PR-004`
- [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md): source-of-truth дизайн `Scene Semantics Layer` (`PrimarySubjectResolver` + `SceneTypeClassifier`) `PR-005/PR-006`
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md): source-of-truth дизайн `FrameCritiqueEngine` `PR-007`
- [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md): source-of-truth дизайн UI интеграции (`Live Hint Adapter`, `Pause Critique Card`, `Overlay Annotations`) `PR-009/PR-010/PR-011`
- [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md): source-of-truth дизайн `ReasoningProvider` и pause-only LLM слоя `PR-012/PR-013`
- [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md): source-of-truth дизайн `eval harness` `PR-014`
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md): source-of-truth research framing для `PR-H01`
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md): source-of-truth evidence taxonomy для `PR-H02`
- [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md): source-of-truth dataset schema и labeling guide для `PR-H03`
- [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md): source-of-truth AVA usage policy и pretraining design для `PR-H04`
- [camera-analysis-requirements-draft.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-requirements-draft.md): требования и продуктовые решения
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md): подробная архитектура
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md): tracks и PR-пайплайн
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/12-agent-prompts.md): промпты для AI-агентов

## Практическая рекомендация

Если цель сейчас перейти к реализации без хаоса, оптимальный порядок такой:
1. Зафиксировать contracts и доменную модель.
2. Собрать deterministic critique core без LLM.
3. Подключить `pause` expanded analysis.
4. Перевести `live` на новую модель hint-ов.
5. Добавить LLM только как controlled reasoning/text layer.
6. После этого строить eval и runtime feedback loop.
