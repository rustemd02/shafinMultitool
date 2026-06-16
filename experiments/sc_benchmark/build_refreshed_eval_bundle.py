#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from build_leakage_aware_eval_bundle import CorpusSpec, DEFAULT_BENCHMARK_MODELS, DEFAULT_BENCHMARK_PAIRS, DEFAULT_CORPORA
from prepare_experiment_assets import REQUIRED_METRICS, _build_case_from_row, _build_snapshots, _write_json, _write_jsonl

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS_ROOT = REPO_ROOT / "docs" / "SGv7pipeline"
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from cir_contract.contracts import serialize_to_scenescript, structural_hash
from dataset_builder.ingest import normalized_source_hash_v1
from graph_generator.dedup import graph_fingerprint


DEFAULT_OUTPUT_BUNDLE = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "eval_bundle_v2_fresh262_all_models"
DEFAULT_OUTPUT_CONFIG = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "benchmark_config.seed42.fresh262_all_models.json"
DEFAULT_OUTPUT_README = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "fresh262_rerun_instructions.md"
DEFAULT_GENERATION_ROOT = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "fresh262_generation"


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if not raw:
                continue
            payload = json.loads(raw)
            if isinstance(payload, dict):
                rows.append(payload)
    return rows


def first_nonempty_string(values: list[Any]) -> str | None:
    for value in values:
        if isinstance(value, str):
            text = value.strip()
            if text:
                return text
    return None


def get_pkg(row: dict[str, Any]) -> dict[str, Any]:
    payload = row.get("packaging_metadata")
    return payload if isinstance(payload, dict) else {}


def sample_hash_from_sample_id(value: str) -> str | None:
    match = re.search(r"__([0-9a-f]{8,16})$", value.strip().lower())
    if match:
        return match.group(1)[:8]
    return None


def infer_sample_id(row: dict[str, Any]) -> str | None:
    return first_nonempty_string(
        [
            row.get("sample_id"),
            get_pkg(row).get("sample_id"),
        ]
    )


def infer_source_text(row: dict[str, Any]) -> str | None:
    return first_nonempty_string(
        [
            row.get("source_text"),
            row.get("source"),
            get_pkg(row).get("source_text"),
            (row.get("gold_target_json") or {}).get("originalDescription") if isinstance(row.get("gold_target_json"), dict) else None,
            (row.get("target_json") or {}).get("originalDescription") if isinstance(row.get("target_json"), dict) else None,
        ]
    )


def infer_normalized_source_hash(row: dict[str, Any]) -> str | None:
    direct = first_nonempty_string(
        [
            row.get("normalized_source_hash"),
            get_pkg(row).get("normalized_source_hash"),
        ]
    )
    if direct:
        return direct.lower()
    source_text = infer_source_text(row)
    if source_text:
        return normalized_source_hash_v1(source_text).lower()
    return None


def family_tokens_from_row(row: dict[str, Any]) -> set[str]:
    pkg = get_pkg(row)
    family_proof = pkg.get("family_resolution_proof")
    if not isinstance(family_proof, dict):
        family_proof = {}
    raw_values = [
        row.get("graph_family_key"),
        row.get("split_family_id"),
        row.get("graph_hash"),
        row.get("sample_id"),
        pkg.get("graph_family_key"),
        pkg.get("split_family_id"),
        pkg.get("graph_hash"),
        pkg.get("sample_id"),
        family_proof.get("resolved_graph_family_key"),
    ]
    tokens: set[str] = set()
    for raw in raw_values:
        if not raw:
            continue
        text = str(raw).strip().lower()
        if not text:
            continue
        tokens.add(text)
        if re.fullmatch(r"[0-9a-f]+", text) and len(text) >= 8:
            tokens.add(text[:8])
        sample_hash = sample_hash_from_sample_id(text)
        if sample_hash:
            tokens.add(sample_hash)
    return tokens


def normalized_source_text(text: str | None) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip().lower()


def build_corpus_indexes(corpora: tuple[CorpusSpec, ...]) -> dict[str, Any]:
    sample_ids: set[str] = set()
    sources: set[str] = set()
    source_hashes: set[str] = set()
    family_tokens: set[str] = set()
    corpus_rows: list[dict[str, Any]] = []
    for corpus in corpora:
        rows = read_jsonl(corpus.path)
        corpus_rows.append(
            {
                "corpus_id": corpus.corpus_id,
                "path": str(corpus.path),
                "row_count": len(rows),
            }
        )
        for row in rows:
            sample_id = infer_sample_id(row)
            if sample_id:
                sample_ids.add(sample_id.lower())
            source = normalized_source_text(infer_source_text(row))
            if source:
                sources.add(source)
            source_hash = infer_normalized_source_hash(row)
            if source_hash:
                source_hashes.add(source_hash.lower())
            family_tokens.update(family_tokens_from_row(row))
    return {
        "sample_ids": sample_ids,
        "sources": sources,
        "source_hashes": source_hashes,
        "family_tokens": family_tokens,
        "corpora": corpus_rows,
    }


def overlap_reasons(row: dict[str, Any], *, corpus_indexes: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    sample_id = infer_sample_id(row)
    if sample_id and sample_id.lower() in corpus_indexes["sample_ids"]:
        reasons.append("train_sample_id")
    source = normalized_source_text(infer_source_text(row))
    if source and source in corpus_indexes["sources"]:
        reasons.append("train_source")
    source_hash = infer_normalized_source_hash(row)
    if source_hash and source_hash.lower() in corpus_indexes["source_hashes"]:
        reasons.append("train_normalized_source_hash")
    if family_tokens_from_row(row) & corpus_indexes["family_tokens"]:
        reasons.append("train_graph_family")
    return reasons


def build_overlap_summary(eval_cases: list[dict[str, Any]], *, corpus_indexes: dict[str, Any]) -> dict[str, Any]:
    retained_by_set: Counter[str] = Counter()
    excluded_by_set: Counter[str] = Counter()
    reason_counts: Counter[str] = Counter()
    excluded_case_ids: list[str] = []
    for row in eval_cases:
        reasons = overlap_reasons(row, corpus_indexes=corpus_indexes)
        set_name = str(row.get("eval_set", "unknown"))
        if reasons:
            excluded_by_set[set_name] += 1
            reason_counts.update(reasons)
            excluded_case_ids.append(str(row.get("eval_case_id", "")))
        else:
            retained_by_set[set_name] += 1
    return {
        "total": len(eval_cases),
        "retained": int(sum(retained_by_set.values())),
        "excluded": int(sum(excluded_by_set.values())),
        "retained_by_set": dict(retained_by_set),
        "excluded_by_set": dict(excluded_by_set),
        "reason_counts": dict(reason_counts),
        "excluded_case_ids": excluded_case_ids,
    }


def run_step(cmd: list[str], *, cwd: Path) -> None:
    completed = subprocess.run(cmd, cwd=str(cwd), check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed ({completed.returncode}): {' '.join(cmd)}")


def build_fresh_source_pool(
    *,
    bucket: str,
    total_records: int,
    seed: int,
    output_root: Path,
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    output_root.mkdir(parents=True, exist_ok=True)
    graphs_jsonl = output_root / f"{bucket}_graphs.jsonl"
    graphs_manifest = output_root / f"{bucket}_graphs.manifest.json"
    sources_jsonl = output_root / f"{bucket}_sources.jsonl"
    sources_rejected = output_root / f"{bucket}_sources.rejected.jsonl"
    run_step(
        [
            "python3",
            str(REPO_ROOT / "docs" / "SGv7pipeline" / "graph_generator" / "01_build_pattern_graphs.py"),
            "--seed",
            str(seed),
            "--bucket",
            bucket,
            "--total-records",
            str(total_records),
            "--output-jsonl",
            str(graphs_jsonl),
            "--output-manifest",
            str(graphs_manifest),
        ],
        cwd=REPO_ROOT,
    )
    run_step(
        [
            "python3",
            str(REPO_ROOT / "docs" / "SGv7pipeline" / "source_generation" / "02_generate_source_variants.py"),
            "--input-jsonl",
            str(graphs_jsonl),
            "--output-jsonl",
            str(sources_jsonl),
            "--reject-log-jsonl",
            str(sources_rejected),
            "--seed",
            str(seed),
            "--difficulty-bucket",
            bucket,
            "--max-variants-per-graph",
            "1",
            "--paraphraser-backend",
            "heuristic",
            "--paraphraser-workers",
            "1",
            "--batch-size",
            "16",
        ],
        cwd=REPO_ROOT,
    )

    cir_rows = read_jsonl(graphs_jsonl)
    cir_by_sample_id: dict[str, dict[str, Any]] = {str(row["sample_id"]): row for row in cir_rows}
    source_rows = read_jsonl(sources_jsonl)
    return source_rows, cir_by_sample_id


def fresh_candidate_row(source_row: dict[str, Any], cir_row: dict[str, Any]) -> dict[str, Any]:
    family_key = graph_fingerprint(cir_row)
    graph_hash = structural_hash(cir_row)
    source_text = str(source_row.get("source_text", "")).strip()
    metadata = {
        "contract_version": "sg_v7_contract_v1",
        "graph_family_key": family_key,
        "split_family_id": family_key,
        "graph_hash": graph_hash,
        "difficulty_bucket": str(cir_row.get("difficulty_bucket", "")),
        "pattern_name": str(cir_row.get("pattern_name", "")),
        "pattern_family": str((cir_row.get("internal_metadata") or {}).get("pattern_family", "")),
        "semantic_tags": cir_row.get("semantic_tags", []),
        "sample_id": str(cir_row.get("sample_id", "")),
        "normalized_source_hash": normalized_source_hash_v1(source_text),
        "source_variant_key": str(cir_row.get("source_variant_key", "")),
        "complexity_class": str(cir_row.get("complexity_class", "")),
        "correction_tier": "tier_b_deterministic_canonical",
    }
    return {
        "sample_id": str(cir_row.get("sample_id", "")),
        "source_text": source_text,
        "packaging_metadata": metadata,
    }


def build_gold_script(cir_row: dict[str, Any], *, source_text: str) -> dict[str, Any]:
    return serialize_to_scenescript(cir_row, original_description=source_text)


def iter_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    beats = script.get("beats")
    if not isinstance(beats, list):
        return actions
    for beat in beats:
        if not isinstance(beat, dict):
            continue
        beat_actions = beat.get("actions")
        if not isinstance(beat_actions, list):
            continue
        for action in beat_actions:
            if isinstance(action, dict):
                actions.append(action)
    return actions


def degrade_runtime_reference(script: dict[str, Any], *, salt: int) -> dict[str, Any]:
    degraded = deepcopy(script)
    beats = degraded.get("beats")
    if not isinstance(beats, list) or not beats:
        return degraded
    objects = degraded.get("objects")
    if not isinstance(objects, list):
        objects = []
        degraded["objects"] = objects
    actions = iter_actions(degraded)
    if not actions:
        return degraded

    marked_object_ids = [str(obj.get("id", "")) for obj in objects if isinstance(obj, dict) and str(obj.get("id", "")).startswith("object_marked_")]
    selector = salt % 4

    if selector == 0 and marked_object_ids:
        target_id = marked_object_ids[0]
        for action in actions:
            if str(action.get("target", "")) == target_id:
                action.pop("target", None)
                return degraded

    if selector == 1 and len(beats) >= 2:
        last_beat = beats[-1]
        if isinstance(last_beat, dict) and isinstance(last_beat.get("actions"), list) and last_beat["actions"]:
            last_beat["actions"] = last_beat["actions"][:-1]
            if not last_beat["actions"]:
                beats.pop()
            return degraded

    if selector == 2:
        actor_ids = [str(actor.get("id", "")) for actor in degraded.get("actors", []) if isinstance(actor, dict)]
        fallback_target = actor_ids[1] if len(actor_ids) >= 2 else ""
        for action in reversed(actions):
            current_target = str(action.get("target", ""))
            if current_target and current_target != fallback_target and fallback_target:
                action["target"] = fallback_target
                return degraded

    for beat in beats:
        if not isinstance(beat, dict):
            continue
        beat_actions = beat.get("actions")
        if isinstance(beat_actions, list) and len(beat_actions) >= 2:
            beat["actions"] = beat_actions[:-1]
            return degraded
    return degraded


def materialize_case(
    *,
    row_stub: dict[str, Any],
    cir_row: dict[str, Any],
    eval_case_id: str,
    eval_set: str,
    provenance_origin: str,
    rule_reference_script: dict[str, Any] | None = None,
) -> dict[str, Any]:
    source_text = str(row_stub.get("source_text", ""))
    gold_script = build_gold_script(cir_row, source_text=source_text)
    reference = rule_reference_script if isinstance(rule_reference_script, dict) else gold_script
    case = _build_case_from_row(
        row=row_stub,
        eval_case_id=eval_case_id,
        eval_set=eval_set,
        gold_script=gold_script,
        rule_reference_script=reference,
        provenance_origin=provenance_origin,
    )
    case["graph_family_key"] = str(get_pkg(row_stub).get("graph_family_key", case.get("graph_family_key", "")))
    if provenance_origin == "synthetic_runtime_proxy":
        provenance = case.get("provenance")
        if isinstance(provenance, dict):
            provenance["proxy_strategy"] = "deterministic_offline_degradation_v1"
            provenance["final_script_source"] = "synthetic_runtime_proxy"
            provenance["gold_source"] = "fresh_cir_projection"
    return case


def make_rerun_config(*, output_bundle: Path, output_config: Path) -> None:
    predictions_root = output_bundle.parent / "predictions_fresh262_all_models"
    models: list[dict[str, Any]] = []
    for model in DEFAULT_BENCHMARK_MODELS:
        payload = {
            "id": str(model["id"]),
            "name": str(model["name"]),
            "predictions_path": str(predictions_root / str(model["id"]) / "seed_42.jsonl"),
        }
        if "comparison_role" in model:
            payload["comparison_role"] = model["comparison_role"]
        models.append(payload)
    config = {
        "eval_bundle_dir": str(output_bundle),
        "eval_seed": 20260615,
        "seeds": [42],
        "checkpoint_id_template": "{model_id}_seed{seed}",
        "models": models,
        "pairs": DEFAULT_BENCHMARK_PAIRS,
        "note": "Predictions for fresh262 bundle must be regenerated before benchmark execution.",
    }
    _write_json(output_config, config)


def make_rerun_readme(*, output_path: Path, output_bundle: Path, output_config: Path) -> None:
    lines = [
        "# Fresh 262 benchmark rerun",
        "",
        "Этот bundle честно очищен от overlap со всеми train-корпусами сравниваемых поколений.",
        "",
        "## Что уже готово",
        "",
        f"- eval bundle: `{output_bundle}`",
        f"- benchmark config template: `{output_config}`",
        "",
        "## Что ещё нужно",
        "",
        "1. Сгенерировать новые predictions JSONL для всех моделей на этом bundle.",
        "2. Только после этого запускать `run_scientific_benchmark.py`.",
        "",
        "Старые prediction exports на bundle v1 переиспользовать нельзя: `eval_case_id` и тексты уже другие.",
        "",
        "## Почему runtime-срез помечен как proxy",
        "",
        "В старых внутренних пулах не осталось leakage-safe real runtime кейсов.",
        "Поэтому 64 runtime-case replacement materialized как synthetic runtime proxies:",
        "- gold берётся из fresh CIR projection;",
        "- rule_based_reference_json получается детерминированной деградацией gold;",
        "- provenance это явно фиксирует.",
    ]
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a fully refreshed 262-case eval bundle with strict anti-leakage filtering.")
    parser.add_argument("--output-bundle", type=Path, default=DEFAULT_OUTPUT_BUNDLE)
    parser.add_argument("--output-config", type=Path, default=DEFAULT_OUTPUT_CONFIG)
    parser.add_argument("--output-readme", type=Path, default=DEFAULT_OUTPUT_README)
    parser.add_argument("--generation-root", type=Path, default=DEFAULT_GENERATION_ROOT)
    parser.add_argument("--core-seed", type=int, default=20260615)
    parser.add_argument("--hard-seed", type=int, default=20260616)
    parser.add_argument("--core-target", type=int, default=109)
    parser.add_argument("--hard-target", type=int, default=89)
    parser.add_argument("--runtime-target", type=int, default=64)
    parser.add_argument("--core-generate", type=int, default=320)
    parser.add_argument("--hard-generate", type=int, default=280)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    corpus_indexes = build_corpus_indexes(DEFAULT_CORPORA)

    original_bundle = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "eval_bundle_v1" / "eval_cases.jsonl"
    original_cases = read_jsonl(original_bundle)
    original_overlap = build_overlap_summary(original_cases, corpus_indexes=corpus_indexes)

    core_sources, core_cir = build_fresh_source_pool(
        bucket="core",
        total_records=args.core_generate,
        seed=args.core_seed,
        output_root=args.generation_root,
    )
    hard_sources, hard_cir = build_fresh_source_pool(
        bucket="hard",
        total_records=args.hard_generate,
        seed=args.hard_seed,
        output_root=args.generation_root,
    )

    used_sample_ids: set[str] = set()
    used_sources: set[str] = set()
    used_families: set[str] = set()

    def select_clean(
        source_rows: list[dict[str, Any]],
        cir_by_sample_id: dict[str, dict[str, Any]],
        *,
        limit: int,
    ) -> list[tuple[dict[str, Any], dict[str, Any]]]:
        selected: list[tuple[dict[str, Any], dict[str, Any]]] = []
        for source_row in source_rows:
            sample_id = str(source_row.get("sample_id", "")).strip()
            cir_row = cir_by_sample_id.get(sample_id)
            if cir_row is None:
                continue
            row_stub = fresh_candidate_row(source_row, cir_row)
            reasons = overlap_reasons(row_stub, corpus_indexes=corpus_indexes)
            if reasons:
                continue
            source_norm = normalized_source_text(str(row_stub.get("source_text", "")))
            family_key = str(get_pkg(row_stub).get("graph_family_key", "")).lower()
            sample_key = str(row_stub.get("sample_id", "")).lower()
            if sample_key in used_sample_ids or source_norm in used_sources or family_key in used_families:
                continue
            used_sample_ids.add(sample_key)
            used_sources.add(source_norm)
            used_families.add(family_key)
            selected.append((row_stub, cir_row))
            if len(selected) >= limit:
                break
        return selected

    selected_core = select_clean(core_sources, core_cir, limit=args.core_target)
    selected_hard_and_runtime = select_clean(hard_sources, hard_cir, limit=args.hard_target + args.runtime_target)
    if len(selected_core) < args.core_target:
        raise SystemExit(f"Not enough clean core replacements: need {args.core_target}, got {len(selected_core)}")
    if len(selected_hard_and_runtime) < args.hard_target + args.runtime_target:
        raise SystemExit(
            "Not enough clean hard/runtime replacements: "
            f"need {args.hard_target + args.runtime_target}, got {len(selected_hard_and_runtime)}"
        )

    selected_hard = selected_hard_and_runtime[: args.hard_target]
    selected_runtime = selected_hard_and_runtime[args.hard_target : args.hard_target + args.runtime_target]

    eval_cases: list[dict[str, Any]] = []
    for idx, (row_stub, cir_row) in enumerate(selected_core, start=1):
        case = materialize_case(
            row_stub=row_stub,
            cir_row=cir_row,
            eval_case_id=f"synr-{idx:04d}::{row_stub['sample_id']}",
            eval_set="synthetic_heldout",
            provenance_origin="synthetic_refresh",
        )
        eval_cases.append(case)

    for idx, (row_stub, cir_row) in enumerate(selected_hard, start=1):
        case = materialize_case(
            row_stub=row_stub,
            cir_row=cir_row,
            eval_case_id=f"hardr-{idx:04d}::{row_stub['sample_id']}",
            eval_set="hard_heldout",
            provenance_origin="synthetic_refresh",
        )
        eval_cases.append(case)

    for idx, (row_stub, cir_row) in enumerate(selected_runtime, start=1):
        gold_script = build_gold_script(cir_row, source_text=str(row_stub["source_text"]))
        rule_reference = degrade_runtime_reference(gold_script, salt=idx)
        row_with_proxy = deepcopy(row_stub)
        row_with_proxy["recoverability_score"] = 0.85
        row_pkg = get_pkg(row_with_proxy)
        row_pkg["correction_tier"] = "tier_c_reviewed_merge"
        row_with_proxy["packaging_metadata"] = row_pkg
        case = materialize_case(
            row_stub=row_with_proxy,
            cir_row=cir_row,
            eval_case_id=f"rtr-{idx:04d}::{row_stub['sample_id']}",
            eval_set="real_runtime",
            provenance_origin="synthetic_runtime_proxy",
            rule_reference_script=rule_reference,
        )
        eval_cases.append(case)

    final_overlap = build_overlap_summary(eval_cases, corpus_indexes=corpus_indexes)
    if final_overlap["excluded"] != 0:
        raise SystemExit(f"Fresh bundle still overlaps training corpora: {final_overlap}")

    args.output_bundle.mkdir(parents=True, exist_ok=True)
    _write_jsonl(args.output_bundle / "eval_cases.jsonl", eval_cases)
    snapshot_hashes = _build_snapshots(args.output_bundle)

    set_counts = {
        "synthetic_heldout": args.core_target,
        "hard_heldout": args.hard_target,
        "real_runtime": args.runtime_target,
    }
    manifest = {
        "bundle_id": "sg_fresh262_eval_bundle_v2",
        "bundle_version": "eval_bundle_v2_fresh262_all_models",
        "contract_version": "sg_v7_contract_v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "required_contract_snapshots": list(snapshot_hashes.keys()),
        "expected_snapshot_hashes": snapshot_hashes,
        "set_counts": set_counts,
        "required_metrics": REQUIRED_METRICS,
        "provenance": {
            "methodology_version": "strict_fresh262_refresh_v1",
            "core_seed": args.core_seed,
            "hard_seed": args.hard_seed,
            "core_generate": args.core_generate,
            "hard_generate": args.hard_generate,
            "strict_match_policy": [
                "sample_id",
                "source_text",
                "normalized_source_hash",
                "graph_family_key_with_short_hash_normalization",
            ],
            "runtime_slice_note": "real_runtime set is a synthetic runtime-proxy refresh because no unused leakage-safe runtime pool remained.",
        },
    }
    _write_json(args.output_bundle / "eval_bundle_manifest.json", manifest)

    audit = {
        "methodology_version": "strict_fresh262_refresh_v1",
        "corpora_checked": corpus_indexes["corpora"],
        "original_eval_bundle_v1": {
            "path": str(original_bundle),
            "strict_overlap_summary": original_overlap,
        },
        "fresh_generation": {
            "core_seed": args.core_seed,
            "hard_seed": args.hard_seed,
            "core_generate": args.core_generate,
            "hard_generate": args.hard_generate,
            "selected_counts": {
                "synthetic_heldout": len(selected_core),
                "hard_heldout": len(selected_hard),
                "real_runtime": len(selected_runtime),
            },
        },
        "final_bundle": {
            "path": str(args.output_bundle / "eval_cases.jsonl"),
            "strict_overlap_summary": final_overlap,
        },
        "limitations": [
            "fresh262 bundle is leakage-safe against the checked train corpora, but it requires regenerated model predictions before metric reporting.",
            "real_runtime slice was rebuilt as synthetic runtime proxies because no unused leakage-safe runtime reserve remained inside historical SGv7 pools.",
        ],
    }
    _write_json(args.output_bundle / "strict_overlap_audit.json", audit)

    markdown_lines = [
        "# Fresh 262 strict refresh audit",
        "",
        "## Main result",
        "",
        f"- Original `eval_bundle_v1`: retained `{original_overlap['retained']}` / `{original_overlap['total']}` under strict matching.",
        f"- Fresh `eval_bundle_v2_fresh262_all_models`: retained `{final_overlap['retained']}` / `{final_overlap['total']}` under strict matching.",
        "",
        "## Original bundle overlap",
        "",
        f"- excluded: `{original_overlap['excluded']}`",
        f"- by set: `{json.dumps(original_overlap['excluded_by_set'], ensure_ascii=False)}`",
        f"- reasons: `{json.dumps(original_overlap['reason_counts'], ensure_ascii=False)}`",
        "",
        "## Fresh bundle composition",
        "",
        f"- synthetic_heldout: `{len(selected_core)}`",
        f"- hard_heldout: `{len(selected_hard)}`",
        f"- real_runtime (synthetic proxy): `{len(selected_runtime)}`",
        "",
        "## Important note",
        "",
        "Новый bundle готов для честного model-vs-model rerun, но старые prediction-файлы от `eval_bundle_v1` к нему неприменимы.",
    ]
    (args.output_bundle / "strict_overlap_audit.md").write_text("\n".join(markdown_lines) + "\n", encoding="utf-8")

    make_rerun_config(output_bundle=args.output_bundle, output_config=args.output_config)
    make_rerun_readme(output_path=args.output_readme, output_bundle=args.output_bundle, output_config=args.output_config)

    print(f"[fresh262] bundle={args.output_bundle}")
    print(f"[fresh262] config={args.output_config}")
    print(f"[fresh262] readme={args.output_readme}")
    print(f"[fresh262] original_retained={original_overlap['retained']} of {original_overlap['total']}")
    print(f"[fresh262] final_retained={final_overlap['retained']} of {final_overlap['total']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
