#!/usr/bin/env python3
"""Pair two evaluation arms by record and emit the comparison the §5.1 gate needs.

The neural-gain gate wants paired per-cluster values from two arms, and it
computes the paired bootstrap itself. What was missing is the step before that:
pairing the arms honestly and deriving the numbers, which is easy to do wrongly —
comparing two arms that do not cover the same records is not a paired comparison,
and feeding two deterministic runs into the `neural_gain` block would relabel them
as a neural result.

So this tool:

* pairs strictly by `record_id` and refuses when the two arms do not cover the
  same records (a non-paired comparison is not a paired comparison);
* requires an explicit kind for each arm, and only writes
  `evaluation.neural_gain` when the arms are declared `neural` versus
  `deterministic_baseline`. Any other pair is reported as a plain comparison and
  the gate then finds `neural_gain` not measurable — which is the honest outcome
  for two deterministic arms;
* reports how many records it paired and how many it excluded, so a shrinking
  denominator cannot hide inside a comparison;
* leaves the bootstrap to the gate, so there is exactly one implementation of
  that statistic in the toolchain.

The arm kinds are declarations, like the gold declarations: this tool makes the
label unforgeable by accident, not by intent.

Exit codes
    0  a comparison was produced
    1  the arms disagree with each other in a way that forbids pairing
    2  an input is missing, unreadable, or lacks the required columns

Usage
    python3 tools/release/compare_arms.py \\
        --arm-a <candidate>/case_results.jsonl --arm-a-kind neural \\
        --arm-b <baseline>/case_results.jsonl --arm-b-kind deterministic_baseline \\
        --clusters clusters.json --metric passed --safety-metric forbidden_action_violation \\
        --out comparison.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

NEURAL_KIND = "neural"
BASELINE_KIND = "deterministic_baseline"
KNOWN_KINDS = (NEURAL_KIND, BASELINE_KIND, "candidate", "candidate_calibrated", "reference")


class InputError(Exception):
    pass


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_arm(path: Path) -> dict[str, dict]:
    if not path.is_file():
        raise InputError(f"arm not found: {path}")
    rows: dict[str, dict] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise InputError(f"{path}:{number} is not JSON: {error}") from error
        if not isinstance(row, dict) or "record_id" not in row:
            raise InputError(f"{path}:{number} has no record_id")
        record_id = str(row["record_id"])
        if record_id in rows:
            raise InputError(f"{path}:{number} repeats record_id {record_id}: "
                             "a duplicated record would be counted twice")
        rows[record_id] = row
    if not rows:
        raise InputError(f"{path} carries no records")
    return rows


def metric_value(row: dict, metric: str):
    if metric == "passed":
        value = row.get("passed")
    else:
        metrics = row.get("metrics")
        if not isinstance(metrics, dict):
            raise InputError("row has no metrics object")
        value = metrics.get(metric)
    if value is None:
        return None
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return float(value)
    raise InputError(f"metric {metric!r} is not numeric (got {value!r})")


def paired(arm_a: dict, arm_b: dict, metric: str, clusters: dict) -> tuple[list[tuple[str, float, float]], int]:
    if set(arm_a) != set(arm_b):
        only_a = sorted(set(arm_a) - set(arm_b))[:5]
        only_b = sorted(set(arm_b) - set(arm_a))[:5]
        raise InputError("the two arms do not cover the same records "
                         f"(only in A: {only_a}; only in B: {only_b}); "
                         "pairing them would not be a paired comparison")
    pairs = []
    excluded = 0
    for record_id in sorted(arm_a):
        value_a = metric_value(arm_a[record_id], metric)
        value_b = metric_value(arm_b[record_id], metric)
        cluster = clusters.get(record_id)
        if value_a is None or value_b is None or cluster is None:
            excluded += 1
            continue
        pairs.append((str(cluster), value_a, value_b))
    return pairs, excluded


def build(pairs: list[tuple[str, float, float]], *, metric: str,
          safety_pairs: list[tuple[str, float, float]] | None,
          safety_direction: str = "lower_is_better") -> dict:
    # The gate resamples per cluster over `(a_hits, a_n, b_hits, b_n)`, so the
    # clusters are emitted as counts. A pair of cluster *means* would crash the
    # bootstrap instead of comparing anything (found by the integration test).
    by_cluster: dict[str, list[tuple[float, float]]] = {}
    for cluster, value_a, value_b in pairs:
        by_cluster.setdefault(cluster, []).append((value_a, value_b))
    clusters = [[sum(a for a, _ in rows), len(rows), sum(b for _, b in rows), len(rows)]
                for cluster, rows in sorted(by_cluster.items())]
    mean_a = sum(a for _, a, _ in pairs) / len(pairs)
    mean_b = sum(b for _, _, b in pairs) / len(pairs)
    values = [a for _, a, _ in pairs] + [b for _, _, b in pairs]
    metric_kind = "rate" if all(value in (0.0, 1.0) for value in values) else "mean"

    safety_not_worse = None
    if safety_pairs:
        safety_a = sum(a for _, a, _ in safety_pairs) / len(safety_pairs)
        safety_b = sum(b for _, _, b in safety_pairs) / len(safety_pairs)
        # The direction is the caller's explicit declaration, never assumed: a
        # hardcoded "lower is better" would silently invert a quality metric.
        if safety_direction == "lower_is_better":
            safety_not_worse = safety_a <= safety_b
        else:
            safety_not_worse = safety_a >= safety_b

    return {
        "metric": metric,
        # `rate` when every paired value is 0/1 (a pass rate); `mean` otherwise.
        # The gate resamples the ratio sum(hits)/sum(n), which for a mean metric is
        # a weighted mean - valid, but it must not be described as a pass rate.
        "metric_kind": metric_kind,
        "paired_records": len(pairs),
        "clusters": clusters,
        "cluster_count": len(clusters),
        "mean_arm_a": mean_a,
        "mean_arm_b": mean_b,
        "point_gain_pp": (mean_a - mean_b) * 100.0,
        "safety_not_worse": safety_not_worse,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arm-a", type=Path, required=True)
    parser.add_argument("--arm-b", type=Path, required=True)
    parser.add_argument("--arm-a-kind", required=True, choices=KNOWN_KINDS)
    parser.add_argument("--arm-b-kind", required=True, choices=KNOWN_KINDS)
    parser.add_argument("--clusters", type=Path, required=True,
                        help="JSON mapping record_id -> source-shoot/session cluster id")
    parser.add_argument("--metric", default="passed")
    parser.add_argument("--safety-metric",
                        help="metric compared for safety, e.g. forbidden_action_violation")
    parser.add_argument("--safety-direction", choices=("lower_is_better", "higher_is_better"),
                        default="lower_is_better",
                        help="how to read the safety metric; declared, not assumed")
    parser.add_argument("--subset", default="<set-by-caller>",
                        help="the pre-chosen pass/expected-action or protected semantic subset")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    try:
        arm_a = load_arm(args.arm_a)
        arm_b = load_arm(args.arm_b)
        raw_clusters = json.loads(args.clusters.read_text(encoding="utf-8"))
        if not isinstance(raw_clusters, dict):
            raise InputError("clusters must be a JSON object mapping record_id to cluster id")
        pairs, excluded = paired(arm_a, arm_b, args.metric, raw_clusters)
        safety_pairs = None
        if args.safety_metric:
            safety_pairs, _ = paired(arm_a, arm_b, args.safety_metric, raw_clusters)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    if not pairs:
        print("FAIL CLOSED: no record could be paired with a cluster", file=sys.stderr)
        return 1
    comparison = build(pairs, metric=args.metric, safety_pairs=safety_pairs,
                       safety_direction=args.safety_direction)
    if comparison["cluster_count"] < 2:
        print(f"FAIL CLOSED: {comparison['cluster_count']} cluster(s) is not independence; "
              "a paired bootstrap needs at least 2 source-shoot/session clusters", file=sys.stderr)
        return 1

    neural = {args.arm_a_kind, args.arm_b_kind} == {NEURAL_KIND, BASELINE_KIND}
    payload = {
        "schema_id": "camera-arm-comparison",
        "schema_version": "1.0.0",
        "arms": {
            "a": {"path": str(args.arm_a), "sha256": _sha256(args.arm_a), "kind": args.arm_a_kind},
            "b": {"path": str(args.arm_b), "sha256": _sha256(args.arm_b), "kind": args.arm_b_kind},
        },
        "comparison": comparison,
        "excluded_records": excluded,
        "emitted_neural_gain_block": neural,
        "safety_direction": args.safety_direction,
        "note": (
            "arms are declared neural vs deterministic_baseline, so this comparison may fill "
            "evaluation.neural_gain"
        ) if neural else (
            "arm kinds are not neural vs deterministic_baseline, so this comparison must NOT be "
            "reported as neural gain; the gate will find neural_gain not measurable"
        ),
    }
    if neural:
        payload["neural_gain_block"] = {
            "clusters": comparison["clusters"],
            "point_gain_pp": comparison["point_gain_pp"],
            "safety_not_worse": comparison["safety_not_worse"],
            "subset": args.subset,
        }

    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(text)
    print(f"COMPARISON metric={comparison['metric']} paired={comparison['paired_records']} "
          f"excluded={excluded} clusters={comparison['cluster_count']} "
          f"point_gain_pp={comparison['point_gain_pp']:.4f} neural_block={neural}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
