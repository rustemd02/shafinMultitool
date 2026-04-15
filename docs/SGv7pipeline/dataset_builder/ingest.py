from __future__ import annotations

from collections import defaultdict
from copy import deepcopy
import hashlib
import re
from typing import Any

from cir_contract.contracts import structural_hash
from graph_generator.dedup import graph_fingerprint
from pattern_library import PATTERN_REGISTRY
from source_generation.filters import has_technical_identifier_literals, normalize_persisted_source_text

from .config import DatasetBuildError, DatasetBuildRequest
from .renderer import render_sft_messages
from .writer import read_jsonl


_WS_RE = re.compile(r"\s+", flags=re.UNICODE)
_EDGE_PUNCT_RE = re.compile(r"^[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+|[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+$")

CRITICAL_EVAL_TAGS = (
    "ordinal_cases",
    "marked_object_morphology",
    "same_type_markers",
    "unsupported_action_cases",
    "three_beat_cases",
    "exact_marker_identity_cases",
    "reviewed_merge_cases",
)


def normalize_source_key_v1(text: str) -> str:
    value = normalize_persisted_source_text(text).lower()
    value = _EDGE_PUNCT_RE.sub("", value)
    value = _WS_RE.sub(" ", value).strip()
    return value.replace("ё", "е")


def normalized_source_hash_v1(text: str) -> str:
    payload = normalize_source_key_v1(text)
    return "nsh_" + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:8]


def token_count(text: str) -> int:
    normalized = _WS_RE.sub(" ", text.strip())
    if not normalized:
        return 0
    return len(normalized.split(" "))


def build_semantic_family_key(
    *,
    pattern_family: str,
    source_variant_key: str,
    difficulty_bucket: str,
    complexity_class: str,
    semantic_tags: list[str],
) -> str:
    tags = ",".join(sorted(str(item) for item in semantic_tags))
    return "|".join([pattern_family, source_variant_key, difficulty_bucket, complexity_class, tags])


def _critical_eval_tags(*, row: dict[str, Any], cir_record: dict[str, Any]) -> list[str]:
    tags = {str(item) for item in cir_record.get("semantic_tags", [])}
    critical: list[str] = []
    if "ordinal_reference" in tags:
        critical.append("ordinal_cases")
    if str(cir_record.get("source_variant_key", "")) == "morphology_stress":
        critical.append("marked_object_morphology")
    if "same_type_markers" in tags:
        critical.append("same_type_markers")
    if "described_action" in tags:
        critical.append("unsupported_action_cases")
    if int(cir_record.get("budgets", {}).get("beat_count", 0)) >= 3:
        critical.append("three_beat_cases")
    if "marked_object" in tags or "same_type_markers" in tags:
        critical.append("exact_marker_identity_cases")
    if str(row.get("correction_tier", "")) == "tier_c_reviewed_merge":
        critical.append("reviewed_merge_cases")
    return sorted(critical)


def _resolve_pattern_family(cir_record: dict[str, Any]) -> str:
    internal = cir_record.get("internal_metadata", {})
    if isinstance(internal, dict):
        pattern_family = internal.get("pattern_family")
        if isinstance(pattern_family, str) and pattern_family:
            return pattern_family
    pattern_name = str(cir_record.get("pattern_name", ""))
    spec = PATTERN_REGISTRY.get(pattern_name)
    if spec is None:
        raise DatasetBuildError(f"pattern_family_resolution_failed: {pattern_name!r}")
    return spec.pattern_family


def _require_contract_version(row: dict[str, Any], expected: str, *, source_name: str) -> None:
    actual = row.get("contract_version")
    if actual is None:
        return
    if str(actual) != expected:
        raise DatasetBuildError(
            f"mixed_contract_version in {source_name}: expected={expected!r} actual={actual!r}"
        )


def build_cir_indices(cir_jsonl: Any, *, contract_version: str) -> dict[str, Any]:
    rows = read_jsonl(cir_jsonl)
    by_sample_id: dict[str, dict[str, Any]] = {}
    by_graph_hash: dict[str, list[str]] = defaultdict(list)
    by_graph_family: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        _require_contract_version(row, contract_version, source_name="cir_jsonl")
        sample_id = str(row.get("sample_id", "")).strip()
        if not sample_id:
            raise DatasetBuildError("cir_jsonl row missing sample_id")
        if sample_id in by_sample_id:
            raise DatasetBuildError(f"contract_cir_join_non_unique sample_id={sample_id!r}")
        graph_hash = structural_hash(row)
        graph_family_key = str(row.get("graph_family_key") or graph_fingerprint(row))
        row_copy = deepcopy(row)
        row_copy["graph_hash"] = graph_hash
        row_copy["graph_family_key"] = graph_family_key
        by_sample_id[sample_id] = row_copy
        by_graph_hash[graph_hash].append(sample_id)
        by_graph_family[graph_family_key].append(sample_id)
    return {
        "rows": rows,
        "by_sample_id": by_sample_id,
        "by_graph_hash": dict(by_graph_hash),
        "by_graph_family": dict(by_graph_family),
    }


def _load_promoted_review_rows(
    request: DatasetBuildRequest,
    *,
    contract_version: str,
) -> list[dict[str, Any]]:
    if request.review_promoted_jsonl is None:
        return []
    if request.manual_review_jsonl is None:
        raise DatasetBuildError("manual_review_promoted.jsonl requires manual_review.jsonl")

    reviewed_rows = read_jsonl(request.manual_review_jsonl)
    reviewed_by_sample: dict[str, dict[str, Any]] = {}
    for row in reviewed_rows:
        _require_contract_version(row, contract_version, source_name="manual_review_jsonl")
        sample_id = str(row.get("sample_id", "")).strip()
        if not sample_id:
            raise DatasetBuildError("manual_review row missing sample_id")
        if sample_id in reviewed_by_sample:
            raise DatasetBuildError(f"manual_review duplicate sample_id={sample_id!r}")
        reviewed_by_sample[sample_id] = row

    promoted_rows = read_jsonl(request.review_promoted_jsonl)
    promoted: list[dict[str, Any]] = []
    for decision in promoted_rows:
        sample_id = str(decision.get("sample_id", "")).strip()
        if not sample_id:
            raise DatasetBuildError("manual_review_promoted row missing sample_id")
        source_row = reviewed_by_sample.get(sample_id)
        if source_row is None:
            raise DatasetBuildError(f"promotion sidecar missing reviewed source for sample_id={sample_id!r}")

        promoted_train_eligibility = str(decision.get("promoted_train_eligibility", "")).strip()
        if promoted_train_eligibility not in {"direct_sft", "hard_or_preference_only"}:
            raise DatasetBuildError(
                f"invalid promoted_train_eligibility={promoted_train_eligibility!r} for sample_id={sample_id!r}"
            )
        if (
            str(source_row.get("correction_tier", "")) == "tier_d_auto_repair_only"
            and promoted_train_eligibility == "direct_sft"
        ):
            raise DatasetBuildError(
                f"tier_d sample cannot be promoted to direct_sft: sample_id={sample_id!r}"
            )

        merged = deepcopy(source_row)
        merged["validation_status"] = "accepted"
        merged["train_eligibility"] = promoted_train_eligibility
        merged["review_decision"] = decision.get("review_decision")
        merged["reviewed_at"] = decision.get("reviewed_at")
        merged["reviewer"] = decision.get("reviewer")
        merged["promoted_from_manual_review"] = True
        promoted.append(merged)
    return promoted


def _admit_sft_row(row: dict[str, Any]) -> bool:
    if str(row.get("validation_status", "")) != "accepted":
        return False
    if str(row.get("correction_tier", "")) == "tier_d_auto_repair_only":
        return False
    return str(row.get("train_eligibility", "")) in {"direct_sft", "hard_or_preference_only"}


def _allowed_technical_literal_count(*, clean_count: int, technical_count: int, max_share: float) -> int:
    if clean_count < 0:
        return 0
    if max_share <= 0:
        return 0
    if max_share >= 1:
        return max(0, technical_count)
    # Enforce t / (clean + t) <= max_share  =>  t <= (max_share * clean) / (1 - max_share)
    allowed = int((max_share * clean_count) / (1 - max_share))
    return max(0, allowed)


def _technical_keep_priority(candidate: dict[str, Any]) -> tuple[int, int, int, int, str]:
    critical = {str(tag) for tag in candidate.get("critical_eval_tags", [])}
    critical_weight = 0
    if "exact_marker_identity_cases" in critical:
        critical_weight += 3
    if "same_type_markers" in critical:
        critical_weight += 2
    if "ordinal_cases" in critical:
        critical_weight += 1
    metadata = candidate.get("packaging_metadata", {})
    token_count_score = int(metadata.get("source_text_token_count", 0)) if isinstance(metadata, dict) else 0
    return (
        1 if bool(candidate.get("promoted_from_manual_review", False)) else 0,
        critical_weight,
        int(candidate.get("recoverability_score", 0)),
        token_count_score,
        str(candidate.get("sample_id", "")),
    )


def _enforce_technical_source_share(
    candidates: list[dict[str, Any]],
    *,
    max_share: float,
) -> tuple[list[dict[str, Any]], int]:
    if not candidates:
        return [], 0

    technical = [row for row in candidates if bool(row.get("_has_technical_literals", False))]
    if not technical:
        return candidates, 0

    clean_count = len(candidates) - len(technical)
    allowed_technical = _allowed_technical_literal_count(
        clean_count=clean_count,
        technical_count=len(technical),
        max_share=max_share,
    )
    if len(technical) <= allowed_technical:
        return candidates, 0

    keep_technical = set()
    ranked = sorted(technical, key=_technical_keep_priority, reverse=True)
    for row in ranked[:allowed_technical]:
        keep_technical.add(str(row.get("sample_id", "")))

    filtered: list[dict[str, Any]] = []
    dropped = 0
    for row in candidates:
        sample_id = str(row.get("sample_id", ""))
        has_technical = bool(row.get("_has_technical_literals", False))
        if has_technical and sample_id not in keep_technical:
            dropped += 1
            continue
        filtered.append(row)
    return filtered, dropped


def load_sft_candidates(
    request: DatasetBuildRequest,
    *,
    cir_index: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    if request.max_technical_source_share < 0 or request.max_technical_source_share > 1:
        raise DatasetBuildError(
            f"max_technical_source_share must be within [0,1], got {request.max_technical_source_share!r}"
        )

    accepted_rows = read_jsonl(request.accepted_jsonl)
    promoted_rows = _load_promoted_review_rows(request, contract_version=request.contract_version)
    candidates: list[dict[str, Any]] = []
    dropped = {
        "not_admitted_by_policy": 0,
        "missing_cir_join": 0,
    }
    for row in [*accepted_rows, *promoted_rows]:
        _require_contract_version(row, request.contract_version, source_name="accepted_or_promoted")
        if not _admit_sft_row(row):
            dropped["not_admitted_by_policy"] += 1
            continue
        sample_id = str(row.get("sample_id", "")).strip()
        cir_record = cir_index["by_sample_id"].get(sample_id)
        if cir_record is None:
            dropped["missing_cir_join"] += 1
            continue

        source_text = normalize_persisted_source_text(str(row.get("source_text", "")))
        if not source_text:
            dropped["not_admitted_by_policy"] += 1
            continue
        has_technical_literals = has_technical_identifier_literals(source_text)

        messages, target_json, assistant_content = render_sft_messages(source_text=source_text, cir_record=cir_record)
        graph_hash = str(cir_record["graph_hash"])
        graph_family_key = str(cir_record["graph_family_key"])
        pattern_family = _resolve_pattern_family(cir_record)
        semantic_tags = [str(item) for item in cir_record.get("semantic_tags", [])]
        normalized_source_hash = normalized_source_hash_v1(source_text)
        source_text_token_count = token_count(source_text)
        target_json_token_count = token_count(assistant_content)
        full_sequence_token_count = token_count(
            messages[0]["content"] + " " + messages[1]["content"] + " " + messages[2]["content"]
        )
        semantic_family_key = build_semantic_family_key(
            pattern_family=pattern_family,
            source_variant_key=str(cir_record.get("source_variant_key", "base")),
            difficulty_bucket=str(cir_record.get("difficulty_bucket", "")),
            complexity_class=str(cir_record.get("complexity_class", "")),
            semantic_tags=semantic_tags,
        )
        budgets = cir_record.get("budgets", {})
        packaging_metadata = {
            "split": "",
            "task_type": "sft",
            "contract_version": request.contract_version,
            "sample_id": sample_id,
            "graph_id": str(row.get("graph_id") or sample_id),
            "graph_hash": graph_hash,
            "graph_family_key": graph_family_key,
            "normalized_source_hash": normalized_source_hash,
            "pattern_name": str(cir_record.get("pattern_name", "")),
            "pattern_family": pattern_family,
            "source_variant_key": str(cir_record.get("source_variant_key", "")),
            "difficulty_bucket": str(cir_record.get("difficulty_bucket", "")),
            "complexity_class": str(cir_record.get("complexity_class", "")),
            "semantic_tags": semantic_tags,
            "style_bucket": str(row.get("style_bucket", "")),
            "generation_pass": str(row.get("generation_pass", "")),
            "validation_status": str(row.get("validation_status", "")),
            "train_eligibility": str(row.get("train_eligibility", "")),
            "validator_stack_version": str(row.get("validation_report", {}).get("validator_stack_version", "")),
            "split_family_id": graph_family_key,
            "semantic_family_key": semantic_family_key,
            "dedup_group_key": f"{graph_hash}|{normalized_source_hash}",
            "source_text_token_count": source_text_token_count,
            "target_json_token_count": target_json_token_count,
            "full_sequence_token_count": full_sequence_token_count,
            "actor_count": int(budgets.get("actor_count", 0)),
            "object_count": int(budgets.get("object_count", 0)),
            "beat_count": int(budgets.get("beat_count", 0)),
            "action_count": int(budgets.get("action_count", 0)),
            "correction_tier": str(row.get("correction_tier", "")),
        }
        critical_eval_tags = _critical_eval_tags(row=row, cir_record=cir_record)
        candidate = {
            "sample_id": sample_id,
            "task_type": "sft",
            "messages": messages,
            "target_json": target_json,
            "packaging_metadata": packaging_metadata,
            "critical_eval_tags": critical_eval_tags,
            "source_text": source_text,
            "recoverability_score": int(row.get("validation_report", {}).get("recoverability_score", 0)),
            "promoted_from_manual_review": bool(row.get("promoted_from_manual_review", False)),
            "review_decision": row.get("review_decision"),
            "reviewed_at": row.get("reviewed_at"),
            "reviewer": row.get("reviewer"),
            "_has_technical_literals": has_technical_literals,
        }
        candidates.append(candidate)

    filtered_candidates, dropped_technical = _enforce_technical_source_share(
        candidates,
        max_share=request.max_technical_source_share,
    )
    dropped["technical_token_over_budget"] = dropped_technical
    for candidate in filtered_candidates:
        candidate.pop("_has_technical_literals", None)
    return filtered_candidates, dropped


def load_raw_preference_candidates(request: DatasetBuildRequest) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if request.runtime_failures_jsonl is not None:
        for row in read_jsonl(request.runtime_failures_jsonl):
            _require_contract_version(row, request.contract_version, source_name="runtime_failures_jsonl")
            row_copy = deepcopy(row)
            row_copy["_preference_origin"] = "runtime_failure_reviewed_merge"
            rows.append(row_copy)

    if request.rejected_jsonl is not None:
        for row in read_jsonl(request.rejected_jsonl):
            if not isinstance(row, dict):
                continue
            if "bad_json" not in row or "good_json" not in row:
                continue
            _require_contract_version(row, request.contract_version, source_name="rejected_jsonl")
            row_copy = deepcopy(row)
            row_copy["_preference_origin"] = "offline_eval_bad_vs_corrected"
            rows.append(row_copy)
    return rows
