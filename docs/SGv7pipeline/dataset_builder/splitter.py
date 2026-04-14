from __future__ import annotations

from collections import defaultdict
from copy import deepcopy
from typing import Any


def _group_by_family(records: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in records:
        family = str(row["packaging_metadata"]["split_family_id"])
        grouped[family].append(row)
    return dict(grouped)


def _rarity_score(rows: list[dict[str, Any]]) -> int:
    first = rows[0]["packaging_metadata"]
    score = 0
    if str(first.get("difficulty_bucket")) == "hard":
        score += 10
    if str(first.get("correction_tier")) == "tier_c_reviewed_merge":
        score += 6
    score += len(rows[0].get("critical_eval_tags", []))
    return score


def _assign_families(
    families: dict[str, list[dict[str, Any]]],
    *,
    ratios: tuple[float, float, float],
) -> dict[str, str]:
    order = sorted(
        families.items(),
        key=lambda item: (
            item[1][0]["packaging_metadata"].get("difficulty_bucket", ""),
            -_rarity_score(item[1]),
            item[0],
        ),
    )
    split_names = ("train", "val", "test")
    total = sum(len(rows) for rows in families.values())
    target = {
        "train": total * ratios[0],
        "val": total * ratios[1],
        "test": total * ratios[2],
    }
    current = {"train": 0, "val": 0, "test": 0}
    mapping: dict[str, str] = {}
    for family_id, rows in order:
        best_split = "train"
        best_cost = float("inf")
        for split in split_names:
            projected = current[split] + len(rows)
            cost = abs(projected - target[split]) - abs(current[split] - target[split])
            if cost < best_cost:
                best_cost = cost
                best_split = split
        mapping[family_id] = best_split
        current[best_split] += len(rows)
    return mapping


def split_sft_records(
    records: list[dict[str, Any]],
    *,
    ratios: tuple[float, float, float],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, str]]:
    families = _group_by_family(records)
    mapping = _assign_families(families, ratios=ratios)
    output = {"train": [], "val": [], "test": []}
    for family_id, rows in families.items():
        split = mapping[family_id]
        for row in rows:
            cloned = deepcopy(row)
            cloned["packaging_metadata"]["split"] = split
            output[split].append(cloned)
    for split in output:
        output[split].sort(key=lambda item: item["sample_id"])
    return output, mapping


def split_preference_records(
    records: list[dict[str, Any]],
    *,
    ratios: tuple[float, float, float],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, str], str]:
    families = _group_by_family(records)
    mapping = _assign_families(families, ratios=ratios)

    family_count = len(families)
    coverage_status = "ok"
    if family_count < 3:
        coverage_status = "undersized_preference_corpus"

    if family_count >= 2 and "test" not in set(mapping.values()):
        # deterministic fallback: promote one family into held-out test slice whenever possible
        # so sparse corpora still exercise leakage checks against preference_test.
        movable_families = sorted(
            family_id
            for family_id, split in mapping.items()
            if split in {"train", "val"}
        )
        if movable_families:
            mapping[movable_families[-1]] = "test"

    output = {"train": [], "val": [], "test": []}
    for family_id, rows in families.items():
        split = mapping[family_id]
        for row in rows:
            cloned = deepcopy(row)
            cloned["packaging_metadata"]["split"] = split
            output[split].append(cloned)
    for split in output:
        output[split].sort(key=lambda item: item["preference_id"])
    return output, mapping, coverage_status
