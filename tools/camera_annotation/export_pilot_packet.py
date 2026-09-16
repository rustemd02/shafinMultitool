#!/usr/bin/env python3
"""Export the annotation pilot sample as a human-readable packet.

Reads the blinded pilot sample (pilot-sample-v1.jsonl) and writes a CSV and a
Markdown list that contain ONLY what an annotator may see: record id, case id,
mode, scenario, and advice. The adjudicator key and any expected verdict are
never included.

Votes are still cast through the existing append-only vote capture
(tools/camera_annotation/annotate_camera.py); this script only prepares the
packet.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def load_sample(path: Path) -> list[dict]:
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    records = load_sample(args.sample)
    if not records:
        raise SystemExit(f"no records in {args.sample}")
    forbidden = {"intended_verdict", "intended_reason", "focus"}
    for record in records:
        leaked = forbidden.intersection(record)
        if leaked:
            raise SystemExit(f"sample leaks adjudication fields: {sorted(leaked)}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.out_dir / "pilot-packet.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["record_id", "case_id", "mode", "scenario", "advice"])
        for record in records:
            writer.writerow([
                record["pilot_record_id"],
                record["case_id"],
                record["mode"],
                record["scenario"],
                record["advice"],
            ])

    markdown_path = args.out_dir / "pilot-packet.md"
    lines = [
        "# Annotation pilot v1 — packet",
        "",
        f"Записей: {len(records)}. Оценка каждого совета: `good` / `bad` / `abstain` по инструкции "
        "(`annotation-pilot-instructions.md`). Ключевой файл аннотатору недоступен.",
        "",
    ]
    for record in records:
        lines.append(f"## {record['pilot_record_id']} — {record['case_id']}")
        lines.append("")
        lines.append(f"- Режимы: {record['mode']}")
        lines.append(f"- Сценарий: {record['scenario']}")
        lines.append(f"- Совет: {record['advice']}")
        lines.append("")
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"WROTE {csv_path} and {markdown_path} ({len(records)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
