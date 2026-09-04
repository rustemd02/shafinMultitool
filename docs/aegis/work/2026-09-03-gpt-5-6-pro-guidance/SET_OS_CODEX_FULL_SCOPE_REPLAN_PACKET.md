# SET OS / Shafin Multitool — Full-Scope Replan Packet for Codex

**Purpose:** one self-contained input packet for the next Codex session.

## Authority and precedence

1. The **Full-Scope Replan Prompt** below is the active instruction and has priority over the previous plan wherever they conflict.
2. The **Previous App Store 1.0 Master Plan** is retained as prior analysis, evidence mapping, thresholds, risks, and task material. It is not automatically authoritative after the full-scope correction.
3. Codex must inspect the current checkout and current diff before relying on any historical path, HEAD, test result, bundle inventory, or release claim.
4. This packet does not authorize destructive Git operations, commits, pushes, worktrees, paid actions, Apple account actions, or physical-device claims.
5. SET OS v2.6 remains the visual authority. Do not restart moodboarding or create a parallel design system.
6. Before changing production source, Codex must first produce the full-scope revised execution plan required by the active prompt, reconcile it against the current repository, and explicitly identify which recommendations from the previous plan are retained, modified, or rejected.

---

# PART I — ACTIVE FULL-SCOPE REPLAN PROMPT

# Prompt for GPT-5.6 Pro — Full-scope App Store 1.0 replan

Ты — независимый principal iOS engineer, ML lead, product architect и App Store release owner. Перед тобой handoff Shafin Multitool / SET OS, исходный код, тесты, release scripts, ML/eval материалы, Visual Policy v2.6, evidence и предыдущий документ `SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN.md`.

Изучи все приложенные материалы до ответа. Отличай:

- source-backed реализацию;
- тестовый контракт, который ещё нужно свежо выполнить;
- fixture/mock;
- исторический или устаревший claim;
- simulator evidence;
- physical-device evidence;
- signed-distribution evidence.

Не утверждай, что запускал код, тесты, Xcode, модели или устройства, если это не было фактически доступно в приложениях.

## 1. Статус предыдущего master plan

Предыдущий план полезен как аудит, но его Camera-only App Store cut отклонён владельцем.

Следующие решения предыдущего плана объявлены `SUPERSEDED`:

- Camera-only public build;
- исключение Scene Library;
- исключение Scene Generator;
- исключение AR Workspace;
- исключение Storyboard;
- исключение video recording/playback/export;
- исключение lens switching;
- rear-wide-only product scope;
- исключение Pro Controls;
- iPhone-only;
- полный отказ от production neural inference в пользу Vision/if-only policy.

Не создавай errata или дополнение к старому документу. Создай новый самостоятельный execution document:

`SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md`

Он должен полностью заменять предыдущий master plan и быть достаточным для последующих Codex-сессий без чтения старого плана.

## 2. Окончательно принятый владельцем App Store 1.0 scope

Ниже перечислены уже принятые продуктовые решения. Не проси повторного approval и не предлагай удалить эти возможности ради более быстрого MVP.

### 2.1 Camera Coach

В публичный релиз входят:

- полный entry/permission/blocked flow;
- live camera preview;
- корректное определение объекта или группы;
- ручной выбор объекта касанием при неоднозначности;
- стабильное отслеживание выбранного объекта;
- распознавание композиционных и технических проблем;
- одна безопасная рекомендация за раз;
- marker-аннотации и target-linked geometry;
- `KEEP`, `CORRECT`, `SELECT_SUBJECT`, `WAIT`, `ABSTAIN`;
- короткое объяснение «Почему?»;
- полный цикл `detect → advise → user moves → verify result`;
- portrait и landscape;
- RU и EN;
- Dynamic Type, VoiceOver, Reduce Motion/Transparency;
- честные interruption, unavailable, thermal и error states.

### 2.2 Scene Library

В релиз входят:

- empty/loaded/selected states;
- создание и переименование сцены;
- duplicate-name handling;
- delete confirmation;
- persistence failure;
- реальные previews или честные metadata placeholders, но не fake thumbnails;
- корректная связь с Generator, AR, Storyboard и recording artifacts;
- доступность на iPhone и iPad.

### 2.3 Scene Generator

В релиз входят:

- screenplay input;
- keyboard states;
- detected/marked objects;
- clarification;
- accepted/leader/progress stages;
- cancel/background/recovery;
- parse/network/model failure;
- retry;
- success;
- production parser/model delivery story;
- structured and validated output;
- связь результата с AR и Storyboard.

### 2.4 AR Workspace

В релиз входят:

- preparing/ready/surface-search;
- placement;
- marking;
- live hints;
- hint pause;
- playback;
- recording;
- interruption;
- error;
- async teardown;
- world tracking и lifecycle recovery;
- iPhone и iPad layouts/orientations;
- доказательство на физических устройствах.

### 2.5 Storyboard

В релиз входят:

- tray collapsed/expanded;
- selection/reflow;
- result;
- inspector;
- editor medium/large;
- сохранение;
- validation failure;
- delete confirmation;
- marker-name sheet;
- Decision Trace/«Почему?»;
- реальные связи со сценой, AR и recording media.

### 2.6 Video recording и media lifecycle

В релиз входят:

- фактическая запись камеры;
- микрофон;
- начало/остановка записи;
- recording owner и ownership ledger;
- корректная ориентация и metadata;
- interruption/recovery;
- stop/finalize races;
- A/V sync;
- playback;
- Photos export;
- share;
- retention;
- Pending promotion;
- cold-launch recovery;
- low-disk behavior;
- project deletion и cleanup связанных файлов;
- privacy disclosures;
- физическая device verification.

### 2.7 Lenses и Pro Controls

В релиз входят:

- переключение доступных физических объективов;
- пользовательские `0.5×`, `1×`, `2×`, только если соответствующие lenses реально доступны;
- отсутствие fake lens options;
- continuity capture/session при переключении;
- Pro Controls;
- определение точного минимального набора Pro Controls на основе существующего продукта и beginner use case;
- доступность и portrait/landscape layouts.

### 2.8 iPad

iPad является полноценной release platform, а не compatibility mode.

Нужны:

- adaptive layouts;
- size classes;
- portrait/landscape;
- logical reading order;
- Camera Coach;
- Scene Library;
- Generator;
- AR;
- Storyboard;
- recording/playback;
- keyboard support;
- Dynamic Type/VoiceOver/Reduce Motion;
- iPad physical-device matrix;
- App Store screenshots.

### 2.9 Neural inference

Production neural inference является обязательной частью продукта. Полностью heuristic/Vision-only Camera Coach владельцем отклонён.

Apple Vision, deterministic geometry и rules могут использоваться как:

- feature extractors;
- safety layer;
- fallback;
- abstention policy;
- verifier;
- interpretable baseline.

Но production architecture должна содержать обучаемый neural component, который даёт измеримый вклад в понимание кадра или выбор безопасного действия.

Это не означает, что обязательно сохраняются именно текущие DETR, NIMA, llama или отсутствующая `compact_neural_evidence_net`. Для каждого компонента выбери один статус:

- `KEEP`;
- `RETRAIN`;
- `REPLACE`;
- `REMOVE_AFTER_VERIFIED_REPLACEMENT`;
- `CAMERA_ONLY`;
- `SCENE_ONLY`.

Нельзя сначала удалить neural capability, а потом обещать когда-нибудь вернуть её. Любое удаление должно иметь проверенную replacement path.

## 3. Что остаётся открытым для твоего технического решения

Ты должен самостоятельно выбрать и обосновать:

1. Целевую Camera Coach neural architecture.
2. Нужно ли сохранить/переобучить DETR и NIMA или заменить их.
3. Нужна ли compact multi-task Core ML model.
4. Нужна ли visual embedding model.
5. Как связать neural output, Apple Vision, deterministic policy и verifier.
6. Архитектуру Scene Generator parser/model.
7. Нужен ли backend для Generator, Deep Review, model delivery или quality feedback.
8. Какие функции должны работать offline.
9. Какой минимальный набор Pro Controls нужен начинающей съёмочной команде.
10. Минимальную поддерживаемую iOS/iPadOS версию после проверки API.
11. Как обеспечить release/legal story для моделей, данных, fonts, AppIcon, USDZ, llama и других компонентов.

Не выбирай самый маленький продукт. Выбирай минимально сложную архитектуру, которая реализует весь утверждённый scope.

## 4. Главная задача

Составь конечную программу работ от текущего dirty checkout до полноценного App Store Release Candidate.

Нужен не обзор и не список из десяти рекомендаций, а полный исчерпывающий Task Tracker.

Tracker должен включать ВСЕ необходимые задачи:

- аудит и воспроизводимость checkout;
- исправление correctness/race/ownership проблем;
- Camera Coach;
- neural model и данные;
- Scene Library;
- Generator;
- AR;
- recording/playback/media lifecycle;
- Storyboard;
- lenses/Pro Controls;
- iPhone;
- iPad;
- UI/SET OS compliance;
- localization;
- accessibility;
- privacy;
- provenance/legal;
- build configuration;
- tests;
- performance/thermal;
- CI;
- signed archive;
- TestFlight;
- App Store Connect;
- release evidence.

Количество задач НЕ ограничено. Если для честного плана нужно 80, 150 или 250 задач — перечисли их все.

Не объединяй крупные месяцы работы в строки вроде «реализовать ML», «доделать AR» или «отполировать UI». Каждая задача должна быть достаточно узкой, чтобы Codex мог взять её как отдельный worker packet, изменить ограниченный набор файлов, выполнить конкретную проверку и остановиться на явном gate.

## 5. Обязательная Camera Coach architecture

Опиши end-to-end data flow:

```text
capture
→ immutable frame/timestamp ownership
→ subject resolution
→ temporal tracking
→ feature extraction
→ neural inference
→ confidence calibration
→ safety/abstention gate
→ action planner
→ temporal stabilization
→ SET OS marker presentation
→ user movement observation
→ before/after verification
→ improved/unchanged/worse/incomparable
```

Закрой существующие риски:

- camera-vs-subject direction inversion;
- orientation/mirroring transforms;
- mixed-age pause evidence;
- unstable subject identity;
- ambiguous group/object intent;
- uncalibrated confidence;
- harmful advice;
- overcorrection of already-good frames;
- advice flicker;
- stale advice after rotation/lens/lifecycle changes;
- subject/overlay occlusion;
- false verification success.

## 6. Полный AI/ML delivery plan

Для Camera Coach и Scene Generator отдельно дай:

### 6.1 Product contract

- supported classes;
- supported actions;
- forbidden actions;
- abstention rules;
- failure/fallback behavior;
- user-visible limitations.

### 6.2 Dataset

- record schema;
- source provenance;
- rights/consent;
- minimum volume by class/action;
- stills and temporal sequences;
- before/after episodes;
- hard negatives;
- already-good frames;
- difficult light;
- intentional stylistic exceptions;
- data storage/versioning.

### 6.3 Annotation

- independent annotators;
- adjudication;
- annotation guide;
- acceptable multiple actions;
- forbidden actions;
- hidden QC;
- agreement thresholds;
- human gold freeze.

### 6.4 Leakage protection

- split by shoot/scene/person/location/time family;
- derivation families;
- exact and perceptual deduplication;
- locked holdout;
- retest policy;
- dataset/model/eval hashes.

### 6.5 Training and conversion

- exact candidate architectures;
- baseline;
- training stages;
- losses;
- calibration;
- ablations;
- random seeds;
- reproducible environment;
- Core ML conversion;
- quantization;
- model card;
- artifact provenance;
- bundle integration;
- rollback.

### 6.6 Evaluation

- actual Swift runtime output;
- offline metrics;
- per-class/action thresholds;
- harmful/forbidden advice rate;
- good-frame preservation;
- calibration/selective risk;
- verification accuracy;
- temporal stability;
- human blind evaluation;
- latency/memory/thermal;
- physical-device protocol;
- binary go/no-go criteria.

Не отвечай «соберите больше данных». Укажи конкретные минимальные объёмы, этапы расширения и точные условия, при которых model candidate принимается либо отклоняется.

## 7. Backend decision

Проведи отдельное решение для каждого use case:

- live Camera Coach;
- Deep Review;
- Scene Generator;
- model delivery/update;
- telemetry/quality feedback;
- accountless usage;
- media sync, если он действительно нужен.

Для каждого выбери:

- `LOCAL_ONLY`;
- `OPTIONAL_REMOTE`;
- `BACKEND_REQUIRED`;
- `POST_1_0`.

Live Camera Coach должен иметь полезный offline path.

Если backend нужен, дай минимальный production contract:

- API schema;
- auth;
- rate limit/quota;
- timeout/retry/idempotency;
- encryption;
- region;
- consent;
- redaction;
- retention/deletion;
- provider/model versioning;
- observability;
- cost ceiling;
- fallback;
- kill switch;
- App Privacy implications.

Не проектируй микросервисы и provider-neutral abstractions без доказанной необходимости.

## 8. AR, recording и media correctness

Отдельно спроектируй задачи и gates для:

- ARKit session ownership;
- surface search и placement;
- world tracking;
- interruption/background/foreground;
- async teardown;
- recording source ownership;
- start/stop/finalize races;
- A/V sync;
- orientation metadata;
- dropped frames;
- microphone permissions;
- Photos permissions;
- playback;
- share/export;
- low disk;
- Pending ownership;
- cold-launch recovery;
- OS kill during promotion;
- retention;
- deletion/orphan cleanup;
- sustained thermal and memory behavior.

Simulator не является доказательством этих возможностей.

## 9. iPad plan

Не ограничивайся `TARGETED_DEVICE_FAMILY = 1,2`.

Дай отдельный tracker для:

- supported iPad generations;
- split/full-screen behavior;
- size classes;
- portrait/landscape;
- external/software keyboard;
- safe areas;
- Camera preview geometry;
- AR layouts;
- Library/Generator/Storyboard information density;
- VoiceOver order;
- Dynamic Type;
- Reduce Motion;
- multitasking decision;
- device performance;
- App Store media.

Если iPad multitasking несовместим с camera/AR, предложи честный supported-orientation/windowing contract, но не удаляй iPad из релиза.

## 10. SET OS/UI constraints

Не возвращай проект к moodboards или новому арт-дирекшну.

Единственный visual authority:

`docs/implementation/ux/set-os-visual-policy.md` — SET OS v2.6.

Сохраняются:

- советская полиграфическая сетка и типографика;
- A24-сдержанность и приоритет кадра;
- функциональная плёнка;
- marker-on-glass annotations;
- микроскевоморфизм только как пунктуация;
- один `setOrange`;
- motion event ownership;
- Reduce Motion behavior;
- motif budget.

Запрещены:

- новая параллельная дизайн-система;
- generic cards;
- material/blur/shadow/gradient;
- fake thumbnails;
- повторный moodboard phase;
- decorative polish вместо закрытия correctness.

Для каждого reachable screen/state включи задачи проверки:

- RU/EN;
- required orientations;
- iPhone/iPad;
- Dynamic Type;
- VoiceOver;
- Reduce Motion/Transparency;
- keyboard where relevant;
- upright screenshots;
- motion video where relevant.

## 11. Release, privacy и legal

Tracker обязан включать:

- current checkout receipt;
- diff ownership/classification;
- reproducible candidate;
- target/resource/framework inventory;
- model/data/media/font/AppIcon/USDZ provenance;
- machine-readable disposition records;
- third-party notices in distributed artifact;
- privacy manifest;
- runtime egress audit;
- Privacy Policy;
- Support URL;
- App Privacy answers;
- age rating;
- export compliance;
- secret/config audit;
- full production test suite;
- durable `.xcresult` and logs;
- performance/thermal evidence;
- clean unsigned release gates;
- signed archive;
- codesign/entitlements inspection;
- Apple Validate;
- App Store Connect upload/processing;
- internal TestFlight;
- external TestFlight;
- final metadata/screenshots/review notes;
- exact-binary RC manifest.

## 12. Обязательный полный Task Tracker

Создай раздел `FULL_TASK_TRACKER`.

Он должен содержать не выборочные примеры, а все задачи до App Store RC.

Формат каждой строки:

```text
ID
milestone
priority
subsystem
objective
exact repo areas/files
behavior owner
dependencies
can_start_now
blocked_by
autonomous_or_external
implementation notes
acceptance criteria
narrow verification
required evidence
device matrix
rollback/kill condition
stop gate
```

Требования:

1. У каждой задачи уникальный стабильный ID.
2. Все зависимости ссылаются на реальные ID.
3. Ни одна задача не называется просто «доделать», «улучшить», «полировать» или «реализовать ML».
4. Крупные задачи делятся до отдельного reviewable diff/worker packet.
5. Указывай конкретные repo areas и вероятные файлы из attachments.
6. У каждой задачи есть бинарный acceptance criterion.
7. У каждой задачи есть минимальная, но достаточная verification.
8. Device-only evidence явно отделяется от simulator evidence.
9. External actions не смешиваются с автономным кодом.
10. Tracker продолжается до TestFlight и App Store submission, а не заканчивается на реализации UI.
11. Количество задач не ограничено.
12. Не сокращай tracker ради длины ответа.

Если весь tracker не помещается в один ответ, выводи его последовательными частями:

- `PART 1/N`, `PART 2/N`, ...;
- без пропуска ID;
- без пересказа уже выданных частей;
- последняя часть обязана содержать полный dependency audit и RC gate.

## 13. READY_NOW queue

После полного tracker создай отдельный раздел `READY_NOW`.

Это не ограничение tracker десятью задачами. Это фильтр из полного tracker.

В него должны войти ВСЕ задачи, которые можно начать прямо сейчас после уже принятого product scope:

- без physical device;
- без Apple account;
- без legal approval;
- без новых owner product decisions;
- без destructive Git operations.

Количество `READY_NOW` задач также не ограничено.

Раздели их на:

- sequential critical path;
- parallel-safe workstreams;
- documentation/data tooling;
- tests/release tooling;
- ML preparation;
- UI/correctness work.

Затем отдельно выдели `FIRST_EXECUTION_PACKET` — только первый безопасный пакет, который Codex действительно должен начать первым. Он может содержать 5–15 тесно связанных задач, но не заменяет полный tracker.

## 14. Обязательная структура документа

Новый документ должен содержать:

1. `EXECUTIVE_VERDICT`
2. `SUPERSEDED_DECISIONS`
3. `FIXED_APP_STORE_1_0_SCOPE`
4. `VERIFIED_SYSTEM_MAP`
5. `P0_P1_P2_BLOCKER_REGISTER`
6. `TARGET_PRODUCTION_ARCHITECTURE`
7. `CAMERA_COACH_NEURAL_ARCHITECTURE`
8. `SCENE_GENERATOR_MODEL_ARCHITECTURE`
9. `DATASET_TRAINING_EVALUATION_PROGRAM`
10. `BACKEND_DECISION`
11. `AR_RECORDING_MEDIA_CORRECTNESS_PLAN`
12. `IPAD_STRATEGY_AND_DEVICE_MATRIX`
13. `SET_OS_SCREEN_AND_EVIDENCE_MATRIX`
14. `PRIVACY_PROVENANCE_APP_STORE_PLAN`
15. `FULL_TASK_TRACKER`
16. `DEPENDENCY_DAG`
17. `MILESTONES_AND_GATES`
18. `READY_NOW`
19. `FIRST_EXECUTION_PACKET`
20. `EXTERNAL_ACTION_QUEUE`
21. `DEFINITION_OF_RELEASE_CANDIDATE`
22. `KILL_AND_FEATURE_DEGRADATION_CRITERIA`
23. `ASSUMPTIONS_CONFIDENCE_AND_OPEN_FACTS`

## 15. Milestones

Минимальные milestones:

```text
M0 current-state/reproducibility
M1 correctness and ownership races
M2 Camera Coach closed loop
M3 dataset and human-gold infrastructure
M4 production neural model
M5 Scene Library and Generator
M6 AR Workspace
M7 recording/playback/media lifecycle
M8 Storyboard
M9 lenses/Pro Controls
M10 iPad/adaptive UI/accessibility
M11 localization/SET OS evidence
M12 privacy/provenance/legal
M13 full verification/performance/device matrix
M14 signed build/TestFlight
M15 App Store Release Candidate
```

Покажи:

- обязательный critical path;
- задачи, которые можно вести параллельно;
- gates, после которых запрещено продолжать;
- owner/device/legal/account dependencies;
- какие evidence закрывают каждый milestone.

## 16. Definition of Release Candidate

RC definition должна быть бинарной и покрывать весь зафиксированный scope.

Нельзя признать RC готовым, если:

- Camera Coach не проходит neural/human/device quality gates;
- before/after verifier даёт ложный success;
- Scene Library/Generator/AR/Storyboard недостижимы или используют fake data;
- recording/playback/A/V sync/storage recovery не доказаны на устройствах;
- lens selector показывает несуществующий объектив;
- Pro Controls не соответствуют фактическому capture configuration;
- iPad является только растянутым iPhone UI;
- full production suite не green;
- archive содержит неизвестные модели/framework/media;
- privacy/legal не соответствуют бинарнику;
- signed ASC binary отличается от проверенного TestFlight binary;
- остаются открытые P0/P1.

Если отдельная функция не проходит gate, не предлагай молча удалить её из scope. Зафиксируй `NO-GO`, причину, remediation tasks и повторный gate.

## 17. Ограничения исполнения

- Не трогать `docs/thesis/litreview*`.
- Не использовать `git reset`, `git clean`, `git stash`, force checkout или worktree.
- Не commit/push без отдельного разрешения владельца.
- Не перезаписывать user changes.
- Не использовать iPhone 17 Pro.
- Не менять CommercialShell route semantics без доказанной миграции.
- Сохранять awaited async teardown ownership.
- Сохранять accessibility identifiers либо давать явную migration map.
- Не выдавать simulator evidence за hardware evidence.
- Не выдавать существование теста за его прохождение.
- Не выдавать source code за release verification.
- Не добавлять model/backend/SDK без measurable need, provenance, budget и exit criterion.
- Не возвращаться к moodboards.
- Не создавать новый visual authority.

## 18. Финальная инструкция

Твоя задача — не уменьшить продукт и не перечислить общие рекомендации.

Твоя задача — выдать полный, конечный, dependency-ordered execution system, по которому Codex сможет последовательно довести весь утверждённый Shafin Multitool / SET OS App Store 1.0 до одной проверенной подписанной сборки.

В конце ответа обязательно укажи:

1. общее количество задач в `FULL_TASK_TRACKER`;
2. количество задач `READY_NOW`;
3. количество задач, требующих device;
4. количество задач, требующих owner/legal/account/human action;
5. первый `FIRST_EXECUTION_PACKET`;
6. ближайший milestone, после которого можно впервые честно измерить end-to-end пользовательскую ценность.

Не ограничивай полный tracker десятью задачами. Первые задачи — только стартовая очередь внутри полного плана.

---

# PART II — PREVIOUS MASTER PLAN AND PRIOR ANALYSIS

> This section is preserved as prior work. It must be critically reconciled with Part I rather than followed blindly.

# SET OS / Shafin Multitool — App Store 1.0 Master Plan for Codex

**Purpose:** this is the single execution document for the next Codex sessions.  
**Product:** Shafin Multitool / SET OS  
**Primary release goal:** ship a smaller, honest, measurable App Store 1.0 centered on Camera Coach.  
**Visual authority:** `docs/implementation/ux/set-os-visual-policy.md` (SET OS v2.6).  
**This document is an execution directive, not a new design brief.**

---

## 0. Operating rules for Codex

Before changing source:

1. Inspect the **current** checkout and current diff. The handoff was captured on branch `store`, but the checkout is known to have been dirty at handoff time. Do not assume the old HEAD or old file counts still match.
2. Treat:
   - **source code** as evidence of implementation,
   - **tests** as contracts until freshly run,
   - **fixtures/mocks** as non-production evidence,
   - **historical docs** as claims that may be stale,
   - **signed archive / Apple validation / device runs** as the only valid evidence for release facts they actually cover.
3. Do not report that anything was run, built, tested, archived, validated, or verified unless the current session actually produced that evidence.
4. Do not start with redesign, moodboards, a second visual language, or decorative polish.
5. Do not edit `docs/thesis/litreview*`.
6. Do not use destructive Git operations:
   - no `git reset`,
   - no `git clean`,
   - no `git stash`,
   - no force checkout,
   - no worktree creation,
   - no commit/push unless the owner separately authorizes it.
7. Preserve existing user changes. When a target file has unrelated uncommitted changes, stop and isolate the smallest safe edit.
8. Do not require or use **iPhone 17 Pro** for this project.
9. Do not change:
   - CommercialShell route semantics,
   - awaited async teardown ownership,
   - existing accessibility identifiers,
   unless a concrete migration need is first demonstrated and covered by focused tests.
10. Simulator evidence must never be presented as proof of:
    - physical camera behavior,
    - real lenses,
    - microphone,
    - Photos,
    - ARKit tracking,
    - recording/playback,
    - A/V sync,
    - thermal behavior,
    - hardware timing.
11. Do not add a backend, model, SDK, or framework unless it has:
    - a measurable product need,
    - a release/legal story,
    - a cost/performance budget,
    - a clear exit criterion.
12. The execution order is:
    **reproducibility → correctness → ML quality → release/legal/privacy → device qualification → TestFlight → App Store RC**.

### Handoff inputs this plan was derived from

The original handoff consisted of:

- `00-README-FIRST.md`
- `01-CURRENT-STATE-REPORT.md`
- `04-CHECKSUMS.md`
- `10-camera-coach-source.txt`
- `11-scene-mode-source.txt`
- `12-tests-and-release-source.txt`
- `13-authority-and-evidence-docs.txt`
- `14-ml-eval-and-dataset-snapshot.txt`
- visual evidence:
  - `approved-concept.png`
  - `camera-corrective-ru-portrait.png`
  - `camera-en-landscape-dynamic-type.png`
  - `generator-workspace-ru-landscape.png`
  - `library-selected-ru-landscape.png`
  - `storyboard-result-ru-tray-expanded.png`
  - `marker-draw-corrective-ru-portrait.mp4`

The handoff checksum file reported successful handoff integrity checks and no credential values beyond expected API-key variable names. This does **not** prove the current checkout is clean or identical to the handoff snapshot.

---

# 1. Brutal executive verdict

## Readiness: **32 / 100**

This is a score for **App Store release-candidate readiness**, not code volume.

| Area | Score | Reason |
|---|---:|---|
| Product/visual direction | 11/15 | Camera Coach is clearly the primary value and SET OS v2.6 is already an adequate visual authority |
| Implemented engineering base | 13/25 | Camera, lifecycle, local analysis, planner, shell, Scene/AR/recording contours and a large test surface exist |
| Proven core user value | 3/25 | Advice exists, but a trustworthy end-to-end `detect → advise → user moves → verify result` loop is not release-proven |
| Release/legal/privacy | 5/20 | Validators and a privacy manifest exist, but provenance, metadata, signed distribution and final disclosures are not closed |
| Physical-device / beta evidence | 0/15 | Required camera/device/thermal/live-sequence evidence and external beta are missing |

## Three main reasons the product is not shippable

### 1. The core promise is not closed end-to-end

The product promise is not “show a tip”. It is:

> detect a practical framing problem or preserve a good frame → give one physical action → observe the change → verify whether it improved the frame.

Source supports Camera Coach states and advice machinery, but the handoff explicitly identifies subject clarification, action observation, and before→after verification as incomplete or insufficiently evidenced.

### 2. Current recommendation quality is below a safe release bar

The broad 207-case evaluation reported:

| Metric | Result |
|---|---:|
| pass rate | 0.671498 |
| expected-action hit | 0.748792 |
| forbidden-action violation | 0.188406 |
| good-frame preservation | 0.875000 |
| technical gate | 0.962963 |
| confidence accuracy | 0.859903 |
| demo pass | 0.500000 |
| forbidden violations | 39 |
| missing expected actions | 52 |
| good-frame overcorrections | 12 |

The earlier 107/107 result is development regression evidence only. It must not be treated as a generalization result because the later broader set collapsed sharply and the labels are not locked human gold.

### 3. Release evidence does not exist yet

At handoff time there was no current, reproducible release candidate with:

- a clean immutable baseline,
- a fresh full green suite,
- closed provenance/legal blockers,
- required physical-device evidence,
- signed archive,
- codesign inspection,
- Apple Validate,
- processed App Store Connect build,
- external TestFlight evidence.

---

## DO NOT BUILD

Stop spending time on the following until the Camera Coach critical path is closed:

- new moodboards;
- new design systems;
- full visual resets;
- Scene Generator expansion;
- AR feature expansion;
- Storyboard expansion;
- History;
- new Pro Controls;
- StoreKit;
- credits;
- subscriptions;
- account systems;
- analytics SDKs;
- production backend;
- another VLM transport;
- another third-party model;
- additional DETR/NIMA tuning against familiar data;
- vague “cinematic” recommendation types;
- object-naming advice without grounded object identity;
- new recording features;
- cosmetic polish on screens removed from 1.0;
- hiding unfinished features behind undocumented runtime switches in the App Store binary.

---

## Exact recommended App Store 1.0 cut

**App Store 1.0 = free, local-first, iPhone-only Camera Coach for framing/setup before recording.**

### Included

1. iPhone-only.
2. Portrait + landscape Camera Coach.
3. Rear wide camera only for the release-critical flow.
4. Contextual camera permission flow.
5. Automatic person/group subject resolution.
6. Tap-to-select for objects, food, ambiguous subject, or failed auto-selection.
7. One stable recommendation at a time from a closed action catalog.
8. Explicit safe states:
   - `KEEP`
   - `CORRECT`
   - `SELECT_SUBJECT`
   - `WAIT`
   - `ABSTAIN`
9. Short optional “why” explanation.
10. Full before→after verification:
    - baseline frozen,
    - relevant movement observed,
    - after-state stabilized,
    - outcome classified as:
      - improved,
      - unchanged,
      - worse,
      - incomparable.
11. RU + EN after editorial review.
12. No frame upload and no live network dependency.

### Excluded from Store 1.0

- Scenes;
- Generator;
- AR workspace;
- Storyboard;
- Decision Trace UI;
- History;
- video recording;
- microphone;
- Photos;
- Speech Recognition;
- front camera;
- multi-lens selector;
- Pro Controls;
- Deep Review;
- remote VLM;
- StoreKit;
- subscriptions;
- credits;
- DETR;
- NIMA;
- `compact_neural_evidence_net`;
- llama framework;
- GGUF;
- Scene-only USDZ assets;
- benchmark packs;
- fixture/mock providers;
- gallery/debug routes.

The source code may remain in the repository, but these features must not be reachable or secretly activatable in the public 1.0 build. Release target membership and bundle contents must match the cut.

### App Store promise

> **Point the camera, get one clear adjustment, make it, and Camera Coach checks the result. If the frame is already strong, it leaves it alone.**

Do not make claims such as:

- “understands any frame”;
- “AI cinematographer”;
- “makes footage cinematic”;
- “professional composition assessment”;
- “recognizes all objects”;
- “records production-quality video”;

unless those capabilities are separately reintroduced and release-proven.

---

# 2. Verified system map

**Important:** “test-backed” below means a test contract or saved historical evidence exists. It does **not** mean the current checkout has freshly passed that test.

| Subsystem | Implemented / source-backed | Test-backed | Fixture/doc-only | Missing | Release impact |
|---|---|---|---|---|---|
| Commercial launch / shell | Camera-first shell, single active route, lazy secondary routes, awaited teardown, transition lock | Routing/composition/UI-test source exists | Some screen evidence is simulator/fixture-based | Current reproducible launch evidence | Preserve mechanics; public 1.0 should expose Camera only |
| Camera entry / permissions | Intro, permission context, denied/restricted/unavailable/unknown recovery, foreground recheck | Entry model/presentation/UI tests exist | Simulator permission states | Real first-run permission recovery on device | Keep; physical gate |
| Camera capture / lifecycle | `AVCaptureVideoDataOutput`, scheduler, pause/resume, camera discovery | Lifecycle/scheduler tests exist | Benchmark harness | Hardware interruptions/timing | Keep; physical gate |
| Lens switching | Back-camera discovery and replacement transaction | Focused tests | UI fixtures | Real lens continuity | Remove from 1.0 |
| Scheduler / thermal | Multi-cadence scheduler and thermal governor | Scheduler/thermal tests | Benchmark config | Sustained physical thermal evidence | Keep internals; remove fake ECO UI |
| Vision subject detection | Face/person/saliency paths | Pipeline/semantic tests | Mock observations | Stable identity + tap owner | Keep and complete |
| `VisionTracking` | Frame-by-frame detection | Unit seams | Name implies tracking | Temporal identity tracking | Rework |
| Horizon | Horizon estimator + confidence | Focused tests | Synthetic tilt | Orientation/lens physical calibration | Keep |
| Lighting | Luma/backlight/subject metrics | Used in pipeline tests | Synthetic technical cases | Proper background masking and calibration | Rework |
| DETR | Core ML segmentation wrapper | DETR tests | Replay/fixture use | Calibrated confidence and closed provenance | Remove from 1.0 |
| NIMA | Core ML aesthetic wrapper | Pipeline/fusion tests | Threshold assumptions | Robust normalization, uncertainty, provenance | Remove from 1.0 |
| Compact neural evidence | Contracts/provider/fusion scaffolding | Neural/fusion mocks/tests | Mock snapshots | Production model artifact/training provenance | Do not ship |
| Deterministic critique | Critique engine, summary, issues/strengths | Domain/critique tests | Python proxy also exists | Conservative human-gold calibration | Keep but narrow |
| Advice planner | Recommendation plan, semantic planner, temporal gates | Planner/presentation tests | Proxy/oracle eval modes | Canonical direction semantics + calibrated abstention | Rework |
| Live presentation | Seeking/corrective/keep/explanation UI | Presentation/render/UI tests | Fixture-driven screenshots | Correct action geometry + outcome UI | Keep and fix |
| Direction mapping | `move_frame_*` actions + arrows | Partial mapping tests | Static copy fixtures | Unambiguous subject/camera coordinate contract | P0 |
| Subject clarification | Product/state docs expect it | No convincing end-to-end evidence | Contract-level documentation | Tap owner + selection persistence + tracking | P0 |
| Before→after verification | Product contract expects it | Analytics/state contracts exist | Spec/documentation | Episode owner + verifier + outcome UI | P0 |
| Pause review | Snapshot/reasoning/review exists | Pause tests | Fixture/VLM paths | Same-frame consistency | Keep, simplify |
| Remote VLM / Deep Critic | Contracts/environment transport/mock provider | Coordinator/mock tests | Prototypes | Provider, auth, privacy, cost, SLA | Remove from 1.0 |
| Scene library | Persistence and route exist | Model/UI tests | Screenshot reveals selected-row defect | Physical journey evidence | Cut |
| Generator/parser | Rules/LLM/chunking/result UI | Large parser test surface | GGUF benchmark paths | Release model provenance/quality linkage | Cut |
| AR workspace | Session/placement/maps/teardown plumbing | Coordinator/teardown tests | Simulator unavailable states | Physical ARKit qualification | Cut |
| Scene recording | Recorder/artifact/playback/share | Recorder/adapters tests | Simulator artifacts | Physical finalize/save/A-V sync/race evidence | Cut |
| Persistence | Scene projects + intro store | DB/save-load tests | Fixtures | Camera Coach episode owner | 1.0 persists intro/preferences only |
| SET OS visual system | Palette/type/spacing/marker/event owners | Token/gallery tests | Approved concept | Final physical-device evidence | Freeze; do not redesign |
| Localization | EN/RU String Catalogs | Catalog/glyph checks | Mechanical translations | Native editorial pass | P1 |
| Accessibility | IDs, Dynamic Type, Reduce Motion seams | UI/presentation tests | Partial screenshot coverage | Full VoiceOver/device pass | P1 |
| Privacy manifest | App-owned `PrivacyInfo.xcprivacy` exists | Validator/self-test | Older docs incorrectly say missing | Runtime data-flow audit + ASC answers | P0 release gate |
| Release bundle gate | Release scripts, allowlists, privacy/contamination checks | Shell/Python negative tests | Summary says 6 fixtures while script defines 11 | Machine-readable legal status + fresh run | Keep and repair |
| Test topology | Unit + UI targets exist, roughly ~850 methods reported | Many suites | Historical focused runs | Fresh complete production green suite | P0 |
| Signed distribution | No current signed archive evidence | None | Historical unsigned builds | Archive/export/codesign/Validate/upload | P0 |

---

# 3. Blocker register

## P0 — product/release blockers

| ID | Evidence | Root cause | User risk | Closure criterion |
|---|---|---|---|---|
| P0-BASE-01 | Handoff reported large modified/untracked state | No immutable candidate baseline | Evidence cannot be tied to shipped binary | Current diff classified and candidate revision/materialized state recorded |
| P0-CORE-01 | Accepted live slice stops before real action verification | Partial implementation of product promise | User gets text but not validated improvement | Real camera flow reaches `advice → action observed → verified outcome → live` |
| P0-ML-01 | 207-case metrics: 67.15% pass, 18.84% forbidden, 87.5% good preservation | Heuristics generalized poorly | Wrong advice destroys trust | All ML thresholds in §5 pass on locked human-gold holdout |
| P0-DATA-01 | Current labels are AI/synthetic-first and not locked human gold | No independent gold set | Metrics are not trustworthy release estimates | Human adjudication, shoot-level split, holdout freeze, zero leakage |
| P0-ACT-01 | Current action naming/copy can invert camera motion vs subject displacement | Coordinate semantics are ambiguous | User may move in the wrong direction | Canonical subject-target coordinate system + exhaustive orientation/mirroring tests |
| P0-LEGAL-01 | Known blockers include llama, DETR, NIMA, `Circle.usdz`, `Person.usdz` | Redistribution/provenance unresolved | Rejection/legal risk | These artifacts are absent from Store archive or separately legally approved |
| P0-TEST-01 | Historical broad audit: 593 total / 496 pass / 94 fail / 3 skip | Mixed test topology and stale evidence | Unknown regressions | Fresh default production unit/UI suite with zero failures |
| P0-DEVICE-01 | No complete hardware matrix | Simulator cannot prove hardware behavior | Crash, stale advice, thermal problems | Required device matrix passes |
| P0-ARCHIVE-01 | No signed archive/Apple validation | Distribution pipeline incomplete | App may fail upload/review | Signed archive validates, uploads, processes in ASC, audited by hash |
| P0-PRIV-01 | Final privacy policy, Support URL, ASC answers and runtime audit not closed | Source manifest mistaken for complete privacy compliance | Review rejection/inaccurate disclosure | Runtime egress audit + accurate policy/ASC packet |

## P1 — required quality blockers

| ID | Evidence | Root cause | User risk | Closure criterion |
|---|---|---|---|---|
| P1-FRAME-01 | Pause can combine DETR/NIMA from accepted pixel buffer with age-gated Vision/light/horizon | No immutable all-source frame envelope | Explanation may describe mixed timestamps | Every decision tied to one frame/declared temporal window |
| P1-XMARK-01 | Camera root xmark uses `dismiss()` in hosting root | No meaningful parent dismissal owner | Broken control | Remove from public camera-only build; preserve internal route behavior |
| P1-UI-01 | Corrective lower-third can obscure the scene being judged | Static layout not subject-aware | Advice blocks the shot | Advice avoids active subject/target region within bounded viewport |
| P1-CONFIG-01 | Current target family includes iPad; deployment targets disagree | Historical config drift | Unsupported configurations | iPhone-only + aligned iOS minimum |
| P1-GATE-01 | Release summary says 6 contamination fixtures; script defines 11 | Hard-coded reporting drift | False green confidence | Summary derived from actual fixture results |
| P1-LOC-01 | Catalogs are mechanically populated; mixed raw errors exist in secondary UI | Error/copy policy not fully owned | Amateur UX | All shipped Camera states editor-reviewed in EN/RU |
| P1-A11Y-01 | Partial accessibility evidence | Component-level testing only | Primary action may be inaccessible | VoiceOver + XXL + Reduce Motion + contrast pass |
| P1-EVID-01 | Some files named landscape were physically portrait/rotated | Evidence pipeline not physically inspected | False closure of visual gate | Fresh upright device evidence |
| P1-CI-01 | No minimal current CI | Ad-hoc verification only | Regression reintroduction | Reproducible build/unit/release checks on each candidate revision |

## P2 — defer if removed from 1.0

| ID | Defect | Why it may wait | Escalation |
|---|---|---|---|
| P2-SCENE-01 | Selected scene row overlap/nested buttons | Scene excluded | Becomes P1 if Scene returns |
| P2-SCENE-02 | Mixed RU/EN AR error | Scene excluded | P1 if Scene returns |
| P2-SCENE-03 | Generator clarification/recovery ownership incomplete | Generator excluded | P1 if Generator returns |
| P2-SCENE-04 | Recording teardown/owner-token race | Recording excluded | P0/P1 if recording returns |
| P2-ECO-01 | ECO is fixture-only | ECO removed from public UI | P1 if shown |
| P2-HISTORY-01 | History is stub/empty | History excluded | P1 if navigable |
| P2-LEGACY-01 | Legacy screens remain in repository | Repository presence is not release presence | P1 if reachable or bundled via hidden route |

## Contradictory / stale documents

- `README.md`: useful onboarding, but old test counts, dependencies, iOS assumptions and architecture claims are stale.
- `docs/app-store-product-plan.md`: contains older server/monetization/recording decisions; treat as product history where superseded by current cut.
- `docs/implementation/STATUS.md`: historical checkpoint and HEAD/build assumptions, not current checkout evidence.
- Historical `docs/aegis/**/90-evidence.md`: bounded evidence only; never extend its claim scope.
- 107/107 camera eval: development regression evidence only.
- 207-case camera eval: strongest current negative quality signal, but still not human-gold release evidence.
- Old screenshots with wrong orientation: not orientation evidence.
- `04-CHECKSUMS.md`: validates handoff payload integrity, not current Git checkout integrity.

---

# 4. Recommended 1.0 architecture

## Architecture choice

| Option | Strength | Critical weakness | Release decision |
|---|---|---|---|
| Current deterministic + DETR/NIMA | Already integrated | Weak broad eval, unresolved model provenance, uncalibrated/unsafe model semantics | Reject for Store 1.0 |
| Apple Vision + deterministic geometry | Existing system APIs, explainable, low provenance risk, local | Needs real subject tracking, selection, calibration, verifier | **Winner** |
| Compact trainable Core ML model | Could outperform thresholds and calibrate actions | No human-gold corpus / production artifact yet | Candidate after deterministic baseline |
| Opt-in remote VLM | Useful for ambiguous artistic review | No provider/backend/privacy/cost contract; network dependency | Post-1.0 experiment only |

## Winner

**Apple Vision + deterministic geometry + conservative calibrated policy + explicit abstention + before→after verifier.**

### Remove/replace for 1.0

Remove from Store composition:

- DETR;
- NIMA;
- compact neural evidence artifact expectation;
- remote VLM transport;
- llama framework;
- GGUF;
- Scene-only models/assets.

Replace the current semantic layer where necessary with:

- Vision face/person detection;
- saliency;
- temporal subject tracking;
- explicit user-selected subject region;
- horizon;
- subject/background-masked light metrics;
- deterministic action planner.

## Target data flow

```text
AVCaptureSession / rear wide camera
        │
        ▼
CameraManager
- single session owner
- lifecycle/orientation
- stable timestamps
        │
        ▼
FrameSampler
- geometry/light: ~6–8 Hz
- person/face redetection: ~3–5 Hz
        │
        ▼
AcceptedFrameEnvelope
- frameID
- timestamp
- orientation/mirroring
- pixelBuffer reference
- source timestamps
        │
        ├──► SubjectResolver
        │    - face/person/group
        │    - saliency
        │    - user-selected region
        │    - ambiguity detection
        │
        ├──► SubjectTracker
        │    - temporal identity
        │    - periodic redetection
        │    - explicit track loss
        │
        ├──► GeometryExtractor
        │    - edge pressure
        │    - subject size
        │    - target placement
        │    - horizon
        │
        └──► TechnicalExtractor
             - motion
             - subject luma
             - masked background luma
             - clipping/hotspot overlap
        │
        ▼
CompositionPolicyV1
- bounded issue/action catalog
- no free text
- no object naming
        │
        ▼
ConfidenceCalibrator + SafetyGate
- keep / correct / select / wait / abstain
        │
        ▼
AdviceStabilizer
- one active action
- hysteresis
- dwell time
- contradiction suppression
        │
        ▼
SET OS Presentation
- observation
- one action
- target-linked marker
- optional WHY
        │
        ▼
CoachingEpisodeCoordinator
- freeze baseline
- observe relevant movement
- preserve subject identity
        │
        ▼
ActionVerifier
- improved / unchanged / worse / incomparable
        │
        ▼
Resume live loop
```

## Ownership boundaries

| Boundary | Owner |
|---|---|
| Capture/session/lifecycle | existing `CameraManager` |
| Immutable frame identity | new `AcceptedFrameEnvelope` |
| Feature extraction | explicit Vision / geometry / lighting extractors |
| Subject choice | new `SubjectResolver` |
| Temporal identity | new `SubjectTracker` |
| Composition inference | narrowed deterministic policy |
| Advice selection | existing planner concepts against new action catalog |
| Stabilization | one temporal owner using hysteresis/motion |
| Verification | new `CoachingEpisodeCoordinator` + `ActionVerifier` |
| Presentation | existing SET OS v2.6 primitives |
| Persistence | intro + benign preferences only |
| Scene Mode | excluded from Store 1.0 |
| Backend | none |

## Fail/abstain behavior

| Condition | Behavior |
|---|---|
| No stable subject | `SELECT_SUBJECT` or `ABSTAIN` |
| Two similarly prominent people | treat union as group or ask user |
| Camera moving | `WAIT`, suppress semantic correction |
| Track lost | cancel current episode and reacquire |
| Orientation/lens/session change | invalidate transforms and episode |
| Distributed landscape without clear subject | horizon-only or abstain |
| Intentional low-key / uncertain backlight | abstain on exposure/light advice |
| Strong frame | stable `KEEP` |
| Thermal serious | lower analysis cadence; never show stale advice |
| Missing feature/model signal | mark unavailable; never coerce to a fake zero confidence |
| Verification frames incomparable | return `INCOMPARABLE`, never fake success |

---

# 5. ML/model delivery plan

## 5.1 Operational label taxonomy

### Seven mandatory release classes

1. `single_person`
2. `two_people`
3. `object_or_food`
4. `interior`
5. `street_or_landscape`
6. `difficult_light`
7. `already_good_frame`

### Issue labels

| Label | Observable condition | Allowed action |
|---|---|---|
| `subject_edge_pressure_left` | subject crowded against left edge | `place_subject_right` |
| `subject_edge_pressure_right` | subject crowded against right edge | `place_subject_left` |
| `subject_edge_pressure_top` | insufficient headroom/top clipping | `place_subject_down` |
| `subject_edge_pressure_bottom` | unsuitable lower clipping | `place_subject_up` |
| `subject_too_small` | subject scale too small for supported context | `move_closer` |
| `subject_too_large` | subject too large/clipped | `move_farther` |
| `horizon_tilt_clockwise` | reliable horizon tilted clockwise | `level_counterclockwise` |
| `horizon_tilt_counterclockwise` | reliable horizon tilted counterclockwise | `level_clockwise` |
| `subject_underlit` | subject materially underlit vs useful background | `add_front_light` |
| `background_hotspot_behind_subject` | hotspot/background dominates subject | `avoid_backlight` |
| `camera_unstable` | motion makes geometry unreliable | `hold_steady` |
| `ambiguous_primary_subject` | no safe automatic subject | `select_subject` |
| `already_good` | no material issue with adequate confidence | `keep_frame` |
| `insufficient_signal` | system cannot judge safely | `abstain` |

### Canonical action IDs

```text
place_subject_left
place_subject_right
place_subject_up
place_subject_down
move_closer
move_farther
level_clockwise
level_counterclockwise
add_front_light
avoid_backlight
hold_steady
select_subject
keep_frame
abstain
```

### Direction semantics

`place_subject_left/right/up/down` always describes the **desired subject position in the preview**, not the physical camera movement direction.

Marker rendering must:

- originate from the actual subject region,
- point toward the target region,
- apply orientation/mirroring transforms in one adapter,
- avoid copy such as “move the camera left” when the actual user goal is “place the subject further left/right”.

This explicitly fixes the high-risk camera-vs-subject inversion problem.

## 5.2 Forbidden advice for 1.0

Do not emit:

- `change_angle`;
- `make_more_cinematic`;
- `simplify_background`;
- “remove distracting object X”;
- arbitrary object names;
- `clean_lens`;
- `reduce_iso_noise`;
- `refocus_subject` without a real measured focus signal;
- directional action without a stable track;
- directional action on distributed landscape without selected subject;
- one-face crop advice in a two-person scene without intent;
- exposure correction for intentional low-key;
- horizon correction for explicit intentional Dutch angle;
- corrections on `already_good`;
- `keep_frame` when a dominant technical failure exists;
- any “improved” claim after subject/lens/orientation/scene identity changed;
- advice based solely on aesthetic/NIMA score;
- unavailable evidence converted into confident numeric state.

## 5.3 Dataset record contract

Recommended record:

```json
{
  "record_id": "cc_v1_...",
  "dataset_version": "cc-v1.0.0",
  "label_schema_version": "action-v1",
  "source_shoot_id": "...",
  "scene_instance_id": "...",
  "take_id": "...",
  "derivation_family_id": "...",
  "content_sha256": "...",
  "perceptual_cluster_id": "...",
  "matrix_class": "single_person",
  "content_tags": ["portrait", "window_light"],
  "subject_type": "person",
  "subject_regions": [],
  "issue_labels": [],
  "acceptable_primary_actions": [],
  "forbidden_actions": [],
  "abstention_allowed": false,
  "abstention_reason": null,
  "verification_predicate": {},
  "rights_disposition": "approved_for_internal_eval",
  "annotation_status": "human_gold_adjudicated",
  "annotator_votes": [],
  "adjudicator_id": "...",
  "split": "locked_holdout"
}
```

## 5.4 Dataset artifacts/versioning

```text
datasets/camera-coach/v1/
  README.md
  label-schema.json
  annotation-guide.md
  source-shoots.jsonl
  records.jsonl
  before-after-episodes.jsonl
  rights-manifest.jsonl
  derivation-manifest.jsonl
  split-manifest.json
  dedup-report.json
  qa/
    disagreements.jsonl
    adjudications.jsonl
    hidden-qc-results.json
  releases/
    cc-v1.0.0.manifest.json
    cc-v1.0.0.sha256
```

Version independently:

- dataset version;
- label schema;
- split version;
- feature schema;
- policy version;
- model version;
- calibration version.

Store only schemas/manifests/small approved fixtures in Git. Large raw photo/video data should live externally under content-addressed hashes.

## 5.5 Minimum reasonable data volume

Existing 207 cases remain **development regression** only.

| Artifact | Minimum | Structure |
|---|---:|---|
| Locked human-gold still holdout | 1,050 | 150 per each of 7 classes |
| Independent source shoots in holdout | 210 | ≥30 per class; max 5 decisions from one shoot |
| Calibration/validation | 700 | 100 per class, separate shoots |
| Before→after episodes | 420 | 60 per class |
| Hard negatives inside episodes | 140 | ≥20 per class |
| Physical live scripted sequences | 70 | 10 per class |
| Blind human comparison | 210 | 30 per class, 3 reviewers |
| Train set for compact feature model | 4,900 | 700 per class, ≥70 source-shoot families per class |

The 4,900 figure is suitable only for a **small structured-feature model**, not a general end-to-end vision foundation model.

For each production action family:

- ≥50 positive cases in locked holdout;
- ≥50 cases where the action is forbidden;
- ≥20 near-threshold cases;
- ≥10 intentional-style hard negatives.

## 5.6 Leakage guard / split rules

1. Split by `source_shoot_id` and `scene_instance_id`, never by adjacent frames.
2. Same person/location/take family should not cross train/calibration/holdout when visual conditions are near-identical.
3. Crops, color variants, synthetic degradations and image-to-image derivatives share one `derivation_family_id` and one split.
4. Frames within at least ±10 seconds from the same take cannot cross splits.
5. Public source stills and their synthetic variants never cross splits.
6. Synthetic data is separately bucketed and cannot hide poor organic performance.

Dedup:

- exact SHA-256;
- perceptual hash, initial `Hamming <= 6`;
- local embedding similarity `cosine >= 0.985`;
- suspicious pairs checked with SSIM `>= 0.92` and manual review;
- split by whole dedup cluster;
- `cross_split_leak_count = 0` required.

Holdout freeze:

1. Create sorted manifest before final tuning.
2. Hash manifest with SHA-256.
3. Store hash in release evidence.
4. Do not use holdout failures as a new calibration set.
5. Any post-holdout tuning requires a new holdout version or a predeclared single retest policy.

## 5.7 Annotation QA

- Two independent annotators.
- No model output shown.
- Annotate:
  - issue labels,
  - acceptable primary actions,
  - forbidden actions,
  - abstention permissibility,
  - verification predicate.
- Disagreements go to third adjudicator.
- 10% adjudicated records re-reviewed.
- 5% batches include hidden QC seeds.

Minimum agreement:

| Annotation | Gate |
|---|---:|
| keep/correct/abstain | Cohen κ ≥ 0.80 |
| primary action family | κ ≥ 0.75 |
| forbidden-action agreement | ≥ 0.90 |
| person/object subject-region IoU median | ≥ 0.80 |

If agreement fails, rewrite the annotation guide and relabel. Do not hide disagreement by averaging it into a fake “gold” label.

## 5.8 Before→after verification contract

`CoachingEpisode` should contain:

```text
episodeID
baselineFrameID
subjectTrackID
actionID
baselineFeatures
targetPredicate
safetyPredicates
acceptedAt
expiresAt
```

Verification algorithm:

1. Freeze baseline.
2. Wait for **relevant** movement, not merely a later frame.
3. After movement, require at least 5 stable frames over ≥0.8 s.
4. Require subject identity continuity.
5. Compare only action-specific metric(s).
6. Check safety regression.
7. Return:
   - improved,
   - unchanged,
   - worse,
   - incomparable.

Initial predicates:

| Action | Success predicate |
|---|---|
| `place_subject_*` | distance to target region improves ≥20% and ≥0.04 normalized units |
| `move_closer` | subject area approaches target band ≥15%, no clipping |
| `move_farther` | oversize/clipping improves ≥15%, subject retained |
| `level_*` | abs tilt improves ≥1.5°, final tilt ≤1.5° |
| `add_front_light` | subject luma +≥0.08, readability improves, clipping does not increase >0.02 |
| `avoid_backlight` | hotspot overlap / subject-background deficit improves ≥20% |
| `hold_steady` | motion remains below still threshold ≥0.8 s |

`KEEP` also requires a stable window, not a single lucky frame.

## 5.9 Baselines / ablations

### Baselines

- **B0:** historical 207-case current runtime; regression reference only.
- **B1:** Vision geometry conservative, no tracking/manual tap.
- **B2:** B1 + temporal subject tracking.
- **B3:** B2 + manual tap/ambiguity.
- **B4:** B3 + verifier.
- **C1:** compact feature model replacing action scoring.
- **C2:** compact model + small visual embedding only if C1 is inadequate.

### Required ablations

- no saliency;
- no person/face;
- no tracking;
- no lighting;
- no horizon;
- no manual selection;
- no confidence calibration;
- no hysteresis;
- compact model vs deterministic;
- compact model without visual embedding;
- model-as-decision vs model-as-calibrator.

Select winners on safety/selective risk, not raw accuracy.

## 5.10 Offline release thresholds

| Metric | Required |
|---|---:|
| Locked records | ≥1,050 |
| Overall pass rate | ≥0.90 |
| Expected-action hit | ≥0.90 |
| Forbidden-action violation | ≤0.02 |
| Good-frame preservation | ≥0.95 |
| Technical failure gate | 1.00 |
| Confidence-band accuracy | ≥0.90 |
| Per-class pass | ≥0.85 |
| Organic source-family floor | ≥0.80 |
| Synthetic/adversarial floor | ≥0.65 |
| Critical forbidden violations | 0 |
| Direction/horizon action precision | point ≥0.95; Wilson 95% LB ≥0.90 |
| Lighting action precision | point ≥0.92; Wilson 95% LB ≥0.87 |
| Accepted coverage overall | ≥0.65 |
| Accepted coverage ordinary class | ≥0.55 |
| Accepted coverage difficult-light | ≥0.35 |
| Abstention correctness | ≥0.90 |
| Verification accuracy | ≥0.90 |
| False “improved” | ≤0.02 |
| Wrong-direction false success | 0 |
| Material advice changes | ≤1 per 3 s |
| Time to useful result | p50 ≤2.5 s; p95 ≤6 s |

## 5.11 Compact model admission rule

A compact Core ML model may replace deterministic scoring only if:

- absolute improvement in overall pass or expected-action hit ≥5 percentage points;
- paired bootstrap by `source_shoot_id`, 10,000 resamples, lower 95% CI for improvement >0;
- forbidden-action rate worsens by no more than 0.005;
- good-frame preservation does not regress;
- no class regresses by >0.03;
- critical violations remain zero;
- better coverage is not achieved by indiscriminately accepting risky advice;
- blind human evaluation passes.

## 5.12 Human blind evaluation

For 210 cases, 3 reviewers each.

Reviewers see:

- frame,
- selected subject,
- advice,
- no candidate/model name,
- no confidence source.

Judge:

- correctness,
- executability,
- probability of harming the frame,
- usefulness to beginner,
- whether abstention was preferable,
- verification truth for before→after.

Gates:

| Human metric | Gate |
|---|---:|
| safe + executable | ≥0.90 |
| helpful | ≥0.80 |
| candidate preference among non-ties | ≥0.60 |
| majority-rated materially harmful | ≤0.01 |
| critical harm | 0 |

## 5.13 Latency / memory / thermal budgets

On oldest supported device:

| Budget | Threshold |
|---|---:|
| Vision/geometry feature pass p95 | ≤150 ms |
| deterministic planner p95 | ≤10 ms |
| optional compact model p95 | ≤80 ms |
| total analysis sample p95 | ≤250 ms |
| main-thread work/update | ≤8 ms |
| preview p50 | ≥28 FPS |
| preview p5 | ≥24 FPS |
| app RSS p95 | ≤250 MB |
| compact model incremental RSS | ≤60 MB |
| compact model package | ≤10 MB |
| 30-min run | no thermal `.critical` |
| serious thermal duration | ≤5% |
| 30-min battery drain mid-tier | ≤10% |

On thermal degradation, cadence may reduce, but stale advice must never be shown as current.

## 5.14 Physical device protocol

No iPhone 17 Pro.

Use three tiers:

1. oldest physically available supported iPhone;
2. mid-tier A15-class or similar non-Pro;
3. current available non-Pro.

Required per matrix:

- fresh install;
- allow/deny/settings permission flow;
- 20 portrait↔landscape rotations;
- 10 background/foreground cycles;
- interruption scenarios;
- 30-minute soak;
- bright-window / dark scene transitions;
- track loss/reacquisition;
- tap selection;
- VoiceOver / XXL / Reduce Motion;
- no-network mode.

All 70 live scripted sequences must cover all seven classes, with every class run on at least two device tiers.

## 5.15 Model packaging / provenance

Any future Core ML model requires:

- exact training dataset manifest/hash;
- rights disposition for all source families;
- training code revision;
- immutable command/config;
- Python/package lock;
- random seeds;
- feature schema;
- calibration method;
- source checkpoint and license;
- conversion command/version;
- input/output tensor contract;
- `.mlpackage` SHA-256;
- model card;
- quantization regression report;
- bundle allowlist entry;
- NOTICE/license location;
- validator failure on unknown model.

Do not ship only an opaque compiled model without reproducible source/conversion evidence.

## 5.16 Go/no-go for Camera Coach

Production Camera Coach corrective mode is enabled only if:

```text
human_gold_holdout_pass
AND zero_cross_split_leakage
AND zero_critical_forbidden
AND before_after_verifier_pass
AND blind_human_pass
AND device_matrix_pass
AND latency_memory_thermal_pass
AND fresh_full_suite_green
AND privacy_release_legal_pass
```

No perfect development run can replace this gate.

---

# 6. Backend decision

## **NO BACKEND FOR 1.0**

Reasons:

1. The live value must work offline.
2. The local decision loop is the current quality bottleneck.
3. Remote VLM cannot compensate for an unsafe local product contract.
4. Production provider/auth/consent/retention/quota/cost/observability are not closed.
5. No-backend simplifies App Privacy and release operations.
6. Monetization is not required to validate the first product value.

### Store build requirements

- exclude environment-selected VLM providers from production composition;
- exclude mock/offload routes;
- do not read production API credentials for Camera Coach;
- no Deep Review button;
- no quota/paywall/server-consent UI;
- static and runtime egress audit;
- no analytics/crash SDK unless separately approved and disclosed;
- local diagnostics only by explicit user export.

### Post-1.0 admission gate for Deep Review

A backend may be tested later only if it provides measurable value on a locked ambiguous/difficult subset:

- ≥10 pp absolute uplift on the target subset;
- >60% blind preference among non-ties;
- completed response rate ≥0.98;
- p95 end-to-end latency ≤15 s;
- malformed accepted response rate = 0;
- cost per completed review ≤$0.05 before Apple/tax margin;
- explicit one-time/feature consent before image transmission;
- default raw-frame retention = 0;
- remote kill switch;
- local Camera Coach remains fully functional if backend is unavailable.

Do not build provider-neutral backend abstractions before this admission gate is justified.

---

# 7. Ordered execution tracker

The tracker is dependency-ordered. Do not convert this into one giant refactor. Execute and close evidence task by task.

| ID | priority | objective | exact repo areas/files | dependencies | acceptance criteria | narrow verification | required evidence | autonomous/owner/device/legal/account | stop gate |
|---|---|---|---|---|---|---|---|---|---|
| BAS-001 | P0 | Capture current checkout receipt without mutation | read-only Git; `build/release-evidence/baseline/` | none | HEAD, branch, porcelain-v2, diff stat/name-status, untracked inventory, merge state recorded | compare receipt to old handoff | `baseline.json`, command log, hashes | autonomous | stop on active merge/rebase |
| BAS-002 | P0 | Classify current diff | every path from BAS-001 | BAS-001 | every path tagged owner-intended/generated/research/release/unknown | classified count equals inventory | `diff-classification.jsonl` | autonomous | do not edit unknown paths |
| BAS-003 | P0 | Map current target/build topology | `project.pbxproj`, workspace, schemes, `Podfile*` | BAS-001 | targets, memberships, configs, deployment, device family, frameworks, resources mapped | `xcodebuild -list`, `-showBuildSettings` only | topology report | autonomous | stop if workspace/scheme unresolved |
| CUT-001 | P0 | Define camera-only Store composition | shell composition, `SceneDelegate`, project config, new cut owner if needed | BAS-002, BAS-003 | public Release exposes Camera only | source-level composition tests | decision record | owner approval then autonomous | do not apply without cut approval |
| CUT-002 | P0 | Exclude Scene/History public routes | `CommercialShell/**`, Scene modules, release config | CUT-001 | no visible/hidden public Scene/History route | composition tests + string/symbol scan | route inventory | autonomous | preserve internal mechanics |
| CUT-003 | P0 | Exclude recording/mic/Photos/Speech/Pro Controls | recording services, camera service, speech service, overlays, usage strings | CUT-001 | Store flow never requests these permissions | call-site/static permission scan | feature-cut report | autonomous | stop on core Camera dependency |
| CUT-004 | P1 | Narrow visible product claims | camera entry copy, `Localizable.xcstrings`, metadata draft | CUT-002, CUT-003 | copy promises local setup/verification only | forbidden-claim test | RU/EN diff | owner/editor | no final metadata before ML pass |
| REL-001 | P0 | Remove third-party ML/Scene binaries from Store | project membership, DETR/NIMA, llama, GGUF, USDZ | CUT-002, BAS-003 | zero DETR/NIMA/GGUF/llama/Circle/Person in Release | built bundle + `otool` scan | sorted bundle manifest/hash | autonomous after cut | stop on unresolved symbol |
| REL-002 | P0 | Enforce zero-model camera-only allowlist | `validate_release_bundle.sh`, tests | REL-001 | unknown model/framework/Scene asset blocks | negative fixtures | fixture logs | autonomous | no hard-coded success count |
| CFG-001 | P1 | Make 1.0 iPhone-only and align iOS minimum | project + Podfile + targets | BAS-003, CUT-001 | device family=1; aligned min target | build-settings assertions | settings report | owner minimum OS | stop if APIs require higher min |
| REL-003 | P1 | Machine-readable component/legal status | release scripts + new status manifest | BAS-003 | gate derives blocker disposition from records | approved/replaced/excluded/missing fixtures | machine summary | autonomous | missing record always blocks |
| REL-004 | P1 | Fix 6-vs-11 fixture report drift | release scripts/tests | BAS-003 | actual fixture count reported | fixture self-test shows 11 | fixture list/log | autonomous | temp-owned paths only |
| COR-001 | P1 | Remove no-op camera xmark from public cut | `OverlayView.swift`, presentation tests | CUT-001 | no meaningless public close control | focused rendering/source test | AX tree | autonomous | do not alter shell teardown |
| COR-002 | P0 | Canonicalize subject-target directions | domain contracts, `DirectionArrows.swift`, planner tests | BAS-003 | action means desired subject displacement; orientation/mirroring covered | exhaustive 4-dir × orientation × mirroring tests | serialized action contract | autonomous | no visible copy until tests green |
| COR-003 | P1 | Add immutable accepted-frame envelope | `AnalysisPipeline.swift`, `LatestFrameEvidenceStore.swift`, contracts | COR-002 | decision features tied to one frame/window | stale-source deterministic tests | frame/timestamp trace | autonomous | bounded pixel-buffer lifetime |
| COR-004 | P0 | Implement subject resolver + tap selection | new `SubjectResolver.swift`, camera view/view model | COR-003 | auto person/group, tap object, ambiguity | unit fixtures | resolver decisions | autonomous | stop on gesture-owner conflict |
| COR-005 | P0 | Implement temporal subject tracking | `VisionTracking.swift` or new tracker | COR-004 | stable track ID, redetection, explicit loss | sequence tests | track transitions | autonomous; device later | no silent identity switch |
| COR-006 | P1 | Fix lighting background mask | `LightingEstimator.swift`, tests | COR-003, COR-004 | subject excluded from background; finite outputs | fixed pixel-buffer tests | numeric goldens | autonomous | lighting advice remains feature-gated |
| COR-007 | P0 | Build conservative policy v1 | critique/planner/domain contracts | COR-002, COR-005, COR-006 | only approved issue/action catalog; unavailable remains unavailable | table-driven policy tests | policy matrix | autonomous | unknown issue fails closed |
| COR-008 | P1 | Stabilize advice temporally | EMA/hysteresis/motion gate/advice state | COR-007 | one active action; no flip faster than 3 s | sequence tests | jitter report | autonomous | no stale tip after track loss |
| COR-009 | P0 | Implement coaching episode owner | new coaching coordinator | COR-003, COR-005, COR-008 | baseline, movement, invalidation correct | deterministic state-machine tests | episode traces | autonomous | coordinator cannot claim success |
| COR-010 | P0 | Implement action verifier | new verifier + outcome contract | COR-009 | action-specific improved/unchanged/worse/incomparable | synthetic pair matrix | metric deltas | autonomous | wrong-direction false success hard-fails |
| UI-001 | P0 | Bind marker to target semantics | camera overlay, arrow code, suggestion UI | COR-002, COR-007 | arrow depicts desired subject displacement and copy agrees | geometry/snapshot tests | inspected PNGs | autonomous | no new visual system |
| UI-002 | P1 | Prevent corrective overlay occlusion | `SETCameraCoachProductionView.swift`, layout tokens | UI-001, COR-004 | overlay avoids subject/target and stays bounded | portrait/landscape + XXL render | upright screenshots | autonomous/device later | frame remains hero content |
| UI-003 | P0 | Add verifier outcome states | camera presentation/view model | COR-010, UI-002 | four outcomes return cleanly to live | UI state tests | interaction trace | autonomous/device later | no fake success celebration |
| LOC-001 | P1 | Editorial RU/EN pass | `Localizable.xcstrings`, `InfoPlist.xcstrings` | CUT-004, UI-003 | consistent human camera language | missing-key/forbidden-copy tests | editorial checklist | owner/editor | preserve accessibility IDs |
| A11Y-001 | P1 | Close Camera accessibility matrix | entry/live/outcome UI | UI-003, LOC-001 | VO order, 44pt controls, XXL, RM, contrast | UI tests + device checklist | screenshots/notes | autonomous + device | inaccessible primary action blocks |
| DATA-001 | P0 | Freeze action label schema | `datasets/camera-coach/v1/label-schema.json` | COR-002, COR-010 | seven classes + action/forbidden/verification fields | JSON schema fixtures | schema hash | autonomous | no case-specific heuristics in schema |
| DATA-002 | P0 | Create data rights/provenance manifests | dataset manifests | DATA-001 | every source has origin/right/disposition/hash | coverage validator | missing-source report | autonomous + legal | missing rights excludes data |
| DATA-003 | P0 | Implement dedup/split auditor | new `tools/camera_dataset_audit.py` | DATA-001 | exact/near dedup + zero cross-split leakage | synthetic collision fixtures | dedup report | autonomous | leakage blocks freeze |
| DATA-004 | P0 | Create annotation guide + simple QA tool | dataset guide/tool | DATA-001, DATA-003 | multi-valid actions, forbidden labels, adjudication, hidden QC | annotation round-trip fixtures | tool tests | autonomous | no model output shown by default |
| DATA-05A | P0 | Collect single-person data | raw store + manifests | DATA-004 | quotas met | dataset validator | rights/shoot counts | data/human | stop if shoot diversity insufficient |
| DATA-05B | P0 | Collect two-people data | same | DATA-004 | quotas met + group negatives | validator | group report | data/human | rights required |
| DATA-05C | P0 | Collect object/food data | same | DATA-004 | quotas met + tap failures | validator | object report | data/human | no object-name labels |
| DATA-05D | P0 | Collect interior data | same | DATA-004 | quotas met + no-subject interiors | validator | interior report | data/human | do not force subject |
| DATA-05E | P0 | Collect street/landscape data | same | DATA-004 | quotas met + horizon + intentional tilt | validator | landscape report | data/human | intentional tilt explicit |
| DATA-05F | P0 | Collect difficult-light data | same | DATA-004 | quotas met + low-key/hotspot/backlight | validator | light report | data/human | disable light action on disagreement |
| DATA-05G | P0 | Collect already-good data | same | DATA-004 | quotas met + off-center strong frames | validator | preservation report | data/human | not synthetic-only |
| DATA-006 | P0 | Adjudicate + freeze splits | QA + release manifests | DATA-05A..G, DATA-002, DATA-003 | agreement gates pass, 1,050 holdout frozen | full data audit | manifest/hash | human/legal | failed QA reopens data, not thresholds |
| EVAL-001 | P0 | Produce actual Swift fullRuntime output | production replay/device harness + exporter | COR-007, DATA-001 | production pipeline output, not Python oracle/proxy | small parity fixture | candidate JSONL + binary/source hash | autonomous/device later | proxy cannot close release |
| EVAL-002 | P0 | Implement release metrics | camera eval package | DATA-001, EVAL-001 | per-class/action/forbidden/preservation/calibration/coverage | scorer tests | metrics JSON/schema | autonomous | denominator change requires version bump |
| EVAL-003 | P0 | Add verifier scorer | eval package | COR-010, DATA-006 | outcome accuracy and false-success metrics | synthetic pair matrix | pair report | autonomous | wrong-direction false success blocks |
| EVAL-004 | P0 | Establish deterministic production baseline | frozen holdout + fullRuntime | DATA-006, EVAL-002, EVAL-003 | one sealed evaluation | rerun same outputs deterministically | baseline report | autonomous | do not tune on holdout IDs |
| MOD-001 | P2 | Train feature-only compact candidate | new `ml/camera_coach_policy/**` | EVAL-004 | reproducible training, <=10 MB model | repeated train comparison | model card | autonomous | stop if deterministic passes and uplift immaterial |
| MOD-002 | P2 | Integrate candidate behind non-public flag | new provider or compact policy provider | MOD-001 | Store default deterministic until gate | provider parity/failure tests | latency/bundle report | autonomous | no DETR/NIMA/VLM ensemble |
| MOD-003 | P0 | Model go/no-go | eval + device | MOD-002, DEV-002, DEV-003 | uplift/non-regression/human gates | sealed compare | decision record | owner evidence decision | failing model excluded |
| TEST-001 | P0 | Close focused Camera suites | camera domain/services/UI tests | COR-010, UI-003 | all focused core tests green | non-Pro simulator | `.xcresult` + parsed summary | autonomous | no iPhone 17 Pro |
| TEST-002 | P0 | Fresh full production suite | all production unit/UI tests | TEST-001, CUT-003 | zero failures, explicit external/device skips only | isolated DerivedData | durable `.xcresult` | autonomous | default suite failure blocks |
| CI-001 | P1 | Add minimal CI | chosen CI workflow/scripts | TEST-002, REL-004 | build, unit, Python, unsigned release gate | same commands locally | CI receipt | account maybe | device lane remains separate |
| PRIV-001 | P0 | Runtime/static egress audit | URLSession, VLM, offload, SDKs, entitlements | CUT-003, REL-001 | no unexplained public-build egress | scan + no-network/proxy device check | data-flow map | autonomous + device | unexplained egress blocks |
| PRIV-002 | P0 | Align privacy artifacts | manifest, usage strings, policy/ASC draft | PRIV-001 | exact binary behavior reflected | validator + review | privacy packet | owner/legal/account | no “no data” claim before proof |
| LEG-001 | P0 | Close shipped component/media inventory | SnapKit, fonts, AppIcon, branding, all bundled files | REL-001, DATA-002 | every shipped item has source/hash/license/right/disposition | bundle-to-inventory coverage | SBOM/NOTICE/rights packet | legal/owner | missing item blocks |
| REL-005 | P0 | Fresh clean unsigned release gate | release scripts | TEST-002, PRIV-002, LEG-001, REL-003 | all stages pass, blocker count 0 | isolated build | logs + bundle manifest/hash | autonomous | only claim unsigned evidence |
| DEV-001 | P0 | Physical permissions/lifecycle/orientation qualification | device script | REL-005, A11Y-001 | all first-run/lifecycle scripts pass | three non-Pro tiers | videos/checklist/device info | physical | crash/black preview/stale route blocks |
| DEV-002 | P0 | Run 70 live quality sequences | production build + frozen scripts | EVAL-004, DEV-001 | seven-class live thresholds pass | guided capture/postprocess | raw rows/metrics/videos | physical/human | critical forbidden=0 |
| DEV-003 | P0 | Qualify latency/memory/thermal | benchmark harness | DEV-001, EVAL-001 | all budgets pass | 30-min per tier | signposts/thermal/memory | physical | critical thermal/OOM blocks |
| TF-001 | P0 | Internal TestFlight candidate | exact signed build | REL-005, DEV-002, DEV-003, ASC-001 | same build installs/runs, no P0/P1 | internal smoke | build ID/feedback | Apple account/device | no local rebuild substitution |
| TF-002 | P0 | External beta 15–20 users | TestFlight | TF-001 | >=200 meaningful sessions, no open P0/P1 | structured tasks + exported diagnostics | cohort report | owner/account/human | systematic UX/safety issue reopens correctness |
| ASC-001 | P0 | Signed archive + Apple validation/upload | Xcode signing/project | REL-005 + credentials | archive, codesign, Validate, upload, processed build | Organizer/ASC | archive hash/receipt/build ID | Apple account | binary frozen after qualification |
| ASC-002 | P0 | Complete App Store record | ASC metadata/screens/privacy/support/age/export/notes | TF-002, PRIV-002, LEG-001 | metadata exactly matches cut | independent metadata audit | exported checklist | owner/account/legal | no unverified ML claims |
| RC-001 | P0 | Final binary go/no-go | all evidence | ASC-001, ASC-002, TF-002, MOD decision | every §11 criterion true | two-person final audit | RC manifest | owner release decision | any missing evidence = NO-GO |

---

# 8. Dependency DAG and milestones

```text
M0 REPRODUCIBLE BASELINE
    BAS-001 → BAS-002 → BAS-003
            ├───────────────┐
            ▼               ▼
M1 PRODUCT CUT          M1 CORE CORRECTNESS
CUT / CFG / REL-001     COR-001..010
            │               │
            ├──────┬────────┘
            │      │
            ▼      ▼
      M2 DATA TOOLING / GOLD DATA
      DATA-001..006
            │
            ▼
      M3 ML QUALITY
      EVAL-001..004
            │
            ├────────► optional MOD-001..003
            │
            ▼
      M4 RELEASE / PRIVACY / LEGAL
      TEST / CI / PRIV / LEG / REL-005
            │
            ▼
      M5 PHYSICAL DEVICE QUALIFICATION
      DEV-001..003
            │
            ▼
      M6 SIGNED BUILD + INTERNAL TESTFLIGHT
      ASC-001 + TF-001
            │
            ▼
      M7 EXTERNAL TESTFLIGHT
      TF-002
            │
            ▼
      M8 APP STORE RC
      ASC-002 + RC-001
```

## Milestone exit rules

### M0 — reproducible baseline

Exit only when:

- current checkout receipt exists;
- current diff is classified;
- build/target/resource topology is mapped.

### M1 — correctness

Exit only when:

- public Camera-only cut is clear;
- canonical direction semantics exist;
- subject selection/tracking exist;
- verifier loop exists;
- no misleading xmark/public dead control.

### M2 — gold data

Exit only when:

- label schema is fixed;
- rights manifests exist;
- leakage audit reports zero cross-split leakage;
- human QA gates pass;
- locked holdout is hashed.

### M3 — ML quality

Exit only when:

- actual Swift production outputs are scored;
- deterministic baseline meets thresholds, or the feature remains disabled;
- optional compact model is evaluated against the same frozen data.

### M4 — release/legal/privacy

Exit only when:

- fresh full production suite passes;
- public release bundle contains only allowed components;
- privacy artifacts match actual behavior;
- shipped component/media inventory is complete;
- unsigned release gate passes with zero blockers.

### M5 — device qualification

Exit only when:

- permissions/lifecycle/orientation pass;
- 70 live quality sequences pass;
- latency/memory/thermal budgets pass.

### M6 — internal TestFlight

Exit only when:

- the exact qualified binary is signed, validated and processed;
- internal smoke passes without a rebuild.

### M7 — external TestFlight

Exit only when:

- 15–20 relevant testers have used it;
- at least 200 meaningful sessions exist;
- no unresolved P0/P1 quality or usability defect remains.

### M8 — App Store RC

Exit only when every binary criterion in §11 is true.

### Mandatory order

```text
No baseline → no broad source edits
No full coaching loop → no ML release claim
No frozen holdout → no final model selection
No release/legal/privacy → no signed RC
No device evidence → no TestFlight RC
No external beta → no public App Store submission
```

---

# 9. NEXT_PACKET_FOR_CODEX

**These are exactly the first 10 tasks Codex may start autonomously without the owner or a physical device.**

Do not commit/push/stash/reset/clean.

| # | ID | Files/areas | Change | Narrow verification | Stop condition |
|---:|---|---|---|---|---|
| 1 | CPX-01 | read-only entire checkout; output `/private/tmp/set-os-current-baseline/` | capture HEAD, branch, porcelain-v2, diff, untracked inventory, operation state | counts and listed paths reconcile | stop on active merge/rebase/cherry-pick; do not mutate tree |
| 2 | CPX-02 | current repo paths vs handoff source inventory | build path-by-path drift matrix: same/changed/missing/new | SHA/path report | do not auto-fix drift |
| 3 | CPX-03 | `project.pbxproj`, workspace, schemes, `Podfile*` | export targets, memberships, deployment targets, device family, frameworks, resources | `xcodebuild -list`, `-showBuildSettings`, no build | stop if workspace/scheme resolution requires signing |
| 4 | CPX-04 | Camera/Scene/recording/model call sites | construct dependency closure for Camera-only public cut: required/removable/uncertain | every Release resource/framework maps to consumer | uncertain consumers remain report-only |
| 5 | CPX-05 | `scripts/validate_release_bundle.sh`, `scripts/run_release_gates.sh`, release tests | introduce machine-readable component disposition input while preserving current blocker behavior | fixture tests for approved/replaced/excluded/missing | stop on overlap with unrelated user edits |
| 6 | CPX-06 | `scripts/tests/test_release_bundle_gate.sh`, release summary | derive contamination fixture count instead of hard-coded `6` | `bash -n`; fixture enumeration expected 11 | temp-owned paths only |
| 7 | CPX-07 | `OverlayView.swift`, camera presentation tests | add proof that root xmark has no meaningful parent-route owner and prepare injectable seam if needed, without changing shell semantics | focused compile/test | preserve route/teardown/accessibility ID |
| 8 | CPX-08 | action domain contracts, `DirectionArrows.swift`, planner tests | define `desired subject displacement` coordinate contract and add exhaustive failing tests for direction/orientation/mirroring | focused tests + serialized expectations | do not modify user-visible copy until mapping tests green |
| 9 | CPX-09 | `AnalysisPipeline.swift`, `LatestFrameEvidenceStore.swift`, pipeline tests | add diagnostic test for mixed-age pause evidence and explicit source timestamp report | deterministic test, no real camera | do not change inference policy in this task |
| 10 | CPX-10 | `docs/cameraanalysis/eval/**`, new dataset audit fixtures | mark 107/207 sets `development_regression`; add source/scene/derivation split schema + leakage validator | synthetic exact/near-duplicate pass/fail fixtures | do not relabel current AI data as human gold |

After CPX-10, Codex should stop and produce:

- current-state evidence summary;
- files changed;
- narrow verification results;
- unresolved conflicts/unknowns;
- recommended next executable packet from §7.

---

# 10. External action queue

## Owner product decisions

- Approve the Camera-only, no-recording, no-Scene, no-backend 1.0 cut.
- Approve iPhone-only.
- Approve rear-wide-only for 1.0.
- Approve final minimum iOS after current API inspection.
- Approve final public name after App Store/trademark conflict check.
- Approve RU+EN storefront scope and support capacity.
- Approve the public product promise.
- Provide/approve the physical device matrix.
- Do not require iPhone 17 Pro.

## Legal / provenance decisions

- AppIcon authorship/rights.
- SET OS branding rights.
- Approved-concept-derived visual assets.
- Bundled font licenses.
- SnapKit notices/acknowledgement handling.
- Verify DETR/NIMA/llama/GGUF/Circle/Person are absent from public 1.0 archive so they are not public release blockers.
- Dataset creator/source/consent/training/eval rights.
- Final component disposition manifest.

Never infer usage rights from filename, checksum, or technical linkage.

## Apple Developer / App Store Connect actions

- Active Apple Developer membership and roles.
- App ID / Bundle ID / App Store record.
- Distribution signing identities/profiles.
- Public Privacy Policy URL.
- Public Support URL.
- App Privacy questionnaire based on final binary/data-flow audit.
- Age rating.
- Export compliance.
- Signed upload.
- Processed build verification.
- Internal TestFlight group.
- External TestFlight group.
- Beta App Review information.
- Final App Review notes:
  - camera permission purpose,
  - local processing,
  - no recording/upload in 1.0,
  - how to trigger correction,
  - how to trigger `KEEP`,
  - how to tap-select,
  - how abstention works.
- Store screenshots from upright, real, final experience.
- Final metadata audit against actual binary.

## Physical-device tests

- fresh install;
- camera permission allow;
- deny → Settings → return;
- restricted/unavailable recovery where possible;
- portrait/landscape rotation during all states;
- tap selection near edges and overlays;
- single-person tracking;
- two-person group behavior;
- object/food selection;
- interior without person;
- landscape without clear primary subject;
- intentional Dutch-angle hard negative;
- low-key light hard negative;
- strong backlight;
- subject loss/reacquisition;
- background/foreground;
- system interruption;
- 30-minute soak;
- thermal pressure;
- Low Power Mode;
- no network;
- VoiceOver;
- XXL text;
- Reduce Motion;
- all 70 locked live sequences;
- upright final screenshots/videos.

## Data collection / human labeling

- Recruit at least:
  - 2 independent annotators,
  - 1 adjudicator.
- Pilot 70 records, 10/class.
- Measure agreement and revise guide before scale.
- Obtain rights/consent before source ingestion.
- Capture independent scene decisions, not only burst-adjacent frames.
- For problem examples, collect:
  - correct fix,
  - no-change,
  - wrong-direction or harmful change.
- Never show current model output to annotators.
- Maintain separate critical-forbidden set.
- Conduct 210-case blind compare.
- Freeze holdout before final tuning.

---

# 11. Definition of Release Candidate

## Scope

- [ ] Public build opens Camera Coach only.
- [ ] Scene/AR/Generator/Storyboard/History/recording unavailable.
- [ ] No secret public route via environment/launch argument.
- [ ] Rear-wide-only public camera path.
- [ ] No Deep Review/backend/StoreKit/account/paywall.
- [ ] Public copy exactly matches this scope.

## Core behavior

- [ ] Camera permission allow/deny/recovery passes on device.
- [ ] Automatic person/group selection works.
- [ ] Tap selection works for object/ambiguous cases.
- [ ] Subject identity never silently switches.
- [ ] At most one material advice item is active.
- [ ] Direction copy and marker agree in every orientation.
- [ ] Overlay does not hide subject/target.
- [ ] `KEEP` preserves good frames.
- [ ] `ABSTAIN` is a first-class output.
- [ ] Full `advice → movement → verification → live` loop works.
- [ ] Verifier can say “unchanged”, “worse”, “incomparable”.
- [ ] Background/interruption/rotation never leave stale advice.

## ML/eval

- [ ] 1,050 human-gold locked holdout cases.
- [ ] overall pass ≥0.90.
- [ ] expected-action hit ≥0.90.
- [ ] forbidden-action violation ≤0.02.
- [ ] good-frame preservation ≥0.95.
- [ ] every class ≥0.85.
- [ ] critical forbidden violations = 0.
- [ ] cross-split leakage = 0.
- [ ] verification accuracy ≥0.90.
- [ ] false “improved” ≤0.02.
- [ ] wrong-direction false success = 0.
- [ ] human blind gates pass.
- [ ] production evaluation uses actual Swift fullRuntime outputs.

## Performance/device

- [ ] Oldest, mid, current non-Pro tiers pass.
- [ ] No iPhone 17 Pro required or used.
- [ ] Preview p5 ≥24 FPS.
- [ ] No thermal critical during 30-min run.
- [ ] No OOM.
- [ ] p95 time to useful result ≤6 s.
- [ ] VoiceOver/XXL/Reduce Motion pass.

## Test/release

- [ ] Fresh default production suite = zero failures.
- [ ] Research/device suites cannot create a false green default run.
- [ ] CI reproduces build/unit/release gates.
- [ ] Release blocker count = 0.
- [ ] Public archive contains none of the excluded models/frameworks/assets.
- [ ] Every bundled third-party/media item has provenance/rights status.
- [ ] Privacy manifest matches binary.
- [ ] Privacy policy and App Privacy complete.
- [ ] Signed archive created.
- [ ] Codesign inspection passed.
- [ ] Apple Validate passed.
- [ ] Build processed in App Store Connect.
- [ ] Exact same build passed internal and external TestFlight.
- [ ] 15–20 relevant external testers.
- [ ] ≥200 meaningful external beta sessions.
- [ ] No open P0/P1.

## Kill criteria

Do **not** submit if any of the following is true:

- archive cannot be linked to the evidence revision/hash;
- any critical forbidden-action violation exists;
- corrective advice is not safer/more useful than abstention;
- verifier false-success rate >2%;
- good-frame preservation <95%;
- any claimed class misses the class floor;
- directional mapping remains ambiguous;
- camera preview crashes, blacks out, or shows stale advice under lifecycle/rotation;
- thermal/device budget fails;
- full production suite is not green;
- unknown model/framework/media exists in archive;
- actual data/network behavior disagrees with privacy disclosure;
- external beta finds systematic confusion or harmful action;
- screenshots/metadata show excluded features;
- final ASC binary differs from the qualified/TestFlight binary.

## Feature removal / feature-flag rules

| Failure | 1.0 action |
|---|---|
| Compact model fails | do not ship it; use deterministic |
| Difficult-light class fails | remove lighting advice/claims; abstain instead |
| Two-person class fails | require group/tap selection or abstain; remove claim |
| Object/food class fails | require tap; if geometry still fails, remove claim |
| Vertical placement fails | disable up/down actions and recompute all gates |
| Horizon fails | disable horizon advice/claim |
| Action family has <50 positive or <50 forbidden holdout cases | do not ship that action family |
| Before→after verifier fails | **do not ship Camera Coach 1.0** |
| Overall corrective quality gate fails | do not ship under Camera Coach corrective promise |
| Scene evidence absent | irrelevant if Scene is truly absent from archive |
| Backend absent | no effect; backend is not part of 1.0 |

---

# 12. Assumptions and confidence

## Known from handoff

- The handoff described a substantial existing product and not a toy prototype.
- Camera Coach has real local source implementation.
- Scene/Generator/AR/recording source exists, but is secondary to the 1.0 recommendation.
- SET OS v2.6 is the only intended visual authority.
- DETR/NIMA are present in source/release history, but provenance and quality are not closed.
- `compact_neural_evidence_net` is expected by code but its production artifact is missing.
- Remote VLM is an unfinished, environment-selected transport rather than a production backend.
- The 207-case camera evaluation is below release quality.
- Existing eval labels are not a locked human-gold release holdout.
- Current release infrastructure includes privacy/bundle validators and negative contamination fixtures.
- Historical release evidence is not equivalent to a signed App Store candidate.
- Physical-device evidence remains required.
- iPhone 17 Pro is forbidden for this project.

## Inferred, not yet proven

- The earlier 107/107 run is likely too narrow, over-tuned, contaminated, or otherwise non-generalizing. This is a risk inference, not proof of leakage.
- The visible left/right issue is likely a coordinate-semantics bug or at minimum a dangerous naming ambiguity. Exact root cause must be proven by orientation/mirroring tests.
- Removing Scene/recording/third-party models should greatly simplify legal/release scope, but actual dependency closure must be inspected in the current repo.
- Apple Vision + deterministic geometry is the lowest-risk architecture, not a guarantee of passing quality thresholds.
- iPhone-only is the strongest 1.0 choice because there is no iPad-specific release evidence and the core product is live camera coaching.

## Missing evidence

- current `git status` / diff;
- current Xcode/SDK;
- current simulator list;
- current full test run;
- current Release bundle inventory;
- current signing identities;
- current Apple Developer/App Store Connect state;
- actual physical device list;
- human-gold labels;
- locked holdout;
- before→after gold episodes;
- final AppIcon/brand/font rights;
- Privacy Policy;
- Support URL;
- external TestFlight;
- signed archive;
- Apple Validate/upload/processing evidence.

## Confidence

| Decision | Confidence |
|---|---:|
| Camera-only App Store 1.0 | 0.92 |
| Remove recording from 1.0 | 0.86 |
| NO BACKEND FOR 1.0 | 0.96 |
| iPhone-only | 0.95 |
| Apple Vision + deterministic geometry | 0.88 |
| Remove DETR/NIMA from Store 1.0 | 0.94 |
| Compact Core ML only after gold data | 0.93 |
| 1,050 locked holdout minimum | 0.76 |
| Readiness ≈32/100 | 0.82 |
| Scene Mode should be post-1.0 | 0.89 |

---

# Final execution instruction to Codex

The project does **not** need another concept phase. The product is already visually defined enough.

The objective is to make a smaller product true.

The next Codex session must begin with **CPX-01** and proceed through **CPX-10**. It must not redesign the app, add a backend, train a model, remove large subsystems blindly, or start App Store metadata work before the current checkout and dependency closure are re-established.

After those ten tasks, the next implementation work should prioritize, in order:

1. canonical direction semantics;
2. same-frame evidence ownership;
3. subject resolution + tap clarification;
4. temporal subject identity;
5. conservative action policy;
6. stable advice;
7. coaching episode ownership;
8. before→after verifier;
9. actual Swift runtime eval;
10. human-gold dataset/evaluation.

The definition of success is not “the app builds” and not “the UI looks finished”.

**Success = a real user can point the camera at one of the supported scene classes, receive either one safe actionable instruction or a truthful KEEP/ABSTAIN response, make the change, and have the app correctly verify the result on a real supported iPhone — with release, privacy, legal, TestFlight, and Apple evidence tied to the exact same binary.**

---

# PART III — SOURCE HANDOFF INDEX

The underlying handoff supplied for repository-grounded analysis contains:

- `00-README-FIRST.md`
- `01-CURRENT-STATE-REPORT.md`
- `04-CHECKSUMS.md`
- `10-camera-coach-source.txt`
- `11-scene-mode-source.txt`
- `12-tests-and-release-source.txt`
- `13-authority-and-evidence-docs.txt`
- `14-ml-eval-and-dataset-snapshot.txt`
- `approved-concept.png`
- `camera-corrective-ru-portrait.png`
- `camera-en-landscape-dynamic-type.png`
- `generator-workspace-ru-landscape.png`
- `library-selected-ru-landscape.png`
- `storyboard-result-ru-tray-expanded.png`
- `marker-draw-corrective-ru-portrait.mp4`

Those source snapshots and visual artifacts remain the factual evidence base. A test count is not a test result; a source implementation is not physical-device evidence; a fixture/mock is not a production backend/model; and an unsigned simulator build is not an App Store release candidate.

# Codex starting instruction

Read Part I completely, then use Part II only as prior analysis. Inspect the actual current checkout before producing or executing any plan. Do not start code changes until the full-scope replan, conflict ledger, dependency-ordered tracker, and first autonomous task packet required by Part I are complete.
