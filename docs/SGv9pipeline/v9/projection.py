from __future__ import annotations

from typing import Any

from .contracts import EventTableRecord, SlotCatalogRecord

SUPPORTED_ACTION_TYPES = {
    "walk",
    "run",
    "approach",
    "pass_by",
    "enter",
    "exit",
    "stand",
    "sit",
    "lie_down",
    "stop",
    "turn",
    "crouch",
    "look_at",
    "pick_up",
    "put_down",
    "open",
    "close",
    "give",
    "talk",
    "described_action",
}


def _actor_ref_for_index(index: int) -> str:
    if index == 1:
        return "first"
    if index == 2:
        return "second"
    if index == 3:
        return "third"
    return f"actor_ref_{index}"


def _object_ref(object_id: str, next_slot_index: int) -> tuple[str, int]:
    if object_id.startswith("object_marked_"):
        return object_id, next_slot_index
    return f"object_slot_{next_slot_index}", next_slot_index + 1


def cir_to_v9_slot_catalog(record: dict[str, Any]) -> SlotCatalogRecord:
    scene_graph = record["scene_graph"]
    actor_slots: list[dict[str, Any]] = []
    object_slots: list[dict[str, Any]] = []
    beat_slots: list[dict[str, Any]] = []
    marked_object_slots: list[str] = []
    relation_hints: list[dict[str, str]] = []
    action_types: set[str] = set(SUPPORTED_ACTION_TYPES)

    actor_id_to_slot: dict[str, str] = {}
    for index, actor in enumerate(scene_graph.get("actors", []), start=1):
        actor_ref = str(actor.get("labels", {}).get("ordinal") or _actor_ref_for_index(index))
        slot_id = f"actor_slot_{index}"
        actor_id_to_slot[str(actor["id"])] = slot_id
        row: dict[str, Any] = {
            "slotId": slot_id,
            "ref": actor_ref,
            "type": str(actor.get("type") or "human"),
        }
        if actor.get("name"):
            row["name"] = str(actor["name"])
        actor_slots.append(row)

    object_id_to_slot: dict[str, str] = {}
    next_object_slot = 1
    for object_index, obj in enumerate(scene_graph.get("objects", []), start=1):
        object_id = str(obj["id"])
        object_ref, next_object_slot = _object_ref(object_id, next_object_slot)
        slot_id = f"object_slot_{object_index}"
        object_id_to_slot[object_id] = slot_id
        row: dict[str, Any] = {
            "slotId": slot_id,
            "ref": object_ref,
            "type": str(obj.get("type") or "generic"),
            "relativePosition": str(obj.get("relative_position") or "unknown"),
        }
        if obj.get("name"):
            row["name"] = str(obj["name"])
        if object_ref.startswith("object_marked_"):
            row["markedObjectID"] = object_ref
            marked_object_slots.append(slot_id)
        object_slots.append(row)

    for beat_index, beat in enumerate(scene_graph.get("beats", []), start=1):
        beat_slot = f"beat_slot_{beat_index}"
        beat_row: dict[str, Any] = {
            "slotId": beat_slot,
            "beatRef": str(beat.get("id") or beat_slot),
            "order": beat_index,
        }
        if beat.get("phase"):
            beat_row["phaseHint"] = str(beat["phase"])
        if beat.get("min_duration") is not None:
            beat_row["minDuration"] = float(beat["min_duration"])
        beat_slots.append(beat_row)
        for action in beat.get("actions", []):
            action_type = str(action.get("type") or "").strip()
            if action_type:
                action_types.add(action_type)

    for relation in scene_graph.get("spatial_relations", []):
        subject_id = str(relation.get("subject") or "")
        object_id = str(relation.get("object") or "")
        subject_slot = actor_id_to_slot.get(subject_id) or object_id_to_slot.get(subject_id)
        object_slot = actor_id_to_slot.get(object_id) or object_id_to_slot.get(object_id)
        if not subject_slot or not object_slot:
            continue
        relation_hints.append(
            {
                "subjectSlot": subject_slot,
                "relation": str(relation.get("relation") or "near"),
                "objectSlot": object_slot,
            }
        )

    return {
        "contractVersion": "sg_v9_slot_catalog_v1",
        "actorSlots": actor_slots,
        "objectSlots": object_slots,
        "markedObjectSlots": sorted(set(marked_object_slots)),
        "beatSlots": beat_slots,
        "actionTypes": sorted(action_types),
        "relationHints": relation_hints,
    }


def cir_to_v9_event_table(record: dict[str, Any], slot_catalog: SlotCatalogRecord) -> EventTableRecord:
    scene_graph = record["scene_graph"]
    actor_slots = slot_catalog.get("actorSlots", [])
    object_slots = slot_catalog.get("objectSlots", [])
    beat_slots = slot_catalog.get("beatSlots", [])

    actor_id_to_slot: dict[str, str] = {}
    for index, actor in enumerate(scene_graph.get("actors", []), start=1):
        if index - 1 < len(actor_slots):
            actor_id_to_slot[str(actor["id"])] = str(actor_slots[index - 1]["slotId"])

    object_id_to_slot: dict[str, str] = {}
    for index, obj in enumerate(scene_graph.get("objects", []), start=1):
        if index - 1 < len(object_slots):
            object_id_to_slot[str(obj["id"])] = str(object_slots[index - 1]["slotId"])

    rows: list[dict[str, Any]] = []
    row_index = 1
    for beat_index, beat in enumerate(scene_graph.get("beats", []), start=1):
        beat_slot = str(beat_slots[beat_index - 1]["slotId"]) if beat_index - 1 < len(beat_slots) else f"beat_slot_{beat_index}"
        for action in beat.get("actions", []):
            actor_slot = actor_id_to_slot.get(str(action.get("actor_id") or ""))
            if not actor_slot:
                continue
            row: dict[str, Any] = {
                "rowId": f"row_{row_index}",
                "beatSlot": beat_slot,
                "actorSlot": actor_slot,
                "actionType": str(action.get("type") or "stand"),
                "confidence": 1.0,
            }
            target_id = str(action.get("target_id") or "").strip()
            if target_id:
                target_slot = actor_id_to_slot.get(target_id) or object_id_to_slot.get(target_id)
                if target_slot:
                    row["targetSlot"] = target_slot
            holding_object = str(action.get("holding_object") or "").strip()
            if holding_object:
                holding_slot = object_id_to_slot.get(holding_object)
                if holding_slot:
                    row["holdingObjectSlot"] = holding_slot
            if action.get("dialogue"):
                row["dialogueText"] = str(action["dialogue"])
            if str(action.get("type") or "") == "described_action":
                described_payload = action.get("described_action") if isinstance(action.get("described_action"), dict) else {}
                canonical_text = str(described_payload.get("canonical_text") or action.get("source_text") or "").strip()
                if canonical_text:
                    row["describedActionText"] = canonical_text
            rows.append(row)
            row_index += 1

    return {
        "contractVersion": "sg_v9_event_table_v1",
        "rows": rows,
    }
