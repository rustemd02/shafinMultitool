# SET OS Visual Policy v2.0 — деструктивное ревью

Статус: **v2.6 опубликована 18 августа 2026; critique-гейт закрыт; findings и evidence этого документа сохранены как исторические**  
Указатель scope: Phase 0-only и все прежние узкие планы superseded полным
production scope «SET OS v2.6 — полный production-редизайн приложения».
Этот critique не является отдельной execution authority и не переписывается
в рамках v2.6.
Объект ревью: `docs/implementation/ux/set-os-visual-policy.md`  
Ограничение: это ревью не возвращает neutral-surface и не предлагает generic UI. Его цель — сохранить характер SET OS, убрав противоречия, которые иначе превратятся в визуальные, продуктовые и технические баги.

## Короткий вердикт

Направление жизнеспособно: производственная графика, жёсткая типографика, монтажный ритм и печатная фактура дают продукту узнаваемый язык. Но v2.0 пока нельзя безопасно отдавать в имплементацию.

Главные причины:

- заявленный основной display-шрифт не содержит кириллицу;
- интерфейс обещает `REC`, хотя Camera Coach не записывает видео;
- разрешённый Material над камерой сам является постоянно пересчитываемым live-эффектом;
- визуальная таблица состояний не совпадает с фактической моделью Camera Coach и существующим behavior contract;
- правила iPad/HUD не определяют единую геометрию preview и оверлеев;
- несколько критериев приёмки сейчас либо нетестируемы, либо создают огромную, но недоказательную матрицу скриншотов.

Ниже каждое замечание сформулировано как локальная поправка, а не как переписывание политики.

## Метод и проверенные ограничения

Ревью сверено с текущими владельцами поведения в репозитории: `CommercialShellViewController`, `CommercialShellRouteComposition`, `CameraCoachEntryFlowModel`, `CameraViewModel`, `CameraOverlayUXPresentation`, `OverlayView`, `CameraManager`, `ThermalGovernor`, `SceneGeneratorViewModel`, UIKit-библиотека сцен и существующие unit/UI-тесты.

Контраст пересчитан по WCAG relative luminance, а не взят из текста политики:

| Пара | Контраст | Вывод |
|---|---:|---|
| ink `#0B0B0E` / orange `#FF5A1F` | 6.30:1 | проходит AA для обычного текста |
| white / orange | 3.12:1 | только крупный текст; обычный не проходит |
| ink / yellow `#FFD02F` | 13.40:1 | проходит |
| orange / paper `#F4F1EA` | 2.77:1 | не проходит даже 3:1 для крупного текста |
| ink / paper | 17.42:1 | проходит |
| white / ink | 19.66:1 | проходит |
| white 40% / ink | 3.80:1 | обычный текст не проходит |
| white 28% / ink | 2.41:1 | не проходит |

Проверка шрифтов выполнена по metadata официального репозитория Google Fonts: у Bebas Neue перечислены `latin`, `latin-ext`, `menu`, но не Cyrillic; у Oswald и Caveat кириллица заявлена. Поэтому фраза политики о текущей кириллице Bebas Neue фактически неверна.

### Основания ревью

Ключевые локальные свидетельства, на которых построены замечания:

- `shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift` и `shafinMultitoolTests/CameraOverlayUXPresentationTests.swift` — фактические live-состояния и явный запрет `reserve/резерв`;
- `shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift` — Material над preview, текущая геометрия `BBoxOverlay`, zoom UI и pause composition;
- `shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift` — pause lifecycle, lenses и отсутствие timecode/take/effective-ECO state;
- `shafinMultitool/Multitool2Module/Services/Pipeline/ThermalGovernor.swift` — thermal tier и low-battery budget как разные сигналы;
- `shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift` — обязательные AR readiness/camera transform и failure branches до генерации;
- `shafinMultitool/CommercialShell/CommercialShellViewController.swift`, `CommercialShellModeControl.swift`, действующие shell-тесты и `docs/aegis/plans/2026-08-17-camera-coach-fullscreen-navigation.md` — route/teardown ownership и принятая one-button shell-модель;
- `shafinMultitool.xcodeproj/project.pbxproj` — скрытый status bar, device family и текущая локализационная конфигурация;
- `docs/implementation/ux/camera-coach-state-spec.md` — существующий behavior/visual contract, с которым v2.0 сейчас пересекается без precedence.

Внешние первичные источники по шрифтам:

- [Bebas Neue metadata — Google Fonts](https://github.com/google/fonts/blob/main/ofl/bebasneue/METADATA.pb);
- [Oswald metadata — Google Fonts](https://github.com/google/fonts/blob/main/ofl/oswald/METADATA.pb);
- [Caveat metadata — Google Fonts](https://github.com/google/fonts/blob/main/ofl/caveat/METADATA.pb);
- [JetBrains Mono — официальный репозиторий](https://github.com/JetBrains/JetBrainsMono).

## Блокирующие замечания

### SET-001 — `[BLOCKER]` §3.1 Display: Bebas Neue не покрывает русский алфавит

**Суть.** Политика назначает Bebas Neue основным display-шрифтом RU+EN и утверждает, что актуальная Google Fonts-версия содержит кириллицу. Официальные metadata этого не подтверждают. На русском экран либо уйдёт в системный fallback посреди фирменной строки, либо целиком потеряет ожидаемую метрику.

**Где сломается.** Заголовки `СНИМАЙ КИНО`, состояния разрешений, экран генерации и смешанные RU/EN-композиции получат разные ширины, переносы и визуальный голос. Скриншот EN пройдёт, RU развалится уже на устройстве.

**Было → стало.**  
Было: «Display: Bebas Neue; текущая версия Google Fonts поддерживает Cyrillic; Oswald — fallback».  
Стало: «Bebas Neue используется только в неизменяемом латинском wordmark `SHAFIN MULTITOOL`. Все локализуемые RU+EN display-строки набираются Oswald. В bundle закрепляются точные файлы, версии, лицензии и checksums. Phase 0 содержит CoreText-тест `CTFontGetGlyphsForCharacters` для полного RU+EN набора и render-fixtures, а не только проверку загрузки шрифта».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-002 — `[BLOCKER]` §5.4 Tally и §7 Camera Coach: `REC` сообщает о несуществующей записи

**Суть.** Текущий Camera Coach запускает анализ потока и pause critique, но не создаёт пользовательский видеофайл. Красный/оранжевый tally `REC` — не декор, а устоявшееся обещание записи и приватностно значимый сигнал.

**Где сломается.** Пользователь решит, что дубль записан, закроет приложение и потеряет материал; либо решит, что приложение тайно сохраняет видео. В будущем настоящий recording-state уже некуда будет семантически посадить.

**Было → стало.**  
Было: «Tally `REC` активен во время live-анализа».  
Стало: «Во время анализа Camera Coach показывает tally `LIVE` или `COACH`. `REC` зарезервирован только для состояния, в котором приложение действительно пишет и сохраняет медиа; его включение требует отдельного behavior contract».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-003 — `[BLOCKER]` §6 Live-layer performance: Material над камерой противоречит запрету per-frame blur

**Суть.** `.ultraThinMaterial` назван допустимым для “статического chrome”, но над движущимся `AVCaptureVideoPreviewLayer` материал пересэмпливает и размывает меняющийся фон на каждом кадре. Визуально неподвижная панель не является вычислительно статичной.

**Где сломается.** На старых iPhone blur, несколько HUD-панелей, preview и ML-pipeline конкурируют за GPU/thermal budget; появляются dropped frames, нагрев и ранний ECO. Это прямо нарушает заявленный бюджет live-слоя.

**Было → стало.**  
Было: «Для статического chrome над камерой допустим `.ultraThinMaterial`; per-frame guides — без blur».  
Стало: «Над live-preview запрещены SwiftUI Material, `UIVisualEffectView`, backdrop blur и тени для всех элементов, включая неподвижный chrome. HUD использует единый токен полупрозрачной ink-плашки с hairline; прозрачность проверяется на worst-case светлом и пёстром preview. Material разрешён только вне live-preview».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-004 — `[BLOCKER]` §2/§7/§9: визуальная политика конфликтует с действующим behavior contract

**Суть.** v2.0 объявляет `camera-coach-state-spec.md` контрактом поведения, но одновременно вводит `РЕЗЕРВ`, новую цветовую семантику и shell-капсулу `A/B ROLL`. Текущая presentation-модель намеренно запрещает слова `reserve/резерв`; тесты это фиксируют. Принятый shell-план и тесты требуют ровно одну тихую icon-only кнопку 44×44 без capsule/title/material. Не определено, какой документ supersede-ит только визуальные положения, не меняя роуты и ownership.

**Где сломается.** Инженер либо нарушит policy, сохранив тесты, либо “починит” тесты и незаметно изменит behavior/IA. Два документа останутся каноническими одновременно.

**Было → стало.**  
Было: «Behavior contract сохраняется; shell использует A/B ROLL capsule; fallback — `РЕЗЕРВ`».  
Стало: «До Phase 0 составляется таблица precedence: SET OS v2.1 supersede-ит только перечисленные visual clauses старого spec/plan. Роуты, один intent-owner, async teardown и accessibility-ID остаются behavior truth. Любые новые пользовательские состояния/термины (`РЕЗЕРВ`, capsule с двумя подписями) требуют отдельного принятого изменения behavior contract и синхронного обновления тестов; до этого они не имплементируются».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-005 — `[BLOCKER]` §7.2 Camera Coach states: таблица не отображает реальную машину состояний

**Суть.** В репозитории presentation-state имеет `liveSeeking`, `stableTip`, `explanation`, `keepAsIs`; `isPaused` передаётся, но не участвует в presentation. Отдельных состояний fallback, camera starting/interrupted/failed, lens switch, pause loading/nil-result/failure и resume нет. Политика рисует результат, но не назначает источник истины и переходы.

**Где сломается.** При остановке камеры поверх последнего кадра останется live-состояние; fallback станет “вечным поиском”; двойной tap pause создаст повторный haptic/штамп; ошибка анализа окажется визуально неотличима от пустого результата.

**Было → стало.**  
Было: «Визуальная таблица: waiting / keep / corrective / fallback / explanation / paused / ECO».  
Стало: «Перед Phase 1 таблица дополняется колонками: behavior source, входное событие, выходное событие, допустимые действия, copy, accessibility announcement, screenshot fixture. Обязательные группы: camera lifecycle; live presentation; lens switching; pause requesting/loading/success/empty/failure/resume; thermal effective tier. Визуальный слой не создаёт параллельную state machine и не выводит состояние, которого нет у behavior-owner».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-006 — `[BLOCKER]` §9 iPad monitor и §7 HUD: нет единой координатной системы preview/оверлеев

**Суть.** Текущий preview использует `resizeAspectFill`, а bounding boxes переводятся из normalized coordinates прямо в весь `GeometryReader`. Политика добавляет iPad 16:9 monitor/letterbox и HUD на полях, но не определяет `previewContentRect` и преобразование камеры в экран.

**Где сломается.** После letterbox либо aspect-fill рамки лиц/объектов сместятся относительно картинки; tap-to-focus и гайды будут попадать в поля. В landscape ошибка станет особенно заметной.

**Было → стало.**  
Было: «На iPad камера выглядит как 16:9 director monitor; HUD может жить на полях».  
Стало: «Preview-owner публикует единый `previewContentRect` и transform normalized-camera-space → view-space с учётом aspect mode, aperture, mirroring и orientation. Preview, bbox, guides, tap targets и snapshot используют только этот transform. HUD-поля не входят в camera coordinate space. Это покрывается unit-тестами геометрии для portrait/landscape/iPad letterbox».

**Решение владельца:** ☐ принять ☐ отклонить

## Существенные замечания

### SET-007 — `[MAJOR]` §2.2 Цвет: orange-on-paper ошибочно разрешён как крупный семантический текст

**Суть.** Контраст orange/paper равен 2.77:1, а не требуемым 3:1 для крупного текста. Размер 24 pt не исправляет пару цветов.

**Где сломается.** Оранжевый заголовок или статус на бумажном фоне провалит WCAG AA даже в display-размере; на тонком Bebas/Oswald визуальная читаемость будет ещё хуже.

**Было → стало.**  
Было: «Orange на paper допустим для display ≥24 pt или декоративно».  
Стало: «Orange на paper разрешён только для несемантических заливок, линий и крупных декоративных форм. Весь читаемый текст на paper — ink. Исключение возможно только для новой пары, подтверждённой расчётом ≥3:1 для крупного и ≥4.5:1 для обычного текста».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-008 — `[MAJOR]` §2.3/§6: muted text и текст поверх камеры не имеют гарантии контраста

**Суть.** Политика запрещает “серый текст”, но использует opacity как иерархию без минимального значения. White 40% на ink даёт лишь 3.80:1; поверх произвольного видео даже white 100% может исчезнуть на светлом кадре.

**Где сломается.** Вторичная инструкция, таймкод или статус будут нечитаемы на снегу/небе либо при Reduce Transparency; VoiceOver не компенсирует слабовидящему пользователю визуальную потерю.

**Было → стало.**  
Было: «Иерархия строится opacity; HUD может быть полупрозрачным».  
Стало: «Для semantic text вводятся именованные foreground-токены с измеренным контрастом: normal ≥4.5:1, large ≥3:1. Текст live-HUD всегда лежит на ink-scrim достаточной непрозрачности; контраст проверяется на белом, чёрном и пёстром video-fixture. При Reduce Transparency scrim становится непрозрачным без изменения размеров».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-009 — `[MAJOR]` §3/§12: RU+EN заявлены, но локализационного контура в приложении нет

**Суть.** В проекте нет String Catalog/`Localizable.strings`; существующие строки в entry, overlay и генераторе захардкожены по-русски, target regions не описывают реальный RU+EN launch. Перевод только галереи создаст ложное чувство готовности.

**Где сломается.** Смена языка системы не изменит экран либо даст смесь RU/EN; accessibility labels и snapshot-fixtures разойдутся с видимым copy; длинный английский/русский текст не попадёт в layout QA.

**Было → стало.**  
Было: «Базовый язык RU, на запуске RU+EN; галерея показывает обе локали».  
Стало: «Phase 0 включает String Catalog для всех затрагиваемых экранов, локализованные accessibility strings, явную fallback-locale и deterministic locale override только для previews/UI-tests. Ни одна видимая SET OS-строка не хранится литералом во View. Acceptance включает запуск app target на RU и EN, а не только preview».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-010 — `[MAJOR]` §3.4 Шрифты: проверка “рендером” недостаточна без provenance и полного glyph-set

**Суть.** Даже шрифты с кириллицей могут иметь неполные кавычки, `Ё/ё`, цифры, валюту, narrow no-break space или измениться при обновлении asset. Для PT Mono/Courier fallback не закреплены источник, лицензия и метрики.

**Где сломается.** Один символ уйдёт в fallback внутри таймкода/сценария; новый файл шрифта изменит переносы и golden screenshots без изменения кода.

**Было → стало.**  
Было: «Добавить UIAppFonts, fallback и проверить кириллицу рендером».  
Стало: «Для каждого bundled font закрепить filename, PostScript name, source, license, version/checksum и допустимый fallback. Автотест проверяет glyph coverage полного продуктового RU+EN charset через CoreText; screenshot проверяет метрики на эталонных строках `Ёж, съёмка № 03 — TAKE 12:34:56:23`».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-011 — `[MAJOR]` §5.5 Timecode: wall-clock `HH:MM:SS:FF` не определён и может дёргать весь SwiftUI HUD

**Суть.** Wall clock может прыгнуть при смене системного времени и не даёт честный frame number без resolved FPS. Обновление `FF` 24–60 раз/с через общий observable model способно инвалидировать всё дерево HUD.

**Где сломается.** Таймкод перескочит назад, `FF` не совпадёт с камерой, а частые state updates съедят frame budget одновременно с ML.

**Было → стало.**  
Было: «Таймкод `HH:MM:SS:FF`, моноширинный, живой».  
Стало: «Camera session owner задаёт monotonic epoch и resolved FPS. Timecode — session elapsed, не `Date()`. Изолированный renderer обновляет только label; допустимая cadence и способ вычисления `FF` фиксируются отдельно и профилируются. При недоступном FPS показывается `HH:MM:SS`, без выдуманного frame count».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-012 — `[MAJOR]` §7.2 ECO: политика использует thermal state, а runtime имеет ещё low-battery override

**Суть.** `ThermalGovernor.currentTier` отражает thermal state, но фактический budget меняется также из-за низкого заряда. ViewModel не публикует эффективный tier для UI. Значит, ECO-бейдж либо не появится при реальном throttling, либо UI создаст вторую интерпретацию.

**Где сломается.** Pipeline перейдёт в reduced budget на холодном устройстве с низким зарядом, а интерфейс продолжит показывать normal. Или бейдж будет мигать из-за разных источников.

**Было → стало.**  
Было: «ECO показывается при thermal throttling».  
Стало: «Thermal/power owner публикует один effective performance mode с reason (`thermal`, `lowBattery`, другое). UI только отображает его и не вычисляет mode самостоятельно. Текст пользователю не обещает причину, если она не подтверждена; debounce/hysteresis принадлежат owner».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-013 — `[MAJOR]` §5.6/§7.3 Pause-review: нет контракта snapshot, take counter и ошибочных исходов

**Суть.** Текущий pause останавливает camera и запускает async critique, но не имеет immutable captured frame, номера дубля и полной модели loading/failure/empty. `PauseCritiqueCard` живёт в legacy shell, а не в Camera Coach.

**Где сломается.** Штамп поставится поверх другого кадра после rotation/resume; `TAKE 03` сбросится при пересоздании View; nil critique покажет пустую “успешную” карточку.

**Было → стало.**  
Было: «На паузе появляется разбор со штампом и номером TAKE».  
Стало: «Pause owner создаёт immutable pause snapshot ID, session take number и одно из состояний loading/success/empty/failure/cancelled. Штамп и TAKE привязаны к snapshot ID, переживают rotation, не повторяют haptic при recomposition и сбрасываются только по явно описанному session reset».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-014 — `[MAJOR]` §5 Motion: “один раз” не имеет устойчивого владельца события

**Суть.** Лидер “один раз за сессию”, хлопок при завершении и штамп легко реализовать визуально, но `@State` во View повторит их после route recreation, rotation или возврата из background. Политика описывает choreography, но не event identity.

**Где сломается.** Пользователь повернёт телефон и снова получит leader + haptic; async completion придёт после teardown и анимация запустится на новом экране.

**Было → стало.**  
Было: «Leader показывается один раз; slate snap срабатывает на completion».  
Стало: «Каждая one-shot animation получает event ID и owner вне transient View. View отмечает consumed event; повторный render/rotation не повторяет motion и haptic. Async event проверяет актуальный route/session generation перед показом. В tests используется motion/haptic spy».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-015 — `[MAJOR]` §8 Scene Generator: “offline/ЦЕХ” противоречит обязательной AR-готовности

**Суть.** `generateScene()` сейчас требует готовую ARSession и camera transform до перехода в generating. Это не offline-инструмент. Политика запускает leader/progress, не определив preflight, clarification, parse failure, cancellation, background и retry.

**Где сломается.** Пользователь введёт сцену без AR-ready, увидит эффект запуска, а затем мгновенную ошибку; progress будет выглядеть как зависший или лживый.

**Было → стало.**  
Было: «Offline-инструменты / ЦЕХ; после запуска leader переходит в perforation progress».  
Стало: «Регистр называется `non-live editorial surfaces`, пока генератор зависит от AR. До leader проходит preflight: input, AR readiness, camera transform и request eligibility. Leader запускается только после принятия request owner-ом. Политика перечисляет clarification, progress, cancellable/background, parse/network failure, retry и success; каждый исход имеет deterministic fixture».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-016 — `[MAJOR]` §8.3 Library contact sheet: текущая модель не содержит кадров

**Суть.** Библиотека получает только имя сцены и дату обновления; thumbnail/frame/take metadata отсутствуют. “Контактшит” может быть только метафорой верстки, иначе потребуется изменение persistence/data contract, а задача обещает restyle без редизайна IA.

**Где сломается.** Дизайнер нарисует честные thumbnails, инженер подставит fake placeholders или полезет расширять БД и миграции внутри визуальной фазы.

**Было → стало.**  
Было: «Библиотека — контактшит».  
Стало: «В v1 contact-sheet — типографическая сетка существующих metadata: имя, дата, статус; fake frame thumbnails запрещены. Настоящие кадры/дубли требуют отдельного принятого persistence contract и миграционного плана и не входят в restyle».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-017 — `[MAJOR]` §9 Adaptivity: size class недостаточно для правил collapse

**Суть.** iPad portrait и landscape обычно остаются regular/regular; на iPhone разные комбинации size class не являются надёжным названием ориентации. Dynamic Type и реальный container width важнее. `UIDevice.orientation` тоже нельзя делать owner-ом layout.

**Где сломается.** HUD выберет portrait-композицию в iPad landscape или не схлопнется при Accessibility XXL; после rotation появится overlap.

**Было → стало.**  
Было: «Композиция определяется size classes; на SE HUD коллапсирует».  
Стало: «Layout resolver использует container size/aspect, horizontal/vertical size class, safe areas и Dynamic Type. Ориентация устройства не является источником истины. Для каждой композиции заданы minimum content width/height и порядок collapse; тесты прогоняют iPhone SE, Pro Max, iPad fullscreen в portrait/landscape и accessibility sizes».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-018 — `[MAJOR]` §9 iPad: не определён scope multitasking

**Суть.** Target поддерживает iPad, но сейчас требует full screen. Политика описывает iPad как фиксированный director monitor и не говорит, обязана ли v1 поддерживать Split View/Stage Manager и произвольные окна.

**Где сломается.** QA сочтёт узкое iPad-окно обязательным и заведёт дефекты, либо позже снятие `UIRequiresFullScreen` мгновенно разрушит HUD.

**Было → стало.**  
Было: «iPad: 16:9 director monitor с HUD на полях».  
Стало: «Для v1 iPad scope явно: fullscreen portrait+landscape при действующем `UIRequiresFullScreen`. Split View/Stage Manager не входят в acceptance до отдельного изменения target capability. Layout resolver при этом не полагается на конкретную модель iPad и готов к container-based расширению».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-019 — `[MAJOR]` §5/§11 Motion accessibility: Reduce Motion описан эффектами, но не смыслом перехода

**Суть.** Простая замена snap/wipe на fade может убрать причинно-следственную связь “запуск → обработка → результат”. Пульс tally и бесконечные индикаторы не имеют лимита повторения.

**Где сломается.** При Reduce Motion пользователь не поймёт, что стадия сменилась, либо получит постоянное мерцание, хотя запросил меньше движения.

**Было → стало.**  
Было: «При Reduce Motion крупные анимации заменяются fade; pulse упрощается».  
Стало: «Reduce Motion сохраняет те же дискретные стадии через мгновенную смену композиции + короткий opacity transition без travel/scale/rotation. Бесконечный pulse становится статическим индикатором. Meaningful completion дополнительно подтверждается текстом и, если разрешено, одиночным haptic. Reduce Motion не меняет state timing и actions».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-020 — `[MAJOR]` §12 Gallery/evidence: нет детерминированного способа получить обязательные состояния

**Суть.** Текущий DEBUG UI-test root умеет подменять только часть entry permission/intro. Corrective/fallback/pause/ECO/generator outcomes зависят от камеры, ML, thermal и async. Скриншоты физического потока не будут воспроизводимы; известный host-capture может отдавать неверно повёрнутый кадр.

**Где сломается.** Матрицу формально заполнят разными случайными кадрами; fallback или ECO невозможно стабильно вызвать; landscape-артефакт будет принят за layout bug либо тест просто skip-нут.

**Было → стало.**  
Было: «Снять screenshot matrix всех состояний на устройствах; минимум 144 артефакта».  
Стало: «Phase 0 добавляет DEBUG-only deterministic gallery/fixture root, недоступный production routing: фиксированные state payloads, video stills, locales, orientation, Reduce Motion/Transparency, Dynamic Type. Golden matrix снимается из fixtures; отдельный physical-device smoke доказывает preview, rotation, thermal и teardown. Host-capture orientation валидируется по metadata/размеру, skip не считается evidence».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-021 — `[MAJOR]` §12 Matrix: 144 артефакта не покрывают заявленный scope и плохо локализуют регрессии

**Суть.** Число 144 уже получается до явного умножения на portrait/landscape, Dynamic Type, blocked×4 и generator failure states. Большой набор похожих картинок создаёт ревью-шум, но не заменяет layout/glyph/contrast/state tests.

**Где сломается.** Команда потратит часы на ручное пролистывание, пропустит смещение bbox на 4 px и всё равно не докажет event ownership или контраст.

**Было → стало.**  
Было: «Минимум 144 screenshot artifacts».  
Стало: «Evidence делится на: (1) автоматические state/layout/glyph/contrast/geometry tests; (2) owner-approved golden subset ключевого пути на RU+EN и двух ориентациях; (3) pairwise accessibility/device matrix; (4) physical smoke. Полная декартова матрица допускается для генерации, но не является самостоятельным acceptance criterion. В документе фиксируется точный manifest ожидаемых fixtures».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-022 — `[MAJOR]` §12 Guard tests: source scanning не доказывает соблюдение палитры и шрифтов

**Суть.** Regex по `Color(red:)`, hex и строкам ловит debug/exempt code, но пропускает Asset Catalog, `UIColor`, dynamic providers и fallback на уровне glyph. Он также поощряет спрятать magic number в helper.

**Где сломается.** Guard зелёный при неправильном asset color; либо красный из-за DebugOverlay, который запрещено трогать. Шрифт загрузится, но половина строки отрендерится системным fallback.

**Было → стало.**  
Было: «Source guard запрещает прямые цвета/hex и проверяет display font».  
Стало: «Guard ограничивается production UI scope с явным allowlist legacy/debug. Unit tests проверяют RGBA/semantic mapping токенов, asset names и отсутствие запрещённых API в live-HUD. Glyph coverage проверяется CoreText. Source lint остаётся быстрым сигналом, но не считается доказательством визуальной корректности».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-023 — `[MAJOR]` §1/§4 Tokens: абсолютный запрет “магических чисел во View” смешивает дизайн и домен

**Суть.** Если любое число обязано жить в глобальном DesignSystem, туда попадут fps, duration, camera geometry и одноразовые размеры конкретного screen. Получится общий склад констант и новый источник связности.

**Где сломается.** Изменение camera cadence будет выглядеть как дизайн-правка; локальный layout будет переиспользовать семантически чужой token только ради прохождения guard.

**Было → стало.**  
Было: «Токены — единственный источник чисел; магических чисел во views нет».  
Стало: «Глобальные tokens владеют повторяемыми visual primitives и semantic design values. Feature-specific layout constants могут быть именованными и локальными рядом с компонентом. Domain values — fps, timeouts, camera transforms, ML thresholds — остаются у domain owner и запрещены в DesignSystem. Голые необъяснённые literals во View не допускаются».

**Решение владельца:** ☐ принять ☐ отклонить

### SET-024 — `[MAJOR]` §10 System chrome: политика управляет status bar, который target скрывает глобально

**Суть.** Build setting включает `UIStatusBarHidden=YES`, поэтому правила light/dark status bar не выполняются и не проверяются. Их реализация потребует изменения глобального app behavior, не локального restyle.

**Где сломается.** Инженер потратит время на `preferredStatusBarStyle`, не увидит результата, либо включит status bar глобально и изменит safe areas всех экранов.

**Было → стало.**  
Было: «Status bar меняет стиль по surface».  
Стало: «В v1 status bar остаётся скрытым согласно target configuration; правила его окраски не входят в acceptance. Включение status bar — отдельное behavior/layout изменение с проверкой safe areas всех shell routes».

**Решение владельца:** ☐ принять ☐ отклонить

## Неблокирующие, но полезные уточнения

### SET-025 — `[MINOR]` §7/§8 Copy: часть терминов звучит как машинный перевод или меняет смысл

**Суть.** `СЛЕТ` по-русски читается как gathering/съезд, а не slate; если нужен профессиональный термин — это “хлопушка” или заимствованное “слейт”. `SHOOT CINEMA` и `TAKE 03 REVIEW` неестественны для английского интерфейса.

**Где сломается.** Фирменный copy станет мемом не в нужном смысле; переводчик позже изменит длину CTA и сломает заранее утверждённую композицию.

**Было → стало.**  
Было: `СЛЕТ`, `SHOOT CINEMA`, `TAKE 03 REVIEW`.  
Стало: короткий CTA `ХЛОП!` с helper `Собрать раскадровку` либо термин `СЛЕЙТ`; EN — `MAKE A FILM`/`SHOOT A FILM` и `TAKE 03 / REVIEW`. Финальный вариант проходит отдельный RU+EN copy review до фиксации golden screenshots.

**Решение владельца:** ☐ принять ☐ отклонить

### SET-026 — `[MINOR]` §5.7 Grain/torn paper: runtime-random фактура не запрещена явно

**Суть.** Зерно и рваный край реализуемы через bundled assets/masks или Canvas, но случайная генерация на каждом render даст мерцание, нестабильные snapshots и лишнюю работу CPU/GPU.

**Где сломается.** Grain “кипит” при state update, golden screenshots никогда не совпадают, маска рваного края меняет hit area.

**Было → стало.**  
Было: «Использовать зерно и рваный край дозированно».  
Стало: «Фактуры детерминированы: bundled assets либо seeded static masks с зафиксированным scale. Они не регенерируются при render, не участвуют в hit testing и не применяются поверх live-preview. Decorative layers скрыты от accessibility».

**Решение владельца:** ☐ принять ☐ отклонить

## Реализуемость мотивов в текущем репозитории

| Мотив | Реализация | Главный риск | Необходимый контракт |
|---|---|---|---|
| Лидер 3–2–1 | SwiftUI `Shape`/`Canvas`, дешёво вне live | повтор при recreation | session-owned consumed event ID |
| Хлопок слейта | SwiftUI transform + optional haptic | повторный trigger после async completion | generation completion event ID + route generation guard |
| Штамп | overlay/mask, дёшево | штамп на изменившемся кадре | immutable pause snapshot ID |
| Перфорация-progress | повторяемый Shape/Canvas | indeterminate progress выглядит как ложный процент | явный determinate/indeterminate contract |
| Рваный край | static mask/asset | runtime randomness, hit area | deterministic asset/token; decoration only |
| Зерно | static bitmap/tile вне live | fill-rate и flicker | no-live rule, fixed seed/asset |
| Таймкод | isolated label/Core Animation | 24–60 state invalidations, неверный FPS | monotonic epoch + resolved FPS owner |
| Tally | text + compositor-only opacity | `REC` лжёт; pulse при Reduce Motion | `LIVE/COACH`; static accessible variant |
| Notes/рукопись | Caveat для коротких decorative strings | длинный copy и fallback | лимит длины; semantic duplicate обычным шрифтом |

Вывод: сами графические мотивы реализуемы. Нереализуемой сейчас является не картинка, а обещанная семантика: “один раз”, “этот дубль”, “реальный frame count”, “эффективный ECO” и “запись”. Эти значения должны прийти от существующих или явно расширенных behavior-owner’ов.

## Совместимость с архитектурой и тестами

Чтобы SET OS не создал второй центр управления приложением, v2.1 должна закрепить следующие границы:

- `CommercialShellViewController` и route composition остаются единственными владельцами переключения и async teardown; анимационный shell только визуализирует разрешённый переход.
- accessibility-ID не меняются; локализуется label/value, но не identifier.
- presentation adapter Camera Coach отображает domain state; View не выводит fallback/ECO/pause самостоятельно.
- rotation не создаёт новую session identity и не повторяет one-shot events.
- design gallery использует те же production components и tokens, но fixture owners; копии компонентов только для preview запрещены.
- существующие тесты, которые намеренно запрещают `reserve/резерв` и shell capsule, нельзя просто удалить: сначала владелец принимает изменение контракта и v2.1 явно называет superseded assertions.

## Проверяемость критериев приёмки

| Критерий | Сейчас | Как сделать проверяемым |
|---|---|---|
| Палитра только из tokens | частично; regex обходим | token RGBA tests + scoped lint + visual fixtures |
| RU+EN display без fallback | не доказуем screenshot-ом полностью | CoreText glyph test + mixed-string render |
| Контраст | некоторые цифры неверны | автоматический расчёт каждой semantic token pair |
| HUD совпадает с preview | не описано | geometry tests normalized → contentRect для orientations |
| Нет blur/теней live | противоречие с Material | API/source guard в live-HUD scope + GPU capture smoke |
| One-shot motion | нет event owner | event-consumption unit tests + motion/haptic spy |
| Reduce Motion/Transparency | только визуальное пожелание | environment fixtures + snapshot/layout assertions |
| ECO честно отражает runtime | нет observable effective mode | governor/view-model contract test |
| Zoom только real lenses | enum ограничен, metadata нет | fixture of available devices + label mapping tests |
| Async teardown сохранён | риск от transition animation | existing shell teardown tests + stale completion test |
| “Выглядит как promo” | субъективно, не автоматизируется | owner approval по фиксированному golden manifest |
| Не похоже на generic app | субъективно | art-direction checklist: typography, motif budget, surface split, no-slop audit |

## Слабые места арт-дирекшна

Это не аргументы за нейтральный дизайн. Это способы сделать выбранный язык более собственным и менее похожим на набор референсов.

### ART-01 — `[MAJOR]` §0/§5 Референсы: слишком буквальная сумма A24 + Persona 5 + советская полиграфия

**Вызов.** Если перенести диагонали, high-impact wipes, off-white/black/orange и condensed type одновременно, результат легко прочитается как “Persona-lite с A24-постером”, а не как Shafin Multitool.

**Альтернатива.** Описывать не бренды, а собственные операции SET OS: `crop`, `registration`, `call-sheet grid`, `slate snap`, `contact strip`, `ink stamp`. Запретить узнаваемые композиции и прямое цитирование UI референсов.

**Цена.** Низкая в коде; средняя на арт-дирекшн — потребуется один проход по mockups и собственная таблица композиционных примитивов.

**Где сломается.** Entry с диагональным слоганом, orange/black и collision-motion будет выглядеть как фанатская вариация Persona, а не как самостоятельный продукт; юридически безопасная, но визуально вторичная работа провалит критерий узнаваемости.

**Было → стало.**  
Было: «Референсы A24/MUBI, Persona 5, Overwatch 1 задают стиль».  
Стало: «Референсы задают только качества — редакционная смелость, монтажный ритм, ясная event-анимация. Прямое копирование узнаваемых layouts, HUD silhouettes и transition compositions запрещено; SET OS строится из собственного набора production primitives».

**Решение владельца:** ☐ принять ☐ отклонить

### ART-02 — `[MAJOR]` §0/§5 Печатная энергия: “советская энергия” рискует стать историческим косплеем

**Вызов.** Даже без символики сочетание лозунговой типографики, красно-оранжевых диагоналей, штампов и состаренной бумаги может прочитаться как ретро-пропаганда. Это сузит продукт до стилизации эпохи.

**Альтернатива.** Брать энергию не из агитплаката, а из производственной бюрократии кино: call sheets, монтажные пометки, паспорт плёнки, номер дубля, registration marks, лабораторная маркировка. Бумагу оставить светлой и современной, aging/грязь не использовать.

**Цена.** Средняя дизайнерская, низкая инженерная: меняются assets/micro-layout, не архитектура.

**Где сломается.** Сочетание лозунга, состаренной бумаги и печатного штампа на onboarding будет воспринято как ретро-тема приложения, хотя Camera Coach должен ощущаться современным рабочим инструментом.

**Было → стало.**  
Было: «Советская полиграфическая энергия; зерно, рваная бумага, штамп».  
Стало: «Энергия конструктивной печатной композиции без исторической имитации: production paperwork, registration и монтажные marks. Состаривание, грязь, propaganda-like лозунговые композиции и period cosplay запрещены».

**Решение владельца:** ☐ принять ☐ отклонить

### ART-03 — `[MAJOR]` §5 Мотивы: одновременное использование всех мотивов создаст theme park

**Вызов.** Лидер, хлопушка, штамп, перфорация, рваный край, grain, handwritten notes и timecode по отдельности сильны; вместе на одном экране они конкурируют за роль героя.

**Альтернатива.** Motif budget: один hero motif + максимум один supporting motif на состояние. Например, live = timecode+tally; pause = stamp+note; generation = leader→perforation; library = contact strip без leader/stamp.

**Цена.** Низкая и даже уменьшает объём имплементации.

**Где сломается.** Pause-review с timecode, perforation, grain, рваным краем, рукописной заметкой и штампом потеряет визуальную иерархию; состояние “разбор” станет медленнее считываться, чем нынешняя нейтральная карточка.

**Было → стало.**  
Было: «Мотивы применяются дозированно» без измеримого правила.  
Стало: «На одном стабильном состоянии допускается один hero motif и один supporting motif. Transition motif исчезает после завершения. Матрица экранов перечисляет разрешённую пару; остальные мотивы на этом экране запрещены».

**Решение владельца:** ☐ принять ☐ отклонить

### ART-04 — `[MAJOR]` §5/§7 Motion и HUD: диагональная композиция может разрушить рабочую точность

**Вызов.** Persona-like over-animation хороша для перехода, но постоянные диагонали и collision-композиция в Camera Coach конкурируют с лицом, bbox и горизонтом — то есть с инструментальной задачей.

**Альтернатива.** Статический live-HUD строить на ортогональной сетке и camera-safe fields. Диагональ разрешать только как краткий transition/accent вне области анализа.

**Цена.** Низкая; уменьшает сложность layout и риска overlap.

**Где сломается.** На iPhone SE диагональная подсказка пересечётся с bbox/лицом и будет выглядеть частью computer-vision guide; пользователь неверно прочитает декоративное движение как инструкцию кадрирования.

**Было → стало.**  
Было: «Резкие диагональные влеты и over-animation — часть языка».  
Стало: «Диагональ — transition primitive, не постоянная сетка live-HUD. Camera guidance и bbox остаются ортогональными и геометрически точными; impact motion не перекрывает область анализа дольше transition budget».

**Решение владельца:** ☐ принять ☐ отклонить

### ART-05 — `[MINOR]` §3/§9 Wordmark: логотип рискует остаться строкой готовым шрифтом

**Вызов.** Высокий condensed font сам по себе не создаёт логотип. Если просто набрать `SHAFIN MULTITOOL` Bebas Neue, бренд будет легко заменяемым.

**Альтернатива.** Зафиксировать typographic lockup: line break, crop, tracking, baseline relation и protected clear space; Bebas остаётся материалом, а не всей идеей. Не добавлять отдельную generic-иконку.

**Цена.** Низкая в коде, низкая–средняя в дизайне; потребуется один векторный master и адаптации horizontal/vertical lockup.

**Где сломается.** В horizontal shell слово придётся перенабрать меньшим кеглем, в portrait — другим line break; без master-lockup это будут два разных логотипа, а любой конкурент сможет выглядеть почти так же заменой текста.

**Было → стало.**  
Было: «Логотип — высокий wordmark из варианта 2».  
Стало: «Wordmark имеет две зафиксированные композиции — horizontal и stacked — с неизменяемыми crop/tracking/line-break и clear-space tokens. Локализации wordmark не меняют. Произвольный набор названия тем же шрифтом не считается логотипом».

**Решение владельца:** ☐ принять ☐ отклонить

## Top-5 правок до Phase 0

1. **SET-001:** оставить Bebas Neue только для латинского wordmark, сделать Oswald локализуемым display и ввести glyph/provenance tests.
2. **SET-002:** заменить ложный `REC` на `LIVE/COACH`, пока приложение реально не записывает медиа.
3. **SET-003:** полностью убрать Material/blur/shadows с live-preview chrome, а не только с guide layer.
4. **SET-004 + SET-005:** явно развести visual policy и behavior contract, затем описать полную таблицу состояний через существующих owner’ов.
5. **SET-006:** ввести единый `previewContentRect`/camera transform до iPad letterbox и любых новых HUD-композиций.

## Решения владельца (2026-08-17)

Ревью принято как качественное: факты проверены владельцем независимо
(запрет «резерв» в `CameraOverlayUXPresentationTests.swift:108`;
`UIStatusBarHidden=YES` в обеих конфигурациях target; отсутствие записи
медиа в Camera Coach). Итог: **27 из 31 пункта приняты полностью,
4 — приняты с переопределением владельца** (ни один не отклонён).

| ID | Решение | Комментарий |
|---|---|---|
| SET-001 | ПРИНЯТЬ | Oswald — локализуемый display; Bebas — только латинский wordmark |
| SET-002 | ПРИНЯТЬ, tally = `LIVE` | Не `COACH` (читается как спорт). `REC` зарезервирован за будущей реальной записью (CC-008 §3.1) |
| SET-003 | ПРИНЯТЬ | Замена: `hud.scrim` = ink@0.72 (+допустим вертикальный ink-fade без blur) + hairline white@0.14 |
| SET-004 | ПРИНЯТЬ с решениями | См. Переопределение O-1 |
| SET-005 | ПРИНЯТЬ | Полная таблица состояний через behavior-owner'ов до Фазы 1 |
| SET-006 | ПРИНЯТЬ | `previewContentRect` + transform — обязательный предшественник iPad-композиций |
| SET-007 | ПРИНЯТЬ | Оранжевый на бумаге — только несемантические формы/линии |
| SET-008 | ПРИНЯТЬ | Токены `text.secondary` = white@0.64 (≈7:1), `text.tertiary` = white@0.40 — только ≥17pt semibold или декоративно |
| SET-009 | ПРИНЯТЬ | String Catalog с Фазы 0; ни одной SET OS-строки литералом во View |
| SET-010 | ПРИНЯТЬ | Provenance-таблица + CoreText glyph-тест полного RU+EN набора |
| SET-011 | ПРИНЯТЬ с корректировкой | См. Переопределение O-2 |
| SET-012 | ПРИНЯТЬ | Один effective performance mode от governor'а; UI не интерпретирует |
| SET-013 | ПРИНЯТЬ | Immutable pause snapshot ID + session take counter у pause owner |
| SET-014 | ПРИНЯТЬ | One-shot event ID вне transient View; motion/haptic spy в тестах |
| SET-015 | ПРИНЯТЬ | Названия регистров «ЦЕХ»/«ПЛОЩАДКА» остаются арт-словарём; определение — «non-live editorial» / «live over camera»; preflight до лидера |
| SET-016 | ПРИНЯТЬ | Честная типографическая сетка metadata; fake thumbnails запрещены |
| SET-017 | ПРИНЯТЬ | Layout resolver на container size/aspect + Dynamic Type, не на size class/ориентацию устройства |
| SET-018 | ПРИНЯТЬ | iPad v1 = fullscreen только; Split View/Stage Manager вне acceptance |
| SET-019 | ПРИНЯТЬ | Reduce Motion сохраняет стадии композицией + opacity; пульс → статический индикатор |
| SET-020 | ПРИНЯТЬ | DEBUG-only deterministic fixture root; физический smoke отдельно |
| SET-021 | ПРИНЯТЬ | Golden manifest вместо декартовой матрицы как acceptance |
| SET-022 | ПРИНЯТЬ | Guard в production UI scope с allowlist; доказательства — тесты токенов/glyph, не regex |
| SET-023 | ПРИНЯТЬ | Три уровня: глобальные токены / локальные именованные константы / domain values у owner'ов |
| SET-024 | ПРИНЯТЬ | Статус-бар остаётся скрытым; правила окраски вне v1 |
| SET-025 | ПРИНЯТЬ с копий-таблицей владельца | См. Переопределение O-3 |
| SET-026 | ПРИНЯТЬ | Детерминированные текстуры; вне hit-testing и live-preview |
| ART-01 | ПРИНЯТЬ | Референсы = качества; собственные primitives: crop, registration, call-sheet grid, slate snap, contact strip, ink stamp |
| ART-02 | ПРИНЯТЬ с уточнением объёма | См. Переопределение O-4 |
| ART-03 | ПРИНЯТЬ | Motif budget: 1 hero + 1 supporting на стабильное состояние; матрица пар в v2.1 |
| ART-04 | ПРИНЯТЬ | Live-HUD ортогонален; диагональ — только transition-примитив |
| ART-05 | ПРИНЯТЬ | Lockup (horizontal + stacked) в галерее Фазы 0; иконка приложения вне скоупа |

### Переопределения владельца

**O-1 (SET-004).** Процесс precedence-таблицы принимается. Владелец explicit
одобряет два supersede визуальных положений старых spec/plan в составе v2.1:

1. Shell-навигация: вместо принятой тихой icon-only кнопки 44×44 — капсула
   `A/B ROLL` (КАМЕРА/СЦЕНЫ) со скользящим оранжевым tally-индикатором.
   Обоснование: одинокая иконка без подписи — ровно тот generic-навигационный
   шаблон, от которого уходит продукт; капсула читаема и входит в язык SET OS.
   Условия: роуты, single intent-owner, async teardown, accessibility-ID не
   меняются; hit-target каждого сегмента ≥44pt; shell-тесты обновляются
   адресно (капсула вместо кнопки) в том же изменении, что и v2.1.
2. Слово «резерв» остаётся запрещённым в пользовательском копирайте.
   Fallback-состояние выражается визуально (маркерно-жёлтая метка края chip +
   ровный тусклый tally) и текстом из presentation-слоя без жаргона
   (например «Меньше уверенности — держи то, что видишь»); точный copy
   фиксируется в таблице состояний SET-005.

**O-2 (SET-011).** Монотонный epoch и изолированный renderer принимаются.
Владелец решает: разницы кадров `FF` считаются от nominal 24 fps session
elapsed, документируются как presentation-only (медиа не пишется —
несоответствия с камерой нет); при профилировании, если изолировать
инвалидацию label не удаётся, — деградация до `HH:MM:SS`. При появлении
реальной записи — пересмотр к honest frame count.

**O-3 (SET-025).** Направление принимается; финальный копирайт-сет владельца:

| Элемент | RU | EN |
|---|---|---|
| Плакат entry | СНИМАЙ КИНО | MAKE CINEMA |
| Главный CTA | МОТОР! | ACTION! |
| CTA генерации | ХЛОП! (helper: «Собрать раскадровку») | SLATE IT! (helper: "Build the storyboard") |
| Счётчик | ДУБЛЬ 03 | TAKE 03 |
| Заголовок разбора | РАЗБОР ДУБЛЯ 03 | TAKE 03 — REVIEW |
| Продолжить | ЕЩЁ ДУБЛЬ | ONE MORE TAKE |
| Термин компонента в доках | слейт | slate |

Native EN copy-review обязателен до фиксации golden screenshots.

**O-4 (ART-02).** Принимается: энергия — производственная бюрократия кино,
не агитплакат; без состаривания/грязи/period-косплейя. Уточнение объёма:
статичное зерно 3–4% сохраняется на офлайн-экранах (фактура печати, не aging);
рваный край сокращается до ОДНОГО места (лист сценария) и убирается из
разбора — в пользу motif budget (ART-03).

**O-5 (post-Phase-0 visual correction, 17 августа 2026).** Первая галерея и
последующие approval-макеты показали, что правило ART-03 «один hero + один
supporting motif» недостаточно: даже разрешённая пара могла сделать весь экран
бумажным столом, контактным отпечатком или реквизитом. Владелец отклонил это
направление и зафиксировал более узкую трактовку:

1. Эталон системы — Camera Coach approval-макет portrait + landscape:
   современная тёмная цифровая рама, тёплый белый, один оранжевый и короткие
   пометки «маркером на стекле» со стрелками/подчёркиваниями.
2. `ink / warmWhite / setOrange` — полная фирменная палитра новой галереи;
   `markerYellow` выведен из production visual treatment. Это уточнение
   заменяет только цвет fallback-метки из O-1; safe copy, honest abstention и
   behavior ownership не меняются.
3. Плёнка, перфорация, registration marks и подобные детали разрешены только
   как малые функциональные акценты. Суммарный opaque footprint буквальных
   кино-деталей — не более 8% viewport; основной контент/действие остаётся
   цифровым.
4. Запрещены экран как физический предмет, бумажные рабочие столы, стопки
   листов, скотч, скрепки, карандаши, ticket-like CTA, literal stamp/slate и
   paper-feed. Contact sheet и screenplay задают ритм сетки/типографики, а не
   материал поверхности.
5. На Camera Coach кадр доминирует; corrective = одна короткая команда + одна
   action-linked marker guide. Постоянный ряд `.5 / 1 / 2` скрыт: в покое
   показывается только текущая реальная линза, полный список — по
   взаимодействию.

O-5 не отменяет агрессивную типографику, кинематографическую лексику, лидер,
перфорационный прогресс или motion-язык. Она запрещает буквальный
скевоморфизм как композиционную систему и оставляет его следы только в
микродеталях.

**O-6 (concept approval, 18 августа 2026).** Владелец принял направление
вариантов A/C/D из mobile Scene flow и motion-принцип варианта B:

1. Второй signature primitive — `montage reflow`: активный beat/scene/frame
   получает 45–60% главной оси, соседи сжимаются, но остаются читаемыми и
   tappable. Одна orange `cut seam` обозначает монтажную границу.
2. Вариант A принят для Generator: крупный активный beat, предыдущий/следующий
   как читаемые полосы, marker label объясняет смысл строки.
3. Вариант C принят для Library: максимум три крупные сцены на phone viewport;
   selected row раскрывает реальный preview и два essential metadata либо,
   если preview отсутствует, только расширенный metadata. Fake thumbnails
   остаются запрещены.
4. Вариант D принят для Storyboard: три кадра, центральный selected frame
   расширяется, соседи остаются peeking; orange edge уже сообщает выбор,
   поэтому у `ОПОРНЫЙ КАДР` остаётся underline/bracket без стрелки.
5. Из варианта B принят только transition: cropped oversized percentage и
   seam travel создают impact во время перестройки. В stable state percentage
   полностью читается, equal-card grid не остаётся.
6. Marker semantics становятся нормативными: arrow = movement/pointing from a
   detached label; straight line = horizon/axis без arrowhead; outline =
   object/selection; underline/bracket = text/group. Redundant arrows
   запрещены.
7. Phone landscape — самостоятельный mobile layout: body ≥17pt, action
   ≥44pt, одновременно 3–5 content groups; desktop table/footer запрещены.

**O-7 (visual implementation correction, 18 августа 2026).** Владелец
отклонил первую исполняемую gallery v2.3: выбранные motifs были формально
перенесены в SwiftUI, но экран превратился в постер с фотографией внутри
телефона. Принятая корректировка: portrait Camera Coach возвращает кадру
dominant/full-bleed роль; compact HUD, команда и action-linked glass mark
накладываются прямо на изображение. Pause review остаётся экраном решения
после дубля: кадр + плотная нижняя editorial band, а не большой display
заголовок с воздухом. Горизонтальные экраны сохраняют A/C/D reflow, но несут
реальный рабочий контекст выбранного элемента, а не только три визуальные
панели. Это уточнение меняет только композицию Phase 0 gallery; routes,
teardown, a11y IDs, product state и O-1 precedence не затрагиваются.

## Гейт владельца

Гейт ЗАКРЫТ 17 августа 2026: решения по всем пунктам `SET-001…SET-026` и
`ART-01…ART-05` зафиксированы в разделе «Решения владельца» выше
(27 — принять полностью, 4 — принять с переопределениями O-1…O-4,
отклонённых нет).

**Статус внесения:** SET OS Visual Policy v2.6 опубликована 18 августа 2026.
Дальнейшие ссылки в этом critique на Phase 0, Phase 1 или более узкий план —
исторические pointers, superseded активным полным production scope v2.6.

### O-8 — owner motion correction (принято, 18 августа 2026)

Владелец запросил ощущение живой пометки на режиссёрском мониторе: стрелки,
рамки и подчёркивания должны рисоваться в момент акцента, а не появляться
готовым слоем. Принятая граница: один one-shot vector draw по event ID,
320ms, без анимации video/HUD/grain; `Reduce Motion` показывает полный
маркер без travel/scale/rotation. Это уточняет motion §9 и не меняет routes,
camera state machine, async teardown или accessibility-ID.

**Статус внесения:** SET OS Visual Policy v2.6 опубликована 18 августа 2026.
Принятые формулировки O-1…O-4 сохранены; O-5 адресно корректирует
визуальную грамматику и цвет fallback-метки. Precedence относительно CC-008
по-прежнему ограничен двумя visual clauses, behavior/route/teardown/
accessibility ownership не менялся. O-6 фиксирует утверждённую marker semantics
и montage reflow; O-7 фиксирует full-bleed camera/pause review composition.
Первая executable gallery v2.3 владельцем не одобрена; новая SwiftUI gallery
всё ещё должна пройти отдельный approval. Phase 0 ведётся по
`docs/aegis/plans/2026-08-17-set-os-v2-1-phase-0.md` и останавливается на
отдельном owner approval исполняемой галереи — это историческая запись, не
текущий execution boundary. Findings/evidence critique остаются historical
evidence; v2.6 production authority указана в Visual Policy §0 и §8.

**Исторический указатель:** Phase 0-only план и все более узкие scope
superseded; этот critique не переписывается и не создаёт параллельную policy.

Дальнейшие шаги для имплементатора (исторический список, superseded v2.6):

1. Внести принятые формулировки и переопределения O-1…O-4 адресно в
   `set-os-visual-policy.md` → версия v2.1 с записью в changelog и
   precedence-таблицей к `camera-coach-state-spec.md` (supersede — только
   визуальные положения из O-1; поведение/роуты/teardown/a11y-ID нетронуты).
2. Синхронно обновить затронутые ассерты shell/presentation-тестов (только
   в рамках явно названных supersede из O-1).
3. Переработать Фазу 0 по O-5/O-6 и Visual Policy v2.3; существующие скриншоты
   и компоненты v2.1 не являются approval evidence. После новой исполняемой
   галереи снова остановиться на owner approval.
