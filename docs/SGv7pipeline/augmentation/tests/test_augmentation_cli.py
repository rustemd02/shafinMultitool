from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from collections import Counter
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[4]
DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from augmentation import AugmentationRequest, generate_augmented_variants
from augmentation.batcher import build_transform_plan
from pattern_library import generate_pattern_record, list_pattern_names
from source_generation import HeuristicParaphraser, SourceGenerationRequest, generate_source_variants


class TestAugmentationCLI(unittest.TestCase):
    def _build_source_input(self, tmp_path: Path) -> Path:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        input_jsonl = tmp_path / "graphs.jsonl"
        input_jsonl.write_text(
            json.dumps(json.loads(fixture.read_text(encoding="utf-8")), ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        return input_jsonl

    def test_generate_augmented_variants_smoke_from_track4_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            graph_input = self._build_source_input(tmp_path)
            source_output = tmp_path / "sources.jsonl"
            source_rejects = tmp_path / "source_rejects.jsonl"
            generate_source_variants(
                SourceGenerationRequest(
                    input_jsonl=graph_input,
                    output_jsonl=source_output,
                    reject_log_jsonl=source_rejects,
                    seed=20260413,
                    paraphraser_backend="heuristic",
                ),
                paraphraser=HeuristicParaphraser(),
            )

            augmentation_output = tmp_path / "augmentation.jsonl"
            augmentation_rejects = tmp_path / "augmentation_rejects.jsonl"
            result = generate_augmented_variants(
                AugmentationRequest(
                    input_jsonl=source_output,
                    output_jsonl=augmentation_output,
                    reject_log_jsonl=augmentation_rejects,
                    seed=20260413,
                    difficulty_bucket="hard",
                )
            )
            self.assertTrue(result.accepted_records)
            self.assertEqual(len(result.accepted_records), 6)
            counts = Counter(row["parent_variant_id"] for row in result.accepted_records)
            self.assertTrue(all(count <= 2 for count in counts.values()))
            row = result.accepted_records[0]
            self.assertTrue(row["variant_id"].endswith("-aug-01"))
            self.assertIn("graph_constraints", row)
            self.assertTrue(row["transform_chain"])

    def test_cli_runs_and_writes_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            graph_input = self._build_source_input(tmp_path)
            source_output = tmp_path / "sources.jsonl"
            source_rejects = tmp_path / "source_rejects.jsonl"
            generate_source_variants(
                SourceGenerationRequest(
                    input_jsonl=graph_input,
                    output_jsonl=source_output,
                    reject_log_jsonl=source_rejects,
                    seed=20260413,
                    paraphraser_backend="heuristic",
                ),
                paraphraser=HeuristicParaphraser(),
            )
            output_jsonl = tmp_path / "augmented.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            script = DOCS_ROOT / "augmentation" / "04_noise_and_morphology.py"
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--input-jsonl",
                    str(source_output),
                    "--output-jsonl",
                    str(output_jsonl),
                    "--reject-log-jsonl",
                    str(reject_jsonl),
                    "--seed",
                    "20260413",
                    "--difficulty-bucket",
                    "hard",
                ],
                check=True,
                cwd=REPO_ROOT,
            )
            rows = [json.loads(line) for line in output_jsonl.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(len(rows), 6)

    def test_same_type_conflict_blocks_risky_planning(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects",
            graph_seed=20260413,
            source_variant_key="same_type_marker_stress",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            graph_input = tmp_path / "graphs.jsonl"
            graph_input.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            source_output = tmp_path / "sources.jsonl"
            source_rejects = tmp_path / "source_rejects.jsonl"
            source_result = generate_source_variants(
                SourceGenerationRequest(
                    input_jsonl=graph_input,
                    output_jsonl=source_output,
                    reject_log_jsonl=source_rejects,
                    seed=20260413,
                    paraphraser_backend="heuristic",
                ),
                paraphraser=HeuristicParaphraser(),
            )
            self.assertTrue(source_result.accepted_records)
            plan = build_transform_plan(
                source_result.accepted_records[0],
                AugmentationRequest(
                    input_jsonl=source_output,
                    output_jsonl=tmp_path / "augmented.jsonl",
                    reject_log_jsonl=tmp_path / "rejects.jsonl",
                    seed=20260413,
                    difficulty_bucket="hard",
                    enable_risky=True,
                ),
            )
            self.assertTrue(plan)
            self.assertTrue(all("risky_transform_requested" not in item.risk_flags for item in plan))

    def test_broad_pattern_library_smoke(self) -> None:
        pattern_names = list_pattern_names()
        records = [
            generate_pattern_record(pattern_name, graph_seed=20260413 + idx)
            for idx, pattern_name in enumerate(pattern_names)
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            graph_input = tmp_path / "graphs.jsonl"
            graph_input.write_text(
                "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
                encoding="utf-8",
            )
            source_output = tmp_path / "sources.jsonl"
            source_rejects = tmp_path / "source_rejects.jsonl"
            source_result = generate_source_variants(
                SourceGenerationRequest(
                    input_jsonl=graph_input,
                    output_jsonl=source_output,
                    reject_log_jsonl=source_rejects,
                    seed=20260413,
                    paraphraser_backend="heuristic",
                ),
                paraphraser=HeuristicParaphraser(),
            )
            self.assertTrue(source_result.accepted_records)

            augmentation_output = tmp_path / "augmentation.jsonl"
            augmentation_rejects = tmp_path / "augmentation_rejects.jsonl"
            augmentation_result = generate_augmented_variants(
                AugmentationRequest(
                    input_jsonl=source_output,
                    output_jsonl=augmentation_output,
                    reject_log_jsonl=augmentation_rejects,
                    seed=20260413,
                )
            )
            self.assertTrue(augmentation_result.accepted_records)
            counts = Counter(row["parent_variant_id"] for row in augmentation_result.accepted_records)
            self.assertTrue(all(count <= 2 for count in counts.values()))
            self.assertTrue(
                any(row["pattern_name"] == "dialogue_then_small_action" for row in source_result.accepted_records)
            )
            self.assertTrue(
                any("augmentation_policy_version" in row for row in augmentation_result.accepted_records)
            )
