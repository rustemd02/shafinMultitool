# Current State Report — Shafin Multitool / SET OS

Дата: 2026-09-03  
Назначение: фактическая стартовая точка для независимого guidance, не декларация готовности.

## 1. Короткий вердикт

В репозитории уже есть крупный iOS-продукт: Camera Coach, библиотека сцен, generator/AR workspace, recording review и storyboard. SET OS v2.6 существенно реализован в source. Но продукт пока нельзя честно назвать App Store-ready:

- текущая версия не закреплена как воспроизводимый clean candidate;
- качество распознавания композиционных ошибок не достигает доказанного release threshold;
- часть ML-цепочки отсутствует либо имеет нерешённый provenance;
- production backend не выбран и не контрактован;
- пять известных provenance/legal проверок намеренно блокируют release gate;
- нет текущего green full suite, подписанного archive и Apple/App Store Connect validation;
- камера/AR/REC остаются без обязательного доказательства на физическом устройстве;
- часть сохранённых UI evidence неверно ориентирована или показывает реальные layout-проблемы.

Следующий этап должен быть finishing program, а не продолжение арт-дирекшна.

## 2. Продуктовая цель 1.0

Главный продукт — ассистент для начинающей съёмочной команды:

1. Камера видит реальный кадр.
2. Приложение определяет практическую проблему композиции или подтверждает хороший кадр.
3. Даёт короткое конкретное действие: например, «смести объект левее», «подойди ближе», «оставь больше воздуха», «выровняй горизонт».
4. После движения повторно анализирует кадр и подтверждает улучшение либо корректирует совет.
5. Не мешает изображению: A24-сдержанность, советская полиграфическая сетка, функциональная плёнка и одна рисуемая marker-аннотация.

Scene Mode остаётся вторичным production flow: библиотека → генератор → AR workspace → storyboard/recording review.

## 3. Достижимая карта продукта

```text
Launch
└─ CommercialShell
   ├─ Camera
   │  ├─ Entry: resolving / intro / permission / requesting / blocked / ready
   │  ├─ Live: starting / interrupted / failed
   │  ├─ Coach: seeking / keep / corrective / fallback / explanation
   │  ├─ Lens switching / pause analysis / resume
   │  └─ A/B ROLL → Scenes
   └─ Scenes
      └─ Library
         ├─ empty / loaded / selected
         ├─ create / duplicate / delete / persistence failure
         └─ Generator + AR workspace
            ├─ screenplay and marker-name sheets
            ├─ parse / progress / failure / result
            ├─ AR search / placement / marking / live hints
            ├─ recording / playback / share
            ├─ storyboard tray / inspector / editor
            └─ Decision Trace
```

History stub не имеет production control и недостижим. `StageSelectionViewController`, старый `CameraScreenViewController` и `EditScriptViewController` считаются legacy-кандидатами: их не рестайлить и не удалять без отдельного решения. Debug/Performance/Benchmark не входят в product redesign.

## 4. Визуальный authority

Канон: `docs/implementation/ux/set-os-visual-policy.md`, SET OS v2.6.

- Советская полиграфия — сетка и плакатная типографика.
- A24 — сдержанность, кадр всегда hero-content.
- Плёнка — только функциональная механика: A/B ROLL, leader, честный timecode, contact sheet, perforation progress, montage seam.
- Микроскевоморфизм — пунктуация, а не физические бумажные контейнеры.
- Палитра: ink, warm white, один `setOrange`.
- Запрещены material/blur/shadow/gradient, generic cards, system-blue branding, fake thumbnails, зелёно-красная семантика.
- Стабильное состояние: максимум один annotation motif и один cinematic accent; буквальные детали ≤8% viewport.
- Marker рисуется по event ID; one-shot не повторяется при rotation/re-render.

Оригинальный визуальный референс и текущие screenshots приложены отдельно. Текущие снимки не все являются надёжным evidence: часть landscape-файлов физически portrait или отображается повёрнутой.

## 5. Что реально есть в source

### Camera Coach

- Камера, разрешения, lifecycle, lens discovery/switching.
- Детерминированный analysis pipeline и presentation state machine.
- DETR semantic segmentation и NIMA aesthetic evidence через Core ML.
- Semantic tip planner, pause reasoning, hybrid evidence fusion.
- Motion/event ledger, marker presentation, leader и thermal governor.
- Pause snapshot и review presentation.

Фактический data flow: `AVCaptureVideoDataOutput` → `FrameContext` → cadence 15/8/0.8 Hz → Vision face/person/saliency + horizon → lighting → gated DETR/NIMA → evidence aggregation → deterministic critique/recommendation → необязательные neural/VLM adjustments → UI. Это реальный offline pipeline, но product decision layer сегодня преимущественно эвристический. Pause повторно запускает DETR/NIMA на принятом pixel buffer, однако Vision/horizon/lighting могут быть age-gated samples, а не полностью свежей инференсией того же кадра.

### Scene Mode

- Persistence-backed library и маршрутизация.
- Generator/AR workspace.
- AR session/coaching/interruption/teardown plumbing.
- Recording owner/ledger, playback/share и retention work.
- Storyboard tray/inspector/editor и Decision Trace.

### Release infrastructure

- Workspace/shared scheme, Release configuration, bundle/privacy validators.
- SnapKit как единственный CocoaPod; vendored llama XCFramework.
- Debug fixtures/models исключаются из Release.
- EN/RU String Catalogs и bundled fonts.
- Большая тестовая поверхность: около 850 test methods в source. Это inventory, не доказательство прохождения.

## 6. ML: текущее состояние и главная неопределённость

### Имеющиеся артефакты

- `DETRResnet50SemanticSegmentationF16P8.mlpackage` — около 41.7 MB в Release bundle.
- `aesthetic_nima_mobilenet_fp16.mlpackage` — около 6.3 MB.
- Код ожидает `compact_neural_evidence_net`, но соответствующего production model artifact нет.
- GGUF `dataset_v9_event_sft_q4_k_m.gguf` около 1.1 GB присутствует в Resources, но исключён из Release.
- Remote VLM provider существует как environment-selected transport, однако production endpoint/provider/auth/consent/retention/cost не определены; default production configuration фактически disabled.
- Mock VLM provider существует и не является production доказательством.
- DeepCritic имеет contracts/coordinator/mock, но не имеет production provider или live composition.
- `VisionTracking` выполняет frame-by-frame detection, а не устойчивый identity tracking.
- DETR `confidence` вычисляется из площади connected component и не является calibrated probability.
- NIMA не имеет достаточной output normalization/finite/uncertainty validation; runtime при этом использует fixed thresholds для intent/composition/verdict confidence вопреки документированному ограничению AVA aesthetics.
- Lighting estimator включает subject в условный background mean; blur/noise эвристики могут выдавать взаимоисключающие или неизмеренные выводы по одному кадру.
- Release запрещает `.gguf`, но продолжает поставлять llama framework. Scene parsing в Release фактически падает на rule parsing; метрики v9.3 не связаны с checked-in release artifact/hash.

### Конфликтующие eval-результаты

Узкий более ранний прогон `out_semantic_real_runtime_after_r21a` показал 107/107 и 1.0 по ключевым метрикам. Более широкий поздний `out_semantic_real_runtime_v2_after_runtime_fix_r6` на 207 случаях показал:

| Metric | Result |
|---|---:|
| pass rate | 0.671498 |
| expected action hit | 0.748792 |
| forbidden action violation | 0.188406 |
| good-frame preservation | 0.875000 |
| technical gate | 0.962963 |
| confidence accuracy | 0.859903 |
| demo pass | 0.500000 |
| forbidden violations | 39 |
| missing expected actions | 52 |
| good-frame overcorrections | 12 |

Это не release quality. Идеальный ранний результат следует считать подозрением на слишком узкий набор, переобучение или leakage, пока не доказано обратное.

Full-v2 набор состоит из AI/synthetic first-pass labels без подтверждённого human gold. Сокращённый результат около 85% исключает ambiguous/subtle/weak cases и заменяет плохие примеры на более явные дефекты; это demo slice, а не доказательство generalization.

### Что требуется решить

- Какой минимальный on-device стек действительно нужен для 1.0.
- Оставлять ли DETR/NIMA, заменять ли их Apple Vision/собственной Core ML моделью или сочетать.
- Какие composition labels имеют операционное значение и переводятся в проверяемое действие.
- Как построить независимые train/validation/test splits по сценам/съёмкам, а не по соседним кадрам.
- Как калибровать confidence, abstention и good-frame preservation.
- Нужен ли backend вообще для 1.0. Если нужен, он должен быть только явным Deep Review, не скрытой зависимостью live loop.

## 7. Конкретные product/UI дефекты

1. Camera xmark вызывает SwiftUI `dismiss()` внутри hosting root и вероятно не меняет shell route; существующая проверка подтверждает наличие кнопки, а не результат нажатия.
2. Selected library row построен как внешняя Button с вложенными Open/Delete Buttons. Это создаёт overlap, hit-testing и VoiceOver risk; problem screenshot приложен.
3. RU generator может показывать mixed-language raw error, например `ОШИБКА AR: Unsupported configuration.`.
4. ECO пока fixture-only, потому что эффективный runtime signal отсутствует.
5. Generator clarification недостижим при текущем parser contract; retry/cancel recovery имеют неполного behavior owner.
6. Сохранённые Package 3–6 screenshots частично неверно ориентированы. Package 1 evidence directories, указанные документом, отсутствуют.
7. RU/EN catalogs заполнены механически, но native-English editorial review и полная accessibility matrix не закрыты.
8. Незавершённый recording race: stale AR coordinator failure может снять claim после смены owner; start recording может завершиться после начала teardown. Это необходимо перепроверить в актуальном diff, затем исправить на owner-token boundary и покрыть узким deterministic race check.

## 8. Release blockers

### P0

- Пять hard-coded provenance/legal blockers: llama redistribution/notices, DETR, NIMA, `Circle.usdz`, `Person.usdz`.
- Возможный недоучёт provenance AppIcon/branding/material assets.
- 75 modified tracked files, 28 untracked top-level entries и примерно 195 untracked files на момент аудита; критический production candidate не является clean immutable baseline.
- Release validator всегда формирует пять blockers и выходит nonzero; orchestrator не доходит до следующей стадии. После юридического решения gate всё равно должен читать машинный статус, а не hard-coded count.
- Нет текущего полного green test run. Последний сохранённый широкий unit audit: 593 total / 496 passed / 94 failed / 3 skipped.
- Нет signed archive/export/codesign inspection/Apple Validate/App Store Connect validation.
- Не завершены privacy policy, Support URL, App Privacy answers, age rating, export compliance и решение по remote VLM/Speech disclosure.

### P1

- Notices не доказаны внутри распространяемого bundle.
- Target family сейчас iPhone+iPad, хотя продукт описан как iPhone-first; iPad evidence отсутствует.
- Нет минимального CI.
- Release gate summary говорит о 6 fixtures, тогда как текущий fixture script содержит 11.
- Значимая часть процитированных `.xcresult` отсутствует или неполна; результаты под ignored `build/` не являются durable evidence.
- Deployment targets расходятся: project 16.2, app/UI 17.0, unit 17.2, Podfile 14.0.

## 9. Что симулятор не доказывает

Обязательная физическая проверка остаётся для:

- first-launch camera/microphone/Speech/Photos permissions и recovery;
- реальных lenses, ориентации и hardware interruption;
- ARKit world tracking, placement, map restore и teardown timing;
- физической записи, audible playback, share/export, A/V sync;
- low disk, OS kill во время Pending promotion и cold-launch recovery;
- DETR/NIMA latency, sustained FPS, memory, thermal transitions;
- real Speech/network failure modes.

До устройства Codex может автономно закончить source correctness, deterministic simulation, ML dataset/eval tooling, release gates, privacy/provenance records, clean candidate preparation и signed archive prerequisites. Но нельзя обещать владельцу «100% уверенность на телефоне» без device run.

## 10. Решения, которые должен принять guidance

1. Чёткий App Store 1.0 product cut: что ship, что скрыть, что удалить из claims.
2. On-device ML architecture и измеримые quality thresholds.
3. Dataset/training/eval program с leakage guard и human review.
4. Backend: none либо минимальный opt-in Deep Review с конкретным API/privacy/cost contract.
5. iPhone-only или реальная поддержка iPad.
6. Порядок закрытия correctness → ML quality → release/legal → device → TestFlight/App Store.
7. Tracker, который не позволяет снова уйти в бесконечные мудборды и декоративную полировку.

## 11. Репозиторные ограничения

- Не коммитить, push, stash, reset, clean или создавать worktree без отдельного разрешения владельца.
- Не перезаписывать пользовательские uncommitted changes.
- Не трогать `docs/thesis/litreview*`.
- Не использовать iPhone 17 Pro.
- CommercialShell routes, async teardown и accessibility IDs сохранять, если change request не доказывает необходимость миграции.
- Claim `release-ready` разрешён только после свежего evidence.
