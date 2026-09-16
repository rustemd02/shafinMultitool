"""Arm pairing must be honest before any bootstrap runs on top of it.

`tools/release/compare_arms.py` sits between two evaluation runs and the §5.1
neural-gain gate. The ways that step goes wrong are all about the pairing and the
label, not the arithmetic:

* two arms that do not cover the same records are not a paired comparison;
* two deterministic runs must not be relabelled as a neural result;
* a shrinking denominator must be visible, not silent;
* the safety direction must be declared, because assuming it inverts quality.

The real-arm checks skip when the replay directories are absent: they are working
evidence, not committed files.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/compare_arms.py"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"

REAL_ARMS = {
    "a": REPO_ROOT / "docs/cameraanalysis/eval/camera-baseline-v0/drift-174-calibrated-edge-neutral/scored/case_results.jsonl",
    "b": REPO_ROOT / "docs/cameraanalysis/eval/camera-baseline-v0/drift-174/scored/case_results.jsonl",
}


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


arms = _load(TOOL, "compare_arms")
gates = _load(GATE_TOOL, "candidate_gates_for_arm_tests")


def _row(record_id: str, passed: bool, **metrics) -> dict:
    base = {"expected_action_hit": 1.0 if passed else 0.0, "forbidden_action_violation": 0.0}
    base.update(metrics)
    return {"record_id": record_id, "passed": passed, "metrics": base}


def _write(path: Path, rows: list[dict]) -> Path:
    path.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n",
                    encoding="utf-8")
    return path


def _clusters(path: Path, mapping: dict) -> Path:
    path.write_text(json.dumps(mapping), encoding="utf-8")
    return path


def _synthetic(tmp_path: Path, *, clusters: int = 8, per_cluster: int = 10,
               arm_a_pass: int = 9, arm_b_pass: int = 3):
    """Two arms over `clusters` shoots with a clear, reproducible difference."""
    rows_a, rows_b, mapping = [], [], {}
    for cluster in range(clusters):
        for index in range(per_cluster):
            record_id = f"c{cluster:02d}-{index:02d}"
            rows_a.append(_row(record_id, index < arm_a_pass))
            rows_b.append(_row(record_id, index < arm_b_pass))
            mapping[record_id] = f"shoot-{cluster:02d}"
    return (_write(tmp_path / "a.jsonl", rows_a), _write(tmp_path / "b.jsonl", rows_b),
            _clusters(tmp_path / "clusters.json", mapping))


def _run(tmp_path: Path, a: Path, b: Path, clusters: Path, *extra: str):
    out = tmp_path / "comparison.json"
    code = arms.main(["--arm-a", str(a), "--arm-b", str(b), "--clusters", str(clusters),
                      "--out", str(out), *extra])
    payload = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
    return code, payload


# ------------------------------------------------------------ the label guard
def test_two_deterministic_arms_do_not_produce_a_neural_gain_block(tmp_path: Path):
    a, b, clusters = _synthetic(tmp_path)
    code, payload = _run(tmp_path, a, b, clusters, "--arm-a-kind", "candidate_calibrated",
                         "--arm-b-kind", "deterministic_baseline")
    assert code == 0
    assert payload["emitted_neural_gain_block"] is False
    assert "neural_gain_block" not in payload
    assert "must NOT" in payload["note"]


def test_declared_neural_versus_baseline_does_produce_the_block(tmp_path: Path):
    a, b, clusters = _synthetic(tmp_path)
    code, payload = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                         "--arm-b-kind", "deterministic_baseline", "--subset", "protected semantic")
    assert code == 0
    assert payload["emitted_neural_gain_block"] is True
    block = payload["neural_gain_block"]
    assert block["subset"] == "protected semantic"
    assert len(block["clusters"]) == 8
    assert all(len(cluster) == 4 for cluster in block["clusters"])
    assert block["clusters"][0] == [9, 10, 3, 10]
    assert payload["comparison"]["metric_kind"] == "rate"
    assert block["point_gain_pp"] == pytest.approx(60.0)


def test_the_emitted_block_is_accepted_by_the_gate_it_feeds(tmp_path: Path):
    a, b, clusters = _synthetic(tmp_path)
    _, payload = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                      "--arm-b-kind", "deterministic_baseline")
    manifest = {"evaluation": {"neural_gain": payload["neural_gain_block"]}}
    gate = next(g for g in gates.evaluate(manifest) if g.name == "neural_gain_over_baseline")
    assert gate.state == "pass", gate.detail


def test_a_held_back_safety_metric_blocks_the_gate(tmp_path: Path):
    a_rows = [_row(f"c{c}-{i}", True, forbidden_action_violation=1.0 if c < 4 else 0.0)
              for c in range(8) for i in range(10)]
    b_rows = [_row(f"c{c}-{i}", i < 3, forbidden_action_violation=0.0)
              for c in range(8) for i in range(10)]
    mapping = {f"c{c}-{i}": f"shoot-{c}" for c in range(8) for i in range(10)}
    a = _write(tmp_path / "a.jsonl", a_rows)
    b = _write(tmp_path / "b.jsonl", b_rows)
    clusters = _clusters(tmp_path / "clusters.json", mapping)
    _, payload = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                      "--arm-b-kind", "deterministic_baseline",
                      "--safety-metric", "forbidden_action_violation")
    assert payload["neural_gain_block"]["safety_not_worse"] is False
    manifest = {"evaluation": {"neural_gain": payload["neural_gain_block"]}}
    gate = next(g for g in gates.evaluate(manifest) if g.name == "neural_gain_over_baseline")
    assert gate.state == "fail"
    assert "safety degraded" in gate.detail


def test_the_safety_direction_is_declared_not_assumed(tmp_path: Path):
    # arm A has a *worse* forbidden rate, so the two directions must disagree
    rows_a, rows_b, mapping = [], [], {}
    for cluster in range(8):
        for index in range(10):
            record_id = f"c{cluster:02d}-{index:02d}"
            rows_a.append(_row(record_id, True, forbidden_action_violation=0.2))
            rows_b.append(_row(record_id, True, forbidden_action_violation=0.0))
            mapping[record_id] = f"shoot-{cluster:02d}"
    a = _write(tmp_path / "sa.jsonl", rows_a)
    b = _write(tmp_path / "sb.jsonl", rows_b)
    clusters = _clusters(tmp_path / "sclusters.json", mapping)
    _, lower = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                    "--arm-b-kind", "deterministic_baseline",
                    "--safety-metric", "forbidden_action_violation")
    _, higher = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                     "--arm-b-kind", "deterministic_baseline",
                     "--safety-metric", "forbidden_action_violation",
                     "--safety-direction", "higher_is_better")
    assert lower["neural_gain_block"]["safety_not_worse"] is False
    assert higher["neural_gain_block"]["safety_not_worse"] is True
    assert lower["safety_direction"] == "lower_is_better"
    assert higher["safety_direction"] == "higher_is_better"
    assert higher["neural_gain_block"]["safety_not_worse"] is not lower["neural_gain_block"]["safety_not_worse"]


# ---------------------------------------------------------------- fail-closed
def test_arms_that_do_not_cover_the_same_records_are_refused(tmp_path: Path, capsys):
    a_rows = [_row("r1", True), _row("r2", True)]
    b_rows = [_row("r1", False), _row("r3", False)]
    a = _write(tmp_path / "a.jsonl", a_rows)
    b = _write(tmp_path / "b.jsonl", b_rows)
    clusters = _clusters(tmp_path / "clusters.json", {"r1": "s1", "r2": "s2", "r3": "s2"})
    code, _ = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                   "--arm-b-kind", "deterministic_baseline")
    assert code == 2
    assert "do not cover the same records" in capsys.readouterr().err


def test_a_duplicated_record_is_refused(tmp_path: Path, capsys):
    a = _write(tmp_path / "a.jsonl", [_row("r1", True), _row("r1", False)])
    b = _write(tmp_path / "b.jsonl", [_row("r1", True)])
    clusters = _clusters(tmp_path / "clusters.json", {"r1": "s1", "r2": "s2"})
    code, _ = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                   "--arm-b-kind", "deterministic_baseline")
    assert code == 2
    assert "repeats record_id" in capsys.readouterr().err


def test_a_single_cluster_is_not_independence(tmp_path: Path, capsys):
    a, b, _ = _synthetic(tmp_path, clusters=1)
    one = _clusters(tmp_path / "one.json", {f"c00-{i:02d}": "shoot-00" for i in range(10)})
    code, _ = _run(tmp_path, a, b, one, "--arm-a-kind", "neural",
                   "--arm-b-kind", "deterministic_baseline")
    assert code == 1
    assert "not independence" in capsys.readouterr().err


def test_a_missing_arm_fails_closed(tmp_path: Path, capsys):
    b = _write(tmp_path / "b.jsonl", [_row("r1", True)])
    clusters = _clusters(tmp_path / "clusters.json", {"r1": "s1"})
    code, _ = _run(tmp_path, tmp_path / "absent.jsonl", b, clusters,
                   "--arm-a-kind", "neural", "--arm-b-kind", "deterministic_baseline")
    assert code == 2
    assert "FAIL CLOSED" in capsys.readouterr().err


def test_records_missing_the_metric_are_excluded_and_reported(tmp_path: Path):
    a_rows = [_row("r1", True), _row("r2", True), _row("r3", True)]
    for row in a_rows:
        row["metrics"]["good_frame_preserved"] = 1.0
    a_rows[1]["metrics"]["good_frame_preserved"] = None  # dropped from the pairing
    b_rows = [_row("r1", True), _row("r2", True), _row("r3", True)]
    for row in b_rows:
        row["metrics"]["good_frame_preserved"] = 1.0
    a = _write(tmp_path / "a.jsonl", a_rows)
    b = _write(tmp_path / "b.jsonl", b_rows)
    clusters = _clusters(tmp_path / "clusters.json", {"r1": "s1", "r2": "s2", "r3": "s2"})
    code, payload = _run(tmp_path, a, b, clusters, "--arm-a-kind", "neural",
                         "--arm-b-kind", "deterministic_baseline",
                         "--metric", "good_frame_preserved")
    assert code == 0
    assert payload["comparison"]["paired_records"] == 2
    assert payload["excluded_records"] == 1
    assert payload["comparison"]["cluster_count"] == 2


# ------------------------------------------------------------- real arm pair
def test_the_real_arm_pair_pairs_perfectly_and_is_not_labelled_neural(tmp_path: Path):
    if not all(path.is_file() for path in REAL_ARMS.values()):
        pytest.skip("the real replay arms are not on disk")
    rows = [json.loads(line) for line in REAL_ARMS["a"].read_text(encoding="utf-8").splitlines() if line.strip()]
    clusters = _clusters(tmp_path / "clusters.json",
                         {row["record_id"]: row["source_bucket"] for row in rows})
    code, payload = _run(tmp_path, REAL_ARMS["a"], REAL_ARMS["b"], clusters,
                         "--arm-a-kind", "candidate_calibrated", "--arm-b-kind", "reference",
                         "--safety-metric", "forbidden_action_violation")
    assert code == 0
    assert payload["comparison"]["paired_records"] == 174
    assert payload["excluded_records"] == 0
    assert payload["emitted_neural_gain_block"] is False
    # the calibrated arm gained pass rate but its forbidden rate is worse: the
    # recorded trade-off in EV-CA-EVAL-011, reproduced independently here
    assert payload["comparison"]["point_gain_pp"] > 0
    assert payload["comparison"]["safety_not_worse"] is False