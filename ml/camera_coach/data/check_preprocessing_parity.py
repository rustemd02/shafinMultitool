"""Check Python preprocessing against independent frozen Swift fixture math."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import struct
import sys

if not __package__:  # Keep direct path execution useful in addition to -m.
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
    from ml.camera_coach.data.preprocessing import preprocess_frame
else:
    from .preprocessing import preprocess_frame

from ml.camera_coach.contracts import check_parity as frozen_contract
from ml.camera_coach.models.set_composition_net import SETCompositionNetManifest


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "contracts" / "set_composition_net_v1.json"
SCHEMA_PATH = ROOT / "contracts" / "set_composition_net_v1.schema.json"
INPUT_FIXTURE_PATH = ROOT / "contracts" / "fixtures" / "set_composition_net_v1_parity.json"
FIXTURE_PATH = Path(__file__).resolve().parent / "fixtures" / "preprocessing_parity.json"
TOLERANCE = 1e-6
SOURCE_DIMENSION_FORMULA = {
    "width": "2 + (index * 5 % 7)",
    "height": "2 + (index * 5 % 8)",
}


def _lcg(state: int) -> tuple[int, int]:
    state = (1664525 * state + 1013904223) & 0xFFFFFFFF
    return state, state


def _case(index: int, seed: int, feature_names: tuple[str, ...], normalization: dict) -> dict:
    state = (seed + index * 7919) & 0xFFFFFFFF
    width = 2 + (index * 5 % 7)
    height = 2 + (index * 5 % 8)
    pixels: list[int] = []
    for _ in range(width * height * 4):
        state, value = _lcg(state)
        pixels.append(value & 0xFF)
    orientations = [
        "up", "upMirrored", "right", "rightMirrored",
        "down", "downMirrored", "left", "leftMirrored",
    ]
    orientation = orientations[index % len(orientations)]
    if index % 11 == 0:
        roi = None
    elif index % 11 == 1:
        roi = (0.0, 0.0, 0.2, 0.2)
    elif index % 11 == 2:
        roi = (0.8, 0.8, 0.2, 0.2)
    else:
        roi_width = 0.15 + 0.05 * (index % 4)
        roi_height = 0.2 + 0.04 * (index % 3)
        roi = (
            (0.07 * index) % (1.0 - roi_width),
            (0.11 * index) % (1.0 - roi_height),
            roi_width,
            roi_height,
        )
    raw: dict[str, object] = {}
    missing: list[str] = []
    for feature_index, name in enumerate(feature_names):
        state, value = _lcg(state)
        fraction = value / 0xFFFFFFFF
        kind = normalization[name]
        if kind == "unit_interval":
            raw[name] = fraction * 1.5 - 0.25
        elif kind == "signed_unit_interval":
            raw[name] = fraction * 3.0 - 1.5
        elif kind == "count_0_to_8":
            raw[name] = fraction * 12.0 - 2.0
        elif kind == "angle_degrees_to_unit":
            raw[name] = fraction * 540.0 - 270.0
        elif kind == "categorical_index":
            raw[name] = (index + feature_index) % (4 if name == "orientation_category" else 3)
        elif kind == "aspect_ratio":
            raw[name] = (width + 1 + index % 5, height + 1 + (index + 2) % 4)
        if (index + feature_index) % 13 == 0:
            missing.append(name)
    return {
        "index": index,
        "pixels": pixels,
        "width": width,
        "height": height,
        "roi": roi,
        "raw_features": raw,
        "missing_features": tuple(missing),
        "orientation": orientation,
        "lens": (index + 1) % 3,
    }


def _oriented(source: list[float], width: int, height: int, orientation: str) -> tuple[list[float], int, int]:
    swaps = orientation in {"right", "rightMirrored", "left", "leftMirrored"}
    output_width, output_height = (height, width) if swaps else (width, height)
    values: list[float] = []
    for y in range(output_height):
        for x in range(output_width):
            coordinates = {
                "up": (x, y),
                "upMirrored": (width - 1 - x, y),
                "down": (width - 1 - x, height - 1 - y),
                "downMirrored": (x, height - 1 - y),
                "leftMirrored": (y, x),
                "right": (y, height - 1 - x),
                "rightMirrored": (width - 1 - y, height - 1 - x),
                "left": (width - 1 - y, x),
            }
            source_x, source_y = coordinates[orientation]
            offset = (source_y * width + source_x) * 3
            values.extend(source[offset:offset + 3])
    return values, output_width, output_height


def _resize(source: list[float], width: int, height: int, target_width: int, target_height: int,
            left: float, top: float, right: float, bottom: float) -> list[float]:
    def clamp(value: float, lower: float, upper: float) -> float:
        return min(upper, max(lower, value))

    values: list[float] = []
    for y in range(target_height):
        source_y = clamp(top + (y + 0.5) * (bottom - top) / target_height - 0.5, 0.0, height - 1.0)
        y0, y1 = int(source_y), min(int(source_y) + 1, height - 1)
        y_weight = source_y - y0
        for x in range(target_width):
            source_x = clamp(left + (x + 0.5) * (right - left) / target_width - 0.5, 0.0, width - 1.0)
            x0, x1 = int(source_x), min(int(source_x) + 1, width - 1)
            x_weight = source_x - x0
            for channel in range(3):
                top_left = source[(y0 * width + x0) * 3 + channel]
                top_right = source[(y0 * width + x1) * 3 + channel]
                bottom_left = source[(y1 * width + x0) * 3 + channel]
                bottom_right = source[(y1 * width + x1) * 3 + channel]
                top_value = (1.0 - x_weight) * top_left + x_weight * top_right
                bottom_value = (1.0 - x_weight) * bottom_left + x_weight * bottom_right
                values.append((1.0 - y_weight) * top_value + y_weight * bottom_value)
    return values


def _reference(case: dict) -> dict[str, list[float]]:
    pixels = case["pixels"]
    # The fixture source is transport-order BGRA; alpha is discarded.
    rgb = [
        float(pixels[offset + channel]) / 255.0
        for offset in range(0, len(pixels), 4)
        for channel in (2, 1, 0)
    ]
    oriented, width, height = _oriented(rgb, case["width"], case["height"], case["orientation"])
    full = _resize(oriented, width, height, 320, 320, 0.0, 0.0, float(width), float(height))
    roi = case["roi"]
    if roi is None:
        crop = [0.0] * (192 * 192 * 3)
        roi_values = (0.0, 0.0, 0.0, 0.0)
    else:
        x, y, roi_width, roi_height = roi
        raw_width, raw_height = roi_width * width, roi_height * height
        side = max(raw_width, raw_height) * 1.25
        center_x, center_y = x * width + raw_width / 2.0, y * height + raw_height / 2.0
        left, top = max(0.0, center_x - side / 2.0), max(0.0, center_y - side / 2.0)
        right, bottom = min(float(width), center_x + side / 2.0), min(float(height), center_y + side / 2.0)
        crop = _resize(oriented, width, height, 192, 192, left, top, right, bottom)
        roi_values = roi
    mask = [
        1.0
        if roi_values[0] <= (x + 0.5) / 320 < roi_values[0] + roi_values[2]
        and roi_values[1] <= (y + 0.5) / 320 < roi_values[1] + roi_values[3]
        else 0.0
        for y in range(320)
        for x in range(320)
    ]
    raw = dict(case["raw_features"])
    raw.update({
        "roi_present": 1.0 if roi is not None else 0.0,
        "roi_area_ratio": roi_values[2] * roi_values[3],
        "roi_mask_coverage": sum(mask) / len(mask),
        "orientation_category": ("up", "right", "down", "left").index(case["orientation"].replace("Mirrored", "")),
        "mirroring_flag": 1.0 if "Mirrored" in case["orientation"] else 0.0,
        "lens_category": case["lens"],
    })
    feature_names = tuple(SETCompositionNetManifest.load(MANIFEST_PATH).raw["inputs"]["scalar_features"]["ordered_names"])
    mapping = SETCompositionNetManifest.load(MANIFEST_PATH).raw["feature_normalization"]["feature_to_normalization"]
    values: list[float] = []
    missing = set(case["missing_features"])
    for name in feature_names:
        if name in missing:
            values.append(0.0)
            continue
        value = raw[name]
        kind = mapping[name]
        if kind == "unit_interval":
            values.append(min(1.0, max(0.0, float(value))))
        elif kind == "signed_unit_interval":
            values.append(min(1.0, max(-1.0, float(value))))
        elif kind == "count_0_to_8":
            values.append(min(8.0, max(0.0, float(value))) / 8.0)
        elif kind == "angle_degrees_to_unit":
            values.append(min(1.0, max(-1.0, float(value) / 180.0)))
        elif kind == "categorical_index":
            count = 4 if name == "orientation_category" else 3
            values.append(float(value) / (count - 1))
        elif kind == "aspect_ratio":
            raw_width, raw_height = value
            values.append(min(4.0, max(0.0, raw_width / raw_height)) / 4.0)
        else:  # pragma: no cover
            raise AssertionError(kind)
    return {
        "full_frame_rgb": full,
        "subject_crop_rgb": crop,
        "roi_mask": mask,
        "roi_normalized_xywh": list(roi_values),
        "scalar_features": values,
        "missing_feature_mask": [1.0 if name in missing else 0.0 for name in feature_names],
    }


def _float_bytes(values: list[float]) -> bytes:
    return struct.pack(f"<{len(values)}f", *values)


def _digest(result: dict[str, list[float]]) -> str:
    digest = hashlib.sha256()
    for name in ("full_frame_rgb", "subject_crop_rgb", "roi_normalized_xywh", "roi_mask", "scalar_features", "missing_feature_mask"):
        values = result[name]
        digest.update(name.encode("ascii"))
        digest.update(struct.pack("<I", len(values)))
        digest.update(_float_bytes(values))
    return digest.hexdigest()


def _image_digest(result: dict[str, list[float]], digest: hashlib._Hash | None = None) -> str:
    image_digest = digest or hashlib.sha256()
    for name in ("full_frame_rgb", "subject_crop_rgb", "roi_normalized_xywh", "roi_mask"):
        values = result[name]
        image_digest.update(name.encode("ascii"))
        image_digest.update(struct.pack("<I", len(values)))
        image_digest.update(_float_bytes(values))
    return image_digest.hexdigest()


def _assert_close(actual: list[float], expected: list[float], label: str) -> None:
    if len(actual) != len(expected):
        raise AssertionError(f"{label} length drift: {len(actual)} != {len(expected)}")
    difference = max((abs(float(a) - float(b)) for a, b in zip(actual, expected)), default=0.0)
    if difference > TOLERANCE:
        raise AssertionError(f"{label} max difference {difference} > {TOLERANCE}")


def main() -> int:
    fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    frozen_contract.validate_manifest(manifest, schema)
    frozen_contract.validate_input_fixture(manifest, json.loads(INPUT_FIXTURE_PATH.read_text(encoding="utf-8")))
    assert fixture["fixture_version"] == "setcompositionnet.training_preprocessing_parity.v1"
    assert fixture["contract_version"] == manifest["contract_version"]
    assert fixture["case_count"] >= 50
    assert fixture["source_dimension_formula"] == SOURCE_DIMENSION_FORMULA
    expected_case_image_digests = fixture["expected_case_image_digests"]
    assert len(expected_case_image_digests) == fixture["case_count"]
    contract = SETCompositionNetManifest.load(MANIFEST_PATH)
    feature_names = tuple(contract.raw["inputs"]["scalar_features"]["ordered_names"])
    normalization = contract.raw["feature_normalization"]["feature_to_normalization"]
    digest = hashlib.sha256()
    swift_image_digest = hashlib.sha256()
    orientation_counts = {name: 0 for name in fixture["orientation_order"]}
    absent_count = 0
    mirrored_count = 0
    source_widths: set[int] = set()
    source_heights: set[int] = set()
    source_dimension_pairs: set[tuple[int, int]] = set()
    source_aspect_ratios: set[tuple[int, int]] = set()
    min_aspect_ratio = math.inf
    max_aspect_ratio = -math.inf
    for index in range(fixture["case_count"]):
        case = _case(index, fixture["seed"], feature_names, normalization)
        width, height = int(case["width"]), int(case["height"])
        source_widths.add(width)
        source_heights.add(height)
        source_dimension_pairs.add((width, height))
        divisor = math.gcd(width, height)
        source_aspect_ratios.add((width // divisor, height // divisor))
        aspect_ratio = width / height
        min_aspect_ratio = min(min_aspect_ratio, aspect_ratio)
        max_aspect_ratio = max(max_aspect_ratio, aspect_ratio)
        expected = _reference(case)
        actual = preprocess_frame(
            case["pixels"],
            width=case["width"],
            height=case["height"],
            roi=case["roi"],
            raw_features=case["raw_features"],
            missing_features=case["missing_features"],
            orientation=case["orientation"],
            lens=case["lens"],
            channel_order="BGRA",
        )
        actual_values = {
            "full_frame_rgb": actual.full_frame_rgb.flatten().tolist(),
            "subject_crop_rgb": actual.subject_crop_rgb.flatten().tolist(),
            "roi_normalized_xywh": actual.roi_normalized_xywh.flatten().tolist(),
            "roi_mask": actual.roi_mask.flatten().tolist(),
            "scalar_features": actual.scalar_features.flatten().tolist(),
            "missing_feature_mask": actual.missing_feature_mask.flatten().tolist(),
        }
        for name, values in actual_values.items():
            _assert_close(values, expected[name], f"case {index} {name}")
        case_image_digest = _image_digest(actual_values)
        assert case_image_digest == expected_case_image_digests[index], (
            index,
            expected_case_image_digests[index],
            case_image_digest,
        )
        _image_digest(actual_values, swift_image_digest)
        _assert_close(actual_values["roi_normalized_xywh"], expected["roi_normalized_xywh"], f"case {index} ROI")
        assert all(value in (0.0, 1.0) for value in actual_values["roi_mask"])
        assert all(0.0 <= value <= 1.0 for value in actual_values["full_frame_rgb"])
        assert all(0.0 <= value <= 1.0 for value in actual_values["subject_crop_rgb"])
        if case["roi"] is None:
            assert all(value == 0.0 for value in actual_values["roi_mask"])
            assert all(value == 0.0 for value in actual_values["subject_crop_rgb"])
        assert all(
            mask_value == 0.0 or (mask_value == 1.0 and value == 0.0)
            for value, mask_value in zip(actual_values["scalar_features"], actual_values["missing_feature_mask"])
        )
        for name in actual_values:
            digest.update(name.encode("ascii"))
            digest.update(struct.pack("<I", len(actual_values[name])))
            digest.update(_float_bytes(actual_values[name]))
        orientation_counts[case["orientation"]] += 1
        mirrored_count += "Mirrored" in case["orientation"]
        absent_count += case["roi"] is None
    actual_digest = digest.hexdigest()
    assert actual_digest == fixture["expected_digest"], (fixture["expected_digest"], actual_digest)
    actual_swift_image_digest = swift_image_digest.hexdigest()
    assert actual_swift_image_digest == fixture["expected_swift_image_digest"], (
        fixture["expected_swift_image_digest"],
        actual_swift_image_digest,
    )
    assert absent_count > 0 and mirrored_count > 0
    assert all(value > 0 for value in orientation_counts.values())
    source_dimension_summary = {
        "width_min": min(source_widths),
        "width_max": max(source_widths),
        "unique_widths": len(source_widths),
        "height_min": min(source_heights),
        "height_max": max(source_heights),
        "unique_heights": len(source_heights),
        "unique_dimension_pairs": len(source_dimension_pairs),
        "unique_aspect_ratios": len(source_aspect_ratios),
        "aspect_ratio_min": min_aspect_ratio,
        "aspect_ratio_max": max_aspect_ratio,
    }
    expected_dimension_summary = fixture["source_dimension_summary"]
    for key in (
        "width_min", "width_max", "unique_widths", "height_min", "height_max",
        "unique_heights", "unique_dimension_pairs", "unique_aspect_ratios",
    ):
        assert source_dimension_summary[key] == expected_dimension_summary[key], (
            key, expected_dimension_summary[key], source_dimension_summary[key]
        )
    for key in ("aspect_ratio_min", "aspect_ratio_max"):
        assert math.isclose(
            source_dimension_summary[key], expected_dimension_summary[key],
            rel_tol=0.0, abs_tol=TOLERANCE,
        ), (key, expected_dimension_summary[key], source_dimension_summary[key])
    assert source_dimension_summary["unique_widths"] >= 4
    assert source_dimension_summary["unique_heights"] >= 4
    assert source_dimension_summary["unique_dimension_pairs"] >= 20
    assert source_dimension_summary["unique_aspect_ratios"] >= 10
    report = {
        "status": "pass",
        "contract_version": manifest["contract_version"],
        "case_count": fixture["case_count"],
        "orientation_counts": orientation_counts,
        "mirrored_cases": mirrored_count,
        "absent_roi_cases": absent_count,
        "tolerance": TOLERANCE,
        "canonical_digest": actual_digest,
        "swift_image_digest": actual_swift_image_digest,
        "case_image_digest_count": len(expected_case_image_digests),
        "source": fixture["source_generator"],
        "source_dimension_formula": fixture["source_dimension_formula"],
        "source_dimension_summary": source_dimension_summary,
    }
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
