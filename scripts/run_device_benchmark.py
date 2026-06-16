#!/usr/bin/env python3
"""
Run the device benchmark harness on a connected iPhone and collect xcresult attachments.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import threading
from typing import Any
import zipfile


SCENE_ATTACHMENT_ALIASES = {
    "run_manifest.json",
    "device_info.json",
    "perf_samples.jsonl",
    "camera_summary.json",
    "scene_summary.json",
    "combined_summary.json",
    "combined_summary.md",
    "camera_still_rows.jsonl",
    "camera_live_sequence_rows.jsonl",
    "scene_case_results.json",
    "scene_execution_events.jsonl",
    "scene_checkpoint_manifest.jsonl",
}


def normalize_attachment_alias(suggested_name: str) -> str | None:
    if not suggested_name:
        return None
    match = re.match(r"(?P<stem>.+?)_\d+_[0-9A-F-]{36}(?P<ext>\.[^.]+)$", suggested_name)
    candidate = f"{match.group('stem')}{match.group('ext')}" if match else suggested_name
    return candidate if candidate in SCENE_ATTACHMENT_ALIASES else None


def build_config(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "runId": args.run_id,
        "tier": args.tier,
        "enabledModules": args.modules,
        "sceneGeneratorModelPolicy": "explicitOrLatest",
        "sceneGeneratorRuntimePreset": args.scene_runtime_preset,
        "sceneGeneratorExecutionMode": args.scene_execution_mode,
        "sceneGeneratorThermalPolicy": {
            "mode": args.scene_execution_mode,
            "cooldownOnSeriousMs": args.scene_serious_cooldown_ms,
            "cooldownOnCriticalMs": args.scene_critical_cooldown_ms,
            "maxChunkAttempts": args.scene_max_chunk_attempts,
            "checkpointEnabled": args.scene_checkpoint_enabled,
        },
        "cameraResourcePackId": "camera_device_benchmark_pack_v1",
        "sceneResourcePackId": "scene_generator_device_pack_v1",
        "guidedLiveEnabled": args.guided_live,
        "softThresholds": {
            "scenePassRate": args.scene_min_pass_rate,
        },
        "autoStart": True,
        "liveSequenceEnabled": True,
    }


def run_command(command: list[str], env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        env=env,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def run_streaming_command(
    command: list[str],
    env: dict[str, str] | None = None,
    check: bool = True,
    log_path: Path | None = None,
    timeout_seconds: int | None = None,
    append_log: bool = False,
) -> tuple[subprocess.CompletedProcess[str], bool]:
    log_mode = "a" if append_log else "w"
    log_file = log_path.open(log_mode, encoding="utf-8") if log_path is not None else None
    output_lines: list[str] = []
    process = subprocess.Popen(
        command,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )

    def consume_stdout() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            if log_file is not None:
                log_file.write(line)
                log_file.flush()
            output_lines.append(line)

    reader = threading.Thread(target=consume_stdout, daemon=True)
    reader.start()
    timed_out = False
    try:
        return_code = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        return_code = process.wait()
    reader.join()
    if log_file is not None:
        log_file.close()

    stdout = "".join(output_lines)
    completed = subprocess.CompletedProcess(command, return_code, stdout, None)
    if check and return_code != 0:
        raise subprocess.CalledProcessError(return_code, command, output=stdout)
    return completed, timed_out


def maybe_export_attachments(xcresult: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    export = run_command(
        [
            "xcrun",
            "xcresulttool",
            "export",
            "attachments",
            "--path",
            str(xcresult),
            "--output-path",
            str(output_dir),
        ],
        check=False,
    )
    if export.returncode != 0:
        print(export.stdout)
        print("warning: xcresult attachments export failed; inspect the xcresult bundle manually.", file=sys.stderr)


def normalize_exported_attachments(attachments_dir: Path) -> dict[str, str]:
    manifest_path = attachments_dir / "manifest.json"
    if not manifest_path.exists():
        return {}

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        print("warning: could not parse xcresult attachment manifest.json; skipping alias normalization.", file=sys.stderr)
        return {}

    latest_by_alias: dict[str, dict[str, Any]] = {}
    for test_entry in manifest:
        for attachment in test_entry.get("attachments", []):
            alias = normalize_attachment_alias(attachment.get("suggestedHumanReadableName", ""))
            exported_name = attachment.get("exportedFileName")
            if alias is None or not exported_name:
                continue
            current = latest_by_alias.get(alias)
            if current is None or attachment.get("timestamp", 0) >= current.get("timestamp", 0):
                latest_by_alias[alias] = attachment

    normalized: dict[str, str] = {}
    for alias, attachment in latest_by_alias.items():
        source = attachments_dir / attachment["exportedFileName"]
        destination = attachments_dir / alias
        if not source.exists():
            continue
        if source.resolve() != destination.resolve():
            shutil.copyfile(source, destination)
        normalized[alias] = source.name
    return normalized


def maybe_extract_artifacts_zip(attachments_dir: Path, extracted_dir: Path) -> Path | None:
    archive = next(attachments_dir.rglob("artifacts.zip"), None)
    if archive is None:
        return None
    extracted_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(extracted_dir)
    return extracted_dir


def find_first(root: Path, name: str) -> Path | None:
    return next(root.rglob(name), None) if root.exists() else None


def collect_device_diagnostics(device_id: str) -> dict[str, Any]:
    lock_state = run_command(
        ["xcrun", "devicectl", "device", "info", "lockState", "--device", device_id],
        check=False,
    )
    apps = run_command(
        ["xcrun", "devicectl", "device", "info", "apps", "--device", device_id],
        check=False,
    )
    processes = run_command(
        ["xcrun", "devicectl", "device", "info", "processes", "--device", device_id],
        check=False,
    )
    interesting_app_lines = [
        line
        for line in apps.stdout.splitlines()
        if any(token in line.lower() for token in ("shafin", "multitool"))
    ]
    interesting_process_lines = [
        line
        for line in processes.stdout.splitlines()
        if any(token in line.lower() for token in ("shafin", "xctest", "xctrunner", "testrunner"))
    ]
    return {
        "device_id": device_id,
        "lock_state_stdout": lock_state.stdout,
        "installed_app_matches": interesting_app_lines,
        "running_process_matches": interesting_process_lines,
    }


def write_json_artifact(path: Path, payload: dict[str, Any]) -> Path:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def find_xctestrun_file(derived_data_path: Path) -> Path | None:
    candidates = sorted(derived_data_path.rglob("*.xctestrun"))
    return candidates[0] if candidates else None


def patch_xctestrun_environment(source_path: Path, destination_path: Path, injected_environment: dict[str, str]) -> Path:
    payload = plistlib.loads(source_path.read_bytes())
    for configuration in payload.get("TestConfigurations", []):
        for target in configuration.get("TestTargets", []):
            target.setdefault("EnvironmentVariables", {})
            target["EnvironmentVariables"].update(injected_environment)
            target.setdefault("TestingEnvironmentVariables", {})
            target["TestingEnvironmentVariables"].update(injected_environment)
    destination_path.write_bytes(plistlib.dumps(payload))
    return destination_path


def maybe_run_camera_postprocess(repo_root: Path, artifacts_root: Path, tier: str, postprocess_dir: Path) -> Path | None:
    candidate = find_first(artifacts_root, "camera_still_rows.jsonl")
    if candidate is None:
        print("warning: camera_still_rows.jsonl attachment not found; skipping camera postprocess.", file=sys.stderr)
        return None

    labels = repo_root / "shafinMultitool" / "Resources" / "DeviceBenchmark" / "camera_device_benchmark_pack_v1" / (
        "camera_full_labels.jsonl" if tier == "full" else "camera_quick_labels.jsonl"
    )
    postprocess_dir.mkdir(parents=True, exist_ok=True)
    command = [
        sys.executable,
        str(repo_root / "docs" / "cameraanalysis" / "eval" / "run_semantic_label_eval.py"),
        "--labels",
        str(labels),
        "--candidate",
        str(candidate),
        "--outputs",
        str(postprocess_dir),
    ]
    result = run_command(command, check=False)
    if result.returncode != 0:
        print(result.stdout)
        print("warning: camera postprocess failed.", file=sys.stderr)
        return None
    return postprocess_dir / "set_metrics.json"


def load_json_if_exists(path: Path | str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    path = Path(path)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def make_camera_gate(tier: str, camera_eval: dict[str, Any] | None) -> dict[str, Any]:
    if camera_eval is None:
        return {"status": "missing", "checks": {}, "notes": ["camera postprocess missing"]}

    set_metrics = camera_eval.get("set_metrics", {})
    checks = {
        "pass_rate": (set_metrics.get("pass_rate") or 0) >= 0.80,
        "forbidden_action_violation_rate": (set_metrics.get("forbidden_action_violation_rate") or 1) <= 0.08,
        "good_frame_preservation_rate": (set_metrics.get("good_frame_preservation_rate") or 0) >= 0.92,
    }
    bucket_metrics = load_json_if_exists(camera_eval.get("_bucket_metrics_path"))
    synthetic_bucket = None
    if bucket_metrics:
        synthetic_bucket = (
            bucket_metrics.get("bucket_metrics", {})
            .get("synthetic_bad_paired_apple_tv_press", {})
            .get("pass_rate")
        )
    if synthetic_bucket is not None:
        checks["synthetic_bad_paired_apple_tv_press_pass_rate"] = synthetic_bucket >= 0.40

    if tier != "full":
        status = "sample_only"
    else:
        status = "pass" if all(checks.values()) else "fail"

    notes: list[str] = []
    if synthetic_bucket is None:
        notes.append("synthetic_bad_paired_apple_tv_press bucket missing in postprocess output")
    return {"status": status, "checks": checks, "set_metrics": set_metrics, "notes": notes}


def make_scene_gate(scene_summary: dict[str, Any] | None, scene_min_pass_rate: float) -> dict[str, Any]:
    if scene_summary is None:
        return {"status": "missing", "checks": {}, "notes": ["scene summary missing"]}

    hard_failures = scene_summary.get("hardFailures") or []
    pass_rate = scene_summary.get("passRate")
    checks = {
        "hard_failures_empty": len(hard_failures) == 0,
        "soft_pass_rate": (pass_rate if isinstance(pass_rate, (int, float)) else 0.0) >= scene_min_pass_rate,
    }
    if hard_failures:
        status = "fail"
    elif checks["soft_pass_rate"]:
        status = "pass"
    else:
        status = "warn"
    return {"status": status, "checks": checks, "hard_failures": hard_failures}


def overall_status(*statuses: str) -> str:
    priority = {"fail": 4, "warn": 3, "research_only": 2, "sample_only": 2, "missing": 2, "pass": 1, "not_requested": 0}
    return max(statuses, key=lambda value: priority.get(value, 0), default="pass")


def make_host_compare(
    baseline_summary: dict[str, Any],
    candidate_summary: dict[str, Any],
) -> dict[str, Any]:
    baseline_camera = baseline_summary.get("camera_summary") or {}
    baseline_camera_eval = baseline_summary.get("camera_eval") or {}
    baseline_scene = baseline_summary.get("scene_summary") or {}
    candidate_camera = candidate_summary.get("camera_summary") or {}
    candidate_camera_eval = candidate_summary.get("camera_eval") or {}
    candidate_scene = candidate_summary.get("scene_summary") or {}

    def metric_delta(key: str) -> dict[str, Any]:
        baseline_value = baseline_scene.get(key)
        candidate_value = candidate_scene.get(key)
        delta = None
        if isinstance(baseline_value, (int, float)) and isinstance(candidate_value, (int, float)):
            delta = candidate_value - baseline_value
        return {
            "baseline": baseline_value,
            "candidate": candidate_value,
            "delta": delta,
        }

    def nested_metric_delta(summary_a: dict[str, Any], summary_b: dict[str, Any], *path: str) -> dict[str, Any]:
        baseline_value: Any = summary_a
        candidate_value: Any = summary_b
        for key in path:
            baseline_value = baseline_value.get(key) if isinstance(baseline_value, dict) else None
            candidate_value = candidate_value.get(key) if isinstance(candidate_value, dict) else None
        delta = None
        if isinstance(baseline_value, (int, float)) and isinstance(candidate_value, (int, float)):
            delta = candidate_value - baseline_value
        return {
            "baseline": baseline_value,
            "candidate": candidate_value,
            "delta": delta,
        }

    return {
        "baseline_run_id": baseline_summary.get("run_id"),
        "candidate_run_id": candidate_summary.get("run_id"),
        "baseline_camera_status": baseline_camera.get("status"),
        "candidate_camera_status": candidate_camera.get("status"),
        "baseline_execution_mode": baseline_scene.get("executionMode"),
        "candidate_execution_mode": candidate_scene.get("executionMode"),
        "camera_quality_metrics": {
            "pass_rate": nested_metric_delta(baseline_camera_eval, candidate_camera_eval, "set_metrics", "pass_rate"),
            "forbidden_action_violation_rate": nested_metric_delta(
                baseline_camera_eval,
                candidate_camera_eval,
                "set_metrics",
                "forbidden_action_violation_rate",
            ),
            "good_frame_preservation_rate": nested_metric_delta(
                baseline_camera_eval,
                candidate_camera_eval,
                "set_metrics",
                "good_frame_preservation_rate",
            ),
            "expected_action_hit_rate": nested_metric_delta(
                baseline_camera_eval,
                candidate_camera_eval,
                "set_metrics",
                "expected_action_hit_rate",
            ),
            "future_action_hit_rate": nested_metric_delta(
                baseline_camera_eval,
                candidate_camera_eval,
                "set_metrics",
                "future_action_hit_rate",
            ),
        },
        "camera_metrics": {
            "batteryDelta": nested_metric_delta(baseline_camera, candidate_camera, "mobileMetrics", "batteryDelta"),
            "uiFPSP50": nested_metric_delta(baseline_camera, candidate_camera, "mobileMetrics", "uiFPSP50"),
            "pipelineFPSP50": nested_metric_delta(baseline_camera, candidate_camera, "mobileMetrics", "pipelineFPSP50"),
            "frameTimeP95Ms": nested_metric_delta(baseline_camera, candidate_camera, "mobileMetrics", "frameTimeP95Ms"),
            "cpuP95": nested_metric_delta(baseline_camera, candidate_camera, "mobileMetrics", "cpuP95"),
            "memoryP95MB": nested_metric_delta(baseline_camera, candidate_camera, "mobileMetrics", "memoryP95MB"),
        },
        "metrics": {
            "passRate": metric_delta("passRate"),
            "firstPassSuccessRate": metric_delta("firstPassSuccessRate"),
            "retryCaseRate": metric_delta("retryCaseRate"),
            "meanRetryCountPerCase": metric_delta("meanRetryCountPerCase"),
            "maxTokensReachedCaseRate": metric_delta("maxTokensReachedCaseRate"),
            "successfulCasesPerMinute": metric_delta("successfulCasesPerMinute"),
            "batteryDrainPer100Cases": metric_delta("batteryDrainPer100Cases"),
            "parseP50Ms": metric_delta("parseP50Ms"),
            "parseP95Ms": metric_delta("parseP95Ms"),
            "seriousThermalDurationRatio": metric_delta("seriousThermalDurationRatio"),
            "timeToSeriousThermalMs": metric_delta("timeToSeriousThermalMs"),
            "sustainedLatencyDegradationRatio": metric_delta("sustainedLatencyDegradationRatio"),
            "casesPerMinute": metric_delta("casesPerMinute"),
            "checkpointCount": metric_delta("checkpointCount"),
            "completedChunkCount": metric_delta("completedChunkCount"),
            "chunkFailureRate": metric_delta("chunkFailureRate"),
            "chunkRetryCount": metric_delta("chunkRetryCount"),
            "memoryP95MB": metric_delta("memoryP95MB"),
            "cpuP95": metric_delta("cpuP95"),
        },
    }


def write_host_compare(
    result_root: Path,
    run_id: str,
    compare: dict[str, Any],
) -> tuple[Path, Path]:
    json_path = result_root / f"{run_id}-host_pairwise_compare.json"
    md_path = result_root / f"{run_id}-host_pairwise_compare.md"
    json_path.write_text(json.dumps(compare, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Host Pairwise Compare",
        "",
        f"- `baseline_run_id`: {compare.get('baseline_run_id')}",
        f"- `candidate_run_id`: {compare.get('candidate_run_id')}",
        f"- `baseline_camera_status`: {compare.get('baseline_camera_status')}",
        f"- `candidate_camera_status`: {compare.get('candidate_camera_status')}",
        f"- `baseline_execution_mode`: {compare.get('baseline_execution_mode')}",
        f"- `candidate_execution_mode`: {compare.get('candidate_execution_mode')}",
        "",
        "## Camera quality metrics",
    ]
    for key, values in compare.get("camera_quality_metrics", {}).items():
        lines.append(
            f"- `{key}`: baseline={values.get('baseline')} candidate={values.get('candidate')} delta={values.get('delta')}"
        )
    lines.extend([
        "",
        "## Camera mobile metrics",
    ])
    for key, values in compare.get("camera_metrics", {}).items():
        lines.append(
            f"- `{key}`: baseline={values.get('baseline')} candidate={values.get('candidate')} delta={values.get('delta')}"
        )
    lines.extend([
        "",
        "## Scene metrics",
    ])
    for key, values in compare.get("metrics", {}).items():
        lines.append(
            f"- `{key}`: baseline={values.get('baseline')} candidate={values.get('candidate')} delta={values.get('delta')}"
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def write_host_summary(
    result_root: Path,
    run_id: str,
    tier: str,
    modules: list[str],
    app_summary: dict[str, Any] | None,
    camera_summary: dict[str, Any] | None,
    scene_summary: dict[str, Any] | None,
    camera_eval: dict[str, Any] | None,
    camera_gate: dict[str, Any],
    scene_gate: dict[str, Any],
) -> tuple[Path, Path]:
    summary = {
        "run_id": run_id,
        "tier": tier,
        "modules": modules,
        "app_summary": app_summary,
        "camera_summary": camera_summary,
        "scene_summary": scene_summary,
        "camera_eval": camera_eval,
        "camera_gate": camera_gate,
        "scene_gate": scene_gate,
        "overall_status": overall_status(
            app_summary.get("overallStatus", "pass") if app_summary else "missing",
            camera_gate["status"],
            scene_gate["status"],
        ),
    }
    json_path = result_root / f"{run_id}-host_combined_summary.json"
    md_path = result_root / f"{run_id}-host_combined_summary.md"
    json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Host Device Benchmark Summary",
        "",
        f"- `run_id`: {run_id}",
        f"- `tier`: {tier}",
        f"- `modules`: {', '.join(modules)}",
        f"- `overall_status`: {summary['overall_status']}",
        f"- `app_status`: {(app_summary or {}).get('overallStatus', 'missing')}",
        f"- `camera_gate`: {camera_gate['status']}",
        f"- `scene_gate`: {scene_gate['status']}",
        "",
        "## Camera gate checks",
    ]
    for key, value in camera_gate.get("checks", {}).items():
        lines.append(f"- `{key}`: {value}")
    if camera_eval:
        set_metrics = camera_eval.get("set_metrics", {})
        lines.extend(
            [
                "",
                "## Camera set metrics",
                f"- `pass_rate`: {set_metrics.get('pass_rate')}",
                f"- `forbidden_action_violation_rate`: {set_metrics.get('forbidden_action_violation_rate')}",
                f"- `good_frame_preservation_rate`: {set_metrics.get('good_frame_preservation_rate')}",
            ]
        )
    if camera_summary:
        mobile_metrics = camera_summary.get("mobileMetrics") or {}
        lines.extend(
            [
                "",
                "## Camera mobile metrics",
                f"- `status`: {camera_summary.get('status')}",
                f"- `batteryDelta`: {mobile_metrics.get('batteryDelta')}",
                f"- `uiFPSP50`: {mobile_metrics.get('uiFPSP50')}",
                f"- `pipelineFPSP50`: {mobile_metrics.get('pipelineFPSP50')}",
                f"- `frameTimeP95Ms`: {mobile_metrics.get('frameTimeP95Ms')}",
                f"- `cpuP95`: {mobile_metrics.get('cpuP95')}",
                f"- `memoryP95MB`: {mobile_metrics.get('memoryP95MB')}",
                f"- `thermalStatesSeen`: {mobile_metrics.get('thermalStatesSeen')}",
            ]
        )
    lines.extend(["", "## Scene gate checks"])
    for key, value in scene_gate.get("checks", {}).items():
        lines.append(f"- `{key}`: {value}")
    if scene_summary:
        lines.extend(
            [
                "",
                "## Scene Generator metrics",
                f"- `passRate`: {scene_summary.get('passRate')}",
                f"- `firstPassSuccessRate`: {scene_summary.get('firstPassSuccessRate')}",
                f"- `retryCaseRate`: {scene_summary.get('retryCaseRate')}",
                f"- `meanRetryCountPerCase`: {scene_summary.get('meanRetryCountPerCase')}",
                f"- `maxTokensReachedCaseRate`: {scene_summary.get('maxTokensReachedCaseRate')}",
                f"- `successfulCasesPerMinute`: {scene_summary.get('successfulCasesPerMinute')}",
                f"- `batteryDrainPer100Cases`: {scene_summary.get('batteryDrainPer100Cases')}",
                f"- `parseP50Ms`: {scene_summary.get('parseP50Ms')}",
                f"- `parseP95Ms`: {scene_summary.get('parseP95Ms')}",
                f"- `cpuP95`: {scene_summary.get('cpuP95')}",
                f"- `memoryP95MB`: {scene_summary.get('memoryP95MB')}",
                f"- `seriousThermalDurationRatio`: {scene_summary.get('seriousThermalDurationRatio')}",
                f"- `sustainedLatencyDegradationRatio`: {scene_summary.get('sustainedLatencyDegradationRatio')}",
            ]
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--tier", choices=("quick", "full"), default="quick")
    parser.add_argument("--modules", nargs="+", choices=("camera", "sceneGenerator"), default=["camera", "sceneGenerator"])
    parser.add_argument("--guided-live", action="store_true")
    parser.add_argument("--scene-min-pass-rate", type=float, default=0.60)
    parser.add_argument("--scene-runtime-preset", choices=("baseline", "efficiency", "batterySaver"), default="baseline")
    parser.add_argument("--scene-execution-mode", choices=("monolithic", "chunkedThermalAware"), default="chunkedThermalAware")
    parser.add_argument("--scene-serious-cooldown-ms", type=int, default=15000)
    parser.add_argument("--scene-critical-cooldown-ms", type=int, default=30000)
    parser.add_argument("--scene-max-chunk-attempts", type=int, default=2)
    parser.add_argument("--scene-checkpoint-enabled", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--compare-against", default=None)
    parser.add_argument("--workspace", default=None)
    parser.add_argument("--project", default="shafinMultitool.xcodeproj")
    parser.add_argument("--scheme", default="shafinMultitool")
    parser.add_argument("--result-root", default="build/device-benchmark")
    parser.add_argument("--run-id", default=f"device-benchmark-host-{os.getpid()}")
    parser.add_argument("--xcodebuild-timeout-seconds", type=int, default=1800)
    args = parser.parse_args(argv)

    if args.guided_live:
        print(
            "error: --guided-live is not supported by the current host-side xcodebuild harness. "
            "This path runs the non-interactive XCTest benchmark and would only record skipped guided-live coverage.",
            file=sys.stderr,
        )
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    result_root = (repo_root / args.result_root).resolve()
    result_root.mkdir(parents=True, exist_ok=True)
    xcresult = result_root / f"{args.run_id}.xcresult"
    attachments_dir = result_root / f"{args.run_id}-attachments"
    extracted_dir = result_root / f"{args.run_id}-artifacts"
    postprocess_dir = result_root / f"{args.run_id}-camera-postprocess"
    xcodebuild_log_path = result_root / f"{args.run_id}-xcodebuild.log"
    device_diagnostics_path = result_root / f"{args.run_id}-device_diagnostics.json"
    patched_xctestrun_path = result_root / f"{args.run_id}.xctestrun"
    isolated_build_root = Path("/private/tmp") / args.run_id
    derived_data_path = isolated_build_root / "derived-data"
    build_dir = isolated_build_root / "build"
    derived_data_path.mkdir(parents=True, exist_ok=True)
    build_dir.mkdir(parents=True, exist_ok=True)

    workspace = args.workspace
    if workspace is None:
        default_workspace = repo_root / "shafinMultitool.xcworkspace"
        workspace = str(default_workspace) if default_workspace.exists() else None

    config_json = json.dumps(build_config(args), separators=(",", ":"), ensure_ascii=False)
    config_base64 = base64.b64encode(config_json.encode("utf-8")).decode("ascii")
    env = dict(os.environ)
    env["DEVICE_BENCHMARK_CONFIG_BASE64"] = config_base64

    build_command = ["xcodebuild", "build-for-testing"]
    if workspace is not None:
        build_command.extend(["-workspace", workspace])
    else:
        build_command.extend(["-project", args.project])
    build_command.extend(
        [
            "-scheme",
            args.scheme,
            "-destination",
            "generic/platform=iOS",
            "-derivedDataPath",
            str(derived_data_path),
            f"BUILD_DIR={build_dir}",
        ]
    )
    print("running build-for-testing:", " ".join(build_command))
    build_result, build_timed_out = run_streaming_command(
        build_command,
        env=env,
        check=False,
        log_path=xcodebuild_log_path,
        timeout_seconds=args.xcodebuild_timeout_seconds,
    )
    xctestrun_path = find_xctestrun_file(derived_data_path)
    test_result = build_result
    test_timed_out = False
    xcodebuild_failed = build_result.returncode != 0
    if not xcodebuild_failed and xctestrun_path is None:
        xcodebuild_failed = True
        test_result = subprocess.CompletedProcess(
            ["xcodebuild", "build-for-testing"],
            65,
            "error: build-for-testing completed but no .xctestrun file was produced.\n",
            None,
        )
        print(test_result.stdout, file=sys.stderr)
    if not xcodebuild_failed and xctestrun_path is not None:
        patch_xctestrun_environment(
            xctestrun_path,
            patched_xctestrun_path,
            {"DEVICE_BENCHMARK_CONFIG_BASE64": config_base64},
        )
        test_command = [
            "xcodebuild",
            "test-without-building",
            "-xctestrun",
            str(patched_xctestrun_path),
            "-destination",
            f"platform=iOS,id={args.device_id}",
            "-resultBundlePath",
            str(xcresult),
            "-only-testing:shafinMultitoolTests/DeviceBenchmarkHarnessTests/testRunConfiguredDeviceBenchmark",
        ]
        print("running test-without-building:", " ".join(test_command))
        test_result, test_timed_out = run_streaming_command(
            test_command,
            env=env,
            check=False,
            log_path=xcodebuild_log_path,
            timeout_seconds=args.xcodebuild_timeout_seconds,
            append_log=True,
        )
        xcodebuild_failed = test_result.returncode != 0
    timed_out = build_timed_out or test_timed_out
    result = test_result
    device_diagnostics_json = None
    if xcodebuild_failed:
        if timed_out:
            print(
                f"warning: xcodebuild test timed out after {args.xcodebuild_timeout_seconds} seconds; collecting device diagnostics.",
                file=sys.stderr,
            )
        print("warning: device benchmark xcodebuild test failed; attempting to export partial attachments and summaries.", file=sys.stderr)
        device_diagnostics_json = write_json_artifact(
            device_diagnostics_path,
            collect_device_diagnostics(args.device_id),
        )

    maybe_export_attachments(xcresult, attachments_dir)
    normalized_aliases = normalize_exported_attachments(attachments_dir)
    extracted_root = maybe_extract_artifacts_zip(attachments_dir, extracted_dir)
    artifacts_search_root = extracted_root or attachments_dir
    camera_metrics_path = maybe_run_camera_postprocess(repo_root, artifacts_search_root, args.tier, postprocess_dir)

    app_summary = load_json_if_exists(find_first(artifacts_search_root, "combined_summary.json"))
    camera_summary = load_json_if_exists(find_first(artifacts_search_root, "camera_summary.json"))
    scene_summary = load_json_if_exists(find_first(artifacts_search_root, "scene_summary.json"))
    camera_eval = load_json_if_exists(camera_metrics_path)
    if camera_eval is not None:
        camera_eval["_bucket_metrics_path"] = str(postprocess_dir / "bucket_metrics.json")
    camera_gate = make_camera_gate(args.tier, camera_eval) if "camera" in args.modules else {"status": "not_requested", "checks": {}}
    scene_gate = make_scene_gate(scene_summary, args.scene_min_pass_rate) if "sceneGenerator" in args.modules else {"status": "not_requested", "checks": {}}
    host_summary_json, host_summary_md = write_host_summary(
        result_root=result_root,
        run_id=args.run_id,
        tier=args.tier,
        modules=args.modules,
        app_summary=app_summary,
        camera_summary=camera_summary,
        scene_summary=scene_summary,
        camera_eval=camera_eval,
        camera_gate=camera_gate,
        scene_gate=scene_gate,
    )

    archive_root = result_root / args.run_id
    if attachments_dir.exists():
        shutil.make_archive(str(archive_root), "zip", root_dir=attachments_dir)

    if args.compare_against:
        baseline_summary = load_json_if_exists(args.compare_against)
        if baseline_summary is None:
            print(f"warning: compare-against summary not found at {args.compare_against}", file=sys.stderr)
        else:
            compare = make_host_compare(baseline_summary, load_json_if_exists(host_summary_json) or {})
            compare_json, compare_md = write_host_compare(result_root, args.run_id, compare)
            print(f"host_compare_json: {compare_json}")
            print(f"host_compare_md: {compare_md}")

    print(f"xcresult: {xcresult}")
    print(f"attachments: {attachments_dir}")
    if normalized_aliases:
        print("normalized_attachments:")
        for alias, source_name in sorted(normalized_aliases.items()):
            print(f"  {alias} <- {source_name}")
    if postprocess_dir.exists():
        print(f"camera_postprocess: {postprocess_dir}")
    if extracted_dir.exists():
        print(f"artifacts_dir: {extracted_dir}")
    print(f"host_summary_json: {host_summary_json}")
    print(f"host_summary_md: {host_summary_md}")
    print(f"xcodebuild_log: {xcodebuild_log_path}")
    if device_diagnostics_json is not None:
        print(f"device_diagnostics_json: {device_diagnostics_json}")
    zip_path = archive_root.with_suffix(".zip")
    if zip_path.exists():
        print(f"artifacts_zip: {zip_path}")
    return result.returncode if xcodebuild_failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
