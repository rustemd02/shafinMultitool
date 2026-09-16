# OWNER-PACKET — что требуется именно от владельца

Составлен 2026-09-13 по runbook `docs/aegis/plans/2026-09-13-setos-release-execution.md`
(правило: «нужен шаг владельца → подготовить максимальный пакет: точное действие, путь/экран,
ожидаемый результат, откат, следующая команда; блокировать только зависимую часть»).

Формат каждого пункта: **действие → путь/экран → ожидаемый результат → откат → что разблокирует**.

Проверенные факты, на которые опирается документ (не предположения):

- Допущенных корпусов: **0** (`datasets/camera-coach/v1/research-source-catalog.json`:
  `default_admission="quarantine"`, `release_rule="A research source is never release-cleared by this catalog"`,
  `human_gold_policy.status="not_present"`; рукописные манифесты прав — пустые шаблоны, `record_count=0`).
- Очередь разметки уже собрана и проверена: `~/Library/Application Support/SETOS/annotation/queue-v3-cinematic.jsonl`
  — **547 записей** (кинокадры 313, ваш device pack 174, AVA 60), **0 отсутствующих файлов** на диске.
- Кинокадры: Blender open movies, `license=CC-BY 3.0 (Blender Foundation)`, репозиторная заметка
  прямо запрещает редистрибуцию → нужен ваш вердикт по правам.
- Human-gold gate M3-022: ≥1,400 stills, **2 независимых аннотатора + адъюдикатор, κ≥0.80**.
  Один человек + подсказки ИИ независимыми аннотаторами **не являются** — это теперь технически
  энфорсится: assisted-голоса исключены из κ, а отчёт печатает «Независимое согласие НЕДОСТУПНО»,
  пока нет второго независимого голоса.

---

## Packet A — права на данные (блокирует D03, human-gold, любой fit)

Без этого нельзя ни обучение, ни калибровку ≤2% FP_CORRECT, ни sealed eval. Четыре отдельные решения;
они независимы, можно отвечать по одному.

### A1. Кинокадры Blender CC-BY — решение оказалось **раздельным** для двух подмножеств

Я прочитал первоисточники (страницы самих правообладателей и условия лицензии) — полная справка с дословными цитатами:
[PacketA-license-facts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/PacketA-license-facts.md)
и машиночитаемые факты `datasets/camera-coach/v1/cinematic-license-facts.draft.json`. Это **факты, а не юридическое заключение**, и решение остаётся вашим.

**Ключевое: подмножества не эквивалентны.**

| Подмножество | Кадров | Что говорит сам издатель | Что решить |
|---|---|---|---|
| **Big Buck Bunny** (Peach) | 146 | «you can freely reuse and distribute this content, **also commercially**, as long you provide a proper attribution» | включать ли в продукт с атрибуцией (или только в research/демо) |
| **Tears of Steel + teaser** (Mango) | 167 + 6 | «the actors keep their **Personal Image (Portrait) and Privacy Rights**… the footage is OK to use for **technical demos, showcases, tutorials** etc. **But not to use the actor for making a commercial**» | включать ли только как research/демо, или в карантин |

То есть «подтвердить CC-BY» — неточная формулировка: для Big Buck Bunny вопрос про атрибуцию, а для Tears of Steel — про права актёров, и издатель сам разграничивает дозволенное и недозволенное.

**Для нашего случая точная строка атрибуции предписана издателем (вариант 3, переиспользование частей):**
`(c) copyright 2008, Blender Foundation / www.bigbuckbunny.org`. Для Tears of Steel строка кредита на прочитанной
странице не опубликована — я её **не выдумываю**, её нужно взять из кредита издателя и внести в карту атрибуции.

**Обязательные условия атрибуции (CC BY 3.0, версии до 4.0):** создатель и стороны атрибуции, copyright notice,
license notice, disclaimer, ссылка на материал и **название**; исключены логотипы и товарные знаки (в т.ч. Blender и
Creative Commons) — значит логотипы в бандл не попадают. Лицензия сама оговаривает: «other rights such as publicity,
privacy, or moral rights may still limit how you use the material».

- **Действие:** выбрать вариант **раздельно** по двум подмножествам (включить в продукт / research+демо / карантин) и
  заполнить `rights-attestation.template.json` (22 поля) + карту атрибуции (`author`, `license_url`,
  `attribution_string`, `source_url` по каждому фильму).
- **Путь/экран:** `datasets/camera-coach/v1/rights-attestation.template.json`, `attribution-map.template.json`.
- **Ожидаемый результат:** после заполнения активация механическая — `validate_rights_attestation.py` →
  `emit_attribution_notices.py` → запись в `datasets/camera-coach/v1/rights-manifest.jsonl` → `build_split_groups.py` (инструменты уже
  написаны и проверены: без подтверждения они ничего не пишут).
- **Откат:** решение фиксируется только в этих файлах; ничего необратимого не делается, корпуса можно вернуть в карантин.
- **Разблокирует:** D03 (пилот и sealed splits) → P02 (заморозка; receipt готов) → C08 и M03–M06 → Q01.

**Наблюдение, которое инструмент требует объяснить:** в очереди 313 кинокадров, в источнике 319 — отсутствуют все 6
кадров `tos_teaser` (очередь создана раньше их добавления). Это **не** ваше подтверждение, а факт для объяснения.

### A1-точный список: что уже установлено как факт, а что решаете вы

Список полей снят **из самого шаблона** (`datasets/camera-coach/v1/rights-attestation.template.json`), а не по памяти: сейчас пусты **24 поля**.

**Установлено как факт (можно перенести как есть, с провенансом):**

- `license.license_id` — CC-BY-3.0 (verified at creativecommons.org/licenses/by/3.0/)
- `license.license_name` — Creative Commons Attribution 3.0 Unported (verified)
- `license.license_url` — https://creativecommons.org/licenses/by/3.0/ (verified)
- `license.attribution_required` — true — attribution is a condition of CC BY 3.0 (verified)
- `corpus.source_id` — cinematic (Blender open movies) — per research-source-catalog.json
- `corpus.source_path` — cinematic corpus root (receipt-backed, outside git)
- `corpus.manifest_sha256` — manifest hash to be read from the corpus receipt
- `basis.basis_url` — publisher pages, read 2026-09-13: peach.blender.org/about/ and mango.blender.org (for Big Buck Bunny / Tears of Steel respectively)

**Решаете только вы (это и есть Packet A):**

- `attester.attester_id`
- `attester.attester_name`
- `attester.attester_role`
- `attester.attester_contact`
- `attested_at`
- `permissions.production_allowed`
- `permissions.redistribution_allowed`
- `permissions.derived_media_allowed`
- `people.people_present`
- `people.consent_obtained`
- `people.consent_reference`
- `basis.basis_type`
- `basis.basis_reference`
- `basis.basis_url`
- `basis.basis_sha256`
- `attribution.attribution_map_ref`
- `decision.admitted`
- `decision.decision`
- `decision.decision_scope`

Плюс карта атрибуции по трём фильмам: `author`, `license_url`, `attribution_string`, `source_url`. Для Big Buck Bunny строка
атрибуции уже установлена из первоисточника (вариант 3, переиспользование частей): `(c) copyright 2008, Blender Foundation /
www.bigbuckbunny.org`. Для Tears of Steel строку нужно взять из кредита издателя — я её не выдумываю.

После заполнения: `validate_rights_attestation.py` → `emit_attribution_notices.py` → запись в `datasets/camera-coach/v1/rights-manifest.jsonl` →
`build_split_groups.py`. Сейчас все три инструмента падают закрыто (validator exit 1, splits exit 1), манифест прав
остаётся шаблоном (`record_count: 0`).

### A2. Device benchmark pack (174 кадра) — единственный корпус, где решение целиком ваше

- **Действие:** подтвердить, что эти кадры сняты вами, и подтвердить согласие изображённых людей
  (или подтвердить, что людей в кадре нет).
- **Путь/экран:** `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images/`
  (записи в очереди: 174, источник `benchmark`; `CC-002` уже исключён из Release).
- **Ожидаемый результат:** attestation «мои кадры, consent есть/людей нет» — этого достаточно для
  admitted, потому что права изначально ваши.
- **Откат:** не требуется; при отказе корпус остаётся только в research-контуре.
- **Разблокирует:** честный admitted human-annotatable корпус без юридических рисков — самый
  надёжный путь к human-gold.

### A3. Wikimedia Commons PD-подмножество (767 принятых из 1199 кандидатов)

- **Действие:** per-file clearance decision на PD-файлы + решение по CC BY-SA/GFDL (6540 в карантине).
- **Путь/экран:** `receipts/commons-source-receipt.json` (`accepted sha256=fcdb4f62…`,
  `quarantined ccebda88…`, `status=PARTIAL`), `accepted-rights-receipt.jsonl`.
- **Ожидаемый результат:** «PD-подмножество допускаем с attribution» — и отдельно решение по
  CC BY-SA/GFDL (по умолчанию они остаются в карантине).
- **Откат:** запись решения делается в `datasets/camera-coach/v1/rights-manifest.jsonl` (именно camera-coach: в репозитории есть одноимённые файлы других корпусов); карантин не трогается.
- **Разблокирует:** дополнительные admitted не-киношные кадры для баланса корпуса.

### A4. AVA / AADB / EVA — решение «остаются research-only навсегда»

- **Действие:** подтвердить, что pixels и derived-веса этих корпусов **не** попадают ни в production
  веса, ни в release-бандл (в очереди есть 60 кадров AVA — они допустимы только как research-диагностика).
- **Путь/экран:** `datasets/camera-coach/v1/research-source-catalog.json` (записи `research/ava/*`,
  `research/aadb/*`, `research/eva/*`) + `EXECUTION_STATE` D01/D05.
- **Ожидаемый результат:** подтверждение границы; альтернатива — внешняя закупка прав, что вне
  полномочий проекта и требует отдельного юридического процесса.
- **Откат:** не требуется.
- **Разблокирует:** снимает неопределённость; ничего не разблокирует сверх A1–A3, но защищает от
  случайного попадания research-данных в релиз.

**Что разблокирует Packet A целиком:** D03 (pilot + sealed splits на admitted данных) → M01
(production trainer на реальном батче) → M04 (калибровка и порог FP_CORRECT ≤2%) → M06 (sealed eval).

**Что Packet A не разблокирует никогда (честное ограничение):** κ≥0.80 требует **второго
независимого человека**. Если второго аннотатора нет, human-gold gate не закрывается — это не
вопрос ресурсов, а вопрос, который нельзя обойти. Варианты: пригласить второго человека либо
понизить заявляемый статус (research/demo, без заявки на human-gold).

---

## Важная поправка к ожиданиям: production-модели в сборке нет

Проверено на **собранном** продукте, а не по документам: в Release-бандле лежат только две скомпилированные модели —
`aesthetic_nima_mobilenet_fp16` (оценка эстетики) и `DETRResnet50SemanticSegmentationF16P8` (сегментация). Модель
`compact_neural_evidence_net`, которую ищет neural-провайдер приложения, **отсутствует в проекте вообще**, поэтому
`isModelAvailable == false` и neural inference в сборке не выполняется. Research-пакет `SETCompositionNet-Stage2-Local`
отсутствует **намеренно** — он исключён из таргета как не прошедший права.

Что это значит практически: сегодня приложение работает на **детерминированном** пути критики и планирования.
Это не «слабая модель» и не забытый файл — это осознанное состояние: контракты, производители, экспортный путь и
intent-вход подготовлены и проверены, но **самой production-модели не существует**, пока нет допущенных данных,
калибровки и физической проверки. Поэтому утверждение «приложение использует нейросетевую модель композиции»
**неверно**, и из Packet A (права → данные) напрямую следует вся модельная цепочка: обучение → калибровка ≤2% FP_CORRECT
→ экспорт Core ML → sealed evaluation.

## Packet B — прогон разметки (можно начинать сегодня, права A1/A2 нужны для *использования*)

- **Действие:** запустить GUI и разметить очередь.
- **Точная команда:**
  ```bash
  cd /Users/unterlantas/Documents/XCode/shafinMultitool
  python3 tools/camera_annotation/annotate_gui.py \
    --queue "/Users/unterlantas/Library/Application Support/SETOS/annotation/queue-v3-cinematic.jsonl" \
    --store "/Users/unterlantas/Library/Application Support/SETOS/annotation/labels-owner.jsonl" \
    --annotator-id owner
  ```
- **Что вы увидите:** кадр слева; справа сверху — блок **«Права на кадр»** (источник, лицензия,
  таймкод), потому что очередь смешивает CC-BY кинокадры, ваш device pack и research-only AVA;
  далее «Кадр» (красиво / пограничное / некрасиво, «Нужно улучшать» с клавишей `K`,
  «Не уверен» с `U`), «Что мешает» (8 замороженных проблем), «Что сделать»
  (26 действий), «Своими словами» (текст разбирается в галочки, `Enter`), **«Направление правки» —
  5 необязательных осей с галочкой** (без галочки ось остаётся неразмеченной, а не «нет изменений»),
  «Области» (рисуются мышью), сохранение `Enter`.
- **Горячие клавиши:** `1/2/3` — красота, `K` — оставить/улучшать, `U` — не уверен, `A` — подсказка
  по кадру, `Enter` — сохранить и далее, `S` — пропустить, `B` — назад, `Del` — удалить область.
- **Ожидаемый результат:** файл `labels-owner.jsonl`, по строке на кадр; каждая строка проходит
  admission-валидацию (иначе GUI покажет ошибку и не сохранит).
- **Откат:** store append-only; чтобы откатить, удалите последние строки (или весь файл) — исходные
  изображения и очередь не меняются.
- **Важно про независимость:** если вы нажимаете `A`, метка автоматически сохраняется как
  `assisted=true` с указанием источника, и такой голос **не** попадает в расчёт согласия (в CLI-пути
  голосования тот же смысл несёт флаг `--assisted --assist-source`). Для human-gold нужен второй
  независимый человек, который размечает те же кадры без подсказок.
- **Два утверждения, которые вносите именно вы (не инструмент):** в манифест золота нужно явно
  записать `annotators_are_distinct_humans: true` (два `annotator-id` — это два разных человека) и
  `ai_suggestions_in_independent_pass: false` (в независимом проходе подсказки по кадру не были
  видны). Оценщик ворот `tools/release/check_candidate_gates.py` **не** пропустит манифест, где эти
  поля просто отсутствуют: отсутствие объявления он считает нарушением, а не согласием. Посмотреть
  обязательные поля можно командой `python3 tools/release/check_candidate_gates.py --template` —
  блок `gold` печатается со всеми требуемыми ключами.

---

## Packet C — Colab-пакет (сборка готова; ваш шаг — авторизация и Run all)

Пакет собран и проверен (M02). Я воспроизвёл ваш путь целиком локально: обе архивы собираются с ожидаемыми
хэшами, preflight даёт `exit 0` и в квитанции честное доказательство устройства
(`model parameters, batch inputs, loss and gradients observed on the declared device`). **Никакого Drive/OAuth
и никакого egress не требуется** — ноутбук один раз просит выбрать два файла в обычном диалоге.

- **Шаг 1. Собрать два архива у себя** (без сети):
  ```bash
  cd /Users/unterlantas/Documents/XCode/shafinMultitool
  python3 tools/dataset/package_camera_colab.py build \
    --profile records \
    --output /private/tmp/SET_OS_Camera_Coach_Records.zip
  python3 tools/dataset/package_camera_colab.py --pack-records-data \
    --records ml/camera_coach/configs/production_records_smoke.jsonl \
    --admission non_admitted_research \
    --output /private/tmp/SET_OS_Camera_Coach_Records_DATA.zip
  ```
  Обе команды печатают `sha256` архива — **сохраните оба значения**, они понадобятся в блокноте как
  `EXPECTED_CODE_BUNDLE_SHA256` и `EXPECTED_DATA_BUNDLE_SHA256`. Путь через `/private/tmp` не случаен: на macOS
  `/tmp` — симлинк, и пакаджер намеренно отказывает («FAIL path uses a symlink»).
- **Шаг 2. Открыть** `ml/camera_coach/colab/SET_OS_Camera_Coach_Records.ipynb` в Colab и выбрать GPU-рантайм
  (`Runtime → Change runtime type → T4 GPU`).
- **Шаг 3. Заполнить один блок параметров:** `RUN_ID`, пути к двум архивам, два ожидаемых хэша,
  `EXECUTION_PROFILE`, `REQUIRE_CUDA`, `ALLOW_CPU_SMOKE`, `RESUME`, `RUNTIME_ROOT`, `DURABLE_DIR`.
- **Шаг 4. Run all.** Colab один раз спросит два `.zip` обычным файловым диалогом.
- **Шаг 5. Забрать результат:** блокнот скачает `result-manifest.json` и напечатает run id, статус, фактическое
  устройство, пиковую VRAM, выбранный seed и линию resume. Квитанция помечена `not_a_quality_claim`.

**Ожидаемый результат сегодня:** `non_admitted_research` — это прогон пайплайна и доказательство устройства,
**не** обучение на допущенных данных. Preflight намеренно отказывает в `--execution-profile full_fit`, потому что
admitted записей **0** (Packet A). То есть Colab-шаг сейчас подтверждает, что обучение запускается и считает
на GPU; сам fit станет возможен только после Packet A. Ограничение честнее показать заранее, чем выдать
«прогон прошёл» за обучение.

- **Ожидаемый результат:** `drive.mount('/content/drive')` успешно; выбран T4.
- **Откат:** отзыв доступа в Google Account → Security → Third-party access; удаление блокнота.
- **Историческая справка:** попытки Drive-OAuth из встроенного браузера структурно невозможны (4 попытки:
  `mount failed`, затем `credential propagation was unsuccessful`). Поэтому текущий пакет **не использует Drive
  вообще**: файлы выбираются вручную, а durable-каталог можно указать на уже смонтированный путь. Локальное
  обучение Stage-1/Stage-2 (артефакты захэшированы, `research/runs/eva-stage1-local-20260913` и `…/stage2-local-20260913`)
  остаётся research-only и production-весами не является.
- **Разблокирует:** production fit после Packet A (данные) + M01 (trainer, `verified` для CPU-пути).

---

## Packet B-доп — реальные съёмки и слепая оценка (подготовка готова, оценка ждёт людей)

Подготовительный срез Q02 выполнен и проверен: **[shot-list-v1.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/implementation/human-eval/shot-list-v1.md)**
(10 условий съёмки SL-01…SL-10: что снимать, что должно быть в кадре, что считается валидной попыткой и что её
аннулирует) и **[attempt-record-schema.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/implementation/human-eval/attempt-record-schema.md)**
(форма реальной попытки с fail-closed правилом: `record_status = complete` только при выполнении всех условий,
иначе `incomplete`; `declined`/`cancelled` — валидные записи, но не успех).

Что это значит практически: сцены можно планировать по shot list без домысливания условий, но **оценка
заблокирована и не имитируется**. Арифметика, которую я проверил: нужно **350 locked cases → 350 × 3 = 1 050 слепых голосов**,
700 эпизодов, 350 защищённых негативов, 210 физически управляемых последовательностей и **2 независимых
аннотатора + адъюдикатор**; реально есть **0 / 0 / 0 / 0 / 0**. Поэтому κ, hidden QC, ROI IoU и все human-gates
(≥0.90 safe+executable, ≥0.80 helpful, ≥0.60 preference, ≤0.01 harmful, 0 критического вреда) **не вычислимы —
знаменатель нулевой**, и ни один из них не помечен пройденным.

Правила, которые в пакете прямо запрещены (и я их подтверждаю как обязательные): заполнять оценки от лица
реальных людей, выдумывать участников/квоты/κ, считать подсказки ИИ независимым оценщиком, выдавать ваши голоса
за двух аннотаторов, истребовать причину отказа (отказ без объяснения — валиден), усреднять разногласия
большинством и считать «красивый after по другой причине» доказательством успешного совета.

## Packet D-доп — готовый протокол прогона и импортёр отчёта (Q03)

Подготовительная часть физического прогона выполнена и проверена: протоколы
[recording-v1.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/implementation/device-tests/recording-v1.md) и
[ar-workspace-v1.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/implementation/device-tests/ar-workspace-v1.md)
дополнены восемью новыми v3-проверками (`v3.two_object_target`, `v3.protected_ref_intent`, `v3.glare_review`,
`v3.lens_switch_fence`, `v3.video_temporal_coverage`, `v3.track_swap_incomparable`, `v3.output_crop`,
`v3.technical_action_verify`), а сводный пакет —
[Q03-device-run-packet.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/Q03-device-run-packet.md).

Профиль для прогона: **iPhone 13 Pro (`iPhone14,2`) + самый старый доступный iPad владельца (iPadOS 17.0+)**.
Это самая слабая **реально доступная** ступень; A12-класс остаётся явным `blocked_external`-пробелом, а не
молча снимается. iPhone 17 Pro не используется — Master Plan это прямо запрещает, и сильнейшая ступень
маскирует worst-case риски.

Отчёт принимается только через fail-closed импортёр `tools/device/import_device_report.py`: он сверяет
**точный** build/device/OS/source tuple и отвергает расхождения. Что я проверил своими прогонами:
корректный отчёт → `ACCEPTED`; чужой `build_id` → `REJECTED: wrong build: report build_id 'OTHER-BUILD' != pinned 'b1'`;
thermal-проверка, подтверждённая **скриншотом**, → `REJECTED: category 'thermal' forbids role 'screenshot';
thermal/audio/perf claims need a measured device export, not a screenshot` (и требуются `measured`-ключи);
при разрешённой роли `thermal_report` проверка проходит гейт роли. Импортёр **никогда не выставляет `pass`** —
он только фиксирует статусы, поэтому «зелёного» протокола из ничего не получится.

Ни один hardware gate не помечен пройденным: физический прогон, установка и замеры — это Q04 на ваших устройствах.

## Packet E — шаги в Apple-аккаунте (проверено по первоисточнику Apple 2026-09-13)

Я прочитал официальную страницу Apple «Upcoming Requirements» в браузере и сверил с фактами проекта; полная
сверка с цитатами — [Q06-apple-requirements-check.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/Q06-apple-requirements-check.md).
Два пункта может закрыть **только владелец в App Store Connect**, и подготовкой они не отменяются:

1. **Опросник age rating по новой системе** (действует с 31.01.2026). Формулировка Apple: ответы на обновлённые
   вопросы нужно дать, «чтобы избежать прерывания при отправке обновлений». Для нового приложения это заполняется
   при создании записи в **App Information**.
   - **Путь:** App Store Connect → ваше приложение → App Information → Age Rating.
   - **Ожидаемый результат:** вопросы отвечены, рейтинг присвоен по новой системе.
   - **Откат:** ответы можно изменить в том же разделе до отправки.
2. **DSA trader status для распространения в ЕС** (с 17.02.2025). Формулировка Apple: приложения без trader status
   **удаляются** из App Store в Евросоюзе, пока статус не предоставлен и не проверен.
   - **Путь:** App Store Connect → Business/Compliance → EU Digital Services Act trader requirements.
   - **Ожидаемый результат:** статус предоставлен и подтверждён.
   - **Откат:** это юридическое заявление о вашем статусе — я его за вас не принимаю; решение полностью ваше.

**Что со стороны проекта уже готово и проверено:** сборка идёт на **Xcode 26.6**, то есть требование «Xcode 26+ с
SDK iOS 26» (действует с **28.04.2026**) выполнимо, но должно быть подтверждено на **архивной** сборке кандидата —
именно поэтому я не заявляю это заранее. Требование «approved reasons for APIs» (с 01.05.2024) закрыто:
`PrivacyInfo.xcprivacy` объявляет четыре категории с причинами, а сторонний SDK SnapKit несёт собственный манифест;
пиннинг `tools/tests/test_release_metadata.py` проверяет, что объявлено **всё, что использует код**.

**Неприменимое не превращаю в блокеры:** receipt signing SHA‑256, APNs, macOS quarantine, Game Center и notarization
относятся к функциям, которых в приложении нет (IAP/подписок, push, Game Center тоже нет) — это же служит основанием
не вводить StoreKit из старого списка блокеров.

## Packet F — одно решение по интерфейсу: лимит строк командной полосы

Проверка состояний интерфейса (пункт 4 карточки S06) нашла **измеримую** причину обрезки подсказок, и это
не «русский язык слишком длинный»: командная полоса рендерит инструкцию с лимитом **2 строки**
(`SETCameraCoachProductionView.swift:1722` `.lineLimit(2)`), а метрика высоты режет измеренную высоту до
`2 × lineHeight` (`SETMetrics.swift:226` `maximumLines: 2`, `:260-261`). Замер по реальному шрифту
(`Oswald-Variable.ttf`, wght 700, 22pt) показал, что **часть инструкций требует 3–4 строк** — и обрезаются
**и русские, и английские** строки, поэтому простое сокращение текста неполно без решения по лимиту.

- **Что решить:** оставить лимит 2 строки (и тогда часть инструкций будет обрезаться), поднять его до 3,
  или разрешить уменьшение шрифта до минимального масштаба. Это **layout-бюджет**, то есть визуальное решение,
  а не техническая правка — поэтому оно здесь, а не в коде.
- **Путь:** решение влияет на `SETCameraCommandBand` (командная полоса) и метрики `SETMetrics`.
- **Ожидаемый результат:** одна выбранная политика; после неё недостающие строки локализации сокращаются
  (список ключей и языков собран исполнителем с замерами) — **без** redesign.
- **Откат:** изменение лимита обратимо одной правкой константы; строки каталога версионируются отдельно.
- **Что уже сделано и не требует решения:** два узких дефекта интерфейса исправлены и проверены —
  тумблер Pro Controls больше не перекрывает кнопку паузы/возобновления, а панель Pro Controls прокручивается,
  поэтому нижние строки достижимы на компактной высоте и при увеличенном тексте (Accessibility).

## Packet D — физические устройства (финальная фаза, не сейчас)

- **Действие:** предоставить доступ к iPhone 13 Pro и iPad на время прогона.
- **Что будет проверяться:** камеры и линзы (в т.ч. `change_lens`), App Attest roundtrip
  (`S02b`/`Q04`), iPad-раскладка (`S06`), финальная физическая квалификация (`Q04`).
- **Ожидаемый результат:** протокол прогона с записанными результатами; без него `S02b` и `Q04`
  остаются открытыми, а `READY_FOR_APPLE_WORKFLOW` не заявляется.
- **Откат:** не требуется (измерения, а не изменения).
- **Разблокирует:** закрытие device-гейтов и финальную физическую проверку.

---

## Сводка

| Packet | Что нужно от вас | Что разблокирует | Можно ли обойти |
|---|---|---|---|
| **G** | выбрать по одному чтению на 10 строк §5.1 (механически, одна команда) | измеримость десяти строк приёмки | нет |
| A1 | вердикт по CC-BY кинокадрам | admitted 313 кадров → D03 | нет |
| A2 | attestation своих кадров + consent | admitted 174 кадра → D03 | нет |
| A3 | per-file PD clearance | admitted 767 кадров | нет |
| A4 | подтверждение границы research-only | защита релиза | да, но с риском |
| B | разметка в GUI (+ второй человек для κ) | labels → supervision | нет |
| C | Drive OAuth в Colab | облачный fit | да, локальный fallback работает |
| D | iPhone 13 Pro + iPad | S02b/Q04/S06 | нет |
| E | возрастной рейтинг и DSA-статус | Apple-пакет (M14) | нет |
| F | одно решение по лимиту строк | UI-приёмка | да, можно отложить |

## Порядок выполнения (что за чем, и что можно параллельно)

Зависимости важнее размера: два первых шага не блокируют друг друга, а третий бессмысленен без первого.

1. **Packet G (первым, самый короткий).** Ни от чего не зависит, разблокирует измеримость десяти строк §5.1. Одна команда после выбора: `apply_definition_choices.py` → три команды заморозки. Ожидаемый результат: `APPLIED 10 definition(s)`, затем `--check` exit 2 → `--write` → `--check` PASS.
2. **Packet A (параллельно с G).** Ни от чего не зависит и открывает больше всего: D03/D04, квоты, сплиты и обучение M03/M04. Внутри A решения **раздельные по подмножествам** — можно отвечать по одному. **Уточнение:** A снимает блокировку *датасета*, но **не** снимает 16 блокеров `legal-state-pending` релизного гейта — это отдельное решение о правах на материалы, уже входящие в бандл (см. пункт 7).
3. **Packet B (после A).** Разметка начинается сразу, но human-gold требует второго независимого человека; до закрытия A размеченные кадры остаются research-only. Проверено: путь «метки → золотой блок → ворота» по инструментам связен.
4. **Packet C (после A).** Colab не зависит от разметки, но обучение имеет смысл на допущенных данных; локальный fallback работает, если Drive недоступен.
5. **Packet D (после A и желательно после C).** Устройства нужны для S02b/S03b и Q04; отчёт начинайте с `--template` импортёра. Приёмка отчёта **не** равна квалификации устройства — это указано и в самом манифесте.
6. **Packet E/F** — независимы, можно в любой момент; E нужен для Apple-пакета, F можно отложить.
7. **Packet R — правовое состояние материалов уже в бандле (отдельно от A).** Релизный гейт
   `scripts/validate_release_component_status.py` читает
   `docs/implementation/provenance/release-component-status.json`: там **19 компонентов, у всех
   `legal_state=PENDING`**, и **16 из них входят в Release** — отсюда `KNOWN_BLOCKER_COUNT=16`
   с `blocker=legal-state-pending`. Это **не то же самое**, что права датасета в Packet A: цепочка A
   (`attestation_from_decisions.py` → `validate_rights_attestation.py` → `emit_attribution_notices.py`
   → `datasets/camera-coach/v1/rights-manifest.jsonl` → `build_split_groups.py`) этот файл не читает и не пишет, поэтому
   **Packet A эти 16 блокеров не снимет**. Что нужно в этом файле:
   - **13 из 16** — решение владельца выставить `legal_state: "APPROVED"` (5 шрифтов: `font-bebasneue-regular`,
     `font-caveat-variable`, `font-jetbrainsmono-variable`, `font-oswald-variable`, `font-ptm55ft`;
     5 ассетов: `resource-assets-catalog`, `module-assets-catalog`, `privacy-manifest`,
     `info-plist-localization`, `localized-resources`; `circle-usdz`, `person-usdz`, `snapkit-dependency`);
   - **3 из 16** — `llama-framework`, `detr-segmentation-model`, `nima-aesthetic-model` — кроме
     `APPROVED` требуют `replacement_dependency.status: "VERIFIED"` (сейчас `PENDING`), потому что у них
     `disposition=REMOVE_AFTER_VERIFIED_REPLACEMENT`; без этого гейт сменит блокер на
     `replacement-pending`, а не снимет его.
   **Ожидаемый результат:** `python3 scripts/validate_release_component_status.py --repo-root .` —
   сейчас `KNOWN_BLOCKER_COUNT=16`, exit 1; после решений `PASS COMPONENT STATUS: no known provenance
   blockers`, exit 0. Отдельного конвертера у файла нет — он редактируется вручную, поле `owner`
   ссылается на задачи M12.

**Если время ограничено:** сделайте G и A — они снимают блокировки для всего остального; B/C/D без них не имеют смысла.

**Пока вы не ответили, я не простаиваю:** незаблокированные пакеты (камера-ядро C02/C03,
Scene Generator S03a, контракт v2 и trainer-подготовка) продолжаются, а зависимые от Packet A
помечены `blocked_external` без имитации результата.

---

## Packet G — определения десяти строк §5.1 (новое, найдено аудитом 2026-09-13)

**Что нашлось.** В таблице приёмки §5.1 у **десяти строк есть порог, но нет определения** — ни числителя, ни знаменателя ни в одном документе репозитория. Проверено поиском: `direction/horizon precision` и `light/exposure precision` встречаются ровно три раза, и все три — копии таблицы порогов (runbook, мастер-план §9.6, handover); `accepted coverage` (три варианта) и `abstention correctness` не упоминаются вне таблиц вообще; `verification accuracy` — только пункты чек-листа. То есть эти строки нельзя ни пройти, ни провалить: их можно только угадать, а угадывать знаменатель запрещено правилами проекта.

**Точное действие:** открыть
`docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/definition-packet-5-1.json` и по каждой из десяти строк выбрать одно чтение (или написать своё). Для каждой строки там 2–3 варианта, и у каждого есть: формула (что числитель, что знаменатель), на какие артефакты репозитория он опирается, что именно нужно решить вам и к чему это приведёт.

**Ожидаемый результат:** у десяти строк появляется определение; после этого соответствующие ключи перестают быть задокументированными пробелами, и производителя для них можно писать, не выдумывая знаменатель.

**Откат:** нечего откатывать — пакет ничего не решает и ничего не меняет в гейтах; `status: awaiting_owner_decision`, ни один вариант не помечен выбранным (это проверяется тестом).

**Следующие команды после вашего выбора** (правка политики делается конвертером, а не руками — он сам ставит `definition_status`/`definition_source` из выбранного варианта, поднимает `schema_version` и записывает impact):

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool

# 1) записать выбор в один маленький файл: строка -> id варианта
cat > /private/tmp/choices.json <<'JSON'
{
  "direction_horizon_precision": "A",
  "light_exposure_precision": "A",
  "accepted_coverage_overall": "A",
  "accepted_coverage_ordinary": "A",
  "accepted_coverage_difficult_light": "A",
  "abstention_correctness": "A",
  "verification_accuracy": "A",
  "critical_forbidden_observed": "A",
  "wrong_direction_false_success": "A",
  "wrong_target_false_success": "A"
}
JSON
#    (подставьте свои id вместо A/B/C; если выбор неполный, команда откажет и НИЧЕГО не изменит)

# 2) применить (все десять строк обязательны):
python3 tools/release/apply_definition_choices.py \
  --choices /private/tmp/choices.json \
  --out /private/tmp/definitions-receipt.json

# 3) принять версию в заморозке — правка перестанет быть молчаливой:
python3 tools/release/freeze_receipt.py --check   # ожидается exit 2: "requires impact list"
python3 tools/release/freeze_receipt.py --write
python3 tools/release/freeze_receipt.py --check   # ожидается PASS
```

**Откат для этого шага:** политика версионируется — вернуть прежнюю версию можно из git (`git diff datasets/camera-coach/v1/evaluation-policy-v1.json`) и перегенерировать receipt тем же `--write`; повторное применение тех же choices инструмент отвергает, чтобы решение нельзя было применить дважды случайно.

**Что это меняет для готовности:** даже при закрытых правах и подключённых устройствах эти десять строк нельзя будет измерить, пока определения не написаны. Это часть плана приёмки, а не инструментальная работа, поэтому решение остаётся за вами.


---

## Packet X — одиннадцать решений по итогам аудита (новое)

Пять раундов read-only аудита плюс полный прогон unit-набора нашли одиннадцать пунктов, которые я
**не исправлял сам**: это поведение продукта, а не инструментарий, и цель требует отдавать такие границы вам.
Сведите их в `evidence-release/OWNER-DECISIONS-audit.md`: для каждой находки — что подтверждено с `file:line`,
что **не** подтверждено, варианты решения и чем проверяется результат.

Коротко, что там: (1) показ совета не консультируется с safety gate и подтверждённым замыслом;
(2) рантайм-валидатор Scene не исполняет условные требования замороженного контракта;
(3) при записи медиа `expectedFileSize` пишется и никогда не читается, а успех решается состоянием, не файлом;
(4) сырой технический текст в UI (панель подсказки, VoiceOver, Decision Trace);
(5) передача пользовательского **текста** возможна при развёртывании с `SETOS_SCENE_BASE_URL`, а манифест
приватности заявляет `NSPrivacyCollectedDataTypes: []`; (6) бэкенд сохраняет результат провайдера без валидации; (7) в отслеживаемом `scripts/scripts.md` почти всё содержимое — чужая киносценарная строка; (8) повреждённая карта мира открывает сцену как исправную, теряя привязки молча; (9) отсутствующий ассет актёра молча заменяется коробкой, а генерация сообщает успех; (10) C05 — показанная команда не обязательно та, что допустил bounded-планировщик, а эпизод стабилизации может начаться при скрытой подсказке; (11) **приложение не проходит собственную сюиту — ~29 падений**, и выбор «продукт или намеренная смена + тесты» за вами.

**Ответ:** `/private/tmp/audit-decisions.json` вида `{"1": "a", "2": "b", ...}`. Находка 5 связана с манифестом
для Apple-пакета (Packet E) — её стоит решить до подачи.
