# UI-006 — permission screens: живой симуляторный smoke (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `78369f23` · Ветка: `store`
Задача: **UI-006** (закрытие строки; симуляторно-проверяемая часть — ресипт
`2026-09-22-ui-006-permission-states.md`, матрица A1–A10, 43/0)
Среда: **симулятор** iPhone 17e / iOS 26.5 — **не физическое устройство**.

## 1. Дополнение этого запуска: живой прогон БЕЗ тест-фикстур

Свежая установка Debug-сборки, `simctl privacy <udid> reset camera <bundle>` —
реальный first-launch путь (никаких `-SHAFIN_*` аргументов):

- `1-fresh-first-launch.png` (OCR): «КАМЕРА / СНИМАЙ КИНО / Одно ясное действие.
  Затем проверка результата. / МОТОР! / **начать съёмку** / (• Приватность и лицензии)» —
  ровно одно primary action, **ссылка «Приватность и лицензии» доступна ДО запроса
  камеры** (требование SEC/UI-001), промпт камеры не запускается без явного тапа.
- Второй запуск (`2-denied.png`) — тот же intro: камера не запрошена, prompt-loop
  отсутствует (повторного запроса без действия нет).

## 2. Факт среды (честное ограничение локальной проверки)

`xcrun simctl privacy` на этом runtime **не имеет сервиса `camera`** (доступны
calendar/contacts/location/microphone/motion/photos/…): реальное состояние
«denied»/«restricted» камеры переключить из CLI нельзя (действия `deny`/`revoke
camera` отклонены). Поэтому:

- denied/restricted/no-device состояния проверены **фикстурами** (`-SHAFIN_CAMERA_PERMISSION_STATE`
  × 6 состояний; скриншоты M-UI lane, OCR 2026-09-27: denied → «КАМЕРА /
  ПРОВЕРИТЬ СНОВА» + OPEN SETTINGS; restricted → «КАМЕРА ОГРАНИЧЕНА СИСТЕМОЙ»,
  recheck-only; unavailable → «КАМЕРА НЕДОСТУПНА»; unknown → recheck-only) и
  unit-матрицей A1–A10 (43/0);
- **реальный** denial/restricted/Settings-round-trip — физическое устройство
  (Screen Time restriction там настоящая) → **DEV-002**.

## 3. Проверки

| Check | Итог |
|---|---|
| Живой first-launch smoke (reset camera → launch → screenshot ×2) | intro с одним CTA + privacy-ссылка до запроса; без повторных промптов |
| OCR скриншотов permission-состояний (4 состояния, M-UI lane 2026-09-27) | copy соответствует матрице A1–A10 (§2) |
| Unit-матрица A1–A10 (2026-09-22, serial) | 43 / 0 (принято как действующий check строки) |

## 4. Статус

UI-006 → **`DONE`**: все симуляторно-проверяемые ветки строки подтверждены
(матрица A1–A10 + живой first-launch/privacy-before-permission smoke); остаток
строки — **физический** Settings round-trip / реальный restricted / реальное
отсутствие камеры — перенесён в **DEV-002** (его собственный scope) и здесь не
заявляется. Скриншоты: `$COMMANDCODE_SCRATCHPAD/ui006/` (удаляются по cleanup;
содержимое зафиксировано OCR-транскрипциями выше).
