#!/usr/bin/env python3
"""Build bounded research edge/no-op controls from existing Commons/Vision bytes.

The synthetic transform is exact; the selected ROI remains Apple Vision silver.
No semantic intent, action benefit, good-frame, physical delta or human gold is
inferred. All source bytes and historical receipts remain unchanged.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import time

from PIL import Image

from tools.dataset import generate_camera_corruptions as geometry_tools
from ml.camera_coach.data.training_records import (
    GEOMETRIC_LABEL_SCHEMA_VERSION, TRAINING_RECORD_SCHEMA_ID, edge_measurement, parse_record,
)
from ml.camera_coach.models.set_composition_net_v2 import SETCompositionNetV2Manifest

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_DATA_ROOT = ROOT.parent / "setos-backend/local-data/SETOS"
SCHEMA_ID = "camera-edge-controls-v1"
MAX_SOURCE_RECORDS = 48
MAX_DERIVATIVES = 288
MAX_OUTPUT_BYTES = 250 * 1024 * 1024
DEFAULT_SEED = 20260916


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_jsonl(path):
    data = Path(path).read_bytes()
    return [json.loads(line) for line in data.splitlines() if line.strip()], data


def perceptual_hash(image):
    thumb = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
    values = list(thumb.get_flattened_data())
    return sum((values[y*9+x] > values[y*9+x+1]) << (y*8+x) for y in range(8) for x in range(8))


def grouped_sources(sources, seed):
    """Union same authors, exact pixels and conservative near-duplicate candidates."""
    parents = list(range(len(sources)))
    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i
    links = []
    for i, first in enumerate(sources):
        for j, second in enumerate(sources[:i]):
            reasons = []
            if first["author"].casefold().strip() == second["author"].casefold().strip():
                reasons.append("same_recorded_author")
            if first["pixel_sha256"] == second["pixel_sha256"]:
                reasons.append("same_decoded_pixels")
            if (first["dhash"] ^ second["dhash"]).bit_count() <= 8:
                reasons.append("dhash_distance_at_most_8")
            if reasons:
                parents[root(i)] = root(j)
                links.append({"first": first["id"], "second": second["id"], "reasons": reasons})
    members = {}
    for i, source in enumerate(sources):
        members.setdefault(root(i), []).append(source["id"])
    assignments = {}
    for values in members.values():
        group = "commons-edge-group-" + sha(canonical(sorted(values)))[:24]
        split = "validation" if int(sha(f"{seed}:{group}".encode())[:8], 16) % 5 == 0 else "train"
        for name in values:
            assignments[name] = (group, split)
    return assignments, links


def windows(roi):
    yield "source_noop", (0.0, 0.0, 1.0, 1.0)
    x, y, w, h = roi
    span = min(1.0, max(0.45, w / 0.74, h / 0.74))
    left = max(0.0, min(1.0-span, x+w/2-span/2))
    top = max(0.0, min(1.0-span, y+h/2-span/2))
    window = (left, top, left+span, top+span)
    if window != (0.0, 0.0, 1.0, 1.0) and edge_measurement(geometry_tools._crop_roi(roi, window)) == 0:
        yield "clear_crop", window
    for direction in ("left", "right", "top", "bottom"):
        try:
            window = geometry_tools._crop_window_for_edge(roi, direction)
            projected = geometry_tools._crop_roi(roi, window)
            geometry_tools._assert_roi(projected, "edge control")
            if edge_measurement(projected) == 1:
                yield "edge_" + direction, window
        except geometry_tools.CorruptionError:
            continue


def make_record(source, recipe, window, image, roi, group, split, manifest_hashes, contract):
    targets = {
        "scene_class": None,
        "subjectness": {key: None for key in contract.output_head_specs["subjectness_roi_agreement_logits"]["ordered_names"]},
        "issues": {key: None for key in contract.output_head_specs["issue_logits"]["ordered_names"]},
        "utility": {"reviewed": False, "acceptable": [], "forbidden": []},
        "good_frame": None, "abstention": None, "risk": None,
        "target_deltas": {key: None for key in contract.output_head_specs["continuous_target_deltas"]["ordered_names"]},
    }
    targets["issues"]["subject_too_close_to_edge"] = edge_measurement(roi)
    geometry, rights = source["geometry"], source["rights"]
    record_id = "edge-" + sha(canonical([source["id"], recipe, window]))[:32]
    record = dict(schema_id=TRAINING_RECORD_SCHEMA_ID, schema_version=GEOMETRIC_LABEL_SCHEMA_VERSION,
        record_id=record_id, split=split, source_family_id=group, matrix_class="single_person",
        capture_intent={"styles": [], "known": False}, roi_normalized_xywh=list(roi),
        pixels={"width": image.width, "height": image.height, "values": list(image.tobytes())},
        scalar_features=None, missing_feature_mask=None, targets=targets, ranking=[],
        annotation_provenance=dict(schema_id="camera-edge-measurement-intake-v1",
            label_origin="silver_apple_vision_analytic_crop", source_record_id=source["id"], source_group_id=group,
            source_media_sha256=geometry["source"]["sha256"], geometry_sha256=sha(canonical(geometry)), geometry=geometry,
            rights_sha256=sha(canonical(rights)), rights=rights, geometry_manifest_sha256=manifest_hashes["geometry"],
            rights_manifest_sha256=manifest_hashes["rights"], crop_window_xyxy=list(window),
            coordinate_space="oriented_full_frame_top_left_normalized", pixel_sha256=sha(image.tobytes()), recipe=recipe,
            research_only=True, human_gold=False, release_admissible=False, training_ready=False))
    parse_record(record, contract)
    return record


def build(source_root: Path, geometry_root: Path, out: Path, seed: int = DEFAULT_SEED):
    started = time.monotonic()
    source_root = geometry_tools._external_directory(source_root, "source", must_exist=True)
    geometry_root = geometry_tools._external_directory(geometry_root, "geometry", must_exist=True)
    out = out.expanduser().absolute()
    geometry_tools._assert_no_symlink_components(out)
    if out.exists() or not out.is_relative_to(CANONICAL_DATA_ROOT.resolve()):
        raise ValueError("Output must be new and inside canonical backend/local-data/SETOS")
    if shutil.disk_usage(CANONICAL_DATA_ROOT).free < 2 * MAX_OUTPUT_BYTES:
        raise ValueError("Insufficient free space for bounded edge controls")
    inventory, inventory_bytes = read_jsonl(source_root / "inventory.jsonl")
    geometry_rows, geometry_bytes = read_jsonl(geometry_root / "geometry.jsonl")
    rights_rows, rights_bytes = read_jsonl(source_root / "accepted-rights-receipt.jsonl")
    geometry_receipt = json.loads((geometry_root / "receipt.json").read_text())
    if (geometry_receipt["input_inventory"]["sha256"] != sha(inventory_bytes) or
            geometry_receipt["output_geometry"]["sha256"] != sha(geometry_bytes)):
        raise ValueError("Historical geometry receipt does not match its exact input/output snapshots")
    entries = geometry_tools._validate_inventory(inventory, source_root)
    verified_geometry = geometry_tools._validate_geometry(geometry_rows, entries)
    rights_by_id = {row["source_record_id"]: row for row in rights_rows}
    if len(rights_by_id) != len(rights_rows):
        raise ValueError("Duplicate rights source IDs")
    selected, skipped = [], Counter()
    for entry in entries:
        geometry = verified_geometry[(entry["source_id"], entry["source_record_id"])]
        subject = geometry["selected_subject"]
        if geometry["selection_status"] != "selected" or subject["kind"] not in ("face", "person") or subject["confidence"] < 0.8:
            skipped["no_qualified_silver_person_roi"] += 1
            continue
        roi = geometry_tools._top_left_roi(subject)
        if edge_measurement(roi) != 0 or max(roi[2:]) > 0.70 or roi[2]*roi[3] < 0.005:
            skipped["insufficient_control_margin_or_size"] += 1
            continue
        rights_row = rights_by_id.get(entry["source_record_id"])
        if not rights_row or rights_row.get("local_sha256") != entry["sha256"]:
            raise ValueError("Selected source lacks matching hash-bound rights receipt")
        rights = rights_row["rights"]
        if (rights.get("license_kind") not in ("public-domain", "cc0", "cc-by-4.0") or not rights.get("artist_text") or
                rights.get("restrictions") or rights_row.get("research_only") is not True or
                rights_row.get("human_gold") is not False or rights_row.get("release_admissible") is not False):
            skipped["unsupported_or_incomplete_rights"] += 1
            continue
        if len(selected) >= MAX_SOURCE_RECORDS:
            skipped["fixed_source_cap"] += 1
            continue
        image = geometry_tools._canonical_source_image(entry, geometry)
        selected.append(dict(id=entry["source_record_id"], entry=entry, geometry=geometry, rights=rights,
            rights_row=rights_row, image=image, roi=roi, author=rights["artist_text"],
            pixel_sha256=sha(image.tobytes()), dhash=perceptual_hash(image)))
    if len(selected) < 12:
        raise ValueError("Too few independent source candidates for the bounded experiment")
    assignments, links = grouped_sources(selected, seed)
    groups = {split: sorted({group for group, chosen_split in assignments.values() if split == chosen_split}) for split in ("train", "validation")}
    if len(groups["train"]) < 8 or len(groups["validation"]) < 3:
        raise ValueError("Fixed split lacks enough groups; do not tune seed against validation")
    contract = SETCompositionNetV2Manifest.load()
    manifest_hashes = {"inventory": sha(inventory_bytes), "geometry": sha(geometry_bytes), "rights": sha(rights_bytes)}
    out.mkdir(parents=True, exist_ok=False)
    (out / "images").mkdir()
    counts, recipes, coverage, records_count, bytes_written = Counter(), Counter(), Counter(), 0, 0
    with (out / "records.jsonl").open("xb") as records, (out / "lineage.jsonl").open("xb") as lineage:
        for source in selected:
            group, split = assignments[source["id"]]
            lineage.write(canonical({"source_record_id": source["id"], "group": group, "split": split,
                "source": {k:v for k,v in source["entry"].items() if k != "path"},
                "source_path": str(source["entry"]["path"]), "rights_source": source["rights_row"],
                "original_pixel_sha256": source["pixel_sha256"], "dhash": f"{source['dhash']:016x}"}) + b"\n")
            for recipe, window in windows(source["roi"]):
                derivative = geometry_tools._transform_extent(source["image"], window)
                derivative.thumbnail((160, 160), Image.Resampling.LANCZOS)
                roi = geometry_tools._crop_roi(source["roi"], window)
                record = make_record(source, recipe, window, derivative, roi, group, split, manifest_hashes, contract)
                payload = canonical(record) + b"\n"
                bytes_written += len(payload)
                records_count += 1
                if bytes_written > MAX_OUTPUT_BYTES or records_count > MAX_DERIVATIVES or time.monotonic()-started > 180:
                    raise ValueError("Declared finite data budget exceeded; partial output retained")
                records.write(payload)
                derivative.save(out / "images" / (record["record_id"] + ".png"))
                counts[split] += 1
                recipes[recipe] += 1
                coverage[f"{split}:{record['targets']['issues']['subject_too_close_to_edge']}"] += 1
    if any(coverage[f"{split}:{label}"] == 0 for split in groups for label in (0, 1)):
        raise ValueError("Each actual split must contain both positive and no-op edge targets")
    split_report = dict(schema_id="camera-edge-split-assessment-v1", seed=seed, groups=groups,
        source_records=len(selected), derivative_records=records_count, near_duplicate_and_author_links=links,
        split_conflicts=0, locked_test_used=False, calibration_used=False, diagnostics_quarantine=["LASIESTA:I_SI_01"],
        grouping_scope="All derivatives grouped with their source; same recorded author, decoded pixels and dHash<=8 joined before splitting. Author grouping is conservative; independent shoots are not established.")
    (out / "split-assessment.json").write_bytes(canonical(split_report) + b"\n")
    for path, expected in ((source_root / "inventory.jsonl", inventory_bytes), (source_root / "accepted-rights-receipt.jsonl", rights_bytes), (geometry_root / "geometry.jsonl", geometry_bytes)):
        if path.read_bytes() != expected:
            raise ValueError("Source snapshot changed during materialization")
    receipt = dict(schema_id=SCHEMA_ID, schema_version=1, seed=seed, records=records_count, source_records=len(selected),
        records_sha256=sha((out/"records.jsonl").read_bytes()), lineage_sha256=sha((out/"lineage.jsonl").read_bytes()),
        split_assessment_sha256=sha((out/"split-assessment.json").read_bytes()), input_manifest_sha256=manifest_hashes,
        source_root=str(source_root), geometry_root=str(geometry_root), split_counts=dict(counts), recipe_counts=dict(recipes),
        edge_target_counts=dict(coverage), skipped=dict(skipped), source_rights_counts=dict(Counter(s["rights"]["license_kind"] for s in selected)),
        preprocessing="Verified original bytes; ImageOps.exif_transpose once and existing ICC-to-sRGB recipe; analytic isotropic crop; Lanczos thumbnail max160; existing v2 preprocess uses independent_scale_to_target bilinear resize to full320/subject192, pixel-center ROI raster320, RGB/255 and explicit unknown intent.",
        observed_meaning="Edge pressure extremes conditional on selected silver face/person ROI. No-op means no edge-margin defect for that ROI; it does not mean good frame or no useful advice.",
        matrix_class_basis="single_person is the selected person/face ROI sampling stratum, not reviewed whole-frame scene classification",
        active_outputs={"issue_logits": ["subject_too_close_to_edge"]}, masked_outputs="All remaining issue components, scene, subjectness, utility, good-frame, risk, abstention and all deltas",
        budget={"api_cost_usd": 0, "max_source_records": MAX_SOURCE_RECORDS, "max_derivatives": MAX_DERIVATIVES, "max_output_bytes": MAX_OUTPUT_BYTES,
            "materialization_time_limit_seconds": 180, "fit_time_limit_seconds": 300, "fit_cpu_threads": 1, "fit_mps_requested": False},
        elapsed_seconds=time.monotonic()-started, research_only=True, human_gold=False, release_admissible=False, training_ready=False,
        script_sha256=sha(Path(__file__).read_bytes()), loader_sha256=sha((ROOT/"ml/camera_coach/data/training_records.py").read_bytes()))
    (out/"receipt.json").write_bytes(canonical(receipt) + b"\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.source, args.geometry, args.out)
    print(json.dumps({key:result[key] for key in ("records", "source_records", "split_counts", "edge_target_counts", "source_rights_counts", "elapsed_seconds")}, sort_keys=True))


if __name__ == "__main__":
    main()
