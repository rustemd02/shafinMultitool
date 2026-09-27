#!/usr/bin/env python3
"""Calibration subset для DATA-009: детерминированный отбор кадров под независимый второй проход.

Правило отбора (без случайности): по каждой `strata_group` — первые `--per-group`
строки после сортировки по (`content_sha256` или `image_sha256`,
`package_record_id`); плюс явно перечисленные известные спорные записи
(`--extra RECORD_ID`), если они есть в очереди.

Выход контент-связанный: каждая строка несёт `package_record_id` и `image_sha256`,
поэтому ремонт record_id (см. identity-repair-20260927) не ломает манифест.
Человеческие метки не создаются и не подставляются — манифест это только список
кадров для второго blind-прохода; `human_gold` поднимается лишь adjudication
(DATA-011), не этим скриптом.

Байт-детерминизм: тот же вход → те же байты выхода (дат/случайности в файле нет).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

SCHEMA = "camera-calibration-subset-v1"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_subset(rows: list[dict], *, per_group: int, extras: list[str]) -> list[dict]:
    if per_group < 1:
        raise ValueError("per_group должен быть >= 1")
    picked: list[dict] = []
    seen: set[str] = set()
    groups = sorted({str(r.get("strata_group") or "ungrouped") for r in rows})
    for group in groups:
        group_rows = [r for r in rows if str(r.get("strata_group") or "ungrouped") == group]
        group_rows.sort(key=lambda r: (str(r.get("content_sha256") or r.get("image_sha256") or ""),
                                       str(r.get("package_record_id") or "")))
        for row in group_rows[:per_group]:
            rid = str(row.get("record_id") or "")
            if rid in seen:
                continue
            seen.add(rid)
            picked.append(_entry(row, pick_reason="group_sample"))
    by_id = {str(r.get("record_id") or ""): r for r in rows}
    for rid in extras:
        if rid in seen:
            continue
        row = by_id.get(rid)
        if row is None:
            raise ValueError(f"--extra {rid!r} отсутствует в очереди")
        seen.add(rid)
        picked.append(_entry(row, pick_reason="named_dispute"))
    return picked


def _entry(row: dict, *, pick_reason: str) -> dict:
    return {
        "record_id": row.get("record_id"),
        "package_record_id": row.get("package_record_id"),
        "image_sha256": row.get("image_sha256"),
        "content_sha256": row.get("content_sha256"),
        "strata_group": row.get("strata_group"),
        "source_family_id": row.get("source_family_id"),
        "pick_reason": pick_reason,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--queue", type=Path, required=True, help="очередь пилота (queue-v2-diverse.jsonl)")
    parser.add_argument("--out", type=Path, required=True, help="выходной JSON-манифест")
    parser.add_argument("--per-group", type=int, default=2, help="кадров на strata_group (по умолчанию 2)")
    parser.add_argument("--extra", action="append", default=[],
                        help="добавить известную спорную запись (record_id, можно повторять)")
    args = parser.parse_args(argv)

    rows = [json.loads(line) for line in args.queue.read_text(encoding="utf-8").splitlines()
            if line.strip()]
    if not rows:
        print(f"очередь пуста: {args.queue}", file=sys.stderr)
        return 2
    try:
        picked = select_subset(rows, per_group=args.per_group, extras=args.extra)
    except ValueError as exc:
        print(f"ОТКАЗ: {exc}", file=sys.stderr)
        return 2

    manifest = {
        "schema": SCHEMA,
        "purpose": ("DATA-009/DATA-011: независимый второй blind-проход calibration subset; "
                    "human_gold поднимается только adjudication (DATA-011), не этим манифестом"),
        "queue_file": args.queue.name,
        "queue_sha256": sha256_file(args.queue),
        "selection_rule": (f"per strata_group: first {args.per_group} by "
                           "(content_sha256, package_record_id); + named_dispute extras"),
        "independence": ("второй проход — отдельные store/details/session и annotator-id, "
                         "без показа первого прохода (blind); assisted-записи не считаются "
                         "независимыми ратерами"),
        "records": picked,
    }
    args.out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
    groups = {}
    for row in picked:
        groups[row["strata_group"]] = groups.get(row["strata_group"], 0) + 1
    print(f"OK: {len(picked)} запис(ей) -> {args.out}")
    print(f"  groups: {groups}")
    print(f"  queue sha256: {manifest['queue_sha256'][:12]}…")
    return 0


if __name__ == "__main__":
    sys.exit(main())
