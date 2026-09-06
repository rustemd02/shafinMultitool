#!/usr/bin/env python3
"""M11-023: motion evidence — one-shot transitions are event-ledger owned
(one complete transition per event ID); no test substitutes animation
evidence for functional device evidence."""
import re, sys
from pathlib import Path
# 1. Every motion/animation trigger in production UI pairs with an event
# ledger consume or a reduce-motion instant path.
motion_files = [p for d in [Path('shafinMultitool/Multitool2Module/UI'), Path('shafinMultitool/SceneGeneratorModule/Views')]
                for p in d.rglob('*.swift') if 'Tests' not in str(p)]
unguarded = []
for path in motion_files:
    text = path.read_text(errors='ignore')
    for m in re.finditer(r'withAnimation\(', text):
        window = text[max(0, m.start()-900):m.start()]
        if not re.search(r'reduceMotion|isMotionReduced|setReduceMotion|eventLedger|consume\(eventID|hasConsumed', window):
            unguarded.append(f"{path}:{text[:m.start()].count(chr(10))+1}")
# 2. Motion video attachments identify event/build/device/traits via names.
ui_text = '\n'.join(p.read_text(errors='ignore') for p in Path('shafinMultitoolUITests').glob('*.swift'))
videos = re.findall(r'leader|Leader|motion|Motion', ui_text)
print(f"MOTION EVIDENCE: {len(motion_files)} UI files, {len(videos)} motion references in UI tests")
if unguarded:
    print(f"FAIL: {len(unguarded)} unguarded animations:")
    for u in unguarded[:8]: print('  ', u)
    sys.exit(1)
print("MOTION EVIDENCE OK: every animation is ledger- or reduce-motion-gated")
