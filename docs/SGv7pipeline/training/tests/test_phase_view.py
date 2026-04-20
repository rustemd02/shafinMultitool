from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from training import PhaseViewRequest, TrainingPhaseConfig, build_phase_view, default_phase_config


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _write_json(path: Path, payload: dict[str, object]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def _sft_row(
    sample_id: str,
    *,
    bucket: str,
    complexity: str,
    tokens: int,
    tier: str = "tier_b_deterministic_canonical",
    eligibility: str = "direct_sft",
) -> dict[str, object]:
    return {
        "sample_id": sample_id,
        "packaging_metadata": {
            "sample_id": sample_id,
            "difficulty_bucket": bucket,
            "complexity_class": complexity,
            "full_sequence_token_count": tokens,
            "correction_tier": tier,
            "train_eligibility": eligibility,
        },
    }


def _preference_row(
    preference_id: str,
    *,
    pattern_name: str,
    semantic_tags: list[str],
) -> dict[str, object]:
    return {
        "preference_id": preference_id,
        "packaging_metadata": {
            "pattern_name": pattern_name,
            "semantic_tags": semantic_tags,
        },
    }


class TestPhaseView(unittest.TestCase):
    def test_phase2_enforces_l_caps(self) -> None:
        rows: list[dict[str, object]] = []
        for idx in range(20):
            complexity = "L" if idx < 10 else "M"
            rows.append(
                _sft_row(
                    f"core-{idx}",
                    bucket="core",
                    complexity=complexity,
                    tokens=500 if complexity == "L" else 200,
                )
            )

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            sft = tmp / "sft_train.jsonl"
            split_manifest = tmp / "split_manifest.json"
            out = tmp / "out"
            _write_jsonl(sft, rows)
            _write_json(split_manifest, {"contract_versions_present": ["sg_v7_contract_v1"]})
            result = build_phase_view(
                PhaseViewRequest(
                    phase="phase2",
                    sft_train_jsonl=sft,
                    split_manifest_json=split_manifest,
                    output_dir=out,
                    seed=20260414,
                )
            )

            materialized = (out / "phase2_mixed_sft_sft_train.jsonl").read_text(encoding="utf-8").strip().splitlines()
            parsed = [json.loads(item) for item in materialized if item]
            l_rows = [row for row in parsed if row["packaging_metadata"]["complexity_class"] == "L"]
            total = len(parsed)
            self.assertGreater(total, 0)
            self.assertLessEqual(len(l_rows), int(total * 0.15))
            self.assertEqual(result["phase"], "phase2_mixed_sft")

    def test_phase3_enforces_reviewed_merge_caps(self) -> None:
        rows: list[dict[str, object]] = []
        for idx in range(40):
            rows.append(_sft_row(f"hard-{idx}", bucket="hard", complexity="M", tokens=220))
        for idx in range(20):
            rows.append(
                _sft_row(
                    f"reviewed-{idx}",
                    bucket="hard",
                    complexity="M",
                    tokens=220,
                    tier="tier_c_reviewed_merge",
                    eligibility="hard_or_preference_only",
                )
            )

        config = TrainingPhaseConfig(
            **{
                **default_phase_config("phase3").__dict__,
                "pool_ratios": {
                    "core_anchor": 0.10,
                    "hard_synthetic": 0.40,
                    "real_corrected_strict": 0.20,
                    "reviewed_merge_hard": 0.30,
                },
            }
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            sft = tmp / "sft_train.jsonl"
            split_manifest = tmp / "split_manifest.json"
            out = tmp / "out"
            _write_jsonl(sft, rows)
            _write_json(split_manifest, {"contract_versions_present": ["sg_v7_contract_v1"]})
            result = build_phase_view(
                PhaseViewRequest(
                    phase="phase3",
                    sft_train_jsonl=sft,
                    split_manifest_json=split_manifest,
                    output_dir=out,
                    seed=20260414,
                    phase_config=config,
                )
            )
            parsed = [
                json.loads(line)
                for line in (out / "phase3_hard_consolidation_sft_train.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            reviewed = [
                row
                for row in parsed
                if row["packaging_metadata"]["correction_tier"] == "tier_c_reviewed_merge"
            ]
            hard = [row for row in parsed if row["packaging_metadata"]["difficulty_bucket"] == "hard"]
            self.assertGreater(len(parsed), 0)
            self.assertLessEqual(len(reviewed), int(len(parsed) * 0.02))
            self.assertLessEqual(len(reviewed), int(len(hard) * 0.05))
            self.assertEqual(sum(result["counts"]["selected_by_pool"].values()), len(parsed))
            self.assertIn("selected_by_pool_pre_cap", result["counts"])
            self.assertGreaterEqual(
                result["counts"]["selected_by_pool_pre_cap"].get("reviewed_merge_hard", 0),
                result["counts"]["selected_by_pool"].get("reviewed_merge_hard", 0),
            )

    def test_phase4_enforces_pattern_caps_and_family_weights(self) -> None:
        rows: list[dict[str, object]] = []
        for idx in range(8):
            rows.append(
                _preference_row(
                    f"pref-same-{idx}",
                    pattern_name="same_type_two_marked_objects",
                    semantic_tags=["same_type_markers", "ordinal_reference"],
                )
            )
        for idx in range(4):
            rows.append(
                _preference_row(
                    f"pref-multi-{idx}",
                    pattern_name="toward_each_other_then_pass_by_marked_object_then_second_runs",
                    semantic_tags=["multi_beat", "ordinal_reference"],
                )
            )
        for idx in range(4):
            rows.append(
                _preference_row(
                    f"pref-ord-{idx}",
                    pattern_name="ordinal_first_second_third",
                    semantic_tags=["ordinal_reference"],
                )
            )

        config = TrainingPhaseConfig(
            **{
                **default_phase_config("phase4").__dict__,
                "phase4_max_pattern_share": 0.40,
                "phase4_min_family_counts": {"ordinal": 6, "three_beat": 4, "exact_marker_identity": 4},
                "phase4_family_weight_overrides": {
                    "ordinal": 1.10,
                    "three_beat": 1.20,
                    "exact_marker_identity": 1.25,
                },
            }
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            sft = tmp / "sft_train.jsonl"
            pref = tmp / "preference_train.jsonl"
            out = tmp / "out"
            _write_jsonl(sft, [_sft_row("sft-1", bucket="core", complexity="M", tokens=120)])
            _write_jsonl(pref, rows)
            result = build_phase_view(
                PhaseViewRequest(
                    phase="phase4",
                    sft_train_jsonl=sft,
                    preference_train_jsonl=pref,
                    output_dir=out,
                    seed=20260414,
                    phase_config=config,
                )
            )
            parsed = [
                json.loads(line)
                for line in (out / "phase4_preference_preference_train.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            pattern_counts: dict[str, int] = {}
            for row in parsed:
                pattern = str(row["packaging_metadata"]["pattern_name"])
                pattern_counts[pattern] = pattern_counts.get(pattern, 0) + 1
                self.assertGreaterEqual(float(row["training_weight"]), 1.0)
            self.assertLessEqual(
                pattern_counts.get("same_type_two_marked_objects", 0),
                int(len(rows) * 0.40),
            )
            self.assertGreaterEqual(result["counts"]["family_counts"]["ordinal"], 6)
            self.assertGreaterEqual(result["counts"]["family_counts"]["three_beat"], 4)
            self.assertGreaterEqual(result["counts"]["family_counts"]["exact_marker_identity"], 4)

    def test_phase4_fails_when_family_coverage_is_below_minimum(self) -> None:
        rows = [
            _preference_row(
                "pref-only-1",
                pattern_name="dialogue_only",
                semantic_tags=["dialogue"],
            )
        ]
        config = TrainingPhaseConfig(
            **{
                **default_phase_config("phase4").__dict__,
                "phase4_min_family_counts": {"ordinal": 1},
            }
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            sft = tmp / "sft_train.jsonl"
            pref = tmp / "preference_train.jsonl"
            out = tmp / "out"
            _write_jsonl(sft, [_sft_row("sft-1", bucket="core", complexity="M", tokens=120)])
            _write_jsonl(pref, rows)
            with self.assertRaises(ValueError):
                build_phase_view(
                    PhaseViewRequest(
                        phase="phase4",
                        sft_train_jsonl=sft,
                        preference_train_jsonl=pref,
                        output_dir=out,
                        seed=20260414,
                        phase_config=config,
                    )
                )


if __name__ == "__main__":
    unittest.main()
