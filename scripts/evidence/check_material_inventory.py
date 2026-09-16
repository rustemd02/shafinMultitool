#!/usr/bin/env python3
"""M0-007: verify every material artifact has path/size/hash/targets/consumer/disposition."""
import json, sys
from pathlib import Path
REQUIRED = {'path', 'bytes', 'sha256', 'configurations', 'targets', 'consumer', 'disposition'}
rows = [json.loads(l) for l in Path('docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m0/material-inventory-v2.jsonl').read_text().splitlines() if l.strip()]
bad = [r.get('path', '?') for r in rows if set(r) < REQUIRED or r['bytes'] < 0 or len(r['sha256']) != 64]
if not REQUIRED:
    print("MATERIAL INVENTORY FAIL: no required-field set is declared, so every row would pass")
    sys.exit(1)
if not rows:
    print("MATERIAL INVENTORY FAIL: the inventory has 0 rows — an empty scan is not 'all fields present'")
    sys.exit(1)
if bad:
    print(f"MATERIAL INVENTORY FAIL: {len(bad)} invalid rows, e.g. {bad[:3]}")
    sys.exit(1)
print(f"MATERIAL INVENTORY OK: {len(rows)} rows, all fields present")
