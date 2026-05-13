# Thesis Brief

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`
Protected litreview: `docs/thesis/litreview.md`

## Предполагаемая тема ВКР

Разработка мобильной интеллектуальной системы поддержки процессов видеопроизводства с использованием структурированного сценического парсинга, локального ML/LLM-инференса и объяснимого анализа кадра.

## Объект исследования

Процессы мобильного видеопроизводства на этапах предварительного производства и съёмки, включая превизуализацию сцен, структурирование сценарного описания и анализ композиционно-технического качества кадра.

## Предмет исследования

Методы и архитектурные решения для локальной и гибридной обработки сценических описаний и видеокадров на мобильном устройстве: structured output generation, deterministic compilation, локальный LLM-инференс, computer vision, explainability contracts and evaluation gates.

## Цель

Разработать и экспериментально оценить прототип мобильной системы, которая преобразует текстовое описание сцены в структурированное представление для превизуализации и формирует объяснимые рекомендации по улучшению кадра в процессе съёмки.

## Задачи

1. Проанализировать существующие методы оптимизации мобильного видеопроизводства на основе защищённого литературного обзора `docs/thesis/litreview.md`.
2. Спроектировать архитектуру Scene Generator, разделяющую ML/LLM-generated intermediate output и deterministic compilation в итоговый `SceneScript`.
3. Реализовать и описать data/training/eval pipeline для Scene Generator: SG v7, SG v8, SG v9 and chunk-native bundle pipeline.
4. Спроектировать и описать Camera Analysis pipeline с feature snapshots, deterministic critique, explainability contract, neural evidence wrapper and semantic tips.
5. Сформировать evidence-first экспериментальную методологию на основе benchmark/eval artifacts, не заявляя неподтверждённых метрик.
6. Зафиксировать ограничения текущего прототипа и направления дальнейшей работы.

## Практическая значимость

Практическая значимость состоит в создании воспроизводимого iOS-прототипа, который поддерживает два прикладных сценария: подготовку структурированной сцены для превизуализации и объяснимую оценку кадра в процессе съёмки. Отдельная ценность проекта заключается в трассируемых контрактах между runtime, data pipeline and evaluation, что позволяет безопасно развивать модельные компоненты без скрытого drift.

## Научно-техническая новизна

| Направление | Формулировка новизны | Evidence |
|---|---|---|
| Structured scene parsing | Переход от прямой генерации финального JSON к промежуточным контрактам `ScenePlanIR` and V9 slot/event table с deterministic compiler. | EV-SG8-001, EV-SG9-001 |
| Evidence-first training pipeline | SG v7 строит canonical scene semantics до textual variants, снижая зависимость target JSON от teacher-generated шума. | EV-SG7-001, EV-SG7-002 |
| Runtime traceability | В V9 verifier/recovery layer reason codes фиксируют repairs and coverage issues вместо silent correction. | EV-SG9-002 |
| Explainable camera analysis | Camera Analysis описывает frame critique через domain contracts, evidence refs and explainability gates, а не только через scalar aesthetic score. | EV-CA-001, EV-CA-002 |
| Mobile-first AI architecture | Прототип комбинирует локальный inference, deterministic fallback, cadence/thermal policies and benchmark gates. | EV-ARCH-001, EV-CA-003 |

## Что уже покрыто в litreview

Литературный обзор уже покрывает предметную область мобильного видеопроизводства, ограничения мобильных устройств, AR/previsualization, image aesthetic assessment, mobile video understanding, automated editing and общую проблему отсутствия комплексных мобильных решений.

## Что нужно раскрыть в практической части

1. Архитектуру Scene Generator и границы между deterministic and ML/LLM-based слоями.
2. Эволюцию SG v7 -> SG v8 -> SG v9 -> chunk-native bundle pipeline.
3. Интеграцию локальных моделей через llama.cpp/GGUF and constrained output contracts.
4. Camera Analysis contracts, explainability pipeline and neural evidence wrapper.
5. Экспериментальные результаты из frozen benchmark/eval artifacts, включая отрицательный live smoke результат для v8 and improved V9 evidence.
6. Ограничения прототипа: неполный монтажный контур, зависимость части claims от demo/eval artifacts, conditional gates for hybrid Camera Analysis.

## Честные ограничения текущего проекта

| Ограничение | Статус |
|---|---|
| Полный automated editing pipeline не реализован в production runtime. | limitation |
| Часть SG metrics получена на seed 42 and frozen eval bundle; обобщение требует дополнительных seeds/datasets. | limitation |
| Camera Analysis hybrid neural path имеет demo-level smoke with `mobile_blocked` verdict; deterministic v1 baseline сильнее подтверждён. | limitation |
| Некоторые bibliographic claims litreview требуют отдельной проверки источников и не должны считаться verified через код. | litreview_unchecked |
| V9 live smoke подтверждён через log in `diploma.md`, но финальный parity package should be attached before defense freeze. | partially_verified |
