"""Weight release clearance must be derived and linked, not written down.

The runbook is explicit that credits do not clear research-only weights for the App
Store, and the §5 gate turns that into a verdict. Two properties are checked here:

* `tools/release/build_weight_lineage.py` derives each lineage entry from a real
  provenance document and a rights manifest, refuses a provenance that does not
  state its own lineage, and never clears an artifact the provenance calls
  `release_admissible: false`;
* the gate no longer accepts a free-text basis: a clearance has to point at the
  record it rests on and carry that record's digest.

The real-provenance checks skip when the artifact is absent from disk.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/build_weight_lineage.py"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"
REAL_PROVENANCE = REPO_ROOT / "ml/camera_coach/artifacts/SETCompositionNet-v2-tooling-untrained.mlpackage.provenance.json"
REAL_RIGHTS = REPO_ROOT / "datasets/camera-coach/v1/rights-manifest.jsonl"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


lineage_tool = _load(TOOL, "build_weight_lineage")
gates = _load(GATE_TOOL, "candidate_gates_for_lineage_tests")


def _provenance(tmp_path: Path, **overrides) -> Path:
    document = {
        "schema_id": "camera-v2-coreml-tooling-export-v1",
        "status": "trained_candidate",
        "release_admissible": True,
        "admitted_data": "admitted:cinematic-ccby",
        "weights_sha256": "a" * 64,
        "weights_origin": "trained on admitted corpora",
        "weight_parameter_count": 123,
        "candidate_id": "cand-1",
        "mlpackage": {"path": "artifacts/candidate.mlpackage"},
    }
    document.update(overrides)
    path = tmp_path / "provenance.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def _rights(tmp_path: Path, entries: list[dict]) -> Path:
    header = {"manifest_type": "rights", "schema_id": "camera-rights-manifest-v1",
              "record_count": len(entries), "template_only": False}
    path = tmp_path / "rights-manifest.jsonl"
    path.write_text("\n".join(json.dumps(record) for record in [header, *entries]) + "\n",
                    encoding="utf-8")
    return path


def _admitted_entry(**overrides) -> dict:
    entry = {
        "record_type": "rights-entry",
        "training_data_lineage": "admitted:cinematic-ccby",
        "corpus": {"corpus_id": "admitted:cinematic-ccby"},
        "decision": {"admitted": True, "decision": "admit", "decision_scope": "train+eval+release"},
        "basis": {"basis_type": "owner_decision", "basis_reference": "Packet A",
                  "basis_sha256": "b" * 64},
    }
    entry.update(overrides)
    return entry


def _run(tmp_path: Path, provenance: Path, rights: Path | None, *extra: str):
    out = tmp_path / "lineage.json"
    argv = ["--provenance", str(provenance), "--out", str(out), *extra]
    if rights is not None:
        argv += ["--rights-manifest", str(rights)]
    code = lineage_tool.main(argv)
    payload = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
    return code, payload


# ------------------------------------------------------- derivation behaviour
def test_an_admitted_provenance_with_a_release_scope_entry_is_cleared(tmp_path: Path):
    code, payload = _run(tmp_path, _provenance(tmp_path), _rights(tmp_path, [_admitted_entry()]))
    assert code == 0
    entry = payload["weight_lineage"][0]
    assert entry["release_cleared"] is True
    assert entry["basis_reference"] == "Packet A"
    assert entry["basis_sha256"] == "b" * 64
    gate = next(g for g in gates.evaluate({"weight_lineage": payload["weight_lineage"]})
                if g.name == "weight_lineage_release_cleared")
    assert gate.state == "pass", gate.detail


def test_a_train_only_scope_does_not_clear_a_release(tmp_path: Path):
    entry = _admitted_entry(decision={"admitted": True, "decision": "admit",
                                      "decision_scope": "train+eval"})
    code, payload = _run(tmp_path, _provenance(tmp_path), _rights(tmp_path, [entry]))
    assert code == 0
    assert payload["weight_lineage"][0]["release_cleared"] is False
    assert "no admitted rights entry with a release scope" in payload["weight_lineage"][0]["basis"]


def test_an_incomplete_rights_basis_does_not_clear(tmp_path: Path):
    entry = _admitted_entry(basis={"basis_type": "owner_decision", "basis_reference": "Packet A"})
    _, payload = _run(tmp_path, _provenance(tmp_path), _rights(tmp_path, [entry]))
    assert payload["weight_lineage"][0]["release_cleared"] is False
    assert "incomplete basis" in payload["weight_lineage"][0]["basis"]


def test_a_provenance_that_does_not_state_its_lineage_is_refused(tmp_path: Path, capsys):
    path = _provenance(tmp_path)
    document = json.loads(path.read_text(encoding="utf-8"))
    for key in ("admitted_data", "training_data", "training_data_lineage", "corpora"):
        document.pop(key, None)
    path.write_text(json.dumps(document), encoding="utf-8")
    code, _ = _run(tmp_path, path, None)
    assert code == 2
    assert "refusing to guess" in capsys.readouterr().err


def test_a_missing_provenance_pattern_fails_closed(tmp_path: Path, capsys):
    code = lineage_tool.main(["--provenance", str(tmp_path / "nope*.json")])
    assert code == 2
    assert "no provenance matches" in capsys.readouterr().err


def test_require_release_cleared_refuses_when_something_is_not_cleared(tmp_path: Path, capsys):
    entry = _admitted_entry(decision={"admitted": True, "decision": "admit",
                                      "decision_scope": "train"})
    code, _ = _run(tmp_path, _provenance(tmp_path), _rights(tmp_path, [entry]),
                   "--require-release-cleared")
    assert code == 1
    assert "require-release-cleared" in capsys.readouterr().err


# ------------------------------------------------- the real, blocked artifact
def test_the_real_tooling_artifact_cannot_be_release_cleared(tmp_path: Path):
    if not REAL_PROVENANCE.is_file():
        pytest.skip("the tooling provenance is not on disk")
    code, payload = _run(tmp_path, REAL_PROVENANCE, REAL_RIGHTS if REAL_RIGHTS.is_file() else None)
    assert code == 0
    entry = payload["weight_lineage"][0]
    assert entry["release_cleared"] is False
    assert "release_admissible=False" in entry["basis"]
    assert entry["training_data_lineage"] == "none"
    assert payload["rights_manifest"]["record_count"] == 0


def test_the_real_tooling_artifact_fails_the_gate_it_feeds(tmp_path: Path):
    if not REAL_PROVENANCE.is_file():
        pytest.skip("the tooling provenance is not on disk")
    _, payload = _run(tmp_path, REAL_PROVENANCE, REAL_RIGHTS if REAL_RIGHTS.is_file() else None)
    gate = next(g for g in gates.evaluate({"weight_lineage": payload["weight_lineage"]})
                if g.name == "weight_lineage_release_cleared")
    assert gate.state == "fail"
    assert "release_cleared" in gate.detail


# ------------------------------------------------ the gate requires a link
def _lineage_gate(entry: dict):
    manifest = {"weight_lineage": [entry]}
    return next(g for g in gates.evaluate(manifest) if g.name == "weight_lineage_release_cleared")


def test_a_free_text_basis_alone_no_longer_clears_a_weight():
    gate = _lineage_gate({"artifact": "m.mlpackage", "sha256": "a" * 64,
                          "training_data_lineage": "admitted:x", "release_cleared": True,
                          "basis": "trust me, it is fine"})
    assert gate.state == "fail"
    assert "not linked" in gate.detail


def test_a_basis_digest_that_is_not_a_sha256_fails():
    gate = _lineage_gate({"artifact": "m.mlpackage", "sha256": "a" * 64,
                          "training_data_lineage": "admitted:x", "release_cleared": True,
                          "basis": "owner decision", "basis_reference": "Packet A",
                          "basis_sha256": "not-a-digest"})
    assert gate.state == "fail"
    assert "not a lowercase sha256" in gate.detail


def test_a_linked_basis_clears_a_weight():
    gate = _lineage_gate({"artifact": "m.mlpackage", "sha256": "a" * 64,
                          "training_data_lineage": "admitted:x", "release_cleared": True,
                          "basis": "owner decision", "basis_reference": "Packet A",
                          "basis_sha256": "c" * 64})
    assert gate.state == "pass", gate.detail