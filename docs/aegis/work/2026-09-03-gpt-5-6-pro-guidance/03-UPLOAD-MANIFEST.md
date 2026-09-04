# Upload Manifest

Все пути локальные. Веб-ChatGPT не видит их без фактической загрузки.

## Обязательные текстовые файлы

| Order | File | Purpose |
|---:|---|---|
| 1 | `00-README-FIRST.md` | Правила чтения и ограничения |
| 2 | `01-CURRENT-STATE-REPORT.md` | Синтез фактического состояния |
| 3 | `02-GPT-5.6-PRO-PROMPT.md` | Полный запрос и response contract |
| 4 | `04-CHECKSUMS.md` | Integrity and credential-like scan result |
| 5 | `10-camera-coach-source.txt` | Camera Coach production source |
| 6 | `11-scene-mode-source.txt` | Scene/Generator/AR/Storyboard/Shell source |
| 7 | `12-tests-and-release-source.txt` | Tests, scripts, build/release configuration |
| 8 | `13-authority-and-evidence-docs.txt` | Product/visual authority and evidence docs |
| 9 | `14-ml-eval-and-dataset-snapshot.txt` | ML/eval/dataset text snapshot |

Корень: `/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/`

## Визуальные файлы

Все выбранные файлы скопированы в подпапку `visuals/`, поэтому исходные каталоги искать не нужно:

1. `visuals/approved-concept.png` — направление, одобренное владельцем.
2. `visuals/camera-corrective-ru-portrait.png` — текущий Camera Coach portrait.
3. `visuals/camera-en-landscape-dynamic-type.png` — Camera Coach landscape/Dynamic Type.
4. `visuals/library-selected-ru-landscape.png` — overlap/nested-action проблема.
5. `visuals/generator-workspace-ru-landscape.png` — проблема ориентации generator evidence.
6. `visuals/storyboard-result-ru-tray-expanded.png` — проблема ориентации storyboard evidence.
7. `visuals/marker-draw-corrective-ru-portrait.mp4` — marker motion, опционально.

## Намеренно не загружается

- GGUF около 1.1 GB и бинарные Core ML/USDZ/XCFramework assets: для guidance достаточно source/config/provenance snapshots; бинарники не позволяют Pro доказать качество или права.
- Весь Git repository archive: он увеличит шум и может включить build artifacts; пять тематических source snapshots уже покрывают нужные text inputs.
- Секреты и локальные account artifacts.
- `docs/thesis/litreview*`: защищённая и нерелевантная release scope область.

## Проверка перед загрузкой

- Сверить SHA-256 и размеры всех текстовых файлов.
- Просканировать handoff на credential-like значения.
- Убедиться, что каждый визуальный файл существует.
- Отправлять prompt только после успешной загрузки всех обязательных файлов; если интерфейс ограничивает batch size, загружать несколькими сообщениями в один Project/chat и последним сообщением отправить `02-GPT-5.6-PRO-PROMPT.md`.
