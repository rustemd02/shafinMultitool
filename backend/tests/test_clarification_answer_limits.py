from __future__ import annotations

import importlib.util
import sys
import unittest
from unittest import mock
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "scene_request_limits", REPO_ROOT / "backend/scene_request_limits.py"
)
assert SPEC and SPEC.loader
LIMITS = importlib.util.module_from_spec(SPEC)
sys.modules["scene_request_limits"] = LIMITS
SPEC.loader.exec_module(LIMITS)


def base_answer(**overrides):
    answer = {
        "clarification_id": "clar_01HX8Q3P5M",
        "request_id": "123e4567-e89b-42d3-a456-426614174000",
        "epoch": 0,
        "selected_option_id": "opt_actor_marina",
    }
    answer.update(overrides)
    return answer


class ClarificationAnswerLimitsTests(unittest.TestCase):
    def setUp(self):
        LIMITS._load_validator.cache_clear()

    def test_option_only_answer_passes(self):
        self.assertTrue(LIMITS.validate_clarification_answer(base_answer()).accepted)

    def test_free_text_only_answer_passes(self):
        answer = base_answer()
        answer.pop("selected_option_id")
        answer["free_text"] = "МАРИНА"
        self.assertTrue(LIMITS.validate_clarification_answer(answer).accepted)

    def test_option_and_free_text_answer_passes(self):
        answer = base_answer(free_text="МАРИНА")
        self.assertTrue(LIMITS.validate_clarification_answer(answer).accepted)

    def test_multibyte_free_text_at_schema_limit_passes(self):
        answer = base_answer()
        answer.pop("selected_option_id")
        answer["free_text"] = "М" * 160
        self.assertTrue(LIMITS.validate_clarification_answer(answer).accepted)

    def test_free_text_over_schema_limit_rejected(self):
        answer = base_answer()
        answer.pop("selected_option_id")
        answer["free_text"] = "М" * 161
        result = LIMITS.validate_clarification_answer(answer)
        self.assertFalse(result.accepted)
        self.assertEqual(result.reasons, ("payload does not match request schema",))

    def test_answer_without_option_or_free_text_rejected(self):
        answer = base_answer()
        answer.pop("selected_option_id")
        result = LIMITS.validate_clarification_answer(answer)
        self.assertFalse(result.accepted)
        self.assertEqual(
            result.reasons,
            ("answer carries neither selected_option_id nor free_text",),
        )

    def test_missing_required_fields_rejected(self):
        for field in ("clarification_id", "request_id", "epoch"):
            answer = base_answer()
            answer.pop(field)
            self.assertFalse(LIMITS.validate_clarification_answer(answer).accepted, field)

    def test_unknown_field_rejected(self):
        result = LIMITS.validate_clarification_answer(base_answer(extra="x"))
        self.assertFalse(result.accepted)
        self.assertEqual(result.reasons, ("payload does not match request schema",))

    def test_wrong_types_rejected(self):
        self.assertFalse(
            LIMITS.validate_clarification_answer(base_answer(epoch="zero")).accepted
        )
        self.assertFalse(
            LIMITS.validate_clarification_answer(
                base_answer(request_id="not-a-uuid")
            ).accepted
        )
        self.assertFalse(
            LIMITS.validate_clarification_answer(base_answer(epoch=-1)).accepted
        )
        self.assertFalse(
            LIMITS.validate_clarification_answer(base_answer(free_text="")).accepted
        )

    def test_non_dict_and_non_json_values_rejected_without_raise(self):
        self.assertFalse(LIMITS.validate_clarification_answer(None).accepted)
        self.assertFalse(LIMITS.validate_clarification_answer("opt_actor_marina").accepted)
        self.assertFalse(
            LIMITS.validate_clarification_answer(base_answer(nested=object())).accepted
        )

    def test_fail_closed_when_schema_file_missing(self):
        missing = REPO_ROOT / "backend" / "does-not-exist.yaml"
        LIMITS._load_validator.cache_clear()
        with mock.patch.object(LIMITS, "OPENAPI_SCHEMA_PATH", missing):
            result = LIMITS.validate_clarification_answer(base_answer())
        self.assertFalse(result.accepted)
        self.assertEqual(result.reasons, ("request schema unavailable",))

    def test_fail_closed_when_dependency_unavailable(self):
        real_import = __import__

        def blocked(name, *args, **kwargs):
            if name in {"jsonschema", "yaml", "referencing"}:
                raise ImportError(name)
            return real_import(name, *args, **kwargs)

        LIMITS._load_validator.cache_clear()
        with mock.patch("builtins.__import__", side_effect=blocked):
            result = LIMITS.validate_clarification_answer(base_answer())
        self.assertFalse(result.accepted)
        self.assertEqual(result.reasons, ("request schema unavailable",))

    def test_create_job_validation_unaffected_by_loader_generalization(self):
        import hashlib

        payload = {
            "request_id": "123e4567-e89b-42d3-a456-426614174000",
            "client_build": "1.0 (1)",
            "schema_version": "scene-script-v1",
            "locale": "ru",
            "script_text": "МАРА подходит к столу.",
            "marked_objects": [{"canonical_id": "object_marked_deadbeef"}],
            "constraints": {"maximum_scenes": 2},
            "schema_version_backend": "scene-api-v1",
            "model_version": "scene-model-v1",
            "prompt_version": "scene-prompt-v1",
            "provider_name": "first-party-scene",
            "provider_version": "2026-09-01",
        }
        payload["request_hash"] = hashlib.sha256(
            LIMITS.canonical_request_json(payload).encode("utf-8")
        ).hexdigest()
        self.assertTrue(LIMITS.validate_scene_request(payload).accepted)


if __name__ == "__main__":
    unittest.main()
