# SET OS: исполнительный план доведения до подготовки публикации

Дата: 2026-09-13. Автор: GPT-6 / Codex. Тип: подробный runbook к действующему Master Plan v2, **не новый конкурирующий master plan**. Исполнение начинается после передачи владельцем этого документа вместе со стартовым промптом. В рамках создания документа обучение, сборки, отправка данных, deployment и изменения production-кода не выполнялись.

**Goal:** получить цельное приложение в согласованном объёме, квалифицированную модель Camera Coach, воспроизводимые клиент/сервер/данные и пакет, с которым владелец может начать Apple publishing workflow. Не считать загрузку в ASC, TestFlight, App Review и публичный выпуск уже выполненными.

**Architecture:** один клиент iOS/iPadOS, существующий backend Scene/AI, offline-процесс данных/обучения. Камера, идентичность сущностей, локальный допуск действия, текст/overlay и verify имеют существующих владельцев. VLM предлагает evidence; он не выдаёт окончательное решение, trackID, разрешение вмешиваться в сцену или результат verify. Не создавать второй planner, отдельную графовую БД, новый движок tracking или новую дизайн-систему.

**Tech stack:** текущие Swift/SwiftUI/UIKit, AVFoundation, Vision, Core ML, ARKit; существующий Python backend и PyTorch pipeline; Colab для запланированного fit, macOS для Core ML. Framework и версии не заменять ради этого плана.

**Baseline / authority:** текущий запрос и присланная пользователем выдержка zcode; Master Plan v2, прежде всего §24 и обязательный scope §3; `docs/cameraanalysis/03-domain-contracts.md` N1–N12; аудит `36-frame-defect-coverage-audit.md` §§7–10; действующие domain/ML/API/visual документы. Исходный `.zcode-session` по указанному пути отсутствовал; вместо него использована предоставленная владельцем переписка, без заявления о прочтении файла.

**Compatibility boundary:** приложение ещё не выпущено; не строить миграции для выдуманной установленной базы. Но существующие проекты, записи, research datasets, checkpoints и незакоммиченные изменения сохраняются. Не сбрасывать данные ради удобного теста. Старые форматы читать только там, где существует реальный consumer или нужный исторический артефакт; новая версия не маскируется под старую.

**TDD route:** strict test-first не требуется. Исполнитель использует минимальные проверки конкретного риска; стартовый промпт явно разрешает необходимые узкие регрессионные/контрактные проверки. Не писать тесты, повторяющие реализацию, и не расширять нерелевантные suites. Полные проверки — в интеграционной/финальной фазе, а не после каждого изменения.

**Verification:** каждый закрытый пакет содержит изменения, точную команду, exit code, ссылку на результат, версии входов и ограничения. Исторический PASS не закрывает изменённый путь. Simulator, macOS parity, физическое устройство, human evaluation и Apple distribution — разные классы доказательств.

## 1. Решения по девяти пунктам владельца

| Пункт переписки | Решение для исполнения | Чего это не разрешает |
|---|---|---|
| 1. iPhone 13 Pro — в самом конце | Подготовить протоколы заранее; полный физический прогон после стабилизации runtime, модели и UI. Учесть обязательный iPad из исходного scope. | До этого не объявлять выполненными camera/AR/microphone/thermal/App Attest/VoiceOver hardware gates. Если устройство обнаружит дефект, вернуться к соответствующему пакету. |
| 2. Нужен ли видео-лейн, можно ли учить по картинкам? | **Да, видео остаётся в целевом Camera domain.** Учить покадровое восприятие на stills; реальные короткие последовательности использовать для tracking, временных метрик и проверки действий. Сначала имеющиеся алгоритмы и metadata; отдельную большую видеосеть не строить. | Набор случайных кадров не доказывает отсутствие мерцания, рывков и смены identity между ними. Не обещать поддержку всего клипа по редким сэмплам. |
| 3. Всё в credits | Сформировать полноценные notices/attributions на допущенные компоненты, изображения и источники. До обучения отдельно проверить разрешения на pixels, annotations, base weights и производные веса. | Credits не снимают noncommercial/research-only ограничения. Отметка «для диплома можно» не является разрешением для App Store. |
| 4. Владелец размечает в готовом инструменте | Доработать существующий GUI/export под замороженные labels, подготовить удобные независимые пакеты. Его голоса использовать как реальные человеческие данные с указанным авторством. | Один человек и подсказки ИИ не образуют двух независимых аннотаторов. Gold/adjudication/слепая оценка требуют отдельных реальных голосов. |
| 5. Human-eval — да | Подготовить и провести реальную съёмку с советами и слепую оценку полезности; подготовку автоматизировать, человеческие наблюдения не подделывать. | VLM не выступает независимым человеком и не подтверждает причинное улучшение своим же советом. |
| 6. Регрессии и freeze — да | Версионировать контракт, policy, dataset, модель, preprocessing и backend; запускать связанные проверки при изменении владельца. | Не подгонять пороги по locked test, не повторять весь набор после правки документа. |
| 7. Rollout, приложение не выпущено | Не строить A/B-платформу, dark launch и сложный staged rollout до первой версии. Оставить проверку допуска артефакта, понятное отключение проблемной cloud capability, recovery и сохранённый предыдущий candidate. | Нерелизность не отменяет защиту данных, серверные квоты и право пользователя остановить совет. |
| 8. Синхронизация диссертации — да | По завершении значимых пакетов обновлять `diploma.md`, evidence map, claim registry и затронутые snapshots/chapters по router. | Не переписывать `docs/thesis/litreview*`; не переносить ожидания из плана в научные результаты. |
| 9. Ресурсы пока безлимитны | Не урезать качество ради предполагаемой экономии. Планировать полноценные данные, несколько seeds, человеческие проверки и продолжительные GPU runs. | Это плановая предпосылка, не права на данные, не доступ к аккаунтам и не разрешение покупать тарифы/нанимать людей/разглашать кадры без конкретной санкции. |

Два исправления zcode-сводки обязательны. Сумма «5 оставить + 16 переформулировать + 3 слить + 3 детектора» равна **27**, а действий 26; пересчитать по строкам, не переносить ошибочную сводку в registry. `keep_current_setup` — положительный статус, ему не нужен фиктивный movement-verifier. Абстрактным simplify/rebalance после слияния нужна проверка выбранной конкретной операции, а не ещё один пустой verifier.

## 2. Что проверено перед составлением плана

Рабочая копия: `/Users/unterlantas/Documents/XCode/shafinMultitool`, ветка `store`, HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`. Большой dirty diff — часть исходного состояния. Хэш HEAD один не идентифицирует текущий candidate.

| Наблюдение | Источник в прочитанном дереве | Следствие |
|---|---|---|
| Domain v3 пока design, не реализованная новая нейросеть | `docs/cameraanalysis/03-domain-contracts.md:581,912–935` | Сначала schema, bindings и qualified registry; не переименовывать checkpoint в v3. |
| Draft содержит 20 параметризованных operations, старый ML utility — 26 индексов | `03-domain-contracts.md:720–751`; `ml/camera_coach/contracts/set_composition_net_v1.json` | Нужен явный смысловой mapping, а не rename enum или добавление головы на каждый кейс. |
| Stage2 учил три головы; текущий scorer research-only | `ml/camera_coach/train_silver_actions.py:1195–1211,1320–1324`; `ml/camera_coach/INTEGRATION.md:3–12` | Good/risk/abstention нельзя использовать как обученные safety probabilities. |
| `train.py` — synthetic dry run; converter принимает research Stage2 | `ml/camera_coach/train.py:820–827,873–939`; `convert_coreml.py:60–83,158–160` | Реальный human-data trainer и явный export admission — отдельная работа до Colab. |
| GUI-schema и dataset-schema не совпадают | `datasets/camera-coach/v1/label-schema.json`; `tools/camera_annotation/annotation_labels.py:30–88,281–303` | Устранить 21 domain issues ↔ 8 neural issues; beauty ≠ KEEP; пропущенное поле не отрицательный label/нулевая delta. |
| Pilot из 35 briefs не содержит pixels | `tools/camera_annotation/build_annotation_pilot.py:8–12,26` | Подготовить реальный media pilot, не выдавать текстовые задачи за калибровку восприятия. |
| Репозиторные rights/consent/source-shoot/derivation manifests — шаблоны без records | `datasets/camera-coach/v1/*-manifest.jsonl`, `source-shoots.jsonl` | Реально обследовать внешние data roots; не объявлять допущенный корпус по наличию файла. |
| Камерные verification gaps подтверждены аудитом | `36-frame-defect-coverage-audit.md` §§9–10; `UserMovementObserver.swift:561–612`; `ActionVerifier.swift:319–340` | Исправлять эффект/адресата, а не уверенность и красивые слова. |
| Certification script может завершиться успехом после failed xcodebuild и удаляет xcresult | `scripts/run_camera_certification.sh:22–50` | Исправить сам измерительный инструмент до использования как gate. |
| Swift/OpenAPI и внешний HTTP adapter не согласованы по clarification body | `SceneGenerationClient.swift:231–238`; `backend/openapi-scene-v1.yaml:113–116`; `/Users/unterlantas/Documents/XCode/setos-backend/service.py:674–680` | Проверить и исправить producer→consumer roundtrip; зелёные отдельные unit suites не доказывают wire совместимость. |
| Старые «не реализовано» местами устарели | `SceneGeneratorViewModel.swift:3108`; `ProControlsPanelView.swift:5`; `SETCameraCoachProductionView.swift:254`; `LegacySceneGeneratorCameraShell.swift:1325,1788` | AR hint binding, Pro Controls, iPad tray/shortcuts искать и квалифицировать, не писать заново. |

Здесь приведено source evidence, а не свежие результаты обучения, тестов или работы устройства. Старые «13 из 81» и частоты 174-кадрового replay — development evidence из переписки/артефактов, не измерение будущей release-модели.

### 2.1. Карта чтения

Не загружать всё дерево в каждый subagent. Оркестратор читает этот план, последний хвост `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/EXECUTION_STATE.md` и только нужные источники:

- **Продукт и старые обязательства:** `SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md` в той же папке, §§3, 9, 24; `docs/implementation/PRODUCTION_ACCEPTANCE.md`; visual policy `docs/implementation/ux/set-os-visual-policy.md`.
- **Камера:** `docs/cameraanalysis/03-domain-contracts.md` N1–N12; `camera-analysis-requirements-draft.md` §23, все 68 `CC-*`; `24-semantic-tip-taxonomy-and-action-catalog.md`, `25-vlm-visual-semantic-evidence-contract.md`, `26-semantic-tip-fusion-and-planner.md`, `34-case-traceability-map.md`, аудит `36` §§9–10.
- **ML/data:** `ml/camera_coach/INTEGRATION.md`, `contracts/set_composition_net_v1.json`, `data/preprocessing.py`, `datasets/camera-coach/v1/label-schema.json`, `capture-protocol.md`, source catalog и реальные receipts.
- **Backend/release:** `backend/openapi-scene-v1.yaml`, `docs/implementation/backend-service-boundary-v1.md`, внешний backend README/source; `docs/implementation/release/`, `docs/implementation/provenance/`, `docs/implementation/device-tests/`.
- **Научный журнал:** сначала `docs/thesis/08_agent_context_router.md`; затем только затронутые claims и snapshots.

Правило расхождений: текущий явный запрос выше старого совета; фиксированный продуктовый scope не сокращать; принятый контракт выше теста, который случайно закрепил старое поведение. Код показывает действительность, но не автоматически правильное поведение. Новый task начинает с проверки этого различия. Историческую запись не переписывать; актуальное решение дописать со ссылкой.

## 3. Автономное исполнение и продолжение после обрыва

### 3.1. Два конечных состояния

1. **AUTONOMOUS_WORK_COMPLETE_PENDING_OWNER:** все доступные кодовые, data-tooling, model-work и подготовительные задачи сделаны; осталось конкретное внешнее действие — реальные голоса, авторизация Colab, документы на права, устройство, hosting account. Это честная передача пакета, **не готовность приложения**.
2. **READY_FOR_APPLE_WORKFLOW:** все обязательные **до Apple/TestFlight** функциональные, data/model, human и физические gates пройдены на привязанных версиях; release-пакет собран; остаются действия владельца с Apple — аккаунт/подписание при необходимости, загрузка, TestFlight, review и финальная публикация. Если отсутствует production backend или коммерческие права, это состояние запрещено. Это не final RC: исходные M14 external beta и M15 RC/submission остаются отдельными обязательными этапами после начала Apple workflow; их результаты и возможные исправления не обещаются заранее.

Не продлевать задачу искусственно после выполнения её scope. Не объявлять READY только потому, что исчерпаны часы, число попыток или доступные инструменты.

### 3.2. Один оркестратор, ограниченные владельцы

Использовать subagents для независимых пакетов; максимум определяется реальными слотами и памятью, а не словом «безлимитно». Рекомендуемые дорожки: Camera core; Data/ML; Backend/Scene; UI/accessibility; независимый reviewer. При трёх слотах запускать три подходящие дорожки волнами. Один writer на файл/модуль; два агента не редактируют одновременно `CameraAnalysisDomainContracts.swift`, `AnalysisPipeline.swift`, `CameraViewModel.swift` или один dataset manifest.

Рабочая копия общая: не создавать worktrees/копии репозитория, не reset/clean/stash/force checkout. Не делать commit/push без отдельного разрешения. Не отменять и не удалять чужие GPU-процессы и незавершённые изменения. Серверные файлы принадлежат отдельной дорожке в `/Users/unterlantas/Documents/XCode/setos-backend`; сначала проверить фактическое существование и локальные правила этого repo.

Каждому агенту дать: task ID, цель, разрешённые файлы, входные версии, инварианты, исключённые файлы, конкретную проверку и формат результата. Указать, что он не один. Не пересылать всю историю. Сложную неоднозначность поднять оркестратору как выбор с evidence; механическую задачу не превращать в новое проектирование.

### 3.3. Протокол пакета

Для каждого ID из §6–10:

1. Проверить dependencies, текущий source и чужой ownership; сохранить hash/diff только нужных файлов.
2. Прочитать перечисленных owners, callers и ближайшие existing checks. Если уже реализовано — проверить, а не воспроизвести.
3. Выполнить один законченный смысловой slice. Пакет больше 60–90 минут активной работы разбить на `ID.a`, `ID.b` с отдельными файлами/результатами; время — ориентир, не обещание.
4. Запустить самую узкую проверку. При failure сохранить output, найти причину, исправить в том же пакете; не менять expected result ради зелёного цвета без контракта.
5. Независимый reviewer проверяет опасные seams: schema, identity, verify, ML labels, export admission, privacy, wire API. Обычную копию/типографику закрывает оркестратор.
6. Записать результат в **существующий** `EXECUTION_STATE.md`: `task_id`, `status`, changed paths, входные hashes, command/exit/evidence, ограничения, next ready task. Компактные evidence сохранять в существующей work-папке `evidence-release/`; большие медиа/checkpoints — во внешнем data root с manifest.
7. Освободить ownership и сразу взять следующую dependency-ready задачу. Не спрашивать «продолжать?» после пакета.

Состояния: `pending`, `running`, `needs_review`, `verified`, `blocked_external`, `blocked_contract`, `superseded`. «Тест написан», «сборка запущена» и «код выглядит готовым» не равны `verified`.

Перед compaction/паузы записать активную задачу, точные изменения, запущенный process/run ID, команду возобновления и следующую точку проверки. После возврата сначала прочитать checkpoint и сравнить дерево/receipts. Не начинать fit заново, пока не проверен существующий процесс и последний атомарный checkpoint. Во время GPU-run выполнять независимые CPU/source/doc задачи; не занимать GPU вторым fit без измеренного запаса.

### 3.4. Остановки без остановки всей работы

Отсутствует OAuth, устройство, human votes или право на конкретный источник — закрыть только зависимый участок. Подготовить владельцу один конкретный пакет: что открыть, что сделать, какой файл/результат вернуть и какая проверка после этого продолжится. Перейти к независимой работе.

Три одинаковые неуспешные попытки без новых данных — прекратить повтор того же решения; диагностировать или сменить обоснованную гипотезу. Не понижать gate. Если исчерпаны все независимые задачи, выдать `AUTONOMOUS_WORK_COMPLETE_PENDING_OWNER` со списком фактических блокеров. «Многочасовая работа» не даёт права выдумать human/device evidence.

## 4. Scope, контракт и ML: что замораживается

Freeze выполняется в двух слоях:

- **Структурный:** сущности, регионы, ссылки, координаты, provenance, типы evidence, action payload и состояния. Его можно реализовывать до массовой разметки.
- **Квалификационный:** разрешённые operation × case × mode × evidence/device profiles, метрики, deadbands, пороги и labels. Он требует контрпримеров и pilot. Без него новая операция не получает production CORRECT.

Не задерживать исправление уже доказанной лжи verify до нового training run. Первым вертикальным сценарием сделать «две лампы/две одинаково названные вещи»: выбран герой, двигается конкретный предмет, герой защищён, один совет, одно движение, честный результат. Два bbox с label «лампа» не дают устойчивую identity.

20 operations v3 сохраняются как проектируемые семейства: `reframe_subject`, `change_subject_scale`, `level_frame`, `reposition_entity`, `rotate_entity`, `exclude_entity`, `reposition_camera`, `adjust_light`, `adjust_exposure`, `refocus_subject`, `hold_steady`, `set_capture_parameter`, `change_lens`, `reserve_output_region`, `wait_for_clearance`, `select_capture_moment`, `maintain_subject_zone`, `smooth_camera_motion`, `plan_motion_endpoints`, `clear_lens_obstruction`. У каждого — реально поддержанные payload, mode и verifier. «Все 20 в schema» не означает «все 20 квалифицированы на любом устройстве».

Семь обсуждавшихся дополнений сопоставить явно: rotate_object → rotate_entity; uniform light → reposition_entity с локальной световой целью; lateral translation / point without glass → reposition_camera с разными effect goals и prerequisites; accessible lamp → существующий световой/предметный actuator; hand pose → ограниченный разрешённый person pose case. `disable_synthetic_background_blur` отсутствует в этих 20 как явный параметр: сначала проверить наличие реального управления; при необходимости оформить точечное расширение schema/registry до freeze либо оставить review-only unsupported. Не выдавать его через чужой параметр и не добавлять второй обходной planner.

`clean_lens` и `clear_lens_obstruction` различны: первое требует подтверждённого загрязнения/материала для очистки, второе освобождает оптический путь от пальца/чехла. Нельзя перенести диагноз грязи в draft-операцию освобождения пути без изменения контракта.

Для каждого из 68 CC-кейсов создать строку traceability: requirement → evidence → operation/proposal/state-only → prerequisite → verifier → dataset slice → test/evidence → release disposition. Допустимые dispositions: `qualified`, `conditional_review`, `unsupported_with_reason`, `out_of_release_scope_by_owner`. Последнее требует явного решения, не удобства исполнителя. Для обязательной достижимой функции отсутствие квалификации блокирует готовность; для принципиально невыводимого из available evidence кейса корректный отказ — предусмотренное поведение. Не заявлять поддержку всей функции, если реализована только возможность отказать.

Нейросеть остаётся поставщиком числового evidence. Сохранить v1 tensor order в историческом контракте и сделать явный mapping; не менять старые файлы и индексы под новым именем. Один дефицит уже установлен: нынешние six inputs/40 features не содержат user intent, а одинаковые pixels/ROI могут требовать разных KEEP/utility labels. Поэтому этот план выбирает явное versioned intent conditioning (M00) до fit; не обучать противоречивые intent-dependent targets при одинаковом входе. При изменении tensor signature создать новую версию одновременно для schema, loader, trainer, export, Swift, preprocessing, registry и parity. Замена 26 логитов на 20 operations по индексам запрещена. Неучившиеся heads имеют маску unavailable; отсутствующий label не равен «ошибки нет».

## 5. Приёмка до обучения

### 5.1. Бюджет ложных предупреждений

Предлагаемая продуктовая настройка этого плана: **FP_CORRECT на хороших in-domain кадрах ≤2%** вместо только старого preservation ≥95%. Это решение автора плана для принятия владельцем через запуск; не найденная в коде константа и не достигнутый результат. Размещается в versioned evaluation policy до locked test.

`FP_CORRECT = число хороших кадров с хотя бы одной недопустимой коррекцией / число оценённых хороших кадров`. KEEP и ABSTAIN считать раздельно; нельзя выполнить gate сплошным молчанием. Показывать point estimate и одностороннюю верхнюю 95% границу. Для финального заявления о бюджете верхняя граница тоже должна быть ≤2%; недостаточно данных означает `insufficient_evidence`. Независимость считать по source-shoot/session clusters, а не по сотне почти одинаковых соседних кадров. При действительно независимых 0/81 верхняя односторонняя граница всё ещё около 3.6%: один маленький удачный набор не доказывает 2%.

Остальные исходные gates Master Plan §9.6 сохраняются; новый строгий good-frame gate их не ослабляет:

| Метрика | Gate |
|---|---|
| pass / expected-action hit | ≥0.90 / ≥0.90 |
| forbidden violations / critical forbidden | ≤0.02 / 0 наблюдаемых критических случаев |
| technical failure gate | 1.00 по замороженному определению |
| каждая scene class / material organic source | ≥0.85 / ≥0.80 |
| synthetic/adversarial bucket | ≥0.65 |
| confidence-band accuracy / abstention correctness / verification accuracy | каждая ≥0.90 |
| direction/horizon precision | point ≥0.95, Wilson lower 95% ≥0.90 |
| light/exposure precision | point ≥0.92, Wilson lower 95% ≥0.87 |
| false improved | ≤0.02; знаменатель определить до fit, см. ниже |
| wrong-direction false success / wrong-target false success | 0 в обязательных safety случаях |
| accepted coverage overall / ordinary / difficult light | ≥0.65 / ≥0.55 / ≥0.35 |
| human safe+executable / helpful / preference среди non-ties | ≥0.90 / ≥0.80 / ≥0.60 |
| human materially harmful / critical harm | ≤0.01 / 0 |

Для false improved публиковать обе стороны: ошибочные подтверждения / все выданные improved; ошибочные improved / все действительно non-improved эпизоды. Старое определение метрики извлечь из evaluator и закрепить; нельзя сменить знаменатель, чтобы сохранить 2%. Incomparable не выбрасывать из confusion matrix. При нуле выданных improved precision не определён и coverage gate не пройден автоматически.

Нейросеть обязана приносить пользу против уже имеющегося deterministic baseline: ≥5 п.п. на заранее выбранном pass/expected-action или защищённом semantic subset, нижняя 95% граница парного bootstrap по source-shoot >0, без ухудшения safety. Не переносить сюда ложный «рост loss-quality» и сравнение разных корпусов.

### 5.2. Квоты данных и независимость

300–500 кадров — разумный **development pilot**, не релизный corpus. Сохранить обязательства Master Plan §9: 8 400 train candidates, 1 400 calibration/validation stills в исходном master, 1 400 locked stills, 1 400 live sequences, 700 episodes, 350 protected negatives, 210 physical guided sequences, 350 × 3 blind reviews. Это разные срезы с разрешёнными пересечениями внутри одного split, а не сумма независимых скачанных файлов. Для этого плана сознательно разделяем validation и calibration: закладываем по 1 400 независимых stills в каждый, вместо общей корзины 1 400; это дополнительный плановый объём, а не цитата прежней квоты. Validation не заимствует calibration/test. По каждому из семи классов master сохраняются минимум 1 200 train, 200 calibration, 200 locked stills, 200 sequences, 100 episodes, 50 protected negatives, 30 physical guided; отдельный validation также планируется по 200/class. Unknown/OOD и новые case slices учитываются дополнительно по freeze P02, не теряются при переходе к восьми neural scene logits.

Per-action floors исходного master: 400 train positives, 100 calibration, 100 test, 120 forbidden opportunities, 30 near-threshold, 20 style exceptions где применимо; эпизоды по соответствующим обязательным action families — 80 improved, 40 unchanged/worse, 20 incomparable. В P02 сопоставить их новому operational registry: синонимы не умножают физические записи, принципиально неприменимые режимы отмечаются с причиной. Не уменьшать quotas самостоятельно и не выдавать все числа за уже собранные.

Gold: два независимых аннотатора + adjudicator, 5% hidden QC, 10% adjudicated re-review; Cohen κ для KEEP/CORRECT/ABSTAIN ≥0.80, action family κ ≥0.75, forbidden agreement ≥0.90, median ROI IoU ≥0.80, hidden QC ≥95%. Предложения ИИ в GUI выключены в независимом проходе либо факт их просмотра помечен и данные не выдаются за слепые. Владелец может быть одним аннотатором; существование второго не выдумывать.

Splits разносить по группам происхождения/съёмки/производным файлам, а не случайным jpg. Соседние кадры одного клипа, crop/коррупции/экспорты одного оригинала и связанные action episodes идут в один split. Device family — срез анализа и осознанный OOD protocol; разрешить конфликт существующих split-правил явно, а не склеить все кадры iPhone в одну неделимую группу случайно.

### 5.3. Stills, пары и видео

- **Stills:** локализация, композиция, свет/фокус, protected intent, гипотезы issues, OOD и условная utility. Оценку красоты хранить отдельно от KEEP: мрачный или некрасивый намеренный кадр не требует автоматически исправления.
- **Реальные action episodes:** before, выданное действие, изменяемый/защищённый экземпляр, after, движение/параметр, контекст, метаданные, независимая оценка. Учат/проверяют эффект действия и ложное «помогло».
- **Последовательности:** реальные PTS, gaps, track swaps, motion/settling, scene cut, temporal continuity. Учить маленькую temporal модель только после failure analysis существующего extractor; не начинать с покупки видеодатасета и новой архитектуры.
- **AVA/EVA/AADB и подобные:** вспомогательные aesthetic/perceptual данные лишь при допустимых правах. Не основной телефонный in-domain gold и не истина о физическом действии.
- **FiveK/PP-R и пары ретуши:** прежде установить реальные условия и labels. Предпочтение обработанного изображения не является доказательством, что шаг или поворот на площадке поможет. Не использовать такие пары как ground truth physical action без отдельного валидного соответствия.
- **Synthetic corruptions:** полезны для известных технических и adversarial случаев, но не доказывают реальную выполнимость, движение и переносимость на смартфон.

## 6. Подготовка и Camera runtime

Для относительных source paths корень — репозиторий. Сокращение **CA** в перечне owners означает `shafinMultitool/Multitool2Module/Models/CameraAnalysis/`; **Pipeline** — `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`; **Planner** — `shafinMultitool/Multitool2Module/Services/Recommendation/SemanticTipPlanner.swift`. Это обозначения путей, не новые модули.

### P00 — актуальная карта работы

**Dependencies:** нет. **Owners:** существующий `EXECUTION_STATE.md`, evidence-release, прочитанные source и receipts; production-код пока не менять.

1. Снять HEAD, branch, tracked/untracked diff, список текущих процессов и task owners. Не читать секреты из env-файлов в лог. Зафиксировать отдельно внешний backend HEAD+dirty digest, model/data paths и toolchain.
2. Для каждого M/R-пакета старого master определить `verified current / implemented needs recheck / unfinished / external`. Проверять последние записи и конкретный source; не запускать заново закрытые M0/M1 из-за исторического заголовка.
3. Сопоставить дальнейшие ID этого runbook старым M2/M3/M4, R-пакетам и §10 аудита. Вести одну таблицу статусов в существующем журнале; не создавать новую систему управления проектами.
4. Подготовить очередь независимых работ и выписать реальные внешние inputs. Новые human/device требования не прятать до дня финального прогона, хотя само устройство используется в конце.

**Готово:** по каждому обязательному product lane известен текущий owner, evidence и следующий шаг; чужой diff сохранён. **Проверка:** source review + `git diff --check`; статистика старых задач не объявлена процентом готовности.

### P01 — структурный контракт и disposition всех требований

**Dependencies:** P00. **Owners:** `docs/cameraanalysis/03-domain-contracts.md`, `24`, `25`, `26`, `34-case-traceability-map.md`, existing production contract/registry owners.

1. Сверить 68 CC-сценариев, 26 legacy actions, 7 technical actions, 20 draft operations и условные дополнения §9. Не дублировать технические id.
2. Для каждой operation записать payload, executor, target/protected refs, evidence prerequisite, mode, effect goal, verifier, template, причины отказа. Для уже известного разрыва измерения назначить C04, а не добавлять threshold.
3. Разрешить phase=review: proposals и сравнения, не активный live CORRECT. Разделить временное WAIT и недостаток evidence ABSTAIN; KEEP требует положительного основания.
4. Задать точные version IDs; сформировать машиночитаемый registry в существующем контрактном каталоге, если аналога нет. Stable v3 не объявлять до C01 conformance. Будущие невыводимые cases остаются честно unsupported.

**Готово:** нет требования без disposition и нет активного действия без адресата/результата; все конфликты смыслов разрешены до массовой разметки. **Проверка:** coverage таблица без потерянных ID, независимый contract review. Числа 26/20 проверяются по source, не ручной сводке.

### P02 — qualification pilot и заморозка gates

**Dependencies:** P01, D01, D02a и real pilot D03; структура нового ML-входа согласована в M00 до итогового freeze. D02b зависит от этого freeze, а не наоборот. **Owners:** existing eval policy/config, case traceability, qualified registry.

1. Для топ-10 дефектов §7.7 собрать хорошие контрпримеры: силуэт, intentional tilt/blur, negative space, светлая кромка, отражение, тесный осмысленный crop, смысловой фон. У каждой рекомендации — positive, intentional exception, no-resource и wrong-target case.
2. Прогнать available signals без обещания нового детектора. Для каждого failed case разделить: неверный label, недостаточная локализация, плохая метрика, ошибка planner, intent unknown, физически невыводимо.
3. Заморозить §5 metrics/denominators/coverage, quotas, split grouping, trained-head masks, calibration метод и action eligibility. Для новых T-метрик определить длину окна/gap из pilot, затем записать versioned policy до финального test.
4. Установить freeze receipt: hashes схем, catalog, policy, preprocessing, labels и protocol. Изменение после freeze требует версии и явного impact списка; не перемаркировывать молча.

**Готово:** labels имеют проверяемый смысл и контрпримеры; qualification неизвестной операции остаётся закрытой, а не получает придуманную вероятность. **Проверка:** pilot report и независимый review оснований. Не использовать финальный holdout для выбора порогов.

### P03 — достоверность проверяющего инструмента

**Dependencies:** P00. **Owners:** `scripts/run_camera_certification.sh`, существующие проверки scripts.

1. Сохранить exit code каждой фазы и вернуть ненулевой итог при любой failed фазе/ошибке получения обязательного результата.
2. Перестать удалять `.xcresult` после прогона; использовать уникальный task-owned result-dir. Не удалять старые evidence перед запуском ради совпадения имени.
3. Убрать зависимость от зашитого UDID: принимать обнаруженный destination и проверять его. Не увеличивать таймауты production-кода, чтобы скрыть contention simulator.
4. Минимально проверить failure propagation на управляемом ненулевом исполнителе и отсутствие потери evidence; затем один уместный targeted реальный прогон в интеграционной фазе.

**Готово:** failed xcodebuild невозможно выдать за successful certification; результат сохранён. **Не делать:** новый CI framework, полный suite только ради проверки shell-кода.

### C01 — исполняемая schema и типы

**Dependencies:** P01. **Owners:** CA `CameraAnalysisDomainContracts.swift` и существующие validators; dataset/provider schema owners.

1. Реализовать v3 envelope, references, action payload, review/verification states в существующей архитектуре; при слишком большом файле вынести только типы этого нового связного контракта, без второго owner.
2. Проверять finite/ranges, Region, frame/transform references, entity graph endpoints/cycles, exact schemaVersion, enum/payload combinations. Unknown не превращать в zero или guessed enum.
3. Проверить одинаковую сериализацию Swift/Python: Bool vs число, MediaTime Int64 строкой, optional отсутствие, нормализованные координаты.
4. Оставить legacy decoders только для реальных v1/v2 consumers; новый payload не принимать через permissive fallback.

**Готово:** позитивные и негативные contract cases N12 одинаково принимаются/отклоняются Swift/Python; review не содержит activeAction. **Проверка:** ближайшие domain-contract suites + schema conformance, один reviewer. **Retirement:** временный adapter удаляется после перевода его конкретных callers, не «когда-нибудь».

### C02 — координаты и preprocessing без скрытых преобразований

**Dependencies:** C01. **Owners:** существующие CameraCoordinateSpace/DisplayTransform, model preprocessing, overlay mapper.

1. Проследить sensor/Vision → oriented frame → model input → preview/output, отдельно portrait/landscape/mirror/aspect fill/independent scale.
2. Разрешить зафиксированный N11 конфликт: ML v1 independent scale не равен preview aspect-fill. Для каждого tensor сохранить actual transform, не использовать удобную чужую матрицу.
3. Исключать невидимый target; не прижимать его координаты к краю. Поворот телефона, изменение высоты и перенос точки не выводить друг из друга по одному смещению bbox.
4. Проверить текст/стрелку для одного и того же accepted action, включая зеркальное превью и изменение output crop.

**Готово:** target попадает в ту же деталь во всех поддержанных преобразованиях; свежесть/generation invalidation сохраняется. **Проверка:** `CameraCoordinateSpaceTests`, preprocessing parity; не требуется обучение.

### C03 — несколько сущностей и устойчивый адресат

**Dependencies:** C01/C02. **Owners:** CA `SubjectIdentityRegistry.swift`, `SubjectTracker.swift`, `SubjectResolver`/resolution contracts, `SubjectTapSelector.swift`, existing frame evidence store.

1. Обследовать уже добавленный registry, не писать второй. Отделить frame-local entityID, session trackID и safe display label.
2. Поддержать selected person и отдельный изменяемый предмет/группу. Face/person не удваивают участника; одинаковые labels не доказывают identity; reflection не становится вещью для перестановки.
3. На swap, occlusion, reacquisition и generation change сохранять неопределённость. Прежняя ROI lost track не выдаётся за текущую.
4. Заморозить baseline bindings target и protected refs; user intent revision имеет единственного owner. Поздний provider response не меняет выбор.

**Готово:** в «двух лампах» выбранная лампа не меняется при перестановке местами; потеря связи отменяет/инвалидирует эпизод, не переназначает другой объект. **Проверка:** существующие identity/tracker/subject selection suites и реальные короткие dev sequences.

### C04 — исправить verify результата, а не жеста

**Dependencies:** C02/C03; известные legacy баги можно чинить узкими slices до полного P02. **Owners:** CA `UserMovementObserver.swift`, `ActionVerifier.swift`, `CoachingEpisodeCoordinator.swift`.

1. Убрать horizon absoluteChange как критерий исправления фоновой помехи у change_camera_angle. Использовать выбранную квалифицированную метрику контура/перекрытия; при отсутствии сигнала — unsupported, не выдуманная формула.
2. Наблюдать action-relevant change отдельно от effect goal. Достаточный моторный delta не приводит автоматически к improved. Проверять именно targetRefs, одновременно protectedRefs.
3. Поддержать ожидаемое исчезновение удаляемого target через expectedAbsenceRefs: исходный track, наблюдённый выход, подтверждённо свободная область, сохранённые protected tracks. Просто пропавший bbox не успех.
4. Для ожидания проверить конкретный blocker/область и сохранность момента; для параметра/света — фактическое изменение M/evidence и эффект. Для keep не создавать исполнительный эпизод. Слитые generic actions проверяются через выбранную конкретную операцию.
5. Применить порядок N7: scope/identity/comparability → protected regressions → effect delta/deadband → improved/unchanged/worse; неизвестность → incomparable. Отдельно от outcome — goalSatisfied. Старое fixed сопоставить явно, не потерять смысл.
6. Разрешать только перечисленные changes конкретного verifier; lens/orientation/route/background завершают старый эпизод. Не отключать все guards ради полезного camera movement.

**Готово:** lateral movement с ровным горизонтом может получить правильный результат, завал без устранения помехи — нет; чашка измеряется отдельно от лица; вред защищённой детали не хвалится. **Проверка:** existing verifier/closed-loop/coordinator suites + реальные episode slices, confusion matrix по каждому допущенному семейству.

### C05 — один допущенный план и одна команда

**Dependencies:** C01/C03/C04. **Owners:** CA `CameraBoundedActionPlanner.swift`, `CameraAdviceSafetyGate.swift`, `AdviceStabilizer.swift`, Planner, Pipeline.

1. Зафиксировать одного владельца final decision. SemanticTipPlanner/materializer строит текст того же Action, а не выбирает второй совет по raw logits/VLM.
2. Исправить `technicalPauseActions`: одна причина не становится тремя независимыми командами с nil target. Альтернативы имеют общий alternativeGroup; следующий шаг только после завершения/отмены и нового анализа.
3. До ранжирования проверять intent, permissions/manipulation, resource, reachable destination, mode, calibrated evidence, supported verifier, target freshness. Никакое score не преодолевает запрет.
4. Объединить существующие technical/semantic действия на уровне пользовательской карточки, сохранив typed payload. Удалить generic исполняемые simplify/rebalance/hotspot там, где они должны раскрыться в конкретный actuator.
5. Сохранить reason-coded KEEP/WAIT/ABSTAIN/SELECT_SUBJECT. При отмене не наказывать пользователя и не возвращать тот же непригодный совет немедленно.

**Готово:** live — одна квалифицированная команда; pause — до трёх независимых проблем/предложений без параллельного исполнения; нет обхода safety через technical fallback. **Проверка:** planner/safety/presentation existing suites, матрица issue→candidate→reject reason→displayed action.

### C06 — конкретные действия и захват

**Dependencies:** C05/P02. **Owners:** `shafinMultitool/Services/CameraService.swift`, camera view model/ProControls owners, qualified registry.

1. Для focus/exposure/hold/obstruction проверить существующее управление, доступность параметра на устройстве, диапазон и подтверждённое применение. Не считать autoFocus+autoExpose фокусным lock.
2. Реализовать только требуемые отсутствующие операции в существующем owner: target refocus, exposure bias, доступные locks; preserve recording/capture lifecycle. Не обещать установку неподдерживаемого ISO/WB/shutter.
3. Для rotate/reposition entity, uniform light, боковой камеры и доступной лампы назначить точный payload, разрешение постановки и локальный effect goal. Scene object availability подтверждает пользователь/qualified evidence, не название класса DETR.
4. Неподдержанный effect/контрол оставляет конкретный case условным/недоступным. Не выпускать «попробуй что-нибудь» как закрытый action.

**Готово:** каждое qualified семейство можно выполнить по одной карточке и проверить; ни один callback не меняет/не прерывает запись неожиданно. **Проверка:** доступные control/lens tests и contract cases; аппаратные диапазоны окончательно — Q04.

### C07 — RU/EN и доступность одной команды

**Dependencies:** C05; интеграция по мере C06. **Owners:** Planner copy, `SETLocalization.swift`, `Localizable.xcstrings`, `CameraOverlayUXPresentation.swift`, `SETCameraCoachProductionView.swift`, existing intent presentation.

1. Пересчитать фактические строки аудита и обновить каждую нужную формулировку. Не терять адресата: поворот телефона ≠ его подъём; ближе к объективу ≠ «вперёд»; window/light reference не выдумывать.
2. Человек в согласованном портрете — предложение оператору попросить его; свой телефон — ясная прямая команда. Документальные запреты проверяются до текста, а не словом «пожалуйста».
3. Текст, overlay и VoiceOver строятся из одного accepted action/target/direction. Дать повтор, пропуск, паузу подсказок и понятный comparable/unknown статус; они не становятся новыми моторными actions.
4. Проверить весь набор реальных production states RU/EN, Dynamic Type, Reduce Motion/Transparency, focus order и unobstructed shutter. Не выводить voice в записанный звук по умолчанию.

**Готово:** нет технических placeholders в пользовательском flow; доступные labels описывают реальное движение; отказ от совета доступен без объяснения диагноза. **Проверка:** существующие presentation/localization suites и captures конечных состояний; финальный физический VoiceOver — Q04.

### C08 — короткий клип и временное evidence

**Dependencies:** C03/C04/P02. **Owners:** existing frame scheduler/tracker, accepted envelope, media selection/import и temporal feature owners; recording owner не заменять.

1. Реализовать Coverage single_frame/sampled_frames/continuous_interval с PTS, measured gaps, examined interval и content revision. Импорт только выбранного пользователем материала; не сканировать всю медиатеку.
2. По существующим capture protocols собрать реальные sequences. Первый temporal scope: устойчивость выбранной зоны, рывки/дрожание при известном intent, стабильность экспозиции/WB при доступных metadata. Каждой метрике — достаточное окно, sampling и qualification.
3. Поддержать maintain zone/smooth motion/endpoints только при соответствующем evidence и разрешённой фазе; endpoint из реальной репетиции, не невидимый придуманный маршрут.
4. Во время записи локальные ненавязчивые подсказки; никакого постоянного видео-egress, блокирующего review или остановки recording. Scene cut/identity loss инвалидирует текущий совет.
5. Если материал содержит редкие sampled frames — выводить только то, что видно в них; отсутствие T defects между кадрами не утверждать.

**Готово:** заявленная video-функция соответствует реальному coverage и прошла temporal slices; нельзя пройти gate повтором одного still. **Проверка:** source/video protocol checks, настоящие dev sequences, tracking/temporal confusion и later device recording regression. Большая video-сеть не prerequisite.

### C09 — подробный разбор и provider evidence

**Dependencies:** C01/C03/C05, S02a для локального/исследовательского сетевого пути; production device-auth qualification завершается S02b/Q04. **Owners:** существующий VLM provider/ingress по `25`, Pipeline, review presentation, backend boundary.

1. Сохранить локальный live как обязательную основу. Detailed cloud analysis — только по явному запросу, разрешённому privacy scope и настроенному backend; нельзя скрыто посылать кадры ради quality gate.
2. Реализовать s2 correlation tuple, deadline/bytes/pixels/frames limits, safe attachments, enum/region/reference validation и grounding proposals. Provider не назначает entity identity/qualification/final action.
3. Показать review findings, evidence, uncertainty и alternatives; review-only user assessment помечается human input, не objective verify и не новый gold vote.
4. Проверить timeout/offline/refusal/invalid/stale response, cancellation, revoked consent, redacted regions. Не отправлять больше данных как fallback при отказе модели.

**Готово:** реальный accepted provider response проходит локальный допуск; ложный/stale payload не меняет выбор и совет; отказ сети не ломает local camera. **Проверка:** существующие ingress/provider/transport suites и staging сценарий на разрешённых тестовых медиа. Research two-object probe не считать production интеграцией.

## 7. Данные, разметка и обучение в Colab

### D01 — права и реальные источники

**Dependencies:** P00; параллельно Camera. **Owners:** `datasets/camera-coach/v1/`, existing source intake/governance/rights manifests; внешний raw-media root.

1. Инвентаризировать реально имеющиеся файлы/receipts, source URL/version/date, pixels/annotations/weights licenses, derivatives и consent. Header-only manifest не считать выполненной задачей.
2. Разделить `admitted_for_target_use`, `research_only`, `quarantine`, `needs_rights_decision`. Проверить lineage всех encoder initializers и derived weights; fine-tune на своих фото не отменяет ограничений исходного checkpoint.
3. Подготовить rights-first путь production corpus/initializer, исключая неизвестные источники из соответствующего fit. Подготовить владельцу только конкретные нерешённые permissions; не собирать без разбора тысячи недопустимых кадров.
4. Сгенерировать notices/credits из admitted registry; сохранить авторов, точные licenses/URLs и required modification notices. Не приписывать всему фильму/Commons/датасету одинаковое разрешение.

**Готово:** понятно, какие реальные данные и веса допустимы для каждого назначения; unknown не проходит production admission. **Проверка:** существующий governance/intake checker + ручной provenance review; это не автоматическое юридическое заключение.

### D02 — единая семантика labels и рабочий GUI

**Dependencies:** P01 для D02a; P02 и M00 для D02b. D02a — draft schema/GUI для pilot; D02b — окончательная фиксация export/input compatibility. Это два последовательных состояния одного пакета. **Owners:** `tools/camera_annotation/annotation_labels.py`, `annotate_gui.py`, export/build queue/pilot/report; dataset label schema и ML mapping.

1. Развести beauty, KEEP/no-needed-correction, issue presence, action usefulness, action infeasibility/forbidden, intent unknown, target/protected ROI, scene/subject agreement, before-after outcome. Не учить `good_frame_probability = beauty` автоматически.
2. Устранить implicit negatives: missing issue/action labels, absent delta components и unknown resources получают explicit masks. Forbidden и unknown различны; 21 domain issue не ужимать в 8 без documented mapping.
3. Добавить недостающие target fields для обучаемых heads; для каждого head указать источник supervision. Не генерировать safety ground truth из собственной model confidence.
4. Сохранить существующий инструмент и hotkeys. Сделать blind mode без AI hints, author/time/schema metadata, устойчивое сохранение/возобновление, export validation. Старый label-format конвертировать только явно и с report потерь.
5. Заменить «pilot без pixels» новым версионированным real-image packet, старый сохранить как исторический учебный материал.

**Готово:** roundtrip GUI→saved label→export→loader сохраняет смысл и masks; владелец может реально разметить выданный пакет без ручной правки JSON. **Проверка:** минимальные affected annotation checks и ручной roundtrip на настоящем снимке, не только brief.

### D03 — human pilot и уточнение инструкции

**Dependencies:** D01/D02a; даёт evidence для P02. Завершённый D02b для pilot не требуется. **Owners:** существующий annotation protocol/pilot/report и реальные annotators.

1. Подготовить небольшой pre-pilot для отладки инструмента, затем обязательный 140-case real-media pilot по master M3-010 с измеренным соглашением; после его приёмки расширять до 300–500 development кадров партиями. Включить хорошие контрпримеры, ambiguous target, лампы-дубликаты, дефекты смартфона и пустые/непонятные случаи.
2. Выдать двум реальным людям независимые packets без видимых чужих ответов и model suggestions; собрать disagreements и adjudication. Если доступен только владелец, вести development labels и оставить independent gold gate открытым.
3. Исправить agreement report: нужные Cohen state/action, forbidden agreement, ROI IoU, QC; один Fleiss-score не подменяет набор критериев.
4. Не пускать массовую разметку, пока ошибки инструкции/схемы повторяются. Менять правила на pilot, версионировать и заново проверить затронутые labels.

**Готово:** реальные голоса и соглашение по §5.2, пакет понятен владельцу; при внешнем блокере вся подготовка закончена и следующий импорт автоматизирован. **Проверка:** receipts голосов/QC/agreement, без вымышленных независимых экспертов.

### D04 — полный корпус и sealed splits

**Dependencies:** D03/P02/D01/D02b. **Owners:** existing intake, dedup, dataset audit/split/packaging scripts, capture protocol.

1. Расширить offline train/validation/calibration/test корпус до §5.2, используя in-domain stills и настоящие ранее собранные episodes/sequences. Финальные physical guided 210 и blind field reviews собираются на Q02/Q04: сейчас заморозить их protocol, reserved scenes и критерии, не требовать будущие результаты до обучения. Сбор датасета и квалификация финального приложения на устройстве — разные работы; просьба отложить финальный iPhone-прогон не делает кадры заменой необходимых последовательностей. Подготовить сценарные shot lists/таблицы для людей: id, intent, target, protected, операция, допустимость, before/after, no-effect/worse/incomparable.
2. Проверить exact/near duplicates, original/derivative/sequence family leakage; оформить rights/consent на конкретные records. Разнести train/validation/calibration/test до model selection.
3. Посчитать coverage по operation/case/mode/style/device/source/unknown; deficits заполнить целевым сбором, не случайным увеличением похожих фото.
4. Запечатать locked labels отдельно от training worker; test не используется sampler, early stopping, prompt tuning или calibration. Фиксировать hashes и доступы.
5. Предоставить воспроизводимый command, который из admitted manifests строит training/Colab package. Не использовать historical stage2 defaults с тремя research roots как production pack.

**Готово:** admitted offline corpus с соответствующими quotas, нулевая подтверждённая межsplit утечка, воспроизводимые manifests; отдельные final physical/human quotas явно pending до Q02/Q04, а не ложно выполнены. **Проверка:** существующие camera_dataset/governance checks, список near-duplicate review decisions и split receipts.

### D05 — отдельный corpus и human-gold для Scene Generator

**Dependencies:** P00, права на соответствующие тексты; независимо от Camera GPU. **Owners:** существующие Scene dataset/eval tools и artifacts в `docs/SGv9pipeline/`, старые M3/M5 evidence; не путать с camera annotation schema.

1. Инвентаризировать имеющиеся SGv9 corpora/receipts, train/validation/locked outputs и реальные лицензии. Не запускать обучение Generator заново и не создавать новый corpus, если существующий удовлетворяет требованиям.
2. Сохранить master §9.7 floors: 6 000 core train prompts, 800 validation/calibration, 1 200 locked core; ambiguity train/test 800/200, long-form 600/200, entity-binding 800/250, adversarial 500/250; owner-independent qualitative ≥100, из них ≥30 независимо написанных. RU и EN — каждый ≥35%. Применимость пересечений зафиксировать, не складывать слепо counts и не выдавать derivatives одного screenplay за независимые источники.
3. Развести validation и calibration для фактически калибруемых решений; зафиксировать source-author/document/project/template families и запрет leakage. Права на screenplay excerpts не предполагаются; synthetic lineage хранится, silver не становится locked human gold.
4. Два независимых реальных annotators и adjudication размечают entities/coreference, marked bindings, chronology, action, allowed structured variants, clarification и forbidden meaning changes. Существующие annotations принять только с подтверждённым происхождением/QA.
5. До locked test зафиксировать gates: JSON/schema 1.00; boundaries F1≥.98; actor attribution≥.97; marked binding≥.95; target resolution≥.98; chronology≥.98; hallucinated objects≤.01; clarification recall≥.90; critical meaning corruption=0. Разрешить старое разночтение action recall .95/.98 явно: этот план выбирает **≥.98**, сохраняя более строгий production acceptance. Это плановое решение до test, не достигнутая метрика.
6. Зафиксировать реальные small/long input buckets, p95≤20s/≤60s, completed cost mean≤$0.05/p95≤$0.10 по исходному master; ресурсный бюджет разработки не отменяет runtime-продуктовые ограничения. Сравнить local parser и два prompt-only provider candidates; fine-tune только при подтверждённой необходимости и разрешённом датасете.

**Готово:** воспроизводимый Scene eval/human packet с замороженными splits/критериями и правами; отсутствие реальных голосов не маскируется model judging. **Проверка:** существующий SGv9 evaluator/validators по реальной CLI, read-only baseline сначала; итоговая quality часть закрывается вместе с S03.

### M00 — явный intent input и согласованная цель supervision

**Dependencies:** P01/D02a/D03; фиксация вместе с P02, до D02b и любого fit. **Owners:** ML contracts/schema, data preprocessing/loader, model signature, Swift input builder, export/parity, annotation mapping.

1. Создать новую числовую версию модели, отдельно от domain v3: `ml/camera_coach/contracts/set_composition_net_v2.json` и соответствующую schema по существующему паттерну. V1 оставить неизменным для исторических артефактов; старый checkpoint нельзя объявить v2 простой сменой metadata.
2. Добавить явный `intent_features`: восемь флагов styles из CaptureIntent (`natural`, `silhouette`, `low_key`, `symmetry`, `negative_space`, `dutch_angle`, `intentional_motion_blur`, `handheld`) плюс отдельный флаг known. Это выбранный начальный 9-компонентный профиль; пустой/неизвестный intent не кодировать как natural. Несколько заданных стилей сохраняются. Unknown: known=0 и все style flags=0; known=1 требует непустого явного набора. Shape/dtype/order/unknown semantics заморозить в manifest; не занимать скрыто существующие 40 scalar slots.
3. Реальные user constraints/manipulation/resource availability остаются у deterministic runtime gates. Модельная utility/risk supervision описывает только информацию, которая подана входом: визуальную пользу/риск при заданном style и выбранном ROI. Скрытые запреты «вещь чужая», неизвестная опора и недоступный проход не обучаются как будто видны в pixels. Такие labels нужны policy evaluation, а для соответствующего neural target применяется mask.
4. Для выбранной цели вне выразимого профиля/ROI не придумывать conditional label: сохранить human annotation, пометить неподдержанный neural target и применить runtime intent/ABSTAIN. Новые intent inputs добавлять только отдельным schema decision, если обязательный кейс требует их.
5. Согласованно обновить model input layer, trainer loader, export, Swift input builder и parity fixtures. Девять прежних output семейств и порядок 26 utility индексов сохранять там, где семантика не изменилась; documented output semantics относятся к новому v2 manifest. Проверить парные одинаковые pixels/ROI с разными явными styles и с unknown: input различается только ожидаемой частью, отсутствующие input не заполняются ложной известностью.

**Готово:** labels зависят только от реально доступных входов/explicit masks, все consumers одинаково понимают новый intent vector. **Проверка:** schema/preprocessing/input conformance и tiny real-batch check до GPU. Перенос существующего encoder допустим лишь при совместимости слоёв и допущенной lineage; никакого автоматического «продолжим старый Stage2 и всё готово».

### M01 — production-capable loader, losses, trainer

**Dependencies:** D02b/P02/M00; запуск на D03 pilot, полный fit после D04. **Owners:** `ml/camera_coach/train.py`, `data/`, `losses.py`, `models/set_composition_net.py`, configs/contract checks.

1. Расширить существующий trainer реальными typed records; сохранить synthetic и silver research режимы явно, не строить третий независимый training framework.
2. Дать supervision необходимым scene, subjectness/ROI, issue, utility, good, abstention/risk, delta heads; каждая loss применяет собственную маску. Непомеченная delta не обучается к нулю. Utility conditional on intent/targets; запрещённые действия имеют свой смысл.
3. Настроить family-balanced sampler, class weights на train, paired ranking только на подходящих реальных/допустимых парах. Data augmentations трансформируют также ROI/directions/labels; слепой horizontal flip не сохраняет left/right labels.
4. Реализовать validation, early-stop, фиксированный selection rule, три seeds, trained-head mask и атомарный checkpoint/resume с optimizer/scheduler/RNG/sampler state.
5. Проверить маленький настоящий admitted batch: finite inputs/loss/gradients, нужные параметры меняются, masked targets не вносят loss, interrupted resume совпадает в допустимых численных пределах с непрерывным run.

**Готово:** документированная реальная CLI для human fit; она сохраняет честный receipt. До этого **не существует корректной команды полного обучения**, её нельзя сочинить в notebook. **Проверка:** environment/parity и самый узкий data/loss/resume smoke.

### M02 — готовый пакет Colab и возобновление

**Dependencies:** M01/D04; разработка packaging возможна на admitted pilot. **Owners:** `tools/dataset/package_camera_colab.py`, `package_camera_stage2_data.py`, `ml/camera_coach/colab/`, configs и run receipt.

1. Добавить явный профиль нового trainer/data version. Notebook — тонкий вызов той же CLI, один блок параметров: run ID, bundle/data locations, expected hashes, config, resume.
2. Подготовить README «загрузить/открыть → авторизовать → Run all → получить result manifest» без ручного поиска encoder по папкам. Existing local/Colab Stage1/Stage2 receipts сохранить, не перезапускать ради свежести.
3. Preflight проверяет hashes/schema/rights/splits, disk/RAM/VRAM, CUDA фактически используемых tensors, pretrained lineage, safe extraction. Ошибка до fit блокирует run; expected hash не переписывать под случайный архив.
4. Данные читать с local runtime disk после проверки; checkpoints/metrics/config/receipt атомарно сохранять в durable storage. На disconnect восстанавливать тот же run, если code/config/data/contract совпадают; иначе новый run с явным warm-start.
5. Проверить маленький pilot, намеренный controlled interruption и resume. Зафиксировать sec/step, VRAM, I/O, epoch estimate, фактический device. «GPU выбран» не доказывает, что вычисления выполнялись на GPU.

**Готово:** владелец проходит только реальный OAuth/подключение и запускает пакет; ИИ продолжает автоматически после получения manifest. **Остановка:** не обходить Google consent/2FA и не бесконечно повторять известный Drive mount failure. Альтернатива dedicated GPU оформляется с измерениями и отдельной санкцией расходов.

### M03 — controlled fit

**Dependencies:** D04/M02 и разрешённый runtime. **Owners:** те же trainer/config; внешние runs.

1. Зафиксировать baseline и candidate hypothesis, три seeds и selection rule **до** результата. Сравнить одинаковые данные/метрики; не выбирать удачное исключение после просмотра test.
2. Выполнить pilot schedule, затем полный fit; отслеживать train/validation gap, поhead loss, per-source/style slices и rare/forbidden actions. Сначала измерять проблему, затем менять schedule/архитектуру.
3. При невозможности выучить target проверить labels/masks/feature contract и доменный gap, а не просто увеличить epochs. Ветку архитектурного изменения проводить только с отдельной версией и доказанным основанием.
4. Сохранить все runs и selection receipt выбранного checkpoint. Другие seeds не исчезают из отчёта; train loss не называется quality.

**Готово:** один выбранный validation-кандидат с правами, кодом, обученными heads и reproducible receipt. **Проверка:** независимый review выбора и lineage; final holdout пока закрыт.

### M04 — калибровка и политика молчания

**Dependencies:** M03, отдельный calibration split, C05. **Owners:** existing calibration/fusion/safety owners, versioned policy.

1. Калибровать good/risk/abstention и action confidence на calibration data, с intent/style/source slices. Temperature/isotonic выбирать по заранее заданной validation-процедуре, не потому, что способ дал красивее цифры на test.
2. Настроить thresholds под §5 FP и coverage вместе. Порог отказа не имеет права скрыть отсутствие useful coverage.
3. Квалифицировать operation×case×mode×evidence profile, per-action verifier deadbands и fresh/stable windows. Недостающий локальный измеритель не заменять confidence VLM.
4. Проверить known good counterexamples, difficult light, OOD, wrong target/direction, контекст/замысел, no resource, loss of comparability.

**Готово:** замороженная policy с калибровочным report; good-frame защита и utility не смешаны с эстетической оценкой. **Проверка:** calibration curves/error/coverage slices и registry completeness.

### M05 — экспорт и интеграция candidate

**Dependencies:** M04/C05. **Owners:** `ml/camera_coach/convert_coreml.py`, existing ML manifest/preprocessing, `SETCompositionNetScorer.swift`, actual inference provider/fusion/registry.

1. Ввести явный receipt/export profile нового trained candidate. Не подделывать research Stage2 receipt и не просто переключать `release_admissible=true`.
2. Экспортировать exact checkpoint FP16 mlprogram; записать shape/dtype/head order, preprocessing/calibration hashes, supported heads, units, numerical tolerances, initializer/data lineage.
3. Сравнить PyTorch и Core ML на representative real/edge inputs: EXIF/mirror/aspect/ROI/no-ROI/missing scalars/dark/highlight. Одного deterministic parity примера недостаточно; проверить и числа, и итоговые решения на пороговых примерах.
4. Подключить candidate через существующий inference→evidence→safety путь в dev qualification. Ни тестовый scorer, ни путь DEBUG не считаются доказательством production use.
5. Измерить влияние fallback/model unavailable/invalid metadata. Неподдержанные heads не создают fabricated safe defaults. Старый research package не должен случайно попасть в final Release.

**Готово:** candidate реально влияет на предусмотренный runtime, одинаковые входы сохраняют смысл, research не принят за release. **Проверка:** parity + targeted scorer/pipeline tests; аппаратная latency и final admission после Q04.

### M06 — запечатанная оценка и решение по модели

**Dependencies:** M05, frozen D04/M04, C08 для temporal scope. **Owners:** existing Swift replay/eval, human protocols, registry.

1. Оценить один выбранный candidate с exact configuration на locked stills/sequences/episodes. Считать policy+model+planner+verifier, а не только logits.
2. Выдать §5 metrics с counts, intervals, subgroup failures; compare against same-source baseline. Отдельно оценить model output, admission, emitted UI и episode result: сохранённый `semantic_actions` список не равен числу показов.
3. При failure: gate остаётся FAILED; найти owner, новый candidate/config version, записать факт доступа к test. Не сделать бывший test снова «невиданным»: retest по замороженному reserve/новому независимому набору и правилам master.
4. Human и hardware части закрываются настоящими Q03/Q04 evidence; до них registry release admission остаётся pending.

**Готово:** офлайн verdict доказан, candidate идентифицирован; полная модель принимается только после остальных gates. **Не делать:** снижать threshold, выкидывать плохой class или считать abstention успехом без coverage.

## 8. Остальное приложение и backend

Полный Camera audit не заменяет исходный scope Scene Library → Generator → AR → Storyboard → запись/экспорт, Pro Controls и iPad. Эти пакеты выполняются параллельно ожиданию данных/GPU; уже существующее поведение сначала проверяется. Не возобновлять сотни исторических задач автоматически.

### S01 — исправить реальную wire-границу уточнений

**Dependencies:** P00. **Owners:** `SceneGenerationClient.swift`, `SceneGenerationAPIContracts.swift`, `backend/openapi-scene-v1.yaml`, `backend/scene_request_limits.py`, внешний `setos-backend/service.py` и его existing tests.

1. Зафиксировать canonical direct ClarificationAnswer body по Swift/OpenAPI. Проверить текущий HTTP adapter: он ожидает обёртку `answer`, которая не совпадает с producer.
2. Исправить принимающую границу минимально; вызвать канонический validator до записи ответа, проверить ограничения полей/размера/раундов. Не менять одновременно обе стороны, чтобы случайно скрыть нарушение frozen API.
3. Прогнать настоящий сериализованный Swift payload через HTTP handler и вернуть response в Swift decoder: valid answer, malformed, oversized, stale round, duplicate, чужой job, repeated answer.
4. Сохранить idempotency, cancellation, owner identity и transactional state. Обновить документацию границы только по итоговому контракту.

**Готово:** product body принимается; invalid body не меняет job. **Проверка:** узкие client/backend suites и producer→HTTP→consumer roundtrip, не два независимых зелёных fake-теста.

### S02 — готовый сервер и production configuration

**Dependencies:** S01/P00. **Подэтапы:** S02a — source/local HTTP/config/deploy preparation; S02b — реальная attested-device qualification на Q04. **Owners:** внешний backend, `backend-service-boundary-v1.md`, `SceneRemoteServiceComposition.swift`, `AppAttestServiceTokenProvider.swift`, request/limits owners.

1. Проверить уже существующие App Attest enrollment/assertions, counters, tokens, job store/worker, provider и clarification. Не строить заново реализованные компоненты.
2. Устранить недопустимые продовые env-only/debug injection paths: подготовить явную конфигурацию endpoint, app identity, provider/model revision, quotas, timeout, retention. Секреты — на сервере/в разрешённом secret storage, не bundle и не plan.
3. Проверить ownership на всех endpoints, replay/nonce/counter, idempotent requests, cancel/late worker result, crash/restart recovery, quota reservation/refund, round cap, request-size/time limits. «Безлимитные ресурсы» разработки не снимают runtime limits.
4. Подготовить deploy/runbook с existing stack, health/readiness, sanitized logs, data deletion/retention, backup/restore и provider outage. Один backend, без микросервисов/новой multi-provider платформы.
5. Поднять разрешённый staging/production только при наличии конкретного hosting/account/egress authorization. До него локальный end-to-end доступен, deployment отмечен внешней зависимостью. Физический App Attest roundtrip — S02b/Q04. Для S02a допустим реальный локальный HTTP test с явно тестовой identity/config; production authentication bypass, mock attestation в production и ослабление проверки ради раннего PASS запрещены.

**Готово S02a:** проверенная source/local конфигурация, подготовленный повторяемый deploy и operations packet; S02b закрывается только настоящим device roundtrip на Q04; security/failure paths не зависят от удачи worker. **Проверка:** existing targeted server suites, локальный реальный HTTP roundtrip, затем разрешённый live endpoint; fixtures не заменяют provider/device evidence.

### S03 — законченный Scene Generator

**Dependencies:** S02a для кода; D05 для offline/human Scene quality. **Подэтапы:** S03a — настоящий protocol/local HTTP path и подготовленный staging; S03b — квалификация device-authenticated product flow на Q04. **Owners:** `SceneGeneratorViewModel.swift`, `SceneParserService.swift`, `SceneRemoteServiceComposition.swift`, `SceneCreateJobRequestBuilder.swift`, existing v9 pipeline/validator.

1. Проследить именно production text→request→job→clarification→validated SceneScript/bundle→saved project. Не подключать только legacy parser, которого нет на активном экране.
2. Проверить RU/EN, длинный текст, отказ/timeout, повторный submit, cancel, background/resume, поздний response после другой сцены, revision ownership и повторный запуск приложения.
3. Сохранить entity/chunk IDs, source order, chronology, actor/target binding. Расследовать текущий SceneBundle demo duplicate-phone/ID case; чинить, если путь достижим/нужен scope, иначе явно оставить историческим без ложного green релизного пути.
4. Оценить model/provider на замороженном D05 по существующим Scene gates master. Если quality не проходит — локализовать grounding/contract/model причину; fine-tune Generator только после baseline, не автоматически обучать ещё одну сеть.

**Готово S03a:** product-path protocol и локальный HTTP flow дают валидный сохранённый редактируемый результат или ясную ошибку без порчи проекта. S03b дополнительно требует реальный device-authenticated endpoint на Q04; до этого не заявлять финальную production qualification. **Проверка:** Scene client/bundle/save tests + accepted staging scenario и замороженный Scene eval; старый camera replay эту часть не покрывает.

### S04 — Library, AR и Storyboard как один workflow

**Dependencies:** S03a, P00 current evidence. **Owners:** существующие Library/DB/project lifecycle, Scene/AR view model, Storyboard и media references.

1. Открыть/создать/сохранить/переименовать/удалить настоящий проект; проверить restart, missing asset, частичный failure, transactional deletion и связь с записью.
2. Проверить уже существующие planned-action hint bindings, AR placement/edit/recovery, неизменность entity identity при выборе действия. Не писать повторный `refreshSceneHintBinding` вместо существующего.
3. Пройти Scene → AR → Storyboard → Camera/Library и обратно: awaited teardown, одна camera session authority, state/selection сохранены по контракту. Не использовать fake thumbnails/демо-объекты вместо данных проекта.
4. Сверить старые source gates M6/M8 с текущим diff. Закрыть реальные gaps; физический world tracking, anchors и interruptions остаются для Q04.

**Готово:** реальные проекты и storyboard переживают необходимые переходы/перезапуск; failure не выдаёт успешный save/delete. **Проверка:** existing Library/SceneSaveLoad/AR/Storyboard relevant suites и production navigation captures; аппаратный AR — отдельно.

### S05 — recording/media lifecycle и recovery

**Dependencies:** P00/C08/S04 в части общего маршрута. **Owners:** существующие recorder contracts/SerializedMediaRecorder/SceneRecordingController/CameraService/RecordingArtifactStore.

1. Сверить historical M7 source PASS с изменёнными callers. Не переизобретать recorder; проверить begin/commit configuration, один writer/capture owner, stop/finalize idempotency.
2. Пройти запись из всех обязательных entry points, route switch, background, interruption, cancel/error, low disk, denied microphone/Photos, audio absent, restart recovery.
3. Проверить real file ownership, playable artifact, thumbnail, duration/audio metadata, transactional promotion/save/export/delete. Ошибка cleanup не должна создавать вымышленный успешный artifact.
4. Новые Camera подсказки не меняют recording state и не записывают голосовые команды без соответствующего явного режима. Защитить media от concurrent teardown.

**Готово:** source/targeted state matrix закрыта, аппаратный протокол подготовлен. **Проверка:** существующие recorder/recovery/adapter/lifecycle suites только затронутых путей; реальный A/V sync и hardware interruptions — Q04.

### S06 — линзы, Pro Controls, iPad и единый UI

**Dependencies:** C06/C07/S04/S05. **Owners:** существующие lens/pro controls/presentation, `LegacySceneGeneratorCameraShell.swift`, visual tokens, localization.

1. Проверить обнаруженные hardware lenses, фактически применённые ISO/WB/exposure/focus, rejected-value persistence, pause/resume. Расследовать оставшиеся LensSwitch baseline и telephoto preservation failures, не объявлять их вечными flakes.
2. Принять одну iPad scope policy: текущий platform contract full-screen/no Split View против AR test resize step — конфликт требований, а не повод заставить приложение пройти невозможную комбинацию. Сохранить обязательный iPad, зафиксировать корректный сценарий проверки.
3. Проверить существующие tray/keyboard shortcuts/ProControls wiring, layouts portrait/landscape, safe areas, Dynamic Type и VoiceOver на iPhone/iPad. Не удалять уже существующие features из-за старого статуса missing.
4. Закрыть пустые/ошибочные/loading/permission states, RU/EN overflow и reachable controls существующей SET OS v2.6 системой. Не начинать redesign, не добавлять subscriptions/StoreKit из устаревшего списка blockers без продуктовой необходимости.

**Готово:** полная обязательная навигация и controls согласованы со state; physical usability — Q04. **Проверка:** current lens/pro/presentation suites + матрица production captures; локальный visual approval не переносится автоматически на новые состояния.

### S07 — права, privacy и эксплуатационный пакет

**Dependencies:** D01, S02a и source/data-flow часть C09, финальный состав bundle уточняется после M05. **Owners:** `docs/implementation/provenance/`, `third-party-notices/`, `PrivacyInfo.xcprivacy`, `Info.plist`, release metadata/privacy drafts, existing settings/about.

1. Обновить component inventory по фактическому bundle: модели, llama/frameworks, шрифты, AR assets, текстуры и исходники. Каждому — версия/hash/license/disposition; training lineage и redistribution решаются отдельно.
2. Сформировать credits/notices и доступную страницу privacy/support. Credits здесь — указание авторства, **не виртуальная валюта и не новая монетизация**.
3. Проследить реальные потоки данных local/staging/cloud: что отправляется, когда, кому, сколько хранится, как удаляется, как отзывается согласие; API keys/frames/личные данные не текут в logs. App Privacy ответы строить по фактам, не по фразе «on-device ML».
4. Проверить required-reason API, включённые SDK/privacy manifests, purpose strings camera/microphone/Photos и фактическое поведение permission failures. Сам Core ML не означает автоматически отдельную декларацию каждого вида данных.
5. Подготовить hosting/provider retention/region/export-compliance решения и документы для владельца. Не отмечать спорные права cleared собственной уверенной формулировкой.

**Готово:** нет неизвестных обязательных provenance/privacy blockers у финального состава либо они явно блокируют READY; все drafts соответствуют данным. **Проверка:** существующие manifest/bundle/provenance validators + inspection настоящего Release и network paths.

## 9. Интеграция, люди, устройство — и граница передачи владельцу

### Q01 — один интегрированный candidate

**Dependencies:** source/local части C01–C09, M05/M06 offline, D05/S03 Scene quality, S01, S02a/S03a, S04–S07 source, P03; S02b/S03b и аппаратная часть C09 ожидаются до Q04. Это кандидат для финального устройства, а не заранее прошедшая hardware сборка.

1. Снять согласованную version tuple: source+dirty snapshot, backend revision/config, dataset/split/label/rights receipts, model+calibration+preprocessing hashes, toolchain, registry.
2. Пройти полные пользовательские сценарии из §10 ниже. Нельзя показать зелёный camera-only build и объявить готовым весь SET OS.
3. Выполнить релевантную интеграционную сертификацию исправленным runner; отдельные known failures локализовать, а не автоматически переименовать в flake. Собрать Debug build-for-testing и unsigned Release через существующий gate на этом candidate.
4. Проверить actual Release composition: research/debug assets, keys, ненужные models/frameworks не попали; полезная production модель реально wired. Отсутствие PENDING прав не выводится из exit=0, если validator лишь печатает список blockers.

**Готово:** source/runtime/release evidence привязаны к одному candidate, обязательные source/integration failures закрыты. Это ещё не human/device/Apple PASS.

### Q02 — human evaluation и пакет реальных действий

**Dependencies:** стабильный Q01; протокол и наборы готовятся с D03. **Owners:** existing capture/human-eval protocol, подготовленные packets, реальные участники/оценщики.

1. Дать владельцу готовый shot list без необходимости сочинять условия: portrait, two objects, labels/glare, documentary no-staging, low light, wide-angle near face, hands/props, moving background, scene cut, lens switch.
2. Для каждой реальной попытки фиксировать предложенное действие, понял ли человек, смог ли выполнить, что изменил фактически, before/after, intent, target/protected, latency, отмену/причину отказа без принудительного объяснения.
3. Слепая оценка expert/участников различает visually improved, useful instruction, executable, harmful и intent preserved. Красивый after по другой причине не доказательство успешного совета.
4. Выполнить quotas и gates master; owner-only informal просмотр использовать как development feedback. Разногласия adjudicate по protocol, не большинством субагентов.

**Готово:** настоящие голоса и real action evidence, §5 human gates; если нет людей — подготовка verified, сама оценка blocked_external. **Не делать:** заполнять surveys от лица реальных людей или считать AI hints независимым оценщиком.

### Q03 — подготовка финального физического прогона

**Dependencies:** Q01; подготовка возможна заранее. **Owners:** существующие `docs/implementation/device-tests/recording-v1.md`, `ar-workspace-v1.md`, test topology, release evidence.

1. Выдать владельцу один готовый пакет для iPhone 13 Pro и обязательного доступного iPad: install procedure, exact build identifier, тестовые материалы, порядок сценариев, куда сохраняются diagnostics/видео, как вернуть manifest.
2. Добавить новые v3 case checks к существующему протоколу; не дублировать весь hardware handbook. Отдельно выбрать weakest supported profile из реально заявленной матрицы; не требовать iPhone 17 Pro.
3. Составить automatic report importer с проверкой exact build/device/OS/source timestamps. Не превращать снимок экрана в доказательство thermal или audio sync.

**Готово:** человек может выполнить протокол без дополнительного проектирования; ни один hardware gate не отмечен pass заранее. Этот пакет не требует устройства до согласованного конца.

### Q04 — реальное устройство и финальная model qualification

**Dependencies:** Q01/Q03, доступные реальные устройства; human field часть Q02 может идти в той же съёмочной сессии, с отдельными оценщиками/receipts.

1. Выполнить camera permissions/denied/restricted, autofocus/exposure/lenses, pause/resume, route/background, subject identity, two objects, before-after и output crop на фактической камере.
2. Измерить end-to-end p50/p95, skipped/stale frames, energy/thermal, memory, длительную live/recording сессию и ECO поведение. Проверить master budgets: Vision/geometry p95≤150 ms, composition≤100 ms, planner≤10 ms, accepted analysis sample≤250 ms, Camera RSS p95≤350 MB. Percentiles компонентов не суммировать как total p95.
3. Проверить hardware AR/recording, A/V sync, реальные interruptions, low disk/recovery/export/Photos. Исторические simulator PASS не заменяют эти шаги.
4. Закрыть S02b/S03b и аппаратную часть C09: выполнить реальный App Attest challenge/enrollment/assertion roundtrip на настроенном backend и правильной identity; wrong app/environment, повтор assertion и отказ должны обрабатываться предсказуемо.
5. Проверить VoiceOver, Dynamic Type, touch/accessibility и RU/EN на настоящих экранах. Оператор может отменить невыполнимый совет; shutter и запись не заблокированы коучем.
6. При failure исправить owner, создать новый candidate и повторить затронутые checks. На финальном candidate пересчитать все evidence invalidated изменением; нельзя оставить старое устройство как свидетельство новых весов.

**Готово:** physical/human/offline gates вместе позволяют принять exact model и runtime; registry/bundle admission меняется только по полному receipt. Если не доступен iPad или Apple identity, честно blocked, не «для iPhone почти достаточно».

### Q05 — синхронизация доказательств и научных документов

**Dependencies:** выполняется после значимых пакетов, финальный проход после Q04. **Owners:** `diploma.md`, thesis router→`03_evidence_map.md`, `04_claim_registry.md`, затронутые snapshots/chapters; existing execution state.

1. Записать, что реализовано/измерено, на каких данных и версиях; разделить research-only, offline, human, physical и release evidence.
2. Исправить устаревшие claims в затронутых artifacts, поставить `needs_update` главам с ещё не отражёнными результатами. Не переносить плановые числа в «достигнуто» и не скрывать single-rater ограничения.
3. Сначала evidence map и claim registry, затем практические главы; litreview не менять. Модели/corpora rights и версии указывать фактические.

**Готово:** проектная история и научные утверждения согласованы с доказательствами; нет заявлений о публикации или качестве, которого не проверяли. **Проверка:** узкий source/link/status review, без повторного benchmark ради текста.

### Q06 — пакет для начала Apple publishing workflow

**Dependencies:** Q02/Q04/Q05, закрытые S02b/S03b и разрешённый S02 deployment и S07 права, финальный Q01 повтор при изменениях.

1. Повторно проверить актуальные требования Apple в официальных источниках, scheme/target/minimum OS/SDK, entitlements, bundle IDs/versioning, privacy/support URLs, age rating/export compliance drafts.
2. Заморозить final candidate и собрать reproducible Release; если существующие signing credentials уже доступны и их использование разрешено — подготовить signed archive/IPA/dSYM. Если нет, подготовить проверенную archive/export recipe с точным списком Apple inputs. Не называть unsigned build подписанным.
3. Обновить существующие `AppStoreMetadata.draft.json`, `AppPrivacyAnswers.json`, `ReviewNotes.draft.md`, `AppStoreSubmissionGates.json`, `ExportOptions.plist`; подготовить реальные screenshots на конечном UI и перечень owner-only marketing/account решений.
4. Убрать нерелевантный blocker StoreKit, только если подтверждено отсутствие approved paid feature; не внедрять подписки ради старого JSON. До первого релиза достаточно управляемого candidate и ручного release GO, не rollout платформы.
5. Передать единую сводку: source/model/backend/build hashes, satisfied gates, remaining Apple-only steps, install/archive/export commands, human/device reports, notices/privacy/support, known limitations и воспроизводимый recovery/rollback.

**Готово:** `READY_FOR_APPLE_WORKFLOW` означает проверенный pre-Apple candidate. В owner packet явно оставить M14 TestFlight/external beta с исходными выборкой/gates и возможной remediation, затем M15 final RC/submission; они ещё не пройдены. Включить в packet: internal smoke на iPhone+iPad; external beta 15–20 релевантных пользователей, минимум 15 и ≥200 meaningful sessions; все подсистемы; zero open P0/P1; исправления и повторная квалификация затронутого exact binary. Эти требования взяты из master M14-012–017, не сводятся к нажатию Upload. Не выставлять статус, когда остались data rights, обучение, недостающий evaluator, обязательный hardware gate или неработающий backend.

**За пределом автоматического выполнения этого плана:** принятие соглашений Apple, покупка membership/тарифов, создание/изменение коммерческих обязательств, загрузка в ASC, TestFlight invitations, submit/App Review и публичный release. Всё технически необходимое подготовить заранее. При дополнительном разрешении эти шаги продолжаются по существующему master R24–R26; новая approval от Apple остаётся внешним решением. Не обещать App Store approval.

## 10. Сквозные сценарии и расписание зависимостей

### 10.1. Обязательные демонстрации на реальном production path

| Сценарий | Успех | Негативная ветвь, которую нельзя пропустить |
|---|---|---|
| Хороший или намеренный кадр | Узко обоснованный KEEP либо честный ABSTAIN | Не «исправлять» silhouette, dutch angle, negative space без intent; не маскировать отсутствие данных похвалой. |
| Одна направленная коррекция | Тот же accepted action в тексте/overlay; эффект измерен | Повернул не туда / другой человек сдвинулся / граница пересекла нужную деталь. |
| Две одинаковые вещи | Точный target, protected человек, тот же track | Swap, occlusion, чужая лампа, потерянная ROI; никакого успеха по движению человека. |
| Боковой перенос при ровном горизонте | Выбранное слияние устранено | Завал горизонта без изменения слияния не улучшение. |
| Технический дефект | Одна доступная операция focus/exposure/hold/obstruction | Нет функции, намеренный blur/low key, false finger, отсутствующая салфетка/лампа. |
| Документальная сцена | Оператор меняет только допустимые собственные действия | Не переставлять участников/доказательства, не ждать ценой события. |
| Короткий выбранный клип | Временные claims ограничены измеренным coverage | Sample gaps, scene cut, identity swap, playback/import не запускает скан всей библиотеки. |
| Cloud review по запросу | Consent → ограниченный request → grounded evidence → локальное решение | Offline, stale generation, invalid payload, refusal, quota; никакого скрытого egress. |
| Scene generation | Текст → реальный backend → clarification → валидный сохранённый проект | Duplicate submit, cancel, restart, чужой job, malformed answer. |
| Проект целиком | Library → AR → Storyboard → запись → просмотр/export → restart | Teardown race, missing file, low disk, denied permissions, транзакционная ошибка удаления. |
| iPad/Pro | Действительно применённые настройки и поддержанный layout | Rejected control value, lens switch/pause-resume, accessibility и клавиатура. |

### 10.2. Очередь волн

| Волна | Параллельные задачи | Условие перехода |
|---|---|---|
| 0 | P00 → P01; параллельно P03, D01/D05, S01 | Current-state ledger, сохранённый diff и source defects локализованы. |
| 1 | C01→C02→C03; D02a→D03; S02a/S03a | Структурные типы и настоящий media pilot. |
| 2 | C04→C05; M00/P02 на pilot → D02b; S04; S05 подготовка | Правдивый vertical slice и freeze catalog/labels/metrics. |
| 3 | C06/C07/C08; D04; M01 после M00/D02b; S05 завершение после C08; S06/S07 | Реальные labels/splits и production-capable trainer; shared files сериализованы. |
| 4 | M02→M03; C09; независимые Scene/UI исправления и thesis sync | Reproducible Colab run; нет idle ожидания при доступной работе. |
| 5 | M04→M05→M06; Q01/Q03 preparation | Exact integrated candidate и offline verdict; hardware/human ещё не подменены. |
| 6 | Q02 и Q04 с S02b/S03b; targeted repairs; Q05 | Фактические human/device gates и исправленные результаты. |
| 7 | Q06 | Handoff владельцу; Apple публикация отдельно. |

Стрелки не разрешают перескакивать dependencies, указанные в карточке. GPU fit не запускается до freeze и admission данных. Полный физический прогон — в конце, как просил владелец; но исправление аппаратного failure может вернуть работу в более раннюю волну.

### 10.3. Что требуется от владельца и как подготовить это заранее

| Input | Кто готовит | Когда действительно блокирует |
|---|---|---|
| Голоса в GUI и независимые gold/field reviewers | ИИ готовит packets/tooling; владелец и реальные люди дают голоса | D03/D04/M06/Q02; один владелец не обязан вручную размечать весь corpus в одиночку. |
| OAuth/Drive и доступ к Colab runtime | ИИ готовит notebook/bundles/hashes/resume; владелец авторизует | M02/M03; отдельный автоматизируемый CLI не заменяет login. |
| Права на конкретный source/initializer | ИИ собирает evidence/alternatives, право подтверждается надлежащим источником/владельцем | Допуск конкретных данных/весов; другие admitted источники обрабатываются дальше. |
| Реальные устройства и съёмочные действия | ИИ готовит один готовый protocol/collector | Q02/Q04; финальные результаты не симулируются. |
| Hosting/provider/domain/account policy | ИИ готовит deploy/config/операционку | Настоящий endpoint S02/C09; локальная подготовка продолжается. |
| Apple Developer/ASC/сертификаты/2FA и финальный GO | ИИ готовит drafts, exact candidate и команды | Signing при отсутствии готового доступа и следующая publishing-фаза; не блокирует автономные source/data задачи. |

## 11. Команды и evidence: что можно копировать исполнителю

Это существующие CLI, проверенные чтением файлов при составлении плана. Исполнитель сверяет `--help` и environment перед запуском; выполняет только команду своего пакета. Новая human-training CLI появляется в M01, документируется и проверяется **до** того, как M02 вставит её в notebook. Не подставлять неподтверждённые flags старому research trainer.

### 11.1. Начало работы

```sh
cd /Users/unterlantas/Documents/XCode/shafinMultitool
git status --short
git rev-parse HEAD
git branch --show-current
git diff --check
xcodebuild -list -workspace shafinMultitool.xcworkspace
xcrun simctl list devices available
```

Выбрать реально доступный simulator из вывода. Не копировать исторический UDID/iOS version из журнала. Проверка `-list` нужна при восстановлении toolchain/scheme, не при каждом мелком slice.

### 11.2. Один существующий Swift suite

Объявленные ниже переменные — параметры исполнителя, не автоматически найденные значения. `CAMERA_TEST_UDID` устанавливается из discovery, `CAMERA_TEST_CLASS` — существующий релевантный класс; например `ActionVerifierTests`. Новый уникальный `CAMERA_VERIFY_ROOT` создаётся для этого запуска.

```sh
: "${CAMERA_TEST_UDID:?set from simctl discovery}"
: "${CAMERA_TEST_CLASS:?set an existing affected test class}"
CAMERA_VERIFY_ROOT="$(mktemp -d /tmp/setos-verify.XXXXXX)"
xcodebuild test \
  -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination "platform=iOS Simulator,id=$CAMERA_TEST_UDID" \
  -only-testing:"shafinMultitoolTests/$CAMERA_TEST_CLASS" \
  -derivedDataPath "$CAMERA_VERIFY_ROOT/DerivedData" \
  -resultBundlePath "$CAMERA_VERIFY_ROOT/result.xcresult"
```

Примеры existing owners/suites: `CameraAnalysisDomainContractsTests`, `CameraCoordinateSpaceTests`, `SubjectIdentityRegistryTests`, `SubjectTrackerTests`, `ActionVerifierTests`, `CoachingEpisodeCoordinatorTests`, `SemanticTipPlannerTests`, `CameraAdviceSafetyGateTests`, `CameraCoachClosedLoopTests`, `SETCompositionNetScorerTests`, `SceneGenerationClientTests`, `SceneSaveLoadTests`, `RecordingRecoveryAndRetentionTests`, `ProControlsPresentationTests`. Выбирать по изменённому пути, не запускать весь список после каждого пакета. `CameraCoachClosedLoopTests` с capture scheduler при необходимости выполнять serial, сохраняя смысл проверок.

### 11.3. ML/data checks

В dependency-capable Python environment проекта/Colab выбрать только затронутое:

```sh
python3 ml/camera_coach/contracts/check_parity.py
python3 ml/camera_coach/data/check_preprocessing_parity.py
python3 ml/camera_coach/check_training_environment.py
python3 tools/dataset/camera_coach_check.py --self-test
: "${CAMERA_DATASET_MANIFEST:?set the actual candidate manifest}"
python3 tools/dataset/governance_check.py --manifest "$CAMERA_DATASET_MANIFEST"
python3 ml/camera_coach/preflight_device.py
```

`camera_coach_check.py --self-test` проверяет сам checker на fixtures, а не новый corpus. У `governance_check.py` вызов без `--manifest` использует default fixture; такой PASS запрещено выдавать за admission данных. Последняя команда требует CUDA для настоящего fit по текущей policy; CPU override допускается только для bounded smoke. Не считать MPS автоматическим равноценным обходом зафиксированной проблемы скорости. Current research packaging/conversion можно использовать только для соответствующего исторического профиля, не для production data:

```sh
: "${CAMERA_RESEARCH_BUNDLE:?set a fresh external research output path}"
python3 tools/dataset/package_camera_colab.py build --profile stage2 --output "$CAMERA_RESEARCH_BUNDLE"
```

`CAMERA_RESEARCH_BUNDLE` **нельзя** брать из `mktemp -d`: пакаджер намеренно отказывает на симлинковых путях, и на macOS обе обычные формы дают симлинк — голый `mktemp -d` возвращает `/var/...` (`/var` → симлинк), а `mktemp -d /tmp/x.XXXXXX` даёт `/tmp/...` (`/tmp` → симлинк). Обе команды печатают `FAIL path uses a symlink` и выходят с кодом 1. Рабочая форма — `/private/tmp`:

```sh
CAMERA_RESEARCH_BUNDLE="$(mktemp -d /private/tmp/setos-research.XXXXXX)/stage2.zip"
```

Проверено прогоном: голый `mktemp -d` → `FAIL path uses a symlink: /var`; `mktemp -d /tmp/…` → `FAIL path uses a symlink: /tmp`; `mktemp -d /private/tmp/…` → `PASS`.

Этот пример **не запускает обучение** и не является финальным production recipe. M02 обязан создать проверенный профиль нового пакета; M05 — receipt-aware export. `tools/camera_dataset_audit.py` и другие audit tools сначала проверить через их реальную CLI; не придумывать путь `tools/dataset/camera_dataset_audit.py`.

### 11.4. Backend

В клиентском repo, когда затронуты limits:

```sh
python3 -m pytest backend/tests/test_clarification_answer_limits.py
```

Во внешнем backend использовать его существующее окружение и фактический framework suite. Пример узкого unittest для текущего clarification файла, после проверки, что зависимости установлены:

```sh
cd /Users/unterlantas/Documents/XCode/setos-backend
PYTHONPATH=/Users/unterlantas/Documents/XCode/shafinMultitool/backend \
  .venv/bin/python -m unittest -v test_clarification_flow.py
```

Файл действительно использует unittest; перед выполнением сверить текущие imports и окружение, не требовать установку лишнего runner. Unit suite не закрывает необходимый настоящий HTTP roundtrip S01.

### 11.5. Финальный Release

Только Q01/Q06 на согласованном candidate:

```sh
cd /Users/unterlantas/Documents/XCode/shafinMultitool
SETOS_RELEASE_CHECK_ROOT="$(mktemp -d /tmp/setos-release-gates.XXXXXX)"
scripts/run_release_gates.sh --derived-data-root "$SETOS_RELEASE_CHECK_ROOT"
```

Сохранить результаты во внешнем durable evidence location/manifest перед удалением временного каталога. Этот gate проверяет Debug/unsigned Release/privacy/provenance/bundle, но не гарантирует signing, distribution, device или TestFlight. Список оставшихся component blockers анализировать отдельно от exit code. `scripts/run_camera_certification.sh` использовать только после P03 с обнаруженным UDID и task-owned output.

Archive/export инструкции уже есть в `docs/implementation/release/ExportOptions.plist`; привязать их к текущим scheme/team/profile и конкретному candidate. Не придумывать Team ID, signing identity, пароль или Apple agreement acceptance.

## 12. Пакет завершения, внешние источники и запреты на ложный PASS

Финальный отчёт исполнения должен содержать:

1. Статус из §3.1 и список verified task IDs; отдельно внешние блокеры с готовыми owner packets.
2. Candidate tuple: source+dirty snapshot, backend config/revision, model/calibration/preprocess, dataset/schema/splits/rights, toolchain/build; что именно устанавливалось на устройства.
3. Таблицу §5 gates: observed numerator/denominator, threshold, interval, passed/failed/insufficient, evidence path. Отсутствующий результат не ноль ошибок.
4. Матрицу 68 cases и operations: qualified/conditional/unsupported; честные ограничения перечислены в user-facing review, где уместно.
5. Полный сценарий install→shoot→advise→verify и Scene→AR→record→export, production RU/EN captures, human/device receipts.
6. Existing App Store drafts/notices/privacy/support, signed artifacts при разрешённой подготовке либо точную signing recipe, список следующих Apple-only действий.
7. Краткую запись в существующем execution journal и обновлённые затронутые thesis claims. Не создавать ещё один master plan для следующего продолжения.

Проверенные внешние основания на 2026-09-13, перепроверить перед actual upload:

- Apple публикует актуальные [минимальные SDK/Xcode требования](https://developer.apple.com/news/upcoming-requirements/); на момент проверки указаны Xcode 26+ и SDK iOS/iPadOS 26+. Это требование сборки, не приказ сделать minimum deployment target iOS 26.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) и [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) требуют соответствия реальным функциям/данным и правам, а не только наличия markdown checklist. [Required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) проверяются по фактическому API use/SDK.
- [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) разделяет attribution и запрет коммерческого использования; перечисление автора не снимает второе условие. У конкретных pixels/annotations/weights могут быть разные условия, их нельзя вывести из общей лицензии репозитория.
- [Colab FAQ](https://research.google.com/colaboratory/intl/en-GB/faq.html) прямо не гарантирует неограниченные ресурсы: потому checkpoint/resume обязательны даже при большом бюджете.
- Apple описывает [phased release для version updates](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases). Не делать сложный staged rollout обязательной разработкой перед первой публикацией; последующие updates можно планировать отдельно.

**Запрещённые способы «закончить»:** удалить обязательный scope; выдать research вес за production; занулить unknown labels; принять scorer confidence за calibrated probability; отрегулировать thresholds по test; сделать всю модель ABSTAIN ради safety score; зачесть движение bbox как устранение дефекта; сравнить другого адресата; объявить любое исчезновение предмета выполненным удалением; назвать credits коммерческими правами; заполнить голоса или аппаратные результаты от лица людей; принять exit=0 сломанного runner как успешные тесты; назвать uploaded/submitted/released то, что только собрано локально.
