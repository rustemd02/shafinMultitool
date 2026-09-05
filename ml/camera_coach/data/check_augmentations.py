"""Small runnable adversarial check for the M4-008 augmentation boundary."""

from __future__ import annotations

import copy
from io import BytesIO
import hashlib
import json
from pathlib import Path
import tempfile

from tools import camera_dataset_audit as m3
from tools.dataset.camera_coach_check import validate_record

from . import augmentations as aug

Image = m3.Image


ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = ROOT / "tools" / "dataset" / "tests" / "fixtures" / "camera-coach-fixtures.json"
MANIFEST_PATH = ROOT / "datasets" / "camera-coach" / "v1" / "derivation-manifest.jsonl"

# Independent oracles intentionally do not import production remap tables.
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
    "source_shoot", "scene", "person", "location", "time", "derivation", "sequence", "take", "device", "dedup_cluster",
)


def _reject(callable_, *args, **kwargs) -> None:
    try:
        callable_(*args, **kwargs)
    except (aug.AugmentationError, TypeError, ValueError, KeyError):
        return
    raise AssertionError(f"expected rejection from {getattr(callable_, '__name__', callable_)}")


def _swap(value: str | None, pairs: tuple[tuple[str, str], ...]) -> str | None:
    if value is None:
        return None
    for left, right in pairs:
        if value == left:
            return right
        if value == right:
            return left
    return value


def _oracle_targets(targets: dict, *, flip: bool) -> dict:
    result = copy.deepcopy(targets)
    if not flip:
        return result
    label = result["label"]
    label["acceptable_action_ids"] = [_swap(v, ACTION_ORACLE) for v in label["acceptable_action_ids"]]
    label["forbidden_action_ids"] = [_swap(v, ACTION_ORACLE) for v in label["forbidden_action_ids"]]
    label["selected_action_id"] = _swap(label["selected_action_id"], ACTION_ORACLE)
    for issue in label["issues"]:
        issue["acceptable_action_ids"] = [_swap(v, ACTION_ORACLE) for v in issue["acceptable_action_ids"]]
        issue["forbidden_action_ids"] = [_swap(v, ACTION_ORACLE) for v in issue["forbidden_action_ids"]]
    for verification in label["verification"]:
        verification["action_id"] = _swap(verification["action_id"], ACTION_ORACLE)
        verification["verifier_id"] = _swap(verification["verifier_id"], VERIFIER_ORACLE)
    for candidate in result["subject"]["candidates"]:
        if "region" in candidate:
            x, y, width, height = candidate["region"]
            candidate["region"] = [1.0 - x - width, y, width, height]
    if "episode" in result:
        result["episode"]["action_step"]["action_id"] = _swap(result["episode"]["action_step"]["action_id"], ACTION_ORACLE)
        result["episode"]["outcome_verifier"] = _swap(result["episode"]["outcome_verifier"], VERIFIER_ORACLE)
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


def _one_pixel_png() -> bytes:
    image = Image.new("RGB", (1, 1), (7, 11, 13))
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def _fixtures() -> tuple[list[dict], dict[str, bytes]]:
    payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    records = copy.deepcopy(payload["valid_records"])
    assets: dict[str, bytes] = {}
    for index, record in enumerate(records):
        record["subject"]["candidates"][0]["region"] = [0.125, 0.25, 0.25, 0.125]
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
            raise AssertionError(f"canonical source fixture rejected: {record['record_id']}: {errors}")
    records[2]["label"]["acceptable_action_ids"] = [left for left, _ in ACTION_ORACLE]
    records[2]["label"]["forbidden_action_ids"] = [right for _, right in ACTION_ORACLE]
    records[2]["label"]["selected_action_id"] = ACTION_ORACLE[0][0]
    records[2]["label"]["selection_status"] = "multiple_valid"
    records[2]["label"]["keep_decision"] = "not_keep"
    issue = records[2]["label"]["issues"][0]
    issue["acceptable_action_ids"] = [left for left, _ in ACTION_ORACLE]
    issue["forbidden_action_ids"] = [right for _, right in ACTION_ORACLE]
    records[2]["label"]["verification"] = [
        {"action_id": left, "verifier_id": verifier_left, "result": "not_run", "measurement": "before_after"}
        for (left, _), (verifier_left, _) in zip(ACTION_ORACLE, VERIFIER_ORACLE)
    ]
    records[2]["label"]["verification"][2]["result"] = "pass"
    records[2]["episode"]["action_step"]["action_id"] = ACTION_ORACLE[2][0]
    records[2]["episode"]["outcome_verifier"] = VERIFIER_ORACLE[2][0]
    errors = validate_record(records[2], {}, admission=False)
    if errors:
        raise AssertionError(f"directional source fixture rejected: {errors}")
    records[0]["media"]["content_sha256"] = hashlib.sha256(assets[records[0]["media"]["asset_ids"][0]]).hexdigest()
    return records, assets


def _fixture_m3_items(records: list[dict], assets: dict[str, bytes], root: Path) -> list[m3.MediaItem]:
    """Issue test cluster input independently of the augmentation owner."""
    rows: dict[str, dict] = {}
    for record in records:
        for asset_id in record["media"]["asset_ids"]:
            row = rows.setdefault(
                asset_id,
                {"record_ids": set(), "sequence_ids": set(), "frame_ordinals": set(), "derivation_family_ids": set()},
            )
            row["record_ids"].add(record["record_id"])
            row["derivation_family_ids"].add(record["provenance"]["derivation_family_id"])
            if record["record_type"] == "temporal":
                row["sequence_ids"].add(record["sequence"]["sequence_id"])
                row["frame_ordinals"].update(
                    frame["ordinal"] for frame in record["sequence"]["frames"] if frame["asset_id"] == asset_id
                )
            elif record["record_type"] == "episode":
                row["sequence_ids"].add(record["episode"]["episode_id"])
                row["frame_ordinals"].add(0 if record["episode"]["before"]["asset_id"] == asset_id else 1)
    items = []
    for index, asset_id in enumerate(sorted(rows)):
        encoded = assets[asset_id]
        path = root / f"fixture-asset-{index}.bin"
        path.write_bytes(encoded)
        row = rows[asset_id]
        items.append(
            m3.MediaItem(
                asset_id=asset_id,
                path=path,
                record_ids=tuple(sorted(row["record_ids"])),
                sequence_ids=tuple(sorted(row["sequence_ids"])),
                frame_ordinals=tuple(sorted(row["frame_ordinals"])),
                derivation_family_ids=tuple(sorted(row["derivation_family_ids"])),
                declared_sha256=hashlib.sha256(encoded).hexdigest(),
            )
        )
    return items


def _fixture_split_records(records: list[dict]) -> list[m3.SplitRecord]:
    """Build the metadata-only M3 input independently for fixture issuance."""
    entries = []
    for record in records:
        entry = {
            "record_id": record["record_id"],
            "record_type": record["record_type"],
            "bucket": "synthetic",
            "rights_disposition": record["provenance"]["rights_disposition"],
            "source_shoot_id": record["provenance"]["source_shoot_id"],
            "scene_family_id": record["capture"]["scene_family_id"],
            "person_family_ids": list(record["capture"]["person_family_ids"]),
            "location_family_id": record["capture"]["location_family_id"],
            "time_family_id": record["capture"]["time_family_id"],
            "take_family_id": record["capture"]["take_family_id"],
            "device_family_id": record["capture"]["device_family_id"],
            "derivation_family_id": record["provenance"]["derivation_family_id"],
            "asset_ids": list(record["media"]["asset_ids"]),
            "review": copy.deepcopy(record["review"]),
        }
        if record["record_type"] == "episode":
            entry["sequence_id"] = record["episode"]["episode_id"]
        if record["record_type"] == "temporal":
            entry["sequence_id"] = record["sequence"]["sequence_id"]
            entry["sequence"] = {
                "sequence_id": record["sequence"]["sequence_id"],
                "derivation_family_id": record["provenance"]["derivation_family_id"],
                "frames": [
                    {
                        "asset_id": frame["asset_id"],
                        "sequence_id": record["sequence"]["sequence_id"],
                        "ordinal": frame["ordinal"],
                        "derivation_family_id": record["provenance"]["derivation_family_id"],
                    }
                    for frame in record["sequence"]["frames"]
                ],
            }
        entries.append(entry)
    payload = {
        "manifest_type": m3.SPLIT_MANIFEST_TYPE,
        "schema_id": m3.SPLIT_INPUT_SCHEMA_ID,
        "schema_version": m3.SCHEMA_VERSION,
        "entries": entries,
    }
    with tempfile.TemporaryDirectory(prefix="camera-augmentation-check-split-") as temp:
        path = Path(temp) / "fixture-split-input.json"
        path.write_text(aug.canonical_json(payload), encoding="utf-8")
        return m3.load_split_manifest(path)


def _fixture_authority(records: list[dict], assets: dict[str, bytes]) -> aug.M3Authority:
    """Test-only receipt issuance; production authority loading is disabled."""
    with tempfile.TemporaryDirectory(prefix="camera-augmentation-check-authority-") as temp:
        cluster = m3.cluster_media(_fixture_m3_items(records, assets, Path(temp)))
    split = m3.split_records(
        _fixture_split_records(records),
        cluster,
        seed=0,
        train_ratio=0.8,
        calibration_ratio=0.1,
        locked_test_ratio=0.1,
    )
    return aug._load_fixture_authority(records, cluster, split)


def _rehashed(result: dict) -> dict:
    forged = copy.deepcopy(result)
    body = {key: value for key, value in forged["lineage"].items() if key != "receipt_sha256"}
    forged["lineage"]["receipt_sha256"] = aug.digest(body)
    return forged


def _run() -> dict:
    records, asset_bytes = _fixtures()
    bundles = [aug.make_source_bundle(record, {asset_id: asset_bytes[asset_id] for asset_id in record["media"]["asset_ids"]}) for record in records]
    authority = _fixture_authority(records, asset_bytes)
    schedule = aug.make_trusted_schedule(authority)
    schedule_repeat = aug.make_trusted_schedule(authority)
    assert schedule.schedule_sha256 == schedule_repeat.schedule_sha256
    by_id = {bundle.record["record_id"]: bundle for bundle in bundles}
    results = [aug.augment(by_id[job["record_id"]], schedule, job["job_id"]) for job in schedule.jobs]
    for result in results:
        job = schedule.job(result["job_id"])
        aug.validate_result(by_id[job.record_id], result, authority=authority, schedule=schedule)
        assert result["lineage"]["source_split"] == "fixture"
        assert result["lineage"]["split_owner"] == "fixture"
    assert authority.authority_kind == "fixture"
    assert schedule.schedule()["authority_kind"] == "fixture"

    negatives = 0
    def reject(*args, **kwargs):
        nonlocal negatives
        _reject(*args, **kwargs)
        negatives += 1

    aug.validate_lineage_batch(bundles, results, authority=authority, schedule=schedule)

    # Batch cardinality and authority identity are checked independently of
    # the per-result receipt.  A complete source set is the authority's set,
    # not a caller-selected subset.
    reject(aug.validate_lineage_batch, [], [], authority=authority, schedule=schedule)
    reject(aug.validate_lineage_batch, bundles, results[:-1], authority=authority, schedule=schedule)
    duplicate_results = results[:-1] + [copy.deepcopy(results[0])]
    reject(aug.validate_lineage_batch, bundles, duplicate_results, authority=authority, schedule=schedule)
    reject(aug.validate_lineage_batch, bundles, results + [copy.deepcopy(results[0])], authority=authority, schedule=schedule)
    reject(aug.validate_lineage_batch, bundles + [bundles[0]], results, authority=authority, schedule=schedule)
    cross_split_results = copy.deepcopy(results)
    cross_split_results[0]["lineage"]["source_split"] = "train"
    cross_split_results[0]["lineage"]["split_owner"] = "train"
    cross_split_results[0] = _rehashed(cross_split_results[0])
    reject(aug.validate_lineage_batch, bundles, cross_split_results, authority=authority, schedule=schedule)
    other_authority = _fixture_authority(records, asset_bytes)
    reject(aug.validate_lineage_batch, bundles, results, authority=other_authority, schedule=schedule)

    # Every direction-bearing label location and normalized geometry uses an
    # independent oracle; exact representable coordinates round-trip twice.
    directional = next(result for result in results if result["record_id"] == records[2]["record_id"] and result["lineage"]["transform"]["kind"] == "horizontal_flip")
    source_targets = {
        "capture": copy.deepcopy(records[2]["capture"]),
        "subject": copy.deepcopy(records[2]["subject"]),
        "label": copy.deepcopy(records[2]["label"]),
        "episode": copy.deepcopy(records[2]["episode"]),
    }
    assert _oracle_targets(source_targets, flip=True) == directional["targets"]
    assert _oracle_targets(_oracle_targets(source_targets, flip=True), flip=True) == source_targets
    assert aug._flip_region([0.125, 0.25, 0.25, 0.125], "roundtrip") == [0.625, 0.25, 0.25, 0.125]
    assert aug._flip_region(aug._flip_region([0.125, 0.25, 0.25, 0.125], "roundtrip"), "roundtrip") == [0.125, 0.25, 0.25, 0.125]
    _reject(aug._flip_region, [0.1, 0.2, 0.3, 0.1], "high_precision_roundtrip")
    for result in results:
        if result["lineage"]["transform"]["kind"] == "horizontal_flip":
            for asset_id, output in result["pixels_by_asset"].items():
                with Image.open(BytesIO(asset_bytes[asset_id])) as image:
                    original = [[list(image.convert("RGB").getpixel((x, y))) for x in range(image.width)] for y in range(image.height)]
                assert _oracle_pixels(output) == original

    still_id = records[0]["media"]["asset_ids"][0]
    temporal = records[1]
    temporal_assets = {asset_id: asset_bytes[asset_id] for asset_id in temporal["media"]["asset_ids"]}
    bad_record = copy.deepcopy(records[0])
    bad_record["media"]["content_sha256"] = "f" * 64
    reject(aug.make_source_bundle, bad_record, {still_id: asset_bytes[still_id]})
    missing = dict(temporal_assets)
    missing.pop(temporal["media"]["asset_ids"][0])
    reject(aug.make_source_bundle, temporal, missing)
    extra = dict(temporal_assets)
    extra["asset-extra-fixture"] = _png(250)
    reject(aug.make_source_bundle, temporal, extra)
    one_asset = copy.deepcopy(next(result for result in results if result["record_id"] == temporal["record_id"] and result["lineage"]["transform"]["kind"] == "horizontal_flip"))
    one_asset["pixels_by_asset"].pop(temporal["media"]["asset_ids"][0])
    reject(aug.validate_result, bundles[1], one_asset, authority=authority, schedule=schedule)
    forged = copy.deepcopy(one_asset)
    forged["pixels_by_asset"] = copy.deepcopy(next(result for result in results if result["record_id"] == temporal["record_id"] and result["lineage"]["transform"]["kind"] == "horizontal_flip")["pixels_by_asset"])
    first_asset = temporal["media"]["asset_ids"][0]
    forged["pixels_by_asset"][first_asset][0][0][0] ^= 1
    reject(aug.validate_result, bundles[1], _rehashed(forged), authority=authority, schedule=schedule)
    for field, value in (("split_owner", "locked_test"), ("protected_families", {**directional["lineage"]["protected_families"], "dedup_cluster": ["forged-cluster"]}), ("config_sha256", "0" * 64)):
        forged = copy.deepcopy(directional)
        forged["lineage"][field] = value
        reject(aug.validate_result, bundles[2], _rehashed(forged), authority=authority, schedule=schedule)
    for field, value in (("seed", 18), ("sample_counter", 999)):
        forged = copy.deepcopy(directional)
        forged["lineage"][field] = value
        reject(aug.validate_result, bundles[2], _rehashed(forged), authority=authority, schedule=schedule)
    forged = copy.deepcopy(directional)
    forged["lineage"]["transform"]["kind"] = "photometric_identity"
    reject(aug.validate_result, bundles[2], _rehashed(forged), authority=authority, schedule=schedule)
    oversized_output = copy.deepcopy(directional)
    directional_asset_id = next(iter(oversized_output["pixels_by_asset"]))
    first_output = oversized_output["pixels_by_asset"][directional_asset_id]
    oversized_output["pixels_by_asset"][directional_asset_id] = first_output + [first_output[0]]
    reject(aug.validate_result, bundles[2], oversized_output, authority=authority, schedule=schedule)
    forged = copy.deepcopy(next(result for result in results if result["record_id"] == records[0]["record_id"]))
    forged["targets"]["label"]["keep_decision"] = "keep"
    reject(aug.validate_result, bundles[0], forged, authority=authority, schedule=schedule)
    reject(aug.make_source_bundle, temporal, {**temporal_assets, first_asset: _png(251)})
    unknown_record = copy.deepcopy(records[0])
    unknown_record["unknown"] = True
    reject(aug.make_source_bundle, unknown_record, {still_id: asset_bytes[still_id]})
    unknown_label = copy.deepcopy(records[0])
    unknown_label["label"]["selected_action_id"] = "unknown_action"
    reject(aug.make_source_bundle, unknown_label, {still_id: asset_bytes[still_id]})

    # Production authority loading is hard-disabled; only the private
    # fixture-only path above can issue an in-repo authority.
    reject(aug.load_m3_authority, records, authority.cluster_receipt(), authority.split_receipt())
    production_record = copy.deepcopy(records[1])
    production_record["split"] = "train"
    production_record["provenance"]["source_kind"] = "owned"
    production_record["provenance"]["rights_disposition"] = "approved"
    reject(aug._load_fixture_authority, [production_record], authority.cluster_receipt(), authority.split_receipt())
    production_still = copy.deepcopy(records[0])
    production_still["split"] = "train"
    production_still["provenance"]["source_kind"] = "owned"
    production_still["provenance"]["rights_disposition"] = "approved"
    reject(aug.make_source_bundle, production_still, {still_id: asset_bytes[still_id]})
    mixed_fixture = copy.deepcopy(records[0])
    mixed_fixture["split"] = "train"
    reject(aug.make_source_bundle, mixed_fixture, {still_id: asset_bytes[still_id]})
    wrong_fixture_id = copy.deepcopy(records[0])
    wrong_fixture_id["record_id"] = "cam-still-fixture-forged"
    reject(aug.make_source_bundle, wrong_fixture_id, {still_id: asset_bytes[still_id]})
    mixed_records = copy.deepcopy(records)
    mixed_records[0] = copy.deepcopy(production_still)
    reject(aug._load_fixture_authority, mixed_records, authority.cluster_receipt(), authority.split_receipt())
    bad_fixture_cluster = authority.cluster_receipt()
    bad_fixture_cluster["clusters"][0]["members"][0]["content_sha256"] = "0" * 64
    reject(aug._load_fixture_authority, records, bad_fixture_cluster, authority.split_receipt())
    for field, value in (("seed", 1), ("ratios", {"train": 0.7, "calibration": 0.2, "locked_test": 0.1})):
        bad_fixture_split = authority.split_receipt()
        bad_fixture_split["config"][field] = value
        reject(aug._load_fixture_authority, records, authority.cluster_receipt(), bad_fixture_split)

    # No caller can inject an alternative/partial schedule or transform spec.
    reject(aug.make_trusted_schedule, bundles)
    reject(aug.make_trusted_schedule, authority, [{"job_id": "forged"}])
    reject(aug._load_fixture_authority, records[:1], authority.cluster_receipt(), authority.split_receipt())
    oversized_record = copy.deepcopy(records[1])
    oversized_record["media"]["asset_ids"] = [f"asset-overflow-{index}" for index in range(aug.MAX_ASSETS_PER_BUNDLE + 1)]
    reject(aug.make_source_bundle, oversized_record, {})
    reject(aug._validate_transform, "photometric", {})
    reject(aug._validate_transform, "crop", {})
    reject(aug._validate_transform, "unknown", {})
    reject(aug._validate_transform, "horizontal_flip", {"amount": 1})
    reject(aug._validate_transform, "horizontal_flip", {"amount": float("nan")})
    reject(aug._validate_transform, "horizontal_flip", {"amount": True})
    reject(aug._flip_region, [0.0, float("nan"), 1.0, 0.0], "nonfinite")
    reject(aug._flip_region, [0.0, 0.0, 2.0, 0.0], "range")

    # Authority/schedule/result values are immutable or fresh copies after
    # construction; post-hash mutation cannot alter replay behavior.
    receipt_copy = authority.cluster_receipt()
    receipt_copy["clusters"][0]["cluster_id"] = "cdc_0000000000000000"
    schedule_copy = schedule.schedule()
    schedule_copy["jobs"][0]["seed"] = 999
    assert schedule.schedule_sha256 == schedule_repeat.schedule_sha256
    aug.validate_result(by_id[results[0]["record_id"]], results[0], authority=authority, schedule=schedule)
    for owner, field, value in ((authority, "_rows", ()), (schedule, "_jobs", ())):
        try:
            setattr(owner, field, value)
        except AttributeError:
            pass
        else:
            raise AssertionError(f"{type(owner).__name__} retained mutable authority internals")
    try:
        aug.AUGMENTATION_CONFIG["fixture_asset_sha256"][still_id] = "0" * 64
    except (TypeError, AttributeError):
        pass
    else:
        raise AssertionError("exported augmentation config is mutable")
    original_fixture_alias = aug._FIXTURE_ASSET_SHA256
    aug._FIXTURE_ASSET_SHA256 = ((still_id, "0" * 64),)
    try:
        assert aug.make_source_bundle(records[0], {still_id: asset_bytes[still_id]}).asset_ids == (still_id,)
    finally:
        aug._FIXTURE_ASSET_SHA256 = original_fixture_alias
    original_remap_digest = aug.REMAP_AUTHORITY_SHA256
    aug.REMAP_AUTHORITY_SHA256 = "0" * 64
    try:
        reject(aug.augment, bundles[0], schedule, results[0]["job_id"])
    finally:
        aug.REMAP_AUTHORITY_SHA256 = original_remap_digest

    # Fixture-only arbitrary bytes, oriented storage pixels, truncation, and
    # resource caps all fail before a training result exists.
    reject(aug.make_source_bundle, records[0], {still_id: _one_pixel_png()})
    budget_asset = aug._DecodedAsset("budget", b"x", "0" * 64, 512, 512, b"\0\0\0")
    reject(aug._check_bundle_budget, (budget_asset, budget_asset))
    many_assets = tuple(
        aug._DecodedAsset(f"budget-{index}", b"x", "0" * 64, 1, 1, b"\0\0\0")
        for index in range(aug.MAX_ASSETS_PER_BUNDLE + 1)
    )
    reject(aug._check_bundle_budget, many_assets)
    one = Image.new("RGB", (2, 3), (1, 2, 3))
    exif = Image.Exif()
    exif[274] = 6
    output = BytesIO()
    one.save(output, format="JPEG", exif=exif)
    reject(aug.make_source_bundle, records[0], {still_id: output.getvalue()})
    reject(aug.make_source_bundle, records[0], {still_id: asset_bytes[still_id][:-2]})
    reject(aug.make_source_bundle, records[0], {still_id: b"x" * (aug.MAX_ENCODED_BYTES + 1)})
    for size in ((aug.MAX_WIDTH + 1, 1), (1, aug.MAX_HEIGHT + 1), (513, 512)):
        oversized = BytesIO()
        Image.new("RGB", size, (3, 5, 7)).save(oversized, format="PNG")
        reject(aug.make_source_bundle, records[0], {still_id: oversized.getvalue()})
    gif = BytesIO()
    Image.new("RGB", (2, 2), (0, 0, 0)).save(
        gif,
        format="GIF",
        save_all=True,
        append_images=[Image.new("RGB", (2, 2), (1, 1, 1))],
    )
    reject(aug.make_source_bundle, records[0], {still_id: gif.getvalue()})

    # Grouped production remains unavailable until the independent authority
    # artifact exists; no test fixture is allowed to masquerade as production.
    assert not validate_record(production_record, {}, admission=False)
    reject(aug.make_source_bundle, production_record, temporal_assets)

    # Manifest remains a canonical zero-record template.
    manifest = aug.validate_derivation_manifest(MANIFEST_PATH)
    with tempfile.TemporaryDirectory(prefix="camera-augmentation-manifest-") as temp:
        path = Path(temp) / "manifest.jsonl"
        shuffled = dict(reversed(list(manifest.items())))
        path.write_text(json.dumps(shuffled, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        reject(aug.validate_derivation_manifest, path)
        line = MANIFEST_PATH.read_text(encoding="utf-8")
        path.write_text(line.replace(manifest["manifest_sha256"], "0" * 64), encoding="utf-8")
        reject(aug.validate_derivation_manifest, path)
        path.write_text(line + line, encoding="utf-8")
        reject(aug.validate_derivation_manifest, path)

    return {
        "status": "pass",
        "action_catalog_count": len(m3.ACTION_IDS) if hasattr(m3, "ACTION_IDS") else 26,
        "verifier_catalog_count": len(m3.VERIFIER_IDS) if hasattr(m3, "VERIFIER_IDS") else 23,
        "action_pair_count": len(ACTION_ORACLE),
        "verifier_pair_count": len(VERIFIER_ORACLE),
        "protected_category_count": len(PROTECTED_ORACLE),
        "complete_source_record_count": len(bundles),
        "complete_asset_count": sum(len(bundle.asset_ids) for bundle in bundles),
        "cluster_receipt_sha256": authority.cluster_receipt_sha256,
        "split_manifest_sha256": authority.split_manifest_sha256,
        "schedule_sha256": schedule.schedule_sha256,
        "job_count": len(results),
        "flip_output_pixels_sha256": directional["lineage"]["output_pixels_sha256"],
        "flip_output_targets_sha256": directional["lineage"]["output_targets_sha256"],
        "flip_receipt_sha256": directional["lineage"]["receipt_sha256"],
        "identity_receipt_sha256": next(result["lineage"]["receipt_sha256"] for result in results if result["lineage"]["transform"]["kind"] == "photometric_identity"),
        "augmentation_config_sha256": aug.AUGMENTATION_CONFIG_SHA256,
        "negative_probe_count": negatives,
    }


if __name__ == "__main__":
    print(aug.canonical_json(_run()))
