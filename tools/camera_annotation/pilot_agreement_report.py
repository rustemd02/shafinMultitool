#!/usr/bin/env python3
"""Agreement report for the Camera Coach annotation pilot (R13 preparation).

Reads the append-only vote store produced by annotate_camera.py (never
modifies it) and reports per-record verdict distributions, pairwise annotator
agreement, and Fleiss' kappa over the good/bad/abstain verdicts for records
with at least two votes.

Two independence rules are enforced rather than assumed:

* An assisted vote is not an independent annotator, so it never enters the
  agreement or kappa input (M3-022).
* One rater contributes at most one verdict per record. If the same
  `annotator_id` voted twice on a record, the later vote is the recorded
  decision and the earlier one is reported as a revision - it must not turn a
  single person into a two-rater panel, which would let one human reach
  kappa=1.0 by agreeing with themselves.

This report measures annotation agreement mechanics only. It is not a quality
metric for the app and not human-gold evidence.

Exit codes
    0  a report was produced (it may legitimately say agreement is unavailable)
    2  the store is unreadable, or a vote carries a value outside the closed
       verdict set - the report refuses instead of quietly dropping it
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path

from annotate_camera import VOTE_VERDICTS, load_store

CATEGORIES = sorted(VOTE_VERDICTS)


def fleiss_kappa(vote_matrix: list[list[int]], categories: int) -> float | None:
    """Fleiss' kappa over records with exactly two raters.

    Fleiss' kappa assumes a constant number of raters per subject, so records
    with more (or fewer) than two raters are excluded from this statistic and
    reported separately. The caller is responsible for the stronger
    precondition that those two raters are two different people.
    """
    rows = [row for row in vote_matrix if sum(row) == 2]
    if not rows:
        return None
    n = 2
    total_assignments = len(rows) * n
    category_proportions = [
        sum(row[c] for row in rows) / total_assignments for c in range(categories)
    ]
    p_expected = sum(p * p for p in category_proportions)
    p_observed = sum(
        (sum(c * (c - 1) for c in row) / (n * (n - 1))) for row in rows
    ) / len(rows)
    if p_expected == 1.0:
        return None
    return (p_observed - p_expected) / (1.0 - p_expected)


def latest_votes(independent_votes: list[dict]) -> tuple[dict[str, dict[str, dict]], Counter]:
    """One rater, one verdict per record: the latest vote is the decision.

    Returns `(by_record, revisions)`. `by_record[record_id]` maps annotator id to
    that annotator's latest vote, so a repeated vote can never be counted as a
    second rater. `revisions` counts the earlier votes it replaced.
    """
    ordered = sorted(range(len(independent_votes)),
                     key=lambda index: (independent_votes[index].get("created_at", ""), index))
    by_record: dict[str, dict[str, dict]] = defaultdict(dict)
    revisions: Counter = Counter()
    for index in ordered:
        vote = independent_votes[index]
        record_id, annotator = vote["record_id"], vote["annotator_id"]
        if annotator in by_record[record_id]:
            revisions[record_id] += 1
        by_record[record_id][annotator] = vote
    return by_record, revisions


def _read_votes(records: list[dict]) -> tuple[list[dict], str | None]:
    """Select the votes, refusing any value outside the closed vocabulary."""
    votes = [record for record in records if record.get("record_type") == "vote"]
    malformed = [index for index, vote in enumerate(votes, start=1)
                 if not vote.get("record_id") or not vote.get("annotator_id")]
    if malformed:
        return [], f"vote #{malformed[0]} has no record_id/annotator_id"
    unknown = sorted({vote.get("verdict") for vote in votes if vote.get("verdict") not in VOTE_VERDICTS})
    if unknown:
        return [], (f"verdict(s) {unknown} are outside the closed set {CATEGORIES}; "
                    "refusing rather than dropping them from the denominators")
    return votes, None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--store", type=Path, required=True)
    parser.add_argument("--sample", type=Path, default=None, help="pilot sample jsonl for coverage")
    parser.add_argument("--out", type=Path, default=None, help="write markdown report here")
    parser.add_argument("--json-out", type=Path, default=None, help="write the numbers here")
    args = parser.parse_args(argv)

    try:
        records = load_store(args.store)
    except (OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2
    votes, problem = _read_votes(records)
    if problem:
        print(f"FAIL CLOSED: {problem}", file=sys.stderr)
        return 2

    adjudications = [record for record in records if record.get("record_type") == "adjudication"]
    # An assisted vote is not an independent annotator. Independence (the M3-022
    # gold gate) may only be computed over unassisted votes; assisted ones are
    # reported separately and never inflate the annotator count.
    assisted_votes = [vote for vote in votes if vote.get("assisted")]
    independent_votes = [vote for vote in votes if not vote.get("assisted")]
    by_record, revisions = latest_votes(independent_votes)

    annotators = sorted({vote["annotator_id"] for vote in independent_votes})
    co_voting_records = sorted(rid for rid, raters in by_record.items() if len(raters) >= 2)
    # Two ids are not yet an independent panel: at least one record has to have
    # been rated by two different people, otherwise there is no pair to measure.
    independent_ready = len(annotators) >= 2 and bool(co_voting_records)

    record_lines = []
    matrix: list[list[int]] = []
    unanimous = 0
    needs_adjudication = []
    for record_id in sorted(by_record):
        raters = by_record[record_id]
        counts = Counter(vote["verdict"] for vote in raters.values())
        row = [counts.get(verdict, 0) for verdict in CATEGORIES]
        matrix.append(row)
        distinct = len([c for c in counts.values() if c > 0])
        if len(raters) >= 2 and distinct == 1:
            unanimous += 1
        if len(raters) >= 2 and distinct > 1:
            needs_adjudication.append((record_id, dict(counts)))
        distribution = ", ".join(f"{verdict}={counts[verdict]}" for verdict in CATEGORIES if counts[verdict])
        annotation = "unanimous" if distinct == 1 else "split"
        if revisions.get(record_id):
            annotation += f"; +{revisions[record_id]} повторных голосов (учтён последний)"
        record_lines.append(f"| {record_id} | {len(raters)} | {distribution} | {annotation} |")

    pairwise: Counter = Counter()
    pair_totals: Counter = Counter()
    for annotator_a, annotator_b in combinations(annotators, 2):
        for raters in by_record.values():
            verdicts = {annotator: vote["verdict"] for annotator, vote in raters.items()}
            if annotator_a not in verdicts or annotator_b not in verdicts:
                continue
            pair_totals[(annotator_a, annotator_b)] += 1
            if verdicts[annotator_a] == verdicts[annotator_b]:
                pairwise[(annotator_a, annotator_b)] += 1

    kappa = fleiss_kappa(matrix, len(CATEGORIES)) if independent_ready else None
    abstain_total = sum(1 for vote in votes if vote["verdict"] == "abstain")
    abstain_by_annotator = Counter(
        vote["annotator_id"] for vote in votes if vote["verdict"] == "abstain"
    )

    sample_count = None
    if args.sample is not None:
        sample_count = sum(
            1 for line in args.sample.read_text(encoding="utf-8").splitlines() if line.strip()
        )

    if independent_ready:
        independence_line = (
            f"- Независимых аннотаторов: {len(annotators)} — согласие считается только по неassisted "
            f"голосам; записей с двумя разными аннотаторами: {len(co_voting_records)}."
        )
    elif len(annotators) >= 2:
        independence_line = (
            f"- Независимое согласие НЕДОСТУПНО: есть {len(annotators)} разных `annotator_id`, но ни "
            "одной записи, где голосовали двое разных аннотаторов. κ по таким данным измерял бы "
            "самосогласие одного человека, а не согласие между людьми, поэтому не приводится."
        )
    else:
        independence_line = (
            f"- Независимое согласие НЕДОСТУПНО: независимых аннотаторов {len(annotators)} (<2). "
            "Подсказки ИИ и один человек не образуют двух независимых аннотаторов (M3-022), "
            "поэтому κ не приводится, пока нет второго независимого голоса."
        )
    lines = [
        "# Camera Coach annotation pilot — agreement report",
        "",
        "Механика согласованности разметки. Не метрика качества приложения, не human-gold evidence.",
        "Подсказанные (assisted) голоса исключены из согласия: они не являются независимым аннотатором.",
        "Повторный голос одного аннотатора по записи не создаёт второго оценщика: учитывается последний.",
        "",
        f"- Store: `{args.store}`; голосов: {len(votes)} (независимых {len(independent_votes)}, "
        f"assisted {len(assisted_votes)}) от {len(annotators)} независимых аннотаторов; адъюдикаций: {len(adjudications)}.",
        f"- Записей с голосами: {len(by_record)}; из них с ≥2 разными аннотаторами: {len(co_voting_records)}"
        + (f" из {sample_count} в sample (покрытие {len(by_record) / sample_count:.0%})." if sample_count else "."),
        f"- Единогласных (≥2 голоса): {unanimous}; спорных (≥2 голоса, расхождение): {len(needs_adjudication)}.",
        independence_line,
        f"- Fleiss' κ по записям ровно с 2 голосами (good/bad/abstain): "
        + ("n/a" if kappa is None else f"{kappa:.3f}"),
    ]
    if revisions:
        lines.append(
            f"- Повторных голосов одного аннотатора по одной записи: {sum(revisions.values())} "
            f"в {len(revisions)} записях — второй оценщик из них не создаётся."
        )
    if assisted_votes:
        lines.append("")
        lines.append("## Assisted-голоса (не считаются независимыми)")
        lines.append("")
        assisted_by_source = Counter(
            vote.get("assist_source", "unknown") for vote in assisted_votes
        )
        for source in sorted(assisted_by_source):
            lines.append(f"- источник `{source}`: {assisted_by_source[source]} голосов")
    if annotators:
        lines.append("")
        lines.append("## По парам аннотаторов")
        lines.append("")
        lines.append("| Пара | Совпало | Записей вместе | % |")
        lines.append("|---|---|---|---|")
        for pair in sorted(pair_totals):
            agreement = f"{100.0 * pairwise[pair] / pair_totals[pair]:.0f}%"
            lines.append(f"| {pair[0]} vs {pair[1]} | {pairwise[pair]} | {pair_totals[pair]} | {agreement} |")
        if not pair_totals:
            lines.append("| — | — | 0 | n/a (нет общих записей) |")
    if record_lines:
        lines.append("")
        lines.append("## По записям")
        lines.append("")
        lines.append("| Запись | Голосов | Вердикты | Статус |")
        lines.append("|---|---|---|---|")
        lines.extend(record_lines)
    if needs_adjudication:
        lines.append("")
        lines.append("## Нужна адъюдикация")
        lines.append("")
        for record_id, counts in needs_adjudication:
            lines.append(f"- `{record_id}`: {counts}")
    if abstain_total:
        lines.append("")
        lines.append("## Abstain")
        lines.append(f"- всего abstain: {abstain_total} ({abstain_total / max(len(votes), 1):.0%})")
        for annotator in sorted(abstain_by_annotator):
            lines.append(f"- {annotator}: {abstain_by_annotator[annotator]}")

    report = "\n".join(lines) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(report)
    if args.json_out is not None:
        payload = {
            "schema_id": "camera-annotation-agreement",
            "schema_version": "1.0.0",
            "votes": len(votes),
            "independent_votes": len(independent_votes),
            "assisted_votes": len(assisted_votes),
            "independent_annotators": len(annotators),
            "records_with_votes": len(by_record),
            "records_with_two_distinct_annotators": len(co_voting_records),
            "independent_ready": independent_ready,
            "repeated_votes_replaced": sum(revisions.values()),
            "fleiss_kappa": kappa,
            "note": "agreement mechanics only; not human-gold evidence and not a quality metric",
        }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
