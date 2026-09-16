"""Non-vacuity guards for the M0/M11 evidence checkers.

These checkers are not wired into `run_release_gates.sh`; they are run by hand and
their output is quoted as evidence. Six of them used to print OK after examining
nothing — an empty material inventory, an empty string table, a source scan that
matched no directories — which is the same "PASS because nothing was looked at"
failure that `check_release_logs.py` was hardened against.

Each test drives the real script from a throwaway working directory, because the
scripts resolve their inputs relative to the process cwd. Nothing here touches the
repository's own files.

Run: python3 -m pytest scripts/tests/test_evidence_checkers_non_vacuity.py -q
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = REPO_ROOT / "scripts/evidence"

MATERIAL_INVENTORY = Path("docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m0")
STRINGS = Path("shafinMultitool/Resources/Localizable.xcstrings")

MUST_SCAN_SOMETHING = (
    "check_reduce_motion.py",
    "check_motif_budget.py",
    "check_motion_evidence.py",
    "check_material_inventory.py",
    "check_copy_inventory.py",
    "check_localization.py",
    "check_screenshot_matrix.py",
)


def run_checker(script: str, cwd: Path) -> tuple[int, str]:
    result = subprocess.run([sys.executable, str(EVIDENCE / script)], cwd=cwd,
                            capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def _empty_tree(root: Path) -> None:
    """Inputs exist but hold nothing: this is the vacuous case, not the missing case."""
    (root / MATERIAL_INVENTORY).mkdir(parents=True, exist_ok=True)
    (root / MATERIAL_INVENTORY / "material-inventory-v2.jsonl").write_text("", encoding="utf-8")
    (root / STRINGS).parent.mkdir(parents=True, exist_ok=True)
    (root / STRINGS).write_text(json.dumps({"strings": {}}), encoding="utf-8")
    (root / "shafinMultitool/App.swift").write_text("import SwiftUI\n", encoding="utf-8")


@pytest.mark.parametrize("script", MUST_SCAN_SOMETHING)
def test_an_empty_input_is_not_a_pass(script: str):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _empty_tree(root)
        code, output = run_checker(script, root)
        assert code != 0, f"{script} reported success after scanning nothing: {output.strip()[-160:]}"
        assert "FAIL" in output, output


@pytest.mark.parametrize("script", MUST_SCAN_SOMETHING)
def test_a_missing_source_tree_is_not_a_pass(script: str):
    """Absent directories must refuse, not resolve to an empty scan."""
    with tempfile.TemporaryDirectory() as tmp:
        code, output = run_checker(script, Path(tmp))
        assert code != 0, f"{script} passed with no source tree at all: {output.strip()[-160:]}"


def test_the_guards_do_not_fire_on_the_real_repository():
    """The non-vacuity guards must not turn a genuine, non-empty scan into a failure."""
    for script in MUST_SCAN_SOMETHING:
        code, output = run_checker(script, REPO_ROOT)
        assert code == 0, f"{script} now fails on the real tree: {output.strip()[-200:]}"


def test_the_material_inventory_reports_a_real_row_count():
    """A guard that never sees rows would be indistinguishable from no guard."""
    code, output = run_checker("check_material_inventory.py", REPO_ROOT)
    assert code == 0
    assert "0 rows" not in output
    assert "rows, all fields present" in output
