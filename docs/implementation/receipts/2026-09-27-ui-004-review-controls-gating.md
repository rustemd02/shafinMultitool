# UI-004 — pause/review: gating Skip/Repeat и честная структура «что увидели → что сделать → как проверить»

Дата: **2026-09-27** · HEAD: `1a973099` · Ветка: `store`
Задача: **UI-004** (bounded slice; строка → `PARTIAL`: визуальная приёмка листа —
UI-013/014 после feature freeze, физический UX — DEV-003)
Зона Own: pause/review sheet + существующие presentation-компоненты.

## 1. Что уже существует (проверено, не переписывалось)

Структура «что увидели → что сделать → как проверить» уже собрана типизированной
проекцией `CameraReviewPresentation`:

- **что увидели** — `findings` + `evidence` (+ `uncertainties` без повторов —
  `visibleUncertaintyDetails` не дублирует primary summary);
- **что сделать** — `alternativeGroups`/proposals (каждая proposal несёт свой
  `copyKey`, `isWellFormed`), причём C09.3-инвариант: review **никогда** не несёт
  `decision.activeAction` (`hasActiveAction == false`) и не открывает live-эпизод;
- **как проверить** — `status` (`CameraReviewVerificationStatus`) +
  `showsAssessmentRequest`: когда верификатор не работал и пользователь не
  ответил, лист честно просит human assessment вместо заявления автоматического
  результата; `verificationStatusLabel` не выдаёт `unknown` за сравнение.

## 2. Check строки (Skip/Repeat реально выполняют действие или отсутствуют)

Инвариант был реализован (`availableCycleControls`), но **не закреплён тестами** —
закреплён этим слайсом (2 новых теста в `CameraOverlayUXPresentationTests`):

- `testSkipAndPauseControlsExistOnlyWhenAnEpisodeActionCanContinue`: `.skipHint`/
  `.pauseHints` появляются только при `canContinueEpisode` (живой эпизод с
  действием + здоровый анализ); в `liveSeeking` без действия их **нет вообще**
  (не серые кнопки); при `.limited` анализ не обещает продолжение;
- `testRepeatControlRequiresNonEmptyVisibleCopy`: `.repeatHint` только когда есть
  непустая copy.

**Реальный крайний случай исправлен:** `visibleCopy` считал строку из пробелов
контентом — «повторить» и VoiceOver могли получить пустую строку вместо
отсутствия действия. Теперь пустые/пробельные строки фильтруются.

Skip зеркалирует видимый Continue (выполняет действие), Repeat повторяет
принятую подсказку — оба через существующие named accessibility actions
(аудит UI-008: PASS).

## 3. Проверки

| Check | Результат |
|---|---|
| `CameraOverlayUXPresentationTests` (31, включая 2 новых) + `CameraCoachAccessibilityPresentationTests` + `CameraReviewPresentationTests` | **49 / 0** |
| M0 smoke lane после изменений (blocking-минимум) | **133 / 0** |
| Сборка app-таргета | BUILD SUCCEEDED |

Симулятор iPhone 17e/iOS 26.5; не физическое устройство.

## 4. Честные границы / остаток строки

- **Визуальная приёмка листа** (плотность/иерархия «что увидели → что сделать →
  как проверить», safe-area, скриншот-фикстуры) — UI-013/014 после feature freeze.
- Физический UX pause/review на устройстве (реальные паузы/свайпы) — DEV-003/008.
- Полная строка также зависит от CAM-012 (unified decision) для финального
  контента действия; типизированные инварианты и gating закрыты сейчас.
