"""v2 intent preprocessing and loader-facing input assembly.

The pixel/scalar path is inherited unchanged from the v1 preprocessor.  v2 adds
one explicit step: encoding the CaptureIntent style selection into the frozen
9-component ``intent_features`` vector, with an unambiguous unknown state that
is never filled with ``natural``.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

import torch
from torch import Tensor

from ..models.set_composition_net import SETCompositionNetInputs
from ..models.set_composition_net_v2 import (
    INTENT_ORDER,
    INTENT_STYLE_NAMES,
    KNOWN_FLAG_INDEX,
    SETCompositionNetV2Inputs,
    encode_intent,
    intent_supervision_mask,
    validate_intent_features,
)
from .preprocessing import preprocess_frame


def assemble_v2_inputs(
    base: SETCompositionNetInputs,
    intent_features: Tensor,
) -> SETCompositionNetV2Inputs:
    """Attach validated ``intent_features`` to the inherited v1 tensors."""

    if not isinstance(base, SETCompositionNetInputs):
        raise TypeError("base must be a SETCompositionNetInputs instance")
    intent = validate_intent_features(intent_features)
    return SETCompositionNetV2Inputs(
        full_frame_rgb=base.full_frame_rgb,
        subject_crop_rgb=base.subject_crop_rgb,
        roi_normalized_xywh=base.roi_normalized_xywh,
        roi_mask=base.roi_mask,
        scalar_features=base.scalar_features,
        missing_feature_mask=base.missing_feature_mask,
        intent_features=intent.squeeze(0),
    )


def preprocess_frame_v2(
    pixels: Sequence[object] | Tensor,
    *,
    intent_styles: Sequence[str] | None = None,
    intent_known: bool | None = None,
    width: int | None = None,
    height: int | None = None,
    roi: Sequence[float] | None = None,
    raw_features: Mapping[str, object] | None = None,
    normalized_features: Mapping[str, object] | Sequence[object] | Tensor | None = None,
    missing_features: Sequence[str] = (),
    missing_feature_mask: Sequence[float] | Tensor | None = None,
    orientation: str | None = None,
    mirroring: bool | float | None = None,
    lens: str | int | float | None = None,
    channel_order: str = "BGRA",
) -> SETCompositionNetV2Inputs:
    """Build one model-ready v2 record from a camera frame and an explicit intent.

    ``intent_styles=None`` or ``intent_styles=[]`` is the unknown state and is
    encoded as ``known=0`` with every style flag 0.  ``natural`` is only set when
    explicitly requested.
    """

    base = preprocess_frame(
        pixels,
        width=width,
        height=height,
        roi=roi,
        raw_features=raw_features,
        normalized_features=normalized_features,
        missing_features=missing_features,
        missing_feature_mask=missing_feature_mask,
        orientation=orientation,
        mirroring=mirroring,
        lens=lens,
        channel_order=channel_order,
    )
    intent = encode_intent(intent_styles, known=intent_known)
    return assemble_v2_inputs(base, intent)


__all__ = [
    "INTENT_ORDER",
    "INTENT_STYLE_NAMES",
    "KNOWN_FLAG_INDEX",
    "assemble_v2_inputs",
    "encode_intent",
    "intent_supervision_mask",
    "preprocess_frame_v2",
    "validate_intent_features",
]
