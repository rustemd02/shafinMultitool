#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class CorpusSpec:
    corpus_id: str
    description: str
    path: Path
    output_contract: str
    note: str


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_BUNDLE = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "eval_bundle_v1"
DEFAULT_OUTPUT_BUNDLE = REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "eval_bundle_v1_leakage_aware_all_models"

DEFAULT_CORPORA: tuple[CorpusSpec, ...] = (
    CorpusSpec(
        corpus_id="v7_sft_train",
        description="SG v7 direct SceneScript SFT train corpus",
        path=REPO_ROOT / "docs" / "SGv7pipeline" / "runs" / "sgv7_full_20260417" / "final" / "dataset" / "sft_train.jsonl",
        output_contract="sg_v7_contract_v1",
        note="Shared SFT base for direct SceneScript v7/v7_orpo checkpoints.",
    ),
    CorpusSpec(
        corpus_id="v7_pref_train",
        description="SG v7 ORPO preference train corpus",
        path=REPO_ROOT / "docs" / "SGv7pipeline" / "runs" / "sgv7_full_20260417" / "final" / "dataset" / "preference_train.jsonl",
        output_contract="preference_pairs",
        note="Checked for overlap because v7_orpo checkpoints depend on this corpus.",
    ),
    CorpusSpec(
        corpus_id="v8_plan_sft_all",
        description="SG v8 ScenePlanIR SFT corpus",
        path=REPO_ROOT / "docs" / "SGv8pipeline" / "runs" / "v8_0_seed42" / "plan_sft" / "v8_plan_sft_all.jsonl",
        output_contract="sg_v8_plan_ir_v1",
        note="Core SFT data for v8 plan checkpoints.",
    ),
    CorpusSpec(
        corpus_id="v8_plan_pref_all",
        description="SG v8 preference corpus",
        path=REPO_ROOT / "docs" / "SGv8pipeline" / "runs" / "v8_0_seed42" / "plan_preference_iter2_vs_v7" / "v8_plan_preference_all.jsonl",
        output_contract="preference_pairs",
        note="Preference data used by v8 ORPO training.",
    ),
    CorpusSpec(
        corpus_id="v9_0_event_sft_all",
        description="SG v9.0 slot/event SFT corpus",
        path=REPO_ROOT / "docs" / "SGv9pipeline" / "runs" / "v9_0_seed42" / "event_sft" / "v9_event_sft_all.jsonl",
        output_contract="sg_v9_event_table_v1",
        note="Initial slot/event training data for v9.0 event_sft.",
    ),
    CorpusSpec(
        corpus_id="v9_2_mixed_all",
        description="SG v9.2 mixed slot/event SFT corpus",
        path=REPO_ROOT / "docs" / "SGv9pipeline" / "runs" / "v9_2_seed42" / "mixed_event_sft" / "v9_2_event_sft_mixed_all.jsonl",
        output_contract="sg_v9_event_table_v1",
        note="Contains targeted hard cases and explicit origin links back to the eval bundle.",
    ),
    CorpusSpec(
        corpus_id="v9_3_mixed_all",
        description="SG v9.3 mixed slot/event SFT corpus",
        path=REPO_ROOT / "docs" / "SGv9pipeline" / "runs" / "v9_3_seed42" / "mixed_event_sft" / "v9_3_event_sft_mixed_all.jsonl",
        output_contract="sg_v9_event_table_v1",
        note="Fresh successor dataset; also checked for direct and family-level overlap.",
    ),
)


DEFAULT_BENCHMARK_MODELS: list[dict[str, Any]] = [
    {
        "id": "base_qwen3_1_7b",
        "name": "Base Qwen3-1.7B",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv7pipeline"
            / "runs"
            / "sgv7_full_20260417"
            / "iter2"
            / "benchmark_results_seed42"
            / "predictions_sanitized"
            / "base_qwen3_1_7b"
            / "seed_42.jsonl"
        ),
    },
    {
        "id": "dataset_v7",
        "name": "SG v7 direct SceneScript",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv7pipeline"
            / "runs"
            / "sgv7_full_20260417"
            / "iter2"
            / "benchmark_results_seed42"
            / "predictions_sanitized"
            / "dataset_v7"
            / "seed_42.jsonl"
        ),
    },
    {
        "id": "dataset_v7_orpo_iter1",
        "name": "SG v7 ORPO iter1",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv7pipeline"
            / "runs"
            / "sgv7_full_20260417"
            / "iter2"
            / "benchmark_results_seed42"
            / "predictions_sanitized"
            / "dataset_v7_orpo_iter1"
            / "seed_42.jsonl"
        ),
    },
    {
        "id": "dataset_v7_orpo_iter2",
        "name": "SG v7 ORPO iter2",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv7pipeline"
            / "runs"
            / "sgv7_full_20260417"
            / "iter2"
            / "benchmark_results_seed42"
            / "predictions_sanitized"
            / "dataset_v7_orpo_iter2"
            / "seed_42.jsonl"
        ),
    },
    {
        "id": "dataset_v8_plan_sft",
        "name": "SG v8 ScenePlanIR SFT",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv8pipeline"
            / "runs"
            / "v8_0_seed42"
            / "eval_artifacts"
            / "dataset_v8_plan_sft_seed42.compiled_predictions.jsonl"
        ),
        "v8_plan_case_results_path": str(
            REPO_ROOT
            / "docs"
            / "SGv8pipeline"
            / "runs"
            / "v8_0_seed42"
            / "eval_artifacts"
            / "dataset_v8_plan_sft_seed42.plan_case_results.jsonl"
        ),
    },
    {
        "id": "dataset_v8_plan_orpo_iter1",
        "name": "SG v8 ScenePlanIR ORPO iter1",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv8pipeline"
            / "runs"
            / "v8_0_seed42"
            / "eval_artifacts"
            / "dataset_v8_plan_orpo_iter1_seed42.compiled_predictions.jsonl"
        ),
        "v8_plan_case_results_path": str(
            REPO_ROOT
            / "docs"
            / "SGv8pipeline"
            / "runs"
            / "v8_0_seed42"
            / "eval_artifacts"
            / "dataset_v8_plan_orpo_iter1_seed42.plan_case_results.jsonl"
        ),
    },
    {
        "id": "dataset_v9_event_sft",
        "name": "SG v9.0 slot/event SFT",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv9pipeline"
            / "runs"
            / "v9_0_seed42"
            / "eval_artifacts"
            / "dataset_v9_event_sft_seed42.compiled_predictions.jsonl"
        ),
    },
    {
        "id": "dataset_v9_2_event_sft_policy_v93",
        "name": "SG v9.2 frozen predictions with V9.3 policy replay",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv9pipeline"
            / "runs"
            / "v9_2_seed42"
            / "from_user_predictions_policy_v93"
            / "eval_artifacts"
            / "dataset_v9_2_event_sft_policy_v93_seed42.compiled_predictions.jsonl"
        ),
        "comparison_role": "policy_replay_reference",
    },
    {
        "id": "dataset_v9_3_event_sft",
        "name": "SG v9.3 slot/event successor",
        "predictions_path": str(
            REPO_ROOT
            / "docs"
            / "SGv9pipeline"
            / "runs"
            / "v9_3_seed42"
            / "from_user_predictions"
            / "eval_artifacts"
            / "dataset_v9_3_event_sft_seed42.compiled_predictions.jsonl"
        ),
    },
]

DEFAULT_BENCHMARK_PAIRS: list[list[str]] = [
    ["dataset_v7", "base_qwen3_1_7b"],
    ["dataset_v7_orpo_iter1", "dataset_v7"],
    ["dataset_v7_orpo_iter2", "dataset_v7_orpo_iter1"],
    ["dataset_v8_plan_sft", "dataset_v7_orpo_iter2"],
    ["dataset_v8_plan_orpo_iter1", "dataset_v8_plan_sft"],
    ["dataset_v9_event_sft", "dataset_v8_plan_orpo_iter1"],
    ["dataset_v9_2_event_sft_policy_v93", "dataset_v9_event_sft"],
    ["dataset_v9_3_event_sft", "dataset_v9_event_sft"],
    ["dataset_v9_3_event_sft", "dataset_v8_plan_orpo_iter1"],
    ["dataset_v9_3_event_sft", "dataset_v7_orpo_iter2"],
]


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON object expected in {path}")
    return payload


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


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")


def get_nested(payload: dict[str, Any], *keys: str) -> Any:
    current: Any = payload
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def first_nonempty_string(values: list[Any]) -> str | None:
    for value in values:
        if isinstance(value, str):
            text = value.strip()
            if text:
                return text
    return None


def infer_graph_family_key(row: dict[str, Any]) -> str | None:
    return first_nonempty_string(
        [
            row.get("graph_family_key"),
            row.get("split_family_id"),
            get_nested(row, "packaging_metadata", "graph_family_key"),
            get_nested(row, "packaging_metadata", "split_family_id"),
        ]
    )


def infer_source_text(row: dict[str, Any]) -> str | None:
    return first_nonempty_string(
        [
            row.get("source_text"),
            get_nested(row, "packaging_metadata", "source_text"),
            get_nested(row, "target_json", "originalDescription"),
            get_nested(row, "compiled_target_json", "originalDescription"),
        ]
    )


def infer_eval_origin_ids(row: dict[str, Any]) -> list[str]:
    values = [
        row.get("v9_2_origin_eval_case_id"),
        row.get("v9_3_origin_eval_case_id"),
        get_nested(row, "packaging_metadata", "v9_2_origin_eval_case_id"),
        get_nested(row, "packaging_metadata", "v9_3_origin_eval_case_id"),
    ]
    result: list[str] = []
    for value in values:
        if isinstance(value, str):
            text = value.strip()
            if text and text not in result:
                result.append(text)
    return result


def copy_bundle_files(source_bundle: Path, output_bundle: Path) -> None:
    if output_bundle.exists():
        shutil.rmtree(output_bundle)
    output_bundle.mkdir(parents=True, exist_ok=True)
    for item in source_bundle.iterdir():
        target = output_bundle / item.name
        if item.is_dir():
            shutil.copytree(item, target)
        elif item.name != "eval_cases.jsonl":
            shutil.copy2(item, target)


def build_overlap_audit(
    *,
    eval_cases: list[dict[str, Any]],
    corpora: tuple[CorpusSpec, ...],
) -> dict[str, Any]:
    eval_by_id = {
        str(row.get("eval_case_id", "")).strip(): row
        for row in eval_cases
        if str(row.get("eval_case_id", "")).strip()
    }
    eval_by_source = {
        str(row.get("source_text", "")).strip(): str(row.get("eval_case_id", "")).strip()
        for row in eval_cases
        if str(row.get("source_text", "")).strip() and str(row.get("eval_case_id", "")).strip()
    }
    eval_by_family = {
        str(row.get("graph_family_key", "")).strip(): str(row.get("eval_case_id", "")).strip()
        for row in eval_cases
        if str(row.get("graph_family_key", "")).strip() and str(row.get("eval_case_id", "")).strip()
    }

    overlaps_by_case: dict[str, dict[str, Any]] = {}
    corpus_rows: list[dict[str, Any]] = []

    for corpus in corpora:
        rows = read_jsonl(corpus.path)
        row_count = len(rows)
        direct_origin_hits = 0
        source_text_hits = 0
        family_hits = 0
        matched_case_ids: set[str] = set()
        for row_index, row in enumerate(rows, start=1):
            row_reasons: list[dict[str, Any]] = []
            for origin_case_id in infer_eval_origin_ids(row):
                if origin_case_id in eval_by_id:
                    direct_origin_hits += 1
                    row_reasons.append(
                        {
                            "reason": "direct_origin_eval_case_id",
                            "eval_case_id": origin_case_id,
                            "row_index": row_index,
                        }
                    )
            source_text = infer_source_text(row)
            matched_by_source = eval_by_source.get(source_text or "")
            if matched_by_source:
                source_text_hits += 1
                row_reasons.append(
                    {
                        "reason": "exact_source_text",
                        "eval_case_id": matched_by_source,
                        "row_index": row_index,
                    }
                )
            family_key = infer_graph_family_key(row)
            matched_by_family = eval_by_family.get(family_key or "")
            if matched_by_family:
                family_hits += 1
                row_reasons.append(
                    {
                        "reason": "graph_family_key",
                        "eval_case_id": matched_by_family,
                        "row_index": row_index,
                    }
                )

            seen_case_reason_pairs: set[tuple[str, str]] = set()
            for reason_payload in row_reasons:
                eval_case_id = str(reason_payload["eval_case_id"])
                reason = str(reason_payload["reason"])
                pair = (eval_case_id, reason)
                if pair in seen_case_reason_pairs:
                    continue
                seen_case_reason_pairs.add(pair)
                matched_case_ids.add(eval_case_id)
                case_record = overlaps_by_case.setdefault(
                    eval_case_id,
                    {
                        "eval_case_id": eval_case_id,
                        "eval_set": str(eval_by_id[eval_case_id].get("eval_set", "")),
                        "source_text": str(eval_by_id[eval_case_id].get("source_text", "")),
                        "graph_family_key": str(eval_by_id[eval_case_id].get("graph_family_key", "")),
                        "overlaps": [],
                    },
                )
                case_record["overlaps"].append(
                    {
                        "corpus_id": corpus.corpus_id,
                        "reason": reason,
                        "row_index": int(reason_payload["row_index"]),
                        "corpus_path": str(corpus.path),
                    }
                )

        corpus_rows.append(
            {
                "corpus_id": corpus.corpus_id,
                "description": corpus.description,
                "path": str(corpus.path),
                "output_contract": corpus.output_contract,
                "note": corpus.note,
                "row_count": row_count,
                "matched_eval_case_count": len(matched_case_ids),
                "direct_origin_hits": direct_origin_hits,
                "source_text_hits": source_text_hits,
                "graph_family_hits": family_hits,
            }
        )

    total_by_set: dict[str, int] = {}
    for row in eval_cases:
        set_name = str(row.get("eval_set", "")).strip() or "unknown"
        total_by_set[set_name] = total_by_set.get(set_name, 0) + 1

    excluded_case_ids = sorted(overlaps_by_case.keys())
    excluded_by_set: dict[str, int] = {}
    for case_id in excluded_case_ids:
        set_name = str(overlaps_by_case[case_id].get("eval_set", "")).strip() or "unknown"
        excluded_by_set[set_name] = excluded_by_set.get(set_name, 0) + 1

    retained_by_set = {
        set_name: total_by_set.get(set_name, 0) - excluded_by_set.get(set_name, 0)
        for set_name in sorted(total_by_set.keys())
    }

    excluded_case_rows: list[dict[str, Any]] = []
    for case_id in excluded_case_ids:
        row = overlaps_by_case[case_id]
        overlap_counts: dict[str, int] = {}
        corpus_ids: list[str] = []
        for item in row["overlaps"]:
            corpus_id = str(item["corpus_id"])
            corpus_ids.append(corpus_id)
            reason = str(item["reason"])
            overlap_counts[reason] = overlap_counts.get(reason, 0) + 1
        unique_corpus_ids = sorted(set(corpus_ids))
        excluded_case_rows.append(
            {
                **row,
                "overlap_corpus_count": len(unique_corpus_ids),
                "overlap_corpus_ids": unique_corpus_ids,
                "reason_counts": overlap_counts,
            }
        )

    return {
        "methodology_version": "leakage_aware_eval_bundle_v1",
        "matching_policy": {
            "exclude_if_any": [
                "direct_origin_eval_case_id",
                "exact_source_text",
                "graph_family_key",
            ],
            "purpose": (
                "Construct a conservative clean holdout for cross-generation Scene Generator comparison. "
                "Family-level matches are treated as leakage because source texts are often paraphrased over a shared semantic graph."
            ),
        },
        "corpora_checked": corpus_rows,
        "total_eval_case_count": len(eval_cases),
        "excluded_eval_case_count": len(excluded_case_ids),
        "retained_eval_case_count": len(eval_cases) - len(excluded_case_ids),
        "total_by_set": total_by_set,
        "excluded_by_set": excluded_by_set,
        "retained_by_set": retained_by_set,
        "excluded_eval_case_ids": excluded_case_ids,
        "excluded_eval_cases": excluded_case_rows,
    }


def write_audit_markdown(output_path: Path, audit: dict[str, Any], source_bundle: Path, output_bundle: Path) -> None:
    corpora = audit["corpora_checked"]
    lines: list[str] = []
    lines.append("# Leakage-aware eval bundle audit")
    lines.append("")
    lines.append("## Setup")
    lines.append(f"- source bundle: `{source_bundle}`")
    lines.append(f"- output bundle: `{output_bundle}`")
    lines.append(f"- total eval cases: {audit['total_eval_case_count']}")
    lines.append(f"- excluded eval cases: {audit['excluded_eval_case_count']}")
    lines.append(f"- retained eval cases: {audit['retained_eval_case_count']}")
    lines.append("")
    lines.append("## Matching policy")
    lines.append("")
    lines.append(
        "A case is excluded if any compared training corpus links to it by explicit origin case id, exact `source_text`, "
        "or shared `graph_family_key`."
    )
    lines.append("")
    lines.append("## Excluded / retained by set")
    lines.append("")
    lines.append("| Eval set | Total | Excluded | Retained |")
    lines.append("| --- | ---: | ---: | ---: |")
    for set_name in sorted(audit["total_by_set"].keys()):
        lines.append(
            f"| {set_name} | {audit['total_by_set'].get(set_name, 0)} | {audit['excluded_by_set'].get(set_name, 0)} | {audit['retained_by_set'].get(set_name, 0)} |"
        )
    lines.append("")
    lines.append("## Corpus overlap summary")
    lines.append("")
    lines.append("| Corpus | Rows | Matched eval cases | Direct origin hits | Exact source hits | Family hits |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    for row in corpora:
        lines.append(
            f"| {row['corpus_id']} | {row['row_count']} | {row['matched_eval_case_count']} | {row['direct_origin_hits']} | {row['source_text_hits']} | {row['graph_family_hits']} |"
        )
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    for row in corpora:
        lines.append(f"- `{row['corpus_id']}`: {row['note']}")
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_benchmark_config(eval_bundle_dir: Path, output_path: Path) -> None:
    models: list[dict[str, Any]] = []
    for model in DEFAULT_BENCHMARK_MODELS:
        row: dict[str, Any] = {
            "id": model["id"],
            "name": model["name"],
            "predictions_path": model["predictions_path"],
        }
        if "v8_plan_case_results_path" in model:
            row["v8_plan_case_results_path"] = model["v8_plan_case_results_path"]
        if "comparison_role" in model:
            row["comparison_role"] = model["comparison_role"]
        models.append(row)

    payload = {
        "eval_bundle_dir": str(eval_bundle_dir),
        "eval_seed": 20260419,
        "seeds": [42],
        "checkpoint_id_template": "{model_id}_seed{seed}",
        "models": models,
        "pairs": DEFAULT_BENCHMARK_PAIRS,
        "slice_gate_baseline_model_id": "dataset_v7_orpo_iter2",
        "notes": {
            "primary_model_vs_model_rows": [
                model["id"]
                for model in DEFAULT_BENCHMARK_MODELS
                if model.get("comparison_role") != "policy_replay_reference"
            ],
            "policy_replay_reference_rows": [
                model["id"]
                for model in DEFAULT_BENCHMARK_MODELS
                if model.get("comparison_role") == "policy_replay_reference"
            ],
            "purpose": (
                "Leakage-aware seed42 benchmark on existing prediction artifacts. "
                "The V9.2 policy replay row is retained as a methodology reference, not as a fresh model checkpoint."
            ),
        },
    }
    write_json(output_path, payload)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Build a leakage-aware filtered eval bundle for Scene Generator model comparison and "
            "write a ready-to-run benchmark config for the retained holdout."
        )
    )
    parser.add_argument("--source-bundle", type=Path, default=DEFAULT_SOURCE_BUNDLE)
    parser.add_argument("--output-bundle", type=Path, default=DEFAULT_OUTPUT_BUNDLE)
    parser.add_argument(
        "--benchmark-config-out",
        type=Path,
        default=REPO_ROOT / "experiments" / "sc_benchmark" / "workspace" / "benchmark_config.seed42.leakage_aware_all_models.json",
    )
    args = parser.parse_args()

    source_bundle = args.source_bundle.expanduser().resolve()
    output_bundle = args.output_bundle.expanduser().resolve()
    benchmark_config_out = args.benchmark_config_out.expanduser().resolve()

    eval_cases_path = source_bundle / "eval_cases.jsonl"
    manifest_path = source_bundle / "eval_bundle_manifest.json"
    if not eval_cases_path.exists():
        raise SystemExit(f"Missing eval cases: {eval_cases_path}")
    if not manifest_path.exists():
        raise SystemExit(f"Missing bundle manifest: {manifest_path}")

    for corpus in DEFAULT_CORPORA:
        if not corpus.path.exists():
            raise SystemExit(f"Missing overlap corpus: {corpus.path}")

    eval_cases = read_jsonl(eval_cases_path)
    source_manifest = read_json(manifest_path)
    audit = build_overlap_audit(eval_cases=eval_cases, corpora=DEFAULT_CORPORA)

    excluded_case_ids = set(audit["excluded_eval_case_ids"])
    retained_cases = [
        row for row in eval_cases if str(row.get("eval_case_id", "")).strip() not in excluded_case_ids
    ]
    excluded_cases = [
        row for row in eval_cases if str(row.get("eval_case_id", "")).strip() in excluded_case_ids
    ]

    copy_bundle_files(source_bundle, output_bundle)
    write_jsonl(output_bundle / "eval_cases.jsonl", retained_cases)
    write_jsonl(output_bundle / "excluded_eval_cases.jsonl", excluded_cases)
    write_json(output_bundle / "leakage_audit.json", audit)
    write_audit_markdown(output_bundle / "leakage_audit.md", audit, source_bundle, output_bundle)

    updated_manifest = dict(source_manifest)
    updated_manifest["bundle_id"] = f"{source_manifest.get('bundle_id', 'sgv7_eval_bundle_v1')}__leakage_aware_all_models"
    updated_manifest["bundle_version"] = "eval_bundle_v1_leakage_aware_all_models"
    updated_manifest["set_counts"] = audit["retained_by_set"]
    updated_manifest["provenance"] = {
        **(source_manifest.get("provenance", {}) if isinstance(source_manifest.get("provenance"), dict) else {}),
        "source_bundle_dir": str(source_bundle),
        "leakage_audit_path": str(output_bundle / "leakage_audit.json"),
        "excluded_eval_case_count": audit["excluded_eval_case_count"],
        "retained_eval_case_count": audit["retained_eval_case_count"],
        "matching_policy_version": audit["methodology_version"],
    }
    write_json(output_bundle / "eval_bundle_manifest.json", updated_manifest)

    build_benchmark_config(output_bundle, benchmark_config_out)

    print(f"wrote filtered bundle: {output_bundle}")
    print(f"retained eval cases: {audit['retained_eval_case_count']}")
    print(f"excluded eval cases: {audit['excluded_eval_case_count']}")
    print(f"wrote benchmark config: {benchmark_config_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
