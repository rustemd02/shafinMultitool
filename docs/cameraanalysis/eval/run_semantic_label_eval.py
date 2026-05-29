#!/usr/bin/env python3
"""Run semantic label eval for the 107-image Camera Analysis dataset."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict, List

from eval_io import read_jsonl, write_json, write_jsonl
from semantic_label_adapter import load_semantic_label_records, normalize_semantic_label_cases
from semantic_output_schema import (
    build_bad_candidate_outputs,
    build_oracle_candidate_outputs,
    build_proxy_current_outputs,
    render_semantic_eval_summary,
    score_semantic_candidate_outputs,
)


BUILTIN_CANDIDATES = {
    "oracle_projection",
    "bad_candidate",
    "proxy_current_limitations",
    "current_proxy",
    "manual_proxy_current_limitations",
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run semantic label eval")
    parser.add_argument("--labels", required=True, help="Path to semantic_labels_v1.jsonl")
    parser.add_argument("--outputs", required=True, help="Output directory")
    parser.add_argument(
        "--candidate",
        default="proxy_current_limitations",
        help="Candidate id or candidate-output JSONL path",
    )
    parser.add_argument(
        "--images-dir",
        default=None,
        help="Optional image directory for label/image integrity checks",
    )
    return parser.parse_args()


def _default_images_dir(labels_path: Path) -> Path | None:
    candidate = labels_path.parent / "images"
    return candidate if candidate.exists() else None


def _load_candidate_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows = read_jsonl(path)
    outputs: List[Dict[str, Any]] = []
    for row in rows:
        payload = row.get("output")
        outputs.append(payload if isinstance(payload, dict) else row)
    return outputs


def _resolve_candidate(candidate: str, cases: List[Dict[str, Any]]) -> tuple[str, List[Dict[str, Any]]]:
    candidate_path = Path(candidate)
    if candidate_path.exists() and candidate_path.is_file():
        return candidate_path.stem, _load_candidate_jsonl(candidate_path)
    if candidate not in BUILTIN_CANDIDATES:
        raise ValueError(
            f"unknown candidate {candidate!r}; use one of {sorted(BUILTIN_CANDIDATES)} "
            "or pass a JSONL path"
        )
    if candidate == "oracle_projection":
        return candidate, build_oracle_candidate_outputs(cases)
    if candidate == "bad_candidate":
        return candidate, build_bad_candidate_outputs(cases)
    return "proxy_current_limitations", build_proxy_current_outputs(cases)


def _candidate_rows(candidate_id: str, outputs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [
        {
            "record_id": output["record_id"],
            "candidate_id": candidate_id,
            "output": output,
        }
        for output in sorted(outputs, key=lambda item: item["record_id"])
    ]


def main() -> None:
    args = _parse_args()
    labels_path = Path(args.labels).resolve()
    output_dir = Path(args.outputs).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    images_dir = Path(args.images_dir).resolve() if args.images_dir else _default_images_dir(labels_path)
    records = load_semantic_label_records(labels_path, images_dir=images_dir)
    cases = normalize_semantic_label_cases(records)
    candidate_id, candidate_outputs = _resolve_candidate(args.candidate, cases)
    report = score_semantic_candidate_outputs(cases, candidate_outputs)

    write_jsonl(output_dir / "candidate_outputs.jsonl", _candidate_rows(candidate_id, candidate_outputs))
    if candidate_id == "proxy_current_limitations":
        write_jsonl(
            output_dir / "candidate_outputs_current_baseline.jsonl",
            _candidate_rows(candidate_id, candidate_outputs),
        )
    write_jsonl(output_dir / "case_results.jsonl", report["case_results"])
    write_json(
        output_dir / "set_metrics.json",
        {
            "candidate_id": candidate_id,
            "runtime_claim": candidate_outputs[0].get("runtime_claim") if candidate_outputs else None,
            "set_metrics": report["set_metrics"],
        },
    )
    write_json(
        output_dir / "bucket_metrics.json",
        {
            "candidate_id": candidate_id,
            "bucket_metrics": report["bucket_metrics"],
        },
    )
    (output_dir / "semantic_eval_summary.md").write_text(
        render_semantic_eval_summary(candidate_id, report),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
