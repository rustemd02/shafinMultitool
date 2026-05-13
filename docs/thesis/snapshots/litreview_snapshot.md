# Litreview Snapshot

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`
Protected source: `docs/thesis/litreview.md`

## Найденный файл

| Поле | Значение |
|---|---|
| Файл | `docs/thesis/litreview.md` |
| Формат | Markdown |
| Язык | русский |
| Роль | защищённая уже написанная теоретическая часть / литературный обзор |
| Политика | не редактировать без отдельной явной задачи; предложения фиксировать в `docs/thesis/07_litreview_alignment.md` или review notes |

## Текущая структура

| Раздел | Что покрывает | Наблюдения |
|---|---|---|
| Название, аннотация, ключевые слова | Обзор методов и технологий оптимизации мобильного видеопроизводства | Хорошая рамка для темы ВКР, но требуется bridge к конкретной системе в репозитории. |
| Введение | Проблемы превизуализации, съёмки, монтажа; объект и предмет исследования | Уже задаёт объект/предмет, которые можно использовать в `00_thesis_brief.md`. |
| Методология | Базы поиска, ключевые слова, критерии включения/исключения | Есть потенциальная временная неоднозначность: в тексте указаны публикации до 31 декабря 2025 года; это litreview-claim, проверять через код нельзя. |
| Этап предварительного производства | ARKit-превизуализация, вставка 3D-контента, ограничения мобильного исполнения | Прямо связывается с Scene Generator, AR/previsualization и mobile-first ограничениями. |
| Этап съёмки | Aesthetic assessment, activity/video understanding, mobile CV | Связывается с Camera Analysis, explainability, CoreML wrappers и нейронным evidence layer. |
| Этап монтажа | Автоматический монтаж и мобильное diffusion video editing | В текущем проекте это слабее покрыто практической частью; вероятно, оставить как контекст и limitation. |
| Заключение | Пробел: отсутствие комплексных мобильных решений, компромисс качество/производительность | Сильная bridge-точка к проекту как комплексному прототипу preproduction + shooting assistance. |
| Список литературы | 14 источников | Источники внутри litreview считать `litreview_unchecked`, пока не проводится отдельная библиографическая проверка. |

## Уже покрытые темы

| Тема | Статус покрытия |
|---|---|
| Мобильное видеопроизводство как предметная область | покрыто |
| Ограничения мобильных устройств: нагрев, FPS, батарея, память | покрыто |
| AR/previsualization на iOS/ARKit | покрыто |
| Оценка эстетики изображения | покрыто |
| Мобильное video understanding | покрыто |
| Автоматизированный монтаж | покрыто на уровне обзора |
| Компромисс качество/производительность | покрыто |
| Необходимость объяснимых рекомендаций пользователю | покрыто как открытая проблема |

## Темы, которые нужно связать с практической частью

| Тема | Проектная связка |
|---|---|
| Mobile AR/previsualization | `shafinMultitool/SceneGeneratorModule/**`, `SceneScript`, AR/RealityKit runtime, bundle-first pipeline. |
| Local ML/LLM inference | `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift`, llama.cpp/Qwen/GGUF записи в `diploma.md`, live smoke tests. |
| Scene parsing | `shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift`, `shafinMultitool/SceneGeneratorModule/Services/SceneParseCoordinator.swift`, `shafinMultitool/SceneGeneratorModule/Services/ScenePlanCompiler.swift`, `shafinMultitool/SceneGeneratorModule/Services/SceneEventTableV9Service.swift`. |
| Structured output / JSON generation | `shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift`, `shafinMultitool/SceneGeneratorModule/Models/ScenePlanning.swift`, SG v7/v8/v9 contracts and eval artifacts. |
| Constrained decoding / GBNF | `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift`, `docs/SGv7pipeline/18-runtime-train-contract.md`, `diploma.md`. |
| Fine-tuning / SFT / preference optimization | `docs/SGv7pipeline/training/**`, `docs/SGv8pipeline/v8/**`, `docs/SGv9pipeline/v9/**`, benchmark reports. |
| Explainable AI | `docs/cameraanalysis/04-explainability-contract.md`, explainability trace contracts (`ExplainabilityTraceItem`, `ExplainabilityTraceBundle`) in Camera Analysis. |
| Mobile-first AI architecture | runtime gates, thermal/cadence policies, `shafinMultitool/Multitool2Module/Services/Pipeline/NeuralEvidenceInferenceService.swift`, `shafinMultitool/Multitool2Module/Services/Pipeline/ThermalGovernor.swift`. |
| Computer vision / camera analysis | `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/**`, `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`, `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift`. |
| Evaluation methodology | `experiments/sc_benchmark/**`, `docs/cameraanalysis/eval/**`, SG v8/v9 run reports. |

## Термины для синхронизации с глоссарием

`SceneScript`, `ScenePlanIR`, `CIR`, `SG v7`, `SG v8`, `V9 slot/event table`, `GBNF`, `SFT`, `ORPO`, `previsualization`, `on-device inference`, `CoreML`, `llama.cpp`, `GGUF`, `Camera Analysis`, `ExplainabilityTraceBundle`, `NeuralEvidenceSnapshot`, `ARKit`, `RealityKit`, `runtime feedback loop`.

## Потенциальные повторы, слабые связки и неподтверждённые утверждения

| Наблюдение | Риск | Рекомендуемое действие |
|---|---|---|
| В litreview есть общая постановка о комплексном мобильном решении, но практический прототип ещё не введён. | Резкий переход от обзора к реализации. | Добавить короткую bridge-секцию перед архитектурной главой. |
| Эксперимент по ARKit-превизуализации приведён в litreview как часть обзора. | Нужно явно отделить литературный обзор от собственной практической реализации текущего репозитория. | В claim registry помечать такие утверждения как `litreview_claim` или bridge, не как code evidence. |
| Тема монтажа раскрыта в обзоре, но текущая реализация репозитория сфокусирована на preproduction и shooting assistance. | Несоответствие объёма обзора и практического вклада. | В outline оставить монтаж как контекст и limitation, не обещать реализацию монтажа. |
| Методология указывает анализ публикаций до 31.12.2025. | Требуется отдельная библиографическая проверка, не связанная с кодом. | Статус `litreview_unchecked`. |
| Часть терминов написана на русском и английском без единого стандарта. | Непоследовательность в главах. | Использовать `02_glossary.md` как style guide. |
