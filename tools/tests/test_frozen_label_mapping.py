#!/usr/bin/env python3
"""D02a check: the v1 annotation vocabulary and the frozen neural axis stay in sync.

The v1 dataset schema annotates 21 domain issues; the frozen model contract has
8 issue heads.  ``datasets/camera-coach/v1/frozen-label-mapping.json`` records
how the two relate so an annotation maps losslessly to a training target and no
equivalence is invented.  This suite fails if the mapping drifts from either
side, if a v1 issue silently disappears, or if a frozen head loses its sources.

Run: python3 -m pytest tools/tests/test_frozen_label_mapping.py -q
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MAPPING_PATH = REPO_ROOT / "datasets/camera-coach/v1/frozen-label-mapping.json"
V1_SCHEMA_PATH = REPO_ROOT / "datasets/camera-coach/v1/label-schema.json"
CONTRACT_PATH = REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json"
sys.path.insert(0, str(REPO_ROOT / "tools/camera_annotation"))
import annotation_labels  # noqa: E402

KINDS = {"one_to_one", "aggregate", "no_frozen_issue"}
ROADMAP = {"behaviour_not_issue", "candidate_gap"}


def _v1_issues() -> list[str]:
    schema = json.loads(V1_SCHEMA_PATH.read_text(encoding="utf-8"))
    found: list[str] = []

    def walk(node) -> None:
        if isinstance(node, dict):
            if node.get("type") == "object" and isinstance(node.get("properties"), dict):
                issue_id = node["properties"].get("issue_id")
                if isinstance(issue_id, dict) and isinstance(issue_id.get("enum"), list):
                    found.extend(issue_id["enum"])
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(schema)
    if not found:
        raise AssertionError("label-schema.json: no issue_id enum found")
    return list(dict.fromkeys(found))


def _frozen_issues() -> list[str]:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    for head in contract["outputs"]["heads"]:
        if head.get("name") == "issue_logits":
            return list(head["ordered_names"])
    raise AssertionError("set_composition_net_v1.json: no issue_logits head")


class FrozenLabelMappingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mapping = json.loads(MAPPING_PATH.read_text(encoding="utf-8"))
        cls.entries = cls.mapping["v1_to_frozen"]
        cls.v1 = _v1_issues()
        cls.frozen = _frozen_issues()

    def test_v1_schema_still_has_21_domain_issues(self):
        self.assertEqual(len(self.v1), 21, f"v1 issue enum changed: {self.v1}")

    def test_frozen_axis_is_the_one_the_gui_writes(self):
        self.assertEqual(list(annotation_labels.ISSUES), self.frozen,
                         "the GUI writer's ISSUES must equal the frozen contract's issue_logits order")

    def test_every_v1_issue_is_mapped_exactly_once(self):
        mapped = [e["v1_issue"] for e in self.entries]
        self.assertEqual(len(mapped), len(set(mapped)), "a v1 issue is mapped twice")
        self.assertEqual(sorted(mapped), sorted(self.v1),
                         "the mapping and the v1 schema disagree on the issue set")

    def test_no_entry_names_an_unknown_frozen_issue(self):
        for e in self.entries:
            target = e.get("frozen_issue")
            if target is not None:
                self.assertIn(target, self.frozen, f"{e['v1_issue']} maps to an invented frozen id {target!r}")

    def test_every_frozen_issue_has_at_least_one_source(self):
        for issue in self.frozen:
            sources = [e["v1_issue"] for e in self.entries if e.get("frozen_issue") == issue]
            self.assertTrue(sources, f"frozen head {issue} has no v1 annotation source")

    def test_recorded_coverage_matches_recomputation(self):
        recorded = self.mapping["frozen_coverage"]
        self.assertEqual(sorted(recorded), sorted(self.frozen), "frozen_coverage covers a different head set")
        for issue in self.frozen:
            expected = sorted(e["v1_issue"] for e in self.entries if e.get("frozen_issue") == issue)
            self.assertEqual(sorted(recorded[issue]["v1_sources"]), expected, f"stale coverage for {issue}")
            self.assertEqual(recorded[issue]["covered"], bool(expected))

    def test_kinds_and_counts_are_honest(self):
        for e in self.entries:
            self.assertIn(e["kind"], KINDS, f"{e['v1_issue']}: unknown kind {e['kind']!r}")
        counted = {k: sum(1 for e in self.entries if e["kind"] == k) for k in KINDS}
        self.assertEqual(self.mapping["counts"]["one_to_one"], counted["one_to_one"])
        self.assertEqual(self.mapping["counts"]["aggregate"], counted["aggregate"])
        self.assertEqual(self.mapping["counts"]["no_frozen_issue"], counted["no_frozen_issue"])
        self.assertEqual(self.mapping["counts"]["v1_total"], len(self.entries))

    def test_no_equivalence_is_claimed_while_a_decision_is_open(self):
        for e in self.entries:
            if e.get("requires_contract_decision"):
                self.assertNotEqual(e["kind"], "one_to_one",
                                    f"{e['v1_issue']} claims 1:1 equivalence while a contract decision is still open")
                self.assertTrue(e.get("note"), f"{e['v1_issue']}: requires_contract_decision without a note")

    def test_unmapped_issues_declare_a_roadmap(self):
        for e in self.entries:
            if e["kind"] == "no_frozen_issue":
                self.assertIn(e.get("roadmap"), ROADMAP,
                              f"{e['v1_issue']}: no_frozen_issue must say why (behaviour_not_issue | candidate_gap)")

    def test_beauty_is_not_a_keep_decision(self):
        rules = self.mapping["rules"]
        for key in ("beauty_vs_keep", "missing_is_not_negative", "missing_delta_is_mask", "no_invented_equivalence"):
            self.assertIn(key, rules, f"rules.{key} is missing")
        text = rules["beauty_vs_keep"].lower()
        self.assertIn("not a keep decision", text)
        self.assertIn("positive evidence", text)


if __name__ == "__main__":
    unittest.main()
