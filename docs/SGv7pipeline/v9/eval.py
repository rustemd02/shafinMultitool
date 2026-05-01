from __future__ import annotations

from typing import Any


def _safe_rate(numerator: int | float, denominator: int | float) -> float | None:
    if denominator <= 0:
        return None
    return float(numerator) / float(denominator)


def summarize_event_slice_metrics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(rows)
    if total == 0:
        return {
            "overall": {"case_count": 0},
            "structural": {
                "event_parse_rate": 0.0,
                "event_schema_valid_rate": 0.0,
                "event_actor_slot_structural_pass_rate": 0.0,
                "event_target_slot_structural_pass_rate": 0.0,
                "event_action_type_structural_pass_rate": 0.0,
                "event_beat_order_structural_pass_rate": 0.0,
                "patch_success_rate": 0.0,
                "compiler_repair_rate": 0.0,
            },
            "semantic": {
                "event_actor_slot_accuracy": None,
                "event_target_slot_accuracy": None,
                "event_action_type_accuracy": None,
                "event_beat_order_accuracy": None,
            },
            "degradation": {
                "targetless_event_repaired_rate": 0.0,
                "unknown_slot_blocked_rate": 0.0,
                "dropped_event_row_rate": 0.0,
                "targetless_event_repaired_count": 0,
                "unknown_slot_blocked_count": 0,
                "dropped_event_rows_total": 0,
                "input_event_rows_total": 0,
            },
        }

    parse_ok = sum(1 for row in rows if bool(row.get("event_parse_ok", False)))
    schema_ok = sum(1 for row in rows if bool(row.get("event_schema_valid", False)))
    actor_ok = sum(1 for row in rows if bool(row.get("event_actor_slot_structural_pass", False)))
    target_ok = sum(1 for row in rows if bool(row.get("event_target_slot_structural_pass", False)))
    action_ok = sum(1 for row in rows if bool(row.get("event_action_type_structural_pass", False)))
    beat_ok = sum(1 for row in rows if bool(row.get("event_beat_order_structural_pass", False)))
    patch_ok = sum(1 for row in rows if bool(row.get("patch_success", False)))
    repair_used = sum(1 for row in rows if bool(row.get("compiler_repair_applied", False)))

    semantic_total = sum(int(row.get("semantic_row_total", 0) or 0) for row in rows)
    semantic_actor_hits = sum(int(row.get("semantic_actor_hit_count", 0) or 0) for row in rows)
    semantic_target_hits = sum(int(row.get("semantic_target_hit_count", 0) or 0) for row in rows)
    semantic_action_hits = sum(int(row.get("semantic_action_hit_count", 0) or 0) for row in rows)
    semantic_beat_hits = sum(int(row.get("semantic_beat_hit_count", 0) or 0) for row in rows)

    targetless_cases = sum(1 for row in rows if bool(row.get("targetless_event_repaired", False)))
    unknown_slot_cases = sum(1 for row in rows if bool(row.get("unknown_slot_blocked", False)))
    dropped_rows_total = sum(int(row.get("dropped_event_row_count", 0) or 0) for row in rows)
    input_rows_total = sum(int(row.get("input_event_row_count", 0) or 0) for row in rows)

    return {
        "overall": {
            "case_count": total,
            "semantic_row_total": semantic_total,
        },
        "structural": {
            "event_parse_rate": parse_ok / total,
            "event_schema_valid_rate": schema_ok / total,
            "event_actor_slot_structural_pass_rate": actor_ok / total,
            "event_target_slot_structural_pass_rate": target_ok / total,
            "event_action_type_structural_pass_rate": action_ok / total,
            "event_beat_order_structural_pass_rate": beat_ok / total,
            "patch_success_rate": patch_ok / total,
            "compiler_repair_rate": repair_used / total,
        },
        "semantic": {
            "event_actor_slot_accuracy": _safe_rate(semantic_actor_hits, semantic_total),
            "event_target_slot_accuracy": _safe_rate(semantic_target_hits, semantic_total),
            "event_action_type_accuracy": _safe_rate(semantic_action_hits, semantic_total),
            "event_beat_order_accuracy": _safe_rate(semantic_beat_hits, semantic_total),
        },
        "degradation": {
            "targetless_event_repaired_rate": targetless_cases / total,
            "unknown_slot_blocked_rate": unknown_slot_cases / total,
            "dropped_event_row_rate": _safe_rate(dropped_rows_total, input_rows_total) or 0.0,
            "targetless_event_repaired_count": targetless_cases,
            "unknown_slot_blocked_count": unknown_slot_cases,
            "dropped_event_rows_total": dropped_rows_total,
            "input_event_rows_total": input_rows_total,
        },
    }
