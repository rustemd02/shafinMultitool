#!/usr/bin/env python3
"""Build the pilot intent dataset from an instrumented still-replay dump
(R03/R15 groundwork, variant A pilot stage 1).

Input: an INTENTDUMP log produced by the temporary full-replay dump test
(one line per record of the benchmark pack: record id, curated label,
confidence target, runtime verdict/confidence/actions/issues, numeric and
semantic debug features) plus the canonical labels file.

Output (research_only, human_gold=false, deterministic, seeded):
  - intent-dataset-train.jsonl / intent-dataset-test.jsonl (stratified split)
  - intent-dataset-manifest.json (counts, feature names, provenance, hashes)

The features are low-level deterministic snapshot/critic diagnostics. They are
NOT an intent ground truth: the pilot quantifies how far current features
separate curated quality classes and nothing more.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from datetime import datetime, timezone
from pathlib import Path

SEED = 20260912
TEST_FRACTION = 0.30
CLASSES = ["good", "mixed", "bad"]


def parse_dump_line(line: str) -> dict | None:
    match = re.match(
        r"INTENTDUMP\|([^|]+)\|label=([^|]+)\|target=([^|]+)\|verdict=([^|]+)\|conf=([^|]+)\|act=([^|]*)\|issues=([^|]*)\|NUM\[([^\]]*)\]\|SEM\[([^\]]*)\]",
        line.strip(),
    )
    if not match:
        return None
    record_id, label, target, verdict, conf, act, issues, num, sem = match.groups()
    numeric = {}
    for pair in num.split(","):
        if "=" in pair:
            key, value = pair.split("=", 1)
            try:
                numeric[key.strip()] = float(value)
            except ValueError:
                numeric[key.strip()] = -1.0
    semantic = {}
    for pair in sem.split(","):
        if "=" in pair:
            key, value = pair.split("=", 1)
            semantic[key.strip()] = value.strip()
    return {
        "record_id": record_id,
        "label": label,
        "target": target,
        "verdict": verdict,
        "confidence": float(conf),
        "actions": sorted(a.strip(' "') for a in act.strip("[]").split(",") if a.strip()),
        "issues": sorted(i.strip(' "') for i in issues.strip("[]").split(",") if i.strip()),
        "numeric": numeric,
        "semantic": semantic,
    }


def load_dump(path: Path) -> list[dict]:
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("INTENTDUMP|"):
            record = parse_dump_line(line)
            if record is not None:
                records.append(record)
    return records


def build_feature_names(records: list[dict]) -> tuple[list[str], list[str]]:
    base = sorted({key for r in records for key in r["numeric"] if not key.startswith("severity_")})
    severity = sorted({key for r in records for key in r["numeric"] if key.startswith("severity_")})
    return base, severity


def feature_vector(record: dict, base: list[str], severity: list[str], kinds: list[str]) -> list[float]:
    values = [record["numeric"].get(key, -1.0) for key in base]
    values += [record["numeric"].get(key, 0.0) for key in severity]
    kind = record["semantic"].get("primary_subject_kind", "?")
    values += [1.0 if kind == k else 0.0 for k in kinds]
    values += [1.0 if record["semantic"].get("subject_readable") == "true" else 0.0]
    values += [1.0 if record["semantic"].get("has_clear_focus") == "true" else 0.0]
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", type=Path, required=True, help="INTENTDUMP log path")
    parser.add_argument("--labels", type=Path, required=True, help="camera_full_labels.jsonl")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--test-fraction", type=float, default=TEST_FRACTION)
    args = parser.parse_args()

    records = load_dump(args.dump)
    if not records:
        raise SystemExit(f"no INTENTDUMP records parsed from {args.dump}")

    label_rows = {}
    for line in args.labels.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        label_rows[row["record_id"]] = row
    for record in records:
        curated = label_rows.get(record["record_id"])
        record["curated_problems"] = curated.get("problems", []) if curated else None
        record["curated_technical_defects"] = curated.get("technical_quality_defects", []) if curated else None

    base, severity = build_feature_names(records)
    kinds = sorted({r["semantic"].get("primary_subject_kind", "?") for r in records})

    rng = random.Random(args.seed)
    by_class: dict[str, list[dict]] = {}
    for record in records:
        by_class.setdefault(record["label"], []).append(record)
    train: list[dict] = []
    test: list[dict] = []
    for label in sorted(by_class):
        group = sorted(by_class[label], key=lambda r: r["record_id"])
        rng.shuffle(group)
        cut = max(1, int(round(len(group) * (1.0 - args.test_fraction))))
        train += group[:cut]
        test += group[cut:]

    # `cut` is floored at 1 per class, so a class with a single record sends its only
    # row to train. With one record per class the whole corpus lands in train and the
    # test side comes out empty — a dataset that can be "evaluated" on nothing. The
    # run must fail here rather than emit a split whose test half is empty.
    if args.test_fraction > 0 and not test:
        counts = {name: len(rows) for name, rows in by_class.items()}
        raise SystemExit(
            f"empty test split: no class has enough records for test_fraction={args.test_fraction} "
            f"(class counts: {counts})"
        )

    def feature_names() -> list[str]:
        return base + severity + [f"kind_{k}" for k in kinds] + ["sem_readable", "sem_clear_focus"]

    feature_name_list = feature_names()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    provenance = {
        "dataset_id": "camera-intent-pilot-v1",
        "research_only": True,
        "human_gold": False,
        "note": "low-level deterministic diagnostics; labels are curated quality classes",
        "dump_source": str(args.dump),
        "seed": args.seed,
        "test_fraction": args.test_fraction,
        "feature_names": feature_name_list,
        "classes": CLASSES,
        "generated_at": now,
    }
    for split_name, split_rows in (("train", train), ("test", test)):
        split_path = args.out_dir / f"intent-dataset-{split_name}.jsonl"
        with split_path.open("w", encoding="utf-8") as handle:
            for record in split_rows:
                handle.write(json.dumps({
                    "record_id": record["record_id"],
                    "split": split_name,
                    "label": record["label"],
                    "target": record["target"],
                    "verdict": record["verdict"],
                    "confidence": record["confidence"],
                    "actions": record["actions"],
                    "issues": record["issues"],
                    "features": dict(zip(feature_name_list, feature_vector(record, base, severity, kinds))),
                    "curated_problems": record["curated_problems"],
                    "curated_technical_defects": record["curated_technical_defects"],
                    "provenance": provenance,
                }, ensure_ascii=False, sort_keys=True) + "\n")

    manifest_path = args.out_dir / "intent-dataset-manifest.json"
    manifest_path.write_text(
        json.dumps({
            **provenance,
            "train_count": len(train),
            "test_count": len(test),
            "label_distribution": {
                split_name: {
                    label: sum(1 for r in rows if r["label"] == label)
                    for label in CLASSES
                }
                for split_name, rows in (("train", train), ("test", test))
            },
        }, ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8",
    )
    print(f"WROTE train={len(train)} test={len(test)} -> {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
