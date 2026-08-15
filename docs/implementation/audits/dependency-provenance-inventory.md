# CC-004 dependency, model, media, and acknowledgement provenance inventory

Evidence snapshot: starting commit `d40a4ec67e34260b77584a62f4efd76ccff41c6a` (`d40a4ec docs: accept privacy and test topology audits`), detached `HEAD`, clean before this audit. This file is the only file owned by CC-004.

This is a repository-evidence audit, not a legal opinion and not a redistribution approval. It records what is present, what the repository says about it, and what is still unknown. A filename, model family, paper citation, README statement, or embedded string is not treated as permission to redistribute. “Verified” below means that the stated evidence path and scope are concrete in this checkout; it does not mean that a legal or App Store owner decision has been made.

## Executive disposition

The checkout is not provenance-ready for an App Store release. The main blockers are the vendored `llama.xcframework`, all intended local model payloads, the two present Core ML packages plus one missing default Core ML model, the USDZ and image families, and the camera benchmark pack. The benchmark and research packs must not enter Release until the owner either supplies a complete source/permission/content record or explicitly keeps them development-only.

The accepted `docs/implementation/audits/release-bundle-inventory.md` did not exist at the starting commit. Therefore, sizes below are source-tree measurements unless explicitly labelled historical `STATUS.md` evidence. The Xcode project uses a synchronized app root, so the non-source files under `shafinMultitool/**` are bundle-entry candidates; the final archive still needs a separate reproducible bundle audit.

| Disposition | Count | Meaning in this audit |
| --- | ---: | --- |
| `verified` | 2 | Concrete local evidence covers the stated current scope; no legal conclusion. |
| `missing` | 8 | Provenance, redistribution, source, or identity evidence is incomplete, or the expected payload is absent. Release is blocked until resolved or intentionally removed. |
| `replace` | 0 | No replacement was selected by this audit. |
| `exclude` | 2 | The current ship candidate should not contain this family unless the owner reverses the decision after evidence review. |
| `non-shipping-development-only` | 4 | Keep outside the Release target/bundle; Debug/device harness use remains possible only if separately gated. |

Top blockers:

1. `Frameworks/llama.xcframework` is linked and embedded, but its upstream source commit/version and license/notice package are not recorded.
2. `compact_neural_evidence_net` is the default local Core ML provider contract, but no matching model package is present in the clean checkout.
3. The two present Core ML packages have hashes and limited serialized metadata, but no complete source/conversion/notice record.
4. No GGUF payload is present in this clean checkout. The historical `STATUS.md` bundle measurement cannot serve as a current model hash or provenance record.
5. Camera benchmark images include user-curated, public-IQA, official-promo, and synthetic families. The current app pack lacks complete source/permission records and has 41 label rows with no image hash.
6. App branding images and `Person.usdz` still have no repository source, author, license, notice, or export record. `Circle.usdz` now has repository-correlation evidence from common UUID/metadata/hash/Git observations, but source-to-export causality, a deterministic export recipe, and an explicit creator/rights declaration remain unproven or missing.
7. A final Release archive and accepted allowlist are absent, so synchronized-root membership has not been proven against a built product.

`Circle.rcproject` and `Circle.usdz` have verified repository-correlation evidence in `docs/implementation/provenance/circle-asset-provenance.json` and `scripts/validate_circle_asset_provenance.py`: recorded RCFoundation project metadata, exported-member bytes, hashes, Git co-change and a shared object UUID agree as repository observations. This does not prove that the project caused or was used to export the USDZ. Deterministic source-to-export recipe, creator, permission/right, redistribution approval, and App Store readiness remain unproven; the legal/release owner decision remains blocked.

The record's `git_lineage`, `runtime_consumers`, and `source_project.target_boundary` are human-reviewed annotations. The validator checks their shape only; it does not verify Git history, source lines, or `project.pbxproj` membership.

## Scope, authorities, and bundle boundary

Authorities read:

- `docs/app-store-product-plan.md`: identifies unknown benchmark provenance, potentially bundled ~1 GB model material, missing privacy manifest, and legal review of models/datasets/images/assets as App Store gates.
- `docs/implementation/BACKLOG.md`, CC-004: requires this exact audit path and the dependency/model/media fields used below.
- `docs/implementation/STATUS.md`: records historical bundle observations, including a parent Release partial app of 1,198,316 KB and a 1,094,912 KB GGUF; those figures are not measurements of this clean checkout.
- `docs/implementation/audits/release-bundle-inventory.md`: absent at the starting commit; no accepted bundle allowlist was available.
- `Podfile`, `Podfile.lock`, the vendored `Pods/**` metadata, `Frameworks/llama.xcframework`, Core ML packages, app resources, source consumers, acknowledgements, README files, and `shafinMultitool.xcodeproj/project.pbxproj`.

The app target is a `PBXFileSystemSynchronizedRootGroup` at `shafinMultitool` (`project.pbxproj:75-87`). Its build-file exception list contains `Info.plist` and `Resources/Circle.rcproject` (`:54-62`); the compile-source exception also contains `Resources/Circle.rcproject` (`:65-72`). The practical implication is that Core ML packages, DeviceBenchmark packs, USDZ files, asset catalogs, and other non-source files below the app root must be treated as bundle candidates until a built Release archive proves otherwise. `Circle.rcproject` is explicitly excluded from target membership and compile sources.

System SDK references such as `ARKit.framework`, `RealityKit.framework`, Core ML, Vision, AVFoundation, Core Video, and Photos are not vendored third-party payloads in this repository. They are recorded as SDK usage, not counted as redistributable third-party components in the disposition table. Their camera/microphone/Photos behavior is already documented in the CC-003 privacy/permissions audit.

## Disposition inventory

The tables use the required fields for every component/family row. Hashes are SHA-256 unless stated otherwise. A package/family aggregate digest is the SHA-256 of the sorted per-file `shasum -a 256` output for that package/family. “No evidence” means no repository evidence was found; it does not assert that a right or permission does not exist outside this checkout.

### CocoaPods direct and transitive components

`Podfile.lock` lists exactly two pod components and no additional transitive pod entries. The lock was generated with CocoaPods `1.12.1` from `https://github.com/CocoaPods/Specs.git`; the Podfile pins `ARVideoKit '~> 1.5.51'` and `SnapKit '~> 5.6.0'` for the app, with SnapKit also used by tests.

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SnapKit | `Podfile:7`, `Podfile.lock`; `SnapKit (5.6.0)`; spec checksum `e01d52ebb8ddbc333eefe2132acf85c8227d9c25`; `Pods/SnapKit/LICENSE` SHA-256 `7c0d21cf5314759fd35a22e42a52099d9cad2570db55a78e4eda26c82493b96b` | Direct app and test pod. App source imports it in `Views/PerformanceOverlayView.swift`, `Extensions/UIView+Extensions.swift`, `SceneModules/CameraScreenModule/View/CameraScreenViewController.swift`, and `SceneGeneratorModule/Views/LegacySceneGeneratorCameraShell.swift`. CocoaPods target support links/embeds `SnapKit.framework`. | Pinned local CocoaPods source tree and `Pods/SnapKit/README.md`; no exact upstream commit is recorded in the lock. | `Pods/SnapKit/LICENSE`; generated app acknowledgement `Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.markdown` / `.plist`; generated plist labels the entry `MIT`. | The local license, lock checksum, and generated acknowledgement are concrete repository evidence for this pinned pod. No separate product-owner disclosure decision is recorded. | SnapKit source inspected as a UIKit layout DSL; no URL/session, camera, microphone, Photos, or speech capability was observed. | No accepted archive exists. Framework is a declared link/embed input in `Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-frameworks-Release-input-files.xcfilelist`. | `verified` | Preserve the generated acknowledgement in the final disclosure surface and recheck the built archive. | High — lock, local license, consumers, and generated acknowledgement all present. |
| ARVideoKit | `Podfile:6`, `Podfile.lock`; `ARVideoKit (1.5.51)`; spec checksum `cd70e1e49e042ed4a88fb59964c17520e34f7f5b`; `Pods/ARVideoKit/LICENSE` SHA-256 `c8a43b944cf362a4a67c252da9fa40460d262260748ccdc855a2c60f6a7cd9e2` | Direct app pod. CocoaPods target support links/embeds `ARVideoKit.framework`. No app-side `import ARVideoKit`, `RecordAR`, or `RenderAR` consumer was found in the searched production Swift; the pod is still a release bundle input. | Local source tree and `Pods/ARVideoKit/README.md`; README describes AR video/photo/Live Photo/GIF capture and points to its upstream project, but no exact source commit is locked. | `Pods/ARVideoKit/LICENSE`; generated app acknowledgement markdown/plist; generated plist labels the entry `Apache 2.0`. README also contains a publishing note to add the ARVideoKit license to the app licence list. | Local license and acknowledgement exist, but the repository has no owner decision explaining why this linked/embedded capability is needed when no app consumer was found. | Inspected pod source contains camera, microphone, audio-session, and Photos permission/capture paths (`ARVideoKit/Rendering/Writer/WritAR.swift`, `ARVideoKit/Sources/RecordAR.swift`). No network stack was observed. | No accepted archive. Framework is an explicit Release input in the CocoaPods xcfilelist; final bytes are unmeasured here. | `exclude` | Release owner: confirm no hidden/serialized consumer, then remove the Podfile entry and regenerate the pod lock/project support files in a separate implementation task; otherwise retain only with an explicit capability and acknowledgement decision. | Medium — local pod evidence is strong; no app callsite and no final archive. |

No other pod component appears in `Podfile.lock`; there is no transitive pod row to inventory. The app acknowledgement covers only ARVideoKit and SnapKit, not any other family below.

### Vendored native binary

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `llama.xcframework` | `Frameworks/llama.xcframework`; device `ios-arm64/llama.framework/llama`: 4,525,784 bytes, SHA-256 `a1b7a3743d31f19dce2bffd9cf8ea873c43449dd3c8cc12d03aff698611a2066`; simulator universal slice: 9,522,920 bytes, SHA-256 `ad72b38fc0c5073aa90794506c4abdd68b4423e54b5702eb6d5e18841c95054a`; top Info.plist SHA-256 `d627efae4a23e59d7c007e3de77109b1a616512a17087715e8c2caeca2c43a7d`; framework Info.plists SHA-256 `37905f3a249c754041bab4c4c84c7089566e8feecbc8e70a4e4dec0246147af1` | Linked and embedded with `CodeSignOnCopy` by `project.pbxproj:13-14,105-119`. `SceneGeneratorModule/Services/LlamaContext.swift` imports the `llama` module; `LLMParserService` calls it for local GGUF inference. | Info.plist identity is `org.ggml.llama`, `CFBundleVersion=1`, `MinimumOSVersion=16.4`; the xcframework has device arm64 and simulator arm64/x86_64 slices. Reachable Git history records `cec8fb70d0bb9fdb63b1e1dda9030a53b3a9eb7c` (`Project snapshot`) and `78aed0f4fa085de505f0f1fcd725dbe0fd999e6c` (`llama.cpp + Qwen2.5-0.5B` integration), but neither is an upstream llama.cpp source commit/version for the shipped binary. `strings` exposes build-path/upstream-reference text only; it does not establish provenance. | No `LICENSE`, `NOTICE`, README, or copyright package exists below `Frameworks/llama.xcframework`. The binary contains the string `general.license`, which is not a substitute for a repository notice file. | README statements that the app bundles llama.cpp and the two Git history messages do not establish permission for this exact binary or its build inputs. No source commit, build recipe, or redistribution record is present. | App consumer is local inference; no app `URLSession`/network consumer is associated with this framework. Native-binary internals are not treated as fully audited from strings alone. | Device slice is 4.53 MB; simulator slice is 9.52 MB. No accepted Release archive. Historical `STATUS.md` model size is GGUF data, not this framework. | `missing` | LLM owner: identify the exact upstream source repository/commit and local build recipe, preserve the complete applicable license/NOTICE set, record the device/simulator hashes, and give Release an explicit keep/exclude decision. | High for presence/identity; low for provenance/redistribution. |

### Core ML packages and generated metadata

The clean checkout contains two `.mlpackage` directories. It does not contain the default `compact_neural_evidence_net` package requested by `CoreMLNeuralEvidenceProvider.ModelResource`. The package sizes below are source-tree payload sizes (sum of package files), not an archived app size.

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Default compact neural evidence model | Expected bundle resource name `compact_neural_evidence_net.mlmodelc` or `.mlpackage`, requested by `shafinMultitool/Multitool2Module/Services/Pipeline/CoreMLNeuralEvidenceProvider.swift:14-25`; no matching file/path exists anywhere in the checkout. Descriptor claims model family `compact_neural_evidence_net`, version `h05.v1`, bundle version `compact_neural_evidence_net.bundle.v1` (`:43-52`). | `NeuralEvidenceInferenceService.makeDefault()` constructs this provider (`NeuralEvidenceInferenceService.swift:329-332`). In the current tree `isModelAvailable` can only be false for this provider because the resource is absent. | Consumer code and design documents `docs/cameraanalysis/18-hybrid-model-architecture-spec.md`, `19-neural-evidence-domain-contract.md`, and `29-on-device-semantic-evidence-distillation-plan.md` name the contract, but no model artifact, conversion manifest, source commit, or weights is tracked. | None found. No package manifest, model spec, weights, `LICENSE`, or `NOTICE` exists for this expected family. | No payload or permission record to inspect; model identity is a code contract, not a redistribution record. | Intended provider is on-device Core ML; no network API is in this consumer. | 0 bytes present in this checkout. `STATUS.md`’s approximate Core ML total refers to present source packages and does not prove this model exists. | `missing` | ML owner: either provide the exact package plus source/conversion/checksum/notice record, or intentionally disable/replace the provider and adjust its consumers and release acceptance. | High — absent artifact and exact consumer are directly observable. |
| DETR ResNet-50 semantic segmentation | `shafinMultitool/Multitool2Module/Models/CoreML/DETRResnet50SemanticSegmentationF16P8.mlpackage`; 43,085,928 bytes; package aggregate digest `94027c4eeca5707937753eab3b682716eac7d20e76be78fc6565dc972d9072b8`; spec `model.mlmodel` 337,183 bytes, SHA-256 `3d3666837fe990d3948308e417949864b5c2ab0dd9f21091c755c8effa005c40`; weights 42,748,128 bytes, SHA-256 `8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7`; Manifest SHA-256 `e7154240ddfd55b776642ae4f6b47d42bf8ad1b9425d97151d4d7b7875d0bf95` | Candidate synchronized-root resource. `Models/CoreMLWrappers/DETRDetector.swift:50-68` loads it by name; pipeline code consumes detections for local semantic evidence. | Serialized spec includes the DETR name, a paper citation, the `facebook/detr-resnet-50-panoptic` source URL, COCO-style labels, and the text `Apache 2`. This is model-embedded metadata only; no exact source revision, conversion command, training-weight identity, or complete notice is recorded. | No standalone license/notice/readme exists under the package or Core ML directory. The embedded `Apache 2` text is not treated as a complete license/notice package. | No repository permission or redistribution record links the current converted weights to the cited source. Do not infer clearance from the model name or embedded citation. | Loaded locally through Core ML/Vision; no network or user-media persistence is performed by this wrapper. The model consumes camera-derived pixel buffers in the on-device pipeline. | 43.09 MB source payload (about 41.1 MiB). No accepted archive. | `missing` | ML owner: record exact source weights/revision, conversion tool/version and command, model-specific notice/license evidence, and final hash; otherwise replace or exclude the consumer. | High for bytes/consumer; medium-low for origin/notice. |
| NIMA MobileNet aesthetic scorer | `shafinMultitool/Multitool2Module/Models/CoreML/aesthetic_nima_mobilenet_fp16.mlpackage`; 6,499,576 bytes; package aggregate digest `5e7f33b3967b7738a4c3c2c7f87ce5a9204e976f2e86d221a974f9eba581c743`; spec `model.mlmodel` 82,747 bytes, SHA-256 `e5d44425c132e7ed2be99310226b573ae1765c37a909c1a0fd08aff311fb9cfc`; weights 6,416,212 bytes, SHA-256 `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717`; Manifest SHA-256 `552c2bf2bbcd6e91f8f87b5a724dcdaa765895dbc179a9e28e0b4181d05eeaae` | Candidate synchronized-root resource. `Models/CoreMLWrappers/AestheticScorer.swift:12-22` loads it by name and scores camera frames; the pipeline invokes the scorer as an on-device signal. | Serialized spec contains `tensorflow==2.20.0`, `coremltools` source/version markers, and `nima_mobilenet_v1` graph names. No source URL, model checkpoint identity, conversion date/command, or exact upstream revision is present. | No standalone license/notice/readme exists under the package or Core ML directory. | No repository permission or redistribution record links the current weights/conversion to an identified source. Framework/tool markers are not a license. | Loaded locally through Core ML/Vision; no network API in the wrapper; consumes camera-derived pixel buffers. | 6.50 MB source payload (about 6.20 MiB). No accepted archive. | `missing` | ML owner: provide source/checkpoint identity, conversion recipe/tool versions, applicable notice/license evidence, and final hash; otherwise replace or exclude the scorer and its consumer. | High for bytes/consumer; low for provenance. |

### GGUF model families and local payload policy

The clean checkout contains no `.gguf` file. `.gitignore` ignores `*.gguf` and `/models`; `git status --ignored` showed no ignored GGUF payload in this worktree. This is materially different from a tracked clean checkout containing a model and from the historical parent Release measurement in `STATUS.md`.

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Intended release GGUF candidates | Expected `shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf`; test alternative `shafinMultitool/Resources/Models/qwen2.5-1.5b-instruct.Q4_K_M.gguf`; benchmark direct bundle lookup in `DeviceBenchmarkCoordinator.swift:1363-1388`; no file exists and no hash/model header can be measured. | `LLMParserService.swift:2338-2375` discovers GGUF files in the main/all bundles and frameworks; `LlamaContext` loads the selected local model. `scripts/run_open_domain_scene_benchmark.py:23` expects the dataset-v9 path. | `.gitignore` only proves local payload policy. README and historical docs mention bundled llama.cpp and model workflows, while code/tests name candidate files; no exact model card, source commit, training-data record, checksum, or model-specific provenance ledger is present. | No GGUF-side `LICENSE`, `NOTICE`, model card, or attribution file exists in the clean checkout. | Current status is “absent,” not “approved for download or redistribution.” A historical `STATUS.md` note reports a parent Release partial app with `dataset_v9_event_sft_q4_k_m.gguf` at 1,094,912 KB, but provides no hash or permission evidence and is not a current checkout measurement. | Runtime is local inference; no network download path is established by these consumers. A separately supplied model could have different data/privacy obligations, which remain unknown. | 0 bytes present now. Historical parent bundle numbers are reference-only; no accepted bundle audit exists. | `missing` | LLM/release owner: select one exact model, supply the actual payload or an explicitly approved download/on-demand design, record model header/version/source/checksum/notice evidence, and measure the final Release bundle. | High for absence/path references; low for model provenance. |
| Developer-local ignored GGUF family | `.gitignore` entries `*.gguf` and `/models`; expected local locations include `shafinMultitool/Resources/Models/**`; no payload found by `find . -name '*.gguf'` and no ignored GGUF entry reported. | Development/test-only local inference convention. It is not a tracked resource and cannot be assumed to enter an app bundle from this clean checkout. | Only ignore rules and local test/runtime path conventions are present. No concrete local file identity exists to hash or inspect. | None. | No local payload is present; therefore no redistribution claim can be made. | Local-only runtime convention; no network evidence. | 0 bytes in this worktree. | `non-shipping-development-only` | Release owner: keep ignored local files outside synchronized app membership and add a Release allowlist assertion that no GGUF enters unless the release candidate row above is resolved. | High for current absence; medium for developer environments outside this worktree. |

### DeviceBenchmark image and data families

The two tracked packs are below the synchronized app root. They are runtime-resolvable by `DeviceBenchmarkSupport.swift:344-371` and materialized by `:381-420`; the benchmark route is environment-gated, but the resource files remain bundle candidates. The current camera pack differs from the historical `STATUS.md` summary: current source measurement is 179 files and 37,249,630 bytes, not 182 files and approximately 51 MB.

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Camera device benchmark pack v1 | `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/`; 179 files, 37,249,630 bytes; family digest `a7d2298eae745d04b40bc31b7ba6f4d65b49cf52a6193d1224b815596a69ce2`; 174 images (146 `.jpg`, 8 `.jpeg`, 20 `.bmp`) and 5 metadata files. Manifest SHA-256 `116ff030e6ddac44ae276487945b0b249acc8bc71621db0afd602dfaa2470b1a`; full labels SHA-256 `c1dba72a21551b70cc8edc4bbe9f3484c95776b24b84e8fe5d659f3a4cb0eefc`; quick labels SHA-256 `1849907741f0837d08d4fca8473b13568ee0e1ee438d97adb7c6ceea86661a10`; guided SHA-256 `862afbafbc4731b676b2a679a560c5ccbb32ccb8ee0469d12c9a1fe8ea496641`; live sequences SHA-256 `14ffd976652af16437e1ccf450e32d35d37094e29be1bfd585f17daf13f51618` | Benchmark-only camera replay/evaluation. `DeviceBenchmarkSupport` resolves the pack from `Bundle.main` and copies its images/JSONL/manifest to a local benchmark directory. `SceneDelegate` can enter the harness through `DEVICE_BENCHMARK_CONFIG_BASE64`. | Current label fields identify five source datasets: `user_curated_candidate` 57 full rows, `live_challenge_bad_tail` 50, `apple_tv_press_trailer_poster_candidate` 35, `imagegen_bad_v2_regen_bad_v1` 15, and `apple_tv_press_synthetic_bad_v2_regen_bad_v1` 17. Source buckets are `curated_user_inbox`, `public_iqa_bad_tail`, `official_promo_cinematic_preservation`, `imagegen_bad_candidate`, and `synthetic_bad_paired_apple_tv_press`. `docs/cameraanalysis/dataset/README.md:42-52` describes the intended source policy and says separate manifests contain URLs/parent paths, but those source records are not carried into the current app pack. | No `LICENSE`, `NOTICE`, `COPYING`, or permission file exists under the pack. `docs/cameraanalysis/dataset/inbox/unsplash_sources.jsonl` has source metadata fields, including a `license_note`, but it is outside the app pack and is not a complete rights record for this family. | The current pack does not establish permission to redistribute the user-curated, public-IQA, official-promo, or synthetic-derived media. The repository also does not establish privacy clearance for people or other personal/third-party content. | 37.25 MB source-tree payload; no accepted Release archive. Full labels contain 174 records and quick labels 24. Non-null image hashes match actual files: full 139/174, quick 18/24; 35 full + 6 quick rows have no `sha256` value. Review fields show 142 rows still marked as first-pass/human-review-needed and 32 as the regeneration visual-audit status. | `exclude` | Benchmark/privacy/release owner: exclude from Release now; if retained later, preserve per-image source/permission/privacy/content decisions, fill the 41 missing hashes, reconcile current numbering with source manifests, and produce a Debug-only membership proof. Do not put raw images in an approval report. | High for files/counts/metadata; low for redistribution/privacy. |
| Scene generator device pack v1 | `shafinMultitool/Resources/DeviceBenchmark/scene_generator_device_pack_v1/`; 3 files, 15,669,658 bytes; family digest `466739320078d5cf59c3f551f6204477d6a544854b6f4c1d79f5965acab6d2b6`; core JSONL 2,375 rows, SHA-256 `b15851d8a33fbedcf80b52d85b02d94daabac4448021dc9929be0deaf6bc6d51`; hard JSONL 2,198 rows, SHA-256 `948434e4586766b2f4d178d8f9154d0583e789489a5cbecc157d75f4ea715e16`; manifest SHA-256 `d1c8e90151052f7061828f5995b879fb375d681dd98175251fda745d11fff714` | Device benchmark scene-generation inputs; loaded by the same benchmark pack resolver and passed to local LLM benchmark execution. Not a declared commercial content source. | Records identify `model_name=gpt-5.4-nano`, `source_policy_version=sgv7_source_policy_v1`, `contract_version=sg_v7_contract_v1`, `validation_status=accepted`, and `train_eligibility=direct_sft`. These are generation/evaluation metadata, not a redistribution grant or dataset licence. | No license, notice, source-generation ledger, or redistribution record exists under the pack. | No repository evidence supports shipping this generated evaluation corpus as app content. The model name is not treated as provenance or permission. | Local JSONL only; no network behavior in the pack. It contains generated prompts/scene data, not raw media, but source/authoring and redistribution terms remain incomplete. | 15.67 MB source-tree payload; no accepted Release archive. | `non-shipping-development-only` | Benchmark/release owner: keep outside Release via explicit allowlist; if product later needs it, create a generation/source/permission ledger and measure the Debug-only path. | High for files/metadata; low for redistribution. |

### Image and icon families

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| App material images and icon family | `shafinMultitool/Resources/Assets.xcassets`: `background.png` 1,908,458 bytes, SHA-256 `45d6d015721e3a4d36522dbf160e476f64dc047a4448524e1767268f241e0fb9`; `blur.png` 5,362 bytes, SHA-256 `caa88f0cbf495454104ea4875826706bee3a4608f27315b15e40f728212d0081`; `logo_menu.png` 23,322 bytes, SHA-256 `8f2350d110094ba3ecdf288df4652b8a902b6ac1e5f28d2bd7196bb0f3c94f9f`; `лого-кругл.png` 596,865 bytes, SHA-256 `640059d36001808139ba57d285b9d23ee445cbb8598a9a3dbcc96ef3c15c3984`. The catalog also has generated `Contents.json` files. | UI background/blur/logo and AppIcon candidates under the synchronized app root. Project build settings select `AppIcon` and `AccentColor`; exact runtime lookup for the three named raster sets was not found in the searched Swift, but synchronized-root membership still makes them release candidates. | No author/source/design file, source URL, creation record, or asset provenance metadata is stored in the catalog. `Contents.json` identifies Xcode catalog structure only. | No asset-level `LICENSE`, `NOTICE`, or attribution file exists. | Repository evidence does not distinguish app-owned artwork from third-party or generated artwork and provides no redistribution record. | No network behavior. Unknown image content/privacy/brand provenance is itself the blocker; total material raster payload is 2,534,007 bytes. | 2.53 MB source-tree raster payload; no accepted archive. | `missing` | Product/brand owner: provide a source/creation/permission record for each material image and icon, or replace with provenance-cleared assets; release owner must verify final AppIcon/catalog membership. | High for bytes; low for origin/rights. |
| Contents-only asset catalog and app-owned UI resources | `shafinMultitool/Multitool2Module/Assets.xcassets` contains only `Contents.json`, `AppIcon.appiconset/Contents.json`, and `AccentColor.colorset/Contents.json`; `shafinMultitool/LaunchScreen.storyboard` is the app UI resource. `Info.plist` is an explicit build-setting input and is excluded from synchronized resource membership. | Generated catalog metadata and launch UI; no material third-party raster payload was found in this family. | Local Xcode catalog/storyboard files; no external component or source claim. | No third-party license/notice required by the repository evidence for these app-owned/generated files. | Scope is limited to confirming absence of a material third-party payload; it is not a legal approval of app branding. | No network/privacy capability beyond the app UI itself. | Contents-only catalog is negligible; final archive not measured. | `verified` | Keep this scope in the archive allowlist check and separately resolve the material image family above. | High — exhaustive file listing in the app root for these paths. |

### USDZ, Reality Composer, sample media, and generated scene data

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Person USDZ | `shafinMultitool/Resources/Person.usdz`; 412,930 bytes; SHA-256 `a4af24cd3b5dad3ff19d8bf64b4ae10a92618ff3bd6ce0e70a7a15bb36814010`; archive contains `FinalBaseMesh.usdc` 412,764 bytes. Git history adds it in commit `655a860820171139d14e59c2a04f7a3ba0f144c1` (`Elapsed time added`). | Runtime-loaded by `ModelEntity.loadModel(named: "Person")` in `SceneGeneratorViewModel.swift:1766-1774` and `CameraScreenInteractor.swift`; synchronized-root bundle candidate. Saved AR world maps/scenes refer to anchors named `Person`, so dynamic/serialized use cannot be excluded by literal `.usdz` search alone. | Git history provides an addition commit only; no author, modeling source, export settings, source asset, or upstream URL is present. | No USDZ-side or resource-side license/notice/credits file. | No repository permission or redistribution record for the mesh. | Local RealityKit asset; no network behavior. It can be attached to camera/AR scene data, but the mesh’s origin and privacy content are unknown. | 412,930 bytes source-tree payload; no accepted archive. | `missing` | 3D/product owner: provide source/export/provenance/permission record and final hash, or replace/exclude the model and update dynamic/serialized scene behavior. | High for runtime/hash; low for origin/rights. |
| Circle USDZ | `shafinMultitool/Resources/Circle.usdz`; 60,847 bytes; SHA-256 `8099ec655334ebeb2a1bd078df6fbb725386cdd870d6c00cd56671f49ea8aa30`; archive contains `4646EE66-A797-4665-895A-1D353AE06283.usdc` (60,553 bytes; SHA-256 `46fa822816945b19076553d6ab5b3222127f086b1835aa726102c038f29630ec`). Git history adds the export in `24754f6a035f4d35b14fd27a9163056cce6580c2` (`UX changes`). | Runtime-loaded through dynamic `ModelEntity.loadModel(named: entityName)` with `entityName == "Circle"` and anchor names containing `Circle` in `CameraScreenInteractor.swift:131-141,450-515`; synchronized-root bundle candidate. | Repository-correlation evidence is verified by the offline validator: the RCFoundation project records scene object UUID `44109F70-2E63-4249-91FD-37EDDF809807`, primitive `cylinder`, and material `paintEnamelMatte`; the USDZ member contains the same UUID without hyphens and reports `com.apple.RCFoundation Vers` `1.5 (192.5)`. These hashes, metadata and Git co-change establish common repository observations only; they do not prove source-to-export causality. Git history, runtime lines and target boundary are human-reviewed annotations, not machine-verified. | No USDZ-side or resource-side license/notice/credits file. | No explicit creator/rights/permission declaration or redistribution approval; repository correlation is not legal clearance. | Local RealityKit asset; no network behavior. | 60,847 bytes source-tree payload; no accepted archive. | `missing` | Deterministic source-to-export recipe and explicit creator/rights declaration remain missing; source-to-export causality is not proven; legal/release owner decision remains blocked. Do not call Circle redistribution approved. | High for bytes and correlation predicates; human-reviewed for runtime/Git/target annotations; low for creator/rights/release decision. |
| Reality Composer project and thumbnails | `shafinMultitool/Resources/Circle.rcproject`; 615,735 bytes total. The record covers all five tracked material files, including `com.apple.RCFoundation.Project` SHA-256 `04c82cdd9506ec2fb0bb3a14ac8457f2e7c0a21f0acfa8d1d4d3ff8a3d693c8d`, `Version.json` SHA-256 `875afbac1f90283660316c2bd0f6f5c65751f6ee1bf49420308697e937add1d6`, and thumbnail SHA-256 values `344d6971e9314a7f2d8d0a4cf1040ea0ea6e57737f8c384ca28a4e588794ecaa` / `fb1dd7f8f9f88d231a3b50623e83318fe55128e9976171fe9dcf8df9d965071a`. | Tracked development artifact. `project.pbxproj:57-60,69-84` explicitly excludes it from target membership and Compile Sources. No `.rcproject` loader/reference was found; `Person`/`Circle` runtime paths use USDZ names instead. | Repository-correlation evidence with the exported USDZ is verified by the recorded object UUID, member hashes, RCFoundation/version metadata and offline predicates. This is common repository evidence only; source-to-export causality, deterministic export, creator and rights remain unproven. Git history and project membership are human-reviewed annotations; the validator checks their shape only. | No project-side license/notice/credits. | Explicit target exclusion is release-boundary evidence only; it is not a redistribution permission record or owner approval. | No network behavior; thumbnails are sample media. | 615,735 bytes source-tree payload; excluded from target by project configuration. | `non-shipping-development-only` | Preserve the explicit exclusion and archive assertion. Deterministic source-to-export recipe, explicit creator/rights declaration and causal export evidence remain missing; legal/release owner decision remains blocked if this project or export is reconsidered. | High for file/correlation/exclusion predicates; human-reviewed for Git/target annotations; low for creator/rights/release decision. |

### Scripts, datasets, templates, and synchronized-root sweep

| Component/family | Exact path; version/hash where observable | Runtime / bundle role | Source/origin evidence | License/notice evidence path | Redistribution status evidence | Network/privacy capability evidence | Measured bundle impact / accepted-bundle reference | Disposition | Blocker / follow-up | Confidence / evidence label |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Research scripts/data/templates outside the app target | `scripts/**`, `data/legacy/**`, `docs/**`, and `experiments/**` are repository research/development trees. The synchronized app-root sweep found no bundled `.py`, `.sh`, `.md`, `.csv`, `.yaml`, or template files; the only non-Swift app-root families are the Core ML packages, benchmark JSON/JSONL/images, asset catalogs, storyboard, USDZ, and Reality Composer files enumerated above. | Development and evaluation only; no project reference from these top-level research trees was found in `project.pbxproj`. README names legacy datasets and generation scripts, but they are outside the target root. | Local README/docs describe generation and evaluation roles; they do not establish a product redistribution right. | No complete top-level `LICENSE`, `NOTICE`, `COPYING`, or `CREDITS` file exists. | Not a current app-bundle payload by project membership evidence; do not treat this as approval to move any file into the app root. | Scripts may access local files/services when run by developers; no app runtime capability is assigned to them. | No app-root bundle bytes; final archive allowlist still required. | `non-shipping-development-only` | Release owner: enforce a synchronized-root allowlist and keep research trees outside target membership. Any future resource promotion must receive its own provenance row. | High for current project boundary; medium for future changes. |

## Acknowledgements, licenses, notices, and provenance coverage

The repository-wide search found only two license files: `Pods/ARVideoKit/LICENSE` and `Pods/SnapKit/LICENSE`. There is no root `LICENSE`, `NOTICE`, `COPYING`, or `CREDITS` file. `README.ru.md:369-371` explicitly says that the repository has no separate root license file. This is an evidence-of-absence statement, not a legal conclusion.

| Evidence artifact | Concrete local evidence | Component/family actually covered | Not covered / release implication |
| --- | --- | --- | --- |
| `Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.markdown` (12,626 bytes, SHA-256 `f2b2ed63362f5dd84bc8a6c450f797783f9fb85f4fa936041673fd1f859f2491`) and matching `.plist` (13,707 bytes, SHA-256 `e89aa94803834431bfcd323504551022d7f3f1abcc6125f19187261fc5df01d1`) | Generated CocoaPods entries for ARVideoKit and SnapKit; plist labels them `Apache 2.0` and `MIT`. | App pod target only. | Does not cover llama, Core ML, GGUF, benchmark media/data, asset catalogs, USDZ, or Reality Composer. Final app disclosure placement is not proven by a release archive. |
| `Pods/Target Support Files/Pods-shafinMultitoolTests/Pods-shafinMultitoolTests-acknowledgements.markdown` (1,240 bytes, SHA-256 `f90ca1e5afd9b40c4e4cee2a78a6e921761f2663362c5b5482f281278fd2bca0`) and `.plist` (2,113 bytes, SHA-256 `8e4fca8740c41c88ff0483d679cb7f65b33ec8c65ace4503352d96e370d08bbd`) | Generated test-target entry for SnapKit; plist labels it `MIT`. | Test target only. | It is not evidence for app-bundle coverage of models or media. |
| `Pods/ARVideoKit/LICENSE` and `Pods/ARVideoKit/README.md` | Local license text, pod README feature/capability text, and an App Store acknowledgement instruction. | ARVideoKit only. | No llama/Core ML/media coverage; no exact upstream commit in the lock. |
| `Pods/SnapKit/LICENSE` and `Pods/SnapKit/README.md` | Local license text and pod README. | SnapKit only. | No other dependency/model/media coverage. |
| `README.md:68-72,238-240,344-346` and `README.ru.md:66-70,237-238,343-371` | Project README claims bundled llama.cpp through `llama.xcframework`, lists CocoaPods dependencies, names model path checks, and records no root license file. | Project-level orientation only; not a notice or model permission record. | Does not identify the exact llama source commit, GGUF payload, Core ML source, benchmark rights, or asset provenance. |
| `docs/integrations/llama-cpp-integration.md` | Generic/older integration instructions mention cloning llama.cpp and a TinyLlama/Qwen workflow; no exact current binary source commit or current payload hash. | Historical development guidance for llama integration. | Must not be used as current redistribution evidence. |
| `docs/cameraanalysis/dataset/README.md:42-52` and source manifests under `docs/cameraanalysis/dataset/inbox/` | Source-policy categories and references to Apple TV Press/imagegen parent metadata; `unsplash_sources.jsonl` has source and `license_note` fields. | Research dataset provenance work outside the bundled camera pack. | Current app pack does not carry complete source/permission/privacy records; this evidence does not clear the pack for Release. |

No acknowledgement or notice file maps to `Frameworks/llama.xcframework`, either Core ML package, any GGUF, either DeviceBenchmark pack, the material asset images, either USDZ, or the Reality Composer project. These are explicit release blockers or exclusion decisions in the inventory above.

## Executable release blocker and disposition list

| Disposition | Families | Executable release action | Evidence/artifact required to close |
| --- | --- | --- | --- |
| `missing` | `llama.xcframework` | Stop Release approval for the binary until identity and notice scope are recorded. | Exact upstream repo/commit, build recipe, applicable license/NOTICE set, device/simulator hashes, and archive link/embed proof. |
| `missing` | `compact_neural_evidence_net`, DETR, NIMA | Supply provenance-cleared model packages or make an owner-approved replace/exclude decision and update their consumers. | Model source/checkpoint identity, conversion metadata, package/file hashes, notice/license evidence, and runtime verification for `CoreMLNeuralEvidenceProvider`, `DETRDetector`, and `AestheticScorer`. |
| `missing` | GGUF release candidate(s) | Do not ship a model merely because historical Release output contained one. | One selected payload, model header identity, SHA-256, source/model-card record, notice/license evidence, and final bundle or approved download design. |
| `exclude` | ARVideoKit | Remove the unconsumed pod from the Release dependency graph unless the owner documents a real consumer and capability need. | Regenerated pod/project state, no-link/no-embed proof, and updated app acknowledgement evidence. |
| `exclude` | Camera benchmark image pack | Keep all benchmark images and metadata out of Release. | Release archive scan showing absence; separate Debug harness scan showing intended pack only; if later shipped, per-family source/permission/privacy ledger and 41 missing hashes repaired. |
| `missing` | Material asset image/icon family; Person/Circle USDZ | Stop release approval for these media families until creator/source/permission provenance is documented or assets are replaced. Circle repository-correlation evidence is verified, but that does not clear its creator/rights or causal-export blocker. | Asset-level source/creation/export record, permission/attribution record, final hashes, and runtime/archive allowlist proof. |
| `non-shipping-development-only` | Scene generator benchmark pack; ignored local GGUF policy; `Circle.rcproject`; research scripts/data/templates | Keep outside the Release target/bundle and assert the boundary mechanically. | Release allowlist/archive scan and Debug/device-only harness proof. |
| `verified` | SnapKit; contents-only catalog + LaunchScreen scope | No provenance blocker in the stated repository scope; still verify final archive disclosure and target membership. | Final archive dependency/ack scan. |

## Exact follow-up task packet

These are handoff tasks, not changes made by this audit. Legal, product, privacy, and brand approval remain with their owners.

| Owner | Exact file/artifact needed | Action and acceptance evidence |
| --- | --- | --- |
| Release/dependency owner | `Podfile`, `Podfile.lock`, generated Pods support files, and a fresh Release archive | Confirm ARVideoKit is not a hidden/serialized consumer; remove it if unused; verify only SnapKit remains linked/embedded and that the app acknowledgement matches the final dependency graph. |
| LLM/framework owner | `Frameworks/llama.xcframework` plus a provenance record kept with the release process | Identify exact upstream source commit/version and build inputs; attach the complete applicable notice/license evidence; re-hash both slices; record the final archive role. |
| ML owner | Three model provenance packets for `compact_neural_evidence_net`, DETR, and NIMA | For each model, provide source/checkpoint identity, conversion tool/version/command, package and internal-file hashes, model-specific notice/license evidence, and a replace/exclude decision if any record cannot be completed. |
| LLM/release owner | One selected GGUF payload and its model metadata | Record exact file path, header identity, SHA-256, source/checkpoint/model-card evidence, notice/license evidence, and whether the payload is bundled or downloaded. Measure the final app impact. |
| Benchmark/privacy owner | `camera_device_benchmark_pack_v1` source ledger, image labels, source manifests, and Release/Debug archive scans | Exclude the camera pack from Release now; reconcile current 179-file snapshot with source manifests, fill 41 missing image hashes, and document source/permission/privacy/content review if any subset is reconsidered. |
| Benchmark owner | `scene_generator_device_pack_v1` generation/source ledger and target-membership proof | Keep the generated JSONL outside Release; preserve Debug/device harness access and record the generation inputs/source policy without treating the model name as redistribution evidence. |
| Product/brand owner | Per-file asset provenance record for `Resources/Assets.xcassets` | Identify creator/source, creation or permission record, and final approved icon/logo/background set; replace any unknown material before archive acceptance. |
| 3D asset owner | Export/provenance records for `Person.usdz`, `Circle.usdz`, and any future `Circle.rcproject` use | Circle's repository-correlation evidence, hashes and metadata are recorded; Git paths, runtime consumers and target boundary are human-reviewed annotations. Still provide the deterministic export recipe and explicit creator/permission/notice evidence. Complete the analogous source/export record for Person, and keep the rcproject excluded unless it becomes an intentional runtime input. |
| Release/CC-001 owner | Accepted `docs/implementation/audits/release-bundle-inventory.md` and a fresh signing-disabled Release archive | Measure actual `.app` membership and sizes, including synchronized-root resources, embedded frameworks, Core ML, GGUF, acknowledgements, and all media; publish an allowlist that matches this audit. |
| CC-011/release-gate owner | Reproducible CI/local scan script and archive assertions | Fail Release when unknown model/media/framework families, missing hashes, unexpected GGUF, benchmark packs, or missing acknowledgement coverage enter the bundle. |

## Unknowns that remain explicit

- No accepted release-bundle inventory or fresh Release archive exists at this starting commit; source-tree measurements cannot prove final archive membership.
- The synchronized-root project format can make many files bundle candidates, but only an archive scan can prove the actual path/name and compiled treatment.
- The exact upstream source commit/version and build recipe for the vendored llama binary are unknown.
- The default `compact_neural_evidence_net` artifact is absent; its intended weights and conversion provenance are unknown.
- The two present Core ML packages expose limited serialized metadata but no complete source/checkpoint/conversion/notice record.
- No GGUF exists in the clean worktree; the historical `STATUS.md` model size is not a current hash or proof of current bundle membership.
- Benchmark source metadata is split between research manifests and the current app pack. The app pack lacks 41 image hashes and does not establish per-family permission/privacy/content decisions.
- The creator/rights and redistribution status of all material app raster images/icons and both USDZ files are unknown. Circle's repository correlation is verified, but source-to-export causality, creator, permission, redistribution approval, and release readiness remain unproven.
- No root acknowledgement/license/notice document covers non-Pod components.
- The repository does not select a replacement model or asset; `replace` is intentionally unused rather than guessed.
- No external browsing, download, installation, paid service, tracker edit, or legal conclusion was used in this audit.

## Reproducible command appendix

Commands used or sufficient to reproduce the local evidence. Run from repository root; commands below do not require network access.

### Starting state and authority checks

```bash
git status --short --branch
git rev-parse HEAD
git log -1 --oneline
test ! -e docs/implementation/audits/release-bundle-inventory.md
git ls-files docs/app-store-product-plan.md docs/implementation/BACKLOG.md docs/implementation/STATUS.md Podfile Podfile.lock
```

Observed start: clean detached `HEAD`; `d40a4ec67e34260b77584a62f4efd76ccff41c6a`; `d40a4ec docs: accept privacy and test topology audits`; no accepted release-bundle inventory.

### Dependency, acknowledgement, and license evidence

```bash
sed -n '1,220p' Podfile.lock
rg -n 'ARVideoKit|SnapKit|frameworks|acknowledg|LICENSE|NOTICE' Podfile Podfile.lock 'Pods/Target Support Files' Pods/ARVideoKit Pods/SnapKit
find . -type f \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'NOTICE' -o -iname 'NOTICE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' -o -iname 'CREDITS' -o -iname 'CREDITS.*' \) -print | sort
for f in Pods/ARVideoKit/LICENSE Pods/SnapKit/LICENSE \
  'Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.markdown' \
  'Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.plist'; do
  stat -f '%z bytes %N' "$f"
  shasum -a 256 "$f"
done
plutil -p 'Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.plist'
```

### Synchronized target membership and consumers

```bash
rg -n 'PBXFileSystemSynchronizedRootGroup|membershipExceptions|explicitFolders|llama.xcframework' shafinMultitool.xcodeproj/project.pbxproj
find shafinMultitool -type f ! -name '*.swift' -print | sort
rg -n 'import ARVideoKit|RecordAR|RenderAR|import SnapKit|compact_neural_evidence_net|DETRResnet|aesthetic_nima|\.gguf|ModelEntity\.loadModel|Circle\.rcproject|Person|Circle' shafinMultitool shafinMultitoolTests scripts --glob '*.swift' --glob '*.py'
```

### Hashes and package metadata

```bash
find Frameworks/llama.xcframework -type f -print0 | sort -z | xargs -0 -n1 shasum -a 256
file Frameworks/llama.xcframework/ios-arm64/llama.framework/llama
file Frameworks/llama.xcframework/ios-arm64_x86_64-simulator/llama.framework/llama
plutil -p Frameworks/llama.xcframework/Info.plist
plutil -p Frameworks/llama.xcframework/ios-arm64/llama.framework/Info.plist
find shafinMultitool/Multitool2Module/Models/CoreML -type f -print0 | xargs -0 -n1 shasum -a 256
find shafinMultitool/Multitool2Module/Models/CoreML/DETRResnet50SemanticSegmentationF16P8.mlpackage -type f -print0 | sort -z | xargs -0 -n1 shasum -a 256 | shasum -a 256
find shafinMultitool/Multitool2Module/Models/CoreML/aesthetic_nima_mobilenet_fp16.mlpackage -type f -print0 | sort -z | xargs -0 -n1 shasum -a 256 | shasum -a 256
find shafinMultitool/Resources/DeviceBenchmark -type f -print0 | sort -z | xargs -0 -n1 shasum -a 256
find shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1 -type f -print0 | sort -z | xargs -0 -n1 shasum -a 256 | shasum -a 256
find shafinMultitool/Resources/DeviceBenchmark/scene_generator_device_pack_v1 -type f -print0 | sort -z | xargs -0 -n1 shasum -a 256 | shasum -a 256
for f in shafinMultitool/Resources/Person.usdz shafinMultitool/Resources/Circle.usdz; do
  file "$f"
  stat -f '%z bytes %N' "$f"
  shasum -a 256 "$f"
  unzip -l "$f"
done
```

### Benchmark counts and image-hash consistency

```bash
for f in shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/*labels.jsonl; do
  jq -s '{rows:length, keys:(.[0]|keys), source_dataset_counts:(group_by(.source_dataset)|map({key:.[0].source_dataset,count:length})), review_status_counts:(group_by(.review_status)|map({key:.[0].review_status,count:length}))}' "$f"
done
for f in shafinMultitool/Resources/DeviceBenchmark/scene_generator_device_pack_v1/*.jsonl; do
  jq -s '{rows:length, keys:(.[0]|keys), model_names:(map(.model_name)|unique), source_policy_versions:(map(.source_policy_version)|unique), contract_versions:(map(.contract_version)|unique), validation_statuses:(map(.validation_status)|unique)}' "$f"
done
python3 - <<'PY'
import hashlib, json, pathlib
root = pathlib.Path('shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1')
for name in ('camera_full_labels.jsonl', 'camera_quick_labels.jsonl'):
    rows = [json.loads(line) for line in (root / name).read_text().splitlines() if line]
    missing = wrong = matching = 0
    for row in rows:
        expected = row.get('sha256')
        actual = hashlib.sha256((root / row['image_path']).read_bytes()).hexdigest()
        if not expected:
            missing += 1
        elif expected == actual:
            matching += 1
        else:
            wrong += 1
    print(name, rows.__len__(), matching, missing, wrong)
PY
```

Expected consistency result: full labels `174 rows, 139 matching, 35 missing_sha256, 0 wrong_nonnull_sha256`; quick labels `24 rows, 18 matching, 6 missing_sha256, 0 wrong_nonnull_sha256`.

### Final verification after the single commit

```bash
git diff --check
git status --short
git add docs/implementation/audits/dependency-provenance-inventory.md
git commit -m 'docs: inventory dependency and media provenance'
git diff --check d40a4ec67e34260b77584a62f4efd76ccff41c6a HEAD
git diff --name-only d40a4ec67e34260b77584a62f4efd76ccff41c6a HEAD
git show --stat --oneline --summary HEAD
git status --short
```

Acceptance result must be exactly one changed path from the starting commit: `docs/implementation/audits/dependency-provenance-inventory.md`; the final worktree must be clean, with no push or PR.
