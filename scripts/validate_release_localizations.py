#!/usr/bin/env python3
"""Compare the two app string catalogs with Xcode's exact compiled products.

The installed compiler owns fallback, extraction, plural and substitution
semantics. This gate does not synthesize translations from catalog keys.
It reads the supplied app, compiles immutable source snapshots in temporary
storage, and compares decoded property lists rather than serialization bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any
from xml.parsers.expat import ExpatError


CATALOGS = ("InfoPlist", "Localizable")
LOCALES = frozenset({"en", "ru"})
RESOURCE_ROOT = Path("shafinMultitool/Resources")
PRODUCT_SUFFIXES = frozenset({".strings", ".stringsdict"})


class ValidationError(ValueError):
    pass


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_regular(path: Path, root: Path) -> bytes:
    cursor = root
    for part in path.relative_to(root).parts:
        cursor /= part
        if cursor.is_symlink():
            raise ValidationError(f"symlink is not an admitted localization input: {cursor}")
    if not path.is_file():
        raise ValidationError(f"localization file is missing: {path}")
    return path.read_bytes()


def _run(argv: list[str]) -> bytes:
    try:
        result = subprocess.run(argv, capture_output=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValidationError(f"localization tool could not complete: {argv[0]}: {exc}") from exc
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()[:1000]
        raise ValidationError(f"localization tool failed: {argv[0]} exit={result.returncode}: {detail}")
    return result.stdout


def _unique_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError(f"duplicate catalog JSON key: {key!r}")
        result[key] = value
    return result


def _check_catalog(data: bytes, label: str) -> None:
    try:
        document = json.loads(data, object_pairs_hook=_unique_json_object)
    except (ValueError, UnicodeError) as exc:
        raise ValidationError(f"invalid string catalog {label}: {exc}") from exc
    if not isinstance(document, dict) or document.get("sourceLanguage") != "en":
        raise ValidationError(f"{label}: required sourceLanguage is en")
    strings = document.get("strings")
    if not isinstance(strings, dict) or not strings:
        raise ValidationError(f"{label}: string catalog must contain nonempty strings")
    for key, entry in strings.items():
        if not isinstance(entry, dict) or not isinstance(entry.get("localizations", {}), dict):
            raise ValidationError(f"{label}: invalid localizations for key {key!r}")
        extra_locales = set(entry.get("localizations", {})) - LOCALES
        if extra_locales:
            raise ValidationError(f"{label}: unsupported source locales: {sorted(extra_locales)}")


def _compile_catalog(compiler: Path, source: Path, output: Path) -> None:
    output.mkdir()
    # Compile all declared languages; --language filtering could hide an extra
    # source locale. Binary serialization preserves the default .strings and
    # .stringsdict product split and is directly readable by plistlib.
    _run([str(compiler), "compile", str(source), "--output-directory", str(output),
          "--serialization-format", "binary"])


def _compiled_products(root: Path, table: str) -> dict[str, bytes]:
    products: dict[str, bytes] = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValidationError(f"compiler emitted a symlink: {path}")
        if path.is_dir():
            continue
        relative = path.relative_to(root)
        if (len(relative.parts) != 2 or relative.parts[0] not in {f"{x}.lproj" for x in LOCALES}
                or path.stem != table or path.suffix not in PRODUCT_SUFFIXES):
            raise ValidationError(f"unsupported localization compiler product: {relative}")
        products[relative.as_posix()] = _read_regular(path, root)
    for locale in sorted(LOCALES):
        if not any(name.startswith(f"{locale}.lproj/") for name in products):
            raise ValidationError(f"{table}: compiler produced no {locale} localization products")
    return products


def _app_products(app: Path) -> dict[str, bytes]:
    products: dict[str, bytes] = {}
    for directory in sorted(app.iterdir()):
        if directory.stem in CATALOGS and directory.suffix in PRODUCT_SUFFIXES:
            products[directory.name] = _read_regular(directory, app)
            continue
        if not directory.name.endswith(".lproj"):
            continue
        if directory.is_symlink() or not directory.is_dir():
            raise ValidationError(f"invalid app localization directory: {directory}")
        if directory.name not in {f"{x}.lproj" for x in LOCALES} | {"Base.lproj"}:
            raise ValidationError(f"unexpected app locale directory: {directory.name}")
        # Other app resources (for example Base storyboard products) have their
        # own owners. Every compiled product of these two tables is checked,
        # including products in unexpected locales.
        for path in sorted(directory.rglob("*")):
            if path.is_symlink():
                raise ValidationError(f"symlink inside app localization directory: {path}")
            if path.stem in CATALOGS and path.suffix in PRODUCT_SUFFIXES:
                products[path.relative_to(app).as_posix()] = _read_regular(path, app)
    return products


def _decode_plist(data: bytes, scratch: Path, label: str) -> dict[str, Any]:
    try:
        value = plistlib.loads(data)
    except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError):
        # Foundation also accepts OpenStep/UTF-16 .strings files, which Python's
        # plist reader does not. Parse a snapshot, never the mutable app path.
        scratch.write_bytes(data)
        converted = _run(["/usr/bin/plutil", "-convert", "binary1", "-o", "-", "--", str(scratch)])
        try:
            value = plistlib.loads(converted)
        except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError) as exc:
            raise ValidationError(f"cannot decode localization property list: {label}") from exc
    if not isinstance(value, dict) or any(not isinstance(key, str) for key in value):
        raise ValidationError(f"localization product is not a string-keyed dictionary: {label}")
    return value


def _same_value(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(_same_value(value, right[key]) for key, value in left.items())
    if isinstance(left, list):
        return len(left) == len(right) and all(_same_value(a, b) for a, b in zip(left, right))
    return left == right


def validate_localizations(repo: Path, app: Path) -> dict[str, Any]:
    for label, root in (("repository", repo), ("app", app)):
        if not root.is_absolute() or root.is_symlink() or not root.is_dir():
            raise ValidationError(f"{label} must be an absolute existing nonsymlink directory: {root}")
    repo, app = repo.resolve(), app.resolve()
    compiler = Path(_run(["/usr/bin/xcrun", "--find", "xcstringstool"]).decode().strip())
    if not compiler.is_absolute() or not compiler.is_file():
        raise ValidationError("xcstringstool did not resolve to an existing compiler")
    report: dict[str, Any] = {"compiler": str(compiler), "compiler_sha256": _digest(compiler.read_bytes()),
                              "sources": [], "products": [], "errors": []}
    originals: dict[Path, bytes] = {}
    for table in CATALOGS:
        relative = RESOURCE_ROOT / f"{table}.xcstrings"
        data = _read_regular(repo / relative, repo)
        _check_catalog(data, relative.as_posix())
        originals[relative] = data
        report["sources"].append({"path": relative.as_posix(), "sha256": _digest(data)})
    with tempfile.TemporaryDirectory(prefix="setos-localization-validation-") as temporary:
        work = Path(temporary)
        expected: dict[str, bytes] = {}
        for relative, data in originals.items():
            snapshot = work / relative.name
            snapshot.write_bytes(data)
            output = work / relative.stem
            _compile_catalog(compiler, snapshot, output)
            expected.update(_compiled_products(output, relative.stem))
        actual = _app_products(app)
        for name in sorted(expected.keys() - actual.keys()):
            report["errors"].append(f"missing localization product: {name}")
        for name in sorted(actual.keys() - expected.keys()):
            report["errors"].append(f"unexpected localization product: {name}")
        nonempty_locales: set[tuple[str, str]] = set()
        for index, name in enumerate(sorted(expected)):
            wanted = _decode_plist(expected[name], work / f"expected-{index}.plist", name)
            if wanted:
                nonempty_locales.add((Path(name).stem, Path(name).parts[0]))
            if name not in actual:
                continue
            found = _decode_plist(actual[name], work / f"actual-{index}.plist", name)
            row = {"path": name, "expected_sha256": _digest(expected[name]), "actual_sha256": _digest(actual[name]),
                   "expected_keys": len(wanted), "actual_keys": len(found),
                   "missing_keys": sorted(wanted.keys() - found.keys()),
                   "extra_keys": sorted(found.keys() - wanted.keys()),
                   "changed_values": sorted(key for key in wanted.keys() & found.keys() if not _same_value(wanted[key], found[key]))}
            report["products"].append(row)
            if row["missing_keys"] or row["extra_keys"] or row["changed_values"]:
                report["errors"].append(f"{name}: missing_keys={len(row['missing_keys'])} "
                                        f"extra_keys={len(row['extra_keys'])} changed_values={len(row['changed_values'])}")
        for table in CATALOGS:
            for locale in sorted(LOCALES):
                if (table, f"{locale}.lproj") not in nonempty_locales:
                    raise ValidationError(f"{table}: compiler produced empty {locale} localization dictionaries")
        for relative, data in originals.items():
            if _read_regular(repo / relative, repo) != data:
                raise ValidationError(f"source catalog changed during validation: {relative}")
        if _app_products(app) != actual:
            raise ValidationError("app localization products changed during validation")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        report = validate_localizations(args.repo_root, args.app)
    except (ValidationError, OSError) as exc:
        print(f"FAIL LOCALIZATION: {exc}", file=sys.stderr)
        return 1
    print(f"LOCALIZATION_COMPILER: path={report['compiler']} sha256={report['compiler_sha256']}")
    for row in report["sources"]:
        print(f"LOCALIZATION_SOURCE: path={row['path']} sha256={row['sha256']}")
    for message in report["errors"]:
        print(f"FAIL LOCALIZATION: {message}", file=sys.stderr)
    if report["errors"]:
        return 1
    print(f"PASS localization source/bundle equality: catalogs=2 locales=en,ru products={len(report['products'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
