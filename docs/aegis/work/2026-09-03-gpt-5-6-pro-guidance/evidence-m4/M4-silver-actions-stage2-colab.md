# M4 Stage-2 silver-action fit + Colab packaging

## Status

This slice adds the minimum research-only Stage-2 path for SET OS Camera
Coach. It consumes one or more independently audited generator pair roots
(`pairs.jsonl`, `receipt.json`, and derivative PNGs) without copying media,
then fits only CandidateA's `issue_logits`, `action_utility_logits`, and
`continuous_target_deltas` heads. Each root requires an externally declared
receipt SHA-256 and passes deep generator, inventory, geometry-receipt,
tool/environment-chain, schema, and media checks. The Stage-1 encoder is
accepted only when a caller declares its SHA-256 and the completed Stage-1
receipt binds that same artifact, path, kind, and CandidateA full-frame
encoder contract.

The output is a restartable run root containing atomic epoch checkpoints,
fit-only metrics, a receipt, and one `candidate-final.pt` state artifact. Every
artifact and receipt is explicitly `research_only=true`, `human_gold=false`,
and `release_admissible=false`. Unknown target entries remain mask `0`; source
and control image references are validated as metadata but their pixels are
never loaded. There is no validation/test/release metric or promotion claim.

## Admission and training contract

`ml/camera_coach/train_silver_actions.py` reuses the frozen CandidateA,
`preprocess_frame`, and `compute_multitask_loss` owners. Before the first
batch it checks every root's externally supplied receipt SHA-256, exact
manifest hash/count, media aggregate, contract and pair-schema hashes,
generator source, inventory, geometry receipt/tool/environment chain, frozen
semantics, and research boundary. It then rejects unsafe or duplicate IDs,
source-family collisions across roots, derivative paths, schema drift, unknown
target catalogs, invalid masks/ranges, altered derivative bytes, non-PNG or
multi-frame images, and source/geometry linkage mismatches. Full records are
sorted globally by pair ID with root/path tie-breakers; `max_records`, when
used, selects a deterministic fit prefix within each root and does not create
an evaluation split. All root receipt/provenance records are retained in the
run receipt.

Only derivative PNGs pass through the canonical preprocessing path. ROI-derived
features are supplied where present and other scalar metadata remains unknown
with explicit missing masks. CandidateA output ordering and contract ranges
are checked on every batch. All parameters and buffers are frozen except the
three declared action heads; loss weights for all other heads, ranking, and
contrastive terms are zero.

The Stage-2 config is
`ml/camera_coach/configs/silver_actions_stage2_colab.json`. It intentionally
declares only external relative data roots and a tracked contract hash. A
Stage-1 artifact is never guessed, downloaded, or accepted without the
`--stage1-sha256` declaration and receipt binding.

## Colab and bundle contract

`ml/camera_coach/colab/SET_OS_Camera_Coach_Stage2.ipynb` mounts Google Drive,
accepts the small reviewed code bundle through the notebook, and requires one
data ZIP containing the three audited pair roots to be uploaded directly to
the documented Drive workspace before its verification cell. This keeps the
1.2-GB payload out of Colab process memory. The user pastes both external
bundle SHA-256 values and the completed Stage-1 artifact SHA-256; the three
root receipt hashes and expected pair counts are fixed in the notebook. Both
ZIPs are verified before extraction. The data archive is streamed from Drive,
checked for duplicate, unsafe, non-regular, oversized, unexpected, or
hash-mismatched members, extracted into staging, then atomically published.
Every root is verified again by the trainer before fitting; source/control
pixels are absent from the archive. On completion the notebook identifies and
downloads only `candidate-final.pt` and its `receipt.json`; checkpoints and
pair media remain on Drive.

`tools/dataset/package_camera_colab.py` retains the Stage-1 default and its
byte identity exactly, while adding an explicit `--profile stage2` allowlist.
Both profiles use deterministic ZIP ordering/timestamps/permissions, generated
manifest and SHA-256 records, strict regular-file checks, and the existing size
ceilings. The Stage-2 bundle includes the tracked schema/generator/geometry
authority files needed for deep admission, but does not contain source/control
images, pair media, checkpoints, or a model redistribution claim.

`tools/dataset/package_camera_stage2_data.py` creates the single Stage-2 data
upload from the audited Commons, EVA, and AADB roots. It is stdlib-only and
stores already-compressed PNGs without recompression. The packager admits only
`pairs.jsonl`, `receipt.json`, and the derivative PNG named by each row; it
recomputes all hashes, enforces the three fixed external receipt digests,
rejects symlinks/path escape/collisions/mutation, and emits deterministic
bundle manifests before atomic publication.

## Verification

All pre-Colab implementation commands below were run from the repository root.
No real ML training was run in that verification batch; the trainer self-test
uses tiny synthetic PNG derivatives and a disposable fake Stage-1 encoder
artifact, then exercises one interrupted epoch and ledger-selected resume. Its
bounded admission cases cover two roots, swapped and missing receipt hashes,
deterministic global ordering, cross-root family and media/pair collisions, and
preservation of each root's receipt/provenance. The later real Colab result is
recorded separately below.

```text
python3 -m py_compile ml/camera_coach/train_silver_actions.py tools/dataset/package_camera_colab.py
PASS

python3 ml/camera_coach/train_silver_actions.py --self-test
PASS train_silver_actions self-test multi-root swapped-hash-missing-hash collision global-order pair-receipt-chain derivative-only-preprocessing masked-three-head-fit stage1-hash-gate atomic-resume research-boundary

Generated-output admission integration
PASS generator-output-admission pairs=9 receipt_sha256=1c09be1e4ec8b7e0379bc6387e7e889f93edc1d4781c4e96f41fe7e8c9332b88
PASS generate_camera_corruptions self-test recipes square_stream_zoom_receipt_lf hash_path_mask_determinism atomic_research_only

Read-only audited Commons + EVA multi-root admission (no training or media copy)
PASS real-multi-root-admission roots=2 records=1332 receipts=2
PASS real-root-order first=pair_00521a7206ef725470713d1aac6740bbcdded7fa last=pair_ff6eb956da8dc837ad5d3fcfea6ea00a2801ad31 data_hash=47b76c980e6d196579d319450ea87ffd7838f54b7c0c13e545f3949da7535b52

After the independent AADB compact source was published, the same generic
admission path was rerun without code changes or media copying:
PASS real-three-root-admission roots=3 records=5597 receipts=3 data_hash=18bb707699a9129b07ac3a4970beea4ed248009ddf6a54558c55a9117f9c1996

python3 tools/dataset/package_camera_colab.py --self-test
PASS package_camera_colab self-test deterministic-zip strict-allowlist sha256-manifest output-collision symlink-guard

python3 tools/dataset/package_camera_stage2_data.py --self-test
PASS package_camera_stage2_data deterministic-jsonl-derivative-only receipt-binding safe-member-order atomic-output

Config JSON and notebook code-cell AST validation
PASS notebook-json-ast cells=12 stage2-allowlist-match single-data-upload

Real-repository package profile inspection (temporary output under /private/tmp)
PASS profile=stage1 sha256=82937047ab9f3ebf279f63fe25cb99aeebf2cdd0330e1974779897a87aa7fc79 files=10 schema=camera-eva-stage1-colab-bundle-v1 sums=camera-eva-stage1-sha256-v1
PASS profile=stage2 sha256=0e32237f40ce56065e9d9bceec50c7152329b9265554626820d7e4d80159bdeb files=13 schema=camera-coach-stage2-colab-bundle-v1 sums=camera-coach-stage2-sha256-v1

Read-only full Stage-2 data-bundle verification
PASS bytes=1202444021 members=5605 roots=3 pairs=5597 images=5597
PASS receipt-roots commons=233 eva=1099 aadb=4265
PASS local-notebook-extraction staged-verify-atomic-replace

Stage-1 profile regression
PASS Stage-1 bundle hash remains 82937047ab9f3ebf279f63fe25cb99aeebf2cdd0330e1974779897a87aa7fc79 (10 files)

Scoped owned-file whitespace check (`git diff --check`; `git diff --no-index --check /dev/null` for new files)
PASS git-diff-check scoped-owned-files
```

Temporary self-test directories are cleaned on exit. The audited Stage-2 code
bundle is stored outside Git at
`~/Library/Application Support/SETOS/Datasets/camera-coach/research/bundles/SET_OS_CAMERA_STAGE2_a_20260910_v4.zip`
with SHA-256
`0e32237f40ce56065e9d9bceec50c7152329b9265554626820d7e4d80159bdeb`.
The single Stage-2 data upload is
`~/Library/Application Support/SETOS/Datasets/camera-coach/research/bundles/SET_OS_CAMERA_STAGE2_DATA_20260909_v1.zip`,
1,202,444,021 bytes, SHA-256
`dcf3a3ce3aa949bcd17b49435e50d74761e02893e644cd87106b3e19e95acf04`.
The existing Stage-1 bundle remains byte-identical at SHA-256
`82937047ab9f3ebf279f63fe25cb99aeebf2cdd0330e1974779897a87aa7fc79`.

## Completed Colab run and research conversion

The user-operated Stage-1 and Stage-2 Colab runs completed on 2026-09-11.
Stage 2 binds the completed Stage-1 encoder SHA-256
`cbaeddfeae41a3e65c0e8ec841621e1e0c7a5d2730b935a542ef35a182b7db6f`.
The returned `candidate-final.pt` SHA-256 is
`e663e2c595f49ac7f603d84f8795d0633c5079467c01ce04e13bea05abbc2d9f`;
its returned receipt SHA-256 is
`dd515bf93c1fa4ab0bd09be0e78726bcba41349b5e44d0ea32606272c36fb46c`.
The receipt is `complete`, covers all 5,597 fit records and five epochs, and
retains `research_only=true`, `human_gold=false`, and
`release_admissible=false`. Its artifact, contract, config, data, code-boundary,
pair-root and Stage-1 hashes match the supplied files and current conversion
sources.

Fit-only total loss fell monotonically from `0.0968005` to `0.0434874` across
the five epochs. The three component losses also fell: issue
`0.0197569→0.0011950`, action utility `0.0522798→0.0239891`, and continuous
delta `0.0247639→0.0183032`. A deterministic state comparison found changes in
all 308 Stage-1 full-frame-backbone tensors and exactly six head tensors: the
weight and bias of `issue_logits`, `action_utility_logits`, and
`continuous_target_deltas`. No other head or fusion tensor changed. An
eight-sample fresh-input probe produced finite, non-constant outputs for all
three trained heads. This excludes an obvious frozen-head or constant-output
failure, but fit-only metrics do not establish validation quality,
generalization, calibration, or candidate selection.

`ml/camera_coach/convert_coreml.py` now performs the minimal fail-closed
research conversion. It verifies the receipt, source artifact and current code
boundary, strictly loads finite state, converts FP16 `mlprogram` for iOS 17,
exports all six canonical named inputs and all nine canonical named outputs,
embeds the research boundary in metadata, loads the package on macOS CPU, and
writes a deterministic-input PyTorch/Core ML parity report. The external
package is
`/Users/unterlantas/Documents/ВКР2/SETCompositionNet-Stage2-Silver-FP16.mlpackage`
(aggregate tree SHA-256
`f0e55cf2f43278c930fcf8bf4ae0c3160da89bb7c948b8e752b1494f7c07e0fd`,
4,868,999 bytes). Core ML inspection reports `mlProgram`, no custom op, and
the expected six-input/nine-output interface.

All nine outputs passed one deterministic CPU parity case with `atol=0.005`
and `rtol=0.01`; the largest absolute differences were `0.0256262` for action
utility logits, `0.0102720` for issue logits, and `0.0022486` for continuous
deltas, with argmax preserved. The sidecars are adjacent to the package as
`.parity.json` and `.conversion-receipt.json`. Core ML transport images use
NCHW with a leading batch dimension while the frozen logical contract remains
HWC. Tracing does not embed CandidateA's Python trust-boundary range checks, so
the package metadata and receipt require external input validation. This is a
known research boundary for the later runtime provider, not permission to wire
this package into production.

## Known limits

This is synthetic/silver supervision only. It does not establish human-gold
quality, family-aware generalization, calibration, abstention/risk behavior,
release readiness, physical-device performance, or image rights. The single
synthetic parity case establishes only bounded research conversion parity, not
the M4-016 validation-selected production conversion gate. Core ML Tools 9.0
also warns that installed Torch 2.10.0 is newer than its latest tested Torch
2.7.0. The Stage-1 encoder remains a research warm-start. The final state is
not a production iOS model and must not be redistributed as one.
