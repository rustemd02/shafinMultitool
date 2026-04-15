from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class DatasetBuildRequest:
    accepted_jsonl: Path
    cir_jsonl: Path
    output_dir: Path
    seed: int
    manual_review_jsonl: Path | None = None
    review_promoted_jsonl: Path | None = None
    rejected_jsonl: Path | None = None
    runtime_failures_jsonl: Path | None = None
    contract_version: str = "sg_v7_contract_v1"
    sft_train_ratio: float = 0.84
    sft_val_ratio: float = 0.08
    sft_test_ratio: float = 0.08
    preference_train_ratio: float = 0.85
    preference_val_ratio: float = 0.10
    preference_test_ratio: float = 0.05
    max_technical_source_share: float = 0.15


@dataclass(frozen=True)
class SplitPlan:
    sft_family_to_split: dict[str, str]
    preference_family_to_split: dict[str, str]
    preference_test_coverage_status: str


@dataclass(frozen=True)
class PreferenceBuildResult:
    splitable_records: list[dict[str, object]]
    quarantined_records: list[dict[str, object]]
    dropped_records: list[dict[str, object]]


@dataclass(frozen=True)
class DatasetBuildResult:
    sft_records: dict[str, list[dict[str, object]]]
    preference_records: dict[str, list[dict[str, object]]]
    split_manifest: dict[str, object]
    preference_manifest: dict[str, object]
    leakage_report: dict[str, object]


class DatasetBuildError(ValueError):
    """Contract or invariant violation in dataset assembly."""
