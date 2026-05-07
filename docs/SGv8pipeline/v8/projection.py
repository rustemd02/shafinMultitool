from __future__ import annotations

from typing import Any

try:
    from .contracts import ScenePlanIRRecord
except ImportError:  # pragma: no cover - direct script execution
    from contracts import ScenePlanIRRecord


def _actor_ref_for_index(index: int) -> str:
    if index == 1:
        return "first"
    if index == 2:
        return "second"
    if index == 3:
        return "third"
    return f"actor_ref_{index}"


def cir_to_scene_plan_ir(record: dict[str, Any]) -> ScenePlanIRRecord:
    scene_graph = record["scene_graph"]

    actor_id_to_ref: dict[str, str] = {}
    actors = []
    for index, actor in enumerate(scene_graph["actors"], start=1):
        labels = actor.get("labels", {})
        actor_ref = str(labels.get("ordinal") or _actor_ref_for_index(index))
        actor_id_to_ref[actor["id"]] = actor_ref
        actor_row = {
            "ref": actor_ref,
            "type": actor["type"],
        }
        if actor.get("name"):
            actor_row["name"] = actor["name"]
        actors.append(actor_row)

    object_id_to_ref: dict[str, str] = {}
    objects = []
    unmarked_index = 1
    for obj in scene_graph["objects"]:
        object_ref = obj["id"] if obj["id"].startswith("object_marked_") else f"object_slot_{unmarked_index}"
        if not obj["id"].startswith("object_marked_"):
            unmarked_index += 1
        object_id_to_ref[obj["id"]] = object_ref
        obj_row = {
            "ref": object_ref,
            "type": obj["type"],
            "relativePosition": obj["relative_position"],
        }
        if obj.get("name"):
            obj_row["name"] = obj["name"]
        if obj["id"].startswith("object_marked_"):
            obj_row["markedObjectID"] = obj["id"]
        objects.append(obj_row)

    beats = []
    for beat in scene_graph["beats"]:
        beat_row: dict[str, Any] = {
            "ref": beat["id"],
            "actions": [],
        }
        if beat.get("phase"):
            beat_row["phase"] = beat["phase"]
        if beat.get("min_duration") is not None:
            beat_row["minDuration"] = beat["min_duration"]
        for action in beat["actions"]:
            action_row = {
                "actorRef": actor_id_to_ref[action["actor_id"]],
                "type": action["type"],
                "resultingPose": action["resulting_pose"],
            }
            target_id = action.get("target_id")
            if target_id:
                action_row["targetRef"] = actor_id_to_ref.get(target_id) or object_id_to_ref[target_id]
            if action.get("direction"):
                action_row["direction"] = action["direction"]
            if action.get("modifier"):
                action_row["modifier"] = action["modifier"]
            if action.get("holding_object"):
                action_row["holdingObjectRef"] = object_id_to_ref[action["holding_object"]]
            if action.get("dialogue"):
                action_row["dialogue"] = action["dialogue"]
            if action["type"] == "described_action":
                payload = action["described_action"]
                action_row["fallbackText"] = payload["fallback_text"]
                action_row["sourceText"] = payload["canonical_text"]
            beat_row["actions"].append(action_row)
        beats.append(beat_row)

    relations = []
    for relation in scene_graph["spatial_relations"]:
        relations.append(
            {
                "ref": relation["id"],
                "subjectRef": actor_id_to_ref.get(relation["subject"]) or object_id_to_ref[relation["subject"]],
                "relation": relation["relation"],
                "objectRef": actor_id_to_ref.get(relation["object"]) or object_id_to_ref[relation["object"]],
            }
        )

    bindings = scene_graph["reference_bindings"]
    alias_map = {
        alias: actor_id_to_ref.get(target_id) or object_id_to_ref[target_id]
        for alias, target_id in bindings.get("alias_to_object_id", {}).items()
    }
    return {
        "actors": actors,
        "objects": objects,
        "beats": beats,
        "spatialRelations": relations,
        "referenceBindings": {
            "actorBindings": {actor_ref: actor_id for actor_id, actor_ref in actor_id_to_ref.items()},
            "markedObjectIDs": list(bindings.get("marked_object_ids", [])),
            "aliasToObjectRef": alias_map,
        },
    }
