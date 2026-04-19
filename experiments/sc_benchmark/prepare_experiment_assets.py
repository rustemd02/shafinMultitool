#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_SNAPSHOTS = [
    "prompt_contract_snapshot.json",
    "decoding_config_snapshot.json",
    "grammar_constraint_snapshot.json",
    "normalization_policy_snapshot.json",
    "runtime_policy_snapshot.json",
]

REQUIRED_METRICS = [
    "json_valid_rate",
    "marked_object_recall",
    "exact_marked_object_id_accuracy",
    "beat_count_accuracy",
    "action_recall",
    "described_action_precision",
    "dangling_target_rate",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "llm_accept_rate",
    "llm_merge_rate",
    "llm_reject_rate",
    "runtime_fallback_rate",
]

DEFAULT_MODEL_IDS = [
    "base_qwen3_1_7b",
    "dataset_v6",
    "dataset_v7",
    "dataset_v7_orpo",
]

MODEL_NAME_HINTS = {
    "base_qwen3_1_7b": "Base Qwen3-1.7B",
    "dataset_v6": "Fine-tuned on generate_dataset_v6",
    "dataset_v7": "Fine-tuned on generate_dataset_v7",
    "dataset_v7_orpo": "Fine-tuned on generate_dataset_v7 + ORPO",
}


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            payload = line.strip()
            if not payload:
                continue
            item = json.loads(payload)
            if not isinstance(item, dict):
                continue
            rows.append(item)
    return rows


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _norm_action_type(value: Any) -> str:
    return str(value or "").strip().replace("-", "_").replace(" ", "_").lower()


def _extract_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    beats = script.get("beats", [])
    if isinstance(beats, list):
        for beat_idx, beat in enumerate(beats, start=1):
            if not isinstance(beat, dict):
                continue
            beat_actions = beat.get("actions", [])
            if not isinstance(beat_actions, list):
                continue
            for action_idx, action in enumerate(beat_actions, start=1):
                if not isinstance(action, dict):
                    continue
                action_copy = dict(action)
                action_copy["_beat_index"] = beat_idx
                action_copy["_action_index"] = action_idx
                actions.append(action_copy)
    top_level = script.get("actions")
    if isinstance(top_level, list):
        for action_idx, action in enumerate(top_level, start=1):
            if not isinstance(action, dict):
                continue
            action_copy = dict(action)
            action_copy["_beat_index"] = int(action.get("beatIndex", 0) or 0)
            action_copy["_action_index"] = action_idx
            actions.append(action_copy)
    return actions


def _extract_marked_objects(script: dict[str, Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for obj in script.get("objects", []) if isinstance(script.get("objects"), list) else []:
        if not isinstance(obj, dict):
            continue
        object_id = str(obj.get("id", "")).strip()
        if not object_id.startswith("object_marked_"):
            continue
        out.append(
            {
                "id": object_id,
                "name": str(obj.get("name") or object_id),
                "type": str(obj.get("type") or "generic"),
                "mentioned_aliases": [str(obj.get("name") or object_id)],
            }
        )
    return out


def _extract_expected_bindings(script: dict[str, Any]) -> dict[str, str]:
    actor_ids = {
        str(actor.get("id", "")).strip()
        for actor in (script.get("actors", []) if isinstance(script.get("actors"), list) else [])
        if isinstance(actor, dict)
    }
    bindings: dict[str, str] = {}
    if "actor_1" in actor_ids:
        bindings["first"] = "actor_1"
    if "actor_2" in actor_ids:
        bindings["second"] = "actor_2"
    if "actor_3" in actor_ids:
        bindings["third"] = "actor_3"
    return bindings


def _lemmas_from_text(value: str) -> list[str]:
    words = re.findall(r"[A-Za-zА-Яа-яЁё]{3,}", value.lower())
    uniq: list[str] = []
    for word in words:
        if word not in uniq:
            uniq.append(word)
        if len(uniq) >= 4:
            break
    return uniq


def _critical_tags_from_row(row: dict[str, Any], *, script: dict[str, Any]) -> list[str]:
    explicit = row.get("critical_eval_tags")
    tags: list[str] = [str(x) for x in explicit if str(x).strip()] if isinstance(explicit, list) else []
    pkg = row.get("packaging_metadata", {}) if isinstance(row.get("packaging_metadata"), dict) else {}
    pattern = str(pkg.get("pattern_name", "")).lower()
    semantic_tags = pkg.get("semantic_tags", [])
    if not isinstance(semantic_tags, list):
        semantic_tags = []
    semantic_tags = [str(x).lower() for x in semantic_tags]

    actions = _extract_actions(script)
    beat_count = len(script.get("beats", [])) if isinstance(script.get("beats"), list) else 0
    marked = _extract_marked_objects(script)

    if "same_type" in pattern and "same_type_markers" not in tags:
        tags.append("same_type_markers")
    if ("ordinal" in pattern or "ordinal_reference" in semantic_tags) and "ordinal_cases" not in tags:
        tags.append("ordinal_cases")
    if beat_count >= 3 and "three_beat_cases" not in tags:
        tags.append("three_beat_cases")
    if marked and "exact_marker_identity_cases" not in tags:
        tags.append("exact_marker_identity_cases")
    if marked and "marked_object_morphology" not in tags:
        tags.append("marked_object_morphology")
    if any(_norm_action_type(a.get("type")) == "described_action" for a in actions):
        if "unsupported_action_cases" not in tags:
            tags.append("unsupported_action_cases")
    if row.get("promoted_from_manual_review"):
        if "reviewed_merge_cases" not in tags:
            tags.append("reviewed_merge_cases")
    return sorted(set(tags))


def _make_expected_action_units(script: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    expected: list[dict[str, Any]] = []
    phase_sequence: list[str] = []
    for action in _extract_actions(script):
        beat_index = int(action.get("_beat_index", 0) or 0)
        action_idx = int(action.get("_action_index", 0) or 0)
        action_type = _norm_action_type(action.get("type"))
        actor_id = str(action.get("actorId") or action.get("actor_id") or "").strip()
        target_id = str(action.get("target") or action.get("targetId") or "").strip()
        phase_label = f"beat{beat_index:02d}_{action_type or 'unknown'}_{action_idx:02d}"
        unit: dict[str, Any] = {
            "beat_index": beat_index,
            "actor_id": actor_id,
            "action_type": action_type,
            "phase_label": phase_label,
        }
        if target_id:
            unit["target_id"] = target_id
        if action_type == "described_action":
            fallback_text = str(action.get("fallbackText") or action.get("fallback_text") or action.get("sourceText") or "")
            lemmas = _lemmas_from_text(fallback_text)
            if lemmas:
                unit["fallback_text_lemmas"] = lemmas
        expected.append(unit)
        phase_sequence.append(phase_label)
    return expected, phase_sequence


def _has_dangling_targets(script: dict[str, Any]) -> bool:
    actor_ids = {
        str(a.get("id", "")).strip()
        for a in (script.get("actors", []) if isinstance(script.get("actors"), list) else [])
        if isinstance(a, dict)
    }
    object_ids = {
        str(o.get("id", "")).strip()
        for o in (script.get("objects", []) if isinstance(script.get("objects"), list) else [])
        if isinstance(o, dict)
    }
    valid = actor_ids.union(object_ids)
    target_required = {"approach", "stop", "stand", "passby", "pass_by", "pass-by"}
    for action in _extract_actions(script):
        atype = _norm_action_type(action.get("type"))
        if atype not in target_required:
            continue
        target = str(action.get("target") or action.get("targetId") or "").strip()
        if not target or target not in valid:
            return True
    return False


def _build_case_from_row(
    *,
    row: dict[str, Any],
    eval_case_id: str,
    eval_set: str,
    gold_script: dict[str, Any],
    rule_reference_script: dict[str, Any],
    provenance_origin: str,
) -> dict[str, Any]:
    pkg = row.get("packaging_metadata", {}) if isinstance(row.get("packaging_metadata"), dict) else {}
    marked_objects = _extract_marked_objects(gold_script)
    marked_ids = [x["id"] for x in marked_objects]
    expected_bindings = _extract_expected_bindings(gold_script)
    expected_action_units, phase_sequence = _make_expected_action_units(gold_script)
    critical_tags = _critical_tags_from_row(row, script=gold_script)

    actions = _extract_actions(gold_script)
    objects = gold_script.get("objects", [])
    if not isinstance(objects, list):
        objects = []
    rule_conf = float(row.get("recoverability_score", 0.85) or 0.85)
    rule_conf = 0.0 if rule_conf < 0.0 else 1.0 if rule_conf > 1.0 else rule_conf

    correction_tier = str(pkg.get("correction_tier") or "tier_b_deterministic_canonical")
    if eval_set == "real_runtime" and correction_tier not in {
        "tier_a_human_gold",
        "tier_b_deterministic_canonical",
        "tier_c_reviewed_merge",
    }:
        correction_tier = "tier_c_reviewed_merge"

    return {
        "eval_case_id": eval_case_id,
        "eval_set": eval_set,
        "sample_id": str(row.get("sample_id") or pkg.get("sample_id") or eval_case_id),
        "graph_family_key": str(pkg.get("graph_family_key") or pkg.get("split_family_id") or ""),
        "contract_version": str(pkg.get("contract_version") or "sg_v7_contract_v1"),
        "difficulty_bucket": str(pkg.get("difficulty_bucket") or ("hard" if eval_set == "hard_heldout" else "core")),
        "source_text": str(row.get("source_text") or ""),
        "marked_objects": marked_objects,
        "gold_target_json": gold_script,
        "rule_based_reference_json": rule_reference_script,
        "eval_expectations": {
            "expected_marked_object_ids": marked_ids,
            "expected_ordinal_bindings": expected_bindings,
            "expected_action_units": expected_action_units,
            "expected_phase_sequence": phase_sequence,
            "critical_eval_tags": critical_tags,
        },
        "runtime_policy_inputs": {
            "rule_confidence": rule_conf,
            "rule_object_count": len(objects),
            "rule_action_count": len(actions),
            "rule_has_dangling_targets": _has_dangling_targets(gold_script),
            "rule_matched_marked_object_count": len(marked_ids),
            "mentioned_marked_object_ids": marked_ids,
        },
        "provenance": {
            "origin": provenance_origin,
            "correction_tier": correction_tier,
            "review_status": "approved",
            "gold_source": "corrected_target_json",
            "final_script_source": "merge_reviewed" if eval_set == "real_runtime" else "deterministic_canonical",
        },
    }


def _build_snapshots(bundle_dir: Path) -> dict[str, str]:
    now = datetime.now(timezone.utc).isoformat()
    snapshots: dict[str, dict[str, Any]] = {
        "prompt_contract_snapshot.json": {
            "snapshot_id": "sgv7_prompt_contract_v1",
            "contract_version": "sg_v7_contract_v1",
            "generated_at": now,
            "note": "Frozen prompt contract snapshot for scientific benchmark eval_bundle_v1.",
        },
        "decoding_config_snapshot.json": {
            "snapshot_id": "sgv7_decoding_v1",
            "temperature": 0.0,
            "top_p": 1.0,
            "max_output_tokens": 4096,
            "generated_at": now,
        },
        "grammar_constraint_snapshot.json": {
            "snapshot_id": "sgv7_grammar_constraint_v1",
            "grammar_family": "SceneScript JSON schema",
            "generated_at": now,
        },
        "normalization_policy_snapshot.json": {
            "snapshot_id": "sgv7_normalization_policy_v1",
            "source_text_normalization": "strict_whitespace_and_noise_filters",
            "generated_at": now,
        },
        "runtime_policy_snapshot.json": {
            "snapshot_id": "sgv7_runtime_policy_mirror_v1",
            "confidence_model": {
                "base": 0.50,
                "actor_weight": 0.10,
                "object_weight": 0.05,
                "action_weight": 0.05,
                "missing_action_penalty": 0.10,
                "max_actor_bonus": 3,
                "max_object_bonus": 5,
                "max_action_bonus": 5,
            },
            "generated_at": now,
        },
    }
    for name, payload in snapshots.items():
        _write_json(bundle_dir / name, payload)
    return {name: _sha256(bundle_dir / name) for name in REQUIRED_SNAPSHOTS}


def _select_rows(rows: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    sorted_rows = sorted(rows, key=lambda r: str(r.get("sample_id") or (r.get("packaging_metadata", {}) or {}).get("sample_id") or ""))
    return sorted_rows[:limit]


def _detect_base_model(model_ids: list[str]) -> str | None:
    preferred = ("base_qwen3_1_7b",)
    model_set = set(model_ids)
    for candidate in preferred:
        if candidate in model_set:
            return candidate
    for model_id in model_ids:
        if model_id.startswith("base_"):
            return model_id
    return None


def _default_pairs(model_ids: list[str]) -> list[list[str]]:
    pairs: list[list[str]] = []
    model_set = set(model_ids)
    base = _detect_base_model(model_ids)

    if base is not None and base in model_set:
        for candidate in ("dataset_v6", "dataset_v7", "dataset_v7_orpo"):
            if candidate in model_set:
                pairs.append([candidate, base])
    if "dataset_v7" in model_set and "dataset_v6" in model_set:
        pairs.append(["dataset_v7", "dataset_v6"])
    if "dataset_v7_orpo" in model_set and "dataset_v7" in model_set:
        pairs.append(["dataset_v7_orpo", "dataset_v7"])
    if "dataset_v7_orpo" in model_set and "dataset_v6" in model_set:
        pairs.append(["dataset_v7_orpo", "dataset_v6"])
    return pairs


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare scientific benchmark assets: eval_bundle_v1 + oracle predictions + benchmark config."
    )
    parser.add_argument(
        "--dataset-dir",
        type=Path,
        default=Path("/tmp/sgv7_full_20260417/final/dataset"),
        help="Path to SGv7 final dataset directory (contains sft_*.jsonl and preference_*.jsonl).",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace"),
        help="Single root directory for all scientific benchmark artifacts.",
    )
    parser.add_argument("--bundle-id", default="sgv7_eval_bundle_v1")
    parser.add_argument("--bundle-version", default="eval_bundle_v1")
    parser.add_argument("--synthetic-limit", type=int, default=120)
    parser.add_argument("--hard-limit", type=int, default=120)
    parser.add_argument("--runtime-limit", type=int, default=64)
    parser.add_argument("--seeds", default="42,43,44")
    parser.add_argument("--models", default=",".join(DEFAULT_MODEL_IDS))
    args = parser.parse_args()

    dataset_dir = args.dataset_dir.expanduser().resolve()
    output_root = args.output_root.expanduser().resolve()
    bundle_dir = output_root / "eval_bundle_v1"
    preds_dir = output_root / "predictions_oracle_v1"

    required_inputs = [
        dataset_dir / "sft_test.jsonl",
        dataset_dir / "preference_test.jsonl",
    ]
    for path in required_inputs:
        if not path.exists():
            raise SystemExit(f"Missing required input: {path}")

    sft_rows = _read_jsonl(dataset_dir / "sft_test.jsonl")
    pref_rows = _read_jsonl(dataset_dir / "preference_test.jsonl")

    sft_core = []
    sft_hard = []
    for row in sft_rows:
        pkg = row.get("packaging_metadata", {}) if isinstance(row.get("packaging_metadata"), dict) else {}
        if str(pkg.get("difficulty_bucket")).lower() == "hard":
            sft_hard.append(row)
        else:
            sft_core.append(row)

    selected_core = _select_rows(sft_core, args.synthetic_limit)
    selected_hard = _select_rows(sft_hard, args.hard_limit)
    selected_runtime = _select_rows(pref_rows, args.runtime_limit)

    eval_cases: list[dict[str, Any]] = []
    for idx, row in enumerate(selected_core, start=1):
        sample_id = str(row.get("sample_id") or f"core_{idx:04d}")
        gold = row.get("target_json")
        if not isinstance(gold, dict):
            continue
        eval_cases.append(
            _build_case_from_row(
                row=row,
                eval_case_id=f"syn-{idx:04d}::{sample_id}",
                eval_set="synthetic_heldout",
                gold_script=gold,
                rule_reference_script=gold,
                provenance_origin="synthetic",
            )
        )

    for idx, row in enumerate(selected_hard, start=1):
        sample_id = str(row.get("sample_id") or f"hard_{idx:04d}")
        gold = row.get("target_json")
        if not isinstance(gold, dict):
            continue
        eval_cases.append(
            _build_case_from_row(
                row=row,
                eval_case_id=f"hard-{idx:04d}::{sample_id}",
                eval_set="hard_heldout",
                gold_script=gold,
                rule_reference_script=gold,
                provenance_origin="synthetic",
            )
        )

    for idx, row in enumerate(selected_runtime, start=1):
        pref_id = str(row.get("preference_id") or f"runtime_{idx:04d}")
        chosen = row.get("chosen_json")
        rejected = row.get("rejected_json")
        if not isinstance(chosen, dict):
            continue
        if not isinstance(rejected, dict):
            rejected = chosen
        eval_cases.append(
            _build_case_from_row(
                row=row,
                eval_case_id=f"rt-{idx:04d}::{pref_id}",
                eval_set="real_runtime",
                gold_script=chosen,
                rule_reference_script=rejected,
                provenance_origin="runtime_reviewed",
            )
        )

    if not eval_cases:
        raise SystemExit("No eval cases produced. Check input dataset content.")

    bundle_dir.mkdir(parents=True, exist_ok=True)
    _write_jsonl(bundle_dir / "eval_cases.jsonl", eval_cases)
    hashes = _build_snapshots(bundle_dir)

    set_counts = {
        "synthetic_heldout": sum(1 for c in eval_cases if c["eval_set"] == "synthetic_heldout"),
        "hard_heldout": sum(1 for c in eval_cases if c["eval_set"] == "hard_heldout"),
        "real_runtime": sum(1 for c in eval_cases if c["eval_set"] == "real_runtime"),
    }
    manifest = {
        "bundle_id": args.bundle_id,
        "bundle_version": args.bundle_version,
        "contract_version": "sg_v7_contract_v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "required_contract_snapshots": REQUIRED_SNAPSHOTS,
        "expected_snapshot_hashes": hashes,
        "set_counts": set_counts,
        "required_metrics": REQUIRED_METRICS,
        "provenance": {
            "dataset_dir": str(dataset_dir),
            "synthetic_limit": args.synthetic_limit,
            "hard_limit": args.hard_limit,
            "runtime_limit": args.runtime_limit,
        },
    }
    _write_json(bundle_dir / "eval_bundle_manifest.json", manifest)

    # Oracle predictions (SMOKE ONLY): gold target copied as predicted_script for each model+seed.
    model_ids = [item.strip() for item in args.models.split(",") if item.strip()]
    seeds = [int(item.strip()) for item in args.seeds.split(",") if item.strip()]
    preds_dir.mkdir(parents=True, exist_ok=True)

    predictions_rows = [{"eval_case_id": case["eval_case_id"], "predicted_script": case["gold_target_json"]} for case in eval_cases]
    for model_id in model_ids:
        for seed in seeds:
            _write_jsonl(preds_dir / f"{model_id}_seed{seed}.jsonl", predictions_rows)

    config = {
        "eval_bundle_dir": str(bundle_dir),
        "eval_seed": 20260419,
        "seeds": seeds,
        "checkpoint_id_template": "{model_id}_seed{seed}",
        "models": [
            {
                "id": model_id,
                "name": MODEL_NAME_HINTS.get(model_id, model_id),
                "predictions_path_template": str(preds_dir / f"{model_id}_seed{{seed}}.jsonl"),
            }
            for model_id in model_ids
        ],
        "pairs": _default_pairs(model_ids),
    }
    _write_json(output_root / "benchmark_config.v1.json", config)

    # Real predictions config: expected to be filled by online/local model inference.
    real_preds_dir = output_root / "predictions_real_v1"
    real_preds_dir.mkdir(parents=True, exist_ok=True)
    real_config = {
        **config,
        "models": [
            {
                **model_payload,
                "predictions_path_template": str(real_preds_dir / f"{model_payload['id']}_seed{{seed}}.jsonl"),
            }
            for model_payload in config["models"]
        ],
    }
    _write_json(output_root / "benchmark_config.real.v1.json", real_config)

    serving_model_map = {model_id: model_id for model_id in model_ids}
    _write_json(output_root / "serving_model_map.template.json", serving_model_map)

    notes = {
        "warning": (
            "predictions_oracle_v1 are smoke placeholders copied from gold_target_json. "
            "Replace with real model outputs before scientific conclusions."
        ),
        "bundle_dir": str(bundle_dir),
        "predictions_dir": str(preds_dir),
        "real_predictions_dir": str(real_preds_dir),
        "config_path": str(output_root / "benchmark_config.v1.json"),
        "real_config_path": str(output_root / "benchmark_config.real.v1.json"),
        "serving_model_map_template": str(output_root / "serving_model_map.template.json"),
        "set_counts": set_counts,
        "total_cases": len(eval_cases),
    }
    _write_json(output_root / "README.assets.json", notes)

    print(f"[prepare] eval bundle: {bundle_dir}")
    print(f"[prepare] predictions (oracle smoke): {preds_dir}")
    print(f"[prepare] benchmark config: {output_root / 'benchmark_config.v1.json'}")
    print(f"[prepare] set_counts={set_counts} total={len(eval_cases)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
