#!/usr/bin/env python3
"""Deterministic metric scorer for Camera Analysis eval harness."""

from __future__ import annotations

from collections import defaultdict
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple


ALL_METRICS: Tuple[str, ...] = (
    "verdict_accuracy",
    "issue_precision",
    "issue_recall",
    "issue_f1",
    "strength_precision",
    "strength_recall",
    "strength_f1",
    "no_false_problem_rate",
    "fallback_policy_accuracy",
    "primary_action_match_rate",
    "fix_type_coverage_rate",
    "issue_to_action_link_rate",
    "guardrail_compliance_rate",
    "good_frame_confirmation_rate",
    "trace_issue_coverage_rate",
    "trace_action_coverage_rate",
    "three_stage_chain_rate",
    "evidence_key_validity_rate",
    "summary_consistency_rate",
    "unsupported_claim_rate",
    "explanation_faithfulness_score",
    "hint_visibility_policy_accuracy",
    "hint_jitter_rate",
    "frames_to_stable_correct_hint",
)


def _pick(mapping: Dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in mapping:
            return mapping[key]
    return default


def _safe_div(num: float, den: float, default: float = 1.0) -> float:
    return default if den == 0 else num / den


def _f1(precision: float, recall: float) -> float:
    return _safe_div(2.0 * precision * recall, precision + recall, default=0.0)


def _metric_mean(values: Sequence[float]) -> Optional[float]:
    if not values:
        return None
    return sum(values) / float(len(values))


def _round_metric(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    return round(float(value), 6)


def _normalize_issue_records(output: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], Set[str], Dict[str, str]]:
    critique = _pick(output, "critique_report", "critiqueReport", default={}) or {}
    raw_issues = _pick(critique, "issues", default=[]) or []
    issue_types: Set[str] = set()
    id_to_type: Dict[str, str] = {}
    normalized: List[Dict[str, Any]] = []
    for issue in raw_issues:
        if not isinstance(issue, dict):
            continue
        issue_type = _pick(issue, "type", "issueType", default=None)
        if not isinstance(issue_type, str) or not issue_type:
            continue
        issue_id = _pick(issue, "id", default=f"issue:{issue_type}")
        issue_types.add(issue_type)
        id_to_type[str(issue_id)] = issue_type
        normalized.append(issue)
    return normalized, issue_types, id_to_type


def _normalize_strength_types(output: Dict[str, Any]) -> Set[str]:
    critique = _pick(output, "critique_report", "critiqueReport", default={}) or {}
    raw_strengths = _pick(critique, "strengths", default=[]) or []
    out: Set[str] = set()
    for strength in raw_strengths:
        if isinstance(strength, dict):
            strength_type = _pick(strength, "type", "strengthType", default=None)
            if isinstance(strength_type, str) and strength_type:
                out.add(strength_type)
    return out


def _primary_action_info(output: Dict[str, Any]) -> Tuple[Optional[str], Optional[str], List[str], int]:
    plan = _pick(output, "recommendation_plan", "recommendationPlan", default={}) or {}
    primary = _pick(plan, "primaryAction", "primary_action", default=None)
    secondary = _pick(plan, "secondaryActions", "secondary_actions", default=[]) or []
    if not isinstance(primary, dict):
        return None, None, [], len(secondary) if isinstance(secondary, list) else 0
    action_type = _pick(primary, "actionType", "action_type", default=None)
    action_id = _pick(primary, "id", default=None)
    linked = _pick(primary, "linkedIssueIds", "linked_issue_ids", default=[]) or []
    return (
        str(action_type) if isinstance(action_type, str) else None,
        str(action_id) if isinstance(action_id, str) else None,
        [str(item) for item in linked if isinstance(item, str)],
        len(secondary) if isinstance(secondary, list) else 0,
    )


def _fallback_used(output: Dict[str, Any]) -> bool:
    critique = _pick(output, "critique_report", "critiqueReport", default={}) or {}
    return bool(_pick(critique, "fallbackUsed", "fallback_used", default=False))


def _verdict(output: Dict[str, Any]) -> Optional[str]:
    critique = _pick(output, "critique_report", "critiqueReport", default={}) or {}
    verdict = _pick(critique, "verdict", default=None)
    return str(verdict) if isinstance(verdict, str) else None


def _summary(output: Dict[str, Any]) -> Dict[str, Any]:
    critique = _pick(output, "critique_report", "critiqueReport", default={}) or {}
    return _pick(critique, "summary", default={}) or {}


def _trace_items(output: Dict[str, Any]) -> List[Dict[str, Any]]:
    trace = _pick(output, "explainability_trace", "explainabilityTrace", default={}) or {}
    items = _pick(trace, "items", default=[]) or []
    return [item for item in items if isinstance(item, dict)]


def _live_hint_state(output: Dict[str, Any]) -> Tuple[Optional[str], Optional[str]]:
    live_hint = _pick(output, "live_hint_projection", "liveHintProjection", default={}) or {}
    state = _pick(live_hint, "hintState", "hint_state", default=None)
    action = _pick(live_hint, "primaryAction", "primary_action", default=None)
    return (
        str(state) if isinstance(state, str) else None,
        str(action) if isinstance(action, str) else None,
    )


def _is_evidence_key_valid(key: str) -> bool:
    allowed_prefixes = (
        "snapshot.",
        "scene_semantics.",
        "sceneSemantics.",
        "rule.",
        "planner.",
        "plan.",
        "critique.",
    )
    return any(key.startswith(prefix) for prefix in allowed_prefixes)


def _score_detection(gold: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Optional[float]]:
    metrics: Dict[str, Optional[float]] = {}
    normalized_issues, issue_types, _ = _normalize_issue_records(output)
    strength_types = _normalize_strength_types(output)
    verdict = _verdict(output)

    required_issues = set(_pick(gold, "required_issues", default=[]) or [])
    forbidden_issues = set(_pick(gold, "forbidden_issues", default=[]) or [])
    required_strengths = set(_pick(gold, "required_strengths", default=[]) or [])
    forbidden_strengths = set(_pick(gold, "forbidden_strengths", default=[]) or [])
    expected_verdict = _pick(gold, "verdict", default=None)

    metrics["verdict_accuracy"] = 1.0 if verdict == expected_verdict else 0.0

    issue_tp = float(len(issue_types & required_issues))
    issue_fn = float(len(required_issues - issue_types))
    issue_fp = float(len(issue_types & forbidden_issues))
    issue_precision = _safe_div(issue_tp, issue_tp + issue_fp, default=1.0)
    issue_recall = _safe_div(issue_tp, issue_tp + issue_fn, default=1.0)
    metrics["issue_precision"] = issue_precision
    metrics["issue_recall"] = issue_recall
    metrics["issue_f1"] = _f1(issue_precision, issue_recall)

    strength_tp = float(len(strength_types & required_strengths))
    strength_fn = float(len(required_strengths - strength_types))
    strength_fp = float(len(strength_types & forbidden_strengths))
    strength_precision = _safe_div(strength_tp, strength_tp + strength_fp, default=1.0)
    strength_recall = _safe_div(strength_tp, strength_tp + strength_fn, default=1.0)
    metrics["strength_precision"] = strength_precision
    metrics["strength_recall"] = strength_recall
    metrics["strength_f1"] = _f1(strength_precision, strength_recall)

    good_policy = _pick(gold, "good_frame_policy", default="")
    if good_policy == "must_confirm_good_frame" or expected_verdict == "good":
        critical_issue = any(float(_pick(issue, "severity", default=0.0)) >= 0.65 for issue in normalized_issues)
        has_forbidden = len(issue_types & forbidden_issues) > 0
        metrics["no_false_problem_rate"] = 0.0 if (critical_issue or has_forbidden) else 1.0
    else:
        metrics["no_false_problem_rate"] = None

    expected_fallback = bool(_pick(gold, "fallback_expected", default=False))
    metrics["fallback_policy_accuracy"] = 1.0 if _fallback_used(output) == expected_fallback else 0.0
    return metrics


def _score_actions(gold: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Optional[float]]:
    metrics: Dict[str, Optional[float]] = {}
    issues, issue_types, id_to_type = _normalize_issue_records(output)
    action_type, _, linked_issue_ids, secondary_count = _primary_action_info(output)
    plan = _pick(output, "recommendation_plan", "recommendationPlan", default={}) or {}
    allowed_actions = set(_pick(gold, "allowed_primary_actions", default=[]) or [])
    required_fix_types = set(_pick(gold, "required_fix_types", default=[]) or [])
    required_issues = set(_pick(gold, "required_issues", default=[]) or [])
    verdict_target = _pick(gold, "verdict", default=None)
    good_policy = _pick(gold, "good_frame_policy", default="")

    if allowed_actions:
        metrics["primary_action_match_rate"] = 1.0 if action_type in allowed_actions else 0.0
    else:
        metrics["primary_action_match_rate"] = 1.0 if action_type is None else 0.0

    if required_fix_types:
        predicted_fix_types: Set[str] = set()
        for issue in issues:
            for fix_type in _pick(issue, "suggestedFixTypes", "suggested_fix_types", default=[]) or []:
                if isinstance(fix_type, str):
                    predicted_fix_types.add(fix_type)
        metrics["fix_type_coverage_rate"] = 1.0 if required_fix_types.issubset(predicted_fix_types) else 0.0
    else:
        metrics["fix_type_coverage_rate"] = None

    if required_issues:
        linked_types = {id_to_type.get(issue_id) for issue_id in linked_issue_ids if issue_id in id_to_type}
        linked_types.discard(None)
        metrics["issue_to_action_link_rate"] = 1.0 if bool(linked_types & required_issues) else 0.0
    else:
        metrics["issue_to_action_link_rate"] = 1.0 if action_type in {None, "leave_frame_as_is"} else 0.0

    guardrail_ok = True
    mode = _pick(plan, "mode", default="pause")
    if mode == "live" and secondary_count > 0:
        guardrail_ok = False
    if action_type not in {None, "leave_frame_as_is"} and not linked_issue_ids:
        guardrail_ok = False
    if verdict_target == "good" and action_type not in {None, "leave_frame_as_is"}:
        guardrail_ok = False
    metrics["guardrail_compliance_rate"] = 1.0 if guardrail_ok else 0.0

    if good_policy == "must_confirm_good_frame":
        no_change = _pick(plan, "noChangeRationale", "no_change_rationale", default=None)
        confirmed = action_type == "leave_frame_as_is" or (action_type is None and isinstance(no_change, str) and bool(no_change.strip()))
        metrics["good_frame_confirmation_rate"] = 1.0 if confirmed else 0.0
    else:
        metrics["good_frame_confirmation_rate"] = None

    return metrics


def _score_explainability(gold: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Optional[float]]:
    metrics: Dict[str, Optional[float]] = {}
    explainability = _pick(gold, "explainability", default={}) or {}
    required_issue_links = set(_pick(explainability, "required_issue_links", default=[]) or [])
    must_have_chain = bool(
        _pick(explainability, "require_observation_interpretation_recommendation_chain", default=False)
    )
    summary_tokens = [str(token).lower() for token in (_pick(explainability, "summary_must_reference_any", default=[]) or [])]

    issue_records, _, id_to_type = _normalize_issue_records(output)
    issue_type_to_ids: Dict[str, Set[str]] = defaultdict(set)
    for issue_id, issue_type in id_to_type.items():
        issue_type_to_ids[issue_type].add(issue_id)

    action_type, action_id, _, _ = _primary_action_info(output)
    trace_items = _trace_items(output)
    by_id = {str(_pick(item, "id", default="")): item for item in trace_items if _pick(item, "id", default="")}

    interpretation_items = [item for item in trace_items if _pick(item, "stage", default=None) == "interpretation"]
    recommendation_items = [item for item in trace_items if _pick(item, "stage", default=None) == "recommendation"]

    covered_required = 0
    for required_issue_type in required_issue_links:
        required_ids = issue_type_to_ids.get(required_issue_type, set())
        matched = False
        for item in interpretation_items:
            links = _pick(item, "links", default=[]) or []
            for link in links:
                if not isinstance(link, dict):
                    continue
                if _pick(link, "kind", default=None) != "issue":
                    continue
                ref_id = _pick(link, "refId", "ref_id", default=None)
                if not isinstance(ref_id, str):
                    continue
                if ref_id == required_issue_type or ref_id in required_ids:
                    matched = True
                    break
            if matched:
                break
        covered_required += 1 if matched else 0
    metrics["trace_issue_coverage_rate"] = _safe_div(
        float(covered_required),
        float(len(required_issue_links)),
        default=1.0,
    )

    if action_type is None:
        metrics["trace_action_coverage_rate"] = 1.0
    else:
        matched_action = False
        for item in recommendation_items:
            for link in _pick(item, "links", default=[]) or []:
                if not isinstance(link, dict):
                    continue
                if _pick(link, "kind", default=None) != "action":
                    continue
                ref_id = _pick(link, "refId", "ref_id", default=None)
                if ref_id in {action_id, action_type}:
                    matched_action = True
                    break
            if matched_action:
                break
        metrics["trace_action_coverage_rate"] = 1.0 if matched_action else 0.0

    if must_have_chain:
        has_chain = False
        for recommendation in recommendation_items:
            deps = _pick(recommendation, "dependsOn", "depends_on", default=[]) or []
            for dep_id in deps:
                interpretation = by_id.get(str(dep_id))
                if not isinstance(interpretation, dict) or _pick(interpretation, "stage", default=None) != "interpretation":
                    continue
                interpretation_deps = _pick(interpretation, "dependsOn", "depends_on", default=[]) or []
                if any(
                    isinstance(by_id.get(str(obs_id)), dict)
                    and _pick(by_id[str(obs_id)], "stage", default=None) == "observation"
                    for obs_id in interpretation_deps
                ):
                    has_chain = True
                    break
            if has_chain:
                break
        metrics["three_stage_chain_rate"] = 1.0 if has_chain else 0.0
    else:
        metrics["three_stage_chain_rate"] = 1.0

    evidence_keys: List[str] = []
    for item in trace_items:
        for key in _pick(item, "evidenceKeys", "evidence_keys", default=[]) or []:
            if isinstance(key, str):
                evidence_keys.append(key)
    for issue in issue_records:
        for evidence in _pick(issue, "evidence", default=[]) or []:
            if isinstance(evidence, dict):
                key = _pick(evidence, "key", default=None)
                if isinstance(key, str):
                    evidence_keys.append(key)
    valid_count = sum(1 for key in evidence_keys if _is_evidence_key_valid(key))
    metrics["evidence_key_validity_rate"] = _safe_div(float(valid_count), float(len(evidence_keys)), default=1.0)

    summary = _summary(output)
    summary_text = " ".join(
        [
            str(_pick(summary, "shortVerdict", "short_verdict", default="") or ""),
            str(_pick(summary, "whyGood", "why_good", default="") or ""),
            str(_pick(summary, "whyProblematic", "why_problematic", default="") or ""),
        ]
    ).lower()
    verdict = _verdict(output)
    consistent = True
    if verdict == "good" and _pick(summary, "whyProblematic", "why_problematic", default=None):
        consistent = False
    if verdict == "needs_fix" and not _pick(summary, "whyProblematic", "why_problematic", default=None):
        consistent = False
    if summary_tokens and not any(token in summary_text for token in summary_tokens):
        consistent = False
    metrics["summary_consistency_rate"] = 1.0 if consistent else 0.0

    unsupported = _pick(output, "unsupported_claims", "unsupportedClaims", default=0)
    if isinstance(unsupported, (int, float)):
        metrics["unsupported_claim_rate"] = 1.0 if float(unsupported) > 0 else 0.0
    elif isinstance(unsupported, bool):
        metrics["unsupported_claim_rate"] = 1.0 if unsupported else 0.0
    else:
        metrics["unsupported_claim_rate"] = 0.0

    metrics["explanation_faithfulness_score"] = (
        0.25 * (metrics["trace_issue_coverage_rate"] or 0.0)
        + 0.20 * (metrics["trace_action_coverage_rate"] or 0.0)
        + 0.25 * (metrics["three_stage_chain_rate"] or 0.0)
        + 0.15 * (metrics["evidence_key_validity_rate"] or 0.0)
        + 0.15 * (metrics["summary_consistency_rate"] or 0.0)
    )
    return metrics


def _score_live_single_frame(gold: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Optional[float]]:
    expected_hint_state = _pick(gold, "expected_hint_state", default=None)
    if not isinstance(expected_hint_state, str):
        return {
            "hint_visibility_policy_accuracy": None,
            "hint_jitter_rate": None,
            "frames_to_stable_correct_hint": None,
        }
    predicted_hint_state, _ = _live_hint_state(output)
    return {
        "hint_visibility_policy_accuracy": 1.0 if predicted_hint_state == expected_hint_state else 0.0,
        "hint_jitter_rate": None,
        "frames_to_stable_correct_hint": None,
    }


def _score_live_sequence(case: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Optional[float]]:
    frames = sorted(case.get("sequence", []), key=lambda item: item.get("frameOrdinal", 0))
    frame_outputs = _pick(output, "frame_outputs", "sequence_outputs", default=[]) or []
    frame_output_by_ordinal: Dict[int, Dict[str, Any]] = {
        int(_pick(item, "frameOrdinal", "frame_ordinal", default=-1)): item
        for item in frame_outputs
        if isinstance(item, dict)
    }

    visibility_hits = 0
    visibility_total = 0
    action_by_ordinal: Dict[int, Optional[str]] = {}
    for frame in frames:
        ordinal = int(_pick(frame, "frameOrdinal", "frame_ordinal", default=0))
        expected_state = _pick(frame, "expectedHintState", "expected_hint_state", default=None)
        predicted = frame_output_by_ordinal.get(ordinal, {})
        predicted_state = _pick(predicted, "hintState", "hint_state", default=None)
        predicted_action = _pick(predicted, "primaryAction", "primary_action", default=None)
        if isinstance(expected_state, str):
            visibility_total += 1
            visibility_hits += 1 if predicted_state == expected_state else 0
        action_by_ordinal[ordinal] = str(predicted_action) if isinstance(predicted_action, str) else None

    hint_visibility_accuracy = _safe_div(float(visibility_hits), float(visibility_total), default=0.0)

    jitter_changes = 0
    for prev, cur in zip(frames, frames[1:]):
        prev_exempt = bool(_pick(prev, "jitterExempt", "jitter_exempt", default=False))
        cur_exempt = bool(_pick(cur, "jitterExempt", "jitter_exempt", default=False))
        if prev_exempt or cur_exempt:
            continue
        prev_ord = int(_pick(prev, "frameOrdinal", "frame_ordinal", default=0))
        cur_ord = int(_pick(cur, "frameOrdinal", "frame_ordinal", default=0))
        if action_by_ordinal.get(prev_ord) != action_by_ordinal.get(cur_ord):
            jitter_changes += 1
    jitter_rate = _safe_div(float(jitter_changes), float(len(frames)), default=0.0) if frames else None

    sequence_meta = case.get("sequenceMeta", {})
    anchor = _pick(sequence_meta, "stabilityAnchorFrame", "stability_anchor_frame", default=None)
    stable_action = _pick(sequence_meta, "stablePrimaryAction", "stable_primary_action", default=None)
    max_frames = _pick(sequence_meta, "maxFramesToStable", "max_frames_to_stable", default=None)
    frames_to_stable: Optional[float]
    if isinstance(anchor, int) and isinstance(stable_action, str):
        found: Optional[int] = None
        for frame in frames:
            ordinal = int(_pick(frame, "frameOrdinal", "frame_ordinal", default=0))
            if ordinal < anchor:
                continue
            if not bool(_pick(frame, "countsTowardStability", "counts_toward_stability", default=False)):
                continue
            if _pick(frame, "expectedHintState", "expected_hint_state", default=None) != "visible_action":
                continue
            if action_by_ordinal.get(ordinal) == stable_action:
                found = ordinal
                break
        if found is None:
            if isinstance(max_frames, int):
                frames_to_stable = float(max_frames + 1)
            else:
                frames_to_stable = None
        else:
            frames_to_stable = float(max(0, found - anchor))
    else:
        frames_to_stable = None

    return {
        "hint_visibility_policy_accuracy": hint_visibility_accuracy,
        "hint_jitter_rate": jitter_rate,
        "frames_to_stable_correct_hint": frames_to_stable,
    }


def score_case(case: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Any]:
    case_kind = case.get("case_kind")
    metrics: Dict[str, Optional[float]] = {name: None for name in ALL_METRICS}

    if case_kind == "live_sequence":
        sequence_metrics = _score_live_sequence(case, output)
        metrics.update(sequence_metrics)
        return {
            "eval_case_id": case["eval_case_id"],
            "eval_set": case.get("eval_set"),
            "case_kind": case_kind,
            "bucket_tags": sorted(case.get("bucket_tags", [])),
            "metrics": {k: _round_metric(v) for k, v in metrics.items()},
        }

    gold = case.get("gold_expectations", {})
    metrics.update(_score_detection(gold, output))
    metrics.update(_score_actions(gold, output))
    metrics.update(_score_explainability(gold, output))

    if case_kind == "single_frame_live":
        metrics.update(_score_live_single_frame(gold, output))

    return {
        "eval_case_id": case["eval_case_id"],
        "eval_set": case.get("eval_set"),
        "case_kind": case_kind,
        "bucket_tags": sorted(case.get("bucket_tags", [])),
        "metrics": {k: _round_metric(v) for k, v in metrics.items()},
    }


def _aggregate_case_metrics(case_results: Sequence[Dict[str, Any]]) -> Dict[str, Optional[float]]:
    grouped: Dict[str, List[float]] = {name: [] for name in ALL_METRICS}
    for result in case_results:
        metrics = result.get("metrics", {})
        for name in ALL_METRICS:
            value = metrics.get(name)
            if isinstance(value, (int, float)):
                grouped[name].append(float(value))

    aggregated: Dict[str, Optional[float]] = {}
    for name, values in grouped.items():
        aggregated[name] = _round_metric(_metric_mean(values))
    return aggregated


def _aggregate_bucket_metrics(case_results: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Optional[float]]]:
    by_bucket: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for result in case_results:
        for bucket in result.get("bucket_tags", []):
            by_bucket[str(bucket)].append(result)

    bucket_metrics: Dict[str, Dict[str, Optional[float]]] = {}
    for bucket in sorted(by_bucket.keys()):
        bucket_metrics[bucket] = _aggregate_case_metrics(by_bucket[bucket])
    return bucket_metrics


def score_model(cases: Sequence[Dict[str, Any]], outputs_by_case_id: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
    case_results: List[Dict[str, Any]] = []
    for case in sorted(cases, key=lambda item: item["eval_case_id"]):
        output = outputs_by_case_id.get(case["eval_case_id"], {})
        case_results.append(score_case(case, output))
    return {
        "case_results": case_results,
        "set_metrics": _aggregate_case_metrics(case_results),
        "bucket_metrics": _aggregate_bucket_metrics(case_results),
    }


def validate_sequence_contract(cases: Sequence[Dict[str, Any]]) -> None:
    for case in cases:
        if case.get("case_kind") != "live_sequence":
            continue
        sequence_meta = case.get("sequenceMeta")
        if not isinstance(sequence_meta, dict):
            raise ValueError(
                f"live_sequence case {case['eval_case_id']} is missing sequenceMeta "
                "(contract-invalid per Sequence Case Extension)"
            )
        for key in ("stabilityAnchorFrame", "stablePrimaryAction", "maxFramesToStable"):
            if key not in sequence_meta:
                raise ValueError(
                    f"live_sequence case {case['eval_case_id']} missing sequenceMeta.{key} "
                    "(contract-invalid per Sequence Case Extension)"
                )
        for frame in case.get("sequence", []):
            if "jitterExempt" not in frame or "countsTowardStability" not in frame:
                ordinal = frame.get("frameOrdinal")
                raise ValueError(
                    f"live_sequence case {case['eval_case_id']} frame {ordinal} missing "
                    "jitterExempt/countsTowardStability (contract-invalid per Sequence Case Extension)"
                )
