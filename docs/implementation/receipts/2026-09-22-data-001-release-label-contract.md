# DATA-001 — release label contract

Date: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`.
The working tree was already dirty; no commit, reset, stash, branch, worktree,
production Swift, or raw data was changed.

## Delivered

- `ml/camera_coach/contracts/camera_release_label_v1.schema.json` — closed,
  versioned Draft 2020-12 structure for verdict, exhaustive issue statuses,
  action/magnitude, target identity/region, risk, abstention, intent,
  movability, before/after evidence, and provenance.
- `ml/camera_coach/contracts/camera_release_label_v1.md` — field semantics,
  V3/app enum mapping, identity/region boundary, and validator ownership.
- `ml/camera_coach/contracts/validate_camera_release_label.py` — the persistent
  stdlib + `jsonschema` validator for schema and cross-field rules that JSON
  Schema cannot express.
- `ml/camera_coach/contracts/fixtures/camera_release_label_v1.valid.json` —
  adjudicated positive record with all 15 release issue heads exactly once.
- `ml/camera_coach/contracts/fixtures/camera_release_label_v1.invalid.json` —
  16 named negative mutations plus one accepted incomparable boundary case.
- Canonical tracker row DATA-001 is `DONE`.

## Enum and semantic cross-check

| Contract field | Existing owner/raw values checked |
|---|---|
| `verdict` | `FrameVerdict`: `good`, `mixed`, `needs_fix` |
| `issues[].issue_id` | eight `IssueTypeV1` IDs plus seven `TechnicalQualityIssueType` IDs |
| `action.action_id` | 26 `SemanticActionType` IDs plus seven `TechnicalQualityActionType` IDs |
| `intent` | `CaptureIntentSelection` (`unknown`, `automatic`, `user`, `group`) and all eight `CaptureStyle` IDs |
| `before_after.metric/outcome` | `ActionVerificationMetric`; `ActionVerificationOutcome` (`fixed`, `improved`, `unchanged`, `worse`) plus V3 `incomparable` |
| target/region | V3 entity kinds/roles and `CameraAnalysisV3Region` (`x`, `y`, `width`, `height`) |

No parallel action taxonomy or coordinate-space claim was introduced. Target
references use opaque app/V3 entity IDs (the fixture uses `lampA`, not an
invented `entity-*` prefix). `goal_satisfied` plus `objective_predicate`
records the V3/`ActionVerifier` `goalSatisfied` evidence needed for `fixed`.
Model proposals are schema-forced to `human_gold=false` and
`release_admissible=false`; only two-review adjudication can set both true.

## Validation commands and results

Persistent schema, positive, negative, and boundary validation:

```text
python3 ml/camera_coach/contracts/validate_camera_release_label.py
```

Result:

```text
schema: PASS (.../ml/camera_coach/contracts/camera_release_label_v1.schema.json)
positive camera_release_label_v1.valid.json: PASS
negative abstain_cannot_keep_verdict_or_action: REJECTED
negative model_proposal_cannot_self_promote_to_gold: REJECTED
negative corrective_action_requires_grounded_target: REJECTED
negative physical_move_requires_movability_and_permission: REJECTED
negative improved_requires_comparable_same_target_evidence: REJECTED
negative region_coordinates_must_be_in_unit_square: REJECTED
negative needs_fix_cannot_omit_action: REJECTED
negative corrective_action_requires_issue_reference: REJECTED
negative region_overflows_unit_square_with_individually_valid_coordinates: REJECTED
negative action_references_absent_issue: REJECTED
negative duplicate_issue_id: REJECTED
negative before_after_target_mismatch: REJECTED
negative same_before_after_frame_ids: REJECTED
negative fixed_without_goal_satisfied_or_objective_predicate: REJECTED
negative incomparable_identity_reason_cannot_claim_same_target: REJECTED
negative incomparable_target_missing_cannot_claim_same_target: REJECTED
boundary incomparable_metric_unavailable_same_target_is_allowed: PASS (accepted)
DATA-001 VALIDATION PASS: 16 named negatives rejected; 1 boundary case(s) accepted
```

The persistent validator checks issue-head coverage and action references,
finite region containment, before/after frame identity, target consistency,
the `fixed` goal predicate, and incomparable reason semantics (including
fail-closed `target_missing` continuity). JSON Schema alone does not enforce
those arithmetic and cross-record rules.

Enum cross-check against the app source:

```text
python3 - <<'PY'
import json, re
from pathlib import Path
from jsonschema import Draft202012Validator

schema = json.loads(Path("ml/camera_coach/contracts/camera_release_label_v1.schema.json").read_text())
swift = Path("shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift").read_text()
intent = Path("shafinMultitool/Multitool2Module/Models/CameraAnalysis/CaptureIntent.swift").read_text()
def block(text, name):
    match = re.search(r"enum\s+" + name + r"\b[^\{]*\{(.*?)\n\}", text, re.S)
    assert match, name
    return match.group(1)
def values(text, name):
    out = []
    for line in block(text, name).splitlines():
        match = re.search(r"^\s*case\s+(\w+)(?:\s*=\s*\"([^\"]+)\")?", line)
        if match:
            out.append(match.group(2) or re.sub(r"(?<!^)([A-Z])", r"_\1", match.group(1)).lower())
    return out
assert schema["properties"]["verdict"]["enum"][:-1] == values(swift, "FrameVerdict")
assert set(schema["$defs"]["issueID"]["enum"]) == set(values(swift, "IssueTypeV1") + values(swift, "TechnicalQualityIssueType"))
assert set(schema["$defs"]["actionID"]["enum"]) == set(values(swift, "SemanticActionType") + values(swift, "TechnicalQualityActionType"))
assert set(schema["$defs"]["intent"]["properties"]["selection"]["enum"]) == set(values(intent, "CaptureIntentSelection"))
assert set(schema["$defs"]["intent"]["properties"]["styles"]["items"]["enum"]) == set(values(intent, "CaptureStyle"))
assert set(schema["$defs"]["outcomeMetric"]["properties"]["metric_id"]["enum"]) == set(values(swift, "ActionVerificationMetric"))
assert set(schema["$defs"]["comparableOutcome"]["properties"]["outcome"]["enum"]) == set(values(swift, "ActionVerificationOutcome"))
Draft202012Validator.check_schema(schema)
print("enum cross-check: PASS")
PY
```

Result: `enum cross-check: PASS`.

Python syntax check:

```text
python3 -m py_compile ml/camera_coach/contracts/validate_camera_release_label.py
```

Result: exit `0`.

Owned-file whitespace check (untracked files are compared against `/dev/null`):

```text
git diff --check -- ml/camera_coach/contracts docs/implementation/APP_STORE_RELEASE_TRACKER.md docs/implementation/receipts/2026-09-22-data-001-release-label-contract.md
for path in \
  ml/camera_coach/contracts/camera_release_label_v1.schema.json \
  ml/camera_coach/contracts/camera_release_label_v1.md \
  ml/camera_coach/contracts/validate_camera_release_label.py \
  ml/camera_coach/contracts/fixtures/camera_release_label_v1.valid.json \
  ml/camera_coach/contracts/fixtures/camera_release_label_v1.invalid.json \
  docs/implementation/APP_STORE_RELEASE_TRACKER.md \
  docs/implementation/receipts/2026-09-22-data-001-release-label-contract.md; do
  git diff --no-index --check /dev/null "$path" || true
done
```

Result: new contract/fixture/validator/receipt files have no whitespace
errors. The canonical tracker emits only its pre-existing hard-break spaces on
lines 3–7; those bytes were deliberately preserved.

## Final SHA-256 evidence

The parent task reports the final hashes after the receipt is written. The
reproducible command is:

```text
shasum -a 256 \
  ml/camera_coach/contracts/camera_release_label_v1.schema.json \
  ml/camera_coach/contracts/camera_release_label_v1.md \
  ml/camera_coach/contracts/validate_camera_release_label.py \
  ml/camera_coach/contracts/fixtures/camera_release_label_v1.valid.json \
  ml/camera_coach/contracts/fixtures/camera_release_label_v1.invalid.json \
  docs/implementation/APP_STORE_RELEASE_TRACKER.md \
  docs/implementation/receipts/2026-09-22-data-001-release-label-contract.md
```

## Residual gaps

DATA-002 mapping, annotation export integration, and human corpus creation
remain separate tracker tasks. No production Swift or DATA-002 work was
needed for this contract slice.
