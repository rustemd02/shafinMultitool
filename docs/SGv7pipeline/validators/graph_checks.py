from __future__ import annotations


def validate_graph_consistency(cir_record: dict[str, object]) -> list[str]:
    reasons: list[str] = []
    scene_graph = cir_record.get("scene_graph", {})
    actor_ids = {actor.get("id") for actor in scene_graph.get("actors", []) if isinstance(actor, dict)}
    object_ids = {obj.get("id") for obj in scene_graph.get("objects", []) if isinstance(obj, dict)}
    valid_targets = actor_ids | object_ids

    beat_ids: set[str] = set()
    action_ids: set[str] = set()

    for beat in scene_graph.get("beats", []):
        beat_id = beat.get("id")
        if beat_id in beat_ids:
            reasons.append("graph_duplicate_beat_id")
        beat_ids.add(beat_id)
        for action in beat.get("actions", []):
            action_id = action.get("id")
            if action_id in action_ids:
                reasons.append("graph_duplicate_action_id")
            action_ids.add(action_id)

            actor_id = action.get("actor_id")
            if actor_id not in actor_ids:
                reasons.append("graph_missing_actor")

            target_id = action.get("target_id")
            if target_id is not None and target_id not in valid_targets:
                reasons.append("graph_dangling_target")
                if isinstance(target_id, str) and target_id.startswith("actor_"):
                    reasons.append("graph_missing_actor")
                elif isinstance(target_id, str):
                    reasons.append("graph_missing_object")

            holding_object = action.get("holding_object")
            if holding_object is not None and holding_object not in object_ids:
                reasons.append("graph_missing_object")

    for relation in scene_graph.get("spatial_relations", []):
        for key in ("subject", "object"):
            target = relation.get(key)
            if target not in valid_targets:
                reasons.append("graph_dangling_target")
                if isinstance(target, str) and target.startswith("actor_"):
                    reasons.append("graph_missing_actor")
                elif isinstance(target, str):
                    reasons.append("graph_missing_object")

    return sorted(set(reasons))
