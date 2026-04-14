#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from training import CheckpointCompareError, CheckpointCompareRequest, compare_checkpoints


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare Track 8 checkpoints and materialize promotion artifacts.")
    parser.add_argument("--phase", required=True, help="phase1|phase2|phase3|phase4")
    parser.add_argument("--checkpoints-jsonl", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--reference-checkpoint-id")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        result = compare_checkpoints(
            CheckpointCompareRequest(
                phase=args.phase,
                checkpoints_jsonl=args.checkpoints_jsonl,
                output_dir=args.output_dir,
                seed=args.seed,
                reference_checkpoint_id=args.reference_checkpoint_id,
            )
        )
    except CheckpointCompareError as exc:
        sys.stderr.write(f"Checkpoint compare failed: {exc}\n")
        return 2

    sys.stdout.write(
        f"Compared checkpoints for {result['phase']}: winner={result['winner_checkpoint_id']} output={args.output_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

