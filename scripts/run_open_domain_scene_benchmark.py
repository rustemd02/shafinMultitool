#!/usr/bin/env python3
"""
Run open-domain screenplay cases through the app's real device benchmark scene pipeline
on an iOS Simulator, without the XCTest harness.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCRIPTS_PATH = REPO_ROOT / "scripts" / "scripts.md"
DEFAULT_MODEL_PATH = REPO_ROOT / "shafinMultitool" / "Resources" / "Models" / "dataset_v9_event_sft_q4_k_m.gguf"
DEFAULT_BUNDLE_ID = "com.vigvamcev-media.shafinMultitool"
DEFAULT_SCHEME = "shafinMultitool"
DEFAULT_PROJECT = "shafinMultitool.xcodeproj"
DEFAULT_WORKSPACE = "shafinMultitool.xcworkspace"
DEFAULT_CONFIGURATION = "Debug"
DEFAULT_PACK_ID = "scene_generator_open_domain_scripts_md"
SCENE_PREFIX_MARKERS = {
    "ПЛАН НА:",
    "ВЫХОД ИЗ ЗАТЕМНЕНИЯ:",
    "ЧЕРНЫЙ ЭКРАН",
    "КОНЕЦ ТИЗЕРА",
    "ПЕРВЫЙ АКТ",
    "ВТОРОЙ АКТ",
    "ТРЕТИЙ АКТ",
}
SCENE_BOUNDARY_PREFIXES = (
    "ИНТ.",
    "ЭКСТ.",
    "INT.",
    "EXT.",
)


def run_command(
    command: list[str],
    *,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    check: bool = True,
    capture: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        check=check,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def load_script_cases(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    cases = [line.strip() for line in text.splitlines() if line.strip()]
    if not cases:
        raise ValueError(f"No non-empty cases found in {path}")
    return cases


def preprocess_script(text: str) -> str:
    output = text.replace("\r\n", "\n").replace("\r", "\n")
    output = " ".join(output.split()).strip()

    markers = [
        "ПЛАН НА:",
        "ВЫХОД ИЗ ЗАТЕМНЕНИЯ:",
        "ЧЕРНЫЙ ЭКРАН",
        "КОНЕЦ ТИЗЕРА",
        "ПЕРВЫЙ АКТ",
        "ВТОРОЙ АКТ",
        "ТРЕТИЙ АКТ",
        "ИНТ.",
        "ЭКСТ.",
        "INT.",
        "EXT.",
    ]
    for marker in markers:
        output = output.replace(marker, f"\n{marker}")

    output = output.replace("\n ", "\n")
    output = output.strip()

    import re
    output = re.sub(r'(?<=[.!?…])\s+(?=[A-ZА-ЯЁ0-9"«])', "\n", output)
    output = re.sub(r"\n+", "\n", output)
    return output.strip()


def is_scene_boundary(line: str) -> bool:
    upper = line.upper()
    return upper.startswith(SCENE_BOUNDARY_PREFIXES) or upper.startswith(tuple(SCENE_PREFIX_MARKERS))


def split_into_scene_units(text: str) -> list[str]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return []

    units: list[str] = []
    current_lines: list[str] = []

    def flush() -> None:
        if current_lines:
            units.append("\n".join(current_lines).strip())
            current_lines.clear()

    for line in lines:
        if is_scene_boundary(line) and current_lines:
            flush()
        current_lines.append(line)
    flush()

    merged: list[str] = []
    index = 0
    while index < len(units):
        unit = units[index].strip()
        if unit in SCENE_PREFIX_MARKERS and index + 1 < len(units):
            merged.append(f"{unit}\n{units[index + 1].strip()}".strip())
            index += 2
            continue
        merged.append(unit)
        index += 1

    return [unit for unit in merged if unit]


def build_records(
    cases: list[str],
    *,
    split_scenes: bool,
    case_index: int | None,
    max_records: int | None,
    scene_specs: list[str] | None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if scene_specs:
        parsed_specs: list[tuple[int, int]] = []
        for raw_spec in scene_specs:
            if ":" not in raw_spec:
                raise ValueError(f"Invalid scene spec '{raw_spec}'. Expected case:scene")
            raw_case, raw_scene = raw_spec.split(":", 1)
            parsed_specs.append((int(raw_case), int(raw_scene)))

        records: list[dict[str, Any]] = []
        selected_summaries: list[dict[str, Any]] = []
        for selected_case_index, selected_scene_index in parsed_specs:
            if selected_case_index < 1 or selected_case_index > len(cases):
                raise ValueError(f"Scene spec case index out of range: {selected_case_index}")
            original_case = cases[selected_case_index - 1]
            preprocessed = preprocess_script(original_case)
            scene_units = split_into_scene_units(preprocessed)
            if selected_scene_index < 1 or selected_scene_index > len(scene_units):
                raise ValueError(
                    f"Scene spec {selected_case_index}:{selected_scene_index} out of range; "
                    f"case has {len(scene_units)} scenes"
                )
            scene_text = scene_units[selected_scene_index - 1]
            sample_id = f"case_{selected_case_index:03d}_scene_{selected_scene_index:03d}"
            records.append(
                make_scene_record(
                    sample_id=sample_id,
                    source_text=scene_text,
                    pattern_name="open_domain_scene",
                    difficulty_bucket="open_domain_scene",
                )
            )
            selected_summaries.append(
                {
                    "case_index": selected_case_index,
                    "scene_index": selected_scene_index,
                    "sample_id": sample_id,
                    "char_count": len(scene_text),
                    "preview": scene_text.replace("\n", " | ")[:220],
                }
            )

        metadata = {
            "mode": "scene_specs",
            "case_index": None,
            "record_count": len(records),
            "selected_scenes": selected_summaries,
        }
        return records, metadata

    if split_scenes:
        if case_index is None:
            case_index = 1
        if case_index < 1 or case_index > len(cases):
            raise ValueError(f"--case-index must be between 1 and {len(cases)}")
        original_case = cases[case_index - 1]
        preprocessed = preprocess_script(original_case)
        scene_units = split_into_scene_units(preprocessed)
        if max_records is not None:
            scene_units = scene_units[:max_records]
        records = [
            make_scene_record(
                sample_id=f"case_{case_index:03d}_scene_{scene_index:03d}",
                source_text=scene_text,
                pattern_name="open_domain_scene",
                difficulty_bucket="open_domain_scene",
            )
            for scene_index, scene_text in enumerate(scene_units, start=1)
        ]
        metadata = {
            "mode": "scene_split",
            "case_index": case_index,
            "source_case_char_count": len(original_case),
            "preprocessed_char_count": len(preprocessed),
            "record_count": len(records),
        }
        return records, metadata

    records = [
        make_scene_record(
            sample_id=f"scripts_md_case_{index:03d}",
            source_text=case,
            pattern_name="open_domain_script",
            difficulty_bucket="open_domain",
        )
        for index, case in enumerate(cases, start=1)
    ]
    if max_records is not None:
        records = records[:max_records]
    metadata = {
        "mode": "whole_script",
        "case_index": None,
        "record_count": len(records),
    }
    return records, metadata


def make_scene_record(
    *,
    sample_id: str,
    source_text: str,
    pattern_name: str,
    difficulty_bucket: str,
) -> dict[str, Any]:
    return {
        "pattern_name": pattern_name,
        "difficulty_bucket": difficulty_bucket,
        "sample_id": sample_id,
        "source_text": source_text,
        "graph_constraints": {
            "marked_objects": [],
            "ordinal_bindings": {},
            "same_type_marker_conflict": False,
        },
        "validation_report": {
            "critic_verdict": "pass",
            "critic_detected_failures": [],
        },
    }


def write_pack(pack_root: Path, records: list[dict[str, Any]]) -> None:
    pack_root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "id": DEFAULT_PACK_ID,
        "core_source_file": "core_accepted_source.jsonl",
        "hard_source_file": "hard_accepted_source.jsonl",
        "default_quick_case_limit": len(records),
        "default_full_case_limit": len(records),
        "seed_quick": 20260616,
        "seed_full": 20260616,
    }
    (pack_root / "scene_generator_device_benchmark_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (pack_root / "core_accepted_source.jsonl").write_text(
        "\n".join(json.dumps(record, ensure_ascii=False) for record in records) + "\n",
        encoding="utf-8",
    )
    (pack_root / "hard_accepted_source.jsonl").write_text("", encoding="utf-8")


def find_simulator_udid(preferred_udid: str | None = None) -> str:
    if preferred_udid:
        return preferred_udid

    result = run_command(["xcrun", "simctl", "list", "devices", "available", "--json"])
    payload = json.loads(result.stdout)
    booted_candidates: list[tuple[str, str]] = []
    shutdown_candidates: list[tuple[str, str]] = []

    for runtime, devices in payload.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if not device.get("isAvailable", False):
                continue
            name = device.get("name", "")
            if "iPhone" not in name:
                continue
            item = (name, device["udid"])
            if device.get("state") == "Booted":
                booted_candidates.append(item)
            else:
                shutdown_candidates.append(item)

    candidates = booted_candidates or shutdown_candidates
    if not candidates:
        raise RuntimeError("No available iPhone simulator found.")

    candidates.sort()
    return candidates[0][1]


def boot_simulator(device_id: str) -> None:
    run_command(["xcrun", "simctl", "boot", device_id], check=False)
    run_command(["xcrun", "simctl", "bootstatus", device_id, "-b"], check=True)


def build_app(
    derived_data_path: Path,
    build_dir: Path,
    configuration: str,
    workspace: str | None,
    project: str,
    scheme: str,
) -> Path:
    command = ["xcodebuild"]
    workspace_path = REPO_ROOT / workspace if workspace else None
    if workspace_path and workspace_path.exists():
        command.extend(["-workspace", workspace])
    else:
        command.extend(["-project", project])
    command.extend(
        [
            "-scheme",
            scheme,
            "-configuration",
            configuration,
            "-destination",
            "generic/platform=iOS Simulator",
            "-derivedDataPath",
            str(derived_data_path),
            f"BUILD_DIR={build_dir}",
            "build",
        ]
    )
    result = run_command(command, cwd=REPO_ROOT, check=False)
    if result.returncode != 0:
        print(result.stdout)
        raise RuntimeError("xcodebuild failed")

    candidates = [
        derived_data_path / "Build" / "Products" / f"{configuration}-iphonesimulator" / "shafinMultitool.app",
        build_dir / f"{configuration}-iphonesimulator" / "shafinMultitool.app",
        build_dir / "shafinMultitool.app",
    ]
    for app_path in candidates:
        if app_path.exists():
            return app_path
    raise RuntimeError(
        "Built app not found. Checked: " + ", ".join(str(path) for path in candidates)
    )


def install_app(device_id: str, app_path: Path) -> None:
    result = run_command(["xcrun", "simctl", "install", device_id, str(app_path)], check=False)
    if result.returncode != 0:
        print(result.stdout)
        raise RuntimeError("simctl install failed")


def simulator_data_container(device_id: str) -> Path:
    result = run_command(["xcrun", "simctl", "get_app_container", device_id, DEFAULT_BUNDLE_ID, "data"])
    return Path(result.stdout.strip())


def make_config(run_id: str, pack_id: str, execution_mode: str) -> dict[str, Any]:
    return {
        "runId": run_id,
        "tier": "full",
        "enabledModules": ["sceneGenerator"],
        "sceneGeneratorModelPolicy": "explicitOrLatest",
        "sceneGeneratorExecutionMode": execution_mode,
        "sceneGeneratorThermalPolicy": {
            "mode": execution_mode,
            "cooldownOnSeriousMs": 15000,
            "cooldownOnCriticalMs": 30000,
            "maxChunkAttempts": 2,
            "checkpointEnabled": True,
        },
        "cameraResourcePackId": "camera_device_benchmark_pack_v1",
        "sceneResourcePackId": pack_id,
        "guidedLiveEnabled": False,
        "softThresholds": {
            "scenePassRate": 0.0,
        },
        "autoStart": True,
        "liveSequenceEnabled": False,
    }


def seed_pack_into_container(container_data_path: Path, run_id: str, pack_id: str, host_pack_path: Path) -> Path:
    run_root = container_data_path / "Library" / "Caches" / "DeviceBenchmark" / run_id
    if run_root.exists():
        shutil.rmtree(run_root)
    destination = run_root / "packs" / pack_id
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(host_pack_path, destination)
    return run_root


def launch_app(device_id: str, config: dict[str, Any], model_path: Path) -> str:
    config_base64 = base64.b64encode(
        json.dumps(config, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")
    env = dict(os.environ)
    env["SIMCTL_CHILD_DEVICE_BENCHMARK_CONFIG_BASE64"] = config_base64
    env["SIMCTL_CHILD_SG_LIVE_MODEL_PATH"] = str(model_path)
    env["SIMCTL_CHILD_NSUnbufferedIO"] = "YES"
    result = run_command(
        ["xcrun", "simctl", "launch", "--terminate-running-process", device_id, DEFAULT_BUNDLE_ID],
        env=env,
        check=False,
    )
    if result.returncode != 0:
        print(result.stdout)
        raise RuntimeError("simctl launch failed")
    return result.stdout.strip()


def wait_for_file(path: Path, timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if path.exists() and path.stat().st_size > 0:
            return
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for {path}")


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def collect_case_outputs(run_root: Path) -> list[dict[str, Any]]:
    scene_results_path = run_root / "scene_case_results.json"
    case_results = load_json(scene_results_path) if scene_results_path.exists() else []
    final_outputs: dict[str, dict[str, Any]] = {}
    checkpoints_root = run_root / "scene_checkpoints"
    if checkpoints_root.exists():
        for sample_dir in checkpoints_root.iterdir():
            if not sample_dir.is_dir():
                continue
            final_file = sample_dir / "scene_chunked_result.json"
            if not final_file.exists():
                final_file = sample_dir / "scene_monolithic_result.json"
            if final_file.exists():
                final_outputs[sample_dir.name] = load_json(final_file)

    combined: list[dict[str, Any]] = []
    for case_result in case_results:
        sample_id = case_result["sampleId"]
        final_output = final_outputs.get(sample_id, {})
        active_scene = final_output.get("activeSceneScript") or {}
        beats = active_scene.get("beats") or []
        nested_action_count = sum(len(beat.get("actions") or []) for beat in beats)
        combined.append(
            {
                "sample_id": sample_id,
                "pattern_name": case_result.get("patternName"),
                "passed": case_result.get("passed"),
                "parse_wall_time_ms": case_result.get("parseWallTimeMs"),
                "route": case_result.get("route"),
                "reason_codes": case_result.get("reasonCodes") or [],
                "hard_issues": case_result.get("hardIssues") or [],
                "soft_issues": case_result.get("softIssues") or [],
                "actor_count": case_result.get("actorCount"),
                "beat_count": case_result.get("beatCount"),
                "action_count": case_result.get("actionCount"),
                "checkpoint_count": (final_output.get("checkpointCount") if final_output else None),
                "scene_count": (final_output.get("sceneCount") if final_output else None),
                "active_scene_id": active_scene.get("id"),
                "active_scene_title": active_scene.get("title"),
                "active_scene_actors": len(active_scene.get("actors") or []),
                "active_scene_objects": len(active_scene.get("objects") or []),
                "active_scene_beats": len(beats),
                "active_scene_actions": nested_action_count,
                "final_checkpoint_file": str(
                    (
                        (checkpoints_root / sample_id / "scene_chunked_result.json")
                        if (checkpoints_root / sample_id / "scene_chunked_result.json").exists()
                        else (checkpoints_root / sample_id / "scene_monolithic_result.json")
                    )
                ),
            }
        )
    return combined


def write_host_report(
    output_root: Path,
    run_id: str,
    config: dict[str, Any],
    source_metadata: dict[str, Any],
    run_root: Path,
    scripts_path: Path,
    model_path: Path,
) -> tuple[Path, Path]:
    combined_summary = load_json(run_root / "combined_summary.json")
    scene_summary = load_json(run_root / "scene_summary.json")
    case_outputs = collect_case_outputs(run_root)
    payload = {
        "run_id": run_id,
        "scripts_path": str(scripts_path),
        "model_path": str(model_path),
        "config": config,
        "case_count": source_metadata.get("record_count"),
        "source_metadata": source_metadata,
        "combined_summary": combined_summary,
        "scene_summary": scene_summary,
        "cases": case_outputs,
    }
    json_path = output_root / f"{run_id}-open-domain-scene-report.json"
    md_path = output_root / f"{run_id}-open-domain-scene-report.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Open-Domain Scene Benchmark Report",
        "",
        f"- `run_id`: {run_id}",
        f"- `case_count`: {source_metadata.get('record_count')}",
        f"- `source_mode`: {source_metadata.get('mode')}",
        f"- `source_case_index`: {source_metadata.get('case_index')}",
        f"- `overall_status`: {combined_summary.get('overallStatus')}",
        f"- `scene_execution_mode`: {scene_summary.get('executionMode')}",
        f"- `model_path`: {scene_summary.get('modelPath')}",
        f"- `parse_p50_ms`: {scene_summary.get('parseP50Ms')}",
        f"- `parse_p95_ms`: {scene_summary.get('parseP95Ms')}",
        f"- `cases_per_minute`: {scene_summary.get('casesPerMinute')}",
        "",
        "## Cases",
    ]
    for index, case in enumerate(case_outputs, start=1):
        lines.extend(
            [
                f"### Case {index}",
                f"- `sample_id`: {case['sample_id']}",
                f"- `passed`: {case['passed']}",
                f"- `parse_wall_time_ms`: {case['parse_wall_time_ms']}",
                f"- `route`: {case['route']}",
                f"- `reason_codes`: {case['reason_codes']}",
                f"- `hard_issues`: {case['hard_issues']}",
                f"- `soft_issues`: {case['soft_issues']}",
                f"- `actors/beats/actions`: {case['active_scene_actors']}/{case['active_scene_beats']}/{case['active_scene_actions']}",
                f"- `checkpoint`: {case['final_checkpoint_file']}",
                "",
            ]
        )

    md_path.write_text("\n".join(lines), encoding="utf-8")
    return json_path, md_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scripts-path", default=str(DEFAULT_SCRIPTS_PATH))
    parser.add_argument("--model-path", default=str(DEFAULT_MODEL_PATH))
    parser.add_argument("--device-id", default=None)
    parser.add_argument("--run-id", default=f"open-domain-scene-{int(time.time())}")
    parser.add_argument("--execution-mode", choices=("monolithic", "chunkedThermalAware"), default="chunkedThermalAware")
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    parser.add_argument("--result-root", default="build/open-domain-scene-benchmark")
    parser.add_argument("--configuration", default=DEFAULT_CONFIGURATION)
    parser.add_argument("--workspace", default=DEFAULT_WORKSPACE)
    parser.add_argument("--project", default=DEFAULT_PROJECT)
    parser.add_argument("--scheme", default=DEFAULT_SCHEME)
    parser.add_argument("--app-path", default=None, help="Optional prebuilt .app path to reuse instead of rebuilding")
    parser.add_argument("--split-scenes", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--case-index", type=int, default=None)
    parser.add_argument("--max-records", type=int, default=None)
    parser.add_argument("--scene-specs", default=None, help="Comma-separated case:scene selectors, e.g. 1:1,1:3,2:22")
    args = parser.parse_args(argv)

    scripts_path = Path(args.scripts_path).resolve()
    model_path = Path(args.model_path).resolve()
    result_root = (REPO_ROOT / args.result_root).resolve()
    result_root.mkdir(parents=True, exist_ok=True)

    if not scripts_path.exists():
        raise FileNotFoundError(f"Scripts file not found: {scripts_path}")
    if not model_path.exists():
        raise FileNotFoundError(f"Model file not found: {model_path}")

    scene_specs = None
    if args.scene_specs:
        scene_specs = [item.strip() for item in args.scene_specs.split(",") if item.strip()]

    cases = load_script_cases(scripts_path)
    records, source_metadata = build_records(
        cases,
        split_scenes=args.split_scenes,
        case_index=args.case_index,
        max_records=args.max_records,
        scene_specs=scene_specs,
    )
    device_id = find_simulator_udid(args.device_id)
    boot_simulator(device_id)

    host_pack_root = result_root / f"{args.run_id}-pack"
    if host_pack_root.exists():
        shutil.rmtree(host_pack_root)
    write_pack(host_pack_root, records)

    print(f"Using simulator: {device_id}")
    if args.app_path:
        app_path = Path(args.app_path).resolve()
        if not app_path.exists():
            raise FileNotFoundError(f"Prebuilt app not found: {app_path}")
        print(f"Reusing prebuilt app: {app_path}")
    else:
        isolated_build_root = Path("/private/tmp") / args.run_id
        derived_data_path = isolated_build_root / "derived-data"
        build_dir = isolated_build_root / "build"
        derived_data_path.mkdir(parents=True, exist_ok=True)
        build_dir.mkdir(parents=True, exist_ok=True)
        print(f"Building app into: {derived_data_path}")
        app_path = build_app(
            derived_data_path,
            build_dir,
            args.configuration,
            args.workspace,
            args.project,
            args.scheme,
        )
        print(f"Built app: {app_path}")
    install_app(device_id, app_path)

    container_data_path = simulator_data_container(device_id)
    config = make_config(run_id=args.run_id, pack_id=DEFAULT_PACK_ID, execution_mode=args.execution_mode)
    run_root = seed_pack_into_container(container_data_path, args.run_id, DEFAULT_PACK_ID, host_pack_root)
    print(f"Seeded pack into: {run_root}")
    launch_output = launch_app(device_id, config, model_path)
    print(f"Launch output: {launch_output}")

    combined_summary_path = run_root / "combined_summary.json"
    wait_for_file(combined_summary_path, args.timeout_seconds)
    wait_for_file(run_root / "scene_summary.json", args.timeout_seconds)
    wait_for_file(run_root / "scene_case_results.json", args.timeout_seconds)

    copied_run_root = result_root / args.run_id
    if copied_run_root.exists():
        shutil.rmtree(copied_run_root)
    shutil.copytree(run_root, copied_run_root)
    report_json, report_md = write_host_report(
        result_root,
        args.run_id,
        config,
        source_metadata,
        copied_run_root,
        scripts_path,
        model_path,
    )

    print(f"run_root: {copied_run_root}")
    print(f"report_json: {report_json}")
    print(f"report_md: {report_md}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise
