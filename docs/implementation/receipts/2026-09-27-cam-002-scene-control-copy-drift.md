# CAM-002 — SceneControl copy drift: вердикт stale oracle и перепрогон пары

Дата: **2026-09-27** · HEAD: `6dac68cd5c55750740afd6ea0695591ce61225e2` · Ветка: `store`
Задача: **CAM-002** (финальный остаток строки — copy-drift pseudo-UI пара, §19 п.11;
contention-корневая причина закрыта ранее, `receipts/2026-09-27-cam-002-detr-warmup.md`)
Тулчейн: Xcode 27.0 (27A266a) / iOS SDK 27.0 · Destination `id=1F680A42-CEB3-43E8-9CED-52F874962A62`
(iPhone 17e, iOS 26.5, **симулятор — не физическое устройство**), serial
(`-parallel-testing-enabled NO -collect-test-diagnostics never`), DerivedData
`$COMMANDCODE_SCRATCHPAD/dd-session` (переиспользован между слайсами, удаление по
финальному cleanup-списку).

## 1. Вопрос строки (§19 п.11)

`testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer` и
`testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset` красны в изоляции:
тестовая литера pause-review advice не появляется в рантайме, а shipped keys
`set.camera.corrective.change_angle` / `set.trace.action.change_angle` несут
«Move with the phone…» / «Сместись с телефоном…». Классификация **stale oracle vs
осознанная смена копии** была release-gated и делегирована владельцу
(«owner-delegated 2026-09-27»).

## 2. Факты (все проверены в этом запуске)

1. **История копии детерминирована:** commit `5c15f3a2` (2026-09-17)
   «fix(camera): name the phone in the change-angle copy» с сопроводительным
   сообщением меняет РОВНО эти два ключа с «Try another camera position while
   keeping the main subject in frame» / «Попробуй другую точку съёмки, сохраняя
   главный объект в кадре» на «Move with the phone to another camera position…» /
   «Сместись с телефоном к другой точке съёмки…». Причина в сообщении коммита:
   RU-строка не называла ни телефон, ни камеру (neutralStatus), EN называла
   «camera» (operatorCamera) — два языка не соглашались, кто адресат; новый copy
   называет телефон и совпадает с формулировкой планировщика
   («Сместись с телефоном к выбранной точке»).
2. **Старая литера существует только в UI-тесте** — grep по всему дереву
   (`*.swift/*.xcstrings/*.py/*.md` без `docs/`) находит «Попробуй другую точку
   съёмки… / Try another camera position…» только в
   `shafinMultitoolUITests/CameraCoachProductionUITests.swift`; в каталоге
   `Localizable.xcstrings` такой строки нет ни в HEAD, ни в рабочем дереве.
3. **Shipped copy подтверждена контрактом адресата:** оба ключа описаны в
   `CameraCoachLocalizationAddresseeTests` как `.operatorPhone` (обязательный
   адресат — телефон оператора); сам гейт `testCameraCoachRUAndENAgreeOnAddressee`
   требует совпадения адресата RU/EN. Старая пара (neutralStatus RU + operatorCamera EN)
   этот гейт не проходила бы.

## 3. Вердикт (owner-delegated 2026-09-27)

**Stale oracle.** Копия «Move with the phone…» / «Сместись с телефоном…» —
**осознанная смена copy** (коммит `5c15f3a2` с рационале, закрывающий addressee-гейт),
и она остаётся shipped. Оракул UI-теста отстаёт от принятой копии и обновляется под
неё. Обоснование: (а) смена копии мотивирована контрактом адресата и согласована
между языками и с планировщиком; (б) контрольная литера существует только в тесте и
не может быть рантайм-регрессией презентации — регрессия означала бы, что рендерится
строка, которой нет в каталоге; (в) направление фикса «тест следует за продуктом»
соответствует §0 (не подгонять код под строку/оракул).

## 4. Изменение

Единственный файл: `shafinMultitoolUITests/CameraCoachProductionUITests.swift`,
хелпер `assertPauseReviewTextAndActionReachable` — обе литералы `expectedText`
заменены на shipped copy (`set.camera.corrective.change_angle` и
`set.trace.action.change_angle` несут идентичные значения), рядом комментарий с
вердиктом и ссылкой на `5c15f3a2`. **Ни одно утверждение не ослаблено и не
удалено:** проверка `advice.waitForExistence` + `XCTAssertEqual(advice.label,
expectedText)` + видимость primary advice/action сохранена 1:1, изменилось только
ожидаемое значение строки. Продуктовый код и каталог локализации не тронуты.

## 5. Проверки (команды и итоги)

| # | Команда (сокращены только пути scratch) | Итог |
|---|---|---|
| 1 | `xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool -sdk iphonesimulator -destination id=1F680A42… -derivedDataPath …/dd-session IPHONEOS_DEPLOYMENT_TARGET=15.0 build` (обход Xcode 27.0, файлы не меняются) | BUILD SUCCEEDED |
| 2 | **до правки**, та же пара в изоляции: `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool … -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests/testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset -only-testing:…testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer test` | **EXIT=65**, «Executed 2 tests, with 2 failures», оба падения на `CameraCoachProductionUITests.swift:1016` (`XCTAssertTrue(advice.waitForExistence)`) — воспроизведение stale-литеры честно зафиксировано в этом запуске |
| 3 | **после правки** та же команда | **EXIT=0**, «Executed 2 tests, with 0 failures» (EN 41.0 с, RU 36.5 с), `** TEST SUCCEEDED **` |
| 4 | независимая проверка (python, вне xcodebuild): литералы теста ↔ значения `set.camera.corrective.change_angle`/`set.trace.action.change_angle` в `Localizable.xcstrings` | RU match=True, EN match=True для обоих ключей |
| 5 | независимая проверка рискованного изменения: `xcodebuild … -only-testing:shafinMultitoolTests/CameraCoachLocalizationAddresseeTests test` | **16 / 0**, `** TEST SUCCEEDED **` |

Логи запусков: `$COMMANDCODE_SCRATCHPAD/cam002/logs/pre-fix-scenecontrol-pair.log`
(sha-суммы не заявляются — агентский /tmp-скретч, удаляется по cleanup) и
`post-fix-scenecontrol-pair.log`; xcresult в `…/dd-session/Logs/Test/`.

## 6. Честные границы и остаток

- Проверено на **симуляторе** iPhone 17e / iOS 26.5; физический UX паузы/scene control —
  DEV-003/008, не закрывается этим слайсом.
- Строка комментария в тесте цитирует старую литеру (для истории вердикта), поэтому
  текстовый grep по старой фразе остаётся положительным — в тестовом файле и только в
  комментарии.
- Итоговая классификация A-семьи (9 «чистых» методов → снять order-artifact статус,
  env-gated iPad) остаётся за строкой **CAM-022** (её собственный scope) — CAM-002
  закрывает обе root causes строки: suite-order interference (production warm-up,
  ресипт 2026-09-27) и copy-drift пару (настоящий ресипт).
- `testTorchStateResetsOnRelease` (E-класс, device-gated) и его флакучесть на новом
  тулчейне не входят в строку (DEV-004).

## 7. Статус

CAM-002 → **`DONE`**: общий root cause suite-order interference устранён в production
lifecycle (не retries/disable), copy-drift pseudo-UI пара закрыта вердиктом stale
oracle и зелёным перепрогоном. §19 п.11 — решён.
