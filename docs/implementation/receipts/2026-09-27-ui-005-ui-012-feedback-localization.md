# UI-005 / UI-012 — feedback-события и полная локализация (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `4dd3496c` · Ветка: `store`
Задачи: **UI-005** (минимальные transitions/haptics; выполнено как часть слайса
UI-012, т.к. motion/haptics не добавляют copy) и **UI-012** (полный
локализационный аудит).
Среда: симулятор iPhone 17e/iOS 26.5 + юнит-прогоны; Xcode 27.0.

## 1. UI-005 — feedback для четырёх продуктовых моментов

Что уже существовало (проверено, не переписывалось): `SETMotion.swift`
(`SETHapticPerforming`/`SETHapticFeedback`, one-shot `SETMotionEventLedger`),
transitions в `SETComponents` с guard'ами Reduce Motion
(`guard !reduceMotion` → мгновенный показ, `reducedMotionCrossfadeDuration`
120 мс иначе), гаптика pause cut-mark и lens selection.

Добавлено (минимально):

- `SETHapticEvent.error` (`UINotificationFeedbackGenerator(.error)`) —
  существующих трёх стилей не хватало на «ошибку»;
- `SETCameraFeedbackController` — one-shot обратная связь четырёх моментов
  строки через общий ledger: **acquired target** → `.selection`
  (новый episode token = цель зафиксирована), **advice change** → `.soft`
  (`applyLiveHint`, по `hint.id`), **verified improvement** → `.rigid`
  (только `.improved`/`.fixed`; unchanged/worse/incomparable молчат),
  **error** → `.error` (`reportAnalysisFailure`);
- подключение в `CameraViewModel` (4 точки) с внедряемым
  `feedbackHaptic: SETHapticPerforming` (как существующий
  `lensSelectionHaptic`) — тесты инжектят recorder.

Новых анимаций не добавлялось (строка говорит «minimal transitions» —
переходы уже покрыты guard'ами Reduce Motion); никаких loop-анимаций нет по
построению (one-shot ledger запрещает повторы).

**Найден и закрыт дефект тестом:** пустой `eventID` сперва проходил guard —
префикс имени пространства («target./advice./…») делал ключ валидным
(«failed.»), и анонимный триггер срабатывал. `testEmptyEventIDNeverFires`
поймал это (4/1 красный); фикс — fail-closed guard на **сыром** id перед
сборкой ledger-ключа; повторный прогон 5/0.

### Проверки

| Check | Итог |
|---|---|
| `shafinMultitoolTests/CameraFeedbackControllerTests` (новый, 5 тестов: маппинг моментов, one-shot, изоляция id, пустой id, общий ledger) | **5 / 0** (после фикса; промежуточный красный 4/1 зафиксирован выше) |
| `shafinMultitoolTests/CameraViewModelLifecycleTests` (регрессия wiring) | **18 / 0** |
| Итог объединённого прогона | `** TEST SUCCEEDED **`, 23/0 |

**Честные границы:** восприятие гаптики проверимо только на устройстве
(DEV-003); «нет jank» визуально в этом запуске не проверялось (канал
изображений инструмента сломан — см. ресипт UI-003/004 §8) — новых анимаций
нет, существующие не менялись.

## 2. UI-012 — полный аудит каталога (699 ключей)

| Критерий строки | Результат | Evidence |
|---|---|---|
| Все ключи RU/EN | PASS | новый валидатор `tools/tests/test_localization_catalog_audit.py`: пустые/отсутствующие значения запрещены (699/699 en+ru непустые) |
| Pluralization | Закрыто product-решением | `set.library.count` («СЦЕН: %d») был грамматически неверен для 1–4 → **число-нейтральная copy** «СЦЕН В БИБЛИОТЕКЕ: %d» / «SCENES IN LIBRARY: %d» (верна для любого N без plural-механики; решение owner-delegated). `set.generator.beat.status` («Такт %d/%d») — **ordinal-позиция**, не существительное при числительном: plural-вариации не применимы, оставлен как есть (adjudication зафиксирована здесь). Честная граница: полноценные plural-variations потребовали бы stringsdict-проводки — не делается без нужды |
| Truncation | PASS (по критерием UI-007) | fixed-size поверхности только HUD-хром (компактный fixed — функции через named a11y actions); всё остальное scaled + multiline; anti-clipping тесты XS→AX5 (77/0) |
| Source/bundle equality | PASS | `plutil -p` построенной app-сборки: ru 699/699, en 699/699, missing=0, extra=0 (команда в ресипте) |
| Format-консистентность RU↔EN | PASS | specifier parity в валидаторе (0 расхождений: `%d`/`%@` множества идентичны) |
| Без technical/placeholder copy | PASS | запрет TODO/FIXME/TBD/lorem/template-заглушек + «value == key» (ловушка фолбэка) |
| Enum↔catalog coverage | PASS (существующий) | `test_localization_catalog_coverage.py` — каждый `SETCopyKey` есть в каталоге (5/0) |

Прогон: `python3 -m pytest tools/tests/test_localization_catalog_audit.py
tools/tests/test_localization_catalog_coverage.py -q` → **9 passed**.

**Зафиксированные границы/остатки:**

- `locale: .current`-инвентарь (латентная хрупкость при override локали) —
  список file:line в ресипте UI-003/004 §3; production-импакт не показан,
  код не менялся (без доказанного дефекта).
- Ключи UI-010 (Scene error surfaces) придут с backend-цепочкой (BE-012) —
  новый валидатор накрывает их автоматически при появлении.
- Финальная проверка «не отрезается ли copy на AX5/XXXL визуально» — UI-013/014.

## 3. Статус

- UI-005 → `DONE`: четыре момента строки несут one-shot feedback, Reduce Motion
  path подтверждён существующими guard'ами + отсутствием новых анимаций;
  haptic availability — стандартные UIKit-генераторы (внедряемые, заменяемые в
  тестах); восприятие — DEV-003.
- UI-012 → `DONE`: все критерии строки выполнены на полном каталоге (таблица
  выше); каталоговый валидатор остаётся в дереве как anti-регрессия будущих
  ключей.
