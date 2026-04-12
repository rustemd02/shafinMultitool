#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cir_contract.contracts.cir_validator import CIRValidationError, load_schema, validate_file


def _default_example_paths() -> list[Path]:
    examples_dir = ROOT / "cir_contract" / "contracts" / "examples"
    return sorted(examples_dir.glob("*.json"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate SG v7 CIR contract examples/files.")
    parser.add_argument("paths", nargs="*", type=Path, help="Files to validate. Defaults to bundled examples.")
    args = parser.parse_args()

    schema = load_schema()
    paths = args.paths or _default_example_paths()
    if not paths:
        print("No CIR files provided and no default examples found.", file=sys.stderr)
        return 2

    failures = 0
    for path in paths:
        try:
            validate_file(path, schema=schema)
            print(f"OK: {path}")
        except (OSError, CIRValidationError, ValueError) as exc:
            failures += 1
            print(f"FAIL: {path}: {exc}", file=sys.stderr)

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
