# Эссе для вступительного испытания в аспирантуру КГЭУ (иностранный язык)

Рабочий материал для подготовки. Не является частью диссертационного workspace (`docs/thesis/`).
Структура повторяет все 10 пунктов программы испытания, поэтому текст удобно заучивать по блокам, а на экзамене — сокращать, сохраняя порядок.

---

# Essay: About Myself and My Research Work

## 1. General information about myself

My name is Rustem Davletshin. I am a software engineer, and I live in Kazan, the capital of the Republic of Tatarstan, Russia. In 2026 I graduated from Kazan Federal University with a master's degree in Software Engineering; earlier I received my bachelor's degree in the same field there. Along with my work on iOS applications, I continue to develop the research started in my master's thesis, so my everyday experience combines practical software development with academic work. My main professional interest is the creation of intelligent mobile systems, and this interest defines both my master's thesis and my plans for the future.

## 2. General information about my university

I studied at Kazan (Volga Region) Federal University, one of the oldest and largest universities in Russia. My institute was the Institute of Information Technology and Intelligent Systems (ITIS). The Institute trains specialists in software engineering, artificial intelligence, data science and human-computer interaction, and it is well known for its practice-oriented approach: students take part in real projects and research groups from their first years of study. Both my bachelor's and master's programs belonged to the field of Software Engineering; my master's program was called "Analytics and Product Development", and it combined programming, product management and research methodology.

Thanks to my university I obtained both engineering skills (Swift, Python, machine learning tools) and research skills: analyzing scientific literature, designing experiments and writing academic papers. In my future research work I am going to study methods of on-device machine learning and the architecture of intelligent mobile applications, in particular the generation of structured data by compact neural models and explainable computer vision for media production.

## 3. General information about the topic of my research work

The topic of my master's thesis is "Development of Neural-Network Methods, Tools and a Prototype of a Mobile Application for Video Production Processes".

The problem I deal with comes from practice. Video production consists of two large stages: pre-production, where the scene is planned and storyboards are created, and shooting itself. Beginners and independent authors face three applied problems. First, drawing storyboards requires time and artistic skills that most people do not have. Second, people without professional training cannot objectively evaluate the aesthetic quality of their shot. Third, even when a person feels that the frame looks bad, they usually cannot explain why, because there is no formal language for such an explanation. In addition, mobile devices have strict limitations: limited computing resources, battery drain, overheating, and model degradation on unusual data.

Existing solutions mostly rely on cloud services or powerful desktop computers, and they rarely combine high quality with acceptable performance on a smartphone. This is the research gap my work addresses.

While studying the problem, I considered new information from several areas: quantized local large language models, grammar-constrained decoding, structured output generation, preference optimization and explainable artificial intelligence.

## 4. Methods used in my research work

In my research I compare traditional methods with new ones and use both deterministic and neural techniques.

For scene generation, the traditional approach is to ask a large language model to produce the final JSON description of the scene directly. In my work I use a different scheme: the neural model generates only a compact intermediate representation (an event table), and a deterministic compiler converts it into the final scene contract called SceneScript. Compact language models with 0.5–1.7 billion parameters (the Qwen family) are quantized to the GGUF format (Q4_K_M) and run directly on the device through the llama.cpp runtime with grammar-constrained decoding. To improve quality, I apply supervised fine-tuning, LoRA/QLoRA adapters and preference optimization (ORPO).

For frame analysis, I use computer vision methods: a multi-head neural model based on the MobileNetV3 architecture, which predicts the composition class, the main subject, possible defects, the usefulness of user actions, the probability of a "good frame", and abstention or risk; the NIMA model for aesthetic assessment; and the DETR model for semantic segmentation. The models are trained in PyTorch and exported to Core ML for on-device inference.

For evaluation, I use frozen benchmark datasets, leakage-aware train/test splits and statistical confidence bounds.

The advantages of the new methods over the old ones are significant. First, they provide deterministic guarantees: the share of valid final documents grows from about 43% for the base model to 100%. Second, they provide explainability: instead of a single "beauty score" the user receives recommendations with evidence and reasons. Third, they protect privacy and work offline, because all the analysis runs on the device. Finally, they take the limited resources of mobile hardware into account.

## 5. The content of my work, my hypothesis and the expected results

My work includes the design, implementation and experimental evaluation of the system. My hypothesis is the following: if a neural model produces only a bounded intermediate representation which is then compiled deterministically, and if frame criticism is built as an evidence-linked explanation instead of a scalar score, then a mobile application can provide useful support both in pre-production and during shooting without the usual trade-off between quality and performance on limited hardware.

I expect to obtain the following results: a formalized description of the method; a working iOS prototype; dataset and benchmark pipelines with reproducible metrics; and publications that confirm the practical value of the approach. In the future I also plan to prepare a state registration certificate for the computer program.

## 6. The goal of my research work

The goal of my work is to develop neural-network methods, tools and a prototype of a mobile application that optimize video production processes, taking into account the limited computational resources of mobile devices.

## 7. The value and significance of my research work

The practical value of the work is that it makes professional-level support available to beginners and independent creators: a storyboard can be generated from a text description in seconds, and recommendations during shooting are clear and explainable, so the user not only improves the shot but also learns. The application works offline, keeps personal data on the device and does not require paid cloud services.

The scientific value lies in the combination of three ideas in one mobile system: compact neural generation with deterministic compilation, evidence-based explainability, and an honest evaluation methodology with fixed benchmarks. I believe that the same methods can be transferred to other domains where mobile devices are used in field conditions, including technical diagnostics and monitoring in power engineering.

## 8. The completed part of my work

A significant part of the work has already been done. The results were published in the article: Davletshin R. F., Shakhova I. S. "A software tool for the optimization of video production processes" // Electronic Libraries. 2024. Vol. 27, No. 4. P. 478–502. This journal is included in the list of VAK publications. A second article has been submitted to the same journal and is currently under review.

The prototype of the application is implemented: it is a native iOS application with about 180 automated tests. The experimental results are also obtained. In scene generation, the final architecture reaches 100% valid JSON documents and 99.6% fully correct scenes, while the base model shows only 42.75% valid documents and no fully correct scenes at all. In frame analysis, on the audited test set of 174 images the system passes 85% of the cases, correctly hits the expected recommendations in 91% of them and preserves good frames in 99% of the cases.

The source code and the research materials are available in an open repository of the university.

## 9. The role of my research supervisor

My research supervisor is Airat Faridovich Khasyanov, PhD in Physics and Mathematics, Associate Professor of the Department of Software Engineering. His role in my work is difficult to overestimate. He helped me to choose and formulate the topic, to plan the research and to structure it correctly: from the problem statement and the literature review to the design of experiments with clear acceptance criteria. He also taught me research discipline: every claim must be supported by evidence, and verified results must be separated from assumptions. He reviews my drafts and articles and gives critical feedback. I am sure that a supervisor is not only a consultant but also a teacher of scientific culture.

## 10. My personal interest in the topic

My interest in this topic is personal. I have been fond of cinematography for many years and have made videos myself, so I know from my own experience how difficult it is to plan a scene without professional skills and how frustrating it is to see that a shot looks wrong without understanding why. When I started to study programming and machine learning, I wanted to connect these two worlds and create a tool that would make professional techniques available to ordinary people.

This topic is important for me also because it requires a combination of skills I enjoy: mobile development, applied machine learning and creative thinking. I see it as my long-term career path.

## 11. My plans for future research work

My master's thesis was the first stage of a longer research program, and I am going to continue it in postgraduate school.

First, I plan to strengthen the empirical base of the project. At the moment a significant part of the training data is labelled automatically, so my next step is to build a human-annotated dataset: expert-confirmed labels for composition problems, useful actions and good frames, collected and reviewed with the annotation tools that I have already developed. On this data I will train the full multi-head neural model and calibrate its confidence, so that it can be integrated into the release version of the application; today the release build uses only the simpler aesthetic and segmentation models, while the composition model works in research mode.

Second, I am going to test the system on physical devices and with real users. I plan to measure performance, battery consumption and thermal behaviour during long shooting sessions, and then to conduct a user study with beginner filmmakers in order to check whether explainable recommendations really improve their shots and their understanding of composition. In addition, I will extend the evaluation methodology — new datasets, additional random seeds and fully independent test sets — so that the results do not depend on a single benchmark.

Third, I want to develop the hybrid architecture of the system, where the local module gives instant feedback during shooting and the server module performs a deeper analysis on request. The backend prototype with authentication, request limits and data retention rules already exists in my project, and I plan to bring it to a working state with clear privacy guarantees.

Fourth, I consider the transfer of these methods to other domains an important direction. The combination of on-device neural inference, deterministic compilation and explainable analysis can be useful wherever mobile devices are used in field conditions — for example, in technical diagnostics and monitoring of power equipment, where a specialist needs an understandable conclusion here and now.

Finally, I am going to publish the results: articles in peer-reviewed journals, reports at conferences, a state registration certificate for the software and, as the result of all this work, a PhD thesis. That is why I am applying for the postgraduate program at Kazan State Power Engineering University: I would like to develop my research in the field of information technologies and telecommunications under the guidance of experienced researchers.

---

# Перевод (для самопроверки и заучивания)

## 1. Общая информация о себе

Меня зовут Рустем Давлетшин. Я программист, живу в Казани, столице Республики Татарстан. В 2026 году я окончил Казанский федеральный университет, получив магистерскую степень по программной инженерии; ранее там же получил бакалаврскую степень по тому же направлению. Параллельно с работой над iOS-приложениями я продолжаю развивать исследование, начатое в магистерской диссертации, поэтому моя повседневная практика соединяет реальную разработку и академическую работу. Мой главный профессиональный интерес — создание интеллектуальных мобильных систем, и именно он определяет как мою магистерскую диссертацию, так и планы на будущее.

## 2. Общая информация о вузе

Я окончил Казанский (Приволжский) федеральный университет — один из старейших и крупнейших университетов России. Я учился в Институте информационных технологий и интеллектуальных систем (ИТИС). Институт готовит специалистов по программной инженерии, искусственному интеллекту, анализу данных и человеко-компьютерному взаимодействию и известен практико-ориентированным подходом: студенты участвуют в реальных проектах и исследовательских группах с первых курсов. Мои бакалаврская и магистерская программы относились к направлению «Программная инженерия»; магистерская программа называлась «Аналитика и управление разработкой» и объединяла программирование, управление продуктом и методологию исследований.

Благодаря университету я получил и инженерные навыки (Swift, Python, инструменты машинного обучения), и исследовательские: анализ научной литературы, постановка экспериментов и написание научных работ. В своей будущей научной работе я собираюсь изучать методы машинного обучения на устройстве и архитектуру интеллектуальных мобильных приложений, в частности генерацию структурированных данных компактными нейросетевыми моделями и объяснимый компьютерный анализ изображений для видеопроизводства.

## 3. Общая информация о теме научной работы

Тема моей магистерской диссертации — «Разработка нейросетевых методов, инструментов и прототипа мобильного приложения для процессов видеопроизводства».

Проблема, которой я занимаюсь, пришла из практики. Видеопроизводство состоит из двух больших этапов: предварительной подготовки, где планируется сцена и создаются раскадровки, и самой съемки. Начинающие и независимые авторы сталкиваются с тремя прикладными проблемами. Во-первых, отрисовка раскадровок требует времени и художественных навыков, которых у большинства людей нет. Во-вторых, человек без профессиональной подготовки не может объективно оценить эстетическое качество своего кадра. В-третьих, даже когда человек чувствует, что кадр выглядит плохо, он обычно не может объяснить почему, потому что формального языка для такого объяснения не существует. Кроме того, мобильные устройства имеют жесткие ограничения: нехватка вычислительных ресурсов, расход батареи, перегрев и деградация моделей на нетипичных данных.

Существующие решения в основном опираются на облачные сервисы или мощные настольные компьютеры и редко сочетают высокое качество с приемлемой производительностью на смартфоне. Именно этот разрыв и закрывает моя работа.

Изучая проблему, я рассматривал новую информацию из нескольких областей: квантованные локальные большие языковые модели, декодирование с грамматическими ограничениями, генерация структурированного вывода, оптимизация по предпочтениям и объяснимый искусственный интеллект.

## 4. Методы, используемые в работе

В исследовании я сравниваю традиционные методы с новыми и использую как детерминированные, так и нейросетевые техники.

Для генерации сцен традиционный подход — попросить большую языковую модель сразу выдать финальное JSON-описание сцены. В моей работе применяется другая схема: нейросетевая модель порождает только компактное промежуточное представление (таблицу событий), а детерминированный компилятор преобразует его в итоговый контракт сцены SceneScript. Компактные языковые модели на 0.5–1.7 млрд параметров (семейство Qwen) квантуются в формат GGUF (Q4_K_M) и работают прямо на устройстве через рантайм llama.cpp с грамматически ограниченным декодированием. Для повышения качества я применяю дообучение с учителем, адаптеры LoRA/QLoRA и оптимизацию по предпочтениям (ORPO).

Для анализа кадра я использую методы компьютерного зрения: многоцелевую нейросетевую модель на архитектуре MobileNetV3, которая предсказывает класс композиции, главный объект, возможные дефекты, полезность действий пользователя, вероятность «хорошего кадра», а также отказ от ответа и риск; модель NIMA для эстетической оценки и модель DETR для семантической сегментации. Модели обучаются на PyTorch и экспортируются в Core ML для инференса на устройстве.

Для оценки качества я использую замороженные бенчмарк-наборы, разбиения train/test с защитой от утечек и статистические доверительные границы.

Преимущества новых методов перед старыми существенны. Во-первых, они дают детерминированные гарантии: доля валидных итоговых документов растет с примерно 43% у базовой модели до 100%. Во-вторых, они обеспечивают объяснимость: вместо одной «оценки красоты» пользователь получает рекомендации с доказательствами и причинами. В-третьих, они защищают приватность и работают офлайн, так как весь анализ выполняется на устройстве. Наконец, они учитывают ограниченные ресурсы мобильного железа.

## 5. Содержание работы, гипотеза и ожидаемые результаты

Моя работа включает проектирование, реализацию и экспериментальную оценку системы. Гипотеза формулируется так: если нейросетевая модель порождает только ограниченное промежуточное представление, которое затем детерминированно компилируется, и если критика кадра строится как объяснение, связанное с доказательствами, а не как скалярная оценка, то мобильное приложение сможет давать полезную поддержку и на этапе подготовки, и во время съемки — без обычного компромисса между качеством и производительностью на слабом железе.

Я планирую получить следующие результаты: формализованное описание метода; работающий iOS-прототип; пайплайны датасетов и бенчмарков с воспроизводимыми метриками; публикации, подтверждающие практическую ценность подхода. В дальнейшем я также планирую подготовить свидетельство о государственной регистрации программы для ЭВМ.

## 6. Цель научной работы

Цель моей работы — разработать нейросетевые методы, инструменты и прототип мобильного приложения, оптимизирующие процессы видеопроизводства с учетом ограниченных вычислительных ресурсов мобильных устройств.

## 7. Ценность и значимость научной работы

Практическая ценность работы в том, что она делает поддержку профессионального уровня доступной начинающим и независимым авторам: раскадровка генерируется из текстового описания за секунды, а рекомендации во время съемки понятны и объяснимы, поэтому пользователь не только улучшает кадр, но и учится. Приложение работает офлайн, хранит персональные данные на устройстве и не требует платных облачных сервисов.

Научная ценность заключается в соединении трех идей в одной мобильной системе: компактная нейросетевая генерация с детерминированной компиляцией, объяснимость на основе доказательств и честная методика оценки на фиксированных бенчмарках. Я считаю, что те же методы можно перенести в другие области, где мобильные устройства используются в полевых условиях, включая техническую диагностику и мониторинг в энергетике.

## 8. О проделанной части работы

Значительная часть работы уже выполнена. Результаты опубликованы в статье: Давлетшин Р. Ф., Шахова И. С. «Программное средство оптимизации процессов видеопроизводства» // Электронные библиотеки. 2024. Т. 27. № 4. С. 478–502. Журнал входит в список изданий ВАК. Вторая статья отправлена в тот же журнал и находится на рецензировании.

Прототип приложения реализован: это нативное iOS-приложение с примерно 180 автоматическими тестами. Экспериментальные результаты также получены. В генерации сцен итоговая архитектура достигает 100% валидных JSON-документов и 99,6% полностью корректных сцен, тогда как базовая модель показывает лишь 42,75% валидных документов и ни одной полностью корректной сцены. В анализе кадра на проверенном наборе из 174 изображений система проходит 85% случаев, корректно попадает в ожидаемые рекомендации в 91% случаев и сохраняет хорошие кадры в 99% случаев.

Исходный код и исследовательские материалы доступны в открытом репозитории университета.

## 9. Роль научного руководителя

Мой научный руководитель — Айрат Фаридович Хасьянов, PhD (физико-математические науки), доцент кафедры программной инженерии. Его роль в моей работе трудно переоценить. Он помог выбрать и сформулировать тему, спланировать исследование и правильно его структурировать: от постановки проблемы и литературного обзора до проектирования экспериментов с четкими критериями приемки. Он же приучил меня к исследовательской дисциплине: каждое утверждение должно опираться на доказательства, а проверенные результаты нужно отделять от предположений. Он рецензирует мои черновики и статьи и дает критическую обратную связь. Я уверен, что научный руководитель — это не только консультант, но и учитель научной культуры.

## 10. Личный интерес к теме

Мой интерес к теме личный. Я много лет увлекаюсь кино и сам снимаю видео, поэтому знаю по своему опыту, как трудно планировать сцену без профессиональных навыков и как обидно видеть, что кадр выглядит неправильно, не понимая почему. Когда я начал изучать программирование и машинное обучение, мне захотелось соединить эти два мира и создать инструмент, который сделает профессиональные приемы доступными обычным людям.

Эта тема важна для меня еще и потому, что требует сочетания навыков, которые мне нравятся: мобильная разработка, прикладное машинное обучение и творческое мышление. Я вижу в ней свою долгосрочную карьеру.

## 11. Планы на будущую научную работу

Магистерская диссертация стала для меня первым этапом более длинной исследовательской программы, и я собираюсь продолжить ее в аспирантуре.

Во-первых, я планирую усилить эмпирическую базу проекта. Сейчас значительная часть обучающих данных размечена автоматически, поэтому мой следующий шаг — собрать датасет с ручной разметкой: подтвержденные экспертом метки композиционных проблем, полезных действий и хороших кадров, собранные и проверенные с помощью инструментов аннотации, которые я уже разработал. На этих данных я обучу полную многоцелевую нейросетевую модель и откалибрую ее уверенность, чтобы интегрировать модель в релизную версию приложения; сегодня в релизной сборке работают только более простые модели эстетики и сегментации, а композиционная модель находится в исследовательском режиме.

Во-вторых, я собираюсь проверить систему на реальных устройствах и с реальными пользователями. Я планирую измерить производительность, расход батареи и тепловое поведение во время длительных съемочных сессий, а затем провести пользовательское исследование с начинающими кинематографистами, чтобы проверить, действительно ли объяснимые рекомендации улучшают их кадры и понимание композиции. Кроме того, я расширю методику оценки — новые датасеты, дополнительные случайные seed и полностью независимые тестовые наборы, — чтобы результаты не зависели от одного бенчмарка.

В-третьих, я хочу развивать гибридную архитектуру системы, где локальный модуль дает мгновенную обратную связь во время съемки, а серверный модуль выполняет более глубокий анализ по запросу. Прототип бэкенда с аутентификацией, лимитами запросов и правилами хранения данных уже существует в моем проекте, и я планирую довести его до рабочего состояния с понятными гарантиями приватности.

В-четвертых, я считаю важным направлением перенос этих методов в другие области. Сочетание нейросетевого инференса на устройстве, детерминированной компиляции и объяснимого анализа может быть полезно везде, где мобильные устройства используются в полевых условиях, — например, в технической диагностике и мониторинге энергетического оборудования, где специалисту нужен понятный вывод здесь и сейчас.

Наконец, я собираюсь публиковать результаты: статьи в рецензируемых журналах, доклады на конференциях, свидетельство о государственной регистрации программы для ЭВМ и, как итог всей этой работы, кандидатскую диссертацию. Поэтому я подаю документы на программу аспирантуры Казанского государственного энергетического университета: я хотел бы развивать свое исследование в области информационных технологий и телекоммуникаций под руководством опытных ученых.

---

# Short exam version (about 700 words)

My name is Rustem Davletshin, in 2026 I graduated from Kazan Federal University with a master's degree in Software Engineering, and today I develop iOS applications. My master's program, "Analytics and Product Development", combined programming, product management and research methodology, while my studies at the Institute of Information Technology and Intelligent Systems gave me both engineering and research skills.

The topic of my master's thesis is the development of neural-network methods, tools and a prototype of a mobile application for video-production processes. Beginners and independent authors face three applied problems: creating storyboards requires time and artistic skills; the aesthetic quality of a shot cannot be evaluated objectively without professional training; and a frame that looks wrong cannot be explained, because no formal language for such an explanation exists. These difficulties are aggravated by the strict limitations of mobile devices, such as weak computing resources, battery drain and overheating, while the existing solutions, mostly cloud-based, rarely combine high quality with acceptable performance on a smartphone.

In my work, a compact language model of the Qwen family (0.5–1.7 billion parameters, quantized to the GGUF format) runs on the device through llama.cpp and produces only an intermediate event table, from which a deterministic compiler derives the final scene contract called SceneScript. Frame analysis relies on computer-vision models: a multi-head network built on MobileNetV3, trained in PyTorch and exported to Core ML, together with the NIMA aesthetic model and the DETR segmentation model. What these methods offer, in comparison with the traditional ones, is not only deterministic guarantees and respect for mobile resources, but also explainability and offline operation: the share of valid final documents grows from about 43% for the base model to 100%, and an opaque "beauty score" is replaced by recommendations supported with evidence.

My hypothesis is that bounded neural generation with deterministic compilation, together with evidence-linked frame criticism, can provide useful support both in pre-production and during shooting without the trade-off between quality and performance that limited hardware usually imposes. The goal of my work follows from this hypothesis: to develop neural-network methods, tools and a prototype mobile application that optimize video-production processes with respect to the limited resources of mobile devices. The value of the work is both practical, since professional-level support becomes available to ordinary creators and works offline, and scientific, because compact neural generation, deterministic compilation and explainable analysis are combined within a single reproducible mobile system.

A considerable part of the work has already been completed. Its results were published in the article "A software tool for the optimization of video production processes" (Electronic Libraries, 2024, Vol. 27, No. 4, pp. 478–502), a journal included in the VAK list, while a second article is currently under review. The prototype has been implemented and is covered by about 180 automated tests. As for the experiments, the final architecture of scene generation achieves 100% valid documents and 99.6% fully correct scenes, whereas the base model reaches only 42.75% and no fully correct scenes at all; in frame analysis, 85% of the cases on the audited set of 174 images are passed successfully.

The master's thesis, however, is only the first stage of a longer research program. Among my next steps are building a human-annotated dataset, training and calibrating the full neural composition model so that it can be included in the release build, validating the application on real devices and with beginner filmmakers, and developing the hybrid architecture, in which the local module provides instant feedback while the server performs a deeper analysis on request. I also consider it important to transfer these methods to domains where mobile devices operate in field conditions, for example to technical diagnostics and monitoring of power equipment.

My research supervisor, Airat Faridovich Khasyanov, PhD in Physics and Mathematics, helped me to formulate the topic, to design experiments with clear acceptance criteria and to maintain research discipline, according to which every claim must be supported by evidence. My interest in the topic is deeply personal: since I make videos myself, I know how valuable clear and explainable guidance can be for a beginner, and it is for this reason that I intend to continue my research at Kazan State Power Engineering University.

---

# Заметки для подготовки

## Соответствие пунктам программы испытания

| Пункт программы | Раздел эссе |
|---|---|
| Общая информация о себе | 1 |
| Общая информация о вузе | 2 |
| Общая информация о теме научной работы | 3 |
| Методы, используемые в работе | 4 |
| Содержание проводимой работы (включая гипотезу) | 5 |
| Цель научной работы | 6 |
| Ценность и значимость | 7 |
| О проделанной части работы | 8 |
| Роль научного руководителя | 9 |
| Личный интерес к теме | 10 |
| Планы на будущее (сверх обязательных пунктов) | 11 |

## Откуда взяты факты и цифры

- Тема ВКР, объект/предмет, новизна — `docs/thesis/00_thesis_brief.md`, `docs/thesis/ДИССЕР.md`.
- Метрики генерации сцен (42.75% → 100%, strict 99.62%) — `docs/thesis/chapters/ch5_experiments.md` (таблица эволюции подходов), `docs/thesis/snapshots/model_eval_snapshot.md`.
- Метрики анализа кадра (174 изображения) — `docs/thesis/chapters/ch5_2_camera_analysis.md`.
- Статья — библиография в `docs/thesis/ДИССЕР.md` и `docs/thesis/litreview.md` (ссылка № 4). ВАК-статус журнала указан по вашей формулировке из задания.
- Вторая статья «отправлена» — упоминание в `docs/thesis/defense/pre-defense-script.md`, подтверждается только как «отправлено на публикацию», поэтому в эссе стоит «under review».
- Планы на будущее (раздел 11): human-gold разметка, обучение и калибровка полной модели, устройство/пользователи, гибридная архитектура, релизные гейты — это зафиксированные next steps из `docs/thesis/00_thesis_brief.md` («Честные ограничения») и мастер-плана `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md` §24.

## Что проверить / заменить перед подачей

- **Работа.** Формулировки про iOS-разработку («Along with my work on iOS applications», «today I develop iOS applications») — если вы не работаете по найму, замените на «I develop iOS applications as part of my engineering practice and research».
- **Год выпуска.** В тексте стоит «In 2026 I graduated…» — если будете подаваться в другом году или захотите без года, уберите его: «I graduated from Kazan Federal University with…».
- **Бакалавриат.** В эссе сказано, что бакалавриат тоже в КФУ — если это не так, поправьте название вуза.
- **Вторая статья.** Оставлена как «submitted and under review» — держите формулировку только если это действительно так.
- **Свидетельство о госрегистрации программы для ЭВМ** — в тексте стоит как *план* («I plan to prepare»). Если сертификат уже получен, переформулируйте в завершенный факт.
- **Репозиторий.** «Open repository of the university» — при желании добавьте ссылку `git.kpfu.ru/RusFDavletshin/shafinMultitool`.
- **Направление 2.3.1.** В эссе направление указано словами («information technologies and telecommunications»). Учтите: в номенклатуре специальностей 2.3 — это группа «Информационные технологии и телекоммуникации», а 2.3.1 официально называется «Системный анализ, управление и обработка информации, статистика». Если на экзамене попросят точную формулировку, лучше назвать официальное название специальности с сайта КГЭУ.
- **Планы (раздел 11).** Это черновик вашей будущей программы исследования. Согласуйте его с будущим научным руководителем; «техническая диагностика и мониторинг энергетического оборудования» — пример переноса методов, при желании замените на конкретное направление кафедры КГЭУ.

## Совет по формату экзамена

Готовая сжатая версия уже есть выше — раздел «Short exam version» (~700 слов, все 10 пунктов + планы на будущее). Она рассчитана на реальное время письма; полная версия — для заучивания формулировок и устного ответа.

Если времени на письме мало, сокращайте полную версию в таком порядке: (1) уберите разделы 2 и 7 до одного предложения каждый, (2) объедините 5 и 6, (3) оставьте в разделе 8 только статью и одну метрику по генерации сцен и одну по анализу кадра. Все цифры и термин «SceneScript» лучше произносить точно — они показывают владение профессиональной лексикой.
