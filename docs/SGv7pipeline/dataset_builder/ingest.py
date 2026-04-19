from __future__ import annotations

from collections import defaultdict
from copy import deepcopy
import hashlib
import re
from typing import Any

from cir_contract.contracts import structural_hash
from graph_generator.dedup import graph_fingerprint
from pattern_library import PATTERN_REGISTRY
from source_generation.filters import (
    disallowed_source_text_reasons,
    has_technical_identifier_literals,
    meta_language_reasons,
    morphology_reasons,
    normalize_persisted_source_text,
    surface_noise_reasons,
    technical_literal_reasons,
)

from .config import DatasetBuildError, DatasetBuildRequest
from .renderer import render_sft_messages
from .writer import read_jsonl


_WS_RE = re.compile(r"\s+", flags=re.UNICODE)
_EDGE_PUNCT_RE = re.compile(r"^[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+|[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+$")
_META_TAIL_RE = re.compile(
    r"\b(?:"
    r"beat_count\s*=\s*\d+|pass_by_then_role_shift|stop_near_then_role_shift|stop_phase_before_run|"
    r"marked_object_grounding|second_actor_runs|final_beat|multi_beat|recoverability|"
    r"must_ground_object|canonical|role_shift|put_down_target|holding_object_preserved|"
    r"handoff_object|pickup_target|inside_relation|open_before_pick_up|dual_motion|"
    r"symmetric_toward_each_other|direction_toward_each_other|pass_by|pick_up|put_down"
    r")\b",
    flags=re.IGNORECASE,
)

CRITICAL_EVAL_TAGS = (
    "ordinal_cases",
    "marked_object_morphology",
    "same_type_markers",
    "unsupported_action_cases",
    "three_beat_cases",
    "exact_marker_identity_cases",
    "reviewed_merge_cases",
)

_LEXEME_FAMILY_PATTERNS: dict[str, re.Pattern[str]] = {
    "comp_family": re.compile(
        r"(?:\bкомп(?:а|у|ом|е)?\b|\bкомпьютер(?:а|у|ом|е|ы|ов|ам|ами|ах)?\b)",
        flags=re.IGNORECASE,
    ),
    "notebook_family": re.compile(
        r"\bноутбук(?:а|у|ом|е|и|ов|ам|ами|ах)?\b",
        flags=re.IGNORECASE,
    ),
    "smoke_family": re.compile(
        r"(?:\bкур(?:ить|ю|ит|ят|ил|ила|или|ишь|им|ите)\b|\bзакур(?:ить|ю|ит|ят|ил|ила|или)\b|\bсигарет(?:а|ы|е|у|ой|ами|ах)?\b)",
        flags=re.IGNORECASE,
    ),
}


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


def sanitize_source_text_for_sft(text: str) -> str:
    value = normalize_persisted_source_text(text)
    if not value:
        return value
    if "\ufffd" in value:
        return ""

    meta_rejects = meta_language_reasons(value)
    surface_rejects = surface_noise_reasons(value)
    morphology_rejects = morphology_reasons(value)
    if not meta_rejects and not surface_rejects and not morphology_rejects:
        return value

    replacements = (
        (
            r"\bпервый\s+акт[её]р\s+и\s+второй\s+акт[её]ры\b",
            "первый и второй актёры",
        ),
        (
            r"\bоткрывает\s+коробка\b",
            "открывает коробку",
        ),
        (
            r"\bколоны\b",
            "колонны",
        ),
        (
            r"\bу\s+стол\b",
            "у стола",
        ),
        (
            r"\bк\s+ближний\b",
            "к ближнему",
        ),
        (
            r"\bк\s+дальний\b",
            "к дальнему",
        ),
        (
            r"\bу\s+ближний\b",
            "у ближнего",
        ),
        (
            r"\bу\s+дальний\b",
            "у дальнего",
        ),
        (
            r"\bоколо\s+ближний\b",
            "около ближнего",
        ),
        (
            r"\bоколо\s+дальний\b",
            "около дальнего",
        ),
        (
            r"\bвозле\s+ближний\b",
            "возле ближнего",
        ),
        (
            r"\bвозле\s+дальний\b",
            "возле дальнего",
        ),
        (
            r"\bрядом\s+с\s+ближний\b",
            "рядом с ближним",
        ),
        (
            r"\bрядом\s+с\s+дальний\b",
            "рядом с дальним",
        ),
        (
            r"\bмимо\s+ближний\b",
            "мимо ближнего",
        ),
        (
            r"\bмимо\s+дальний\b",
            "мимо дальнего",
        ),
        (
            r"\bво?\s+втором\s+акт[её]ре(?:\s+в\s+(?:конце|финале))?\s+начина(?:ет|ется)\s+(?:бег(?:ать)?|бежать)\b",
            "в конце второй актёр начинает бежать",
        ),
        (
            r"\bво?\s+втором\s+акт[её]ре(?:\s+в\s+(?:конце|финале))?\s+уже\s+начина(?:ет|ется)\s+(?:бег(?:ать)?|бежать)\b",
            "в конце второй актёр начинает бежать",
        ),
    )
    for pattern, replacement in replacements:
        value = re.sub(pattern, replacement, value, flags=re.IGNORECASE)

    value = re.sub(
        r"\b(первый|второй|третий)\s+(?!акт[её]р\b)([А-ЯЁ][а-яё]+)\s+"
        r"(подходит|ид[её]т|направляется|бер[её]т|клад[её]т|оста[её]тся|смотрит|входит|проходит|начинает)\b",
        r"\1 актёр \2 \3",
        value,
        flags=re.IGNORECASE,
    )

    def _strip_meta_parenthetical(match: re.Match[str]) -> str:
        inner = match.group(1)
        if _META_TAIL_RE.search(inner):
            return ""
        return match.group(0)

    value = re.sub(r"\(([^)]*)\)", _strip_meta_parenthetical, value)
    value = re.sub(
        r"([,;]\s*[^,;.!?]*\b(?:beat_count\s*=\s*\d+|pass_by_then_role_shift|stop_near_then_role_shift|"
        r"stop_phase_before_run|marked_object_grounding|second_actor_runs|final_beat|multi_beat|recoverability|"
        r"must_ground_object|canonical|role_shift|put_down_target|holding_object_preserved|handoff_object|"
        r"pickup_target|inside_relation|open_before_pick_up|dual_motion|symmetric_toward_each_other|"
        r"direction_toward_each_other|pass_by|pick_up|put_down)\b[^,;.!?]*)$",
        "",
        value,
        flags=re.IGNORECASE,
    )

    dash_tail = re.search(r"\s*[—-]\s*(.+)$", value)
    if dash_tail and _META_TAIL_RE.search(dash_tail.group(1)):
        value = value[:dash_tail.start()]

    value = re.sub(r"\s+([,.;:!?])", r"\1", value)
    value = re.sub(r"\s{2,}", " ", value, flags=re.UNICODE)
    value = value.strip(" -—,;:")
    return normalize_persisted_source_text(value)


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
        if promoted_train_eligibility != "hard_or_preference_only":
            raise DatasetBuildError(
                "manual_review promotion must target hard_or_preference_only; "
                f"got promoted_train_eligibility={promoted_train_eligibility!r} for sample_id={sample_id!r}"
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
    if bool(row.get("promoted_from_manual_review", False)):
        return False
    return str(row.get("train_eligibility", "")) == "direct_sft"


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


def _candidate_keep_priority(candidate: dict[str, Any]) -> tuple[int, int, int, int, str]:
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


def _validate_optional_share(name: str, value: float | None) -> None:
    if value is None:
        return
    if value < 0 or value > 1:
        raise DatasetBuildError(f"{name} must be within [0,1], got {value!r}")


def detect_lexeme_families(text: str) -> set[str]:
    lowered = text.lower()
    return {
        family
        for family, pattern in _LEXEME_FAMILY_PATTERNS.items()
        if pattern.search(lowered)
    }


def _enforce_technical_source_share(
    candidates: list[dict[str, Any]],
    *,
    max_share: float | None,
) -> tuple[list[dict[str, Any]], int]:
    if not candidates:
        return [], 0
    if max_share is None:
        return candidates, 0

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
    ranked = sorted(technical, key=_candidate_keep_priority, reverse=True)
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


def _enforce_lexeme_family_share(
    candidates: list[dict[str, Any]],
    *,
    max_shares: dict[str, float | None],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    if not candidates:
        return [], {family: 0 for family in max_shares}

    active_caps = {family: share for family, share in max_shares.items() if share is not None}
    if not active_caps:
        return candidates, {family: 0 for family in max_shares}

    counts = {family: 0 for family in active_caps}
    keep_mask = [True] * len(candidates)
    for idx, candidate in enumerate(candidates):
        families = candidate.get("_lexeme_families", set())
        if not isinstance(families, set):
            families = set(families) if isinstance(families, (list, tuple)) else set()
            candidate["_lexeme_families"] = families
        for family in families:
            if family in counts:
                counts[family] += 1

    dropped_by_family = {family: 0 for family in max_shares}

    while True:
        current_total = sum(1 for keep in keep_mask if keep)
        allowed_by_family: dict[str, int] = {}
        for family, share in active_caps.items():
            if share <= 0:
                allowed = 0
            elif share >= 1:
                allowed = current_total
            else:
                allowed = int(current_total * share)
            allowed_by_family[family] = allowed

        overflow = {
            family: counts[family] - allowed_by_family[family]
            for family in active_caps
            if counts[family] > allowed_by_family[family]
        }
        if not overflow:
            break

        best_idx: int | None = None
        best_key: tuple[int, int, tuple[int, int, int, int, str]] | None = None
        for idx, candidate in enumerate(candidates):
            if not keep_mask[idx]:
                continue
            families = candidate.get("_lexeme_families", set())
            impacted = [family for family in families if family in overflow]
            if not impacted:
                continue
            key = (
                -sum(overflow[family] for family in impacted),
                -len(impacted),
                _candidate_keep_priority(candidate),
            )
            if best_key is None or key < best_key:
                best_key = key
                best_idx = idx

        if best_idx is None:
            break

        keep_mask[best_idx] = False
        families = candidates[best_idx].get("_lexeme_families", set())
        for family in families:
            if family in counts:
                counts[family] -= 1
                dropped_by_family[family] += 1

    filtered = [candidate for idx, candidate in enumerate(candidates) if keep_mask[idx]]
    return filtered, dropped_by_family


def load_sft_candidates(
    request: DatasetBuildRequest,
    *,
    cir_index: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    _validate_optional_share("max_technical_source_share", request.max_technical_source_share)
    _validate_optional_share("max_comp_family_share", request.max_comp_family_share)
    _validate_optional_share("max_notebook_family_share", request.max_notebook_family_share)
    _validate_optional_share("max_smoke_family_share", request.max_smoke_family_share)

    accepted_rows = read_jsonl(request.accepted_jsonl)
    promoted_rows = _load_promoted_review_rows(request, contract_version=request.contract_version)
    candidates: list[dict[str, Any]] = []
    dropped = {
        "not_admitted_by_policy": 0,
        "missing_cir_join": 0,
        "technical_literal_source": 0,
        "meta_language_source": 0,
        "surface_noise_source": 0,
        "bad_morphology_source": 0,
        "comp_family_over_budget": 0,
        "notebook_family_over_budget": 0,
        "smoke_family_over_budget": 0,
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

        source_text_raw = normalize_persisted_source_text(str(row.get("source_text", "")))
        source_text = sanitize_source_text_for_sft(source_text_raw)
        if not source_text:
            dropped["not_admitted_by_policy"] += 1
            continue

        technical_rejects = technical_literal_reasons(source_text)
        meta_rejects = meta_language_reasons(source_text)
        surface_rejects = surface_noise_reasons(source_text)
        morphology_rejects = morphology_reasons(source_text)
        if technical_rejects or meta_rejects or surface_rejects or morphology_rejects:
            if technical_rejects:
                dropped["technical_literal_source"] += 1
            if meta_rejects:
                dropped["meta_language_source"] += 1
            if surface_rejects:
                dropped["surface_noise_source"] += 1
            if morphology_rejects:
                dropped["bad_morphology_source"] += 1
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
            "source_text_sanitized": source_text != source_text_raw,
            "promoted_from_manual_review": bool(row.get("promoted_from_manual_review", False)),
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
            "source_text_quality_flags": disallowed_source_text_reasons(source_text),
            "_has_technical_literals": has_technical_literals,
            "_lexeme_families": detect_lexeme_families(source_text),
        }
        candidates.append(candidate)

    filtered_candidates, dropped_technical = _enforce_technical_source_share(
        candidates,
        max_share=request.max_technical_source_share,
    )
    dropped["technical_token_over_budget"] = dropped_technical

    filtered_candidates, dropped_by_family = _enforce_lexeme_family_share(
        filtered_candidates,
        max_shares={
            "comp_family": request.max_comp_family_share,
            "notebook_family": request.max_notebook_family_share,
            "smoke_family": request.max_smoke_family_share,
        },
    )
    dropped["comp_family_over_budget"] += dropped_by_family.get("comp_family", 0)
    dropped["notebook_family_over_budget"] += dropped_by_family.get("notebook_family", 0)
    dropped["smoke_family_over_budget"] += dropped_by_family.get("smoke_family", 0)

    for candidate in filtered_candidates:
        candidate.pop("_has_technical_literals", None)
        candidate.pop("_lexeme_families", None)
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
