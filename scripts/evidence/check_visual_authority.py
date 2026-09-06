#!/usr/bin/env python3
"""M11-001: visual-authority checklist — fail-closed grep audit.

Scope: the SET OS production surface (Multitool2Module UI, SceneGenerator
views, CommercialShell, DesignSystem). Out of scope by tracker authority:
legacy SceneModules/CameraScreen/EditScript/History screens, Benchmark and
Debug/Performance overlays, Tests/Previews/fixtures, DEBUG-only seams.
Banned tokens use word-boundary or API-exact patterns to avoid component
false positives (e.g. a `blue:` color channel is not system blue).
"""
import re, sys
from pathlib import Path

IN_SCOPE = ('shafinMultitool/Multitool2Module/UI', 'shafinMultitool/Multitool2Module/Shell',
            'shafinMultitool/SceneGeneratorModule/Views', 'shafinMultitool/CommercialShell')
OUT_OF_SCOPE = ('Benchmark', 'Debug', 'Performance', 'History', 'SceneModules',
                'CameraScreenModule', 'EditScript', 'StageSelection')
PROD = [p for p in Path('shafinMultitool').rglob('*.swift')
        if str(p).startswith(IN_SCOPE)
        and not any(s in str(p) for s in OUT_OF_SCOPE)
        and 'Tests' not in str(p) and 'Preview' not in p.name
        and 'Fixture' not in str(p)]
BANNED = [
    (r'\.blur\(radius', 'blur modifier'),
    (r'UIVisualEffectView|UIBlurEffect', 'visual effect view'),
    (r'\.shadow\(color:\s*\.black', 'black drop shadow'),
    (r'LinearGradient|RadialGradient|AngularGradient', 'gradient'),
    (r'Color\.blue\b|\.systemBlue|UIColor\.systemBlue', 'system blue'),
    (r'repeatForever', 'per-frame decorative loop'),
]
REQUIRED = [
    ('setOrange', 'single cinematic accent'),
    ('setTextPrimary', 'ink text'),
    ('warmWhite|WarmWhite', 'warm white'),
]
violations, missing = [], []
for path in PROD:
    text = path.read_text(errors='ignore')
    for pattern, name in BANNED:
        for m in re.finditer(pattern, text):
            line = text[:m.start()].count('\n') + 1
            violations.append(f"{path}:{line}: {name}")
all_text = '\n'.join(p.read_text(errors='ignore') for p in PROD)
for token, name in REQUIRED:
    if not re.search(token, all_text):
        missing.append(name)
print(f"VISUAL AUTHORITY: {len(PROD)} SET OS production files scanned")
if violations:
    print(f"FAIL: {len(violations)} banned-pattern hits:")
    for v in violations[:15]: print('  ', v)
    sys.exit(1)
if missing:
    print(f"FAIL: missing required tokens: {missing}")
    sys.exit(1)
print("VISUAL AUTHORITY OK: no banned patterns, required tokens present")
