"""Self-tests for the candidate gate evaluator.

These tests exist because the runbook forbids earning a PASS from a checker whose
own self-test never touches a candidate manifest: the numbers below are checked
against independently derivable reference values, and every "no data" path must
fail closed rather than default to success.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"


def _load():
    spec = importlib.util.spec_from_file_location("candidate_gates", TOOL)
    module = importlib.util.module_from_spec(spec)
    sys.modules["candidate_gates"] = module
    spec.loader.exec_module(module)
    return module


gates = _load()


# ----------------------------------------------------------------- reference maths
def test_clopper_pearson_upper_matches_the_runbook_reference():
    """The runbook states 0/81 still leaves a one-sided upper bound near 3.6%."""
    upper = gates.clopper_pearson_upper(0, 81)
    assert upper == pytest.approx(0.0363, abs=0.0005), upper


def test_clopper_pearson_upper_shrinks_with_more_clean_frames():
    assert gates.clopper_pearson_upper(0, 1400) < 0.003
    assert gates.clopper_pearson_upper(0, 1400) < gates.clopper_pearson_upper(0, 81)


def test_wilson_lower_matches_reference_value():
    # standard Wilson 95% lower bound for 95/100 (published CI ~[0.888, 0.980])
    assert gates.wilson_lower(95, 100) == pytest.approx(0.8882, abs=0.0005)


# ----------------------------------------------------------------- fp_correct gate
def _manifest(**overrides) -> dict:
    base = json.loads(json.dumps(gates.TEMPLATE))
    base.update(overrides)
    return base


def _fp_gate(manifest):
    return next(g for g in gates.evaluate(manifest) if g.name == "fp_correct_on_good_frames")


def test_clean_large_set_passes_the_fp_correct_budget():
    manifest = _manifest(evaluation={"fp_correct": {
        "good_frames_with_forbidden_correction": 0, "good_frames_evaluated": 1400,
                       "cluster_count": 40,
        "keep_rate": 0.3, "abstain_rate": 0.2}})
    gate = _fp_gate(manifest)
    assert gate.state == "pass", gate.detail


def test_small_lucky_set_is_insufficient_not_a_pass():
    """0/100 has an upper bound above 2%, so it cannot prove the budget."""
    manifest = _manifest(evaluation={"fp_correct": {
        "good_frames_with_forbidden_correction": 0, "good_frames_evaluated": 100,
                       "cluster_count": 40,
        "keep_rate": 0.3, "abstain_rate": 0.2}})
    gate = _fp_gate(manifest)
    assert gate.state == "insufficient_evidence", gate.detail
    assert gate.observed["upper_95"] > 0.02


def test_point_estimate_above_budget_fails_even_with_many_frames():
    manifest = _manifest(evaluation={"fp_correct": {
        "good_frames_with_forbidden_correction": 30, "good_frames_evaluated": 1000,
                       "cluster_count": 40,
        "keep_rate": 0.3, "abstain_rate": 0.2}})
    gate = _fp_gate(manifest)
    assert gate.state == "fail", gate.detail


def test_all_silence_cannot_pass():
    """Empty ABSTAIN on every frame is a forbidden way to obtain PASS."""
    manifest = _manifest(evaluation={"fp_correct": {
        "good_frames_with_forbidden_correction": 0, "good_frames_evaluated": 1400,
                       "cluster_count": 40,
        "keep_rate": 0.0, "abstain_rate": 1.0}})
    gate = _fp_gate(manifest)
    assert gate.state == "fail"
    assert "silence" in gate.detail or "KEEP" in gate.detail


def test_missing_fp_block_is_not_measurable():
    gate = _fp_gate(_manifest(evaluation={}))
    assert gate.state == "not_measurable"


# ----------------------------------------------------------------- neural gain gate
def _gain_gate(manifest):
    return next(g for g in gates.evaluate(manifest) if g.name == "neural_gain_over_baseline")


def test_neural_gain_pass_requires_positive_bootstrap_lower_bound():
    clusters = [[9, 10, 6, 10] for _ in range(40)]
    manifest = _manifest(evaluation={"neural_gain": {
        "clusters": clusters, "point_gain_pp": 30.0, "safety_not_worse": True}})
    gate = _gain_gate(manifest)
    assert gate.state == "pass", gate.detail
    assert gate.observed["bootstrap_lower"] > 0


def test_identical_neural_and_baseline_fail_the_gain_gate():
    clusters = [[7, 10, 7, 10] for _ in range(40)]
    manifest = _manifest(evaluation={"neural_gain": {
        "clusters": clusters, "point_gain_pp": 0.0, "safety_not_worse": True}})
    gate = _gain_gate(manifest)
    assert gate.state == "fail", gate.detail


def test_neural_gain_with_one_cluster_is_not_measurable():
    manifest = _manifest(evaluation={"neural_gain": {
        "clusters": [[9, 10, 5, 10]], "point_gain_pp": 40.0, "safety_not_worse": True}})
    gate = _gain_gate(manifest)
    assert gate.state == "not_measurable"


def test_safety_regression_fails_even_with_big_gain():
    clusters = [[9, 10, 6, 10] for _ in range(40)]
    manifest = _manifest(evaluation={"neural_gain": {
        "clusters": clusters, "point_gain_pp": 30.0, "safety_not_worse": False}})
    assert _gain_gate(manifest).state == "fail"


# ----------------------------------------------------------------- structural gates
def test_heads_claimed_trained_without_evidence_fail():
    manifest = _manifest(trained_heads={"issue_logits": True, "risk_probability": True},
                         training_evidence={"issue_logits": {"receipt": "r"}})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "trained_heads_backed_by_evidence")
    assert gate.state == "fail"
    assert "risk_probability" in gate.detail


def test_evaluation_must_run_on_the_locked_split():
    manifest = _manifest(evaluated_split="validation",
                         splits={"train": {"manifest_sha256": "a"}, "validation": {"manifest_sha256": "b"},
                                 "calibration": {"manifest_sha256": "c"}, "locked": {"manifest_sha256": "d"}})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "split_disjointness")
    assert gate.state == "fail"


def test_reused_split_manifest_hash_fails():
    manifest = _manifest(splits={"train": {"manifest_sha256": "same"}, "validation": {"manifest_sha256": "same"},
                                 "calibration": {"manifest_sha256": "c"}, "locked": {"manifest_sha256": "d"}})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "split_disjointness")
    assert gate.state == "fail"


def test_gold_with_one_annotator_fails():
    manifest = _manifest(gold={"annotators": 1, "hidden_qc_rate": 0.05, "adjudicated_review_rate": 0.10,
                               "kappa_keep_correct_abstain": 0.9, "kappa_action_family": 0.9,
                               "forbidden_agreement": 0.95, "median_roi_iou": 0.9, "hidden_qc": 0.99})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "gold_independence_and_kappa")
    assert gate.state == "fail"
    assert "annotators" in gate.detail


def _valid_gold(**overrides) -> dict:
    gold = {"annotators": 2, "hidden_qc_rate": 0.05, "adjudicated_review_rate": 0.10,
            "kappa_keep_correct_abstain": 0.9, "kappa_action_family": 0.9,
            "forbidden_agreement": 0.95, "median_roi_iou": 0.9, "hidden_qc": 0.99,
            "annotators_are_distinct_humans": True,
            "ai_suggestions_in_independent_pass": False}
    gold.update(overrides)
    return gold


def _gold_gate(**overrides):
    return next(g for g in gates.evaluate(_manifest(gold=_valid_gold(**overrides)))
                if g.name == "gold_independence_and_kappa")


def test_a_fully_declared_valid_gold_block_passes():
    """The new declarations are not a blanket fail: declaring them correctly clears."""
    assert _gold_gate().state == "pass"


def test_gold_with_ai_suggestions_visible_fails():
    gate = _gold_gate(ai_suggestions_in_independent_pass=True)
    assert gate.state == "fail"
    assert "ai_suggestions_in_independent_pass" in gate.detail


def test_gold_omitting_the_ai_suggestion_declaration_fails():
    """An omitted independence fact is a violated one, not a silent pass."""
    gold = _valid_gold()
    del gold["ai_suggestions_in_independent_pass"]
    gate = next(g for g in gates.evaluate(_manifest(gold=gold))
                if g.name == "gold_independence_and_kappa")
    assert gate.state == "fail"
    assert "ai_suggestions_in_independent_pass" in gate.detail


def test_gold_omitting_the_distinct_human_declaration_fails():
    """Two annotator ids are not two humans unless the owner declares it."""
    gold = _valid_gold()
    del gold["annotators_are_distinct_humans"]
    gate = next(g for g in gates.evaluate(_manifest(gold=gold))
                if g.name == "gold_independence_and_kappa")
    assert gate.state == "fail"
    assert "annotators_are_distinct_humans" in gate.detail


def test_gold_denying_distinct_humans_fails():
    assert _gold_gate(annotators_are_distinct_humans=False).state == "fail"


def test_zero_improved_issued_fails_false_improved_gate():
    manifest = _manifest(evaluation={"false_improved": {
        "wrong_confirmations": 0, "improved_issued": 0,
        "wrong_improved": 0, "non_improved_episodes": 10, "incomparable_in_confusion": True}})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "false_improved")
    assert gate.state == "fail"
    assert "precision is undefined" in gate.detail


# ----------------------------------------------------------------- full candidate
def _complete_manifest() -> dict:
    manifest = _manifest(
        trained_heads={"issue_logits": True},
        contract_heads=["issue_logits", "risk_probability"],
        untrained_head_mask=["risk_probability"],
        training_evidence={"issue_logits": {"receipt": "receipts/issue.json", "sha256": "x",
                                            "artifact": "set_composition_net_v2.mlpackage"}},
        weight_lineage=[{"artifact": "set_composition_net_v2.mlpackage", "sha256": "abc",
                         "training_data_lineage": "admitted:cinematic-ccby", "release_cleared": True,
                         "basis": "CC-BY attribution generated; Packet A decision A1 recorded",
                         "basis_reference": "evidence-release/rights-attestation.json",
                         "basis_sha256": "0" * 64}],
        evaluated_split="locked",
        splits={"train": {"manifest_sha256": "a"}, "validation": {"manifest_sha256": "b"},
                "calibration": {"manifest_sha256": "c"}, "locked": {"manifest_sha256": "d"}},
        quota_counts={k: v for k, v in gates.QUOTAS.items()},
        per_class_counts={"landscape": {k: v for k, v in gates.PER_CLASS_FLOORS.items()}},
        per_action_counts={"level_horizon": {**{k: v for k, v in gates.PER_ACTION_FLOORS.items()},
                                             "episodes": dict(gates.EPISODE_FLOORS)}},
        gold={"annotators": 2, "hidden_qc_rate": 0.05, "adjudicated_review_rate": 0.10,
              "kappa_keep_correct_abstain": 0.81, "kappa_action_family": 0.76,
              "forbidden_agreement": 0.91, "median_roi_iou": 0.81, "hidden_qc": 0.96,
              "annotators_are_distinct_humans": True,
              "ai_suggestions_in_independent_pass": False},
    )
    manifest["evaluation"] = {
        "fp_correct": {"good_frames_with_forbidden_correction": 0, "good_frames_evaluated": 1400,
                       "cluster_count": 40,
                       "cluster_count": 40,
                       "keep_rate": 0.3, "abstain_rate": 0.2},
        "rate_table": {
            "pass_rate": 0.91, "expected_action_hit": 0.91, "forbidden_violations_rate": 0.01,
            "critical_forbidden_observed": 0, "technical_failure_pass_rate": 1.0,
            "scene_class_min": 0.86, "material_organic_source_min": 0.81, "synthetic_adversarial": 0.66,
            "confidence_band_accuracy": 0.91, "abstention_correctness": 0.91, "verification_accuracy": 0.91,
            "direction_horizon_hits": 970, "direction_horizon_n": 1000,
            "light_exposure_hits": 940, "light_exposure_n": 1000,
            "accepted_coverage_overall": 0.66, "accepted_coverage_ordinary": 0.56,
            "accepted_coverage_difficult_light": 0.36,
            "wrong_direction_false_success": 0, "wrong_target_false_success": 0,
        },
        "false_improved": {"wrong_confirmations": 1, "improved_issued": 100,
                           "wrong_improved": 1, "non_improved_episodes": 50,
                           "incomparable_in_confusion": True},
        "human": {"safe_and_executable": 0.91, "helpful": 0.81, "preference_non_ties": 0.61,
                  "materially_harmful": 0.005, "critical_harm": 0},
        "neural_gain": {"clusters": [[9, 10, 6, 10] for _ in range(40)],
                        "point_gain_pp": 30.0, "safety_not_worse": True, "subset": "protected semantic"},
        "confusion": {"correct": 900, "keep": 300, "abstain": 150, "incomparable": 50,
                      "forbidden_advised": 0, "evaluated_total": 1400},
    }
    return manifest


def test_complete_candidate_passes_every_mandatory_gate():
    report, failed = gates.render(gates.evaluate(_complete_manifest()))
    assert not failed, report


def test_an_empty_manifest_cannot_pass():
    """The whole point: absent evidence must never read as success."""
    report, failed = gates.render(gates.evaluate({}))
    assert failed
    assert "NOT A RELEASE CANDIDATE" in report


# ------------------------------------------------------------ fail-closure sweep
# Which manifest block each gate reads. The module promises that "every no-data
# path must fail closed"; this table states that promise once per gate, so a gate
# that would default to `pass` when its evidence is missing cannot be added
# quietly. Every produced gate must appear here, and removing its evidence must
# take it out of `pass`.
GATE_EVIDENCE: dict[str, tuple[str, ...]] = {
    "fp_correct_on_good_frames": ("evaluation.fp_correct",),
    "pass_rate": ("evaluation.rate_table",),
    "expected_action_hit": ("evaluation.rate_table",),
    "forbidden_violations": ("evaluation.rate_table",),
    "critical_forbidden": ("evaluation.rate_table",),
    "technical_failure": ("evaluation.rate_table",),
    "scene_class_min": ("evaluation.rate_table",),
    "material_organic_source_min": ("evaluation.rate_table",),
    "synthetic_adversarial": ("evaluation.rate_table",),
    "confidence_band_accuracy": ("evaluation.rate_table",),
    "abstention_correctness": ("evaluation.rate_table",),
    "verification_accuracy": ("evaluation.rate_table",),
    "direction_horizon_precision": ("evaluation.rate_table",),
    "light_exposure_precision": ("evaluation.rate_table",),
    "accepted_coverage_overall": ("evaluation.rate_table",),
    "accepted_coverage_ordinary": ("evaluation.rate_table",),
    "accepted_coverage_difficult_light": ("evaluation.rate_table",),
    "wrong_direction_false_success": ("evaluation.rate_table",),
    "wrong_target_false_success": ("evaluation.rate_table",),
    "false_improved": ("evaluation.false_improved",),
    "confusion_matrix_integrity": ("evaluation.confusion",),
    "human_safe_executable": ("evaluation.human",),
    "human_helpful": ("evaluation.human",),
    "human_preference_non_ties": ("evaluation.human",),
    "human_materially_harmful": ("evaluation.human",),
    "human_critical_harm": ("evaluation.human",),
    "neural_gain_over_baseline": ("evaluation.neural_gain",),
    "trained_heads_backed_by_evidence": ("trained_heads", "training_evidence"),
    "split_disjointness": ("splits",),
    "quotas": ("quota_counts",),
    "per_class_floors": ("per_class_counts",),
    "per_action_floors": ("per_action_counts",),
    "gold_independence_and_kappa": ("gold",),
    "weight_lineage_release_cleared": ("weight_lineage",),
}


def _delete_path(manifest: dict, dotted: str) -> None:
    head, _, tail = dotted.partition(".")
    if not tail:
        manifest.pop(head, None)
        return
    node = manifest.get(head)
    if isinstance(node, dict):
        _delete_path(node, tail)


def test_every_produced_gate_has_a_declared_evidence_block():
    produced = {gate.name for gate in gates.evaluate(_complete_manifest())}
    assert produced == set(GATE_EVIDENCE), sorted(produced ^ set(GATE_EVIDENCE))


@pytest.mark.parametrize("gate_name", sorted(GATE_EVIDENCE))
def test_no_gate_can_pass_with_its_evidence_removed(gate_name):
    manifest = _complete_manifest()
    for path in GATE_EVIDENCE[gate_name]:
        _delete_path(manifest, path)
    gate = next(g for g in gates.evaluate(manifest) if g.name == gate_name)
    assert gate.state != "pass", (
        f"{gate_name} still passes without {GATE_EVIDENCE[gate_name]}: {gate.detail}")


def test_cli_fails_closed_when_the_manifest_is_missing(tmp_path: Path):
    result = subprocess.run([sys.executable, str(TOOL), "--manifest", str(tmp_path / "nope.json")],
                            capture_output=True, text=True)
    assert result.returncode == 2
    assert "FAIL CLOSED" in result.stdout


def test_cli_returns_zero_only_for_a_complete_candidate(tmp_path: Path):
    manifest_path = tmp_path / "candidate.json"
    manifest_path.write_text(json.dumps(_complete_manifest()), encoding="utf-8")
    result = subprocess.run([sys.executable, str(TOOL), "--manifest", str(manifest_path)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout
    assert "RELEASE-CANDIDATE GATES PASS" in result.stdout


def test_cli_returns_nonzero_for_an_incomplete_manifest(tmp_path: Path):
    manifest_path = tmp_path / "candidate.json"
    manifest_path.write_text(json.dumps({"candidate_id": "x"}), encoding="utf-8")
    result = subprocess.run([sys.executable, str(TOOL), "--manifest", str(manifest_path)],
                            capture_output=True, text=True)
    assert result.returncode == 1
    assert "NOT A RELEASE CANDIDATE" in result.stdout


# ----------------------------------------------------------------- threshold planner
def _planner():
    spec = importlib.util.spec_from_file_location(
        "plan_threshold", REPO_ROOT / "tools/release/plan_abstention_threshold.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["plan_threshold"] = module
    spec.loader.exec_module(module)
    return module


def _calibration(clusters: int, per_cluster: int, *, good_fraction: float = 1.0,
                 forbidden_rate: float = 0.0, silence: float = 0.1) -> list[dict]:
    """Synthesise calibration records with a clean separation at score >= 80.

    A tenth of the frames is deliberately weak (low score), so a feasible threshold
    still serves about 90% of them: a set where the budget only holds by silencing
    most frames is the case the planner must refuse, not a realistic calibration.
    """
    cut = max(1, int(per_cluster * silence))
    records = []
    for cluster in range(clusters):
        for index in range(per_cluster):
            weak = index >= per_cluster - cut
            is_good = (not weak) and index < per_cluster * good_fraction
            records.append({
                "cluster_id": f"shoot-{cluster}",
                "split": "calibration",
                "score": 10 if weak else 90,
                "is_good_frame": is_good,
                "would_emit_correction": True,
                "forbidden_correction": bool(is_good and forbidden_rate > 0 and index % 5 == 0),
                "critical_forbidden": False,
                "bucket": "ordinary" if index % 3 else "difficult_light",
            })
    return records


def test_planner_proves_the_budget_from_a_large_clean_calibration_set():
    planner = _planner()
    result = planner.plan(_calibration(clusters=70, per_cluster=20, forbidden_rate=0.0))
    assert result["verdict"] == "pass", result["reason"]
    assert result["policy"]["fp_correct_upper_95"] <= planner.FP_CORRECT_BUDGET
    assert result["policy"]["derived_from"].startswith("calibration split only")


def test_planner_refuses_a_small_lucky_calibration_set():
    """100 good frames with zero forbidden corrections still cannot prove 2%."""
    planner = _planner()
    result = planner.plan(_calibration(clusters=10, per_cluster=10, forbidden_rate=0.0))
    assert result["verdict"] == "insufficient_evidence", result


def test_planner_refuses_when_only_one_cluster_exists():
    planner = _planner()
    result = planner.plan(_calibration(clusters=1, per_cluster=2000, forbidden_rate=0.0))
    assert result["verdict"] == "insufficient_evidence"
    assert "clusters" in result["reason"]


def test_planner_refuses_when_no_threshold_meets_the_budget():
    planner = _planner()
    # every advised good frame carries a forbidden correction
    records = []
    for cluster in range(70):
        for index in range(20):
            records.append({"cluster_id": f"s{cluster}", "score": 90, "is_good_frame": True,
                            "would_emit_correction": True, "forbidden_correction": True,
                            "bucket": "ordinary"})
    result = planner.plan(records)
    assert result["verdict"] == "insufficient_evidence"
    assert result["policy"] is None


def test_planner_is_deterministic():
    planner = _planner()
    records = _calibration(clusters=40, per_cluster=20)
    first = planner.plan(records)
    second = planner.plan(list(records))
    assert first["policy"] == second["policy"]


def test_planner_cli_fails_closed_without_calibration(tmp_path: Path):
    tool = REPO_ROOT / "tools/release/plan_abstention_threshold.py"
    result = subprocess.run([sys.executable, str(tool), "--calibration", str(tmp_path / "nope.jsonl")],
                            capture_output=True, text=True)
    assert result.returncode == 2
    assert "FAIL CLOSED" in result.stdout


def test_planner_rejects_records_without_cluster_identity(tmp_path: Path):
    planner = _planner()
    calibration = tmp_path / "cal.jsonl"
    calibration.write_text('{"score": 90}\n', encoding="utf-8")
    with pytest.raises(ValueError):
        planner.load_calibration(calibration)


def test_planner_respects_the_forbidden_budget_of_the_old_gate():
    """A threshold that serves too much forbidden advice must not be chosen."""
    planner = _planner()
    records = []
    for cluster in range(70):
        for index in range(20):
            # a tenth of the frames is weak, so the feasible threshold still serves
            # ~90% and the coverage floors are not what this test is about
            weak = index >= 18
            records.append({"cluster_id": f"s{cluster}", "split": "calibration",
                            "score": 10 if weak else 90,
                            "is_good_frame": True, "would_emit_correction": True,
                            "forbidden_correction": False, "bucket": "ordinary"})
    # low-score half is all forbidden advice: serving it would blow forbidden <= 2%
    for record in records:
        if record["score"] == 10:
            record["forbidden_correction"] = True
    result = planner.plan(records)
    assert result["verdict"] == "pass", result["reason"]
    assert result["policy"]["advise_threshold"] == 90, result["policy"]
    assert result["policy"]["forbidden_rate"] == 0.0


def test_planner_refuses_a_threshold_serving_a_critical_forbidden_case():
    planner = _planner()
    records = _calibration(clusters=70, per_cluster=20)
    for record in records:
        if record["score"] == 90:
            record["critical_forbidden"] = True
    result = planner.plan(records)
    assert result["verdict"] == "insufficient_evidence"
    assert "critical" in result["reason"]


def test_clopper_pearson_survives_realistic_n():
    """math.comb overflows at this size; the log-space tail must not."""
    value = gates.clopper_pearson_upper(700, 1400)
    # cross-checked independently: the normal approximation of the same quantile
    # (z = -1.6449 at p where P(X<=700)=0.05) gives 0.522316, agreeing to 1e-5
    assert value == pytest.approx(0.52232, abs=0.0005), value
    assert gates.clopper_pearson_upper(5, 1400) < 0.01
    assert gates.clopper_pearson_upper(1399, 1400) > 0.99


def test_the_budget_needs_at_least_149_clean_advised_good_frames():
    """The crisp boundary M04 must plan against: 148 clean frames cannot prove 2%."""
    assert gates.clopper_pearson_upper(0, 149) <= 0.02
    assert gates.clopper_pearson_upper(0, 148) > 0.02


def test_confusion_counts_must_add_up():
    """A self-reported boolean is not evidence; the counts have to reconcile."""
    manifest = _manifest(evaluation={"confusion": {
        "correct": 10, "keep": 5, "abstain": 2, "incomparable": 1,
        "forbidden_advised": 0, "evaluated_total": 99}})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "confusion_matrix_integrity")
    assert gate.state == "fail"
    assert "sum" in gate.detail


def test_dropping_incomparable_from_the_matrix_fails():
    manifest = _manifest(evaluation={"confusion": {
        "correct": 10, "keep": 5, "abstain": 2, "forbidden_advised": 0, "evaluated_total": 17}})
    gate = next(g for g in gates.evaluate(manifest) if g.name == "confusion_matrix_integrity")
    assert gate.state == "fail"
    assert "incomparable" in gate.detail


def test_absent_confusion_block_cannot_be_a_pass():
    gate = next(g for g in gates.evaluate(_manifest(evaluation={}))
                if g.name == "confusion_matrix_integrity")
    assert gate.state == "not_provided"


# --------------------------------------------------------------- weight provenance
def _lineage_gate(manifest):
    return next(g for g in gates.evaluate(manifest) if g.name == "weight_lineage_release_cleared")


def test_research_only_weights_are_not_cleared_by_being_listed():
    """Credits do not clear research-only weights for the App Store."""
    manifest = _manifest(weight_lineage=[{
        "artifact": "set_composition_net_v2.mlpackage", "sha256": "abc",
        "training_data_lineage": "research:ava+silver", "release_cleared": False,
        "basis": "credits list the dataset"}])
    gate = _lineage_gate(manifest)
    assert gate.state == "fail"
    assert "release_cleared" in gate.detail


def test_lineage_without_a_basis_for_clearance_fails():
    manifest = _manifest(weight_lineage=[{
        "artifact": "m.mlpackage", "sha256": "abc",
        "training_data_lineage": "admitted:x", "release_cleared": True}])
    gate = _lineage_gate(manifest)
    assert gate.state == "fail"
    assert "basis" in gate.detail


def test_training_evidence_must_be_traceable_to_cleared_weights():
    manifest = _manifest(
        trained_heads={"issue_logits": True},
        training_evidence={"issue_logits": {"artifact": "unknown.mlpackage", "receipt": "r"}},
        weight_lineage=[{"artifact": "other.mlpackage", "sha256": "abc",
                         "training_data_lineage": "admitted:x", "release_cleared": True,
                         "basis": "b"}])
    gate = _lineage_gate(manifest)
    assert gate.state == "fail"
    assert "absent from weight_lineage" in gate.detail


def test_absent_weight_lineage_cannot_pass():
    manifest = _manifest()
    del manifest["weight_lineage"]
    assert _lineage_gate(manifest).state == "not_provided"


def test_the_template_itself_fails_every_gate_until_it_is_filled_in():
    """A skeleton with placeholders must not read as a passing candidate."""
    report, failed = gates.render(gates.evaluate(json.loads(json.dumps(gates.TEMPLATE))))
    assert failed, report
    assert "NOT A RELEASE CANDIDATE" in report
