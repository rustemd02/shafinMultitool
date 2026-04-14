#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from runtime_feedback import NormalizeRuntimeFeedbackRequest, RuntimeFeedbackError, normalize_runtime_feedback


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Normalize runtime parse events into runtime_failures artifacts.")
    parser.add_argument("--runtime-events-jsonl", type=Path, required=True)
    parser.add_argument("--runtime-failures-jsonl", type=Path, required=True)
    parser.add_argument("--review-queue-jsonl", type=Path, required=True)
    parser.add_argument("--cluster-manifest-json", type=Path, required=True)
    parser.add_argument("--manifest-json", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--contract-version", default="sg_v7_contract_v1")
    parser.add_argument("--unsupported-action-lemmas-path", type=Path)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    request = NormalizeRuntimeFeedbackRequest(
        runtime_events_jsonl=args.runtime_events_jsonl,
        runtime_failures_jsonl=args.runtime_failures_jsonl,
        review_queue_jsonl=args.review_queue_jsonl,
        cluster_manifest_json=args.cluster_manifest_json,
        manifest_json=args.manifest_json,
        seed=args.seed,
        contract_version=args.contract_version,
        unsupported_action_lemmas_path=args.unsupported_action_lemmas_path,
    )
    try:
        result = normalize_runtime_feedback(request)
    except RuntimeFeedbackError as exc:
        sys.stderr.write(f"Runtime feedback normalization failed: {exc}\n")
        return 2

    sys.stdout.write(
        f"Normalized {result.manifest['input_event_count']} runtime events -> "
        f"{result.manifest['runtime_failure_count']} failures ({args.runtime_failures_jsonl})\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

