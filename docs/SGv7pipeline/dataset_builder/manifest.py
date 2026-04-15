from __future__ import annotations

from collections import Counter
import hashlib
from itertools import combinations
from typing import Any

from .config import DatasetBuildError, DatasetBuildRequest
from .ingest import CRITICAL_EVAL_TAGS, normalize_source_key_v1


def _meta(row: dict[str, Any]) -> dict[str, Any]:
    return row["packaging_metadata"]


def _count_by(records: list[dict[str, Any]], key: str) -> dict[str, int]:
    counter = Counter(str(_meta(row).get(key, "")) for row in records)
    return dict(sorted(counter.items()))


def _across_split_overlap(records_by_split: dict[str, list[dict[str, Any]]], key_fn) -> list[dict[str, Any]]:
    overlaps: list[dict[str, Any]] = []
    for left, right in combinations(sorted(records_by_split.keys()), 2):
        left_keys = {item for item in (key_fn(row) for row in records_by_split[left]) if item}
        right_keys = {item for item in (key_fn(row) for row in records_by_split[right]) if item}
        shared = sorted(left_keys & right_keys)
        if shared:
            overlaps.append(
                {
                    "left_split": left,
                    "right_split": right,
                    "shared_count": len(shared),
                    "shared_examples": shared[:5],
                }
            )
    return overlaps


def _assert_no_overlap(
    records_by_split: dict[str, list[dict[str, Any]]],
    *,
    check_name: str,
    key_fn,
    violations: list[dict[str, Any]],
) -> None:
    entries = _across_split_overlap(records_by_split, key_fn)
    if entries:
        violations.append({"check": check_name, "violations": entries})


def _assert_cross_task_no_overlap(
    *,
    left_records: list[dict[str, Any]],
    right_records: list[dict[str, Any]],
    check_name: str,
    left_key_fn,
    right_key_fn,
    violations: list[dict[str, Any]],
) -> None:
    left_keys = {item for item in (left_key_fn(row) for row in left_records) if item}
    right_keys = {item for item in (right_key_fn(row) for row in right_records) if item}
    shared = sorted(left_keys & right_keys)
    if shared:
        violations.append(
            {
                "check": check_name,
                "shared_count": len(shared),
                "shared_examples": shared[:5],
            }
        )


def build_split_manifest(
    request: DatasetBuildRequest,
    *,
    sft_records: dict[str, list[dict[str, Any]]],
    dropped_by_dedup: dict[str, int],
    dropped_by_ingest: dict[str, int],
) -> dict[str, Any]:
    all_rows = [row for split in ("train", "val", "test") for row in sft_records.get(split, [])]
    by_split = {split: len(sft_records.get(split, [])) for split in ("train", "val", "test")}
    by_bucket = _count_by(all_rows, "difficulty_bucket")
    by_tier = _count_by(all_rows, "correction_tier")
    by_semantic_family = _count_by(all_rows, "semantic_family_key")

    critical_counts = Counter()
    for row in all_rows:
        for tag in row.get("critical_eval_tags", []):
            critical_counts[str(tag)] += 1
    for tag in CRITICAL_EVAL_TAGS:
        critical_counts.setdefault(tag, 0)

    contracts = sorted({str(_meta(row).get("contract_version", "")) for row in all_rows})
    return {
        "build_config": {
            "seed": request.seed,
            "sft_ratios": {
                "train": request.sft_train_ratio,
                "val": request.sft_val_ratio,
                "test": request.sft_test_ratio,
            },
            "max_technical_source_share": request.max_technical_source_share,
            "contract_version": request.contract_version,
        },
        "input_artifacts": {
            "accepted_jsonl": str(request.accepted_jsonl),
            "manual_review_jsonl": str(request.manual_review_jsonl) if request.manual_review_jsonl else None,
            "review_promoted_jsonl": str(request.review_promoted_jsonl) if request.review_promoted_jsonl else None,
            "cir_jsonl": str(request.cir_jsonl),
        },
        "counts_by_split": by_split,
        "counts_by_difficulty_bucket": by_bucket,
        "counts_by_correction_tier": by_tier,
        "counts_by_semantic_family_key": by_semantic_family,
        "counts_by_critical_eval_tags": dict(sorted(critical_counts.items())),
        "dropped_by_ingest_reason": dict(sorted(dropped_by_ingest.items())),
        "dropped_by_dedup_reason": dict(sorted(dropped_by_dedup.items())),
        "contract_versions_present": contracts,
    }


def build_preference_manifest(
    request: DatasetBuildRequest,
    *,
    preference_records: dict[str, list[dict[str, Any]]],
    preference_test_coverage_status: str,
    quarantined_records: list[dict[str, Any]],
    dropped_records: list[dict[str, Any]],
) -> dict[str, Any]:
    all_rows = [row for split in ("train", "val", "test") for row in preference_records.get(split, [])]
    by_split = {split: len(preference_records.get(split, [])) for split in ("train", "val", "test")}
    by_origin = _count_by(all_rows, "preference_origin")
    by_bucket = _count_by(all_rows, "difficulty_bucket")
    by_tier = _count_by(all_rows, "correction_tier")
    by_family = _count_by(all_rows, "graph_family_key")

    quarantine_reasons = Counter(str(item.get("reason", "")) for item in quarantined_records)
    dropped_reasons = Counter(str(item.get("reason", "")) for item in dropped_records)
    proof_status = Counter(str(_meta(row).get("family_resolution_proof", {}).get("proof_status", "")) for row in all_rows)

    return {
        "build_config": {
            "seed": request.seed,
            "preference_ratios": {
                "train": request.preference_train_ratio,
                "val": request.preference_val_ratio,
                "test": request.preference_test_ratio,
            },
            "contract_version": request.contract_version,
        },
        "counts_by_split": by_split,
        "counts_by_preference_origin": by_origin,
        "counts_by_difficulty_bucket": by_bucket,
        "counts_by_correction_tier": by_tier,
        "counts_by_graph_family_key": by_family,
        "preference_test_coverage_status": preference_test_coverage_status,
        "quarantined_candidate_counts": {
            "total": len(quarantined_records),
            "by_reason": dict(sorted(quarantine_reasons.items())),
        },
        "dropped_candidate_counts": {
            "total": len(dropped_records),
            "by_reason": dict(sorted(dropped_reasons.items())),
        },
        "family_resolution_proof_summary": dict(sorted(proof_status.items())),
    }


def build_leakage_report(
    *,
    sft_records: dict[str, list[dict[str, Any]]],
    preference_records: dict[str, list[dict[str, Any]]],
) -> dict[str, Any]:
    violations: list[dict[str, Any]] = []
    sft = {split: sft_records.get(split, []) for split in ("train", "val", "test")}
    pref = {split: preference_records.get(split, []) for split in ("train", "val", "test")}

    _assert_no_overlap(
        sft,
        check_name="no_shared_sample_id_across_sft_splits",
        key_fn=lambda row: str(_meta(row).get("sample_id", "")),
        violations=violations,
    )
    _assert_no_overlap(
        sft,
        check_name="no_shared_split_family_id_across_sft_splits",
        key_fn=lambda row: str(_meta(row).get("split_family_id", "")),
        violations=violations,
    )
    _assert_no_overlap(
        sft,
        check_name="no_shared_graph_hash_and_normalized_source_hash_across_sft_splits",
        key_fn=lambda row: f"{_meta(row).get('graph_hash','')}|{_meta(row).get('normalized_source_hash','')}",
        violations=violations,
    )
    _assert_no_overlap(
        sft,
        check_name="no_shared_normalized_source_hash_across_sft_splits",
        key_fn=lambda row: str(_meta(row).get("normalized_source_hash", "")),
        violations=violations,
    )
    _assert_no_overlap(
        pref,
        check_name="no_shared_split_family_id_across_preference_splits",
        key_fn=lambda row: str(_meta(row).get("split_family_id", "")),
        violations=violations,
    )
    _assert_no_overlap(
        pref,
        check_name="no_shared_normalized_source_hash_across_preference_splits",
        key_fn=lambda row: str(_meta(row).get("normalized_source_hash", "")),
        violations=violations,
    )

    heldout_sft = [*sft["val"], *sft["test"]]
    all_pref = [*pref["train"], *pref["val"], *pref["test"]]
    _assert_cross_task_no_overlap(
        left_records=heldout_sft,
        right_records=all_pref,
        check_name="no_shared_split_family_id_between_sft_heldout_and_any_preference",
        left_key_fn=lambda row: str(_meta(row).get("split_family_id", "")),
        right_key_fn=lambda row: str(_meta(row).get("split_family_id", "")),
        violations=violations,
    )
    _assert_cross_task_no_overlap(
        left_records=heldout_sft,
        right_records=all_pref,
        check_name="no_shared_graph_family_key_between_sft_heldout_and_any_preference",
        left_key_fn=lambda row: str(_meta(row).get("graph_family_key", "")),
        right_key_fn=lambda row: str(_meta(row).get("graph_family_key", "")),
        violations=violations,
    )
    _assert_cross_task_no_overlap(
        left_records=heldout_sft,
        right_records=all_pref,
        check_name="no_shared_normalized_source_hash_between_sft_heldout_and_any_preference",
        left_key_fn=lambda row: str(_meta(row).get("normalized_source_hash", "")),
        right_key_fn=lambda row: str(_meta(row).get("normalized_source_hash", "")),
        violations=violations,
    )
    _assert_cross_task_no_overlap(
        left_records=heldout_sft,
        right_records=all_pref,
        check_name="no_shared_sample_id_between_sft_heldout_and_any_preference_when_present",
        left_key_fn=lambda row: str(_meta(row).get("sample_id", "")),
        right_key_fn=lambda row: str(_meta(row).get("sample_id", "")),
        violations=violations,
    )
    _assert_cross_task_no_overlap(
        left_records=heldout_sft,
        right_records=all_pref,
        check_name="no_shared_graph_hash_between_sft_heldout_and_any_preference_when_present",
        left_key_fn=lambda row: str(_meta(row).get("graph_hash", "")),
        right_key_fn=lambda row: str(_meta(row).get("graph_hash", "")),
        violations=violations,
    )

    all_rows = [*sft["train"], *sft["val"], *sft["test"], *pref["train"], *pref["val"], *pref["test"]]
    missing_nsh = [
        row.get("sample_id") or row.get("preference_id")
        for row in all_rows
        if not _meta(row).get("normalized_source_hash")
    ]
    if missing_nsh:
        violations.append(
            {
                "check": "all_emitted_records_persist_normalized_source_hash",
                "missing_count": len(missing_nsh),
                "missing_examples": missing_nsh[:5],
            }
        )

    nsh_mismatch = []
    for row in all_rows:
        metadata = _meta(row)
        source_text = str(row.get("source_text", ""))
        expected = metadata.get("normalized_source_hash")
        recomputed = "nsh_" + hashlib.sha256(normalize_source_key_v1(source_text).encode("utf-8")).hexdigest()[:8]
        if expected != recomputed:
            nsh_mismatch.append(row.get("sample_id") or row.get("preference_id"))
    if nsh_mismatch:
        violations.append(
            {
                "check": "normalized_source_hash_matches_recomputed_value",
                "mismatch_count": len(nsh_mismatch),
                "mismatch_examples": nsh_mismatch[:5],
            }
        )

    invalid_proofs = [
        row["preference_id"]
        for row in all_pref
        if str(_meta(row).get("family_resolution_proof", {}).get("proof_status", "")) != "resolved"
    ]
    if invalid_proofs:
        violations.append(
            {
                "check": "all_emitted_preference_records_have_resolved_family_proof",
                "invalid_count": len(invalid_proofs),
                "invalid_examples": invalid_proofs[:5],
            }
        )

    versions = {str(_meta(row).get("contract_version", "")) for row in all_rows}
    if len(versions) > 1:
        violations.append(
            {
                "check": "no_mixed_contract_version_in_emitted_files",
                "versions": sorted(versions),
            }
        )

    core_eligibility_violations = [
        row["sample_id"]
        for row in all_rows
        if row.get("task_type") == "sft"
        and str(_meta(row).get("difficulty_bucket", "")) == "core"
        and str(_meta(row).get("train_eligibility", "")) == "hard_or_preference_only"
    ]
    if core_eligibility_violations:
        violations.append(
            {
                "check": "no_hard_or_preference_only_records_in_core_only_views",
                "invalid_count": len(core_eligibility_violations),
                "invalid_examples": core_eligibility_violations[:5],
            }
        )

    return {
        "status": "pass" if not violations else "fail",
        "violations": violations,
        "checked_outputs": {
            "sft_train": len(sft["train"]),
            "sft_val": len(sft["val"]),
            "sft_test": len(sft["test"]),
            "preference_train": len(pref["train"]),
            "preference_val": len(pref["val"]),
            "preference_test": len(pref["test"]),
        },
    }


def enforce_leakage_report(report: dict[str, Any]) -> None:
    if report.get("status") != "pass":
        raise DatasetBuildError("leakage audit failed")
