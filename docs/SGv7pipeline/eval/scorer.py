from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any

from .runtime_policy import TARGET_REQUIRED_ACTIONS, replay_runtime_policy


EVAL_SETS = ["synthetic_heldout", "hard_heldout", "real_runtime"]
CRITICAL_BUCKETS = [
    "ordinal_cases",
    "marked_object_morphology",
    "same_type_markers",
    "unsupported_action_cases",
    "three_beat_cases",
    "exact_marker_identity_cases",
    "reviewed_merge_cases",
]
CHRONOLOGY_SENSITIVE_BUCKETS = {
    "ordinal_cases",
    "three_beat_cases",
    "unsupported_action_cases",
    "exact_marker_identity_cases",
    "reviewed_merge_cases",
}


@dataclass(frozen=True)
class ScoreCasesRequest:
    checkpoint_id: str
    cases: list[dict[str, Any]]
    predicted_by_case: dict[str, dict[str, Any] | None]
    runtime_policy_snapshot: dict[str, Any]


def _normalize_action_type(value: Any) -> str:
    return str(value or "").strip().replace("-", "_").replace(" ", "_").lower()


def _normalize_text(value: Any) -> str:
    return " ".join(str(value or "").lower().replace("\n", " ").split())


def _as_list(payload: Any) -> list[Any]:
    return payload if isinstance(payload, list) else []


def _as_dict(payload: Any) -> dict[str, Any]:
    return payload if isinstance(payload, dict) else {}


def _collect_actor_ids(script: dict[str, Any]) -> set[str]:
    actors = _as_list(script.get("actors"))
    return {str(actor.get("id", "")).strip() for actor in actors if isinstance(actor, dict) and str(actor.get("id", "")).strip()}


def _collect_object_ids(script: dict[str, Any]) -> set[str]:
    objects = _as_list(script.get("objects"))
    return {str(obj.get("id", "")).strip() for obj in objects if isinstance(obj, dict) and str(obj.get("id", "")).strip()}


def _collect_marked_object_ids(script: dict[str, Any]) -> set[str]:
    return {obj_id for obj_id in _collect_object_ids(script) if obj_id.startswith("object_marked_")}


def _flatten_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    top_level = script.get("actions")
    if isinstance(top_level, list):
        for action in top_level:
            if not isinstance(action, dict):
                continue
            actions.append(
                {
                    "beat_index": int(action.get("beatIndex", 0) or 0),
                    "actor_id": str(action.get("actorId") or action.get("actor_id") or "").strip(),
                    "action_type": _normalize_action_type(action.get("type")),
                    "target_id": str(action.get("target") or action.get("targetId") or "").strip(),
                    "fallback_text": _normalize_text(action.get("fallbackText") or action.get("fallback_text") or ""),
                }
            )
    beats = script.get("beats")
    if isinstance(beats, list):
        for beat_idx, beat in enumerate(beats, start=1):
            if not isinstance(beat, dict):
                continue
            beat_actions = beat.get("actions")
            if not isinstance(beat_actions, list):
                continue
            for action in beat_actions:
                if not isinstance(action, dict):
                    continue
                actions.append(
                    {
                        "beat_index": beat_idx,
                        "actor_id": str(action.get("actorId") or action.get("actor_id") or "").strip(),
                        "action_type": _normalize_action_type(action.get("type")),
                        "target_id": str(action.get("target") or action.get("targetId") or "").strip(),
                        "fallback_text": _normalize_text(action.get("fallbackText") or action.get("fallback_text") or ""),
                    }
                )
    return actions


def _canonical_parse_ok(script: dict[str, Any]) -> bool:
    if not isinstance(script, dict):
        return False
    for name in ("actors", "objects"):
        if name in script and not isinstance(script.get(name), list):
            return False
    if "beats" in script and not isinstance(script.get("beats"), list):
        return False
    if "actions" in script and not isinstance(script.get("actions"), list):
        return False
    return True


def _action_refs(action: dict[str, Any]) -> tuple[str, str] | None:
    actor_camel = str(action.get("actorId") or "").strip()
    actor_snake = str(action.get("actor_id") or "").strip()
    if actor_camel and actor_snake and actor_camel != actor_snake:
        return None
    actor_id = actor_camel or actor_snake

    target_camel = str(action.get("targetId") or "").strip()
    target_plain = str(action.get("target") or "").strip()
    if target_camel and target_plain and target_camel != target_plain:
        return None
    target_id = target_plain or target_camel
    return actor_id, target_id


def _schema_valid_action(action: dict[str, Any], *, actor_ids: set[str], valid_target_ids: set[str]) -> bool:
    refs = _action_refs(action)
    if refs is None:
        return False
    actor_id, target_id = refs
    if not actor_id or actor_id not in actor_ids:
        return False

    action_type = _normalize_action_type(action.get("type"))
    if not action_type:
        return False
    if target_id and target_id not in valid_target_ids:
        return False
    if action_type in TARGET_REQUIRED_ACTIONS and not target_id:
        return False
    return True


def _schema_valid(script: dict[str, Any]) -> bool:
    actors = _as_list(script.get("actors"))
    objects = _as_list(script.get("objects"))
    actor_ids: set[str] = set()
    object_ids: set[str] = set()
    for actor in actors:
        if not isinstance(actor, dict):
            return False
        actor_id = str(actor.get("id", "")).strip()
        if not actor_id or actor_id in actor_ids:
            return False
        actor_ids.add(actor_id)
    for obj in objects:
        if not isinstance(obj, dict):
            return False
        object_id = str(obj.get("id", "")).strip()
        if not object_id or object_id in object_ids:
            return False
        object_ids.add(object_id)

    valid_target_ids = actor_ids.union(object_ids)

    top_level_actions = script.get("actions")
    if top_level_actions is not None and not isinstance(top_level_actions, list):
        return False
    for action in _as_list(top_level_actions):
        if not isinstance(action, dict):
            return False
        if not _schema_valid_action(action, actor_ids=actor_ids, valid_target_ids=valid_target_ids):
            return False

    beats = script.get("beats")
    if beats is not None and not isinstance(beats, list):
        return False
    for beat in _as_list(beats):
        if not isinstance(beat, dict):
            return False
        beat_actions = beat.get("actions")
        if beat_actions is not None and not isinstance(beat_actions, list):
            return False
        for action in _as_list(beat_actions):
            if not isinstance(action, dict):
                return False
            if not _schema_valid_action(action, actor_ids=actor_ids, valid_target_ids=valid_target_ids):
                return False
    return True


def _action_matches(
    expected: dict[str, Any],
    predicted: dict[str, Any],
    *,
    require_beat_index: bool,
    require_target_for_target_units: bool,
) -> bool:
    actor_id = str(expected.get("actor_id") or "").strip()
    if actor_id and predicted["actor_id"] != actor_id:
        return False
    action_type = _normalize_action_type(expected.get("action_type"))
    if action_type and predicted["action_type"] != action_type:
        return False
    beat_index = int(expected.get("beat_index", 0) or 0)
    if require_beat_index and beat_index > 0 and predicted["beat_index"] != beat_index:
        return False
    target_id = str(expected.get("target_id") or "").strip()
    if require_target_for_target_units and target_id:
        if predicted["target_id"] != target_id:
            return False
    fallback_lemmas = [str(item).strip().lower() for item in _as_list(expected.get("fallback_text_lemmas")) if str(item).strip()]
    if fallback_lemmas:
        fallback_text = predicted["fallback_text"]
        if not all(lemma in fallback_text for lemma in fallback_lemmas):
            return False
    return True


def _match_expected_actions(
    expected_actions: list[dict[str, Any]],
    predicted_actions: list[dict[str, Any]],
    *,
    require_beat_index: bool,
) -> tuple[int, set[int], int]:
    used_indices: set[int] = set()
    matched = 0
    matched_described = 0
    for expected in expected_actions:
        found_idx: int | None = None
        for idx, predicted in enumerate(predicted_actions):
            if idx in used_indices:
                continue
            if not _action_matches(
                expected,
                predicted,
                require_beat_index=require_beat_index,
                require_target_for_target_units=True,
            ):
                continue
            found_idx = idx
            break
        if found_idx is None:
            continue
        used_indices.add(found_idx)
        matched += 1
        if _normalize_action_type(expected.get("action_type")) == "described_action":
            matched_described += 1
    return matched, used_indices, matched_described


def _build_chronology_sequence(
    expected_actions: list[dict[str, Any]],
    predicted_actions: list[dict[str, Any]],
) -> tuple[list[str], bool]:
    predicted_sequence: list[str] = []
    used_indices: set[int] = set()
    for expected in expected_actions:
        phase_label = str(expected.get("phase_label") or "").strip()
        if not phase_label:
            continue
        found_idx: int | None = None
        for idx, predicted in enumerate(predicted_actions):
            if idx in used_indices:
                continue
            if not _action_matches(
                expected,
                predicted,
                require_beat_index=True,
                require_target_for_target_units=True,
            ):
                continue
            found_idx = idx
            break
        if found_idx is None:
            predicted_sequence.append(f"missing::{phase_label}")
            continue
        used_indices.add(found_idx)
        predicted_sequence.append(phase_label)
    has_missing = any(item.startswith("missing::") for item in predicted_sequence)
    return predicted_sequence, has_missing


def _count_invalid_target_actions(predicted_actions: list[dict[str, Any]], valid_ids: set[str]) -> tuple[int, int]:
    invalid = 0
    total = 0
    for action in predicted_actions:
        if action["action_type"] not in TARGET_REQUIRED_ACTIONS:
            continue
        total += 1
        target_id = action["target_id"]
        if not target_id or target_id not in valid_ids:
            invalid += 1
    return invalid, total


def _failure_code(case_result: dict[str, Any]) -> str:
    if not bool(case_result.get("json_valid")):
        return "json_invalid"
    if not bool(case_result.get("schema_valid")):
        return "schema_invalid"
    flags = _as_dict(case_result.get("metric_flags"))
    if not bool(flags.get("exact_marked_object_id_pass", False)):
        return "exact_marker_id_fail"
    if not bool(flags.get("ordinal_binding_pass", False)):
        return "ordinal_binding_fail"
    if not bool(flags.get("target_resolution_pass", False)):
        return "target_resolution_fail"
    if not bool(flags.get("chronology_phase_pass", False)):
        return "chronology_phase_fail"
    if not bool(flags.get("beat_count_pass", False)):
        return "beat_count_fail"
    if not bool(flags.get("action_recall_pass", False)):
        return "action_recall_fail"
    decision = str(case_result.get("runtime_policy_decision", ""))
    if decision == "reject":
        return "fallback_reject"
    if decision == "merge":
        return "fallback_merge"
    return "pass"


def _cluster_id(case_result: dict[str, Any]) -> str:
    eval_set = str(case_result.get("eval_set", "unknown"))
    primary_code = _failure_code(case_result)
    tags = sorted(str(tag) for tag in _as_list(case_result.get("bucket_tags")) if str(tag))
    primary_bucket = tags[0] if tags else "none"
    return f"{eval_set}::{primary_code}::{primary_bucket}"


def _case_score(
    case: dict[str, Any],
    *,
    checkpoint_id: str,
    predicted_script: dict[str, Any] | None,
    runtime_policy_snapshot: dict[str, Any],
) -> dict[str, Any]:
    eval_case_id = str(case["eval_case_id"])
    eval_set = str(case["eval_set"])
    expectations = _as_dict(case.get("eval_expectations"))
    expected_marked_ids = [str(item).strip() for item in _as_list(expectations.get("expected_marked_object_ids")) if str(item).strip()]
    expected_bindings = _as_dict(expectations.get("expected_ordinal_bindings"))
    expected_actions = [item for item in _as_list(expectations.get("expected_action_units")) if isinstance(item, dict)]
    expected_phase_sequence = [str(item).strip() for item in _as_list(expectations.get("expected_phase_sequence")) if str(item).strip()]
    bucket_tags = [str(item).strip() for item in _as_list(expectations.get("critical_eval_tags")) if str(item).strip()]
    require_beat_index = any(tag in CHRONOLOGY_SENSITIVE_BUCKETS for tag in bucket_tags)

    json_valid = isinstance(predicted_script, dict)
    canonical_parse = json_valid and _canonical_parse_ok(predicted_script if predicted_script is not None else {})
    schema_valid = canonical_parse and _schema_valid(predicted_script if predicted_script is not None else {})
    diagnostics_notes: list[str] = []
    if not json_valid:
        diagnostics_notes.append("predicted_script_not_json_object")
    elif not canonical_parse:
        diagnostics_notes.append("canonical_parse_failed")
    elif not schema_valid:
        diagnostics_notes.append("schema_validation_failed")

    safe_script = predicted_script if isinstance(predicted_script, dict) else {}
    predicted_actions = _flatten_actions(safe_script)
    predicted_actor_ids = _collect_actor_ids(safe_script)
    predicted_object_ids = _collect_object_ids(safe_script)
    predicted_marked_ids = _collect_marked_object_ids(safe_script)

    marked_expected = len(expected_marked_ids)
    marked_matched = len(predicted_marked_ids.intersection(set(expected_marked_ids)))
    marked_recall_case = 1.0 if marked_expected == 0 else marked_matched / marked_expected
    exact_marked_case = marked_recall_case
    exact_marked_pass = (marked_expected == 0) or (marked_matched == marked_expected)

    gold_target = _as_dict(case.get("gold_target_json"))
    gold_beats_payload = gold_target.get("beats")
    gold_beats = len(gold_beats_payload) if isinstance(gold_beats_payload, list) else 0
    if gold_beats <= 0 and expected_actions:
        gold_beats = max(int(item.get("beat_index", 0) or 0) for item in expected_actions)
    predicted_beats_payload = safe_script.get("beats")
    predicted_beats = len(predicted_beats_payload) if isinstance(predicted_beats_payload, list) else 0
    beat_count_pass = (gold_beats == 0) or (predicted_beats == gold_beats)

    action_matched, action_used, described_matched = _match_expected_actions(
        expected_actions,
        predicted_actions,
        require_beat_index=require_beat_index,
    )
    action_total = len(expected_actions)
    action_recall_case = 1.0 if action_total == 0 else action_matched / action_total
    action_recall_pass = action_recall_case >= 1.0 - 1e-12

    expected_described = sum(
        1 for item in expected_actions if _normalize_action_type(item.get("action_type")) == "described_action"
    )
    predicted_described = sum(1 for item in predicted_actions if item["action_type"] == "described_action")
    if predicted_described == 0:
        described_precision_case = 1.0 if expected_described == 0 else 0.0
    else:
        described_precision_case = described_matched / predicted_described

    ordinal_total = len(expected_bindings)
    ordinal_matched = 0
    for _, actor_id in expected_bindings.items():
        if str(actor_id).strip() in predicted_actor_ids:
            ordinal_matched += 1
    ordinal_case = 1.0 if ordinal_total == 0 else ordinal_matched / ordinal_total
    ordinal_pass = ordinal_case >= 1.0 - 1e-12

    target_expected = [item for item in expected_actions if str(item.get("target_id") or "").strip()]
    target_total = len(target_expected)
    target_matched, _, _ = _match_expected_actions(
        target_expected,
        predicted_actions,
        require_beat_index=require_beat_index,
    )
    target_case = 1.0 if target_total == 0 else target_matched / target_total
    target_pass = target_case >= 1.0 - 1e-12

    chronology_sequence, chronology_missing = _build_chronology_sequence(expected_actions, predicted_actions)
    chronology_expected_total = len(expected_phase_sequence)
    chronology_pass = False
    if chronology_expected_total == 0:
        chronology_pass = True
    else:
        chronology_pass = chronology_sequence == expected_phase_sequence and not chronology_missing
    chronology_case = 1.0 if chronology_pass else 0.0

    invalid_targets, required_targets = _count_invalid_target_actions(
        predicted_actions,
        valid_ids=predicted_actor_ids.union(predicted_object_ids),
    )
    dangling_case = 0.0 if required_targets == 0 else invalid_targets / required_targets

    runtime_policy = replay_runtime_policy(
        predicted_script,
        expected_marked_object_ids=expected_marked_ids,
        runtime_policy_inputs=_as_dict(case.get("runtime_policy_inputs")),
        runtime_policy_snapshot=runtime_policy_snapshot,
    )

    metric_flags = {
        "marked_object_recall_pass": marked_recall_case >= 1.0 - 1e-12,
        "exact_marked_object_id_pass": exact_marked_pass,
        "beat_count_pass": beat_count_pass,
        "action_recall_pass": action_recall_pass,
        "described_action_precision_pass": described_precision_case >= 1.0 - 1e-12,
        "ordinal_binding_pass": ordinal_pass,
        "target_resolution_pass": target_pass,
        "chronology_phase_pass": chronology_pass,
    }

    case_result: dict[str, Any] = {
        "eval_case_id": eval_case_id,
        "eval_set": eval_set,
        "checkpoint_id": checkpoint_id,
        "json_valid": json_valid,
        "canonical_parse": canonical_parse,
        "schema_valid": schema_valid,
        "runtime_policy_decision": runtime_policy.decision,
        "runtime_outcome": runtime_policy.outcome,
        "bucket_tags": bucket_tags,
        "metric_flags": metric_flags,
        "metric_values": {
            "marked_object_recall_case": marked_recall_case,
            "exact_marked_object_id_accuracy_case": exact_marked_case,
            "action_recall_case": action_recall_case,
            "described_action_precision_case": described_precision_case,
            "ordinal_actor_binding_accuracy_case": ordinal_case,
            "target_resolution_accuracy_case": target_case,
            "chronology_phase_accuracy_case": chronology_case,
            "dangling_target_rate_case": dangling_case,
            "prediction_action_count": len(predicted_actions),
            "prediction_beat_count": predicted_beats,
            "predicted_target_length": len(json.dumps(safe_script, ensure_ascii=False, sort_keys=True)) if json_valid else 0,
        },
        "diagnostics": {
            "parse_error": None if json_valid else "predicted_script_not_json_object",
            "gate_blocker": None,
            "notes": diagnostics_notes,
            "runtime_policy_reason": runtime_policy.reason,
            "runtime_policy_signals": runtime_policy.signals,
        },
        "_counts": {
            "marked_expected": marked_expected,
            "marked_matched": marked_matched,
            "exact_marked_expected": marked_expected,
            "exact_marked_matched": marked_matched,
            "action_expected": action_total,
            "action_matched": action_matched,
            "described_expected": expected_described,
            "described_predicted": predicted_described,
            "described_matched": described_matched,
            "ordinal_expected": ordinal_total,
            "ordinal_matched": ordinal_matched,
            "target_expected": target_total,
            "target_matched": target_matched,
            "required_target_actions": required_targets,
            "invalid_target_actions": invalid_targets,
            "beat_expected_cases": 1 if gold_beats > 0 else 0,
            "beat_pass_cases": 1 if beat_count_pass and gold_beats > 0 else 0,
            "chronology_expected_cases": 1 if chronology_expected_total > 0 else 0,
            "chronology_pass_cases": 1 if chronology_pass and chronology_expected_total > 0 else 0,
        },
    }
    cluster_id = _cluster_id(case_result)
    case_result["failure_cluster"] = {
        "primary_failure_code": _failure_code(case_result),
        "cluster_id": cluster_id,
    }
    case_result["case_strict_success"] = (
        metric_flags["exact_marked_object_id_pass"]
        and metric_flags["ordinal_binding_pass"]
        and metric_flags["target_resolution_pass"]
        and metric_flags["chronology_phase_pass"]
        and runtime_policy.decision == "accept"
    )
    return case_result


def _aggregate(case_results: list[dict[str, Any]]) -> tuple[dict[str, float], dict[str, int]]:
    total_cases = len(case_results)
    supports = {
        "cases": total_cases,
        "policy_cases": 0,
        "marked_refs": 0,
        "actions_expected": 0,
        "ordinal_refs": 0,
        "target_actions": 0,
        "required_target_actions": 0,
        "beat_cases": 0,
        "chronology_cases": 0,
    }
    counters = {
        "json_valid": 0,
        "canonical_parse": 0,
        "schema_valid": 0,
        "marked_matched": 0,
        "exact_marked_matched": 0,
        "action_matched": 0,
        "ordinal_matched": 0,
        "target_matched": 0,
        "invalid_target_actions": 0,
        "chronology_pass": 0,
        "llm_accept": 0,
        "llm_merge": 0,
        "llm_reject": 0,
        "described_expected_total": 0,
        "described_predicted_total": 0,
        "described_matched_total": 0,
        "prediction_action_count_sum": 0.0,
        "prediction_beat_count_sum": 0.0,
        "case_strict_success_count": 0,
    }
    for result in case_results:
        counts = _as_dict(result.get("_counts"))
        supports["marked_refs"] += int(counts.get("marked_expected", 0))
        supports["actions_expected"] += int(counts.get("action_expected", 0))
        supports["ordinal_refs"] += int(counts.get("ordinal_expected", 0))
        supports["target_actions"] += int(counts.get("target_expected", 0))
        supports["required_target_actions"] += int(counts.get("required_target_actions", 0))
        supports["beat_cases"] += int(counts.get("beat_expected_cases", 0))
        supports["chronology_cases"] += int(counts.get("chronology_expected_cases", 0))

        if bool(result.get("json_valid")):
            counters["json_valid"] += 1
        if bool(result.get("canonical_parse")):
            counters["canonical_parse"] += 1
        if bool(result.get("schema_valid")):
            counters["schema_valid"] += 1

        counters["marked_matched"] += int(counts.get("marked_matched", 0))
        counters["exact_marked_matched"] += int(counts.get("exact_marked_matched", 0))
        counters["action_matched"] += int(counts.get("action_matched", 0))
        counters["ordinal_matched"] += int(counts.get("ordinal_matched", 0))
        counters["target_matched"] += int(counts.get("target_matched", 0))
        counters["invalid_target_actions"] += int(counts.get("invalid_target_actions", 0))
        counters["chronology_pass"] += int(counts.get("chronology_pass_cases", 0))
        counters["described_expected_total"] += int(counts.get("described_expected", 0))
        counters["described_predicted_total"] += int(counts.get("described_predicted", 0))
        counters["described_matched_total"] += int(counts.get("described_matched", 0))
        beat_pass_cases = int(counts.get("beat_pass_cases", 0))

        policy = str(result.get("runtime_policy_decision", ""))
        if policy in {"accept", "merge", "reject"}:
            supports["policy_cases"] += 1
            if policy == "accept":
                counters["llm_accept"] += 1
            elif policy == "merge":
                counters["llm_merge"] += 1
            else:
                counters["llm_reject"] += 1

        values = _as_dict(result.get("metric_values"))
        counters["prediction_action_count_sum"] += float(values.get("prediction_action_count", 0.0))
        counters["prediction_beat_count_sum"] += float(values.get("prediction_beat_count", 0.0))
        counters.setdefault("average_target_length_sum", 0.0)
        counters["average_target_length_sum"] += float(values.get("predicted_target_length", 0.0))
        counters.setdefault("beat_pass_case_count", 0)
        counters["beat_pass_case_count"] += beat_pass_cases
        if bool(result.get("case_strict_success", False)):
            counters["case_strict_success_count"] += 1

    def _ratio(numerator: float, denominator: int) -> float:
        if denominator <= 0:
            return 0.0
        return float(numerator) / float(denominator)

    policy_cases = supports["policy_cases"]
    described_predicted_total = int(counters["described_predicted_total"])
    described_expected_total = int(counters["described_expected_total"])
    if described_predicted_total > 0:
        described_action_precision = _ratio(counters["described_matched_total"], described_predicted_total)
    else:
        described_action_precision = 1.0 if described_expected_total == 0 else 0.0
    metrics = {
        "json_valid_rate": _ratio(counters["json_valid"], total_cases),
        "canonical_parse_rate": _ratio(counters["canonical_parse"], total_cases),
        "schema_valid_rate": _ratio(counters["schema_valid"], total_cases),
        "marked_object_recall": _ratio(counters["marked_matched"], supports["marked_refs"]),
        "exact_marked_object_id_accuracy": _ratio(counters["exact_marked_matched"], supports["marked_refs"]),
        "beat_count_accuracy": _ratio(counters.get("beat_pass_case_count", 0), supports["beat_cases"]),
        "action_recall": _ratio(counters["action_matched"], supports["actions_expected"]),
        "described_action_precision": described_action_precision,
        "dangling_target_rate": _ratio(counters["invalid_target_actions"], supports["required_target_actions"]),
        "ordinal_actor_binding_accuracy": _ratio(counters["ordinal_matched"], supports["ordinal_refs"]),
        "target_resolution_accuracy": _ratio(counters["target_matched"], supports["target_actions"]),
        "chronology_phase_accuracy": _ratio(counters["chronology_pass"], supports["chronology_cases"]),
        "llm_accept_rate": _ratio(counters["llm_accept"], policy_cases),
        "llm_merge_rate": _ratio(counters["llm_merge"], policy_cases),
        "llm_reject_rate": _ratio(counters["llm_reject"], policy_cases),
        "runtime_fallback_rate": _ratio(counters["llm_merge"] + counters["llm_reject"], policy_cases),
        "average_target_length": _ratio(counters.get("average_target_length_sum", 0.0), total_cases),
        "prediction_action_count_mean": _ratio(counters["prediction_action_count_sum"], total_cases),
        "prediction_beat_count_mean": _ratio(counters["prediction_beat_count_sum"], total_cases),
        "case_strict_success_rate": _ratio(counters["case_strict_success_count"], total_cases),
    }
    return metrics, supports


def _top_clusters(case_results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counts: dict[str, int] = {}
    for result in case_results:
        cluster = _as_dict(result.get("failure_cluster"))
        cluster_id = str(cluster.get("cluster_id", "")).strip()
        if not cluster_id:
            continue
        counts[cluster_id] = counts.get(cluster_id, 0) + 1
    ordered = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return [{"cluster_id": cluster_id, "count": count} for cluster_id, count in ordered[:3]]


def score_cases(request: ScoreCasesRequest) -> dict[str, Any]:
    case_results: list[dict[str, Any]] = []
    runtime_policy_snapshot = request.runtime_policy_snapshot
    for case in request.cases:
        case_id = str(case["eval_case_id"])
        predicted = request.predicted_by_case.get(case_id)
        case_results.append(
            _case_score(
                case,
                checkpoint_id=request.checkpoint_id,
                predicted_script=predicted,
                runtime_policy_snapshot=runtime_policy_snapshot,
            )
        )

    sets_payload: dict[str, Any] = {}
    for eval_set in EVAL_SETS:
        set_rows = [row for row in case_results if str(row.get("eval_set")) == eval_set]
        metrics, supports = _aggregate(set_rows)
        sets_payload[eval_set] = {
            "case_count": len(set_rows),
            "metrics": metrics,
            "supports": supports,
            "top_failure_clusters": _top_clusters(set_rows),
        }

    overall_metrics, overall_supports = _aggregate(case_results)
    set_metrics = {
        "sets": sets_payload,
        "overall": {
            "case_count": len(case_results),
            "metrics": overall_metrics,
            "supports": overall_supports,
            "top_failure_clusters": _top_clusters(case_results),
        },
    }

    bucket_payload: dict[str, Any] = {}
    for bucket in CRITICAL_BUCKETS:
        bucket_rows = [row for row in case_results if bucket in _as_list(row.get("bucket_tags"))]
        metrics, supports = _aggregate(bucket_rows)
        bucket_payload[bucket] = {
            "case_count": len(bucket_rows),
            "metrics": metrics,
            "supports": supports,
        }

    bucket_metrics = {"buckets": bucket_payload}
    return {
        "case_results": case_results,
        "set_metrics": set_metrics,
        "bucket_metrics": bucket_metrics,
    }
