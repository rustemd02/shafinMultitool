#!/usr/bin/env python3
"""Threshold planner for the FP_CORRECT budget (runbook §5.1, feeds M04).

The product decision is FP_CORRECT ≤2% on good in-domain frames, proven by the
one-sided 95% upper bound — not by a point estimate that a small lucky set can
produce. This tool derives the advising threshold from the **calibration** split
so the locked split stays untouched, and it refuses to invent a threshold when
the calibration data cannot support the budget.

Definitions used (from §5.1):
    advised good frames     = good frames on which the candidate emits a CORRECT
    FP_CORRECT              = advised good frames carrying ≥1 forbidden correction
                              / advised good frames
    coverage                = advised frames / all frames (gate: ≥0.65 overall)
    abstained/KEEP frames   are reported separately and never enter the numerator

Input: calibration records, one JSON object per line:
    {"cluster_id": "shoot-a", "is_good_frame": true, "score": 0.83,
     "would_emit_correction": true, "forbidden_correction": false, "bucket": "ordinary"}
Only `cluster_id`, `score` and `would_emit_correction` are mandatory; the rest
default to conservative values (treated as good + forbidden when unknown makes
the gate harder, never easier).

Usage
    python3 tools/release/plan_abstention_threshold.py --calibration <file.jsonl> --out <policy.json>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_candidate_gates import FP_CORRECT_BUDGET, clopper_pearson_upper  # noqa: E402

MIN_INDEPENDENT_CLUSTERS = 2

DEFAULT_POLICY = Path(__file__).resolve().parents[2] / "datasets/camera-coach/v1/evaluation-policy-v1.json"
COVERAGE_FLOOR_KEYS = ("accepted_coverage_overall", "accepted_coverage_ordinary",
                       "accepted_coverage_difficult_light")


def load_coverage_floors(policy_path: Path, metric: str) -> dict[str, float]:
    """The coverage floors the chosen threshold must still satisfy."""
    document = json.loads(policy_path.read_text(encoding="utf-8"))
    gates = ((document.get("rate_gates") or {}) if metric == "rate_gates"
             else (document.get("human_gates") or {}))
    missing = [key for key in COVERAGE_FLOOR_KEYS if key not in gates]
    if missing:
        raise ValueError(f"policy lacks coverage floors {missing}")
    return {key: float(gates[key]["threshold"]) for key in COVERAGE_FLOOR_KEYS}


def coverage_shortfalls(row: dict, floors: dict[str, float]) -> dict[str, float]:
    """Which floors this row misses; an absent bucket is not a shortfall."""
    short = {}
    for key, floor in floors.items():
        value = row.get(key if key != "accepted_coverage_overall" else "coverage_overall")
        if key == "accepted_coverage_ordinary":
            value = row.get("coverage_ordinary")
        elif key == "accepted_coverage_difficult_light":
            value = row.get("coverage_difficult_light")
        if value is None:
            continue  # no such frames in the calibration set
        if value < floor:
            short[key] = value
    return short


FORBIDDEN_BUDGET = 0.02


def load_calibration(path: Path) -> list[dict]:
    """Read calibration records; the split must be declared as calibration.

    The threshold may only be chosen on calibration data (runbook 5.1: no fitting on
    the locked test). A file that does not say which split it is cannot be checked at
    all, so an undeclared split is refused rather than assumed.
    """
    records = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        record = json.loads(line)
        if "cluster_id" not in record or "score" not in record:
            raise ValueError(f"line {line_number}: cluster_id and score are required")
        split = record.get("split")
        if split is None:
            raise ValueError(f"line {line_number}: split is required; a file that does not declare "
                             "its split cannot be checked against 'calibration only'")
        if split != "calibration":
            raise ValueError(f"line {line_number}: split={split!r}; a threshold may only be derived "
                             "from the calibration split, never from the locked test")
        records.append({
            "cluster_id": record["cluster_id"],
            "score": float(record["score"]),
            "is_good_frame": bool(record.get("is_good_frame", True)),
            "would_emit_correction": bool(record.get("would_emit_correction", True)),
            "forbidden_correction": bool(record.get("forbidden_correction", False)),
            "critical_forbidden": bool(record.get("critical_forbidden", False)),
            "bucket": record.get("bucket", "ordinary"),
        })
    return records


def evaluate_threshold(records: list[dict], threshold: int) -> dict:
    """Serve only records whose score >= threshold; the rest abstain."""
    advised = [r for r in records if r["score"] >= threshold]
    good = [r for r in advised if r["is_good_frame"]]
    bad = [r for r in good if r.get("forbidden_correction", False)]
    n = len(good)
    point = (len(bad) / n) if n else None
    upper = clopper_pearson_upper(len(bad), n) if n else None
    # the older gate stays in force: forbidden advice over everything served
    forbidden_advised = [r for r in advised if r.get("forbidden_correction", False)]
    forbidden_rate = (len(forbidden_advised) / len(advised)) if advised else None
    critical_advised = [r for r in advised if r.get("critical_forbidden", False)]
    coverage = len(advised) / len(records) if records else 0.0
    ordinary = [r for r in advised if r["bucket"] != "difficult_light"]
    difficult = [r for r in advised if r["bucket"] == "difficult_light"]
    ordinary_all = [r for r in records if r["bucket"] != "difficult_light"]
    difficult_all = [r for r in records if r["bucket"] == "difficult_light"]
    return {
        "threshold": threshold,
        "advised": len(advised),
        "good_advised": n,
        "forbidden_in_advised_good": len(bad),
        "fp_point": point,
        "fp_upper_95": upper,
        "forbidden_rate": forbidden_rate,
        "critical_forbidden_advised": len(critical_advised),
        "coverage_overall": coverage,
        # None means "no such frames", which is not the same as "covered none"
        "coverage_ordinary": (len(ordinary) / len(ordinary_all)) if ordinary_all else None,
        "coverage_difficult_light": (len(difficult) / len(difficult_all)) if difficult_all else None,
        "clusters_advised": len({r["cluster_id"] for r in advised}),
    }


def plan(records: list[dict], budget: float = FP_CORRECT_BUDGET,
         coverage_floors: dict[str, float] | None = None) -> dict:
    """Pick the threshold that proves the budget while keeping the coverage floors.

    A threshold can meet FP_CORRECT by advising almost nothing, which is the
    "silence everywhere" the owner forbids. So the floors are part of feasibility,
    not a note printed next to a pass.
    """
    # The floors are part of the acceptance definition, not an optional extra: a
    # caller that omits them gets them from the frozen policy, so the silence case
    # cannot be reached by simply not passing them.
    floors = coverage_floors if coverage_floors is not None         else load_coverage_floors(DEFAULT_POLICY, "rate_gates")
    clusters = {r["cluster_id"] for r in records}
    # candidate thresholds are the observed integer/label scores
    steps = sorted({int(r["score"]) for r in records}, reverse=True)
    ladder = [evaluate_threshold(records, t) for t in steps]
    budget_feasible = [row for row in ladder
                       if row["fp_upper_95"] is not None and row["fp_upper_95"] <= budget
                       and row["critical_forbidden_advised"] == 0
                       and row["forbidden_rate"] is not None
                       and row["forbidden_rate"] <= FORBIDDEN_BUDGET]
    feasible = [row for row in budget_feasible if not coverage_shortfalls(row, floors)]
    result = {
        "calibration_records": len(records),
        "clusters": len(clusters),
        "budget": budget,
        "forbidden_budget": FORBIDDEN_BUDGET,
        "coverage_floors": floors,
        "ladder": ladder,
    }
    if len(clusters) < MIN_INDEPENDENT_CLUSTERS:
        result.update({"verdict": "insufficient_evidence",
                       "reason": f"only {len(clusters)} source-shoot clusters; independence is not established",
                       "policy": None})
        return result
    if not feasible:
        best = min((row for row in ladder if row["fp_upper_95"] is not None),
                   key=lambda row: row["fp_upper_95"], default=None)
        if budget_feasible:
            # the budget holds only by silencing frames the coverage floors require
            best_effort = max(budget_feasible,
                              key=lambda row: (row["coverage_overall"], row["coverage_difficult_light"] or 0.0))
            result.update({
                "verdict": "insufficient_evidence",
                "reason": ("no threshold proves the budget while keeping the coverage floors "
                           f"{floors}; the budget is only met by silencing frames "
                           f"(best effort covers {best_effort['coverage_overall']:.1%}), which is the "
                           "silence case the owner forbids"),
                "best_effort": best_effort,
                "coverage_shortfalls": coverage_shortfalls(best_effort, floors),
                "policy": None,
            })
            return result
        result.update({
            "verdict": "insufficient_evidence",
            "reason": ("no threshold satisfies both the FP_CORRECT upper bound and the forbidden budget "
                       "(or it would serve a critical forbidden case)"),
            "best_effort": best,
            "policy": None,
        })
        return result
    # among feasible thresholds prefer the highest coverage, then the harder-light coverage
    chosen = max(feasible, key=lambda row: (row["coverage_overall"],
                                            row["coverage_difficult_light"] or 0.0))
    result.update({
        "verdict": "pass",
        "reason": (f"threshold {chosen['threshold']} keeps the one-sided 95% upper bound at "
                   f"{chosen['fp_upper_95']:.4%} (forbidden rate {chosen['forbidden_rate']:.4%}) "
                   f"with coverage {chosen['coverage_overall']:.1%}"),
        "policy": {
            "advise_threshold": chosen["threshold"],
            "fp_correct_point": chosen["fp_point"],
            "fp_correct_upper_95": chosen["fp_upper_95"],
            "forbidden_rate": chosen["forbidden_rate"],
            "critical_forbidden_advised": chosen["critical_forbidden_advised"],
            "coverage_overall": chosen["coverage_overall"],
            "coverage_ordinary": chosen["coverage_ordinary"],
            "coverage_difficult_light": chosen["coverage_difficult_light"],
            "derived_from": "calibration split only; the locked split was not read",
        },
    })
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calibration", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--budget", type=float, default=FP_CORRECT_BUDGET)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY,
                        help="frozen evaluation policy: the coverage floors are read from it, not invented")
    args = parser.parse_args(argv)

    if not args.calibration.exists():
        print(f"FAIL CLOSED: calibration file not found at {args.calibration}")
        return 2
    if not args.policy.is_file():
        print(f"FAIL CLOSED: the frozen evaluation policy is missing: {args.policy}")
        return 2
    try:
        records = load_calibration(args.calibration)
        if not records:
            print("FAIL CLOSED: calibration file has no records; no threshold can be derived")
            return 2
        floors = load_coverage_floors(args.policy, "rate_gates")
        result = plan(records, args.budget, floors)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        # a traceback is fail-closed but unreadable; say what was wrong instead
        print(f"FAIL CLOSED: {error}")
        return 2
    print(f"verdict: {result['verdict']}")
    print(f"reason: {result['reason']}")
    if result["policy"]:
        print(json.dumps(result["policy"], ensure_ascii=False, indent=2))
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"WROTE {args.out}")
    return 0 if result["verdict"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
