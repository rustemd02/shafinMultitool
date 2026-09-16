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
from .intent_features import (
    INTENT_ORDER,
    INTENT_STYLE_NAMES,
    KNOWN_FLAG_INDEX,
    assemble_v2_inputs,
    encode_intent,
    intent_supervision_mask,
    preprocess_frame_v2,
    validate_intent_features,
)

__all__ = [
    "INTENT_ORDER",
    "INTENT_STYLE_NAMES",
    "KNOWN_FLAG_INDEX",
    "PreprocessingError",
    "assemble_v2_inputs",
    "encode_intent",
    "intent_supervision_mask",
    "normalize_scalar_features",
    "preprocess",
    "preprocess_frame",
    "preprocess_frame_v2",
    "prepare_inputs",
    "validate_intent_features",
]
