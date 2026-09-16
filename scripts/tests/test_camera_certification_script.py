"""P03 invariants for the camera certification script.

The certification script is the instrument that decides whether a build "passed"
certification, so its failure modes are checked with stub binaries rather than by
reading the shell:

* a failing phase exits non-zero and the receipt says `failed`;
* an unavailable/stale simulator destination is refused *before* xcodebuild runs,
  instead of failing later in a way that could be mistaken for a test result;
* a later run does not delete an earlier run's evidence.

No real simulator or xcodebuild is involved: `PATH` is prefixed with stubs.
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts/run_camera_certification.sh"

SIM_UDID = "11111111-1111-1111-1111-111111111111"
SIMCTL_ONE_DEVICE = json.dumps({
    "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 16", "udid": SIM_UDID, "isAvailable": True, "state": "Shutdown"},
        ]
    }
})
SIMCTL_NO_DEVICES = json.dumps({"devices": {}})

XCODEBUILD_STUB = '''#!/usr/bin/env python3
import os, sys, pathlib
marker = os.environ.get("STUB_MARKER")
if marker:
    pathlib.Path(marker).write_text("xcodebuild invoked", encoding="utf-8")
args = sys.argv[1:]
if "-resultBundlePath" in args:
    bundle = pathlib.Path(args[args.index("-resultBundlePath") + 1])
    bundle.mkdir(parents=True, exist_ok=True)
    (bundle / "stub-result").write_text("bundle", encoding="utf-8")
sys.exit(int(os.environ.get("STUB_XCODEBUILD_EXIT", "0")))
'''

XCRUN_STUB = '''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args[:3] == ["simctl", "list", "devices"]:
    print(os.environ.get("STUB_SIMCTL_JSON", "{}"))
    sys.exit(0)
if args and args[0] == "xcresulttool":
    print(json.dumps({"result": "Passed", "totalTestCount": 3, "passedTests": 3,
                      "failedTests": 0, "skippedTests": 0, "testFailures": []}))
    sys.exit(0)
sys.exit(0)
'''


def _write_stub(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _stub_bin(tmp_path: Path) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_stub(bin_dir / "xcodebuild", XCODEBUILD_STUB)
    _write_stub(bin_dir / "xcrun", XCRUN_STUB)
    return bin_dir


def _run_script(tmp_path: Path, out_dir: Path, *, env_extra: dict | None = None,
                stub_simctl: str = SIMCTL_ONE_DEVICE) -> subprocess.CompletedProcess:
    bin_dir = _stub_bin(tmp_path)
    env = dict(os.environ)
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["STUB_SIMCTL_JSON"] = stub_simctl
    env.pop("UDID", None)
    env.update(env_extra or {})
    return subprocess.run([str(SCRIPT), str(out_dir)], capture_output=True, text=True, env=env)


def _receipt(out_dir: Path) -> dict:
    runs = sorted(path for path in out_dir.iterdir() if path.name.startswith("run-"))
    assert runs, "the run directory was not created"
    return json.loads((runs[-1] / "certification-receipt.json").read_text(encoding="utf-8"))


def test_a_clean_run_reports_passed_and_records_the_destination(tmp_path: Path):
    out_dir = tmp_path / "out"
    result = _run_script(tmp_path, out_dir)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "DESTINATION: platform=iOS Simulator,id=" + SIM_UDID + " (verified available)" in result.stdout
    receipt = _receipt(out_dir)
    assert receipt["status"] == "passed"
    assert receipt["phase_count"] == 2
    assert receipt["totals"]["passed"] == 6  # two phases, three stub tests each
    assert SIM_UDID in receipt["destination"]


def test_a_failing_phase_exits_non_zero_and_the_receipt_says_failed(tmp_path: Path):
    out_dir = tmp_path / "out"
    result = _run_script(tmp_path, out_dir, env_extra={"STUB_XCODEBUILD_EXIT": "65"})

    assert result.returncode == 1, result.stdout + result.stderr
    assert "CERTIFICATION_STATUS: failed" in result.stdout
    receipt = _receipt(out_dir)
    assert receipt["status"] == "failed"
    assert any(phase["xcodebuild_exit"] == 65 for phase in receipt["phases"])


def test_a_stale_udid_is_refused_before_any_xcodebuild_runs(tmp_path: Path):
    out_dir = tmp_path / "out"
    marker = tmp_path / "xcodebuild-ran"
    result = _run_script(
        tmp_path, out_dir,
        env_extra={"UDID": "DEADBEEF-0000-0000-0000-000000000000", "STUB_MARKER": str(marker)},
    )

    assert result.returncode == 2, result.stdout + result.stderr
    assert "CERTIFICATION_REFUSED" in result.stderr
    assert "not among the available simulators" in result.stderr
    assert not marker.exists(), "xcodebuild must not run against an unverified destination"


def test_no_available_simulator_refuses_rather_than_running(tmp_path: Path):
    out_dir = tmp_path / "out"
    marker = tmp_path / "xcodebuild-ran"
    result = _run_script(
        tmp_path, out_dir,
        env_extra={"STUB_MARKER": str(marker)}, stub_simctl=SIMCTL_NO_DEVICES,
    )

    assert result.returncode == 2, result.stdout + result.stderr
    assert "no available iOS simulator" in result.stderr
    assert not marker.exists()


def test_a_later_run_does_not_delete_earlier_evidence(tmp_path: Path):
    out_dir = tmp_path / "out"
    older = out_dir / "run-19700101T000000Z-1"
    older.mkdir(parents=True)
    keep = older / "closedloop-serial.xcresult"
    keep.mkdir()
    (keep / "previous-run-evidence").write_text("do not delete me", encoding="utf-8")

    result = _run_script(tmp_path, out_dir)

    assert result.returncode == 0, result.stdout + result.stderr
    assert (keep / "previous-run-evidence").read_text(encoding="utf-8") == "do not delete me"
    assert len([p for p in out_dir.iterdir() if p.name.startswith("run-")]) == 2


def test_the_evidence_note_matches_the_behaviour(tmp_path: Path):
    """The receipt may not claim something the script does not do."""
    out_dir = tmp_path / "out"
    _run_script(tmp_path, out_dir)
    receipt = _receipt(out_dir)
    assert "does not delete evidence" in receipt["evidence_note"]
    assert not any("rm -rf" in line for line in SCRIPT.read_text(encoding="utf-8").splitlines())
