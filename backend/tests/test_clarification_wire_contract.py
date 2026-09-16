"""Wire-contract guard for the clarification-answer boundary (S01, 2026-09-13).

The iOS client, the frozen OpenAPI document and the fail-closed validator must
agree on ONE body shape. Before S01 they did not: the OpenAPI document, the
Swift encoder and `validate_clarification_answer` used the bare
`ClarificationAnswer` object, while the external HTTP service expected a
`{"answer": {...}}` wrapper, so a spec-conformant client received 400.

This test pins the contract in the app repository, where all three consumers can
be checked from one place:

* OpenAPI path `/jobs/{jobId}/clarification-answer` references the frozen
  `ClarificationAnswer` component, unwrapped, with exactly the documented keys;
* the repository validator accepts that shape and rejects the legacy wrapper;
* the Swift encoder writes the same key set — pinned separately by
  `SceneGenerationClientTests.testClarificationAnswerPayloadOmitsUnsetFieldsAndMatchesFrozenSchemaKeys`
  (target of that test: same five snake_case keys, unset optionals omitted).

The service-side counterpart lives in the external backend
(`test_clarification_flow.py::test_wrapped_legacy_body_is_rejected`).
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
OPENAPI = REPO_ROOT / "backend" / "openapi-scene-v1.yaml"

SPEC = importlib.util.spec_from_file_location(
    "scene_request_limits", REPO_ROOT / "backend" / "scene_request_limits.py"
)
assert SPEC and SPEC.loader
LIMITS = importlib.util.module_from_spec(SPEC)
sys.modules["scene_request_limits"] = LIMITS
SPEC.loader.exec_module(LIMITS)

EXPECTED_PROPERTIES = {
    "clarification_id",
    "request_id",
    "epoch",
    "selected_option_id",
    "free_text",
}
EXPECTED_REQUIRED = {"clarification_id", "request_id", "epoch"}


def _openapi() -> dict:
    return yaml.safe_load(OPENAPI.read_text(encoding="utf-8"))


class ClarificationWireContractTests(unittest.TestCase):
    def test_path_references_the_frozen_unwrapped_component(self) -> None:
        document = _openapi()
        path = document["paths"]["/jobs/{jobId}/clarification-answer"]["post"]
        schema_ref = path["requestBody"]["content"]["application/json"]["schema"]["$ref"]
        self.assertEqual(schema_ref, "#/components/schemas/ClarificationAnswer")

    def test_component_shape_is_unchanged(self) -> None:
        component = _openapi()["components"]["schemas"]["ClarificationAnswer"]
        self.assertFalse(component.get("additionalProperties", True))
        self.assertEqual(set(component["properties"]), EXPECTED_PROPERTIES)
        self.assertEqual(set(component["required"]), EXPECTED_REQUIRED)

    def test_validator_accepts_the_spec_shape(self) -> None:
        payload = {
            "clarification_id": "clar_demo001",
            "request_id": "123e4567-e89b-42d3-a456-426614174000",
            "epoch": 0,
            "selected_option_id": "option_demo001",
        }
        result = LIMITS.validate_clarification_answer(payload)
        self.assertTrue(result.accepted, result.reasons)

    def test_validator_rejects_the_legacy_wrapper(self) -> None:
        wrapped = {
            "answer": {
                "clarification_id": "clar_demo001",
                "request_id": "123e4567-e89b-42d3-a456-426614174000",
                "epoch": 0,
                "selected_option_id": "option_demo001",
            }
        }
        result = LIMITS.validate_clarification_answer(wrapped)
        self.assertFalse(result.accepted, "the legacy {'answer': {...}} wrapper must not be admitted")

    def test_swift_encoder_pins_the_same_key_set(self) -> None:
        """Fail loudly if the Swift payload keys drift from this contract.

        The authoritative assertion is the Swift test named above; this cheap
        source check keeps the drift visible from the Python side too, so a
        rename cannot pass silently in one language only.
        """
        source = (
            REPO_ROOT
            / "shafinMultitool/SceneGeneratorModule/Services/SceneGenerationAPIContracts.swift"
        ).read_text(encoding="utf-8")
        block_start = source.index("struct SceneClarificationAPIPayload")
        block = source[block_start : source.index("}", block_start)]
        # Four keys are declared with an explicit wire string; `epoch` uses the
        # implicit key (same name on the wire), so it is asserted as a case.
        for key in EXPECTED_PROPERTIES - {"epoch"}:
            self.assertIn(f'"{key}"', block, f"Swift payload is missing CodingKey {key}")
        self.assertIn("case epoch", block, "Swift payload is missing the implicit `epoch` key")


if __name__ == "__main__":
    unittest.main()
