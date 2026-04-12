from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from cir_contract.contracts.cir_types import CIRRecord, SceneScriptRecord


_ID_NUMERIC_SUFFIX_RE = re.compile(r"_(\d+)$")


def _numeric_suffix(value: str) -> tuple[int, str]:
    match = _ID_NUMERIC_SUFFIX_RE.search(value)
    if match:
        return int(match.group(1)), value
    return 10**9, value


def _object_sort_key(object_node: dict[str, Any]) -> tuple[int, str]:
    object_id = object_node["id"]
    if object_id.startswith("object_marked_"):
        return 0, object_id
    index, full = _numeric_suffix(object_id)
    return 1, f"{index:09d}:{full}"


def _sorted_scene_graph(scene_graph: dict[str, Any]) -> dict[str, Any]:
    beats = []
    for beat in sorted(scene_graph["beats"], key=lambda item: _numeric_suffix(item["id"])):
        actions = sorted(
            beat["actions"],
            key=lambda action: (action["semantics"]["chronology_rank"], _numeric_suffix(action["id"])),
        )
        cloned_beat = dict(beat)
        cloned_beat["actions"] = actions
        beats.append(cloned_beat)

    return {
        "actors": sorted(scene_graph["actors"], key=lambda item: _numeric_suffix(item["id"])),
        "objects": sorted(scene_graph["objects"], key=_object_sort_key),
        "beats": beats,
        "spatial_relations": sorted(scene_graph["spatial_relations"], key=lambda item: _numeric_suffix(item["id"])),
        "reference_bindings": scene_graph["reference_bindings"],
        "must_preserve": sorted(scene_graph["must_preserve"]),
    }


def structural_hash(record: CIRRecord | dict[str, Any]) -> str:
    canonical = _sorted_scene_graph(record["scene_graph"])
    payload = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:8]


def expected_sample_id(record: CIRRecord | dict[str, Any]) -> str:
    return (
        f"{record['pattern_name']}__{record['source_variant_key']}__"
        f"s{record['graph_seed']}__{structural_hash(record)}"
    )


def _strip_none_fields(payload: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in payload.items() if value is not None}


def serialize_to_scenescript(
    record: CIRRecord | dict[str, Any],
    *,
    original_description: str,
) -> SceneScriptRecord:
    projection = record["runtime_projection"]
    if projection["top_level_optional_policy"] != "omit_all":
        raise ValueError("sg_v7_cir_v1 requires runtime_projection.top_level_optional_policy=omit_all")
    if projection["beat_optional_policy"] != "preserve_if_present_else_omit":
        raise ValueError("sg_v7_cir_v1 requires runtime_projection.beat_optional_policy=preserve_if_present_else_omit")
    if projection["described_action_source_text_policy"] != "canonical_text_to_sourceText":
        raise ValueError("sg_v7_cir_v1 requires canonical_text_to_sourceText policy")

    scene_graph = _sorted_scene_graph(record["scene_graph"])

    actors = [
        _strip_none_fields(
            {
                "id": actor["id"],
                "type": actor["type"],
                "name": actor.get("name"),
            }
        )
        for actor in scene_graph["actors"]
    ]

    objects = [
        _strip_none_fields(
            {
                "id": obj["id"],
                "type": obj["type"],
                "name": obj.get("name"),
                "relativePosition": obj["relative_position"],
            }
        )
        for obj in scene_graph["objects"]
    ]

    beats = []
    for beat in scene_graph["beats"]:
        serialized_actions = []
        for action in beat["actions"]:
            serialized_action = {
                "id": action["id"],
                "actorId": action["actor_id"],
                "type": action["type"],
                "target": action.get("target_id"),
                "direction": action.get("direction"),
                "modifier": action.get("modifier"),
                "resultingPose": action["resulting_pose"],
                "holdingObject": action.get("holding_object"),
                "dialogue": action.get("dialogue"),
            }
            if action["type"] == "described_action":
                described_action = action["described_action"]
                serialized_action["fallbackText"] = described_action["fallback_text"]
                serialized_action["sourceText"] = described_action["canonical_text"]
            serialized_actions.append(_strip_none_fields(serialized_action))

        serialized_beat: dict[str, Any] = {
            "id": beat["id"],
            "actions": serialized_actions,
        }
        if "camera" in beat and beat["camera"] is not None:
            camera = {
                "shotType": beat["camera"]["shot_type"],
                "movement": beat["camera"].get("movement"),
                "target": beat["camera"].get("target"),
            }
            serialized_beat["camera"] = _strip_none_fields(camera)
        if "min_duration" in beat and beat["min_duration"] is not None:
            serialized_beat["minDuration"] = beat["min_duration"]
        beats.append(serialized_beat)

    relations = [
        {
            "id": relation["id"],
            "subject": relation["subject"],
            "relation": relation["relation"],
            "object": relation["object"],
        }
        for relation in scene_graph["spatial_relations"]
    ]

    return {
        "actors": actors,
        "objects": objects,
        "beats": beats,
        "spatialRelations": relations,
        "originalDescription": original_description,
    }


def dump_scenescript_json(record: CIRRecord | dict[str, Any], *, original_description: str) -> str:
    payload = serialize_to_scenescript(record, original_description=original_description)
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
