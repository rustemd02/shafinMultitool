#!/usr/bin/env python3
"""Stdlib-only Camera Coach v1 schema, provenance, rights, and family check."""

from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CAMERA_DIR = ROOT / "datasets/camera-coach/v1"
FIXTURE_PATH = ROOT / "tools/dataset/tests/fixtures/camera-coach-fixtures.json"
AUTHORITY_PATH = ROOT / "docs/implementation/camera-coach-contract-v2.json"
SCHEMA_FILES = ("label-schema.json", "temporal-schema.json", "episode-schema.json")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
RECORD_ID_RE = re.compile(r"^cam-[a-z0-9][a-z0-9._-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
SCHEMA_VERSION = "v1.0.0"

MATRIX_CLASSES = {
    "single_person",
    "two_people",
    "object_or_food",
    "interior",
    "street_or_landscape",
    "difficult_light",
    "already_good_frame",
}
RECORD_TYPES = {"still", "temporal", "episode"}
SPLITS = {"train", "calibration", "holdout", "quarantine", "fixture"}
RIGHTS_DISPOSITIONS = {"approved", "denied", "unresolved", "pending", "withdrawn", "fixture_only"}
SOURCE_KINDS = {"owned", "licensed", "consented", "public", "runtime_export", "synthetic_fixture"}
NON_INDEPENDENT_DERIVATION_KINDS = {"burst_frame", "crop", "resize", "color_variant", "temporal_frame", "episode_view"}
INDEPENDENT_DERIVATION_KINDS = {"original_still", "original_temporal_sequence", "original_before_after_episode"}
DERIVATION_KINDS = INDEPENDENT_DERIVATION_KINDS | NON_INDEPENDENT_DERIVATION_KINDS
RIGHTS_USES = {"train", "calibration", "holdout", "fixture"}
RELEASE_SPLITS = {"train", "calibration", "holdout"}

# The JSON Schema files are intentionally closed. This small stdlib walker
# keeps production admission closed even when a full JSON Schema engine is not
# installed, including record extensions and every known nested object.
CLOSED_KEYS = {
    "record": {"schema_id", "schema_version", "record_id", "record_type", "matrix_class", "split", "media", "capture", "provenance", "subject", "style_intent", "label", "review", "sequence", "episode"},
    "media": {"asset_id", "asset_ids", "content_sha256", "hash_algorithm", "storage"},
    "capture": {"scene_family_id", "take_family_id", "time_family_id", "location_family_id", "person_family_ids", "device_family_id", "orientation", "lens", "lighting", "capture_mode"},
    "provenance": {"source_shoot_id", "source_asset_ids", "derivation_family_id", "rights_record_id", "rights_disposition", "source_kind", "raw_storage"},
    "subject": {"status", "candidates", "selected_subject_id"},
    "subject_candidate": {"subject_id", "kind", "reference", "region"},
    "style_intent": {"style_id", "intentional", "basis"},
    "label": {"issues", "acceptable_action_ids", "forbidden_action_ids", "selected_action_id", "selection_status", "keep_decision", "abstention", "verification"},
    "issue": {"issue_id", "severity", "evidence", "acceptable_action_ids", "forbidden_action_ids"},
    "abstention": {"status", "reasons"},
    "verification": {"action_id", "verifier_id", "result", "measurement"},
    "review": {"status", "vote_history", "adjudication_history"},
    "vote": {"vote_id", "annotator_id", "submitted_at", "decision"},
    "adjudication": {"adjudication_id", "adjudicator_id", "occurred_at", "based_on_vote_ids", "outcome"},
    "sequence": {"sequence_id", "frame_count", "frames", "timeline"},
    "frame": {"frame_id", "ordinal", "timestamp_ms", "asset_id", "state"},
    "timeline_segment": {"state", "start_frame", "end_frame"},
    "episode": {"episode_id", "before", "action_step", "after", "outcome", "outcome_verifier", "subject_continuity"},
    "episode_asset": {"asset_id", "captured_at"},
    "action_step": {"action_id", "performed_at"},
    "source_shoot_entry": {"manifest_type", "schema_id", "manifest_version", "source_shoot_id", "scene_family_id", "take_family_id", "time_family_id", "location_family_id", "person_family_ids", "device_family_id", "orientation", "lens", "lighting", "asset_ids", "storage", "source_kind"},
    "consent_entry": {"manifest_type", "schema_id", "manifest_version", "consent_record_id", "source_shoot_id", "asset_ids", "disposition", "allowed_uses", "evidence_ref", "recorded_at"},
    "rights_entry": {"manifest_type", "schema_id", "manifest_version", "rights_record_id", "source_shoot_id", "consent_record_id", "asset_ids", "disposition", "allowed_uses", "evidence_ref", "recorded_at"},
    "derivation_entry": {"manifest_type", "schema_id", "manifest_version", "derivation_id", "source_shoot_id", "record_id", "input_asset_ids", "output_asset_ids", "derivation_family_id", "derivation_kind", "is_independent", "counts_toward_quota"},
}
CLOSED_CHILDREN = {
    "record": {"media": ("media", False), "capture": ("capture", False), "provenance": ("provenance", False), "subject": ("subject", False), "style_intent": ("style_intent", False), "label": ("label", False), "review": ("review", False), "sequence": ("sequence", False), "episode": ("episode", False)},
    "subject": {"candidates": ("subject_candidate", True)},
    "label": {"issues": ("issue", True), "abstention": ("abstention", False), "verification": ("verification", True)},
    "review": {"vote_history": ("vote", True), "adjudication_history": ("adjudication", True)},
    "sequence": {"frames": ("frame", True), "timeline": ("timeline_segment", True)},
    "episode": {"before": ("episode_asset", False), "action_step": ("action_step", False), "after": ("episode_asset", False)},
}


def _validate_closed_keys(value: Any, schema_name: str, path: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        return
    for key in sorted(set(value) - CLOSED_KEYS[schema_name]):
        errors.append(_error("unknown_field", f"{path}.{key}"))
    for field, (child_schema, is_list) in CLOSED_CHILDREN.get(schema_name, {}).items():
        child = value.get(field)
        if is_list:
            if isinstance(child, list):
                for index, item in enumerate(child):
                    _validate_closed_keys(item, child_schema, f"{path}.{field}[{index}]", errors)
        elif child is not None:
            _validate_closed_keys(child, child_schema, f"{path}.{field}", errors)


def _load_canonical_action_ids() -> set[str]:
    """Load the approved action catalog from the read-only contract authority."""
    authority = json.loads(AUTHORITY_PATH.read_text(encoding="utf-8"))
    actions = authority.get("approvedActionIDs") if isinstance(authority, dict) else None
    if not isinstance(actions, list) or not actions or any(not isinstance(action, str) for action in actions):
        raise ValueError(f"canonical action catalog missing from {AUTHORITY_PATH}")
    if len(set(actions)) != len(actions):
        raise ValueError(f"canonical action catalog contains duplicates: {AUTHORITY_PATH}")
    return set(actions)


def _load_label_issue_evidence_ids() -> set[str]:
    """Derive the closed issue-evidence catalog from the owned JSON Schema."""
    schema = json.loads((CAMERA_DIR / "label-schema.json").read_text(encoding="utf-8"))
    evidence = (
        schema.get("$defs", {})
        .get("issue", {})
        .get("properties", {})
        .get("evidence", {})
        .get("items", {})
        .get("enum")
    )
    if not isinstance(evidence, list) or not evidence or any(not isinstance(item, str) for item in evidence):
        raise ValueError(f"closed issue-evidence catalog missing from {CAMERA_DIR / 'label-schema.json'}")
    if len(set(evidence)) != len(evidence):
        raise ValueError(f"closed issue-evidence catalog contains duplicates: {CAMERA_DIR / 'label-schema.json'}")
    return set(evidence)


# This is derived state, not a second action-catalog owner. Schema parity is
# checked against the same authority in validate_schema_files().
ACTION_IDS = _load_canonical_action_ids()
VERIFIER_BY_ACTION = {
    "shift_frame_left": "framing_left_improves",
    "shift_frame_right": "framing_right_improves",
    "shift_frame_up": "headroom_or_upper_boundary_improves",
    "shift_frame_down": "lower_frame_context_improves",
    "level_horizon": "horizon_tilt_decreases",
    "step_back": "framing_breathing_room_increases",
    "step_closer": "subject_prominence_increases",
    "lower_camera": "perspective_height_improves",
    "raise_camera": "perspective_height_improves",
    "change_camera_angle": "background_or_perspective_improves",
    "rotate_subject_toward_light": "subject_light_direction_improves",
    "move_subject_left": "subject_position_improves_left",
    "move_subject_right": "subject_position_improves_right",
    "move_subject_away_from_background": "subject_separation_increases",
    "move_object_left": "object_position_improves_left",
    "move_object_right": "object_position_improves_right",
    "move_object_forward": "object_depth_relation_improves_forward",
    "move_object_back": "object_depth_relation_improves_back",
    "remove_distracting_object": "background_competition_decreases",
    "reposition_prop_for_balance": "object_balance_improves",
    "add_front_fill_light": "subject_exposure_improves",
    "add_background_light": "subject_separation_increases",
    "remove_background_hotspot": "background_competition_decreases",
    "simplify_background": "background_competition_decreases",
    "wait_for_background_clearance": "transient_blocker_clears",
    "keep_current_setup": "frame_remains_acceptable",
}
VERIFIER_IDS = set(VERIFIER_BY_ACTION.values()) | {"insufficient_evidence"}
ISSUE_IDS = {
    "insufficient_look_space", "subject_edge_pressure", "object_edge_pressure", "tight_framing",
    "weak_subject_prominence", "weak_object_prominence", "camera_height_mismatch", "perspective_mismatch",
    "background_competition", "tilted_horizon", "weak_subject_background_separation", "flat_depth",
    "front_light_deficit", "prop_breaks_balance", "object_conflicts_with_subject", "face_contour_occlusion",
    "subject_blends_into_dark_background", "bright_background_pull", "unclear_focus_hierarchy",
    "timing_blocker_in_frame", "background_clutter",
}
ISSUE_EVIDENCE_IDS = _load_label_issue_evidence_ids()
REQUIRED_CAPTURE_FIELDS = {
    "scene_family_id", "take_family_id", "time_family_id", "location_family_id", "person_family_ids",
    "device_family_id", "orientation", "lens", "lighting", "capture_mode",
}


def _error(code: str, detail: str) -> str:
    return f"{code}: {detail}"


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _canonical_digest(value: dict[str, Any], field: str) -> str:
    payload = copy.deepcopy(value)
    payload.pop(field, None)
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _check_id(value: Any, path: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not ID_RE.fullmatch(value):
        errors.append(_error("invalid_id", path))


def _check_sha(value: Any, path: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        errors.append(_error("invalid_sha256", path))


def _require(mapping: Any, fields: set[str], path: str, errors: list[str]) -> None:
    if not isinstance(mapping, dict):
        errors.append(_error("invalid_object", path))
        return
    for field in sorted(fields - set(mapping)):
        errors.append(_error("missing_field", f"{path}.{field}"))


def _check_enum(value: Any, allowed: set[str], path: str, errors: list[str], code: str = "invalid_value") -> None:
    try:
        valid = value in allowed
    except TypeError:
        valid = False
    if not valid:
        errors.append(_error(code, path))


def _parse_timestamp(value: Any) -> datetime | None:
    """Parse the contract's UTC timestamp shape and reject impossible values."""
    if not isinstance(value, str) or not DATE_RE.fullmatch(value):
        return None
    try:
        return datetime.strptime(value, TIMESTAMP_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _check_timestamp(value: Any, path: str, errors: list[str]) -> datetime | None:
    parsed = _parse_timestamp(value)
    if parsed is None:
        errors.append(_error("invalid_timestamp", path))
    return parsed


def _is_strict_int(value: Any) -> bool:
    """Match JSON Schema integer semantics without Python's bool-as-int trap."""
    return type(value) is int


def _is_json_number(value: Any) -> bool:
    """Match JSON number semantics and reject booleans/non-finite Python values."""
    return type(value) is int or (type(value) is float and math.isfinite(value))


def _check_list(value: Any, path: str, errors: list[str], *, nonempty: bool = False) -> list[Any]:
    if not isinstance(value, list) or (nonempty and not value) or len({json.dumps(v, sort_keys=True) for v in value}) != len(value):
        errors.append(_error("invalid_list", path))
        return []
    return value


def _check_no_locked_outputs(value: Any, path: str, errors: list[str]) -> None:
    forbidden = {"candidate", "candidate_output", "locked_label", "model_output", "prediction", "oracle"}
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in forbidden:
                errors.append(_error("locked_output_exposed", f"{path}.{key}"))
            _check_no_locked_outputs(child, f"{path}.{key}", errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _check_no_locked_outputs(child, f"{path}[{index}]", errors)


def _validate_media(media: Any, errors: list[str]) -> set[str]:
    _require(media, {"asset_id", "asset_ids", "content_sha256", "hash_algorithm", "storage"}, "media", errors)
    if not isinstance(media, dict):
        return set()
    _check_id(media.get("asset_id"), "media.asset_id", errors)
    asset_ids = _check_list(media.get("asset_ids"), "media.asset_ids", errors, nonempty=True)
    for asset_id in asset_ids:
        _check_id(asset_id, "media.asset_ids", errors)
    _check_sha(media.get("content_sha256"), "media.content_sha256", errors)
    if media.get("hash_algorithm") != "sha256":
        errors.append(_error("invalid_hash_algorithm", "media.hash_algorithm"))
    if media.get("storage") != "outside_git":
        errors.append(_error("raw_media_inside_git", "media.storage"))
    return {asset_id for asset_id in asset_ids if isinstance(asset_id, str)}


def _validate_capture(capture: Any, errors: list[str]) -> None:
    _require(capture, REQUIRED_CAPTURE_FIELDS, "capture", errors)
    if not isinstance(capture, dict):
        return
    for field in REQUIRED_CAPTURE_FIELDS - {"person_family_ids"}:
        _check_id(capture.get(field), f"capture.{field}", errors)
    persons = _check_list(capture.get("person_family_ids"), "capture.person_family_ids", errors)
    for person in persons:
        _check_id(person, "capture.person_family_ids", errors)
    _check_enum(capture.get("orientation"), {"portrait", "landscape", "square", "unknown"}, "capture.orientation", errors)
    _check_enum(capture.get("lens"), {"front", "ultrawide", "wide", "telephoto", "macro", "unknown"}, "capture.lens", errors)
    _check_enum(capture.get("lighting"), {"daylight", "overcast", "tungsten", "mixed", "low_key", "backlit", "high_key", "practical", "flicker", "unknown"}, "capture.lighting", errors)
    _check_enum(capture.get("capture_mode"), {"still", "temporal_sequence", "before_after_episode"}, "capture.capture_mode", errors)


def _validate_provenance(provenance: Any, errors: list[str]) -> set[str]:
    _require(provenance, {"source_shoot_id", "source_asset_ids", "derivation_family_id", "rights_record_id", "rights_disposition", "source_kind", "raw_storage"}, "provenance", errors)
    if not isinstance(provenance, dict):
        return set()
    if not provenance.get("source_shoot_id"):
        errors.append(_error("missing_source_shoot", "provenance.source_shoot_id"))
    else:
        _check_id(provenance.get("source_shoot_id"), "provenance.source_shoot_id", errors)
    assets = _check_list(provenance.get("source_asset_ids"), "provenance.source_asset_ids", errors, nonempty=True)
    for asset_id in assets:
        _check_id(asset_id, "provenance.source_asset_ids", errors)
    _check_id(provenance.get("derivation_family_id"), "provenance.derivation_family_id", errors)
    _check_id(provenance.get("rights_record_id"), "provenance.rights_record_id", errors)
    _check_enum(provenance.get("rights_disposition"), RIGHTS_DISPOSITIONS, "provenance.rights_disposition", errors)
    _check_enum(provenance.get("source_kind"), SOURCE_KINDS, "provenance.source_kind", errors)
    if provenance.get("raw_storage") != "outside_git":
        errors.append(_error("raw_media_inside_git", "provenance.raw_storage"))
    return set(assets)


def _validate_subject(subject: Any, errors: list[str]) -> None:
    _require(subject, {"status", "candidates", "selected_subject_id"}, "subject", errors)
    if not isinstance(subject, dict):
        return
    _check_enum(subject.get("status"), {"selected", "ambiguous", "none", "abstain"}, "subject.status", errors)
    candidates = _check_list(subject.get("candidates"), "subject.candidates", errors)
    candidate_ids: list[str] = []
    for index, candidate in enumerate(candidates):
        path = f"subject.candidates[{index}]"
        _require(candidate, {"subject_id", "kind", "reference"}, path, errors)
        if not isinstance(candidate, dict):
            continue
        candidate_id = candidate.get("subject_id")
        _check_id(candidate_id, f"{path}.subject_id", errors)
        _check_enum(candidate.get("kind"), {"face", "person", "object", "group", "scene", "unknown"}, f"{path}.kind", errors)
        _check_id(candidate.get("reference"), f"{path}.reference", errors)
        region = candidate.get("region")
        if region is not None:
            if (
                not isinstance(region, list)
                or len(region) != 4
                or any(not _is_json_number(value) or not 0 <= value <= 1 for value in region)
            ):
                errors.append(_error("invalid_subject_region", f"{path}.region"))
        if isinstance(candidate_id, str):
            candidate_ids.append(candidate_id)
    if len(set(candidate_ids)) != len(candidate_ids):
        errors.append(_error("invalid_subject_reference", "subject.candidates duplicate subject_id"))
    selected = subject.get("selected_subject_id")
    if selected is not None and (not isinstance(selected, str) or selected not in candidate_ids):
        errors.append(_error("invalid_subject_reference", "subject.selected_subject_id"))
    status = subject.get("status")
    if status == "selected" and (len(candidate_ids) != 1 or not isinstance(selected, str) or selected != candidate_ids[0]):
        errors.append(_error("invalid_subject_reference", "selected subject requires exactly one matching candidate"))
    if status in {"ambiguous", "none", "abstain"} and selected is not None:
        errors.append(_error("invalid_subject_reference", "non-selected status cannot name a subject"))
    if status == "ambiguous" and len(candidate_ids) < 2:
        errors.append(_error("invalid_subject_reference", "ambiguous subject needs at least two candidates"))


def _validate_label(label: Any, errors: list[str]) -> None:
    required = {"issues", "acceptable_action_ids", "forbidden_action_ids", "selected_action_id", "selection_status", "keep_decision", "abstention", "verification"}
    _require(label, required, "label", errors)
    if not isinstance(label, dict):
        return
    issues = _check_list(label.get("issues"), "label.issues", errors)
    accepted = _check_list(label.get("acceptable_action_ids"), "label.acceptable_action_ids", errors)
    forbidden = _check_list(label.get("forbidden_action_ids"), "label.forbidden_action_ids", errors)
    for action in accepted + forbidden:
        if action not in ACTION_IDS:
            errors.append(_error("invalid_action_id", "label action list"))
    if set(accepted) & set(forbidden):
        errors.append(_error("contradictory_actions", "label action lists overlap"))
    for index, issue in enumerate(issues):
        path = f"label.issues[{index}]"
        _require(issue, {"issue_id", "severity", "evidence", "acceptable_action_ids", "forbidden_action_ids"}, path, errors)
        if not isinstance(issue, dict):
            continue
        _check_enum(issue.get("issue_id"), ISSUE_IDS, f"{path}.issue_id", errors)
        _check_enum(issue.get("severity"), {"minor", "moderate", "major", "critical"}, f"{path}.severity", errors)
        evidence = _check_list(issue.get("evidence"), f"{path}.evidence", errors, nonempty=True)
        for evidence_id in evidence:
            _check_enum(evidence_id, ISSUE_EVIDENCE_IDS, f"{path}.evidence", errors, code="invalid_issue_evidence")
        _check_list(issue.get("acceptable_action_ids"), f"{path}.acceptable_action_ids", errors)
        _check_list(issue.get("forbidden_action_ids"), f"{path}.forbidden_action_ids", errors)
        if not evidence:
            errors.append(_error("missing_issue_evidence", path))
        for action in issue.get("acceptable_action_ids", []):
            if action not in ACTION_IDS:
                errors.append(_error("invalid_action_id", f"{path}.acceptable_action_ids"))
            if action not in accepted:
                errors.append(_error("action_issue_mismatch", path))
        for action in issue.get("forbidden_action_ids", []):
            if action not in ACTION_IDS:
                errors.append(_error("invalid_action_id", f"{path}.forbidden_action_ids"))
            if action not in forbidden:
                errors.append(_error("action_issue_mismatch", path))
    selected = label.get("selected_action_id")
    if selected is not None and (not isinstance(selected, str) or selected not in accepted):
        errors.append(_error("invalid_action_id", "label.selected_action_id"))
    status = label.get("selection_status")
    _check_enum(status, {"single", "multiple_valid", "no_action", "abstain"}, "label.selection_status", errors)
    if status == "single" and (len(accepted) != 1 or selected is None):
        errors.append(_error("invalid_selection", "single selection requires one selected action"))
    if status == "multiple_valid" and (len(accepted) < 2 or selected is None):
        errors.append(_error("invalid_selection", "multiple_valid requires two actions and a selection"))
    if status == "no_action" and (accepted or selected is not None):
        errors.append(_error("invalid_selection", "no_action cannot select corrective actions"))
    if status == "abstain" and (accepted or selected is not None):
        errors.append(_error("invalid_selection", "abstain cannot select corrective actions"))
    keep = label.get("keep_decision")
    _check_enum(keep, {"keep", "not_keep", "uncertain"}, "label.keep_decision", errors)
    abstention = label.get("abstention")
    _require(abstention, {"status", "reasons"}, "label.abstention", errors)
    abstention_status = None
    if isinstance(abstention, dict):
        abstention_status = abstention.get("status")
        _check_enum(abstention_status, {"none", "abstain"}, "label.abstention.status", errors)
        reasons = _check_list(abstention.get("reasons"), "label.abstention.reasons", errors)
        if abstention_status == "none" and reasons:
            errors.append(_error("invalid_abstention", "abstention.status=none requires empty reasons"))
        for reason in abstention.get("reasons", []):
            _check_enum(reason, {"subject_unclear", "issue_unclear", "style_intent_unclear", "insufficient_visibility", "rights_or_privacy_blocker", "before_after_not_comparable", "other"}, "label.abstention.reasons", errors)
    if keep == "keep" and accepted != ["keep_current_setup"]:
        errors.append(_error("invalid_keep_label", "KEEP requires keep_current_setup only"))
    if keep != "keep" and "keep_current_setup" in accepted:
        errors.append(_error("invalid_keep_label", "no-change actions require KEEP"))
    if status == "abstain" and (abstention_status != "abstain" or keep != "uncertain"):
        errors.append(_error("invalid_abstention", "selection_status=abstain requires abstention.status=abstain and uncertain KEEP"))
    if abstention_status == "abstain" and (status != "abstain" or keep != "uncertain" or not abstention.get("reasons")):
        errors.append(_error("invalid_abstention", "ABSTAIN requires uncertain/no-action label and a reason"))
    verifications = _check_list(label.get("verification"), "label.verification", errors, nonempty=True)
    seen_actions: set[str] = set()
    for index, verification in enumerate(verifications):
        path = f"label.verification[{index}]"
        _require(verification, {"action_id", "verifier_id", "result", "measurement"}, path, errors)
        if not isinstance(verification, dict):
            continue
        action = verification.get("action_id")
        verifier = verification.get("verifier_id")
        if action != "abstain" and action not in ACTION_IDS:
            errors.append(_error("invalid_action_verifier", f"{path}.action_id"))
        if verifier not in VERIFIER_IDS:
            errors.append(_error("invalid_action_verifier", f"{path}.verifier_id"))
        elif action in VERIFIER_BY_ACTION and verifier != VERIFIER_BY_ACTION[action]:
            errors.append(_error("invalid_action_verifier", f"{path}: {action} requires {VERIFIER_BY_ACTION[action]}"))
        elif action == "abstain" and verifier != "insufficient_evidence":
            errors.append(_error("invalid_action_verifier", f"{path}: abstain requires insufficient_evidence"))
        if action in seen_actions:
            errors.append(_error("duplicate_action_verification", path))
        seen_actions.add(action)
        _check_enum(verification.get("result"), {"pass", "fail", "inconclusive", "not_run"}, f"{path}.result", errors)
        _check_enum(verification.get("measurement"), {"single_frame", "before_after", "temporal_timeline", "not_observed"}, f"{path}.measurement", errors)
    is_abstention = status == "abstain" or abstention_status == "abstain"
    expected_actions = {"abstain"} if is_abstention else set(accepted)
    if not expected_actions.issubset(seen_actions):
        errors.append(_error("missing_action_verification", "every accepted action needs a verifier"))
    if is_abstention:
        abstain_verifications = [item for item in verifications if isinstance(item, dict) and item.get("action_id") == "abstain"]
        if (
            abstention_status != "abstain"
            or status != "abstain"
            or len(abstain_verifications) != 1
            or abstain_verifications[0].get("verifier_id") != "insufficient_evidence"
            or abstain_verifications[0].get("result") != "inconclusive"
            or abstain_verifications[0].get("measurement") != "not_observed"
            or len(verifications) != 1
        ):
            errors.append(_error("invalid_abstention", "ABSTAIN needs exactly one insufficient-evidence/inconclusive/not_observed verification"))


def _validate_subject_label_semantics(subject: Any, label: Any, errors: list[str]) -> None:
    """Keep SELECT_SUBJECT and ABSTAIN outcomes fail-closed and distinct."""
    if not isinstance(subject, dict) or not isinstance(label, dict):
        return
    subject_status = subject.get("status")
    selected_subject_id = subject.get("selected_subject_id")
    abstention = label.get("abstention")
    abstention_status = abstention.get("status") if isinstance(abstention, dict) else None
    abstention_reasons = abstention.get("reasons") if isinstance(abstention, dict) else None
    label_status = label.get("selection_status")
    label_abstain = label_status == "abstain" or abstention_status == "abstain"
    verifications = label.get("verification") if isinstance(label.get("verification"), list) else []
    if subject_status == "abstain" and selected_subject_id is not None:
        errors.append(_error("invalid_subject_reference", "subject ABSTAIN requires selected_subject_id=null"))
    if subject_status == "abstain" and not label_abstain:
        errors.append(_error("invalid_abstention", "subject ABSTAIN requires label ABSTAIN"))
    if subject_status == "ambiguous" and (
        label_status != "no_action"
        or label.get("acceptable_action_ids")
        or label.get("selected_action_id") is not None
        or label.get("keep_decision") != "uncertain"
        or abstention_status != "none"
        or abstention_reasons
        or any(
            isinstance(item, dict) and item.get("action_id") not in {"keep_current_setup"}
            for item in verifications
        )
    ):
        errors.append(_error("invalid_selection", "ambiguous subject requires SELECT_SUBJECT/no corrective action"))


def _validate_review(review: Any, errors: list[str]) -> None:
    _require(review, {"status", "vote_history", "adjudication_history"}, "review", errors)
    if not isinstance(review, dict):
        return
    _check_enum(review.get("status"), {"unreviewed", "in_review", "dual_reviewed", "adjudicated", "rejected"}, "review.status", errors)
    votes = _check_list(review.get("vote_history"), "review.vote_history", errors)
    vote_ids: set[str] = set()
    annotators: set[str] = set()
    vote_times: dict[str, datetime] = {}
    previous_vote_at: datetime | None = None
    for index, vote in enumerate(votes):
        path = f"review.vote_history[{index}]"
        _require(vote, {"vote_id", "annotator_id", "submitted_at", "decision"}, path, errors)
        if not isinstance(vote, dict):
            continue
        vote_id = vote.get("vote_id")
        annotator_id = vote.get("annotator_id")
        submitted_at = vote.get("submitted_at")
        submitted_at_instant = _parse_timestamp(submitted_at)
        _check_id(vote_id, f"{path}.vote_id", errors)
        _check_id(annotator_id, f"{path}.annotator_id", errors)
        if isinstance(vote_id, str) and vote_id in vote_ids:
            errors.append(_error("duplicate_vote_id", path))
        if isinstance(vote_id, str):
            vote_ids.add(vote_id)
            if submitted_at_instant is not None:
                vote_times[vote_id] = submitted_at_instant
        if isinstance(annotator_id, str):
            annotators.add(annotator_id)
        if submitted_at_instant is None:
            errors.append(_error("invalid_timestamp", f"{path}.submitted_at"))
        elif previous_vote_at is not None and submitted_at_instant <= previous_vote_at:
            errors.append(_error("invalid_review_chronology", f"{path}.submitted_at must strictly follow prior vote"))
        if submitted_at_instant is not None:
            previous_vote_at = submitted_at_instant
        _check_enum(vote.get("decision"), {"accept", "reject", "abstain"}, f"{path}.decision", errors)
    adjudications = _check_list(review.get("adjudication_history"), "review.adjudication_history", errors)
    adjudication_ids: set[str] = set()
    previous_adjudication_at: datetime | None = None
    for index, adjudication in enumerate(adjudications):
        path = f"review.adjudication_history[{index}]"
        _require(adjudication, {"adjudication_id", "adjudicator_id", "occurred_at", "based_on_vote_ids", "outcome"}, path, errors)
        if not isinstance(adjudication, dict):
            continue
        adjudication_id = adjudication.get("adjudication_id")
        occurred_at = adjudication.get("occurred_at")
        occurred_at_instant = _parse_timestamp(occurred_at)
        _check_id(adjudication_id, f"{path}.adjudication_id", errors)
        _check_id(adjudication.get("adjudicator_id"), f"{path}.adjudicator_id", errors)
        if isinstance(adjudication_id, str) and adjudication_id in adjudication_ids:
            errors.append(_error("duplicate_adjudication_id", path))
        if isinstance(adjudication_id, str):
            adjudication_ids.add(adjudication_id)
        if occurred_at_instant is None:
            errors.append(_error("invalid_timestamp", f"{path}.occurred_at"))
        elif previous_adjudication_at is not None and occurred_at_instant <= previous_adjudication_at:
            errors.append(_error("invalid_review_chronology", f"{path}.occurred_at must follow prior adjudication"))
        if occurred_at_instant is not None:
            previous_adjudication_at = occurred_at_instant
        based_on = _check_list(adjudication.get("based_on_vote_ids"), f"{path}.based_on_vote_ids", errors, nonempty=True)
        referenced_vote_ids = {vote_id for vote_id in based_on if isinstance(vote_id, str)}
        if len(referenced_vote_ids) != len(based_on) or not referenced_vote_ids.issubset(vote_ids):
            errors.append(_error("unknown_vote_reference", path))
        if occurred_at_instant is not None:
            for vote_id in referenced_vote_ids:
                submitted_at = vote_times.get(vote_id)
                if submitted_at is not None and occurred_at_instant <= submitted_at:
                    errors.append(_error("invalid_review_chronology", f"{path}.occurred_at must follow referenced vote {vote_id}"))
        _check_enum(adjudication.get("outcome"), {"accepted", "rejected", "quarantined"}, f"{path}.outcome", errors)
    status = review.get("status")
    if status == "unreviewed" and (votes or adjudications):
        errors.append(_error("review_status_mismatch", "unreviewed record has review events"))
    if status == "dual_reviewed" and len(annotators) < 2:
        errors.append(_error("review_status_mismatch", "dual_reviewed requires two annotators"))
    if status == "dual_reviewed" and adjudications:
        errors.append(_error("review_status_mismatch", "dual_reviewed cannot contain adjudications"))
    if status == "adjudicated" and (len(annotators) < 2 or not adjudications):
        errors.append(_error("review_status_mismatch", "adjudicated requires two votes and adjudication history"))


def _validate_release_review(review: Any, split: Any, errors: list[str]) -> None:
    """Require a resolved independent human review before release admission."""
    if split not in RELEASE_SPLITS:
        return
    if not isinstance(review, dict):
        errors.append(_error("review_not_admissible", f"{split} requires resolved human review"))
        return
    status = review.get("status")
    votes = review.get("vote_history") if isinstance(review.get("vote_history"), list) else []
    adjudications = review.get("adjudication_history") if isinstance(review.get("adjudication_history"), list) else []
    valid_votes = [vote for vote in votes if isinstance(vote, dict)]
    annotators = {vote.get("annotator_id") for vote in valid_votes if isinstance(vote.get("annotator_id"), str)}
    vote_ids = {vote.get("vote_id") for vote in valid_votes if isinstance(vote.get("vote_id"), str)}
    decisions = [vote.get("decision") for vote in valid_votes]

    if len(valid_votes) < 2 or len(annotators) < 2 or len(vote_ids) != len(valid_votes):
        errors.append(_error("review_not_admissible", f"{split} requires two independent annotator votes"))
        return
    if status == "dual_reviewed":
        if adjudications:
            errors.append(_error("review_not_admissible", "dual_reviewed release review cannot include adjudication history"))
        if len(set(decisions)) > 1:
            errors.append(_error("review_conflict_unresolved", "conflicting independent votes require adjudication"))
        elif decisions != ["accept"] * len(decisions):
            errors.append(_error("review_not_admissible", "release review votes must all accept"))
        return
    if status != "adjudicated":
        errors.append(_error("review_not_admissible", f"{split} requires dual_reviewed or adjudicated review"))
        return
    if not adjudications:
        errors.append(_error("missing_adjudication", "adjudicated release review requires adjudication history"))
        return
    latest = adjudications[-1] if isinstance(adjudications[-1], dict) else {}
    based_on = latest.get("based_on_vote_ids") if isinstance(latest.get("based_on_vote_ids"), list) else []
    referenced_vote_ids = {vote_id for vote_id in based_on if isinstance(vote_id, str)}
    if len(referenced_vote_ids) != len(based_on) or referenced_vote_ids != vote_ids:
        errors.append(_error("invalid_adjudication_scope", "latest adjudication must resolve every independent vote"))
    elif latest.get("outcome") != "accepted":
        errors.append(_error("review_not_admissible", "release adjudication outcome must be accepted"))


def _validate_sequence(sequence: Any, media_assets: set[str], source_assets: set[str], errors: list[str]) -> None:
    _require(sequence, {"sequence_id", "frame_count", "frames", "timeline"}, "sequence", errors)
    if not isinstance(sequence, dict):
        return
    _check_id(sequence.get("sequence_id"), "sequence.sequence_id", errors)
    frames = _check_list(sequence.get("frames"), "sequence.frames", errors, nonempty=True)
    if len(frames) < 2:
        errors.append(_error("invalid_sequence_length", "temporal sequence requires at least two frames"))
    frame_assets: list[str] = []
    ordinals: list[int] = []
    timestamps: list[int] = []
    for index, frame in enumerate(frames):
        path = f"sequence.frames[{index}]"
        _require(frame, {"frame_id", "ordinal", "timestamp_ms", "asset_id", "state"}, path, errors)
        if not isinstance(frame, dict):
            continue
        _check_id(frame.get("frame_id"), f"{path}.frame_id", errors)
        asset_id = frame.get("asset_id")
        _check_id(asset_id, f"{path}.asset_id", errors)
        frame_assets.append(asset_id)
        if asset_id not in source_assets:
            errors.append(_error("missing_source_asset", f"{path}.asset_id"))
        ordinal = frame.get("ordinal")
        timestamp = frame.get("timestamp_ms")
        if not _is_strict_int(ordinal) or ordinal < 0:
            errors.append(_error("invalid_sequence_numeric_type" if not _is_strict_int(ordinal) else "invalid_sequence_order", f"{path}.ordinal"))
        else:
            ordinals.append(ordinal)
        if not _is_strict_int(timestamp) or timestamp < 0:
            errors.append(_error("invalid_sequence_numeric_type" if not _is_strict_int(timestamp) else "invalid_sequence_timestamp", f"{path}.timestamp_ms"))
        else:
            timestamps.append(timestamp)
        _check_enum(frame.get("state"), {"acquire", "stable", "moving", "rotation", "lens_change", "lighting_transition", "scene_cut", "unknown"}, f"{path}.state", errors)
    frame_count = sequence.get("frame_count")
    if not _is_strict_int(frame_count):
        errors.append(_error("invalid_sequence_numeric_type", "sequence.frame_count"))
    elif frame_count < 2:
        errors.append(_error("invalid_sequence_length", "sequence.frame_count"))
    elif frame_count != len(frames):
        errors.append(_error("invalid_sequence_order", "sequence.frame_count does not match frames"))
    if ordinals != list(range(len(frames))):
        errors.append(_error("invalid_sequence_order", "frame ordinals must be contiguous"))
    if timestamps != sorted(timestamps) or len(set(timestamps)) != len(timestamps):
        errors.append(_error("invalid_sequence_timestamp", "timestamps must be strictly increasing"))
    if set(frame_assets) != media_assets or set(frame_assets) != source_assets:
        errors.append(_error("sequence_asset_mismatch", "sequence/source/media asset sets differ"))
    timeline = _check_list(sequence.get("timeline"), "sequence.timeline", errors, nonempty=True)
    expected_start = 0
    for index, segment in enumerate(timeline):
        path = f"sequence.timeline[{index}]"
        _require(segment, {"state", "start_frame", "end_frame"}, path, errors)
        if not isinstance(segment, dict):
            continue
        _check_enum(segment.get("state"), {"acquire", "stable", "moving", "rotation", "lens_change", "lighting_transition", "scene_cut", "unknown"}, f"{path}.state", errors)
        start = segment.get("start_frame")
        end = segment.get("end_frame")
        if (
            not _is_strict_int(start)
            or not _is_strict_int(end)
            or start != expected_start
            or end < start
            or end >= len(frames)
        ):
            errors.append(_error(
                "invalid_sequence_numeric_type" if not _is_strict_int(start) or not _is_strict_int(end) else "invalid_sequence_timeline",
                f"{path}.start_frame/end_frame" if not _is_strict_int(start) or not _is_strict_int(end) else f"{path}: segments must be non-overlapping and cover every frame",
            ))
        else:
            expected_start = end + 1
    if timeline and expected_start != len(frames):
        errors.append(_error("invalid_sequence_timeline", "segments must cover every frame exactly once"))


def _validate_episode(episode: Any, accepted: set[str], verifications: list[Any], media_assets: set[str], source_assets: set[str], errors: list[str]) -> None:
    _require(episode, {"episode_id", "before", "action_step", "after", "outcome", "outcome_verifier", "subject_continuity"}, "episode", errors)
    if not isinstance(episode, dict):
        return
    _check_id(episode.get("episode_id"), "episode.episode_id", errors)
    before = episode.get("before")
    after = episode.get("after")
    for name, value in (("before", before), ("after", after)):
        path = f"episode.{name}"
        _require(value, {"asset_id", "captured_at"}, path, errors)
        if not isinstance(value, dict):
            continue
        asset_id = value.get("asset_id")
        _check_id(asset_id, f"{path}.asset_id", errors)
        if asset_id not in source_assets:
            errors.append(_error("missing_source_asset", f"{path}.asset_id"))
        _check_timestamp(value.get("captured_at"), f"{path}.captured_at", errors)
    if isinstance(before, dict) and isinstance(after, dict) and before.get("asset_id") == after.get("asset_id"):
        errors.append(_error("invalid_episode", "before and after assets must differ"))
    action_step = episode.get("action_step")
    _require(action_step, {"action_id", "performed_at"}, "episode.action_step", errors)
    action = None
    if isinstance(action_step, dict):
        action = action_step.get("action_id")
        if action not in ACTION_IDS or action not in accepted:
            errors.append(_error("invalid_action_id", "episode.action_step.action_id must be acceptable"))
        _check_timestamp(action_step.get("performed_at"), "episode.action_step.performed_at", errors)
    before_at = _parse_timestamp(before.get("captured_at")) if isinstance(before, dict) else None
    action_at = _parse_timestamp(action_step.get("performed_at")) if isinstance(action_step, dict) else None
    after_at = _parse_timestamp(after.get("captured_at")) if isinstance(after, dict) else None
    if (
        before_at is not None
        and action_at is not None
        and after_at is not None
        and not (before_at < action_at < after_at)
    ):
        errors.append(_error("invalid_episode_order", "chronology requires before < action_step < after"))
    verifier = episode.get("outcome_verifier")
    if action in VERIFIER_BY_ACTION and verifier != VERIFIER_BY_ACTION[action]:
        errors.append(_error("invalid_action_verifier", "episode.outcome_verifier"))
    _check_enum(episode.get("outcome"), {"correct", "no_op", "opposite", "overshoot", "track_loss", "incomparable"}, "episode.outcome", errors)
    _check_enum(episode.get("outcome_verifier"), VERIFIER_IDS, "episode.outcome_verifier", errors)
    _check_enum(episode.get("subject_continuity"), {"same", "changed", "lost", "unknown"}, "episode.subject_continuity", errors)
    if isinstance(before, dict) and isinstance(after, dict) and {before.get("asset_id"), after.get("asset_id")} - media_assets:
        errors.append(_error("episode_asset_mismatch", "before/after assets must be in media.asset_ids"))
    matching = [
        item for item in verifications
        if isinstance(item, dict) and item.get("action_id") == action and item.get("verifier_id") == verifier
    ]
    measurable = {"correct", "no_op", "opposite", "overshoot"}
    has_passed_before_after = any(item.get("result") == "pass" and item.get("measurement") == "before_after" for item in matching)
    if episode.get("outcome") in measurable and not has_passed_before_after:
        errors.append(_error("invalid_episode_outcome", f"{episode.get('outcome')} requires matching action verification pass/before_after"))
    if episode.get("outcome") in measurable and episode.get("subject_continuity") != "same":
        errors.append(_error("invalid_episode_outcome", f"{episode.get('outcome')} requires subject_continuity=same"))
    if episode.get("outcome") not in measurable and has_passed_before_after:
        errors.append(_error("contradictory_episode_outcome", "non-measurable outcome cannot have a matching pass/before_after verification"))


def _validate_manifest_references(record: dict[str, Any], manifests: dict[str, list[dict[str, Any]]], errors: list[str], *, fixture_mode: bool) -> None:
    source_by_id = {entry.get("source_shoot_id"): entry for entry in manifests.get("source_shoots", [])}
    consent_by_id = {entry.get("consent_record_id"): entry for entry in manifests.get("consents", [])}
    rights_by_id = {entry.get("rights_record_id"): entry for entry in manifests.get("rights", [])}
    derivation_by_record: dict[Any, dict[str, Any]] = {}
    for entry in manifests.get("derivations", []):
        derivation_by_record.setdefault(entry.get("record_id"), entry)
    provenance = record.get("provenance")
    if not isinstance(provenance, dict):
        return
    source_id = provenance.get("source_shoot_id")
    source = source_by_id.get(source_id)
    if source is None:
        errors.append(_error("missing_source_shoot", str(source_id)))
        return
    source_kind = source.get("source_kind")
    if provenance.get("source_kind") != source_kind:
        errors.append(_error("source_authority_mismatch", "provenance.source_kind must equal resolved source-shoot source_kind"))
    split = record.get("split")
    # Admission is based on the resolved source authority. A claimant cannot
    # relabel a synthetic source as owned/licensed to bypass release gates.
    if source_kind == "synthetic_fixture" and split not in {"fixture", "quarantine"}:
        errors.append(_error("synthetic_source_not_admissible", "resolved source_shoot source_kind is synthetic_fixture"))
    if split == "fixture" and (not fixture_mode or source_kind != "synthetic_fixture"):
        errors.append(_error("synthetic_data_not_admitted", "fixture split requires a resolved synthetic_fixture source"))
    source_assets = set(source.get("asset_ids", []))
    record_source_assets = set(provenance.get("source_asset_ids", []))
    media = record.get("media") if isinstance(record.get("media"), dict) else {}
    media_asset_ids = {asset_id for asset_id in media.get("asset_ids", []) if isinstance(asset_id, str)}
    # Temporal/episode records may use an aggregate primary asset not repeated
    # in asset_ids; both fields still need independent authority resolution.
    media_asset_refs = media_asset_ids | ({media.get("asset_id")} if isinstance(media.get("asset_id"), str) else set())
    if not record_source_assets.issubset(source_assets):
        errors.append(_error("missing_source_asset", "provenance.source_asset_ids"))
    if not media_asset_refs.issubset(source_assets):
        errors.append(_error("missing_source_asset", "media.asset_id/media.asset_ids"))
    capture = record.get("capture")
    if not isinstance(capture, dict):
        capture = {}
    for field in ("scene_family_id", "take_family_id", "time_family_id", "location_family_id", "device_family_id"):
        if capture.get(field) != source.get(field):
            errors.append(_error("family_mismatch", f"capture.{field}"))
    if set(capture.get("person_family_ids", [])) != set(source.get("person_family_ids", [])):
        errors.append(_error("family_mismatch", "capture.person_family_ids"))
    for field in ("orientation", "lens", "lighting"):
        if capture.get(field) != source.get(field):
            errors.append(_error("capture_context_mismatch", f"capture.{field}"))
    rights_id = provenance.get("rights_record_id")
    rights = rights_by_id.get(rights_id)
    if rights is None:
        errors.append(_error("missing_rights_record", str(rights_id)))
    else:
        _check_id(rights.get("consent_record_id"), "rights.consent_record_id", errors)
        if rights.get("source_shoot_id") != source_id:
            errors.append(_error("provenance_mismatch", "rights source_shoot_id"))
        consent_id = rights.get("consent_record_id")
        consent = consent_by_id.get(consent_id)
        if consent is None:
            errors.append(_error("missing_consent_record", str(consent_id)))
        else:
            _check_enum(consent.get("disposition"), RIGHTS_DISPOSITIONS, "consent.disposition", errors)
            if consent.get("source_shoot_id") != source_id:
                errors.append(_error("provenance_mismatch", "consent source_shoot_id"))
            consent_assets = {asset_id for asset_id in consent.get("asset_ids", []) if isinstance(asset_id, str)}
            if not set(rights.get("asset_ids", [])).issubset(consent_assets):
                errors.append(_error("consent_scope_mismatch", "consent asset_ids"))
            if consent.get("disposition") != rights.get("disposition"):
                errors.append(_error("provenance_mismatch", "consent disposition"))
            if not set(rights.get("allowed_uses", [])).issubset(set(consent.get("allowed_uses", []))):
                errors.append(_error("consent_scope_mismatch", "consent allowed_uses"))
            consent_allowed = set(consent.get("allowed_uses", []))
            if split in RELEASE_SPLITS and (consent.get("disposition") != "approved" or split not in consent_allowed):
                errors.append(_error("consent_not_admissible", f"{split} requires approved consent and allowed use"))
            if split == "fixture" and (not fixture_mode or consent.get("disposition") != "fixture_only" or "fixture" not in consent_allowed):
                errors.append(_error("consent_not_admissible", "fixture split is synthetic-test-only"))
        rights_assets = set(rights.get("asset_ids", []))
        if not record_source_assets.issubset(rights_assets) or not media_asset_refs.issubset(rights_assets):
            errors.append(_error("rights_scope_mismatch", "rights asset_ids"))
        if rights.get("disposition") != provenance.get("rights_disposition"):
            errors.append(_error("provenance_mismatch", "rights disposition"))
        allowed = set(rights.get("allowed_uses", []))
        if split in {"train", "calibration", "holdout"} and (rights.get("disposition") != "approved" or split not in allowed):
            errors.append(_error("rights_not_approved", f"{split} requires approved rights and allowed use"))
        if split == "fixture" and (not fixture_mode or rights.get("disposition") != "fixture_only" or "fixture" not in allowed):
            errors.append(_error("rights_not_approved", "fixture split is synthetic-test-only"))
    derivation = derivation_by_record.get(record.get("record_id"))
    if derivation is None:
        errors.append(_error("missing_derivation_record", record.get("record_id", "")))
    else:
        if derivation.get("source_shoot_id") != source_id or derivation.get("derivation_family_id") != provenance.get("derivation_family_id"):
            errors.append(_error("family_mismatch", "derivation family/source shoot"))
        derivation_kind = derivation.get("derivation_kind")
        _check_enum(derivation_kind, DERIVATION_KINDS, "derivation.derivation_kind", errors, code="invalid_derivation_kind")
        independent = derivation.get("is_independent")
        counts_toward_quota = derivation.get("counts_toward_quota")
        if independent is not True or derivation_kind in NON_INDEPENDENT_DERIVATION_KINDS:
            errors.append(_error("non_independent_derivation", record.get("record_id", "")))
        expected_kind = {"still": "original_still", "temporal": "original_temporal_sequence", "episode": "original_before_after_episode"}.get(record.get("record_type"))
        if independent is True and derivation_kind != expected_kind:
            errors.append(_error("invalid_derivation_kind", "independent derivation kind does not match record type"))
        if split in RELEASE_SPLITS and independent is True and counts_toward_quota is not True:
            errors.append(_error("invalid_quota_semantics", f"{split} independent record must count toward quota"))
        if split in {"fixture", "quarantine"} and counts_toward_quota is True:
            errors.append(_error("invalid_quota_semantics", f"{split} record cannot count toward release quota"))
        derivation_outputs = set(derivation.get("output_asset_ids", []))
        if not record_source_assets.issubset(derivation_outputs) or not media_asset_refs.issubset(derivation_outputs):
            errors.append(_error("provenance_mismatch", "derivation output assets"))


def validate_record(record: Any, manifests: dict[str, list[dict[str, Any]]], *, fixture_mode: bool = False) -> list[str]:
    if not isinstance(record, dict):
        return [_error("invalid_object", "record")]
    errors: list[str] = []
    _validate_closed_keys(record, "record", "record", errors)
    _check_no_locked_outputs(record, "record", errors)
    required = {"schema_id", "schema_version", "record_id", "record_type", "matrix_class", "split", "media", "capture", "provenance", "subject", "style_intent", "label", "review"}
    _require(record, required, "record", errors)
    record_type = record.get("record_type")
    _check_enum(record_type, RECORD_TYPES, "record.record_type", errors)
    expected_schema = {"still": "camera-label-v1", "temporal": "camera-temporal-v1", "episode": "camera-episode-v1"}.get(record_type)
    if record.get("schema_id") != expected_schema:
        errors.append(_error("schema_record_type_mismatch", "record.schema_id"))
    if record.get("schema_version") != SCHEMA_VERSION:
        errors.append(_error("invalid_schema_version", "record.schema_version"))
    if not isinstance(record.get("record_id"), str) or not RECORD_ID_RE.fullmatch(record.get("record_id", "")):
        errors.append(_error("invalid_record_id", "record.record_id"))
    _check_enum(record.get("matrix_class"), MATRIX_CLASSES, "record.matrix_class", errors)
    _check_enum(record.get("split"), SPLITS, "record.split", errors)
    media_assets = _validate_media(record.get("media"), errors)
    capture = record.get("capture") if isinstance(record.get("capture"), dict) else {}
    _validate_capture(record.get("capture"), errors)
    source_assets = _validate_provenance(record.get("provenance"), errors)
    subject = record.get("subject")
    _validate_subject(subject, errors)
    style = record.get("style_intent")
    _require(style, {"style_id", "intentional", "basis"}, "style_intent", errors)
    if isinstance(style, dict):
        _check_enum(style.get("style_id"), {"naturalistic", "cinematic", "documentary", "commercial", "stylized", "already_good", "unknown"}, "style_intent.style_id", errors)
        if not isinstance(style.get("intentional"), bool):
            errors.append(_error("invalid_style_intent", "style_intent.intentional"))
        _check_enum(style.get("basis"), {"capture_brief", "annotator_observed", "not_available", "fixture"}, "style_intent.basis", errors)
    label = record.get("label")
    _validate_label(label, errors)
    _validate_subject_label_semantics(subject, label, errors)
    _validate_review(record.get("review"), errors)
    _validate_release_review(record.get("review"), record.get("split"), errors)
    accepted = set(label.get("acceptable_action_ids", [])) if isinstance(label, dict) else set()
    if record_type == "still":
        if capture.get("capture_mode") != "still":
            errors.append(_error("capture_context_mismatch", "still capture_mode"))
        if "sequence" in record or "episode" in record:
            errors.append(_error("unexpected_record_extension", "still record"))
    elif record_type == "temporal":
        if capture.get("capture_mode") != "temporal_sequence":
            errors.append(_error("capture_context_mismatch", "temporal capture_mode"))
        if "sequence" not in record:
            errors.append(_error("missing_sequence", "temporal.sequence"))
        else:
            _validate_sequence(record.get("sequence"), media_assets, source_assets, errors)
        if "episode" in record:
            errors.append(_error("unexpected_record_extension", "temporal record"))
    elif record_type == "episode":
        if capture.get("capture_mode") != "before_after_episode":
            errors.append(_error("capture_context_mismatch", "episode capture_mode"))
        if "episode" not in record:
            errors.append(_error("missing_episode", "episode.episode"))
        else:
            verifications = label.get("verification", []) if isinstance(label, dict) else []
            _validate_episode(record.get("episode"), accepted, verifications, media_assets, source_assets, errors)
        if "sequence" in record:
            errors.append(_error("unexpected_record_extension", "episode record"))
    _validate_manifest_references(record, manifests, errors, fixture_mode=fixture_mode)
    return errors


def validate_split_isolation(records: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    family_splits: dict[str, set[str]] = {}
    for record in records:
        if not isinstance(record, dict):
            continue
        provenance = record.get("provenance") if isinstance(record.get("provenance"), dict) else {}
        capture = record.get("capture") if isinstance(record.get("capture"), dict) else {}
        families = [provenance.get("source_shoot_id"), capture.get("scene_family_id"), capture.get("take_family_id"), capture.get("time_family_id"), capture.get("location_family_id"), capture.get("device_family_id"), provenance.get("derivation_family_id")]
        families += capture.get("person_family_ids", []) if isinstance(capture.get("person_family_ids"), list) else []
        for family in families:
            if family:
                family_splits.setdefault(family, set()).add(record.get("split"))
    for family, splits in family_splits.items():
        admitted = splits & {"train", "calibration", "holdout"}
        if len(admitted) > 1:
            errors.append(_error("family_cross_split", family))
    return errors


def _validate_fixture_manifests(manifests: dict[str, list[dict[str, Any]]]) -> list[str]:
    errors: list[str] = []
    source_ids: set[str] = set()
    source_assets: dict[str, set[str]] = {}
    for index, entry in enumerate(manifests.get("source_shoots", [])):
        path = f"manifests.source_shoots[{index}]"
        _require(entry, {"manifest_type", "schema_id", "manifest_version", "source_shoot_id", "scene_family_id", "take_family_id", "time_family_id", "location_family_id", "person_family_ids", "device_family_id", "orientation", "lens", "lighting", "asset_ids", "storage", "source_kind"}, path, errors)
        if not isinstance(entry, dict):
            continue
        _validate_closed_keys(entry, "source_shoot_entry", path, errors)
        if entry.get("manifest_type") != "source_shoot_entry" or entry.get("schema_id") != "camera-source-shoot-v1" or entry.get("manifest_version") != SCHEMA_VERSION:
            errors.append(_error("invalid_manifest_entry", path))
        source_id = entry.get("source_shoot_id")
        _check_id(source_id, f"{path}.source_shoot_id", errors)
        if source_id in source_ids:
            errors.append(_error("duplicate_manifest_id", path))
        source_ids.add(source_id)
        assets = _check_list(entry.get("asset_ids"), f"{path}.asset_ids", errors, nonempty=True)
        asset_set = set(assets)
        if len(asset_set) != len(assets):
            errors.append(_error("duplicate_manifest_id", f"{path}.asset_ids"))
        for asset_id in assets:
            _check_id(asset_id, f"{path}.asset_ids", errors)
        source_assets[source_id] = asset_set
        _check_enum(entry.get("source_kind"), SOURCE_KINDS, f"{path}.source_kind", errors)
        if entry.get("storage") != "outside_git":
            errors.append(_error("raw_media_inside_git", path))
    consent_ids: set[str] = set()
    consent_by_id: dict[str, dict[str, Any]] = {}
    consent_assets: dict[str, set[str]] = {}
    for index, entry in enumerate(manifests.get("consents", [])):
        path = f"manifests.consents[{index}]"
        _require(entry, {"manifest_type", "schema_id", "manifest_version", "consent_record_id", "source_shoot_id", "asset_ids", "disposition", "allowed_uses", "evidence_ref", "recorded_at"}, path, errors)
        if not isinstance(entry, dict):
            continue
        _validate_closed_keys(entry, "consent_entry", path, errors)
        if entry.get("manifest_type") != "consent_entry" or entry.get("schema_id") != "camera-consent-entry-v1" or entry.get("manifest_version") != SCHEMA_VERSION:
            errors.append(_error("invalid_manifest_entry", path))
        consent_id = entry.get("consent_record_id")
        _check_id(consent_id, f"{path}.consent_record_id", errors)
        if consent_id in consent_ids:
            errors.append(_error("duplicate_manifest_id", path))
        consent_ids.add(consent_id)
        consent_by_id[consent_id] = entry
        source_id = entry.get("source_shoot_id")
        if source_id not in source_ids:
            errors.append(_error("missing_source_shoot", path))
        assets = _check_list(entry.get("asset_ids"), f"{path}.asset_ids", errors, nonempty=True)
        asset_set = {asset_id for asset_id in assets if isinstance(asset_id, str)}
        if source_id in source_assets and not asset_set.issubset(source_assets[source_id]):
            errors.append(_error("missing_source_asset", path))
        consent_assets[consent_id] = asset_set
        _check_enum(entry.get("disposition"), RIGHTS_DISPOSITIONS, f"{path}.disposition", errors)
        allowed_uses = _check_list(entry.get("allowed_uses"), f"{path}.allowed_uses", errors, nonempty=True)
        for use in allowed_uses:
            _check_enum(use, RIGHTS_USES, f"{path}.allowed_uses", errors)
        if not isinstance(entry.get("evidence_ref"), str) or not entry.get("evidence_ref"):
            errors.append(_error("missing_consent_evidence", path))
        _check_timestamp(entry.get("recorded_at"), f"{path}.recorded_at", errors)
    rights_ids: set[str] = set()
    for index, entry in enumerate(manifests.get("rights", [])):
        path = f"manifests.rights[{index}]"
        _require(entry, {"manifest_type", "schema_id", "manifest_version", "rights_record_id", "source_shoot_id", "consent_record_id", "asset_ids", "disposition", "allowed_uses", "evidence_ref", "recorded_at"}, path, errors)
        if not isinstance(entry, dict):
            continue
        _validate_closed_keys(entry, "rights_entry", path, errors)
        if entry.get("manifest_type") != "rights_entry" or entry.get("schema_id") != "camera-rights-entry-v1" or entry.get("manifest_version") != SCHEMA_VERSION:
            errors.append(_error("invalid_manifest_entry", path))
        rights_id = entry.get("rights_record_id")
        _check_id(rights_id, f"{path}.rights_record_id", errors)
        if rights_id in rights_ids:
            errors.append(_error("duplicate_manifest_id", path))
        rights_ids.add(rights_id)
        source_id = entry.get("source_shoot_id")
        if source_id not in source_ids:
            errors.append(_error("missing_source_shoot", path))
        consent_id = entry.get("consent_record_id")
        consent = consent_by_id.get(consent_id)
        if consent is None:
            errors.append(_error("missing_consent_record", str(consent_id)))
        else:
            if consent.get("source_shoot_id") != source_id:
                errors.append(_error("provenance_mismatch", f"{path}.consent source_shoot_id"))
        assets = _check_list(entry.get("asset_ids"), f"{path}.asset_ids", errors, nonempty=True)
        asset_set = {asset_id for asset_id in assets if isinstance(asset_id, str)}
        if source_id in source_assets and not asset_set.issubset(source_assets[source_id]):
            errors.append(_error("missing_source_asset", path))
        if consent is not None:
            if not asset_set.issubset(consent_assets.get(consent_id, set())):
                errors.append(_error("consent_scope_mismatch", path))
            if consent.get("disposition") != entry.get("disposition"):
                errors.append(_error("provenance_mismatch", f"{path}.consent disposition"))
            if not set(entry.get("allowed_uses", [])).issubset(set(consent.get("allowed_uses", []))):
                errors.append(_error("consent_scope_mismatch", f"{path}.consent allowed_uses"))
        _check_id(entry.get("consent_record_id"), f"{path}.consent_record_id", errors)
        _check_enum(entry.get("disposition"), RIGHTS_DISPOSITIONS, f"{path}.disposition", errors)
        allowed_uses = _check_list(entry.get("allowed_uses"), f"{path}.allowed_uses", errors, nonempty=True)
        for use in allowed_uses:
            _check_enum(use, RIGHTS_USES, f"{path}.allowed_uses", errors)
        if not isinstance(entry.get("evidence_ref"), str) or not entry.get("evidence_ref"):
            errors.append(_error("missing_rights_evidence", path))
        _check_timestamp(entry.get("recorded_at"), f"{path}.recorded_at", errors)
    derivation_ids: set[str] = set()
    derivation_record_ids: set[str] = set()
    for index, entry in enumerate(manifests.get("derivations", [])):
        path = f"manifests.derivations[{index}]"
        _require(entry, {"manifest_type", "schema_id", "manifest_version", "derivation_id", "source_shoot_id", "record_id", "input_asset_ids", "output_asset_ids", "derivation_family_id", "derivation_kind", "is_independent", "counts_toward_quota"}, path, errors)
        if not isinstance(entry, dict):
            continue
        _validate_closed_keys(entry, "derivation_entry", path, errors)
        if entry.get("manifest_type") != "derivation_entry" or entry.get("schema_id") != "camera-derivation-entry-v1" or entry.get("manifest_version") != SCHEMA_VERSION:
            errors.append(_error("invalid_manifest_entry", path))
        derivation_id = entry.get("derivation_id")
        _check_id(derivation_id, f"{path}.derivation_id", errors)
        if derivation_id in derivation_ids:
            errors.append(_error("duplicate_manifest_id", path))
        derivation_ids.add(derivation_id)
        source_id = entry.get("source_shoot_id")
        if source_id not in source_ids:
            errors.append(_error("missing_source_shoot", path))
        output_assets = _check_list(entry.get("output_asset_ids"), f"{path}.output_asset_ids", errors, nonempty=True)
        input_assets = _check_list(entry.get("input_asset_ids"), f"{path}.input_asset_ids", errors, nonempty=True)
        if source_id in source_assets and not set(output_assets).issubset(source_assets[source_id]):
            errors.append(_error("missing_source_asset", path))
        if not set(input_assets).issubset(set(output_assets)):
            errors.append(_error("provenance_mismatch", path))
        _check_id(entry.get("record_id"), f"{path}.record_id", errors)
        record_id = entry.get("record_id")
        if record_id in derivation_record_ids:
            errors.append(_error("duplicate_derivation_record", record_id))
        derivation_record_ids.add(record_id)
        _check_id(entry.get("derivation_family_id"), f"{path}.derivation_family_id", errors)
        derivation_kind = entry.get("derivation_kind")
        _check_enum(derivation_kind, DERIVATION_KINDS, f"{path}.derivation_kind", errors, code="invalid_derivation_kind")
        independent = entry.get("is_independent")
        counts_toward_quota = entry.get("counts_toward_quota")
        if not isinstance(independent, bool) or not isinstance(counts_toward_quota, bool):
            errors.append(_error("invalid_derivation_flag", path))
        elif isinstance(derivation_kind, str):
            expected_independent = derivation_kind in INDEPENDENT_DERIVATION_KINDS
            if independent != expected_independent:
                errors.append(_error("invalid_derivation_flag", f"{path}: derivation kind and independence disagree"))
            if counts_toward_quota and not independent:
                errors.append(_error("invalid_quota_semantics", f"{path}: non-independent derivation cannot count toward quota"))
    return errors


def _validate_manifest_header(path: Path, expected_type: str) -> list[str]:
    errors: list[str] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) != 1:
        return [_error("invalid_manifest_template", f"{path} must contain one header line")]
    try:
        header = json.loads(lines[0])
    except json.JSONDecodeError as exc:
        return [_error("json_parse_error", f"{path}: {exc}")]
    required = {"manifest_type", "schema_id", "manifest_version", "manifest_id", "manifest_sha256", "entry_schema", "record_count", "hash_algorithm", "raw_data_location", "rights_uncleared_location", "template_only"}
    _require(header, required, str(path), errors)
    if header.get("manifest_type") != expected_type:
        errors.append(_error("invalid_manifest_template", f"{path} manifest_type"))
    if header.get("manifest_version") != SCHEMA_VERSION:
        errors.append(_error("invalid_schema_version", str(path)))
    _check_id(header.get("manifest_id"), f"{path}.manifest_id", errors)
    _check_sha(header.get("manifest_sha256"), f"{path}.manifest_sha256", errors)
    if isinstance(header.get("manifest_sha256"), str) and header.get("manifest_sha256") != _canonical_digest(header, "manifest_sha256"):
        errors.append(_error("stale_manifest_hash", str(path)))
    if header.get("record_count") != 0 or header.get("hash_algorithm") != "sha256":
        errors.append(_error("invalid_manifest_template", str(path)))
    if header.get("raw_data_location") != "outside_git" or header.get("rights_uncleared_location") != "outside_git":
        errors.append(_error("raw_media_inside_git", str(path)))
    if header.get("template_only") is not True:
        errors.append(_error("invalid_manifest_template", f"{path} template_only"))
    return errors


def _read_collection(path: Path) -> list[dict[str, Any]]:
    """Read a JSON array/object or JSONL collection without using fixture state."""
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        return []
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = []
        for line_number, line in enumerate(text.splitlines(), start=1):
            if not line.strip():
                continue
            try:
                payload.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: {exc}") from exc
    if isinstance(payload, dict):
        if isinstance(payload.get("records"), list):
            payload = payload["records"]
        elif isinstance(payload.get("valid_records"), list):
            # This supports extracting a caller-selected record collection from
            # the synthetic fixture while deliberately ignoring its manifests.
            payload = payload["valid_records"]
        else:
            payload = [payload]
    if not isinstance(payload, list) or any(not isinstance(item, dict) for item in payload):
        raise ValueError(f"{path} must contain a JSON object collection")
    return payload


def _load_external_manifests(source_path: Path, consent_path: Path, rights_path: Path, derivation_path: Path) -> dict[str, list[dict[str, Any]]]:
    """Load only caller-supplied manifests for production/batch admission."""
    collections = {
        "source_shoots": _read_collection(source_path),
        "consents": _read_collection(consent_path),
        "rights": _read_collection(rights_path),
        "derivations": _read_collection(derivation_path),
    }
    manifests: dict[str, list[dict[str, Any]]] = {}
    for name, entries in collections.items():
        manifests[name] = [entry for entry in entries if entry.get("template_only") is not True]
    return manifests


def validate_schema_files() -> list[str]:
    errors: list[str] = []
    for filename in SCHEMA_FILES:
        path = CAMERA_DIR / filename
        try:
            schema = _read_json(path)
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(_error("json_parse_error", f"{path}: {exc}"))
            continue
        if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            errors.append(_error("invalid_schema_dialect", filename))
        if schema.get("schema_version") != SCHEMA_VERSION:
            errors.append(_error("invalid_schema_version", filename))
        if filename == "label-schema.json":
            required = set(schema.get("required", []))
            expected = {"record_id", "record_type", "matrix_class", "split", "provenance", "review"}
            if not expected.issubset(required):
                errors.append(_error("schema_missing_required_field", filename))
            classes = set(schema.get("properties", {}).get("matrix_class", {}).get("enum", []))
            if classes != MATRIX_CLASSES:
                errors.append(_error("schema_matrix_class_mismatch", filename))
            actions = set(schema.get("$defs", {}).get("actionId", {}).get("enum", []))
            if actions != ACTION_IDS:
                errors.append(_error("canonical_action_drift", "label-schema actionId enum differs from camera-coach-contract-v2 approvedActionIDs"))
            verification_actions = set(schema.get("$defs", {}).get("verificationActionId", {}).get("enum", []))
            if verification_actions != ACTION_IDS | {"abstain"}:
                errors.append(_error("canonical_action_drift", "label-schema verificationActionId enum differs from approved actions plus abstain"))
            if set(VERIFIER_BY_ACTION) != ACTION_IDS:
                errors.append(_error("action_verifier_catalog_mismatch", "every approved action needs one verifier predicate"))
            evidence = schema.get("$defs", {}).get("issue", {}).get("properties", {}).get("evidence", {}).get("items", {}).get("enum")
            if not isinstance(evidence, list) or set(evidence) != ISSUE_EVIDENCE_IDS or len(evidence) != len(ISSUE_EVIDENCE_IDS):
                errors.append(_error("issue_evidence_catalog_mismatch", "label-schema issue evidence enum drift"))
        if schema.get("title", "").startswith("Camera Coach") is False:
            errors.append(_error("invalid_schema_title", filename))
    return errors


def _load_fixture() -> dict[str, Any]:
    fixture = _read_json(FIXTURE_PATH)
    if not isinstance(fixture, dict) or fixture.get("synthetic") is not True:
        raise ValueError("camera fixture must be explicitly synthetic")
    return fixture


def _set_path(mapping: Any, path: str, value: Any, *, remove: bool = False) -> None:
    parts = path.split(".")
    current = mapping
    for part in parts[:-1]:
        if part.isdigit():
            current = current[int(part)]
        else:
            current = current[part]
    leaf = parts[-1]
    if leaf.isdigit():
        if remove:
            current.pop(int(leaf))
        else:
            current[int(leaf)] = value
    elif remove:
        current.pop(leaf, None)
    else:
        current[leaf] = value


def _apply_mutations(record: dict[str, Any], manifests: dict[str, list[dict[str, Any]]], mutations: list[dict[str, Any]]) -> None:
    for mutation in mutations:
        target = mutation["target"]
        if target == "record":
            target_object: Any = record
        elif target == "rights":
            rights_id = record["provenance"]["rights_record_id"]
            target_object = next(item for item in manifests["rights"] if item["rights_record_id"] == rights_id)
        elif target == "consent":
            rights_id = record["provenance"]["rights_record_id"]
            rights = next(item for item in manifests["rights"] if item["rights_record_id"] == rights_id)
            target_object = next(item for item in manifests["consents"] if item["consent_record_id"] == rights["consent_record_id"])
        elif target == "derivation":
            target_object = next(item for item in manifests["derivations"] if item["record_id"] == record["record_id"])
        else:
            raise ValueError(f"unknown fixture mutation target: {target}")
        _set_path(target_object, mutation["path"], mutation.get("value"), remove=mutation.get("operation") == "remove")


def validate_batch(records: list[dict[str, Any]], manifests: dict[str, list[dict[str, Any]]], *, fixture_mode: bool = False) -> list[str]:
    """Validate an externally supplied collection and isolate all families."""
    errors = _validate_fixture_manifests(manifests)
    record_ids: set[str] = set()
    for record in records:
        record_id = record.get("record_id")
        if isinstance(record_id, str):
            if record_id in record_ids:
                errors.append(_error("duplicate_record_id", record_id))
            record_ids.add(record_id)
        errors.extend(validate_record(record, manifests, fixture_mode=fixture_mode))
    errors.extend(validate_split_isolation(records))
    for entry in manifests.get("derivations", []):
        if entry.get("record_id") not in record_ids:
            errors.append(_error("orphan_derivation_record", str(entry.get("record_id"))))
    return errors


def self_test() -> None:
    schema_errors = validate_schema_files()
    assert not schema_errors, schema_errors
    for name, expected_type in (("source-shoots.jsonl", "source_shoots"), ("consent-manifest.jsonl", "consent"), ("rights-manifest.jsonl", "rights"), ("derivation-manifest.jsonl", "derivation")):
        errors = _validate_manifest_header(CAMERA_DIR / name, expected_type)
        assert not errors, errors
    fixture = _load_fixture()
    manifests = fixture["manifests"]
    manifest_errors = _validate_fixture_manifests(manifests)
    assert not manifest_errors, manifest_errors
    valid_records = fixture["valid_records"]
    assert len(valid_records) == 3
    for record in valid_records:
        errors = validate_record(record, manifests, fixture_mode=True)
        assert not errors, (record.get("record_id"), errors)
    resolved_review = {
        "status": "dual_reviewed",
        "vote_history": [
            {"vote_id": "vote-self-test-001", "annotator_id": "annotator-self-test-001", "submitted_at": "2026-09-05T00:00:00Z", "decision": "accept"},
            {"vote_id": "vote-self-test-002", "annotator_id": "annotator-self-test-002", "submitted_at": "2026-09-05T00:00:01Z", "decision": "accept"},
        ],
        "adjudication_history": [],
    }
    resolved_review_errors: list[str] = []
    _validate_review(resolved_review, resolved_review_errors)
    _validate_release_review(resolved_review, "train", resolved_review_errors)
    assert not resolved_review_errors, resolved_review_errors
    adjudicated_review = copy.deepcopy(resolved_review)
    adjudicated_review["status"] = "adjudicated"
    adjudicated_review["adjudication_history"] = [{
        "adjudication_id": "adjudication-self-test-001",
        "adjudicator_id": "adjudicator-self-test-001",
        "occurred_at": "2026-09-05T00:00:02Z",
        "based_on_vote_ids": ["vote-self-test-001", "vote-self-test-002"],
        "outcome": "accepted",
    }]
    adjudicated_review_errors: list[str] = []
    _validate_review(adjudicated_review, adjudicated_review_errors)
    _validate_release_review(adjudicated_review, "calibration", adjudicated_review_errors)
    assert not adjudicated_review_errors, adjudicated_review_errors
    for outcome in ("correct", "no_op", "opposite", "overshoot"):
        measurable_episode = copy.deepcopy(valid_records[2])
        measurable_episode["episode"]["outcome"] = outcome
        errors = validate_record(measurable_episode, manifests, fixture_mode=True)
        assert not errors, (outcome, errors)
    keep = copy.deepcopy(valid_records[0])
    keep["label"] = {
        "issues": [],
        "acceptable_action_ids": ["keep_current_setup"],
        "forbidden_action_ids": [],
        "selected_action_id": "keep_current_setup",
        "selection_status": "single",
        "keep_decision": "keep",
        "abstention": {"status": "none", "reasons": []},
        "verification": [{"action_id": "keep_current_setup", "verifier_id": "frame_remains_acceptable", "result": "not_run", "measurement": "single_frame"}],
    }
    assert not validate_record(keep, manifests, fixture_mode=True)
    abstain_selected_subject = copy.deepcopy(valid_records[0])
    abstain_selected_subject["label"] = {
        "issues": [],
        "acceptable_action_ids": [],
        "forbidden_action_ids": [],
        "selected_action_id": None,
        "selection_status": "abstain",
        "keep_decision": "uncertain",
        "abstention": {"status": "abstain", "reasons": ["subject_unclear"]},
        "verification": [{"action_id": "abstain", "verifier_id": "insufficient_evidence", "result": "inconclusive", "measurement": "not_observed"}],
    }
    assert not validate_record(abstain_selected_subject, manifests, fixture_mode=True)
    abstain_subject = copy.deepcopy(abstain_selected_subject)
    abstain_subject["subject"] = {"status": "abstain", "candidates": [], "selected_subject_id": None}
    assert not validate_record(abstain_subject, manifests, fixture_mode=True)
    select_subject = copy.deepcopy(valid_records[0])
    select_subject["subject"] = {
        "status": "ambiguous",
        "candidates": [
            {"subject_id": "subject-fixture-001", "kind": "person", "reference": "subject-fixture-001"},
            {"subject_id": "subject-fixture-001-b", "kind": "person", "reference": "subject-fixture-001-b"},
        ],
        "selected_subject_id": None,
    }
    select_subject["label"] = {
        "issues": [],
        "acceptable_action_ids": [],
        "forbidden_action_ids": [],
        "selected_action_id": None,
        "selection_status": "no_action",
        "keep_decision": "uncertain",
        "abstention": {"status": "none", "reasons": []},
        "verification": [{"action_id": "keep_current_setup", "verifier_id": "frame_remains_acceptable", "result": "not_run", "measurement": "single_frame"}],
    }
    assert not validate_record(select_subject, manifests, fixture_mode=True)
    assert not validate_split_isolation(valid_records)
    invalid_passes = 0
    for case in fixture["invalid_cases"]:
        base = next(record for record in valid_records if record["record_id"] == case["base_record_id"])
        record = copy.deepcopy(base)
        case_manifests = copy.deepcopy(manifests)
        _apply_mutations(record, case_manifests, case["mutations"])
        errors = _validate_fixture_manifests(case_manifests)
        errors.extend(validate_record(record, case_manifests, fixture_mode=True))
        reason = case["declared_reason"]
        assert errors and any(reason in error for error in errors), (case["case_id"], reason, errors)
        invalid_passes += 1
    print(f"PASS M3-002 schemas matrix_classes={len(MATRIX_CLASSES)} actions={len(ACTION_IDS)} keep=1 abstain=1")
    print(f"PASS M3-003 references valid_records={len(valid_records)} rights_dispositions=fixture_only invalid_cases={invalid_passes}")
    print("PASS M3-004 temporal_sequence=1 timeline=full_nonoverlap episode_outcomes=correct/no_op/opposite/overshoot measurable_subject_continuity=same capture_families=scene/take/time/device/derivation")
    print("PASS M3-005 fixture_review_status=unreviewed release_gate=resolved_human_review vote_history=append_only adjudication_history=separate human_calibration=pending")
    print(f"PASS camera-coach self-test valid={len(valid_records)} invalid={invalid_passes}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--record", type=Path)
    parser.add_argument("--batch-records", type=Path, help="caller-supplied JSON/JSONL record collection")
    parser.add_argument("--source-shoots", type=Path, help="caller-supplied source-shoot manifest JSON/JSONL")
    parser.add_argument("--consent-manifest", type=Path, help="caller-supplied consent manifest JSON/JSONL")
    parser.add_argument("--rights-manifest", type=Path, help="caller-supplied rights manifest JSON/JSONL")
    parser.add_argument("--derivation-manifest", type=Path, help="caller-supplied derivation manifest JSON/JSONL")
    parser.add_argument("--fixture-mode", action="store_true", help="explicitly admit synthetic_fixture records only for fixture tests")
    args = parser.parse_args(argv)
    manifest_paths = (args.source_shoots, args.consent_manifest, args.rights_manifest, args.derivation_manifest)
    has_all_manifests = all(path is not None for path in manifest_paths)
    if args.self_test:
        self_test()
        return 0
    if args.record is None and args.batch_records is None:
        self_test()
        return 0
    if args.record is not None and args.batch_records is not None:
        print(_error("input_error", "--record and --batch-records are mutually exclusive"), file=sys.stderr)
        return 1
    if not has_all_manifests:
        print(_error("input_error", "explicit --source-shoots, --consent-manifest, --rights-manifest, and --derivation-manifest are required for admission"), file=sys.stderr)
        return 1
    try:
        manifests = _load_external_manifests(args.source_shoots, args.consent_manifest, args.rights_manifest, args.derivation_manifest)
        if args.batch_records is not None:
            records = _read_collection(args.batch_records)
            errors = validate_batch(records, manifests, fixture_mode=args.fixture_mode)
        else:
            record = _read_json(args.record)
            errors = _validate_fixture_manifests(manifests)
            errors.extend(validate_record(record, manifests, fixture_mode=args.fixture_mode))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(_error("input_error", str(exc)), file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    if args.batch_records is not None:
        print(
            f"PASS {args.batch_records} camera-coach-batch "
            f"records={len(records)} source_shoots={len(manifests['source_shoots'])} "
            f"consents={len(manifests['consents'])} rights={len(manifests['rights'])} "
            f"derivations={len(manifests['derivations'])}"
        )
    else:
        print(f"PASS {args.record} camera-coach-record")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
