from __future__ import annotations

from .registry import PATTERN_REGISTRY


CRITICAL_RUNTIME_FAILURES: dict[str, str] = {
    "example_1_beat_collapse_and_unsupported_action_loss": "Movement -> stop near marked object -> described action chain collapses or loses unsupported action.",
    "example_2_marked_object_morphology_loss": "Marked object mention in oblique form loses exact grounding or semantic phase.",
    "example_3_multi_beat_role_shift_loss": "Later actor-specific run escalation is flattened into generic symmetric motion.",
    "example_4_same_type_marker_identity_loss": "Two marked objects of the same type collapse into type-only matching.",
    "example_5_acceptability_drift": "Formally valid but semantically poor JSON sneaks through with under-specified actions/objects.",
    "example_6_three_actor_ordinal_binding_loss": "Three-actor scenes lose first/second/third identity or silently drop actor_3.",
    "example_7_three_actor_handoff_loss": "Three-actor object handoff collapses by dropping pick_up/give chronology or recipient binding.",
}


PATTERN_FAILURE_OWNERSHIP: dict[str, tuple[str, ...]] = {
    "dialogue_only": ("example_5_acceptability_drift",),
    "dialogue_then_pick_up_object_then_give_to_third_actor": (
        "example_6_three_actor_ordinal_binding_loss",
        "example_7_three_actor_handoff_loss",
    ),
    "dialogue_then_put_down_object": ("example_5_acceptability_drift",),
    "dialogue_then_small_action": ("example_5_acceptability_drift",),
    "enter_then_put_down_object": ("example_5_acceptability_drift",),
    "open_then_pick_up_object": ("example_5_acceptability_drift",),
    "ordinal_first_second": ("example_5_acceptability_drift",),
    "ordinal_first_second_third": ("example_6_three_actor_ordinal_binding_loss",),
    "pick_up_then_put_down_object": ("example_5_acceptability_drift",),
    "same_type_two_marked_objects": ("example_4_same_type_marker_identity_loss",),
    "stop_near_marked_object_then_first_described_action": (
        "example_1_beat_collapse_and_unsupported_action_loss",
        "example_2_marked_object_morphology_loss",
    ),
    "toward_each_other": ("example_5_acceptability_drift",),
    "toward_each_other_then_pass_by_marked_object": ("example_2_marked_object_morphology_loss",),
    "toward_each_other_then_pass_by_object_then_second_runs": ("example_3_multi_beat_role_shift_loss",),
    "toward_each_other_then_stop_near_marked_object": ("example_2_marked_object_morphology_loss",),
    "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action": (
        "example_1_beat_collapse_and_unsupported_action_loss",
        "example_2_marked_object_morphology_loss",
        "example_6_three_actor_ordinal_binding_loss",
    ),
    "unsupported_action_described_action": ("example_1_beat_collapse_and_unsupported_action_loss",),
}


def build_failure_coverage_report() -> dict[str, object]:
    unknown_patterns = sorted(name for name in PATTERN_FAILURE_OWNERSHIP if name not in PATTERN_REGISTRY)
    patterns_by_failure = {failure_id: [] for failure_id in CRITICAL_RUNTIME_FAILURES}
    unknown_failures: set[str] = set()

    for pattern_name, failure_ids in PATTERN_FAILURE_OWNERSHIP.items():
        for failure_id in failure_ids:
            if failure_id not in CRITICAL_RUNTIME_FAILURES:
                unknown_failures.add(failure_id)
                continue
            patterns_by_failure[failure_id].append(pattern_name)

    for pattern_names in patterns_by_failure.values():
        pattern_names.sort()

    uncovered_failures = sorted(
        failure_id for failure_id, pattern_names in patterns_by_failure.items() if not pattern_names
    )

    return {
        "critical_failure_count": len(CRITICAL_RUNTIME_FAILURES),
        "pattern_count": len(PATTERN_REGISTRY),
        "uncovered_failures": uncovered_failures,
        "unknown_patterns": unknown_patterns,
        "unknown_failures": sorted(unknown_failures),
        "failures": [
            {
                "failure_id": failure_id,
                "description": CRITICAL_RUNTIME_FAILURES[failure_id],
                "owning_patterns": patterns_by_failure[failure_id],
            }
            for failure_id in sorted(CRITICAL_RUNTIME_FAILURES)
        ],
    }
