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

from graph_generator import GraphBuildRequest, build_graph_records


class TestGraphGeneratorCLI(unittest.TestCase):
    def test_build_graph_records_writes_manifest_and_projects_to_scene_script(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            output_jsonl = tmp_path / "graphs.jsonl"
            output_manifest = tmp_path / "graphs.manifest.json"
            request = GraphBuildRequest(
                seed=20260413,
                difficulty_bucket="core",
                total_records=8,
                pattern_names=["dialogue_only", "dialogue_then_small_action", "toward_each_other"],
                include_variants=None,
                output_jsonl=output_jsonl,
                output_manifest=output_manifest,
                refill_budget=3,
                fail_on_duplicates=False,
            )
            result = build_graph_records(request)
            self.assertEqual(len(result.records), 8)
            self.assertTrue(output_jsonl.exists())
            self.assertTrue(output_manifest.exists())

            build_scene_script = __import__("generate_dataset_v7").build_scene_script
            projected = build_scene_script(result.records[0], original_description="smoke")
            self.assertIn("beats", projected)
            self.assertIn("actors", projected)

            manifest = json.loads(output_manifest.read_text(encoding="utf-8"))
            self.assertEqual(manifest["emitted_total_records"], 8)
            self.assertEqual(manifest["pattern_registry_version"], "sg_v7_pattern_library_v1")
            self.assertIn("dedup_group_counts", manifest)
            self.assertTrue(manifest["dedup_group_counts"])
            self.assertEqual(sum(manifest["dedup_group_counts"].values()), manifest["emitted_total_records"])

    def test_cli_writes_only_requested_bucket(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script = REPO_ROOT / "docs" / "SGv7pipeline" / "graph_generator" / "01_build_pattern_graphs.py"
            output_jsonl = tmp_path / "hard.jsonl"
            output_manifest = tmp_path / "hard.manifest.json"
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--seed",
                    "20260413",
                    "--bucket",
                    "hard",
                    "--total-records",
                    "6",
                    "--output-jsonl",
                    str(output_jsonl),
                    "--output-manifest",
                    str(output_manifest),
                ],
                check=True,
                cwd=REPO_ROOT,
            )
            records = [
                json.loads(line)
                for line in output_jsonl.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            self.assertTrue(records)
            self.assertTrue(all(record["difficulty_bucket"] == "hard" for record in records))

    def test_byte_identical_output_for_same_request(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            request_a = GraphBuildRequest(
                seed=42,
                difficulty_bucket="core",
                total_records=5,
                pattern_names=["dialogue_only", "ordinal_first_second"],
                include_variants=["base", "ordinal_stress"],
                output_jsonl=tmp_path / "a.jsonl",
                output_manifest=tmp_path / "a.manifest.json",
                refill_budget=3,
                fail_on_duplicates=False,
            )
            request_b = GraphBuildRequest(
                seed=42,
                difficulty_bucket="core",
                total_records=5,
                pattern_names=["dialogue_only", "ordinal_first_second"],
                include_variants=["base", "ordinal_stress"],
                output_jsonl=tmp_path / "b.jsonl",
                output_manifest=tmp_path / "b.manifest.json",
                refill_budget=3,
                fail_on_duplicates=False,
            )
            build_graph_records(request_a)
            build_graph_records(request_b)
            self.assertEqual(
                request_a.output_jsonl.read_text(encoding="utf-8"),
                request_b.output_jsonl.read_text(encoding="utf-8"),
            )

    def test_large_core_build_refills_across_patterns(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            request = GraphBuildRequest(
                seed=20260415,
                difficulty_bucket="core",
                total_records=240,
                pattern_names=None,
                include_variants=None,
                output_jsonl=tmp_path / "core_large.jsonl",
                output_manifest=tmp_path / "core_large.manifest.json",
                refill_budget=12,
                fail_on_duplicates=False,
            )
            result = build_graph_records(request)
            self.assertEqual(len(result.records), 240)
            manifest = json.loads(request.output_manifest.read_text(encoding="utf-8"))
            self.assertEqual(manifest["requested_total_records"], 240)
            self.assertEqual(manifest["emitted_total_records"], 240)
