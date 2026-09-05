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


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise AssertionError(f"{path} must contain a JSON object")
    return value


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
    left = max(0.0, raw_x + raw_width / 2.0 - side / 2.0)
    top = max(0.0, raw_y + raw_height / 2.0 - side / 2.0)
    right = min(float(width), left + side)
    bottom = min(float(height), top + side)

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
    for name, value, missing_value in zip(names, scalar, missing):
        lower, upper = ranges[normalization[name]]["value_range"]
        assert lower <= value <= upper, (name, value, lower, upper)
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
    required = {
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
    }
    assert required <= manifest.keys()
    assert schema["properties"]["contract_id"]["const"] == manifest["contract_id"]
    assert schema["properties"]["contract_version"]["const"] == manifest["contract_version"]
    assert schema["properties"]["input_contract_version"]["const"] == manifest["input_contract_version"]
    assert schema["properties"]["preprocessing_version"]["const"] == manifest["preprocessing_version"]
    assert schema["properties"]["feature_version"]["const"] == manifest["feature_version"]
    assert schema["properties"]["output_contract_version"]["const"] == manifest["output_contract_version"]

    assert manifest["tensor_layout"] == "HWC"
    inputs = manifest["inputs"]

    def tensor(name: str, shape: list[int], *, binary: bool = False) -> dict:
        value = inputs[name]
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

    roi = inputs["roi_normalized_xywh"]
    assert roi["dtype"] == "float32"
    assert roi["shape"] == [4]
    assert roi["ordered_names"] == ["x", "y", "width", "height"]
    assert roi["coordinate_space"] == "oriented_full_frame"
    assert roi["origin"] == "top_left"
    assert roi["axis_direction"] == ["right", "down"]
    assert roi["value_range"] == [0.0, 1.0]
    assert roi["bounds"] == ["x + width <= 1.0", "y + height <= 1.0"]
    assert roi["missing_value"] == [0.0, 0.0, 0.0, 0.0]

    scalar = inputs["scalar_features"]
    names = scalar["ordered_names"]
    assert scalar["dtype"] == "float32"
    assert scalar["shape"] == [40]
    assert scalar["count"] == len(names) == 40
    missing_mask = scalar["missing_mask"]
    assert missing_mask["dtype"] == "float32"
    assert missing_mask["shape"] == [len(names)]
    assert missing_mask["ordered_names"] == "same_as_scalar_features"
    assert missing_mask["values"] == [0.0, 1.0]
    assert missing_mask["fill_value"] == 0.0

    categorical = manifest["categorical_features"]
    assert categorical["orientation_category"]["count"] == 8
    assert categorical["orientation_category"]["ordered_names"] == [
        "up", "up_mirrored", "down", "down_mirrored",
        "left_mirrored", "right", "right_mirrored", "left"
    ]
    assert categorical["lens_category"]["count"] == 3
    assert categorical["lens_category"]["ordered_names"] == ["ultra_wide", "wide", "tele"]

    normalization = manifest["feature_normalization"]
    feature_to_normalization = normalization["feature_to_normalization"]
    assert list(feature_to_normalization) == names
    allowed_normalizations = {
        "unit_interval": [0.0, 1.0],
        "signed_unit_interval": [-1.0, 1.0],
        "count_0_to_8": [0.0, 1.0],
        "angle_degrees_to_unit": [-1.0, 1.0],
        "categorical_index": [0.0, 1.0],
        "aspect_ratio": [0.0, 1.0],
    }
    for feature_name, normalization_name in feature_to_normalization.items():
        assert normalization_name in allowed_normalizations
        assert normalization[normalization_name]["value_range"] == allowed_normalizations[normalization_name]

    preprocessing = manifest["preprocessing"]
    assert preprocessing["source_color_space"] == "sRGB"
    assert preprocessing["source_pixel_format"] == "32BGRA"
    assert preprocessing["model_channel_order"] == ["R", "G", "B"]
    assert preprocessing["alpha"] == "discard"
    assert preprocessing["orientation"].startswith("apply the ImageIO orientation exactly once")
    assert "no additional mirror" in preprocessing["mirroring"]
    assert preprocessing["resize_interpolation"] == "bilinear"
    assert preprocessing["resize_geometry"] == "independent_scale_to_target"
    assert preprocessing["normalization"]["value_range"] == [0.0, 1.0]
    assert preprocessing["subject_crop"]["recipe_version"] == "square_expand_1.25.v1"
    assert "clip padded square to oriented full-frame bounds" in preprocessing["subject_crop"]["clipping"]
    assert preprocessing["subject_crop"]["missing_crop"] == "zero-filled 192x192x3 tensor"

    outputs = manifest["outputs"]
    head_order = outputs["head_order"]
    heads = outputs["heads"]
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
    assert [head["name"] for head in heads] == head_order
    assert len(set(head_order)) == len(head_order) == 9
    assert "generated_text" in outputs["forbidden_outputs"]
    assert "arbitrary_object_name" in outputs["forbidden_outputs"]
    for head in heads:
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

    # The Swift runtime intentionally has no build-time codegen dependency.
    # Keep the checked manifest canonical by comparing its ordered catalogs to
    # the runtime declarations on every deterministic parity run.
    swift_source = SWIFT_CONTRACT_PATH.read_text(encoding="utf-8")
    swift_heads = swift_string_array(swift_source, "outputHeadNames")
    swift_features = swift_string_array(swift_source, "featureNames")
    swift_scene = swift_string_array(swift_source, "sceneClassNames")
    swift_subjectness = swift_string_array(swift_source, "subjectnessROIAgreementNames")
    swift_targets = swift_string_array(swift_source, "targetDeltaNames")
    swift_orientation = swift_string_array(swift_source, "orientationCategoryNames")
    swift_lenses = swift_string_array(swift_source, "lensCategoryNames")
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
    source_rgb = [value / 255.0 for value in source["values"]]
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

    bad_roi = deepcopy(input_fixture)
    bad_roi["roi_normalized_xywh"] = [0.9, 0.9, 0.2, 0.2]
    assert_rejected(
        "out-of-bounds ROI",
        lambda: validate_input_fixture(manifest, bad_roi),
    )
    return ["embedding_64", "risk_99", "removed_scene_head", "manifest_embedding_64", "roi_out_of_bounds"]


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
