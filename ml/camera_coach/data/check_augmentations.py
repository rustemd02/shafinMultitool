"""Runnable M4-008 checks with independent label and pixel oracles."""

from __future__ import annotations

import copy
from io import BytesIO
import hashlib
import json
from pathlib import Path
import tempfile

from PIL import Image

from tools.dataset.camera_coach_check import validate_record

from .augmentations import (
    AUGMENTATION_CONFIG_SHA256,
    AugmentationError,
    augment,
    canonical_json,
    digest,
    make_cluster_authority,
    make_source_bundle,
    make_split_authority,
    make_trusted_schedule,
    validate_derivation_manifest,
    validate_lineage_batch,
    validate_result,
)


ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = ROOT / "tools" / "dataset" / "tests" / "fixtures" / "camera-coach-fixtures.json"
MANIFEST_PATH = ROOT / "datasets" / "camera-coach" / "v1" / "derivation-manifest.jsonl"

# Independent frozen oracles.  Production mapping tables are intentionally not
# used to decide whether these pairs were all transformed.
ACTION_ORACLE = (
    ("shift_frame_left", "shift_frame_right"),
    ("move_subject_left", "move_subject_right"),
    ("move_object_left", "move_object_right"),
)
VERIFIER_ORACLE = (
    ("framing_left_improves", "framing_right_improves"),
    ("subject_position_improves_left", "subject_position_improves_right"),
    ("object_position_improves_left", "object_position_improves_right"),
)
PROTECTED_ORACLE = (
    "source_shoot",
    "scene",
    "person",
    "location",
    "time",
    "derivation",
    "sequence",
    "take",
    "device",
    "dedup_cluster",
)


def _reject(callable_, *args, **kwargs) -> None:
    try:
        callable_(*args, **kwargs)
    except AugmentationError:
        return
    raise AssertionError(f"expected rejection from {getattr(callable_, '__name__', callable_)}")


def _oracle(value: str | None, pairs: tuple[tuple[str, str], ...]) -> str | None:
    if value is None:
        return None
    for left, right in pairs:
        if value == left:
            return right
        if value == right:
            return left
    return value


def _oracle_region(region: list[float]) -> list[float]:
    return [1.0 - region[0] - region[2], region[1], region[2], region[3]]


def _oracle_targets(targets: dict, *, flip: bool) -> dict:
    result = copy.deepcopy(targets)
    if not flip:
        return result
    label = result["label"]
    label["acceptable_action_ids"] = [_oracle(v, ACTION_ORACLE) for v in label["acceptable_action_ids"]]
    label["forbidden_action_ids"] = [_oracle(v, ACTION_ORACLE) for v in label["forbidden_action_ids"]]
    label["selected_action_id"] = _oracle(label["selected_action_id"], ACTION_ORACLE)
    for issue in label["issues"]:
        issue["acceptable_action_ids"] = [_oracle(v, ACTION_ORACLE) for v in issue["acceptable_action_ids"]]
        issue["forbidden_action_ids"] = [_oracle(v, ACTION_ORACLE) for v in issue["forbidden_action_ids"]]
    for verification in label["verification"]:
        verification["action_id"] = _oracle(verification["action_id"], ACTION_ORACLE)
        verification["verifier_id"] = _oracle(verification["verifier_id"], VERIFIER_ORACLE)
    for candidate in result["subject"]["candidates"]:
        if "region" in candidate:
            candidate["region"] = _oracle_region(candidate["region"])
    if "episode" in result:
        result["episode"]["action_step"]["action_id"] = _oracle(result["episode"]["action_step"]["action_id"], ACTION_ORACLE)
        result["episode"]["outcome_verifier"] = _oracle(result["episode"]["outcome_verifier"], VERIFIER_ORACLE)
    return result


def _oracle_pixels(pixels: list[list[list[int]]]) -> list[list[list[int]]]:
    return [[list(pixel) for pixel in reversed(row)] for row in pixels]


def _png(offset: int) -> bytes:
    image = Image.new("RGB", (4, 3))
    for y in range(3):
        for x in range(4):
            image.putpixel((x, y), ((offset + x * 31) % 256, (offset + y * 47) % 256, (x + y + offset) % 256))
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def _fixtures() -> tuple[list[dict], dict[str, bytes]]:
    payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    records = copy.deepcopy(payload["valid_records"])
    assets: dict[str, bytes] = {}
    for index, record in enumerate(records):
        candidate = record["subject"]["candidates"][0]
        candidate["region"] = [0.125, 0.25, 0.25, 0.125]
        # The episode fixture has no in-frame person family.  A synthetic
        # protected ID makes the M3 split projection admissible without
        # changing any real label or claiming a human annotation.
        if record["record_type"] == "episode":
            record["capture"]["person_family_ids"] = ["person-fixture-003"]
        record["review"] = {
            "status": "dual_reviewed",
            "vote_history": [
                {"vote_id": f"fixture-vote-a-{record['record_id']}", "annotator_id": "fixture-annotator-a", "submitted_at": "2026-09-05T00:00:00Z", "decision": "accept"},
                {"vote_id": f"fixture-vote-b-{record['record_id']}", "annotator_id": "fixture-annotator-b", "submitted_at": "2026-09-05T00:00:01Z", "decision": "accept"},
            ],
            "adjudication_history": [],
        }
        for asset_index, asset_id in enumerate(record["media"]["asset_ids"]):
            assets[asset_id] = _png(index * 60 + asset_index * 11)
        errors = validate_record(record, {}, admission=False)
        if errors:
            raise AssertionError(f"canonical fixture rejected: {record['record_id']}: {errors}")
    records[2]["label"]["acceptable_action_ids"] = [left for left, _ in ACTION_ORACLE]
    records[2]["label"]["forbidden_action_ids"] = [right for _, right in ACTION_ORACLE]
    records[2]["label"]["selected_action_id"] = ACTION_ORACLE[0][0]
    records[2]["label"]["selection_status"] = "multiple_valid"
    records[2]["label"]["keep_decision"] = "not_keep"
    issue = records[2]["label"]["issues"][0]
    issue["acceptable_action_ids"] = [left for left, _ in ACTION_ORACLE]
    issue["forbidden_action_ids"] = [right for _, right in ACTION_ORACLE]
    records[2]["label"]["verification"] = [
        {
            "action_id": left,
            "verifier_id": verifier_left,
            "result": "not_run",
            "measurement": "before_after",
        }
        for (left, _), (verifier_left, _) in zip(ACTION_ORACLE, VERIFIER_ORACLE)
    ]
    records[2]["label"]["verification"][2]["result"] = "pass"
    records[2]["episode"]["action_step"]["action_id"] = ACTION_ORACLE[2][0]
    records[2]["episode"]["outcome_verifier"] = VERIFIER_ORACLE[2][0]
    errors = validate_record(records[2], {}, admission=False)
    if errors:
        raise AssertionError(f"directional fixture rejected: {errors}")
    records[0]["media"]["content_sha256"] = hashlib.sha256(assets[records[0]["media"]["asset_ids"][0]]).hexdigest()
    return records, assets


def _jobs(records: list[dict]) -> list[dict]:
    return [
        {
            "job_id": f"job-{index:02d}",
            "record_id": record["record_id"],
            "kind": "photometric_identity" if index == 0 else "horizontal_flip",
            "parameters": {},
            "seed": 17,
            "sample_counter": index,
        }
        for index, record in enumerate(records)
    ]


def _rehashed(result: dict) -> dict:
    forged = copy.deepcopy(result)
    body = {key: value for key, value in forged["lineage"].items() if key != "receipt_sha256"}
    forged["lineage"]["receipt_sha256"] = digest(body)
    return forged


def _run() -> dict:
    records, asset_bytes = _fixtures()
    bundles = [make_source_bundle(record, {asset_id: asset_bytes[asset_id] for asset_id in record["media"]["asset_ids"]}) for record in records]
    cluster = make_cluster_authority(bundles)
    split = make_split_authority(bundles, cluster)
    jobs = _jobs(records)
    schedule = make_trusted_schedule(bundles, jobs, cluster_authority=cluster, split_authority=split)
    schedule_repeat = make_trusted_schedule(bundles, jobs, cluster_authority=cluster, split_authority=split)
    assert schedule.schedule_sha256 == schedule_repeat.schedule_sha256
    results = [augment(bundle, schedule, job["job_id"]) for bundle, job in zip(bundles, jobs)]
    for bundle, result in zip(bundles, results):
        validate_result(
            bundle,
            result,
            schedule=schedule,
            cluster_authority=cluster,
            split_authority=split,
        )
    validate_lineage_batch(
        bundles,
        results,
        schedule=schedule,
        cluster_authority=cluster,
        split_authority=split,
    )

    directional = results[2]
    source_target = {
        "capture": copy.deepcopy(records[2]["capture"]),
        "subject": copy.deepcopy(records[2]["subject"]),
        "label": copy.deepcopy(records[2]["label"]),
        "episode": copy.deepcopy(records[2]["episode"]),
    }
    assert _oracle_targets(source_target, flip=True) == directional["targets"]
    assert _oracle_targets(_oracle_targets(source_target, flip=True), flip=True) == source_target
    # Compare every direction-bearing location against an independent oracle.
    label = directional["targets"]["label"]
    assert label["acceptable_action_ids"] == [right for _, right in ACTION_ORACLE]
    assert label["forbidden_action_ids"] == [left for left, _ in ACTION_ORACLE]
    assert label["selected_action_id"] == ACTION_ORACLE[0][1]
    assert label["issues"][0]["acceptable_action_ids"] == [right for _, right in ACTION_ORACLE]
    assert label["issues"][0]["forbidden_action_ids"] == [left for left, _ in ACTION_ORACLE]
    assert [v["action_id"] for v in label["verification"]] == [right for _, right in ACTION_ORACLE]
    assert [v["verifier_id"] for v in label["verification"]] == [right for _, right in VERIFIER_ORACLE]
    assert directional["targets"]["episode"]["action_step"]["action_id"] == ACTION_ORACLE[2][1]
    assert directional["targets"]["episode"]["outcome_verifier"] == VERIFIER_ORACLE[2][1]
    assert directional["targets"]["subject"]["candidates"][0]["region"] == [0.625, 0.25, 0.25, 0.125]
    # The actual full-bundle pixel oracle checks every temporal/episode asset.
    for bundle, result in zip(bundles, results):
        if result["lineage"]["transform"]["kind"] == "horizontal_flip":
            for asset_id, output_pixels in result["pixels_by_asset"].items():
                image = Image.open(BytesIO(asset_bytes[asset_id])).convert("RGB")
                original = [[list(image.getpixel((x, y))) for x in range(image.width)] for y in range(image.height)]
                assert _oracle_pixels(output_pixels) == original

    # Source-to-asset binding and complete grouped replay.
    bad_record = copy.deepcopy(records[0])
    bad_record["media"]["content_sha256"] = "f" * 64
    _reject(make_source_bundle, bad_record, {records[0]["media"]["asset_ids"][0]: asset_bytes[records[0]["media"]["asset_ids"][0]]})
    temporal = records[1]
    temporal_assets = {asset_id: asset_bytes[asset_id] for asset_id in temporal["media"]["asset_ids"]}
    missing = dict(temporal_assets)
    missing.pop(temporal["media"]["asset_ids"][0])
    _reject(make_source_bundle, temporal, missing)
    extra = dict(temporal_assets)
    extra["asset-extra-fixture"] = _png(250)
    _reject(make_source_bundle, temporal, extra)
    one_asset = copy.deepcopy(results[1])
    one_asset["pixels_by_asset"].pop(temporal["media"]["asset_ids"][0])
    _reject(validate_result, bundles[1], one_asset, schedule=schedule, cluster_authority=cluster, split_authority=split)
    forged_pixels = copy.deepcopy(results[1])
    first_asset = temporal["media"]["asset_ids"][0]
    forged_pixels["pixels_by_asset"][first_asset][0][0][0] ^= 1
    _reject(validate_result, bundles[1], _rehashed(forged_pixels), schedule=schedule, cluster_authority=cluster, split_authority=split)
    for field, value in (
        ("split_owner", "locked_test"),
        ("protected_families", {**results[2]["lineage"]["protected_families"], "dedup_cluster": ["forged-cluster"]}),
        ("config_sha256", "0" * 64),
    ):
        forged = copy.deepcopy(directional)
        forged["lineage"][field] = value
        _reject(validate_result, bundles[2], _rehashed(forged), schedule=schedule, cluster_authority=cluster, split_authority=split)
    for field, value in (("seed", 18), ("sample_counter", 99)):
        forged = copy.deepcopy(directional)
        forged["lineage"][field] = value
        _reject(validate_result, bundles[2], _rehashed(forged), schedule=schedule, cluster_authority=cluster, split_authority=split)
    forged_spec = copy.deepcopy(directional)
    forged_spec["lineage"]["transform"]["kind"] = "photometric_identity"
    _reject(validate_result, bundles[2], _rehashed(forged_spec), schedule=schedule, cluster_authority=cluster, split_authority=split)
    forged_label = copy.deepcopy(results[0])
    forged_label["targets"]["label"]["keep_decision"] = "keep"
    _reject(validate_result, bundles[0], forged_label, schedule=schedule, cluster_authority=cluster, split_authority=split)
    bad_bundle_bytes = dict(temporal_assets)
    bad_bundle_bytes[first_asset] = _png(251)
    _reject(make_source_bundle, temporal, bad_bundle_bytes)
    nonfixture_temporal = copy.deepcopy(temporal)
    nonfixture_temporal["provenance"]["source_kind"] = "owned"
    _reject(make_source_bundle, nonfixture_temporal, temporal_assets)

    # Schedule trust boundary and closed operation policy.
    unknown_record = copy.deepcopy(records[0])
    unknown_record["unknown"] = True
    _reject(make_source_bundle, unknown_record, {records[0]["media"]["asset_ids"][0]: asset_bytes[records[0]["media"]["asset_ids"][0]]})
    unknown_label = copy.deepcopy(records[0])
    unknown_label["label"]["selected_action_id"] = "unknown_action"
    _reject(make_source_bundle, unknown_label, {records[0]["media"]["asset_ids"][0]: asset_bytes[records[0]["media"]["asset_ids"][0]]})
    for patch in (
        {"kind": "photometric", "parameters": {}},
        {"kind": "crop", "parameters": {}},
        {"kind": "unknown", "parameters": {}},
        {"kind": "horizontal_flip", "parameters": {"amount": 1}},
        {"kind": "horizontal_flip", "parameters": {"amount": float("nan")}},
    ):
        job = {**jobs[0], "job_id": "job-99", **patch}
        _reject(make_trusted_schedule, bundles, jobs + [job], cluster_authority=cluster, split_authority=split)
    _reject(make_trusted_schedule, bundles, list(reversed(jobs)), cluster_authority=cluster, split_authority=split)
    _reject(make_trusted_schedule, bundles, [{**jobs[0], "seed": True}], cluster_authority=cluster, split_authority=split)
    _reject(make_trusted_schedule, bundles, [{**jobs[0], "sample_counter": -1}], cluster_authority=cluster, split_authority=split)
    _reject(validate_result, bundles[0], results[0], schedule=schedule, cluster_authority=make_cluster_authority(bundles), split_authority=split)

    # Batch exactness: no empty, missing, duplicate, extra, or one-frame batch.
    _reject(validate_lineage_batch, [], [], schedule=schedule, cluster_authority=cluster, split_authority=split)
    _reject(validate_lineage_batch, bundles[:-1], results, schedule=schedule, cluster_authority=cluster, split_authority=split)
    _reject(validate_lineage_batch, bundles, results[:-1], schedule=schedule, cluster_authority=cluster, split_authority=split)
    _reject(validate_lineage_batch, bundles, results + [copy.deepcopy(results[0])], schedule=schedule, cluster_authority=cluster, split_authority=split)

    # Manifest is a canonical zero-record template, not an admission list.
    manifest = validate_derivation_manifest(MANIFEST_PATH)
    with tempfile.TemporaryDirectory(prefix="camera-augmentation-check-") as temp:
        path = Path(temp) / "manifest.jsonl"
        shuffled = dict(reversed(list(manifest.items())))
        path.write_text(json.dumps(shuffled, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        _reject(validate_derivation_manifest, path)
        path.write_text(
            lines := MANIFEST_PATH.read_text(encoding="utf-8").replace(
                '"manifest_sha256":"42047b8ea073d1749b592885966cc1563663c632ec5c119c391d75d615f36714"',
                '"manifest_sha256":"' + "0" * 64 + '"',
            ),
            encoding="utf-8",
        )
        _reject(validate_derivation_manifest, path)
        path.write_text(lines.replace("\n", "") + "\n" + lines, encoding="utf-8")
        _reject(validate_derivation_manifest, path)

    return {
        "status": "pass",
        "action_catalog_count": 26,
        "verifier_catalog_count": 23,
        "action_pair_count": len(ACTION_ORACLE),
        "verifier_pair_count": len(VERIFIER_ORACLE),
        "protected_category_count": len(PROTECTED_ORACLE),
        "complete_source_record_count": len(bundles),
        "complete_asset_count": sum(len(bundle.asset_ids) for bundle in bundles),
        "cluster_receipt_sha256": cluster.receipt_sha256,
        "split_manifest_sha256": split.manifest_sha256,
        "schedule_sha256": schedule.schedule_sha256,
        "flip_output_pixels_sha256": directional["lineage"]["output_pixels_sha256"],
        "flip_output_targets_sha256": directional["lineage"]["output_targets_sha256"],
        "flip_receipt_sha256": directional["lineage"]["receipt_sha256"],
        "identity_receipt_sha256": results[0]["lineage"]["receipt_sha256"],
        "augmentation_config_sha256": AUGMENTATION_CONFIG_SHA256,
        "negative_probe_count": 32,
    }


if __name__ == "__main__":
    print(canonical_json(_run()))
