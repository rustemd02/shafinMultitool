# M3-008 protected deterministic split evidence

Status: tooling complete for the bounded M3-008 splitter layered on the
corrected M3-007 cluster receipt. This is not a production dataset-quality,
label-quality, or holdout-quality claim. The fixture writes only temporary
synthetic PNGs and metadata; no raw media, labels, or external data are stored
in Git.

## Contract and implementation

- [`tools/camera_dataset_audit.py`](../tools/camera_dataset_audit.py) now loads
  an unassigned metadata-only split projection and a validated M3-007 cluster
  receipt. It requires admissible rights (`approved` or `fixture_only`) and a
  resolved review status, rejects preassigned splits, duplicate IDs, malformed
  or missing protected IDs, conflicting family declarations, raw-media paths,
  candidate/model fields, and assets absent from the cluster receipt.
- Protected connected components union source shoot, scene, person, location,
  time, derivation, optional take/device, sequence, and dedup-cluster families.
  Components are assigned independently within explicit `organic` and
  `synthetic` buckets to exactly `train`, `calibration`, or `locked_test`.
  Sequence families resolve against the M3-007 receipt and cannot be split.
- Assignment order is a SHA-256 score over the explicit seed, bucket, and
  stable component ID. Input records are sorted before all hashes and output
  rows; changing a seed may change assignments but cannot create a leak.
  Indivisible component targets use deterministic largest remainder and are
  reported separately per bucket.
- [`datasets/camera-coach/v1/split-manifest-schema.json`](../datasets/camera-coach/v1/split-manifest-schema.json)
  is a closed Draft 2020-12 schema. The existing repository `jsonschema`
  dependency is reused through one generic validator owner. Receipts expose
  only opaque record IDs, component IDs, family hashes, counts, and stable
  configuration/input/manifest SHA-256 values; locked-test labels/content and
  raw paths are not emitted.

## Synthetic verification

[`tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py`](../tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py)
creates exact, crop, color, blurred-near, far, and temporal-frame images in a
temporary directory. It verifies M3-007 and M3-008 together, including each
protected-family leakage case: source shoot, scene, person, location, time,
derivation, dedup cluster, and sequence. Shared protected families are
co-located in one component and every accepted receipt reports zero leakage.
It also exercises bucket isolation, changed-seed integrity, duplicate and
missing IDs, rights/review/bucket/split rejection, absent cluster assets,
  non-finite/bool/wrong-type parameters, raw-media path rejection,
  closed-schema extra/missing/wrong-type and non-finite negatives, and CLI
  order independence under two hash seeds.

```text
$ python3 tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py
M3-008 split seed=1 output_sha256=be56c2ecc2cee97383b4abc0859534d3c82692cacf0d9d62440f2226b55cd085 seed5_output_sha256=d6e742e899695ea1f82d8da486a64b372aeed8dd695938f9b549c879b45f8b6c cli_sha256=99589a1deb5189ff13cd372d6d118551993ad99fa576af4eab7fbc01c040a28b input_sha256=96681925857c42083d540bdb5839bfa8ccb2f7b42b907b1eb9de3d117967fb5e components=3 per_split={"calibration":{"buckets":{"organic":{"component_count":1,"record_count":2},"synthetic":{"component_count":0,"record_count":0}},"component_count":1,"record_count":2},"locked_test":{"buckets":{"organic":{"component_count":0,"record_count":0},"synthetic":{"component_count":0,"record_count":0}},"component_count":0,"record_count":0},"train":{"buckets":{"organic":{"component_count":1,"record_count":1},"synthetic":{"component_count":1,"record_count":1}},"component_count":2,"record_count":2}}
PASS M3-007 fixture exact_sha near_crop_color near_blur far_discriminated sequence_family input_order_independent malformed_rejected rights_required media_map_conflict schema_round_trip ssim_review_only typed_parameters phash64 decompression_bomb_rejected M3-008 split_components protected_family_leakage bucket_isolation changed_seed_integrity split_schema_negative_cases
```

The fixture's CLI subprocess runs the same seed and ratios with
`PYTHONHASHSEED=1` and `PYTHONHASHSEED=5`; the output bytes match exactly and
have `cli_sha256=99589a1deb5189ff13cd372d6d118551993ad99fa576af4eab7fbc01c040a28b`.
The API reverse-input run is byte/object-identical. `seed=1` and `seed=5`
produce different fixture assignment receipts while preserving the same record
set and `cross_split_leak_count=0`.

## Verification commands

```text
$ python3 tools/camera_dataset_audit.py --self-test
PASS M3-007 camera_dataset_audit self-test
$ python3 tools/dataset/camera_coach_check.py --self-test
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=90 source_metadata=owner/operator/captured_at/receipt_required
PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap unique_frame_ids=required episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation family_namespace_keyed=category+id same_string_cross_category=allowed same_category_cross_split=rejected quota_key=source+take+derivation one_counted_decision=required quota_batch_records=2 second_counted_decision=rejected non_quota_duplicates=allowed separate_record_admission=non_admitting
PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=90
$ python3 -m py_compile tools/camera_dataset_audit.py tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py
PASS
$ python3 -m json.tool datasets/camera-coach/v1/cluster-schema.json >/dev/null
PASS
$ python3 -m json.tool datasets/camera-coach/v1/split-manifest-schema.json >/dev/null
PASS
$ git diff --check
PASS
```

The fixture invokes the repository-owned `Draft202012Validator` for both
positive receipts and extra/missing/wrong-type/non-finite negative cases. No
new package, model, network access, raw/user media, labels, or simulator was
used. Pairwise M3-007 image work remains the deliberately bounded local
O(n²) audit; M3-008 adds no model or ANN dependency. Component indivisibility
means realized counts can differ from requested ratios, which is reported in
the receipt rather than hidden by cross-bucket substitution.
