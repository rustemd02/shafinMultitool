#!/usr/bin/env python3
"""Build the reproducible ML-004 Colab training bundle (camera coach).

The bundle pins *code and metadata only*. Raw media, silver derivative images
and human-gold labels are never copied into the bundle: they travel through
Google Drive, and this builder emits ``data_manifest.jsonl`` rows that carry a
Drive placeholder path plus the pinned ``content_sha256`` of every file. The
Colab preflight (``check_environment.py``) re-verifies those hashes on the
runtime before anything trains.

Human-gold status is fail-closed by construction: the human labels directory
slot is emitted as an explicit, empty ``awaiting_owner`` row until the pilot
(DATA-008) and the corpus (DATA-010…016) exist. With an empty slot the bundle
permits ``dry_run``/``smoke`` modes only; ``final_fit`` refuses without
adjudicated ``human_gold=true`` labels (silver is never gold).

The builder is stdlib-only and writes the ``tar.gz`` under ``/tmp`` by
default; nothing is uploaded and no training is started here.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import gzip
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DATA_ROOT = Path("/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS")

BUNDLE_SCHEMA_ID = "camera-coach-ml004-colab-bundle-v1"
BUNDLE_SCHEMA_VERSION = "1.0.0"
CONFIG_SCHEMA_ID = "camera-coach-ml004-production-config-v1"
DATA_MANIFEST_SCHEMA_ID = "camera-coach-ml004-data-manifest-v1"

DEFAULT_DRIVE_ROOT = "/content/drive/MyDrive/SETOS"

V2_PACKAGE_REL = "Datasets/camera-coach/colab_package_v2_20260914"
SILVER_PAIRS_REL = "Datasets/camera-coach/silver-fit-20260918/pairs"
PILOT_ANNOTATION_REL = "annotation/pilot-20260923-strata-v1"

#: Files copied into ``ml/`` and ``tools/`` inside the bundle, hashed at build.
#: Mirrors the reviewed execution-closure pattern of tools/dataset/package_camera_colab.py.
CODE_FILES: tuple[str, ...] = (
    "ml/camera_coach/losses.py",
    "ml/camera_coach/production_heads.py",
    "ml/camera_coach/train_silver_actions.py",
    "ml/camera_coach/evaluate_silver_pairs.py",
    "ml/camera_coach/data/__init__.py",
    "ml/camera_coach/data/preprocessing.py",
    "ml/camera_coach/models/__init__.py",
    "ml/camera_coach/models/set_composition_net.py",
    "ml/camera_coach/models/set_composition_net_v2.py",
    "ml/camera_coach/contracts/camera_production_heads_v1.md",
    "ml/camera_coach/contracts/camera_release_label_v1.schema.json",
    "ml/camera_coach/contracts/camera_release_capability_mapping_v1.json",
    "ml/camera_coach/contracts/set_composition_net_v1.json",
    "ml/camera_coach/contracts/check_production_heads_v1.py",
    "ml/camera_coach/contracts/validate_camera_release_label.py",
    "ml/camera_coach/contracts/fixtures/camera_release_label_v1.valid.json",
    "ml/camera_coach/contracts/fixtures/camera_release_label_v1.invalid.json",
    "tools/dataset/generate_camera_corruptions.py",
)

#: Pinned production training knobs (contract ML-002 layout, ML-003 masked
#: losses). ``resume`` checkpoints stream to Drive every N optimizer steps.
PINNED_CONFIG: dict[str, Any] = {
    "schema_id": CONFIG_SCHEMA_ID,
    "schema_version": "1.0.0",
    "purpose": (
        "pinned knobs for the human-gold production fit (ML-004/ML-005); "
        "the production heads layout is derived at runtime from the pinned "
        "contracts via ml.camera_coach.production_heads.ProductionHeadsSpec.load()"
    ),
    "heads_contract": {
        "document": "ml/camera_coach/contracts/camera_production_heads_v1.md",
        "expected_tensor_head_widths": {
            "good_frame_probability": 1,
            "issue_logits": 15,
            "action_utility_logits": 26,
            "continuous_target_deltas": 5,
            "risk_probability": 1,
            "abstention_probability": 1,
        },
        "calibration_artifact": "non-tensor head; owned by CAM-003/ML-007",
        "temporal": "deferred_to_ML_011",
    },
    "masked_losses": {
        "single_logit_heads": ["good_frame_probability", "risk_probability", "abstention_probability"],
        "loss_by_head": {
            "good_frame_probability": "masked_bce",
            "issue_logits": "masked_bce_with_logits",
            "action_utility_logits": "masked_bce_with_logits",
            "continuous_target_deltas": "masked_huber",
            "risk_probability": "masked_bce",
            "abstention_probability": "masked_bce",
        },
        "mask_semantics": "label presence; missing label = mask 0, never a zero target",
        "loss_weights": {head: 1.0 for head in (
            "good_frame_probability",
            "issue_logits",
            "action_utility_logits",
            "continuous_target_deltas",
            "risk_probability",
            "abstention_probability",
        )},
        "huber_beta": 1.0,
    },
    "seed": 20260923,
    "seeds_variance_check": [20260923, 20260924, 20260925],
    "training": {
        "input_size": [320, 320],
        "epochs": 24,
        "batch_size": 32,
        "learning_rate": 0.0003,
        "weight_decay": 0.0001,
        "early_stopping_patience_epochs": 4,
    },
    "resume": {
        "checkpoint_every_steps": 200,
        "checkpoint_dir": f"{DEFAULT_DRIVE_ROOT}/runs/ml004/checkpoints",
        "keep_last_k": 3,
        "resume_from_latest": True,
    },
    "evaluation": {
        "per_head_metrics": ["auroc", "ece", "brier", "masked_top1_per_family", "delta_mae"],
        "locked_test": "forbidden until ML-008 (single locked evaluation)",
    },
    "environment": {
        "python_min": "3.10",
        "torch_min": "2.4",
        "accelerators_expected": ["A100", "T4"],
        "note": "Colab supplies torch; do not install the macOS requirements.lock in Colab",
    },
}


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _git_head(repo: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True, check=True
        )
        return result.stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def _fail(message: str) -> None:
    raise SystemExit(f"build_bundle: FAIL {message}")


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _fail(f"cannot read JSON {path}: {exc}")


def _deterministic_sample(rows: list[dict[str, Any]], sample: int) -> list[dict[str, Any]]:
    """Deterministic stride sample over rows sorted by content_sha256."""

    if sample <= 0 or len(rows) <= sample:
        return list(rows)
    ordered = sorted(rows, key=lambda row: (row["content_sha256"], row["record_id"]))
    step = len(rows) / float(sample)
    return [ordered[min(len(ordered) - 1, int(i * step))] for i in range(sample)]


def _verify_sample(rows: list[dict[str, Any]], roots: dict[str, Path], label: str) -> dict[str, Any]:
    checked, mismatches, missing = 0, [], []
    for row in rows:
        local = roots[row["source_kind"]] / row["local_relpath"]
        if not local.is_file():
            missing.append(row["record_id"])
            continue
        if _sha256_file(local) != row["content_sha256"]:
            mismatches.append(row["record_id"])
            continue
        checked += 1
    if missing or mismatches:
        _fail(
            f"{label}: sample verification failed: {len(missing)} missing, "
            f"{len(mismatches)} hash mismatches (first: {(*missing, *mismatches)[:3]})"
        )
    return {"checked": checked, "mismatches": 0, "missing": 0}


def build_data_manifest(data_root: Path, sample: int, full_verify: bool) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    verification: dict[str, Any] = {}

    # --- (1) v2 research package frames (research_only silver-raw media) -----
    package_root = data_root / V2_PACKAGE_REL
    manifest_path = package_root / "manifest.jsonl"
    receipt_path = package_root / "package-receipt.json"
    if not manifest_path.is_file() or not receipt_path.is_file():
        _fail(f"v2 package manifest/receipt missing under {package_root}")
    receipt = _read_json(receipt_path)
    manifest_sha = _sha256_file(manifest_path)
    if manifest_sha != receipt.get("manifest_sha256"):
        _fail("v2 package manifest.jsonl sha256 disagrees with package-receipt.json")
    frame_rows: list[dict[str, Any]] = []
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        relpath = record.get("image_relpath")
        if not isinstance(relpath, str) or not relpath:
            _fail(f"v2 manifest row without image_relpath: {record.get('record_id')!r}")
        frame_rows.append(
            {
                "schema_id": DATA_MANIFEST_SCHEMA_ID,
                "record_id": str(record["record_id"]),
                "source_kind": "package_frame",
                "local_relpath": f"{V2_PACKAGE_REL}/{relpath}",
                "drive_path": f"{DEFAULT_DRIVE_ROOT}/camera-coach/colab_package_v2_20260914/{relpath}",
                "content_sha256": str(record["image_sha256"]),
                "pixel_sha256": record.get("pixel_sha256"),
                "source_family": record.get("source_family"),
                "width": record.get("width"),
                "height": record.get("height"),
                "research_only": True,
                "human_gold": False,
                "release_admissible": False,
                "intended_use": "silver_raw_media; labels come from human adjudication only",
            }
        )
    rows.extend(frame_rows)
    sample_rows = frame_rows if full_verify else _deterministic_sample(frame_rows, sample)
    verification["package_frames"] = {
        **_verify_sample(sample_rows, {"package_frame": data_root}, "v2 package frames"),
        "rows_total": len(frame_rows),
        "mode": "full" if full_verify else "deterministic_sample",
        "manifest_sha256_verified": manifest_sha,
    }

    # --- (2) silver pair root (research-only silver supervision) -------------
    pairs_root = data_root / SILVER_PAIRS_REL
    pairs_manifest = pairs_root / "pairs.jsonl"
    pairs_receipt = pairs_root / "receipt.json"
    if not pairs_manifest.is_file() or not pairs_receipt.is_file():
        _fail(f"silver pairs manifest/receipt missing under {pairs_root}")
    silver_receipt = _read_json(pairs_receipt)
    output = silver_receipt.get("output_manifest") or {}
    pairs_sha = _sha256_file(pairs_manifest)
    if output.get("sha256") != pairs_sha:
        _fail("silver pairs.jsonl sha256 disagrees with receipt.output_manifest.sha256")
    rows.append(
        {
            "schema_id": DATA_MANIFEST_SCHEMA_ID,
            "record_id": "silver_pairs_manifest",
            "source_kind": "silver_pairs",
            "local_relpath": f"{SILVER_PAIRS_REL}/pairs.jsonl",
            "drive_path": f"{DEFAULT_DRIVE_ROOT}/camera-coach/silver-fit-20260918/pairs/pairs.jsonl",
            "content_sha256": pairs_sha,
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
            "intended_use": "research-only silver supervision; never quoted as human gold",
        }
    )
    rows.append(
        {
            "schema_id": DATA_MANIFEST_SCHEMA_ID,
            "record_id": "silver_pairs_receipt",
            "source_kind": "silver_pairs",
            "local_relpath": f"{SILVER_PAIRS_REL}/receipt.json",
            "drive_path": f"{DEFAULT_DRIVE_ROOT}/camera-coach/silver-fit-20260918/pairs/receipt.json",
            "content_sha256": _sha256_file(pairs_receipt),
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
            "intended_use": "pins pair counts and per-derivative hashes inside pairs.jsonl",
        }
    )
    derivative_rows: list[dict[str, Any]] = []
    for line in pairs_manifest.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        pair = json.loads(line)
        derivative = pair.get("derivative") or {}
        relpath = derivative.get("relative_path")
        if not isinstance(relpath, str) or not relpath or not derivative.get("sha256"):
            _fail(f"silver pair without derivative hash: {pair.get('pair_id')!r}")
        derivative_rows.append(
            {
                "schema_id": DATA_MANIFEST_SCHEMA_ID,
                "record_id": f"silverimg_{pair['pair_id']}",
                "source_kind": "silver_derivative_image",
                "local_relpath": f"{SILVER_PAIRS_REL}/{relpath}",
                "drive_path": f"{DEFAULT_DRIVE_ROOT}/camera-coach/silver-fit-20260918/pairs/{relpath}",
                "content_sha256": str(derivative["sha256"]),
                "research_only": True,
                "human_gold": False,
                "release_admissible": False,
                "intended_use": "silver corruption derivative; research-only",
            }
        )
    rows.extend(derivative_rows)
    silver_sample = derivative_rows if full_verify else _deterministic_sample(derivative_rows, max(10, sample // 2))
    verification["silver"] = {
        **_verify_sample(
            [*silver_sample, *([r for r in rows if r["source_kind"] == "silver_pairs"])],
            {"silver_derivative_image": data_root, "silver_pairs": data_root},
            "silver pairs",
        ),
        "pairs_total": len(derivative_rows),
        "mode": "full" if full_verify else "deterministic_sample",
        "pairs_jsonl_sha256_verified": pairs_sha,
    }

    # --- (3) human-gold slot: explicitly empty, fail-closed ------------------
    rows.append(
        {
            "schema_id": DATA_MANIFEST_SCHEMA_ID,
            "record_id": "human_labels_dir_slot",
            "source_kind": "human_labels_dir",
            "status": "awaiting_owner",
            "local_relpath": None,
            "drive_path": f"{DEFAULT_DRIVE_ROOT}/annotation/pilot-20260923-strata-v1/labels.jsonl",
            "content_sha256": None,
            "expected": {
                "pilot_100": {
                    "source": f"{DEFAULT_DRIVE_ROOT}/annotation/pilot-20260923-strata-v1/labels.jsonl",
                    "queue_pin": {
                        "queue_file": "queue-v2-diverse.jsonl",
                        "queue_sha256": "dd47f199ba4089d34b94c11ad89f9f65b82b820b2112a77bdbb90de75f0559f8",
                        "items": 100,
                        "strata": "10 groups x 10 (coverage matrix section 4)",
                        "identity_repair": ("identity-repair-20260927/migration-manifest.json "
                                            "(record_id pilot23-composition-07 -> pilot23-composition-11 "
                                            "for the unshown scenetrans frame; human rows untouched)"),
                        "prep_queue_pin_20260923": {
                            "queue_file": "queue.jsonl",
                            "queue_sha256": "cbb55e6376cf4e2d560ba52426347f40d90a57f61419c3401a511ea839c3cbbe",
                            "note": "original strata prep queue; pilot annotation runs on queue-v2-diverse",
                        },
                    },
                    "raw_stores": {
                        "labels": "annotation/pilot-20260923-strata-v1/fast_labels.jsonl",
                        "details": "annotation/pilot-20260923-strata-v1/fast_details.jsonl",
                        "note": ("raw review records (human_gold=false); release-label envelopes "
                                 "come from annotate_fast --export-out after adjudication"),
                    },
                    "format": "camera-release-label-v1 envelopes (envelope_schema_id from release_label_adapter)",
                    "adjudication": "human_gold=true requires DATA-010/011 adjudication, not raw review",
                },
                "future_data_013_episodes": {
                    "source": f"{DEFAULT_DRIVE_ROOT}/annotation/ (owner-confirmed layout, DATA-013/014)",
                    "format": "before/after temporal episodes; pinned by DATA-014 manifests",
                },
            },
            "research_only": False,
            "human_gold": False,
            "release_admissible": False,
            "intended_use": (
                "human-gold supervision slot; empty today, so check_environment.py permits "
                "dry_run/smoke only and refuses final_fit"
            ),
        }
    )
    verification["human_labels_dir"] = {"rows_total": 0, "status": "awaiting_owner"}
    return rows, verification


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True, help="directory for the tar.gz (use /tmp)")
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    parser.add_argument("--sample", type=int, default=50, help="deterministic hash-sample size at build")
    parser.add_argument("--full-verify", action="store_true", help="hash every data file at build (slow)")
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    for rel in CODE_FILES:
        if not (REPO_ROOT / rel).is_file():
            _fail(f"code file missing: {rel}")
    for name in ("check_environment.py", "colab_training_template.ipynb"):
        if not (here / name).is_file():
            _fail(f"bundle source missing: {here / name}")

    build_utc = _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()
    data_rows, verification = build_data_manifest(args.data_root, args.sample, args.full_verify)

    out_dir = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    stage = out_dir / f".stage-camera-coach-ml004-{os.getpid()}"
    root = stage / "camera-coach-ml004-colab-bundle"
    code_root = root / "bundle"
    for rel in CODE_FILES:
        dest = code_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes((REPO_ROOT / rel).read_bytes())
    (root / "config.json").write_text(json.dumps(PINNED_CONFIG, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (root / "data_manifest.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in data_rows), encoding="utf-8"
    )
    (root / "check_environment.py").write_bytes((here / "check_environment.py").read_bytes())
    (root / "colab_training_template.ipynb").write_bytes((here / "colab_training_template.ipynb").read_bytes())

    code_hashes = {rel: _sha256_file(REPO_ROOT / rel) for rel in sorted(CODE_FILES)}
    receipt = {
        "schema_id": BUNDLE_SCHEMA_ID,
        "schema_version": BUNDLE_SCHEMA_VERSION,
        "built_utc": build_utc,
        "git_head": _git_head(REPO_ROOT),
        "git_branch": "store",
        "builder": "ml/camera_coach/colab_bundle/build_bundle.py",
        "data_verification_mode": "full" if args.full_verify else f"deterministic_sample({args.sample})",
        "data_root": str(args.data_root),
        "code_hashes_sha256": code_hashes,
        "config_sha256": _sha256_file(root / "config.json"),
        "data_manifest_sha256": _sha256_file(root / "data_manifest.jsonl"),
        "data_manifest_rows": len(data_rows),
        "data_verification": verification,
        "human_gold_status": "awaiting_owner",
        "permitted_modes_without_human_gold": ["dry_run", "smoke"],
        "forbidden_without_human_gold": ["final_fit"],
        "locked_test_rule": "locked test untouched until ML-008",
        "no_media_in_bundle": True,
    }
    (root / "bundle-receipt.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (root / "README_BUNDLE.md").write_text(
        "# camera-coach-ml004-colab-bundle\n\n"
        "Upload this tar.gz plus the Drive data roots listed in `data_manifest.jsonl`.\n"
        "Run `check_environment.py` first; it is fail-closed. See the repo README in\n"
        "`ml/camera_coach/colab_bundle/README.md` for the owner workflow.\n",
        encoding="utf-8",
    )

    stamp = build_utc.replace("-", "").replace(":", "").replace("+00:00", "Z")
    archive = out_dir / f"camera-coach-ml004-colab-bundle-{stamp}.tar.gz"
    members = sorted(path for path in stage.rglob("*") if path.is_file())
    with io.BytesIO() as buffer:
        with tarfile.open(fileobj=buffer, mode="w") as tar:
            for member in members:
                info = tar.gettarinfo(str(member), arcname=str(member.relative_to(stage)))
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mtime = 0
                info.mode = 0o755 if member.name.endswith(".py") else 0o644
                with member.open("rb") as stream:
                    tar.addfile(info, stream)
        payload = buffer.getvalue()
    with archive.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as gz:
            gz.write(payload)

    import shutil

    shutil.rmtree(stage)
    archive_sha = _sha256_file(archive)
    print(f"BUNDLE {archive}")
    print(f"SHA256 {archive_sha}")
    print(f"ROWS {len(data_rows)} CODE_FILES {len(CODE_FILES)} HUMAN_GOLD {receipt['human_gold_status']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
