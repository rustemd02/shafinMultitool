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
import re
import shutil
import subprocess
import sys
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
    "scene_monolithic_result.json",
    "scene_chunked_result.json",
}


def normalize_attachment_alias(suggested_name: str) -> str | None:
    if not suggested_name:
        return None
    match = re.match(r"(?P<stem>.+?)_\d+_[0-9A-Fa-f-]{36}(?P<ext>\.[^.]+)$", suggested_name)
    candidate = f"{match.group('stem')}{match.group('ext')}" if match else suggested_name
    if candidate in SCENE_ATTACHMENT_ALIASES or candidate.startswith("chunk_"):
        return candidate
    return None


def build_config(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "runId": args.run_id,
        "tier": args.tier,
        "enabledModules": args.modules,
        "sceneGeneratorModelPolicy": "explicitOrLatest",
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


def find_first_across_roots(roots: list[Path], name: str) -> Path | None:
    for root in roots:
        candidate = find_first(root, name)
        if candidate is not None:
            return candidate
    return None


def maybe_run_camera_postprocess(repo_root: Path, search_roots: list[Path], tier: str, postprocess_dir: Path) -> Path | None:
    candidate = find_first_across_roots(search_roots, "camera_still_rows.jsonl")
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
    baseline_scene = baseline_summary.get("scene_summary") or {}
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

    return {
        "baseline_run_id": baseline_summary.get("run_id"),
        "candidate_run_id": candidate_summary.get("run_id"),
        "baseline_execution_mode": baseline_scene.get("executionMode"),
        "candidate_execution_mode": candidate_scene.get("executionMode"),
        "metrics": {
            "passRate": metric_delta("passRate"),
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
        f"- `baseline_execution_mode`: {compare.get('baseline_execution_mode')}",
        f"- `candidate_execution_mode`: {compare.get('candidate_execution_mode')}",
        "",
        "## Scene metrics",
    ]
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
    lines.extend(["", "## Scene gate checks"])
    for key, value in scene_gate.get("checks", {}).items():
        lines.append(f"- `{key}`: {value}")
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--tier", choices=("quick", "full"), default="quick")
    parser.add_argument("--modules", nargs="+", choices=("camera", "sceneGenerator"), default=["camera", "sceneGenerator"])
    parser.add_argument("--guided-live", action="store_true")
    parser.add_argument("--scene-min-pass-rate", type=float, default=0.60)
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

    command = ["xcodebuild", "test"]
    if workspace is not None:
        command.extend(["-workspace", workspace])
    else:
        command.extend(["-project", args.project])
    command.extend(
        [
            "-scheme",
            args.scheme,
            "-destination",
            f"platform=iOS,id={args.device_id}",
            "-derivedDataPath",
            str(derived_data_path),
            "-resultBundlePath",
            str(xcresult),
            "-only-testing:shafinMultitoolTests/DeviceBenchmarkHarnessTests/testRunConfiguredDeviceBenchmark",
            f"BUILD_DIR={build_dir}",
        ]
    )
    print("running:", " ".join(command))
    result = run_command(command, env=env, check=False)
    print(result.stdout)
    xcodebuild_failed = result.returncode != 0
    if xcodebuild_failed:
        print("warning: device benchmark xcodebuild test failed; attempting to export partial attachments and summaries.", file=sys.stderr)

    maybe_export_attachments(xcresult, attachments_dir)
    normalized_aliases = normalize_exported_attachments(attachments_dir)
    extracted_root = maybe_extract_artifacts_zip(attachments_dir, extracted_dir)
    artifacts_search_roots = [root for root in [extracted_root, attachments_dir] if root is not None]
    camera_metrics_path = maybe_run_camera_postprocess(repo_root, artifacts_search_roots, args.tier, postprocess_dir)

    app_summary = load_json_if_exists(find_first_across_roots(artifacts_search_roots, "combined_summary.json"))
    camera_summary = load_json_if_exists(find_first_across_roots(artifacts_search_roots, "camera_summary.json"))
    scene_summary = load_json_if_exists(find_first_across_roots(artifacts_search_roots, "scene_summary.json"))
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
    zip_path = archive_root.with_suffix(".zip")
    if zip_path.exists():
        print(f"artifacts_zip: {zip_path}")
    return result.returncode if xcodebuild_failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
