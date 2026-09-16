#!/usr/bin/env python3
"""Validate the release component disposition record.

This gate owns the status of every material family, replacing the five
provenance blocker rows previously emitted by ``validate_release_bundle.sh``.
The record deliberately keeps legal and replacement decisions explicit:
technical repository evidence is not legal approval, and a pending replacement
never turns into an allowed Release payload by accident.

The validator is offline and read-only.  It checks the record shape, the
repository source paths, and (when ``--app`` is supplied) the expected paths in
the exact built app.  A well-formed record always emits one
``KNOWN_BLOCKER_COUNT`` metric; malformed records fail before they can be
treated as release evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any


DEFAULT_RECORD_PATH = (
    Path(__file__).resolve().parents[1]
    / "docs/implementation/provenance/release-component-status.json"
)
EXPECTED_SCHEMA = "set-os-release-component-status"
EXPECTED_SCHEMA_VERSION = 1
FONT_PROVENANCE_PATH = "docs/implementation/provenance/font-provenance.json"
SNAPKIT_PROVENANCE_PATH = "docs/implementation/provenance/snapkit-provenance.json"
SNAPKIT_ACKNOWLEDGEMENTS = "Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements"
SOURCE_TREE_HASH_METHOD = "SHA256 of concatenated UTF-8 lines <file SHA256><two spaces><POSIX relative path><LF>, sorted by relative path, covering all installed files."
DISPOSITIONS = frozenset(
    {
        "KEEP",
        "RETRAIN",
        "REPLACE",
        "REMOVE_AFTER_VERIFIED_REPLACEMENT",
    }
)
SCOPES = frozenset({"CAMERA_ONLY", "SCENE_ONLY"})
LEGAL_STATES = frozenset({"PENDING", "APPROVED", "REJECTED"})
RELEASE_MEMBERSHIP = frozenset({"bundled", "excluded", "deferred"})
REPLACEMENT_STATES = frozenset({"PENDING", "VERIFIED"})
REPLACEMENT_DISPOSITIONS = frozenset(
    {"RETRAIN", "REPLACE", "REMOVE_AFTER_VERIFIED_REPLACEMENT"}
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
ID_RE = re.compile(r"[a-z0-9][a-z0-9.-]*\Z")

MATERIAL_KINDS = frozenset(
    {"framework", "model", "media", "font", "asset", "dependency"}
)
NON_RELEASE_KINDS = frozenset({"benchmark", "fixture"})
SUPPLEMENTAL_MATERIAL_PATHS = frozenset({"Pods/SnapKit"})
EXPECTED_ID_OVERRIDES = {
    "Frameworks/llama.xcframework": "llama-framework",
    "shafinMultitool/Multitool2Module/Models/CoreML/DETRResnet50SemanticSegmentationF16P8.mlpackage": "detr-segmentation-model",
    "shafinMultitool/Multitool2Module/Models/CoreML/aesthetic_nima_mobilenet_fp16.mlpackage": "nima-aesthetic-model",
    "shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf": "scene-gguf-model",
    "shafinMultitool/Resources/Circle.rcproject": "circle-rcproject",
    "shafinMultitool/Resources/Circle.usdz": "circle-usdz",
    "shafinMultitool/Resources/Person.usdz": "person-usdz",
    "shafinMultitool/Multitool2Module/Assets.xcassets": "module-assets-catalog",
    "shafinMultitool/Resources/Assets.xcassets": "resource-assets-catalog",
    "shafinMultitool/PrivacyInfo.xcprivacy": "privacy-manifest",
    "shafinMultitool/Resources/InfoPlist.xcstrings": "info-plist-localization",
    "shafinMultitool/Resources/Localizable.xcstrings": "localized-resources",
    "shafinMultitool/Resources/Textures/SETGrain.png": "set-grain-texture",
    "Pods/SnapKit": "snapkit-dependency",
}


class ComponentStatusValidationError(ValueError):
    """Raised when the status record cannot be trusted as release evidence."""


def _fail(message: str) -> None:
    raise ComponentStatusValidationError(message)


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail(f"malformed record: {label} must be an object")
    return value


def _list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        _fail(f"malformed record: {label} must be an array")
    return value


def _required(mapping: dict[str, Any], key: str, label: str) -> Any:
    if key not in mapping:
        _fail(f"malformed record: {label} is missing required field '{key}'")
    return mapping[key]


def _nonempty_string(mapping: dict[str, Any], key: str, label: str) -> str:
    value = _required(mapping, key, label)
    if not isinstance(value, str) or not value.strip():
        _fail(f"malformed record: {label}.{key} must be a non-empty string")
    return value


def _strict_keys(mapping: dict[str, Any], required: set[str], optional: set[str], label: str) -> None:
    missing = sorted(required - mapping.keys())
    if missing:
        _fail(f"malformed record: {label} is missing required field(s): {', '.join(missing)}")
    unknown = sorted(set(mapping) - required - optional)
    if unknown:
        _fail(f"malformed record: {label} contains unknown field(s): {', '.join(unknown)}")


def _safe_relative_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(f"malformed record: {label} must be a non-empty relative path")
    if "\\" in value:
        _fail(f"malformed record: {label} must use POSIX separators")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        _fail(f"malformed record: {label} must not escape its root: {value}")
    return path.as_posix()


def _sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        _fail(f"malformed record: {label} must be a lowercase SHA-256 digest")
    return value


def _load_json(path: Path, label: str) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file():
        _fail(f"{label} file is missing or is a symlink: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"malformed record: cannot read {label} at {path}: {exc}")
    return _mapping(value, label)


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_snapkit_provenance(repo_root: Path, app_root: Path | None = None) -> dict[str, Any]:
    """Bind the admitted source, CocoaPods locks and full shipped MIT notice."""
    repo_root = repo_root.resolve()
    proof = _load_json(repo_root / SNAPKIT_PROVENANCE_PATH, "SnapKit provenance")
    _strict_keys(proof, {"schema", "schema_version", "verified_at", "id", "version", "upstream_repository",
        "upstream_commit", "upstream_tag", "podspec_checksum_sha1", "lock_sha256", "source_path",
        "source_tree_sha256", "source_tree_hash_method", "source_file_count", "source_swift_count", "license",
        "license_path", "license_sha256", "notice_source_path", "notice_bundle_path", "evidence_receipt_path",
        "evidence_receipt_sha256", "licensing_basis", "limitations"}, set(), "SnapKit provenance")
    if proof["schema"] != "set-os-snapkit-provenance" or type(proof["schema_version"]) is not int or proof["schema_version"] != 1:
        _fail("unsupported SnapKit provenance schema")
    if (proof["id"] != "snapkit-dependency" or proof["license"] != "MIT" or
            proof["upstream_repository"] != "https://github.com/SnapKit/SnapKit"):
        _fail("SnapKit provenance does not identify the admitted MIT upstream")
    for key in ("upstream_commit", "podspec_checksum_sha1"):
        if not isinstance(proof[key], str) or not re.fullmatch(r"[0-9a-f]{40}", proof[key]):
            _fail("SnapKit provenance needs an immutable upstream commit and spec checksum")
    version = _nonempty_string(proof, "version", "SnapKit provenance")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or proof["upstream_tag"] != version:
        _fail("SnapKit provenance version/tag mismatch")
    for key in ("source_file_count", "source_swift_count"):
        if type(proof[key]) is not int or proof[key] <= 0:
            _fail("SnapKit provenance must cover a non-empty installed source tree")
    for key in ("lock_sha256", "source_tree_sha256", "license_sha256", "evidence_receipt_sha256"):
        _sha256(proof[key], "SnapKit " + key)
    for key in ("source_path", "license_path", "notice_source_path", "notice_bundle_path"):
        _safe_relative_path(proof[key], "SnapKit " + key)
    if (proof["source_path"] != "Pods/SnapKit" or proof["license_path"] != "Pods/SnapKit/LICENSE" or
            proof["notice_source_path"] != "third-party-notices/SnapKit-LICENSE.txt" or
            proof["notice_bundle_path"] != "SnapKit-LICENSE.txt" or proof["source_tree_hash_method"] != SOURCE_TREE_HASH_METHOD):
        _fail("SnapKit provenance source/notice path or hashing contract changed")

    def read_file(root: Path, relative: str, label: str) -> bytes:
        path = root / relative
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            _fail(f"{label} is missing, outside its root, or a symlink: {relative}")
        try:
            return path.read_bytes()
        except OSError as exc:
            _fail(f"cannot read {label}: {exc}")

    lock = read_file(repo_root, "Podfile.lock", "SnapKit Podfile.lock")
    installed_lock = read_file(repo_root, "Pods/Manifest.lock", "SnapKit installed lock")
    if lock != installed_lock or hashlib.sha256(lock).hexdigest() != proof["lock_sha256"]:
        _fail("SnapKit lockfiles differ or changed since source verification")
    try:
        lock_text = lock.decode("utf-8")
    except UnicodeError as exc:
        _fail(f"SnapKit lock is not UTF-8: {exc}")
    if (re.findall(r"(?m)^  - SnapKit \(([0-9.]+)\)$", lock_text) != [version] or
            re.findall(r"(?m)^  SnapKit: ([0-9a-f]{40})$", lock_text) != [proof["podspec_checksum_sha1"]]):
        _fail("SnapKit lock version/spec checksum does not match provenance")
    podfile_sha1 = hashlib.sha1(read_file(repo_root, "Podfile", "SnapKit Podfile")).hexdigest()
    if re.findall(r"(?m)^PODFILE CHECKSUM: ([0-9a-f]{40})$", lock_text) != [podfile_sha1]:
        _fail("SnapKit Podfile changed after the installed lock")

    source_root = repo_root / proof["source_path"]
    if source_root.is_symlink() or not source_root.is_dir() or not source_root.resolve().is_relative_to(repo_root):
        _fail("SnapKit installed source root is missing, outside repository, or a symlink")
    source_files: list[str] = []
    try:
        for path in source_root.rglob("*"):
            if path.is_symlink() or not (path.is_file() or path.is_dir()):
                _fail("SnapKit source tree contains a symlink or nonregular entry")
            if path.is_file():
                source_files.append(path.relative_to(source_root).as_posix())
    except OSError as exc:
        _fail(f"cannot enumerate SnapKit source tree: {exc}")
    source_files.sort()
    if len(source_files) != proof["source_file_count"] or sum(name.endswith(".swift") for name in source_files) != proof["source_swift_count"]:
        _fail("SnapKit source tree file coverage changed")
    tree_lines = []
    for relative in source_files:
        digest = hashlib.sha256(read_file(source_root, relative, "SnapKit source file")).hexdigest()
        tree_lines.append(f"{digest}  {relative}\n")
    if hashlib.sha256("".join(tree_lines).encode("utf-8")).hexdigest() != proof["source_tree_sha256"]:
        _fail("SnapKit source tree SHA mismatch")

    license_bytes = read_file(repo_root, proof["license_path"], "SnapKit upstream license")
    notice_bytes = read_file(repo_root, proof["notice_source_path"], "SnapKit preserved notice")
    if hashlib.sha256(license_bytes).hexdigest() != proof["license_sha256"] or notice_bytes != license_bytes:
        _fail("SnapKit preserved copyright/license notice SHA mismatch")
    plist_bytes = read_file(repo_root, SNAPKIT_ACKNOWLEDGEMENTS + ".plist", "SnapKit CocoaPods acknowledgement plist")
    markdown = read_file(repo_root, SNAPKIT_ACKNOWLEDGEMENTS + ".markdown", "SnapKit CocoaPods acknowledgement markdown")
    try:
        acknowledgements = plistlib.loads(plist_bytes)
        entries = acknowledgements.get("PreferenceSpecifiers") if isinstance(acknowledgements, dict) else None
        if not isinstance(entries, list) or not all(isinstance(row, dict) for row in entries):
            _fail("SnapKit acknowledgement plist has no valid PreferenceSpecifiers")
        snapkit_entries = [row for row in entries if row.get("Title") == "SnapKit"]
        if len(snapkit_entries) != 1:
            _fail("SnapKit acknowledgement entry must occur exactly once")
        entry = snapkit_entries[0]
        footer = entry.get("FooterText")
        if (entry.get("License") != "MIT" or entry.get("Type") != "PSGroupSpecifier" or
                not isinstance(footer, str) or footer.encode("utf-8") != license_bytes):
            _fail("SnapKit acknowledgement does not contain the complete exact MIT notice")
    except (ValueError, TypeError, OverflowError, UnicodeError) as exc:
        _fail(f"cannot parse SnapKit acknowledgement plist: {exc}")
    if license_bytes not in markdown or b"## SnapKit\n" not in markdown:
        _fail("SnapKit acknowledgement markdown does not contain the exact MIT notice")
    if b"arvideokit" in markdown.lower() or b"arvideokit" in plist_bytes.lower():
        _fail("SnapKit acknowledgement contains forbidden ARVideoKit")
    if app_root is not None:
        if read_file(app_root, proof["notice_bundle_path"], "bundled SnapKit MIT notice") != license_bytes:
            _fail("bundled SnapKit MIT notice SHA mismatch")
    return proof


def validate_font_provenance(repo_root: Path, app_root: Path | None = None) -> dict[str, dict[str, Any]]:
    """Verify the exact admitted font/notice pairs, independently of filenames."""
    repo_root = repo_root.resolve()
    proof = _load_json(repo_root / FONT_PROVENANCE_PATH, "font provenance")
    _strict_keys(proof, {"schema", "schema_version", "verified_at", "upstream_repository", "upstream_commit",
        "evidence_receipt_path", "evidence_receipt_sha256", "license", "licensing_basis", "limitations", "fonts"}, set(), "font provenance")
    if proof["schema"] != "set-os-font-provenance" or type(proof["schema_version"]) is not int or proof["schema_version"] != 1:
        _fail("unsupported font provenance schema")
    if proof["license"] != "OFL-1.1" or proof["upstream_repository"] != "https://github.com/google/fonts":
        _fail("font provenance license/upstream is not the admitted OFL source")
    if not isinstance(proof["upstream_commit"], str) or not re.fullmatch(r"[0-9a-f]{40}", proof["upstream_commit"]):
        _fail("font provenance needs an immutable upstream commit")
    _sha256(proof["evidence_receipt_sha256"], "font evidence receipt SHA")
    rows = _list(proof["fonts"], "font provenance fonts")
    if not rows:
        _fail("font provenance is empty")
    verified: dict[str, dict[str, Any]] = {}
    bundle_names: set[str] = set()
    notice_names: set[str] = set()

    def checked_file(root: Path, relative: str, digest: str, label: str) -> None:
        path = root / relative
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            _fail(f"{label} is missing, outside its root, or a symlink: {relative}")
        try:
            actual = _file_digest(path)
        except OSError as exc:
            _fail(f"cannot read {label}: {exc}")
        if actual != digest:
            _fail(f"{label} SHA mismatch: {relative}")

    for raw in rows:
        row = _mapping(raw, "font provenance row")
        _strict_keys(row, {"id", "source_path", "bundle_path", "sha256", "notice_path", "notice_bundle_path",
            "notice_sha256", "upstream_font_path", "upstream_notice_path", "family", "embedded_version"}, set(), "font provenance row")
        component_id = _nonempty_string(row, "id", "font provenance row")
        if component_id in verified:
            _fail("duplicate font provenance component")
        for key in ("source_path", "bundle_path", "notice_path", "notice_bundle_path", "upstream_font_path", "upstream_notice_path"):
            _safe_relative_path(row[key], "font provenance " + key)
        if row["bundle_path"] != Path(row["source_path"]).name or row["notice_bundle_path"] != Path(row["notice_path"]).name:
            _fail("font provenance bundle paths must preserve source filenames at app root")
        if row["bundle_path"] in bundle_names or row["notice_bundle_path"] in notice_names:
            _fail("duplicate font or notice bundle filename")
        bundle_names.add(row["bundle_path"]); notice_names.add(row["notice_bundle_path"])
        font_sha = _sha256(row["sha256"], "font SHA")
        notice_sha = _sha256(row["notice_sha256"], "font notice SHA")
        checked_file(repo_root, row["source_path"], font_sha, "font source")
        checked_file(repo_root, row["notice_path"], notice_sha, "font notice source")
        if app_root is not None:
            checked_file(app_root, row["bundle_path"], font_sha, "bundled font")
            checked_file(app_root, row["notice_bundle_path"], notice_sha, "bundled font notice")
        verified[component_id] = dict(row)
    info_path = (app_root / "Info.plist") if app_root is not None else (repo_root / "shafinMultitool/Info.plist")
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
            declared = info.get("UIAppFonts") if isinstance(info, dict) else None
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as exc:
        _fail(f"font provenance cannot read UIAppFonts: {exc}")
    if (not isinstance(declared, list) or not all(isinstance(name, str) for name in declared) or
            len(declared) != len(set(declared)) or set(declared) != bundle_names):
        _fail("font provenance does not cover exactly UIAppFonts")
    return verified


def _load_inventory_rows(path: Path) -> list[dict[str, Any]]:
    try:
        raw_rows = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"malformed source inventory: cannot read {path}: {exc}")
    rows = _list(raw_rows, "source inventory")
    if not rows:
        _fail("malformed source inventory: must not be empty")
    result: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for index, raw_row in enumerate(rows):
        row = _mapping(raw_row, f"source inventory[{index}]")
        path_value = _safe_relative_path(
            _required(row, "path", f"source inventory[{index}]"),
            f"source inventory[{index}].path",
        )
        if path_value in seen_paths:
            _fail(f"malformed source inventory: duplicate path: {path_value}")
        seen_paths.add(path_value)
        result.append({"path": path_value})
    return result


def _material_family_paths(rows: list[dict[str, Any]]) -> set[str]:
    """Derive material family roots from the complete M0 inventory.

    Packages and asset catalogs are one release family each; individual font,
    texture, media, localization, and manifest files remain independently
    addressable. This keeps the coverage check exact-once without pretending
    that every package member is an independent product component.
    """

    families: set[str] = set()
    for row in rows:
        value = row["path"]
        path = PurePosixPath(value)
        if value.startswith("Frameworks/llama.xcframework/"):
            families.add("Frameworks/llama.xcframework")
            continue
        if ".mlpackage/" in value:
            package_end = value.index(".mlpackage/") + len(".mlpackage")
            families.add(value[:package_end])
            continue
        if ".xcassets/" in value:
            catalog_end = value.index(".xcassets/") + len(".xcassets")
            families.add(value[:catalog_end])
            continue
        if value.endswith(".usdz") or value.endswith(".gguf"):
            families.add(value)
            continue
        if value.endswith(".rcproject/"):
            families.add(value.rstrip("/"))
            continue
        if ".rcproject/" in value:
            project_end = value.index(".rcproject/") + len(".rcproject")
            families.add(value[:project_end])
            continue
        if "/Fonts/" in value and value.endswith(".ttf"):
            families.add(value)
            continue
        if value.endswith(".xcstrings") or value.endswith(".xcprivacy"):
            families.add(value)
            continue
        if "/Textures/" in value and path.suffix.lower() in {".png", ".jpg", ".jpeg", ".heic", ".webp"}:
            families.add(value)
    families.update(SUPPLEMENTAL_MATERIAL_PATHS)
    if not families:
        _fail("malformed source inventory: no material families were derived")
    return families


def _canonical_component_id(source_path: str) -> str:
    if source_path in EXPECTED_ID_OVERRIDES:
        return EXPECTED_ID_OVERRIDES[source_path]
    name = source_path.rsplit("/", 1)[-1]
    if name.endswith(".ttf"):
        name = name[:-4]
    elif name.endswith(".png"):
        name = name[:-4]
    elif name.endswith(".xcstrings"):
        name = name[:-10]
    elif name.endswith(".xcprivacy"):
        name = name[:-10]
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    prefix = "font" if "/Fonts/" in source_path else "asset"
    return f"{prefix}-{slug}"


def _reject_path_overlaps(paths: set[str], label: str) -> None:
    ordered = sorted(paths)
    for index, first in enumerate(ordered):
        for second in ordered[index + 1 :]:
            if second.startswith(first + "/") or first.startswith(second + "/"):
                _fail(f"malformed record: cross-family {label} overlap: {first} and {second}")


def _validate_source(source: dict[str, Any], repo_root: Path) -> set[str]:
    _strict_keys(
        source,
        {"baseline_task", "inventory_path", "inventory_sha256"},
        set(),
        "source",
    )
    if _nonempty_string(source, "baseline_task", "source") != "M0-007":
        _fail("malformed record: source.baseline_task must be M0-007")
    inventory_path = _safe_relative_path(
        _required(source, "inventory_path", "source"), "source.inventory_path"
    )
    inventory_sha256 = _sha256(
        _required(source, "inventory_sha256", "source"), "source.inventory_sha256"
    )
    inventory = repo_root / inventory_path
    if not inventory.is_file() or inventory.is_symlink():
        _fail(f"source inventory is missing or is a symlink: {inventory_path}")
    if _file_digest(inventory) != inventory_sha256:
        _fail(f"source inventory hash mismatch: {inventory_path}")
    return _material_family_paths(_load_inventory_rows(inventory))


def _validate_expected(expected: dict[str, Any], label: str) -> dict[str, str | None]:
    _strict_keys(expected, set(), {"source_path", "bundle_path", "manifest_sha256"}, label)
    values: dict[str, str | None] = {
        "source_path": None,
        "bundle_path": None,
        "manifest_sha256": None,
    }
    for key in values:
        if key not in expected or expected[key] is None:
            continue
        if key.endswith("path"):
            values[key] = _safe_relative_path(expected[key], f"{label}.{key}")
        else:
            values[key] = _sha256(expected[key], f"{label}.{key}")
    if not any(values.values()):
        _fail(f"malformed record: {label} must contain a source/bundle path or manifest hash")
    return values


def _validate_replacement(
    value: Any, disposition: str, label: str
) -> dict[str, str] | None:
    if disposition not in REPLACEMENT_DISPOSITIONS:
        if value is not None:
            _fail(f"malformed record: {label} must be null for KEEP")
        return None
    dependency = _mapping(value, label)
    _strict_keys(dependency, {"task", "status", "reason"}, set(), label)
    task = _nonempty_string(dependency, "task", label)
    status = _nonempty_string(dependency, "status", label)
    reason = _nonempty_string(dependency, "reason", label)
    if status not in REPLACEMENT_STATES:
        _fail(f"malformed record: {label}.status is unknown: {status}")
    return {"task": task, "status": status, "reason": reason}


def _validate_release_membership(value: Any, label: str) -> dict[str, str]:
    membership = _mapping(value, label)
    _strict_keys(membership, {"Debug", "Release"}, set(), label)
    result: dict[str, str] = {}
    for configuration in ("Debug", "Release"):
        state = _nonempty_string(membership, configuration, label)
        if state not in RELEASE_MEMBERSHIP:
            _fail(f"malformed record: {label}.{configuration} is unknown: {state}")
        result[configuration] = state
    return result


def _validate_component(
    raw: Any,
    index: int,
    repo_root: Path,
    app_root: Path | None,
) -> tuple[dict[str, Any], str | None]:
    label = f"components[{index}]"
    component = _mapping(raw, label)
    _strict_keys(
        component,
        {
            "id",
            "kind",
            "disposition",
            "scope",
            "source_state",
            "owner",
            "reason",
            "expected",
            "legal_state",
            "replacement_dependency",
            "release_config_membership",
        },
        set(),
        label,
    )
    component_id = _nonempty_string(component, "id", label)
    if not ID_RE.fullmatch(component_id):
        _fail(f"malformed record: {label}.id is not a stable lowercase id: {component_id}")
    kind = _nonempty_string(component, "kind", label)
    if kind not in MATERIAL_KINDS:
        _fail(f"malformed record: {label}.kind is unknown: {kind}")
    disposition = _nonempty_string(component, "disposition", label)
    if disposition not in DISPOSITIONS:
        _fail(f"malformed record: {label}.disposition is unknown: {disposition}")
    scope_values = _list(_required(component, "scope", label), f"{label}.scope")
    if not scope_values:
        _fail(f"malformed record: {label}.scope must not be empty")
    scope: list[str] = []
    for scope_index, raw_scope in enumerate(scope_values):
        if not isinstance(raw_scope, str) or raw_scope not in SCOPES:
            _fail(f"malformed record: {label}.scope[{scope_index}] is unknown")
        if raw_scope in scope:
            _fail(f"malformed record: {label}.scope contains a duplicate value: {raw_scope}")
        scope.append(raw_scope)
    source_state = _nonempty_string(component, "source_state", label)
    if source_state not in {"present", "absent"}:
        _fail(f"malformed record: {label}.source_state is unknown: {source_state}")
    owner = _nonempty_string(component, "owner", label)
    reason = _nonempty_string(component, "reason", label)
    expected = _validate_expected(
        _mapping(_required(component, "expected", label), f"{label}.expected"),
        f"{label}.expected",
    )
    if expected["source_path"] is None:
        _fail(f"malformed record: {label}.expected.source_path is required for material coverage")
    legal_state = _nonempty_string(component, "legal_state", label)
    if legal_state not in LEGAL_STATES:
        _fail(f"malformed record: {label}.legal_state is unknown: {legal_state}")
    replacement = _validate_replacement(
        component["replacement_dependency"], disposition, f"{label}.replacement_dependency"
    )
    membership = _validate_release_membership(
        component["release_config_membership"], f"{label}.release_config_membership"
    )

    source_path = expected["source_path"]
    assert source_path is not None
    source = repo_root / source_path
    source_present = source.exists() and not source.is_symlink()
    if source_state == "present" and not source_present:
        _fail(f"component source path is missing or is a symlink: {source_path}")
    if source_state == "absent" and source_present:
        _fail(f"component source state says absent but path exists: {source_path}")
    bundle_path = expected["bundle_path"]
    if app_root is not None and bundle_path is not None:
        bundle = app_root / bundle_path
        present = bundle.exists() and not bundle.is_symlink()
        if membership["Release"] == "bundled" and not present:
            _fail(f"component bundle path is missing or is a symlink: {bundle_path}")
        if membership["Release"] == "excluded" and present:
            _fail(f"excluded component is present in Release bundle: {bundle_path}")
    if membership["Release"] == "bundled" and source_state != "present":
        _fail(f"malformed record: {label} cannot bundle an absent source")

    blocker: str | None = None
    if membership["Release"] == "deferred":
        blocker = "release-membership-deferred"
    elif membership["Release"] == "bundled":
        if legal_state != "APPROVED":
            blocker = f"legal-state-{legal_state.lower()}"
        elif disposition in REPLACEMENT_DISPOSITIONS and replacement is not None:
            if replacement["status"] != "VERIFIED":
                blocker = f"replacement-{replacement['status'].lower()}"
        elif disposition in REPLACEMENT_DISPOSITIONS:
            _fail(f"malformed record: {label}.replacement_dependency is required")

    normalized = {
        "id": component_id,
        "kind": kind,
        "disposition": disposition,
        "scope": scope,
        "source_state": source_state,
        "owner": owner,
        "reason": reason,
        "expected": expected,
        "legal_state": legal_state,
        "replacement_dependency": replacement,
        "release_config_membership": membership,
    }
    return normalized, blocker


def _validate_exclusions(value: Any, repo_root: Path) -> set[str]:
    exclusions = _list(value, "explicit_exclusions")
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for index, raw in enumerate(exclusions):
        label = f"explicit_exclusions[{index}]"
        exclusion = _mapping(raw, label)
        _strict_keys(
            exclusion,
            {"id", "kind", "scope", "path", "owner", "reason", "release_config_membership"},
            set(),
            label,
        )
        exclusion_id = _nonempty_string(exclusion, "id", label)
        if not ID_RE.fullmatch(exclusion_id) or exclusion_id in seen_ids:
            _fail(f"malformed record: duplicate or unstable exclusion id: {exclusion_id}")
        seen_ids.add(exclusion_id)
        kind = _nonempty_string(exclusion, "kind", label)
        if kind not in NON_RELEASE_KINDS:
            _fail(f"malformed record: {label}.kind is unknown: {kind}")
        scopes = _list(_required(exclusion, "scope", label), f"{label}.scope")
        if not scopes or any(scope not in SCOPES for scope in scopes):
            _fail(f"malformed record: {label}.scope is empty or unknown")
        if len(scopes) != len(set(scopes)):
            _fail(f"malformed record: {label}.scope contains a duplicate value")
        path = _safe_relative_path(_required(exclusion, "path", label), f"{label}.path")
        if path in seen_paths:
            _fail(f"malformed record: duplicate exclusion path: {path}")
        seen_paths.add(path)
        exclusion_path = repo_root / path
        if not exclusion_path.exists() or exclusion_path.is_symlink():
            _fail(f"explicit exclusion path is missing or is a symlink: {path}")
        _nonempty_string(exclusion, "owner", label)
        _nonempty_string(exclusion, "reason", label)
        membership = _validate_release_membership(
            _required(exclusion, "release_config_membership", label),
            f"{label}.release_config_membership",
        )
        if membership["Release"] != "excluded":
            _fail(f"malformed record: {label} must have Release=excluded")
    return seen_paths


def _validate_record_shape(
    record: dict[str, Any], repo_root: Path, app_root: Path | None
) -> list[tuple[dict[str, Any], str | None]]:
    _strict_keys(
        record,
        {"schema", "schema_version", "source", "components", "explicit_exclusions"},
        {"$schema"},
        "record",
    )
    if _required(record, "schema", "record") != EXPECTED_SCHEMA:
        _fail("malformed record: unsupported schema")
    if _required(record, "schema_version", "record") != EXPECTED_SCHEMA_VERSION:
        _fail("malformed record: unsupported schema_version")
    material_family_paths = _validate_source(
        _mapping(_required(record, "source", "record"), "source"), repo_root
    )
    components = _list(_required(record, "components", "record"), "components")
    if not components:
        _fail("malformed record: components must not be empty")
    results: list[tuple[dict[str, Any], str | None]] = []
    seen_ids: set[str] = set()
    seen_source_paths: set[str] = set()
    seen_bundle_paths: set[str] = set()
    for index, raw in enumerate(components):
        normalized, blocker = _validate_component(raw, index, repo_root, app_root)
        component_id = normalized["id"]
        if component_id in seen_ids:
            _fail(f"malformed record: duplicate component id: {component_id}")
        source_path = normalized["expected"]["source_path"]
        assert source_path is not None
        if source_path in seen_source_paths:
            _fail(f"malformed record: duplicate component source path: {source_path}")
        expected_id = _canonical_component_id(source_path)
        if component_id != expected_id:
            _fail(
                f"malformed record: component id does not match source family: "
                f"{component_id} != {expected_id}"
            )
        seen_source_paths.add(source_path)
        bundle_path = normalized["expected"]["bundle_path"]
        if bundle_path is not None:
            if bundle_path in seen_bundle_paths:
                _fail(f"malformed record: duplicate component bundle path: {bundle_path}")
            seen_bundle_paths.add(bundle_path)
        seen_ids.add(component_id)
        results.append((normalized, blocker))
    _reject_path_overlaps(seen_source_paths, "source path")
    _reject_path_overlaps(seen_bundle_paths, "bundle path")
    if seen_source_paths != material_family_paths:
        missing = sorted(material_family_paths - seen_source_paths)
        unknown = sorted(seen_source_paths - material_family_paths)
        details = []
        if missing:
            details.append(f"missing={','.join(missing)}")
        if unknown:
            details.append(f"unknown={','.join(unknown)}")
        _fail("malformed record: material family coverage mismatch (" + "; ".join(details) + ")")
    exclusion_paths = _validate_exclusions(
        _required(record, "explicit_exclusions", "record"), repo_root
    )
    duplicate_coverage_paths = sorted(seen_source_paths & exclusion_paths)
    if duplicate_coverage_paths:
        _fail(
            "malformed record: coverage path is listed as both component and exclusion: "
            + ",".join(duplicate_coverage_paths)
        )
    _reject_path_overlaps(seen_source_paths | exclusion_paths, "coverage path")
    return results


def validate_record(
    repo_root: Path, record_path: Path = DEFAULT_RECORD_PATH, app_root: Path | None = None
) -> list[dict[str, Any]]:
    """Validate a record and return normalized known blockers.

    The function is intentionally read-only.  A successful return means the
    schema and all referenced paths were valid; an empty list means the
    Release configuration is technically unblocked by this manifest.
    """

    if repo_root.is_symlink():
        _fail(f"repository root is missing or is a symlink: {repo_root}")
    if record_path.is_symlink():
        _fail(f"status record is missing or is a symlink: {record_path}")
    if app_root is not None and app_root.is_symlink():
        _fail(f"app root is missing or is a symlink: {app_root}")
    repo_root = repo_root.resolve()
    record_path = record_path.resolve()
    if not repo_root.is_dir():
        _fail(f"repository root is missing or is a symlink: {repo_root}")
    if app_root is not None:
        app_root = app_root.resolve()
        if not app_root.is_dir():
            _fail(f"app root is missing or is a symlink: {app_root}")
    record = _load_json(record_path, "status record")
    results = _validate_record_shape(record, repo_root, app_root)
    approved_fonts = [component for component, _ in results if component["kind"] == "font" and
                      component["legal_state"] == "APPROVED" and component["release_config_membership"]["Release"] == "bundled"]
    if approved_fonts:
        font_proof = validate_font_provenance(repo_root, app_root)
        for component in approved_fonts:
            proved = font_proof.get(component["id"])
            if proved is None or proved["source_path"] != component["expected"]["source_path"]:
                _fail("approved font lacks matching hash-bound provenance: " + component["id"])
    approved_snapkit = [component for component, _ in results if component["id"] == "snapkit-dependency" and
                        component["legal_state"] == "APPROVED" and component["release_config_membership"]["Release"] == "bundled"]
    if approved_snapkit:
        snapkit_proof = validate_snapkit_provenance(repo_root, app_root)
        if approved_snapkit[0]["expected"]["source_path"] != snapkit_proof["source_path"]:
            _fail("approved SnapKit lacks matching hash-bound source provenance")
    blockers: list[dict[str, Any]] = []
    for component, blocker in results:
        if blocker is None:
            continue
        blockers.append(
            {
                "id": component["id"],
                "component": component["expected"].get("bundle_path") or component["id"],
                "kind": component["kind"],
                "disposition": component["disposition"],
                "scope": component["scope"],
                "legal_state": component["legal_state"],
                "blocker": blocker,
                "reason": component["reason"],
            }
        )
    return sorted(blockers, key=lambda row: row["id"])


def _emit_blockers(blockers: list[dict[str, Any]]) -> None:
    for blocker in blockers:
        print(
            "KNOWN_BLOCKER: "
            f"id={blocker['id']} "
            f"component={blocker['component']} "
            f"kind={blocker['kind']} "
            f"disposition={blocker['disposition']} "
            f"scope={','.join(blocker['scope'])} "
            f"legal_state={blocker['legal_state']} "
            f"blocker={blocker['blocker']}"
        )
    print(f"KNOWN_BLOCKER_COUNT={len(blockers)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--record", type=Path, default=DEFAULT_RECORD_PATH)
    parser.add_argument("--app", type=Path, help="optional exact built Release app to inspect")
    scope_options = parser.add_mutually_exclusive_group()
    scope_options.add_argument("--fonts-only", action="store_true", help="verify admitted font/notice hashes only; not a full release decision")
    scope_options.add_argument("--snapkit-only", action="store_true", help="verify SnapKit source and full MIT notice only; not a full release decision")
    args = parser.parse_args(argv)
    try:
        if args.fonts_only:
            fonts = validate_font_provenance(args.repo_root, args.app)
            scope = "bundle" if args.app is not None else "source"
            print(f"PASS FONT PROVENANCE: scope={scope} fonts={len(fonts)} notices={len(fonts)}; other release gates remain separate")
            return 0
        if args.snapkit_only:
            proof = validate_snapkit_provenance(args.repo_root, args.app)
            scope = "bundle" if args.app is not None else "source"
            print(f"PASS SNAPKIT PROVENANCE: scope={scope} version={proof['version']} files={proof['source_file_count']} license=MIT; other release gates remain separate")
            return 0
        blockers = validate_record(args.repo_root, args.record, args.app)
    except ComponentStatusValidationError as exc:
        print(f"FAIL COMPONENT STATUS: {exc}", file=sys.stderr)
        return 1
    _emit_blockers(blockers)
    if blockers:
        print(
            f"FAIL COMPONENT STATUS: release blocked by {len(blockers)} known provenance blocker(s)",
            file=sys.stderr,
        )
        return 1
    print("PASS COMPONENT STATUS: no known provenance blockers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
