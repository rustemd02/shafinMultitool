from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from source_generation.config import SourceGenerationRequest
from source_generation.batcher import build_variant_plan


class TestPromptBuilder(unittest.TestCase):
    def test_same_type_markers_produce_disambiguation_block(self) -> None:
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
        block = clean_item.prompt_payload["same_type_disambiguation_block"]
        self.assertIsNotNone(block)
        self.assertTrue(clean_item.required_disambiguation_cues)
        self.assertIn("прав", " ".join(clean_item.required_disambiguation_cues))
