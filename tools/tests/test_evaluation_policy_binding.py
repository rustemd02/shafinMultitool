"""The frozen evaluation policy must bind the gate instrument.

`datasets/camera-coach/v1/evaluation-policy-v1.json` is the versioned acceptance
policy the runbook requires before the locked test. A policy that merely restates
numbers is decoration, so this suite binds it to behaviour in both directions:

* with every measured value set exactly to its frozen threshold, the matching gate
  does not fail;
* nudging that one value past its threshold flips that gate to fail.

It also checks coverage both ways: every threshold the policy declares must
correspond to a gate the instrument actually produces, and every thresholded gate
the instrument produces must be declared in the policy. A gate that exists only in
code (a silently added threshold) or only in the policy (an unenforced requirement)
fails here.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
POLICY_PATH = REPO_ROOT / "datasets/camera-coach/v1/evaluation-policy-v1.json"
TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"


def _load_tool():
    spec = importlib.util.spec_from_file_location("candidate_gates_policy_binding", TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["candidate_gates_policy_binding"] = module
    spec.loader.exec_module(module)
    return module


gates = _load_tool()
POLICY = json.loads(POLICY_PATH.read_text(encoding="utf-8"))

NUDGE = 0.001
WILSON_N = 2000  # large enough that the Wilson lower bound clears the point rule


def _gate(manifest: dict, name: str):
    return next(g for g in gates.evaluate(manifest) if g.name == name)


def _at_threshold_manifest() -> dict:
    """A manifest whose measured values sit exactly on the frozen thresholds."""
    rate_table: dict = {}
    for spec in POLICY["rate_gates"].values():
        rate_table[spec["manifest_key"]] = spec["threshold"]
    for spec in POLICY["precision_gates"].values():
        rate_table[spec["hits_key"]] = int(round(spec["point"] * WILSON_N))
        rate_table[spec["n_key"]] = WILSON_N
    for spec in POLICY["zero_gates"].values():
        if "manifest_path" not in spec:
            rate_table[spec["key"]] = spec["must_equal"]
    return {
        "evaluation": {
            "rate_table": rate_table,
            "false_improved": {"wrong_confirmations": 1, "improved_issued": 100,
                               "wrong_improved": 1, "non_improved_episodes": 100},
            "human": {
                "safe_and_executable": POLICY["human_gates"]["safe_and_executable"]["threshold"],
                "helpful": POLICY["human_gates"]["helpful"]["threshold"],
                "preference_non_ties": POLICY["human_gates"]["preference_non_ties"]["threshold"],
                "materially_harmful": POLICY["human_gates"]["materially_harmful"]["threshold"],
                "critical_harm": POLICY["zero_gates"]["human_critical_harm"]["must_equal"],
            },
            "neural_gain": {"clusters": [[9, 10, 6, 10] for _ in range(40)],
                            "point_gain_pp": POLICY["neural_gain"]["point_gain_pp_min"],
                            "safety_not_worse": True,
                            "subset": "protected semantic"},
            "confusion": {"correct": 900, "keep": 300, "abstain": 150, "incomparable": 50,
                          "forbidden_advised": 0, "evaluated_total": 1400},
        }
    }


# ------------------------------------------------------- constants are the same
def test_constant_blocks_match_the_policy_exactly():
    assert gates.FP_CORRECT_BUDGET == POLICY["good_frame_budget"]["budget"]
    assert gates.FP_CORRECT_MIN_CLUSTERS == POLICY["good_frame_budget"]["min_clusters"]
    assert gates.NEURAL_GAIN_PP * 100 == POLICY["neural_gain"]["point_gain_pp_min"]
    assert gates.QUOTAS == POLICY["quotas"]
    assert gates.PER_CLASS_FLOORS == POLICY["per_class_floors"]
    assert gates.PER_ACTION_FLOORS == POLICY["per_action_floors"]
    assert gates.EPISODE_FLOORS == POLICY["episode_floors"]


def test_gold_floors_match_the_policy_exactly():
    gold = POLICY["gold"]
    for key, value in gates.GOLD_FLOORS.items():
        assert gold[key] == value, f"GOLD_FLOORS[{key}]={value} but policy says {gold.get(key)}"


# ---------------------------------------------------------- values at threshold
def test_every_value_at_its_frozen_threshold_passes_its_gate():
    manifest = _at_threshold_manifest()
    names = [spec["gate_name"] if "gate_name" in spec else name
             for name, spec in POLICY["rate_gates"].items()]
    names += [spec["gate_name"] for spec in POLICY["precision_gates"].values()]
    names += [spec["gate_name"] for spec in POLICY["zero_gates"].values()]
    names += ["false_improved", "neural_gain_over_baseline"]
    names += [spec["gate_name"] for spec in POLICY["human_gates"].values()]
    for name in names:
        gate = _gate(manifest, name)
        assert gate.state == "pass", f"{name}: {gate.state} ({gate.detail})"


def test_the_all_silence_run_cannot_pass_the_good_frame_budget():
    manifest = _at_threshold_manifest()
    manifest["evaluation"]["fp_correct"] = {
        "good_frames_with_forbidden_correction": 0, "good_frames_evaluated": 1400,
        "cluster_count": 40, "keep_rate": 1.0, "abstain_rate": 0.0,
    }
    gate = _gate(manifest, "fp_correct_on_good_frames")
    assert gate.state == "fail"
    assert "all-silence" in gate.detail


# ------------------------------------------------------ nudged past threshold
@pytest.mark.parametrize("name", sorted(POLICY["rate_gates"]))
def test_a_rate_moved_past_its_threshold_fails_its_gate(name):
    spec = POLICY["rate_gates"][name]
    manifest = _at_threshold_manifest()
    table = manifest["evaluation"]["rate_table"]
    if spec["direction"] == "at_least":
        table[spec["manifest_key"]] = spec["threshold"] - NUDGE
    else:
        table[spec["manifest_key"]] = spec["threshold"] + NUDGE
    gate_name = spec.get("gate_name", name)
    assert _gate(manifest, gate_name).state == "fail"


@pytest.mark.parametrize("zero_name", sorted(POLICY["zero_gates"]))
def test_a_zero_gate_moved_off_zero_fails(zero_name):
    spec = POLICY["zero_gates"][zero_name]
    manifest = _at_threshold_manifest()
    if "manifest_path" in spec:
        manifest["evaluation"]["human"]["critical_harm"] = 1
    else:
        manifest["evaluation"]["rate_table"][spec["key"]] = 1
    assert _gate(manifest, spec["gate_name"]).state == "fail"


@pytest.mark.parametrize("family", sorted(POLICY["precision_gates"]))
def test_precision_below_the_point_rule_fails(family):
    spec = POLICY["precision_gates"][family]
    manifest = _at_threshold_manifest()
    manifest["evaluation"]["rate_table"][spec["hits_key"]] = int(round((spec["point"] - NUDGE) * WILSON_N))
    assert _gate(manifest, spec["gate_name"]).state == "fail"


@pytest.mark.parametrize("family", sorted(POLICY["precision_gates"]))
def test_precision_point_met_but_lower_bound_short_is_insufficient_evidence(family):
    spec = POLICY["precision_gates"][family]
    manifest = _at_threshold_manifest()
    n = 100  # at n=100 a point of 0.95 leaves the Wilson lower bound near 0.888
    hits = int(round(spec["point"] * n))
    table = manifest["evaluation"]["rate_table"]
    table[spec["hits_key"]] = hits
    table[spec["n_key"]] = n
    gate = _gate(manifest, spec["gate_name"])
    if gates.wilson_lower(hits, n) < spec["wilson_lower_95"]:
        assert gate.state == "insufficient_evidence"
    else:
        assert gate.state == "pass"


# ---------------------------------------------------------------- coverage both ways
def _declared_gate_names() -> set[str]:
    names = {spec.get("gate_name", name) for name, spec in POLICY["rate_gates"].items()}
    names |= {spec["gate_name"] for spec in POLICY["precision_gates"].values()}
    names |= {spec["gate_name"] for spec in POLICY["zero_gates"].values()}
    names |= {spec["gate_name"] for spec in POLICY["human_gates"].values()}
    names |= {"false_improved", "neural_gain_over_baseline", "fp_correct_on_good_frames",
              "confusion_matrix_integrity"}
    return names


# Structural gates whose thresholds are the quota/floor/gold/provenance blocks above.
STRUCTURAL_GATES = {"quotas", "per_class_floors", "per_action_floors", "gold_independence_and_kappa",
                    "weight_lineage_release_cleared", "trained_heads_backed_by_evidence",
                    "split_disjointness"}


def test_every_thresholded_gate_the_tool_produces_is_declared_in_the_policy():
    produced = {gate.name for gate in gates.evaluate(_at_threshold_manifest())}
    assert produced - _declared_gate_names() <= STRUCTURAL_GATES, sorted(produced - _declared_gate_names() - STRUCTURAL_GATES)


def test_every_declared_policy_threshold_has_a_produced_gate():
    produced = {gate.name for gate in gates.evaluate(_at_threshold_manifest())}
    missing = sorted(name for name in _declared_gate_names() if name not in produced)
    assert missing == [], missing


def test_the_policy_declares_its_unenforced_requirements_rather_than_hiding_them():
    uncovered = POLICY["runbook_requirements_not_enforced_by_the_instrument"]
    assert isinstance(uncovered, list) and uncovered
    assert all(isinstance(item, str) and item for item in uncovered)


def test_the_policy_carries_thresholds_only_no_measurements():
    """Numbers may appear only inside declared threshold/quota blocks.

    A rate recorded outside those blocks would read as a measurement of the
    candidate, which a policy must never contain.
    """
    threshold_blocks = {
        "good_frame_budget", "rate_gates", "precision_gates", "zero_gates", "false_improved",
        "human_gates", "neural_gain", "quotas", "per_class_floors", "per_action_floors",
        "episode_floors", "gold",
    }
    offenders: list[str] = []

    def walk(node, path: str) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                walk(value, f"{path}.{key}" if path else key)
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]")
        elif isinstance(node, (int, float)) and not isinstance(node, bool):
            root = path.split(".")[0].split("[")[0]
            if root not in threshold_blocks:
                offenders.append(path)

    walk(POLICY, "")
    assert offenders == [], offenders


def test_the_pending_pilot_parameters_are_null_and_flagged():
    pending = POLICY["pending_pilot_parameters"]
    assert pending["status"].startswith("not frozen")
    assert all(value is None for value in pending["items"].values())
