from __future__ import annotations

import json
from pathlib import Path


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def stable_sort_records(records: list[dict]) -> list[dict]:
    return sorted(
        records,
        key=lambda record: (
            record["difficulty_bucket"],
            record["pattern_name"],
            record["source_variant_key"],
            record["graph_seed"],
            record["sample_id"],
        ),
    )


def write_jsonl(records: list[dict], path: Path) -> None:
    _ensure_parent(path)
    with path.open("w", encoding="utf-8") as fh:
        for record in stable_sort_records(records):
            fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


def write_manifest(manifest: dict[str, object], path: Path) -> None:
    _ensure_parent(path)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, sort_keys=True, indent=2)
        fh.write("\n")

