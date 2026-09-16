"""Human rates must come from blind, independent reviews — never from silences.

§5.1 asks for human safe+executable, helpful, preference among non-ties, and harm
rates. `tools/release/build_human_report.py` computes them from reviewer votes, and
the properties checked here are the ones that decide whether the human evidence
means anything:

* `assisted` votes are excluded, as the vote schema says they do not enter gates;
* `blind: false` reviews are excluded, and a store with no blind review is refused —
  a rate over non-blind reviews is not a blind-review rate;
* a pretty after caused by something else is not a success (§4.2), so `other_cause`
  lowers helpful instead of being dropped;
* an empty store is refused rather than turned into a row of zeros.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/build_human_report.py"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


report_tool = _load(TOOL, "build_human_report")
gates = _load(GATE_TOOL, "candidate_gates_for_human_tests")


def _vote(review_id: str, *, blind: bool = True, assisted: bool = False,
          visually_improved: str = "yes", useful_instruction: str = "yes",
          executable: str = "yes", harmful: str = "none", intent_preserved: str = "yes",
          attribution: str = "action_caused") -> dict:
    vote = {
        "review_id": review_id, "reviewer_id": "rev-1", "voted_at": "2026-09-13T10:00:00Z",
        "blind": blind, "assisted": assisted, "visually_improved": visually_improved,
        "useful_instruction": useful_instruction, "executable": executable, "harmful": harmful,
        "intent_preserved": intent_preserved, "attribution": attribution, "notes": None,
    }
    if assisted:
        vote["assist_source"] = "camera_assist_hints_v1"
    return vote


def _write(tmp_path: Path, votes: list[dict]) -> Path:
    path = tmp_path / "reviews.jsonl"
    path.write_text("\n".join(json.dumps(vote) for vote in votes) + "\n", encoding="utf-8")
    return path


def _run(tmp_path: Path, votes: list[dict]):
    out = tmp_path / "human.json"
    code = report_tool.main(["--votes", str(_write(tmp_path, votes)), "--out", str(out)])
    payload = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
    return code, payload


# ------------------------------------------------------------- the success rule
def test_a_pretty_after_caused_by_something_else_is_not_a_success(tmp_path: Path):
    votes = [_vote("v1"), _vote("v2", attribution="other_cause"),
             _vote("v3", attribution="unknown"), _vote("v4", intent_preserved="no")]
    code, payload = _run(tmp_path, votes)
    assert code == 0
    assert payload["human"]["helpful"] == pytest.approx(0.25)
    # other_cause/unknown stay in the denominator as non-success rather than being dropped
    assert payload["counts"]["counted"] == 4
    assert payload["counts"]["attribution"] == {"action_caused": 2, "other_cause": 1, "unknown": 1}


def test_preference_excludes_ties_but_helpful_keeps_them_as_non_success(tmp_path: Path):
    votes = [_vote("v1"), _vote("v2", visually_improved="unsure", attribution="unknown"),
             _vote("v3", visually_improved="no", attribution="other_cause")]
    _, payload = _run(tmp_path, votes)
    human = payload["human"]
    assert payload["counts"]["non_ties"] == 2
    assert payload["counts"]["ties"] == 1
    assert human["preference_non_ties"] == pytest.approx(0.5)  # 1 preferred of 2 non-ties
    assert human["helpful"] == pytest.approx(1 / 3)  # the tie counts as non-success


def test_critical_harm_is_counted_and_material_harm_is_a_rate(tmp_path: Path):
    votes = [_vote("v1"), _vote("v2", harmful="material"), _vote("v3", harmful="critical"),
             _vote("v4", harmful="minor")]
    _, payload = _run(tmp_path, votes)
    assert payload["human"]["critical_harm"] == 1
    assert payload["human"]["materially_harmful"] == pytest.approx(0.25)
    gate = next(g for g in gates.evaluate({"evaluation": {"human": payload["human"]}})
                if g.name == "human_critical_harm")
    assert gate.state == "fail"


def test_safe_and_executable_counts_only_yes(tmp_path: Path):
    votes = [_vote("v1"), _vote("v2", executable="no"), _vote("v3", executable="unsure"),
             _vote("v4", executable="yes")]
    _, payload = _run(tmp_path, votes)
    assert payload["human"]["safe_and_executable"] == pytest.approx(0.5)


# ------------------------------------------------------- blindness and independence
def test_assisted_votes_are_excluded_from_the_rates(tmp_path: Path):
    votes = [_vote("v1"), _vote("v2", assisted=True, executable="no", harmful="critical")]
    _, payload = _run(tmp_path, votes)
    assert payload["counts"]["counted"] == 1
    assert payload["counts"]["assisted_excluded"] == 1
    assert payload["human"]["critical_harm"] == 0
    assert payload["human"]["safe_and_executable"] == 1.0


def test_non_blind_reviews_are_excluded_and_reported(tmp_path: Path):
    votes = [_vote("v1"), _vote("v2", blind=False, executable="no")]
    _, payload = _run(tmp_path, votes)
    assert payload["counts"]["counted"] == 1
    assert payload["counts"]["non_blind_excluded"] == 1
    assert payload["human"]["safe_and_executable"] == 1.0


def test_a_store_with_no_blind_review_is_refused(tmp_path: Path, capsys):
    votes = [_vote("v1", blind=False), _vote("v2", blind=False, assisted=True)]
    code, _ = _run(tmp_path, votes)
    assert code == 2
    assert "is a blind, unassisted review" in capsys.readouterr().err


def test_an_all_unsure_preference_denominator_is_not_a_rate(tmp_path: Path):
    votes = [_vote("v1", visually_improved="unsure", attribution="unknown"),
             _vote("v2", visually_improved="unsure", attribution="unknown")]
    _, payload = _run(tmp_path, votes)
    assert payload["human"]["preference_non_ties"] is None
    gate = next(g for g in gates.evaluate({"evaluation": {"human": payload["human"]}})
                if g.name == "human_preference_non_ties")
    assert gate.state == "not_measurable"


# ----------------------------------------------------------------- fail-closed
def test_an_empty_store_fails_closed(tmp_path: Path, capsys):
    empty = tmp_path / "reviews.jsonl"
    empty.write_text("", encoding="utf-8")
    assert report_tool.main(["--votes", str(empty)]) == 2
    assert "empty review set is not a result" in capsys.readouterr().err


def test_an_unknown_attribution_value_is_refused(tmp_path: Path, capsys):
    vote = _vote("v1")
    vote["attribution"] = "probably_the_action"
    code, _ = _run(tmp_path, [vote])
    assert code == 2
    assert "attribution" in capsys.readouterr().err


def test_an_assisted_vote_without_a_source_is_refused(tmp_path: Path, capsys):
    vote = _vote("v1", assisted=True)
    vote.pop("assist_source")
    code, _ = _run(tmp_path, [vote])
    assert code == 2
    assert "requires assist_source" in capsys.readouterr().err


def test_the_derived_rates_are_consumable_by_the_gate(tmp_path: Path):
    votes = [_vote(f"v{i}") for i in range(10)] + [_vote("bad", executable="no")]
    _, payload = _run(tmp_path, votes)
    manifest = {"evaluation": {"human": payload["human"]}}
    statuses = {gate.name: gate.state for gate in gates.evaluate(manifest)
                if gate.name.startswith("human_") or gate.name == "human_critical_harm"}
    # 10/11 safe and helpful is above 0.90 and 0.80; harmful 0 and critical 0 pass
    assert statuses["human_safe_executable"] == "pass", statuses
    assert statuses["human_helpful"] == "pass", statuses
    assert statuses["human_materially_harmful"] == "pass", statuses
    assert statuses["human_critical_harm"] == "pass", statuses