from __future__ import annotations

from typing import Any

try:
    from .contracts import ScenePlanIRRecord
except ImportError:  # pragma: no cover - direct script execution
    from contracts import ScenePlanIRRecord

_TARGET_REQUIRED_TYPES = {"look_at", "pick_up", "open", "close", "approach", "put_down", "give", "pass_by", "stop"}


class ScenePlanCompileError(ValueError):
    pass


def _default_pose(action_type: str) -> str:
    if action_type in {"walk", "approach", "pass_by", "enter", "exit"}:
        return "walking"
    if action_type == "run":
        return "running"
    if action_type == "sit":
        return "sitting"
    if action_type == "lie_down":
        return "lying"
    if action_type == "crouch":
        return "crouching"
    return "standing"


def compile_scene_plan_ir(plan: ScenePlanIRRecord, *, original_description: str) -> dict[str, Any]:
    actor_bindings = dict(plan.get("referenceBindings", {}).get("actorBindings", {}))
    if not actor_bindings:
        actor_bindings = {
            actor["ref"]: f"actor_{index}"
            for index, actor in enumerate(plan["actors"], start=1)
        }
    object_bindings: dict[str, str] = {}
    next_object_index = 1
    for obj in plan["objects"]:
        object_ref = obj["ref"]
        if object_ref.startswith("object_marked_"):
            object_bindings[object_ref] = obj.get("markedObjectID", object_ref)
        else:
            object_bindings[object_ref] = f"object_{next_object_index}"
            next_object_index += 1

    actors = []
    for actor in plan["actors"]:
        row: dict[str, Any] = {
            "id": actor_bindings[actor["ref"]],
            "type": actor["type"],
        }
        if actor.get("name"):
            row["name"] = actor["name"]
        actors.append(row)

    objects = []
    for obj in plan["objects"]:
        row: dict[str, Any] = {
            "id": object_bindings[obj["ref"]],
            "type": obj["type"],
            "relativePosition": obj["relativePosition"],
        }
        if obj.get("name"):
            row["name"] = obj["name"]
        objects.append(row)

    beats = []
    for beat_index, beat in enumerate(plan["beats"], start=1):
        if not beat.get("actions"):
            raise ScenePlanCompileError(f"Beat {beat.get('ref', beat_index)} has no actions")
        actions = []
        for action_index, action in enumerate(beat["actions"], start=1):
            actor_ref = action["actorRef"]
            if actor_ref not in actor_bindings:
                raise ScenePlanCompileError(f"Unknown actorRef: {actor_ref}")
            target_ref = action.get("targetRef")
            target_id = None
            if target_ref:
                target_id = actor_bindings.get(target_ref) or object_bindings.get(target_ref)
            if action["type"] in _TARGET_REQUIRED_TYPES and not target_id:
                raise ScenePlanCompileError(f"Missing targetRef for required action type: {action['type']}")
            holding_object_ref = action.get("holdingObjectRef")
            holding_object_id = object_bindings.get(holding_object_ref) if holding_object_ref else None
            action_row: dict[str, Any] = {
                "id": f"action_{beat_index}_{action_index}",
                "actorId": actor_bindings[actor_ref],
                "type": action["type"],
                "resultingPose": action.get("resultingPose", _default_pose(action["type"])),
            }
            if target_id:
                action_row["target"] = target_id
            if action.get("direction"):
                action_row["direction"] = action["direction"]
            if action.get("modifier"):
                action_row["modifier"] = action["modifier"]
            if holding_object_id:
                action_row["holdingObject"] = holding_object_id
            if action.get("dialogue"):
                action_row["dialogue"] = action["dialogue"]
            if action.get("fallbackText"):
                action_row["fallbackText"] = action["fallbackText"]
            if action.get("sourceText"):
                action_row["sourceText"] = action["sourceText"]
            actions.append(action_row)
        beat_row: dict[str, Any] = {
            "id": beat.get("ref", f"beat_{beat_index}"),
            "actions": actions,
        }
        if beat.get("minDuration") is not None:
            beat_row["minDuration"] = beat["minDuration"]
        beats.append(beat_row)

    relations = []
    for index, relation in enumerate(plan.get("spatialRelations", []), start=1):
        subject_id = actor_bindings.get(relation["subjectRef"]) or object_bindings.get(relation["subjectRef"])
        object_id = actor_bindings.get(relation["objectRef"]) or object_bindings.get(relation["objectRef"])
        if not subject_id or not object_id:
            raise ScenePlanCompileError(f"Unknown spatial relation refs: {relation}")
        relations.append(
            {
                "id": relation.get("ref", f"rel_{index}"),
                "subject": subject_id,
                "relation": relation["relation"],
                "object": object_id,
            }
        )

    return {
        "actors": actors,
        "objects": objects,
        "beats": beats,
        "spatialRelations": relations,
        "originalDescription": original_description,
    }
