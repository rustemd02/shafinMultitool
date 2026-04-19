from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from source_generation.config import SourceGenerationRequest
from source_generation.batcher import build_variant_plan
from source_generation.prompt_builder import (
    _inflect_actor_name,
    build_source_prompt,
    localized_object_aliases,
    summarize_graph_for_source_prompt,
)
from pattern_library import PATTERN_REGISTRY, generate_pattern_record


class TestPromptBuilder(unittest.TestCase):
    def test_same_type_markers_produce_disambiguation_block(self) -> None:
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
        block = clean_item.prompt_payload["same_type_disambiguation_block"]
        self.assertIsNotNone(block)
        self.assertTrue(clean_item.required_disambiguation_cues)
        self.assertIn("прав", " ".join(clean_item.required_disambiguation_cues))

    def test_near_far_same_type_markers_use_russian_disambiguation_cues(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects_near_far",
            graph_seed=1302,
            source_variant_key="same_type_marker_stress",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        block = clean_item.prompt_payload["same_type_disambiguation_block"]
        self.assertIsNotNone(block)

        entries = block["objects"]
        preferred_aliases = [entry["preferred_alias"] for entry in entries]
        self.assertTrue(any("ближ" in alias.lower() for alias in preferred_aliases))
        self.assertTrue(any("даль" in alias.lower() for alias in preferred_aliases))
        self.assertFalse(any("near " in alias.lower() or "far " in alias.lower() for alias in preferred_aliases))

        all_cues = {cue.lower() for entry in entries for cue in entry["fallback_cues"]}
        self.assertTrue(any("ближ" in cue for cue in all_cues))
        self.assertTrue(any("даль" in cue for cue in all_cues))
        self.assertFalse(any("near " in cue or "far " in cue for cue in all_cues))

    def test_same_type_markers_do_not_leak_mixed_script_aliases(self) -> None:
        obj = {
            "id": "object_marked_test",
            "name": "left monitor",
            "marker_binding": {
                "source_name": "monitor",
                "mentioned_aliases": ["left monitor", "that monitor"],
            },
        }
        aliases = [alias.lower() for alias in localized_object_aliases(obj)]
        self.assertIn("левый монитор", aliases)
        self.assertIn("монитор", aliases)
        self.assertIn("тот монитор", aliases)
        self.assertFalse(any("monitor" in alias for alias in aliases))

    def test_source_prompt_hides_pipeline_meta_language(self) -> None:
        record = generate_pattern_record(
            "toward_each_other_then_pass_by_object_then_second_runs",
            graph_seed=20260416,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        _, user_prompt = build_source_prompt(clean_item)
        lowered = user_prompt.lower()
        self.assertNotIn("pattern_name:", lowered)
        self.assertNotIn("semantic_tags:", lowered)
        self.assertNotIn("dual_motion", lowered)
        self.assertNotIn("pass_by_then_role_shift", lowered)
        self.assertNotIn("must_ground_object", lowered)
        self.assertNotIn("object_marked_", lowered)

    def test_same_type_prompt_hides_same_type_pipeline_language(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects_left_right",
            graph_seed=20260416,
            source_variant_key="same_type_marker_stress",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        _, user_prompt = build_source_prompt(clean_item)
        lowered = user_prompt.lower()
        self.assertNotIn("same_type_markers_present", lowered)
        self.assertNotIn("marker_axis:left_right", lowered)
        self.assertNotIn("type_only_resolution", lowered)
        self.assertNotIn("merge_markers", lowered)
        self.assertNotIn("drop_relative_side", lowered)

    def test_prompt_avoids_abstract_placeholder_phrases(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects_left_right",
            graph_seed=20260417,
            source_variant_key="same_type_marker_stress",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        system_prompt, user_prompt = build_source_prompt(clean_item)
        lowered = (system_prompt + "\n" + user_prompt).lower()
        self.assertNotIn("якорн", lowered)
        self.assertNotIn("нужный предмет", lowered)
        self.assertNotIn("нужное место", lowered)
        self.assertNotIn("объект-ориентир", lowered)

    def test_canonical_template_falls_back_when_registry_text_has_mixed_script(self) -> None:
        record = generate_pattern_record(
            "open_then_pick_up_object",
            graph_seed=576329,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        self.assertNotIn("кейc", clean_item.canonical_source_template.lower())
        self.assertNotRegex(clean_item.canonical_source_template, r"(?=\w*[A-Za-z])(?=\w*[А-Яа-яЁё])")

    def test_real_fixture_localizes_single_token_object_names(self) -> None:
        record = generate_pattern_record(
            "open_then_pick_up_object",
            graph_seed=576329,
            source_variant_key="base",
        )
        container_aliases = [alias.lower() for alias in localized_object_aliases(record["scene_graph"]["objects"][0])]
        item_aliases = [alias.lower() for alias in localized_object_aliases(record["scene_graph"]["objects"][1])]
        self.assertIn("кейс", container_aliases)
        self.assertNotIn("кейc", container_aliases)
        self.assertIn("папка", item_aliases)
        self.assertNotIn("folder", item_aliases)

    def test_full_prompt_hides_pattern_and_phase_labels_for_open_then_pick_up(self) -> None:
        record = generate_pattern_record(
            "open_then_pick_up_object",
            graph_seed=576329,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        system_prompt, user_prompt = build_source_prompt(clean_item)
        lowered = (system_prompt + "\n" + user_prompt).lower()
        self.assertNotIn("pattern open_then_pick_up_object", lowered)
        self.assertNotIn("open object", lowered)
        self.assertNotIn("pickup object", lowered)
        self.assertNotIn("кейc", lowered)
        self.assertNotIn("folder", lowered)
        self.assertIn("кейс", lowered)
        self.assertIn("папка", lowered)

    def test_dialogue_followup_prompt_keeps_explicit_beat_summaries(self) -> None:
        record = generate_pattern_record(
            "dialogue_then_small_action",
            graph_seed=106,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        system_prompt, user_prompt = build_source_prompt(clean_item)
        lowered = (system_prompt + "\n" + user_prompt).lower()
        self.assertNotIn("следующий шаг сцены", lowered)
        self.assertIn("смотрит на", lowered)

    def test_enter_then_put_down_prompt_keeps_enter_beat(self) -> None:
        record = generate_pattern_record(
            "enter_then_put_down_object",
            graph_seed=211,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        system_prompt, user_prompt = build_source_prompt(clean_item)
        lowered = (system_prompt + "\n" + user_prompt).lower()
        self.assertIn("входит", lowered)
        self.assertNotIn("следует отдельное действие", lowered)

    def test_give_to_third_prompt_uses_dative_recipient(self) -> None:
        record = generate_pattern_record(
            "first_pick_up_object_then_give_to_third_actor",
            graph_seed=211,
            source_variant_key="base",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        system_prompt, user_prompt = build_source_prompt(clean_item)
        lowered = (system_prompt + "\n" + user_prompt).lower()
        self.assertIn("третьему", lowered)
        self.assertNotIn("передаёт телефон третий", lowered)

    def test_marked_object_prompt_uses_noun_like_aliases_in_summary(self) -> None:
        record = generate_pattern_record(
            "toward_each_other_then_pass_by_marked_object",
            graph_seed=279899,
            source_variant_key="base",
        )
        payload = summarize_graph_for_source_prompt(record)
        summary = str(payload["graph_summary"]).lower()
        self.assertNotIn("обычные названия предметов: комп.", summary)
        self.assertNotIn("обычные названия предметов: у ", summary)
        self.assertNotIn("важно явно назвать предмет: у ", summary)

    def test_open_then_pick_up_summary_uses_object_case(self) -> None:
        record = generate_pattern_record(
            "open_then_pick_up_object",
            graph_seed=1000,
            source_variant_key="base",
        )
        payload = summarize_graph_for_source_prompt(record)
        summary = str(payload["graph_summary"]).lower()
        self.assertNotIn("открывает коробка", summary)

    def test_irregular_actor_name_inflection_keeps_pavel_grammatical(self) -> None:
        self.assertEqual(_inflect_actor_name("Павел", "nominative"), "Павел")
        self.assertEqual(_inflect_actor_name("Павел", "accusative"), "Павла")
        self.assertEqual(_inflect_actor_name("Павел", "dative"), "Павлу")

    def test_prompt_localizes_object_aliases_without_raw_english_tokens(self) -> None:
        cases = [
            ("dialogue_then_put_down_object", 104),
            ("open_then_pick_up_object", 576329),
            ("pick_up_then_put_down_object", 404),
        ]
        for pattern_name, seed in cases:
            with self.subTest(pattern_name=pattern_name):
                record = generate_pattern_record(
                    pattern_name,
                    graph_seed=seed,
                    source_variant_key=PATTERN_REGISTRY[pattern_name].allowed_source_variant_keys[0],
                )
                with tempfile.TemporaryDirectory() as tmpdir:
                    tmp_path = Path(tmpdir)
                    input_jsonl = tmp_path / "input.jsonl"
                    input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
                    request = SourceGenerationRequest(
                        input_jsonl=input_jsonl,
                        output_jsonl=tmp_path / "out.jsonl",
                        reject_log_jsonl=tmp_path / "rejects.jsonl",
                        seed=1,
                        paraphraser_backend="heuristic",
                    )
                    plan = build_variant_plan(request)
                clean_item = next(item for item in plan if item.style_bucket == "clean")
                system_prompt, user_prompt = build_source_prompt(clean_item)
                lowered = (system_prompt + "\n" + user_prompt).lower()
                self.assertNotRegex(lowered, r"\b(?:cup|bag|package|paper|folder)\b")

    def test_prompt_humanization_does_not_fall_back_to_generic_placeholders(self) -> None:
        for pattern_name, spec in PATTERN_REGISTRY.items():
            with self.subTest(pattern_name=pattern_name):
                record = generate_pattern_record(
                    pattern_name,
                    graph_seed=211,
                    source_variant_key=spec.allowed_source_variant_keys[0],
                )
                with tempfile.TemporaryDirectory() as tmpdir:
                    tmp_path = Path(tmpdir)
                    input_jsonl = tmp_path / "input.jsonl"
                    input_jsonl.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
                    request = SourceGenerationRequest(
                        input_jsonl=input_jsonl,
                        output_jsonl=tmp_path / "out.jsonl",
                        reject_log_jsonl=tmp_path / "rejects.jsonl",
                        seed=1,
                        paraphraser_backend="heuristic",
                    )
                    plan = build_variant_plan(request)
                clean_item = next(item for item in plan if item.style_bucket == "clean")
                system_prompt, user_prompt = build_source_prompt(clean_item)
                lowered = (system_prompt + "\n" + user_prompt).lower()
                self.assertNotIn("сохрани обязательный смысловой якорь сцены", lowered)
                self.assertNotIn("не теряй важное ограничение сцены", lowered)
