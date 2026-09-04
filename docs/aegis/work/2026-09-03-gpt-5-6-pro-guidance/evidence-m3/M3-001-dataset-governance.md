# M3-001 dataset governance evidence

## Scope

M3-001 defines a versioned dataset-release contract without collecting or
committing raw data. The v1 manifest independently binds the data, label schema,
split, rights manifest, feature schema, evaluator, and model-candidate
identities. Each identity carries an `id`, semantic version, and lowercase
SHA-256 digest.

The contract is fail-closed for rights: a frozen release requires
`rights_status=approved` and `unresolved_rights_count=0`. It requires
content-addressed SHA-256 storage, keeps raw and rights-uncleared material
outside Git, names reader/writer roles, and requires positive raw/derived
retention windows. A frozen receipt is retained permanently; deletion requires
a new dataset version. The receipt digest covers the complete canonical JSON
object except its own digest field.

## Changed files

- `datasets/README.md` — governance rules, layout, and operational limits.
- `datasets/schemas/dataset-version-v1.schema.json` — versioned JSON Schema
  contract with closed objects and required component identities.
- `datasets/schemas/fixtures/dataset-version-v1.valid.json` — deterministic,
  raw-data-free valid manifest fixture.
- `tools/dataset/governance_check.py` — stdlib-only schema declaration,
  fail-closed manifest, canonicalization, and SHA-256 checks.

## Baseline and narrow verification

- Baseline: `e950e1934648a01f47ba19cf101f50d596745956`
  (`e950e19 checkpoint: SET OS through M2-023`), branch
  `codex/set-os-ml-b1`.
- Command: `python3 tools/dataset/governance_check.py --self-test`
  Result: `PASS M3-001 self-test fixture_sha256=ca09976a2c817d34bdf024723bf88d914dc900ccec5ea6e756280ae9381a09a5`.
  This checks schema required-field declarations, a valid fixture, canonical
  manifest hash, JSON serialize/deserialize hash round-trip, and rejection of
  missing/unknown rights, stale version digest, missing component identity,
  unknown fields, and unknown access roles.
- Command: `python3 tools/dataset/governance_check.py`
  Result: `PASS /Users/unterlantas/.codex/worktrees/shafinMultitool/ml-b1/datasets/schemas/fixtures/dataset-version-v1.valid.json manifest_sha256=ca09976a2c817d34bdf024723bf88d914dc900ccec5ea6e756280ae9381a09a5`.
- Command: `git diff --cached --check` (run after staging only the five files
  in the four task-owned path areas above)
  Result: pass, no output.

No tests, build, simulator, device, network, data collection, annotation, or
training commands were run.

## Limits and risks

This is a metadata contract and local validator, not an external CAS, IAM, or
retention-deletion service. It cannot prove that an external object exists,
that a rights record is legally sufficient, or that access/deletion controls
are enforced by infrastructure. Component hashes in the fixture are
deterministic placeholders and make no dataset-quality, legal, training, or
model-performance claim. Real admission tooling must resolve external CAS
objects, rights records, protected-family splits, and evaluator/model
artifacts before issuing a frozen manifest.
