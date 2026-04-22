# 20. On-Device Inference Wrapper (PR-H07)

Статус: design spec + design verify (ready for implement)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [18-hybrid-model-architecture-spec.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/18-hybrid-model-architecture-spec.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)
- [RealtimeScheduler.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/RealtimeScheduler.swift)
- [ThermalGovernor.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/ThermalGovernor.swift)
- [CameraViewModel.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift)

## Цель

Зафиксировать runtime design для `PR-H07` так, чтобы следующий implementation-агент мог безопасно подключить on-device neural evidence path без fusion logic и без изменения финальной critique/planner логики.

`PR-H07` должен закрыть три практические задачи:
- дать mockable wrapper поверх on-device inference provider;
- формализовать cadence policy для `live` и `pause`;
- сделать degradation/fallback behavior предсказуемым и безопасным для offline-first UX.

Этот документ закрывает design-часть `PR-H07` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Scope

`PR-H07` отвечает за:
- service-level API для локального neural evidence inference;
- mode-aware execution policy;
- wrapper normalization от raw provider output к `NeuralEvidenceSnapshot` и `NeuralEvidenceRuntimeMetadata`;
- distinction между `disabled`, `policy skipped` и `runtime failure`;
- mock path и contract-safe test surface;
- integration note для current pipeline.

`PR-H07` не отвечает за:
- fusion formulas;
- изменение `FrameCritiqueEngine` или `RecommendationPlanner`;
- user-facing UI wiring для hybrid verdict;
- server path/offloading;
- изменение frozen evidence taxonomy;
- обязательность neural layer для baseline UX.

Граница ответственности:
- [18-hybrid-model-architecture-spec.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/18-hybrid-model-architecture-spec.md) фиксирует форму model inputs/outputs;
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md) фиксирует canonical runtime/domain envelope;
- `PR-H07` фиксирует, когда, как часто и при каких условиях локальный provider вообще вызывается на устройстве.

## Design Summary

Ключевая формула `PR-H07`:

`execution gate -> preprocess -> mockable provider -> contract normalization -> safe handoff`

Из нее следуют обязательные правила:
- wrapper должен быть optional и feature-gated;
- deterministic pipeline остается fully useful при полном отсутствии neural path;
- `live` работает по best-effort cadence и может soft-skip execution;
- `pause` обязан пытаться выполнить fresh local inference для текущего кадра, а не silently reuse-ить старый результат;
- distinction между `policy_skipped` и `unavailable` должна быть явной и сериализуемой;
- wrapper не может полагаться только на внешний scheduler или thermal governor для safety;
- если execution был реально начат, downstream должен получить contract-safe `NeuralEvidenceSnapshot` или hard-failure snapshot;
- если feature целиком отключен, downstream получает `disabled` outcome, а не synthetic failure.

## Runtime Roles

### 1. `NeuralEvidenceInferenceService`

Главный orchestration layer, который:
- принимает mode-aware request;
- проверяет feature flags и cadence;
- запускает preprocessing;
- вызывает provider;
- нормализует output в `NeuralEvidenceSnapshot`;
- собирает `NeuralEvidenceRuntimeMetadata`;
- возвращает service-level outcome.

Этот слой не знает fusion formulas и не принимает product решений по `issue/action/verdict`.

### 2. `NeuralEvidenceProvider`

Mockable provider abstraction для low-level inference.

Канонический protocol-level смысл:

```text
NeuralEvidenceProvider
- prepareIfNeeded() async throws
- infer(request: ProviderRequest) async throws -> ProviderOutput
- descriptor: ProviderDescriptor
```

Разрешенные baseline-реализации:
- `CoreMLNeuralEvidenceProvider`
- `MockNeuralEvidenceProvider`

`PR-H07` не требует remote provider и не должен кодировать server semantics.

### 3. `NeuralEvidenceCadencePolicy`

Отдельный policy object, который решает:
- можно ли запускать live inference сейчас;
- какой timeout допустим;
- какой ROI strategy использовать;
- можно ли выполнять richer path или нужно деградировать.

Важно:
- cadence policy не строит snapshot;
- cadence policy only decides `execute vs skip` и execution profile.

### 4. `NeuralEvidenceSnapshotBuilder`

Слой нормализации, который:
- переводит raw provider tensors/values в frozen `EvidenceHeadId` order;
- соблюдает `available / not_applicable / unavailable` semantics;
- строит `NeuralEvidenceRuntimeMetadata`;
- оформляет hard-failure snapshot при runtime error;
- никогда не invent-ит verdict/action semantics.

## Service-Level Contract

`PR-H07` не меняет frozen domain envelope из `PR-H06`, но добавляет service-level handoff для pipeline:

```text
NeuralEvidenceInferenceRequest
- frameId: String
- mode: AnalysisMode
- capturedAt: Date
- pixelBuffer: CVPixelBuffer
- orientation: CGImagePropertyOrientation
- sceneSemantics: SceneSemanticsReport?          // required for final face_saliency applicability
- primarySubjectRegion: NormalizedRect?          // optional ROI proposal from deterministic upstream
- motionState: CameraAnalysisMotionState
- shakeLevel: Double
- isStable: Bool
- thermalTier: ThermalBudgetTier
- heavyModelsEnabled: Bool
- batteryLevel: Float?
- forcePauseExecution: Bool                      // true only for explicit pause analysis

NeuralEvidenceInferenceOutcome
- disabled
- executed(snapshot, metadata)
- policySkipped(snapshot, metadata)
- failed(snapshot, metadata)
```

Нормативные правила:
- `disabled` означает feature/config-level opt-out и не считается failure;
- `executed` означает, что provider реально был вызван и вернул contract-safe snapshot;
- `policySkipped` разрешен только для `live`;
- `failed` означает, что execution должен был случиться, но runtime не смог отдать usable output;
- при `policySkipped` и `failed` snapshot и metadata все равно обязаны быть contract-safe и сериализуемыми;
- `policySkipped` и `failed` не могут отдавать `nil` snapshot;
- `pause` не может завершаться `policySkipped`, потому что explicit pause analysis должен либо выполниться, либо дать hard failure;
- wrapper не может возвращать snapshot со старым `frameId` для нового request.

## Provider Descriptor

Provider descriptor нужен, чтобы runtime metadata были стабильными и пригодными для regression triage:

```text
ProviderDescriptor
- providerKind: NeuralEvidenceProviderKind      // coreml_local | mock
- inferenceTarget: InferenceTargetKind          // on_device
- modelFamily: String
- modelVersion: String
- preprocessingVersion: String
- thresholdProfileLive: String
- thresholdProfilePause: String
- bundleVersion: String
```

`bundleVersion` и version-поля обязаны быть стабильными между одинаковыми сборками и не могут зависеть от случайных runtime string values.

## Input and Preprocessing Policy

### Full frame

- full frame обязателен всегда;
- shape и normalization обязаны совпадать с [18-hybrid-model-architecture-spec.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/18-hybrid-model-architecture-spec.md);
- preprocessing mismatch трактуется как `preprocessing_failed`, а не как silent score drift.

### Subject crop

- `pause` должен использовать `full_frame_plus_subject_crop`, если deterministic upstream дал валидный `primarySubjectRegion`;
- если ROI нет, `pause` fallback-ит на `full_frame_only`, но shape output не меняется;
- `live` baseline path использует `full_frame_only`;
- future richer `live` crop path разрешен только отдельным PR после performance validation.

### Applicability anchor

`face_saliency` final status обязан определяться только через `sceneSemantics.primarySubject.kind`, как уже заморожено в `PR-H06`.

Следствия для wrapper-а:
- если mode разрешает `face_saliency`, но `sceneSemantics` отсутствует, это `unavailable`, а не `not_applicable`;
- raw detector outputs и ROI presence не могут самостоятельно легализовать `face_saliency`.

## Cadence Policy

### `live`

Цель `live` path:
- не становиться обязательной частью UX;
- не перегревать устройство;
- не производить мерцающий taste-like signal;
- быть безопасным preparatory runtime path для следующих `PR-H08/H11`.

Каноническая baseline policy:

| Условие | Решение |
| --- | --- |
| feature `live` disabled | `disabled` |
| `thermalTier == .critical` | `policySkipped` |
| `heavyModelsEnabled == false` | `policySkipped` |
| `batteryLevel >= 0 && batteryLevel < 0.20` | `policySkipped` |
| `isStable == false` | `policySkipped` |
| `motionState` указывает на движение камеры (`moving` или `panning`) | `policySkipped` |
| `shakeLevel > 0.35` | `policySkipped` |
| time since last live execution < `liveMinInterval` | `policySkipped` |
| иначе | execute |

Baseline `liveMinInterval`:
- `1.25s` при `thermalTier == .unrestricted`;
- `2.50s` при `thermalTier == .constrained`.

Baseline `liveTimeout`:
- `180ms` end-to-end от start preprocess до normalized output.

Baseline `live` ROI strategy:
- `full_frame_only`.

Baseline `live` head policy:
- allowed heads: `subject_prominence`, `background_clutter`, `lighting_quality`, `face_saliency`;
- pause-only heads обязаны сериализоваться как `not_applicable`, even when provider execution happened successfully;
- если live execution soft-skipped, allowed heads становятся `unavailable`, а pause-only heads остаются `not_applicable`.

Почему policy такая консервативная:
- текущий app scheduler уже dispatch-ит low-priority consumers достаточно свободно;
- текущий thermal layer в коде может быть ослаблен от production discipline;
- значит wrapper сам обязан быть final safety gate, а не "надеяться, что выше уже притормозили".

### `pause`

Цель `pause` path:
- выполнить один explicit fresh pass для текущего paused кадра;
- разрешить richer heads;
- остаться optional, но полезным;
- при любом failure не ломать deterministic pause critique.

Каноническая baseline policy:

| Условие | Решение |
| --- | --- |
| feature `pause` disabled | `disabled` |
| provider/model не готов, но может быть поднят в рамках timeout | `execute after prepareIfNeeded()` |
| `thermalTier == .critical`, но pause feature enabled | `execute` в degraded profile |
| `heavyModelsEnabled == false`, но pause feature enabled | `execute` в degraded profile |
| explicit pause request пришел | execute fresh |

Baseline `pauseTimeout`:
- `600ms` end-to-end.

Baseline `pause` ROI strategy:
- `full_frame_plus_subject_crop`, если ROI доступен;
- иначе `full_frame_only`.

Degraded `pause` profile:
- сначала wrapper обязан упростить execution profile, а не сразу отказываться от попытки локального анализа;
- первый шаг деградации: принудительно использовать `full_frame_only`;
- второй шаг деградации: сохранить тот же contract, но ограничить execution только одним fresh attempt без retry loop;
- если и после этого budget/timeout не выдерживается, runtime возвращает hard-failure snapshot и deterministic fallback.

Нормативные правила:
- `pause` не reuse-ит live snapshot другого `frameId`;
- `pause` всегда строит snapshot именно для paused frame;
- при timeout/error `pause` возвращает hard-failure snapshot и deterministic critique продолжается без neural evidence;
- `pause` richer heads разрешены целиком по frozen taxonomy.

## Fallback and Degradation

`PR-H07` фиксирует 4 уровня деградации.

### 1. Feature disabled

Причины:
- feature flag off;
- provider не сконфигурирован;
- build/profile не включает hybrid assets.

Поведение:
- outcome = `disabled`;
- никакой synthetic failure snapshot не создается;
- deterministic pipeline работает как раньше.

### 2. Live policy skip

Причины:
- cadence limit;
- instability/motion;
- critical thermal;
- low battery;
- heavy model budget отключен.

Поведение:
- outcome = `policySkipped`;
- metadata `failureReason = policy_skipped`;
- live-allowed heads получают `unavailable`;
- pause-only heads получают `not_applicable`;
- snapshot остается dense и contract-safe.

### 3. Runtime failure

Причины:
- `model_not_loaded`
- `preprocessing_failed`
- `inference_failed`
- `postprocessing_failed`
- `runtime_timeout`
- `unknown`

Поведение:
- outcome = `failed`;
- metadata `failureReason` должен точно отражать surface failure;
- snapshot оформляется как hard-failure snapshot из `PR-H06`;
- downstream обязан иметь возможность явно выбрать deterministic fallback без crash или hidden partial state.

### 4. Partial success

Причины:
- часть head-ов собрана валидно;
- часть head-ов недоступна из-за missing applicability input или postprocess problem.

Поведение:
- outcome = `executed`, если provider execution завершился и snapshot валиден;
- snapshot может содержать mix `available / unavailable / not_applicable`;
- per-head `unavailable` не подменяется snapshot-level `failed`, если хотя бы часть outputs корректна;
- metadata `failureReason` может быть заполнен только если был snapshot-level degraded path; ordinary partial applicability не является failure.

## Metadata Rules

`PR-H07` обязан материализовать `NeuralEvidenceRuntimeMetadata` при `executed`, `policySkipped` и `failed`.

Нормативные правила:
- `providerKind = coreml_local` для реального runtime provider-а;
- `providerKind = mock` для тестового/mock path;
- `inferenceTarget = on_device` всегда;
- `roiStrategy` должен отражать реальную execution strategy, а не потенциально доступную;
- `latencyMs` измеряется только для реально начатого execution;
- при `policySkipped` `latencyMs == null`;
- `thresholdProfile` должен быть mode-aware:
  - `default_live_v1`
  - `default_pause_v1`
- `producedAt >= capturedAt`.

## Integration Note

### Integration boundary for current app

`PR-H07` интегрируется в pipeline как optional service и не меняет `CameraViewModel` contract.

Рекомендуемый baseline write scope:
- новый runtime service в `Multitool2Module/Services/Pipeline/` или соседнем `Hybrid/`;
- минимальный hook inside [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift);
- tests;
- без изменения `SuggestionEngine` и без UI wiring.

### Recommended pipeline handoff

1. Deterministic feature aggregation и semantics остаются upstream.
2. После появления `SceneSemanticsReport` pipeline может собрать `NeuralEvidenceInferenceRequest`.
3. Wrapper возвращает один из service outcomes.
4. До `PR-H08` результат можно логировать, хранить рядом с debug state или пробрасывать только во внутренний pipeline state без влияния на final critique.
5. Если outcome не `executed`, текущий deterministic critique flow продолжается без изменений.

### Why `AnalysisPipeline` still owns the request

Только pipeline уже знает одновременно:
- `frameId`;
- `mode`;
- актуальный paused/live context;
- motion/stability state;
- deterministic semantics для `face_saliency` applicability;
- thermal budget/runtime mode.

Поэтому wrapper не должен сам ходить за этими зависимостями глобально.

### Scheduler interaction

Текущий [RealtimeScheduler.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/RealtimeScheduler.swift) не является source-of-truth для cadence `PR-H07`.

Нормативное правило:
- даже если scheduler зовет consumer слишком часто, wrapper обязан сам soft-skip-ить лишние `live` request-ы.

### Thermal interaction

Текущий [ThermalGovernor.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/ThermalGovernor.swift) может использоваться как источник budget hints, но не заменяет cadence policy.

Нормативное правило:
- wrapper обязан самостоятельно уважать `thermalTier`, `heavyModelsEnabled`, stability и motion guards.

## Recommended File Layout

Нормативный baseline layout для implementation PR:

```text
shafinMultitool/Multitool2Module/Services/Pipeline/NeuralEvidenceInferenceService.swift
shafinMultitool/Multitool2Module/Services/Pipeline/CoreMLNeuralEvidenceProvider.swift
shafinMultitool/Multitool2Module/Services/Pipeline/MockNeuralEvidenceProvider.swift
shafinMultitoolTests/NeuralEvidenceInferenceServiceTests.swift
```

Допустимы другие имена, если сохраняются:
- узкий write scope;
- mockable provider boundary;
- отдельные tests для cadence и fallback.

## Design Verify (2026-04-22)

Источник независимой проверки: текущий `design verify` прогон по Prompt 15 с cross-check против `02/14/18/19` и текущего `AnalysisPipeline`.

Закрытые замечания:
- устранено противоречие с mobile-first degradation policy: `pause` больше не требует безусловного richer pass при `critical` thermal или disabled heavy budget;
- явно зафиксировано, что `pause` сначала деградирует execution profile (`full_frame_only`, single attempt), а уже потом может уйти в hard failure;
- подтверждена совместимость `policySkipped` semantics с invariants из [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md).

Открытые замечания (не блокируют `PR-H07`):
- источник feature flags/config surface не стандартизован на уровне пакета.
  Каноническая трактовка для implement: конфиг должен быть injected dependency сервиса, а не скрытой глобальной настройкой.
- concurrency/ownership surface оставлена implementation-уровню.
  Ограничение для implement: wrapper не должен блокировать main thread и не должен публиковать snapshot для устаревшего `frameId`.

Verdict readiness:
- **Ready for implement** -> документ достаточно точен для `PR-H07`, если реализация сохранит injected config boundary и frame-freshness guarantees.

## Test Matrix

`PR-H07` должен иметь минимум следующие тесты.

1. Provider injection test
   Проверяет, что service работает с mock provider без Core ML dependency.

2. Live cadence skip test
   Проверяет, что второй `live` request внутри `liveMinInterval` дает `policySkipped`, а не второй real inference call.

3. Live stability gate test
   Проверяет, что `isStable == false` или высокий `shakeLevel` дают `policySkipped`.

4. Pause force execution test
   Проверяет, что `pause` request запускает fresh execution даже после недавнего live skip.

5. Disabled feature test
   Проверяет, что при disabled config service возвращает `disabled` без synthetic failure snapshot.

6. Hard failure snapshot test
   Проверяет, что provider error превращается в dense hard-failure snapshot с корректным `failureReason`.

7. Face saliency applicability test
   Проверяет, что `face_saliency` становится `not_applicable` только при `primarySubject.kind in {object, unknown}` и `unavailable` при missing semantics.

8. Live mode head policy test
   Проверяет, что pause-only heads в `live` всегда `not_applicable`, даже если provider execution прошел.

9. Metadata integrity test
   Проверяет согласованность `frameId`, `mode`, `schemaVersion`, `thresholdProfile`, `roiStrategy`, `producedAt`.

10. Pause timeout test
    Проверяет, что timeout в `pause` дает `failed` outcome и hard-failure snapshot, а не silent nil result.

11. Partial snapshot test
    Проверяет, что частично доступный snapshot остается `executed`, если envelope валиден.

## Definition of Done

`design` для `PR-H07` считается завершенным, если:
- implementation-агент может собрать wrapper без споров о `execute/skip/fail/disable` semantics;
- `live` и `pause` cadence policy зафиксированы явно;
- fallback behavior не оставляет ambiguous `nil` states;
- distinction между config disable, policy skip и runtime failure формализована;
- integration boundary с текущим `AnalysisPipeline` понятна без изменения UI;
- test matrix покрывает cadence, fallback, applicability и metadata integrity.

## Practical Outcome for Next PR

После этой spec следующий implementation-агент должен быть в состоянии:
- подключить Core ML wrapper как optional dependency;
- безопасно вызывать его из pipeline;
- не ломать `live` и `pause` UX при отсутствии модели или при runtime failures;
- подготовить `PR-H08`, где pause-only neural evidence уже реально попадет в downstream pipeline.
