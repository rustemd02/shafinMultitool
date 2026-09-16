"""Episode metrics must refuse to compute an error rate over unverified episodes.

`false_improved` is where "the pixel changed" could quietly become "the advice
worked". `tools/release/build_episode_metrics.py` derives the confusion matrix and
both false-improved ratios from episode records, and the property that matters is
what it does with missing truth: an unverified improvement must block the
derivation rather than shrink a denominator.

The gate side is checked too: the derived block must be consumable, silence must
not pass it, and incomparable must stay in the matrix.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/build_episode_metrics.py"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


episodes_tool = _load(TOOL, "build_episode_metrics")
gates = _load(GATE_TOOL, "candidate_gates_for_episode_tests")


def _episode(episode_id: str, *, decision: str = "correct", verifier: str = "improved",
             truth: str = "correct", cluster: str = "shoot-1",
             family: str = "level_horizon") -> dict:
    return {
        "episode_id": episode_id, "cluster_id": cluster, "app_decision": decision,
        "app_verifier_outcome": verifier, "truth_outcome": truth,
        "expected_action_family": family, "advised_action_family": family,
    }


def _write(tmp_path: Path, records: list[dict]) -> Path:
    path = tmp_path / "episodes.jsonl"
    path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")
    return path


def _run(tmp_path: Path, records: list[dict]):
    out = tmp_path / "blocks.json"
    code = episodes_tool.main(["--episodes", str(_write(tmp_path, records)), "--out", str(out)])
    payload = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
    return code, payload


# ------------------------------------------------------------ the refusal rule
def test_an_unverified_improvement_blocks_the_derivation(tmp_path: Path, capsys):
    records = [_episode("e1"), _episode("e2", truth="incomparable")]
    code, _ = _run(tmp_path, records)
    assert code == 2
    error = capsys.readouterr().err
    assert "no established truth" in error
    assert "e2" in error


def test_an_unverified_episode_without_an_improvement_claim_is_allowed(tmp_path: Path):
    records = [_episode("e1"),
               _episode("e2", decision="incomparable", verifier="incomparable", truth="incomparable")]
    code, payload = _run(tmp_path, records)
    assert code == 0
    assert payload["false_improved"]["truth_unestablished"] == 1
    assert payload["false_improved"]["non_improved_episodes"] == 0


# ------------------------------------------------------------------- derivation
def test_both_false_improved_ratios_are_emitted(tmp_path: Path):
    records = [_episode(f"e{i}", truth="correct" if i % 2 == 0 else "no_op") for i in range(10)]
    code, payload = _run(tmp_path, records)
    assert code == 0
    fi = payload["false_improved"]
    assert fi["improved_issued"] == 10
    assert fi["wrong_confirmations"] == 5
    assert fi["non_improved_episodes"] == 5
    assert fi["wrong_improved"] == 5


def test_incomparable_stays_in_the_confusion_matrix(tmp_path: Path):
    records = [_episode("e1"),
               _episode("e2", decision="incomparable", verifier="incomparable", truth="incomparable"),
               _episode("e3", decision="abstain", verifier="unchanged", truth="no_op"),
               _episode("e4", decision="keep", verifier="unchanged", truth="correct")]
    _, payload = _run(tmp_path, records)
    confusion = payload["confusion"]
    assert confusion["incomparable"] == 1
    assert confusion["evaluated_total"] == 4
    assert confusion["correct"] + confusion["keep"] + confusion["abstain"] \
        + confusion["incomparable"] + confusion["forbidden_advised"] == 4


def test_an_incomparable_flag_with_a_comparable_verdict_is_refused(tmp_path: Path, capsys):
    records = [_episode("e1", decision="incomparable", verifier="improved", truth="incomparable")]
    code, _ = _run(tmp_path, records)
    assert code == 2
    assert "cannot be both" in capsys.readouterr().err


def test_a_duplicated_episode_is_refused(tmp_path: Path, capsys):
    records = [_episode("e1"), _episode("e1")]
    code, _ = _run(tmp_path, records)
    assert code == 2
    assert "repeats episode_id" in capsys.readouterr().err


def test_an_unknown_vocabulary_value_is_refused(tmp_path: Path, capsys):
    records = [_episode("e1", truth="sort_of_better")]
    code, _ = _run(tmp_path, records)
    assert code == 2
    assert "truth_outcome" in capsys.readouterr().err


def test_an_empty_file_fails_closed(tmp_path: Path, capsys):
    empty = tmp_path / "episodes.jsonl"
    empty.write_text("", encoding="utf-8")
    code = episodes_tool.main(["--episodes", str(empty)])
    assert code == 2
    assert "empty evaluation is not a result" in capsys.readouterr().err


def test_the_episode_block_does_not_fill_the_train_positives_quota(tmp_path: Path):
    """`train_positives` is a §5.2 quota, not an episode count.

    Writing an episode count under that key would satisfy a floor with a different
    quantity, so the block carries only episode floors and the gate must report the
    quota as missing instead.
    """
    records = [_episode(f"e{i}") for i in range(30)]
    _, payload = _run(tmp_path, records)
    for counts in payload["per_action_counts"].values():
        assert "train_positives" not in counts
    assert payload["episode_positives_by_action"]["level_horizon"] == 30

    gate = next(g for g in gates.evaluate({"per_action_counts": payload["per_action_counts"]})
                if g.name == "per_action_floors")
    assert gate.state == "fail"
    assert "train_positives" in gate.detail


def test_silence_is_not_a_pass(tmp_path: Path, capsys):
    """No improved episode issued: precision is undefined, so the run is not a pass."""
    records = [_episode("e1", decision="keep", verifier="unchanged", truth="correct")]
    code, payload = _run(tmp_path, records)
    assert code == 1
    assert payload["false_improved"]["improved_issued"] == 0
    assert "precision is undefined" in capsys.readouterr().err


# ------------------------------------------------------------- gate integration
def test_the_derived_blocks_are_consumable_by_the_gate(tmp_path: Path):
    """Both false-improved denominators must be defined for the gate to decide."""
    records = [_episode(f"e{i}", cluster=f"shoot-{i % 3}") for i in range(190)]
    records += [_episode(f"n{i}", cluster=f"shoot-{i % 3}", decision="abstain",
                         verifier="unchanged", truth="no_op") for i in range(10)]
    _, payload = _run(tmp_path, records)
    manifest = {"evaluation": {"confusion": payload["confusion"],
                               "false_improved": payload["false_improved"]}}
    confusion_gate = next(g for g in gates.evaluate(manifest)
                          if g.name == "confusion_matrix_integrity")
    false_improved_gate = next(g for g in gates.evaluate(manifest) if g.name == "false_improved")
    assert confusion_gate.state == "pass", confusion_gate.detail
    assert false_improved_gate.state == "pass", false_improved_gate.detail


def test_a_ten_percent_error_rate_fails_the_gate(tmp_path: Path):
    records = [_episode(f"e{i}", truth="correct" if i > 2 else "no_op") for i in range(30)]
    _, payload = _run(tmp_path, records)
    manifest = {"evaluation": {"confusion": payload["confusion"],
                               "false_improved": payload["false_improved"]}}
    gate = next(g for g in gates.evaluate(manifest) if g.name == "false_improved")
    assert gate.state == "fail"
    assert "> 0.02" in gate.detail
