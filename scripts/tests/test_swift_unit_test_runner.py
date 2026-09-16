"""Invariants for the batched Swift unit-test runner.

`scripts/run_swift_unit_tests.sh` exists because a single full-target run needs more
free space than this machine had, and the run that crashed the volume is the reason
the disk guard exists. These tests drive the real script against stub binaries, so
they exercise discovery, batching and the exit codes without building anything.

The load-bearing assertion is that no invocation carries `-resultBundlePath`: that
omission is what makes a batch affordable, and re-adding it would silently restore
the multi-gigabyte cost that stopped the earlier run.

Run: python3 -m pytest scripts/tests/test_swift_unit_test_runner.py -q
"""

from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/run_swift_unit_tests.sh"
UDID = "11111111-1111-1111-1111-111111111111"


def _write_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def _stubs(tmp_path: Path, *, failing: bool = False, silent: bool = False) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    log = tmp_path / "xcodebuild-args.log"

    _write_executable(bin_dir / "xcrun", "#!/bin/sh\n"
                      f'echo "    iPhone Stub ({UDID}) (Booted)"\n')
    if silent:
        # A build failure: xcodebuild exits non-zero and prints no test case lines.
        outcome = "echo 'error: something did not compile'\nexit 65\n"
    elif failing:
        outcome = ("echo \"Test Case '-[StubTests testTwo]' failed on 'Clone 1 of iPhone Stub' (0.001 seconds)\"\n"
                   "echo '** TEST FAILED **'\nexit 65\n")
    else:
        outcome = (
            "echo \"Test Case '-[StubTests testOne]' passed on 'Clone 1 of iPhone Stub' (0.001 seconds)\"\n"
            "echo '** TEST SUCCEEDED **'\nexit 0\n")
    _write_executable(bin_dir / "xcodebuild",
                      "#!/bin/sh\n"
                      f'printf "%s\\n" "$@" >> "{log}"\n'
                      f'printf "%s\\n" "---" >> "{log}"\n'
                      f"{outcome}")

    env = dict(os.environ)
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["STUB_LOG"] = str(log)
    return env, log


def _run(tmp_path: Path, *args: str, failing: bool = False,
         silent: bool = False) -> tuple[int, str, list[list[str]]]:
    """A few large batches and a 1s poll keep the stub run fast while still
    exercising the batching path."""
    env, log = _stubs(tmp_path, failing=failing, silent=silent)
    result = subprocess.run(["bash", str(RUNNER), "--udid", UDID, "--batch-size", "40",
                             "--poll-seconds", "1", *args],
                            cwd=REPO_ROOT, capture_output=True, text=True, env=env, timeout=600)
    invocations: list[list[str]] = []
    if log.exists():
        for block in log.read_text(encoding="utf-8").split("---\n"):
            args_line = [line for line in block.splitlines() if line.strip()]
            if args_line:
                invocations.append(args_line)
    return result.returncode, result.stdout + result.stderr, invocations


def test_the_listing_previews_the_batches_without_a_simulator(tmp_path: Path):
    env, _ = _stubs(tmp_path)
    env["BATCHES_ONLY"] = "1"
    result = subprocess.run(["bash", str(RUNNER)], cwd=REPO_ROOT, capture_output=True,
                            text=True, env=env, timeout=300)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "batch 1:" in result.stdout
    assert "classes=" in result.stdout


def test_every_class_is_attempted_and_the_run_reports_success(tmp_path: Path):
    code, output, invocations = _run(tmp_path)
    assert code == 0, output
    assert "RESULT: PASSED" in output, output
    assert "failures=0" in output, output
    assert invocations, "the runner never invoked xcodebuild"
    # One -only-testing per class, and every class belongs to exactly one batch.
    only_testing = [arg for call in invocations for arg in call if arg.startswith("-only-testing:")]
    assert len(only_testing) == len(set(only_testing)), "a class was scheduled twice"


def test_no_invocation_carries_a_result_bundle(tmp_path: Path):
    """Re-adding -resultBundlePath restores the cost that stopped the earlier run."""
    _, _, invocations = _run(tmp_path)
    offenders = [arg for call in invocations for arg in call if arg.startswith("-resultBundlePath")]
    assert offenders == [], f"result bundles were requested: {offenders}"


def test_a_failing_case_makes_the_runner_fail(tmp_path: Path):
    code, output, _ = _run(tmp_path, failing=True)
    assert code == 1, output
    assert "RESULT: FAILED" in output, output


def test_an_unavailable_simulator_is_refused(tmp_path: Path):
    env, _ = _stubs(tmp_path)
    result = subprocess.run(["bash", str(RUNNER), "--udid", "99999999-9999-9999-9999-999999999999"],
                            cwd=REPO_ROOT, capture_output=True, text=True, env=env, timeout=300)
    assert result.returncode == 2, result.stdout + result.stderr
    assert "REFUSED" in result.stdout + result.stderr


def test_a_non_positive_batch_size_is_refused(tmp_path: Path):
    env, _ = _stubs(tmp_path)
    result = subprocess.run(["bash", str(RUNNER), "--batch-size", "0"],
                            cwd=REPO_ROOT, capture_output=True, text=True, env=env, timeout=300)
    assert result.returncode == 2, result.stdout + result.stderr


def test_a_batch_that_executes_no_test_case_is_a_failure(tmp_path: Path):
    """A build failure prints no test-case lines; that is not a clean batch.

    The first version of this runner counted only "passed" and "failed" lines, so a
    batch where nothing compiled was reported as a batch with nothing wrong — and nine
    of them scrolled past before the run was stopped by hand.
    """
    code, output, _ = _run(tmp_path, silent=True)
    assert code == 1, output
    assert "FAILING BATCH" in output, output
    assert "RESULT: PASSED" not in output, output
