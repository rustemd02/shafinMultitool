# CameraCoach_Dataset_v2 — пригодность для визуального видеоассистента

Дата: 2026-10-11. Read-only аудит локального пакета, просмотр изображений и проверка источников. Датасет, разметка, код приложения и модели не изменялись; обучение не проводилось.

Источник: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/CameraCoach_Dataset_v2/`. Полученный от GPT Pro текст о недостатках рассматривается как baseline-гипотеза, а не инструкция и не автоматически истинное заключение.

## Оценка: 3/10 для нашей цели

Это инженерная оценка пригодности **нынешнего входного корпуса для подготовки живого киноассистента**, не измеренная accuracy и не прогноз качества будущей модели. Корпус имеет полезную инфраструктуру и реальные объектные маски, но содержит очень мало целевого кино/видеоконтекста и не содержит supervision для операторских советов.

| Критерий | Вес | Балл | Основание |
|---|---:|---:|---|
| Представительность для кино/сериалов и начинающего оператора | 25% | 2/10 | 1270 COCO-фото и только один фильм; нет полноценного кино/сериального ядра и мобильного видеодомена |
| Полезность входов для разметки советов | 25% | 2/10 | Можно начать conditional still review, но очередь сформирована по геометрии объектов; связанных попыток и temporal task context почти нет |
| Пространственная локализация | 15% | 6/10 | 9352 source-native object regions с масками; мало разрешение, нет киношного grounding и выбранного operator target |
| Временная структура и движение | 15% | 1/10 | Два секундных окна, ноль проверенных tracks, motion labels и intervention episodes |
| Технические рекомендации и проверка результата | 10% | 1/10 | Нет applied controls/IMU/reference WB и causal outcomes |
| Целостность, документация и воспроизводимость доставки | 10% | 7/10 | Основные bytes/ссылки/hashes согласованы; ограничения честно названы. Upstream authenticity, часть происхождения, отдельные masters и авторы не подтверждены |

Взвешенно 2.85/10, округлённо **3/10**. Для отдельной auxiliary-задачи статичного object grounding — приблизительно **6/10**; это иной критерий. Оценка независимого Luna reviewer была строже: 2/10 для обучения полного live assistant. Разница не меняет решения: не тратить всю первую сотню экспертной разметки на нынешнюю очередь.

## Что фактически доставлено

| Единица | Число / состояние | Evidence внутри пакета |
|---|---|---|
| Primary images | 1318 | `DATASET_COUNTS.json`, `manifests/assets.jsonl` |
| COCO2017 val photographs | 1270; 96.36% всех image assets | `assets.jsonl`: `source_family=coco2017`, `source_domain=Flickr_web_photo` |
| COCO фото с native labels | 1256; 14 без labels | `DATASET_COUNTS.json`, `annotations/native/instances_all.json` |
| Object regions / convenience masks | 9352; 9246 noncrowd instances + 106 crowd regions | `DATASET_COUNTS.json`, `manifests/masks.jsonl` |
| Кинокадры | 48; 3.64% image assets; один фильм Tears of Steel | `assets.jsonl`, `clips.jsonl` |
| Видео | 2 reconstructed MP4 previews по 24 кадра при declared 24 fps | `clips.jsonl`: `tos_08400_08423`, `tos_08640_08663` |
| Сериалы | В source manifests отсутствуют | Все temporal записи относятся к одному фильму |
| Связанные scene packs | 1 candidate на двух кадрах; 0 полноценно размеченных | `scene_packs.jsonl`: `actual_fully_annotated_scene_pack=false` |
| Реальные action episodes | 0 | `episodes.jsonl` пуст; counts/matrix |
| Проверенные temporal instance tracks | 0 | Counts; capability matrix |
| Actual control capture series | 0 | Counts; capability matrix |
| Human Coach labels | 0 | Counts; все поля queue pending |
| Первая очередь | 250 COCO-фото, 0 кинокадров; 184 train / 44 calibration / 22 development | `annotation_queue/queue.jsonl` |
| Evaluation reserve | 300 COCO-фото; отсутствуют в обычной очереди | Queue/splits; `unseen_benchmark=false` |

Окно из 24 кадров соответствует одной секунде при заявленной timebase; PTS последнего кадра 23/24 ≈ 0.9583 секунды. Нативный fps полного исходного фильма отдельно не измерен. Между `tos_08405` и `tos_08406` видна склейка. Киношная часть даёт примерно три наблюдаемых плана, а не 48 независимых съёмочных ситуаций. Все окна одного фильма правильно объединены в один split group.

PNG masters — alternate representations тех же кадров. В предоставленной **папке** их нет: manifest относит 48 PNG и два companion files к отдельному lossless archive. Это граница проверенной доставки, а не доказательство, что соседний архив никогда не был доставлен. В основной папке JPEG views и previews присутствуют.

## Главные недостатки по существу

### 1. Сбор смещён к удобной native supervision

COCO даёт bbox/masks/classes, которые проще организовать, чем киноязык и траектории. Поэтому сборщик фактически подготовил auxiliary detection/segmentation корпус. Он сам это честно признаёт в `START_HERE_RU.md` и `reports/AUDIT_RU.md`. Нельзя считать честность описания выполнением первоначальной продуктовой задачи.

Категория `multi_person` основана на числе native person regions. На просмотренных листах встречаются транспорт с маленькими прохожими, спорт, групповые фото, предметы с изображёнными людьми. Это не label диалога, блокинга или восьмёрки. Есть полезные отдельные кадры, но bucket не обеспечивает целевой отбор.

Первые восемь кадров очереди — встречи/кафе, семейный кадр, еда, выставка, дети с устройствами; несколько хорошо подходят для выбора цели и неоднозначной композиции, но не заменяют репрезентативный набор постановочных сцен.

### 2. Киношная часть номинальна

Один live-action/VFX фильм, два кратких окна, без serial scenes, альтернативных ракурсов и широкого распределения стилей/крупностей. Один предполагаемый scene pack содержит только `tos_08400` и `tos_08640`, интервал между ними не включён. По нему нельзя проверить всю географию диалога или монтажную связность.

Фильмы и сериалы нужны как источники читаемых решений композиции, блокинга, крупности, света и последовательностей. Однако готовый профессиональный кадр — выбранный и обычно обработанный результат. Он не является автоматически положительной меткой действия и не показывает все ошибки начинающего оператора. Нужна связь с мобильными/учебными video inputs, ошибками, намеренным стилем и допустимыми действиями.

### 3. Процесс съёмки не представлен

Нет полноценной temporal supervision для устойчивого target ID, masklets, camera/subject motion, появления/потери цели, ошибочного восстановления, jitter и актуальности подсказок. 48 unlabeled frames не дают такой выборки. Наличие двух MP4 не меняет этот вывод.

Один и тот же край кадра может означать ошибку статичного плана, начало намеренного pan/reveal, actor crossing или временную фазу follow. Live planner должен различать это по прошлым наблюдениям и задаче; нельзя учить его независимым verdict каждого JPEG.

### 4. Локализация не равна операторскому совету

9352 instance regions не говорят, кто выбранный герой, кого можно двигать, какой вариант лучше, куда направить действие, как обосновать совет и когда его отменить. Фильмовые 48 frames вообще не имеют native object annotations.

Все 40 capabilities каталога — proposed. Queue labels не заполнены. Пользовательский UI может собирать static target/desired rectangle/2D arrow, но не хранит полноценные clip tracks, временные интервалы действий и camera trajectories. Custom target — прямоугольник; точный контур потребует дополнительной representation и проверки.

### 5. Нет доказательств результата или технических настроек

Применённое действие, изменение композиции, выполнение цели и художественное улучшение — отдельные labels. Finished film/pan не доказывает, что оператор выполнил совет нашего приложения. Ни native COCO, ни произвольная пара кадров не обучают causal improvement.

COCO ≤640 px длинной стороны и неизвестный color/camera pipeline ограничивают fine focus/noise/WB. Даже крупный готовый movie frame не раскрывает истинные Kelvin/ISO/shutter/focal length и не является эталоном нейтрального белого. Нужны reference series/telemetry там, где capability их использует.

### 6. Holdout и self-review имеют ограничения

COCO val широко используется обученными CV-моделями; сам пакет помечает reserve как не unseen. Singleton ID groups не доказывают разные author/shoot/burst. Hash-уникальность не устраняет source dependence.

В `review/actual_visual_reviews.jsonl` 174 строки на 150 уникальных COCO IDs: 150 pixel reviews + 24 geometry reviews. В этом журнале нет film IDs, хотя summary заявляет просмотр всех 48 temporal frames. Кадры и temporal contact sheets присутствуют, но item-level review trace для фильма в данном журнале отсутствует. Это недостаток audit trail, не доказательство, что GPT их не видел.

## Как учить поведение в видео

| Компонент | Полезные обучающие/оценочные данные | Граница доказательства |
|---|---|---|
| Detector/segmenter | Native masks/boxes + кино/мобильные target frames | COCO можно использовать вспомогательно; сначала сравнить уже обученный baseline |
| Tracker | Непрерывные видео, linked entity IDs/masklets, loss/occlusion/reacquisition | Off-line all-frame labels не являются доступными будущими runtime inputs |
| Motion estimator / classifier | Camera-motion labels; video+IMU/pose когда доступны; static-camera actor motion controls | Optical flow не доказывает метрическое движение камеры; gyro не даёт надёжной translation |
| Temporal task assessor | История кадров/признаков до t, заданная задача, segment labels о её выполнении | Future frames и after недоступны planner в момент t |
| Planner | Conditional action preferences, preconditions, target grounding, preserve/abstain, adverse actions | Native shot/motion labels не равны supervision «исправь так» |
| Overlay/state machine | Frame geometry, track validity, transforms, cut/lens/target events | Контур и стрелка требуют renderer/координатного преобразования и state logic |
| Verifier | Реальные before/action/after либо отдельно labelled synthetic episodes | Action completed ≠ goal achieved ≠ frame aesthetically improved |

Temporal-модель не обязана быть новым монолитным video network. Уже обученные CV-компоненты, геометрия, память состояния и planner могут решить часть задач. Выбор GRU/TCN/Transformer требует baseline comparison; fps/window из ответа GPT — проектные гипотезы, не замеры.

## Отношение к присланному ответу GPT Pro

Подтверждается: нынешний корпус не закрывает live video; static images вспомогательны; нужны temporal identity/motion/context и реальные action evidence; synthetic crop не заменяет физический параллакс.

Не принимать без исследования: необходимость именно маленькой temporal NN; обязательность ровно 50 собственных постановок/200 дублей; оптимальность окна 2–4 секунды и частот; inference metric translation из одного gyro; достаточность SA-V/MovieShots для всего продукта. Их native targets существенно уже советов о красоте. Разные иллюстративные movie pictures в ответе не образуют реальный episode — текст сам обозначает эту условность.

Новое задание должно автономно получить всё доступное из existing cinematic/video/tracking/motion/pose источников и обоснованно дополнить автоматической разметкой и контролируемой синтетикой. Невосстановимые исторические намерения/controls и отсутствующая физическая съёмка не превращаются в факты от требования «полностью автоматически». Полноту проверять по agreed capability/data matrix, с различием raw/proposed/verified/synthetic supervision.

## Источники для исправления

- [MovieShots](https://virtualfilmstudio.github.io/projects/eccv20shot/): первичная страница описывает 46K shots из 7K trailers и scale/movement annotations. Это подходящий киношный motion prior; grant commercial rights на странице не установлен.
- [MovieNet](https://movienet.github.io/): movie/scene/character/style annotations; keyframes 240p, full movies исключены из basic download. Нельзя переносить разрешение annotations/download на все media uses.
- [CineScale](https://cinescale.github.io/shotscale/): shot-scale research source с отдельными access/use terms; изучить как reference, не обещать commercial clearance.
- [SA-V](https://ai.meta.com/datasets/segment-anything-video/): первичная страница описывает 51K videos и 643K class-agnostic masklets, CC BY 4.0; download требует проверки формы/terms. Это object segmentation supervision, а не operator advice.
- [TUM VI](https://cvg.cit.tum.de/data/datasets/visual-inertial-dataset): imagery/IMU/pose GT с batch access; full-path vs start/end-only GT различаются. Подходит motion/sensor-fusion задачам, но не cinematic utility и не iPhone telemetry.
- [RealEstate10K](https://google.github.io/realestate10k/download.html): доступный архив trajectory metadata/URLs/intrinsics/poses, не автоматически сами video bytes или их права. [MOVi/Kubric](https://github.com/google-research/kubric/blob/main/challenges/movi/README.md): controlled synthetic camera/object motion, masks/depth/flow; synthetic domain и data/assets terms требуют отдельной проверки.
- [Blender films](https://studio.blender.org/films/) и [Tears of Steel downloads](https://mango.blender.org/download/): реальные материалы с film-specific условиями; ширина live-action домена ограничена.
- [LOC National Screening Room rights](https://www.loc.gov/collections/national-screening-room/about-this-collection/rights-and-access/), [Prelinger FAQ](https://archivesupport.zendesk.com/hc/en-us/articles/360004715031-Prelinger-Archive): item-specific archive candidates; не заменять весь современный cinema corpus исторической хроникой.
- Google Image Search полезен как discovery. [Google guidance](https://support.google.com/websearch/answer/29508) рекомендует проверять условия у host/provider. Появление в поиске не устанавливает разрешение любого использования. [US Copyright Office](https://copyright.gov/fair-use/) описывает fair use как case-specific; это не юридический вывод о нашем проекте или иной юрисдикции.

Не объявлять все screenshots незаконными и не объявлять все разрешёнными. Собирать широкий cinema source inventory; отдельно отмечать разрешённые use scopes и unknowns. Public availability, приватность папки и copyright clearance — разные свойства.

## Что проверено в этом аудите

- Основной агент прочитал counts/manifests/catalog/matrix/guide/audit/source evidence и посмотрел все 10 pixel sheets (150 COCO), все 4 temporal sheets (48 frames), geometry sheet 1 и первые 8 queue images в исходном масштабе. Всего 157 уникальных COCO images + 48 film frames. Contact-sheet выборка создана сборщиком; это ограничивает её независимость и не позволяет оценить долю всех визуальных ошибок в 1270 stills.
- Luna inventory agent read-only проверил 10756 main-package files по size/SHA-256, decode и pixel hashes всех 1318 images, hash/dimensions/area 9352 masks; несоответствий/empty masks не найдено. Проверил согласованность checksum-sidecar с 10806 file records, включая 50 records отдельного архива. Bytes отдельного lossless archive не проверялись.
- Luna supervision agent проверил native labels, queue, UI/export format, temporal отсутствие и split limitations. Luna source agent проверил первичные страницы источников кино/видео; это не получение нового media.
- Модель, приложение, camera loop, loader tests, UI persistence и training не запускались. Старые `18 tests passed` — заявление отчёта сборщика, здесь не воспроизведённый результат.

## Решение

Сохранить v2 как auxiliary/архивный источник. Первая экспертная разметка должна перейти к небольшому сбалансированному кино/мобильному пакету и видеопоследовательностям. Создать v3 вокруг **целевых кино-сцен + живого video process + conditional advice**, не увеличивать COCO ради общего counts. Полное задание: [camera-coach-v3-continuation-prompt.md](camera-coach-v3-continuation-prompt.md).
