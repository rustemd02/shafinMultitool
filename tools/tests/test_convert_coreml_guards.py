"""The research-only guards of `ml/camera_coach/convert_coreml.py`.

This converter is the step that turns a trained Stage-2 artifact into something an
app could ship. It must therefore be impossible to run it on anything that is not
the completed research-only three-head contract, and impossible to get an output
that looks release-admissible: credits for a research model do not permit a
research-only weight in an App Store build.

The receipt is validated *before* torch loads anything, so these tests exercise the
real guard functions directly and stay fast.

Run: python3 -m pytest tools/tests/test_convert_coreml_guards.py -q
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "ml/camera_coach/convert_coreml.py"
MODULE_NAME = "ml.camera_coach.convert_coreml"


def _load():
    sys.path.insert(0, str(REPO_ROOT / "ml/camera_coach"))
    spec = importlib.util.spec_from_file_location("convert_coreml", MODULE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["convert_coreml"] = module
    spec.loader.exec_module(module)
    return module


convert = _load()
TRAINABLE = list(convert.TRAINABLE_HEADS)


def _receipt(**overrides) -> dict:
    receipt = {
        "status": "complete",
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "trainable_heads": list(TRAINABLE),
    }
    receipt.update(overrides)
    return receipt


def _write(tmp_path: Path, name: str, payload: dict) -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def test_the_trainable_head_contract_is_the_three_heads():
    """If this list grew, a receipt naming extra heads would pass the guard below."""
    assert TRAINABLE == ["issue_logits", "action_utility_logits", "continuous_target_deltas"]


@pytest.mark.parametrize("field,value,why", [
    ("research_only", False, "a non-research artifact must not be converted here"),
    ("research_only", None, "an absent flag is not a research declaration"),
    ("release_admissible", True, "a release-admissible receipt must not route through the research path"),
    ("human_gold", True, "human-gold is not this lane"),
    ("status", "partial", "an incomplete run is not convertible"),
    ("status", None, "a missing status is not a completed run"),
    ("trainable_heads", ["issue_logits", "action_utility_logits", "continuous_target_deltas", "extra"],
     "extra heads would claim training that did not happen"),
    ("trainable_heads", ["issue_logits", "action_utility_logits"],
     "fewer heads is not the frozen contract either"),
])
def test_a_receipt_that_is_not_the_research_contract_is_refused(tmp_path: Path, field, value, why):
    artifact = tmp_path / "candidate.pt"
    artifact.write_bytes(b"not a real artifact")
    receipt = _write(tmp_path, "receipt.json", _receipt(**{field: value}))
    with pytest.raises(ValueError) as error:
        convert.load_model(artifact, receipt)
    assert "research-only" in str(error.value), f"{field} refusal was not the contract guard: {error.value}"


def test_a_conforming_receipt_passes_the_contract_guard(tmp_path: Path):
    """Positive control: the guard must fire on the contract, not on everything.

    With conforming flags the next guard is the artifact/sha mismatch, which proves
    the run got past the research-contract check rather than being rejected blindly.
    """
    artifact = tmp_path / "candidate.pt"
    artifact.write_bytes(b"not a real artifact")
    receipt = _write(tmp_path, "receipt.json", _receipt())
    with pytest.raises(ValueError) as error:
        convert.load_model(artifact, receipt)
    message = str(error.value)
    assert "research-only" not in message, message
    assert "artifact" in message, message


def run_cli(*args: str) -> tuple[int, str]:
    result = subprocess.run([sys.executable, "-m", MODULE_NAME, *args],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
    return result.returncode, result.stdout + result.stderr


def test_the_output_must_be_an_mlpackage(tmp_path: Path):
    artifact = tmp_path / "a.pt"
    artifact.write_bytes(b"x")
    receipt = _write(tmp_path, "r.json", _receipt())
    code, output = run_cli("--artifact", str(artifact), "--receipt", str(receipt),
                           "--output", str(tmp_path / "out.zip"))
    assert code != 0
    assert "mlpackage" in output


def test_an_existing_output_is_never_overwritten(tmp_path: Path):
    artifact = tmp_path / "a.pt"
    artifact.write_bytes(b"x")
    receipt = _write(tmp_path, "r.json", _receipt())
    existing = tmp_path / "already.mlpackage"
    existing.mkdir()
    code, output = run_cli("--artifact", str(artifact), "--receipt", str(receipt),
                           "--output", str(existing))
    assert code != 0
    assert "already exists" in output
