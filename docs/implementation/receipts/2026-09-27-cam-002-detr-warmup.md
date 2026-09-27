# CAM-002 — production heavy-model warm-up: закрытие contention-корневой причины

Дата: **2026-09-27** · HEAD: `4c73605` · Ветка: `store`
Задача: **CAM-002** (bounded slice — production heavy-model lifecycle; строка остаётся
`PARTIAL`: copy-drift пара pseudo-UI — решение владельца §19 п.11, итоговая
классификация — в CAM-022 матрице)
Тулчейн: Xcode 27.0 / iOS SDK 27.0 · Destination `id=1F680A42-CEB3-43E8-9CED-52F874962A62`
(iPhone 17e, iOS 26.5, существующий симулятор), serial-режим
(`-parallel-testing-enabled NO -collect-test-diagnostics never`).

## 1. Корневая причина (по ресипту 2026-09-22-cam-002 и коду)

Единственный serial-флак `testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries`
(1/20 до починки) — не order-artifact, а **холодный старт тяжёлой модели в production
lifecycle**: первый DETR-inference на экземпляр (`DETRDetector` → `MLModel` load +
первый `VNCoreMLRequest`) занимал 1676–2192 мс против 607–656 мс в steady state;
на этот window production high-priority путь по дизайну сбрасывал кадры
(`[PIPE_HIGH]` получил 2 из 10 сэмплов), и 2-секундные окна фикстуры голодали.

## 2. Исправление (production lifecycle, не тестовый retry/disable)

- `DETRDetector.warmUp(waitUntilDone:)` — **один** throwaway-inference на синтетическом
  64×64 буфере на собственной serial-очереди детектора: холодный старт платится до того,
  как от него зависят кадровые окна. Идемпотентно, single-flight; `detect`, поставленный
  в очередь после warm-up, всегда выполняется за ним. `waitUntilDone: false` — продакшен
  (fire-and-forget), `true` — тестовый harness (bounded wait ≤30 c).
- `AnalysisPipeline.warmUpHeavyModels(waitUntilDone:)` — единая точка прогрева
  тяжёлых моделей пайплайна (сейчас DETR; расширяемо).
- Production-точки: `ContentView.makeCameraCoachDependencies()` и роут UI-тестов
  (`SceneDelegate`) вызывают warm-up сразу при создании пайплайна — во время
  permission/intro, до потока кадров.
- Shared test harness `makeCapturePathHarness` (`CameraCoachClosedLoopTests` —
  зона Own CAM-002) вызывает `warmUpHeavyModels(waitUntilDone: true)` до первого
  `deliverCaptureSample`: кадровые окна больше не пересекаются с холодным стартом.

Ни одно assert не ослаблено, ничего не отключено и не повторено «на удачу»;
утверждения фикстуры (baseline/scene-cut publication в 2-секундных окнах) не тронуты.

## 3. Проверки (serial, симулятор — не физическое устройство)

| Check | Результат |
|---|---|
| `DETRDetectorTests` (включая новый `testWarmUpIsIdempotentAndDetectionAfterwardsCompletes`) | **8 / 0** |
| `CameraCoachClosedLoopTests` (полный класс, прогретый harness) | **29 / 0** |
| `…SceneCutRejectsLatePreCutSampleAndRetries` ×5 повторных запусков | **5/5 passed** (плюс 1/1 внутри класса = 6/6 после починки; до починки — 1 red на 20 serial-прогонов) |
| M0 smoke lane (blocking-минимум проекта, 13 масок required_check) | **133 / 0** |
| Сборка app-таргета (Pods prebuild обход Xcode 27.0 + -project lane) | BUILD SUCCEEDED, rc=0 |

Все прогоны — симулятор iPhone 17e/iOS 26.5. Это НЕ заменяет физическое устройство
(DEV-004/005) и не заявляет физическую latency/thermal-приёмку (ML-016).

## 4. Честные границы

- **Не воспроизведено ≠ доказано отсутствие:** флак был ~5%; 6 зелёных прогонов после
  починки — честные свидетельства, а не математическое доказательство. Итоговая
  серийная квалификация — в CAM-022 матрице.
- **Copy-drift пара pseudo-UI** (`testSceneControlRuntimeEN…/RU…`) не входит в этот слайс:
  тестовая литера существует только в тесте, shipped keys несут другую копию —
  stale oracle vs осознанная смена копии = **решение владельца (§19 п.11)**,
  release-gated до решения.
- `testTorchStateResetsOnRelease` (E-class, device-gated) флакует на тулчейне — не
  затронут и не заявлен закрытым.
- Warm-up выполняется на симуляторе/CPU по-разному против физического ANE; физическая
  польза (первый inference в live-окне) ожидается той же природой, но физически не
  измерялась — DEV-005/ML-016.

## 5. Файлы

`shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift`,
`shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (метод
`warmUpHeavyModels`), `shafinMultitool/Multitool2Module/ContentView.swift`,
`shafinMultitool/Resources/SceneDelegate.swift`, `shafinMultitoolTests/CameraCoachClosedLoopTests.swift`
(harness), `shafinMultitoolTests/DETRDetectorTests.swift`. Scratch DerivedData/логи —
в session-scratchpad (`cam002/`), удаляются вместе с ним; симуляторы не создавались и
не удалялись.
