from __future__ import annotations

from typing import Any

from .compiler import compile_event_table_to_script
from .verifier import verify_and_repair_event_table


SUPPORTED_ACTION_TYPES = {
    "walk",
    "run",
    "approach",
    "pass_by",
    "enter",
    "exit",
    "stand",
    "sit",
    "lie_down",
    "stop",
    "turn",
    "crouch",
    "look_at",
    "pick_up",
    "put_down",
    "open",
    "close",
    "give",
    "talk",
    "described_action",
}


def _extract_payload(row: dict[str, Any], keys: tuple[str, ...]) -> dict[str, Any] | None:
    for key in keys:
        payload = row.get(key)
        if isinstance(payload, dict):
            return payload
    return None


def _actor_ref_for_index(index: int) -> str:
    if index == 1:
        return "first"
    if index == 2:
        return "second"
    if index == 3:
        return "third"
    return f"actor_ref_{index}"


def _derive_gold_slot_catalog_from_scene_script(scene_script: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(scene_script, dict):
        return None
    actors = scene_script.get("actors")
    objects = scene_script.get("objects")
    beats = scene_script.get("beats")
    if not isinstance(actors, list) or not isinstance(objects, list) or not isinstance(beats, list):
        return None

    actor_slots: list[dict[str, Any]] = []
    object_slots: list[dict[str, Any]] = []
    beat_slots: list[dict[str, Any]] = []
    marked_object_slots: list[str] = []
    relation_hints: list[dict[str, str]] = []
    action_types: set[str] = set(SUPPORTED_ACTION_TYPES)

    actor_id_to_slot: dict[str, str] = {}
    object_id_to_slot: dict[str, str] = {}

    for index, actor in enumerate(actors, start=1):
        if not isinstance(actor, dict):
            continue
        actor_id = str(actor.get("id") or actor.get("ref") or f"actor_{index}")
        slot_id = f"actor_slot_{index}"
        actor_id_to_slot[actor_id] = slot_id
        row: dict[str, Any] = {
            "slotId": slot_id,
            "ref": _actor_ref_for_index(index),
            "type": str(actor.get("type") or "human"),
        }
        if actor.get("name"):
            row["name"] = str(actor["name"])
        actor_slots.append(row)

    for index, obj in enumerate(objects, start=1):
        if not isinstance(obj, dict):
            continue
        object_id = str(obj.get("id") or obj.get("ref") or f"object_{index}")
        slot_id = f"object_slot_{index}"
        object_id_to_slot[object_id] = slot_id
        object_ref = str(obj.get("id") or obj.get("ref") or slot_id)
        row = {
            "slotId": slot_id,
            "ref": object_ref,
            "type": str(obj.get("type") or "generic"),
            "relativePosition": str(obj.get("relativePosition") or obj.get("relative_position") or "unknown"),
        }
        if obj.get("name"):
            row["name"] = str(obj["name"])
        marked_id = str(obj.get("markedObjectID") or object_ref)
        if marked_id.startswith("object_marked_"):
            row["markedObjectID"] = marked_id
            marked_object_slots.append(slot_id)
        object_slots.append(row)

    for index, beat in enumerate(beats, start=1):
        if not isinstance(beat, dict):
            continue
        beat_slot = f"beat_slot_{index}"
        beat_row: dict[str, Any] = {
            "slotId": beat_slot,
            "beatRef": str(beat.get("id") or beat.get("ref") or f"beat_{index}"),
            "order": index,
        }
        if beat.get("phase"):
            beat_row["phaseHint"] = str(beat["phase"])
        if beat.get("minDuration") is not None:
            beat_row["minDuration"] = float(beat["minDuration"])
        beat_slots.append(beat_row)
        for action in beat.get("actions", []) if isinstance(beat.get("actions"), list) else []:
            if isinstance(action, dict) and action.get("type"):
                action_types.add(str(action["type"]))

    for relation in scene_script.get("spatialRelations", []) if isinstance(scene_script.get("spatialRelations"), list) else []:
        if not isinstance(relation, dict):
            continue
        subject_id = str(relation.get("subjectRef") or relation.get("subject") or "")
        object_id = str(relation.get("objectRef") or relation.get("object") or "")
        subject_slot = actor_id_to_slot.get(subject_id) or object_id_to_slot.get(subject_id)
        object_slot = actor_id_to_slot.get(object_id) or object_id_to_slot.get(object_id)
        if subject_slot and object_slot:
            relation_hints.append(
                {
                    "subjectSlot": subject_slot,
                    "relation": str(relation.get("relation") or "near"),
                    "objectSlot": object_slot,
                }
            )

    return {
        "contractVersion": "sg_v9_slot_catalog_v1",
        "actorSlots": actor_slots,
        "objectSlots": object_slots,
        "markedObjectSlots": sorted(set(marked_object_slots)),
        "beatSlots": beat_slots,
        "actionTypes": sorted(action_types),
        "relationHints": relation_hints,
    }


def _derive_gold_event_table_from_scene_script(
    scene_script: dict[str, Any],
    slot_catalog: dict[str, Any],
) -> dict[str, Any] | None:
    beats = scene_script.get("beats")
    actors = scene_script.get("actors")
    objects = scene_script.get("objects")
    if not isinstance(beats, list) or not isinstance(actors, list) or not isinstance(objects, list):
        return None

    actor_id_to_slot = {
        str(actor.get("id") or actor.get("ref") or f"actor_{index}"): f"actor_slot_{index}"
        for index, actor in enumerate(actors, start=1)
        if isinstance(actor, dict)
    }
    object_id_to_slot = {
        str(obj.get("id") or obj.get("ref") or f"object_{index}"): f"object_slot_{index}"
        for index, obj in enumerate(objects, start=1)
        if isinstance(obj, dict)
    }
    beat_slots = list(slot_catalog.get("beatSlots", []))

    rows: list[dict[str, Any]] = []
    row_index = 1
    for beat_index, beat in enumerate(beats, start=1):
        if not isinstance(beat, dict):
            continue
        beat_slot = str(beat_slots[beat_index - 1].get("slotId") or f"beat_slot_{beat_index}") if beat_index - 1 < len(beat_slots) else f"beat_slot_{beat_index}"
        actions = beat.get("actions")
        if not isinstance(actions, list):
            continue
        for action in actions:
            if not isinstance(action, dict):
                continue
            actor_id = str(action.get("actorId") or action.get("actor_id") or action.get("actorRef") or "")
            actor_slot = actor_id_to_slot.get(actor_id)
            if not actor_slot:
                continue
            row: dict[str, Any] = {
                "rowId": f"row_{row_index}",
                "beatSlot": beat_slot,
                "actorSlot": actor_slot,
                "actionType": str(action.get("type") or "stand"),
                "confidence": 1.0,
            }
            target_id = str(action.get("target") or action.get("targetId") or action.get("targetRef") or "").strip()
            if target_id:
                target_slot = actor_id_to_slot.get(target_id) or object_id_to_slot.get(target_id)
                if target_slot:
                    row["targetSlot"] = target_slot
            holding_id = str(action.get("holdingObject") or action.get("holdingObjectRef") or "").strip()
            if holding_id:
                holding_slot = object_id_to_slot.get(holding_id)
                if holding_slot:
                    row["holdingObjectSlot"] = holding_slot
            dialogue_text = str(action.get("dialogue") or "").strip()
            if dialogue_text:
                row["dialogueText"] = dialogue_text
            if str(action.get("type") or "") == "described_action":
                described_text = str(
                    action.get("fallbackText")
                    or action.get("sourceText")
                    or action.get("describedActionText")
                    or ""
                ).strip()
                if described_text:
                    row["describedActionText"] = described_text
            rows.append(row)
            row_index += 1

    return {
        "contractVersion": "sg_v9_event_table_v1",
        "rows": rows,
    }


def _schema_valid(slot_catalog: dict[str, Any], event_table: dict[str, Any]) -> bool:
    actor_slots = {str(item.get("slotId")) for item in slot_catalog.get("actorSlots", [])}
    object_slots = {str(item.get("slotId")) for item in slot_catalog.get("objectSlots", [])}
    beat_slots = {str(item.get("slotId")) for item in slot_catalog.get("beatSlots", [])}
    action_types = {str(item) for item in slot_catalog.get("actionTypes", [])}
    rows = event_table.get("rows")
    if not isinstance(rows, list):
        return False
    seen_rows: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            return False
        row_id = str(row.get("rowId") or "").strip()
        if not row_id or row_id in seen_rows:
            return False
        seen_rows.add(row_id)
        if str(row.get("beatSlot") or "").strip() not in beat_slots:
            return False
        if str(row.get("actorSlot") or "").strip() not in actor_slots:
            return False
        if str(row.get("actionType") or "").strip() not in action_types:
            return False
        target_slot = str(row.get("targetSlot") or "").strip()
        if target_slot and target_slot not in actor_slots.union(object_slots):
            return False
    return True


def _rows_by_id(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]] | None:
    row_map: dict[str, dict[str, Any]] = {}
    for row in rows:
        row_id = str(row.get("rowId") or "").strip()
        if not row_id or row_id in row_map:
            return None
        row_map[row_id] = row
    return row_map


def _slot_identity_map(slot_catalog: dict[str, Any] | None) -> dict[str, str]:
    if not isinstance(slot_catalog, dict):
        return {}
    mapping: dict[str, str] = {}
    for slot in slot_catalog.get("actorSlots", []):
        if not isinstance(slot, dict):
            continue
        slot_id = str(slot.get("slotId") or "").strip()
        if slot_id:
            mapping[slot_id] = str(slot.get("ref") or slot.get("name") or slot_id)
    for slot in slot_catalog.get("objectSlots", []):
        if not isinstance(slot, dict):
            continue
        slot_id = str(slot.get("slotId") or "").strip()
        if slot_id:
            mapping[slot_id] = str(slot.get("markedObjectID") or slot_id)
    for slot in slot_catalog.get("beatSlots", []):
        if not isinstance(slot, dict):
            continue
        slot_id = str(slot.get("slotId") or "").strip()
        if slot_id:
            mapping[slot_id] = str(slot.get("beatRef") or slot.get("order") or slot_id)
    return mapping


def _resolved_slot_value(slot_id: str, identity_map: dict[str, str]) -> str:
    key = str(slot_id or "").strip()
    if not key:
        return ""
    return identity_map.get(key, key)


def _semantic_hit_counts(
    *,
    predicted_event_table: dict[str, Any] | None,
    gold_event_table: dict[str, Any] | None,
    predicted_slot_catalog: dict[str, Any] | None = None,
    gold_slot_catalog: dict[str, Any] | None = None,
) -> dict[str, int]:
    if not isinstance(predicted_event_table, dict) or not isinstance(gold_event_table, dict):
        return {
            "semantic_row_total": 0,
            "semantic_actor_hit_count": 0,
            "semantic_target_hit_count": 0,
            "semantic_action_hit_count": 0,
            "semantic_beat_hit_count": 0,
            "semantic_full_row_hit_count": 0,
        }
    predicted_rows = predicted_event_table.get("rows")
    gold_rows = gold_event_table.get("rows")
    if not isinstance(predicted_rows, list) or not isinstance(gold_rows, list) or not gold_rows:
        return {
            "semantic_row_total": 0,
            "semantic_actor_hit_count": 0,
            "semantic_target_hit_count": 0,
            "semantic_action_hit_count": 0,
            "semantic_beat_hit_count": 0,
            "semantic_full_row_hit_count": 0,
        }

    predicted_by_id = _rows_by_id([row for row in predicted_rows if isinstance(row, dict)])
    gold_by_id = _rows_by_id([row for row in gold_rows if isinstance(row, dict)])
    aligned_pairs: list[tuple[dict[str, Any], dict[str, Any]]] = []
    if predicted_by_id is not None and gold_by_id is not None:
        for row_id, gold_row in gold_by_id.items():
            aligned_pairs.append((predicted_by_id.get(row_id, {}), gold_row))
    else:
        typed_predicted = [row for row in predicted_rows if isinstance(row, dict)]
        typed_gold = [row for row in gold_rows if isinstance(row, dict)]
        max_len = max(len(typed_predicted), len(typed_gold))
        for index in range(max_len):
            predicted = typed_predicted[index] if index < len(typed_predicted) else {}
            gold = typed_gold[index] if index < len(typed_gold) else {}
            if isinstance(gold, dict) and gold:
                aligned_pairs.append((predicted if isinstance(predicted, dict) else {}, gold))

    predicted_identity = _slot_identity_map(predicted_slot_catalog)
    gold_identity = _slot_identity_map(gold_slot_catalog)

    total = 0
    actor_hits = 0
    target_hits = 0
    action_hits = 0
    beat_hits = 0
    full_row_hits = 0
    for predicted, gold in aligned_pairs:
        total += 1
        row_actor_hit = False
        row_target_hit = False
        row_action_hit = False
        row_beat_hit = False
        predicted_actor = _resolved_slot_value(str(predicted.get("actorSlot") or ""), predicted_identity)
        gold_actor = _resolved_slot_value(str(gold.get("actorSlot") or ""), gold_identity)
        if predicted_actor == gold_actor:
            actor_hits += 1
            row_actor_hit = True

        predicted_target = _resolved_slot_value(str(predicted.get("targetSlot") or ""), predicted_identity)
        gold_target = _resolved_slot_value(str(gold.get("targetSlot") or ""), gold_identity)
        if predicted_target == gold_target:
            target_hits += 1
            row_target_hit = True

        predicted_action = str(predicted.get("actionType") or "").strip()
        gold_action = str(gold.get("actionType") or "").strip()
        if predicted_action == gold_action:
            action_hits += 1
            row_action_hit = True

        predicted_beat = _resolved_slot_value(str(predicted.get("beatSlot") or ""), predicted_identity)
        gold_beat = _resolved_slot_value(str(gold.get("beatSlot") or ""), gold_identity)
        if predicted_beat == gold_beat:
            beat_hits += 1
            row_beat_hit = True

        if row_actor_hit and row_target_hit and row_action_hit and row_beat_hit:
            full_row_hits += 1

    return {
        "semantic_row_total": total,
        "semantic_actor_hit_count": actor_hits,
        "semantic_target_hit_count": target_hits,
        "semantic_action_hit_count": action_hits,
        "semantic_beat_hit_count": beat_hits,
        "semantic_full_row_hit_count": full_row_hits,
    }


def build_v9_eval_artifacts(
    *,
    eval_case_rows: list[dict[str, Any]],
    prediction_rows: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    predictions_by_id: dict[str, dict[str, Any]] = {}
    duplicate_ids: list[str] = []
    for row in prediction_rows:
        eval_case_id_value = str(row.get("eval_case_id") or "").strip()
        if not eval_case_id_value:
            continue
        if eval_case_id_value in predictions_by_id:
            duplicate_ids.append(eval_case_id_value)
            continue
        predictions_by_id[eval_case_id_value] = row
    if duplicate_ids:
        unique_duplicates = sorted(set(duplicate_ids))
        preview = ", ".join(unique_duplicates[:10])
        tail = "..." if len(unique_duplicates) > 10 else ""
        raise ValueError(f"Duplicate eval_case_id values in prediction_rows: {preview}{tail}")
    event_case_rows: list[dict[str, Any]] = []
    compiled_prediction_rows: list[dict[str, Any]] = []

    for eval_case in eval_case_rows:
        eval_case_id = str(eval_case.get("eval_case_id") or "")
        if not eval_case_id:
            continue
        prediction_row = predictions_by_id.get(eval_case_id, {})
        slot_catalog = _extract_payload(
            prediction_row,
            ("predicted_slot_catalog", "slot_catalog", "model_only_slot_catalog", "raw_slot_catalog"),
        )
        gold_slot_catalog = _extract_payload(
            eval_case,
            ("gold_slot_catalog", "expected_slot_catalog", "target_slot_catalog"),
        )
        if gold_slot_catalog is None and isinstance(eval_case.get("gold_target_json"), dict):
            gold_slot_catalog = _derive_gold_slot_catalog_from_scene_script(eval_case["gold_target_json"])
        event_table = _extract_payload(
            prediction_row,
            ("predicted_event_table", "event_table", "model_only_event_table", "raw_output_json"),
        )
        gold_event_table = _extract_payload(
            eval_case,
            ("gold_event_table", "expected_event_table", "target_event_table"),
        )
        if gold_event_table is None and isinstance(eval_case.get("gold_target_json"), dict) and isinstance(gold_slot_catalog, dict):
            gold_event_table = _derive_gold_event_table_from_scene_script(eval_case["gold_target_json"], gold_slot_catalog)
        parse_ok = isinstance(slot_catalog, dict) and isinstance(event_table, dict)
        schema_ok = False
        actor_slot_structural_pass = False
        target_slot_structural_pass = False
        action_type_structural_pass = False
        beat_order_structural_pass = False
        patch_success = False
        compiler_repair_applied = False
        verifier_notes: list[str] = []
        compiled_script: dict[str, Any] | None = None
        compile_notes: list[str] = []
        compile_error: str | None = None
        targetless_event_repaired = False
        unknown_slot_blocked = False
        input_event_row_count = 0
        repaired_event_row_count = 0
        dropped_event_row_count = 0
        semantic_counts = {
            "semantic_row_total": 0,
            "semantic_actor_hit_count": 0,
            "semantic_target_hit_count": 0,
            "semantic_action_hit_count": 0,
            "semantic_beat_hit_count": 0,
            "semantic_full_row_hit_count": 0,
        }
        chunk_metadata = eval_case.get("chunk_metadata") if isinstance(eval_case.get("chunk_metadata"), dict) else {}

        if parse_ok and slot_catalog and event_table:
            input_rows = event_table.get("rows")
            if isinstance(input_rows, list):
                input_event_row_count = len(input_rows)
            repaired, issues, verifier_notes = verify_and_repair_event_table(slot_catalog, event_table)
            repaired_rows = repaired.get("rows")
            if isinstance(repaired_rows, list):
                repaired_event_row_count = len(repaired_rows)
            dropped_event_row_count = max(0, input_event_row_count - repaired_event_row_count)
            schema_ok = _schema_valid(slot_catalog, repaired)
            actor_slot_structural_pass = not any(issue["code"] == "unknown_actor_slot" for issue in issues)
            target_slot_structural_pass = not any(
                issue["code"] in {"unknown_target_slot", "target_required_missing"} for issue in issues
            )
            action_type_structural_pass = not any(issue["code"] == "unknown_action_type" for issue in issues)
            beat_order_structural_pass = not any(issue["code"] == "unknown_beat_slot" for issue in issues)
            patch_success = schema_ok and len(issues) > 0
            compiler_repair_applied = len(verifier_notes) > 0
            targetless_event_repaired = any(issue["code"] == "target_required_missing" for issue in issues)
            unknown_slot_blocked = any(issue["code"] == "unknown_actor_slot" for issue in issues)

            if isinstance(gold_slot_catalog, dict) and isinstance(gold_event_table, dict):
                semantic_counts = _semantic_hit_counts(
                    predicted_event_table=repaired,
                    gold_event_table=gold_event_table,
                    predicted_slot_catalog=slot_catalog,
                    gold_slot_catalog=gold_slot_catalog,
                )
            try:
                compiled_script, compile_notes = compile_event_table_to_script(
                    slot_catalog=slot_catalog,
                    event_table=repaired,
                    source_text=str(eval_case.get("source_text") or ""),
                )
            except ValueError as exc:
                compile_error = str(exc)

        event_case_rows.append(
            {
                "eval_case_id": eval_case_id,
                "sample_id": eval_case.get("sample_id"),
                "eval_set": eval_case.get("eval_set"),
                "event_parse_ok": parse_ok,
                "event_schema_valid": schema_ok,
                "event_actor_slot_structural_pass": actor_slot_structural_pass,
                "event_target_slot_structural_pass": target_slot_structural_pass,
                "event_action_type_structural_pass": action_type_structural_pass,
                "event_beat_order_structural_pass": beat_order_structural_pass,
                # Backward-compatible aliases (deprecated).
                "event_actor_slot_pass": actor_slot_structural_pass,
                "event_target_slot_pass": target_slot_structural_pass,
                "event_action_type_pass": action_type_structural_pass,
                "event_beat_order_pass": beat_order_structural_pass,
                "patch_success": patch_success,
                "compiler_repair_applied": compiler_repair_applied,
                "targetless_event_repaired": targetless_event_repaired,
                "unknown_slot_blocked": unknown_slot_blocked,
                "input_event_row_count": input_event_row_count,
                "repaired_event_row_count": repaired_event_row_count,
                "dropped_event_row_count": dropped_event_row_count,
                **semantic_counts,
                "chunk_group_id": chunk_metadata.get("chunk_group_id") or eval_case.get("document_id") or eval_case.get("scene_id"),
                "chunk_id": chunk_metadata.get("chunk_id") or eval_case.get("chunk_id"),
                "chunk_index": chunk_metadata.get("chunk_index") if chunk_metadata.get("chunk_index") is not None else eval_case.get("chunk_index"),
                "chunk_count": chunk_metadata.get("chunk_count") if chunk_metadata.get("chunk_count") is not None else eval_case.get("chunk_count"),
                "chunk_expected_event_count": semantic_counts["semantic_row_total"],
                "chunk_predicted_event_count": repaired_event_row_count,
                "chunk_missing_event_count": max(0, semantic_counts["semantic_row_total"] - semantic_counts["semantic_full_row_hit_count"]),
                "chunk_extra_event_count": max(0, repaired_event_row_count - semantic_counts["semantic_row_total"]),
                "chunk_event_coverage_pass": (
                    semantic_counts["semantic_row_total"] > 0
                    and semantic_counts["semantic_full_row_hit_count"] >= semantic_counts["semantic_row_total"]
                ),
                "cross_chunk_actor_continuity_pass": eval_case.get("cross_chunk_actor_continuity_pass"),
                "cross_chunk_object_continuity_pass": eval_case.get("cross_chunk_object_continuity_pass"),
                "pronoun_resolution_after_chunk_pass": eval_case.get("pronoun_resolution_after_chunk_pass"),
                "stitch_no_duplicate_actor_pass": eval_case.get("stitch_no_duplicate_actor_pass"),
                "playback_intent_success_pass": eval_case.get("playback_intent_success_pass"),
                "compile_notes": compile_notes,
                "compile_error": compile_error,
            }
        )

        reason_codes: list[str] = []
        for code in prediction_row.get("slice_reason_codes", []) if isinstance(prediction_row.get("slice_reason_codes"), list) else []:
            code_value = str(code).strip()
            if code_value and code_value not in reason_codes:
                reason_codes.append(code_value)
        for note in verifier_notes + compile_notes:
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
                "v9_verifier_notes": verifier_notes,
            }
        )

    return event_case_rows, compiled_prediction_rows
