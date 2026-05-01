from __future__ import annotations

from copy import deepcopy

from .contracts import EventTableRecord, PatchOpsRecord, SlotCatalogRecord, VerifierIssueRecord

TARGET_REQUIRED_ACTIONS = {"look_at", "pick_up", "open", "close", "approach", "put_down", "give", "pass_by", "stop"}


def apply_patch_ops(event_table: EventTableRecord, patch_ops: PatchOpsRecord) -> EventTableRecord:
    rows = [deepcopy(row) for row in event_table.get("rows", [])]
    row_by_id = {str(row.get("rowId")): row for row in rows}
    for op in patch_ops.get("ops", []):
        operation = str(op.get("op") or "").strip()
        row_id = str(op.get("rowId") or "").strip()
        if not row_id:
            continue
        if operation == "delete":
            row_by_id.pop(row_id, None)
            continue
        if operation == "add":
            if row_id in row_by_id:
                continue
            payload = deepcopy(op.get("value")) if isinstance(op.get("value"), dict) else {}
            payload["rowId"] = row_id
            row_by_id[row_id] = payload
            continue
        if operation == "replace":
            row = row_by_id.get(row_id)
            if row is None:
                continue
            field = str(op.get("field") or "").strip()
            if not field:
                continue
            row[field] = op.get("value")
    normalized_rows = list(row_by_id.values())
    normalized_rows.sort(key=lambda item: str(item.get("rowId") or ""))
    return {
        "contractVersion": event_table.get("contractVersion", "sg_v9_event_table_v1"),
        "rows": normalized_rows,
    }


def verify_and_repair_event_table(
    slot_catalog: SlotCatalogRecord,
    event_table: EventTableRecord,
    *,
    patch_ops: PatchOpsRecord | None = None,
) -> tuple[EventTableRecord, list[VerifierIssueRecord], list[str]]:
    current = deepcopy(event_table)
    reason_codes: list[str] = []
    if patch_ops and patch_ops.get("ops"):
        current = apply_patch_ops(current, patch_ops)
        reason_codes.append("v9.verifier_patch_applied")

    actor_slots = {str(item.get("slotId")) for item in slot_catalog.get("actorSlots", [])}
    object_slots = {str(item.get("slotId")) for item in slot_catalog.get("objectSlots", [])}
    beat_slots = {str(item.get("slotId")) for item in slot_catalog.get("beatSlots", [])}
    action_types = {str(item) for item in slot_catalog.get("actionTypes", [])}
    issues: list[VerifierIssueRecord] = []
    fixed_rows = []
    seen_row_ids: set[str] = set()

    for row in current.get("rows", []):
        row_id = str(row.get("rowId") or "").strip()
        if not row_id:
            issues.append(
                {
                    "code": "missing_row_id",
                    "rowId": "",
                    "details": "Event row has no rowId",
                    "fixable": False,
                }
            )
            continue
        if row_id in seen_row_ids:
            issues.append(
                {
                    "code": "duplicate_row_id",
                    "rowId": row_id,
                    "details": "Duplicate rowId was dropped",
                    "fixable": True,
                }
            )
            reason_codes.append("v9.duplicate_row_dropped")
            continue
        seen_row_ids.add(row_id)

        beat_slot = str(row.get("beatSlot") or "").strip()
        actor_slot = str(row.get("actorSlot") or "").strip()
        action_type = str(row.get("actionType") or "").strip()
        target_slot = str(row.get("targetSlot") or "").strip()
        holding_slot = str(row.get("holdingObjectSlot") or "").strip()
        row_copy = deepcopy(row)

        if beat_slot not in beat_slots:
            issues.append(
                {
                    "code": "unknown_beat_slot",
                    "rowId": row_id,
                    "details": f"Unknown beatSlot: {beat_slot}",
                    "fixable": True,
                }
            )
            reason_codes.append("v9.beat_slot_mismatch")
            row_copy["beatSlot"] = next(iter(beat_slots), "")

        if actor_slot not in actor_slots:
            issues.append(
                {
                    "code": "unknown_actor_slot",
                    "rowId": row_id,
                    "details": f"Unknown actorSlot: {actor_slot}",
                    "fixable": False,
                }
            )
            reason_codes.append("v9.unknown_slot_blocked")
            continue

        if action_type not in action_types:
            issues.append(
                {
                    "code": "unknown_action_type",
                    "rowId": row_id,
                    "details": f"Unknown actionType: {action_type}",
                    "fixable": True,
                }
            )
            reason_codes.append("v9.action_type_repaired")
            row_copy["actionType"] = "described_action"
            action_type = "described_action"

        if target_slot and target_slot not in actor_slots.union(object_slots):
            issues.append(
                {
                    "code": "unknown_target_slot",
                    "rowId": row_id,
                    "details": f"Unknown targetSlot: {target_slot}",
                    "fixable": True,
                }
            )
            reason_codes.append("v9.target_slot_repaired")
            row_copy.pop("targetSlot", None)
            target_slot = ""

        if holding_slot and holding_slot not in object_slots:
            issues.append(
                {
                    "code": "unknown_holding_object_slot",
                    "rowId": row_id,
                    "details": f"Unknown holdingObjectSlot: {holding_slot}",
                    "fixable": True,
                }
            )
            reason_codes.append("v9.holding_slot_repaired")
            row_copy.pop("holdingObjectSlot", None)

        if action_type in TARGET_REQUIRED_ACTIONS and not target_slot:
            issues.append(
                {
                    "code": "target_required_missing",
                    "rowId": row_id,
                    "details": "Action requires targetSlot",
                    "fixable": True,
                }
            )
            reason_codes.append("v9.targetless_event_repaired")
            row_copy["actionType"] = "stand"

        if row_copy.get("actionType") == "described_action":
            desc_text = str(row_copy.get("describedActionText") or "").strip()
            src_text = str(row_copy.get("sourceSpan") or "").strip()
            if not desc_text and not src_text:
                issues.append(
                    {
                        "code": "described_action_without_text",
                        "rowId": row_id,
                        "details": "described_action should carry text",
                        "fixable": True,
                    }
                )
                reason_codes.append("v9.described_text_repaired")
                row_copy["describedActionText"] = "described_action"

        fixed_rows.append(row_copy)

    repaired = {
        "contractVersion": current.get("contractVersion", "sg_v9_event_table_v1"),
        "rows": fixed_rows,
    }
    unique_reasons: list[str] = []
    for reason in reason_codes:
        if reason not in unique_reasons:
            unique_reasons.append(reason)
    return repaired, issues, unique_reasons
