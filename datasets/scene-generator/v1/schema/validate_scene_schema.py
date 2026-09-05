#!/usr/bin/env python3
"""Validate the versioned SET OS Scene Generator schema fixtures.

The checker intentionally has no production/runtime imports.  JSON Schema is
used when the already-installed ``jsonschema`` package is available; the
semantic checks below remain stdlib-only and enforce the cross-record rules
JSON Schema cannot express (references, ordered history and source ranges).
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures"
SCHEMAS = {
    "input": ROOT / "scene-input-v1.schema.json",
    "script": ROOT / "scene-script-v1.schema.json",
    "output": ROOT / "scene-output-v1.schema.json",
    "clarification": ROOT / "scene-clarification-v1.schema.json",
    "annotation": ROOT / "scene-annotation-v1.schema.json",
}
SHARED_SCHEMA = ROOT / "scene-contract-v1.schema.json"

IDENTIFIER = re.compile(r"^[a-z][a-z0-9_-]{0,127}$")
REQUEST_ID = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
ENTITY_ID = re.compile(r"^[a-z][a-z0-9_-]{0,127}$")
ACTOR_ID = re.compile(r"^actor_[a-z0-9][a-z0-9_-]{0,63}$")
OBJECT_ID = re.compile(r"^(object_[a-z0-9][a-z0-9_-]{0,63}|object_marked_[a-z0-9]{8,64})$")
TARGET_ID = re.compile(
    r"^(actor_[a-z0-9][a-z0-9_-]{0,63}|object_[a-z0-9][a-z0-9_-]{0,63}|object_marked_[a-z0-9]{8,64})$"
)
BEAT_ID = re.compile(r"^beat_[a-z0-9][a-z0-9_-]{0,63}$")
ACTION_ID = re.compile(r"^action_[a-z0-9][a-z0-9_-]{0,63}$")
RELATION_ID = re.compile(r"^(rel|relation)_[a-z0-9][a-z0-9_-]{0,63}$")
MARKER_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
PROMPT_KEY = re.compile(r"^scene\.clarify\.[a-z0-9_.-]+$")
QUESTION_ID = re.compile(r"^q[0-9]+$|^q_[a-z0-9][a-z0-9_-]{0,63}$")

ACTOR_TYPES = {"human", "tiger", "lion", "dog", "cat", "bird", "generic"}
OBJECT_TYPES = {"table", "chair", "cabinet", "door", "couch", "bed", "window", "shelf", "tv", "phone", "generic"}
POSITIONS = {"left", "right", "center", "background", "foreground", "unknown"}
ACTION_TYPES = {
    "walk", "run", "stop", "turn", "approach", "pass_by", "enter", "exit", "stand", "sit",
    "lie_down", "crouch", "look_at", "pick_up", "put_down", "open", "close", "give", "talk",
    "described_action",
}
DIRECTIONS = {"left", "right", "forward", "backward", "toward_each_other", "away_from_each_other", "to_target"}
MODIFIERS = {"slowly", "quickly", "carefully"}
POSES = {"standing", "sitting", "crouching", "lying", "walking", "running"}
RELATIONS = {"near", "in_front_of", "behind", "left_of", "right_of", "between", "pass_by", "inside", "outside"}
SHOTS = {"wide", "medium", "close_up", "extreme_close_up", "over_shoulder", "two_shot"}
MOVEMENTS = {"static", "pan_left", "pan_right", "tilt_up", "tilt_down", "dolly_in", "dolly_out", "tracking", "crane_up", "crane_down"}
QUESTION_FIELDS = {"target_entity", "actor_identity", "marked_object", "scene_boundary", "action", "spatial_relation", "other"}
ISSUE_CODES = {
    "malformed", "duplicate_id", "missing_actor", "dangling_target", "missing_marked_object", "invalid_action",
    "chronology_conflict", "hallucinated_entity", "dialogue_not_in_source", "clarification_required",
    "unsupported_action", "meaning_corruption",
}


class ContractError(Exception):
    """A concise contract violation suitable for CLI output."""


def load_json(path: Path) -> Any:
    def reject_constant(value: str) -> None:
        raise ContractError(f"{path}: non-finite JSON constant {value}")

    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ContractError(f"{path}: invalid JSON: {exc}") from exc


def expect_object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{path}: expected object")
    return value


def expect_array(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise ContractError(f"{path}: expected array")
    return value


def required_keys(value: dict[str, Any], keys: set[str], path: str) -> None:
    missing = sorted(keys - set(value))
    unknown = sorted(set(value) - keys)
    if missing:
        raise ContractError(f"{path}: missing fields {', '.join(missing)}")
    if unknown:
        raise ContractError(f"{path}: unknown fields {', '.join(unknown)}")


def non_empty_text(value: Any, path: str, *, maximum: int = 65536) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContractError(f"{path}: expected non-empty string")
    if "\x00" in value:
        raise ContractError(f"{path}: NUL is not allowed")
    if len(value) > maximum:
        raise ContractError(f"{path}: exceeds {maximum} characters")
    if len(value.encode("utf-8")) > 65536:
        raise ContractError(f"{path}: exceeds 65536 UTF-8 bytes")
    return value


def short_text(value: Any, path: str) -> str:
    return non_empty_text(value, path, maximum=512)


def enum(value: Any, allowed: set[str], path: str) -> str:
    if not isinstance(value, str) or value not in allowed:
        raise ContractError(f"{path}: unsupported value {value!r}")
    return value


def identifier(value: Any, path: str, pattern: re.Pattern[str] = IDENTIFIER) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ContractError(f"{path}: invalid identifier {value!r}")
    return value


def finite_number(value: Any, path: str, *, minimum: float | None = None, maximum: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ContractError(f"{path}: expected finite number")
    if minimum is not None and value < minimum:
        raise ContractError(f"{path}: must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise ContractError(f"{path}: must be <= {maximum}")
    return float(value)


def unique(values: list[Any], path: str) -> None:
    if len(values) != len(set(values)):
        raise ContractError(f"{path}: duplicate values")


def validate_position(value: Any, path: str) -> None:
    obj = expect_object(value, path)
    required_keys(obj, {"x", "y", "z"}, path)
    for axis in ("x", "y", "z"):
        finite_number(obj[axis], f"{path}.{axis}")


def validate_marked_object(value: Any, path: str) -> str:
    obj = expect_object(value, path)
    required_keys(obj, {"id", "name", "aliases"}, path)
    marker_id = identifier(obj["id"], f"{path}.id", MARKER_ID)
    short_text(obj["name"], f"{path}.name")
    aliases = expect_array(obj["aliases"], f"{path}.aliases")
    if len(aliases) > 32:
        raise ContractError(f"{path}.aliases: too many values")
    alias_values = [short_text(item, f"{path}.aliases[{index}]") for index, item in enumerate(aliases)]
    unique(alias_values, f"{path}.aliases")
    return marker_id


def validate_scene_script(value: Any, path: str = "scene_script") -> tuple[set[str], set[str]]:
    script = expect_object(value, path)
    allowed = {
        "sceneHeading", "locationName", "interiorExterior", "timeOfDay", "actors", "objects",
        "beats", "spatialRelations", "originalDescription",
    }
    required = {"actors", "objects", "beats", "spatialRelations", "originalDescription"}
    missing = sorted(required - set(script))
    unknown = sorted(set(script) - allowed)
    if missing:
        raise ContractError(f"{path}: missing fields {', '.join(missing)}")
    if unknown:
        raise ContractError(f"{path}: unknown fields {', '.join(unknown)}")
    for field in ("sceneHeading", "locationName", "interiorExterior", "timeOfDay"):
        if field in script:
            short_text(script[field], f"{path}.{field}")
    non_empty_text(script["originalDescription"], f"{path}.originalDescription")

    actors = expect_array(script["actors"], f"{path}.actors")
    if not actors or len(actors) > 64:
        raise ContractError(f"{path}.actors: expected 1..64 actors")
    actor_ids: set[str] = set()
    for index, item in enumerate(actors):
        actor = expect_object(item, f"{path}.actors[{index}]")
        required_keys(actor, {"id", "type"} | ({"name"} if "name" in actor else set()), f"{path}.actors[{index}]")
        actor_id = identifier(actor["id"], f"{path}.actors[{index}].id", ACTOR_ID)
        if actor_id in actor_ids:
            raise ContractError(f"{path}.actors[{index}].id: duplicate {actor_id}")
        actor_ids.add(actor_id)
        enum(actor["type"], ACTOR_TYPES, f"{path}.actors[{index}].type")
        if "name" in actor:
            short_text(actor["name"], f"{path}.actors[{index}].name")

    objects = expect_array(script["objects"], f"{path}.objects")
    if len(objects) > 256:
        raise ContractError(f"{path}.objects: too many objects")
    object_ids: set[str] = set()
    for index, item in enumerate(objects):
        obj = expect_object(item, f"{path}.objects[{index}]")
        allowed_object = {"id", "type", "relativePosition"} | ({"name"} if "name" in obj else set()) | ({"detectedPosition"} if "detectedPosition" in obj else set())
        required_keys(obj, allowed_object, f"{path}.objects[{index}]")
        object_id = identifier(obj["id"], f"{path}.objects[{index}].id", OBJECT_ID)
        if object_id in object_ids:
            raise ContractError(f"{path}.objects[{index}].id: duplicate {object_id}")
        object_ids.add(object_id)
        enum(obj["type"], OBJECT_TYPES, f"{path}.objects[{index}].type")
        enum(obj["relativePosition"], POSITIONS, f"{path}.objects[{index}].relativePosition")
        if "name" in obj:
            short_text(obj["name"], f"{path}.objects[{index}].name")
        if "detectedPosition" in obj:
            validate_position(obj["detectedPosition"], f"{path}.objects[{index}].detectedPosition")

    targets = actor_ids | object_ids
    beats = expect_array(script["beats"], f"{path}.beats")
    if not beats or len(beats) > 256:
        raise ContractError(f"{path}.beats: expected 1..256 beats")
    beat_ids: set[str] = set()
    action_ids: set[str] = set()
    for beat_index, item in enumerate(beats):
        beat_path = f"{path}.beats[{beat_index}]"
        beat = expect_object(item, beat_path)
        allowed_beat = {"id", "actions"} | ({"camera"} if "camera" in beat else set()) | ({"minDuration"} if "minDuration" in beat else set())
        required_keys(beat, allowed_beat, beat_path)
        beat_id = identifier(beat["id"], f"{beat_path}.id", BEAT_ID)
        if beat_id in beat_ids:
            raise ContractError(f"{beat_path}.id: duplicate {beat_id}")
        beat_ids.add(beat_id)
        actions = expect_array(beat["actions"], f"{beat_path}.actions")
        if not actions or len(actions) > 128:
            raise ContractError(f"{beat_path}.actions: expected 1..128 actions")
        if "minDuration" in beat:
            finite_number(beat["minDuration"], f"{beat_path}.minDuration", minimum=0, maximum=86400)
        if "camera" in beat:
            camera = expect_object(beat["camera"], f"{beat_path}.camera")
            allowed_camera = {"shotType"} | ({"movement"} if "movement" in camera else set()) | ({"target"} if "target" in camera else set())
            required_keys(camera, allowed_camera, f"{beat_path}.camera")
            enum(camera["shotType"], SHOTS, f"{beat_path}.camera.shotType")
            if "movement" in camera:
                enum(camera["movement"], MOVEMENTS, f"{beat_path}.camera.movement")
            if "target" in camera:
                target = identifier(camera["target"], f"{beat_path}.camera.target", TARGET_ID)
                if target not in targets:
                    raise ContractError(f"{beat_path}.camera.target: dangling reference {target}")
        for action_index, item in enumerate(actions):
            action_path = f"{beat_path}.actions[{action_index}]"
            action = expect_object(item, action_path)
            allowed_action = {"id", "actorId", "type"}
            allowed_action |= {field for field in ("target", "direction", "modifier", "resultingPose", "holdingObject", "dialogue", "fallbackText", "sourceText") if field in action}
            required_keys(action, allowed_action, action_path)
            action_id = identifier(action["id"], f"{action_path}.id", ACTION_ID)
            if action_id in action_ids:
                raise ContractError(f"{action_path}.id: duplicate {action_id}")
            action_ids.add(action_id)
            actor = identifier(action["actorId"], f"{action_path}.actorId", ACTOR_ID)
            if actor not in actor_ids:
                raise ContractError(f"{action_path}.actorId: missing actor {actor}")
            action_type = enum(action["type"], ACTION_TYPES, f"{action_path}.type")
            if "target" in action:
                target = identifier(action["target"], f"{action_path}.target", TARGET_ID)
                if target not in targets:
                    raise ContractError(f"{action_path}.target: dangling reference {target}")
            if "direction" in action:
                enum(action["direction"], DIRECTIONS, f"{action_path}.direction")
            if "modifier" in action:
                enum(action["modifier"], MODIFIERS, f"{action_path}.modifier")
            if "resultingPose" in action:
                enum(action["resultingPose"], POSES, f"{action_path}.resultingPose")
            if "holdingObject" in action:
                holding = identifier(action["holdingObject"], f"{action_path}.holdingObject", OBJECT_ID)
                if holding not in object_ids:
                    raise ContractError(f"{action_path}.holdingObject: missing object {holding}")
            if "dialogue" in action:
                non_empty_text(action["dialogue"], f"{action_path}.dialogue")
            if "fallbackText" in action:
                non_empty_text(action["fallbackText"], f"{action_path}.fallbackText")
            if "sourceText" in action:
                non_empty_text(action["sourceText"], f"{action_path}.sourceText")
            if action_type == "talk" and "dialogue" not in action:
                raise ContractError(f"{action_path}: talk requires dialogue")
            if action_type == "described_action" and not {"fallbackText", "sourceText"}.issubset(action):
                raise ContractError(f"{action_path}: described_action requires fallbackText and sourceText")

    relations = expect_array(script["spatialRelations"], f"{path}.spatialRelations")
    if len(relations) > 512:
        raise ContractError(f"{path}.spatialRelations: too many relations")
    relation_ids: set[str] = set()
    for index, item in enumerate(relations):
        relation_path = f"{path}.spatialRelations[{index}]"
        relation = expect_object(item, relation_path)
        required_keys(relation, {"id", "subject", "relation", "object"}, relation_path)
        relation_id = identifier(relation["id"], f"{relation_path}.id", RELATION_ID)
        if relation_id in relation_ids:
            raise ContractError(f"{relation_path}.id: duplicate {relation_id}")
        relation_ids.add(relation_id)
        subject = identifier(relation["subject"], f"{relation_path}.subject", TARGET_ID)
        obj = identifier(relation["object"], f"{relation_path}.object", TARGET_ID)
        if subject not in targets or obj not in targets:
            raise ContractError(f"{relation_path}: dangling reference")
        enum(relation["relation"], RELATIONS, f"{relation_path}.relation")
    return actor_ids, object_ids


def validate_scene_boundary(value: Any, path: str, source_length: int) -> str:
    boundary = expect_object(value, path)
    allowed = {"id", "start", "end"} | ({"heading"} if "heading" in boundary else set())
    required_keys(boundary, allowed, path)
    boundary_id = identifier(boundary["id"], f"{path}.id")
    for field in ("start", "end"):
        if isinstance(boundary[field], bool) or not isinstance(boundary[field], int):
            raise ContractError(f"{path}.{field}: expected integer")
    if boundary["start"] < 0 or boundary["end"] <= boundary["start"] or boundary["end"] > source_length:
        raise ContractError(f"{path}: range is outside source text")
    if "heading" in boundary:
        short_text(boundary["heading"], f"{path}.heading")
    return boundary_id


def validate_boundaries(value: Any, path: str, source_text: str, *, required: bool) -> None:
    boundaries = expect_array(value, path)
    if required and not boundaries:
        raise ContractError(f"{path}: at least one boundary is required")
    if len(boundaries) > 20:
        raise ContractError(f"{path}: too many boundaries")
    ids: set[str] = set()
    previous_end = -1
    for index, item in enumerate(boundaries):
        boundary_id = validate_scene_boundary(item, f"{path}[{index}]", len(source_text))
        if boundary_id in ids:
            raise ContractError(f"{path}[{index}].id: duplicate {boundary_id}")
        ids.add(boundary_id)
        start = item["start"]
        if start < previous_end:
            raise ContractError(f"{path}[{index}]: boundaries overlap or are out of order")
        previous_end = item["end"]


def validate_input(value: Any) -> None:
    request = expect_object(value, "input")
    required_keys(request, {"request_id", "client_build", "schema_version", "locale", "script_text", "marked_objects", "constraints", "previous_job_id", "consent_version"}, "input")
    identifier(request["request_id"], "input.request_id", REQUEST_ID)
    short_text(request["client_build"], "input.client_build")
    if request["schema_version"] != "scene-script-v1":
        raise ContractError("input.schema_version: expected scene-script-v1")
    enum(request["locale"], {"ru", "en"}, "input.locale")
    script_text = non_empty_text(request["script_text"], "input.script_text")
    markers = expect_array(request["marked_objects"], "input.marked_objects")
    if len(markers) > 256:
        raise ContractError("input.marked_objects: too many markers")
    marker_ids = [validate_marked_object(item, f"input.marked_objects[{index}]") for index, item in enumerate(markers)]
    unique(marker_ids, "input.marked_objects.id")
    if "scene_boundaries" in request:
        validate_boundaries(request["scene_boundaries"], "input.scene_boundaries", script_text, required=False)
    constraints = expect_object(request["constraints"], "input.constraints")
    required_keys(constraints, {"maximum_scenes", "allow_clarification"}, "input.constraints")
    if isinstance(constraints["maximum_scenes"], bool) or not isinstance(constraints["maximum_scenes"], int) or not 1 <= constraints["maximum_scenes"] <= 20:
        raise ContractError("input.constraints.maximum_scenes: expected integer in 1..20")
    if not isinstance(constraints["allow_clarification"], bool):
        raise ContractError("input.constraints.allow_clarification: expected boolean")
    previous = request["previous_job_id"]
    if previous is not None:
        identifier(previous, "input.previous_job_id", REQUEST_ID)
    if request["consent_version"] != "scene-processing-v1":
        raise ContractError("input.consent_version: expected scene-processing-v1")


def validate_option(value: Any, path: str, candidate_ids: set[str]) -> str:
    option = expect_object(value, path)
    allowed = {"id", "label"} | ({"entity_id"} if "entity_id" in option else set())
    required_keys(option, allowed, path)
    option_id = identifier(option["id"], f"{path}.id")
    short_text(option["label"], f"{path}.label")
    if "entity_id" in option:
        entity_id = identifier(option["entity_id"], f"{path}.entity_id", ENTITY_ID)
        if entity_id not in candidate_ids:
            raise ContractError(f"{path}.entity_id: not in candidate_entity_ids")
    return option_id


def validate_question(value: Any, path: str) -> None:
    question = expect_object(value, path)
    allowed = {"id", "field", "prompt_key", "candidate_entity_ids", "allows_free_text"} | ({"options"} if "options" in question else set())
    required_keys(question, {"id", "field", "prompt_key", "candidate_entity_ids", "allows_free_text"} | ({"options"} if "options" in question else set()), path)
    identifier(question["id"], f"{path}.id", QUESTION_ID)
    enum(question["field"], QUESTION_FIELDS, f"{path}.field")
    if not isinstance(question["prompt_key"], str) or not PROMPT_KEY.fullmatch(question["prompt_key"]):
        raise ContractError(f"{path}.prompt_key: invalid prompt key")
    candidates = expect_array(question["candidate_entity_ids"], f"{path}.candidate_entity_ids")
    if not candidates or len(candidates) > 32:
        raise ContractError(f"{path}.candidate_entity_ids: expected 1..32 values")
    candidate_ids = [identifier(item, f"{path}.candidate_entity_ids[{index}]", ENTITY_ID) for index, item in enumerate(candidates)]
    unique(candidate_ids, f"{path}.candidate_entity_ids")
    candidate_id_set = set(candidate_ids)
    if not isinstance(question["allows_free_text"], bool):
        raise ContractError(f"{path}.allows_free_text: expected boolean")
    if "options" in question:
        options = expect_array(question["options"], f"{path}.options")
        if not options or len(options) > 32:
            raise ContractError(f"{path}.options: expected 1..32 values")
        option_ids = [validate_option(item, f"{path}.options[{index}]", candidate_id_set) for index, item in enumerate(options)]
        unique(option_ids, f"{path}.options.id")
    elif question["allows_free_text"] is False:
        raise ContractError(f"{path}: non-free-text question requires options")


def validate_clarification(value: Any, path: str = "clarification") -> None:
    response = expect_object(value, path)
    required_keys(response, {"status", "questions", "schema_version"}, path)
    if response["status"] != "clarification_required":
        raise ContractError(f"{path}.status: expected clarification_required")
    if response["schema_version"] != "scene-script-v1":
        raise ContractError(f"{path}.schema_version: expected scene-script-v1")
    questions = expect_array(response["questions"], f"{path}.questions")
    if not questions or len(questions) > 8:
        raise ContractError(f"{path}.questions: expected 1..8 questions")
    ids = [identifier(item.get("id"), f"{path}.questions[{index}].id", QUESTION_ID) if isinstance(item, dict) else "" for index, item in enumerate(questions)]
    unique(ids, f"{path}.questions.id")
    for index, question in enumerate(questions):
        validate_question(question, f"{path}.questions[{index}]")


def validate_output(value: Any, path: str = "output") -> None:
    response = expect_object(value, path)
    status = response.get("status")
    if status == "complete":
        required_keys(response, {"status", "scene_script", "model_version", "prompt_version", "schema_version", "warnings"}, path)
        validate_scene_script(response["scene_script"], f"{path}.scene_script")
        short_text(response["model_version"], f"{path}.model_version")
        short_text(response["prompt_version"], f"{path}.prompt_version")
        if response["schema_version"] != "scene-script-v1":
            raise ContractError(f"{path}.schema_version: expected scene-script-v1")
        warnings = expect_array(response["warnings"], f"{path}.warnings")
        if len(warnings) > 64:
            raise ContractError(f"{path}.warnings: too many warnings")
        for index, warning in enumerate(warnings):
            short_text(warning, f"{path}.warnings[{index}]")
    elif status == "clarification_required":
        validate_clarification(response, path)
    else:
        raise ContractError(f"{path}.status: expected complete or clarification_required")


def validate_validation(value: Any, path: str) -> str:
    validation = expect_object(value, path)
    required_keys(validation, {"status", "issues"}, path)
    status = enum(validation["status"], {"valid", "invalid", "clarification_required"}, f"{path}.status")
    issues = expect_array(validation["issues"], f"{path}.issues")
    if len(issues) > 128:
        raise ContractError(f"{path}.issues: too many issues")
    for index, item in enumerate(issues):
        issue_path = f"{path}.issues[{index}]"
        issue = expect_object(item, issue_path)
        allowed = {"code", "path", "severity"} | ({"detail"} if "detail" in issue else set())
        required_keys(issue, allowed, issue_path)
        enum(issue["code"], ISSUE_CODES, f"{issue_path}.code")
        short_text(issue["path"], f"{issue_path}.path")
        enum(issue["severity"], {"error", "warning"}, f"{issue_path}.severity")
        if "detail" in issue:
            short_text(issue["detail"], f"{issue_path}.detail")
    if status == "valid" and issues:
        raise ContractError(f"{path}: valid status cannot contain issues")
    if status != "valid" and not issues:
        raise ContractError(f"{path}: non-valid status requires an issue")
    return status


def validate_annotation(value: Any, path: str = "annotation") -> None:
    annotation = expect_object(value, path)
    required_keys(annotation, {"schema_version", "annotation_id", "sample_id", "locale", "source_text", "scene_boundaries", "marked_objects", "candidates", "acceptable_variants", "forbidden_hallucinations", "gold", "votes", "review_history"}, path)
    if annotation["schema_version"] != "scene-annotation-v1":
        raise ContractError(f"{path}.schema_version: expected scene-annotation-v1")
    identifier(annotation["annotation_id"], f"{path}.annotation_id")
    identifier(annotation["sample_id"], f"{path}.sample_id")
    enum(annotation["locale"], {"ru", "en"}, f"{path}.locale")
    source_text = non_empty_text(annotation["source_text"], f"{path}.source_text")
    validate_boundaries(annotation["scene_boundaries"], f"{path}.scene_boundaries", source_text, required=True)

    markers = expect_array(annotation["marked_objects"], f"{path}.marked_objects")
    marker_ids = [validate_marked_object(item, f"{path}.marked_objects[{index}]") for index, item in enumerate(markers)]
    unique(marker_ids, f"{path}.marked_objects.id")

    candidates = expect_array(annotation["candidates"], f"{path}.candidates")
    if not candidates or len(candidates) > 32:
        raise ContractError(f"{path}.candidates: expected 1..32 candidates")
    candidate_ids: list[str] = []
    candidate_scripts: list[tuple[str, set[str]]] = []
    for index, item in enumerate(candidates):
        candidate_path = f"{path}.candidates[{index}]"
        candidate = expect_object(item, candidate_path)
        required_keys(candidate, {"candidate_id", "kind", "scene_script", "validation"}, candidate_path)
        candidate_id = identifier(candidate["candidate_id"], f"{candidate_path}.candidate_id")
        candidate_ids.append(candidate_id)
        enum(candidate["kind"], {"human", "deterministic", "model"}, f"{candidate_path}.kind")
        _, object_ids = validate_scene_script(candidate["scene_script"], f"{candidate_path}.scene_script")
        validation_status = validate_validation(candidate["validation"], f"{candidate_path}.validation")
        if validation_status == "valid":
            candidate_scripts.append((candidate_id, object_ids))
    unique(candidate_ids, f"{path}.candidates.candidate_id")

    variants = expect_array(annotation["acceptable_variants"], f"{path}.acceptable_variants")
    variant_ids: list[str] = []
    for index, item in enumerate(variants):
        variant_path = f"{path}.acceptable_variants[{index}]"
        variant = expect_object(item, variant_path)
        required_keys(variant, {"variant_id", "scene_script", "rationale"}, variant_path)
        variant_ids.append(identifier(variant["variant_id"], f"{variant_path}.variant_id"))
        validate_scene_script(variant["scene_script"], f"{variant_path}.scene_script")
        short_text(variant["rationale"], f"{variant_path}.rationale")
    unique(variant_ids, f"{path}.acceptable_variants.variant_id")

    forbidden = expect_array(annotation["forbidden_hallucinations"], f"{path}.forbidden_hallucinations")
    forbidden_ids: list[str] = []
    for index, item in enumerate(forbidden):
        forbidden_path = f"{path}.forbidden_hallucinations[{index}]"
        entry = expect_object(item, forbidden_path)
        allowed = {"id", "kind", "reason"} | ({"ref"} if "ref" in entry else set()) | ({"source_text"} if "source_text" in entry else set())
        required_keys(entry, allowed, forbidden_path)
        forbidden_ids.append(identifier(entry["id"], f"{forbidden_path}.id"))
        enum(entry["kind"], {"entity", "object", "action", "target", "relation", "dialogue", "scene"}, f"{forbidden_path}.kind")
        if "ref" in entry:
            identifier(entry["ref"], f"{forbidden_path}.ref", ENTITY_ID)
        if "source_text" in entry:
            short_text(entry["source_text"], f"{forbidden_path}.source_text")
        short_text(entry["reason"], f"{forbidden_path}.reason")
    unique(forbidden_ids, f"{path}.forbidden_hallucinations.id")

    gold = expect_object(annotation["gold"], f"{path}.gold")
    required_keys(gold, {"primary_candidate_id", "acceptable_variant_ids"}, f"{path}.gold")
    primary = identifier(gold["primary_candidate_id"], f"{path}.gold.primary_candidate_id")
    if primary not in candidate_ids:
        raise ContractError(f"{path}.gold.primary_candidate_id: unknown candidate {primary}")
    acceptable_ids = expect_array(gold["acceptable_variant_ids"], f"{path}.gold.acceptable_variant_ids")
    acceptable = [identifier(item, f"{path}.gold.acceptable_variant_ids[{index}]") for index, item in enumerate(acceptable_ids)]
    unique(acceptable, f"{path}.gold.acceptable_variant_ids")
    unknown_variants = sorted(set(acceptable) - set(variant_ids))
    if unknown_variants:
        raise ContractError(f"{path}.gold.acceptable_variant_ids: unknown variants {', '.join(unknown_variants)}")

    validate_append_only_history(annotation["votes"], f"{path}.votes", "vote", candidate_ids)
    validate_append_only_history(annotation["review_history"], f"{path}.review_history", "review", candidate_ids)

    marker_suffixes = {marker_id.lower() for marker_id in marker_ids}
    for candidate_id, object_ids in candidate_scripts:
        for object_id in object_ids:
            if not object_id.startswith("object_marked_"):
                continue
            suffix = object_id.removeprefix("object_marked_").lower()
            if suffix not in marker_suffixes and object_id.lower() not in marker_suffixes:
                raise ContractError(f"{path}.candidates[{candidate_id}]: missing marked object {object_id}")


def validate_append_only_history(value: Any, path: str, kind: str, candidate_ids: list[str]) -> None:
    entries = expect_array(value, path)
    if len(entries) > 256:
        raise ContractError(f"{path}: too many entries")
    previous_sequence = 0
    seen_ids: set[str] = set()
    for index, item in enumerate(entries):
        entry_path = f"{path}[{index}]"
        entry = expect_object(item, entry_path)
        if kind == "vote":
            allowed = {"vote_id", "sequence", "annotator_id", "candidate_id", "decision", "recorded_at"} | ({"field_paths"} if "field_paths" in entry else set()) | ({"notes"} if "notes" in entry else set())
            required_keys(entry, allowed, entry_path)
            entry_id = identifier(entry["vote_id"], f"{entry_path}.vote_id")
            enum(entry["decision"], {"accept", "reject", "abstain"}, f"{entry_path}.decision")
            if "field_paths" in entry:
                fields = expect_array(entry["field_paths"], f"{entry_path}.field_paths")
                values = [short_text(item, f"{entry_path}.field_paths[{field_index}]") for field_index, item in enumerate(fields)]
                unique(values, f"{entry_path}.field_paths")
            if "notes" in entry:
                short_text(entry["notes"], f"{entry_path}.notes")
        else:
            allowed = {"review_id", "sequence", "reviewer_id", "status", "recorded_at"} | ({"reason_codes"} if "reason_codes" in entry else set())
            required_keys(entry, allowed, entry_path)
            entry_id = identifier(entry["review_id"], f"{entry_path}.review_id")
            enum(entry["status"], {"pending", "pass", "fail", "needs_adjudication"}, f"{entry_path}.status")
            if "reason_codes" in entry:
                reasons = expect_array(entry["reason_codes"], f"{entry_path}.reason_codes")
                reason_values = [identifier(item, f"{entry_path}.reason_codes[{reason_index}]") for reason_index, item in enumerate(reasons)]
                unique(reason_values, f"{entry_path}.reason_codes")
        sequence = entry["sequence"]
        if isinstance(sequence, bool) or not isinstance(sequence, int) or sequence <= previous_sequence:
            raise ContractError(f"{entry_path}.sequence: must increase strictly")
        previous_sequence = sequence
        if entry_id in seen_ids:
            raise ContractError(f"{entry_path}: duplicate history ID {entry_id}")
        seen_ids.add(entry_id)
        identifier(entry["annotator_id"] if kind == "vote" else entry["reviewer_id"], f"{entry_path}.actor_id")
        if kind == "vote" and entry["candidate_id"] not in candidate_ids:
            raise ContractError(f"{entry_path}.candidate_id: unknown candidate {entry['candidate_id']}")
        if not isinstance(entry["recorded_at"], str):
            raise ContractError(f"{entry_path}.recorded_at: expected RFC3339 string")
        try:
            parsed = datetime.fromisoformat(entry["recorded_at"].replace("Z", "+00:00"))
        except ValueError as exc:
            raise ContractError(f"{entry_path}.recorded_at: invalid RFC3339 value") from exc
        if parsed.tzinfo is None:
            raise ContractError(f"{entry_path}.recorded_at: timezone is required")


def schema_validator(path: Path):
    """Return an optional Draft 2020-12 validator with local refs resolved."""
    try:
        from jsonschema import Draft202012Validator, FormatChecker
    except ImportError:
        return None
    schema = load_json(path)
    shared = load_json(SHARED_SCHEMA)
    canonical_shared_uri = "https://set-os.local/schemas/scene-contract-v1.schema.json"
    try:
        from referencing import Registry, Resource
    except ImportError:
        # jsonschema's legacy resolver is retained only for older installations
        # which do not ship the standalone ``referencing`` package.
        from jsonschema import RefResolver

        resolver = RefResolver(
            base_uri=path.as_uri(),
            referrer=schema,
            store={SHARED_SCHEMA.as_uri(): shared, canonical_shared_uri: shared},
        )
        return Draft202012Validator(schema, resolver=resolver, format_checker=FormatChecker())

    registry = Registry().with_resource(canonical_shared_uri, Resource.from_contents(shared))
    return Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())


def validate_json_schema(path: Path, value: Any) -> None:
    validator = schema_validator(path)
    if validator is None:
        return
    errors = sorted(validator.iter_errors(value), key=lambda error: list(error.absolute_path))
    if errors:
        error = errors[0]
        location = "/".join(str(part) for part in error.absolute_path) or "$"
        raise ContractError(f"{path.name}:{location}: {error.message}")


def validate(kind: str, value: Any) -> None:
    if kind == "input":
        validate_input(value)
    elif kind == "script":
        validate_scene_script(value)
    elif kind == "output":
        validate_output(value)
    elif kind == "clarification":
        validate_clarification(value)
    elif kind == "annotation":
        validate_annotation(value)
    else:
        raise ContractError(f"unknown fixture kind {kind}")
    validate_json_schema(SCHEMAS[kind], value)


VALID_FIXTURES = {
    "input": "input-valid-ru.json",
    "script": "script-valid-en.json",
    "output": "output-valid-complete.json",
    "clarification": "clarification-valid.json",
    "annotation": "annotation-valid.json",
}
INVALID_FIXTURES = {
    "script": "script-invalid-target.json",
    "output": "output-invalid-target.json",
    "annotation": "annotation-invalid-history.json",
}


def self_test() -> None:
    for kind, filename in VALID_FIXTURES.items():
        validate(kind, load_json(FIXTURES / filename))
    for kind, filename in INVALID_FIXTURES.items():
        try:
            validate(kind, load_json(FIXTURES / filename))
        except ContractError:
            continue
        raise ContractError(f"negative fixture unexpectedly passed: {filename}")

    complete = load_json(FIXTURES / VALID_FIXTURES["output"])
    changed = copy.deepcopy(complete)
    changed["scene_script"]["beats"][0]["actions"][0]["target"] = "object_999"
    try:
        validate("output", changed)
    except ContractError:
        pass
    else:
        raise ContractError("mutation target reference unexpectedly passed")
    print("PASS M3-023 self-test: 5 positive and 3 negative fixtures")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--kind", choices=sorted(SCHEMAS))
    parser.add_argument("path", type=Path, nargs="?")
    args = parser.parse_args(argv)
    try:
        if args.self_test:
            self_test()
            return 0
        if not args.path:
            for kind, filename in VALID_FIXTURES.items():
                validate(kind, load_json(FIXTURES / filename))
            print("PASS M3-023 positive fixture set")
            return 0
        if not args.kind:
            parser.error("--kind is required when validating a path")
        validate(args.kind, load_json(args.path))
        print(f"PASS M3-023 {args.kind}: {args.path}")
        return 0
    except ContractError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
