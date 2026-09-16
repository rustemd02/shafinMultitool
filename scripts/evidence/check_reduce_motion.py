#!/usr/bin/env python3
"""M11-011: every withAnimation site on the production surface pairs with a
reduce-motion branch (instant/crossfade) or is itself the crossfade."""
import re, sys
from pathlib import Path
SCOPE = [Path('shafinMultitool/Multitool2Module/UI'), Path('shafinMultitool/SceneGeneratorModule/Views'),
         Path('shafinMultitool/ScenesOverviewModule'), Path('shafinMultitool/CommercialShell')]
OUT = ('Benchmark', 'Debug', 'Tests', 'Preview', 'Fixture')
violations = []
count = 0
for d in SCOPE:
    for p in d.rglob('*.swift'):
        if any(s in str(p) for s in OUT): continue
        text = p.read_text(errors='ignore')
        for m in re.finditer(r'withAnimation\(', text):
            count += 1
            window = text[max(0, m.start()-600):m.start()]
            # A guard counts if reduceMotion/isMotionReduced/setReduceMotion or
            # the crossfade constant appears in the enclosing 600 chars.
            if not re.search(r'reduceMotion|isMotionReduced|setReduceMotion|reducedMotionCrossfade|markerDrawDuration|tallyPulseDuration', window):
                violations.append(f"{p}:{text[:m.start()].count(chr(10))+1}")
print(f"REDUCE MOTION: {count} withAnimation sites scanned")
if count == 0:
    print("REDUCE MOTION FAIL: 0 withAnimation sites were scanned — a scan that found nothing "
          "is not a scan that found no problems")
    sys.exit(1)
if violations:
    print(f"FAIL: {len(violations)} unguarded:")
    for v in violations[:10]: print('  ', v)
    sys.exit(1)
print("REDUCE MOTION OK")
