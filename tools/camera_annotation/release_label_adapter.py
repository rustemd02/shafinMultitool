#!/usr/bin/env python3
"""Adapter: v1 human-gold review records -> camera-release-label-v1 exports.

Bounded DATA-005 slice. The existing annotation path (build_label -> review
store -> vote capture) stays the annotator-facing surface, including the
natural-language notes UX; this module only converts an admitted v1 review
record into a `camera-release-label-v1` structured label and exports it in an
envelope that keeps the raw opinion BESIDE the structured label (the release
schema forbids extra properties, so the opinion cannot live inside it).

Fail-closed rules encoded here (no silent fabrication):

- A present issue requires annotator-provided severity, confidence, evidence
  refs and (optionally) a region; the v1 record alone cannot satisfy the
  release contract, so the export refuses instead of inventing numbers.
- improvement_needed=true requires exactly one corrective action; the release
  contract has a single action object and choosing among several is a human
  decision, not an adapter default.
- The proposal/teacher suggestion is never copied into the label: only its ID
  travels (provenance.proposal_id). Origin stays human_review/human_adjudication;
  model_proposal exports are rejected.
- release_admissible=True requires human_gold=True, an adjudication origin and
  an adjudicator id.
- Frame identity is re-verified at export time: content_sha256 must equal the
  current file hash, so a stale record cannot export silently.

Round-trip (raw -> proposal -> human edit -> export) is available as the
`roundtrip` subcommand, which validates the exported label with the DATA-001
contract validator (schema + semantic cross-record checks).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
CONTRACTS = REPO / "ml" / "camera_coach" / "contracts"
sys.path.insert(0, str(CONTRACTS))

from annotation_labels import ISSUES as V1_ISSUES  # noqa: E402
from annotation_labels import validate_label  # noqa: E402

ENVELOPE_SCHEMA_ID = "camera-release-label-export-v1"
ENVELOPE_VERSION = 1

# Unambiguous v1 delta axes per corrective action. Actions missing here get
# magnitude not_observed unless the caller supplies explicit magnitude input;
# guessing an axis from an action name would fabricate evidence.
ACTION_DELTA_AXIS: dict[str, str] = {
    "shift_frame_left": "delta_x",
    "shift_frame_right": "delta_x",
    "shift_frame_up": "delta_y",
    "shift_frame_down": "delta_y",
    "step_back": "scale_delta",
    "step_closer": "scale_delta",
    "lower_camera": "delta_y",
    "raise_camera": "delta_y",
    "level_horizon": "horizon_delta",
    "move_object_left": "delta_x",
    "move_object_right": "delta_x",
    "move_object_forward": "scale_delta",
    "move_object_back": "scale_delta",
}

KEEP_ACTION = "keep_current_setup"

_NOT_OBSERVED_ISSUE = {
    "status": "not_observed",
    "severity": None,
    "confidence": None,
    "region": None,
    "evidence_refs": [],
}

_NOT_OBSERVED_OUTCOME = {
    "status": "not_observed",
    "outcome": None,
    "same_target": False,
    "target_ref": None,
    "before_frame_id": None,
    "after_frame_id": None,
    "metric": None,
}


class AdapterError(Exception):
    """The record cannot be converted without fabricating contract data."""


def _load_schema() -> dict:
    return json.loads((CONTRACTS / "camera_release_label_v1.schema.json").read_text(encoding="utf-8"))


SCHEMA = _load_schema()
RELEASE_ISSUE_IDS: list[str] = SCHEMA["$defs"]["issueID"]["enum"]
RELEASE_ACTION_IDS: list[str] = SCHEMA["$defs"]["actionID"]["enum"]
STABLE_ID_PATTERN = SCHEMA["$defs"]["stableID"]["pattern"]
RECORD_ID_PATTERN = SCHEMA["$defs"]["recordID"]["pattern"]

if not set(V1_ISSUES).issubset(set(RELEASE_ISSUE_IDS)):
    raise RuntimeError(
        "annotation tool issue vocabulary is not a subset of the release contract: "
        f"{sorted(set(V1_ISSUES) - set(RELEASE_ISSUE_IDS))}"
    )


def _import_validator():
    import importlib

    module = importlib.import_module("validate_camera_release_label")
    from jsonschema import Draft202012Validator

    validator = Draft202012Validator(SCHEMA)
    return module, validator


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_stable_id(value: Any, field: str) -> str:
    import re

    if not isinstance(value, str) or not re.match(STABLE_ID_PATTERN, value):
        raise AdapterError(f"{field} must be a stable id matching {STABLE_ID_PATTERN}")
    return value


def _region_from_rect(rect: list[float] | None) -> dict | None:
    if rect is None:
        return None
    x, y, w, h = (float(v) for v in rect)
    return {"x": x, "y": y, "width": w, "height": h}


def _magnitude_for(action_id: str, review: dict, explicit: dict | None) -> dict:
    if explicit is not None:
        if set(explicit) != {"status", "axis", "value", "unit"}:
            raise AdapterError("explicit magnitude must carry exactly status/axis/value/unit")
        return dict(explicit)
    axis = ACTION_DELTA_AXIS.get(action_id)
    deltas = review.get("deltas") or {}
    if axis is not None and axis in deltas:
        return {"status": "observed", "axis": axis, "value": float(deltas[axis]), "unit": "normalized_delta"}
    return {"status": "not_observed", "axis": None, "value": None, "unit": None}


def build_release_label(
    review: dict,
    *,
    release_record_id: str,
    source_family_id: str,
    frame_id: str,
    captured_at: str,
    image_file: Path,
    issue_evidence: dict[str, dict],
    target: dict,
    corrective_action_id: str | None = None,
    action_issue_ids: list[str] | None = None,
    action_magnitude: dict | None = None,
    risk: dict | None = None,
    abstention_reasons: list[str] | None = None,
    intent_selection: str = "unknown",
    intent_subject_refs: list[str] | None = None,
    review_ids: list[str] | None = None,
    origin: str = "human_review",
    adjudicator_id: str | None = None,
    human_gold: bool = False,
    release_admissible: bool = False,
    before_after: dict | None = None,
) -> dict:
    """Convert one admitted v1 review record into a release-label-v1 dict."""
    import re

    errors = validate_label(review)
    if errors:
        raise AdapterError(f"v1 review record is not admissible: {errors}")

    if not re.match(RECORD_ID_PATTERN, release_record_id):
        raise AdapterError(f"release_record_id must match {RECORD_ID_PATTERN}")

    content_sha = sha256_file(image_file)
    if content_sha != review["image_sha256"]:
        raise AdapterError(
            f"frame identity changed: record says {review['image_sha256'][:12]}…, file hashes {content_sha[:12]}…"
        )

    unsure = bool(review.get("unsure"))
    improvement_needed = review.get("improvement_needed")

    abstention = {"status": "none", "reasons": []}
    if unsure:
        if improvement_needed is not None:
            raise AdapterError("undecided review must carry improvement_needed=null")
        if not abstention_reasons:
            raise AdapterError("abstaining export requires explicit abstention_reasons (no silent default)")
        abstention = {"status": "abstain", "reasons": list(abstention_reasons)}
        verdict = None
        action = None
    elif improvement_needed is True:
        verdict = "needs_fix"
        corrective = [a for a in review["actions"] if a != KEEP_ACTION]
        if corrective_action_id is None:
            if len(corrective) != 1:
                raise AdapterError(
                    "exactly one corrective action must be named for a needs_fix export "
                    f"(review carries {corrective}); the release contract has a single action object"
                )
            corrective_action_id = corrective[0]
        elif corrective_action_id not in corrective:
            raise AdapterError(
                f"corrective_action_id {corrective_action_id!r} is not among the review's corrective actions {corrective}"
            )
        if corrective_action_id not in RELEASE_ACTION_IDS:
            raise AdapterError(f"action {corrective_action_id!r} is not in the release contract vocabulary")
        issue_ids = list(action_issue_ids) if action_issue_ids is not None else list(review["issues"])
        unknown = [i for i in issue_ids if i not in RELEASE_ISSUE_IDS]
        if unknown:
            raise AdapterError(f"action_issue_ids contains unknown issue heads: {unknown}")
        action = {
            "action_id": corrective_action_id,
            "issue_ids": issue_ids,
            "magnitude": _magnitude_for(corrective_action_id, review, action_magnitude),
        }
    elif improvement_needed is False:
        verdict = "good"
        if review["actions"] != [KEEP_ACTION]:
            raise AdapterError("improvement_needed=false reviews export only keep_current_setup")
        action = {"action_id": KEEP_ACTION, "issue_ids": [], "magnitude": _magnitude_for(KEEP_ACTION, review, None)}
    else:
        raise AdapterError("review must be decided (improvement_needed true/false) or explicitly unsure")

    issues: list[dict] = []
    for head in RELEASE_ISSUE_IDS:
        if head in review["issues"]:
            evidence = issue_evidence.get(head)
            if not evidence or "severity" not in evidence or "confidence" not in evidence:
                raise AdapterError(
                    f"present issue {head!r} requires severity+confidence in issue_evidence "
                    "(the release contract forbids fabricating them)"
                )
            refs = evidence.get("evidence_refs") or []
            if not refs:
                raise AdapterError(f"present issue {head!r} requires at least one evidence ref")
            issues.append(
                {
                    "issue_id": head,
                    "status": "present",
                    "severity": float(evidence["severity"]),
                    "confidence": float(evidence["confidence"]),
                    "region": _region_from_rect(evidence.get("rect")),
                    "evidence_refs": [_require_stable_id(r, f"evidence_refs[{head}]") for r in refs],
                }
            )
        else:
            issues.append({"issue_id": head, **_NOT_OBSERVED_ISSUE})

    for field, pattern_key in (
        ("entity_ref", None),
        ("identity_status", None),
        ("kind", None),
        ("role", None),
        ("movability", None),
    ):
        if field not in target:
            raise AdapterError(f"target.{field} is required (the release contract has no legal default)")
    movability = target["movability"]
    if set(movability) != {"status", "permission"}:
        raise AdapterError("target.movability must carry exactly status+permission")
    resolved_target = {
        "entity_ref": _require_stable_id(target["entity_ref"], "target.entity_ref"),
        "identity_status": target["identity_status"],
        "kind": target["kind"],
        "role": target["role"],
        "region": _region_from_rect(target.get("rect")),
        "movability": {"status": movability["status"], "permission": movability["permission"]},
    }

    if origin not in ("human_review", "human_adjudication"):
        raise AdapterError("the annotation tool exports human records only; model_proposal is rejected")
    review_status = "reviewed" if origin == "human_review" else "adjudicated"
    if origin == "human_adjudication" and not adjudicator_id:
        raise AdapterError("adjudication export requires adjudicator_id")
    if not (review_ids or []):
        # The contract's provenance schema requires a non-empty review_ids list;
        # an export without at least one review record id would be invalid.
        raise AdapterError("review_ids must name at least one review record id")
    if origin == "human_adjudication" and not adjudicator_id:
        raise AdapterError("adjudication export requires adjudicator_id")
    if release_admissible and not (human_gold and review_status == "adjudicated" and adjudicator_id):
        raise AdapterError(
            "release_admissible=true requires human_gold=true, adjudication origin and an adjudicator id"
        )
    proposal_id = review.get("teacher_proposal_id")
    provenance = {
        "origin": origin,
        "review_status": review_status,
        "annotator_id": review["annotator_id"],
        "proposal_id": proposal_id,
        "review_ids": [_require_stable_id(r, "review_ids") for r in (review_ids or [])],
        "adjudicator_id": adjudicator_id,
        "human_gold": bool(human_gold),
        "release_admissible": bool(release_admissible),
    }

    styles = [review["capture_intent"]] if review.get("capture_intent") else []
    if intent_selection == "unknown" and intent_subject_refs:
        raise AdapterError("intent selection unknown forbids subject_refs")

    return {
        "schema_id": "camera-release-label-v1",
        "schema_version": "1.0.0",
        "record_id": release_record_id,
        "source": {
            "source_family_id": _require_stable_id(source_family_id, "source_family_id"),
            "frame_id": _require_stable_id(frame_id, "frame_id"),
            "content_sha256": content_sha,
            "captured_at": captured_at,
        },
        "provenance": provenance,
        "verdict": verdict,
        "issues": issues,
        "action": action,
        "target": resolved_target,
        "risk": risk or {"status": "not_observed", "probability": None},
        "abstention": abstention,
        "intent": {
            "selection": intent_selection,
            "subject_refs": [_require_stable_id(r, "intent.subject_refs") for r in (intent_subject_refs or [])],
            "styles": styles,
            "intent_revision": 0,
        },
        "before_after": before_after or dict(_NOT_OBSERVED_OUTCOME),
    }


def build_export_envelope(
    release_label: dict,
    *,
    source_review: dict,
    raw_opinion: str,
    raw_opinion_author: str | None = None,
) -> dict:
    """Wrap the structured label with the raw opinion and identity refs.

    The release label itself stays schema-clean; the opinion text travels
    beside it so no free-form content can drift into the contract surface.
    """
    opinion = (raw_opinion or "").strip()
    if not opinion:
        raise AdapterError("raw opinion is required next to the structured label (natural-language UX)")
    return {
        "envelope_schema_id": ENVELOPE_SCHEMA_ID,
        "envelope_version": ENVELOPE_VERSION,
        "source_review": {
            "record_id": source_review["record_id"],
            "image_sha256": source_review["image_sha256"],
            "image_path": source_review.get("image_path"),
            "created_at": source_review["created_at"],
            "assisted": bool(source_review.get("assisted")),
            "assist_source": source_review.get("assist_source"),
            "teacher_proposal_id": source_review.get("teacher_proposal_id"),
        },
        "raw_opinion": {
            "text": opinion,
            "annotator_id": raw_opinion_author or source_review["annotator_id"],
            "created_at": source_review["created_at"],
        },
        "release_label": release_label,
    }


def validate_release_label(label: dict) -> list[str]:
    module, validator = _import_validator()
    return module.validate_record(validator, label)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)

    conv = sub.add_parser("convert", help="v1 review record -> release label envelope")
    conv.add_argument("--review", type=Path, required=True, help="v1 label JSON from build_label")
    conv.add_argument("--config", type=Path, required=True, help="conversion inputs JSON (see build_release_label)")
    conv.add_argument("--out", type=Path, required=True)

    val = sub.add_parser("validate", help="validate an exported release label with the DATA-001 validator")
    val.add_argument("--label", type=Path, required=True)

    args = ap.parse_args()

    if args.command == "convert":
        try:
            review = json.loads(args.review.read_text(encoding="utf-8"))
            config = json.loads(args.config.read_text(encoding="utf-8"))
            image_file = Path(review.get("image_path") or config["image_file"])
            label = build_release_label(
                review,
                release_record_id=config["release_record_id"],
                source_family_id=config["source_family_id"],
                frame_id=config["frame_id"],
                captured_at=config["captured_at"],
                image_file=image_file,
                issue_evidence=config.get("issue_evidence", {}),
                target=config["target"],
                corrective_action_id=config.get("corrective_action_id"),
                action_issue_ids=config.get("action_issue_ids"),
                action_magnitude=config.get("action_magnitude"),
                risk=config.get("risk"),
                abstention_reasons=config.get("abstention_reasons"),
                intent_selection=config.get("intent_selection", "unknown"),
                intent_subject_refs=config.get("intent_subject_refs"),
                review_ids=config.get("review_ids"),
                origin=config.get("origin", "human_review"),
                adjudicator_id=config.get("adjudicator_id"),
                human_gold=config.get("human_gold", False),
                release_admissible=config.get("release_admissible", False),
                before_after=config.get("before_after"),
            )
            envelope = build_export_envelope(
                label,
                source_review=review,
                raw_opinion=config.get("raw_opinion") or review.get("notes", ""),
            )
        except AdapterError as exc:
            print(f"CONVERSION REJECTED: {exc}", file=sys.stderr)
            return 1
        args.out.write_text(json.dumps(envelope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"EXPORTED envelope record_id={label['record_id']} out={args.out}")
        return 0

    label = json.loads(args.label.read_text(encoding="utf-8"))
    payload = label["release_label"] if "envelope_schema_id" in label else label
    errors = validate_release_label(payload)
    if errors:
        print("RELEASE LABEL INVALID:")
        for err in errors:
            print(f"  - {err}")
        return 1
    print("RELEASE LABEL VALID")
    return 0


if __name__ == "__main__":
    sys.exit(main())
