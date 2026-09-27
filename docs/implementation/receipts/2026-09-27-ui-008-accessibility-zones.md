# UI-008 — accessibility: зоны D/E/F/H, порядок фокуса, reveal-флак (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `a7c5f412` · Ветка: `store`
Задача: **UI-008** (закрытие строки; база — ресипт `2026-09-22-ui-008-accessibility.md`:
зоны A/B/C/G, live-region cadence, regionWords ×7 ключей)
Среда: **симулятор** iPhone 17e / iOS 26.5 — не физическое устройство.

## 1. Аудит оставшихся зон D/E/F/H (по строкам кода + тестовое покрытие)

| Зона | Владельцы (code) | Interactive / a11y атрибутов | Тестовое покрытие (прогоны этого запуска) | Вердикт |
|---|---|---|---|---|
| D — Cloud review/consent | `CameraCloudReviewControls.swift`, `SETCameraCloudConsentFixtureRoot.swift` | 2 кнопки (обе с ролью/действием) / 25 a11y-атрибутов; disclosure в ScrollView с идентификатором `camera_cloud_consent_scroll` | `testCloudConsentDisclosureFitsAndCanBeCancelledInBothLanguages`, `…ReachesApprovalInLandscapeWithDynamicType` — green в M-UI прогоне (действия видимы/достижимы на XXL, обе локали, обе ориентации; assert'ы `assertCloudConsentActionVisible`) | PASS |
| E — Recording/Export | `CameraRecordingControlsView.swift` | 3 / 18 (labels+identifiers на play/record/controls) | `testProductionInterruptedFixtureUsesLifecycleCopy`, pause/резюм-цепочки — green; реальная запись/аудиосинк — DEV-008 (физика) | PASS (симуляторная часть) |
| F — Scene Mode | `SceneInputSheet.swift`, `SceneGeneratorView.swift`, `ARSceneContainer.swift`, `LegacySceneGeneratorCameraShell.swift` | TextField + кнопки с локализованным `localizedTextKey`; error band/storyboard/leader — с labels/identifiers | `SETGeneratorProductionUITests` — класс green в M-UI прогоне (workspace/input sheet/error band/storyboard/leader, RU/EN, reduce motion, dynamic type) | PASS |
| H — Privacy/deletion | `SETPrivacyInformationView.swift` (+ library→privacy путь) | 3 / 33 (закрыть, notice-строки, account) | `SETPrivacyUITests` — 2/0 ×2 прогона после фикса reveal (§3); путь library→privacy→full license→back проверен end-to-end | PASS |

Дополнительно сверены скриншоты permission/privacy-состояний (M-UI lane,
OCR 2026-09-27) — copy без raw-ключей и debug-строк.

## 2. Порядок фокуса live-surface

Вместо рискованной ZStack-реструктуризации (см. остаток 2026-09-22) —
детерминированный порядок через `accessibilitySortPriority(100)` на командной
полосе (`SETCameraCommandBand`): VoiceOver в контейнере live-surface должен
входить в primary instruction **до** HUD-хрома (timecode/tally), объявленного
раньше в ZStack. Свойство меняет только accessibility-порядок, layout не
трогается (нулевой визуальный риск). **Честная граница:** поведение реального
VoiceOver-фокуса на этом изменении не проверялось (нет локального механизма
прогона VoiceOver) — остаётся DEV-002/UI-013; закреплено только декларативно
+ зелёной a11y-зоной тестов.

## 3. Reveal-флак зоны H (классифицирован и закрыт)

`SETPrivacyUITests testLibraryPrivacyContainsFullLicenseAndReturnsToLibrary`
(red в M-UI прогоне 2026-09-27, `:88`; 2/2 green в изоляции) — root cause:
flick-жест reveal-цикла не укладывался в бюджет 20 жестов под нагрузкой.
Исправление: **controlled scroll** (slow velocity + hold 0.2 c) — тот же
приём, что в `placementDrag(controlledScroll:)`; утверждения не ослаблены,
бюджет не увеличен. Прогон класса после фикса: **2/0 и 2/0** (два прогона).

## 4. Проверки

| Check | Итог |
|---|---|
| `shafinMultitoolTests/CameraCoachAccessibilityPresentationTests` | **8 / 0** |
| `shafinMultitoolTests/CameraOverlayUXPresentationTests` | **31 / 0** |
| `shafinMultitoolUITests/SETPrivacyUITests` ×2 после фикса | **2/0, 2/0** |
| M-UI lane 2026-09-27 (D/E/F классы) | green (см. UI-003/004 ресипт) |

## 5. Статус

UI-008 → **`DONE`**: Done-when строки (VoiceOver order — декларативно §2,
labels/hints — все 8 зон аудированы, live region cadence и target-overlay
словами — приняты 2026-09-22) выполнен. Остаток — **физический VoiceOver
journey** (человек без зрения) → DEV-002/UI-013; формальный a11y-приёмочный
прогон на устройстве — часть DEV-012.
