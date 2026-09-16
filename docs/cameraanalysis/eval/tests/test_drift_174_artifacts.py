from __future__ import annotations

import hashlib
import json
from pathlib import Path

from label_drift_report import build_drift_report


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = Path(__file__).resolve().parents[1] / "camera-baseline-v0" / "drift-174"
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)
IMAGES_ROOT = (
    REPO_ROOT / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images"
)
RAW_ROWS = LANE / "m4-001-fullruntime-174-drift-r1.jsonl"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_committed_drift_lane_artifacts_exist() -> None:
    for name in (
        "manifest.json",
        "swift-replay-receipt-174.json",
        "m4-001-fullruntime-174-drift-r1.jsonl",
        "label-drift-report.json",
        "label-drift-report.md",
        "drift-rows.jsonl",
        "scored/set_metrics.json",
        "scored/bucket_metrics.json",
        "scored/case_results.jsonl",
        "scored/candidate_outputs.jsonl",
        "scored/semantic_eval_summary.md",
    ):
        assert (LANE / name).is_file(), name


def _normalize_paths(report: dict) -> dict:
    inputs = dict(report["inputs"])
    for field in ("labels_path", "outputs_path", "images_root"):
        value = Path(inputs[field])
        inputs[field] = (
            str(value.relative_to(REPO_ROOT)) if value.is_absolute() else str(value)
        )
    normalized = dict(report)
    normalized["inputs"] = inputs
    return normalized


def test_committed_report_reproduces_from_committed_inputs() -> None:
    committed = json.loads((LANE / "label-drift-report.json").read_text(encoding="utf-8"))
    recomputed = build_drift_report(
        LABELS, RAW_ROWS, IMAGES_ROOT, candidate_id="m4-001-fullruntime-174-drift-r1"
    )
    assert json.dumps(_normalize_paths(recomputed), sort_keys=True) == json.dumps(
        _normalize_paths(committed), sort_keys=True
    )


def test_manifest_metrics_match_scored_artifacts() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    set_metrics = json.loads((LANE / "scored/set_metrics.json").read_text(encoding="utf-8"))
    assert manifest["metrics"]["full_174"]["set_metrics"] == set_metrics["set_metrics"]
    assert set_metrics["runtime_claim"] == "real_runtime_still_replay"
    assert set_metrics["set_metrics"]["record_count"] == 174


def test_manifest_artifact_hashes_match_files() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"], "manifest must pin lane artifacts"
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert _sha256(path) == artifact["sha256"], artifact["path"]
        assert path.stat().st_size == artifact["bytes"], artifact["path"]


HISTORICAL_ROWS = (
    REPO_ROOT
    / "docs/cameraanalysis/eval/out_semantic_real_runtime_v2_regen_bad_v1/candidate_outputs_raw.jsonl"
)
HISTORICAL_METRICS = (
    REPO_ROOT
    / "docs/cameraanalysis/eval/out_semantic_real_runtime_v2_regen_bad_v1/set_metrics.json"
)


def _rows_by_record(path: Path) -> dict[str, dict[str, dict]]:
    grouped: dict[str, dict[str, dict]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        grouped.setdefault(row["record_id"], {})[row.get("mode")] = row
    return grouped


def test_historical_crosscheck_matches_committed_row_files() -> None:
    import hashlib

    cross = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))["historical_crosscheck"]
    historical = _rows_by_record(HISTORICAL_ROWS)
    current = _rows_by_record(RAW_ROWS)
    labels = {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }

    changed = keep_to_correct = changed_good = 0
    object_count = confidence = aesthetic_same = 0
    for record_id, label in labels.items():
        before = set(historical[record_id]["pause"].get("semantic_actions") or [])
        after = set(current[record_id]["pause"].get("semantic_actions") or [])
        if before != after:
            changed += 1
            if label["quality_label"] == "good":
                changed_good += 1
            if before == {"keep_current_setup"} and after and after != {"keep_current_setup"}:
                keep_to_correct += 1
        before_features = historical[record_id]["pause"].get("debug_numeric_features", {})
        after_features = current[record_id]["pause"].get("debug_numeric_features", {})
        if before_features.get("object_count") != after_features.get("object_count"):
            object_count += 1
        if abs(
            float(historical[record_id]["pause"].get("confidence", 0.0))
            - float(current[record_id]["pause"].get("confidence", 0.0))
        ) > 1e-9:
            confidence += 1
        if before_features.get("aesthetic_score") == after_features.get("aesthetic_score"):
            aesthetic_same += 1

    assert cross["historical_artifact_sha256"] == hashlib.sha256(HISTORICAL_ROWS.read_bytes()).hexdigest()
    assert cross["pause_rows_with_changed_action_set"] == changed
    assert cross["changed_action_set_on_good_records"] == changed_good
    assert cross["keep_current_setup_to_corrective"] == keep_to_correct
    assert cross["pause_rows_with_changed_object_count"] == object_count
    assert cross["pause_rows_with_changed_confidence"] == confidence
    assert cross["aesthetic_score_identical_records"] == aesthetic_same


def test_regression_localization_matches_committed_row_files() -> None:
    import statistics

    localization = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))[
        "regression_localization"
    ]
    historical = _rows_by_record(HISTORICAL_ROWS)
    current = _rows_by_record(RAW_ROWS)
    labels = {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    flips = [
        record_id
        for record_id in labels
        if set(historical[record_id]["pause"].get("semantic_actions") or [])
        == {"keep_current_setup"}
        and set(current[record_id]["pause"].get("semantic_actions") or [])
        - {"keep_current_setup"}
    ]
    unreadable = sum(
        1
        for record_id in flips
        if historical[record_id]["pause"].get("debug_semantic_labels", {}).get("subject_readable")
        == "true"
        and current[record_id]["pause"].get("debug_semantic_labels", {}).get("subject_readable")
        == "false"
    )
    edge_issue = sum(
        1
        for record_id in flips
        if "subject_too_close_to_edge"
        in (current[record_id]["pause"].get("debug_issue_types") or [])
    )
    edge_delta = statistics.mean(
        current[record_id]["pause"].get("debug_numeric_features", {}).get("edge_pressure", 0.0)
        - historical[record_id]["pause"].get("debug_numeric_features", {}).get("edge_pressure", 0.0)
        for record_id in flips
    )
    object_delta = statistics.mean(
        current[record_id]["pause"].get("debug_numeric_features", {}).get("object_count", 0.0)
        - historical[record_id]["pause"].get("debug_numeric_features", {}).get("object_count", 0.0)
        for record_id in flips
    )
    assert localization["flip_count"] == len(flips)
    assert localization["subject_readable_true_to_false"] == unreadable
    assert localization["subject_too_close_to_edge_on_flips"] == edge_issue
    assert localization["mean_edge_pressure_delta"] == round(edge_delta, 4)
    assert localization["mean_object_count_delta"] == round(object_delta, 4)


def test_quoted_historical_metrics_match_the_committed_artifact() -> None:
    cross = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))["historical_crosscheck"]
    metrics = json.loads(HISTORICAL_METRICS.read_text(encoding="utf-8"))["set_metrics"]
    for name, value in cross["historical_metrics"].items():
        assert metrics[name] == value, name


def test_manifest_records_label_image_binding_split() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    dataset = manifest["datasets"]["pack_174"]
    assert dataset["label_records"] == 174
    assert dataset["image_records_missing"] == 0
    assert dataset["human_gold"] is False
    assert dataset["label_image_sha256_verified"] + dataset["label_image_sha256_unverified"] == 174


def test_pack_labels_extend_the_107_lane_without_contradiction() -> None:
    pack = {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    v1_path = REPO_ROOT / "docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl"
    v1 = [
        json.loads(line)
        for line in v1_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert len(v1) == 107
    compared_fields = (
        "quality_label",
        "expected_semantic_actions",
        "forbidden_actions",
        "confidence_target",
        "future_needed_actions",
        "eval_tags",
        "demo_priority",
        "sha256",
    )
    for record in v1:
        pack_record = pack[record["record_id"]]
        for field in compared_fields:
            assert record.get(field) == pack_record.get(field), (record["record_id"], field)


def test_master_gate_position_is_honest_about_failed_gates() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    position = manifest["master_gate_position"]
    assert position["expected_action_hit_rate"]["meets"] is False
    assert position["forbidden_action_violation_rate"]["meets"] is False
    assert position["good_frame_preservation_rate"]["meets"] is False
