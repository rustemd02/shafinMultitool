"""Focused, deterministic property checks for Camera Coach M4-008.

The fixtures are validated by the canonical Camera record checker before this
module exercises augmentation behavior. Expected left/right pairs below are
independent oracles: they are deliberately not imported from production
mapping tables.
"""

from __future__ import annotations

import copy
import json
import math
from pathlib import Path
import tempfile

from tools.dataset.camera_coach_check import validate_record

from .augmentations import (
    ACTION_IDS,
    AUGMENTATION_CONFIG_SHA256,
    AugmentationError,
    AugmentationSpec,
    DELTA_NAMES,
    FEATURE_NAMES,
    VERIFIER_IDS,
    augment,
    canonical_json,
    digest,
    pixel_digest,
    validate_derivation_manifest,
    validate_lineage_batch,
    validate_result,
    validate_spec,
)


ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = ROOT / "tools" / "dataset" / "tests" / "fixtures" / "camera-coach-fixtures.json"
MANIFEST_PATH = ROOT / "datasets" / "camera-coach" / "v1" / "derivation-manifest.jsonl"

# Independent frozen-catalog oracle. These are the only v1 left/right pairs;
# a production table that silently drops one makes this check fail.
ACTION_PAIRS_ORACLE = (
    ("shift_frame_left", "shift_frame_right"),
    ("move_subject_left", "move_subject_right"),
    ("move_object_left", "move_object_right"),
)
VERIFIER_PAIRS_ORACLE = (
    ("framing_left_improves", "framing_right_improves"),
    ("subject_position_improves_left", "subject_position_improves_right"),
    ("object_position_improves_left", "object_position_improves_right"),
)


def _assert_reject(callable_, *args, contains: str | None = None, **kwargs) -> None:
    try:
        callable_(*args, **kwargs)
    except AugmentationError as exc:
        if contains is not None and contains not in str(exc):
            raise AssertionError(f"rejection did not contain {contains!r}: {exc}") from exc
        return
    raise AssertionError(f"expected AugmentationError from {getattr(callable_, '__name__', callable_)}")


def _load_source_records() -> list[dict]:
    payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    records = payload.get("valid_records") if isinstance(payload, dict) else None
    if not isinstance(records, list) or len(records) != 3:
        raise AssertionError("canonical fixture must contain exactly three valid records")
    for record in records:
        errors = validate_record(record, {}, admission=False)
        if errors:
            raise AssertionError(f"canonical fixture rejected: {record.get('record_id')}: {errors}")
    return copy.deepcopy(records)


def _directional_record(source: dict) -> dict:
    """Make a canonical-valid episode with every direction-bearing location populated."""
    record = copy.deepcopy(source)
    left_actions = [left for left, _ in ACTION_PAIRS_ORACLE]
    right_actions = [right for _, right in ACTION_PAIRS_ORACLE]
    left_verifiers = [left for left, _ in VERIFIER_PAIRS_ORACLE]
    issue = record["label"]["issues"][0]
    issue["acceptable_action_ids"] = left_actions
    issue["forbidden_action_ids"] = right_actions
    record["label"]["acceptable_action_ids"] = left_actions
    record["label"]["forbidden_action_ids"] = right_actions
    record["label"]["selected_action_id"] = left_actions[0]
    record["label"]["selection_status"] = "multiple_valid"
    record["label"]["keep_decision"] = "not_keep"
    record["label"]["verification"] = [
        {
            "action_id": action,
            "verifier_id": verifier,
            "result": "not_run",
            "measurement": "before_after",
        }
        for action, verifier in zip(left_actions, left_verifiers)
    ]
    # The episode is part of the frozen record contract and has its own action
    # and verifier locations. Keep it measurable for the canonical checker.
    record["episode"]["action_step"]["action_id"] = "move_object_left"
    record["episode"]["outcome_verifier"] = "object_position_improves_left"
    for item in record["label"]["verification"]:
        if item["action_id"] == "move_object_left":
            item["result"] = "pass"
            item["measurement"] = "before_after"
    errors = validate_record(record, {}, admission=False)
    if errors:
        raise AssertionError(f"directional source fixture is not canonical-valid: {errors}")
    return record


def _source_targets() -> dict:
    values = {name: 0.0 for name in FEATURE_NAMES}
    values.update({
        "subject_bbox_x": 0.125,
        "subject_bbox_y": 0.25,
        "subject_bbox_width": 0.25,
        "subject_bbox_height": 0.125,
        "subject_edge_pressure_left": 0.125,
        "subject_edge_pressure_right": 0.375,
        "saliency_left_right_balance": 0.25,
        "horizon_angle": 0.5,
        "orientation_category": 1.0 / 3.0,
        "mirroring_flag": 0.0,
    })
    vector = [values[name] for name in FEATURE_NAMES]
    missing = [0.0] * len(FEATURE_NAMES)
    missing[FEATURE_NAMES.index("subject_edge_pressure_left")] = 1.0
    logits = [float(index) + 0.125 for index in range(len(ACTION_IDS))]
    deltas = [0.125, -0.25, 0.375, 0.5, 0.625]
    mask = [0.0] * (320 * 320)
    mask[0] = 1.0
    mask[320] = 1.0
    return {
        "regions": {
            "subject": [0.125, 0.25, 0.25, 0.125],
            "object": [0.375, 0.5, 0.125, 0.125],
        },
        "features": {
            "scalar_features": values,
            "scalar_vector": vector,
            "missing_feature_mask": missing,
            "action_utility_logits": logits,
            "continuous_target_deltas": deltas,
            "roi_normalized_xywh": [0.125, 0.25, 0.25, 0.125],
            "roi_mask": mask,
        },
    }


def _assert_feature_flip(source: dict, flipped: dict) -> None:
    source_features = source["features"]
    output = flipped["features"]
    source_scalars = source_features["scalar_features"]
    output_scalars = output["scalar_features"]
    assert output_scalars["subject_bbox_x"] == 1.0 - source_scalars["subject_bbox_x"] - source_scalars["subject_bbox_width"]
    assert output_scalars["subject_bbox_y"] == source_scalars["subject_bbox_y"]
    assert output_scalars["subject_edge_pressure_left"] == source_scalars["subject_edge_pressure_right"]
    assert output_scalars["subject_edge_pressure_right"] == source_scalars["subject_edge_pressure_left"]
    assert output_scalars["saliency_left_right_balance"] == -source_scalars["saliency_left_right_balance"]
    assert output_scalars["horizon_angle"] == -source_scalars["horizon_angle"]
    assert output_scalars["orientation_category"] == source_scalars["orientation_category"]
    assert output_scalars["mirroring_flag"] == 1.0

    source_vector = source_features["scalar_vector"]
    output_vector = output["scalar_vector"]
    untouched = {"subject_bbox_x", "subject_edge_pressure_left", "subject_edge_pressure_right", "saliency_left_right_balance", "horizon_angle", "mirroring_flag"}
    for name in FEATURE_NAMES:
        index = FEATURE_NAMES.index(name)
        if name not in untouched:
            assert output_vector[index] == source_vector[index], name
    assert output_vector[FEATURE_NAMES.index("subject_bbox_x")] == 0.625
    assert output_vector[FEATURE_NAMES.index("subject_edge_pressure_left")] == source_vector[FEATURE_NAMES.index("subject_edge_pressure_right")]
    assert output_vector[FEATURE_NAMES.index("subject_edge_pressure_right")] == source_vector[FEATURE_NAMES.index("subject_edge_pressure_left")]
    assert output_vector[FEATURE_NAMES.index("saliency_left_right_balance")] == -source_vector[FEATURE_NAMES.index("saliency_left_right_balance")]
    assert output_vector[FEATURE_NAMES.index("horizon_angle")] == -source_vector[FEATURE_NAMES.index("horizon_angle")]
    assert output_vector[FEATURE_NAMES.index("mirroring_flag")] == 1.0

    source_missing = source_features["missing_feature_mask"]
    output_missing = output["missing_feature_mask"]
    left_index = FEATURE_NAMES.index("subject_edge_pressure_left")
    right_index = FEATURE_NAMES.index("subject_edge_pressure_right")
    assert output_missing[left_index] == source_missing[right_index]
    assert output_missing[right_index] == source_missing[left_index]
    for left, right in ACTION_PAIRS_ORACLE:
        left_index, right_index = ACTION_IDS.index(left), ACTION_IDS.index(right)
        assert output["action_utility_logits"][left_index] == source_features["action_utility_logits"][right_index]
        assert output["action_utility_logits"][right_index] == source_features["action_utility_logits"][left_index]
    for name in DELTA_NAMES:
        index = DELTA_NAMES.index(name)
        expected = -source_features["continuous_target_deltas"][index] if name in {"delta_x", "horizon_delta"} else source_features["continuous_target_deltas"][index]
        assert output["continuous_target_deltas"][index] == expected
    assert output["roi_normalized_xywh"] == [0.625, 0.25, 0.25, 0.125]
    assert output["roi_mask"][319] == 1.0 and output["roi_mask"][320] == 0.0


def _reissued_result(result: dict, *, pixel_mutation: bool = False) -> dict:
    forged = copy.deepcopy(result)
    if pixel_mutation:
        forged["pixels"][0][0][0] = (forged["pixels"][0][0][0] + 1) % 256
        forged["lineage"]["output_pixels_sha256"] = pixel_digest(forged["pixels"])
    body = {key: value for key, value in forged["lineage"].items() if key != "receipt_sha256"}
    forged["lineage"]["receipt_sha256"] = digest(body)
    return forged


def _run() -> dict:
    records = _load_source_records()
    source = _directional_record(records[2])
    source_snapshot = copy.deepcopy(source)
    pixels = [
        [[0, 0, 0], [255, 0, 0], [0, 255, 0]],
        [[0, 0, 255], [32, 64, 96], [255, 255, 255]],
    ]
    targets = _source_targets()
    flip_spec = AugmentationSpec("horizontal_flip", seed=17, sample_counter=3)
    flipped = augment(source, pixels, flip_spec, source_targets=targets)
    assert flipped["record_id"] == source["record_id"]
    assert source == source_snapshot
    assert flipped["pixels"] == [
        [[0, 255, 0], [255, 0, 0], [0, 0, 0]],
        [[255, 255, 255], [32, 64, 96], [0, 0, 255]],
    ]
    left_actions = [left for left, _ in ACTION_PAIRS_ORACLE]
    right_actions = [right for _, right in ACTION_PAIRS_ORACLE]
    assert flipped["targets"]["label"]["acceptable_action_ids"] == right_actions
    assert flipped["targets"]["label"]["forbidden_action_ids"] == left_actions
    assert flipped["targets"]["label"]["selected_action_id"] == right_actions[0]
    assert flipped["targets"]["label"]["issues"][0]["acceptable_action_ids"] == right_actions
    assert flipped["targets"]["label"]["issues"][0]["forbidden_action_ids"] == left_actions
    assert [item["action_id"] for item in flipped["targets"]["label"]["verification"]] == right_actions
    assert [item["verifier_id"] for item in flipped["targets"]["label"]["verification"]] == [
        right for _, right in VERIFIER_PAIRS_ORACLE
    ]
    assert flipped["targets"]["episode"]["action_step"]["action_id"] == "move_object_right"
    assert flipped["targets"]["episode"]["outcome_verifier"] == "object_position_improves_right"
    assert flipped["targets"]["regions"] == {
        "subject": [0.625, 0.25, 0.25, 0.125],
        "object": [0.5, 0.5, 0.125, 0.125],
    }
    _assert_feature_flip(targets, flipped["targets"])
    validate_result(source, pixels, flipped, flip_spec, source_targets=targets)
    temporal = augment(
        records[1], pixels, AugmentationSpec("horizontal_flip", seed=16, sample_counter=0),
        dedup_cluster_id="dedup-cluster-fixture-001",
    )
    validate_result(records[1], pixels, temporal, AugmentationSpec("horizontal_flip", seed=16, sample_counter=0), dedup_cluster_id="dedup-cluster-fixture-001")
    assert len(temporal["lineage"]["protected_families"]["person"]) == 2
    assert temporal["lineage"]["protected_families"]["sequence"] == ["sequence-fixture-002"]
    assert temporal["lineage"]["protected_families"]["dedup_cluster"] == ["dedup-cluster-fixture-001"]

    # Full-precision, binary-exact geometry/scalars round-trip without a
    # rounded/deletion oracle. The second result is another training envelope,
    # not an admitted canonical record.
    mirrored_source = copy.deepcopy(source)
    mirrored_source["label"] = copy.deepcopy(flipped["targets"]["label"])
    mirrored_source["episode"] = copy.deepcopy(flipped["targets"]["episode"])
    assert validate_record(mirrored_source, {}, admission=False) == []
    round_spec = AugmentationSpec("horizontal_flip", seed=18, sample_counter=4)
    round_trip = augment(mirrored_source, flipped["pixels"], round_spec, source_targets=flipped["targets"])
    expected_original_targets = {"label": source["label"], "episode": source["episode"], **targets}
    assert round_trip["targets"] == expected_original_targets
    assert round_trip["pixels"] == pixels
    validate_result(mirrored_source, flipped["pixels"], round_trip, round_spec, source_targets=flipped["targets"])
    high_precision_targets = copy.deepcopy(targets)
    high_precision_targets["regions"]["subject"] = [0.12345678901234567, 0.23456789012345678, 0.23456789012345678, 0.12345678901234567]
    _assert_reject(
        augment, source, pixels, flip_spec, source_targets=high_precision_targets,
        contains="requires_reannotation",
    )

    identity_spec = AugmentationSpec("photometric", {"operation": "identity"}, seed=21, sample_counter=0)
    identity = augment(source, pixels, identity_spec)
    assert identity["pixels"] == pixels and identity["targets"] == {"label": source["label"], "episode": source["episode"]}
    validate_result(source, pixels, identity, identity_spec)

    # Strict closed-spec and trust-boundary negatives.
    _assert_reject(AugmentationSpec, "unknown")
    _assert_reject(AugmentationSpec, "horizontal_flip", {"extra": 1})
    _assert_reject(AugmentationSpec, "horizontal_flip", seed=True)
    _assert_reject(AugmentationSpec, "photometric", {"operation": "brightness"}, contains="requires_reannotation")
    _assert_reject(AugmentationSpec, "photometric", {"operation": "identity", "label_patch": {"keep_decision": "keep"}}, contains="requires_reannotation")
    _assert_reject(AugmentationSpec, "photometric", {"operation": "identity", "amount": 0.0}, contains="requires_reannotation")
    crop_spec = AugmentationSpec("crop", {"window": [0.0, 0.0, 1.0, 1.0]})
    _assert_reject(AugmentationSpec, "crop", {"window": [0.0, 0.0, 0.0, 1.0]})
    _assert_reject(AugmentationSpec, "crop", {"window": [0.0, 0.0, math.nan, 1.0]})
    _assert_reject(AugmentationSpec, "crop", {"window": [0.8, 0.0, 0.3, 1.0]})
    _assert_reject(augment, source, pixels, crop_spec, source_targets=targets, contains="requires_reannotation")
    _assert_reject(augment, source, None, flip_spec)
    bad_feature_range = copy.deepcopy(targets)
    bad_feature_range["features"]["scalar_features"]["subject_bbox_x"] = 1.1
    _assert_reject(augment, source, pixels, flip_spec, source_targets=bad_feature_range)
    bad_feature_type = copy.deepcopy(targets)
    bad_feature_type["features"]["scalar_features"]["mirroring_flag"] = True
    _assert_reject(augment, source, pixels, flip_spec, source_targets=bad_feature_type)
    unknown_record = copy.deepcopy(source)
    unknown_record["unexpected"] = True
    _assert_reject(augment, unknown_record, pixels, flip_spec)
    unknown_label = copy.deepcopy(source)
    unknown_label["label"]["selected_action_id"] = "not-a-frozen-action"
    _assert_reject(augment, unknown_label, pixels, flip_spec)
    _assert_reject(validate_spec, {"kind": "horizontal_flip", "parameters": {}, "unknown": 1})

    # Recomputed digests cannot bless forged output because validation replays
    # actual pixels and explicit targets from the source.
    forged_pixels = _reissued_result(flipped, pixel_mutation=True)
    _assert_reject(validate_result, source, pixels, forged_pixels, flip_spec, source_targets=targets)
    cosmetic = copy.deepcopy(identity)
    cosmetic["targets"]["label"]["keep_decision"] = "keep"
    _assert_reject(validate_result, source, pixels, cosmetic, identity_spec)
    mismatched_id = copy.deepcopy(identity)
    mismatched_id["record_id"] = "cam-forged-output-id"
    _assert_reject(validate_result, source, pixels, mismatched_id, identity_spec)
    extra_output_id = copy.deepcopy(identity)
    extra_output_id["output_record_id"] = "cam-forged-output-id"
    _assert_reject(validate_result, source, pixels, extra_output_id, identity_spec)
    unknown_lineage = copy.deepcopy(identity)
    unknown_lineage["lineage"]["unknown"] = True
    _assert_reject(validate_result, source, pixels, unknown_lineage, identity_spec)
    reordered_lineage = copy.deepcopy(identity)
    reordered_lineage["lineage"] = {key: reordered_lineage["lineage"][key] for key in reversed(tuple(reordered_lineage["lineage"]))}
    _assert_reject(validate_result, source, pixels, reordered_lineage, identity_spec)

    # Per-category protected-family registry: same string in different
    # categories is allowed, same category across split owners is rejected.
    cross_split = copy.deepcopy(source)
    cross_split["record_id"] = "cam-cross-split-fixture-001"
    cross_split["split"] = "quarantine"
    assert validate_record(cross_split, {}, admission=False) == []
    cross_split_result = augment(cross_split, pixels, AugmentationSpec("horizontal_flip", seed=22, sample_counter=0), source_targets=targets)
    _assert_reject(validate_lineage_batch, [flipped["lineage"], cross_split_result["lineage"]])
    cross_category = copy.deepcopy(source)
    cross_category["record_id"] = "cam-cross-category-fixture-001"
    cross_category["provenance"]["source_shoot_id"] = source["capture"]["scene_family_id"]
    cross_category["capture"]["scene_family_id"] = "scene-cross-category-fixture-001"
    assert validate_record(cross_category, {}, admission=False) == []
    cross_category_result = augment(cross_category, pixels, AugmentationSpec("horizontal_flip", seed=23, sample_counter=0), source_targets=targets)
    validate_lineage_batch([flipped["lineage"], cross_category_result["lineage"]])
    _assert_reject(validate_lineage_batch, [flipped["lineage"], flipped["lineage"]])
    same_counter_spec = AugmentationSpec("photometric", {"operation": "identity"}, seed=17, sample_counter=3)
    same_counter = augment(source, pixels, same_counter_spec, source_targets=targets)
    _assert_reject(validate_lineage_batch, [flipped["lineage"], same_counter["lineage"]])

    manifest = validate_derivation_manifest(MANIFEST_PATH)
    with tempfile.TemporaryDirectory(prefix="camera-augment-check-") as temp_dir:
        path = Path(temp_dir) / "manifest.jsonl"
        tampered = dict(manifest)
        tampered["record_count"] = 1
        path.write_text(canonical_json(tampered) + "\n", encoding="utf-8")
        _assert_reject(validate_derivation_manifest, path)
        unknown = dict(manifest)
        unknown["unknown"] = True
        path.write_text(canonical_json(unknown) + "\n", encoding="utf-8")
        _assert_reject(validate_derivation_manifest, path)
        reordered = {key: manifest[key] for key in reversed(tuple(manifest))}
        path.write_text(json.dumps(reordered, separators=(",", ":")) + "\n", encoding="utf-8")
        _assert_reject(validate_derivation_manifest, path)
        duplicate = canonical_json(manifest)[:-1] + ',"manifest_id":"camera-derivation-manifest"}'
        path.write_text(duplicate + "\n", encoding="utf-8")
        _assert_reject(validate_derivation_manifest, path)

    return {
        "action_catalog_count": len(ACTION_IDS),
        "action_pair_count": len(ACTION_PAIRS_ORACLE),
        "canonical_source_record_count": len(records),
        "config_sha256": AUGMENTATION_CONFIG_SHA256,
        "flip_output_pixels_sha256": flipped["lineage"]["output_pixels_sha256"],
        "flip_output_targets_sha256": flipped["lineage"]["output_targets_sha256"],
        "flip_receipt_sha256": flipped["lineage"]["receipt_sha256"],
        "identity_receipt_sha256": identity["lineage"]["receipt_sha256"],
        "manifest_sha256": manifest["manifest_sha256"],
        "temporal_person_family_count": len(temporal["lineage"]["protected_families"]["person"]),
        "temporal_sequence_bound": bool(temporal["lineage"]["protected_families"]["sequence"]),
        "dedup_cluster_bound": bool(temporal["lineage"]["protected_families"]["dedup_cluster"]),
        "protected_category_count": len(flipped["lineage"]["protected_families"]),
        "verifier_catalog_count": len(VERIFIER_IDS),
        "verifier_pair_count": len(VERIFIER_PAIRS_ORACLE),
        "status": "pass",
    }


if __name__ == "__main__":
    print(canonical_json(_run()))
