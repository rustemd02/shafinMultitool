"""The gold block must be computed from the store, and independence must be real.

§5.2 asks for two independent humans, κ on the KEEP/CORRECT/ABSTAIN axis, action-family
κ, forbidden agreement, median ROI IoU, hidden QC and adjudicated re-review. Those
numbers were hand-written before; `tools/release/build_gold_report.py` computes them.

The properties checked here are the ones that keep the human evidence honest: an
assisted vote is not a second annotator, a value the store cannot support is absent
rather than defaulted, and a store that only carries the verdict axis does not get
its κ reported under the gate's KEEP/CORRECT/ABSTAIN key.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/build_gold_report.py"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


report_tool = _load(TOOL, "build_gold_report")
gates = _load(GATE_TOOL, "candidate_gates_for_gold_tests")


def _label(record_id: str, annotator: str, *, improvement_needed: bool, unsure: bool = False,
           actions: list | None = None, regions: list | None = None, assisted: bool = False) -> dict:
    return {
        "schema_id": "camera-coach-label", "record_id": record_id, "annotator_id": annotator,
        "beauty": "borderline", "improvement_needed": improvement_needed, "unsure": unsure,
        "issues": [], "actions": actions if actions is not None else
        (["level_horizon"] if improvement_needed else ["keep_current_setup"]),
        "regions": regions if regions is not None else
        [{"role": "subject", "rect": [0.1, 0.1, 0.3, 0.3]}],
        "notes": "", "assisted": assisted,
    }


def _store(tmp_path: Path, records: list[dict]) -> Path:
    path = tmp_path / "store.jsonl"
    path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")
    return path


def _run(tmp_path: Path, records: list[dict], *extra: str):
    out = tmp_path / "gold.json"
    code = report_tool.main(["--store", str(_store(tmp_path, records)), "--out", str(out), *extra])
    payload = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
    return code, payload


def _agreeing_pair(record_id: str, *, improvement_needed: bool | None = None) -> list[dict]:
    """Two annotators who agree.

    The category varies with the record on purpose: with a single category the
    expected agreement is 1 and Cohen kappa is undefined, which is not what these
    fixtures are testing.
    """
    if improvement_needed is None:
        improvement_needed = int(record_id.lstrip("r") or 0) % 2 == 0
    return [_label(record_id, "owner", improvement_needed=improvement_needed),
            _label(record_id, "second", improvement_needed=improvement_needed)]


def test_two_independent_annotators_produce_the_computable_values(tmp_path: Path):
    records = [record for i in range(10) for record in _agreeing_pair(f"r{i}")]
    code, payload = _run(tmp_path, records)
    assert code == 0
    gold = payload["gold"]
    assert gold["annotators"] == 2
    assert gold["kappa_keep_correct_abstain"] == pytest.approx(1.0)
    assert gold["kappa_action_family"] == pytest.approx(1.0)
    assert gold["median_roi_iou"] == pytest.approx(1.0)
    assert gold["hidden_qc"] is None  # nothing seeded yet
    assert any("hidden_qc" in reason for reason in payload["unavailable"])


def test_an_assisted_second_annotator_is_not_independence(tmp_path: Path, capsys):
    """One person plus AI hints is not two annotators (M3-022)."""
    records = [record for i in range(5)
               for record in (_label(f"r{i}", "owner", improvement_needed=False),
                              _label(f"r{i}", "ai_assisted", improvement_needed=False, assisted=True))]
    code, payload = _run(tmp_path, records)
    assert code == 1
    assert payload["gold"]["annotators"] == 1
    assert "fewer than two independent annotators" in capsys.readouterr().err


def test_a_record_with_one_vote_does_not_crash_the_derivation(tmp_path: Path):
    """A real store has partially labelled records; they are skipped, not fatal."""
    records = [record for i in range(4) for record in _agreeing_pair(f"r{i}")]
    records.append(_label("solo", "owner", improvement_needed=True))
    code, payload = _run(tmp_path, records)
    assert code == 0
    assert payload["gold"]["kappa_keep_correct_abstain"] == pytest.approx(1.0)
    assert payload["informational"]["paired_records"] == 4


def test_a_single_annotator_cannot_claim_independence(tmp_path: Path, capsys):
    records = [_label(f"r{i}", "owner", improvement_needed=bool(i % 2)) for i in range(6)]
    code, _ = _run(tmp_path, records)
    assert code == 1
    assert "one person's votes are not two annotators" in capsys.readouterr().err


def test_the_verdict_axis_is_not_reported_under_the_axis_key(tmp_path: Path):
    """`good` is not `keep`; translating it would be an unauthorised mapping."""
    votes = [{"record_type": "vote", "record_id": f"r{i}", "annotator_id": annotator,
              "verdict": "good" if i % 2 else "bad", "subject_state": "selected",
              "selected_subject_id": "e1", "region_ids": [], "notes": "", "assisted": False}
             for i in range(4) for annotator in ("a1", "a2")]
    _, payload = _run(tmp_path, votes)
    assert payload["gold"]["kappa_keep_correct_abstain"] is None
    assert any("verdict axis is not that axis" in reason for reason in payload["unavailable"])
    assert payload["informational"]["kappa_verdict_axis"] == 1.0


def test_hidden_qc_and_adjudication_rates_come_from_their_records(tmp_path: Path):
    records = [record for i in range(20) for record in _agreeing_pair(f"r{i}")]
    records += [{"record_type": "hidden_qc", "record_id": "r0", "annotator_id": "owner",
                 "observed_verdict": "good", "expected_verdict": "good", "agrees": True,
                 "notes": "seeded"}]
    records += [{"record_type": "adjudication", "record_id": f"r{i}", "adjudicator_id": "adj",
                 "outcome": "uphold", "referenced_vote_ids": [f"v{i}"], "notes": "ok"}
                for i in range(5)]
    _, payload = _run(tmp_path, records)
    gold = payload["gold"]
    assert gold["hidden_qc"] == 1.0
    assert gold["hidden_qc_rate"] == 1 / 40
    assert gold["adjudicated_review_rate"] == 5 / 40


def test_a_disagreeing_hidden_qc_lowers_the_agreement(tmp_path: Path):
    records = [record for i in range(5) for record in _agreeing_pair(f"r{i}")]
    records += [{"record_type": "hidden_qc", "record_id": "r0", "annotator_id": "owner",
                 "observed_verdict": "bad", "expected_verdict": "good", "agrees": False,
                 "notes": "seeded"}]
    _, payload = _run(tmp_path, records)
    assert payload["gold"]["hidden_qc"] == 0.0


def test_roi_iou_uses_matching_roles_only(tmp_path: Path):
    records = []
    for i in range(3):
        records.append(_label(f"r{i}", "owner", improvement_needed=True,
                              regions=[{"role": "subject", "rect": [0.0, 0.0, 0.5, 0.5]}]))
        records.append(_label(f"r{i}", "second", improvement_needed=True,
                              regions=[{"role": "background", "rect": [0.0, 0.0, 0.5, 0.5]}]))
    _, payload = _run(tmp_path, records)
    assert payload["gold"]["median_roi_iou"] is None
    assert any("regions of the same role" in reason for reason in payload["unavailable"])


def test_forbidden_agreement_needs_an_explicit_forbidden_set(tmp_path: Path):
    records = [record for i in range(4) for record in _agreeing_pair(f"r{i}")]
    _, without = _run(tmp_path, records)
    assert without["gold"]["forbidden_agreement"] is None
    assert any("no --forbidden-actions set" in reason for reason in without["unavailable"])

    forbidden = tmp_path / "forbidden.json"
    forbidden.write_text(json.dumps(["level_horizon"]), encoding="utf-8")
    code, with_set = _run(tmp_path, records, "--forbidden-actions", str(forbidden))
    assert code == 0
    assert with_set["gold"]["forbidden_agreement"] == 1.0


def test_an_empty_store_fails_closed(tmp_path: Path, capsys):
    empty = tmp_path / "store.jsonl"
    empty.write_text("", encoding="utf-8")
    assert report_tool.main(["--store", str(empty)]) == 2
    assert "FAIL CLOSED" in capsys.readouterr().err


def _gold_gate(gold: dict):
    manifest = {"gold": {**gold, "annotators_are_distinct_humans": True,
                         "ai_suggestions_in_independent_pass": False}}
    return next(g for g in gates.evaluate(manifest) if g.name == "gold_independence_and_kappa")


def test_everything_the_producer_cannot_compute_makes_the_gate_say_so(tmp_path: Path):
    records = [record for i in range(10) for record in _agreeing_pair(f"r{i}")]
    _, payload = _run(tmp_path, records)
    gate = _gold_gate(payload["gold"])
    assert gate.state == "fail"
    # the failures name the values the store could not support, not a silent zero
    assert "hidden_qc" in gate.detail or "hidden_qc_rate" in gate.detail


def test_a_complete_store_clears_the_gold_gate(tmp_path: Path):
    records = [record for i in range(20) for record in _agreeing_pair(f"r{i}")]
    records += [{"record_type": "hidden_qc", "record_id": f"r{i}", "annotator_id": "owner",
                 "observed_verdict": "good", "expected_verdict": "good", "agrees": True,
                 "notes": "seeded"} for i in range(2)]
    records += [{"record_type": "adjudication", "record_id": f"r{i}", "adjudicator_id": "adj",
                 "outcome": "uphold", "referenced_vote_ids": [f"v{i}"], "notes": "ok"}
                for i in range(4)]
    forbidden = tmp_path / "forbidden.json"
    forbidden.write_text(json.dumps(["level_horizon"]), encoding="utf-8")
    code, payload = _run(tmp_path, records, "--forbidden-actions", str(forbidden))
    assert code == 0
    gate = _gold_gate(payload["gold"])
    assert gate.state == "pass", gate.detail