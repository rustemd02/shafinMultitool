"""Deterministic Python preprocessing for the frozen SETCompositionNet-v1 input contract.

The runtime source is a 32BGRA camera buffer.  This module keeps the training
adapter in the same logical top-left RGB/HWC space as ``MetalPreprocessor``:
orientation is applied once, resize uses the runtime pixel-centre formula, and
the padded subject crop is clipped by intersection without shifting.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
import math
from pathlib import Path
from typing import Any

import torch
from torch import Tensor

from ..models.set_composition_net import SETCompositionNetInputs, SETCompositionNetManifest


class PreprocessingError(ValueError):
    """Raised when untrusted source pixels or metadata cannot be admitted."""


_MANIFEST = SETCompositionNetManifest.load()
_FEATURE_NAMES = tuple(_MANIFEST.raw["inputs"]["scalar_features"]["ordered_names"])
_FEATURE_INDEX = {name: index for index, name in enumerate(_FEATURE_NAMES)}
_NORMALIZATION = _MANIFEST.raw["feature_normalization"]
_FEATURE_TO_NORMALIZATION = _NORMALIZATION["feature_to_normalization"]
_ORIENTATION_NAMES = tuple(_MANIFEST.raw["categorical_features"]["orientation_category"]["ordered_names"])
_LENS_NAMES = tuple(_MANIFEST.raw["categorical_features"]["lens_category"]["ordered_names"])
_ORIENTATION_VALUES = tuple(
    _MANIFEST.raw["categorical_features"]["orientation_category"]["allowed_normalized_values"]
)
_LENS_VALUES = tuple(_MANIFEST.raw["categorical_features"]["lens_category"]["allowed_normalized_values"])

_ORIENTATION_ALIASES = {
    "up": "up",
    "upmirrored": "upMirrored",
    "down": "down",
    "downmirrored": "downMirrored",
    "left": "left",
    "leftmirrored": "leftMirrored",
    "right": "right",
    "rightmirrored": "rightMirrored",
}
_MIRRORED_ORIENTATIONS = frozenset({"upMirrored", "downMirrored", "leftMirrored", "rightMirrored"})


def _finite(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _clip(value: float, lower: float, upper: float) -> float:
    return min(upper, max(lower, value))


def _canonical_orientation(value: str | None) -> str:
    if value is None:
        return "up"
    if not isinstance(value, str):
        raise PreprocessingError("orientation must be an ImageIO orientation string")
    key = value.replace("_", "").replace("-", "").lower()
    try:
        return _ORIENTATION_ALIASES[key]
    except KeyError as exc:
        raise PreprocessingError(f"unsupported ImageIO orientation: {value!r}") from exc


def _as_flat_source(
    pixels: Sequence[object] | Tensor,
    width: int | None,
    height: int | None,
    channel_order: str,
) -> tuple[list[int], int, int, int]:
    """Return flat uint8 source pixels and their dimensions.

    Both flat transport bytes and HWC tensors are accepted so callers can use
    camera buffers or compact deterministic fixtures without an adapter class.
    """

    if isinstance(pixels, Tensor):
        if pixels.device.type != "cpu":
            pixels = pixels.detach().cpu()
        if pixels.dtype != torch.uint8 or pixels.ndim != 3 or pixels.shape[2] not in (3, 4):
            raise PreprocessingError("source pixels tensor must be a CPU uint8 HWC RGB/RGBA/BGR/BGRA tensor")
        inferred_height, inferred_width, channels = (int(value) for value in pixels.shape)
        if width is not None and width != inferred_width or height is not None and height != inferred_height:
            raise PreprocessingError("source dimensions disagree with source pixel tensor")
        return [int(value) for value in pixels.reshape(-1).tolist()], inferred_width, inferred_height, channels

    if isinstance(pixels, (bytes, bytearray)):
        values = list(pixels)
        if width is None or height is None:
            raise PreprocessingError("byte source pixels require explicit width and height")
        inferred_width, inferred_height = width, height
    elif not isinstance(pixels, Sequence) or isinstance(pixels, str):
        raise PreprocessingError("source pixels must be a flat sequence or HWC uint8 tensor")
    else:
        values = list(pixels)
    channels = len(channel_order)
    if channels not in (3, 4):
        raise PreprocessingError("source channel order must contain RGB plus optional alpha")
    # Nested HWC/row-major fixtures are convenient and do not change the
    # transport contract; flatten them before validating uint8 values.
    if values and isinstance(values[0], Sequence) and not isinstance(values[0], (str, bytes, bytearray)):
        rows = values
        inferred_height = len(rows)
        if not inferred_height or not isinstance(rows[0], Sequence):
            raise PreprocessingError("nested source pixels must be HWC")
        first_row = list(rows[0])
        if first_row and isinstance(first_row[0], Sequence) and not isinstance(first_row[0], (str, bytes, bytearray)):
            inferred_width = len(first_row)
            flattened: list[object] = []
            for row in rows:
                if not isinstance(row, Sequence) or len(row) != inferred_width:
                    raise PreprocessingError("nested source rows must have equal widths")
                for pixel in row:
                    if not isinstance(pixel, Sequence) or len(pixel) != channels:
                        raise PreprocessingError("nested source pixels must match channel order")
                    flattened.extend(pixel)
            values = flattened
        else:
            values = [item for row in rows for item in row]  # type: ignore[misc]
            if width is None or height is None:
                raise PreprocessingError("flat row pixels require explicit width and height")
            inferred_width, inferred_height = width, height
    elif not isinstance(pixels, (bytes, bytearray)):
        if width is None or height is None:
            raise PreprocessingError("flat source pixels require explicit width and height")
        inferred_width, inferred_height = width, height

    if type(inferred_width) is not int or type(inferred_height) is not int or inferred_width <= 0 or inferred_height <= 0:
        raise PreprocessingError("source width and height must be positive integers")
    expected = inferred_width * inferred_height * channels
    if len(values) != expected:
        raise PreprocessingError(f"source pixel count must be {expected}, got {len(values)}")
    if not all(type(value) is int and 0 <= value <= 255 for value in values):
        raise PreprocessingError("source pixels must be uint8 values in [0, 255]")
    return [int(value) for value in values], inferred_width, inferred_height, channels


def _source_rgb_u8(values: Sequence[int], channels: int, channel_order: str) -> list[float]:
    order = channel_order.upper()
    if len(order) != channels or set(order) not in ({"R", "G", "B"}, {"R", "G", "B", "A"}):
        raise PreprocessingError("source channel order must be RGB/BGR with optional alpha")
    try:
        red, green, blue = (order.index(channel) for channel in "RGB")
    except ValueError as exc:
        raise PreprocessingError("source channel order must contain R, G and B") from exc
    return [float(pixel[channel]) / 255.0 for offset in range(0, len(values), channels) for pixel in [values[offset:offset + channels]] for channel in (red, green, blue)]


def _oriented_rgb(values: Sequence[float], width: int, height: int, orientation: str) -> tuple[list[float], int, int]:
    swaps_axes = orientation in {"leftMirrored", "right", "rightMirrored", "left"}
    oriented_width = height if swaps_axes else width
    oriented_height = width if swaps_axes else height
    output: list[float] = []
    for output_y in range(oriented_height):
        for output_x in range(oriented_width):
            if orientation == "up":
                source_x, source_y = output_x, output_y
            elif orientation == "upMirrored":
                source_x, source_y = width - 1 - output_x, output_y
            elif orientation == "down":
                source_x, source_y = width - 1 - output_x, height - 1 - output_y
            elif orientation == "downMirrored":
                source_x, source_y = output_x, height - 1 - output_y
            elif orientation == "leftMirrored":
                source_x, source_y = output_y, output_x
            elif orientation == "right":
                source_x, source_y = output_y, height - 1 - output_x
            elif orientation == "rightMirrored":
                source_x, source_y = width - 1 - output_y, height - 1 - output_x
            elif orientation == "left":
                source_x, source_y = width - 1 - output_y, output_x
            else:  # pragma: no cover - canonicalization makes this unreachable.
                raise PreprocessingError(f"unsupported orientation {orientation!r}")
            offset = (source_y * width + source_x) * 3
            output.extend(values[offset:offset + 3])
    return output, oriented_width, oriented_height


def _resize(
    source: Sequence[float],
    source_width: int,
    source_height: int,
    target_width: int,
    target_height: int,
    *,
    left: float,
    top: float,
    right: float,
    bottom: float,
) -> list[float]:
    """Mirror Swift's setCompositionNetResize pixel-centre arithmetic."""

    if not all(_finite(value) for value in (left, top, right, bottom)) or right <= left or bottom <= top:
        raise PreprocessingError("resize bounds must be finite and non-degenerate")
    output: list[float] = []
    for target_y in range(target_height):
        source_y = _clip(top + (target_y + 0.5) * (bottom - top) / target_height - 0.5, 0.0, source_height - 1.0)
        y0 = int(source_y)
        y1 = min(y0 + 1, source_height - 1)
        y_weight = source_y - y0
        for target_x in range(target_width):
            source_x = _clip(left + (target_x + 0.5) * (right - left) / target_width - 0.5, 0.0, source_width - 1.0)
            x0 = int(source_x)
            x1 = min(x0 + 1, source_width - 1)
            x_weight = source_x - x0
            for channel in range(3):
                top_left = source[(y0 * source_width + x0) * 3 + channel]
                top_right = source[(y0 * source_width + x1) * 3 + channel]
                bottom_left = source[(y1 * source_width + x0) * 3 + channel]
                bottom_right = source[(y1 * source_width + x1) * 3 + channel]
                top_value = (1.0 - x_weight) * top_left + x_weight * top_right
                bottom_value = (1.0 - x_weight) * bottom_left + x_weight * bottom_right
                output.append((1.0 - y_weight) * top_value + y_weight * bottom_value)
    return output


def _roi_values(roi: Sequence[float] | None) -> tuple[float, float, float, float]:
    if roi is None:
        return 0.0, 0.0, 0.0, 0.0
    if isinstance(roi, Tensor):
        if roi.ndim != 1:
            raise PreprocessingError("ROI must be a vector")
        values = roi.detach().cpu().tolist()
    else:
        values = list(roi)
    if len(values) != 4 or not all(_finite(value) for value in values):
        raise PreprocessingError("ROI must contain four finite normalized values")
    x, y, width, height = (float(value) for value in values)
    if x == y == width == height == 0.0:
        return 0.0, 0.0, 0.0, 0.0
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0 and 0.0 < width <= 1.0 and 0.0 < height <= 1.0):
        raise PreprocessingError("present ROI must be a positive top-left [0, 1] rectangle")
    if x + width > 1.0 or y + height > 1.0:
        raise PreprocessingError("present ROI must remain within the normalized frame")
    return x, y, width, height


def _roi_mask(roi: tuple[float, float, float, float], width: int, height: int) -> list[float]:
    x, y, roi_width, roi_height = roi
    if roi_width == 0.0 or roi_height == 0.0:
        return [0.0] * (width * height)
    return [
        1.0
        if x <= (column + 0.5) / width < x + roi_width
        and y <= (row + 0.5) / height < y + roi_height
        else 0.0
        for row in range(height)
        for column in range(width)
    ]


def _normalized_category(value: object, names: Sequence[str], allowed: Sequence[float], label: str) -> float:
    if isinstance(value, str):
        try:
            return float(allowed[names.index(value)])
        except ValueError as exc:
            raise PreprocessingError(f"{label} is not in its frozen catalog") from exc
    if not _finite(value):
        raise PreprocessingError(f"{label} must be finite or a catalog name")
    numeric = float(value)
    # Raw integer indices follow the manifest's categorical_index formula.
    if numeric.is_integer() and 0.0 <= numeric < len(names):
        return numeric / (len(names) - 1)
    if any(abs(numeric - item) <= 1e-12 for item in allowed):
        return numeric
    raise PreprocessingError(f"{label} is not a valid raw index or normalized catalog value")


def _normalize_feature(name: str, raw: object, *, source_aspect_ratio: float | None = None) -> float:
    kind = _FEATURE_TO_NORMALIZATION[name]
    if kind == "categorical_index":
        if name == "orientation_category":
            return _normalized_category(raw, _ORIENTATION_NAMES, _ORIENTATION_VALUES, name)
        return _normalized_category(raw, _LENS_NAMES, _LENS_VALUES, name)
    if kind == "aspect_ratio":
        if isinstance(raw, Sequence) and not isinstance(raw, (str, bytes, bytearray)):
            dimensions = list(raw)
            if len(dimensions) != 2 or not all(_finite(value) for value in dimensions):
                raise PreprocessingError(f"{name} dimensions must be two finite values")
            width, height = (float(value) for value in dimensions)
            if height <= 0.0:
                raise PreprocessingError(f"{name} height must be positive")
            raw = width / height
        elif raw is None:
            if source_aspect_ratio is None:
                raise PreprocessingError(f"{name} requires a ratio or source dimensions")
            raw = source_aspect_ratio
        if not _finite(raw):
            raise PreprocessingError(f"{name} must be finite")
        return _clip(float(raw), 0.0, 4.0) / 4.0
    if not _finite(raw):
        raise PreprocessingError(f"{name} must be finite")
    numeric = float(raw)
    if kind == "unit_interval":
        return _clip(numeric, 0.0, 1.0)
    if kind == "signed_unit_interval":
        return _clip(numeric, -1.0, 1.0)
    if kind == "count_0_to_8":
        return _clip(numeric, 0.0, 8.0) / 8.0
    if kind == "angle_degrees_to_unit":
        return _clip(numeric / 180.0, -1.0, 1.0)
    raise PreprocessingError(f"unsupported manifest normalization kind: {kind}")


def _missing_indices(
    missing_features: Iterable[str],
    missing_mask: Sequence[float] | Tensor | None,
) -> set[int]:
    missing_names = set(missing_features)
    unknown = missing_names.difference(_FEATURE_INDEX)
    if unknown:
        raise PreprocessingError(f"unknown missing feature names: {sorted(unknown)}")
    indices = {_FEATURE_INDEX[name] for name in missing_names}
    if missing_mask is None:
        return indices
    if isinstance(missing_mask, Tensor):
        if missing_mask.ndim != 1:
            raise PreprocessingError("missing_feature_mask must be a vector")
        values = missing_mask.detach().cpu().tolist()
    else:
        values = list(missing_mask)
    if len(values) != len(_FEATURE_NAMES) or any(not _finite(value) or float(value) not in (0.0, 1.0) for value in values):
        raise PreprocessingError("missing_feature_mask must contain exactly 40 finite 0/1 values")
    indices.update(index for index, value in enumerate(values) if float(value) == 1.0)
    return indices


def normalize_scalar_features(
    raw_features: Mapping[str, object] | None = None,
    *,
    normalized_features: Mapping[str, object] | Sequence[object] | Tensor | None = None,
    roi: Sequence[float] | None = None,
    roi_mask: Sequence[float] | None = None,
    source_aspect_ratio: float | None = None,
    orientation: str | None = None,
    mirroring: bool | float | None = None,
    lens: str | int | float | None = None,
    missing_features: Iterable[str] = (),
    missing_feature_mask: Sequence[float] | Tensor | None = None,
) -> tuple[Tensor, Tensor]:
    """Normalize raw scalar metadata and return ``(values, missing_mask)``.

    Missing entries are filled with the manifest's zero value before any
    reduction.  ROI-derived fields are always made consistent with the
    canonical normalized ROI unless explicitly marked missing.
    """

    if raw_features is not None and normalized_features is not None:
        raise PreprocessingError("pass raw_features or normalized_features, not both")
    raw = dict(raw_features or {})
    normalized_values: list[object] | None
    if normalized_features is None:
        normalized_values = None
    elif isinstance(normalized_features, Mapping):
        unknown = set(normalized_features).difference(_FEATURE_INDEX)
        if unknown:
            raise PreprocessingError(f"unknown normalized feature names: {sorted(unknown)}")
        normalized_values = [normalized_features.get(name) for name in _FEATURE_NAMES]
    elif isinstance(normalized_features, Tensor):
        if normalized_features.ndim != 1:
            raise PreprocessingError("normalized_features must be a vector")
        normalized_values = normalized_features.detach().cpu().tolist()
    else:
        normalized_values = list(normalized_features)
    if normalized_values is not None and len(normalized_values) != len(_FEATURE_NAMES):
        raise PreprocessingError("normalized_features must contain exactly 40 values")
    unknown = set(raw).difference(_FEATURE_INDEX)
    if unknown:
        raise PreprocessingError(f"unknown scalar feature names: {sorted(unknown)}")
    normalized_orientation = _canonical_orientation(orientation) if orientation is not None else None
    if mirroring is not None and type(mirroring) is not bool and (
        not _finite(mirroring) or float(mirroring) not in (0.0, 1.0)
    ):
        raise PreprocessingError("mirroring must be a finite boolean-like value")
    roi_values = _roi_values(roi)
    present = roi is not None and roi_values[2] > 0.0 and roi_values[3] > 0.0
    if isinstance(roi_mask, Tensor):
        if roi_mask.ndim != 1:
            raise PreprocessingError("roi_mask must be a vector")
        mask_values = roi_mask.detach().cpu().tolist()
    else:
        mask_values = list(roi_mask) if roi_mask is not None else None
    expected_mask_count = _MANIFEST.roi_mask_shape[0] * _MANIFEST.roi_mask_shape[1]
    if mask_values is not None and (len(mask_values) != expected_mask_count or any(value not in (0.0, 1.0) for value in mask_values)):
        raise PreprocessingError("roi_mask must contain exactly 320*320 binary values")
    expected_mask = _roi_mask(roi_values, _MANIFEST.roi_mask_shape[1], _MANIFEST.roi_mask_shape[0])
    if mask_values is None:
        mask_values = expected_mask
    elif mask_values != expected_mask:
        raise PreprocessingError("roi_mask does not match normalized ROI pixel-centre rasterization")
    missing = _missing_indices(missing_features, missing_feature_mask)
    values: list[float] = []
    roi_derived = {
        "roi_present": 1.0 if present else 0.0,
        "roi_area_ratio": roi_values[2] * roi_values[3],
        "roi_mask_coverage": sum(float(value) for value in mask_values) / expected_mask_count,
    }
    if normalized_orientation is not None:
        raw["orientation_category"] = _ORIENTATION_NAMES.index(normalized_orientation.replace("Mirrored", ""))
    if mirroring is not None:
        raw["mirroring_flag"] = 1.0 if mirroring else 0.0
    elif normalized_orientation is not None:
        raw["mirroring_flag"] = 1.0 if normalized_orientation in _MIRRORED_ORIENTATIONS else 0.0
    if lens is not None:
        raw["lens_category"] = lens
    for name in _FEATURE_NAMES:
        index = _FEATURE_INDEX[name]
        supplied = normalized_values[index] if normalized_values is not None else raw.get(name)
        if name in roi_derived and index not in missing:
            supplied = roi_derived[name]
        elif name == "orientation_category" and normalized_orientation is not None:
            supplied = _ORIENTATION_VALUES[_ORIENTATION_NAMES.index(normalized_orientation.replace("Mirrored", ""))]
        elif name == "mirroring_flag" and normalized_orientation is not None and mirroring is None:
            supplied = 1.0 if normalized_orientation in _MIRRORED_ORIENTATIONS else 0.0
        elif name == "mirroring_flag" and mirroring is not None:
            supplied = 1.0 if mirroring else 0.0
        elif name == "lens_category" and lens is not None:
            supplied = lens
        elif name == "format_aspect_ratio" and supplied is None and source_aspect_ratio is not None:
            supplied = source_aspect_ratio
        if index in missing or supplied is None:
            values.append(0.0)
            missing.add(index)
            continue
        if name == "orientation_category" and normalized_orientation is not None:
            values.append(float(_ORIENTATION_VALUES[_ORIENTATION_NAMES.index(normalized_orientation.replace("Mirrored", ""))]))
            continue
        if name == "lens_category" and lens is not None:
            values.append(_normalize_feature(name, lens))
            continue
        if normalized_values is not None:
            if not _finite(supplied):
                raise PreprocessingError(f"normalized feature {name} must be finite")
            normalized = float(supplied)
            lower, upper = _NORMALIZATION[_FEATURE_TO_NORMALIZATION[name]]["value_range"]
            if not lower <= normalized <= upper:
                raise PreprocessingError(f"normalized feature {name} is outside its manifest range")
            if name == "orientation_category" and not any(abs(normalized - item) <= 1e-6 for item in _ORIENTATION_VALUES):
                raise PreprocessingError(f"normalized categorical feature {name} is unsupported")
            if name == "lens_category" and not any(abs(normalized - item) <= 1e-6 for item in _LENS_VALUES):
                raise PreprocessingError(f"normalized categorical feature {name} is unsupported")
            values.append(normalized)
        else:
            values.append(_normalize_feature(name, supplied, source_aspect_ratio=source_aspect_ratio))
    return torch.tensor(values, dtype=torch.float32), torch.tensor(
        [1.0 if index in missing else 0.0 for index in range(len(_FEATURE_NAMES))], dtype=torch.float32
    )


def preprocess_frame(
    pixels: Sequence[object] | Tensor,
    *,
    width: int | None = None,
    height: int | None = None,
    roi: Sequence[float] | None = None,
    raw_features: Mapping[str, object] | None = None,
    normalized_features: Mapping[str, object] | Sequence[object] | Tensor | None = None,
    missing_features: Iterable[str] = (),
    missing_feature_mask: Sequence[float] | Tensor | None = None,
    orientation: str | None = None,
    mirroring: bool | float | None = None,
    lens: str | int | float | None = None,
    channel_order: str = "BGRA",
) -> SETCompositionNetInputs:
    """Create model-ready float32 HWC tensors from one camera frame."""

    order = channel_order.upper()
    if order not in {"RGB", "BGR", "RGBA", "BGRA"}:
        raise PreprocessingError("channel_order must be RGB, BGR, RGBA or BGRA")
    source_values, source_width, source_height, channels = _as_flat_source(pixels, width, height, order)
    source_rgb = _source_rgb_u8(source_values, channels, order)
    canonical_orientation = _canonical_orientation(orientation)
    oriented, oriented_width, oriented_height = _oriented_rgb(
        source_rgb, source_width, source_height, canonical_orientation
    )
    full_height, full_width, _ = _MANIFEST.full_frame_shape
    crop_height, crop_width, _ = _MANIFEST.subject_crop_shape
    mask_height, mask_width, _ = _MANIFEST.roi_mask_shape
    full = _resize(
        oriented,
        oriented_width,
        oriented_height,
        full_width,
        full_height,
        left=0.0,
        top=0.0,
        right=float(oriented_width),
        bottom=float(oriented_height),
    )
    roi_values = _roi_values(roi)
    present = roi is not None and roi_values[2] > 0.0 and roi_values[3] > 0.0
    if present:
        x, y, roi_width, roi_height = roi_values
        raw_width = roi_width * oriented_width
        raw_height = roi_height * oriented_height
        side = max(raw_width, raw_height) * 1.25
        center_x = x * oriented_width + raw_width / 2.0
        center_y = y * oriented_height + raw_height / 2.0
        left = max(0.0, center_x - side / 2.0)
        top = max(0.0, center_y - side / 2.0)
        right = min(float(oriented_width), center_x + side / 2.0)
        bottom = min(float(oriented_height), center_y + side / 2.0)
        crop = _resize(
            oriented,
            oriented_width,
            oriented_height,
            crop_width,
            crop_height,
            left=left,
            top=top,
            right=right,
            bottom=bottom,
        )
    else:
        crop = [0.0] * (crop_width * crop_height * 3)
    mask = _roi_mask(roi_values, mask_width, mask_height)
    scalar, missing = normalize_scalar_features(
        raw_features,
        normalized_features=normalized_features,
        roi=roi if present else None,
        roi_mask=mask,
        source_aspect_ratio=source_width / source_height,
        orientation=orientation,
        mirroring=mirroring,
        lens=lens,
        missing_features=missing_features,
        missing_feature_mask=missing_feature_mask,
    )
    return SETCompositionNetInputs(
        torch.tensor(full, dtype=torch.float32).reshape(full_height, full_width, 3),
        torch.tensor(crop, dtype=torch.float32).reshape(crop_height, crop_width, 3),
        torch.tensor(roi_values, dtype=torch.float32),
        torch.tensor(mask, dtype=torch.float32).reshape(mask_height, mask_width, 1),
        scalar,
        missing,
    )


# Keep the canonical owner easy to find for data-loader callers.
preprocess = preprocess_frame
prepare_inputs = preprocess_frame


__all__ = [
    "PreprocessingError",
    "normalize_scalar_features",
    "preprocess",
    "preprocess_frame",
    "prepare_inputs",
]
