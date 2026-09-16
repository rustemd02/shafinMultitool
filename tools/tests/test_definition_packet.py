"""The definition packet must stay a packet: options with evidence, never a decision.

Ten rows of the §5.1 table have a threshold and no definition (recorded in
`datasets/camera-coach/v1/evaluation-policy-v1.json`). The repository can already
support several readings for each of them, so
`evidence-release/definition-packet-5-1.json` lays those readings out for the owner.
This suite keeps it honest:

* every row the policy marks `pending_definition` appears in the packet;
* each row offers at least two distinct readings, and every reading names the
  evidence it rests on and what the owner has to decide;
* the packet is still `awaiting_owner_decision` and no option is marked chosen, so a
  prepared option cannot quietly become the contract.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
POLICY = REPO_ROOT / "datasets/camera-coach/v1/evaluation-policy-v1.json"
PACKET = REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/definition-packet-5-1.json"

policy = json.loads(POLICY.read_text(encoding="utf-8"))
packet = json.loads(PACKET.read_text(encoding="utf-8"))
ROWS = policy["runbook_5_1_rows"]["rows"]
PENDING = sorted(row for row, entry in ROWS.items()
                 if entry["definition_status"] == "pending_definition")


def test_every_pending_row_has_a_packet_entry():
    assert sorted(packet["rows"]) == PENDING


def test_each_pending_row_offers_at_least_two_distinct_readings():
    thin = {row: len(entry["options"]) for row, entry in packet["rows"].items()
            if len(entry["options"]) < 2}
    assert thin == {}, f"rows with a single reading are not a choice: {thin}"


@pytest.mark.parametrize("row", PENDING)
def test_every_option_cites_evidence_and_states_what_the_owner_must_decide(row):
    for option in packet["rows"][row]["options"]:
        assert option.get("id"), row
        assert len(option.get("reading", "")) > 40, f"{row}/{option.get('id')}: reading too thin"
        assert option.get("formula"), f"{row}/{option.get('id')}: no formula"
        assert option.get("evidence"), f"{row}/{option.get('id')}: no evidence"
        assert option.get("needs_from_owner"), f"{row}/{option.get('id')}: no owner decision named"


def test_the_packet_does_not_decide_anything():
    assert packet["status"] == "awaiting_owner_decision"
    assert "nothing here is decided" in packet["decision_required"].lower()
    for row, entry in packet["rows"].items():
        for option in entry["options"]:
            assert "chosen" not in option and "selected" not in option, row
            assert option.get("decided") in (None, False), f"{row}/{option['id']} looks decided"


def test_the_packet_states_how_a_decision_is_applied():
    steps = packet["how_to_apply_a_decision"]
    assert set(steps) == {"step_1", "step_2", "step_3", "step_4"}
    assert "evaluation-policy-v1.json" in steps["step_2"]
    assert "freeze_receipt" in steps["step_3"]


def test_the_policy_points_at_the_packet():
    """A reader of the policy must be able to find the pending decision."""
    assert policy["runbook_5_1_rows"].get("decision_packet") == \
        "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/definition-packet-5-1.json"

# -------------------------------------------------- option-space coherence
def test_option_interactions_reference_real_rows_and_options():
    """The interaction notes must point at rows and options that exist.

    Each pair maps `rows[i]` to `options[i]`, so a note cannot drift into naming an
    option one of its rows does not have.
    """
    interactions = packet.get("option_interactions")
    assert isinstance(interactions, dict), "the packet carries no option_interactions section"
    pairs = interactions.get("pairs")
    assert isinstance(pairs, list) and pairs
    for pair in pairs:
        rows, options = pair["rows"], pair["options"]
        assert len(rows) == len(options) == 2, pair
        for row, option in zip(rows, options):
            if option == "(already defined)":
                assert row == "false_improved", pair
                continue
            assert row in packet["rows"], f"{row} is not a packet row"
            ids = [item["id"] for item in packet["rows"][row]["options"]]
            assert option in ids, f"{row} has no option {option} (has {ids})"
        assert pair.get("overlap") and pair.get("if_both") and pair.get("prefer"), pair


def test_the_interactions_section_does_not_decide_anything():
    interactions = packet["option_interactions"]
    assert "only states which pairs overlap" in interactions["note"]
    for pair in interactions["pairs"]:
        assert "chosen" not in pair and "selected" not in pair
