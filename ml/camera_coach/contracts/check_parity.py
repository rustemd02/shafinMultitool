#!/usr/bin/env python3
"""Validate the frozen SETCompositionNet-v1 manifest and synthetic fixtures.

This is intentionally stdlib-only. It is a contract/parity check, not a model
runner: no dataset, model asset, calibration data, or quality claim is needed.
"""

from __future__ import annotations

import hashlib
import json
import re
import struct
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


def validate_manifest(manifest: dict, schema: dict) -> None:
    required = {
        "contract_id",
        "contract_version",
        "input_contract_version",
        "preprocessing_version",
        "feature_version",
        "output_contract_version",
        "inputs",
        "preprocessing",
        "outputs",
    }
    assert required <= manifest.keys()
    assert schema["properties"]["contract_id"]["const"] == manifest["contract_id"]
    assert schema["properties"]["contract_version"]["const"] == manifest["contract_version"]
    assert schema["properties"]["input_contract_version"]["const"] == manifest["input_contract_version"]
    assert schema["properties"]["preprocessing_version"]["const"] == manifest["preprocessing_version"]
    assert schema["properties"]["feature_version"]["const"] == manifest["feature_version"]
    assert schema["properties"]["output_contract_version"]["const"] == manifest["output_contract_version"]

    scalar = manifest["inputs"]["scalar_features"]
    names = scalar["ordered_names"]
    assert scalar["count"] == len(names) == 40
    assert scalar["missing_mask"]["shape"] == [len(names)]
    assert scalar["missing_mask"]["ordered_names"] == "same_as_scalar_features"

    assert manifest["inputs"]["full_frame_rgb"]["shape"] == [320, 320, 3]
    assert manifest["inputs"]["subject_crop_rgb"]["shape"] == [192, 192, 3]
    assert manifest["inputs"]["roi_mask"]["shape"] == [320, 320, 1]
    assert manifest["preprocessing"]["model_channel_order"] == ["R", "G", "B"]
    assert manifest["preprocessing"]["orientation"].startswith("apply the ImageIO orientation")
    assert "no additional mirror" in manifest["preprocessing"]["mirroring"]

    outputs = manifest["outputs"]
    head_order = outputs["head_order"]
    heads = outputs["heads"]
    assert [head["name"] for head in heads] == head_order
    assert len(set(head_order)) == len(head_order)
    assert "generated_text" in outputs["forbidden_outputs"]
    assert "arbitrary_object_name" in outputs["forbidden_outputs"]
    for head in heads:
        assert head["dtype"] == "float32"
        assert len(head["shape"]) == 1
        assert head["shape"][0] > 0

    # The Swift runtime intentionally has no build-time codegen dependency.
    # Keep the checked manifest canonical by comparing its ordered catalogs to
    # the runtime declarations on every deterministic parity run.
    swift_source = SWIFT_CONTRACT_PATH.read_text(encoding="utf-8")
    swift_heads = swift_string_array(swift_source, "outputHeadNames")
    swift_features = swift_string_array(swift_source, "featureNames")
    swift_scene = swift_string_array(swift_source, "sceneClassNames")
    swift_subjectness = swift_string_array(swift_source, "subjectnessROIAgreementNames")
    swift_targets = swift_string_array(swift_source, "targetDeltaNames")
    swift_issues = swift_enum_raw_values(swift_source, "IssueTypeV1")
    swift_actions = swift_enum_raw_values(swift_source, "ActionTypeV1")

    assert swift_heads == head_order
    assert swift_features == manifest["inputs"]["scalar_features"]["ordered_names"]
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
    assert [len(source["values"])] == [width * height * 3]
    source_rgb = [value / 255.0 for value in source["values"]]
    roi = fixture["roi_normalized_xywh"]
    assert len(roi) == 4 and all(0.0 <= value <= 1.0 for value in roi)
    assert roi[0] + roi[2] <= 1.0 and roi[1] + roi[3] <= 1.0

    full = bilinear_resize(source_rgb, width, height, 320, 320)
    crop = square_crop(source_rgb, width, height, roi, 192, 192)
    mask = normalized_mask(roi, 320, 320)
    scalar = fixture["scalar_features"]
    missing = fixture["missing_feature_mask"]
    assert len(scalar) == len(missing) == 40
    assert all(value == 0.0 or value == 1.0 for value in missing)

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
        assert all(isinstance(value, (int, float)) and value == value for value in values)
        head = next(item for item in manifest["outputs"]["heads"] if item["name"] == name)
        if "value_range" in head:
            lower, upper = head["value_range"]
            assert all(lower <= value <= upper for value in values), name
        flattened.extend(float(value) for value in values)
    actual_hash = packed_hash(flattened)
    assert fixture["expected"]["flattened_float32_sha256"] == actual_hash
    return actual_hash


def main() -> None:
    manifest = load_json(MANIFEST_PATH)
    schema = load_json(SCHEMA_PATH)
    input_fixture = load_json(INPUT_FIXTURE_PATH)
    output_fixture = load_json(OUTPUT_FIXTURE_PATH)
    validate_manifest(manifest, schema)
    input_hashes = validate_input_fixture(manifest, input_fixture)
    output_hash = validate_output_fixture(manifest, output_fixture)
    report = {
        "status": "pass",
        "contract_version": manifest["contract_version"],
        "scalar_feature_count": manifest["inputs"]["scalar_features"]["count"],
        "output_head_count": len(manifest["outputs"]["head_order"]),
        "input_hashes": input_hashes,
        "output_hash": output_hash,
        "pixel_tolerance": input_fixture["pixel_tolerance"],
        "scalar_tolerance": input_fixture["scalar_tolerance"],
    }
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
