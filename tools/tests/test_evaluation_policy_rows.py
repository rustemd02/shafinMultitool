"""Every §5.1 row must say whether it can be computed at all.

The acceptance table names thresholds; a threshold without a definition cannot be
met or failed, only guessed at. `datasets/camera-coach/v1/evaluation-policy-v1.json`
now carries one entry per row with a `definition_status`, and this suite keeps that
registry honest in both directions:

* every row maps to a gate the instrument actually produces, and every §5 gate has
  a row — a new gate cannot appear without a definition decision;
* a row marked `defined_in_evaluator` cites a key that must exist in a real
  evaluator artifact, so the citation is checked rather than trusted;
* a row marked `pending_definition` must not be produced by any tool, so nobody can
  compute an undefined quantity (and by implication invent its denominator).

`pending_definition` is not a defect to hide: it names what the owner or planner has
to write before the row can be measured.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
POLICY_PATH = REPO_ROOT / "datasets/camera-coach/v1/evaluation-policy-v1.json"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"
REAL_SET_METRICS = [
    REPO_ROOT / "docs/cameraanalysis/eval/camera-baseline-v0/drift-174-calibrated-edge-neutral/scored/set_metrics.json",
    REPO_ROOT / "docs/cameraanalysis/eval/camera-baseline-v0/drift-174/scored/set_metrics.json",
]

# row key -> gate name the instrument produces for it
ROW_TO_GATE = {
    "forbidden_violations_rate": "forbidden_violations",
    "critical_forbidden_observed": "critical_forbidden",
    "technical_failure": "technical_failure",
    "gold_independence_and_kappa": "gold_independence_and_kappa",
}


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


gates = _load(GATE_TOOL, "candidate_gates_for_row_tests")
POLICY = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
ROWS = POLICY["runbook_5_1_rows"]["rows"]

# gates that implement a §5.1 row (as opposed to provenance/structure gates)
ROW_GATES = {
    "fp_correct_on_good_frames", "pass_rate", "expected_action_hit", "forbidden_violations",
    "critical_forbidden", "technical_failure", "scene_class_min", "material_organic_source_min",
    "synthetic_adversarial", "confidence_band_accuracy", "abstention_correctness",
    "verification_accuracy", "direction_horizon_precision", "light_exposure_precision",
    "false_improved", "wrong_direction_false_success", "wrong_target_false_success",
    "accepted_coverage_overall", "accepted_coverage_ordinary", "accepted_coverage_difficult_light",
    "human_safe_executable", "human_helpful", "human_preference_non_ties",
    "human_materially_harmful", "human_critical_harm", "gold_independence_and_kappa",
}


def _gate_name(row_key: str) -> str:
    return ROW_TO_GATE.get(row_key, row_key)


@pytest.fixture(scope="module")
def produced_keys() -> set[str]:
    spec = importlib.util.spec_from_file_location(
        "coverage_map", REPO_ROOT / "tools/tests/test_manifest_key_coverage.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["coverage_map"] = module
    spec.loader.exec_module(module)
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        produced = module._run_producers(Path(directory))
    return set().union(*produced.values())


def test_every_row_maps_to_a_gate_the_tool_produces():
    produced_gates = {gate.name for gate in gates.evaluate({})}
    missing = sorted(row for row in ROWS if _gate_name(row) not in produced_gates)
    assert missing == [], f"rows without a produced gate: {missing}"


def test_every_gate_row_has_a_definition_entry():
    declared = {_gate_name(row) for row in ROWS}
    missing = sorted(ROW_GATES - declared)
    assert missing == [], f"§5.1 gates with no definition decision: {missing}"


def test_every_row_states_a_status_and_a_source_or_a_reason():
    for row, entry in ROWS.items():
        assert entry["definition_status"] in {
            "defined_in_evaluator", "defined_in_runbook_prose", "defined_by_schema",
            "partially_defined", "pending_definition",
            # produced by apply_definition_choices.py once the owner picks a reading
            "defined_by_owner_choice"}, row
        assert entry.get("definition_source"), f"{row} has no source or reason"
        assert entry.get("threshold"), f"{row} has no threshold"


def test_a_row_marked_defined_in_evaluator_cites_a_key_that_exists():
    """The citation is checked against a real artifact, not trusted."""
    artifacts = [path for path in REAL_SET_METRICS if path.is_file()]
    if not artifacts:
        pytest.skip("no real set_metrics.json on disk")
    reported = set()
    for path in artifacts:
        reported |= set(json.loads(path.read_text(encoding="utf-8"))["set_metrics"].keys())
    for row, entry in ROWS.items():
        if entry["definition_status"] != "defined_in_evaluator":
            continue
        cited = entry.get("evaluator_key")
        assert cited, f"{row} is marked defined_in_evaluator but carries no evaluator_key"
        assert cited in reported, f"{row} cites {cited!r}, which no evaluator artifact carries"


def test_a_row_without_a_definition_is_not_produced_by_any_tool(produced_keys):
    """Computing an undefined quantity would mean inventing its denominator."""
    offenders = []
    for row, entry in ROWS.items():
        if entry["definition_status"] != "pending_definition":
            continue
        if any(key == f"evaluation.rate_table.{row}" or key.endswith(f".{row}")
               for key in produced_keys):
            offenders.append(row)
    assert offenders == [], f"rows with no definition are being produced: {offenders}"


def _packet_rows() -> list[str]:
    packet = (REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release"
              / "definition-packet-5-1.json")
    return sorted(json.loads(packet.read_text(encoding="utf-8"))["rows"])


def test_the_registry_records_what_the_audit_found():
    """The definition gap is the finding, and the packet is its record.

    The size is pinned on the packet rather than on the policy's current statuses,
    so the owner applying a choice does not make this test lie: the finding stays
    recorded even after every row is defined.
    """
    found = _packet_rows()
    assert len(found) == 10
    assert "direction_horizon_precision" in found
    assert "accepted_coverage_overall" in found

    pending = sorted(row for row, entry in ROWS.items()
                     if entry["definition_status"] == "pending_definition")
    # every row still pending must be one the audit found (before the owner decides),
    # and it can only shrink by being defined
    assert set(pending) <= set(found), sorted(set(pending) - set(found))
