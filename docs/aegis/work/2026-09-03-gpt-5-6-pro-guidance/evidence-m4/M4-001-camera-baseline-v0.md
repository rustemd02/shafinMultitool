# M4-001 — Camera fullRuntime development baseline v0

Status: **PARTIAL / 107 current orchestration rows exported; Vision failed closed 107/107, NIMA scores returned 107/107, DETR foreground detections non-empty in 85/107; 207 current replay blocked by missing inputs**

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
- This is genuine Swift fullRuntime orchestration. Apple Vision tracking
  fail-closed for all 107 records with the observed `Failed to create espresso
  context`. The same run returned a finite NIMA score for all 107 records and
  serialized non-empty DETR-derived foreground detections for 85 records. The
  rows therefore prove the production orchestration, NIMA score-return path,
  DETR non-empty-output evidence, decoding, fail-closed Vision path, and output
  contract, but not successful Vision tracking, calibrated model quality, or
  compact neural-evidence inference.
- The run used the ordinary **iPhone 17e Simulator** only:
  `1F680A42-CEB3-43E8-9CED-52F874962A62`, iOS 26.5 (`23F77`). No physical
  device or iPhone 17 Pro was used.

The claim is limited to the Swift production replay path. It proves NIMA score
return for 107/107 and records a lower-bound DETR-derived non-empty count of
85/107; it does not prove successful Vision tracking, DETR quality, calibrated
NIMA quality, compact neural-evidence inference, physical camera timing, ARKit,
thermal behavior, or release readiness.

## Inference evidence in the 107-row export

| Source | Exact serialized evidence | Scope of claim |
| --- | --- | --- |
| Apple Vision tracking | `Failed to create espresso context` for 107/107 records | Tracking failed closed in this simulator run; no successful Vision tracking claim |
| NIMA | finite `debug_numeric_features.aesthetic_score` for 107/107 records; range `0.3325038909912109…0.5681289792060852` | NIMA score-return path succeeded; `aesthetic_confidence=-1` is not calibrated confidence |
| DETR | `debug_numeric_features.object_count > 0` for exactly 85/107 records; 22 records are zero; foreground count sum 239 | Exact serialized non-empty foreground-detection evidence; zero-count rows are not classified as successful or failed raw inference because pre-filter arrays are not exported |
| Compact neural evidence | `compact_neural_evidence_net` absent from checkout | No compact-neural inference claim |

The raw artifact has one live and one pause row per record (214 rows total), so
the 85/107 and 107/107 counts are record-level counts, not doubled row counts.

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
| `m4-001-fullruntime-107-r1.jsonl` | `baa132b46e60b88f98189fab72d961f79be859218c636fe9c64df04ac33305e2` |
| `scored_candidate_outputs_107.jsonl` | `aa0254c949ba5ad4e505dbb160d2ca8ee4344ea2e9993ebb32eb6d60e5c72990` |
| `case_results_107.jsonl` | `36d41998affbf3fa8f9f404ef9973ca73ecf202cae9fd86c9233b9cbcf72d13b` |
| `set_metrics_107.json` | `98416533db179f45073073f7e38f6b44b738b70768831ff7778fdb352803c862` |
| `bucket_metrics_107.json` | `948343c381303b70cbf770bff493d34b63d087d549e2037864b96ef69ea605d2` |
| `semantic_eval_summary_107.md` | `a636cde18082ba03ab68fd244b96b873065fb6cf711b58045763007339d14aa8` |
| `replay-config-107.json` | `05852dd1721656616b9d1e7db7b776315e5726413ba7851f4fefe129f4bca518` |
| `swift-replay-receipt-107.json` | `37419c5e543f2566c2d98093a5e46aa4ad731de7223a7c1294d103955aaa33e9` |
| `manifest.json` | `1fa02079742e287a966d35103f9ab1f576ade80bbcb05b850c9b7a9a4350d6f8` |

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
the exact package tree and component hashes. Each package tree digest is
computed as SHA-256 over sorted entries
`relative_path\0byte_length\0file_sha256\n` (UTF-8 path/ASCII metadata), as
declared in the manifest.

- DETR wrapper:
  `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift`
  (`254eeff6…e0a13`); package tree digest
  `6a5d3f2f7431f4964674cef8e054ac74c66e4f326e057bf5f4b35f8bfd6e7696`;
  43,085,928 bytes. The embedded model specification identifies DETR,
  references the original paper and `facebook/detr-resnet-50-panoptic`, and
  contains an Apache 2.0 reference. In the executed replay, serialized
  foreground detections were non-empty for exactly 85/107 records (239 total
  foreground detections); 22 zero-count records remain unclassified for raw
  inference because the export does not contain pre-filter arrays.
- NIMA wrapper:
  `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift`
  (`54f910…a404`); package tree digest
  `cd1032aa55ad9bf3fb2d9e95606cf3cd74b32ff9848cef6d43f7b70a30c8f495`;
  6,499,576 bytes. The embedded spec identifies a NIMA MobileNet v1 graph and
  CoreML6, but contains no authoritative upstream URL or license text. The
  executed replay returned finite NIMA scores for all 107/107 records (range
  `0.3325038909912109…0.5681289792060852`); the exported aesthetic confidence
  remains `-1` and is not calibrated.
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

## Portable replay configuration

The committed normalized configuration is
`docs/cameraanalysis/eval/camera-baseline-v0/replay-config-107.json` with SHA-256
`05852dd1721656616b9d1e7db7b776315e5726413ba7851f4fefe129f4bca518`. It uses
repository-relative label/image inputs and the explicit `<EXTERNAL_OUTPUT_PATH>`
placeholder; it contains no checkout, worktree, home, or temporary-directory
path. The executable runner is
`docs/cameraanalysis/eval/run_swift_semantic_replay.py` with SHA-256
`20fa2e289c7e6877cf684257132e1ef94e8ed48220f0716b9a0ac01bd81b50b1`. It
materializes this committed config by resolving the two inputs against the
repository root, substitutes a writable external output path, sets
`SEMANTIC_EVAL_CONFIG`, and writes the Swift test's canonical transient config
candidate before invoking `xcodebuild`. The exact executed transient config
hash for the verification run was
`bd1dbe8156b6ff064f522acc71c719e7520f34383647a8bcdad55ad8800d07ce`; the
materialized file was removed after the run.

Build receipt: configuration `Debug`; Xcode `26.6 (17F113)`;
iPhoneSimulator SDK `26.5 (23F81a)`; ordinary iPhone 17e Simulator
(`1F680A42-CEB3-43E8-9CED-52F874962A62`, OS build `23F77`). The portable
evidence locator is this report; the local `.xcresult` path is retained in the
manifest only as a nonportable session note.

## Exact commands and results

The executable Swift replay command (the runner selects the committed config
through `SEMANTIC_EVAL_CONFIG` and the test's canonical transient candidate) is:

```sh
m4_fix_run_dir=$(mktemp -d /private/tmp/m4-001-fix-replay.XXXXXX)
python3 docs/cameraanalysis/eval/run_swift_semantic_replay.py \
  --destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  --derived-data-path "$m4_fix_run_dir/derived" \
  --result-bundle-path "$m4_fix_run_dir/replay.xcresult" \
  --output-path "$m4_fix_run_dir/candidate_outputs.jsonl"
```

Verification run directory: `/private/tmp/m4-001-fix-replay.qyakaD` (a
nonportable session locator; no such path is required by the committed config).
Result: `** TEST SUCCEEDED **`; one targeted test passed in 83.629 seconds,
exporting 214 rows / 107 records with raw output SHA-256
`baa132b46e60b88f98189fab72d961f79be859218c636fe9c64df04ac33305e2`.
The fresh result bundle tree digest is
`01bdddee76e9407bb80e7c9bfb7ce2232de8bdeef40c5e32d97e4d5a005e3997`.
The compact durable receipt is
`camera-baseline-v0/swift-replay-receipt-107.json`.

Canonical scoring command:

```sh
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs <temporary-output-dir> \
  --candidate docs/cameraanalysis/eval/camera-baseline-v0/m4-001-fullruntime-107-r1.jsonl \
  --images-dir shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images
```

Result: successful; second run was byte-identical for all five generated
report files, and both clean replay directories matched the committed scored
artifacts byte-for-byte. The raw filename stem `m4-001-fullruntime-107-r1`
also now matches the scorer-derived `candidate_id`, so the documented command
is reproducible without a machine-specific rename. JSON manifest validation
also passed with `python3 -m json.tool`.

Clean replay comparison result:

```text
candidate_outputs.jsonl: clean replay A/B cmp=0; vs committed cmp=0
case_results.jsonl:      clean replay A/B cmp=0; vs committed cmp=0
set_metrics.json:        clean replay A/B cmp=0; vs committed cmp=0
bucket_metrics.json:     clean replay A/B cmp=0; vs committed cmp=0
semantic_eval_summary.md: clean replay A/B cmp=0; vs committed cmp=0
```

No threshold tuning, holdout access, oracle projection, proxy relabelling,
production source edits, or simulator target outside the allowed ordinary
iPhone 17e were used. This M4-001 receipt remains incomplete for the full 207
current dataset until the 65 source images are restored and the 35 hashless
label records receive authoritative hashes. The simulator fail-closed Vision
result is an explicit limitation: a future device-backed receipt must prove
successful Vision tracking and device-backed model behavior separately from
the NIMA score-return and DETR non-empty-output evidence recorded here.

## Correction history retained

The original baseline commit (`7fc77cd`) intentionally remains in history.
This correction records, rather than erases, the issues found in its review:

- the first current-HEAD 207 replay stopped at the missing `110.jpg` input and
  produced no candidate output;
- the original raw artifact name (`fullruntime_candidate_outputs_107.jsonl`)
  made a fresh scorer run derive a different `candidate_id` than the committed
  scored artifacts; the raw file is now renamed to the stable
  `m4-001-fullruntime-107-r1.jsonl` convention;
- the original DETR/NIMA aggregate digests omitted the declared byte-length
  field. They are replaced by the exact
  `relative_path\0byte_length\0file_sha256\n` digests recorded above;
- the initial receipt did not distinguish fullRuntime orchestration from
  successful simulator Vision/model inference. The corrected claim explicitly
  records the observed `Failed to create espresso context` fail-closed result,
  the 107/107 finite NIMA score returns, and the exact 85/107 serialized
  non-empty DETR-derived foreground-detection count;
- the follow-up replay now executes from the committed portable config through
  the repository runner and retains its compact receipt, instead of relying on
  an undocumented transient config.
