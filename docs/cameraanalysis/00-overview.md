# 00. Overview

## Проблема

Текущий camera-модуль уже умеет:
- получать кадры с камеры;
- выделять людей, лица и saliency;
- оценивать свет, горизонт и эстетический score;
- показывать простые подсказки в live и список советов в pause.

Но системные проблемы текущего решения такие:
- подсказки слишком эвристические и короткие;
- почти нет объяснимости уровня "почему кадр хороший/плохой";
- система плохо понимает cinematic intent сцены;
- нет явного слоя semantic critique;
- нет структурированного контракта между анализом, объяснением и UI;
- нет deterministic pipeline для поэтапной реализации через AI-агентов.

## Почему текущей версии уже недостаточно

Сильные стороны текущей реализации:
- уже есть многопоточный camera pipeline;
- уже есть разделение по частотам вычислений;
- уже есть полезные fast signals;
- уже есть UX-паттерн `live + pause`.

Ограничения текущей реализации:
- `SuggestionEngine` в основном опирается на local heuristics;
- нет scene-aware интерпретации;
- нет формальной модели `strengths / issues / actions`;
- нет explainability trace;
- нет отдельно оформленного research-grade pipeline;
- трудно делить работу на безопасные PR-юниты.

## Что такое `Camera Analysis v1`

`Camera Analysis v1` — это не просто новый экран или более "умные" тексты.

Это полный explainable pipeline:
0. baseline freeze и contract фиксация
1. deterministic feature aggregation
2. primary subject и scene semantics
3. structured critique engine
4. recommendation planning
5. live hint projection
6. pause deep analysis
7. optional LLM-assisted explanation
8. eval harness
9. runtime feedback loop

## Ограничения мобильного устройства

Pipeline должен учитывать:
- ограниченный compute budget iPhone;
- риск перегрева;
- ограничения latency в live;
- невозможность запускать тяжелый reasoning на каждом кадре;
- необходимость fallback-а при недоступности тяжелых стадий.

Поэтому в `v1` обязательно должны быть:
- cascade-by-cost architecture;
- четкое разделение `live` и `pause`;
- offline-first baseline;
- explainability contract;
- контролируемый LLM usage, а не "LLM as source of truth".

## Цели качества

Pipeline должен улучшить:
- правдоподобность объяснений;
- полезность рекомендаций;
- стабильность live hint-ов;
- качество pause-разбора;
- демонстрируемость "до/после" для комиссии;
- прозрачность причин, по которым дан совет.

## Не-цели

- не делать универсальный camera coach для всех жанров съемки;
- не пытаться решить всю cinematography теорию в `v1`;
- не делать full server dependency обязательной;
- не строить giant black-box model without traceability;
- не переписывать весь текущий camera stack одним PR.
