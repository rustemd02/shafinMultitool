"""A quarantined film must not block the chain, and must not receive a notice or a claim.

The owner's realistic rights decision is mixed: one film admitted, the others
quarantined (the publisher states the actors keep portrait and privacy rights, and
publishes no credit string). Two behaviours follow from that, and both were wrong
before this suite existed:

* the notices step refused to write anything because the *quarantined* films lacked
  an `attribution_string` — but the decision form says only `decision` and `basis`
  are required for `quarantine`/`reject`, so the owner's own path dead-ended with no
  legitimate way out (inventing a credit for an unused film is forbidden);
* the emitted notices and summary stamped `release_cleared: true` on everything,
  even when the owner's scope was `train+eval`.

These tests pin the fixed behaviour on small fixtures; the rehearsal that found it ran
against the real 319-frame corpus manifest.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/datasets/emit_attribution_notices.py"


def _load():
    spec = importlib.util.spec_from_file_location("emit_notices_admission", TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["emit_notices_admission"] = module
    spec.loader.exec_module(module)
    return module


emitter = _load()


def _manifest(tmp_path: Path) -> Path:
    rows = []
    for film, count in (("big_buck_bunny", 3), ("tears_of_steel", 2)):
        for index in range(count):
            rows.append({
                "record_id": f"cine__{film}__frame_{index:04d}",
                "image_path": f"/data/{film}/frame_{index:04d}.jpg",
                "image_sha256": "a" * 64,
                "narrative_key": film,
                "provenance": {"source": "cinematic", "license": "CC-BY 3.0 (Blender Foundation)",
                               "origin": "download.blender.org"},
            })
    path = tmp_path / "manifest.jsonl"
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
    return path


def _attestation(tmp_path: Path, manifest: Path, map_path: Path, *, scope: str,
                 tears_decision: str) -> Path:
    document = {
        "attestation_schema_id": "camera-rights-attestation-v1",
        "attestation_version": "v1.0.0",
        "attester": {"attester_id": "owner", "attester_name": "Owner", "attester_role": "owner"},
        "attested_at": "2026-09-13",
        "corpus": {"corpus_id": "cinematic", "source_id": "cinematic",
                   "manifest_sha256": emitter.sha256_file(manifest)},
        "license": {"license_id": "CC-BY-3.0", "license_name": "CC BY 3.0",
                    "license_url": "https://creativecommons.org/licenses/by/3.0/",
                    "attribution_required": True},
        "permissions": {"production_allowed": "release" in scope,
                        "redistribution_allowed": True, "derived_media_allowed": True},
        "people": {"people_present": False, "consent_obtained": False,
                   "consent_reference": "not_applicable"},
        "basis": {"basis_type": "license", "basis_reference": "CC BY 3.0",
                  "basis_url": "https://creativecommons.org/licenses/by/3.0/"},
        "attribution": {"attribution_required": True, "attribution_map_ref": str(map_path)},
        "decision": {"admitted": True, "decision": "admit", "decision_scope": scope},
        "subset_decisions": {
            "big_buck_bunny": {"decision": "admit", "scope": scope},
            "tears_of_steel": {"decision": tears_decision, "scope": ""},
        },
    }
    path = tmp_path / "attestation.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def _map(tmp_path: Path, *, include_tears_string: bool) -> Path:
    entries = [
        {"film_key": "big_buck_bunny", "author": "Blender Foundation",
         "attribution_string": "(c) copyright 2008, Blender Foundation / www.bigbuckbunny.org",
         "license_url": "https://creativecommons.org/licenses/by/3.0/",
         "source_url": "https://peach.blender.org/"},
        {"film_key": "tears_of_steel", "author": "Blender Foundation",
         "attribution_string": "publisher credit" if include_tears_string else "",
         "license_url": "https://creativecommons.org/licenses/by/3.0/",
         "source_url": "https://mango.blender.org/"},
    ]
    path = tmp_path / "attribution-map.json"
    path.write_text(json.dumps({"schema_id": "camera-attribution-map-v1", "provided_by": "owner",
                                "entries": entries}), encoding="utf-8")
    return path


def _run(tmp_path: Path, *, scope: str, tears_decision: str, include_tears_string: bool):
    manifest = _manifest(tmp_path)
    attribution = _map(tmp_path, include_tears_string=include_tears_string)
    attestation = _attestation(tmp_path, manifest, attribution, scope=scope,
                               tears_decision=tears_decision)
    out_dir = tmp_path / "out"
    code = emitter.main(["--manifest", str(manifest), "--attestation", str(attestation),
                         "--attribution-map", str(attribution), "--out-dir", str(out_dir)])
    jsonl = out_dir / "cinematic-attribution.draft.jsonl"
    summary_path = out_dir / "cinematic-attribution-summary.draft.json"
    rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines()
            if line.strip()] if jsonl.exists() else None
    summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else None
    return code, rows, summary


# ------------------------------------------------- quarantine does not block
def test_a_quarantined_film_without_a_credit_string_does_not_block_the_chain(tmp_path: Path):
    """The documented contract only requires decision+basis for quarantine."""
    code, rows, summary = _run(tmp_path, scope="train+eval", tears_decision="quarantine",
                               include_tears_string=False)
    assert code == 0
    assert rows is not None and len(rows) == 3  # the admitted film's frames only
    assert {row["film_key"] for row in rows} == {"big_buck_bunny"}
    assert summary["films_skipped"] == {"tears_of_steel": "quarantine"}
    assert summary["films_emitted"] == ["big_buck_bunny"]


def test_an_admitted_film_still_requires_its_credit_fields(tmp_path: Path):
    """Skipping quarantined films must not weaken the admitted one's requirements."""
    manifest = _manifest(tmp_path)
    attribution = _map(tmp_path, include_tears_string=False)
    attestation = _attestation(tmp_path, manifest, attribution, scope="train+eval",
                               tears_decision="quarantine")
    document = json.loads(attribution.read_text(encoding="utf-8"))
    document["entries"][0]["attribution_string"] = ""
    attribution.write_text(json.dumps(document), encoding="utf-8")
    code = emitter.main(["--manifest", str(manifest), "--attestation", str(attestation),
                         "--attribution-map", str(attribution), "--out-dir", str(tmp_path / "o")])
    assert code == 1


def test_a_corpus_where_every_film_is_quarantined_is_refused(tmp_path: Path):
    """Nothing to attribute must not read as success."""
    manifest = _manifest(tmp_path)
    attribution = _map(tmp_path, include_tears_string=True)
    attestation = _attestation(tmp_path, manifest, attribution, scope="train+eval",
                               tears_decision="quarantine")
    document = json.loads(attestation.read_text(encoding="utf-8"))
    document["subset_decisions"]["big_buck_bunny"]["decision"] = "quarantine"
    attestation.write_text(json.dumps(document), encoding="utf-8")
    out_dir = tmp_path / "o2"
    code = emitter.main(["--manifest", str(manifest), "--attestation", str(attestation),
                         "--attribution-map", str(attribution), "--out-dir", str(out_dir)])
    assert code == 1
    assert not out_dir.exists()


# ------------------------------------------------------- derived release claim
def test_a_train_eval_scope_does_not_claim_release_clearance(tmp_path: Path):
    code, rows, summary = _run(tmp_path, scope="train+eval", tears_decision="quarantine",
                               include_tears_string=False)
    assert code == 0
    assert {row["release_cleared"] for row in rows} == {False}
    assert {row["admitted"] for row in rows} == {True}
    assert summary["release_cleared"] is False
    assert summary["admitted"] is True


def test_a_release_scope_everywhere_does_claim_release_clearance(tmp_path: Path):
    code, rows, summary = _run(tmp_path, scope="train+eval+release", tears_decision="quarantine",
                               include_tears_string=False)
    assert code == 0
    assert {row["release_cleared"] for row in rows} == {True}
    assert summary["release_cleared"] is True


def test_a_quarantined_subset_without_release_scope_blocks_the_release_claim(tmp_path: Path):
    """Even with a release corpus scope, an admitted subset that lacks it wins."""
    manifest = _manifest(tmp_path)
    attribution = _map(tmp_path, include_tears_string=False)
    attestation = _attestation(tmp_path, manifest, attribution, scope="train+eval+release",
                               tears_decision="quarantine")
    document = json.loads(attestation.read_text(encoding="utf-8"))
    document["subset_decisions"]["big_buck_bunny"]["scope"] = "train+eval"
    attestation.write_text(json.dumps(document), encoding="utf-8")
    out_dir = tmp_path / "out3"
    code = emitter.main(["--manifest", str(manifest), "--attestation", str(attestation),
                         "--attribution-map", str(attribution), "--out-dir", str(out_dir)])
    assert code == 0
    summary = json.loads((out_dir / "cinematic-attribution-summary.draft.json").read_text())
    assert summary["release_cleared"] is False
