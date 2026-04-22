from __future__ import annotations

from typing import Any

try:
    from .compiler import compile_scene_plan_ir_with_notes
except ImportError:  # pragma: no cover - direct script execution
    from compiler import compile_scene_plan_ir_with_notes


def extract_plan_payload(row: dict[str, Any]) -> dict[str, Any] | None:
    for key in ("predicted_plan_ir", "model_only_plan_ir", "raw_output_json", "plan_ir"):
        payload = row.get(key)
        if isinstance(payload, dict):
            return payload
    return None


def plan_parse_ok(plan: dict[str, Any] | None) -> bool:
    if not isinstance(plan, dict):
        return False
    return (
        isinstance(plan.get("actors"), list)
        and isinstance(plan.get("objects"), list)
        and isinstance(plan.get("beats"), list)
        and isinstance(plan.get("spatialRelations"), list)
        and isinstance(plan.get("referenceBindings"), dict)
    )


def reference_binding_pass(plan: dict[str, Any], eval_case: dict[str, Any]) -> bool:
    bindings = plan.get("referenceBindings", {})
    actor_bindings = bindings.get("actorBindings", {}) if isinstance(bindings, dict) else {}
    marked_ids = bindings.get("markedObjectIDs", []) if isinstance(bindings, dict) else []
    expected_ordinal = (eval_case.get("eval_expectations") or {}).get("expected_ordinal_bindings", {})
    if not isinstance(actor_bindings, dict):
        return False
    if not isinstance(marked_ids, list):
        return False
    for ordinal, actor_id in expected_ordinal.items():
        if actor_bindings.get(ordinal) != actor_id:
            return False
    expected_marked_ids = sorted(
        str(item.get("id"))
        for item in eval_case.get("marked_objects", [])
        if isinstance(item, dict) and item.get("id")
    )
    return sorted(str(item) for item in marked_ids) == expected_marked_ids


def beat_integrity_pass(plan: dict[str, Any], eval_case: dict[str, Any]) -> bool:
    beats = plan.get("beats")
    if not isinstance(beats, list) or not beats:
        return False
    for beat in beats:
        if not isinstance(beat, dict):
            return False
        actions = beat.get("actions")
        if not isinstance(actions, list) or not actions:
            return False
    gold_beats = (eval_case.get("gold_target_json") or {}).get("beats", [])
    if isinstance(gold_beats, list) and gold_beats:
        return len(beats) == len(gold_beats)
    return True


def build_v8_eval_artifacts(
    *,
    eval_case_rows: list[dict[str, Any]],
    prediction_rows: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    predictions_by_id = {str(row["eval_case_id"]): row for row in prediction_rows if row.get("eval_case_id")}
    plan_case_rows: list[dict[str, Any]] = []
    compiled_prediction_rows: list[dict[str, Any]] = []

    for eval_case in eval_case_rows:
        eval_case_id = str(eval_case.get("eval_case_id") or "")
        if not eval_case_id:
            continue
        prediction_row = predictions_by_id.get(eval_case_id, {})
        predicted_plan = extract_plan_payload(prediction_row)
        parsed_ok = plan_parse_ok(predicted_plan)
        ref_pass = False
        beat_pass = False
        compile_ok = False
        compile_error = None
        compile_notes: list[str] = []
        compiled_script = None

        if parsed_ok and isinstance(predicted_plan, dict):
            ref_pass = reference_binding_pass(predicted_plan, eval_case)
            beat_pass = beat_integrity_pass(predicted_plan, eval_case)
            try:
                compiled_script, compile_notes = compile_scene_plan_ir_with_notes(
                    predicted_plan,
                    original_description=str(eval_case.get("source_text") or ""),
                )
                compile_ok = True
            except ValueError as exc:
                compile_error = str(exc)

        plan_case_rows.append(
            {
                "eval_case_id": eval_case_id,
                "sample_id": eval_case.get("sample_id"),
                "eval_set": eval_case.get("eval_set"),
                "plan_parse_ok": parsed_ok,
                "plan_reference_binding_pass": ref_pass,
                "plan_beat_integrity_pass": beat_pass,
                "plan_compile_ok": compile_ok,
                "compile_error": compile_error,
                "compile_notes": compile_notes,
                "predicted_plan_ir": predicted_plan,
            }
        )
        reason_codes: list[str] = []
        input_reason_codes = prediction_row.get("slice_reason_codes")
        if isinstance(input_reason_codes, list):
            for code in input_reason_codes:
                code_value = str(code).strip()
                if code_value:
                    reason_codes.append(code_value)
        for note in compile_notes:
            if note not in reason_codes:
                reason_codes.append(note)
        compiled_prediction_rows.append(
            {
                "eval_case_id": eval_case_id,
                "slice_reason_codes": reason_codes,
                "selected_slice": "both",
                "model_only_predicted_script": compiled_script if isinstance(compiled_script, dict) else None,
                "end_to_end_predicted_script": compiled_script if isinstance(compiled_script, dict) else None,
                "raw_output_json": compiled_script if isinstance(compiled_script, dict) else None,
                "predicted_script": compiled_script if isinstance(compiled_script, dict) else None,
                "selected_predicted_script": compiled_script if isinstance(compiled_script, dict) else None,
                "compile_notes": compile_notes,
            }
        )

    return plan_case_rows, compiled_prediction_rows
