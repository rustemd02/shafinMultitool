# 13. Agent Briefing Template

Этот шаблон нужен, чтобы любому AI-агенту хватало контекста для отдельного PR по `Camera Analysis v1`.

## Короткий ответ на вопрос "хватит ли контекста?"

Для стратегической и design-проработки документов в `docs/cameraanalysis` контекста обычно хватает.

Для качественной реализации почти всегда нужно добавить еще:
- конкретную цель;
- номер PR;
- границы ответственности;
- входные файлы;
- ожидаемый артефакт;
- definition of done;
- write scope.

## Рекомендуемые режимы

Для новых чатов явно указывайте один из режимов:
- `Режим: design`
- `Режим: design verify`
- `Режим: implement`
- `Режим: implement verify`

`design verify` использовать перед кодингом для contract-sensitive PR.
`implement verify` использовать после кодинга для проверки соответствия design docs и DoD.

## Рекомендуемый briefing

```text
Контекст:
Прочитай:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/00-overview.md
- docs/cameraanalysis/01-roadmap.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md
- <профильные design docs>
- <нужные файлы кода>

Проект:
- iOS camera coaching module inside `shafinMultitool/Multitool2Module`
- целевая система: explainable camera analysis for cinematic framing
- режимы: `live` и `pause`
- architectural principle: offline-first with optional hybrid reasoning
- LLM не является source-of-truth для raw critique

PR:
- номер: <PR-XXX>
- название: <короткое имя PR>

Цель:
<одна конкретная цель>

Что нужно сделать:
- <список задач>

Что не нужно делать:
- не менять unrelated parts
- не расширять scope сверх PR
- не перепроектировать frozen contracts без явной причины

Ограничения:
- сохранить mobile-first behavior
- сохранить explainability
- сохранить fallback path
- минимизировать write scope

Write scope:
- <список допустимых файлов/директорий>

Ожидаемый результат:
- <design doc / implementation plan / code patch / tests / prompt pack>

Definition of done:
- <четкие критерии готовности>

Проверка:
- <команды тестов / smoke steps / UI verification>
```

## Когда контекста уже недостаточно

Нужно добавлять больше контекста, если задача:
- меняет core domain contracts;
- меняет UI state flow между `live` и `pause`;
- затрагивает `AnalysisPipeline`, `CameraViewModel` и `OverlayView` одновременно;
- вводит LLM/provider abstraction;
- меняет eval contracts или runtime logging schema.

## Что лучше прикладывать дополнительно

Для implementation-агента:
- [CameraViewModel.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)
- [SuggestionEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Suggestion/SuggestionEngine.swift)
- [OverlayView.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift)
- [camera-analysis-requirements-draft.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-requirements-draft.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)

Для eval-агента:
- frozen golden cases
- baseline examples
- 5-10 sample critique outputs

Для reasoning-агента:
- critique contract
- recommendation contract
- pause presentation contract
- fallback behavior rules

## Практическое правило

Если агент должен:
- исследовать;
- декомпозировать;
- спроектировать;

то документов `docs/cameraanalysis` обычно хватит.

Если агент должен:
- писать production code;
- менять pipeline;
- менять UI wiring;
- вводить LLM/provider layer;
- строить eval infrastructure;

то к документам нужно добавить соответствующие исходники и 3-10 concrete examples или golden cases.
