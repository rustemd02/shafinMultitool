#!/usr/bin/env python3
"""Build an unsigned device Release archive with exact input and output receipts.

This is an engineering build, not distribution signing or release admission.
The existing bundle validator remains authoritative. Every invocation owns a
fresh output directory and retains failed builds. No Git state is changed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone


REPO_ROOT = Path(__file__).resolve().parents[2]
INPUT_PATHS = (
    "shafinMultitool", "shafinMultitool.xcodeproj", "shafinMultitool.xcworkspace",
    "Frameworks", "Pods", "Podfile", "Podfile.lock", "scripts", "tools/release",
    "docs/implementation/provenance", "third-party-notices",
    "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m0",
)


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def git(root: Path, *arguments: str) -> bytes:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def file_identity(path: Path, root: Path) -> dict:
    if path.is_symlink():
        target = path.resolve(strict=True)
        if not target.is_relative_to(root.resolve()) or not target.is_file():
            raise ValueError(f"input symlink escapes the source tree: {path}")
        return {"symlink": os.readlink(path), "sha256": digest(target),
                "bytes": target.stat().st_size}
    if not path.exists():
        return {"deleted": True}
    if not path.is_file():
        raise ValueError(f"input is not a regular file: {path}")
    return {"sha256": digest(path), "bytes": path.stat().st_size,
            "executable": bool(path.stat().st_mode & 0o111)}


def source_identity(root: Path) -> tuple[dict, bytes, list[str]]:
    names = git(root, "ls-files", "--cached", "--others", "--exclude-standard",
                "-z", "--", *INPUT_PATHS).decode().split("\0")
    paths = sorted({name for name in names if name})
    if not paths:
        raise ValueError("no application build inputs were found")
    patch = git(root, "diff", "--binary", "HEAD", "--", *INPUT_PATHS)
    untracked = [p for p in git(root, "ls-files", "--others", "--exclude-standard",
                                "-z", "--", *INPUT_PATHS).decode().split("\0") if p]
    identity = {
        "baseline_commit": git(root, "rev-parse", "HEAD").decode().strip(),
        "tracked_delta_sha256": hashlib.sha256(patch).hexdigest(),
        "untracked_paths": sorted(untracked),
        "files": {name: file_identity(root / name, root) for name in paths},
        "input_scope": list(INPUT_PATHS),
        "excluded_scope": "Git-ignored research media, datasets and caches are not build inputs; the existing Release bundle validator rejects unexpected shipped payloads.",
    }
    identity["fingerprint"] = hashlib.sha256(
        json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    return identity, patch, untracked


def inspect_archive(archive: Path) -> dict:
    info_path = archive / "Info.plist"
    if not info_path.is_file():
        raise ValueError("xcodebuild produced no archive Info.plist")
    info = plistlib.loads(info_path.read_bytes())
    application_path = info.get("ApplicationProperties", {}).get("ApplicationPath")
    if application_path != "Applications/shafinMultitool.app":
        raise ValueError("archive does not identify the expected application")
    app = archive / "Products" / application_path
    if not app.is_dir() or app.is_symlink():
        raise ValueError("archive application is absent or a symlink")
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = app_info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise ValueError("invalid archived executable name")
    binary = app / executable
    if not binary.is_file() or binary.stat().st_size == 0 or not os.access(binary, os.X_OK):
        raise ValueError("archive executable is missing, empty or not executable")
    if app_info.get("CFBundleIdentifier") != "com.vigvamcev-media.shafinMultitool":
        raise ValueError("archive bundle identifier does not match this application")
    if app_info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("archive is not an iPhoneOS device product")
    files = {str(p.relative_to(app)): file_identity(p, app)
             for p in sorted(app.rglob("*")) if p.is_file() or p.is_symlink()}
    if not files:
        raise ValueError("archive application has no files")
    return {
        "app": str(app), "archive_info_sha256": digest(info_path),
        "app_info_sha256": digest(app / "Info.plist"),
        "bundle_id": app_info["CFBundleIdentifier"],
        "version": app_info.get("CFBundleShortVersionString"),
        "build": app_info.get("CFBundleVersion"),
        "minimum_os": app_info.get("MinimumOSVersion"),
        "device_families": app_info.get("UIDeviceFamily"),
        "scene_backend_url": app_info.get("SETOSSceneBaseURL", ""),
        "source_entitlements_require_signing": True,
        "total_app_bytes": sum(row.get("bytes", 0) for row in files.values()),
        "files": files,
    }


def classify_result(build_exit: int, source_unchanged: bool, artifact: dict | None,
                    validation_exit: int | None) -> str:
    if build_exit != 0 or not source_unchanged or artifact is None:
        return "engineering_build_failed"
    if validation_exit != 0:
        return "engineering_archive_built_release_validation_failed"
    return "unsigned_archive_validated_distribution_and_acceptance_pending"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--output-parent", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path)
    args = parser.parse_args()
    root, parent = args.repo_root.resolve(), args.output_parent.resolve()
    if not parent.is_dir() or parent.is_relative_to(root) or parent == Path("/"):
        parser.error("output-parent must be an existing dedicated directory outside the repository")
    if shutil.disk_usage(parent).free < 8 * 1024**3:
        parser.error("at least 8 GiB of free space is required before archiving")
    run = parent / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-release-archive")
    run.mkdir(mode=0o700)
    receipt = {"schema": "setos-unsigned-archive-v1", "run": str(run),
               "started_at": datetime.now(timezone.utc).isoformat(),
               "release_ready": False, "distribution_signed": False}
    write_json(run / "invocation.json", receipt)
    print(json.dumps({"run": str(run), "state": "started"}), flush=True)
    build_exit, artifact, validation_exit = -1, None, None
    unchanged = False
    try:
        before, patch, untracked = source_identity(root)
        write_json(run / "source-before.json", before)
        (run / "source.patch").write_bytes(patch)
        with tarfile.open(run / "untracked-inputs.tar.gz", "w:gz", dereference=False) as archive:
            for name in untracked:
                archive.add(root / name, arcname=name, recursive=False)
        derived = args.derived_data.resolve() if args.derived_data else run / "DerivedData"
        if derived.is_relative_to(root) or derived == parent or derived == Path("/"):
            raise ValueError("derived-data must be a dedicated directory outside the repository")
        command = ["xcodebuild", "archive", "-workspace", "shafinMultitool.xcworkspace",
                   "-scheme", "shafinMultitool", "-configuration", "Release",
                   "-destination", "generic/platform=iOS", "-jobs", "4",
                   "-derivedDataPath", str(derived), "-archivePath", str(run / "SETOS.xcarchive"),
                   "-resultBundlePath", str(run / "archive.xcresult"),
                   "CODE_SIGNING_ALLOWED=NO", "COMPILER_INDEX_STORE_ENABLE=NO"]
        receipt.update(command=command, source_fingerprint=before["fingerprint"],
                       baseline_commit=before["baseline_commit"])
        write_json(run / "invocation.json", receipt)
        with (run / "toolchain.txt").open("wb") as log:
            subprocess.run(["xcodebuild", "-version"], check=True, stdout=log, stderr=subprocess.STDOUT)
            subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], check=True,
                           stdout=log, stderr=subprocess.STDOUT)
        with (run / "xcodebuild.log").open("wb") as log:
            build_exit = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT).returncode
        after, _, _ = source_identity(root)
        write_json(run / "source-after.json", after)
        unchanged = before == after
        if build_exit == 0:
            artifact = inspect_archive(run / "SETOS.xcarchive")
            write_json(run / "archive-files.json", artifact)
            validation = ["/bin/bash", str(root / "scripts/validate_release_bundle.sh"),
                          "--repo-root", str(root), "--source-manifest",
                          str(root / "shafinMultitool/PrivacyInfo.xcprivacy"), "--app", artifact["app"]]
            receipt["validation_command"] = validation
            with (run / "bundle-validation.log").open("wb") as log:
                validation_exit = subprocess.run(validation, cwd=root, stdout=log, stderr=subprocess.STDOUT).returncode
            architecture = subprocess.run(["xcrun", "lipo", "-archs", str(Path(artifact["app"]) / "shafinMultitool")],
                                          capture_output=True, text=True)
            (run / "binary-architecture.txt").write_text(architecture.stdout + architecture.stderr)
            receipt["architecture_inspection_exit"] = architecture.returncode
            if architecture.returncode != 0 or architecture.stdout.strip().split() != ["arm64"]:
                raise ValueError("archived executable is not the expected arm64 device binary")
        final_source, _, _ = source_identity(root)
        write_json(run / "source-after-verification.json", final_source)
        unchanged = unchanged and before == final_source
        receipt["status"] = classify_result(build_exit, unchanged, artifact, validation_exit)
    except Exception as error:
        receipt.update(status="engineering_build_failed", error=f"{type(error).__name__}: {error}")
    finally:
        receipt.update(build_exit=build_exit, source_unchanged=unchanged,
                       validation_exit=validation_exit, artifact_present=artifact is not None,
                       finished_at=datetime.now(timezone.utc).isoformat())
        receipt["evidence_sha256"] = {p.name: digest(p) for p in sorted(run.iterdir())
                                     if p.is_file() and p.name != "receipt.json"}
        write_json(run / "receipt.json", receipt)
    print(json.dumps({key: receipt.get(key) for key in
                      ("run", "status", "build_exit", "source_unchanged", "validation_exit", "error")}), flush=True)
    return 0 if receipt["status"] == "unsigned_archive_validated_distribution_and_acceptance_pending" else 2


if __name__ == "__main__":
    raise SystemExit(main())
