from __future__ import annotations

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
import importlib.util
import sys

SPEC = importlib.util.spec_from_file_location(
    "scene_request_limits", REPO_ROOT / "backend/scene_request_limits.py"
)
assert SPEC and SPEC.loader
LIMITS = importlib.util.module_from_spec(SPEC)
sys.modules["scene_request_limits"] = LIMITS
SPEC.loader.exec_module(LIMITS)

HASH = "a" * 64


def base_payload(**overrides):
    payload = {
        "request_id": "123e4567-e89b-42d3-a456-426614174000",
        "client_build": "1.0 (1)",
        "schema_version": "scene-script-v1",
        "locale": "ru",
        "script_text": "МАРА подходит к столу.",
        "marked_objects": [{"canonical_id": "object_marked_deadbeef"}],
        "constraints": {"maximum_scenes": 2},
        "request_hash": HASH,
        "schema_version_backend": "scene-api-v1",
        "model_version": "scene-model-v1",
        "prompt_version": "scene-prompt-v1",
        "provider_name": "first-party-scene",
        "provider_version": "2026-09-01",
    }
    payload.update(overrides)
    return payload


class SceneRequestLimitsTests(unittest.TestCase):
    def test_valid_ru_and_en_pass(self):
        self.assertTrue(LIMITS.validate_scene_request(base_payload()).accepted)
        self.assertTrue(LIMITS.validate_scene_request(base_payload(locale="en")).accepted)

    def test_oversize_text_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(script_text="x" * 4001)).accepted
        )

    def test_unknown_field_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(surprise="nope")).accepted
        )

    def test_media_personal_fields_rejected(self):
        for field in ("camera_frame", "audio_blob", "contacts", "idfa", "file_upload"):
            with self.subTest(field=field):
                self.assertFalse(
                    LIMITS.validate_scene_request(base_payload(**{field: "x"})).accepted
                )

    def test_unsupported_locale_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(locale="de")).accepted
        )

    def test_marked_object_overflow_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(
                base_payload(marked_objects=[{"canonical_id": f"object_{i}"} for i in range(33)])
            ).accepted
        )

    def test_constraints_bound_enforced(self):
        self.assertFalse(
            LIMITS.validate_scene_request(
                base_payload(constraints={"maximum_scenes": 9})
            ).accepted
        )

    def test_bad_hash_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(request_hash="ZZZ")).accepted
        )

    def test_canonical_json_is_deterministic(self):
        a = LIMITS.canonical_request_json(base_payload())
        b = LIMITS.canonical_request_json(base_payload())
        self.assertEqual(a, b)
        reparsed = json.loads(a)
        self.assertEqual(reparsed["locale"], "ru")


if __name__ == "__main__":
    unittest.main()
