# M3-002→M3-005 Camera dataset foundation evidence

## Status

Complete for the autonomous foundation correction batch. This receipt documents
contracts and validator evidence only; it is not a collection, rights grant,
human calibration result, or model-quality claim.

## Changes

- `datasets/camera-coach/v1/label-schema.json` — closed shared record contract:
  seven matrix classes, subject selection/ambiguity, intentional style,
  multi-valid and forbidden actions, KEEP/ABSTAIN, action verifiers, and
  append-only review/adjudication arrays. Its action enums exactly mirror the
  read-only `approvedActionIDs` catalog in
  `docs/implementation/camera-coach-contract-v2.json` (26 IDs); legacy-only
  aliases are rejected.
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
  family/split/rights gates; seven-class and capture-dimension coverage;
  explicit external-manifest batch admission invocations.
- `datasets/camera-coach/v1/annotation-guide.md` — operational rubric for
  subject, issue, action, KEEP, ABSTAIN, style, verification, and review.
- `tools/dataset/camera_coach_check.py` — stdlib-only narrow schema declaration,
  canonical-action parity, record, manifest, source-authority, rights,
  derivation, family, split, temporal, episode, and verifier checks. Production
  `--record` and batch admission require explicit source/rights/derivation
  manifests; embedded synthetic manifests are used only by `--self-test`.
- `tools/dataset/tests/fixtures/camera-coach-fixtures.json` — explicitly
  synthetic valid still/temporal/episode records and 20 declared negative
  mutation cases, including source relabel, abstention, subject, temporal, and
  episode safety probes.
- `tools/dataset/tests/fixtures/camera-coach-batch-*.jsonl` — explicitly
  synthetic caller-supplied positive batch/manifests and a train/calibration
  protected-family crossing batch/derivation fixture.

## Verification

From the repository root:

```text
$ python3 tools/dataset/governance_check.py --self-test && python3 tools/dataset/governance_check.py
PASS M3-001 self-test fixture_sha256=1ab4d8715ea1af6a98d30ed68b4831500cc747b2eb8a79b877cf9fccaa2a1bec
PASS /Users/unterlantas/.codex/worktrees/shafinMultitool/m3-dataset-foundation/datasets/schemas/fixtures/dataset-version-v1.valid.json manifest_sha256=1ab4d8715ea1af6a98d30ed68b4831500cc747b2eb8a79b877cf9fccaa2a1bec

$ python3 tools/dataset/camera_coach_check.py --self-test
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=20
PASS M3-004 temporal_sequence=1 episode_outcomes=correct capture_families=scene/take/time/derivation
PASS M3-005 review_status=unreviewed vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=20

$ python3 -c 'import json; from pathlib import Path; a=json.loads(Path("docs/implementation/camera-coach-contract-v2.json").read_text()); s=json.loads(Path("datasets/camera-coach/v1/label-schema.json").read_text()); assert set(a["approvedActionIDs"]) == set(s["$defs"]["actionId"]["enum"]); assert set(s["$defs"]["verificationActionId"]["enum"]) == set(a["approvedActionIDs"]) | {"abstain"}; print("PASS canonical_action_parity actions=26 verification_actions=27")'
PASS canonical_action_parity actions=26 verification_actions=27

The same self-test's 20 declared negative cases include eight hostile probes:
inconsistent ABSTAIN, selected ambiguous subject, too-short/noncontiguous/
non-increasing temporal records, non-later correct episode, failed correct
verification, and synthetic-source relabel with approved claimant rights.

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
PASS tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl camera-coach-batch records=1 source_shoots=1 rights=1 derivations=1

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-family.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-negative-derivations.jsonl
FAIL synthetic_source_not_admissible ... (2 records)
FAIL rights_not_approved ... (2 records)
FAIL family_cross_split ... (7 protected families)
exit=1 (expected negative)

$ python3 tools/dataset/camera_coach_check.py --record tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl
input_error: explicit --source-shoots, --rights-manifest, and --derivation-manifest are required for admission
exit=1 (expected: no implicit fixture manifests)

$ python3 -m py_compile tools/dataset/camera_coach_check.py && echo 'PASS py_compile camera_coach_check.py'
PASS py_compile camera_coach_check.py

$ python3 <stdlib JSON/JSONL parse loop over datasets/camera-coach/v1 and tools/dataset/tests/fixtures>
PASS parsed_files=14

$ git diff --check
PASS (no output); diff_check_exit=0
```

The 20 declared negative fixtures cover missing source shoot, denied rights,
unresolved rights, invalid subject reference, invalid action ID, invalid action
verifier, family mismatch, missing rights record, missing source asset,
non-independent derivation, burst-frame inflation, episode verifier mismatch,
inconsistent selection ABSTAIN, selected ambiguous subject, too-short temporal
sequence, noncontiguous temporal ordinals, non-increasing temporal timestamps,
non-later episode after timestamp, correct episode with failed verification, and
synthetic-source relabeled as owned with approved rights/train claimant fields.
The self-test requires each case to fail with its declared reason. The hostile
source case still fails because the resolved source entry remains
`synthetic_fixture`; claimant fields cannot override source authority.

The validator uses only Python standard-library modules and intentionally does
not claim full JSON Schema implementation. JSON Schema files use the repository
contract's Draft 2020-12 dialect; the validator implements the deterministic
structural/referential gates required for this batch.

## Human and data boundaries

- Production JSONL manifests are empty headers (`record_count=0`) until real
  source shoots and rights evidence exist. Batch admission requires caller-
  supplied manifests and applies the same source/rights/derivation and family
  gates across the complete collection.
- The checker derives its action catalog from the read-only contract authority
  and deterministically rejects drift between that catalog, schema enums, and
  verifier coverage.
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
