"""Fail-closed tests for the Packet A rights-activation toolkit.

Covers:
  (a) tools refuse without an owner attestation and say what is missing;
  (b) a complete attestation + attribution map generates notices with the
      mandatory fields (author is owner-provided, never invented);
  (c) AVA/AADB/EVA marked production/admitted is rejected;
  (d) origin-family grouping keeps adjacent clip frames together and splits are
      refused while the rights manifest is not admitted;
  (e) --dry-run writes nothing.

The tools are loaded by path, matching the rest of tools/tests/.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLS = REPO_ROOT / "tools/datasets"


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, TOOLS / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def validator():
    return _load("cc_validate_rights", "validate_rights_attestation.py")


@pytest.fixture(scope="module")
def emitter():
    return _load("cc_emit_attribution", "emit_attribution_notices.py")


@pytest.fixture(scope="module")
def splitter():
    return _load("cc_build_split_groups", "build_split_groups.py")


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
    "tos_teaser": ("Tears of Steel — teaser (Blender Open Movie)", "https://example.invalid/tos-teaser.mp4"),
}


def _write_manifest(tmp_path: Path, per_film: dict[str, int] | None = None) -> Path:
    per_film = per_film or {"big_buck_bunny": 3, "tears_of_steel": 2, "tos_teaser": 2}
    rows = []
    for film_dir, count in per_film.items():
        title, url = FILMS[film_dir]
        for i in range(count):
            record_id = f"cine__{film_dir}__frame_{i:04d}"
            rows.append(_frame(record_id, film_dir, title, url, float(i)))
    path = tmp_path / "cinematic-manifest.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return path


def _write_attribution_map(tmp_path: Path, skip: str | None = None) -> Path:
    entries = []
    for film_dir, (title, url) in FILMS.items():
        if film_dir == skip:
            continue
        entries.append(
            {
                "film_key": film_dir,
                "title": title,
                "author": f"Owner-declared author for {film_dir}",
                "author_url": "https://example.invalid/author",
                "license_id": "CC-BY-3.0",
                "license_url": "https://creativecommons.org/licenses/by/3.0/",
                "attribution_string": f"(c) Owner-declared author for {film_dir}, CC BY 3.0",
                "source_url": url,
            }
        )
    path = tmp_path / "attribution-map.json"
    path.write_text(json.dumps({"attribution_map_schema_id": "camera-attribution-map-v1", "entries": entries}), encoding="utf-8")
    return path


def _valid_attestation(manifest: Path, map_path: Path | None = None, **overrides) -> dict:
    data = {
        "attestation_schema_id": "camera-rights-attestation-v1",
        "attestation_version": "v1.0.0",
        "attester": {
            "attester_id": "owner-1",
            "attester_name": "Owner",
            "attester_role": "dataset-owner",
            "attester_contact": "owner@example.invalid",
        },
        "attested_at": "2026-09-13",
        "corpus": {
            "corpus_id": "cinematic",
            "source_id": "cinematic",
            "source_path": "research/cinematic",
            "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
        },
        "license": {
            "license_id": "CC-BY-3.0",
            "license_name": "Creative Commons Attribution 3.0",
            "license_url": "https://creativecommons.org/licenses/by/3.0/",
            "attribution_required": True,
        },
        "permissions": {
            "production_allowed": True,
            "redistribution_allowed": True,
            "derived_media_allowed": True,
        },
        "people": {
            "people_present": False,
            "consent_obtained": False,
            "consent_reference": "not_applicable",
        },
        "basis": {
            "basis_type": "license",
            "basis_reference": "CC-BY-3.0 license text",
            "basis_url": "https://creativecommons.org/licenses/by/3.0/legalcode",
            "basis_sha256": "",
        },
        "attribution": {
            "attribution_map_ref": str(map_path) if map_path else "",
            "per_film": [],
        },
        "decision": {
            "admitted": True,
            "decision": "admit",
            "decision_scope": "train/calibration/locked/release",
        },
    }
    data.update(overrides)
    return data


def _write_json(tmp_path: Path, name: str, data: dict) -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


# --- (a) refusal without owner attestation ---------------------------------


def test_validator_refuses_without_attestation(validator, capsys):
    code = validator.main([])
    assert code == 1
    assert "--attestation" in capsys.readouterr().err


def test_emit_refuses_without_attestation_and_writes_nothing(emitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    out = tmp_path / "out"
    code = emitter.main(["--manifest", str(manifest), "--out-dir", str(out)])
    assert code == 1
    err = capsys.readouterr().err
    assert "missing --attestation" in err
    assert "attribution map" in err
    assert not out.exists() or list(out.iterdir()) == []


def test_emit_refuses_when_attribution_map_missing_a_film(emitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    att = _write_json(tmp_path, "att.json", _valid_attestation(manifest))
    partial = _write_attribution_map(tmp_path, skip="tos_teaser")
    out = tmp_path / "out"
    code = emitter.main(
        [
            "--manifest", str(manifest),
            "--out-dir", str(out),
            "--attestation", str(att),
            "--attribution-map", str(partial),
        ]
    )
    assert code == 1
    err = capsys.readouterr().err
    assert "tos_teaser" in err and "no attribution map entry" in err and "author" in err
    assert not out.exists() or list(out.iterdir()) == []


# --- (b) complete attestation generates notices ----------------------------


def test_valid_attestation_passes_validator(validator, tmp_path):
    manifest = _write_manifest(tmp_path)
    map_path = _write_attribution_map(tmp_path)
    att = _write_json(tmp_path, "att.json", _valid_attestation(manifest, map_path))
    assert validator.validate(json.loads(att.read_text())) == []


def test_emit_generates_attribution_with_required_fields(emitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    map_path = _write_attribution_map(tmp_path)
    att = _write_json(tmp_path, "att.json", _valid_attestation(manifest, map_path))
    out = tmp_path / "out"
    code = emitter.main(
        [
            "--manifest", str(manifest),
            "--out-dir", str(out),
            "--attestation", str(att),
            "--attribution-map", str(map_path),
        ]
    )
    assert code == 0
    jsonl = out / "cinematic-attribution.draft.jsonl"
    assert jsonl.exists()
    rows = [json.loads(line) for line in jsonl.read_text().splitlines() if line.strip()]
    assert len(rows) == 7  # 3 + 2 + 2 fixture frames == manifest count
    for row in rows:
        for field in ("author", "title", "license", "license_url", "source_url", "notice_text", "image_sha256"):
            assert row[field], f"notice missing {field}"
        assert row["author"] != row["title"]  # author is owner-declared, not the film title
        assert row["admitted"] is True and row["release_cleared"] is True
    summary = json.loads((out / "cinematic-attribution-summary.draft.json").read_text())
    assert summary["notice_count"] == summary["manifest_frame_count"] == 7
    assert summary["admitted"] is True


def test_emit_requires_count_discrepancy_explanation(emitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    map_path = _write_attribution_map(tmp_path)
    att = _write_json(tmp_path, "att.json", _valid_attestation(manifest, map_path))
    # Queue only knows two of the seven frames.
    queue = tmp_path / "queue.jsonl"
    first = json.loads(manifest.read_text().splitlines()[0])
    queue.write_text(json.dumps(first) + "\n", encoding="utf-8")
    out = tmp_path / "out"
    common = [
        "--manifest", str(manifest),
        "--out-dir", str(out),
        "--attestation", str(att),
        "--attribution-map", str(map_path),
        "--annotation-queue", str(queue),
    ]
    assert emitter.main(common) == 1
    assert "count discrepancy" in capsys.readouterr().err
    assert emitter.main([*common, "--count-discrepancy-note", "queue predates 6 teaser frames"]) == 0
    assert (out / "cinematic-attribution.draft.jsonl").exists()


# --- (c) barred corpora -----------------------------------------------------


@pytest.mark.parametrize("corpus", ["ava_hf_mirror", "aadb_official", "eva_official", "research/eva/fb40a9f1"])
def test_validator_rejects_barred_production(validator, tmp_path, corpus):
    manifest = _write_manifest(tmp_path)
    att = _valid_attestation(manifest)
    att["corpus"]["corpus_id"] = corpus
    att["corpus"]["source_id"] = corpus
    errors = validator.validate(att)
    assert any("research-only source" in e for e in errors), errors
    assert any("production_allowed" in e for e in errors), errors


def test_validator_rejects_barred_admitted_even_without_production_flag(validator, tmp_path):
    manifest = _write_manifest(tmp_path)
    att = _valid_attestation(manifest)
    att["corpus"]["corpus_id"] = "aadb_official"
    att["permissions"]["production_allowed"] = False
    att["permissions"]["redistribution_allowed"] = False
    errors = validator.validate(att)
    assert any("admitting it as release-clearable" in e for e in errors), errors


def test_validator_rejects_admitted_without_basis(validator, tmp_path):
    manifest = _write_manifest(tmp_path)
    att = _valid_attestation(manifest)
    att["basis"] = {"basis_type": "", "basis_reference": "", "basis_url": "", "basis_sha256": ""}
    errors = validator.validate(att)
    assert any("without a complete, linked basis" in e for e in errors), errors


def test_emit_rejects_barred_attestation(emitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    map_path = _write_attribution_map(tmp_path)
    att = _valid_attestation(manifest, map_path)
    att["corpus"]["corpus_id"] = "ava_hf_mirror"
    att_path = _write_json(tmp_path, "ava-att.json", att)
    out = tmp_path / "out"
    code = emitter.main(
        [
            "--manifest", str(manifest),
            "--out-dir", str(out),
            "--attestation", str(att_path),
            "--attribution-map", str(map_path),
        ]
    )
    assert code == 1
    assert "research-only source" in capsys.readouterr().err
    assert not out.exists() or list(out.iterdir()) == []


# --- (d) origin-family grouping and split refusal --------------------------


def test_grouping_keeps_adjacent_clip_frames_together(splitter, tmp_path):
    manifest = _write_manifest(tmp_path)
    rows = splitter.load_jsonl(manifest)
    groups = splitter.group_records(rows)
    assert len(groups) == 3  # one per origin clip
    by_label = {g["family_label"]: g for g in groups}
    assert by_label["big_buck_bunny"]["frame_count"] == 3
    assert by_label["tears_of_steel"]["frame_count"] == 2
    assert by_label["tos_teaser"]["frame_count"] == 2
    assert all(g["family_kind"] == "clip" for g in groups)


def test_derivatives_and_episodes_share_a_family(splitter):
    base = _frame("base", "shoot", "Shoot", "https://example.invalid/a", 0.0)
    crop = dict(base, record_id="crop")
    crop["provenance"] = dict(base["provenance"], derives_from="base")
    episode = dict(base, record_id="ep2")
    episode["provenance"] = dict(base["provenance"], episode_id="ep-1")
    episode2 = dict(base, record_id="ep1")
    episode2["provenance"] = dict(base["provenance"], episode_id="ep-1")
    groups = splitter.group_records([base, crop, episode, episode2])
    kinds = {g["family_kind"]: g["frame_count"] for g in groups}
    assert kinds["derivation"] == 1
    assert kinds["episode"] == 2
    assert kinds["clip"] == 1


def test_split_refuses_while_rights_manifest_not_admitted(splitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    out = tmp_path / "out"
    code = splitter.main(
        [
            "--manifest", str(manifest),
            "--rights-manifest", str(REPO_ROOT / "datasets/camera-coach/v1/rights-manifest.jsonl"),
            "--out-dir", str(out),
            "--dry-run",
        ]
    )
    assert code == 1
    err = capsys.readouterr().err
    assert "REFUSED to emit splits" in err
    assert "not admitted" in err
    assert not out.exists() or list(out.iterdir()) == []


def _write_admitted_rights(tmp_path: Path) -> Path:
    path = tmp_path / "rights-manifest.jsonl"
    row = {
        "manifest_type": "rights",
        "schema_id": "camera-rights-manifest-v1",
        "record_count": 1,
        "template_only": False,
        "entries": [
            {
                "record_id": "rights-cinematic-0001",
                "corpus_id": "cinematic",
                "source_id": "cinematic",
                "admitted": True,
                "admitted_by": "owner-1",
                "attested_at": "2026-09-13",
            }
        ],
    }
    path.write_text(json.dumps(row) + "\n", encoding="utf-8")
    return path


def test_split_emits_atomic_groups_when_admitted(splitter, tmp_path):
    manifest = _write_manifest(tmp_path)
    rights = _write_admitted_rights(tmp_path)
    out = tmp_path / "out"
    code = splitter.main(
        [
            "--manifest", str(manifest),
            "--rights-manifest", str(rights),
            "--out-dir", str(out),
        ]
    )
    assert code == 0
    groups = [json.loads(line) for line in (out / "cinematic-split-groups.draft.jsonl").read_text().splitlines() if line.strip()]
    assert len(groups) == 3
    summary = json.loads((out / "cinematic-splits.draft.json").read_text())
    assert summary["cross_split_leak_count"] == 0
    assert summary["group_count"] == 3
    # Every origin family is assigned to exactly one split.
    assert all(g["split"] in splitter.SPLITS for g in groups)
    assert len({g["group_id"] for g in groups}) == 3


# --- (e) dry-run writes nothing --------------------------------------------


def test_emit_dry_run_writes_nothing(emitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    out = tmp_path / "out"
    code = emitter.main(["--manifest", str(manifest), "--out-dir", str(out), "--dry-run"])
    assert code == 0
    stdout = capsys.readouterr().out
    assert "DRY-RUN" in stdout
    assert "NO 'author' field" in stdout
    for film in ("big_buck_bunny", "tears_of_steel", "tos_teaser"):
        assert film in stdout
    assert not out.exists() or list(out.iterdir()) == []


def test_split_dry_run_writes_nothing_even_when_admitted(splitter, tmp_path, capsys):
    manifest = _write_manifest(tmp_path)
    rights = _write_admitted_rights(tmp_path)
    out = tmp_path / "out"
    code = splitter.main(
        [
            "--manifest", str(manifest),
            "--rights-manifest", str(rights),
            "--out-dir", str(out),
            "--dry-run",
        ]
    )
    assert code == 0
    assert "DRY-RUN" in capsys.readouterr().out
    assert not out.exists() or list(out.iterdir()) == []
