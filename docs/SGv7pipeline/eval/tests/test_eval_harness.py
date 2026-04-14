from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from eval import CompareReportsRequest, EvalScoreRequest, compare_reports, score_checkpoint
from eval.harness import EvalHarnessError
from eval.release_gate import CORE_METRICS, ReleaseGateRequest, evaluate_release_gate
from eval.scorer import ScoreCasesRequest, score_cases


REQUIRED_SNAPSHOTS = [
    "prompt_contract_snapshot.json",
    "decoding_config_snapshot.json",
    "grammar_constraint_snapshot.json",
    "normalization_policy_snapshot.json",
    "runtime_policy_snapshot.json",
]


def _write_json(path: Path, payload: dict[str, object]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _base_script() -> dict[str, object]:
    return {
        "actors": [{"id": "actor_1"}, {"id": "actor_2"}],
        "objects": [{"id": "object_marked_ab12"}],
        "beats": [
            {"id": "beat_1", "actions": [{"actorId": "actor_1", "type": "approach", "target": "actor_2"}]},
            {"id": "beat_2", "actions": [{"actorId": "actor_1", "type": "stop", "target": "object_marked_ab12"}]},
            {
                "id": "beat_3",
                "actions": [{"actorId": "actor_1", "type": "described_action", "fallbackText": "начал курить"}],
            },
        ],
    }


def _eval_case(case_id: str, eval_set: str, correction_tier: str) -> dict[str, object]:
    return {
        "eval_case_id": case_id,
        "eval_set": eval_set,
        "sample_id": case_id,
        "graph_family_key": "gfk_case",
        "contract_version": "sg_v7_contract_v1",
        "difficulty_bucket": "hard",
        "source_text": "2 актера идут навстречу друг другу, останавливаются у компа, первый начинает курить",
        "marked_objects": [{"id": "object_marked_ab12", "name": "комп", "type": "generic"}],
        "gold_target_json": _base_script(),
        "rule_based_reference_json": _base_script(),
        "eval_expectations": {
            "expected_marked_object_ids": ["object_marked_ab12"],
            "expected_ordinal_bindings": {"first": "actor_1", "second": "actor_2"},
            "expected_action_units": [
                {
                    "beat_index": 1,
                    "actor_id": "actor_1",
                    "action_type": "approach",
                    "target_id": "actor_2",
                    "phase_label": "move_toward_each_other",
                },
                {
                    "beat_index": 2,
                    "actor_id": "actor_1",
                    "action_type": "stop",
                    "target_id": "object_marked_ab12",
                    "phase_label": "stop_near_marked_object",
                },
                {
                    "beat_index": 3,
                    "actor_id": "actor_1",
                    "action_type": "described_action",
                    "fallback_text_lemmas": ["курить"],
                    "phase_label": "described_action_smoke",
                },
            ],
            "expected_phase_sequence": [
                "move_toward_each_other",
                "stop_near_marked_object",
                "described_action_smoke",
            ],
            "critical_eval_tags": [
                "ordinal_cases",
                "three_beat_cases",
                "unsupported_action_cases",
            ],
        },
        "runtime_policy_inputs": {
            "rule_confidence": 0.75,
            "rule_object_count": 1,
            "rule_action_count": 3,
            "rule_has_dangling_targets": False,
            "rule_matched_marked_object_count": 1,
            "mentioned_marked_object_ids": ["object_marked_ab12"],
        },
        "provenance": {
            "origin": "runtime_reviewed" if eval_set == "real_runtime" else "synthetic",
            "correction_tier": correction_tier,
            "review_status": "approved",
            "gold_source": "corrected_target_json",
            "final_script_source": "merge_reviewed",
        },
    }


def _build_bundle(bundle_dir: Path, *, mismatch_hashes: bool = False) -> None:
    snapshot_hashes: dict[str, str] = {}
    for snapshot_name in REQUIRED_SNAPSHOTS:
        snapshot_path = bundle_dir / snapshot_name
        _write_json(snapshot_path, {"snapshot_id": snapshot_name, "version": "v1"})
        snapshot_hashes[snapshot_name] = _sha256(snapshot_path)
    if mismatch_hashes:
        snapshot_hashes["prompt_contract_snapshot.json"] = "bad_hash"

    manifest = {
        "bundle_id": "test_bundle",
        "bundle_version": "v1",
        "contract_version": "sg_v7_contract_v1",
        "required_contract_snapshots": REQUIRED_SNAPSHOTS,
        "expected_snapshot_hashes": snapshot_hashes,
    }
    _write_json(bundle_dir / "eval_bundle_manifest.json", manifest)
    rows = [
        _eval_case("hard-1", "hard_heldout", "tier_b_deterministic_canonical"),
        _eval_case("runtime-1", "real_runtime", "tier_c_reviewed_merge"),
    ]
    _write_jsonl(bundle_dir / "eval_cases.jsonl", rows)


def _core_metrics(*, runtime_fallback_rate: float, llm_merge_rate: float = 0.10, llm_reject_rate: float = 0.10) -> dict[str, float]:
    metrics: dict[str, float] = {}
    for metric_name in CORE_METRICS:
        if metric_name in {"dangling_target_rate", "llm_merge_rate", "llm_reject_rate", "runtime_fallback_rate"}:
            metrics[metric_name] = 0.10
        else:
            metrics[metric_name] = 0.90
    metrics["runtime_fallback_rate"] = runtime_fallback_rate
    metrics["llm_merge_rate"] = llm_merge_rate
    metrics["llm_reject_rate"] = llm_reject_rate
    return metrics


def _case_rows_for_cluster(*, eval_set: str, cluster_id: str, count: int) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for _ in range(count):
        rows.append(
            {
                "eval_set": eval_set,
                "failure_cluster": {"cluster_id": cluster_id},
            }
        )
    return rows


class TestEvalHarness(unittest.TestCase):
    def test_score_materializes_reports(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            bundle = tmp / "bundle"
            bundle.mkdir(parents=True, exist_ok=True)
            _build_bundle(bundle)
            out = tmp / "out"

            result = score_checkpoint(
                EvalScoreRequest(
                    eval_bundle_dir=bundle,
                    checkpoint_id="ckpt_oracle",
                    output_dir=out,
                    seed=20260414,
                )
            )
            self.assertIn(result["release_gate_summary"]["gate_status"], {"pass", "pass_with_watchlist"})
            for filename in (
                "raw_outputs.jsonl",
                "case_results.jsonl",
                "set_metrics.json",
                "bucket_metrics.json",
                "release_gate_summary.json",
                "eval_summary.md",
                "run_manifest.json",
            ):
                self.assertTrue((out / filename).exists(), msg=filename)

    def test_compare_reports_materializes_ab_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            bundle = tmp / "bundle"
            bundle.mkdir(parents=True, exist_ok=True)
            _build_bundle(bundle)

            baseline_out = tmp / "baseline"
            score_checkpoint(
                EvalScoreRequest(
                    eval_bundle_dir=bundle,
                    checkpoint_id="baseline",
                    output_dir=baseline_out,
                    seed=20260414,
                )
            )

            predictions = tmp / "predictions.jsonl"
            _write_jsonl(
                predictions,
                [
                    {"eval_case_id": "hard-1", "predicted_script": _base_script()},
                    {"eval_case_id": "runtime-1", "raw_output_text": "not json"},
                ],
            )
            candidate_out = tmp / "candidate"
            score_checkpoint(
                EvalScoreRequest(
                    eval_bundle_dir=bundle,
                    checkpoint_id="candidate",
                    output_dir=candidate_out,
                    seed=20260414,
                    predictions_jsonl=predictions,
                )
            )

            compare_out = tmp / "compare"
            summary = compare_reports(
                CompareReportsRequest(
                    candidate_report_dir=candidate_out,
                    baseline_report_dir=baseline_out,
                    output_dir=compare_out,
                )
            )
            self.assertGreater(summary["wins_baseline"], 0)
            self.assertTrue((compare_out / "ab_summary.json").exists())
            self.assertTrue((compare_out / "ab_report.md").exists())
            self.assertTrue((compare_out / "paired_case_results.jsonl").exists())

    def test_contract_drift_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            bundle = tmp / "bundle"
            bundle.mkdir(parents=True, exist_ok=True)
            _build_bundle(bundle, mismatch_hashes=True)
            with self.assertRaises(EvalHarnessError):
                score_checkpoint(
                    EvalScoreRequest(
                        eval_bundle_dir=bundle,
                        checkpoint_id="ckpt",
                        output_dir=tmp / "out",
                        seed=20260414,
                    )
                )

    def test_gate4_cluster_compare_uses_full_candidate_cluster_counts(self) -> None:
        baseline_case_results = []
        baseline_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_b", count=7))
        baseline_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_c", count=6))
        baseline_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_a", count=5))
        baseline_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_d", count=4))

        candidate_case_results = []
        candidate_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_b", count=100))
        candidate_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_c", count=90))
        candidate_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_d", count=80))
        candidate_case_results.extend(_case_rows_for_cluster(eval_set="hard_heldout", cluster_id="cluster_a", count=9))

        baseline_overall = _core_metrics(runtime_fallback_rate=0.20)
        candidate_overall = _core_metrics(runtime_fallback_rate=0.10)
        baseline_real_runtime = _core_metrics(runtime_fallback_rate=0.20, llm_merge_rate=0.20, llm_reject_rate=0.20)
        candidate_real_runtime = _core_metrics(runtime_fallback_rate=0.10, llm_merge_rate=0.20, llm_reject_rate=0.20)
        summary = evaluate_release_gate(
            ReleaseGateRequest(
                candidate_set_metrics={
                    "overall": {"metrics": candidate_overall},
                    "sets": {"real_runtime": {"metrics": candidate_real_runtime}},
                },
                candidate_bucket_metrics={"buckets": {}},
                candidate_case_results=candidate_case_results,
                candidate_contract={"snapshot_hashes": {"prompt_contract_snapshot.json": "hash"}},
                baseline_set_metrics={
                    "overall": {"metrics": baseline_overall},
                    "sets": {"real_runtime": {"metrics": baseline_real_runtime}},
                },
                baseline_bucket_metrics=None,
                baseline_case_results=baseline_case_results,
                baseline_contract={"snapshot_hashes": {"prompt_contract_snapshot.json": "hash"}},
            )
        )
        self.assertIn("gate4:cluster_regression:hard_heldout:cluster_a", summary["blocking_reasons"])

    def test_described_action_precision_is_global_micro_precision(self) -> None:
        case_a = _eval_case("case-a", "hard_heldout", "tier_b_deterministic_canonical")
        case_b = _eval_case("case-b", "hard_heldout", "tier_b_deterministic_canonical")
        case_b_expectations = dict(case_b["eval_expectations"])
        expected_action_units = list(case_b_expectations["expected_action_units"])
        case_b_expectations["expected_action_units"] = [expected_action_units[0], expected_action_units[1]]
        case_b_expectations["expected_phase_sequence"] = ["move_toward_each_other", "stop_near_marked_object"]
        case_b["eval_expectations"] = case_b_expectations

        script_with_extra_described = _base_script()
        script_with_extra_described["beats"] = [
            {"id": "beat_1", "actions": [{"actorId": "actor_1", "type": "approach", "target": "actor_2"}]},
            {"id": "beat_2", "actions": [{"actorId": "actor_1", "type": "stop", "target": "object_marked_ab12"}]},
            {
                "id": "beat_3",
                "actions": [
                    {"actorId": "actor_1", "type": "described_action", "fallbackText": f"action_{idx}"}
                    for idx in range(9)
                ],
            },
        ]

        scored = score_cases(
            ScoreCasesRequest(
                checkpoint_id="candidate",
                cases=[case_a, case_b],
                predicted_by_case={
                    "case-a": _base_script(),
                    "case-b": script_with_extra_described,
                },
                runtime_policy_snapshot={},
            )
        )
        described_precision = scored["set_metrics"]["overall"]["metrics"]["described_action_precision"]
        self.assertAlmostEqual(described_precision, 0.1, places=6)

    def test_schema_valid_rate_rejects_broken_action_references(self) -> None:
        case = _eval_case("schema-case", "hard_heldout", "tier_b_deterministic_canonical")
        bad_script = {
            "actors": [{"id": "actor_1"}],
            "objects": [{"id": "object_marked_ab12"}],
            "beats": [
                {
                    "id": "beat_1",
                    "actions": [
                        {
                            "actorId": "actor_1",
                            "type": "approach",
                            "target": "actor_2",
                        }
                    ],
                }
            ],
        }
        scored = score_cases(
            ScoreCasesRequest(
                checkpoint_id="candidate",
                cases=[case],
                predicted_by_case={"schema-case": bad_script},
                runtime_policy_snapshot={},
            )
        )
        case_result = scored["case_results"][0]
        schema_valid_rate = scored["set_metrics"]["overall"]["metrics"]["schema_valid_rate"]
        self.assertTrue(case_result["json_valid"])
        self.assertTrue(case_result["canonical_parse"])
        self.assertFalse(case_result["schema_valid"])
        self.assertEqual(schema_valid_rate, 0.0)


if __name__ == "__main__":
    unittest.main()
