#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from validators import ValidationRequest, run_semantic_critic


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run SG v7 semantic critic for a single candidate JSON.")
    parser.add_argument("--input-json", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--critic-backend", choices=["heuristic", "openai"], default="heuristic")
    parser.add_argument("--model-name", default="gpt-5.4-nano")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    sample = json.loads(args.input_json.read_text(encoding="utf-8"))
    cir_record = sample.get("cir_record")
    if not isinstance(cir_record, dict):
        raise SystemExit("--input-json must contain embedded cir_record for 03_semantic_critic.py")
    request = ValidationRequest(
        input_jsonl=args.input_json,
        cir_jsonl=None,
        accepted_jsonl=args.output_json,
        review_jsonl=args.output_json,
        rejected_jsonl=args.output_json,
        manifest_json=args.output_json,
        seed=0,
        critic_model=args.model_name,
        critic_backend=args.critic_backend,
    )
    result = run_semantic_critic(sample, request, cir_record=cir_record)
    payload = {
        "artifact_id": result.artifact_id,
        "execution": result.execution,
        "verdict": result.verdict,
        "confidence": result.confidence,
        "findings": list(result.findings),
        "detected_failures": list(result.detected_failures),
        "chronology_preserved": result.chronology_preserved,
        "object_grounding_preserved": result.object_grounding_preserved,
        "ordinal_binding_preserved": result.ordinal_binding_preserved,
        "unsupported_action_preserved": result.unsupported_action_preserved,
        "invented_content_present": result.invented_content_present,
        "summary": result.summary,
    }
    args.output_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    sys.stdout.write(f"Wrote critic artifact -> {args.output_json}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
