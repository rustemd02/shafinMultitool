from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from source_generation.batcher import build_variant_plan
from source_generation.config import SourceGenerationRequest
from source_generation.filters import evaluate_candidate_text


class TestFilters(unittest.TestCase):
    def test_missing_disambiguation_cue_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex3_same_type_two_marked_objects.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        clean_item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text(
            "Первый подходит к стулу, второй стоит рядом.",
            clean_item,
            existing_keys=set(),
        )
        self.assertIn("missing_required_disambiguation_cue", reasons)

    def test_json_like_output_is_rejected(self) -> None:
        fixture = DOCS_ROOT / "cir_contract" / "contracts" / "examples" / "ex1_stop_near_marked_then_first_described.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            input_jsonl = tmp_path / "input.jsonl"
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            input_jsonl.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
            request = SourceGenerationRequest(
                input_jsonl=input_jsonl,
                output_jsonl=tmp_path / "out.jsonl",
                reject_log_jsonl=tmp_path / "rejects.jsonl",
                seed=1,
                paraphraser_backend="heuristic",
            )
            plan = build_variant_plan(request)

        item = next(item for item in plan if item.style_bucket == "clean")
        reasons = evaluate_candidate_text('{"scene":"bad"}', item, existing_keys=set())
        self.assertIn("json_like_output", reasons)
