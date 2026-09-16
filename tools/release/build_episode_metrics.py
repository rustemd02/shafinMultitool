#!/usr/bin/env python3
"""Derive the episode-side §5 blocks: confusion matrix and false-improved.

`false_improved` is the gate that keeps "the frame moved" from reading as "the
advice worked": it compares what the app claimed (its verifier's `improved`
verdict, `ActionVerifier.swift` lines 424-455) against what an independent
evaluation says actually happened (the episode `outcome` vocabulary in
`datasets/camera-coach/v1/episode-schema.json`: correct / no_op / opposite /
overshoot / track_loss / incomparable).

Nothing produced this block before, and it is the one place where a missing truth
value is dangerous: if an unverified episode is allowed into the denominators, the
error rate can be made to look better by simply not checking. So the rule here is
strict:

* every episode where the app claimed improvement must carry an established
  independent truth, otherwise the tool refuses (exit 2) and names how many and
  which episodes are unverified;
* episodes with no truth and no improvement claim are counted separately as
  `truth_unestablished`, never folded into a denominator;
* `incomparable` stays in the confusion matrix, and a record cannot be both
  comparable and incomparable.

Both false-improved ratios are emitted. Under this derivation they share a
numerator (an improved claim contradicted by the truth); §5.1 gives them different
denominators, which is what the two published ratios are for. If a future evaluator
distinguishes the numerators, this tool has to be updated rather than assumed.

Exit codes
    0  the blocks were derived
    1  the data cannot support the claim (e.g. zero improved issued)
    2  an input is missing, unreadable, or a required truth value is absent

Usage
    python3 tools/release/build_episode_metrics.py --episodes episodes.jsonl --out blocks.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

CONFUSION_BUCKETS = ("correct", "keep", "abstain", "incomparable", "forbidden_advised")
# the app verifier's decision, reduced to what the block needs
IMPROVEMENT_CLAIM = {"improved", "unchanged", "worse", "incomparable"}
EPISODE_OUTCOMES = {"correct", "no_op", "opposite", "overshoot", "track_loss", "incomparable"}
TRUTH_IMPROVED = {"correct": True, "no_op": False, "opposite": False, "overshoot": False,
                  "track_loss": False, "incomparable": None}

REQUIRED_FIELDS = ("episode_id", "cluster_id", "app_decision", "app_verifier_outcome",
                   "truth_outcome", "expected_action_family", "advised_action_family")


class InputError(Exception):
    pass


def load_episodes(path: Path) -> list[dict]:
    if not path.is_file():
        raise InputError(f"episodes not found: {path}")
    episodes, seen = [], set()
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise InputError(f"{path}:{number} is not JSON: {error}") from error
        if not isinstance(record, dict):
            raise InputError(f"{path}:{number} is not an object")
        missing = [field for field in REQUIRED_FIELDS if not record.get(field)]
        if missing:
            raise InputError(f"{path}:{number} lacks {missing}")
        episode_id = str(record["episode_id"])
        if episode_id in seen:
            raise InputError(f"{path}:{number} repeats episode_id {episode_id}")
        seen.add(episode_id)
        if record["app_decision"] not in CONFUSION_BUCKETS:
            raise InputError(f"{path}:{number} app_decision={record['app_decision']!r} is not one "
                             f"of {sorted(CONFUSION_BUCKETS)}")
        if record["app_verifier_outcome"] not in IMPROVEMENT_CLAIM:
            raise InputError(f"{path}:{number} app_verifier_outcome="
                             f"{record['app_verifier_outcome']!r} is not one of "
                             f"{sorted(IMPROVEMENT_CLAIM)}")
        if record["truth_outcome"] not in EPISODE_OUTCOMES:
            raise InputError(f"{path}:{number} truth_outcome={record['truth_outcome']!r} is not one "
                             f"of {sorted(EPISODE_OUTCOMES)}")
        if record["app_decision"] == "incomparable" and record["app_verifier_outcome"] != "incomparable":
            raise InputError(f"{path}:{number} is flagged incomparable while the verifier reported "
                             f"{record['app_verifier_outcome']!r}: an episode cannot be both")
        episodes.append(record)
    if not episodes:
        raise InputError(f"{path} carries no episodes: an empty evaluation is not a result")
    return episodes


def derive(episodes: list[dict]) -> dict:
    unverified = []
    for record in episodes:
        claimed = record["app_verifier_outcome"] == "improved"
        truth = TRUTH_IMPROVED[record["truth_outcome"]]
        if claimed and truth is None:
            unverified.append(str(record["episode_id"]))
    if unverified:
        raise InputError(f"{len(unverified)} episode(s) where the app claimed improvement have no "
                         f"established truth (e.g. {unverified[:5]}); an unverified improvement "
                         "cannot enter the false-improved denominators")

    confusion = dict.fromkeys(CONFUSION_BUCKETS, 0)
    for record in episodes:
        confusion[record["app_decision"]] += 1
    evaluated_total = sum(confusion.values())

    issued = [record for record in episodes if record["app_verifier_outcome"] == "improved"]
    wrong = [record for record in issued if TRUTH_IMPROVED[record["truth_outcome"]] is False]
    truly_non_improved = [record for record in episodes
                          if TRUTH_IMPROVED[record["truth_outcome"]] is False]
    truth_unestablished = [record for record in episodes
                           if TRUTH_IMPROVED[record["truth_outcome"]] is None]

    # Only the episode floors are emitted here. `per_action_counts.<action>.train_positives`
    # is a §5.2 quota over training positives, which still rows cannot know: putting an
    # episode count under that key would satisfy a floor with the wrong quantity. The
    # episode positives are reported separately instead.
    per_action: dict[str, dict] = {}
    positives_by_action: dict[str, int] = {}
    for record in episodes:
        family = record["expected_action_family"]
        bucket = per_action.setdefault(family, {"episodes": {"improved": 0,
                                                            "unchanged_or_worse": 0,
                                                            "incomparable": 0}})
        positives_by_action[family] = positives_by_action.get(family, 0) + 1
        if record["truth_outcome"] == "correct":
            bucket["episodes"]["improved"] += 1
        elif record["truth_outcome"] == "incomparable":
            bucket["episodes"]["incomparable"] += 1
        else:
            bucket["episodes"]["unchanged_or_worse"] += 1

    return {
        "confusion": {**{key: confusion[key] for key in CONFUSION_BUCKETS},
                      "evaluated_total": evaluated_total},
        "false_improved": {
            "wrong_confirmations": len(wrong),
            "improved_issued": len(issued),
            "wrong_improved": len(wrong),
            "non_improved_episodes": len(truly_non_improved),
            "incomparable_in_confusion": confusion["incomparable"] > 0,
            "truth_unestablished": len(truth_unestablished),
        },
        "per_action_counts": {family: {"episodes": counts["episodes"]}
                              for family, counts in sorted(per_action.items())},
        "episode_positives_by_action": dict(sorted(positives_by_action.items())),
        "cluster_count": len({record["cluster_id"] for record in episodes}),
        "decisions": dict(sorted(Counter(record["app_verifier_outcome"]
                                         for record in episodes).items())),
        "truth_outcomes": dict(sorted(Counter(record["truth_outcome"]
                                             for record in episodes).items())),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--episodes", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    try:
        episodes = load_episodes(args.episodes)
        derived = derive(episodes)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    payload = {
        "schema_id": "camera-episode-blocks",
        "schema_version": "1.0.0",
        "source": {"path": str(args.episodes), "episodes": len(episodes)},
        "definitions": {
            "app_claim": "the app verifier's `improved` verdict (ActionVerifier.swift:424-455)",
            "truth": "the episode outcome vocabulary (episode-schema.json: correct/no_op/opposite/"
                     "overshoot/track_loss/incomparable)",
            "wrong": "an improved claim whose established truth is not `correct`",
            "incomparable_stays_in_matrix": True,
            "unverified_improvements_refused": True,
        },
        **derived,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(text)

    fi = derived["false_improved"]
    print(f"EPISODES total={derived['confusion']['evaluated_total']} "
          f"improved_issued={fi['improved_issued']} wrong={fi['wrong_confirmations']} "
          f"non_improved={fi['non_improved_episodes']} "
          f"truth_unestablished={fi['truth_unestablished']} clusters={derived['cluster_count']}")
    if fi["improved_issued"] == 0:
        print("FAIL: no improved episode was issued, so precision is undefined and the "
              "false-improved gate cannot pass (coverage is not satisfied by silence)",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
