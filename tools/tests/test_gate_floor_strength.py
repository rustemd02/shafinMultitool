"""Every declared quota and floor must actually decide a verdict.

`QUOTAS`, `PER_CLASS_FLOORS`, `PER_ACTION_FLOORS` and `EPISODE_FLOORS` are the §5.2
data commitments. A floor that is declared but not read would let a candidate pass a
commitment it does not meet — the same class as a gate that passes on no data — so
for every key this suite checks the boundary in both directions: exactly at the
floor the gate passes, one below the floor it fails.

The fixtures are built from the tool's own dictionaries on purpose: adding a
commitment there must immediately make it enforceable, and the test fails if the
gate stops reading a key that the manifest still declares.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"


def _load():
    spec = importlib.util.spec_from_file_location("candidate_gates_floor_strength", TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["candidate_gates_floor_strength"] = module
    spec.loader.exec_module(module)
    return module


gates = _load()


def _gate(manifest: dict, name: str):
    return next(g for g in gates.evaluate(manifest) if g.name == name)


# --------------------------------------------------------------------- quotas
def _quota_manifest(overrides: dict | None = None) -> dict:
    counts = dict(gates.QUOTAS)
    counts.update(overrides or {})
    return {"quota_counts": counts}


def test_all_quotas_at_their_floor_pass():
    assert _gate(_quota_manifest(), "quotas").state == "pass"


@pytest.mark.parametrize("key", sorted(gates.QUOTAS))
def test_each_quota_one_below_its_floor_fails(key):
    gate = _gate(_quota_manifest({key: gates.QUOTAS[key] - 1}), "quotas")
    assert gate.state == "fail", f"{key} below its floor did not fail"
    assert key in gate.detail


# ---------------------------------------------------------------- per class
def _per_class_manifest(overrides: dict | None = None, klass: str = "single_person") -> dict:
    counts = dict(gates.PER_CLASS_FLOORS)
    counts.update(overrides or {})
    return {"per_class_counts": {klass: counts}}


def test_all_per_class_floors_at_their_floor_pass():
    assert _gate(_per_class_manifest(), "per_class_floors").state == "pass"


@pytest.mark.parametrize("key", sorted(gates.PER_CLASS_FLOORS))
def test_each_per_class_floor_one_below_fails(key):
    gate = _gate(_per_class_manifest({key: gates.PER_CLASS_FLOORS[key] - 1}), "per_class_floors")
    assert gate.state == "fail", f"{key} below its floor did not fail"
    assert key in gate.detail


# --------------------------------------------------------------- per action
def _per_action_manifest(overrides: dict | None = None,
                         episode_overrides: dict | None = None,
                         action: str = "level_horizon") -> dict:
    counts = dict(gates.PER_ACTION_FLOORS)
    counts.update(overrides or {})
    episodes = dict(gates.EPISODE_FLOORS)
    episodes.update(episode_overrides or {})
    return {"per_action_counts": {action: {**counts, "episodes": episodes}}}


def test_all_per_action_and_episode_floors_at_their_floor_pass():
    assert _gate(_per_action_manifest(), "per_action_floors").state == "pass"


@pytest.mark.parametrize("key", sorted(gates.PER_ACTION_FLOORS))
def test_each_per_action_floor_one_below_fails(key):
    gate = _gate(_per_action_manifest({key: gates.PER_ACTION_FLOORS[key] - 1}), "per_action_floors")
    assert gate.state == "fail", f"{key} below its floor did not fail"
    assert key in gate.detail


@pytest.mark.parametrize("key", sorted(gates.EPISODE_FLOORS))
def test_each_episode_floor_one_below_fails(key):
    gate = _gate(_per_action_manifest(episode_overrides={key: gates.EPISODE_FLOORS[key] - 1}),
                 "per_action_floors")
    assert gate.state == "fail", f"episodes.{key} below its floor did not fail"
    assert f"episodes.{key}" in gate.detail


def test_the_episode_floors_are_only_read_under_the_episodes_key():
    """A bare `improved` next to the action counts must not satisfy the episode floor."""
    counts = dict(gates.PER_ACTION_FLOORS)
    counts["improved"] = 10_000
    gate = _gate({"per_action_counts": {"level_horizon": counts}}, "per_action_floors")
    assert gate.state == "fail"
    assert "episodes.improved" in gate.detail


# ------------------------------------------------------- trained-head masks
def _heads_manifest(**overrides) -> dict:
    manifest = {
        "contract_heads": ["issue_logits", "risk_probability"],
        "trained_heads": {"issue_logits": True},
        "training_evidence": {"issue_logits": {"artifact": "m.mlpackage", "receipt": "r", "sha256": "x"}},
    }
    manifest.update(overrides)
    return manifest


def _heads_gate(manifest: dict):
    return _gate(manifest, "trained_heads_backed_by_evidence")


def test_an_untrained_contract_head_without_a_mask_fails():
    """A few trained heads must never read as 'the rest are trained too'."""
    gate = _heads_gate(_heads_manifest())
    assert gate.state == "fail"
    assert "no untrained_head_mask was declared" in gate.detail
    assert "risk_probability" in gate.detail


def test_an_untrained_contract_head_covered_by_the_mask_passes():
    gate = _heads_gate(_heads_manifest(untrained_head_mask=["risk_probability"]))
    assert gate.state == "pass", gate.detail


def test_a_mask_that_does_not_cover_every_untrained_head_fails():
    gate = _heads_gate(_heads_manifest(untrained_head_mask=[]))
    assert gate.state == "fail"
    assert "outside the declared mask" in gate.detail


def test_a_mask_naming_a_trained_head_is_contradictory():
    gate = _heads_gate(_heads_manifest(untrained_head_mask=["issue_logits"]))
    assert gate.state == "fail"
    assert "claimed trained" in gate.detail


def test_a_mask_with_everything_trained_is_a_stale_declaration():
    gate = _heads_gate(_heads_manifest(trained_heads={"issue_logits": True, "risk_probability": True},
                                       training_evidence={"issue_logits": {"artifact": "m.mlpackage",
                                                                           "receipt": "r", "sha256": "x"},
                                                          "risk_probability": {"artifact": "m.mlpackage",
                                                                               "receipt": "r2", "sha256": "y"}},
                                       untrained_head_mask=["risk_probability"]))
    assert gate.state == "fail"
    assert "every contract head is trained" in gate.detail


def test_a_missing_contract_head_list_cannot_be_checked():
    manifest = _heads_manifest()
    manifest.pop("contract_heads")
    gate = _heads_gate(manifest)
    assert gate.state == "fail"
    assert "contract_heads is absent" in gate.detail


def test_a_claimed_head_without_evidence_still_fails():
    manifest = _heads_manifest(trained_heads={"issue_logits": True, "risk_probability": True})
    manifest["untrained_head_mask"] = []
    gate = _heads_gate(manifest)
    assert gate.state == "fail"
    assert "without training evidence" in gate.detail
