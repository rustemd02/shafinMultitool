#!/usr/bin/env python3
"""Validate the frozen SETCompositionNet-v1 manifest and synthetic fixtures.

This is intentionally stdlib-only. It is a contract/parity check, not a model
runner: no dataset, model asset, calibration data, or quality claim is needed.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import struct
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parent
MANIFEST_PATH = ROOT / "set_composition_net_v1.json"
SCHEMA_PATH = ROOT / "set_composition_net_v1.schema.json"
INPUT_FIXTURE_PATH = ROOT / "fixtures" / "set_composition_net_v1_parity.json"
OUTPUT_FIXTURE_PATH = ROOT / "fixtures" / "set_composition_net_v1_output.json"
SWIFT_CONTRACT_PATH = (
    ROOT.parents[2]
    / "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift"
)
SWIFT_PREPROCESSOR_PATH = (
    ROOT.parents[2]
    / "shafinMultitool/Multitool2Module/Utilities/Metal/MetalPreprocessor.swift"
)

EXPECTED_RGB_NORMALIZATION = {
    "source_dtype": "uint8",
    "target_dtype": "float32",
    "source_range": [0, 255],
    "formula": "uint8_channel / 255.0",
    "denominator": 255.0,
    "value_range": [0.0, 1.0],
    "per_channel_offset": [0.0, 0.0, 0.0],
    "per_channel_scale": [0.00392156862745098, 0.00392156862745098, 0.00392156862745098],
}

EXPECTED_SCALAR_NORMALIZATION = {
    "unit_interval": {
        "formula": "clip(raw, 0.0, 1.0)",
        "value_range": [0.0, 1.0],
    },
    "signed_unit_interval": {
        "formula": "clip(raw, -1.0, 1.0)",
        "value_range": [-1.0, 1.0],
    },
    "count_0_to_8": {
        "formula": "clip(raw, 0.0, 8.0) / 8.0",
        "value_range": [0.0, 1.0],
    },
    "angle_degrees_to_unit": {
        "formula": "clip(raw_degrees / 180.0, -1.0, 1.0)",
        "value_range": [-1.0, 1.0],
    },
    "categorical_index": {
        "formula": "index / (category_count - 1)",
        "value_range": [0.0, 1.0],
    },
    "aspect_ratio": {
        "formula": "clip(raw_width / raw_height, 0.0, 4.0) / 4.0",
        "value_range": [0.0, 1.0],
    },
}

EXPECTED_FEATURE_TO_NORMALIZATION = {
    "subject_bbox_x": "unit_interval",
    "subject_bbox_y": "unit_interval",
    "subject_bbox_width": "unit_interval",
    "subject_bbox_height": "unit_interval",
    "subject_area_ratio": "unit_interval",
    "subject_edge_pressure_left": "unit_interval",
    "subject_edge_pressure_right": "unit_interval",
    "subject_edge_pressure_top": "unit_interval",
    "subject_edge_pressure_bottom": "unit_interval",
    "person_count": "count_0_to_8",
    "face_count": "count_0_to_8",
    "group_count": "count_0_to_8",
    "person_confidence": "unit_interval",
    "face_confidence": "unit_interval",
    "group_confidence": "unit_interval",
    "saliency_left_right_balance": "signed_unit_interval",
    "saliency_top_bottom_balance": "signed_unit_interval",
    "saliency_subject_mean": "unit_interval",
    "saliency_background_mean": "unit_interval",
    "saliency_subject_background_delta": "signed_unit_interval",
    "horizon_angle": "angle_degrees_to_unit",
    "horizon_confidence": "unit_interval",
    "subject_mean_luma": "unit_interval",
    "background_mean_luma": "unit_interval",
    "subject_luma_delta": "signed_unit_interval",
    "subject_clipped_ratio": "unit_interval",
    "background_hotspot_ratio": "unit_interval",
    "motion_shake": "unit_interval",
    "motion_stability": "unit_interval",
    "focus_readability": "unit_interval",
    "focus_confidence": "unit_interval",
    "orientation_category": "categorical_index",
    "mirroring_flag": "unit_interval",
    "lens_category": "categorical_index",
    "format_aspect_ratio": "aspect_ratio",
    "roi_present": "unit_interval",
    "roi_area_ratio": "unit_interval",
    "roi_mask_coverage": "unit_interval",
    "subject_separation": "unit_interval",
    "camera_exposure_bias": "signed_unit_interval",
}


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise AssertionError(f"{path} must contain a JSON object")
    return value


def assert_exact_keys(value: object, expected: set[str], label: str) -> dict:
    assert isinstance(value, dict), f"{label} must be an object"
    assert set(value) == expected, (label, sorted(value), sorted(expected))
    return value


def assert_closed_schema_object(value: object, expected: set[str], label: str) -> dict:
    node = assert_exact_keys(value, {"type", "required", "properties", "additionalProperties"}, label)
    assert node["type"] == "object"
    assert node["additionalProperties"] is False
    assert isinstance(node["required"], list)
    assert len(node["required"]) == len(expected)
    assert set(node["required"]) == expected
    assert_exact_keys(node["properties"], expected, f"{label}.properties")
    return node


def packed_hash(values: list[float]) -> str:
    packed = struct.pack(f"<{len(values)}f", *values)
    return hashlib.sha256(packed).hexdigest()


def swift_string_array(source: str, declaration: str) -> list[str]:
    match = re.search(
        rf"static let {re.escape(declaration)} = \[(.*?)\]",
        source,
        flags=re.DOTALL,
    )
    assert match, f"Swift contract declaration not found: {declaration}"
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))


def swift_enum_raw_values(source: str, enum_name: str) -> list[str]:
    match = re.search(
        rf"enum {re.escape(enum_name)}:[^{{]+\{{(.*?)\n\}}",
        source,
        flags=re.DOTALL,
    )
    assert match, f"Swift enum not found: {enum_name}"
    return re.findall(r'case \w+ = "([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))


def swift_int_constant(source: str, declaration: str) -> int:
    match = re.search(rf"static let {re.escape(declaration)} = (\d+)", source)
    assert match, f"Swift contract declaration not found: {declaration}"
    return int(match.group(1))


def swift_string_constant(source: str, declaration: str) -> str:
    match = re.search(rf'static let {re.escape(declaration)} = "([^"\\]*)"', source)
    assert match, f"Swift contract declaration not found: {declaration}"
    return match.group(1)


def swift_number_constant(source: str, declaration: str) -> float:
    match = re.search(rf"static let {re.escape(declaration)} = (-?\d+(?:\.\d+)?)", source)
    assert match, f"Swift contract declaration not found: {declaration}"
    return float(match.group(1))


def swift_number_array(source: str, declaration: str) -> list[float]:
    match = re.search(
        rf"static let {re.escape(declaration)} = \[(.*?)\]",
        source,
        flags=re.DOTALL,
    )
    assert match, f"Swift contract declaration not found: {declaration}"
    return [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", match.group(1))]


def finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def bilinear_resize(source: list[float], width: int, height: int,
                    target_width: int, target_height: int) -> list[float]:
    output: list[float] = []
    for target_y in range(target_height):
        source_y = (target_y + 0.5) * height / target_height - 0.5
        source_y = max(0.0, min(height - 1.0, source_y))
        y0 = int(source_y)
        y1 = min(y0 + 1, height - 1)
        y_weight = source_y - y0
        for target_x in range(target_width):
            source_x = (target_x + 0.5) * width / target_width - 0.5
            source_x = max(0.0, min(width - 1.0, source_x))
            x0 = int(source_x)
            x1 = min(x0 + 1, width - 1)
            x_weight = source_x - x0
            for channel in range(3):
                top_left = source[(y0 * width + x0) * 3 + channel]
                top_right = source[(y0 * width + x1) * 3 + channel]
                bottom_left = source[(y1 * width + x0) * 3 + channel]
                bottom_right = source[(y1 * width + x1) * 3 + channel]
                top = (1.0 - x_weight) * top_left + x_weight * top_right
                bottom = (1.0 - x_weight) * bottom_left + x_weight * bottom_right
                output.append((1.0 - y_weight) * top + y_weight * bottom)
    return output


def square_crop(source: list[float], width: int, height: int,
                roi: list[float], target_width: int,
                target_height: int) -> list[float]:
    x, y, roi_width, roi_height = roi
    raw_x = x * width
    raw_y = y * height
    raw_width = roi_width * width
    raw_height = roi_height * height
    side = max(raw_width, raw_height) * 1.25
    # Intersect the raw padded square with frame bounds. Do not derive the
    # far edge from a clipped near edge: that would shift the crop toward the
    # frame interior and disagree with the production preprocessor.
    raw_left = raw_x + raw_width / 2.0 - side / 2.0
    raw_top = raw_y + raw_height / 2.0 - side / 2.0
    raw_right = raw_x + raw_width / 2.0 + side / 2.0
    raw_bottom = raw_y + raw_height / 2.0 + side / 2.0
    left = max(0.0, raw_left)
    top = max(0.0, raw_top)
    right = min(float(width), raw_right)
    bottom = min(float(height), raw_bottom)
    assert right > left and bottom > top

    output: list[float] = []
    for target_y in range(target_height):
        source_y = top + (target_y + 0.5) * (bottom - top) / target_height - 0.5
        source_y = max(0.0, min(height - 1.0, source_y))
        y0 = int(source_y)
        y1 = min(y0 + 1, height - 1)
        y_weight = source_y - y0
        for target_x in range(target_width):
            source_x = left + (target_x + 0.5) * (right - left) / target_width - 0.5
            source_x = max(0.0, min(width - 1.0, source_x))
            x0 = int(source_x)
            x1 = min(x0 + 1, width - 1)
            x_weight = source_x - x0
            for channel in range(3):
                top_left = source[(y0 * width + x0) * 3 + channel]
                top_right = source[(y0 * width + x1) * 3 + channel]
                bottom_left = source[(y1 * width + x0) * 3 + channel]
                bottom_right = source[(y1 * width + x1) * 3 + channel]
                top_value = (1.0 - x_weight) * top_left + x_weight * top_right
                bottom_value = (1.0 - x_weight) * bottom_left + x_weight * bottom_right
                output.append((1.0 - y_weight) * top_value + y_weight * bottom_value)
    return output


def normalized_mask(roi: list[float], width: int, height: int) -> list[float]:
    x, y, roi_width, roi_height = roi
    return [
        1.0 if x <= (column + 0.5) / width < x + roi_width
        and y <= (row + 0.5) / height < y + roi_height else 0.0
        for row in range(height)
        for column in range(width)
    ]


def pixel_at(values: list[float], width: int, x: int, y: int) -> list[float]:
    offset = (y * width + x) * 3
    return values[offset:offset + 3]


def validate_scalar_features(manifest: dict, scalar: object, missing: object,
                             roi: list[float], mask: list[float], tolerance: float) -> None:
    names = manifest["inputs"]["scalar_features"]["ordered_names"]
    assert isinstance(scalar, list) and isinstance(missing, list)
    assert len(scalar) == len(missing) == len(names)
    assert all(finite_number(value) for value in scalar)
    assert all(finite_number(value) and value in (0.0, 1.0) for value in missing)
    normalization = manifest["feature_normalization"]["feature_to_normalization"]
    ranges = manifest["feature_normalization"]
    categorical_values = {
        "orientation_category": manifest["categorical_features"]["orientation_category"]["allowed_normalized_values"],
        "lens_category": manifest["categorical_features"]["lens_category"]["allowed_normalized_values"],
    }
    for name, value, missing_value in zip(names, scalar, missing):
        lower, upper = ranges[normalization[name]]["value_range"]
        assert lower <= value <= upper, (name, value, lower, upper)
        if name in categorical_values:
            assert any(abs(value - allowed) <= tolerance for allowed in categorical_values[name]), (
                name, value, categorical_values[name]
            )
        if missing_value == 1.0:
            assert value == manifest["inputs"]["scalar_features"]["missing_mask"]["fill_value"]

    expected_roi_scalars = {
        "roi_present": 1.0,
        "roi_area_ratio": roi[2] * roi[3],
        "roi_mask_coverage": sum(mask) / len(mask),
    }
    indexes = {name: index for index, name in enumerate(names)}
    for name, expected in expected_roi_scalars.items():
        index = indexes[name]
        if missing[index] == 0.0:
            assert abs(scalar[index] - expected) <= tolerance, (name, scalar[index], expected)


def validate_manifest(manifest: dict, schema: dict) -> None:
    manifest_required_order = [
        "contract_id",
        "contract_version",
        "input_contract_version",
        "preprocessing_version",
        "feature_version",
        "output_contract_version",
        "tensor_layout",
        "inputs",
        "preprocessing",
        "categorical_features",
        "feature_normalization",
        "outputs",
    ]
    manifest_keys = set(manifest_required_order)
    manifest = assert_exact_keys(manifest, manifest_keys, "manifest")
    schema = assert_exact_keys(
        schema,
        {"$schema", "$id", "title", "type", "required", "properties", "$defs", "additionalProperties"},
        "schema",
    )
    assert schema["type"] == "object"
    assert schema["additionalProperties"] is False
    assert schema["required"] == manifest_required_order
    assert_exact_keys(schema["properties"], manifest_keys, "schema.properties")
    assert set(schema["$defs"]) == {
        "rgbTensor", "binaryTensor", "orientationCatalog", "lensCatalog", "headBase",
        "headScene", "headSubjectness", "headIssues", "headActions", "headGoodFrame",
        "headAbstention", "headRisk", "headDeltas", "headEmbedding",
    }
    assert schema["properties"]["contract_id"]["const"] == manifest["contract_id"]
    assert schema["properties"]["contract_version"]["const"] == manifest["contract_version"]
    assert schema["properties"]["input_contract_version"]["const"] == manifest["input_contract_version"]
    assert schema["properties"]["preprocessing_version"]["const"] == manifest["preprocessing_version"]
    assert schema["properties"]["feature_version"]["const"] == manifest["feature_version"]
    assert schema["properties"]["output_contract_version"]["const"] == manifest["output_contract_version"]

    assert manifest["tensor_layout"] == "HWC"
    input_keys = {
        "full_frame_rgb", "subject_crop_rgb", "roi_normalized_xywh", "roi_mask", "scalar_features"
    }
    inputs = assert_exact_keys(manifest["inputs"], input_keys, "inputs")

    def tensor(name: str, shape: list[int], *, binary: bool = False) -> dict:
        expected_keys = {"dtype", "shape", "value_range", "values", "rasterization", "missing_value"} if binary else {
            "dtype", "shape", "channel_order", "value_range"
        }
        value = assert_exact_keys(inputs[name], expected_keys, f"inputs.{name}")
        assert value["dtype"] == "float32"
        assert value["shape"] == shape
        assert value["value_range"] == [0.0, 1.0]
        if binary:
            assert value["values"] == [0.0, 1.0]
            assert value["missing_value"] == 0.0
        else:
            assert value["channel_order"] == ["R", "G", "B"]
        return value

    tensor("full_frame_rgb", [320, 320, 3])
    tensor("subject_crop_rgb", [192, 192, 3])
    tensor("roi_mask", [320, 320, 1], binary=True)

    roi = assert_exact_keys(
        inputs["roi_normalized_xywh"],
        {"dtype", "shape", "ordered_names", "coordinate_space", "origin", "axis_direction", "value_range", "bounds", "missing_value"},
        "inputs.roi_normalized_xywh",
    )
    assert roi["dtype"] == "float32"
    assert roi["shape"] == [4]
    assert roi["ordered_names"] == ["x", "y", "width", "height"]
    assert roi["coordinate_space"] == "oriented_full_frame"
    assert roi["origin"] == "top_left"
    assert roi["axis_direction"] == ["right", "down"]
    assert roi["value_range"] == [0.0, 1.0]
    assert roi["bounds"] == ["x + width <= 1.0", "y + height <= 1.0"]
    assert roi["missing_value"] == [0.0, 0.0, 0.0, 0.0]

    scalar = assert_exact_keys(
        inputs["scalar_features"],
        {"dtype", "shape", "count", "ordered_names", "missing_mask"},
        "inputs.scalar_features",
    )
    names = scalar["ordered_names"]
    assert scalar["dtype"] == "float32"
    assert scalar["shape"] == [40]
    assert scalar["count"] == len(names) == 40
    missing_mask = assert_exact_keys(
        scalar["missing_mask"],
        {"dtype", "shape", "ordered_names", "values", "fill_value", "semantics"},
        "inputs.scalar_features.missing_mask",
    )
    assert missing_mask["dtype"] == "float32"
    assert missing_mask["shape"] == [len(names)]
    assert missing_mask["ordered_names"] == "same_as_scalar_features"
    assert missing_mask["values"] == [0.0, 1.0]
    assert missing_mask["fill_value"] == 0.0

    categorical = assert_exact_keys(
        manifest["categorical_features"],
        {"orientation_category", "lens_category"},
        "categorical_features",
    )
    assert_exact_keys(
        categorical["orientation_category"],
        {"count", "ordered_names", "allowed_normalized_values", "index_semantics"},
        "categorical_features.orientation_category",
    )
    assert_exact_keys(
        categorical["lens_category"],
        {"count", "ordered_names", "allowed_normalized_values", "index_semantics"},
        "categorical_features.lens_category",
    )
    assert categorical["orientation_category"]["count"] == 4
    assert categorical["orientation_category"]["ordered_names"] == [
        "up", "right", "down", "left"
    ]
    assert categorical["orientation_category"]["allowed_normalized_values"] == [
        0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0
    ]
    assert categorical["lens_category"]["count"] == 3
    assert categorical["lens_category"]["ordered_names"] == ["ultra_wide", "wide", "tele"]
    assert categorical["lens_category"]["allowed_normalized_values"] == [0.0, 0.5, 1.0]
    assert len(categorical["orientation_category"]["ordered_names"]) == categorical["orientation_category"]["count"]
    assert len(categorical["lens_category"]["ordered_names"]) == categorical["lens_category"]["count"]
    assert len(categorical["orientation_category"]["allowed_normalized_values"]) == categorical["orientation_category"]["count"]
    assert len(categorical["lens_category"]["allowed_normalized_values"]) == categorical["lens_category"]["count"]

    normalization = assert_exact_keys(
        manifest["feature_normalization"],
        {"unit_interval", "signed_unit_interval", "count_0_to_8", "angle_degrees_to_unit", "categorical_index", "aspect_ratio", "feature_to_normalization"},
        "feature_normalization",
    )
    for normalization_name in EXPECTED_SCALAR_NORMALIZATION:
        assert_exact_keys(
            normalization[normalization_name],
            {"formula", "value_range"},
            f"feature_normalization.{normalization_name}",
        )
    feature_to_normalization = assert_exact_keys(
        normalization["feature_to_normalization"],
        set(names),
        "feature_normalization.feature_to_normalization",
    )
    assert list(feature_to_normalization) == names
    assert feature_to_normalization == EXPECTED_FEATURE_TO_NORMALIZATION
    assert list(EXPECTED_FEATURE_TO_NORMALIZATION) == names
    for normalization_name, expected_spec in EXPECTED_SCALAR_NORMALIZATION.items():
        assert normalization[normalization_name]["formula"] == expected_spec["formula"]
        assert normalization[normalization_name]["value_range"] == expected_spec["value_range"]
    preprocessing = assert_exact_keys(
        manifest["preprocessing"],
        {"source_color_space", "source_pixel_format", "model_channel_order", "alpha", "orientation", "mirroring", "resize_interpolation", "resize_geometry", "normalization", "subject_crop"},
        "preprocessing",
    )
    assert_exact_keys(
        preprocessing["normalization"],
        {"source_dtype", "target_dtype", "source_range", "formula", "denominator", "value_range", "per_channel_offset", "per_channel_scale"},
        "preprocessing.normalization",
    )
    assert_exact_keys(
        preprocessing["subject_crop"],
        {"recipe_version", "square_side", "clipping", "missing_crop"},
        "preprocessing.subject_crop",
    )
    assert preprocessing["source_color_space"] == "sRGB"
    assert preprocessing["source_pixel_format"] == "32BGRA"
    assert preprocessing["model_channel_order"] == ["R", "G", "B"]
    assert preprocessing["alpha"] == "discard"
    assert preprocessing["orientation"].startswith("apply the ImageIO orientation exactly once")
    assert "no additional mirror" in preprocessing["mirroring"]
    assert preprocessing["resize_interpolation"] == "bilinear"
    assert preprocessing["resize_geometry"] == "independent_scale_to_target"
    assert preprocessing["normalization"] == EXPECTED_RGB_NORMALIZATION
    assert all(type(value) is int for value in preprocessing["normalization"]["source_range"])
    assert type(preprocessing["normalization"]["denominator"]) is float
    assert all(type(value) is float for value in preprocessing["normalization"]["per_channel_scale"])
    assert preprocessing["subject_crop"]["recipe_version"] == "square_expand_1.25.v1"
    assert "clip padded square to oriented full-frame bounds" in preprocessing["subject_crop"]["clipping"]
    assert "derive raw padded square bounds first" in preprocessing["subject_crop"]["clipping"]
    assert "intersection without shifting" in preprocessing["subject_crop"]["clipping"]
    assert preprocessing["subject_crop"]["missing_crop"] == "zero-filled 192x192x3 tensor"

    outputs = assert_exact_keys(
        manifest["outputs"],
        {"head_order", "heads", "forbidden_outputs"},
        "outputs",
    )
    head_order = outputs["head_order"]
    heads = outputs["heads"]
    assert isinstance(head_order, list)
    assert isinstance(heads, list)
    expected_shapes = {
        "scene_class_logits": 8,
        "subjectness_roi_agreement_logits": 3,
        "issue_logits": 8,
        "action_utility_logits": 26,
        "good_frame_probability": 1,
        "abstention_probability": 1,
        "risk_probability": 1,
        "continuous_target_deltas": 5,
        "embedding": 128,
    }
    assert head_order == list(expected_shapes)
    assert len(head_order) == len(heads) == 9
    assert [head["name"] for head in heads] == head_order
    assert len(set(head_order)) == len(head_order) == 9
    assert outputs["forbidden_outputs"] == ["generated_text", "arbitrary_object_name"]
    head_key_sets = {
        "scene_class_logits": {"name", "dtype", "shape", "ordered_names", "value_semantics"},
        "subjectness_roi_agreement_logits": {"name", "dtype", "shape", "ordered_names", "value_semantics"},
        "issue_logits": {"name", "dtype", "shape", "ordered_names", "value_semantics"},
        "action_utility_logits": {"name", "dtype", "shape", "ordered_names", "catalog_version", "catalog_source", "value_semantics"},
        "good_frame_probability": {"name", "dtype", "shape", "value_range"},
        "abstention_probability": {"name", "dtype", "shape", "value_range"},
        "risk_probability": {"name", "dtype", "shape", "value_range"},
        "continuous_target_deltas": {"name", "dtype", "shape", "ordered_names", "value_range", "value_semantics"},
        "embedding": {"name", "dtype", "shape", "value_semantics"},
    }
    for index, head in enumerate(heads):
        assert isinstance(head, dict)
        assert head.get("name") in head_key_sets
        head = assert_exact_keys(head, head_key_sets[head["name"]], f"outputs.heads[{index}]")
        name = head["name"]
        assert head["dtype"] == "float32"
        assert head["shape"] == [expected_shapes[name]]
        if name in {"scene_class_logits", "subjectness_roi_agreement_logits", "issue_logits"}:
            assert len(head["ordered_names"]) == expected_shapes[name]
        if name == "action_utility_logits":
            assert head["catalog_version"] == 2
            assert head["catalog_source"] == "CameraCoachContractV2.production.approvedActionIDs"
            assert "move_frame_" not in " ".join(head["ordered_names"])
            assert "change_angle" not in head["ordered_names"]
        if name in {"good_frame_probability", "abstention_probability", "risk_probability"}:
            assert head["value_range"] == [0.0, 1.0]
        if name == "continuous_target_deltas":
            assert head["value_range"] == [-1.0, 1.0]
            assert len(head["ordered_names"]) == expected_shapes[name]

    # Validate nested schema constants as well as the manifest's top-level
    # version constants. A paired manifest/schema edit must still fail if the
    # runtime's frozen version, shape, range, or catalog is unchanged.
    schema_inputs_node = assert_closed_schema_object(schema["properties"]["inputs"], input_keys, "schema.inputs")
    schema_inputs = schema_inputs_node["properties"]
    assert_closed_schema_object(
        schema_inputs["roi_normalized_xywh"],
        {"dtype", "shape", "ordered_names", "coordinate_space", "origin", "axis_direction", "value_range", "bounds", "missing_value"},
        "schema.inputs.roi_normalized_xywh",
    )
    schema_scalar_node = assert_closed_schema_object(
        schema_inputs["scalar_features"],
        {"dtype", "shape", "count", "ordered_names", "missing_mask"},
        "schema.inputs.scalar_features",
    )
    assert_closed_schema_object(
        schema_scalar_node["properties"]["missing_mask"],
        {"dtype", "shape", "ordered_names", "values", "fill_value", "semantics"},
        "schema.inputs.scalar_features.missing_mask",
    )
    assert_closed_schema_object(schema["$defs"]["rgbTensor"], {"dtype", "shape", "channel_order", "value_range"}, "schema.$defs.rgbTensor")
    assert_closed_schema_object(schema["$defs"]["binaryTensor"], {"dtype", "shape", "value_range", "values", "rasterization", "missing_value"}, "schema.$defs.binaryTensor")
    assert_closed_schema_object(schema["$defs"]["headBase"], {"name", "dtype", "shape"}, "schema.$defs.headBase")
    for input_name, expected_shape in {
        "full_frame_rgb": [320, 320, 3],
        "subject_crop_rgb": [192, 192, 3],
        "roi_mask": [320, 320, 1],
        "roi_normalized_xywh": [4],
        "scalar_features": [40],
    }.items():
        assert schema_inputs[input_name]["properties"]["shape"]["const"] == expected_shape
    schema_rgb = schema["$defs"]["rgbTensor"]["properties"]
    assert schema_rgb["channel_order"]["const"] == ["R", "G", "B"]
    assert schema_rgb["value_range"]["const"] == [0.0, 1.0]
    schema_binary = schema["$defs"]["binaryTensor"]["properties"]
    assert schema_binary["values"]["const"] == [0.0, 1.0]
    assert schema_binary["missing_value"]["const"] == 0.0
    assert schema_inputs["roi_normalized_xywh"]["properties"]["ordered_names"]["const"] == [
        "x", "y", "width", "height"
    ]
    assert schema_inputs["roi_normalized_xywh"]["properties"]["coordinate_space"]["const"] == "oriented_full_frame"
    assert schema_inputs["roi_normalized_xywh"]["properties"]["origin"]["const"] == "top_left"
    assert schema_inputs["roi_normalized_xywh"]["properties"]["axis_direction"]["const"] == ["right", "down"]
    assert schema_inputs["roi_normalized_xywh"]["properties"]["value_range"]["const"] == [0.0, 1.0]
    assert schema_inputs["roi_normalized_xywh"]["properties"]["missing_value"]["const"] == [0.0, 0.0, 0.0, 0.0]
    assert schema_inputs["scalar_features"]["properties"]["ordered_names"]["const"] == names
    assert schema_inputs["scalar_features"]["properties"]["missing_mask"]["properties"]["shape"]["const"] == [40]
    assert schema_inputs["scalar_features"]["properties"]["missing_mask"]["properties"]["ordered_names"]["const"] == "same_as_scalar_features"
    assert schema_inputs["scalar_features"]["properties"]["missing_mask"]["properties"]["values"]["const"] == [0.0, 1.0]
    assert schema_inputs["scalar_features"]["properties"]["missing_mask"]["properties"]["fill_value"]["const"] == 0.0

    schema_preprocessing_node = assert_closed_schema_object(
        schema["properties"]["preprocessing"],
        {"source_color_space", "source_pixel_format", "model_channel_order", "alpha", "orientation", "mirroring", "resize_interpolation", "resize_geometry", "normalization", "subject_crop"},
        "schema.preprocessing",
    )
    schema_preprocessing = schema_preprocessing_node["properties"]
    assert_closed_schema_object(
        schema_preprocessing["normalization"],
        {"source_dtype", "target_dtype", "source_range", "formula", "denominator", "value_range", "per_channel_offset", "per_channel_scale"},
        "schema.preprocessing.normalization",
    )
    assert_closed_schema_object(
        schema_preprocessing["subject_crop"],
        {"recipe_version", "square_side", "clipping", "missing_crop"},
        "schema.preprocessing.subject_crop",
    )
    assert schema_preprocessing["source_color_space"]["const"] == preprocessing["source_color_space"]
    assert schema_preprocessing["source_pixel_format"]["const"] == preprocessing["source_pixel_format"]
    assert schema_preprocessing["model_channel_order"]["const"] == preprocessing["model_channel_order"]
    assert schema_preprocessing["alpha"]["const"] == preprocessing["alpha"]
    assert schema_preprocessing["resize_interpolation"]["const"] == preprocessing["resize_interpolation"]
    assert schema_preprocessing["resize_geometry"]["const"] == preprocessing["resize_geometry"]
    schema_normalization = schema_preprocessing["normalization"]["properties"]
    assert schema_normalization["source_dtype"]["const"] == preprocessing["normalization"]["source_dtype"]
    assert schema_normalization["target_dtype"]["const"] == preprocessing["normalization"]["target_dtype"]
    assert schema_normalization["source_range"]["const"] == preprocessing["normalization"]["source_range"]
    assert schema_normalization["formula"]["const"] == preprocessing["normalization"]["formula"]
    assert schema_normalization["denominator"]["const"] == preprocessing["normalization"]["denominator"]
    assert schema_normalization["value_range"]["const"] == preprocessing["normalization"]["value_range"]
    assert schema_normalization["per_channel_offset"]["const"] == preprocessing["normalization"]["per_channel_offset"]
    assert schema_normalization["per_channel_scale"]["const"] == preprocessing["normalization"]["per_channel_scale"]
    assert all(type(value) is int for value in schema_normalization["source_range"]["const"])
    assert type(schema_normalization["denominator"]["const"]) is float
    assert all(type(value) is float for value in schema_normalization["per_channel_scale"]["const"])
    assert abs(
        1.0 / preprocessing["normalization"]["denominator"]
        - preprocessing["normalization"]["per_channel_scale"][0]
    ) <= 1e-15
    assert all(
        scale == preprocessing["normalization"]["per_channel_scale"][0]
        for scale in preprocessing["normalization"]["per_channel_scale"]
    )
    schema_crop = schema_preprocessing["subject_crop"]["properties"]
    assert schema_crop["recipe_version"]["const"] == preprocessing["subject_crop"]["recipe_version"]
    assert schema_crop["square_side"]["const"] == preprocessing["subject_crop"]["square_side"]
    assert schema_crop["clipping"]["pattern"] == "derive raw padded square bounds first.*clip padded square to oriented full-frame bounds.*intersection without shifting"
    assert schema_crop["missing_crop"]["const"] == preprocessing["subject_crop"]["missing_crop"]

    assert_closed_schema_object(
        schema["properties"]["categorical_features"],
        {"orientation_category", "lens_category"},
        "schema.categorical_features",
    )
    assert_closed_schema_object(
        schema["$defs"]["orientationCatalog"],
        {"count", "ordered_names", "allowed_normalized_values", "index_semantics"},
        "schema.$defs.orientationCatalog",
    )
    assert_closed_schema_object(
        schema["$defs"]["lensCatalog"],
        {"count", "ordered_names", "allowed_normalized_values", "index_semantics"},
        "schema.$defs.lensCatalog",
    )
    schema_orientation = schema["$defs"]["orientationCatalog"]["properties"]
    schema_lens = schema["$defs"]["lensCatalog"]["properties"]
    assert schema_orientation["count"]["const"] == categorical["orientation_category"]["count"]
    assert schema_orientation["ordered_names"]["const"] == categorical["orientation_category"]["ordered_names"]
    assert schema_orientation["allowed_normalized_values"]["const"] == categorical["orientation_category"]["allowed_normalized_values"]
    assert schema_lens["count"]["const"] == categorical["lens_category"]["count"]
    assert schema_lens["ordered_names"]["const"] == categorical["lens_category"]["ordered_names"]
    assert schema_lens["allowed_normalized_values"]["const"] == categorical["lens_category"]["allowed_normalized_values"]

    schema_feature_node = assert_closed_schema_object(
        schema["properties"]["feature_normalization"],
        {"unit_interval", "signed_unit_interval", "count_0_to_8", "angle_degrees_to_unit", "categorical_index", "aspect_ratio", "feature_to_normalization"},
        "schema.feature_normalization",
    )
    schema_ranges = schema_feature_node["properties"]
    for normalization_name, expected_spec in EXPECTED_SCALAR_NORMALIZATION.items():
        assert_closed_schema_object(
            schema_ranges[normalization_name],
            {"formula", "value_range"},
            f"schema.feature_normalization.{normalization_name}",
        )
        assert schema_ranges[normalization_name]["properties"]["formula"]["const"] == expected_spec["formula"]
        assert schema_ranges[normalization_name]["properties"]["value_range"]["const"] == expected_spec["value_range"]
    assert_exact_keys(
        schema_ranges["feature_to_normalization"],
        {"type", "const"},
        "schema.feature_normalization.feature_to_normalization",
    )
    assert schema_ranges["feature_to_normalization"]["const"] == EXPECTED_FEATURE_TO_NORMALIZATION

    schema_outputs_node = assert_closed_schema_object(
        schema["properties"]["outputs"],
        {"head_order", "heads", "forbidden_outputs"},
        "schema.outputs",
    )
    schema_outputs = schema_outputs_node["properties"]
    assert_exact_keys(
        schema_outputs["head_order"],
        {"type", "const", "minItems", "maxItems", "uniqueItems", "items"},
        "schema.outputs.head_order",
    )
    assert_exact_keys(
        schema_outputs["heads"],
        {"type", "minItems", "maxItems", "prefixItems", "items"},
        "schema.outputs.heads",
    )
    assert_exact_keys(
        schema_outputs["forbidden_outputs"],
        {"type", "const", "minItems", "maxItems", "uniqueItems", "items"},
        "schema.outputs.forbidden_outputs",
    )
    assert schema_outputs["head_order"]["const"] == head_order
    assert schema_outputs["head_order"]["minItems"] == 9
    assert schema_outputs["head_order"]["maxItems"] == 9
    assert schema_outputs["heads"]["minItems"] == 9
    assert schema_outputs["heads"]["maxItems"] == 9
    assert schema_outputs["heads"]["items"] is False
    assert schema_outputs["forbidden_outputs"]["const"] == outputs["forbidden_outputs"]

    schema_head_defs = {
        "scene_class_logits": "headScene",
        "subjectness_roi_agreement_logits": "headSubjectness",
        "issue_logits": "headIssues",
        "action_utility_logits": "headActions",
        "good_frame_probability": "headGoodFrame",
        "abstention_probability": "headAbstention",
        "risk_probability": "headRisk",
        "continuous_target_deltas": "headDeltas",
        "embedding": "headEmbedding",
    }
    expected_prefix_refs = [{"$ref": f"#/$defs/{definition}"} for definition in schema_head_defs.values()]
    assert schema_outputs["heads"]["prefixItems"] == expected_prefix_refs
    for head_name, definition in schema_head_defs.items():
        schema_head = assert_closed_schema_object(
            schema["$defs"][definition],
            head_key_sets[head_name],
            f"schema.$defs.{definition}",
        )
        schema_head_properties = schema_head["properties"]
        manifest_head = next(head for head in heads if head["name"] == head_name)
        for key, value in manifest_head.items():
            assert schema_head_properties[key]["const"] == value

    # The Swift runtime intentionally has no build-time codegen dependency.
    # Keep the checked manifest canonical by comparing its ordered catalogs to
    # the runtime declarations on every deterministic parity run.
    swift_source = SWIFT_CONTRACT_PATH.read_text(encoding="utf-8")
    swift_preprocessor_source = SWIFT_PREPROCESSOR_PATH.read_text(encoding="utf-8")
    swift_heads = swift_string_array(swift_source, "outputHeadNames")
    swift_features = swift_string_array(swift_source, "featureNames")
    swift_scene = swift_string_array(swift_source, "sceneClassNames")
    swift_subjectness = swift_string_array(swift_source, "subjectnessROIAgreementNames")
    swift_targets = swift_string_array(swift_source, "targetDeltaNames")
    swift_orientation = swift_string_array(swift_source, "orientationCategoryNames")
    swift_lenses = swift_string_array(swift_source, "lensCategoryNames")
    swift_orientation_values = swift_number_array(swift_source, "orientationCategoryNormalizedValues")
    swift_lens_values = swift_number_array(swift_source, "lensCategoryNormalizedValues")
    swift_signed_features = swift_string_array(swift_source, "signedFeatureNames")
    swift_issues = swift_enum_raw_values(swift_source, "IssueTypeV1")
    swift_actions = swift_enum_raw_values(swift_source, "SemanticActionType")

    assert swift_heads == head_order
    assert swift_features == manifest["inputs"]["scalar_features"]["ordered_names"]
    assert swift_int_constant(swift_source, "fullFrameWidth") == 320
    assert swift_int_constant(swift_source, "fullFrameHeight") == 320
    assert swift_int_constant(swift_source, "subjectCropWidth") == 192
    assert swift_int_constant(swift_source, "subjectCropHeight") == 192
    assert swift_int_constant(swift_source, "roiMaskWidth") == 320
    assert swift_int_constant(swift_source, "roiMaskHeight") == 320
    assert swift_int_constant(swift_source, "scalarFeatureCount") == 40
    assert swift_int_constant(swift_source, "embeddingDimension") == 128
    assert swift_orientation == categorical["orientation_category"]["ordered_names"]
    assert swift_lenses == categorical["lens_category"]["ordered_names"]
    assert len(swift_orientation_values) == categorical["orientation_category"]["count"]
    assert len(swift_lens_values) == categorical["lens_category"]["count"]
    assert all(
        abs(actual - expected) <= 1e-12
        for actual, expected in zip(
            swift_orientation_values,
            categorical["orientation_category"]["allowed_normalized_values"],
        )
    )
    assert all(
        abs(actual - expected) <= 1e-12
        for actual, expected in zip(
            swift_lens_values,
            categorical["lens_category"]["allowed_normalized_values"],
        )
    )
    assert set(swift_signed_features) == {
        name for name, kind in feature_to_normalization.items()
        if kind in {"signed_unit_interval", "angle_degrees_to_unit"}
    }
    assert "static let actionUtilityNames = CameraCoachContractV2.production.approvedActionIDs" in swift_source
    assert swift_scene == next(
        head["ordered_names"] for head in heads if head["name"] == "scene_class_logits"
    )
    assert swift_subjectness == next(
        head["ordered_names"]
        for head in heads
        if head["name"] == "subjectness_roi_agreement_logits"
    )
    assert swift_issues == next(
        head["ordered_names"] for head in heads if head["name"] == "issue_logits"
    )
    assert swift_actions == next(
        head["ordered_names"] for head in heads if head["name"] == "action_utility_logits"
    )
    assert swift_targets == next(
        head["ordered_names"]
        for head in heads
        if head["name"] == "continuous_target_deltas"
    )
    for declaration, manifest_key in {
        "contractVersion": "contract_version",
        "inputContractVersion": "input_contract_version",
        "preprocessingVersion": "preprocessing_version",
        "featureVersion": "feature_version",
        "outputContractVersion": "output_contract_version",
    }.items():
        assert swift_string_constant(swift_source, declaration) == manifest[manifest_key]
    assert abs(
        swift_number_constant(swift_source, "scalarMissingFillValue")
        - inputs["scalar_features"]["missing_mask"]["fill_value"]
    ) <= 1e-12
    assert swift_string_constant(swift_source, "rgbSourceDType") == preprocessing["normalization"]["source_dtype"]
    assert swift_string_constant(swift_source, "rgbTensorDType") == preprocessing["normalization"]["target_dtype"]
    assert abs(
        swift_number_constant(swift_source, "rgbNormalizationDenominator")
        - preprocessing["normalization"]["denominator"]
    ) <= 1e-12
    assert abs(
        swift_number_constant(swift_source, "rgbNormalizationScale")
        - preprocessing["normalization"]["per_channel_scale"][0]
    ) <= 1e-15
    assert "SETCompositionNetContract.rgbNormalizationDenominator" in swift_preprocessor_source


def validate_input_fixture(manifest: dict, fixture: dict) -> dict:
    assert fixture["synthetic"] is True
    for version_key in (
        "contract_version",
        "input_contract_version",
        "preprocessing_version",
        "feature_version",
    ):
        assert fixture[version_key] == manifest[version_key]

    source = fixture["source_rgb_u8"]
    width = source["width"]
    height = source["height"]
    assert isinstance(width, int) and isinstance(height, int) and width > 0 and height > 0
    assert source["channel_order"] == ["R", "G", "B"]
    assert [len(source["values"])] == [width * height * 3]
    assert all(isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 255
               for value in source["values"])
    rgb_normalization = manifest["preprocessing"]["normalization"]
    assert rgb_normalization["source_dtype"] == "uint8"
    assert rgb_normalization["target_dtype"] == "float32"
    assert rgb_normalization["source_range"] == [0, 255]
    assert rgb_normalization["formula"] == "uint8_channel / 255.0"
    source_rgb = [value / rgb_normalization["denominator"] for value in source["values"]]
    roi = fixture["roi_normalized_xywh"]
    assert len(roi) == 4 and all(finite_number(value) and 0.0 <= value <= 1.0 for value in roi)
    assert roi[0] + roi[2] <= 1.0 and roi[1] + roi[3] <= 1.0

    full = bilinear_resize(source_rgb, width, height, 320, 320)
    crop = square_crop(source_rgb, width, height, roi, 192, 192)
    mask = normalized_mask(roi, 320, 320)
    scalar = fixture["scalar_features"]
    missing = fixture["missing_feature_mask"]
    validate_scalar_features(manifest, scalar, missing, roi, mask, fixture["scalar_tolerance"])

    expected = fixture["expected"]
    actual_hashes = {
        "full_frame_rgb_sha256": packed_hash(full),
        "subject_crop_rgb_sha256": packed_hash(crop),
        "roi_mask_sha256": packed_hash(mask),
        "scalar_features_sha256": packed_hash(scalar),
        "missing_feature_mask_sha256": packed_hash(missing),
    }
    for key, value in actual_hashes.items():
        assert expected[key] == value, (key, expected[key], value)
    assert expected["full_frame_rgb_shape"] == [320, 320, 3]
    assert expected["subject_crop_rgb_shape"] == [192, 192, 3]
    assert expected["roi_mask_shape"] == [320, 320, 1]
    for coordinate, sample in expected["full_frame_rgb_samples"].items():
        x, y = (int(part) for part in coordinate.split(","))
        for actual, wanted in zip(pixel_at(full, 320, x, y), sample):
            assert abs(actual - wanted) <= fixture["pixel_tolerance"]
    for coordinate, sample in expected["subject_crop_rgb_samples"].items():
        x, y = (int(part) for part in coordinate.split(","))
        for actual, wanted in zip(pixel_at(crop, 192, x, y), sample):
            assert abs(actual - wanted) <= fixture["pixel_tolerance"]

    absent = fixture["absent_roi_fixture"]
    assert absent["roi_present"] is False
    absent_roi = absent["roi_normalized_xywh"]
    assert absent_roi == [0.0, 0.0, 0.0, 0.0]
    absent_mask = normalized_mask(absent_roi, 320, 320)
    absent_crop = [0.0] * (192 * 192 * 3)
    assert absent["expected_roi_mask_shape"] == [320, 320, 1]
    assert absent["expected_subject_crop_rgb_shape"] == [192, 192, 3]
    assert absent["expected_roi_mask_sha256"] == packed_hash(absent_mask)
    assert absent["expected_subject_crop_rgb_sha256"] == packed_hash(absent_crop)
    assert all(value == 0.0 for value in absent_mask)
    assert all(value == 0.0 for value in absent_crop)
    actual_hashes["absent_roi_mask_sha256"] = packed_hash(absent_mask)
    actual_hashes["absent_subject_crop_rgb_sha256"] = packed_hash(absent_crop)

    edge_hashes: dict[str, str] = {}
    for edge in fixture["edge_fixtures"]:
        edge_roi = edge["roi_normalized_xywh"]
        assert len(edge_roi) == 4 and all(finite_number(value) and 0.0 <= value <= 1.0 for value in edge_roi)
        assert edge_roi[0] + edge_roi[2] <= 1.0 and edge_roi[1] + edge_roi[3] <= 1.0
        edge_crop = square_crop(source_rgb, width, height, edge_roi, 192, 192)
        edge_expected = edge["expected"]
        edge_hash = packed_hash(edge_crop)
        assert edge_expected["subject_crop_rgb_shape"] == [192, 192, 3]
        assert edge_expected["subject_crop_rgb_sha256"] == edge_hash
        for coordinate, sample in edge_expected["subject_crop_rgb_samples"].items():
            x, y = (int(part) for part in coordinate.split(","))
            for actual, wanted in zip(pixel_at(edge_crop, 192, x, y), sample):
                assert abs(actual - wanted) <= fixture["pixel_tolerance"]
        edge_hashes[edge["fixture_id"]] = edge_hash
    assert len(edge_hashes) == len(fixture["edge_fixtures"])
    actual_hashes["edge_subject_crop_rgb_sha256"] = edge_hashes
    return actual_hashes


def validate_output_fixture(manifest: dict, fixture: dict) -> str:
    assert fixture["synthetic"] is True
    assert fixture["contract_version"] == manifest["contract_version"]
    assert fixture["output_contract_version"] == manifest["output_contract_version"]
    assert fixture["head_order"] == manifest["outputs"]["head_order"]
    tensors = fixture["tensors"]
    shapes = {head["name"]: head["shape"][0] for head in manifest["outputs"]["heads"]}
    assert set(tensors) == set(shapes)
    flattened: list[float] = []
    for name in fixture["head_order"]:
        values = tensors[name]
        assert len(values) == shapes[name], (name, len(values), shapes[name])
        assert all(finite_number(value) for value in values)
        head = next(item for item in manifest["outputs"]["heads"] if item["name"] == name)
        if "value_range" in head:
            lower, upper = head["value_range"]
            assert all(lower <= value <= upper for value in values), name
        flattened.extend(float(value) for value in values)
    actual_hash = packed_hash(flattened)
    assert fixture["expected"]["flattened_float32_sha256"] == actual_hash
    return actual_hash


def assert_rejected(label: str, operation) -> None:
    try:
        operation()
    except (AssertionError, KeyError, TypeError, ValueError):
        return
    raise AssertionError(f"mutation accepted: {label}")


def validate_mutation_guards(manifest: dict, schema: dict,
                             input_fixture: dict, output_fixture: dict) -> list[str]:
    """Exercise the trust-boundary failures that must stay fail closed."""
    embedding_short = deepcopy(output_fixture)
    embedding_short["tensors"]["embedding"] = embedding_short["tensors"]["embedding"][:64]
    assert_rejected(
        "embedding dimension 64",
        lambda: validate_output_fixture(manifest, embedding_short),
    )

    risk_out_of_range = deepcopy(output_fixture)
    risk_out_of_range["tensors"]["risk_probability"] = [99.0]
    assert_rejected(
        "risk probability 99",
        lambda: validate_output_fixture(manifest, risk_out_of_range),
    )

    removed_head = deepcopy(output_fixture)
    removed_head["tensors"].pop("scene_class_logits")
    assert_rejected(
        "removed scene head",
        lambda: validate_output_fixture(manifest, removed_head),
    )

    manifest_embedding_short = deepcopy(manifest)
    next(head for head in manifest_embedding_short["outputs"]["heads"]
         if head["name"] == "embedding")["shape"] = [64]
    assert_rejected(
        "manifest embedding dimension 64",
        lambda: validate_manifest(manifest_embedding_short, schema),
    )

    schema_embedding_short = deepcopy(schema)
    schema_embedding_short["$defs"]["headEmbedding"]["properties"]["shape"]["const"] = [64]
    assert_rejected(
        "schema embedding dimension 64",
        lambda: validate_manifest(manifest, schema_embedding_short),
    )

    extra_depth_map = deepcopy(manifest)
    extra_depth_map["inputs"]["depth_map"] = {"dtype": "float32"}
    assert_rejected(
        "extra depth_map input",
        lambda: validate_manifest(extra_depth_map, schema),
    )

    extra_category = deepcopy(manifest)
    extra_category["categorical_features"]["depth_category"] = {}
    assert_rejected(
        "extra categorical feature",
        lambda: validate_manifest(extra_category, schema),
    )

    extra_normalization = deepcopy(manifest)
    extra_normalization["feature_normalization"]["depth_map"] = {}
    assert_rejected(
        "extra normalization entry",
        lambda: validate_manifest(extra_normalization, schema),
    )

    duplicate_head = deepcopy(manifest)
    duplicate_head["outputs"]["heads"][8] = deepcopy(duplicate_head["outputs"]["heads"][0])
    assert_rejected(
        "duplicate output head",
        lambda: validate_manifest(duplicate_head, schema),
    )

    tenth_head = deepcopy(manifest)
    tenth_head["outputs"]["heads"].append(deepcopy(tenth_head["outputs"]["heads"][-1]))
    assert_rejected(
        "tenth output head",
        lambda: validate_manifest(tenth_head, schema),
    )

    reordered_heads = deepcopy(manifest)
    reordered_heads["outputs"]["heads"][0], reordered_heads["outputs"]["heads"][1] = (
        reordered_heads["outputs"]["heads"][1],
        reordered_heads["outputs"]["heads"][0],
    )
    assert_rejected(
        "reordered output heads",
        lambda: validate_manifest(reordered_heads, schema),
    )

    rgb_formula_manifest = deepcopy(manifest)
    rgb_formula_schema = deepcopy(schema)
    rgb_formula_manifest["preprocessing"]["normalization"]["formula"] = "uint8_channel / 127.0"
    rgb_formula_schema["properties"]["preprocessing"]["properties"]["normalization"]["properties"]["formula"]["const"] = "uint8_channel / 127.0"
    assert_rejected(
        "paired RGB normalization formula drift",
        lambda: validate_manifest(rgb_formula_manifest, rgb_formula_schema),
    )

    rgb_scale_manifest = deepcopy(manifest)
    rgb_scale_schema = deepcopy(schema)
    rgb_scale_manifest["preprocessing"]["normalization"]["per_channel_scale"] = [1.0 / 127.0] * 3
    rgb_scale_schema["properties"]["preprocessing"]["properties"]["normalization"]["properties"]["per_channel_scale"]["const"] = [1.0 / 127.0] * 3
    assert_rejected(
        "paired RGB normalization scale drift",
        lambda: validate_manifest(rgb_scale_manifest, rgb_scale_schema),
    )

    rgb_type_manifest = deepcopy(manifest)
    rgb_type_schema = deepcopy(schema)
    rgb_type_manifest["preprocessing"]["normalization"]["source_dtype"] = "float16"
    rgb_type_schema["properties"]["preprocessing"]["properties"]["normalization"]["properties"]["source_dtype"]["const"] = "float16"
    assert_rejected(
        "paired RGB normalization type drift",
        lambda: validate_manifest(rgb_type_manifest, rgb_type_schema),
    )

    scalar_formula_manifest = deepcopy(manifest)
    scalar_formula_schema = deepcopy(schema)
    scalar_formula_manifest["feature_normalization"]["count_0_to_8"]["formula"] = "raw / 8.0"
    scalar_formula_schema["properties"]["feature_normalization"]["properties"]["count_0_to_8"]["properties"]["formula"]["const"] = "raw / 8.0"
    assert_rejected(
        "paired scalar normalization formula drift",
        lambda: validate_manifest(scalar_formula_manifest, scalar_formula_schema),
    )

    scalar_mapping_manifest = deepcopy(manifest)
    scalar_mapping_schema = deepcopy(schema)
    scalar_mapping_manifest["feature_normalization"]["feature_to_normalization"]["person_count"] = "unit_interval"
    scalar_mapping_schema["properties"]["feature_normalization"]["properties"]["feature_to_normalization"]["const"]["person_count"] = "unit_interval"
    assert_rejected(
        "person_count normalization mapping drift",
        lambda: validate_manifest(scalar_mapping_manifest, scalar_mapping_schema),
    )

    paired_version_manifest = deepcopy(manifest)
    paired_version_schema = deepcopy(schema)
    paired_version_manifest["contract_version"] = "setcompositionnet.v2"
    paired_version_schema["properties"]["contract_version"]["const"] = "setcompositionnet.v2"
    assert_rejected(
        "paired contract version drift",
        lambda: validate_manifest(paired_version_manifest, paired_version_schema),
    )

    paired_signed_range_manifest = deepcopy(manifest)
    paired_signed_range_schema = deepcopy(schema)
    paired_signed_range_manifest["feature_normalization"]["signed_unit_interval"]["value_range"] = [-2.0, 2.0]
    paired_signed_range_schema["properties"]["feature_normalization"]["properties"]["signed_unit_interval"]["properties"]["value_range"]["const"] = [-2.0, 2.0]
    assert_rejected(
        "paired signed feature range drift",
        lambda: validate_manifest(paired_signed_range_manifest, paired_signed_range_schema),
    )

    bad_roi = deepcopy(input_fixture)
    bad_roi["roi_normalized_xywh"] = [0.9, 0.9, 0.2, 0.2]
    assert_rejected(
        "out-of-bounds ROI",
        lambda: validate_input_fixture(manifest, bad_roi),
    )
    bad_categorical_scalar = deepcopy(input_fixture)
    bad_categorical_scalar["scalar_features"][33] = 0.8461538461538461
    assert_rejected(
        "unsupported categorical scalar value",
        lambda: validate_input_fixture(manifest, bad_categorical_scalar),
    )
    return [
        "embedding_64",
        "risk_99",
        "removed_scene_head",
        "manifest_embedding_64",
        "schema_embedding_64",
        "extra_depth_map_input",
        "extra_categorical_feature",
        "extra_normalization_entry",
        "duplicate_output_head",
        "tenth_output_head",
        "reordered_output_heads",
        "paired_rgb_formula_drift",
        "paired_rgb_scale_drift",
        "paired_rgb_type_drift",
        "paired_scalar_formula_drift",
        "person_count_mapping_drift",
        "paired_contract_version_drift",
        "paired_signed_range_drift",
        "roi_out_of_bounds",
        "unsupported_categorical_scalar",
    ]


def main() -> None:
    manifest = load_json(MANIFEST_PATH)
    schema = load_json(SCHEMA_PATH)
    input_fixture = load_json(INPUT_FIXTURE_PATH)
    output_fixture = load_json(OUTPUT_FIXTURE_PATH)
    validate_manifest(manifest, schema)
    input_hashes = validate_input_fixture(manifest, input_fixture)
    output_hash = validate_output_fixture(manifest, output_fixture)
    mutation_checks = validate_mutation_guards(manifest, schema, input_fixture, output_fixture)
    report = {
        "status": "pass",
        "contract_version": manifest["contract_version"],
        "scalar_feature_count": manifest["inputs"]["scalar_features"]["count"],
        "output_head_count": len(manifest["outputs"]["head_order"]),
        "input_hashes": input_hashes,
        "output_hash": output_hash,
        "mutation_checks": mutation_checks,
        "pixel_tolerance": input_fixture["pixel_tolerance"],
        "scalar_tolerance": input_fixture["scalar_tolerance"],
    }
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
