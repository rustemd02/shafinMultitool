#!/usr/bin/env python3
"""ML-002 bounded check for camera_production_heads_v1.md.

Parses the machine-readable JSON block embedded in the contract document and
verifies, against the pinned sibling contracts:

(a) all 15 DATA-001 release issue heads are covered by the issue head;
(b) every documented app consumer symbol occurs verbatim in
    camera_release_capability_mapping_v1.json;
(c) every production head has non-empty target/mask/loss/metric/consumer;
(d) temporal modeling is marked separately and deferred to ML-011;
(e) the proposed action set equals exactly the DATA-002 disposition=mapped
    actions, and every non-proposed DATA-001 action is explicitly excluded.

Dependency-light (stdlib only). Prints PASS/FAIL and exits non-zero on any
failure. This check proves contract consistency only; it does not train a
model and does not admit anything into the app.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CONTRACTS_DIR = Path(__file__).resolve().parent
DOC_PATH = CONTRACTS_DIR / "camera_production_heads_v1.md"
MAPPING_PATH = CONTRACTS_DIR / "camera_release_capability_mapping_v1.json"
LABEL_SCHEMA_PATH = CONTRACTS_DIR / "camera_release_label_v1.schema.json"

BEGIN_MARKER = "<!-- camera-production-heads-v1:machine-readable-begin -->"
END_MARKER = "<!-- camera-production-heads-v1:machine-readable-end -->"

EXPECTED_HEAD_IDS = {
    "good_frame_probability",
    "issue_logits",
    "action_utility_logits",
    "continuous_target_deltas",
    "risk_probability",
    "abstention_probability",
    "calibration_artifact",
}
REQUIRED_FIELDS = ("target", "mask", "loss", "metric")


class CheckFailure(Exception):
    pass


def load_machine_readable_block(doc_text: str) -> dict:
    if BEGIN_MARKER not in doc_text or END_MARKER not in doc_text:
        raise CheckFailure("machine-readable markers missing from the document")
    begin = doc_text.index(BEGIN_MARKER) + len(BEGIN_MARKER)
    end = doc_text.index(END_MARKER)
    block = doc_text[begin:end]
    fence_match = re.search(r"```json\s*(\{.*?\})\s*```", block, re.DOTALL)
    if fence_match is None:
        raise CheckFailure("no ```json fenced object between the markers")
    try:
        return json.loads(fence_match.group(1))
    except json.JSONDecodeError as exc:
        raise CheckFailure(f"machine-readable block is not valid JSON: {exc}") from exc


def main() -> int:
    failures: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    # --- load pinned canonical inputs -------------------------------------
    doc_text = DOC_PATH.read_text(encoding="utf-8")
    mapping_raw = MAPPING_PATH.read_text(encoding="utf-8")
    mapping = json.loads(mapping_raw)
    schema = json.loads(LABEL_SCHEMA_PATH.read_text(encoding="utf-8"))

    contract: dict = {}
    try:
        contract = load_machine_readable_block(doc_text)
    except CheckFailure as exc:
        print(f"FAIL ML-002 production-heads check: {exc}")
        return 1

    require(
        contract.get("contract_id") == "camera-production-heads-v1",
        "contract_id must be camera-production-heads-v1",
    )
    require(
        contract.get("authority") == "ML-002",
        "authority must be ML-002",
    )

    heads = contract.get("heads")
    require(isinstance(heads, list) and bool(heads), "heads must be a non-empty list")
    if not isinstance(heads, list) or not heads:
        print("FAIL ML-002 production-heads check: heads block missing")
        return 1

    heads_by_id = {}
    for head in heads:
        head_id = head.get("head_id")
        require(bool(head_id), "every head needs a head_id")
        if head_id:
            require(
                head_id not in heads_by_id,
                f"duplicate head_id: {head_id}",
            )
            heads_by_id[head_id] = head

    # --- (structure) exact minimal production head set --------------------
    require(
        set(heads_by_id) == EXPECTED_HEAD_IDS,
        "head set must be exactly the 7 minimal production entries "
        f"(found: {sorted(heads_by_id)}; expected: {sorted(EXPECTED_HEAD_IDS)})",
    )

    # --- (c) every head has non-empty target/mask/loss/metric/consumer ----
    for head in heads:
        head_id = head.get("head_id", "<missing>")
        for field in REQUIRED_FIELDS:
            value = head.get(field)
            require(
                isinstance(value, str) and value.strip() != "",
                f"head {head_id}: field '{field}' must be a non-empty string",
            )
        consumers = head.get("consumer")
        require(
            isinstance(consumers, list) and len(consumers) > 0,
            f"head {head_id}: 'consumer' must be a non-empty list",
        )

    # --- (b) every consumer symbol occurs in the capability mapping -------
    for head in heads:
        head_id = head.get("head_id", "<missing>")
        consumers = head.get("consumer") or []
        if not isinstance(consumers, list):
            continue
        for symbol in consumers:
            require(
                isinstance(symbol, str) and bool(symbol),
                f"head {head_id}: consumer symbol must be a non-empty string",
            )
            if isinstance(symbol, str) and symbol:
                require(
                    symbol in mapping_raw,
                    f"head {head_id}: consumer symbol not found in "
                    f"{MAPPING_PATH.name}: {symbol!r}",
                )

    # --- (a) all 15 DATA-001 issue heads covered ---------------------------
    schema_issue_ids = schema.get("$defs", {}).get("issueID", {}).get("enum")
    require(
        isinstance(schema_issue_ids, list) and len(schema_issue_ids) == 15,
        "label schema must declare exactly 15 issue ids",
    )
    issue_head = heads_by_id.get("issue_logits")
    covered = (issue_head or {}).get("covered_issue_ids")
    require(
        isinstance(covered, list),
        "issue_logits must declare covered_issue_ids",
    )
    if isinstance(schema_issue_ids, list) and isinstance(covered, list):
        require(
            set(covered) == set(schema_issue_ids),
            "covered_issue_ids must equal the 15 schema issue ids "
            f"(missing: {sorted(set(schema_issue_ids) - set(covered))}; "
            f"extra: {sorted(set(covered) - set(schema_issue_ids))})",
        )
        require(
            len(covered) == len(set(covered)) == 15,
            "covered_issue_ids must list each of the 15 issue ids exactly once",
        )

    # --- (e) action set equals DATA-002 mapped dispositions ----------------
    schema_action_ids = schema.get("$defs", {}).get("actionID", {}).get("enum")
    dispositions = mapping.get("action_dispositions", {})
    action_head = heads_by_id.get("action_utility_logits")
    proposed = (action_head or {}).get("proposed_action_ids")
    excluded = (action_head or {}).get("excluded_action_ids")
    require(
        isinstance(schema_action_ids, list) and len(schema_action_ids) == 33,
        "label schema must declare exactly 33 action ids",
    )
    require(
        isinstance(proposed, list) and bool(proposed),
        "action_utility_logits must declare proposed_action_ids",
    )
    require(
        isinstance(excluded, list),
        "action_utility_logits must declare excluded_action_ids",
    )
    if (
        isinstance(schema_action_ids, list)
        and isinstance(proposed, list)
        and isinstance(excluded, list)
        and dispositions
    ):
        mapped_ids = {
            action_id
            for action_id, record in dispositions.items()
            if isinstance(record, dict) and record.get("status") == "mapped"
        }
        require(
            set(proposed) == mapped_ids,
            "proposed_action_ids must equal exactly the DATA-002 mapped actions "
            f"(missing: {sorted(mapped_ids - set(proposed))}; "
            f"extra: {sorted(set(proposed) - mapped_ids)})",
        )
        require(
            len(proposed) == len(set(proposed)),
            "proposed_action_ids must not contain duplicates",
        )
        require(
            not (set(proposed) & set(excluded)),
            "an action cannot be both proposed and excluded",
        )
        require(
            set(proposed) | set(excluded) == set(schema_action_ids),
            "proposed + excluded must partition all 33 DATA-001 actions "
            f"(unaccounted: {sorted(set(schema_action_ids) - set(proposed) - set(excluded))})",
        )
        for action_id in excluded:
            record = dispositions.get(action_id)
            require(
                isinstance(record, dict) and record.get("status") in ("unsupported", "app_only"),
                f"excluded action {action_id} must be unsupported/app_only in DATA-002",
            )

    # --- (d) temporal marked separately and deferred to ML-011 -------------
    temporal = contract.get("temporal")
    require(
        isinstance(temporal, dict) and bool(temporal),
        "temporal must be documented as a separate entry",
    )
    if isinstance(temporal, dict):
        require(
            temporal.get("status") == "deferred_to_ML_011",
            "temporal status must be deferred_to_ML_011",
        )
        require(
            "ML-011" in json.dumps(temporal),
            "temporal entry must reference the ML-011 decision",
        )
        require(
            temporal.get("head_id") not in heads_by_id,
            "temporal must not be part of the v1 production head set",
        )

    # --- report ------------------------------------------------------------
    if failures:
        print("FAIL ML-002 production-heads check")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS ML-002 production-heads check")
    print(f"  contract: {contract.get('contract_id')} v{contract.get('contract_version')}")
    print(f"  heads: {len(heads_by_id)}/7 minimal production entries with target/mask/loss/metric/consumer")
    print(f"  (a) issue coverage: {len(covered)}/15 DATA-001 issue heads")
    consumer_count = sum(len(h.get('consumer') or []) for h in heads)
    print(f"  (b) consumer symbols verified in {MAPPING_PATH.name}: {consumer_count}")
    print(f"  (e) action head: {len(proposed)} proposed = DATA-002 mapped; {len(excluded)} explicitly excluded")
    print(f"  (d) temporal: {temporal.get('status')} (separate entry, not a v1 head)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
