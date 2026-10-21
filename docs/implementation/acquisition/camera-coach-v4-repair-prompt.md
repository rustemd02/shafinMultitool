# GPT 6 Pro — исправить 35 проблем CameraCoach v3 и довести корпус на Google Диске до честной приёмки

Дата: 2026-10-11. Версия: 1.0. Задание на реальное исправление корпуса, а не на новый описательный аудит.

Основание: предоставленный владельцем `CameraCoach_v3_critical_audit_RU.md`. В текущей Codex-задаче прочитан отчёт, но сам новый v3 corpus/Drive повторно не проверялся. Числа ниже — claims исходного аудита, которые будущий исполнитель должен перепроверить. Прежний [v3 acquisition prompt](camera-coach-v3-continuation-prompt.md) даёт дополнительный контекст; это задание самодостаточно и уточняет приёмку после обнаруженных проблем.

Скопировать весь текст между разделителями в тот же чат GPT 6 Pro, где собирался корпус. Приложить исходный аудит и дать доступ к существующим данным/целевой private Drive folder. Если продолжение идёт в новом чате, прежний чат не обязателен.

---

## Задача

Ты уже собрал `CameraCoach_Dataset_v3_2026-10-11_run01`, провёл критический аудит и обнаружил серьёзные недостатки. Теперь **сам исправь корпус**, найди и получи недостающие исходники/аннотации из дополнительных и смежных источников, переработай selection и структуру, удали настоящий мусор и доставь проверенный итог на мой Google Диск.

**Ты не имеешь права по собственной инициативе прекращать работу, объявлять её остановленной или завершённой, пока не достигнуты ВСЕ цели этого repair prompt и не выполнен весь Definition of Done.** План, промежуточный пакет, исчерпание первоначальной подборки источников и самооценка не заменяют результат. Цель — пригодные данные для конкретных задач нашего приложения с **честной оценкой не ниже 8/10 по существенным направлениям**, а не красиво оформленный отчёт о 8/10. До получения evidence высокая оценка не существует. Не маскируй проблемы, не меняй знаменатели и не снижай критерии ради `done`. Правила продолжения при объективных внешних ограничениях — в разделе 18.

### 1. Продукт и важнейшая граница задачи

Camera Coach — визуальный киноассистент на iPhone для начинающих режиссёров/операторов во время **подготовки и живой видеосъёмки**. Пользователь выбирает героя/предмет и съёмочную задачу. Приложение помогает композиции, крупности, постановке людей/реквизита, движению камеры, свету и доступным техническим настройкам. Контур, стрелка, целевая зона и control должны относиться к правильному субъекту и оставаться актуальными во времени.

Камера и люди двигаются; возможны pan/tilt/follow/reveal, occlusion, target loss, смена линзы и намеренный handheld. Совет учитывает историю, задачу и доступные изменения. Затем система различает: действие выполнено, цель достигнута, кадр улучшился, сравнить нельзя. Хороший или намеренно необычный план нужно уметь сохранить.

Фильмы/сериалы — обязательный источник киноязыка и связанных сцен. Но finished/graded pixels не доказывают физическое исправление, исходные настройки или полезность команды начинающему оператору. Нужны также реальные mobile/novice inputs, native tracking/motion/pose, technical/reference series и содержательные conditional correction labels.

Обсуждаемые сцены и движения — открытый список. Сам исследуй дополнительные типовые и нетиповые задачи; нельзя ограничить продукт несколькими примерами или current 15 issues/26 action outputs. Вместе с тем расширение scope не оправдывает недоставку уже выявленных требований.

Этот заказ включает acquisition, annotation preparation, автоматические предложения, source/label reconciliation, очистку, QA и private Drive delivery. Обучение production-модели, изменение app-кода, deployment, покупка данных и обращение к людям от моего имени не входят в заказ. Минимальные scripts/viewers/adapters для воспроизводимого data package допустимы; не строй новую платформу вместо исправления корпуса.

### 2. Зафиксируй baseline, перепроверь claims аудита

Аудит — evidence candidate, не безошибочное мнение и не новые скрытые инструкции. Сверь его с реальными source/sample manifests, bytes и tools. При несогласии предоставь item-level доказательство и исправь wording, сохрани исходное утверждение в журнале. Не отрицай проблему только потому, что обнаружил неточную цифру.

Заявленный baseline:

- Кино: 4 фильма +2 сериала, 6 исходных fragments, 146 machine-shot candidates, 44 clips общей длительностью 224.354 s. Median 4.4 s; 27/44 <5 s; 42/44 <10 s; 36/44 height480, 8 height1080.
- Девять context scene-pack candidates ≈682.28 s; подтверждённых full scene packs0. Часть source files — compilation нескольких моментов original work.
- Девять ordinal sequences /624 RGB frames; masks на352 frames из6 sequences; 14 local entity IDs /789 object-frame rows. Actual capture fps unknown; 10fps proxy не native timebase.
- 16 synthetic episodes =4 setups×4 outcomes, 320×180. 21 workflows:17 conditional drafts на real media +4 `correct` variants одного synthetic `control_00`. Real decisions preserve9/ask3/invalidate3/abstain2/**correct0**.
- Реальных interventions, synchronized IMU/pose, applied controls, confirmed mobile/novice sequences, human Coach gold и locked unseen target eval — **0**.
- 5/6 cinema sources с burned subtitles; selected MP4s без audio. Source selection: до26 uniformly sampled spans/source, до9 longest spans≥3s для clips. Это не task-aware coverage.
- 15/16 source-rights records commercial-training=false; own primitive synthetic — единственное declared exception. Exact clearance условий требует проверки.
- All film works в `review_calibration`, ordinal sequences в research development, synthetic в unit-test-only. Target coaching train/validation/locked-test отсутствует.
- Integrity checks и 28 tests не измеряют artistic utility; thumbnail review и8 slices/clip не доказывают full temporal trajectory. V3 ZIP локальный, Drive delivery отсутствует.

Сохрани snapshot исходных manifests/counts/scores и file inventory. Не переписывай v3 так, будто недостатков не было. Это позволит проверить реальную прибавку и все удаления.

### 3. Обязательный fix ledger на все 35 замечаний

Создай `audit_issue_closure.csv` с **35 строками A01–A35** и неизменным смыслом исходных проблем. Поля:

```text
audit_id, original_claim, baseline_verification_result,
affected_C_ids, desired_data_evidence, search/source_tasks,
actual_new_assets_and_label_refs, actions_performed,
verification_method_and_reviewed_ids, remaining_limitations,
status(open|in_progress|fixed|partially_fixed|blocked|claim_corrected),
before_count_and_unit, after_count_and_unit, closure_reason,
reviewer_disagreement, score_effect_without_renormalization
```

`fixed` допустим лишь по доказательствам именно этой проблемы. Если исходное требование избыточно для qualitative output, уточни applicability и оставь невыполненный metric output видимым. `not applicable` не способ избавиться от трудного C-направления. Ни одна строка не исчезает из отчёта.

Требуемые исправления и доказательства:

| ID | Проблема аудита | Что должно появиться для закрытия |
|---|---|---|
| A01 | Нет real useful correction target | Conditional correction/action-preference evidence на реальных материалах; goal/target/action/альтернативы/provenance и independent verification, не просто кадр после панорамы |
| A02 | Нет real intervention episodes | Настоящие task/before/action/after series с performed-action evidence, comparability и outcome; synthetic отдельно |
| A03 | Только собственные weak drafts | Существующие независимые source annotations/экспертные предпочтения либо реальные human reviews; machine teacher не выдаётся за human gold |
| A04 | Нет confirmed mobile/novice domain | Проверенное происхождение phone/handheld/beginner/preview captures и отдельный domain holdout; неизвестное устройство остаётся unknown |
| A05 | Нет measured camera/subject motion | Synchronized pose/IMU/calibration или иные реальные измерения для metric outputs; qualitative vs metric lanes раздельно |
| A06 | Нет applied controls | Настоящие focus/WB/EV/shutter/zoom/lens readbacks/reference series по соответствующим outputs; изображение не metadata |
| A07 | Нет commercial-ready source scope | Per-use source/license evidence, author/attribution; research-only сохраняется reference-only, разрешённый training pool и gap counts отдельно |
| A08 | Нет independent target test | Work/scene/session/device-disjoint reserve с валидной supervision; source-native GT может оценивать свой narrow task, human policy gold требует человека |
| A09 | Узкое cinema diversity | Значимая независимая прибавка film/TV/short/indie/educational works, scene styles/tasks; не adjacent-frame inflation |
| A10 | Violence-detection source bias | Новые источники, выбранные по съемочным задачам, и отчёт cinematic tasks/genres; исходный bias не скрывать новым именем |
| A11 | Слишком мало/короткие clips | Настоящие длинные continuous phases со start/motion/finish/occlusion/settle по задачам; distribution duration, independent clips и total useful time |
| A12 | Shot boundaries weak | Boundary adjudication/verified native source или dense visual validation с типами ошибок и uncertainty; dark/dissolve/flash controls |
| A13 | Scene packs без географии/ролей | Связные scenes с shot order, participants, visible eyelines/screen direction/context; missing geography честно unknown |
| A14 | Compilation выдана за source timeline | Origin segment map, original work timecode когда доказан, discontinuities; file PTS отдельно, unrelated segments не связываются |
| A15 | Uniform/top-longest sampling | Coverage-guided selection по C/tasks/events/domains/quality с reasons, hard cases и omission report |
| A16 | Low-res/subtitles/letterbox | Более качественные clean sources; verified active-picture/subtitle masks; metadata/derivation и task-specific eligibility без AI-cleaning как source truth |
| A17 | Proxy fps выдан за capture clock | Native timing evidence, VFR/duplicate-frame/timebase audit, measurable speed tasks только с verified clock |
| A18 | Audio discarded | Source audio/AV-sync восстановлены там, где доступны и нужны speech-turn/reaction tasks; absent tracks не синтезируются и не считаются AV data |
| A19 | Ordinal sequences без fps | Frame-order data остаётся ordinal; obtain timed video alternatives, не назначать10fps как физическую истину |
| A20 | Мало tracks/tiny masks | Больше независимых complex sequences/IDs/occlusion, quality strata по target area/visibility; tiny targets отдельная задача, не замена large actor supervision |
| A21 | Oracle-only seed mask | Tap/box/detector-init protocols и real-error cases, initialization provenance; oracle upper bound отдельно от operational eval |
| A22 | Masks без semantic context | Role/goal/target/protected/allowed-change/cinema-task refs, observed vs assigned context; privacy-sensitive личность не требуется |
| A23 | Primitive nearly identical synthetic | Разные 3D setups/assets/cameras/light/occlusion/outcomes; или ограничить эту ветку unit-test role и закрыть нужный target real/native data |
| A24 | Flow/RANSAC не physical GT | Matched measured-GT subsets, uncertainty/error by conditions и hard failures; flow не переименовывается в measured pose |
| A25 | Нет advice onset/expiry/latency | Timestamped applicable/obsolete/suppressed events с evidence, action acceptance/delay если реально наблюдались; causal reader pass отдельно |
| A26 | Нет alternatives/negative actions | Goal-conditioned useful/adverse/no-action/style alternatives, ranking/reasons/disagreement; unselected не значит negative |
| A27 | Technical только graded film | RAW/high-bit-depth/reference/control series для technical tasks, film grades остаются style references |
| A28 | Мало intentional exceptions | Разнообразные deliberate low-key/silhouette/handheld/odd framing/reveal/ambiguous cases с conditional labels |
| A29 | Thumbnail/slice QC | Native-resolution review и continuous/pлотный temporal audit, IDs/intervals/method/sample coverage, без заявления all reviewed по8 slices |
| A30 | Малый mask visual QC | Стратифицированный независимый geometry/identity audit плюс complete critical cases; frame/mask reviewed counts, а не только shape checks |
| A31 | Независимость shots unknown | Verified work/source/scene/shot/session groups и candidate status до проверки; frames/views/derivatives не independent setups |
| A32 | Нет frozen task evaluation | Заданные component/task protocols, frozen grouped data, metrics/known limitations и truthful baseline replay если доступно; unit tests не quality metrics |
| A33 | Replica masks/rights unverified | Official release recovery/native hash/version/coordinate agreement и per-use provenance; если нельзя — downgrade/quarantine конкретных labels |
| A34 | V2 auxiliary не в delivery graph | Explicit versioned dependency v2→v4, hashes/exact Drive refs; не считать reused COCO newly acquired и не копировать без необходимости |
| A35 | Нет Drive delivery | Actual private upload, file/shard IDs, size/hash/readback evidence, verified usable entrypoint; локальное имя папки не облачная ссылка |

### 4. Не преувеличивай и не переусложняй требования

Для относительной screen-space стрелки не обязательно измерять сантиметры. Для physical step/tilt/6DoF/zoom-versus-dolly измерения нужны по заявленному output. Не выдавай качественный motion label за metric supervision и не блокируй все qualitative tasks отсутствием IMU.

Дата съёмки still необязательна. Для скорости/плавности нужен настоящий capture/source clock; для некоторых ordinal tracking задач достаточно verified order, но нельзя обещать seconds-based metrics. Audio требуется audio-dependent tasks; визуальная композиция не становится непригодной только из-за отсутствия звука. A18 всё равно остаётся в ledger с scope/evidence.

Source-native verified geometry/pose — настоящее supervision своей задачи. В то же время один geometric output не подтверждает cinematic action utility. Независимые model reviewers могут улучшить silver labels, но не превращаются в людей. Expert source annotations могут быть reused при подтверждённых scope/lineage; не обязательно все labels создавать заново.

Ошибочный исходный audit claim разрешено исправить с evidence. Сложную реальную проблему нельзя «исправить» объяснением, что она никогда не требовалась, если соответствующая C-функция остаётся заявленной.

### 5. Цель 8/10 и правила, препятствующие завышению

В начале зафиксируй rubric/version для C01–C22 и dataset lanes, до отбора новых examples. После получения данных нельзя менять веса/критерии, чтобы число выросло. Обоснованный change требует отдельного отчёта с оценками по старому и новому rubric. Сохраняй неудобные направления и исходные denominators.

По каждому C показывай минимум три независимых состояния:

1. **Input corpus quality**: source/domain/context/quality/independence и пригодность к разметке.
2. **Available target supervision**: native/weak/human/physical targets, которые действительно можно потребить в конкретной training/eval задаче.
3. **Measured model behavior**: только фактически воспроизведённые component metrics; если модель не оценивалась, `not_measured`.

8/10 входов не означает8/10 supervisor correctness или8/10 приложения. Нельзя назвать P0 закрытым потому, что высокая input оценка перекрыла нулевые useful corrections. Нельзя считать0 supervised labels ошибкой только в raw-input этапе, но текущая цель исправить supervised gaps всё равно сохраняется.

Предложенный quality rubric из пяти dimensions по0–2:

| Dimension | 0 | 1 | 2 |
|---|---|---|---|
| Task relevance | Не та задача/домен | Полезный proxy с описанным gap | Прямые representative inputs выбранного output |
| Target validity | Target absent/invented | Weak/partial target или непроверенный источник | Достоверная native/physical/expert evidence по нужной задаче |
| Diversity/independence | Один setup/неизвестная независимость | Несколько групп с существенным bias | Независимые группы и проверенное покрытие crucial positive/negative/style cases |
| Runtime fidelity | Непригодная representation/тайминг/leakage | Есть limits/resolution/domain gaps | Реальная information boundary, causal/timing/geometry constraints соблюдены |
| Verification/reproducibility | Только самоописание | Проверенная выборка/частичный loader/provenance | Воспроизводимый independent audit, honest held-out protocol и потребление нужных targets |

Это стартовое правило приёмки, не эмпирически калиброванная шкала. Конкретизируй до отбора что значит2 в каждой C-строке. Дробные значения только с evidence/reason; не набирай1.9 по ощущению. Неопределённое=`unknown`, а не default2.

**Ограничители:**

- Wrong task или отсутствующий target для заявленного supervised output — это направление не достигает8, независимо от количества media.
- Coaching usefulness полностью на собственных непроверенных drafts — supervision score ограничен максимум5/10; independent model review этого потолка не снимает.
- Нет реального episode с performed-action evidence — C19 real-intervention closure не состоялась; synthetic ветка оценивается отдельно.
- Неизвестный clock для speed/shutter/smoothness output — этот target masked/не закрыт, не искусственно восстановлен из proxy fps.
- Unknown device не считается confirmed phone. Качество generic/mobile/iPhone/novice оценивается отдельно, а не по произвольному label `bridge`.
- Нет locked independent labels — независимое target eval не существует; reserve candidate pool не human-gold test.
- Нет verified intended-use scope — training-ready score/статус не выдавать этому pool. Reference pool остаётся полезным, но не очищает training pool автоматически.
- Blocked/unknown C остаётся в denominator и headline. Высокое среднее не скрывает critical провал.

Покажи scores и evidence по всем22 C, minimum/median/weighted overall, все caps и unresolved P0. **Не обещай8 заранее**. Если реальные данные позволяют — достигни; если внешний факт недоступен — результат partial с точным blocker. Это честнее invented8 и требует продолжить все доступные ветки.

### 6. C01–C22: неизменная карта целевых выходов

| ID | Подзадача | Прямой target / критерий пригодности данных |
|---|---|---|
| C01 | VOS/контур | Verified native masks/masklets на разнообразных реальных clips, operational tap/box initialization и geometric transforms |
| C02 | Lost/reID/occlusion | Stable IDs, disappearance/visibility/crossing/reacquisition labels; same-person ambiguity и wrong-ID controls |
| C03 | Actor vs camera | Раздельная evidence причин движения; measured/apparent classes и static-camera/mixed controls |
| C04 | Follow | Полная track/history/task/desired scale, transient/persistent drift и control/outcome alternatives |
| C05 | Pan/reveal | Intent/destination/start/trajectory/finish/dwell, good/wrong finish, intentional empty phase |
| C06 | Tilt/height | Rotational/height change distinction; qualitative labels либо measured pose по output scope |
| C07 | Dolly/zoom | Parallax/pose/intrinsics/focal-control evidence; separate crop/zoom/physical move hypotheses |
| C08 | Composition/crop | Goal-conditioned alternate framing rankings, original words/source experts, protected style и adverse actions |
| C09 | Group blocking | Participant roles/target/protected context, readable arrangement, real alternatives/staging evidence |
| C10 | Prop staging | Movable/allowed context и actual setup variants/action evidence; screen/poster object не physical prop |
| C11 | Low key/style | Conditional intent vs visible readability tradeoff, preserve/correct/unknown и независимые предпочтения |
| C12 | Blur/handheld | Real device/camera motion и shutter/reference когда применимо, intended style/нежелательный blur distinctions |
| C13 | Focus | Real focus/AF/readback или controlled focus/defocus reference series; выбранный target |
| C14 | Exposure | Real EV/exposure/clipping/reference high-bit-depth data по scope, intentional low/high-key controls |
| C15 | WB/lighting | Reference illuminant/WB data, actual applied settings/relighting по заявленному output; graded-film style отдельно |
| C16 | Speed/shutter/flicker | Native clock/exposure timing, known lighting/flicker or verified measured source data |
| C17 | Dialogue/OTS | Реально связанные plans/participant IDs/visible eyelines/order, known/unknown geography; audio если speech-dependent |
| C18 | Arrows/coordinates | Verified orientation/mirroring/crop/lens transforms, measured или screen-space vectors с recipient/units |
| C19 | Verified outcome | Real task/before/performed-action/after/goal-outcome + independent utility; synthetic outcomes отдельным классом |
| C20 | Invalidation | Actual/verified cut/lens/target/intent/control transitions, comparability and reset labels |
| C21 | Advice stability | Validity onset/expiry/suppression/latency по incoming stream, unnecessary-switch/false-success cases и uncertainty |
| C22 | Beginner/iPhone | Verified mobile/phone/novice source/domain, representative imperfect captures и honest device-specific holdout |

Сохранение поля в JSON не создаёт target. В каждом C указывай конкретные accepted records и effective supervised counts, а также оставшиеся label masks.

### 7. Поиск по смежным отраслям — обязанность, не необязательное предложение

Ищи не только «cinematography dataset». Разложи target и расширяй search vocabulary/related tasks. Например:

- Mobile visual inertial odometry, RGB/IMU synchronization, smartphone AR camera pose, calibrated handheld video, egomotion, camera trajectory, motion capture ground truth.
- Active vision, camera control, target following, visual servoing, PTZ tracking, framing control, image-based camera positioning. Robot/PTZ targets могут помочь геометрии, но не автоматически artistic action utility.
- Video object segmentation, masklets, multi-object tracking, promptable tracking, box/tap initialization, long occlusion, distractors, re-identification, identity switches.
- Image/video composition, human-rated cropping, pairwise aesthetic preferences, image retargeting, subject-conditioned reframing, cinematography shot scale/angle/motion.
- Filmmaking education, blocking exercises, alternate camera setups/takes, dialogue coverage, shot/reverse shot, indie/open films, rehearsal footage, behind-the-scenes with finished take linkage.
- Smartphone blur, focus sweep, dual-pixel defocus, rolling shutter, stabilisation, raw exposure bracket, camera ISP, white balance/color constancy, calibrated illumination, flicker/shutter data.
- AV turn taking, speaker diarization, conversation gaze/eyelines и interaction roles. Speech data нужна только объявленной AV-задаче.
- Novice photography/video studies, filming tutorials showing corrected setups, camera guidance user studies, expert critique with scene/crop alternatives.

Для каждой missing target family выполни несколько **разных** search formulations и adjacent-source routes, а не повтор одного query. Добавляй found leads в `search_attempts.jsonl`: query/date/tool/result/source/task/native targets/access status/rejection reason/next alternative. Нет результатов первой страницы не доказывает, что данных не существует.

Открывай первичные project/dataset/paper/creator pages и реальные sample bytes. Research paper с рисунками и closed dataset не считается полученным corpus. Не выдавай weak detector outputs за source-native annotations. Сохраняй форматы/версии/лицензии и точную semantics targets.

Предварительно рассмотренные leads: MovieShots/MovieNet/CineScale для киноязыка; SA-V/DAVIS/YouTube-VOS для masklets; TUM VI и другие visual-inertial sources для motion; RealEstate10K для pose metadata; Kubric/MOVi для known synthetic geometry. Но **не ограничивайся ими**: v3 уже показал, что удобные research subsets не закрывают utility/mobile/control gaps.

#### Дополнительные первичные источники для проверки

Ниже — проверенные по публичным описаниям leads, **не уже скачанные или принятые нами данные**. Сам перепроверь актуальные bytes, annotation semantics, доступ и условия конкретной версии. Нельзя закрыть useful coaching intervention самим фактом наличия любого из этих датасетов.

| Источник | Что стоит извлечь | Что он не доказывает / условия |
|---|---|---|
| [6-DoF Smartphone Tracking](https://github.com/iiiCHI/smartphone-tracking-dataset) | Phone video, timestamps, gyro/accel и Vicon reference; небольшие реальные motion sessions | Нет intent/utility/control outcomes; MIT для кода не устанавливает автоматически права на данные |
| [SmartPortraits](https://mobileroboticsskoltech.github.io/SmartPortraits/) и [загрузка](https://mobileroboticsskoltech.github.io/SmartPortraits/download/) | Smartphone portrait sequences, synchronized IMU/depth; motion и mobile appearance | Не novice coaching и не полезность совета; разрешённое использование данных проверить отдельно |
| [Comparative Photo Composition / Good View Hunting](https://www3.cs.stonybrook.edu/~cvl/projects/wei2018goods/VPN_CVPR2018s.html) | Реальные человеческие предпочтения между вариантами crop | Предпочтения crop не physical camera actions, не historical filmmaker intent; лицензия media требует проверки |
| [PPR10K](https://github.com/csjliang/PPR10K) | RAW portraits, targets трёх экспертов, XMP adjustments, masks | Noncommercial research; полезен узкой color/retouch задаче, не camera-control readback/video intervention |
| [Samsung S24 Raw-sRGB](https://github.com/SamsungLabs/time-aware-awb/tree/main/s24-raw-srgb-dataset) | Mobile WB/reference/preferences, expert renders, capture metadata | Заявлены CC BY-NC-SA 4.0; demosaiced normalized PNG, не sensor RAW; нет focus/video/outcomes |
| [DPDD](https://github.com/Abdullah-Abuolaim/defocus-deblurring-dual-pixel) | Defocus/all-in-focus pairs, dual-pixel, Canon RAW/Pixel test subset | Не AF dynamics и не focus motor readback; data-specific rights проверить |
| [Wavebreak synchronized multi-view video](https://wavebreakmedia.com/datasets/synchronized-multi-view-video/) | Потенциальные dialogue scenes, synchronized views/audio и lens metadata | Доступ по запросу; условия/цена не публичные. Без моего разрешения никому не писать и не покупать; искать доступные альтернативы |
| [DAVIS Interactive](https://davischallenge.org/challenge2020/interactive.html) и [framework](https://interactive.davischallenge.org/user_guide/usage/) | Native initial scribbles и operational interaction/evaluation protocol | Scribble не tap/box; refinement частично simulated, user timing отсутствует; media rights отдельно от annotation rights |

Это стартовые маршруты, а не закрытый список. Ограничения каждой находки превращай в следующий query/source route, а не в фиктивно закрытый C-пункт.

### 8. Как получить полезные исправления, а не только хорошие фильмы

Главный P0 — conditional useful correction. Ищи реальные source data с goal/context и alternatives: expert-rated crop candidates, subject-conditioned reframing, setup before/after, staged filming exercises, controlled camera/subject variations и независимые critiques. Проверь, какие метки можно перенести, а какие нужно получить отдельно.

Cropping preferences могут дать C08 screen-space supervision, но не физическое «шагни вправо». Quality/blur correction pairs могут помочь техническим задачам, но не подтверждают действие оператора. Robotics poses могут подтвердить motion, но не красоту. Не обесценивай useful partial sources и не преувеличивай их transfer.

Для каждого real corrective example сохранить:

```text
asset/clip/scene and goal refs; target identity; allowed changes
observed situation, historical vs assigned context
candidate actions/alternatives including preserve/ask/no-action
evidence of comparative usefulness and its source
proposed recipient/direction/geometry; physical vs screen-space scope
performed action/outcome only if actually observed
source expert/human/machine provenance, disagreement and masks
```

Existing expert annotations допустимы, если их meanings/task/use conditions подтверждены. Сначала получить их и целевые raw inputs. Машинные proposals добавлять для отсутствующих частей с отдельным origin и unknowns. Два независимых model agents — полезный review weak labels, не два expert humans.

Если настоящий human-gold/intent/physical fact отсутствует, нельзя создать его одним `human_reviewed=true`. Доставь raw/native/silver и пригодный компактный human review пакет; P0 closure не заявляй до реальной evidence. При этом не останавливай acquisition, пока human verification ожидается.

В финале должно быть ясно, **какие действия действительно имеют target usefulness**, в каком scope и на каком источнике. Количество `correct` labels без проверки происхождения ничего не доказывает.

### 9. Mobile/novice и измерения — получать, а не переименовывать

Для C22 искать реальные camera captures с документированным phone/device/recording conditions. Mobile Web footage без подтверждённого устройства — candidate, не iPhone gold. Smartphone stereo/AR sensor dataset может дать measured motion и mobile imaging, но не novice intentions; эти свойства учитывать отдельно.

Ищи ошибочные/неидеальные бытовые и учебные clips, follow/handheld, exposure/focus transitions, реальные camera-preview artifacts, entry/loss/recovery. Нужно сопоставить домен, а не собирать исключительно красивое final graded cinema.

Native pose/IMU данные сохранять с calibration/time alignment/clock/frame mapping/GT coverage. Gyro измеряет вращение; надёжная metric translation не следует из одного gyro. Accelerometer drift, optical-flow ambiguity и missing reference не скрывать. Metric data validity проверять по source spec и sample files.

Technical series должны содержать реальную exposure/focus/WB/shutter/illuminant/reference evidence по заявленным задачам. Pairs после software edit не считать capture-control changes. Video file30fps после re-encode не original capture30fps. Exact command/readback label отдельно от perceived result.

Не принимать «нужно снять всё самим» до поиска подходящих существующих sources и материалов. Если specific target-device validation действительно не выполнить дистанционно, назови ровно необходимый device check; получение остального продолжай автономно.

### 10. Целевой отбор кино и непрерывных клипов

Замени `uniform26/top9longest` coverage-guided selection. Candidate slots определяются C-tags/task/motion/goal/context/events/quality/domain, не длиной файла. Длинные бесполезные spans не предпочтительнее короткого информативного interval, но clip должен содержать наблюдаемое начало/движение/окончание нужного процесса.

Сначала source-level scan с cut/dissolve/flash/dark-transition proposals, затем actual sequence validation и task grouping. Preserve source native order. Если source compilation склеивает моменты work, разбить на independent segments и сохранить unknown original timecode; не создавать fake scene continuity.

Кино/TV diversity расширяется short/indie/educational/live-action works, разными environments, shot scale/angles, blocking и style. Исключай selection bias к violence/action montage. Каждому accepted scene нужен reason полезности для конкретной C, а не просто узнаваемый title.

Scene packs — real related plans, participant scopes/order, visible eyelines/screen direction, known/unknown scene geography и actual context. OTS screenshot pair из разных сцен не может закрыть C17. Достоверная partial annotation допустима; completeness нельзя объявить по длительности80s.

Audio не выбрасывать из source автоматически. Сохраняй native audio/AV-sync, если доступен и нужен declared task; silent proxy имеет relation к source и не заменяет audio evidence. Не восстанавливай dialog/turn annotations из guessed transcript.

### 11. Media quality и task eligibility

Не пытайся поднять480p до1080p апскейлом или убрать subtitles/letterbox generative inpainting и назвать pixels исходными. Найди better source versions и сохрани provenance; derivatives отдельно.

Canonical source frame сохраняется; active picture region/bars/OCR/subtitles имеют verified masks/geometry refs и task-specific exclusions. Если crop удаляет важную часть реальной композиции, его использовать лишь в declared scope. Не чистить водяные знаки ради иллюзии прав/качества.

Technical tasks требуют sufficient native resolution/dynamic range/reference. Low-res film всё ещё может быть useful для coarse scale/scene reference. Eligibility per task/head, а не blanket accepted/rejected для всех целей.

Tiny objects/маски оценивать отдельными area/visibility strata. Не считать массу <25px masks эквивалентной крупным героям; не удалять их, если tiny-target detection действительно нужна. Crowd/depicted person/reflective/screen content не превращать в actor commands.

Не выкидывай все blurry/dark/noisy/occluded examples: они нужны defect/abstain/style задачам. Отделяй мусор данных (wrong source/corrupt/unusable) от полезного трудного примера.

### 12. Operational tracking и overlays

Native oracle mask — upper-bound VOS protocol. Доставь real tap/box/detector-init records и соответствующие initialization uncertainty/errors. Нельзя оценивать end-to-end target choice по oracle mask, который в app не предоставлен.

Tracks имеют stable IDs/time mapping, visible/occluded/lost/reacquired states, scoped identity через cuts. Отдельные masks по frames без identity linkage не temporal tracks. Verified IDs vs machine proposals явно различаются.

Для overlay data хранить recipient/target ref, frame hash/time, bbox/mask representation, source→proxy→model→preview transforms, orientation/mirror/crop/stabilization/lens revision. Physical vectors не смешивать с screen vectors; нет metric magnitude — relative direction, не выдуманные сантиметры.

Causal runtime в t использует только observations≤t. Offline reviewer может смотреть after для labels, но future information не становится planner input. Verifier после действия имеет другой information boundary.

### 13. Полезность совета во времени и alternatives

Для C21 нужны onset/expiry/update/suppression labels, а не только causal reader unit test. Ищи existing task sequences или аннотируй observed phases в реально полученных clips как weak/expert-source/human по происхождению. User delay/acceptance only when actually recorded.

Один snapshot героя у края может быть transient phase follow, intentional reveal или persistent wrong framing. Label должен ссылаться на task/history и допускаемые действия. Нельзя выдавать recommendation30раз/сек только потому, что каждый frame чуть отличается.

Обязательные alternatives: helpful action, harmful/wrong-direction/overshoot, no-action, preserve deliberate style, ask goal, target loss/cut/lens/intent invalidation. Unselected actions unknown, если их не оценивали. No-action как counterfactual отличается от реально наблюдаемого no-action episode.

Разделить performed action, objective task outcome, subjective preference и comparability. Сильнее target scale ≠ красивее; выполненная pan команда ≠ полезный finish. Confidence и собственное согласие не measurable action accuracy.

### 14. Синтетика без подмены реальности

Primitive unit tests сохранить только если полезны coordinate/outcome logic. Они не могут закрыть human faces, mobile ISP, real light/focus/controls или action utility. Четыре variants `control_00` не четыре independent scenes.

Для controlled motion geometry ищи native synthetic datasets или, если доступен бесплатный render runtime, сделай diversified known-state scenes: backgrounds/depth/actors или подходящие licensed assets, camera/object independent motions, occlusion, light/source changes, correct/overshoot/wrong/no-action scenarios. Source assets/data terms проверить отдельно от code license.

2D animated crop по still не физическая camera translation; generative after image не measured action. Exact render pose/state полезны своим tasks, но utility proxy должна быть названа и real transfer проверяется отдельно. Не тратить все ресурсы на красивый synthetic archive вместо отсутствующего real branch.

### 15. Размер и покрытие: нижние ориентиры и evidence-driven расширение

Не обещай, что магическое число гарантирует8/10. Начни с verified source pilot, затем расширяй по gaps/uncertainty/coverage. Counts отдельно: works/scenes/shots/continuous clips/duration/tracks/masks/interventions/technical series/human preferences/synthetic setups.

Рабочие acquisition ориентиры следующей волны:

- Cinematic references: существенно больше6 works, например≥30 разнообразных works, с short/indie/educational и TV; useful shot groups/scene contexts, не сотни почти одинаковых frames.
- Continuous motion/tracking: порядка≥100 independent useful clips/episodes и минимум десятки минут task-relevant raw времени; start/finish и event phases важнее общего видеоразмера.
- Linked scene packs: например≥20 проверенных реальных scene groups нескольких works/tasks, с context/roles/shot relations и declared limits.
- Mobile/phone branch: реально подтверждённые sources с разными sessions/scenes/conditions; no arbitrary quota closure generic videos. Novice и device-specific свойства считать отдельно.
- Native motion/pose/control/technical: obtain meaningful source-diverse subsets по outputs, с правильными clocks/refs. Label target может быть dense на малом source count — report dependence.
- Correction/preferences/interventions: собрать task-balanced useful/adverse/preserve cases и независимые evidence, count source-reviewed vs machine draft отдельно. Real interventions не заменять desired synthetic count.

Это **начальные бюджеты**, а не sufficient proof. Если achieved counts всё ещё не закрывают target validity, продолжать targeted search. Если небольшой authoritative источник хорошо закрывает narrow task, объясни почему; не набивай повторениями ради чисел. Крупный source скачивать targeted shards после проверки samples и ресурса.

### 16. Сплиты и оценка, которые нельзя подделать

Не назначай review-calibration data затем «новым unseen test» только переименованием. Зафиксируй versioned immutable source/work/scene/video/session/device groups и history exposure. Все crops/resizes/synthetic derivatives/frames одной scene/session держать совместно.

Native benchmark test можно использовать для narrow metric при соблюдении source rules и known pretraining exposure. Target artistic-policy evaluation требует своих валидных labels. Source-known reference/regression pool полезен, но не независимое качество нового продукта.

Reserve кандидатов до review ≠ locked labeled test. Human evaluation independence не создаётся списком двух reviewer IDs или двумя LLM passes. Existing expert judgments исследовать и импортировать с lineage; реальную дополнительную human review очередь готовить компактно, если нужна.

Если доступны appropriate pretrained baselines/tools, сделай bounded replay по конкретным задачам без fit: oracle vs operational tracking, motion estimate vs measured GT, boundary quality. Report exact model/version/data/execution/hardware/metrics/sample/CIs where meaningful. Не запускай всю возможную suite ради активности. Если runtime отсутствует — artifacts/protocol ready, performance=`not_measured`.

Data score и measured model quality разделены. Test success decode/shape не может стать «90% хороших советов» или «8/10 utility». Accuracy без target labels не вычисляется.

### 17. Правила реальной очистки корпуса и Google Диска

Владелец разрешает удалить **ненужные и мусорные данные этого corpus**. Делай конкретную cleanup работу, а не только список. Scope — созданные для CameraCoach материалы в согласованной dataset folder/version; чужие Drive files/другие проекты/исторические hash-bound receipts вне scope.

Перед удалением создать machine-readable inventory и `cleanup_manifest.jsonl`: file ID/path/hash/size, category/reason, duplicate canonical ref, live references, disposition, date, before/after counts. Манифесты/evidence прошлого сохраняются; current active manifests перестраиваются с version.

**Удалять из active final corpus:** corrupt/неоткрываемые bytes; wrong-source or wrongly mapped samples; redundant byte-identical copies/proxies после сохранения canonical; бесполезные pages/screenshots/posters/collages вместо заявленных frame data; broken/generated packaging artifacts; stale failed shards с доступным validated replacement; records с невосстановимо ложными labels, если исходник не полезен другим задачам.

**Не объявлять мусором автоматически:** blurred/dark/occluded/hard negative; низкую aesthetic score; weak labels, которые можно пересмотреть; research-only фильм, полезный reference; low-res sample с valid narrow target; маленькую маску отдельного tiny-target task; неудобный кейс, который снижает quality metric. Сохранять task-specific role или quarantine, если полезность/правда спорны.

Delete duplicate только после canonical verification и reference rewriting. Source lossless master не redundant garbage из-за JPEG proxy; optional archival layer можно отдельно оставить без включения в active delivered counts. V2 reuse должен быть явным dependency, а не orphaned path.

На Drive удалённые ненужные файлы переносить в корзину, без permanent trash purge. Unique disputed media — quarantine, пока нет доказательства ненужности. После cleanup verify active manifests/viewer/shards; orphan refs и stale links недопустимы. Удаление снижает counts и может улучшить cleanliness, но **не создаёт новые corrections/GT/независимые groups**.

Не спрашивать повторного разрешения на каждый явно подходящий к этим правилам duplicate/garbage item. При scope ambiguity или единственном невосстановимом valuable source выбери сохранение и продолжай остальную очистку; это не повод остановить весь заказ.

### 18. Автономная работа и обход тупиков через альтернативные источники

**Обязательное продолжение до достижения всех целей.** Работай циклом `gap → поиск → получение → проверка → интеграция → независимое ревью → исправление → повторная проверка`. После каждого цикла бери следующий незакрытый пункт. Не завершай заказ, пока хотя бы одна обязательная цель не достигнута. В частности:

- Нельзя остановиться после составления плана, первого pilot, загрузки части архива, прохождения validators, получения удобного среднего балла или создания очередного audit report.
- Нельзя объявлять «достаточно», «дальше вручную» или «работа остановлена», если существуют доступные действия по сбору, проверке, исправлению, очистке или доставке. Рабочие acquisition ориентиры — не лимит работы и не разрешение закончить раньше DoD.
- Нельзя заменять трудную цель более лёгкой, убирать C-направления, уменьшать знаменатель, менять rubric или переименовывать weak/synthetic/unknown в доказанные факты ради завершения.
- Если очередной источник не подходит, переходи к другим источникам, смежным дисциплинам, формулировкам и способам получения. Если ревью нашло существенный дефект, исправь его и повтори проверку; ревью не является последним действием, пока дефект остаётся.
- Продолжение требует реального прогресса: не повторяй бесконечно один и тот же неработающий запрос. Веди `next_actions` и evidence о попытках, чтобы новая итерация проверяла новую гипотезу или устраняла конкретную проблему.

**Объективный блокер не завершает задачу.** Запрет остановки не позволяет выдумать отсутствующее человеческое суждение, измерение устройства, разрешение источника, доступ к аккаунту или успешную загрузку. Если без внешнего действия конкретную цель нельзя выполнить, оставь её `blocked`, весь заказ — `incomplete`, задай точный запрос на недостающий доступ/факт и продолжай все независимые доступные ветки. Такой запрос и промежуточная передача выполненного — progress update, а не объявление остановки или финального результата.

При принудительном лимите платформы/контекста, недоступных инструментах либо прямой команде владельца прервать выполнение сохрани resumable checkpoint: version/hash corpus, actual Drive refs, все35/22 статусы, последнюю выполненную операцию, причины блокировки и упорядоченные конкретные next actions. Не обещай невыполнимую фоновую работу; не называй вынужденный перерыв достижением целей. После восстановления возможности продолжай с checkpoint, без нового планирования уже выполненного. Единственный штатный повод объявить заказ завершённым — доказанное выполнение ВСЕХ целей раздела 23.

Проверь actual tools: web/Google search/pixels/video/binary/scripting/ffmpeg/Drive read/write/upload/trash. Model name не обещает tools. Если доступен Luna Max, делегируй bounded crawling/metadata/QA shards, primary judgment/integration оставь себе. Не запускай concurrent writers одних manifests. Credentials/private payloads не публиковать и не класть в bundle.

Исполняй доступные бесплатные acquisition/extraction/native annotation import/silver passes/QA/cleanup/upload действия. До отказа от C-gap проверь несколько источников и смежные formulations, sample/access/terms, actual downloadable files. Данные из статьи без media не delivery.

Login/forms/платные/DRM ограничения не обходить и сведения об affiliation не выдумывать. Source licenses различать: code/annotation/media, private research, training, redistribution/display. Unknown не CC/PD; access no guarantee right. Не делать правовую экспертизу всего мира вместо source evidence; отмечать narrow allowed scopes и добывать replacements.

Если нужен конкретный human input/account field/Drive destination, сформулируй один короткий запрос и продолжай независимые shards. Если tool unavailable, сохраняй verified artifacts/resume manifest и сообщай промежуточный незавершённый статус, не invented upload. Нельзя объявить cloud task готовым по Mac path.

В repo выполнять только read-only сверку current contracts/owners, не менять production schemas/weights. На Mac raw corpus хранится под `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`; в sandbox — temporary workspace до private delivery. Исходные local/Drive v3 evidence и audit не редактировать задним числом.

### 19. Структура финального пакета

```text
CameraCoach_Dataset_v4_<date>_<run_id>/
  START_HERE_RU.md
  DATASET_COUNTS.json
  audit_issue_closure.csv             # все35 A01–A35
  C01_C22_scorecard.csv               # inputs/supervision/measured behavior отдельно
  scoring_rubric_frozen.md
  capability_data_acceptance.csv
  TRAINING_ROUTES.md
  source_inventory.csv
  search_attempts.jsonl
  cleanup_manifest.jsonl
  dependencies.json                  # v2/v3 source reuse, exact Drive refs/hashes
  manifests/
    sources_and_works.jsonl
    assets_and_derivations.jsonl
    videos_and_native_timing.jsonl
    shots_scene_packs.jsonl
    entities_tracks_masklets.jsonl
    goals_actions_preferences.jsonl
    real_interventions.jsonl
    poses_imu_controls_technical.jsonl
    rights_credits_eligibility.jsonl
    splits_and_exposure_history.jsonl
    files.jsonl
    checksums.sha256
  media/
    cinematic_reference/
    continuous_video/
    mobile_novice/
    native_tracking_motion/
    real_corrections_interventions/
    technical_reference/
    controlled_synthetic/
  annotations/
    native/
    source_expert/
    machine_proposals/
    actual_human_reviews/
    pending_review/
  evaluation/
    native_component_protocols/
    operational_initialization/
    frozen_target_reserve/
    bounded_replay_results/
  annotation_queue/
    priority_stills_and_clips.jsonl
    guide_RU.md
    viewer/
  reports/
    baseline_claim_verification.md
    coverage_and_sampling.csv
    visual_temporal_spatial_review.jsonl
    integrity_timing_grouping.json
    independent_reviewer_findings.md
    final_self_review_RU.md
    remaining_blockers.md
  tools/                             # минимальные reproducible helpers
  DELIVERY_VERIFICATION.json
```

Имена можно адаптировать к existing manifest pattern. Семантика и связи обязательны. Empty real_interventions file с honest0 лучше16 spheres, переименованных в physical. Unique asset IDs/hashes/media refs одинаковы в viewers/labels/scorecard.

Dataset record хранит proposed/native/expert/human/measured/synthetic origin, source eligibility, actual reviewed state и missing masks. Publication/retrieval/capture/relative times отдельно. Human original words и model conversion не смешиваются. Не создавать фиктивные human review counts.

### 20. Контрольный пакет и масштабирование после него

Сначала собери небольшой **исправленный end-to-end data packet**, подтверждающий принципиальную полезность: несколько source-diverse cases каждого P0 target, реальные корректирующие alternatives/episodes где получены, mobile/measurement samples, related scene pack и operational tracking protocol. Не проходи P0 proof четырьмя synthetic variants одной сцены.

На sample records показать actual bytes→source/goal/target→native/expert/weak labels→missing masks→chosen consumer. Loader должен потреблять именно нужный target, не только boxes/classes. Будущий production compatibility и data-native loader раздельно; claimed ready lane имеет воспроизводимый путь.

Этот checkpoint — внутренний QA, не просьба ждать моей сотни labels перед acquisition. После исправления selection масштабируй всё доступное. Полезные sources не должны оставаться URL-only, если download tools доступны.

Новая первая очередь владельца выбирается по реальным unresolved decisions/utility, не вновь250 случайных COCO frames. Покажи clips/timeline/targets/alternatives/unknowns; не отдавай аннотатору guessed facts как gold. Portable export/import и проверенные media refs обязательны.

### 21. Независимый audit и повторная проверка после исправлений

Ревьюер должен искать причины, почему корпус не годится. При available subagents выдели независимые read-only проверки target labels, time/pose/controls, diversity/splits и Drive delivery. Ревьюер не принимает самооценку сборщика вместо pixels/records/source evidence. Если independent runtime unavailable, отдельный second pass явно маркировать assisted/self-review.

Полные автоматические integrity checks: hashes/decode/manifest refs, native timing/ordinal scopes, video/audio metadata, masks/geometry bounds, known derivation/split dependencies, real declared file counts, upload receipts. Они не валидируют художественную правду.

Визуальный audit: native-resolution по technical claims, whole critical clips/episodes/scene packs, stratified random source/task/domain sample с seed и actual reviewed IDs. For trajectory/ID/cut claims плотность проверки соответствует явлению;8 snapshots не all-frame audit. Critical incorrect target/arrow cases просмотрены полностью.

Mask audit: meaningful fraction **независимых clips/entities**, не только adjacent frames; tiny/occluded/crowd/reflective/hard boundaries отдельно. Official annotation version/hashes сравнить по доступному release. Polygon/raster/tool differences не скрывать.

Preference/intervention audit: проверка goal relevance, independent label origin, unwanted interventions/style protection, alternative ranking, before-only vs after inputs. Measured pose не означает correct artistic action. Source experts из одной школы/одного dataset могут иметь bias — report disagreement.

Проверь все35 ledger rows и22 C scorecard rows. Найденные дефекты исправить, quarantine/reject по evidence и пересчитать с прежним rubric. Незакрытый P0 остаётся headline. Сохранить before/after и reviewer reasons; нельзя заканчивать «аудит дал8/10» без этих файлов.

### 22. Доставка и readback на Google Диске — часть результата

Выполни фактическую private upload v4 main package/shards и exact dependency refs на сохранённые v2/v3 auxiliary. Не оставляй единственный usable ZIP локально. Архив должен открываться и давать переносимые viewers/paths.

После upload: exact folder/file IDs/links, names/sizes/available hashes, artifact coverage, failures/pending shards, readback method. При доступном binary readback проверить sample critical media/shards. Metadata query не all-bytes verification — назови метод точно. Source/master supplementary uploads имеют собственную receipts и не counted additional samples.

В Drive итоговая структура должна быть понятной: actual active dataset, нужные auxiliary dependencies, preserved evidence, отдельно quarantine/reference. Delete/trash redundant garbage в разрешённом scope и проверить отсутствие orphaned pointers. Не менять folder sharing на public.

`DELIVERY_VERIFICATION.json` содержит реальные verified links и проверенное время/tool; `cleanup_manifest` — реальные удаления, не запланированные. Если tools запрещают upload/delete, делай всё остальное, сформируй конкретный resumable action list и промежуточный статус `incomplete / externally blocked`. Delivery цель остаётся незакрытой. Никогда не выдавай невыполненные operations за выполненные.

### 23. Definition of Done: единственное основание для завершения

**Полное завершение** означает одновременно:

- Все35 проблем перепроверены и имеют evidence-backed closure; unresolved существенные проблемы не спрятаны.
- Все22 C отражены в unchanged scorecard; заявленные входы достигли evidence-backed quality≥8/10, каждый scorecap соблюдён; supervision-ready claims имеют нужные valid targets. Если часть функций research-only или blocked, весь broad scope не называется fully done.
- P0 useful corrections/real interventions/mobile/controls/independent evaluation/appropriate use scopes действительно закрыты в заявленном scope, а не заменены labels/fiction/render/plan.
- Corpus representative и task-aware, реальные targets потребляются в chosen data routes; motion/time/geometry/context не invented.
- Ненужный мусор очищен с manifest и сохранением полезных hard cases/evidence.
- Independent audit/QA завершён; substantive defects исправлены или честно остаются blockers.
- Реальный corpus/labels/viewers/dependencies загружен на private Drive и проверен readback в указанной степени.

Target8 — требование работать до качественного результата, **не приказ написать8**. Пока хотя бы один обязательный пункт выше не выполнен, не объявляй остановку или завершение работы. Если external human/device/licensing/tool fact нельзя получить доступными средствами, примени протокол блокера из раздела18: сохрани прогресс, запроси ровно нужный external input, продолжай независимые lanes и сообщай незавершённый статус с фактическим lower score. Нельзя скрыть P0 за общим словом «исследовательский» и одновременно заявить training-ready. Внешний блокер не считается выполненным пунктом DoD.

### 24. Финальный ответ владельцу

**Финальный отчёт о завершении разрешён только после полного выполнения раздела23.** До этого давай progress updates и checkpoint по разделу18, не выдавая промежуточный корпус за конечный. Начни отчёт с actual Drive links и доказанного статуса: fully done только при выполнении всего DoD; в промежуточном сообщении — incomplete / externally blocked, реальный minimum/overall score и ключевые остающиеся P0. Короткая итоговая часть, все детали в artifacts.

Покажи:

1. До→после по meaningful units: works/scenes/shots/clips/useful duration/tracks/GT/preference/intervention/mobile/control/source experts и verified use pool.
2. Все35 A-statuses; какие именно недостатки исправлены, какие claim corrections, какие partial/blockers. Links на records/review receipts.
3. Все22 C scores с отдельными inputs/supervision/model behavior, rubric/caps/evidence/disagreement. Модель не оценена — не выдумывать цифру.
4. Какие смежные sources реально найдены и downloaded; какие дали нужные targets и где transfer ограничен.
5. Useful corrections/real actions/technical/mobile evidence examples с source/goal/labels/consumer. Машинные предложения явно отдельно.
6. Что удалено/trash/quarantine и почему, без hidden denominator manipulation; что полезное сохранено.
7. Self-review результаты, native/temporal/spatial coverage и ограничения, failed cases и исправления.
8. Actual delivery/readback и dependency graph; нет неявной зависимости от папки на Mac.
9. Remaining external steps только если действительно необходимы; конкретный небольшой review/device check вместо новой задачи «сами найдите все данные».

Нужен максимально полезный, честный и воспроизводимый корпус. Сильный результат — закрытые реальные data targets и доказуемая пригодность. Доведи всё доступное самостоятельно, ищи шире привычных datasets и не прекращай работу после косметических изменений.

---

Это промпт на будущую доработку. В текущей Codex-задаче не выполнялись загрузка/удаление Drive-данных, повторный аудит v3 bytes, сбор v4 или обучение. Цель8/10 не является уже достигнутой оценкой.
