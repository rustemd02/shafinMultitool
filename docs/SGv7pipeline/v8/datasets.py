from __future__ import annotations

import hashlib
import json
import random
import re
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from source_generation.filters import normalize_persisted_source_text

try:
    from .compiler import compile_scene_plan_ir
    from .projection import cir_to_scene_plan_ir
except ImportError:  # pragma: no cover - direct script execution
    from compiler import compile_scene_plan_ir
    from projection import cir_to_scene_plan_ir


PLAN_SYSTEM_PROMPT = (
    "Ты ScenePlanIR planner. Верни только валидный JSON ScenePlanIR без пояснений и без markdown."
)
CRITIC_SYSTEM_PROMPT = (
    "Ты ScenePlanIR critic. Сравни два кандидата и верни только JSON verdict без пояснений и без markdown."
)
PLAN_CONTRACT_VERSION = "sg_v8_plan_ir_v1"
ANCHOR_CONTRACT_VERSION = "sg_v8_anchor_bundle_v1"
COMPILER_VERSION = "sg_v8_compiler_v1"

_WS_RE = re.compile(r"\s+", flags=re.UNICODE)
_EDGE_PUNCT_RE = re.compile(r"^[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+|[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+$")
_TARGET_REQUIRED_TYPES = {"look_at", "pick_up", "open", "close", "approach", "put_down", "give", "pass_by", "stop", "stand"}
_LEGACY_BEAT_FIELDS = {
    "type",
    "action",
    "actorId",
    "actor_id",
    "actorIds",
    "target",
    "targetId",
    "dialogue",
    "resultingText",
    "resultingDialogue",
    "resultingPose",
}


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if not raw:
                continue
            payload = json.loads(raw)
            if isinstance(payload, dict):
                rows.append(payload)
    return rows


def write_jsonl(rows: list[dict[str, Any]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def canonical_json_string(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def normalize_source_key_v1(text: str) -> str:
    value = normalize_persisted_source_text(text).lower()
    value = _EDGE_PUNCT_RE.sub("", value)
    value = _WS_RE.sub(" ", value).strip()
    return value.replace("ё", "е")


def normalized_source_hash_v1(text: str) -> str:
    payload = normalize_source_key_v1(text)
    return "nsh_" + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:8]


def token_count(text: str) -> int:
    normalized = _WS_RE.sub(" ", text.strip())
    if not normalized:
        return 0
    return len(normalized.split(" "))


def _actor_ref_for_index(index: int) -> str:
    if index == 1:
        return "first"
    if index == 2:
        return "second"
    if index == 3:
        return "third"
    return f"actor_ref_{index}"


def _object_ref(object_id: str, *, next_slot_index: int) -> tuple[str, int]:
    if object_id.startswith("object_marked_"):
        return object_id, next_slot_index
    return f"object_slot_{next_slot_index}", next_slot_index + 1


def _extract_scene_script_payload(row: dict[str, Any]) -> dict[str, Any] | None:
    for key in (
        "model_only_predicted_script",
        "raw_output_json",
        "predicted_script",
        "selected_predicted_script",
        "end_to_end_predicted_script",
    ):
        payload = row.get(key)
        if isinstance(payload, dict):
            return deepcopy(payload)
    return None


def _iter_scene_actions(beat: dict[str, Any]) -> list[dict[str, Any]]:
    actions = beat.get("actions")
    if isinstance(actions, list) and actions:
        return [action for action in actions if isinstance(action, dict)]

    if any(field in beat for field in _LEGACY_BEAT_FIELDS):
        actor_ids = beat.get("actorIds")
        actor_id = beat.get("actorId") or beat.get("actor_id")
        if not actor_id and isinstance(actor_ids, list) and actor_ids:
            actor_id = actor_ids[0]
        if not actor_id:
            actor_id = "actor_1"
        action = {
            "actorId": actor_id,
            "type": beat.get("type") or beat.get("action") or "talk",
            "resultingPose": beat.get("resultingPose") or "standing",
        }
        if beat.get("target") or beat.get("targetId"):
            action["target"] = beat.get("target") or beat.get("targetId")
        dialogue = beat.get("dialogue") or beat.get("resultingDialogue") or beat.get("resultingText")
        if dialogue:
            action["dialogue"] = dialogue
        return [action]

    return []


def _maybe_target_ref(target_id: str | None, actor_refs: dict[str, str], object_refs: dict[str, str]) -> str | None:
    if not target_id:
        return None
    return actor_refs.get(target_id) or object_refs.get(target_id)


def scene_script_to_plan_ir(
    script: dict[str, Any],
    *,
    marked_object_ids: list[str] | None = None,
) -> dict[str, Any]:
    actors = script.get("actors")
    objects = script.get("objects")
    beats = script.get("beats")
    spatial_relations = script.get("spatialRelations") or []
    if not isinstance(actors, list) or not isinstance(objects, list) or not isinstance(beats, list):
        raise ValueError("invalid SceneScript payload")

    marked_set = set(marked_object_ids or [])
    actor_id_to_ref: dict[str, str] = {}
    actor_rows: list[dict[str, Any]] = []
    for index, actor in enumerate(actors, start=1):
        if not isinstance(actor, dict):
            continue
        actor_id = str(actor.get("id") or "").strip()
        if not actor_id:
            continue
        actor_ref = _actor_ref_for_index(index)
        actor_id_to_ref[actor_id] = actor_ref
        actor_row = {
            "ref": actor_ref,
            "type": str(actor.get("type") or "human"),
        }
        if actor.get("name"):
            actor_row["name"] = actor["name"]
        actor_rows.append(actor_row)

    object_id_to_ref: dict[str, str] = {}
    object_rows: list[dict[str, Any]] = []
    next_slot_index = 1
    for obj in objects:
        if not isinstance(obj, dict):
            continue
        object_id = str(obj.get("id") or "").strip()
        if not object_id:
            continue
        if object_id.startswith("object_marked_"):
            marked_set.add(object_id)
        object_ref, next_slot_index = _object_ref(object_id, next_slot_index=next_slot_index)
        object_id_to_ref[object_id] = object_ref
        object_row = {
            "ref": object_ref,
            "type": str(obj.get("type") or "generic"),
            "relativePosition": str(obj.get("relativePosition") or "center"),
        }
        if obj.get("name"):
            object_row["name"] = obj["name"]
        if object_id in marked_set:
            object_row["markedObjectID"] = object_id
        object_rows.append(object_row)

    beat_rows: list[dict[str, Any]] = []
    for beat_index, beat in enumerate(beats, start=1):
        if not isinstance(beat, dict):
            continue
        beat_row: dict[str, Any] = {
            "ref": str(beat.get("id") or f"beat_{beat_index}"),
            "actions": [],
        }
        phase = beat.get("phase")
        if phase:
            beat_row["phase"] = phase
        if beat.get("minDuration") is not None:
            beat_row["minDuration"] = beat["minDuration"]
        for action in _iter_scene_actions(beat):
            actor_id = str(action.get("actorId") or action.get("actor_id") or "").strip()
            actor_ref = actor_id_to_ref.get(actor_id)
            if not actor_ref:
                continue
            action_type = str(action.get("type") or "").strip()
            if not action_type:
                continue
            action_row: dict[str, Any] = {
                "actorRef": actor_ref,
                "type": action_type,
            }
            target_ref = _maybe_target_ref(
                str(action.get("target") or action.get("targetId") or "").strip() or None,
                actor_id_to_ref,
                object_id_to_ref,
            )
            if target_ref:
                action_row["targetRef"] = target_ref
            holding_object_ref = _maybe_target_ref(
                str(action.get("holdingObject") or action.get("holdingObjectId") or "").strip() or None,
                actor_id_to_ref,
                object_id_to_ref,
            )
            if holding_object_ref:
                action_row["holdingObjectRef"] = holding_object_ref
            if action.get("direction"):
                action_row["direction"] = action["direction"]
            if action.get("modifier"):
                action_row["modifier"] = action["modifier"]
            if action.get("resultingPose"):
                action_row["resultingPose"] = action["resultingPose"]
            if action.get("dialogue"):
                action_row["dialogue"] = action["dialogue"]
            if action.get("fallbackText"):
                action_row["fallbackText"] = action["fallbackText"]
            if action.get("sourceText"):
                action_row["sourceText"] = action["sourceText"]
            beat_row["actions"].append(action_row)
        if beat_row["actions"]:
            beat_rows.append(beat_row)

    relation_rows: list[dict[str, Any]] = []
    for index, relation in enumerate(spatial_relations, start=1):
        if not isinstance(relation, dict):
            continue
        subject_ref = _maybe_target_ref(
            str(relation.get("subject") or "").strip() or None,
            actor_id_to_ref,
            object_id_to_ref,
        )
        object_ref = _maybe_target_ref(
            str(relation.get("object") or "").strip() or None,
            actor_id_to_ref,
            object_id_to_ref,
        )
        if not subject_ref or not object_ref:
            continue
        relation_type = str(relation.get("relation") or "").strip()
        if not relation_type:
            continue
        relation_rows.append(
            {
                "ref": str(relation.get("id") or f"rel_{index}"),
                "subjectRef": subject_ref,
                "relation": relation_type,
                "objectRef": object_ref,
            }
        )

    return {
        "actors": actor_rows,
        "objects": object_rows,
        "beats": beat_rows,
        "spatialRelations": relation_rows,
        "referenceBindings": {
            "actorBindings": {actor_ref: actor_id for actor_id, actor_ref in actor_id_to_ref.items()},
            "markedObjectIDs": sorted(marked_set),
            "aliasToObjectRef": {},
        },
    }


def source_anchor_bundle_from_cir(record: dict[str, Any]) -> dict[str, Any]:
    scene_graph = record["scene_graph"]
    marked_ids = list(scene_graph.get("reference_bindings", {}).get("marked_object_ids", []))
    marked_types: list[str] = []
    object_surface_mentions: list[str] = []
    for obj in scene_graph.get("objects", []):
        if not isinstance(obj, dict):
            continue
        if obj.get("id") in marked_ids:
            marked_types.append(str(obj.get("type") or "generic"))
        label = str(obj.get("name") or obj.get("type") or "").strip()
        if label:
            object_surface_mentions.append(label.lower())
    same_type_marker_conflict = len(marked_types) != len(set(marked_types))
    unsupported_action_flags = []
    for beat in scene_graph.get("beats", []):
        for action in beat.get("actions", []):
            if action.get("type") == "described_action":
                unsupported_action_flags.append(str(action.get("id") or "described_action"))
    low_confidence_flags: list[str] = []
    if same_type_marker_conflict:
        low_confidence_flags.append("same_type_marker_conflict")
    if unsupported_action_flags:
        low_confidence_flags.append("unsupported_action_present")
    return {
        "actor_count_hint": int(record.get("budgets", {}).get("actor_count", len(scene_graph.get("actors", [])))),
        "ordinal_mentions": list(scene_graph.get("reference_bindings", {}).get("ordinal_map", {}).keys()),
        "mentioned_marked_objects": marked_ids,
        "object_surface_mentions": sorted(set(object_surface_mentions)),
        "phase_cues": [str(beat.get("phase")) for beat in scene_graph.get("beats", []) if beat.get("phase")],
        "unsupported_action_flags": unsupported_action_flags,
        "same_type_marker_conflict": same_type_marker_conflict,
        "low_confidence_flags": low_confidence_flags,
    }


def source_anchor_bundle_from_eval_case(row: dict[str, Any]) -> dict[str, Any]:
    gold_target = row.get("gold_target_json") or {}
    actors = gold_target.get("actors") if isinstance(gold_target, dict) else []
    beats = gold_target.get("beats") if isinstance(gold_target, dict) else []
    marked_objects = row.get("marked_objects") if isinstance(row.get("marked_objects"), list) else []
    marked_ids = [str(item.get("id")) for item in marked_objects if isinstance(item, dict) and item.get("id")]
    marked_types = [str(item.get("type") or "generic") for item in marked_objects if isinstance(item, dict)]
    object_surface_mentions: list[str] = []
    for item in marked_objects:
        if not isinstance(item, dict):
            continue
        canonical_name = str(item.get("canonical_name") or "").strip().lower()
        if canonical_name:
            object_surface_mentions.append(canonical_name)
        for alias in item.get("allowed_aliases", []):
            alias_text = str(alias).strip().lower()
            if alias_text:
                object_surface_mentions.append(alias_text)
    unsupported_action_flags: list[str] = []
    if isinstance(beats, list):
        for beat in beats:
            if not isinstance(beat, dict):
                continue
            for action in beat.get("actions", []):
                if isinstance(action, dict) and action.get("type") == "described_action":
                    unsupported_action_flags.append(str(action.get("id") or "described_action"))
    same_type_marker_conflict = len(marked_types) != len(set(marked_types))
    low_confidence_flags: list[str] = []
    if same_type_marker_conflict:
        low_confidence_flags.append("same_type_marker_conflict")
    if unsupported_action_flags:
        low_confidence_flags.append("unsupported_action_present")
    return {
        "actor_count_hint": len(actors) if isinstance(actors, list) else 0,
        "ordinal_mentions": list((row.get("eval_expectations") or {}).get("expected_ordinal_bindings", {}).keys()),
        "mentioned_marked_objects": marked_ids,
        "object_surface_mentions": sorted(set(object_surface_mentions)),
        "phase_cues": list((row.get("eval_expectations") or {}).get("expected_phase_sequence", [])),
        "unsupported_action_flags": unsupported_action_flags,
        "same_type_marker_conflict": same_type_marker_conflict,
        "low_confidence_flags": low_confidence_flags,
    }


def render_plan_messages(*, source_text: str, anchor_bundle: dict[str, Any], assistant_payload: dict[str, Any] | None = None) -> list[dict[str, str]]:
    user_prompt = "\n\n".join(
        [
            "Task instruction:\nСконвертируй source text в ScenePlanIR JSON.",
            "Output contract:\nВерни только JSON c top-level полями actors, objects, beats, spatialRelations, referenceBindings.",
            f"SourceAnchorBundle:\n{canonical_json_string(anchor_bundle)}",
            f"Source text:\n{source_text}",
        ]
    )
    messages = [
        {"role": "system", "content": PLAN_SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
    ]
    if assistant_payload is not None:
        messages.append({"role": "assistant", "content": canonical_json_string(assistant_payload)})
    return messages


def render_subtask_messages(
    *,
    source_text: str,
    anchor_bundle: dict[str, Any],
    subtask_type: str,
    output_contract: str,
    assistant_payload: dict[str, Any],
) -> list[dict[str, str]]:
    user_prompt = "\n\n".join(
        [
            f"Task instruction:\nСконвертируй source text в {subtask_type} JSON.",
            f"Output contract:\nВерни только JSON c top-level полями {output_contract}.",
            f"SourceAnchorBundle:\n{canonical_json_string(anchor_bundle)}",
            f"Source text:\n{source_text}",
        ]
    )
    return [
        {"role": "system", "content": PLAN_SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
        {"role": "assistant", "content": canonical_json_string(assistant_payload)},
    ]


def render_critic_messages(
    *,
    source_text: str,
    anchor_bundle: dict[str, Any],
    candidate_a_json: dict[str, Any],
    candidate_b_json: dict[str, Any],
) -> list[dict[str, str]]:
    user_prompt = "\n\n".join(
        [
            "Task instruction:\nСравни два ScenePlanIR candidate для одного source text и выбери лучший.",
            "Output contract:\nВерни только JSON c top-level полями winner, confidence, reasons.",
            f"SourceAnchorBundle:\n{canonical_json_string(anchor_bundle)}",
            f"Source text:\n{source_text}",
            f"Candidate A:\n{canonical_json_string(candidate_a_json)}",
            f"Candidate B:\n{canonical_json_string(candidate_b_json)}",
        ]
    )
    return [
        {"role": "system", "content": CRITIC_SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
    ]


def _sample_graph_family_key(sample_id: str, fallback: str) -> str:
    if "::" in fallback:
        return fallback
    if "__" in sample_id:
        return sample_id.rsplit("__", 1)[-1]
    return sample_id


def _base_packaging_metadata(
    *,
    sample_id: str,
    source_text: str,
    graph_family_key: str,
    pattern_name: str,
    pattern_family: str,
    source_variant_key: str,
    difficulty_bucket: str,
    complexity_class: str,
    semantic_tags: list[str],
) -> dict[str, Any]:
    return {
        "contract_version": PLAN_CONTRACT_VERSION,
        "plan_contract_version": PLAN_CONTRACT_VERSION,
        "anchor_contract_version": ANCHOR_CONTRACT_VERSION,
        "compiler_version": COMPILER_VERSION,
        "graph_family_key": graph_family_key,
        "split_family_id": graph_family_key,
        "normalized_source_hash": normalized_source_hash_v1(source_text),
        "sample_id": sample_id,
        "pattern_name": pattern_name,
        "pattern_family": pattern_family,
        "source_variant_key": source_variant_key,
        "difficulty_bucket": difficulty_bucket,
        "complexity_class": complexity_class,
        "semantic_tags": semantic_tags,
        "source_text_token_count": token_count(source_text),
    }


def build_plan_sft_rows(cir_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    dataset: list[dict[str, Any]] = []
    for row in cir_rows:
        source_text = (
            row.get("source_variant_text")
            or row.get("original_description")
            or row.get("internal_metadata", {}).get("canonical_source_template")
            or row["sample_id"]
        )
        plan_ir = cir_to_scene_plan_ir(row)
        anchor_bundle = source_anchor_bundle_from_cir(row)
        packaging_metadata = _base_packaging_metadata(
            sample_id=str(row["sample_id"]),
            source_text=str(source_text),
            graph_family_key=_sample_graph_family_key(str(row["sample_id"]), str(row.get("graph_family_key") or "")),
            pattern_name=str(row.get("pattern_name", "")),
            pattern_family=str(row.get("internal_metadata", {}).get("pattern_family", "")),
            source_variant_key=str(row.get("source_variant_key", "")),
            difficulty_bucket=str(row.get("difficulty_bucket", "")),
            complexity_class=str(row.get("complexity_class", "")),
            semantic_tags=[str(item) for item in row.get("semantic_tags", []) if isinstance(item, str)],
        )
        packaging_metadata.update(
            {
                "task_type": "sft",
                "v8_task_type": "plan_sft",
                "training_target": "scene_plan_ir",
                "actor_count": len(plan_ir["actors"]),
                "object_count": len(plan_ir["objects"]),
                "beat_count": len(plan_ir["beats"]),
                "action_count": sum(len(beat.get("actions", [])) for beat in plan_ir["beats"]),
            }
        )
        dataset.append(
            {
                "sample_id": row["sample_id"],
                "task_type": "sft",
                "messages": render_plan_messages(source_text=str(source_text), anchor_bundle=anchor_bundle, assistant_payload=plan_ir),
                "source_text": source_text,
                "source_anchor_bundle": anchor_bundle,
                "target_plan_ir": plan_ir,
                "compiled_target_json": compile_scene_plan_ir(plan_ir, original_description=str(source_text)),
                "packaging_metadata": packaging_metadata,
            }
        )
    return dataset


def _subtask_targets(plan_ir: dict[str, Any]) -> dict[str, dict[str, Any]]:
    beat_plan = {
        "actors": deepcopy(plan_ir["actors"]),
        "objects": deepcopy(plan_ir["objects"]),
        "beats": [],
    }
    target_linking = {
        "links": [],
    }
    for beat in plan_ir["beats"]:
        beat_row = {"ref": beat["ref"], "actions": []}
        if beat.get("phase"):
            beat_row["phase"] = beat["phase"]
        if beat.get("minDuration") is not None:
            beat_row["minDuration"] = beat["minDuration"]
        for action_index, action in enumerate(beat.get("actions", []), start=1):
            action_row = {
                "actorRef": action["actorRef"],
                "type": action["type"],
            }
            if action.get("direction"):
                action_row["direction"] = action["direction"]
            if action.get("modifier"):
                action_row["modifier"] = action["modifier"]
            if action.get("resultingPose"):
                action_row["resultingPose"] = action["resultingPose"]
            if action.get("dialogue"):
                action_row["dialogue"] = action["dialogue"]
            if action.get("fallbackText"):
                action_row["fallbackText"] = action["fallbackText"]
            if action.get("sourceText"):
                action_row["sourceText"] = action["sourceText"]
            beat_row["actions"].append(action_row)

            link_row = {
                "beatRef": beat["ref"],
                "actionIndex": action_index,
                "actorRef": action["actorRef"],
                "actionType": action["type"],
            }
            if action.get("targetRef"):
                link_row["targetRef"] = action["targetRef"]
            if action.get("holdingObjectRef"):
                link_row["holdingObjectRef"] = action["holdingObjectRef"]
            target_linking["links"].append(link_row)
        beat_plan["beats"].append(beat_row)

    ordinal_linking = {
        "actorBindings": deepcopy(plan_ir["referenceBindings"].get("actorBindings", {})),
        "markedObjectIDs": deepcopy(plan_ir["referenceBindings"].get("markedObjectIDs", [])),
        "aliasToObjectRef": deepcopy(plan_ir["referenceBindings"].get("aliasToObjectRef", {})),
    }
    return {
        "anchor_extraction": {},
        "beat_plan": beat_plan,
        "target_linking": target_linking,
        "ordinal_linking": ordinal_linking,
    }


def build_subtask_sft_rows(cir_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for record in cir_rows:
        source_text = (
            record.get("source_variant_text")
            or record.get("original_description")
            or record.get("internal_metadata", {}).get("canonical_source_template")
            or record["sample_id"]
        )
        plan_ir = cir_to_scene_plan_ir(record)
        anchor_bundle = source_anchor_bundle_from_cir(record)
        targets = _subtask_targets(plan_ir)
        targets["anchor_extraction"] = deepcopy(anchor_bundle)
        base_metadata = _base_packaging_metadata(
            sample_id=str(record["sample_id"]),
            source_text=str(source_text),
            graph_family_key=_sample_graph_family_key(str(record["sample_id"]), str(record.get("graph_family_key") or "")),
            pattern_name=str(record.get("pattern_name", "")),
            pattern_family=str(record.get("internal_metadata", {}).get("pattern_family", "")),
            source_variant_key=str(record.get("source_variant_key", "")),
            difficulty_bucket=str(record.get("difficulty_bucket", "")),
            complexity_class=str(record.get("complexity_class", "")),
            semantic_tags=[str(item) for item in record.get("semantic_tags", []) if isinstance(item, str)],
        )
        for subtask_type, target_json in targets.items():
            packaging_metadata = deepcopy(base_metadata)
            packaging_metadata.update(
                {
                    "task_type": "sft",
                    "v8_task_type": "subtask_sft",
                    "training_target": subtask_type,
                    "subtask_type": subtask_type,
                }
            )
            if subtask_type == "anchor_extraction":
                output_contract = "actor_count_hint, ordinal_mentions, mentioned_marked_objects, object_surface_mentions, phase_cues, unsupported_action_flags, same_type_marker_conflict, low_confidence_flags"
            elif subtask_type == "beat_plan":
                output_contract = "actors, objects, beats"
            elif subtask_type == "target_linking":
                output_contract = "links"
            else:
                output_contract = "actorBindings, markedObjectIDs, aliasToObjectRef"
            rows.append(
                {
                    "sample_id": record["sample_id"],
                    "subtask_id": f"{record['sample_id']}::{subtask_type}",
                    "task_type": "sft",
                    "messages": render_subtask_messages(
                        source_text=str(source_text),
                        anchor_bundle=anchor_bundle,
                        subtask_type=subtask_type,
                        output_contract=output_contract,
                        assistant_payload=target_json,
                    ),
                    "source_text": source_text,
                    "source_anchor_bundle": anchor_bundle,
                    "subtask_type": subtask_type,
                    "target_json": target_json,
                    "packaging_metadata": packaging_metadata,
                }
            )
    return rows


def _case_quality_score(row: dict[str, Any]) -> float:
    metric_flags = row.get("metric_flags", {}) if isinstance(row.get("metric_flags"), dict) else {}
    values = row.get("metric_values", {}) if isinstance(row.get("metric_values"), dict) else {}
    score = 0.0
    score += 4.0 if bool(row.get("case_strict_success")) else 0.0
    score += 1.0 if bool(row.get("json_valid")) else 0.0
    score += 1.0 if bool(row.get("schema_valid")) else 0.0
    score += sum(1.0 for value in metric_flags.values() if bool(value))
    score += float(values.get("target_resolution_accuracy_case", 0.0))
    score += float(values.get("chronology_phase_accuracy_case", 0.0))
    score += float(values.get("action_recall_case", 0.0))
    return score


def _preference_reasons(*, chosen_label: str, candidate_case: dict[str, Any], baseline_case: dict[str, Any], pairwise_row: dict[str, Any] | None) -> list[str]:
    reasons = [f"winner={chosen_label}"]
    if pairwise_row is not None:
        reasons.append("winner_source=pairwise")
    else:
        reasons.append("winner_source=case_quality_score")
    if bool(candidate_case.get("case_strict_success")) != bool(baseline_case.get("case_strict_success")):
        reasons.append("strict_gap")
    candidate_flags = candidate_case.get("metric_flags", {}) if isinstance(candidate_case.get("metric_flags"), dict) else {}
    baseline_flags = baseline_case.get("metric_flags", {}) if isinstance(baseline_case.get("metric_flags"), dict) else {}
    for key in ("target_resolution_pass", "chronology_phase_pass", "action_recall_pass", "ordinal_binding_pass"):
        if bool(candidate_flags.get(key)) != bool(baseline_flags.get(key)):
            reasons.append(key)
    return reasons


def _prefer_winner(
    *,
    pairwise_row: dict[str, Any] | None,
    candidate_case: dict[str, Any],
    baseline_case: dict[str, Any],
) -> str | None:
    if pairwise_row is not None:
        winner = str(pairwise_row.get("winner") or "").strip().lower()
        if winner in {"candidate", "baseline"}:
            return winner
    candidate_score = _case_quality_score(candidate_case)
    baseline_score = _case_quality_score(baseline_case)
    if candidate_score > baseline_score:
        return "candidate"
    if baseline_score > candidate_score:
        return "baseline"
    return None


def build_plan_preference_rows(
    *,
    eval_case_rows: list[dict[str, Any]],
    candidate_prediction_rows: list[dict[str, Any]],
    baseline_prediction_rows: list[dict[str, Any]],
    candidate_case_rows: list[dict[str, Any]],
    baseline_case_rows: list[dict[str, Any]],
    candidate_model_id: str,
    baseline_model_id: str,
    paired_case_rows: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    eval_cases_by_id = {str(row["eval_case_id"]): row for row in eval_case_rows if row.get("eval_case_id")}
    candidate_predictions_by_id = {str(row["eval_case_id"]): row for row in candidate_prediction_rows if row.get("eval_case_id")}
    baseline_predictions_by_id = {str(row["eval_case_id"]): row for row in baseline_prediction_rows if row.get("eval_case_id")}
    candidate_cases_by_id = {str(row["eval_case_id"]): row for row in candidate_case_rows if row.get("eval_case_id")}
    baseline_cases_by_id = {str(row["eval_case_id"]): row for row in baseline_case_rows if row.get("eval_case_id")}
    pairwise_by_id = {str(row["eval_case_id"]): row for row in (paired_case_rows or []) if row.get("eval_case_id")}

    rows: list[dict[str, Any]] = []
    for eval_case_id, eval_case in eval_cases_by_id.items():
        candidate_prediction = candidate_predictions_by_id.get(eval_case_id)
        baseline_prediction = baseline_predictions_by_id.get(eval_case_id)
        candidate_case = candidate_cases_by_id.get(eval_case_id)
        baseline_case = baseline_cases_by_id.get(eval_case_id)
        if not candidate_prediction or not baseline_prediction or not candidate_case or not baseline_case:
            continue
        candidate_script = _extract_scene_script_payload(candidate_prediction)
        baseline_script = _extract_scene_script_payload(baseline_prediction)
        if candidate_script is None or baseline_script is None:
            continue
        marked_object_ids = [str(item.get("id")) for item in eval_case.get("marked_objects", []) if isinstance(item, dict) and item.get("id")]
        try:
            candidate_plan = scene_script_to_plan_ir(candidate_script, marked_object_ids=marked_object_ids)
            baseline_plan = scene_script_to_plan_ir(baseline_script, marked_object_ids=marked_object_ids)
        except ValueError:
            continue
        candidate_json = canonical_json_string(candidate_plan)
        baseline_json = canonical_json_string(baseline_plan)
        if candidate_json == baseline_json:
            continue
        winner = _prefer_winner(
            pairwise_row=pairwise_by_id.get(eval_case_id),
            candidate_case=candidate_case,
            baseline_case=baseline_case,
        )
        if winner is None:
            continue
        anchor_bundle = source_anchor_bundle_from_eval_case(eval_case)
        source_text = str(eval_case.get("source_text") or "")
        gold_target = eval_case.get("gold_target_json")
        gold_plan_ir = (
            scene_script_to_plan_ir(gold_target, marked_object_ids=marked_object_ids)
            if isinstance(gold_target, dict)
            else None
        )
        chosen_plan = candidate_plan if winner == "candidate" else baseline_plan
        rejected_plan = baseline_plan if winner == "candidate" else candidate_plan
        try:
            chosen_compiled_json = compile_scene_plan_ir(chosen_plan, original_description=source_text)
            rejected_compiled_json = compile_scene_plan_ir(rejected_plan, original_description=source_text)
        except ValueError:
            continue
        chosen_model_id = candidate_model_id if winner == "candidate" else baseline_model_id
        rejected_model_id = baseline_model_id if winner == "candidate" else candidate_model_id
        chosen_case = candidate_case if winner == "candidate" else baseline_case
        rejected_case = baseline_case if winner == "candidate" else candidate_case
        packaging_metadata = _base_packaging_metadata(
            sample_id=str(eval_case.get("sample_id") or eval_case_id),
            source_text=source_text,
            graph_family_key=str(eval_case.get("graph_family_key") or eval_case_id),
            pattern_name=str(eval_case_id.split("::", 1)[-1].split("__", 1)[0]),
            pattern_family="eval_case",
            source_variant_key=str(eval_case.get("sample_id") or ""),
            difficulty_bucket=str(eval_case.get("difficulty_bucket") or ""),
            complexity_class="",
            semantic_tags=[],
        )
        packaging_metadata.update(
            {
                "task_type": "preference",
                "v8_task_type": "plan_preference",
                "training_target": "scene_plan_ir",
                "eval_case_id": eval_case_id,
                "eval_set": eval_case.get("eval_set"),
                "candidate_model_id": candidate_model_id,
                "baseline_model_id": baseline_model_id,
                "chosen_model_id": chosen_model_id,
                "rejected_model_id": rejected_model_id,
                "candidate_quality_score": _case_quality_score(candidate_case),
                "baseline_quality_score": _case_quality_score(baseline_case),
                "preference_reason_codes": _preference_reasons(
                    chosen_label=winner,
                    candidate_case=candidate_case,
                    baseline_case=baseline_case,
                    pairwise_row=pairwise_by_id.get(eval_case_id),
                ),
            }
        )
        rows.append(
            {
                "preference_id": f"pref-v8-{candidate_model_id}-vs-{baseline_model_id}-{eval_case_id}",
                "task_type": "preference",
                "messages": render_plan_messages(source_text=source_text, anchor_bundle=anchor_bundle),
                "source_text": source_text,
                "source_anchor_bundle": anchor_bundle,
                "gold_plan_ir": gold_plan_ir,
                "chosen": canonical_json_string(chosen_plan),
                "rejected": canonical_json_string(rejected_plan),
                "chosen_plan_ir": chosen_plan,
                "rejected_plan_ir": rejected_plan,
                "chosen_compiled_json": chosen_compiled_json,
                "rejected_compiled_json": rejected_compiled_json,
                "chosen_case_result": chosen_case,
                "rejected_case_result": rejected_case,
                "packaging_metadata": packaging_metadata,
            }
        )
    return rows


def build_critic_rank_rows(
    *,
    eval_case_rows: list[dict[str, Any]],
    candidate_prediction_rows: list[dict[str, Any]],
    baseline_prediction_rows: list[dict[str, Any]],
    candidate_case_rows: list[dict[str, Any]],
    baseline_case_rows: list[dict[str, Any]],
    candidate_model_id: str,
    baseline_model_id: str,
    paired_case_rows: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    preference_rows = build_plan_preference_rows(
        eval_case_rows=eval_case_rows,
        candidate_prediction_rows=candidate_prediction_rows,
        baseline_prediction_rows=baseline_prediction_rows,
        candidate_case_rows=candidate_case_rows,
        baseline_case_rows=baseline_case_rows,
        candidate_model_id=candidate_model_id,
        baseline_model_id=baseline_model_id,
        paired_case_rows=paired_case_rows,
    )
    critic_rows: list[dict[str, Any]] = []
    for row in preference_rows:
        chosen_is_candidate = row["packaging_metadata"]["chosen_model_id"] == candidate_model_id
        candidate_a_json = row["chosen_plan_ir"] if chosen_is_candidate else row["rejected_plan_ir"]
        candidate_b_json = row["rejected_plan_ir"] if chosen_is_candidate else row["chosen_plan_ir"]
        candidate_a_case = row["chosen_case_result"] if chosen_is_candidate else row["rejected_case_result"]
        candidate_b_case = row["rejected_case_result"] if chosen_is_candidate else row["chosen_case_result"]
        preferred_side = "candidate_a" if chosen_is_candidate else "candidate_b"
        metadata = deepcopy(row["packaging_metadata"])
        metadata.update(
            {
                "task_type": "critic_rank",
                "v8_task_type": "critic_rank",
                "training_target": "critic_score",
                "preferred_side": preferred_side,
            }
        )
        critic_rows.append(
            {
                "critic_id": row["preference_id"].replace("pref-v8-", "critic-v8-"),
                "task_type": "critic_rank",
                "messages": render_critic_messages(
                    source_text=row["source_text"],
                    anchor_bundle=row["source_anchor_bundle"],
                    candidate_a_json=candidate_a_json,
                    candidate_b_json=candidate_b_json,
                ),
                "source_text": row["source_text"],
                "source_anchor_bundle": row["source_anchor_bundle"],
                "gold_plan_ir": row["gold_plan_ir"],
                "candidate_a": canonical_json_string(candidate_a_json),
                "candidate_b": canonical_json_string(candidate_b_json),
                "candidate_a_plan_ir": candidate_a_json,
                "candidate_b_plan_ir": candidate_b_json,
                "candidate_a_case_result": candidate_a_case,
                "candidate_b_case_result": candidate_b_case,
                "preferred_side": preferred_side,
                "preferred_model_id": metadata["chosen_model_id"],
                "packaging_metadata": metadata,
            }
        )
    return critic_rows


def split_rows(rows: list[dict[str, Any]], *, key_field: str, val_fraction: float, seed: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if val_fraction <= 0.0 or not rows:
        return rows, []
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        metadata = row.get("packaging_metadata", {}) if isinstance(row.get("packaging_metadata"), dict) else {}
        key = str(metadata.get(key_field) or row.get("sample_id") or row.get("preference_id") or row.get("critic_id"))
        grouped.setdefault(key, []).append(row)
    keys = list(grouped.keys())
    random.Random(seed).shuffle(keys)
    val_count = max(1, int(round(len(keys) * val_fraction)))
    val_keys = set(keys[:val_count])
    train_rows: list[dict[str, Any]] = []
    val_rows: list[dict[str, Any]] = []
    for key, items in grouped.items():
        target = val_rows if key in val_keys else train_rows
        split_name = "val" if key in val_keys else "train"
        for row in items:
            row_copy = deepcopy(row)
            metadata = row_copy.get("packaging_metadata", {})
            if isinstance(metadata, dict):
                metadata["split"] = split_name
            target.append(row_copy)
    return train_rows, val_rows
