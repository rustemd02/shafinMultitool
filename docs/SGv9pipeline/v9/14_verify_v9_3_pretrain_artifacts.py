from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RUN_ROOT = REPO_ROOT / "docs/SGv9pipeline/runs/v9_3_seed42"
EXPECTED_ZIP_SHA256 = "c57e83c839e3ce84a5963e91a141801ab0506f7c00d3b856e5732699e617b297"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def count_jsonl(path: Path) -> int:
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                json.loads(line)
                count += 1
    return count


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(condition: bool, label: str, failures: list[str]) -> None:
    if not condition:
        failures.append(label)


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify V9.3 pre-training artifacts before Colab upload.")
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--expected-zip-sha256", default=EXPECTED_ZIP_SHA256)
    args = parser.parse_args()

    run_root = args.run_root.resolve()
    failures: list[str] = []
    mixed_dir = run_root / "mixed_event_sft"
    manifest_path = mixed_dir / "v9_3_event_sft_mixed_manifest.json"
    all_path = mixed_dir / "v9_3_event_sft_mixed_all.jsonl"
    train_path = mixed_dir / "v9_3_event_sft_mixed_train.jsonl"
    val_path = mixed_dir / "v9_3_event_sft_mixed_val.jsonl"
    zip_path = run_root / "colab_upload/v9_3_event_sft_mixed_upload.zip"
    zip_manifest_path = run_root / "colab_upload/v9_3_event_sft_mixed_upload_manifest.json"
    audit_path = run_root / "V9_3_GOAL_AUDIT.md"
    runbook_path = run_root / "V9_3_TRAIN_BENCH_RUNBOOK.md"

    for path in [manifest_path, all_path, train_path, val_path, zip_path, zip_manifest_path, audit_path, runbook_path]:
        check(path.exists(), f"missing:{path}", failures)

    manifest: dict[str, Any] = {}
    if manifest_path.exists():
        manifest = read_json(manifest_path)
        expected_counts = {
            all_path: int(manifest.get("all_rows", -1)),
            train_path: int(manifest.get("train_rows", -1)),
            val_path: int(manifest.get("val_rows", -1)),
        }
        for path, expected in expected_counts.items():
            if path.exists():
                actual = count_jsonl(path)
                check(actual == expected, f"row_count_mismatch:{path.name}:actual={actual}:expected={expected}", failures)
        targeted_counts = manifest.get("targeted_row_counts", {})
        check(int(targeted_counts.get("v9_3_total", 0) or 0) >= 278, "v9_3_targeted_rows_below_278", failures)
        check(int(manifest.get("all_rows", 0) or 0) >= 5564, "mixed_all_rows_below_5564", failures)

    zip_sha = None
    zip_entries: list[str] = []
    if zip_path.exists():
        zip_sha = sha256(zip_path)
        check(zip_sha == args.expected_zip_sha256, f"zip_sha_mismatch:actual={zip_sha}", failures)
        with zipfile.ZipFile(zip_path) as archive:
            zip_entries = sorted(info.filename for info in archive.infolist() if not info.is_dir())
        for required_entry in [
            "mixed_event_sft/v9_3_event_sft_mixed_manifest.json",
            "mixed_event_sft/v9_3_event_sft_mixed_all.jsonl",
            "mixed_event_sft/v9_3_event_sft_mixed_train.jsonl",
            "mixed_event_sft/v9_3_event_sft_mixed_val.jsonl",
        ]:
            check(required_entry in zip_entries, f"zip_missing_entry:{required_entry}", failures)

    if zip_manifest_path.exists() and zip_sha:
        zip_manifest = read_json(zip_manifest_path)
        check(zip_manifest.get("sha256") == zip_sha, "zip_manifest_sha_mismatch", failures)
        check(int(zip_manifest.get("entry_count", 0) or 0) == len(zip_entries), "zip_manifest_entry_count_mismatch", failures)

    summary = {
        "run_root": str(run_root),
        "pass": not failures,
        "failures": failures,
        "manifest": {
            "all_rows": manifest.get("all_rows"),
            "train_rows": manifest.get("train_rows"),
            "val_rows": manifest.get("val_rows"),
            "targeted_row_counts": manifest.get("targeted_row_counts"),
        },
        "zip": {
            "path": str(zip_path),
            "sha256": zip_sha,
            "entry_count": len(zip_entries),
        },
    }
    output_path = run_root / "v9_3_pretrain_artifact_verification.json"
    output_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
