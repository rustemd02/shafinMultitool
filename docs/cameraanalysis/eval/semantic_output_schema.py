#!/usr/bin/env python3
"""Candidate-output schema and scorer for semantic camera labels."""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any, Dict, Iterable, List, Sequence

from semantic_label_adapter import SEMANTIC_ACTION_TYPES, FUTURE_TECHNICAL_ACTION_TYPES


OUTPUT_MODES = {"live", "pause", "both"}
RUNTIME_CLAIMS = {
    "label_oracle",
    "test_fixture",
    "not_real_runtime",
    "real_runtime_still_replay",
}
CONFIDENCE_BY_TARGET = {
    "high": 0.86,
    "medium": 0.62,
    "low": 0.32,
}
SUPPORTED_PROXY_ACTIONS = set(SEMANTIC_ACTION_TYPES)
COMPOSITION_ONLY_ACTIONS = {
    "shift_frame_left",
    "shift_frame_right",
    "shift_frame_up",
    "shift_frame_down",
    "step_closer",
    "step_back",
    "level_horizon",
}


class SemanticOutputValidationError(ValueError):
    pass


def _safe_div(num: float, den: float, default: float = 1.0) -> float:
    return default if den == 0 else num / den


def _mean(values: Sequence[float]) -> float | None:
    if not values:
        return None
    return round(sum(values) / float(len(values)), 6)


def _target_confidence(target: str) -> float:
    return CONFIDENCE_BY_TARGET.get(target, 0.62)


def _confidence_band_matches(target: str, confidence: float) -> bool:
    if target == "high":
        return confidence >= 0.75
    if target == "medium":
        return 0.45 <= confidence < 0.75
    if target == "low":
        return confidence < 0.45
    return False


def _output_for_case(
    case: Dict[str, Any],
    *,
    shown: bool,
    semantic_actions: Iterable[str],
    future_actions: Iterable[str] = (),
    confidence: float | None = None,
    source: str,
    runtime_claim: str = "not_real_runtime",
    live_tip: str | None = None,
    pause_summary: str | None = None,
) -> Dict[str, Any]:
    return {
        "record_id": case["record_id"],
        "filename": case["filename"],
        "mode": "live",
        "shown": bool(shown),
        "live_tip": live_tip if live_tip is not None else (case["expected_live_text_class"] if shown else None),
        "pause_summary": pause_summary,
        "semantic_actions": list(semantic_actions),
        "future_actions": list(future_actions),
        "confidence": float(_target_confidence(case["confidence_target"]) if confidence is None else confidence),
        "source": source,
        "runtime_claim": runtime_claim,
        "trace_ids": [],
    }


def build_oracle_candidate_outputs(cases: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    outputs: List[Dict[str, Any]] = []
    for case in cases:
        outputs.append(
            _output_for_case(
                case,
                shown=True,
                semantic_actions=case["expected_actions"],
                future_actions=case["future_actions"],
                source="oracle_projection",
                runtime_claim="label_oracle",
                pause_summary=case["expected_pause_summary"],
            )
        )
    return outputs


def build_bad_candidate_outputs(cases: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    outputs: List[Dict[str, Any]] = []
    for case in cases:
        forbidden = list(case["forbidden_actions"])
        action = forbidden[0] if forbidden else "level_horizon"
        outputs.append(
            _output_for_case(
                case,
                shown=True,
                semantic_actions=[action],
                confidence=0.9,
                source="deliberately_bad_candidate",
                runtime_claim="test_fixture",
                live_tip="Механическая подсказка без понимания сцены.",
            )
        )
    return outputs


def build_proxy_current_outputs(cases: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Approximate current deterministic limitations without claiming runtime replay.

    This is useful for prioritization, but it is not a measured app result. It
    encodes the current product boundary: live is deterministic, technical IQA
    actions are not implemented as user-facing semantic actions yet, and several
    pause/object-aware actions are still unsupported.
    """

    outputs: List[Dict[str, Any]] = []
    for case in cases:
        expected = list(case["expected_actions"])
        supported = [action for action in expected if action in SUPPORTED_PROXY_ACTIONS]
        if supported:
            outputs.append(
                _output_for_case(
                    case,
                    shown=True,
                    semantic_actions=[supported[0]],
                    confidence=_target_confidence(case["confidence_target"]),
                    source="manual_proxy_current_limitations",
                    runtime_claim="not_real_runtime",
                    pause_summary=case["expected_pause_summary"] if supported[0] == "keep_current_setup" else None,
                )
            )
        else:
            outputs.append(
                _output_for_case(
                    case,
                    shown=False,
                    semantic_actions=[],
                    confidence=0.2,
                    source="manual_proxy_current_limitations",
                    runtime_claim="not_real_runtime",
                    live_tip=None,
                    pause_summary=None,
                )
            )
    return outputs


def validate_candidate_outputs(cases: Sequence[Dict[str, Any]], outputs: Sequence[Dict[str, Any]]) -> None:
    case_by_id = {case["record_id"]: case for case in cases}
    seen: set[tuple[str, str]] = set()
    modes_by_record: dict[str, set[str]] = defaultdict(set)
    runtime_claims_by_record: dict[str, set[str]] = defaultdict(set)
    errors: List[str] = []

    for index, output in enumerate(outputs):
        record_id = output.get("record_id")
        if not isinstance(record_id, str) or not record_id:
            errors.append(f"output[{index}].record_id must be non-empty string")
            continue
        case = case_by_id.get(record_id)
        if case is None:
            errors.append(f"{record_id}: output has no matching case")
            continue
        mode = output.get("mode")
        if mode not in OUTPUT_MODES:
            errors.append(f"{record_id}: mode must be one of {sorted(OUTPUT_MODES)}")
            mode = "invalid"
        key = (record_id, str(mode))
        if key in seen:
            errors.append(f"{record_id}: duplicate output for mode {mode}")
        seen.add(key)
        modes_by_record[record_id].add(str(mode))
        if output.get("filename") != case["filename"]:
            errors.append(f"{record_id}: filename must match case")
        runtime_claim = output.get("runtime_claim")
        if runtime_claim not in RUNTIME_CLAIMS:
            errors.append(f"{record_id}: runtime_claim must be one of {sorted(RUNTIME_CLAIMS)}")
        else:
            runtime_claims_by_record[record_id].add(str(runtime_claim))
        if not isinstance(output.get("shown"), bool):
            errors.append(f"{record_id}: shown must be bool")
        confidence = output.get("confidence")
        if not isinstance(confidence, (int, float)) or not (0.0 <= float(confidence) <= 1.0):
            errors.append(f"{record_id}: confidence must be in [0, 1]")

        for field, allowed in (
            ("semantic_actions", SEMANTIC_ACTION_TYPES),
            ("future_actions", FUTURE_TECHNICAL_ACTION_TYPES),
        ):
            value = output.get(field, [])
            if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
                errors.append(f"{record_id}: {field} must be list[str]")
                continue
            invalid = sorted(set(value) - set(allowed))
            if invalid:
                errors.append(f"{record_id}: {field} contains invalid actions {invalid}")

    for record_id, modes in sorted(modes_by_record.items()):
        if "both" in modes and len(modes) > 1:
            errors.append(f"{record_id}: mode 'both' cannot be combined with live/pause rows")
    for record_id, claims in sorted(runtime_claims_by_record.items()):
        if len(claims) > 1:
            errors.append(f"{record_id}: live/pause rows must use the same runtime_claim, got {sorted(claims)}")

    missing = sorted(set(case_by_id.keys()) - set(modes_by_record.keys()))
    if missing:
        errors.append(f"missing outputs for cases: {missing[:10]}")

    if errors:
        raise SemanticOutputValidationError("\n".join(errors))


def _map_outputs(cases: Sequence[Dict[str, Any]], outputs: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    grouped: dict[str, list[Dict[str, Any]]] = defaultdict(list)
    for output in outputs:
        grouped[output["record_id"]].append(output)

    return {
        record_id: _merge_record_outputs(rows)
        for record_id, rows in grouped.items()
    }


def _unique_preserving_order(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def _merge_record_outputs(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    if len(rows) == 1:
        return dict(rows[0])

    mode_order = {"live": 0, "pause": 1, "both": 2}
    ordered = sorted(rows, key=lambda item: mode_order.get(item.get("mode"), 99))
    runtime_claims = _unique_preserving_order(
        str(row.get("runtime_claim"))
        for row in ordered
        if row.get("runtime_claim") is not None
    )
    sources = _unique_preserving_order(
        str(row.get("source"))
        for row in ordered
        if row.get("source") is not None
    )
    semantic_actions = _unique_preserving_order(
        action
        for row in ordered
        for action in row.get("semantic_actions", [])
    )
    future_actions = _unique_preserving_order(
        action
        for row in ordered
        for action in row.get("future_actions", [])
    )
    trace_ids = _unique_preserving_order(
        trace_id
        for row in ordered
        for trace_id in row.get("trace_ids", [])
    )

    semantic_confidences = [
        float(row.get("confidence", 0.0))
        for row in ordered
        if bool(row.get("shown")) and bool(row.get("semantic_actions", []))
    ]
    shown_confidences = semantic_confidences or [
        float(row.get("confidence", 0.0))
        for row in ordered
        if bool(row.get("shown"))
    ]
    confidence_pool = shown_confidences or [
        float(row.get("confidence", 0.0))
        for row in ordered
    ]

    return {
        "record_id": ordered[0]["record_id"],
        "filename": ordered[0]["filename"],
        "mode": "both",
        "shown": any(bool(row.get("shown")) for row in ordered),
        "live_tip": next((row.get("live_tip") for row in ordered if row.get("live_tip")), None),
        "pause_summary": next((row.get("pause_summary") for row in ordered if row.get("pause_summary")), None),
        "semantic_actions": semantic_actions,
        "future_actions": future_actions,
        "confidence": max(confidence_pool) if confidence_pool else 0.0,
        "source": "+".join(sources),
        "runtime_claim": runtime_claims[0] if runtime_claims else None,
        "trace_ids": trace_ids,
    }


def _is_technical_future_case(case: Dict[str, Any]) -> bool:
    return bool(case["future_actions"]) and not bool(case["expected_actions"])


def _score_case(case: Dict[str, Any], output: Dict[str, Any]) -> Dict[str, Any]:
    expected = set(case["expected_actions"])
    future_expected = set(case["future_actions"])
    forbidden = set(case["forbidden_actions"])
    semantic_actions = set(output.get("semantic_actions", []))
    future_actions = set(output.get("future_actions", []))
    confidence = float(output.get("confidence", 0.0))

    expected_action_hit = 1.0 if not expected else float(bool(expected & semantic_actions))
    future_action_hit = None if not future_expected else float(bool(future_expected & future_actions))
    forbidden_violation = bool(semantic_actions & forbidden)
    has_correction = bool(semantic_actions - {"keep_current_setup"})
    is_good = case["quality_label"] == "good"
    is_technical_future = _is_technical_future_case(case)
    semantic_overreach = is_technical_future and bool(semantic_actions & COMPOSITION_ONLY_ACTIONS)
    positive_confirmation = (
        None
        if not is_good
        else float(bool(output.get("shown")) and "keep_current_setup" in semantic_actions and not has_correction)
    )
    good_preserved = None if not is_good else float(not forbidden_violation and not has_correction)
    technical_gate = None if not is_technical_future else float(not semantic_overreach)
    confidence_match = float(_confidence_band_matches(case["confidence_target"], confidence))

    failures: List[str] = []
    if expected and not expected_action_hit:
        failures.append("missing_expected_action")
    if future_expected and future_action_hit == 0.0:
        failures.append("missing_future_action")
    if forbidden_violation:
        failures.append("forbidden_action_violation")
    if is_good and good_preserved == 0.0:
        failures.append("good_frame_overcorrection")
    if positive_confirmation == 0.0:
        failures.append("missing_positive_confirmation")
    if semantic_overreach:
        failures.append("semantic_overreach_on_technical_failure")
    if confidence_match == 0.0:
        failures.append("confidence_band_mismatch")

    return {
        "record_id": case["record_id"],
        "filename": case["filename"],
        "quality_label": case["quality_label"],
        "source_bucket": case["source_bucket"],
        "demo_priority": case["demo_priority"],
        "tags": case["tags"],
        "expected_actions": sorted(expected),
        "future_actions": sorted(future_expected),
        "forbidden_actions": sorted(forbidden),
        "candidate_actions": sorted(semantic_actions),
        "candidate_future_actions": sorted(future_actions),
        "candidate_source": output.get("source"),
        "runtime_claim": output.get("runtime_claim"),
        "failures": failures,
        "passed": not failures,
        "metrics": {
            "expected_action_hit": expected_action_hit,
            "future_action_hit": future_action_hit,
            "forbidden_action_violation": float(forbidden_violation),
            "good_frame_preserved": good_preserved,
            "technical_failure_gate": technical_gate,
            "positive_confirmation": positive_confirmation,
            "confidence_band_match": confidence_match,
        },
    }


def _mean_metric(rows: Sequence[Dict[str, Any]], metric: str) -> float | None:
    values = [
        row["metrics"][metric]
        for row in rows
        if row["metrics"].get(metric) is not None
    ]
    return _mean(values)


def _build_set_metrics(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    demo_rows = [row for row in rows if row["demo_priority"]]
    failures = Counter(failure for row in rows for failure in row["failures"])
    return {
        "record_count": len(rows),
        "pass_rate": _mean([float(row["passed"]) for row in rows]),
        "expected_action_hit_rate": _mean_metric(rows, "expected_action_hit"),
        "future_action_hit_rate": _mean_metric(rows, "future_action_hit"),
        "forbidden_action_violation_rate": _mean_metric(rows, "forbidden_action_violation"),
        "good_frame_preservation_rate": _mean_metric(rows, "good_frame_preserved"),
        "technical_failure_gate_rate": _mean_metric(rows, "technical_failure_gate"),
        "positive_confirmation_rate": _mean_metric(rows, "positive_confirmation"),
        "confidence_band_accuracy": _mean_metric(rows, "confidence_band_match"),
        "demo_priority_pass_rate": _mean([float(row["passed"]) for row in demo_rows]),
        "failure_counts": dict(sorted(failures.items())),
    }


def _bucket_metrics_for(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    return {
        "record_count": len(rows),
        "pass_rate": _mean([float(row["passed"]) for row in rows]),
        "expected_action_hit_rate": _mean_metric(rows, "expected_action_hit"),
        "forbidden_action_violation_rate": _mean_metric(rows, "forbidden_action_violation"),
        "good_frame_preservation_rate": _mean_metric(rows, "good_frame_preserved"),
        "technical_failure_gate_rate": _mean_metric(rows, "technical_failure_gate"),
        "positive_confirmation_rate": _mean_metric(rows, "positive_confirmation"),
        "confidence_band_accuracy": _mean_metric(rows, "confidence_band_match"),
        "failure_counts": dict(sorted(Counter(f for row in rows for f in row["failures"]).items())),
    }


def _build_bucket_metrics(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    by_quality: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    by_source: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    by_tag: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_quality[row["quality_label"]].append(row)
        by_source[row["source_bucket"]].append(row)
        for tag in row["tags"]:
            by_tag[tag].append(row)
    return {
        "quality_label": {key: _bucket_metrics_for(value) for key, value in sorted(by_quality.items())},
        "source_bucket": {key: _bucket_metrics_for(value) for key, value in sorted(by_source.items())},
        "eval_tags": {key: _bucket_metrics_for(value) for key, value in sorted(by_tag.items())},
    }


def score_semantic_candidate_outputs(
    cases: Sequence[Dict[str, Any]],
    outputs: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    validate_candidate_outputs(cases, outputs)
    by_id = _map_outputs(cases, outputs)
    case_results = [_score_case(case, by_id[case["record_id"]]) for case in cases]
    return {
        "case_results": case_results,
        "set_metrics": _build_set_metrics(case_results),
        "bucket_metrics": _build_bucket_metrics(case_results),
    }


def render_semantic_eval_summary(candidate_id: str, report: Dict[str, Any]) -> str:
    metrics = report["set_metrics"]
    failure_counts = metrics.get("failure_counts", {})
    lines = [
        "# Semantic Label Eval Summary",
        "",
        f"Candidate: `{candidate_id}`",
        "",
        "## Set Metrics",
        "",
    ]
    for key in (
        "record_count",
        "pass_rate",
        "expected_action_hit_rate",
        "future_action_hit_rate",
        "forbidden_action_violation_rate",
        "good_frame_preservation_rate",
        "technical_failure_gate_rate",
        "positive_confirmation_rate",
        "confidence_band_accuracy",
        "demo_priority_pass_rate",
    ):
        lines.append(f"- `{key}`: {metrics.get(key)}")

    lines.extend(["", "## Failure Counts", ""])
    if failure_counts:
        for key, value in sorted(failure_counts.items()):
            lines.append(f"- `{key}`: {value}")
    else:
        lines.append("- none")

    failed_cases = [row for row in report["case_results"] if not row["passed"]][:20]
    lines.extend(["", "## First Failed Cases", ""])
    if failed_cases:
        for row in failed_cases:
            failures = ", ".join(row["failures"])
            lines.append(f"- `{row['record_id']}` / `{row['filename']}`: {failures}")
    else:
        lines.append("- none")

    return "\n".join(lines) + "\n"
