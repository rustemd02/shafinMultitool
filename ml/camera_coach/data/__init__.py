"""Camera Coach data preprocessing.

Augmentation authorities stay in the explicit submodule and are not imported
by ordinary package initialization while production M3 authority is absent.
"""

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
