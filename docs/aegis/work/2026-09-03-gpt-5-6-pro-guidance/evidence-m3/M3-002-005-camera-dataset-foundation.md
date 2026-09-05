# M3-002→M3-005 Camera dataset foundation evidence

## Status

Complete for the autonomous seventh correction batch. This receipt documents
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
  `consent-manifest.jsonl`, `rights-manifest.jsonl`,
  `derivation-manifest.jsonl` — versioned, content-addressed, template-only
  JSONL headers; no raw or synthetic production records are committed. Consent
  entries resolve source/asset scope and admissible disposition before rights
  admission.
- `datasets/camera-coach/v1/capture-manifest-template.json` — auditable
  capture-entry fields and pilot checklist including consent and device-family
  split checks.
- `datasets/camera-coach/v1/capture-protocol.md` — independent still,
  temporal, and before/after procedures; burst-frame inflation prevention;
  closed derivation kinds and quota rules; strict integer temporal fields and
  timeline coverage;
  measurable episode verification with subject continuity; source/consent/rights/
  family/review gates;
  seven-class and capture-dimension coverage; explicit external-manifest batch
  admission invocations and duplicate guards.
- `datasets/camera-coach/v1/annotation-guide.md` — operational rubric for
  subject, canonical SELECT_SUBJECT/fail-closed encoding, issue, action, KEEP,
  ABSTAIN with or without a selected subject, intentional style, verification,
  temporal segments, episode outcomes with subject continuity, issue-evidence
  enum, and release review with chronological adjudication.
- `tools/dataset/camera_coach_check.py` — stdlib-only narrow schema declaration,
  canonical-action parity, recursively closed production record keys,
  record/manifest checks, source-authority and media-asset resolution,
  consent/rights resolution, derivation independence/quota and duplicate
  checks, subject/ABSTAIN semantics, family/device split isolation, temporal
  chronology/full timeline with strict JSON integer typing, strict RFC3339 UTC
  timestamp parsing, episode chronology/measurable outcomes with
  subject-continuity coupling, exact schema-derived issue evidence, resolved
  human-review admission with chronological and coherent adjudication checks,
  total malformed-ID handling for arbitrary schema-invalid JSON values in the
  declared hostile corpus, and action-specific verifier checks. Production
  `--record` and batch admission require explicit source/consent/rights/
  derivation manifests; embedded synthetic manifests are used only by
  `--self-test`.
- `tools/dataset/tests/fixtures/camera-coach-fixtures.json` — explicitly
  synthetic valid still/temporal/episode records and 75 declared negative
  mutation cases, including source relabel, media asset authority, recursive
  unknown fields, subject/ABSTAIN semantics, consent resolution, derivation
  kind/independence/quota, temporal timeline, review status/conflict/
  adjudication outcome/chronology, impossible timestamps and reversed vote
  history, strict numeric types (including Python bool rejection), malformed
  subject IDs, malformed action/provenance source-asset/capture person-family/
  temporal asset/manifest source IDs, closed issue evidence, and episode
  outcome/subject-continuity probes.
- `tools/dataset/tests/fixtures/camera-coach-batch-*.jsonl` — explicitly
  synthetic caller-supplied positive manifests, train/calibration protected-
  family crossing, device-family-only crossing, duplicate record, and duplicate
  derivation hostile batches.

## Verification

From the repository root:

```text
$ python3 tools/dataset/governance_check.py --self-test && python3 tools/dataset/governance_check.py
PASS M3-001 self-test fixture_sha256=1ab4d8715ea1af6a98d30ed68b4831500cc747b2eb8a79b877cf9fccaa2a1bec
PASS /Users/unterlantas/.codex/worktrees/shafinMultitool/m3-dataset-foundation/datasets/schemas/fixtures/dataset-version-v1.valid.json manifest_sha256=1ab4d8715ea1af6a98d30ed68b4831500cc747b2eb8a79b877cf9fccaa2a1bec

$ python3 tools/dataset/camera_coach_check.py --self-test
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=75
PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation
PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=75

$ python3 tools/dataset/camera_coach_check.py --self-test  # repeated deterministic run
PASS M3-002 schemas matrix_classes=7 actions=26 keep=1 abstain=1
PASS M3-003 references valid_records=3 rights_dispositions=fixture_only invalid_cases=75
PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation
PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending
PASS camera-coach self-test valid=3 invalid=75

$ python3 -c 'import json; from pathlib import Path; a=json.loads(Path("docs/implementation/camera-coach-contract-v2.json").read_text()); s=json.loads(Path("datasets/camera-coach/v1/label-schema.json").read_text()); assert set(a["approvedActionIDs"]) == set(s["$defs"]["actionId"]["enum"]); assert set(s["$defs"]["verificationActionId"]["enum"]) == set(a["approvedActionIDs"]) | {"abstain"}; e=s["$defs"]["issue"]["properties"]["evidence"]["items"]["enum"]; assert e == list(dict.fromkeys(e)); print("PASS canonical_action_parity actions=26 verification_actions=27 issue_evidence=8")'
PASS canonical_action_parity actions=26 verification_actions=27 issue_evidence=8

$ python3 - <<'PY'
import copy, json, sys
from pathlib import Path
sys.path.insert(0, "tools/dataset")
import camera_coach_check as check
fixture = json.loads(Path("tools/dataset/tests/fixtures/camera-coach-fixtures.json").read_text())
valid = {item["record_id"]: item for item in fixture["valid_records"]}
for case in fixture["invalid_cases"]:
    record = copy.deepcopy(valid[case["base_record_id"]])
    manifests = copy.deepcopy(fixture["manifests"])
    check._apply_mutations(record, manifests, case["mutations"])
    try:
        errors = check._validate_fixture_manifests(manifests)
        errors.extend(check.validate_record(record, manifests, fixture_mode=True))
    except Exception as exc:
        raise AssertionError(f"{case['case_id']} raised {type(exc).__name__}") from exc
    assert errors and any(case["declared_reason"] in error for error in errors), (case["case_id"], case["declared_reason"], errors)
print(f"PASS declared_hostile_probes={len(fixture['invalid_cases'])} exact_declared_reasons={len({case['declared_reason'] for case in fixture['invalid_cases']})}")
PY
PASS declared_hostile_probes=75 exact_declared_reasons=33

The self-test and hostile probe loop require every one of the 75 declared
negative fixtures to fail for its declared reason and to return validation
errors without raising an exception. They cover missing source,
denied/unresolved rights, source-kind relabeling, foreign primary/member media
assets, recursive unknown `candidate_identity`/`modelOutput`/`label` fields,
invalid subject selection and canonical SELECT_SUBJECT corrective-action
attempts, ABSTAIN status/reason/subject cross-semantics, consent absence and
denial, closed derivation kinds and independence/quota semantics, duplicate
record/derivation controls, temporal length/order/timestamps and full timeline
overlap/gap plus strict integer typing for frame count, frame ordinals,
timestamps, timeline indices, subject-region numbers, and valid UTC RFC3339
timestamps, all three episode timestamp boundaries, and
missing measured pass evidence for correct/no-op/opposite/overshoot outcomes,
unreviewed, conflicting, rejected-adjudication, before-vote adjudication,
impossible-timestamp, reversed-vote-history, and missing-adjudication release
review, exact issue evidence (`model_output` and unknown strings), malformed
subject IDs, malformed action/provenance source-asset/capture person-family/
temporal asset/manifest source IDs, and measurable outcomes with lost, changed,
or unknown subject continuity. The release review gate accepts only two distinct
accepting votes or a latest accepted adjudication that chronologically follows
every referenced vote, covers every vote, and has accepted outcome.

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
PASS tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl camera-coach-batch records=2 source_shoots=2 consents=2 rights=2 derivations=2

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-family.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-negative-derivations.jsonl --fixture-mode
FAIL review_not_admissible: train requires two independent annotator votes
FAIL synthetic_source_not_admissible: resolved source_shoot source_kind is synthetic_fixture
FAIL consent_not_admissible: train requires approved consent and allowed use
FAIL rights_not_approved: train requires approved rights and allowed use
FAIL invalid_quota_semantics: train independent record must count toward quota
FAIL review_not_admissible: calibration requires two independent annotator votes
FAIL synthetic_source_not_admissible: resolved source_shoot source_kind is synthetic_fixture
FAIL consent_not_admissible: calibration requires approved consent and allowed use
FAIL rights_not_approved: calibration requires approved rights and allowed use
FAIL invalid_quota_semantics: calibration independent record must count toward quota
FAIL family_cross_split: shoot-fixture-001
FAIL family_cross_split: scene-fixture-001
FAIL family_cross_split: take-fixture-001
FAIL family_cross_split: time-fixture-001
FAIL family_cross_split: location-fixture-001
FAIL family_cross_split: device-fixture-001
FAIL family_cross_split: derivation-family-fixture-001
FAIL family_cross_split: person-fixture-001
exit=1

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-device.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
FAIL review_not_admissible: train requires two independent annotator votes
FAIL synthetic_source_not_admissible: resolved source_shoot source_kind is synthetic_fixture
FAIL consent_not_admissible: train requires approved consent and allowed use
FAIL rights_not_approved: train requires approved rights and allowed use
FAIL invalid_quota_semantics: train independent record must count toward quota
FAIL review_not_admissible: calibration requires two independent annotator votes
FAIL synthetic_source_not_admissible: resolved source_shoot source_kind is synthetic_fixture
FAIL consent_not_admissible: calibration requires approved consent and allowed use
FAIL rights_not_approved: calibration requires approved rights and allowed use
FAIL invalid_quota_semantics: calibration independent record must count toward quota
FAIL family_cross_split: device-fixture-001
exit=1

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-duplicates.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
FAIL duplicate_record_id: cam-still-fixture-001
exit=1

$ python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-duplicate-derivations.jsonl --fixture-mode
FAIL duplicate_derivation_record: cam-still-fixture-001
exit=1

$ python3 tools/dataset/camera_coach_check.py --record tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl
input_error: explicit --source-shoots, --consent-manifest, --rights-manifest, and --derivation-manifest are required for admission
exit=1 (expected: no implicit fixture manifests)

$ python3 -m py_compile tools/dataset/camera_coach_check.py
(no output); exit=0

$ python3 - <<'PY'
import json
from pathlib import Path
roots = [Path("datasets/camera-coach/v1"), Path("tools/dataset/tests/fixtures")]
paths = sorted({path for root in roots for pattern in ("*.json", "*.jsonl") for path in root.rglob(pattern)})
for path in paths:
    if path.suffix == ".jsonl":
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.strip():
                json.loads(line)
    else:
        json.loads(path.read_text(encoding="utf-8"))
print(f"PASS parsed_files={len(paths)} json_and_jsonl={len(paths)}")
PY
PASS parsed_files=19 json_and_jsonl=19

$ git diff --check
(no output); exit=0
```

The self-test and hostile probe loop require every one of the 75 declared
negative fixtures to fail for its declared reason and to return validation
errors without raising an exception. They cover missing source,
denied/unresolved rights, source-kind relabeling, foreign primary/member media
assets, recursive unknown `candidate_identity`/`modelOutput`/`label` fields,
invalid subject selection and canonical SELECT_SUBJECT corrective-action
attempts, ABSTAIN status/reason/subject cross-semantics, consent absence and
denial, closed derivation kinds and independence/quota semantics, duplicate
record/derivation controls, temporal length/order/timestamps and full timeline
overlap/gap plus strict integer typing for frame count, frame ordinals,
timestamps, timeline indices, subject-region numbers, and valid UTC RFC3339
timestamps, all three episode timestamp boundaries, and
missing measured pass evidence for correct/no-op/opposite/overshoot outcomes,
release review status/conflict/rejected-adjudication/before-vote chronology/
impossible-timestamp/reversed-vote-history/missing-adjudication, exact closed
issue evidence, malformed subject IDs, malformed action/provenance
source-asset/capture person-family/temporal asset/manifest source IDs, and
measurable outcome subject-continuity failures. The hostile source case still fails because the
resolved source entry remains
`synthetic_fixture`; claimant fields cannot override source authority.

The validator uses only Python standard-library modules and intentionally does
not claim full JSON Schema implementation. JSON Schema files use the repository
contract's Draft 2020-12 dialect; the validator implements the deterministic
structural, closed-key, and referential gates required for this batch.

## Human and data boundaries

- Production JSONL manifests are empty headers (`record_count=0`) until real
  source shoots, consent, and rights evidence exist. Batch admission requires
  caller-supplied manifests and applies the same source/consent/rights/
  derivation and family gates across the complete collection.
- The checker derives its action catalog from the read-only contract authority
  and deterministically rejects drift between that catalog, schema enums, and
  verifier coverage.
- Fixture rights and consent use `fixture_only`; they do not assert legal
  permission and are allowed only on the synthetic `fixture` split.
- Missing, denied, unresolved, pending, withdrawn, or fixture-only rights or
  consent fail train/calibration/holdout admission.
- Release splits require resolved human review: two distinct accepting votes or
  a latest accepted adjudication that chronologically follows every referenced
  vote and coherently covers every vote; rejected/quarantined adjudication
  outcomes are not admissible. Fixture/quarantine review may remain unreviewed
  for audit only. Review arrays are empty in fixtures.
- Review timestamp and append-order checks cover only the current record's
  history; cross-snapshot append-only continuity is explicitly deferred to
  M3-006.
- The required two-annotator, 35-case calibration and disagreement report
  remain pending HUMAN work; no human agreement, calibration quality, or release
  readiness claim is made.
- No raw media, rights-uncleared media, candidate/model outputs, locked labels,
  model downloads, network access, collection, annotation, or training was
  used.

## Commit

This receipt is included in the local seventh-correction commit; the worker
return reports its exact SHA.
