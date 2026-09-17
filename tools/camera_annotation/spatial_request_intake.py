#!/usr/bin/env python3
"""Research spatial-intent evidence sidecar, not a neural training-record producer.

No pixels are read and no provider is called. Image-space arithmetic is conditional
on an unconfirmed model ROI; it neither selects an entity nor prescribes an actuator.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys

REPO = Path(os.environ.get("SETOS_SPATIAL_INTAKE_REPO", Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(REPO / "tools/camera_annotation"))
from language_intake import (canonical_sha256, normalized_interpretation,
                             read_snapshot, research_flags, select_confirmations)
from language_labels import projection, validate, validate_visual

SCHEMA = "camera-spatial-request-evidence-v1"
FLAGS = dict(research_only=True, human_gold=False, release_admissible=False, training_ready=False)


def checked_sha(value):
    if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Invalid SHA256")
    return value


def center_geometry(rect):
    if not isinstance(rect, list) or len(rect) != 4 or any(
        type(x) not in (int, float) or not math.isfinite(x) for x in rect
    ):
        raise ValueError("Invalid normalized rectangle")
    x, y, w, h = rect
    if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > 1 or y + h > 1:
        raise ValueError("Rectangle outside oriented full frame")
    center = [x + w / 2, y + h / 2]
    offset = [0.5 - center[0], 0.5 - center[1]]
    return dict(
        coordinate_space="oriented_full_frame_top_left_normalized",
        current_center_xy=center,
        reference_point_xy=[0.5, 0.5],
        offset_to_reference_xy=offset,
        constraint="decrease_squared_image_distance_to_reference",
        baseline_squared_distance=sum(x*x for x in offset),
        exact_displacement_required=False,
        units="fraction_of_oriented_image_width_and_height",
        meaning="conditional_geometry_only_not_action_or_delta_supervision",
    )


def derive(queue_entries, journal_entries, teachers):
    items = {}
    for _, item in queue_entries:
        if item["record_id"] in items:
            raise ValueError("Duplicate queue record")
        items[item["record_id"]] = item
    selected, held = select_confirmations(journal_entries)
    rows = []
    for line, event, proposal_line, original_proposal in selected:
        value = normalized_interpretation(event)
        if not value["spatial_requests"]:
            continue
        item = items.get(event["record_id"])
        if item is None:
            raise ValueError("Spatial confirmation absent from queue")
        for node in (item, item["source"], event["contract_projection"]):
            research_flags(node)
        digest = checked_sha(item["media_sha256"])
        if event["media_sha256"] != digest or item["source"]["image_sha256"] != digest:
            raise ValueError("Source media SHA mismatch")
        if item["source"]["record_id"] != item["record_id"]:
            raise ValueError("Source record identity mismatch")
        if item["kind"] != "photo" or event["media_kind"] != "photo":
            raise ValueError("Temporal spatial requests require separate episode admission")
        if item["source"].get("split") not in ("train", "validation", "calibration") or not item["source"].get("source_group"):
            raise ValueError("Existing non-locked source-group split required")
        if event["state"] == "visual_confirmed":
            validate_visual(value, "photo")
            origin = "model_visual_human_confirmed"
        else:
            validate(value, event["raw_text"], "photo")
            origin = "human_text_model_translation_confirmed"
        if event["contract_projection"] != projection(value, "photo"):
            raise ValueError("Confirmed source projection changed")
        for request_index, request in enumerate(value["spatial_requests"]):
            candidates, seen = [], set()
            for teacher in teachers:
                row = teacher["row"]
                if row.get("record_id") != item["record_id"] or row.get("accepted") is not True:
                    continue
                if row.get("image_sha256") != digest:
                    raise ValueError("Same-record teacher media SHA mismatch")
                research_flags(row)
                transmitted_sha = checked_sha(row.get("transmitted_sha256"))
                p = row.get("proposal")
                if not isinstance(p, dict) or p.get("record_id") != item["record_id"]:
                    raise ValueError("Teacher proposal identity mismatch")
                research_flags(p)
                if not p.get("model") or not p.get("proposal_id"):
                    raise ValueError("Model grounding provenance missing")
                if row.get("model") != p["model"]:
                    raise ValueError("Teacher model provenance mismatch")
                for index, region in enumerate(p.get("regions", [])):
                    if region.get("role") != "subject":
                        continue
                    key = (p["proposal_id"], index)
                    if key in seen:
                        raise ValueError("Duplicate model grounding candidate")
                    seen.add(key)
                    geometry = center_geometry(region.get("rect"))
                    candidates.append(dict(
                        source_file_sha256=teacher["file_sha256"], source_line=teacher["line"],
                        source_event_sha256=canonical_sha256(row),
                        proposal_id=p["proposal_id"], model=p["model"], region_index=index,
                        media_sha256=digest, proposed_entity_label=region.get("label"),
                        submitted_image_sha256=transmitted_sha,
                        source_training_ready=row.get("training_ready"),
                        coordinate_basis="declared_teacher_top_left_oriented_thumbnail_not_independently_validated",
                        roi_xywh=region["rect"],
                        entity_binding_status="unresolved_model_candidate_not_confirmed_by_user",
                        geometry=geometry if request["goal"] == "center" else None,
                        **FLAGS,
                    ))
            rows.append(dict(
                schema_id=SCHEMA,
                request_id=canonical_sha256([canonical_sha256(event), request_index]),
                record_id=item["record_id"], media_sha256=digest,
                source_family_id=item["source"]["source_group"], split=item["source"]["split"],
                request=request, request_index=request_index,
                request_origin=origin, event_line=line, event_sha256=canonical_sha256(event),
                source_proposal_line=proposal_line, source_proposal_sha256=canonical_sha256(original_proposal),
                source_projection=event["contract_projection"],
                source_rights=item["source"].get("provenance"),
                model_region_candidates=candidates,
                selected_candidate=None, actuator=None, outcome_verified=None,
                v2_spatial_supervision=dict(
                    admitted=False, continuous_target_deltas=[None]*5,
                    action_utility_targets=None,
                    reasons=["named_entity_and_placement_goal_not_encoded_in_v2_input",
                             "entity_binding_unresolved",
                             "qualitative_goal_does_not_specify_delta_magnitude"],
                ),
                **FLAGS,
            ))
    return rows, held


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", type=Path, required=True)
    parser.add_argument("--teacher", type=Path, action="append", default=[])
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        raise ValueError("Refusing existing output")
    source_paths = [args.folder/"queue.jsonl", args.folder/"opinions.jsonl", *args.teacher]
    before = {str(p.resolve()): p.read_bytes() for p in source_paths}
    _, queue = read_snapshot(args.folder/"queue.jsonl")
    _, journal = read_snapshot(args.folder/"opinions.jsonl")
    teachers = []
    for path in args.teacher:
        data, entries = read_snapshot(path)
        digest = hashlib.sha256(data).hexdigest()
        teachers.extend(dict(file_sha256=digest, line=line, row=row) for line, row in entries)
    rows, held = derive(queue, journal, teachers)
    if not rows:
        raise ValueError("No current confirmed spatial requests")
    sources = {p: hashlib.sha256(b).hexdigest() for p, b in before.items()}
    if any(Path(p).read_bytes() != b for p, b in before.items()):
        raise ValueError("Sources changed during projection")
    # Sidecar has a separate schema; it cannot be sent to the v2 records loader.
    payload = "".join(json.dumps(r, ensure_ascii=False, sort_keys=True, allow_nan=False)+"\n" for r in rows)
    receipt = dict(schema_id=SCHEMA, sources=sources, records=len(rows), held=held,
                   model_region_candidates=sum(len(r["model_region_candidates"]) for r in rows),
                   neural_supervision_admitted=0, pixels_read=0, provider_calls=0,
                   output_sha256=hashlib.sha256(payload.encode()).hexdigest(),
                   adapter_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   source_mutations=False, **FLAGS)
    args.out.mkdir(parents=True, exist_ok=False)
    (args.out/"requests.jsonl").write_text(payload)
    (args.out/"receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True)+"\n")
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    main()
