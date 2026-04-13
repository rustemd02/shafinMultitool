from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from cir_contract.contracts.cir_types import DifficultyBucket


SafetyLevel = Literal["safe", "risky"]


@dataclass(frozen=True)
class AugmentationRequest:
    input_jsonl: Path
    output_jsonl: Path
    reject_log_jsonl: Path | None
    seed: int
    policy_version: str = "sgv7_augmentation_policy_v1"
    difficulty_bucket: DifficultyBucket | None = None
    max_augmented_variants_per_parent: int | None = None
    enable_risky: bool = False


@dataclass(frozen=True)
class TransformPlanItem:
    parent_record: dict[str, object]
    parent_variant_id: str
    sample_id: str
    graph_id: str
    difficulty_bucket: DifficultyBucket
    style_bucket: str
    recipe_id: str
    transform_ids: tuple[str, ...]
    variant_ordinal: int
    risk_flags: tuple[str, ...]
    policy_version: str
    seed: int


@dataclass(frozen=True)
class AugmentationResult:
    accepted_records: list[dict[str, object]]
    reject_records: list[dict[str, object]]
