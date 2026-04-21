from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .io import read_json, read_jsonl, write_json


class Iter3ReleaseGateError(ValueError):
    """Raised when iter3 release gate inputs are malformed."""


TARGETED_PATTERN_GROUPS: dict[str, tuple[str, ...]] = {
    "open_then_pick_up_object": ("open_then_pick_up_object",),
    "ordinal_first_second_third": ("ordinal_first_second_third",),
    "give_to_third_actor": (
        "dialogue_then_pick_up_object_then_give_to_third_actor",
        "first_pick_up_object_then_give_to_third_actor",
        "second_pick_up_object_then_give_to_third_actor",
    ),
}

TARGETED_GROUP_MIN_PASS_RATE = 0.95


@dataclass(frozen=True)
class Iter3ReleaseGateRequest:
    runs_scored_csv: Path
    model_slice_summary_csv: Path
    iter3_manifest_json: Path
    candidate_model_only_case_results_jsonl: Path
    baseline_model_only_case_results_jsonl: Path
    candidate_model_id: str
    output_dir: Path
    baseline_model_id: str = "dataset_v7_orpo_iter2"
    seed: int | None = None
    manual_review_json: Path | None = None


def _read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            return []
        return list(reader)


def _as_float(row: dict[str, Any], key: str) -> float:
    raw = row.get(key)
    if raw in {None, ""}:
        raise Iter3ReleaseGateError(f"missing metric={key!r}")
    return float(raw)


def _load_manual_review(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise Iter3ReleaseGateError("manual_review_json must be an object")
    return payload


def _filter_model_rows(
    rows: list[dict[str, Any]],
    *,
    model_id: str,
    seed: int | None,
    label: str,
) -> list[dict[str, Any]]:
    filtered = [row for row in rows if str(row.get("model_id", "")).strip() == model_id]
    if seed is not None:
        filtered = [row for row in filtered if int(row.get("seed", 0) or 0) == seed]
    if not filtered:
        raise Iter3ReleaseGateError(f"{label} rows not found for model_id={model_id!r} seed={seed!r}")
    return filtered


def _select_single_row(
    rows: list[dict[str, Any]],
    *,
    model_id: str,
    seed: int | None,
    label: str,
) -> dict[str, Any]:
    filtered = _filter_model_rows(rows, model_id=model_id, seed=seed, label=label)
    if len(filtered) != 1:
        raise Iter3ReleaseGateError(
            f"{label} requires exactly one row for model_id={model_id!r} seed={seed!r}, got {len(filtered)}"
        )
    return filtered[0]


def _slice_row(
    rows: list[dict[str, Any]],
    *,
    model_id: str,
    seed: int | None,
    slice_name: str,
) -> dict[str, Any] | None:
    matching = [
        row
        for row in rows
        if str(row.get("model_id", "")).strip() == model_id
        and str(row.get("slice", "")).strip() == slice_name
        and (seed is None or int(row.get("seed", 0) or 0) == seed)
    ]
    if len(matching) > 1:
        raise Iter3ReleaseGateError(
            f"model_slice_summary has duplicate rows for model_id={model_id!r} seed={seed!r} slice={slice_name!r}"
        )
    return matching[0] if matching else None


def _pattern_from_eval_case_id(eval_case_id: str) -> str:
    tail = eval_case_id.split("::", 1)[1] if "::" in eval_case_id else eval_case_id
    for prefix in ("pref-rtf-rejected-", "pref-rtf-accepted-", "pref-rtf-"):
        if tail.startswith(prefix):
            tail = tail[len(prefix) :]
            break
    return tail.split("__", 1)[0]


def _case_flag(case_row: dict[str, Any], name: str) -> bool:
    if name in {"json_valid", "schema_valid", "case_strict_success"}:
        return bool(case_row.get(name, False))
    if name == "runtime_policy_decision":
        return str(case_row.get(name, "")).strip() == "accept"
    metric_flags = case_row.get("metric_flags")
    if not isinstance(metric_flags, dict):
        return False
    return bool(metric_flags.get(name, False))


def _group_case_rows(rows: list[dict[str, Any]], *, patterns: tuple[str, ...]) -> list[dict[str, Any]]:
    return [
        row
        for row in rows
        if _pattern_from_eval_case_id(str(row.get("eval_case_id", ""))) in patterns
    ]


def _pass_rate(rows: list[dict[str, Any]], *flag_names: str) -> float:
    if not rows:
        return 0.0
    passed = 0
    for row in rows:
        if all(_case_flag(row, flag_name) for flag_name in flag_names):
            passed += 1
    return passed / len(rows)


def evaluate_iter3_release_gate(request: Iter3ReleaseGateRequest) -> dict[str, Any]:
    run_rows = _read_csv_rows(request.runs_scored_csv)
    if not run_rows:
        raise Iter3ReleaseGateError(f"runs_scored_csv is empty: {request.runs_scored_csv}")

    candidate = _select_single_row(
        run_rows,
        model_id=request.candidate_model_id,
        seed=request.seed,
        label="candidate runs_scored",
    )
    baseline = _select_single_row(
        run_rows,
        model_id=request.baseline_model_id,
        seed=request.seed,
        label="baseline runs_scored",
    )
    seed_value = int(candidate.get("seed", 0) or 0)
    if request.seed is not None and seed_value != request.seed:
        raise Iter3ReleaseGateError(f"seed mismatch in candidate row: expected {request.seed}, got {seed_value}")

    overall_checks = {
        "overall.json_valid_rate": _as_float(candidate, "overall.json_valid_rate") >= 0.980,
        "overall.exact_marked_object_id_accuracy": _as_float(candidate, "overall.exact_marked_object_id_accuracy") >= 0.99,
        "overall.ordinal_actor_binding_accuracy": _as_float(candidate, "overall.ordinal_actor_binding_accuracy") >= 0.97,
        "overall.target_resolution_accuracy": _as_float(candidate, "overall.target_resolution_accuracy")
        > max(0.1162, _as_float(baseline, "overall.target_resolution_accuracy")),
        "overall.chronology_phase_accuracy": _as_float(candidate, "overall.chronology_phase_accuracy")
        > max(0.0840, _as_float(baseline, "overall.chronology_phase_accuracy")),
        "overall.case_strict_success_rate": _as_float(candidate, "overall.case_strict_success_rate")
        > max(0.0382, _as_float(baseline, "overall.case_strict_success_rate")),
        "overall.runtime_fallback_rate": _as_float(candidate, "overall.runtime_fallback_rate")
        < min(0.9466, _as_float(baseline, "overall.runtime_fallback_rate")),
        "bucket.three_beat_cases.target_resolution_accuracy": _as_float(
            candidate, "bucket.three_beat_cases.target_resolution_accuracy"
        )
        > 0.2625,
        "bucket.three_beat_cases.chronology_phase_accuracy": _as_float(
            candidate, "bucket.three_beat_cases.chronology_phase_accuracy"
        )
        > 0.25,
    }

    slice_rows = _read_csv_rows(request.model_slice_summary_csv)
    slice_checks: dict[str, bool] = {}
    slice_blockers: list[str] = []
    candidate_model_only = None
    candidate_end_to_end = None
    baseline_end_to_end = None
    if not slice_rows:
        slice_blockers.append("missing_model_slice_summary")
    else:
        candidate_model_only = _slice_row(
            slice_rows,
            model_id=request.candidate_model_id,
            seed=seed_value,
            slice_name="model_only",
        )
        candidate_end_to_end = _slice_row(
            slice_rows,
            model_id=request.candidate_model_id,
            seed=seed_value,
            slice_name="end_to_end",
        )
        baseline_end_to_end = _slice_row(
            slice_rows,
            model_id=request.baseline_model_id,
            seed=seed_value,
            slice_name="end_to_end",
        )
        missing_slices = [
            label
            for label, row in (
                ("candidate_model_only", candidate_model_only),
                ("candidate_end_to_end", candidate_end_to_end),
                ("baseline_end_to_end", baseline_end_to_end),
            )
            if row is None
        ]
        if missing_slices:
            slice_blockers.append("missing_dual_slice_rows:" + ",".join(missing_slices))
        else:
            slice_checks = {
                "slice.model_only.json_valid_rate": _as_float(candidate_model_only, "json_valid_rate") >= 0.980,
                "slice.model_only.exact_marked_object_id_accuracy": _as_float(
                    candidate_model_only, "exact_marked_object_id_accuracy"
                )
                >= 0.99,
                "slice.model_only.ordinal_actor_binding_accuracy": _as_float(
                    candidate_model_only, "ordinal_actor_binding_accuracy"
                )
                >= 0.97,
                "slice.end_to_end.parse_non_regression_vs_model_only": _as_float(
                    candidate_end_to_end, "json_valid_rate"
                )
                >= _as_float(candidate_model_only, "json_valid_rate")
                and _as_float(candidate_end_to_end, "schema_valid_rate")
                >= _as_float(candidate_model_only, "schema_valid_rate"),
                "slice.end_to_end.target_resolution_accuracy": _as_float(
                    candidate_end_to_end, "target_resolution_accuracy"
                )
                > _as_float(baseline_end_to_end, "target_resolution_accuracy"),
                "slice.end_to_end.chronology_phase_accuracy": _as_float(
                    candidate_end_to_end, "chronology_phase_accuracy"
                )
                > _as_float(baseline_end_to_end, "chronology_phase_accuracy"),
                "slice.end_to_end.action_recall": _as_float(candidate_end_to_end, "action_recall")
                > _as_float(baseline_end_to_end, "action_recall"),
                "slice.end_to_end.case_strict_success_rate": _as_float(
                    candidate_end_to_end, "case_strict_success_rate"
                )
                > _as_float(baseline_end_to_end, "case_strict_success_rate"),
                "slice.end_to_end.runtime_fallback_rate": _as_float(
                    candidate_end_to_end, "runtime_fallback_rate"
                )
                < _as_float(baseline_end_to_end, "runtime_fallback_rate"),
            }

    manifest = read_json(request.iter3_manifest_json)
    manifest_checks = {
        "manifest.requires_dual_slice": bool(
            manifest.get("prediction_source_policy", {}).get("requires_dual_slice", False)
        ),
        "manifest.selection_slice_model_only": str(
            manifest.get("prediction_source_policy", {}).get("selection_slice", "")
        )
        == "model_only_predicted_script",
        "manifest.gold_chosen_share_overall": float(manifest.get("gold_chosen_share_overall", 1.0) or 1.0) <= 0.55,
        "manifest.model_chosen_share_overall": float(manifest.get("model_chosen_share_overall", 0.0) or 0.0) >= 0.25,
        "manifest.exact_marker_identity_floor_present": int(
            manifest.get("configured_family_floors", {}).get("exact_marker_identity", 0) or 0
        )
        >= 4,
        "manifest.exact_marker_identity_floor_satisfied": int(
            manifest.get("preference_family_counts", {}).get("exact_marker_identity", 0) or 0
        )
        >= int(manifest.get("configured_family_floors", {}).get("exact_marker_identity", 0) or 0),
    }
    delta_family_counts = manifest.get("delta_family_counts", {})
    delta_total = int(manifest.get("counts", {}).get("delta_sft_total", 0) or 0)
    delta_max_family_share_raw = manifest.get("delta_sft_max_family_share")
    delta_max_family_share = None
    try:
        if delta_max_family_share_raw is not None:
            delta_max_family_share = float(delta_max_family_share_raw)
    except (TypeError, ValueError):
        delta_max_family_share = None
    manifest_checks["manifest.delta_sft_max_family_share_present"] = (
        delta_max_family_share is not None and 0 < delta_max_family_share <= 1
    )
    manifest_checks["manifest.delta_family_counts_present"] = isinstance(delta_family_counts, dict)
    if delta_total > 0 and delta_max_family_share is not None and 0 < delta_max_family_share <= 1 and isinstance(delta_family_counts, dict):
        delta_max_allowed = max(1, int(delta_total * delta_max_family_share))
        for family in sorted(TARGETED_PATTERN_GROUPS.keys() | {"exact_marker_identity", "three_beat"}):
            family_key = {
                "open_then_pick_up_object": "open_then_pick_up",
                "ordinal_first_second_third": "ordinal",
                "give_to_third_actor": "give_to_third_actor",
            }.get(family, family)
            manifest_checks[f"manifest.delta_family_cap.{family_key}"] = int(delta_family_counts.get(family_key, 0) or 0) <= delta_max_allowed
    gold_share_by_family = manifest.get("gold_chosen_share_by_family", {})
    model_count_by_family = manifest.get("model_chosen_count_by_family", {})
    for family in sorted({"open_then_pick_up", "ordinal", "give_to_third_actor", "three_beat", "exact_marker_identity"}):
        manifest_checks[f"manifest.gold_share_by_family.{family}"] = float(gold_share_by_family.get(family, 1.0) or 1.0) <= 0.60
        if int(manifest.get("selection_family_counts", {}).get(family, 0) or 0) >= 4:
            manifest_checks[f"manifest.model_count_by_family.{family}"] = int(model_count_by_family.get(family, 0) or 0) >= 2
    manifest_checks["manifest.raw_vs_end_to_end_divergence_counts_present"] = isinstance(
        manifest.get("raw_vs_end_to_end_divergence_counts"), dict
    )

    candidate_case_rows = read_jsonl(request.candidate_model_only_case_results_jsonl)
    baseline_case_rows = read_jsonl(request.baseline_model_only_case_results_jsonl)
    targeted_pattern_checks: dict[str, bool] = {}
    targeted_pattern_rates: dict[str, Any] = {}
    for group_name, patterns in TARGETED_PATTERN_GROUPS.items():
        candidate_group = _group_case_rows(candidate_case_rows, patterns=patterns)
        baseline_group = _group_case_rows(baseline_case_rows, patterns=patterns)
        if not candidate_group or not baseline_group:
            targeted_pattern_checks[f"pattern_group.{group_name}.coverage_present"] = False
            targeted_pattern_rates[group_name] = {
                "candidate_rows": len(candidate_group),
                "baseline_rows": len(baseline_group),
            }
            continue
        if group_name == "open_then_pick_up_object":
            candidate_rate = _pass_rate(candidate_group, "beat_count_pass", "chronology_phase_pass")
            baseline_rate = _pass_rate(baseline_group, "beat_count_pass", "chronology_phase_pass")
        elif group_name == "ordinal_first_second_third":
            candidate_rate = _pass_rate(candidate_group, "ordinal_binding_pass", "target_resolution_pass")
            baseline_rate = _pass_rate(baseline_group, "ordinal_binding_pass", "target_resolution_pass")
        else:
            candidate_rate = _pass_rate(candidate_group, "action_recall_pass", "chronology_phase_pass")
            baseline_rate = _pass_rate(baseline_group, "action_recall_pass", "chronology_phase_pass")
        targeted_pattern_rates[group_name] = {
            "candidate_pass_rate": candidate_rate,
            "baseline_pass_rate": baseline_rate,
            "candidate_rows": len(candidate_group),
            "baseline_rows": len(baseline_group),
        }
        targeted_pattern_checks[f"pattern_group.{group_name}.pass_rate"] = (
            candidate_rate >= TARGETED_GROUP_MIN_PASS_RATE and candidate_rate >= baseline_rate
        )

    manual_review = _load_manual_review(request.manual_review_json)
    manual_review_checks = {
        "open_then_pick_up_object": bool(manual_review.get("open_then_pick_up_object", False)),
        "ordinal_first_second_third": bool(manual_review.get("ordinal_first_second_third", False)),
        "dialogue_then_pick_up_object_then_give_to_third_actor": bool(
            manual_review.get("dialogue_then_pick_up_object_then_give_to_third_actor", False)
        ),
    }

    numeric_pass = all(overall_checks.values())
    slice_pass = not slice_blockers and all(slice_checks.values())
    manifest_pass = all(manifest_checks.values())
    targeted_pass = all(targeted_pattern_checks.values())
    manual_pass = all(manual_review_checks.values()) if request.manual_review_json is not None else False
    if numeric_pass and slice_pass and manifest_pass and targeted_pass and manual_pass:
        gate_status = "pass"
    elif numeric_pass and slice_pass and manifest_pass and targeted_pass:
        gate_status = "pending_manual_review"
    else:
        gate_status = "fail"

    payload = {
        "candidate_model_id": request.candidate_model_id,
        "baseline_model_id": request.baseline_model_id,
        "seed": seed_value,
        "gate_status": gate_status,
        "overall_checks": overall_checks,
        "slice_checks": slice_checks,
        "slice_blockers": slice_blockers,
        "manifest_checks": manifest_checks,
        "targeted_pattern_slice": "model_only",
        "targeted_pattern_checks": targeted_pattern_checks,
        "targeted_pattern_rates": targeted_pattern_rates,
        "manual_review_checks": manual_review_checks,
        "numeric_pass": numeric_pass,
        "slice_pass": slice_pass,
        "manifest_pass": manifest_pass,
        "targeted_pattern_pass": targeted_pass,
        "manual_review_pass": manual_pass,
    }
    write_json(payload, request.output_dir / "iter3_release_gate.json")
    return payload
