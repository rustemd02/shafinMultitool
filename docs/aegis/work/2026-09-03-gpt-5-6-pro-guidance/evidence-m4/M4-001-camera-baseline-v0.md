# M4-001 — Camera fullRuntime development baseline v0

Status: **PARTIAL / 107 current rows exported; 207 current replay blocked by missing inputs**

This receipt deliberately does not make a release-quality, model-quality, or
holdout claim. It locks the current Swift replay evidence that can be proved
from this checkout and records why the 207-row run cannot be reproduced here.
The machine-readable manifest and all current 107 output/metric artifacts are
under [`docs/cameraanalysis/eval/camera-baseline-v0/`](../../../../cameraanalysis/eval/camera-baseline-v0/).

## Source and runtime claim

- Source commit: `e1280c83d787284f33076694b4b61ca88081f6fd`
  (`state: start Camera development baseline lane`).
- Branch: `codex/set-os-m4-001`.
- Production path: `AnalysisPipeline.testingReplayStillImageForSemanticEval`.
- Options: `SemanticEvalStillImageReplayOptions.fullRuntime`:
  `runHeavyModels=true`, `runNeuralEvidence=true`,
  `runVisualEvidence=true`, source `swift_still_image_replay`.
- Every exported row has `runtime_claim=real_runtime_still_replay` and
  `source=swift_still_image_replay`. There are 214 rows: 107 `live` and 107
  `pause`, covering the complete v1 label set.
- The run used the ordinary **iPhone 17e Simulator** only:
  `1F680A42-CEB3-43E8-9CED-52F874962A62`, iOS 26.5 (`23F77`). No physical
  device or iPhone 17 Pro was used.

The claim is limited to the Swift production replay path. It does not prove
that every model call succeeded on every frame, nor does it prove physical
camera timing, ARKit, thermal behavior, or release readiness.

## 107-row current receipt

Input integrity is complete for v1:

- labels: `docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl`
  (`db8a2cb5bb8b81a6cbf84585e1849f783e503ce03a9e090e59f9fe1bc04a3fd0`);
- images: `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images`;
- 107/107 files present and all 107 label SHA-256 values match;
- selected image tree digest:
  `4b35072bc2355684ffbd17bfdd9ca45c51739450ad4ddab8636c95054bc62fb0`.

Measured metrics from the canonical evaluator:

| Metric | Value |
| --- | ---: |
| records | 107 |
| pass rate | 0.467290 |
| expected action hit rate | 0.588785 |
| future action hit rate | 0.895833 |
| forbidden action violation rate | 0.084112 |
| good-frame preservation rate | 0.478261 |
| technical failure gate rate | 0.900000 |
| positive confirmation rate | 0.434783 |
| confidence-band accuracy | 0.672897 |
| demo-priority pass rate | 0.500000 |

Failure counts are 35 confidence-band mismatches, 9 forbidden-action
violations, 24 good-frame overcorrections, 44 missing expected actions, 5
missing future actions, 26 missing positive confirmations, and 2 semantic
overreaches on technical failure. These are development regression signals,
not a pass/fail release gate.

Committed artifacts and SHA-256 values:

| Artifact | SHA-256 |
| --- | --- |
| `fullruntime_candidate_outputs_107.jsonl` | `baa132b46e60b88f98189fab72d961f79be859218c636fe9c64df04ac33305e2` |
| `scored_candidate_outputs_107.jsonl` | `aa0254c949ba5ad4e505dbb160d2ca8ee4344ea2e9993ebb32eb6d60e5c72990` |
| `case_results_107.jsonl` | `36d41998affbf3fa8f9f404ef9973ca73ecf202cae9fd86c9233b9cbcf72d13b` |
| `set_metrics_107.json` | `98416533db179f45073073f7e38f6b44b738b70768831ff7778fdb352803c862` |
| `bucket_metrics_107.json` | `948343c381303b70cbf770bff493d34b63d087d549e2037864b96ef69ea605d2` |
| `semantic_eval_summary_107.md` | `a636cde18082ba03ab68fd244b96b873065fb6cf711b58045763007339d14aa8` |
| `manifest.json` | `2a3ea47474de33d4d5681e9e1dfd1197bd5639244c5e16e895f84455966bb2dc` |

## 207-row status

The v2 labels file has 207 rows (`3fb47ecfe3ac0edfda4afece45f9bd44fd507ab9d7476952108b83905f6da30a`). The checked-in image root contains only 142 of those rows; 65 source files are absent, from `110.jpg` through the listed gaps and `157.jpg`–`207.jpg`. The 35 present v2 rows have no label `sha256` value, so they cannot be hash-verified against the image pack. Consequently a partial run would not be the declared 207 dataset and no current 207 fullRuntime output is exported.

The existing `out_semantic_real_runtime_v2_after_runtime_fix_r6` output is
retained as a historical reference only:

- 414 rows / 207 records;
- candidate output SHA-256:
  `a0bc552fc33b4eea1093590885b0f5e5ee4214ec22bfe5e0ac5bdd8dfabfa57e`;
- source commit: `56440ecf344f2f3064270789e6cf6549215bb1f0`
  (`camanalfixes`), not the current HEAD;
- historical pass rate: `0.671498`.

The canonical scorer reproduced the historical metric values from this stored
file, but that check is not source authentication. No historical row is
relabelled as current evidence.

## DETR / NIMA provenance read

No model wrappers or resources were changed by this task. The manifest records
the exact package tree and component hashes.

- DETR wrapper:
  `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift`
  (`254eeff6…e0a13`); package tree digest
  `8ef98e8375d1e4abe14cb5db64c889af21152175d6178203b8a4e6eaeb1f0e4f`;
  43,085,928 bytes. The embedded model specification identifies DETR,
  references the original paper and `facebook/detr-resnet-50-panoptic`, and
  contains an Apache 2.0 reference.
- NIMA wrapper:
  `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift`
  (`54f910…a404`); package tree digest
  `4ee0d71da23f242abfba7a1164944511960fd7ed4b48eb5ed04f612eb0af5a65`;
  6,499,576 bytes. The embedded spec identifies a NIMA MobileNet v1 graph and
  CoreML6, but contains no authoritative upstream URL or license text.
- `compact_neural_evidence_net` is not present in this checkout. The receipt
  therefore does not claim an executed local neural-evidence model, even
  though `.fullRuntime` requests the neural-evidence branch.

## Evaluator provenance and reproducibility

Evaluator source is pinned by the current commit and file hashes in
`camera-baseline-v0/manifest.json`:

- Python `3.11.9`;
- `run_semantic_label_eval.py` SHA-256
  `0d370819607b34f32cc3f073f25a3f768ec4e0571363f54d9d1135fc51305df0`;
- `semantic_label_adapter.py` SHA-256
  `9927bce99985df1e6855b74ba9581a69bc0c5d77c4753d7f06c033a0e2e1df73`;
- `semantic_output_schema.py` SHA-256
  `b8d6489977abf7ab19934ac2ad1d5540ed4c2b5d1f06d5f5298c7ce63b7ae573`;
- `scorer.py` SHA-256
  `2b1d351effe0ae61a07b66a729c79baa389f52480ea11290b171c31b846adfa2`;
- `eval_io.py` SHA-256
  `c1f81e9ce1740e058ea79def4d4d649b487c0b9243d220f97c53d3ae7d5299b4`.

Scoring the committed 107 candidate output twice produced byte-identical
candidate outputs, case results, set metrics, bucket metrics, and summaries.

## Exact commands and results

The Swift export command (executed with a transient absolute-path replay
config, removed before this handoff) was:

```sh
xcodebuild test \
  -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/m4-001-dd-107 \
  -resultBundlePath /private/tmp/m4-001-fullruntime-107-r1.xcresult \
  -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **`; one targeted test passed in 70.479 seconds.
The result bundle tree digest is
`544811e6305fc859423ff6c5fbf5987c9fb6d0242bf055f0fc39fd8f99265d01`.

Canonical scoring command:

```sh
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs <temporary-output-dir> \
  --candidate docs/cameraanalysis/eval/camera-baseline-v0/fullruntime_candidate_outputs_107.jsonl \
  --images-dir shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images
```

Result: successful; second run was byte-identical for all five generated
report files. JSON manifest validation also passed with
`python3 -m json.tool`.

No threshold tuning, holdout access, oracle projection, proxy relabelling,
production source edits, or simulator target outside the allowed ordinary
iPhone 17e were used. This M4-001 receipt remains incomplete for the full 207
current dataset until the 65 source images are restored and the 35 hashless
label records receive authoritative hashes.
