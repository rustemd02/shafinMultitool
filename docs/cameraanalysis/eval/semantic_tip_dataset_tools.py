#!/usr/bin/env python3
"""Tools for PR-S06 semantic tip dataset validation and hard-case exchange."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence, Tuple

from eval_io import read_json, read_jsonl, write_json, write_jsonl


SEMANTIC_TIP_DATASET_SCHEMA_VERSION = "s6.v1"

SOURCE_BUCKETS = {
    "curated_demo",
    "curated_real",
    "runtime_hard_case",
    "public_relicensed_demo",
}

DATASET_SPLITS = {"train", "validation", "test", "holdout"}
MODE_TARGETS = {"pause", "live", "both"}
CASE_KINDS = {"still_frame", "structured_only_case", "redacted_visual_case"}
VISUAL_AVAILABILITY = {
    "none_structured_only",
    "redacted_visual_available",
    "private_not_exported",
}

PRIVACY_TIERS = {"structured_only", "redacted_visual"}
EXPORT_STATUSES = {
    "repo_safe_structured_only",
    "repo_safe_redacted_visual",
    "internal_only",
    "blocked",
}

REVIEW_DECISIONS = {
    "accepted_teacher_tip",
    "edited_teacher_tip",
    "rejected_teacher_tip",
    "deterministic_only",
    "no_tip_should_fire",
    "needs_followup",
}

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

ACTION_FRAMES = {"move_camera", "move_subject", "move_object", "adjust_light", "wait"}
DIRECTIONS = {"left", "right", "up", "down", "forward", "back", "none"}
LABEL_SOURCES = {"deterministic_local", "vlm_visual", "vlm_structured_copy", "human_override"}

REVIEWED_DECISIONS = {
    "accepted_teacher_tip",
    "edited_teacher_tip",
    "rejected_teacher_tip",
    "deterministic_only",
    "no_tip_should_fire",
}


@dataclass(frozen=True)
class ValidationIssue:
    record_id: str
    path: str
    message: str

    def render(self) -> str:
        return f"[{self.record_id}] {self.path}: {self.message}"


def _is_non_empty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _ensure_enum(
    issues: List[ValidationIssue],
    record_id: str,
    value: Any,
    allowed: Sequence[str],
    path: str,
) -> None:
    if value not in allowed:
        issues.append(ValidationIssue(record_id, path, f"invalid value {value!r}"))


def _ensure_required_keys(
    issues: List[ValidationIssue],
    record_id: str,
    payload: Dict[str, Any],
    keys: Iterable[str],
    path_prefix: str,
) -> None:
    for key in keys:
        if key not in payload:
            issues.append(ValidationIssue(record_id, f"{path_prefix}.{key}", "missing required field"))


def _validate_final_tip(
    record_id: str,
    final_tip: Dict[str, Any],
    issues: List[ValidationIssue],
) -> None:
    required = (
        "tipType",
        "actionType",
        "actionFrame",
        "targetEntityKind",
        "targetEntityRole",
        "targetEntityDisplayLabel",
        "labelConfidence",
        "linkedSemanticActionTypes",
    )
    _ensure_required_keys(issues, record_id, final_tip, required, "review.finalTip")

    action_type = final_tip.get("actionType")
    _ensure_enum(issues, record_id, action_type, tuple(SEMANTIC_ACTION_TYPES), "review.finalTip.actionType")
    _ensure_enum(issues, record_id, final_tip.get("actionFrame"), tuple(ACTION_FRAMES), "review.finalTip.actionFrame")

    direction = final_tip.get("direction")
    if direction is not None:
        _ensure_enum(issues, record_id, direction, tuple(DIRECTIONS), "review.finalTip.direction")

    linked_semantic_actions = final_tip.get("linkedSemanticActionTypes", [])
    if not isinstance(linked_semantic_actions, list):
        issues.append(ValidationIssue(record_id, "review.finalTip.linkedSemanticActionTypes", "must be list"))
        linked_semantic_actions = []
    else:
        for idx, value in enumerate(linked_semantic_actions):
            _ensure_enum(
                issues,
                record_id,
                value,
                tuple(SEMANTIC_ACTION_TYPES),
                f"review.finalTip.linkedSemanticActionTypes[{idx}]",
            )

    if isinstance(action_type, str) and action_type and action_type not in linked_semantic_actions:
        issues.append(
            ValidationIssue(
                record_id,
                "review.finalTip.linkedSemanticActionTypes",
                "must include finalTip.actionType",
            )
        )

    if final_tip.get("actionFrame") == "wait" and action_type != "wait_for_background_clearance":
        issues.append(
            ValidationIssue(
                record_id,
                "review.finalTip",
                "actionFrame=wait requires actionType=wait_for_background_clearance",
            )
        )

    if action_type == "keep_current_setup" and final_tip.get("problemType") is not None:
        issues.append(
            ValidationIssue(
                record_id,
                "review.finalTip.problemType",
                "keep_current_setup must not include problemType",
            )
        )

    label_confidence = final_tip.get("labelConfidence")
    if not isinstance(label_confidence, (float, int)) or not (0.0 <= float(label_confidence) <= 1.0):
        issues.append(ValidationIssue(record_id, "review.finalTip.labelConfidence", "must be in [0, 1]"))


def _validate_teacher_grounding(
    record_id: str,
    teacher: Dict[str, Any],
    privacy_tier: str,
    issues: List[ValidationIssue],
) -> None:
    for key in ("groundedTarget", "groundedSecondary"):
        grounded = teacher.get(key)
        if grounded is None:
            continue
        if not isinstance(grounded, dict):
            issues.append(ValidationIssue(record_id, f"teacher.{key}", "must be object"))
            continue
        label_source = grounded.get("labelSource")
        _ensure_enum(issues, record_id, label_source, tuple(LABEL_SOURCES), f"teacher.{key}.labelSource")
        if privacy_tier == "structured_only" and label_source == "vlm_structured_copy":
            issues.append(
                ValidationIssue(
                    record_id,
                    f"teacher.{key}.labelSource",
                    "structured_only must not introduce vlm_structured_copy labels",
                )
            )


def validate_semantic_tip_records(rows: Sequence[Dict[str, Any]]) -> List[ValidationIssue]:
    issues: List[ValidationIssue] = []
    seen_record_ids: set[str] = set()

    for row in rows:
        record_id = row.get("recordId")
        if not _is_non_empty_str(record_id):
            issues.append(ValidationIssue("<unknown>", "recordId", "missing or empty"))
            continue
        record_id = str(record_id)

        if record_id in seen_record_ids:
            issues.append(ValidationIssue(record_id, "recordId", "duplicate recordId"))
            continue
        seen_record_ids.add(record_id)

        _ensure_enum(issues, record_id, row.get("sourceBucket"), tuple(SOURCE_BUCKETS), "sourceBucket")
        _ensure_enum(issues, record_id, row.get("split"), tuple(DATASET_SPLITS), "split")
        _ensure_enum(issues, record_id, row.get("modeTarget"), tuple(MODE_TARGETS), "modeTarget")
        _ensure_enum(issues, record_id, row.get("caseKind"), tuple(CASE_KINDS), "caseKind")

        asset = row.get("asset")
        if not isinstance(asset, dict):
            issues.append(ValidationIssue(record_id, "asset", "missing or not object"))
            asset = {}
        _ensure_required_keys(
            issues,
            record_id,
            asset,
            ("assetRef", "assetKind", "crossDatasetLinkKey", "sceneBrief", "visualAvailability"),
            "asset",
        )
        _ensure_enum(
            issues,
            record_id,
            asset.get("visualAvailability"),
            tuple(VISUAL_AVAILABILITY),
            "asset.visualAvailability",
        )

        provenance = row.get("provenance")
        if not isinstance(provenance, dict):
            issues.append(ValidationIssue(record_id, "provenance", "missing or not object"))
            provenance = {}
        _ensure_required_keys(
            issues,
            record_id,
            provenance,
            ("sourceOrigin", "consentStatus", "exportStatus", "licenseClass", "createdBy"),
            "provenance",
        )
        _ensure_enum(
            issues,
            record_id,
            provenance.get("exportStatus"),
            tuple(EXPORT_STATUSES),
            "provenance.exportStatus",
        )

        privacy = row.get("privacy")
        if not isinstance(privacy, dict):
            issues.append(ValidationIssue(record_id, "privacy", "missing or not object"))
            privacy = {}
        _ensure_required_keys(
            issues,
            record_id,
            privacy,
            ("privacyTier", "redactionApplied", "redactionNotes"),
            "privacy",
        )
        privacy_tier = privacy.get("privacyTier")
        _ensure_enum(issues, record_id, privacy_tier, tuple(PRIVACY_TIERS), "privacy.privacyTier")

        if privacy_tier == "structured_only" and asset.get("redactedVisualRef") is not None:
            issues.append(
                ValidationIssue(record_id, "asset.redactedVisualRef", "must be null for structured_only")
            )
        if privacy_tier == "redacted_visual" and privacy.get("redactionApplied") is not True:
            issues.append(
                ValidationIssue(record_id, "privacy.redactionApplied", "must be true for redacted_visual")
            )

        teacher = row.get("teacher")
        if not isinstance(teacher, dict):
            issues.append(ValidationIssue(record_id, "teacher", "missing or not object"))
            teacher = {}
        _ensure_required_keys(
            issues,
            record_id,
            teacher,
            ("responseStatus", "privacyTier", "suggestedActionIds"),
            "teacher",
        )
        teacher_privacy_tier = teacher.get("privacyTier")
        _ensure_enum(
            issues,
            record_id,
            teacher_privacy_tier,
            tuple(PRIVACY_TIERS),
            "teacher.privacyTier",
        )
        if teacher_privacy_tier != privacy_tier:
            issues.append(
                ValidationIssue(
                    record_id,
                    "teacher.privacyTier",
                    "must match privacy.privacyTier",
                )
            )

        suggested_action_ids = teacher.get("suggestedActionIds", [])
        if not isinstance(suggested_action_ids, list):
            issues.append(ValidationIssue(record_id, "teacher.suggestedActionIds", "must be list"))
        else:
            for idx, action_id in enumerate(suggested_action_ids):
                _ensure_enum(
                    issues,
                    record_id,
                    action_id,
                    tuple(SEMANTIC_ACTION_TYPES),
                    f"teacher.suggestedActionIds[{idx}]",
                )

        teacher_proposal = teacher.get("teacherProposal")
        if isinstance(teacher_proposal, dict):
            if "actionType" in teacher_proposal:
                _ensure_enum(
                    issues,
                    record_id,
                    teacher_proposal.get("actionType"),
                    tuple(SEMANTIC_ACTION_TYPES),
                    "teacher.teacherProposal.actionType",
                )
            if "actionFrame" in teacher_proposal:
                _ensure_enum(
                    issues,
                    record_id,
                    teacher_proposal.get("actionFrame"),
                    tuple(ACTION_FRAMES),
                    "teacher.teacherProposal.actionFrame",
                )
            if "direction" in teacher_proposal and teacher_proposal.get("direction") is not None:
                _ensure_enum(
                    issues,
                    record_id,
                    teacher_proposal.get("direction"),
                    tuple(DIRECTIONS),
                    "teacher.teacherProposal.direction",
                )
        _validate_teacher_grounding(record_id, teacher, str(privacy_tier), issues)

        review = row.get("review")
        if not isinstance(review, dict):
            issues.append(ValidationIssue(record_id, "review", "missing or not object"))
            continue

        decision = review.get("decision")
        _ensure_enum(issues, record_id, decision, tuple(REVIEW_DECISIONS), "review.decision")
        final_tip = review.get("finalTip")
        if decision in REVIEWED_DECISIONS and final_tip is None and decision not in {
            "rejected_teacher_tip",
            "no_tip_should_fire",
        }:
            issues.append(
                ValidationIssue(record_id, "review.finalTip", "required for current review decision")
            )
        if isinstance(final_tip, dict):
            _validate_final_tip(record_id, final_tip, issues)
        elif final_tip is not None:
            issues.append(ValidationIssue(record_id, "review.finalTip", "must be object or null"))

    return issues


def summarize_semantic_tip_records(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    by_bucket: Dict[str, int] = {}
    by_privacy_tier: Dict[str, int] = {}
    by_decision: Dict[str, int] = {}
    by_action_frame: Dict[str, int] = {}

    for row in rows:
        source_bucket = str(row.get("sourceBucket", "unknown"))
        privacy_tier = str((row.get("privacy") or {}).get("privacyTier", "unknown"))
        decision = str((row.get("review") or {}).get("decision", "unknown"))
        action_frame = str(((row.get("review") or {}).get("finalTip") or {}).get("actionFrame", "none"))

        by_bucket[source_bucket] = by_bucket.get(source_bucket, 0) + 1
        by_privacy_tier[privacy_tier] = by_privacy_tier.get(privacy_tier, 0) + 1
        by_decision[decision] = by_decision.get(decision, 0) + 1
        by_action_frame[action_frame] = by_action_frame.get(action_frame, 0) + 1

    return {
        "recordCount": len(rows),
        "bySourceBucket": dict(sorted(by_bucket.items())),
        "byPrivacyTier": dict(sorted(by_privacy_tier.items())),
        "byReviewDecision": dict(sorted(by_decision.items())),
        "byActionFrame": dict(sorted(by_action_frame.items())),
    }


def export_hard_case_bundle(
    rows: Sequence[Dict[str, Any]],
    include_source_buckets: Sequence[str],
    allow_export_statuses: Sequence[str],
    bundle_id: str,
    schema_version: str = SEMANTIC_TIP_DATASET_SCHEMA_VERSION,
) -> Dict[str, Any]:
    source_bucket_set = set(include_source_buckets)
    export_status_set = set(allow_export_statuses)

    filtered: List[Dict[str, Any]] = []
    for row in rows:
        source_bucket = row.get("sourceBucket")
        export_status = ((row.get("provenance") or {}).get("exportStatus"))
        decision = ((row.get("review") or {}).get("decision"))
        if source_bucket not in source_bucket_set:
            continue
        if export_status not in export_status_set:
            continue
        if decision not in REVIEWED_DECISIONS:
            continue
        filtered.append(row)

    return {
        "exportBundleId": bundle_id,
        "schemaVersion": schema_version,
        "createdAt": datetime.now(tz=timezone.utc).replace(microsecond=0).isoformat(),
        "exportPolicy": "repo_safe_only",
        "records": filtered,
        "includedVisualArtifacts": sorted(
            {
                str((row.get("asset") or {}).get("redactedVisualRef"))
                for row in filtered
                if _is_non_empty_str((row.get("asset") or {}).get("redactedVisualRef"))
            }
        ),
        "counts": {
            "recordCount": len(filtered),
            "sourceBuckets": dict(
                sorted(
                    {
                        bucket: sum(1 for row in filtered if row.get("sourceBucket") == bucket)
                        for bucket in source_bucket_set
                    }.items()
                )
            ),
        },
    }


def import_hard_case_bundle(
    base_rows: Sequence[Dict[str, Any]],
    bundle_payload: Dict[str, Any],
    conflict_mode: str = "error",
) -> Tuple[List[Dict[str, Any]], Dict[str, int]]:
    if conflict_mode not in {"error", "skip"}:
        raise ValueError("conflict_mode must be one of: error, skip")

    bundle_schema_version = bundle_payload.get("schemaVersion")
    if bundle_schema_version != SEMANTIC_TIP_DATASET_SCHEMA_VERSION:
        raise ValueError(
            f"unsupported schemaVersion: {bundle_schema_version!r}; "
            f"expected {SEMANTIC_TIP_DATASET_SCHEMA_VERSION!r}"
        )

    incoming_rows = bundle_payload.get("records")
    if not isinstance(incoming_rows, list):
        raise ValueError("bundle payload must contain list field 'records'")

    merged: Dict[str, Dict[str, Any]] = {}
    for row in base_rows:
        record_id = row.get("recordId")
        if not _is_non_empty_str(record_id):
            raise ValueError(f"base row has invalid recordId: {row!r}")
        merged[str(record_id)] = row

    added = 0
    skipped = 0
    conflicted = 0

    for row in incoming_rows:
        if not isinstance(row, dict):
            raise ValueError(f"incoming record must be object: {row!r}")
        record_id = row.get("recordId")
        if not _is_non_empty_str(record_id):
            raise ValueError(f"incoming row has invalid recordId: {row!r}")
        record_id = str(record_id)

        if record_id not in merged:
            merged[record_id] = row
            added += 1
            continue

        existing = merged[record_id]
        if existing == row:
            skipped += 1
            continue

        existing_link = ((existing.get("asset") or {}).get("crossDatasetLinkKey"))
        incoming_link = ((row.get("asset") or {}).get("crossDatasetLinkKey"))
        existing_origin = ((existing.get("provenance") or {}).get("sourceOrigin"))
        incoming_origin = ((row.get("provenance") or {}).get("sourceOrigin"))
        if existing_link != incoming_link or existing_origin != incoming_origin:
            conflicted += 1
            if conflict_mode == "skip":
                skipped += 1
                continue
            raise ValueError(
                "conflicting recordId with mismatched provenance/crossDatasetLinkKey: "
                f"{record_id}"
            )

        if conflict_mode == "skip":
            skipped += 1
            continue
        raise ValueError(f"conflicting recordId with different payload: {record_id}")

    out_rows = [merged[key] for key in sorted(merged.keys())]
    return out_rows, {"added": added, "skipped": skipped, "conflicted": conflicted}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PR-S06 semantic tip dataset tools")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="Validate semantic tip dataset JSONL")
    validate_parser.add_argument("--input", required=True, help="Path to semantic tip dataset JSONL")

    export_parser = subparsers.add_parser("export-hard-cases", help="Export filtered hard-case bundle JSON")
    export_parser.add_argument("--input", required=True, help="Path to semantic tip dataset JSONL")
    export_parser.add_argument("--output", required=True, help="Path to output hard-case bundle JSON")
    export_parser.add_argument(
        "--bundle-id",
        default="semantic_tip_hard_cases_export",
        help="Bundle identifier",
    )
    export_parser.add_argument(
        "--source-bucket",
        action="append",
        default=None,
        help="Source bucket to include (repeatable)",
    )
    export_parser.add_argument(
        "--allow-export-status",
        action="append",
        default=None,
        help="Allowed provenance.exportStatus (repeatable)",
    )

    import_parser = subparsers.add_parser("import-hard-cases", help="Import hard-case bundle into JSONL")
    import_parser.add_argument("--base", required=True, help="Base semantic tip dataset JSONL")
    import_parser.add_argument("--bundle", required=True, help="Hard-case bundle JSON")
    import_parser.add_argument("--output", required=True, help="Output merged JSONL")
    import_parser.add_argument(
        "--conflict-mode",
        choices=["error", "skip"],
        default="error",
        help="How to handle conflicting recordId payloads",
    )
    return parser.parse_args()


def _print_summary(summary: Dict[str, Any]) -> None:
    print(f"records: {summary['recordCount']}")
    print(f"by_source_bucket: {summary['bySourceBucket']}")
    print(f"by_privacy_tier: {summary['byPrivacyTier']}")
    print(f"by_review_decision: {summary['byReviewDecision']}")
    print(f"by_action_frame: {summary['byActionFrame']}")


def main() -> None:
    args = _parse_args()

    if args.command == "validate":
        rows = read_jsonl(Path(args.input).resolve())
        issues = validate_semantic_tip_records(rows)
        _print_summary(summarize_semantic_tip_records(rows))
        if issues:
            print(f"validation_issues: {len(issues)}")
            for issue in issues:
                print(f"- {issue.render()}")
            raise SystemExit(1)
        print("validation_ok")
        return

    if args.command == "export-hard-cases":
        rows = read_jsonl(Path(args.input).resolve())
        source_buckets = (
            args.source_bucket if args.source_bucket is not None else ["runtime_hard_case"]
        )
        allowed_export_statuses = (
            args.allow_export_status
            if args.allow_export_status is not None
            else ["repo_safe_structured_only", "repo_safe_redacted_visual"]
        )
        bundle = export_hard_case_bundle(
            rows=rows,
            include_source_buckets=source_buckets,
            allow_export_statuses=allowed_export_statuses,
            bundle_id=str(args.bundle_id),
        )
        write_json(Path(args.output).resolve(), bundle)
        print(f"exported_records: {len(bundle['records'])}")
        print(f"output: {Path(args.output).resolve().as_posix()}")
        return

    if args.command == "import-hard-cases":
        base_rows = read_jsonl(Path(args.base).resolve())
        bundle = read_json(Path(args.bundle).resolve())
        merged_rows, stats = import_hard_case_bundle(
            base_rows=base_rows,
            bundle_payload=bundle,
            conflict_mode=str(args.conflict_mode),
        )
        write_jsonl(Path(args.output).resolve(), merged_rows)
        print(
            "import_stats: "
            f"added={stats['added']} skipped={stats['skipped']} conflicted={stats['conflicted']}"
        )
        print(f"output: {Path(args.output).resolve().as_posix()}")
        return

    raise SystemExit(f"unsupported command: {args.command}")


if __name__ == "__main__":
    main()
