# 17. AVA Usage Policy and Pretraining Design (PR-H04)

Статус: design spec (source-of-truth)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [01-roadmap.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/01-roadmap.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md)

## Цель

Зафиксировать безопасную и научно честную роль `AVA` в hybrid stage так, чтобы:
- `PR-H05` мог проектировать модель и objectives без архитектурной ошибки;
- `PR-H06` мог вводить runtime contract без протечки `AVA`-специфичных сущностей в production API;
- `PR-H14` мог честно оценивать hybrid uplift на cinematic critique, а не на proxy aesthetic benchmark;
- thesis/demo narrative не подменял explainable camera coaching общим photo-aesthetic score.

Этот документ закрывает design-часть `PR-H04` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Terminology Note

В этом документе `AVA` означает public image-aesthetics dataset family уровня `Aesthetic Visual Analysis`.

Нормативное уточнение:
- здесь `AVA` не означает action-recognition/video dataset;
- если в downstream note используется сокращение `AVA`, она должна трактоваться именно как aesthetic pretraining source;
- при необходимости в code/docs допустимо писать `AVA-aesthetics`, чтобы убрать двусмысленность.

Важное разделение:
- `raw AVA labels` означает native aesthetic targets исходного public dataset-а;
- `rubric-relabeled public asset` означает public asset, который уже получил labels по [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md);
- после rubric relabeling asset больше не считается `raw AVA supervision` и должен трактоваться по своему `labelTier`, а не по native aesthetic target.

## Scope

`PR-H04` отвечает за:
- allowed и forbidden uses для `AVA`;
- canonical contract для raw public aesthetic pretraining corpora;
- stage-wise pretraining strategy;
- domain adaptation strategy после public pretraining;
- safeguards against misuse;
- risk register и reporting policy.

`PR-H04` не отвечает за:
- выбор backbone и final loss formulas;
- runtime/domain contract для neural outputs;
- fusion formulas;
- offloading policy;
- замену rubric-driven dataset strategy на public benchmark strategy.

## Design Summary

Ключевая позиция `PR-H04`:
- `AVA` разрешен только как weak prior и representation pretraining layer;
- `AVA` не является source-of-truth для cinematic quality, verdict, issues, strengths, actions или shot intent;
- финальная hybrid система обязана учиться на rubric-driven cinematic data из [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md), а не на одном aesthetic score;
- любой runtime output обязан выражаться только через evidence heads из [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md);
- если `AVA` помогает, это допустимо трактовать только как улучшение инициализации, устойчивости или calibration under domain adaptation, но не как доказательство, что модель "научилась cinematic critique" на `AVA`.

Короткая формула policy:

`AVA is allowed for initialization, not for final semantics.`

## Canonical Raw Public Pretraining Contract

Чтобы `PR-H05` не invent-ил отдельный data shape, raw public aesthetic corpora получают собственный минимальный contract.

```text
PublicAestheticPretrainingManifest
- manifestId: String
- schemaVersion: String                 // example: "h04.v1"
- trainingSourceKind: TrainingSourceKind // required, always `public_aesthetic_manifest`
- sourceFamily: PublicAestheticSourceFamily
- createdAt: Date                       // UTC
- recordCount: Int
- splitPolicy: PublicPretrainingSplitPolicy
- records: [PublicAestheticPretrainingRecord]
- notes: String?

TrainingSourceKind
- hybrid_dataset_public
- hybrid_dataset_curated
- hybrid_dataset_runtime_hard_case
- public_aesthetic_manifest

PublicAestheticSourceFamily
- ava_aesthetics
- other_public_aesthetic

PublicPretrainingSplitPolicy
- trainRatio: Double
- validationRatio: Double
- testRatio: Double
- groupingStrategy: PublicPretrainingGroupingStrategy

PublicPretrainingGroupingStrategy
- source_asset_group
- source_record_group
- external_collection_group

PublicAestheticPretrainingRecord
- recordId: String
- sourceDatasetId: String
- split: DatasetSplit                   // train | validation | test
- assetRef: String
- assetSha256: String
- sourceRecordKey: String               // required stable upstream identifier
- crossDatasetLinkKey: String           // required for cross-manifest dedup against PR-H03 assets
- splitGroupKey: String                 // required group-aware split key under current groupingStrategy
- nativeTargetKind: NativeAestheticTargetKind
- nativeTargetPayload: String           // opaque source-native payload or pointer
- licenseClass: String
- exportStatus: PublicPretrainingExportStatus
- notes: String?

NativeAestheticTargetKind
- mean_score
- score_distribution
- ordinal_band
- ranking_pair_member
- contrastive_only

PublicPretrainingExportStatus
- allowed_for_pretraining
- allowed_for_eval_proxy_only
- blocked
```

Нормативные правила:
- `PublicAestheticPretrainingRecord` не является `HybridDatasetRecord` из [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md);
- у него нет `labelTier`, `EvidenceTargetLabel`, `CritiqueCompatibilityLabel` или `AdjudicatedLabelBundle`;
- он допустим только для public pretraining / proxy diagnostics и не может напрямую использоваться как runtime/eval source-of-truth;
- `trainingSourceKind = public_aesthetic_manifest` обязателен для всего manifest-а и является единственным допустимым source identity для raw public aesthetic corpora;
- `assetSha256`, `sourceRecordKey`, `crossDatasetLinkKey` и `splitGroupKey` обязательны, чтобы `PR-H05/H14` могли enforce-ить cross-manifest dedup, leakage checks и честный proxy eval;
- любой public asset, который позже попадает в rubric/eval dataset, обязан сохранять тот же `crossDatasetLinkKey` в поле `AssetDescriptor.crossDatasetLinkKey` из `PR-H03` для сопоставления с raw public manifest;
- если тот же public asset позже получает rubric labels, это уже новый downstream dataset entry в схеме `PR-H03`, а не переиспользование raw aesthetic contract как будто это head supervision.

## Почему `AVA` полезен

`AVA` может дать практическую пользу в трех зонах:

### 1. Broad visual prior

- помогает encoder-у увидеть много разных композиций, lighting patterns и глобальных visual layouts;
- может ускорить convergence, если curated cinematic rubric dataset пока небольшой;
- полезен как weak regularizer против слишком раннего переобучения на узкий curated set.

### 2. Coarse aesthetic sensitivity

- может дать начальную чувствительность к общим photo-level cues:
  - visual balance;
  - tonal pleasantness;
  - gross clutter vs cleanliness;
  - broad composition appeal.
- это допустимо только как pretraining prior, а не как финальный смысл head-ов.

### 3. Public-data bootstrap

- позволяет начать training pipeline до того, как накоплен большой собственный curated corpus;
- полезен как источник diversity для public bucket из [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md).

## Почему `AVA` опасен

`AVA` вреден, если трактовать его шире, чем public weak prior.

### 1. Domain gap

- `AVA` в основном отражает photo aesthetics, а не mobile cinematic coaching;
- в нем нет live/pause execution constraints;
- в нем нет shot-intent-aware critique и issue/action semantics.

### 2. Non-actionable supervision

- высокий aesthetic score сам по себе не говорит, что нужно сказать пользователю;
- по `AVA` нельзя честно вывести `IssueTypeV1`, `StrengthTypeV1` или `ActionTypeV1`;
- `AVA` плохо соответствует explainable цепочке `observation -> interpretation -> recommendation`.

### 3. Taste and contest bias

- public aesthetic labels могут переоценивать stylized, moody или heavily processed кадры;
- это может конфликтовать с задачей real-time coaching, где важны readability, clarity и actionable framing fixes;
- особенно опасно для `cinematic_expressiveness`, потому что этот head легче всего незаметно превратить в proxy aesthetic score.

### 4. Scientific overclaim risk

- improvement после `AVA` pretraining легко неправильно описать как "модель понимает cinematic quality";
- без строгой ablation discipline можно спутать representation benefit с task-semantic understanding.

## Allowed Uses

Ниже перечислены допустимые роли `AVA`.

### Allowed A. Encoder warm-start

Разрешено:
- использовать `AVA` для initialization image encoder-а или shared visual trunk;
- обучать disposable auxiliary head на broad aesthetic target;
- переносить только веса encoder/shared trunk в downstream hybrid training.

Ограничение:
- `AVA`-specific prediction head не должен становиться runtime output contract.

### Allowed B. Auxiliary pretraining-only objective

Разрешено:
- на pretraining stage использовать `AVA`-target как auxiliary objective;
- после этого удалять или reinitialize-ить `AVA`-head перед rubric-driven fine-tuning.

Ограничение:
- результат этого objective не должен напрямую сериализоваться в `NeuralEvidenceSnapshot`.
- после завершения `Stage 1` raw `AVA` objective должен быть полностью выключен и не может оставаться активным как low-weight multitask branch в `Stage 2+`.

### Allowed C. Public-data regularization

Разрешено:
- использовать `AVA` records как часть public pretraining family через `PublicAestheticPretrainingManifest`;
- добавлять rubric-relabeled public assets в source-aware training schedule с меньшим приоритетом, чем `curated` и `runtime_hard_case`.

Ограничение:
- public pretraining family и rubric-relabeled public assets не имеют права доминировать над task-specific supervision.

### Allowed D. Offline ablation baseline

Разрешено:
- сравнивать `same_base_without_ava_stage` vs `AVA-initialized` модели;
- анализировать влияние `AVA` на convergence, calibration и generalization.

Ограничение:
- итоговые product/release claims делаются только по cinematic eval, а не по `AVA` benchmark.

## Forbidden Uses

Ниже перечислены запреты `PR-H04`.

### Forbidden A. `AVA` as final truth

Запрещено использовать `AVA` как:
- финальную истину о cinematic quality;
- источник truth labels для `verdict`;
- источник truth labels для `IssueTypeV1`, `StrengthTypeV1`, `ActionTypeV1`;
- proxy ground truth для shot intent или scene type.

### Forbidden B. `AVA` score in runtime semantics

Запрещено:
- включать raw `AVA` score в runtime contract;
- показывать пользователю `AVA`-derived quality number;
- использовать `AVA` score как hidden gate для `good/mixed/needs_fix`;
- делать `AVA` score частью explainability trace.

### Forbidden C. `AVA` as eval gate

Запрещено:
- считать improvement на `AVA` benchmark достаточным доказательством качества hybrid stage;
- выпускать runtime path на основании только `AVA`-aligned metrics;
- заменять curated cinematic holdout public aesthetic validation-ом.

### Forbidden D. `AVA` as pseudo-label factory

Запрещено:
- генерировать из `AVA` pseudo-issues, pseudo-actions или pseudo-verdicts;
- напрямую маппить `AVA` score на `cinematic_expressiveness` или любой другой evidence head как на final target;
- подменять critique anchors из [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md) одним общим aesthetic band.

## Stage-Wise Pretraining Strategy

`PR-H04` фиксирует четырехэтапную стратегию.

### Stage 0. Data hygiene and source separation

Перед training pipeline обязательно:
- хранить raw `AVA` assets только в `PublicAestheticPretrainingManifest` с `trainingSourceKind = public_aesthetic_manifest` и `sourceFamily = ava_aesthetics`;
- не смешивать provenance `AVA` и `curated/runtime_hard_case`;
- хранить raw aesthetic-only public corpora через `PublicAestheticPretrainingManifest`, а не через `HybridDatasetRecord`;
- маркировать `labelTier` только у public assets, которые уже вошли в rubric dataset по `PR-H03`;
- не использовать `AVA`-derived labels в `full_rubric`.

Нормативное правило:
- public pretraining data и cinematic source-of-truth labels должны быть логически и отчетно разделены.

### Stage 1. Public aesthetic warm-start

Цель:
- получить broad visual encoder prior.

Источник данных для этого stage:
- records из `PublicAestheticPretrainingManifest`;
- rubric-labeled public assets из `PR-H03` не используются на этом stage, чтобы AVA/public-aesthetic warm-start оставался изолированным для честной ablation.

Разрешенные targets:
- coarse aesthetic band;
- score distribution / ordinal quality target;
- optional contrastive or ranking-style objective внутри public pretraining stage.

Результат stage:
- encoder/shared trunk weights;
- optional disposable `AVA` auxiliary head.

Нельзя делать на этом stage:
- учить `IssueTypeV1`, `ActionTypeV1` или final evidence taxonomy напрямую;
- считать, что модель уже готова к runtime inference.
- смешивать Stage 1 с rubric-labeled public supervision.

### Stage 2. Rubric alignment on cinematic data

После Stage 1 обязательно:
- удалить, заморозить вне runtime или переинициализировать `AVA`-specific head;
- подключить downstream heads только из taxonomy [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md);
- fine-tune модель на `curated` full-rubric data как на основном supervision source.

Важное правило:
- единого глобального priority list для всех objectives не существует;
- weighting обязан key-иться как минимум по `(objectiveFamily, trainingSourceKind, labelTier_or_sourceContract)`.
- raw `AVA` / `PublicAestheticPretrainingManifest` не может участвовать в `Stage 2+` scheduler ни для semantic, ни для calibration objectives.

Канонический порядок по objective family:
1. `semantic_head_supervision`
   - `hybrid_dataset_curated + full_rubric`
   - `hybrid_dataset_runtime_hard_case + full_rubric`
   - `hybrid_dataset_public + full_rubric`
   - `hybrid_dataset_public + public_partial_rubric`
   - raw `AVA` / `PublicAestheticPretrainingManifest` не допускается
2. `calibration_and_hard_error_suppression`
   - `hybrid_dataset_runtime_hard_case + full_rubric`
   - `hybrid_dataset_curated + full_rubric`
   - `hybrid_dataset_public + full_rubric`
   - `hybrid_dataset_public + public_partial_rubric`

Смысл:
- semantic authority определяется близостью к explainable cinematic rubric, а не просто bucket origin;
- `runtime_hard_case` доминирует только там, где нужна calibration и correction of known failures, но не заменяет `curated` как основной semantic teacher;
- валидный кейс `public + full_rubric` считается rubric supervision и поэтому стоит выше `public_partial_rubric`.
- raw `AVA` objective живет только в `Stage 1` и не должен протекать в downstream fine-tuning schedule.

### Stage 3. Domain adaptation and hard-case correction

После rubric alignment модель обязана пройти domain adaptation layer:
- mobile-like crops и aspect-ratio shifts;
- exposure shifts, low-light noise, compression artifacts;
- motion blur и handheld instability augmentations;
- oversampling ambiguity buckets и known hard cases;
- calibration на borderline frames, где deterministic и human rubric чаще расходятся.

Основная цель:
- уменьшить разрыв между polished still-photo prior и реальным mobile coaching usage.

### Stage 4. Release gating on cinematic eval only

Перед любым runtime rollout:
- экспортируемый bundle должен содержать только sanctioned evidence heads;
- `AVA` auxiliary head не должен входить в production model interface;
- release decision должен приниматься на curated cinematic eval и runtime-like buckets;
- `same_base_without_ava_stage` vs `AVA-initialized` ablation должна быть сохранена в report.

Нормативное правило:
- если `AVA` warm-start дает выигрыш только на public aesthetic proxy, но не на cinematic eval, он не считается полезным для продукта.

## Domain Adaptation Strategy

`PR-H04` фиксирует не только pretraining, но и поведение после него.

### 1. Source-aware weighting

Training pipeline обязан учитывать происхождение labels:
- weighting не может выражаться одной глобальной лестницей по `sourceBucket`;
- обязательный key space: `objectiveFamily`, `trainingSourceKind`, `labelTier_or_sourceContract`;
- `hybrid_dataset_curated + full_rubric` имеет максимальный приоритет для semantic supervision;
- `hybrid_dataset_runtime_hard_case + full_rubric` имеет максимальный приоритет для calibration и hard-error suppression;
- `hybrid_dataset_public + full_rubric` и `hybrid_dataset_public + public_partial_rubric` допустимы как supplemental rubric supervision;
- raw `AVA` / `PublicAestheticPretrainingManifest` имеет authority только внутри isolated `Stage 1` warm-start и нулевую authority в `Stage 2+`.

### 2. Head-specific supervision policy

Нормативные правила по head-ам:
- ни один runtime `EvidenceHeadId` из [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md) не может использовать raw `AVA` labels как final supervision target;
- raw `AVA` labels допустимы только для disposable auxiliary objective или shared trunk warm-start;
- `subject_prominence`, `background_clutter`, `lighting_quality`, `face_saliency`, `balance_confidence`, `depth_separation`, `cinematic_expressiveness`, `shot_type_confidence` должны получать final supervision только из rubric-labeled sources;
- `cinematic_expressiveness` нельзя обучать как простой alias для `AVA` score;
- если `AVA` используется для раннего auxiliary warmup этого направления, финальная калибровка обязана происходить только на rubric-driven data.
- public assets, уже relabeled по `PR-H03`, считаются rubric supervision и не подпадают под ограничения для raw `AVA labels`.

### 3. Confidence calibration on in-domain data

`confidence` для evidence head-ов:
- не калибруется на raw `AVA` validation;
- калибруется только на in-domain holdout из `curated` и `runtime_hard_case`;
- проверяется отдельно для ambiguity buckets.

### 4. Pause-first adaptation bias

Поскольку первый полезный hybrid milestone зафиксирован как `pause-only neural evidence`, adaptation strategy обязана:
- сначала оптимизироваться под still-frame `pause`;
- не использовать `AVA` как аргумент для раннего включения `live` path;
- не считать хороший public-aesthetic prior достаточным основанием для `live` rollout.

## Safeguards Against Misuse

### Safeguard 1. Contract firewall

- в runtime contract нет поля `avaScore`;
- explainability trace не ссылается на `AVA`-specific outputs;
- production API оперирует только heads из `PR-H02`.

### Safeguard 2. Dataset firewall

- raw `AVA` records остаются в `PublicAestheticPretrainingManifest` / public source family;
- rubric-relabeled public assets могут входить в `PR-H03` dataset только уже как rubric supervision, а не как raw aesthetic labels;
- `AVA` labels не попадают в `full_rubric`;
- `AVA` не подменяет critique anchors.

### Safeguard 3. Evaluation firewall

- release gate строится на cinematic eval;
- `AVA` benchmark допустим только как auxiliary research diagnostic;
- отчеты обязаны разделять `public proxy metrics` и `cinematic task metrics`.

### Safeguard 4. Reporting firewall

Запрещенные формулировки:
- "модель обучена оценивать cinematic quality на `AVA`";
- "`AVA` доказал качество critique engine";
- "высокий aesthetic score подтверждает хороший coaching verdict".

Допустимые формулировки:
- "`AVA` использован как public pretraining source";
- "`AVA` warm-start улучшил initialization/convergence under in-domain fine-tuning";
- "итоговое качество подтверждено только на cinematic rubric eval".

### Safeguard 5. Export firewall

- `AVA` auxiliary head не экспортируется в Core ML/runtime bundle;
- если export pipeline не умеет отделять auxiliary head, такой training setup не считается production-ready.

### Safeguard 6. Human-rubric override

- при конфликте между `AVA`-shaped prior и rubric-driven cinematic labels приоритет всегда у rubric-driven data;
- сложные conflict buckets должны попадать в hard-case review, а не "усредняться" public prior-ом.

## Risk Register

### R1. Domain gap masquerades as progress

Риск:
- рост public aesthetic proxy метрик ошибочно трактуется как рост cinematic critique quality.

Снижение риска:
- separate reports;
- cinematic holdout release gate;
- обязательная `same_base_without_ava_stage` vs `AVA-initialized` ablation.

### R2. `cinematic_expressiveness` collapses into beauty score

Риск:
- head начинает измерять только общий aesthetic appeal и перестает быть bounded evidence signal.

Снижение риска:
- head-specific rubric labels;
- запрет на direct `AVA` target как финальную supervision цель;
- проверка, что head не может sole-drive `good` verdict.

### R3. Actionability regresses

Риск:
- модель выглядит "умнее", но советы становятся менее конкретными и менее traceable.

Снижение риска:
- deterministic critique core остается source-of-truth;
- `AVA` не участвует в issue/action contracts;
- explainability faithfulness входит в release gate.

### R4. Public-data bias leaks into product behavior

Риск:
- stylized or contest-preferred images начинают системно переоцениваться в реальном mobile use.

Снижение риска:
- source-aware weighting;
- runtime hard cases;
- mobile-like augmentations и in-domain calibration.

### R5. Evaluation becomes scientifically dishonest

Риск:
- thesis/demo claims строятся на удобном public benchmark вместо task-realistic evaluation.

Снижение риска:
- явное разделение proxy и task metrics;
- downstream `PR-H14` обязан мерить hybrid uplift на curated cinematic buckets.

### R6. Auxiliary head leaks into runtime

Риск:
- `AVA`-specific output случайно остается в production graph или начинает влиять на final verdict через hidden heuristic.

Снижение риска:
- export firewall;
- runtime contract review в `PR-H06`;
- no raw `AVA` field in serialized snapshot.

### R7. Pause-first thesis erodes into premature live rollout

Риск:
- хороший public warm-start используется как аргумент для преждевременного включения neural path в `live`.

Снижение риска:
- `pause`-first release discipline;
- отдельные latency/thermal/runtime gates;
- запрет делать `AVA` benchmark substitute for live validation.

## Scientific Honesty Policy

Этот раздел обязателен для thesis/demo narrative.

### Что можно утверждать

Можно утверждать только следующее:
- `AVA` дал полезный initialization prior;
- `AVA` помог convergence или regularization;
- финальный uplift доказан только после in-domain adaptation и cinematic eval.

### Что нельзя утверждать

Нельзя утверждать:
- что `AVA` является датасетом cinematic coaching quality;
- что `AVA` сам по себе учит issue/action semantics;
- что хорошая корреляция с `AVA` score подтверждает качество explainable critique system.

### Required ablation language

В отчетах и заметках рекомендуется минимум такой compare:
- `same_base_without_ava_stage`
- `AVA-initialized`
- `AVA-initialized + curated fine-tune`
- `AVA-initialized + curated + runtime_hard_case adaptation`

Смысл:
- любой claim про пользу `AVA` должен быть локализован до конкретного места в training pipeline.

Нормативное уточнение:
- если в `PR-H05` используется backbone с generic pretraining до `AVA` stage, baseline обязан означать `тот же base setup без AVA stage`, а не обязательно случайную инициализацию;
- literal random-init compare допустим как дополнительная ablation, но не заменяет обязательный control без `AVA` stage.

## What This Unblocks Next

После фиксации этого документа:
- `PR-H05` может выбирать backbone и loss design, не протаскивая `AVA` в runtime semantics;
- `PR-H06` может проектировать `NeuralEvidenceSnapshot` без `AVA`-специфичных полей;
- `PR-H14` может отделять public proxy metrics от cinematic eval metrics;
- hybrid stage можно объяснять комиссии как `rubric-driven cinematic system with optional public pretraining`, а не как aesthetic score demo.

## Definition of Done (design mode)

Этот design считается готовым, если:
- явно перечислены допустимые и запрещенные роли `AVA`;
- stage-wise pretraining strategy не позволяет превратить `AVA` в hidden source-of-truth;
- domain adaptation strategy зафиксирована через source-aware weighting и in-domain calibration;
- safeguards against misuse покрывают runtime, dataset, eval и reporting layers;
- risk register объясняет, почему `AVA` опасен без ограничений;
- по документу понятно, как использовать `AVA` без архитектурной ошибки и без научного overclaim.
