# Core ML model provenance and replacement research

- Date: 2026-08-15
- Scope: `DETRResnet50SemanticSegmentationF16P8.mlpackage` and `aesthetic_nima_mobilenet_fp16.mlpackage`
- Status: research evidence complete; no release decision accepted; implementation and product calibration not performed
- Decision owner: product/release owner
- Legal boundary: this is an engineering provenance review, not legal advice

## Executive recommendation

1. **The current DETR identity/source evidence is strong, but DETR is not yet approved for the RC.** It is byte-for-byte identical to the inspected Apple F16P8 package and its embedded metadata identifies the upstream `facebook/detr-resnet-50-panoptic` model and Apache-2.0 license. That closes an engineering provenance question, not the product-contract, calibration, redistribution-compliance or legal-owner gates.
2. **Recommended minimal commercial RC: exclude DETR, NIMA and compact neural fusion.** Apple Vision subject/saliency plus deterministic critique remain; missing object, aesthetic and neural evidence must be represented as unavailable. This is the smallest release route because the current DETR consumer misrepresents semantic coverage as confidence, NIMA lacks provenance and has unsafe nil/error semantics, and the compact artifact does not exist locally.
3. **If object-aware coaching is an owner requirement, retain-and-harden DETR is the only plausible exception.** Before production use, validate the output layout, replace pseudo-confidence with coverage semantics, calibrate the permitted advice against the Camera Coach benchmark, record redistribution notices and pass device latency/thermal gates. Provenance alone is insufficient.
4. **Do not ship the current NIMA payload as provenance-cleared.** Its package contains no author, license, checkpoint, upstream revision, or conversion command. Architecture similarity is not sufficient to assign it a license retroactively.
5. **Apple Vision aesthetics is a future measured replacement on iOS 18+, not an automatic RC substitution.** Use `VNCalculateImageAestheticsScoresRequest` only behind typed availability and calibration; keep aesthetics explicitly unavailable on iOS 17. A high aesthetic score must never suppress hard technical faults.
6. If product evidence later proves that an aesthetic score is essential on iOS 17, build a **new, reproducible Core ML package** from a pinned, rights-reviewed checkpoint. Do not relabel the existing package without reproducible equivalence proof.

## Local artifact inventory

### DETR

- Path: `shafinMultitool/Multitool2Module/Models/CoreML/DETRResnet50SemanticSegmentationF16P8.mlpackage`
- Source payload size: approximately 41 MiB (`du`); Apple gallery reports 43.1 MB.
- Input: RGB image, 448 × 448.
- Output: `semanticPredictions`, `Int32[448, 448]` semantic class map.
- Minimum model runtime: iOS 17.0.
- Model specification: ML Program, specification version 8, mixed Float16/palettized 8-bit storage.
- `model.mlmodel` SHA-256: `3d3666837fe990d3948308e417949864b5c2ab0dd9f21091c755c8effa005c40`
- `weight.bin` SHA-256: `8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7`
- `Manifest.json` SHA-256: `e7154240ddfd55b776642ae4f6b47d42bf8ad1b9425d97151d4d7b7875d0bf95`
- Embedded license: `Apache 2. Please, see the original model for details: https://huggingface.co/facebook/detr-resnet-50-panoptic`.
- Embedded release metadata: Apple model gallery name `DETRResnet50SemanticSegmentationF16.mlpackage`, release `2024-06`.

### NIMA

- Path: `shafinMultitool/Multitool2Module/Models/CoreML/aesthetic_nima_mobilenet_fp16.mlpackage`
- Source payload size: approximately 6.2 MiB.
- Input: RGB image, 224 × 224.
- Output: `Identity`, `Float16[1, 10]` score distribution.
- Minimum model runtime: iOS 16.0.
- Model specification: ML Program, specification version 7, Float16 storage.
- `model.mlmodel` SHA-256: `e5d44425c132e7ed2be99310226b573ae1765c37a909c1a0fd08aff311fb9cfc`
- `weight.bin` SHA-256: `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717`
- Embedded conversion markers: `coremltools 8.3.0`, `tensorflow==2.20.0`.
- Missing from artifact and repository: author, license, exact checkpoint, source URL, source revision, conversion script/command, conversion date, NOTICE, validation dataset and calibration record.

## DETR provenance proof

The exact official archive was downloaded from Apple on 2026-08-15:

- Gallery: <https://developer.apple.com/machine-learning/models/>
- Direct archive: <https://ml-assets.apple.com/coreml/models/Image/Segmentation/DETR/DETRResnet50SemanticSegmentationF16P8.mlpackage.zip>
- Downloaded ZIP SHA-256: `9436f344d7e935ef8f54025a43e760888a058ab9192f18248c3745d25fced4a7`

The downloaded package and repository package have identical hashes for all three material package files:

| File | Repository | Apple download | Result |
|---|---|---|---|
| `model.mlmodel` | `3d3666...5c40` | `3d3666...5c40` | exact match |
| `weights/weight.bin` | `8e0a22...ce7` | `8e0a22...ce7` | exact match |
| `Manifest.json` | `e71542...5d0b` | `e71542...5d0b` | exact match |

Upstream evidence:

- Apple lists the exact F16P8 package as a downloadable Core ML model and links the original DETR source.
- The package metadata identifies `facebook/detr-resnet-50-panoptic` and Apache-2.0.
- The upstream DETR repository is Apache-2.0: <https://github.com/facebookresearch/detr/blob/main/LICENSE>.
- The referenced checkpoint is labeled Apache-2.0: <https://huggingface.co/facebook/detr-resnet-50-panoptic>.

### DETR license conclusion

Engineering conclusion: commercial App Store use and redistribution are compatible with the supplied Apache-2.0 license, subject to satisfying its redistribution conditions. Before release:

- include the complete Apache-2.0 license text in the app's third-party acknowledgements or distributed notices;
- retain applicable attribution and copyright notices;
- record the Apple gallery URL, direct download URL, hashes above, model metadata and upstream source in the release provenance packet;
- if the model bytes are changed, record the modification prominently;
- confirm whether the selected upstream distribution includes a `NOTICE` file and preserve any applicable contents.

This closes the engineering **identity/source/license-evidence** question for the current DETR bytes. It is not legal approval and does not close redistribution compliance, accuracy, calibration, runtime, thermal or user-advice safety gates.

## DETR product-contract issue

The current Core ML package returns one class ID per pixel. It does **not** return per-instance bounding boxes or calibrated class probabilities. The existing `DETRDetector` wrapper currently:

- assumes a contiguous `Int32` memory layout instead of validating data type, strides and shape;
- joins every region of the same class into one bounding rectangle, so two separate chairs can become one large box;
- derives `confidence` from class pixel coverage (`count / totalPixels * 20`), which is not model confidence;
- suppresses `person` because another Vision path handles it;
- uses `.scaleFill`, which can distort geometry relative to the camera frame.

Required contract before object-aware advice may rely on DETR:

1. Treat the signal as semantic coverage/presence, not object detection confidence.
2. Validate `MLMultiArray.dataType`, shape and strides; prefer shaped-array/indexed access where practical.
3. Use connected-component extraction if separate regions/instances are required.
4. Rename the field to `coverage` or define a separate confidence source; never display it as probability.
5. Establish orientation/crop coordinate tests.
6. Calibrate class allowlists and thresholds on the Camera Coach benchmark set.
7. Benchmark latency and thermal scheduling on the minimum supported hardware.

Until those gates pass, DETR may support low-risk scene semantics but should not independently trigger high-confidence user instructions.

## NIMA replacement routes

### Route A — Apple Vision aesthetics (recommended)

- API: `VNCalculateImageAestheticsScoresRequest`
- Result: `VNImageAestheticsScoresObservation.overallScore`, range `-1...1`, plus `isUtility`.
- Availability verified in the installed iPhoneOS SDK header: iOS 18.0+, macOS 15.0+, tvOS 18.0+, visionOS 2.0+.
- Official documentation: <https://developer.apple.com/documentation/vision/vncalculateimageaestheticsscoresrequest>
- Bundled model bytes: none.
- Third-party model license/NOTICE: none.
- Expected integration risk: low to medium; score semantics differ from the current NIMA `1...10` distribution and require product calibration.

Recommended compatibility policy:

- iOS 18+: use Vision aesthetics behind an explicit `AestheticEvidence.available(...)` state;
- iOS 17: return `AestheticEvidence.unavailable(.osUnsupported)` and continue with deterministic technical, saliency and subject evidence;
- do not synthesize zero, one or another neutral score when unavailable;
- do not map the Vision score into the old NIMA scale until benchmark evidence defines a stable mapping;
- never allow an aesthetic score alone to suppress hard technical faults such as severe blur, clipping or unusable exposure.

Why this is the best RC route: Apple itself recommends considering an SDK API before bundling a third-party Core ML model because it can reduce app size and improve platform integration. See <https://developer.apple.com/documentation/coreml/classifying-images-with-vision-and-core-ml>.

### Route B — reproducible idealo NIMA Core ML build (only if iOS 17 coverage is required)

- Repository: <https://github.com/idealo/image-quality-assessment>
- Repository state: archived/read-only since 2024-12-02.
- License: Apache-2.0.
- Pinned revision: `dceaf7c2d218bc6e80b21d6e147e3b56a21b7f31`.
- Exact aesthetic checkpoint path: `models/MobileNet/weights_mobilenet_aesthetic_0.07.hdf5`.
- Checkpoint SHA-256: `e563ad91b3d47410e45f7238f07ab8f6abd1bd0c4b18a4b0af9c681a21a91cb2`.
- Checkpoint size: `13,174,216` bytes.
- Published model metrics: EMD `0.071`, LCC `0.626`, SRCC `0.609` on AVA, as reported by the repository.
- Expected Core ML payload: roughly comparable to the current MobileNet FP16 payload, but must be measured after conversion.

Required reproducible build packet:

1. Fetch only the pinned revision and verify the checkpoint hash.
2. Archive the upstream Apache-2.0 license and applicable notices.
3. Pin Python, TensorFlow/Keras and `coremltools` versions in a lockfile or container.
4. Store the conversion script in the repository; no manual notebook-only conversion.
5. Define exact preprocessing: RGB order, resize/crop behavior, scale and normalization.
6. Preserve a pre-conversion reference inference set and expected score distributions.
7. Compare TensorFlow and Core ML outputs with explicit numerical tolerances.
8. Populate Core ML author, license, source revision, checkpoint hash, conversion command and version metadata.
9. Hash the final `.mlpackage` contents and add license/NOTICE evidence to the release inventory.
10. Benchmark device latency, memory and thermal behavior; harden every callback/error path.

The current local NIMA package is plausibly a similar MobileNet-v1 architecture, but there is no evidence tying its bytes to this checkpoint. It must not inherit this license record without equivalence proof.

### Route C — heavier/newer aesthetic models

Not recommended for the first commercial release. Transformer-based image-quality/aesthetic models may outperform old NIMA on research datasets, but the candidates inspected did not offer a better combination of all four requirements: exact commercially redistributable weights, reproducible Core ML conversion, small mobile payload and measured iPhone latency. Revisit only after the first-party Vision route is benchmarked against real Camera Coach user cases.

## Object model alternatives considered

| Candidate | License evidence | Mobile/Core ML fit | Decision |
|---|---|---|---|
| Current Apple-gallery DETR F16P8 | Exact Apple-byte match; embedded and upstream Apache-2.0 | Already integrated; Apple reports about 32–52 ms on recent iPhones, but output is semantic segmentation | Conditional retain-and-harden route; exclude from minimal RC |
| Apple Vision subject/saliency APIs | First-party OS APIs | No payload; good for subject geometry/saliency, but not a general semantic label detector | Keep as complementary evidence |
| YOLOX Nano/Tiny | Official repository and weights under Apache-2.0; <https://github.com/Megvii-BaseDetection/YOLOX> | True boxes/classes; Nano 0.91M params, Tiny 5.06M; requires owned ONNX/Core ML conversion, NMS and iPhone benchmark | Backup experiment only if DETR semantic output cannot satisfy product needs |
| PaddleDetection RT-DETR / PicoDet | Official toolkit under Apache-2.0; <https://github.com/PaddlePaddle/PaddleDetection> | Strong detector family, but conversion/operator and device-performance work is materially larger | Later benchmark, not RC |
| Apple-gallery YOLOv3 Tiny | Apple supplies Core ML variants down to 8.9 MB; <https://developer.apple.com/machine-learning/models/> | Easy provenance and true detection contract, but older architecture/accuracy | Fallback benchmark, not preferred |
| Ultralytics YOLO models | AGPL-3.0 unless an Enterprise license is purchased; <https://docs.ultralytics.com/help/contributing> | Technically attractive, commercially unsuitable for this closed-source low-budget RC without a paid license | Exclude |

## Proposed owner decision

### Recommended minimal commercial RC

- **DETR:** exclude from the first RC. Its exact bytes have credible provenance evidence, but its current consumer does not yet provide a calibrated object-aware product contract.
- **NIMA:** remove the current unidentified package from Release.
- **Compact neural fusion:** keep explicitly disabled and reject accidental model contamination; no artifact or training/rights packet exists locally.
- **Aesthetics:** explicit unavailable state plus deterministic critique in the minimal RC; no fake fallback score.
- **Future iOS 17 aesthetic model:** only a pinned, reproducibly converted idealo package if product metrics prove the missing score materially harms outcomes.

Owner acceptance sentence:

`Camera Coach RC выпускаем без DETR, NIMA и compact neural fusion; принимаем отсутствие object-aware labels, model aesthetic score и neural fusion.`

### Alternative owner route — retain DETR

Choose this only if object-aware coaching is mandatory for the first release. Keep the exact inspected DETR package, complete Apache attribution/NOTICE review, and first implement the output-contract, coordinate, calibration and device-performance program described above. NIMA and compact neural fusion remain excluded. This route is materially larger and is not the minimal RC.

### Acceptance evidence for implementation

1. Minimal-RC Release contains no `.mlmodelc` or `.mlpackage` payload and the release validator rejects DETR, NIMA and compact contamination fixtures.
2. Default production construction never requests any of the three model signals; absence is unavailable, not zero, positive or a fabricated neutral value.
3. Apple Vision subject/saliency and deterministic critique continue to work without the models.
4. Missing aesthetics cannot suppress hard technical advice or hang pause analysis.
5. Missing neural evidence preserves deterministic critique exactly.
6. Focused tests and full release gates pass; physical-device and legal-owner gates remain separately explicit.
7. If the alternative DETR route is selected, replace items 1–2 with exact hash/attribution evidence plus output-contract, coordinate, benchmark calibration and device latency/thermal acceptance before any object-aware advice ships.

## Research limits

- No legal counsel reviewed Apple download terms, Apache compliance presentation, COCO/AVA training-data implications or App Store agreements.
- No candidate was converted or integrated in this research task.
- No aesthetic candidate was accuracy-benchmarked on Camera Coach images.
- Apple Vision latency and score distribution were not measured on supported devices.
- The current NIMA package was not proven equivalent to any public checkpoint.
