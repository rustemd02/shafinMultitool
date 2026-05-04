from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any


CLUSTER_RULES: list[tuple[str, tuple[str, ...]]] = [
    ("dialogue_action", ("говорит", "спрашивает", "отвечает", "«", "\"")),
    ("put_pick", ("клад", "полож", "бер", "поднима")),
    ("collective", ("оба", "вместе", "двое")),
    ("reciprocal", ("навстреч", "друг другу")),
    ("stop_near", ("остан", "рядом", "около", " возле ", " у ")),
    ("temporal", ("потом", "затем", "после этого", "в этот момент")),
    ("unsupported_described", ("поправ", "улыба", "кива", "вздыха", "машет", "смотрит на экран")),
]


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def source_text(row: dict[str, Any]) -> str:
    for key in ("source_text", "input_text", "text", "prompt"):
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value
    return ""


def cluster_for(row: dict[str, Any], event_row: dict[str, Any] | None) -> str:
    text = source_text(row).lower()
    for cluster, needles in CLUSTER_RULES:
        if any(needle in text for needle in needles):
            return cluster
    if event_row:
        if int(event_row.get("chunk_missing_event_count", 0) or 0) > 0:
            return "coverage_missing"
        if not bool(event_row.get("event_target_slot_structural_pass", True)):
            return "target_slot"
    return "other"


def is_failed(event_row: dict[str, Any] | None) -> bool:
    if not event_row:
        return True
    if bool(event_row.get("compile_error")):
        return True
    if not bool(event_row.get("event_schema_valid", False)):
        return True
    if int(event_row.get("chunk_missing_event_count", 0) or 0) > 0:
        return True
    if event_row.get("playback_intent_success_pass") is False:
        return True
    semantic_total = int(event_row.get("semantic_row_total", 0) or 0)
    full_hits = int(event_row.get("semantic_full_row_hit_count", 0) or 0)
    return semantic_total > 0 and full_hits < semantic_total


def main() -> None:
    parser = argparse.ArgumentParser(description="Mine V9 hard cases from event eval artifacts.")
    parser.add_argument("--eval-cases", required=True, type=Path)
    parser.add_argument("--event-case-results", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--max-per-cluster", type=int, default=80)
    args = parser.parse_args()

    eval_rows = read_jsonl(args.eval_cases)
    event_rows = read_jsonl(args.event_case_results)
    event_by_id = {str(row.get("eval_case_id")): row for row in event_rows if row.get("eval_case_id")}

    clusters: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in eval_rows:
        eval_case_id = str(row.get("eval_case_id") or "")
        event_row = event_by_id.get(eval_case_id)
        if not is_failed(event_row):
            continue
        cluster = cluster_for(row, event_row)
        if len(clusters[cluster]) >= args.max_per_cluster:
            continue
        clusters[cluster].append(
            {
                "eval_case_id": eval_case_id,
                "cluster": cluster,
                "source_text": source_text(row),
                "event_metrics": event_row or {},
                "original_case": row,
            }
        )

    all_rows = [item for cluster_rows in clusters.values() for item in cluster_rows]
    write_jsonl(args.output_dir / "v9_hard_cases.jsonl", all_rows)
    manifest = {
        "cluster_counts": {cluster: len(rows) for cluster, rows in sorted(clusters.items())},
        "total": len(all_rows),
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "v9_hard_case_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
