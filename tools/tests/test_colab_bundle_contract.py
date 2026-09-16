"""The Colab code bundle must stay a self-contained execution closure.

The owner uploads this archive and presses "Run all". If a needed file silently
drops out of the bundle, they discover it inside Colab after the upload — the
worst place to find it. These tests build the real bundle and check the contract:
a fixed member set, the notebook's own literal references, determinism, and the
refusal of a symlinked output path (`mktemp -d` on macOS produces one).

Run: python3 -m pytest tools/tests/test_colab_bundle_contract.py -q
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGER = REPO_ROOT / "tools/dataset/package_camera_colab.py"
PROFILE = "records"
NOTEBOOK = "ml/camera_coach/colab/SET_OS_Camera_Coach_Records.ipynb"

# The files the notebook needs in order to run: its own copy, the config it reads
# by literal path, the preflight it invokes, the v2 contract, and the audit files
# that let the run be verified afterwards.
REQUIRED_MEMBERS = (
    NOTEBOOK,
    "ml/camera_coach/configs/production_records_colab.json",
    "ml/camera_coach/preflight_records_run.py",
    "ml/camera_coach/contracts/set_composition_net_v2.json",
    "ml/camera_coach/requirements.lock",
    "bundle-manifest.json",
    "SHA256SUMS.json",
)


def build(output: Path) -> str:
    result = subprocess.run([sys.executable, str(PACKAGER), "build", "--profile", PROFILE,
                             "--output", str(output)],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
    assert result.returncode == 0, result.stdout + result.stderr
    match = re.search(r"sha256=([0-9a-f]{64})", result.stdout)
    assert match, f"the packager printed no sha256: {result.stdout}"
    return match.group(1)


def test_the_bundle_carries_every_file_the_notebook_needs(tmp_path: Path):
    archive = tmp_path / "records.zip"
    build(archive)
    with zipfile.ZipFile(archive) as handle:
        members = set(handle.namelist())
    missing = [name for name in REQUIRED_MEMBERS if name not in members]
    assert missing == [], f"bundle is missing required members: {missing}"


def test_every_literal_path_the_notebook_references_is_inside_the_bundle(tmp_path: Path):
    """A literal reference is an input the notebook cannot invent at runtime."""
    archive = tmp_path / "records.zip"
    build(archive)
    with zipfile.ZipFile(archive) as handle:
        members = set(handle.namelist())
        notebook = json.loads(handle.read(NOTEBOOK).decode("utf-8"))
    source = "\n".join("".join(cell.get("source", [])) for cell in notebook["cells"])
    referenced = sorted(set(re.findall(r"\b(ml/camera_coach/[A-Za-z0-9_./-]+)", source)))
    assert referenced, "the notebook references no paths at all: the check would be vacuous"
    missing = [path for path in referenced if path not in members]
    assert missing == [], f"the notebook reads paths absent from the bundle: {missing}"


def test_the_bundle_is_byte_deterministic(tmp_path: Path):
    """A bundle that changes per build cannot be pinned by EXPECTED_*_SHA256."""
    first = build(tmp_path / "a.zip")
    second = build(tmp_path / "b.zip")
    assert first == second, f"two builds produced different digests: {first} != {second}"
    left = hashlib.sha256((tmp_path / "a.zip").read_bytes()).hexdigest()
    right = hashlib.sha256((tmp_path / "b.zip").read_bytes()).hexdigest()
    assert left == right


def test_a_symlinked_output_path_is_refused(tmp_path: Path):
    """`mktemp -d` yields /var/... or /tmp/..., both symlinked on macOS."""
    result = subprocess.run([sys.executable, str(PACKAGER), "build", "--profile", PROFILE,
                             "--output", "/tmp/setos-bundle-should-refuse.zip"],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
    assert result.returncode != 0
    assert "symlink" in (result.stdout + result.stderr)


@pytest.mark.parametrize("profile", ["records", "stage2", "stage1"])
def test_every_declared_profile_builds(tmp_path: Path, profile: str):
    result = subprocess.run([sys.executable, str(PACKAGER), "build", "--profile", profile,
                             "--output", str(tmp_path / f"{profile}.zip")],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
    assert result.returncode == 0, result.stdout + result.stderr
