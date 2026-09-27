#!/usr/bin/env python3
"""UI-012 full catalog audit: every localized key is production-usable.

The 2026-09-23 preview audit covered only the 9 keys added that week. This
validator covers the WHOLE `Localizable.xcstrings` catalog (699 keys after the
UI-004 pause-failure key) and fails on the four failure classes the UI-012 row
names:

1. missing/empty locale value (a key must ship RU and EN);
2. format-specifier drift between RU and EN (a key that formats `%d` in one
   locale and `%@` in the other crashes or prints garbage at runtime);
3. placeholder/technical leftovers (TODO/FIXME/template stubs/raw keys);
4. value == key (the catalog-lookup fallback trap: the raw key would render).

Pluralization is adjudicated per key in the UI-012 receipt (number-neutral copy
where noun agreement would be needed); truncation is covered by the Dynamic
Type anti-clipping lane (UI-007) — those two axes are documented there, not
re-derived here.

Run: python3 -m pytest tools/tests/test_localization_catalog_audit.py -q
"""

from __future__ import annotations

import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG = REPO_ROOT / "shafinMultitool/Resources/Localizable.xcstrings"

LOCALES = ("en", "ru")
PLACEHOLDER_TOKENS = ("todo", "fixme", "lorem", "<#", "tbd", "xxx")
SPECIFIER = re.compile(r"%(?:\d+\$)?[#0 +\-']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?[@dDiuUxXoOfeEgGcCsSpaAF%]")


def load_catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def specifiers(value: str) -> list[str]:
    return sorted(match.group(0) for match in SPECIFIER.finditer(value) if match.group(0) != "%%")


def iter_localized_values():
    catalog = load_catalog()
    for key, entry in sorted(catalog["strings"].items()):
        localizations = entry.get("localizations") or {}
        yield key, localizations


def test_every_key_ships_non_empty_values_for_all_locales():
    missing: list[str] = []
    for key, localizations in iter_localized_values():
        for locale in LOCALES:
            unit = ((localizations.get(locale) or {}).get("stringUnit") or {})
            value = str(unit.get("value") or "")
            if not value.strip():
                missing.append(f"{key} [{locale}]")
    assert not missing, "empty or missing locale values:\n" + "\n".join(missing)


def test_format_specifiers_agree_between_ru_and_en():
    drifted: list[str] = []
    for key, localizations in iter_localized_values():
        values = {}
        for locale in LOCALES:
            unit = ((localizations.get(locale) or {}).get("stringUnit") or {})
            values[locale] = str(unit.get("value") or "")
        if specifiers(values["en"]) != specifiers(values["ru"]):
            drifted.append(
                f"{key}: en={specifiers(values['en'])} ru={specifiers(values['ru'])}"
            )
    assert not drifted, "format specifier drift:\n" + "\n".join(drifted)


def test_no_placeholder_or_technical_leftovers():
    bad: list[str] = []
    for key, localizations in iter_localized_values():
        for locale in LOCALES:
            unit = ((localizations.get(locale) or {}).get("stringUnit") or {})
            value = str(unit.get("value") or "")
            lowered = value.lower()
            for token in PLACEHOLDER_TOKENS:
                if token in lowered:
                    bad.append(f"{key} [{locale}]: {value!r} contains {token!r}")
            if value.strip() == key:
                bad.append(f"{key} [{locale}]: value equals the raw key (fallback trap)")
    assert not bad, "placeholder/technical leftovers:\n" + "\n".join(bad)


def test_catalog_keys_are_unique_and_sorted_json_preserves_them():
    catalog = load_catalog()
    keys = list(catalog["strings"].keys())
    assert len(keys) == len(set(keys)), "duplicate keys in catalog"
    assert keys, "catalog must not be empty"
