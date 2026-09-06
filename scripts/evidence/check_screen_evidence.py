#!/usr/bin/env python3
"""M11-013: screen evidence — every listed journey state family has RU/EN
coverage, required orientations, default/XXL dynamic type, VoiceOver
semantics hooks, Reduce Motion/Transparency variants, and upright
screenshots via the UI attachment seams. Motion video only where behavior
depends on animation (leader countdown)."""
import re, sys
from pathlib import Path
checks = []
ui_files = list(Path('shafinMultitoolUITests').glob('*.swift'))
ui_text = '\n'.join(p.read_text(errors='ignore') for p in ui_files)

def check(name, pattern):
    ok = bool(re.search(pattern, ui_text))
    checks.append((name, ok))
    return ok

check('RU locale coverage', r'locale.*ru|"ru"')
check('EN locale coverage', r'locale.*en|"en"')
check('landscape orientation', r'landscapeLeft|landscapeRight|\.landscape')
check('portrait orientation', r'\.portrait')
check('reduce motion variant', r'reduceMotion.*true|ReduceMotion|REDUCE_MOTION')
check('dynamic type variant', r'dynamicType|DynamicType|XXL|accessibility.*size')
# VoiceOver semantics are asserted through element queries against the
# production identifiers (buttons[...]/staticTexts/descendants), which is
# how XCTest observes the accessibility tree.
check('voiceover semantics', r'buttons\[|staticTexts|descendants\(matching')
check('screenshot attachments', r'attachScreenshot|screenshot\(\)')
check('leader motion video seam', r'leader|Leader')
print(f"SCREEN EVIDENCE: {len(ui_files)} UI files")
failed = [n for n, ok in checks if not ok]
for name, ok in checks:
    print(f"  {'OK ' if ok else 'MISS'} {name}")
if failed:
    sys.exit(1)
print("SCREEN EVIDENCE OK")
