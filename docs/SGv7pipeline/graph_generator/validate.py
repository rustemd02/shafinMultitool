from __future__ import annotations

from cir_contract.contracts import CIRValidationError, validate_record

from .config import BucketPolicy, DifficultyBucket


class GraphGeneratorValidationError(ValueError):
    pass


def bucket_policy_for(bucket: DifficultyBucket) -> BucketPolicy:
    if bucket == "core":
        return BucketPolicy(difficulty_bucket="core", allowed_complexity=("S", "M"), max_beats=3, max_actions=5)
    return BucketPolicy(difficulty_bucket="hard", allowed_complexity=("S", "M", "L"), max_beats=4, max_actions=6)


def validate_bucket_policy(record: dict, policy: BucketPolicy) -> None:
    if record["difficulty_bucket"] != policy.difficulty_bucket:
        raise GraphGeneratorValidationError(
            f"difficulty_bucket mismatch: expected={policy.difficulty_bucket}, got={record['difficulty_bucket']}"
        )

    if record["complexity_class"] not in policy.allowed_complexity:
        raise GraphGeneratorValidationError(
            f"complexity_class={record['complexity_class']} is not allowed for bucket={policy.difficulty_bucket}"
        )

    budgets = record["budgets"]
    if budgets["beat_count"] > policy.max_beats:
        raise GraphGeneratorValidationError(
            f"beat_count={budgets['beat_count']} exceeds policy.max_beats={policy.max_beats}"
        )
    if budgets["action_count"] > policy.max_actions:
        raise GraphGeneratorValidationError(
            f"action_count={budgets['action_count']} exceeds policy.max_actions={policy.max_actions}"
        )

    if policy.difficulty_bucket == "hard" and record["complexity_class"] == "L" and record["difficulty_bucket"] != "hard":
        raise GraphGeneratorValidationError("L complexity is only valid for hard records")


def validate_graph_record(record: dict, policy: BucketPolicy) -> None:
    try:
        validate_record(record)
    except CIRValidationError as exc:
        raise GraphGeneratorValidationError(str(exc)) from exc
    validate_bucket_policy(record, policy)

