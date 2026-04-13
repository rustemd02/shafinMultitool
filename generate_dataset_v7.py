#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
DOCS_ROOT = ROOT / "docs" / "SGv7pipeline"
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from cir_contract.contracts import serialize_to_scenescript, validate_record


def _load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def build_scene_script(cir_record: dict, *, original_description: str) -> dict:
    validate_record(cir_record)
    return serialize_to_scenescript(cir_record, original_description=original_description)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Canonical SG v7 entrypoint: validate a CIR record and project it to SceneScript JSON."
    )
    parser.add_argument("--cir", type=Path, required=True, help="Path to a CIR JSON file.")
    parser.add_argument(
        "--original-description",
        required=True,
        help="Source text that should populate SceneScript.originalDescription.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional output path. Defaults to stdout.",
    )
    args = parser.parse_args()

    record = _load_json(args.cir)
    scene_script = build_scene_script(record, original_description=args.original_description)
    serialized = json.dumps(scene_script, ensure_ascii=False, indent=2) + "\n"

    if args.output:
        args.output.write_text(serialized, encoding="utf-8")
    else:
        sys.stdout.write(serialized)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
