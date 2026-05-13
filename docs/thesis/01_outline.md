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
| Вводный архитектурный блок без выделения подпункта | new | 1-2 стр. | `litreview`, `diploma.md`, `docs` | CL-BR-001, CL-ARCH-001 | Общая схема системы и поток данных между модулями. |
| 2.1. Архитектура модуля генерации структурированного представления сцены | new | 4-5 стр. | `diploma.md`, `code`, `docs/SGv*` | EV-ARCH-001, EV-SG7-001, EV-SG8-001, EV-SG9-001 | Диаграмма Scene Generator runtime/data flow. |
| 2.2. Архитектура модуля анализа кадра и формирования рекомендаций | new | 4-5 стр. | `code`, `docs/cameraanalysis` | EV-CA-001, EV-CA-002 | Pipeline diagram: snapshot -> semantics -> critique -> planner. |

## 3. Реализация программного решения

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| 3.1. Реализация модуля генерации структурированного представления сцены | new | 8-10 стр. | `code`, `docs/SGv*`, `tests` | EV-IMPL-001, EV-SG7-002, EV-SG8-002, EV-SG9-002, EV-BUNDLE-001 | Таблица Swift/Python modules for Scene Generator. |
| 3.2. Реализация модуля анализа кадра и формирования рекомендаций | new | 6-8 стр. | `code`, `docs/cameraanalysis`, `tests` | EV-CA-001, EV-CA-002, EV-CA-003 | Camera Analysis implementation pipeline. |

## 4. Экспериментальная часть

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Методика оценки Scene Generator | new | 3-4 стр. | `experiments/sc_benchmark`, `docs/SGv7pipeline/eval` | EV-EVAL-001 | Таблица метрик. |
| Сравнение base/v6/v7/v8/v9 | new | 5-7 стр. | benchmark artifacts | EV-MET-001, EV-MET-002, EV-MET-003, EV-MET-004 | Основная таблица метрик, граф improvements. |
| Live smoke and limitations | new | 2-3 стр. | `diploma.md`, tests | EV-LIVE-001, EV-LIVE-002 | Таблица positive/negative live evidence. |
| Оценка Camera Analysis | new | 3-4 стр. | `docs/cameraanalysis/eval/out_*` | EV-CA-EVAL-001, EV-CA-EVAL-002 | Таблица deterministic vs legacy and hybrid gates. |

## 5. Заключение

| Глава/раздел | Статус | Объём | Источник | Evidence/Claim IDs | Таблицы/диаграммы |
|---|---|---:|---|---|---|
| Итоги работы | new | 2-3 стр. | all verified claims | CL-CONTR-001, CL-CONTR-002, CL-CONTR-003 | Таблица goals/tasks completion. |
| Ограничения | new | 2-3 стр. | limitations claims | CL-LIM-001, CL-LIM-002, CL-LIM-003 | Limitation matrix. |
| Направления развития | new | 1-2 стр. | `diploma.md`, open needs_source | CL-NEEDS-001, CL-NEEDS-002 | Roadmap figure. |

## Рекомендуемый итоговый баланс страниц

| Блок | Страницы |
|---|---:|
| Теория из litreview | 24-31 |
| Bridge sections | 5-8 |
| Архитектура и реализация | 23-29 |
| Эксперименты | 10-14 |
| Заключение | 5-7 |
| Итого | 60-70 |
