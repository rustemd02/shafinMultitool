# M4-008 — Camera Coach augmentation trust boundary

Status: `PARTIAL` for production closure; the v4 implementation and focused
checks pass, but this repository contains no externally issued production M3
cluster/split artifact or signed dataset-admission source-set receipt.  The
module therefore accepts production grouped media only when that external
authority is injected, and never self-issues one.  This report supersedes the
rejected implementations in commits `5380270` and `1d704b2`; the committed
derivation manifest remains a zero-record template.

No real media, rights-uncleared content, human labels, locked holdout,
candidate model, training run, calibration, export, selection, runtime
enablement, or iOS change is claimed.

## Implemented boundary

- `load_m3_authority(records, cluster_receipt, split_receipt)` is the only
  authority injection path.  It accepts canonical v1 records through the
  existing `validate_record(..., admission=False)` owner, validates exact M3
  cluster/split schemas, checks that both receipts cover exactly the supplied
  record and asset set, recomputes the split from the canonical projections,
  rejects locked-test assignments, and stores source records/receipts as
  canonical bytes plus frozen tuples.  It does not choose ratios, jobs, seeds,
  counters, or a partial batch.
- `make_source_bundle` requires an exact `asset_id -> encoded bytes` map.  A
  still is bound to its frozen aggregate `media.content_sha256`; grouped
  records require the injected M3 per-asset digest authority unless they are
  the six pinned synthetic fixtures.  Every supplied byte is hashed before
  decode, decoded through the existing M3 Pillow owner as one-frame RGB8 HWC,
  and checked against the authoritative per-asset digest.  Missing, extra,
  mismatched, truncated, multiframe, oversized, decompression-bomb, or
  non-normalized EXIF-oriented assets fail closed.  Encoded bytes are capped at
  8 MiB; dimensions at 4096×4096 and 16,777,216 pixels.
- `make_trusted_schedule(authority)` is the sole schedule constructor.  It
  derives every source and exactly two fixed jobs per source (`horizontal_flip`
  and `photometric_identity`) from one immutable authority.  The seed (17),
  counters, job IDs, parameters, and transform order are module-owned; caller
  job lists, ratios, source subsets, and alternate seeds are not accepted.
  Schedule and authority internals are frozen value objects/canonical strings;
  returned receipts/schedules are fresh copies and post-construction mutation
  attempts cannot change replay behavior.
- `augment` returns an explicit training result, never a derived canonical
  record.  It transforms every identified asset in a grouped/temporal bundle,
  retains the source `record_id`, and emits transformed target fields plus
  lineage binding source-record hash, each encoded asset hash, decoded input
  pixels, output pixels, source/output target hashes, transform parameters,
  fixed seed/counter, policy/config, external authority, schedule, all ten
  protected family categories, split owner, and a deterministic receipt.
  `validate_result` replays the fixed assignment from the supplied immutable
  authority and actual bundle bytes; a forged output with a recomputed
  unkeyed receipt is rejected.
- `validate_lineage_batch` rejects empty, incomplete, duplicate, or extra
  source/result sets; re-runs M3 clustering and splitting over every actual
  asset; validates every result; and maintains a category/value-to-split
  registry for `source_shoot`, `scene`, `person`, `location`, `time`,
  `derivation`, `sequence`, `take`, `device`, and `dedup_cluster`.  A family
  crossing split owners is rejected.  One grouped production fixture proves
  the non-circular external-authority path and all assets are replayed.
- Horizontal flip uses an explicit exhaustive table for all frozen left/right
  action/verifier pairs at global, per-issue, selected, verification, and
  episode locations, plus every tracked normalized top-left subject region.
  Exact representable geometry values round-trip twice; values whose IEEE-754
  complement would lose a low-order bit reject with `requires_reannotation`
  rather than being rounded.  The v1 records do not contain model-derived
  scalar vectors, logits, masks, or continuous deltas, so those are not
  accepted or silently copied as stale targets.  EXIF orientation is rejected
  because the frozen preprocessing contract requires ImageIO orientation to be
  applied exactly once before model coordinates are defined; no storage-pixel
  flip is allowed to guess displayed coordinates.
- Photometric policy is identity-only.  Non-identity photometric and all crop
  specifications reject with `requires_reannotation`; there is no label patch
  API and no cosmetic keep/lighting-label mutation path.
- `AUGMENTATION_CONFIG` is recursively immutable.  Its pinned digest binds the
  exact label schema, runtime contract, M3 schemas, explicit remap/schedule
  authorities, protected categories, decoder name/version, orientation
  semantics, resource caps, and fixture hashes.  Runtime Pillow must be the
  existing M3 decoder version `12.2.0`; a mismatch fails closed.  No new
  dependency or unpinned lock entry was added; `ml/camera_coach/requirements.lock`
  is outside this slice and does not contain Pillow, so production environment
  packaging remains an external prerequisite.

## Exact verification

All commands below were run from the M4-008 worktree:

```text
python3 -m py_compile ml/camera_coach/data/augmentations.py ml/camera_coach/data/check_augmentations.py ml/camera_coach/data/__init__.py
ruff check ml/camera_coach/data/augmentations.py ml/camera_coach/data/check_augmentations.py ml/camera_coach/data/__init__.py
PYTHONHASHSEED=1 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-v4-seed1.json
PYTHONHASHSEED=777 python3 -m ml.camera_coach.data.check_augmentations > /tmp/m4-008-v4-seed777.json
cmp -s /tmp/m4-008-v4-seed1.json /tmp/m4-008-v4-seed777.json
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
PASS M3-007 camera_dataset_audit self-test
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=90 source_metadata=owner/operator/captured_at/receipt_required
PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap unique_frame_ids=required episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation family_namespace_keyed=category+id same_string_cross_category=allowed same_category_cross_split=rejected quota_key=source+take+derivation one_counted_decision=required quota_batch_records=2 second_counted_decision=rejected non_quota_duplicates=allowed separate_record_admission=non_admitting
PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=90
preprocessing parity status=pass case_count=50 case_image_digest_count=50 mirrored_cases=25 canonical_digest=2795a72659873d369581b686f29d3fe0b70aa7513db98a28374de3cdb581f26a swift_image_digest=962ee64634f9ccb52d91971fa247e141e7800014609963c54e123b2c225c49a1
manifest_sha256=58d1b66978f0b1c91dd60b6e56cdb362dd1c26957f59f9157cc2fee8c06cf6fe
diff_check=pass
```

The dual-seed checker output was byte-identical and both runs reported:

```json
{"action_catalog_count":26,"action_pair_count":3,"augmentation_config_sha256":"c54a4c4ace2165a84a17ea4b8670fba8a3159a772ab371751c4a3206b89d4746","cluster_receipt_sha256":"f02f386d3452a43c86a77a6d6550b0b0b8b825eed56bf5516a7eb51ccce39ff1","complete_asset_count":6,"complete_source_record_count":3,"flip_output_pixels_sha256":"3dae527250e395073975b86001420b809ee7b8f74ddd2702109346dcd154d8c2","flip_output_targets_sha256":"dc1161be4ec9eaad3be3326955450e6479f5b79cd4199157c0d5e07ae095f27b","flip_receipt_sha256":"70ffac0e5743c93d26bad6cd74a47da021d3ff55adc51ccac9226108b460da23","identity_receipt_sha256":"136438f4826befe19bfbeff5fbce117db7f784709f155198f14653a426831f56","job_count":6,"negative_probe_count":36,"protected_category_count":10,"schedule_sha256":"aec3158e5b8653d8a6fdb4be87f728b270c1bfba8323e8af03412890f2547c0f","split_manifest_sha256":"580d4bbf6b1238adace00b95de9511e6c8b851c6cc1a92640a5106d92e2af7b","status":"pass","verifier_catalog_count":23,"verifier_pair_count":3}
```

The checker’s 36 negative probes cover the reviewer attacks: mismatched
record/media bytes; missing/extra grouped assets; one-asset temporal output;
forged/rehashed output, split, family, dedup, seed, counter, and transform;
unknown record/label fields; alternate/partial schedule calls; immutable
authority/schedule mutation; exported config and fixture-map mutation;
arbitrary 1×1 fixture bytes; 90° EXIF; truncation; encoded/resource caps;
multiframe input; bool/non-finite/range/unknown transform values; missing
grouped authority; and empty/incomplete/duplicate/extra batch or manifest
records.  Positive coverage includes canonical-valid fixtures, exact
full-bundle replay, deterministic schedule construction, double-flip geometry,
all-assets temporal/episode flips, protected-family replay, and a valid
externally injected grouped production authority.

## Scope, judgments, and non-claims

The changed scope is exactly the five owned files: explicit augmentation owner,
focused self-check, data exports, zero-record derivation-manifest header, and
this evidence report. The main judgment is to delete the prior self-issued
authority/schedule path and require external M3 receipts, while retaining only
horizontal flip and identity photometric jobs. Crop and all non-identity
photometric work remain fail-closed pending full reannotation and proof.

This work does not claim model quality, image-quality improvement, fairness,
split balance beyond replay of a supplied M3 receipt, rights approval,
production admission, feature-vector/logit/mask augmentation, training,
calibration, Core ML export, candidate selection, runtime enablement, or iOS
behavior. No locked-test records are inspected or synthesized. The remaining
external-data limit is concrete: M3-008 currently commits schemas and owner
code, but no production cluster/split receipt or authenticated complete source
set exists in this repository. Until that authority is supplied by the M3/data
owner (with environment packaging for the existing Pillow decoder), grouped
production augmentation remains intentionally unavailable; synthetic fixture
checks are not production evidence.

Final owned-file line counts at this verification:

```text
1301 ml/camera_coach/data/augmentations.py
 372 ml/camera_coach/data/check_augmentations.py
  77 ml/camera_coach/data/__init__.py
   1 datasets/camera-coach/v1/derivation-manifest.jsonl
```
