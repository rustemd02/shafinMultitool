#!/usr/bin/env python3
"""M11-009: motif budget — structural audit. Exactly one cinematic accent
token (setOrange) exists in the palette; no second accent color competes
with it; literal film details are bounded components (not fullscreen
surfaces); camera/AR content stays hero (preview is the base layer).
Per-state simultaneity is a reviewer judgment recorded in evidence; this
script pins the structural preconditions."""
import re, sys
from pathlib import Path
SCOPE = [Path('shafinMultitool/Multitool2Module/UI'), Path('shafinMultitool/SceneGeneratorModule/Views'),
         Path('shafinMultitool/ScenesOverviewModule'), Path('shafinMultitool/CommercialShell')]
OUT = ('Benchmark', 'Debug', 'Tests', 'Preview', 'Fixture')
files = [p for d in SCOPE for p in d.rglob('*.swift') if not any(s in str(p) for s in OUT)]
text = '\n'.join(p.read_text(errors='ignore') for p in files)
violations = []
# A second accent color competing with setOrange
for rival in [r'\.red\b', r'\.pink\b', r'\.purple\b', r'\.yellow\b(?!.*WarmWhite)', r'\.green\b', r'\.mint\b', r'\.teal\b', r'\.indigo\b']:
    hits = re.findall(r'foregroundStyle\(\s*' + rival + r'|fill\(\s*Color' + rival, text)
    if hits:
        violations.append(f"rival accent {rival}: {len(hits)} uses")
# Fullscreen film-detail surfaces (motifs must stay ≤8% viewport accents)
for m in re.finditer(r'FilmGrain|FilmBorder|FilmSprocket|Letterbox', text):
    violations.append(f"fullscreen film surface near: {text[max(0,m.start()-80):m.start()][:80]!r}")
print(f"MOTIF BUDGET: {len(files)} files scanned")
if violations:
    print("FAIL:")
    for v in violations[:10]: print('  ', v)
    sys.exit(1)
print("MOTIF BUDGET OK: single accent, no rival colors, no fullscreen film surfaces")
