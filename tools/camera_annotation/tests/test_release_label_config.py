#!/usr/bin/env python3
"""Unit tests for the DATA-005 GUI release-label config builder.

Headless coverage for the annotate_gui export path: the pure builder
(release_label_config.build_conversion_config) plus the real adapter CLI
boundary it drives. No tkinter is instantiated — the GUI only reads widgets
into the plain dicts these tests construct by hand.

Happy path: a fixture v1 review + GUI-collected elicitations must convert
through release_label_adapter.py and pass the DATA-001 contract validator
(RELEASE LABEL VALID). Missing elicitation: the builder refuses (so the GUI
never invokes the adapter and writes nothing), and the adapter itself
rejects an evidence-less config fed directly to its CLI (no output file).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parents[1]
ADAPTER = TOOLS / "release_label_adapter.py"
sys.path.insert(0, str(TOOLS))

from annotation_labels import build_label, sha256_file  # noqa: E402
from release_label_config import (  # noqa: E402
    ReleaseConfigError,
    build_conversion_config,
    derive_source_fields,
    parse_unit_interval,
    sanitize_release_record_id,
    sanitize_stable_id,
)

CAPTURED_AT = "2026-09-22T10:00:00Z"


def make_image(tmp_path: Path) -> Path:
    image = tmp_path / "frame_0001.jpg"
    image.write_bytes(b"\xff\xd8fake-jpeg-bytes-for-test-only")
    return image


def make_review(tmp_path: Path, **overrides) -> dict:
    image = make_image(tmp_path)
    kwargs = dict(
        record_id="benchmark__frame_0001",
        image_sha256=sha256_file(image),
        annotator_id="tester",
        beauty="ugly",
        improvement_needed=True,
        issues=["background_competes_with_subject"],
        actions=["move_object_left"],
        regions=[{"role": "distractor", "rect": [0.6, 0.5, 0.3, 0.3], "label": "lamp"}],
        notes="лампа справа отвлекает",
        image_path=str(image),
        provenance={"source": "benchmark", "license": "project-owned", "origin": "repo"},
    )
    kwargs.update(overrides)
    return build_label(**kwargs)


def gui_evidence(ref: str = "benchmark__frame_0001.region0") -> dict:
    return {
        "background_competes_with_subject": {
            "severity": "0.7",
            "confidence": "0.8",
            "evidence_refs": [ref],
        }
    }


def gui_target(**overrides) -> dict:
    target = {
        "entity_ref": "lamp-1",
        "identity_status": "resolved",
        "kind": "object",
        "role": "target",
        "movability_status": "movable",
        "movability_permission": "allowed",
        "rect": [0.6, 0.5, 0.3, 0.3],
    }
    target.update(overrides)
    return target


def run_adapter(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(ADAPTER), *args], capture_output=True, text=True, timeout=120
    )


def write_json(path: Path, payload: dict) -> Path:
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return path


# ------------------------------------------------------------- pure helpers
def test_release_record_id_is_sanitized_to_contract_pattern():
    assert (
        sanitize_release_record_id("benchmark__Frame 001.JPG")
        == "cam-release-benchmark__frame-001.jpg"
    )
    assert sanitize_release_record_id("ava__x-2").startswith("cam-release-ava__x-2")
    with pytest.raises(ReleaseConfigError):
        sanitize_release_record_id("___")


def test_stable_id_sanitizer_requires_latin_vocabulary():
    assert sanitize_stable_id("lamp 1", "target.entity_ref") == "lamp-1"
    # Cyrillic region labels cannot become stable ids: refuse instead of
    # transliterating (identity must not be silently rewritten).
    with pytest.raises(ReleaseConfigError):
        sanitize_stable_id("лампа", "target.entity_ref")


def test_unit_interval_parsing_refuses_blank_and_out_of_range():
    assert parse_unit_interval("0,8", "x") == 0.8
    assert parse_unit_interval(1.0, "x") == 1.0
    with pytest.raises(ReleaseConfigError):
        parse_unit_interval("", "severity")
    with pytest.raises(ReleaseConfigError):
        parse_unit_interval("abc", "severity")
    with pytest.raises(ReleaseConfigError):
        parse_unit_interval("1.5", "severity")


def test_source_fields_derive_from_record_without_fabricating_capture_time():
    review = make_review(Path("/tmp"))  # image path is only read, not hashed here
    fields = derive_source_fields(review)
    assert fields["source_family_id"] == "benchmark"
    assert fields["frame_id"] == "benchmark__frame_0001"
    assert fields["captured_at"] == ""  # not invented


# ------------------------------------------------------ config + adapter CLI
def test_happy_path_config_exports_contract_valid_label(tmp_path):
    review = make_review(tmp_path)
    config = build_conversion_config(
        review,
        issue_evidence=gui_evidence(),
        target=gui_target(),
        review_ids=["benchmark__frame_0001"],
        captured_at=CAPTURED_AT,
    )
    assert config["release_record_id"] == "cam-release-benchmark__frame_0001"
    assert config["source_family_id"] == "benchmark"
    # GUI exports live human review only; admission stays a downstream step.
    assert config["origin"] == "human_review"
    assert config["human_gold"] is False
    assert config["release_admissible"] is False

    out = tmp_path / "envelope.json"
    converted = run_adapter(
        "convert",
        "--review", str(write_json(tmp_path / "review.json", review)),
        "--config", str(write_json(tmp_path / "config.json", config)),
        "--out", str(out),
    )
    assert converted.returncode == 0, converted.stderr
    assert "EXPORTED" in converted.stdout
    envelope = json.loads(out.read_text(encoding="utf-8"))
    assert envelope["raw_opinion"]["text"] == "лампа справа отвлекает"
    assert envelope["release_label"]["record_id"] == "cam-release-benchmark__frame_0001"

    validated = run_adapter("validate", "--label", str(out))
    assert validated.returncode == 0, validated.stdout
    assert "RELEASE LABEL VALID" in validated.stdout


def test_missing_raw_opinion_refuses_before_the_adapter(tmp_path):
    # The envelope stores the annotator's raw opinion beside the label; a
    # note-less review must be refused by the builder, not by the subprocess.
    review = make_review(tmp_path, notes="   ")
    with pytest.raises(ReleaseConfigError, match="raw_opinion"):
        build_conversion_config(
            review,
            issue_evidence=gui_evidence(),
            target=gui_target(),
            captured_at=CAPTURED_AT,
        )


def test_missing_severity_refuses_before_anything_is_written(tmp_path):
    review = make_review(tmp_path)
    evidence = gui_evidence()
    evidence["background_competes_with_subject"]["severity"] = ""
    with pytest.raises(ReleaseConfigError, match="severity"):
        build_conversion_config(
            review,
            issue_evidence=evidence,
            target=gui_target(),
            captured_at=CAPTURED_AT,
        )


def test_missing_evidence_ref_refuses(tmp_path):
    review = make_review(tmp_path)
    evidence = gui_evidence()
    evidence["background_competes_with_subject"]["evidence_refs"] = []
    with pytest.raises(ReleaseConfigError, match="evidence"):
        build_conversion_config(
            review,
            issue_evidence=evidence,
            target=gui_target(),
            captured_at=CAPTURED_AT,
        )


def test_adapter_rejects_evidenceless_config_and_writes_nothing(tmp_path):
    # Boundary: even bypassing the GUI builder, the adapter CLI refuses a
    # present issue without severity/confidence/evidence and leaves no output.
    review = make_review(tmp_path)
    out = tmp_path / "must-not-exist.json"
    bad_config = {
        "release_record_id": "cam-release-benchmark__frame_0001",
        "source_family_id": "benchmark",
        "frame_id": "benchmark__frame_0001",
        "captured_at": CAPTURED_AT,
        "issue_evidence": {},
        "target": gui_target(),
        "review_ids": ["benchmark__frame_0001"],
    }
    converted = run_adapter(
        "convert",
        "--review", str(write_json(tmp_path / "review.json", review)),
        "--config", str(write_json(tmp_path / "bad-config.json", bad_config)),
        "--out", str(out),
    )
    assert converted.returncode == 1
    assert "CONVERSION REJECTED" in converted.stderr
    assert not out.exists()


def test_incomplete_target_and_missing_captured_at_refuse(tmp_path):
    review = make_review(tmp_path)
    with pytest.raises(ReleaseConfigError, match="identity_status"):
        build_conversion_config(
            review,
            issue_evidence=gui_evidence(),
            target=gui_target(identity_status=""),
            captured_at=CAPTURED_AT,
        )
    with pytest.raises(ReleaseConfigError, match="movability"):
        build_conversion_config(
            review,
            issue_evidence=gui_evidence(),
            target=gui_target(movability_permission=""),
            captured_at=CAPTURED_AT,
        )
    with pytest.raises(ReleaseConfigError, match="captured_at"):
        build_conversion_config(
            review,
            issue_evidence=gui_evidence(),
            target=gui_target(),
            captured_at="  ",
        )


def test_multiple_corrective_actions_require_explicit_choice(tmp_path):
    review = make_review(
        tmp_path, actions=["move_object_left", "move_object_right"]
    )
    with pytest.raises(ReleaseConfigError, match="corrective_action_id"):
        build_conversion_config(
            review,
            issue_evidence=gui_evidence(),
            target=gui_target(),
            captured_at=CAPTURED_AT,
        )
    config = build_conversion_config(
        review,
        issue_evidence=gui_evidence(),
        target=gui_target(),
        corrective_action_id="move_object_right",
        captured_at=CAPTURED_AT,
    )
    assert config["corrective_action_id"] == "move_object_right"


def test_unsure_review_requires_explicit_abstention_reason_and_exports(tmp_path):
    review = make_review(
        tmp_path,
        beauty="unrated",
        improvement_needed=None,
        unsure=True,
        issues=[],
        actions=[],
        notes="не уверен, что тут не так",
    )
    with pytest.raises(ReleaseConfigError, match="abstention"):
        build_conversion_config(
            review,
            target=gui_target(identity_status="unknown", rect=None,
                              movability_status="unknown",
                              movability_permission="unknown"),
            captured_at=CAPTURED_AT,
        )
    config = build_conversion_config(
        review,
        target=gui_target(identity_status="unknown", rect=None,
                          movability_status="unknown",
                          movability_permission="unknown"),
        abstention_reason="ambiguous_subject",
        captured_at=CAPTURED_AT,
    )
    assert config["abstention_reasons"] == ["ambiguous_subject"]
    assert "issue_evidence" not in config

    out = tmp_path / "abstain.json"
    converted = run_adapter(
        "convert",
        "--review", str(write_json(tmp_path / "review.json", review)),
        "--config", str(write_json(tmp_path / "config.json", config)),
        "--out", str(out),
    )
    assert converted.returncode == 0, converted.stderr
    validated = run_adapter("validate", "--label", str(out))
    assert validated.returncode == 0, validated.stdout
    assert "RELEASE LABEL VALID" in validated.stdout


def test_good_review_exports_keep_without_issue_evidence(tmp_path):
    review = make_review(
        tmp_path,
        beauty="beautiful",
        improvement_needed=False,
        issues=[],
        actions=["keep_current_setup"],
        regions=[{"role": "subject", "rect": [0.2, 0.2, 0.4, 0.5]}],
        notes="всё устраивает",
    )
    config = build_conversion_config(
        review,
        target=gui_target(entity_ref="scene-1", kind="object", role="context"),
        captured_at=CAPTURED_AT,
    )
    assert "issue_evidence" not in config
    assert config["target"]["role"] == "context"

    out = tmp_path / "good.json"
    converted = run_adapter(
        "convert",
        "--review", str(write_json(tmp_path / "review.json", review)),
        "--config", str(write_json(tmp_path / "config.json", config)),
        "--out", str(out),
    )
    assert converted.returncode == 0, converted.stderr
    validated = run_adapter("validate", "--label", str(out))
    assert validated.returncode == 0, validated.stdout
    assert "RELEASE LABEL VALID" in validated.stdout
