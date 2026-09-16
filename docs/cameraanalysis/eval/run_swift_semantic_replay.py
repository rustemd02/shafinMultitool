#!/usr/bin/env python3
"""Run the Swift semantic still-image replay from a committed replay config.

The checked-in config is intentionally portable. This runner resolves its
repository-relative inputs and external output contract into a transient
absolute config, selects it through SEMANTIC_EVAL_CONFIG, and also writes the
test's canonical transient config path for Xcode test-process inheritance.

The default config is the M4-001 fullRuntime 107-record lane; ``--config``
selects another committed lane (for example the 174-record label-drift lane)
without changing how the M4-001 lane materializes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


CONFIG_RELATIVE_PATH = Path(
    "docs/cameraanalysis/eval/camera-baseline-v0/replay-config-107.json"
)
TEST_IDENTIFIER = (
    "shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/"
    "testExportSemanticEvalCandidateOutputsFromStillImages"
)
CANONICAL_TEST_CONFIG_PATH = Path("/private/tmp/semantic_eval_replay_config.json")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def repository_root(script_path: Path) -> Path:
    result = subprocess.run(
        ["git", "-C", str(script_path.parent), "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
        text=True,
    )
    return Path(result.stdout.strip()).resolve()


def repo_relative_path(repo_root: Path, value: str, field: str) -> Path:
    candidate = Path(value)
    if candidate.is_absolute():
        raise SystemExit(f"{field} must remain repository-relative: {value}")
    resolved = (repo_root / candidate).resolve()
    if resolved != repo_root and repo_root not in resolved.parents:
        raise SystemExit(f"{field} escapes the repository root: {value}")
    return resolved


def external_absolute_path(value: str, field: str, repo_root: Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise SystemExit(f"{field} must be an absolute external path: {value}")
    resolved = path.resolve()
    if resolved == repo_root or repo_root in resolved.parents:
        raise SystemExit(f"{field} must stay outside the repository: {value}")
    return resolved


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay the committed M4-001 Swift fullRuntime config."
    )
    parser.add_argument(
        "--destination",
        required=True,
        help="Explicit allowed iOS Simulator destination (never iPhone 17 Pro).",
    )
    parser.add_argument("--derived-data-path", required=True)
    parser.add_argument("--result-bundle-path", required=True)
    parser.add_argument(
        "--output-path",
        required=True,
        help="External path for the JSONL output written by the Swift test.",
    )
    parser.add_argument(
        "--config",
        default=str(CONFIG_RELATIVE_PATH),
        help=(
            "Repository-relative committed replay config to execute "
            f"(default: {CONFIG_RELATIVE_PATH})."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    script_path = Path(__file__).resolve()
    repo_root = repository_root(script_path)
    config_path = repo_relative_path(repo_root, args.config, "config")
    config_bytes = config_path.read_bytes()
    config = json.loads(config_bytes)
    config_relative = config_path.relative_to(repo_root)

    if not isinstance(config.get("config_id"), str) or not config["config_id"]:
        raise SystemExit("committed replay config is missing a config_id")
    if config.get("runtime") != "real_runtime_still_replay":
        raise SystemExit("committed replay config is not fullRuntime")
    if config.get("output_path") != "<EXTERNAL_OUTPUT_PATH>":
        raise SystemExit("committed replay config must retain the external output placeholder")

    labels_path = repo_relative_path(repo_root, config["labels_path"], "labels_path")
    images_root_path = repo_relative_path(
        repo_root, config["images_root_path"], "images_root_path"
    )
    output_path = external_absolute_path(args.output_path, "output_path", repo_root)
    derived_data_path = external_absolute_path(
        args.derived_data_path, "derived_data_path", repo_root
    )
    result_bundle_path = external_absolute_path(
        args.result_bundle_path, "result_bundle_path", repo_root
    )

    if not labels_path.is_file():
        raise SystemExit(f"labels file does not exist: {labels_path}")
    if not images_root_path.is_dir():
        raise SystemExit(f"images directory does not exist: {images_root_path}")
    if output_path.exists():
        raise SystemExit(f"refusing to overwrite existing output: {output_path}")
    if result_bundle_path.exists():
        raise SystemExit(f"refusing to overwrite existing result bundle: {result_bundle_path}")

    materialized = dict(config)
    materialized["labels_path"] = str(labels_path)
    materialized["images_root_path"] = str(images_root_path)
    materialized["output_path"] = str(output_path)
    materialized["delete_after_read"] = False
    materialized_bytes = (json.dumps(materialized, sort_keys=True, indent=2) + "\n").encode()

    materialized_path = CANONICAL_TEST_CONFIG_PATH
    if materialized_path.exists():
        raise SystemExit(
            "refusing to overwrite the canonical transient test config: "
            f"{materialized_path}"
        )
    try:
        materialized_path.write_bytes(materialized_bytes)

        command = [
            "xcodebuild",
            "test",
            "-workspace",
            str(repo_root / "shafinMultitool.xcworkspace"),
            "-scheme",
            "shafinMultitool",
            "-configuration",
            "Debug",
            "-destination",
            args.destination,
            "-derivedDataPath",
            str(derived_data_path),
            "-resultBundlePath",
            str(result_bundle_path),
            f"-only-testing:{TEST_IDENTIFIER}",
            "-collect-test-diagnostics",
            "never",
            "CODE_SIGNING_ALLOWED=NO",
        ]

        env = os.environ.copy()
        for key in (
            "SEMANTIC_EVAL_LABELS",
            "SEMANTIC_EVAL_IMAGES_ROOT",
            "SEMANTIC_EVAL_OUTPUT",
            "SEMANTIC_EVAL_RUNTIME",
            "SEMANTIC_EVAL_LIMIT",
        ):
            env.pop(key, None)
        env["SEMANTIC_EVAL_CONFIG"] = str(materialized_path)

        print(f"committed_config={config_relative}")
        print(f"committed_config_sha256={sha256_bytes(config_bytes)}")
        print(f"materialized_config_sha256={sha256_bytes(materialized_bytes)}")
        print("xcodebuild_command=" + " ".join(command))
        completed = subprocess.run(command, cwd=repo_root, env=env)
        if completed.returncode != 0:
            return completed.returncode

        if not output_path.is_file():
            raise SystemExit(f"Swift replay did not create output: {output_path}")
        rows = output_path.read_text(encoding="utf-8").splitlines()
        records = {json.loads(row)["record_id"] for row in rows}
        expected_records = config.get("expected_records")
        expected_rows = config.get("expected_rows")
        if isinstance(expected_records, int) and len(records) != expected_records:
            raise SystemExit(
                f"output record count {len(records)} does not match expected_records {expected_records}"
            )
        if isinstance(expected_rows, int) and len(rows) != expected_rows:
            raise SystemExit(
                f"output row count {len(rows)} does not match expected_rows {expected_rows}"
            )
        print(f"output_sha256={sha256_file(output_path)}")
        print(f"output_rows={len(rows)}")
        print(f"output_records={len(records)}")
        return 0
    finally:
        materialized_path.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
