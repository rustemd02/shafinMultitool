# M4-008 — Camera Coach augmentation trust boundary

Status: `PARTIAL`.  This correction supersedes rejected commits `5380270`
and `1d704b2` and hard-disables production M3 authority loading.  The
repository has no authenticated production M3 source-set artifact, so only a
private fixture-only authority path is executable here.  The derivation
manifest remains a zero-record template.

No real media, rights-uncleared content, human labels, locked holdout,
candidate model, training run, calibration, export, selection, runtime
enablement, or iOS change is claimed.

## Implemented boundary

- Public `load_m3_authority` is not exported from `ml.camera_coach.data` and
  always raises.  Caller-provided records, seeds, ratios, receipts, or source
  subsets can never issue a production authority.
- Private `_load_fixture_authority` is test-only by contract and accepts only
  the exact three pinned fixture record IDs, with split `fixture`, source kind
  `synthetic_fixture`, rights disposition `fixture_only`, and the exact pinned
  six-asset SHA-256 map.  It copies and replays the M3 receipts, but its
  resulting authority kind is permanently `fixture`; mixed train/fixture
  provenance and caller-selected fixture seed/ratios/receipts reject.
- The future production contract is named
  `camera-m3-redacted-train-calibration-view-v1`: an independently
  authenticated redacted view derived from the complete frozen M3 receipt,
  containing only train/calibration record and asset authority.  It must bind
  artifact, complete-receipt, cluster, split, record/asset, and signature
  fields; it does not require locked-test records or media.  No issuer or
  verifier exists in this repository, so this view is a contract only.
- The fixed schedule derives only from the immutable authority object.  Its
  body includes `authority_kind` and each source includes `source_split`.
  Every emitted lineage retains both `source_split` and `split_owner`; fixture
  provenance cannot masquerade as train or calibration.
- The checker issues synthetic receipts independently through the M3 owner and
  its own metadata projection.  It does not call augmentation `_m3_items` or
  `_m3_records_from_records`, avoiding a production/checker circular oracle.

## Asset and transform boundary

- `make_source_bundle` requires an exact asset-ID-to-encoded-byte map for every
  still, temporal, or episode asset.  Actual bytes are hashed and decoded;
  caller-declared media hashes cannot override them.  Production bundles fail
  closed without the unavailable authenticated authority, including stills.
- Existing M3 Pillow is reused with runtime pin `12.2.0`; each encoded asset is
  capped at 8 MiB and 4096×4096/`262,144` pixels, while each grouped bundle is
  capped at 16 assets, 16 MiB encoded, and 512×512 aggregate pixels/output
  bytes before nested-list materialization or result validation.  Truncation,
  decompression bombs, multiframe media, and non-normalized EXIF orientation
  reject before a training result exists.
- Horizontal flip remains explicit and exhaustive for frozen directional
  action/verifier IDs, all label locations, episode fields, and normalized
  top-left subject regions.  Exact representable geometry double-flips; values
  that lose an IEEE-754 bit reject rather than round.
- Photometric policy is identity-only.  Non-identity photometric and all crop
  specifications reject with `requires_reannotation`; no label patch API
  exists.  Grouped transforms always transform every identified asset.
- `validate_result` bounds untrusted output and replays the transform from the
  source bundle and trusted schedule.  `validate_lineage_batch` requires the
  authority's complete source and job sets, replays M3 over every actual asset,
  and rejects duplicate, missing, extra, empty, or cross-split family jobs.
- Output validation checks exact HWC/RGB cell and scalar types/ranges and exact
  replay tree shape before hashing; oversized strings, unknown nested payloads,
  and over-cardinality iterables reject without canonical serialization.
- `ml.camera_coach.data` lazily exports preprocessing only; importing the
  package does not import Pillow or the unavailable augmentation authority.

## Frozen bindings

```text
augmentation_config_sha256=cd6bc245669ea9de189c12f4428734d436a7fe01f8000b862c0ed669670e6b8b
schedule_authority_sha256=9b916392542ffc2145f4e19e6251254a8f9c6dfbfe31eb7011ecfb8d29a93d18
cluster_receipt_sha256=f02f386d3452a43c86a77a6d6550b0b0b8b825eed56bf5516a7eb51ccce39ff1
split_manifest_sha256=580d4bbf6b1238adace00b95de9511e6c8b851c6cc1a92640a5106d92e2af7b
manifest_sha256=40b99ecec2af343d8aff1eb8e4e66dca40d353ca08fca008baf118068e664e73
```

## Exact verification

All commands ran from the M4-008 worktree:

```text
python3 -m py_compile ml/camera_coach/data/augmentations.py ml/camera_coach/data/check_augmentations.py ml/camera_coach/data/__init__.py
ruff check ml/camera_coach/data/augmentations.py ml/camera_coach/data/check_augmentations.py ml/camera_coach/data/__init__.py
PYTHONHASHSEED=1 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-correction-seed1.json
PYTHONHASHSEED=777 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-correction-seed777.json
cmp -s /tmp/m4-008-correction-seed1.json /tmp/m4-008-correction-seed777.json
python3 - <<'PY'
import sys
import ml.camera_coach.data
assert "PIL" not in sys.modules
assert "ml.camera_coach.data.augmentations" not in sys.modules
print("package_import_without_augmentation=pass")
PY
python3 tools/camera_dataset_audit.py --self-test
python3 tools/dataset/camera_coach_check.py --self-test
python3 -m ml.camera_coach.data.check_preprocessing_parity
python3 -m json.tool datasets/camera-coach/v1/derivation-manifest.jsonl >/dev/null
python3 - <<'PY'
from ml.camera_coach.data.augmentations import validate_derivation_manifest
print('manifest_sha256=' + validate_derivation_manifest()['manifest_sha256'])
PY
git diff --check
```

Results:

```text
py_compile=pass
All checks passed!
dual_seed=pass; output bytes=983
package_import_without_augmentation=pass
PASS M3-007 camera_dataset_audit self-test
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=90 source_metadata=owner/operator/captured_at/receipt_required
PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap unique_frame_ids=required episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation family_namespace_keyed=category+id same_string_cross_category=allowed same_category_cross_split=rejected quota_key=source+take+derivation one_counted_decision=required quota_batch_records=2 second_counted_decision=rejected non_quota_duplicates=allowed separate_record_admission=non_admitting
PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=90
preprocessing parity status=pass case_count=50 case_image_digest_count=50 mirrored_cases=25 canonical_digest=2795a72659873d369581b686f29d3fe0b70aa7513db98a28374de3cdb581f26a swift_image_digest=962ee64634f9ccb52d91971fa247e141e7800014609963c54e123b2c225c49a1
manifest_sha256=40b99ecec2af343d8aff1eb8e4e66dca40d353ca08fca008baf118068e664e73
diff_check=pass
```

Both checker runs produced the same canonical JSON and reported:

```json
{"action_catalog_count":26,"action_pair_count":3,"augmentation_config_sha256":"cd6bc245669ea9de189c12f4428734d436a7fe01f8000b862c0ed669670e6b8b","cluster_receipt_sha256":"f02f386d3452a43c86a77a6d6550b0b0b8b825eed56bf5516a7eb51ccce39ff1","complete_asset_count":6,"complete_source_record_count":3,"flip_output_pixels_sha256":"3dae527250e395073975b86001420b809ee7b8f74ddd2702109346dcd154d8c2","flip_output_targets_sha256":"dc1161be4ec9eaad3be3326955450e6479f5b79cd4199157c0d5e07ae095f27b","flip_receipt_sha256":"e34c6be0a6d71b8449657d35348fada05e1d8df0c8b47b9a19e3850b956e109a","identity_receipt_sha256":"b21e11e54ebea56da7deeeef0cce7c9ad32440f2c8120bc7165828d93a12515e","job_count":6,"negative_probe_count":63,"protected_category_count":10,"schedule_sha256":"9534b79f8845b9183e441ae9ba2ded68aea3b88baf998f05643e41f9fe7f51ef","split_manifest_sha256":"580d4bbf6b1238adace00b95bde9511e6c8b851c6cc1a92640a5106d92e2af7b","status":"pass","verifier_catalog_count":23,"verifier_pair_count":3}
```

The 63 negative probes include the reviewer attacks: public production-loader
rejection; fixture/production separation; mismatched record/media bytes;
missing, extra, or one-of-many grouped assets; forged/rehashed output,
families, split, seed, counter, and transform; unknown record/label fields;
alternate/partial schedule and authority calls; immutable authority/schedule
and exported-config mutation; arbitrary 1×1 bytes; EXIF 90°; truncation;
encoded, width, height, and expanded-pixel caps; multiframe media;
bool/non-finite/range/unknown transforms; empty/incomplete/duplicate/extra
lineage batches; cross-split lineage and authority mismatch; mixed
train/fixture provenance; caller-selected fixture seed/ratios; aggregate
bundle/output caps; exact RGB cell/channel validation including a 1 MB string
attack; generator/iterable over-cardinality rejection; and manifest
reorder/hash/duplicate records.

## Scope, judgments, and gaps

Changed scope is exactly the five owned files: augmentation owner, focused
self-check, data exports, zero-record derivation manifest, and this evidence.
The corrective judgment is to delete the self-issued production authority
surface and retain only a fixture test path until M3 supplies the authenticated
redacted view.  No production grouped-authority success is claimed.

Remaining external prerequisites are concrete: M3 must supply and verify the
complete frozen cluster/split/source-set receipt plus the redacted
train/calibration artifact; environment packaging must provide the existing
Pillow `12.2.0` runtime (the out-of-scope requirements lock does not contain
Pillow).  No model-quality or production-enablement evidence exists.

Final pre-commit line counts:

```text
1549 ml/camera_coach/data/augmentations.py
544 ml/camera_coach/data/check_augmentations.py
21 ml/camera_coach/data/__init__.py
1 datasets/camera-coach/v1/derivation-manifest.jsonl
166 docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m4/M4-008-augmentation-policy.md
```
