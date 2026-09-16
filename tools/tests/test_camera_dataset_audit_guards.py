"""Regression tests for the fail-closed guards of `tools/camera_dataset_audit.py`.

That module is the cluster/split authority the ML lane imports as `m3`, and it
carries the guards the gates quietly depend on: an empty manifest, an
unreadable one, a manifest whose shape is not a container, a receipt that does
not match its schema, and — most importantly — any candidate/model identity
leaking into an otherwise valid manifest. It is 2400 lines and, until this file,
no test referenced it at all.

The tests pin refusals that were verified by hand: they assert the guard fires
*and* that the guard does not fire on a clean payload, so a check that always
raises cannot pass as coverage.

Run: python3 -m pytest tools/tests/test_camera_dataset_audit_guards.py -q
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE = REPO_ROOT / "tools/camera_dataset_audit.py"


def _load():
    spec = importlib.util.spec_from_file_location("camera_dataset_audit", MODULE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["camera_dataset_audit"] = module
    spec.loader.exec_module(module)
    return module


audit = _load()


def _write(tmp_path: Path, name: str, text: str) -> Path:
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return path


def _refuses(path: Path, fragment: str) -> None:
    with pytest.raises(audit.AuditInputError) as error:
        audit.load_manifest(path)
    assert fragment in str(error.value), str(error.value)


# ------------------------------------------------------------ manifest refusal
def test_an_empty_manifest_is_refused(tmp_path: Path):
    _refuses(_write(tmp_path, "empty.jsonl", ""), "empty_manifest")


def test_a_whitespace_only_manifest_is_refused(tmp_path: Path):
    _refuses(_write(tmp_path, "blank.json", "   \n\n"), "empty_manifest")


def test_a_non_json_manifest_is_refused(tmp_path: Path):
    _refuses(_write(tmp_path, "junk.json", "definitely not json"), "malformed_manifest_json")


def test_an_empty_array_manifest_is_refused(tmp_path: Path):
    """An empty list is not 'a manifest with no problems'; it is nothing to audit."""
    _refuses(_write(tmp_path, "arr.json", "[]"), "invalid_manifest_entries")


def test_an_empty_object_manifest_is_refused(tmp_path: Path):
    _refuses(_write(tmp_path, "obj.json", "{}"), "missing_rights_disposition")


def test_a_top_level_scalar_is_refused(tmp_path: Path):
    _refuses(_write(tmp_path, "scalar.json", "42"), "invalid_manifest_shape")


def test_raw_media_inside_git_is_refused(tmp_path: Path):
    payload = {"entries": [{"asset_id": "a", "path": "x.png"}], "raw_data_location": "inside_git"}
    _refuses(_write(tmp_path, "git.json", json.dumps(payload)), "raw_media_inside_git")


# ------------------------------------------------- candidate-identity leakage
def test_candidate_identity_in_the_header_is_refused(tmp_path: Path):
    payload = {"entries": [{"asset_id": "a", "path": "x.png"}], "candidate_id": "c1"}
    _refuses(_write(tmp_path, "hdr.json", json.dumps(payload)), "candidate_identity_leakage")


@pytest.mark.parametrize("payload", [
    {"entries": [{"candidate": "x"}]},
    {"entries": [{"oracle": 1}]},
    {"entries": {"a": {"model_output": 2}}},
    {"Entries": [{"Oracle": 1}]},
    {"locked_label": "good"},
])
def test_candidate_identity_is_refused_wherever_it_is_nested(tmp_path: Path, payload: dict):
    _refuses(_write(tmp_path, "leak.json", json.dumps(payload)), "candidate_identity_leakage")


def test_the_leak_guard_does_not_fire_on_a_clean_payload():
    """A guard that rejects everything would pass the tests above and protect nothing."""
    audit._reject_forbidden({"asset_id": "a", "path": ["x.png"], "provenance": {"source_kind": "owned"}})


# -------------------------------------------------------- receipt shape checks
def test_an_empty_cluster_receipt_is_refused():
    with pytest.raises(audit.AuditInputError) as error:
        audit.validate_cluster_output({})
    assert "cluster_schema_invalid" in str(error.value)


def test_an_empty_split_receipt_is_refused():
    with pytest.raises(audit.AuditInputError) as error:
        audit.validate_split_output({})
    assert "split_schema_invalid" in str(error.value)


def test_the_module_self_test_still_runs():
    """A positive control: the module's own happy path (real images -> cluster receipt)."""
    result = subprocess.run([sys.executable, "-m", "tools.camera_dataset_audit", "--self-test"],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "self-test" in (result.stdout + result.stderr)
