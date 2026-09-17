from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("camera_gate_under_test", ROOT / "scripts/run_device_benchmark.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
EVAL_ROOT = ROOT / "docs/cameraanalysis/eval"
sys.path.insert(0, str(EVAL_ROOT))
from semantic_output_schema import build_oracle_candidate_outputs, score_semantic_candidate_outputs
sys.path.remove(str(EVAL_ROOT))


@pytest.fixture(autouse=True)
def no_native_or_network_calls(monkeypatch):
    def forbidden(*args, **kwargs):
        raise AssertionError("camera gate controls must not execute commands or make network requests")
    monkeypatch.setattr(subprocess, "run", forbidden)
    monkeypatch.setattr(subprocess, "Popen", forbidden)
    monkeypatch.setattr(socket, "socket", forbidden)
    monkeypatch.setattr(socket, "create_connection", forbidden)


def camera_report(tmp_path: Path, *, synthetic_hits: int = 5, forbidden_count: int = 0):
    """Use the real semantic exporter with explicitly synthetic label/output cases."""
    assert 0 <= synthetic_hits <= 5 and 0 <= forbidden_count <= 5 - synthetic_hits
    cases = []
    for index in range(25):
        good = index < 20
        cases.append({
            "record_id": f"gate-fixture-{index}", "filename": f"fixture-{index}.jpg",
            "quality_label": "good" if good else "bad",
            "source_bucket": "good_fixture" if good else "synthetic_bad_paired_apple_tv_press",
            "demo_priority": False, "tags": ["synthetic_gate_control"],
            "expected_actions": ["keep_current_setup"] if good else ["shift_frame_left"],
            "future_actions": [], "forbidden_actions": ["shift_frame_right"],
            "confidence_target": "high", "expected_live_text_class": "fixture_text",
            "expected_pause_summary": "Synthetic gate control; no model or human evaluation.",
        })
    outputs = build_oracle_candidate_outputs(cases)
    for index, output in enumerate(outputs[20:]):
        if index >= synthetic_hits:
            output["semantic_actions"] = ["shift_frame_right"] if index >= 5 - forbidden_count else []
    scored = score_semantic_candidate_outputs(cases, outputs)
    bucket_path = tmp_path / "bucket_metrics.json"
    bucket_path.write_text(json.dumps({"bucket_metrics": scored["bucket_metrics"]}))
    return {"set_metrics": scored["set_metrics"], "_bucket_metrics_path": str(bucket_path)}


def rewrite_buckets(report, mutate):
    path = Path(report["_bucket_metrics_path"])
    payload = json.loads(path.read_text())
    mutate(payload)
    path.write_text(json.dumps(payload))


def test_real_zero_violation_rate_passes_with_nonempty_actual_exporter_schema(tmp_path):
    report = camera_report(tmp_path)
    assert report["set_metrics"]["record_count"] == 25
    assert report["set_metrics"]["forbidden_action_violation_rate"] == 0.0
    buckets = json.loads(Path(report["_bucket_metrics_path"]).read_text())["bucket_metrics"]["source_bucket"]
    assert sum(bucket["record_count"] for bucket in buckets.values()) == 25
    assert buckets["synthetic_bad_paired_apple_tv_press"]["record_count"] == 5
    gate = MODULE.make_camera_gate("full", report)
    assert gate["checks"]["forbidden_action_violation_rate"] is True
    assert gate["status"] == "pass"


@pytest.mark.parametrize("hits,forbidden,expected", [(3, 2, True), (2, 3, False)])
def test_forbidden_rate_boundary_uses_real_exported_counts(tmp_path, hits, forbidden, expected):
    report = camera_report(tmp_path, synthetic_hits=hits, forbidden_count=forbidden)
    assert report["set_metrics"]["forbidden_action_violation_rate"] == forbidden / 25
    gate = MODULE.make_camera_gate("full", report)
    assert gate["checks"]["forbidden_action_violation_rate"] is expected
    assert gate["status"] == ("pass" if expected else "fail")


@pytest.mark.parametrize("hits,expected", [(2, True), (1, False)])
def test_synthetic_threshold_reads_the_actual_nested_source_bucket(tmp_path, hits, expected):
    # One measured forbidden action gives .04, isolating the bucket lookup from
    # the independent zero-rate regression; overall pass remains >= .80.
    report = camera_report(tmp_path, synthetic_hits=hits, forbidden_count=1)
    assert report["set_metrics"]["pass_rate"] >= .80
    gate = MODULE.make_camera_gate("full", report)
    assert gate["checks"]["synthetic_bad_paired_apple_tv_press_pass_rate"] is expected
    assert gate["status"] == ("pass" if expected else "fail")


@pytest.mark.parametrize("field", ["pass_rate", "forbidden_action_violation_rate", "good_frame_preservation_rate"])
@pytest.mark.parametrize("value", [None, False, float("nan"), float("inf"), -.1, "0"])
def test_unknown_or_invalid_metric_cannot_pass_full_gate(tmp_path, field, value):
    report = camera_report(tmp_path, synthetic_hits=4, forbidden_count=1)
    report["set_metrics"][field] = value
    gate = MODULE.make_camera_gate("full", report)
    assert gate["checks"][field] is False
    assert gate["status"] == "fail"


@pytest.mark.parametrize("case", ["missing_file", "missing_source_bucket", "obsolete_flat_layout",
                                  "zero_total_count", "missing_synthetic_bucket", "zero_synthetic_count",
                                  "inconsistent_source_counts"])
def test_full_gate_requires_nonempty_consistent_source_bucket_coverage(tmp_path, case):
    report = camera_report(tmp_path, synthetic_hits=4, forbidden_count=1)
    if case == "missing_file":
        Path(report["_bucket_metrics_path"]).unlink()
    elif case == "zero_total_count":
        report["set_metrics"]["record_count"] = 0
    else:
        def mutate(payload):
            buckets = payload["bucket_metrics"]
            if case == "missing_source_bucket":
                buckets.pop("source_bucket")
            elif case == "obsolete_flat_layout":
                payload["bucket_metrics"] = buckets["source_bucket"]
            elif case == "missing_synthetic_bucket":
                buckets["source_bucket"].pop("synthetic_bad_paired_apple_tv_press")
            elif case == "zero_synthetic_count":
                buckets["source_bucket"]["synthetic_bad_paired_apple_tv_press"]["record_count"] = 0
            else:
                buckets["source_bucket"]["good_fixture"]["record_count"] += 1
        rewrite_buckets(report, mutate)
    gate = MODULE.make_camera_gate("full", report)
    assert gate["status"] == "fail"
    assert gate["notes"]


@pytest.mark.parametrize("hits", [0, 5])
def test_quick_results_never_become_a_product_quality_gate(tmp_path, hits):
    gate = MODULE.make_camera_gate("quick", camera_report(tmp_path, synthetic_hits=hits))
    assert gate["status"] == "sample_only"


def test_missing_camera_postprocess_is_not_a_pass():
    assert MODULE.make_camera_gate("full", None)["status"] == "missing"
