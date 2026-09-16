#!/usr/bin/env python3
"""Derive the §5.2 gold block from an annotation store.

The gold gate decides whether the human evidence is real: two independent humans,
κ ≥ 0.80 on KEEP/CORRECT/ABSTAIN, action-family κ ≥ 0.75, forbidden agreement
≥ 0.90, median ROI IoU ≥ 0.80, ≥5% hidden QC with ≥95% agreement, ≥10% adjudicated
re-review. Those numbers were hand-written before; this tool computes them from the
append-only store the annotation tooling already writes.

Two rules keep it honest:

* a value that the store cannot support is **not emitted**. The gate then reports it
  missing and fails, instead of reading a plausible default;
* the KEEP/CORRECT/ABSTAIN axis is read from the label invariants
  (`annotation_labels.py`: `unsure` ⇒ abstain, `improvement_needed=false` ⇒ keep
  with `actions == ['keep_current_setup']`, `improvement_needed=true` ⇒ correct).
  A store that only carries a `verdict` axis gets its κ reported under a different
  name, never under the gate's key, because mapping `good`→`keep` would be a
  translation nobody authorised.

Exit codes
    0  a gold block was derived
    1  fewer than two independent annotators, so independence cannot be claimed
    2  the store is missing, unreadable, or malformed

Usage
    python3 tools/release/build_gold_report.py --store labels.jsonl [--forbidden-actions f.json] \\
        --out gold.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

GATE_KEYS = ("annotators", "hidden_qc_rate", "adjudicated_review_rate",
             "kappa_keep_correct_abstain", "kappa_action_family", "forbidden_agreement",
             "median_roi_iou", "hidden_qc")
AXIS_LABELS = ("keep", "correct", "abstain")
KEEP_ACTION = "keep_current_setup"


class InputError(Exception):
    pass


def load_store(path: Path) -> list[dict]:
    if not path.is_file():
        raise InputError(f"store not found: {path}")
    records = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise InputError(f"{path}:{number} is not JSON: {error}") from error
        if not isinstance(record, dict):
            raise InputError(f"{path}:{number} is not an object")
        records.append(record)
    if not records:
        raise InputError(f"{path} carries no records")
    return records


def is_label(record: dict) -> bool:
    return "improvement_needed" in record


def is_vote(record: dict) -> bool:
    return record.get("record_type") == "vote" or "verdict" in record


def axis_of(record: dict) -> str | None:
    """KEEP/CORRECT/ABSTAIN from the label invariants, or None if not a label."""
    if not is_label(record):
        return None
    if record.get("unsure"):
        return "abstain"
    return "correct" if record.get("improvement_needed") else "keep"


def cohen_kappa(pairs: list[tuple[str, str]], categories: tuple[str, ...]) -> float | None:
    if not pairs:
        return None
    n = len(pairs)
    observed = sum(1 for a, b in pairs if a == b) / n
    counts_a = Counter(a for a, _ in pairs)
    counts_b = Counter(b for _, b in pairs)
    expected = sum((counts_a[c] / n) * (counts_b[c] / n) for c in categories)
    if expected >= 1.0:
        return None
    return (observed - expected) / (1.0 - expected)


def iou(rect_a: list, rect_b: list) -> float | None:
    ax, ay, aw, ah = (float(v) for v in rect_a)
    bx, by, bw, bh = (float(v) for v in rect_b)
    left, top = max(ax, bx), max(ay, by)
    right, bottom = min(ax + aw, bx + bw), min(ay + ah, by + bh)
    if right <= left or bottom <= top:
        return 0.0
    intersection = (right - left) * (bottom - top)
    union = aw * ah + bw * bh - intersection
    return intersection / union if union > 0 else None


def median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def derive(records: list[dict], forbidden_actions: set[str]) -> dict:
    votes = [r for r in records if (is_label(r) or is_vote(r)) and not r.get("assisted")]
    adjudications = [r for r in records if r.get("record_type") == "adjudication"]
    qc = [r for r in records if r.get("record_type") == "hidden_qc"]
    annotators = sorted({str(r.get("annotator_id")) for r in votes if r.get("annotator_id")})

    unavailable: list[str] = []
    gold: dict = {"annotators": len(annotators)}

    # ---- Cohen kappa between the two annotators, over records both labelled
    by_record: dict[str, dict[str, dict]] = defaultdict(dict)
    for record in votes:
        by_record[str(record.get("record_id"))][str(record.get("annotator_id"))] = record
    # Built in a loop on purpose: a comprehension that indexes the sorted keys
    # eagerly crashes on a record with a single vote, which a real store will have.
    paired = []
    for per_record in by_record.values():
        names = sorted(per_record)
        if len(names) < 2:
            continue
        paired.append((per_record[names[0]], per_record[names[1]]))


    axis_pairs = [(axis_of(x), axis_of(y)) for x, y in paired
                  if axis_of(x) is not None and axis_of(y) is not None]
    gold["kappa_keep_correct_abstain"] = cohen_kappa(axis_pairs, AXIS_LABELS)
    if gold["kappa_keep_correct_abstain"] is None:
        unavailable.append("kappa_keep_correct_abstain: no record carries two unassisted "
                           "KEEP/CORRECT/ABSTAIN labels (the verdict axis is not that axis)")

    action_pairs = []
    for first, second in paired:
        if isinstance(first.get("actions"), list) and isinstance(second.get("actions"), list):
            action_pairs.append((tuple(sorted(first["actions"])), tuple(sorted(second["actions"]))))
    if action_pairs:
        categories = tuple(sorted({item for pair in action_pairs for item in pair}))
        gold["kappa_action_family"] = cohen_kappa(action_pairs, categories)
    else:
        gold["kappa_action_family"] = None
        unavailable.append("kappa_action_family: no record carries two unassisted action sets")

    verdict_pairs = [(str(x.get("verdict")), str(y.get("verdict"))) for x, y in paired
                     if x.get("verdict") and y.get("verdict")]
    informational = cohen_kappa(verdict_pairs, tuple(sorted({v for pair in verdict_pairs for v in pair}))) \
        if verdict_pairs else None

    if forbidden_actions:
        forbidden_pairs = []
        for first, second in paired:
            if isinstance(first.get("actions"), list) and isinstance(second.get("actions"), list):
                flag_a = any(action in forbidden_actions for action in first["actions"])
                flag_b = any(action in forbidden_actions for action in second["actions"])
                forbidden_pairs.append((str(flag_a), str(flag_b)))
        gold["forbidden_agreement"] = (sum(1 for a, b in forbidden_pairs if a == b)
                                       / len(forbidden_pairs)) if forbidden_pairs else None
        if gold["forbidden_agreement"] is None:
            unavailable.append("forbidden_agreement: no paired record carries action sets")
    else:
        gold["forbidden_agreement"] = None
        unavailable.append("forbidden_agreement: no --forbidden-actions set was supplied, so the "
                           "forbidden flag has no definition to agree on")

    rois = []
    for first, second in paired:
        regions_a = first.get("regions") or []
        regions_b = second.get("regions") or []
        if not isinstance(regions_a, list) or not isinstance(regions_b, list):
            continue
        best = None
        for region_a in regions_a:
            for region_b in regions_b:
                if not isinstance(region_a, dict) or not isinstance(region_b, dict):
                    continue
                if region_a.get("role") != region_b.get("role"):
                    continue
                value = iou(region_a.get("rect") or [], region_b.get("rect") or [])
                if value is not None and (best is None or value > best):
                    best = value
        if best is not None:
            rois.append(best)
    gold["median_roi_iou"] = median(rois)
    if gold["median_roi_iou"] is None:
        unavailable.append("median_roi_iou: no paired record carries regions of the same role from "
                           "both annotators")

    gold["hidden_qc_rate"] = (len(qc) / len(votes)) if votes and qc else (0.0 if votes else None)
    gold["hidden_qc"] = (sum(1 for record in qc if record.get("agrees") is True) / len(qc)) \
        if qc else None
    if not qc:
        unavailable.append("hidden_qc: the store carries no hidden_qc record; the write path exists "
                           "(annotate_camera.py hidden-qc) and nothing has been seeded yet")
    gold["adjudicated_review_rate"] = (len(adjudications) / len(votes)) if votes else None
    if not adjudications:
        unavailable.append("adjudicated_review_rate: the store carries no adjudication record")

    return {
        "gold": gold,
        "unavailable": unavailable,
        "informational": {"kappa_verdict_axis": informational,
                          "votes": len(votes), "adjudications": len(adjudications),
                          "hidden_qc": len(qc), "paired_records": len(paired),
                          "annotators": annotators},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--store", type=Path, required=True)
    parser.add_argument("--forbidden-actions", type=Path,
                        help="JSON list of action names that are forbidden for this corpus")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    try:
        records = load_store(args.store)
        forbidden = set()
        if args.forbidden_actions is not None:
            payload = json.loads(args.forbidden_actions.read_text(encoding="utf-8"))
            if not isinstance(payload, list) or not all(isinstance(item, str) for item in payload):
                raise InputError("--forbidden-actions must be a JSON list of action names")
            forbidden = set(payload)
        derived = derive(records, forbidden)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    gold = derived["gold"]
    payload = {
        "schema_id": "camera-gold-report",
        "schema_version": "1.0.0",
        "store": {"path": str(args.store), "records": len(records)},
        "gold": gold,
        "unavailable": derived["unavailable"],
        "informational": derived["informational"],
        "note": "values the store cannot support are absent rather than defaulted; the gate then "
                "reports them missing and fails, which is the honest state",
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(text)

    print(f"GOLD annotators={gold['annotators']} "
          f"kappa_axis={gold['kappa_keep_correct_abstain']} "
          f"kappa_actions={gold['kappa_action_family']} "
          f"hidden_qc_rate={gold['hidden_qc_rate']} hidden_qc={gold['hidden_qc']} "
          f"adjudicated_rate={gold['adjudicated_review_rate']}")
    for reason in derived["unavailable"]:
        print(f"  UNAVAILABLE: {reason}")
    if gold["annotators"] < 2:
        print("FAIL: fewer than two independent annotators, so independence cannot be claimed "
              "(one person's votes are not two annotators)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
