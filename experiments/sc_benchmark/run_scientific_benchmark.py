#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import shlex
import statistics
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DOCS_ROOT = Path(__file__).resolve().parents[2] / "docs" / "SGv7pipeline"
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from eval.scorer import ScoreCasesRequest, score_cases


PRIMARY_SET_METRICS = [
    "json_valid_rate",
    "exact_marked_object_id_accuracy",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "runtime_fallback_rate",
    "case_strict_success_rate",
]

PRIMARY_BUCKETS = [
    "same_type_markers",
    "three_beat_cases",
    "ordinal_cases",
    "exact_marker_identity_cases",
    "marked_object_morphology",
]

SET_NAMES = ["overall", "synthetic_heldout", "hard_heldout", "real_runtime"]
SLICE_METRICS = [
    "json_valid_rate",
    "schema_valid_rate",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "action_recall",
    "runtime_fallback_rate",
    "case_strict_success_rate",
]


class BenchmarkConfigError(ValueError):
    pass


@dataclass(frozen=True)
class ModelRunSpec:
    model_id: str
    model_name: str
    seed: int
    checkpoint_id: str
    predictions_jsonl: Path
    report_dir: Path


@dataclass(frozen=True)
class PairSpec:
    candidate_model_id: str
    baseline_model_id: str
    seed: int
    compare_dir: Path


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise BenchmarkConfigError(f"JSON object expected in {path}")
    return payload


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if not raw:
                continue
            payload = json.loads(raw)
            if isinstance(payload, dict):
                rows.append(payload)
    return rows


def _fmt(value: Any, mapping: dict[str, Any]) -> str:
    if isinstance(value, str):
        return value.format_map(mapping)
    return str(value)


def _safe_key(model_id: str) -> str:
    return "".join(ch if ch.isalnum() or ch in ("_", "-") else "_" for ch in model_id)


def _as_list(value: Any, *, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise BenchmarkConfigError(f"{label} must be a list")
    return value


def _as_dict(value: Any, *, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise BenchmarkConfigError(f"{label} must be an object")
    return value


def _validate_pairs(pairs: list[Any], known_models: set[str]) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for idx, item in enumerate(pairs, start=1):
        if not isinstance(item, list) or len(item) != 2:
            raise BenchmarkConfigError(f"pairs[{idx}] must be [candidate_model_id, baseline_model_id]")
        candidate = str(item[0]).strip()
        baseline = str(item[1]).strip()
        if not candidate or not baseline:
            raise BenchmarkConfigError(f"pairs[{idx}] has empty model id")
        if candidate not in known_models:
            raise BenchmarkConfigError(f"pairs[{idx}] unknown candidate model_id={candidate!r}")
        if baseline not in known_models:
            raise BenchmarkConfigError(f"pairs[{idx}] unknown baseline model_id={baseline!r}")
        if candidate == baseline:
            raise BenchmarkConfigError(f"pairs[{idx}] candidate and baseline must differ")
        result.append((candidate, baseline))
    return result


def _resolve_predictions_path(model_cfg: dict[str, Any], *, seed: int, mapping: dict[str, Any]) -> Path | None:
    by_seed = model_cfg.get("predictions_by_seed")
    if isinstance(by_seed, dict):
        raw = by_seed.get(str(seed))
        if raw is not None:
            return Path(_fmt(raw, mapping)).expanduser()

    template = model_cfg.get("predictions_path_template")
    if isinstance(template, str):
        return Path(_fmt(template, mapping)).expanduser()

    single = model_cfg.get("predictions_path")
    if isinstance(single, str):
        return Path(_fmt(single, mapping)).expanduser()

    return None


def _run(cmd: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    completed = subprocess.run(cmd, cwd=str(cwd) if cwd else None, env=env, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed ({completed.returncode}): {' '.join(shlex.quote(x) for x in cmd)}")


def _run_shell(cmd: str, *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    completed = subprocess.run(cmd, cwd=str(cwd) if cwd else None, env=env, shell=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Shell command failed ({completed.returncode}): {cmd}")


def _mean_std(values: list[float]) -> tuple[float, float]:
    if not values:
        return 0.0, 0.0
    if len(values) == 1:
        return values[0], 0.0
    return statistics.mean(values), statistics.stdev(values)


def _binom_cdf(k: int, n: int, p: float) -> float:
    total = 0.0
    for i in range(k + 1):
        total += math.comb(n, i) * (p ** i) * ((1.0 - p) ** (n - i))
    return total


def _sign_test_pvalue_plus_minus(plus: int, minus: int) -> float:
    n = plus + minus
    if n == 0:
        return 1.0
    k = min(plus, minus)
    # two-sided exact sign test, p=0.5
    return min(1.0, 2.0 * _binom_cdf(k, n, 0.5))


def _collect_score_metrics(report_dir: Path) -> dict[str, Any]:
    set_metrics = _read_json(report_dir / "set_metrics.json")
    release_gate = _read_json(report_dir / "release_gate_summary.json")

    sets = set_metrics.get("sets", {})
    if not isinstance(sets, dict):
        sets = {}
    overall = set_metrics.get("overall", {})
    if not isinstance(overall, dict):
        overall = {}

    out: dict[str, Any] = {
        "gate_status": str(release_gate.get("gate_status", "")),
        "gate_blockers": ",".join(release_gate.get("blocking_reasons", []))
        if isinstance(release_gate.get("blocking_reasons"), list)
        else "",
    }

    for set_name in SET_NAMES:
        container = overall if set_name == "overall" else sets.get(set_name, {})
        if not isinstance(container, dict):
            container = {}
        metrics = container.get("metrics", {})
        if not isinstance(metrics, dict):
            metrics = {}
        for metric_name in PRIMARY_SET_METRICS:
            out[f"{set_name}.{metric_name}"] = float(metrics.get(metric_name, 0.0))

    bucket_metrics = _read_json(report_dir / "bucket_metrics.json").get("buckets", {})
    if not isinstance(bucket_metrics, dict):
        bucket_metrics = {}
    for bucket_name in PRIMARY_BUCKETS:
        payload = bucket_metrics.get(bucket_name, {})
        if not isinstance(payload, dict):
            payload = {}
        out[f"bucket.{bucket_name}.case_count"] = int(payload.get("case_count", 0) or 0)
        metrics = payload.get("metrics", {})
        if not isinstance(metrics, dict):
            metrics = {}
        for metric_name in PRIMARY_SET_METRICS:
            out[f"bucket.{bucket_name}.{metric_name}"] = float(metrics.get(metric_name, 0.0))
    return out


def _collect_compare_metrics(compare_dir: Path) -> dict[str, Any]:
    ab_summary = _read_json(compare_dir / "ab_summary.json")
    paired = compare_dir / "paired_case_results.jsonl"
    wins_by_set = ab_summary.get("wins_by_set", {})
    if not isinstance(wins_by_set, dict):
        wins_by_set = {}

    plus = int(ab_summary.get("wins_candidate", 0) or 0)
    minus = int(ab_summary.get("wins_baseline", 0) or 0)
    pvalue = _sign_test_pvalue_plus_minus(plus, minus)
    result: dict[str, Any] = {
        "wins_candidate": plus,
        "wins_baseline": minus,
        "ties": int(ab_summary.get("ties", 0) or 0),
        "sign_test_pvalue": pvalue,
    }

    critical = ab_summary.get("critical_metric_deltas_pp", {})
    if isinstance(critical, dict):
        for key, value in critical.items():
            result[f"delta_pp.{key}"] = float(value or 0.0)

    for set_name in ("synthetic_heldout", "hard_heldout", "real_runtime"):
        payload = wins_by_set.get(set_name, {})
        if not isinstance(payload, dict):
            payload = {}
        result[f"{set_name}.wins_candidate"] = int(payload.get("candidate", 0) or 0)
        result[f"{set_name}.wins_baseline"] = int(payload.get("baseline", 0) or 0)
        result[f"{set_name}.ties"] = int(payload.get("tie", 0) or 0)

    result["paired_rows_exists"] = paired.exists()
    return result


def _script_runtime_safe(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    for key in ("actors", "objects", "beats", "actions"):
        value = payload.get(key)
        if value is None:
            continue
        if not isinstance(value, list):
            return False
        if key in {"actors", "objects", "actions"}:
            if any(not isinstance(item, dict) for item in value):
                return False
        if key == "beats":
            for beat in value:
                if not isinstance(beat, dict):
                    return False
                beat_actions = beat.get("actions")
                if beat_actions is not None:
                    if not isinstance(beat_actions, list):
                        return False
                    if any(not isinstance(action, dict) for action in beat_actions):
                        return False
    return True


def _sanitize_predictions_for_eval(*, input_path: Path, output_path: Path) -> Path:
    rows = _read_jsonl(input_path)
    sanitized: list[dict[str, Any]] = []
    for row in rows:
        row_copy = dict(row)
        pred = row_copy.get("predicted_script")
        raw_json = row_copy.get("raw_output_json")
        pred_ok = _script_runtime_safe(pred) if isinstance(pred, dict) else False
        raw_ok = _script_runtime_safe(raw_json) if isinstance(raw_json, dict) else False
        if isinstance(pred, dict) and not pred_ok:
            row_copy["predicted_script"] = None
            row_copy.setdefault("sanitization_notes", []).append("invalid_predicted_script_shape")
        if isinstance(raw_json, dict) and not raw_ok:
            row_copy["raw_output_json"] = None
            row_copy.setdefault("sanitization_notes", []).append("invalid_raw_output_json_shape")
        sanitized.append(row_copy)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as fh:
        for row in sanitized:
            fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    return output_path


def _slice_predicted_script(row: dict[str, Any], *, slice_name: str) -> dict[str, Any] | None:
    if slice_name == "model_only":
        payload = row.get("model_only_predicted_script")
    elif slice_name == "end_to_end":
        payload = row.get("end_to_end_predicted_script")
    else:
        payload = None
    if isinstance(payload, dict) and _script_runtime_safe(payload):
        return payload
    return None


def _collect_slice_metrics(
    *,
    predictions_jsonl: Path,
    checkpoint_id: str,
    cases: list[dict[str, Any]],
    runtime_policy_snapshot: dict[str, Any],
    require_both_slices: bool,
) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, int], list[str], dict[str, list[dict[str, Any]]]]:
    rows = _read_jsonl(predictions_jsonl)
    by_case: dict[str, dict[str, Any]] = {}
    for row in rows:
        case_id = str(row.get("eval_case_id", "")).strip()
        if not case_id or case_id in by_case:
            continue
        by_case[case_id] = row

    reason_counts: dict[str, int] = {}
    for row in rows:
        codes = row.get("slice_reason_codes")
        if not isinstance(codes, list):
            continue
        for code in codes:
            key = str(code).strip()
            if not key:
                continue
            reason_counts[key] = reason_counts.get(key, 0) + 1

    available_slices: list[str] = []
    if rows:
        has_model_only = all("model_only_predicted_script" in row for row in rows)
        has_end_to_end = all("end_to_end_predicted_script" in row for row in rows)
        if has_model_only:
            available_slices.append("model_only")
        if has_end_to_end:
            available_slices.append("end_to_end")

    if require_both_slices and set(available_slices) != {"model_only", "end_to_end"}:
        raise BenchmarkConfigError(
            "Slice metrics require prediction files exported with --report-slice both "
            f"(missing in {predictions_jsonl})"
        )

    out_flat: dict[str, Any] = {}
    out_rows: list[dict[str, Any]] = []
    case_results_by_slice: dict[str, list[dict[str, Any]]] = {}
    for slice_name in available_slices:
        predicted_by_case: dict[str, dict[str, Any] | None] = {}
        for case in cases:
            case_id = str(case.get("eval_case_id", "")).strip()
            row = by_case.get(case_id, {})
            predicted_by_case[case_id] = _slice_predicted_script(row, slice_name=slice_name)
        scored = score_cases(
            ScoreCasesRequest(
                checkpoint_id=f"{checkpoint_id}::{slice_name}",
                cases=cases,
                predicted_by_case=predicted_by_case,
                runtime_policy_snapshot=runtime_policy_snapshot,
            )
        )
        metrics = scored.get("set_metrics", {}).get("overall", {}).get("metrics", {})
        if not isinstance(metrics, dict):
            metrics = {}
        case_results = scored.get("case_results", [])
        if not isinstance(case_results, list):
            case_results = []
        case_results_by_slice[slice_name] = [row for row in case_results if isinstance(row, dict)]
        row_payload: dict[str, Any] = {
            "checkpoint_id": checkpoint_id,
            "slice": slice_name,
            "predictions_jsonl": str(predictions_jsonl),
        }
        for metric_name in SLICE_METRICS:
            value = float(metrics.get(metric_name, 0.0))
            out_flat[f"slice.{slice_name}.{metric_name}"] = value
            row_payload[metric_name] = value
        out_rows.append(row_payload)
    return out_flat, out_rows, reason_counts, available_slices, case_results_by_slice


def _write_csv(rows: list[dict[str, Any]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames: list[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    with output_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def _write_jsonl(rows: list[dict[str, Any]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


def _build_markdown_report(
    *,
    output_path: Path,
    config_path: Path,
    eval_bundle_dir: Path,
    run_rows: list[dict[str, Any]],
    model_summary_rows: list[dict[str, Any]],
    pair_rows: list[dict[str, Any]],
    slice_summary_rows: list[dict[str, Any]],
    slice_reason_rows: list[dict[str, Any]],
) -> None:
    lines: list[str] = []
    lines.append("# Scientific Benchmark Report")
    lines.append("")
    lines.append("## Setup")
    lines.append(f"- config: `{config_path}`")
    lines.append(f"- eval_bundle_dir: `{eval_bundle_dir}`")
    lines.append(f"- total_scored_runs: {len(run_rows)}")
    lines.append(f"- total_pairwise_compares: {len(pair_rows)}")
    lines.append("")

    lines.append("## Model Summary (mean ± std across seeds)")
    lines.append("")
    lines.append("| model_id | seeds | overall.json_valid_rate | hard.chronology_phase_accuracy | real_runtime.runtime_fallback_rate | overall.case_strict_success_rate |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    for row in model_summary_rows:
        lines.append(
            "| {model_id} | {seed_count} | {json_valid_mean:.4f} ± {json_valid_std:.4f} | {hard_chrono_mean:.4f} ± {hard_chrono_std:.4f} | {rr_fallback_mean:.4f} ± {rr_fallback_std:.4f} | {strict_mean:.4f} ± {strict_std:.4f} |".format(
                model_id=row["model_id"],
                seed_count=row["seed_count"],
                json_valid_mean=row["overall.json_valid_rate.mean"],
                json_valid_std=row["overall.json_valid_rate.std"],
                hard_chrono_mean=row["hard_heldout.chronology_phase_accuracy.mean"],
                hard_chrono_std=row["hard_heldout.chronology_phase_accuracy.std"],
                rr_fallback_mean=row["real_runtime.runtime_fallback_rate.mean"],
                rr_fallback_std=row["real_runtime.runtime_fallback_rate.std"],
                strict_mean=row["overall.case_strict_success_rate.mean"],
                strict_std=row["overall.case_strict_success_rate.std"],
            )
        )
    lines.append("")

    lines.append("## Pairwise Results")
    lines.append("")
    lines.append("| candidate | baseline | seed | wins_candidate | wins_baseline | ties | sign_test_pvalue | delta_pp.json_valid_rate | delta_pp.exact_marked_object_id_accuracy | delta_pp.chronology_phase_accuracy |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in pair_rows:
        lines.append(
            "| {candidate} | {baseline} | {seed} | {wc} | {wb} | {ties} | {p:.6f} | {d1:.3f} | {d2:.3f} | {d3:.3f} |".format(
                candidate=row["candidate_model_id"],
                baseline=row["baseline_model_id"],
                seed=row["seed"],
                wc=row.get("wins_candidate", 0),
                wb=row.get("wins_baseline", 0),
                ties=row.get("ties", 0),
                p=row.get("sign_test_pvalue", 1.0),
                d1=row.get("delta_pp.json_valid_rate", 0.0),
                d2=row.get("delta_pp.exact_marked_object_id_accuracy", 0.0),
                d3=row.get("delta_pp.chronology_phase_accuracy", 0.0),
            )
        )
    lines.append("")
    lines.append("## Slice Summary")
    lines.append("")
    if not slice_summary_rows:
        lines.append("- none")
    else:
        lines.append("| model_id | seed | slice | json_valid_rate | schema_valid_rate | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | action_recall | runtime_fallback_rate | case_strict_success_rate |")
        lines.append("| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        for row in slice_summary_rows:
            lines.append(
                "| {model_id} | {seed} | {slice} | {json:.4f} | {schema:.4f} | {ordinal:.4f} | {target:.4f} | {chronology:.4f} | {action:.4f} | {fallback:.4f} | {strict:.4f} |".format(
                    model_id=row.get("model_id", ""),
                    seed=row.get("seed", ""),
                    slice=row.get("slice", ""),
                    json=float(row.get("json_valid_rate", 0.0)),
                    schema=float(row.get("schema_valid_rate", 0.0)),
                    ordinal=float(row.get("ordinal_actor_binding_accuracy", 0.0)),
                    target=float(row.get("target_resolution_accuracy", 0.0)),
                    chronology=float(row.get("chronology_phase_accuracy", 0.0)),
                    action=float(row.get("action_recall", 0.0)),
                    fallback=float(row.get("runtime_fallback_rate", 0.0)),
                    strict=float(row.get("case_strict_success_rate", 0.0)),
                )
            )
    lines.append("")
    lines.append("## Slice Reason Codes")
    lines.append("")
    if not slice_reason_rows:
        lines.append("- none")
    else:
        lines.append("| model_id | seed | reason_code | count |")
        lines.append("| --- | ---: | --- | ---: |")
        for row in slice_reason_rows:
            lines.append(
                "| {model_id} | {seed} | {reason_code} | {count} |".format(
                    model_id=row.get("model_id", ""),
                    seed=row.get("seed", ""),
                    reason_code=row.get("reason_code", ""),
                    count=int(row.get("count", 0) or 0),
                )
            )
    lines.append("")
    lines.append("## Artifacts")
    lines.append("- `runs_scored.csv`")
    lines.append("- `model_summary.csv`")
    lines.append("- `pairwise_compare.csv`")
    lines.append("- `model_slice_summary.csv`")
    lines.append("- `model_slice_summary_by_model.csv`")
    lines.append("- `slice_reason_codes.csv`")
    lines.append("- `slice_gate_results.csv`")
    lines.append("- `slice_gate_winner.json` (when at least one candidate passes)")
    lines.append("- `reports/` (raw eval harness outputs)")
    lines.append("- `compares/` (A/B per-seed outputs)")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _build_model_summary(run_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in run_rows:
        grouped.setdefault(str(row["model_id"]), []).append(row)

    summary_rows: list[dict[str, Any]] = []
    metrics = [
        "overall.json_valid_rate",
        "hard_heldout.chronology_phase_accuracy",
        "real_runtime.runtime_fallback_rate",
        "overall.case_strict_success_rate",
    ]
    for model_id in sorted(grouped.keys()):
        rows = grouped[model_id]
        summary: dict[str, Any] = {"model_id": model_id, "seed_count": len(rows)}
        for metric in metrics:
            values = [float(item.get(metric, 0.0)) for item in rows]
            mean, std = _mean_std(values)
            summary[f"{metric}.mean"] = mean
            summary[f"{metric}.std"] = std
        summary_rows.append(summary)
    return summary_rows


def _build_slice_model_summary(slice_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in slice_rows:
        model_id = str(row.get("model_id", ""))
        slice_name = str(row.get("slice", ""))
        grouped.setdefault((model_id, slice_name), []).append(row)

    summary_rows: list[dict[str, Any]] = []
    for (model_id, slice_name) in sorted(grouped.keys()):
        rows = grouped[(model_id, slice_name)]
        summary: dict[str, Any] = {
            "model_id": model_id,
            "slice": slice_name,
            "seed_count": len(rows),
        }
        for metric in SLICE_METRICS:
            values = [float(item.get(metric, 0.0)) for item in rows]
            mean, std = _mean_std(values)
            summary[f"{metric}.mean"] = mean
            summary[f"{metric}.std"] = std
        summary_rows.append(summary)
    return summary_rows


def _evaluate_slice_gate(
    *,
    run_rows: list[dict[str, Any]],
    baseline_model_id: str,
) -> tuple[list[dict[str, Any]], dict[str, Any] | None]:
    by_model_seed: dict[tuple[str, int], dict[str, Any]] = {}
    for row in run_rows:
        by_model_seed[(str(row.get("model_id", "")), int(row.get("seed", 0) or 0))] = row

    gate_rows: list[dict[str, Any]] = []
    for row in run_rows:
        model_id = str(row.get("model_id", ""))
        seed = int(row.get("seed", 0) or 0)
        if model_id == baseline_model_id:
            continue
        baseline = by_model_seed.get((baseline_model_id, seed))
        if baseline is None:
            continue

        blockers: list[str] = []
        required_raw_keys = [
            "slice.model_only.json_valid_rate",
            "slice.model_only.schema_valid_rate",
            "slice.model_only.ordinal_actor_binding_accuracy",
            "slice.model_only.target_resolution_accuracy",
            "slice.model_only.chronology_phase_accuracy",
            "slice.model_only.action_recall",
            "slice.model_only.runtime_fallback_rate",
            "slice.model_only.case_strict_success_rate",
        ]
        required_end_to_end_keys = [
            "slice.end_to_end.json_valid_rate",
            "slice.end_to_end.schema_valid_rate",
            "slice.end_to_end.target_resolution_accuracy",
            "slice.end_to_end.chronology_phase_accuracy",
            "slice.end_to_end.action_recall",
            "slice.end_to_end.runtime_fallback_rate",
        ]
        has_all_keys = all(key in row for key in required_raw_keys + required_end_to_end_keys) and all(
            key in baseline for key in required_raw_keys
        )
        if not has_all_keys:
            gate_rows.append(
                {
                    "model_id": model_id,
                    "seed": seed,
                    "baseline_model_id": baseline_model_id,
                    "gate_pass": False,
                    "blocking_reasons": "missing_slice_metrics",
                    "balanced_score": float("-inf"),
                }
            )
            continue

        def _val(payload: dict[str, Any], key: str) -> float:
            return float(payload.get(key, 0.0) or 0.0)

        raw_checks = {
            "json_non_regression": _val(row, "slice.model_only.json_valid_rate") >= _val(baseline, "slice.model_only.json_valid_rate"),
            "schema_non_regression": _val(row, "slice.model_only.schema_valid_rate") >= _val(baseline, "slice.model_only.schema_valid_rate"),
            "ordinal_non_regression": _val(row, "slice.model_only.ordinal_actor_binding_accuracy") >= _val(
                baseline, "slice.model_only.ordinal_actor_binding_accuracy"
            ),
            "target_improved": _val(row, "slice.model_only.target_resolution_accuracy") > _val(
                baseline, "slice.model_only.target_resolution_accuracy"
            ),
            "chronology_improved": _val(row, "slice.model_only.chronology_phase_accuracy") > _val(
                baseline, "slice.model_only.chronology_phase_accuracy"
            ),
            "action_improved": _val(row, "slice.model_only.action_recall") > _val(
                baseline, "slice.model_only.action_recall"
            ),
            "strict_improved": _val(row, "slice.model_only.case_strict_success_rate") > _val(
                baseline, "slice.model_only.case_strict_success_rate"
            ),
            "fallback_reduced": _val(row, "slice.model_only.runtime_fallback_rate") < _val(
                baseline, "slice.model_only.runtime_fallback_rate"
            ),
        }
        for name, ok in raw_checks.items():
            if not ok:
                blockers.append(f"raw::{name}")

        end_to_end_checks = {
            "parse_non_regression_vs_raw": _val(row, "slice.end_to_end.json_valid_rate") >= _val(
                row, "slice.model_only.json_valid_rate"
            )
            and _val(row, "slice.end_to_end.schema_valid_rate") >= _val(row, "slice.model_only.schema_valid_rate"),
            "target_improved_vs_raw": _val(row, "slice.end_to_end.target_resolution_accuracy")
            > _val(row, "slice.model_only.target_resolution_accuracy"),
            "chronology_improved_vs_raw": _val(row, "slice.end_to_end.chronology_phase_accuracy")
            > _val(row, "slice.model_only.chronology_phase_accuracy"),
            "action_improved_vs_raw": _val(row, "slice.end_to_end.action_recall") > _val(row, "slice.model_only.action_recall"),
            "fallback_reduced_vs_raw": _val(row, "slice.end_to_end.runtime_fallback_rate")
            < _val(row, "slice.model_only.runtime_fallback_rate"),
        }
        for name, ok in end_to_end_checks.items():
            if not ok:
                blockers.append(f"end_to_end::{name}")

        delta_target = _val(row, "slice.model_only.target_resolution_accuracy") - _val(
            baseline, "slice.model_only.target_resolution_accuracy"
        )
        delta_chron = _val(row, "slice.model_only.chronology_phase_accuracy") - _val(
            baseline, "slice.model_only.chronology_phase_accuracy"
        )
        delta_action = _val(row, "slice.model_only.action_recall") - _val(
            baseline, "slice.model_only.action_recall"
        )
        delta_strict = _val(row, "slice.model_only.case_strict_success_rate") - _val(
            baseline, "slice.model_only.case_strict_success_rate"
        )
        parse_penalty = max(0.0, _val(baseline, "slice.model_only.json_valid_rate") - _val(row, "slice.model_only.json_valid_rate"))
        schema_penalty = max(
            0.0,
            _val(baseline, "slice.model_only.schema_valid_rate") - _val(row, "slice.model_only.schema_valid_rate"),
        )
        ordinal_penalty = max(
            0.0,
            _val(baseline, "slice.model_only.ordinal_actor_binding_accuracy")
            - _val(row, "slice.model_only.ordinal_actor_binding_accuracy"),
        )
        fallback_penalty = max(
            0.0,
            _val(row, "slice.model_only.runtime_fallback_rate")
            - _val(baseline, "slice.model_only.runtime_fallback_rate"),
        )
        balanced_score = (
            (delta_target + delta_chron + delta_action + delta_strict) * 100.0
            - parse_penalty * 150.0
            - schema_penalty * 150.0
            - ordinal_penalty * 80.0
            - fallback_penalty * 100.0
        )

        gate_rows.append(
            {
                "model_id": model_id,
                "seed": seed,
                "baseline_model_id": baseline_model_id,
                "gate_pass": len(blockers) == 0,
                "blocking_reasons": ";".join(blockers),
                "balanced_score": balanced_score,
            }
        )

    passed = [row for row in gate_rows if bool(row.get("gate_pass", False))]
    winner: dict[str, Any] | None = None
    if passed:
        winner = max(
            passed,
            key=lambda item: (
                float(item.get("balanced_score", 0.0)),
                str(item.get("model_id", "")),
                int(item.get("seed", 0) or 0),
            ),
        )
    return gate_rows, winner


def _prepare_specs(
    cfg: dict[str, Any],
    *,
    output_dir: Path,
    resolve_only: bool,
) -> tuple[list[ModelRunSpec], list[PairSpec], Path, Path, int]:
    eval_bundle_dir = Path(str(cfg.get("eval_bundle_dir", "")).strip()).expanduser()
    if not eval_bundle_dir:
        raise BenchmarkConfigError("config.eval_bundle_dir is required")
    if not resolve_only and not eval_bundle_dir.exists():
        raise BenchmarkConfigError(f"eval_bundle_dir does not exist: {eval_bundle_dir}")

    eval_seed = int(cfg.get("eval_seed", 20260419))
    seeds = [int(x) for x in _as_list(cfg.get("seeds", []), label="config.seeds")]
    if not seeds:
        raise BenchmarkConfigError("config.seeds must be non-empty")

    models_raw = _as_list(cfg.get("models", []), label="config.models")
    if not models_raw:
        raise BenchmarkConfigError("config.models must be non-empty")

    model_cfg_by_id: dict[str, dict[str, Any]] = {}
    for idx, raw in enumerate(models_raw, start=1):
        mcfg = _as_dict(raw, label=f"models[{idx}]")
        model_id = str(mcfg.get("id", "")).strip()
        model_name = str(mcfg.get("name", model_id)).strip()
        if not model_id:
            raise BenchmarkConfigError(f"models[{idx}].id is required")
        if model_id in model_cfg_by_id:
            raise BenchmarkConfigError(f"duplicate model id: {model_id!r}")
        mcfg["name"] = model_name or model_id
        model_cfg_by_id[model_id] = mcfg

    pair_defs = _validate_pairs(
        _as_list(cfg.get("pairs", []), label="config.pairs"),
        known_models=set(model_cfg_by_id.keys()),
    )

    checkpoint_template = str(cfg.get("checkpoint_id_template", "{model_id}_seed{seed}"))
    reports_root = output_dir / "reports"
    compares_root = output_dir / "compares"

    run_specs: list[ModelRunSpec] = []
    for model_id in sorted(model_cfg_by_id.keys()):
        mcfg = model_cfg_by_id[model_id]
        model_name = str(mcfg.get("name", model_id))
        for seed in seeds:
            mapping = {
                "model_id": model_id,
                "model_name": model_name,
                "seed": seed,
                "output_dir": str(output_dir),
                "reports_root": str(reports_root),
                "compares_root": str(compares_root),
            }
            checkpoint_id = _fmt(checkpoint_template, mapping)
            predictions_path = _resolve_predictions_path(mcfg, seed=seed, mapping=mapping)
            if predictions_path is None:
                raise BenchmarkConfigError(
                    f"model {model_id!r} seed {seed}: predictions path is missing; "
                    "set predictions_by_seed/predictions_path_template/predictions_path"
                )
            report_dir = reports_root / _safe_key(model_id) / f"seed_{seed}"
            run_specs.append(
                ModelRunSpec(
                    model_id=model_id,
                    model_name=model_name,
                    seed=seed,
                    checkpoint_id=checkpoint_id,
                    predictions_jsonl=predictions_path,
                    report_dir=report_dir,
                )
            )

    pair_specs: list[PairSpec] = []
    for candidate, baseline in pair_defs:
        for seed in seeds:
            compare_dir = compares_root / f"{_safe_key(candidate)}_vs_{_safe_key(baseline)}" / f"seed_{seed}"
            pair_specs.append(
                PairSpec(
                    candidate_model_id=candidate,
                    baseline_model_id=baseline,
                    seed=seed,
                    compare_dir=compare_dir,
                )
            )

    return run_specs, pair_specs, eval_bundle_dir, output_dir, eval_seed


def _maybe_generate_predictions(
    *,
    cfg: dict[str, Any],
    run_spec: ModelRunSpec,
    dry_run: bool,
) -> None:
    models = _as_list(cfg.get("models", []), label="config.models")
    model_cfg: dict[str, Any] | None = None
    for item in models:
        if isinstance(item, dict) and str(item.get("id", "")).strip() == run_spec.model_id:
            model_cfg = item
            break
    if model_cfg is None:
        return
    command_template = model_cfg.get("generate_predictions_cmd")
    if not isinstance(command_template, str) or not command_template.strip():
        raise BenchmarkConfigError(
            f"predictions file missing for model={run_spec.model_id} seed={run_spec.seed}, "
            "and generate_predictions_cmd is not configured"
        )

    mapping = {
        "model_id": run_spec.model_id,
        "model_name": run_spec.model_name,
        "seed": run_spec.seed,
        "checkpoint_id": run_spec.checkpoint_id,
        "predictions_jsonl": str(run_spec.predictions_jsonl),
        "report_dir": str(run_spec.report_dir),
    }
    cmd = command_template.format_map(mapping)
    print(f"[benchmark] generating predictions: {cmd}")
    if dry_run:
        return
    env = os.environ.copy()
    _run_shell(cmd, env=env)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Scientific benchmark orchestrator for base_qwen3_1_7b / dataset_v6 / dataset_v7 / dataset_v7_orpo. "
            "Runs score+compare across seeds and builds aggregate tables."
        )
    )
    parser.add_argument("--config", type=Path, required=True, help="Path to benchmark config JSON")
    parser.add_argument("--output-dir", type=Path, required=True, help="Where reports/compares/summary files are stored")
    parser.add_argument(
        "--eval-cli",
        type=Path,
        default=Path("/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/eval/07_eval_local_model.py"),
        help="Path to SGv7 eval harness CLI",
    )
    parser.add_argument(
        "--mode",
        choices=("full", "score-only", "aggregate-only"),
        default="full",
        help="full=score+compare+aggregate, score-only=skip pairwise compare, aggregate-only=read existing artifacts",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without executing eval commands",
    )
    parser.add_argument(
        "--allow-generate-predictions",
        action="store_true",
        help="If predictions file is missing, execute per-model generate_predictions_cmd from config",
    )
    parser.add_argument(
        "--sanitize-predictions-before-score",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Drop structurally invalid predicted_script/raw_output_json payloads before score mode.",
    )
    args = parser.parse_args()

    config_path = args.config.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    eval_cli = args.eval_cli.expanduser().resolve()

    if not config_path.exists():
        raise SystemExit(f"Config not found: {config_path}")
    if not eval_cli.exists() and args.mode != "aggregate-only":
        raise SystemExit(f"Eval CLI not found: {eval_cli}")

    cfg = _read_json(config_path)
    run_specs, pair_specs, eval_bundle_dir, output_dir, eval_seed = _prepare_specs(
        cfg, output_dir=output_dir, resolve_only=(args.mode == "aggregate-only")
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "reports").mkdir(parents=True, exist_ok=True)
    (output_dir / "compares").mkdir(parents=True, exist_ok=True)
    (output_dir / "aggregate").mkdir(parents=True, exist_ok=True)

    # 1) SCORE RUNS
    if args.mode in ("full", "score-only"):
        for spec in run_specs:
            if not spec.predictions_jsonl.exists():
                if args.allow_generate_predictions:
                    _maybe_generate_predictions(cfg=cfg, run_spec=spec, dry_run=args.dry_run)
                if not args.dry_run and not spec.predictions_jsonl.exists():
                    raise SystemExit(
                        f"Missing predictions after generation attempt: {spec.predictions_jsonl} "
                        f"(model={spec.model_id}, seed={spec.seed})"
                    )
            score_cmd = [
                sys.executable,
                str(eval_cli),
                "--mode",
                "score",
                "--eval-bundle-dir",
                str(eval_bundle_dir),
                "--checkpoint-id",
                spec.checkpoint_id,
                "--predictions-jsonl",
                "",
                "--output-dir",
                str(spec.report_dir),
                "--seed",
                str(eval_seed),
            ]
            score_predictions_path = spec.predictions_jsonl
            if bool(args.sanitize_predictions_before_score):
                sanitized_path = (
                    output_dir
                    / "predictions_sanitized"
                    / _safe_key(spec.model_id)
                    / f"seed_{spec.seed}.jsonl"
                )
                if args.dry_run:
                    score_predictions_path = sanitized_path
                else:
                    score_predictions_path = _sanitize_predictions_for_eval(
                        input_path=spec.predictions_jsonl,
                        output_path=sanitized_path,
                    )
            score_cmd[9] = str(score_predictions_path)
            print(f"[benchmark] score model={spec.model_id} seed={spec.seed}")
            if args.dry_run:
                print("  " + " ".join(shlex.quote(x) for x in score_cmd))
            else:
                _run(score_cmd)

    # 2) COMPARE RUNS
    if args.mode == "full":
        report_by_model_seed: dict[tuple[str, int], Path] = {
            (x.model_id, x.seed): x.report_dir for x in run_specs
        }
        for pair in pair_specs:
            candidate_report = report_by_model_seed[(pair.candidate_model_id, pair.seed)]
            baseline_report = report_by_model_seed[(pair.baseline_model_id, pair.seed)]
            compare_cmd = [
                sys.executable,
                str(eval_cli),
                "--mode",
                "compare",
                "--candidate-report",
                str(candidate_report),
                "--baseline-report",
                str(baseline_report),
                "--output-dir",
                str(pair.compare_dir),
            ]
            print(
                f"[benchmark] compare candidate={pair.candidate_model_id} baseline={pair.baseline_model_id} seed={pair.seed}"
            )
            if args.dry_run:
                print("  " + " ".join(shlex.quote(x) for x in compare_cmd))
            else:
                _run(compare_cmd)

    # 3) AGGREGATION
    aggregate_dir = output_dir / "aggregate"
    run_rows: list[dict[str, Any]] = []
    slice_rows: list[dict[str, Any]] = []
    reason_rows: list[dict[str, Any]] = []
    slice_case_result_payloads: list[tuple[Path, list[dict[str, Any]]]] = []
    eval_cases_path = eval_bundle_dir / "eval_cases.jsonl"
    runtime_policy_path = eval_bundle_dir / "runtime_policy_snapshot.json"
    can_recompute_slices = eval_cases_path.exists() and runtime_policy_path.exists()
    eval_cases: list[dict[str, Any]] = []
    runtime_policy_snapshot: dict[str, Any] = {}
    if can_recompute_slices:
        eval_cases = _read_jsonl(eval_cases_path)
        runtime_policy_snapshot = _read_json(runtime_policy_path)
    elif args.mode != "aggregate-only":
        raise SystemExit(
            "Slice recompute requires eval bundle files: "
            f"{eval_cases_path} and {runtime_policy_path}"
        )
    else:
        print(
            "[benchmark] aggregate-only: missing eval bundle inputs for slice recompute; "
            "slice summaries will be skipped."
        )

    for spec in run_specs:
        if not spec.report_dir.exists():
            if args.mode == "aggregate-only":
                raise SystemExit(f"Missing report dir for aggregate-only mode: {spec.report_dir}")
            continue
        row: dict[str, Any] = {
            "model_id": spec.model_id,
            "model_name": spec.model_name,
            "seed": spec.seed,
            "checkpoint_id": spec.checkpoint_id,
            "report_dir": str(spec.report_dir),
            "predictions_jsonl": str(spec.predictions_jsonl),
        }
        row.update(_collect_score_metrics(spec.report_dir))
        if can_recompute_slices and spec.predictions_jsonl.exists():
            slice_flat, per_slice_rows, reason_counts, available_slices, case_results_by_slice = _collect_slice_metrics(
                predictions_jsonl=spec.predictions_jsonl,
                checkpoint_id=spec.checkpoint_id,
                cases=eval_cases,
                runtime_policy_snapshot=runtime_policy_snapshot,
                require_both_slices=(args.mode != "aggregate-only"),
            )
            row.update(slice_flat)
            row["slice_available"] = ",".join(available_slices)
            for item in per_slice_rows:
                slice_name = str(item.get("slice", "")).strip()
                case_results_jsonl = (
                    aggregate_dir
                    / "slice_case_results"
                    / _safe_key(spec.model_id)
                    / f"seed_{spec.seed}"
                    / f"{slice_name}_case_results.jsonl"
                )
                if slice_name:
                    slice_case_result_payloads.append((case_results_jsonl, case_results_by_slice.get(slice_name, [])))
                slice_rows.append(
                    {
                        "model_id": spec.model_id,
                        "seed": spec.seed,
                        "case_results_jsonl": str(case_results_jsonl),
                        **item,
                    }
                )
            for reason_code in sorted(reason_counts.keys()):
                reason_rows.append(
                    {
                        "model_id": spec.model_id,
                        "seed": spec.seed,
                        "reason_code": reason_code,
                        "count": int(reason_counts[reason_code]),
                        "predictions_jsonl": str(spec.predictions_jsonl),
                    }
                )
        elif args.mode == "aggregate-only":
            row["slice_available"] = "unavailable"
        run_rows.append(row)

    pair_rows: list[dict[str, Any]] = []
    for pair in pair_specs:
        if not pair.compare_dir.exists():
            continue
        row: dict[str, Any] = {
            "candidate_model_id": pair.candidate_model_id,
            "baseline_model_id": pair.baseline_model_id,
            "seed": pair.seed,
            "compare_dir": str(pair.compare_dir),
        }
        row.update(_collect_compare_metrics(pair.compare_dir))
        pair_rows.append(row)

    model_summary_rows = _build_model_summary(run_rows)
    slice_model_summary_rows = _build_slice_model_summary(slice_rows)
    baseline_model_id = str(cfg.get("slice_gate_baseline_model_id", "")).strip()
    if not baseline_model_id and any(str(row.get("model_id", "")) == "dataset_v7_orpo" for row in run_rows):
        baseline_model_id = "dataset_v7_orpo"
    slice_gate_rows: list[dict[str, Any]] = []
    slice_gate_winner: dict[str, Any] | None = None
    if baseline_model_id:
        slice_gate_rows, slice_gate_winner = _evaluate_slice_gate(
            run_rows=run_rows,
            baseline_model_id=baseline_model_id,
        )

    _write_csv(run_rows, aggregate_dir / "runs_scored.csv")
    _write_csv(model_summary_rows, aggregate_dir / "model_summary.csv")
    _write_csv(pair_rows, aggregate_dir / "pairwise_compare.csv")
    _write_csv(slice_rows, aggregate_dir / "model_slice_summary.csv")
    _write_csv(slice_model_summary_rows, aggregate_dir / "model_slice_summary_by_model.csv")
    _write_csv(reason_rows, aggregate_dir / "slice_reason_codes.csv")
    for path, rows in slice_case_result_payloads:
        _write_jsonl(rows, path)
    _write_csv(slice_gate_rows, aggregate_dir / "slice_gate_results.csv")
    if slice_gate_winner is not None:
        (aggregate_dir / "slice_gate_winner.json").write_text(
            json.dumps(slice_gate_winner, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    metadata = {
        "config_path": str(config_path),
        "eval_bundle_dir": str(eval_bundle_dir),
        "eval_cli": str(eval_cli),
        "mode": args.mode,
        "eval_seed": eval_seed,
        "total_runs": len(run_rows),
        "total_pairwise_rows": len(pair_rows),
        "total_slice_rows": len(slice_rows),
        "total_slice_reason_rows": len(reason_rows),
        "total_slice_case_result_files": len(slice_case_result_payloads),
        "slice_recompute_enabled": can_recompute_slices,
        "slice_gate_baseline_model_id": baseline_model_id or None,
        "slice_gate_rows": len(slice_gate_rows),
        "primary_set_metrics": PRIMARY_SET_METRICS,
        "primary_buckets": PRIMARY_BUCKETS,
        "slice_metrics": SLICE_METRICS,
    }
    (aggregate_dir / "benchmark_manifest.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    _build_markdown_report(
        output_path=aggregate_dir / "scientific_report.md",
        config_path=config_path,
        eval_bundle_dir=eval_bundle_dir,
        run_rows=run_rows,
        model_summary_rows=model_summary_rows,
        pair_rows=pair_rows,
        slice_summary_rows=slice_rows,
        slice_reason_rows=reason_rows,
    )

    print(f"[benchmark] done. aggregate artifacts: {aggregate_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
