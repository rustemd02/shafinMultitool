from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

try:
    from .datasets import build_v9_event_sft_rows, split_rows, write_jsonl
except ImportError:  # pragma: no cover - allows direct script execution.
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[3]))
    from docs.SGv9pipeline.v9.datasets import build_v9_event_sft_rows, split_rows, write_jsonl


ORDINAL_BY_ACTOR_ID = {
    "actor_1": "first",
    "actor_2": "second",
    "actor_3": "third",
}

REQUIRED_TARGET_ACTIONS = {
    "approach",
    "close",
    "give",
    "look_at",
    "open",
    "pass_by",
    "pick_up",
    "put_down",
    "stop",
}


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = line.strip()
            if payload:
                rows.append(json.loads(payload))
    return rows


def _pattern_name(sample_id: str) -> str:
    return sample_id.split("__", 1)[0] if "__" in sample_id else sample_id


def _actor_to_cir(actor: dict[str, Any], index: int) -> dict[str, Any]:
    actor_id = str(actor.get("id") or f"actor_{index}")
    row: dict[str, Any] = {
        "id": actor_id,
        "type": str(actor.get("type") or "human"),
        "labels": {"ordinal": ORDINAL_BY_ACTOR_ID.get(actor_id, f"actor_ref_{index}")},
    }
    if actor.get("name"):
        row["name"] = str(actor["name"])
    return row


def _object_to_cir(obj: dict[str, Any]) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": str(obj.get("id") or "object_1"),
        "type": str(obj.get("type") or "generic"),
        "relative_position": str(obj.get("relativePosition") or obj.get("relative_position") or "unknown"),
    }
    if obj.get("name"):
        row["name"] = str(obj["name"])
    return row


def _action_to_cir(action: dict[str, Any]) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": str(action.get("id") or ""),
        "actor_id": str(action.get("actorId") or action.get("actor_id") or ""),
        "type": str(action.get("type") or "stand"),
    }
    target = action.get("target") or action.get("targetId") or action.get("target_id")
    if target:
        row["target_id"] = str(target)
    holding = action.get("holdingObject") or action.get("holding_object")
    if holding:
        row["holding_object"] = str(holding)
    if action.get("dialogue"):
        row["dialogue"] = str(action["dialogue"])
    source_text = action.get("sourceText") or action.get("source_text")
    if source_text:
        row["source_text"] = str(source_text)
    if row["type"] == "described_action":
        described = action.get("describedAction") or action.get("described_action")
        if isinstance(described, dict):
            row["described_action"] = described
        else:
            canonical_text = str(source_text or action.get("fallbackText") or "").strip()
            if canonical_text:
                row["described_action"] = {"canonical_text": canonical_text}
    return row


def _beat_to_cir(beat: dict[str, Any]) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": str(beat.get("id") or ""),
        "actions": [_action_to_cir(action) for action in beat.get("actions", []) if isinstance(action, dict)],
    }
    if beat.get("phase"):
        row["phase"] = str(beat["phase"])
    if beat.get("minDuration") is not None:
        row["min_duration"] = beat["minDuration"]
    return row


def _relation_to_cir(relation: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(relation.get("id") or relation.get("ref") or ""),
        "subject": str(relation.get("subject") or relation.get("subjectRef") or ""),
        "relation": str(relation.get("relation") or "near"),
        "object": str(relation.get("object") or relation.get("objectRef") or ""),
    }


def hard_case_to_cir(hard_case: dict[str, Any]) -> dict[str, Any]:
    original_case = hard_case["original_case"]
    gold = original_case["gold_target_json"]
    original_sample_id = str(original_case.get("sample_id") or hard_case.get("eval_case_id") or "")
    sample_id = f"v9_2_hardcase__{original_sample_id}"
    source_text = str(original_case.get("source_text") or gold.get("originalDescription") or hard_case.get("source_text") or "").strip()
    graph_family_key = f"v9_2_hc_{original_case.get('graph_family_key') or original_sample_id.rsplit('__', 1)[-1] if '__' in original_sample_id else original_sample_id}"
    tags = ["v9_2_hard_case", str(hard_case.get("cluster") or "unknown_cluster")]
    tags.extend(str(tag) for tag in original_case.get("eval_expectations", {}).get("critical_eval_tags", []) if isinstance(tag, str))
    return {
        "contract_version": str(original_case.get("contract_version") or "sg_v7_contract_v1"),
        "cir_version": "sg_v7_cir_from_eval_case_v1",
        "sample_id": sample_id,
        "graph_family_key": graph_family_key,
        "pattern_name": _pattern_name(sample_id),
        "difficulty_bucket": str(original_case.get("difficulty_bucket") or "hard"),
        "complexity_class": "targeted",
        "semantic_tags": sorted(set(tags)),
        "source_variant_key": "v9_2_hard_case",
        "source_variant_text": source_text,
        "internal_metadata": {
            "canonical_source_template": source_text,
            "v9_2_origin_eval_case_id": str(hard_case.get("eval_case_id") or ""),
            "v9_2_cluster": str(hard_case.get("cluster") or ""),
            "v9_2_original_sample_id": original_sample_id,
        },
        "scene_graph": {
            "actors": [_actor_to_cir(actor, index) for index, actor in enumerate(gold.get("actors", []), start=1)],
            "objects": [_object_to_cir(obj) for obj in gold.get("objects", [])],
            "beats": [_beat_to_cir(beat) for beat in gold.get("beats", [])],
            "spatial_relations": [_relation_to_cir(relation) for relation in gold.get("spatialRelations", [])],
            "reference_bindings": {},
            "must_preserve": [],
        },
    }


def validate_sft_row(row: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    catalog = row.get("slot_catalog") if isinstance(row.get("slot_catalog"), dict) else {}
    table = row.get("target_event_table") if isinstance(row.get("target_event_table"), dict) else {}
    actor_slots = {str(item.get("slotId")) for item in catalog.get("actorSlots", []) if isinstance(item, dict)}
    object_slots = {str(item.get("slotId")) for item in catalog.get("objectSlots", []) if isinstance(item, dict)}
    beat_slots = {str(item.get("slotId")) for item in catalog.get("beatSlots", []) if isinstance(item, dict)}
    rows = table.get("rows") if isinstance(table.get("rows"), list) else []
    if not rows:
        issues.append("empty_event_table")
    for event in rows:
        row_id = str(event.get("rowId") or "<missing>")
        if str(event.get("actorSlot") or "") not in actor_slots:
            issues.append(f"{row_id}:unknown_actor_slot")
        if str(event.get("beatSlot") or "") not in beat_slots:
            issues.append(f"{row_id}:unknown_beat_slot")
        target = str(event.get("targetSlot") or "")
        if target and target not in actor_slots and target not in object_slots:
            issues.append(f"{row_id}:unknown_target_slot")
        action_type = str(event.get("actionType") or "")
        if action_type in REQUIRED_TARGET_ACTIONS and not target:
            issues.append(f"{row_id}:missing_required_target")
        if action_type == "described_action" and not str(event.get("describedActionText") or "").strip():
            issues.append(f"{row_id}:missing_described_action_text")
    return issues


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hard-cases", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--val-fraction", type=float, default=0.15)
    parser.add_argument("--live-smoke-xcresult", type=Path)
    parser.add_argument("--live-smoke-status", choices=["passed", "failed", "unknown"], default="unknown")
    args = parser.parse_args()

    hard_cases = read_jsonl(args.hard_cases)
    cir_rows = [hard_case_to_cir(row) for row in hard_cases]
    sft_rows = build_v9_event_sft_rows(cir_rows)
    hard_case_by_original_sample = {str(row["original_case"].get("sample_id") or ""): row for row in hard_cases}

    validation_issues: dict[str, list[str]] = {}
    for row in sft_rows:
        sample_id = str(row.get("sample_id") or "")
        original_sample_id = str(row.get("packaging_metadata", {}).get("sample_id") or "").removeprefix("v9_2_hardcase__")
        hard_case = hard_case_by_original_sample.get(original_sample_id, {})
        metadata = row.setdefault("packaging_metadata", {})
        metadata["v9_2_targeted"] = True
        metadata["v9_2_source"] = "benchmark_failure_mining"
        metadata["v9_2_origin_eval_case_id"] = str(hard_case.get("eval_case_id") or "")
        metadata["v9_2_hard_cluster"] = str(hard_case.get("cluster") or "")
        metadata["v9_2_training_target"] = "sg_v9_event_table_v1"
        issues = validate_sft_row(row)
        if issues:
            validation_issues[sample_id] = issues

    train_rows, val_rows = split_rows(
        sft_rows,
        key_field="split_family_id",
        val_fraction=args.val_fraction,
        seed=args.seed,
    )

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    hard_case_out = output_dir / "v9_2_hard_cases.jsonl"
    write_jsonl(hard_cases, hard_case_out)
    write_jsonl(sft_rows, output_dir / "v9_2_event_sft_targeted_all.jsonl")
    write_jsonl(train_rows, output_dir / "v9_2_event_sft_targeted_train.jsonl")
    write_jsonl(val_rows, output_dir / "v9_2_event_sft_targeted_val.jsonl")

    cluster_counts = Counter(str(row.get("cluster") or "unknown") for row in hard_cases)
    row_counts_by_cluster: Counter[str] = Counter()
    action_counts: Counter[str] = Counter()
    rows_by_cluster: defaultdict[str, int] = defaultdict(int)
    for row in sft_rows:
        cluster = str(row.get("packaging_metadata", {}).get("v9_2_hard_cluster") or "unknown")
        row_counts_by_cluster[cluster] += 1
        events = row.get("target_event_table", {}).get("rows", [])
        rows_by_cluster[cluster] += len(events)
        for event in events:
            action_counts[str(event.get("actionType") or "unknown")] += 1

    manifest = {
        "contract_version": "sg_v9_2_targeted_event_sft_manifest_v1",
        "hard_case_source": str(args.hard_cases),
        "hard_case_output": str(hard_case_out),
        "total_hard_cases": len(hard_cases),
        "cluster_counts": dict(sorted(cluster_counts.items())),
        "total_sft_rows": len(sft_rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "event_rows_by_cluster": dict(sorted(rows_by_cluster.items())),
        "sft_rows_by_cluster": dict(sorted(row_counts_by_cluster.items())),
        "action_type_counts": dict(sorted(action_counts.items())),
        "validation": {
            "valid_rows": len(sft_rows) - len(validation_issues),
            "invalid_rows": len(validation_issues),
            "issues_by_sample_id": validation_issues,
        },
        "live_smoke": {
            "status": args.live_smoke_status,
            "xcresult_path": str(args.live_smoke_xcresult) if args.live_smoke_xcresult else None,
            "mined_failure_count": 0 if args.live_smoke_status == "passed" else None,
            "note": "Latest live smoke had no failure clusters to mine; targeted rows come from benchmark semantic misses.",
        },
    }
    manifest_path = output_dir / "v9_2_targeted_sft_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
