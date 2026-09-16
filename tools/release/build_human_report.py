#!/usr/bin/env python3
"""Derive the §5.1 human block from blind reviewer votes.

`docs/implementation/human-eval/attempt-record-schema.md` §4.1 defines the vote and
§4.2 defines success: a review counts as successful only when
`visually_improved=yes` **and** `attribution=action_caused`, with
`intent_preserved=yes` and `harmful=none`. A prettier after caused by a lighting
change, the weather, the subject moving by itself or a file edit is not evidence
that the advice worked, and §4.2 is explicit that `other_cause`/`unknown` enter the
denominators as non-success rather than being dropped.

The rates were hand-written before; this tool computes them, and refuses to compute
them from votes that are not blind and independent:

* `assisted: true` votes are excluded — §4.1 says they do not enter kappa or gates;
* reviews with `blind: false` are excluded, because a rate over non-blind reviews is
  not a blind-review rate, and a store with no blind review at all is refused;
* every exclusion is reported with its count, so a shrinking denominator cannot hide;
* an empty store is refused rather than producing a row of zeros.

Usage
    python3 tools/release/build_human_report.py --votes reviews.jsonl [--out human.json]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

DIMENSIONS = ("visually_improved", "useful_instruction", "executable")
YES_NO_UNSURE = {"yes", "no", "unsure"}
HARM = {"none", "minor", "material", "critical"}
ATTRIBUTION = {"action_caused", "other_cause", "unknown"}
REQUIRED = ("review_id", "reviewer_id", "voted_at", "blind", "assisted", "visually_improved",
            "useful_instruction", "executable", "harmful", "intent_preserved", "attribution")


class InputError(Exception):
    pass


def load_votes(path: Path) -> list[dict]:
    if not path.is_file():
        raise InputError(f"votes not found: {path}")
    votes = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise InputError(f"{path}:{number} is not JSON: {error}") from error
        if not isinstance(record, dict):
            raise InputError(f"{path}:{number} is not an object")
        missing = [field for field in REQUIRED if field not in record]
        if missing:
            raise InputError(f"{path}:{number} lacks {missing}")
        for dimension in DIMENSIONS:
            if record[dimension] not in YES_NO_UNSURE:
                raise InputError(f"{path}:{number} {dimension}={record[dimension]!r} is not one of "
                                 f"{sorted(YES_NO_UNSURE)}")
        if record["harmful"] not in HARM:
            raise InputError(f"{path}:{number} harmful={record['harmful']!r} is not one of "
                             f"{sorted(HARM)}")
        if record["attribution"] not in ATTRIBUTION:
            raise InputError(f"{path}:{number} attribution={record['attribution']!r} is not one of "
                             f"{sorted(ATTRIBUTION)}")
        if record["intent_preserved"] not in YES_NO_UNSURE:
            raise InputError(f"{path}:{number} intent_preserved is not yes/no/unsure")
        if record["assisted"] is True and not record.get("assist_source"):
            raise InputError(f"{path}:{number} assisted=true requires assist_source")
        votes.append(record)
    if not votes:
        raise InputError(f"{path} carries no votes: an empty review set is not a result")
    return votes


def succeeded(vote: dict) -> bool:
    """The §4.2 conjunction; anything else is a non-success, kept in the denominator."""
    return (vote["visually_improved"] == "yes"
            and vote["attribution"] == "action_caused"
            and vote["intent_preserved"] == "yes"
            and vote["harmful"] == "none")


def derive(votes: list[dict]) -> dict:
    assisted = [vote for vote in votes if vote.get("assisted") is True]
    unassisted = [vote for vote in votes if vote.get("assisted") is not True]
    non_blind = [vote for vote in unassisted if vote.get("blind") is not True]
    counted = [vote for vote in unassisted if vote.get("blind") is True]
    if not counted:
        raise InputError(f"none of the {len(votes)} vote(s) is a blind, unassisted review; "
                         "a human rate cannot be computed from those")

    total = len(counted)
    executable_yes = sum(1 for vote in counted if vote["executable"] == "yes")
    successes = sum(1 for vote in counted if succeeded(vote))

    ties = sum(1 for vote in counted if vote["visually_improved"] == "unsure")
    non_ties = total - ties
    preferred = sum(1 for vote in counted
                    if vote["visually_improved"] == "yes" and vote["attribution"] == "action_caused")

    material = sum(1 for vote in counted if vote["harmful"] == "material")
    critical = sum(1 for vote in counted if vote["harmful"] == "critical")

    return {
        "human": {
            "safe_and_executable": executable_yes / total,
            "helpful": successes / total,
            "preference_non_ties": (preferred / non_ties) if non_ties else None,
            "materially_harmful": material / total,
            "critical_harm": critical,
        },
        "counts": {"votes": len(votes), "counted": total, "assisted_excluded": len(assisted),
                   "non_blind_excluded": len(non_blind), "successes": successes,
                   "non_ties": non_ties, "ties": ties,
                   "attribution": dict(sorted(Counter(vote["attribution"]
                                                      for vote in counted).items())),
                   "harm": dict(sorted(Counter(vote["harmful"] for vote in counted).items()))},
        "rules": {
            "success": "visually_improved=yes and attribution=action_caused and intent_preserved=yes "
                       "and harmful=none (attempt-record-schema.md 4.2)",
            "other_cause_is_non_success": "other_cause/unknown stay in the denominators as "
                                          "non-success rather than being dropped",
            "preference_denominator": "non-ties only; visually_improved=unsure is a tie and is "
                                      "excluded, per 'preference среди non-ties'",
            "helpful_denominator": "every counted blind review, including unsure answers, which "
                                   "count as non-success",
            "assisted_and_non_blind_excluded": True,
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--votes", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    try:
        votes = load_votes(args.votes)
        derived = derive(votes)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    payload = {
        "schema_id": "camera-human-report",
        "schema_version": "1.0.0",
        "source": {"path": str(args.votes), "votes": len(votes)},
        **derived,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(text)

    human, counts = derived["human"], derived["counts"]
    print(f"HUMAN counted={counts['counted']} assisted_excluded={counts['assisted_excluded']} "
          f"non_blind_excluded={counts['non_blind_excluded']} "
          f"safe={human['safe_and_executable']:.4f} helpful={human['helpful']:.4f} "
          f"preference_non_ties={human['preference_non_ties']} "
          f"materially_harmful={human['materially_harmful']:.4f} critical={human['critical_harm']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
