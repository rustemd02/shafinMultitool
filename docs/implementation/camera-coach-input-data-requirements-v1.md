# Camera Coach — требования к входным данным для поиска, разметки и обучения

Дата исходного документа: 2026-10-10. Обновление: 2026-10-11. Версия содержимого: 2.1 (имя файла сохранено для существующих ссылок). Статус: **спецификация следующего сбора; сбор и обучение по этому документу не выполнялись**.

Владелец запросил подробные требования и промпт для последующего поиска агентами по интернету, включая готовые датасеты. Этот документ описывает желаемый intake и критерии пригодности. Он **не меняет** JSON-схемы, production-модель, результаты прошлой разметки и обязательные release-гейты. Предлагаемые квоты и пороги качества ниже — инженерные начальные настройки, которые проверяются пилотом; это не доказанные оптимальные размеры датасета.

Готовый пакет задания поисковым агентам: [camera-coach-dataset-acquisition-swarm-prompt.md](camera-coach-dataset-acquisition-swarm-prompt.md).

**Продолжение 2026-10-11:** полученный внешний v2 корпус проверен в [отдельном аудите](acquisition/camera-coach-v2-audit-2026-10-11.md). Для нового запуска использовать [промпт продолжения v3](acquisition/camera-coach-v3-continuation-prompt.md): кино/сериальные scenes и continuous video process обязательны, текущий COCO — auxiliary. Это обновление требований, не объявление выполненного v3 acquisition.

**Уточнение владельца 2026-10-10:** первым исполнителем будет GPT 6 Pro в отдельном чате с доступом к репозиторию. Он должен широко найти и получить материалы, выгрузить корпус на Google Диск и выполнить self-review. Отсутствие даты съёмки у одиночного кадра **не является критерием отказа в сборе/разметке**; неизвестное время сохраняется честно. Current exporter constraints — последующая техническая адаптация, а не ограничение discovery/acquisition. Видеопоследовательности требуют порядка/непрерывности/сопоставимости независимо от календарной даты.

## 1. Какая задача должна определять данные

Camera Coach задуман как **визуальный киноассистент для начинающих кинематографистов**, снимающих постановочные сцены, короткометражки и другие видео с осмысленным киноязыком. Он помогает сделать кадр красивее и выразительнее прямо на площадке: выделяет конкретного героя или предмет, показывает направление исправления, предлагает изменение положения камеры, постановки, света или доступных настроек. Идеальный набор подсказок ещё формируется; исследование не ограничено текущими классификаторами. По изображению, выбранной цели и доступному контексту он должен:

1. Оставить хороший или намеренно стилизованный кадр без лишних исправлений.
2. Указать наблюдаемую проблему, если исправление действительно полезно.
3. Предложить одно понятное, выполнимое и поддерживаемое действие.
4. Учитывать цель съёмки и не выдавать неизвестное за установленный факт.
5. Воздержаться или запросить уточнение, когда доказательств недостаточно.
6. После действия оценить результат только при сопоставимых кадрах и сохранённой цели.

Поэтому единица ценности — **проверяемая съёмочная ситуация**, а не красивая картинка или количество файлов. Оценка эстетики, подпись к фотографии, bounding box и последовательность соседних кадров решают разные задачи; ни один из этих видов разметки автоматически не даёт команду оператору.

Приоритет домена: реальные съёмочные ситуации начинающего кинематографиста — диалог восьмёркой, общий/средний/крупный план, реакция, план через плечо, двое/группа в кадре, проходка и сопровождение, панорама и наклон камеры, наезд/отъезд, предметная перебивка, интерьер/экстерьер и сложный свет. Профессиональное кино полезно как отдельный источник киноязыка и референсов при подходящих правах, но финальный цветокорректированный кадр не заменяет необработанный мобильный preview. Общая фотография, товары/еда, животные и природа — дополнительное покрытие, а не основание незаметно сменить целевой продукт.

### 1.1 От возможностей приложения к данным

До массового сбора нужен versioned каталог возможностей: **съёмочная задача → полезная подсказка → доступные входы → разметка → визуальное предложение → проверка результата**. Каждая возможность имеет статус current/proposed/research/deferred и явную границу наблюдаемости. Исследовать сильные отличия от конкурентов по актуальным первичным источникам; гипотеза полезности или уникальности не равна подтверждённой killer feature.

Каталог должен отдельно рассматривать композицию, перемещение оператора/камеры, блокинг актёров, реквизит, свет, WB/цвет, экспозицию/фокус и другие реально доступные controls, временное поведение и связь соседних планов. Состояния «сказать», «показать направление», «показать условный preview», «применить настройку после согласия» и «автоматически управлять» требуют разных доказательств.

Классификация сцены многомерная: содержание, драматургическая/съёмочная задача, крупность, движение камеры, намерение и контекст соседних планов. Один кадр не доказывает восьмёрку, траекторию, соблюдение монтажной оси или художественный замысел. Намеренная асимметрия, короткий look room, силуэт и нестандартный цвет могут быть правильными для цели. Эти случаи нужны как защищённые контрпримеры.

### 1.2 Обязательные виды исходных материалов

| Вид | Какие данные необходимы | Что не следует из этих данных автоматически |
|---|---|---|
| Still и варианты одной сцены | Полный кадр, контекст/намерение, субъект, различия между вариантами | Предпочтение не доказывает физическое действие или causal improvement |
| Пространственная разметка | Stable entity IDs, bbox/mask/pose/anchors по выбранной задаче, видимость и occlusion | Bbox не является точным контуром; положение на экране не задаёт свободный путь в 3D |
| Непрерывный clip | Исходная временная шкала, tracks, смены видимости/плана/линзы, наблюдаемое движение | Optical flow не отделяет движение камеры от актёра без дополнительных оснований |
| До / действие / после | Планируемое и выполненное действие, один target, сопоставимость, результат, no-action/wrong-direction controls | Соседние кадры не являются подтверждённой коррекцией |
| Cinematic scene pack | Связанные планы одной сцены, участники, shot IDs/роли/порядок, eyelines/screen direction, известная география | Нарезка несвязанных киноскриншотов не образует диалог/coverage |
| Technical capture series | Реальные настройки камеры/линзы, WB/экспозиции/фокуса, цветовой pipeline, reference conditions | По готовому JPEG нельзя надёжно восстановить Kelvin/ISO/shutter или отделить стиль от ошибки |

Для overlay-задач фиксировать систему координат, orientation/mirroring, crop/resize/letterbox и связь source frame → model input → preview. Для видео нужны persistence target identity, reacquisition/expiry и условия скрытия стрелки при неоднозначности. Точная маска, трек и глубина требуются только возможностям, которые действительно их используют; отсутствующая разметка остаётся unknown. Метры, градусы и положение за пределами видимой сцены без измерений не придумывать.

Помимо классификации нужен дизайн структурированного visual proposal: адресат, target ref, действие, наблюдаемые предпосылки, направление и координаты, вид overlay, неопределённость, условия отмены и критерий результата. Предложить 6–10 полных примеров на разных киношных ситуациях. Renderer/tracker и проверка состояния — самостоятельные компоненты; их нельзя считать выученными по коллекции красивых фото. Выбор local CV/моделей, VLM или гибрида исследуется отдельно с привязкой к реальным latency/heat/memory ограничениям телефона.

## 2. Источники правды и ограничения совместимости

Для экспорта в **нынешнюю** модель использовать машинный контракт и существующий acceptance. Для новых возможностей предложить отдельный versioned каталог и mapping current → proposed → required migration: нынешние 15 issues и 26 mapped actions не ограничивают продуктовый поиск. Не менять смысл существующих IDs и не выдавать proposed labels за уже совместимые:

- [Release label v1](../../ml/camera_coach/contracts/camera_release_label_v1.md) и [JSON Schema](../../ml/camera_coach/contracts/camera_release_label_v1.schema.json).
- [Production heads v1](../../ml/camera_coach/contracts/camera_production_heads_v1.md).
- [Capability mapping](../../ml/camera_coach/contracts/camera_release_capability_mapping_v1.md).
- [Production acceptance](PRODUCTION_ACCEPTANCE.md), особенно C1–C3.
- [AVA policy](../cameraanalysis/17-ava-usage-policy-and-pretraining-design.md).
- [Coverage matrix](data-coverage-matrix-v1.md), [shot list](human-eval/shot-list-v1.md) и [аудит прежней сотни](../product-discovery-2026-10-08.md).

Перед утверждением end-to-end training readiness требуется разобраться с четырьмя несовместимостями ниже. Они **не запрещают широкий сбор исходников**; этот документ не исправляет code/schemas:

| Ограничение текущего пути | Последствие для сбора |
|---|---|
| Release label требует доказуемый `captured_at` в UTC; текущий exporter не умеет unknown/null | Полезное интернет-фото без даты собирать и размечать; source capture time = unknown. При последующей конверсии нужна адаптация exporter/contract либо совместимый research-путь. Не подменять дату съёмки загрузкой/публикацией и не отклонять из-за неё материал. |
| Свободный текст не является release label | Сохранять оригинальные слова рядом с отдельной структурированной меткой; конверсию подтверждает reviewer. |
| `production_heads.py` обучает головы на векторах признаков; исследовательская image-v2 имеет другой состав выходов | Наличие изображений и JSON ещё не доказывает готовый end-to-end production image trainer. На 5–10 записях доказать реальное потребление выбранным training path. |
| Текущий action-utility adapter обучает только выбранную положительную колонку; остальные маскирует | Не кодировать все невыбранные действия как плохие. Явные оценки неправильных альтернатив сохранять отдельно; для их обучения нужен отдельный совместимый adapter/contract change. |

Существующий [v2 input contract](../../ml/camera_coach/contracts/set_composition_net_v2.json) задаёт `full_frame_rgb` 320×320×3, `subject_crop_rgb` 192×192×3, ROI xywh[4] в oriented full frame, ROI mask 320×320×1, scalar features[40] с missing mask[40] и отдельные intent features[9]. Intent-conditioned supervision учитывает известность intent и наличие ROI по этому контракту. Это производные tensor inputs исследовательской модели, **не требования скачивать миниатюры такого размера**. `ProductionHeadsScorer` отдельно принимает float32 `[batch, feature_dim]` (default feature_dim=32); он не содержит image-adapter. Production preprocessing должен быть отдельно зафиксирован и совпадать с runtime. Не менять размеры, orientation/crop/resize геометрию или feature order только по этому документу.

## 3. Пригодность — несколько независимых решений

Для каждого материала хранить отдельно: права, техническую пригодность, смысловую полезность, доступную supervision, пригодность текущему exporter и предназначенный split. Общий `accepted=true` скрывает слишком много.

| Роль | Что допускается | Чего эта роль не доказывает |
|---|---|---|
| `discovery_candidate` | Найденный URL/record с описанием и неизвестными полями | Право скачать, наличие оригинала, реальные дефекты, готовность обучению |
| `annotation_still` | Просмотренный реальный кадр, достаточное разрешение для конкретной задачи, права на нужное использование подтверждены | Полную разметку, action feasibility, temporal outcome |
| `task_training` | Полезные структурированные метки и маски, совместимые с выбранным loader; provenance и split проверены | Human-gold и независимую оценку |
| `auxiliary_pretraining` | Native aesthetic/IQA/detection/tracking labels с их исходным смыслом и допустимыми правами | Coach verdict/action/risk или production quality |
| `synthetic_control` | Документированная трансформация разрешённого исходника либо контролируемый рендер | Реальные мобильные дефекты и успешное физическое действие |
| `temporal_episode` | Исходное видео/серия с подтверждённой непрерывностью, действием и контекстом | Автоматически improved/fixed, физическую App Store-приёмку |
| `locked_evaluation` | Независимо проверенные, замороженные и недоступные настройке примеры | Пригодность для обучения; использовать их для обучения запрещено |
| `quarantine` | Неполные права, сомнительная идентичность, отсутствующие байты или непроверенный контекст | Разрешение использовать в fit/export |
| `rejected` | Зафиксированная причина отказа | Право удалить исторические исходники или receipts |

Названия ролей выше — vocabulary будущего intake-ledger, а не новые enum значения release label. Роль и решения можно пересматривать с новой evidence; исходный файл и историческая запись остаются неизменными.

Кандидат считается **готовым к выбранному обучению** только когда одновременно подтверждены права, доступность/хеш медиа, задача и контекст, полезные labels/masks, split без leakage и успешный путь через конкретный loader. Отсутствующая метка не должна становиться отрицательной.

### 3.1 Какие данные питают нынешние production heads

| Consumer/target | Нужная evidence | Что маскировать / не выводить автоматически |
|---|---|---|
| `good_frame_probability` | Adjudicated good/mixed/needs_fix относительно цели и полезности коррекции | Abstain/unknown verdict; native MOS, лайки и «красивость» не target |
| `issue_logits` (15) | Проверенное presence/absence каждого issue с region/evidence где нужно | Неосмотренные issue heads, технический дефект на недостаточном разрешении |
| `action_utility_logits` (26) | Полезное поддерживаемое действие с context/target и evidence допустимости | Неизвестные альтернативы; forbidden-action sidecar до совместимого adapter |
| `continuous_target_deltas` (5 осей) | Измеримая magnitude/direction относительно указанного frame/target | Вербальное «немного», неизвестная ось/величина, физическая дистанция по одному фото |
| `risk_probability` | Явно оценённый риск данного proposal по доступной information; скрытая permission остаётся app gate | Неизвестное не становится нулевым риском; вероятность не выдумывать для заполнения |
| `abstention_probability` | Adjudicated should-abstain/should-not-abstain и причины недостаточной evidence | Неоднозначность не превращать в bad; отсутствие метки не считать abstain label |
| Calibration artifact | Отдельная frozen human-gold calibration partition с достаточным покрытием | Silver/proposal labels и training examples не заменяют calibration ground truth |
| App selection/tracking/verifier | ROI/identity/continuity, реальные episodes и объективные metrics | Не изобретать новый neural target head для app-owned функции |

Каждая запись должна дать хотя бы одну полезную наблюдаемую supervision или конкретную regression/abstention задачу. Отчёт содержит **effective supervised counts по head**, положительные/отрицательные/unknown и независимые scene groups. 1000 images с почти всеми masks=0 не равны 1000 обучающих примеров.

## 4. Обязательное содержательное покрытие

Агенты ищут кандидатов под именованные пробелы. Класс источника, название альбома, поисковая фраза и предсказание VLM — только гипотеза. Категория подтверждается просмотром конкретного кадра.

| Семейство ситуаций | Какие входные примеры нужны | Контрпримеры и неизвестности |
|---|---|---|
| Край кадра и масштаб цели | Человек/объект близко к краю, случайно обрезанная значимая часть, слишком мелкий субъект; альтернативы кадрирования | Намеренный close-up, detail shot, off-center framing, свободное место под текст |
| Look room и композиция | Видимые направление взгляда/движения, недостаточное пространство; баланс, горизонт, камера выше/ниже | Взгляд неизвестен; необычная композиция задана пользователем; нечитаемый горизонт |
| Выбор цели | Один объект, несколько конкурирующих, группа как единая цель, target вне кадра/частично закрыт | Не выбирать героя за пользователя; отсутствие явной цели не всегда дефект |
| Фон и перегруженность | Реальный clutter, merger, перекрытие, passer-by, яркий отвлекающий элемент или надпись | Важный контекст/документальная сцена; разрешение убрать предмет неизвестно |
| Свет и экспозиция | Контровой свет, потерянный субъект, clipping, недосвет, локальные hotspots, тени, смешанный свет | Silhouette, low-key, high-key, night mood, intentional flare; свет менять нельзя |
| Фокус и движение | Промах фокуса относительно выбранной цели, motion blur, shake; sharp/blurred фон при резком target | Bokeh, intentional motion blur, низкое разрешение или resize, которые мешают судить |
| Шум и оптика | Реальный шум, грязная/запотевшая линза, glare/obstruction с доказуемой причиной | JPEG/compression не выдавать за sensor noise; дым/туман/софт-фильтр не выдавать за грязь |
| Люди и группы | Разные лица, рост, возрастные группы, одежда, skin tones, кадрирование головы/рук, группа в помещении/на улице | Человека нельзя переставлять без разрешения; факт pose/эмоции не выдумывать |
| Предметы и постановка | Товар, еда, лампа, стул, декор; цель, movable/allowed и свободное место подтверждены контекстом | Встроенный предмет, чужое имущество, источник света без разрешения/безопасного доступа |
| Формат | Нативные/явно производные 9:16, 16:9, 4:3, 3:4, 1:1; место под титры задано context | 16:9-кадр не считается доказательством вертикальной съёмки; safe area не выводится без требования |
| Хороший кадр | Удачные обычные кадры, намеренный стиль, отсутствие полезного исправления | Высокий MOS не равен good; technically imperfect может быть правильным для цели |
| Воздержание | Неясная цель/intent, сильная окклюзия, неизвестные возможности действия, неоднозначный дефект | Честное unknown не означает автоматически bad и не требует конкретного действия |
| Временная проверка | Действие выполнено/не выполнено/в противоположную сторону; fixed/improved/unchanged/worse/incomparable | Target lost, cut, lens switch, изменившаяся цель/intent, postprocessing вместо съёмки |

### 4.1 Точные 15 issue IDs нынешнего экспортного пути

В релизной разметке каждый ID присутствует ровно один раз со статусом `present`, `absent` или `not_observed`:

```text
subject_too_close_to_edge
subject_not_prominent_enough
background_competes_with_subject
insufficient_look_space
backlight_hides_subject
scene_has_no_clear_focus
frame_visually_overloaded
horizon_distracts
motion_blur
defocus
overexposure
underexposure
noise
occlusion
lens_smudge
```

Coverage-теги вроде mixed-white-balance, title-safe, pose и perspective полезны для поиска и проектирования новых возможностей. Они не добавляют heads существующей модели автоматически. Новую supervision описывать в proposed-каталоге с будущим consumer и migration plan; до реализации адаптера сохранять отдельно от текущего release label.

### 4.2 Действия: искать только с проверяемыми предпосылками

Текущие production heads планируют 26 mapped action IDs:

```text
shift_frame_left, shift_frame_right, shift_frame_up, shift_frame_down,
step_back, step_closer, lower_camera, raise_camera, change_camera_angle,
level_horizon, move_subject_left, move_subject_right,
move_subject_away_from_background, move_object_left, move_object_right,
move_object_forward, move_object_back, remove_distracting_object,
add_front_fill_light, add_background_light, wait_for_background_clearance,
stabilize_camera, refocus_subject, reduce_exposure, increase_exposure,
avoid_occlusion
```

Оставшиеся IDs release-каталога: `rotate_subject_toward_light`, `reposition_prop_for_balance`, `remove_background_hotspot`, `simplify_background`, `clean_lens`, `reduce_iso_noise`, `keep_current_setup`. Их dispositions различаются; не включать их в эти 26 output columns. В частности, `keep_current_setup` — app-only policy output. Потенциально полезный кейс неподдержанного действия можно сохранить отдельным backlog/example, но не выдавать за готовую training supervision текущей модели.

К одному кадру может подходить несколько действий. Один выбранный совет не доказывает, что все альтернативы вредны. Если направление движения камеры и сдвиг цели на изображении имеют разные знаки, их нельзя смешивать. Физические метры/градусы по одному фото не назначать. Continuous deltas — только наблюдаемые значения в существующих нормализованных осях с доказуемым преобразованием.

## 5. Контекст: что реально доступно модели и приложению

Хранить отдельно визуально наблюдаемое, заданное оператором и неизвестное:

- Выбранный target: stable entity ref, person/object/group/light, роль, ROI; явный выбор, независимая разметка или AI proposal как источник.
- Цель и intent/style: пользователь/автор явно сообщил либо `unknown`. Красивый тёмный кадр не доказывает намеренный low-key.
- Разрешённые операции: движения оператора, людей, предметов, света; documentary/no-staging; доступные camera controls.
- Возможность передвинуть предмет и наличие разрешения: context/permission evidence, а не вывод «похож на стул — значит можно двигать».
- Lens, zoom, orientation, exposure/focus metadata: только фактические данные; не выводить значение 0.5× из широкого угла изображения.
- Кадрирование/формат, protected regions, места под надписи: только явное требование или подтверждённая разметка.

Главный критерий обучаемости: **label должен зависеть от информации, доступной соответствующему consumer**. Если две одинаковые картинки получают противоположные советы из-за скрытого разрешения или intent, это надо передать явным context input либо оставить проверку приложению. Нельзя научить image-only модель угадывать юридическое разрешение или пространство за спиной оператора.

Конкретное перемещение человека/объекта допустимо только с подтверждёнными identity, region, movability, allowed permission и поддерживаемой проверкой. Когда этих данных нет, искать/размечать общую поддерживаемую композиционную рекомендацию, ask/abstain либо только issue. Не заполнять недостающий контекст догадкой ради полного label.

## 6. Технические требования к одиночным изображениям

### 6.1 Исходник и качество представления

- Предпочитать оригинальную фотографию/исходный frame, а не превью поисковика, скриншот сайта или thumbnail.
- Для обычной очереди разметки начальный порог: long edge ≥1024 px и short edge ≥512 px; предпочтительно long edge ≥1280 px и short edge ≥720 px. Порог — параметр пилота, а не универсальное свойство модели.
- Для focus/noise/lens/technical-detail желательно original ≥1920×1080 по ориентационно независимым сторонам. Если исходное устройство/формат меньше, техническую head размечать только когда дефект различим на native resolution и просмотрен отдельно от ресайза.
- Кадры 640–1023 px long edge допускаются по reviewer exception для композиции/target с явным ограничением supervision. Малые thumbnails не ставить в основную очередь оценки technical quality. Нечитаемые кадры могут иметь отдельную роль abstention/regression.
- Не апскейлить материал для прохождения порога. Скачивание большего оригинала — допустимо; AI-upscale не восстанавливает evidence о фокусе/шуме.
- Реальная нерезкость, шум, clipping, недосвет и случайное кадрирование — нужные positive examples. Автоматические QC-сигналы помечают причину для проверки, **не удаляют все дефекты**.
- Файлы должны декодироваться; исключить пустые payload, HTML вместо изображения, повреждённые файлы. Ограничить размер/декодирование безопасным intake-процессом; цифры resource cap устанавливает исполнитель под реальный диск.
- Хранить формат, native dimensions, EXIF orientation и ICC/color profile. JPEG/PNG/HEIC/WebP и иные форматы допустимы, если выбранный decoder/preprocessing их действительно поддерживает. Конверсия создаёт производную с новым hash.

### 6.2 Композиция должна сохраняться

- Сохранять полный исходный frame, aspect ratio и crop lineage. Скачанный crop не выдавать за оригинальный field of view.
- Применять orientation ровно один раз. Метки ROI относятся к определённому oriented frame; фиксировать transformation chain.
- Normalized ROI: конечные `x,y,width,height`, ненулевые размеры, unit-square containment. Не переносить bbox из другого crop/resize без проверенного преобразования.
- Отдельный target crop не заменяет full frame: фон и композиция требуют окружения.
- Для mirrored selfie обозначать отражение и пространство координат. Проверять left/right на конкретном преобразовании.
- Watermark, титры, рамки, UI, contact-sheet подписи и overlaid labels фиксировать как артефакты источника. Не использовать подсказку в надписи как shortcut для модели. Не удалять watermark ради обхода происхождения/прав.
- Processing/retouch state: original camera / edited / unknown. Обработанное фото может быть полезно, но не автоматически доказывает исходный capture defect.

### 6.3 Синтетика и аугментации

Сохранять parent hash, generator/version, параметры, seed, transformation order и назначение. Native base должен быть достаточно качественным для создаваемого дефекта. Не наслаивать JPEG noise на уже разрушенную миниатюру и не выдавать результат за sensor noise.

Геометрическая трансформация может дать точную геометрическую величину, но не гарантирует, что кадр стал хуже: off-center/crop/tilt иногда намеренны. Label результата требует task-aware проверки. Простая смена яркости/цвета не подтверждает physically performed action. Генеративные изображения и edits имеют отдельный origin; движок не может self-certify человеческую/физическую evidence.

Все производные одного parent остаются в одной split group. Аугментации создаются после назначения split и не пересекают границы train/val/calibration/test.

### 6.4 Training inputs должны воспроизводить runtime

Для каждой training representation сохранить preprocessing/feature-extractor version и binding к source hash. Scalar features, saliency, target crop/mask и intent должны получать тот же смысл и порядок, что в выбранном runtime contract. Ground-truth ROI допустим как заданный пользователем target или label; если runtime использует detector ROI, оценивать и этот путь, не выдавая oracle boxes за production inputs.

Не включать в before-only advice inputs результат after, final verdict в имени файла, reviewer text с ответом, synthetic parameters, outcome metrics или другую информацию, которая появится лишь после совета. Verifier, которому по задаче доступны оба кадра, оценивается отдельно. Предполагаемый image encoder input должен быть реально связан с нужными production heads, а не только проходить tensor-shape проверку.

## 7. Видео, серии и before/after

Публичное видео может дать tracking, scene-cut, lens-like transition и background-motion examples. Готовое монтажное видео, фотопара ретуши и разные похожие фотографии **не доказывают выполнение подсказки**.

Для полноценного эпизода нужны:

1. Исходный непрерывный clip/доказуемая серия и source hash; предпочтительно ≥1080p и 24–60 fps для новых captures. Более низкое качество допустимо только для наблюдаемых задач, с exception и масками.
2. Общая сцена и stable target identity; before/after — разные frame IDs из известного source/episode.
3. Реальные frame timestamps/PTS и time base. Для VFR не вычислять время как `index / declared_fps`, если это не подтверждено.
4. Интервал before до действия, интервал действия и stable after; заданный operator action и фактически выполненное действие записываются отдельно.
5. Данные о target, protected objects, intent, контролах/линзе и допустимости постановки. Sensor/control logs полезны, но их нельзя выдумывать из видео.
6. Сопоставимость геометрии, света и цели; scene cut, смена линзы/intent, target lost и непредвиденные изменения явно отмечены.
7. Outcome `fixed/improved/unchanged/worse/incomparable/not_observed` только согласно наблюдаемым evidence и действующему verifier. Объективная метрика не заменяет human judgement пользы, а human judgement не подменяет факт выполненного действия.
8. Для `fixed`: objective predicate и goal satisfied; для `improved`: измеренное изменение за deadband; для `incomparable`: reason и честное same-target значение.

Для нового capture-пилота разумный ориентир: 1–2 секунды устойчивого before, выполнение одного действия, 1–2 секунды устойчивого after; весь clip часто 5–20 секунд. Это рекомендация организации съёмки, не универсальный acceptance threshold.

Обязательно собирать контрсценарии: действие не выполнено, неправильное направление, чрезмерная величина, стало хуже, цель закрылась/ушла, свет изменился независимо, произошла склейка/смена линзы. Сотня соседних frames одной попытки — **один эпизод**, не сто независимых примеров.

Реальные iPhone episodes/live-device acceptance нельзя полностью закрыть интернетом. Сначала автономно искать и получать existing real video/pose/IMU/control datasets и достоверные intervention sources; неполученные измерения не выдумывать. Для собственных device-specific проверок остаётся съёмка по [shot list](human-eval/shot-list-v1.md). Нынешний v1 production contract откладывает отдельный temporal scorer до доказанного пробела ML-011; это граница сегодняшней интеграции, не запрет исследовать temporal perception/tracking/motion и не ограничение будущего видеокорпуса.

### 7.1 Live video, causal inputs и раздельная supervision

Для задуманного видеоассистента continuous clips, а не independent stills, представляют процесс съёмки. Нужны camera-only, actor-only и mixed motion, static/follow/pan/tilt/reveal, entry/exit/occlusion/reacquisition, handheld style, cut/lens/target change и временное/устойчивое отклонение от заданного плана. Полезная единица содержит task-appropriate duration и native timestamps; два секундных окна не закрывают общий motion curriculum.

Раздельные consumers: detector/segmenter (frames/masks), tracker (linked identities/masklets), motion estimator (apparent type или measured pose), temporal task assessor (история/задача), planner (conditional полезность действия), overlay/state logic (fresh geometry/transforms/validity) и verifier (before/action/after). Наличие labels для одного consumer не считается supervision всех остальных. Pretrained reuse и geometry/state memory сравниваются с новой temporal NN; отдельная NN не является обязательной исходной аксиомой.

Совет в момент t потребляет только наблюдения ≤t, заданную задачу и реально доступные sensors/controls. Future frames, after metrics, final human verdict и annotations с ответом не становятся runtime features. Offline teacher, просмотревший весь clip, даёт privileged label с указанным происхождением; live evaluation использует past-only replay. Verifier после действия имеет другой information boundary.

Gyro даёт информацию о вращении, но не reliable metric translation сам по себе. Bbox drift/optical flow могут смешивать camera motion, actor motion, zoom, stabilization и parallax; measured/apparent/inferred/unknown labels различаются. Pose/calibration/IMU data полезны, но sensor rig не объявляется iPhone telemetry. Technical outcomes и artistic utility также разделены.

Corpus completeness проверяется по capability/input/label/consumer матрице. Автоматически собранные native и machine-proposal данные могут быть полезны для подготовки обучения; все необходимые человеческие/физические факты без соответствующей evidence не появляются. Controlled synthetic 3D data может дополнить motion/action supervision с отдельным origin; 2D animated crop не заменяет real motion.

## 8. Provenance, права и хранение

### 8.1 Что должен сохранить агент

На уровне источника и элемента: название/версия датасета, upstream ID, landing page, original/media URL, author/rightsholder при наличии, license identifier/version и URL текста, scope лицензии (annotations/images/video), attribution, ограничения retrieval/training/redistribution, дата проверки условий, краткая выдержка/evidence pointer, решение и неизвестности.

На уровне байтов: SHA-256 исходника после скачивания, dimensions/duration, decoder result, local media ref, retrieved_at, transformation lineage. Source URL без доступных проверенных байтов — только discovered candidate.

`retrieved_at`, `published_at`, EXIF local time и `captured_at` — разные поля. UTC capture instant устанавливается только из доказуемой даты и timezone/offset. EXIF без timezone сохраняется как исходная evidence со статусом unknown UTC; `Z` не дописывать автоматически. Извлечение frame требует ещё относительного media timestamp, не вымышленной даты.

### 8.2 Правила допуска

- Публичная доступность, индексирование поиском, кнопка Download и лицензия на dataset code/annotations не доказывают права на изображения или commercial model training.
- CC0/public-domain/permissive источники — кандидаты с более простым provenance, но всё равно проверить конкретный asset, применимость заявления и ограничения исходного сайта.
- CC-BY: сохранить attribution obligations. CC-BY-SA: отметить условия отдельно; не предполагать автоматически ни разрешение на все планы, ни запрет на model weights. Вывод о подходящем commercial workflow фиксируется отдельно с evidence.
- NC, research-only, unclear image rights или условия без подтверждения коммерческого применения: не admitting в production-training/release role; metadata-only discovery или иной явно допустимый research role, пока решение не подтверждено.
- Лицензия на copyright не заменяет consent/privacy/portrait/location rights и разрешение распространять персональные данные. Не собирать биометрическую идентификацию людей; stable target ref работает внутри эпизода.
- Не обходить login, paywall, access controls, rate limits или технические ограничения. Условия доступа, официальный API и retrieval rules проверяются отдельно; robots.txt не является лицензией на training.
- Социальные платформы можно исследовать как источники ссылок/потенциальных коллекций. Автоматическое скачивание допускается только при подтверждённых правах на asset и разрешённом способе доступа. Screenshot не исправляет отсутствие прав.
- Не публиковать raw corpus, thumbnails, contact sheets или model bundle assets до отдельной проверки соответствующего использования. Разрешение обучать и разрешение распространять исходники — разные решения.
- Если права неясны: записать URL и uncertainty в ledger; не притворяться, что issue решён, и не скачивать массово.

Это операционные admission-правила, не индивидуальное юридическое заключение. Старые license receipts и hash-bound manifests не переписывать.

### 8.3 Пути

Raw media, intake ledgers, queues, contact sheets, labels, split manifests, checksums и acquisition receipts хранить только под:

```text
/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/
```

Для новой волны использовать отдельный каталог, например `Datasets/camera-coach/intake/<run_id>/<source_family>/`; точное размещение согласовать с существующими conventions и `LOCAL_DATA.md`. Это рекомендация нового run, не команда создать его сейчас. В iOS-репозитории остаются спецификации, code и маленькие технические fixtures, **не raw corpus**. Не писать в Library и не класть датасет в Xcode bundle.

## 9. Минимальный intake-ledger

Ниже логические группы полей для будущего `candidates.jsonl`. Это **предлагаемый intake format**, а не executable schema и не допустимый release-label JSON. При реализации можно использовать существующие acquisition manifests и adapters; не создавать дублирующий persistence owner.

| Группа | Обязательные сведения | Неизвестное |
|---|---|---|
| Identity | run/worker/candidate ID, source family/version/record key, asset type | Не создавать идентичность только из порядкового номера без upstream key |
| Discovery | landing URL, media URL если известен, retrieval method, checked_at, источник search evidence | Недоступный оригинал явно указать |
| Rights | license/scope/URL, author, attribution, terms evidence, intended uses, rights decision/reason | `unknown` не превращать в admitted |
| Media | local ref после acquisition, SHA-256, dimensions/format/orientation/color profile; duration/fps/timebase для видео | До скачивания hash и local ref = null; не вставлять примерные/чужие хеши |
| Times | retrieved_at, source published_at, raw capture-time evidence, captured_at UTC, timestamp status | Сохранять null/unknown честно на intake; current release export при этом blocked |
| Lineage | parent assets, source video+PTS, crop/edit/resize chain, derivative/near-dup/scene/author groups; stable `crossDatasetLinkKey` для связи public pretraining и rubric records | Обработку unknown не объявлять original |
| Domain | mobile/native-camera/web-photo/pro/cg/scan/screen, device claims и evidence, organic/synthetic | Не считать web-photo автоматически smartphone |
| Coverage | proposed buckets и rationale, human/AI/source origin, visually inspected? | Proposed bucket не final issue label |
| Context | target/ROI, explicit intent, allowed operations, protected refs, observed vs unknown evidence | Ненаблюдаемое context не имитировать |
| Cinema | scene/shot/episode/technical-series IDs, participant refs, shot scale/task/motion/sequence roles, связь планов | Восьмёрка и continuity без связанного контекста остаются непроверенными |
| Grounding | entity/track IDs, masks/boxes/pose/anchors refs, frame time, visibility, coordinate transforms | Отсутствующий mask/track не заменять выдуманной точной геометрией |
| Capabilities | proposed/current capability IDs, доступные inputs/labels, missing supervision, будущий consumer | Useful source не означает готовность новой возможности |
| Suitability | intended lane, eligibility per task/head, quality exceptions, pending blockers/reject reasons | Один общий boolean не использовать |
| Annotation | raw opinion ref, proposal model/version/prompt/ref, review refs, adjudication ref, label schema/version | Нет review — нет human-gold |
| Splits | split group IDs, assigned split, freeze/version, duplicate evidence | Split не назначать независимо каждым downloader |

Агент может заполнить только то, что проверил. Метаданные стороннего датасета сохраняются исходным payload/ref; наши labels лежат отдельно с lineage.

## 10. Ручная и автоматическая разметка

### 10.1 Без человеческой оценки можно автоматизировать

- Decode, dimensions, hashes, source IDs, source-native annotations и provenance checks.
- OCR/детект объектов/ROI/blur-exposure metrics как proposals/features с указанием модели и ограничений.
- Deterministic transformations и точные геометрические параметры их генерации.
- Поиск duplicates, candidate grouping и баланс очереди; спорные совпадения — review.
- Предварительные issue/action/intent suggestions VLM, natural-language-to-structured conversion и triage.

Автоматический confidence — не подтверждение истинности. Два VLM, один VLM в двух проходах или согласие нескольких агентов не образуют независимых человеческих reviewers. Модель, помогающая аннотатору, делает проход assisted; он не считается blind human vote.

AI labels могут быть отдельной silver/research supervision для разработки/экспериментов, если loader это честно поддерживает. По текущему production пути final fit и calibration требуют установленного human-gold допуска; автоматическое промаркирование миллионов фото этот gate не закрывает.

### 10.2 Что подтверждает человек

- Видимый дефект и его значимость относительно target/intent; good/preserve/mixed/needs_fix/abstain.
- Реальная полезность и допустимость действия; identity/ROI при неоднозначности.
- Safety-critical, object/person-move, wrong-direction, intentional-style и no-issue cases.
- Истинные temporal outcomes и спорные изменения качества.
- Структуру, полученную из его исходного свободного текста.

`provenance.origin=model_proposal` навсегда non-gold для этой записи. Обычный human review тоже не равно gold. По текущему release contract только `human_adjudication`, ≥2 review IDs и adjudicator ID допускают `human_gold=true` и `release_admissible=true`; нужны реальные независимые проходы, а не формальные фиктивные IDs.

### 10.3 Правила labels

- Для 15 issue heads: `present` с evidence/severity/confidence; `absent` только после проверки; `not_observed` для неизвестного. Не заполненные аннотатором поля не становятся absent.
- `good/mixed/needs_fix` оценивается относительно цели. `abstain` не кодируется как good/bad; в release label это null verdict/action и поддерживаемый reason.
- Не принуждать reviewer выбирать действие, если полезного поддерживаемого действия нет.
- Не писать нулевые deltas/risk вместо unknown. Уточнить, что confidence reviewer, estimated risk и измеренная probability calibration — разные сущности.
- Normalized delta хранить только для наблюдаемой оси и с convention. «Чуть левее» без измерения не даёт точное число −0.17.
- Expected/forbidden actions и negative alternatives можно хранить в evidence sidecar для оценки; не расширять closed label schema произвольными keys.
- Предположение о пользе действия по одиночному кадру и наблюдение результата после выполнения хранить раздельно.

### 10.4 QA и экономия времени владельца

Предлагать человеку curated очередь с оригиналом/zoom, target/context и короткой причиной включения. Перед основной очередью проверить фактическое соответствие displayed pixels ↔ frame_id ↔ SHA-256; stale preview и duplicate record IDs — блокер.

Калибровать reviewers на небольшой подвыборке с blind first pass. Для контроля согласия считать по осям verdict/issue/action/target/intent, отдельно анализировать критические споры. Финальное решение фиксирует adjudicator с причиной. Быстрый проход, согласие с моделью или низкий disagreement сами по себе не доказывают качество.

Автоматический отбор тоже проверять: взять random subset отклонённых кандидатов, чтобы обнаружить потерю реальных дефектов/хороших кадров. Разметка нескольких frames одной сцены не увеличивает diversity; сначала покрывать новую ситуацию.

## 11. Баланс, объём и этапы

Количество кадров не задаёт качество. Сбор и готовность обучения — разные milestones: после control sample можно широко получать полезные исходники, не ожидая моей разметки. Перед final fit требуется проверить acquisition → annotation → label validation → loader → supervised loss masks. Числа ниже — бюджеты циклов, **не обещание достаточности для production training**.

Для GPT 6 Pro полного acquisition/upload запуска рабочий ориентир: 1000–3000 независимых useful still groups, curated queue 200–300, около 300 отдельного evaluation reserve, 30–100 useful real clips/scene units при возможностях sources/tools. Clips, связанные scene packs, technical series и genuine action episodes считать отдельно, не складывать как эквивалентные единицы. Эти бюджеты пересматриваются после выбора приоритетных capabilities; stills не закрывают дефицит временного/межпланового контекста. Больший auxiliary источник допустим по обоснованной роли/правам/ресурсам; меньший проверенный результат лучше искусственного заполнения quota. Аудит capture sample 20–30 предшествует масштабированию **сбора**; human label→loader proof остаётся отдельным шагом до обучения.

### Этап A — калибровочный пилот

Для новых возможностей сначала проверяется capability→data матрица и подходящая единица из §1.2. Следующие пункты относятся к проверке нынешнего label/loader пути; они не сужают исследование до 15 issues и не блокируют сбор proposed возможностей.

- 20 уникальных и просмотренных примеров с подтверждёнными правами; на 5–10 доказать весь выбранный pipeline.
- Рабочая смесь: 8 очевидных исправимых ситуаций, 6 good/intentional-style, 4 ambiguous/abstain, 2 ограничения разрешения/движения. Это task quota, не оценка реального prevalence; несколько tags могут пересекаться.
- Добавить несколько реальных before/after episodes отдельным пилотом; still quota их не заменяет.
- Проверить все 15 issue statuses, target/intent, правила unknown, верный displayed frame и не только schema validity, но ненулевую **нужную** supervision в loader; unknown capture-time exporter issue учесть отдельно, не отбраковывая полезные stills.
- Измерить время разметки, долю пригодных кандидатов, reviewer disagreement, частые unknowns, source/technical rejection и стоимость привлечения одного нового полезного scene group.

### Этап B — проверка расширения

- До 100–200 уникальных scene/asset groups после успешного A; 2–3 кандидата на нужную позицию можно найти, но в annotation queue идёт лучший подходящий материал.
- Начальные ориентиры основной still training-очереди: 25–35% good/preserve, 15–25% ambiguous/abstain, остальные corrective. Это ориентир против false positives; категории качества назначает reviewer, не crawler.
- Предпочитать реальные smartphone captures; для нового mobile-core стремиться к ≥60% подтверждённых mobile/специально записанных групп. Если происхождение unknown, не включать его в эту долю. Не добирать процент предположениями.
- Ни одна source family не должна занимать >20%, один автор/альбом >10% curated still queue без явно зарегистрированного исключения. Цель — разнообразие; для отдельного auxiliary датасета эти caps не применяются механически.
- Organic, synthetic, generative и pro/cinematic домены отчётно разделены. Synthetic не закрывает quota organic. Для пилота model-free assisted labels permissible только в research/silver role.
- Для каждого поддерживаемого issue искать positives и проверенные negatives; для intent-sensitive heads — intentional counterexamples; для действия — допустимость, направление, полезные и вредные/неэффективные варианты.

### Этап C — масштабирование по ошибкам

Размер следующей волны определяется learning curves, per-head masks/coverage, ошибки на validation, а не желанием набрать 10/100 тысяч файлов. Если новый корпус не улучшает нужный bucket или не уменьшает критические ошибки, менять источник/label/task, а не просто объём.

Для финальной оценки действующий контракт требует ≥250 различных locked stills и ≥30 реальных guided physical-device sequences. Иные операционные планы — 350 stills, 700 episodes, 350 protected negatives, 210 device sequences — описаны в старом shot list и не являются численными требованиями Apple. Эта спецификация не отменяет acceptance и не выдаёт pilot за его прохождение.

Balanced evaluation по buckets хранить отдельно от естественной user-distribution выборки. Результаты balanced set не представлять как прямую оценку частоты ошибок у всех пользователей.

## 12. Splits и защита от leakage

- Уникальность считать по source/scene/derivation group, не только SHA-256 файла.
- Exact duplicates: hash bytes; near duplicates: visual similarity/crops/resizes, подтверждение спорных случаев; cross-dataset overlap — общие source keys и ancestry.
- Все frames одного video/episode, burst, сцены, before/after, исходника и его transforms держать в одном partition. Для shot-series учитывать author/location/session, иначе фон и субъект утекают.
- Split assignment делает один coordinator после дедупликации. Workers не распределяют одинаковый source независимо.
- Отдельно train, development validation, calibration и locked final test; proportions выбираются по числу независимых групп и покрытию. Не обещать, что random 80/10/10 устраняет leakage.
- Gold calibration/test не формируются только из AI proposals и не показываются trainer/tuner/prompt-optimizer. Candidate curator, уже знакомый с test, не использует его ошибки для настройки оцениваемой версии.
- Aesthetic pretraining и прочие auxiliary sources тоже проверяются на пересечение с downstream locked test. При overlap — исключить из соответствующего training source либо честно перенести record в знакомый regression слой.
- Новые случаи, по которым уже исправляли систему, полезны для regression, но больше не unseen holdout.
- Freeze: manifest version/hash, schema/adapter/preprocessing versions, counts по scene groups, split hashes и фиксированные QA/rights decisions. Пересмотр создаёт новую версию, не переписывает историческую evidence.

## 13. Как искать в интернете и готовых датасетах

Discovery может охватывать весь доступный интернет. Acquisition начинается с источников, где можно подтвердить provenance, достаточное качество, разрешённое использование и связь с named gap.

Предпочтительный порядок:

1. Уже имеющиеся local families — инвентаризация manifest/labels, dedup и targeted sample review; не скачивать повторно то, что есть.
2. Собственные/разрешённые smartphone captures и коллекции с явным описанием съёмки.
3. Public-domain/permissively licensed отдельные реальные фото и исходные видеоклипы с per-item evidence.
4. Task datasets для visual priors: эстетика, image quality, detection/segmentation/pose/grounding/tracking/depth, composition; отдельно источники shot scale/camera motion/связанных кино-сцен, WB/color и контролируемых capture series. Native labels сохраняются без переименования в Coach labels.
5. Синтетические контролируемые случаи для узких transform/identity/geometry задач и robustness.

AVA здесь всегда **Aesthetic Visual Analysis**, не одноимённый action-recognition video dataset. Старое описание `ava` как кино-клипов в `data-quality-analysis-v1.md` противоречит канонической AVA policy; фактическое происхождение локальной семьи надо проверять по manifest, а не переносить эту фразу в новый dataset report.

Raw aesthetic MOS/score distribution допустимы как отдельный auxiliary pretraining/proxy objective. Они не превращаются в `good`, issue, intent или action. AVA-origin asset, заново размеченный по нашей rubric, получает **отдельный downstream record** с собственным label tier, правами и split constraints; raw AVA record не переименовывается в gold. Stable `crossDatasetLinkKey` должен совпадать в raw manifest и rubric asset descriptor для cross-dataset dedup. AVA provenance сам по себе не гарантирует ни запрещение, ни admission. Native AVA labels не становятся release evidence.

При оценке dataset-source агент отвечает: какие именно labels есть; какая head/task получает честную supervision; нужны ли original images; какие licenses покрывают annotations и медиа; есть ли версии/links/dead sources; насколько домен похож; какие metadata отсутствуют; что придётся размечать заново. Paper citations, mirrors и GitHub wrapper не заменяют исходные условия доступа.

### 13.1 Начальный source inventory: что известно и что ещё проверять

Проверка ссылок/условий: 2026-10-10. Это примеры источников для следующего поиска, **не список разрешённых production-загрузок**. Оценка возможной роли для Coach — наше task mapping, а не обещание авторов датасета.

| Источник и primary reference | Исходная supervision / возможная роль | Ограничения и непроверенные права |
|---|---|---|
| [AVA: Murray, Marchesotti, Perronnin, CVPR 2012](https://projet.liris.cnrs.fr/imagine/pub/proceedings/CVPR2012/data/papers/304_P2C-42.pdf) | Aesthetic scores, semantic/style metadata; отдельный visual prior | Текущие первичные условия получения/использования конкретных изображений не подтверждены. Paper не даёт автоматического права на corpus. Не путать с action AVA и не конвертировать native scores в Coach labels. |
| [KonIQ-10k, страница авторов](https://database.mmsp-kn.de/koniq-10k-database.html) | Generic in-the-wild image-quality ratings, MOS/dispersion и indicators; IQA auxiliary | Страница предлагает full 1024×768 и small 512×384; для разметки предпочитать full. Отдельные коммерческие условия images/ratings здесь не установлены; доступ для research community не считать разрешением коммерческого fit. |
| [PaQ-2-PiQ, оригинальная CVPR 2020 статья](https://openaccess.thecvf.com/content_CVPR_2020/html/Ying_From_Patches_to_Pictures_PaQ-2-PiQ_Mapping_the_Perceptual_Space_of_CVPR_2020_paper.html) | Global/patch quality judgments; local/global IQA auxiliary | Статья подтверждает задачу качества, но просмотренный paper не устанавливает применимые права на конкретные файлы. Actions/intent не предоставляются этой supervision. |
| [Open Images V7 — описание и licenses](https://storage.googleapis.com/openimages/web/factsfigures_v7.html), [форматы/metadata](https://storage.googleapis.com/openimages/web/download_v7.html) | Categories, boxes, masks, relationships, occluded/truncated/group hints; поиск target/context | Annotations CC BY 4.0, изображения перечислены как CC BY 2.0; авторы требуют самостоятельно проверять права каждого изображения. Metadata различает OriginalURL и thumbnail. Native occluded flag не равен вредной для выбранной цели Coach occlusion. |
| [COCO, официальный сайт](https://cocodataset.org/) | Detection/segmentation/captions; поиск subjects/scenes | Caption/box не дают verdict/action. Конкретные image и annotation terms/источник каждого asset проверяются отдельно; в этой задаче они не установлены. |
| [MIT-Adobe FiveK, официальный источник](https://data.csail.mit.edu/graphics/fivek/), [Adobe license](https://data.csail.mit.edu/graphics/fivek/legal/LicenseAdobe.txt) | Кандидат для изучения тоновых/editing пар, если их состав и lineage подтверждены | Проверенная Adobe license разрешает только research и исключает commercial advantage/compensation для охватываемых ею images. Нужна привязка конкретных файлов к license/file list; не переносить этот вывод механически на все файлы FiveK. Пара обработки не является выполненной подсказкой при съёмке. |

Недоступность страницы, mirror без проверенной lineage или неполные terms должны попасть в source report как unknown/blocker. Поисковый агент может предложить другой источник под тот же gap, вместо попытки любой ценой скачать известный benchmark.

## 14. Admission checklist и результаты будущей волны

Материал попадает в очередь человека, если:

- [ ] Назван конкретный gap/task; есть короткая причина, почему данный кадр полезен.
- [ ] Просмотрены правильные pixels; ID/hash/URL соответствуют исходнику.
- [ ] Права и способ получения проверены для предназначенного использования; неопределённости не скрыты.
- [ ] Достаточны разрешение/контекст для хотя бы одной named supervision; exceptions отмечены.
- [ ] Исходник, transformations и metadata сохранены; времена не выдуманы.
- [ ] Есть независимая source/scene group и dedup status.
- [ ] Organic/synthetic/domain, intent и target claims имеют evidence либо unknown.
- [ ] Определён lane; current exporter/loader incompatibilities перечислены.

Дополнительный допуск к task fit требует подтверждённой структуры, верных masks и совместимого loader. Допуск к gold/evaluation требует независимых reviewers/adjudication и locked splits. Эти состояния не объединяются.

До масштабирования acquisition coordinator должен получить пункты 1–5. Пункты 6–7 относятся к отдельной training-readiness приёмке, а не останавливают получение полезного raw corpus:

1. Source inventory с primary URLs, правами, task mapping и неизвестностями.
2. Candidate ledger с per-item evidence, rejected/quarantine reasons и dedup IDs.
3. Curated 20-example pilot; при annotation-ready статусе — доступные исходники и проверенный viewer, а не список ссылок.
4. План отдельных real-capture gaps, которые интернет не закрывает.
5. Отчёт числа **независимых пригодных групп** и распределений tasks/heads/domains/quality/unknowns/rights, а не только количества файлов.
6. Результат 5–10 label→loader проходов с именем trainer/adapter; test fixture или schema PASS не выдаётся за полный training fit.
7. Решение go/no-go training шага. При неготовых правах или loader — точный blocker; unknown still timestamps — задача совместимости, не причина отвергнуть useful corpus.

Сбор считается полезным, когда он уменьшает дефицит конкретной наблюдаемой задачи и сохраняет честность evaluation. Download count и красивый contact sheet этого не доказывают.

## 15. TaskStartSnapshot и граница выполненной работы

Change Necessity: прежняя source-based очередь не задаёт надёжных требований к семантике кадров и совместимости обучения; владельцу нужен самостоятельный документ для будущих acquisition agents.

Ownership этой задачи: новая спецификация и acquisition prompt, короткая ссылка из implementation index. ArchitectureReviewRequired: **нет**, потому что production/data schemas и persistence не меняются; отмеченные gaps требуют отдельных задач перед реализацией.

На момент записи не выполнялись crawling, download, пересборка очередей, изменение labels/splits, schema migration или training. Числа пилота — план. Документ не добавляет empirical evidence к thesis и не меняет прежние результаты/статусы готовности приложения.
