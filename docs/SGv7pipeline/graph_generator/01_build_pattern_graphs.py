#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cir_contract.contracts.cir_types import SourceVariantKey
from graph_generator import GraphBuildRequest, build_graph_records


def _log(stage: str, message: str) -> None:
    sys.stdout.write(f"[sgv7:graph_generator] {stage}: {message}\n")
    sys.stdout.flush()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build deterministic SG v7 CIR graph records as JSONL.")
    parser.add_argument("--seed", type=int, required=True, help="Build seed for deterministic planning.")
    parser.add_argument("--bucket", choices=["core", "hard"], dest="difficulty_bucket")
    parser.add_argument("--total-records", type=int, dest="total_records")
    parser.add_argument("--pattern-name", action="append", dest="pattern_names")
    parser.add_argument(
        "--variant",
        action="append",
        dest="include_variants",
        choices=["base", "ordinal_stress", "morphology_stress", "same_type_marker_stress", "dialogue_mix"],
        help="Optional variant filter; may be repeated.",
    )
    parser.add_argument("--output-jsonl", type=Path, required=True)
    parser.add_argument("--output-manifest", type=Path)
    parser.add_argument("--refill-budget", type=int, default=3)
    parser.add_argument("--fail-on-duplicates", action="store_true")
    return parser.parse_args()


def main() -> int:
    _log("stage 1/4", "parse args")
    args = _parse_args()
    include_variants = None
    if args.include_variants is not None:
        include_variants = [variant for variant in args.include_variants]

    _log(
        "stage 2/4",
        f"build request bucket={args.difficulty_bucket or 'all'} total_records={args.total_records or 'auto'} refill_budget={args.refill_budget}",
    )
    request = GraphBuildRequest(
        seed=args.seed,
        difficulty_bucket=args.difficulty_bucket,
        total_records=args.total_records,
        pattern_names=args.pattern_names,
        include_variants=include_variants,
        output_jsonl=args.output_jsonl,
        output_manifest=args.output_manifest,
        refill_budget=args.refill_budget,
        fail_on_duplicates=args.fail_on_duplicates,
    )
    _log("stage 3/4", "run deterministic graph builder")
    result = build_graph_records(request)
    _log("stage 4/4", f"write artifacts records={len(result.records)}")
    sys.stdout.write(
        f"Built {len(result.records)} graph records -> {request.output_jsonl}"
        + (f" and {request.output_manifest}" if request.output_manifest is not None else "")
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
