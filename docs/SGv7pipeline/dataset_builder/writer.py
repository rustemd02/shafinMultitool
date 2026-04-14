from __future__ import annotations

import json
from pathlib import Path


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def read_jsonl(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            payload = line.strip()
            if not payload:
                continue
            rows.append(json.loads(payload))
    return rows


def write_jsonl(records: list[dict[str, object]], path: Path) -> None:
    _ensure_parent(path)
    with path.open("w", encoding="utf-8") as fh:
        for record in records:
            fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


def write_json(payload: dict[str, object], path: Path) -> None:
    _ensure_parent(path)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

