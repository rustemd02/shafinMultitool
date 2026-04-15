from __future__ import annotations

import json
from typing import Any

from cir_contract.contracts import serialize_to_scenescript
from runtime_train_contract.marked_ids import resolve_marked_object_rows


SYSTEM_PROMPT = (
    "Ты SceneScript parser. Верни только валидный JSON SceneScript без пояснений и без markdown."
)


def canonical_json_string(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _format_marked_objects(cir_record: dict[str, Any]) -> str:
    marked_rows: list[dict[str, Any]] = []
    for obj in cir_record["scene_graph"]["objects"]:
        binding = obj.get("marker_binding", {})
        if binding.get("kind") != "marked":
            continue
        name = str(obj.get("name") or binding.get("source_name") or "-").strip().lower() or "-"
        marked_rows.append(
            {
                "existing_id": obj.get("id"),
                "marker_uuid": binding.get("marker_uuid"),
                "normalized_name": name,
                "type": str(obj.get("type", "generic")).strip().lower() or "generic",
                "source_marker_ordinal": binding.get("source_marker_ordinal"),
                "marker_origin_key": binding.get("marker_origin_key") or str(obj.get("id") or "").strip() or None,
                "name": name,
            }
        )
    if not marked_rows:
        return "- none"

    resolved_rows = resolve_marked_object_rows(marked_rows)
    lines = [
        f"- id={row['resolved_id']}; name={row['name']}; type={row['type']}; aliases=-"
        for row in sorted(resolved_rows, key=lambda item: str(item["resolved_id"]))
    ]
    return "\n".join(lines)


def _format_constraints(cir_record: dict[str, Any]) -> str:
    must_preserve = cir_record["scene_graph"].get("must_preserve", [])
    lines = [f"- {item}" for item in must_preserve if isinstance(item, str)]
    if not lines:
        lines = ["- preserve chronology and object bindings from the input graph"]
    return "\n".join(lines)


def render_user_prompt(*, source_text: str, cir_record: dict[str, Any]) -> str:
    sections = [
        "Task instruction:\nСконвертируй source text в SceneScript JSON.",
        "Output contract:\nВерни только JSON c top-level полями actors, objects, beats, spatialRelations, originalDescription.",
        f"Action/object constraints:\n{_format_constraints(cir_record)}",
        f"Marked objects:\n{_format_marked_objects(cir_record)}",
        f"Source text:\n{source_text}",
    ]
    return "\n\n".join(sections)


def render_sft_messages(*, source_text: str, cir_record: dict[str, Any]) -> tuple[list[dict[str, str]], dict[str, Any], str]:
    target_json = serialize_to_scenescript(cir_record, original_description=source_text)
    assistant = canonical_json_string(target_json)
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": render_user_prompt(source_text=source_text, cir_record=cir_record)},
        {"role": "assistant", "content": assistant},
    ]
    return messages, target_json, assistant


def render_preference_messages(*, source_text: str, cir_record: dict[str, Any]) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": render_user_prompt(source_text=source_text, cir_record=cir_record)},
    ]
