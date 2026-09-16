"""Dataset tools must not report success over an empty result.

Both tools checked here printed PASS while having examined nothing:

* `camera_coach_check.py --batch-records` read an empty collection, and
  `validate_batch([])` returned no errors — so the mode reported a passed
  admission check with zero records and zero manifests;
* `generate_camera_corruptions.py` allowed every entry to be skipped and then
  published an empty `pairs.jsonl` with `PASS ... pairs=0`.

Each case is covered in both directions: the empty input must fail closed, and
the real repository fixtures must still pass, so the guard cannot be satisfied by
refusing everything.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
BATCH_TOOL = REPO_ROOT / "tools/dataset/camera_coach_check.py"
CORRUPTION_TOOL = REPO_ROOT / "tools/dataset/generate_camera_corruptions.py"
FIXTURES = REPO_ROOT / "tools/dataset/tests/fixtures"

MANIFEST_FLAGS = ("--source-shoots", "--consent-manifest", "--rights-manifest", "--derivation-manifest")


def _run(tool: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(tool), *args], capture_output=True, text=True,
                          cwd=REPO_ROOT)


def test_empty_batch_collection_fails_closed(tmp_path: Path):
    """Zero records is not a passed batch admission check."""
    batch = tmp_path / "batch.jsonl"
    batch.write_text("", encoding="utf-8")
    manifests = []
    for index in range(4):
        path = tmp_path / f"m{index}.jsonl"
        path.write_text("", encoding="utf-8")
        manifests.append(str(path))

    args = ["--batch-records", str(batch)]
    for flag, manifest in zip(MANIFEST_FLAGS, manifests):
        args += [flag, manifest]
    result = _run(BATCH_TOOL, *args)

    assert result.returncode == 1, result.stdout + result.stderr
    assert "batch collection is empty" in result.stderr
    assert "PASS" not in result.stdout


def test_empty_batch_as_an_empty_json_array_fails_closed(tmp_path: Path):
    batch = tmp_path / "batch.json"
    batch.write_text("[]", encoding="utf-8")
    manifests = []
    for index in range(4):
        path = tmp_path / f"m{index}.jsonl"
        path.write_text("", encoding="utf-8")
        manifests.append(str(path))

    args = ["--batch-records", str(batch)]
    for flag, manifest in zip(MANIFEST_FLAGS, manifests):
        args += [flag, manifest]
    result = _run(BATCH_TOOL, *args)

    assert result.returncode == 1, result.stdout + result.stderr
    assert "batch collection is empty" in result.stderr


def test_the_repository_batch_fixtures_still_pass():
    """The counter-control: the guard must not refuse a real batch."""
    result = _run(
        BATCH_TOOL,
        "--batch-records", str(FIXTURES / "camera-coach-batch-positive.jsonl"),
        "--source-shoots", str(FIXTURES / "camera-coach-batch-source-shoots.jsonl"),
        "--consent-manifest", str(FIXTURES / "camera-coach-batch-consents.jsonl"),
        "--rights-manifest", str(FIXTURES / "camera-coach-batch-rights.jsonl"),
        "--derivation-manifest", str(FIXTURES / "camera-coach-batch-derivations.jsonl"),
        "--fixture-mode",
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PASS" in result.stdout


def _corruption_module():
    spec = importlib.util.spec_from_file_location("generate_camera_corruptions", CORRUPTION_TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["generate_camera_corruptions"] = module
    spec.loader.exec_module(module)
    return module


def test_zero_generated_pairs_is_refused():
    """`pairs=0` must not be publishable as a completed generation."""
    module = _corruption_module()
    with pytest.raises(module.CorruptionError) as error:
        module._require_generated_pairs(0, {"vision_unavailable": 3, "no_selected_subject": 1})
    assert "no corruption pairs were generated" in str(error.value)
    assert "vision_unavailable=3" in str(error.value)


def test_zero_pairs_with_no_recorded_skip_is_still_refused():
    module = _corruption_module()
    with pytest.raises(module.CorruptionError) as error:
        module._require_generated_pairs(0, {})
    assert "none recorded" in str(error.value)


def test_a_nonzero_pair_count_passes_the_guard():
    module = _corruption_module()
    module._require_generated_pairs(1, {})  # must not raise


# ------------------------------------------------- the fixture-only PASS trap
GOVERNANCE_TOOL = REPO_ROOT / "tools/dataset/governance_check.py"


def test_governance_check_without_a_manifest_marks_its_pass_as_fixture_only():
    """`PASS` on the built-in fixture must not read as a corpus admission check."""
    result = _run(GOVERNANCE_TOOL)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "fixture-only" in result.stdout
    assert "NOT the caller's data" in result.stdout
    assert "not a corpus admission check" in result.stdout


def test_governance_check_with_an_explicit_manifest_is_not_marked_fixture_only():
    fixture = REPO_ROOT / "datasets/schemas/fixtures/dataset-version-v1.valid.json"
    result = _run(GOVERNANCE_TOOL, "--manifest", str(fixture))
    assert result.returncode == 0, result.stdout + result.stderr
    assert "fixture-only" not in result.stdout
