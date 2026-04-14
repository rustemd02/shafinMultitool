#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from runtime_feedback import ReviewAndPromoteRequest, RuntimeFeedbackError, review_and_promote_runtime_feedback


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply review decisions and promote runtime feedback artifacts.")
    parser.add_argument("--runtime-failures-jsonl", type=Path, required=True)
    parser.add_argument("--review-decisions-jsonl", type=Path, required=True)
    parser.add_argument("--output-runtime-failures-jsonl", type=Path, required=True)
    parser.add_argument("--output-promoted-jsonl", type=Path, required=True)
    parser.add_argument("--output-manifest-json", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    request = ReviewAndPromoteRequest(
        runtime_failures_jsonl=args.runtime_failures_jsonl,
        review_decisions_jsonl=args.review_decisions_jsonl,
        output_runtime_failures_jsonl=args.output_runtime_failures_jsonl,
        output_promoted_jsonl=args.output_promoted_jsonl,
        output_manifest_json=args.output_manifest_json,
    )
    try:
        result = review_and_promote_runtime_feedback(request)
    except RuntimeFeedbackError as exc:
        sys.stderr.write(f"Runtime feedback review/promotion failed: {exc}\n")
        return 2

    sys.stdout.write(
        f"Applied {result.manifest['applied_review_decisions']} review decisions -> "
        f"{result.manifest['promoted_count']} promoted samples ({args.output_promoted_jsonl})\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

