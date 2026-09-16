"""The threshold planner must not be able to fit on the test or buy the budget with silence.

Two prohibitions meet in `tools/release/plan_abstention_threshold.py`:

* the threshold may only be chosen on calibration data, never on the locked test
  ("не использовать финальный holdout для выбора порогов"), so the calibration input
  has to declare its split;
* the FP_CORRECT budget must be met while keeping coverage ("с сохранением coverage"),
  so a threshold that proves the budget by advising almost nothing is the silence case
  the owner forbids and must come back as insufficient evidence, not as a pass.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/plan_abstention_threshold.py"


def _planner():
    spec = importlib.util.spec_from_file_location("plan_threshold_guards", TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["plan_threshold_guards"] = module
    spec.loader.exec_module(module)
    return module


planner = _planner()


def _records(*, clusters: int = 70, per_cluster: int = 20, weak_tail: int = 2,
             split: str | None = "calibration", bucket: str = "ordinary",
             weak_are_unsafe: bool = False) -> list[dict]:
    out = []
    for cluster in range(clusters):
        for index in range(per_cluster):
            weak = index >= per_cluster - weak_tail
            record = {"cluster_id": f"s{cluster}", "score": 10 if weak else 90,
                      "is_good_frame": True, "would_emit_correction": True,
                      "forbidden_correction": bool(weak and weak_are_unsafe),
                      "critical_forbidden": False,
                      "bucket": bucket}
            if split is not None:
                record["split"] = split
            out.append(record)
    return out


def _write(tmp_path: Path, records: list[dict]) -> Path:
    path = tmp_path / "calibration.jsonl"
    path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")
    return path


# --------------------------------------------------------- calibration split only
def test_an_undeclared_split_is_refused(tmp_path: Path):
    path = _write(tmp_path, _records(split=None))
    with pytest.raises(ValueError) as error:
        planner.load_calibration(path)
    assert "split is required" in str(error.value)


def test_a_locked_split_cannot_be_used_as_calibration(tmp_path: Path):
    """Deriving the threshold on the locked test is the fitting the runbook forbids."""
    path = _write(tmp_path, _records(split="locked"))
    with pytest.raises(ValueError) as error:
        planner.load_calibration(path)
    assert "never from the locked test" in str(error.value)


def test_a_declared_calibration_split_is_accepted(tmp_path: Path):
    records = planner.load_calibration(_write(tmp_path, _records()))
    assert len(records) == 1400


def test_the_cli_refuses_a_locked_split_before_planning(tmp_path: Path, capsys):
    path = _write(tmp_path, _records(split="test"))
    code = planner.main(["--calibration", str(path)])
    assert code == 2
    assert "never from the locked test" in capsys.readouterr().out


# ------------------------------------------------------------ coverage floors
def test_a_budget_bought_by_silence_is_not_a_pass():
    """The budget is provable only on 30% of the frames, and the rest are unsafe.

    Note on the arithmetic: silencing also shrinks the denominator, and 0/140 still
    leaves a 2.59% upper bound. The served set therefore has to stay large enough to
    prove the budget (>=149 clean frames) while covering less than the floor — that is
    the only shape in which "the budget holds" and "coverage fails" are both true.
    """
    records = _records(weak_tail=14, weak_are_unsafe=True)  # 30% served, 420 frames
    result = planner.plan(records)
    assert result["verdict"] == "insufficient_evidence"
    assert "silencing frames" in result["reason"]
    assert "coverage_shortfalls" in result
    assert result["policy"] is None


def test_the_floors_come_from_the_policy_and_can_be_relaxed_only_explicitly():
    records = _records(weak_tail=14, weak_are_unsafe=True)
    strict = planner.plan(records)
    assert strict["verdict"] == "insufficient_evidence"
    relaxed = planner.plan(records, coverage_floors={
        "accepted_coverage_overall": 0.05, "accepted_coverage_ordinary": 0.05,
        "accepted_coverage_difficult_light": 0.05})
    assert relaxed["verdict"] == "pass", relaxed["reason"]


def test_the_default_floors_are_the_frozen_policy_ones():
    floors = planner.load_coverage_floors(planner.DEFAULT_POLICY, "rate_gates")
    policy = json.loads(planner.DEFAULT_POLICY.read_text(encoding="utf-8"))
    for key, floor in floors.items():
        assert policy["rate_gates"][key]["threshold"] == floor


def test_an_absent_bucket_is_not_a_coverage_shortfall():
    """A calibration set with no difficult-light frames cannot be short on them."""
    records = _records(bucket="ordinary")
    result = planner.plan(records)
    assert result["verdict"] == "pass", result["reason"]
    assert result["policy"]["coverage_difficult_light"] is None


def test_a_clean_calibration_set_passes_and_reports_the_floors():
    result = planner.plan(_records())
    assert result["verdict"] == "pass", result["reason"]
    assert result["coverage_floors"]["accepted_coverage_overall"] == 0.65
    assert result["policy"]["coverage_overall"] >= 0.65
