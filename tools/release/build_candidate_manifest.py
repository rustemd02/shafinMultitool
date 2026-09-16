#!/usr/bin/env python3
"""Assemble a candidate manifest from per-record evaluation rows.

M06 requires §5 metrics *with counts* for one exact candidate, and
`tools/release/check_candidate_gates.py` decides the release from a manifest that
carries those counts. Nothing produced such a manifest before: the aggregate
documents exist (`set_metrics.json`) but a manifest has to be assembled, and hand
assembling it is where a number gets typed instead of computed.

This tool recomputes the §5 quantities from the per-record rows that the replay
evaluator already writes (`case_results.jsonl`), and emits only the blocks those
rows can actually support. Everything it cannot compute from them is left out on
purpose: the gate then reports `not_measurable` for that row rather than reading a
plausible default.

Aggregation rules, derived by reproducing the historical `set_metrics.json` exactly
rather than asserted (see `tools/tests/test_candidate_manifest_builder.py`):

* `pass_rate`                 = mean(`passed`)
* `expected_action_hit`       = mean(`metrics.expected_action_hit`) over non-null
* `forbidden_violations_rate` = mean(`metrics.forbidden_action_violation`) over non-null
* `confidence_band_accuracy`  = mean(`metrics.confidence_band_match`) over non-null
* each metric keeps its own denominator: `good_frame_preserved` and
  `positive_confirmation` are null outside the good frames and are averaged over
  the frames that have them (68/81 and 65/81 on the historical artifact)
* `false_improved` and the confusion matrix need episode outcomes, which still rows
  do not carry, so they are not produced here

`--set-metrics` is the anti-drift check: when the evaluator's aggregate document is
supplied, the recomputation must match it exactly, otherwise the tool fails. That
is what keeps these definitions verifiable instead of asserted.

Exit codes
    0  a manifest was assembled and every supplied cross-check matched
    1  the recomputation disagrees with the supplied aggregate document
    2  an input is missing, unreadable, or carries no records

Usage
    python3 tools/release/build_candidate_manifest.py \\
        --case-results <scored/case_results.jsonl> \\
        --set-metrics <scored/set_metrics.json> \\
        --candidate-id <id> --clusters <record-to-cluster.json> --out candidate.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY = REPO_ROOT / "datasets/camera-coach/v1/evaluation-policy-v1.json"
KEEP_ACTION = "keep_current_setup"
GOOD_OVER_CORRECTION = "good_frame_overcorrection"

REQUIRED_ROW_KEYS = ("record_id", "quality_label", "passed", "metrics", "failures",
                     "candidate_actions", "expected_actions")

METRIC_KEYS = {
    "expected_action_hit": "expected_action_hit",
    "forbidden_action_violation": "forbidden_violations_rate",
    "confidence_band_match": "confidence_band_accuracy",
    "good_frame_preserved": "good_frame_preservation_rate",
    "positive_confirmation": "positive_confirmation_rate",
}


class InputError(Exception):
    pass


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_rows(path: Path) -> list[dict]:
    if not path.is_file():
        raise InputError(f"case-results not found: {path}")
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise InputError(f"{path}:{number} is not JSON: {error}") from error
        if not isinstance(row, dict):
            raise InputError(f"{path}:{number} is not an object")
        missing = [key for key in REQUIRED_ROW_KEYS if key not in row]
        if missing:
            raise InputError(f"{path}:{number} lacks {missing}")
        if not isinstance(row["metrics"], dict):
            raise InputError(f"{path}:{number} metrics is not an object")
        rows.append(row)
    if not rows:
        raise InputError(f"{path} carries no records: an empty evaluation is not a result")
    return rows


def _mean(values: list) -> float | None:
    usable = [value for value in values if value is not None]
    if not usable:
        return None
    return sum(usable) / len(usable)


def aggregate(rows: list[dict]) -> dict:
    # A metric key that exists in no row means the row schema moved; averaging it
    # would quietly produce None and read as "no data" instead of "wrong name".
    present = {key for row in rows for key in row["metrics"]}
    absent = sorted(source for source in METRIC_KEYS if source not in present)
    if absent:
        raise InputError(f"metric key(s) absent from every row: {absent}; the row schema may have changed")

    metrics = {name: _mean([row["metrics"].get(key) for row in rows])
               for key, name in METRIC_KEYS.items()}
    failure_counts = Counter(failure for row in rows for failure in row["failures"])
    good = [row for row in rows if row["quality_label"] == "good"]
    over_corrected = [row for row in good if GOOD_OVER_CORRECTION in row["failures"]]
    keeps = [row for row in rows if list(row["candidate_actions"]) == [KEEP_ACTION]]
    return {
        "record_count": len(rows),
        "pass_rate": _mean([1.0 if row["passed"] else 0.0 for row in rows]),
        "expected_action_hit": metrics["expected_action_hit"],
        "forbidden_violations_rate": metrics["forbidden_violations_rate"],
        "confidence_band_accuracy": metrics["confidence_band_accuracy"],
        "good_frame_preservation_rate": metrics["good_frame_preservation_rate"],
        "positive_confirmation_rate": metrics["positive_confirmation_rate"],
        "failure_counts": dict(sorted(failure_counts.items())),
        "good_frames_evaluated": len(good),
        "good_frames_overcorrected": len(over_corrected),
        "keep_rate": (len(keeps) / len(rows)) if rows else None,
        "quality_labels": dict(sorted(Counter(row["quality_label"] for row in rows).items())),
    }


def cross_check(recomputed: dict, aggregate_path: Path) -> list[str]:
    try:
        document = json.loads(aggregate_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"set-metrics is unreadable: {error}") from error
    reported = document.get("set_metrics") if isinstance(document, dict) else None
    if not isinstance(reported, dict):
        raise InputError("set-metrics has no set_metrics object")

    mismatches = []
    for key in ("record_count", "pass_rate", "expected_action_hit", "forbidden_action_violation_rate",
                "confidence_band_accuracy", "good_frame_preservation_rate",
                "positive_confirmation_rate"):
        if key not in reported:
            continue
        ours = recomputed.get(key)
        if key == "forbidden_action_violation_rate":
            ours = recomputed.get("forbidden_violations_rate")
        # the aggregate document rounds to six decimals; compare at that granularity
        if ours is None or abs(ours - reported[key]) > 5e-7:
            mismatches.append(f"{key}: recomputed={ours} reported={reported[key]}")
    if "failure_counts" in reported and recomputed["failure_counts"] != reported["failure_counts"]:
        mismatches.append(f"failure_counts: recomputed={recomputed['failure_counts']} "
                          f"reported={reported['failure_counts']}")
    return mismatches


def load_neural_gain(path: Path) -> dict:
    """Accept an arm comparison only when it is declared neural vs baseline."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"neural-gain comparison is unreadable: {error}") from error
    if not isinstance(payload, dict) or "comparison" not in payload:
        raise InputError("neural-gain comparison has no comparison block")
    if payload.get("emitted_neural_gain_block") is not True:
        kinds = {arm.get("kind") for arm in (payload.get("arms") or {}).values()}
        raise InputError(f"the comparison's arms are declared {sorted(k for k in kinds if k)}; "
                         "only a neural versus deterministic_baseline comparison may fill "
                         "evaluation.neural_gain")
    block = payload.get("neural_gain_block")
    if not isinstance(block, dict):
        raise InputError("the comparison declares a neural block but carries none")
    return {"block": block, "arms": payload.get("arms"), "metric": payload["comparison"].get("metric"),
            "metric_kind": payload["comparison"].get("metric_kind"),
            "excluded_records": payload.get("excluded_records")}


def load_episode_blocks(path: Path) -> dict:
    """Accept blocks produced by tools/release/build_episode_metrics.py."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"episode blocks are unreadable: {error}") from error
    if not isinstance(payload, dict) or "confusion" not in payload or "false_improved" not in payload:
        raise InputError("episode blocks carry no confusion/false_improved pair")
    return {"confusion": payload["confusion"], "false_improved": payload["false_improved"],
            "per_action_counts": payload.get("per_action_counts"),
            "source": payload.get("source"), "definitions": payload.get("definitions"),
            "cluster_count": payload.get("cluster_count")}


def load_derived_block(path: Path, key: str, name: str) -> dict:
    """Read a block produced by another tool (human report, gold report)."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"{name} is unreadable: {error}") from error
    block = payload.get(key) if isinstance(payload, dict) else None
    if not isinstance(block, dict) or not block:
        raise InputError(f"{name} carries no {key} block")
    return block


def build_manifest(rows: list[dict], recomputed: dict, *, candidate_id: str,
                   contract_version: str, evaluated_split: str,
                   clusters: dict | None, case_results_path: Path,
                   policy_path: Path, neural_gain: dict | None = None,
                   episode_blocks: dict | None = None, human: dict | None = None,
                   gold: dict | None = None) -> dict:
    good = recomputed["good_frames_evaluated"]
    if not good:
        raise InputError("no good frames are present: FP_CORRECT has no denominator and must not be claimed")

    cluster_ids = None
    if clusters is not None:
        cluster_ids = {clusters.get(row["record_id"]) for row in rows if row["quality_label"] == "good"}
        cluster_ids.discard(None)

    return {
        "candidate_id": candidate_id,
        "contract_version": contract_version,
        "evaluated_split": evaluated_split,
        "evaluation": {
            "fp_correct": {
                "good_frames_with_forbidden_correction": recomputed["good_frames_overcorrected"],
                "good_frames_evaluated": good,
                "keep_rate": recomputed["keep_rate"],
                "abstain_rate": None,
                # §5.1 independence: the budget is claimed over source-shoot/session
                # clusters, never over near-identical adjacent frames. Without a
                # cluster mapping this stays null and the gate must not pass it.
                "cluster_count": len(cluster_ids) if cluster_ids else None,
            },
            "rate_table": {
                "pass_rate": recomputed["pass_rate"],
                "expected_action_hit": recomputed["expected_action_hit"],
                "forbidden_violations_rate": recomputed["forbidden_violations_rate"],
                "confidence_band_accuracy": recomputed["confidence_band_accuracy"],
            },
        },
        "provenance": {
            "schema_id": "camera-candidate-manifest",
            "schema_version": "1.0.0",
            "built_by": "tools/release/build_candidate_manifest.py",
            "case_results": {"path": str(case_results_path), "sha256": _sha256(case_results_path)},
            "evaluation_policy": {
                "path": str(policy_path),
                "sha256": _sha256(policy_path),
                "policy_version": json.loads(policy_path.read_text(encoding="utf-8")).get("policy_version"),
            },
            "aggregation_rules": {
                "mean": "arithmetic mean over records that carry a value for that metric; a metric's nulls are its own denominator",
                "pass_rate": "mean(passed)",
                "failure_counts": "count of each name in the per-record failures list",
                "good_frames": "records with quality_label == 'good'",
                "forbidden_correction_on_good_frame": f"'{GOOD_OVER_CORRECTION}' in a good frame's failures",
                "keep_rate": f"share of records whose candidate_actions == ['{KEEP_ACTION}']",
            },
            "clusters_supplied": clusters is not None,
            "not_produced_here": [
                "evaluation.false_improved (needs episode outcomes, which still rows do not carry)",
                "evaluation.confusion (same)",
                "evaluation.human, evaluation.neural_gain, gold, quotas, per_class/action floors, splits, weight_lineage",
                "direction/light precision and coverage rows (no hits/denominators in still replay rows)",
            ],
            "recomputed_aggregates": recomputed,
            "episode_blocks_source": None if episode_blocks is None else {
                "source": episode_blocks["source"],
                "definitions": episode_blocks["definitions"],
                "cluster_count": episode_blocks["cluster_count"],
            },
            "rows_seen": len(rows),
            "neural_gain_source": None if neural_gain is None else {
                "arms": neural_gain["arms"],
                "metric": neural_gain["metric"],
                "metric_kind": neural_gain["metric_kind"],
                "excluded_records": neural_gain["excluded_records"],
            },
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case-results", type=Path, required=True)
    parser.add_argument("--set-metrics", type=Path,
                        help="the evaluator's aggregate document; the recomputation must match it exactly")
    parser.add_argument("--candidate-id", required=True)
    parser.add_argument("--contract-version", default="<set-by-caller>")
    parser.add_argument("--evaluated-split", default="locked")
    parser.add_argument("--clusters", type=Path,
                        help="JSON mapping record_id -> source-shoot/session cluster id")
    parser.add_argument("--human-report", type=Path,
                        help="output of tools/release/build_human_report.py")
    parser.add_argument("--gold-report", type=Path,
                        help="output of tools/release/build_gold_report.py")
    parser.add_argument("--episode-blocks", type=Path,
                        help="output of tools/release/build_episode_metrics.py: confusion and "
                             "false_improved")
    parser.add_argument("--neural-gain", type=Path,
                        help="output of tools/release/compare_arms.py; only accepted when its arms "
                             "are declared neural versus deterministic_baseline")
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    if args.evaluated_split != "locked":
        print(f"FAIL CLOSED: M06 evaluates the locked split, not {args.evaluated_split!r}", file=sys.stderr)
        return 2
    if not args.policy.is_file():
        print(f"FAIL CLOSED: the frozen evaluation policy is missing: {args.policy}", file=sys.stderr)
        return 2

    try:
        rows = load_rows(args.case_results)
        recomputed = aggregate(rows)
        clusters = None
        if args.clusters is not None:
            clusters = json.loads(args.clusters.read_text(encoding="utf-8"))
            if not isinstance(clusters, dict):
                raise InputError("clusters must be a JSON object mapping record_id to cluster id")
        mismatches = cross_check(recomputed, args.set_metrics) if args.set_metrics else []
        neural_gain = load_neural_gain(args.neural_gain) if args.neural_gain else None
        episode_blocks = load_episode_blocks(args.episode_blocks) if args.episode_blocks else None
        human = load_derived_block(args.human_report, "human", "human report") \
            if args.human_report else None
        gold = load_derived_block(args.gold_report, "gold", "gold report") if args.gold_report else None
        manifest = build_manifest(rows, recomputed, candidate_id=args.candidate_id,
                                  contract_version=args.contract_version,
                                  evaluated_split=args.evaluated_split, clusters=clusters,
                                  case_results_path=args.case_results, policy_path=args.policy,
                                  neural_gain=neural_gain)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    if mismatches:
        print("FAIL: the recomputation disagrees with the evaluator's aggregate document:", file=sys.stderr)
        for mismatch in mismatches:
            print(f"  - {mismatch}", file=sys.stderr)
        return 1

    if human is not None:
        manifest["evaluation"]["human"] = human
    if gold is not None:
        # the gate lives on the top-level gold block, not under evaluation
        manifest["gold"] = gold

    if episode_blocks is not None:
        manifest["provenance"]["episode_blocks_source"] = {
            "source": episode_blocks["source"],
            "definitions": episode_blocks["definitions"],
            "cluster_count": episode_blocks["cluster_count"],
        }
        manifest["evaluation"]["confusion"] = episode_blocks["confusion"]
        manifest["evaluation"]["false_improved"] = episode_blocks["false_improved"]
        if episode_blocks["per_action_counts"]:
            manifest["per_action_counts"] = episode_blocks["per_action_counts"]
        manifest["provenance"]["not_produced_here"] = [
            item for item in manifest["provenance"]["not_produced_here"]
            if "false_improved" not in item and "confusion" not in item
        ]

    if neural_gain is not None:
        manifest["evaluation"]["neural_gain"] = neural_gain["block"]
        manifest["provenance"]["not_produced_here"] = [
            item for item in manifest["provenance"]["not_produced_here"]
            if not item.startswith("evaluation.human") and "neural_gain" not in item
        ] + ["evaluation.human, gold, quotas, per_class/action floors, splits, weight_lineage "
             "(still not produced here)"]

    text = json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(text)

    fp = manifest["evaluation"]["fp_correct"]
    print(f"MANIFEST {args.candidate_id}: records={recomputed['record_count']} "
          f"good_frames={fp['good_frames_evaluated']} "
          f"overcorrected={fp['good_frames_with_forbidden_correction']} "
          f"clusters={fp['cluster_count']}")
    print("NOT PRODUCED HERE (the gate will report them not_measurable): "
          + "; ".join(manifest["provenance"]["not_produced_here"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
