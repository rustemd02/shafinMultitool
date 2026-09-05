# M4-006 — reproducible Camera training environment

Status: `PASS` for infrastructure evidence only.

This slice provides a local, deterministic Python 3.11/PyTorch runner around
the two accepted disabled SETCompositionNet-v1 constructors.  It performs one
tiny synthetic CPU optimisation step and writes `config.json` plus
`receipt.json` under a new run directory.  An existing output target is
rejected before any write; receipts are never overwritten.

## Implementation

- `ml/camera_coach/train.py` parses a closed JSON config into frozen
  dataclasses, validates exact keys/types/ranges, pins the frozen manifest and
  synthetic source, imports the fixed `ml.camera_coach.models.set_composition_net`
  module, derives its actual `__file__`, and hashes that source plus `train.py`.
  It seeds Python and Torch, fixes CPU thread/deterministic settings, runs one
  SGD step, and emits hashes for config, dataset, model/contract, imported
  model source, runner source, runtime lock, environment, command,
  content-stable projection, and the receipt.
- `ml/camera_coach/requirements.lock` is a real pip `--require-hashes`
  requirements lock for the resolved nine-package Torch 2.10.0 closure on
  CPython 3.11.9/Darwin arm64.  It contains the actual SHA-256 hashes of the
  downloaded wheels, not installed `RECORD` hashes.  The runner parses the
  closed lock format, rejects closure/header drift, records its hash, and
  rejects installed package-version drift.
- `ml/camera_coach/configs/synthetic_dry_run.json` is the default four-sample,
  two-example-batch dry-run config.  Candidate A and B IDs are both accepted;
  the default is B to keep the evidence run small on CPU.  The admitted
  `sample_count` maximum is four, matching the executable synthetic source.
- `ml/camera_coach/configs/synthetic_dataset.json` is only a declared
  synthetic source.  It contains no human images or labels and is not an
  approved-data manifest.
- `ml/camera_coach/configs/training_config.schema.json` closes the config
  object and nested objects.  `ml/camera_coach/check_training_environment.py`
  is the bounded acceptance check; its temporary run directories are removed
  after the summary is emitted.

The stable receipt projection deliberately excludes run ID, timestamp, output
directory, config path, and the self-hash.  `--run-dir`/`--output-dir`/
`--output-root` values are normalized in the command projection, so separate
destinations do not create false reproducibility drift.  The actual
destination and invocation remain in `run_instance`/the normalized command
receipt.

## Verification

Static and schema checks:

```text
python3 -m py_compile ml/camera_coach/train.py ml/camera_coach/check_training_environment.py
python3 -m json.tool ml/camera_coach/configs/synthetic_dry_run.json >/dev/null
python3 -m json.tool ml/camera_coach/configs/training_config.schema.json >/dev/null
python3 -m json.tool ml/camera_coach/configs/synthetic_dataset.json >/dev/null
```

The bounded checker was run with:

```text
python3 -m ml.camera_coach.check_training_environment \
  > /private/tmp/setos-m4-006-environment-check-corrected.json
```

Its result was `status=pass`, with these material assertions:

```json
{
  "same_seed_projection_equal": true,
  "changed_seed_drift_detected": true,
  "changed_config_drift_detected": true,
  "runtime_lock_hash_pin_rejected": true,
  "runtime_version_drift_rejected": true,
  "alternate_model_source_path_rejected": true,
  "logical_tensor_slice_hash_isolated": true,
  "maximum_sample_count_exercised": true,
  "existing_target_rejected": true,
  "first_step_loss": 0.20278294384479523,
  "first_step_loss_tolerance": 1e-07
}
```

The tensor regression hashes a non-contiguous logical slice, changes unrelated
bytes in its larger backing tensor, and confirms the slice hash is unchanged;
then it changes a logical slice byte and confirms the hash changes.

Two independent CLI runs used the same config and seed and wrote compact
receipts to:

- `/private/tmp/setos-m4-006-corrected-a.json`
- `/private/tmp/setos-m4-006-corrected-b.json`

The temporary run directories were removed after comparison.  Both returned
`status=pass`; after removing only `run_instance` and
`hashes.receipt_sha256`, the complete receipts were equal.  Shared values:

| Value | Result |
|---|---|
| sample-order SHA-256 | `0091e5e462d4e98ce03fdc826950b0337725f6dfe97ff886240dd86cc9009cdb` |
| model-initialization SHA-256 | `4ec82bedc5aa25cd5f7e1a1cfdcf6ac8191c3c26cf1cfec4bf05cded4fd8781d` |
| first-step loss | `0.20278294384479523` |
| allowed loss tolerance | `<= 1e-7` |
| content-stable projection SHA-256 | `331852f3a0fe3e9a90bf4bb428c911012c12abd988fca4eecdf66033bee8968b` |
| config SHA-256 | `574f040d706f5db1aa5c7cff47d2db5c6d5395d0b03fed026873f4b7f9741085` |
| runtime lock SHA-256 | `b3c308e04fc071402e14114e0fd43fd59677142f3e51a03bf2276c35b8ab0992` |
| realized dataset SHA-256 | `9ba7707760019915288a87f18b2afa0a7b5a0498fa66f1d41570a3e95bbc49fe` |
| model source SHA-256 (imported path) | `dee99381729988d3d8294293d8dc552cb3d5a4066891c4ab65418ea8c17854f4` |
| runner source SHA-256 | `5a2eda2cad12fcc04af4e722227861f60f60b1aa27e18ec8897393f1d43ee69f` |
| environment SHA-256 | `e891752d630aff92a1ed086c2634f658845f010dd1549267d9b531c8d0ee50ec` |
| command SHA-256 | `a38ee94a830803caa89b70bf794c88b7968c68e98c8f7a392bac93728a0c4d1d` |

### Clean isolated install

The wheelhouse was populated without committing or retaining wheels:

```text
python3 -m pip download --only-binary=:all: --dest <wheelhouse> \
  torch==2.10.0 filelock==3.23.0 fsspec==2026.2.0 jinja2==3.1.6 \
  markupsafe==3.0.3 mpmath==1.3.0 networkx==3.6.1 sympy==1.14.0 \
  typing-extensions==4.15.0
python3 -m venv --clear <venv>
<venv>/bin/python -m pip install --no-index --only-binary=:all: \
  --require-hashes --find-links <wheelhouse> -r ml/camera_coach/requirements.lock
PYTHONPATH=. <venv>/bin/python -m ml.camera_coach.train \
  --config ml/camera_coach/configs/synthetic_dry_run.json \
  --run-dir <new-run-dir>
```

This completed successfully from the temporary wheelhouse in a fresh venv.
The compact receipt is retained at
`/private/tmp/setos-m4-006-clean-install-final.json`; it reports the same lock hash,
sample-order hash, model-initialization hash, and first-step loss as the two
in-place runs:

```json
{
  "status": "pass",
  "lockfile_sha256": "b3c308e04fc071402e14114e0fd43fd59677142f3e51a03bf2276c35b8ab0992",
  "sample_order_sha256": "0091e5e462d4e98ce03fdc826950b0337725f6dfe97ff886240dd86cc9009cdb",
  "model_initialization_sha256": "4ec82bedc5aa25cd5f7e1a1cfdcf6ac8191c3c26cf1cfec4bf05cded4fd8781d",
  "first_step_loss": 0.20278294384479523
}
```

`git diff --check` returned exit 0.  A focused search of the added
Python/config files found no Swift, Core ML, network, or production-route
imports.

An additional candidate-A constructor smoke passed in a temporary run and was
cleaned: first-step loss `0.20293012261390686`, initialization SHA-256
`3c5f30a98f61d9a57d0d580e743bb80e1d880f30536fc53ac27a52c380cfeb86`.

## Judgment calls and bounded gaps

- The default B config keeps required evidence quick on CPU while the runner
  accepts both frozen candidate IDs.  This is not candidate selection.
- Wheelhouse population uses the current installed-compatible dependency
  versions under Torch's declared constraints; the lock records each actual
  wheel hash and the clean install proves those hashes offline.
- The one-step mean-MSE objective and generated tensors are manifest-shaped
  smoke data only; their loss must not be read as model quality.
- The receipt pins the accepted manifest, the actual imported implementation
  path, the runner source, and the lock; the realized dataset hash includes
  the seed and generated tensors so changed-seed drift is visible.
- No real Camera data, rights/consent manifest, preprocessing campaign,
  holdout, multi-seed training campaign, calibration, quality metric,
  checkpoint promotion, Core ML export, iOS routing, device
  latency/thermal result, cloud/server, or production enablement is included.
  Those remain downstream M4 work.
