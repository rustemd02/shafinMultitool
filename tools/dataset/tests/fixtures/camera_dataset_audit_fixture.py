#!/usr/bin/env python3
"""Synthetic, temp-only M3-007 fixture (no media is committed)."""

from __future__ import annotations

import importlib.util
import json
import copy
import hashlib
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[4]
TOOL_PATH = ROOT / "tools/camera_dataset_audit.py"
SPEC = importlib.util.spec_from_file_location("camera_dataset_audit", TOOL_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot import {TOOL_PATH}")
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


def _base_image() -> Image.Image:
    image = Image.new("RGB", (96, 72), (24, 42, 64))
    draw = ImageDraw.Draw(image)
    draw.rectangle((20, 10, 68, 62), fill=(214, 92, 45))
    draw.ellipse((31, 17, 58, 44), fill=(245, 190, 90))
    draw.line((0, 68, 95, 68), fill=(80, 180, 220), width=3)
    return image


def _sequence_frame(color: tuple[int, int, int], offset: int) -> Image.Image:
    image = Image.new("RGB", (96, 72), color)
    draw = ImageDraw.Draw(image)
    draw.rectangle((5 + offset, 8, 36 + offset, 38), fill=(245, 245, 245))
    draw.line((55, 0, 10, 71), fill=(8, 8, 8), width=5)
    return image


def _write_fixture_images(root: Path) -> dict[str, str]:
    base = _base_image()
    images = {
        "asset-base": base,
        "asset-exact": base.copy(),
        "asset-crop": base.crop((8, 4, 88, 68)).resize(base.size, Image.Resampling.BICUBIC),
        "asset-color": ImageEnhance.Color(base).enhance(0.55),
        "asset-near": base.filter(ImageFilter.GaussianBlur(0.6)),
        "asset-far": Image.new("RGB", base.size, (232, 232, 232)),
        "asset-seq-f0": _sequence_frame((140, 38, 48), 0),
        "asset-seq-f1": _sequence_frame((38, 140, 72), 9),
        "asset-seq-f2": _sequence_frame((42, 65, 160), 18),
    }
    far_draw = ImageDraw.Draw(images["asset-far"])
    far_draw.ellipse((5, 5, 30, 30), fill=(0, 0, 0))
    far_draw.line((70, 0, 95, 72), fill=(0, 0, 0), width=5)
    paths: dict[str, str] = {}
    for asset_id, image in images.items():
        path = root / f"{asset_id}.png"
        image.save(path, format="PNG")
        paths[asset_id] = path.name
    # Make the exact pair byte-for-byte identical, not merely pixel-identical.
    (root / "asset-exact.png").write_bytes((root / "asset-base.png").read_bytes())
    return paths


def _manifest(paths: dict[str, str]) -> dict:
    entries = [
        {"asset_id": "asset-base", "path": paths["asset-base"], "record_id": "cam-base", "derivation_family_id": "family-base", "rights_disposition": "fixture_only"},
        {"asset_id": "asset-exact", "path": paths["asset-exact"], "record_id": "cam-exact", "derivation_family_id": "family-exact", "rights_disposition": "fixture_only"},
        {"asset_id": "asset-crop", "path": paths["asset-crop"], "record_id": "cam-crop", "derivation_family_id": "family-crop", "rights_disposition": "fixture_only"},
        {"asset_id": "asset-color", "path": paths["asset-color"], "record_id": "cam-color", "derivation_family_id": "family-color", "rights_disposition": "fixture_only"},
        {"asset_id": "asset-near", "path": paths["asset-near"], "record_id": "cam-near", "derivation_family_id": "family-near", "rights_disposition": "fixture_only"},
        {"asset_id": "asset-far", "path": paths["asset-far"], "record_id": "cam-far", "derivation_family_id": "family-far", "rights_disposition": "fixture_only"},
    ]
    for ordinal in range(3):
        asset_id = f"asset-seq-f{ordinal}"
        entries.append(
            {
                "asset_id": asset_id,
                "path": paths[asset_id],
                "record_id": "cam-seq",
                "sequence_id": "sequence-fixture",
                "frame_ordinal": ordinal,
                "rights_disposition": "fixture_only",
            }
        )
    return {
        "manifest_type": "camera_dedup_input",
        "schema_id": AUDIT.INPUT_SCHEMA_ID,
        "manifest_version": AUDIT.SCHEMA_VERSION,
        "hash_algorithm": "sha256",
        "raw_data_location": "outside_git",
        "entries": entries,
    }


def run() -> None:
    with TemporaryDirectory(prefix="camera-dataset-audit-fixture-") as temp:
        root = Path(temp)
        paths = _write_fixture_images(root)
        manifest_path = root / "manifest.json"
        manifest_path.write_text(json.dumps(_manifest(paths)), encoding="utf-8")
        items = AUDIT.load_manifest(manifest_path, media_root=root)
        output = AUDIT.cluster_media(items, ssim_review=True)
        reversed_output = AUDIT.cluster_media(list(reversed(items)), ssim_review=True)
        assert output == reversed_output, "cluster output depends on input order"
        AUDIT.validate_cluster_output(json.loads(json.dumps(output)))

        by_asset = {
            asset_id: cluster
            for cluster in output["clusters"]
            for asset_id in cluster["asset_ids"]
        }
        target_assets = {"asset-base", "asset-exact", "asset-crop", "asset-color", "asset-near"}
        assert len({by_asset[asset]["cluster_id"] for asset in target_assets}) == 1
        assert by_asset["asset-base"]["cluster_kind"] == "near_duplicate"
        assert output["audit"]["exact_cluster_count"] >= 0
        member_hashes = {
            member["asset_id"]: member["content_sha256"]
            for member in by_asset["asset-base"]["members"]
        }
        assert member_hashes["asset-base"] == member_hashes["asset-exact"]
        assert by_asset["asset-far"]["cluster_id"] not in {by_asset[asset]["cluster_id"] for asset in target_assets}
        sequence = next(item for item in output["sequence_families"] if item["sequence_id"] == "sequence-fixture")
        assert len({by_asset[asset]["cluster_id"] for asset in sequence["asset_ids"]}) == 1
        assert sequence["derivation_family_id"] == AUDIT._derived_sequence_family("sequence-fixture")
        sequence_family = sequence["derivation_family_id"]
        for asset_id in sequence["asset_ids"]:
            member_by_asset = {member["asset_id"]: member for member in by_asset[asset_id]["members"]}
            assert member_by_asset[asset_id]["derivation_family_ids"] == [sequence_family]
        assert output["ssim_review"]["enabled"] is True
        assert output["ssim_review"]["admission_oracle"] is False
        assert output["ssim_review"]["pairs"]
        assert len(AUDIT.perceptual_hash(root / "asset-base.png")) == 16

        bad_manifest = root / "bad.json"
        bad_manifest.write_text(json.dumps({"schema_id": AUDIT.INPUT_SCHEMA_ID, "entries": [{"asset_id": "asset-missing", "path": "missing.png", "rights_disposition": "fixture_only"}]}), encoding="utf-8")
        try:
            AUDIT.load_manifest(bad_manifest, media_root=root)
        except AUDIT.AuditInputError as exc:
            assert "missing_media" in str(exc)
        else:
            raise AssertionError("missing media was accepted")

        unreadable = root / "unreadable.bin"
        unreadable.write_bytes(b"not an image")
        unreadable_manifest = root / "unreadable.json"
        unreadable_manifest.write_text(json.dumps({"entries": [{"asset_id": "asset-bad", "path": unreadable.name, "rights_disposition": "fixture_only"}]}), encoding="utf-8")
        try:
            AUDIT.cluster_media(AUDIT.load_manifest(unreadable_manifest, media_root=root))
        except AUDIT.AuditInputError as exc:
            assert "unreadable_media" in str(exc)
        else:
            raise AssertionError("unreadable media was accepted")

        missing_rights = root / "missing-rights.json"
        missing_rights.write_text(json.dumps({"entries": [{"asset_id": "asset-no-rights", "path": paths["asset-base"]}]}), encoding="utf-8")
        try:
            AUDIT.load_manifest(missing_rights, media_root=root)
        except AUDIT.AuditInputError as exc:
            assert "missing_rights_disposition" in str(exc)
        else:
            raise AssertionError("missing rights disposition was accepted")

        conflicting_sequence = root / "conflicting-sequence.json"
        conflicting_sequence.write_text(
            json.dumps(
                {
                    "entries": [
                        {"asset_id": "asset-seq-f0", "path": paths["asset-seq-f0"], "record_id": "cam-seq", "sequence_id": "sequence-conflict", "frame_ordinal": 0, "derivation_family_id": "family-a", "rights_disposition": "fixture_only"},
                        {"asset_id": "asset-seq-f1", "path": paths["asset-seq-f1"], "record_id": "cam-seq", "sequence_id": "sequence-conflict", "frame_ordinal": 1, "derivation_family_id": "family-b", "rights_disposition": "fixture_only"},
                    ]
                }
            ),
            encoding="utf-8",
        )
        try:
            AUDIT.load_manifest(conflicting_sequence, media_root=root)
        except AUDIT.AuditInputError as exc:
            assert "sequence_derivation_family_conflict" in str(exc)
        else:
            raise AssertionError("conflicting sequence families were accepted")

        media_map_main = root / "media-map-main.json"
        media_map_main.write_text(
            json.dumps(
                {
                    "schema_id": AUDIT.INPUT_SCHEMA_ID,
                    "entries": [{"asset_id": "asset-base", "record_id": "cam-base", "derivation_family_id": "family-base", "rights_disposition": "fixture_only"}],
                }
            ),
            encoding="utf-8",
        )
        wrong_digest = "0" * 64
        map_rows = [
            {"asset_id": "asset-base", "path": paths["asset-base"], "sha256": wrong_digest},
            {"asset_id": "asset-base", "path": paths["asset-base"]},
        ]
        map_errors = []
        for rows in (map_rows, list(reversed(map_rows))):
            media_map = root / f"media-map-{len(map_errors)}.json"
            media_map.write_text(json.dumps({"schema_id": AUDIT.INPUT_SCHEMA_ID, "entries": rows}), encoding="utf-8")
            try:
                AUDIT.load_manifest(media_map_main, media_root=root, media_manifest=media_map)
            except AUDIT.AuditInputError as exc:
                map_errors.append(str(exc))
            else:
                raise AssertionError("conflicting media-map rows were accepted")
        assert map_errors[0] == map_errors[1]

        leaking_map = root / "leaking-map.json"
        leaking_map.write_text(
            json.dumps({"schema_id": AUDIT.INPUT_SCHEMA_ID, "entries": [{"asset_id": "asset-base", "path": paths["asset-base"], "candidate": "must-not-pass"}]}),
            encoding="utf-8",
        )
        try:
            AUDIT.load_manifest(media_map_main, media_root=root, media_manifest=leaking_map)
        except AUDIT.AuditInputError as exc:
            assert "candidate_identity_leakage" in str(exc)
        else:
            raise AssertionError("candidate/model identity leaked through media map")

        hostile_ppm = root / "hostile.ppm"
        # The header is tiny; Pillow must reject it before attempting a pixel allocation.
        hostile_ppm.write_bytes(b"P6\n100000000 100000000\n255\n")
        try:
            AUDIT._load_image(hostile_ppm)
        except AUDIT.AuditInputError as exc:
            assert "decompression_bomb" in str(exc)
        else:
            raise AssertionError("hostile decompression-bomb header was accepted")

        for bad_value in (True, 1.5):
            try:
                AUDIT.cluster_media(items, phash_distance=bad_value)
            except AUDIT.AuditInputError as exc:
                assert "phash_distance" in str(exc)
            else:
                raise AssertionError("non-integer pHash distance was accepted")
        for bad_value in (float("nan"), float("inf"), float("-inf")):
            try:
                AUDIT.cluster_media(items, descriptor_similarity=bad_value)
            except AUDIT.AuditInputError as exc:
                assert "descriptor_similarity" in str(exc)
            else:
                raise AssertionError("non-finite descriptor threshold was accepted")
        for bad_value in (1, None, "true"):
            try:
                AUDIT.cluster_media(items, ssim_review=bad_value)
            except AUDIT.AuditInputError as exc:
                assert "ssim_review" in str(exc)
            else:
                raise AssertionError("non-boolean SSIM flag was accepted")

        def split_entry(
            record_id: str,
            asset_ids: list[str],
            suffix: str,
            *,
            bucket: str = "organic",
            sequence_id: str | None = None,
            derivation_family_id: str | None = None,
            source_kind: str | None = None,
        ) -> dict:
            entry = {
                "record_id": record_id,
                "asset_ids": asset_ids,
                "bucket": bucket,
                "source_shoot_id": f"split-shoot-{suffix}",
                "scene_family_id": f"split-scene-{suffix}",
                "person_family_ids": [f"split-person-{suffix}"],
                "location_family_id": f"split-location-{suffix}",
                "time_family_id": f"split-time-{suffix}",
                "derivation_family_id": derivation_family_id or f"split-derivation-{suffix}",
                "rights_disposition": "fixture_only" if bucket == "synthetic" else "approved",
                "review": {
                    "status": "dual_reviewed",
                    "vote_history": [
                        {
                            "vote_id": f"vote-{suffix}-a",
                            "annotator_id": f"annotator-{suffix}-a",
                            "submitted_at": "2026-09-05T00:00:00Z",
                            "decision": "accept",
                        },
                        {
                            "vote_id": f"vote-{suffix}-b",
                            "annotator_id": f"annotator-{suffix}-b",
                            "submitted_at": "2026-09-05T00:00:01Z",
                            "decision": "accept",
                        },
                    ],
                    "adjudication_history": [],
                },
            }
            if source_kind is not None:
                entry["source_kind"] = source_kind
            if sequence_id is not None:
                entry["sequence_id"] = sequence_id
            return entry

        def split_document(entries: list[dict]) -> dict:
            return {
                "manifest_type": "camera_split_input",
                "schema_id": AUDIT.SPLIT_INPUT_SCHEMA_ID,
                "schema_version": AUDIT.SCHEMA_VERSION,
                "entries": entries,
            }

        sequence_receipt = next(item for item in output["sequence_families"] if item["sequence_id"] == "sequence-fixture")
        split_entries = [
            split_entry("split-base", ["asset-base"], "base"),
            split_entry("split-exact", ["asset-exact"], "exact"),
            split_entry(
                "split-sequence",
                ["asset-seq-f0", "asset-seq-f1", "asset-seq-f2"],
                "sequence",
                sequence_id="sequence-fixture",
                derivation_family_id=sequence_receipt["derivation_family_id"],
            ),
            split_entry("split-far", ["asset-far"], "far", bucket="synthetic", source_kind="synthetic_fixture"),
        ]
        split_manifest = root / "split-input.json"
        split_manifest.write_text(
            json.dumps(
                split_document(split_entries)
            ),
            encoding="utf-8",
        )
        cluster_path = root / "clusters.json"
        cluster_path.write_text(json.dumps(output, sort_keys=True), encoding="utf-8")
        cli_outputs: dict[str, bytes] = {}
        for hash_seed in ("1", "5"):
            cli_output = root / f"split-cli-{hash_seed}.json"
            cli_environment = os.environ.copy()
            cli_environment["PYTHONHASHSEED"] = hash_seed
            cli_result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "--split",
                    "--split-manifest",
                    str(split_manifest),
                    "--cluster-output",
                    str(cluster_path),
                    "--seed",
                    "1",
                    "--train-ratio",
                    "0.5",
                    "--calibration-ratio",
                    "0.25",
                    "--locked-test-ratio",
                    "0.25",
                    "--output",
                    str(cli_output),
                ],
                cwd=ROOT,
                env=cli_environment,
                check=False,
                capture_output=True,
                text=True,
            )
            assert cli_result.returncode == 0, cli_result.stderr
            cli_outputs[hash_seed] = cli_output.read_bytes()
        assert cli_outputs["1"] == cli_outputs["5"], "CLI split output depends on PYTHONHASHSEED"
        cli_sha256 = hashlib.sha256(cli_outputs["1"]).hexdigest()
        split_records = AUDIT.load_split_manifest(split_manifest)
        split_output = AUDIT.split_records(
            split_records,
            output,
            seed=1,
            train_ratio=0.5,
            calibration_ratio=0.25,
            locked_test_ratio=0.25,
        )
        reverse_split = AUDIT.split_records(
            list(reversed(split_records)),
            output,
            seed=1,
            train_ratio=0.5,
            calibration_ratio=0.25,
            locked_test_ratio=0.25,
        )
        assert split_output == reverse_split, "split output depends on input order"
        assert split_output["cross_split_leak_count"] == 0
        assert split_output["counts"]["family_counts"]["dedup_cluster"] == split_output["counts"]["dedup_cluster_count"]
        assert {row["record_id"] for row in split_output["assignments"]} == {entry["record_id"] for entry in split_entries}
        split_text = json.dumps(split_output)
        assert all(token not in split_text for token in ("asset_id", "asset_ids", "path", "content_sha256"))
        assert all(
            len({row["split"] for row in split_output["assignments"] if row["bucket"] == bucket}) <= 3
            for bucket in ("organic", "synthetic")
        )
        AUDIT.validate_split_output(json.loads(json.dumps(split_output)))

        counted_document = split_document(split_entries)
        counted_document["record_count"] = len(split_entries)
        counted_manifest = root / "counted-split-input.json"
        counted_manifest.write_text(json.dumps(counted_document), encoding="utf-8")
        assert AUDIT.load_split_manifest(counted_manifest) == split_records

        assert "admission_sha256" in AUDIT._canonical_split_records(split_records)[0]
        try:
            AUDIT.SplitRecord(
                "forged-record",
                ("asset-base",),
                "organic",
                split_records[0].families,
                "approved",
                "dual_reviewed",
            )
        except TypeError as exc:
            assert "load_split_manifest" in str(exc)
        else:
            raise AssertionError("public SplitRecord constructor remained available")

        def forge_split_record(rights: str, status: str) -> object:
            forged = object.__new__(AUDIT.SplitRecord)
            for field_name in ("record_id", "asset_ids", "bucket", "families"):
                object.__setattr__(forged, field_name, getattr(split_records[0], field_name))
            object.__setattr__(forged, "rights_disposition", rights)
            object.__setattr__(forged, "review_status", status)
            return forged

        for forged_rights, forged_status in (
            ("denied", "dual_reviewed"),
            ("approved", "unreviewed"),
            ("approved", "dual_reviewed"),
        ):
            forged = forge_split_record(forged_rights, forged_status)
            try:
                AUDIT.split_records(
                    [forged],
                    output,
                    train_ratio=1.0,
                    calibration_ratio=0.0,
                    locked_test_ratio=0.0,
                )
            except AUDIT.AuditInputError as exc:
                assert "split_record_admission_required" in str(exc)
            else:
                raise AssertionError("caller-created split record emitted a passing receipt")

        mutated_admission = copy.copy(split_records[0])
        object.__setattr__(mutated_admission, "rights_disposition", "denied")
        try:
            AUDIT.split_records(
                [mutated_admission],
                output,
                train_ratio=1.0,
                calibration_ratio=0.0,
                locked_test_ratio=0.0,
            )
        except AUDIT.AuditInputError as exc:
            assert "split_record_admission_conflict" in str(exc)
        else:
            raise AssertionError("mutated admission evidence emitted a passing receipt")

        def forged_admission_record(base: object, admission: object) -> object:
            forged = object.__new__(AUDIT.SplitRecord)
            for field_name in ("record_id", "asset_ids", "bucket", "families", "rights_disposition", "review_status"):
                object.__setattr__(forged, field_name, getattr(base, field_name))
            object.__setattr__(forged, "_admission", admission)
            return forged

        base_record = split_records[0]
        base_admission = base_record._admission
        valid_review_json = base_admission.review_json

        replayed_admission = forged_admission_record(split_records[1], base_admission)
        try:
            AUDIT.split_records(
                [replayed_admission],
                output,
                train_ratio=1.0,
                calibration_ratio=0.0,
                locked_test_ratio=0.0,
            )
        except AUDIT.AuditInputError as exc:
            assert "split_record_admission_conflict" in str(exc)
        else:
            raise AssertionError("admission evidence replayed onto another record")

        mutated_record_id = copy.copy(base_record)
        object.__setattr__(mutated_record_id, "record_id", "split-mutated")
        try:
            AUDIT.split_records(
                [mutated_record_id],
                output,
                train_ratio=1.0,
                calibration_ratio=0.0,
                locked_test_ratio=0.0,
            )
        except AUDIT.AuditInputError as exc:
            assert "split_record_admission_conflict" in str(exc)
        else:
            raise AssertionError("mutated record projection emitted a passing receipt")

        wrong_digest = AUDIT._SplitAdmission(
            review_json=valid_review_json,
            rights_disposition=base_admission.rights_disposition,
            review_status=base_admission.review_status,
            record_sha256="0" * 64,
        )
        try:
            AUDIT.split_records(
                [forged_admission_record(base_record, wrong_digest)],
                output,
                train_ratio=1.0,
                calibration_ratio=0.0,
                locked_test_ratio=0.0,
            )
        except AUDIT.AuditInputError as exc:
            assert "split_record_admission_conflict" in str(exc)
        else:
            raise AssertionError("arbitrary admission digest was accepted")

        noncanonical_review = AUDIT._SplitAdmission(
            review_json=valid_review_json + " ",
            rights_disposition=base_admission.rights_disposition,
            review_status=base_admission.review_status,
            record_sha256=base_admission.record_sha256,
        )
        try:
            AUDIT.split_records(
                [forged_admission_record(base_record, noncanonical_review)],
                output,
                train_ratio=1.0,
                calibration_ratio=0.0,
                locked_test_ratio=0.0,
            )
        except AUDIT.AuditInputError as exc:
            assert "split_record_admission_invalid" in str(exc)
        else:
            raise AssertionError("non-canonical admission evidence was accepted")

        status_only = AUDIT._SplitAdmission(
            review_json=AUDIT._canonical_json({"status": "dual_reviewed"}),
            rights_disposition=base_admission.rights_disposition,
            review_status=base_admission.review_status,
            record_sha256=base_admission.record_sha256,
        )
        omitted_review_evidence = object.__new__(AUDIT._SplitAdmission)
        object.__setattr__(omitted_review_evidence, "rights_disposition", base_admission.rights_disposition)
        object.__setattr__(omitted_review_evidence, "review_status", base_admission.review_status)
        object.__setattr__(omitted_review_evidence, "record_sha256", base_admission.record_sha256)
        mismatched_status = AUDIT._SplitAdmission(
            review_json=valid_review_json,
            rights_disposition=base_admission.rights_disposition,
            review_status="adjudicated",
            record_sha256=base_admission.record_sha256,
        )
        for mismatched, expected in (
            (mismatched_status, "split_record_admission_conflict"),
        ):
            try:
                AUDIT.split_records(
                    [forged_admission_record(base_record, mismatched)],
                    output,
                    train_ratio=1.0,
                    calibration_ratio=0.0,
                    locked_test_ratio=0.0,
                )
            except AUDIT.AuditInputError as exc:
                assert expected in str(exc), exc
            else:
                raise AssertionError("mismatched admission status was accepted")
        for forged_review, expected in (
            (status_only, "review_not_admissible"),
            (omitted_review_evidence, "split_record_admission_invalid"),
            (
                AUDIT._SplitAdmission(
                    review_json=AUDIT._canonical_json({**json.loads(valid_review_json), "status": "rejected"}),
                    rights_disposition=base_admission.rights_disposition,
                    review_status=base_admission.review_status,
                    record_sha256=base_admission.record_sha256,
                ),
                "review_not_admissible",
            ),
            (
                AUDIT._SplitAdmission(
                    review_json=AUDIT._canonical_json({**json.loads(valid_review_json), "status": "unreviewed"}),
                    rights_disposition=base_admission.rights_disposition,
                    review_status=base_admission.review_status,
                    record_sha256=base_admission.record_sha256,
                ),
                "review_not_admissible",
            ),
        ):
            try:
                AUDIT.split_records(
                    [forged_admission_record(base_record, forged_review)],
                    output,
                    train_ratio=1.0,
                    calibration_ratio=0.0,
                    locked_test_ratio=0.0,
                )
            except AUDIT.AuditInputError as exc:
                assert expected in str(exc), exc
            else:
                raise AssertionError("forged denied/unreviewed review evidence was accepted")

        split_jsonl = root / "split-input.jsonl"
        jsonl_header = split_document([])
        jsonl_header.pop("entries")
        split_jsonl.write_text(
            "\n".join(json.dumps(row) for row in [jsonl_header, *split_entries]) + "\n",
            encoding="utf-8",
        )
        assert AUDIT.load_split_manifest(split_jsonl) == split_records
        mixed_jsonl = root / "mixed-inline-entries.jsonl"
        mixed_jsonl.write_text(
            "\n".join(json.dumps(row) for row in [split_document([]), *split_entries]) + "\n",
            encoding="utf-8",
        )
        try:
            AUDIT.load_split_manifest(mixed_jsonl)
        except AUDIT.AuditInputError as exc:
            assert "inline_entries_in_jsonl_header" in str(exc)
        else:
            raise AssertionError("JSONL header inline entries were silently discarded")
        for header_mutation, expected in (
            (lambda value: value.pop("manifest_type"), "invalid_split_manifest_type"),
            (lambda value: value.__setitem__("manifest_type", 1), "invalid_split_manifest_type"),
            (lambda value: value.__setitem__("manifest_type", "not_camera_split_input"), "invalid_split_manifest_type"),
            (lambda value: value.pop("schema_id"), "invalid_split_schema_id"),
            (lambda value: value.pop("schema_version"), "invalid_split_schema_version"),
            (lambda value: value.__setitem__("schema_version", "v0.0.0"), "invalid_split_schema_version"),
            (lambda value: value.__setitem__("record_count", True), "invalid_split_record_count"),
            (lambda value: value.__setitem__("record_count", 1.5), "invalid_split_record_count"),
            (lambda value: value.__setitem__("record_count", 99), "split_manifest_record_count_mismatch"),
        ):
            bad_header = split_document([])
            bad_header.pop("entries")
            header_mutation(bad_header)
            bad_header_path = root / f"bad-header-{expected}.jsonl"
            bad_header_path.write_text(
                "\n".join(json.dumps(row) for row in [bad_header, split_entries[0]]) + "\n",
                encoding="utf-8",
            )
            try:
                AUDIT.load_split_manifest(bad_header_path)
            except AUDIT.AuditInputError as exc:
                assert expected in str(exc), (expected, exc)
            else:
                raise AssertionError(f"split header mutation {expected} was accepted")
        unversioned_path = root / "unversioned-split.json"
        unversioned_path.write_text(
            json.dumps({"manifest_type": "camera_split_input", "entries": split_entries}),
            encoding="utf-8",
        )
        try:
            AUDIT.load_split_manifest(unversioned_path)
        except AUDIT.AuditInputError as exc:
            assert "invalid_split_schema_id" in str(exc)
        else:
            raise AssertionError("unversioned split input was accepted")
        for forbidden_field in ("label", "locked_label", "content", "content_sha256"):
            forbidden_entry = copy.deepcopy(split_entries[0])
            forbidden_entry[forbidden_field] = "must-not-enter"
            forbidden_path = root / f"forbidden-{forbidden_field}.json"
            forbidden_path.write_text(json.dumps(split_document([forbidden_entry])), encoding="utf-8")
            try:
                AUDIT.load_split_manifest(forbidden_path)
            except AUDIT.AuditInputError as exc:
                assert "content_payload_in_split_input" in str(exc), (forbidden_field, exc)
            else:
                raise AssertionError(f"split input field {forbidden_field} was accepted")

        unknown_topology_cases = []
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["annotation"] = "must-not-enter"
        unknown_topology_cases.append(("record", unknown_entry, "annotation"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["provenance"] = {"ground_truth": "must-not-enter"}
        unknown_topology_cases.append(("provenance", unknown_entry, "ground_truth"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["capture"] = {"target": "must-not-enter"}
        unknown_topology_cases.append(("capture", unknown_entry, "target"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["media"] = {"caption": "must-not-enter"}
        unknown_topology_cases.append(("media", unknown_entry, "caption"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["sequence"] = {"sequence_id": "sequence-fixture", "caption": "must-not-enter"}
        unknown_topology_cases.append(("sequence", unknown_entry, "caption"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["sequence"] = {
            "sequence_id": "sequence-fixture",
            "frames": [{"asset_id": "asset-seq-f0", "raw_bytes": "must-not-enter"}],
        }
        unknown_topology_cases.append(("frame", unknown_entry, "raw_bytes"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["review"]["annotation"] = "must-not-enter"
        unknown_topology_cases.append(("review", unknown_entry, "annotation"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["review"]["vote_history"][0]["image_base64"] = "must-not-enter"
        unknown_topology_cases.append(("vote", unknown_entry, "image_base64"))
        unknown_entry = copy.deepcopy(split_entries[0])
        unknown_entry["review"]["adjudication_history"] = [{
            "adjudication_id": "adjudication-unknown",
            "adjudicator_id": "adjudicator-unknown",
            "occurred_at": "2026-09-05T00:00:02Z",
            "based_on_vote_ids": ["vote-base-a", "vote-base-b"],
            "outcome": "accepted",
            "target": "must-not-enter",
        }]
        unknown_topology_cases.append(("adjudication", unknown_entry, "target"))
        for object_name, unknown_entry, unknown_field in unknown_topology_cases:
            unknown_path = root / f"unknown-{object_name}.json"
            unknown_path.write_text(json.dumps(split_document([unknown_entry])), encoding="utf-8")
            try:
                AUDIT.load_split_manifest(unknown_path)
            except AUDIT.AuditInputError as exc:
                assert "unknown_split_field" in str(exc), (object_name, unknown_field, exc)
                assert unknown_field in str(exc), (object_name, unknown_field, exc)
            else:
                raise AssertionError(f"unknown {object_name} field {unknown_field} was accepted")
        unknown_header = split_document([split_entries[0]])
        unknown_header["image_base64"] = "must-not-enter"
        unknown_header_path = root / "unknown-header.json"
        unknown_header_path.write_text(json.dumps(unknown_header), encoding="utf-8")
        try:
            AUDIT.load_split_manifest(unknown_header_path)
        except AUDIT.AuditInputError as exc:
            assert "unknown_split_field" in str(exc)
            assert "image_base64" in str(exc)
        else:
            raise AssertionError("unknown split header field was accepted")

        seed_five = AUDIT.split_records(
            split_records,
            output,
            seed=5,
            train_ratio=0.5,
            calibration_ratio=0.25,
            locked_test_ratio=0.25,
        )
        assert seed_five["cross_split_leak_count"] == 0
        assert {row["record_id"]: row["split"] for row in seed_five["assignments"]} != {
            row["record_id"]: row["split"] for row in split_output["assignments"]
        }, "changed seed did not change this multi-component fixture"
        assert {row["record_id"] for row in seed_five["assignments"]} == {row["record_id"] for row in split_output["assignments"]}
        for bucket in ("organic", "synthetic"):
            bucket_rows = [row for row in split_output["assignments"] if row["bucket"] == bucket]
            assert len({row["split"] for row in bucket_rows}) <= 3

        leakage_categories = ("source_shoot", "scene", "person", "location", "time", "derivation")
        for category in leakage_categories:
            left = split_entry(f"leak-{category}-left", ["asset-base"], f"leak-{category}-left")
            right = split_entry(f"leak-{category}-right", ["asset-far"], f"leak-{category}-right")
            field = {
                "source_shoot": "source_shoot_id",
                "scene": "scene_family_id",
                "person": "person_family_ids",
                "location": "location_family_id",
                "time": "time_family_id",
                "derivation": "derivation_family_id",
            }[category]
            right[field] = left[field]
            leakage_path = root / f"leak-{category}.json"
            leakage_path.write_text(
                json.dumps(split_document([left, right])),
                encoding="utf-8",
            )
            leakage_records = AUDIT.load_split_manifest(leakage_path)
            leakage_output = AUDIT.split_records(
                leakage_records,
                output,
                seed=1,
                train_ratio=0.5,
                calibration_ratio=0.5,
                locked_test_ratio=0.0,
            )
            assert leakage_output["cross_split_leak_count"] == 0
            component_for = {row["record_id"]: row["component_id"] for row in leakage_output["assignments"]}
            assert component_for[left["record_id"]] == component_for[right["record_id"]]

        for category, field in (("take", "take_family_id"), ("device", "device_family_id")):
            left = split_entry(f"leak-{category}-left", ["asset-base"], f"leak-{category}-left")
            right = split_entry(f"leak-{category}-right", ["asset-far"], f"leak-{category}-right")
            left[field] = right[field] = f"split-{category}-shared"
            leakage_path = root / f"leak-{category}.json"
            leakage_path.write_text(json.dumps(split_document([left, right])), encoding="utf-8")
            leakage_output = AUDIT.split_records(
                AUDIT.load_split_manifest(leakage_path),
                output,
                seed=1,
                train_ratio=0.5,
                calibration_ratio=0.5,
                locked_test_ratio=0.0,
            )
            component_for = {row["record_id"]: row["component_id"] for row in leakage_output["assignments"]}
            assert component_for[left["record_id"]] == component_for[right["record_id"]]

        dedup_left = split_entry("leak-dedup-left", ["asset-base"], "leak-dedup-left")
        dedup_right = split_entry("leak-dedup-right", ["asset-exact"], "leak-dedup-right")
        dedup_path = root / "leak-dedup-cluster.json"
        dedup_path.write_text(json.dumps(split_document([dedup_left, dedup_right])), encoding="utf-8")
        dedup_output = AUDIT.split_records(AUDIT.load_split_manifest(dedup_path), output, train_ratio=0.5, calibration_ratio=0.5, locked_test_ratio=0.0)
        dedup_components = {row["record_id"]: row["component_id"] for row in dedup_output["assignments"]}
        assert dedup_components[dedup_left["record_id"]] == dedup_components[dedup_right["record_id"]]

        sequence_entries = [
            split_entry("leak-sequence-left", ["asset-seq-f0"], "leak-sequence-left", sequence_id="sequence-fixture", derivation_family_id=sequence_receipt["derivation_family_id"]),
            split_entry("leak-sequence-right", ["asset-seq-f1"], "leak-sequence-right", sequence_id="sequence-fixture", derivation_family_id=sequence_receipt["derivation_family_id"]),
        ]
        sequence_path = root / "leak-sequence.json"
        sequence_path.write_text(json.dumps(split_document(sequence_entries)), encoding="utf-8")
        sequence_output = AUDIT.split_records(AUDIT.load_split_manifest(sequence_path), output, train_ratio=0.5, calibration_ratio=0.5, locked_test_ratio=0.0)
        sequence_components = {row["record_id"]: row["component_id"] for row in sequence_output["assignments"]}
        assert sequence_components[sequence_entries[0]["record_id"]] == sequence_components[sequence_entries[1]["record_id"]]

        assert split_records[0].review_status == "dual_reviewed"
        valid_adjudicated = copy.deepcopy(split_entries[0])
        valid_adjudicated["record_id"] = "review-adjudicated"
        valid_adjudicated["review"]["status"] = "adjudicated"
        valid_adjudicated["review"]["vote_history"][1]["decision"] = "reject"
        valid_adjudicated["review"]["adjudication_history"] = [
            {
                "adjudication_id": "adjudication-fixture-001",
                "adjudicator_id": "adjudicator-fixture-001",
                "occurred_at": "2026-09-05T00:00:02Z",
                "based_on_vote_ids": ["vote-base-a", "vote-base-b"],
                "outcome": "accepted",
            }
        ]
        adjudicated_path = root / "valid-adjudicated.json"
        adjudicated_path.write_text(json.dumps(split_document([valid_adjudicated])), encoding="utf-8")
        adjudicated_records = AUDIT.load_split_manifest(adjudicated_path)
        assert adjudicated_records[0].review_status == "adjudicated"

        review_cases = []
        conflicting = copy.deepcopy(split_entries[0])
        conflicting["record_id"] = "review-conflicting"
        conflicting["review"]["vote_history"][1]["decision"] = "reject"
        review_cases.append((conflicting, "review_conflict_unresolved"))
        rejected_adjudication = copy.deepcopy(valid_adjudicated)
        rejected_adjudication["record_id"] = "review-rejected-adjudication"
        rejected_adjudication["review"]["adjudication_history"][0]["outcome"] = "rejected"
        review_cases.append((rejected_adjudication, "release adjudication"))
        bad_scope = copy.deepcopy(valid_adjudicated)
        bad_scope["record_id"] = "review-bad-scope"
        bad_scope["review"]["adjudication_history"][0]["based_on_vote_ids"] = ["vote-base-a"]
        review_cases.append((bad_scope, "invalid_adjudication_scope"))
        bare_status = copy.deepcopy(split_entries[0])
        bare_status["record_id"] = "review-bare-status"
        bare_status.pop("review")
        bare_status["review_status"] = "reviewed"
        review_cases.append((bare_status, "review_status_only_not_admissible"))
        for review_entry, expected in review_cases:
            review_path = root / f"{review_entry['record_id']}.json"
            review_path.write_text(json.dumps(split_document([review_entry])), encoding="utf-8")
            try:
                AUDIT.load_split_manifest(review_path)
            except AUDIT.AuditInputError as exc:
                assert expected in str(exc), (expected, exc)
            else:
                raise AssertionError(f"review case {review_entry['record_id']} was accepted")

        for mutation, expected in (
            (lambda value: value.pop("source_shoot_id"), "missing_protected_id"),
            (lambda value: value.__setitem__("rights_disposition", "unresolved"), "rights_not_admissible"),
            (lambda value: (value.pop("review"), value.__setitem__("review_status", "unreviewed")), "review_status_only_not_admissible"),
            (lambda value: value.__setitem__("split", "train"), "preassigned_split_not_allowed"),
        ):
            mutated = copy.deepcopy(split_entries[0])
            mutation(mutated)
            mutation_path = root / f"bad-split-{expected}.json"
            mutation_path.write_text(json.dumps(split_document([mutated])), encoding="utf-8")
            try:
                AUDIT.load_split_manifest(mutation_path)
            except AUDIT.AuditInputError as exc:
                assert expected in str(exc), (expected, exc)
            else:
                raise AssertionError(f"split mutation {expected} was accepted")

        duplicate_path = root / "duplicate-split-record.json"
        duplicate_path.write_text(json.dumps(split_document([split_entries[0], copy.deepcopy(split_entries[0])])), encoding="utf-8")
        try:
            AUDIT.load_split_manifest(duplicate_path)
        except AUDIT.AuditInputError as exc:
            assert "duplicate_record_id" in str(exc)
        else:
            raise AssertionError("duplicate split record ID was accepted")

        bucket_conflict = copy.deepcopy(split_entries[0])
        bucket_conflict["bucket"] = "organic"
        bucket_conflict["source_kind"] = "synthetic_fixture"
        bucket_path = root / "bucket-conflict.json"
        bucket_path.write_text(json.dumps(split_document([bucket_conflict])), encoding="utf-8")
        try:
            AUDIT.load_split_manifest(bucket_path)
        except AUDIT.AuditInputError as exc:
            assert "bucket_source_kind_conflict" in str(exc)
        else:
            raise AssertionError("bucket/source-kind conflict was accepted")

        missing_cluster = copy.deepcopy(split_entries[0])
        missing_cluster["asset_ids"] = ["asset-not-in-receipt"]
        missing_cluster_path = root / "missing-cluster-asset.json"
        missing_cluster_path.write_text(json.dumps(split_document([missing_cluster])), encoding="utf-8")
        try:
            AUDIT.split_records(AUDIT.load_split_manifest(missing_cluster_path), output)
        except AUDIT.AuditInputError as exc:
            assert "asset_missing_from_cluster_receipt" in str(exc)
        else:
            raise AssertionError("asset absent from cluster receipt was accepted")

        raw_path_entry = copy.deepcopy(split_entries[0])
        raw_path_entry["media_path"] = "../outside.png"
        raw_path_path = root / "raw-path-split.json"
        raw_path_path.write_text(json.dumps(split_document([raw_path_entry])), encoding="utf-8")
        try:
            AUDIT.load_split_manifest(raw_path_path)
        except AUDIT.AuditInputError as exc:
            assert "raw_media_reference_in_split_input" in str(exc)
        else:
            raise AssertionError("raw media path was accepted by split loader")

        for bad_seed in (True, 1.5):
            try:
                AUDIT.split_records(split_records, output, seed=bad_seed)
            except AUDIT.AuditInputError as exc:
                assert "seed" in str(exc)
            else:
                raise AssertionError("invalid split seed was accepted")
        try:
            AUDIT.split_records(split_records, output, train_ratio=float("nan"))
        except AUDIT.AuditInputError as exc:
            assert "train_ratio" in str(exc)
        else:
            raise AssertionError("non-finite split ratio was accepted")

        schema_extra = copy.deepcopy(split_output)
        schema_extra["unexpected"] = True
        try:
            AUDIT.validate_split_output(schema_extra)
        except AUDIT.AuditInputError as exc:
            assert "split_schema_invalid" in str(exc)
        else:
            raise AssertionError("schema extra field was accepted")
        schema_missing = copy.deepcopy(split_output)
        del schema_missing["assignments"]
        try:
            AUDIT.validate_split_output(schema_missing)
        except AUDIT.AuditInputError as exc:
            assert "split_schema_invalid" in str(exc)
        else:
            raise AssertionError("schema missing field was accepted")
        schema_wrong_type = copy.deepcopy(split_output)
        schema_wrong_type["counts"]["component_count"] = True
        try:
            AUDIT.validate_split_output(schema_wrong_type)
        except AUDIT.AuditInputError as exc:
            assert "split_schema_invalid" in str(exc)
        else:
            raise AssertionError("schema bool-as-integer was accepted")
        schema_nonfinite = copy.deepcopy(split_output)
        schema_nonfinite["config"]["ratios"]["train"] = float("nan")
        try:
            AUDIT.validate_split_output(schema_nonfinite)
        except AUDIT.AuditInputError as exc:
            assert "non_finite_number" in str(exc)
        else:
            raise AssertionError("schema non-finite number was accepted")

        tampered_hash = copy.deepcopy(split_output)
        tampered_hash["assignments"][0]["split"] = "locked_test"
        try:
            AUDIT.validate_split_output(tampered_hash)
        except AUDIT.AuditInputError as exc:
            assert "manifest_sha256" in str(exc)
        else:
            raise AssertionError("assignment tamper with retained manifest hash was accepted")

        tampered_config = copy.deepcopy(split_output)
        tampered_config["config"]["seed"] = 9
        tampered_config["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_config.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_config)
        except AUDIT.AuditInputError as exc:
            assert "config_sha256" in str(exc)
        else:
            raise AssertionError("config hash drift was accepted")

        tampered_input = copy.deepcopy(split_output)
        tampered_input["input"]["records_manifest_sha256"] = "0" * 64
        tampered_input["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_input.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_input)
        except AUDIT.AuditInputError as exc:
            assert "input_sha256" in str(exc)
        else:
            raise AssertionError("input hash drift was accepted")

        tampered_input_count = copy.deepcopy(split_output)
        tampered_input_count["input"]["record_count"] += 1
        tampered_input_count["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_input_count.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_input_count)
        except AUDIT.AuditInputError as exc:
            assert "input_record_count" in str(exc)
        else:
            raise AssertionError("input record-count drift was accepted")

        tampered_duplicate_assignment = copy.deepcopy(split_output)
        tampered_duplicate_assignment["assignments"].append(copy.deepcopy(tampered_duplicate_assignment["assignments"][0]))
        tampered_duplicate_assignment["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_duplicate_assignment.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_duplicate_assignment)
        except AUDIT.AuditInputError as exc:
            assert "duplicate_assignment_id" in str(exc)
        else:
            raise AssertionError("duplicate assignment was accepted")

        tampered_missing_assignment = copy.deepcopy(split_output)
        del tampered_missing_assignment["assignments"][0]
        tampered_missing_assignment["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_missing_assignment.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_missing_assignment)
        except AUDIT.AuditInputError as exc:
            assert "assignment_record_set" in str(exc)
        else:
            raise AssertionError("missing assignment was accepted")

        tampered_per_split = copy.deepcopy(split_output)
        tampered_per_split["counts"]["per_split"]["train"]["record_count"] += 1
        tampered_per_split["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_per_split.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_per_split)
        except AUDIT.AuditInputError as exc:
            assert "per_split:train" in str(exc)
        else:
            raise AssertionError("per-split count drift was accepted")

        tampered_component = copy.deepcopy(split_output)
        tampered_component["components"][0]["record_count"] += 1
        tampered_component["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_component.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_component)
        except AUDIT.AuditInputError as exc:
            assert "component_record_count" in str(exc)
        else:
            raise AssertionError("inconsistent component count was accepted after hash recompute")

        tampered_counts = copy.deepcopy(split_output)
        tampered_counts["counts"]["record_count"] += 1
        tampered_counts["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_counts.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_counts)
        except AUDIT.AuditInputError as exc:
            assert "aggregate_count" in str(exc)
        else:
            raise AssertionError("inconsistent aggregate count was accepted after hash recompute")

        tampered_assignment = copy.deepcopy(split_output)
        organic_components = [component for component in tampered_assignment["components"] if component["bucket"] == "organic"]
        assert len(organic_components) == 2 and organic_components[0]["split"] != organic_components[1]["split"]
        first_split, second_split = organic_components[0]["split"], organic_components[1]["split"]
        organic_components[0]["split"], organic_components[1]["split"] = second_split, first_split
        for assignment in tampered_assignment["assignments"]:
            if assignment["component_id"] == organic_components[0]["component_id"]:
                assignment["split"] = second_split
            elif assignment["component_id"] == organic_components[1]["component_id"]:
                assignment["split"] = first_split
        for split in AUDIT.SPLITS:
            split_components = [component for component in tampered_assignment["components"] if component["split"] == split]
            split_assignments = [assignment for assignment in tampered_assignment["assignments"] if assignment["split"] == split]
            tampered_assignment["counts"]["per_split"][split] = {
                "component_count": len(split_components),
                "record_count": len(split_assignments),
                "buckets": {
                    bucket: {
                        "component_count": sum(component["bucket"] == bucket for component in split_components),
                        "record_count": sum(assignment["bucket"] == bucket for assignment in split_assignments),
                    }
                    for bucket in AUDIT.BUCKETS
                },
            }
        tampered_assignment["counts"]["component_count"] = len(tampered_assignment["components"])
        tampered_assignment["counts"]["record_count"] = len(tampered_assignment["assignments"])
        tampered_assignment["counts"]["family_counts"] = {
            category: len({
                family["hash"]
                for component in tampered_assignment["components"]
                for family in component["protected_family_hashes"]
                if family["category"] == category
            })
            for category in AUDIT.PROTECTED_CATEGORIES
        }
        tampered_assignment["counts"]["dedup_cluster_count"] = sum(
            component["dedup_cluster_count"] for component in tampered_assignment["components"]
        )
        tampered_assignment["counts"]["sequence_count"] = sum(
            component["sequence_count"] for component in tampered_assignment["components"]
        )
        config_body = {
            key: value for key, value in tampered_assignment["config"].items() if key != "config_sha256"
        }
        tampered_assignment["config"]["config_sha256"] = AUDIT._json_digest(config_body)
        input_body = {
            "records_manifest_sha256": tampered_assignment["input"]["records_manifest_sha256"],
            "clusters_receipt_sha256": tampered_assignment["input"]["clusters_receipt_sha256"],
        }
        tampered_assignment["input"]["input_sha256"] = AUDIT._json_digest(input_body)
        tampered_assignment["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_assignment.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_assignment)
        except AUDIT.AuditInputError as exc:
            assert "seeded_assignment" in str(exc)
        else:
            raise AssertionError("seeded component reassignment was accepted after all count/hash recomputes")

        organic_components = [component for component in split_output["components"] if component["bucket"] == "organic"]
        assert len({component["split"] for component in organic_components}) > 1
        source_hashes = {
            component["component_id"]: next(
                family["hash"] for family in component["protected_family_hashes"] if family["category"] == "source_shoot"
            )
            for component in organic_components
        }
        leak_left, leak_right = organic_components[0], organic_components[1]
        tampered_family = copy.deepcopy(split_output)
        target = next(component for component in tampered_family["components"] if component["component_id"] == leak_right["component_id"])
        replacement = source_hashes[leak_left["component_id"]]
        for family in target["protected_family_hashes"]:
            if family["category"] == "source_shoot":
                family["hash"] = replacement
        tampered_family["counts"]["family_counts"]["source_shoot"] -= 1
        tampered_family["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_family.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_family)
        except AUDIT.AuditInputError as exc:
            assert "family_owner" in str(exc)
        else:
            raise AssertionError("cross-split family-hash tamper was accepted after hash recompute")

        tampered_bucket_family = copy.deepcopy(split_output)
        organic_train = next(
            component
            for component in tampered_bucket_family["components"]
            if component["bucket"] == "organic" and component["split"] == "train"
        )
        synthetic_train = next(
            component
            for component in tampered_bucket_family["components"]
            if component["bucket"] == "synthetic" and component["split"] == "train"
        )
        replacement = next(
            family["hash"]
            for family in organic_train["protected_family_hashes"]
            if family["category"] == "source_shoot"
        )
        for family in synthetic_train["protected_family_hashes"]:
            if family["category"] == "source_shoot":
                family["hash"] = replacement
        tampered_bucket_family["counts"]["family_counts"]["source_shoot"] -= 1
        tampered_bucket_family["manifest_sha256"] = AUDIT._json_digest(
            {key: value for key, value in tampered_bucket_family.items() if key != "manifest_sha256"}
        )
        try:
            AUDIT.validate_split_output(tampered_bucket_family)
        except AUDIT.AuditInputError as exc:
            assert "family_owner" in str(exc)
        else:
            raise AssertionError("same-split cross-bucket family-hash tamper was accepted")

        print(
            "M3-008 split seed=1 output_sha256=" + split_output["manifest_sha256"] +
            " seed5_output_sha256=" + seed_five["manifest_sha256"] +
            " cli_sha256=" + cli_sha256 +
            " input_sha256=" + split_output["input"]["input_sha256"] +
            " components=" + str(split_output["counts"]["component_count"]) +
            " per_split=" + json.dumps(split_output["counts"]["per_split"], sort_keys=True, separators=(",", ":"))
        )

    print(
        "PASS M3-007 fixture exact_sha near_crop_color near_blur far_discriminated "
        "sequence_family input_order_independent malformed_rejected rights_required media_map_conflict "
        "schema_round_trip ssim_review_only typed_parameters phash64 decompression_bomb_rejected "
        "M3-008 split_components protected_family_leakage bucket_isolation changed_seed_integrity "
        "split_schema_negative_cases closed_input_topology review_history_contract "
        "seeded_assignment_receipt_tamper family_hash_owner_tamper split_admission_boundary "
        "admission_revalidation jsonl_header_representation header_value_validation"
    )


if __name__ == "__main__":
    run()
