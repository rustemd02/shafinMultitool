# M3-007 deterministic Camera dedup evidence

Status: tooling complete for the bounded M3-007 audit slice. This is not a
production dataset-quality claim and no raw or user media is stored in Git.

## Implemented contract

- [`tools/camera_dataset_audit.py`](../tools/camera_dataset_audit.py) reads a
  content-addressed JSON/JSONL manifest plus external local media references.
- Exact identity is the computed lowercase SHA-256 of each file. A declared
  digest, when present, must match the file; missing/unreadable media and
  malformed lineage fail closed.
- Near matching combines 64-bit grayscale DCT pHash Hamming distance with a
  deterministic centered 8x8 grayscale descriptor cosine score. The descriptor
  is explicitly `local_descriptor_v1`, not a learned embedding; a model-backed
  embedding is a future versioned upgrade boundary.
- Sequence members are unioned into one cluster and reported in
  `sequence_families`; they retain one `derivation_family_id` from the M3-003
  provenance convention. SSIM is optional review evidence only and is never a
  cluster-admission oracle.
- Cluster IDs and output order are derived from sorted asset IDs and computed
  content hashes. Receipts contain no media paths, raw bytes, labels, or
  candidate/model output fields.
- [`datasets/camera-coach/v1/cluster-schema.json`](../datasets/camera-coach/v1/cluster-schema.json)
  closes the receipt shape as `camera-dedup-clusters-v1` / `v1.0.0`.

## Synthetic verification

[`tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py`](../tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py)
creates PNGs only in a temporary directory and verifies exact, crop, color,
near, far, sequence-family, input-order, malformed/missing-media, schema
round-trip, and SSIM-review-only behavior.

```text
$ python3 tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py
PASS M3-007 fixture exact_sha near_crop_color near_blur far_discriminated sequence_family input_order_independent malformed_rejected schema_round_trip ssim_review_only
```

The tool also has a tiny no-media smoke check:

```text
$ python3 tools/camera_dataset_audit.py --self-test
PASS M3-007 camera_dataset_audit self-test
```

## Verification commands

```text
$ python3 -m py_compile tools/camera_dataset_audit.py tools/dataset/tests/fixtures/camera_dataset_audit_fixture.py
PASS
$ python3 -m json.tool datasets/camera-coach/v1/cluster-schema.json >/dev/null
PASS
$ python3 - <<'PY'  # Draft 2020-12 schema + generated receipt
... Draft202012Validator.check_schema(schema)
... Draft202012Validator(schema).validate(output)
... print("PASS jsonschema output")
PASS jsonschema output
$ git diff --check
PASS
```

## Deliberate boundaries

- This task does not assign train/calibration/holdout splits (M3-008).
- `fixture_only` is accepted for synthetic audit evidence; other unresolved,
  denied, pending, withdrawn, or missing rights dispositions are rejected.
- Pairwise near matching and optional SSIM review are O(n²) within an audit;
  the code marks the upgrade boundary for an indexed/ANN implementation if
  scale requires it.
