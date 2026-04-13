"""Deterministic graph generator for SG v7."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from .builder import GraphBuildError, build_graph_records, materialize_plan_item
from .config import (
    BucketPolicy,
    BuildResult,
    DifficultyBucket,
    GraphBuildRequest,
    OutputTargets,
    PatternQuota,
    PlanItem,
)
from .dedup import DedupIndex, dedup_group_key, graph_fingerprint, normalize_record_for_graph_fingerprint
from .planner import GraphPlannerError, derive_graph_seed, plan_graph_records, plan_pattern_quotas
from .validate import GraphGeneratorValidationError, bucket_policy_for, validate_bucket_policy, validate_graph_record

__all__ = [
    "BucketPolicy",
    "BuildResult",
    "DedupIndex",
    "DifficultyBucket",
    "GraphBuildError",
    "GraphBuildRequest",
    "GraphGeneratorValidationError",
    "GraphPlannerError",
    "OutputTargets",
    "PatternQuota",
    "PlanItem",
    "bucket_policy_for",
    "build_graph_records",
    "dedup_group_key",
    "derive_graph_seed",
    "graph_fingerprint",
    "materialize_plan_item",
    "normalize_record_for_graph_fingerprint",
    "plan_graph_records",
    "plan_pattern_quotas",
    "validate_bucket_policy",
    "validate_graph_record",
]
