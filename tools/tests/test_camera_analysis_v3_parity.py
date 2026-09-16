#!/usr/bin/env python3
"""Independent Python conformance validator and parity suite for the
CameraAnalysis v3 draft contract (runbook package C01.a).

Authority chain
---------------
* ``docs/cameraanalysis/operations-registry.v3-draft.json`` is the
  machine-readable P01 projection of ``docs/cameraanalysis/03-domain-contracts.md``
  N6.1.  It is *not* a stable contract; stable v3 is only declared after this
  C01 conformance passes (registry field ``not_a_stable_contract``).
* The Swift validator lives in
  ``shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisV3Contracts.swift``.
* Both languages consume the *same* shared JSON fixtures
  ``tools/tests/fixtures/camera_analysis_v3_cases.json``.  A byte/JSO-equal copy
  is bundled for the Swift test at
  ``shafinMultitoolTests/Fixtures/camera_analysis_v3_cases.json``; this suite
  fails if the two copies diverge.

The validator is deliberately fail-closed: unknown enum values, unknown
operations, missing optionals, non-finite / out-of-range numbers and stale
intent revisions are rejected with a specific canonical reason.  Unknown is
never coerced to zero or to a guessed enum value.
"""

from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

# --------------------------------------------------------------------------
# Canonical constants (mirrored verbatim in the Swift validator)
# --------------------------------------------------------------------------

SCHEMA_ID = "camera-operations-registry-v3-draft"
SCHEMA_VERSION = "3.0.0-draft.1"

REPO_ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = REPO_ROOT / "docs/cameraanalysis/operations-registry.v3-draft.json"
CANONICAL_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "camera_analysis_v3_cases.json"
BUNDLED_FIXTURE = REPO_ROOT / "shafinMultitoolTests" / "Fixtures" / "camera_analysis_v3_cases.json"

# The frozen operation catalog is read from the registry in tests
# (``test_registry_operation_catalog_matches_validator``); this pinned list is
# what the Swift validator hard-codes, so a registry edit must be mirrored.
PINNED_OPERATIONS = (
    "reframe_subject",
    "change_subject_scale",
    "level_frame",
    "reposition_entity",
    "rotate_entity",
    "exclude_entity",
    "reposition_camera",
    "adjust_light",
    "adjust_exposure",
    "refocus_subject",
    "hold_steady",
    "set_capture_parameter",
    "change_lens",
    "reserve_output_region",
    "wait_for_clearance",
    "select_capture_moment",
    "maintain_subject_zone",
    "smooth_camera_motion",
    "plan_motion_endpoints",
    "clear_lens_obstruction",
)

# Operations whose id equals a frozen TechnicalQualityActionType: the entry
# must reference the existing technical action and never re-declare it
# (registry ``duplicate_ids_forbidden``).
TECHNICAL_AXIS_OPERATION_IDS = frozenset({"refocus_subject"})

STATES = frozenset({"CORRECT", "SELECT_SUBJECT", "KEEP", "WAIT", "ABSTAIN"})
PHASES = frozenset({"live", "review"})
ORIENTATIONS = frozenset({"portrait", "landscape"})
ENTITY_KINDS = frozenset({"person", "object", "group", "light"})
ENTITY_ROLES = frozenset({"target", "protected", "context"})
EVIDENCE_QUALIFICATIONS = frozenset({"qualified", "unknown"})
QUALIFICATION_STATUSES = frozenset({"qualified", "unknown"})
ARTIFACT_KINDS = frozenset({"production", "research"})
DESIRED_VALUES = frozenset({"inside_region", "increase", "decrease", "preserve"})
VERIFICATION_OUTCOMES = frozenset({"improved", "unchanged", "worse", "incomparable"})
COVERAGE_KINDS = frozenset({"single_frame", "sampled_frames", "continuous_interval"})
TEMPORAL_COVERAGE_KINDS = frozenset({"sampled_frames", "continuous_interval"})
LOCK_PARAMETERS = frozenset({"exposure_lock", "focus_lock", "white_balance_lock"})
NUMERIC_PARAMETERS = frozenset({"white_balance_kelvin", "shutter_seconds"})
CAPTURE_PARAMETERS = LOCK_PARAMETERS | NUMERIC_PARAMETERS

# Canonical rejection reasons shared with Swift.
REASON_INVALID_JSON = "invalid_json"
REASON_SCHEMA_VERSION_MISMATCH = "schema_version_mismatch"
REASON_MISSING_REQUIRED_FIELD = "missing_required_field"
REASON_UNKNOWN_ENUM_VALUE = "unknown_enum_value"
REASON_UNKNOWN_REASON_CODE = "unknown_reason_code"
REASON_UNKNOWN_OPERATION = "unknown_operation"
REASON_INVALID_ACTION_PAYLOAD = "invalid_action_payload"
REASON_NON_FINITE_NUMBER = "non_finite_number"
REASON_REGION_NOT_NUMERIC = "region_not_numeric"
REASON_REGION_NON_FINITE = "region_non_finite"
REASON_REGION_OUT_OF_RANGE = "region_out_of_range"
REASON_REGION_DEGENERATE = "region_degenerate"
REASON_ENTITY_REFERENCE_MISSING = "entity_reference_missing"
REASON_RELATION_ENDPOINT_MISSING = "relation_endpoint_missing"
REASON_DUPLICATE_ENTITY_ID = "duplicate_entity_id"
REASON_DUPLICATE_RELATION_ID = "duplicate_relation_id"
REASON_ENTITY_GRAPH_CYCLE = "entity_graph_cycle"
REASON_LABEL_NOT_IDENTITY = "label_not_identity"
REASON_FRAME_REFERENCE_MISSING = "frame_reference_missing"
REASON_TRANSFORM_REFERENCE_MISSING = "transform_reference_missing"
REASON_OUTPUT_CROP_MISMATCH = "output_crop_mismatch"
REASON_ORIENTATION_MISMATCH = "orientation_mismatch"
REASON_MIRRORING_MISMATCH = "mirroring_mismatch"
REASON_STALE_INTENT_REVISION = "stale_intent_revision"
REASON_STATE_ACTION_CONFLICT = "state_action_conflict"
REASON_REVIEW_STATE_WITH_ACTION = "review_state_with_action"
REASON_SELECTION_CANDIDATES_CONFLICT = "selection_candidates_conflict"
REASON_MISSING_QUALIFICATION = "missing_qualification"
REASON_UNQUALIFIED_EVIDENCE = "unqualified_evidence"
REASON_RESEARCH_NOT_ADMITTED = "research_not_admitted"
REASON_MISSING_TEMPORAL_EVIDENCE = "missing_temporal_evidence"
REASON_CLAIMED_IMPROVEMENT_WITHOUT_DELTA = "claimed_improvement_without_delta"
REASON_PROTECTED_REGRESSION = "protected_regression"
REASON_FROZEN_RECORD_MUTATION = "frozen_record_mutation"
REASON_IDENTITY_LOST = "identity_lost"


class ValidationError(Exception):
    """Canonical fail-closed rejection carrying a stable reason code."""

    def __init__(self, reason: str, path: str = "", detail: str = "") -> None:
        super().__init__(f"{reason} @ {path}: {detail}" if detail else f"{reason} @ {path}")
        self.reason = reason
        self.path = path
        self.detail = detail


# --------------------------------------------------------------------------
# Primitive coercion helpers.  Never clamp; never coerce unknown to zero.
# --------------------------------------------------------------------------


def _coerce_float(value):
    """Return (float_value, reason).  Bool is explicitly not a number."""
    if isinstance(value, bool):
        return None, REASON_REGION_NOT_NUMERIC
    if isinstance(value, (int, float)):
        return float(value), None
    if isinstance(value, str):
        try:
            return float(value), None
        except ValueError:
            return None, REASON_REGION_NOT_NUMERIC
    return None, REASON_REGION_NOT_NUMERIC


def _require(obj, key, path):
    if not isinstance(obj, dict) or key not in obj or obj[key] is None:
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.{key}")
    return obj[key]


def _require_str(obj, key, path):
    value = _require(obj, key, path)
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.{key}")
    return value


def _require_int(obj, key, path):
    value = _require(obj, key, path)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.{key}")
    return value


def _require_bool(obj, key, path):
    value = _require(obj, key, path)
    if not isinstance(value, bool):
        raise ValidationError(REASON_UNKNOWN_ENUM_VALUE, f"{path}.{key}")
    return value


def _require_enum(obj, key, path, allowed):
    value = _require(obj, key, path)
    if not isinstance(value, str) or value not in allowed:
        raise ValidationError(REASON_UNKNOWN_ENUM_VALUE, f"{path}.{key}")
    return value


def _finite_number(value, path):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValidationError(REASON_NON_FINITE_NUMBER, path)
    try:
        numeric = float(value)
    except ValueError:
        raise ValidationError(REASON_NON_FINITE_NUMBER, path)
    if not math.isfinite(numeric):
        raise ValidationError(REASON_NON_FINITE_NUMBER, path)
    return numeric


def _validate_region(region, path):
    """Validate a Region in the general [0,1] contract space.

    Order is deterministic and mirrored in Swift:
    missing -> not numeric -> non finite -> out of [0,1] -> degenerate ->
    overflowing origin+extent.
    """
    if not isinstance(region, dict):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, path)
    coords = {}
    for key in ("x", "y", "width", "height"):
        if key not in region or region[key] is None:
            raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.{key}")
        value, reason = _coerce_float(region[key])
        if reason is not None:
            raise ValidationError(reason, f"{path}.{key}")
        if not math.isfinite(value):
            raise ValidationError(REASON_REGION_NON_FINITE, f"{path}.{key}")
        coords[key] = value
    for key, value in coords.items():
        if value < 0.0 or value > 1.0:
            raise ValidationError(REASON_REGION_OUT_OF_RANGE, f"{path}.{key}")
    if coords["width"] <= 0.0 or coords["height"] <= 0.0:
        raise ValidationError(REASON_REGION_DEGENERATE, path)
    eps = 1e-9
    if coords["x"] + coords["width"] > 1.0 + eps or coords["y"] + coords["height"] > 1.0 + eps:
        raise ValidationError(REASON_REGION_OUT_OF_RANGE, path)
    return coords


def _contained(inner, outer, path):
    eps = 1e-9
    if (
        inner["x"] < outer["x"] - eps
        or inner["y"] < outer["y"] - eps
        or inner["x"] + inner["width"] > outer["x"] + outer["width"] + eps
        or inner["y"] + inner["height"] > outer["y"] + outer["height"] + eps
    ):
        raise ValidationError(REASON_OUTPUT_CROP_MISMATCH, path)
    return inner


def _resolve_entity(ref, entity_ids, labels, path):
    if not isinstance(ref, str) or not ref.strip():
        raise ValidationError(REASON_ENTITY_REFERENCE_MISSING, path)
    if ref in entity_ids:
        return ref
    if ref in labels:
        # A display label is not an identity; refuse rather than guess.
        raise ValidationError(REASON_LABEL_NOT_IDENTITY, path)
    raise ValidationError(REASON_ENTITY_REFERENCE_MISSING, path)


# --------------------------------------------------------------------------
# Payload validation per operation (enum/payload combinations).
# --------------------------------------------------------------------------


def _payload_target_region(payload, path, output_crop):
    region = _require(payload, "targetRegion", path)
    return _contained(_validate_region(region, f"{path}.targetRegion"), output_crop, path)


def _validate_payload(operation, payload, ctx):
    """Payload validation with payload-level faults normalized to
    ``invalid_action_payload`` (region/range faults keep their own reason)."""
    try:
        _validate_payload_inner(operation, payload, ctx)
    except ValidationError as error:
        if error.reason == REASON_MISSING_REQUIRED_FIELD:
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, error.path, error.detail)
        raise


def _validate_payload_inner(operation, payload, ctx):
    """ctx supplies entity_ids/labels/relation_ids/frame_ids/output_crop/phase."""
    path = "activeAction.payload"
    if not isinstance(payload, dict):
        raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, path)

    def enum(key, allowed):
        return _require_enum(payload, key, path, allowed)

    def entity_ref(key, required=True):
        if key not in payload or payload[key] is None:
            if required:
                raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.{key}")
            return None
        return _resolve_entity(payload[key], ctx["entity_ids"], ctx["labels"], f"{path}.{key}")

    if operation == "reframe_subject":
        _contained(_validate_region(_require(payload, "targetRegion", path), f"{path}.targetRegion"),
                   ctx["output_crop"], path)

    elif operation == "change_subject_scale":
        enum("method", {"camera_distance", "zoom"})
        enum("desired", {"larger", "smaller"})
        ratio = _finite_number(_require(payload, "targetAreaRatio", path), f"{path}.targetAreaRatio")
        if not (0.0 < ratio <= 1.0):
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.targetAreaRatio")

    elif operation == "level_frame":
        enum("rotation", {"clockwise", "counterclockwise"})
        _finite_number(_require(payload, "targetHorizonDegrees", path), f"{path}.targetHorizonDegrees")

    elif operation == "reposition_entity":
        destination = enum("destination", {"screen_goal", "relative_depth"})
        if destination == "screen_goal":
            _contained(_validate_region(_require(payload, "targetRegion", path), f"{path}.targetRegion"),
                       ctx["output_crop"], path)
            if payload.get("fixedCamera") is not True:
                raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.fixedCamera")
        else:
            _require_str(payload, "relationRef", path)
            _require_str(payload, "referencePoint", path)

    elif operation == "rotate_entity":
        has_toward = payload.get("towardEntityRef") is not None
        has_reveal = payload.get("revealRegion") is not None
        if has_toward == has_reveal:
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.toward/reveal")
        if has_toward:
            entity_ref("towardEntityRef")
        else:
            _validate_region(payload["revealRegion"], f"{path}.revealRegion")
        turn = enum("turn", {"small_probe", "measured"})
        has_angle = payload.get("angleDegrees") is not None
        if turn == "measured":
            if not has_angle:
                raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.angleDegrees")
            _finite_number(payload["angleDegrees"], f"{path}.angleDegrees")
        elif has_angle:
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.angleDegrees")

    elif operation == "exclude_entity":
        _validate_region(_require(payload, "fromRegion", path), f"{path}.fromRegion")

    elif operation == "reposition_camera":
        change = enum("change", {"raise", "lower", "lateral_probe"})
        _validate_region(_require(payload, "goalRegion", path), f"{path}.goalRegion")
        if payload.get("step") != "small_probe":
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.step")
        if change == "lateral_probe":
            enum("lateralDirection", {"left", "right"})
        elif payload.get("lateralDirection") is not None:
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.lateralDirection")

    elif operation == "adjust_light":
        change = enum("change", {"dim", "brighten", "switch_off", "add_fill", "add_background"})
        entity_ref("receiverEntityRef")
        if change in {"dim", "brighten", "switch_off"}:
            entity_ref("sourceEntityRef")

    elif operation == "adjust_exposure":
        enum("change", {"increase", "decrease"})
        if payload.get("parameter") != "exposure_bias":
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.parameter")
        if payload.get("suggestedEV") is not None:
            _finite_number(payload["suggestedEV"], f"{path}.suggestedEV")

    elif operation == "refocus_subject":
        _validate_region(_require(payload, "focusRegion", path), f"{path}.focusRegion")

    elif operation == "hold_steady":
        _require_str(payload, "windowPolicyRef", path)

    elif operation == "set_capture_parameter":
        parameter = enum("parameter", CAPTURE_PARAMETERS)
        if "value" not in payload or payload["value"] is None:
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.value")
        value = payload["value"]
        if parameter in LOCK_PARAMETERS:
            if not isinstance(value, bool):
                raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.value")
        else:
            if isinstance(value, bool):
                raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.value")
            numeric = _finite_number(value, f"{path}.value")
            if numeric <= 0.0:
                raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.value")

    elif operation == "change_lens":
        _require_str(payload, "deviceLensID", path)

    elif operation == "reserve_output_region":
        _contained(_validate_region(_require(payload, "region", path), f"{path}.region"),
                   ctx["output_crop"], path)

    elif operation == "wait_for_clearance":
        _validate_region(_require(payload, "region", path), f"{path}.region")
        blockers = _require(payload, "blockerRefs", path)
        if not isinstance(blockers, list) or not blockers:
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.blockerRefs")
        for index, ref in enumerate(blockers):
            _resolve_entity(ref, ctx["entity_ids"], ctx["labels"], f"{path}.blockerRefs[{index}]")
        _require_str(payload, "windowPolicyRef", path)

    elif operation == "select_capture_moment":
        frame_ref = _require_str(payload, "frameRef", path)
        if frame_ref not in ctx["frame_ids"]:
            raise ValidationError(REASON_FRAME_REFERENCE_MISSING, f"{path}.frameRef")
        if ctx["phase"] != "review":
            raise ValidationError(REASON_INVALID_ACTION_PAYLOAD, f"{path}.frameRef")

    elif operation == "maintain_subject_zone":
        _validate_region(_require(payload, "region", path), f"{path}.region")
        _require_str(payload, "windowPolicyRef", path)

    elif operation == "smooth_camera_motion":
        _require_str(payload, "windowPolicyRef", path)

    elif operation == "plan_motion_endpoints":
        for key in ("startFrameRef", "endFrameRef"):
            ref = _require_str(payload, key, path)
            if ref not in ctx["frame_ids"]:
                raise ValidationError(REASON_FRAME_REFERENCE_MISSING, f"{path}.{key}")
        _require_str(payload, "holdPolicyRef", path)

    elif operation == "clear_lens_obstruction":
        _validate_region(_require(payload, "obstructionRegion", path), f"{path}.obstructionRegion")

    else:  # pragma: no cover - reached only if the catalog diverges
        raise ValidationError(REASON_UNKNOWN_OPERATION, path)


# --------------------------------------------------------------------------
# Envelope validation
# --------------------------------------------------------------------------


def validate_envelope(body):
    """Validate a v3 envelope body.  Raises ValidationError on the first fault."""
    if not isinstance(body, dict):
        raise ValidationError(REASON_INVALID_JSON, "$")

    version = body.get("schemaVersion")
    if version != SCHEMA_VERSION:
        raise ValidationError(REASON_SCHEMA_VERSION_MISMATCH, "$.schemaVersion")
    _require_str(body, "analysisID", "$")
    _require_str(body, "sessionID", "$")
    _require_int(body, "generation", "$")
    _require_int(body, "intentRevision", "$")
    intent_revision = body["intentRevision"]
    phase = _require_enum(body, "phase", "$", PHASES)
    state = _require_enum(body, "state", "$", STATES)
    reason_code = _require_str(body, "reasonCode", "$")
    if reason_code not in REASON_CODES:
        raise ValidationError(REASON_UNKNOWN_REASON_CODE, "$.reasonCode")

    active_action = body.get("activeAction")
    if state == "CORRECT":
        if phase != "live":
            raise ValidationError(REASON_REVIEW_STATE_WITH_ACTION, "$.phase")
        if not isinstance(active_action, dict):
            raise ValidationError(REASON_STATE_ACTION_CONFLICT, "$.activeAction")
    elif active_action is not None:
        raise ValidationError(REASON_STATE_ACTION_CONFLICT, "$.activeAction")

    candidates = body.get("selectionCandidates")
    if candidates is None:
        candidates = []
    if not isinstance(candidates, list):
        raise ValidationError(REASON_SELECTION_CANDIDATES_CONFLICT, "$.selectionCandidates")
    if state == "SELECT_SUBJECT":
        if not candidates:
            raise ValidationError(REASON_SELECTION_CANDIDATES_CONFLICT, "$.selectionCandidates")
    elif candidates:
        raise ValidationError(REASON_SELECTION_CANDIDATES_CONFLICT, "$.selectionCandidates")

    # ---- frame reference / transform references -------------------------
    frame = _require(body, "frameReference", "$")
    if not isinstance(frame, dict):
        raise ValidationError(REASON_FRAME_REFERENCE_MISSING, "$.frameReference")
    frame_id = _require_str(frame, "frameID", "$.frameReference")
    orientation = _require_enum(frame, "orientation", "$.frameReference", ORIENTATIONS)
    mirrored = _require_bool(frame, "mirrored", "$.frameReference")
    output_crop = _validate_region(_require(frame, "outputCrop", "$.frameReference"),
                                   "$.frameReference.outputCrop")
    transform_ref = _require_str(frame, "transformRef", "$.frameReference")
    transforms = body.get("transformRefs")
    if not isinstance(transforms, list) or not transforms:
        raise ValidationError(REASON_TRANSFORM_REFERENCE_MISSING, "$.transformRefs")
    if transform_ref not in transforms:
        raise ValidationError(REASON_TRANSFORM_REFERENCE_MISSING, "$.frameReference.transformRef")
    frame_ids = {frame_id}
    for extra in body.get("additionalFrameIds", []) or []:
        if isinstance(extra, str) and extra:
            frame_ids.add(extra)

    # ---- entity graph ---------------------------------------------------
    entities = _require(body, "entities", "$")
    if not isinstance(entities, list) or not entities:
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, "$.entities")
    entity_ids = set()
    labels = set()
    track_bindings = {}
    for index, entity in enumerate(entities):
        entity_path = f"$.entities[{index}]"
        if not isinstance(entity, dict):
            raise ValidationError(REASON_MISSING_REQUIRED_FIELD, entity_path)
        entity_id = _require_str(entity, "entityID", entity_path)
        if entity_id in entity_ids:
            raise ValidationError(REASON_DUPLICATE_ENTITY_ID, entity_path)
        entity_ids.add(entity_id)
        labels.add(_require_str(entity, "displayLabel", entity_path))
        _require_enum(entity, "kind", entity_path, ENTITY_KINDS)
        _require_enum(entity, "role", entity_path, ENTITY_ROLES)
        track_bindings[entity_id] = _require_str(entity, "trackID", entity_path)

    relations = body.get("relations")
    if relations is None:
        relations = []
    if not isinstance(relations, list):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, "$.relations")
    relation_ids = set()
    edges = {}
    for index, relation in enumerate(relations):
        relation_path = f"$.relations[{index}]"
        if not isinstance(relation, dict):
            raise ValidationError(REASON_MISSING_REQUIRED_FIELD, relation_path)
        relation_id = _require_str(relation, "relationID", relation_path)
        if relation_id in relation_ids:
            raise ValidationError(REASON_DUPLICATE_RELATION_ID, relation_path)
        relation_ids.add(relation_id)
        endpoints = relation.get("endpoints")
        if not isinstance(endpoints, list) or not endpoints:
            raise ValidationError(REASON_RELATION_ENDPOINT_MISSING, relation_path)
        for endpoint in endpoints:
            if not isinstance(endpoint, str) or endpoint not in entity_ids:
                raise ValidationError(REASON_RELATION_ENDPOINT_MISSING, relation_path)
        if len(endpoints) >= 2:
            edges.setdefault(endpoints[0], set()).update(endpoints[1:])
    _detect_cycle(edges, "$.relations")

    # ---- evidence -------------------------------------------------------
    evidence = body.get("evidence")
    if evidence is None:
        evidence = []
    if not isinstance(evidence, list):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, "$.evidence")
    for index, item in enumerate(evidence):
        item_path = f"$.evidence[{index}]"
        if not isinstance(item, dict):
            raise ValidationError(REASON_MISSING_REQUIRED_FIELD, item_path)
        _require_str(item, "evidenceID", item_path)
        _require_enum(item, "qualificationStatus", item_path, EVIDENCE_QUALIFICATIONS)
        if item.get("relationRef") is not None:
            if item["relationRef"] not in relation_ids:
                raise ValidationError(REASON_ENTITY_REFERENCE_MISSING, f"{item_path}.relationRef")
        if item.get("entityRef") is not None:
            _resolve_entity(item["entityRef"], entity_ids, labels, f"{item_path}.entityRef")
        if item.get("intentRevision") is not None:
            if item["intentRevision"] != intent_revision:
                raise ValidationError(REASON_STALE_INTENT_REVISION, f"{item_path}.intentRevision")

    # ---- qualification --------------------------------------------------
    qualification = body.get("qualification")
    if state == "CORRECT":
        if not isinstance(qualification, dict):
            raise ValidationError(REASON_MISSING_QUALIFICATION, "$.qualification")
        qualification_ref = _require_str(qualification, "ref", "$.qualification")
        status = _require_enum(qualification, "status", "$.qualification", QUALIFICATION_STATUSES)
        if status != "qualified":
            raise ValidationError(REASON_UNQUALIFIED_EVIDENCE, "$.qualification.status")
        artifact_kind = _require_enum(qualification, "artifactKind", "$.qualification", ARTIFACT_KINDS)
        if artifact_kind == "research" and not qualification.get("releaseAdmissionRef"):
            raise ValidationError(REASON_RESEARCH_NOT_ADMITTED, "$.qualification.releaseAdmissionRef")
    else:
        qualification_ref = None
        if isinstance(qualification, dict):
            if qualification.get("artifactKind") is not None:
                _require_enum(qualification, "artifactKind", "$.qualification", ARTIFACT_KINDS)
            if qualification.get("status") is not None:
                _require_enum(qualification, "status", "$.qualification", QUALIFICATION_STATUSES)

    # ---- active action --------------------------------------------------
    action = active_action
    if isinstance(action, dict):
        _validate_action(action, qualification_ref, intent_revision, entity_ids, labels,
                         relation_ids, track_bindings, frame_ids, output_crop, phase,
                         orientation, mirrored)

    # ---- verification ---------------------------------------------------
    verification = body.get("verification")
    if verification is not None:
        _validate_verification(verification, entity_ids, labels)

    # ---- coverage / temporality ----------------------------------------
    coverage = body.get("coverage")
    if coverage is not None:
        if not isinstance(coverage, dict):
            raise ValidationError(REASON_MISSING_REQUIRED_FIELD, "$.coverage")
        kind = _require_enum(coverage, "kind", "$.coverage", COVERAGE_KINDS)
        _require_int(coverage, "contentRevision", "$.coverage")
        if kind in TEMPORAL_COVERAGE_KINDS:
            pts = coverage.get("pts")
            if not isinstance(pts, list) or not pts:
                raise ValidationError(REASON_MISSING_TEMPORAL_EVIDENCE, "$.coverage.pts")
            for index, value in enumerate(pts):
                if isinstance(value, bool):
                    raise ValidationError(REASON_NON_FINITE_NUMBER, f"$.coverage.pts[{index}]")
                if isinstance(value, str):
                    try:
                        int(value)
                        continue
                    except ValueError:
                        raise ValidationError(REASON_NON_FINITE_NUMBER, f"$.coverage.pts[{index}]")
                if not isinstance(value, int):
                    raise ValidationError(REASON_NON_FINITE_NUMBER, f"$.coverage.pts[{index}]")

    # ---- record immutability -------------------------------------------
    record = body.get("record")
    if record is not None:
        _validate_record(record, action, entity_ids, labels)

    return None


def _detect_cycle(edges, path):
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {}

    def visit(node):
        color[node] = GRAY
        for neighbor in edges.get(node, ()):  # noqa: B007
            state = color.get(neighbor, WHITE)
            if state == GRAY:
                return True
            if state == WHITE and visit(neighbor):
                return True
        color[node] = BLACK
        return False

    for node in list(edges):
        if color.get(node, WHITE) == WHITE and visit(node):
            raise ValidationError(REASON_ENTITY_GRAPH_CYCLE, path)


def _validate_action(action, qualification_ref, intent_revision, entity_ids, labels,
                     relation_ids, track_bindings, frame_ids, output_crop, phase,
                     frame_orientation, frame_mirrored):
    path = "activeAction"
    operation = _require_str(action, "operation", path)
    if operation not in PINNED_OPERATIONS:
        raise ValidationError(REASON_UNKNOWN_OPERATION, f"{path}.operation")
    for key in ("actionID", "frameRef", "qualificationRef", "verifierRef"):
        _require_str(action, key, path)
    _require_int(action, "intentRevision", path)
    targets = _require(action, "targetRefs", path)
    protected = _require(action, "protectedRefs", path)
    if not isinstance(targets, list) or not targets:
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.targetRefs")
    if not isinstance(protected, list):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.protectedRefs")
    for index, ref in enumerate(targets):
        _resolve_entity(ref, entity_ids, labels, f"{path}.targetRefs[{index}]")
    for index, ref in enumerate(protected):
        _resolve_entity(ref, entity_ids, labels, f"{path}.protectedRefs[{index}]")
    if action["frameRef"] not in frame_ids:
        raise ValidationError(REASON_FRAME_REFERENCE_MISSING, f"{path}.frameRef")

    payload = _require(action, "payload", path)
    ctx = {
        "entity_ids": entity_ids,
        "labels": labels,
        "relation_ids": relation_ids,
        "frame_ids": frame_ids,
        "output_crop": output_crop,
        "phase": phase,
    }
    _validate_payload(operation, payload, ctx)

    effect_goal = _require(action, "effectGoal", path)
    _validate_effect_goal(effect_goal, entity_ids, labels, relation_ids, output_crop)

    if action.get("frameOrientation") is not None:
        if action["frameOrientation"] not in ORIENTATIONS:
            raise ValidationError(REASON_UNKNOWN_ENUM_VALUE, f"{path}.frameOrientation")
        if action["frameOrientation"] != frame_orientation:
            raise ValidationError(REASON_ORIENTATION_MISMATCH, f"{path}.frameOrientation")
    if action.get("mirrored") is not None:
        if not isinstance(action["mirrored"], bool):
            raise ValidationError(REASON_MIRRORING_MISMATCH, f"{path}.mirrored")
        if action["mirrored"] != frame_mirrored:
            raise ValidationError(REASON_MIRRORING_MISMATCH, f"{path}.mirrored")

    if action["intentRevision"] != intent_revision:
        raise ValidationError(REASON_STALE_INTENT_REVISION, f"{path}.intentRevision")

    baseline = _require(action, "baseline", path)
    if not isinstance(baseline, dict):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.baseline")
    _require_str(baseline, "actionID", f"{path}.baseline")
    if baseline.get("intentRevision") != intent_revision:
        raise ValidationError(REASON_STALE_INTENT_REVISION, f"{path}.baseline.intentRevision")
    if isinstance(baseline.get("trackBindings"), dict):
        for entity_id, track_id in baseline["trackBindings"].items():
            if track_bindings.get(entity_id) != track_id:
                raise ValidationError(REASON_IDENTITY_LOST, f"{path}.baseline.trackBindings.{entity_id}")

    if qualification_ref is not None and action["qualificationRef"] != qualification_ref:
        raise ValidationError(REASON_UNQUALIFIED_EVIDENCE, f"{path}.qualificationRef")


def _validate_effect_goal(goal, entity_ids, labels, relation_ids, output_crop):
    path = "activeAction.effectGoal"
    if not isinstance(goal, dict):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, path)
    _require_str(goal, "metricID", path)
    refs = _require(goal, "targetEntityRefs", path)
    if not isinstance(refs, list) or not refs:
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.targetEntityRefs")
    for index, ref in enumerate(refs):
        _resolve_entity(ref, entity_ids, labels, f"{path}.targetEntityRefs[{index}]")
    _require_enum(goal, "desired", path, DESIRED_VALUES)
    _require_str(goal, "policyRef", path)
    if goal.get("relationRef") is not None and goal["relationRef"] not in relation_ids:
        raise ValidationError(REASON_ENTITY_REFERENCE_MISSING, f"{path}.relationRef")
    if goal.get("targetRegion") is not None:
        _contained(_validate_region(goal["targetRegion"], f"{path}.targetRegion"), output_crop, path)


def _validate_verification(verification, entity_ids, labels):
    path = "$.verification"
    if not isinstance(verification, dict):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, path)
    outcome = _require_enum(verification, "outcome", path, VERIFICATION_OUTCOMES)
    effect_delta = _finite_number(_require(verification, "effectDelta", path), f"{path}.effectDelta")
    deadband = _finite_number(_require(verification, "deadband", path), f"{path}.deadband")
    if deadband < 0.0:
        raise ValidationError(REASON_NON_FINITE_NUMBER, f"{path}.deadband")
    if verification.get("goalSatisfied") is not None:
        _require_bool(verification, "goalSatisfied", path)
    if outcome == "improved":
        if not effect_delta > deadband:
            raise ValidationError(REASON_CLAIMED_IMPROVEMENT_WITHOUT_DELTA, f"{path}.effectDelta")
        deltas = verification.get("protectedDeltas")
        if deltas is None:
            deltas = []
        if not isinstance(deltas, list):
            raise ValidationError(REASON_MISSING_REQUIRED_FIELD, f"{path}.protectedDeltas")
        for index, delta in enumerate(deltas):
            delta_path = f"{path}.protectedDeltas[{index}]"
            if not isinstance(delta, dict):
                raise ValidationError(REASON_MISSING_REQUIRED_FIELD, delta_path)
            _resolve_entity(_require(delta, "entityRef", delta_path), entity_ids, labels,
                            f"{delta_path}.entityRef")
            value = _finite_number(_require(delta, "delta", delta_path), f"{delta_path}.delta")
            if value > 0.0:
                raise ValidationError(REASON_PROTECTED_REGRESSION, f"{delta_path}.delta")


def _validate_record(record, action, entity_ids, labels):
    path = "$.record"
    if not isinstance(record, dict):
        raise ValidationError(REASON_MISSING_REQUIRED_FIELD, path)
    _require_str(record, "recordID", path)
    _require_int(record, "revision", path)
    frozen = _require_bool(record, "frozen", path)
    if not frozen:
        return
    if not isinstance(action, dict):
        raise ValidationError(REASON_FROZEN_RECORD_MUTATION, path)
    baseline = record.get("baseline")
    if not isinstance(baseline, dict):
        raise ValidationError(REASON_FROZEN_RECORD_MUTATION, f"{path}.baseline")
    if baseline.get("actionID") != action.get("actionID"):
        raise ValidationError(REASON_FROZEN_RECORD_MUTATION, f"{path}.baseline.actionID")
    if baseline.get("targetRefs") != action.get("targetRefs"):
        raise ValidationError(REASON_FROZEN_RECORD_MUTATION, f"{path}.baseline.targetRefs")
    if baseline.get("protectedRefs") != action.get("protectedRefs"):
        raise ValidationError(REASON_FROZEN_RECORD_MUTATION, f"{path}.baseline.protectedRefs")


# --------------------------------------------------------------------------
# Registry loading
# --------------------------------------------------------------------------


def load_registry():
    with REGISTRY_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


REASON_CODES = None  # populated from the registry in the test setup


def _load_reason_codes():
    global REASON_CODES
    REASON_CODES = list(load_registry()["reason_codes"])
    return REASON_CODES


# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------


_load_reason_codes()


def _load_cases():
    with CANONICAL_FIXTURE.open(encoding="utf-8") as handle:
        return json.load(handle)["cases"]


class RegistryContractTests(unittest.TestCase):
    def test_registry_operation_catalog_matches_validator(self):
        registry = load_registry()
        self.assertEqual(registry["schema_id"], SCHEMA_ID)
        self.assertEqual(registry["schema_version"], SCHEMA_VERSION)
        operation_ids = [op["operation_id"] for op in registry["operations"]]
        self.assertEqual(len(operation_ids), 20)
        self.assertEqual(operation_ids, list(PINNED_OPERATIONS))
        self.assertEqual(len(set(operation_ids)), len(operation_ids))
        for op in registry["operations"]:
            self.assertIn(op["admissibility"], {"qualified", "needs_user_input", "unsupported"})
            self.assertTrue(op["payload_spec"])

    def test_registry_reason_codes_are_the_frozen_eighteen(self):
        self.assertEqual(len(REASON_CODES), 18)
        self.assertEqual(len(set(REASON_CODES)), 18)
        self.assertIn("ready", REASON_CODES)
        self.assertIn("invalid_payload", REASON_CODES)
        self.assertIn("scope_changed", REASON_CODES)

    def test_registry_declares_review_semantics_without_active_action(self):
        registry = load_registry()
        semantics = registry["review_semantics"]
        if isinstance(semantics, dict):
            # Registry revision 2+ projects review semantics as a keyed object.
            blob = " ".join(str(value) for value in semantics.values())
            self.assertIn("no decision.activeAction", blob)
            self.assertIn("never masked as live CORRECT", blob)
        else:
            self.assertIn("not active live CORRECT", semantics)
            self.assertIn("never an instruction to fix", semantics)
        self.assertEqual(registry["state_semantics"]["CORRECT"],
                         "exactly one activeAction; other states carry none")

    def test_bundled_fixture_matches_canonical_fixture(self):
        self.assertTrue(BUNDLED_FIXTURE.exists(),
                        "Swift test bundle fixture is missing; regenerate from the canonical copy")
        with CANONICAL_FIXTURE.open(encoding="utf-8") as handle:
            canonical = json.load(handle)
        with BUNDLED_FIXTURE.open(encoding="utf-8") as handle:
            bundled = json.load(handle)
        self.assertEqual(canonical, bundled,
                         "bundled Swift fixture diverged from tools/tests/fixtures canonical copy")


class FixtureParityTests(unittest.TestCase):
    def test_fixture_catalog_is_non_trivial(self):
        cases = _load_cases()
        accepts = [c for c in cases if c["expect"] == "accept"]
        rejects = [c for c in cases if c["expect"] == "reject"]
        self.assertGreaterEqual(len(accepts), 20)
        self.assertGreaterEqual(len(rejects), 30)
        ids = [c["id"] for c in cases]
        self.assertEqual(len(ids), len(set(ids)), "fixture ids must be unique")

    def test_every_conformance_tag_from_n12_is_present(self):
        cases = _load_cases()
        tags = {c["conformance"] for c in cases}
        required = {
            "N12.1_two_lamps_same_label",
            "N12.2_invalid_endpoint",
            "N12.3_region",
            "N12.4_frame_transform",
            "N12.5_same_label_track_swap",
            "N12.6_unknown_operation",
            "N12.7_stale_intent",
            "N12.8_qualified_evidence",
            "N12.9_result_unchanged_worse",
            "N12.10_face_protection",
            "N12.11_sampled_still_temporality",
            "N12.12_record_immutability",
            "N12.13_research_admission",
            "C01.finite_ranges",
            "C01.entity_graph_cycles",
            "C01.enum_payload_combinations",
            "C01.review_no_active_action",
        }
        self.assertTrue(required.issubset(tags), f"missing conformance tags: {required - tags}")

    def test_every_fixture_case_matches_expected_decision(self):
        failures = []
        for case in _load_cases():
            try:
                validate_envelope(case["body"])
                got_expect, got_reason = "accept", "ok"
            except ValidationError as error:
                got_expect, got_reason = "reject", error.reason
            if (got_expect, got_reason) != (case["expect"], case["reason"]):
                failures.append(
                    f"{case['id']}: expected {case['expect']}/{case['reason']} "
                    f"got {got_expect}/{got_reason}"
                )
        self.assertEqual(failures, [])

    def test_unknown_operation_is_rejected_not_defaulted(self):
        with self.assertRaises(ValidationError) as context:
            validate_envelope({"schemaVersion": SCHEMA_VERSION, "state": "CORRECT"})
        self.assertNotEqual(context.exception.reason, "ok")


if __name__ == "__main__":
    unittest.main(verbosity=2)
