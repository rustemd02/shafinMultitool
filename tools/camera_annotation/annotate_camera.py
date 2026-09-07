#!/usr/bin/env python3
"""Camera annotation vote capture (M3-006).

Local annotation/review assistant for the Camera Coach dataset. The
tool writes schema-valid, append-only votes; it deliberately hides
candidate identity and model output (records carrying candidate or
model fields are rejected at admission); adjudication is a separate
append-only record type so an adjudicator can resolve without ever
overwriting an annotator's vote.

Modes:
  vote        Append one annotator vote for one record.
  adjudicate  Append one adjudication decision (references votes).
  export      Emit the append-only store as a merged review bundle.

Storage: one JSONL file (append-only). Every line is a complete
self-contained record validated against the admission rules below;
lines are never rewritten or removed.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


TOOL_ID = "camera-annotation-vote-capture-v1"
STORE_VERSION = 1

FORBIDDEN_FIELD_HINTS = (
    "candidate", "model", "score", "probability", "prediction",
    "output", "logits", "confidence_model",
)
VOTE_VERDICTS = {"good", "bad", "abstain"}
VOTE_SUBJECT_STATES = {"selected", "ambiguous", "none", "abstain"}
RECORD_TYPES = {"vote", "adjudication", "hidden_qc"}
ADJUDICATION_OUTCOMES = {"uphold", "override", "split", "quarantine"}

_WRITE_LOCK = threading.Lock()


class AdmissionError(Exception):
    """The record cannot enter the append-only store."""


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def check_no_candidate_leak(record: dict) -> None:
    """Hidden-QC gate: reject any record that carries candidate or
    model-derived fields anywhere in its tree."""
    def walk(node: Any, path: str) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                lowered = key.lower()
                if any(hint in lowered for hint in FORBIDDEN_FIELD_HINTS):
                    raise AdmissionError(
                        f"candidate/model field '{path}{key}' is forbidden in the annotation store"
                    )
                walk(value, f"{path}{key}.")
        elif isinstance(node, list):
            for index, item in enumerate(node):
                walk(item, f"{path}{index}.")
    walk(record, "")


def build_vote(
    record_id: str,
    annotator_id: str,
    verdict: str,
    subject_state: str,
    selected_subject_id: str | None,
    region_ids: list[str],
    notes: str = "",
) -> dict:
    if verdict not in VOTE_VERDICTS:
        raise AdmissionError(f"verdict must be one of {sorted(VOTE_VERDICTS)}")
    if subject_state not in VOTE_SUBJECT_STATES:
        raise AdmissionError(f"subject_state must be one of {sorted(VOTE_SUBJECT_STATES)}")
    if verdict == "abstain" and not notes:
        raise AdmissionError("abstain votes require a reason in notes")
    vote: dict[str, Any] = {
        "record_type": "vote",
        "tool_id": TOOL_ID,
        "store_version": STORE_VERSION,
        "record_id": record_id,
        "annotator_id": annotator_id,
        "verdict": verdict,
        "subject_state": subject_state,
        "selected_subject_id": selected_subject_id,
        "region_ids": list(region_ids),
        "notes": notes,
        "created_at": _utc_now(),
    }
    if subject_state in {"ambiguous", "none", "abstain"} and selected_subject_id is not None:
        raise AdmissionError(f"subject_state={subject_state} requires selected_subject_id=null")
    check_no_candidate_leak(vote)
    return vote


def build_adjudication(
    record_id: str,
    adjudicator_id: str,
    outcome: str,
    referenced_vote_ids: list[str],
    resolved_subject_id: str | None,
    notes: str,
) -> dict:
    if outcome not in ADJUDICATION_OUTCOMES:
        raise AdmissionError(f"outcome must be one of {sorted(ADJUDICATION_OUTCOMES)}")
    if not referenced_vote_ids:
        raise AdmissionError("adjudication must reference at least one vote id")
    if not notes:
        raise AdmissionError("adjudication requires notes")
    entry: dict[str, Any] = {
        "record_type": "adjudication",
        "tool_id": TOOL_ID,
        "store_version": STORE_VERSION,
        "record_id": record_id,
        "adjudicator_id": adjudicator_id,
        "outcome": outcome,
        "referenced_vote_ids": list(referenced_vote_ids),
        "resolved_subject_id": resolved_subject_id,
        "notes": notes,
        "created_at": _utc_now(),
    }
    check_no_candidate_leak(entry)
    return entry


def append_record(store_path: Path, record: dict) -> int:
    """Append one record. Thread-safe; returns the new line count."""
    check_no_candidate_leak(record)
    with _WRITE_LOCK:
        store_path.parent.mkdir(parents=True, exist_ok=True)
        with store_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        with store_path.open("r", encoding="utf-8") as handle:
            return sum(1 for line in handle if line.strip())


def load_store(store_path: Path) -> list[dict]:
    if not store_path.exists():
        return []
    records: list[dict] = []
    for line in store_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        check_no_candidate_leak(entry)
        records.append(entry)
    return records


def export_bundle(store_path: Path) -> dict:
    records = load_store(store_path)
    votes = [r for r in records if r["record_type"] == "vote"]
    adjudications = [r for r in records if r["record_type"] == "adjudication"]
    qc = [r for r in records if r["record_type"] == "hidden_qc"]
    return {
        "tool_id": TOOL_ID,
        "store_version": STORE_VERSION,
        "exported_at": _utc_now(),
        "vote_count": len(votes),
        "adjudication_count": len(adjudications),
        "hidden_qc_count": len(qc),
        "records": records,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--store", type=Path, required=True)
    sub = ap.add_subparsers(dest="command", required=True)

    vote_ap = sub.add_parser("vote")
    vote_ap.add_argument("--record-id", required=True)
    vote_ap.add_argument("--annotator-id", required=True)
    vote_ap.add_argument("--verdict", required=True, choices=sorted(VOTE_VERDICTS))
    vote_ap.add_argument("--subject-state", required=True, choices=sorted(VOTE_SUBJECT_STATES))
    vote_ap.add_argument("--selected-subject-id", default=None)
    vote_ap.add_argument("--region-ids", nargs="*", default=[])
    vote_ap.add_argument("--notes", default="")

    adj_ap = sub.add_parser("adjudicate")
    adj_ap.add_argument("--record-id", required=True)
    adj_ap.add_argument("--adjudicator-id", required=True)
    adj_ap.add_argument("--outcome", required=True, choices=sorted(ADJUDICATION_OUTCOMES))
    adj_ap.add_argument("--referenced-vote-ids", nargs="+", required=True)
    adj_ap.add_argument("--resolved-subject-id", default=None)
    adj_ap.add_argument("--notes", required=True)

    sub.add_parser("export")
    args = ap.parse_args()

    try:
        if args.command == "vote":
            record = build_vote(
                record_id=args.record_id,
                annotator_id=args.annotator_id,
                verdict=args.verdict,
                subject_state=args.subject_state,
                selected_subject_id=args.selected_subject_id,
                region_ids=args.region_ids,
                notes=args.notes,
            )
            count = append_record(args.store, record)
            print(f"APPENDED vote line_count={count}")
            return 0
        if args.command == "adjudicate":
            record = build_adjudication(
                record_id=args.record_id,
                adjudicator_id=args.adjudicator_id,
                outcome=args.outcome,
                referenced_vote_ids=args.referenced_vote_ids,
                resolved_subject_id=args.resolved_subject_id,
                notes=args.notes,
            )
            count = append_record(args.store, record)
            print(f"APPENDED adjudication line_count={count}")
            return 0
        bundle = export_bundle(args.store)
        print(json.dumps(bundle, ensure_ascii=False, indent=1))
        return 0
    except AdmissionError as exc:
        print(f"ADMISSION REJECTED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
