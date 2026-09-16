from __future__ import annotations

import copy
import hashlib
import json
import math
import unittest
from unittest import mock
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

def base_payload(**overrides):
    payload = {
        "request_id": "123e4567-e89b-42d3-a456-426614174000",
        "client_build": "1.0 (1)",
        "schema_version": "scene-script-v1",
        "locale": "ru",
        "script_text": "МАРА подходит к столу.",
        "marked_objects": [{"canonical_id": "object_marked_deadbeef"}],
        "constraints": {"maximum_scenes": 2},
        "request_hash": "placeholder",
        "schema_version_backend": "scene-api-v1",
        "model_version": "scene-model-v1",
        "prompt_version": "scene-prompt-v1",
        "provider_name": "first-party-scene",
        "provider_version": "2026-09-01",
    }
    payload.update(overrides)
    if "request_hash" not in overrides:
        payload["request_hash"] = hashlib.sha256(
            LIMITS.canonical_request_json(payload).encode("utf-8")
        ).hexdigest()
    return payload


def payload_without(field):
    payload = base_payload()
    payload.pop(field)
    payload["request_hash"] = hashlib.sha256(
        LIMITS.canonical_request_json(payload).encode("utf-8")
    ).hexdigest()
    return payload


class SceneRequestLimitsTests(unittest.TestCase):
    def setUp(self):
        LIMITS._load_validator.cache_clear()

    def test_valid_ru_and_en_pass(self):
        self.assertTrue(LIMITS.validate_scene_request(base_payload()).accepted)
        self.assertTrue(LIMITS.validate_scene_request(base_payload(locale="en")).accepted)
        self.assertTrue(
            LIMITS.validate_scene_request(
                base_payload(script_text="МАРА 😀 / \u2028\x00\u001f")
            ).accepted
        )

    def test_oversize_text_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(script_text="x" * 4001)).accepted
        )

    def test_required_fields_uuid_and_versions_rejected(self):
        for field in (
            "request_id",
            "client_build",
            "schema_version",
            "locale",
            "script_text",
            "request_hash",
            "schema_version_backend",
            "model_version",
            "prompt_version",
            "provider_name",
            "provider_version",
        ):
            with self.subTest(field=field):
                payload = base_payload()
                payload.pop(field)
                self.assertFalse(LIMITS.validate_scene_request(payload).accepted)
        for field, value in (
            ("request_id", "not-a-uuid"),
            ("schema_version", "scene-script-v2"),
            ("schema_version_backend", "scene-api-v2"),
            ("client_build", ""),
            ("model_version", 3),
        ):
            with self.subTest(field=field):
                self.assertFalse(
                    LIMITS.validate_scene_request(base_payload(**{field: value})).accepted
                )

    def test_unknown_field_rejected(self):
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(surprise="nope")).accepted
        )

        self.assertFalse(
            LIMITS.validate_scene_request(
                base_payload(marked_objects=[{"canonical_id": "object", "name": "extra"}])
            ).accepted
        )

    def test_flattened_wire_format_rejected(self):
        payload = base_payload()
        payload.pop("constraints")
        payload["maximum_scenes"] = 2
        self.assertFalse(LIMITS.validate_scene_request(payload).accepted)
        self.assertFalse(
            LIMITS.validate_scene_request(
                base_payload(marked_objects=["object_marked_deadbeef"])
            ).accepted
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
        for value in (0, 9, True):
            with self.subTest(value=value):
                self.assertFalse(
                    LIMITS.validate_scene_request(
                        base_payload(constraints={"maximum_scenes": value})
                    ).accepted
                )

    def test_optional_nested_fields_allow_absence_but_not_null(self):
        for field in ("marked_objects", "constraints"):
            with self.subTest(field=field, state="absent"):
                self.assertTrue(LIMITS.validate_scene_request(payload_without(field)).accepted)
            with self.subTest(field=field, state="null"):
                self.assertFalse(
                    LIMITS.validate_scene_request(base_payload(**{field: None})).accepted
                )
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(previous_job_id=None)).accepted
        )
        self.assertFalse(
            LIMITS.validate_scene_request(
                base_payload(marked_objects=[None])
            ).accepted
        )

    def test_previous_job_id_uses_full_loaded_pattern(self):
        self.assertTrue(
            LIMITS.validate_scene_request(base_payload(previous_job_id="job_ok")).accepted
        )
        self.assertFalse(
            LIMITS.validate_scene_request(base_payload(previous_job_id="job_ok\n")).accepted
        )

    def test_marked_object_bound_enforced(self):
        self.assertFalse(
            LIMITS.validate_scene_request(
                base_payload(marked_objects=[{"canonical_id": f"object_{i}"} for i in range(33)])
            ).accepted
        )

    def test_bad_hash_rejected(self):
        for value in ("ZZZ", "A" * 64):
            with self.subTest(value=value):
                self.assertFalse(
                    LIMITS.validate_scene_request(base_payload(request_hash=value)).accepted
                )

    def test_stale_hash_after_tampering_rejected(self):
        payload = base_payload()
        payload["script_text"] = "tampered"
        self.assertFalse(LIMITS.validate_scene_request(payload).accepted)

    def test_input_unchanged(self):
        payload = base_payload(
            previous_job_id="job_ok",
            marked_objects=[{"canonical_id": "object", "extra": "rejected"}],
        )
        before = copy.deepcopy(payload)
        LIMITS.validate_scene_request(payload)
        self.assertEqual(payload, before)

    def test_non_json_values_and_surrogates_rejected_without_raise(self):
        surrogate_payload = base_payload()
        surrogate_payload["script_text"] = "\ud800"
        set_payload = base_payload()
        set_payload["marked_objects"] = [set()]
        nan_payload = base_payload()
        nan_payload["constraints"] = {"maximum_scenes": math.nan}
        invalid_payloads = ({1: "non-string key"}, surrogate_payload, set_payload, nan_payload)
        for payload in invalid_payloads:
            with self.subTest(payload_type=type(payload)):
                result = LIMITS.validate_scene_request(payload)
                self.assertFalse(result.accepted)
                self.assertTrue(result.reasons)

    def test_fail_closed_when_schema_file_missing(self):
        missing = REPO_ROOT / "backend" / "does-not-exist.yaml"
        LIMITS._load_validator.cache_clear()
        with mock.patch.object(LIMITS, "OPENAPI_SCHEMA_PATH", missing):
            result = LIMITS.validate_scene_request(base_payload())
        self.assertFalse(result.accepted)
        self.assertEqual(result.reasons, ("request schema unavailable",))

    def test_fail_closed_when_dependency_unavailable(self):
        real_import = __import__

        def blocked(name, *args, **kwargs):
            if name in {"jsonschema", "yaml", "referencing"}:
                raise ImportError(name)
            return real_import(name, *args, **kwargs)

        LIMITS._load_validator.cache_clear()
        with mock.patch(
            "builtins.__import__", side_effect=blocked
        ):
            result = LIMITS.validate_scene_request(base_payload())
        self.assertFalse(result.accepted)
        self.assertEqual(result.reasons, ("request schema unavailable",))

    def test_canonical_json_is_deterministic(self):
        payload = base_payload()
        a = LIMITS.canonical_request_json(payload)
        b = LIMITS.canonical_request_json(payload)
        self.assertEqual(a, b)
        reparsed = json.loads(a)
        self.assertEqual(reparsed["locale"], "ru")
        self.assertNotIn("request_hash", reparsed)
        self.assertIn("request_hash", payload)

    def test_canonical_json_removes_only_top_level_hash(self):
        payload = base_payload(
            surprise="preserved",
            nested={"request_hash": "nested-hash", "slash": "/", "emoji": "😀"},
        )
        before = json.loads(json.dumps(payload, ensure_ascii=False))
        canonical = json.loads(LIMITS.canonical_request_json(payload))
        self.assertEqual(payload, before)
        self.assertNotIn("request_hash", canonical)
        self.assertEqual(canonical["nested"]["request_hash"], "nested-hash")
        self.assertEqual(canonical["surprise"], "preserved")


if __name__ == "__main__":
    unittest.main()
