from __future__ import annotations

import json
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from source_generation.metadata import build_graph_constraints
from validators import ValidationRequest
from validators.semantic_critic import (
    SemanticCriticError,
    _decode_critic_payload,
    _from_payload,
    _normalize_compat_payload,
    run_semantic_critic,
)


def _request() -> ValidationRequest:
    return ValidationRequest(
        input_jsonl=Path("input.jsonl"),
        cir_jsonl=None,
        accepted_jsonl=Path("accepted.jsonl"),
        review_jsonl=Path("review.jsonl"),
        rejected_jsonl=Path("rejected.jsonl"),
        manifest_json=Path("manifest.json"),
        seed=0,
        critic_backend="heuristic",
        critic_model="heuristic",
    )


def _valid_payload() -> dict[str, object]:
    request = _request()
    return {
        "artifact_id": "critic-sample-v1",
        "execution": {
            "temperature": request.critic_temperature,
            "top_p": request.critic_top_p,
            "max_output_tokens": request.critic_max_output_tokens,
            "recomputed": False,
        },
        "verdict": "pass",
        "confidence": 0.99,
        "findings": ["Critical semantics preserved."],
        "detected_failures": [],
        "chronology_preserved": True,
        "object_grounding_preserved": True,
        "ordinal_binding_preserved": True,
        "unsupported_action_preserved": True,
        "invented_content_present": False,
        "summary": "Critical semantics preserved.",
    }


class TestSemanticCriticContracts(unittest.TestCase):
    def test_from_payload_rejects_invalid_verdict(self) -> None:
        payload = _valid_payload()
        payload["verdict"] = "PASS"
        with self.assertRaisesRegex(SemanticCriticError, "schema violation at verdict"):
            _from_payload(payload)

    def test_from_payload_rejects_out_of_taxonomy_failure_code(self) -> None:
        payload = _valid_payload()
        payload["verdict"] = "hard_fail"
        payload["detected_failures"] = ["semantic_not_a_real_code"]
        with self.assertRaisesRegex(SemanticCriticError, "schema violation at detected_failures.0"):
            _from_payload(payload)

    def test_openai_mode_falls_back_to_heuristic_on_backend_error(self) -> None:
        class AlwaysFailBackend:
            def evaluate(self, *, sample, cir_record, prompt_payload):
                raise SemanticCriticError("simulated_openai_payload_failure")

        cir_path = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        cir_record = json.loads(cir_path.read_text(encoding="utf-8"))
        sample = {
            "sample_id": cir_record["sample_id"],
            "graph_id": cir_record["sample_id"],
            "difficulty_bucket": cir_record["difficulty_bucket"],
            "source_text": "2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить.",
            "generation_pass": "base_paraphrase",
            "pattern_name": cir_record["pattern_name"],
            "graph_constraints": build_graph_constraints(cir_record),
        }
        request = ValidationRequest(
            input_jsonl=Path("input.jsonl"),
            cir_jsonl=None,
            accepted_jsonl=Path("accepted.jsonl"),
            review_jsonl=Path("review.jsonl"),
            rejected_jsonl=Path("rejected.jsonl"),
            manifest_json=Path("manifest.json"),
            seed=0,
            critic_backend="openai",
            critic_model="gpt-5.4-nano",
        )
        result = run_semantic_critic(sample, request, cir_record=cir_record, backend=AlwaysFailBackend())
        self.assertIn(result.verdict, {"pass", "soft_fail", "hard_fail"})
        self.assertEqual(result.execution["recomputed"], False)

    def test_decode_payload_with_salvage_from_markdown_fence(self) -> None:
        content = """Вот результат:
```json
{"verdict":"pass","confidence":0.99,"findings":[],"detected_failures":[],"chronology_preserved":true,"object_grounding_preserved":true,"ordinal_binding_preserved":true,"unsupported_action_preserved":true,"invented_content_present":false,"summary":"ok"}
```"""
        payload = _decode_critic_payload(content, allow_salvage=True)
        self.assertEqual(payload["verdict"], "pass")

    def test_decode_payload_without_salvage_rejects_non_json_envelope(self) -> None:
        content = """```json
{"verdict":"pass","confidence":0.99}
```"""
        with self.assertRaisesRegex(SemanticCriticError, "non-JSON"):
            _decode_critic_payload(content, allow_salvage=False)

    def test_normalize_compat_payload_maps_unknown_failure_strings(self) -> None:
        payload = {
            "verdict": "HARD_FAIL",
            "confidence": "1.7",
            "findings": "x",
            "detected_failures": ["beat_count=1 not preserved", "object_grounding lost around put_down_target"],
            "chronology_preserved": False,
            "object_grounding_preserved": False,
            "ordinal_binding_preserved": True,
            "unsupported_action_preserved": True,
            "invented_content_present": False,
            "summary": 123,
        }
        normalized = _normalize_compat_payload(payload)
        self.assertEqual(normalized["verdict"], "hard_fail")
        self.assertEqual(normalized["confidence"], 1.0)
        self.assertIn("semantic_beat_collapse", normalized["detected_failures"])
        self.assertIn("semantic_marked_object_lost", normalized["detected_failures"])

    def test_normalize_compat_payload_coerces_boolish_fields(self) -> None:
        payload = {
            "verdict": "soft-fail",
            "confidence": 0.62,
            "findings": ["x"],
            "detected_failures": [],
            "chronology_preserved": "partially",
            "object_grounding_preserved": "likely",
            "ordinal_binding_preserved": "uncertain",
            "unsupported_action_preserved": "yes",
            "invented_content_present": "no",
            "summary": "ok",
        }
        normalized = _normalize_compat_payload(payload)
        self.assertEqual(normalized["verdict"], "soft_fail")
        self.assertEqual(normalized["chronology_preserved"], False)
        self.assertEqual(normalized["object_grounding_preserved"], False)
        self.assertEqual(normalized["ordinal_binding_preserved"], False)
        self.assertEqual(normalized["unsupported_action_preserved"], True)
        self.assertEqual(normalized["invented_content_present"], False)
