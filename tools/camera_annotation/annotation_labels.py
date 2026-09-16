#!/usr/bin/env python3
"""Human review records for the Camera Coach annotation tool.

The historical schema name retains 'human-gold' for compatibility; creating a
record does not grant gold/release admission. The review pilot uses
review_pipeline.training_record for the frozen v2 targets and missing-label
masks. In that path unsure is review uncertainty, not abstention supervision,
and borderline does not fabricate a binary good-frame target. The legacy
training_targets helper below retains its old semantics for existing callers.

Records are append-only JSONL. Teacher proposals live in a separate store;
human reviews retain only the proposal ID and assistance provenance.

Deliberate rule encoded here: an ugly frame with `improvement_needed=false`
is allowed only with a note. That is the documented "intentional mood" case
(dark, low-key, silhouette) — the coach must confirm it instead of "fixing"
it, and the label has to say so explicitly.
"""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

SCHEMA_ID = "camera-human-gold-label-v1"
SCHEMA_VERSION = 1

# Frozen from ml/camera_coach/contracts/set_composition_net_v1.json
ISSUES: tuple[str, ...] = (
    "subject_too_close_to_edge",
    "subject_not_prominent_enough",
    "background_competes_with_subject",
    "insufficient_look_space",
    "backlight_hides_subject",
    "scene_has_no_clear_focus",
    "frame_visually_overloaded",
    "horizon_distracts",
)

ACTIONS: tuple[str, ...] = (
    "shift_frame_left",
    "shift_frame_right",
    "shift_frame_up",
    "shift_frame_down",
    "step_back",
    "step_closer",
    "lower_camera",
    "raise_camera",
    "change_camera_angle",
    "level_horizon",
    "rotate_subject_toward_light",
    "move_subject_left",
    "move_subject_right",
    "move_subject_away_from_background",
    "move_object_left",
    "move_object_right",
    "move_object_forward",
    "move_object_back",
    "remove_distracting_object",
    "reposition_prop_for_balance",
    "add_front_fill_light",
    "add_background_light",
    "remove_background_hotspot",
    "simplify_background",
    "wait_for_background_clearance",
    "keep_current_setup",
)

DELTAS: tuple[str, ...] = (
    "delta_x",
    "delta_y",
    "scale_delta",
    "light_delta",
    "horizon_delta",
)

KEEP_ACTION = "keep_current_setup"

BEAUTY_LEVELS: tuple[str, ...] = ("beautiful", "borderline", "ugly")
INTENT_STYLES = ("natural", "silhouette", "low_key", "symmetry", "negative_space",
                 "dutch_angle", "intentional_motion_blur", "handheld")
MATRIX_CLASSES = ("single_person", "two_people", "object_or_food", "interior",
                  "street_or_landscape", "difficult_light", "already_good_frame")
REGION_ROLES: tuple[str, ...] = ("subject", "distractor", "problem", "target")

# good_frame_probability target per beauty level.
BEAUTY_TARGET: dict[str, float] = {"beautiful": 1.0, "borderline": 0.5, "ugly": 0.0}


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_label(record: dict) -> list[str]:
    """Return every admission error; an empty list means the record is valid."""
    errors: list[str] = []

    if record.get("schema_id") != SCHEMA_ID:
        errors.append(f"schema_id must be {SCHEMA_ID}")
    if record.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}")
    for required in ("record_id", "image_sha256", "annotator_id", "created_at", "beauty"):
        if not record.get(required):
            errors.append(f"{required} is required")

    beauty = record.get("beauty")
    undecided = record.get("unsure") is True and beauty == "unrated"
    if beauty is not None and beauty not in BEAUTY_LEVELS and not undecided:
        errors.append(f"beauty must be one of {list(BEAUTY_LEVELS)}")

    improvement_needed = record.get("improvement_needed")
    if not isinstance(improvement_needed, bool) and not (undecided and improvement_needed is None):
        errors.append("improvement_needed must be a boolean")
    if improvement_needed is None and (record.get("issues") or record.get("actions") or record.get("deltas")):
        errors.append("undecided review cannot carry asserted corrections")

    issues = record.get("issues") or []
    if not isinstance(issues, list):
        errors.append("issues must be a list")
        issues = []
    unknown_issues = [i for i in issues if i not in ISSUES]
    if unknown_issues:
        errors.append(f"unknown issues: {unknown_issues}")
    if len(set(issues)) != len(issues):
        errors.append("issues must not repeat")

    actions = record.get("actions") or []
    if not isinstance(actions, list):
        errors.append("actions must be a list")
        actions = []
    unknown_actions = [a for a in actions if a not in ACTIONS]
    if unknown_actions:
        errors.append(f"unknown actions: {unknown_actions}")
    if len(set(actions)) != len(actions):
        errors.append("actions must not repeat")
    forbidden = record.get("forbidden_actions", [])
    if not isinstance(forbidden, list) or not all(isinstance(a, str) and a in ACTIONS for a in forbidden):
        errors.append("forbidden_actions must contain approved action IDs")
    elif len(set(forbidden)) != len(forbidden) or set(forbidden).intersection(actions):
        errors.append("forbidden actions repeat or contradict acceptable actions")
    if record.get("unsure") and forbidden:
        errors.append("uncertain review cannot assert forbidden actions")

    if isinstance(improvement_needed, bool):
        corrective = [a for a in actions if a != KEEP_ACTION]
        if improvement_needed:
            if not corrective:
                errors.append("improvement_needed=true requires at least one corrective action")
            if KEEP_ACTION in actions:
                errors.append("improvement_needed=true forbids keep_current_setup")
            if not issues:
                errors.append("improvement_needed=true requires at least one issue")
        else:
            if actions != [KEEP_ACTION]:
                errors.append("improvement_needed=false requires actions=['keep_current_setup']")
            if issues:
                errors.append("improvement_needed=false forbids issues")
            # Intentional-mood escape hatch: an ugly frame may still be a keep,
            # but only when the annotator explains why.
            if beauty == "ugly" and not (record.get("notes") or "").strip():
                errors.append("beauty='ugly' with improvement_needed=false requires a note (intentional mood)")

    for index, region in enumerate(record.get("regions") or []):
        if not isinstance(region, dict):
            errors.append(f"regions[{index}] must be an object")
            continue
        role = region.get("role")
        if "label" in region and (not isinstance(region["label"], str) or len(region["label"]) > 200):
            errors.append(f"regions[{index}].label must be a string of at most 200 characters")
        if role not in REGION_ROLES:
            errors.append(f"regions[{index}].role must be one of {list(REGION_ROLES)}")
        rect = region.get("rect")
        if (not isinstance(rect, list) or len(rect) != 4
                or not all(isinstance(v, (int, float)) for v in rect)):
            errors.append(f"regions[{index}].rect must be [x, y, w, h]")
        else:
            x, y, w, h = (float(v) for v in rect)
            if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0 and 0.0 < w <= 1.0 and 0.0 < h <= 1.0
                    and x + w <= 1.0001 and y + h <= 1.0001):
                errors.append(f"regions[{index}].rect must be normalized inside [0,1]")

    deltas = record.get("deltas")
    if deltas is not None:
        if not isinstance(deltas, dict):
            errors.append("deltas must be an object when present")
        else:
            for key, value in deltas.items():
                if key not in DELTAS:
                    errors.append(f"unknown delta '{key}'")
                elif not isinstance(value, (int, float)) or not -1.0 <= float(value) <= 1.0:
                    errors.append(f"deltas.{key} must be a number in [-1,1]")
                elif improvement_needed is False and float(value) != 0:
                    errors.append("KEEP cannot carry a nonzero corrective delta")

    if record.get("unsure") is not None and not isinstance(record.get("unsure"), bool):
        errors.append("unsure must be a boolean when present")

    if record.get("assisted") is not None and not isinstance(record.get("assisted"), bool):
        errors.append("assisted must be a boolean when present")
    if record.get("assisted") and not record.get("assist_source"):
        errors.append("assisted=true requires assist_source")
    if record.get("assist_source") is not None and not isinstance(record.get("assist_source"), str):
        errors.append("assist_source must be a string when present")
    if record.get("capture_intent") is not None and record["capture_intent"] not in INTENT_STYLES:
        errors.append("unknown capture_intent")
    if record.get("matrix_class") is not None and record["matrix_class"] not in MATRIX_CLASSES:
        errors.append("unknown matrix_class")
    if record.get("review_mode") is not None and record["review_mode"] not in ("blind", "assisted"):
        errors.append("review_mode must be blind or assisted")
    if record.get("review_mode") == "blind" and (record.get("assisted") or record.get("teacher_proposal_id")):
        errors.append("blind review cannot carry assistance or teacher references")
    if record.get("teacher_proposal_id") is not None:
        if not isinstance(record["teacher_proposal_id"], str) or not record["teacher_proposal_id"]:
            errors.append("teacher_proposal_id must be a nonempty string")
        if not record.get("assisted"):
            errors.append("teacher exposure must be marked assisted")

    return errors


def build_label(
    *,
    record_id: str,
    image_sha256: str,
    annotator_id: str,
    beauty: str,
    improvement_needed: bool | None,
    issues: Iterable[str] = (),
    actions: Iterable[str] = (),
    regions: Iterable[dict] | None = None,
    deltas: dict | None = None,
    unsure: bool = False,
    notes: str = "",
    image_path: str | None = None,
    provenance: dict | None = None,
    created_at: str | None = None,
    assisted: bool = False,
    assist_source: str | None = None,
    human_score: float | None = None,
    capture_intent: str | None = None,
    review_mode: str | None = None,
    teacher_proposal_id: str | None = None,
    matrix_class: str | None = None,
    forbidden_actions: Iterable[str] = (),
) -> dict:
    record: dict[str, Any] = {
        "schema_id": SCHEMA_ID,
        "schema_version": SCHEMA_VERSION,
        "record_id": record_id,
        "image_sha256": image_sha256,
        "annotator_id": annotator_id,
        "beauty": beauty,
        "improvement_needed": improvement_needed,
        "issues": list(dict.fromkeys(issues)),
        "actions": list(dict.fromkeys(actions)),
        "regions": list(regions or []),
        "unsure": bool(unsure),
        "notes": notes,
        "created_at": created_at or _utc_now(),
        "assisted": bool(assisted),
    }
    if assist_source:
        record["assist_source"] = assist_source
    if human_score is not None:
        record["human_score"] = float(human_score)
    if deltas:
        record["deltas"] = dict(deltas)
    if image_path:
        record["image_path"] = image_path
    if provenance:
        record["provenance"] = dict(provenance)
    if review_mode is not None:
        record.update(capture_intent=capture_intent, review_mode=review_mode,
                      research_only=True, release_admissible=False, label_origin="human_review")
    elif capture_intent is not None:
        record["capture_intent"] = capture_intent
    if teacher_proposal_id:
        record["teacher_proposal_id"] = teacher_proposal_id
    if matrix_class is not None:
        record["matrix_class"] = matrix_class
    if forbidden_actions:
        record["forbidden_actions"] = list(dict.fromkeys(forbidden_actions))

    errors = validate_label(record)
    if errors:
        raise ValueError("invalid label: " + "; ".join(errors))
    return record


def append_label(path: Path, record: dict) -> int:
    """Append one validated label; returns the new record count."""
    errors = validate_label(record)
    if errors:
        raise ValueError("invalid label: " + "; ".join(errors))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def load_labels(path: Path) -> list[dict]:
    if not path.exists():
        return []
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records


def labelled_record_ids(path: Path) -> set[str]:
    return {r["record_id"] for r in load_labels(path) if r.get("record_id")}


def training_targets(record: dict) -> dict:
    """Convert one label into the contract's training targets.

    Masking rules (D02a, runbook 2026-09-13):

    * an unexpressed delta stays ``None`` per element — a fabricated ``0.0``
      would teach "no change needed", a claim the annotator never made;
    * an ``unsure`` record masks the issue/action/delta heads entirely instead of
      turning absence into negative evidence; the abstention head carries it;
    * ``target_mask`` states the masking explicitly so no consumer can read
      ``None`` as a value by accident.
    """
    errors = validate_label(record)
    if errors:
        raise ValueError("invalid label: " + "; ".join(errors))

    actions = set(record.get("actions") or [])
    expressed = {name: float(value) for name, value in (record.get("deltas") or {}).items()}
    unsure = bool(record.get("unsure"))

    return {
        "record_id": record["record_id"],
        "good_frame_probability": BEAUTY_TARGET.get(record["beauty"]),
        "abstention_probability": 1.0 if unsure else 0.0,
        "issue_logits": None if unsure else [1.0 if name in set(record.get("issues") or []) else 0.0 for name in ISSUES],
        "action_utility_logits": None if unsure else [1.0 if name in actions else 0.0 for name in ACTIONS],
        "continuous_target_deltas": None if unsure else [expressed.get(name) for name in DELTAS],
        "target_mask": {
            "unsure": unsure,
            "issue_logits": [not unsure] * len(ISSUES),
            "action_utility_logits": [not unsure] * len(ACTIONS),
            "continuous_target_deltas": [False if unsure else name in expressed for name in DELTAS],
        },
        "regions": record.get("regions") or [],
    }


def label_summary(records: list[dict]) -> dict:
    """Fit-only summary the annotator can read back; never a quality claim."""
    total = len(records)
    per_beauty: dict[str, int] = {level: 0 for level in BEAUTY_LEVELS}
    per_issue: dict[str, int] = {name: 0 for name in ISSUES}
    per_action: dict[str, int] = {name: 0 for name in ACTIONS}
    unsure = 0
    with_regions = 0
    for record in records:
        per_beauty[record.get("beauty", "borderline")] = per_beauty.get(record.get("beauty"), 0) + 1
        for name in record.get("issues") or []:
            per_issue[name] = per_issue.get(name, 0) + 1
        for name in record.get("actions") or []:
            per_action[name] = per_action.get(name, 0) + 1
        unsure += 1 if record.get("unsure") else 0
        with_regions += 1 if record.get("regions") else 0
    return {
        "total": total,
        "per_beauty": per_beauty,
        "unsure": unsure,
        "with_regions": with_regions,
        "per_issue": {k: v for k, v in per_issue.items() if v},
        "per_action": {k: v for k, v in per_action.items() if v},
        "metrics_scope": "annotation coverage only; no quality or release claim",
    }
