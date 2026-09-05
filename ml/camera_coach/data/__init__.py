"""Training-side data adapters for the frozen SETCompositionNet-v1 contract."""

from .preprocessing import (
    PreprocessingError,
    normalize_scalar_features,
    preprocess,
    preprocess_frame,
    prepare_inputs,
)

__all__ = [
    "PreprocessingError",
    "normalize_scalar_features",
    "preprocess",
    "preprocess_frame",
    "prepare_inputs",
]
