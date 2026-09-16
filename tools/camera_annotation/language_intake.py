"""Versioned research intake of existing confirmations, never a confirmation writer.

Only frame-wide issue labels enter v2.1 loss. Other opinions, including spatial
requests, stay verbatim in provenance and cannot become ROI or action targets.
"""
from __future__ import annotations

import collections
import hashlib
import json
from pathlib import Path
import platform
import sys

from PIL import Image, ImageOps, __version__ as pillow_version

from annotation_labels import ISSUES, DELTAS, sha256_file, local_media_path
from language_labels import FLAGS, projection, validate, validate_visual

REPO = Path(__file__).resolve().parents[2]
ADAPTER_VERSION = "camera-language-partial-intake-v1"
CONFIRMED = ("confirmed", "visual_confirmed")
MANUAL = ("draft", "raw", "proposal", "confirmed")


def canonical_sha256(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def read_snapshot(path):
    data = Path(path).read_bytes()
    entries = [(line, json.loads(text)) for line, text in enumerate(data.decode("utf-8").splitlines(), 1) if text.strip()]
    return data, entries


def research_flags(value):
    if any(value.get(key) is not expected for key, expected in FLAGS.items()):
        raise ValueError("Source research provenance flags are missing or changed")


def normalized_interpretation(event):
    value = {key: child for key, child in event["interpretation"].items() if key != "summary"}
    # The pre-visual journal predates spatial_requests; the original event is
    # retained in lineage, and this one explicit legacy default means no claim.
    value.setdefault("spatial_requests", [])
    return value


def select_confirmations(entries):
    """Use append order, retaining new drafts as withdrawal of old supervision."""
    latest = {}
    for line, event in entries:
        if event.get("state") in CONFIRMED:
            latest[(event["record_id"], event["annotator_id"])] = (line, event)
    selected, held = [], []
    for key, (line, event) in latest.items():
        related = [(i, e) for i, e in entries if (e.get("record_id"), e.get("annotator_id")) == key]
        if any(i > line and e.get("state") in MANUAL for i, e in related):
            held.append(dict(record_id=key[0], event_line=line, reason="newer_unconfirmed_manual_revision"))
            continue
        visual = event["state"] == "visual_confirmed"
        identity = "job_id" if visual else "review_id"
        proposal_state = "visual_proposal" if visual else "proposal"
        proposals = [(i, e) for i, e in related if i < line and e.get("state") == proposal_state and
                     e.get(identity) == event.get(identity)]
        if not proposals:
            raise ValueError("Confirmed record lacks its source proposal")
        proposal_line, proposal_event = proposals[-1]
        if (proposal_event.get("media_sha256") != event.get("media_sha256") or
                normalized_interpretation(proposal_event) != normalized_interpretation(event)):
            raise ValueError("Confirmation and source proposal disagree")
        if visual:
            dispatches = [(i, e) for i, e in related if i < proposal_line and e.get("state") == "visual_dispatch"
                          and e.get(identity) == event.get(identity) and e.get("cache_key") == event.get("cache_key")]
            if not dispatches:
                raise ValueError("Visual confirmation lacks its dispatch/cache lineage")
            if any(i > dispatches[-1][0] and e.get("state") in MANUAL for i, e in related):
                held.append(dict(record_id=key[0], event_line=line, reason="visual_superseded_by_manual_revision"))
                continue
        confirmation_key = "human_confirmed_assessment" if visual else "human_confirmed_translation"
        if event.get(confirmation_key) is not True:
            raise ValueError("An unconfirmed model proposal cannot enter reviewed intake")
        research_flags(event); research_flags(proposal_event)
        selected.append((line, event, proposal_line, proposal_event))
    ids = [event["record_id"] for _, event, _, _ in selected]
    if len(ids) != len(set(ids)):
        raise ValueError("Multiple reviewers require adjudication before intake")
    return sorted(selected, key=lambda item: item[0]), held


def image_pixels(item):
    path = local_media_path(item["media_path"])
    if sha256_file(path) != item["media_sha256"]:
        raise ValueError("Reviewed source media SHA changed")
    with Image.open(path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
        original_size = list(image.size)
        small = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
        values = list(small.tobytes())
        bits = [int(values[y * 9 + x] > values[y * 9 + x + 1]) for y in range(8) for x in range(8)]
        dhash = sum(bit << index for index, bit in enumerate(bits))
        image.thumbnail((320, 320), Image.Resampling.LANCZOS)
        width, height = image.size
        pixel_bytes = image.tobytes()
    pixels = dict(width=width, height=height, values=list(pixel_bytes))
    transform = dict(recipe="EXIF transpose; RGB; aspect-preserving thumbnail max320 Lanczos; runtime v2 preprocessing follows",
                     source_size=original_size, materialized_size=[width, height], pillow_version=pillow_version,
                     pixel_sha256=hashlib.sha256(f"{width}x{height}:".encode() + pixel_bytes).hexdigest(),
                     dhash64=f"{dhash:016x}")
    return pixels, transform


def source_split_assessment(queue, records, lineage):
    groups = collections.defaultdict(set)
    media = collections.defaultdict(set)
    for item in queue:
        source = item.get("source", {})
        if item.get("kind") != "photo" or source.get("split") not in ("train", "validation", "calibration"):
            continue
        if source.get("source_group"):
            groups[source["source_group"]].add(source["split"])
        media[item["media_sha256"]].add(source["split"])
    group_conflicts = sorted(key for key, splits in groups.items() if len(splits) > 1)
    media_conflicts = sorted(key for key, splits in media.items() if len(splits) > 1)
    candidates, pixel_conflicts = [], []
    for index, left in enumerate(lineage):
        for right in lineage[index + 1:]:
            cross_split = left["split"] != right["split"]
            a, b = left["transform"], right["transform"]
            pair = dict(record_ids=[left["record_id"], right["record_id"]], cross_split=cross_split)
            if a["pixel_sha256"] == b["pixel_sha256"] and cross_split:
                pixel_conflicts.append(pair)
            distance = (int(a["dhash64"], 16) ^ int(b["dhash64"], 16)).bit_count()
            if distance <= 4:
                candidates.append(dict(pair, hamming_distance=distance))
    cross_near = [pair for pair in candidates if pair["cross_split"]]
    return dict(queue_photo_count=sum(item.get("kind") == "photo" for item in queue),
        reviewed_photo_count=len(records), reviewed_source_groups=len({r["source_family_id"] for r in records}),
        group_split_conflicts=group_conflicts, media_split_conflicts=media_conflicts,
        pixel_split_conflicts=pixel_conflicts, near_duplicate_candidates=candidates,
        near_duplicate_method="64-bit horizontal dHash, Hamming <=4, reviewed subset only; candidate screen, not duplicate proof",
        scene_identity="Original queue author/source groups preserved; independent shoot/scene IDs not established",
        validation_independence="Assisted opinions; not independent human-gold validation or locked test",
        usable_for_gradient_probe=not(group_conflicts or media_conflicts or pixel_conflicts or cross_near),
        release_evaluation_ready=False)


def export_language_review(folder, out):
    folder, out = Path(folder), Path(out)
    if out.exists():
        raise ValueError("Refusing to overwrite an existing research intake")
    queue_path, journal_path = folder / "queue.jsonl", folder / "opinions.jsonl"
    queue_bytes, queue_entries = read_snapshot(queue_path)
    journal_bytes, entries = read_snapshot(journal_path)
    queue = [item for _, item in queue_entries]
    items = {item["record_id"]: item for item in queue}
    if len(items) != len(queue):
        raise ValueError("Duplicate queue record IDs")
    source_hashes = dict(queue_sha256=hashlib.sha256(queue_bytes).hexdigest(), journal_sha256=hashlib.sha256(journal_bytes).hexdigest())
    chosen, held = select_confirmations(entries)
    if not chosen:
        raise ValueError("No current confirmed reviews; empty intake refused")
    if str(REPO) not in sys.path:
        sys.path.insert(0, str(REPO))
    from ml.camera_coach.data.training_records import PARTIAL_LABEL_SCHEMA_VERSION, parse_record
    records, lineage, active = [], [], collections.Counter()
    per_issue = {split: {name: dict(positive=0, negative=0, unknown=0) for name in ISSUES}
                 for split in ("train", "validation", "calibration")}
    for line, event, proposal_line, proposal_event in chosen:
        item = items.get(event["record_id"])
        if item is None:
            raise ValueError("Confirmation references a record outside the source queue")
        research_flags(item)
        if item["media_sha256"] != event["media_sha256"] or item["kind"] != event["media_kind"]:
            raise ValueError("Confirmation media identity disagrees with queue")
        source = item["source"]
        if source.get("split") == "locked_test":
            raise ValueError("Locked test remains sealed; no intake permitted")
        if item["kind"] != "photo":
            held.append(dict(record_id=item["record_id"], event_line=line, reason="temporal_episode_admission_required"))
            continue
        research_flags(source)
        if source["record_id"] != item["record_id"] or source["image_sha256"] != item["media_sha256"]:
            raise ValueError("Source row and queue media disagree")
        if source.get("split") not in per_issue or not source.get("source_group"):
            raise ValueError("Photo requires an existing non-locked source-group split")
        value = normalized_interpretation(event)
        visual = event["state"] == "visual_confirmed"
        if visual:
            validate_visual(value, "photo")
        else:
            validate(value, event["raw_text"], "photo")
        source_projection = event["contract_projection"]
        if projection(value, "photo") != source_projection:
            raise ValueError("Stored projection no longer matches its confirmed interpretation")
        research_flags(source_projection)
        if source_projection.get("training_ready") is not False:
            raise ValueError("Source training admission must remain false")
        pixels, transform = image_pixels(item)
        origin = "model_visual_human_confirmed" if visual else "human_text_model_translation_confirmed"
        provenance = dict(schema_id=ADAPTER_VERSION, label_origin=origin, event_line=line,
            event_sha256=canonical_sha256(event), media_sha256=item["media_sha256"],
            projection=source_projection, training_ready=False, **source_hashes, **FLAGS)
        record = dict(schema_id="camera-training-record-v2", schema_version=PARTIAL_LABEL_SCHEMA_VERSION,
            record_id=item["record_id"], split=source["split"], source_family_id=source["source_group"],
            matrix_class=source["matrix_class"], capture_intent=dict(known=False, styles=[]),
            roi_normalized_xywh=None, pixels=pixels, scalar_features=None, missing_feature_mask=None, ranking=[],
            annotation_provenance=provenance,
            targets=dict(scene_class=None, subjectness=dict(subjectness=None, roi_agreement=None, ambiguity=None),
                issues=dict(zip(ISSUES, source_projection["issue_logits"])),
                utility=dict(reviewed=False, acceptable=[], forbidden=[]), good_frame=None, abstention=None, risk=None,
                target_deltas={name: None for name in DELTAS}))
        parsed = parse_record(record)
        for head, mask in parsed.masks.items():
            active[head] += int(mask.sum())
        for name, label in record["targets"]["issues"].items():
            per_issue[record["split"]][name]["unknown" if label is None else "positive" if label else "negative"] += 1
        records.append(record)
        lineage.append(dict(record_id=item["record_id"], split=record["split"], source_event=event,
            source_event_line=line, source_proposal=proposal_event, source_proposal_line=proposal_line,
            source_queue_item=item, transform=transform, label_origin=origin,
            matrix_class_use="Existing discovery stratum for sampling only; no scene_class target",
            source_projection_unchanged=True, training_ready=False, **FLAGS))
    if not records:
        raise ValueError("No supported photo records; empty training intake refused")
    split_assessment = source_split_assessment(queue, records, lineage)
    if not split_assessment["usable_for_gradient_probe"]:
        raise ValueError("Source/media/perceptual split conflict; intake requires duplicate review")
    # Verify the two byte snapshots once more before creating output. No source
    # rewriting or journal append is performed by this exporter.
    if queue_path.read_bytes() != queue_bytes or journal_path.read_bytes() != journal_bytes:
        raise ValueError("Source queue/journal changed during export; no intake written")
    from review_pipeline import write_rows, write_new
    out.mkdir(parents=True, exist_ok=False)
    write_rows(out / "records.jsonl", records)
    write_rows(out / "lineage.jsonl", lineage)
    write_new(out / "split-assessment.json", split_assessment)
    receipt = dict(schema_id=ADAPTER_VERSION, record_schema_version=PARTIAL_LABEL_SCHEMA_VERSION,
        records=len(records), active_targets=dict(active), per_issue=per_issue,
        splits=dict(collections.Counter(record["split"] for record in records)), held=held,
        label_origins=dict(collections.Counter(row["label_origin"] for row in lineage)),
        source_folder=str(folder.resolve()), records_sha256=sha256_file(out / "records.jsonl"),
        lineage_sha256=sha256_file(out / "lineage.jsonl"), split_assessment_sha256=sha256_file(out / "split-assessment.json"),
        adapter_sha256=sha256_file(Path(__file__)), loader_sha256=sha256_file(REPO / "ml/camera_coach/data/training_records.py"),
        python_version=platform.python_version(), pillow_version=pillow_version,
        training_ready=False, full_fit_ready=False, admission="non_admitted_research",
        limitations=["Partial issue supervision only; no inferred negative for unmentioned issues",
            "ROI, action identity, physical execution and intent admission unresolved",
            "Aesthetic verdict is retained as opinion; no good-frame/risk/abstention target",
            "Spatial requests and temporal assessment are unevaluated source metadata",
            "Assisted validation is not independent human-gold or release evaluation"],
        **source_hashes, **FLAGS)
    write_new(out / "receipt.json", receipt)
    return receipt
