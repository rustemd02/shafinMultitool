from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
from typing import Any

from .config import TrainingPhaseConfig, default_phase_config
from .io import read_jsonl, write_json


class CheckpointCompareError(ValueError):
    """Raised when checkpoint compare inputs violate Track 8 expectations."""


@dataclass(frozen=True)
class CheckpointCompareRequest:
    phase: str
    checkpoints_jsonl: Path
    output_dir: Path
    seed: int
    reference_checkpoint_id: str | None = None
    phase_config: TrainingPhaseConfig | None = None


CORE_METRICS = [
    "json_valid_rate",
    "marked_object_recall",
    "exact_marked_object_id_accuracy",
    "beat_count_accuracy",
    "action_recall",
    "described_action_precision",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "llm_accept_rate",
]

STABILITY_PROXY_METRICS = [
    "average_target_length",
]

LOWER_IS_BETTER_METRICS = [
    "llm_merge_rate",
    "llm_reject_rate",
    "dangling_target_rate",
    "runtime_fallback_rate",
]

CRITICAL_BUCKETS = [
    "ordinal_cases",
    "marked_object_morphology",
    "same_type_markers",
    "unsupported_action_cases",
    "three_beat_cases",
    "exact_marker_identity_cases",
    "reviewed_merge_cases",
]

PHASES_REQUIRING_EXPLICIT_REFERENCE = {
    "phase3_hard_consolidation",
    "phase4_preference",
}

MAX_ALLOWED_LENGTH_DROP_RATIO = 0.05


def _metric(payload: dict[str, Any], name: str) -> float:
    metrics = payload.get("metrics", {})
    if not isinstance(metrics, dict) or name not in metrics:
        raise CheckpointCompareError(f"checkpoint={payload.get('checkpoint_id')} missing metric={name}")
    return float(metrics[name])


def _bucket_metric(payload: dict[str, Any], name: str) -> float:
    bucket = payload.get("bucket_metrics", {})
    if not isinstance(bucket, dict) or name not in bucket:
        raise CheckpointCompareError(f"checkpoint={payload.get('checkpoint_id')} missing bucket_metric={name}")
    return float(bucket[name])


def _pp_delta(current: float, reference: float) -> float:
    # Interpret [0,1] metrics as fractions, otherwise treat as percentage-space.
    scale = 100.0 if max(abs(current), abs(reference)) <= 1.5 else 1.0
    return (current - reference) * scale


def _checkpoint_hash(payload: dict[str, Any]) -> str:
    checkpoint_id = str(payload.get("checkpoint_id", ""))
    global_step = int(payload.get("global_step", 0) or 0)
    digest = hashlib.sha256(f"{checkpoint_id}|{global_step}".encode("utf-8")).hexdigest()
    return digest[:12]


def _validate_inputs(rows: list[dict[str, Any]], *, phase: str) -> None:
    if not rows:
        raise CheckpointCompareError("checkpoints_jsonl is empty")
    seen: set[str] = set()
    for row in rows:
        checkpoint_id = str(row.get("checkpoint_id", "")).strip()
        if not checkpoint_id:
            raise CheckpointCompareError("checkpoint row missing checkpoint_id")
        if checkpoint_id in seen:
            raise CheckpointCompareError(f"duplicate checkpoint_id={checkpoint_id!r}")
        seen.add(checkpoint_id)
        if "global_step" not in row:
            raise CheckpointCompareError(f"checkpoint={checkpoint_id!r} missing global_step")
        for metric_name in CORE_METRICS + LOWER_IS_BETTER_METRICS + STABILITY_PROXY_METRICS:
            _metric(row, metric_name)
        for bucket_name in CRITICAL_BUCKETS:
            _bucket_metric(row, bucket_name)
        if phase == "phase4_preference":
            pref = row.get("preference_metrics", {})
            if not isinstance(pref, dict):
                raise CheckpointCompareError(f"checkpoint={checkpoint_id!r} missing preference_metrics")
            for name in ("preference_pair_win_rate_val", "preference_pair_win_rate_test", "preference_tie_rate_val", "preference_tie_rate_test"):
                if name not in pref:
                    raise CheckpointCompareError(f"checkpoint={checkpoint_id!r} missing preference metric={name}")


def _non_regression(current: float, reference: float, *, lower_is_better: bool) -> bool:
    if lower_is_better:
        return current <= reference + 1e-12
    return current >= reference - 1e-12


def _length_drop_ratio(current: float, reference: float) -> float:
    if reference <= 1e-12:
        return 0.0 if current >= reference else 1.0
    return max(0.0, (reference - current) / reference)


def _length_growth_ratio(current: float, reference: float) -> float:
    if reference <= 1e-12:
        return 0.0 if current <= reference + 1e-12 else 1.0
    return (current - reference) / reference


def _eligible(current: dict[str, Any], reference: dict[str, Any]) -> tuple[bool, list[str]]:
    violations: list[str] = []
    if bool(current.get("contract_drift", False)):
        violations.append("contract_drift")

    for name in CORE_METRICS:
        if not _non_regression(_metric(current, name), _metric(reference, name), lower_is_better=False):
            violations.append(f"regression:{name}")
    for name in LOWER_IS_BETTER_METRICS:
        if not _non_regression(_metric(current, name), _metric(reference, name), lower_is_better=True):
            violations.append(f"regression:{name}")
    for name in CRITICAL_BUCKETS:
        if not _non_regression(_bucket_metric(current, name), _bucket_metric(reference, name), lower_is_better=False):
            violations.append(f"bucket_regression:{name}")
    if _length_drop_ratio(
        _metric(current, "average_target_length"),
        _metric(reference, "average_target_length"),
    ) > MAX_ALLOWED_LENGTH_DROP_RATIO:
        violations.append("length_collapse:average_target_length")
    return len(violations) == 0, violations


def _positive_sign(current: dict[str, Any], reference: dict[str, Any], *, threshold_pp: float) -> bool:
    ok, _ = _eligible(current, reference)
    if not ok:
        return False
    if _metric(current, "runtime_fallback_rate") > _metric(reference, "runtime_fallback_rate") + 1e-12:
        return False
    for bucket in CRITICAL_BUCKETS:
        if _pp_delta(_bucket_metric(current, bucket), _bucket_metric(reference, bucket)) >= threshold_pp:
            return True
    return False


def _write_promotion_decision(path: Path, *, phase: str, winner_id: str | None, rows: list[dict[str, Any]]) -> None:
    lines = [
        f"# {phase} promotion decision",
        "",
        f"winner: `{winner_id or 'none'}`",
        "",
        "checkpoint statuses:",
    ]
    for row in rows:
        status = row["status"]
        reasons = ", ".join(row["reasons"]) if row["reasons"] else "none"
        lines.append(f"- `{row['checkpoint_id']}`: `{status}` (reasons: {reasons})")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_checkpoint_compare_markdown(
    path: Path,
    *,
    phase: str,
    reference_id: str,
    winner_id: str | None,
    scored: list[dict[str, Any]],
    rows: list[dict[str, Any]],
) -> None:
    row_by_checkpoint = {str(row["checkpoint_id"]): row for row in rows}
    lines = [
        "# checkpoint compare",
        "",
        f"phase: `{phase}`",
        f"reference_checkpoint_id: `{reference_id}`",
        f"winner_checkpoint_id: `{winner_id or 'none'}`",
        "",
        "| checkpoint_id | global_step | status | eligible | positive_sign | independent_pass | consecutive_positive_passes | length_growth_ratio | max_bucket_improvement_pp | reasons |",
        "| --- | ---: | --- | --- | --- | --- | ---: | ---: | ---: | --- |",
    ]

    for item in sorted(scored, key=lambda payload: (payload["global_step"], payload["row_order"])):
        checkpoint_id = str(item["checkpoint_id"])
        row = row_by_checkpoint.get(checkpoint_id, {})
        reasons = ", ".join(row.get("reasons", [])) if row.get("reasons") else "none"
        reasons = reasons.replace("|", "/")
        lines.append(
            "| `{checkpoint_id}` | {global_step} | `{status}` | `{eligible}` | `{positive_sign}` | `{independent_pass}` | {consecutive_positive_passes} | {length_growth:.4f} | {max_bucket:.3f} | {reasons} |".format(
                checkpoint_id=checkpoint_id,
                global_step=int(item["global_step"]),
                status=row.get("status", "unknown"),
                eligible=str(bool(item.get("eligible", False))).lower(),
                positive_sign=str(bool(item.get("positive_sign", False))).lower(),
                independent_pass=str(bool(item.get("independent_pass", False))).lower(),
                consecutive_positive_passes=int(item.get("consecutive_positive_passes", 0)),
                length_growth=float(item.get("length_growth_ratio", 0.0)),
                max_bucket=max(item.get("critical_bucket_improvement_pp", {}).values(), default=0.0),
                reasons=reasons,
            )
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _winner_sort_key(item: dict[str, Any], *, include_preference_gain: bool) -> tuple[float, ...]:
    base = (
        max(item["critical_bucket_improvement_pp"].values()),
        -float(item["runtime_fallback_rate"]),
        -float(item["dangling_target_rate"]),
        -max(float(item.get("length_growth_ratio", 0.0)), 0.0),
    )
    if not include_preference_gain:
        return base
    gains = item.get("preference_pair_win_rate_gain_pp", {})
    min_gain = min(gains.values()) if isinstance(gains, dict) and gains else float("-inf")
    return (float(min_gain),) + base


def compare_checkpoints(request: CheckpointCompareRequest) -> dict[str, Any]:
    config = request.phase_config or default_phase_config(request.phase)
    rows = read_jsonl(request.checkpoints_jsonl)
    _validate_inputs(rows, phase=config.phase)
    by_id = {str(row["checkpoint_id"]): row for row in rows}
    reference_id = request.reference_checkpoint_id
    if reference_id is None:
        if config.phase in PHASES_REQUIRING_EXPLICIT_REFERENCE:
            raise CheckpointCompareError(
                f"{config.phase} requires explicit reference_checkpoint_id bound to prior phase winner"
            )
        # Default deterministic baseline: smallest global_step.
        reference_id = str(min(rows, key=lambda item: int(item.get("global_step", 0)))["checkpoint_id"])
    if reference_id not in by_id:
        raise CheckpointCompareError(f"reference_checkpoint_id={reference_id!r} not present in checkpoints_jsonl")

    reference = by_id[reference_id]
    reference_target_length = _metric(reference, "average_target_length")
    scored: list[dict[str, Any]] = []
    for row_order, row in sorted(enumerate(rows), key=lambda item: (int(item[1].get("global_step", 0)), item[0])):
        checkpoint_id = str(row["checkpoint_id"])
        eligible, violations = _eligible(row, reference)
        improvements = {
            bucket: _pp_delta(_bucket_metric(row, bucket), _bucket_metric(reference, bucket))
            for bucket in CRITICAL_BUCKETS
        }
        scored.append(
            {
                "checkpoint_id": checkpoint_id,
                "global_step": int(row.get("global_step", 0)),
                "row_order": row_order,
                "checkpoint_hash": _checkpoint_hash(row),
                "eligible": eligible,
                "violations": violations,
                "critical_bucket_improvement_pp": improvements,
                "runtime_fallback_rate": _metric(row, "runtime_fallback_rate"),
                "dangling_target_rate": _metric(row, "dangling_target_rate"),
                "length_growth_ratio": _length_growth_ratio(
                    _metric(row, "average_target_length"),
                    reference_target_length,
                ),
                "raw": row,
            }
        )

    winner_id: str | None = None
    statuses: list[dict[str, Any]] = []
    if config.phase == "phase3_hard_consolidation":
        threshold = float(config.phase3_positive_bucket_improvement_pp or 0.3)
        interval = int(config.phase3_eval_interval_steps or 1000)
        seen_steps: set[int] = set()
        previous_event: dict[str, Any] | None = None
        consecutive_positive_passes = 0
        for item in scored:
            step = int(item["global_step"])
            if step in seen_steps:
                item["duplicate_global_step_event"] = True
                item["counted_as_compare_pass"] = False
                item["independent_pass"] = False
                item["positive_sign"] = False
                item["consecutive_positive_passes"] = 0
                continue
            seen_steps.add(step)
            item["duplicate_global_step_event"] = False
            item["counted_as_compare_pass"] = item["checkpoint_id"] != reference_id
            item["positive_sign"] = _positive_sign(item["raw"], reference, threshold_pp=threshold)
            independent_pass = False
            if previous_event is None:
                independent_pass = True
            else:
                independent_pass = (
                    item["checkpoint_id"] != previous_event["checkpoint_id"]
                    and (step - int(previous_event["global_step"])) >= interval
                )
            item["independent_pass"] = bool(item["counted_as_compare_pass"] and independent_pass)
            if item["independent_pass"] and item["positive_sign"]:
                consecutive_positive_passes += 1
            else:
                consecutive_positive_passes = 0
            item["consecutive_positive_passes"] = consecutive_positive_passes
            previous_event = item

        candidate_ids: set[str] = set()
        for item in scored:
            if item.get("consecutive_positive_passes", 0) >= 2:
                candidate_ids.add(str(item["checkpoint_id"]))

        candidates = [item for item in scored if item["checkpoint_id"] in candidate_ids and item["eligible"]]
        if candidates:
            winner = max(
                candidates,
                key=lambda item: _winner_sort_key(item, include_preference_gain=False),
            )
            winner_id = winner["checkpoint_id"]
        for item in scored:
            reasons = list(item["violations"])
            if item.get("duplicate_global_step_event", False):
                reasons.append("duplicate_global_step_event_not_counted")
            if item["checkpoint_id"] == reference_id:
                reasons.append("reference_baseline")
            if item.get("counted_as_compare_pass", False):
                if not item.get("independent_pass", False):
                    reasons.append("non_independent_compare_pass")
                if not item.get("positive_sign", False):
                    reasons.append("no_positive_sign")
                if item["checkpoint_id"] not in candidate_ids:
                    reasons.append("missing_independent_two_pass_sequence")
            status = "winner" if item["checkpoint_id"] == winner_id else ("eligible" if item["eligible"] else "rejected")
            statuses.append({"checkpoint_id": item["checkpoint_id"], "status": status, "reasons": sorted(set(reasons))})
    else:
        required_gain_pp = float(config.phase4_min_preference_win_rate_gain_pp or 3.0)
        baseline_pref = reference.get("preference_metrics", {})
        if config.phase == "phase4_preference":
            for item in scored:
                pref = item["raw"].get("preference_metrics", {})
                gains = {
                    "val": _pp_delta(
                        float(pref.get("preference_pair_win_rate_val", 0.0)),
                        float(baseline_pref.get("preference_pair_win_rate_val", 0.0)),
                    ),
                    "test": _pp_delta(
                        float(pref.get("preference_pair_win_rate_test", 0.0)),
                        float(baseline_pref.get("preference_pair_win_rate_test", 0.0)),
                    ),
                }
                item["preference_pair_win_rate_gain_pp"] = gains
                item["meets_preference_gain"] = min(gains.values()) >= required_gain_pp
            candidates = [
                item
                for item in scored
                if item["eligible"] and bool(item.get("meets_preference_gain", False))
            ]
        else:
            candidates = [item for item in scored if item["eligible"]]
        if candidates:
            winner = max(
                candidates,
                key=lambda item: _winner_sort_key(
                    item,
                    include_preference_gain=(config.phase == "phase4_preference"),
                ),
            )
            winner_id = winner["checkpoint_id"]
        for item in scored:
            reasons = list(item["violations"])
            if config.phase == "phase4_preference" and not bool(item.get("meets_preference_gain", False)):
                reasons.append("insufficient_preference_pair_win_rate_gain_pp")
            if item["checkpoint_id"] == winner_id:
                status = "winner"
            elif config.phase == "phase4_preference":
                status = (
                    "eligible"
                    if item["eligible"] and bool(item.get("meets_preference_gain", False))
                    else "rejected"
                )
            else:
                status = "eligible" if item["eligible"] else "rejected"
            statuses.append({"checkpoint_id": item["checkpoint_id"], "status": status, "reasons": sorted(set(reasons))})

    request.output_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_table = {
        "phase": config.phase,
        "reference_checkpoint_id": reference_id,
        "winner_checkpoint_id": winner_id,
        "rows": statuses,
    }
    write_json(checkpoint_table, request.output_dir / "checkpoint_table.json")
    bucket_deltas = {
        "phase": config.phase,
        "reference_checkpoint_id": reference_id,
        "critical_bucket_improvement_pp_by_checkpoint": {
            item["checkpoint_id"]: item["critical_bucket_improvement_pp"] for item in scored
        },
    }
    write_json(bucket_deltas, request.output_dir / "bucket_deltas.json")
    _write_checkpoint_compare_markdown(
        request.output_dir / "checkpoint_compare.md",
        phase=config.phase,
        reference_id=reference_id,
        winner_id=winner_id,
        scored=scored,
        rows=statuses,
    )
    _write_promotion_decision(
        request.output_dir / "promotion_decision.md",
        phase=config.phase,
        winner_id=winner_id,
        rows=statuses,
    )

    if config.phase == "phase4_preference":
        baseline = by_id[reference_id].get("preference_metrics", {})
        winner_pref = by_id[winner_id].get("preference_metrics", {}) if winner_id else None
        val_delta = (
            _pp_delta(
                float((winner_pref or {}).get("preference_pair_win_rate_val", 0.0)),
                float(baseline.get("preference_pair_win_rate_val", 0.0)),
            )
            if winner_pref is not None
            else None
        )
        test_delta = (
            _pp_delta(
                float((winner_pref or {}).get("preference_pair_win_rate_test", 0.0)),
                float(baseline.get("preference_pair_win_rate_test", 0.0)),
            )
            if winner_pref is not None
            else None
        )
        required_gain_pp = float(config.phase4_min_preference_win_rate_gain_pp or 3.0)
        preference_eval = {
            "phase": config.phase,
            "baseline_at_entry_checkpoint_id": reference_id,
            "winner_checkpoint_id": winner_id,
            "preference_pair_win_rate_val": (winner_pref or {}).get("preference_pair_win_rate_val"),
            "preference_pair_win_rate_test": (winner_pref or {}).get("preference_pair_win_rate_test"),
            "preference_tie_rate_val": (winner_pref or {}).get("preference_tie_rate_val"),
            "preference_tie_rate_test": (winner_pref or {}).get("preference_tie_rate_test"),
            "delta_vs_baseline_pp": {
                "val": val_delta,
                "test": test_delta,
            },
            "required_win_rate_gain_pp": required_gain_pp,
            "winner_meets_required_win_rate_gain": (
                bool(winner_id) and val_delta is not None and test_delta is not None and min(val_delta, test_delta) >= required_gain_pp
            ),
        }
        write_json(preference_eval, request.output_dir / "preference_eval.json")

    return {
        "phase": config.phase,
        "reference_checkpoint_id": reference_id,
        "winner_checkpoint_id": winner_id,
        "rows": statuses,
    }
