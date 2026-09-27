#!/usr/bin/env python3
"""Тесты calibration-subset builder (DATA-009 prep): детерминизм, квоты, контент-связность."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

import build_calibration_subset as bcs  # noqa: E402


def make_rows() -> list[dict]:
    rows = []
    for group in ("composition", "light", "goodframe"):
        for i in range(3):
            rows.append({
                "record_id": f"pilot23-{group}-{i + 1:02d}",
                "package_record_id": f"photo__fixture__{group}_{i}",
                "image_sha256": f"{group[0] * 2}{i:062x}",
                "content_sha256": f"{group[0] * 2}{i:062x}",
                "strata_group": group,
                "source_family_id": "fixture",
            })
    return rows


def test_selection_is_deterministic_and_quota_bound():
    rows = make_rows()
    first = bcs.select_subset(rows, per_group=2, extras=[])
    second = bcs.select_subset(list(reversed(rows)), per_group=2, extras=[])
    assert first == second  # порядок входа не влияет
    assert len(first) == 6
    by_group: dict[str, int] = {}
    for row in first:
        by_group[row["strata_group"]] = by_group.get(row["strata_group"], 0) + 1
        assert row["pick_reason"] == "group_sample"
    assert by_group == {"composition": 2, "light": 2, "goodframe": 2}


def test_named_extras_are_added_once_and_must_exist():
    rows = make_rows()
    picked = bcs.select_subset(rows, per_group=1, extras=["pilot23-composition-03", "pilot23-composition-03"])
    extras = [r for r in picked if r["pick_reason"] == "named_dispute"]
    assert [r["record_id"] for r in extras] == ["pilot23-composition-03"]
    with pytest.raises(ValueError):
        bcs.select_subset(rows, per_group=1, extras=["pilot23-missing-99"])


def test_subset_survives_record_id_rename(tmp_path: Path):
    """Ремонт идентичности меняет record_id — манифест обязан ссылаться на контент."""
    rows = make_rows()
    base = bcs.select_subset(rows, per_group=1, extras=[])
    renamed = [dict(r, record_id=r["record_id"] + "-renamed") for r in rows]
    after = bcs.select_subset(renamed, per_group=1, extras=[])
    assert [r["image_sha256"] for r in base] == [r["image_sha256"] for r in after]
    assert [r["package_record_id"] for r in base] == [r["package_record_id"] for r in after]


def test_cli_writes_byte_identical_manifest(tmp_path: Path):
    queue = tmp_path / "queue.jsonl"
    queue.write_text("".join(json.dumps(r) + "\n" for r in make_rows()), encoding="utf-8")
    out_a = tmp_path / "a.json"
    out_b = tmp_path / "b.json"
    assert bcs.main(["--queue", str(queue), "--out", str(out_a), "--per-group", "2"]) == 0
    assert bcs.main(["--queue", str(queue), "--out", str(out_b), "--per-group", "2"]) == 0
    assert out_a.read_bytes() == out_b.read_bytes()
    manifest = json.loads(out_a.read_text(encoding="utf-8"))
    assert manifest["schema"] == bcs.SCHEMA
    assert len(manifest["records"]) == 6
    assert manifest["queue_sha256"]
