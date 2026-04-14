from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .io import read_json, read_jsonl, write_json, write_jsonl


class CompareError(ValueError):
    """Raised when A/B compare inputs are malformed."""


@dataclass(frozen=True)
class CompareReportsRequest:
    candidate_report_dir: Path
    baseline_report_dir: Path
    output_dir: Path


def _decision_rank(value: str) -> int:
    normalized = str(value).strip().lower()
    if normalized == "accept":
        return 2
    if normalized == "merge":
        return 1
    return 0


def _winner(candidate: dict[str, Any], baseline: dict[str, Any]) -> str:
    candidate_flags = candidate.get("metric_flags", {})
    baseline_flags = baseline.get("metric_flags", {})
    if not isinstance(candidate_flags, dict):
        candidate_flags = {}
    if not isinstance(baseline_flags, dict):
        baseline_flags = {}

    candidate_key = (
        int(bool(candidate.get("json_valid", False))),
        int(bool(candidate_flags.get("exact_marked_object_id_pass", False))),
        int(bool(candidate_flags.get("ordinal_binding_pass", False))),
        int(bool(candidate_flags.get("target_resolution_pass", False))),
        int(bool(candidate_flags.get("chronology_phase_pass", False))),
        _decision_rank(str(candidate.get("runtime_policy_decision", ""))),
    )
    baseline_key = (
        int(bool(baseline.get("json_valid", False))),
        int(bool(baseline_flags.get("exact_marked_object_id_pass", False))),
        int(bool(baseline_flags.get("ordinal_binding_pass", False))),
        int(bool(baseline_flags.get("target_resolution_pass", False))),
        int(bool(baseline_flags.get("chronology_phase_pass", False))),
        _decision_rank(str(baseline.get("runtime_policy_decision", ""))),
    )
    if candidate_key > baseline_key:
        return "candidate"
    if candidate_key < baseline_key:
        return "baseline"
    return "tie"


def _metrics(payload: dict[str, Any], set_name: str) -> dict[str, Any]:
    if set_name == "overall":
        container = payload.get("overall", {})
    else:
        sets = payload.get("sets", {})
        if not isinstance(sets, dict):
            raise CompareError("set_metrics.sets must be object")
        container = sets.get(set_name, {})
    if not isinstance(container, dict):
        raise CompareError(f"set_metrics.{set_name} must be object")
    metrics = container.get("metrics", {})
    if not isinstance(metrics, dict):
        raise CompareError(f"set_metrics.{set_name}.metrics must be object")
    return metrics


def _load_report_dir(report_dir: Path) -> dict[str, Any]:
    return {
        "set_metrics": read_json(report_dir / "set_metrics.json"),
        "bucket_metrics": read_json(report_dir / "bucket_metrics.json"),
        "case_results": read_jsonl(report_dir / "case_results.jsonl"),
    }


def _delta(candidate: float, baseline: float) -> float:
    return (candidate - baseline) * 100.0


def compare_reports(request: CompareReportsRequest) -> dict[str, Any]:
    candidate = _load_report_dir(request.candidate_report_dir)
    baseline = _load_report_dir(request.baseline_report_dir)

    baseline_by_case = {
        str(row.get("eval_case_id", "")): row
        for row in baseline["case_results"]
        if str(row.get("eval_case_id", "")).strip()
    }
    paired_rows: list[dict[str, Any]] = []
    wins_candidate = 0
    wins_baseline = 0
    ties = 0
    wins_by_set: dict[str, dict[str, int]] = {}

    for candidate_row in candidate["case_results"]:
        case_id = str(candidate_row.get("eval_case_id", "")).strip()
        if not case_id:
            continue
        baseline_row = baseline_by_case.get(case_id)
        if baseline_row is None:
            continue
        eval_set = str(candidate_row.get("eval_set", "unknown"))
        bucket = wins_by_set.setdefault(eval_set, {"candidate": 0, "baseline": 0, "tie": 0})
        winner = _winner(candidate_row, baseline_row)
        if winner == "candidate":
            wins_candidate += 1
            bucket["candidate"] += 1
        elif winner == "baseline":
            wins_baseline += 1
            bucket["baseline"] += 1
        else:
            ties += 1
            bucket["tie"] += 1
        paired_rows.append(
            {
                "eval_case_id": case_id,
                "eval_set": eval_set,
                "winner": winner,
                "candidate_runtime_policy_decision": candidate_row.get("runtime_policy_decision"),
                "baseline_runtime_policy_decision": baseline_row.get("runtime_policy_decision"),
            }
        )

    candidate_overall = _metrics(candidate["set_metrics"], "overall")
    baseline_overall = _metrics(baseline["set_metrics"], "overall")
    critical_metric_deltas = {
        metric_name: _delta(float(candidate_overall.get(metric_name, 0.0)), float(baseline_overall.get(metric_name, 0.0)))
        for metric_name in [
            "json_valid_rate",
            "exact_marked_object_id_accuracy",
            "ordinal_actor_binding_accuracy",
            "target_resolution_accuracy",
            "chronology_phase_accuracy",
            "runtime_fallback_rate",
        ]
    }

    candidate_buckets = candidate["bucket_metrics"].get("buckets", {})
    baseline_buckets = baseline["bucket_metrics"].get("buckets", {})
    if not isinstance(candidate_buckets, dict) or not isinstance(baseline_buckets, dict):
        raise CompareError("bucket_metrics.buckets must be object")
    critical_bucket_deltas: dict[str, dict[str, float]] = {}
    for bucket_name in sorted(set(candidate_buckets.keys()).intersection(baseline_buckets.keys())):
        candidate_metrics = candidate_buckets.get(bucket_name, {}).get("metrics", {})
        baseline_metrics = baseline_buckets.get(bucket_name, {}).get("metrics", {})
        if not isinstance(candidate_metrics, dict) or not isinstance(baseline_metrics, dict):
            continue
        critical_bucket_deltas[bucket_name] = {
            metric_name: _delta(float(candidate_metrics.get(metric_name, 0.0)), float(baseline_metrics.get(metric_name, 0.0)))
            for metric_name in (
                "exact_marked_object_id_accuracy",
                "ordinal_actor_binding_accuracy",
                "target_resolution_accuracy",
                "chronology_phase_accuracy",
                "runtime_fallback_rate",
            )
        }

    hard_wins = wins_by_set.get("hard_heldout", {"candidate": 0, "baseline": 0, "tie": 0})
    runtime_wins = wins_by_set.get("real_runtime", {"candidate": 0, "baseline": 0, "tie": 0})

    summary = {
        "wins_candidate": wins_candidate,
        "wins_baseline": wins_baseline,
        "ties": ties,
        "wins_by_set": wins_by_set,
        "critical_metric_deltas_pp": critical_metric_deltas,
        "critical_bucket_deltas_pp": critical_bucket_deltas,
        "promotion_check": {
            "candidate_not_losing_real_runtime": runtime_wins["candidate"] >= runtime_wins["baseline"],
            "candidate_non_negative_hard_net_wins": hard_wins["candidate"] >= hard_wins["baseline"],
        },
    }

    request.output_dir.mkdir(parents=True, exist_ok=True)
    write_json(summary, request.output_dir / "ab_summary.json")
    write_jsonl(paired_rows, request.output_dir / "paired_case_results.jsonl")
    report_lines = [
        "# A/B report",
        "",
        f"- wins_candidate: {wins_candidate}",
        f"- wins_baseline: {wins_baseline}",
        f"- ties: {ties}",
        "",
        "## Promotion checks",
        f"- candidate_not_losing_real_runtime: {summary['promotion_check']['candidate_not_losing_real_runtime']}",
        f"- candidate_non_negative_hard_net_wins: {summary['promotion_check']['candidate_non_negative_hard_net_wins']}",
    ]
    (request.output_dir / "ab_report.md").write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    return summary
