"""The governance_check CLI must not let a fixture PASS read as a corpus admission.

`tools/dataset/governance_check.py` runs against a built-in fixture when no
`--manifest` is given. That is convenient, and dangerous: a bare `PASS` next to a
file path is exactly how "the dataset passed admission" starts being claimed for a
run that only validated a repository fixture. The CLI therefore labels that case,
and the label is what these tests pin — the module's own `--self-test` covers the
validation logic but never exercises `main`.

Run: python3 -m pytest tools/tests/test_governance_check_cli.py -q
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/dataset/governance_check.py"
FIXTURE = REPO_ROOT / "datasets/schemas/fixtures/dataset-version-v1.valid.json"


def run(*args: str) -> tuple[int, str]:
    result = subprocess.run([sys.executable, str(TOOL), *args],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=120)
    return result.returncode, result.stdout + result.stderr


def test_the_fixture_default_is_labelled_and_not_quotable_as_admission():
    code, output = run()
    assert code == 0, output
    assert "fixture-only" in output, output
    assert "NOT the caller's data" in output, output
    assert "not a corpus admission check" in output, output
    assert "--manifest" in output, "the operator must be told how to check their own manifest"


def test_an_explicit_manifest_is_reported_without_the_fixture_label():
    """The label must mean something: it may not appear on a real manifest check."""
    code, output = run("--manifest", str(FIXTURE))
    assert code == 0, output
    assert "fixture-only" not in output, output
    assert "manifest_sha256=" in output, output


def test_an_invalid_manifest_fails_closed(tmp_path: Path):
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    del payload["rights_status"]
    broken = tmp_path / "broken.json"
    broken.write_text(json.dumps(payload), encoding="utf-8")
    code, output = run("--manifest", str(broken))
    assert code != 0, output
    assert "FAIL" in output, output


def test_the_self_test_flag_still_works():
    code, output = run("--self-test")
    assert code == 0, output
    assert "self-test" in output.lower(), output


def test_the_fixture_used_by_the_default_branch_exists():
    """If the fixture moved, the default branch would silently validate nothing."""
    assert FIXTURE.is_file()
