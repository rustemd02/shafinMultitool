#!/usr/bin/env python3
"""Semantic camera label loader and eval-case projection.

This module intentionally validates the first-pass dataset before any scoring
logic runs. Bad labels are worse than no labels here: they would train us to
"fix" the camera coach in the wrong direction.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence


QUALITY_LABELS = {"good", "mixed", "bad"}
CONFIDENCE_TARGETS = {"high", "medium", "low"}

SEMANTIC_ACTION_TYPES = {
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
}

FUTURE_TECHNICAL_ACTION_TYPES = {
    "stabilize_camera",
    "refocus_subject",
    "reduce_exposure",
    "increase_exposure",
    "avoid_occlusion",
    "clean_lens",
    "reduce_iso_noise",
}

REQUIRED_FIELDS = (
    "record_id",
    "filename",
    "image_path",
    "source_bucket",
    "source_dataset",
    "quality_label",
    "scene_type",
    "primary_subject",
    "positive_factors",
    "problems",
    "technical_quality_defects",
    "expected_live_tip",
    "expected_pause_summary",
    "expected_semantic_actions",
    "future_needed_actions",
    "forbidden_actions",
    "confidence_target",
    "demo_priority",
    "eval_tags",
    "review_status",
)


@dataclass(frozen=True)
class SemanticLabelIssue:
    record_id: str
    path: str
    message: str

    def render(self) -> str:
        return f"[{self.record_id}] {self.path}: {self.message}"


class SemanticLabelValidationError(ValueError):
    def __init__(self, issues: Sequence[SemanticLabelIssue]) -> None:
        self.issues = list(issues)
        rendered = "\n".join(issue.render() for issue in self.issues[:20])
        extra = "" if len(self.issues) <= 20 else f"\n... and {len(self.issues) - 20} more"
        super().__init__(rendered + extra)


def _read_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SemanticLabelValidationError(
                [SemanticLabelIssue("<jsonl>", f"line:{line_no}", f"invalid json: {exc}")]
            ) from exc
        if not isinstance(row, dict):
            raise SemanticLabelValidationError(
                [SemanticLabelIssue("<jsonl>", f"line:{line_no}", "row must be object")]
            )
        rows.append(row)
    return rows


def _is_non_empty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_str_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def _validate_list_actions(
    issues: List[SemanticLabelIssue],
    row: Dict[str, Any],
    field: str,
    allowed: Iterable[str],
) -> None:
    record_id = str(row.get("record_id", "<unknown>"))
    value = row.get(field)
    allowed_set = set(allowed)
    if not _is_str_list(value):
        issues.append(SemanticLabelIssue(record_id, field, "must be list[str]"))
        return
    for index, action in enumerate(value):
        if action not in allowed_set:
            issues.append(
                SemanticLabelIssue(
                    record_id,
                    f"{field}[{index}]",
                    f"invalid action {action!r}",
                )
            )


def validate_semantic_label_records(
    rows: Sequence[Dict[str, Any]],
    *,
    images_dir: Path | None = None,
) -> None:
    issues: List[SemanticLabelIssue] = []
    seen_record_ids: set[str] = set()
    seen_filenames: set[str] = set()

    for index, row in enumerate(rows):
        record_id = str(row.get("record_id", f"<row:{index}>"))
        for field in REQUIRED_FIELDS:
            if field not in row:
                issues.append(SemanticLabelIssue(record_id, field, "missing required field"))

        if not _is_non_empty_str(row.get("record_id")):
            issues.append(SemanticLabelIssue(record_id, "record_id", "must be non-empty string"))
        elif record_id in seen_record_ids:
            issues.append(SemanticLabelIssue(record_id, "record_id", "duplicate record id"))
        else:
            seen_record_ids.add(record_id)

        filename = row.get("filename")
        if not _is_non_empty_str(filename):
            issues.append(SemanticLabelIssue(record_id, "filename", "must be non-empty string"))
        elif str(filename) in seen_filenames:
            issues.append(SemanticLabelIssue(record_id, "filename", "duplicate filename"))
        else:
            seen_filenames.add(str(filename))
            if images_dir is not None and not (images_dir / str(filename)).exists():
                issues.append(
                    SemanticLabelIssue(
                        record_id,
                        "filename",
                        f"image file not found under {images_dir.as_posix()}",
                    )
                )

        quality = row.get("quality_label")
        if quality not in QUALITY_LABELS:
            issues.append(SemanticLabelIssue(record_id, "quality_label", f"invalid value {quality!r}"))

        confidence_target = row.get("confidence_target")
        if confidence_target not in CONFIDENCE_TARGETS:
            issues.append(
                SemanticLabelIssue(record_id, "confidence_target", f"invalid value {confidence_target!r}")
            )

        for field in (
            "positive_factors",
            "problems",
            "technical_quality_defects",
            "eval_tags",
        ):
            if not _is_str_list(row.get(field)):
                issues.append(SemanticLabelIssue(record_id, field, "must be list[str]"))

        for field in ("expected_live_tip", "expected_pause_summary"):
            if not _is_non_empty_str(row.get(field)):
                issues.append(SemanticLabelIssue(record_id, field, "must be non-empty string"))

        if not isinstance(row.get("demo_priority"), bool):
            issues.append(SemanticLabelIssue(record_id, "demo_priority", "must be bool"))

        _validate_list_actions(issues, row, "expected_semantic_actions", SEMANTIC_ACTION_TYPES)
        _validate_list_actions(issues, row, "forbidden_actions", SEMANTIC_ACTION_TYPES)
        _validate_list_actions(issues, row, "future_needed_actions", FUTURE_TECHNICAL_ACTION_TYPES)

        expected_actions = set(row.get("expected_semantic_actions", []))
        forbidden_actions = set(row.get("forbidden_actions", []))
        overlap = sorted(expected_actions & forbidden_actions)
        if overlap:
            issues.append(
                SemanticLabelIssue(
                    record_id,
                    "expected_semantic_actions",
                    f"must not overlap forbidden_actions: {overlap}",
                )
            )

    if issues:
        raise SemanticLabelValidationError(issues)


def load_semantic_label_records(
    path: Path,
    *,
    images_dir: Path | None = None,
) -> List[Dict[str, Any]]:
    rows = _read_jsonl(path)
    validate_semantic_label_records(rows, images_dir=images_dir)
    return rows


def normalize_semantic_label_cases(records: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    cases: List[Dict[str, Any]] = []
    for row in records:
        cases.append(
            {
                "case_id": row["record_id"],
                "record_id": row["record_id"],
                "image_ref": row["filename"],
                "filename": row["filename"],
                "image_path": row["image_path"],
                "quality_label": row["quality_label"],
                "scene_type": row["scene_type"],
                "primary_subject": row["primary_subject"],
                "positive_factors": list(row["positive_factors"]),
                "problems": list(row["problems"]),
                "technical_quality_defects": list(row["technical_quality_defects"]),
                "expected_actions": list(row["expected_semantic_actions"]),
                "future_actions": list(row["future_needed_actions"]),
                "forbidden_actions": list(row["forbidden_actions"]),
                "expected_live_text_class": row["expected_live_tip"],
                "expected_pause_summary": row["expected_pause_summary"],
                "confidence_target": row["confidence_target"],
                "demo_priority": bool(row["demo_priority"]),
                "tags": list(row["eval_tags"]),
                "source_bucket": row["source_bucket"],
                "source_dataset": row["source_dataset"],
                "review_status": row["review_status"],
            }
        )
    return cases
