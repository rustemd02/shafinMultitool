from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from graph_generator import GraphBuildRequest, derive_graph_seed, plan_graph_records, plan_pattern_quotas


class TestGraphGeneratorPlanner(unittest.TestCase):
    def _request(self, **overrides) -> GraphBuildRequest:
        tmpdir = Path(tempfile.gettempdir())
        payload = {
            "seed": 20260413,
            "difficulty_bucket": "core",
            "total_records": 12,
            "pattern_names": None,
            "include_variants": None,
            "output_jsonl": tmpdir / "planner_graphs.jsonl",
            "output_manifest": tmpdir / "planner_graphs.manifest.json",
            "refill_budget": 3,
            "fail_on_duplicates": False,
        }
        payload.update(overrides)
        return GraphBuildRequest(**payload)

    def test_plan_is_stable_for_identical_request(self) -> None:
        request = self._request()
        left = plan_graph_records(request)
        right = plan_graph_records(request)
        self.assertEqual(left, right)

    def test_core_and_hard_plan_independently(self) -> None:
        core_request = self._request(difficulty_bucket="core", total_records=6)
        hard_request = self._request(difficulty_bucket="hard", total_records=6)
        core = plan_graph_records(core_request)
        hard = plan_graph_records(hard_request)
        self.assertTrue(all(item.difficulty_bucket == "core" for item in core))
        self.assertTrue(all(item.difficulty_bucket == "hard" for item in hard))
        self.assertNotEqual([item.graph_seed for item in core], [item.graph_seed for item in hard])

    def test_repeated_quota_seed_derivation_is_stable(self) -> None:
        request = self._request()
        seed_a = derive_graph_seed(
            request,
            difficulty_bucket="core",
            pattern_name="dialogue_only",
            source_variant_key="base",
            ordinal=5,
            attempt_index=0,
        )
        seed_b = derive_graph_seed(
            request,
            difficulty_bucket="core",
            pattern_name="dialogue_only",
            source_variant_key="base",
            ordinal=5,
            attempt_index=0,
        )
        self.assertEqual(seed_a, seed_b)

    def test_refill_attempt_changes_seed(self) -> None:
        request = self._request()
        original = derive_graph_seed(
            request,
            difficulty_bucket="core",
            pattern_name="dialogue_only",
            source_variant_key="base",
            ordinal=1,
            attempt_index=0,
        )
        refill = derive_graph_seed(
            request,
            difficulty_bucket="core",
            pattern_name="dialogue_only",
            source_variant_key="base",
            ordinal=1,
            attempt_index=1,
        )
        self.assertNotEqual(original, refill)

    def test_pattern_quota_total_matches_request(self) -> None:
        request = self._request(total_records=25)
        quotas = plan_pattern_quotas(request)
        self.assertEqual(sum(quota.count for quota in quotas), 25)

