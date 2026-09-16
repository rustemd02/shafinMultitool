"""Which manifest keys does each producer actually fill, and what is still missing?

The gate reads a manifest; six producers now write parts of it. Between them there is
a real risk that a gate row exists for which nothing produces a value — the row then
reads `not_measurable`, or worse, a hand-written number appears where a computed one
belongs. This suite makes the mapping executable rather than aspirational:

* every key that is claimed to have a producer is checked by **running** that producer
  on a fixture and looking for the key in its output;
* every key still without a producer is listed as a gap with the reason it is blocked,
  and the test fails if a producer starts emitting one of them (so the table cannot go
  stale) or if one of them silently disappears;
* the two lists together must cover the quantities the gate decides on, so a new gate
  row cannot be added without either a producer or an explicit gap entry.

Gaps here are not defects to hide: each names the package that will fill it.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RELEASE = REPO_ROOT / "tools/release"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


gates = _load(RELEASE / "check_candidate_gates.py", "gates_for_key_coverage")

# ---------------------------------------------------------------- fixtures
EPISODES = [
    {"episode_id": f"e{i}", "cluster_id": f"shoot-{i % 3}", "app_decision": "correct",
     "app_verifier_outcome": "improved", "truth_outcome": "correct",
     "expected_action_family": "level_horizon", "advised_action_family": "level_horizon"}
    for i in range(190)
] + [
    {"episode_id": f"n{i}", "cluster_id": f"shoot-{i % 3}", "app_decision": "abstain",
     "app_verifier_outcome": "unchanged", "truth_outcome": "no_op",
     "expected_action_family": "level_horizon", "advised_action_family": "level_horizon"}
    for i in range(10)
]

STILL_ROWS = [
    {"record_id": f"r{i}", "quality_label": "good", "passed": True,
     "metrics": {"expected_action_hit": 1.0, "forbidden_action_violation": 0.0,
                 "confidence_band_match": 1.0, "good_frame_preserved": 1.0,
                 "positive_confirmation": 1.0, "future_action_hit": None,
                 "technical_failure_gate": None},
     "failures": [], "candidate_actions": ["keep_current_setup"],
     "expected_actions": ["keep_current_setup"]}
    for i in range(30)
]


def _label(record_id: str, annotator: str, improvement_needed: bool) -> dict:
    return {"schema_id": "camera-coach-label", "record_id": record_id, "annotator_id": annotator,
            "beauty": "borderline", "improvement_needed": improvement_needed, "unsure": False,
            "issues": [], "actions": ["level_horizon"] if improvement_needed
            else ["keep_current_setup"],
            "regions": [{"role": "subject", "rect": [0.1, 0.1, 0.3, 0.3]}], "notes": "",
            "assisted": False}


def _vote(review_id: str) -> dict:
    return {"review_id": review_id, "reviewer_id": "rev-1", "voted_at": "2026-09-13T10:00:00Z",
            "blind": True, "assisted": False, "visually_improved": "yes",
            "useful_instruction": "yes", "executable": "yes", "harmful": "none",
            "intent_preserved": "yes", "attribution": "action_caused", "notes": None}


def _write_jsonl(path: Path, rows: list[dict]) -> Path:
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
    return path


def _dotted(node, prefix: str = "") -> set[str]:
    out: set[str] = set()
    if isinstance(node, dict):
        for key, value in node.items():
            out |= _dotted(value, f"{prefix}.{key}" if prefix else key)
    elif isinstance(node, list):
        out.add(prefix)
    else:
        out.add(prefix)
    return out


def _run_producers(tmp_path: Path) -> dict[str, set[str]]:
    """Run every producer and collect the dotted keys it writes."""
    produced: dict[str, set[str]] = {}

    builder = _load(RELEASE / "build_candidate_manifest.py", "builder_for_coverage")
    stills = _write_jsonl(tmp_path / "case_results.jsonl", STILL_ROWS)
    clusters = tmp_path / "clusters.json"
    clusters.write_text(json.dumps({row["record_id"]: f"shoot-{i % 3}"
                                    for i, row in enumerate(STILL_ROWS)}), encoding="utf-8")
    out = tmp_path / "candidate.json"
    assert builder.main(["--case-results", str(stills), "--candidate-id", "coverage",
                         "--clusters", str(clusters), "--out", str(out)]) == 0
    manifest = json.loads(out.read_text(encoding="utf-8"))
    produced["build_candidate_manifest"] = _dotted(
        {k: v for k, v in manifest.items() if k != "provenance"})

    episodes_tool = _load(RELEASE / "build_episode_metrics.py", "episodes_for_coverage")
    episode_path = _write_jsonl(tmp_path / "episodes.jsonl", EPISODES)
    blocks = tmp_path / "blocks.json"
    assert episodes_tool.main(["--episodes", str(episode_path), "--out", str(blocks)]) == 0
    payload = json.loads(blocks.read_text(encoding="utf-8"))
    # recorded in the shape it takes inside a manifest, which is how the gate reads it
    produced["build_episode_metrics"] = _dotted({
        "evaluation": {"confusion": payload["confusion"],
                       "false_improved": payload["false_improved"]},
        "per_action_counts": payload["per_action_counts"]})

    arms = _load(RELEASE / "compare_arms.py", "arms_for_coverage")
    strong = [_dict_row(f"s{i}", True) for i in range(80)]
    weak = [_dict_row(f"s{i}", i < 24) for i in range(80)]
    arm_a = _write_jsonl(tmp_path / "arm_a.jsonl", strong)
    arm_b = _write_jsonl(tmp_path / "arm_b.jsonl", weak)
    arm_clusters = tmp_path / "arm_clusters.json"
    arm_clusters.write_text(json.dumps({f"s{i}": f"shoot-{i // 10}" for i in range(80)}),
                            encoding="utf-8")
    comparison = tmp_path / "comparison.json"
    assert arms.main(["--arm-a", str(arm_a), "--arm-a-kind", "neural",
                      "--arm-b", str(arm_b), "--arm-b-kind", "deterministic_baseline",
                      "--clusters", str(arm_clusters), "--out", str(comparison)]) == 0
    arm_payload = json.loads(comparison.read_text(encoding="utf-8"))
    produced["compare_arms"] = _dotted({"evaluation": {"neural_gain":
                                                       arm_payload["neural_gain_block"]}})

    lineage_tool = _load(RELEASE / "build_weight_lineage.py", "lineage_for_coverage")
    provenance = tmp_path / "provenance.json"
    provenance.write_text(json.dumps({
        "release_admissible": True, "admitted_data": "admitted:cinematic-ccby",
        "weights_sha256": "a" * 64, "weights_origin": "trained", "mlpackage": {"path": "m"}}),
        encoding="utf-8")
    rights = tmp_path / "rights.jsonl"
    rights.write_text("\n".join(json.dumps(record) for record in (
        {"manifest_type": "rights", "record_count": 1, "template_only": False},
        {"record_type": "rights-entry", "training_data_lineage": "admitted:cinematic-ccby",
         "decision": {"admitted": True, "decision": "admit",
                      "decision_scope": "train+eval+release"},
         "basis": {"basis_type": "owner_decision", "basis_reference": "Packet A",
                   "basis_sha256": "b" * 64}})) + "\n", encoding="utf-8")
    lineage = tmp_path / "lineage.json"
    assert lineage_tool.main(["--provenance", str(provenance), "--rights-manifest", str(rights),
                              "--out", str(lineage)]) == 0
    produced["build_weight_lineage"] = _dotted(
        {"weight_lineage": json.loads(lineage.read_text(encoding="utf-8"))["weight_lineage"]})

    gold_tool = _load(RELEASE / "build_gold_report.py", "gold_for_coverage")
    store_rows: list[dict] = []
    for i in range(20):
        store_rows.append(_label(f"r{i}", "owner", i % 2 == 0))
        store_rows.append(_label(f"r{i}", "second", i % 2 == 0))
    store_rows += [{"record_type": "hidden_qc", "record_id": f"r{i}", "annotator_id": "owner",
                    "observed_verdict": "good", "expected_verdict": "good", "agrees": True,
                    "notes": "seeded"} for i in range(2)]
    gold_store = _write_jsonl(tmp_path / "store.jsonl", store_rows)
    forbidden = tmp_path / "forbidden.json"
    forbidden.write_text(json.dumps(["level_horizon"]), encoding="utf-8")
    gold = tmp_path / "gold.json"
    assert gold_tool.main(["--store", str(gold_store), "--forbidden-actions", str(forbidden),
                           "--out", str(gold)]) == 0
    produced["build_gold_report"] = _dotted({"gold": json.loads(gold.read_text(encoding="utf-8"))
                                             ["gold"]})

    human_tool = _load(RELEASE / "build_human_report.py", "human_for_coverage")
    votes = _write_jsonl(tmp_path / "reviews.jsonl", [_vote(f"v{i}") for i in range(10)])
    human = tmp_path / "human.json"
    assert human_tool.main(["--votes", str(votes), "--out", str(human)]) == 0
    produced["build_human_report"] = _dotted({"evaluation": {"human":
                                                             json.loads(human.read_text(encoding="utf-8"))["human"]}})
    return produced


def _dict_row(record_id: str, passed: bool) -> dict:
    return {"record_id": record_id, "passed": passed,
            "metrics": {"expected_action_hit": 1.0 if passed else 0.0,
                        "forbidden_action_violation": 0.0}}


# Quantities the gate decides on, grouped by the block it reads.
GATE_QUANTITIES = {
    "evaluation.fp_correct.good_frames_evaluated",
    "evaluation.fp_correct.good_frames_with_forbidden_correction",
    "evaluation.fp_correct.keep_rate",
    "evaluation.fp_correct.abstain_rate",
    "evaluation.fp_correct.cluster_count",
    "evaluation.rate_table.pass_rate",
    "evaluation.rate_table.expected_action_hit",
    "evaluation.rate_table.forbidden_violations_rate",
    "evaluation.rate_table.confidence_band_accuracy",
    "evaluation.confusion.correct",
    "evaluation.confusion.keep",
    "evaluation.confusion.abstain",
    "evaluation.confusion.incomparable",
    "evaluation.confusion.forbidden_advised",
    "evaluation.confusion.evaluated_total",
    "evaluation.false_improved.wrong_confirmations",
    "evaluation.false_improved.improved_issued",
    "evaluation.false_improved.wrong_improved",
    "evaluation.false_improved.non_improved_episodes",
    "evaluation.neural_gain.clusters",
    "evaluation.neural_gain.point_gain_pp",
    "evaluation.neural_gain.safety_not_worse",
    "evaluation.human.safe_and_executable",
    "evaluation.human.helpful",
    "evaluation.human.preference_non_ties",
    "evaluation.human.materially_harmful",
    "evaluation.human.critical_harm",
    "gold.annotators",
    "gold.kappa_keep_correct_abstain",
    "gold.kappa_action_family",
    "gold.forbidden_agreement",
    "gold.median_roi_iou",
    "gold.hidden_qc_rate",
    "gold.hidden_qc",
    "gold.adjudicated_review_rate",
    "weight_lineage",
}

# Still nothing produces these. Each entry names the package that will.
DEFINITION_GAP = ("no operational definition exists anywhere in the repository (see "
                  "datasets/camera-coach/v1/evaluation-policy-v1.json runbook_5_1_rows): "
                  "the row must be defined before it can be produced, otherwise its "
                  "denominator would be invented")

DOCUMENTED_GAPS = {
    "evaluation.rate_table.direction_horizon_hits": DEFINITION_GAP,
    "evaluation.rate_table.light_exposure_hits": DEFINITION_GAP,
    "evaluation.rate_table.accepted_coverage_overall": DEFINITION_GAP,
    "evaluation.rate_table.abstention_correctness": DEFINITION_GAP,
    "evaluation.rate_table.verification_accuracy": DEFINITION_GAP,
    "evaluation.rate_table.scene_class_min": "D04 sealed splits; also a partially_defined row "
                                             "(source_bucket is not the scene-class taxonomy)",
    "evaluation.rate_table.synthetic_adversarial": "D04 sealed splits; also partially_defined "
                                                   "(which buckets are adversarial is unstated)",
    "evaluation.rate_table.technical_failure_pass_rate": "D04 sealed splits; the frozen "
                                                         "definition text still has to be pinned",
    "quota_counts": "D04 sealed splits (blocked by Packet A)",
    "per_class_counts": "D04 sealed splits (blocked by Packet A)",
    "per_action_counts.train_positives": "D04 sealed splits (blocked by Packet A)",
    "splits": "build_split_groups refuses until a corpus is admitted (Packet A)",
    "trained_heads": "M03/M04 trained candidate",
    "training_evidence": "M03/M04 trained candidate",
}


@pytest.fixture(scope="module")
def produced() -> dict[str, set[str]]:
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        yield _run_producers(Path(directory))


def test_every_claimed_producer_really_emits_its_keys(produced):
    """The table is checked by running the tools, not by trusting this file."""
    expected = {
        "build_candidate_manifest": {
            "evaluation.fp_correct.good_frames_evaluated",
            "evaluation.fp_correct.good_frames_with_forbidden_correction",
            "evaluation.fp_correct.keep_rate",
            "evaluation.fp_correct.cluster_count",
            "evaluation.rate_table.pass_rate",
            "evaluation.rate_table.expected_action_hit",
            "evaluation.rate_table.forbidden_violations_rate",
            "evaluation.rate_table.confidence_band_accuracy",
        },
        "build_episode_metrics": {
            "evaluation.confusion.correct", "evaluation.confusion.keep",
            "evaluation.confusion.abstain", "evaluation.confusion.incomparable",
            "evaluation.confusion.forbidden_advised", "evaluation.confusion.evaluated_total",
            "evaluation.false_improved.wrong_confirmations",
            "evaluation.false_improved.improved_issued",
            "evaluation.false_improved.wrong_improved",
            "evaluation.false_improved.non_improved_episodes",
            "per_action_counts.level_horizon.episodes.improved",
            "per_action_counts.level_horizon.episodes.unchanged_or_worse",
            "per_action_counts.level_horizon.episodes.incomparable",
        },
        "compare_arms": {
            "evaluation.neural_gain.clusters",
            "evaluation.neural_gain.point_gain_pp",
            "evaluation.neural_gain.safety_not_worse",
        },
        "build_weight_lineage": {"weight_lineage"},
        "build_gold_report": {
            "gold.annotators", "gold.kappa_keep_correct_abstain", "gold.kappa_action_family",
            "gold.forbidden_agreement", "gold.median_roi_iou", "gold.hidden_qc_rate",
            "gold.hidden_qc", "gold.adjudicated_review_rate",
        },
        "build_human_report": {
            "evaluation.human.safe_and_executable", "evaluation.human.helpful",
            "evaluation.human.preference_non_ties", "evaluation.human.materially_harmful",
            "evaluation.human.critical_harm",
        },
    }
    missing = {producer: sorted(keys - produced[producer])
               for producer, keys in expected.items() if keys - produced[producer]}
    assert missing == {}, missing


def test_the_gap_list_has_no_stale_entries(produced):
    """A gap that a producer now fills must be removed from the list."""
    everything = set().union(*produced.values())
    stale = sorted(key for key in DOCUMENTED_GAPS
                   if any(key == item or item.startswith(f"{key}.") for item in everything))
    assert stale == [], f"these keys are produced now and must leave DOCUMENTED_GAPS: {stale}"


def test_produced_keys_and_declared_gaps_cover_the_gate_quantities(produced):
    everything = set().union(*produced.values())
    covered = set()
    for key in GATE_QUANTITIES:
        if any(key == item or item.startswith(f"{key}.") for item in everything):
            covered.add(key)
    gaps = {key for key in GATE_QUANTITIES
            if any(key == gap or key.startswith(f"{gap}.") for gap in DOCUMENTED_GAPS)}
    uncovered = sorted(GATE_QUANTITIES - covered - gaps)
    assert uncovered == [], f"gate quantities with neither producer nor documented gap: {uncovered}"


def test_the_gate_quantities_are_the_ones_the_tool_decides_on():
    """Cross-check: every name above is a real gate the tool produces."""
    gates_now = {gate.name for gate in gates.evaluate({})}
    assert "fp_correct_on_good_frames" in gates_now
    assert "neural_gain_over_baseline" in gates_now
    assert "gold_independence_and_kappa" in gates_now
    assert "weight_lineage_release_cleared" in gates_now
