from __future__ import annotations

from copy import deepcopy
from typing import Any

from dataset_builder.ingest import build_cir_indices

from .config import ExportEvalCasesRequest, ExportEvalCasesResult
from .io import read_jsonl, write_json, write_jsonl


def _as_dict(value: object) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return {}


def _as_list(value: object) -> list[Any]:
    if isinstance(value, list):
        return value
    return []


def _critical_eval_tags(*, cir_record: dict[str, Any], correction_tier: str) -> list[str]:
    tags = {str(item) for item in _as_list(cir_record.get("semantic_tags"))}
    result: list[str] = []
    if "ordinal_reference" in tags:
        result.append("ordinal_cases")
    if str(cir_record.get("source_variant_key", "")) == "morphology_stress":
        result.append("marked_object_morphology")
    if "same_type_markers" in tags:
        result.append("same_type_markers")
    if "described_action" in tags:
        result.append("unsupported_action_cases")
    beat_count = int(_as_dict(cir_record.get("budgets")).get("beat_count", 0))
    if beat_count >= 3:
        result.append("three_beat_cases")
    if "marked_object" in tags or "same_type_markers" in tags:
        result.append("exact_marker_identity_cases")
    if correction_tier == "tier_c_reviewed_merge":
        result.append("reviewed_merge_cases")
    return sorted(set(result))


def _expectations_from_cir(cir_record: dict[str, Any], correction_tier: str) -> dict[str, Any]:
    scene_graph = _as_dict(cir_record.get("scene_graph"))
    constraints = _as_dict(scene_graph.get("constraints"))
    beats = _as_list(scene_graph.get("beats"))

    expected_marked_object_ids = [
        str(item.get("id"))
        for item in _as_list(scene_graph.get("objects"))
        if isinstance(item, dict) and str(item.get("id", "")).startswith("object_marked_")
    ]

    expected_action_units: list[dict[str, Any]] = []
    expected_phase_sequence: list[str] = []
    for beat_index, beat in enumerate(beats, start=1):
        if not isinstance(beat, dict):
            continue
        phase_label = str(beat.get("phase", f"beat_{beat_index}"))
        expected_phase_sequence.append(phase_label)
        for action in _as_list(beat.get("actions")):
            if not isinstance(action, dict):
                continue
            unit = {
                "beat_index": beat_index,
                "actor_id": str(action.get("actor_id", "")),
                "action_type": str(action.get("type", "")),
                "phase_label": phase_label,
            }
            if "target_id" in action:
                unit["target_id"] = action.get("target_id")
            described_action = _as_dict(action.get("described_action"))
            if described_action:
                source_text = str(described_action.get("source_text", "")).strip()
                if source_text:
                    unit["fallback_text_lemmas"] = [source_text]
            expected_action_units.append(unit)

    return {
        "expected_marked_object_ids": expected_marked_object_ids,
        "expected_ordinal_bindings": _as_dict(constraints.get("ordinal_bindings")),
        "expected_action_units": expected_action_units,
        "expected_phase_sequence": expected_phase_sequence,
        "critical_eval_tags": _critical_eval_tags(cir_record=cir_record, correction_tier=correction_tier),
    }


def _cir_for_row(row: dict[str, Any], cir_index: dict[str, Any]) -> dict[str, Any] | None:
    sample_id = str(row.get("sample_id", "")).strip()
    if sample_id:
        cir_record = _as_dict(cir_index["by_sample_id"].get(sample_id))
        if cir_record:
            return cir_record

    graph_hash = str(row.get("graph_hash", "")).strip()
    if graph_hash:
        sample_ids = _as_list(_as_dict(cir_index).get("by_graph_hash", {}).get(graph_hash))
        if len(sample_ids) == 1:
            resolved_sample = str(sample_ids[0])
            return _as_dict(cir_index["by_sample_id"].get(resolved_sample))

    family_anchor = _as_dict(row.get("family_anchor"))
    anchor_type = str(family_anchor.get("anchor_type", "")).strip()
    anchor_value = str(family_anchor.get("anchor_value", "")).strip()
    if anchor_type == "sample_id" and anchor_value:
        cir_record = _as_dict(cir_index["by_sample_id"].get(anchor_value))
        if cir_record:
            return cir_record
    if anchor_type == "graph_hash" and anchor_value:
        sample_ids = _as_list(_as_dict(cir_index).get("by_graph_hash", {}).get(anchor_value))
        if len(sample_ids) == 1:
            resolved_sample = str(sample_ids[0])
            return _as_dict(cir_index["by_sample_id"].get(resolved_sample))
    anchor_graph_family = str(family_anchor.get("graph_family_key", "")).strip()
    if anchor_graph_family:
        sample_ids = _as_list(_as_dict(cir_index).get("by_graph_family", {}).get(anchor_graph_family))
        if sample_ids:
            resolved_sample = str(sorted(sample_ids)[0])
            return _as_dict(cir_index["by_sample_id"].get(resolved_sample))
    return None


def export_real_runtime_eval_cases(request: ExportEvalCasesRequest) -> ExportEvalCasesResult:
    rows = read_jsonl(request.runtime_failures_jsonl)
    cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)

    eval_cases: list[dict[str, Any]] = []
    quarantined: list[dict[str, Any]] = []
    for row in rows:
        failure_id = str(row.get("failure_id", "")).strip()
        if not failure_id:
            quarantined.append({"candidate_id": "", "reason": "missing_failure_id"})
            continue
        if not bool(row.get("eval_bridge_ready", False)):
            quarantined.append(
                {
                    "candidate_id": failure_id,
                    "reason": str(row.get("eval_bridge_block_reason", "eval_bridge_not_ready")),
                }
            )
            continue
        corrected = row.get("corrected_target_json")
        if not isinstance(corrected, dict):
            quarantined.append({"candidate_id": failure_id, "reason": "missing_corrected_target_json"})
            continue
        rule_ref = row.get("rule_based_reference_json")
        if not isinstance(rule_ref, dict):
            quarantined.append({"candidate_id": failure_id, "reason": "missing_rule_based_reference_json"})
            continue
        runtime_policy_inputs = row.get("runtime_policy_inputs")
        if not isinstance(runtime_policy_inputs, dict):
            quarantined.append({"candidate_id": failure_id, "reason": "missing_runtime_policy_inputs"})
            continue

        cir_record = _cir_for_row(row, cir_index)
        if cir_record is None:
            quarantined.append({"candidate_id": failure_id, "reason": "missing_deterministic_cir_join"})
            continue

        sample_id = str(row.get("sample_id") or cir_record.get("sample_id") or "").strip()
        graph_family_key = str(row.get("graph_family_key") or cir_record.get("graph_family_key") or "").strip()
        correction_tier = str(row.get("correction_tier", ""))
        eval_case = {
            "eval_case_id": failure_id,
            "eval_set": "real_runtime",
            "sample_id": sample_id,
            "graph_family_key": graph_family_key,
            "contract_version": request.contract_version,
            "difficulty_bucket": str(cir_record.get("difficulty_bucket", "")),
            "source_text": str(row.get("source", "")),
            "marked_objects": _as_list(row.get("marked_objects")),
            "gold_target_json": corrected,
            "rule_based_reference_json": rule_ref,
            "eval_expectations": _expectations_from_cir(cir_record, correction_tier),
            "runtime_policy_inputs": runtime_policy_inputs,
            "provenance": {
                "origin": "runtime_reviewed",
                "correction_tier": correction_tier,
                "review_status": str(row.get("review_status", "")),
                "gold_source": str(row.get("gold_source", "")),
                "final_script_source": str(row.get("final_script_source", "")),
                "runtime_failure_id": failure_id,
            },
        }
        eval_cases.append(eval_case)

    manifest = {
        "runtime_eval_export_version": "runtime_feedback_eval_export_v1",
        "input_runtime_failure_count": len(rows),
        "exported_eval_case_count": len(eval_cases),
        "quarantined_count": len(quarantined),
    }

    write_jsonl(eval_cases, request.output_eval_cases_jsonl)
    write_jsonl(quarantined, request.output_quarantine_jsonl)
    write_json(manifest, request.output_manifest_json)

    return ExportEvalCasesResult(
        eval_cases=deepcopy(eval_cases),
        quarantined=deepcopy(quarantined),
        manifest=deepcopy(manifest),
    )
