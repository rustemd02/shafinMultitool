from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Protocol

from cir_contract.contracts.cir_types import CIRRecord, DifficultyBucket


StyleBucket = Literal["clean", "colloquial", "user_short"]
ParaphraserBackendName = Literal["openai", "heuristic"]


@dataclass(frozen=True)
class SourceGenerationRequest:
    input_jsonl: Path
    output_jsonl: Path
    reject_log_jsonl: Path | None
    seed: int
    model_name: str = "gpt-5.4-nano"
    prompt_template_version: str = "sgv7_source_prompt_v1"
    policy_version: str = "sgv7_source_policy_v1"
    max_variants_per_graph: int | None = None
    difficulty_bucket: DifficultyBucket | None = None
    max_graphs: int | None = None
    batch_size: int = 16
    paraphraser_backend: ParaphraserBackendName = "openai"
    paraphraser_workers: int = 1
    enable_clean_fallback: bool = True


@dataclass(frozen=True)
class VariantPlanItem:
    record: CIRRecord
    sample_id: str
    graph_id: str
    pattern_name: str
    difficulty_bucket: DifficultyBucket
    graph_seed: int
    style_bucket: StyleBucket
    variant_ordinal: int
    prompt_payload: dict[str, object]
    required_aliases: tuple[str, ...]
    required_ordinal_tokens: tuple[str, ...]
    required_disambiguation_cues: tuple[str, ...]
    canonical_source_template: str
    prompt_template_version: str
    source_policy_version: str
    model_name: str
    seed: int


@dataclass(frozen=True)
class SourceGenerationResult:
    accepted_records: list[dict[str, object]]
    reject_records: list[dict[str, object]]


class Paraphraser(Protocol):
    def generate(self, *, plan_item: VariantPlanItem, system_prompt: str, user_prompt: str) -> str:
        ...
