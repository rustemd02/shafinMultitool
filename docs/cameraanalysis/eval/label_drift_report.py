#!/usr/bin/env python3
"""Label-drift report over canonical semantic-eval scoring.

The canonical evaluator in this directory already scores exported runtime rows
against quality-labeled records. This tool adds the drift view that the critic
alignment work needs and that the earlier one-off forensics dump did not keep:

* canonical set metrics for the full label set;
* the same canonical metrics restricted to records whose label ``sha256``
  actually matches the replayed image bytes;
* explicit per-record drift dispositions (keep / correct / silence) and flag
  counts (expected-action miss, forbidden hit, good-frame overcorrection,
  false keep on non-good frames);
* a strict drift counter defined as ``set(candidate_actions) !=
  set(expected_actions) or forbidden hit`` so historical forensics numbers can
  be compared like for like.

Everything is derived from committed inputs; no network, model download, or
device access is involved. The report is descriptive evidence about the current
deterministic critic, not a release claim.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List, Sequence

from eval_io import read_jsonl, write_json, write_jsonl
from semantic_label_adapter import load_semantic_label_records, normalize_semantic_label_cases
from semantic_output_schema import score_semantic_candidate_outputs

KEEP_ACTION = "keep_current_setup"
DISPOSITIONS = ("keep", "correct", "silence")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_label_image_bindings(
    records: Sequence[Dict[str, Any]],
    images_root: Path,
) -> tuple[List[str], List[Dict[str, str]]]:
    """Return (verified record ids, unverified entries) for label sha256 bindings."""
    verified: List[str] = []
    unverified: List[Dict[str, str]] = []
    for row in records:
        record_id = str(row["record_id"])
        filename = str(row["filename"])
        declared = str(row.get("sha256", ""))
        image_path = images_root / filename
        if not image_path.is_file():
            unverified.append({"record_id": record_id, "filename": filename, "reason": "image_missing"})
            continue
        actual = sha256_file(image_path)
        if actual != declared:
            unverified.append(
                {
                    "record_id": record_id,
                    "filename": filename,
                    "reason": "sha256_mismatch",
                    "declared_sha256": declared,
                    "actual_sha256": actual,
                }
            )
            continue
        verified.append(record_id)
    return verified, unverified


def _disposition(candidate_actions: Sequence[str]) -> str:
    actions = set(candidate_actions)
    if not actions:
        return "silence"
    if actions == {KEEP_ACTION}:
        return "keep"
    return "correct"


def drift_rows(case_results: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for result in case_results:
        expected = set(result["expected_actions"])
        candidate = set(result["candidate_actions"])
        forbidden = set(result["forbidden_actions"])
        forbidden_hit = sorted(candidate & forbidden)
        quality = result["quality_label"]
        disposition = _disposition(result["candidate_actions"])
        strict_drift = candidate != expected or bool(forbidden_hit)
        rows.append(
            {
                "record_id": result["record_id"],
                "quality_label": quality,
                "filename": result.get("filename"),
                "expected_actions": sorted(expected),
                "candidate_actions": sorted(candidate),
                "disposition": disposition,
                "expected_miss": bool(expected) and not bool(expected & candidate),
                "forbidden_hit": forbidden_hit,
                "good_frame_overcorrection": quality == "good" and disposition == "correct",
                "false_keep_on_non_good": quality != "good" and KEEP_ACTION in candidate,
                "silence_on_non_good": quality != "good" and disposition == "silence",
                "strict_drift": strict_drift,
                "canonical_failures": list(result.get("failures", [])),
            }
        )
    return sorted(rows, key=lambda row: row["record_id"])


def _aggregate(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    def count(predicate) -> int:
        return sum(1 for row in rows if predicate(row))

    by_quality: Dict[str, int] = {}
    for row in rows:
        by_quality[row["quality_label"]] = by_quality.get(row["quality_label"], 0) + 1

    return {
        "record_count": len(rows),
        "by_quality_label": dict(sorted(by_quality.items())),
        "by_disposition": {
            name: count(lambda row, name=name: row["disposition"] == name) for name in DISPOSITIONS
        },
        "strict_drift_count": count(lambda row: row["strict_drift"]),
        "expected_miss_count": count(lambda row: row["expected_miss"]),
        "forbidden_hit_count": count(lambda row: bool(row["forbidden_hit"])),
        "forbidden_hit_records": [
            {"record_id": row["record_id"], "actions": row["forbidden_hit"]}
            for row in rows
            if row["forbidden_hit"]
        ],
        "good_frame_overcorrection_count": count(lambda row: row["good_frame_overcorrection"]),
        "false_keep_on_non_good_count": count(lambda row: row["false_keep_on_non_good"]),
        "silence_on_non_good_count": count(lambda row: row["silence_on_non_good"]),
        "good_overcorrection_rate": _rate(rows, lambda row: row["good_frame_overcorrection"]),
        "false_keep_on_non_good_rate": _rate(rows, lambda row: row["false_keep_on_non_good"]),
        "silence_on_non_good_rate": _rate(rows, lambda row: row["silence_on_non_good"]),
        "strict_drift_rate": _rate(rows, lambda row: row["strict_drift"]),
    }


def _rate(rows: Sequence[Dict[str, Any]], predicate) -> float | None:
    if not rows:
        return None
    return round(sum(1 for row in rows if predicate(row)) / len(rows), 6)


def build_drift_report(
    labels_path: Path,
    outputs_path: Path,
    images_root: Path,
    *,
    candidate_id: str,
) -> Dict[str, Any]:
    records = load_semantic_label_records(labels_path)
    cases = normalize_semantic_label_cases(records)
    outputs = read_jsonl(outputs_path)
    flat_outputs = [row["output"] if isinstance(row.get("output"), dict) else row for row in outputs]

    full = score_semantic_candidate_outputs(cases, flat_outputs)
    verified_ids, unverified = verify_label_image_bindings(records, images_root)
    verified_set = set(verified_ids)
    verified_cases = [case for case in cases if case["record_id"] in verified_set]
    verified_outputs = [row for row in flat_outputs if row["record_id"] in verified_set]
    verified = score_semantic_candidate_outputs(verified_cases, verified_outputs)

    rows = drift_rows(full["case_results"])
    verified_rows = [row for row in rows if row["record_id"] in verified_set]

    return {
        "report_id": f"{candidate_id}-label-drift",
        "candidate_id": candidate_id,
        "inputs": {
            "labels_path": str(labels_path),
            "labels_sha256": sha256_file(labels_path),
            "outputs_path": str(outputs_path),
            "outputs_sha256": sha256_file(outputs_path),
            "images_root": str(images_root),
            "output_rows": len(outputs),
            "label_records": len(records),
        },
        "integrity": {
            "verified_binding_records": len(verified_ids),
            "unverified_binding_records": len(unverified),
            "unverified": unverified,
            "scope_note": (
                "Unverified bindings mean the label sha256 does not match the image bytes that were "
                "replayed. Metrics restricted to verified bindings are reported separately so the "
                "drift numbers can be read on byte-bound records only."
            ),
        },
        "full_set": {
            "set_metrics": full["set_metrics"],
            "quality_label_buckets": full["bucket_metrics"]["quality_label"],
            "drift": _aggregate(rows),
            "drift_rows": rows,
        },
        "verified_binding_subset": {
            "set_metrics": verified["set_metrics"],
            "quality_label_buckets": verified["bucket_metrics"]["quality_label"],
            "drift": _aggregate(verified_rows),
        },
    }


def render_markdown(report: Dict[str, Any]) -> str:
    lines: List[str] = [
        "# Label Drift Report",
        "",
        f"Report: `{report['report_id']}`",
        "",
        f"Candidate: `{report['candidate_id']}`",
        "",
        "## Inputs",
        "",
        f"- Labels: `{report['inputs']['labels_path']}` "
        f"(sha256 `{report['inputs']['labels_sha256']}`, {report['inputs']['label_records']} records)",
        f"- Outputs: `{report['inputs']['outputs_path']}` "
        f"(sha256 `{report['inputs']['outputs_sha256']}`, {report['inputs']['output_rows']} rows)",
        f"- Images root: `{report['inputs']['images_root']}`",
        "",
        "## Label/image sha256 bindings",
        "",
        f"- Verified: {report['integrity']['verified_binding_records']}",
        f"- Unverified: {report['integrity']['unverified_binding_records']}",
        "",
        report["integrity"]["scope_note"],
        "",
        "## Full label set",
        "",
    ]
    lines.extend(_render_metrics_block(report["full_set"]))
    lines.extend(["", "## Byte-verified subset", "", ""])
    lines.extend(_render_metrics_block(report["verified_binding_subset"]))
    lines.extend(
        [
            "",
            "## Drifted records",
            "",
            "Rows whose exported action set differs from the label expectation or hits a forbidden "
            "action. Silent rows are shown only when the label expected an action.",
            "",
        ]
    )
    lines.append("| record | quality | disposition | expected | candidate | flags |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for row in report["full_set"]["drift_rows"]:
        flags = []
        if row["expected_miss"]:
            flags.append("expected_miss")
        if row["forbidden_hit"]:
            flags.append("forbidden:" + ",".join(row["forbidden_hit"]))
        if row["good_frame_overcorrection"]:
            flags.append("good_overcorrection")
        if row["false_keep_on_non_good"]:
            flags.append("false_keep")
        if not row["strict_drift"]:
            continue
        lines.append(
            "| {record} | {quality} | {disposition} | `{expected}` | `{candidate}` | {flags} |".format(
                record=row["record_id"],
                quality=row["quality_label"],
                disposition=row["disposition"],
                expected=", ".join(row["expected_actions"]) or "—",
                candidate=", ".join(row["candidate_actions"]) or "—",
                flags=", ".join(flags) or "—",
            )
        )
    lines.append("")
    return "\n".join(lines)


def _render_metrics_block(block: Dict[str, Any]) -> List[str]:
    metrics = block["set_metrics"]
    drift = block["drift"]
    lines = [
        f"- Records: {metrics['record_count']}",
        f"- pass_rate: {metrics['pass_rate']}",
        f"- expected_action_hit_rate: {metrics['expected_action_hit_rate']}",
        f"- forbidden_action_violation_rate: {metrics['forbidden_action_violation_rate']}",
        f"- good_frame_preservation_rate: {metrics['good_frame_preservation_rate']}",
        f"- confidence_band_accuracy: {metrics['confidence_band_accuracy']}",
        f"- failure_counts: `{json.dumps(metrics['failure_counts'], sort_keys=True)}`",
        "",
        f"- strict_drift_rate (set inequality or forbidden hit): {drift['strict_drift_rate']} "
        f"({drift['strict_drift_count']}/{drift['record_count']})",
        f"- disposition counts: `{json.dumps(drift['by_disposition'], sort_keys=True)}`",
        f"- by quality label: `{json.dumps(drift['by_quality_label'], sort_keys=True)}`",
        f"- good_frame_overcorrection: {drift['good_frame_overcorrection_count']} "
        f"(rate {drift['good_overcorrection_rate']})",
        f"- false_keep_on_non_good: {drift['false_keep_on_non_good_count']} "
        f"(rate {drift['false_keep_on_non_good_rate']})",
        f"- silence_on_non_good: {drift['silence_on_non_good_count']} "
        f"(rate {drift['silence_on_non_good_rate']})",
    ]
    return lines


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a label-drift report")
    parser.add_argument("--labels", type=Path, required=True)
    parser.add_argument("--outputs", type=Path, required=True)
    parser.add_argument("--images-root", type=Path, required=True)
    parser.add_argument("--candidate-id", required=True)
    parser.add_argument("--out-json", type=Path, required=True)
    parser.add_argument("--out-md", type=Path, required=True)
    parser.add_argument(
        "--emit-case-results",
        type=Path,
        default=None,
        help="Optional path for the canonical per-record case results JSONL.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    for path, label in ((args.labels, "labels"), (args.outputs, "outputs")):
        if not path.is_file():
            raise SystemExit(f"{label} file does not exist: {path}")
    if not args.images_root.is_dir():
        raise SystemExit(f"images root does not exist: {args.images_root}")

    report = build_drift_report(
        args.labels,
        args.outputs,
        args.images_root,
        candidate_id=args.candidate_id,
    )
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.out_json, report)
    args.out_md.write_text(render_markdown(report), encoding="utf-8")
    if args.emit_case_results is not None:
        write_jsonl(
            args.emit_case_results,
            [
                {"case_id": row["record_id"], **row}
                for row in report["full_set"]["drift_rows"]
            ],
        )
    drift = report["full_set"]["drift"]
    print(f"records={drift['record_count']}")
    print(f"strict_drift={drift['strict_drift_count']}/{drift['record_count']}")
    print(f"forbidden_hit={drift['forbidden_hit_count']}")
    print(f"verified_bindings={report['integrity']['verified_binding_records']}")
    print(f"unverified_bindings={report['integrity']['unverified_binding_records']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
