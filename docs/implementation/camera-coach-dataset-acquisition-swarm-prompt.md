# GPT 6 Pro — визуальный киноассистент: продукт, подсказки, датасет, Google Диск и self-review

Дата: 2026-10-10. Версия: 3.0. Полная переработка по уточнению владельца: сначала замысел приложения и возможности визуального coaching, затем требования к данным и фактический сбор.

Скопировать весь текст между разделителями в GPT 6 Pro. Промпт самодостаточен; дополнительная [спецификация данных](camera-coach-input-data-requirements-v1.md) помогает при технической детализации. Здесь подготовлен текст задания; новый crawling/upload/training не выполнялся.

---

## Копируемый промпт

Ты помогаешь мне спроектировать и подготовить данные для **визуального киноассистента на iPhone для начинающих кинематографистов**. Работай как исследователь продукта, оператор-постановщик, инженер computer vision/ML и инженер данных. У тебя будет доступ к репозиторию, но прежний чат тебе не нужен: весь замысел описан здесь.

Твоя задача состоит из связанной цепочки: **понять продукт → исследовать и обосновать полезные возможности → сформировать каталог подсказок и визуальных предложений → определить необходимые данные → найти и получить подходящий корпус → выгрузить его на мой Google Диск → провести критический второй проход по своему результату**. Не заканчивай работу только красивым планом, если инструменты позволяют получить реальные материалы.

### 1. Что именно я хочу создать

Моё приложение SET OS / Camera Coach должно помогать человеку **прямо во время подготовки и съёмки делать кадр красивее, выразительнее и уместнее для его сцены**. Начинающий кинооператор смотрит в видоискатель телефона. Приложение понимает доступный контекст, замечает, что можно улучшить, и наглядно показывает, что сделать.

Например, в кадре два человека и стул. Для заданного диалога приложение может предложить немного сместить одного из участников, изменить высоту или позицию камеры, убрать конфликтующий фон, подобрать крупность, поправить свет или техническую настройку. Оно должно ясно показать, **кого/что касается предложение**, куда направлено действие и какой результат ожидается. Это может быть контур выбранного человека, подсветка объекта, стрелка перемещения, направляющая горизонта, пример желаемого положения/кадрирования, зона света, область фокуса или понятный control для настройки камеры.

Пользователь выполняет действие — приложение удерживает связь с нужным объектом и проверяет, получилось ли ожидаемое улучшение. Если кадр уже хорош для выбранной задачи, его не нужно бесконечно «чинить». Если цель/замысел неизвестны, приложение должно уточнить их простым способом или предложить условный вариант, а не угадывать уверенно.

Мы **ещё формируем идеальный набор подсказок и выразительных визуальных возможностей**. Ты должен исследовать, что действительно полезно и реализуемо. Текущие enums, heads модели и старый датасет не должны ограничивать продуктовый поиск. При этом найденная идея не становится реализованной функцией от того, что ты описал её в отчёте.

Главные пользователи: начинающие режиссёры, операторы, студенты киношкол, люди, которые снимают короткометражки, диалоги, постановочные сцены, учебные этюды и небольшие ролики с киноязыком. Съёмка возможна в одиночку или небольшой командой с ограниченным светом и оборудованием. Киноязык и осмысленная помощь на площадке важнее абстрактного рейтинга фотографии.

Сейчас работа ведётся над существующим iOS-приложением. Уже есть локальный camera-analysis/coaching путь, target selection, часть проверки действий, запись и отдельный Scene workflow. Есть исследовательские модели и данные, но полноценное качество задуманного ассистента ещё не доказано. Новые SMM/бизнес-идеи из других обсуждений к этому заданию не относятся.

### 2. Каким должен быть пользовательский опыт

Продумай полный процесс, а затем свяжи каждый его шаг с данными и техническими ограничениями:

1. Пользователь показывает сцену и при необходимости выбирает задачу: например, диалог, общий план комнаты, крупный план реакции, проходку или предметную вставку.
2. Система предлагает распознанный контекст и степень уверенности. Отличает то, что видно, от того, что можно узнать только из выбора пользователя, предыдущих планов или истории съёмки.
3. Пользователь может выбрать героя/группу/предмет, желаемый стиль и разрешённые изменения. Начальное взаимодействие должно быть коротким и понятным.
4. Приложение выбирает одно полезное следующее действие, объясняет его коротко и визуально привязывает к нужной части кадра.
5. На экране видно, где исходная цель и что означает стрелка: движение камеры, движение человека, движение предмета, поворот, изменение кадрирования либо настройка устройства.
6. Во время движения подсказка остаётся стабильной, не перескакивает между людьми, не дрожит и исчезает/обновляется, если стала неактуальна.
7. После действия приложение различает «действие выполнено», «кадр улучшился», «цель достигнута» и «сравнить нельзя». Это разные события.
8. Пользователь сохраняет дубль, сравнивает варианты или переходит к следующему плану. Межплановые советы возможны лишь при доступном контексте сцены/предыдущих кадров.

Исследуй работу до записи, во время записи и на паузе отдельно: подробный разбор и активные overlays могут быть полезны при подготовке и мешать дублю. Определи, что должно работать локально и быстро, а что допустимо запускать изредка по запросу.

### 3. Киноязык и типовые ситуации, под которые нужны данные

Не своди категорию «тип сцены» к одному плоскому label. Предложи связанную разметку по независимым измерениям:

- Содержание: люди, группа, предмет, помещение, улица, действие и взаимодействия.
- Задача/контекст: диалог, реакция, представление пространства, наблюдение, проходка, раскрытие предмета, вставка и другие обоснованные сценарии.
- Крупность и устройство плана: общий, средний, крупный/деталь, single/two-shot, over-the-shoulder и т. п.
- Положение/движение камеры: static, pan, tilt, tracking/follow, push/pull и другие реально доступные действия.
- Намерение: кто главный, что зритель должен заметить, настроение, deliberate style, степень постановочности.
- Отношения с соседними планами: последовательность, действие/взгляд/экранное направление, география участников, continuity.

Проверь термины и практические рекомендации по первичным/профессиональным источникам. Не объявляй это готовой окончательной онтологией без анализа.

| Съёмочная ситуация | Какой вид помощи исследовать | Какие данные потребуются сверх отдельного красивого кадра |
|---|---|---|
| Диалог «восьмёркой», shot/reverse-shot | Крупность, взгляд, взаимное положение, линии взаимодействия, согласованность обратных планов, положение плеча/фона | Связанные планы одной сцены, identity участников, роли, camera/subject geography при наличии, замысел и история |
| Общий/установочный план | Читаемость пространства, главный акцент, глубина, связь людей со средой | Полный кадр, выбранная цель, альтернативы позиции/кропа, структура сцены |
| Средний/крупный план и реакция | Head/look room, фон, фокус на нужном субъекте, выражение/момент без выдуманной психологии | Target/face geometry, task/intent, варианты крупности/ракурса и последовательность |
| Over-the-shoulder / two-shot / группа | Иерархия, перекрытия, разделение субъектов, foreground/background | Несколько identities, masks/boxes/pose при полезности, target/protected roles |
| Проходка/follow/tracking | Удержание крупности/позиции героя, стабильность, смена фона, траектория | Непрерывный clip, tracks/visibility/occlusion, camera-motion evidence и action context |
| Pan/tilt | Начало и конец движения, направление, темп, устойчивость, целевой объект | Временная последовательность, trajectory, start/end states, frame times; один still этого не доказывает |
| Приближение/отъезд/смена высоты/ракурса | Выразительность перспективы и различие physical move, zoom и crop | Связанные реальные takes, lens/control metadata или явное unknown, pose/depth если требуется |
| Предметная вставка/товар/деталь | Видимость формы/текста, distracting reflections, свет, баланс, фон | Target regions, разрешённая постановка, альтернативы света/положения, good/bad/ambiguous cases |
| Low-light/backlight/силуэт | Сохранение настроения при читаемости нужного объекта | Explicit/unknown intent, реальные captures разных экспозиций/света; защита deliberate style |
| Последовательность планов одной сцены | Coverage, continuity, ощущение пространства, сопоставимость технического вида | Scene pack с несколькими планами и контекстом; не случайная подборка похожих фотографий |

Проверь, какие нарушения киноязыка бывают намеренными и полезными. Не обучай модель механически запрещать каждый необычный ракурс, пересечение линии или нестандартную композицию. Для спорных сцен нужны context/alternatives/abstention.

### 4. Полный спектр подсказок, который нужно исследовать

Исследуй минимум следующие семейства; дополни их, если найдёшь более ценное:

**Композиция и выразительность.** Главный акцент, крупность, head/look room, crop/edge, баланс, negative space, foreground/background, глубина, горизонт, перспектива и фон. Совет должен учитывать замысел, а не насильно применять одну сетку.

**Камера и оператор.** Сдвиг точки съёмки, высота, pan/tilt, физический шаг/приближение/отход, lens/zoom/crop различия, выбор начала/конца движения, стабилизация и удержание героя. Показать различие между стрелкой камеры и стрелкой объекта.

**Люди и постановка.** Конкретный участник чуть левее/правее/дальше от фона, изменение взаимного расположения или направления корпуса/лица, группа как цель, props/foreground. Оценить практическую пользу, разрешения, наблюдаемость и способы проверки. Не угадывать согласие участников или доступное пространство вне кадра.

**Предметы и окружение.** Перемещение/поворот/удаление разрешённого предмета, разделение силуэтов, осмысленный акцент, фон и светильники. Объект должен быть конкретно идентифицирован и визуально показан.

**Свет и цвет.** Направление/жёсткость света, отделение от фона, лицо в контровом свете, fill, hotspot/glare, смешанный свет, white balance и consistency между планами. Разделить подсказку изменить реальный свет, настройку WB и будущую цветокоррекцию.

**Технические параметры.** Exposure/clipping, focus/AF lock/tracking, ISO/shutter/frame rate, flicker/motion rendering, stabilization, объективы и доступные controls. Исследовать реальные возможности iPhone/iOS по устройствам и ограничения auto/manual modes. Не обещать контрол, которого нет на конкретном устройстве.

**Проверка результата.** Target continuity, before/after, correct/wrong direction, overshoot, улучшение относительно цели, сохранение стиля, invalidation при смене сцены/линзы/намерения.

**Межплановая помощь.** Какие практические continuity/coverage подсказки полезны начинающему, какое состояние проекта они требуют и насколько оправданы в первой версии.

Различай: предложение пользователю, preview результата, one-tap применение технического параметра и полностью автоматическая корректировка. Для каждого режима оцени необходимость подтверждения, обратимость, устойчивость и риск неожиданно испортить дубль. Наличие модели не означает, что автоматический режим всегда предпочтительнее.

### 5. Найди действительно сильные отличия продукта

Я хочу полезные отличительные возможности, которые потенциально могут стать killer features. Это гипотезы для проверки, а не требование объявить наш продукт уникальным.

Исследуй прямые и соседние решения: mobile camera/pro-camera apps, AI composition/coaching, cinematography/shot planning/previsualization tools, visual subject guidance и технические assistants. Пользуйся актуальными официальными страницами, documentation и demonstrable flows. Для утверждений «у конкурентов нет» укажи границы проверенного набора и дату; отсутствие функции в описании не доказывает отсутствие в продукте.

Для 5–10 сильнейших гипотез составь карточку:

- Кто и в какой конкретной съёмочной ситуации выигрывает.
- Что приложение говорит и что именно рисует на экране.
- Какой наблюдаемый результат пользователь получает и как его измерить.
- Что уже предлагают проверенные альтернативы и в чём возможное отличие.
- Какие данные/labels/context/geometry нужны.
- Что можно собрать в интернете, что нужно снять/разметить отдельно.
- Вероятный технический путь, latency/compute/energy constraints, ограничения и цена ошибки.
- Оценка пользы, сложности, evidence strength; версия first release / later / reject и почему.

Как исходные гипотезы проверь: target-specific contour+arrow, stable desired-position preview, coaching диалога с контекстом обратного плана, guided pan/tilt с правильным finish frame, intent-preserving improvement, technical consistency между планами, понятное подтверждение результата. Предлагай собственные варианты и отвергай мои, если они плохо обоснованы.

Не раздувай MVP: выбери несколько наиболее ценных замкнутых сценариев. При этом data strategy должна описывать широкий продуктовый горизонт и приоритеты, чтобы ранний сбор не завёл в тупик.

### 6. Каталог подсказок и структурированный visual proposal

Прежде чем массово собирать исходники, составь **версионируемый предложенный каталог возможностей**, связанный с кино-сценариями. В repo может быть старый каталог: используй его как baseline, выяви пробелы и предложи расширения. Не переименовывай старые поля молча и не редактируй production schema в этой задаче.

Для каждого proposed capability укажи:

```text
capability_id, status(current/proposed/research/deferred), user_goal,
scene/shot/motion/sequence_context,
required_runtime_inputs, observability(single_frame/temporal/user_input/sensors),
target/recipient(operator/person/object/light/device),
issue_or_opportunity, supported_action, preconditions,
expected_visual_benefit, alternatives/when_not_to_advise,
overlay_type, grounding_geometry, coordinate_frame,
verification_evidence, invalidation_conditions,
required_dataset_units, label_types, source_availability,
priority, uncertainty, acceptance_method
```

Сформируй design proposal для typed visual output: target identity и mask/box/keypoints/anchor по необходимости, action recipient, direction/rotation/path/magnitude с единицами и uncertainty, цель/desired framing, confidence/evidence refs, active/updated/completed/expired state, время/условия validity, success criteria. Приведи 6–10 полностью объяснённых примеров разного типа. Это проект расширенного контракта, не заявление совместимости с текущим JSON.

Обязательно учти:

- Экранные left/right и физическое движение различаются; orientation, mirrored selfie, preview crop, stabilization и смена линзы требуют преобразований.
- Box показывает регион, но точная обводка требует mask/contour или иного явно названного representation.
- Screen-space стрелка не доказывает метрическую 3D траекторию; сантиметры/углы требуют измерений/calibration либо качественного relative action.
- Для движущегося target нужны устойчивый track и reacquisition/occlusion states. Потеря цели инвалидирует конкретную подсказку.
- Desired-position ghost не выдавать за предсказанное физически достоверное after image без такого evidence.
- Renderer, tracking и safety/state machine — самостоятельные части приложения. Датасет красивых фотографий сам по себе не научит всю систему правильно рисовать UI.

### 7. Предложи подходящий ML/CV путь и только затем supervision

Сравни несколько реалистичных схем: лёгкие специализированные local models/heads; vision+geometry+tracking+typed planner; VLM для редкого смыслового анализа; крупная VLM как offline teacher с последующей distillation; hybrid on-device/cloud для отдельных режимов.

Не навязывай одну огромную модель или текущий scorer. Для каждой схемы покажи, что она реально получает на вход, какие outputs обучаются, что вычисляется geometry/runtime, как обрабатываются uncertainty и накопленный scene context. Оцени speed, память, нагрев, privacy, network/offline, стоимость вызовов и зависимость от количества кадров. Числа опирай на измерения/источники либо пометь engineering estimate.

Сцена, крупность, движение и режиссёрский замысел имеют разную наблюдаемость. По одному still нельзя честно восстановить pan trajectory или доказать dialogue continuity. Правильный WB по художественному кадру может быть неоднозначен; для точной technical supervision потребуются соответствующие reference/metadata/captures. Разрешения, доступные controls и пользовательская цель должны быть входом или runtime gate, а не скрытым target, который image model обязана угадать.

Для каждого output составь цепочку **пользовательская возможность → runtime input → dataset unit → label/evidence → training/eval method → overlay/verification**. Если данные не позволяют выучить output, прямо назови пробел.

### 8. Единицы корпуса, которые нужно собрать

Не делай один неразличимый мешок JPEG. Нужны разные связные части:

| Единица | Назначение | Какие связи/labels нужны |
|---|---|---|
| Одиночный full frame | Композиция, target, технические признаки, good/style/ambiguous | Subject/context, observable issues, explicit/unknown intent, regions, task suitability |
| Варианты одной сцены/ракурса | Сравнение композиции/крупности/света | Scene identity, что изменилось, conditional preference/reason, protected intent |
| Spatial grounding sample | Обвести нужного человека/объект и привязать предложение | Stable entity refs, masks/boxes/pose/anchors при необходимости, roles, coordinate transforms |
| Непрерывный clip | Движение камеры/субъекта, устойчивость overlays | Frames/times, tracks/visibility/occlusion, camera-motion evidence, start/end states |
| Before/action/after episode | Проверка выполнения и улучшения | Planned vs performed action, same-target/same-scene, context, outcome, wrong-direction/no-action controls |
| Cinematic scene pack | Диалог/coverage/continuity и связанные планы | Scene/shot IDs, participant identities, shot order/roles, eyelines/screen direction, geography/intent если известны |
| Technical capture series | Exposure/focus/WB/light/control suggestions | Actual applied parameters, device/lens/color pipeline, reference conditions, perceived/technical outcomes |
| Good/intentional/hard negatives | Сохранять хороший кадр и стиль, abstain | Why preserve, ambiguous context, adverse alternatives, forbidden/unknown changes |
| Auxiliary source-native data | Aesthetic/IQA/detection/segmentation/tracking priors | Native labels без переименования в coaching truth, source/rights/overlap lineage |
| Synthetic control | Геометрия/robustness/controlled transformations | Parent/generator/parameters/seed и ограничения переноса на real captures |

Для scene packs и trajectories связь между материалами важнее числа отдельных frames. Сбор киношных screenshots может дать references/shot-scale samples при подходящих правах, но не автоматически camera pose, author intent, physical action или пригодный commercial training corpus.

### 9. Отбор, контекст и техническое качество

Сначала первичный материал под named capability. Category источника, поисковая фраза и VLM guess — только proposed tag, а не подтверждённое содержание.

Предпочитай originals/full frames. Начальный ориентир ordinary still: long edge ≥1024, short ≥512, предпочтительно ≥1280/720; для fine detail/focus/noise — native ≥1920/1080, когда доступно. Более низкое разрешение допустимо для конкретной наблюдаемой задачи с reason. Не апскейль для обхода порога. Размер tensors модели не равен размеру исходника для разметки.

Реальные blur/noise/clipping/underexposure — нужные примеры. Не отбрасывай их массово quality filter. Отделяй capture defect от JPEG, resize, screenshot/UI, watermark и обработки. Сохраняй orientation/aspect/crop/color/edit lineage; target annotations должны относиться к точному frame reference.

Дата съёмки одиночного кадра **не обязательна**. Сохраняй полезные изображения без EXIF/date с unknown time. Publication/retrieval time отдельно; календарную дату не выдумывать. Старое требование exporter к captured_at — будущая техническая адаптация, а не причина остановить сбор. Для clips/episodes важны frame order, relative timestamps/PTS/timebase, continuity и comparability.

Для людей/предметов различай observed, user-provided и unknown identity/intent/movability/permission. Не собирай персональную идентификацию сверх нужного track внутри сцены. Specific physical move требует соответствующего context; otherwise general/conditional/ask/abstain. Правило «человек должен всегда стоять по третям» не подходит как универсальный ground truth.

Для auto controls сохраняй actual applied values, не только запрошенную настройку. Unknown WB/ISO/shutter/lens не заполнять предположением из pixels. Для причинных before/after фиксируй остальные изменения; улучшение одновременно после смены света/камеры/позы не доказывает вклад одного действия.

### 10. Готовые датасеты и широкий поиск

Ищи по всему доступному интернету, включая новые источники, с primary documentation и воспроизводимыми ссылками. Оцени native labels, domain gap, resolution, rights, availability и связь с capability. Проверь существующие локальные manifests при доступе, чтобы не скачать уже имеющееся повторно.

Начальные направления, которые нужно проверить и дополнить:

- **AVA Aesthetic Visual Analysis**, эстетические scores/style tags: https://projet.liris.cnrs.fr/imagine/pub/proceedings/CVPR2012/data/papers/304_P2C-42.pdf . Не путать с action-recognition AVA. Native scores могут быть visual prior; не превращать их в coaching action, shot intent или achieved outcome.
- **KonIQ-10k**: https://database.mmsp-kn.de/koniq-10k-database.html — image-quality labels, full vs small versions, terms проверить.
- **PaQ-2-PiQ**: https://openaccess.thecvf.com/content_CVPR_2020/html/Ying_From_Patches_to_Pictures_PaQ-2-PiQ_Mapping_the_Perceptual_Space_of_CVPR_2020_paper.html — local/global quality, не full coaching.
- **Open Images**: https://storage.googleapis.com/openimages/web/factsfigures_v7.html и https://storage.googleapis.com/openimages/web/download_v7.html — objects/boxes/masks/relationships/occlusion/group hints, per-image rights.
- **COCO**: https://cocodataset.org/ — detection/segmentation/pose/context, applicable annotations/version и media terms проверить.
- **MIT-Adobe FiveK**: https://data.csail.mit.edu/graphics/fivek/ — editing/tonal examples; пары ретуши не physical action. Для охватываемых файлов Adobe research-only terms: https://data.csail.mit.edu/graphics/fivek/legal/LicenseAdobe.txt ; нужен file→license mapping.
- Дополнительные **cinematography/shot-type/camera-motion/scene-understanding, segmentation/tracking/pose, depth/multiview, mobile technical-quality, color/WB/light datasets**. Найди конкретные подходящие источники и обоснуй их роль; не заполняй список названиями из памяти.
- Авторские разрешённые film/educational scene packs, public-domain/permissive video, Commons/Openverse и собственные/специально снятые mobile examples. По каждому установить реальное содержание и права.

AVA-origin image после новой task-разметки — отдельный downstream record со stable crossDatasetLinkKey, правами и split lineage. Native aesthetic labels сами не являются Coach gold. Data rights нельзя выводить из популярности benchmark, кнопки Download или license его code/annotations.

Раздели условия на медиа, аннотации, retrieval, commercial training, redistribution/attribution. Unclear/research-only/NC не принимать как разрешение production use. Сохрани metadata кандидата и предложи замену. CC-BY-SA/public-domain statements проверять предметно, без автоматического юридического вердикта о model weights. Не обходи login/paywall/rate limits/access controls; screenshot не исправляет отсутствие прав. Copyright license не заменяет consent/privacy условия.

### 11. Автоматическая и человеческая разметка

Автоматизируй decode/hash/metadata/dedup, source-native annotation import, proposals для labels/regions/scene types, preliminary caption/critique и structured conversion. Укажи модель/version/prompt/evidence и limitations. Не выдавай confidence одной VLM или согласие нескольких моделей за измеренную правильность.

Для новых визуальных labels различай: модель предложила mask/track/action; человек проверил; независимые reviewers adjudicated. Original free-text владельца сохраняется неизменным рядом с parsed proposal. Отсутствующий label не становится negative; `unknown/not_observed` отличается от absent/zero. Один выбранный совет не доказывает вред всех остальных.

Критические cases, good/style/abstention, spatial identity, wrong-direction и subjective benefit требуют соответствующего human/evidence review. Self-review GPT качества acquisition не является независимой human adjudication. Current release gold требует реальных review IDs/adjudicator; future taxonomy нужно отдельно согласовать/реализовать.

Предложи практический режим, уменьшающий мою ручную работу: что разметить на небольшом calibration set, что можно предложить автоматически, как находить разногласия и что проверять обязательно. Не обещай полностью автоматический ground truth для смысла сцены и «красивее».

### 12. Размер, баланс и splits

Сначала выбери ценные capabilities и минимальные данные для их проверки. Проверь control sample 20–30 разнородных материалов, затем продолжай acquisition. Human label→loader proof не должен останавливать полезный raw collection, но нужен до утверждения training readiness.

Рабочий ориентир первой версии: 1000–3000 независимых useful still groups; curated human queue 200–300; около 300 отдельного evaluation reserve; 30–100 полезных real clips/scene units при возможностях среды. Scene packs и genuine action episodes считай отдельно; их недобор не скрывай количеством extracted frames. Это поисковые бюджеты, не гарантия достаточности модели. Пересмотри их с обоснованием по выбранным capabilities и yield.

Нужны good/preserve, corrective, intentional style, ambiguity/abstention, сложные multi-person/occlusion и adverse actions. Предварительно ориентируй curated still mixture на 25–35% good/preserve и 15–25% ambiguous/abstain, но не выдавай это за user prevalence и не назначай labels для выполнения quota. По каждой важной capability нужны positive/negative/uncertain cases; число supervised labels считать отдельно от raw media.

Приоритет mobile domain; web-photo/pro/cinematic/CG/scan и unknown-device считать отдельно. Ограничивай доминирование одной сцены/автора/family; source caps — ориентир diversity, не причина отказаться от уникального valuable episode.

Exact hashes, near duplicates/crops/resizes, source video/burst/scene/author и derivation groups проверяй централизованно. Все планы одного scene pack, frames одного video и варианты одного parent — одна partition, пока явно обоснованная evaluation схема не говорит иначе. Аугментации после split. Проверяй overlap auxiliary-pretraining с downstream reserve.

Отдельно train candidates, development, calibration и evaluation reserve. Пока нет независимых gold labels/freeze — это reserve, не готовый benchmark. Не включать reviewer answer/outcome/after/synthetic parameters в before-only model inputs. Ground-truth geometry и реальные runtime detector outputs оценивать раздельно, чтобы не получить oracle-only качество.

### 13. Как использовать репозиторий

Начни с README/AGENTS и минимального набора, а не чтения всего проекта:

```text
docs/implementation/camera-coach-input-data-requirements-v1.md
docs/implementation/APP_STORE_RELEASE_TRACKER.md
docs/implementation/PRODUCTION_ACCEPTANCE.md — C1–C3
ml/camera_coach/contracts/camera_release_label_v1.md и .schema.json
ml/camera_coach/contracts/camera_production_heads_v1.md
ml/camera_coach/contracts/camera_release_capability_mapping_v1.md
ml/camera_coach/contracts/set_composition_net_v2.json
ml/camera_coach/production_heads.py
docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md
docs/implementation/data-coverage-matrix-v1.md
docs/implementation/human-eval/shot-list-v1.md
```

Для предметного обзора киноязыка и визуальных предложений дополнительно используй:

```text
docs/cameraanalysis/README.md
docs/cameraanalysis/camera-analysis-requirements-draft.md
docs/cameraanalysis/03-domain-contracts.md
docs/cameraanalysis/operations-registry.v3-draft.json
docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md
shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift
shafinMultitool/Multitool2Module/Models/CameraAnalysis/ProCameraControlContracts.swift
shafinMultitool/Multitool2Module/Models/CameraAnalysis/ActionVerifier.swift
shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift
shafinMultitool/Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift
```

Проверь существующие SceneScript/shot/movement vocabularies, camera controls, target/overlay/planner/verifier owners. Отметь implemented, research-only, proposed и unavailable. Scene workflow и Camera Coach могут иметь разные owners: наличие термина в сценарии не доказывает способность live model его распознать. Draft v3 не равен runtime-контракту; `two_character_frame` не доказывает поддержку восьмёрки, `panning` — умение советовать панораму, а verifier пары стабильных кадров — проверку произвольной киношной траектории. Существующие arrows/region highlights и capability-gated camera controls — основа для исследования, не свидетельство готовности всех задуманных функций.

Справка по текущей реализации: 15 issue heads, 26 mapped action outputs, отдельные good/risk/abstention/delta/calibration contracts. Исследовательская image-v2 имеет иной layout, чем production heads trainer на feature vectors. Current action adapter обучает выбранную positive column, не полноценную negative action utility. Это технический baseline и список future integration tasks, **не потолок исследования WB, cinematic context, movements, grounding и новых подсказок**.

Предлагаемые новые labels/outputs храни в отдельном versioned design и mapping `current → proposed → required migration`. Не ломай существующие records, не назначай новым labels старые IDs с другим смыслом. Не заявляй current-loader compatibility там, где её нет.

Remote repo может не содержать local-data и ещё не опубликованные документы. При отсутствии доступа продолжай по данному контексту; явно перечисли непроверенные факты. Соблюдай owner storage rules на его Mac: raw data под `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`, не iOS repo/Xcode bundle/Library. В отдельной ChatGPT среде допустимо её временное artifact storage для подготовки upload; пути Mac не считать доступными.

### 14. Выполнение, полномочия и Google Диск

Я разрешаю в этой задаче искать, получать подходящие материалы разрешённым способом, создавать новую частную папку `CameraCoach_CinemaDataset_<date>_<run_id>` на моём Google Диске и загружать туда результат. Если я указал folder link, используй его. Повторного подтверждения этих действий не требуется. Не меняй существующие файлы/папки, не включай публичный sharing. Платные покупки, обход ограничений, отправка сообщений авторам, изменение production code/schemas, commits/pushes и обучение в эту задачу не входят.

В начале установи реальные tool capabilities: web search, pixels, binary download, scripting/archive, Drive upload. Не предполагай, что название GPT Pro/Deep Research/Drive connector гарантирует каждую возможность. При доступных subagents используй Luna Max для crawling/лёгких independent shards; иначе работай последовательно. Не заявляй использованную модель без runtime evidence.

Не трать основную работу на бесконечное проектирование: после сравнительного анализа зафиксируй provisional capability priorities и собери полезные данные под них. Если критическая гипотеза не подтверждается, скорректируй selection и объясни причину.

Если Drive upload недоступен, подготовь реальные downloadable ZIP shards/attachments, manifests и при необходимости воспроизводимый downloader; полезные acquisition/research работы продолжай. Если binary download тоже недоступен, верни verified ledger и способ получения, обозначив невыполненные bytes. Не выдумывай ссылки, hashes, проверенные изображения или выгрузку. Если требуется одно подключение/выбор папки, подготовь всё остальное до обращения ко мне.

Условие `done`: обоснованы capabilities/data mapping; фактический корпус получен/организован/проверен; promised bytes и manifests загружены в private Drive; upload подтверждён tools; выполнен self-review. Fallback с архивами для ручного импорта — `частично выполнено: upload blocked`, а не завершённая доставка.

### 15. Deliverables и организация файлов

```text
CameraCoach_CinemaDataset_<date>_<run_id>/
  START_HERE.md
  product_and_cinematic_workflows.md
  competitor_and_feature_research.md
  capability_catalog.csv
  visual_proposal_design.md
  capability_to_data_matrix.csv
  model_options_and_training_plan.md
  source_inventory.csv
  manifests/
    assets.jsonl
    scene_packs.jsonl
    episodes.jsonl
    rights.jsonl
    split_groups.jsonl
    checksums.sha256
  media/
    stills/<source_family>/
    clips/<source_family>/
    scene_packs/<scene_id>/
    technical_series/<series_id>/
    auxiliary/<dataset_version>/
    synthetic/<generator_version>/
  annotation_queue/
    queue.jsonl
    contact_sheets/
    review_instructions.md
  evaluation_reserve/manifest.jsonl
  proposals/                       # machine drafts, not human gold
  reports/
    coverage_by_capability.csv
    acquisition_report.md
    self_review.md
    capture_and_annotation_gaps.md
  tools/download_remaining.py      # только если нужен, без secrets
```

Можно адаптировать структуру к tools, сохранив однозначную связь ID→bytes. Для большого числа files используй ZIP shards с hash и manifest shard→relative path. Не копируй одни bytes между категориями ради count. CSV/отчёт без медиа не называется delivered image corpus.

Intake ledger должен содержать source/version/upstream IDs, landing/media URLs, per-use rights/author/license/evidence, реальный hash/path/decode/dimensions, capture time если известен и retrieval отдельно, origin/domain/edit lineage, parent/scene/shot/episode/track refs, proposed/verified content and capability tags, annotation/native-label refs, inspected-pixels status, split group и оставшиеся uncertainties. Предложенный intake/proposal формат не выдавать за существующую release schema.

Для каждого capability покажи acquired raw, available labels/geometry/context, effective supervised counts, manual/automatic work left и пригодность текущему/future trainer. Отдельно что невозможно получить простым scraping: controlled technical series, permission/intent, camera-motion measurements, true interventions и linked cinematic scenes.

### 16. Обязательный self-review

После сборки и выгрузки сделай отдельный критический проход. Цель — найти причины, по которым этот корпус **не научит заявленным возможностям**, а не подтвердить собственный оптимизм. При доступности отдельного reviewer используй его; иначе явно отдели acquisition и audit passes. Это не independent human gold.

Проверь по всему acquired набору, где tools позволяют: files/hashes/decode/manifest, exact duplicates/derivation/split leakage, per-use rights, фактические counts/groups, наличие Drive artifacts. Проверка metadata upload не равна проверке всех удалённых bytes — назови метод точно.

Визуальная выборка: stratified random по capability/source/unit type с seed и actually inspected IDs. Ориентир 10% крупной family, минимум 5 при наличии, суммарно ≥50 для корпуса ≥50; если ресурсы не позволяют, укажи действительный sample и границы. Для curated queue/critical spatial cases желательно полный просмотр. Technical examples смотреть на native resolution, temporal — как последовательность, scene packs — связно, а не случайной contact sheet.

Проверь по каждому приоритетному сценарию:

- Есть ли входные данные для recognition, target grounding, proposal и проверки результата, или только красивые иллюстрации?
- Dialogue pack действительно содержит связанные роли/планы? Pan/tilt представлен движением, а не одним still?
- Contour-capability имеет masks/способ их проверки? Identity держится при двух людях и occlusion?
- WB/control suggestion опирается на необходимые measurements/context, а не arbitrary «на глаз» число?
- Есть ли good/style/unknown и wrong-action counterexamples? Дефекты не уничтожены quality filter?
- Не смешаны desired outcome, наблюдавшийся outcome и synthetic rendering?
- Не выданы annotations/license другой задачи за Coach truth/разрешение на media?
- На какие предложения из каталога собранный корпус пока не даёт supervision?

Исправь/quarantine конкретные проблемы и пересчитай результат. Report должен содержать found/fixed/unresolved, reviewed IDs, sampling limits и **verdict по каждой capability**, а не одну оценку «9/10». Модельный confidence и согласие с собственной разметкой не являются измеренной точностью будущего приложения.

### 17. Как ответить мне

Начни с реального результата и Drive/attachment links. Дальше объясни:

1. Какой визуальный киноассистент мы можем обоснованно строить; какие первые сценарии выбраны и почему.
2. Какие отличительные возможности подтверждены лучше всего, какие только гипотезы; competitor evidence и неопределённости.
3. Каталог подсказок и 6–10 walkthrough примеров: контекст → что видим → что говорим/рисуем → что делает пользователь → как проверяем.
4. Рекомендуемые ML/CV варианты, grounded outputs и минимум новой архитектуры; реализация сейчас vs proposed changes.
5. Что фактически найдено/downloaded/uploaded: unique still groups, clips, linked scene packs, genuine episodes, technical series, annotations/masks/tracks; discovered-only отдельно.
6. Матрица capability→data→missing supervision. Какие функции можно начать проверять сейчас, а какие требуют отдельной съёмки/разметки.
7. Результаты self-review с найденными недостатками и исправлениями, а также границами проверки.
8. Лучший первый пакет для моей разметки, понятная инструкция и 5–10 примеров для будущего data→label→trainer→visual-proposal proof.
9. Готовый следующий план для Codex: подготовка/изменения контракта/разметка/обучение/интеграция/проверка, зависимости и критерии результата. Не выдавай этот план за выполненные работы.

Мне важны красота и выразительность результата, понятная визуальная помощь на площадке и честная техническая реализуемость. Не ограничивай исследование старыми 15 issue IDs/26 action IDs; не обещай магию одной модельки. Найди полезный набор возможностей, данные для них и доставь проверенные материалы, с которых действительно можно продолжать разработку.

---

Промпт подготовлен для нового чата GPT 6 Pro. Можно добавить конкретную Drive folder link и бюджет; весь продуктовый контекст уже включён. Сбор данных, проверка конкурентов и выгрузка — задания будущему исполнителю, не результаты этого документа.
