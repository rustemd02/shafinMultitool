"""Splits must honour the owner's per-film decisions, not just the corpus decision.

The admission record is written by `attestation_from_decisions.py`. While it carried
only a corpus-level `admitted: true`, a consumer could not tell that a particular film
had been quarantined — and the splits tool grouped every family, so quarantined frames
landed in `train`. The converter now records the per-film decisions and the split tool
filters on them.

These tests cover both bases: a record with per-film decisions filters the families
and reports the excluded ones, and a record without them keeps the previous
corpus-level behaviour while saying so in the output.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SPLITS_TOOL = REPO_ROOT / "tools/datasets/build_split_groups.py"
DECISIONS_TOOL = REPO_ROOT / "tools/datasets/attestation_from_decisions.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


splits = _load(SPLITS_TOOL, "split_groups_admission")
converter = _load(DECISIONS_TOOL, "attestation_converter_admission")


def _manifest(tmp_path: Path) -> Path:
    rows = []
    for film, count in (("big_buck_bunny", 6), ("tears_of_steel", 4)):
        for index in range(count):
            rows.append({
                "record_id": f"cine__{film}__frame_{index:04d}",
                "image_path": f"/data/{film}/frame_{index:04d}.jpg",
                "image_sha256": "a" * 64,
                # family_of() derives the clip family from provenance.origin_url and
                # labels it with the parent directory, as the real manifest does
                "provenance": {"source": "cinematic", "origin": "download.blender.org",
                               "origin_url": f"https://example.invalid/{film}",
                               "title": film},
            })
    path = tmp_path / "manifest.jsonl"
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
    return path


def _rights(tmp_path: Path, *, subsets: dict | None) -> Path:
    header = {"manifest_type": "rights", "schema_id": "camera-rights-manifest-v1",
              "record_count": 1, "template_only": False}
    record = {"manifest_type": "rights", "record_id": "rights-cinematic-2026-09-13",
              "corpus_id": "cinematic", "source_id": "cinematic", "admitted": True,
              "admitted_by": "owner", "attested_at": "2026-09-13",
              "decision_scope": "train+eval", "basis_reference": "CC BY 3.0"}
    if subsets is not None:
        record["subset_decisions"] = subsets
    path = tmp_path / "rights-manifest.jsonl"
    path.write_text("\n".join(json.dumps(item) for item in (header, record)) + "\n",
                    encoding="utf-8")
    return path


def _run(tmp_path: Path, rights: Path, out_name: str = "splits"):
    manifest = _manifest(tmp_path)
    out_dir = tmp_path / out_name
    code = splits.main(["--manifest", str(manifest), "--rights-manifest", str(rights),
                        "--out-dir", str(out_dir)])
    summary_path = out_dir / "cinematic-splits.draft.json"
    groups_path = out_dir / "cinematic-split-groups.draft.jsonl"
    summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else None
    groups = [json.loads(line) for line in groups_path.read_text(encoding="utf-8").splitlines()
              if line.strip()] if groups_path.exists() else None
    return code, summary, groups


def test_per_film_decisions_exclude_quarantined_families(tmp_path: Path):
    rights = _rights(tmp_path, subsets={"big_buck_bunny": {"decision": "admit", "scope": "train+eval"},
                                        "tears_of_steel": {"decision": "quarantine", "scope": None}})
    code, summary, groups = _run(tmp_path, rights)
    assert code == 0
    assert {group["family_label"] for group in groups} == {"big_buck_bunny"}
    assert summary["admission_basis"] == "subset_decisions"
    assert summary["frame_count"] == 6
    assert summary["manifest_frame_count_total"] == 10
    assert summary["excluded_families"] == [{"family_label": "tears_of_steel",
                                             "decision": "quarantine", "frames": 4}]


def test_a_corpus_level_record_keeps_every_family_and_says_so(tmp_path: Path):
    """Legacy records have no per-film decisions; the weaker basis is visible."""
    rights = _rights(tmp_path, subsets=None)
    code, summary, groups = _run(tmp_path, rights)
    assert code == 0
    assert {group["family_label"] for group in groups} == {"big_buck_bunny", "tears_of_steel"}
    assert summary["admission_basis"] == "corpus_level"
    assert summary["excluded_families"] == []
    assert summary["frame_count"] == 10


def test_every_family_quarantined_refuses_rather_than_splitting_nothing(tmp_path: Path):
    rights = _rights(tmp_path, subsets={"big_buck_bunny": {"decision": "quarantine"},
                                        "tears_of_steel": {"decision": "quarantine"}})
    code, _, groups = _run(tmp_path, rights)
    assert code == 1
    assert groups is None


def test_the_converter_records_the_per_film_decisions(tmp_path: Path, capsys):
    """Without this the split tool cannot know a film was quarantined."""
    decisions = {
        "schema_id": "camera-owner-decisions-v1",
        "attester": {"attester_id": "owner", "attester_name": "Owner", "attester_role": "owner"},
        "attested_at": "2026-09-13",
        "corpus": {"corpus_id": "cinematic", "source_id": "cinematic"},
        "subsets": {
            "big_buck_bunny": {"decision": "admit", "scope": "train+eval",
                               "permissions": {"production_allowed": False,
                                               "redistribution_allowed": True,
                                               "derived_media_allowed": True},
                               "people": {"people_present": False, "consent_obtained": False,
                                          "consent_reference": "not_applicable"},
                               "basis": {"basis_type": "license", "basis_reference": "CC BY 3.0",
                                         "basis_url": "https://creativecommons.org/licenses/by/3.0/"}},
            "tears_of_steel": {"decision": "quarantine",
                               "basis": {"basis_type": "license",
                                         "basis_reference": "actor rights limitation",
                                         "basis_url": "https://mango.blender.org/"}},
            "tos_teaser": {"decision": "quarantine",
                           "basis": {"basis_type": "license",
                                     "basis_reference": "actor rights limitation",
                                     "basis_url": "https://mango.blender.org/"}},
        },
        "attribution_map": {"provided_by": "owner", "entries": [
            {"film_key": "big_buck_bunny", "author": "Blender Foundation",
             "attribution_string": "(c) copyright 2008, Blender Foundation / www.bigbuckbunny.org",
             "source_url": "https://peach.blender.org/"},
            {"film_key": "tears_of_steel", "author": "Blender Foundation",
             "attribution_string": "", "source_url": "https://mango.blender.org/"},
            {"film_key": "tos_teaser", "author": "Blender Foundation",
             "attribution_string": "", "source_url": "https://mango.blender.org/"},
        ]},
    }
    decisions_path = tmp_path / "decisions.json"
    decisions_path.write_text(json.dumps(decisions), encoding="utf-8")
    manifest = _manifest(tmp_path)
    rights = tmp_path / "rights.jsonl"
    rights.write_text(json.dumps({"manifest_type": "rights", "record_count": 0,
                                  "template_only": True}) + "\n", encoding="utf-8")
    code = converter.main(["--decisions", str(decisions_path), "--manifest", str(manifest),
                           "--attestation-out", str(tmp_path / "att.json"),
                           "--attribution-map-out", str(tmp_path / "map.json"),
                           "--rights-manifest", str(rights), "--append-manifest"])
    assert code == 0, capsys.readouterr().err
    record = [json.loads(line) for line in rights.read_text(encoding="utf-8").splitlines()
              if line.strip()][-1]
    assert record["admitted"] is True
    assert record["subset_decisions"]["tears_of_steel"]["decision"] == "quarantine"
    assert record["subset_decisions"]["big_buck_bunny"]["scope"] == "train+eval"
