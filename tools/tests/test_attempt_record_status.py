"""The attempt-record status must be derived, not asserted.

`docs/implementation/human-eval/attempt-record-schema.md` §3 says
`record_status = complete` only if nine conditions hold and that a record is never
upgraded by guessing. These tests pin the derivation in both directions: a fully
resolved clean attempt derives `complete`, and every single violation — including
the ones that used to be invisible, like an asserted "complete" with no
`performed_change` — derives `incomplete` and is refused as an overclaim.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/human_eval/validate_attempt_record.py"

BEFORE_SHA = "a" * 64
AFTER_SHA = "b" * 64


def _load():
    spec = importlib.util.spec_from_file_location("validate_attempt_record", TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["validate_attempt_record"] = module
    spec.loader.exec_module(module)
    return module


tool = _load()


def _record(**overrides) -> dict:
    record = {
        "attempt_id": "att-0001",
        "shot_scenario_id": "SL-01",
        "matrix_class": "single_person",
        "split": "calibration",
        "source_shoot_id": "shoot-1",
        "operator_id": "owner",
        "captured_at": "2026-09-13T10:00:00Z",
        "consent_record_id": "consent-1",
        "rights_record_id": "rights-1",
        "provenance_receipt_ref": "receipt-1",
        "proposed_at": "2026-09-13T10:00:05Z",
        "advice_count": 1,
        "proposed_action_id": "move_subject_left",
        "proposed_action_text": "Сдвинь героя чуть левее",
        "proposed_target_refs": ["e1"],
        "understood": "yes",
        "executable": "yes",
        "status": "completed",
        "performed_change": "moved the subject left of frame centre",
        "performed_at": "2026-09-13T10:00:20Z",
        "refusal_reason_source": "not_provided",
        "self_report_author": "owner",
        "before": {"asset_id": "before-1", "sha256": BEFORE_SHA, "captured_at": "2026-09-13T10:00:00Z"},
        "after": {"asset_id": "after-1", "sha256": AFTER_SHA, "captured_at": "2026-09-13T10:00:30Z"},
        "same_context": True,
        "subject_continuity": "same",
        "derivation_kind": "original_before_after_episode",
        "intent": {"style_id": "naturalistic", "intentional": False, "basis": "capture_brief"},
        "target_refs": ["e1"],
        "protected_refs": [],
        "outcome": "correct",
        "outcome_verifier": "subject_position_improves_left",
        "measurement": "before_after",
        "verification_result": "pass",
    }
    record.update(overrides)
    return record


def _resolution() -> dict:
    return {
        "entity_refs": ["e1", "e2"],
        "asset_sha256": [BEFORE_SHA, AFTER_SHA],
        "admitted_consents": ["consent-1"],
        "admitted_rights": ["rights-1"],
    }


def test_a_fully_resolved_clean_attempt_derives_complete():
    result = tool.derive(_record(), _resolution())
    assert result["status"] == "complete", result["reasons"]
    assert result["reasons"] == []


def test_without_resolution_the_record_cannot_be_complete():
    """Conditions 4, 5 and 9 need supplied evidence; absent means unresolved."""
    result = tool.derive(_record(), None)
    assert result["status"] == "incomplete"
    assert any("unresolved" in reason for reason in result["reasons"])
    assert result["conditions"]["ref_resolution"] == "unresolved"
    assert result["conditions"]["rights_resolution"] == "unresolved"


@pytest.mark.parametrize("field,value,fragment", [
    ("advice_count", 2, "integer 1"),
    ("proposed_action_text", "   ", "no shown advice"),
    ("outcome", "correct", "verification_result"),
    ("subject_continuity", "changed", "subject_continuity"),
    ("matrix_class", "not_a_class", "matrix_class"),
    ("understood", "maybe", "understood"),
    ("derivation_kind", "crop_pair", "derivation_kind"),
])
def test_a_single_enum_or_rule_violation_makes_it_incomplete(field, value, fragment):
    record = _record(**{field: value})
    if field == "outcome":
        record["verification_result"] = "fail"
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any(fragment in reason for reason in result["reasons"]), result["reasons"]


def test_completed_without_performed_change_is_incomplete():
    record = _record(performed_change="")
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("performed_change" in reason for reason in result["reasons"])


def test_completed_without_an_after_side_is_incomplete():
    record = _record()
    record.pop("after")
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("after" in reason for reason in result["reasons"])


def test_non_increasing_timestamps_are_incomplete():
    record = _record(proposed_at="2026-09-13T10:00:00Z")  # equal to captured_at
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("strictly increase" in reason for reason in result["reasons"])


def test_a_non_utc_timestamp_is_incomplete():
    record = _record(proposed_at="2026-09-13 10:00:05")
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("UTC Z" in reason for reason in result["reasons"])


def test_identical_before_and_after_digests_are_not_an_episode():
    record = _record()
    record["after"]["sha256"] = BEFORE_SHA
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("not an episode" in reason for reason in result["reasons"])


def test_a_dangling_target_ref_is_incomplete():
    record = _record(target_refs=["e1", "e999"], proposed_target_refs=["e999"])
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("do not resolve" in reason for reason in result["reasons"])


def test_a_digest_that_matches_no_real_asset_is_incomplete():
    record = _record()
    record["before"]["sha256"] = "c" * 64
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert any("do not match real assets" in reason for reason in result["reasons"])


def test_an_unadmitted_rights_record_is_incomplete():
    resolution = _resolution()
    resolution["admitted_rights"] = ["other-rights"]
    result = tool.derive(_record(), resolution)
    assert result["status"] == "incomplete"
    assert any("rights_record_id" in reason for reason in result["reasons"])


def test_a_declined_attempt_is_a_complete_record_but_not_a_success():
    """§3 keeps the two axes apart: declined is a valid record, not an episode."""
    record = _record(status="declined", outcome="incomparable")
    record.pop("after")
    record.pop("performed_change")
    record.pop("measurement")
    result = tool.derive(record, _resolution())
    assert result["status"] == "complete", result["reasons"]
    assert result["is_success"] is False


def test_a_completed_attempt_is_reported_as_a_success():
    result = tool.derive(_record(), _resolution())
    assert result["status"] == "complete"
    assert result["is_success"] is True


# ------------------------------------------------------------------ CLI behaviour
def _write(tmp_path: Path, name: str, payload) -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return path


def test_cli_refuses_an_asserted_complete_that_the_derivation_contradicts(tmp_path: Path):
    record = _record(record_status="complete", performed_change="")
    record_path = _write(tmp_path, "attempt.json", record)
    assert tool.main(["--record", str(record_path)]) == 1


def test_cli_exits_zero_when_nothing_overclaims(tmp_path: Path, capsys):
    record_path = _write(tmp_path, "attempt.json", _record())
    out = tmp_path / "derived.json"
    assert tool.main(["--record", str(record_path), "--resolution", str(tmp_path / "r.json"),
                      "--json-out", str(out)]) == 2  # resolution file does not exist yet

    resolution_path = _write(tmp_path, "r.json", _resolution())
    assert tool.main(["--record", str(record_path), "--resolution", str(resolution_path),
                      "--json-out", str(out)]) == 0
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert payload["results"][0]["derived_record_status"] == "complete"
    assert payload["validity_checked"] is False
    assert "shot-list validity is a separate axis" in payload["note"]


def test_cli_fails_closed_on_an_empty_file(tmp_path: Path, capsys):
    empty = tmp_path / "empty.jsonl"
    empty.write_text("", encoding="utf-8")
    assert tool.main(["--records", str(empty)]) == 2
    assert "FAIL CLOSED" in capsys.readouterr().err


def test_cli_reports_a_jsonl_batch_and_flags_the_one_overclaimer(tmp_path: Path):
    good = _record(attempt_id="att-0001")
    bad = _record(attempt_id="att-0002", record_status="complete", advice_count=3)
    batch = tmp_path / "batch.jsonl"
    batch.write_text("\n".join(json.dumps(item, ensure_ascii=False) for item in (good, bad)) + "\n",
                     encoding="utf-8")
    assert tool.main(["--records", str(batch), "--resolution", str(_write(tmp_path, "r.json", _resolution()))]) == 1


# ------------------------------------------------------- the unenforced rules
# These mutations all used to derive `complete`: the schema required them (§2/§3)
# and the derivation never looked. Each now has to make the record incomplete.
@pytest.mark.parametrize("name,mutate", [
    ("intent.intentional absent", lambda r: r["intent"].pop("intentional")),
    ("intent.intentional not a bool", lambda r: r["intent"].__setitem__("intentional", "maybe")),
    ("before.asset_id absent", lambda r: r["before"].pop("asset_id")),
    ("before.captured_at absent", lambda r: r["before"].pop("captured_at")),
    ("after.captured_at absent while completed", lambda r: r["after"].pop("captured_at")),
    ("performed_at absent while completed", lambda r: r.pop("performed_at")),
    ("same_context false", lambda r: r.__setitem__("same_context", False)),
    ("target_refs empty", lambda r: r.__setitem__("target_refs", [])),
    ("proposed_target_refs empty", lambda r: r.__setitem__("proposed_target_refs", [])),
    ("proposed_action_id outside actionId", lambda r: r.__setitem__("proposed_action_id", "reposition_entity")),
    ("outcome_verifier outside verifierId", lambda r: r.__setitem__("outcome_verifier", "verifier-reposition-v1")),
    ("attempt_id violates its pattern", lambda r: r.__setitem__("attempt_id", "ATT 0001")),
    ("shot_scenario_id outside SL-01..SL-10", lambda r: r.__setitem__("shot_scenario_id", "SL-99")),
    ("refusal_reason outside the closed set", lambda r: r.__setitem__("refusal_reason", "because")),
    ("performed_action_id outside actionId", lambda r: r.__setitem__("performed_action_id", "bogus")),
    ("before.captured_at after proposed_at", lambda r: r["before"].__setitem__("captured_at", "2026-09-13T10:00:09Z")),
    ("advice_count is the bool True", lambda r: r.__setitem__("advice_count", True)),
    ("advice_count is a float", lambda r: r.__setitem__("advice_count", 1.0)),
    ("action_latency_ms contradicts the timestamps", lambda r: r.__setitem__("action_latency_ms", 1)),
    ("action_latency_ms negative", lambda r: r.__setitem__("action_latency_ms", -5)),
    ("measurement outside its closed set", lambda r: r.__setitem__("measurement", "eyeballed")),
])
def test_a_rule_the_schema_states_but_the_derivation_ignored_now_fails_closed(name, mutate):
    record = _record()
    mutate(record)
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete", f"{name} still derived complete"
    assert result["is_success"] is False


def test_failed_attempt_requires_performed_at():
    record = _record(status="failed_attempt", outcome="incomparable")
    record.pop("performed_at")
    record.pop("measurement")
    result = tool.derive(record, _resolution())
    assert any("performed_at" in reason for reason in result["reasons"]), result["reasons"]


# --------------------------------------------- every declared condition is live
# One mutation per enforced condition. If a check is deleted the matching mutation
# stops flipping its condition, so this sweep goes red instead of quietly passing.
CONDITION_MUTATIONS = {
    "required_fields": lambda r: r.pop("operator_id"),
    "identifiers": lambda r: r.__setitem__("attempt_id", "not an id"),
    "enum_membership": lambda r: r.__setitem__("matrix_class", "not_a_class"),
    "intent_declaration": lambda r: r["intent"].pop("intentional"),
    "context_declaration": lambda r: r.__setitem__("same_context", False),
    "ref_cardinality": lambda r: r.__setitem__("target_refs", []),
    "chronology": lambda r: r.__setitem__("proposed_at", "2026-09-13T10:00:00Z"),
    "before_chronology": lambda r: r["before"].__setitem__("captured_at", "2026-09-13T10:00:09Z"),
    "single_advice": lambda r: r.__setitem__("advice_count", 2),
    "measurable_outcome": lambda r: r.__setitem__("verification_result", "fail"),
    "completed_proof": lambda r: r.__setitem__("performed_change", ""),
    "asset_identity": lambda r: r["after"].__setitem__("sha256", BEFORE_SHA),
    "latency_consistency": lambda r: r.__setitem__("action_latency_ms", 1),
    "ref_resolution": lambda r: r.__setitem__("target_refs", ["e999"]),
    "asset_match": lambda r: r["before"].__setitem__("sha256", "c" * 64),
    "rights_resolution": lambda r: r.__setitem__("rights_record_id", "other-rights"),
}


def test_the_condition_declaration_matches_the_mutations():
    """Adding or dropping an enforced condition without updating the sweep must fail."""
    assert set(CONDITION_MUTATIONS) == set(tool.ENFORCED_CONDITIONS)
    assert tool.ENFORCED_CONDITIONS, "an empty condition list would make the sweep vacuous"


@pytest.mark.parametrize("condition", sorted(CONDITION_MUTATIONS))
def test_every_enforced_condition_can_be_violated_by_a_real_record(condition):
    record = _record()
    CONDITION_MUTATIONS[condition](record)
    result = tool.derive(record, _resolution())
    assert result["status"] == "incomplete"
    assert result["conditions"][condition] == "violated", result["conditions"]


def test_a_clean_record_meets_every_enforced_condition():
    result = tool.derive(_record(), _resolution())
    assert set(result["conditions"]) == set(tool.ENFORCED_CONDITIONS)
    unmet = {name: value for name, value in result["conditions"].items() if value != "met"}
    assert unmet == {}, unmet


# -------------------------------------------- the vocabulary is not optional
def test_an_unreadable_frozen_vocabulary_is_not_a_pass():
    """An absent reference list must leave checks unresolved, never skipped."""
    result = tool.derive(_record(), _resolution(), vocab={})
    assert result["status"] == "incomplete"
    assert any("frozen vocabulary" in reason for reason in result["reasons"]), result["reasons"]


def test_the_frozen_vocabulary_is_loaded_from_the_repository_artifacts():
    vocab, problems = tool.frozen_vocabulary()
    assert problems == []
    assert len(vocab["action_id"]) == 26
    assert len(vocab["verifier_id"]) == 23
    assert vocab["shot_scenario"] == {f"SL-{n:02d}" for n in range(1, 11)}


def test_the_unenforced_requirements_are_declared_rather_than_implied():
    declared = dict(tool.NOT_ENFORCED_CONDITIONS)
    for required in ("case_id", "proposed_protected_refs", "validity"):
        assert required in declared, f"{required} is not declared as unenforced"
    assert all(why.strip() for why in declared.values())


def test_a_keep_attempt_is_a_complete_record_that_executed_no_episode():
    """§2.4 exempts KEEP from the after side; §3 keeps it out of the episode counts."""
    record = _record(proposed_action_id="keep_current_setup", outcome="incomparable")
    record.pop("after")
    record.pop("measurement")
    result = tool.derive(record, _resolution())
    assert result["status"] == "complete", result["reasons"]
    assert result["is_keep"] is True
    assert result["is_success"] is False


def test_the_payload_declares_the_enforced_and_unenforced_sets(tmp_path: Path):
    record_path = _write(tmp_path, "attempt.json", _record())
    out = tmp_path / "derived.json"
    assert tool.main(["--record", str(record_path),
                      "--resolution", str(_write(tmp_path, "r.json", _resolution())),
                      "--json-out", str(out)]) == 0
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert payload["enforced_conditions"] == sorted(tool.ENFORCED_CONDITIONS)
    assert payload["frozen_vocabulary"]["action_id"] == 26
    assert payload["vocabulary_problems"] == []
    declared = {item["condition"] for item in payload["conditions_not_enforced"]}
    assert declared == {name for name, _ in tool.NOT_ENFORCED_CONDITIONS}
