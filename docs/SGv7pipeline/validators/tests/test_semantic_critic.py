from __future__ import annotations

import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from validators import ValidationRequest
from validators.semantic_critic import SemanticCriticError, _from_payload


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
