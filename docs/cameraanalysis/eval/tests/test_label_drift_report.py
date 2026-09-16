from __future__ import annotations

import hashlib
import json
from pathlib import Path

from label_drift_report import build_drift_report, render_markdown, verify_label_image_bindings


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _label(
    record_id: str,
    filename: str,
    *,
    quality: str,
    expected: list[str],
    forbidden: list[str],
    sha256: str,
    confidence_target: str = "high",
) -> dict:
    return {
        "record_id": record_id,
        "filename": filename,
        "image_path": f"images/{filename}",
        "source_bucket": "unit_fixture",
        "source_dataset": "unit_fixture",
        "width": 8,
        "height": 8,
        "sha256": sha256,
        "quality_label": quality,
        "scene_type": "fixture_scene",
        "primary_subject": "fixture subject",
        "positive_factors": [],
        "problems": [],
        "technical_quality_defects": [],
        "expected_live_tip": "fixture live tip",
        "expected_pause_summary": "fixture pause summary",
        "expected_semantic_actions": expected,
        "future_needed_actions": [],
        "forbidden_actions": forbidden,
        "confidence_target": confidence_target,
        "demo_priority": False,
        "eval_tags": ["unit_fixture"],
        "review_status": "test_fixture",
        "label_source": "unit_test",
    }


def _output(record_id: str, filename: str, actions: list[str], confidence: float = 0.9) -> dict:
    return {
        "record_id": record_id,
        "filename": filename,
        "mode": "both",
        "shown": True,
        "live_tip": "tip",
        "pause_summary": "summary",
        "semantic_actions": actions,
        "future_actions": [],
        "confidence": confidence,
        "source": "unit_fixture",
        "runtime_claim": "test_fixture",
        "trace_ids": [],
    }


def _write_fixture(tmp_path: Path) -> tuple[Path, Path, Path]:
    images_root = tmp_path / "images"
    images_root.mkdir()
    records = []
    outputs = []
    payloads = {
        "001.jpg": b"good-keep",
        "002.jpg": b"good-overcorrect",
        "003.jpg": b"bad-false-keep",
        "004.jpg": b"mixed-silence",
    }
    for filename, payload in payloads.items():
        (images_root / filename).write_bytes(payload)
    records.append(
        _label(
            "r_good_keep",
            "001.jpg",
            quality="good",
            expected=["keep_current_setup"],
            forbidden=["add_front_fill_light", "step_closer"],
            sha256=_sha256(payloads["001.jpg"]),
        )
    )
    records.append(
        _label(
            "r_good_overcorrect",
            "002.jpg",
            quality="good",
            expected=["keep_current_setup"],
            forbidden=["add_front_fill_light"],
            sha256=_sha256(payloads["002.jpg"]),
        )
    )
    records.append(
        _label(
            "r_bad_false_keep",
            "003.jpg",
            quality="bad",
            expected=["step_back"],
            forbidden=["keep_current_setup"],
            sha256=_sha256(payloads["003.jpg"]),
        )
    )
    records.append(
        _label(
            "r_mixed_silence",
            "004.jpg",
            quality="mixed",
            expected=["simplify_background"],
            forbidden=["keep_current_setup"],
            sha256="0" * 64,
        )
    )
    outputs.append(_output("r_good_keep", "001.jpg", ["keep_current_setup"]))
    outputs.append(_output("r_good_overcorrect", "002.jpg", ["add_front_fill_light"]))
    outputs.append(_output("r_bad_false_keep", "003.jpg", ["keep_current_setup"]))
    outputs.append(_output("r_mixed_silence", "004.jpg", []))

    labels_path = tmp_path / "labels.jsonl"
    outputs_path = tmp_path / "outputs.jsonl"
    labels_path.write_text(
        "\n".join(json.dumps(row) for row in records) + "\n", encoding="utf-8"
    )
    outputs_path.write_text(
        "\n".join(json.dumps(row) for row in outputs) + "\n", encoding="utf-8"
    )
    return labels_path, outputs_path, images_root


def test_verify_label_image_bindings_separates_mismatch(tmp_path: Path) -> None:
    labels_path, _, images_root = _write_fixture(tmp_path)
    records = [json.loads(line) for line in labels_path.read_text().splitlines()]
    verified, unverified = verify_label_image_bindings(records, images_root)
    assert verified == ["r_good_keep", "r_good_overcorrect", "r_bad_false_keep"]
    assert [entry["record_id"] for entry in unverified] == ["r_mixed_silence"]
    assert unverified[0]["reason"] == "sha256_mismatch"


def test_drift_report_counts_dispositions_and_flags(tmp_path: Path) -> None:
    labels_path, outputs_path, images_root = _write_fixture(tmp_path)
    report = build_drift_report(
        labels_path, outputs_path, images_root, candidate_id="unit_fixture"
    )

    full = report["full_set"]
    assert full["set_metrics"]["record_count"] == 4
    assert full["drift"]["strict_drift_count"] == 3
    assert full["drift"]["by_disposition"] == {"keep": 2, "correct": 1, "silence": 1}
    assert full["drift"]["good_frame_overcorrection_count"] == 1
    assert full["drift"]["false_keep_on_non_good_count"] == 1
    assert full["drift"]["silence_on_non_good_count"] == 1
    assert full["drift"]["forbidden_hit_records"] == [
        {"record_id": "r_bad_false_keep", "actions": ["keep_current_setup"]},
        {"record_id": "r_good_overcorrect", "actions": ["add_front_fill_light"]},
    ]
    assert full["set_metrics"]["good_frame_preservation_rate"] == 0.5
    assert full["set_metrics"]["forbidden_action_violation_rate"] == 0.5

    verified = report["verified_binding_subset"]
    assert verified["set_metrics"]["record_count"] == 3
    assert verified["drift"]["false_keep_on_non_good_count"] == 1
    assert verified["drift"]["silence_on_non_good_count"] == 0
    assert report["integrity"]["verified_binding_records"] == 3
    assert report["integrity"]["unverified_binding_records"] == 1


def test_drift_report_is_deterministic_and_pins_input_hashes(tmp_path: Path) -> None:
    labels_path, outputs_path, images_root = _write_fixture(tmp_path)
    first = build_drift_report(labels_path, outputs_path, images_root, candidate_id="unit_fixture")
    second = build_drift_report(labels_path, outputs_path, images_root, candidate_id="unit_fixture")
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)
    assert first["inputs"]["labels_sha256"] == _sha256(labels_path.read_bytes())
    assert first["inputs"]["outputs_sha256"] == _sha256(outputs_path.read_bytes())


def test_render_markdown_lists_drifted_records(tmp_path: Path) -> None:
    labels_path, outputs_path, images_root = _write_fixture(tmp_path)
    report = build_drift_report(labels_path, outputs_path, images_root, candidate_id="unit_fixture")
    markdown = render_markdown(report)
    assert "## Byte-verified subset" in markdown
    assert "r_good_overcorrect" in markdown
    assert "good_overcorrection" in markdown
    assert "forbidden:keep_current_setup" in markdown
    assert "r_good_keep" not in markdown
