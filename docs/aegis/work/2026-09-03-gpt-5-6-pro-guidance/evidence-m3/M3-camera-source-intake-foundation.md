# M3 — Camera source-intake foundation

Status: implemented in the current working tree; no commit made by this
worker. This package establishes a reproducible research-source intake
boundary. It does not claim a trained model, Camera Coach human gold, or
release-cleared media.

## Owned artifacts

- `datasets/camera-coach/v1/research-source-catalog.json`
  - Registers the existing AVA Hugging Face mirror, official EVA, LIVE
    ChallengeDB, SPAQ, KonIQ, Wikimedia Commons, Library of Congress, and the
    existing Apple TV Press candidate manifest.
  - Records purpose, access path, rights tier, redistribution rule, label
    status, admission/quarantine rule, and an explicit
    `camera_coach_human_gold: false` boundary for every source.
  - Uses research-only or per-asset-clearance tiers where a catalog/landing
    page does not prove redistribution rights.
- `tools/dataset/camera_source_intake.py`
  - Stdlib-first CLI with Pillow used only for image decode/dimensions/format.
  - `--self-test` covers atomic output, deterministic rerun, SHA-256 and
    dimensions, format, duplicate IDs/content, malformed JSON, missing and
    non-image files, the explicit upstream-metadata allowlist (including
    nested unknown/policy fields), output/media collision refusal, lexical
    in-root/out-of-root symlink refusal, non-finite-number rejection, and
    repository-boundary refusal (including repository ancestors and the
    filesystem root).
  - `verify-local` validates an external data root and writes deterministic
    JSONL metadata. Raw media is never copied into the repository and emitted
    paths are relative to the declared data root. The output is stamped
    `intake_tier=research_only`, `human_gold=false`, and
    `release_admissible=false`; upstream policy-bearing metadata is rejected.
  - No generic network downloader is included. Later source-specific,
    allowlisted adapters must acquire each source under its own terms and then
    hand local media to `verify-local`.

## Verification evidence

Environment: macOS workspace, Python 3, Pillow available, repository branch
`store`. No iPhone or simulator was used; this package is host-side dataset
tooling only.

### Syntax and catalog

Command:

```text
python3 -m py_compile tools/dataset/camera_source_intake.py
python3 -m json.tool datasets/camera-coach/v1/research-source-catalog.json >/dev/null
```

Result: PASS. The catalog parses as JSON and the intake script compiles.

### Self-test

Command:

```text
python3 tools/dataset/camera_source_intake.py --self-test
```

Result:

```text
PASS camera_source_intake self-test atomic_write deterministic hashes dimensions format duplicates missing non_image metadata_allowlist nonfinite_guards output_collisions symlink_guards repo_boundary
```

### Existing AVA cache (read-only verification)

The pre-existing AVA cache was moved from `/private/tmp/ava_silver` to the
durable external location
`/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/ava/legacy-silver-4000`.
The image bytes were unchanged by the relocation. The old manifest retained
absolute `/private/tmp/ava_silver/images/...` paths; parent fail-closed
verification caught this, and all 4,000 lines were mechanically changed to
relative `images/...` paths. The corrected durable manifest SHA-256 is
`0dcc4d0b6ebf389be608584dadc7ce688530f8c54dee27c73ccb8a5bf8112159`.
Verification was run into a task-owned temporary directory and the temporary
inventory was removed after the check.

Command:

```text
python3 tools/dataset/camera_source_intake.py verify-local \
  --source-id ava_hf_mirror \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/ava/legacy-silver-4000" \
  --manifest "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/ava/legacy-silver-4000/manifest.jsonl" \
  --output <temporary>/inventory-current.jsonl
```

The current run returned:

```text
PASS verify-local source_id=ava_hf_mirror records=4000 output_sha256=6a1bd12dc5d3d01aecdfbf531883f3c278b71f53758c74468ea2f27341413887
```

The inventory JSONL has digest
`6a1bd12dc5d3d01aecdfbf531883f3c278b71f53758c74468ea2f27341413887`. Every
record had a unique `source_record_id`, relative path, and content SHA-256;
the shared `source_id` identifies the source batch. Dimensions
and decoded image format were present. The first canonical record was
`640×298`, `jpeg`, and `22,723` bytes. No absolute local path appeared in an
emitted path field.

### Workspace hygiene

The AVA cache remains in the durable external location above after the
relocation. The task-owned verification output file and its temporary directory
were removed after hashing. No repository file outside the three
owned artifacts was edited, and no commit, push, reset, or destructive cleanup
was performed during this verification.

## Honest boundaries and next work

1. AVA, LIVE, SPAQ, KonIQ, and Apple TV Press remain research/quarantine
   inputs. Their MOS or curator labels are not Camera Coach human gold.
2. EVA's repository license declaration and public-domain/open sources still
   require asset-level provenance receipts before release use. Wikimedia and
   LOC category/collection membership is not treated as a license.
3. `verify-local` validates files already present; it does not prove upstream
   dataset terms, source ownership, consent, or semantic correctness.
4. A later acquisition package may add source-specific, allowlisted adapters;
   this package intentionally performs no network acquisition. Any adapter
   must hand local media to this verifier and preserve the external-root,
   hash, rights, and quarantine boundary.
5. The next ML package should build a silver-label export and leakage-safe
   family split from these inventories, then create a small human review
   packet. Automated teacher labels can bootstrap; they cannot close the
   capture protocol's two-annotator release gate.
