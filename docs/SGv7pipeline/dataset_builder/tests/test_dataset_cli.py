from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[4]
DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from pattern_library import generate_pattern_record


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _accepted_row(cir: dict[str, object], idx: int) -> dict[str, object]:
    return {
        "sample_id": cir["sample_id"],
        "graph_id": cir["sample_id"],
        "difficulty_bucket": cir["difficulty_bucket"],
        "source_text": f"Тестовый source {idx} для {cir['pattern_name']}",
        "generation_pass": "base_paraphrase",
        "style_bucket": "clean",
        "correction_tier": "tier_b_deterministic_canonical",
        "validation_status": "accepted",
        "train_eligibility": "direct_sft",
        "contract_version": "sg_v7_contract_v1",
        "validation_report": {
            "validator_stack_version": "sgv7_validator_stack_v1",
            "recoverability_score": 90 + idx,
        },
    }


class TestDatasetCLI(unittest.TestCase):
    def test_cli_materializes_preference_test_and_leakage_surface(self) -> None:
        cir_rows = [
            generate_pattern_record("toward_each_other", graph_seed=301, source_variant_key="base"),
            generate_pattern_record("toward_each_other_then_stop_near_marked_object", graph_seed=302, source_variant_key="base"),
            generate_pattern_record("dialogue_then_small_action", graph_seed=303, source_variant_key="base"),
        ]
        accepted_rows = [_accepted_row(cir, idx) for idx, cir in enumerate(cir_rows, start=1)]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            accepted = tmp_path / "accepted.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            output_dir = tmp_path / "out"
            _write_jsonl(accepted, accepted_rows)
            _write_jsonl(cir_jsonl, cir_rows)
            script = DOCS_ROOT / "dataset_builder" / "06_build_dataset_splits.py"
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--accepted-jsonl",
                    str(accepted),
                    "--cir-jsonl",
                    str(cir_jsonl),
                    "--output-dir",
                    str(output_dir),
                    "--seed",
                    "20260413",
                ],
                check=True,
                cwd=REPO_ROOT,
            )

            self.assertTrue((output_dir / "preference_test.jsonl").exists())
            leakage = json.loads((output_dir / "leakage_report.json").read_text(encoding="utf-8"))
            self.assertIn("preference_test", leakage["checked_outputs"])
            pref_manifest = json.loads((output_dir / "preference_manifest.json").read_text(encoding="utf-8"))
            self.assertIn("preference_test_coverage_status", pref_manifest)
