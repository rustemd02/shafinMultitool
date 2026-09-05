# M4-008 — closed, asset-addressed Camera Coach augmentation policy

Status: `PASS` for the corrective v3 owner and its deterministic replay checks.
This report supersedes the rejected permissive implementation in commit
`5380270`; it does not preserve that API. The committed derivation manifest is
still a zero-record template. No real media, rights-uncleared content, human
labels, locked holdout, candidate model, training run, calibration, export, or
runtime enablement is claimed.

## Implemented boundary

- `ml/camera_coach/data/augmentations.py` is the single owner. A
  `SourceBundle` is constructed only by `make_source_bundle` from a canonical
  v1 record and an exact `asset_id -> encoded bytes` map. The source is checked
  with `tools.dataset.camera_coach_check.validate_record(..., admission=False)`;
  unknown record fields and label IDs therefore fail at the frozen validator.
  Every declared asset is required exactly once, decoded deterministically as a
  one-frame RGB image, and hashed from the supplied bytes. A still also has its
  frozen `media.content_sha256` checked against those actual bytes. Temporal and
  episode records must supply every frame/before-after asset; an anonymous
  single-image call cannot satisfy a grouped record.
- `make_cluster_authority` runs the existing M3-008 media cluster owner over
  every concrete asset in the bundle using temporary files only. The split
  authority is likewise regenerated through M3-008 from the complete source
  bundle and cluster receipt. `make_trusted_schedule` accepts only the exact
  source set, closed job keys/enums, frozen seed/counter assignments, and those
  trusted authority objects. It derives split ownership and all ten protected
  categories (`source_shoot`, `scene`, `person`, `location`, `time`,
  `derivation`, `sequence`, `take`, `device`, `dedup_cluster`) rather than
  accepting caller-supplied family/split/dedup claims.
- `augment` returns a training result, not a derived canonical record. Its
  explicit output retains the immutable source `record_id`, transformed pixels
  for every bound asset, transformed v1 target fields, and lineage. The
  lineage binds source-record hash, actual encoded-asset hashes, decoded input
  and output pixel hashes, source/output target hashes, transform version and
  parameters, seed/counter, current config, schedule, M3 cluster and split
  authorities, every protected family, split owner, and a deterministic
  receipt. `validate_result` requires the same trusted schedule/authority
  objects and replays the source bundle; a forged output with a recomputed
  unkeyed receipt does not validate. Batch validation is non-empty and exact,
  reruns M3 cluster/split generation over every supplied asset, validates every
  scheduled result, rejects duplicate/missing/extra jobs, and independently
  rejects a protected category crossing split owners.
- The configuration digest binds the exact bytes of the frozen label schema,
  runtime contract, M3 cluster schema, split schema, explicit remap authority,
  schedule authority, pixel codec, and eligible split owners. Changing any of
  those authorities changes the bound configuration digest.
- Horizontal flip is the only non-identity transform. Its explicit remap
  authority covers the three frozen left/right action pairs and three frozen
  verifier pairs at global, per-issue, selected, verification, and episode
  locations, plus every tracked normalized top-left subject region. The pixel
  operation reverses RGB pixels per row for every grouped asset. The exact
  full-precision geometry involution is checked; no rounding or deletion-based
  oracle is used. The v1 record does not carry model scalar vectors, logits,
  masks, or continuous deltas; those downstream contract features are not
  accepted as caller payloads or silently copied as stale features and remain
  outside this owner.
- Photometric policy is deliberately identity-only. Any non-identity
  photometric job, including a cosmetic “keep” or lighting patch, rejects with
  `requires_reannotation`; no label patch API exists. Crop jobs also reject
  with `requires_reannotation`, because this owner cannot prove non-full-frame
  composition/visibility safety from the frozen source record. No stale
  geometry or issue labels are carried through unsupported operations.
- The repository fixtures are synthetic test inputs only. The checker deep
  copies them, adds fixture-only review/person-family metadata required by the
  existing M3 release splitter, then revalidates each copy with the canonical
  record validator. Their six deterministic PNG asset digests are an explicit
  fixture-only mapping bound into the configuration; a changed fixture byte is
  rejected. The production owner never invents review, person, rights, or
  media truth; a grouped production record fails closed because v1 has no
  per-asset digest until an external M3/source-asset authority is supplied.

## Exact verification

Commands below were run from the M4-008 worktree:

```text
python3 -m py_compile ml/camera_coach/data/augmentations.py ml/camera_coach/data/check_augmentations.py ml/camera_coach/data/__init__.py
PYTHONHASHSEED=1 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-final-seed1.json
PYTHONHASHSEED=777 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-final-seed777.json
cmp -s /tmp/m4-008-final-seed1.json /tmp/m4-008-final-seed777.json
python3 tools/camera_dataset_audit.py --self-test
python3 tools/dataset/camera_coach_check.py --self-test
python3 -m ml.camera_coach.data.check_preprocessing_parity
python3 -m json.tool datasets/camera-coach/v1/derivation-manifest.jsonl >/dev/null
python3 - <<'PY'
from ml.camera_coach.data.augmentations import validate_derivation_manifest
print(validate_derivation_manifest()['manifest_sha256'])
PY
git diff --check
```

The two checker outputs were byte-identical (`dual_seed_cmp=pass`) and both
reported this deterministic evidence:

```json
{"action_catalog_count":26,"action_pair_count":3,"augmentation_config_sha256":"4c45e17bf2c09f54c9ce5982ce6a5baf6792c131c3b26eea5b6677c06cb05aed","cluster_receipt_sha256":"f02f386d3452a43c86a77a6d6550b0b0b8b825eed56bf5516a7eb51ccce39ff1","complete_asset_count":6,"complete_source_record_count":3,"flip_output_pixels_sha256":"3dae527250e395073975b86001420b809ee7b8f74ddd2702109346dcd154d8c2","flip_output_targets_sha256":"dc1161be4ec9eaad3be3326955450e6479f5b79cd4199157c0d5e07ae095f27b","flip_receipt_sha256":"ab1194b57ce62f050bb20b31f2548df5956ddf135307d94e8d2bcd25d5c33809","identity_receipt_sha256":"d4a72f8c26028a36671ab7231f73044c27434c196a0d90993c2672e5bd7e62a7","negative_probe_count":32,"protected_category_count":10,"schedule_sha256":"e742e236e7d77716766f3a550efe7c99ef596c002f2aa300ac9554a789ab53d2","split_manifest_sha256":"580d4bbf6b1238adace00b95bde9511e6c8b851c6cc1a92640a5106d92e2af7b","status":"pass","verifier_catalog_count":23,"verifier_pair_count":3}
```

The exact auxiliary outputs were:

```text
PASS M3-007 camera_dataset_audit self-test
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=90 source_metadata=owner/operator/captured_at/receipt_required
PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap unique_frame_ids=required episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation family_namespace_keyed=category+id same_string_cross_category=allowed same_category_cross_split=rejected quota_key=source+take+derivation one_counted_decision=required quota_batch_records=2 second_counted_decision=rejected non_quota_duplicates=allowed separate_record_admission=non_admitting
PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=90
{"absent_roi_cases":5,"canonical_digest":"2795a72659873d369581b686f29d3fe0b70aa7513db98a28374de3cdb581f26a","case_count":50,"case_image_digest_count":50,"contract_version":"setcompositionnet.v1","mirrored_cases":25,"orientation_counts":{"down":6,"downMirrored":6,"left":6,"leftMirrored":6,"right":6,"rightMirrored":6,"up":7,"upMirrored":7},"source":"lcg_bgra_u8.v1","source_dimension_formula":{"height":"2 + (index * 5 % 8)","width":"2 + (index * 5 % 7)"},"source_dimension_summary":{"aspect_ratio_max":4.0,"aspect_ratio_min":0.2222222222222222,"height_max":9,"height_min":2,"unique_aspect_ratios":36,"unique_dimension_pairs":50,"unique_heights":8,"unique_widths":7,"width_max":8,"width_min":2},"status":"pass","swift_image_digest":"962ee64634f9ccb52d91971fa247e141e7800014609963c54e123b2c225c49a1","tolerance":1e-06}
42047b8ea073d1749b592885966cc1563663c632ec5c119c391d75d615f36714
```

The focused checker covers every independent directional oracle location,
exact full-precision double-flip semantics and pixels across the temporal and
episode bundles, canonical source validation, unknown record/label IDs,
unknown/reordered/duplicate manifest data, bool/non-finite/range failures,
blocked photometric/crop operations, source media hash mismatch, missing and
extra grouped assets, one-asset grouped output, forged/rehashed output,
forged split/family/config claims, changed seed/counter/spec, schedule
authority mismatch, incomplete/duplicate/extra/empty batches, grouped
production asset-authority rejection, and manifest canonical/hash failures.
It exercises 32 negative probe scenarios.

## Scope, judgments, and non-claims

The changed scope is exactly the five M4-008-owned files: the explicit
augmentation owner, focused self-check, data export surface, zero-record
derivation-manifest header, and this evidence report. The principal judgment
is to support only horizontal flip and identity photometric work until full
reannotation/proof exists; crop and all non-identity photometric operations
remain fail-closed. The result is a training-envelope contract, not dataset
admission: no canonical derived records or real media are generated.

This work does not claim image-quality improvement, model quality, fairness,
split balance, rights approval, production readiness, feature-vector/logit/mask
augmentation, training, calibration, Core ML export, candidate selection, or
iOS/runtime enablement. It also does not inspect or synthesize locked-test
records. Multi-asset production admission depends on the existing M3-008
per-asset cluster/split authority; an aggregate v1 record media hash alone is
not treated as a bridge for grouped pixels. Because no such external
per-asset authority is committed in this repository, grouped production
bundles currently fail closed with `requires_external_asset_authority`; adding
that source/M3 contract is required before production grouped augmentation.
A production record lacking M3-required review/family information also fails
closed.

Final owned-file line counts at verification were:

```text
1239 ml/camera_coach/data/augmentations.py
 361 ml/camera_coach/data/check_augmentations.py
  67 ml/camera_coach/data/__init__.py
   1 datasets/camera-coach/v1/derivation-manifest.jsonl
```

The implementation is intentionally explicit rather than a generic recursive
transformer; the larger owner line count includes the asset/authority/replay
trust boundary. Known limit: ordinary Python float arithmetic can make some
full-precision normalized rectangles non-involutive, and those inputs reject
with `requires_reannotation` instead of being rounded. The positive fixture
uses binary-exact geometry values.
