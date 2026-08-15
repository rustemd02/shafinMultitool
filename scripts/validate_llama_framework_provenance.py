#!/usr/bin/env python3
"""Validate the vendored llama.cpp XCFramework provenance record.

The default mode is deliberately offline: it checks the tracked framework
against the checked-in manifest and verifies the verbatim upstream MIT notice
artifact.  ``--upstream-checkout`` is an explicit, read-only second mode that
also checks the checkout's origin/HEAD, narrow build-relevant cleanliness,
recipe/build metadata, and the existing build output byte for byte against the
vendored framework.  It does not rebuild the framework.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
from typing import Any


EXPECTED_UPSTREAM_URL = "https://github.com/ggerganov/llama.cpp.git"
EXPECTED_UPSTREAM_COMMIT = "8f974d2392da4e6fa422a67050e90f1471d72966"
EXPECTED_SHORT_COMMIT = EXPECTED_UPSTREAM_COMMIT[:7]
EXPECTED_LICENSE_SHA256 = "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d"
EXPECTED_BUILD_SCRIPT_SHA256 = "fba0661d8efc621b1116c0d3365e43fd536833af61417424aa363dd3cccf8673"
EXPECTED_BUILD_INFO_SHA256 = "2db48f66ed50cc61c52f5925aba2180d169bad5a5841731ded94d4971830da68"
EXPECTED_VENDORED_PATH = "Frameworks/llama.xcframework"
DEFAULT_RECORD_PATH = "docs/implementation/provenance/llama-framework.json"
EXPECTED_TECHNICAL_STATUS = "traceability_complete_rebuild_unproven"
EXPECTED_BUILD_OBSERVATION_STATUS = "existing_build_output_match"

EXPECTED_HISTORICAL_TOOLS = {
    "cmake_version": "4.2.3",
    "xcode_version": "26.0",
    "xcode_build": "17A324",
    "compiler": "AppleClang 17.0.0.17000319",
    "device_sdk": "iPhoneOS26.0",
    "simulator_sdk": "iPhoneSimulator26.0",
}

EXPECTED_CURRENT_HOST_TOOLS = {
    "xcode_version": "26.6",
    "xcode_build": "17F113",
    "compiler": "AppleClang 21.0.0 (clang-2100.1.1.101)",
    "device_sdk": "iPhoneOS26.5",
    "simulator_sdk": "iPhoneSimulator26.5",
}

BUILD_RELEVANT_ROOT_FILES = {
    ".gitmodules",
    "CMakeLists.txt",
    "CMakePresets.json",
    "Makefile",
    "build-ios-only.sh",
    "build-xcframework.sh",
}
BUILD_RELEVANT_PREFIXES = (
    "cmake/",
    "common/",
    "examples/",
    "ggml/",
    "include/",
    "scripts/",
    "src/",
    "tools/",
    "vendor/",
)
GENERATED_BUILD_PREFIXES = (
    "build-apple/",
    "build-ios-device/",
    "build-ios-sim/",
)
UNRELATED_DIRTY_BASENAMES = {"AGENTS.md", "CLAUDE.md"}
BUILD_RELEVANT_EXTENSIONS = {
    ".c",
    ".cc",
    ".cpp",
    ".cxx",
    ".h",
    ".hh",
    ".hpp",
    ".m",
    ".mm",
    ".metal",
    ".cmake",
    ".sh",
}

EXPECTED_BUILD_OPTIONS = {
    "BUILD_SHARED_LIBS": False,
    "LLAMA_BUILD_EXAMPLES": False,
    "LLAMA_BUILD_TOOLS": False,
    "LLAMA_BUILD_TESTS": False,
    "LLAMA_BUILD_SERVER": False,
    "GGML_METAL": True,
    "GGML_METAL_EMBED_LIBRARY": True,
    "GGML_BLAS_DEFAULT": True,
    "GGML_METAL_USE_BF16": True,
    "GGML_NATIVE": False,
    "GGML_OPENMP": False,
    "LLAMA_OPENSSL": False,
}


class ProvenanceError(ValueError):
    """A deterministic validation failure."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProvenanceError(f"required metadata {field} must be an object")
    return value


def _require_string(mapping: dict[str, Any], key: str, field: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise ProvenanceError(f"required metadata {field}.{key} is missing or empty")
    return value


def _require_hash(mapping: dict[str, Any], key: str, field: str) -> str:
    value = _require_string(mapping, key, field)
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise ProvenanceError(f"metadata {field}.{key} must be a lowercase SHA-256 hex digest")
    return value


def _validate_relative_path(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise ProvenanceError(f"metadata {field} must be a non-empty POSIX relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != value:
        raise ProvenanceError(f"metadata {field} must be a normalized POSIX relative path")
    return value


def _load_record(record_path: Path) -> dict[str, Any]:
    try:
        raw = record_path.read_text(encoding="utf-8")
    except OSError as error:
        raise ProvenanceError(f"cannot read provenance record: {record_path}: {error}") from error
    try:
        record = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ProvenanceError(f"provenance record is malformed JSON: {record_path}: {error.msg}") from error
    if not isinstance(record, dict):
        raise ProvenanceError("provenance record root must be an object")
    return record


def _validate_build_metadata(record: dict[str, Any]) -> None:
    build = _require_mapping(record.get("build"), "build")
    expected_strings = {
        "source_checkout": "llama.cpp",
        "source_script": "build-ios-only.sh",
        "command": "./build-ios-only.sh",
        "output": "build-apple/llama.xcframework",
        "configuration": "Release",
        "generator": "Xcode",
        "platform": "iOS",
        "minimum_os_version": "16.4",
    }
    for key, expected in expected_strings.items():
        actual = _require_string(build, key, "build")
        if actual != expected:
            raise ProvenanceError(f"metadata build.{key} must be {expected!r}, got {actual!r}")
    _validate_relative_path(build["source_checkout"], "build.source_checkout")
    _validate_relative_path(build["source_script"], "build.source_script")
    _validate_relative_path(build["output"], "build.output")
    if _require_hash(build, "source_script_sha256", "build") != EXPECTED_BUILD_SCRIPT_SHA256:
        raise ProvenanceError("metadata build.source_script_sha256 does not match the verified build recipe")
    preserved_recipe_path = _validate_relative_path(
        build.get("preserved_recipe_path"), "build.preserved_recipe_path"
    )
    if preserved_recipe_path != "docs/implementation/provenance/llama/build-ios-only.sh":
        raise ProvenanceError("metadata build.preserved_recipe_path is not the tracked llama recipe")
    if _require_hash(build, "preserved_recipe_sha256", "build") != EXPECTED_BUILD_SCRIPT_SHA256:
        raise ProvenanceError("metadata build.preserved_recipe_sha256 does not match the tracked llama recipe")

    architectures = _require_mapping(build.get("architectures"), "build.architectures")
    expected_architectures = {
        "ios-arm64": ["arm64"],
        "ios-arm64_x86_64-simulator": ["arm64", "x86_64"],
    }
    if architectures != expected_architectures:
        raise ProvenanceError("metadata build.architectures does not match the verified iOS slices")

    options = _require_mapping(build.get("cmake_options"), "build.cmake_options")
    if options != EXPECTED_BUILD_OPTIONS:
        raise ProvenanceError("metadata build.cmake_options does not match the verified build recipe")

    build_metadata = _require_mapping(record.get("build_metadata"), "build_metadata")
    expected_slice_metadata = {
        "device": {
            "build_info_path": "build-ios-device/common/build-info.cpp",
            "sysroot": "iphoneos",
            "architectures": ["arm64"],
        },
        "simulator": {
            "build_info_path": "build-ios-sim/common/build-info.cpp",
            "sysroot": "iphonesimulator",
            "architectures": ["arm64", "x86_64"],
        },
    }
    for slice_name, expected in expected_slice_metadata.items():
        metadata = _require_mapping(build_metadata.get(slice_name), f"build_metadata.{slice_name}")
        build_info_path = _require_string(metadata, "build_info_path", f"build_metadata.{slice_name}")
        if build_info_path != expected["build_info_path"]:
            raise ProvenanceError(
                f"metadata build_metadata.{slice_name}.build_info_path does not match the verified build output"
            )
        _validate_relative_path(build_info_path, f"build_metadata.{slice_name}.build_info_path")
        if _require_hash(metadata, "build_info_sha256", f"build_metadata.{slice_name}") != EXPECTED_BUILD_INFO_SHA256:
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.build_info_sha256 is not verified")
        if _require_string(metadata, "llama_commit", f"build_metadata.{slice_name}") != EXPECTED_SHORT_COMMIT:
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.llama_commit is not verified")
        if _require_string(metadata, "compiler", f"build_metadata.{slice_name}") != "AppleClang 17.0.0.17000319":
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.compiler is not verified")
        if _require_string(metadata, "build_target", f"build_metadata.{slice_name}") != "iOS ":
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.build_target is not verified")
        if _require_string(metadata, "cmake_generator", f"build_metadata.{slice_name}") != "Xcode":
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.cmake_generator is not verified")
        if _require_string(metadata, "system_name", f"build_metadata.{slice_name}") != "iOS":
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.system_name is not verified")
        if _require_string(metadata, "sysroot", f"build_metadata.{slice_name}") != expected["sysroot"]:
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.sysroot is not verified")
        if metadata.get("architectures") != expected["architectures"]:
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.architectures is not verified")
        if _require_string(metadata, "deployment_target", f"build_metadata.{slice_name}") != "16.4":
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.deployment_target is not verified")
        if _require_string(metadata, "configuration", f"build_metadata.{slice_name}") != "Release":
            raise ProvenanceError(f"metadata build_metadata.{slice_name}.configuration is not verified")

    tool_metadata = _require_mapping(record.get("tool_metadata"), "tool_metadata")
    if _require_string(tool_metadata, "cmake_generator", "tool_metadata") != "Xcode":
        raise ProvenanceError("metadata tool_metadata.cmake_generator is not verified")
    if _require_string(tool_metadata, "apple_clang", "tool_metadata") != "AppleClang 17.0.0.17000319":
        raise ProvenanceError("metadata tool_metadata.apple_clang is not verified")
    if _require_string(tool_metadata, "cmake_executable", "tool_metadata") != "/opt/homebrew/bin/cmake":
        raise ProvenanceError("metadata tool_metadata.cmake_executable is not verified")
    historical = _require_mapping(tool_metadata.get("historical"), "tool_metadata.historical")
    for key, expected in EXPECTED_HISTORICAL_TOOLS.items():
        if _require_string(historical, key, "tool_metadata.historical") != expected:
            raise ProvenanceError(f"metadata tool_metadata.historical.{key} is not verified")
    current_host = _require_mapping(tool_metadata.get("current_host"), "tool_metadata.current_host")
    for key, expected in EXPECTED_CURRENT_HOST_TOOLS.items():
        if _require_string(current_host, key, "tool_metadata.current_host") != expected:
            raise ProvenanceError(f"metadata tool_metadata.current_host.{key} is not verified")


def _validate_manifest(record: dict[str, Any]) -> dict[str, str]:
    manifest = _require_mapping(record.get("manifest"), "manifest")
    if _require_string(manifest, "algorithm", "manifest") != "sha256":
        raise ProvenanceError("metadata manifest.algorithm must be sha256")
    if _require_string(manifest, "path_format", "manifest") != "posix-relative":
        raise ProvenanceError("metadata manifest.path_format must be posix-relative")
    if _require_string(manifest, "root", "manifest") != EXPECTED_VENDORED_PATH:
        raise ProvenanceError(f"metadata manifest.root must be {EXPECTED_VENDORED_PATH!r}")
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise ProvenanceError("required metadata manifest.files is missing or empty")
    if manifest.get("file_count") != len(entries):
        raise ProvenanceError("metadata manifest.file_count does not match manifest.files")

    result: dict[str, str] = {}
    paths: list[str] = []
    for index, entry_value in enumerate(entries):
        entry = _require_mapping(entry_value, f"manifest.files[{index}]")
        path = _validate_relative_path(entry.get("path"), f"manifest.files[{index}].path")
        file_hash = _require_hash(entry, "sha256", f"manifest.files[{index}]")
        paths.append(path)
        if path in result:
            raise ProvenanceError(f"manifest.files contains duplicate path: {path}")
        result[path] = file_hash
    if paths != sorted(paths):
        raise ProvenanceError("manifest.files must be sorted by relative POSIX path")
    return result


def _validate_build_observation(record: dict[str, Any]) -> None:
    observation = _require_mapping(record.get("build_observation"), "build_observation")
    if _require_string(observation, "status", "build_observation") != EXPECTED_BUILD_OBSERVATION_STATUS:
        raise ProvenanceError(
            "metadata build_observation.status must be existing_build_output_match"
        )
    if _require_string(observation, "rebuild_status", "build_observation") != "not_proven":
        raise ProvenanceError("metadata build_observation.rebuild_status must be not_proven")
    if observation.get("current_host_mismatch") is not True:
        raise ProvenanceError("metadata build_observation.current_host_mismatch must be true")
    _require_string(observation, "rebuild_reason", "build_observation")


def _validate_record(record: dict[str, Any]) -> dict[str, Any]:
    if record.get("schema_version") != 1:
        raise ProvenanceError("required metadata schema_version must be 1")
    if record.get("component") != "llama.xcframework":
        raise ProvenanceError("required metadata component must be llama.xcframework")
    if record.get("vendored_path") != EXPECTED_VENDORED_PATH:
        raise ProvenanceError(f"required metadata vendored_path must be {EXPECTED_VENDORED_PATH!r}")

    technical = _require_mapping(record.get("technical_provenance"), "technical_provenance")
    if _require_string(technical, "status", "technical_provenance") != EXPECTED_TECHNICAL_STATUS:
        raise ProvenanceError(
            "metadata technical_provenance.status must be traceability_complete_rebuild_unproven"
        )

    upstream = _require_mapping(record.get("upstream"), "upstream")
    if _require_string(upstream, "url", "upstream") != EXPECTED_UPSTREAM_URL:
        raise ProvenanceError("metadata upstream.url is not the verified llama.cpp repository")
    if _require_string(upstream, "commit", "upstream") != EXPECTED_UPSTREAM_COMMIT:
        raise ProvenanceError("metadata upstream.commit is not the verified llama.cpp commit")
    if _require_string(upstream, "remote", "upstream") != "origin":
        raise ProvenanceError("metadata upstream.remote must be origin")

    _validate_build_metadata(record)
    _validate_build_observation(record)

    license_metadata = _require_mapping(record.get("license"), "license")
    if _require_string(license_metadata, "spdx_id", "license") != "MIT":
        raise ProvenanceError("metadata license.spdx_id must be MIT")
    if _require_string(license_metadata, "upstream_path", "license") != "LICENSE":
        raise ProvenanceError("metadata license.upstream_path must be LICENSE")
    if _require_hash(license_metadata, "upstream_sha256", "license") != EXPECTED_LICENSE_SHA256:
        raise ProvenanceError("metadata license.upstream_sha256 is not the verified upstream LICENSE")
    notice_path = _validate_relative_path(license_metadata.get("notice_path"), "license.notice_path")
    if _require_hash(license_metadata, "notice_sha256", "license") != EXPECTED_LICENSE_SHA256:
        raise ProvenanceError("metadata license.notice_sha256 is not the verified MIT notice")
    if license_metadata["notice_sha256"] != license_metadata["upstream_sha256"]:
        raise ProvenanceError("metadata license hashes disagree")

    redistribution = _require_mapping(record.get("redistribution"), "redistribution")
    if _require_string(redistribution, "status", "redistribution") != "owner_approval_pending":
        raise ProvenanceError("metadata redistribution.status must remain owner_approval_pending")

    manifest = _validate_manifest(record)
    build = _require_mapping(record.get("build"), "build")
    preserved_recipe_path = _validate_relative_path(
        build.get("preserved_recipe_path"), "build.preserved_recipe_path"
    )
    return {
        "license_notice_path": notice_path,
        "manifest": manifest,
        "preserved_recipe_path": preserved_recipe_path,
    }


def _enumerate_files(root: Path) -> dict[str, Path]:
    if not root.is_dir() or root.is_symlink():
        raise ProvenanceError(f"framework root is missing or not a directory: {root}")
    files: dict[str, Path] = {}
    for current, directories, filenames in os.walk(root, followlinks=False):
        current_path = Path(current)
        for directory in directories:
            directory_path = current_path / directory
            if directory_path.is_symlink():
                raise ProvenanceError(f"framework contains an unsupported symlink: {directory_path.relative_to(root)}")
        for filename in filenames:
            file_path = current_path / filename
            relative = file_path.relative_to(root).as_posix()
            if file_path.is_symlink():
                raise ProvenanceError(f"framework contains an unsupported symlink: {relative}")
            if not file_path.is_file():
                raise ProvenanceError(f"framework entry is not a regular file: {relative}")
            files[relative] = file_path
    return dict(sorted(files.items()))


def _validate_framework(framework_path: Path, manifest: dict[str, str]) -> int:
    actual = _enumerate_files(framework_path)
    expected_paths = set(manifest)
    actual_paths = set(actual)
    errors: list[str] = []
    for path in sorted(expected_paths - actual_paths):
        errors.append(f"missing file: {path}")
    for path in sorted(actual_paths - expected_paths):
        errors.append(f"unexpected file: {path}")
    for path in sorted(expected_paths & actual_paths):
        actual_hash = _sha256(actual[path])
        if actual_hash != manifest[path]:
            errors.append(f"modified file: {path} (expected {manifest[path]}, got {actual_hash})")
    if errors:
        raise ProvenanceError("framework manifest mismatch:\n- " + "\n- ".join(errors))
    return len(actual)


def _validate_notice(repo_root: Path, record: dict[str, Any], notice_relative_path: str) -> None:
    notice_path = repo_root / Path(*PurePosixPath(notice_relative_path).parts)
    if not notice_path.is_file() or notice_path.is_symlink():
        raise ProvenanceError(f"MIT notice artifact is missing: {notice_relative_path}")
    actual_hash = _sha256(notice_path)
    if actual_hash != EXPECTED_LICENSE_SHA256:
        raise ProvenanceError(
            f"MIT notice artifact hash mismatch: {notice_relative_path} "
            f"(expected {EXPECTED_LICENSE_SHA256}, got {actual_hash})"
        )


def _validate_preserved_recipe(repo_root: Path, recipe_relative_path: str) -> None:
    recipe_path = repo_root / Path(*PurePosixPath(recipe_relative_path).parts)
    if not recipe_path.is_file() or recipe_path.is_symlink():
        raise ProvenanceError(f"preserved llama build recipe is missing: {recipe_relative_path}")
    actual_hash = _sha256(recipe_path)
    if actual_hash != EXPECTED_BUILD_SCRIPT_SHA256:
        raise ProvenanceError(
            f"preserved llama build recipe hash mismatch: {recipe_relative_path} "
            f"(expected {EXPECTED_BUILD_SCRIPT_SHA256}, got {actual_hash})"
        )


def _git_output(checkout: Path, *arguments: str) -> str:
    process = subprocess.run(
        ["git", "-C", str(checkout), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        detail = (process.stderr or process.stdout).strip()
        raise ProvenanceError(f"git {' '.join(arguments)} failed in {checkout}: {detail}")
    return process.stdout.rstrip("\r\n")


def _git_status_lines(checkout: Path) -> list[tuple[str, list[str]]]:
    output = _git_output(
        checkout,
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
    )
    records = output.split("\0")
    entries: list[tuple[str, list[str]]] = []
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue
        status = record[:2]
        path = record[3:] if len(record) >= 4 else ""
        if len(record) < 4:
            raise ProvenanceError("git status returned a malformed porcelain record")
        paths = [path]
        if status[0] in "RC" or status[1] in "RC":
            if index >= len(records) or not records[index]:
                raise ProvenanceError("git status returned an incomplete rename/copy record")
            paths.append(records[index])
            index += 1
        entries.append((status, paths))
    return entries


def _is_build_relevant_path(path: str) -> bool:
    normalized = path.replace("\\", "/")
    if not normalized:
        return False
    if normalized.startswith("docs/") or PurePosixPath(normalized).name in UNRELATED_DIRTY_BASENAMES:
        return False
    if normalized.startswith(GENERATED_BUILD_PREFIXES):
        return False
    if normalized in BUILD_RELEVANT_ROOT_FILES:
        return True
    if normalized.startswith(BUILD_RELEVANT_PREFIXES):
        return True
    return PurePosixPath(normalized).suffix.lower() in BUILD_RELEVANT_EXTENSIONS


def _build_relevant_dirty_paths(status_entries: list[tuple[str, list[str]]]) -> tuple[list[str], list[str]]:
    build_relevant: list[str] = []
    unrelated: list[str] = []
    for _status, paths in status_entries:
        for path in paths:
            if _is_build_relevant_path(path):
                build_relevant.append(path)
            else:
                unrelated.append(path)
    return sorted(set(build_relevant)), sorted(set(unrelated))


def _compare_trees(left: Path, right: Path, label: str) -> None:
    left_files = _enumerate_files(left)
    right_files = _enumerate_files(right)
    left_paths = set(left_files)
    right_paths = set(right_files)
    errors: list[str] = []
    for path in sorted(left_paths - right_paths):
        errors.append(f"{label}: unexpected upstream file: {path}")
    for path in sorted(right_paths - left_paths):
        errors.append(f"{label}: missing upstream file: {path}")
    for path in sorted(left_paths & right_paths):
        if left_files[path].read_bytes() != right_files[path].read_bytes():
            errors.append(f"{label}: byte mismatch: {path}")
    if errors:
        raise ProvenanceError("\n".join(errors))


def _validate_upstream_checkout(
    checkout: Path,
    vendored_framework: Path,
    repo_root: Path,
    record: dict[str, Any],
    notice_relative_path: str,
) -> list[str]:
    if not checkout.is_dir() or checkout.is_symlink():
        raise ProvenanceError(f"upstream checkout is missing or not a directory: {checkout}")
    remote = _git_output(checkout, "remote", "get-url", record["upstream"]["remote"])
    if remote != EXPECTED_UPSTREAM_URL:
        raise ProvenanceError(f"upstream remote mismatch: expected {EXPECTED_UPSTREAM_URL}, got {remote}")
    head = _git_output(checkout, "rev-parse", "HEAD")
    if head != EXPECTED_UPSTREAM_COMMIT:
        raise ProvenanceError(f"upstream HEAD mismatch: expected {EXPECTED_UPSTREAM_COMMIT}, got {head}")

    build_relevant_dirty, unrelated_dirty = _build_relevant_dirty_paths(_git_status_lines(checkout))
    if build_relevant_dirty:
        paths = ", ".join(build_relevant_dirty)
        raise ProvenanceError(
            "upstream checkout has build-relevant dirty paths; source validation refused: " + paths
        )

    source_script = checkout / Path(*PurePosixPath(record["build"]["source_script"]).parts)
    if not source_script.is_file():
        raise ProvenanceError(f"upstream build recipe is missing: {source_script}")
    preserved_recipe = repo_root / Path(*PurePosixPath(record["build"]["preserved_recipe_path"]).parts)
    if not preserved_recipe.is_file() or preserved_recipe.is_symlink():
        raise ProvenanceError(f"preserved llama build recipe is missing: {preserved_recipe}")
    source_script_hash = _sha256(source_script)
    if source_script_hash != record["build"]["source_script_sha256"]:
        raise ProvenanceError(
            "upstream build recipe hash mismatch: "
            f"expected {record['build']['source_script_sha256']}, got {source_script_hash}"
        )
    preserved_recipe_hash = _sha256(preserved_recipe)
    if preserved_recipe_hash != record["build"]["preserved_recipe_sha256"]:
        raise ProvenanceError(
            "tracked preserved recipe hash mismatch: "
            f"expected {record['build']['preserved_recipe_sha256']}, got {preserved_recipe_hash}"
        )
    if source_script.read_bytes() != preserved_recipe.read_bytes():
        raise ProvenanceError("upstream build recipe bytes do not match the tracked preserved recipe")

    for slice_name in ("device", "simulator"):
        metadata = record["build_metadata"][slice_name]
        build_info = checkout / Path(*PurePosixPath(metadata["build_info_path"]).parts)
        if not build_info.is_file():
            raise ProvenanceError(f"upstream build-info file is missing: {build_info}")
        build_info_hash = _sha256(build_info)
        if build_info_hash != metadata["build_info_sha256"]:
            raise ProvenanceError(
                f"upstream {slice_name} build-info hash mismatch: "
                f"expected {metadata['build_info_sha256']}, got {build_info_hash}"
            )
        if f'LLAMA_COMMIT = "{metadata["llama_commit"]}"' not in build_info.read_text(encoding="utf-8"):
            raise ProvenanceError(f"upstream {slice_name} build-info does not contain the recorded LLAMA_COMMIT")

    output_relative = record["build"]["output"]
    upstream_framework = checkout / Path(*PurePosixPath(output_relative).parts)
    _compare_trees(upstream_framework, vendored_framework, "upstream build comparison")

    upstream_license = checkout / Path(*PurePosixPath(record["license"]["upstream_path"]).parts)
    notice_path = repo_root / Path(*PurePosixPath(notice_relative_path).parts)
    if not upstream_license.is_file():
        raise ProvenanceError(f"upstream LICENSE is missing: {upstream_license}")
    if upstream_license.read_bytes() != notice_path.read_bytes():
        raise ProvenanceError("upstream LICENSE does not match the tracked MIT notice artifact")
    return unrelated_dirty


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, help="repository root; defaults to the script's repository")
    parser.add_argument("--framework", type=Path, help="vendored XCFramework path")
    parser.add_argument("--record", type=Path, help="JSON provenance record path")
    parser.add_argument(
        "--upstream-checkout",
        type=Path,
        help="explicit local llama.cpp checkout for read-only remote/HEAD/output verification",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    repo_root = (args.repo_root or Path(__file__).resolve().parents[1]).resolve()
    record_path = (args.record or repo_root / DEFAULT_RECORD_PATH).resolve()
    framework_path = (args.framework or repo_root / EXPECTED_VENDORED_PATH).resolve()
    try:
        record = _load_record(record_path)
        validated = _validate_record(record)
        _validate_notice(repo_root, record, validated["license_notice_path"])
        _validate_preserved_recipe(repo_root, validated["preserved_recipe_path"])
        file_count = _validate_framework(framework_path, validated["manifest"])
        upstream_status = "not-run"
        unrelated_dirty_paths: list[str] = []
        if args.upstream_checkout is not None:
            unrelated_dirty_paths = _validate_upstream_checkout(
                args.upstream_checkout.resolve(),
                framework_path,
                repo_root,
                record,
                validated["license_notice_path"],
            )
            upstream_status = EXPECTED_BUILD_OBSERVATION_STATUS
    except (OSError, ProvenanceError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    dirty_suffix = (
        f" unrelated_dirty_paths={','.join(unrelated_dirty_paths)}"
        if unrelated_dirty_paths
        else ""
    )
    print(
        "PASS llama framework provenance: "
        f"files={file_count} commit={EXPECTED_UPSTREAM_COMMIT} "
        f"license=MIT upstream_check={upstream_status}{dirty_suffix}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
