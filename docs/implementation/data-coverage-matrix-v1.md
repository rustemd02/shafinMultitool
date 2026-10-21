# DATA-004 — Coverage matrix и sampling plan корпуса Camera Coach (v1)

Дата: 2026-09-22. Статус: **active planning artifact** (не acceptance contract; целевые числа — рабочие планы, кроме прямо процитированных порогов `PRODUCTION_ACCEPTANCE.md`).
Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`. Задача: DATA-004 (Depends: DATA-001 ✓, DATA-003 ✓).

Источники counts (все — существующие артефакты, не новые прогоны):

- `docs/implementation/PRODUCTION_ACCEPTANCE.md` — Gate C1/C3/K минимумы.
- `docs/implementation/APP_STORE_RELEASE_TRACKER.md` §4 — 10 релизных групп.
- `docs/cameraanalysis/34-case-traceability-map.md` — 68 кейсов и статусы владельцев.
- `docs/implementation/human-eval/shot-list-v1.md` §4 — операционные квоты (350/700/350/210).
- `…/SETOS/Datasets/camera-coach/colab_package_v2_20260914/package-receipt.json` — 11 810 frames / 84 clips по источникам.
- `receipts/2026-09-22-data-003-local-data-inventory.md` и `receipts/2026-09-22-gov-007-storage-audit.md` — объёмы семей.
- `setos-backend/local-data/SETOS/annotation/*` — очереди и пилот разметки (подсчёт строк 2026-09-22).
- Tracker §3.2 — параметры последнего qualified silver fit (1 340 кадров / 636 fit pairs / 142 held-out pairs).

Ключевое семантическое ограничение: кадры v2-пакета и `research/` **не несут issue/intent/verdict меток** («No aesthetic, intent, issue, performed or improved labels fabricated» — package-receipt.json). Они дают только **raw-покрытие источников**. Silver-лейблы существуют на 1 340 кадрах qualified fit (research-only). **Human-gold = 0 по всем ячейкам** (DATA-010/011/013 `BLOCKED_OWNER`).

## 1. Слои корпуса: target vs current

| Слой | Target (контракт) | Target (операционный, shot-list) | Current | Gap |
|---|---|---|---|---|
| `regression` (curated replay, app-side) | не нормируется (не holdout) | — | 174 curated-записи (dump 2026-09-12, карта 34) + 68 кейсов | поддерживается тестами; не считается unseen |
| `locked_holdout` stills, human-gold | **≥ 250 уникальных** (C1) | 350 × 3 ревьюера = 1 050 blind votes | **0** | 100% — DATA-010/011 |
| `live_device` guided sequences | **≥ 30** (C3) | 210 | **0** | 100% — DEV-003, физические устройства |
| Temporal before/after episodes, human-gold | требуется для ML-011 | 700 | silver: 636 fit pairs (research-only); human: **0** | 100% — DATA-013 |
| Protected negatives (no-issue / intentional style) | входят в C1 (good/preserve) | 350 | **0** human | 100% — DATA-010 |
| External beta sessions | ≥ 200 сессий, 15–20 участников (K) | — | 0 | BETA-001/002 |

## 2. Матрица по 10 релизным группам §4

Колонки: «Silver raw» — источники v2-пакета/`research/`, чей контент реально покрывает группу (кадры **без меток**); «Silver labels» — кадры qualified fit; «Human gold» — 0 везде; «Target locked» — рабочее распределение 350 locked stills (план, не контракт); «Gap» — что нужно докупить/разметить.

| Группа §4 | Silver raw (источники, кадров) | Silver labels | Human gold | Target locked (план) | Gap / действие |
|---|---|---:|---:|---:|---|
| Композиция (edge/scale/headroom/баланс/горизонт/ракурс) | scenetrans_bedroom_shelf 900; commons_scenario_photo 1 185; met_open 56; webresearch ~12 206 файлов; aadb 9 433 | часть 1 340 | 0 | 60 | дефицит направлений (look-room, выше/ниже): размечать парными вариантами кадра |
| Главный объект (один/несколько/группа/unknown) | commons_quality_diverse 284; commons_scenario_photo 1 185; open-images-lamp-pilot (аннотации, 50 MB) | часть 1 340 | 0 | 40 | группы-как-герой (CC-I02) и unknown-target — нет ни одного источника: добор в DATA-015 |
| Свет/цвет (недосвет/пересвет/hotspot/тени/WB) | mit_adobe_fivek_tone_pairs 108 (тон-пары); lasiesta_indoor_temporal 3 075 (интерьер/свет); lighting/ (конфиги, 26 MB) | часть 1 340 | 0 | 50 | paired light-дефекты: fivek 108 пар мало; расширение через paired-corruptions (5 597 файлов) |
| Фон/окклюзия (clutter/merger/photobomb) | commons_real_video_sequence 575; webresearch; edge-controls 418 | часть 1 340 | 0 | 40 | occlusion-семейство почти пусто: приоритет DATA-015 |
| Техническое качество (blur/shake/focus/noise/грязная линза) | paired-corruptions ~5 597 (синтетические порчи); tapvid/lasiesta temporal | часть 1 340 | 0 | 40 | dirty-lens и focus-miss как реальные фото — нет; syntheтика ≠ organic (Gate C1: отдельные buckets) |
| Люди (лицо/глаза/headroom/pose/группа/consent) | Ava 16 809 (права: только pretraining-политика 17); lasiesta; webresearch | часть 1 340 | 0 | 40 | AVA не release-admissible: для gold нужны собственные съёмки с согласиями (shot-list SL-01/04/06) |
| Объекты сцены (movable lamp/chair/decor) | open-images-lamp-pilot (только пилот); scenetrans shelf-pairs 900 | 0 | 0 | 30 | movable/identity-кейсы отсутствуют как класс: ключевой пробел под fail-closed инвариант §4 |
| Формат/пересъёмка (9:16/16:9/1:1, title-safe, дубли) | cinematic 7 073 (16:9-кино-кадры); webresearch | 0 | 0 | 25 | форматы 9:16/1:1 и title-safe — 0; добор при съёмках (CAM-018/019) |
| Временное поведение (fixed/improved/wrong-direction/incomparable) | temporal clips 84 (v2) + temporal/ 3 796 файлов; 636 silver fit pairs | 636 pairs (silver) | 0 | 700 episodes (shot-list) | wrong-direction counterexamples в silver не размечены: DATA-013 |
| Хороший кадр (no-issue, low-key/silhouette/negative space) | aadb 9 433 (MOS, не verdict); cinematic; queue-v3-cinematic 547 строк | часть 1 340 | 0 | 45 (из них ≥15 intentional-style) | намеренный стиль почти не представлен: риск «насильственного» дефекта-файндинга |

Сумма target locked stills: 410 (350 по shot-list + резерв 60 на разбраковку/замену) — план, согласованный с квотой 350.

## 3. Покрытие размерностей

| Размерность | Target | Current | Gap |
|---|---|---|---|
| Good negatives | ≥ 15% locked (≥52) | silver: нет подтверждённых; raw: aadb-подобные MOS-источники не verdict | подтверждение только human (DATA-010) |
| Hard negatives (похожие, но разные вердикты) | ≥ 40 пар | 0 human; silver-пары 636 без hard-negative контроля | PLAN: выбрать из fivek/scenetrans пар при разметке |
| Defects (15 issue-heads контракта) | каждая head ≥ 12 stills и ≥ 3 severity-уровня | silver: только те, что были в 1 340 (issue_logits); распределение не аудировалось | аудит распределения silver — перед DATA-008 |
| Actions (33 catalog; 12 app-only) | каждая supported family ≥ 30 episodes | 0 human episodes; silver 636 pairs на 4 старых heads | DATA-013; новые heads без labels (§3.2 трекера) |
| Directions (пример: left/right/forward/back) | каждая direction ≥ 10 examples на family | 0 human; silver delta-направления не разделены | DATA-013 разметка deltas |
| Magnitudes (small/medium/large) | каждая ≥ 10 на family | 0 human | DATA-013 |
| Devices | физический iPhone: ≥ 2 уровня матрицы Gate F | 0 физических; corpus — desktop/web/cinematic источники | снимать по shot-list SL-01…10; синтетика не заменяет (C1 buckets) |
| Languages | RU/EN copy во всех tips; аннотации language-neutral (schema enum) + RU/EN opinions | opinions.jsonl 85 строк; UI RU/EN есть; tips-копия — CAM-013 (не начата) | CAM-013 после CAM-012 |
| Intents (naturalistic/low-key/silhouette/negative space/documentary/food…) | каждый intent ≥ 15 stills | очередь cinematic 547 строк (silver proposal); human 0 | приоритет: intentional-style под §4 «Хороший кадр» |

## 4. Приоритеты добора (вход в DATA-008…015)

1. **Pilot 100 (DATA-008)** — из существующих v2-пакетов + очередей: strata по 10 группам §4, по 8–12 stills на группу, включая ≥15 намеренно-стилевых. Не требует новой съёмки.
2. **Добор-съёмка владельцем (DATA-010/013, по shot-list SL-01…10)** — закрывает Люди/movable/Формат/Временное поведение с consent и iPhone-устройствами.
3. **DATA-015 докупка** — только после пилота: occlusion-семейство, группы-как-герой, dirty-lens/focus-miss органика, 9:16/1:1 форматы.
4. **Не докупать**: AVA-подобные MOS-корпуса для объёма (запрет DATA-015); silver-расширение без human-подтверждения.

## 5. Ограничения этой матрицы

- Counts зафиксированы 2026-09-22 от перечисленных receipts; манифесты пакетов не несут семантических меток, поэтому отнесение источников к группам §4 — по смыслу семейства (источник указан вreceipt), не по per-frame разметке.
- «Silver labels — часть 1 340» означает: qualified fit intake не публиковал per-group распределение; перед DATA-008 нужен отдельный аудит распределения silver по issue-heads.
- Целевые числа внутри ячеек (60/40/50…) — рабочий план распределения квоты 350, подлежат пересмотру после пилота; пороги `PRODUCTION_ACCEPTANCE.md` (≥250, ≥30, bucket ≥0.80/0.65 и т.д.) остаются единственными обязательными.
