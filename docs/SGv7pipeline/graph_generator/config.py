from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from cir_contract.contracts.cir_types import CIRRecord, SourceVariantKey


DifficultyBucket = Literal["core", "hard"]
ComplexityClass = Literal["S", "M", "L"]


@dataclass(frozen=True)
class OutputTargets:
    jsonl: Path
    manifest: Path | None = None


@dataclass(frozen=True)
class GraphBuildRequest:
    seed: int
    difficulty_bucket: DifficultyBucket | None
    total_records: int | None
    pattern_names: list[str] | None
    include_variants: list[SourceVariantKey] | None
    output_jsonl: Path
    output_manifest: Path | None
    refill_budget: int = 3
    fail_on_duplicates: bool = False


@dataclass(frozen=True)
class PatternQuota:
    pattern_name: str
    count: int


@dataclass(frozen=True)
class BucketPolicy:
    difficulty_bucket: DifficultyBucket
    allowed_complexity: tuple[ComplexityClass, ...]
    max_beats: int
    max_actions: int


@dataclass(frozen=True)
class PlanItem:
    ordinal: int
    pattern_name: str
    difficulty_bucket: DifficultyBucket
    source_variant_key: SourceVariantKey
    graph_seed: int
    attempt_index: int = 0


@dataclass(frozen=True)
class BuildResult:
    records: list[CIRRecord]
    manifest: dict[str, object]

