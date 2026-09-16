#!/usr/bin/env python3
"""Generate research-only Camera Coach paired pixel corruptions.

The input inventory and Apple Vision geometry are already verified metadata.
This tool only derives deterministic image pairs and analytic targets; it never
re-runs a detector on a derivative and never emits release or human-gold data.
"""

from __future__ import annotations

import argparse
from io import BytesIO
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tempfile
import warnings
from typing import Any, Callable, Mapping

try:
    from PIL import Image, ImageCms, ImageOps
except ImportError as exc:  # pragma: no cover - exercised by environment setup.
    raise SystemExit("Pillow is required") from exc


ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json"
GEOMETRY_SCHEMA_PATH = ROOT / "datasets/camera-coach/v1/silver-geometry-schema.json"
PAIR_SCHEMA_PATH = ROOT / "datasets/camera-coach/v1/silver-action-pair-schema.json"
GENERATOR_RELATIVE_PATH = "tools/dataset/generate_camera_corruptions.py"
GEOMETRY_TOOL_RELATIVE_PATH = "tools/dataset/extract_camera_geometry.swift"
GEOMETRY_RECEIPT_SCHEMA_ID = "camera-silver-geometry-receipt-v1"
GEOMETRY_DETERMINISM = "conditional_on_captured_apple_os_vision_runtime"
VISION_REQUEST_FAMILY = (
    "VNDetectHumanRectanglesRequest",
    "VNDetectFaceRectanglesRequest",
    "VNGenerateAttentionBasedSaliencyImageRequest",
    "VNDetectHorizonRequest",
)
PAIR_SCHEMA_ID = "camera-silver-action-pair-v1"
PAIR_SCHEMA_VERSION = "1.0.0"
RESEARCH_SPLIT = "research_fit"
PILLOW_VERSION_PIN = "12.2.0"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SAFE_ID_RE = re.compile(r"^[^/\\\x00\r\n]+$")
FORMAT_RE = re.compile(r"^[a-z0-9.+-]+$")
MAX_WIDTH = 4096
MAX_HEIGHT = 4096
MAX_PIXELS = MAX_WIDTH * MAX_HEIGHT
TARGET_EDGE_GAP = 0.02
ZOOM_MIN = 1.15
ZOOM_MAX = 1.50
ZOOM_PRESSURE_MIN_GAP = 0.03
ZOOM_PRESSURE_MAX_GAP = 0.12

ORIENTATION_NAMES = {
    1: "up",
    2: "up_mirrored",
    3: "down",
    4: "down_mirrored",
    5: "left_mirrored",
    6: "right",
    7: "right_mirrored",
    8: "left",
}

VISION_PILLOW_TRANSFORM = "after ImageOps.exif_transpose exactly once: x'=x; y'=1-y-height; width'=width; height'=height; no second EXIF transform"
RAW_PIXEL_PREPROCESSING = "ImageIO/CGImage remains in encoded storage orientation; raw Pillow pixels require ImageOps.exif_transpose exactly once before geometry transforms"
HORIZON_ANGLE_CONTRACT = "observed Vision tilt, not an uprighting correction; positive means the horizon falls toward +x in the oriented display (clockwise in x-right/y-down), equivalently a negative line angle in x-right/y-up"
HORIZON_PILLOW_ROTATION = "after ImageOps.exif_transpose exactly once, call PIL Image.rotate(angle=pillow_uprighting_rotation_degrees); Pillow positive angles are counter-clockwise visually, and this levels the observed tilt"

# This block is the single frozen owner of the target-delta meaning.  Its
# canonical digest is copied into the pair schema and every output receipt.
SEMANTICS = {
    "coordinate_space": "oriented_full_frame_top_left_normalized",
    "axes": {"x": "right", "y": "down"},
    "roi": "transform the silver selected ROI analytically; never detect on a derivative",
    "delta_x": "desired subject-center displacement in normalized frame units; positive is right",
    "delta_y": "desired subject-center displacement in normalized frame units; positive is down",
    "scale_delta": "log2(target source linear scale / derivative linear scale); zoom-in is negative",
    "horizon_delta": "required scene correction degrees / 180; derivative +theta maps to -theta/180",
    "label_mask": "mask=1 only for the recipe-positive label and exact forbidden opposite/keep labels; unknown=0",
}


class CorruptionError(ValueError):
    """Raised for an unsafe, malformed, or unverifiable input."""


def _reject_constant(value: str) -> Any:
    raise CorruptionError(f"non-finite JSON number is not allowed: {value}")


def _canonical_json(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise CorruptionError("value is not canonical JSON") from exc


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    try:
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise CorruptionError(f"not a regular file: {path}")
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
        return digest.hexdigest()
    except CorruptionError:
        raise
    except OSError as exc:
        raise CorruptionError(f"cannot read file: {path}") from exc


def _json_bytes(value: Any) -> bytes:
    return (_canonical_json(value) + "\n").encode("utf-8")


def _read_json(path: Path, label: str) -> tuple[Any, bytes]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise CorruptionError(f"cannot read {label}") from exc
    try:
        value = json.loads(data.decode("utf-8"), parse_constant=_reject_constant)
    except CorruptionError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise CorruptionError(f"{label} is malformed JSON") from exc
    return value, data


def _read_jsonl(path: Path, label: str) -> tuple[list[dict[str, Any]], bytes]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise CorruptionError(f"cannot read {label}") from exc
    rows: list[dict[str, Any]] = []
    # JSON Lines uses LF as the record delimiter.  ``str.splitlines`` also
    # treats U+2028/U+2029 as line boundaries, which would corrupt otherwise
    # valid JSON strings containing those characters.
    physical_lines = data.split(b"\n")
    if physical_lines and physical_lines[-1] == b"":
        physical_lines.pop()
    for line_number, raw_line in enumerate(physical_lines, 1):
        if not raw_line.strip():
            raise CorruptionError(f"{label} has a blank line at {line_number}")
        try:
            line = raw_line.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise CorruptionError(f"{label} line {line_number} is not UTF-8") from exc
        try:
            value = json.loads(line, parse_constant=_reject_constant)
        except CorruptionError:
            raise
        except (json.JSONDecodeError, RecursionError) as exc:
            raise CorruptionError(f"{label} line {line_number} is malformed JSON") from exc
        if not isinstance(value, dict):
            raise CorruptionError(f"{label} line {line_number} must be an object")
        rows.append(value)
    if not rows:
        raise CorruptionError(f"{label} contains no rows")
    return rows, data


def _assert_no_symlink_components(path: Path) -> None:
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise CorruptionError(f"cannot inspect path component: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise CorruptionError(f"path uses a symlink: {current}")


def _external_directory(value: Path, label: str, *, must_exist: bool) -> Path:
    candidate = value.expanduser()
    _assert_no_symlink_components(candidate)
    absolute = Path(os.path.abspath(candidate))
    exists = absolute.exists()
    if exists:
        try:
            info = absolute.lstat()
        except OSError as exc:
            raise CorruptionError(f"cannot inspect {label}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise CorruptionError(f"{label} must be a regular directory")
    elif must_exist:
        raise CorruptionError(f"{label} must be an existing directory")
    resolved = absolute.resolve(strict=False)
    repository = ROOT.resolve()
    if resolved == repository or repository in resolved.parents or resolved in repository.parents:
        raise CorruptionError(f"{label} must be outside the repository")
    if not exists:
        parent = resolved.parent
        _assert_no_symlink_components(parent)
        if not parent.is_dir() or parent.is_symlink():
            raise CorruptionError(f"{label} parent must be a regular directory")
    return resolved


def _regular_input(path: Path, label: str) -> Path:
    candidate = path.expanduser()
    _assert_no_symlink_components(candidate)
    try:
        info = candidate.lstat()
    except OSError as exc:
        raise CorruptionError(f"cannot inspect {label}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise CorruptionError(f"{label} must be a regular file")
    return candidate


def _safe_relative(root: Path, value: Any, label: str) -> tuple[Path, str]:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise CorruptionError(f"{label} must be a non-empty relative path")
    normalized = value.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    if (
        normalized.startswith("/")
        or not parts
        or any(part in ("", ".", "..") for part in parts)
        or ":" in parts[0]
    ):
        raise CorruptionError(f"{label} is not safely relative")
    current = root
    for part in parts:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise CorruptionError(f"cannot inspect {label}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise CorruptionError(f"{label} uses a symlink")
    candidate = root.joinpath(*parts)
    resolved = candidate.resolve(strict=False)
    if resolved != candidate or root not in resolved.parents and resolved != root:
        raise CorruptionError(f"{label} escapes source-root")
    return candidate, PurePosixPath(*parts).as_posix()


def _finite(value: Any, label: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        raise CorruptionError(f"{label} must be finite")
    return float(value)


def _int(value: Any, label: str, minimum: int | None = None) -> int:
    if type(value) is not int or (minimum is not None and value < minimum):
        raise CorruptionError(f"{label} must be an integer")
    return value


def _digest_fingerprint(path: Path) -> tuple[int, str]:
    try:
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise CorruptionError(f"source is not a regular file: {path}")
        return info.st_size, _sha256_file(path)
    except CorruptionError:
        raise
    except OSError as exc:
        raise CorruptionError(f"cannot inspect source: {path}") from exc


def _reject_policy_metadata(value: Any, path: str = "upstream_metadata") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            if any(token in key_text.lower() for token in ("rights", "license", "consent", "split", "gold", "release", "approved")):
                raise CorruptionError(f"policy-bearing metadata is not accepted: {path}.{key_text}")
            _reject_policy_metadata(child, f"{path}.{key_text}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_policy_metadata(child, f"{path}[{index}]")
    elif isinstance(value, float) and not math.isfinite(value):
        raise CorruptionError(f"metadata contains a non-finite number: {path}")
    elif value is not None and not isinstance(value, (str, int, bool, float)):
        raise CorruptionError(f"metadata contains an unsupported value: {path}")


def _load_contract() -> tuple[dict[str, Any], str, tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    contract, raw = _read_json(CONTRACT_PATH, "SETCompositionNet contract")
    if not isinstance(contract, dict) or contract.get("contract_version") != "setcompositionnet.v1":
        raise CorruptionError("unexpected SETCompositionNet contract")
    outputs = contract.get("outputs")
    heads = outputs.get("heads") if isinstance(outputs, dict) else None
    head_order = outputs.get("head_order") if isinstance(outputs, dict) else None
    if not isinstance(heads, list) or not isinstance(head_order, list) or len(heads) != len(head_order):
        raise CorruptionError("SETCompositionNet contract outputs are malformed")
    by_name: dict[str, dict[str, Any]] = {}
    for head in heads:
        if not isinstance(head, dict) or not isinstance(head.get("name"), str) or head["name"] in by_name:
            raise CorruptionError("SETCompositionNet contract has duplicate or malformed heads")
        by_name[head["name"]] = head
    if set(head_order) != set(by_name):
        raise CorruptionError("SETCompositionNet head order disagrees with heads")

    def ordered(name: str, expected_size: int) -> tuple[str, ...]:
        head = by_name.get(name)
        values = head.get("ordered_names") if isinstance(head, dict) else None
        if not isinstance(values, list) or len(values) != expected_size or any(not isinstance(item, str) for item in values):
            raise CorruptionError(f"contract head {name} lacks an ordered catalog")
        if len(set(values)) != len(values):
            raise CorruptionError(f"contract head {name} has duplicate names")
        return tuple(values)

    issues = ordered("issue_logits", 8)
    actions = ordered("action_utility_logits", 26)
    deltas = ordered("continuous_target_deltas", 5)
    required_issues = {"subject_too_close_to_edge", "horizon_distracts"}
    required_actions = {
        "shift_frame_left", "shift_frame_right", "shift_frame_up", "shift_frame_down",
        "step_back", "step_closer", "level_horizon", "keep_current_setup",
    }
    if not required_issues.issubset(issues) or not required_actions.issubset(actions):
        raise CorruptionError("contract target catalogs lack required frozen recipe labels")
    if set(deltas) != {"delta_x", "delta_y", "scale_delta", "light_delta", "horizon_delta"}:
        raise CorruptionError("contract continuous target catalog is not the frozen five-element order")
    return contract, _sha256_bytes(raw), issues, actions, deltas


def _load_geometry_schema() -> tuple[dict[str, Any], str]:
    schema, raw = _read_json(GEOMETRY_SCHEMA_PATH, "silver geometry schema")
    if not isinstance(schema, dict) or schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        raise CorruptionError("silver geometry schema is not a closed JSON object schema")
    properties = schema.get("properties")
    required = schema.get("required")
    if not isinstance(properties, dict) or not isinstance(required, list):
        raise CorruptionError("silver geometry schema lacks properties/required")
    schema_id = properties.get("schema_id")
    schema_version = properties.get("schema_version")
    if not isinstance(schema_id, dict) or not isinstance(schema_version, dict) or schema_id.get("const") != "camera-silver-geometry-v1" or schema_version.get("const") != "1.0.0":
        raise CorruptionError("silver geometry schema has unexpected identity")
    return schema, _sha256_bytes(raw)


def _load_pair_schema(
    semantics_sha256: str,
    issue_names: tuple[str, ...],
    action_names: tuple[str, ...],
    delta_names: tuple[str, ...],
) -> str:
    schema, raw = _read_json(PAIR_SCHEMA_PATH, "silver action-pair schema")
    schema_id = schema.get("$id") if isinstance(schema, dict) else None
    if not isinstance(schema, dict) or not isinstance(schema_id, str) or not schema_id.endswith("silver-action-pair-schema.json"):
        raise CorruptionError("silver action-pair schema is malformed")
    if schema.get("x-semantics") != SEMANTICS or schema.get("x-semantics-sha256") != semantics_sha256:
        raise CorruptionError("silver action-pair schema semantics are not frozen to this generator")
    definitions = schema.get("$defs")
    expected_catalogs = {
        "issueHead": issue_names,
        "actionHead": action_names,
        "continuousHead": delta_names,
    }
    def catalog(name: str) -> Any:
        definition = definitions.get(name) if isinstance(definitions, dict) else None
        properties = definition.get("properties") if isinstance(definition, dict) else None
        ordered = properties.get("ordered_names") if isinstance(properties, dict) else None
        return ordered.get("const") if isinstance(ordered, dict) else None
    if not isinstance(definitions, dict) or any(catalog(name) != list(values) for name, values in expected_catalogs.items()):
        raise CorruptionError("silver action-pair schema catalogs disagree with SETCompositionNet")
    return _sha256_bytes(raw)


def _validate_inventory(rows: list[dict[str, Any]], source_root: Path) -> list[dict[str, Any]]:
    allowed = {
        "byte_count", "format", "height", "human_gold", "intake_tier", "relative_path",
        "release_admissible", "sha256", "source_id", "source_record_id", "upstream_metadata", "width",
    }
    required = allowed - {"upstream_metadata"}
    seen_keys: set[tuple[str, str]] = set()
    seen_paths: set[str] = set()
    output: list[dict[str, Any]] = []
    for index, row in enumerate(rows, 1):
        unknown = set(row) - allowed
        missing = required - set(row)
        if unknown:
            raise CorruptionError(f"inventory line {index} has unknown fields: {sorted(unknown)}")
        if missing:
            raise CorruptionError(f"inventory line {index} is missing fields: {sorted(missing)}")
        source_id = row["source_id"]
        record_id = row["source_record_id"]
        if not isinstance(source_id, str) or not SAFE_ID_RE.fullmatch(source_id) or any(c.isspace() or ord(c) < 32 for c in source_id):
            raise CorruptionError(f"invalid inventory source_id at line {index}")
        if not isinstance(record_id, str) or not SAFE_ID_RE.fullmatch(record_id) or "/" in record_id or "\\" in record_id or any(c.isspace() or ord(c) < 32 for c in record_id):
            raise CorruptionError(f"invalid inventory source_record_id at line {index}")
        key = (source_id, record_id)
        if key in seen_keys:
            raise CorruptionError(f"duplicate inventory source record: {source_id}/{record_id}")
        path, relative = _safe_relative(source_root, row["relative_path"], "inventory relative_path")
        if relative in seen_paths:
            raise CorruptionError(f"duplicate inventory relative_path: {relative}")
        digest = row["sha256"]
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            raise CorruptionError(f"inventory sha256 is invalid at line {index}")
        byte_count = _int(row["byte_count"], "inventory byte_count", 1)
        width = _int(row["width"], "inventory width", 1)
        height = _int(row["height"], "inventory height", 1)
        if width > MAX_WIDTH or height > MAX_HEIGHT or width * height > MAX_PIXELS:
            raise CorruptionError(f"inventory dimensions exceed decoder limits: {relative}")
        fmt = row["format"]
        if not isinstance(fmt, str) or not FORMAT_RE.fullmatch(fmt.lower()):
            raise CorruptionError(f"inventory format is invalid at line {index}")
        if row["intake_tier"] != "research_only" or row["human_gold"] is not False or row["release_admissible"] is not False:
            raise CorruptionError(f"inventory line {index} is not immutable research-only metadata")
        if "upstream_metadata" in row:
            _reject_policy_metadata(row["upstream_metadata"])
        output.append({
            "source_id": source_id,
            "source_record_id": record_id,
            "relative_path": relative,
            "path": path,
            "sha256": digest,
            "byte_count": byte_count,
            "width": width,
            "height": height,
            "format": fmt.lower(),
        })
        seen_keys.add(key)
        seen_paths.add(relative)
    return sorted(output, key=lambda item: (item["source_id"], item["source_record_id"], item["relative_path"]))


GEOMETRY_KEYS = {
    "analysis_status", "coordinate_space", "exif_orientation", "geometry_authority", "horizon", "human_gold",
    "image", "research_only", "release_admissible", "schema_id", "schema_version", "saliency", "selection_rule",
    "selection_status", "selected_subject", "source", "subject_candidates",
}


def _validate_unit_rect(value: Any, label: str) -> tuple[float, float, float, float]:
    if not isinstance(value, dict) or not {"x", "y", "width", "height"}.issubset(value):
        raise CorruptionError(f"{label} must be an xywh object")
    x = _finite(value["x"], f"{label}.x")
    y = _finite(value["y"], f"{label}.y")
    width = _finite(value["width"], f"{label}.width")
    height = _finite(value["height"], f"{label}.height")
    if not (0 <= x < 1 and 0 <= y < 1 and 0 < width <= 1 and 0 < height <= 1 and x + width <= 1 and y + height <= 1):
        raise CorruptionError(f"{label} is outside normalized bounds")
    return x, y, width, height


def _validate_geometry(rows: list[dict[str, Any]], inventory: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    inventory_map = {(row["source_id"], row["source_record_id"]): row for row in inventory}
    output: dict[tuple[str, str], dict[str, Any]] = {}
    for index, row in enumerate(rows, 1):
        if set(row) != GEOMETRY_KEYS:
            raise CorruptionError(f"geometry line {index} has unknown or missing fields")
        if row["schema_id"] != "camera-silver-geometry-v1" or row["schema_version"] != "1.0.0":
            raise CorruptionError(f"geometry line {index} has an unknown schema")
        if row["geometry_authority"] != "silver_apple_vision" or row["research_only"] is not True or row["human_gold"] is not False or row["release_admissible"] is not False:
            raise CorruptionError(f"geometry line {index} is not silver research-only metadata")
        source = row["source"]
        if not isinstance(source, dict) or set(source) != {"relative_path", "sha256", "source_id", "source_record_id"}:
            raise CorruptionError(f"geometry line {index} source linkage is malformed")
        source_id = source.get("source_id")
        record_id = source.get("source_record_id")
        if not isinstance(source_id, str) or not isinstance(record_id, str):
            raise CorruptionError(f"geometry line {index} source identifiers are malformed")
        key = (source_id, record_id)
        inventory_row = inventory_map.get(key)
        if inventory_row is None:
            raise CorruptionError(f"geometry line {index} links an unknown inventory record")
        if source.get("relative_path") != inventory_row["relative_path"] or source.get("sha256") != inventory_row["sha256"]:
            raise CorruptionError(f"geometry line {index} disagrees with inventory linkage")
        if key in output:
            raise CorruptionError(f"duplicate geometry source record: {key[0]}/{key[1]}")

        coordinate = row["coordinate_space"]
        if not isinstance(coordinate, dict) or coordinate != {
            "axes": "x_right_y_up",
            "box_format": "normalized_xywh",
            "dimensions": "oriented_image",
            "horizon_angle_contract": HORIZON_ANGLE_CONTRACT,
            "horizon_pillow_rotation": HORIZON_PILLOW_ROTATION,
            "id": "vision_oriented_normalized",
            "origin": "bottom_left",
            "pillow_transform": VISION_PILLOW_TRANSFORM,
            "raw_pixel_preprocessing": RAW_PIXEL_PREPROCESSING,
        }:
            raise CorruptionError(f"geometry line {index} has an unsupported coordinate space")
        exif = row["exif_orientation"]
        if not isinstance(exif, dict) or set(exif) != {"applied_by_decoder", "exif_present", "name", "passed_to_vision", "passed_to_vision_exactly_once", "source", "tag"}:
            raise CorruptionError(f"geometry line {index} EXIF metadata is malformed")
        tag = _int(exif["tag"], "geometry EXIF tag", 1)
        if tag > 8 or not isinstance(exif["name"], str) or exif["name"] != ORIENTATION_NAMES[tag] or exif["applied_by_decoder"] is not False or exif["passed_to_vision"] is not True or exif["passed_to_vision_exactly_once"] is not True:
            raise CorruptionError(f"geometry line {index} EXIF metadata is inconsistent")
        if not isinstance(exif["source"], str) or exif["source"] not in {"kCGImagePropertyOrientation", "default_when_EXIF_missing"} or not isinstance(exif["exif_present"], bool):
            raise CorruptionError(f"geometry line {index} EXIF source is invalid")
        if (exif["source"] == "kCGImagePropertyOrientation") != exif["exif_present"]:
            raise CorruptionError(f"geometry line {index} EXIF source disagrees with exif_present")

        image = row["image"]
        if not isinstance(image, dict) or set(image) != {"decoded_dimensions", "format", "oriented_dimensions"}:
            raise CorruptionError(f"geometry line {index} image metadata is malformed")
        decoded = image["decoded_dimensions"]
        oriented = image["oriented_dimensions"]
        for dimensions, label in ((decoded, "decoded dimensions"), (oriented, "oriented dimensions")):
            if not isinstance(dimensions, dict) or set(dimensions) != {"height", "width"}:
                raise CorruptionError(f"geometry line {index} {label} is malformed")
            _int(dimensions["width"], f"geometry {label} width", 1)
            _int(dimensions["height"], f"geometry {label} height", 1)
        if (decoded["width"], decoded["height"]) != (inventory_row["width"], inventory_row["height"]):
            raise CorruptionError(f"geometry line {index} decoded dimensions disagree with inventory")
        if not isinstance(image["format"], str) or image["format"] not in {"avif", "bmp", "gif", "heic", "heif", "jpeg", "jp2", "png", "tiff", "webp"}:
            raise CorruptionError(f"geometry line {index} has an unknown image format")
        if not _image_format_matches(inventory_row["format"], image["format"]):
            raise CorruptionError(f"geometry line {index} format disagrees with inventory")
        expected_oriented_dimensions = (
            (decoded["height"], decoded["width"])
            if tag in {5, 6, 7, 8}
            else (decoded["width"], decoded["height"])
        )
        if (oriented["width"], oriented["height"]) != expected_oriented_dimensions:
            raise CorruptionError(f"geometry line {index} oriented dimensions disagree with EXIF tag")

        candidates = row["subject_candidates"]
        if not isinstance(candidates, list):
            raise CorruptionError(f"geometry line {index} subject_candidates is not a list")
        for candidate in candidates:
            if not isinstance(candidate, dict) or set(candidate) != {"confidence", "height", "kind", "width", "x", "y"}:
                raise CorruptionError(f"geometry line {index} candidate is malformed")
            _validate_unit_rect(candidate, f"geometry line {index} candidate")
            confidence = _finite(candidate["confidence"], "candidate confidence")
            if not 0 <= confidence <= 1 or not isinstance(candidate["kind"], str) or candidate["kind"] not in {"face", "person"}:
                raise CorruptionError(f"geometry line {index} candidate is out of range")

        selected = row["selected_subject"]
        if selected is not None:
            if not isinstance(selected, dict) or set(selected) != {"confidence", "height", "kind", "source_candidate_indices", "width", "x", "y"}:
                raise CorruptionError(f"geometry line {index} selected_subject is malformed")
            _validate_unit_rect(selected, f"geometry line {index} selected_subject")
            confidence = _finite(selected["confidence"], "selected confidence")
            source_indices = selected["source_candidate_indices"]
            if not isinstance(selected["kind"], str) or selected["kind"] not in {"face", "person"} or not 0 <= confidence <= 1 or not isinstance(source_indices, list) or not source_indices or any(type(item) is not int or item < 0 for item in source_indices) or len(set(source_indices)) != len(source_indices):
                raise CorruptionError(f"geometry line {index} selected_subject is out of range")
            if any(item >= len(candidates) for item in source_indices):
                raise CorruptionError(f"geometry line {index} selected_subject index is out of range")
        if not isinstance(row["selection_status"], str) or row["selection_status"] not in {"selected", "ambiguous", "none"} or not isinstance(row["selection_rule"], str) or row["selection_rule"] not in {
            "no_candidates", "single_candidate", "merged_person_face", "single_candidate_low_confidence", "unique_saliency_endorsement",
            "saliency_low_detection_confidence", "clear_confidence_winner", "low_detection_confidence", "confidence_tie_or_conflict",
        }:
            raise CorruptionError(f"geometry line {index} selection metadata is invalid")
        if (row["selection_status"] == "selected") != (selected is not None):
            raise CorruptionError(f"geometry line {index} selection status disagrees with selected_subject")

        horizon = row["horizon"]
        if horizon is not None:
            if not isinstance(horizon, dict) or set(horizon) != {"confidence", "observed_angle_degrees", "pillow_uprighting_rotation_degrees"}:
                raise CorruptionError(f"geometry line {index} horizon is malformed")
            angle = _finite(horizon["observed_angle_degrees"], "horizon observed angle")
            pillow_rotation = _finite(horizon["pillow_uprighting_rotation_degrees"], "horizon Pillow rotation")
            confidence = _finite(horizon["confidence"], "horizon confidence")
            if not -180 <= angle <= 180 or pillow_rotation != angle or not -180 <= pillow_rotation <= 180 or not 0 <= confidence <= 1:
                raise CorruptionError(f"geometry line {index} horizon is out of range")
        saliency = row["saliency"]
        if saliency is not None:
            if not isinstance(saliency, dict) or set(saliency) != {"center", "confidence", "region"}:
                raise CorruptionError(f"geometry line {index} saliency is malformed")
            center = saliency["center"]
            if not isinstance(center, dict) or set(center) != {"x", "y"} or not 0 <= _finite(center["x"], "saliency center x") < 1 or not 0 <= _finite(center["y"], "saliency center y") < 1:
                raise CorruptionError(f"geometry line {index} saliency center is invalid")
            _validate_unit_rect(saliency["region"], f"geometry line {index} saliency region")
            confidence = _finite(saliency["confidence"], "saliency confidence")
            if not 0 <= confidence <= 1:
                raise CorruptionError(f"geometry line {index} saliency confidence is invalid")
        if not isinstance(row["analysis_status"], str) or row["analysis_status"] not in {"complete", "vision_unavailable"}:
            raise CorruptionError(f"geometry line {index} analysis_status is invalid")
        output[key] = row
    return output


def _validate_geometry_receipt(
    geometry_path: Path,
    inventory_sha256: str,
    inventory_records: int,
    geometry_sha256: str,
    geometry_records: int,
) -> tuple[Path, str, dict[str, Any]]:
    """Validate the extractor's sibling receipt and return its binding data."""
    if geometry_path.name != "geometry.jsonl":
        raise CorruptionError("geometry path must be the extractor's geometry.jsonl")
    receipt_path = _regular_input(geometry_path.with_name("receipt.json"), "geometry receipt")
    receipt, receipt_bytes = _read_json(receipt_path, "geometry receipt")
    receipt_keys = {
        "counts", "determinism", "environment", "geometry_authority", "human_gold", "input_inventory",
        "limits", "output_geometry", "receipt_schema_id", "release_admissible", "research_only",
        "schema_version", "tool_source",
    }
    if not isinstance(receipt, dict) or set(receipt) != receipt_keys:
        raise CorruptionError("geometry receipt has unknown or missing fields")
    if (
        receipt["receipt_schema_id"] != GEOMETRY_RECEIPT_SCHEMA_ID
        or receipt["schema_version"] != "1.0.0"
        or receipt["geometry_authority"] != "silver_apple_vision"
        or receipt["determinism"] != GEOMETRY_DETERMINISM
        or receipt["human_gold"] is not False
        or receipt["research_only"] is not True
        or receipt["release_admissible"] is not False
    ):
        raise CorruptionError("geometry receipt identity or research boundary is invalid")

    def exact_mapping(value: Any, keys: set[str], label: str) -> dict[str, Any]:
        if not isinstance(value, dict) or set(value) != keys:
            raise CorruptionError(f"geometry receipt {label} is malformed")
        return value

    def nonnegative_count(value: Any, label: str) -> int:
        if type(value) is not int or value < 0:
            raise CorruptionError(f"geometry receipt {label} must be a non-negative integer")
        return value

    input_inventory = exact_mapping(receipt["input_inventory"], {"records", "sha256"}, "input_inventory")
    if (
        nonnegative_count(input_inventory["records"], "input_inventory.records") != inventory_records
        or input_inventory["sha256"] != inventory_sha256
        or not isinstance(input_inventory["sha256"], str)
        or not SHA256_RE.fullmatch(input_inventory["sha256"])
    ):
        raise CorruptionError("geometry receipt does not bind the supplied inventory")
    output_geometry = exact_mapping(receipt["output_geometry"], {"path", "records", "sha256"}, "output_geometry")
    if (
        output_geometry["path"] != "geometry.jsonl"
        or nonnegative_count(output_geometry["records"], "output_geometry.records") != geometry_records
        or output_geometry["sha256"] != geometry_sha256
        or not isinstance(output_geometry["sha256"], str)
        or not SHA256_RE.fullmatch(output_geometry["sha256"])
    ):
        raise CorruptionError("geometry receipt does not bind the supplied geometry JSONL")

    limits = exact_mapping(receipt["limits"], {"max_records", "processed_records"}, "limits")
    max_records = limits["max_records"]
    if max_records is not None and (type(max_records) is not int or max_records < 1):
        raise CorruptionError("geometry receipt limits.max_records is invalid")
    if nonnegative_count(limits["processed_records"], "limits.processed_records") != geometry_records:
        raise CorruptionError("geometry receipt processed-record count disagrees with geometry")
    if max_records is not None and max_records < geometry_records:
        raise CorruptionError("geometry receipt max_records is below processed records")

    counts = exact_mapping(receipt["counts"], {"analysis_status", "horizon", "records", "saliency", "selection_status"}, "counts")
    if nonnegative_count(counts["records"], "counts.records") != geometry_records:
        raise CorruptionError("geometry receipt counts.records disagrees with geometry")
    analysis = exact_mapping(counts["analysis_status"], {"complete", "vision_unavailable"}, "counts.analysis_status")
    horizon = exact_mapping(counts["horizon"], {"available", "unavailable"}, "counts.horizon")
    saliency = exact_mapping(counts["saliency"], {"available", "unavailable"}, "counts.saliency")
    selection = exact_mapping(counts["selection_status"], {"selected", "ambiguous", "none"}, "counts.selection_status")
    for label, values in (("analysis_status", analysis), ("horizon", horizon), ("saliency", saliency), ("selection_status", selection)):
        if sum(nonnegative_count(value, f"counts.{label}.{key}") for key, value in values.items()) != geometry_records:
            raise CorruptionError(f"geometry receipt counts.{label} does not sum to records")

    environment = exact_mapping(
        receipt["environment"],
        {"os_version", "os_version_components", "platform", "vision_framework", "vision_request_family", "vision_request_revisions"},
        "environment",
    )
    if not isinstance(environment["os_version"], str) or not environment["os_version"] or environment["platform"] != "macOS":
        raise CorruptionError("geometry receipt environment identity is invalid")
    components = exact_mapping(environment["os_version_components"], {"major", "minor", "patch"}, "environment.os_version_components")
    for key, value in components.items():
        if type(value) is not int or value < 0:
            raise CorruptionError(f"geometry receipt environment component is invalid: {key}")
    framework = exact_mapping(environment["vision_framework"], {"bundle_identifier", "name", "version"}, "environment.vision_framework")
    if framework["bundle_identifier"] != "com.apple.Vision" or framework["name"] != "Vision" or not isinstance(framework["version"], str) or not framework["version"]:
        raise CorruptionError("geometry receipt Vision framework identity is invalid")
    if environment["vision_request_family"] != list(VISION_REQUEST_FAMILY):
        raise CorruptionError("geometry receipt Vision request family is not the frozen extractor set")
    revisions = exact_mapping(environment["vision_request_revisions"], set(VISION_REQUEST_FAMILY), "environment.vision_request_revisions")
    for request, revision in revisions.items():
        if type(revision) is not int or revision < 1:
            raise CorruptionError(f"geometry receipt Vision request revision is invalid: {request}")

    tool_source = exact_mapping(receipt["tool_source"], {"path", "sha256"}, "tool_source")
    if tool_source["path"] != GEOMETRY_TOOL_RELATIVE_PATH or not isinstance(tool_source["sha256"], str) or not SHA256_RE.fullmatch(tool_source["sha256"]):
        raise CorruptionError("geometry receipt tool source binding is malformed")
    tool_path = _regular_input(ROOT / GEOMETRY_TOOL_RELATIVE_PATH, "geometry extractor source")
    if _sha256_file(tool_path) != tool_source["sha256"]:
        raise CorruptionError("geometry receipt tool source hash does not match the repository")
    receipt_sha256 = _sha256_bytes(receipt_bytes)
    binding = {
        "path": "receipt.json",
        "sha256": receipt_sha256,
        "schema_id": receipt["receipt_schema_id"],
        "schema_version": receipt["schema_version"],
        "determinism": receipt["determinism"],
        "environment": environment,
        "tool_source": tool_source,
    }
    return receipt_path, receipt_sha256, binding


def _stable_unit(seed: int, *parts: str) -> float:
    payload = "\0".join((str(seed), *parts)).encode("utf-8")
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "big") / float(1 << 64)


def _stable_bit(seed: int, *parts: str) -> int:
    payload = "\0".join((str(seed), *parts)).encode("utf-8")
    return hashlib.sha256(payload).digest()[8] & 1


def _top_left_roi(selected: Mapping[str, Any]) -> tuple[float, float, float, float]:
    x, y, width, height = _validate_unit_rect(selected, "selected subject")
    return x, 1.0 - y - height, width, height


def _roi_corners(roi: tuple[float, float, float, float]) -> list[tuple[float, float]]:
    x, y, width, height = roi
    return [(x, y), (x + width, y), (x, y + height), (x + width, y + height)]


def _bounds_from_corners(corners: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    xs = [item[0] for item in corners]
    ys = [item[1] for item in corners]
    return min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)


def _crop_roi(roi: tuple[float, float, float, float], window: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    x, y, width, height = roi
    left, top, right, bottom = window
    crop_width = right - left
    crop_height = bottom - top
    transformed = ((x - left) / crop_width, (y - top) / crop_height, width / crop_width, height / crop_height)
    if not all(math.isfinite(item) for item in transformed):
        raise CorruptionError("analytic ROI is non-finite")
    return transformed


def _assert_roi(roi: tuple[float, float, float, float], label: str, *, strict_gap: float | None = None) -> None:
    x, y, width, height = roi
    if not (0 <= x <= 1 and 0 <= y <= 1 and width > 0 and height > 0 and x + width <= 1 + 1e-9 and y + height <= 1 + 1e-9):
        raise CorruptionError(f"{label} is outside normalized frame")
    if strict_gap is not None:
        gaps = (x, 1 - x - width, y, 1 - y - height)
        if any(gap <= strict_gap for gap in gaps):
            raise CorruptionError(f"{label} does not preserve the required edge gap")


def _target_vectors(
    issue_names: tuple[str, ...],
    action_names: tuple[str, ...],
    delta_names: tuple[str, ...],
    issue: str,
    positive_action: str,
    forbidden_actions: tuple[str, ...],
    delta_name: str,
    delta: float,
) -> dict[str, Any]:
    issue_values = [0] * len(issue_names)
    issue_mask = [0] * len(issue_names)
    issue_index = issue_names.index(issue)
    issue_values[issue_index] = 1
    issue_mask[issue_index] = 1
    action_values = [0] * len(action_names)
    action_mask = [0] * len(action_names)
    positive_index = action_names.index(positive_action)
    action_values[positive_index] = 1
    action_mask[positive_index] = 1
    for action in forbidden_actions:
        forbidden_index = action_names.index(action)
        if forbidden_index == positive_index:
            raise CorruptionError("positive and forbidden action overlap")
        action_mask[forbidden_index] = 1
    delta_values = [0.0] * len(delta_names)
    delta_mask = [0] * len(delta_names)
    delta_index = delta_names.index(delta_name)
    if not math.isfinite(delta) or not -1 <= delta <= 1:
        raise CorruptionError("target delta is outside the frozen normalized range")
    delta_values[delta_index] = float(delta)
    delta_mask[delta_index] = 1
    return {
        "issue": {"ordered_names": list(issue_names), "values": issue_values, "mask": issue_mask},
        "action": {"ordered_names": list(action_names), "values": action_values, "mask": action_mask},
        "continuous": {"ordered_names": list(delta_names), "values": delta_values, "mask": delta_mask},
    }


def _image_format_matches(declared: str, actual: str) -> bool:
    declared = declared.lower()
    actual = actual.lower()
    return actual == "jpeg" if declared in {"jpg", "jpeg"} else declared == actual


def _canonical_source_image(entry: Mapping[str, Any], geometry: Mapping[str, Any]) -> Image.Image:
    path = entry["path"]
    try:
        encoded = path.read_bytes()
    except OSError as exc:
        raise CorruptionError(f"cannot read source image: {entry['relative_path']}") from exc
    if len(encoded) != entry["byte_count"] or _sha256_bytes(encoded) != entry["sha256"]:
        raise CorruptionError(f"source image hash/byte_count mismatch: {entry['relative_path']}")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(encoded)) as opened:
                opened.verify()
            with Image.open(BytesIO(encoded)) as opened:
                frame_count = getattr(opened, "n_frames", 1)
                if type(frame_count) is not int or frame_count != 1:
                    raise CorruptionError(f"source image must contain one frame: {entry['relative_path']}")
                if (opened.width, opened.height) != (entry["width"], entry["height"]):
                    raise CorruptionError(f"source image dimensions disagree with inventory: {entry['relative_path']}")
                actual_format = str(opened.format or "").lower()
                if not _image_format_matches(entry["format"], actual_format):
                    raise CorruptionError(f"source image format disagrees with inventory: {entry['relative_path']}")
                raw_pillow_exif_tag = opened.getexif().get(274)
                # ImageIO normalizes malformed orientation values (for
                # example 0) to `.up`; Pillow exposes the invalid raw value
                # and performs no transpose. Canonicalize that equivalent
                # no-op to tag 1, while still rejecting disagreement between
                # valid 1...8 values and the Vision receipt.
                exif_tag = raw_pillow_exif_tag if type(raw_pillow_exif_tag) is int and 1 <= raw_pillow_exif_tag <= 8 else 1
                expected_tag = geometry["exif_orientation"]["tag"]
                if exif_tag != expected_tag:
                    raise CorruptionError(f"source image EXIF orientation disagrees with silver geometry: {entry['relative_path']}")
                opened.load()
                oriented = ImageOps.exif_transpose(opened)
                oriented.load()
                if (oriented.width, oriented.height) != (
                    geometry["image"]["oriented_dimensions"]["width"], geometry["image"]["oriented_dimensions"]["height"]
                ):
                    raise CorruptionError(f"source image oriented dimensions disagree with silver geometry: {entry['relative_path']}")
                profile = opened.info.get("icc_profile")
                if profile:
                    try:
                        source_profile = ImageCms.ImageCmsProfile(BytesIO(profile))
                        destination_profile = ImageCms.createProfile("sRGB")
                        source_space = str(source_profile.profile.xcolor_space or "").strip().upper()
                        if source_space == "RGB" and oriented.mode != "RGB":
                            oriented = oriented.convert("RGB")
                        elif source_space in {"GRAY", "GREY"} and oriented.mode != "L":
                            oriented = oriented.convert("L")
                        elif source_space == "CMYK":
                            if oriented.mode != "CMYK":
                                raise CorruptionError(
                                    f"embedded CMYK profile disagrees with image mode {oriented.mode}: {entry['relative_path']}"
                                )
                        elif source_space not in {"RGB", "GRAY", "GREY"}:
                            raise CorruptionError(
                                f"unsupported embedded ICC colour space {source_space or 'unknown'}: {entry['relative_path']}"
                            )
                        converted = ImageCms.profileToProfile(oriented, source_profile, destination_profile, outputMode="RGB")
                    except Exception as exc:
                        if isinstance(exc, CorruptionError):
                            raise
                        raise CorruptionError(f"source image ICC profile is invalid: {entry['relative_path']}") from exc
                else:
                    converted = oriented.convert("RGB")
                # Rebuild a metadata-free RGB image so orientation/profile cannot
                # be accidentally applied a second time by a later save.
                return Image.frombytes("RGB", converted.size, converted.tobytes())
    except CorruptionError:
        raise
    except (Image.DecompressionBombError, OSError, ValueError) as exc:
        raise CorruptionError(f"source image is not a deterministic media file: {entry['relative_path']}") from exc


def _rotate_derivative(
    image: Image.Image,
    roi: tuple[float, float, float, float] | None,
    angle: float,
) -> tuple[Image.Image, tuple[float, float, float, float] | None, dict[str, Any]]:
    width, height = image.size
    radians = math.radians(angle)
    c, s = abs(math.cos(radians)), abs(math.sin(radians))
    safe_factor = min(width / (width * c + height * s), height / (width * s + height * c))
    safe_width = max(1, int(math.floor(width * safe_factor)))
    safe_height = max(1, int(math.floor(height * safe_factor)))
    rotated = image.rotate(angle, resample=Image.Resampling.BILINEAR, expand=True)
    left = (rotated.width - safe_width) // 2
    top = (rotated.height - safe_height) // 2
    cropped = rotated.crop((left, top, left + safe_width, top + safe_height))
    derivative = cropped.resize((width, height), Image.Resampling.BILINEAR)
    transformed_roi = None
    if roi is not None:
        source_corners = [(x * width, y * height) for x, y in _roi_corners(roi)]
        mapped: list[tuple[float, float]] = []
        # Pillow's positive angle is a visual counter-clockwise rotation in
        # top-left image coordinates.
        for x, y in source_corners:
            dx, dy = x - width / 2, y - height / 2
            rx = math.cos(radians) * dx + math.sin(radians) * dy + rotated.width / 2
            ry = -math.sin(radians) * dx + math.cos(radians) * dy + rotated.height / 2
            mapped.append(((rx - left) / safe_width, (ry - top) / safe_height))
        transformed_roi = _bounds_from_corners(mapped)
        # The conservative safe crop should retain a central proposal.  Do not
        # claim a truncated box as the full subject ROI if a proposal is clipped.
        x, y, w, h = transformed_roi
        clipped = (max(0.0, x), max(0.0, y), min(1.0, x + w) - max(0.0, x), min(1.0, y + h) - max(0.0, y))
        if clipped[2] <= 0 or clipped[3] <= 0 or clipped != transformed_roi:
            transformed_roi = None
        else:
            _assert_roi(transformed_roi, "rotated analytic ROI")
    return derivative, transformed_roi, {
        "pillow_rotation_degrees": angle,
        "overscan": "rotate_expand_then_center_crop_to_border_free_inscribed_window",
        "safe_crop_normalized": [left / rotated.width, top / rotated.height, (left + safe_width) / rotated.width, (top + safe_height) / rotated.height],
        "interpolation": "bilinear",
    }


def _crop_window_for_edge(roi: tuple[float, float, float, float], edge: str) -> tuple[float, float, float, float]:
    x, y, width, height = roi
    target_gap = TARGET_EDGE_GAP
    # Equal normalized spans preserve the source pixel aspect ratio because
    # (span_x * source_width) / (span_y * source_height) == source_width /
    # source_height.  Select the largest feasible span: this is the least
    # zoomed reframe that reaches the configured edge pressure.
    if edge == "left":
        span = min(1.0, x / target_gap, (1.0 - x) / (1.0 - target_gap))
        left = x - target_gap * span
        top_limit = 1.0 - span
    elif edge == "right":
        span = min(1.0, (x + width) / (1.0 - target_gap), (1.0 - x - width) / target_gap)
        left = x + width - (1.0 - target_gap) * span
        top_limit = 1.0 - span
    elif edge == "top":
        span = min(1.0, y / target_gap, (1.0 - y) / (1.0 - target_gap))
        top = y - target_gap * span
        left_limit = 1.0 - span
    elif edge == "bottom":
        span = min(1.0, (y + height) / (1.0 - target_gap), (1.0 - y - height) / target_gap)
        top = y + height - (1.0 - target_gap) * span
        left_limit = 1.0 - span
    else:
        raise CorruptionError(f"unknown crop edge: {edge}")
    required_span = max(width / (1.0 - target_gap), height) if edge in {"left", "right"} else max(width, height / (1.0 - target_gap))
    if not math.isfinite(span) or span <= 0 or span + 1e-12 < required_span:
        raise CorruptionError("square crop is infeasible for selected ROI")
    if edge in {"left", "right"}:
        lower = max(0.0, y + height - span)
        upper = min(y, top_limit)
        if lower > upper + 1e-12:
            raise CorruptionError("square crop is infeasible for selected ROI")
        top = min(max(y + height / 2.0 - span / 2.0, lower), upper)
    else:
        lower = max(0.0, x + width - span)
        upper = min(x, left_limit)
        if lower > upper + 1e-12:
            raise CorruptionError("square crop is infeasible for selected ROI")
        left = min(max(x + width / 2.0 - span / 2.0, lower), upper)
    window = (left, top, left + span, top + span)
    if not (0 <= window[0] < window[2] <= 1 and 0 <= window[1] < window[3] <= 1):
        raise CorruptionError("square crop is infeasible for selected ROI")
    return window


def _transform_extent(image: Image.Image, window: tuple[float, float, float, float]) -> Image.Image:
    left, top, right, bottom = window
    if not (0 <= left < right <= 1 and 0 <= top < bottom <= 1):
        raise CorruptionError("crop extent is outside source image")
    width, height = image.size
    return image.transform(
        (width, height),
        Image.Transform.EXTENT,
        (left * width, top * height, right * width, bottom * height),
        resample=Image.Resampling.BILINEAR,
    )


def _translate_derivative(
    image: Image.Image,
    roi: tuple[float, float, float, float],
    edge: str,
) -> tuple[Image.Image, tuple[float, float, float, float], dict[str, Any]]:
    window = _crop_window_for_edge(roi, edge)
    derivative = _transform_extent(image, window)
    transformed_roi = _crop_roi(roi, window)
    _assert_roi(transformed_roi, "translated analytic ROI")
    gaps = {
        "left": transformed_roi[0],
        "right": 1 - transformed_roi[0] - transformed_roi[2],
        "top": transformed_roi[1],
        "bottom": 1 - transformed_roi[1] - transformed_roi[3],
    }
    if gaps[edge] > 0.03 or min(gaps.values()) < -1e-9:
        raise CorruptionError("translated derivative did not cross its configured edge threshold")
    span_x = window[2] - window[0]
    span_y = window[3] - window[1]
    if abs(span_x - span_y) > 1e-12:
        raise CorruptionError("translated derivative crop is anisotropic")
    source_center = (roi[0] + roi[2] / 2, roi[1] + roi[3] / 2)
    derivative_center = (transformed_roi[0] + transformed_roi[2] / 2, transformed_roi[1] + transformed_roi[3] / 2)
    delta_x = source_center[0] - derivative_center[0]
    delta_y = source_center[1] - derivative_center[1]
    return derivative, transformed_roi, {
        "edge": edge,
        "target_edge_gap": TARGET_EDGE_GAP,
        "crop_window_normalized": list(window),
        "crop_span_normalized": {"x": span_x, "y": span_y},
        "pixel_aspect_preserved": True,
        "interpolation": "bilinear",
        "desired_subject_displacement": {"x": delta_x, "y": delta_y},
    }


def _zoom_window(roi: tuple[float, float, float, float], scale: float) -> tuple[float, float, float, float]:
    x, y, width, height = roi
    if not math.isfinite(scale) or scale <= 1.0:
        raise CorruptionError("zoom scale must be greater than one")
    crop_span = 1.0 / scale
    # Keep every transformed ROI edge strictly outside the minimum gap.  The
    # tiny margin avoids a nominal 0.03 value being rejected after floating
    # point arithmetic while retaining the declared pressure-band semantics.
    minimum_gap = ZOOM_PRESSURE_MIN_GAP + 1e-6

    def axis_range(start: float, size: float) -> tuple[float, float]:
        lower = max(0.0, start + size - (1.0 - minimum_gap) * crop_span)
        upper = min(1.0 - crop_span, start - minimum_gap * crop_span)
        if lower > upper + 1e-12:
            raise CorruptionError("zoom crop cannot keep selected ROI fully visible")
        return lower, upper

    left_range = axis_range(x, width)
    top_range = axis_range(y, height)
    # The minimum edge gap is attained at a boundary of each axis range.  Try
    # all four corners and choose the most edge-pressured valid crop.  If even
    # that crop does not enter the configured band, the recipe is skipped.
    candidates = [
        (left, top)
        for left in left_range
        for top in top_range
    ]

    def minimum_edge_gap(left: float, top: float) -> float:
        transformed = _crop_roi(roi, (left, top, left + crop_span, top + crop_span))
        return min(
            transformed[0], 1.0 - transformed[0] - transformed[2],
            transformed[1], 1.0 - transformed[1] - transformed[3],
        )

    left, top = min(candidates, key=lambda candidate: (minimum_edge_gap(*candidate), candidate[0], candidate[1]))
    return left, top, left + crop_span, top + crop_span


def _zoom_derivative(
    image: Image.Image,
    roi: tuple[float, float, float, float],
    scale: float,
) -> tuple[Image.Image, tuple[float, float, float, float], dict[str, Any]]:
    area = roi[2] * roi[3]
    if area < 0.005 or area > 0.70 or roi[2] > 0.90 or roi[3] > 0.90:
        raise CorruptionError("initial subject area is not sensible for crop_zoom_in")
    window = _zoom_window(roi, scale)
    derivative = _transform_extent(image, window)
    transformed_roi = _crop_roi(roi, window)
    _assert_roi(transformed_roi, "zoomed analytic ROI", strict_gap=ZOOM_PRESSURE_MIN_GAP)
    final_edge_gap = min(
        transformed_roi[0], 1 - transformed_roi[0] - transformed_roi[2], transformed_roi[1], 1 - transformed_roi[1] - transformed_roi[3]
    )
    if final_edge_gap > ZOOM_PRESSURE_MAX_GAP + 1e-12:
        raise CorruptionError("zoomed analytic ROI did not reach edge-pressure band")
    actual_scale = scale
    return derivative, transformed_roi, {
        "linear_scale": actual_scale,
        "final_edge_gap_minimum": final_edge_gap,
        "edge_pressure_band": [ZOOM_PRESSURE_MIN_GAP, ZOOM_PRESSURE_MAX_GAP],
        "crop_window_normalized": list(window),
        "interpolation": "bilinear",
    }


def _pair_id(entry: Mapping[str, Any], recipe: str, variant: str) -> str:
    key = "\0".join((entry["source_id"], entry["source_record_id"], entry["sha256"], recipe, variant))
    return "pair_" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:40]


def _source_family_id(entry: Mapping[str, Any]) -> str:
    key = "\0".join((entry["source_id"], entry["source_record_id"], entry["sha256"]))
    return "family_" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:32]


def _make_pair(
    entry: Mapping[str, Any],
    geometry: Mapping[str, Any],
    image: Image.Image,
    recipe: str,
    variant: str,
    derivative: Image.Image,
    source_roi: tuple[float, float, float, float] | None,
    derivative_roi: tuple[float, float, float, float] | None,
    parameters: dict[str, Any],
    targets: dict[str, Any],
    geometry_sha256: str,
    geometry_schema_sha256: str,
    semantics_sha256: str,
    issue_projection: str | None = None,
) -> tuple[dict[str, Any], bytes]:
    buffer = BytesIO()
    derivative.save(buffer, format="PNG", optimize=False, compress_level=9)
    encoded = buffer.getvalue()
    pair_id = _pair_id(entry, recipe, variant)
    family = _source_family_id(entry)
    relative_media = f"images/{pair_id}.png"
    pair: dict[str, Any] = {
        "schema_id": PAIR_SCHEMA_ID,
        "schema_version": PAIR_SCHEMA_VERSION,
        "pair_id": pair_id,
        "source_family_id": family,
        "derivation_family_id": family,
        "split": RESEARCH_SPLIT,
        "is_independent": False,
        "counts_toward_quota": False,
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "source": {
            "source_id": entry["source_id"],
            "source_record_id": entry["source_record_id"],
            "relative_path": entry["relative_path"],
            "sha256": entry["sha256"],
            "width": entry["width"],
            "height": entry["height"],
            "format": entry["format"],
        },
        "derivative": {
            "relative_path": relative_media,
            "sha256": _sha256_bytes(encoded),
            "width": derivative.width,
            "height": derivative.height,
            "format": "png",
        },
        "recipe": {"name": recipe, "version": "camera-corruption-v1", "parameters": parameters},
        "roi": {
            "coordinate_space": "oriented_full_frame_top_left_normalized",
            "transform": "analytic",
            "source_xywh": list(source_roi) if source_roi is not None else None,
            "derivative_xywh": list(derivative_roi) if derivative_roi is not None else None,
        },
        "geometry": {
            "provider": "silver_apple_vision",
            "runtime": "conditional_on_captured_apple_os_vision_runtime",
            "sha256": geometry_sha256,
            "schema_id": geometry["schema_id"],
            "schema_version": geometry["schema_version"],
            "schema_sha256": geometry_schema_sha256,
            "source_record_id": entry["source_record_id"],
        },
        "targets": targets,
        "semantics_sha256": semantics_sha256,
    }
    if issue_projection is not None:
        pair["issue_projection"] = issue_projection
    return pair, encoded


def _initial_edge_gaps(roi: tuple[float, float, float, float]) -> dict[str, float]:
    x, y, width, height = roi
    return {"left": x, "right": 1 - x - width, "top": y, "bottom": 1 - y - height}


def _candidate_for_entry(
    entry: Mapping[str, Any],
    geometry: Mapping[str, Any],
    image: Image.Image,
    seed: int,
    issue_names: tuple[str, ...],
    action_names: tuple[str, ...],
    delta_names: tuple[str, ...],
    geometry_sha256: str,
    geometry_schema_sha256: str,
    semantics_sha256: str,
    emit: Callable[[dict[str, Any], bytes], None],
    max_per_source: int | None,
) -> dict[str, int]:
    key = f"{entry['source_id']}:{entry['source_record_id']}"
    skips: dict[str, int] = {}
    emitted = 0

    def emit_pair(pair: dict[str, Any], encoded: bytes) -> None:
        nonlocal emitted
        if max_per_source is not None and emitted >= max_per_source:
            return
        emit(pair, encoded)
        emitted += 1

    def skipped(reason: str) -> None:
        skips[reason] = skips.get(reason, 0) + 1

    selected = geometry["selected_subject"]
    roi = _top_left_roi(selected) if selected is not None else None
    if roi is not None:
        _assert_roi(roi, "selected subject ROI")
    if geometry["analysis_status"] == "vision_unavailable":
        skipped("vision_unavailable")
    else:
        horizon = geometry["horizon"]
        if horizon is None:
            skipped("horizon_unavailable")
        elif horizon["confidence"] < 0.65:
            skipped("horizon_confidence_below_0.65")
        elif abs(horizon["observed_angle_degrees"]) > 2.0:
            skipped("horizon_baseline_abs_above_2_degrees")
        else:
            magnitude = 6.0 + 6.0 * _stable_unit(seed, key, "rotate_horizon", "magnitude")
            sign = 1.0 if _stable_bit(seed, key, "rotate_horizon", "sign") else -1.0
            tilt_delta = sign * magnitude
            baseline = float(horizon["observed_angle_degrees"])
            if abs(baseline + tilt_delta) < 6.0:
                tilt_delta = math.copysign(6.0 + abs(baseline), tilt_delta)
            actual_tilt = baseline + tilt_delta
            if not 6.0 <= abs(actual_tilt):
                raise CorruptionError("rotate_horizon derivative tilt did not cross 6 degrees")
            # Geometry's positive observed tilt is leveled by the same
            # positive Pillow rotation, so corruption uses the inverse sign.
            pillow_rotation = -tilt_delta
            derivative, derivative_roi, parameters = _rotate_derivative(image, roi, pillow_rotation)
            parameters.update({
                "observed_tilt_delta_degrees": tilt_delta,
                "source_horizon_angle_degrees": baseline,
                "derivative_horizon_angle_degrees": actual_tilt,
                "horizon_correction_degrees": -actual_tilt,
            })
            targets = _target_vectors(issue_names, action_names, delta_names, "horizon_distracts", "level_horizon", ("keep_current_setup",), "horizon_delta", -actual_tilt / 180.0)
            pair, encoded = _make_pair(entry, geometry, image, "rotate_horizon", f"{tilt_delta:+.6f}", derivative, roi, derivative_roi, parameters, targets, geometry_sha256, geometry_schema_sha256, semantics_sha256)
            emit_pair(pair, encoded)

    if selected is None:
        skipped("no_selected_subject")
    elif geometry["analysis_status"] == "vision_unavailable":
        skipped("subject_geometry_unavailable")
    elif selected["confidence"] < 0.70:
        skipped("selected_subject_confidence_below_0.70")
    elif selected["kind"] not in {"face", "person"}:
        skipped("selected_subject_kind_unsupported")
    else:
        gaps = _initial_edge_gaps(roi)
        eligible_edges = []
        for edge in ("left", "right", "top", "bottom"):
            if gaps[edge] < 0.12:
                continue
            try:
                _crop_window_for_edge(roi, edge)
            except CorruptionError:
                continue
            eligible_edges.append(edge)
        if not eligible_edges:
            skipped("no_feasible_square_crop")
        else:
            edge_index = int(_stable_unit(seed, key, "crop_translate", "edge") * len(eligible_edges))
            edge = eligible_edges[min(edge_index, len(eligible_edges) - 1)]
            try:
                derivative, derivative_roi, parameters = _translate_derivative(image, roi, edge)
            except CorruptionError as exc:
                if "threshold" in str(exc):
                    skipped("translated_edge_threshold_not_reached")
                else:
                    raise
            else:
                delta_x = parameters["desired_subject_displacement"]["x"]
                delta_y = parameters["desired_subject_displacement"]["y"]
                if edge == "left" and delta_x <= 0 or edge == "right" and delta_x >= 0 or edge == "top" and delta_y <= 0 or edge == "bottom" and delta_y >= 0:
                    raise CorruptionError("crop_translate delta sign disagrees with configured edge")
                action = {"left": "shift_frame_left", "right": "shift_frame_right", "top": "shift_frame_up", "bottom": "shift_frame_down"}[edge]
                opposite = {"left": "shift_frame_right", "right": "shift_frame_left", "top": "shift_frame_down", "bottom": "shift_frame_up"}[edge]
                delta_name = "delta_x" if edge in {"left", "right"} else "delta_y"
                delta_value = delta_x if delta_name == "delta_x" else delta_y
                issue_projection = None
                targets = _target_vectors(issue_names, action_names, delta_names, "subject_too_close_to_edge", action, (opposite, "keep_current_setup"), delta_name, delta_value)
                pair, encoded = _make_pair(entry, geometry, image, "crop_translate", edge, derivative, roi, derivative_roi, parameters, targets, geometry_sha256, geometry_schema_sha256, semantics_sha256, issue_projection)
                emit_pair(pair, encoded)

        scale = ZOOM_MIN + (ZOOM_MAX - ZOOM_MIN) * _stable_unit(seed, key, "crop_zoom_in", "scale")
        try:
            derivative, derivative_roi, parameters = _zoom_derivative(image, roi, scale)
        except CorruptionError as exc:
            if "initial subject area" in str(exc):
                reason = "initial_area_not_sensible"
            elif "edge-pressure band" in str(exc):
                reason = "zoom_edge_pressure_band_not_reached"
            else:
                reason = "zoom_final_edge_gap_or_extent_invalid"
            skipped(reason)
        else:
            targets = _target_vectors(issue_names, action_names, delta_names, "subject_too_close_to_edge", "step_back", ("step_closer", "keep_current_setup"), "scale_delta", -math.log2(scale))
            pair, encoded = _make_pair(entry, geometry, image, "crop_zoom_in", f"{scale:.6f}", derivative, roi, derivative_roi, parameters, targets, geometry_sha256, geometry_schema_sha256, semantics_sha256)
            emit_pair(pair, encoded)
    return skips


def _stream_sorted_pairs(metadata_dir: Path, staging: Path) -> tuple[int, str, str]:
    """Stream small staged pair metadata into sorted JSONL without retaining images."""
    try:
        metadata_names = sorted(item.name for item in metadata_dir.iterdir())
    except OSError as exc:
        raise CorruptionError("cannot enumerate staged pair metadata") from exc
    manifest_path = staging / "pairs.jsonl"
    temporary: Path | None = None
    manifest_digest = hashlib.sha256()
    media_digest = hashlib.sha256()
    count = 0
    try:
        fd, name = tempfile.mkstemp(prefix=f".{manifest_path.name}.", suffix=".tmp", dir=manifest_path.parent)
        temporary = Path(name)
        with os.fdopen(fd, "wb") as stream:
            for name in metadata_names:
                metadata_path = metadata_dir / name
                if not re.fullmatch(r"^pair_[0-9a-f]{40}\.json$", name):
                    raise CorruptionError("staged pair metadata has an unsafe name")
                _regular_input(metadata_path, "staged pair metadata")
                pair, _ = _read_json(metadata_path, "staged pair metadata")
                if not isinstance(pair, dict) or pair.get("pair_id") != name[:-5]:
                    raise CorruptionError("staged pair metadata is malformed")
                derivative = pair.get("derivative")
                if not isinstance(derivative, dict):
                    raise CorruptionError("staged pair derivative metadata is malformed")
                media_path, relative_media = _safe_relative(staging, derivative.get("relative_path"), "staged derivative path")
                if relative_media != derivative.get("relative_path") or not relative_media.startswith("images/"):
                    raise CorruptionError("staged derivative path is outside images")
                media_sha256 = _sha256_file(media_path)
                if media_sha256 != derivative.get("sha256"):
                    raise CorruptionError("staged derivative hash disagrees with metadata")
                encoded = _json_bytes(pair)
                stream.write(encoded)
                manifest_digest.update(encoded)
                media_digest.update(
                    f"{relative_media}\0{derivative['sha256']}\0{derivative['width']}\0{derivative['height']}\n".encode("utf-8")
                )
                count += 1
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, manifest_path)
        temporary = None
    except CorruptionError:
        raise
    except (OSError, KeyError, TypeError) as exc:
        raise CorruptionError("cannot stream sorted pair manifest") from exc
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return count, manifest_digest.hexdigest(), media_digest.hexdigest()


def _require_generated_pairs(pair_count: int, skip_reasons: Mapping[str, int]) -> None:
    """Refuse to publish a generation that produced no pair at all.

    Every entry may legitimately be skipped (no selected subject, vision
    unavailable), but the sum of those skips is not a passed generation: without
    this check the run published an empty `pairs.jsonl` and still printed PASS
    with `pairs=0`, which reads as "corruption generation done".
    """
    if pair_count == 0:
        reasons = ", ".join(f"{name}={count}" for name, count in sorted(skip_reasons.items())) or "none recorded"
        raise CorruptionError(
            f"no corruption pairs were generated (skips: {reasons}); refusing to publish an empty generation")


def _atomic_write(path: Path, data: bytes) -> None:
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except OSError as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise CorruptionError(f"cannot atomically write {path.name}") from exc


def _fsync_directory(path: Path) -> None:
    try:
        descriptor = os.open(path, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError:
        pass


def _publish(staging: Path, output: Path) -> None:
    parent = output.parent
    backup: Path | None = None
    try:
        if output.exists() or output.is_symlink():
            if output.is_symlink() or not output.is_dir() or any(output.iterdir()):
                raise CorruptionError("output-root must remain an empty regular directory")
            backup = parent / f".{output.name}.empty-backup-{os.getpid()}"
            if backup.exists() or backup.is_symlink():
                raise CorruptionError("output-root has an unsafe backup collision")
            os.replace(output, backup)
            try:
                os.replace(staging, output)
            except Exception:
                os.replace(backup, output)
                backup = None
                raise
            _fsync_directory(parent)
            shutil.rmtree(backup)
            backup = None
        else:
            os.replace(staging, output)
            _fsync_directory(parent)
    except CorruptionError:
        raise
    except OSError as exc:
        raise CorruptionError("cannot atomically publish output-root") from exc
    finally:
        if backup is not None and backup.exists():
            shutil.rmtree(backup, ignore_errors=True)


def _run(
    inventory_path: Path,
    geometry_path: Path,
    source_root_input: Path,
    output_root_input: Path,
    seed: int,
    max_per_source: int | None,
) -> dict[str, Any]:
    if Image.__version__ != PILLOW_VERSION_PIN:
        raise CorruptionError(f"Pillow runtime {Image.__version__} does not match pinned {PILLOW_VERSION_PIN}")
    inventory_path = _regular_input(inventory_path, "inventory")
    geometry_path = _regular_input(geometry_path, "geometry")
    source_root = _external_directory(source_root_input, "source-root", must_exist=True)
    output_root = _external_directory(output_root_input, "output-root", must_exist=False)
    if source_root == output_root or source_root in output_root.parents or output_root in source_root.parents:
        raise CorruptionError("source-root and output-root must be separate")
    if max_per_source is not None and (type(max_per_source) is not int or max_per_source < 1):
        raise CorruptionError("--max-per-source must be a positive integer")
    contract, contract_sha256, issue_names, action_names, delta_names = _load_contract()
    _ = contract
    _, geometry_schema_sha256 = _load_geometry_schema()
    semantics_sha256 = _sha256_bytes(_canonical_json(SEMANTICS).encode("utf-8"))
    pair_schema_sha256 = _load_pair_schema(semantics_sha256, issue_names, action_names, delta_names)
    generator_sha256 = _sha256_file(Path(__file__))
    inventory_rows, inventory_bytes = _read_jsonl(inventory_path, "inventory")
    geometry_rows, geometry_bytes = _read_jsonl(geometry_path, "geometry")
    inventory = _validate_inventory(inventory_rows, source_root)
    geometry = _validate_geometry(geometry_rows, inventory)
    inventory_sha256 = _sha256_bytes(inventory_bytes)
    geometry_sha256 = _sha256_bytes(geometry_bytes)
    geometry_receipt_path, geometry_receipt_sha256, geometry_receipt = _validate_geometry_receipt(
        geometry_path,
        inventory_sha256,
        len(inventory_rows),
        geometry_sha256,
        len(geometry_rows),
    )
    fingerprints: dict[tuple[str, str], tuple[int, str]] = {}
    for entry in inventory:
        fingerprints[(entry["source_id"], entry["source_record_id"])] = _digest_fingerprint(entry["path"])
        if fingerprints[(entry["source_id"], entry["source_record_id"])] != (entry["byte_count"], entry["sha256"]):
            raise CorruptionError(f"source inventory hash mismatch: {entry['relative_path']}")

    # Refuse ambiguous leftovers instead of guessing whether a prior run is safe.
    staging_prefix = f".{output_root.name}.staging-"
    try:
        if output_root.parent.exists() and any(item.name.startswith(staging_prefix) for item in output_root.parent.iterdir()):
            raise CorruptionError("matching incomplete staging area exists; clean it before retrying")
    except OSError as exc:
        raise CorruptionError("cannot inspect output-root parent") from exc
    staging = Path(tempfile.mkdtemp(prefix=staging_prefix, dir=output_root.parent))
    try:
        (staging / "images").mkdir()
        metadata_dir = staging / "_pair_metadata"
        metadata_dir.mkdir()
        skip_reasons: dict[str, int] = {}
        recipe_counts: dict[str, int] = {}
        action_counts: dict[str, int] = {}

        def emit_pair(pair: dict[str, Any], encoded: bytes) -> None:
            pair_id = pair.get("pair_id")
            if not isinstance(pair_id, str) or not re.fullmatch(r"^pair_[0-9a-f]{40}$", pair_id):
                raise CorruptionError("generated pair id is malformed")
            derivative = pair.get("derivative")
            if not isinstance(derivative, dict):
                raise CorruptionError("generated derivative metadata is malformed")
            media_path, relative_media = _safe_relative(staging, derivative.get("relative_path"), "generated derivative path")
            if relative_media != derivative.get("relative_path") or not relative_media.startswith("images/"):
                raise CorruptionError("generated derivative path is outside images")
            metadata_path = metadata_dir / f"{pair_id}.json"
            if media_path.exists() or metadata_path.exists():
                raise CorruptionError("generated pair id is duplicated")
            _atomic_write(media_path, encoded)
            _atomic_write(metadata_path, _json_bytes(pair))
            recipe = pair["recipe"]["name"]
            recipe_counts[recipe] = recipe_counts.get(recipe, 0) + 1
            action_values = pair["targets"]["action"]
            for name, value, mask in zip(action_values["ordered_names"], action_values["values"], action_values["mask"]):
                if mask and value:
                    action_counts[name] = action_counts.get(name, 0) + 1

        for entry in inventory:
            key = (entry["source_id"], entry["source_record_id"])
            geom = geometry.get(key)
            if geom is None:
                skip_reasons["missing_geometry"] = skip_reasons.get("missing_geometry", 0) + 1
                continue
            image = _canonical_source_image(entry, geom)
            skips = _candidate_for_entry(
                entry, geom, image, seed, issue_names, action_names, delta_names,
                geometry_sha256, geometry_schema_sha256, semantics_sha256,
                emit_pair, max_per_source,
            )
            for reason, count in skips.items():
                skip_reasons[reason] = skip_reasons.get(reason, 0) + count
        pair_count, pair_manifest_sha256, media_aggregate_sha256 = _stream_sorted_pairs(metadata_dir, staging)
        _require_generated_pairs(pair_count, skip_reasons)
        shutil.rmtree(metadata_dir)
        receipt = {
            "schema_id": "camera-silver-action-pair-receipt-v1",
            "schema_version": PAIR_SCHEMA_VERSION,
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
            "split": RESEARCH_SPLIT,
            "seed": seed,
            "max_per_source": max_per_source,
            "inputs": {
                "inventory": {"sha256": inventory_sha256, "records": len(inventory)},
                "geometry": {
                    "sha256": geometry_sha256,
                    "schema_sha256": geometry_schema_sha256,
                    "records": len(geometry_rows),
                    "receipt_path": geometry_receipt["path"],
                    "receipt_sha256": geometry_receipt_sha256,
                },
            },
            "geometry_receipt": geometry_receipt,
            "generator_source": {"path": GENERATOR_RELATIVE_PATH, "sha256": generator_sha256},
            "contract": {"path": str(CONTRACT_PATH.relative_to(ROOT)), "sha256": contract_sha256},
            "pair_schema": {"path": str(PAIR_SCHEMA_PATH.relative_to(ROOT)), "sha256": pair_schema_sha256},
            "semantics": SEMANTICS,
            "semantics_sha256": semantics_sha256,
            "counts": {
                "sources": len(inventory),
                "geometry_records": len(geometry_rows),
                "pairs": pair_count,
                "by_recipe": dict(sorted(recipe_counts.items())),
                "by_action": dict(sorted(action_counts.items())),
                "skip_reasons": dict(sorted(skip_reasons.items())),
            },
            "output_manifest": {"path": "pairs.jsonl", "records": pair_count, "sha256": pair_manifest_sha256},
            "output_media": {"files": pair_count, "aggregate_sha256": media_aggregate_sha256},
        }
        receipt_data = _json_bytes(receipt)
        _atomic_write(staging / "receipt.json", receipt_data)
        # Re-check all trust-boundary inputs before publication.
        if _sha256_file(inventory_path) != inventory_sha256 or _sha256_file(geometry_path) != geometry_sha256 or _sha256_file(geometry_receipt_path) != geometry_receipt_sha256:
            raise CorruptionError("inventory, geometry, or geometry receipt changed during generation")
        if _sha256_file(Path(__file__)) != generator_sha256 or _sha256_file(CONTRACT_PATH) != contract_sha256 or _sha256_file(GEOMETRY_SCHEMA_PATH) != geometry_schema_sha256 or _sha256_file(PAIR_SCHEMA_PATH) != pair_schema_sha256:
            raise CorruptionError("generator or schema authority changed during generation")
        if _sha256_file(ROOT / GEOMETRY_TOOL_RELATIVE_PATH) != geometry_receipt["tool_source"]["sha256"]:
            raise CorruptionError("geometry extractor source changed during generation")
        for entry in inventory:
            key = (entry["source_id"], entry["source_record_id"])
            if _digest_fingerprint(entry["path"]) != fingerprints[key]:
                raise CorruptionError(f"source image changed during generation: {entry['relative_path']}")
        _publish(staging, output_root)
        return receipt
    except Exception:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        raise


def _fixture_geometry(entry: Mapping[str, Any], *, horizon: bool = True, selected: bool = True) -> dict[str, Any]:
    selected_subject = {
        "confidence": 0.90,
        "height": 0.25,
        "kind": "person",
        "source_candidate_indices": [0],
        "width": 0.25,
        "x": 0.08,
        "y": 0.45,
    } if selected else None
    return {
        "analysis_status": "complete",
        "coordinate_space": {
            "axes": "x_right_y_up", "box_format": "normalized_xywh", "dimensions": "oriented_image",
            "horizon_angle_contract": HORIZON_ANGLE_CONTRACT,
            "horizon_pillow_rotation": HORIZON_PILLOW_ROTATION,
            "id": "vision_oriented_normalized", "origin": "bottom_left",
            "pillow_transform": VISION_PILLOW_TRANSFORM,
            "raw_pixel_preprocessing": RAW_PIXEL_PREPROCESSING,
        },
        "exif_orientation": {
            "applied_by_decoder": False, "exif_present": False, "name": "up",
            "passed_to_vision": True, "passed_to_vision_exactly_once": True, "source": "default_when_EXIF_missing", "tag": 1,
        },
        "geometry_authority": "silver_apple_vision",
        "horizon": {
            "confidence": 0.90,
            "observed_angle_degrees": 1.0,
            "pillow_uprighting_rotation_degrees": 1.0,
        } if horizon else None,
        "human_gold": False,
        "image": {
            "decoded_dimensions": {"height": entry["height"], "width": entry["width"]},
            "format": "png",
            "oriented_dimensions": {"height": entry["height"], "width": entry["width"]},
        },
        "research_only": True,
        "release_admissible": False,
        "schema_id": "camera-silver-geometry-v1",
        "schema_version": "1.0.0",
        "saliency": None,
        "selection_rule": "single_candidate" if selected else "no_candidates",
        "selection_status": "selected" if selected else "none",
        "selected_subject": selected_subject,
        "source": {
            "relative_path": entry["relative_path"], "sha256": entry["sha256"],
            "source_id": entry["source_id"], "source_record_id": entry["source_record_id"],
        },
        "subject_candidates": [{"confidence": 0.90, "height": 0.25, "kind": "person", "width": 0.25, "x": 0.08, "y": 0.45}] if selected else [],
    }


def _fixture_inventory_row(source_id: str, record_id: str, relative_path: str, image: Image.Image, source_root: Path) -> dict[str, Any]:
    path = source_root / relative_path
    encoded = path.read_bytes()
    return {
        "byte_count": len(encoded), "format": "png", "height": image.height, "human_gold": False,
        "intake_tier": "research_only", "relative_path": relative_path, "release_admissible": False,
        "sha256": _sha256_bytes(encoded), "source_id": source_id, "source_record_id": record_id, "width": image.width,
    }


def _fixture_geometry_receipt(inventory_bytes: bytes, geometry_bytes: bytes, records: int) -> dict[str, Any]:
    return {
        "counts": {
            "analysis_status": {"complete": records, "vision_unavailable": 0},
            "horizon": {"available": records, "unavailable": 0},
            "records": records,
            "saliency": {"available": records, "unavailable": 0},
            "selection_status": {"selected": records, "ambiguous": 0, "none": 0},
        },
        "determinism": GEOMETRY_DETERMINISM,
        "environment": {
            "os_version": "self-test",
            "os_version_components": {"major": 1, "minor": 0, "patch": 0},
            "platform": "macOS",
            "vision_framework": {"bundle_identifier": "com.apple.Vision", "name": "Vision", "version": "self-test"},
            "vision_request_family": list(VISION_REQUEST_FAMILY),
            "vision_request_revisions": {name: 1 for name in VISION_REQUEST_FAMILY},
        },
        "geometry_authority": "silver_apple_vision",
        "human_gold": False,
        "input_inventory": {"records": records, "sha256": _sha256_bytes(inventory_bytes)},
        "limits": {"max_records": None, "processed_records": records},
        "output_geometry": {"path": "geometry.jsonl", "records": records, "sha256": _sha256_bytes(geometry_bytes)},
        "receipt_schema_id": GEOMETRY_RECEIPT_SCHEMA_ID,
        "release_admissible": False,
        "research_only": True,
        "schema_version": "1.0.0",
        "tool_source": {"path": GEOMETRY_TOOL_RELATIVE_PATH, "sha256": _sha256_file(ROOT / GEOMETRY_TOOL_RELATIVE_PATH)},
    }


def _tree_bytes(root: Path) -> dict[str, bytes]:
    return {str(path.relative_to(root)): path.read_bytes() for path in sorted(root.rglob("*")) if path.is_file()}


def _expect_failure(operation: Any, label: str) -> None:
    try:
        operation()
    except CorruptionError:
        return
    raise CorruptionError(f"self-test accepted invalid {label}")


def _self_test() -> None:
    if Image.__version__ != PILLOW_VERSION_PIN:
        raise CorruptionError(f"Pillow runtime {Image.__version__} does not match pinned {PILLOW_VERSION_PIN}")
    with tempfile.TemporaryDirectory(prefix="camera-corruption-self-test-", dir="/private/tmp") as temp_dir:
        base = Path(temp_dir)
        source_root = base / "source"
        (source_root / "images").mkdir(parents=True)
        rows: list[dict[str, Any]] = []
        geometry_rows: list[dict[str, Any]] = []
        for index, record_id in enumerate(("rotate", "translate", "zoom"), 1):
            image = Image.new("RGB", (320, 240), (20 * index, 80, 160))
            # A visible asymmetric stripe makes derivative byte changes obvious.
            for x in range(35 + index * 20, 100 + index * 20):
                for y in range(50, 180):
                    image.putpixel((x, y), (240, 240 - index * 20, 20))
            relative = f"images/{record_id}.png"
            image.save(source_root / relative, format="PNG", optimize=False, compress_level=9)
            row = _fixture_inventory_row("fixture", record_id, relative, image, source_root)
            rows.append(row)
            geometry_rows.append(_fixture_geometry(row))
        inventory_path = base / "inventory.jsonl"
        geometry_path = base / "geometry.jsonl"
        inventory_bytes = b"".join(_json_bytes(row) for row in rows)
        geometry_bytes = b"".join(_json_bytes(row) for row in geometry_rows)
        inventory_path.write_bytes(inventory_bytes)
        geometry_path.write_bytes(geometry_bytes)
        (base / "receipt.json").write_bytes(_json_bytes(_fixture_geometry_receipt(inventory_bytes, geometry_bytes, len(rows))))

        # Physical LF parsing must preserve U+2028 inside a JSON string.
        lf_probe = base / "lf-probe.jsonl"
        lf_probe.write_bytes(b'{"marker":"before\xe2\x80\xa8after"}\n')
        lf_rows, _ = _read_jsonl(lf_probe, "LF probe")
        if lf_rows != [{"marker": "before\u2028after"}]:
            raise CorruptionError("self-test split JSONL at U+2028 instead of physical LF")

        # A 90-degree EXIF transform keeps square dimensions numerically
        # equal; validation must compare the expected tuple, not require the
        # numbers themselves to differ.
        square_inventory = dict(rows[0])
        square_inventory.update({"source_record_id": "square-exif-6", "width": 100, "height": 100})
        square_geometry = _fixture_geometry(square_inventory)
        square_geometry["source"]["source_record_id"] = "square-exif-6"
        square_geometry["exif_orientation"].update({
            "exif_present": True,
            "name": ORIENTATION_NAMES[6],
            "source": "kCGImagePropertyOrientation",
            "tag": 6,
        })
        _validate_geometry([square_geometry], [square_inventory])

        # The normal runner requires the repository schema; this also verifies
        # that the concurrent geometry schema is actually readable.
        output_one = base / "output-one"
        receipt_one = _run(inventory_path, geometry_path, source_root, output_one, 20260909, None)
        output_two = base / "output-two"
        receipt_two = _run(inventory_path, geometry_path, source_root, output_two, 20260909, None)
        if _tree_bytes(output_one) != _tree_bytes(output_two) or receipt_one != receipt_two:
            raise CorruptionError("same-seed self-test outputs are not byte-identical")
        pairs, _ = _read_jsonl(output_one / "pairs.jsonl", "self-test pairs")
        recipes = {pair["recipe"]["name"] for pair in pairs}
        if not {"rotate_horizon", "crop_translate", "crop_zoom_in"}.issubset(recipes):
            raise CorruptionError(f"self-test did not cover all recipes: {recipes}")
        actions = {name for pair in pairs for name, value, mask in zip(pair["targets"]["action"]["ordered_names"], pair["targets"]["action"]["values"], pair["targets"]["action"]["mask"]) if value and mask}
        if not {"level_horizon", "step_back"}.issubset(actions) or not any(action.startswith("shift_frame_") for action in actions):
            raise CorruptionError("self-test did not cover action targets")
        for pair in pairs:
            for head in ("issue", "action"):
                values = pair["targets"][head]["values"]
                mask = pair["targets"][head]["mask"]
                if any(mask_value not in (0, 1) for mask_value in mask) or any(mask_value == 0 and value != 0 for value, mask_value in zip(values, mask)):
                    raise CorruptionError("self-test found an unmasked target value")
            continuous = pair["targets"]["continuous"]
            if sum(continuous["mask"]) != 1:
                raise CorruptionError("self-test continuous mask is not sparse")
            if pair["recipe"]["name"] == "crop_translate":
                spans = pair["recipe"]["parameters"]["crop_span_normalized"]
                if abs(spans["x"] - spans["y"]) > 1e-12 or pair["recipe"]["parameters"]["pixel_aspect_preserved"] is not True:
                    raise CorruptionError("self-test emitted an anisotropic crop_translate derivative")
            if pair["recipe"]["name"] == "crop_zoom_in":
                final_gap = pair["recipe"]["parameters"]["final_edge_gap_minimum"]
                if not ZOOM_PRESSURE_MIN_GAP < final_gap <= ZOOM_PRESSURE_MAX_GAP:
                    raise CorruptionError("self-test emitted crop_zoom_in outside edge-pressure band")
        output_files = set(_tree_bytes(output_one))
        if any(path.startswith("_pair_metadata/") for path in output_files) or len(output_files) != len(pairs) + 2:
            raise CorruptionError("self-test retained pair staging metadata or wrong output file count")
        if receipt_one["geometry_receipt"]["sha256"] != _sha256_file(base / "receipt.json") or "environment" not in receipt_one["geometry_receipt"]:
            raise CorruptionError("self-test output receipt does not bind geometry receipt environment")

        # An oversized subject cannot be reframed with an equal normalized
        # square crop on the selected horizontal edge; it must be skipped.
        infeasible_dir = base / "infeasible"
        infeasible_dir.mkdir()
        infeasible_inventory_path = infeasible_dir / "inventory.jsonl"
        infeasible_geometry_path = infeasible_dir / "geometry.jsonl"
        infeasible_inventory_path.write_bytes(_json_bytes(rows[0]))
        infeasible_geometry_row = json.loads(_json_bytes(geometry_rows[0]))
        infeasible_geometry_row["selected_subject"].update({"x": 0.40, "y": 0.10, "width": 0.20, "height": 0.80})
        infeasible_geometry_row["subject_candidates"][0].update({"x": 0.40, "y": 0.10, "width": 0.20, "height": 0.80})
        infeasible_geometry_bytes = _json_bytes(infeasible_geometry_row)
        infeasible_geometry_path.write_bytes(infeasible_geometry_bytes)
        infeasible_inventory_bytes = _json_bytes(rows[0])
        (infeasible_dir / "receipt.json").write_bytes(_json_bytes(_fixture_geometry_receipt(infeasible_inventory_bytes, infeasible_geometry_bytes, 1)))
        infeasible_receipt = _run(
            infeasible_inventory_path, infeasible_geometry_path, source_root,
            infeasible_dir / "output", 20260909, None,
        )
        if infeasible_receipt["counts"]["skip_reasons"].get("no_feasible_square_crop", 0) < 1:
            raise CorruptionError("self-test did not skip an infeasible square crop")

        # A sibling receipt with a mismatched geometry hash is not accepted.
        bad_receipt_dir = base / "bad-receipt"
        bad_receipt_dir.mkdir()
        bad_receipt_inventory = bad_receipt_dir / "inventory.jsonl"
        bad_receipt_geometry = bad_receipt_dir / "geometry.jsonl"
        bad_receipt_inventory.write_bytes(inventory_bytes)
        bad_receipt_geometry.write_bytes(geometry_bytes)
        bad_receipt = _fixture_geometry_receipt(inventory_bytes, geometry_bytes, len(rows))
        bad_receipt["output_geometry"] = dict(bad_receipt["output_geometry"])
        bad_receipt["output_geometry"]["sha256"] = "0" * 64
        (bad_receipt_dir / "receipt.json").write_bytes(_json_bytes(bad_receipt))
        _expect_failure(
            lambda: _run(bad_receipt_inventory, bad_receipt_geometry, source_root, bad_receipt_dir / "output", 1, None),
            "geometry receipt binding",
        )
        bad_tool_receipt = json.loads(_json_bytes(_fixture_geometry_receipt(inventory_bytes, geometry_bytes, len(rows))))
        bad_tool_receipt["tool_source"] = dict(bad_tool_receipt["tool_source"])
        bad_tool_receipt["tool_source"]["sha256"] = "0" * 64
        (bad_receipt_dir / "receipt.json").write_bytes(_json_bytes(bad_tool_receipt))
        _expect_failure(
            lambda: _run(bad_receipt_inventory, bad_receipt_geometry, source_root, bad_receipt_dir / "bad-tool-output", 1, None),
            "geometry extractor receipt tool hash",
        )
        bad_revision_receipt = json.loads(_json_bytes(_fixture_geometry_receipt(inventory_bytes, geometry_bytes, len(rows))))
        bad_revision_receipt["environment"] = json.loads(_canonical_json(bad_revision_receipt["environment"]))
        bad_revision_receipt["environment"]["vision_request_revisions"][VISION_REQUEST_FAMILY[0]] = 0
        (bad_receipt_dir / "receipt.json").write_bytes(_json_bytes(bad_revision_receipt))
        _expect_failure(
            lambda: _run(bad_receipt_inventory, bad_receipt_geometry, source_root, bad_receipt_dir / "bad-revision-output", 1, None),
            "geometry receipt Vision revision",
        )

        bad_hash_dir = base / "bad-hash"
        bad_hash_dir.mkdir()
        bad_hash = bad_hash_dir / "inventory.jsonl"
        bad_row = dict(rows[0]); bad_row["sha256"] = "0" * 64
        bad_hash.write_bytes(_json_bytes(bad_row))
        bad_geometry = json.loads(_json_bytes(geometry_rows[0]))
        bad_geometry["source"] = dict(bad_geometry["source"]); bad_geometry["source"]["sha256"] = "0" * 64
        bad_geometry_path = bad_hash_dir / "geometry.jsonl"
        bad_geometry_bytes = _json_bytes(bad_geometry)
        bad_geometry_path.write_bytes(bad_geometry_bytes)
        bad_inventory_bytes = _json_bytes(bad_row)
        (bad_hash_dir / "receipt.json").write_bytes(_json_bytes(_fixture_geometry_receipt(bad_inventory_bytes, bad_geometry_bytes, 1)))
        _expect_failure(lambda: _run(bad_hash, bad_geometry_path, source_root, bad_hash_dir / "output", 1, None), "source hash")

        bad_path_dir = base / "bad-path"
        bad_path_dir.mkdir()
        bad_path = bad_path_dir / "inventory.jsonl"
        bad_row = dict(rows[0]); bad_row["relative_path"] = "../escape.png"
        bad_path.write_bytes(_json_bytes(bad_row))
        bad_path_geometry = bad_path_dir / "geometry.jsonl"
        bad_path_geometry.write_bytes(geometry_bytes)
        bad_path_inventory_bytes = _json_bytes(bad_row)
        (bad_path_dir / "receipt.json").write_bytes(_json_bytes(_fixture_geometry_receipt(bad_path_inventory_bytes, geometry_bytes, 1)))
        _expect_failure(lambda: _run(bad_path, bad_path_geometry, source_root, bad_path_dir / "output", 1, None), "path")
    print("PASS generate_camera_corruptions self-test recipes square_stream_zoom_receipt_lf hash_path_mask_determinism atomic_research_only")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--geometry", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--seed", type=int)
    parser.add_argument("--max-per-source", type=int)
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            if any(value is not None for value in (args.inventory, args.geometry, args.source_root, args.output_root, args.seed, args.max_per_source)):
                raise CorruptionError("--self-test cannot be combined with generation arguments")
            _self_test()
            return 0
        if args.inventory is None or args.geometry is None or args.source_root is None or args.output_root is None or args.seed is None:
            raise CorruptionError("--inventory, --geometry, --source-root, --output-root, and --seed are required")
        receipt = _run(args.inventory, args.geometry, args.source_root, args.output_root, args.seed, args.max_per_source)
        print(f"PASS generate_camera_corruptions pairs={receipt['counts']['pairs']} output={args.output_root.expanduser().resolve()}")
        return 0
    except CorruptionError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
