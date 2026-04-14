from __future__ import annotations

from copy import deepcopy
import hashlib
from typing import Any

from .clustering import build_cluster_id, build_cluster_manifest, build_failure_signature, normalize_source_template
from .config import NormalizeRuntimeFeedbackRequest, NormalizeRuntimeFeedbackResult
from .expectations import compute_source_expectations, load_unsupported_action_lemmas
from .io import read_jsonl, write_json, write_jsonl
from .taxonomy import build_taxonomy_labels, choose_dominant_label


def _as_dict(value: object) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return {}


def _as_list(value: object) -> list[Any]:
    if isinstance(value, list):
        return value
    return []


def _source_hash(source: str) -> str:
    return "sha256:" + hashlib.sha256(source.encode("utf-8")).hexdigest()[:16]


def _infer_action_count(script: dict[str, Any]) -> int:
    actions = script.get("actions")
    if isinstance(actions, list):
        return len(actions)
    beats = script.get("beats")
    if isinstance(beats, list):
        total = 0
        for beat in beats:
            if not isinstance(beat, dict):
                continue
            beat_actions = beat.get("actions")
            if isinstance(beat_actions, list):
                total += len(beat_actions)
        return total
    return 0


def _infer_beat_count(script: dict[str, Any]) -> int:
    beats = script.get("beats")
    if isinstance(beats, list):
        return len(beats)
    return 0


def _infer_has_dangling_targets(script: dict[str, Any]) -> bool:
    interesting = {"approach", "stop", "stand", "pass_by"}
    actions = _as_list(script.get("actions"))
    if not actions:
        for beat in _as_list(script.get("beats")):
            if isinstance(beat, dict):
                actions.extend(_as_list(beat.get("actions")))
    for action in actions:
        if not isinstance(action, dict):
            continue
        action_type = str(action.get("type", ""))
        if action_type in interesting and action.get("target") is None and action.get("targetId") is None:
            return True
    return False


def _script_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    flat_actions = _as_list(script.get("actions"))
    for item in flat_actions:
        if isinstance(item, dict):
            actions.append(item)
    if actions:
        return actions
    for beat in _as_list(script.get("beats")):
        if not isinstance(beat, dict):
            continue
        for item in _as_list(beat.get("actions")):
            if isinstance(item, dict):
                actions.append(item)
    return actions


def _has_described_action(script: dict[str, Any]) -> bool:
    for action in _script_actions(script):
        action_type = str(action.get("type", "")).strip()
        if action_type == "described_action":
            return True
    return False


def _ordinal_binding_lost(*, normalized_source: str, final_script: dict[str, Any]) -> bool:
    actor_ids = {
        str(actor.get("id", ""))
        for actor in _as_list(final_script.get("actors"))
        if isinstance(actor, dict)
    }
    if "перв" in normalized_source and "actor_1" not in actor_ids:
        return True
    if "втор" in normalized_source and "actor_2" not in actor_ids:
        return True
    if "трет" in normalized_source and "actor_3" not in actor_ids:
        return True
    return False


def _event_marked_objects(event: dict[str, Any]) -> list[dict[str, Any]]:
    rows = _as_list(event.get("marked_objects"))
    result: list[dict[str, Any]] = []
    for item in rows:
        if not isinstance(item, dict):
            continue
        result.append(dict(item))
    return result


def _low_quality_reason(
    *,
    decision: str,
    final_script: dict[str, Any],
    final_diagnostics: dict[str, Any],
    expectations: dict[str, Any],
) -> str | None:
    if decision != "accept":
        return None
    actions = _infer_action_count(final_script)
    beats = _infer_beat_count(final_script)
    expected_action_intents = int(expectations.get("expected_action_intents", 1))
    expected_multi_beat = bool(expectations.get("expected_multi_beat", False))
    expected_marked_mentions = int(expectations.get("expected_marked_object_mentions", 0))
    unresolved_marked = bool(final_diagnostics.get("unresolvedMarkedObjects", False))
    matched_marked = int(final_diagnostics.get("matchedMarkedObjectsCount", 0))
    normalized_source = str(expectations.get("normalized_source", ""))
    unsupported_action_present = bool(expectations.get("unsupported_action_present", False))
    has_described_action = _has_described_action(final_script)

    if actions <= 1 and expected_action_intents >= 2:
        return "lqa_rule_1"
    if beats == 1 and expected_multi_beat:
        return "lqa_rule_2"
    if unresolved_marked:
        return "lqa_rule_3"
    if matched_marked < expected_marked_mentions:
        return "lqa_rule_4"
    if _ordinal_binding_lost(normalized_source=normalized_source, final_script=final_script):
        return "lqa_rule_5"
    if unsupported_action_present and not has_described_action:
        return "lqa_rule_6"
    return None


def _build_family_anchor(event: dict[str, Any], source_hash: str) -> tuple[dict[str, Any], dict[str, Any]]:
    graph_family_key = str(event.get("graph_family_key", "")).strip()
    sample_id = str(event.get("sample_id", "")).strip()
    graph_hash = str(event.get("graph_hash", "")).strip()
    reviewed_seed = str(event.get("reviewed_pattern_family_seed", "")).strip()

    if graph_family_key:
        anchor = {
            "anchor_type": "graph_family_key",
            "anchor_value": graph_family_key,
            "graph_family_key": graph_family_key,
            "split_family_id": graph_family_key,
        }
        proof = {
            "input_anchor_type": "graph_family_key",
            "input_anchor_value": graph_family_key,
            "resolution_method": "runtime_direct_graph_family_key",
            "resolved_graph_family_key": graph_family_key,
            "proof_status": "resolved",
        }
        return anchor, proof

    if sample_id:
        anchor = {"anchor_type": "sample_id", "anchor_value": sample_id}
        proof = {
            "input_anchor_type": "sample_id",
            "input_anchor_value": sample_id,
            "resolution_method": "deterministic_cir_join_v1:sample_id",
            "resolved_graph_family_key": "",
            "proof_status": "resolved",
        }
        return anchor, proof

    if graph_hash:
        anchor = {"anchor_type": "graph_hash", "anchor_value": graph_hash}
        proof = {
            "input_anchor_type": "graph_hash",
            "input_anchor_value": graph_hash,
            "resolution_method": "deterministic_cir_join_v1:graph_hash",
            "resolved_graph_family_key": "",
            "proof_status": "resolved",
        }
        return anchor, proof

    if reviewed_seed:
        anchor = {"anchor_type": "reviewed_pattern_family_seed", "anchor_value": reviewed_seed}
        proof = {
            "input_anchor_type": "reviewed_pattern_family_seed",
            "input_anchor_value": reviewed_seed,
            "resolution_method": "",
            "resolved_graph_family_key": "",
            "proof_status": "quarantined",
        }
        return anchor, proof

    anchor = {"anchor_type": "unresolved_runtime_case", "anchor_value": f"source_sha256:{source_hash}"}
    proof = {
        "input_anchor_type": "unresolved_runtime_case",
        "input_anchor_value": f"source_sha256:{source_hash}",
        "resolution_method": "",
        "resolved_graph_family_key": "",
        "proof_status": "quarantined",
    }
    return anchor, proof


def _to_failure_record(
    *,
    event: dict[str, Any],
    index: int,
    unsupported_action_lemmas: set[str],
    contract_version: str,
) -> dict[str, Any] | None:
    selection = _as_dict(event.get("selection"))
    decision = str(selection.get("decision", "rule_only")).strip() or "rule_only"
    reason = str(selection.get("reason", "")).strip()
    source = str(event.get("source", "")).strip()
    if not source:
        return None

    marked_objects = _event_marked_objects(event)
    expectations = compute_source_expectations(
        source=source,
        marked_objects=marked_objects,
        unsupported_action_lemmas=unsupported_action_lemmas,
    )

    final_result = _as_dict(event.get("final_result"))
    final_script = _as_dict(final_result.get("script_json"))
    final_diagnostics = _as_dict(final_result.get("diagnostics"))
    low_quality_reason = _low_quality_reason(
        decision=decision,
        final_script=final_script,
        final_diagnostics=final_diagnostics,
        expectations=expectations,
    )

    user_marked_incorrect = bool(event.get("user_marked_incorrect", False))
    must_capture = decision in {"reject", "merge"} or low_quality_reason is not None or user_marked_incorrect
    if not must_capture:
        return None

    labels = build_taxonomy_labels(
        event=event,
        low_quality_reason=low_quality_reason,
        unsupported_action_present=bool(expectations.get("unsupported_action_present", False)),
    )
    dominant = choose_dominant_label(labels)

    rule_result = _as_dict(event.get("rule_based_result"))
    rule_script = _as_dict(rule_result.get("script_json"))
    rule_diagnostics = _as_dict(rule_result.get("diagnostics"))
    llm_result = _as_dict(event.get("llm_result"))
    llm_diagnostics = _as_dict(llm_result.get("diagnostics"))
    llm_script = _as_dict(llm_result.get("parsed_script_json"))

    source_hash = str(event.get("source_sha256", "")).strip() or _source_hash(source)
    failure_id = str(event.get("failure_id", "")).strip() or f"rtf_{index:06d}"
    event_id = str(event.get("event_id", "")).strip() or f"rtp_{index:06d}"
    timestamp = str(event.get("timestamp", "")).strip()
    sample_id = str(event.get("sample_id", "")).strip()
    graph_hash = str(event.get("graph_hash", "")).strip()
    graph_family_key = str(event.get("graph_family_key", "")).strip()
    privacy = _as_dict(event.get("privacy"))
    privacy_status = str(privacy.get("status", "clear")).strip() or "clear"

    rule_confidence = float(rule_diagnostics.get("confidence", 0.0))
    rule_objects = len(_as_list(rule_script.get("objects")))
    rule_actions = _infer_action_count(rule_script)
    rule_matched_marked = int(rule_diagnostics.get("matchedMarkedObjectsCount", 0))
    mentioned_marked_object_ids = [
        str(item.get("id") or item.get("object_id") or item.get("marker_id_hash"))
        for item in marked_objects
        if bool(item.get("mentioned_in_source", False))
    ]

    family_anchor, family_resolution_proof = _build_family_anchor(event, source_hash)
    final_script_source = str(selection.get("final_script_source", "")).strip() or "rule_based"
    row: dict[str, Any] = {
        "failure_id": failure_id,
        "event_id": event_id,
        "timestamp": timestamp,
        "contract_version": contract_version,
        "sample_id": sample_id,
        "graph_hash": graph_hash,
        "graph_family_key": graph_family_key,
        "source": source,
        "source_sha256": source_hash,
        "privacy_status": privacy_status,
        "marked_objects": marked_objects,
        "raw_llm_output": llm_script,
        "raw_llm_text": str(llm_result.get("raw_llm_text", "")),
        "repaired_llm_output": _as_dict(llm_result.get("repaired_llm_output")),
        "diagnostics": {
            "rule_based_confidence": rule_confidence,
            "llm_confidence": float(llm_diagnostics.get("confidence", 0.0)),
            "final_confidence": float(final_diagnostics.get("confidence", 0.0)),
            "unresolved_marked_objects": bool(final_diagnostics.get("unresolvedMarkedObjects", False)),
            "matched_marked_objects_count": int(final_diagnostics.get("matchedMarkedObjectsCount", 0)),
        },
        "rule_based_reference_json": rule_script,
        "runtime_policy_inputs": {
            "rule_confidence": rule_confidence,
            "rule_object_count": rule_objects,
            "rule_action_count": rule_actions,
            "rule_has_dangling_targets": _infer_has_dangling_targets(rule_script),
            "rule_matched_marked_object_count": rule_matched_marked,
            "mentioned_marked_object_ids": mentioned_marked_object_ids,
        },
        "final_decision": decision,
        "final_script_source": final_script_source,
        "reject_reason": reason,
        "failure_taxonomy": {"labels": labels, "dominant": dominant},
        "family_anchor": family_anchor,
        "family_resolution_proof": family_resolution_proof,
        "source_expectations": expectations,
        "low_quality_accept_policy_version": "low_quality_accept_v1",
        "low_quality_accept_reason": low_quality_reason or "",
        "corrected_target_json": None,
        "gold_source": "pending_review",
        "correction_tier": "",
        "review_status": "pending",
        "review_notes": "",
        "train_eligibility": "review_only",
        "eval_bridge_ready": False,
        "eval_bridge_block_reason": "review_not_approved",
        "final_result": final_result,
    }

    source_template = normalize_source_template(source, marked_objects)
    failure_signature = build_failure_signature(row)
    row["cluster"] = {
        "failure_signature": failure_signature,
        "cluster_id": build_cluster_id(
            failure_signature=failure_signature,
            normalized_source_template=source_template,
        ),
        "cluster_version": "runtime_cluster_v1",
    }
    return row


def normalize_runtime_feedback(request: NormalizeRuntimeFeedbackRequest) -> NormalizeRuntimeFeedbackResult:
    events = read_jsonl(request.runtime_events_jsonl)
    lemmas = load_unsupported_action_lemmas(request.unsupported_action_lemmas_path)

    failures: list[dict[str, Any]] = []
    for index, event in enumerate(events, start=1):
        row = _to_failure_record(
            event=event,
            index=index,
            unsupported_action_lemmas=lemmas,
            contract_version=request.contract_version,
        )
        if row is not None:
            failures.append(row)

    review_queue = [
        {
            "failure_id": str(row["failure_id"]),
            "cluster_id": str(_as_dict(row.get("cluster")).get("cluster_id", "")),
            "dominant_label": str(_as_dict(row.get("failure_taxonomy")).get("dominant", "")),
            "review_status": str(row.get("review_status", "")),
            "source": str(row.get("source", "")),
        }
        for row in failures
        if str(row.get("review_status", "")) == "pending"
    ]

    cluster_manifest = build_cluster_manifest(failures)
    manifest = {
        "runtime_feedback_version": "runtime_feedback_impl_v1",
        "contract_version": request.contract_version,
        "input_event_count": len(events),
        "runtime_failure_count": len(failures),
        "review_queue_count": len(review_queue),
        "cluster_count": int(cluster_manifest.get("cluster_count", 0)),
    }

    write_jsonl(failures, request.runtime_failures_jsonl)
    write_jsonl(review_queue, request.review_queue_jsonl)
    write_json(cluster_manifest, request.cluster_manifest_json)
    write_json(manifest, request.manifest_json)

    return NormalizeRuntimeFeedbackResult(
        runtime_failures=deepcopy(failures),
        review_queue=deepcopy(review_queue),
        cluster_manifest=deepcopy(cluster_manifest),
        manifest=deepcopy(manifest),
    )
