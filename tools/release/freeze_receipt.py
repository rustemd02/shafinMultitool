#!/usr/bin/env python3
"""P02 freeze receipt: pin a frozen artifact set so drift stops being silent.

The P02 card in ``docs/aegis/plans/2026-09-13-setos-release-execution.md`` §6
requires a receipt over schema, catalog, policy, preprocessing, label and
protocol hashes, and the rule: *a change after freeze needs a version and an
explicit impact list; do not relabel silently*.

That rule is exactly what this tool separates:

* **silent drift** — file content changed while its recorded version did not
  (or it never carried one). That is a failure (exit 1).
* **versioned change** — content changed *and* ``schema_version`` /
  ``contract_version`` / any recorded version identifier changed. The author
  did the versioned edit on purpose, but still owes an impact list. We return a
  distinct non-zero code (exit 2) rather than 0: a green CI gate must not let a
  frozen-contract edit pass unnoticed, and P02 explicitly ties a post-freeze
  change to a version *and* an impact list. Exit 2 means "review, then record
  the impact list"; exit 1 means "this is silent drift".

Files removed from the set and files newly added to a globbed contract surface
are reported separately and are failures (exit 1).

Usage
    python3 tools/release/freeze_receipt.py --write
    python3 tools/release/freeze_receipt.py --check
    python3 tools/release/freeze_receipt.py --diff --against old-receipt.json

All three accept ``--root`` (repo/tree root), ``--set`` (freeze set JSON) and
``--receipt`` (receipt path); relative paths resolve against ``--root``, which
is what lets the tests run against a temp copy of the tree.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SET = "tools/release/freeze_set.json"
DEFAULT_RECEIPT = (
    "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/freeze-receipt.json"
)

EXIT_OK = 0
EXIT_DRIFT = 1
EXIT_VERSIONED = 2
# Nothing was compared: the freeze set resolved to no artifacts and the receipt
# records none, so "everything matches" would be true of an empty comparison.
# Distinct from EXIT_DRIFT/EXIT_VERSIONED so it cannot be read as either.
EXIT_NOTHING_TO_VERIFY = 3

# Keys probed for a version/identifier in JSON artifacts, most specific first.
# The first one present becomes the artifact's primary ``version_key``.
DEFAULT_VERSION_KEYS = (
    "schema_version",
    "contract_version",
    "catalog_version",
    "dataset_version",
    "policy_version",
    "schema_id",
    "$id",
    "contract_id",
    "preprocessing_version",
    "feature_version",
    "input_contract_version",
    "output_contract_version",
)

TEXT_SUFFIXES = {".json", ".jsonl", ".md", ".txt", ".yaml", ".yml"}


def _resolve(root: Path, value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def extract_versions(path: Path, entry: dict, version_keys) -> dict:
    """Return the version/identifier fields an artifact carries, as strings."""
    versions: dict[str, str] = {}
    if path.suffix.lower() in {".json", ".jsonl"}:
        data = _load_json(path)
        if isinstance(data, dict):
            for key in version_keys:
                value = data.get(key)
                if isinstance(value, (str, int, float)) and str(value).strip():
                    versions[key] = str(value)
    regex = entry.get("version_regex")
    if regex and path.suffix.lower() in TEXT_SUFFIXES:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            text = ""
        match = re.search(regex, text)
        if match:
            key = entry.get("version_regex_key", "version")
            versions[key] = match.group(1) if match.groups() else match.group(0)
    return versions


def _primary_version(versions: dict, version_keys) -> tuple[str | None, str | None]:
    for key in version_keys:
        if key in versions:
            return key, versions[key]
    if versions:
        key = next(iter(versions))
        return key, versions[key]
    return None, None


def build_artifact(root: Path, rel_path: str, entry: dict, version_keys) -> dict:
    path = root / rel_path
    versions = extract_versions(path, entry, version_keys)
    version_key, version_value = _primary_version(versions, version_keys)
    artifact = {
        "path": rel_path,
        "category": entry.get("category", "uncategorized"),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "versions": versions,
        "version_key": version_key,
        "version_value": version_value,
    }
    if entry.get("note"):
        artifact["note"] = entry["note"]
    return artifact


def expand_set(root: Path, set_path: Path) -> dict[str, dict]:
    """Expand the freeze set to concrete relative paths, sorted by path."""
    config = json.loads(set_path.read_text(encoding="utf-8"))
    artifacts: dict[str, dict] = {}
    for entry in config.get("artifacts", []):
        pattern = entry["path"]
        if "*" in pattern or "?" in pattern or "[" in pattern:
            for match in sorted(root.glob(pattern)):
                if match.is_file():
                    artifacts[str(match.relative_to(root))] = entry
        else:
            artifacts[pattern] = entry
    return dict(sorted(artifacts.items()))


def _git_head(root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def build_receipt(root: Path, set_path: Path, receipt_path: Path) -> dict:
    config = json.loads(set_path.read_text(encoding="utf-8"))
    version_keys = tuple(config.get("version_keys") or DEFAULT_VERSION_KEYS)
    artifacts = []
    for rel_path, entry in expand_set(root, set_path).items():
        if not (root / rel_path).is_file():
            raise FileNotFoundError(
                f"freeze set names a missing artifact: {rel_path} "
                f"(fix the set or restore the file; a receipt cannot be built honestly)"
            )
        artifacts.append(build_artifact(root, rel_path, entry, version_keys))
    return {
        "receipt_version": 1,
        "tool": "tools/release/freeze_receipt.py",
        "freeze_set": str(set_path),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_head": _git_head(root),
        "artifact_count": len(artifacts),
        "artifacts": artifacts,
    }


def _version_delta(old: dict, new: dict) -> list[str]:
    keys = sorted(set(old) | set(new))
    return [f"{key} {old.get(key, '<none>')} -> {new.get(key, '<none>')}" for key in keys]


def compare_receipts(root: Path, set_path: Path, receipt: dict) -> dict:
    config = json.loads(set_path.read_text(encoding="utf-8"))
    version_keys = tuple(config.get("version_keys") or DEFAULT_VERSION_KEYS)
    recorded = {item["path"]: item for item in receipt.get("artifacts", [])}
    current_paths = expand_set(root, set_path)

    removed = sorted(path for path in recorded if path not in current_paths)
    added = sorted(path for path in current_paths if path not in recorded)

    drift: list[dict] = []
    versioned: list[dict] = []
    for rel_path in sorted(set(recorded) & set(current_paths)):
        old = recorded[rel_path]
        if not (root / rel_path).is_file():
            removed.append(rel_path)
            continue
        new = build_artifact(root, rel_path, current_paths[rel_path], version_keys)
        if old.get("sha256") == new["sha256"]:
            continue
        old_versions = old.get("versions") or {}
        new_versions = new.get("versions") or {}
        if old_versions and new_versions and old_versions != new_versions:
            versioned.append({
                "path": rel_path,
                "delta": _version_delta(old_versions, new_versions),
                "old_sha256": old.get("sha256"),
                "new_sha256": new["sha256"],
            })
        else:
            drift.append({
                "path": rel_path,
                "old_sha256": old.get("sha256"),
                "new_sha256": new["sha256"],
                "version": old.get("version_value"),
            })
    return {
        "recorded_count": len(recorded),
        "current_count": len(current_paths),
        "silent_drift": drift,
        "versioned_changes": versioned,
        "removed": sorted(removed),
        "added": added,
    }


def _vacuous_check(result: dict) -> int | None:
    """Refuse to report a match over an empty comparison.

    With no artifacts on either side every diff list is empty, so the tool would
    print the same clean PASS as a real, fully matching freeze — while nothing
    was actually protected.
    """
    if not (result.get("recorded_count") or result.get("current_count")):
        print("FAIL CLOSED: nothing to verify")
        print("  the freeze set resolved to 0 artifacts and the receipt records 0;")
        print("  an empty comparison is not a passing comparison (exit 3).")
        return EXIT_NOTHING_TO_VERIFY
    return None


def _report_check(result: dict) -> int:
    vacuous = _vacuous_check(result)
    if vacuous is not None:
        return vacuous
    drift = result["silent_drift"]
    versioned = result["versioned_changes"]
    removed = result["removed"]
    added = result["added"]
    failures = bool(drift or removed or added)

    if not failures and not versioned:
        print("PASS: frozen artifacts match the receipt; no drift, no versioned change")
        return EXIT_OK

    print("FROZEN ARTIFACTS CHANGED since the receipt:")
    print(
        f"  counts: silent_drift={len(drift)} removed={len(removed)} "
        f"added={len(added)} versioned_changes={len(versioned)}"
    )
    if drift:
        print("  silent drift (content changed, version unchanged or absent) -- exit 1:")
        for item in drift:
            print(
                f"    - {item['path']}  sha256 {item['old_sha256'][:12]} -> {item['new_sha256'][:12]}"
                f"  version={item['version']!r}"
            )
    if removed:
        print("  removed (in the receipt, gone from the tree) -- exit 1:")
        for path in removed:
            print(f"    - {path}")
    if added:
        print("  added (matches the freeze set, absent from the receipt) -- exit 1:")
        for path in added:
            print(f"    - {path}")
    if versioned:
        print("  versioned change (content changed and version changed) -- requires impact list:")
        for item in versioned:
            print(f"    - {item['path']}  {'; '.join(item['delta'])}")
            print(f"      sha256 {item['old_sha256'][:12]} -> {item['new_sha256'][:12]}")

    if failures:
        print(
            "\nFAIL: a change after freeze requires a version and an explicit impact list; "
            "silent drift is not allowed. Bump the artifact version and record the impact, "
            "or restore the frozen content."
        )
        return EXIT_DRIFT
    print(
        "\nREVIEW: versioned frozen change only. The edit carries a version, so it is not "
        "silent drift, but P02 still requires an explicit impact list before it is accepted."
    )
    return EXIT_VERSIONED


def _report_diff(result: dict) -> int:
    vacuous = _vacuous_check(result)
    if vacuous is not None:
        return vacuous
    drift = result["silent_drift"]
    versioned = result["versioned_changes"]
    removed = result["removed"]
    added = result["added"]
    if not (drift or versioned or removed or added):
        print("IDENTICAL: the two receipts cover the same artifacts with the same hashes/versions")
        return EXIT_OK
    print("DIFF between receipts (baseline -> receipt under --receipt):")
    for path in added:
        print(f"  added: {path}")
    for path in removed:
        print(f"  removed: {path}")
    for item in drift:
        print(f"  modified: {item['path']}  sha256 {item['old_sha256'][:12]} -> {item['new_sha256'][:12]}")
    for item in versioned:
        print(f"  versioned: {item['path']}  {'; '.join(item['delta'])}")
    return EXIT_DRIFT


def _read_receipt(path: Path) -> dict:
    if not path.is_file():
        raise SystemExit(f"receipt not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="build and write the receipt")
    mode.add_argument("--check", action="store_true", help="compare the tree against the receipt")
    mode.add_argument("--diff", action="store_true", help="compare --receipt against --against")
    parser.add_argument("--against", type=Path, help="baseline receipt for --diff")
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="tree/repo root (default: repo root)")
    parser.add_argument("--set", dest="set_path", default=DEFAULT_SET, help=f"freeze set JSON (default: {DEFAULT_SET})")
    parser.add_argument("--receipt", type=Path, default=DEFAULT_RECEIPT, help="receipt path")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    set_path = _resolve(root, args.set_path)
    receipt_path = _resolve(root, args.receipt)

    if not set_path.is_file():
        raise SystemExit(f"freeze set not found: {set_path}")

    if args.write:
        receipt = build_receipt(root, set_path, receipt_path)
        receipt_path.parent.mkdir(parents=True, exist_ok=True)
        receipt_path.write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"wrote {receipt_path} ({receipt['artifact_count']} artifacts)")
        return EXIT_OK

    if args.diff:
        if not args.against:
            raise SystemExit("--diff requires --against <baseline receipt>")
        baseline = _read_receipt(_resolve(root, args.against))
        current = _read_receipt(receipt_path)
        baseline_map = {item["path"]: item for item in baseline.get("artifacts", [])}
        current_map = {item["path"]: item for item in current.get("artifacts", [])}
        result = {
            "recorded_count": len(baseline_map),
            "current_count": len(current_map),
            "silent_drift": [],
            "versioned_changes": [],
            "removed": sorted(path for path in baseline_map if path not in current_map),
            "added": sorted(path for path in current_map if path not in baseline_map),
        }
        for path in sorted(set(baseline_map) & set(current_map)):
            old, new = baseline_map[path], current_map[path]
            if old.get("sha256") == new.get("sha256"):
                continue
            old_versions = old.get("versions") or {}
            new_versions = new.get("versions") or {}
            if old_versions and new_versions and old_versions != new_versions:
                result["versioned_changes"].append({
                    "path": path, "delta": _version_delta(old_versions, new_versions),
                    "old_sha256": old.get("sha256"), "new_sha256": new.get("sha256"),
                })
            else:
                result["silent_drift"].append({
                    "path": path, "old_sha256": old.get("sha256"),
                    "new_sha256": new.get("sha256"), "version": old.get("version_value"),
                })
        return _report_diff(result)

    return _report_check(compare_receipts(root, set_path, _read_receipt(receipt_path)))


if __name__ == "__main__":
    sys.exit(main())
