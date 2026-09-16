#!/usr/bin/env python3
"""M11-006: localization validation — missing locale, placeholder mismatch,
unsupported glyph, and raw technical error fail the check; all production
keys must pass."""
import json, re, sys
d = json.load(open('shafinMultitool/Resources/Localizable.xcstrings'))
strings = d['strings']
failures = []
for key, entry in strings.items():
    locs = entry.get('localizations', {})
    for lang in ('en', 'ru'):
        value = locs.get(lang, {}).get('stringUnit', {}).get('value')
        if not value:
            failures.append(f"{key}: missing {lang}")
            continue
        # Placeholder mismatch: %@/%d/format args must agree across locales
        if lang == 'ru':
            en = locs.get('en', {}).get('stringUnit', {}).get('value', '')
            en_args = sorted(re.findall(r'%[@d]|{[^}]*}', en))
            ru_args = sorted(re.findall(r'%[@d]|{[^}]*}', value))
            if en_args != ru_args:
                failures.append(f"{key}: placeholder mismatch en={en_args} ru={ru_args}")
        # Raw technical error: camelCase identifiers or %p/%x leaks
        if re.search(r'%[px]|0x[0-9a-fA-F]{4,}|nil\b.*Optional|\(null\)', value):
            failures.append(f"{key}: raw technical error text")
        # Unsupported glyph: control characters
        if re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', value):
            failures.append(f"{key}: control character")
print(f"LOCALIZATION: {len(strings)} keys checked")
if not strings:
    print("LOCALIZATION FAIL: the string table has 0 keys — nothing was validated")
    sys.exit(1)
if failures:
    print(f"FAIL: {len(failures)}")
    for f in failures[:10]: print('  ', f)
    sys.exit(1)
print("LOCALIZATION OK")
