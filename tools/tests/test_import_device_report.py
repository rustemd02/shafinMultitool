"""Self-tests for the fail-closed device-run report importer (Q03/Q04).

The importer is the only automatic path from an operator's device manifest into
the evidence chain, so these tests pin its failure modes: a wrong build, device,
OS or source timestamp must be rejected; missing fields must be rejected; and a
screenshot must never satisfy a thermal or audio-sync check. A checker that
accepts a plausible-looking but unpinned report is worse than no checker.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/device/import_device_report.py"

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
VIDEO = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 32

HEAD = "a" * 40
PORCELAIN = "b" * 64
DIRTY = "c" * 64
APP_SHA = "d" * 64

EXPECTATIONS = {
    "build_id": "q01-candidate-20260920",
    "build_sha256": APP_SHA,
    "configuration": "Debug",
    "device_model_identifier": "iPhone14,2",
    "os_version": "17.4",
    "source_head": HEAD,
    "source_porcelain_v2_sha256": PORCELAIN,
    "source_dirty_receipt_sha256": DIRTY,
}


def _load():
    spec = importlib.util.spec_from_file_location("import_device_report", TOOL)
    module = importlib.util.module_from_spec(spec)
    sys.modules["import_device_report"] = module
    spec.loader.exec_module(module)
    return module


importer = _load()


def _write(tmp_path: Path, name: str, payload: bytes) -> dict[str, str]:
    path = tmp_path / name
    path.write_bytes(payload)
    return {"path": name, "sha256": hashlib.sha256(payload).hexdigest()}


def _evidence(tmp_path: Path, name: str, payload: bytes, role: str, captured: str, measured=None, origin="device") -> dict:
    entry = _write(tmp_path, name, payload)
    entry.update(
        {
            "role": role,
            "origin": origin,
            "captured_utc": captured,
            "measured": measured,
        }
    )
    return entry


def _valid_report(tmp_path: Path) -> dict:
    screenshot = _evidence(tmp_path, "mic.png", PNG, "screenshot", "2026-10-01T10:05:00Z")
    thermal = _evidence(
        tmp_path,
        "soak.json",
        json.dumps({"thermal_sample_count": 120, "thermal_states_seen": ["nominal", "fair"]}).encode(),
        "benchmark_summary",
        "2026-10-01T11:30:00Z",
        measured={"thermal_sample_count": 120, "thermal_states_seen": ["nominal", "fair"]},
    )
    sync = _evidence(
        tmp_path,
        "avsync.json",
        json.dumps({"sync_error_start_ms": 12.0, "sync_error_end_ms": 41.0}).encode(),
        "audio_sync_report",
        "2026-10-01T10:40:00Z",
        measured={"sync_error_start_ms": 12.0, "sync_error_end_ms": 41.0},
    )
    return {
        "schema_version": "setos-device-run-report-v1",
        "run_id": "q04-2026-10-01-iphone13pro",
        "operator": "owner",
        "created_utc": "2026-10-01T12:05:00Z",
        "build": {
            "build_id": EXPECTATIONS["build_id"],
            "configuration": EXPECTATIONS["configuration"],
            "bundle_id": "com.vigvamcev-media.shafinMultitool",
            "version": "1.0",
            "build_number": "42",
            "app_sha256": APP_SHA,
        },
        "device": {
            "kind": "device",
            "model_identifier": "iPhone14,2",
            "marketing_name": "iPhone 13 Pro",
            "os_version": "17.4",
            "os_build": "21E219",
            "udid": "00008110-000000000000001E",
        },
        "source_state": {
            "branch": "store",
            "head": HEAD,
            "porcelain_v2_sha256": PORCELAIN,
            "dirty_receipt_sha256": DIRTY,
            "captured_utc": "2026-10-01T09:00:00Z",
        },
        "run_window": {"started_utc": "2026-10-01T10:00:00Z", "finished_utc": "2026-10-01T12:00:00Z"},
        "checks": [
            {
                "check_id": "rec.mic_permission",
                "category": "functional",
                "case_ids": ["CC-R02"],
                "status": "executed_pass",
                "evidence": [screenshot],
            },
            {
                "check_id": "rec.soak",
                "category": "thermal",
                "case_ids": ["CC-R04"],
                "status": "executed_pass",
                "evidence": [thermal],
            },
            {
                "check_id": "rec.av_sync",
                "category": "audio_sync",
                "case_ids": ["CC-V04"],
                "status": "executed_pass",
                "evidence": [sync],
            },
        ],
    }


def _expectations() -> "importer.Expectations":
    return importer.Expectations.from_mapping(EXPECTATIONS)


def _validate(tmp_path: Path, report: dict):
    return importer.validate_report(report, _expectations(), report_root=tmp_path)


# --------------------------------------------------------------------- (a) accept
def test_complete_report_from_the_pinned_tuple_is_accepted(tmp_path: Path) -> None:
    result = _validate(tmp_path, _valid_report(tmp_path))
    assert result.ok, result.render()
    assert result.normalized is not None
    assert result.normalized["import_verdict"] == "accepted"
    assert {check["check_id"] for check in result.normalized["checks"]} == {
        "rec.mic_permission",
        "rec.soak",
        "rec.av_sync",
    }


# ------------------------------------------- (b) foreign build/device/OS/source
def test_foreign_build_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["build"]["build_id"] = "some-other-candidate"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("wrong build" in error for error in result.errors), result.errors


def test_foreign_device_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["device"]["model_identifier"] = "iPhone17,1"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("wrong device" in error for error in result.errors), result.errors


def test_foreign_os_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["device"]["os_version"] = "26.5"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("wrong OS" in error for error in result.errors), result.errors


def test_missing_source_timestamp_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    del report["source_state"]["captured_utc"]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("source_state" in error and "captured_utc" in error for error in result.errors), result.errors


def test_evidence_timestamp_outside_the_run_window_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["checks"][0]["evidence"][0]["captured_utc"] = "2026-09-30T10:05:00Z"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("outside the run window" in error for error in result.errors), result.errors


# --------------------------------------------------------- (c) missing structure
def test_missing_build_block_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    del report["build"]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("build" in error for error in result.errors), result.errors


def test_missing_check_evidence_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    del report["checks"][0]["evidence"]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("evidence" in error for error in result.errors), result.errors


def test_executed_status_without_evidence_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["checks"][0]["evidence"] = []
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("requires at least one evidence" in error for error in result.errors), result.errors


def test_unexecuted_status_without_reason_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["checks"][2] = {
        "check_id": "rec.av_sync",
        "category": "audio_sync",
        "case_ids": ["CC-V04"],
        "status": "not_executed",
        "evidence": [],
    }
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("requires a written 'reason'" in error for error in result.errors), result.errors


# --------------------------------------------- (d) screenshot is not measurement
def test_screenshot_only_thermal_check_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    shot = _evidence(tmp_path, "soak_screenshot.png", PNG, "screenshot", "2026-10-01T11:30:00Z")
    report["checks"][1]["evidence"] = [shot]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("forbids role 'screenshot'" in error for error in result.errors), result.errors


def test_screenshot_only_audio_sync_check_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    clip = _evidence(tmp_path, "sync.mp4", VIDEO, "screen_recording", "2026-10-01T10:40:00Z")
    report["checks"][2]["evidence"] = [clip]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("forbids role 'screen_recording'" in error for error in result.errors), result.errors


def test_thermal_export_without_measured_samples_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    # A PNG relabelled as a JSON benchmark export must not pass the signature check.
    decoy = _evidence(tmp_path, "decoy.bin", PNG, "benchmark_summary", "2026-10-01T11:30:00Z")
    report["checks"][1]["evidence"] = [decoy]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("cannot be backed by png content" in error for error in result.errors), result.errors


def test_thermal_summary_missing_measured_keys_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    entry = _evidence(
        tmp_path,
        "soak_nokeys.json",
        json.dumps({"status": "ok"}).encode(),
        "benchmark_summary",
        "2026-10-01T11:30:00Z",
        measured={"status": "ok"},
    )
    report["checks"][1]["evidence"] = [entry]
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("thermal_sample_count" in error for error in result.errors), result.errors


# ---------------------------------------------------- anti-gaming / fail closed
def test_tampered_artifact_hash_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["checks"][0]["evidence"][0]["sha256"] = "0" * 64
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("sha256 mismatch" in error for error in result.errors), result.errors


def test_relabelling_a_check_category_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["checks"][1]["category"] = "functional"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("may not be relabelled" in error for error in result.errors), result.errors


def test_unknown_check_id_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["checks"][0]["check_id"] = "rec.something_invented"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("unknown check_id" in error for error in result.errors), result.errors


def test_simulator_device_kind_is_rejected(tmp_path: Path) -> None:
    report = _valid_report(tmp_path)
    report["device"]["kind"] = "simulator"
    result = _validate(tmp_path, report)
    assert not result.ok
    assert any("simulator evidence is not admissible" in error for error in result.errors), result.errors


def test_valid_report_and_rejection_both_return_real_exit_codes(tmp_path: Path) -> None:
    expectations_path = tmp_path / "expectations.json"
    expectations_path.write_text(json.dumps(EXPECTATIONS), encoding="utf-8")

    valid = _valid_report(tmp_path)
    valid_path = tmp_path / "valid.json"
    valid_path.write_text(json.dumps(valid), encoding="utf-8")
    accepted = subprocess.run(
        [
            sys.executable,
            str(TOOL),
            "--report",
            str(valid_path),
            "--expectations",
            str(expectations_path),
        ],
        capture_output=True,
        text=True,
    )
    assert accepted.returncode == 0, accepted.stdout + accepted.stderr
    assert "ACCEPTED" in accepted.stdout

    foreign = copy.deepcopy(valid)
    foreign["device"]["model_identifier"] = "iPhone11,2"
    foreign_path = tmp_path / "foreign.json"
    foreign_path.write_text(json.dumps(foreign), encoding="utf-8")
    rejected = subprocess.run(
        [
            sys.executable,
            str(TOOL),
            "--report",
            str(foreign_path),
            "--expectations",
            str(expectations_path),
        ],
        capture_output=True,
        text=True,
    )
    assert rejected.returncode == 1, rejected.stdout + rejected.stderr
    assert "REJECTED" in rejected.stdout


def test_cli_without_expectations_fails_closed(tmp_path: Path) -> None:
    report_path = tmp_path / "run.json"
    report_path.write_text(json.dumps(_valid_report(tmp_path)), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(TOOL), "--report", str(report_path)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1, result.stdout + result.stderr
    assert "FAIL CLOSED" in result.stdout
