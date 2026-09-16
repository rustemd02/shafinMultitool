"""The registry conformance checker must not stop checking when a key is removed.

`tools/cameraanalysis/check_registry_conformance.py` derives variant exhaustiveness
from the payload spec. An operation that carries `effect_goal_instantiation` but
declares neither `payload_enum_field` nor `presence_branches` used to run neither
branch: the check count dropped by one (260 -> 259) and the run still printed PASS,
so a non-exhaustive variant set would have gone unnoticed.

The earlier defect-injection round mutated the *variant list* (truncation), which the
enum branch catches. Removing the two keys is a different mutation and was not covered.

These tests drive the checker over a copy of the real registry, so they exercise the
same code path the release check uses and fail if the hole reopens.

Run: python3 -m pytest tools/tests/test_registry_conformance_vacuity.py -q
"""

from __future__ import annotations

import copy
import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKER = REPO_ROOT / "tools/cameraanalysis/check_registry_conformance.py"
OPS = REPO_ROOT / "docs/cameraanalysis/operations-registry.v3-draft.json"
COV = REPO_ROOT / "docs/cameraanalysis/case-coverage.v3-draft.json"


def _load():
    spec = importlib.util.spec_from_file_location("check_registry_conformance", CHECKER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["check_registry_conformance"] = module
    spec.loader.exec_module(module)
    return module


tool = _load()


def _run(operations: dict, coverage: dict, tmp_path: Path, name: str) -> tuple[int, int, list[str]]:
    """Run the checker over the given registries; return (rc, checks, failures)."""
    ops_path = tmp_path / f"{name}-ops.json"
    cov_path = tmp_path / f"{name}-cov.json"
    ops_path.write_text(json.dumps(operations), encoding="utf-8")
    cov_path.write_text(json.dumps(coverage), encoding="utf-8")
    tool.OPS, tool.COV = ops_path, cov_path
    tool.failures.clear()
    tool.checks = 0
    with redirect_stdout(io.StringIO()):
        rc = tool.main()
    return rc, tool.checks, list(tool.failures)


@pytest.fixture
def registries():
    return (json.loads(OPS.read_text(encoding="utf-8")),
            json.loads(COV.read_text(encoding="utf-8")))


def test_the_real_registry_passes(registries, tmp_path: Path):
    rc, checks, failures = _run(*registries, tmp_path, "real")
    assert rc == 0, failures
    assert not failures
    assert checks >= 260, f"the checker ran only {checks} checks"


def test_an_operation_with_variants_must_contribute_an_exhaustiveness_check(registries, tmp_path: Path):
    """Dropping both derivation keys must fail, not silently skip the comparison."""
    operations, coverage = copy.deepcopy(registries)
    stripped = None
    for operation in operations["operations"]:
        instantiation = operation.get("effect_goal_instantiation")
        if instantiation:
            instantiation.pop("payload_enum_field", None)
            instantiation.pop("presence_branches", None)
            stripped = operation["operation_id"]
            break
    assert stripped, "no operation carries effect_goal_instantiation: the fixture is stale"
    rc, _, failures = _run(operations, coverage, tmp_path, "stripped")
    assert rc == 1
    assert any("exhaustiveness" in failure for failure in failures), failures


def test_truncating_the_variants_is_still_caught(registries, tmp_path: Path):
    """The mutation the earlier injection round did cover must keep failing."""
    operations, coverage = copy.deepcopy(registries)
    for operation in operations["operations"]:
        instantiation = operation.get("effect_goal_instantiation")
        if instantiation and instantiation.get("payload_enum_field"):
            instantiation["variants"] = instantiation["variants"][:-1]
            break
    rc, _, failures = _run(operations, coverage, tmp_path, "truncated")
    assert rc == 1
    assert any("exhaustive" in failure for failure in failures), failures


def test_the_presence_branch_is_live(registries, tmp_path: Path):
    """At least one operation derives exhaustiveness from presence_branches.

    If every operation switched to payload_enum_field, the presence path would be
    dead code; this keeps the branch exercised by a real operation.
    """
    operations, coverage = copy.deepcopy(registries)
    lifted = None
    for operation in operations["operations"]:
        instantiation = operation.get("effect_goal_instantiation")
        if instantiation and instantiation.get("presence_branches"):
            del instantiation["presence_branches"]
            lifted = operation["operation_id"]
            break
    assert lifted, ("no operation derives exhaustiveness from presence_branches: that path is now "
                    "unreachable, so it is untested")
    rc, _, failures = _run(operations, coverage, tmp_path, "presence")
    assert rc == 1
    assert any("exhaustiveness" in failure for failure in failures), failures


def test_an_empty_registry_does_not_pass(registries, tmp_path: Path):
    """An empty or malformed registry must never report PASS."""
    operations, coverage = copy.deepcopy(registries)
    operations["operations"] = []
    coverage["case_rows"] = []
    with redirect_stdout(io.StringIO()):
        try:
            rc = _run(operations, coverage, tmp_path, "empty")[0]
        except Exception:  # fail-closed may surface as a raised error, not a clean exit
            rc = 1
    assert rc != 0
