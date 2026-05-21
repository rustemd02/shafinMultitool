# Litreview Alignment

Protected source: `docs/thesis/litreview.md`
Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

| Раздел litreview | Тема | Как связан с проектом | Какие technical chapters должны продолжить мысль | Статус |
|---|---|---|---|---|
| Введение | Комплексная оптимизация мобильного видеопроизводства | Репозиторий реализует прототип, покрывающий preproduction через Scene Generator и shooting assistance через Camera Analysis; монтаж остаётся контекстом и ограничением. | `ch2_architecture`, `ch6_conclusion` | needs_bridge |
| Методология | Критерии поиска и отбора источников | Связь непрямая: методология обзора не является методологией оценки прототипа; экспериментальную методологию надо ввести отдельно через benchmark/eval. | `ch5_experiments` | needs_bridge |
| Этап предварительного производства | AR/previsualization | Scene Generator переводит текстовые описания/сценарные чанки в структурированный `SceneScript` для AR/previz-ready runtime. | `ch2_architecture`, `ch3_scene_generation` | aligned |
| Этап предварительного производства | Ограничения ARKit и мобильного исполнения | Практическая часть может показать local-first архитектуру, fallback, deterministic compile и ограничение тяжёлых ML-частей. | `ch2_architecture`, `ch3_scene_generation`, `ch6_conclusion` | aligned |
| Этап предварительного производства | Генерация 3D/динамического контента | В проекте не реализуется text-to-video/3D generation; Scene Generator создаёт структурный план сцены, а не фотореалистичное видео. | `ch6_conclusion` | out_of_scope |
| Этап съёмки | Оценка эстетики изображения | Camera Analysis содержит domain contracts, feature snapshots, aesthetic/CoreML wrappers и deterministic critique. | `ch2_architecture`, `ch4_camera_analysis`, `ch5_experiments` | aligned |
| Этап съёмки | Компьютерное зрение и mobile video understanding | `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`, `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift`, `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift`, `shafinMultitool/Multitool2Module/Models/Vision/VisionTracking.swift` формируют practical CV layer. | `ch4_camera_analysis` | aligned |
| Этап съёмки | Explainable recommendations | Camera Analysis вводит `CritiqueReport`, evidence refs, explainability contract, semantic tips and fusion trace. | `ch2_architecture`, `ch4_camera_analysis`, `ch5_experiments` | aligned |
| Этап съёмки | Domain shift and weak mobile signals | Eval artifacts фиксируют deterministic uplift и hybrid limitations; bridge нужен от theoretical limitation к evaluation gates. | `ch5_experiments` | needs_bridge |
| Этап монтажа | Автоматический монтаж | В текущем коде не является основным вкладом; можно использовать только как контекст широкой проблемы. | `ch6_conclusion` | out_of_scope |
| Заключение | Отсутствие комплексных мобильных решений | Проект можно позиционировать как прототип комплексной mobile-first системы для preproduction и shooting; не заявлять полный монтажный контур. | `00_thesis_brief`, `ch2_architecture`, `ch6_conclusion` | needs_bridge |
| Заключение | Компромисс качество/производительность | SG v7/v8/v9 и Camera Analysis eval показывают trade-offs между model capacity, structured contracts, fallback и mobile gates. | `ch5_experiments` | aligned |
| Заключение | Потребность в объяснимых моделях | Camera Analysis и V9 reason codes дают практический слой traceability; нужен bridge paragraph. | `ch3_scene_generation`, `ch4_camera_analysis` | needs_bridge |

## Bridge paragraphs to draft later

| Bridge ID | Откуда | Куда | Цель | Статус |
|---|---|---|---|---|
| BR-001 | Заключение litreview | Глава архитектуры | Показать, что practical gap формулируется как local-first, evidence-first архитектура, а не как универсальная генеративная система. | todo |
| BR-002 | Этап предварительного производства | Scene Generator | Связать AR/previsualization с `text -> structured scene -> deterministic compile -> AR-ready scene`. | todo |
| BR-003 | Этап съёмки | Camera Analysis | Связать проблему “не просто score, а объяснимая подсказка” с `CritiqueReport`, `EvidenceRef`, semantic tips. | todo |
| BR-004 | Методология litreview | Experiments chapter | Развести обзорную методологию и экспериментальную методологию прототипа. | todo |
