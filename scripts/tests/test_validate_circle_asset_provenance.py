from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import zipfile
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "validate_circle_asset_provenance.py"
SPEC = importlib.util.spec_from_file_location("validate_circle_asset_provenance", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


REPO_ROOT = Path(__file__).resolve().parents[2]
REAL_RC_PROJECT = REPO_ROOT / "shafinMultitool/Resources/Circle.rcproject"
REAL_USDZ = REPO_ROOT / "shafinMultitool/Resources/Circle.usdz"
REAL_RECORD = (
    REPO_ROOT / "docs/implementation/provenance/circle-asset-provenance.json"
)


def _fixture(tmp_path: Path) -> tuple[Path, dict, Path]:
    fixture_root = tmp_path / "repo"
    resources = fixture_root / "shafinMultitool/Resources"
    resources.mkdir(parents=True)
    shutil.copytree(REAL_RC_PROJECT, resources / "Circle.rcproject")
    shutil.copy2(REAL_USDZ, resources / "Circle.usdz")

    record = json.loads(REAL_RECORD.read_text(encoding="utf-8"))
    record_path = tmp_path / "circle-record.json"
    record_path.write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return fixture_root, record, record_path


def _write_record(record: dict, record_path: Path) -> None:
    record_path.write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _rewrite_usdz(path: Path, members: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, payload in members.items():
            archive.writestr(name, payload)


def _refresh_export_archive_digest(record: dict, path: Path) -> None:
    payload = path.read_bytes()
    record["exported_usdz"]["size"] = len(payload)
    record["exported_usdz"]["sha256"] = hashlib.sha256(payload).hexdigest()


def test_circle_provenance_happy_path_uses_only_temporary_fixture(tmp_path: Path) -> None:
    fixture_root, _, record_path = _fixture(tmp_path)

    MODULE.validate_record(fixture_root, record_path)


def test_different_export_like_payload_with_same_uuid_does_not_prove_causality(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    fixture_root, record, record_path = _fixture(tmp_path)
    export_file = fixture_root / "shafinMultitool/Resources/Circle.usdz"
    member_name = record["exported_usdz"]["members"][0]["path"]
    metadata = record["exported_usdz"]["metadata"]
    shared_uuid = record["shared_identifiers"][0]["export_value"].encode("ascii")
    variant_payload = b"\x00".join(
        [
            metadata["member_format"].encode("ascii"),
            b"different-export-like-payload",
            metadata["rcfoundation_metadata_key"].encode("ascii"),
            metadata["rcfoundation_version"].encode("ascii"),
            shared_uuid,
        ]
    )
    with zipfile.ZipFile(REAL_USDZ) as archive:
        original_payload = archive.read(member_name)
    assert variant_payload != original_payload
    _rewrite_usdz(export_file, {member_name: variant_payload})
    _refresh_export_archive_digest(record, export_file)
    record["exported_usdz"]["members"][0]["size"] = len(variant_payload)
    record["exported_usdz"]["members"][0]["sha256"] = hashlib.sha256(
        variant_payload
    ).hexdigest()
    _write_record(record, record_path)

    status = MODULE.main(
        [
            "--repo-root",
            str(fixture_root),
            "--record",
            str(record_path),
        ]
    )
    output = capsys.readouterr().out

    assert status == 0
    assert "repository correlation verified" in output
    assert "source-to-export causality is not proven" in output
    assert "technical source linkage" not in output
    assert record["claims"]["repository_correlation"] == "verified"
    assert record["claims"]["source_to_export_causality"] == "not_proven"


def test_source_hash_drift_fails_without_touching_real_project(tmp_path: Path) -> None:
    fixture_root, _, record_path = _fixture(tmp_path)
    project_file = (
        fixture_root
        / "shafinMultitool/Resources/Circle.rcproject/com.apple.RCFoundation.Project"
    )
    original = project_file.read_bytes()
    project_file.write_bytes(original.replace(b'"cylinder"', b'"cylindeR"'))

    with pytest.raises(MODULE.ProvenanceValidationError, match="source member hash mismatch"):
        MODULE.validate_record(fixture_root, record_path)
    assert project_file.read_bytes() != (REAL_RC_PROJECT / "com.apple.RCFoundation.Project").read_bytes()


def test_export_hash_drift_fails_before_any_export_attempt(tmp_path: Path) -> None:
    fixture_root, _, record_path = _fixture(tmp_path)
    export_file = fixture_root / "shafinMultitool/Resources/Circle.usdz"
    export_file.write_bytes(export_file.read_bytes() + b"drift")

    with pytest.raises(MODULE.ProvenanceValidationError, match="exported USDZ hash mismatch"):
        MODULE.validate_record(fixture_root, record_path)


def test_missing_shared_identifier_fails_after_fixture_hashes_are_recorded(tmp_path: Path) -> None:
    fixture_root, record, record_path = _fixture(tmp_path)
    export_file = fixture_root / "shafinMultitool/Resources/Circle.usdz"
    with zipfile.ZipFile(export_file) as archive:
        member_name = archive.namelist()[0]
        payload = archive.read(member_name)
    original_identifier = b"44109F702E63424991FD37EDDF809807"
    assert original_identifier in payload
    payload = payload.replace(original_identifier, b"00000000000000000000000000000000", 1)
    _rewrite_usdz(export_file, {member_name: payload})
    _refresh_export_archive_digest(record, export_file)
    record["exported_usdz"]["members"][0]["size"] = len(payload)
    record["exported_usdz"]["members"][0]["sha256"] = hashlib.sha256(payload).hexdigest()
    _write_record(record, record_path)

    with pytest.raises(MODULE.ProvenanceValidationError, match="broken shared identifier"):
        MODULE.validate_record(fixture_root, record_path)


def test_malformed_record_fails_before_asset_reads(tmp_path: Path) -> None:
    fixture_root, record, record_path = _fixture(tmp_path)
    del record["shared_identifiers"]
    _write_record(record, record_path)

    with pytest.raises(
        MODULE.ProvenanceValidationError,
        match="record is missing required field 'shared_identifiers'",
    ):
        MODULE.validate_record(fixture_root, record_path)


def test_extra_source_member_fails(tmp_path: Path) -> None:
    fixture_root, _, record_path = _fixture(tmp_path)
    extra = fixture_root / "shafinMultitool/Resources/Circle.rcproject/extra.bin"
    extra.write_bytes(b"unrecorded")

    with pytest.raises(MODULE.ProvenanceValidationError, match="extra source member"):
        MODULE.validate_record(fixture_root, record_path)


def test_missing_source_member_fails(tmp_path: Path) -> None:
    fixture_root, _, record_path = _fixture(tmp_path)
    missing = (
        fixture_root
        / "shafinMultitool/Resources/Circle.rcproject/Library/ProjectLibrary/Version.json"
    )
    missing.unlink()

    with pytest.raises(MODULE.ProvenanceValidationError, match="missing source member"):
        MODULE.validate_record(fixture_root, record_path)


def test_extra_usdz_member_fails(tmp_path: Path) -> None:
    fixture_root, record, record_path = _fixture(tmp_path)
    export_file = fixture_root / "shafinMultitool/Resources/Circle.usdz"
    with zipfile.ZipFile(export_file) as archive:
        members = {name: archive.read(name) for name in archive.namelist()}
    members["unrecorded.usdc"] = b"unrecorded"
    _rewrite_usdz(export_file, members)
    _refresh_export_archive_digest(record, export_file)
    _write_record(record, record_path)

    with pytest.raises(MODULE.ProvenanceValidationError, match="extra USDZ member"):
        MODULE.validate_record(fixture_root, record_path)


def test_missing_usdz_member_fails(tmp_path: Path) -> None:
    fixture_root, record, record_path = _fixture(tmp_path)
    export_file = fixture_root / "shafinMultitool/Resources/Circle.usdz"
    _rewrite_usdz(export_file, {})
    _refresh_export_archive_digest(record, export_file)
    _write_record(record, record_path)

    with pytest.raises(MODULE.ProvenanceValidationError, match="missing USDZ member"):
        MODULE.validate_record(fixture_root, record_path)
