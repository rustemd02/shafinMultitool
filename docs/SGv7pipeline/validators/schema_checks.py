from __future__ import annotations

from jsonschema import Draft202012Validator

from cir_contract.contracts import load_schema, serialize_to_scenescript


def validate_schema_and_runtime_projection(cir_record: dict[str, object], *, source_text: str) -> list[str]:
    reasons: list[str] = []
    schema = load_schema()
    errors = sorted(Draft202012Validator(schema).iter_errors(cir_record), key=lambda item: list(item.path))
    if errors:
        reasons.append("schema_invalid_cir")
        return reasons

    for beat in cir_record.get("scene_graph", {}).get("beats", []):
        for action in beat.get("actions", []):
            if action.get("type") != "described_action":
                continue
            payload = action.get("described_action")
            if not isinstance(payload, dict):
                reasons.append("schema_invalid_described_action")
                return sorted(set(reasons))
            canonical_text = payload.get("canonical_text")
            fallback_text = payload.get("fallback_text")
            if not isinstance(canonical_text, str) or not canonical_text.strip():
                reasons.append("schema_invalid_described_action")
            if not isinstance(fallback_text, str) or not fallback_text.strip():
                reasons.append("schema_invalid_described_action")
    if reasons:
        return sorted(set(reasons))

    try:
        projected = serialize_to_scenescript(cir_record, original_description=source_text)
    except Exception:
        reasons.append("runtime_projection_failure")
        return reasons

    if cir_record.get("runtime_projection", {}).get("target_schema") != "SceneScript":
        reasons.append("runtime_projection_failure")
        return reasons

    for beat in projected.get("beats", []):
        for action in beat.get("actions", []):
            if action.get("type") != "described_action":
                continue
            if not isinstance(action.get("sourceText"), str) or not action["sourceText"].strip():
                reasons.append("schema_invalid_described_action")
            if not isinstance(action.get("fallbackText"), str) or not action["fallbackText"].strip():
                reasons.append("schema_invalid_described_action")
    return sorted(set(reasons))
