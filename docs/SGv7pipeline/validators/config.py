from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Protocol

from cir_contract.contracts.cir_types import DifficultyBucket


CriticBackendName = Literal["heuristic", "openai"]
ValidationStatus = Literal["accepted", "manual_review", "rejected"]
TrainEligibility = Literal["direct_sft", "hard_or_preference_only", "review_only", "reject_only"]
CriticVerdict = Literal["pass", "soft_fail", "hard_fail"]


@dataclass(frozen=True)
class ValidationRequest:
    input_jsonl: Path
    cir_jsonl: Path | None
    accepted_jsonl: Path
    review_jsonl: Path
    rejected_jsonl: Path
    manifest_json: Path
    seed: int
    critic_model: str = "gpt-5.4-nano"
    critic_temperature: float = 0.0
    critic_top_p: float = 1.0
    critic_max_output_tokens: int = 300
    validator_stack_version: str = "sgv7_validator_stack_v1"
    enable_critic: bool = True
    difficulty_bucket: DifficultyBucket | None = None
    critic_backend: CriticBackendName = "heuristic"


@dataclass(frozen=True)
class CriticResult:
    verdict: CriticVerdict
    confidence: float
    findings: tuple[str, ...]
    detected_failures: tuple[str, ...]
    chronology_preserved: bool
    object_grounding_preserved: bool
    ordinal_binding_preserved: bool
    unsupported_action_preserved: bool
    invented_content_present: bool
    summary: str
    artifact_id: str
    execution: dict[str, object]


@dataclass(frozen=True)
class ValidationDecision:
    status: ValidationStatus
    train_eligibility: TrainEligibility
    record: dict[str, object]


@dataclass(frozen=True)
class ValidationRunResult:
    accepted_records: list[dict[str, object]]
    review_records: list[dict[str, object]]
    rejected_records: list[dict[str, object]]
    manifest: dict[str, object]


class CriticBackend(Protocol):
    def evaluate(self, *, sample: dict[str, object], cir_record: dict[str, object], prompt_payload: dict[str, object]) -> CriticResult:
        ...
