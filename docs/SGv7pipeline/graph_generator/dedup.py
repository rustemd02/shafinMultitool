from __future__ import annotations

import copy
import hashlib
import json
import re
from collections import Counter
from typing import Any


_ID_NUMERIC_SUFFIX_RE = re.compile(r"_(\d+)$")


def _numeric_suffix(value: str) -> tuple[int, str]:
    match = _ID_NUMERIC_SUFFIX_RE.search(value)
    if match:
        return int(match.group(1)), value
    return 10**9, value


def _sorted_actions(actions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(actions, key=lambda action: (action["semantics"]["chronology_rank"], _numeric_suffix(action["id"])))


def _sorted_scene_graph(scene_graph: dict[str, Any]) -> dict[str, Any]:
    beats = []
    for beat in sorted(scene_graph["beats"], key=lambda item: _numeric_suffix(item["id"])):
        cloned = copy.deepcopy(beat)
        cloned["actions"] = _sorted_actions(cloned["actions"])
        beats.append(cloned)

    def object_sort_key(node: dict[str, Any]) -> tuple[int, str]:
        if node["marker_binding"]["kind"] == "marked":
            return 0, node["name"]
        index, full = _numeric_suffix(node["id"])
        return 1, f"{index:09d}:{full}"

    return {
        "actors": sorted(copy.deepcopy(scene_graph["actors"]), key=lambda item: _numeric_suffix(item["id"])),
        "objects": sorted(copy.deepcopy(scene_graph["objects"]), key=object_sort_key),
        "beats": beats,
        "spatial_relations": sorted(
            copy.deepcopy(scene_graph["spatial_relations"]),
            key=lambda item: (_numeric_suffix(item["id"]), item["relation"], item["subject"], item["object"]),
        ),
        "reference_bindings": copy.deepcopy(scene_graph["reference_bindings"]),
        "must_preserve": sorted(copy.deepcopy(scene_graph["must_preserve"])),
    }


def _iter_object_references(scene_graph: dict[str, Any]) -> list[tuple[str, str, str]]:
    refs: list[tuple[str, str, str]] = []
    for beat_index, beat in enumerate(scene_graph["beats"]):
        for action_index, action in enumerate(beat["actions"]):
            if action.get("target_id") is not None:
                refs.append((action["target_id"], f"target:{beat_index}:{action_index}:{action['type']}", "target"))
            if action.get("holding_object") is not None:
                refs.append((action["holding_object"], f"holding:{beat_index}:{action_index}:{action['type']}", "holding"))
    for relation_index, relation in enumerate(scene_graph["spatial_relations"]):
        refs.append((relation["object"], f"relation:{relation_index}:{relation['relation']}", "relation"))
        if relation["subject"].startswith("object_") or relation["subject"].startswith("object_marked_"):
            refs.append((relation["subject"], f"subject_relation:{relation_index}:{relation['relation']}", "relation_subject"))
    return refs


def _first_usage_signatures(scene_graph: dict[str, Any]) -> dict[str, str]:
    signatures: dict[str, str] = {}
    for object_id, signature, _ in _iter_object_references(scene_graph):
        signatures.setdefault(object_id, signature)
    return signatures


def _marked_object_signature(obj: dict[str, Any], first_usage: str) -> tuple[Any, ...]:
    binding = obj["marker_binding"]
    aliases = tuple(sorted(binding.get("mentioned_aliases", [])))
    return (
        obj["type"],
        obj.get("name"),
        obj.get("relative_position"),
        binding.get("source_name"),
        aliases,
        first_usage,
    )


def normalize_record_for_graph_fingerprint(record: dict) -> dict[str, Any]:
    scene_graph = _sorted_scene_graph(record["scene_graph"])
    first_usage = _first_usage_signatures(scene_graph)
    marked_objects = [
        (index, obj)
        for index, obj in enumerate(scene_graph["objects"])
        if obj["marker_binding"]["kind"] == "marked"
    ]

    marked_slots = {}
    sortable = []
    for index, obj in marked_objects:
        signature = _marked_object_signature(obj, first_usage.get(obj["id"], "unused"))
        sortable.append((signature, index, obj["id"]))
    sortable.sort(key=lambda item: (item[0], item[1]))
    for slot_index, (_, _, object_id) in enumerate(sortable, start=1):
        marked_slots[object_id] = f"object_marked_SLOT{slot_index}"

    normalized = copy.deepcopy(scene_graph)

    def map_object_id(object_id: str) -> str:
        return marked_slots.get(object_id, object_id)

    for obj in normalized["objects"]:
        original_id = obj["id"]
        obj["id"] = map_object_id(original_id)
        if obj["marker_binding"]["kind"] == "marked":
            obj["marker_binding"].pop("marker_short_id", None)

    for beat in normalized["beats"]:
        for action in beat["actions"]:
            if action.get("target_id") is not None:
                action["target_id"] = map_object_id(action["target_id"])
            if action.get("holding_object") is not None:
                action["holding_object"] = map_object_id(action["holding_object"])

    for relation in normalized["spatial_relations"]:
        relation["subject"] = map_object_id(relation["subject"])
        relation["object"] = map_object_id(relation["object"])

    bindings = normalized["reference_bindings"]
    bindings["marked_object_ids"] = sorted(map_object_id(object_id) for object_id in bindings["marked_object_ids"])
    bindings["alias_to_object_id"] = {
        alias: map_object_id(object_id)
        for alias, object_id in sorted(bindings["alias_to_object_id"].items())
    }

    return normalized


def graph_fingerprint(record: dict) -> str:
    normalized = normalize_record_for_graph_fingerprint(record)
    payload = json.dumps(normalized, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def dedup_group_key(record: dict) -> str:
    sg = record["scene_graph"]
    object_counter = Counter(obj["marker_binding"]["kind"] for obj in sg["objects"])
    object_mode_shape = f"marked={object_counter.get('marked', 0)}|unmarked={object_counter.get('unmarked', 0)}"
    beat_phase_sequence = ",".join(beat["phase"] for beat in sg["beats"])
    action_type_sequence = ",".join(
        action["type"]
        for beat in sg["beats"]
        for action in _sorted_actions(beat["actions"])
    )
    return "|".join(
        [
            record["pattern_name"],
            record["source_variant_key"],
            beat_phase_sequence,
            str(record["budgets"]["actor_count"]),
            object_mode_shape,
            action_type_sequence,
        ]
    )


class DedupIndex:
    def __init__(self) -> None:
        self._fingerprints: dict[str, str] = {}

    def add(self, record: dict) -> bool:
        fingerprint = graph_fingerprint(record)
        if fingerprint in self._fingerprints:
            return False
        self._fingerprints[fingerprint] = record["sample_id"]
        return True

    def __len__(self) -> int:
        return len(self._fingerprints)

