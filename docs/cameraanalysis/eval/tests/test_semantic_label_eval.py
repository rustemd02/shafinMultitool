from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from semantic_label_adapter import (
    SemanticLabelValidationError,
    load_semantic_label_records,
    normalize_semantic_label_cases,
)
from semantic_output_schema import (
    build_bad_candidate_outputs,
    build_oracle_candidate_outputs,
    build_proxy_current_outputs,
    score_semantic_candidate_outputs,
)


def _record(
    record_id: str = "ca_img_001",
    filename: str = "001.jpg",
    quality_label: str = "good",
    expected_actions: list[str] | None = None,
    future_actions: list[str] | None = None,
    forbidden_actions: list[str] | None = None,
    technical_defects: list[str] | None = None,
    eval_tags: list[str] | None = None,
    confidence_target: str | None = None,
) -> dict:
    return {
        "record_id": record_id,
        "filename": filename,
        "image_path": f"docs/cameraanalysis/dataset/inbox/images/{filename}",
        "source_bucket": "curated_user_inbox",
        "source_dataset": "unit_test",
        "quality_label": quality_label,
        "scene_type": "unit_test_scene",
        "primary_subject": "subject",
        "positive_factors": ["clear subject"] if quality_label == "good" else [],
        "problems": [] if quality_label == "good" else ["problem"],
        "technical_quality_defects": technical_defects or [],
        "expected_live_tip": "Кадр читается хорошо." if quality_label == "good" else "Нужна правка.",
        "expected_pause_summary": "Объяснение кадра.",
        "expected_semantic_actions": expected_actions if expected_actions is not None else ["keep_current_setup"],
        "future_needed_actions": future_actions or [],
        "forbidden_actions": forbidden_actions or [],
        "confidence_target": confidence_target or ("high" if quality_label == "good" else "medium"),
        "demo_priority": quality_label == "good",
        "eval_tags": eval_tags or ["unit"],
        "review_status": "ai_first_pass_needs_human_review",
    }


def test_semantic_label_loader_normalizes_required_projection(tmp_path: Path) -> None:
    image_dir = tmp_path / "images"
    image_dir.mkdir()
    (image_dir / "001.jpg").write_bytes(b"fake")
    labels_path = tmp_path / "semantic_labels.jsonl"
    labels_path.write_text(json.dumps(_record(), ensure_ascii=False) + "\n", encoding="utf-8")

    records = load_semantic_label_records(labels_path, images_dir=image_dir)
    cases = normalize_semantic_label_cases(records)

    assert len(cases) == 1
    assert cases[0]["case_id"] == "ca_img_001"
    assert cases[0]["image_ref"] == "001.jpg"
    assert cases[0]["expected_actions"] == ["keep_current_setup"]
    assert cases[0]["confidence_target"] == "high"


def test_semantic_label_loader_rejects_missing_and_invalid_actions(tmp_path: Path) -> None:
    labels_path = tmp_path / "bad_labels.jsonl"
    row = _record(expected_actions=["invent_new_action"])
    del row["expected_live_tip"]
    labels_path.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")

    with pytest.raises(SemanticLabelValidationError) as exc:
        load_semantic_label_records(labels_path)

    message = str(exc.value)
    assert "expected_live_tip" in message
    assert "invent_new_action" in message


def test_semantic_scorer_reports_good_overcorrection_and_technical_overreach() -> None:
    cases = normalize_semantic_label_cases(
        [
            _record(
                record_id="good_001",
                filename="001.jpg",
                quality_label="good",
                expected_actions=["keep_current_setup"],
                forbidden_actions=["level_horizon", "step_closer"],
                eval_tags=["avoid_overcorrection"],
            ),
            _record(
                record_id="bad_001",
                filename="002.jpg",
                quality_label="bad",
                expected_actions=[],
                future_actions=["stabilize_camera"],
                forbidden_actions=["shift_frame_left", "shift_frame_right"],
                technical_defects=["motion_blur"],
                eval_tags=["motion_blur"],
            ),
        ]
    )
    outputs = [
        {
            "record_id": "good_001",
            "filename": "001.jpg",
            "mode": "live",
            "shown": True,
            "live_tip": "Камеру ровнее.",
            "pause_summary": None,
            "semantic_actions": ["level_horizon"],
            "confidence": 0.9,
            "source": "unit_bad",
            "runtime_claim": "test_fixture",
            "trace_ids": [],
        },
        {
            "record_id": "bad_001",
            "filename": "002.jpg",
            "mode": "live",
            "shown": True,
            "live_tip": "Камеру чуть правее.",
            "pause_summary": None,
            "semantic_actions": ["shift_frame_right"],
            "confidence": 0.7,
            "source": "unit_bad",
            "runtime_claim": "test_fixture",
            "trace_ids": [],
        },
    ]

    report = score_semantic_candidate_outputs(cases, outputs)

    assert report["set_metrics"]["record_count"] == 2
    assert report["set_metrics"]["forbidden_action_violation_rate"] == 1.0
    assert report["set_metrics"]["good_frame_preservation_rate"] == 0.0
    assert report["set_metrics"]["technical_failure_gate_rate"] == 0.0
    failures = {failure for row in report["case_results"] for failure in row["failures"]}
    assert "good_frame_overcorrection" in failures
    assert "semantic_overreach_on_technical_failure" in failures


def test_oracle_outputs_pass_real_semantic_labels() -> None:
    repo_root = Path(__file__).resolve().parents[4]
    labels_path = repo_root / "docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl"
    image_dir = repo_root / "docs/cameraanalysis/dataset/inbox/images"

    records = load_semantic_label_records(labels_path, images_dir=image_dir)
    cases = normalize_semantic_label_cases(records)
    outputs = build_oracle_candidate_outputs(cases)
    report = score_semantic_candidate_outputs(cases, outputs)

    assert report["set_metrics"]["record_count"] == 107
    assert report["set_metrics"]["expected_action_hit_rate"] == 1.0
    assert report["set_metrics"]["forbidden_action_violation_rate"] == 0.0
    assert report["set_metrics"]["good_frame_preservation_rate"] == 1.0


def test_bad_candidate_fails_real_semantic_labels() -> None:
    repo_root = Path(__file__).resolve().parents[4]
    labels_path = repo_root / "docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl"
    records = load_semantic_label_records(labels_path)
    cases = normalize_semantic_label_cases(records)

    report = score_semantic_candidate_outputs(cases, build_bad_candidate_outputs(cases))

    assert report["set_metrics"]["forbidden_action_violation_rate"] > 0.0
    assert report["set_metrics"]["good_frame_preservation_rate"] < 1.0
    assert report["set_metrics"]["demo_priority_pass_rate"] < 1.0


def test_proxy_current_outputs_are_explicitly_not_real_runtime_claim() -> None:
    cases = normalize_semantic_label_cases(
        [
            _record(
                record_id="technical_001",
                filename="001.jpg",
                quality_label="bad",
                expected_actions=[],
                future_actions=["refocus_subject"],
                technical_defects=["defocus"],
                eval_tags=["defocus"],
            )
        ]
    )

    output = build_proxy_current_outputs(cases)[0]

    assert output["source"] == "manual_proxy_current_limitations"
    assert output["runtime_claim"] == "not_real_runtime"
    assert output["semantic_actions"] == []
    assert output["shown"] is False


def test_candidate_output_rejects_invalid_runtime_claim() -> None:
    cases = normalize_semantic_label_cases([_record()])
    output = build_oracle_candidate_outputs(cases)[0]
    output["runtime_claim"] = "real_because_i_said_so"

    with pytest.raises(Exception) as exc:
        score_semantic_candidate_outputs(cases, [output])

    assert "runtime_claim" in str(exc.value)


def test_candidate_output_allows_live_and_pause_rows_for_same_record() -> None:
    cases = normalize_semantic_label_cases(
        [
            _record(
                quality_label="mixed",
                expected_actions=["add_front_fill_light", "simplify_background"],
                forbidden_actions=["level_horizon"],
            )
        ]
    )
    outputs = [
        {
            "record_id": "ca_img_001",
            "filename": "001.jpg",
            "mode": "live",
            "shown": True,
            "live_tip": "Добавь мягкий свет на лицо.",
            "pause_summary": None,
            "semantic_actions": ["add_front_fill_light"],
            "future_actions": [],
            "confidence": 0.7,
            "source": "swift_still_image_replay",
            "runtime_claim": "real_runtime_still_replay",
            "trace_ids": ["trace_live"],
        },
        {
            "record_id": "ca_img_001",
            "filename": "001.jpg",
            "mode": "pause",
            "shown": True,
            "live_tip": None,
            "pause_summary": "Лицу нужен свет, а фон спорит с героем.",
            "semantic_actions": ["simplify_background"],
            "future_actions": [],
            "confidence": 0.72,
            "source": "swift_still_image_replay",
            "runtime_claim": "real_runtime_still_replay",
            "trace_ids": ["trace_pause"],
        },
    ]

    report = score_semantic_candidate_outputs(cases, outputs)

    row = report["case_results"][0]
    assert row["candidate_actions"] == ["add_front_fill_light", "simplify_background"]
    assert row["runtime_claim"] == "real_runtime_still_replay"
    assert row["passed"] is True


def test_scorer_ignores_hidden_row_confidence_when_merging_modes() -> None:
    cases = normalize_semantic_label_cases(
        [
            _record(
                quality_label="mixed",
                expected_actions=["add_front_fill_light"],
            )
        ]
    )
    outputs = [
        {
            "record_id": "ca_img_001",
            "filename": "001.jpg",
            "mode": "live",
            "shown": False,
            "live_tip": None,
            "pause_summary": None,
            "semantic_actions": [],
            "future_actions": ["increase_exposure"],
            "confidence": 0.95,
            "source": "swift_still_image_replay",
            "runtime_claim": "real_runtime_still_replay",
            "trace_ids": [],
        },
        {
            "record_id": "ca_img_001",
            "filename": "001.jpg",
            "mode": "pause",
            "shown": True,
            "live_tip": None,
            "pause_summary": "Нужно добавить свет на лицо.",
            "semantic_actions": ["add_front_fill_light"],
            "future_actions": ["increase_exposure"],
            "confidence": 0.64,
            "source": "swift_still_image_replay",
            "runtime_claim": "real_runtime_still_replay",
            "trace_ids": [],
        },
    ]

    report = score_semantic_candidate_outputs(cases, outputs)

    row = report["case_results"][0]
    assert row["metrics"]["confidence_band_match"] == 1.0
    assert row["passed"] is True


def test_scorer_prefers_semantic_row_confidence_when_merging_modes() -> None:
    cases = normalize_semantic_label_cases(
        [
            _record(
                quality_label="good",
                expected_actions=["keep_current_setup"],
                confidence_target="medium",
            )
        ]
    )
    outputs = [
        {
            "record_id": "ca_img_001",
            "filename": "001.jpg",
            "mode": "live",
            "shown": True,
            "live_tip": "Кадр читается стабильно.",
            "pause_summary": None,
            "semantic_actions": [],
            "future_actions": ["stabilize_camera"],
            "confidence": 0.96,
            "source": "swift_still_image_replay",
            "runtime_claim": "real_runtime_still_replay",
            "trace_ids": ["trace_live"],
        },
        {
            "record_id": "ca_img_001",
            "filename": "001.jpg",
            "mode": "pause",
            "shown": True,
            "live_tip": None,
            "pause_summary": "Кадр читается стабильно.",
            "semantic_actions": ["keep_current_setup"],
            "future_actions": ["stabilize_camera"],
            "confidence": 0.70,
            "source": "swift_still_image_replay",
            "runtime_claim": "real_runtime_still_replay",
            "trace_ids": ["trace_pause"],
        },
    ]

    report = score_semantic_candidate_outputs(cases, outputs)

    row = report["case_results"][0]
    assert row["candidate_actions"] == ["keep_current_setup"]
    assert row["metrics"]["confidence_band_match"] == 1.0
    assert row["passed"] is True


def test_run_semantic_label_eval_generates_required_artifacts(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[4]
    script = repo_root / "docs/cameraanalysis/eval/run_semantic_label_eval.py"
    labels_path = repo_root / "docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl"

    subprocess.run(
        [
            sys.executable,
            str(script),
            "--labels",
            str(labels_path),
            "--outputs",
            str(tmp_path),
            "--candidate",
            "oracle_projection",
        ],
        check=True,
    )

    for name in (
        "case_results.jsonl",
        "set_metrics.json",
        "bucket_metrics.json",
        "candidate_outputs.jsonl",
        "semantic_eval_summary.md",
    ):
        assert (tmp_path / name).exists(), f"missing {name}"

    metrics = json.loads((tmp_path / "set_metrics.json").read_text(encoding="utf-8"))
    assert metrics["candidate_id"] == "oracle_projection"
    assert metrics["set_metrics"]["record_count"] == 107
