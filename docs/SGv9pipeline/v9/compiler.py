from __future__ import annotations

from collections import defaultdict
from pathlib import Path
from typing import Any
import sys

ROOT = Path(__file__).resolve().parents[1]
SGV8_ROOT = ROOT.parent / "SGv8pipeline"
for path in (ROOT, SGV8_ROOT):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from v8.compiler import compile_scene_plan_ir_with_notes


def event_table_to_plan_ir(
    *,
    slot_catalog: dict[str, Any],
    event_table: dict[str, Any],
) -> dict[str, Any]:
    actor_slots = list(slot_catalog.get("actorSlots", []))
    object_slots = list(slot_catalog.get("objectSlots", []))
    beat_slots = list(slot_catalog.get("beatSlots", []))

    actor_slot_map = {str(item.get("slotId")): item for item in actor_slots}
    object_slot_map = {str(item.get("slotId")): item for item in object_slots}
    beat_slot_map = {str(item.get("slotId")): item for item in beat_slots}

    actors = [
        {
            "ref": str(slot.get("ref") or f"actor_ref_{index + 1}"),
            "type": str(slot.get("type") or "human"),
            **({"name": str(slot.get("name"))} if slot.get("name") else {}),
        }
        for index, slot in enumerate(actor_slots)
    ]
    objects = []
    for slot in object_slots:
        object_row: dict[str, Any] = {
            "ref": str(slot.get("ref") or str(slot.get("slotId") or "")),
            "type": str(slot.get("type") or "generic"),
            "relativePosition": str(slot.get("relativePosition") or "unknown"),
        }
        if slot.get("name"):
            object_row["name"] = str(slot["name"])
        if slot.get("markedObjectID"):
            object_row["markedObjectID"] = str(slot["markedObjectID"])
        objects.append(object_row)

    actor_slot_to_ref = {str(slot.get("slotId")): str(slot.get("ref") or "") for slot in actor_slots}
    object_slot_to_ref = {
        str(slot.get("slotId")): str(slot.get("ref") or str(slot.get("slotId") or ""))
        for slot in object_slots
    }
    rows_by_beat: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in event_table.get("rows", []):
        beat_slot = str(row.get("beatSlot") or "")
        if beat_slot:
            rows_by_beat[beat_slot].append(row)

    beats: list[dict[str, Any]] = []
    for index, beat_slot in enumerate(beat_slots, start=1):
        beat_slot_id = str(beat_slot.get("slotId") or "")
        beat_rows = rows_by_beat.get(beat_slot_id, [])
        if not beat_rows:
            continue
        actions: list[dict[str, Any]] = []
        for row in sorted(beat_rows, key=lambda item: str(item.get("rowId") or "")):
            actor_ref = actor_slot_to_ref.get(str(row.get("actorSlot") or ""), "")
            if not actor_ref:
                continue
            action_row: dict[str, Any] = {
                "actorRef": actor_ref,
                "type": str(row.get("actionType") or "stand"),
            }
            target_slot = str(row.get("targetSlot") or "")
            if target_slot:
                target_ref = actor_slot_to_ref.get(target_slot) or object_slot_to_ref.get(target_slot)
                if target_ref:
                    action_row["targetRef"] = target_ref
            holding_slot = str(row.get("holdingObjectSlot") or "")
            if holding_slot:
                holding_ref = object_slot_to_ref.get(holding_slot)
                if holding_ref:
                    action_row["holdingObjectRef"] = holding_ref
            dialogue_text = str(row.get("dialogueText") or "").strip()
            if dialogue_text:
                action_row["dialogue"] = dialogue_text
            described_text = str(row.get("describedActionText") or "").strip()
            if described_text:
                action_row["fallbackText"] = described_text
                action_row["sourceText"] = described_text
            actions.append(action_row)
        if not actions:
            continue
        beat_row: dict[str, Any] = {
            "ref": str(beat_slot.get("beatRef") or f"beat_{index}"),
            "actions": actions,
        }
        if beat_slot.get("phaseHint"):
            beat_row["phase"] = str(beat_slot["phaseHint"])
        if beat_slot.get("minDuration") is not None:
            beat_row["minDuration"] = float(beat_slot["minDuration"])
        beats.append(beat_row)

    alias_to_object = {
        str(slot.get("name")).lower(): str(slot.get("ref"))
        for slot in object_slots
        if slot.get("name") and slot.get("ref")
    }
    marked_ids = sorted(
        {
            str(slot.get("markedObjectID") or slot.get("ref"))
            for slot in object_slots
            if str(slot.get("ref") or "").startswith("object_marked_")
        }
    )
    return {
        "actors": actors,
        "objects": objects,
        "beats": beats,
        "spatialRelations": [],
        "referenceBindings": {
            "actorBindings": {str(actor["ref"]): f"actor_{index + 1}" for index, actor in enumerate(actors)},
            "markedObjectIDs": marked_ids,
            "aliasToObjectRef": alias_to_object,
        },
    }


def compile_event_table_to_script(
    *,
    slot_catalog: dict[str, Any],
    event_table: dict[str, Any],
    source_text: str,
) -> tuple[dict[str, Any], list[str]]:
    plan_ir = event_table_to_plan_ir(slot_catalog=slot_catalog, event_table=event_table)
    compiled, compile_notes = compile_scene_plan_ir_with_notes(plan_ir, original_description=source_text)
    return compiled, compile_notes
