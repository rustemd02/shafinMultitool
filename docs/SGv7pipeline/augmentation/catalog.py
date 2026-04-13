from __future__ import annotations

from dataclasses import dataclass

from .config import SafetyLevel


@dataclass(frozen=True)
class TransformSpec:
    transform_id: str
    transform_class: str
    safety_level: SafetyLevel
    category: str
    core_priority: int
    hard_priority: int


TRANSFORM_SPECS: dict[str, TransformSpec] = {
    "morph.marked_object.case_genitive": TransformSpec(
        "morph.marked_object.case_genitive", "marked_object_morphology", "safe", "marked_object", 10, 10
    ),
    "morph.marked_object.case_dative": TransformSpec(
        "morph.marked_object.case_dative", "marked_object_morphology", "safe", "marked_object", 10, 10
    ),
    "morph.marked_object.case_genitive_noutbuk": TransformSpec(
        "morph.marked_object.case_genitive_noutbuk", "marked_object_morphology", "safe", "marked_object", 10, 10
    ),
    "orthography.actor_yo": TransformSpec(
        "orthography.actor_yo", "orthography_variation", "safe", "orthography", 30, 30
    ),
    "orthography.remove_yo": TransformSpec(
        "orthography.remove_yo", "orthography_variation", "safe", "orthography", 31, 31
    ),
    "ordinal.wrap_actor_head": TransformSpec(
        "ordinal.wrap_actor_head", "ordinal_surface_stress", "safe", "ordinal", 20, 20
    ),
    "ordinal.unwrap_actor_head": TransformSpec(
        "ordinal.unwrap_actor_head", "ordinal_surface_stress", "safe", "ordinal", 21, 21
    ),
    "noise.double_space": TransformSpec(
        "noise.double_space", "whitespace_noise", "safe", "noise", 40, 40
    ),
    "noise.drop_final_punctuation": TransformSpec(
        "noise.drop_final_punctuation", "punctuation_noise", "safe", "noise", 41, 41
    ),
    "noise.drop_optional_comma": TransformSpec(
        "noise.drop_optional_comma", "punctuation_noise", "safe", "noise", 42, 42
    ),
    "noise.no_space_after_comma": TransformSpec(
        "noise.no_space_after_comma", "punctuation_noise", "safe", "noise", 43, 43
    ),
    "telegraph.drop_noncritical_connector": TransformSpec(
        "telegraph.drop_noncritical_connector", "telegraph_shortening", "safe", "telegraph", 35, 25
    ),
    "lexical.preposition_swap": TransformSpec(
        "lexical.preposition_swap", "marked_object_morphology", "risky", "risky", 90, 70
    ),
    "ordinal.numeric_form": TransformSpec(
        "ordinal.numeric_form", "ordinal_surface_stress", "risky", "risky", 91, 71
    ),
    "telegraph.drop_subject_repeat": TransformSpec(
        "telegraph.drop_subject_repeat", "telegraph_shortening", "risky", "risky", 92, 72
    ),
}

NOISE_TRANSFORM_IDS = {
    "noise.double_space",
    "noise.drop_final_punctuation",
    "noise.drop_optional_comma",
    "noise.no_space_after_comma",
}

RISKY_TRANSFORM_IDS = {
    transform_id
    for transform_id, spec in TRANSFORM_SPECS.items()
    if spec.safety_level == "risky"
}


def default_max_augmented_variants_per_parent(difficulty_bucket: str, *, enable_risky: bool) -> int:
    if difficulty_bucket == "core":
        return 1
    if enable_risky:
        return 3
    return 2


def priority_for(transform_id: str, *, difficulty_bucket: str) -> int:
    spec = TRANSFORM_SPECS[transform_id]
    return spec.core_priority if difficulty_bucket == "core" else spec.hard_priority
