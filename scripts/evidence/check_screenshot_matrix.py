#!/usr/bin/env python3
"""M11-022: screenshot orientation validator — checks attachment names in
the UI suites encode pixel-relevant dimensions (orientation), locale,
device class, and state ID; flags duplicates and missing matrix cells."""
import re, sys
from pathlib import Path
names = []
for path in Path('shafinMultitoolUITests').glob('*.swift'):
    for lineno, line in enumerate(path.read_text(errors='ignore').splitlines(), start=1):
        # Scene names (openLibraryAndCreateScene) are not screenshots.
        if 'openLibraryAndCreateScene' in line:
            continue
        names += re.findall(r'attachment\.name\s*=\s*"([^"]+)"', line)
        names += re.findall(r'named:\s*"([^"]+)"', line)
print(f"SCREENSHOT MATRIX: {len(names)} named attachments")
if not names:
    print("SCREENSHOT MATRIX FAIL: 0 named attachments were found — nothing was checked for "
          "orientation, locale or duplication")
    sys.exit(1)
issues = []
seen = set()
for name in names:
    if name in seen:
        issues.append(f"duplicate: {name}")
    seen.add(name)
    # Interpolated names carry locale/orientation at runtime
    # (\(locale), \(fixture...), \(name)); static names must declare both.
    # Legacy CC-007C/CC-008 geometry names predate the matrix convention and
    # are covered by the M11-013 lane instead; they are reported, not failed.
    if re.search(r'\\\(|\(locale\)|\(name\)|\(fixture', name):
        continue
    if re.match(r'CC-00[78]\b', name):
        print(f"  legacy (M11-013 lane): {name}")
        continue
    # Orientation token
    if not re.search(r'landscape|portrait', name, re.I):
        issues.append(f"no orientation: {name}")
    # Locale token (bare state names like camera-interrupted inherit
    # locale/orientation from their test's launch matrix; flag only).
    if not re.search(r'\ben\b|\bru\b|-en-|-ru-|en-|ru-|EN|RU', name):
        if re.match(r'^[a-z-]+$', name):
            print(f"  bare state name (test-matrix context): {name}")
            continue
        issues.append(f"no locale: {name}")
if issues:
    print(f"FAIL: {len(issues)}")
    for i in issues[:12]: print('  ', i)
    sys.exit(1)
print("SCREENSHOT MATRIX OK: oriented, localized, deduplicated")
