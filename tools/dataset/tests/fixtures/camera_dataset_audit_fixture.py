#!/usr/bin/env python3
"""Synthetic, temp-only M3-007 fixture (no media is committed)."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
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
        {"asset_id": "asset-base", "path": paths["asset-base"], "record_id": "cam-base", "derivation_family_id": "family-base"},
        {"asset_id": "asset-exact", "path": paths["asset-exact"], "record_id": "cam-exact", "derivation_family_id": "family-exact"},
        {"asset_id": "asset-crop", "path": paths["asset-crop"], "record_id": "cam-crop", "derivation_family_id": "family-crop"},
        {"asset_id": "asset-color", "path": paths["asset-color"], "record_id": "cam-color", "derivation_family_id": "family-color"},
        {"asset_id": "asset-near", "path": paths["asset-near"], "record_id": "cam-near", "derivation_family_id": "family-near"},
        {"asset_id": "asset-far", "path": paths["asset-far"], "record_id": "cam-far", "derivation_family_id": "family-far"},
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
                "derivation_family_id": "family-sequence",
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
        assert sequence["derivation_family_id"] == "family-sequence"
        assert output["ssim_review"]["enabled"] is True
        assert output["ssim_review"]["admission_oracle"] is False
        assert output["ssim_review"]["pairs"]

        bad_manifest = root / "bad.json"
        bad_manifest.write_text(json.dumps({"schema_id": AUDIT.INPUT_SCHEMA_ID, "entries": [{"asset_id": "asset-missing", "path": "missing.png"}]}), encoding="utf-8")
        try:
            AUDIT.load_manifest(bad_manifest, media_root=root)
        except AUDIT.AuditInputError as exc:
            assert "missing_media" in str(exc)
        else:
            raise AssertionError("missing media was accepted")

        unreadable = root / "unreadable.bin"
        unreadable.write_bytes(b"not an image")
        unreadable_manifest = root / "unreadable.json"
        unreadable_manifest.write_text(json.dumps({"entries": [{"asset_id": "asset-bad", "path": unreadable.name}]}), encoding="utf-8")
        try:
            AUDIT.cluster_media(AUDIT.load_manifest(unreadable_manifest, media_root=root))
        except AUDIT.AuditInputError as exc:
            assert "unreadable_media" in str(exc)
        else:
            raise AssertionError("unreadable media was accepted")

    print(
        "PASS M3-007 fixture exact_sha near_crop_color near_blur far_discriminated "
        "sequence_family input_order_independent malformed_rejected schema_round_trip ssim_review_only"
    )


if __name__ == "__main__":
    run()
