# M3-008 protected deterministic split evidence

Status: tooling complete for the bounded M3-008 splitter layered on the
corrected M3-007 cluster receipt. This is not a production dataset-quality,
label-quality, or holdout-quality claim. The fixture writes only temporary
synthetic PNGs and metadata; no raw media, labels, or external data are stored
in Git.

## Contract and implementation

- [`tools/camera_dataset_audit.py`](../tools/camera_dataset_audit.py) now loads
  an explicitly versioned (`camera-split-input-v1` / `v1.0.0`) unassigned
  metadata-only split projection and a validated M3-007 cluster receipt. It
  requires admissible rights (`approved` or `fixture_only`) and a complete
  release-review vote/adjudication history validated by the repository's
  `camera_coach_check.py` contract (cached once per process). It rejects
  status-only or unresolved review, preassigned splits, duplicate IDs,
  malformed or missing protected IDs, conflicting family declarations,
  raw-media/content/label payloads, candidate/model fields, and assets absent
  from the cluster receipt. A closed per-object allowlist also rejects unknown
  container/header, record, provenance, capture, media, sequence/frame,
  review, vote, or adjudication keys.
- `SplitRecord` construction is parser-only: the public constructor is blocked,
  and parser output carries a private immutable admission object containing the
  canonical review JSON, rights/status values, and a SHA-256 binding of the
  complete record projection (record ID, assets, bucket, families, rights,
  status, and full review evidence). At every public builder boundary the
  canonical JSON is parsed and checked, the authoritative closed review and
  release validator is rerun, the rights allowlist is rerun, and the complete
  binding digest is recomputed. Replay onto another record, mutation, omitted
  or status-only evidence, denied/unreviewed evidence, non-canonical JSON, and
  arbitrary digest replacement are rejected; a status string cannot stand in
  for release evidence.
- Protected connected components union source shoot, scene, person, location,
  time, derivation, optional take/device, sequence, and dedup-cluster families.
  Components are assigned independently within explicit `organic` and
  `synthetic` buckets to exactly `train`, `calibration`, or `locked_test`.
  Sequence families resolve against the M3-007 receipt and cannot be split.
- Assignment order is a SHA-256 score over the declared algorithm ID, explicit
  seed, bucket, and stable component ID, with deterministic largest-remainder
  target counts supplied as the assignment function input. Input records are
  sorted before all hashes and output rows; changing a seed may change
  assignments but cannot create a leak. Indivisible component targets are
  reported separately per bucket. Semantic receipt validation requires every
  `(protected category, family hash)` to have exactly one component and one
  bucket owner, in addition to zero cross-split ownership.
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
derivation, sequence, take, device, and dedup cluster. Shared protected families are
co-located in one component and every accepted receipt reports zero leakage.
JSONL uses a header-only first row; an inline `entries` value in a list/JSONL
header is rejected rather than validated and discarded.
It also exercises bucket isolation, changed-seed integrity, duplicate and
missing IDs, rights/review/bucket/split rejection, absent cluster assets,
non-finite/bool/wrong-type parameters, explicit JSON/JSONL header requirements,
raw-media/content/label rejection, closed-schema extra/missing/wrong-type and
non-finite negatives, and CLI order independence under two hash seeds. Review
fixtures cover valid dual review, valid adjudication, conflicting votes,
rejected adjudication, incomplete scope, and bare status. Receipt tamper cases
cover retained/recomputed hashes, count drift, membership drift, cross-split
family-hash drift, and moving a whole component after recomputing all counts and
hashes; the last case is rejected by recomputing the seeded assignment. Unknown
metadata fixtures cover every supported nested object plus container/header
fields, including `annotation`, `ground_truth`, `target`, `caption`,
`raw_bytes`, and `image_base64`. Family-hash tamper fixtures cover duplicate
ownership across components within one bucket, and duplicate ownership across
organic and synthetic buckets.

```text
$ python3 tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py
M3-008 split seed=1 output_sha256=0786e4b4d4194c077f3007e4bab8a930b49a8cab644f8cfba98db76398767874 seed5_output_sha256=52814979b1fb0eb0529563b6d8a670379c62c0b4f383ab3918a3b0189cc63071 cli_sha256=d606a1de2ff128d0a1666cbe5e3a61f91a4805c5a33f3593c05ef0a184ce4346 input_sha256=043df9257c2bff5950180dfecdd7a9e6dd881fc3b8e042cf325280383526ac12 components=3 per_split={"calibration":{"buckets":{"organic":{"component_count":1,"record_count":2},"synthetic":{"component_count":0,"record_count":0}},"component_count":1,"record_count":2},"locked_test":{"buckets":{"organic":{"component_count":0,"record_count":0},"synthetic":{"component_count":0,"record_count":0}},"component_count":0,"record_count":0},"train":{"buckets":{"organic":{"component_count":1,"record_count":1},"synthetic":{"component_count":1,"record_count":1}},"component_count":2,"record_count":2}}
PASS M3-007 fixture exact_sha near_crop_color near_blur far_discriminated sequence_family input_order_independent malformed_rejected rights_required media_map_conflict schema_round_trip ssim_review_only typed_parameters phash64 decompression_bomb_rejected M3-008 split_components protected_family_leakage bucket_isolation changed_seed_integrity split_schema_negative_cases closed_input_topology review_history_contract seeded_assignment_receipt_tamper family_hash_owner_tamper split_admission_boundary admission_revalidation jsonl_header_representation header_value_validation
```

The fixture's CLI subprocess runs the same seed and ratios with
`PYTHONHASHSEED=1` and `PYTHONHASHSEED=5`; the output bytes match exactly and
have `cli_sha256=d606a1de2ff128d0a1666cbe5e3a61f91a4805c5a33f3593c05ef0a184ce4346`.
The API reverse-input run is byte/object-identical. `seed=1` and `seed=5`
produce different fixture assignment receipts while preserving the same record
set and `cross_split_leak_count=0`. The accepted receipt has three components,
four records, one organic component in calibration (two records), one organic
component in train (one record), and one synthetic component in train (one
record); locked-test is empty for this indivisible four-record fixture.

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

The same fixture also runs `validate_split_output` after closed-schema
validation; its semantic pass recomputes the receipt, config, and input hashes,
component IDs and membership, assignment/target order, all aggregate/per-split
bucket/family/dedup/sequence counts, and protected-family ownership. This
prevents a component move from being hidden by recomputed receipt hashes.

Header validation additionally requires `manifest_type=camera_split_input`,
rejects non-string or alternate values, and checks an optional
non-bool-integer `record_count` exactly against parsed records. Parser-only
admission rejects caller-created denied, unreviewed, or status-only records
before any split receipt can be emitted.

The fixture invokes the repository-owned `Draft202012Validator` for both
positive receipts and extra/missing/wrong-type/non-finite negative cases. No
new package, model, network access, raw/user media, labels, or simulator was
used. Pairwise M3-007 image work remains the deliberately bounded local
O(n²) audit; M3-008 adds no model or ANN dependency. Component indivisibility
means realized counts can differ from requested ratios, which is reported in
the receipt rather than hidden by cross-bucket substitution.
