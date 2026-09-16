#!/usr/bin/env python3
"""Candidate gate evaluator for the SET OS release (runbook §5).

This is the tool that decides whether a *candidate* may be called release-ready.
It computes every statistic itself from raw counts / per-cluster records in the
candidate manifest — it never trusts a claimed number — and fails closed:
a missing or unmeasurable gate is `not_provided` / `not_measurable`, never a
pass.

Gate states
    pass               the computed statistic meets the gate
    fail               the computed statistic violates the gate
    insufficient_evidence  the data cannot support the claim (e.g. the one-sided
                       95% upper bound of FP_CORRECT is still above 2%)
    not_measurable     the manifest lacks the records the gate needs
    not_provided       the manifest does not mention the gate at all

Exit code is 0 only when every mandatory gate is `pass`.

Usage
    python3 tools/release/check_candidate_gates.py --manifest <candidate.json>
    python3 tools/release/check_candidate_gates.py --template   # print a skeleton
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import sys
from pathlib import Path

Z_TWO_SIDED_95 = 1.959963984540054
BOOTSTRAP_SAMPLES = 10_000
BOOTSTRAP_SEED = 20260913

# runbook §5.2 quotas (independent slices, not a sum of downloaded files)
QUOTAS = {
    "train_candidates": 8_400,
    "validation_stills": 1_400,
    "calibration_stills": 1_400,
    "locked_stills": 1_400,
    "live_sequences": 1_400,
    "episodes": 700,
    "protected_negatives": 350,
    "physical_guided": 210,
    "blind_reviews": 350 * 3,
}
PER_CLASS_FLOORS = {
    "train": 1_200, "calibration": 200, "locked_stills": 200,
    "sequences": 200, "episodes": 100, "protected_negatives": 50, "physical_guided": 30,
}
PER_ACTION_FLOORS = {
    "train_positives": 400, "calibration": 100, "test": 100,
    "forbidden_opportunities": 120, "near_threshold": 30,
}
EPISODE_FLOORS = {"improved": 80, "unchanged_or_worse": 40, "incomparable": 20}
GOLD_FLOORS = {
    "annotators": 2, "hidden_qc_rate": 0.05, "adjudicated_review_rate": 0.10,
    "kappa_keep_correct_abstain": 0.80, "kappa_action_family": 0.75,
    "forbidden_agreement": 0.90, "median_roi_iou": 0.80, "hidden_qc": 0.95,
}
FP_CORRECT_BUDGET = 0.02
# §5.1: the budget is claimed over source-shoot/session clusters, so a single
# shoot cannot supply the independence the claim needs.
FP_CORRECT_MIN_CLUSTERS = 2
NEURAL_GAIN_PP = 0.05


# --------------------------------------------------------------------------- maths
def _binomial_tail(k: int, n: int, p: float) -> float:
    """P(X <= k) for X ~ Binomial(n, p), evaluated in log space.

    `math.comb(n, i) * p**i * (1-p)**(n-i)` overflows for realistic n (a few
    thousand): comb returns an astronomically large int and the powers underflow
    to zero, so the product cannot be converted to float. Log-gamma keeps every
    term in a workable range.
    """
    if p <= 0.0:
        return 1.0
    if p >= 1.0:
        return 0.0
    log_p, log_q = math.log(p), math.log1p(-p)
    total = 0.0
    for i in range(k + 1):
        total += math.exp(math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1)
                          + i * log_p + (n - i) * log_q)
    return min(1.0, total)


def clopper_pearson_upper(k: int, n: int, alpha: float = 0.05) -> float:
    """One-sided 1-alpha upper bound for a binomial proportion (exact)."""
    if n <= 0:
        raise ValueError("n must be positive")
    if k < 0 or k > n:
        raise ValueError("k must be in [0, n]")
    if k == n:
        return 1.0
    if k == 0:
        return 1.0 - alpha ** (1.0 / n)
    # solve P(X <= k) = alpha by bisection on p
    lo, hi = k / n, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if _binomial_tail(k, n, mid) > alpha:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def wilson_lower(k: int, n: int, z: float = Z_TWO_SIDED_95) -> float:
    """Lower bound of the Wilson score interval (95%)."""
    if n <= 0:
        raise ValueError("n must be positive")
    p = k / n
    denom = 1.0 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = (z / denom) * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return max(0.0, centre - half)


def paired_bootstrap_lower(pairs: list[tuple[int, int, int, int]]) -> float | None:
    """5th percentile of (neural - baseline) pass-rate over source-shoot clusters.

    pairs: (neural_hits, neural_n, baseline_hits, baseline_n) per cluster.
    Resampling is over clusters, so near-duplicate frames in one shoot cannot
    inflate the evidence.
    """
    usable = [(a, b, c, d) for a, b, c, d in pairs if b > 0 and d > 0]
    if len(usable) < 2:
        return None
    rng = random.Random(BOOTSTRAP_SEED)
    deltas = []
    for _ in range(BOOTSTRAP_SAMPLES):
        sample = [usable[rng.randrange(len(usable))] for _ in usable]
        neural = sum(a for a, _, _, _ in sample) / sum(b for _, b, _, _ in sample)
        baseline = sum(c for _, _, c, _ in sample) / sum(d for _, _, _, d in sample)
        deltas.append(neural - baseline)
    deltas.sort()
    return deltas[int(0.05 * len(deltas))]


# --------------------------------------------------------------------------- gates
class Gate:
    def __init__(self, name: str, mandatory: bool = True):
        self.name = name
        self.mandatory = mandatory
        self.state = "not_provided"
        self.detail = ""
        self.observed: dict = {}

    def set(self, state: str, detail: str, **observed) -> "Gate":
        self.state = state
        self.detail = detail
        # merge: callers record the computed statistics before deciding the state,
        # and a verdict must never erase the numbers it was derived from
        self.observed.update(observed)
        return self


def _ratio_gate(name: str, value, threshold: float, *, at_least: bool = True,
                upper: bool = False) -> Gate:
    gate = Gate(name)
    if value is None:
        return gate.set("not_measurable", f"{name}: no data in the manifest")
    ok = value >= threshold if at_least else value <= threshold
    gate.observed = {"value": value, "threshold": threshold}
    return gate.set("pass" if ok else "fail",
                    f"{name}={value:.4f} vs {'>=' if at_least else '<='}{threshold}")


def _wilson_gate(name: str, k, n, point_threshold: float, lower_threshold: float) -> Gate:
    gate = Gate(name)
    if k is None or not n:
        return gate.set("not_measurable", f"{name}: need hits and denominator")
    point = k / n
    lower = wilson_lower(k, n)
    gate.observed = {"k": k, "n": n, "point": point, "wilson_lower": lower}
    if point < point_threshold:
        return gate.set("fail", f"{name} point={point:.4f} < {point_threshold}")
    if lower < lower_threshold:
        return gate.set("insufficient_evidence",
                        f"{name} Wilson lower={lower:.4f} < {lower_threshold} (point={point:.4f})")
    return gate.set("pass", f"{name} point={point:.4f}, Wilson lower={lower:.4f}")


def evaluate(manifest: dict) -> list[Gate]:
    gates: list[Gate] = []
    ev = manifest.get("evaluation") or {}

    # --- FP_CORRECT on good frames, with the exact one-sided upper bound ---
    fp = ev.get("fp_correct")
    gate = Gate("fp_correct_on_good_frames")
    if not fp:
        gate.set("not_measurable", "no fp_correct block: the budget claim cannot be made")
    else:
        bad, good = fp.get("good_frames_with_forbidden_correction"), fp.get("good_frames_evaluated")
        clusters = fp.get("cluster_count")
        if not good:
            gate.set("not_measurable", "fp_correct has no denominator")
        elif not isinstance(clusters, int) or clusters < FP_CORRECT_MIN_CLUSTERS:
            # §5.1: independence is counted over source-shoot/session clusters, not
            # over a hundred near-identical adjacent frames. Without that count the
            # budget cannot be claimed, however good the point estimate looks.
            gate.set("not_measurable",
                     f"fp_correct needs a source-shoot/session cluster count "
                     f">= {FP_CORRECT_MIN_CLUSTERS} (got {clusters!r})")
        elif fp.get("keep_rate") == 1.0 or fp.get("abstain_rate") == 1.0:
            gate.set("fail", "KEEP/ABSTAIN is everything: all-silence cannot pass the gate",
                     keep_rate=fp.get("keep_rate"), abstain_rate=fp.get("abstain_rate"))
        else:
            point = bad / good
            upper = clopper_pearson_upper(bad, good)
            gate.observed = {"bad": bad, "good": good, "point": point, "upper_95": upper,
                             "cluster_count": clusters,
                             "keep_rate": fp.get("keep_rate"), "abstain_rate": fp.get("abstain_rate")}
            if point > FP_CORRECT_BUDGET:
                gate.set("fail", f"point={point:.4%} exceeds the {FP_CORRECT_BUDGET:.0%} budget")
            elif upper > FP_CORRECT_BUDGET:
                gate.set("insufficient_evidence",
                         f"point={point:.4%} but the one-sided 95% upper bound {upper:.4%} > {FP_CORRECT_BUDGET:.0%}")
            else:
                gate.set("pass", f"point={point:.4%}, upper 95% = {upper:.4%}")
    gates.append(gate)

    # --- the remaining §9.6 table ---
    table = ev.get("rate_table") or {}
    gates.append(_ratio_gate("pass_rate", table.get("pass_rate"), 0.90))
    gates.append(_ratio_gate("expected_action_hit", table.get("expected_action_hit"), 0.90))
    gates.append(_ratio_gate("forbidden_violations", table.get("forbidden_violations_rate"), 0.02, at_least=False))
    critical = table.get("critical_forbidden_observed")
    gate = Gate("critical_forbidden")
    if critical is None:
        gate.set("not_measurable", "critical_forbidden_observed is absent")
    else:
        gate.observed = {"observed": critical}
        gate.set("pass" if critical == 0 else "fail", f"observed critical forbidden cases: {critical}")
    gates.append(gate)
    gates.append(_ratio_gate("technical_failure", table.get("technical_failure_pass_rate"), 1.0))
    gates.append(_ratio_gate("scene_class_min", table.get("scene_class_min"), 0.85))
    gates.append(_ratio_gate("material_organic_source_min", table.get("material_organic_source_min"), 0.80))
    gates.append(_ratio_gate("synthetic_adversarial", table.get("synthetic_adversarial"), 0.65))
    gates.append(_ratio_gate("confidence_band_accuracy", table.get("confidence_band_accuracy"), 0.90))
    gates.append(_ratio_gate("abstention_correctness", table.get("abstention_correctness"), 0.90))
    gates.append(_ratio_gate("verification_accuracy", table.get("verification_accuracy"), 0.90))
    gates.append(_wilson_gate("direction_horizon_precision",
                              table.get("direction_horizon_hits"), table.get("direction_horizon_n"), 0.95, 0.90))
    gates.append(_wilson_gate("light_exposure_precision",
                              table.get("light_exposure_hits"), table.get("light_exposure_n"), 0.92, 0.87))
    gates.append(_ratio_gate("accepted_coverage_overall", table.get("accepted_coverage_overall"), 0.65))
    gates.append(_ratio_gate("accepted_coverage_ordinary", table.get("accepted_coverage_ordinary"), 0.55))
    gates.append(_ratio_gate("accepted_coverage_difficult_light", table.get("accepted_coverage_difficult_light"), 0.35))

    # wrong-direction / wrong-target false success must be zero in mandatory safety cases
    for name in ("wrong_direction_false_success", "wrong_target_false_success"):
        value = table.get(name)
        gate = Gate(name)
        if value is None:
            gate.set("not_measurable", f"{name} is absent")
        else:
            gate.observed = {"observed": value}
            gate.set("pass" if value == 0 else "fail", f"{name}={value} (must be 0)")
        gates.append(gate)

    # false improved: both denominators, and precision is undefined at zero issued
    fi = ev.get("false_improved") or {}
    gate = Gate("false_improved")
    confusion = ev.get("confusion") or {}
    if not fi:
        gate.set("not_measurable", "no false_improved block")
    else:
        wrong_over_issued = fi.get("wrong_confirmations"), fi.get("improved_issued")
        wrong_over_non = fi.get("wrong_improved"), fi.get("non_improved_episodes")
        if not wrong_over_issued[1]:
            gate.set("fail", "no improved episode was issued: precision is undefined and coverage is not passed")
        else:
            rate_issued = wrong_over_issued[0] / wrong_over_issued[1]
            rate_non = (wrong_over_non[0] / wrong_over_non[1]) if wrong_over_non[1] else None
            gate.observed = {"wrong_over_issued": rate_issued, "wrong_over_non_improved": rate_non}
            if rate_issued > 0.02:
                gate.set("fail", f"wrong/issued={rate_issued:.4f} > 0.02")
            else:
                gate.set("pass" if rate_non is not None else "insufficient_evidence",
                         f"wrong/issued={rate_issued:.4f}, wrong/non-improved={rate_non}")
    gates.append(gate)

    # --- the confusion matrix must be explicit and must add up (no self-reported flag) ---
    gate = Gate("confusion_matrix_integrity")
    required_keys = {"correct", "keep", "abstain", "incomparable", "forbidden_advised"}
    if not confusion:
        gate.set("not_provided", "no confusion block: the counts behind the rates cannot be checked")
    else:
        missing = sorted(required_keys - set(confusion))
        total = confusion.get("evaluated_total")
        counted = sum(v for k, v in confusion.items() if k != "evaluated_total" and isinstance(v, int))
        gate.observed = {"counts": {k: confusion.get(k) for k in sorted(required_keys)},
                         "counted": counted, "evaluated_total": total}
        if missing:
            gate.set("fail", f"confusion keys missing (incomparable must not be dropped): {missing}")
        elif not total:
            gate.set("not_measurable", "confusion.evaluated_total is absent")
        elif counted != total:
            gate.set("fail", f"confusion counts sum to {counted} but evaluated_total={total}")
        else:
            gate.set("pass", f"counts add up to {total}; incomparable={confusion.get('incomparable')} kept in the matrix")
    gates.append(gate)

    # --- human gates ---
    human = ev.get("human") or {}
    gates.append(_ratio_gate("human_safe_executable", human.get("safe_and_executable"), 0.90))
    gates.append(_ratio_gate("human_helpful", human.get("helpful"), 0.80))
    gates.append(_ratio_gate("human_preference_non_ties", human.get("preference_non_ties"), 0.60))
    gates.append(_ratio_gate("human_materially_harmful", human.get("materially_harmful"), 0.01, at_least=False))
    critical_harm = human.get("critical_harm")
    gate = Gate("human_critical_harm")
    if critical_harm is None:
        gate.set("not_measurable", "human.critical_harm is absent")
    else:
        gate.observed = {"observed": critical_harm}
        gate.set("pass" if critical_harm == 0 else "fail", f"critical harm={critical_harm} (must be 0)")
    gates.append(gate)

    # --- neural must beat the deterministic baseline, paired by source-shoot ---
    gain = ev.get("neural_gain") or {}
    gate = Gate("neural_gain_over_baseline")
    if not gain:
        gate.set("not_measurable", "no neural_gain block: no paired comparison exists")
    else:
        pairs = [tuple(p) for p in gain.get("clusters", [])]
        lower = paired_bootstrap_lower(pairs)
        safety_ok = gain.get("safety_not_worse")
        if lower is None:
            gate.set("not_measurable", "fewer than 2 usable source-shoot clusters")
        elif safety_ok is False:
            gate.set("fail", "safety degraded against the baseline")
        else:
            delta = lower
            gate.observed = {"bootstrap_lower": delta, "clusters": len(pairs), "subset": gain.get("subset")}
            if delta <= 0:
                gate.set("fail", f"paired bootstrap lower bound {delta:.4f} is not > 0")
            elif gain.get("point_gain_pp", 0) < NEURAL_GAIN_PP * 100:
                gate.set("insufficient_evidence",
                         f"point gain {gain.get('point_gain_pp')} pp < {NEURAL_GAIN_PP * 100:.0f} pp")
            else:
                gate.set("pass", f"paired bootstrap lower={delta:.4f} > 0, point gain={gain.get('point_gain_pp')} pp")
    gates.append(gate)

    # --- trained heads must be backed by training evidence ---
    gate = Gate("trained_heads_backed_by_evidence")
    claims = manifest.get("trained_heads") or {}
    evidence = manifest.get("training_evidence") or {}
    contract = list(manifest.get("contract_heads") or [])
    mask = manifest.get("untrained_head_mask")
    untrained = sorted(set(contract) - set(claims))
    if not claims:
        gate.set("not_provided", "trained_heads is absent")
    else:
        problems = []
        unsupported = sorted(h for h in claims if not evidence.get(h))
        if unsupported:
            problems.append(f"heads claimed trained without training evidence: {unsupported}")
        if not contract:
            # without the contract head list there is no way to tell which heads are
            # allowed to stay untrained, so nothing can be checked
            problems.append("contract_heads is absent: which heads the contract requires is unstated")
        elif untrained:
            # The objective forbids reading "three trained heads" as "the rest are trained
            # too": an untrained contract head may ship only when the frozen policy's
            # trained-head mask explicitly allows it.
            if mask is None:
                problems.append(f"contract heads are untrained and no untrained_head_mask was "
                                f"declared: {untrained}")
            elif not isinstance(mask, list):
                problems.append("untrained_head_mask must be a list of head names")
            else:
                undeclared = sorted(set(untrained) - set(mask))
                if undeclared:
                    problems.append(f"untrained contract heads outside the declared mask: {undeclared}")
                contradictory = sorted(set(mask) & set(claims))
                if contradictory:
                    problems.append(f"untrained_head_mask lists heads that are claimed trained: "
                                    f"{contradictory}")
        elif mask:
            problems.append(f"untrained_head_mask is declared but every contract head is trained: "
                            f"{sorted(mask)}")
        gate.observed = {"trained_heads": sorted(claims), "contract_heads": sorted(contract),
                         "untrained": untrained, "mask": mask}
        gate.set("pass" if not problems else "fail",
                 f"trained={sorted(claims)} untrained={untrained} "
                 f"mask={sorted(mask) if isinstance(mask, list) else mask}"
                 if not problems else "; ".join(problems))
    gates.append(gate)

    # --- splits must be disjoint; the evaluation must be on the locked split ---
    gate = Gate("split_disjointness")
    required_splits = ("train", "validation", "calibration", "locked")
    splits = manifest.get("splits") or {}
    hashes = {name: block.get("manifest_sha256") for name, block in splits.items() if isinstance(block, dict)}
    # A split that is absent or blank is not a satisfied split. Without this, an
    # empty `splits` block trivially satisfied "all hashes are distinct" and the
    # gate guarding against fitting on test passed on no evidence at all.
    unproven = sorted({name for name in required_splits if not hashes.get(name)}
                      | {name for name, value in hashes.items() if not value})
    duplicated = sorted({h for h in hashes.values() if h and list(hashes.values()).count(h) > 1})
    eval_split = manifest.get("evaluated_split")
    gate.observed = {"splits": hashes, "evaluated_split": eval_split}
    if unproven:
        gate.set("not_measurable", f"splits without a manifest hash: {unproven}")
    elif duplicated:
        gate.set("fail", f"split manifests reuse the same hash: {duplicated}")
    elif eval_split != "locked":
        gate.set("fail", f"evaluation ran on {eval_split!r}, not on the locked split")
    else:
        gate.set("pass", "all four split manifests are present, distinct, and the evaluation is on the locked split")
    gates.append(gate)

    # --- quotas and floors ---
    quotas = manifest.get("quota_counts") or {}
    gate = Gate("quotas")
    if not quotas:
        gate.set("not_provided", "quota_counts is absent")
    else:
        short = {k: (quotas.get(k, 0), v) for k, v in QUOTAS.items() if quotas.get(k, 0) < v}
        gate.observed = {"short": short}
        gate.set("pass" if not short else "fail",
                 "every quota slice met" if not short else f"below quota: {short}")
    gates.append(gate)

    gate = Gate("per_class_floors")
    per_class = manifest.get("per_class_counts") or {}
    if not per_class:
        gate.set("not_provided", "per_class_counts is absent")
    else:
        short = {}
        for klass, counts in per_class.items():
            for name, floor in PER_CLASS_FLOORS.items():
                if counts.get(name, 0) < floor:
                    short[f"{klass}.{name}"] = counts.get(name, 0)
        gate.observed = {"classes": len(per_class), "short": short}
        gate.set("pass" if not short else "fail", "floors met" if not short else f"below floors: {short}")
    gates.append(gate)

    gate = Gate("per_action_floors")
    per_action = manifest.get("per_action_counts") or {}
    if not per_action:
        gate.set("not_provided", "per_action_counts is absent")
    else:
        short = {}
        for action, counts in per_action.items():
            for name, floor in PER_ACTION_FLOORS.items():
                if counts.get(name, 0) < floor:
                    short[f"{action}.{name}"] = counts.get(name, 0)
            episode = counts.get("episodes") or {}
            for name, floor in EPISODE_FLOORS.items():
                if episode.get(name, 0) < floor:
                    short[f"{action}.episodes.{name}"] = episode.get(name, 0)
        gate.observed = {"actions": len(per_action), "short": short}
        gate.set("pass" if not short else "fail", "floors met" if not short else f"below floors: {short}")
    gates.append(gate)

    # --- gold ---
    gold = manifest.get("gold") or {}
    gate = Gate("gold_independence_and_kappa")
    if not gold:
        gate.set("not_provided", "gold block is absent")
    else:
        problems = []
        if gold.get("annotators", 0) < GOLD_FLOORS["annotators"]:
            problems.append(f"annotators={gold.get('annotators')} (<{GOLD_FLOORS['annotators']})")
        # These two facts cannot be read off the vote store, so they are
        # declarations — and an undeclared fact is treated like a violated one.
        # Otherwise a manifest could clear M3-022 by leaving the field out, which
        # is exactly the "PASS by omission" the owner forbids.
        if gold.get("annotators_are_distinct_humans") is not True:
            problems.append(
                "annotators_are_distinct_humans must be declared true "
                f"(got {gold.get('annotators_are_distinct_humans')!r})")
        if gold.get("ai_suggestions_in_independent_pass") is not False:
            problems.append(
                "ai_suggestions_in_independent_pass must be declared false "
                f"(got {gold.get('ai_suggestions_in_independent_pass')!r})")
        for key in ("kappa_keep_correct_abstain", "kappa_action_family", "forbidden_agreement",
                    "median_roi_iou", "hidden_qc"):
            value = gold.get(key)
            if value is None:
                problems.append(f"{key} missing")
            elif value < GOLD_FLOORS[key]:
                problems.append(f"{key}={value} (<{GOLD_FLOORS[key]})")
        for key in ("hidden_qc_rate", "adjudicated_review_rate"):
            value = gold.get(key)
            if value is None or value < GOLD_FLOORS[key]:
                problems.append(f"{key}={value} (<{GOLD_FLOORS[key]})")
        gate.observed = {k: gold.get(k) for k in
                         ("annotators", "annotators_are_distinct_humans",
                          "ai_suggestions_in_independent_pass",
                          "kappa_keep_correct_abstain", "kappa_action_family",
                          "forbidden_agreement", "median_roi_iou", "hidden_qc")}
        gate.set("pass" if not problems else "fail", "gold gates met" if not problems else "; ".join(problems))
    gates.append(gate)

    # --- weight provenance: credits do not clear research-only weights for the App Store ---
    gate = Gate("weight_lineage_release_cleared")
    lineage = manifest.get("weight_lineage") or []
    evidence_artifacts = set()
    for entry in (evidence := manifest.get("training_evidence") or {}).values():
        if isinstance(entry, dict) and entry.get("artifact"):
            evidence_artifacts.add(entry["artifact"])
    if not lineage:
        gate.set("not_provided", "no weight_lineage block: provenance of the shipped weights is unstated")
    else:
        problems, cleared = [], set()
        for entry in lineage:
            artifact = entry.get("artifact", "<unnamed>")
            if not entry.get("sha256"):
                problems.append(f"{artifact}: no sha256")
            if entry.get("release_cleared") is not True:
                problems.append(f"{artifact}: release_cleared={entry.get('release_cleared')!r} "
                                f"(lineage {entry.get('training_data_lineage')!r})")
            elif not entry.get("basis"):
                problems.append(f"{artifact}: no basis for the clearance claim")
            else:
                # A free-text basis can be any sentence, so the clearance must point
                # at the record it rests on and carry that record's digest: the claim
                # is then re-checkable instead of merely believed.
                missing = [key for key in ("basis_reference", "basis_sha256") if not entry.get(key)]
                if missing:
                    problems.append(f"{artifact}: clearance basis is not linked (missing {missing})")
                elif not re.fullmatch(r"[0-9a-f]{64}", str(entry.get("basis_sha256"))):
                    problems.append(f"{artifact}: basis_sha256 is not a lowercase sha256")
                else:
                    cleared.add(artifact)
        untraceable = sorted(evidence_artifacts - cleared - {None})
        if untraceable:
            problems.append(f"training evidence points at artifacts absent from weight_lineage: {untraceable}")
        gate.observed = {"artifacts": len(lineage), "cleared": sorted(cleared)}
        gate.set("pass" if not problems else "fail",
                 "every shipped weight artifact is release-cleared with a stated basis"
                 if not problems else "; ".join(problems))
    gates.append(gate)

    return gates


def render(gates: list[Gate]) -> tuple[str, bool]:
    lines = ["| gate | state | observed |", "|---|---|---|"]
    mandatory_failed = False
    for gate in gates:
        observed = json.dumps(gate.observed, ensure_ascii=False) if gate.observed else ""
        lines.append(f"| {gate.name} | {gate.state} | {gate.detail} {observed} |".strip())
        if gate.mandatory and gate.state != "pass":
            mandatory_failed = True
    summary = {state: sum(1 for g in gates if g.state == state)
               for state in ("pass", "fail", "insufficient_evidence", "not_measurable", "not_provided")}
    lines.append("")
    lines.append(f"summary: {json.dumps(summary)}")
    lines.append("VERDICT: " + ("RELEASE-CANDIDATE GATES PASS" if not mandatory_failed
                                else "NOT A RELEASE CANDIDATE (gates unmet)"))
    return "\n".join(lines), mandatory_failed


TEMPLATE = {
    "candidate_id": "<fill>",
    "contract_version": "<fill>",
    "trained_heads": {},
    "contract_heads": [],
    "untrained_head_mask": [],
    "training_evidence": {},
    "weight_lineage": [
        {"artifact": "<file>", "sha256": "<sha256>", "training_data_lineage": "<admitted|research:...>",
         "release_cleared": False, "basis": "<why the clearance holds>"}
    ],
    "evaluated_split": "locked",
    "splits": {"train": {"manifest_sha256": ""}, "validation": {"manifest_sha256": ""},
               "calibration": {"manifest_sha256": ""}, "locked": {"manifest_sha256": ""}},
    "quota_counts": {k: 0 for k in QUOTAS},
    "per_class_counts": {}, "per_action_counts": {},
    "evaluation": {
        "fp_correct": {"good_frames_with_forbidden_correction": 0, "good_frames_evaluated": 0,
                       "keep_rate": 0.0, "abstain_rate": 0.0},
        "rate_table": {}, "false_improved": {}, "human": {}, "neural_gain": {"clusters": []},
        "confusion": {"correct": 0, "keep": 0, "abstain": 0, "incomparable": 0,
                      "forbidden_advised": 0, "evaluated_total": 0},
    },
    "gold": {
        "annotators": 0,
        # both declarations must be filled in explicitly: the evaluator treats an
        # omitted independence fact as a violated one
        "annotators_are_distinct_humans": None,
        "ai_suggestions_in_independent_pass": None,
        "hidden_qc_rate": 0.0,
        "adjudicated_review_rate": 0.0,
        "kappa_keep_correct_abstain": 0.0,
        "kappa_action_family": 0.0,
        "forbidden_agreement": 0.0,
        "median_roi_iou": 0.0,
        "hidden_qc": 0.0,
    },
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--template", action="store_true", help="print a manifest skeleton")
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    if args.template:
        print(json.dumps(TEMPLATE, ensure_ascii=False, indent=2))
        return 0
    if not args.manifest:
        parser.error("--manifest is required (or use --template)")
    if not args.manifest.exists():
        print(f"FAIL CLOSED: candidate manifest not found at {args.manifest}")
        print("There is no candidate to evaluate; no gate can be claimed.")
        return 2

    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        print(f"FAIL CLOSED: candidate manifest is not valid JSON: {error}")
        return 2

    gates = evaluate(manifest)
    report, failed = render(gates)
    print(report)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(
            {"candidate_id": manifest.get("candidate_id"),
             "gates": [{"name": g.name, "state": g.state, "detail": g.detail, "observed": g.observed} for g in gates],
             "verdict": "not_a_candidate" if failed else "pass"},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"WROTE {args.json_out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
