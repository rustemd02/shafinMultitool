"""Executable source generation artifacts for SG v7."""

from .batcher import HeuristicParaphraser, OpenAIParaphraser, build_variant_plan, generate_source_variants
from .config import SourceGenerationRequest, SourceGenerationResult, StyleBucket, VariantPlanItem
from .filters import evaluate_candidate_text

__all__ = [
    "HeuristicParaphraser",
    "OpenAIParaphraser",
    "SourceGenerationRequest",
    "SourceGenerationResult",
    "StyleBucket",
    "VariantPlanItem",
    "build_variant_plan",
    "evaluate_candidate_text",
    "generate_source_variants",
]
