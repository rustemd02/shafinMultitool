# Промпт для ChatGPT Deep Research: проверка продукта Camera Coach

Статус: готов к запуску.

Дата: 15 августа 2026 года.

## Как запускать

1. Откройте новый чат в ChatGPT и включите **Deep research**.
2. Прикрепите файл `docs/app-store-product-plan.md`. Если прикрепить файл нельзя, промпт ниже всё равно содержит необходимый контекст.
3. Разрешите поиск по всему публичному интернету. Не ограничивайте исследование только перечисленными доменами.
4. Вставьте текст между маркерами `PROMPT START` и `PROMPT END` одним сообщением.
5. Перед запуском Deep Research покажет план исследования. Проверьте, что он включает сбор прямых пользовательских свидетельств, конкурентный анализ, монетизацию, privacy, продуктовый scope и итоговый decision packet. Если он предлагает только общий обзор рынка, попросите расширить план по требованиям промпта.
6. После завершения скачайте отчёт в Markdown и передайте Codex **полный файл**, а не только executive summary. Цитаты и список источников должны сохраниться.

Официальная документация OpenAI рекомендует задавать Deep Research цель, контекст, ограничения и желаемый формат, проверять предложенный план исследования и требовать цитаты, оценку качества источников и раздел с пробелами в данных. См. [Deep research in ChatGPT](https://help.openai.com/en/articles/10500283-deep-research-in-chatgpt) и [ChatGPT for research](https://openai.com/academy/research/).

---

# PROMPT START

Проведи глубокое исследование рынка и пользовательских проблем для коммерческого iOS-приложения Camera Coach. Итог должен позволить владельцу продукта и Codex перейти к проектированию и реализации версии 1.0 без дополнительного общего опроса о рынке.

Работай как независимый product researcher и стратег, а не как сторонник исходной идеи. Не подтверждай гипотезы автоматически. Ищи evidence, которое может как поддержать, так и опровергнуть выбранное направление.

Отчёт напиши на русском языке. Названия продуктов, интерфейсные термины, цены и короткие пользовательские цитаты сохраняй на языке источника, при необходимости добавляя краткий перевод.

## 1. Главная цель исследования

Нужно дать evidence-backed ответ на вопросы:

1. Существует ли достаточно частая и болезненная проблема у начинающих мобильных видеографов: человек видит кадр, но не понимает, что именно в нём мешает, какое одно действие поможет и стало ли после действия лучше?
2. В каких ситуациях эта проблема возникает, насколько она важна и к каким последствиям приводит?
3. Какой сегмент испытывает её сильнее всего, достижим для solo-разработчика и потенциально готов платить?
4. Какие существующие продукты, методы и обходные решения уже закрывают эту задачу?
5. Есть ли рыночное пространство для Camera Coach, который локально даёт один совет и проверяет результат, а по запросу предлагает платный серверный Deep Review?
6. Какая версия 1.0 будет минимально достаточной, полезной, понятной и отличимой от бесплатных camera apps и многочисленных AI photo coach приложений?
7. Какая граница Free/paid наиболее честна и коммерчески жизнеспособна?
8. Есть ли основания для подписки или реальное поведение скорее соответствует кредитам/пакетам/единоразовой покупке?
9. Какие требования к доверию, точности, latency, privacy, интерфейсу и объяснимости обязательны?
10. Какие факты всё ещё невозможно получить из публичных источников и какие риски мы принимаем, переходя к реализации без прямых customer interviews?

## 2. Контекст продукта

Проект сейчас называется `Shafin Multitool`. Это существующий исследовательский iOS-проект, который нужно превратить в коммерческое приложение и вывести в App Store.

Фактически в проекте соединены два продукта:

1. Camera analysis: локальные live-подсказки по композиции, главному субъекту, свету, фону, горизонту и крупности; pause-разбор; confidence и explainability.
2. Scene Mode: текст короткой постановочной сцены → локальный разбор → AR-размещение актёров/объектов → репетиция → запись.

Принятое направление: **Camera Coach — основной коммерческий продукт; Scene Mode — продвинутая дополнительная возможность, не главное обещание первого экрана**.

### Подтверждённая центральная боль

> «Я вижу кадр, но не понимаю, что именно в нём плохо, какое одно действие поможет и действительно ли после этого стало лучше».

### Целевой coaching loop

1. Автоматически определить главный субъект.
2. При неоднозначности предложить указать его одним тапом.
3. Выбрать одну приоритетную наблюдаемую проблему.
4. Предложить одно конкретное физическое действие.
5. Дождаться изменения без потока новых советов.
6. Сравнить состояние до и после.
7. Подтвердить улучшение, скорректировать совет или признать, что он не помог.
8. Воздержаться от совета при недостатке данных.
9. Если кадр уже сильный, предложить сохранить его без искусственного исправления.

### Граница рекомендаций 1.0

Приложение должно работать только с достаточно проверяемыми основами:

- читаемость главного субъекта;
- базовый свет и экспозиция;
- горизонт;
- крупность;
- композиционный баланс;
- отвлекающие объекты и визуальный шум;
- сохранение уже удачного кадра.

Оно не обещает понимать режиссёрский замысел, настроение, актёрскую игру или автоматически делать любой кадр «кинематографичным».

### Обязательная матрица качества 1.0

- один человек: talking head, портрет, ведущий, актёр;
- два человека: диалог или общий кадр;
- предмет или еда;
- интерьер;
- улица или пейзаж;
- сложный свет: темнота, пересвет, контровой свет, окно за спиной;
- уже сильный кадр, который система не должна испортить.

### Техническая и операционная рамка

- iPhone-first iOS-приложение;
- текущий deployment target — iOS 17, но окончательная device matrix не выбрана;
- Camera Coach должен работать в portrait и landscape;
- Scene Mode в 1.0 может остаться landscape-only;
- live Coach должен работать локально, быстро, без аккаунта, оплаты и сети;
- серверный Deep Review запускается только по явному действию;
- точный payload ещё не выбран: возможны один кадр, локальные признаки, пара «до/после» или короткая серия;
- обязательного аккаунта нет; Sign in with Apple и синхронизация отложены;
- история 1.0 хранится локально;
- работает один разработчик при постоянной помощи Codex;
- серверный бюджет минимальный;
- нельзя строить решение, требующее ручной модерации или круглосуточной поддержки.

### Принятый beta-вариант freemium, который нужно проверить

Free:

- полный локальный coaching loop;
- локальный pause-разбор;
- Coach и Pro Controls;
- запись без watermark во всех уже реализованных разрешениях/FPS;
- текущая сессия;
- три стартовых серверных Deep Review на установку;
- один пробный Scene Mode-проект;
- без рекламы.

Платный уровень:

- месячная квота Deep Review;
- более глубокий разбор сложных случаев;
- постоянная локальная история и сравнения «до/после»;
- полный Scene Mode без ограничения проектов;
- один уровень с месячным и годовым периодами;
- без недельной подписки и дополнительных пакетов в 1.0.

Подписка считается гипотезой. Если Deep Review используется эпизодически или не превосходит локальный Coach, нужно рекомендовать кредиты, пакеты или единоразовую покупку.

### UI/UX-ограничения

Целевое направление: нативный кинематографический инструмент с человеческим языком.

Нельзя использовать:

- card soup;
- бессмысленный glassmorphism;
- декоративные градиенты/glow;
- AI-sparkles и «магическую» символику;
- случайные pill-кнопки;
- навязчивую геймификацию;
- длинный обязательный onboarding;
- debug IDs и внутренние термины;
- фальшивые точные проценты;
- агрессивный paywall при первом запуске.

## 3. Критическое правило: не выдумывать интервью

Прямые customer interviews в это исследование не входят. Никогда не создавай «синтетических респондентов», придуманные ответы, вымышленные фокус-группы или ложные количественные результаты.

Вместо этого собери и проанализируй публичный corpus реального пользовательского языка:

- App Store reviews;
- Google Play reviews, если продукт имеет релевантную Android-версию;
- Reddit posts/comments;
- форумы мобильных видеографов, киноделов и creators;
- публичные обсуждения в сообществах производителей camera apps;
- YouTube reviews/comments, если комментарии доступны и относятся к конкретному пользовательскому опыту;
- публичные feature requests, support forums и issue discussions;
- профессиональные статьи или исследования о novice photographers/videographers;
- отзывы студентов киношкол и начинающих операторов, если они публичны и проверяемы.

Называй это `public user evidence`, `review mining` или `user-voice corpus`, но не интервью.

Для каждого вывода отделяй:

- **Observed direct evidence** — прямые слова/поведение пользователя в публичном источнике;
- **Published quantitative evidence** — опубликованные числа с методологией;
- **Competitor fact** — проверяемая функция, цена или policy;
- **Inference** — твой вывод из evidence;
- **Unknown** — то, что публичные данные не позволяют установить.

## 4. География и временной диапазон

Исследуй глобальный B2C-рынок с отдельным сравнением:

- США;
- Великобритания;
- Европейский союз;
- русскоязычная аудитория в доступных storefronts;
- при наличии сильных evidence — крупные рынки mobile creation в Азии и Латинской Америке.

Приоритет — данные последних 24 месяцев. Более старые источники используй только для устойчивых поведенческих закономерностей или истории рынка. У каждой цены, политики и продуктовой функции указывай дату проверки и storefront/валюту.

## 5. Требования к источникам

Используй широкий web search, но соблюдай иерархию:

1. Прямые публичные пользовательские свидетельства.
2. Официальные App Store/Google Play страницы и сайты разработчиков.
3. Официальные privacy policies, terms, pricing и support documentation.
4. Официальная документация Apple для App Store/IAP/privacy, когда делаешь нормативный вывод.
5. Академические статьи и исследования с описанной методологией.
6. Надёжные отраслевые публикации и обзоры, если первичного источника нет.
7. SEO-listicles, affiliate pages и автоматически сгенерированные подборки используй только как leads, но не как основание важных выводов.

Не используй поисковый snippet как доказательство: открывай страницу. Для ключевых claims давай ссылку рядом с утверждением. Если источник недоступен, paywalled или содержание нельзя проверить, укажи это.

Не выдавай рейтинг, число скачиваний, выручку, конверсию или размер рынка без проверяемого источника и понятной методологии. Не подменяй отсутствие данных псевдоточностью.

Короткие цитаты пользователей ограничивай одной фразой, достаточной для темы. Не копируй длинные отзывы. Указывай дату, площадку, продукт и ссылку, когда это доступно.

## 6. Минимальная ширина исследования

Стремись исследовать:

- не менее 15 релевантных продуктов/альтернатив;
- не менее четырёх конкурентных кластеров;
- не менее 150 уникальных единиц public user evidence в сумме;
- минимум три независимых типа источников;
- как положительный, так и отрицательный пользовательский опыт;
- recent reviews и устойчивые повторяющиеся темы.

Это цели исследования, а не право выдумывать покрытие. В отчёте укажи фактическое число продуктов, отзывов, постов и источников, которые удалось прочитать. Если доступ ограничен, честно сообщи achieved sample и влияние ограничения.

Не считай несколько копий одного пресс-релиза независимыми источниками. Не считай маркетинговый текст разработчика пользовательским evidence.

## 7. Обязательные конкурентные кластеры

Изучи не только прямых AI-конкурентов, но и реальные альтернативы пользователя.

### A. Профессиональные camera apps

Как минимум проверь актуальное состояние продуктов вроде:

- Blackmagic Camera;
- Final Cut Camera;
- FiLMiC Pro;
- Kino;
- Protake;
- Beastcam;
- Mavis;
- Photon или других релевантных camera apps.

### B. AI/photo/video coach apps

Проверь актуальность и доступность продуктов вроде:

- Shot Coach AI;
- FotoCraft;
- LensMentor;
- Scene Coach;
- Cam AI;
- FooCam;
- GridShot;
- других найденных composition/photo/video coach приложений.

### C. Previsualization и planning

Проверь решения вроде:

- Previs Pro;
- ShotPro;
- Cadrage Director's Viewfinder;
- Artemis Pro;
- Shot Designer;
- другие iOS/desktop tools для блокинга, shot planning и previs.

### D. Непрямые альтернативы

- стандартная Camera app и grid/level;
- YouTube/TikTok tutorials;
- курсы фотографии/видеографии;
- советы коллег и друзей;
- LUT/filter apps;
- video editors с auto-enhance;
- post-capture AI critique;
- reference boards, shot lists и overlays;
- ничего не делать и переснимать по ощущениям.

Если перечисленный продукт больше не существует, сменил модель или нерелевантен, зафиксируй это и замени его более сильным аналогом.

## 8. Исследовательские потоки

### 8.1. Сегменты и первый рынок

Сравни минимум:

- начинающих мобильных видеографов;
- начинающих авторов постановочных коротких роликов;
- creators для Reels/Shorts/TikTok;
- студентов киношкол;
- преподавателей/киношколы как B2B/B2B2C;
- малые indie-команды;
- начинающих фотографов, если evidence показывает более сильный fit, чем video-first.

Для каждого сегмента оцени:

- тяжесть боли;
- частоту ситуации;
- срочность;
- последствия ошибки;
- текущие обходные решения;
- готовность менять привычную camera app;
- признаки willingness to pay;
- достижимость канала;
- конкуренцию;
- fit с локальным Coach и Scene Mode;
- требуемый support;
- server cost exposure;
- privacy sensitivity.

Построй weighted scoring 1–5. Используй веса как прозрачную стартовую модель, но сделай sensitivity analysis:

- severity — 20%;
- frequency — 15%;
- willingness to pay — 15%;
- reachability — 10%;
- current product fit — 15%;
- differentiation — 10%;
- support/server economics — 10%;
- privacy/regulatory risk — 5%.

Покажи, меняется ли победивший сегмент при разумном изменении весов. Не выбирай массовых creators только из-за большого размера аудитории.

### 8.2. Pain/JTBD analysis

Для каждой найденной боли укажи:

- формулировку языком пользователя;
- functional job;
- emotional job;
- social job, только если есть evidence;
- triggering situation;
- desired outcome;
- current workaround;
- cost/consequence;
- frequency;
- evidence count и разнообразие источников;
- confidence;
- какое продуктовое поведение отвечает на боль;
- что могло бы опровергнуть вывод.

Отдельно проверь гипотезы:

- пользователь замечает проблему слишком поздно;
- пересъёмки стоят времени/репутации;
- профессиональные термины не превращаются в действие;
- несколько одновременных советов перегружают;
- неверный категоричный совет разрушает доверие;
- camera apps показывают controls, но не помогают принять решение;
- пользователь хочет подтверждение «стало лучше», а не score;
- пользователь не хочет покидать live-camera flow;
- пользователь боится отправлять личные кадры на сервер;
- пользователь снимает слишком эпизодически для подписки.

### 8.3. User journey и moment of value

Восстанови evidence-backed journey:

- что происходит до открытия приложения;
- почему пользователь выбирает отдельную camera app;
- какой момент наиболее тревожный;
- когда допустима подсказка;
- когда совет мешает;
- что пользователь делает после совета;
- что создаёт доверие;
- что вызывает удаление приложения;
- что может вернуть пользователя;
- какой результат достоин оплаты.

Проверь предполагаемое activation event:

> В первую сессию пользователь получает понятный совет, выполняет его и видит подтверждение улучшения — либо получает честный вердикт «оставить как есть».

Предложи более сильную формулировку activation, если evidence это требует. Не используй открытие камеры, регистрацию или нажатие кнопки как proxy ценности.

### 8.4. Product/market whitespace

Ответь:

- какие pains уже хорошо решены бесплатными camera apps;
- какие pains плохо решены AI coach приложениями;
- где конкуренты ограничиваются photo scoring, общими советами, курсами или post-capture critique;
- существует ли заметный gap вокруг live action + before/after verification;
- насколько Scene Mode усиливает differentiation или, наоборот, размывает продукт;
- что трудно скопировать;
- что выглядит уникальным только технически, но не имеет пользовательской ценности.

Сформулируй recommendation: **build / narrow / pivot / stop**, с evidence и falsifiers.

### 8.5. Feature scope 1.0

Собери таблицу:

- Must have;
- Should have;
- Later;
- Reject/Remove.

Для каждой функции укажи:

- pain/job;
- сегмент;
- evidence;
- frequency;
- expected value;
- implementation/support complexity на уровне low/medium/high;
- privacy/server impact;
- Free/paid recommendation;
- acceptance signal;
- reason to remove/defer.

Обязательно оцени:

- live one-tip coach;
- tap-to-clarify subject;
- before/after verification;
- local pause summary;
- server Deep Review;
- history;
- recording;
- portrait/landscape;
- Pro Controls;
- focus peaking/zebra/histogram;
- Scene Mode;
- account/sync;
- post-record video analysis;
- tutorials/courses/gamification;
- sharing/export;
- presets/reference shots;
- manual intent selection;
- audio analysis.

### 8.6. Качество рекомендаций и trust contract

Определи:

- какие ошибки совета наиболее вредны;
- какие ошибки терпимы;
- когда система обязана abstain;
- какой язык confidence понятен новичку;
- нужен ли процент confidence;
- сколько советов одновременно приемлемо;
- как долго совет должен оставаться стабильным;
- как пользователь понимает, что действие выполнено;
- как отменить или отклонить совет;
- как объяснить «кадр уже хороший»;
- какие данные нужны для доверия к before/after;
- нужен ли expert review/eval rubric.

Для каждого класса обязательной матрицы качества предложи:

- expected advice categories;
- forbidden advice categories;
- high-risk failure cases;
- minimum evidence;
- launch acceptance metric;
- рекомендуемый abstention behavior.

Не придумывай численные пороги без baseline. Если данных нет, дай процедуру их вычисления и initial measurement plan.

### 8.7. Server payload, privacy и perceived value

Сравни варианты:

- один текущий кадр;
- текущий кадр + локальные признаки;
- пара «до/после»;
- короткая серия кадров;
- короткий video clip;
- полностью локальный анализ.

Для каждого варианта оцени:

- какие user jobs он способен решить;
- какие советы невозможны;
- ожидаемое влияние на качество;
- latency;
- server cost;
- upload size;
- privacy sensitivity;
- App Store disclosure;
- сложность consent UX;
- вероятность того, что пользователь согласится;
- минимальный retention;
- риски хранения и улучшения модели.

Не выбирай payload только из соображений приватности или стоимости. Выбери минимально достаточный вариант для подтверждённой пользовательской ценности. Отдельно предложи default no-retention policy и opt-in research flow, если он обоснован.

### 8.8. Monetization и willingness-to-pay proxies

Сравни:

- freemium + subscription;
- freemium + credit packs;
- freemium + lifetime unlock;
- paid download;
- subscription + optional packs;
- бесплатный запуск без монетизации на короткий beta-период.

Для каждой модели оцени:

- соответствие частоте job;
- простоту объяснения;
- регулярную ценность;
- server cost predictability;
- риск злоупотребления;
- App Store fit;
- churn/refund risk;
- perceived fairness;
- solo-developer complexity;
- evidence из конкурентов и пользовательских реакций.

Проверь текущую beta-границу Free/paid. Особенно ответь:

- достаточно ли трёх стартовых Deep Review;
- не слишком ли щедро/бедно бесплатное ядро;
- следует ли ограничивать историю;
- должен ли Scene Mode иметь один бесплатный проект;
- должны ли Pro Controls быть бесплатными;
- нужен ли традиционный free trial;
- оправдана ли месячная подписка;
- нужен ли годовой период;
- когда показывать paywall;
- что происходит после окончания подписки;
- какие материалы нельзя брать «в заложники».

Собери актуальные цены конкурентов по storefront и дате. Не делай финальную цену только по конкурентам. Дай формулу unit economics:

`net revenue – server usage – infrastructure – refunds/support reserve – taxes/fees = contribution margin`.

Если доступно достаточно данных, предложи 2–3 price hypotheses для willingness-to-pay теста, но не называй их подтверждёнными ценами.

### 8.9. UI/UX evidence

Исследуй отзывы о:

- перегруженных professional camera UI;
- слишком упрощённых camera apps;
- нестабильных live hints;
- агрессивных paywalls;
- AI card dashboards;
- длинном onboarding;
- haptics;
- portrait/landscape switching;
- tap-to-focus/exposure;
- accessibility;
- trust language;
- scores и gamification.

Сформулируй evidence-backed UX principles для Camera Coach. Отдельно перечисли patterns, которые рынок воспринимает как дешёвые, непрофессиональные, навязчивые или недостоверные.

### 8.10. Acquisition, positioning и App Store promise

Определи:

- где достижим первый сегмент;
- какие communities/channels реально доступны solo-разработчику;
- какие поисковые запросы и категории App Store релевантны;
- какой язык используют пользователи для описания проблемы;
- какие promises повторяются у конкурентов и стали пустыми;
- какие claims можно доказать в 1.0;
- какие claims опасны или недостоверны;
- должен ли первый запуск быть English-first, Russian-first или bilingual;
- какие storefronts разумны первыми;
- как Camera Coach объяснить за 5–10 секунд без слов `AI`, `VLM`, `computer vision` и `AR`.

Предложи 5–10 product promise вариантов, но привяжи каждый к evidence и quality scope. Не создавай окончательное название бренда без отдельной проверки trademark/domain/App Store conflicts.

### 8.11. Metrics и beta design

Предложи минимальную систему метрик без vanity metrics:

- activation;
- completed coaching loop;
- advice accepted/rejected;
- before/after improvement;
- abstention;
- time to first value;
- repeat use;
- Deep Review request rate;
- starter credit exhaustion;
- paywall view/conversion;
- quota utilization;
- server latency/error/cost;
- crash-free sessions;
- recording success;
- privacy consent/drop-off.

Для каждой метрики укажи:

- точное событие;
- зачем оно нужно;
- решение, которое оно изменит;
- privacy classification;
- минимально достаточные properties;
- что нельзя собирать;
- возможные ложные интерпретации.

Предложи beta go/no-go gates и способ вычислить пороги после baseline. Не придумывай industry benchmarks без источника.

### 8.12. Risks, contradictions и kill criteria

Составь risk register минимум для:

- боль недостаточно частая;
- пользователи не хотят отдельную camera app;
- советы недостаточно точны;
- users предпочитают post-capture editing;
- free camera apps обнуляют ценность Pro Controls;
- Deep Review не превосходит local;
- subscription не соответствует эпизодическому usage;
- server cost/latency;
- privacy отказ;
- слишком большой app bundle;
- thermal/memory;
- Scene Mode размывает onboarding;
- solo-developer support overload;
- App Store review/privacy;
- доступность русскоязычной монетизации;
- competitor copying.

Для каждого риска укажи probability, impact, earliest signal, mitigation и kill/pivot criterion.

## 9. Метод анализа public user evidence

Создай evidence register со стабильными ID `E001`, `E002` и так далее.

Для каждого evidence item укажи:

- ID;
- short claim/theme;
- evidence type;
- segment;
- source/product;
- date;
- URL;
- короткую цитату или точную paraphrase;
- positive/negative/mixed;
- directness;
- source quality;
- relevance;
- limitations.

При тематическом анализе:

- удаляй дубли;
- не смешивай photo и video behavior без пометки;
- не смешивай beginner и professional needs;
- не считай один viral post репрезентативным;
- показывай число свидетельств по теме и число независимых источников;
- отмечай sampling bias;
- показывай противоречащие evidence;
- не превращай sentiment в количественный market estimate.

Используй confidence grade:

- **A** — повторяющийся прямой evidence из нескольких независимых типов источников;
- **B** — прямой, но ограниченный evidence или сильные согласующиеся вторичные источники;
- **C** — правдоподобный вывод с ограниченной прямой поддержкой;
- **D** — предположение/unknown; не использовать как основание реализации без дополнительной проверки.

## 10. Обязательный формат итогового отчёта

Не сокращай отчёт до общего эссе. Используй следующие разделы в этом порядке.

### 0. Research coverage card

- дата исследования;
- регионы;
- временной диапазон;
- фактическое число продуктов;
- фактическое число reviews/posts/comments;
- типы источников;
- недоступные источники;
- ограничения sample;
- overall confidence.

### 1. Одностраничный executive decision memo

- build / narrow / pivot / stop;
- рекомендуемый первый сегмент;
- центральная боль;
- главное ценностное обещание;
- почему пользователь сменит текущий способ;
- рекомендуемая Free/paid модель;
- три главных риска;
- что делать в реализации первым;
- confidence и ключевые evidence IDs.

### 2. Methodology and source quality

- research plan;
- search strategy;
- inclusion/exclusion criteria;
- source hierarchy;
- sample limitations;
- bias assessment.

### 3. Market and competitor map

- кластеры;
- таблица минимум 15 продуктов/альтернатив;
- positioning;
- target customer;
- current pricing;
- free features;
- paid features;
- reviews/ratings с оговорками;
- privacy/data model;
- strengths;
- complaints;
- whitespace.

### 4. Segment decision

- evidence-backed segment profiles;
- weighted scoring;
- sensitivity analysis;
- recommended beachhead;
- secondary segments;
- anti-segments, которые не нужно обслуживать в 1.0.

### 5. Pain and JTBD evidence map

- центральная боль;
- pain hierarchy;
- jobs;
- triggers;
- consequences;
- workarounds;
- frequency evidence;
- willingness-to-pay proxies;
- contradictions;
- confidence;
- evidence IDs.

### 6. User journey and activation

- journey map;
- moments of anxiety;
- moment of value;
- activation event;
- retention triggers;
- churn/deletion triggers.

### 7. Product strategy recommendation

- recommended positioning;
- differentiation;
- defensibility;
- role of Camera Coach;
- role of Scene Mode;
- non-goals;
- falsifiers.

### 8. Version 1.0 scope freeze

Таблица Must / Should / Later / Reject с pain, evidence, Free/paid, complexity, acceptance signal и rationale.

### 9. Trust and quality contract

- allowed advice boundary;
- abstention rules;
- matrix-specific expected/forbidden advice;
- failure severity;
- evaluation plan;
- proposed gates and how to derive thresholds.

### 10. Server/privacy recommendation

- payload comparison;
- recommended minimum sufficient payload;
- consent UX;
- retention;
- opt-in research;
- latency/cost budget method;
- privacy risks;
- unknowns.

### 11. Monetization decision

- Free/paid matrix;
- subscription/credits/lifetime comparison;
- recommended beta model;
- conditions for subscription go/no-go;
- starter allowance;
- paywall timing;
- price hypotheses;
- unit economics formula;
- post-expiration behavior.

### 12. UI/UX implications

- evidence-backed principles;
- required states;
- portrait/landscape implications;
- trust language;
- anti-patterns;
- accessibility implications.

### 13. Acquisition and App Store positioning

- reachable channels;
- language/storefront recommendation;
- product promise candidates;
- keyword themes;
- claims allowed/prohibited;
- launch sequencing.

### 14. Metrics and beta gates

- event dictionary;
- funnel;
- quality metrics;
- business metrics;
- technical metrics;
- privacy boundaries;
- go/no-go decision table.

### 15. Risk register and kill criteria

Probability, impact, early signal, mitigation, kill/pivot criterion и owner.

### 16. Decision ledger

Для каждого решения:

- Decision ID `D001`…;
- question;
- recommendation;
- status: `adopt / reject / defer / benchmark / owner-decision`;
- confidence A/B/C/D;
- evidence IDs;
- counterevidence IDs;
- assumptions;
- falsifier;
- implementation impact;
- decision trigger/date.

### 17. What public research cannot establish

Чётко перечисли:

- что осталось unknown;
- что обычно потребовало бы интервью/наблюдения;
- какой риск возникает, если начать реализацию без этого;
- что можно проверить в instrumented beta вместо интервью;
- какие вопросы блокируют реализацию, а какие могут ждать beta.

Не заканчивай отчёт общей рекомендацией «проведите интервью». Дай best available decision и предложи конкретный beta instrument для каждого остаточного unknown.

### 18. Evidence register

Полная таблица `E001…` со ссылками и ограничениями.

### 19. Source list

Сгруппируй источники по типу и укажи дату доступа.

### 20. Codex implementation handoff

Этот раздел должен быть коротким, однозначным и пригодным для прямой передачи coding agent.

Включи:

- `Recommended direction`;
- `Beachhead segment`;
- `Core pain`;
- `Core job`;
- `Activation event`;
- `Must-have 1.0`;
- `Explicit non-goals`;
- `Free contract`;
- `Paid contract`;
- `Quality matrix`;
- `Trust invariants`;
- `Privacy invariants`;
- `Metrics required before launch`;
- `Implementation blockers`;
- `Decisions safe to make now`;
- `Decisions deferred to benchmark`;
- `Decisions requiring owner approval`;
- `Top 10 implementation priorities in order`;
- `Evidence IDs supporting each priority`.

После Markdown-раздела добавь один валидный JSON-блок без комментариев по этой схеме:

```json
{
  "research_date": "YYYY-MM-DD",
  "overall_confidence": "A|B|C|D",
  "recommendation": "build|narrow|pivot|stop",
  "beachhead_segment": {
    "name": "",
    "why": "",
    "evidence_ids": []
  },
  "core_pain": {
    "statement": "",
    "evidence_ids": [],
    "confidence": "A|B|C|D"
  },
  "core_job": "",
  "activation_event": "",
  "scope_1_0": {
    "must": [],
    "should": [],
    "later": [],
    "reject": []
  },
  "free_contract": [],
  "paid_contract": [],
  "quality_matrix": [],
  "trust_invariants": [],
  "privacy_invariants": [],
  "monetization": {
    "recommended_model": "",
    "subscription_go_no_go_conditions": [],
    "price_hypotheses": [],
    "evidence_ids": []
  },
  "implementation_priorities": [
    {
      "rank": 1,
      "item": "",
      "why": "",
      "evidence_ids": []
    }
  ],
  "safe_decisions_now": [],
  "benchmark_decisions": [],
  "owner_decisions": [],
  "implementation_blockers": [],
  "residual_unknowns": [],
  "kill_criteria": []
}
```

JSON должен согласовываться с основным отчётом. Не включай в него непроверяемые числа как факты.

## 11. Стандарт качества ответа

Перед завершением проверь:

- каждый ключевой claim имеет citation или помечен inference/unknown;
- direct evidence не перепутан с маркетингом;
- фактический sample указан;
- contradicting evidence не скрыт;
- photo и video use cases разделены;
- beginner и professional needs разделены;
- текущие цены имеют дату/storefront;
- маленькие новые приложения с несколькими отзывами не представлены как доказательство рынка;
- вывод о подписке связан с частотой job, а не только с желаемой выручкой;
- Free действительно решает центральную боль;
- Deep Review имеет отличимую платную ценность;
- Scene Mode не размывает основной onboarding;
- privacy и wrong-advice risks отражены;
- рекомендации совместимы с solo-development и минимальным серверным бюджетом;
- implementation handoff не содержит противоречий с отчётом;
- список unknowns честный;
- результат пригоден для принятия решений, а не заканчивается общими фразами.

Если evidence противоречит исходным решениям, не сглаживай конфликт. Назови, какое решение нужно пересмотреть, почему, насколько уверенно и какое минимальное evidence способно закрыть спор.

Не задавай уточняющие вопросы, если можешь использовать приведённые default assumptions. Если критически необходимый контекст недоступен, зафиксируй предположение и продолжай исследование. Сначала покажи предложенный research plan, затем выполни исследование после подтверждения плана пользователем.

# PROMPT END
