"""Every `SETCopyKey` must exist in the string catalog, in both locales.

The production lookup passes the key itself as its fallback value:

    resolvedBundle(for: locale).localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)

so a key that is absent from the catalog is rendered to the user **as the raw key**
(for example `set.camera.eco`). That fallback is currently unreachable only because
every declared key happens to be present; nothing enforced it. Adding one enum case
without a catalog entry, or editing a raw value, would make it visible immediately.

This test closes that: the enum and the catalog are compared, so drift fails here
instead of on a user's screen.

Related, not covered by this test (see the audit entry in EXECUTION_STATE): several
production surfaces render raw technical text directly — technical actor/action/beat
IDs in the scene hint panel, a raw enum case value as an accessibility value, and
`String(describing:)` of a motion state in the decision-trace sheet. Those are
literal `Text(...)`/interpolation sites, not catalog lookups, so a catalog test
cannot see them.

Run: python3 -m pytest tools/tests/test_localization_catalog_coverage.py -q
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
LOCALIZATION_SWIFT = REPO_ROOT / "shafinMultitool/Multitool2Module/UI/DesignSystem/SETLocalization.swift"
CATALOG = REPO_ROOT / "shafinMultitool/Resources/Localizable.xcstrings"

CASE_WITH_VALUE = re.compile(r'^\s*case\s+([A-Za-z0-9_]+)\s*=\s*"([^"]*)"', re.M)
CASE_WITHOUT_VALUE = re.compile(r"^\s*case\s+([A-Za-z0-9_]+)\s*$", re.M)
ENUM_HEADER = re.compile(r"^enum SETCopyKey\b.*\{\s*$", re.M)


def copy_keys() -> dict[str, str]:
    """Map case name -> raw value for SETCopyKey only, resolving implicit raw values.

    The file declares more than one enum (a language enum with `= "en"` / `= "ru"`
    cases sits in it too), so the body is delimited rather than the whole file
    scanned — scanning everything is how the first version of this test reported
    two phantom missing keys.
    """
    source = LOCALIZATION_SWIFT.read_text(encoding="utf-8")
    header = ENUM_HEADER.search(source)
    assert header, "SETCopyKey enum header not found — the parser is stale"
    body_lines: list[str] = []
    for line in source[header.end():].splitlines():
        if line.startswith("}"):
            break
        body_lines.append(line)
    body = "\n".join(body_lines)
    keys = {name: value for name, value in CASE_WITH_VALUE.findall(body)}
    for name in CASE_WITHOUT_VALUE.findall(body):
        keys.setdefault(name, name)
    return keys


def catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def value_for(entry: dict, language: str) -> str | None:
    return entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value")


def test_the_enum_was_actually_parsed():
    """A parser that finds nothing would make the coverage check vacuous."""
    keys = copy_keys()
    assert len(keys) >= 100, f"only {len(keys)} copy keys parsed — the parser is stale"


def test_every_declared_copy_key_is_in_the_catalog():
    strings = catalog()["strings"]
    missing = sorted(value for value in copy_keys().values() if value not in strings)
    assert missing == [], (
        f"{len(missing)} copy key(s) are absent from Localizable.xcstrings; the lookup falls "
        f"back to the raw key, so these would be shown literally to the user: {missing[:10]}")


@pytest.mark.parametrize("language", ["en", "ru"])
def test_every_catalog_entry_for_a_declared_key_has_that_language(language: str):
    strings = catalog()["strings"]
    empty = sorted(value for value in copy_keys().values()
                   if value in strings and not (value_for(strings[value], language) or "").strip())
    assert empty == [], f"{len(empty)} declared key(s) have no usable {language} text: {empty[:10]}"


def test_the_catalog_carries_no_empty_values():
    """An empty string is not a translation; the UI would show a blank control."""
    strings = catalog()["strings"]
    empty = sorted(key for key, entry in strings.items()
                   if not ((value_for(entry, "en") or "").strip() and (value_for(entry, "ru") or "").strip()))
    assert empty == [], f"{len(empty)} catalog entries lack usable en+ru text: {empty[:10]}"
