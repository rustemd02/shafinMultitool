#!/usr/bin/env python3
"""I/O helpers for Camera Analysis eval harness."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Iterable, List


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        rows.append(json.loads(line))
    return rows


def write_jsonl(path: Path, rows: Iterable[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    materialized = [json.dumps(row, ensure_ascii=False, sort_keys=True) for row in rows]
    path.write_text("\n".join(materialized) + ("\n" if materialized else ""), encoding="utf-8")


def resolve_manifest_path(bundle_dir: Path) -> Path:
    primary = bundle_dir / "eval_bundle_manifest.json"
    if primary.exists():
        return primary
    fallback = bundle_dir / "example_eval_bundle_manifest.json"
    if fallback.exists():
        return fallback
    raise FileNotFoundError(
        "manifest not found. Expected one of: "
        f"{primary.as_posix()}, {fallback.as_posix()}"
    )


def resolve_golden_cases_path(bundle_dir: Path) -> Path:
    primary = bundle_dir / "golden_cases.jsonl"
    if primary.exists():
        return primary
    fallback = bundle_dir / "example_golden_cases.jsonl"
    if fallback.exists():
        return fallback
    raise FileNotFoundError(
        "golden cases not found. Expected one of: "
        f"{primary.as_posix()}, {fallback.as_posix()}"
    )


def load_bundle(bundle_dir: Path) -> Dict[str, Any]:
    manifest_path = resolve_manifest_path(bundle_dir)
    cases_path = resolve_golden_cases_path(bundle_dir)
    manifest = read_json(manifest_path)
    cases = read_jsonl(cases_path)
    return {
        "manifest": manifest,
        "cases": cases,
        "manifest_path": manifest_path,
        "cases_path": cases_path,
    }


def output_map_from_jsonl(path: Path) -> Dict[str, Dict[str, Any]]:
    records = read_jsonl(path)
    by_case: Dict[str, Dict[str, Any]] = {}
    for row in records:
        case_id = row.get("eval_case_id")
        if not isinstance(case_id, str) or not case_id:
            raise ValueError(f"record in {path.as_posix()} has invalid eval_case_id: {row!r}")
        payload = row.get("output")
        if isinstance(payload, dict):
            by_case[case_id] = payload
        else:
            by_case[case_id] = {
                k: v for k, v in row.items() if k not in {"eval_case_id", "mode_id"}
            }
    return by_case
