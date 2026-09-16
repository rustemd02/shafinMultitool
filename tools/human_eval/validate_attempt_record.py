#!/usr/bin/env python3
"""Derive `record_status` for a human-eval attempt record (fail-closed).

`docs/implementation/human-eval/attempt-record-schema.md` §3 states the rule:
`record_status = complete` if and only if nine conditions hold, and any violation
makes the record `incomplete`, excluded from every quota and gate denominator,
and never guessed at. Until now that rule lived only as prose, so at device time a
status could be asserted by hand. This tool derives it instead.

Derived from the record alone: required and conditional field presence, closed
vocabulary membership (read from the frozen artifacts, not re-typed here),
strictly increasing UTC `Z` timestamps, `advice_count == 1` with a really shown
text, the measurable-outcome requirements, and `status=completed` requiring an
`after` side and a non-empty `performed_change`.

Needed from outside the record (§3 conditions 4, 5 and 9): entity-ref
resolution, real asset digests, and consent/rights admission. Without
`--resolution` those conditions are reported `unresolved` and the derived status
is `incomplete` — the tool never upgrades a record by assuming a resolution.

A closed vocabulary that cannot be read is treated the same way as a missing
resolution: the checks that needed it are reported `unresolved`, never skipped.
That is deliberate — a validator that silently stops checking because its
reference list came back empty is the "PASS because nothing was examined"
failure this repository keeps finding. `conditions_not_enforced` in the output
names every §2/§3 requirement that is *not* checkable from the record, so the
remaining gap is declared rather than implied.

Exit codes
    0  the derivation ran; per-record results are printed
    1  a record asserted a `record_status` that the derivation contradicts
       (the "complete" that is not - the case this tool exists to catch)
    2  the input could not be read, or a record is not an object

`validity` (shot-list §2 rules) is a separate axis and is NOT checked here; the
output says so explicitly rather than leaving it implied.

Usage
    python3 tools/human_eval/validate_attempt_record.py --record attempt.json
    python3 tools/human_eval/validate_attempt_record.py --records attempts.jsonl \\
        --resolution resolution.json [--json-out derived.json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LABEL_SCHEMA = REPO_ROOT / "datasets/camera-coach/v1/label-schema.json"
DEFAULT_SHOT_LIST = REPO_ROOT / "docs/implementation/human-eval/shot-list-v1.md"

UTC_Z = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ATTEMPT_ID = re.compile(r"^[a-z0-9][a-z0-9._-]*$")

MATRIX_CLASSES = {"single_person", "two_people", "object_or_food", "interior",
                  "street_or_landscape", "difficult_light", "already_good_frame"}
SPLITS = {"train", "calibration", "holdout", "quarantine"}
STATUSES = {"completed", "declined", "cancelled", "not_attempted", "failed_attempt"}
UNDERSTOOD = {"yes", "no", "partial", "not_asked"}
EXECUTABLE = {"yes", "no", "partial", "not_attempted"}
OUTCOMES = {"correct", "no_op", "opposite", "overshoot", "track_loss", "incomparable"}
MEASURABLE_OUTCOMES = {"correct", "no_op", "opposite", "overshoot"}
VERIFICATION_RESULTS = {"pass", "fail", "inconclusive", "not_run"}
MEASUREMENTS = {"single_frame", "before_after", "temporal_timeline", "not_observed"}
SUBJECT_CONTINUITY = {"same", "changed", "lost", "unknown"}
DERIVATION_KINDS = {"original_before_after_episode"}
STYLE_IDS = {"naturalistic", "cinematic", "documentary", "commercial", "stylized",
             "already_good", "unknown"}
INTENT_BASIS = {"capture_brief", "annotator_observed", "not_available"}
REFUSAL_SOURCES = {"human_reported", "not_provided"}
# Schema §2.3 closes this set in prose; no JSON artifact in the repository carries it.
REFUSAL_REASONS = {"not_provided", "prefer_not_to_say", "no_resource", "physically_unable",
                   "unsafe", "unclear_instruction", "too_slow", "other"}
KEEP_ACTION = "keep_current_setup"
PERFORMED_AT_REQUIRED = {"completed", "failed_attempt"}

REQUIRED_TOP = ("attempt_id", "shot_scenario_id", "matrix_class", "split", "source_shoot_id",
                "operator_id", "captured_at", "consent_record_id", "rights_record_id",
                "provenance_receipt_ref", "proposed_at", "advice_count", "proposed_action_id",
                "proposed_action_text", "proposed_target_refs", "understood", "executable",
                "status", "refusal_reason_source", "self_report_author", "same_context",
                "subject_continuity", "derivation_kind", "intent", "target_refs",
                "protected_refs", "outcome", "outcome_verifier", "verification_result")

# Every condition `derive` reports. The payload always carries exactly these keys,
# so a check that is dropped cannot leave an unnoticed hole: the tests assert the
# reported key set equals this declaration.
ENFORCED_CONDITIONS = (
    "required_fields", "identifiers", "enum_membership", "intent_declaration",
    "context_declaration", "ref_cardinality", "chronology", "before_chronology",
    "single_advice", "measurable_outcome", "completed_proof", "asset_identity",
    "latency_consistency", "ref_resolution", "asset_match", "rights_resolution",
)

# Requirements that a record cannot answer for itself. Declared here so the gap is
# named in the output instead of being mistaken for a pass.
NOT_ENFORCED_CONDITIONS = (
    ("case_id",
     "required only for attempts in the locked blind set; membership of that set is not "
     "part of the record, and guessing it either way would invent a gate input"),
    ("proposed_protected_refs",
     "required for actions over entities; which actions those are, and whether a protected "
     "detail exists in the frame, is not derivable from the record"),
    ("proposal_generation_ref",
     "required for recall on a stale generation; staleness is a property of the runtime, "
     "not of the record"),
    ("protected_refs_emptiness",
     "an empty protected_refs is admissible only when no protected detail really exists; "
     "that claim is not verifiable from the record"),
    ("intent.intentional_semantics",
     "the boolean is checked for presence and type, but 'declared before the capture' is "
     "an assertion about ordering in the world, not a field"),
    ("refusal_reason_presence",
     "§2.3 states the reason is never demanded, so an absent reason is not a violation; "
     "only its value is checked when present"),
    ("keep_attempt_outcome",
     "a KEEP attempt needs no after side (§2.4, §3 closing paragraph), but which outcome "
     "and verifier a KEEP may carry is not settled in the contract"),
    ("validity",
     "shot-list §2 validity is a separate axis; see payload.validity_checked"),
)


class InputError(Exception):
    pass


def _load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except (OSError, json.JSONDecodeError) as error:
        return None, f"{path} unreadable: {error}"


def frozen_vocabulary(label_schema: Path | None = None,
                      shot_list: Path | None = None) -> tuple[dict[str, set[str]], list[str]]:
    """Closed vocabularies read from the frozen artifacts rather than re-typed here.

    Returns `(vocab, problems)`. A vocabulary that could not be read is simply
    absent, and every check that needed it reports `unresolved` — an empty list
    must never be able to make a check pass by having nothing to compare against.
    """
    problems: list[str] = []
    vocab: dict[str, set[str]] = {}

    payload, problem = _load_json(label_schema or DEFAULT_LABEL_SCHEMA)
    if problem:
        problems.append(problem)
    else:
        defs = payload.get("$defs") if isinstance(payload, dict) else None
        for key, source in (("action_id", "actionId"), ("verifier_id", "verifierId")):
            enum = (defs or {}).get(source, {}).get("enum") if isinstance(defs, dict) else None
            if isinstance(enum, list) and enum:
                vocab[key] = set(enum)
            else:
                problems.append(f"label-schema declares no non-empty {source} enum")

    try:
        text = (shot_list or DEFAULT_SHOT_LIST).read_text(encoding="utf-8")
    except OSError as error:
        problems.append(f"shot list unreadable: {error}")
    else:
        scenarios = set(re.findall(r"^\|\s*(SL-\d{2})\s*\|", text, re.M))
        if scenarios:
            vocab["shot_scenario"] = scenarios
        else:
            problems.append("shot list declares no scenarios")

    return vocab, problems


_VOCAB_CACHE: tuple[dict[str, set[str]], list[str]] | None = None


def _cached_vocabulary() -> tuple[dict[str, set[str]], list[str]]:
    global _VOCAB_CACHE
    if _VOCAB_CACHE is None:
        _VOCAB_CACHE = frozen_vocabulary()
    return _VOCAB_CACHE


def _parse_utc(value) -> datetime | None:
    if not isinstance(value, str) or not UTC_Z.match(value):
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None


def _non_empty_text(value) -> bool:
    return isinstance(value, str) and value.strip() != ""


def _ref_list(value) -> list[str] | None:
    """Return the ref list, or None when the value is not a list of non-empty strings."""
    if not isinstance(value, list) or not value:
        return None
    if not all(_non_empty_text(item) for item in value):
        return None
    return [str(item) for item in value]


def derive(record: dict, resolution: dict | None,
           vocab: dict[str, set[str]] | None = None) -> dict:
    """Return {'status', 'reasons', 'conditions', 'is_success', 'not_enforced'}."""
    reasons: list[str] = []
    conditions: dict[str, str] = {name: "unresolved" for name in ENFORCED_CONDITIONS}

    def fail(condition: str, reason: str) -> None:
        conditions[condition] = "violated"
        reasons.append(reason)

    def ok(condition: str) -> None:
        if conditions.get(condition) != "violated":
            conditions[condition] = "met"

    if vocab is None:
        vocab, vocab_problems = _cached_vocabulary()
    else:
        vocab_problems = []
    vocab_problems = list(vocab_problems) + [
        f"frozen vocabulary for {key} is unavailable"
        for key in ("action_id", "verifier_id", "shot_scenario") if key not in vocab
    ]

    status_value = record.get("status")
    is_keep = record.get("proposed_action_id") == KEEP_ACTION
    missing: list[str] = []

    # 1. required fields present and non-null
    missing.extend(name for name in REQUIRED_TOP if record.get(name) in (None, ""))
    # a list-typed required field is not "present" merely because the key exists
    for name in ("proposed_target_refs", "target_refs"):
        if _ref_list(record.get(name)) is None:
            missing.append(f"{name} (needs a non-empty list of ids)")
    if record.get("status") == "completed":
        if not _non_empty_text(record.get("performed_change")):
            missing.append("performed_change")
        after = record.get("after")
        if not isinstance(after, dict) or not _non_empty_text(after.get("asset_id")):
            if not is_keep:
                missing.append("after")
    before = record.get("before") if isinstance(record.get("before"), dict) else {}
    for name, reason in (("asset_id", "before.asset_id"),
                         ("captured_at", "before.captured_at"),
                         ("sha256", "before.sha256")):
        if before.get(name) in (None, ""):
            missing.append(reason)
    after = record.get("after") if isinstance(record.get("after"), dict) else {}
    if status_value == "completed" and not is_keep and after.get("captured_at") in (None, ""):
        missing.append("after.captured_at (required for status=completed)")
    if status_value in PERFORMED_AT_REQUIRED and record.get("performed_at") in (None, ""):
        missing.append("performed_at (required for status=" + str(status_value) + ")")
    if missing:
        fail("required_fields", f"missing or null required field(s): {sorted(set(missing))}")
    else:
        ok("required_fields")

    # 1b. identifiers carry a declared shape
    identifiers_ok = True
    if not ATTEMPT_ID.match(str(record.get("attempt_id") or "")):
        fail("identifiers", f"attempt_id={record.get('attempt_id')!r} does not match "
                            f"{ATTEMPT_ID.pattern}")
        identifiers_ok = False
    if "shot_scenario" in vocab:
        if record.get("shot_scenario_id") not in vocab["shot_scenario"]:
            fail("identifiers", f"shot_scenario_id={record.get('shot_scenario_id')!r} is not one of "
                                f"{sorted(vocab['shot_scenario'])}")
            identifiers_ok = False
    if identifiers_ok:
        ok("identifiers")

    # 2. closed enums; nothing defaults silently
    closed_fields = (
        ("matrix_class", MATRIX_CLASSES), ("split", SPLITS), ("status", STATUSES),
        ("understood", UNDERSTOOD), ("executable", EXECUTABLE), ("outcome", OUTCOMES),
    )
    if record.get("measurement") is not None:
        closed_fields += (("measurement", MEASUREMENTS),)
    for field, allowed in closed_fields:
        if record.get(field) not in allowed:
            fail("enum_membership", f"{field}={record.get(field)!r} is not in {sorted(allowed)}")
    if record.get("verification_result") not in VERIFICATION_RESULTS:
        fail("enum_membership",
             f"verification_result={record.get('verification_result')!r} is not in "
             f"{sorted(VERIFICATION_RESULTS)}")
    if record.get("subject_continuity") not in SUBJECT_CONTINUITY:
        fail("enum_membership", f"subject_continuity={record.get('subject_continuity')!r} "
                                f"is not in {sorted(SUBJECT_CONTINUITY)}")
    if record.get("derivation_kind") not in DERIVATION_KINDS:
        fail("enum_membership", f"derivation_kind={record.get('derivation_kind')!r} "
                                f"is not in {sorted(DERIVATION_KINDS)}")
    if record.get("refusal_reason_source") not in REFUSAL_SOURCES:
        fail("enum_membership", f"refusal_reason_source={record.get('refusal_reason_source')!r} "
                                f"is not in {sorted(REFUSAL_SOURCES)}")
    if record.get("refusal_reason") is not None and record.get("refusal_reason") not in REFUSAL_REASONS:
        fail("enum_membership", f"refusal_reason={record.get('refusal_reason')!r} is not in "
                                f"{sorted(REFUSAL_REASONS)}")
    intent = record.get("intent")
    if not isinstance(intent, dict):
        fail("enum_membership", "intent must be an object")
    else:
        if intent.get("style_id") not in STYLE_IDS:
            fail("enum_membership", f"intent.style_id={intent.get('style_id')!r} is not a style id")
        if intent.get("basis") not in INTENT_BASIS:
            fail("enum_membership", f"intent.basis={intent.get('basis')!r} is not a basis")

    # 2b. actions and verifiers come from the frozen vocabularies, not free text
    for field, key in (("proposed_action_id", "action_id"), ("outcome_verifier", "verifier_id")):
        value = record.get(field)
        if key in vocab:
            if value not in vocab[key]:
                fail("enum_membership", f"{field}={value!r} is not in the frozen {key} vocabulary")
        elif value is not None:
            fail("enum_membership", f"{field} cannot be checked: frozen {key} vocabulary unavailable")
    performed_action = record.get("performed_action_id")
    if performed_action is not None:
        if "action_id" in vocab:
            if performed_action not in vocab["action_id"]:
                fail("enum_membership",
                     f"performed_action_id={performed_action!r} is not in the frozen action_id vocabulary")
        else:
            fail("enum_membership", "performed_action_id cannot be checked: vocabulary unavailable")
    ok("enum_membership")

    # 2c. intent.intentional is a required boolean, not a truthy string
    if not isinstance(intent, dict) or not isinstance(intent.get("intentional"), bool):
        fail("intent_declaration",
             f"intent.intentional={intent.get('intentional') if isinstance(intent, dict) else None!r} "
             f"is not a boolean")
    else:
        ok("intent_declaration")

    # 2d. same_context must be exactly true (§2.4 types it `true`)
    if record.get("same_context") is not True:
        fail("context_declaration",
             f"same_context={record.get('same_context')!r}: the record must assert one source/take family")
    else:
        ok("context_declaration")

    # 2e. ref lists that exist must not be empty where §2 requires at least one
    short = [name for name in ("target_refs", "proposed_target_refs")
             if _ref_list(record.get(name)) is None]
    if short:
        fail("ref_cardinality",
             f"{short} must be a non-empty list of ids (at least one addressee)")
    else:
        ok("ref_cardinality")

    # 3. strictly increasing UTC timestamps (§3 condition 3)
    captured = _parse_utc(record.get("captured_at"))
    proposed = _parse_utc(record.get("proposed_at"))
    performed = _parse_utc(record.get("performed_at"))
    after_at = _parse_utc(after.get("captured_at"))
    chain = [("captured_at", captured), ("proposed_at", proposed)]
    if performed is not None:
        chain.append(("performed_at", performed))
    if after_at is not None:
        chain.append(("after.captured_at", after_at))
    if any(value is None for _, value in chain):
        fail("chronology", "a timestamp is not a valid UTC Z value")
    else:
        stamps = [value for _, value in chain]
        if any(later <= earlier for earlier, later in zip(stamps, stamps[1:])):
            fail("chronology", "timestamps do not strictly increase: "
                               + " < ".join(name for name, _ in chain))
        else:
            ok("chronology")

    # 3b. the before side precedes the advice and the after side (§2.4)
    before_at = _parse_utc(before.get("captured_at"))
    if before_at is None:
        fail("before_chronology", "before.captured_at is not a valid UTC Z value")
    elif proposed is None:
        fail("before_chronology", "proposed_at is not a valid UTC Z value")
    elif before_at >= proposed:
        fail("before_chronology",
             "before.captured_at must precede proposed_at (the before frame predates the advice)")
    elif after_at is not None and after_at <= before_at:
        fail("before_chronology", "after.captured_at must follow before.captured_at")
    else:
        ok("before_chronology")

    # 6. one admitted command, with the text that was actually shown
    advice_count = record.get("advice_count")
    if isinstance(advice_count, bool) or not isinstance(advice_count, int) or advice_count != 1:
        fail("single_advice", f"advice_count={advice_count!r}, must be the integer 1")
    elif not _non_empty_text(record.get("proposed_action_text")):
        fail("single_advice", "proposed_action_text is empty: no shown advice to evaluate")
    else:
        ok("single_advice")

    # 7. measurable outcomes require the measurable evidence
    if record.get("outcome") in MEASURABLE_OUTCOMES and not is_keep:
        wrong = []
        if record.get("verification_result") != "pass":
            wrong.append(f"verification_result={record.get('verification_result')!r} (needs pass)")
        if record.get("measurement") != "before_after":
            wrong.append(f"measurement={record.get('measurement')!r} (needs before_after)")
        if record.get("subject_continuity") != "same":
            wrong.append(f"subject_continuity={record.get('subject_continuity')!r} (needs same)")
        if wrong:
            fail("measurable_outcome", "; ".join(wrong))
        else:
            ok("measurable_outcome")
    else:
        ok("measurable_outcome")

    # 8. a completed attempt carries the after side and what actually changed
    if record.get("status") == "completed":
        if not _non_empty_text(record.get("performed_change")):
            fail("completed_proof", "status=completed requires a non-empty performed_change")
        elif not is_keep and not _non_empty_text(after.get("asset_id")):
            fail("completed_proof", "status=completed requires an after side")
        else:
            ok("completed_proof")
    else:
        ok("completed_proof")

    # 5a. both sides present, valid digests, and not the same asset
    before_sha, after_sha = before.get("sha256"), after.get("sha256")
    if not SHA256.match(str(before_sha or "")):
        fail("asset_identity", "before.sha256 is not a lowercase sha256")
    elif not is_keep and record.get("status") == "completed" and not SHA256.match(str(after_sha or "")):
        fail("asset_identity", "after.sha256 is not a lowercase sha256")
    elif before_sha is not None and before_sha == after_sha:
        fail("asset_identity", "before.sha256 == after.sha256: this is not an episode")
    else:
        ok("asset_identity")

    # 2.6. latency fields are declared by formula; check the arithmetic, not just the type
    latency_mismatch: list[str] = []
    for field, end, label in (("action_latency_ms", performed, "performed_at - proposed_at"),
                              ("result_latency_ms", after_at, "after.captured_at - proposed_at")):
        value = record.get(field)
        if value is None:
            continue
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            latency_mismatch.append(f"{field}={value!r} must be a non-negative integer")
        elif proposed is not None and end is not None:
            expected = int((end - proposed).total_seconds() * 1000)
            if value != expected:
                latency_mismatch.append(f"{field}={value} but {label} is {expected}")
    if latency_mismatch:
        fail("latency_consistency", "; ".join(latency_mismatch))
    else:
        ok("latency_consistency")

    # 4, 5b, 9. external resolutions: supplied, or explicitly unresolved
    supplied = resolution or {}
    entity_refs = set(supplied.get("entity_refs") or [])
    asset_digests = set(supplied.get("asset_sha256") or [])
    admitted_consents = set(supplied.get("admitted_consents") or [])
    admitted_rights = set(supplied.get("admitted_rights") or [])

    unresolved: list[str] = []

    refs = list(_ref_list(record.get("target_refs")) or []) \
        + list(_ref_list(record.get("proposed_target_refs")) or []) \
        + list(record.get("protected_refs") or [])
    if not entity_refs:
        unresolved.append("target/protected refs not resolved (no entity_refs supplied)")
    else:
        dangling = sorted({ref for ref in refs if ref not in entity_refs})
        if dangling:
            fail("ref_resolution", f"refs do not resolve to real entities: {dangling}")
        else:
            ok("ref_resolution")

    if not asset_digests:
        unresolved.append("asset digests not supplied (before/after were not matched to real files)")
    else:
        mismatched = sorted(sha for sha in (before_sha, after_sha)
                            if sha and sha not in asset_digests)
        if mismatched:
            fail("asset_match", f"digests do not match real assets: {mismatched}")
        else:
            ok("asset_match")

    if not admitted_consents or not admitted_rights:
        unresolved.append("consent/rights admission not supplied")
    else:
        if record.get("consent_record_id") not in admitted_consents:
            fail("rights_resolution", f"consent_record_id={record.get('consent_record_id')!r} is not admitted")
        elif record.get("rights_record_id") not in admitted_rights:
            fail("rights_resolution", f"rights_record_id={record.get('rights_record_id')!r} is not admitted")
        else:
            ok("rights_resolution")

    reasons.extend(f"unresolved: {item}" for item in vocab_problems)
    reasons.extend(f"unresolved: {item}" for item in unresolved)
    status = "complete" if not reasons else "incomplete"
    # A record can be complete and still not be a success: declined/cancelled are
    # valid records, they just do not become executed episodes. §3 keeps status and
    # success apart, so they are reported as separate axes rather than folded in.
    # A KEEP attempt is the same shape: a complete record that executed no episode.
    is_success = status == "complete" and record.get("status") == "completed" and not is_keep
    return {"status": status, "reasons": reasons, "conditions": conditions,
            "is_success": is_success, "is_keep": is_keep,
            "not_enforced": list(NOT_ENFORCED_CONDITIONS)}


def _load_records(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        raise InputError(f"{path} is empty")
    if path.suffix == ".jsonl":
        records = []
        for number, line in enumerate(text.splitlines(), start=1):
            if not line.strip():
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError as error:
                raise InputError(f"{path}:{number} is not JSON: {error}") from error
            if not isinstance(item, dict):
                raise InputError(f"{path}:{number} is not a JSON object")
            records.append(item)
        if not records:
            raise InputError(f"{path} contains no records")
        return records
    payload = json.loads(text)
    if isinstance(payload, dict):
        return [payload]
    if isinstance(payload, list) and payload and all(isinstance(item, dict) for item in payload):
        return payload
    raise InputError(f"{path} must be an attempt object, a non-empty array, or JSONL")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--record", type=Path)
    source.add_argument("--records", type=Path)
    parser.add_argument("--resolution", type=Path,
                        help="entity refs, asset digests and admitted consent/rights records")
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)

    try:
        records = _load_records(args.record or args.records)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    resolution = None
    if args.resolution is not None:
        try:
            resolution = json.loads(args.resolution.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"FAIL CLOSED: resolution is unreadable: {error}", file=sys.stderr)
            return 2
        if not isinstance(resolution, dict):
            print("FAIL CLOSED: resolution must be a JSON object", file=sys.stderr)
            return 2

    vocab, vocab_problems = _cached_vocabulary()
    for problem in vocab_problems:
        print(f"WARNING: {problem}", file=sys.stderr)

    results = []
    overclaim = 0
    for record in records:
        derived = derive(record, resolution, vocab)
        claimed = record.get("record_status")
        contradiction = claimed == "complete" and derived["status"] != "complete"
        if contradiction:
            overclaim += 1
        results.append({
            "attempt_id": record.get("attempt_id"),
            "claimed_record_status": claimed,
            "derived_record_status": derived["status"],
            "derived_is_success": derived["is_success"],
            "derived_is_keep": derived["is_keep"],
            "contradicts_claim": contradiction,
            "conditions": derived["conditions"],
            "reasons": derived["reasons"],
            "validity_checked": False,
        })
        verdict = "COMPLETE" if derived["status"] == "complete" else "INCOMPLETE"
        success = "success" if derived["is_success"] else f"not a success (status={record.get('status')!r})"
        print(f"{record.get('attempt_id')}: {verdict} | {success}")
        if contradiction:
            print("  CONTRADICTS the asserted record_status='complete'")
        for reason in derived["reasons"]:
            print(f"  - {reason}")

    payload = {
        "schema_id": "camera-attempt-status-derivation",
        "schema_version": "1.1.0",
        "resolution_supplied": resolution is not None,
        "validity_checked": False,
        "note": "record_status only; shot-list validity is a separate axis and is not checked here",
        "enforced_conditions": sorted(ENFORCED_CONDITIONS),
        "frozen_vocabulary": {key: len(value) for key, value in sorted(vocab.items())},
        "vocabulary_problems": vocab_problems,
        "conditions_not_enforced": [{"condition": name, "why": why}
                                    for name, why in NOT_ENFORCED_CONDITIONS],
        "results": results,
    }
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")
    print(f"records={len(results)} complete="
          f"{sum(1 for item in results if item['derived_record_status'] == 'complete')} "
          f"successes={sum(1 for item in results if item['derived_is_success'])} "
          f"overclaimed={overclaim}")
    print(f"enforced_conditions={len(ENFORCED_CONDITIONS)} "
          f"not_enforced={len(NOT_ENFORCED_CONDITIONS)} "
          f"frozen_vocabulary=" + ",".join(f"{key}:{len(value)}" for key, value in sorted(vocab.items())))
    return 1 if overclaim else 0


if __name__ == "__main__":
    sys.exit(main())
