#!/usr/bin/env python3
"""M11-003: copy key inventory — every key has EN+RU values; fixture/debug
keys are tagged and confined to Previews/Tests/DEBUG seams."""
import json, re, sys
from pathlib import Path
d = json.load(open('shafinMultitool/Resources/Localizable.xcstrings'))
strings = d['strings']
bad_values, untagged_use = [], []
for key, entry in strings.items():
    locs = entry.get('localizations', {})
    for lang in ('en', 'ru'):
        if not locs.get(lang, {}).get('stringUnit', {}).get('value'):
            bad_values.append(f"{key} missing {lang}")
fixture_keys = {k for k in strings if any(t in k for t in ('fixture', '.debug.', 'mock'))}
prod_files = [p for p in Path('shafinMultitool').rglob('*.swift')
              if 'Tests' not in str(p) and 'Preview' not in p.name and 'Fixture' not in str(p)]
for path in prod_files:
    text = path.read_text(errors='ignore')
    for key in fixture_keys:
        camel = 'fixture' + ''.join(w.capitalize() for w in key.split('.')[1].split('_'))
        if re.search(rf'\b{camel}\b', text) and '#if DEBUG' not in text[max(0, text.find(camel)-500):text.find(camel)]:
            untagged_use.append(f"{path}:{key}")
print(f"COPY INVENTORY: {len(strings)} keys, {len(fixture_keys)} fixture-tagged")
if not strings:
    print("COPY INVENTORY FAIL: the string table has 0 keys — nothing was checked")
    sys.exit(1)
if not prod_files:
    print("COPY INVENTORY FAIL: 0 production Swift files were scanned, so the fixture-usage "
          "check examined nothing")
    sys.exit(1)
if bad_values:
    print(f"FAIL values: {bad_values[:5]}")
    sys.exit(1)
if untagged_use:
    print(f"FAIL untagged fixture use: {untagged_use[:5]}")
    sys.exit(1)
print("COPY INVENTORY OK")
