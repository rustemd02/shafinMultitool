# GPT 6 Pro — полностью продолжить сбор Camera Coach: кино, сериалы, живое видео, движение и подсказки

Дата: 2026-10-11. Версия: 1.0. Самодостаточное задание на продолжение после проверки `CameraCoach_Dataset_v2` и уточнения, что приложение сопровождает процесс видеосъёмки.

Скопируй весь текст между разделителями. Приложи папку/архив v2 и, если доступны, ответ GPT Pro о временных данных и ссылку на целевую папку Google Диска. Промпт содержит факты аудита, поэтому прежний чат не обязателен. [Локальный аудит](camera-coach-v2-audit-2026-10-11.md) — дополнительная evidence, не условие понимания задания.

---

## Задание для GPT 6 Pro

Ты продолжаешь реальную работу над датасетом для моего приложения **SET OS / Camera Coach — визуального киноассистента на iPhone для начинающего кинематографиста во время видеосъёмки**. Работай как исследователь данных, оператор-постановщик, инженер video computer vision и организатор acquisition. Нужен фактически собранный, пригодный к дальнейшей разметке/обучению корпус, а не новый отчёт с обещаниями.

### 1. Моя цель и твоя ответственность

Пользователь смотрит в живой видоискатель. Приложение помогает сделать кадр и движение камеры красивее, выразительнее и уместнее для снимаемой сцены. Оно понимает доступный контекст, удерживает выбранного героя/предмет, предлагает полезное действие, наглядно показывает его и проверяет по последующим наблюдениям, что произошло.

Совет может касаться композиции, крупности, положения оператора/камеры, pan/tilt/follow, расположения конкретного актёра или предмета, света, экспозиции, фокуса, WB и других доступных controls. На экране могут появляться контур, выделенный регион, стрелка, зона желаемого положения, направляющая горизонта, focus/light region или control. Смысл стрелки должен быть однозначным: оператор, человек, предмет и устройство — разные адресаты.

Во время съёмки всё меняется: герой движется, оператор поворачивается/идёт, фон меняется, цель закрывается, автофокус/экспозиция реагируют. Поэтому система должна работать с историей наблюдений и состоянием задачи. Независимые JPEG не представляют этот процесс.

Твоя цель — **самостоятельно собрать весь доступный и обоснованно необходимый корпус для согласованного набора возможностей**, включая реальное кино/сериальное ядро, непрерывные видео, spatial/temporal annotations, источники движения камеры, conditional advice data и связную структуру. Не перекладывай поиск и скачивание на меня, если tools позволяют тебе это сделать. Автоматизируй acquisition, extraction, grouping, draft annotation, QA и доставку.

«Полностью» означает исполнение проверяемой матрицы capability→input→data→supervision→consumer, а не заявление, что произвольное число видео покрывает любую будущую функцию. Каталог возможностей ещё формируется. Невосстановимые исторические настройки, намерение или физическое действие не становятся фактами от требования автоматизации. Закрывай реальные пробелы другим существующим источником, корректной weak supervision либо отдельно описанной контролируемой синтетикой; оставшееся показывай точно и продолжай остальную работу.

Главные пользователи: начинающие операторы/режиссёры, студенты киношкол, небольшие команды, которые снимают диалоги, постановочные сцены, короткометражки, учебные этюды и небольшие ролики с киноязыком. Идеальный vocabulary подсказок ещё исследуется. Текущие 15 issue heads и 26 mapped actions проекта — baseline интеграции, **не ограничение списка новых возможностей**. Работа не относится к отдельному SMM-продукту.

### 2. Почему предыдущий результат не устроил владельца

Предоставленный `CameraCoach_Dataset_v2` содержит:

| Состав | Проверенное состояние |
|---|---|
| Primary images | 1318 |
| COCO2017 val photos | 1270; 96.36% всех images; max640 px длинной стороны |
| Native object annotations | 9352 regions, 1256 annotated photos, 80 classes; не coaching labels |
| Кинокадры | 48 JPEG views одного фильма Tears of Steel; 3.64% image assets |
| Видео | 2 reconstructed windows по 24 frames при declared 24 fps — примерно секунда каждый |
| Склейка | В первом окне перед `tos_08406` |
| Scene pack | 1 candidate на двух кадрах, без проверенной полной связи/географии |
| Сериальный материал | В source manifests отсутствует |
| Human Coach labels / genuine interventions / verified tracks / actual control series | 0 / 0 / 0 / 0 |
| Первая очередь | 250 только COCO-фото; киношных frames в ней 0 |
| Split этой очереди | 184 train candidates + 44 calibration + 22 development |
| Reserve | 300 COCO photos; не независимый unseen benchmark для COCO-pretrained models |

Все 40 capabilities в каталоге proposed. Полезные native masks дают static grounding supervision; они не дают правильного совета, camera trajectory или доказательства улучшения. `multi_person` означает count native regions, иногда это прохожие, спорт или изображённые люди. Это не диалог/восьмёрка.

Основные bytes/ссылки/hashes пакета согласованы; нет причины выбрасывать v2. Но он является auxiliary/static branch. В локальной проверенной папке separate PNG masters не были найдены, хотя они указаны как отдельный архив: сначала выясни наличие этого архива, не выдумывай потерю/доставку. PNG и JPEG одних кадров никогда не считаются разными независимыми примерами.

По нашей инженерной оценке v2 имеет **3/10 пригодности для целевого live cinema corpus**, примерно 6/10 для отдельной static grounding задачи. Это субъективный rubric score, не accuracy. Исправляй смысловой перекос и временные пробелы; не пытайся поднять оценку переименованием каталогов или увеличением COCO.

### 3. Присланный ответ GPT Pro — baseline для критического продолжения

В предыдущем ответе ты правильно признал: полноценный видеоассистент нельзя обучить на нынешнем наборе; один похожий кадр может относиться к static framing, follow или intentional pan/reveal и требовать разных реакций. Предложены SA-V, MovieShots, temporal features, tracker, camera motion, planner и verifier, а также пример 50 постановок ×4 дубля.

Прими это как **проверяемый baseline**, а не 100% истину:

- Недостаток v2 и необходимость video/context подтверждаются его составом.
- Не доказана обязательность именно TCN/GRU, одной temporal NN или конкретного окна 2–4 секунды. Исследуй уже обученные компоненты + geometry/state memory + planner и сравни разумные альтернативы.
- 30 fps capture, tracking near-preview-rate, 2–5 Hz heavy analysis, 8–16 selected frames — инженерные гипотезы, не hardware measurements и не универсальные требования датасета.
- Gyro помогает измерять вращение; reliable metric translation из gyro/ускорения автоматически не следует. Visual/IMU pose имеет calibration, observability и drift ограничения.
- SA-V masks не являются художественными метками; MovieShots movement/scale не являются метками action utility.
- «200 собственных дублей» не должно стать поводом прекратить автономный сбор и отправить мне домашнее задание. Сначала ищи подходящие existing capture/pose/alternative-take/controlled datasets и реально получай их.
- Разные картинки из фильмов, поставленные в ответе как этапы 00:01/00:03/00:05, не являются связанным episode. Декоративные иллюстрации не включать в evidence counts.

Проверь научные/профессиональные аргументы и источники, уточни ошибочные части baseline и переходи к исполнению. Не повторяй длинное признание ошибки вместо работы.

### 4. Инструменты и автономное выполнение

В начале проверь фактические tools: поиск по web/Google Images, открытие source pages, просмотр pixels/video, binary download, scripts/ffmpeg/archives, local files, Google Drive write/upload. Имя модели/connector не гарантирует каждую возможность. Назови available/unavailable кратко.

Если доступны subagents, используй Luna Max для независимых crawling/source/metadata shards и рутинной обработки; ты остаёшься владельцем taxonomy, качества, дедупликации, split и финального решения. Не заявляй модель/режим агента без runtime evidence. Не запускай несколько writers одного manifest или одни download shards дважды. Сохраняй bounded source/task assignment, hashes и resumable ledger.

Проверяй источник непосредственно, а не только search snippet. Выполняй бесплатные доступные download/extraction/annotation/QA/upload действия без повторных разрешений. Не покупай данные/подписки, не отправляй письма и не публикуй материалы. Формы, которые требуют личных/организационных данных, заполняй только реальными доступными сведениями; не выдумывай affiliation/research purpose. При необходимости конкретного ввода продолжай независимые ветки, затем задай один короткий вопрос.

Если нет binary tools, явно зафиксируй эту границу: URL ledger не является доставленным датасетом. Создай максимально полезные реальные attachments/downloader из доступных ресурсов. Если нет Drive upload, подготовь проверенные downloadable ZIP shards и manifests; обозначь upload blocked. Продолжай весь доступный сбор. Не выдумывай bytes/hashes, просмотр, screenshots, архивы или Drive IDs. Не заявляй full delivery при fallback.

На компьютере владельца исходные datasets/annotations/checkpoints живут в `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`, вне iOS repo и Xcode bundle. В своей sandbox используй явный temporary workspace и сохрани итог для передачи. Repo нужен для read-only проверки contracts/owners; этот заказ не включает обучение, публикацию или изменение production app-кода.

### 5. Полнота через функциональную матрицу

До масштабирования создай `capability_data_acceptance.csv`. Для каждой выбранной возможности:

```text
capability_id / version / current|proposed|research|deferred
concrete user workflow / target / intent source
required runtime observations and history
which component needs to learn or evaluate this behavior
required data unit and minimum observable evidence
source candidates / media availability / use scopes
native targets available / machine draft targets needed / human review needed
coverage dimensions and provisional sampling budget
acquisition, annotation and evaluation acceptance method
status: raw_available|native_supervised|weak_supervised|human_verified|missing
missing fact, replacement source or controlled-synthetic alternative
```

Возможность может иметь несколько data lanes. Различай «мы получили raw для разметки», «есть native targets для этой задачи», «есть машинные coaching proposals» и «проверена пользовательская польза». Не называй их общим training-ready.

Не исключай важный сценарий из каталога только потому, что подходящий download неудобен. Не объявляй любой фильм хорошей разметкой любой функции. Полнота набора определяется coverage и target validity, а не общим числом frames/масок/файлов.

### 6. Архитектура корпуса: шесть связанных частей

**A. Cinematic references и scene context.** Настоящие кадры и связанные планы фильмов/сериалов для крупности, блокинга, композиции, света, экранного направления и постановочной логики.

**B. Live temporal video.** Непрерывные планы с camera/subject motion, устойчивым target ID, occlusion/loss/reacquisition и изменением композиции во времени. Это обязательная основа видеочасти, а не факультативные две секунды.

**C. Mobile/beginner bridge.** Реальные пользовательские, учебные и бюджетные постановочные captures, good/imperfect/ambiguous/style cases. Они связывают красивый final film и наблюдения preview, на которых работает приложение.

**D. Grounding/tracking/pose auxiliary.** Source-native masks/boxes/masklets/pose/depth/flow/IMU там, где это реально помогает нашим компонентам. V2 COCO можно сохранить здесь, не расширяя его вместо целевых частей.

**E. Conditional coaching supervision.** Задача/цель, useful action и adverse alternatives, visual proposal, preserve/ask/abstain и временные моменты актуальности. Автоматическая экспертная proposal-разметка допустима с честным происхождением, human gold без человека не возникает.

**F. Technical/intervention/control evidence.** Доступные existing captures с реальными параметрами/poses/световыми reference, альтернативами и действиями; separately marked controlled synthetic sequences. Они нужны для технических советов и проверки результата. Если raw interventions отсутствуют, фильм не маскируется под intervention.

Assets могут участвовать в нескольких задачах через refs. Не копируй одни bytes в разные папки ради увеличения counts. Сохраняй video→shot→frame→target→proposal→episode связи.

### 7. Кино/сериальное ядро: исследуй широко

Перечни ниже — **открытые стартовые примеры**. Сам расширь taxonomy по киноязыку и болям начинающего оператора; не ограничивай сбор восьмёркой, крупностями или перечисленными движениями.

Разделяй независимые измерения: content; постановочная задача; крупность; camera angle/level; camera movement; субъект/взаимодействия; intent/style; пространственная и межплановая связь. Avoid один плоский class, в котором «крупный план», «диалог» и «pan» взаимоисключают друг друга.

Исследуй, например:

- Диалог single/reverse, OTS, clean singles, two-shot, foreground shoulder, разговор сидя/стоя/в движении, три и более участника.
- Establishing, master, geography, coverage, reaction, eyeline, cutaway, insert/detail и переходы крупности.
- Static posed/action frame, walk-and-talk, follow, leading shot, lateral tracking, reveal, pan/tilt с осмысленным start/end, push/pull, orbit при наблюдаемости.
- Блокинг по глубине, вход/выход, crossing, смена доминирующего героя, фокус на group, foreground occlusion и композиционный акцент.
- Коридор, небольшая комната, стол, дверной проём, лестница, улица, автомобиль/interior, crowded location, экстерьер день/ночь.
- Low-key/high-key, backlight/силуэт, practical lights, mixed light, daylight window, сложные skin tones, deliberate color и мягкая/жёсткая атмосфера.
- Намеренная асимметрия, неудобный look room, нарушение симметрии/осевого ожидания, handheld energy, slow/fast rhythm, false rule violations.

Сохраняй реальное visual evidence и unknown intent. Описание сюжета или намерения автора из твоего воображения не label. Не своди кино к дорогим, знаменитым, симметричным, идеально цветокорректированным кадрам. Нужны простые воспроизводимые задачи и разное качество постановки.

Фильмы и сериалы учитывать отдельно. Для сериала grouping: series/season/episode/scene/shot; не считать десять эпизодов одной серии десятью полностью независимыми стилями. Инди, короткий метр, учебные постановки и разные страны/эпохи нужны наряду со знакомым современным кино. CG/VFX/анимация могут быть отдельной веткой, но не подменять live-action.

### 8. Google Images, screenshots и другие источники

Владелец прямо просит реальные кадры из фильмов и сериалов, включая найденные через Google. **Ищи такой материал предметно и широко.** Не ограничивай corpus COCO или одним Tears of Steel из-за удобства существующих download paths.

Используй Google Images/web, официальные stills/scene excerpts/trailers, cinematography breakdowns, film-frame каталоги и доступные academic datasets. Ищи по названию произведения плюс конкретная постановочная задача/shot/motion, а также по задаче без популярного названия. Перейди на host page, отличи frame от publicity photo/poster/BTS/storyboard и сохрани upstream evidence.

Предпочитай настоящий frame/full-size still или extraction из доступного video исходника. Screenshot кадра может быть reference candidate при достаточном качестве; он не делает источник известным или устраняет compression/crop/права. Не используй screenshots страницы Google с UI, collages, actor headshots, вертикальные crops из widescreen, poster art вместо film frames. Не удаляй watermarks и не достраивай pixels так, будто они исходные.

Для screenshots фиксируй title/episode если подтверждены, source URL, способ получения, реальные dimensions, crop/bars/subtitles, screenshot/derivative origin и unknown timecode. Не выдумывай scene ID/timecode по узнаваемому лицу. Image-search thumbnail не является download original и не должен быть апскейлен ради quota.

Наличие кадра в Google не устанавливает разрешение любого использования. Не объявляй все screenshots незаконными и не объявляй их все cleared. Сохраняй конкретные source/use conditions. Широкий reference/research inventory с unknown rights не нужно заменять бедным permissive-only cinema sample. При получении/копировании учитывай применимые source terms и разрешённый use; недоступные или ограниченные записи оставляй в точном candidate ledger и ищи замену.

Отдельно учитывай исследование/просмотр, хранение копии, annotations, commercial model training, redistribution и показ кадров внутри продукта. Приватный Drive не устанавливает copyright clearance. Не обходи DRM, платный доступ, login restrictions, robots/rate restrictions или закрытый API. При проблеме с конкретным источником переходи к другому, не бросай cinema branch.

Это короткое условие управления происхождением, а не задание написать юридический трактат. Не обращайся к правообладателям и не совершай платные действия без моего разрешения. Unknown scope не переименовывать в CC/PD; research/NC данные не объявлять пригодными для любого paid use.

### 9. Начальные источники: проверь и получи пригодные поднаборы

Это исходные leads, не уже полученные v3 assets. Перепроверь доступ, версии, terms и фактическую task supervision; расширь список.

| Источник | Роль | Что проверить и не предполагать |
|---|---|---|
| [MovieShots](https://virtualfilmstudio.github.io/projects/eccv20shot/) | Movie shot scale и movement | Primary page: 46K shots из 7K trailers. Получи доступный task subset и native labels; отсутствие commercial grant не превращать в разрешение всех media uses. Montage trailer не даёт complete scene continuity |
| [MovieNet](https://movienet.github.io/) | Film/character/scene/style indexing, linked shots | Per-shot keyframes listed as 240p; не выдавать за high-resolution camera originals. Full movies excluded from basic download; metadata/annotations отдельно от media rights |
| [CineScale](https://cinescale.github.io/shotscale/) | Shot-scale reference | Research access/terms; сохранить native definitions и ограничения; не считать всё commercial-cleared |
| [SA-V](https://ai.meta.com/datasets/segment-anything-video/) | Video masks/masklets, identity/occlusion | Primary source: 51K videos/643K masklets, class-agnostic; не 643K независимых videos. Download form/terms требуют реальных данных; masklets не cinematic actions |
| [TUM VI](https://cvg.cit.tum.de/data/datasets/visual-inertial-dataset) | Synchronized imagery/IMU/pose | Batch access; проверить full-path vs start/end-only GT, calibration и data license. Sensor rig не iPhone, room motion не cinematic utility |
| [RealEstate10K](https://google.github.io/realestate10k/download.html) | Video URL/time/pose/intrinsics metadata | Metadata archive не доставленные videos и не grant video rights. Tour domain не диалог/actor blocking |
| [MOVi / Kubric](https://github.com/google-research/kubric/blob/main/challenges/movi/README.md) | Controlled synthetic camera/object motion, masks/depth/flow | Native synthetic physics/pose полезны; short low-res simple scenes не кино/live footage. Code license не автоматически data/assets license |
| [Blender film index](https://studio.blender.org/films/), [Tears of Steel](https://mango.blender.org/download/) | Open-film frames/clips и доступные производные | Film-specific attribution/terms и actor/publicity caveats, CG/VFX доля; расширение не может состоять из одного фильма |
| [LOC National Screening Room](https://www.loc.gov/collections/national-screening-room/about-this-collection/rights-and-access/), [Prelinger FAQ](https://archivesupport.zendesk.com/hc/en-us/articles/360004715031-Prelinger-Archive) | Item-specific real footage и historical movies | Не все архивы/копии одинаково reusable; историческая хроника не заменяет modern fiction/series |
| DAVIS/YouTube-VOS/other video segmentation/tracking sources | Дополнительный identity/occlusion coverage | Найди official page, фактические bytes/targets/use terms; не перечисляй названия без доступа |
| Official cinematography/film-school demonstrations и existing camera capture datasets | Beginner bridge, alternate setup, motion/settings | Проверить непрерывность, реальные changes и доступность video; generic instructional montage не ground truth |
| Contemporary film/TV official stills, scene excerpts, trailers и frame archives | Целевой reference diversity | Отличить publicity/BTS от final frame; known work ≠ known intent, доступность ≠ blanket license |

Не качай гигантский полный archive до small source sample: сначала проверь 10–20 frames/несколько clips на task usefulness и реальные доступные labels. Затем скачивай targeted shards. Не используй регистрацию/платность одного источника как оправдание остановки: seek alternative, preserve metadata lead и продолжай.

### 10. Репрезентативность live video — обязательное покрытие

В motion corpus должны быть реальные связные примеры минимум следующих **различимых причин изменения изображения**:

| Ситуация | Что требуется различать | Нужная evidence |
|---|---|---|
| Камера неподвижна, герой движется | Actor movement и compositional drift | Stable background/pose evidence, target track, actual/unknown tripod condition |
| Герой неподвижен, камера pan/tilt | Rotation и изменение проекции | Continuous source, scene/background trajectory; measured sensors если есть |
| Оператор идёт, герой неподвижен | Translation/parallax vs zoom/crop | Depth/parallax/pose evidence; нельзя только по bbox назначить метры |
| Камера следует за движущимся героем | Actor+camera mixed motion | Relative target motion, background motion, task and desired scale |
| Zoom/смена линзы/стабилизация | Control/display transform vs физическое перемещение | Actual control logs при наличии; otherwise uncertain visual category |
| Вход/выход/перекрытие цели | Visible/occluded/lost/reacquired, identity confidence | Timestamped entity/masklet, cut boundary, alternate identities |
| Pan/reveal до появления главного объекта | Intentional empty phase vs failed composition | Task/user-selected destination или verified context, start/end/dwell |
| Handheld deliberate motion | Style/energy vs unwanted shake | Conditional style/task annotation; нельзя запрещать всё дрожание |
| Склейка/резкая смена сцены | Reset/incomparable vs successful action | Shot boundaries, new context/identity scope |
| Два похожих героя пересекаются | ID switch vs same target | Linked IDs, occlusion/visibility, lost/ask cases |

Движение героя к краю может быть нормальной фазой. Desired framing зависит от времени и задачи, а не от одного постоянного center target. По одному клипу нельзя выдумать, почему двигалась камера. Если измерений нет, label `apparent_camera_motion` или `unknown` честнее metric pose.

### 11. Как именно готовить непрерывные видео

Получай source clips или достаточно длинные неизменённые фрагменты, сохраняй source refs/hashes и native timing. Один кадр и animated JPEG не считаются видеокорпусом. Reconstructed previews можно создавать из настоящей упорядоченной серии при подтверждённой timebase, с честной derivation.

Рабочие ориентиры длительности: несколько секунд для локального tracking/motion, примерно 5–20 секунд для start/motion/finish и 20–90 секунд для scene context. Это task budgets, не жёсткая universal норма; длинный static shot может быть полезен, короткая action phase — тоже. Не доставляй только секунду, если выбранная задача требует начала и конца движения.

Сохрани:

- Source duration, stream/fps/timebase, actual PTS, frame index mapping, original dimensions/aspect, rotation, codec/bit depth/color metadata при наличии.
- Source start/end и shot cut intervals; extraction/transcode parameters, resized/cropped proxy lineage и связь с сохранённым source segment.
- Entities/track IDs в пределах clip/scene, visibility/occlusion/truncation states, known/unknown identity связи через cut.
- Camera movement labels по temporal intervals, direction conventions, measured/inferred/apparent origin, certainty и ambiguous mixed motion.
- Task/intent context отдельно от автоматического recognition label; moments at which action is useful/obsolete/unsafe/unknown.
- Technical/context transitions: focus/brightness variation, lens/zoom/cut, camera-motion start/stop и target entry/exit.

Для VFR не назначай `timestamp=index/fps` по среднему контейнерному fps. Не ресемплируй быстрое движение до 1 fps и потом не заявляй smoothness supervision. Keyframes полезны для аннотирования крупности, но не заменяют последовательность для velocity/jitter/occlusion. Training sampling описывается отдельно от archival native video.

Предпочтительны доступные source segments около 1080p с native fps; 720p и более низкие native данные допустимы для задач, где полезная evidence сохраняется. Не апскейль ради порога. Для fine technical labels нужен отдельно подтверждённый native quality/reference.

### 12. Scene packs фильмов и сериалов

Scene pack должен быть связной единицей одного произведения/эпизода/сцены с несколькими реальными планами и source order/context. Два визуально похожих кадра из разных фильмов никогда не образуют восьмёрку.

Для диалога, например, сохранить master/two-shot, OTS/single одного участника, обратный план, reaction/insert при наличии. Не требуй именно такую схему от каждого автора; annotate фактическую coverage и отсутствующий контекст.

Поля: work/episode/scene/shot IDs, source cut/time refs, participant pseudonymous IDs в scene scope, coarse roles, shot scale/angle, visible eyelines/screen direction, known/unknown geography, reference previous shots и continuity evidence. Celebrity identity не требуется для tracker; нейтральные P1/P2 достаточны.

Нарушение «правила 180°», continuity jump или strange look room не объявляется художественной ошибкой без context. Не восстанавливай физическую camera geography уверенно по одной OTS-картинке. Camera diagram может быть qualitative hypothesis с uncertainty; metric coordinates только с measured evidence.

Trailer montage может дать source shots, но не подтверждённую последовательность оригинальной сцены. Хронологический order трейлера и order сцены хранить отдельно.

### 13. Раздели обучение разных компонентов

Объясни и подготовь конкретный data route для каждого:

| Компонент | Какие входы возможны в runtime | Что составляет supervised target |
|---|---|---|
| Frame detector/segmenter | Текущий frame/target input | Objects/masks/classes/visible extent |
| Tracker | Текущие и прошлые frames/features, selected target state | Identity/masklet/visibility/loss/reacquisition |
| Camera-motion estimator | Frames, calibration, optionally IMU/control readback | Apparent motion type либо measured pose/rotation с units/quality |
| Temporal task assessor | History ≤t, task, target trajectory, known camera state | Task deviation/phase/quality over interval, confidence/unknown |
| Planner | Current/past evidence, intent, allowed changes, active action | Conditional useful action/preserve/ask/abstain, preconditions и rationale |
| Visual proposal/renderer | Current geometry/state/transforms | Grounded recipient/desired region/direction, overlay validity; UI drawing не learnable magic |
| Verifier | Baseline, prescribed action и subsequent observations | Action performed, task outcome, comparability; artistic utility отдельно |

Не предполагай необходимость заново обучать detector на 1270 COCO images, если pretrained baseline уже лучше. Сравни narrow adaptation и reuse; dataset должен проверять cinematic/mobile domain gap. Native object labels можно применять многократно как auxiliary, но нельзя подсчитать их как 9352 полезных советов.

Исследуй компактную temporal модель на последовательности features, local vision+geometry/state machine и sparse VLM/planner. Большой video transformer/VLM может быть offline teacher или редкий slow path. Выбор зависит от evidence, доступных runtime inputs и phone constraints, а не желания иметь одну нейросеть.

Проспективный plan включает sample representations, labels/loss masks, actual loader, evaluation method, runtime consumer и data gaps. Код обучения/fit не запускать в этом задании без дополнительного поручения.

При доступе к repo прочитай AGENTS/README и минимально нужные contracts/owners, не весь проект:

```text
ml/camera_coach/contracts/camera_production_heads_v1.md
ml/camera_coach/contracts/camera_release_label_v1.md и .schema.json
ml/camera_coach/contracts/camera_release_capability_mapping_v1.md
ml/camera_coach/contracts/set_composition_net_v2.json
ml/camera_coach/production_heads.py
docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md
docs/cameraanalysis/03-domain-contracts.md
docs/implementation/PRODUCTION_ACCEPTANCE.md
shafinMultitool/Multitool2Module/Models/CameraAnalysis/ActionVerifier.swift
shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift
```

Сверь фактический case каталога и shipped/proposed/research состояния. V1 production heads trainer принимает feature vectors, image-v2 описывает одиночные image/ROI inputs; наличие scalar motion features не делает его video-sequence trainer. Нынешний temporal scorer deferred (ML-011), поэтому новую temporal supervision/design описывать отдельно с будущим adapter/consumer. Current verifier и frame categories не доказывают поддержку произвольной траектории/восьмёрки. Зафиксируй минимальную необходимую интеграцию без изменения текущих records/контрактов в этом acquisition заказе.

### 14. Causal online processing и отсутствие утечки будущего

Live advice в момент t использует только информацию, реально доступную к t: текущий и прошлые frames, выбранную задачу/target, доступные sensors/controls и прошлые планы. Input window например 0.5–4 секунды — hyperparameter для исследования, не обязательный формат всех sources.

Future frames, после-действия metrics, final annotated verdict, clip filename с ответом и human rationale не подаются как runtime features planner. Offline annotator может смотреть весь clip для labels, но это привилегированная информация; runtime evaluation должна быть causal и учитывать label origin. Bidirectional/video model с future context не выдавать за live performance без проверки past-only режима.

Verifier после действия может использовать after observations согласно отдельной задаче. Это не делает after доступным модели, которая предлагает действие до него.

Оценка должна воспроизводить incoming stream: start without whole clip, timestamped states, delays, lost target, action revision/expiry. Не ограничивай evaluation shuffle-independent frames. Keyframe accuracy и online stability — разные результаты.

### 15. Что должна хранить temporal разметка

Спроектируй versioned proposed schema, не выдавай её за уже существующую production schema. Минимальный смысл:

```text
clip_id, source_asset_id, work/scene/shot/group refs, clip hash
frame/timebase/PTS mapping, frame_id, transform version
entity_id, track_id, visible geometry, representation kind
visibility, occlusion/truncation, target validity, identity uncertainty
camera motion interval/type/direction/origin, measured pose refs if any
subject motion interval/type, camera-vs-subject ambiguity
task_id, desired framing or qualitative goal, intent origin
active proposal_id, recipient, preconditions, valid_from/updated/expired times
planned action vs observed action, evidence refs, comparability reasons
task outcome vs visual preference, annotation provenance, review state
```

Поля могут быть nullable/masked по задаче. Не делай обязательной неизвестную дату съёмки. В relative time должны быть реальные evidence и порядок; publication/retrieval/capture time различаются. Данные без IMU пригодны некоторым video tasks; отсутствие sensors не превращается в dummy sensor zeros с known mask.

Mask — exact/silver/native по происхождению; bbox не contour. Frame-level geometry имеет transforms от source к proxy/model/preview. Image xy left/right не physical camera vector. Mirrored selfie, screen rotation, crop/letterbox, stabilization и lens switch отражаются в coordinate conventions.

Unknown identity через склейку не связывай автоматически; track lifetime и scene identity — разные scopes. Lost target скрывает конкретную arrow; reacquisition требует evidence либо нового выбора. Два похожих лица не повод уверенно продолжать старый target.

### 16. Conditional coaching annotations — автоматически, но без фальшивого gold

Нужен содержательный машинный первый проход по целевому кино/видеоматериалу. Не оставляй весь corpus без task/scene/proposal tags только потому, что human reviewer пока отсутствует. Используй доступные pretrained models, video/frame inspection и структурированные VLM proposals для **silver/weak** labels.

Для каждого curated example дай: что реально видно; available/unknown context; условную задачу; target; keep/correct/ask/abstain; полезное действие если обосновано; что можно показать; предпосылки и альтернативы; почему ничего не советовать; что невозможно доказать из source. Заданный annotation task — условие эксперимента, а не историческое намерение режиссёра.

Для видео добавь интервалы изменения состояния: нормальная фаза, временное отклонение, устойчивое отклонение, корректирующее действие как proposal, отмена/потеря/невозможность сравнить. Посмотри связную последовательность, не сгенерируй текст только по source filename.

Автоматические flags получают model/tool/version/prompt, frame/clip refs, evidence snippets и confidence; confidence — не accuracy. Отделяй recognition proposal от verified native target. Второй model pass помогает найти ошибки, но не создаёт independent human gold. Нет человека — `human_gold=false`.

Для готового хорошего киношного плана preserve/style — содержательная метка. Не выдумывай дефект ради corrective quota. Чтобы получить correction training, ищи настоящие учебные неудачные setup/takes, допустимые alternatives и контролируемые случаи. Машинный counterfactual можно сохранить отдельно; он не executed action.

Не считать все unselected actions отрицательными. При явной альтернативной оценке сохрани why/helpful/harmful/unknown по конкретной задаче. Risk/delta/actual outcome не появятся от произвольного текста «перемести правее».

### 17. Реальные действия, траектории и технические серии

Сначала ищи доступные existing public/authorized datasets и footage: synchronized poses/IMU; camera movement before/after; physical setup variations; focus/exposure/WB series с known settings; demonstrations с показанным действием. Проверь continuous evidence, контекст и реальные measurements. Не назначай proprietary iPhone telemetry generic camera rig.

В intervention episode разделяй:

1. Задача и исходный stable interval.
2. Prescribed/proposed action и допустимость/target.
3. Фактически выполненное действие с measurement либо визуально установленной ограниченной evidence.
4. Subsequent interval, сопоставимость target/context/lens.
5. Objective task change.
6. Conditional artistic preference, её origin и uncertainty.

Камера двигалась вправо ≠ команда выполнена корректно ≠ кадр стал лучше. Actor moved одновременно с камерой — confound. Изменился свет/фокус/постобработка — отдельная причина. Cut, target swap или lens switch могут делать comparison incomparable.

Не требуй численного Kelvin без reference/metadata. Finished movie color grade — style, а не neutral-WB truth. Exposure/focus/privacy/permitted move/available light context нужны только тем outputs, которые действительно их используют. Применение camera control возможно лишь при actual device capabilities/readback.

Если достоверных real episodes мало, не останавливай сбор B/D/A. Доставь всё найденное, точные counts и minimal remaining evidence. Отдельная owner-device validation неизбежна для claims о конкретном iPhone: её нельзя провести скачиванием фильма. Не выдавай это ограничение за недостаток binary acquisition всего корпуса.

### 18. Автоматическая контролируемая синтетика

Если tools позволяют, используй существующие разрешённые synthetic data или сделай обоснованный небольшой render pipeline с точными camera/object state и известной целью. Это способ автономно закрыть controlled geometry/some policy supervision, не замена всему real-video domain.

Различай:

- 2D crop/translation/brightness по still: полезны для coordinate mapping и некоторых framing probes; нет нового parallax/реальной геометрии/AF.
- 3D physically consistent render: можно знать camera pose, object motion, occlusion/depth, before/action/after; всё равно synthetic domain и заданная utility proxy.
- Generative video/edit: может дать reference/augmentation, но не доказанные measurements или physically executed correction.

Нужны origin/generator/version/seed/assets/parameters, source license, trajectory, target/goal, transforms и known limitations. Positive/negative/no-action/wrong-direction cases должны следовать контролируемому заданию, а не произвольной эстетической оценке того же генератора.

Синтетические исходники/варианты одного setup держи одной split group. Не создавать random near-duplicate thousands ради размера. Не использовать внешний paid generation API без разрешения. Если render tools недоступны, получи подходящие существующие native synthetic sequences, а не выдумывай render completion.

### 19. Устойчивость подсказок и temporal failure curriculum

Сформируй связную выборку, на которой потом можно проверить:

- Предложение сохраняет адресата при движении, фоновых похожих лицах и crossing.
- Контур/стрелка следуют текущей геометрии; не остаются на старой координате и не переключают target.
- Временное отклонение при reveal/follow не вызывает ненужный новый совет каждый frame.
- Persistent deviation может дать один совет с evidence, не бесконечную последовательность противоречащих directions.
- Advice suppression при target lost, cuts, изменившемся intent/lens/permission, stale geometry и перегрузке evidence.
- Reacquisition не принимается за success старого action без подходящей проверки.
- Desired framing и физическое движение имеют разных recipients и units.
- Reversing/overshoot/wrong-direction/no-action, intentional handheld, style и ambiguous background change представлены отдельно.
- Изменение света/focus во время движения не маскируется под geometric improvement.
- During-recording quiet mode vs prep/pause guidance обоснованы пользовательской задачей.

Дай sampling labels и future evaluation metrics: identity switches/lost recovery, geometry jitter, wrong-recipient advice, stale-overlay time, unnecessary advice changes, time-to-useful-advice, false-success и comparability errors. Пороги сначала предложенные; не придумывай измеренные значения и не назначай все user benefits proxy metrics.

### 20. Рабочий объём и приоритеты приобретения

Количество — бюджет последовательных волн, не научно доказанный минимум для обучения. Все цели считать в **независимых источниках/планах/сценах**, плюс actual seconds/videos и available supervision. Не компенсировать недобор film/TV сотнями соседних frames или COCO.

**Первый целевой пакет, который нужно реально получить прежде массовой выгрузки:**

- 100 содержательных still/keyframe examples: ориентир 60 film/TV, 30 mobile/beginner bridge, 10 hard/unknown/style cases. Не меньше примерно 15 разных works в cinema части, включая series examples при доступности. Один кадр может иметь несколько coverage tags.
- 30–50 полезных continuous video units из разных сцен/источников: tracking, camera-only, actor-only, mixed movement, pan/tilt/reveal и loss/cut controls. Включить и кино, и live/beginner video. Длительность/task evidence важнее жёсткого числа.
- 10 связных scene packs, несколько dialogue/reverse-context и несколько других постановочных задач.
- Небольшой native-supervised tracking/motion subset с реально полученными masklets/pose refs, пригодный для подготовки training batches.

Это internal acquisition checkpoint, не просьба ждать моей разметки. Сделай pixel/sequence review, исправь selection и продолжай самостоятельно.

**Основная следующая волна — исходный ориентир, который можно обоснованно уточнить после pilot:**

| Lane | Желаемый бюджет | Anti-padding ограничение |
|---|---|---|
| Cinema core | 800–1500 разнообразных useful shot/keyframe units из порядка 40–60 works; фильмы и серии отдельно, современный live-action представлен | Не больше примерно 5% effective core одного work; соседние почти одинаковые frames не новые shots |
| Live video core | 120–200 полезных continuous clips с несколькими motion/target-change states; movie/TV и beginner domain | Два окна одного source не два независимых films; raw frames не episodes |
| Linked scene packs | 40–80 связных scene units нескольких works и условий | Один pair без промежуточного context не complete coverage |
| Beginner/mobile bridge | 300–600 useful stills/alternatives и 40–80 real video units, по фактическому доступу | Не переименовать COCO фото в smartphone filming |
| Native tracking/motion auxiliary | Targeted diverse subsets по masks/pose/IMU tasks | Report independent clips/masklets/duration, source labels и domain gap отдельно |
| Coaching proposals | Содержательная автоматическая разметка всего curated pilot/core по доступным tasks | Не превращать proposal в human-gold и generic caption в operator advice |
| Technical/intervention evidence | Получить все обоснованно полезные доступные targeted series/episodes; начальный pilot 20–40 при наличии | Не выполнять quota фиктивными controls или парой unrelated frames |
| Controlled synthetic | Небольшое varied controlled coverage по доказанным gaps | Отдельные counts; не заменяет реальный camera loop |

Общий candidate pool может быть шире curated core (например, 2000–4000 frames), но найденное/скачанное/просмотренное/принятое считай отдельно. Окончательные размеры зависят от доступа, task validity, полезности и ресурсов. Не писать «done» только потому, что achieved image count.

Если большой источник даёт 100GB, сначала выдели нужный subset/stream/shard; не потребляй весь budget бессмысленным bulk. Регулярно показывай реальный progress по lanes и какие holes закрыты. Если ограничение мешает desired budget, ищи другой источник и доставляй остаток; final статус честно отражает неполноту.

### 21. Quality, разнообразие и защита намеренного стиля

Ищи обычные постановочные задачи, разные люди/skin tones/одежда/рост, количество участников, помещения/экстерьеры, день/ночь, scale/aspect/angles, камерные диалоги и движение. Без вывода чувствительных/личных свойств людей из изображения. Demographic annotation для качества ограничивать наблюдаемыми релевантными признаками и допустимым источником.

Не фильтруй все blurry/dark/noisy/occluded shots как мусор: некоторые нужны для defect/abstention. Separate unusable decode/source failure и учебный дефект. Хороший intentional style — protected example; high aesthetic score не universal verdict.

Резкость/compression/noise/WB оценивать на достаточном native resolution, а temporal smoothness — в связанном clip с реальным timing. Source grade/HDR/SDR/subtitles/bars/frames с водяными знаками помечать. Letterbox не считать scene clutter; canonical full image и active picture region сохранять отдельно, с transforms.

Не применять beautification/AI upscale/color correction ко всем исходникам перед review. Raw bytes сохраняются неизменными; derivatives имеют lineage. Низкое разрешение movie benchmark может быть полезно scale recognition и бесполезно fine technical analysis одновременно.

### 22. Дедупликация, source grouping и честный split

V2 сохраняется как immutable predecessor. Новые additions имеют dataset/run/source versions и relation to v2. Не переписывай старые evidence/hashes/исторические records для удобства новой схемы.

Exact SHA, decoded-pixel duplicates, near duplicates, crops/resizes, film frames из разных сайтов и source-video overlaps объединять через parent/derivation/work/scene/shot identities. Perceptual similarity — proposal, спорные пары проверить; совпадающий actor не same scene.

Split границы определяются задачей: whole scene/video/episode and derivatives никогда не делить по соседним frames. Для cinematic generalization группировать по work, series/franchise/style/source dependencies с явным policy. При необходимости несколько split protocols, но не оценивать work-generalization на frames знакомой train сцены.

COCO и popular film data могут быть известны pretrained models. Назвать это honest reference/regression layer; не обещать unseen релизную метрику только по zero exact overlaps. Создай reserve candidate pool для будущего отдельного review, не выдавая его за locked human-gold. Если reviewer/teacher уже использовал sample для исправлений, это development/regression, не pristine test.

Calibration не равно confidence от VLM. Для gold нужны реальные независимые human reviews и separate frozen procedure. В этой автоматической задаче подготовь данные/инструмент и сохрани статус pending, не выдумывай людей/IDs.

### 23. Viewers и очередь владельца

Не предлагай мне начинать с нынешних 250 COCO frames. Доставь новую **первую сотню целевых примеров** и отдельную небольшую video queue (например, 10–20 наиболее полезных units с temporal tasks). В дальнейшем curated queue можно расширить до 200–300 после feedback.

Сохрани original words свободного объяснения плюс typed labels/proposals отдельно. Short instructions должны объяснять goal/target/intent/allowed moves/preserve/correct/ask/unknown, action recipient, visual geometry и limits single frame vs video. Date still optional.

Нужен реально работающий способ смотреть клипы с таймлайном и связанными frame IDs. Предпочитай простое расширение существующего annotation flow в отдельной v3 version или portable HTML/JSONL workflow. Не строить сложную новую платформу вместо corpus. Интерфейс должен показывать actual downloaded media, позволять start/stop/seek, target/time interval, scene relations и экспорт переносимого результата. Не прикладывать красивый screenshot без usable files.

Для temporal review показать последовательность/скорость, selected target, предложенный motion type, event intervals и unknowns. Если masks/tracks отсутствуют, не рисовать oracle contour как verified. Text/video annotations не могут теряться из-за only-localStorage; portable JSONL export/import и asset refs обязательны.

Не добавляй обучение viewer пользователя как условие продолжения сбора. Ты сам проводишь первый машинный проход и QA. Моя дальнейшая экспертная разметка улучшает gold/utility, но не заменяет твою текущую обязанность получить raw/native/weak data.

### 24. Примеры полного workflow, которые ты должен подготовить

Выбери минимум 10–15 разных **фактически полученных** examples/short clips и разверни chain:

`контекст/задача → доступные inputs до момента t → что известно/unknown → target → полезное предложение или preserve → что рисовать → что меняется во времени → отмена/проверка → dataset targets и provenance`.

Обязательно включи:

1. Static camera vs actor crossing с похожим composition snapshot.
2. Follow героя с временным подходом к краю; distinction transient/persistent drift.
3. Pan/reveal, где вначале target отсутствует намеренно.
4. Tilt или camera height adjustment с различием image projection/physical action.
5. Dialogue/OTS с контекстом обратного плана и unknown geography case.
6. Multi-person crossing/occlusion, где нужно скрыть совет или переспросить.
7. Person/prop motion proposal с permissions unknown vs заданное разрешение.
8. Low-key/силуэт/смешанный цвет, где preserve лучше технического «исправления».
9. Focus/exposure/control case с фактическими measurements либо honest absence.
10. Cut/lens/target change, который инвалидирует сравнение.
11. Wrong-direction/no-action/overshoot case реальный либо явно synthetic.
12. Good film shot, который полезен как reference, но не supervision correction.

Не ищи одной волшебной картинки для каждого пункта. Temporal примеры должны иметь frames/times/source связи; схемы и контрфактические arrows могут быть proposals, а не наблюдённые after states. Если необходимый пример не удалось получить, отметь точный missing evidence и добывай альтернативу.

### 25. Структура результата и машинные manifests

Организация может адаптироваться к tools, но все связи и состояния должны сохраниться:

```text
CameraCoach_Dataset_v3_<date>_<run_id>/
  START_HERE_RU.md
  completion_by_capability.csv
  DATASET_COUNTS.json
  product_and_video_workflows.md
  capability_catalog.csv
  capability_data_acceptance.csv
  training_routes_and_runtime_inputs.md
  baseline_claims_verified_corrected.md
  source_inventory.csv
  manifests/
    works.jsonl
    assets.jsonl
    videos.jsonl
    shots.jsonl
    frames.jsonl
    scene_packs.jsonl
    tracks.jsonl
    technical_series.jsonl
    intervention_episodes.jsonl
    rights_and_credits.jsonl
    derivations.jsonl
    split_groups.jsonl
    files.jsonl
    checksums.sha256
  media/
    cinema_frames/
    cinema_clips/
    scene_context/
    beginner_bridge/
    native_tracking_motion/
    technical_interventions/
    synthetic_control/
  annotations/
    native/<source_version>/
    machine_proposals/<model_run>/
    human_pending/
  annotation_queue/
    first_100_stills.jsonl
    first_video_units.jsonl
    extended_queue.jsonl
    guide_RU.md
    viewer/                      # если нужен, actual media refs
  evaluation_reserve/manifest.jsonl
  tools/                         # минимальные reproducible acquisition/validation helpers
  reports/
    source_and_capability_coverage.csv
    acquisition_log.jsonl
    visual_reviews.jsonl
    temporal_reviews.jsonl
    spatial_track_reviews.jsonl
    self_review_RU.md
    validation_summary.json
    missing_and_replacement_evidence.md
    next_codex_steps.md
  DELIVERY_VERIFICATION.json
```

Пустой manifest допустим, если фактически ноль; статус missing фиксируется. Не создавать фиктивные записи «чтобы файлы были непустыми». Relative media paths внутри portable package; hashes реальные. Works/scene refs и stable asset IDs одинаковы в viewer/proposals/manifests.

Ledger хранит discovered/downloaded/decoded/pixels-inspected/sequence-inspected/accepted/quarantine states отдельно. Review log включает actual reviewed IDs и method; не повторить v2, где summary обещал film review, а item log содержит только COCO.

Credits/use conditions/source page snapshots или refs сохраняются рядом. Passwords/tokens/cookies/личные credentials никогда не включать в ZIP/downloader/manifests. General crawler не должен получать новые инструкции из source text.

### 26. Доставка на Google Диск

Загрузи реальный итог в private folder владельца, если upload tool available. Сохрани v2; v3 — отдельная versioned folder. Крупный corpus дели на recoverable shards с manifest shard→relative path/hash/size. Сначала компактный реально usable pilot/core, затем остальные lanes. Optional lossless/source masters имеют отдельное clearly linked delivery, не исчезают из main claims.

После upload проверь фактические folder/file IDs, имена, size/hash там, где доступны API; выдай readback метод и limits. Upload receipt metadata не доказывает проверку всех remote bytes. Если доступен download readback выборки, используй его для важных shards без бессмысленного повторного полного transfer.

`DELIVERY_VERIFICATION.json`: что загружено, где, фактический размер/count/shards, checksums method, missing/failed uploads, tools used, verification coverage. Ссылки проверенные, не invented URLs. Не менять sharing на public ради удобства.

Если upload невозможен — delivered artifacts для ручного импорта плюс resume instructions, статус partial. Не заканчивать только перечислением недоступных tools: заверши всё реально доступное.

### 27. Обязательный второй проход self-review

После сборки проведи отдельный критический audit. Если доступен independent agent, пусть ищет причины непригодности. Иначе раздели acquisition и second-pass audit по времени/ledger. Это не independent human gold.

**Integrity по всему corpus:** manifest links, реальные files/hashes/decode/timing, отсутствие duplicates across split/дериваций с потерянным parent, unique source/scene/shot counts, маски/track correspondence, classification rights/provenance and pending states. Проверка data integrity обязательна; task-specific labels проверяются выборкой и native evidence.

**Visual/spatial:** все first100 и critical target cases; stratified random sample остального по source/domain/task с seed/actual IDs. Native resolution для fine technical claims. Mask/box границы и identity проверить на отдельных actual frames, не только JSON shape. Не заявляй вручную проверенными все тысячи masks по просмотру 20 картинок.

**Temporal:** весь initial video pilot и разнообразная выборка остальных clips как видео или достаточно плотная ordered sequence. Сохранить inspected intervals/method/sampling rate. Thumbnail start/end не считается проверкой smoothness, ID stability или missed cuts. Native verified measurement refs сравнить с time synchronization и known GT coverage.

**Task completeness:** по каждой priority capability показать, имеются ли raw, достаточный временной/сценический контекст, native/weak labels, target grounding, actual-action evidence и valid training route. «Есть video» не закрывает весь row.

**Cinema diversity:** количество real film/series/short/indie works, independent scenes/shots, contemporary/archival/live-action/CG, distribution actors/locations/scales/motions/styles. Is one film dominating? TV реально скачано или только discovery URLs? Are references frames rather than posters/BTS?

**Live validity:** causal input availability, camera-vs-subject ambiguity, motion windows long enough, target loss/cut/lens reset, false corrections intentional motions, distinction выполнено/полезно/достигнуто/несопоставимо.

**Honesty:** machine proposals не gold; synthetic не physical; filenames/images не settings; reconstruction не source-camera clip; count masklets не videos; own model agreement не measured accuracy. Human review UI не human review result.

Исправь найденные нарушения и пересчитай metrics. Запиши found/fixed/unresolved, IDs и verification limits. Не оставляй известный wrong-source кадр в approved core ради quota. Сравни результат с v2 содержательно: кино/видео coverage, supervision и реальная пригодность, а не только image count.

### 28. Stop conditions и итоговый ответ

Ты должен довести задачу до actual collection/organization/automatic first-pass/QA/delivery по всем доступным веткам. Не останавливайся после source research, плана, prompt generation, одного открытого фильма или создания очереди без медиа. Если внешнее ограничение непреодолимо, выполнены все независимые части, сохранена resume evidence и final статус отражает конкретный blocker.

Нельзя честно объявить абсолютно всё готовым для любой будущей модели, когда ещё не определён output scope и нет validated utility labels. Вместо этой фразы дай **полноту по матрице выбранных возможностей** и фактически достигнутую maturity каждой части. Большой автоматически собранный native/weak корпус может быть полезен, даже если human utility verification и iPhone measurements ещё предстоят.

Начни финальный ответ с real Drive/attachment links и фактического delivery status. Затем:

1. Что изменено относительно v2 и какие её shortcomings закрыты.
2. Фактические counts: кино/сериальные works, независимые scenes/shots, stills, clips, duration, masks/masklets/tracks, measured pose/IMU series, real interventions, controlled synthetic; все разные единицы отдельно.
3. Что именно теперь можно обучать/оценивать, на каких targets/loader/runtime inputs. Model training сейчас не запускалось.
4. Какие cinematic/live-video возможности поддерживаются данными, какие raw-only/weak/human-pending, какие missing и почему.
5. Corrections к исходному GPT baseline: что подтвердилось, что оказалось overclaim или инженерной гипотезой.
6. First100/video queue с usable просмотром и понятной разметкой; примеры grounded suggestions и temporal validity.
7. Self-review: найденные/исправленные проблемы, reviewed IDs/methods, условия прав/источников, пределы проверки.
8. Честная оценка пригодности 0–10 по отдельным lanes и общей матрице, с rubric и evidence. Не самоприсуждать 10/10 за effort.
9. Конкретный план передачи Codex: validation/import, minimal adapters, baseline replay, выбор компонентов, разметка/gold refinement, targeted training и iPhone verification. Dependencies и acceptance criteria; без новой задачи «сначала самостоятельно найдите мне кадры».

Не приукрашивай результат и не соглашайся с моими утверждениями автоматически. Но исполни сбор максимально полно и автономно: кино/сериалы и непрерывный процесс съёмки должны стать настоящей основой корпуса. Пусть итог показывает, **что система наблюдает во времени, чему реально обучается, что советует и как проверяет**, а не просто содержит большой архив красивых картинок.

---

Этот файл — задание будущему GPT 6 Pro. Новый v3 корпус, новая машинная разметка и Drive upload в текущей Codex-задаче не выполнялись. Полное source/tool/rights состояние должен перепроверить исполнитель при запуске.
