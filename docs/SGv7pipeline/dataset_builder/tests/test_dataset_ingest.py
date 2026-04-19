from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from pattern_library import generate_pattern_record

from dataset_builder import DatasetBuildError, DatasetBuildRequest, build_dataset
from dataset_builder.ingest import sanitize_source_text_for_sft


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _accepted_row(cir: dict[str, object], *, source_text: str = "2 актера идут навстречу.") -> dict[str, object]:
    return {
        "sample_id": cir["sample_id"],
        "graph_id": cir["sample_id"],
        "difficulty_bucket": cir["difficulty_bucket"],
        "source_text": source_text,
        "generation_pass": "base_paraphrase",
        "style_bucket": "clean",
        "correction_tier": "tier_b_deterministic_canonical",
        "validation_status": "accepted",
        "train_eligibility": "direct_sft",
        "contract_version": "sg_v7_contract_v1",
        "validation_report": {
            "validator_stack_version": "sgv7_validator_stack_v1",
            "recoverability_score": 95,
        },
    }


class TestDatasetIngest(unittest.TestCase):
    def test_sanitize_fixes_common_surface_grammar_artifacts(self) -> None:
        source = (
            "Первый актер и второй актёры идут навстречу друг другу. "
            "Первый Илья подходит к ближний терминал, а второй остаётся у дальний терминал. "
            "Первый открывает коробка и ждёт у стол, затем идёт к колоны."
        )
        cleaned = sanitize_source_text_for_sft(source)
        lowered = cleaned.lower()
        self.assertNotIn("первый актер и второй актёры", lowered)
        self.assertIn("первый и второй актёры", lowered)
        self.assertIn("первый актёр илья подходит", lowered)
        self.assertNotIn("к ближний", lowered)
        self.assertIn("к ближнему", lowered)
        self.assertNotIn("у дальний", lowered)
        self.assertIn("у дальнего", lowered)
        self.assertIn("открывает коробку", lowered)
        self.assertIn("у стола", lowered)
        self.assertIn("колонны", lowered)

    def test_sanitize_does_not_duplicate_actor_word_in_regular_actor_phrase(self) -> None:
        source = "Первый актёр Ира подходит к терминалу, а второй актёр остаётся у стойки."
        cleaned = sanitize_source_text_for_sft(source)
        lowered = cleaned.lower()
        self.assertIn("первый актёр ира подходит", lowered)
        self.assertNotIn("второй актёр актёр", lowered)

    def test_sanitize_drops_rows_with_replacement_character(self) -> None:
        source = "Первый актёр подходи� к терминалу, а второй остаётся у стойки."
        cleaned = sanitize_source_text_for_sft(source)
        self.assertEqual(cleaned, "")

    def test_promotion_sidecar_requires_manual_review_artifact(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=211, source_variant_key="base")
        accepted = [_accepted_row(cir)]
        promoted = [
            {
                "sample_id": cir["sample_id"],
                "review_decision": "promote_for_hard_sft",
                "reviewer": "human",
                "reviewed_at": "2026-04-13T11:30:00Z",
                "promoted_train_eligibility": "hard_or_preference_only",
            }
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            _write_jsonl(tmp_path / "promoted.jsonl", promoted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
                review_promoted_jsonl=tmp_path / "promoted.jsonl",
            )
            with self.assertRaises(DatasetBuildError):
                build_dataset(request)

    def test_hard_or_preference_only_rows_do_not_enter_sft(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=250, source_variant_key="base")
        accepted = [_accepted_row(cir)]
        accepted[0]["train_eligibility"] = "hard_or_preference_only"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
            )
            result = build_dataset(request)

        all_rows = [*result.sft_records["train"], *result.sft_records["val"], *result.sft_records["test"]]
        self.assertEqual(all_rows, [])

    def test_drops_rows_with_disallowed_source_noise(self) -> None:
        cir_rows = [
            generate_pattern_record("toward_each_other", graph_seed=311, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=312, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=313, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=314, source_variant_key="base"),
        ]
        accepted = [
            _accepted_row(cir_rows[0], source_text="Первый актер (actor_1) идёт к actor_2."),
            _accepted_row(cir_rows[1], source_text="Они идут навстречу друг другу."),
            _accepted_row(cir_rows[2], source_text="Останавливаются у object_marked_deadbeef."),
            _accepted_row(cir_rows[3], source_text="Первый актёр: ИЛЬЯ: затем затем идёт рядом с ноутбук."),
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", cir_rows)
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
                max_technical_source_share=0.40,
            )
            result = build_dataset(request)

            all_rows = [*result.sft_records["train"], *result.sft_records["val"], *result.sft_records["test"]]
            self.assertEqual(len(all_rows), 1)
            self.assertEqual(str(all_rows[0]["source_text"]), "Они идут навстречу друг другу.")

    def test_drops_rows_with_abstract_placeholder_language(self) -> None:
        cir_rows = [
            generate_pattern_record("toward_each_other", graph_seed=321, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=322, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=323, source_variant_key="base"),
        ]
        accepted = [
            _accepted_row(cir_rows[0], source_text="Третий актёр привязан к своему якорному объекту."),
            _accepted_row(cir_rows[1], source_text="Первый поднимает нужный предмет и кладёт его на нужное место."),
            _accepted_row(cir_rows[2], source_text="Они идут навстречу друг другу."),
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", cir_rows)
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
            )
            result = build_dataset(request)

            all_rows = [*result.sft_records["train"], *result.sft_records["val"], *result.sft_records["test"]]
            self.assertEqual(len(all_rows), 1)
            self.assertEqual(str(all_rows[0]["source_text"]), "Они идут навстречу друг другу.")
            self.assertEqual(result.split_manifest["surface_noise_rows"], 0)

    def test_sanitizes_meta_suffixes_in_source_text(self) -> None:
        cir = generate_pattern_record(
            "toward_each_other_then_stop_near_marked_object_then_second_runs",
            graph_seed=401,
            source_variant_key="base",
        )
        accepted = [
            _accepted_row(
                cir,
                source_text=(
                    "Первый и второй актёры идут навстречу друг другу, потом оба останавливаются рядом с компом, "
                    "и во втором актёре в конце начинает бежать — stop_phase_before_run, stop_near_then_role_shift, "
                    "marked_object_grounding, beat_count=3, second_actor_runs."
                ),
            )
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
            )
            result = build_dataset(request)
            all_rows = [*result.sft_records["train"], *result.sft_records["val"], *result.sft_records["test"]]
            self.assertEqual(len(all_rows), 1)
            cleaned = str(all_rows[0]["source_text"])
            self.assertNotIn("beat_count=", cleaned)
            self.assertNotIn("stop_near_then_role_shift", cleaned)
            self.assertNotIn("marked_object_grounding", cleaned)
            self.assertNotIn("во втором актёре", cleaned.lower())

    def test_split_manifest_tracks_quality_counters(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=501, source_variant_key="base")
        accepted = [_accepted_row(cir, source_text="Они идут навстречу друг другу.")]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
            )
            result = build_dataset(request)

        self.assertIn("counts_by_pattern_name", result.split_manifest)
        self.assertIn("technical_literal_rows", result.split_manifest)
        self.assertIn("surface_noise_rows", result.split_manifest)
        self.assertIn("bad_morphology_rows", result.split_manifest)
        self.assertIn("promoted_review_rows", result.split_manifest)
        self.assertEqual(result.split_manifest["technical_literal_rows"], 0)

    def test_enforces_lexeme_family_caps(self) -> None:
        cir_rows = [
            generate_pattern_record("toward_each_other", graph_seed=610 + idx, source_variant_key="base")
            for idx in range(12)
        ]
        accepted: list[dict[str, object]] = []
        for idx, cir in enumerate(cir_rows):
            if idx < 8:
                accepted.append(_accepted_row(cir, source_text="Они останавливаются у компа и смотрят друг на друга."))
            else:
                accepted.append(_accepted_row(cir, source_text="Они идут навстречу друг другу и останавливаются рядом."))

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", cir_rows)
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
                max_comp_family_share=0.25,
                max_notebook_family_share=1.0,
                max_smoke_family_share=1.0,
            )
            result = build_dataset(request)

        all_rows = [*result.sft_records["train"], *result.sft_records["val"], *result.sft_records["test"]]
        comp_rows = sum(1 for row in all_rows if "комп" in str(row.get("source_text", "")).lower())
        self.assertLessEqual(comp_rows, 3)
        self.assertEqual(result.split_manifest["build_config"]["max_comp_family_share"], 0.25)
