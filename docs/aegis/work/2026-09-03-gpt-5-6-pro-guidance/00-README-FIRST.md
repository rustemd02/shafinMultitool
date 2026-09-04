# Shafin Multitool / SET OS — handoff для ChatGPT 5.6 Pro

Дата снимка: 2026-09-03, Europe/Moscow  
Ветка: `store`  
HEAD на момент сборки: `c61e988886499c84c9ff9ec760f9ace5759db001`

## Зачем этот пакет

Это не новый дизайн-документ и не запрос на мудборды. Это снимок текущего продукта для независимого технического и продуктового разбора: что действительно реализовано, что только заявлено, какие части ML/backend/release отсутствуют и какой конечный трек доведёт приложение до проверяемого App Store release candidate.

Единственный визуальный authority внутри репозитория — `docs/implementation/ux/set-os-visual-policy.md`. Файлы этого handoff лишь объясняют состояние и не заменяют его.

## Порядок чтения

1. `01-CURRENT-STATE-REPORT.md` — сжатая карта продукта, факты, риски и открытые вопросы.
2. `02-GPT-5.6-PRO-PROMPT.md` — задача и обязательный формат ответа.
3. `03-UPLOAD-MANIFEST.md` — состав файлов и визуальных evidence.
4. `04-CHECKSUMS.md` — целостность снимка и результат credential-like scan.
5. `10-camera-coach-source.txt` — production source Camera Coach.
6. `11-scene-mode-source.txt` — production source Scene/Generator/AR/Storyboard/Shell.
7. `12-tests-and-release-source.txt` — тесты, release scripts и конфигурация проекта.
8. `13-authority-and-evidence-docs.txt` — политика, acceptance, product plan, checkpoints и evidence.
9. `14-ml-eval-and-dataset-snapshot.txt` — ML/eval scripts, labels и два конфликтующих результата оценки.
10. Визуальные файлы из manifest — референс направления и текущие проблемные production screenshots.

Текстовые source-снимки — механическая конкатенация файлов с заголовками `===== FILE: ... =====`. Они нужны для анализа, но не являются чистым Git checkout. Если документ и код расходятся, попросите считать код фактом реализации, а документ — заявленным контрактом, пока контракт не подтверждён тестом/evidence.

## Жёсткие ограничения для рекомендаций

- Не предлагать ещё один moodboard, параллельную дизайн-систему или полный визуальный reset.
- Не выдавать simulator/source evidence за доказательство камеры, ARKit, микрофона, Photos, REC/playback, A/V sync, thermal и hardware timing.
- Не считать текущий checkout воспроизводимым: он содержит крупный набор modified/untracked изменений.
- Не считать приложение release-ready без чистой воспроизводимой сборки, закрытого provenance/privacy, полного целевого quality gate и подписанного archive/Apple validation.
- Не требовать iPhone 17 Pro: этот симулятор зарезервирован владельцем и запрещён для проекта.
- Не предлагать правки `docs/thesis/litreview*`.
- Не менять CommercialShell routes, async teardown и существующие accessibility identifiers без доказанной необходимости и миграционного плана.
- Не маскировать product gaps новой полировкой UI.

## Что должен дать Pro

Один исполнимый план App Store 1.0: жёсткий product cut, целевая архитектура ML и при необходимости backend, измеримые release thresholds, упорядоченный tracker с зависимостями и acceptance evidence, список первых автономных задач для Codex и отдельный список действий, которые действительно требуют владельца, физического устройства, юридического решения или аккаунта Apple.
