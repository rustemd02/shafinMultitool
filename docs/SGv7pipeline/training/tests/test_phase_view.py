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


if __name__ == "__main__":
    unittest.main()
