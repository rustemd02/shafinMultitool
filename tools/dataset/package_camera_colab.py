#!/usr/bin/env python3
"""Build deterministic one-upload bundles for the Camera Coach Colab lanes.

Only the small, reviewed execution closure is allowed into the bundle.  The
source images, silver manifest, checkpoints, and any generated run products
remain outside Git and are never copied by this tool.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import tempfile
import zipfile
from typing import Any, Mapping


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_ID = "camera-eva-stage1-colab-bundle-v1"
STAGE2_SCHEMA_ID = "camera-coach-stage2-colab-bundle-v1"
RECORDS_SCHEMA_ID = "camera-coach-records-colab-bundle-v1"
RECORDS_SUMS_SCHEMA_ID = "camera-coach-records-sha256-v1"
RECORDS_DATA_SCHEMA_ID = "camera-coach-records-data-bundle-v1"
RECORDS_DATA_SUMS_SCHEMA_ID = "camera-coach-records-data-sha256-v1"
RECORDS_DATA_KIND = "research_only_typed_training_records"
RECORDS_DATA_MEMBER = "records.jsonl"
MAX_MEMBER_BYTES = 2 * 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
MAX_RECORDS_BYTES = 8 * 1024 * 1024 * 1024
BUNDLE_FILES = (
    "datasets/camera-coach/v1/sources/eva-fb40a9f1.json",
    "ml/camera_coach/configs/eva_stage1_colab.json",
    "ml/camera_coach/contracts/set_composition_net_v1.json",
    "ml/camera_coach/colab/SET_OS_EVA_STAGE1.ipynb",
    "ml/camera_coach/models/__init__.py",
    "ml/camera_coach/models/set_composition_net.py",
    "ml/camera_coach/pretrain_eva.py",
    "tools/dataset/build_eva_silver.py",
    "tools/dataset/camera_source_intake.py",
    "tools/dataset/fetch_eva.py",
)
STAGE1_BUNDLE_FILES = BUNDLE_FILES
STAGE2_BUNDLE_FILES = (
    "datasets/camera-coach/v1/silver-action-pair-schema.json",
    "datasets/camera-coach/v1/silver-geometry-schema.json",
    "ml/camera_coach/configs/silver_actions_stage2_colab.json",
    "ml/camera_coach/contracts/set_composition_net_v1.json",
    "ml/camera_coach/colab/SET_OS_Camera_Coach_Stage2.ipynb",
    "ml/camera_coach/data/__init__.py",
    "ml/camera_coach/data/preprocessing.py",
    "ml/camera_coach/losses.py",
    "ml/camera_coach/models/__init__.py",
    "ml/camera_coach/models/set_composition_net.py",
    "tools/dataset/extract_camera_geometry.swift",
    "tools/dataset/generate_camera_corruptions.py",
    "ml/camera_coach/train_silver_actions.py",
)
# The M02 records lane: the same v2 CLI (`python3 -m ml.camera_coach.train
# --config ...`) plus its preflight, the Colab runtime profile config and the
# notebook.  The typed records travel in the separate data bundle, never here.
RECORDS_BUNDLE_FILES = (
    "ml/camera_coach/colab/SET_OS_Camera_Coach_Records.ipynb",
    "ml/camera_coach/colab/README_RECORDS.md",
    "ml/camera_coach/configs/production_records_colab.json",
    "ml/camera_coach/configs/loss_weights.json",
    "ml/camera_coach/configs/loss_weights.schema.json",
    "ml/camera_coach/contracts/set_composition_net_v1.json",
    "ml/camera_coach/contracts/set_composition_net_v2.json",
    "ml/camera_coach/contracts/set_composition_net_v2.schema.json",
    "ml/camera_coach/data/__init__.py",
    "ml/camera_coach/data/intent_features.py",
    "ml/camera_coach/data/preprocessing.py",
    "ml/camera_coach/data/training_records.py",
    "ml/camera_coach/losses.py",
    "ml/camera_coach/models/__init__.py",
    "ml/camera_coach/models/set_composition_net.py",
    "ml/camera_coach/models/set_composition_net_v2.py",
    "ml/camera_coach/preflight_records_run.py",
    "ml/camera_coach/requirements.lock",
    "ml/camera_coach/train.py",
    "ml/camera_coach/trainer_records.py",
)
PROFILE_DEFAULT = "stage1"
PROFILES = {
    "stage1": {
        "schema_id": SCHEMA_ID,
        "sums_schema_id": "camera-eva-stage1-sha256-v1",
        "files": BUNDLE_FILES,
        "disclaimer": "This bundle trains a disposable EVA auxiliary warm-start only; it is not a release model and EVA/AVA image rights remain unresolved.",
    },
    "stage2": {
        "schema_id": STAGE2_SCHEMA_ID,
        "sums_schema_id": "camera-coach-stage2-sha256-v1",
        "files": STAGE2_BUNDLE_FILES,
        "disclaimer": "This bundle fits a disposable CandidateA silver-action state only; it is research/silver, not human-gold, calibrated, release-admissible, or a model-redistribution package.",
    },
    "records": {
        "schema_id": RECORDS_SCHEMA_ID,
        "sums_schema_id": RECORDS_SUMS_SCHEMA_ID,
        "files": RECORDS_BUNDLE_FILES,
        "disclaimer": "This bundle runs the one v2 records trainer CLI in the declared colab_installed_runtime profile only after a fail-closed preflight; it carries no admitted data and makes no quality or release claim.",
    },
}


class BundleError(ValueError):
    """Raised when a bundle cannot be built without widening its allowlist."""


def _canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _sha256(path: Path) -> tuple[int, str]:
    try:
        info = path.lstat()
    except OSError as exc:
        raise BundleError(f"cannot inspect bundle input: {path}") from exc
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise BundleError(f"bundle input is not a regular non-symlink file: {path}")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise BundleError(f"cannot read bundle input: {path}") from exc
    return info.st_size, digest.hexdigest()


def _assert_no_symlink_components(path: Path) -> None:
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise BundleError(f"cannot inspect path component: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise BundleError(f"path uses a symlink: {current}")


def _repo_file(repo_root: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise BundleError(f"allowlist path is unsafe: {relative}")
    candidate = repo_root.joinpath(*path.parts)
    _assert_no_symlink_components(candidate)
    if not candidate.is_file() or candidate.is_symlink():
        raise BundleError(f"required bundle file is missing or unsafe: {relative}")
    return candidate


def _external_output(value: Path, repo_root: Path) -> Path:
    candidate = Path(value).expanduser()
    _assert_no_symlink_components(candidate)
    absolute = Path(os.path.abspath(candidate))
    if absolute == repo_root or repo_root in absolute.parents or absolute in repo_root.parents:
        raise BundleError("bundle output must be outside the repository and its ancestors")
    if absolute.exists():
        if absolute.is_symlink() or not absolute.is_file():
            raise BundleError("bundle output collision is not a regular file")
        raise BundleError(f"bundle output already exists: {absolute}")
    parent = absolute.parent
    if not parent.is_dir():
        raise BundleError(f"bundle output parent does not exist: {parent}")
    return absolute


def _bundle_records(repo_root: Path, files: tuple[str, ...] = BUNDLE_FILES) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    total_bytes = 0
    for relative in files:
        path = _repo_file(repo_root, relative)
        size, digest = _sha256(path)
        if size > MAX_MEMBER_BYTES:
            raise BundleError(f"bundle input exceeds per-member size ceiling: {relative}")
        total_bytes += size
        if total_bytes > MAX_TOTAL_BYTES:
            raise BundleError("bundle inputs exceed total size ceiling")
        records.append({"path": relative, "bytes": size, "sha256": digest})
    return records


def build(repo_root: Path, output: Path, profile: str = PROFILE_DEFAULT) -> tuple[Path, str]:
    repo_root = Path(repo_root).expanduser().resolve(strict=True)
    if not repo_root.is_dir():
        raise BundleError("repo-root is not a directory")
    try:
        selected = PROFILES[profile]
    except KeyError as exc:
        raise BundleError(f"unsupported bundle profile: {profile}") from exc
    files = tuple(selected["files"])
    output = _external_output(output, repo_root)
    records = _bundle_records(repo_root, files)
    manifest = {
        "schema_id": selected["schema_id"],
        "schema_version": "1.0.0",
        "kind": "research_only_colab_orchestration",
        "files": records,
        "disclaimer": selected["disclaimer"],
    }
    sums = {"schema_id": selected["sums_schema_id"], "files": records}
    manifest_bytes = (_canonical_json(manifest) + "\n").encode("utf-8")
    sums_bytes = (_canonical_json(sums) + "\n").encode("utf-8")
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
        os.close(fd)
        temporary = Path(name)
        with zipfile.ZipFile(temporary, mode="w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
            for record in records:
                info = zipfile.ZipInfo(record["path"], date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, (_repo_file(repo_root, record["path"])).read_bytes())
            for name_value, payload in (("bundle-manifest.json", manifest_bytes), ("SHA256SUMS.json", sums_bytes)):
                info = zipfile.ZipInfo(name_value, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, payload)
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(temporary, output)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise BundleError("cannot atomically build Colab bundle") from exc
    return output, hashlib.sha256(output.read_bytes()).hexdigest()


def build_records_data(
    records_path: Path,
    output: Path,
    *,
    admission: str = "non_admitted_research",
    rights_manifest_sha256: str | None = None,
    repo_root: Path = ROOT,
) -> tuple[Path, str, dict[str, Any]]:
    """Package one typed-records JSONL as a deterministic, verified data bundle.

    The data bundle is the only place the typed records travel.  It is distinct
    from the code bundle and carries its own manifest with the record hash,
    byte size, split counts, record schema id/version and the admission/rights
    status, so a preflight can fail closed without trusting the caller.
    """

    import sys

    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from ml.camera_coach.data.training_records import (
        TRAINING_RECORD_SCHEMA_ID,
        TRAINING_RECORD_SCHEMA_VERSION,
        TrainingRecordError,
        load_records,
    )

    if admission not in {"non_admitted_research", "declared_admitted"}:
        raise BundleError(f"unsupported admission status: {admission!r}")
    if admission == "declared_admitted":
        if not isinstance(rights_manifest_sha256, str) or len(rights_manifest_sha256) != 64:
            raise BundleError("declared_admitted data requires a 64-hex rights manifest sha256")
    elif rights_manifest_sha256 is not None:
        raise BundleError("non-admitted research data must not carry a rights manifest sha256")

    repo_root = Path(repo_root).expanduser().resolve(strict=True)
    source = Path(records_path).expanduser()
    if source.is_symlink() or not source.is_file():
        raise BundleError(f"records input must be a regular non-symlink file: {source}")
    source = source.resolve(strict=True)
    size, digest = _sha256(source)
    if size > MAX_RECORDS_BYTES:
        raise BundleError("records input exceeds the data bundle size ceiling")
    try:
        records = load_records(source, digest)
    except TrainingRecordError as exc:
        raise BundleError(f"records input is not a valid typed training bundle: {exc}") from exc
    splits: dict[str, int] = {}
    for record in records:
        splits[record.split] = splits.get(record.split, 0) + 1
    if splits.get("train", 0) == 0 or splits.get("validation", 0) == 0:
        raise BundleError(f"records input needs train and validation splits, got {splits}")
    if splits.get("locked_test", 0) != 0:
        raise BundleError("records input contains sealed locked_test records and cannot be packaged")

    output = _external_output(output, repo_root)
    manifest = {
        "schema_id": RECORDS_DATA_SCHEMA_ID,
        "schema_version": "1.0.0",
        "kind": RECORDS_DATA_KIND,
        "admission": admission,
        "rights_manifest_sha256": rights_manifest_sha256,
        "record_schema_id": TRAINING_RECORD_SCHEMA_ID,
        "record_schema_version": TRAINING_RECORD_SCHEMA_VERSION,
        "record_path": RECORDS_DATA_MEMBER,
        "record_count": len(records),
        "splits": splits,
        "files": [{"path": RECORDS_DATA_MEMBER, "bytes": size, "sha256": digest}],
        "disclaimer": (
            "Research-only typed records. Admission status is a producer claim checked by preflight; "
            "non_admitted_research data can never unlock a full fit."
        ),
    }
    sums = {"schema_id": RECORDS_DATA_SUMS_SCHEMA_ID, "files": manifest["files"]}
    members = [
        (RECORDS_DATA_MEMBER, source.read_bytes()),
        ("data-manifest.json", (_canonical_json(manifest) + "\n").encode("utf-8")),
        ("SHA256SUMS.json", (_canonical_json(sums) + "\n").encode("utf-8")),
    ]
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
        os.close(fd)
        temporary = Path(name)
        with zipfile.ZipFile(temporary, mode="w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
            for member_name, payload in members:
                info = zipfile.ZipInfo(member_name, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, payload)
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(temporary, output)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise BundleError("cannot atomically build records data bundle") from exc
    return output, hashlib.sha256(output.read_bytes()).hexdigest(), manifest


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="camera-colab-bundle-") as temp_dir:
        base = Path(temp_dir).resolve()
        repo = base / "repo"
        external = base / "out"
        repo.mkdir()
        external.mkdir()
        for relative in sorted(set(BUNDLE_FILES) | set(STAGE2_BUNDLE_FILES) | set(RECORDS_BUNDLE_FILES)):
            target = repo.joinpath(*PurePosixPath(relative).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(f"fixture:{relative}\n".encode("utf-8"))
        first, first_sha = build(repo, external / "one.zip")
        second, second_sha = build(repo, external / "two.zip")
        assert first.read_bytes() == second.read_bytes() and first_sha == second_sha
        with zipfile.ZipFile(first) as archive:
            names = archive.namelist()
            assert names == [*BUNDLE_FILES, "bundle-manifest.json", "SHA256SUMS.json"]
            manifest = json.loads(archive.read("bundle-manifest.json"))
            assert manifest["schema_id"] == SCHEMA_ID
            assert [record["path"] for record in manifest["files"]] == list(BUNDLE_FILES)
            for record in manifest["files"]:
                assert hashlib.sha256(archive.read(record["path"])).hexdigest() == record["sha256"]
        stage2, stage2_sha = build(repo, external / "stage2.zip", profile="stage2")
        assert stage2_sha == hashlib.sha256(stage2.read_bytes()).hexdigest()
        with zipfile.ZipFile(stage2) as archive:
            assert archive.namelist() == [*STAGE2_BUNDLE_FILES, "bundle-manifest.json", "SHA256SUMS.json"]
            manifest = json.loads(archive.read("bundle-manifest.json"))
            sums = json.loads(archive.read("SHA256SUMS.json"))
            assert manifest["schema_id"] == STAGE2_SCHEMA_ID
            assert [record["path"] for record in manifest["files"]] == list(STAGE2_BUNDLE_FILES)
            assert sums["schema_id"] == "camera-coach-stage2-sha256-v1"
        records_bundle, records_sha = build(repo, external / "records.zip", profile="records")
        assert records_sha == hashlib.sha256(records_bundle.read_bytes()).hexdigest()
        with zipfile.ZipFile(records_bundle) as archive:
            assert archive.namelist() == [*RECORDS_BUNDLE_FILES, "bundle-manifest.json", "SHA256SUMS.json"]
            manifest = json.loads(archive.read("bundle-manifest.json"))
            assert manifest["schema_id"] == RECORDS_SCHEMA_ID
            assert [record["path"] for record in manifest["files"]] == list(RECORDS_BUNDLE_FILES)
        smoke_records = ROOT / "ml/camera_coach/configs/production_records_smoke.jsonl"
        if smoke_records.is_file():
            data_one, data_sha_one, data_manifest = build_records_data(smoke_records, external / "data-one.zip")
            data_two, data_sha_two, _ = build_records_data(smoke_records, external / "data-two.zip")
            assert data_one.read_bytes() == data_two.read_bytes() and data_sha_one == data_sha_two
            assert data_manifest["record_count"] == 12
            assert data_manifest["splits"] == {"train": 8, "validation": 4}
            assert data_manifest["admission"] == "non_admitted_research"
            with zipfile.ZipFile(data_one) as archive:
                assert archive.namelist() == [RECORDS_DATA_MEMBER, "data-manifest.json", "SHA256SUMS.json"]
                assert json.loads(archive.read("data-manifest.json")) == data_manifest
        try:
            build_records_data(
                smoke_records,
                external / "data-bad-admission.zip",
                admission="non_admitted_research",
                rights_manifest_sha256="0" * 64,
            )
        except BundleError as exc:
            assert "rights manifest" in str(exc)
        else:
            raise AssertionError("non-admitted records with a rights hash were accepted")
        try:
            build(repo, external / "one.zip")
        except BundleError as exc:
            assert "already exists" in str(exc)
        else:
            raise AssertionError("output collision was not rejected")
        symlink_target = repo / BUNDLE_FILES[0]
        real = symlink_target.read_bytes()
        symlink_target.unlink()
        symlink_target.symlink_to(repo / "symlink-target")
        (repo / "symlink-target").write_bytes(real)
        try:
            build(repo, external / "three.zip")
        except BundleError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("symlinked bundle input was accepted")
    print(
        "PASS package_camera_colab self-test deterministic-zip strict-allowlist sha256-manifest "
        "output-collision symlink-guard records-profile records-data-bundle"
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--profile", choices=tuple(PROFILES), default=PROFILE_DEFAULT)
    parser.add_argument("build", nargs="?", choices=("build",))
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pack-records-data", action="store_true")
    parser.add_argument("--records", type=Path, help="typed JSONL for --pack-records-data")
    parser.add_argument(
        "--admission", choices=("non_admitted_research", "declared_admitted"), default="non_admitted_research"
    )
    parser.add_argument("--rights-manifest-sha256", default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.pack_records_data:
            if args.records is None or args.output is None:
                _parser().error("--records and --output are required for --pack-records-data")
            output, digest, manifest = build_records_data(
                args.records,
                args.output,
                admission=args.admission,
                rights_manifest_sha256=args.rights_manifest_sha256,
            )
            print(
                f"PASS package-camera-records-data output={output} sha256={digest} "
                f"records={manifest['record_count']} splits={manifest['splits']} admission={manifest['admission']}"
            )
            return 0
        if args.build != "build" or args.output is None:
            _parser().error("build and --output are required unless --self-test is used")
        output, digest = build(args.repo_root, args.output, profile=args.profile)
        print(f"PASS package-camera-colab profile={args.profile} output={output} sha256={digest} files={len(PROFILES[args.profile]['files'])}")
        return 0
    except BundleError as exc:
        print(f"FAIL {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
