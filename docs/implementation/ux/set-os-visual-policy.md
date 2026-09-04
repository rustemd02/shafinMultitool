# SET OS — Visual Policy v2.6

Статус: **v2.6 опубликована; единственная каноническая визуальная политика и execution authority для production UI**  
Дата: 18 августа 2026 года  
Product authority: `docs/app-store-product-plan.md`  
Поведенческий контракт: `docs/implementation/ux/camera-coach-state-spec.md` (CC-008)  
Implementation owner: `shafinMultitool/Multitool2Module/UI/DesignSystem/` — единственный
владелец повторяемых SET OS primitives и их production-исполнения. Этот документ и
этот owner вместе образуют единственную design/execution authority; отдельные
screen-level visual specs не создаются.  
Замена: данная политика отзывает «neutral-surface / no-card-pill-glass-blur-gradient»
политику из `CameraCoachEntryVisualPolicy` и связанные с ней ассерты. Реставрация
дизайна коммита `018ceab` НЕ является целью; оттуда берётся только принцип
«подсказка ↔ визуализация на кадре».

Цель: дизайн — главная фишка Shafin Multitool. Отклонение от политики = баг.
Аудитория: зумеры и миллениалы — Film-TikTok, студенты киношкол, малые
съёмочные команды. Скриншоты приложения должны быть репостируемыми.

### Precedence относительно CC-008 и прежнего shell-плана

SET OS v2.6 сохраняет precedence v2.1 и supersede-ит **только два визуальных
положения**. Поведение,
роуты, single intent-owner, transition lock, async teardown, orientation
forwarding и accessibility identifiers сохраняют владельцев из CC-008 и
`CommercialShellViewController`.

| Источник и прежнее положение | Что superseded в v2.1 | Что явно сохраняется |
|---|---|---|
| CC-008 §3.1/§3.2 и `2026-08-17-camera-coach-fullscreen-navigation.md`: один тихий icon-only top control без capsule | Визуальная оболочка — двухсегментная капсула `A/B ROLL` (`КАМЕРА / СЦЕНЫ`) со скользящим оранжевым tally; каждый сегмент имеет hit target ≥44 pt | Один shell intent-owner, те же `commercial-shell-open-scenes` / `commercial-shell-return-camera`, отсутствие постоянной нижней навигации, route truth и teardown |
| CC-008 S11: honest abstention/fallback не должен выглядеть поломкой | SET OS treatment: тёпло-белая hairline-метка края + ровный тусклый `LIVE`; точный безопасный copy из presentation-слоя, без слова `резерв`. Это цветовое уточнение O-5 заменяет markerYellow-treatment из O-1/v2.1 | Причина/recovery, abstention semantics, rate limit, analytics и accessibility из S11 |

Все остальные расхождения трактуются в пользу CC-008 как behavior authority.
Изменение product state требует отдельного принятого behavior contract, а не
расширения этой визуальной политики.

---

## 0. Процесс и фазы

Канонический активный план: **«SET OS v2.6 — полный production-редизайн
приложения»**. Он покрывает весь достижимый production UI текущего приложения:
Entry, CommercialShell, Camera Coach, library, generator, AR workspace,
storyboard tray/editor и связанные sheets, включая их состояния и
accessibility-варианты из inventory §8. Визуальная policy не создаёт новых
behavior owners: state truth, routes, transition lock, async teardown,
orientation forwarding и accessibility identifiers остаются у CC-008 и
существующих владельцев.

Предыдущие рамки явно закрыты: прежняя «production-интеграция Фаз 1+2»,
Phase 0-only execution scope, разбиение на старые Фазы 1–4 и любая иная более
узкая screen/family scope помечены **superseded** и остаются только исторической
записью. Они не могут ограничить или породить отдельную execution authority.
Исторические документы, включая план
`docs/aegis/plans/2026-08-17-set-os-v2-1-phase-0.md`, сохраняются для evidence и
аудита, но не являются активным планом.

Критика шага 0, решения владельца SET-001…SET-026 и ART-01…ART-05, а также
O-1…O-8 являются принятым историческим основанием v2.6. Их findings/evidence
сохраняются; возвращать generic UI, neutral surfaces или отвергнутые literal
props через «новую фазу» запрещено.

### Normative v2.6 package sequence

Активная execution sequence строго линейна: **Publication doc round → Package 1
Entry/Shell → Package 2 Camera → Package 3 Library → Package 4 Generator →
Package 5 AR/playback/recording → Package 6 Storyboard/secondary → cleanup
reachability audit only**. Publication doc round — это этот v2.6 документ и его
status pointers; он не считается production package и не разрешает пропускать
approval gates.

Каждый production package ниже обязан пройти одинаковый gate: **Luna/Max
implementation; independent Sol diff/build/test/evidence audit; RU+EN production
screenshots; все указанные required orientations; минимум один Reduce Motion и
один Dynamic Type вариант; motion video для каждого нового moving motif; затем
STOP для explicit owner visual approval**. Следующий package запрещён до этого
approval; gallery-only evidence v2.5 не заменяет production evidence.

Это правило STOP — нормативный default и историческая baseline для обычного
перехода между пакетами. Принятый v2.6 override владельца от 2026-08-21:
после закрытого Package 2 Пакеты 3–6 допускается доводить механически подряд до
финального Package 6 gate без промежуточных owner-STOP; полный mechanical gate
каждого пакета сохраняется, а финальный визуальный вердикт владельца следует
после Package 6. На 2026-08-25 финальный Package 6 visual gate **CLOSED** для
source + simulator visual flow; physical-device pre-release blocker остаётся
открытым, Package 5 owner approval не утверждается, полный v2.6
production-ready статус остаётся открытым.

1. **Package 1 — Entry/Shell**: Entry resolving/requesting/ready/intro/permission/
   blocked×4 и CommercialShell camera/scenes selection, locked transition,
   blocked teardown; required orientations **portrait + landscape**, включая
   fullscreen iPad policy. Применяется полный gate выше; после него STOP.
2. **Package 2 — Camera**: camera lifecycle, live presentation, lens switching,
   ECO, pause loading/success/empty/failure/resume; required orientations
   **portrait + landscape**. Применяется полный gate выше; после него STOP.
3. **Package 3 — Library**: empty/loaded/selected/create-name/duplicate-name/
   delete confirmation/persistence failure; required orientation
   **landscape-only**. Применяется полный gate выше; после него STOP.
4. **Package 4 — Generator**: input, keyboard, marked/detected objects,
   clarification, accepted/leader/progress/background-cancel/failure/retry/
   success; required orientation **landscape-only**. Применяется полный gate
   выше; после него STOP.
5. **Package 5 — AR/playback/recording**: AR preparing/ready/surface search/
   placement/marking/live hints/hint pause/playback/recording/interruption/
   error/teardown; required orientation **landscape-only**. Применяется полный
   gate выше; после него STOP.
6. **Package 6 — Storyboard/secondary**: storyboard tray/selection/result/
   inspector/editor/saving/validation/delete, reachable sheets and Decision
   Trace; required orientation **landscape-only**. Применяется полный gate
   выше; после него STOP.

После Package 6 допускается только cleanup reachability audit: он документирует
зависимости и removal candidates, но не restyle-ит и не удаляет legacy routes.

Следующий список — **исторический execution record (superseded)**. Он объясняет
уже проверенные артефакты, но не задаёт текущий scope и не требует отдельного
approval-гейта перед выполнением v2.6.

- **Шаг 0 — прожарка политики (закрыт 2026-08-17).** До любого кода имплементатор проводит
  деструктивное ревью этого документа и публикует
  `docs/implementation/ux/set-os-policy-critique.md` (формат: находки
  `[BLOCKER|MAJOR|MINOR]` + раздел + сценарий поломки + правка «было → стало»;
  раздел альтернатив по арт-дирекшну; top-5 правок). Правки вносятся в политику
  только после решения владельца по каждой (принять/отклонить), версией v2.1
  с записью в changelog. Молчаливое согласие или вежливое «всё хорошо» =
  провал шага 0. Использовать критику как лазейку вернуть generic-дизайн
  запрещено. Решения владельца по SET-001…SET-026 и ART-01…ART-05, включая
  O-1…O-4, зафиксированы в critique; отклонённых пунктов нет.
- **Фаза 0 — approval-гейт галереи (исторический v2.1–v2.5 scope).** Создать
  `shafinMultitool/Multitool2Module/UI/DesignSystem/` (токены, шрифты,
  переиспользуемые компоненты) и `DesignSystemPreviews.swift` — исполняемую
  галерею: все компоненты, все состояния, мокапы всех экранов, RU+EN,
  варианты Reduce Motion / Reduce Transparency / XXL type. Интеграция в
  реальные экраны начинается ТОЛЬКО после явного одобрения галереи владельцем.
  Этот Phase 0-only boundary superseded планом v2.6; существующие gallery
  artifacts остаются evidence, а не production authority.
- **Фаза 1:** Entry flow (все фазы, включая blocked×4) + shell-капсула A/B ROLL.
- **Фаза 2:** Camera Coach live (таблица состояний §7, tally, таймкод, ECO-бейдж,
  зум из реальных `availableLenses`) + пауза-разбор маркерными аннотациями.
- **Фаза 3:** Scene Generator (плоская редакционная рабочая область, лидер →
  перфорационный прогресс-акцент), библиотека в ритме контактшита,
  AR-оверлеи в языке HUD.
- **Фаза 4 (историческая):** вторичные экраны (EditScript, StageSelection — рестайл без
  редизайна информационной архитектуры), guard-тесты, evidence-скриншот-матрица,
  обновление доков.

Не-цели v1 (запрещено тратить время): портретный Scene-workspace, светлая тема,
иконка приложения (уже есть), скриншоты стора, звук, анимация зерна, UI для
history/«Дайли» (роут и enum остаются как есть, недостижимыми из навигации —
не трогать, их тесты не переписывать; см. CC-008 §3.1). History-stub, Debug,
Performance, Benchmark и `docs/thesis/litreview*` остаются untouched и вне
visual scope.

## 1. Мир

Один образ — современный цифровой режиссёрский монитор. Два регистра одной
системы:

- **«ЦЕХ»** — non-live editorial surfaces (entry, генератор, библиотека,
  разбор): плоская тёмная кинополиграфика. Сверхкрупный узкий заголовок,
  асимметричная композиция, строгая сетка и тёмные цифровые плоскости.
  Маркер, плёнка, перфорация и монтажные метки появляются только как малые
  функциональные акценты; они не превращаются в материал или каркас экрана.
- **«ПЛОЩАДКА»** — live-камера и AR-оверлеи: сдержанный профессиональный
  cine-HUD. Разборчивость поверх реального видео; полиграфический шум
  запрещён. «Цех» может быть типографически громким, но остаётся цифровым;
  «Площадка» — тихая и подчинена кадру.

Контраст регистров — намеренная часть продукта. Референсы задают качества,
а не копируемые композиции: редакционную смелость, монтажный ритм и ясную
event-анимацию. Собственные primitives SET OS: `glass mark`, `crop`,
`registration`, `editorial grid`, `film edge`,
`contact rhythm`, `slate snap`.

Энергия берётся из производственной бюрократии кино — call sheets, паспортов
плёнки, монтажных пометок и лабораторной маркировки, — не из агитплаката.
Запрещены прямое копирование узнаваемых layouts/HUD silhouettes/transitions,
буквальная советская/историческая символика, государственные эмблемы,
состаривание, грязь, propaganda-like лозунговая композиция и period cosplay.
Статичное зерно 3–4% допустимо только как едва заметная фактура тёмной
цифровой плоскости, а не как имитация бумаги или возраста.

### 1.1. Базовый приём: «маркер на стекле»

Фирменный слой SET OS — короткая редакторская пометка поверх изображения или
плоской цифровой поверхности: свободная линия, подчёркивание, окружность,
стрелка и подпись из 1–4 слов. Она выглядит так, будто оператор сделал пометку
белым или оранжевым grease pencil на стекле режиссёрского монитора, но
реализуется чистым вектором без blur, тени и симуляции толщины стекла.

- Пометка всегда указывает на конкретный объект, границу, направление или
  выбранный элемент. Декоративные стрелки «в никуда» запрещены.
- Одна задача = одна связка `текст + линия/стрелка`. Несколько конкурирующих
  рукописных комментариев на одном состоянии запрещены.
- Пометка не становится карточкой, модальным контейнером или фоном текста;
  она живёт прямо на кадре либо рядом с отмечаемым объектом.
- Белый маркер — объяснение/геометрия; `setOrange` — активная команда,
  выбранный объект или единственная точка внимания. Жёлтый в этом приёме не
  используется.
- Смысл не хранится только в рисунке: accessibility label содержит полную
  команду, а при Reduce Motion аннотация появляется fade-ом целиком.
- В обычном режиме actionable `glass mark` рисуется один раз по event ID:
  хвост → линия → наконечник стрелки либо замыкание рамки. Это короткий
  320ms-жест, не постоянная декоративная анимация; HUD, видео и зерно не
  анимируются ради эффекта.
- Референс-эталон направления: Camera Coach approval-макет от 17 августа 2026
  (portrait + landscape: тёмная рама, тёплый белый, один оранжевый, короткая
  команда и маркерная стрелка). Эталон фиксирует грамматику, а не конкретный
  сюжет, копирайт или геометрию изображения.

Семантика формы обязательна:

| Форма | Единственная допустимая роль | Запрет |
|---|---|---|
| Стрелка | физическое направление действия либо связь удалённой подписи с конкретным объектом | стрелка на горизонте/оси, рядом с уже достаточной selection-рамкой или ради композиции |
| Прямая линия | горизонт, уровень, ось, граница кадрирования | arrowhead и декоративный изгиб, меняющий смысл |
| Окружность/обводка | объект, выбранная зона или crop area | закрывать лицо/главный объект; обводить весь экран без локальной цели |
| Подчёркивание/скобка | акцент текста, выбранной строки или группы | дублировать одновременно рамку, цвет и стрелку |

### 1.2. Второй фирменный приём: montage reflow

На non-live рабочих экранах активный фрагмент получает больше места в сетке,
а соседние фрагменты сжимаются, оставаясь читаемыми. Тонкая вертикальная или
горизонтальная `cut seam`-линия `setOrange` отмечает границу перестройки. Это
цифровая монтажная операция, не физическая плёнка и не набор карточек.

- Reflow запускается только сменой выбора, стадии или фокуса; постоянная
  случайная асимметрия запрещена.
- Активный фрагмент занимает 45–60% главной оси; соседние показывают минимум
  идентификатор + одно смысловое поле и остаются tappable ≥44 pt.
- В стабильном состоянии весь semantic text читаем и не обрезан. Крупный
  cropped numeral/percentage разрешён только во время transition и после
  завершения возвращается в читаемую safe area.
- На один экран — одна `cut seam`. Она считается тем же orange focus, что и
  selection edge, и не создаёт второй конкурирующий акцент.
- Маркерная подпись объясняет содержание активного фрагмента, а не сам факт
  reflow. Если orange seam/outline уже однозначно показывает выбор, стрелка к
  нему запрещена; остаётся underline или bracket.
- Reduce Motion: размеры меняются мгновенно, затем content crossfade 120ms;
  seam не travels. В обычном режиме reflow использует один spring preset и
  завершает геометрию до появления marker annotation.

### 1.3. Экран — инструмент, не постер

Утверждённый концепт задаёт иерархию продукта, а не набор декоративных
primitives. Нельзя помещать кадр в большую пустую афишную рамку и объявлять
это Camera Coach.

- **Portrait live-camera:** изображение занимает почти весь usable viewport;
  HUD и короткая команда живут поверх кадра в компактных edge-зонах. Внешняя
  чёрная рамка допускается только как hairline/безопасная зона, не как второй
  «экран вокруг экрана». В stable live нет крупного display-заголовка.
- **Corrective:** одна короткая команда располагается в нижней HUD-зоне
  поверх кадра. Стрелка начинается рядом с командой и заканчивается у
  физически исправляемой области; она не может указывать в пустую плоскость.
- **Pause review:** это плотный экран решения после дубля, а не промо-постер.
  Кадр остаётся героем, а `TAKE`/`CUT!`, observation и CTA образуют компактную
  нижнюю editorial band. Display-типографика не вытесняет действия ниже fold.
  Обводка отмечает только реальную область разбора; рваный край/film edge
  возможны лишь как один микроакцент на границе band.
- **Landscape non-live:** generator/library/storyboard несут рабочую плотность
  выбранного beat/scene/frame и его next action. Три панели сами по себе не
  образуют продуктовый экран: нужны читаемые production metadata, selection
  state и один связанный marker note без desktop-table density.

### 1.4. Approved art code v2.6

Четыре референсных регистра превращаются в собственный код SET OS, а не в
копируемые layouts:

- **Soviet print** задаёт baseline grid, дисциплину полей, tabular metadata и
  жёсткую типографическую иерархию. Это сетка и набор, не историческая
  символика, эмблема, лозунг или имитация агитплаката.
- **A24** задаёт restraint, negative space и приоритет hero frame/content:
  воздух обслуживает читаемость и действие, а не превращает экран в постер.
- **Film** используется функционально: A/B ROLL, лидер, честный timecode,
  contact sheet, перфорация и cut seam показывают production state или
  монтажную операцию. Они не становятся материальной поверхностью или
  контейнером.
- **Micro-skeuomorphism** — только пунктуация: один тонкий mark, edge rhythm,
  registration или cut-mark там, где это объясняет действие или состояние.
  Никаких бумажных столов, объёмного реквизита, realistic film-stock или
  material/glass imitation.

Палитра ограничена `ink`, `warmWhite` и **одним** активным `setOrange`.
На стабильном состоянии буквальные production-мотивы занимают не более 8%
viewport; одновременно разрешены максимум один функциональный annotation motif
и один малый cinematic accent. Hero остаётся пользовательским контентом,
кадром или основным действием. Эти правила применяются к каждой строке
production inventory §8 и не ослабляются для Dynamic Type, landscape или
accessibility-вариантов.

## 2. Локализация и язык

RU — базовый, EN — первая локаль. Приложение двуязычное с первого релиза.

- Финальный copy-set владельца фиксирован таблицей и НЕ переводится машинно:

| Элемент | RU | EN |
|---|---|---|
| Плакат entry | СНИМАЙ КИНО | MAKE CINEMA |
| Главный CTA | МОТОР! | ACTION! |
| CTA генерации | ХЛОП! | SLATE IT! |
| Helper генерации | Собрать раскадровку | Build the storyboard |
| Счётчик | ДУБЛЬ 03 | TAKE 03 |
| Заголовок разбора | РАЗБОР ДУБЛЯ 03 | TAKE 03 — REVIEW |
| Продолжить | ЕЩЁ ДУБЛЬ | ONE MORE TAKE |
| Штамп паузы | СНЯТО! | CUT! |
| Термин компонента в документации | слейт | slate |
| Fallback/abstention | Меньше уверенности — держи то, что видишь | Less certain — hold what you see |

Native EN copy-review обязателен до фиксации golden screenshots. До него EN
строки считаются owner-approved рабочим copy, но не финальным language QA.

- HUD-термины остаются латиницей В ОБОИХ локалях — как на реальных камерах:
  `LIVE`, `STANDBY`, `ECO`, `INT./EXT.`, `A/B ROLL`. `REC` зарезервирован
  только за будущим состоянием реальной записи медиа (CC-008 §3.1) и не
  используется для текущего live-анализа.
- Подсказки коуча: тон «второй оператор, который хочет тебе помочь» — на «ты»,
  конкретное действие первым («Отодвинь камеру — в кадре мало воздуха»), одна
  мысль на подсказку, максимум 2 строки до свёртки. Инженерные формулировки
  («низкая уверенность детекции») запрещены.
- Длины строк: EN ≈ на 20–30% короче RU. Плакатные заголовки — max 2 строки в
  обоих локалях, перенос по словам. Обрезка краем экрана допустима только у
  display-шрифта и только нижней границей.
- Wordmark `SHAFIN MULTITOOL` — латиницей в обеих локалях (решение владельца
  зафиксировано). Он имеет две master-композиции — horizontal и stacked — с
  фиксированными crop/tracking/line-break и clear-space tokens; произвольный
  набор названия тем же шрифтом не считается логотипом.
- Phase 0 использует String Catalog для всех SET OS copy и локализованных
  accessibility label/value. Ни одна видимая SET OS-строка не хранится
  литералом во View. Deterministic locale override разрешён только previews и
  UI-tests; acceptance включает запуск app target на RU и EN.

## 3. Цвет и контраст (WCAG обязателен)

- `ink #0B0B0E` — базовый фон. Приложение dark-locked:
  `.preferredColorScheme(.dark)` везде.
- `surface.solid #141419` — единственная базовая приподнятая поверхность.
  Иерархия строится границей, сеткой и типографикой, не имитацией материала.
- `paper #F4F1EA` переименовывается по смыслу в `warmWhite #F4F1EA`: это цвет
  основного текста, hairline и белого маркера. Он не разрешает автоматически
  бумажную текстуру, лист, билет или светлую карточку.
- `setOrange #FF5A1F` — единственный активный цвет: tally/LIVE, focus edge,
  ретикула, активная команда и отметки редактора. Большая заливка CTA не
  является базовым паттерном; CTA по умолчанию тёмный с warmWhite-текстом и
  одним оранжевым marker/focus accent.
- `markerYellow #FFD02F` выведен из визуальной палитры O-5. Существующий token
  временно может оставаться только для миграции/теста v2.1, но production UI и
  новая галерея его не используют.
- Правила контраста (проверяются guard-тестом):
  - Текст на оранжевой плашке — ТОЛЬКО `ink` (6.3:1, AA). Белый на оранжевом
    запрещён (3.1:1).
  - Orange/warmWhite = 2.77:1 и не проходит даже large-text AA. Orange на
    warmWhite разрешён только для несемантических линий и малых декоративных
    форм; весь читаемый текст на warmWhite — ink.
  - `text.primary` = warmWhite/ink; `text.secondary` = warmWhite@0.64 на ink
    (≈8.2:1); `text.tertiary` = white@0.40 (≈3.8:1) — только ≥17pt semibold
    либо декоративно, не для обычного semantic body.
  - Любой semantic text: ≥4.5:1 normal, ≥3:1 large. Текст live-HUD всегда
    лежит на `hud.scrim`, а не непосредственно на видео.
- `hud.scrim` = ink@0.72 + hairline white@0.14. Разрешён вертикальный
  ink-fade без blur; запрещено семантически полагаться на один opacity без
  контрастной подложки.
- Reduce Transparency: `hud.scrim` и любые допустимые non-live translucent
  surfaces → `surface.solid #141419` без изменения размеров.
- Цветовой вес собственной UI-графики (без учёта цветов camera/photo content):
  тёмная основа занимает 88–94%; тёплый белый и нейтральные hairline — 5–10%;
  `setOrange` — не более 2% площади стабильного состояния. Оранжевый не
  размазывается по нескольким одинаково сильным зонам.
- Запрещены: сине-фиолетовые градиенты, неон, зелёно-красная семантика
  статусов, радужные акценты.

## 4. Типографика (билингвальная матрица)

Все локализуемые роли обязаны покрывать полный продуктовый RU+EN charset.
Bebas Neue — единственное исключение: он используется только в неизменяемом
латинском wordmark.

- Wordmark: **Bebas Neue**; локализуемый текст этим токеном запрещён.
- Display: **Oswald** для всех RU+EN заголовков и слоганов.
- HUD/mono: **JetBrains Mono**. Space Mono запрещён — нет кириллицы.
- Сценарий: **PT Mono**; системный Courier New — runtime fallback.
- Рукописные пометки: **Caveat**, только короткий decorative copy; смысл
  дублируется обычным доступным текстом.
- UI-текст: SF Pro + Dynamic Type (обязательно).
- Command/action labels are Oswald with bounded 22→34pt Dynamic Type scaling;
  body remains SF Pro unbounded/scrollable; the mono helper does not become a
  second hero. At accessibility sizes, command and helper reflow vertically
  with a shared leading edge; standard sizes retain the compact command/helper
  rhythm.
- Fallback-правило: каждый кастомный шрифт инициализируется через typed-токен
  (`.display`, `.hudMono`, `.screenplay`, `.hand`) с системным fallback, если
  шрифт не загрузился. Проверка загрузки на старте — лог в DiagnosticsLogger.
- Шкала: 64/48/34/22/17/13/11. Display — fixed (декоративен), кроме
  bounded command/action scale 22→34pt; SF Pro — relative (масштабируется).
  Tracking: display −0.01em, mono +0.05em, tabular numerals для всего моно.

### 4.1. Font provenance (bundle Phase 0)

Upstream snapshot: `google/fonts@e1118da94a8cb00cf6d06cdac9ef13eb1e5c6ab7`.
Все файлы лицензированы SIL Open Font License 1.1; соответствующие OFL texts
хранятся рядом с assets. Переименование bundle-файла не меняет binary hash.

| Роль | Bundle filename | Upstream filename | PostScript name | Version pin | SHA-256 | Runtime fallback |
|---|---|---|---|---|---|---|
| wordmark | `BebasNeue-Regular.ttf` | `ofl/bebasneue/BebasNeue-Regular.ttf` | `BebasNeue-Regular` | snapshot commit выше; internal 2.000 | `08e4623805102d819f58601e46e345648846075e363b2ceb23313c2d1c83ec73` | `AvenirNextCondensed-DemiBold` только для diagnostic failure, не golden |
| display | `Oswald-Variable.ttf` | `ofl/oswald/Oswald[wght].ttf` | `Oswald-Regular` | snapshot commit выше | `5b38c246e255a12f5712d640d56bcced0472466fc68983d2d0410ec0457c2817` | `AvenirNextCondensed-Bold` |
| hudMono | `JetBrainsMono-Variable.ttf` | `ofl/jetbrainsmono/JetBrainsMono[wght].ttf` | `JetBrainsMono-Regular` | snapshot commit выше | `48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda` | system `.monospaced` |
| screenplay | `PTM55FT.ttf` | `ofl/ptmono/PTM55FT.ttf` | `PTMono-Regular` | snapshot commit выше; internal 1.001 | `cbe732b3b8fd211fd986ebdfc9b870ddeca4faab0bb5425fc509b37f9b4ac804` | `Courier New` → system `.monospaced` |
| hand | `Caveat-Variable.ttf` | `ofl/caveat/Caveat[wght].ttf` | `Caveat-Regular` | snapshot commit выше | `0bdb6b660482d31531b3945849fba5916b3ef8695da7024a9e6b9ee3c4157988` | system `.rounded` only outside golden |

Phase 0 содержит две независимые проверки: (1) exact filename/PostScript/hash,
(2) `CTFontGetGlyphsForCharacters` для полного продуктового charset, включая
`Ёж, съёмка № 03 — TAKE 12:34:56:23`. Screenshot подтверждает метрики, но не
заменяет glyph-тест.

## 5. Токены и границы владения числами

`UI/DesignSystem/` содержит: цвета, типографику, `spacing: 4/8/12/16/24/32/48`,
`radii: 0 (editorial panels) / 8 (контролы) / 14 (chips) / 999 (капсулы)`,
hairline 0.5/1, spring/duration-пресеты, haptic-хелперы и переиспользуемые
компоненты (`GlassMarkGuide`, `MarkerAnnotation`, `CutSeam`, `ReflowLayout`,
`MontageReflow`, `FilmEdge`, `LeaderCountdown`, `TallyBadge`, `TimecodeView`,
`HUDChip`, `DigitalAction`, `ABRollCapsule`). Детерминированное зерно остаётся
разрешённым optional non-live asset, но не является обязательным компонентом
или surface по умолчанию.
`PaperSheet`, ticket-like CTA и `ReviewStamp` как самостоятельные контейнеры
считаются отклонённым направлением Фазы 0 и не входят в production API.

Три уровня чисел:

1. Global tokens — повторяемые visual primitives и semantic design values.
2. Feature-local named constants — уникальная геометрия одного компонента,
   объявленная рядом с ним и названная по смыслу.
3. Domain values — fps, timeouts, camera transforms, ML thresholds — остаются
   только у domain owner и запрещены в DesignSystem.

Голые необъяснённые literals во View запрещены; перенос любого числа в
глобальный token только ради прохождения guard тоже запрещён.

Материалы (выбор зафиксирован, разночтений нет):

- Над live-preview запрещены SwiftUI Material, `UIVisualEffectView`, backdrop
  blur и тени для всех элементов, включая неподвижный chrome. Верхняя панель,
  chip и shell capsule используют `hud.scrim` = ink@0.72 (либо вертикальный
  ink-fade без blur) + hairline white@0.14. Reduce Transparency делает scrim
  непрозрачным `surface.solid`.
- Per-frame слой (ретикулы, стрелки, боксы) — чистый вектор без
  материалов/теней/blur. Контраст оранжевого на видео — двойной штрих:
  оранжевый 2pt + внешняя black@0.6 hairline 1pt.
- Зерно: один deterministic PNG 256×256, статичный, overlay на ink,
  opacity 3–4%, только non-live surfaces. Текстуры не
  регенерируются при render, не участвуют в hit testing и скрыты от
  accessibility.

## 6. Мотивы (микроакценты, а не декорации)

Ни один мотив не получает право превратить весь экран в физический предмет.
Плёнка, перфорация, маркировка и заметка — это пунктуация интерфейса. Суммарная
непрозрачная площадь буквальных кино-деталей на стабильном состоянии — не
более 8% viewport; они не служат основным контейнером данных, навигацией или
формой CTA. Маркерные линии могут быть длиннее, но остаются тонкими и не
закрывают лицо, объект съёмки или читаемый контент.

1. **Лидер** `3→2→1→МОТОР!`: допускается только при первом входе камеры за
   session и при принятом behavior-owner'ом старте генератора. На повторный
   вход, rotation, re-render или recomposition лидер не проигрывается; отдельная
   настройка «отключить лидер» остаётся future.
2. **Длинная загрузка** (генерация на llama.cpp — десятки секунд): после лидера —
   перфорационный прогресс + ротация статусных строк моно («Читаю сценарий…»,
   «Ставлю анкеры…», «Считаю кадр…»). Лидер НЕ маскирует ожидание.
3. **Слейт**: компактная цифровая метка = номер, INT./EXT., ДЕНЬ/НОЧЬ, дубль;
   подтверждение генерации — абстрактный хлопок двух линий 180ms + settle
   120ms + rigid haptic. Фотореалистичная хлопушка и карточка-реквизит
   запрещены.
4. **Tally**: `● LIVE` (пульс 1.2s) во время анализа; `STANDBY` на паузе.
   `REC` не показывается без реальной записи медиа.
5. **Timecode**: mono session elapsed от monotonic epoch. `FF` presentation-only
   и считается по nominal 24 fps; label renderer изолирован от остального HUD.
   Если профилирование не подтверждает изоляцию invalidation — деградация до
   `HH:MM:SS`. При появлении реальной записи правило пересматривается в пользу
   honest media frame count.
6. **Cut-mark** `СНЯТО!`: короткая типографическая отметка с одной маркерной
   окружностью или чертой, 220ms + settle 160ms; Reduce Motion — fade.
   Буквальный резиновый штамп, чернильный отпечаток и бумажная печать запрещены.
7. **Перфорация** — узкая граница карусели или индикатор прогресса; не рамка
   всего экрана и не физическая лента с объёмом.
8. **Заметки монтажёра**: короткая пометка «маркером на стекле» — mono-номер,
   одно подчёркивание/окружность/стрелка и до четырёх слов Caveat.
9. **Физическая бумага**: рваные края, скотч, скрепки, стопки листов, билеты,
   карандаши и объёмные paper-feed механизмы запрещены как UI-композиция.
   Нейтральная плоская screenplay-сетка может цитировать поля сценария только
   типографикой и hairline.

One-shot motion и haptic получают event ID от session/operation owner вне
transient View. Rotation, recomposition и route recreation не повторяют уже
consumed event. Async completion сверяет актуальную route/session generation.

### 6.1. Motif budget

На одном стабильном состоянии разрешён один функциональный annotation motif и
максимум один малый cinematic accent. Ни один из них не может быть «hero
object»: герой экрана — пользовательский контент, кадр или основное действие.
Transition motif исчезает после completion; всё, чего нет в матрице, на этом
состоянии запрещено.

| Surface/state | Annotation motif | Малый cinematic accent | Запрещено одновременно |
|---|---|---|---|
| Entry intro/permission/blocked | один marker underline/circle | registration mark либо узкий film edge | физический реквизит, бумажный CTA, скотч, torn edge |
| Shell capsule | sliding tally | A/B production label | grain, stamp, diagonal stable layout |
| Camera live | отсутствует | timecode + тихий `LIVE` как единый HUD accent | grain, paper, stamp, perforation |
| Camera corrective | action-linked glass-mark guide | короткая оранжевая команда без card background | diagonal decoration, paper, stamp, крупный chip |
| Camera fallback/abstention | warmWhite hairline edge | dim steady `LIVE` | markerYellow, `РЕЗЕРВ`, pulse, stamp |
| Pause-review | glass-mark circle/underline | compact `СНЯТО!` cut-mark | paper panel, torn edge, tape, literal stamp, perforation |
| Generator preflight/input | marker label активного beat | одна cut seam + reflow | paper stack, clipboard, pencil prop, leader before request accepted |
| Generator progress | marker state label | reflow + seam; perforation только edge micro-rhythm | cropped stable percentage, equal card grid, paper feed, stamp |
| Generator result | underline/bracket выбранного кадра | reflow + одна selection seam | redundant arrow, physical slate, leader replay, stamp |
| Library | marker bracket выбранной сцены | expanded selected row + cut seam | spreadsheet, equal card grid, fake preview, photopaper, tape, stamp |
| AR workspace | orthogonal HUD anchors | active orange registration | grain, paper, diagonal stable layout |

Статический live-HUD всегда ортогонален и camera-safe. Диагональ — только
краткий transition primitive; она не пересекает functional guide и не живёт
дольше transition budget.

## 7. Состояния Camera Coach (ядро продукта)

Таблица — visual projection behavior-owner’ов, не параллельная state machine.
Если owner ещё не публикует строку состояния/event ID, соответствующий UI не
выводится в production до Phase 2. Phase 0 fixture при этом обязателен.

| Visual state | Behavior source / owner | Вход → выход | Допустимые действия | Exact copy RU / EN | Accessibility announcement | Fixture ID |
|---|---|---|---|---|---|---|
| camera starting | `CameraManager` lifecycle через `CameraViewModel` | start requested → running / failed / interrupted | cancel route только через shell owner | `ГОТОВЛЮ КАМЕРУ…` / `PREPARING CAMERA…` | один раз при задержке, не на каждый frame | `camera.starting` |
| camera interrupted | camera lifecycle owner | interruption began → recovered / failed | `ПОВТОРИТЬ` только если owner разрешает retry | `КАМЕРА ПРИОСТАНОВЛЕНА` / `CAMERA INTERRUPTED` | причина + доступное recovery | `camera.interrupted` |
| camera failed | camera lifecycle owner | unrecoverable start/runtime failure → retry / route exit | retry либо существующий shell action | `КАМЕРА НЕДОСТУПНА` / `CAMERA UNAVAILABLE` | error и action, не только цвет | `camera.failed` |
| waiting / seeking | `CameraOverlayUXPresentation.liveSeeking` | valid running session, no stable hint → stable/keep/fallback/pause | pause, поддержанные camera controls | `Ищу главное в кадре…` / `Finding the subject…` | status обновляется без repeated focus steal | `camera.seeking` |
| keepAsIs | `CameraOverlayUXPresentation.keepAsIs` | strong-frame verdict → scene change / pause | снимать, pause, explanation только если owner даёт | `Кадр уже сбалансирован` / `The frame is balanced` | полноценный verdict + основание | `camera.keep` |
| corrective | `CameraOverlayUXPresentation.stableTip` | stable actionable hint → explanation / replaced after owner gate / pause | одно физическое действие, `Почему?` | action-first copy из presentation catalog | observation + action объявляются один раз | `camera.corrective` |
| fallback / honest abstention | `CameraOverlayUXPresentation.isFallback` / CC-008 S11 | invalid/insufficient evidence → recovered seeking / user continues | продолжить без совета; recovery только от owner | `Меньше уверенности — держи то, что видишь` / `Less certain — hold what you see` | copy + recovery; marker не единственный носитель | `camera.fallback` |
| explanation | presentation parent state + expansion owner | explicit expand → collapse / parent exits | collapse; parent action остаётся главным | безопасное supporting explanation из presentation | один grouped announcement, без повторного live tip | `camera.explanation` |
| lens switching | `CameraViewModel` lens transaction | user selects available lens → success / rollback / failure | выбранный transaction lock; повторный tap не запускает второй switch | active real-device label; failure uses localized recovery | selected/value + failure без fake focal length | `camera.lens-switching` |
| pause loading | pause owner | immutable snapshot accepted → success / empty / failure / cancelled | resume/cancel по owner contract | `СОБИРАЮ РАЗБОР…` / `BUILDING THE REVIEW…` | announce once; progress не тикает | `camera.pause-loading` |
| pause success | pause owner + immutable snapshot ID / take counter | critique success → resume / route exit | `ЕЩЁ ДУБЛЬ`; supported review actions | `РАЗБОР ДУБЛЯ N` / `TAKE N — REVIEW` (N is the session-owned take number) | take, summary, затем actions в reading order | `camera.pause-success` |
| pause empty | pause owner | valid snapshot, no critique → resume / retry if allowed | `ЕЩЁ ДУБЛЬ`; retry только от owner | `ПОКА БЕЗ ЗАМЕТОК` / `NO NOTES YET` | empty не объявляется ошибкой | `camera.pause-empty` |
| pause failure | pause owner | no evidence / render failure / pipeline unavailable / timeout → recovery; stale/cancelled completion is discarded | owner-approved recovery, `ЕЩЁ ДУБЛЬ` | reason-specific localized title/detail/action | failure + action; не silent empty | `camera.pause-failure` |
| resume | pause owner | resume accepted → previous live context | interaction locked до running | `ВОЗВРАЩАЮСЬ В КАДР…` / `BACK TO THE FRAME…` | announce только при заметной задержке | `camera.resuming` |
| effective ECO overlay | single thermal/power governor mode | effective mode normal → reduced → normal | нет отдельного action | `ECO · Анализ в экономном режиме` / `ECO · Reduced analysis` | mode change rate-limited; reason не выдумывается | `camera.eco` |

Visual treatment:

- seeking: `hud.scrim`, dim `LIVE`, без guide;
- keep: white hairline, steady `LIVE`, без positive green;
- corrective: одна короткая команда (предпочтительно одна строка) у safe edge +
  action-linked glass-mark guide. Текст и стрелка работают как одна пометка;
  отдельная AI-card, confidence label и декоративная цветная рейка запрещены;
- пространственная corrective-команда (сместить кадр / подойти / отойти) и её
  marker допустимы только после общего live evidence gate: свежий Vision,
  согласованные semantic/snapshot области главного объекта и отсутствие любой
  ambiguity. При неполном основании HUD остаётся в `seeking` либо honest
  abstention — стрелка, demo override и legacy fallback не могут обойти это
  правило;
- такой marker публикуется только на третьей последовательной согласованной
  оценке неподвижного кадра с тем же действием; повторный/старый timestamp,
  разрыв, смена действия, движение или lifecycle reset начинают подтверждение
  заново. До этого текущая non-spatial подсказка не заменяется пустым HUD;
- fallback: warmWhite hairline edge, steady dim `LIVE`, слово
  `резерв` запрещено;
- explanation: раскрытие внутри того же semantic parent, без нового state owner;
- pause: live chip скрыт, `STANDBY`, review на immutable snapshot;
- ECO — additive badge от единого effective performance mode, UI сам не
  интерпретирует thermal/battery reason.

Pause snapshot ID, session take counter и one-shot cut-mark event (legacy
`stamp event` ID допустим внутри behavior-owner, но не как visual component)
принадлежат pause owner, переживают rotation и сбрасываются только явным
session reset.
Motion/haptic tests используют injected spy и доказывают отсутствие повторов.

ZoomControl: в спокойном состоянии видна только текущая линза из РЕАЛЬНОГО
`availableLenses` устройства — эквивалентное фокусное, если оно известно,
иначе кратность. Полный список раскрывается только по явному взаимодействию и
после выбора снова сворачивается. Жёсткий хардкод мм запрещён (врёт про
железо); постоянный ряд `.5 / 1 / 2` запрещён как визуально избыточный для
сценария художественной съёмки.

Плотность определяет layout resolver по container size/aspect, safe areas и
Dynamic Type, а не по `UIDevice.orientation` и не только по size class. На
узком container: timecode без `FF`, confidence (если когда-либо разрешён
behavior contract) внутри chip, подпись только активной линзы. Minimum
content width/height и порядок collapse покрываются geometry/layout tests.

До iPad letterbox preview owner обязан публиковать единый
`previewContentRect` и transform normalized-camera-space → view-space с учётом
aperture, aspect mode, mirroring и interface orientation. Preview, bbox,
guides, tap targets и snapshot используют только его; HUD-поля не входят в
camera coordinate space.

## 8. Экраны и ориентации

Ориентационная политика v1 согласована с CC-008 §2 и существующим кодом.
Layout resolver использует container size/aspect, safe areas, horizontal /
vertical size class и Dynamic Type. `UIDevice.orientation` не является
источником layout truth; один size class также недостаточен.

- Camera Coach (entry, live, пауза): **portrait + landscape** (compact —
  одноколоночная вёрстка).
- Scene stack (библиотека, генератор, AR и reachable storyboard workspace):
  **landscape-only** (зафиксировано `CommercialSceneNavigationController`).
  `StageSelectionViewController` и старый `EditScriptViewController` в этот
  reachable stack не входят и не restyle-ятся.
- iPad v1 = fullscreen portrait+landscape при действующем
  `UIRequiresFullScreen`. Split View/Stage Manager не входят в acceptance до
  отдельного изменения target capability. На fullscreen iPad «цех»-экраны —
  двухколоночные (плакат слева / контент
  справа); Camera Coach — концепт «монитор режиссёра»: превью вписано в 16:9
  с ink-леттербоксом, HUD живёт на полях и использует §7
  `previewContentRect` transform.

### Полный production-flow inventory v2.6

В таблице ниже каждая строка — projection уже достижимого behavior owner, а не
новая state machine. Orientation означает layout contract, а не `UIDevice`
signal. `common §11` в запретах означает все общие запреты плюс уточнение в
строке. Hero, annotation и accent всегда подчиняются art code §1.4 и budget
§6.1.

### Historical Package 2 remediation baseline — 2026-08-19 (superseded by the 2026-08-21 approval record)

At that historical checkpoint, Package 2 implementation/source gate: **Sol PASS**. App module and test-target
semantic typecheck: **PASS**. Canonical workspace build, runtime tests and
fresh RU+EN screenshot/motion evidence: **PENDING** because `xcodebuild`
aborts before workspace loading when `CoreSimulatorService` aborts. No
post-remediation simulator test is claimed.

The source contract recorded in that historical baseline was: one immutable accepted pause envelope couples
the copied display pixels with the same source-frame ID, orientation, capture
timestamp, stability and adapter seed; live preview remains visible until the
display-ready image exists; terminal outcomes distinguish no evidence, render
failure, pipeline unavailable, timeout and valid empty review, while cancelled
or stale work publishes nothing. Video data remains native and unmirrored, with
requested orientation carried as metadata; the preview layer owns aspect-fill,
orientation, mirroring and all subject/target transforms. Pause markers use
the accepted-image aspect-fill mapper. Camera-manager discovery derives truthful
magnification from each real device's `activeFormat` field of view relative to
the wide camera when available. The measured-equivalent-focal-length enum is
reserved for a future measured producer and is not emitted by production; when
field-of-view metadata is unavailable, the physical lens name is the honest
fallback and no millimeter value is fabricated. Selection haptic fires only
after a physical change, and pause cut-mark geometry is one flat line plus
short type.

The old Package 2 bundle remains historical only: `screenshots/v26-package2/`
contains 19 PNGs and `motion/v26-package2/` contains 3 MP4s. They predate this
remediation, are stale for the current source contract, and cannot close the
then-open Package 2 visual/runtime gate. The later 2026-08-21 approval and
evidence-completion record is authoritative for current Package 2 status.

### Package 5 current source/evidence status — 2026-08-24

Package 5 source/implementation gate: **fresh Sol/High audit `ship`; no
findings**. Parent verification supplied a successful canonical
`build-for-testing` in `/tmp/set-pkg5-race-dd` and the targeted lifecycle result
`/tmp/set-pkg5-lifecycle-final.xcresult` (**6/6 passed**). The dedicated
production-route UI run on iPhone 17e (`1F680A42-CEB3-43E8-9CED-52F874962A62`)
passed **4/4** and exported the reachable chrome/localization/accessibility
captures under `screenshots/v26-package5-simulator/`.

The Package 5 screenshot lane uses the existing
`-SHAFIN_GENERATOR_MARK_AR_READY` deterministic bootstrap fixture. It proves
only reachable landscape chrome, RU+EN copy, stable accessibility IDs, the
truthful unsupported-AR error band, Reduce Motion, Dynamic Type, focused-editor
state and teardown back to Library. The test taps and captures the editor but
does not assert software-keyboard visibility; keyboard evidence remains
pending. It is not proof of ARKit readiness,
plane recovery, placement, generated storyboard playback, actual recording,
microphone capture, Photos save, A/V sync, thermal behavior or hardware
timing. All real-device-only evidence and Package 5 visual owner approval
remain pending; this checkpoint does not declare the full v2.6 flow
production-ready.

### Package 6 correction readback — 2026-08-25

Package 6 is **source + simulator visual implementation accepted by the owner
on 2026-08-25; the bounded Package 6 visual gate is CLOSED**. The reachable
CommercialShell → Library → Generator route now exercises the planner-backed
storyboard result/tray, selection reflow, inspector, medium/large editor,
owner-busy saving state, field-linked validation recovery, flat
identity-bearing delete confirmation and the production Decision Trace sheet
(`sheet.decision-trace`). The fixture seeds real SceneScript/planned-scene
domain items; it creates no thumbnails and makes no AR/REC claim. Unsupported
AR projection is suppressed only inside this explicit DEBUG storyboard fixture
boundary.

The final serial UI bundle is
`/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-boidexwgwrmvdodmifynurprbtdm/Logs/Test/Test-shafinMultitool-2026.08.25_02-11-12-+0300.xcresult`:
**6/6 passed**, with no `Publishing changes from within view updates` runtime
warning. Focused unit coverage is **73/73 passed** in the parent-final bundle
`/tmp/set-pkg6-parent-final-dd.SGyfyt/Logs/Test/Test-shafinMultitool-2026.08.25_02-51-42-+0300.xcresult`.
The corrected screenshots are the 11 files in `screenshots/v26-package6/`,
all normalized to 2532×1170 landscape, including RU+EN production-route
Decision Trace, Reduce Motion/Dynamic Type editor and selection, saving,
validation and delete states. The retained honest simulator motion is
`motion/v26-package6/storyboard-reflow-seam-editor.mp4` (H.264, 2532×1170,
4.5 s); it is trimmed to result → tray expansion/selection seam → editor and
playback ends in the editor before app termination, with no Home Screen frames.
The real-detent correction's existing production-route method passed **1/1**
in `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-dqhmgzxzlssfjogqonbfcndsulfj/Logs/Test/Test-shafinMultitool-2026.08.25_04-23-42-+0300.xcresult`;
`storyboard_editor_sheet` resolves to the actual editor surface, with measured
medium frame `(152.0, 70.0, 540.0, 320.0)` and large frame
`(152.0, -2.0, 540.0, 392.0)`. Separate Beat 1 text frames are
`(184.0, 146.0, 41.0, 27.0)` and `(184.0, 85.0, 75.0, 49.0)`. The medium
and XXL/large PNGs are distinct 2532×1170 captures with SHA-256 values
`dac54da6ddf9d3c7f27fce585b896bed7966231a3fcf72166feb2668520b05ea` and
`37cfebf6b7a68cbaef062750735590ceb0b70e6a4c70b7fea052dc825fde2d54`.
The bounded Reduce Motion clip is
`motion/v26-package6/storyboard-reflow-reduce-motion.mp4` (H.264, 2532×1170,
3.733 s); adjacent 50 ms frames at 1.20–1.80 s show the immediate final
geometry and short opacity change with no travel/scale/rotation/overshoot, and
playback ends in the editor before app termination with no Home Screen frames.
Final readiness is **source + simulator visual implementation accepted**. The
pre-release physical-device verification blocker remains: ARKit readiness,
plane recovery/placement, real camera and microphone capture, Photos save,
generated storyboard playback, actual recording/playback, A/V sync, thermal
behavior and hardware timing. Simulator/source evidence proves none of those
device-only checks, and full v2.6 production-ready status remains open.

### Camera inventory / lens truth

`CameraManager` owns the physical inventory and deduplicates one descriptor per
available device. UI labels use the manager-derived field-of-view magnification
when available; the measured-equivalent-focal-length enum is reserved and has
no production producer. If that metadata is unavailable, the physical lens
name is shown as an honest fallback. The inventory never exposes guessed
duplicate 2×/3× entries for one telephoto module and never fabricates
millimeter values.

Fixture ID convention: стабильный lowercase namespace `<family>.<state>`
(`entry.*`, `shell.*`, `camera.*`, `library.*`, `generator.*`, `ar.*`,
`storyboard.*`, `sheet.*`, `a11y.*`). Existing IDs in the v2.5 gallery are
marked **implemented — v2.5 gallery evidence only**; this proves reusable
components and fixtures, never production-route styling. Every v2.6 production
fixture is marked **required / pending implementation** until a deterministic
fixture, route evidence and owner-approved screenshot exist.

Package status vocabulary is normative: **production implemented; owner
approval pending** means the production route, deterministic behavior and
mechanical evidence exist, but the next package remains gated. It must never be
read as visual approval or as permission to reuse the candidate as a golden.

| screen/state | behavior owner | orientation | hero-content | annotation motif | cinematic accent | prohibited motifs | fixture ID | required evidence |
|---|---|---|---|---|---|---|---|---|
| Entry resolving | `CameraCoachEntryFlowModel` | portrait + landscape | resolving status and honest progress | none; status is semantic text | one registration mark | common §11; fake camera preview; paper boot card | `entry.resolving` — production implemented; owner approval COMPLETE 2026-08-19 | production route state tests passed; RU+EN and orientation evidence accepted/current for Package 1 |
| Entry requesting | `CameraCoachEntryFlowModel` | portrait + landscape | permission request explanation | one underline on action text | narrow film edge | common §11; hidden system rationale; props | `entry.requesting` — production implemented; owner approval COMPLETE 2026-08-19 | system-request handoff, localized copy and Dynamic Type evidence accepted/current for Package 1 |
| Entry ready | `CameraCoachEntryFlowModel` | portrait + landscape | ready handoff to intro/live | one marker bracket around next action | registration mark | common §11; loading spinner as hero; generic card | `entry.ready` — production implemented; owner approval COMPLETE 2026-08-19 | phase transition and one-shot ledger evidence accepted/current for Package 1 |
| Entry intro | `CameraCoachEntryFlowModel` | portrait + landscape | `СНИМАЙ КИНО` / `MAKE CINEMA` and `МОТОР!` / `ACTION!` | one underline tied to CTA | one small film edge or registration mark | paper ticket, literal slate, torn-edge container, generic hero card | `entry.intro` — production implemented; owner approval COMPLETE 2026-08-19 | RU+EN, both orientations, Reduce Motion and leader/marker evidence accepted/current for Package 1 |
| Entry permission | `CameraCoachEntryFlowModel` + system permission owner | portrait + landscape | honest permission rationale and system action | one circle or underline tied to action | one registration mark | masking system prompt, paper sheet, material/blur | `entry.permission` — production implemented; owner approval COMPLETE 2026-08-19 | permission branches, RU+EN and production evidence accepted/current for Package 1 |
| Entry blocked denied | `CameraCoachEntryFlowModel` | portrait + landscape | blocked reason and Settings CTA | one marker strike/circle on blocked state | one registration mark | blame copy, fake retry, paper lock, generic alert card | `entry.blocked-denied` — production implemented; owner approval COMPLETE 2026-08-19 | denied recovery, VoiceOver action and portrait/landscape/AX XXXL evidence accepted/current for Package 1 |
| Entry blocked restricted | `CameraCoachEntryFlowModel` | portrait + landscape | restricted reason and check CTA | one marker strike/circle | one small film edge | common §11; ambiguous “try again”; literal lock prop | `entry.blocked-restricted` — production implemented; owner approval COMPLETE 2026-08-19 | restricted recovery and Dynamic Type reachability evidence accepted/current for Package 1 |
| Entry blocked unavailable | `CameraCoachEntryFlowModel` | portrait + landscape | unavailable reason and check CTA | one marker strike/circle | one registration mark | common §11; fake permission success; alert stack | `entry.blocked-unavailable` — production implemented; owner approval COMPLETE 2026-08-19 | unavailable branch, RU+EN and action semantics evidence accepted/current for Package 1 |
| Entry blocked unknown | `CameraCoachEntryFlowModel` | portrait + landscape | unknown permission state and safe recovery | one marker strike/circle | one small film edge | common §11; invented cause; decorative warning icon | `entry.blocked-unknown` — production implemented; owner approval COMPLETE 2026-08-19 | safe unknown-state recovery and orientation evidence accepted/current for Package 1 |
| CommercialShell camera selection | `CommercialShellViewController` + `CommercialShellModeControl` | portrait + landscape | active Camera Coach route | sliding tally selection | A/B ROLL production label | common §11; bottom nav; icon-only generic control; extra capsule | `shell.camera-selection` — production implemented; owner approval COMPLETE 2026-08-19 | intent/selection, ≥44pt targets and upright portrait/landscape evidence accepted/current for Package 1 |
| CommercialShell scenes selection | `CommercialShellViewController` + `CommercialShellModeControl` | portrait + landscape | active Scenes route | sliding tally selection | A/B ROLL production label | common §11; duplicate navigation owner; bottom tab bar | `shell.scenes-selection` — production implemented; owner approval COMPLETE 2026-08-19 | route truth, orientation forwarding and selection-motion evidence accepted/current for Package 1 |
| CommercialShell locked transition | `CommercialShellViewController` | portrait + landscape | outgoing/incoming route boundary | none; lock is semantic | one cut seam | common §11; animated duplicate routes; travel beyond transition | `shell.transition-locked` — production implemented; owner approval COMPLETE 2026-08-19 | transition lock/coalescing and rotation evidence accepted/current for Package 1 |
| CommercialShell blocked teardown | `CommercialShellViewController` + route owner | portrait + landscape | still-owned route and recovery action | one underline on recovery | one cut seam | forced removal, torn-edge container, silent data loss | `shell.teardown-blocked` — production implemented; owner approval COMPLETE 2026-08-19 | blocked teardown preserves route/async ownership; evidence accepted/current for Package 1 |
| Camera starting | `CameraManager` lifecycle via `CameraViewModel` | portrait + landscape | camera preparation status | none; status is semantic | 3–2–1 leader only when first session entry qualifies | common §11; fake preview; leader on every render | `camera.starting` — production implemented; owner approval COMPLETE 2026-08-21 | lifecycle test, first-entry event ID, RU+EN, both orientations evidence accepted/current for Package 2 |
| Camera interrupted | camera lifecycle owner | portrait + landscape | live frame or interruption reason | none or one recovery underline | quiet `LIVE` | common §11; `REC` without media; error card | `camera.interrupted` — runtime inactive/interrupted projection implemented; no standalone deterministic screenshot because background/inactive is system-driven; owner approval COMPLETE 2026-08-21 | lifecycle projection/code coverage; inactive runtime capture not claimed |
| Camera failed | camera lifecycle owner | portrait + landscape | failure reason and retry/exit action | one underline on recovery | one cut seam | common §11; green/red status semantics; fake confidence | `camera.failed` — production implemented; owner approval COMPLETE 2026-08-21 | failure action test, RU+EN, Reduce Motion evidence accepted/current for Package 2 |
| Camera seeking | `CameraOverlayUXPresentation.liveSeeking` | portrait + landscape | camera frame with finding status | none | dim steady `LIVE` + timecode | common §11; guide before stable evidence; pulse as meaning | `camera.seeking` — production implemented; owner approval COMPLETE 2026-08-21 | state projection, no focus steal, vector audit evidence accepted/current for Package 2 |
| Camera keep | `CameraOverlayUXPresentation.keepAsIs` | portrait + landscape | camera frame and balanced verdict | one subtle underline on verdict | steady `LIVE` + honest timecode | common §11; positive green; AI card; decorative arrow | `camera.keep` — production implemented; owner approval COMPLETE 2026-08-21 | verdict/a11y test, timecode geometry evidence accepted/current for Package 2 |
| Camera corrective | `CameraOverlayUXPresentation.stableTip` | portrait + landscape | full-bleed camera frame and one physical action | one action-linked glass-mark arrow/line | one short orange command | common §11; AI card; redundant arrow; material over preview | `camera.corrective` — production implemented; owner approval COMPLETE 2026-08-21 | event-ID draw, vector audit, RU+EN portrait/landscape evidence accepted/current for Package 2; spatial live-admission gate source-tested 2026-08-25 (18/18 targeted simulator tests) + temporal confirmation source-tested (4/4 targeted simulator tests), not a physical-camera accuracy claim |
| Camera fallback | `CameraOverlayUXPresentation.isFallback` + CC-008 S11 | portrait + landscape | camera frame and honest abstention copy | warmWhite hairline edge | dim steady `LIVE` | `markerYellow`, `РЕЗЕРВ`, pulse, stamp, common §11 | `camera.fallback` — production implemented; owner approval COMPLETE 2026-08-21 | forbidden-copy test, recovery semantics, contrast evidence accepted/current for Package 2 |
| Camera explanation | presentation parent + expansion owner | portrait + landscape | same camera frame and expanded explanation | one underline/bracket on explanation | one `.soft` explanation accent | second state owner, AI card, repeated live tip | `camera.explanation` — production implemented; owner approval COMPLETE 2026-08-21 | grouped a11y announcement, expand/collapse evidence accepted/current for Package 2 |
| Camera lens switching | `CameraViewModel` lens transaction | portrait + landscape | selected real `availableLenses` lens | one selection underline | one selection haptic/tally | hard-coded focal lengths, persistent zoom rail, fake lens | `camera.lens-switching` — production implemented with manager-owned truthful descriptors; owner approval COMPLETE 2026-08-21 | transaction lock/rollback, truthful lens label evidence accepted/current for Package 2 |
| Camera ECO | single effective thermal/power governor | portrait + landscape | camera frame and effective mode | one underline on ECO label | compact `ECO` badge | invented thermal reason, green/red status, extra card | `camera.eco` — deterministic ECO fixture only; runtime ECO omitted because no owned effective thermal/power signal is available; owner approval COMPLETE 2026-08-21 | fixture projection test and screenshot: `screenshots/v26-package2/camera-eco.png` (fixture-only contract accepted) |
| Camera pause loading | pause owner | portrait + landscape | immutable snapshot under analysis | one progress underline | one cut seam | spinner-only state, mutable frame, paper review sheet | `camera.pause-loading` — production implemented; owner approval COMPLETE 2026-08-21 | accepted snapshot ID, one announcement, cancellation evidence accepted/current for Package 2 |
| Camera pause success | pause owner + snapshot/take counter | portrait + landscape | immutable reviewed snapshot and decision band | one circle/underline on reviewed area | `СНЯТО!` cut-mark | literal stamp, paper/tape, display poster, second marker | `camera.pause-success` — production implemented; owner approval COMPLETE 2026-08-21 | take counter, cut-mark event, RU+EN evidence accepted/current for Package 2 |
| Camera pause empty | pause owner | portrait + landscape | immutable snapshot and no-notes message | one underline on next action | one small cut-mark line | silent failure, error red, paper panel | `camera.pause-empty` — production implemented; owner approval COMPLETE 2026-08-21 | empty semantics, cancellation/stale fence evidence accepted/current for Package 2 |
| Camera pause failure | pause owner | portrait + landscape | immutable snapshot and recoverable failure | one underline on retry | one cut seam | silent empty, literal stamp, generic alert card | `camera.pause-failure` — real owned runtime failure projection; distinct no-evidence/render/pipeline-unavailable/timeout reasons; stale/cancelled work publishes nothing; owner approval COMPLETE 2026-08-21 | typed failure/recovery semantics, RU+EN, Reduce Motion evidence accepted/current for Package 2 |
| Camera resume | pause owner | portrait + landscape | return to previous live context | one underline on resume action | one seam settle | new leader, duplicate haptic, route recreation | `camera.resuming` — production implemented; owner approval COMPLETE 2026-08-21 | resume lock, session event ID evidence accepted/current for Package 2 |
| Library empty | `SOViewController` + scene persistence owner | landscape-only | empty library and create action | one underline on create action | one contact-sheet edge rhythm | spreadsheet, equal cards, fake thumbnail, paper stack | `library.empty` — production implemented; owner approval pending | empty fixture projection + RU+EN landscape evidence captured 2026-08-21 (`screenshots/v26-package3/`) |
| Library loaded | `SOViewController` + `SOPresenter` | landscape-only | real scene rows and metadata | one bracket on selected row | contact-sheet rhythm + one cut seam | fake preview, equal-card grid, photo paper | `library.contact-sheet` — production implemented (real summaries + honest metadata, no fake thumbnails); owner approval pending | RU+EN landscape fixture evidence captured 2026-08-21 |
| Library selected | `SOViewController` + selection owner | landscape-only | selected scene row with real preview or metadata | one marker bracket | one cut seam | redundant arrow, fake thumbnail, persistent footer | `library.selected` — production implemented (expanded selected row + cut seam + bracket marker); owner approval pending | selection/reflow evidence + Reduce Motion capture 2026-08-21 |
| Library create-name | `SOViewController` + `SORouter`/persistence owner | landscape-only | scene-name input and create action | one underline on field/action | one registration mark | paper form, ticket CTA, generic rounded card | `library.create-name` — production implemented (inline SET surface, no UIAlertController); owner approval pending | create/duplicate live-flow UI test + RU+EN captures 2026-08-21 |
| Library duplicate-name | scene persistence owner | landscape-only | duplicate-name explanation and correction | one circle around conflicting name | one cut seam | destructive ambiguity, red/green-only status, paper alert | `library.duplicate-name` — production implemented (circle around conflicting name, correction stays active); owner approval pending | duplicate fixture + live duplicate UI test 2026-08-21 |
| Library delete confirmation | `SOViewController` + persistence owner | landscape-only | selected scene identity and destructive choice | one bracket on scene name | one cut-mark | irreversible default, literal stamp, modal card stack | `library.delete-confirmation` — production implemented (bracket on scene identity + cut-mark boundary); owner approval pending | confirm/cancel model tests + fixture capture 2026-08-21 |
| Library persistence failure | persistence owner + `SOViewController` | landscape-only | scene data and recoverable failure | one underline on retry | one cut seam | silent loss, fake success, generic alert pile | `library.persistence-failure` — production implemented (typed failure + honest retry re-run); owner approval pending | injected-failure model tests + EN fixture capture 2026-08-21 |
| Generator input empty | `SceneInputSheet` + `SceneGeneratorViewModel` | landscape-only | empty screenplay input and CTA | one underline on input/CTA | one registration mark | paper sheet, clipboard, ticket CTA | `generator.input-empty` — production implemented (SET editorial sheet, ХЛОП! command, disabled-when-empty); owner approval pending | RU + EN landscape captures in `screenshots/v26-package4-postfix/`; locale-completeness and owner approval pending |
| Generator input editing | `SceneInputSheet` + `SceneGeneratorViewModel` | landscape-only | screenplay text being edited | one bracket on active field | one orange focus edge; Generate edge becomes neutral | paper texture, material blur, generic form card, orange object-chip pile | `generator.input-editing` — production implemented (screenplay mono editor, single-accent ownership); owner approval pending | final post-remediation capture pending |
| Generator input keyboard | system keyboard owner + `SceneInputSheet` | landscape-only | focused screenplay field and visible context | one underline on focus | none beyond field focus | hidden keyboard context, clipped CTA, modal stack | `generator.input-keyboard` — production implemented (inline paste affordance, focus underline); owner approval pending | focused-editor capture only; software-keyboard visibility, focus/order and hardware-keyboard evidence — pending |
| Generator marked + detected objects | `SceneGeneratorViewModel` + `ARSceneContainer` | landscape-only | marked objects over AR frame | one object-linked outline | one orange registration mark | per-frame material, decorative arrow, fake detection confidence | `generator.input-marked-detected` — production chips restyled (hairline capsules, single-orange active state, no green/red); detection fixture screenshot — pending |
| Generator input invalid | `SceneInputSheet` + input validation owner | landscape-only | invalid input and corrective action | one underline on invalid field | one cut seam | red/green-only semantics, generic error card | `generator.input-invalid` — production implemented: dedicated input-local validation appears immediately for nonempty whitespace input (Generate stays disabled) and for parser-empty output; stale parser output cannot overwrite edited text, `generator_input_validation` exposes the existing text to accessibility, and the validation underline is the only orange accent. Source evidence: `SceneBundlePipelineTests/testSceneGeneratorInputValidationIsScopedAndWhitespaceAware` (1/1) and `SETGeneratorProductionUITests/testWhitespaceInputShowsInlineValidation` (1/1, 2s UI settle, screenshot attachment, iPhone 17e simulator, 2026-08-25). The UI capture proves only the input state; the route uses the documented AR-ready simulator bootstrap and does not prove AR. |
| Generator clarification | `SceneGeneratorViewModel` request owner | landscape-only | clarification question and user choice | one underline on question/choice | one cut seam | leader before acceptance, paper form, spinner-only state | `generator.clarification` — **unreachable in the current production parser contract**: `SceneGeneratorViewModel` calls the stateless bundle parse path, which normalizes active scripts to `acceptLocal`; the only `needsClarification` producer requires legacy stateful parsing. No fake surface is rendered. A dedicated parser-contract change, user-choice model and source tests are required before implementation. |
| Generator execution accepted | request owner after eligibility | landscape-only | accepted request and next stage | one bracket on accepted beat | one cut seam | leader before acceptance, duplicate submit, card stack | `generator.accepted` — not restyled separately; acceptance remains owner-side; no visual duplication introduced — pending |
| Generator leader | generator request owner | landscape-only | accepted request entering production | one underline on leader text | 3–2–1 leader, once per accepted start | replay on render/rotation, physical clapperboard, paper prop | `generator.leader` — pending: generator request owner publishes no leader event ID; no fake leader is drawn (honest abstention) |
| Generator progress reading | `SceneGeneratorViewModel` + pipeline stage owner | landscape-only | active beat and “Читаю сценарий…” stage | one marker label on active stage | edge perforation + reflow seam | cropped stable percentage, paper feed, equal cards | `generator.progress-reading` — production progress overlay restyled (ink@0.88, mono status, deterministic perforation strip, `generator_progress_overlay` id); owner publishes locale-independent stage identity and yields for the render turn — source/simulator build accepted 2026-08-25; production capture remains pending |
| Generator progress anchors | pipeline stage owner | landscape-only | active beat and “Ставлю анкеры…” stage | one marker label on active stage | edge perforation + reflow seam | common §11; percentage crop after transition; material | `generator.progress-anchors` — same truthful stage owner/progress surface; no fake percent or duration; source/simulator build accepted 2026-08-25; dedicated stage-transition capture — pending |
| Generator progress frame | pipeline stage owner | landscape-only | active beat and “Считаю кадр…” stage | one marker label on active stage | edge perforation + reflow seam | generic progress card, stable crop, stamp | `generator.progress-frame` — same truthful stage owner/progress surface; source/simulator build accepted 2026-08-25; dedicated completion capture — pending |
| Generator background-cancel | `SceneGeneratorViewModel` generation owner + scene workspace teardown owner | landscape-only | prior committed scene plus current progress/cancel recovery | one underline on cancel/retry | one cut seam | clearing the committed scene before parse, detached generation task, post-release mutation, fake success | `generator.background-cancel` — production data contract implemented 2026-08-26: concurrent callers join one ViewModel-owned generation task; the prior parsed/planned/storyboard state remains canonical until a non-suspending MainActor commit after parse + plan; complete ViewModel teardown is task-owned before its first suspension, rejects new generation during world-map/persistence capture, cancels + joins generation before snapshot, retains a released result and permits a fresh retry only after a blocked attempt is consumed. Exact iPhone 17e `SceneWorkspaceTeardownTests` passed 16/16; final fresh Sol/High verdict `SHIP`. Visual cancel/recovery surface — pending. |
| Generator parse failure | parser owner | landscape-only | input plus parse failure and retry | one underline on retry | one cut seam | technical jargon as hero, generic alert stack | `generator.failure-parse` — generic alert replaced by the SET error band (title + verbatim reason + close underline + cut seam); typed parse/network/model split remains owner-side |
| Generator network failure | network/execution owner | landscape-only | accepted request plus network recovery | one underline on retry | one cut seam | fake progress, blame copy, red-only status | `generator.failure-network` — surfaced through the SET error band; offline fixture screenshot — pending |
| Generator model failure | model execution owner | landscape-only | accepted request plus model recovery | one underline on retry | one cut seam | model internals as UI, fake success, paper stamp | `generator.failure-model` — surfaced through the SET error band; model fixture screenshot — pending |
| Generator retry | execution owner | landscape-only | recoverable failure context and retry action | one underline on retry | one cut seam | duplicate request, leader replay, spinner-only state | `generator.retry` — honest close-only recovery (no fake retry without an owner retry action); `retry` key reserved |
| Generator success | execution owner + `SceneGeneratorViewModel` | landscape-only | generated storyboard and next action | one bracket/underline on selected beat | reflow seam + one cut-mark | physical slate, equal cards, redundant arrow | `generator.success` — storyboard tray/chips restyled (see storyboard rows); persistence covered by `SceneBundlePipelineTests`; RU+EN golden subset — pending |
| AR preparing | `ARSceneContainer` + `SceneGeneratorViewModel` | landscape-only | AR camera/world preparation | none; state is semantic | one registration mark | fake surface, material over per-frame layer, paper | `ar.preparing` — production loading/progress surface restyled (ink overlay, mono status, perforation); simulator capture is chrome/fixture-only; real world preparation — device-only pending; owner approval pending |
| AR ready | `ARSceneContainer` + `SpatialPlannerService` | landscape-only | live AR frame and available workspace | one orthogonal anchor if actionable | one orange registration mark | diagonal stable layout, grain, shadow/blur | `ar.ready` — chrome restyled (ink bar, hairline, SET buttons); readiness remains truthful and recovery requires a post-interruption frame with a real plane; device-only readiness capture — pending; owner approval pending |
| AR surface search | `ARSceneContainer` + AR session owner | landscape-only | camera frame and search guidance | one orthogonal marker line | reticle focus 260ms | reticle as container, material, decorative diagonal | `ar.surface-search` — system coaching overlay retained (behavior owner); representable updates diff session/depth lifecycle inputs and interruption/recovery flags; actual plane search — device-only pending; owner approval pending |
| AR placement | `SpatialPlannerService` + view model | landscape-only | placed ghost/object anchor | one outline tied to placement | one cut seam | floating card, fake depth, paper prop | `ar.placement` — placement UI unchanged (owner geometry); surface chrome restyled; actual plane/anchor placement and device capture — pending; owner approval pending |
| AR marking | `SceneGeneratorViewModel` marking owner | landscape-only | selected real object/anchor | one object-linked outline or arrow | one orange registration mark | redundant guide, confidence chip, material | `ar.marking` — production restyled: orange marking state, `ar.marking.hint` mono hint chip, marker-name SET sheet; production capture 2026-08-21 (simulator marking hint) |
| AR live hints | camera/AR presentation owner | landscape-only | AR frame with one actionable hint | one action-linked glass mark | quiet HUD `LIVE` | AI card, multiple arrows, grain/noise | `ar.live-hints` — hint chips/annotations restyled (hudScrim+hairline, orange reserved for warning/arrow, no green/red); stale frame generations are rejected before presentation; device capture — pending; owner approval pending |
| AR hint pause | hint presentation owner | landscape-only | paused AR frame and hint state | one underline on paused action | steady `STANDBY` | pulse, new state owner, paper panel | `ar.hint-pause` — hint toggle restyled (orange active state); dedicated capture — pending |
| AR hint playback | hint presentation owner | landscape-only | current AR frame and explanation playback | one underline/bracket on explanation | one `.soft` accent | autoplay replay on recomposition, AI card | `ar.hint-playback` — hint views restyled; one-shot playback event remains owner-side — pending |
| AR recording | recorder/session owner | landscape-only | actual recording frame and honest controls | one underline on recording action | `REC` only with real media recording | `REC` during analysis, fake recording, material | `ar.recording` — REC treatment restyled: honest `REC mm:ss` mono timecode pill with orange edge replaces red stopwatch; reachable raw-camera recording is owned by `SceneRecordingController` through `SerializedMediaRecorder` and the Apple adapters; simulator chrome only, actual media/audio/Photos evidence — device-only pending; owner approval pending |
| AR finalized recording review | `SceneGeneratorViewModel` + `RecordingArtifactStore` + workspace presentation owner | landscape-only | newest resolvable project-owned take and play/share actions | one action-linked underline at most | one `setOrange` edge on the compact review band | fake completed take, absolute sandbox URL, material/card/shadow/gradient, enabled action for a missing file | `ar.recording-review` — production implemented 2026-08-26: `.finalized` alone enters an ordered exactly-once FIFO ledger; the store persists only `recordingID` + relative path + duration/audio metadata, promotes Pending media through descriptor-bound exclusive rename, and restores the newest real file. `generator_recording_review_band`, `generator_recording_playback_button` and `generator_recording_share_button` expose native `AVPlayerViewController`/system share with Dynamic Type and ≥44pt actions; missing media remains visible but disabled. iPhone 17e build and 4/4 focused storage/schema tests passed; fresh Sol/High verdict `SHIP`. Actual camera/audio playback, A/V sync and export remain physical-device evidence; visual owner approval remains pending. |
| AR interruption | AR session owner | landscape-only | interrupted frame and recovery | one underline on recovery | one cut seam | silent interruption, fake live state, red-only status | `ar.interruption` — `ARSceneContainer.Coordinator` advances a frame generation on interruption/end; every frame task carries it, stale generations are rejected, playback/recording/hints are stopped and planes/readiness cleared, and recovery stays unready until a post-interruption real plane; simulator cannot prove hardware interruption/recovery; owner approval pending |
| AR error | AR session owner + view model | landscape-only | recoverable AR error and next action | one underline on recovery | one cut seam | generic alert stack, material, paper | `ar.error` — native `ARSession` failure is projected through the localized `generator_error_band` with close underline; explicit RU/EN AR prefix path is asserted in `SceneBundlePipelineTests` and the production route UI test; simulator unsupported-AR capture only, owner approval pending |
| AR teardown | scene workspace teardown owner | landscape-only | route/workspace boundary | none or one recovery underline | one disappearing cut seam | forced removal, lingering camera/AR, torn-edge container | `ar.teardown` — `SceneGeneratorView` awaits `teardownAndWait()` for back, `onDisappear` and background before `dismiss()`; the representable pauses its session and clears the delegate; simulator back-to-Library capture only, physical camera/AR teardown — pending; owner approval pending |
| Storyboard tray collapsed | `SceneGeneratorViewModel` + reachable workspace UI | landscape-only | selected beat strip in compact tray | one underline on selected beat | one contact-sheet edge rhythm | equal-card grid, paper strip, persistent footer | `storyboard.tray-collapsed` — production tray restyled (hudMono count chip, `storyboard_tray_toggle` a11y); deterministic DEBUG domain fixture capture in `screenshots/v26-package6/storyboard-result-ru-tray-collapsed.png` (iPhone 17e simulator only) |
| Storyboard tray expanded | reachable workspace UI + view model | landscape-only | readable beat strip and next action | one bracket on selected beat | one cut seam | desktop table, multiple accents, card stack | `storyboard.tray-expanded` — same restyled tray; deterministic fixture capture in `screenshots/v26-package6/storyboard-result-ru-tray-expanded.png` (iPhone 17e simulator only) |
| Storyboard selection reflow | storyboard selection owner | landscape-only | selected frame at 45–60% axis with peeking neighbors | underline/bracket only; no redundant arrow | montage spring → seam; Reduce Motion crossfade 120 ms | stable crop, equal cards, two seams | `storyboard.selection-reflow` — `SETMontageReflow` selects before editor presentation; RU normal and EN Reduce Motion captures in `screenshots/v26-package6/storyboard-selection-reflow-ru-landscape.png` and `screenshots/v26-package6/storyboard-selection-reflow-en-reduce-motion.png`, plus honest simulator clips in `motion/v26-package6/storyboard-reflow-seam-editor.mp4` and `motion/v26-package6/storyboard-reflow-reduce-motion.mp4` |
| Storyboard result | `SceneGeneratorViewModel` storyboard projection | landscape-only | three real storyboard frames | underline/bracket `ОПОРНЫЙ КАДР` | one selection seam | redundant arrow, physical slate, fake thumbnail | `storyboard.result` — planner-backed deterministic fixture supplies real scene/beat domain items without thumbnails or AR; RU result captures in `screenshots/v26-package6/`, hardware/generated-scene proof remains pending |
| Storyboard inspector | storyboard inspector projection owner | landscape-only | selected beat metadata and evidence | one bracket on inspected beat | one cut seam | inspector card pile, paper form, shadow/blur | `storyboard.inspector` — inspector card remains a flat editorial surface and is reached/asserted by the selection fixture; no separate hardware/AR claim |
| Storyboard editor medium | `SceneGeneratorViewModel` manual edit owner | landscape-only | beat draft and supported actions | one underline on active field | one registration mark | generic form card, unsupported action, material | `storyboard.editor-medium` — flat ink/cut-seam header replaces system toolbar; the `storyboard_editor_sheet` AX element is the 320pt medium surface and the EN capture is `screenshots/v26-package6/storyboard-editor-medium-en-landscape.png`; `storyboard_editor_save/delete` IDs preserved |
| Storyboard editor large | `SceneGeneratorViewModel` manual edit owner | landscape-only | beat draft with full action context | one bracket on active group | one cut seam | desktop-density table, paper clipboard, extra motif | `storyboard.editor-large` — the real surface grows to 392pt with Reduce Motion + XXL Dynamic Type; capture `screenshots/v26-package6/storyboard-editor-large-en-reduce-motion-dynamic-type.png` |
| Storyboard saving | `SceneGeneratorViewModel` persistence owner | landscape-only | edited beat and save progress | one underline on save action | one cut seam | fake success, spinner-only, duplicate save | `storyboard.saving` — save affordance exposes localized saving state, disables duplicate submit, and keeps async idempotence owner-side; owner-busy UI and Save AX contract captured in `screenshots/v26-package6/storyboard-saving-en-landscape.png` |
| Storyboard validation failure | storyboard validation owner | landscape-only | invalid draft and field-level recovery | one underline on invalid field | one cut seam | red-only error, generic alert, data loss | `storyboard.validation-failure` — canonical view-model validation message and typed invalid-field recovery are rendered inside the active editor; fixture capture `screenshots/v26-package6/storyboard-validation-failure-ru-landscape.png` |
| Storyboard delete confirmation | storyboard persistence owner | landscape-only | selected beat identity and destructive choice | one bracket on beat name | one cut-mark | irreversible default, literal stamp, paper dialog | `storyboard.delete-confirmation` — flat SET-owned overlay names the beat identity, uses no material/blur/red CTA, and only confirm calls the existing async delete owner; capture `screenshots/v26-package6/storyboard-delete-confirmation-ru-landscape.png` |
| Sheet scene-name | `SORouter`/scene persistence owner | landscape-only | scene-name field and create action | one underline on field | one registration mark | paper form, ticket CTA, generic rounded card | `sheet.scene-name` — production implemented by the library create panel (Package 3); RU/EN captures 2026-08-21 |
| Sheet marker-name | marking owner + `SceneGeneratorViewModel` | landscape-only | marker-name field tied to selected object | one underline on field/object | one orange registration mark | detached annotation, paper label, shadow/blur | `sheet.marker-name` — production implemented (SET panel, registration mark, focus underline, `marker_name_*` ids); production capture 2026-08-21 via workspace |
| Sheet screenplay input | `SceneInputSheet` + `SceneGeneratorViewModel` | landscape-only | screenplay text and next action | one bracket on active input | one cut seam | paper sheet, material/blur, clipped CTA | `sheet.screenplay-input` — production implemented by the restyled `SceneInputSheet`; production capture 2026-08-21 |
| Sheet Decision Trace | `DecisionTraceView` + `SceneGeneratorViewModel` | landscape-only | evidence, chosen action and trace IDs | one underline on selected evidence row | one `.soft` explanation accent | debug overlay, raw pipeline dump, card wall | `sheet.decision-trace` — production-route fixture implemented (flat editorial trace, neutral confidence text, `decision_trace_sheet` preserved); deterministic real DecisionTraceView captures `screenshots/v26-package6/decision-trace-ru.png` and `screenshots/v26-package6/decision-trace-en-reduce-motion.png` |
| Accessibility variant RU + EN | each screen behavior owner + String Catalog owner | host orientation | same hero and semantic copy in selected locale | same single motif, no locale-specific extra | same single accent | mixed locale, literal View strings, clipped copy | `a11y.ru-en` — required / pending implementation | full catalog, mixed-string screenshots, locale launch evidence — required / pending |
| Accessibility variant Dynamic Type | each screen behavior owner + system text environment | host orientation | same hero with readable scaled text | same motif; geometry adapts | same accent; no crop | fixed body text, clipped CTA, overflow card | `a11y.dynamic-type` — required / pending implementation | XXL/large type layout and hit-target tests — required / pending |
| Accessibility variant Reduce Motion | each screen behavior owner + accessibility environment | host orientation | same hero and instantaneous state | final marker appears immediately | state changes instantaneously then fade 120ms | travel/scale/rotation, replayed one-shot | `a11y.reduce-motion` — required / pending implementation | exact timing test, event-ID idempotence, screenshots — required / pending |
| Accessibility variant Reduce Transparency | each screen owner + accessibility environment | host orientation | same hero with opaque `surface.solid` surfaces | same vector motif | same accent without scrim dependence | Material/blur, contrast loss, resized surface | `a11y.reduce-transparency` — required / pending implementation | solid-surface contrast and geometry screenshots — required / pending |
| Accessibility variant keyboard | form/sheet owner + system keyboard | host orientation, landscape reading order | focused field plus reachable action | one focus underline | no extra accent | clipped focus, hidden CTA, keyboard-only color meaning | `a11y.keyboard` — required / pending implementation | keyboard focus/order, hardware keyboard and RU+EN evidence — required / pending |
| Accessibility variant logical landscape reading order | shell/route owner + each landscape screen owner | landscape-only | hero → context → action in logical order | one motif follows semantic target | one accent follows selection | visual-only order, desktop footer, hidden offscreen action | `a11y.landscape-reading-order` — required / pending implementation | UIAccessibility traversal, rotation and screenshot evidence — required / pending |

**Package 5 source-mechanics readback (not visual approval).** The AR
representable now owns the state handoff boundary: `updateUIView` receives
locale, generation, depth, readiness and interruption/recovery inputs; the
coordinator diffs session/depth lifecycle work, refreshes only cached viewport
and display-transform geometry on rotation, and does not rerun the session for
representable re-render alone. `ARSceneContainer.Coordinator` increments its
monotonic frame generation at interruption boundaries and passes that token to
both lightweight presentation and throttled frame-processing tasks;
`SceneGeneratorViewModel` rejects stale tokens, stops active playback/recording
and hint analysis, clears planes/readiness, and only leaves recovery after a
new frame exposes a real plane. `SceneRecordingController` owns reachable
raw-camera recorder resources and finishing through `SerializedMediaRecorder`
and the Apple adapters; `SceneGeneratorViewModel` hides `REC` while finalizing
and projects recorder failures into the localized error surface. `SceneGeneratorView` performs async teardown before
background dismissal and route dismissal, while `dismantleUIView` pauses the
session and removes its delegate. These are source/test mechanics only;
simulator evidence does not upgrade them into ARKit, camera, microphone,
Photos, A/V-sync, thermal or hardware-timing proof.

### Cleanup reachability audit — 2026-08-25

This source-only audit is recorded in the sole visual/execution authority; CC-008
remains the behavior authority. `SceneDelegate` invokes
`CommercialShellComposition().makeShell()` for the commercial root. The
composition is defined in
`shafinMultitool/CommercialShell/CommercialShellRouteComposition.swift`: its
camera branch builds `CommercialCameraCoachRoute`, its scenes branch wraps
`SOModuleBuilder.build()` in `CommercialSceneLibraryRoute`, and
`SOModuleBuilder` wires `SORouter`. `SORouter.loadSceneWithName` pushes the
`SceneGeneratorView` workspace. The current shell therefore reaches Camera
Coach and Library → Generator/AR/Storyboard through those owners.

The static production-source reachability record is:

| Candidate | Current reachability | Dependencies / callers found | Status |
|---|---|---|---|
| `StageSelectionViewController` (`SceneModules/StageSelectionViewController.swift`) | No caller from `SceneDelegate` or `CommercialShell`; not on the current shell path. | Its private `openSceneLibrary()` calls `SOModuleBuilder.build()` and pushes the result. | **NOT RESTYLED; removal candidate only.** |
| `CameraScreenViewController` (`SceneModules/CameraScreenModule/View/CameraScreenViewController.swift`) | No active production caller; only the old `CameraScreenBuilder.build(sceneName:newScene:)` constructs it. | `CameraScreenBuilder` assembles `CameraScreenInteractor`, `CameraScreenRouter`, `CameraScreenPresenter` and the view; `CameraScreenRouter` owns the old edit-script transition. Test-only references do not establish product reachability. | **NOT RESTYLED; removal candidate only.** |
| `EditScriptViewController` (`SceneModules/EditScriptModule/View/EditScriptViewController.swift`) | Reachable only through the old `CameraScreenRouter.openEditScriptScreen(...)` path; no active shell dependency. | `CameraScreenRouter` calls `EditScriptBuilder.build(with:newScriptHandler:)`; `EditScriptBuilder` wires `EditScriptInteractor`, `EditScriptRouter`, `EditScriptPresenter` and the view. | **NOT RESTYLED; removal candidate only.** |

No row authorizes deletion. A separate owner-approved review is required before
any removal, covering persistence, deep links, fixtures and routes for each
candidate. History stub, Debug, Performance, Benchmark and
`docs/thesis/litreview*` remain excluded and untouched.

## 9. Motion и haptics

Словарь пресетов (числа — из токенов): spring по умолчанию `response 0.4,
dampingFraction 0.85`; chip-enter снизу overshoot 8pt; hint-change
crossfade+slide 12pt/220ms; mask-reveal 320ms stagger 40ms; `torn-edge wipe`
320ms — только исчезающий transition **между крупными стадиями**, никогда не
container; `reticle-focus` 260ms. Film-burn буквально не воспроизводится: wipe
остаётся абстрактной шторкой и исчезает после перехода.

Нормативная motion grammar v2.6:

- marker annotation рисуется за **320ms** по domain event ID: линия/хвост
  первыми, наконечник/outline completion последними;
- montage: `selection intent → spring 220–320ms → seam → marker 120–180ms`;
- `3–2–1` leader разрешён только при первом camera entry за session и при
  принятом генераторе start; rotation, re-render и recomposition его не
  повторяют;
- `cut-mark` остаётся короткой типографической отметкой с одной линией или
  окружностью, 220ms + settle 160ms, и не является literal stamp;
- AR reticle-focus имеет ровно **260ms**;
- `Reduce Motion`: state changes и геометрия происходят мгновенно, затем идёт
  только opacity fade **120ms**; нет travel, scale, rotation или spring.

Montage reflow: selection intent → geometry spring 220–320ms → seam settles →
marker annotation reveal 120–180ms. Actionable `glass mark` дополнительно
прорисовывает свой вектор за 320ms (line first, arrowhead/outline completion
last); запуск принадлежит domain event ID, а не случайному re-render View. Во время
geometry phase повторный выбор
coalesce-ится существующим interaction owner; DesignSystem не создаёт новый
state owner. Stable semantic copy никогда не остаётся cropped.

Haptics: `.rigid` — абстрактный хлопок слейта и cut-mark; `.selection` —
линза, секция A/B ROLL;
`.soft` — раскрытие объяснения.

`accessibilityReduceMotion`: ВСЁ → мгновенные дискретные состояния + fade
120ms без поворотов/scale/overshoot. Сохраняются те же стадии через
мгновенную смену композиции + opacity transition без travel/scale/rotation.
Бесконечный pulse становится статическим индикатором; meaningful completion
подтверждается текстом и, если разрешено, одиночным haptic. State timing и
actions не меняются.

`accessibilityReduceTransparency`: translucent surfaces → `surface.solid`.

One-shot animation/haptic выполняются по domain event ID ровно один раз, а не по
появлению View; rotation, re-render, recomposition и route recreation не могут
их replay-ить. `SETMotionEventLedger` — persistent/session-operation-owned
one-shot ledger: он переживает SwiftUI recomposition, rotation и route
recreation; transient View никогда не владеет consumption и не решает, был ли
event уже использован. Haptic helper имеет protocol seam для spy-тестов.

## 10. Системный хром

- Клавиатура в редакторе сценария — тёмная (`.dark` поле ввода).
- Алерты/шиты — тёмные: `.preferredColorScheme(.dark)` на презентерах.
- Status bar в v1 остаётся скрытым согласно target configuration
  `UIStatusBarHidden=YES`; его style не входит в acceptance. Включение —
  отдельное behavior/layout изменение с safe-area проверкой всех routes.
- Share sheet — системный, без стилизации.

## 11. Запреты

- Шаблонные rounded-card интерфейсы; одинаковая геометрия карточек на каждом
  экране.
- Тени, blur и материальное «стекло» на non-live экранах «цеха». Название
  `glass mark` описывает жест рисования, а не разрешает glassmorphism.
- Emoji как UI-иконки; декоративные SF Symbols без функции.
- «Приятный серый текст» как единственный способ создать иерархию.
- Белое на оранжевом; шрифты без кириллицы; хардкод фокусных расстояний.
- Fake camera preview в entry flow.
- Буквальная советская/историческая символика, aging/грязь, propaganda-like
  композиция и прямое копирование узнаваемого UI референсов.
- Изменение роутов CommercialShell, async teardown, accessibility-ID.
- Тени/blur/Material над live-preview вообще, включая неподвижный chrome.
- Стилизация DebugOverlay/PerformanceOverlay или Benchmark UI/fixtures.
- Синие/фиолетовые градиенты, неон, зелёно-красная семантика статусов.
- Runtime-random grain/torn masks, decorative layers в hit testing или
  accessibility tree.
- Экран как физический реквизит: стопка бумаги, скрепка, скотч, карандаш,
  билет-кнопка, объёмная плёнка, paper-feed или фотореалистичная хлопушка.
- Светлая бумага как основная поверхность либо контейнер первичного действия.
- Более одного annotation motif + одного малого cinematic accent в стабильном
  состоянии; суммарная площадь буквального реквизита >8% viewport.
- Equal-card grid там, где есть активный выбор; montage reflow обязан давать
  выбранному фрагменту визуальный приоритет.
- Стрелка на horizon/axis, стрелка к уже достаточной selection-рамке и любая
  декоративная стрелка без actionable/pointing semantics.
- Mobile landscape с body <17pt, tappable action <44pt, более чем пятью
  конкурирующими content groups или desktop-like persistent metadata footer.

## 12. Тесты, guard, evidence

- Обновить (не удалить): `CameraOverlayUXPresentationTests` — ассерты под
  таблицу состояний §7; `CameraCoachEntryFlowUITests` — идентификаторы не
  трогать, добавить наличие плакат-элементов; `CommercialShell*Tests` —
  route/teardown логика без изменений, icon-only visual assertions superseded
  O-1 и заменяются capsule-contract assertions.
- `CameraCoachEntryVisualPolicy.sourceMarkers` =
  `["set-os-two-registers", "poster-typography-bilingual",
  "single-orange-accent-wcag", "mono-hud", "glass-mark-annotation",
  "leader-countdown", "state-table-camera-coach",
  "motion-respects-reduce-motion"]`.
- Guard работает только в production UI scope с явным allowlist legacy/debug.
  Unit tests проверяют exact RGBA/semantic mapping токенов, asset names,
  contrast каждой semantic pair и отсутствие запрещённых live-HUD API. Source
  lint остаётся быстрым сигналом, но не доказательством. Display glyph coverage
  доказывается CoreText, не regex по строкам.
- Phase 0 добавляет DEBUG-only deterministic gallery/fixture root, недоступный
  production routing: state payloads, static video fixtures, locales,
  portrait/landscape, Reduce Motion/Transparency и Dynamic Type. Production
  components не копируются специально для preview.
- Evidence boundary v2.6: реализованные v2.5 gallery fixtures и screenshot
  bundles (включая O-7/O-8 mechanical evidence) остаются **gallery-only** и не
  заявляют production styling, route integration или owner approval. Для каждой
  строки §8 требуется отдельный deterministic v2.6 production fixture, route
  evidence, state/layout/accessibility checks и owner-approved screenshot;
  inventory помечает всё отсутствующее как **required / pending implementation**.
- Evidence по культуре репо: `docs/aegis/work/<date>-set-os-redesign/` делится
  на четыре слоя: automated state/layout/glyph/contrast/geometry tests;
  owner-approved golden subset главного пути RU+EN в двух ориентациях;
  pairwise accessibility/device matrix; отдельный physical-device smoke для
  preview/rotation/thermal/teardown. Полная декартова матрица допустима как
  генерация, но не самостоятельный acceptance criterion.
- Golden manifest Phase 0: foundations; wordmark horizontal/stacked; все
  reusable components; entry intro/permission/blocked×4; Camera states §7;
  pause loading/success/empty/failure; generator preflight/progress/result;
  library; RU+EN; минимум один Reduce Motion, Reduce Transparency и XXL
  вариант каждого screen family. Host capture обязан доказать правильную
  orientation; skip не считается evidence.
- Обновить `docs/implementation/ux/camera-coach-state-spec.md`: пометка об
  отзыве neutral-политики и ссылка на эту политику; сверка таблицы §7 с
  поведенческим контрактом CC-008.

## 13. Критерии приёмки

Пункты 1–8 ниже сохраняют исторический v2.1–v2.5 acceptance record. Для
активного полного scope v2.6 дополнительно обязательны пункты 9–10.

1. Прожарка шага 0 закрыта: critique-файл существует, правки проведены через
   гейт владельца; визуальные коррекции O-5/O-6 опубликованы как v2.3.
2. Галерея фазы 0 одобрена владельцем до интеграции.
3. Один образ на всех экранах; «цех»/«площадка» различимы, но живут в одной
   системе токенов.
4. ≥4 момента, которых нет в шаблонных приложениях: marker guide поверх кадра,
   плоский лидер, абстрактный хлопок слейта, film-edge progress, timecode,
   marker selection в библиотеке, ECO-бейдж. Ни один момент не превращает
   экран в физический реквизит.
5. Кириллица рендерится фирменными шрифтами в локализуемых ролях без glyph
   fallback — доказано CoreText charset-тестом и mixed-string screenshots.
6. Контраст-правила §3 выполняются token-pair tests; source lint один этого не
   доказывает.
7. Тесты/доки/evidence обновлены; behavior-тесты shell/entry зелёные;
   accessibility-ID не переименованы; RU+EN локали полны.
8. Скриншоты главных путей (entry → live-подсказка → пауза-разбор →
   генерация → библиотека) выглядят как промо, а не wireframe — финальная
   прикидка владельцем.
9. Каждая reachable production row §8 имеет behavior owner, orientation, hero,
   максимум один annotation и один cinematic accent, prohibition set,
   deterministic fixture status и требуемое evidence; pending не считается
   реализованным.
10. Весь v2.6 production-flow покрыт RU+EN, Dynamic Type, Reduce Motion,
    Reduce Transparency, keyboard и logical landscape reading order; v2.5
    gallery evidence не подменяет production evidence.

## Changelog

- **v2.6 generation/teardown data-safety checkpoint** (2026-08-26) — Scene
  regeneration no longer clears the last committed planned scene, screenplay
  or storyboard before asynchronous parsing. One ViewModel-owned generation
  task is joined by concurrent callers; cancellation and epoch checks fence
  every suspension, while model + AR replacement is a non-suspending MainActor
  commit after parse and planning succeed. The complete ViewModel teardown is
  itself task-owned before the first suspension, rejects generation throughout
  world-map/persistence capture, cancels and joins in-flight generation before
  snapshot, retains released completion and clears a blocked attempt by task
  identity for retry. Exact iPhone 17e teardown evidence passed 16/16. The
  first fresh Sol/High audit found a second-generation admission race during
  snapshot capture; the corrected re-audit returned `SHIP` with no findings.
- **v2.6 project recording-retention checkpoint** (2026-08-26) — Deleting a
  decoded and filename-fenced unified scene now removes only
  `Application Support/Recordings/Projects/<project UUID>` after the legacy
  sidecar and authoritative project JSON have been deleted. The recording
  store opens the configured Application Support root and every descendant
  with `O_NOFOLLOW`/`openat`, accepts only canonical UUID `.mov` regular files,
  and removes entries through the opened project descriptor; missing projects
  are idempotent, while symlink, nested and non-regular entries fail closed.
  Media-cleanup failure remains diagnostic because the existing Library Bool
  represents metadata deletion and must not enter an unrecoverable retry loop.
  An exact iPhone 17e run passed 6/6 focused tests; the correction audit closed
  root-symlink, deletion-order and swallowed-initialization findings, and the
  final fresh Sol/High verdict is `SHIP`. Arbitrary Pending cleanup remains
  prohibited until each Pending take has persisted ownership/lease metadata;
  filename age alone is not an ownership proof.
- **v2.6 finalized REC ownership checkpoint** (2026-08-26) — Reachable user
  stop now promotes only recorder-attested `.finalized` media into
  project-owned Application Support storage and persists no absolute sandbox
  URL. Promotion is descriptor-bound, symlink-fenced, exclusive/no-overwrite
  and inode-validated; failed promotions remain unpublished and are retried in
  strict FIFO order before persistence and teardown. The workspace restores
  the newest resolvable take and exposes a compact SET review band with native
  playback and system share, RU+EN copy, Dynamic Type, stable accessibility IDs
  and ≥44pt actions. The iPhone 17e build passed; focused storage/schema
  evidence passed 4/4; two correction audits closed TOCTOU, player-lifecycle
  and ordered-retry findings, and the final fresh Sol/High verdict is `SHIP`.
  Physical camera/audio recording, A/V sync, export targets and field timing
  remain device-only evidence and are not claimed by the simulator result.
- **v2.6 Package 6 simulator/domain-fixture checkpoint** (2026-08-25) — The
  owner accepted the bounded source + simulator visual implementation on
  2026-08-25; the Package 6 visual gate is **CLOSED for this evidence lane**.
  reachable Storyboard tray, result, selection/reflow, inspector, editor
  medium/large, saving, canonical validation failure and identity-bearing delete
  states are covered by the real CommercialShell → Library → Generator route
  using planner-backed deterministic SceneScript data. The fixture creates no
  thumbnails and does not claim AR readiness; its unsupported-AR error band is
  suppressed only at the explicit DEBUG storyboard-fixture boundary. The editor
  uses a flat SET header and delete overlay, all three action Pickers use SET
  text tint, and the scene title is trailing-anchored to avoid the centered
  CommercialShell A/B ROLL control. Decision Trace copy is fully RU+EN through
  the String Catalog, including the real `DecisionTraceView` fixture. The
  deferred DEBUG AR-ready mutation removes the reproducible SwiftUI publishing
  warning from the affected UI methods.

  The corrected focused UI bundle
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-boidexwgwrmvdodmifynurprbtdm/Logs/Test/Test-shafinMultitool-2026.08.25_02-11-12-+0300.xcresult`
  passed all six Package 6 methods with
  `-collect-test-diagnostics never`; `xcresulttool get test-results tests`
  reports 6/6 Passed and no `Publishing changes from within view updates`.
  Focused unit coverage passed 73/73 in the parent-final bundle
  `/tmp/set-pkg6-parent-final-dd.SGyfyt/Logs/Test/Test-shafinMultitool-2026.08.25_02-51-42-+0300.xcresult`.
  A targeted RU validation/delete recapture then passed 1/1 in
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-ailvhuifnyfkntckphoasuqmkoud/Logs/Test/Test-shafinMultitool-2026.08.25_02-39-36-+0300.xcresult`
  with `-collect-test-diagnostics never`; the existing validation AX element is
  tapped only to settle the vertical editor viewport before attachment. The
  replacement PNG remains the canonical validation evidence path below.
  Post-settle verification is synchronized to the parent-final 73/73 focused
  units in
  `/tmp/set-pkg6-parent-final-dd.SGyfyt/Logs/Test/Test-shafinMultitool-2026.08.25_02-51-42-+0300.xcresult`
  and 6/6 affected UI methods in
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-fyltofdvsddofnaqduzvhgxaoezd/Logs/Test/Test-shafinMultitool-2026.08.25_02-42-10-+0300.xcresult`;
  both used `-collect-test-diagnostics never`, with no
  `Publishing changes from within view updates` warning in the UI log.
  The real-detent correction then rebuilt `/tmp/set-pkg6-real-detent-dd` and passed
  `testStoryboardFixtureENReduceMotionDynamicTypeAndEditorDetents` 1/1 in
  `/Users/unterlantas/Library/Developer/Xcode/DerivedData/shafinMultitool-dqhmgzxzlssfjogqonbfcndsulfj/Logs/Test/Test-shafinMultitool-2026.08.25_04-23-42-+0300.xcresult`;
  its medium and XXL/large editor attachments are distinct normalized
  2532×1170 PNGs.
  Eleven normalized PNGs are in `screenshots/v26-package6/`; honest simulator
  montage reflow → seam → editor motion is
  `motion/v26-package6/storyboard-reflow-seam-editor.mp4` (H.264, 4.5 s,
  2532×1170); the in-app-only playback ends in the editor before app
  termination, with no Home Screen frames. Reduce Motion is also captured in
  `motion/v26-package6/storyboard-reflow-reduce-motion.mp4` (H.264, 3.733 s,
  2532×1170); its in-app-only playback ends in the editor before app
  termination, with no Home Screen frames. These are iPhone 17e
  simulator/domain-fixture evidence only. The pre-release physical-device
  verification blocker remains: ARKit readiness, plane recovery/placement,
  real camera and microphone capture, Photos save, generated storyboard
  playback, actual recording/playback, A/V sync, thermal behavior and hardware
  timing. Full v2.6 production-ready status remains open; this evidence does
  not claim those device-only checks.
- **v2.6 Package 5 simulator/source checkpoint** (2026-08-24) — Fresh
  Sol/High source audit returned `ship` with no findings. Parent verification
  retained the iPhone 17e canonical build-for-testing and targeted lifecycle
  result (6/6); the unchanged production UI test class then passed 4/4 on the
  dedicated iPhone 17e and exported 10 new screenshots into
  `screenshots/v26-package5-simulator/` (RU+EN, focused-editor state, Reduce
  Motion, Dynamic Type, unsupported-AR error and back-to-Library chrome). The
  focused-editor capture does not assert software-keyboard visibility; keyboard
  evidence remains pending. The
  `-SHAFIN_GENERATOR_MARK_AR_READY` argument is a deterministic simulator
  bootstrap fixture, so these captures are labeled chrome/fixture evidence and
  do not claim ARKit readiness, plane recovery, generated playback, recording,
  microphone, Photos, A/V sync, thermal or hardware timing. Interruption
  generation fencing/recovery, truthful recorder lifecycle/native failure
  projection, representable update diffing and async background
  teardown-before-dismiss are recorded in §8. Package 5 visual owner approval
  and all real-device evidence remain pending; this is not full v2.6
  production-ready completion.
- **v2.6 Package 4 remediation checkpoint** (2026-08-24) — Generator input,
  marker-name and honest error-band surfaces remain route-owned and use the SET
  editorial system. The final iPhone 17e build passed; retained focused
  contracts are 4/4 and the explicit EN production route is 1/1 with a complete
  result bundle. Locale, ≥44pt targets, single-accent motif ownership, reduced-
  motion tray crossfade and destructive beat confirmation are implemented; a
  fresh Sol/High review returned `ship` with no findings. The authoritative
  current screenshot is
  `screenshots/v26-package4-postfix/v26-package4-generator-error-band-en-landscape.png`;
  the other Package 4 postfix captures predate the final remediation and are
  historical until a fresh matrix replaces them. Unsupported ARKit is shown as
  an honest error state; generated-scene, leader, device AR,
  playback/recording and storyboard golden evidence remain pending. No iPhone
  17 Pro destination was used. This is a partial checkpoint, not owner visual
  acceptance.
- **v2.6 Package 2 owner approval + Package 3 unlock** (2026-08-21) — владелец
  закрыл Package 2 visual gate по свежему postfix-evidence
  (`screenshots/v26-package2-postfix/`, `motion/v26-package2-postfix/`);
  все camera-строки §8 помечены owner approval COMPLETE. Владелец выдал
  сквозное направление «доведи работу до самого конца»: Пакеты 3–6
  выполняются последовательно без промежуточных owner-STOP при сохранении
  полного механического gate каждого пакета (runtime tests, RU+EN evidence,
  required orientations, Reduce Motion/Dynamic Type, motion video для новых
  движений); финальный визуальный вердикт владельца обязателен после Package 6.
  Допускается полировка в духе владельца внутри рамок политики.
- **v2.6 Package 2 remediation update** (2026-08-19) — source/implementation
  contract получил **Sol PASS**; app module and test-target semantic typecheck
  получили **PASS**. Canonical workspace build, runtime tests and fresh
  RU+EN screenshot/motion evidence остаются **PENDING**: `xcodebuild` aborts
  before workspace loading because `CoreSimulatorService` aborts. The accepted
  pause envelope, display-ready handoff, typed failure/empty/cancel semantics,
  native unmirrored data buffer plus orientation metadata, preview-layer
  transforms, accepted-frame mapper, truthful lens descriptors, success-only
  haptic and single-line cut-mark are the current contracts. The old 19 PNGs
  and 3 MP4s are historical/stale after remediation and cannot close Package 2;
  Package 3 remains gated.
- **v2.6** (2026-08-18) — опубликован полный production-flow authority:
  canonical active plan «SET OS v2.6 — полный production-редизайн приложения»
  заменяет Phase 0-only и все более узкие historical scopes. Зафиксирован
  approved art code Soviet print/A24/film/micro-skeuomorphism, palette
  `ink`/`warmWhite`/one `setOrange`, полный reachable per-screen inventory и
  deterministic fixture/evidence boundary. Motion grammar уточнена для
  event-ID marker 320ms, montage spring → seam → marker, one-shot leader,
  torn-edge wipe, cut-mark, AR reticle 260ms и Reduce Motion 120ms fade.
  Package 1 owner-feedback correction уточнила Entry command/recovery hierarchy:
  shared Oswald command labels use bounded 22→34pt Dynamic Type scaling,
  JetBrains Mono helpers remain subordinate, and accessibility sizes reflow the
  command/helper pair vertically without changing body-copy accessibility.
  Package 1 Entry/Shell production rows теперь помечены **production
  implemented; owner approved 2026-08-19**: после typography-correction
  механические, accessibility- и visual-gates закрыты. Package 2 Camera Coach
  открыт отдельным production slice; Package 3 не начинается до нового
  визуального вердикта владельца по Camera Coach evidence.
- **v2.5** (2026-08-18) — owner visual correction O-8: glass-mark получает
  one-shot vector draw по event ID: стрелка рисуется от хвоста к наконечнику,
  underline/outline — по контуру. Добавлен typed 320ms token; live video/HUD
  не получают декоративного движения, Reduce Motion сохраняет сразу полный
  доступный маркер. Phase 0 остаётся на owner approval.
- **v2.4** (2026-08-18) — owner visual correction O-7: первая executable
  v2.3 gallery отклонена как «постер с фотографией внутри телефона». Добавлен
  composition rule: portrait live-camera full-bleed, HUD/command поверх кадра;
  pause — compact review band, а не display-плакат; marker всегда заканчивается
  у физической цели; landscape reflow обязан нести рабочий контекст. Phase 0
  снова требует owner approval после новых simulator captures.
- **v2.3** (2026-08-18) — owner approval O-6: приняты варианты A/C/D нового
  mobile Scene flow; из B принят только motion-язык. Добавлен второй signature
  primitive `montage reflow`: активный фрагмент расширяется, соседи сжимаются,
  одна orange cut seam фиксирует монтажную границу. Уточнена семантика marker
  shapes: arrow = движение/указание, line = horizon/axis без arrowhead,
  outline = объект/выбор, underline/bracket = текст/группа. Зафиксированы
  mobile thresholds body ≥17pt, action ≥44pt, 3–5 content groups; cropped
  percentage допустим только в transition. Gallery v2.2 concepts одобрены как
  направление, но Phase 0 остаётся открытой до проверки реального SwiftUI.
- **v2.2** (2026-08-17) — owner visual correction O-5 после отклонения первой
  галереи: зафиксирован эталон «маркер на стекле» и цветовой вес
  ink/warmWhite/setOrange; скевоморфизм понижен до микроакцентов ≤8% viewport.
  Бумажные рабочие столы, билеты-CTA, скотч, скрепки, literal stamp/slate и
  paper-feed запрещены. Generator, library, entry и pause возвращены на
  плоские тёмные цифровые поверхности; Camera Coach получает короткую команду,
  action-linked guide и свёрнутый lens control. Галерея v2.1 не одобрена и
  подлежит переработке до Phase 1.
- **v2.1** (2026-08-17) — закрывает обязательную прожарку: применены все
  SET-001…SET-026 и ART-01…ART-05 с owner overrides O-1…O-4. Bebas ограничен
  wordmark, Oswald назначен RU+EN display; добавлены font provenance/glyph
  gates, String Catalog, честный `LIVE`, no-Material live budget, contrast
  corrections, precedence к CC-008, полная visual-state projection, monotonic
  nominal-24 timecode, `previewContentRect`, container-based adaptivity,
  motif budget, deterministic fixtures и evidence manifest. Shell visual
  contract — `A/B ROLL`; routes/teardown/a11y IDs не изменены.
- **v2.0** (2026-08-17) — начальная каноническая версия. Отзывает
  «neutral-surface»-политику; фиксирует двуязычность RU+EN, iPhone+iPad,
  ориентационную политику по режимам, history вне v1.
