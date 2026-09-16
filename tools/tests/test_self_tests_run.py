"""Every `--self-test` entry point in the repository runs, and stays listed here.

Fourteen tools ship a `--self-test` that exercises their own guards with negative
fixtures. None of them was invoked by any suite, so a broken guard could sit in
the tree indefinitely: the tests stayed green because nothing ran them.

This file closes that by running each one, and — more importantly — by deriving the
list from the source tree and asserting it matches the list below. Adding a new
`--self-test` without adding it here fails the suite, so the enumeration cannot
quietly fall behind reality (which is how `check_registry_conformance.py` and the
scene-job validator went uncovered in the first place).

Run: python3 -m pytest tools/tests/test_self_tests_run.py -q
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

# (invocation, target). Modules are launched with -m because they import siblings
# by package path; scripts are launched by path as their own docs show.
SELF_TESTS: tuple[tuple[str, str], ...] = (
    ("script", "tools/dataset/build_eva_silver.py"),
    ("script", "tools/dataset/camera_coach_check.py"),
    ("script", "tools/dataset/camera_source_intake.py"),
    ("script", "tools/dataset/fetch_aadb.py"),
    ("script", "tools/dataset/fetch_commons.py"),
    ("script", "tools/dataset/fetch_eva.py"),
    ("script", "tools/dataset/generate_camera_corruptions.py"),
    ("script", "tools/dataset/governance_check.py"),
    ("script", "tools/dataset/package_camera_colab.py"),
    ("script", "tools/dataset/package_camera_stage2_data.py"),
    ("script", "tools/scene_annotation/annotate_scene.py"),
    ("module", "tools.camera_dataset_audit"),
    ("module", "ml.camera_coach.pretrain_eva"),
    ("module", "ml.camera_coach.train_silver_actions"),
)

SCAN_ROOTS = ("tools", "ml", "scripts", "backend")

# A second class: these verify themselves simply by running, with no --self-test
# flag, so the flag-based discovery above cannot see them. The criterion is the
# filename, which makes the set derivable and the list impossible to let drift.
ML_SELF_CHECK_GLOB = "ml/camera_coach/**/check_*.py"
ML_SELF_CHECKS: tuple[str, ...] = (
    "ml.camera_coach.check_losses",
    "ml.camera_coach.check_training_environment",
    "ml.camera_coach.contracts.check_parity",
    "ml.camera_coach.data.check_augmentations",
    "ml.camera_coach.data.check_preprocessing_parity",
    "ml.camera_coach.models.check_candidates",
)


def _as_module(relative: str) -> str:
    return relative[: -len(".py")].replace("/", ".")


def _discover_ml_self_checks() -> set[str]:
    return {
        _as_module(path.relative_to(REPO_ROOT).as_posix())
        for path in (REPO_ROOT / "ml/camera_coach").rglob("check_*.py")
        if "__pycache__" not in path.parts and "tests" not in path.parts
    }


def _declares_self_test(path: Path) -> bool:
    return "--self-test" in path.read_text(encoding="utf-8", errors="ignore")


def _discover() -> set[str]:
    """Source files that declare a --self-test flag, excluding test code itself."""
    found: set[str] = set()
    for root in SCAN_ROOTS:
        for path in (REPO_ROOT / root).rglob("*.py"):
            if "__pycache__" in path.parts:
                continue
            if "tests" in path.parts or path.name.startswith("test_"):
                continue
            if _declares_self_test(path):
                found.add(path.relative_to(REPO_ROOT).as_posix())
    return found


def _file_for(kind: str, target: str) -> Path:
    """Map a launch target to the source file it names."""
    relative = target if kind == "script" else target.replace(".", "/") + ".py"
    return REPO_ROOT / relative


def test_the_self_test_list_is_not_trivially_small():
    """An emptied list would make the parametrised test below collect nothing."""
    assert len(SELF_TESTS) >= 10, SELF_TESTS
    for kind, target in SELF_TESTS:
        assert _file_for(kind, target).is_file(), f"listed target is missing: {target}"


def test_every_discovered_self_test_is_enforced_here():
    declared = {_file_for(kind, target).relative_to(REPO_ROOT).as_posix()
                for kind, target in SELF_TESTS}
    discovered = _discover()
    missing = sorted(discovered - declared)
    assert not missing, (
        "these files declare a --self-test that nothing runs; add them to SELF_TESTS: "
        f"{missing}")
    stale = sorted(declared - discovered)
    assert not stale, f"SELF_TESTS lists files that no longer declare --self-test: {stale}"


@pytest.mark.parametrize("kind,target", SELF_TESTS)
def test_each_self_test_runs_green(kind: str, target: str):
    command = ([sys.executable, "-m", target] if kind == "module"
               else [sys.executable, target]) + ["--self-test"]
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
    output = result.stdout + result.stderr
    assert result.returncode == 0, f"{target} --self-test failed:\n{output[-1500:]}"
    assert output.strip(), f"{target} --self-test printed nothing, so nothing was shown to pass"


def _tree_state() -> str:
    return subprocess.run(["git", "status", "--porcelain", "--", *SCAN_ROOTS],
                          cwd=REPO_ROOT, capture_output=True, text=True).stdout


def test_the_ml_self_check_list_matches_the_tree():
    """Adding a check_*.py that nothing runs must fail here, not pass silently."""
    assert len(ML_SELF_CHECKS) >= 5, ML_SELF_CHECKS
    discovered = _discover_ml_self_checks()
    assert discovered == set(ML_SELF_CHECKS), (
        f"missing from ML_SELF_CHECKS: {sorted(discovered - set(ML_SELF_CHECKS))}; "
        f"listed but absent: {sorted(set(ML_SELF_CHECKS) - discovered)}")


@pytest.mark.parametrize("target", ML_SELF_CHECKS)
def test_each_ml_self_check_runs_green(target: str):
    result = subprocess.run([sys.executable, "-m", target],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=900)
    output = result.stdout + result.stderr
    assert result.returncode == 0, f"{target} failed:\n{output[-1500:]}"
    assert output.strip(), f"{target} printed nothing, so nothing was shown to pass"


def test_the_ml_self_checks_do_not_write_into_the_repository():
    before = _tree_state()
    for target in ML_SELF_CHECKS:
        subprocess.run([sys.executable, "-m", target],
                       cwd=REPO_ROOT, capture_output=True, text=True, timeout=900)
    assert _tree_state() == before, "running the ML self-checks changed the working tree"


def test_the_self_tests_do_not_write_into_the_repository():
    """A self-test that leaves files behind would corrupt the tree it is verifying.

    Only the change is compared, so an already-dirty working tree is fine; that is
    the normal state here.
    """
    before = _tree_state()
    for kind, target in SELF_TESTS:
        command = ([sys.executable, "-m", target] if kind == "module"
                   else [sys.executable, target]) + ["--self-test"]
        subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
    after = _tree_state()
    assert before == after, "running the self-tests changed the working tree"
