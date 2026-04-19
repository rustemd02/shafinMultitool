#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


class AuditError(RuntimeError):
    pass


def _load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise AuditError(f"Missing required file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise AuditError(f"Invalid JSON in {path}: {exc}") from exc


def _count_jsonl(path: Path) -> int:
    if not path.exists():
        raise AuditError(f"Missing required file: {path}")
    count = 0
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            if raw_line.strip():
                count += 1
    return count


def _safe_int(value: object) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str) and value.strip():
        return int(float(value.strip()))
    return 0


def _reject_ratio(manifest: dict) -> float:
    total = _safe_int(manifest.get("total_input_count"))
    if total <= 0:
        return 0.0
    rejected = _safe_int(manifest.get("rejected_count"))
    return rejected / total


def _max_pattern_share(manifest: dict) -> float:
    counts = manifest.get("pattern_counts", {})
    if not isinstance(counts, dict) or not counts:
        return 0.0
    total = sum(_safe_int(value) for value in counts.values())
    if total <= 0:
        return 0.0
    return max((_safe_int(value) / total) for value in counts.values())


def _pct(value: float) -> str:
    return f"{value * 100:.1f}%"


def _share(count: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return count / total


def run_audit(
    *,
    output_dir: Path,
    min_sft_total: int,
    min_same_type_markers: int,
    min_three_beat_cases: int,
    min_ordinal_cases: int,
    min_exact_marker_identity_cases: int,
    min_marked_object_morphology: int,
    require_preference: bool,
    require_runtime_preference_origin: bool,
    max_source_reject_rate: float | None,
    max_graph_pattern_share: float | None,
    max_final_sft_pattern_share: float | None,
    max_promoted_review_share: float | None,
    max_technical_literal_share: float | None,
    max_meta_language_share: float | None,
    max_surface_noise_share: float | None,
    max_bad_morphology_share: float | None,
) -> None:
    root = output_dir
    dataset_dir = root / "final" / "dataset"

    split_manifest = _load_json(dataset_dir / "split_manifest.json")
    leakage_report = _load_json(dataset_dir / "leakage_report.json")
    preference_manifest = _load_json(dataset_dir / "preference_manifest.json")

    sft_train = _count_jsonl(dataset_dir / "sft_train.jsonl")
    sft_val = _count_jsonl(dataset_dir / "sft_val.jsonl")
    sft_test = _count_jsonl(dataset_dir / "sft_test.jsonl")
    pref_train = _count_jsonl(dataset_dir / "preference_train.jsonl")
    pref_val = _count_jsonl(dataset_dir / "preference_val.jsonl")
    pref_test = _count_jsonl(dataset_dir / "preference_test.jsonl")

    _count_jsonl(root / "final" / "accepted_merged.jsonl")
    _count_jsonl(root / "final" / "cir_merged.jsonl")

    core_source_manifest = _load_json(root / "core" / "source_validation_manifest.json")
    hard_source_manifest = _load_json(root / "hard" / "source_validation_manifest.json")
    core_graph_manifest = _load_json(root / "core" / "graphs.manifest.json")
    hard_graph_manifest = _load_json(root / "hard" / "graphs.manifest.json")

    errors: list[str] = []

    sft_total = sft_train + sft_val + sft_test
    preference_total = pref_train + pref_val + pref_test

    if sft_total < min_sft_total:
        errors.append(f"SFT size too small: {sft_total} < min_sft_total={min_sft_total}")

    if require_preference and preference_total <= 0:
        errors.append("Preference set is empty, but --require-preference is enabled.")

    preference_origins = preference_manifest.get("counts_by_preference_origin", {})
    runtime_origin_count = _safe_int(preference_origins.get("runtime_failure_reviewed_merge"))
    if require_runtime_preference_origin and runtime_origin_count <= 0:
        errors.append(
            "Runtime preference origin is missing, but --require-runtime-preference-origin is enabled."
        )

    leakage_status = str(leakage_report.get("status", "")).strip().lower()
    if leakage_status != "pass":
        errors.append(f"Leakage status must be 'pass', got: {leakage_status or '<empty>'}")

    critical_tags = split_manifest.get("counts_by_critical_eval_tags", {})
    same_type_markers = _safe_int(critical_tags.get("same_type_markers"))
    three_beat_cases = _safe_int(critical_tags.get("three_beat_cases"))
    ordinal_cases = _safe_int(critical_tags.get("ordinal_cases"))
    exact_marker_identity_cases = _safe_int(critical_tags.get("exact_marker_identity_cases"))
    marked_object_morphology = _safe_int(critical_tags.get("marked_object_morphology"))
    if same_type_markers < min_same_type_markers:
        errors.append(
            "same_type_markers coverage is below threshold: "
            f"{same_type_markers} < min_same_type_markers={min_same_type_markers}"
        )
    if three_beat_cases < min_three_beat_cases:
        errors.append(
            "three_beat_cases coverage is below threshold: "
            f"{three_beat_cases} < min_three_beat_cases={min_three_beat_cases}"
        )
    if ordinal_cases < min_ordinal_cases:
        errors.append(
            "ordinal_cases coverage is below threshold: "
            f"{ordinal_cases} < min_ordinal_cases={min_ordinal_cases}"
        )
    if exact_marker_identity_cases < min_exact_marker_identity_cases:
        errors.append(
            "exact_marker_identity_cases coverage is below threshold: "
            f"{exact_marker_identity_cases} < min_exact_marker_identity_cases={min_exact_marker_identity_cases}"
        )
    if marked_object_morphology < min_marked_object_morphology:
        errors.append(
            "marked_object_morphology coverage is below threshold: "
            f"{marked_object_morphology} < min_marked_object_morphology={min_marked_object_morphology}"
        )

    final_pattern_counts = split_manifest.get("counts_by_pattern_name", {})
    final_total = sum(_safe_int(value) for value in final_pattern_counts.values()) if isinstance(final_pattern_counts, dict) else 0
    final_max_pattern_share = 0.0
    if isinstance(final_pattern_counts, dict) and final_total > 0:
        final_max_pattern_share = max(_safe_int(value) / final_total for value in final_pattern_counts.values())

    technical_literal_rows = _safe_int(split_manifest.get("technical_literal_rows"))
    meta_language_rows = _safe_int(split_manifest.get("meta_language_rows"))
    surface_noise_rows = _safe_int(split_manifest.get("surface_noise_rows"))
    bad_morphology_rows = _safe_int(split_manifest.get("bad_morphology_rows"))
    promoted_review_rows = _safe_int(split_manifest.get("promoted_review_rows"))
    technical_literal_share = _share(technical_literal_rows, sft_total)
    meta_language_share = _share(meta_language_rows, sft_total)
    surface_noise_share = _share(surface_noise_rows, sft_total)
    bad_morphology_share = _share(bad_morphology_rows, sft_total)
    promoted_review_share = _share(promoted_review_rows, sft_total)
    lexeme_watch_rows = split_manifest.get("lexeme_watch_rows", {})

    core_reject_ratio = _reject_ratio(core_source_manifest)
    hard_reject_ratio = _reject_ratio(hard_source_manifest)
    core_max_pattern_share = _max_pattern_share(core_graph_manifest)
    hard_max_pattern_share = _max_pattern_share(hard_graph_manifest)
    if max_source_reject_rate is not None:
        if core_reject_ratio > max_source_reject_rate:
            errors.append(
                "Core source reject rate too high: "
                f"{_pct(core_reject_ratio)} > {_pct(max_source_reject_rate)}"
            )
        if hard_reject_ratio > max_source_reject_rate:
            errors.append(
                "Hard source reject rate too high: "
                f"{_pct(hard_reject_ratio)} > {_pct(max_source_reject_rate)}"
            )
    if max_graph_pattern_share is not None:
        if core_max_pattern_share > max_graph_pattern_share:
            errors.append(
                "Core graph pattern skew too high: "
                f"{_pct(core_max_pattern_share)} > {_pct(max_graph_pattern_share)}"
            )
        if hard_max_pattern_share > max_graph_pattern_share:
            errors.append(
                "Hard graph pattern skew too high: "
                f"{_pct(hard_max_pattern_share)} > {_pct(max_graph_pattern_share)}"
            )
    if max_final_sft_pattern_share is not None and final_max_pattern_share > max_final_sft_pattern_share:
        errors.append(
            "Final SFT pattern skew too high: "
            f"{_pct(final_max_pattern_share)} > {_pct(max_final_sft_pattern_share)}"
        )
    if max_promoted_review_share is not None and promoted_review_share > max_promoted_review_share:
        errors.append(
            "Promoted-review share in final SFT is too high: "
            f"{_pct(promoted_review_share)} > {_pct(max_promoted_review_share)}"
        )
    if max_technical_literal_share is not None and technical_literal_share > max_technical_literal_share:
        errors.append(
            "Technical literal share in final SFT is too high: "
            f"{_pct(technical_literal_share)} > {_pct(max_technical_literal_share)}"
        )
    if max_meta_language_share is not None and meta_language_share > max_meta_language_share:
        errors.append(
            "Meta-language share in final SFT is too high: "
            f"{_pct(meta_language_share)} > {_pct(max_meta_language_share)}"
        )
    if max_surface_noise_share is not None and surface_noise_share > max_surface_noise_share:
        errors.append(
            "Surface-noise share in final SFT is too high: "
            f"{_pct(surface_noise_share)} > {_pct(max_surface_noise_share)}"
        )
    if max_bad_morphology_share is not None and bad_morphology_share > max_bad_morphology_share:
        errors.append(
            "Bad-morphology share in final SFT is too high: "
            f"{_pct(bad_morphology_share)} > {_pct(max_bad_morphology_share)}"
        )

    counts_by_split = split_manifest.get("counts_by_split", {})
    preference_counts_by_split = preference_manifest.get("counts_by_split", {})

    print("[sgv7:audit] summary")
    print(f"[sgv7:audit] output_dir={root}")
    print(f"[sgv7:audit] sft_counts(train/val/test)={sft_train}/{sft_val}/{sft_test} total={sft_total}")
    print(
        f"[sgv7:audit] preference_counts(train/val/test)={pref_train}/{pref_val}/{pref_test} "
        f"total={preference_total}"
    )
    print(f"[sgv7:audit] split_manifest.counts_by_split={counts_by_split}")
    print(f"[sgv7:audit] preference_manifest.counts_by_split={preference_counts_by_split}")
    print(f"[sgv7:audit] preference_origins={preference_origins}")
    print(f"[sgv7:audit] leakage_status={leakage_status}")
    print(
        "[sgv7:audit] critical_tags: "
        f"same_type_markers={same_type_markers}, "
        f"three_beat_cases={three_beat_cases}, "
        f"ordinal_cases={ordinal_cases}, "
        f"exact_marker_identity_cases={exact_marker_identity_cases}, "
        f"marked_object_morphology={marked_object_morphology}"
    )
    print(
        "[sgv7:audit] source_reject_rate: "
        f"core={_pct(core_reject_ratio)}, hard={_pct(hard_reject_ratio)}"
    )
    print(
        "[sgv7:audit] max_graph_pattern_share: "
        f"core={_pct(core_max_pattern_share)}, hard={_pct(hard_max_pattern_share)}"
    )
    print(f"[sgv7:audit] max_final_sft_pattern_share={_pct(final_max_pattern_share)}")
    print(
        "[sgv7:audit] final_sft_noise: "
        f"technical={technical_literal_rows} ({_pct(technical_literal_share)}), "
        f"meta={meta_language_rows} ({_pct(meta_language_share)}), "
        f"surface={surface_noise_rows} ({_pct(surface_noise_share)}), "
        f"bad_morphology={bad_morphology_rows} ({_pct(bad_morphology_share)}), "
        f"promoted_review={promoted_review_rows} ({_pct(promoted_review_share)})"
    )
    print(f"[sgv7:audit] lexeme_watch_rows={lexeme_watch_rows}")

    if errors:
        print("[sgv7:audit] FAIL")
        for issue in errors:
            print(f"[sgv7:audit][error] {issue}")
        raise AuditError("SG v7 output audit failed")

    print("[sgv7:audit] PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit SG v7 run outputs and fail on key quality gates.")
    parser.add_argument("--output-dir", type=Path, required=True, help="Root output dir used by run_sgv7_pilot.sh")
    parser.add_argument("--min-sft-total", type=int, default=1, help="Fail if total SFT rows are below this value.")
    parser.add_argument(
        "--min-same-type-markers",
        type=int,
        default=1,
        help="Fail if split_manifest critical coverage for same_type_markers is below this value.",
    )
    parser.add_argument("--min-three-beat-cases", type=int, default=0)
    parser.add_argument("--min-ordinal-cases", type=int, default=0)
    parser.add_argument("--min-exact-marker-identity-cases", type=int, default=0)
    parser.add_argument("--min-marked-object-morphology", type=int, default=0)
    parser.add_argument(
        "--require-preference",
        action="store_true",
        help="Fail when preference_{train,val,test}.jsonl are all empty.",
    )
    parser.add_argument(
        "--require-runtime-preference-origin",
        action="store_true",
        help="Fail when preference manifest has no runtime_failure_reviewed_merge origin rows.",
    )
    parser.add_argument(
        "--max-source-reject-rate",
        type=float,
        help="Optional max allowed reject ratio for core/hard source_validation_manifest (0.0..1.0).",
    )
    parser.add_argument(
        "--max-graph-pattern-share",
        type=float,
        help="Optional max allowed single-pattern share in core/hard graph manifests (0.0..1.0).",
    )
    parser.add_argument("--max-final-sft-pattern-share", type=float)
    parser.add_argument("--max-promoted-review-share", type=float)
    parser.add_argument("--max-technical-literal-share", type=float)
    parser.add_argument("--max-meta-language-share", type=float)
    parser.add_argument("--max-surface-noise-share", type=float)
    parser.add_argument("--max-bad-morphology-share", type=float)
    args = parser.parse_args()

    if args.max_source_reject_rate is not None and not (0.0 <= args.max_source_reject_rate <= 1.0):
        raise SystemExit("--max-source-reject-rate must be within [0.0, 1.0]")
    if args.max_graph_pattern_share is not None and not (0.0 <= args.max_graph_pattern_share <= 1.0):
        raise SystemExit("--max-graph-pattern-share must be within [0.0, 1.0]")
    for value, flag in (
        (args.max_final_sft_pattern_share, "--max-final-sft-pattern-share"),
        (args.max_promoted_review_share, "--max-promoted-review-share"),
        (args.max_technical_literal_share, "--max-technical-literal-share"),
        (args.max_meta_language_share, "--max-meta-language-share"),
        (args.max_surface_noise_share, "--max-surface-noise-share"),
        (args.max_bad_morphology_share, "--max-bad-morphology-share"),
    ):
        if value is not None and not (0.0 <= value <= 1.0):
            raise SystemExit(f"{flag} must be within [0.0, 1.0]")

    run_audit(
        output_dir=args.output_dir,
        min_sft_total=args.min_sft_total,
        min_same_type_markers=args.min_same_type_markers,
        min_three_beat_cases=args.min_three_beat_cases,
        min_ordinal_cases=args.min_ordinal_cases,
        min_exact_marker_identity_cases=args.min_exact_marker_identity_cases,
        min_marked_object_morphology=args.min_marked_object_morphology,
        require_preference=args.require_preference,
        require_runtime_preference_origin=args.require_runtime_preference_origin,
        max_source_reject_rate=args.max_source_reject_rate,
        max_graph_pattern_share=args.max_graph_pattern_share,
        max_final_sft_pattern_share=args.max_final_sft_pattern_share,
        max_promoted_review_share=args.max_promoted_review_share,
        max_technical_literal_share=args.max_technical_literal_share,
        max_meta_language_share=args.max_meta_language_share,
        max_surface_noise_share=args.max_surface_noise_share,
        max_bad_morphology_share=args.max_bad_morphology_share,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
