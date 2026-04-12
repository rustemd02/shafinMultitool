# 13. Agent Briefing Template

Этот шаблон нужен, чтобы любому AI-агенту хватало контекста для отдельной задачи.

## Короткий ответ на вопрос "хватит ли контекста?"

Да, для стратегической проработки документов в `docs/SGv7pipeline` контекста уже хватит.

Но для качественной работы по реализации почти всегда нужно добавить ещё 5 вещей:
- конкретную цель
- границы ответственности
- входные файлы
- ожидаемый артефакт
- критерий готовности

Без этого агент начнёт либо расплываться, либо домысливать.

## Рекомендуемые режимы

Для новых чатов явно указывайте один из режимов:
- `Режим: design`
- `Режим: design verify`
- `Режим: implement`
- `Режим: implement verify`

`design verify` использовать для проверки design-артефакта до начала кодинга.
`implement verify` использовать для проверки уже существующей реализации против design docs и DoD.

## Рекомендуемый briefing

```text
Контекст:
Прочитай:
- <список документов из docs/SGv7pipeline>
- <нужные файлы кода>

Проект:
- локальная модель: qwen 1.5B
- задача: Scene Generator JSON parsing
- canonical SG v7 dataset entrypoint: generate_dataset_v7.py
- legacy reference generator for comparison only: generate_dataset_v6.py
- целевая система: SG v7 graph-first pipeline

Цель:
<одна конкретная цель>

Что нужно сделать:
- <список задач>

Что не нужно делать:
- не менять unrelated parts
- не придумывать новую schema без необходимости
- не оптимизировать всё сразу

Ограничения:
- нужно учитывать ограниченную capacity 1.5B
- train format должен совпадать с runtime prompt format
- canonical JSON должен быть детерминированным
- corrected target должен иметь понятный provenance tier

Ожидаемый результат:
- <design doc / implementation plan / code patch / prompt pack / validator spec>

Definition of done:
- <чёткие критерии готовности>

Фокус внимания:
- <список failure modes>
```

## Когда контекста уже точно недостаточно

Нужно добавлять больше контекста, если задача:
- меняет runtime schema
- затрагивает несколько скриптов и training harness
- требует сравнения с текущим `v6` кодом
- требует реальных runtime failure examples

## Что лучше прикладывать дополнительно

Для implementation-агента:
- [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
- [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py)
- текущие runtime prompts и grammar
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- 5-10 реальных failure examples

Для eval-агента:
- frozen prompt set
- baseline metrics
- несколько raw LLM outputs

Для feedback-loop-агента:
- реальные логи accept/merge/reject
- формат corrected target JSON

## Практическое правило

Если агент должен:
- исследовать
- декомпозировать
- спроектировать

то документов `SGv7pipeline` почти наверняка хватит.

Если агент должен:
- писать код
- менять генератор
- менять eval scripts
- менять training pipeline

то к документам нужно добавить соответствующие исходники и 3-10 примеров реальных failure cases.
