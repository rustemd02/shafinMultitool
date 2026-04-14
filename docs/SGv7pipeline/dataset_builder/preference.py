from __future__ import annotations

from copy import deepcopy
import json
from typing import Any

from .config import DatasetBuildRequest, PreferenceBuildResult
from .ingest import normalized_source_hash_v1, token_count
from .renderer import canonical_json_string, render_preference_messages


def _json_payload(value: object) -> dict[str, Any] | None:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return None
        if isinstance(parsed, dict):
            return parsed
    return None


def _resolve_anchor(
    row: dict[str, Any],
    *,
    cir_index: dict[str, Any],
) -> tuple[str | None, dict[str, str], dict[str, Any] | None]:
    anchor = row.get("family_anchor")
    sample_id = row.get("sample_id")
    graph_hash = row.get("graph_hash")

    input_anchor_type = "unknown"
    input_anchor_value = ""
    if isinstance(anchor, dict):
        input_anchor_type = str(anchor.get("anchor_type", "unknown"))
        input_anchor_value = str(anchor.get("anchor_value", ""))
    if not input_anchor_value:
        if isinstance(sample_id, str) and sample_id:
            input_anchor_type = "sample_id"
            input_anchor_value = sample_id
        elif isinstance(graph_hash, str) and graph_hash:
            input_anchor_type = "graph_hash"
            input_anchor_value = graph_hash

    proof = {
        "input_anchor_type": input_anchor_type,
        "input_anchor_value": input_anchor_value,
        "resolution_method": "",
        "resolved_graph_family_key": "",
        "proof_status": "quarantined",
    }

    resolved_cir: dict[str, Any] | None = None
    resolved_family_key: str | None = None

    if isinstance(sample_id, str) and sample_id:
        resolved_cir = cir_index["by_sample_id"].get(sample_id)
        if resolved_cir is not None:
            resolved_family_key = str(resolved_cir["graph_family_key"])
            proof["resolution_method"] = "deterministic_cir_join_v1:sample_id"

    if resolved_cir is None and isinstance(graph_hash, str) and graph_hash:
        sample_ids = cir_index["by_graph_hash"].get(graph_hash, [])
        if len(sample_ids) == 1:
            resolved_cir = cir_index["by_sample_id"][sample_ids[0]]
            resolved_family_key = str(resolved_cir["graph_family_key"])
            proof["resolution_method"] = "deterministic_cir_join_v1:graph_hash"

    if resolved_cir is None and isinstance(anchor, dict):
        anchor_type = str(anchor.get("anchor_type", ""))
        anchor_value = str(anchor.get("anchor_value", ""))
        if anchor_type == "sample_id" and anchor_value:
            resolved_cir = cir_index["by_sample_id"].get(anchor_value)
            if resolved_cir is not None:
                resolved_family_key = str(resolved_cir["graph_family_key"])
                proof["resolution_method"] = "deterministic_cir_join_v1:family_anchor_sample_id"
        if resolved_cir is None and anchor_type == "graph_hash" and anchor_value:
            sample_ids = cir_index["by_graph_hash"].get(anchor_value, [])
            if len(sample_ids) == 1:
                resolved_cir = cir_index["by_sample_id"][sample_ids[0]]
                resolved_family_key = str(resolved_cir["graph_family_key"])
                proof["resolution_method"] = "deterministic_cir_join_v1:family_anchor_graph_hash"

    if resolved_family_key is not None:
        proof["resolved_graph_family_key"] = resolved_family_key
        proof["proof_status"] = "resolved"
        return resolved_family_key, proof, resolved_cir

    return None, proof, None


def _runtime_candidate_to_pair(
    row: dict[str, Any],
    *,
    request: DatasetBuildRequest,
    cir_record: dict[str, Any],
    graph_family_key: str,
    family_resolution_proof: dict[str, str],
) -> dict[str, Any] | None:
    chosen_json = _json_payload(row.get("corrected_target_json"))
    rejected_json = _json_payload(row.get("raw_llm_output"))
    if chosen_json is None or rejected_json is None:
        return None
    chosen = canonical_json_string(chosen_json)
    rejected = canonical_json_string(rejected_json)
    if chosen == rejected:
        return None
    source_text = str(row.get("source") or row.get("source_text") or "").strip()
    if not source_text:
        return None

    correction_tier = str(row.get("correction_tier", ""))
    if correction_tier == "tier_d_auto_repair_only":
        return None
    if correction_tier not in {"tier_b_deterministic_canonical", "tier_c_reviewed_merge", "tier_a_human_gold"}:
        return None
    preference_id = f"pref-{str(row.get('failure_id') or row.get('runtime_failure_id') or 'runtime')}"
    messages = render_preference_messages(source_text=source_text, cir_record=cir_record)
    normalized_source_hash = normalized_source_hash_v1(source_text)
    metadata = {
        "split": "",
        "task_type": "preference",
        "contract_version": request.contract_version,
        "preference_id": preference_id,
        "preference_origin": "runtime_failure_reviewed_merge",
        "correction_tier": correction_tier,
        "difficulty_bucket": str(cir_record.get("difficulty_bucket", "")),
        "graph_family_key": graph_family_key,
        "normalized_source_hash": normalized_source_hash,
        "split_family_id": graph_family_key,
        "family_resolution_proof": family_resolution_proof,
        "sample_id": row.get("sample_id") or cir_record.get("sample_id"),
        "graph_hash": cir_record.get("graph_hash"),
        "pattern_name": cir_record.get("pattern_name"),
        "pattern_family": cir_record.get("internal_metadata", {}).get("pattern_family"),
        "source_variant_key": cir_record.get("source_variant_key"),
        "complexity_class": cir_record.get("complexity_class"),
        "semantic_tags": cir_record.get("semantic_tags", []),
        "runtime_failure_id": row.get("failure_id") or row.get("runtime_failure_id"),
        "source_text_token_count": token_count(source_text),
    }
    return {
        "preference_id": preference_id,
        "task_type": "preference",
        "messages": messages,
        "chosen": chosen,
        "rejected": rejected,
        "chosen_json": chosen_json,
        "rejected_json": rejected_json,
        "packaging_metadata": metadata,
        "source_text": source_text,
    }


def _offline_candidate_to_pair(
    row: dict[str, Any],
    *,
    request: DatasetBuildRequest,
    cir_record: dict[str, Any],
    graph_family_key: str,
    family_resolution_proof: dict[str, str],
) -> dict[str, Any] | None:
    chosen_json = _json_payload(row.get("good_json") or row.get("corrected_target_json"))
    rejected_json = _json_payload(row.get("bad_json") or row.get("raw_llm_output"))
    if chosen_json is None or rejected_json is None:
        return None
    chosen = canonical_json_string(chosen_json)
    rejected = canonical_json_string(rejected_json)
    if chosen == rejected:
        return None
    source_text = str(row.get("source") or row.get("source_text") or "").strip()
    if not source_text:
        source_text = str(row.get("prompt") or "")
    if not source_text:
        return None
    correction_tier = str(row.get("correction_tier", "tier_b_deterministic_canonical"))
    if correction_tier == "tier_d_auto_repair_only":
        return None
    preference_id = f"pref-{str(row.get('eval_case_id') or row.get('sample_id') or 'offline')}"
    messages = render_preference_messages(source_text=source_text, cir_record=cir_record)
    normalized_source_hash = normalized_source_hash_v1(source_text)
    metadata = {
        "split": "",
        "task_type": "preference",
        "contract_version": request.contract_version,
        "preference_id": preference_id,
        "preference_origin": "offline_eval_bad_vs_corrected",
        "correction_tier": correction_tier,
        "difficulty_bucket": str(cir_record.get("difficulty_bucket", "")),
        "graph_family_key": graph_family_key,
        "normalized_source_hash": normalized_source_hash,
        "split_family_id": graph_family_key,
        "family_resolution_proof": family_resolution_proof,
        "sample_id": row.get("sample_id") or cir_record.get("sample_id"),
        "graph_hash": cir_record.get("graph_hash"),
        "pattern_name": cir_record.get("pattern_name"),
        "pattern_family": cir_record.get("internal_metadata", {}).get("pattern_family"),
        "source_variant_key": cir_record.get("source_variant_key"),
        "complexity_class": cir_record.get("complexity_class"),
        "semantic_tags": cir_record.get("semantic_tags", []),
        "source_text_token_count": token_count(source_text),
    }
    return {
        "preference_id": preference_id,
        "task_type": "preference",
        "messages": messages,
        "chosen": chosen,
        "rejected": rejected,
        "chosen_json": chosen_json,
        "rejected_json": rejected_json,
        "packaging_metadata": metadata,
        "source_text": source_text,
    }


def build_preference_pairs(
    request: DatasetBuildRequest,
    *,
    raw_candidates: list[dict[str, Any]],
    cir_index: dict[str, Any],
    heldout_sft_family_ids: set[str],
) -> PreferenceBuildResult:
    splitable: list[dict[str, Any]] = []
    quarantined: list[dict[str, Any]] = []
    dropped: list[dict[str, Any]] = []

    for row in raw_candidates:
        row_copy = deepcopy(row)
        graph_family_key, proof, cir_record = _resolve_anchor(row_copy, cir_index=cir_index)
        if graph_family_key is None or cir_record is None:
            quarantined.append(
                {
                    "candidate_id": row_copy.get("failure_id") or row_copy.get("eval_case_id") or row_copy.get("sample_id"),
                    "reason": "missing_deterministic_canonical_family_join",
                    "family_resolution_proof": proof,
                }
            )
            continue
        if graph_family_key in heldout_sft_family_ids:
            quarantined.append(
                {
                    "candidate_id": row_copy.get("failure_id") or row_copy.get("eval_case_id") or row_copy.get("sample_id"),
                    "reason": "overlaps_sft_heldout_family",
                    "family_resolution_proof": proof,
                }
            )
            continue

        origin = str(row_copy.get("_preference_origin", ""))
        if origin == "runtime_failure_reviewed_merge":
            pair = _runtime_candidate_to_pair(
                row_copy,
                request=request,
                cir_record=cir_record,
                graph_family_key=graph_family_key,
                family_resolution_proof=proof,
            )
        else:
            pair = _offline_candidate_to_pair(
                row_copy,
                request=request,
                cir_record=cir_record,
                graph_family_key=graph_family_key,
                family_resolution_proof=proof,
            )

        if pair is None:
            dropped.append(
                {
                    "candidate_id": row_copy.get("failure_id") or row_copy.get("eval_case_id") or row_copy.get("sample_id"),
                    "reason": "invalid_pair_or_formatting_only_difference",
                }
            )
            continue
        splitable.append(pair)

    # preference-id dedup
    unique: dict[str, dict[str, Any]] = {}
    for row in sorted(splitable, key=lambda item: item["preference_id"]):
        unique.setdefault(row["preference_id"], row)
    splitable = list(unique.values())

    # near-duplicate preference dedup
    by_dedup_key: dict[str, dict[str, Any]] = {}
    for row in splitable:
        metadata = row["packaging_metadata"]
        key = "|".join(
            [
                str(metadata["graph_family_key"]),
                str(metadata["normalized_source_hash"]),
                row["chosen"],
                row["rejected"],
            ]
        )
        by_dedup_key.setdefault(key, row)
    splitable = sorted(by_dedup_key.values(), key=lambda item: item["preference_id"])
    return PreferenceBuildResult(
        splitable_records=splitable,
        quarantined_records=quarantined,
        dropped_records=dropped,
    )

