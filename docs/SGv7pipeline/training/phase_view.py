from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
from typing import Any

from .config import STRICT_SFT_TIERS, TrainingPhaseConfig, default_phase_config
from .io import read_json, read_jsonl, write_json, write_jsonl


class PhaseViewBuildError(ValueError):
    """Raised when phase-view materialization violates Track 8 policy."""


@dataclass(frozen=True)
class PhaseViewRequest:
    phase: str
    sft_train_jsonl: Path
    output_dir: Path
    seed: int
    split_manifest_json: Path | None = None
    preference_train_jsonl: Path | None = None
    phase_config: TrainingPhaseConfig | None = None


def _meta(row: dict[str, Any]) -> dict[str, Any]:
    payload = row.get("packaging_metadata", {})
    return payload if isinstance(payload, dict) else {}


def _sample_id(row: dict[str, Any]) -> str:
    meta = _meta(row)
    return str(meta.get("sample_id") or row.get("sample_id") or "")


def _stable_order(rows: list[dict[str, Any]], seed: int, tag: str) -> list[dict[str, Any]]:
    def _key(row: dict[str, Any]) -> tuple[int, str]:
        sample_id = _sample_id(row)
        digest = hashlib.sha256(f"{seed}|{tag}|{sample_id}".encode("utf-8")).hexdigest()
        return int(digest[:16], 16), sample_id

    return sorted(rows, key=_key)


def _token_count(row: dict[str, Any]) -> int:
    meta = _meta(row)
    return int(meta.get("full_sequence_token_count", 0) or 0)


def _is_l_complexity(row: dict[str, Any]) -> bool:
    return str(_meta(row).get("complexity_class", "")).upper() == "L"


def _is_strict_sft(row: dict[str, Any]) -> bool:
    meta = _meta(row)
    tier = str(meta.get("correction_tier", ""))
    eligibility = str(meta.get("train_eligibility", ""))
    return tier in STRICT_SFT_TIERS and eligibility == "direct_sft"


def _is_core_anchor(row: dict[str, Any]) -> bool:
    meta = _meta(row)
    return _is_strict_sft(row) and str(meta.get("difficulty_bucket", "")) == "core"


def _is_hard_synthetic(row: dict[str, Any]) -> bool:
    meta = _meta(row)
    return _is_strict_sft(row) and str(meta.get("difficulty_bucket", "")) == "hard"


def _is_real_corrected_strict(row: dict[str, Any]) -> bool:
    meta = _meta(row)
    if not _is_strict_sft(row):
        return False
    if str(meta.get("correction_tier", "")) == "tier_a_human_gold":
        return True
    return bool(row.get("promoted_from_manual_review", False))


def _is_reviewed_merge_hard(row: dict[str, Any]) -> bool:
    meta = _meta(row)
    return (
        str(meta.get("train_eligibility", "")) == "hard_or_preference_only"
        and str(meta.get("correction_tier", "")) == "tier_c_reviewed_merge"
    )


def _within_sequence_budget(row: dict[str, Any], max_tokens: int | None) -> bool:
    if max_tokens is None:
        return True
    return _token_count(row) <= max_tokens


def _apply_ratio_targets(
    pools: dict[str, list[dict[str, Any]]],
    ratios: dict[str, float],
    *,
    seed: int,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    ordered_pool_names = [name for name in ratios if name in pools]
    total_available = sum(len(pools[name]) for name in ordered_pool_names)
    if total_available == 0:
        return [], {name: 0 for name in ordered_pool_names}

    raw_targets = {name: total_available * ratios[name] for name in ordered_pool_names}
    targets = {name: int(raw_targets[name]) for name in ordered_pool_names}
    assigned = sum(targets.values())
    if assigned < total_available:
        remainders = sorted(
            ordered_pool_names,
            key=lambda name: (raw_targets[name] - targets[name], name),
            reverse=True,
        )
        for name in remainders:
            if assigned >= total_available:
                break
            targets[name] += 1
            assigned += 1

    for name in ordered_pool_names:
        targets[name] = min(targets[name], len(pools[name]))

    # Redistribute leftover target volume to pools with spare capacity.
    deficit = total_available - sum(targets.values())
    if deficit > 0:
        by_ratio = sorted(
            ordered_pool_names,
            key=lambda name: (ratios[name], name),
            reverse=True,
        )
        while deficit > 0:
            progressed = False
            for name in by_ratio:
                if targets[name] < len(pools[name]):
                    targets[name] += 1
                    deficit -= 1
                    progressed = True
                    if deficit == 0:
                        break
            if not progressed:
                break

    selected: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    for name in ordered_pool_names:
        ordered_rows = _stable_order(pools[name], seed=seed, tag=name)
        picked = ordered_rows[: targets[name]]
        selected.extend(picked)
        counts[name] = len(picked)
    return selected, counts


def _enforce_l_caps(
    rows: list[dict[str, Any]],
    *,
    seed: int,
    max_l_sample_ratio: float,
    max_l_token_ratio: float,
) -> tuple[list[dict[str, Any]], int]:
    if not rows:
        return rows, 0
    output = list(rows)
    dropped = 0
    while output:
        l_rows = [row for row in output if _is_l_complexity(row)]
        total = len(output)
        total_tokens = sum(max(1, _token_count(row)) for row in output)
        l_tokens = sum(max(1, _token_count(row)) for row in l_rows)
        max_l_count = int(total * max_l_sample_ratio)
        max_l_tokens = int(total_tokens * max_l_token_ratio)
        over_count = len(l_rows) > max_l_count
        over_tokens = l_tokens > max_l_tokens
        if not over_count and not over_tokens:
            return sorted(output, key=_sample_id), dropped
        if not l_rows:
            return sorted(output, key=_sample_id), dropped
        ranked = _stable_order(l_rows, seed=seed, tag="drop_l_complexity")
        victim = ranked[-1]
        victim_id = _sample_id(victim)
        output = [row for row in output if _sample_id(row) != victim_id]
        dropped += 1
    return [], dropped


def _enforce_reviewed_merge_caps(
    rows: list[dict[str, Any]],
    *,
    seed: int,
    max_ratio_of_hard_by_samples: float,
    max_ratio_of_hard_by_tokens: float,
    max_total_ratio_by_samples: float,
) -> tuple[list[dict[str, Any]], int]:
    if not rows:
        return rows, 0
    output = list(rows)
    dropped = 0
    while output:
        reviewed = [row for row in output if _is_reviewed_merge_hard(row)]
        hard = [row for row in output if str(_meta(row).get("difficulty_bucket", "")) == "hard"]
        if not reviewed or not hard:
            return sorted(output, key=_sample_id), dropped

        reviewed_count = len(reviewed)
        hard_count = max(1, len(hard))
        reviewed_tokens = sum(max(1, _token_count(row)) for row in reviewed)
        hard_tokens = max(1, sum(max(1, _token_count(row)) for row in hard))
        total_count = len(output)

        over_sample_ratio = reviewed_count > int(hard_count * max_ratio_of_hard_by_samples)
        over_token_ratio = reviewed_tokens > int(hard_tokens * max_ratio_of_hard_by_tokens)
        over_total_ratio = reviewed_count > int(total_count * max_total_ratio_by_samples)
        if not (over_sample_ratio or over_token_ratio or over_total_ratio):
            return sorted(output, key=_sample_id), dropped

        ranked = _stable_order(reviewed, seed=seed, tag="drop_reviewed_merge")
        victim = ranked[-1]
        victim_id = _sample_id(victim)
        output = [row for row in output if _sample_id(row) != victim_id]
        dropped += 1
    return [], dropped


def _attach_training_fields(
    rows: list[dict[str, Any]],
    *,
    pool_by_sample: dict[str, str],
    multipliers: dict[str, float],
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for row in sorted(rows, key=_sample_id):
        sample_id = _sample_id(row)
        pool = pool_by_sample.get(sample_id, "unknown")
        weight = float(multipliers.get(pool, 1.0))
        row_copy = dict(row)
        row_copy["phase_pool"] = pool
        row_copy["training_weight"] = weight
        result.append(row_copy)
    return result


def _selected_by_pool(rows: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        pool = str(row.get("phase_pool", "unknown"))
        counts[pool] = counts.get(pool, 0) + 1
    return counts


def _build_sft_view(rows: list[dict[str, Any]], *, config: TrainingPhaseConfig, seed: int) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    eligible = [row for row in rows if _within_sequence_budget(row, config.max_full_sequence_tokens)]
    if config.phase == "phase1_core_bootstrap":
        core_rows = [row for row in eligible if _is_core_anchor(row) and not _is_l_complexity(row)]
        pool_by_sample = {_sample_id(row): "core_anchor" for row in core_rows}
        output = _attach_training_fields(core_rows, pool_by_sample=pool_by_sample, multipliers=config.pool_multipliers)
        selected = {"core_anchor": len(output)}
        return output, {
            "selected_by_pool": selected,
            "selected_by_pool_pre_cap": selected,
            "dropped_l_complexity": 0,
            "dropped_reviewed_merge": 0,
        }

    # Build disjoint pools in fixed priority order.
    pools: dict[str, list[dict[str, Any]]] = {
        "core_anchor": [],
        "hard_synthetic": [],
        "real_corrected_strict": [],
        "reviewed_merge_hard": [],
    }
    seen: set[str] = set()
    for row in eligible:
        sample_id = _sample_id(row)
        if not sample_id or sample_id in seen:
            continue
        if config.phase == "phase3_hard_consolidation" and _is_reviewed_merge_hard(row):
            pools["reviewed_merge_hard"].append(row)
            seen.add(sample_id)
            continue
        if _is_real_corrected_strict(row):
            pools["real_corrected_strict"].append(row)
            seen.add(sample_id)
            continue
        if _is_core_anchor(row):
            pools["core_anchor"].append(row)
            seen.add(sample_id)
            continue
        if _is_hard_synthetic(row):
            pools["hard_synthetic"].append(row)
            seen.add(sample_id)
            continue

    if config.phase == "phase2_mixed_sft":
        pools.pop("reviewed_merge_hard", None)

    selected_rows, selected_by_pool = _apply_ratio_targets(pools, config.pool_ratios, seed=seed)

    selected_rows, dropped_l = _enforce_l_caps(
        selected_rows,
        seed=seed,
        max_l_sample_ratio=config.max_l_sample_ratio,
        max_l_token_ratio=config.max_l_token_ratio,
    )
    dropped_reviewed = 0
    if config.phase == "phase3_hard_consolidation":
        selected_rows, dropped_reviewed = _enforce_reviewed_merge_caps(
            selected_rows,
            seed=seed,
            max_ratio_of_hard_by_samples=config.max_reviewed_merge_hard_ratio_by_samples or 1.0,
            max_ratio_of_hard_by_tokens=config.max_reviewed_merge_hard_ratio_by_tokens or 1.0,
            max_total_ratio_by_samples=config.max_reviewed_merge_total_ratio_by_samples or 1.0,
        )

    pool_by_sample: dict[str, str] = {}
    for pool_name, pool_rows in pools.items():
        for row in pool_rows:
            pool_by_sample.setdefault(_sample_id(row), pool_name)
    output_rows = _attach_training_fields(
        selected_rows,
        pool_by_sample=pool_by_sample,
        multipliers=config.pool_multipliers,
    )
    post_cap_selected_by_pool = _selected_by_pool(output_rows)
    meta = {
        "selected_by_pool": post_cap_selected_by_pool,
        "selected_by_pool_pre_cap": selected_by_pool,
        "dropped_l_complexity": dropped_l,
        "dropped_reviewed_merge": dropped_reviewed,
    }
    return output_rows, meta


def _build_preference_view(request: PhaseViewRequest, *, config: TrainingPhaseConfig) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if request.preference_train_jsonl is None:
        raise PhaseViewBuildError("phase4_preference requires preference_train_jsonl")
    rows = read_jsonl(request.preference_train_jsonl)
    rows_sorted = sorted(rows, key=lambda item: str(item.get("preference_id", "")))

    def _pattern_name(row: dict[str, Any]) -> str:
        meta = _meta(row)
        return str(meta.get("pattern_name") or "")

    def _semantic_tags(row: dict[str, Any]) -> set[str]:
        meta = _meta(row)
        tags = meta.get("semantic_tags")
        if not isinstance(tags, list):
            return set()
        return {str(tag) for tag in tags if str(tag)}

    def _families(row: dict[str, Any]) -> set[str]:
        pattern = _pattern_name(row)
        tags = _semantic_tags(row)
        families: set[str] = set()
        if "ordinal_reference" in tags or pattern.startswith("ordinal_"):
            families.add("ordinal")
        if "multi_beat" in tags:
            families.add("three_beat")
        if "same_type_markers" in tags or pattern.startswith("same_type_two_marked_objects"):
            families.add("exact_marker_identity")
        if pattern == "open_then_pick_up_object":
            families.add("open_then_pick_up")
        if "give_to_third_actor" in pattern:
            families.add("give_to_third_actor")
        return families

    dropped_by_pattern_cap: dict[str, int] = {}
    dropped_by_family_cap: dict[str, int] = {}
    capped_rows = rows_sorted
    if config.phase4_max_pattern_share is not None:
        max_share = float(config.phase4_max_pattern_share)
        if not 0 < max_share <= 1:
            raise PhaseViewBuildError(f"phase4_max_pattern_share must be in (0,1], got {max_share!r}")
        by_pattern: dict[str, list[dict[str, Any]]] = {}
        for row in rows_sorted:
            by_pattern.setdefault(_pattern_name(row), []).append(row)
        ordered_by_pattern: dict[str, list[dict[str, Any]]] = {}
        kept_counts: dict[str, int] = {}
        for pattern, pattern_rows in sorted(by_pattern.items(), key=lambda item: item[0]):
            ordered = _stable_order(pattern_rows, seed=request.seed, tag=f"phase4_pattern_cap::{pattern}")
            ordered_by_pattern[pattern] = ordered
            kept_counts[pattern] = len(ordered)

        # Enforce share against the evolving retained total to guarantee the final cap.
        while True:
            retained_total = sum(kept_counts.values())
            if retained_total <= 0:
                break
            max_allowed = int(retained_total * max_share)
            if max_allowed <= 0:
                raise PhaseViewBuildError(
                    "phase4_max_pattern_share is too strict for current preference pool: "
                    f"retained_total={retained_total}, max_share={max_share}"
                )
            over_limit = [pattern for pattern, count in kept_counts.items() if count > max_allowed]
            if not over_limit:
                break
            over_limit.sort(
                key=lambda pattern: (
                    -(kept_counts[pattern] - max_allowed),
                    -kept_counts[pattern],
                    pattern,
                )
            )
            pattern = over_limit[0]
            kept_counts[pattern] -= 1
            dropped_key = pattern or "unknown"
            dropped_by_pattern_cap[dropped_key] = dropped_by_pattern_cap.get(dropped_key, 0) + 1

        capped_rows = []
        for pattern in sorted(ordered_by_pattern.keys()):
            kept = ordered_by_pattern[pattern][: kept_counts[pattern]]
            capped_rows.extend(kept)
        capped_rows = sorted(capped_rows, key=lambda item: str(item.get("preference_id", "")))

    if config.phase4_max_family_share is not None:
        max_share = float(config.phase4_max_family_share)
        if not 0 < max_share <= 1:
            raise PhaseViewBuildError(f"phase4_max_family_share must be in (0,1], got {max_share!r}")
        ordered_rows = _stable_order(capped_rows, seed=request.seed, tag="phase4_family_cap")
        row_by_id = {str(row.get("preference_id", "")): row for row in ordered_rows}
        family_by_id = {
            preference_id: _families(row)
            for preference_id, row in row_by_id.items()
        }
        stable_rank = {
            str(row.get("preference_id", "")): index
            for index, row in enumerate(ordered_rows)
        }
        kept_ids = {str(row.get("preference_id", "")) for row in ordered_rows}

        while True:
            retained_ids = [preference_id for preference_id in kept_ids if preference_id in row_by_id]
            retained_total = len(retained_ids)
            if retained_total <= 0:
                break
            max_allowed = int(retained_total * max_share)
            if max_allowed <= 0:
                raise PhaseViewBuildError(
                    "phase4_max_family_share is too strict for current preference pool: "
                    f"retained_total={retained_total}, max_share={max_share}"
                )

            current_family_counts: dict[str, int] = {}
            for preference_id in retained_ids:
                for family in family_by_id.get(preference_id, set()):
                    current_family_counts[family] = current_family_counts.get(family, 0) + 1
            over_limit = [
                family
                for family, count in current_family_counts.items()
                if count > max_allowed
            ]
            if not over_limit:
                break
            over_limit.sort(
                key=lambda family: (
                    -(current_family_counts[family] - max_allowed),
                    -current_family_counts[family],
                    family,
                )
            )
            target_family = over_limit[0]
            over_limit_set = set(over_limit)
            candidates = [
                preference_id
                for preference_id in retained_ids
                if target_family in family_by_id.get(preference_id, set())
            ]
            if not candidates:
                raise PhaseViewBuildError(
                    f"phase4_max_family_share could not identify a removable row for family={target_family!r}"
                )
            candidates.sort(
                key=lambda preference_id: (
                    len(family_by_id.get(preference_id, set()) & over_limit_set),
                    len(family_by_id.get(preference_id, set())),
                    stable_rank.get(preference_id, -1),
                    preference_id,
                ),
                reverse=True,
            )
            victim_id = candidates[0]
            kept_ids.remove(victim_id)
            dropped_by_family_cap[target_family] = dropped_by_family_cap.get(target_family, 0) + 1

        capped_rows = sorted(
            (row_by_id[preference_id] for preference_id in kept_ids),
            key=lambda item: str(item.get("preference_id", "")),
        )

    min_family_counts: dict[str, int] = {str(k): int(v) for k, v in config.phase4_min_family_counts.items()}
    family_counts: dict[str, int] = {name: 0 for name in min_family_counts.keys()}
    if min_family_counts:
        for row in capped_rows:
            for family in _families(row):
                if family in family_counts:
                    family_counts[family] = family_counts.get(family, 0) + 1
        missing = {
            family: (family_counts.get(family, 0), min_count)
            for family, min_count in min_family_counts.items()
            if family_counts.get(family, 0) < min_count
        }
        if missing:
            details = ", ".join(
                f"{family}={current}<{required}"
                for family, (current, required) in sorted(missing.items(), key=lambda item: item[0])
            )
            raise PhaseViewBuildError(f"phase4 preference family coverage below minimum: {details}")

    pattern_weight_overrides = {str(k): float(v) for k, v in config.phase4_pattern_weight_overrides.items()}
    family_weight_overrides = {str(k): float(v) for k, v in config.phase4_family_weight_overrides.items()}

    output = []
    base_weight = float(config.pool_multipliers.get("preference", 1.0))
    for row in capped_rows:
        row_copy = dict(row)
        row_copy["phase_pool"] = "preference"
        pattern = _pattern_name(row)
        weight = base_weight
        pattern_weight = pattern_weight_overrides.get(pattern)
        if pattern_weight is not None:
            weight = max(weight, pattern_weight)
        for family in _families(row):
            family_weight = family_weight_overrides.get(family)
            if family_weight is not None:
                weight = max(weight, family_weight)
        row_copy["training_weight"] = float(weight)
        output.append(row_copy)
    meta = {
        "selected_by_pool": {"preference": len(output)},
        "selected_by_pool_pre_cap": {"preference": len(rows_sorted)},
        "dropped_l_complexity": 0,
        "dropped_reviewed_merge": 0,
        "dropped_by_pattern_cap": dropped_by_pattern_cap,
        "dropped_by_family_cap": dropped_by_family_cap,
        "family_counts": family_counts,
    }
    return output, meta


def _split_manifest_contract_version(path: Path | None) -> str | None:
    if path is None:
        return None
    payload = read_json(path)
    contracts = payload.get("contract_versions_present", [])
    if not isinstance(contracts, list) or len(contracts) != 1:
        raise PhaseViewBuildError("split_manifest must have exactly one contract_version in contract_versions_present")
    return str(contracts[0])


def build_phase_view(request: PhaseViewRequest) -> dict[str, Any]:
    config = request.phase_config or default_phase_config(request.phase)
    if config.task_type not in {"sft", "preference"}:
        raise PhaseViewBuildError(f"unsupported task_type={config.task_type!r}")

    contract_version = _split_manifest_contract_version(request.split_manifest_json)
    sft_rows = read_jsonl(request.sft_train_jsonl)

    if config.task_type == "preference":
        phase_rows, build_meta = _build_preference_view(request, config=config)
        output_name = f"{config.phase}_preference_train.jsonl"
    else:
        phase_rows, build_meta = _build_sft_view(sft_rows, config=config, seed=request.seed)
        output_name = f"{config.phase}_sft_train.jsonl"

    output_jsonl = request.output_dir / output_name
    output_manifest = request.output_dir / f"{config.phase}_view_manifest.json"
    write_jsonl(phase_rows, output_jsonl)

    result = {
        "phase": config.phase,
        "task_type": config.task_type,
        "seed": request.seed,
        "contract_version": contract_version,
        "input_artifacts": {
            "sft_train_jsonl": str(request.sft_train_jsonl),
            "split_manifest_json": str(request.split_manifest_json) if request.split_manifest_json else None,
            "preference_train_jsonl": str(request.preference_train_jsonl) if request.preference_train_jsonl else None,
        },
        "output_artifacts": {"phase_train_jsonl": str(output_jsonl)},
        "counts": {
            "selected_records": len(phase_rows),
            **build_meta,
        },
        "phase_config": {
            "pool_ratios": config.pool_ratios,
            "pool_multipliers": config.pool_multipliers,
            "max_l_sample_ratio": config.max_l_sample_ratio,
            "max_l_token_ratio": config.max_l_token_ratio,
            "max_full_sequence_tokens": config.max_full_sequence_tokens,
            "max_reviewed_merge_hard_ratio_by_samples": config.max_reviewed_merge_hard_ratio_by_samples,
            "max_reviewed_merge_hard_ratio_by_tokens": config.max_reviewed_merge_hard_ratio_by_tokens,
            "max_reviewed_merge_total_ratio_by_samples": config.max_reviewed_merge_total_ratio_by_samples,
            "phase3_eval_interval_steps": config.phase3_eval_interval_steps,
            "phase3_positive_bucket_improvement_pp": config.phase3_positive_bucket_improvement_pp,
            "phase4_min_preference_train": config.phase4_min_preference_train,
            "phase4_min_preference_val": config.phase4_min_preference_val,
            "phase4_min_preference_test": config.phase4_min_preference_test,
            "phase4_min_preference_win_rate_gain_pp": config.phase4_min_preference_win_rate_gain_pp,
            "phase4_max_pattern_share": config.phase4_max_pattern_share,
            "phase4_max_family_share": config.phase4_max_family_share,
            "phase4_pattern_weight_overrides": config.phase4_pattern_weight_overrides,
            "phase4_min_family_counts": config.phase4_min_family_counts,
            "phase4_family_weight_overrides": config.phase4_family_weight_overrides,
        },
    }
    write_json(result, output_manifest)
    return result
