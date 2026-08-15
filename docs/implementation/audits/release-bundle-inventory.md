# CC-001 release-bundle inventory

## Scope and evidence status

This is a read-only inventory of the material contributors that can enter the
`shafinMultitool` application bundle. No project, source, resource, build
setting, or dependency file was changed.

The evidence labels below distinguish what this checkout proves:

- **Measured** — observed with `du`, `find`, or the partial product output.
- **Observed** — present in project/runtime metadata or source references.
- **Declared** — recorded by an existing implementation document, not
  independently reproducible in this checkout.
- **Inferred** — a conditional path or consequence of the observed build
  structure.
- **Unknown** — the repository does not establish the fact; no legal or
  product conclusion is made.

Product authority remains `docs/app-store-product-plan.md`. It keeps Camera
Coach primary and Scene Mode secondary/preserved; it does not establish that
research benchmark data or a particular model file may be redistributed.
`docs/implementation/BACKLOG.md` CC-001 and
`docs/implementation/STATUS.md` were used as execution evidence only.

## Executive disposition

The proposed Release contract is:

| Contributor | Current evidence | Proposed disposition |
|---|---|---|
| `dataset_v9_event_sft_q4_k_m.gguf` | **Worker checkout:** absent because it is ignored by `.gitignore`. **Parent-supplied, independently reproduced acceptance evidence:** present in the primary developer checkout at 1,094,912 KB and copied to the partial app. | **EXCLUDE FROM Release regardless of checkout contamination; ON-DEMAND only for explicitly supported Debug/device flows.** `.gitignore` is not a Release boundary. |
| `Resources/DeviceBenchmark/camera_device_benchmark_pack_v1` | **Measured** 36,760 KB, 179 files; its files are copied to the partial app root as part of a 52,072 KB flattened benchmark contribution. | **EXCLUDE FROM Release; KEEP for the existing Debug/device harness through a Debug-only input or test artifact.** |
| `Resources/DeviceBenchmark/scene_generator_device_pack_v1` | **Measured** 15,312 KB, 3 JSONL/manifest files; flattened into the same 52,072 KB partial-app contribution. | **EXCLUDE FROM Release; KEEP for the existing Debug/device harness through a Debug-only input or test artifact.** |
| Core ML packages | **Measured** 48,440 KB source; 48,532 KB as two compiled `.mlmodelc` bundles in the partial app. DETR is a hard bundle lookup; aesthetic scoring is an optional/soft lookup. | **KEEP in Release and Debug.** |
| `Assets.xcassets` | **Measured** 2,504 KB source and 2,296 KB `Assets.car`; `background.png` alone is 1,864 KB. | **KEEP in Release and Debug.** |
| `Frameworks/llama.xcframework` | **Measured** 14,252 KB for both slices; 4,684 KB device framework output. | **KEEP the device runtime framework** while local Scene Mode parsing remains product scope; this is the small runtime, not the GGUF payload. |
| `ARVideoKit`, `SnapKit`, generated Pods framework | **Observed/Measured** Release products of 1,340 KB, 912 KB, and 20 KB respectively. | **KEEP as current link/embed dependencies.** |
| `Circle.usdz`, `Person.usdz` | **Measured** 60 KB and 404 KB; both enter through synchronized-root membership. No direct current source reference was found. | **EXCLUDE from Release on current source evidence; retain in the repository until the Scene Mode owner proves a runtime/serialized dependency.** |
| `Circle.rcproject` | **Observed** as a synchronized-group membership exception and not present in the partial app. | **KEEP excluded from the app target.** No change was made. |

The most important result is that the approximately 1.0 GB GGUF and the
approximately 51 MB benchmark packs have different statuses, and that the
GGUF is not safe to classify as merely absent: the clean worker checkout has no
ignored payload, but the parent’s developer checkout reproduced the payload
being copied automatically by synchronized-root membership. CC-002 therefore
needs a deterministic Release allowlist/exclusion boundary that produces the
same result whether the ignored local file exists or not.

## Why the current target bundles these files

The app target is `CFF7B20329CC876400C3B73E` in
`shafinMultitool.xcodeproj/project.pbxproj`.

1. `CF37407A2EC890C80005765D` is a `PBXFileSystemSynchronizedRootGroup`
   rooted at `shafinMultitool` (project file lines 75–87).
2. That group is attached to the app target at lines 198–200.
3. The target Resources phase `CFF7B20229CC876400C3B73E` has an empty explicit
   `files` list (lines 252–258). Therefore, an empty Resources phase does not
   mean that the resource directory is empty.
4. The only current synchronized build-file exceptions are `Info.plist` and
   `Resources/Circle.rcproject` (`CF3740C22...`, lines 54–62). The compile
   source exception also names `Resources/Circle.rcproject`
   (`CF3740C32...`, lines 65–72). There is no exception for `DeviceBenchmark`,
   `Resources/Models`, or either Core ML package.
5. The Debug and Release target configurations both use this same target
   membership. Release is `CFF7B21929CC876500C3B73E` and inherits
   `Pods-shafinMultitool.release.xcconfig` (lines 535–567); there is no
   configuration-specific resource allowlist in the current project.

This synchronized-group behavior is the owner-level control point for the
next mechanical implementation task. The target IDs and paths above are
enough to change membership without rediscovering the resource graph. The
implementation must preserve Debug harness availability while making the
Release output satisfy the disposition contract; this audit does not choose or
apply the project-file mechanism.

## Parent-supplied contaminated-checkout evidence

The following evidence was supplied by the Sol parent after independently
reproducing the same build in the primary developer checkout. It was **not
observed in this worker worktree** and is intentionally kept separate from the
worker measurements above.

- The primary checkout contained the ignored local file
  `shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf`.
- The exact parent command was:

  ```text
  xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/shafin-cc001-parent-release-derived CODE_SIGNING_ALLOWED=NO build
  ```

- The parent build also exited 65 with the same six
  `DeviceBenchmarkCoordinator.swift:465/499` errors documented below. It did
  not produce a clean Release app/archive.
- Parent-supplied partial-app measurements:

  | Parent partial-product item | `du -sk` |
  |---|---:|
  | `/private/tmp/shafin-cc001-parent-release-derived/Build/Products/Release-iphoneos/shafinMultitool.app` | 1,198,316 KB |
  | `dataset_v9_event_sft_q4_k_m.gguf` at the copied app root | 1,094,912 KB |
  | Remaining partial-app content | 103,404 KB |

- The parent partial app path for the copied payload was
  `/private/tmp/shafin-cc001-parent-release-derived/Build/Products/Release-iphoneos/shafinMultitool.app/dataset_v9_event_sft_q4_k_m.gguf`.
- The parent also independently observed `Assets.car`,
  `core_accepted_source.jsonl`, and `hard_accepted_source.jsonl` over 1 MB in
  that partial product. The worker’s 103,404 KB partial-app total and the
  parent’s non-GGUF remainder are exactly equal; this is an independent
  cross-check of the contamination delta, not a claim that the worker saw the
  parent file.

This evidence changes the Release risk classification: an ignored developer
file is a release determinism/security boundary failure when synchronized-root
membership copies it. CC-002 must prevent the file from entering Release by
project/configuration membership or an equivalent explicit allowlist, and must
verify both a clean tracked checkout and a contaminated developer checkout.

## Detailed inventory

### 1. GGUF model payload — external/on-demand

- **Source path:** `shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf`
  is the expected path in `scripts/run_open_domain_scene_benchmark.py:23` and
  the fallback path in `shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:1386–1390`.
  In the clean worker checkout, `find . -iname '*.gguf'` returned no file
  because `.gitignore:4–5` excludes large GGUF files. The parent independently
  reproduced the same path as a developer-local ignored file.
- **Built path:** none was observed in the clean worker product. Parent-supplied
  acceptance evidence observed the copied file at
  `/private/tmp/shafin-cc001-parent-release-derived/Build/Products/Release-iphoneos/shafinMultitool.app/dataset_v9_event_sft_q4_k_m.gguf`.
- **Size:** clean worker measurement is unavailable because the file is absent.
  Existing `STATUS.md` declares approximately 1.0 GB; the parent-supplied
  independent measurement is **1,094,912 KB** (approximately 1.04 GiB).
- **Why it enters:** the synchronized root can make a local file eligible for
  resource copying. Scene Generator runtime then looks for `.gguf` recursively
  in `Bundle.main`, all bundles, and all frameworks
  (`shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift:2313–2360`);
  the device benchmark resolver also checks the direct bundle paths and the
  `SG_LIVE_MODEL_PATH` environment override
  (`DeviceBenchmarkCoordinator.swift:1356–1397`).
- **Debug necessity:** required only when running the local Scene Generator or
  the Scene Generator device benchmark. The existing explicit override routes
  are `SG_LIVE_MODEL_PATH` and UserDefaults key
  `scene_generator_llm_model_path`.
- **Release necessity:** not needed to compile/link the app or to preserve the
  Camera Coach path. It is needed only if Release is expected to ship the
  local Scene Generator model already installed. Product authority does not
  require a bundled GGUF, and parent evidence proves that relying on file
  absence is insufficient.
- **Provenance/license:** no file, checksum, license, or redistribution grant
  can be inspected because the payload is absent. Historical model names in
  old documents are not treated as current authority.
- **Disposition:** **EXCLUDE FROM Release regardless of whether the ignored
  local file exists; ON-DEMAND only for explicitly supported Debug/device
  benchmark flows.** The next implementation should download or otherwise
  provision a model into an app support/cache location, set the existing
  override for benchmark/debug use, and retain a clear unavailable-model
  state. It must make Release resource membership deterministic rather than
  relying on `.gitignore`, the developer’s checkout contents, or an absent
  file.
- **Owner/build reference:** `CF37407A...` synchronized root; target
  `CFF7B203...`; script line 23; coordinator lines 1356–1397; parser lines
  2313–2360.
- **Risk:** retaining the payload makes the partial Release product about 1.2
  GB and allows developer-local data to cross the release boundary. Excluding
  the bundled fallback without provisioning a replacement makes local Scene
  Mode and the Scene Generator benchmark fail with the existing “GGUF model
  not found”/“Could not resolve scene generator runtime model” errors. A
  download policy, endpoint, cache lifetime, size budget, checksum, and legal
  provenance remain open decisions.

### 2. Camera device benchmark pack

- **Source path:** `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1`.
- **Built path:** the partial product contains the pack as flattened files at
  `<partial-app>.app/` (for example `001.jpg`, `camera_full_labels.jsonl`,
  `live_sequences.json`, and `guided_live_scenarios.json`), not as a
  `DeviceBenchmark/camera_device_benchmark_pack_v1` directory. Runtime copies
  them to `Library/Caches/DeviceBenchmark/<run-id>/packs/camera_device_benchmark_pack_v1/`.
  `DeviceBenchmarkSupport.swift:330–363` first searches nested bundle paths,
  then `:424–432` resolves direct bundle filenames, which explains the
  flattened fallback.
- **Size:** **Measured** 36,760 KB and 179 files at source, including 174
  image files and five manifest/label/sequence files. The combined flattened
  benchmark contribution in the partial app is 52,072 KB across 182 files;
  the output has no directory boundary with which to independently `du` the
  camera subset.
- **Why it enters:** all files are under the synchronized root and are not in
  `membershipExceptions`. The default benchmark configuration names this pack
  at `DeviceBenchmarkSupport.swift:92–107`.
- **Debug necessity:** required by the existing camera still/live replay
  harness. The runtime prepares a cache copy and reads the camera labels and
  images (`DeviceBenchmarkSupport.swift:381–410`; coordinator
  `DeviceBenchmarkCoordinator.swift:450–515`).
- **Release necessity:** not required by the product path. It is evaluation
  data, not user-facing Camera Coach content. A Release benchmark run, if ever
  required, should receive a separately provisioned test artifact rather than
  changing the App Store bundle.
- **Provenance/license:** the label records contain source buckets, source
  datasets, SHA-256 values, review status, and label-source metadata such as
  `codex_visual_contact_sheet_review_2026-05-21`. They do not establish a
  license, permission to redistribute, or App Store clearance. Some records
  identify curated inbox material and public/promo candidates. Status:
  **provenance metadata present; redistribution status unknown**.
- **Disposition:** **EXCLUDE FROM Release; KEEP for Debug/device benchmarking**
  through a Debug-only resource/test-artifact path. Do not delete or rename the
  source pack in this audit.
- **Owner/build reference:** synchronized root `CF37407A...`; target
  `CFF7B203...`; pack IDs in `DeviceBenchmarkSupport.swift:101–102` and
  preparation logic at lines 330–432.
- **Risk:** retaining this pack in Release adds roughly 36 MB, creates
  provenance/privacy review exposure for user-curated imagery, and makes the
  app bundle look like a test-data distribution. Excluding it without a Debug
  input path breaks the existing device harness.

### 3. Scene Generator device benchmark pack

- **Source path:** `shafinMultitool/Resources/DeviceBenchmark/scene_generator_device_pack_v1`.
- **Built path:** flattened files at `<partial-app>.app/`, specifically
  `core_accepted_source.jsonl`, `hard_accepted_source.jsonl`, and
  `scene_generator_device_benchmark_manifest.json`. Runtime copies them to
  `Library/Caches/DeviceBenchmark/<run-id>/packs/scene_generator_device_pack_v1/`.
- **Size:** **Measured** 15,312 KB and three files. The two large contributors
  are `core_accepted_source.jsonl` at 7,272 KB and
  `hard_accepted_source.jsonl` at 8,036 KB; the manifest is smaller. Together
  with the camera pack, the source/output benchmark family is 52,072 KB.
- **Why it enters:** synchronized-root membership; the default configuration
  names the pack at `DeviceBenchmarkSupport.swift:101–102`, and the static file
  list is at lines 413–421.
- **Debug necessity:** required for the existing Scene Generator device
  benchmark; it is copied to the run cache before evaluation.
- **Release necessity:** not required by the App Store product path. The pack
  contains accepted research/evaluation records, not a user-facing runtime
  dataset.
- **Provenance/license:** records contain generation/validation metadata and
  accepted status, but no redistribution license or App Store clearance was
  found in the pack. Status: **research provenance visible; redistribution
  status unknown**.
- **Disposition:** **EXCLUDE FROM Release; KEEP for Debug/device benchmarking**
  through a Debug-only resource/test-artifact path. Do not delete the source.
- **Owner/build reference:** synchronized root `CF37407A...`; target
  `CFF7B203...`; pack preparation at `DeviceBenchmarkSupport.swift:330–421`.
- **Risk:** retaining it adds roughly 15 MB and exposes generated research
  text/data in the shipped bundle. Excluding it without a Debug input path
  breaks Scene Generator benchmark preparation.

### 4. DETR Core ML package

- **Source path:** `shafinMultitool/Multitool2Module/Models/CoreML/DETRResnet50SemanticSegmentationF16P8.mlpackage`.
  The `weights/weight.bin` is 41,748 KB; the whole package is 42,084 KB.
- **Built path:** `<app>.app/DETRResnet50SemanticSegmentationF16P8.mlmodelc`.
- **Size:** source **Measured** 42,084 KB; partial Release product
  **Measured** 42,160 KB.
- **Why it enters:** synchronized-root membership and automatic Core ML
  package compilation. `DETRDetector.swift:56–60` requires the compiled model
  from `Bundle.main` and throws if it is absent.
- **Debug necessity:** required for the current detector path.
- **Release necessity:** **required** for current user-visible detector
  behavior; no remote/download fallback is evidenced.
- **Provenance/license:** the Core ML manifest identifies the container author
  as `com.apple.CoreML`, which describes the format, not model ownership.
  Embedded model metadata names DETR, links the original paper, and states
  “Apache 2” with a link to the Facebook DETR model. No complete local NOTICE
  or license bundle was found. This is partial evidence, not legal clearance.
- **Disposition:** **KEEP in Release and Debug.** Any future replacement must
  preserve the exact bundle resource name or update the wrapper and tests in a
  separate authorized change.
- **Owner/build reference:** synchronized root `CF37407A...`; target
  `CFF7B203...`; runtime consumer
  `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift:56–60`.
- **Risk:** exclusion causes detector initialization to throw at runtime.
  Provenance/notice completeness remains a release gate.

### 5. Aesthetic NIMA Core ML package

- **Source path:** `shafinMultitool/Multitool2Module/Models/CoreML/aesthetic_nima_mobilenet_fp16.mlpackage`.
  The `weights/weight.bin` is 6,268 KB; the whole package is 6,356 KB.
- **Built path:** `<app>.app/aesthetic_nima_mobilenet_fp16.mlmodelc`.
- **Size:** source **Measured** 6,356 KB; partial Release product
  **Measured** 6,372 KB.
- **Why it enters:** synchronized-root membership and Core ML compilation.
  `AestheticScorer.swift:18–22` searches `Bundle.main` for the compiled
  resource and creates the Vision model when found.
- **Debug necessity:** preserves the current aesthetic scoring path.
- **Release necessity:** current code treats absence as a soft/optional model
  state, but keeping it preserves the existing feature behavior and avoids an
  unrequested product change.
- **Provenance/license:** the Core ML manifest again only identifies the
  container format. Embedded strings identify NIMA/MobileNet and conversion
  tooling (`tensorflow==2.20.0`, Core ML Tools 8.3.0), but no model license or
  redistribution grant was found. Status: **license unknown**.
- **Disposition:** **KEEP in Release and Debug**, pending a separate model
  provenance/notice decision.
- **Owner/build reference:** synchronized root `CF37407A...`; target
  `CFF7B203...`; consumer
  `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift:18–22`.
- **Risk:** exclusion silently disables the scorer rather than necessarily
  failing startup; shipping without licensing evidence remains a release risk.

### 6. Asset catalog

- **Source path:** `shafinMultitool/Resources/Assets.xcassets`.
  `background.imageset/background.png` is 1,864 KB; the catalog is 2,504 KB
  total.
- **Built path:** `<app>.app/Assets.car`.
- **Size:** source **Measured** 2,504 KB; partial Release product **Measured**
  2,296 KB.
- **Why it enters:** synchronized-root membership plus the Release/Debug
  asset settings `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor` in the target
  configurations. `logo_menu` is loaded by
  `ScenesOverviewModule/SOViewController.swift:70`.
- **Debug/Release necessity:** **KEEP in both**; app icon, accent, and current
  UI assets are product resources.
- **Provenance/license:** no asset-specific license metadata was found in the
  catalog. Status: **unknown**, without a claim about ownership.
- **Disposition:** **KEEP in Release and Debug.**
- **Owner/build reference:** synchronized root `CF37407A...`; target
  configurations `CFF7B218...` and `CFF7B219...`; asset compiler settings at
  `project.pbxproj:500–567`.
- **Risk:** excluding the catalog removes required app branding/UI assets.

### 7. `llama.xcframework` device runtime

- **Source path:** `Frameworks/llama.xcframework`. The source bundle is
  **Measured** 14,252 KB: device arm64 binary 4,420 KB and simulator binary
  9,300 KB, plus framework metadata. The generic iOS device build selects the
  `ios-arm64` slice.
- **Built path:** expected `<app>.app/Frameworks/llama.framework/llama`;
  the failed build produced the device framework product at
  `/private/tmp/cc001-release-derived/Build/Products/Release-iphoneos/llama.framework/llama`
  at **Measured** 4,684 KB. It was not copied into the partial app because
  compilation stopped before the final embed phase.
- **Why it enters:** explicit project references
  `CF3345CB2F6438AC0017F85F` (file reference),
  `CF3345CC2F6438AC0017F85F` (Frameworks phase), and
  `CF3345CD2F6438AC0017F85F` (Embed Frameworks with `CodeSignOnCopy` and
  `RemoveHeadersOnCopy`); embed phase `CF3345CE2F6438AC0017F85F` targets the
  app Frameworks directory.
- **Debug necessity:** required to compile and run the local Scene Generator
  path.
- **Release necessity:** keep while product scope preserves local Scene Mode
  parsing. The framework is a runtime dependency; the large model payload is
  the separate GGUF and is not part of this framework.
- **Provenance/license:** `Info.plist` identifies bundle ID `org.ggml.llama`
  and minimum OS 16.4. No license/NOTICE file was found under the XCFramework;
  redistribution status is **unknown**.
- **Disposition:** **KEEP the device slice in Release and Debug** while the
  existing `LlamaContext`/`LLMParserService` path remains. Exclude only the
  unused simulator slice from the device bundle as Xcode already does.
- **Owner/build reference:** `project.pbxproj:9–14, 27–38, 41–46, 103–113`;
  `SceneGeneratorModule/Services/LlamaContext.swift:9` imports `llama`.
- **Risk:** excluding it breaks link/load for local Scene Mode. Unknown license
  status is a separate shipping gate.

### 8. CocoaPods dependency bundles

- **Source/build references:** `Podfile:5–12` declares `ARVideoKit ~> 1.5.51`
  and `SnapKit ~> 5.6.0`. `Podfile.lock` records those exact versions and
  checksums. Release xcconfig adds framework search paths and
  `OTHER_LDFLAGS = ... -framework "ARVideoKit" -framework "SnapKit"`; the
  `[CP] Embed Pods Frameworks` phase is `430CDBAEF84F01F44B60348F`.
- **Built paths and sizes:** expected embedded paths are
  `<app>.app/Frameworks/ARVideoKit.framework` and
  `<app>.app/Frameworks/SnapKit.framework`. The failed Release build produced
  the framework products at `Build/Products/Release-iphoneos/ARVideoKit/` and
  `.../SnapKit/` at **Measured** 1,340 KB and 912 KB; the generated
  `Pods_shafinMultitool.framework` product was 20 KB. They were not embedded in
  the partial app because compilation stopped before the final app phase.
- **Debug/Release necessity:** **KEEP in both** as current link/embed
  dependencies; this inventory does not authorize pod changes.
- **Provenance/license:** ARVideoKit includes an Apache 2.0 `LICENSE`; SnapKit
  includes an MIT license. The generated acknowledgements file contains both
  notices. Whether the final App Store metadata presents the notices as
  required is not verified here.
- **Disposition:** **KEEP**; no dependency removal is proposed.
- **Risk:** removing either framework causes link/runtime failures. Notice
  presentation must be verified separately.

### 9. USDZ and Reality Composer resources

- **Source paths and sizes:** `shafinMultitool/Resources/Circle.usdz` is 60 KB;
  `shafinMultitool/Resources/Person.usdz` is 404 KB. They are below the 1 MB
  threshold but are included here because CC-001 explicitly requests USDZ and
  Reality Composer inspection. `shafinMultitool/Resources/Circle.rcproject`
  is present in the source tree but is a synchronized membership exception.
- **Built paths:** the partial product contains
  `<app>.app/Circle.usdz` (60 KB) and `<app>.app/Person.usdz` (404 KB); it does
  not contain `Circle.rcproject`.
- **Why they enter:** the two USDZ files are under the synchronized root and
  are not excluded. No direct `Circle.usdz`/`Person.usdz` source reference was
  found; the current project file explicitly excludes only the `.rcproject`.
- **Debug/Release necessity:** no current direct runtime consumer was
  evidenced. They are therefore not proven necessary for either configuration.
- **Provenance/license:** no source/license metadata was found. Status:
  **unknown**.
- **Disposition:** **EXCLUDE from Release on current source evidence; retain in
  the repository until a Scene Mode owner proves a dynamic or serialized
  dependency.** Keep `Circle.rcproject` excluded as it is now. This is a
  bundle-ownership recommendation, not a product decision to remove Scene
  Mode.
- **Risk:** an unsearched serialized/dynamic reference could make a Scene Mode
  asset unavailable. The next implementation must run the existing Scene Mode
  smoke path before enforcing this exclusion.

## Reconciliation of the partial Release products

Neither Release build completed, but Xcode copied resources before the
compiler failed. Both partial products are evidence of resource membership,
not valid Release apps/archives.

### Clean worker checkout: GGUF absent

Measured resource subtotal in the clean worker product at
`/private/tmp/cc001-release-derived/Build/Products/Release-iphoneos/shafinMultitool.app`:

| Partial-app contributor | `du -sk` |
|---|---:|
| Flattened DeviceBenchmark files, 182 files | 52,072 KB |
| `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | 42,160 KB |
| `aesthetic_nima_mobilenet_fp16.mlmodelc` | 6,372 KB |
| `Assets.car` | 2,296 KB |
| `Circle.usdz` + `Person.usdz` | 464 KB |
| **Resource subtotal** | **103,364 KB** |
| Partial `.app` total (`du -sk`) | **103,404 KB** |
| Unattributed residual metadata/partial bundle overhead | **40 KB** |

The 103,364 KB subtotal exactly reconciles with the measured 103,404 KB
partial app to within the 40 KB residual. The partial app contained 198 files,
no `shafinMultitool` executable, and an empty `Frameworks` directory. Separate
Release framework products were measured but not counted in that partial-app
subtotal: `llama.framework` 4,684 KB, `ARVideoKit.framework` 1,340 KB,
`SnapKit.framework` 912 KB, and `Pods_shafinMultitool.framework` 20 KB.

The GGUF is deliberately not added to this worker subtotal because it is absent
from the clean checkout.

### Parent-supplied primary checkout: ignored GGUF copied

The parent-supplied, independently reproduced primary-checkout evidence is:

| Parent partial-app item | `du -sk` |
|---|---:|
| `/private/tmp/shafin-cc001-parent-release-derived/Build/Products/Release-iphoneos/shafinMultitool.app` | 1,198,316 KB |
| `dataset_v9_event_sft_q4_k_m.gguf` copied into that app | 1,094,912 KB |
| Parent partial-app remainder after GGUF | 103,404 KB |

The parent remainder equals the worker partial-app total exactly:

```text
1,198,316 KB - 1,094,912 KB = 103,404 KB
```

This is the critical contamination delta. It proves that the ignored local
file is automatically copied by the synchronized root in a primary Release
build attempt and that the resulting partial app is approximately 1.2 GB.
The parent also observed `Assets.car`, `core_accepted_source.jsonl`, and
`hard_accepted_source.jsonl` over 1 MB in that partial app. Those observations
are parent-supplied and are not relabeled as worker measurements.

## Exact handoff contract for the implementation task

The next task can be mechanical against the following contract:

1. Preserve the existing `CF37407A...` synchronized source root and all source
   files. Change only target resource membership/configuration behavior as
   authorized by the primary.
2. For **Release**, the bundle manifest must contain the two Core ML compiled
   models, `Assets.car`, any explicitly proven product USDZ resources, the
   device `llama.framework`, and the current CocoaPods frameworks. It must not
   contain any `*.gguf` or any file from either `Resources/DeviceBenchmark`
   pack, **whether or not an ignored developer-local GGUF exists in the
   checkout**. The absence of the file in a clean checkout is not sufficient
   evidence.
3. For **Debug/device benchmark**, preserve access to both pack IDs and the
   existing flattened/nested lookup behavior. The harness currently enters
   only when `DEVICE_BENCHMARK_CONFIG_BASE64` is present in `SceneDelegate` and
   prepares cache copies in `DeviceBenchmarkSupport.swift`; do not broaden the
   harness into the product path.
4. For the GGUF, use the existing `SG_LIVE_MODEL_PATH` and
   `scene_generator_llm_model_path` override paths for a provisioned local
   file. Do not create a Release resource dependency on the ignored source
   path. The implementation must define download failure, cache location,
   version/checksum, and provenance separately; none is established by this
   audit. A Release membership test must run once with the ignored local file
   absent and once with it present, and must produce the same no-GGUF result.
5. Keep the direct Core ML bundle names unchanged unless the corresponding
   wrapper and tests are updated in a separate task. Keep the explicit llama
   framework embed phase and the current Pods embed phase.
6. Before accepting the implementation, run both a Debug harness check and a
   clean generic-device Release build/archive-equivalent. Inspect the final
   `.app` with `find`/`du`, assert no `.gguf` and no benchmark-pack files are
   present, assert the required Core ML/framework/assets are present, and
   record the final bundle total. Repeat the Release resource assertion from a
   developer checkout containing the ignored 1,094,912 KB GGUF; the result
   must remain identical. A build-for-testing or either failed build above is
   not a clean Release archive claim.
7. Clear model, benchmark-data, USDZ, llama, and model-conversion provenance
   and notice obligations before App Store submission. This report records
   evidence gaps; it does not make legal determinations.

## Verification record

### Required Release build

Command run exactly:

```text
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/cc001-release-derived CODE_SIGNING_ALLOWED=NO build
```

Result: **exit 65; no `BUILD SUCCEEDED`**. The baseline source blocker is:

```text
shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:465:41: error: value of type 'AnalysisPipeline' has no member 'testingReplayStillImageForSemanticEval'
shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:469:41: error: cannot infer contextual base in reference to member 'up'
shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:471:41: error: cannot infer contextual base in reference to member 'fullRuntime'
shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:499:49: error: value of type 'AnalysisPipeline' has no member 'testingReplayStillImageForSemanticEval'
shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:503:49: error: cannot infer contextual base in reference to member 'up'
shafinMultitool/Benchmark/DeviceBenchmarkCoordinator.swift:505:49: error: cannot infer contextual base in reference to member 'fullRuntime'
```

Parent-supplied independent verification used the primary checkout and this
exact command:

```text
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/shafin-cc001-parent-release-derived CODE_SIGNING_ALLOWED=NO build
```

It also exited 65 with the same errors at `DeviceBenchmarkCoordinator.swift`
465/469/471/499/503/505. Before that failure, the parent partial app measured
1,198,316 KB and contained the ignored GGUF at its app root at 1,094,912 KB.
This is acceptance evidence supplied by the parent, not a worker-observed
success or a clean Release result.

No source fix was attempted. Because the compiler failed, this report makes no
clean Release archive claim. `xcodebuild -list`/`-showBuildSettings` also
returned `xcodebuild: error: 'shafinMultitool.xcworkspace' is not a workspace
file` during follow-up inspection, so project settings were verified directly
from `project.pbxproj`, the workspace XML, the Pods xcconfig, and the partial
product instead.

### Other checks

- `find`/`du` inspection covered synchronized resources, both DeviceBenchmark
  pack families, Core ML packages and individual weight files, the asset
  catalog and largest image, the llama XCFramework slices, USDZ/Reality
  Composer files, and CocoaPods framework products.
- `find . -iname '*.gguf'` returned no file; the absent model is not silently
  counted in the clean-worker bundle totals. Parent-supplied evidence proves
  the same ignored path is copied when present in the primary checkout.
- The current checkout started clean at detached `HEAD`, so the report’s only
  intended change is this file. `git diff --check` and the final path-only diff
  check are required after writing it and before the scoped commit.

## Judgment calls and gaps

- The Release exclusion of both benchmark packs is a bundle disposition, not a
  deletion or a product/legal decision. Debug/test provisioning remains
  required.
- The GGUF is classified as **Release-excluded regardless of local checkout
  contents**, with download/on-demand reserved for explicitly supported
  Debug/device flows. The repository says to download ignored GGUF files
  separately and the runtime already supports explicit paths. Download URL,
  checksum, version policy, storage policy, and license are unresolved.
- USDZ files are classified as Release exclusions only because no current
  source reference was found. A Scene Mode dynamic/serialized reference would
  change their disposition to KEEP and must be checked before implementation.
- Core ML and llama artifacts have incomplete local provenance/license evidence;
  the partial DETR metadata is not a substitute for a full notice review.
- The required Release build is blocked by the pre-existing compile errors
  above. The partial resource product proves membership and reconciles its
  resource subtotal, but cannot prove executable linkage, signing, archive
  size, or final embedded frameworks. Parent evidence adds the contaminated
  checkout size and copied GGUF, but does not change that build blocker.

## Goal closure

- **Goal status:** partial — the owned inventory artifact is complete and
  committed, but the required clean Release build is blocked by the baseline
  compiler errors.
- **Success evidence:** all observed material contributors and conditional
  GGUF path are mapped to source/built paths, sizes, ownership references,
  configuration necessity, provenance status, disposition, risks, and an
  implementation contract. The clean-worker subtotal reconciles to its
  partial app total, and the parent-supplied contaminated-checkout total
  reconciles as 1,198,316 KB = 1,094,912 KB GGUF + 103,404 KB non-GGUF.
- **Stop state:** audit-only; no source/project/resource exclusion was applied.
- **Non-goals respected:** no app-code changes, no build change, no deletion,
  no other docs, no push/PR/rebase/merge, and no clean Release claim.
