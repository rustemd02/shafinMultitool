from __future__ import annotations

from pathlib import Path

from eval_io import read_jsonl
from semantic_tip_dataset_tools import (
    export_hard_case_bundle,
    import_hard_case_bundle,
    summarize_semantic_tip_records,
    validate_semantic_tip_records,
)


def _make_runtime_hard_case(record_id: str, export_status: str, decision: str = "accepted_teacher_tip") -> dict:
    return {
        "recordId": record_id,
        "frameId": f"frame-{record_id}",
        "sourceBucket": "runtime_hard_case",
        "split": "holdout",
        "modeTarget": "pause",
        "caseKind": "structured_only_case",
        "asset": {
            "assetRef": f"demo://{record_id}",
            "assetKind": "synthetic_brief_only",
            "crossDatasetLinkKey": f"link-{record_id}",
            "sceneBrief": "hard case",
            "visualAvailability": "none_structured_only",
        },
        "provenance": {
            "sourceOrigin": "runtime_feedback_export",
            "consentStatus": "granted_redacted_export",
            "exportStatus": export_status,
            "licenseClass": "internal_demo",
            "createdBy": "test",
        },
        "privacy": {
            "privacyTier": "structured_only",
            "containsRealPerson": False,
            "containsReadableText": False,
            "containsBiometricSensitiveFace": False,
            "redactionApplied": False,
            "redactionNotes": [],
            "reviewerMayRequestVisual": False,
        },
        "deterministicBaseline": {
            "sceneType": "single_character_medium",
            "primarySubjectKind": "person",
            "primarySubjectRef": "subject_primary",
            "issueTypes": ["background_clutter"],
            "strengthTypes": [],
            "recommendedActionTypes": ["reduce_background_distractions"],
            "baselineTipType": "simplify_busy_background",
            "baselineActionType": "simplify_background",
            "eligibleHeadIds": ["background_clutter"],
            "deterministicConfidence": 0.7,
        },
        "teacher": {
            "responseStatus": "completed",
            "privacyTier": "structured_only",
            "evidenceDimensions": ["clutter"],
            "suggestedActionIds": ["simplify_background"],
            "teacherProposal": {
                "tipType": "simplify_busy_background",
                "actionType": "simplify_background",
                "actionFrame": "move_object",
                "direction": "none",
                "visualProblemType": "background_clutter",
            },
        },
        "review": {
            "decision": decision,
            "finalTip": {
                "tipType": "simplify_busy_background",
                "actionType": "simplify_background",
                "actionFrame": "move_object",
                "direction": "none",
                "problemType": "background_clutter",
                "targetEntityKind": "background_area",
                "targetEntityRole": "background_zone",
                "targetEntityDisplayLabel": "фон",
                "labelConfidence": 0.9,
                "linkedIssueTypes": ["background_clutter"],
                "linkedStrengthTypes": [],
                "linkedSemanticActionTypes": ["simplify_background"],
            },
        },
    }


def test_validate_demo_cases_fixture_is_clean() -> None:
    fixture_path = Path(__file__).resolve().parents[1] / "semantic_tip_dataset_demo_cases.jsonl"
    rows = read_jsonl(fixture_path)
    issues = validate_semantic_tip_records(rows)
    assert issues == []


def test_validate_rejects_structured_only_vlm_structured_copy() -> None:
    record = _make_runtime_hard_case("runtime-1", export_status="repo_safe_structured_only")
    record["teacher"]["groundedTarget"] = {
        "entityKind": "object",
        "entityRole": "foreground_object",
        "entityRef": "obj-1",
        "displayLabelCandidate": "ваза",
        "labelConfidence": 0.81,
        "labelSource": "vlm_structured_copy",
    }
    issues = validate_semantic_tip_records([record])
    assert any("structured_only must not introduce vlm_structured_copy labels" in issue.message for issue in issues)


def test_validate_rejects_teacher_privacy_tier_mismatch() -> None:
    record = _make_runtime_hard_case("runtime-mismatch", export_status="repo_safe_structured_only")
    record["teacher"]["privacyTier"] = "redacted_visual"
    issues = validate_semantic_tip_records([record])
    assert any("must match privacy.privacyTier" in issue.message for issue in issues)


def test_export_hard_case_bundle_filters_by_export_status() -> None:
    rows = [
        _make_runtime_hard_case("runtime-safe", export_status="repo_safe_structured_only"),
        _make_runtime_hard_case("runtime-internal", export_status="internal_only"),
        {**_make_runtime_hard_case("curated-safe", export_status="repo_safe_structured_only"), "sourceBucket": "curated_real"},
    ]
    bundle = export_hard_case_bundle(
        rows=rows,
        include_source_buckets=["runtime_hard_case"],
        allow_export_statuses=["repo_safe_structured_only", "repo_safe_redacted_visual"],
        bundle_id="test-bundle",
    )
    exported_ids = [row["recordId"] for row in bundle["records"]]
    assert exported_ids == ["runtime-safe"]


def test_export_hard_case_bundle_filters_by_source_bucket() -> None:
    rows = [
        _make_runtime_hard_case("runtime-safe", export_status="repo_safe_structured_only"),
        {**_make_runtime_hard_case("curated-safe", export_status="repo_safe_structured_only"), "sourceBucket": "curated_real"},
    ]
    bundle = export_hard_case_bundle(
        rows=rows,
        include_source_buckets=["curated_real"],
        allow_export_statuses=["repo_safe_structured_only"],
        bundle_id="test-bucket-filter",
    )
    exported_ids = [row["recordId"] for row in bundle["records"]]
    assert exported_ids == ["curated-safe"]


def test_import_hard_case_bundle_conflict_mode_skip() -> None:
    base = [_make_runtime_hard_case("shared", export_status="repo_safe_structured_only")]
    incoming_changed = _make_runtime_hard_case("shared", export_status="repo_safe_structured_only")
    incoming_changed["review"]["finalTip"]["targetEntityDisplayLabel"] = "другой фон"
    incoming_new = _make_runtime_hard_case("new", export_status="repo_safe_structured_only")

    bundle = {
        "exportBundleId": "bundle",
        "schemaVersion": "s6.v1",
        "createdAt": "2026-05-05T00:00:00+00:00",
        "exportPolicy": "repo_safe_only",
        "records": [incoming_changed, incoming_new],
        "includedVisualArtifacts": [],
    }
    merged, stats = import_hard_case_bundle(base, bundle, conflict_mode="skip")
    assert sorted(row["recordId"] for row in merged) == ["new", "shared"]
    assert stats["added"] == 1
    assert stats["skipped"] == 1


def test_import_hard_case_bundle_rejects_wrong_schema_version() -> None:
    base = [_make_runtime_hard_case("base", export_status="repo_safe_structured_only")]
    bundle = {
        "exportBundleId": "bundle",
        "schemaVersion": "s6.v0",
        "createdAt": "2026-05-05T00:00:00+00:00",
        "exportPolicy": "repo_safe_only",
        "records": [_make_runtime_hard_case("incoming", export_status="repo_safe_structured_only")],
        "includedVisualArtifacts": [],
    }
    try:
        import_hard_case_bundle(base, bundle, conflict_mode="error")
        assert False, "expected ValueError for unsupported schemaVersion"
    except ValueError as exc:
        assert "unsupported schemaVersion" in str(exc)


def test_summary_counts_action_frames() -> None:
    rows = [
        _make_runtime_hard_case("a", export_status="repo_safe_structured_only"),
        _make_runtime_hard_case("b", export_status="repo_safe_structured_only"),
    ]
    rows[1]["review"]["finalTip"]["actionFrame"] = "wait"
    rows[1]["review"]["finalTip"]["actionType"] = "wait_for_background_clearance"
    rows[1]["review"]["finalTip"]["linkedSemanticActionTypes"] = ["wait_for_background_clearance"]
    summary = summarize_semantic_tip_records(rows)
    assert summary["recordCount"] == 2
    assert summary["byActionFrame"]["move_object"] == 1
    assert summary["byActionFrame"]["wait"] == 1
