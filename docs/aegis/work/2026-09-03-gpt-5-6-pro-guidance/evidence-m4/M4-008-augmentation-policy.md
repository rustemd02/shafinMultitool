# M4-008 — deterministic Camera Coach augmentation policy

Status: `PASS` for the revised closed owner and replayable training-envelope
checks. This report supersedes the rejected permissive implementation. The
derivation manifest remains a zero-record template; no real media, rights
uncleared content, locked holdout, human labels, candidate model, training,
calibration, export, or runtime enablement is claimed.

## Policy and implementation

- `ml/camera_coach/data/augmentations.py` is the single explicit owner. It
  validates every source with
  `tools.dataset.camera_coach_check.validate_record(..., admission=False)` and
  never fabricates or returns a canonical derived record. `augment` returns a
  training result retaining the source `record_id`, transformed pixels,
  explicit target/feature fields, and lineage.
- Horizontal flip uses an exhaustive frozen v1 action/verifier pair list and
  remaps global, per-issue, selected, verification, and episode action fields;
  tracked normalized top-left geometry; paired edge-pressure scalars;
  signed horizontal balances/deltas; action logits; ROI masks; and the
  contract's mirror state. Quarter-turn orientation remains unchanged because
  the frozen contract stores it separately from `mirroring_flag`. Geometry is
  admitted only when the full-precision mirror is an exact involution;
  otherwise it fails closed with `requires_reannotation`.
- Photometric policy is identity-only. Every non-identity operation, including
  a cosmetic or lighting label patch, fails closed with
  `requires_reannotation`; no label patches are accepted. Crop specs are
  parsed and ranged but every crop currently fails closed with
  `requires_reannotation`, because this owner cannot prove non-full-frame
  label/composition safety from the frozen record alone.
- Pixels are mandatory and hashed from the actual canonical HWC RGB bytes.
  `validate_result` replays the source record, input pixels, explicit source
  targets, and canonical spec before comparing output bytes, targets, hashes,
  and receipt. Lineage binds source-record/pixel/target hashes, policy/config,
  seed/counter, source ID, all protected family categories, and split owner.
  Batch validation rejects replay/counter collisions and a per-category family
  crossing split owners. The manifest binds truthful v2 policy/lineage IDs and
  contains zero admitted records.

## Verification

Exact commands run from the M4-008 worktree:

```text
python3 -m py_compile ml/camera_coach/data/augmentations.py ml/camera_coach/data/check_augmentations.py ml/camera_coach/data/__init__.py
PYTHONHASHSEED=1 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-augment-1.json
PYTHONHASHSEED=777 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-augment-777.json
cmp -s /tmp/m4-008-augment-1.json /tmp/m4-008-augment-777.json
python3 tools/camera_dataset_audit.py --self-test
python3 -m ml.camera_coach.data.check_preprocessing_parity
python3 -m json.tool datasets/camera-coach/v1/derivation-manifest.jsonl >/dev/null
python3 - <<'PY'
from ml.camera_coach.data.augmentations import validate_derivation_manifest
print(validate_derivation_manifest()['manifest_sha256'])
PY
git diff --check
```

Both hash-seed outputs were byte-identical and reported `status=pass`:

```json
{"action_catalog_count":26,"action_pair_count":3,"canonical_source_record_count":3,"config_sha256":"02eb16c99639035fe01ce51f07a9b5437d6a2c40b5e80427e4155e6d5927f28e","dedup_cluster_bound":true,"flip_output_pixels_sha256":"6848ffeae705119b6d8744b1ae2602c37fb5736c506d70f3315d8fd270ef2144","flip_output_targets_sha256":"6911133378499de31e4c54a6a7c977b8bc5163c257d04e55e3ebb309db4fc7bc","flip_receipt_sha256":"177c68c6e08b10f160ae1258fe3010687ae570d6bcebc28013f21cb3a98ea77b","identity_receipt_sha256":"a30008d9c4ccdfcc0a61efb09d2601ef60fd648fa33771781b426dbca27882ff","manifest_sha256":"53b9a262ccdde2fa1dcc0714f775d151cac62116b08decd4802b47247e1930f6","protected_category_count":10,"status":"pass","temporal_person_family_count":2,"temporal_sequence_bound":true,"verifier_catalog_count":23,"verifier_pair_count":3}
```

The self-check independently covers canonical validation of all three frozen
fixtures; every frozen left/right pair and all exercised label locations;
double-flip semantic/geometry/scalar/mask round-trip; unknown IDs/keys;
bool/non-finite/range rejection; lighting-sensitive photometric rejection and
identity-only behavior; labeled crop rejection; actual-pixel replay against
forged/rehashed output; source ID/config/seed/counter binding; protected
family/split inheritance (including two persons, sequence, and dedup-cluster
bindings); replay/counter and cross-category split checks; and
manifest unknown/reordered/duplicate/hash failures.

Adjacent checks produced:

```text
PASS M3-007 camera_dataset_audit self-test
2795a72659873d369581b686f29d3fe0b70aa7513db98a28374de3cdb581f26a
```

The first line is the audit self-test result; the second is the preprocessing
parity check's canonical digest (its run reported `status=pass`, 50 cases, 25
mirrored cases, five absent-ROI cases, and eight orientation counts). The
manifest validator printed:

```text
53b9a262ccdde2fa1dcc0714f775d151cac62116b08decd4802b47247e1930f6
```

## Scope, judgments, and non-claims

Changed scope is limited to the explicit owner, focused self-check, data
exports, zero-record manifest header binding, and this evidence report. The
deliberate judgment is to admit only horizontal flip plus identity photometric
envelopes; all non-identity photometric and crop operations wait for full
reannotation/safety proof. No media loader/writer is provided, and this work
does not establish image-quality gains, label correctness beyond the frozen
contracts and replay invariants, fairness, split balance, model quality,
training readiness, or production/runtime readiness.

Final owned-file line counts are `augmentations.py=807`,
`check_augmentations.py=386`, `data/__init__.py=61`,
`derivation-manifest.jsonl=1`, and this report `=110`.

Known limit: horizontal geometry uses ordinary full-precision Python floats;
non-involutive float pairs are rejected rather than rounded or silently
accepted. The self-check's exact double-flip positive case uses binary-exact
normalized values, and a high-precision non-involutive case is a negative
probe. No quantization or deletion-based oracle is used.
