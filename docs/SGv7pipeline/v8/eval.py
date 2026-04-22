from __future__ import annotations

from typing import Any


def summarize_plan_slice_metrics(rows: list[dict[str, Any]]) -> dict[str, float]:
    total = len(rows)
    if total == 0:
        return {
            "plan_parse_rate": 0.0,
            "plan_reference_binding_accuracy": 0.0,
            "plan_beat_integrity_accuracy": 0.0,
        }

    parsed = sum(1 for row in rows if bool(row.get("plan_parse_ok", False)))
    reference_ok = sum(1 for row in rows if bool(row.get("plan_reference_binding_pass", False)))
    beat_ok = sum(1 for row in rows if bool(row.get("plan_beat_integrity_pass", False)))

    return {
        "plan_parse_rate": parsed / total,
        "plan_reference_binding_accuracy": reference_ok / total,
        "plan_beat_integrity_accuracy": beat_ok / total,
    }
