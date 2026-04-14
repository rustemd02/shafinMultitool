#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from training import PhaseViewBuildError, PhaseViewRequest, build_phase_view, default_phase_config


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Track 8 phase view artifacts from SG v7 dataset splits.")
    parser.add_argument("--phase", required=True, help="phase1|phase2|phase3|phase4")
    parser.add_argument("--sft-train-jsonl", type=Path, required=True)
    parser.add_argument("--split-manifest-json", type=Path)
    parser.add_argument("--preference-train-jsonl", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--phase-config-json", type=Path, help="Optional JSON override for phase config.")
    return parser.parse_args()


def _load_phase_config(phase: str, path: Path | None):
    config = default_phase_config(phase)
    if path is None:
        return config
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise PhaseViewBuildError(f"phase_config_json must be an object: {path}")
    # Minimal override support for common knobs.
    return config.__class__(**{**config.__dict__, **payload})


def main() -> int:
    args = _parse_args()
    try:
        phase_config = _load_phase_config(args.phase, args.phase_config_json)
        result = build_phase_view(
            PhaseViewRequest(
                phase=args.phase,
                sft_train_jsonl=args.sft_train_jsonl,
                split_manifest_json=args.split_manifest_json,
                preference_train_jsonl=args.preference_train_jsonl,
                output_dir=args.output_dir,
                seed=args.seed,
                phase_config=phase_config,
            )
        )
    except (PhaseViewBuildError, ValueError) as exc:
        sys.stderr.write(f"Phase view build failed: {exc}\n")
        return 2

    sys.stdout.write(
        f"Built {result['phase']} view: selected={result['counts']['selected_records']} output={result['output_artifacts']['phase_train_jsonl']}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

