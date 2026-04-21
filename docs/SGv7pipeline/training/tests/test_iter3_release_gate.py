from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from training import Iter3ReleaseGateRequest, evaluate_iter3_release_gate


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _runs_scored_rows() -> tuple[list[str], list[dict[str, object]]]:
    fieldnames = [
        "model_id",
        "seed",
        "overall.json_valid_rate",
        "overall.exact_marked_object_id_accuracy",
        "overall.ordinal_actor_binding_accuracy",
        "overall.target_resolution_accuracy",
        "overall.chronology_phase_accuracy",
        "overall.runtime_fallback_rate",
        "overall.case_strict_success_rate",
        "bucket.three_beat_cases.target_resolution_accuracy",
        "bucket.three_beat_cases.chronology_phase_accuracy",
    ]
    rows = [
        {
            "model_id": "dataset_v7_orpo_iter2",
            "seed": 42,
            "overall.json_valid_rate": 0.9820,
            "overall.exact_marked_object_id_accuracy": 0.9910,
            "overall.ordinal_actor_binding_accuracy": 0.9710,
            "overall.target_resolution_accuracy": 0.1162,
            "overall.chronology_phase_accuracy": 0.0840,
            "overall.runtime_fallback_rate": 0.9465,
            "overall.case_strict_success_rate": 0.0382,
            "bucket.three_beat_cases.target_resolution_accuracy": 0.2625,
            "bucket.three_beat_cases.chronology_phase_accuracy": 0.25,
        },
        {
            "model_id": "dataset_v7_orpo_iter3",
            "seed": 42,
            "overall.json_valid_rate": 0.9850,
            "overall.exact_marked_object_id_accuracy": 0.9950,
            "overall.ordinal_actor_binding_accuracy": 0.9750,
            "overall.target_resolution_accuracy": 0.1300,
            "overall.chronology_phase_accuracy": 0.0950,
            "overall.runtime_fallback_rate": 0.9300,
            "overall.case_strict_success_rate": 0.0500,
            "bucket.three_beat_cases.target_resolution_accuracy": 0.3000,
            "bucket.three_beat_cases.chronology_phase_accuracy": 0.2800,
        },
    ]
    return fieldnames, rows


def _slice_rows(*, bad_model_only: bool = False) -> tuple[list[str], list[dict[str, object]]]:
    fieldnames = [
        "model_id",
        "seed",
        "slice",
        "json_valid_rate",
        "schema_valid_rate",
        "exact_marked_object_id_accuracy",
        "ordinal_actor_binding_accuracy",
        "target_resolution_accuracy",
        "chronology_phase_accuracy",
        "action_recall",
        "runtime_fallback_rate",
        "case_strict_success_rate",
    ]
    candidate_model_only = {
        "model_id": "dataset_v7_orpo_iter3",
        "seed": 42,
        "slice": "model_only",
        "json_valid_rate": 0.970 if bad_model_only else 0.982,
        "schema_valid_rate": 0.970 if bad_model_only else 0.982,
        "exact_marked_object_id_accuracy": 0.980 if bad_model_only else 0.995,
        "ordinal_actor_binding_accuracy": 0.960 if bad_model_only else 0.975,
        "target_resolution_accuracy": 0.121,
        "chronology_phase_accuracy": 0.091,
        "action_recall": 0.101,
        "runtime_fallback_rate": 0.940,
        "case_strict_success_rate": 0.044,
    }
    rows = [
        {
            "model_id": "dataset_v7_orpo_iter2",
            "seed": 42,
            "slice": "end_to_end",
            "json_valid_rate": 0.981,
            "schema_valid_rate": 0.981,
            "exact_marked_object_id_accuracy": 0.992,
            "ordinal_actor_binding_accuracy": 0.971,
            "target_resolution_accuracy": 0.116,
            "chronology_phase_accuracy": 0.084,
            "action_recall": 0.090,
            "runtime_fallback_rate": 0.946,
            "case_strict_success_rate": 0.038,
        },
        candidate_model_only,
        {
            "model_id": "dataset_v7_orpo_iter3",
            "seed": 42,
            "slice": "end_to_end",
            "json_valid_rate": 0.986,
            "schema_valid_rate": 0.986,
            "exact_marked_object_id_accuracy": 0.996,
            "ordinal_actor_binding_accuracy": 0.976,
            "target_resolution_accuracy": 0.133,
            "chronology_phase_accuracy": 0.098,
            "action_recall": 0.110,
            "runtime_fallback_rate": 0.925,
            "case_strict_success_rate": 0.052,
        },
    ]
    return fieldnames, rows


def _manifest(*, excessive_gold: bool = False) -> dict[str, object]:
    gold_share = 0.9 if excessive_gold else 0.40
    model_share = 0.1 if excessive_gold else 0.60
    return {
        "prediction_source_policy": {
            "requires_dual_slice": True,
            "selection_slice": "model_only_predicted_script",
        },
        "counts": {
            "delta_sft_total": 10,
        },
        "configured_family_floors": {
            "exact_marker_identity": 4,
            "give_to_third_actor": 4,
            "open_then_pick_up": 4,
            "ordinal": 6,
            "three_beat": 10,
        },
        "delta_sft_max_family_share": 0.50,
        "delta_family_counts": {
            "exact_marker_identity": 4,
            "give_to_third_actor": 4,
            "open_then_pick_up": 4,
            "ordinal": 4,
            "three_beat": 4,
        },
        "preference_family_counts": {
            "exact_marker_identity": 4,
            "give_to_third_actor": 6,
            "open_then_pick_up": 6,
            "ordinal": 8,
            "three_beat": 10,
        },
        "selection_family_counts": {
            "exact_marker_identity": 4,
            "give_to_third_actor": 6,
            "open_then_pick_up": 6,
            "ordinal": 8,
            "three_beat": 10,
        },
        "gold_chosen_share_overall": gold_share,
        "model_chosen_share_overall": model_share,
        "gold_chosen_share_by_family": {
            "exact_marker_identity": 0.25 if not excessive_gold else 0.90,
            "give_to_third_actor": 0.30 if not excessive_gold else 0.90,
            "open_then_pick_up": 0.30 if not excessive_gold else 0.90,
            "ordinal": 0.35 if not excessive_gold else 0.90,
            "three_beat": 0.30 if not excessive_gold else 0.90,
        },
        "model_chosen_count_by_family": {
            "exact_marker_identity": 3 if not excessive_gold else 1,
            "give_to_third_actor": 4 if not excessive_gold else 1,
            "open_then_pick_up": 4 if not excessive_gold else 1,
            "ordinal": 5 if not excessive_gold else 1,
            "three_beat": 7 if not excessive_gold else 1,
        },
        "raw_vs_end_to_end_divergence_counts": {
            "dataset_v7": 1,
            "dataset_v7_orpo_iter1": 2,
            "dataset_v7_orpo_iter2": 3,
        },
    }


def _case_row(eval_case_id: str, *, beat: bool = True, ordinal: bool = True, target: bool = True, chronology: bool = True, action: bool = True) -> dict[str, object]:
    return {
        "eval_case_id": eval_case_id,
        "json_valid": True,
        "schema_valid": True,
        "case_strict_success": True,
        "runtime_policy_decision": "accept",
        "metric_flags": {
            "beat_count_pass": beat,
            "ordinal_binding_pass": ordinal,
            "target_resolution_pass": target,
            "chronology_phase_pass": chronology,
            "action_recall_pass": action,
        },
    }


def _case_rows(*, degrade_open: bool = False) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    candidate = [
        _case_row("syn-open::open_then_pick_up_object__base__a", beat=not degrade_open, chronology=not degrade_open),
        _case_row("syn-ord::ordinal_first_second_third__base__b"),
        _case_row("syn-give::dialogue_then_pick_up_object_then_give_to_third_actor__base__c"),
    ]
    baseline = [
        _case_row("syn-open::open_then_pick_up_object__base__a"),
        _case_row("syn-ord::ordinal_first_second_third__base__b"),
        _case_row("syn-give::dialogue_then_pick_up_object_then_give_to_third_actor__base__c"),
    ]
    return candidate, baseline


class TestIter3ReleaseGate(unittest.TestCase):
    def test_iter3_release_gate_requires_manual_review_after_automated_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runs_scored = tmp / "runs_scored.csv"
            slice_summary = tmp / "model_slice_summary.csv"
            manifest = tmp / "iter3_manifest.json"
            candidate_cases = tmp / "candidate_model_only_case_results.jsonl"
            baseline_cases = tmp / "baseline_model_only_case_results.jsonl"

            fieldnames, run_rows = _runs_scored_rows()
            _write_csv(runs_scored, fieldnames, run_rows)
            slice_fieldnames, slice_rows = _slice_rows()
            _write_csv(slice_summary, slice_fieldnames, slice_rows)
            manifest.write_text(json.dumps(_manifest()), encoding="utf-8")
            candidate_case_rows, baseline_case_rows = _case_rows()
            _write_jsonl(candidate_cases, candidate_case_rows)
            _write_jsonl(baseline_cases, baseline_case_rows)

            result = evaluate_iter3_release_gate(
                Iter3ReleaseGateRequest(
                    runs_scored_csv=runs_scored,
                    model_slice_summary_csv=slice_summary,
                    iter3_manifest_json=manifest,
                    candidate_model_only_case_results_jsonl=candidate_cases,
                    baseline_model_only_case_results_jsonl=baseline_cases,
                    candidate_model_id="dataset_v7_orpo_iter3",
                    output_dir=tmp,
                    seed=42,
                )
            )
            self.assertEqual(result["gate_status"], "pending_manual_review")
            self.assertTrue(result["numeric_pass"])
            self.assertTrue(result["slice_pass"])
            self.assertTrue(result["manifest_pass"])
            self.assertTrue(result["targeted_pattern_pass"])
            self.assertEqual(result["targeted_pattern_slice"], "model_only")

            manual_path = tmp / "manual_review.json"
            manual_path.write_text(
                json.dumps(
                    {
                        "open_then_pick_up_object": True,
                        "ordinal_first_second_third": True,
                        "dialogue_then_pick_up_object_then_give_to_third_actor": True,
                    }
                ),
                encoding="utf-8",
            )
            result = evaluate_iter3_release_gate(
                Iter3ReleaseGateRequest(
                    runs_scored_csv=runs_scored,
                    model_slice_summary_csv=slice_summary,
                    iter3_manifest_json=manifest,
                    candidate_model_only_case_results_jsonl=candidate_cases,
                    baseline_model_only_case_results_jsonl=baseline_cases,
                    candidate_model_id="dataset_v7_orpo_iter3",
                    output_dir=tmp,
                    seed=42,
                    manual_review_json=manual_path,
                )
            )
            self.assertEqual(result["gate_status"], "pass")

    def test_iter3_release_gate_fails_without_model_slice_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runs_scored = tmp / "runs_scored.csv"
            slice_summary = tmp / "model_slice_summary.csv"
            manifest = tmp / "iter3_manifest.json"
            candidate_cases = tmp / "candidate_model_only_case_results.jsonl"
            baseline_cases = tmp / "baseline_model_only_case_results.jsonl"

            fieldnames, run_rows = _runs_scored_rows()
            _write_csv(runs_scored, fieldnames, run_rows)
            slice_summary.write_text("", encoding="utf-8")
            manifest.write_text(json.dumps(_manifest()), encoding="utf-8")
            candidate_case_rows, baseline_case_rows = _case_rows()
            _write_jsonl(candidate_cases, candidate_case_rows)
            _write_jsonl(baseline_cases, baseline_case_rows)

            result = evaluate_iter3_release_gate(
                Iter3ReleaseGateRequest(
                    runs_scored_csv=runs_scored,
                    model_slice_summary_csv=slice_summary,
                    iter3_manifest_json=manifest,
                    candidate_model_only_case_results_jsonl=candidate_cases,
                    baseline_model_only_case_results_jsonl=baseline_cases,
                    candidate_model_id="dataset_v7_orpo_iter3",
                    output_dir=tmp,
                    seed=42,
                )
            )
            self.assertEqual(result["gate_status"], "fail")
            self.assertIn("missing_model_slice_summary", result["slice_blockers"])

    def test_iter3_release_gate_fails_when_model_only_is_weaker(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runs_scored = tmp / "runs_scored.csv"
            slice_summary = tmp / "model_slice_summary.csv"
            manifest = tmp / "iter3_manifest.json"
            candidate_cases = tmp / "candidate_model_only_case_results.jsonl"
            baseline_cases = tmp / "baseline_model_only_case_results.jsonl"

            fieldnames, run_rows = _runs_scored_rows()
            _write_csv(runs_scored, fieldnames, run_rows)
            slice_fieldnames, slice_rows = _slice_rows(bad_model_only=True)
            _write_csv(slice_summary, slice_fieldnames, slice_rows)
            manifest.write_text(json.dumps(_manifest()), encoding="utf-8")
            candidate_case_rows, baseline_case_rows = _case_rows()
            _write_jsonl(candidate_cases, candidate_case_rows)
            _write_jsonl(baseline_cases, baseline_case_rows)

            result = evaluate_iter3_release_gate(
                Iter3ReleaseGateRequest(
                    runs_scored_csv=runs_scored,
                    model_slice_summary_csv=slice_summary,
                    iter3_manifest_json=manifest,
                    candidate_model_only_case_results_jsonl=candidate_cases,
                    baseline_model_only_case_results_jsonl=baseline_cases,
                    candidate_model_id="dataset_v7_orpo_iter3",
                    output_dir=tmp,
                    seed=42,
                )
            )
            self.assertEqual(result["gate_status"], "fail")
            self.assertFalse(result["slice_pass"])
            self.assertFalse(result["slice_checks"]["slice.model_only.json_valid_rate"])

    def test_iter3_release_gate_fails_when_model_only_targeted_group_regresses(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runs_scored = tmp / "runs_scored.csv"
            slice_summary = tmp / "model_slice_summary.csv"
            manifest = tmp / "iter3_manifest.json"
            candidate_cases = tmp / "candidate_model_only_case_results.jsonl"
            baseline_cases = tmp / "baseline_model_only_case_results.jsonl"

            fieldnames, run_rows = _runs_scored_rows()
            _write_csv(runs_scored, fieldnames, run_rows)
            slice_fieldnames, slice_rows = _slice_rows()
            _write_csv(slice_summary, slice_fieldnames, slice_rows)
            manifest.write_text(json.dumps(_manifest()), encoding="utf-8")
            candidate_case_rows, baseline_case_rows = _case_rows(degrade_open=True)
            _write_jsonl(candidate_cases, candidate_case_rows)
            _write_jsonl(baseline_cases, baseline_case_rows)

            result = evaluate_iter3_release_gate(
                Iter3ReleaseGateRequest(
                    runs_scored_csv=runs_scored,
                    model_slice_summary_csv=slice_summary,
                    iter3_manifest_json=manifest,
                    candidate_model_only_case_results_jsonl=candidate_cases,
                    baseline_model_only_case_results_jsonl=baseline_cases,
                    candidate_model_id="dataset_v7_orpo_iter3",
                    output_dir=tmp,
                    seed=42,
                )
            )

            self.assertEqual(result["targeted_pattern_slice"], "model_only")
            self.assertFalse(result["targeted_pattern_pass"])
            self.assertFalse(result["targeted_pattern_checks"]["pattern_group.open_then_pick_up_object.pass_rate"])
            self.assertEqual(result["gate_status"], "fail")

    def test_iter3_release_gate_fails_on_excessive_gold_share(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runs_scored = tmp / "runs_scored.csv"
            slice_summary = tmp / "model_slice_summary.csv"
            manifest = tmp / "iter3_manifest.json"
            candidate_cases = tmp / "candidate_model_only_case_results.jsonl"
            baseline_cases = tmp / "baseline_model_only_case_results.jsonl"

            fieldnames, run_rows = _runs_scored_rows()
            _write_csv(runs_scored, fieldnames, run_rows)
            slice_fieldnames, slice_rows = _slice_rows()
            _write_csv(slice_summary, slice_fieldnames, slice_rows)
            manifest.write_text(json.dumps(_manifest(excessive_gold=True)), encoding="utf-8")
            candidate_case_rows, baseline_case_rows = _case_rows()
            _write_jsonl(candidate_cases, candidate_case_rows)
            _write_jsonl(baseline_cases, baseline_case_rows)

            result = evaluate_iter3_release_gate(
                Iter3ReleaseGateRequest(
                    runs_scored_csv=runs_scored,
                    model_slice_summary_csv=slice_summary,
                    iter3_manifest_json=manifest,
                    candidate_model_only_case_results_jsonl=candidate_cases,
                    baseline_model_only_case_results_jsonl=baseline_cases,
                    candidate_model_id="dataset_v7_orpo_iter3",
                    output_dir=tmp,
                    seed=42,
                )
            )
            self.assertEqual(result["gate_status"], "fail")
            self.assertFalse(result["manifest_pass"])
            self.assertFalse(result["manifest_checks"]["manifest.gold_chosen_share_overall"])


if __name__ == "__main__":
    unittest.main()
