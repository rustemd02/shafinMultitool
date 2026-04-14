from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


class RuntimeFeedbackError(ValueError):
    """Contract or invariant violation in runtime feedback flow."""


@dataclass(frozen=True)
class NormalizeRuntimeFeedbackRequest:
    runtime_events_jsonl: Path
    runtime_failures_jsonl: Path
    review_queue_jsonl: Path
    cluster_manifest_json: Path
    manifest_json: Path
    seed: int
    contract_version: str = "sg_v7_contract_v1"
    unsupported_action_lemmas_path: Path | None = None


@dataclass(frozen=True)
class NormalizeRuntimeFeedbackResult:
    runtime_failures: list[dict[str, object]]
    review_queue: list[dict[str, object]]
    cluster_manifest: dict[str, object]
    manifest: dict[str, object]


@dataclass(frozen=True)
class ReviewAndPromoteRequest:
    runtime_failures_jsonl: Path
    review_decisions_jsonl: Path
    output_runtime_failures_jsonl: Path
    output_promoted_jsonl: Path
    output_manifest_json: Path


@dataclass(frozen=True)
class ReviewAndPromoteResult:
    runtime_failures: list[dict[str, object]]
    promoted: list[dict[str, object]]
    manifest: dict[str, object]


@dataclass(frozen=True)
class ExportEvalCasesRequest:
    runtime_failures_jsonl: Path
    cir_jsonl: Path
    output_eval_cases_jsonl: Path
    output_quarantine_jsonl: Path
    output_manifest_json: Path
    contract_version: str = "sg_v7_contract_v1"


@dataclass(frozen=True)
class ExportEvalCasesResult:
    eval_cases: list[dict[str, object]]
    quarantined: list[dict[str, object]]
    manifest: dict[str, object]

