from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
import sys
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parents[4]
DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from pattern_library import generate_pattern_record
from source_generation import HeuristicParaphraser, SourceGenerationRequest, generate_source_variants
from source_generation.batcher import build_variant_plan


class TestSourceGeneratorCLI(unittest.TestCase):
    def test_openai_backend_can_fallback_for_required_clean_variant(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex2_pass_by_object_then_second_runs.json"

        class AlwaysBadParaphraser:
            def generate(self, *, plan_item, system_prompt: str, user_prompt: str) -> str:
                return "[]"

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(
                json.dumps(json.loads(fixture.read_text(encoding="utf-8")), ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=output_jsonl,
                reject_log_jsonl=reject_jsonl,
                seed=20260413,
                max_variants_per_graph=1,
                paraphraser_backend="openai",
                enable_clean_fallback=True,
            )
            result = generate_source_variants(request, paraphraser=AlwaysBadParaphraser())
            self.assertEqual(len(result.accepted_records), 1)
            accepted = result.accepted_records[0]
            self.assertEqual(accepted["style_bucket"], "clean")
            self.assertTrue(accepted["acceptance"].get("clean_fallback_used"))

    def test_generate_source_variants_smoke_on_real_graph_fixtures(self) -> None:
        fixtures = [
            DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json",
            DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex2_pass_by_object_then_second_runs.json",
            DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex3_same_type_two_marked_objects.json",
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(
                "".join(json.dumps(json.loads(f.read_text(encoding="utf-8")), ensure_ascii=False) + "\n" for f in fixtures),
                encoding="utf-8",
            )
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=output_jsonl,
                reject_log_jsonl=reject_jsonl,
                seed=20260413,
                paraphraser_backend="heuristic",
            )
            result = generate_source_variants(request, paraphraser=HeuristicParaphraser())

            self.assertEqual(len(result.accepted_records), 9)
            self.assertTrue(output_jsonl.exists())
            rows = [json.loads(line) for line in output_jsonl.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(len(rows), 9)
            self.assertTrue(all(row["acceptance"]["needs_semantic_critic"] for row in rows))
            self.assertIn("same_type_two_marked_objects", {row["pattern_name"] for row in rows})

    def test_cli_runs_in_heuristic_mode(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(
                json.dumps(json.loads(fixture.read_text(encoding="utf-8")), ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            script = DOCS_ROOT / "source_generation" / "02_generate_source_variants.py"
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--input-jsonl",
                    str(input_jsonl),
                    "--output-jsonl",
                    str(output_jsonl),
                    "--reject-log-jsonl",
                    str(reject_jsonl),
                    "--seed",
                    "20260413",
                    "--paraphraser-backend",
                    "heuristic",
                ],
                check=True,
                cwd=REPO_ROOT,
            )
            rows = [json.loads(line) for line in output_jsonl.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual({row["style_bucket"] for row in rows}, {"clean", "colloquial", "user_short"})

    def test_named_dialogue_fixture_does_not_force_ordinals(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex4_dialogue_then_small_action.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(
                json.dumps(json.loads(fixture.read_text(encoding="utf-8")), ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=output_jsonl,
                reject_log_jsonl=reject_jsonl,
                seed=20260413,
                paraphraser_backend="heuristic",
            )
            result = generate_source_variants(request, paraphraser=HeuristicParaphraser())
            clean = next(row for row in result.accepted_records if row["style_bucket"] == "clean")
            self.assertIn("Анна", clean["source_text"])
            self.assertIn("Борис", clean["source_text"])
            self.assertNotIn("Первый", clean["source_text"])
            self.assertNotIn("второй", clean["source_text"].lower())

    def test_morphology_stress_graph_is_covered_by_smoke_generation(self) -> None:
        record = generate_pattern_record(
            "stop_near_marked_object_then_first_described_action",
            graph_seed=20260413,
            source_variant_key="morphology_stress",
        )
        expected_surface = next(
            item.split(":", 1)[1].strip().lower()
            for item in record["scene_graph"]["must_preserve"]
            if item.startswith("morphology_surface:")
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=output_jsonl,
                reject_log_jsonl=reject_jsonl,
                seed=20260413,
                paraphraser_backend="heuristic",
            )
            result = generate_source_variants(request, paraphraser=HeuristicParaphraser())
            self.assertTrue(result.accepted_records)
            clean = next(row for row in result.accepted_records if row["style_bucket"] == "clean")
            self.assertIn(expected_surface, clean["source_text"].lower())
            self.assertNotIn("у рядом с", clean["source_text"].lower())
            self.assertNotIn("quickly", clean["source_text"].lower())

    def test_openai_parallel_workers_generate_variants(self) -> None:
        fixtures = [
            DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json",
            DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex2_pass_by_object_then_second_runs.json",
        ]

        class StyleAwareParaphraser:
            def generate(self, *, plan_item, system_prompt: str, user_prompt: str) -> str:
                return f"{plan_item.canonical_source_template} ({plan_item.style_bucket})"

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(
                "".join(json.dumps(json.loads(f.read_text(encoding="utf-8")), ensure_ascii=False) + "\n" for f in fixtures),
                encoding="utf-8",
            )
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=output_jsonl,
                reject_log_jsonl=reject_jsonl,
                seed=20260413,
                paraphraser_backend="openai",
                paraphraser_workers=3,
            )
            result = generate_source_variants(request, paraphraser=StyleAwareParaphraser())

            self.assertEqual(len(result.accepted_records), 6)
            self.assertEqual(len([row for row in result.accepted_records if row["style_bucket"] == "clean"]), 2)

    def test_missing_required_clean_variant_drops_graph_instead_of_crashing(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex2_pass_by_object_then_second_runs.json"

        class CleanAlwaysBadParaphraser:
            def generate(self, *, plan_item, system_prompt: str, user_prompt: str) -> str:
                if plan_item.style_bucket == "clean":
                    return "[]"
                return plan_item.canonical_source_template

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(
                json.dumps(json.loads(fixture.read_text(encoding="utf-8")), ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            output_jsonl = tmp_path / "sources.jsonl"
            reject_jsonl = tmp_path / "rejects.jsonl"
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=output_jsonl,
                reject_log_jsonl=reject_jsonl,
                seed=20260413,
                max_variants_per_graph=2,
                paraphraser_backend="heuristic",
                enable_clean_fallback=False,
            )
            result = generate_source_variants(request, paraphraser=CleanAlwaysBadParaphraser())

            self.assertEqual(result.accepted_records, [])
            self.assertTrue(any("required_clean_variant_generation_failed" in row["reject_reason"] for row in result.reject_records))

    def test_simple_patterns_use_reduced_variant_budget(self) -> None:
        record = generate_pattern_record(
            "dialogue_only",
            graph_seed=20260416,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "graphs.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "sources.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=20260416,
                max_variants_per_graph=3,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        self.assertEqual([item.style_bucket for item in plan], ["clean"])

    def test_user_short_heuristic_keeps_sentence_connectors_intact(self) -> None:
        plan_item = SimpleNamespace(
            style_bucket="user_short",
            canonical_source_template="2 актёра идут навстречу друг другу и проходят мимо терминала, и второй начинает бежать.",
            prompt_payload={"graph_summary": "unused"},
            required_aliases=(),
            required_disambiguation_cues=(),
            required_ordinal_tokens=(),
        )
        text = HeuristicParaphraser().generate(
            plan_item=plan_item,
            system_prompt="",
            user_prompt="",
        )
        self.assertIn("и проходят мимо терминала", text)
        self.assertIn("и второй начинает бежать", text)
