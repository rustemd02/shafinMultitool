from __future__ import annotations

from copy import deepcopy

from augmentation.slots import has_complete_graph_constraints


ALLOWED_GENERATION_PASSES = {
    "base_paraphrase",
    "augmentation",
    "real_corrected",
    "reviewed_merge",
}

SYNTHETIC_GENERATION_PASSES = {
    "base_paraphrase",
    "augmentation",
}

KNOWN_PROVENANCE_TIERS = {
    "tier_a_human_gold",
    "tier_b_deterministic_canonical",
    "tier_c_reviewed_merge",
    "tier_d_auto_repair_only",
}


def canonical_graph_id(sample: dict[str, object]) -> str:
    graph_id = sample.get("graph_id", sample.get("sample_id"))
    return str(graph_id)


def materialize_correction_tier(sample: dict[str, object]) -> str | None:
    value = sample.get("correction_tier")
    if isinstance(value, str) and value:
        return value
    generation_pass = sample.get("generation_pass")
    if generation_pass in SYNTHETIC_GENERATION_PASSES:
        return "tier_b_deterministic_canonical"
    return None


def clone_record(sample: dict[str, object]) -> dict[str, object]:
    return deepcopy(sample)


def has_required_envelope_fields(sample: dict[str, object]) -> bool:
    required = ("sample_id", "graph_id", "difficulty_bucket", "source_text")
    return all(isinstance(sample.get(key), str) and str(sample.get(key)).strip() for key in required)


def has_required_graph_constraints(sample: dict[str, object]) -> bool:
    return has_complete_graph_constraints(sample)
