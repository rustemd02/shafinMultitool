#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from runtime_feedback import ExportEvalCasesRequest, export_real_runtime_eval_cases


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export reviewed runtime failures into real_runtime eval cases.")
    parser.add_argument("--runtime-failures-jsonl", type=Path, required=True)
    parser.add_argument("--cir-jsonl", type=Path, required=True)
    parser.add_argument("--output-eval-cases-jsonl", type=Path, required=True)
    parser.add_argument("--output-quarantine-jsonl", type=Path, required=True)
    parser.add_argument("--output-manifest-json", type=Path, required=True)
    parser.add_argument("--contract-version", default="sg_v7_contract_v1")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    request = ExportEvalCasesRequest(
        runtime_failures_jsonl=args.runtime_failures_jsonl,
        cir_jsonl=args.cir_jsonl,
        output_eval_cases_jsonl=args.output_eval_cases_jsonl,
        output_quarantine_jsonl=args.output_quarantine_jsonl,
        output_manifest_json=args.output_manifest_json,
        contract_version=args.contract_version,
    )
    result = export_real_runtime_eval_cases(request)
    sys.stdout.write(
        f"Exported {result.manifest['exported_eval_case_count']} real_runtime eval cases "
        f"({args.output_eval_cases_jsonl}); quarantined={result.manifest['quarantined_count']}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

