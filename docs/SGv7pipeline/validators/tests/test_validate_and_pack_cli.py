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

from source_generation.metadata import build_graph_constraints
from source_generation.prompt_builder import summarize_graph_for_source_prompt
from validators import ValidationRequest, validate_and_pack


def _fixture(name: str) -> dict[str, object]:
    path = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / name
    return json.loads(path.read_text(encoding="utf-8"))


def _candidate_from_cir(
    cir_record: dict[str, object],
    *,
    source_text: str | None = None,
    generation_pass: str = "base_paraphrase",
    correction_tier: str | None = None,
    risk_flags: list[str] | None = None,
) -> dict[str, object]:
    payload = summarize_graph_for_source_prompt(cir_record)
    result = {
        "sample_id": cir_record["sample_id"],
        "graph_id": cir_record["sample_id"],
        "difficulty_bucket": cir_record["difficulty_bucket"],
        "source_text": source_text or str(payload["canonical_source_template"]),
        "generation_pass": generation_pass,
        "pattern_name": cir_record["pattern_name"],
        "graph_constraints": build_graph_constraints(cir_record),
    }
    if correction_tier is not None:
        result["correction_tier"] = correction_tier
    if generation_pass == "base_paraphrase":
        result["acceptance"] = {"lexical_checks_passed": True, "needs_semantic_critic": True}
    if generation_pass == "augmentation":
        result["risk_flags"] = risk_flags or []
        result["validation"] = {"lexical_invariants_passed": True, "needs_semantic_validation": True}
    return result


class TestValidateAndPackCLI(unittest.TestCase):
    def test_accept_path_for_clean_tier_b_sample(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        candidate = _candidate_from_cir(
            cir_record,
            source_text="2 актёра идут навстречу друг другу, останавливаются у компа, первый курить не бросает и начинает курить.",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            request = ValidationRequest(
                input_jsonl=input_jsonl,
                cir_jsonl=cir_jsonl,
                accepted_jsonl=accepted,
                review_jsonl=review,
                rejected_jsonl=rejected,
                manifest_json=manifest,
                seed=20260413,
                critic_backend="heuristic",
                critic_model="heuristic",
            )
            result = validate_and_pack(request)
            self.assertEqual(len(result.accepted_records), 1)
            row = result.accepted_records[0]
            self.assertEqual(row["validation_status"], "accepted")
            self.assertEqual(row["train_eligibility"], "direct_sft")
            self.assertEqual(row["correction_tier"], "tier_b_deterministic_canonical")
            self.assertEqual(row["validation_report"]["critic_execution"]["recomputed"], False)

    def test_missing_graph_constraints_is_rejected(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        candidate = {
            "sample_id": cir_record["sample_id"],
            "graph_id": cir_record["sample_id"],
            "difficulty_bucket": cir_record["difficulty_bucket"],
            "source_text": "Тестовый текст.",
            "generation_pass": "base_paraphrase",
            "pattern_name": cir_record["pattern_name"],
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                )
            )
            self.assertEqual(len(result.rejected_records), 1)
            self.assertIn(
                "contract_missing_graph_constraints",
                result.rejected_records[0]["validation_report"]["reject_reasons"],
            )

    def test_graph_dangling_target_is_rejected(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        broken = json.loads(json.dumps(cir_record))
        broken["scene_graph"]["beats"][0]["actions"][0]["target_id"] = "object_marked_deadbeef"
        candidate = _candidate_from_cir(cir_record)
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(broken, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                )
            )
            self.assertEqual(len(result.rejected_records), 1)
            self.assertIn("graph_dangling_target", result.rejected_records[0]["validation_report"]["reject_reasons"])

    def test_marked_object_loss_is_rejected(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        candidate = _candidate_from_cir(cir_record, source_text="2 актёра идут навстречу друг другу и останавливаются.")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                )
            )
            self.assertEqual(len(result.rejected_records), 1)
            self.assertIn("semantic_marked_object_lost", result.rejected_records[0]["validation_report"]["reject_reasons"])

    def test_unsupported_action_loss_is_rejected(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        candidate = _candidate_from_cir(
            cir_record,
            source_text="2 актёра идут навстречу друг другу, останавливаются у компа, первый говорит.",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                )
            )
            self.assertEqual(len(result.rejected_records), 1)
            self.assertIn("semantic_unsupported_action_lost", result.rejected_records[0]["validation_report"]["reject_reasons"])

    def test_same_type_marker_conflict_goes_to_manual_review(self) -> None:
        cir_record = _fixture("ex3_same_type_two_marked_objects.json")
        candidate = _candidate_from_cir(
            cir_record,
            source_text="Первый подходит к правому стулу, второй остаётся у левого.",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                )
            )
            self.assertEqual(len(result.review_records), 1)
            self.assertIn(
                "review_same_type_marker_conflict",
                result.review_records[0]["validation_report"]["review_reasons"],
            )

    def test_persisted_soft_fail_artifact_goes_to_manual_review(self) -> None:
        cir_record = _fixture("ex4_dialogue_then_small_action.json")
        candidate = _candidate_from_cir(
            cir_record,
            source_text="Анна: Я уже отправила письмо. Борис: Тогда покажи вложение. Анна поворачивается к Борису.",
        )
        candidate["validation_report"] = {
            "critic_verdict": "soft_fail",
            "critic_model": "heuristic",
            "critic_artifact_id": "critic-soft-fail-test-v1",
            "critic_execution": {
                "temperature": 0.0,
                "top_p": 1.0,
                "max_output_tokens": 300,
                "recomputed": False,
            },
            "critic_confidence": 0.8,
            "critic_detected_failures": ["recoverability_borderline"],
            "critic_chronology_preserved": True,
            "critic_object_grounding_preserved": True,
            "critic_ordinal_binding_preserved": True,
            "critic_unsupported_action_preserved": True,
            "critic_invented_content_present": False,
            "critic_summary": "Borderline recoverability.",
            "semantic_findings": ["Borderline recoverability."],
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                )
            )
            self.assertEqual(len(result.review_records), 1)
            self.assertIn("review_critic_soft_fail", result.review_records[0]["validation_report"]["review_reasons"])

    def test_invalid_persisted_critic_payload_is_rejected(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        candidate = _candidate_from_cir(
            cir_record,
            source_text="2 актёра идут навстречу друг другу, останавливаются у компа, первый курить не бросает и начинает курить.",
        )
        candidate["validation_report"] = {
            "critic_verdict": "PASS",
            "critic_model": "heuristic",
            "critic_artifact_id": "critic-invalid-payload-v1",
            "critic_execution": {
                "temperature": 0.0,
                "top_p": 1.0,
                "max_output_tokens": 300,
                "recomputed": False,
            },
            "critic_confidence": 0.8,
            "critic_detected_failures": [],
            "critic_chronology_preserved": True,
            "critic_object_grounding_preserved": True,
            "critic_ordinal_binding_preserved": True,
            "critic_unsupported_action_preserved": True,
            "critic_invented_content_present": False,
            "critic_summary": "Malformed verdict should fail closed.",
            "semantic_findings": ["Malformed verdict should fail closed."],
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            result = validate_and_pack(
                ValidationRequest(
                    input_jsonl=input_jsonl,
                    cir_jsonl=cir_jsonl,
                    accepted_jsonl=accepted,
                    review_jsonl=review,
                    rejected_jsonl=rejected,
                    manifest_json=manifest,
                    seed=20260413,
                    critic_backend="heuristic",
                    critic_model="heuristic",
                    enable_critic=False,
                )
            )
            self.assertEqual(len(result.rejected_records), 1)
            report = result.rejected_records[0]["validation_report"]
            self.assertIn("contract_invalid_critic_payload", report["reject_reasons"])
            self.assertIn("schema violation at verdict", report["critic_error"])

    def test_cli_runs_in_heuristic_mode(self) -> None:
        cir_record = _fixture("ex1_stop_near_marked_then_first_described.json")
        candidate = _candidate_from_cir(
            cir_record,
            source_text="2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить.",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            cir_jsonl = tmp_path / "cir.jsonl"
            accepted = tmp_path / "accepted.jsonl"
            review = tmp_path / "review.jsonl"
            rejected = tmp_path / "rejected.jsonl"
            manifest = tmp_path / "manifest.json"
            input_jsonl.write_text(json.dumps(candidate, ensure_ascii=False) + "\n", encoding="utf-8")
            cir_jsonl.write_text(json.dumps(cir_record, ensure_ascii=False) + "\n", encoding="utf-8")
            script = DOCS_ROOT / "validators" / "05_validate_and_pack.py"
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--input-jsonl",
                    str(input_jsonl),
                    "--cir-jsonl",
                    str(cir_jsonl),
                    "--accepted-jsonl",
                    str(accepted),
                    "--review-jsonl",
                    str(review),
                    "--rejected-jsonl",
                    str(rejected),
                    "--manifest-json",
                    str(manifest),
                    "--seed",
                    "20260413",
                    "--critic-backend",
                    "heuristic",
                    "--critic-model",
                    "heuristic",
                ],
                check=True,
                cwd=REPO_ROOT,
            )
            accepted_rows = [json.loads(line) for line in accepted.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertTrue(accepted_rows)
            self.assertEqual(accepted_rows[0]["correction_tier"], "tier_b_deterministic_canonical")
