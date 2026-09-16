"""The candidate-manifest builder must reproduce the evaluator, not invent numbers.

`tools/release/build_candidate_manifest.py` recomputes §5 aggregates from per-record
rows and only emits the blocks those rows support. Two properties matter and are
checked here:

* the recomputation reproduces the evaluator's own aggregate document exactly on a
  real replay artifact — that is what makes the aggregation rules verified rather
  than asserted;
* a disagreement, a missing input, or an empty evaluation fails closed instead of
  producing a plausible manifest.

The real-artifact checks skip when the artifact is not on disk: those replay
directories are working evidence, not committed files.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/build_candidate_manifest.py"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"

# real replay artifacts that carry the per-record shape the builder consumes
REAL_ARTIFACTS = [
    REPO_ROOT / "docs/cameraanalysis/eval/camera-baseline-v0/drift-174-calibrated-edge-neutral/scored",
    REPO_ROOT / "docs/cameraanalysis/eval/camera-baseline-v0/drift-174/scored",
]


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


builder = _load(TOOL, "build_candidate_manifest")
gates = _load(GATE_TOOL, "candidate_gates_for_builder_tests")


def _real_pair():
    for directory in REAL_ARTIFACTS:
        case_results = directory / "case_results.jsonl"
        set_metrics = directory / "set_metrics.json"
        if case_results.is_file() and set_metrics.is_file():
            return case_results, set_metrics
    return None


def _row(**overrides) -> dict:
    row = {
        "record_id": "r1", "quality_label": "good", "passed": True,
        "metrics": {"expected_action_hit": 1.0, "forbidden_action_violation": 0.0,
                    "confidence_band_match": 1.0, "good_frame_preserved": 1.0,
                    "positive_confirmation": 1.0, "future_action_hit": None,
                    "technical_failure_gate": None},
        "failures": [], "candidate_actions": ["keep_current_setup"],
        "expected_actions": ["keep_current_setup"],
    }
    row.update(overrides)
    return row


def _write_rows(path: Path, rows: list[dict]) -> Path:
    path.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n",
                    encoding="utf-8")
    return path


# ---------------------------------------------------- reproduction on real data
def test_the_recomputation_reproduces_the_evaluators_own_aggregate():
    pair = _real_pair()
    if pair is None:
        pytest.skip("no real replay artifact on disk")
    case_results, set_metrics = pair
    rows = builder.load_rows(case_results)
    recomputed = builder.aggregate(rows)
    assert builder.cross_check(recomputed, set_metrics) == []


def test_the_builder_reports_a_disagreement_instead_of_trusting_itself(tmp_path: Path):
    pair = _real_pair()
    if pair is None:
        pytest.skip("no real replay artifact on disk")
    case_results, set_metrics = pair
    tampered = tmp_path / "set_metrics.json"
    document = json.loads(set_metrics.read_text(encoding="utf-8"))
    document["set_metrics"]["pass_rate"] = round(document["set_metrics"]["pass_rate"] + 0.05, 6)
    tampered.write_text(json.dumps(document), encoding="utf-8")

    rows = builder.load_rows(case_results)
    mismatches = builder.cross_check(builder.aggregate(rows), tampered)
    assert any("pass_rate" in mismatch for mismatch in mismatches)


# ------------------------------------------------------------- fail-closed paths
def test_a_missing_input_fails_closed(tmp_path: Path, capsys):
    code = builder.main(["--case-results", str(tmp_path / "nope.jsonl"), "--candidate-id", "c1"])
    assert code == 2
    assert "FAIL CLOSED" in capsys.readouterr().err


def test_an_empty_evaluation_fails_closed(tmp_path: Path, capsys):
    empty = tmp_path / "case_results.jsonl"
    empty.write_text("", encoding="utf-8")
    code = builder.main(["--case-results", str(empty), "--candidate-id", "c1"])
    assert code == 2
    assert "an empty evaluation is not a result" in capsys.readouterr().err


def test_no_good_frames_cannot_claim_the_budget(tmp_path: Path, capsys):
    rows = [_row(quality_label="bad", record_id="b1"),
            _row(quality_label="bad", record_id="b2")]
    path = _write_rows(tmp_path / "case_results.jsonl", rows)
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1"])
    assert code == 2
    assert "no good frames" in capsys.readouterr().err


def test_a_missing_policy_fails_closed(tmp_path: Path, capsys):
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--policy", str(tmp_path / "absent.json")])
    assert code == 2
    assert "evaluation policy is missing" in capsys.readouterr().err


def test_evaluating_something_other_than_the_locked_split_is_refused(tmp_path: Path, capsys):
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--evaluated-split", "train"])
    assert code == 2
    assert "locked split" in capsys.readouterr().err


def test_a_renamed_metric_key_fails_loudly_instead_of_averaging_to_null(tmp_path: Path, capsys):
    """Silent null is not acceptable: a moved key means the row schema changed."""
    row = _row()
    row["metrics"] = {key: value for key, value in row["metrics"].items()
                      if key != "forbidden_action_violation"}
    path = _write_rows(tmp_path / "case_results.jsonl", [row])
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1"])
    assert code == 2
    assert "absent from every row" in capsys.readouterr().err


def test_a_comparison_that_is_not_neural_is_refused_as_a_neural_block(tmp_path: Path, capsys):
    """Two deterministic arms must not be smuggled into evaluation.neural_gain."""
    comparison = tmp_path / "comparison.json"
    comparison.write_text(json.dumps({
        "arms": {"a": {"kind": "candidate_calibrated"}, "b": {"kind": "reference"}},
        "comparison": {"metric": "passed", "metric_kind": "rate", "clusters": [[9, 10, 3, 10]] * 3},
        "excluded_records": 0,
        "emitted_neural_gain_block": False,
    }), encoding="utf-8")
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--neural-gain", str(comparison)])
    assert code == 2
    assert "only a neural versus deterministic_baseline comparison" in capsys.readouterr().err


def test_a_declared_neural_comparison_fills_the_block(tmp_path: Path, capsys):
    comparison = tmp_path / "comparison.json"
    comparison.write_text(json.dumps({
        "arms": {"a": {"kind": "neural", "sha256": "a" * 64},
                 "b": {"kind": "deterministic_baseline", "sha256": "b" * 64}},
        "comparison": {"metric": "passed", "metric_kind": "rate"},
        "excluded_records": 0,
        "emitted_neural_gain_block": True,
        "neural_gain_block": {"clusters": [[9, 10, 3, 10]] * 8, "point_gain_pp": 60.0,
                              "safety_not_worse": True, "subset": "protected semantic"},
    }), encoding="utf-8")
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    out = tmp_path / "candidate.json"
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--neural-gain", str(comparison), "--out", str(out)])
    assert code == 0, capsys.readouterr().err
    manifest = json.loads(out.read_text(encoding="utf-8"))
    assert manifest["evaluation"]["neural_gain"]["point_gain_pp"] == 60.0
    assert manifest["provenance"]["neural_gain_source"]["metric_kind"] == "rate"
    gate = next(g for g in gates.evaluate(manifest) if g.name == "neural_gain_over_baseline")
    assert gate.state == "pass", gate.detail


def test_episode_blocks_fill_the_confusion_and_false_improved(tmp_path: Path):
    blocks = tmp_path / "blocks.json"
    blocks.write_text(json.dumps({
        "confusion": {"correct": 190, "keep": 0, "abstain": 10, "incomparable": 5,
                      "forbidden_advised": 0, "evaluated_total": 205},
        "false_improved": {"wrong_confirmations": 0, "improved_issued": 190,
                           "wrong_improved": 0, "non_improved_episodes": 10,
                           "incomparable_in_confusion": True, "truth_unestablished": 5},
        "per_action_counts": {"level_horizon": {"episodes": {"improved": 190,
                                                             "unchanged_or_worse": 10,
                                                             "incomparable": 5}}},
        "source": {"path": "episodes.jsonl", "episodes": 205},
        "definitions": {"incomparable_stays_in_matrix": True},
        "cluster_count": 3,
    }), encoding="utf-8")
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    out = tmp_path / "candidate.json"
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--episode-blocks", str(blocks), "--out", str(out)])
    assert code == 0
    manifest = json.loads(out.read_text(encoding="utf-8"))
    assert manifest["evaluation"]["false_improved"]["improved_issued"] == 190
    assert manifest["evaluation"]["confusion"]["incomparable"] == 5
    assert manifest["provenance"]["episode_blocks_source"]["cluster_count"] == 3
    assert not any("false_improved" in item for item in manifest["provenance"]["not_produced_here"])
    assert next(g for g in gates.evaluate(manifest)
                if g.name == "confusion_matrix_integrity").state == "pass"


def test_a_blocks_file_without_the_pair_is_refused(tmp_path: Path, capsys):
    blocks = tmp_path / "blocks.json"
    blocks.write_text(json.dumps({"confusion": {"evaluated_total": 0}}), encoding="utf-8")
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--episode-blocks", str(blocks)])
    assert code == 2
    assert "no confusion/false_improved pair" in capsys.readouterr().err


def test_human_and_gold_blocks_are_attached(tmp_path: Path):
    human = tmp_path / "human.json"
    human.write_text(json.dumps({"human": {"safe_and_executable": 0.95, "helpful": 0.85,
                                           "preference_non_ties": 0.65, "materially_harmful": 0.0,
                                           "critical_harm": 0}}), encoding="utf-8")
    gold = tmp_path / "gold.json"
    gold.write_text(json.dumps({"gold": {"annotators": 2, "annotators_are_distinct_humans": True,
                                         "ai_suggestions_in_independent_pass": False,
                                         "hidden_qc_rate": 0.05, "adjudicated_review_rate": 0.10,
                                         "kappa_keep_correct_abstain": 0.85,
                                         "kappa_action_family": 0.80, "forbidden_agreement": 0.95,
                                         "median_roi_iou": 0.85, "hidden_qc": 0.97}}),
                        encoding="utf-8")
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    out = tmp_path / "candidate.json"
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--human-report", str(human), "--gold-report", str(gold), "--out", str(out)])
    assert code == 0
    manifest = json.loads(out.read_text(encoding="utf-8"))
    assert manifest["evaluation"]["human"]["helpful"] == 0.85
    assert manifest["gold"]["annotators"] == 2
    human_gate = next(g for g in gates.evaluate(manifest) if g.name == "human_helpful")
    gold_gate = next(g for g in gates.evaluate(manifest) if g.name == "gold_independence_and_kappa")
    assert human_gate.state == "pass", human_gate.detail
    assert gold_gate.state == "pass", gold_gate.detail


def test_a_report_without_its_block_is_refused(tmp_path: Path, capsys):
    empty = tmp_path / "human.json"
    empty.write_text(json.dumps({"counts": {}}), encoding="utf-8")
    path = _write_rows(tmp_path / "case_results.jsonl", [_row()])
    code = builder.main(["--case-results", str(path), "--candidate-id", "c1",
                         "--human-report", str(empty)])
    assert code == 2
    assert "carries no human block" in capsys.readouterr().err


# --------------------------------------------------------- manifest is honest
def _assemble(tmp_path: Path, rows: list[dict], *, clusters: dict | None = None) -> dict:
    path = _write_rows(tmp_path / "case_results.jsonl", rows)
    out = tmp_path / "candidate.json"
    argv = ["--case-results", str(path), "--candidate-id", "candidate-under-test",
            "--out", str(out)]
    if clusters is not None:
        clusters_path = tmp_path / "clusters.json"
        clusters_path.write_text(json.dumps(clusters), encoding="utf-8")
        argv += ["--clusters", str(clusters_path)]
    code = builder.main(argv)
    assert code == 0
    return json.loads(out.read_text(encoding="utf-8"))


def test_the_manifest_declares_what_it_did_not_produce(tmp_path: Path):
    manifest = _assemble(tmp_path, [_row()])
    not_produced = manifest["provenance"]["not_produced_here"]
    assert any("false_improved" in item for item in not_produced)
    assert any("confusion" in item for item in not_produced)
    assert manifest["provenance"]["evaluation_policy"]["policy_version"]


def test_without_a_cluster_mapping_the_budget_cannot_be_claimed(tmp_path: Path):
    rows = [_row(record_id=f"r{i}") for i in range(20)]
    manifest = _assemble(tmp_path, rows)
    assert manifest["evaluation"]["fp_correct"]["cluster_count"] is None
    gate = next(g for g in gates.evaluate(manifest) if g.name == "fp_correct_on_good_frames")
    assert gate.state == "not_measurable"
    assert "cluster count" in gate.detail


def test_one_shoot_is_not_independence(tmp_path: Path):
    rows = [_row(record_id=f"r{i}") for i in range(20)]
    manifest = _assemble(tmp_path, rows, clusters={f"r{i}": "shoot-1" for i in range(20)})
    assert manifest["evaluation"]["fp_correct"]["cluster_count"] == 1
    gate = next(g for g in gates.evaluate(manifest) if g.name == "fp_correct_on_good_frames")
    assert gate.state == "not_measurable"


def test_an_all_keep_run_cannot_pass_the_good_frame_budget(tmp_path: Path):
    """The prohibition in machine form: silence everywhere is not a pass."""
    rows = [_row(record_id=f"r{i}") for i in range(30)]
    manifest = _assemble(tmp_path, rows, clusters={f"r{i}": f"shoot-{i % 6}" for i in range(30)})
    assert manifest["evaluation"]["fp_correct"]["keep_rate"] == 1.0
    gate = next(g for g in gates.evaluate(manifest) if g.name == "fp_correct_on_good_frames")
    assert gate.state == "fail"
    assert "all-silence" in gate.detail


def test_a_real_replay_manifest_fails_the_budget_it_cannot_meet(tmp_path: Path):
    """The historical replay has 13 overcorrections in 81 good frames; the gate must fail it."""
    pair = _real_pair()
    if pair is None:
        pytest.skip("no real replay artifact on disk")
    case_results, set_metrics = pair
    rows = builder.load_rows(case_results)
    out = tmp_path / "candidate.json"
    clusters = {row["record_id"]: row.get("source_bucket", "bucket") for row in rows}
    clusters_path = tmp_path / "clusters.json"
    clusters_path.write_text(json.dumps(clusters), encoding="utf-8")
    code = builder.main(["--case-results", str(case_results), "--set-metrics", str(set_metrics),
                         "--candidate-id", "historical-replay", "--clusters", str(clusters_path),
                         "--out", str(out)])
    assert code == 0
    manifest = json.loads(out.read_text(encoding="utf-8"))
    fp = manifest["evaluation"]["fp_correct"]
    assert fp["good_frames_evaluated"] == 81
    assert fp["good_frames_with_forbidden_correction"] == 13
    gate = next(g for g in gates.evaluate(manifest) if g.name == "fp_correct_on_good_frames")
    assert gate.state == "fail"
