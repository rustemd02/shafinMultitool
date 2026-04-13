from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

from jsonschema import Draft202012Validator

from cir_contract.contracts.cir_serializer import expected_sample_id, serialize_to_scenescript

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "cir_contract" / "contracts" / "cir_schema_v1.json"

_MOVEMENT_TYPES = {"walk", "run", "approach", "pass_by"}
_MODIFIER_ALLOWED_TYPES = {"walk", "run", "approach", "pass_by", "described_action"}
_TARGET_REQUIRED_TYPES = {"look_at", "pick_up", "open", "close", "approach", "put_down", "give"}
_OBJECT_TARGET_ONLY_TYPES = {"pick_up", "open", "close", "put_down"}
_ACTOR_TARGET_ONLY_TYPES = {"give"}
_HOLDING_OBJECT_REQUIRED_TYPES = {"pick_up", "put_down", "give"}


class CIRValidationError(ValueError):
    pass


def load_schema(path: Path = SCHEMA_PATH) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _iter_action_records(record: dict) -> Iterable[tuple[str, dict]]:
    beats = record["scene_graph"]["beats"]
    for beat in beats:
        beat_id = beat["id"]
        for action in beat["actions"]:
            yield beat_id, action


def _counts(record: dict) -> dict[str, int]:
    beats = record["scene_graph"]["beats"]
    return {
        "actor_count": len(record["scene_graph"]["actors"]),
        "object_count": len(record["scene_graph"]["objects"]),
        "beat_count": len(beats),
        "action_count": sum(len(beat["actions"]) for beat in beats),
        "relation_count": len(record["scene_graph"]["spatial_relations"]),
    }


def _expected_complexity(counts: dict[str, int]) -> str:
    a = counts["actor_count"]
    o = counts["object_count"]
    b = counts["beat_count"]
    x = counts["action_count"]
    if a <= 2 and o <= 1 and b <= 2 and x <= 3:
        return "S"
    if a <= 2 and o <= 2 and b <= 3 and x <= 5:
        return "M"
    if a <= 3 and o <= 2 and b <= 4 and x <= 6:
        return "L"
    raise CIRValidationError(
        f"Counts exceed CIR limits: actors={a}, objects={o}, beats={b}, actions={x}"
    )


def _validate_semantics(record: dict) -> None:
    sg = record["scene_graph"]
    actor_ids = {a["id"] for a in sg["actors"]}
    object_ids = {o["id"] for o in sg["objects"]}
    valid_targets = actor_ids | object_ids
    expected_actor_ids = {f"actor_{index}" for index in range(1, len(actor_ids) + 1)}

    if actor_ids != expected_actor_ids:
        raise CIRValidationError(
            f"Actor ids must be contiguous and canonical: expected={sorted(expected_actor_ids)} got={sorted(actor_ids)}"
        )

    # Top-level optional policy is strict for v1.
    for forbidden in ("scene_heading_stub", "location_stub", "interior_exterior_stub", "time_of_day_stub"):
        if forbidden in sg:
            raise CIRValidationError(f"{forbidden} must be omitted when top_level_optional_policy=omit_all")

    # IDs and ordering integrity.
    action_ids: set[str] = set()
    relation_ids: set[str] = set()
    for rel in sg["spatial_relations"]:
        rid = rel["id"]
        if rid in relation_ids:
            raise CIRValidationError(f"Duplicate spatial relation id: {rid}")
        relation_ids.add(rid)
        if rel["subject"] not in valid_targets:
            raise CIRValidationError(f"Unknown relation.subject target: {rel['subject']}")
        if rel["object"] not in valid_targets:
            raise CIRValidationError(f"Unknown relation.object target: {rel['object']}")

    for beat in sg["beats"]:
        if "camera" in beat and beat["camera"] is None:
            raise CIRValidationError("camera must be omitted when null")
        if "min_duration" in beat and beat["min_duration"] is None:
            raise CIRValidationError("min_duration must be omitted when null")

    for beat_id, action in _iter_action_records(record):
        action_id = action["id"]
        if action_id in action_ids:
            raise CIRValidationError(f"Duplicate action id: {action_id}")
        action_ids.add(action_id)

        atype = action["type"]
        actor_id = action["actor_id"]
        if actor_id not in actor_ids:
            raise CIRValidationError(f"{beat_id}:{action_id} actor_id not found: {actor_id}")

        target_id = action.get("target_id")
        if target_id is not None and target_id not in valid_targets:
            raise CIRValidationError(f"{beat_id}:{action_id} target_id not found: {target_id}")

        holding_object = action.get("holding_object")
        if holding_object is not None and holding_object not in object_ids:
            raise CIRValidationError(f"{beat_id}:{action_id} holding_object not found: {holding_object}")

        if atype == "talk":
            if not action.get("dialogue"):
                raise CIRValidationError(f"{beat_id}:{action_id} talk requires dialogue")
            if "described_action" in action:
                raise CIRValidationError(f"{beat_id}:{action_id} talk must not contain described_action payload")

        if atype == "described_action":
            payload = action.get("described_action")
            if not payload:
                raise CIRValidationError(f"{beat_id}:{action_id} described_action payload is required")
            if action.get("dialogue") is not None:
                raise CIRValidationError(f"{beat_id}:{action_id} described_action must not contain dialogue")

        if atype in _TARGET_REQUIRED_TYPES and not target_id:
            raise CIRValidationError(f"{beat_id}:{action_id} action.type={atype} requires target_id")

        if atype in _OBJECT_TARGET_ONLY_TYPES and target_id is not None and target_id not in object_ids:
            raise CIRValidationError(f"{beat_id}:{action_id} action.type={atype} requires object target_id")

        if atype in _ACTOR_TARGET_ONLY_TYPES and target_id is not None and target_id not in actor_ids:
            raise CIRValidationError(f"{beat_id}:{action_id} action.type={atype} requires actor target_id")

        direction = action.get("direction")
        if direction is not None and atype not in _MOVEMENT_TYPES:
            raise CIRValidationError(f"{beat_id}:{action_id} direction is not allowed for action.type={atype}")

        modifier = action.get("modifier")
        if modifier is not None and atype not in _MODIFIER_ALLOWED_TYPES:
            raise CIRValidationError(f"{beat_id}:{action_id} modifier is not allowed for action.type={atype}")

        if atype in _HOLDING_OBJECT_REQUIRED_TYPES and not holding_object:
            raise CIRValidationError(f"{beat_id}:{action_id} action.type={atype} requires holding_object")

        if atype == "pick_up" and target_id is not None and holding_object is not None and holding_object != target_id:
            raise CIRValidationError(f"{beat_id}:{action_id} pick_up holding_object must equal target_id")

    # Ordinal map checks.
    ordinal_map = sg["reference_bindings"]["ordinal_map"]
    expected_ordinal_map = {"first": "actor_1"}
    if "actor_2" in actor_ids:
        expected_ordinal_map["second"] = "actor_2"
    if "actor_3" in actor_ids:
        expected_ordinal_map["third"] = "actor_3"

    if dict(ordinal_map) != expected_ordinal_map:
        raise CIRValidationError(
            "reference_bindings.ordinal_map mismatch: "
            f"expected={expected_ordinal_map}, got={dict(ordinal_map)}"
        )

    # Marked object checks.
    marked_from_objects = {o["id"] for o in sg["objects"] if o["marker_binding"]["kind"] == "marked"}
    marked_from_bindings = set(sg["reference_bindings"]["marked_object_ids"])
    if marked_from_bindings != marked_from_objects:
        raise CIRValidationError(
            f"marked_object_ids mismatch: bindings={sorted(marked_from_bindings)} objects={sorted(marked_from_objects)}"
        )


def _validate_runtime_projection(record: dict) -> None:
    projection = record["runtime_projection"]
    if projection["top_level_optional_policy"] != "omit_all":
        raise CIRValidationError("runtime_projection.top_level_optional_policy must be omit_all for sg_v7_cir_v1")
    if projection["beat_optional_policy"] != "preserve_if_present_else_omit":
        raise CIRValidationError(
            "runtime_projection.beat_optional_policy must be preserve_if_present_else_omit for sg_v7_cir_v1"
        )

    projected = serialize_to_scenescript(record, original_description="projection check")
    for forbidden in ("sceneHeading", "locationName", "interiorExterior", "timeOfDay"):
        if forbidden in projected:
            raise CIRValidationError(f"Projected SceneScript must omit {forbidden}")
    for beat in projected["beats"]:
        if beat.get("camera") is None and "camera" in beat:
            raise CIRValidationError("Projected beat.camera must be omitted instead of null")
        if beat.get("minDuration") is None and "minDuration" in beat:
            raise CIRValidationError("Projected beat.minDuration must be omitted instead of null")


def validate_record(record: dict, schema: dict | None = None) -> None:
    schema = schema or load_schema()
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(record), key=lambda e: e.path)
    if errors:
        msg = "; ".join(f"{list(err.path)}: {err.message}" for err in errors[:5])
        raise CIRValidationError(msg)

    _validate_semantics(record)
    _validate_runtime_projection(record)

    counts = _counts(record)
    if record["budgets"] != counts:
        raise CIRValidationError(f"budgets mismatch: expected={counts}, got={record['budgets']}")

    expected_class = _expected_complexity(counts)
    if record["complexity_class"] != expected_class:
        raise CIRValidationError(
            f"complexity_class mismatch: expected={expected_class}, got={record['complexity_class']}"
        )

    sample_id = expected_sample_id(record)
    if record["sample_id"] != sample_id:
        raise CIRValidationError(f"sample_id mismatch: expected={sample_id}, got={record['sample_id']}")


def validate_file(path: Path, schema: dict | None = None) -> None:
    with path.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)
    validate_record(payload, schema=schema)
