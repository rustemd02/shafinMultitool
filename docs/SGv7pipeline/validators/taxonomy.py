from __future__ import annotations


CONTRACT_CODES = {
    "contract_missing_required_field",
    "contract_missing_cir_join_source",
    "contract_cir_join_not_found",
    "contract_cir_join_non_unique",
    "contract_sample_id_mismatch",
    "contract_missing_graph_constraints",
    "contract_invalid_critic_payload",
    "contract_unknown_generation_pass",
}

PROVENANCE_CODES = {
    "provenance_missing_tier",
    "provenance_unknown_tier",
    "provenance_tier_not_train_eligible",
}

SCHEMA_CODES = {
    "schema_invalid_cir",
    "schema_invalid_described_action",
    "runtime_projection_failure",
}

GRAPH_CODES = {
    "graph_dangling_target",
    "graph_missing_actor",
    "graph_missing_object",
    "graph_duplicate_action_id",
    "graph_duplicate_beat_id",
}

SEMANTIC_CODES = {
    "semantic_marked_object_lost",
    "semantic_exact_marker_id_conflict",
    "semantic_ordinal_anchor_lost",
    "semantic_same_type_disambiguation_lost",
    "semantic_unsupported_action_lost",
    "semantic_beat_collapse",
    "semantic_invented_object",
    "semantic_invented_action",
    "semantic_invented_dialogue",
}

RECOVERABILITY_CODES = {
    "recoverability_borderline",
    "recoverability_too_low",
    "recoverability_overcompressed",
}

PACKAGING_CODES = {
    "packaging_validation_status_missing",
    "packaging_train_eligibility_conflict",
}

REVIEW_CODES = {
    "review_same_type_marker_conflict",
    "review_recoverability_borderline",
    "review_tier_c_reviewed_merge",
    "review_risky_augmentation_candidate",
    "review_critic_soft_fail",
}

REJECT_CODES = (
    CONTRACT_CODES
    | PROVENANCE_CODES
    | SCHEMA_CODES
    | GRAPH_CODES
    | SEMANTIC_CODES
    | RECOVERABILITY_CODES
    | PACKAGING_CODES
)

ALL_TAXONOMY_CODES = REJECT_CODES | REVIEW_CODES

HARD_FAILURE_CODES = {
    "contract_missing_required_field",
    "contract_missing_cir_join_source",
    "contract_cir_join_not_found",
    "contract_cir_join_non_unique",
    "contract_sample_id_mismatch",
    "contract_missing_graph_constraints",
    "contract_invalid_critic_payload",
    "contract_unknown_generation_pass",
    "provenance_missing_tier",
    "provenance_unknown_tier",
    "schema_invalid_cir",
    "schema_invalid_described_action",
    "runtime_projection_failure",
    "graph_dangling_target",
    "graph_missing_actor",
    "graph_missing_object",
    "graph_duplicate_action_id",
    "graph_duplicate_beat_id",
    "semantic_marked_object_lost",
    "semantic_exact_marker_id_conflict",
    "semantic_ordinal_anchor_lost",
    "semantic_same_type_disambiguation_lost",
    "semantic_unsupported_action_lost",
    "semantic_beat_collapse",
    "semantic_invented_object",
    "semantic_invented_action",
    "semantic_invented_dialogue",
    "recoverability_too_low",
}


def is_allowed_critic_code(code: str) -> bool:
    return code in REJECT_CODES
