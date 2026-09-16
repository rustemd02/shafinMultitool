# M4 EVA Stage-1 encoder warm-start + Colab runner

## Status

The current working tree contains the corrected research-only C1+C2 slice. It
consumes the P3 `silver-manifest.jsonl` and `eva-silver-receipt.json`, admits
the exact image join, and trains only `CandidateA.full_frame_backbone` with
disposable EVA-native auxiliary heads. It does not supervise or export any SET
scene, issue, action, good-frame, abstention, risk, or delta head.

`encoder-final.pt` is an explicit encoder-only artifact with
`contains_set_runtime_heads=false` and `contains_eva_auxiliary_heads=false`.
The resumable epoch checkpoint is a separate file and is not a SET runtime
checkpoint. No production-candidate, validation, or success-threshold claim is
made.

## Admission and training contract

`ml/camera_coach/pretrain_eva.py` requires the external data root to contain
the exact P3 manifest and receipt paths declared by
`ml/camera_coach/configs/eva_stage1_colab.json`. Before the first batch it:

- checks the receipt schema, research-only/non-gold/non-release flags, image
  join contract, exact manifest SHA-256, and exact row count;
- rejects blank/malformed/duplicate rows, unsafe relative paths, lexical
  symlinks, changed image bytes, undecodable images, missing aggregates, and
  out-of-range EVA means;
- verifies every `image_sha256` against the actual external image and
  re-checks the image before each batch read;
- handles integer EXIF orientation tags 1..8 with
  `ImageOps.exif_transpose` exactly once before the fixed-size resize;
  missing/unrecognized tags (including Pillow's legacy `0` sentinel) follow
  no-op behavior; numeric orientation below 0 or above 8 is rejected; embedded ICC profiles are
  converted to sRGB through Pillow `ImageCms`; untagged images use an explicit
  sRGB assumption; malformed or unsupported ICC input fails closed;
- records preprocessing rule/counts in the training receipt, including
  transformed orientations (only EXIF tags 2..8), embedded-profile/conversion,
  and untagged-sRGB rows;
- admits all selected P3 rows into one fit-only set. P3 supplies no family IDs,
  so there is no dev/eval partition, validation metric, holdout claim, or model
  selection in this auxiliary warm-start;
- normalizes score from 0..10 to 0..1 and each 1..4 EVA attribute to 0..1;
- trains six bounded regression outputs (score, difficulty, visual,
  composition, quality, semantic) plus a six-class numeric content-category
  classifier. Uncertainty and vote count are recorded by P3 but are not used
  as weights in this minimal baseline.

## Resume and crash-safety contract

Every epoch writes an atomic checkpoint and an `in_progress` receipt. The
receipt's `last_checkpoint` ledger is the only source used to select a resume
checkpoint. The filename must be exactly `epoch-NNNN.pt`, the path must resolve
under `run_root/checkpoints`, the ledger SHA-256 is verified before
`torch.load(..., weights_only=True)`, and an explicit resume path must match the
ledger. Config/data/model-contract/fit-semantics/code-boundary changes reject
resume. The original `started_at` is retained.

After the final epoch, the encoder artifact is written and verified before the
receipt changes to `complete`. If a crash leaves an `in_progress` receipt, a
later resume never attests an existing `encoder-final.pt`: it rewrites the
export from the verified ledger checkpoint's loaded encoder state, verifies the
new bytes, and only then writes the complete attestation. A completed receipt
always requires a verified final artifact attestation. Checkpoint and final
artifact tampering are rejected.

The receipt distinguishes the two contract hashes: `model_contract_sha256` is
the SHA-256 of canonical JSON for the actual derived model contract, while
`contract_source_sha256` is the SHA-256 of the tracked
`set_composition_net_v1.json` bytes in the code-boundary ledger. They are not
interchangeable.

## Colab handoff

`ml/camera_coach/colab/SET_OS_EVA_STAGE1.ipynb` is orchestration only. It:

1. optionally mounts Drive and chooses the persistent `RUN_ROOT` (and data
   root) under Drive before invoking the trainer, so a fresh runtime can resume
   after receipt/checkpoint integrity checks;
2. accepts exactly one generated bundle upload;
3. requires the user to paste `EXPECTED_BUNDLE_SHA256` from the packager and
   verifies the whole ZIP before extraction;
4. enforces the hard-coded ten-file allowlist, bundle-manifest schema, member
   and total uncompressed size ceilings, safe paths, and per-file SHA-256
   records. Embedded manifests are secondary checks, never the trust anchor;
5. uses the existing pinned EVA fetcher and P3 silver builder;
6. invokes `pretrain_eva.py` (or resumes its ledger-selected checkpoint);
7. displays fit-only metrics, preprocessing counts, both contract hash kinds,
   and artifact hashes, then optionally exports the persistent run/artifact.

The notebook does not duplicate model or trainer logic, does not install the
Darwin `requirements.lock`, and records actual Colab runtime versions.

`tools/dataset/package_camera_colab.py` contains the same strict ten-file
closure, deterministic ZIP timestamps/order/permissions, size ceilings,
generated `bundle-manifest.json`, and `SHA256SUMS.json`. The generated ZIP is
external and is not tracked.

## Verification

Commands run from the repository root after the fix-first changes:

```text
python3 -m py_compile ml/camera_coach/pretrain_eva.py tools/dataset/package_camera_colab.py
PASS

python3 ml/camera_coach/pretrain_eva.py --self-test
PASS pretrain_eva self-test silver-admission exif-once exif-range-rejection icc-to-srgb fit-only tiny-train checkpoint-ledger-resume tamper-rejection crash-recovery-rebuild encoder-only-export

python3 tools/dataset/package_camera_colab.py --self-test
PASS package_camera_colab self-test deterministic-zip strict-allowlist sha256-manifest output-collision symlink-guard

Notebook JSON/code-cell AST parse
PASS cells=12
```

The self-test covers one transformed orientation image, one identity EXIF `1`
image that does not increment the transformed counter, out-of-range EXIF
rejection, one embedded ICC image, malformed ICC fail-closed behavior, the
explicit untagged-sRGB count, fit-only receipt counts, one-epoch resumable
training, checkpoint-byte tamper, checkpoint path escape/non-ledger selection,
final encoder-only export, and crash-window recovery that replaces a different
valid-looking final artifact. It uses only a small CPU fixture and cleans its
temporary directory on exit.

The real P3 admission check is intentionally separate from full training:

```text
PASS real-admission records_full=4070 records_fit=4070
manifest_sha256=8351cdfc3ca43095c109a95c6e317693f4d5479f6f8387d4f2f272cff0947a8c
receipt_sha256=381937c0dba8478640860b255b25ca10cffba7e3034a71092b6831ab2245443f
data_hash=45c877a36233b2d209094283a95b3ac7f9128272eac94f403d7dc73962b77a23
preprocessing_counts={'orientation_transformed_images': 6, 'embedded_icc_images': 713, 'embedded_icc_converted_to_srgb_images': 713, 'untagged_srgb_assumption_images': 3357}
model_contract_sha256=08629f1608cb555e563d412c0d3d7bdebee569d007dc946ceb0b87e90d9231e0
contract_source_sha256=ef05756ac5c78d89d0ec9a14864d193357ced0e1925ef9759b6ab8e78c36e074
```

CandidateA full-frame contract inspection remains `output_shape=(2,720)`;
this check does not run real training locally.

Deterministic external bundle rebuild:

```text
PASS byte-identical, 10 source files
sha256=82937047ab9f3ebf279f63fe25cb99aeebf2cdd0330e1974779897a87aa7fc79
```

Primary generated bundle (outside Git):
`/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/bundles/SET_OS_EVA_STAGE1_a_20260909_v9.zip`

`git diff --check` has no output for tracked changes, but the owned C1+C2 files
are currently untracked in the shared working tree; therefore that command
does not inspect them. The owned files were checked with the equivalent
`git diff --no-index --check /dev/null <file>` form (exit status 1 is expected
for an untracked file; no whitespace diagnostics were emitted).

## Known limits

EVA/AVA underlying image rights remain unresolved, so this lane cannot supply
release data. P3 has no family IDs; family-aware splitting is still required
before any genuine validation or human-gold evaluation. Auxiliary EVA quality
pretraining does not make the model understand SET scene/action taxonomy or
guarantee useful on-device coaching. No Core ML export, iOS model authority,
human-gold labels, or physical-device evidence is created here.
