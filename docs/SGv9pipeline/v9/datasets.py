from __future__ import annotations

import hashlib
import json
import random
from copy import deepcopy
from pathlib import Path
from typing import Any

from .projection import cir_to_v9_event_table, cir_to_v9_slot_catalog

PLAN_SYSTEM_PROMPT = "Ты V9 slot-event planner. Верни только валидный JSON без пояснений и markdown."
PATCH_SYSTEM_PROMPT = "Ты V9 verifier patch assistant. Верни только валидный JSON patch-операций без пояснений."
V9_CONTRACT_VERSION = "sg_v9_event_table_v1"


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = line.strip()
            if not payload:
                continue
            decoded = json.loads(payload)
            if isinstance(decoded, dict):
                rows.append(decoded)
    return rows


def write_jsonl(rows: list[dict[str, Any]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def split_rows(
    rows: list[dict[str, Any]],
    *,
    key_field: str,
    val_fraction: float,
    seed: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        key = str(row.get("packaging_metadata", {}).get(key_field) or row.get(key_field) or "").strip()
        if not key:
            sample_id = str(row.get("sample_id") or "<unknown>")
            raise ValueError(f"Missing split key '{key_field}' for sample_id={sample_id}")
        grouped.setdefault(key, []).append(row)
    keys = sorted(grouped.keys())
    rng = random.Random(seed)
    rng.shuffle(keys)
    val_size = max(1, int(len(keys) * val_fraction)) if keys else 0
    val_keys = set(keys[:val_size])
    train_rows: list[dict[str, Any]] = []
    val_rows: list[dict[str, Any]] = []
    for key in keys:
        target = val_rows if key in val_keys else train_rows
        target.extend(grouped[key])
    return train_rows, val_rows


def _normalize_source_text(record: dict[str, Any]) -> str:
    return str(
        record.get("source_variant_text")
        or record.get("original_description")
        or record.get("internal_metadata", {}).get("canonical_source_template")
        or ""
    ).strip()


def _normalized_source_hash(text: str) -> str:
    normalized = " ".join(text.lower().split()).replace("ё", "е")
    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:8]
    return f"nsh_{digest}"


def _base_metadata(record: dict[str, Any], source_text: str) -> dict[str, Any]:
    sample_id = str(record.get("sample_id") or "")
    graph_family_key = str(record.get("graph_family_key") or sample_id.rsplit("__", 1)[-1] if "__" in sample_id else sample_id)
    return {
        "contract_version": V9_CONTRACT_VERSION,
        "sample_id": sample_id,
        "split_family_id": graph_family_key,
        "graph_family_key": graph_family_key,
        "normalized_source_hash": _normalized_source_hash(source_text),
        "source_text_token_count": len(source_text.split()) if source_text else 0,
        "pattern_name": str(record.get("pattern_name") or ""),
        "difficulty_bucket": str(record.get("difficulty_bucket") or ""),
        "complexity_class": str(record.get("complexity_class") or ""),
        "semantic_tags": [str(item) for item in record.get("semantic_tags", []) if isinstance(item, str)],
    }


def build_v9_event_sft_rows(cir_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for record in cir_rows:
        source_text = _normalize_source_text(record)
        if not source_text:
            continue
        slot_catalog = cir_to_v9_slot_catalog(record)
        event_table = cir_to_v9_event_table(record, slot_catalog)
        user_prompt = "\n\n".join(
            [
                "Task instruction:\nСконвертируй source text в sg_v9_event_table_v1 JSON.",
                "Output contract:\nВерни только JSON c top-level полями contractVersion, rows.",
                f"SlotCatalog:\n{json.dumps(slot_catalog, ensure_ascii=False, separators=(',', ':'))}",
                f"Source text:\n{source_text}",
            ]
        )
        metadata = _base_metadata(record, source_text)
        metadata.update(
            {
                "task_type": "sft",
                "v9_task_type": "event_table_sft",
                "training_target": "sg_v9_event_table_v1",
            }
        )
        rows.append(
            {
                "sample_id": record.get("sample_id"),
                "task_type": "sft",
                "messages": [
                    {"role": "system", "content": PLAN_SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                    {"role": "assistant", "content": json.dumps(event_table, ensure_ascii=False, separators=(",", ":"))},
                ],
                "source_text": source_text,
                "slot_catalog": slot_catalog,
                "target_event_table": event_table,
                "packaging_metadata": metadata,
            }
        )
    return rows


def _make_corrupted_event_table(
    event_table: dict[str, Any],
    *,
    corruption_seed: str,
) -> tuple[dict[str, Any], dict[str, Any]] | None:
    rows = event_table.get("rows") if isinstance(event_table, dict) else None
    if not isinstance(rows, list) or not rows:
        return None
    required_target_actions = {"look_at", "pick_up", "open", "close", "approach", "put_down", "give", "pass_by", "stop"}
    corrupted = deepcopy(event_table)
    target_patch = {"contractVersion": "sg_v9_patch_ops_v1", "ops": []}
    seed_hash = int(hashlib.sha256(corruption_seed.encode("utf-8")).hexdigest()[:8], 16)
    strategy_order = [
        "missing_required_target",
        "unknown_actor_slot",
        "unknown_beat_slot",
        "unknown_action_type",
        "duplicate_row_id",
        "described_action_without_text",
    ]
    start_index = seed_hash % len(strategy_order)
    ordered_strategies = strategy_order[start_index:] + strategy_order[:start_index]

    for strategy in ordered_strategies:
        if strategy == "missing_required_target":
            for row in corrupted["rows"]:
                action_type = str(row.get("actionType") or "")
                if action_type in required_target_actions and row.get("targetSlot"):
                    row_id = str(row.get("rowId") or "row_1")
                    original_target = row.pop("targetSlot")
                    target_patch["ops"].append({"op": "replace", "rowId": row_id, "field": "targetSlot", "value": original_target})
                    return corrupted, target_patch
        elif strategy == "unknown_actor_slot":
            first_row = corrupted["rows"][0]
            row_id = str(first_row.get("rowId") or "row_1")
            original_actor = first_row.get("actorSlot")
            if original_actor:
                first_row["actorSlot"] = "actor_slot_invalid"
                target_patch["ops"].append({"op": "replace", "rowId": row_id, "field": "actorSlot", "value": original_actor})
                return corrupted, target_patch
        elif strategy == "unknown_beat_slot":
            first_row = corrupted["rows"][0]
            row_id = str(first_row.get("rowId") or "row_1")
            original_beat = first_row.get("beatSlot")
            if original_beat:
                first_row["beatSlot"] = "beat_slot_invalid"
                target_patch["ops"].append({"op": "replace", "rowId": row_id, "field": "beatSlot", "value": original_beat})
                return corrupted, target_patch
        elif strategy == "unknown_action_type":
            first_row = corrupted["rows"][0]
            row_id = str(first_row.get("rowId") or "row_1")
            original_type = first_row.get("actionType")
            if original_type:
                first_row["actionType"] = "teleport"
                target_patch["ops"].append({"op": "replace", "rowId": row_id, "field": "actionType", "value": original_type})
                return corrupted, target_patch
        elif strategy == "duplicate_row_id" and len(corrupted["rows"]) >= 2:
            source_row_id = str(corrupted["rows"][0].get("rowId") or "row_1")
            duplicate_row = corrupted["rows"][1]
            original_row_id = str(duplicate_row.get("rowId") or "row_2")
            if source_row_id != original_row_id:
                duplicate_row["rowId"] = source_row_id
                target_patch["ops"].append({"op": "replace", "rowId": source_row_id, "field": "rowId", "value": original_row_id})
                return corrupted, target_patch
        elif strategy == "described_action_without_text":
            for row in corrupted["rows"]:
                if str(row.get("actionType") or "") == "described_action" and (row.get("describedActionText") or row.get("sourceSpan")):
                    row_id = str(row.get("rowId") or "row_1")
                    original_text = row.get("describedActionText")
                    row["describedActionText"] = ""
                    target_patch["ops"].append({"op": "replace", "rowId": row_id, "field": "describedActionText", "value": original_text})
                    return corrupted, target_patch
    return None


def build_v9_patch_sft_rows(cir_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for record in cir_rows:
        source_text = _normalize_source_text(record)
        if not source_text:
            continue
        slot_catalog = cir_to_v9_slot_catalog(record)
        clean_event = cir_to_v9_event_table(record, slot_catalog)
        corrupted_pair = _make_corrupted_event_table(
            clean_event,
            corruption_seed=str(record.get("sample_id") or source_text),
        )
        if corrupted_pair is None:
            continue
        corrupted_event, patch_ops = corrupted_pair
        user_prompt = "\n\n".join(
            [
                "Task instruction:\nИсправь event table по verifier errors только patch-операциями.",
                "Output contract:\nВерни только JSON c top-level полями contractVersion, ops.",
                f"SlotCatalog:\n{json.dumps(slot_catalog, ensure_ascii=False, separators=(',', ':'))}",
                f"Invalid EventTable:\n{json.dumps(corrupted_event, ensure_ascii=False, separators=(',', ':'))}",
                "Verifier errors:\n- resolve invalid slot/value references\n- restore required fields for action semantics",
                f"Source text:\n{source_text}",
            ]
        )
        metadata = _base_metadata(record, source_text)
        metadata.update(
            {
                "task_type": "sft",
                "v9_task_type": "event_table_patch_sft",
                "training_target": "sg_v9_patch_ops_v1",
            }
        )
        rows.append(
            {
                "sample_id": record.get("sample_id"),
                "task_type": "sft",
                "messages": [
                    {"role": "system", "content": PATCH_SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                    {"role": "assistant", "content": json.dumps(patch_ops, ensure_ascii=False, separators=(",", ":"))},
                ],
                "source_text": source_text,
                "slot_catalog": slot_catalog,
                "corrupted_event_table": corrupted_event,
                "target_patch_ops": patch_ops,
                "clean_event_table": clean_event,
                "packaging_metadata": metadata,
            }
        )
    return rows
