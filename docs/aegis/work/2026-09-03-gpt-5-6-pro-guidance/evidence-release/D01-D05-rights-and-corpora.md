# D01 + D05 — реальные права/источники и corpus/human-gold для Scene Generator

Дата обследования: 2026-09-13. Ветка `store`, HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`.
Пакеты: D01 и D05 runbook `docs/aegis/plans/2026-09-13-setos-release-execution.md` (§5.2, §7).
Метод: read-only обследование файловых систем командой; ничего не скачивалось, не обучалось, не публиковалось. Секреты/env не читались.

Ключевой факт, подтверждённый командами: **ни в одном внешнем корне нет записи с `"release_admissible": true` и ни в одном нет `"human_gold": true`**:
```
grep -rl '"release_admissible": true' ~/Library/Application\ Support/SETOS/Datasets/camera-coach/research  -> 0 files
grep -rl '"human_gold": true'          ~/Library/Application\ Support/SETOS/Datasets/camera-coach/research  -> 0 files
```
Каталог `datasets/camera-coach/v1/research-source-catalog.json` задаёт `default_admission = "quarantine"`, `rights_policy.release_rule = "A research source is never release-cleared by this catalog"`, `human_gold_policy.status = "not_present"` для всех 10 зарегистрированных источников.

---

## D01 — права и реальные источники

### D01.1 Внешние реальные корни (обследованы)

Верхнеуровневый корень `~/Library/Application Support/SETOS/Datasets/` содержит только `camera-coach/research/` (верхнеуровневых datasets нет). Итоговый объём `~/Library/Application Support/SETOS/Datasets/camera-coach/research` = **5.1G**.

| путь | объём / число записей | лицензия / условия | receipt / хэш | класс | блокер для App Store | следующий конкретный шаг |
|---|---|---|---|---|---|---|
| `research/aadb/warp256-v1` | 152M; 9433 jpg; inventory/raw/silver по 9433 записи | AADB, `intake_tier=research_only`, `release_admissible=false`, `model_redistribution_cleared=false`, `human_gold=false`, `label_boundary=auxiliary_aesthetic_attributes_only`, `overall_score_only=true`; `rights.redistribution=do_not_redistribute_raw_media_or_derivatives` | `receipts/aadb-compact-receipt.json`; sha256 archive `a31adc66…`, inventory `a3c32369…`, raw `1f76c297…`, silver `8c69aae0…`; metadata `AADBinfo.mat` sha256 `307e6b84…` | **research-only** | research-only; веса base/derived не очищены для редистрибуции; атрибуты не action-labels | Не допускать pixels/derived-веса в production fit и в release bundle; оставить только research pretraining/silver teacher |
| `research/ava/human-rated-20k` | 655M; 12809 jpg; manifest 12809 строк | `license = "AVA research dataset; research/demo use only, no redistribution"`; `images rights-uncleared upstream`; `camera_coach_human_gold=false` | `receipt.json`; `manifest_sha256=fabc6285…`; в receipt `downloaded_now=7699`, `failures=1` | **blocked** | Прямой запрет редистрибуции + права на фото upstream не подтверждены; нет consent | Исключить из любых production-весов и из release; решение о правах AVA не принимается в проекте |
| `research/ava/legacy-silver-4000` | 205M; 4000 jpg; inventory 4000, manifest 4000 | Лицензия в manifest **не указана**; поля только `image_id/path/mean_score/total_votes`; правового файла нет | **receipt отсутствует** (только inventory+manifest, хэшей артефактов нет) | **unknown** | Нет ни лицензии, ни receipt, ни consent; provenance неполный | Либо добавить rights review и receipt с хэшем, либо пометить `quarantine` и не использовать |
| `research/eva/fb40a9f1` | 751M; 5101 jpg; inventory 5101, raw 5101, silver 4070 | Репозиторий `CC0-1.0`, но `underlying_ava_image_rights=unresolved`; `release_admissible=false`, `intake_tier=research_only`; `rights.redistribution=do_not_redistribute…` | `receipts/eva-source-receipt.json` (inventory sha256 `9e19d308…`, raw `6bf7f359…`), `receipts/eva-silver-receipt.json` (silver `8351cdfc…`, votes `b6be4855…`) | **research-only (права не подтверждены → фактически blocked)** | CC0 репозитория не снимает права на исходные фото AVA; нет consent | Не использовать pixels/derived-веса до отдельного разрешения прав AVA |
| `research/commons/v1-pilot-20-r3` | 17M; 15 изображений; candidates 21, accepted-rights 15, quarantined 145 | Per-file лицензии; receipt `rights_boundary="PD is a clearance_candidate, not release clearance"`; `release_admissible=false`, `research_only=true` | `receipts/commons-source-receipt.json` (accepted sha256 `78e73f4c…`, status `PARTIAL`, `exit_code=2`); `accepted-rights-receipt.jsonl` 15 строк | **research-only** | Public-domain — только clearance candidate, не release clearance; нужен per-file rights decision | Собрать per-file clearance decision на 15 PD-файлов + attribution; только после этого возможен release split |
| `research/commons/v1-scale-1000` | 518M; 767 изображений; candidates 1199, accepted 767, quarantined 6540 | То же; `release_admissible=false`, `research_only=true`; quarantined — `"license tuple is not allowlisted"` (напр. CC BY-SA/GFDL) | `receipts/commons-source-receipt.json` (accepted sha256 `fcdb4f62…`, quarantined `ccebda88…`, status `PARTIAL`) | **research-only** | 767 принятых — PD clearance candidates; 6540 в карантине по лицензии; нет release clearance | Per-file clearance для PD-подмножества; CC BY-SA/GFDL не допускать без юридического решения |
| `research/cinematic` | 1.5G; 319 jpg: Big Buck Bunny 146, Tears of Steel 167, tos_teaser 6; `mancandy` 0 изображений (пустой `frames.jsonl` 1 байт), каталог `sintel` без изображений и без `frames.jsonl`; `manifest.jsonl` 319 строк; в per-film `frames.jsonl` суммарно 362 строки (есть устаревшие записи без файлов) | `license_note = "CC-BY Blender open movies; research/demo use, attribution required, no redistribution"`; в manifest per-frame `license="CC-BY 3.0 (Blender Foundation)"`, origin `download.blender.org` | `receipt.json`; `manifest_sha256=5ea01c75…` | **research-only** | Репозиторная заметка прямо запрещает редистрибуцию; CC-BY потенциально допускает при attribution — но это не подтверждено юридически | Юридически подтвердить CC-BY для App Store distribution; если да — сгенерировать per-frame attribution notices и тогда перевести в admitted |
| `research/geometry/apple-vision-20260909` | 33M; 3 `geometry.jsonl` (aadb 9433, commons 767, eva 5101 исходных записей) | `human_gold=false`, `release_admissible=false`, `research_only=true`, `geometry_authority=silver_apple_vision`; conditional-on-runtime | 3 × `receipt.json` с counts/stdout sha256 | **blocked (производная)** | Производная от blocked/research-only родителей; редистрибуция не разрешена | Не допускать в release; держать как research silver geometry |
| `research/paired-corruptions/v1` | 1.1G; 5597 png; pairs: aadb 4265, eva 1099, commons 233 | `release_admissible=false`, `research_only=true`, `human_gold=false`, `split=research_fit`, `counts_toward_quota=false`; синтетические corruption-рецепты | 3 × `receipt.json` (`semantics_sha256=fcca9e96…`, seed 20260909) | **blocked (производная)** | Синтетическая производная research-only родителей; не доказывает переносимость | Не допускать в release; использовать как research corruption reference |
| `research/open-images-lamp-pilot-20260911.4PMfRR` | 50M; 1 изображение (`3bbc38b3beafe343.jpg`); inventory 1, source-manifest 1 | Open Images validation; `declared_license=https://creativecommons.org/licenses/by/2.0/`, но `"not legal clearance or consent review"`; `cloud_upload_authorized=false`; `research_only=true` | `detr-probe-receipt.json` (source sha256 `d2539de3…`, prediction `0302d2ff…`), `detr-signals-export-receipt.json` (source model spec sha256 `3d366683…`) | **research-only / unknown** | CC-BY заявлена, но не проверена независимо; облачная загрузка запрещена | Per-asset проверка лицензии, если изображение понадобится вне локального research |
| `research/vlm-polza/*` (9 run dirs) | 676K; 68 файлов; результаты `results.jsonl`, `manifest.json`, `sources.json` | `annotation_source="agent_visual_review; provisional localization anchors, not aesthetic gold"`; `human_gold=false`, `release_admissible=false`, `research_only=true` | `manifest.json` (`version=camera-coach.research-probe.1`), `summary.json`; хэшей артефактов нет | **research-only** | Это не человек и не gold; локализация provisional | Не использовать как human gold/разметку; только research-диагностика |
| `research/runs/eva-stage1-local-20260913`, `…/stage2-local-20260913` | 173M; 16 файлов (metrics.jsonl + receipt.json + checkpoint) | `release_admissible=false`, `research_only=true`, `human_gold=false`; disclaimer: silver/synthetic supervision, research-only, не release candidate | receipt: `data_hash`, `config_sha256`, `model_contract_sha256`, `git`, env | **research-only** | Обучены на research-only/silver данных; не являются production-весами | Не переносить в production lineage; зафиксировать как research checkpoints |
| `research/bundles` | 8.0K; 1 файл — только macOS `.DS_Store`, данных нет | — | — | **пусто** | Нет корпуса и правового содержания | Из рассмотрения исключить; при необходимости пересоздать bundle-каталог |
| `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1` (в репо) | 174 jpg; `camera_full_labels.jsonl` 174 строки, `camera_quick_labels.jsonl` 24 строки | `source_bucket="curated_user_inbox"`, `source_dataset="user_curated_candidate"`; правового/consent-файла нет; по `docs/implementation/STATUS.md` и `EXECUTION_STATE.md` пак исключён из Release (CC-002/n) | manifest без хэшей; labels содержат `sha256` per image | **unknown** | Происхождение photos = «user curated», но нет attestation/consent владельца; пак уже исключён из Release | Получить от владельца attestation авторства/consent на 174 кадра или оставить вне production admission |

### D01.2 Репозиторные manifests — шаблоны без records (проверено)

| путь | размер / строк | признак шаблона | класс |
|---|---|---|---|
| `datasets/camera-coach/v1/rights-manifest.jsonl` | 508 B, 1 строка | `record_count=0`, `template_only=true` | пустой шаблон |
| `datasets/camera-coach/v1/consent-manifest.jsonl` | 514 B, 1 строка | `record_count=0`, `template_only=true` | пустой шаблон |
| `datasets/camera-coach/v1/source-shoots.jsonl` | 744 B, 1 строка | `record_count=0`, `template_only=true` | пустой шаблон |
| `datasets/camera-coach/v1/derivation-manifest.jsonl` | 891 B, 1 строка | `record_count=0`, `template_only=true` | пустой шаблон |
| `datasets/scene-generator/v1/source-manifest.jsonl` | 566 B, 1 строка | `record_count=0`, `template_only=true` | пустой шаблон |
| `datasets/scene-generator/v1/rights-manifest.jsonl` | 615 B, 1 строка | `record_count=0`, `template_only=true` | пустой шаблон |

То есть ни одного реального source-shoot, consent, rights или derivation record в git нет; допущение корпуса «по наличию файла» невозможно.

Дополнительно: реальных сохранённых human-разметок нет. `~/Library/Application Support/SETOS/annotation/` содержит только очереди задач (не labels): `queue-v1.jsonl` 320 строк, `queue-v2-app-domain.jsonl` 174 строки, `queue-v3-cinematic.jsonl` 547 строк. Поля — `image_path`, `image_sha256`, `provenance`, `record_id`; ответов/голосов аннотаторов нет.

### D01.3 Явная классификация использования

**Можно (допустимо по текущему состоянию прав):** ничего из внешних корней не является admitted. Максимум, что допустимо технически внутри research-контура: unlabeled pretraining / silver teacher / hard-negative mining на AADB, AVA-HF, EVA, Commons(PD candidates), LIVE, SPAQ, KonIQ (согласно `admission.allowed` в `research-source-catalog.json`), а также research-диагностика на cinematic, geometry, paired-corruptions, vlm-polza и research checkpoints. В production-веса и в release-бандл — **ничего**.

**Нельзя:** использовать pixels/derived-веса AADB, AVA, EVA и производных (geometry, paired-corruptions) в production fit или редистрибуции; выдавать source MOS/атрибуты/aesthetic votes за Camera Coach human gold; объявлять любой корпус admitted по факту наличия; использовать `camera_device_benchmark_pack_v1` в Release (уже исключён) без attestation владельца; приписывать CC0 репозитория EVA права на фото AVA; считать Commons PD «release clearance» без per-file decision.

---

## D05 — отдельный corpus и human-gold для Scene Generator

### D05.1 Что реально есть

| путь | объём / число записей | лицензия / условия | receipt / хэш | класс | блокер для App Store | следующий конкретный шаг |
|---|---|---|---|---|---|---|
| `datasets/scene-generator/v1/source-manifest.jsonl`, `rights-manifest.jsonl` | 566 B / 615 B; по 1 строке | `record_count=0`, `template_only=true`; admission rule: copyrighted screenplay excerpts always excluded, нужен explicit lawful basis | манифест-хэши фиктивные `aaaa…` | **unknown (пусто)** | Нет ни одного admitted текста; нет lawful basis | Завести реальные records только из owner-authored/attested текстов с lawful basis |
| `docs/SGv7pipeline/runs/sgv7_full_20260417/final/dataset` | `sft_train` 2090, `sft_val` 200, `sft_test` 198; `preference_train` 1088, `preference_val` 128, `preference_test` 64; `split_manifest.json` (tier_b_deterministic_canonical 2488, core 1369/hard 1119) | Источники сгенерированы OpenAI-моделью (`gpt-5.4-nano`, `prompt_template_version=sgv7_source_prompt_v1`); `reviewer=None`, `review_decision=None`; правового manifest нет | `leakage_report.json`, `build_config.seed=20260417`, `split_manifest.json` | **research-only / unknown rights** | Нет прав на source texts (LLM-generated), нет human gold, нет rights/consent records; лицензия не определена | Построить rights/lineage manifest и прогнать через human annotation; без этого не release split |
| `docs/SGv8pipeline/runs/v8_0_seed42/plan_sft` | 5000 (train 4500 / val 500); `v8_plan_sft_manifest.json` | synthetic, `sg_v8_plan_ir_v1`; прав нет | manifest без внешнего хэша | **research-only** | Права на тексты не подтверждены; synthetic не становится locked human gold | Не использовать как locked test; сохранить как training candidate |
| `docs/SGv8pipeline/runs/v8_0_seed42/plan_preference_iter2_vs_v7` | 52 (train 47 / val 5) | synthetic preference pairs | manifest | **research-only** | Мало, synthetic | Research preference reference only |
| `docs/SGv9pipeline/runs/v9_0_seed42/event_sft` | `v9_event_sft_all` 5000 (train 4500 / val 500) | synthetic; `training_target=sg_v9_event_table_v1`; `packaging_metadata` с `split_family_id`, `graph_family_key`, `normalized_source_hash`; прав нет | нет отдельного receipt | **research-only** | Права текстов и human gold отсутствуют | Зафиксировать lineage и прогнать human review перед release-использованием |
| `docs/SGv9pipeline/runs/v9_0_seed42/patch_sft` | 5000 (train 4500 / val 500) | synthetic | нет receipt | **research-only** | То же | То же |
| `docs/SGv9pipeline/runs/v9_2_seed42/augmented_targeted` | 252 (event_sft all 252, train 215 / val 37); `failure_mining/v9_2_hard_cases.jsonl` 34 | synthetic augmentation | нет receipt | **research-only** | Права/human gold отсутствуют | Research only |
| `docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft` | 5564 (train 4730 / val 834) | synthetic mixed corpus | `V9_3_GOAL_AUDIT.md`, в runbook упомянут human pilot, но записей нет | **research-only** | Нет human gold; права текстов не оформлены | Зафиксировать split families и human-gold процесс |
| `docs/SGv9pipeline/runs/v9_3_seed42/augmented_targeted` + `exact_targeted_sft` | augmented 270 (train 230 / val 40); exact targeted 8 (7/1) | synthetic | нет receipt | **research-only** | То же | То же |
| `docs/SGv9pipeline/runs/v9_openai_source_trial_seed42` | candidates 30 (model `gpt-5.4-nano`), accepted_source 14, review_source 11, final accepted_merged 21, cir_merged 50 | LLM-generated source texts; `source_policy_version=sgv7_source_policy_v1`; прав нет | `graphs.manifest.json` (build_seed 20260415), `*_validation_manifest.json` | **research-only** | Права текстов не подтверждены | Research only; не считать независимым источником |
| `experiments/sc_benchmark/workspace/eval_bundle_v1` | `eval_cases.jsonl` **262** строки: synthetic_heldout 109, hard_heldout 89, real_runtime 64; origin: synthetic 198, runtime_reviewed 64; `gold_source=corrected_target_json` 262; `correction_tier=tier_b_deterministic_canonical` 262; `review_status=approved` 262 | gold получен детерминированно из corrected target JSON, не human annotations | `eval_bundle_manifest.json` с хэшами 5 snapshot-файлов (`6b8fbd0d…`, `f9779b62…`, `a1f2fc00…`, `678bdc22…`, `75374ebd…`); `leakage_audit.json` + `leakage_audit.md` | **research-only (locked-кандидат, но gold не человеческий)** | Заявленный gold — deterministic canonical, не два независимых annotator'а; права source texts не оформлены | Использовать как eval baseline, но построить отдельный human-gold packet; не выдавать `gold_target_json` за человеческий gold |
| `experiments/sc_benchmark/workspace/eval_bundle_v1_leakage_aware_all_models` | leakage audit по корпусам v7_sft_train 2090, v7_pref_train 1088, v8_plan_sft_all 5000, v8_plan_pref 52 и др. | method `leakage_aware_eval_bundle_v1`; exclude по `direct_origin_eval_case_id`, `exact_source_text`, `graph_family_key` | `leakage_audit.json` | **research-only** | Аудит доказывает пересечения (v7: 42 matched; v8 pref: 52/52), т.е. нужна family-level изоляция | Использовать audit как основу для новых split-правил |
| `data/legacy/dataset_finetune.jsonl`, `dataset_finetune_v2.jsonl` | 1883 + 1459 = 3342 строки; 13M | synthetic SceneScript SFT; лицензии/прав нет | нет receipt | **unknown / research-only** | Нет прав, нет provenance | Либо оформить происхождение, либо держать как historical only |
| `tools/scene_annotation/annotate_scene.py` + fixtures | 1 скрипт + fixtures (`positive-annotation-input.json`, negative-фикстуры) | инструмент; `datasets/scene-generator/v1/schema/fixtures/annotation-valid.json` содержит поля `votes[].annotator_id` / `review_history[].reviewer_id` — это **fixture**, не реальные голоса | нет | **инструмент** | Реальных сохранённых аннотаций нет | Провести реальную разметку и сохранить votes/history |
| `shafinMultitool/Resources/DeviceBenchmark/scene_generator_device_pack_v1` | `core_accepted_source.jsonl` **2375**, `hard_accepted_source.jsonl` **2198** | synthetic (`correction_tier=tier_b_deterministic_canonical`, `sg_v7_contract_v1`); manifest `seed_full=20260616` | `scene_generator_device_benchmark_manifest.json` | **research-only** | Synthetic; прав нет | Research/device benchmark only |

Оригинальный гайд `datasets/scene-generator/v1/guides/scene-annotation-guide-v1.md:6` прямо фиксирует: **"Human pilot for finalization is explicitly pending (M3-005)"**. Сохранённых human-разметок Scene Generator нигде в репозитории нет.

### D05.2 Чего требуют D05-шаги (gap к runbook §7 D05 / §5.2)

Текущее состояние против требуемого:
- **6 000 core train prompts** — есть только синтетические ~5000 (v9 event_sft) + ~5000 (v9 patch_sft) + ~5564 (v9.3), но без rights lineup и без human gold. Gap: правовое оформление + разметка.
- **800 validation/calibration, 1 200 locked core** — нет. `eval_cases.jsonl` 262 — только research eval-кандидат, gold детерминированный.
- **ambiguity 800/200, long-form 600/200, entity-binding 800/250, adversarial 500/250** — таких корпусов нет; ближайшее — synthetic hard cases (34 в v9.2, 8 в v9.3).
- **owner-independent qualitative ≥100, из них ≥30 независимо написанных; RU и EN ≥35% каждый** — нет ни одного owner/independent-authored текста с attestation.
- **Два независимых реальных annotators + adjudicator; entity/coreference, marked bindings, chronology, action, variants, clarification, forbidden meaning changes** — нет ни одного реального голоса; схема `scene-annotation-v1.schema.json` и fixture `annotation-valid.json` готовы, но пусты по данным.
- **Splits / запрет leakage** — есть `leakage_audit.json` с подтверждёнными пересечениями (v7 42, v8_pref 52/52); нужна явная family-level изоляция для нового корпуса.
- **Замороженные gates до locked test** (JSON 1.00, boundaries F1≥.98, actor attribution ≥.97, marked binding ≥.95, target resolution ≥.98, chronology ≥.98, hallucinated ≤.01, clarification recall ≥.90, critical meaning corruption 0, action recall ≥.98) — не зафиксированы в новом corpus contract.
- **Receipts на реальные корпуса SG** — отсутствуют; есть только build manifests без внешних хэшей и `eval_bundle_manifest.json` со snapshot-хэшами.

---

## Реальные внешние inputs, которых нет

Ниже — то, что должен подтвердить владелец, потому что это невозможно получить из кода/файлов.

| # | Что подтвердить | Точный ожидаемый документ | Способ проверки |
|---|---|---|---|
| 1 | **Owner attestation на camera-device benchmark pack** (174 кадра, `curated_user_inbox`): авторство, право на обучение и на распространение | Подписанный/датированный `datasets/camera-coach/v1/source-shoots.jsonl` record + `consent-manifest.jsonl` record на каждый family id с `source_owner_id`, `operator_id`, `captured_at`, `provenance_receipt_ref` | `tools/dataset/governance_check.py` + ручной provenance review; запись должна быть не `template_only` и `record_count>0` |
| 2 | **Consent/rights на внешние корни** (AADB, AVA, AVA-HF, EVA, Commons, cinematic): разрешены ли pixels/annotations/base weights/derived weights и редистрибуция | Per-source rights decision, привязанный к `datasets/camera-coach/v1/rights-manifest.jsonl` с `allowed_uses`, matching `source_id`/sha256 | Сверить с `research-source-catalog.json` `rights.tier` и `admission.blocked`; любой `unknown` не проходит admission |
| 3 | **Lawful basis на все Scene Generator тексты** (LLM-generated, legacy, owner scripts): кто автор/владелец, разрешено ли обучение и распространение | Заполненные `datasets/scene-generator/v1/source-manifest.jsonl` и `rights-manifest.jsonl` с `record_count>0`, `lawful basis in {owner-authored attestation, license, public-domain, complete synthetic lineage}`, sha256 на raw text | `datasets/scene-generator/v1/provenance/validate_scene_provenance.py`; copyrighted screenplay excerpts не допускаются |
| 4 | **Owner-independent qualitative texts ≥100, ≥30 независимо написанных, RU/EN ≥35%** | Датасет с authorship metadata (author id, locale, attestation) и рукописными сценами | Подсчёт долей RU/EN и независимых авторов; сверка с §5.2 |
| 5 | **Два реальных независимых аннотатора Scene Generator + adjudicator** (entities/coreference, marked bindings, chronology, action, variants, clarification, forbidden) | Сохранённые `votes[]` с реальными `annotator_id`, `review_history[]` с `reviewer_id`, hidden QC ≥95%, κ-метрики | `tools/scene_annotation/annotate_scene.py` output против `scene-annotation-v1.schema.json`; сейчас есть только fixture `annotation-valid.json` |
| 6 | **Решение по CC-BY cinematic (319 кадров)** — допустима ли редистрибуция кадров/derived в App Store при attribution | Юридическое подтверждение + сгенерированные per-frame notices | Проверить, что `cinematic/receipt.json license_note` обновлён и для каждого кадра есть attribution; иначе оставить research-only |
| 7 | **Per-file clearance для Commons PD-подмножества** (15 + 767) | Per-file rights decision с лицензией/URL/attribution и `clearance_candidate → cleared` | Сверить `accepted-rights-receipt.jsonl` каждого файла с `rights.license_kind` и `license_url`; `release_admissible` должен стать true только по явному решению |
| 8 | **Разрешение прав AVA upstream для AVA-HF/EVA** — без него эти 18 000+ изображений и производные недопустимы | Внешнее письменное разрешение или отказ → quarantine | `grep '"human_gold": true'`/`release_admissible` должен остаться false до документа |

---

## Команды, которыми проверены числа

```bash
# объёмы и файлы
du -sh ~/Library/Application\ Support/SETOS/Datasets/camera-coach/research   # 5.1G
du -sh ~/Library/Application\ Support/SETOS/Datasets/camera-coach/research/* # по корням
find <root> -type f | wc -l
# строки манифестов
wc -l <manifest>
# пустота/шаблонность репо-манифестов
cat datasets/camera-coach/v1/rights-manifest.jsonl   # record_count=0, template_only=true
# отсутствие admitted/human_gold
grep -rl '"release_admissible": true' <root>   # 0
grep -rl '"human_gold": true' <root>           # 0
# D05
find docs/SGv9pipeline -name '*.jsonl' -exec wc -l {} \;
wc -l data/legacy/*.jsonl
wc -l experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl  # 262
```

## Итог

- Реальных admitted (production/release) корпусов нет ни по Camera Coach, ни по Scene Generator. Всё внешнее — `research-only`, `blocked` или `unknown`; `release_admissible=true` и `human_gold=true` не встречаются нигде.
- Реальные внешние pixels есть (AADB 9433, AVA 12809+4000, EVA 5101, Commons 782, cinematic 319, paired 5597, geometry silver, open-images 1), но права на них не очищены.
- Репозиторные rights/consent/source-shoot/derivation и scene source/rights manifests — шаблоны `record_count=0`, `template_only=true`.
- Scene Generator: есть крупные синтетические корпуса (v9 event_sft 5000, patch_sft 5000, v9.3 mixed 5564, v7 sft 2090, v8 plan 5000) и eval 262, но gold — `corrected_target_json`/`tier_b_deterministic_canonical`, не человеческий; реальных голосов аннотаторов и owner-authored текстов нет. D05 не закрыт.
