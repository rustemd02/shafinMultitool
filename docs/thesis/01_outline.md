# Thesis Outline

Target length: 60-70 pages
Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

## 1. Уже существующая теоретическая часть из litreview

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Введение и постановка проблемы | existing | 4-6 стр. | `litreview` | CL-LR-001, CL-BR-001 | Схема этапов видеопроизводства. |
| Методология литературного обзора | existing | 2-3 стр. | `litreview` | CL-LR-002 | Таблица критериев включения/исключения. |
| Этап предварительного производства | existing | 7-9 стр. | `litreview` | CL-LR-003, CL-BR-002 | Таблица 1/2 из litreview, bridge-схема к Scene Generator. |
| Этап съёмки | existing | 7-9 стр. | `litreview` | CL-LR-004, CL-BR-003 | Таблица 3 из litreview, bridge к Camera Analysis. |
| Этап монтажа | existing | 4-6 стр. | `litreview` | CL-LR-005 | Таблица 4 из litreview; отметить как контекст, не как реализованный вклад. |
| Выводы обзора | needs_bridge | 2-3 стр. | `litreview`, `diploma.md` | CL-BR-001, CL-BR-004 | Таблица “theoretical gap -> project response”. |

## 2. Архитектура программного решения

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Глава 2. Архитектура программного решения | draft | 3-5 стр. | `litreview`, `diploma.md`, `docs`, `code` | CL-BR-001, CL-BR-002, CL-BR-003, CL-ARCH-001 | Общая схема системы и поток данных между двумя функциональными модулями. |

## 3. Модуль генерации структурированного представления сцены

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Глава 3. Модуль генерации структурированного представления сцены | new | 10-14 стр. | `code`, `docs/SGv*`, `tests`, `diploma.md` | EV-IMPL-001, EV-SG7-002, EV-SG8-002, EV-SG9-002, EV-BUNDLE-001, EV-LLM-001, EV-GBNF-001 | Таблица Swift/Python modules for Scene Generator; V9 event table verification/compile pipeline. |

## 4. Модуль анализа кадра и формирования рекомендаций

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Глава 4. Модуль анализа кадра и формирования рекомендаций | new | 8-12 стр. | `code`, `docs/cameraanalysis`, `tests` | EV-CA-001, EV-CA-002, EV-CA-003 | Camera Analysis implementation pipeline; contracts and explainability trace table. |

## 5. Экспериментальная часть

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Методика оценки Scene Generator | new | 3-4 стр. | `experiments/sc_benchmark`, `docs/SGv7pipeline/eval` | EV-EVAL-001 | Таблица метрик. |
| Сравнение base/v6/v7/v8/v9 | new | 5-7 стр. | benchmark artifacts | EV-MET-001, EV-MET-002, EV-MET-003, EV-MET-004 | Основная таблица метрик, граф improvements. |
| Live smoke and limitations | new | 2-3 стр. | `diploma.md`, tests | EV-LIVE-001, EV-LIVE-002 | Таблица positive/negative live evidence. |
| Оценка Camera Analysis | new | 3-4 стр. | `docs/cameraanalysis/eval/out_*` | EV-CA-EVAL-001, EV-CA-EVAL-002 | Таблица deterministic vs legacy and hybrid gates. |

## 6. Заключение

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Итоги работы | new | 2-3 стр. | all verified claims | CL-CONTR-001, CL-CONTR-002, CL-CONTR-003 | Таблица goals/tasks completion. |
| Ограничения | new | 2-3 стр. | limitations claims | CL-LIM-001, CL-LIM-002, CL-LIM-003 | Limitation matrix. |
| Направления развития | new | 1-2 стр. | `diploma.md`, open needs_source | CL-NEEDS-001, CL-NEEDS-002 | Roadmap figure. |

## Рекомендуемый итоговый баланс страниц

| Блок | Страницы |
|---|---:|
| Теория из litreview | 24-31 |
| Bridge/architecture sections | 4-6 |
| Модуль генерации сцены | 10-14 |
| Модуль анализа кадра | 8-12 |
| Эксперименты | 10-14 |
| Заключение | 5-7 |
| Итого | 60-70 |
