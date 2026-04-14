from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from training import CheckpointCompareError, CheckpointCompareRequest, compare_checkpoints


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _checkpoint(
    checkpoint_id: str,
    *,
    global_step: int,
    offset: float = 0.0,
    average_target_length: float = 120.0,
    preference_win_val: float | None = None,
    preference_win_test: float | None = None,
) -> dict[str, object]:
    metrics = {
        "json_valid_rate": 0.90 + offset,
        "marked_object_recall": 0.85 + offset,
        "exact_marked_object_id_accuracy": 0.82 + offset,
        "beat_count_accuracy": 0.81 + offset,
        "action_recall": 0.80 + offset,
        "described_action_precision": 0.79 + offset,
        "ordinal_actor_binding_accuracy": 0.83 + offset,
        "target_resolution_accuracy": 0.84 + offset,
        "chronology_phase_accuracy": 0.81 + offset,
        "llm_accept_rate": 0.88 + offset,
        "llm_merge_rate": 0.06 - offset,
        "llm_reject_rate": 0.04 - offset,
        "dangling_target_rate": 0.03 - offset,
        "runtime_fallback_rate": 0.11 - offset,
        "average_target_length": average_target_length,
    }
    bucket_metrics = {
        "ordinal_cases": 0.78 + offset,
        "marked_object_morphology": 0.77 + offset,
        "same_type_markers": 0.75 + offset,
        "unsupported_action_cases": 0.74 + offset,
        "three_beat_cases": 0.73 + offset,
        "exact_marker_identity_cases": 0.76 + offset,
        "reviewed_merge_cases": 0.72 + offset,
    }
    row: dict[str, object] = {
        "checkpoint_id": checkpoint_id,
        "global_step": global_step,
        "contract_drift": False,
        "metrics": metrics,
        "bucket_metrics": bucket_metrics,
    }
    if preference_win_val is not None and preference_win_test is not None:
        row["preference_metrics"] = {
            "preference_pair_win_rate_val": preference_win_val,
            "preference_pair_win_rate_test": preference_win_test,
            "preference_tie_rate_val": 0.15,
            "preference_tie_rate_test": 0.14,
        }
    return row


class TestCheckpointCompare(unittest.TestCase):
    def test_phase3_requires_explicit_reference_checkpoint(self) -> None:
        rows = [
            _checkpoint("phase2_winner", global_step=1000, offset=0.0),
            _checkpoint("phase3_ckpt_1", global_step=2000, offset=0.005),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            checkpoints = tmp / "checkpoints.jsonl"
            out = tmp / "out"
            _write_jsonl(checkpoints, rows)
            with self.assertRaises(CheckpointCompareError):
                compare_checkpoints(
                    CheckpointCompareRequest(
                        phase="phase3",
                        checkpoints_jsonl=checkpoints,
                        output_dir=out,
                        seed=20260414,
                    )
                )

    def test_phase3_requires_two_independent_positive_passes(self) -> None:
        rows = [
            _checkpoint("phase2_winner", global_step=1000, offset=0.0),
            _checkpoint("phase3_ckpt_1", global_step=2000, offset=0.005),
            _checkpoint("phase3_ckpt_2", global_step=3000, offset=0.006),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            checkpoints = tmp / "checkpoints.jsonl"
            out = tmp / "out"
            _write_jsonl(checkpoints, rows)
            result = compare_checkpoints(
                CheckpointCompareRequest(
                    phase="phase3",
                    checkpoints_jsonl=checkpoints,
                    output_dir=out,
                    seed=20260414,
                    reference_checkpoint_id="phase2_winner",
                )
            )
            self.assertEqual(result["winner_checkpoint_id"], "phase3_ckpt_2")
            table = json.loads((out / "checkpoint_table.json").read_text(encoding="utf-8"))
            statuses = {row["checkpoint_id"]: row["status"] for row in table["rows"]}
            self.assertEqual(statuses["phase3_ckpt_2"], "winner")
            compare_md = (out / "checkpoint_compare.md").read_text(encoding="utf-8")
            self.assertIn("consecutive_positive_passes", compare_md)

    def test_phase3_non_consecutive_positive_passes_do_not_promote(self) -> None:
        rows = [
            _checkpoint("phase2_winner", global_step=1000, offset=0.0),
            _checkpoint("phase3_ckpt_pos_1", global_step=2000, offset=0.005),
            _checkpoint("phase3_ckpt_negative", global_step=3000, offset=-0.001),
            _checkpoint("phase3_ckpt_pos_2", global_step=4000, offset=0.006),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            checkpoints = tmp / "checkpoints.jsonl"
            out = tmp / "out"
            _write_jsonl(checkpoints, rows)
            result = compare_checkpoints(
                CheckpointCompareRequest(
                    phase="phase3",
                    checkpoints_jsonl=checkpoints,
                    output_dir=out,
                    seed=20260414,
                    reference_checkpoint_id="phase2_winner",
                )
            )
            self.assertIsNone(result["winner_checkpoint_id"])
            table = json.loads((out / "checkpoint_table.json").read_text(encoding="utf-8"))
            rows_by_id = {row["checkpoint_id"]: row for row in table["rows"]}
            self.assertIn(
                "missing_independent_two_pass_sequence",
                rows_by_id["phase3_ckpt_pos_2"]["reasons"],
            )

    def test_phase4_materializes_preference_eval(self) -> None:
        rows = [
            _checkpoint("phase3_winner", global_step=1000, offset=0.0, preference_win_val=0.50, preference_win_test=0.51),
            _checkpoint("phase4_candidate", global_step=2000, offset=0.004, preference_win_val=0.56, preference_win_test=0.55),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            checkpoints = tmp / "checkpoints.jsonl"
            out = tmp / "out"
            _write_jsonl(checkpoints, rows)
            result = compare_checkpoints(
                CheckpointCompareRequest(
                    phase="phase4",
                    checkpoints_jsonl=checkpoints,
                    output_dir=out,
                    seed=20260414,
                    reference_checkpoint_id="phase3_winner",
                )
            )
            self.assertEqual(result["winner_checkpoint_id"], "phase4_candidate")
            pref = json.loads((out / "preference_eval.json").read_text(encoding="utf-8"))
            self.assertEqual(pref["baseline_at_entry_checkpoint_id"], "phase3_winner")
            self.assertEqual(pref["winner_checkpoint_id"], "phase4_candidate")
            self.assertTrue(pref["winner_meets_required_win_rate_gain"])

    def test_phase4_rejects_candidate_below_min_preference_gain(self) -> None:
        rows = [
            _checkpoint("phase3_winner", global_step=1000, offset=0.0, preference_win_val=0.50, preference_win_test=0.51),
            _checkpoint("phase4_candidate", global_step=2000, offset=0.004, preference_win_val=0.52, preference_win_test=0.53),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            checkpoints = tmp / "checkpoints.jsonl"
            out = tmp / "out"
            _write_jsonl(checkpoints, rows)
            result = compare_checkpoints(
                CheckpointCompareRequest(
                    phase="phase4",
                    checkpoints_jsonl=checkpoints,
                    output_dir=out,
                    seed=20260414,
                    reference_checkpoint_id="phase3_winner",
                )
            )
            self.assertIsNone(result["winner_checkpoint_id"])
            table = json.loads((out / "checkpoint_table.json").read_text(encoding="utf-8"))
            rows_by_id = {row["checkpoint_id"]: row for row in table["rows"]}
            self.assertIn(
                "insufficient_preference_pair_win_rate_gain_pp",
                rows_by_id["phase4_candidate"]["reasons"],
            )
            self.assertEqual(rows_by_id["phase4_candidate"]["status"], "rejected")

    def test_length_collapse_proxy_rejects_candidate(self) -> None:
        rows = [
            _checkpoint("phase2_winner", global_step=1000, offset=0.0, average_target_length=120.0),
            _checkpoint("phase3_length_collapse", global_step=2000, offset=0.006, average_target_length=110.0),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            checkpoints = tmp / "checkpoints.jsonl"
            out = tmp / "out"
            _write_jsonl(checkpoints, rows)
            compare_checkpoints(
                CheckpointCompareRequest(
                    phase="phase3",
                    checkpoints_jsonl=checkpoints,
                    output_dir=out,
                    seed=20260414,
                    reference_checkpoint_id="phase2_winner",
                )
            )
            table = json.loads((out / "checkpoint_table.json").read_text(encoding="utf-8"))
            rows_by_id = {row["checkpoint_id"]: row for row in table["rows"]}
            self.assertIn(
                "length_collapse:average_target_length",
                rows_by_id["phase3_length_collapse"]["reasons"],
            )


if __name__ == "__main__":
    unittest.main()
