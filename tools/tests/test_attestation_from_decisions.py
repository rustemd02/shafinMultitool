"""Fail-closed tests for tools/datasets/attestation_from_decisions.py.

Covers:
  (a) an empty decision form -> exit 1, every missing decision listed, nothing
      written (an empty field is never treated as consent);
  (b) valid decisions on a synthetic fixture corpus -> attestation + attribution
      map written, and validate_rights_attestation.py accepts the attestation;
  (c) release scope without an attribution_string -> refusal;
  (d) an AVA/AADB/EVA-like identifier -> refusal;
  (e) without --append-manifest the rights manifest is byte-for-byte unchanged.

All tests run in tmp_path; the live rights-manifest.jsonl is never written.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLS = REPO_ROOT / "tools/datasets"
LIVE_RIGHTS_MANIFEST = REPO_ROOT / "datasets/camera-coach/v1/rights-manifest.jsonl"
FACTS = REPO_ROOT / "datasets/camera-coach/v1/cinematic-license-facts.draft.json"


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, TOOLS / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def converter():
    return _load("cc_attestation_from_decisions", "attestation_from_decisions.py")


@pytest.fixture(scope="module")
def validator():
    return _load("cc_validate_from_decisions", "validate_rights_attestation.py")


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _frame(record_id: str, film_dir: str, title: str, origin_url: str, ts: float) -> dict:
    return {
        "image_path": f"/fixture/frames/{film_dir}/{record_id}.jpg",
        "image_sha256": _sha(record_id),
        "mean_luma": 0.4,
        "stddev": 0.2,
        "provenance": {
            "kind": "video_screengrab",
            "license": "CC-BY 3.0 (Blender Foundation)",
            "origin": "download.blender.org",
            "origin_url": origin_url,
            "source": "cinematic",
            "timestamp_s": ts,
            "title": title,
        },
        "record_id": record_id,
        "timestamp_s": ts,
    }


FILMS = {
    "big_buck_bunny": ("Big Buck Bunny (Blender Open Movie)", "https://example.invalid/bbb.mp4"),
    "tears_of_steel": ("Tears of Steel (Blender Open Movie)", "https://example.invalid/tos.mov"),
    "tos_teaser": (
        "Tears of Steel — teaser (Blender Open Movie)",
        "https://example.invalid/tos-teaser.mp4",
    ),
}


def _write_manifest(tmp_path: Path) -> Path:
    per_film = {"big_buck_bunny": 3, "tears_of_steel": 2, "tos_teaser": 2}
    rows = []
    for film_dir, count in per_film.items():
        title, url = FILMS[film_dir]
        for i in range(count):
            record_id = f"cine__{film_dir}__frame_{i:04d}"
            rows.append(_frame(record_id, film_dir, title, url, float(i)))
    path = tmp_path / "cinematic-manifest.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return path


def _basis() -> dict:
    return {
        "basis_type": "license",
        "basis_reference": "CC-BY-3.0 license text (creativecommons.org/licenses/by/3.0/)",
        "basis_url": "https://creativecommons.org/licenses/by/3.0/legalcode",
        "basis_sha256": "",
    }


def _admit_subset(scope: str = "train+eval+release", people_present: bool = False,
                  consent: bool = False, consent_ref: str = "not_applicable") -> dict:
    return {
        "decision": "admit",
        "scope": scope,
        "permissions": {
            "production_allowed": True,
            "redistribution_allowed": True,
            "derived_media_allowed": True,
        },
        "people": {
            "people_present": people_present,
            "consent_obtained": consent,
            "consent_reference": consent_ref,
        },
        "basis": _basis(),
    }


def _valid_decisions(
    tmp_path: Path,
    tos_attribution: str = "Tears of Steel — (c) Blender Foundation, CC BY 3.0",
    corpus_id: str = "cinematic",
    decision: str = "admit",
    scope: str = "train+eval+release",
) -> Path:
    """A complete owner answer. BBB attribution_string is intentionally omitted so
    the facts file must supply it, proving fact fallback with provenance."""
    tos_ref = "publisher Mango note: technical demos, showcases, tutorials only"
    subsets = {
        "big_buck_bunny": _admit_subset(scope=scope),
        "tears_of_steel": _admit_subset(scope=scope, people_present=True, consent=True, consent_ref=tos_ref),
        "tos_teaser": _admit_subset(scope=scope, people_present=True, consent=True, consent_ref=tos_ref),
    }
    if decision != "admit":
        for key in subsets:
            subsets[key] = {**subsets[key], "decision": decision, "scope": ""}
    data = {
        "schema_id": "camera-owner-decisions-v1",
        "attester": {
            "attester_id": "owner-1",
            "attester_name": "Owner",
            "attester_role": "dataset-owner",
            "attester_contact": "owner@example.invalid",
        },
        "attested_at": "2026-09-13",
        "corpus": {"corpus_id": corpus_id, "source_id": corpus_id},
        "subsets": subsets,
        "attribution_map": {
            "provided_by": "owner-1",
            "entries": [
                {
                    "film_key": "big_buck_bunny",
                    "author": "Owner-declared author for big_buck_bunny",
                    "attribution_string": "",
                    "source_url": "",
                },
                {
                    "film_key": "tears_of_steel",
                    "author": "Owner-declared author for tears_of_steel",
                    "attribution_string": tos_attribution,
                    "source_url": "",
                },
                {
                    "film_key": "tos_teaser",
                    "author": "Owner-declared author for tos_teaser",
                    "attribution_string": "Tears of Steel teaser — (c) Blender Foundation, CC BY 3.0",
                    "source_url": "https://mango.blender.org/",
                },
            ],
        },
    }
    path = tmp_path / "decisions.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def _empty_decisions(tmp_path: Path) -> Path:
    data = {
        "schema_id": "camera-owner-decisions-v1",
        "attester": {
            "attester_id": "<who asserts this>",
            "attester_name": "",
            "attester_role": "PENDING",
        },
        "attested_at": "",
        "subsets": {
            "big_buck_bunny": {"decision": "", "scope": "", "permissions": {}, "people": {}, "basis": {}},
            "tears_of_steel": {"decision": None, "scope": "", "permissions": {}, "people": {}, "basis": {}},
            "tos_teaser": {"decision": "  ", "scope": "", "permissions": {}, "people": {}, "basis": {}},
        },
        "attribution_map": {"provided_by": "", "entries": []},
    }
    path = tmp_path / "empty-decisions.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def _run(converter, decisions: Path, tmp_path: Path, manifest: Path | None = None,
         extra: list[str] | None = None):
    att_out = tmp_path / "attestation.json"
    map_out = tmp_path / "attribution-map.json"
    argv = [
        "--decisions", str(decisions),
        "--attestation-out", str(att_out),
        "--attribution-map-out", str(map_out),
    ]
    if manifest is not None:
        argv += ["--manifest", str(manifest)]
    argv += extra or []
    code = converter.main(argv)
    return code, att_out, map_out


# --- (a) empty form refuses and writes nothing ------------------------------


def test_empty_form_refuses_lists_missing_and_writes_nothing(converter, tmp_path, capsys):
    decisions = _empty_decisions(tmp_path)
    manifest = _write_manifest(tmp_path)
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    err = capsys.readouterr().err
    assert "attester.attester_id" in err
    assert "attester.attester_role" in err
    assert "attested_at" in err
    for film in ("big_buck_bunny", "tears_of_steel", "tos_teaser"):
        assert f"subsets.{film}.decision" in err
    assert "attribution_map.entries" in err
    assert not att_out.exists(), "refusal must not write an attestation"
    assert not map_out.exists(), "refusal must not write an attribution map"


def test_empty_value_is_not_consent_even_when_other_fields_are_complete(converter, tmp_path, capsys):
    """A single blank scope on an otherwise complete form still refuses."""
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    data = json.loads(decisions.read_text())
    data["subsets"]["tears_of_steel"]["scope"] = ""
    decisions.write_text(json.dumps(data), encoding="utf-8")
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    assert "subsets.tears_of_steel.scope" in capsys.readouterr().err
    assert not att_out.exists() and not map_out.exists()


# --- (b) valid decisions produce validator-accepted artifacts ---------------


def test_valid_decisions_write_attestation_and_map(converter, validator, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 0, capsys.readouterr().err
    assert att_out.exists() and map_out.exists()

    attestation = json.loads(att_out.read_text())
    errors = validator.validate(attestation)
    assert errors == [], errors
    assert attestation["decision"]["admitted"] is True
    assert attestation["decision"]["decision"] == "admit"
    assert attestation["decision"]["decision_scope"] == "train+eval+release"
    assert attestation["permissions"]["production_allowed"] is True
    assert attestation["attribution"]["attribution_map_ref"] == str(map_out.resolve())
    assert len(attestation["subset_decisions"]) == 3
    assert attestation["corpus"]["manifest_sha256"] == hashlib.sha256(manifest.read_bytes()).hexdigest()

    attribution_map = json.loads(map_out.read_text())
    by_key = {entry["film_key"]: entry for entry in attribution_map["entries"]}
    facts = json.loads(FACTS.read_text())
    facts_license = facts["license"]
    facts_bbb = next(f for f in facts["films"] if f["film"] == "big_buck_bunny")
    # Facts fill what the owner left out, with provenance recorded.
    assert by_key["big_buck_bunny"]["attribution_string"] == facts_bbb["attribution_string"]
    assert by_key["big_buck_bunny"]["license_url"] == facts_license["url"]
    assert by_key["big_buck_bunny"]["source_url"] == facts_bbb["publisher_page"]
    assert any(
        "attribution_string[big_buck_bunny]" in field
        for field in attestation["_provenance"]["fields_from_facts"]
    )
    for entry in attribution_map["entries"]:
        assert entry["author"], f"author must be owner-provided for {entry['film_key']}"
        assert entry["attribution_string"], entry["film_key"]


def test_missing_author_for_admitted_film_refuses(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    data = json.loads(decisions.read_text())
    data["attribution_map"]["entries"][1]["author"] = ""
    decisions.write_text(json.dumps(data), encoding="utf-8")
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    assert "owner-provided" in capsys.readouterr().err
    assert not att_out.exists() and not map_out.exists()


def test_film_present_in_manifest_without_decision_refuses(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    data = json.loads(decisions.read_text())
    del data["subsets"]["tos_teaser"]
    decisions.write_text(json.dumps(data), encoding="utf-8")
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    assert "subsets.tos_teaser.decision" in capsys.readouterr().err
    assert not att_out.exists() and not map_out.exists()


# --- (c) release scope requires an attribution_string -----------------------


def test_release_scope_without_attribution_string_refuses(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    # Facts publish no Tears of Steel credit, so an admitted release with an empty
    # attribution_string cannot be completed by facts and must refuse.
    decisions = _valid_decisions(tmp_path, tos_attribution="")
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    err = capsys.readouterr().err
    assert "attribution_string" in err and "release" in err
    assert not att_out.exists() and not map_out.exists()


# --- (d) AVA / AADB / EVA can never be granted ------------------------------


@pytest.mark.parametrize("corpus_id", ["ava_hf_mirror", "aadb_official", "research/eva/fb40a9f1"])
def test_barred_corpus_refuses(converter, tmp_path, capsys, corpus_id):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path, corpus_id=corpus_id)
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    err = capsys.readouterr().err
    assert "AVA/AADB/EVA" in err or "research-only" in err
    assert not att_out.exists() and not map_out.exists()


def test_production_flag_without_linked_basis_refuses(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    data = json.loads(decisions.read_text())
    data["subsets"]["big_buck_bunny"]["basis"]["basis_url"] = ""
    data["subsets"]["big_buck_bunny"]["basis"]["basis_sha256"] = ""
    decisions.write_text(json.dumps(data), encoding="utf-8")
    code, att_out, map_out = _run(converter, decisions, tmp_path, manifest)
    assert code == 1
    assert "linked basis" in capsys.readouterr().err
    assert not att_out.exists() and not map_out.exists()


# --- (e) --append-manifest is opt-in ----------------------------------------


def test_without_append_manifest_rights_manifest_is_unchanged(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    rights_manifest = tmp_path / "rights-manifest.jsonl"
    shutil.copyfile(LIVE_RIGHTS_MANIFEST, rights_manifest)
    before = rights_manifest.read_bytes()
    live_before = LIVE_RIGHTS_MANIFEST.read_bytes()

    code, att_out, map_out = _run(
        converter, decisions, tmp_path, manifest,
        extra=["--rights-manifest", str(rights_manifest)],
    )
    assert code == 0, capsys.readouterr().err
    stdout = capsys.readouterr().out
    assert "--append-manifest" in stdout  # prints the exact next command
    assert rights_manifest.read_bytes() == before
    assert LIVE_RIGHTS_MANIFEST.read_bytes() == live_before
    assert att_out.exists() and map_out.exists()


def test_append_manifest_writes_admitted_record_only_when_requested(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    rights_manifest = tmp_path / "rights-manifest.jsonl"
    shutil.copyfile(LIVE_RIGHTS_MANIFEST, rights_manifest)
    live_before = LIVE_RIGHTS_MANIFEST.read_bytes()

    code, _, _ = _run(
        converter, decisions, tmp_path, manifest,
        extra=["--rights-manifest", str(rights_manifest), "--append-manifest"],
    )
    assert code == 0, capsys.readouterr().err
    lines = [line for line in rights_manifest.read_text().splitlines() if line.strip()]
    record = json.loads(lines[-1])
    assert record["admitted"] is True
    assert record["corpus_id"] == "cinematic"
    assert record["admitted_by"] == "owner-1"
    assert LIVE_RIGHTS_MANIFEST.read_bytes() == live_before


def test_append_manifest_refuses_when_nothing_admitted(converter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    decisions = _valid_decisions(tmp_path)
    data = json.loads(decisions.read_text())
    for key in data["subsets"]:
        data["subsets"][key]["decision"] = "quarantine"
        data["subsets"][key]["scope"] = ""
        data["subsets"][key]["permissions"] = {}
    decisions.write_text(json.dumps(data), encoding="utf-8")
    rights_manifest = tmp_path / "rights-manifest.jsonl"
    shutil.copyfile(LIVE_RIGHTS_MANIFEST, rights_manifest)
    before = rights_manifest.read_bytes()
    code, att_out, map_out = _run(
        converter, decisions, tmp_path, manifest,
        extra=["--rights-manifest", str(rights_manifest), "--append-manifest"],
    )
    assert code == 1
    assert "--append-manifest" in capsys.readouterr().err
    assert rights_manifest.read_bytes() == before
    assert not att_out.exists() and not map_out.exists()


# --- exit 2: missing/unparseable decisions ----------------------------------


def test_missing_decisions_file_exits_2(converter, tmp_path, capsys):
    att_out = tmp_path / "attestation.json"
    map_out = tmp_path / "attribution-map.json"
    code = converter.main(
        [
            "--decisions", str(tmp_path / "nope.json"),
            "--attestation-out", str(att_out),
            "--attribution-map-out", str(map_out),
        ]
    )
    assert code == 2
    assert not att_out.exists() and not map_out.exists()


def test_unparseable_decisions_file_exits_2(converter, tmp_path, capsys):
    bad = tmp_path / "bad.json"
    bad.write_text("{not json", encoding="utf-8")
    att_out = tmp_path / "attestation.json"
    map_out = tmp_path / "attribution-map.json"
    code = converter.main(
        [
            "--decisions", str(bad),
            "--attestation-out", str(att_out),
            "--attribution-map-out", str(map_out),
        ]
    )
    assert code == 2
    assert not att_out.exists() and not map_out.exists()
