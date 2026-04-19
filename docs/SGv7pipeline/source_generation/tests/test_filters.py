from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from source_generation.batcher import build_variant_plan
from source_generation.config import SourceGenerationRequest
from source_generation.filters import evaluate_candidate_text


class TestFilters(unittest.TestCase):
    def test_missing_disambiguation_cue_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex3_same_type_two_marked_objects.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Первый подходит к стулу, второй стоит рядом.",
            clean_item,
            existing_keys=set(),
        )
        self.assertIn("missing_required_disambiguation_cue", reasons)

    def test_json_like_output_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text('{"scene":"bad"}', item, existing_keys=set())
        self.assertIn("json_like_output", reasons)

    def test_technical_ids_are_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Первый актер (actor_1) подходит к object_marked_deadbeef.",
            item,
            existing_keys=set(),
        )
        self.assertIn("contains_actor_id_literal", reasons)
        self.assertIn("contains_marked_object_id_literal", reasons)

    def test_meta_language_tokens_are_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex2_pass_by_object_then_second_runs.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Два актёра делают dual_motion, потом pass_by и во втором финальный run.",
            item,
            existing_keys=set(),
        )
        self.assertIn("contains_dual_motion_marker", reasons)
        self.assertIn("contains_pass_by_token", reasons)

    def test_bad_surface_noise_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Первый актёр: ИЛЬЯ: затем затем идёт к компу. Первый актер и второй актёры идут навстречу.",
            item,
            existing_keys=set(),
        )
        self.assertIn("duplicate_speaker_label", reasons)
        self.assertIn("repeated_connector", reasons)
        self.assertIn("actor_plural_mismatch", reasons)

    def test_actor_with_named_apposition_is_not_rejected_as_awkward_ordinal_name(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex3_same_type_two_marked_objects.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Соня, первый актёр направляется к левому стеллажу, затем второй актёр Лена держится у правого стеллажа.",
            item,
            existing_keys=set(),
        )
        self.assertNotIn("awkward_ordinal_name_surface", reasons)

    def test_abstract_placeholder_language_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Первый актёр привязан к своему якорному объекту и потом кладёт нужный предмет на нужное место.",
            item,
            existing_keys=set(),
        )
        self.assertIn("abstract_anchor_placeholder", reasons)
        self.assertIn("abstract_placeholder_surface", reasons)

    def test_bad_morphology_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Первый актёр открывает коробка, затем подходит к ближний терминал и потом идёт к терминал.",
            item,
            existing_keys=set(),
        )
        self.assertIn("bad_morphology_object_case", reasons)
        self.assertIn("bad_morphology_near_far_case", reasons)

    def test_english_motion_modifiers_and_double_prepositions_are_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex2_pass_by_object_then_second_runs.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "2 актёра quickly идут навстречу друг другу и останавливаются около рядом с компом.",
            item,
            existing_keys=set(),
        )
        self.assertIn("contains_english_motion_modifier", reasons)
        self.assertIn("bad_morphology_double_preposition", reasons)
