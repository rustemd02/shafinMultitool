from __future__ import annotations

from collections import defaultdict
import json
from typing import Any

from .config import DatasetBuildError


def _priority_rank(row: dict[str, Any]) -> tuple[int, int, int, str]:
    metadata = row["packaging_metadata"]
    generation_pass = str(metadata.get("generation_pass", ""))
    if generation_pass == "base_paraphrase":
        pass_rank = 0
    elif generation_pass == "augmentation":
        pass_rank = 1
    else:
        pass_rank = 2
    promoted_rank = 1 if row.get("promoted_from_manual_review") else 0
    recoverability_score = int(row.get("recoverability_score", 0))
    token_count = int(metadata.get("source_text_token_count", 0))
    return (pass_rank, -promoted_rank, -recoverability_score, f"{token_count:09d}:{row['sample_id']}")


def _stable_payload_signature(row: dict[str, Any]) -> str:
    payload = {
        "sample_id": row["sample_id"],
        "source_text": row["source_text"],
        "target_json": row["target_json"],
        "packaging_metadata": {
            "graph_hash": row["packaging_metadata"]["graph_hash"],
            "graph_family_key": row["packaging_metadata"]["graph_family_key"],
            "normalized_source_hash": row["packaging_metadata"]["normalized_source_hash"],
            "contract_version": row["packaging_metadata"]["contract_version"],
            "correction_tier": row["packaging_metadata"]["correction_tier"],
        },
    }
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def dedup_sft_candidates(candidates: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, int]]:
    dropped = {
        "duplicate_sample_id": 0,
        "family_cap_exceeded": 0,
        "same_graph_and_source": 0,
        "normalized_source_hash_collision": 0,
    }

    by_sample_id: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in candidates:
        by_sample_id[row["sample_id"]].append(row)

    unique_by_id: list[dict[str, Any]] = []
    for sample_id, rows in sorted(by_sample_id.items()):
        rows_sorted = sorted(rows, key=_priority_rank)
        chosen = rows_sorted[0]
        chosen_signature = _stable_payload_signature(chosen)
        for other in rows_sorted[1:]:
            if _stable_payload_signature(other) != chosen_signature:
                raise DatasetBuildError(f"duplicate sample_id with conflicting payload: {sample_id}")
            dropped["duplicate_sample_id"] += 1
        unique_by_id.append(chosen)

    by_family: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in unique_by_id:
        family = str(row["packaging_metadata"]["graph_family_key"])
        by_family[family].append(row)

    capped: list[dict[str, Any]] = []
    for family, rows in sorted(by_family.items()):
        rows_sorted = sorted(rows, key=_priority_rank)
        difficulty = str(rows_sorted[0]["packaging_metadata"]["difficulty_bucket"])
        cap = 2 if difficulty == "core" else 3
        capped.extend(rows_sorted[:cap])
        dropped["family_cap_exceeded"] += max(0, len(rows_sorted) - cap)

    by_graph_and_source: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in capped:
        metadata = row["packaging_metadata"]
        key = f"{metadata['graph_hash']}|{metadata['normalized_source_hash']}"
        by_graph_and_source[key].append(row)

    layer3_kept: list[dict[str, Any]] = []
    for _, rows in sorted(by_graph_and_source.items()):
        rows_sorted = sorted(rows, key=_priority_rank)
        layer3_kept.append(rows_sorted[0])
        dropped["same_graph_and_source"] += max(0, len(rows_sorted) - 1)

    by_normalized_source: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in layer3_kept:
        key = str(row["packaging_metadata"]["normalized_source_hash"])
        by_normalized_source[key].append(row)

    final_rows: list[dict[str, Any]] = []
    for _, rows in sorted(by_normalized_source.items()):
        rows_sorted = sorted(rows, key=_priority_rank)
        final_rows.append(rows_sorted[0])
        dropped["normalized_source_hash_collision"] += max(0, len(rows_sorted) - 1)

    final_rows.sort(key=lambda item: (item["packaging_metadata"]["difficulty_bucket"], item["sample_id"]))
    return final_rows, dropped

