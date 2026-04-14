#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from training import ExperimentRegistryError, ExperimentRegistryRequest, register_experiment


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Register reproducible Track 8 experiment notes.")
    parser.add_argument("--experiment-id", required=True)
    parser.add_argument("--phase", required=True, help="phase1|phase2|phase3|phase4")
    parser.add_argument("--config-path", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--input-artifact", type=Path, action="append", default=[])
    parser.add_argument("--notes", default="")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        result = register_experiment(
            ExperimentRegistryRequest(
                experiment_id=args.experiment_id,
                phase=args.phase,
                config_path=args.config_path,
                output_dir=args.output_dir,
                input_artifacts=list(args.input_artifact),
                notes=args.notes,
            )
        )
    except ExperimentRegistryError as exc:
        sys.stderr.write(f"Experiment registration failed: {exc}\n")
        return 2

    sys.stdout.write(
        f"Registered experiment {result['experiment_id']} for {result['phase']} at {args.output_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

