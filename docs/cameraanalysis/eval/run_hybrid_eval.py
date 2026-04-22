#!/usr/bin/env python3
"""Run staged hybrid eval harness for PR-H14."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict, List, Tuple

from adapters import CandidateDeterministicRunner, LegacyBaselineRunner
from compare import build_compare_report, render_markdown_summary
from compare_hybrid import build_ablation_summary, render_hybrid_markdown_summary
from eval_io import load_bundle, read_json, read_jsonl, write_json, write_jsonl
from scorer import score_model, validate_sequence_contract
from scorer_hybrid import (
    extract_final_outputs,
    normalize_projection_rows,
    score_hybrid_variant,
    validate_hybrid_case_contract,
    validate_variant_projections,
)


BUILTIN_RUNNERS = {
    "camera_analysis_v1_core": CandidateDeterministicRunner,
    "candidate_deterministic": CandidateDeterministicRunner,
    "candidate": CandidateDeterministicRunner,
    "legacy_suggestion_engine": LegacyBaselineRunner,
    "legacy_baseline": LegacyBaselineRunner,
    "legacy": LegacyBaselineRunner,
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Camera Analysis hybrid eval harness runner")
    parser.add_argument("--bundle", required=True, help="Path to eval bundle directory")
    parser.add_argument("--matrix", required=True, help="Path to hybrid variant matrix JSON")
    parser.add_argument("--output", required=True, help="Report output directory")
    return parser.parse_args()


def _normalize_variant_matrix(matrix: Dict[str, Any]) -> Tuple[str, List[Dict[str, Any]]]:
    variants = matrix.get("variants")
    if not isinstance(variants, list) or not variants:
        raise ValueError("variant matrix must contain non-empty 'variants' array")
    anchor_variant_id = matrix.get("anchorVariantId", "deterministic_only")
    if not isinstance(anchor_variant_id, str) or not anchor_variant_id:
        raise ValueError("variant matrix must contain valid anchorVariantId")

    normalized: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for item in variants:
        if not isinstance(item, dict):
            raise ValueError(f"invalid variant entry: {item!r}")
        variant_id = item.get("variantId")
        if not isinstance(variant_id, str) or not variant_id:
            raise ValueError(f"variant is missing variantId: {item!r}")
        if variant_id in seen:
            raise ValueError(f"duplicate variantId '{variant_id}' in matrix")
        seen.add(variant_id)
        source = item.get("source")
        if not isinstance(source, dict):
            raise ValueError(f"{variant_id}: variant must declare source object")
        capabilities = item.get("capabilities") if isinstance(item.get("capabilities"), dict) else {}
        normalized.append(
            {
                "variant_id": variant_id,
                "parent_variant_id": item.get("parentVariantId"),
                "family": item.get("family"),
                "label": item.get("label"),
                "source": source,
                "capabilities": {
                    "pauseLocalHybrid": bool(capabilities.get("pauseLocalHybrid", variant_id != "deterministic_only")),
                    "liveHybrid": bool(capabilities.get("liveHybrid", False)),
                    "offload": bool(capabilities.get("offload", False)),
                },
            }
        )
    if anchor_variant_id not in seen:
        raise ValueError(f"anchorVariantId '{anchor_variant_id}' is not present in variants")
    return anchor_variant_id, normalized


def _generate_builtin_outputs(mode_id: str, cases: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    runner_cls = BUILTIN_RUNNERS.get(mode_id)
    if runner_cls is None:
        raise ValueError(f"unknown builtin mode '{mode_id}' in hybrid variant matrix")
    runner = runner_cls()
    outputs: Dict[str, Dict[str, Any]] = {}
    for case in sorted(cases, key=lambda item: item["eval_case_id"]):
        outputs[str(case["eval_case_id"])] = runner.run_case(case)
    return outputs


def _wrap_builtin_outputs_as_hybrid(
    variant_id: str,
    cases: List[Dict[str, Any]],
    outputs_by_case_id: Dict[str, Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    projections: Dict[str, Dict[str, Any]] = {}
    for case in cases:
        case_id = str(case["eval_case_id"])
        output = outputs_by_case_id.get(case_id, {})
        if case.get("case_kind") == "live_sequence":
            projections[case_id] = {
                "evalCaseId": case_id,
                "projectionKind": "live_sequence",
                "mode": "live",
                "deterministicOutput": output,
                "finalOutput": output,
                "frameArtifacts": [],
            }
        else:
            projections[case_id] = {
                "evalCaseId": case_id,
                "projectionKind": "single_frame",
                "mode": "live" if case.get("case_kind") == "single_frame_live" else "pause",
                "deterministicOutput": output,
                "finalOutput": output,
                "localPhaseOutput": output,
                "fusionDecisions": [],
                "inferenceOutcome": {
                    "status": "disabled",
                    "mode": "live" if case.get("case_kind") == "single_frame_live" else "pause",
                    "hasSnapshot": False,
                    "failureReason": None,
                },
            }
    return projections


def _resolve_variant_projections(
    matrix_path: Path,
    variant: Dict[str, Any],
    cases: List[Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    source = variant["source"]
    kind = source.get("kind", "jsonl")
    if kind == "builtin":
        source_id = source.get("id")
        if not isinstance(source_id, str) or not source_id:
            raise ValueError(f"{variant['variant_id']}: builtin source must declare id")
        outputs = _generate_builtin_outputs(source_id, cases)
        return _wrap_builtin_outputs_as_hybrid(variant["variant_id"], cases, outputs)
    if kind == "jsonl":
        source_path = source.get("path")
        if not isinstance(source_path, str) or not source_path:
            raise ValueError(f"{variant['variant_id']}: jsonl source must declare path")
        path = Path(source_path)
        if not path.is_absolute():
            path = (matrix_path.parent / path).resolve()
        return normalize_projection_rows(read_jsonl(path))
    raise ValueError(f"{variant['variant_id']}: unsupported source.kind '{kind}'")


def _ordered_projection_rows(projections_by_case_id: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [projections_by_case_id[case_id] for case_id in sorted(projections_by_case_id.keys())]


def main() -> None:
    args = _parse_args()
    bundle_dir = Path(args.bundle).resolve()
    matrix_path = Path(args.matrix).resolve()
    output_dir = Path(args.output).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    bundle = load_bundle(bundle_dir)
    manifest = bundle["manifest"]
    cases = bundle["cases"]
    validate_sequence_contract(cases)
    validate_hybrid_case_contract(cases)

    anchor_variant_id, variants = _normalize_variant_matrix(read_json(matrix_path))

    variant_projections: Dict[str, Dict[str, Dict[str, Any]]] = {}
    variant_core_scores: Dict[str, Dict[str, Any]] = {}

    variant_output_dir = output_dir / "variant_outputs"
    variant_output_dir.mkdir(parents=True, exist_ok=True)

    for variant in variants:
        projections = _resolve_variant_projections(matrix_path, variant, cases)
        validate_variant_projections(cases, projections, variant["capabilities"])
        variant_projections[variant["variant_id"]] = projections
        final_outputs = extract_final_outputs(projections)
        variant_core_scores[variant["variant_id"]] = score_model(cases, final_outputs)
        write_jsonl(
            variant_output_dir / f"{variant['variant_id']}.jsonl",
            _ordered_projection_rows(projections),
        )

    anchor_scores = variant_core_scores[anchor_variant_id]
    pairwise_reports: Dict[str, Dict[str, Any]] = {}
    hybrid_variants: List[Dict[str, Any]] = []

    pairwise_json_dir = output_dir / "pairwise_compare"
    pairwise_md_dir = output_dir / "pairwise_summary"
    pairwise_json_dir.mkdir(parents=True, exist_ok=True)
    pairwise_md_dir.mkdir(parents=True, exist_ok=True)

    for variant in variants:
        variant_id = variant["variant_id"]
        if variant_id == anchor_variant_id:
            continue

        anchor_compare = build_compare_report(
            bundle_id=str(manifest.get("bundle_id", "hybrid_eval_bundle")),
            baseline_id=anchor_variant_id,
            candidate_id=variant_id,
            baseline_scores=anchor_scores,
            candidate_scores=variant_core_scores[variant_id],
            manifest=manifest,
        )
        pair_name = f"{anchor_variant_id}__vs__{variant_id}"
        pairwise_reports[pair_name] = anchor_compare
        write_json(pairwise_json_dir / f"{pair_name}.json", anchor_compare)
        (pairwise_md_dir / f"{pair_name}.md").write_text(
            render_markdown_summary(
                bundle_id=str(manifest.get("bundle_id", "hybrid_eval_bundle")),
                baseline_id=anchor_variant_id,
                candidate_id=variant_id,
                compare_report=anchor_compare,
            ),
            encoding="utf-8",
        )

        parent_variant_id = variant.get("parent_variant_id")
        if isinstance(parent_variant_id, str) and parent_variant_id and parent_variant_id in variant_core_scores:
            if parent_variant_id != anchor_variant_id:
                parent_compare = build_compare_report(
                    bundle_id=str(manifest.get("bundle_id", "hybrid_eval_bundle")),
                    baseline_id=parent_variant_id,
                    candidate_id=variant_id,
                    baseline_scores=variant_core_scores[parent_variant_id],
                    candidate_scores=variant_core_scores[variant_id],
                    manifest=manifest,
                )
                parent_name = f"{parent_variant_id}__vs__{variant_id}"
                pairwise_reports[parent_name] = parent_compare
                write_json(pairwise_json_dir / f"{parent_name}.json", parent_compare)
                (pairwise_md_dir / f"{parent_name}.md").write_text(
                    render_markdown_summary(
                        bundle_id=str(manifest.get("bundle_id", "hybrid_eval_bundle")),
                        baseline_id=parent_variant_id,
                        candidate_id=variant_id,
                        compare_report=parent_compare,
                    ),
                    encoding="utf-8",
                )

        hybrid_variants.append(
            score_hybrid_variant(
                variant_id=variant_id,
                parent_variant_id=variant.get("parent_variant_id"),
                family=variant.get("family"),
                capabilities=variant["capabilities"],
                cases=cases,
                projections_by_case_id=variant_projections[variant_id],
                core_scores=variant_core_scores[variant_id],
                anchor_core_scores=anchor_scores,
                anchor_compare=anchor_compare,
            )
        )

    hybrid_metrics = {
        "bundle_id": manifest.get("bundle_id"),
        "anchor_variant_id": anchor_variant_id,
        "variants": {
            row["variant_id"]: row["utility_metrics"]
            for row in hybrid_variants
        },
    }
    explainability_metrics = {
        "bundle_id": manifest.get("bundle_id"),
        "anchor_variant_id": anchor_variant_id,
        "variants": {
            row["variant_id"]: row["agreement_metrics"]
            for row in hybrid_variants
        },
    }
    mobile_metrics = {
        "bundle_id": manifest.get("bundle_id"),
        "anchor_variant_id": anchor_variant_id,
        "variants": {
            row["variant_id"]: row["mobile_metrics"]
            for row in hybrid_variants
        },
    }
    ablation_summary = build_ablation_summary(
        bundle_id=str(manifest.get("bundle_id", "hybrid_eval_bundle")),
        anchor_variant_id=anchor_variant_id,
        variants=hybrid_variants,
    )

    write_json(output_dir / "hybrid_metrics.json", hybrid_metrics)
    write_json(output_dir / "explainability_agreement.json", explainability_metrics)
    write_json(output_dir / "mobile_system_metrics.json", mobile_metrics)
    write_json(output_dir / "ablation_summary.json", ablation_summary)
    (output_dir / "hybrid_eval_summary.md").write_text(
        render_hybrid_markdown_summary(
            bundle_id=str(manifest.get("bundle_id", "hybrid_eval_bundle")),
            anchor_variant_id=anchor_variant_id,
            variants=hybrid_variants,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
