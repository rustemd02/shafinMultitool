from __future__ import annotations

import json
from typing import Any

from cir_contract.contracts import serialize_to_scenescript


SYSTEM_PROMPT = (
    "Ты SceneScript parser. Верни только валидный JSON SceneScript без пояснений и без markdown."
)


def canonical_json_string(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _format_marked_objects(cir_record: dict[str, Any]) -> str:
    rows: list[str] = []
    for obj in cir_record["scene_graph"]["objects"]:
        binding = obj.get("marker_binding", {})
        if binding.get("kind") != "marked":
            continue
        aliases = binding.get("mentioned_aliases", [])
        alias_text = ", ".join(str(item) for item in aliases) if aliases else "-"
        rows.append(
            f"- id={obj['id']}; name={obj.get('name', '-')}; type={obj.get('type', '-')}; aliases={alias_text}"
        )
    if not rows:
        return "- (none)"
    return "\n".join(rows)


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

