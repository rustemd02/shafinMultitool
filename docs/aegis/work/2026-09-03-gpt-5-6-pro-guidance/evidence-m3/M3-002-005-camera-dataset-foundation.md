# M3-002→M3-005 Camera dataset foundation evidence

## Status

Complete for the autonomous foundation batch. This receipt documents contracts
and validator evidence only; it is not a collection, rights grant, human
calibration result, or model-quality claim.

## Changes

- `datasets/camera-coach/v1/label-schema.json` — closed shared record contract:
  seven matrix classes, subject selection/ambiguity, intentional style,
  multi-valid and forbidden actions, KEEP/ABSTAIN, action verifiers, and
  append-only review/adjudication arrays.
- `datasets/camera-coach/v1/temporal-schema.json` — monotonic timestamped
  sequence extension with one-take timeline.
- `datasets/camera-coach/v1/episode-schema.json` — before/action/after
  extension with correct, no-op, opposite, overshoot, track-loss, and
  incomparable outcomes.
- `datasets/camera-coach/v1/source-shoots.jsonl`,
  `rights-manifest.jsonl`, `derivation-manifest.jsonl` — versioned,
  content-addressed, template-only JSONL headers; no raw or synthetic
  production records are committed. Each future entry must resolve source
  shoot/assets, consent/rights disposition, and derivation independence.
- `datasets/camera-coach/v1/capture-manifest-template.json` — auditable
  capture-entry fields and pilot checklist.
- `datasets/camera-coach/v1/capture-protocol.md` — independent still,
  temporal, and before/after procedures; burst-frame inflation prevention;
  family/split/rights gates; seven-class and capture-dimension coverage.
- `datasets/camera-coach/v1/annotation-guide.md` — operational rubric for
  subject, issue, action, KEEP, ABSTAIN, style, verification, and review.
- `tools/dataset/camera_coach_check.py` — stdlib-only narrow schema declaration,
  record, manifest, rights, derivation, family, split, and verifier checks.
- `tools/dataset/tests/fixtures/camera-coach-fixtures.json` — explicitly
  synthetic valid still/temporal/episode records and declared negative
  mutation cases.

## Verification

From the repository root:

```text
$ python3 tools/dataset/governance_check.py --self-test && python3 tools/dataset/governance_check.py
PASS M3-001 self-test fixture_sha256=1ab4d8715ea1af6a98d30ed68b4831500cc747b2eb8a79b877cf9fccaa2a1bec
PASS /Users/unterlantas/.codex/worktrees/shafinMultitool/m3-dataset-foundation/datasets/schemas/fixtures/dataset-version-v1.valid.json manifest_sha256=1ab4d8715ea1af6a98d30ed68b4831500cc747b2eb8a79b877cf9fccaa2a1bec

$ python3 tools/dataset/camera_coach_check.py --self-test
PASS M3-002 schemas matrix_classes=7 actions=30 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=12
PASS M3-004 temporal_sequence=1 episode_outcomes=correct capture_families=scene/take/time/derivation
PASS M3-005 review_status=unreviewed vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=12

$ python3 -m py_compile tools/dataset/camera_coach_check.py
PASS py_compile camera_coach_check.py

$ python3 <stdlib JSON/JSONL parse loop over datasets/camera-coach/v1 and tools/dataset/tests/fixtures>
PASS parsed_files=8

$ git diff --cached --check
PASS (no output)
```

The 12 declared negative fixtures cover missing source shoot, denied rights,
unresolved rights, invalid subject reference, invalid action ID, invalid action
verifier, family mismatch, missing rights record, missing source asset,
non-independent derivation, burst-frame inflation, and episode verifier
mismatch. The self-test requires each case to fail with its declared reason.

The validator uses only Python standard-library modules and intentionally does
not claim full JSON Schema implementation. JSON Schema files use the repository
contract's Draft 2020-12 dialect; the validator implements the deterministic
structural/referential gates required for this batch.

## Human and data boundaries

- Production JSONL manifests are empty headers (`record_count=0`) until real
  source shoots and rights evidence exist.
- Fixture rights use `fixture_only`; they do not assert legal permission and are
  allowed only on the synthetic `fixture` split.
- Missing, denied, unresolved, pending, withdrawn, or fixture-only rights fail
  train/calibration/holdout admission.
- Review arrays are empty in fixtures. The required two-annotator, 35-case
  calibration and disagreement report remain pending HUMAN work.
- No raw media, rights-uncleared media, candidate/model outputs, locked labels,
  model downloads, network access, collection, annotation, or training was
  used.

## Commit

This receipt is included in the single local batch commit; the worker return
reports its exact SHA.
