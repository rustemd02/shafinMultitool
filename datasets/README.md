# SET OS dataset governance v1

This directory contains versioned dataset contracts and validation code only. Raw
images, recordings, text, labels, and any rights-uncleared material stay in an
access-controlled store outside Git.

## Release-manifest contract

`schemas/dataset-version-v1.schema.json` defines a frozen dataset release. Every
release independently identifies these content-addressed components with an
`id`, `vMAJOR.MINOR.PATCH` version, and lowercase SHA-256 digest:

- `data`
- `label_schema`
- `split`
- `rights_manifest`
- `feature_schema`
- `evaluator`
- `model_candidate`

The release is admitted only when `rights_status` is `approved` and
`unresolved_rights_count` is zero. Missing, unknown, denied, or unresolved rights
are fail-closed and cannot be represented as a frozen release.

The manifest also records:

- content-addressed storage and SHA-256 as the only release hash algorithm;
- `raw_data_location` and `rights_uncleared_location` as `outside_git`;
- reader/writer roles under an explicit access policy;
- raw/derived retention windows and permanent retention for the frozen receipt;
- a `frozen` release status and the rule that deletion requires a new dataset
  version.

The receipt self-digest is `release.manifest_sha256`. Its input is the complete
JSON object with that one field removed, serialized as sorted keys, UTF-8, and no
insignificant whitespace (`json-sort-keys-utf8-no-whitespace-v1`). Any mutation
without a new version changes the digest and fails validation.

## Layout and checks

```text
datasets/
  README.md
  schemas/
    dataset-version-v1.schema.json
    fixtures/dataset-version-v1.valid.json
tools/dataset/
  governance_check.py
```

Run the stdlib-only check from the repository root:

```bash
python3 tools/dataset/governance_check.py --self-test
python3 tools/dataset/governance_check.py
```

The fixture uses deterministic placeholder component digests so the contract can
be checked without committing raw data. It is not a Camera or Scene quality
claim, a rights grant, a training split, or a release dataset.

Future dataset admission tooling must verify referenced CAS objects and rights
records before producing a frozen manifest; this M3-001 contract does not itself
inspect external storage or grant legal permission.
