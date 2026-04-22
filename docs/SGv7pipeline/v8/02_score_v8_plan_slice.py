#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from eval import summarize_plan_slice_metrics


def _read_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if not raw:
                continue
            payload = json.loads(raw)
            if isinstance(payload, dict):
                rows.append(payload)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Score v8 ScenePlanIR slice metrics from JSONL rows")
    parser.add_argument("--input-jsonl", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    rows = _read_jsonl(args.input_jsonl)
    metrics = summarize_plan_slice_metrics(rows)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
