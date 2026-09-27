# UI-009 — iPad/rotation: сверка контрактных доков и PortraitUpsideDown (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `4a5e22b7` · Ветка: `store`
Задача: **UI-009** (закрытие строки; база — ресипт `2026-09-22-ui-009-ipad-rotation.md`:
iPad capability на 2 симуляторах, реальная геометрия, контракт-тесты 18/18)
Делегировано («owner-delegated 2026-09-27»): сверка stale-строки `UIRequiresFullScreen=YES`
(§19 п.13) и ротация PortraitUpsideDown.

## 1. Сверка доков (§19 п.13) — четыре точки

Источник истины в коде: `shafinMultitool.xcodeproj/project.pbxproj` —
`INFOPLIST_KEY_UIRequiresFullScreen = NO` во **всех четырёх** конфигурациях;
`shafinMultitoolTests/iPadPlatformContractTests.swift:31` —
`testWindowingDoesNotUseScaledFullScreenCompatibilityMode` требует
`UIRequiresFullScreen == false` («master plan §3.8 requires resizable iPad
layouts with native control sizes»). Переход сделал владелец 2026-09-16
(commit `d4815f3`, diploma.md). Обновлено:

| Документ | Было | Стало |
|---|---|---|
| `ipad-platform-contract-v1.md` | «`UIRequiresFullScreen = YES`: the app does not claim multitasking…» | зачёркнуто + dated-коррекция: NO с `d4815f3`, resizable windows, multitasking не заявляется (физика — DEV-011) |
| `windowing-policy-v1.md` | «с `= YES` окно нельзя уменьшить → recovery string unreachable» | посылка устарела; product-решение: строка «expand window» не требуется для 1.0 (честность держит 320pt-минимум камеры/AR → unavailable-состояние); факт: **enforcement 320pt-правила в коде не найден** (см. §3) |
| `ui-states-matrix-v1.md:13` | «`UIRequiresFullScreen=YES`» | зачёркнуто + ссылка на коррекцию |
| claim `CL-CA-049` (`docs/thesis/04_claim_registry.md`) | «single full-screen policy… `= true`» | историческая запись сохранена, добавлена **Correction 2026-09-27** со ссылками на код/доки/ресипт |

Правка `docs/thesis/04_claim_registry.md` **не закоммичена**: файл несёт чужие
незакоммиченные thesis-изменения (рабочее дерево владельца) — правка оставлена
в рабочем дереве, чтобы не смешивать чужую работу в коммитах.

## 2. PortraitUpsideDown — живая ротация (был остаток)

Добавлен фокусный метод `CameraCoachLaunchUITests.testCameraCoachSurfaceSurvivesPortraitUpsideDownRotation`
(тот же диагностический класс, что вёл ротационные проверки UI-009 2026-09-22):
portrait → **portraitUpsideDown** → portrait; pause-кнопка и «Сцены» остаются
hittable после каждой ротации. Прогон на **iPad-симуляторе**
`SETOS UI preflight iPad 20260916` (`AE5076C4-…`):

| Check | Итог |
|---|---|
| `iPadPlatformContractTests` (universal families, 4 ориентации объявлены, resizable windows, minOS 17.0) | **4 / 0** |
| `testCameraCoachSurfaceSurvivesPortraitUpsideDownRotation` (новый) | **passed** (20.9 c) |
| `testCameraCoachSurfaceSurvivesPortraitLandscapeRotation` | **passed** (19.5 c) |
| Итог прогона | `** TEST SUCCEEDED **`, EXIT=0 |

Плюс unit-покрытие самой геометрии upside-down уже существовало
(`CameraDisplayTransformTests`, `CameraCoordinateSpaceTests`,
`SemanticDirectionBehaviorTests`, `AppleRecordingAdaptersTests`).

## 3. Новая находка (честно записана)

Правило контракта «минимум 320pt на camera/AR-окно, ниже — unavailable»
**не имеет найденной точки enforcement/теста** в текущем дереве (grep по
коду/тестам; строка контракта говорит "Enforced where the surface is hosted").
Не подгонял код под док: правило остаётся контрактным требованием, живая
проверка поведения в маленьком окне (Split View/Stage Manager) перенесена в
**DEV-011** (физический iPad) как named-пункт.

## 4. Статус

UI-009 → **`DONE`**: iPad contract реализован/подтверждён (18/18 →
дополнительно 4/0 контракт + 2 ротации), landscape принят реальной геометрией
(2026-09-22), PortraitUpsideDown докручен, stale-доки сверены (§19 п.13 закрыт).
Остатки — **физический iPad** (мультитаскинг/320pt-окно, DEV-011) и физическая
приёмка device-family (DEV-012) — за своими строками.
