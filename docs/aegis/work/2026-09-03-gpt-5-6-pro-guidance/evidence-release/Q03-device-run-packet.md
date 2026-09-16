# Q03 — пакет финального физического прогона (подготовка)

Дата: 2026-09-13. Пакет: Q03 runbook `docs/aegis/plans/2026-09-13-setos-release-execution.md` §9.
Статус: **подготовка выполнена; сам прогон — Q04 и здесь не заявлен.**
Ни один hardware gate не помечен `pass`. Ни один результат устройства не выдуман.

Это единственный пакет, который владелец/оператор берёт в руки. Он не заменяет
`docs/implementation/device-tests/recording-v1.md`, `ar-workspace-v1.md` и
`test-topology.md`, а ссылается на них; v3 case checks добавлены секциями в те же
два файла, второго hardware handbook нет.

---

## 1. Weakest supported profile — выбор и обоснование

Заявленная матрица устройств — Master Plan v2 §12 «Device qualification matrix»
(файл `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md`):

| Tier | iPhone | iPad | Purpose |
|---|---|---|---|
| oldest eligible | A12-class device allowed by target, where available | A12-class iPad | worst supported neural/performance/memory |
| mid/compact | A15-class non-Pro iPhone | iPad mini 6-class | compact screens and representative performance |
| current/large | current available non-Pro iPhone | M-series iPad Air/Pro-class | current OS, regular width, large UI |

Deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `TARGETED_DEVICE_FAMILY = "1,2"`
(см. `shafinMultitool.xcodeproj/project.pbxproj`), то есть iOS/iPadOS 17.0+ и iPad как
first-class. `docs/implementation/ipad-performance-tiers-v1.md` повторяет ту же шкалу
(A12-class = oldest supported).

**Выбранный weakest supported profile для Q04:**

- **iPhone 13 Pro, model identifier `iPhone14,2`** (A15-class, 6 GB RAM,
  triple-camera + LiDAR), iOS 17.x — минимальная **реально доступная** ступень.
- **Обязательный iPad владельца**, iPadOS 17.0+, ARKit world-tracking-capable,
  желательно самый старый из доступных (A12/iPad 8th-gen-class или iPad mini 6-class).
  Точный `model_identifier`, `os_version`, `os_build` и active-window size оператор
  записывает в manifest по факту — устройство не выдумывается.

**Почему не A12-class (самая слабая объявленная ступень).** A12 допустим только
«where available». Инвентаризация физических устройств
(`docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/HANDOVER-2026-09-11-FULL-DELIVERY.md` §4.3)
фиксирует: iPhone 13 Pro `3CF55CC7-88BD-5F96-B1E8-0533C7AA70BC` — доступен;
iPhone 11 (A13) `1F92D07F-F729-51DE-9828-34ADEA45A7F2` — **недоступен**. A12-устройства
в наличии нет. Поэтому A12-ступень нельзя ни потребовать, ни объявить закрытой: она
остаётся явным пробелом `blocked_external`. Если владелец может предоставить
A12-class iPhone или A12-class iPad — ступень добавляется, но требовать покупку
пакета не вправе.

**Почему не iPhone 17 Pro.** Operating constraint Master Plan v2: «Do not use or require
iPhone 17 Pro». Кроме запрета, это самая новая/сильная ступень: она не проверяет
worst supported neural/performance/memory и маскирует риск слабого железа. Симулятор
iPhone 17e/iOS 26.5 — отдельный класс доказательств и физические гейты не заменяет.

**Что этот выбор не разрешает.** Он не объявляет A12/A13-поддержку проверенной и не
понижает требования: `READY_FOR_APPLE_WORKFLOW` не заявляется, пока затронутые
hardware gates не закрыты на Q04, а A12-tier не procured или явно не снят владельцем
документальным решением о deployment/device-support.

---

## 2. Точный идентификатор сборки (Q01 передаёт значения, Q03 их не выдумывает)

Q01 — интегрированный candidate. До его завершения реального хэша не существует,
поэтому пакет задаёт **правило вывода** и команды, а оператор заполняет значения из
Q01-handoff. Плейсхолдеры вида `<...>` подставляются один раз, вручную.

Правило:

```
build_id        = <source_head первых 12 hex>-<app_sha256 первых 12 hex>
app_sha256      = sha256 от ditto-архива ровно того .app, который установлен
source_head     = git rev-parse HEAD
porcelain_v2    = sha256 от "git status --porcelain=v2 -z"
dirty_receipt   = sha256 от "git diff --no-color --binary HEAD" + отсортированный untracked-список
configuration   = Debug (device benchmark harness компилируется только под #if DEBUG)
bundle_id       = com.vigvamcev-media.shafinMultitool
```

Команды (выполняются в корне репозитория после заморозки Q01; здесь только
инструмент, не прогон):

```bash
git rev-parse HEAD
git status --porcelain=v2 -z | shasum -a 256
{ git diff --no-color --binary HEAD; git ls-files --others --exclude-standard | LC_ALL=C sort; } | shasum -a 256
# после xcodebuild build (Q01), для ровно установленного продукта:
ditto -c -k --sequesterRsrc --keepParent "shafinMultitool.app" "shafinMultitool.app.zip"
shasum -a 256 "shafinMultitool.app.zip"
```

Для справки, **текущее дерево** (это НЕ Q01-candidate, значения пересчитываются на
заморозке): `head=0733df2cb83c8e3687c31251e11e5d0747052602`,
`porcelain_v2_sha256=30a28929f98e58837fcc072906e2f5540683595b9f1e66367e4ebfd6405a8faa`,
`dirty_receipt_sha256=e82216373a2275de75451928d861ca3b907828047bd40eb0f7c9908d06207bfb`.

Ожидания для импортёра кладутся в `expectations.json`:

```json
{
  "build_id": "<source_head[:12]>-<app_sha256[:12]>",
  "build_sha256": "<64-hex app_sha256>",
  "configuration": "Debug",
  "device_model_identifier": "iPhone14,2",
  "os_version": "<фактическая iOS на iPhone 13 Pro>",
  "source_head": "<40-hex git rev-parse HEAD>",
  "source_porcelain_v2_sha256": "<64-hex>",
  "source_dirty_receipt_sha256": "<64-hex>"
}
```

`os_version` — точная версия iOS на устройстве в момент прогона, не «17.x». iPad
фиксируется в самом manifest (`device` для iPad-прогона) и, при желании, отдельным
`expectations-ipad.json`; требования те же.

---

## 3. Предусловия прогона (owner inputs)

- iPhone 13 Pro подключён кабелем, разблокирован, доверен компьютеру; доступна
  development-подпись (`DEVELOPMENT_TEAM = 5NAKQ28539`). Если подпись/провижн
  недоступны — прогон честно `blocked_external`, не подменяется симулятором.
- Обязательный iPad: тот же candidate build, iPadOS 17.0+, ARKit-capable.
- Xcode 26.x toolchain и `xcrun devicectl` (проверено локально: devicectl 642.0.1).
- Комната с текстурными поверхностями и ровным светом; вторая тусклая комната для
  tracking-limitation шага; вторая камера/штатив для before/after и A/V sync (клэп).
- Реальная съёмка для human-части Q02 — отдельный поток (`docs/implementation/human-eval/**`,
  `evidence-release/Q02-human-eval-packet.md`), здесь не готовится.
- Никаких секретов ключей в manifest/логах/скриншотах.

---

## 4. Процедура установки

```bash
UDID=<UDID iPhone 13 Pro>          # из: xcrun devicectl list devices
APP=/путь/к/Build/Products/Debug-iphoneos/shafinMultitool.app

# сборка ровно одного candidate (Q01 фиксирует source state до этого шага)
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -configuration Debug -destination "platform=iOS,id=$UDID" \
  -allowProvisioningUpdates build

# точный идентификатор установленного артефакта
ditto -c -k --sequesterRsrc --keepParent "$APP" /private/tmp/shafinMultitool.app.zip
shasum -a 256 /private/tmp/shafinMultitool.app.zip

# установка
xcrun devicectl device install app --device "$UDID" "$APP"
```

Для iPad — тот же `.app`/тот же `build_id`, `--device <UDID iPad>`.

Режим device benchmark включается env-переменной `DEVICE_BENCHMARK_CONFIG_BASE64`
(base64 от JSON `DeviceBenchmarkConfig`, читается в
`shafinMultitool/Benchmark/DeviceBenchmarkSupport.swift`, ветка `#if DEBUG` в
`shafinMultitool/Resources/SceneDelegate.swift:158`). `autoStart=true` запускает
прогон сразу. Точная команда запуска — с inline-конфигом, равным
`DeviceBenchmarkConfig.defaultFull` (поля и raw-значения сверены с
`DeviceBenchmarkSupport.swift:92–134` и
`SceneGeneratorModule/Models/SceneExecutionRuntimeContracts.swift:310–337`):

```bash
UDID=<UDID iPhone 13 Pro>
RUN_ID="q04-$(date -u +%Y%m%dT%H%M%SZ)"

CFG=$(RUN_ID="$RUN_ID" python3 - <<'PY'
import base64, json, os
cfg = {
    "runId": os.environ["RUN_ID"],
    "tier": "full",
    "enabledModules": ["camera", "sceneGenerator"],
    "sceneGeneratorModelPolicy": "explicitOrLatest",
    "sceneGeneratorRuntimePreset": "baseline",
    "sceneGeneratorExecutionMode": "chunkedThermalAware",
    "sceneGeneratorThermalPolicy": {
        "mode": "chunkedThermalAware",
        "cooldownOnSeriousMs": 15000,
        "cooldownOnCriticalMs": 30000,
        "maxChunkAttempts": 2,
        "checkpointEnabled": True,
    },
    "cameraResourcePackId": "camera_device_benchmark_pack_v1",
    "sceneResourcePackId": "scene_generator_device_pack_v1",
    "guidedLiveEnabled": True,
    "softThresholds": {"scenePassRate": 0.60},
    "autoStart": True,
    "liveSequenceEnabled": True,
}
print(base64.b64encode(json.dumps(cfg, separators=(",", ":")).encode()).decode())
PY
)

xcrun devicectl device process launch --device "$UDID" \
  --environment-variables "{\"DEVICE_BENCHMARK_CONFIG_BASE64\":\"$CFG\"}" \
  com.vigvamcev-media.shafinMultitool
```

`runId` из этого конфига — это и есть `<runId>` из путей выгрузки §7; продублируйте
его в `run.json.run_id`.

---

## 5. Тестовые материалы

- Встроенный pack `camera_device_benchmark_pack_v1` (174 кадра + `camera_full_labels.jsonl`,
  `camera_quick_labels.jsonl`, `live_sequences.json`, `guided_live_scenarios.json`) —
  материализуется на устройстве, отдельно копировать не нужно.
- `scene_generator_device_pack_v1` (`core_accepted_source.jsonl`,
  `hard_accepted_source.jsonl`) — для Scene-сценариев.
- Реальная сцена для AR: две лампы/два предмета (CC-O01/O02/O05), блик на стекле
  (CC-L05/L06), намеренный силуэт/контровой свет (CC-I05), текстурная и тусклая
  комнаты, движущийся герой для CC-V01..V03.
- Human-eval shot list — из Q02-пакета, не дублируется здесь.

---

## 6. Порядок сценариев

Порядок обязателен: сначала install в чистое состояние, затем функциональные шаги,
затем измерения, затем выгрузка. `check_id` совпадают с реестром импортёра.

1. **Права и запись:** `rec.mic_permission` → `rec.start_stop` → `rec.orientation` →
   `rec.lens_change` → `rec.audio_interruption` → `rec.background`.
2. **Отказы и восстановление:** `rec.low_disk` → `rec.os_kill` (K0–K4) → `rec.playback`
   → `rec.photos_export` → `rec.share` → `rec.deletion`.
3. **AR workspace:** `ar.entry_readiness` → `ar.surface_search` →
   `ar.placement_determinism` → `ar.marking_lifecycle` → `ar.tracking_limitations` →
   `ar.interruption` → `ar.background` → `ar.world_map_restore` → `ar.hint_pause` →
   `ar.recording_integrity` → `ar.teardown_convergence`.
4. **v3 case checks (iPhone):** `v3.two_object_target` → `v3.protected_ref_intent` →
   `v3.glare_review` → `v3.lens_switch_fence` (AR-секция `ar-workspace-v1.md`) →
   `v3.video_temporal_coverage` → `v3.track_swap_incomparable` → `v3.output_crop` →
   `v3.technical_action_verify` (recording-секция `recording-v1.md`).
5. **Измерения:** `rec.av_sync` (клэп/вспышка, sync report) → `rec.drops_backpressure`
   (10 мин) → `hw.perf_budgets` (p50/p95, RSS) → `hw.thermal_soak` / `rec.soak`
   (30 мин) → `hw.voiceover` → `hw.dynamic_type_ru_en`.
6. **iPad:** повторить шаги 1–4 и `ar.ipad_window_modes` на iPad, обе ориентации +
   resize активного окна.

Шаги 1–3 исполняются по v1-протоколам дословно (номера v1 ↔ `check_id` в реестре
импортёра). v3-шаги — по добавленным секциям. Любой фейл: один повтор; устойчивый
фейл пишется `executed_fail` с receipt, соответствующий пакет переоткрывается.

Дополнительные `hw.*` check_id (это пункты Q04 runbook §9, не новый handbook):

| check_id | категория | что измеряется | обязательные `measured` поля |
|---|---|---|---|
| `hw.perf_budgets` | perf | end-to-end p50/p95, Vision/geometry p95≤150 ms, composition≤100 ms, planner≤10 ms, accepted analysis sample≤250 ms, Camera RSS p95≤350 MB (компонентные p95 не суммировать) | `vision_p95_ms`, `composition_p95_ms`, `planner_p95_ms`, `analysis_sample_p95_ms`, `camera_rss_p95_mb` |
| `hw.thermal_soak` | thermal | длительная live/recording сессия, energy/thermal/memory, ECO-поведение | `thermal_sample_count`, `thermal_states_seen` |
| `hw.voiceover` | accessibility | VoiceOver-обход реальных экранов, порядок/действия, отмена невыполнимого совета, shutter/запись не блокируются | — (screen recording/audit) |
| `hw.dynamic_type_ru_en` | accessibility | Dynamic Type, RU/EN на реальных экранах | — (screen recording/screenshot) |
| `hw.ipad_layout` | ipad_layout | iPad portrait/landscape + active-window resize, recovery при слишком маленьком окне | — (screen recording/screenshot) |

Сбалансированное покрытие: минимум 30 guided sequences по устройству (Gate C,
`docs/implementation/PRODUCTION_ACCEPTANCE.md`).

---

## 7. Куда сохраняются diagnostics/видео и как их забрать

- **Device benchmark** (perf/thermal/execution): на устройстве
  `Library/Caches/DeviceBenchmark/<runId>/` — `camera_summary.json`,
  `scene_summary.json`, `combined_summary.json`, `combined_summary.md`,
  `perf_samples.jsonl`, `device_info.json`, manifest и `*-artifacts.zip`
  (`DeviceBenchmarkArtifactStore`, `DeviceBenchmarkCoordinator`). Забрать:
  ```bash
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer \
    --domain-identifier com.vigvamcev-media.shafinMultitool \
    --source "Library/Caches/DeviceBenchmark/<runId>" \
    --destination "/private/tmp/q04-<runId>"
  ```
- **Screen recording / видео:** запись экрана iOS (Control Center) и клипы из
  приложения попадают в Photos; выгрузить через AirDrop/Files в
  `.../evidence/screen_recordings/`. Это `screen_recording`/`screenshot` роли и
  они **не** доказывают thermal или audio sync.
- **A/V sync:** отдельный sync report (измеренные `sync_error_start_ms`/
  `sync_error_end_ms`) — файл JSON роли `audio_sync_report`; без него шаг
  `rec.av_sync` не импортируется.
- **Thermal:** только device-origin JSON с `thermal_sample_count` и
  `thermal_states_seen` (роль `benchmark_summary`/`thermal_report`/`diagnostics_export`).
  Снимок экрана термометра/настроек — не thermal evidence.
- **App Attest (S02b/Q04):** challenge/enrollment/assertion roundtrip — receipt JSON
  роли `consent_receipt`/`metadata_dump`; wrong app/environment, повтор assertion и
  отказ записываются как отдельные evidence.
- **Sysdiagnose** (при OS-фейле): роли `sysdiagnose` (zip), достаётся по
  [Apple](https://developer.apple.com/bug-reporting/profiles-and-logs/) процедуре.

Все файлы кладутся рядом с `run.json` в подпапку `evidence/`; пути в manifest —
относительные, `sha256` обязателен и должен совпасть с реальным файлом.

---

## 8. Manifest и возврат результата

Импортёр: `tools/device/import_device_report.py` (fail-closed; exit 0 = принят,
1 = отвергнут, 2 = usage error). Он **не** выставляет ни один gate в `pass` —
только проверяет структуру, pinned tuple и вид доказательства.

```bash
# 1. скелет
python3 tools/device/import_device_report.py --template \
  --expectations expectations.json > run.json

# 2. оператор заполняет run.json и evidence/, статусы начинаются not_executed

# 3. импорт (из корня репозитория; --report-root по умолчанию — папка run.json)
python3 tools/device/import_device_report.py \
  --report run.json --expectations expectations.json --out accepted.json
```

Формат `run.json` (`schema_version: setos-device-run-report-v1`): `build`
(`build_id`, `configuration`, `bundle_id`, `version`, `build_number`, `app_sha256`),
`device` (`kind="device"`, `model_identifier`, `marketing_name`, `os_version`,
`os_build`, `udid`), `source_state` (`branch`, `head`, `porcelain_v2_sha256`,
`dirty_receipt_sha256`, `captured_utc`), `run_window` (`started_utc`, `finished_utc`),
`checks[]` (`check_id`, `category`, `case_ids`, `status`, `reason`, `evidence[]`).
Каждый evidence: `path`, `sha256`, `role`, `origin`, `captured_utc`,
опционально `measured`. Полные требования — в docstring инструмента.

**Возврат владельцу/оркестратору:** `run.json` + `expectations.json` + папка
`evidence/` + `accepted.json` (или полный текст `REJECTED` с причинами). Импортированный
отчёт — это `device` evidence; статусы внутри сохраняются как записаны, ни один не
повышается до `pass`.

---

## 9. Что добавлено в v3 case checks и какие gates остаются pending

Добавлены (не дублируя handbook, в тех же v1-файлах):

| check_id | файл | case_ids | категория |
|---|---|---|---|
| `v3.two_object_target` | `ar-workspace-v1.md` §v3 | CC-O01/O02/O05, CC-I01 | functional |
| `v3.protected_ref_intent` | `ar-workspace-v1.md` §v3 | CC-I05, CC-R01 | functional |
| `v3.glare_review` | `ar-workspace-v1.md` §v3 | CC-L05, CC-L06 | functional |
| `v3.lens_switch_fence` | `ar-workspace-v1.md` §v3 | CC-T04 | functional |
| `v3.video_temporal_coverage` | `recording-v1.md` §v3 | CC-V01/V02/V03/V06/V08 | functional |
| `v3.track_swap_incomparable` | `recording-v1.md` §v3 | CC-I06, CC-R02 | functional |
| `v3.output_crop` | `recording-v1.md` §v3 | CC-F01 | functional |
| `v3.technical_action_verify` | `recording-v1.md` §v3 | CC-T01/T02/T03/T05/T06 | functional |

Плюс реестр импортёра фиксирует категории существующих шагов: `rec.soak`/`hw.thermal_soak`
= thermal, `rec.av_sync` = audio_sync, `rec.drops_backpressure`/`hw.perf_budgets` = perf,
`ar.ipad_window_modes`/`hw.ipad_layout` = ipad_layout, `hw.voiceover`/`hw.dynamic_type_ru_en`
= accessibility.

**Hardware gates, остающиеся pending (ни один не `pass`):**

| Gate | check_id (пример) | Статус |
|---|---|---|
| Camera permissions / denied / restricted | `rec.mic_permission` | not_executed |
| Autofocus / exposure / lenses / pause-resume / route-background | `rec.lens_change`, `v3.technical_action_verify` | not_executed |
| Subject identity / two objects / before-after / output crop | `v3.two_object_target`, `v3.output_crop`, `v3.track_swap_incomparable` | not_executed |
| End-to-end p50/p95 и бюджеты (Vision ≤150 ms, composition ≤100, planner ≤10, sample ≤250, RSS ≤350 MB) | `hw.perf_budgets` | not_executed |
| Energy / thermal / memory / 30-min soak / ECO | `hw.thermal_soak`, `rec.soak` | not_executed |
| A/V sync | `rec.av_sync` | not_executed |
| Interruptions / low disk / recovery / export / Photos | `rec.audio_interruption`, `rec.low_disk`, `rec.photos_export` | not_executed |
| AR world tracking / anchors / world map / teardown | `ar.*` | not_executed |
| App Attest challenge/enrollment/assertion (S02b) | S02b device roundtrip | blocked_external до устройства+identity |
| VoiceOver / Dynamic Type / touch / RU-EN | `hw.voiceover`, `hw.dynamic_type_ru_en` | not_executed |
| iPad layout / window modes | `ar.ipad_window_modes`, `hw.ipad_layout` | not_executed |
| Shutter/record не блокируются коучем | входит в `v3.technical_action_verify`/`ar.recording_integrity` | not_executed |
| A12-class tier | нет device | blocked_external / documented gap |

---

## 10. Честная граница: что Q03 НЕ делает

- **Не выполняет физический прогон** — это Q04; ни один результат не заявлен.
- Не отмечает ни один hardware gate `pass`; импортёр этого и не умеет.
- Не считает снимок экрана доказательством thermal/audio sync/perf — это
  энфорсится сигнатурой и `measured`-полями, а не формулировкой.
- Не выдумывает build_id, OS-версию, UDID, модель iPad или участников; значения
  берутся из Q01-handoff и реального инвентаря, недостающие — `blocked_external`.
- Не трогает app-код, `ml/**`, `datasets/**`, `backend/**`, `project.pbxproj`,
  `tools/release/**`, `tools/camera_annotation/**`, human-eval поток.
- Не понижает требования ради зелёного протокола и не объявляет
  `READY_FOR_APPLE_WORKFLOW`.
