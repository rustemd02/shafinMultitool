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
from validators.semantic_critic import SemanticCriticError, _from_payload, run_semantic_critic


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
