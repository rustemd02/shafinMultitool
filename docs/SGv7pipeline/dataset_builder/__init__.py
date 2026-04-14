"""Executable dataset assembly artifacts for SG v7."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from .config import DatasetBuildError, DatasetBuildRequest, DatasetBuildResult, PreferenceBuildResult, SplitPlan
from .dedup import dedup_sft_candidates
from .ingest import build_cir_indices, load_raw_preference_candidates, load_sft_candidates
from .manifest import build_leakage_report, build_preference_manifest, build_split_manifest, enforce_leakage_report
from .preference import build_preference_pairs as _build_preference_pairs
from .splitter import split_preference_records, split_sft_records
from .writer import write_json, write_jsonl


def plan_splits(request: DatasetBuildRequest) -> SplitPlan:
    cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
    sft_candidates, _ = load_sft_candidates(request, cir_index=cir_index)
    sft_deduped, _ = dedup_sft_candidates(sft_candidates)
    _, sft_family_to_split = split_sft_records(
        sft_deduped,
        ratios=(request.sft_train_ratio, request.sft_val_ratio, request.sft_test_ratio),
    )

    heldout_families = {
        family_id
        for family_id, split in sft_family_to_split.items()
        if split in {"val", "test"}
    }
    raw_pref = load_raw_preference_candidates(request)
    preference_build = _build_preference_pairs(
        request,
        raw_candidates=raw_pref,
        cir_index=cir_index,
        heldout_sft_family_ids=heldout_families,
    )
    _, preference_family_to_split, preference_test_coverage_status = split_preference_records(
        preference_build.splitable_records,
        ratios=(request.preference_train_ratio, request.preference_val_ratio, request.preference_test_ratio),
    )
    return SplitPlan(
        sft_family_to_split=sft_family_to_split,
        preference_family_to_split=preference_family_to_split,
        preference_test_coverage_status=preference_test_coverage_status,
    )


def build_preference_pairs(request: DatasetBuildRequest) -> PreferenceBuildResult:
    cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
    sft_candidates, _ = load_sft_candidates(request, cir_index=cir_index)
    sft_deduped, _ = dedup_sft_candidates(sft_candidates)
    sft_split, _ = split_sft_records(
        sft_deduped,
        ratios=(request.sft_train_ratio, request.sft_val_ratio, request.sft_test_ratio),
    )
    heldout_families = {
        row["packaging_metadata"]["split_family_id"]
        for split in ("val", "test")
        for row in sft_split[split]
    }
    raw_pref = load_raw_preference_candidates(request)
    return _build_preference_pairs(
        request,
        raw_candidates=raw_pref,
        cir_index=cir_index,
        heldout_sft_family_ids=set(heldout_families),
    )


def build_dataset(request: DatasetBuildRequest) -> DatasetBuildResult:
    cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
    sft_candidates, dropped_by_ingest = load_sft_candidates(request, cir_index=cir_index)
    sft_deduped, dropped_by_dedup = dedup_sft_candidates(sft_candidates)
    sft_splits, _ = split_sft_records(
        sft_deduped,
        ratios=(request.sft_train_ratio, request.sft_val_ratio, request.sft_test_ratio),
    )

    heldout_sft_families = {
        row["packaging_metadata"]["split_family_id"]
        for split in ("val", "test")
        for row in sft_splits[split]
    }
    raw_preference_candidates = load_raw_preference_candidates(request)
    preference_build = _build_preference_pairs(
        request,
        raw_candidates=raw_preference_candidates,
        cir_index=cir_index,
        heldout_sft_family_ids=set(heldout_sft_families),
    )
    preference_splits, _, preference_test_coverage_status = split_preference_records(
        preference_build.splitable_records,
        ratios=(request.preference_train_ratio, request.preference_val_ratio, request.preference_test_ratio),
    )

    split_manifest = build_split_manifest(
        request,
        sft_records=sft_splits,
        dropped_by_dedup=dropped_by_dedup,
        dropped_by_ingest=dropped_by_ingest,
    )
    preference_manifest = build_preference_manifest(
        request,
        preference_records=preference_splits,
        preference_test_coverage_status=preference_test_coverage_status,
        quarantined_records=preference_build.quarantined_records,
        dropped_records=preference_build.dropped_records,
    )
    leakage_report = build_leakage_report(
        sft_records=sft_splits,
        preference_records=preference_splits,
    )
    enforce_leakage_report(leakage_report)

    output_dir = request.output_dir
    write_jsonl(sft_splits["train"], output_dir / "sft_train.jsonl")
    write_jsonl(sft_splits["val"], output_dir / "sft_val.jsonl")
    write_jsonl(sft_splits["test"], output_dir / "sft_test.jsonl")
    write_jsonl(preference_splits["train"], output_dir / "preference_train.jsonl")
    write_jsonl(preference_splits["val"], output_dir / "preference_val.jsonl")
    write_jsonl(preference_splits["test"], output_dir / "preference_test.jsonl")
    write_json(split_manifest, output_dir / "split_manifest.json")
    write_json(preference_manifest, output_dir / "preference_manifest.json")
    write_json(leakage_report, output_dir / "leakage_report.json")

    return DatasetBuildResult(
        sft_records=sft_splits,
        preference_records=preference_splits,
        split_manifest=split_manifest,
        preference_manifest=preference_manifest,
        leakage_report=leakage_report,
    )


__all__ = [
    "DatasetBuildError",
    "DatasetBuildRequest",
    "DatasetBuildResult",
    "PreferenceBuildResult",
    "SplitPlan",
    "build_dataset",
    "build_preference_pairs",
    "plan_splits",
]

