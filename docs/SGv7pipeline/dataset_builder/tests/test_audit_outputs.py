from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from audit_sgv7_outputs import AuditError, run_audit


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _scaffold_output(root: Path, *, split_manifest_override: dict | None = None) -> None:
    split_manifest = {
        "counts_by_split": {"train": 2, "val": 0, "test": 0},
        "counts_by_pattern_name": {"dialogue_only": 1, "toward_each_other": 1},
        "counts_by_critical_eval_tags": {
            "same_type_markers": 1,
            "three_beat_cases": 1,
            "ordinal_cases": 1,
            "exact_marker_identity_cases": 1,
            "marked_object_morphology": 1,
        },
        "technical_literal_rows": 0,
        "meta_language_rows": 0,
        "surface_noise_rows": 0,
        "bad_morphology_rows": 0,
        "promoted_review_rows": 0,
        "lexeme_watch_rows": {"comp_family_rows": 0, "notebook_family_rows": 0, "smoke_family_rows": 0},
    }
    if split_manifest_override:
        split_manifest.update(split_manifest_override)
    preference_manifest = {
        "counts_by_split": {"train": 0, "val": 0, "test": 0},
        "counts_by_preference_origin": {},
    }
    leakage_report = {"status": "pass"}
    source_manifest = {"total_input_count": 10, "rejected_count": 2}
    graph_manifest = {"pattern_counts": {"dialogue_only": 1, "toward_each_other": 1}}

    _write_json(root / "final" / "dataset" / "split_manifest.json", split_manifest)
    _write_json(root / "final" / "dataset" / "preference_manifest.json", preference_manifest)
    _write_json(root / "final" / "dataset" / "leakage_report.json", leakage_report)
    _write_json(root / "core" / "source_validation_manifest.json", source_manifest)
    _write_json(root / "hard" / "source_validation_manifest.json", source_manifest)
    _write_json(root / "core" / "graphs.manifest.json", graph_manifest)
    _write_json(root / "hard" / "graphs.manifest.json", graph_manifest)

    _write_jsonl(root / "final" / "dataset" / "sft_train.jsonl", [{"source_text": "ok"}, {"source_text": "ok"}])
    _write_jsonl(root / "final" / "dataset" / "sft_val.jsonl", [])
    _write_jsonl(root / "final" / "dataset" / "sft_test.jsonl", [])
    _write_jsonl(root / "final" / "dataset" / "preference_train.jsonl", [])
    _write_jsonl(root / "final" / "dataset" / "preference_val.jsonl", [])
    _write_jsonl(root / "final" / "dataset" / "preference_test.jsonl", [])
    _write_jsonl(root / "final" / "accepted_merged.jsonl", [{"sample_id": "s1"}])
    _write_jsonl(root / "final" / "cir_merged.jsonl", [{"sample_id": "s1"}])


class TestAuditOutputs(unittest.TestCase):
    def test_audit_fails_on_low_three_beat_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            _scaffold_output(root, split_manifest_override={"counts_by_critical_eval_tags": {
                "same_type_markers": 1,
                "three_beat_cases": 0,
                "ordinal_cases": 1,
                "exact_marker_identity_cases": 1,
                "marked_object_morphology": 1,
            }})
            with self.assertRaises(AuditError):
                run_audit(
                    output_dir=root,
                    min_sft_total=1,
                    min_same_type_markers=1,
                    min_three_beat_cases=1,
                    min_ordinal_cases=0,
                    min_exact_marker_identity_cases=0,
                    min_marked_object_morphology=0,
                    require_preference=False,
                    require_runtime_preference_origin=False,
                    max_source_reject_rate=None,
                    max_graph_pattern_share=None,
                    max_final_sft_pattern_share=None,
                    max_promoted_review_share=None,
                    max_technical_literal_share=None,
                    max_meta_language_share=None,
                    max_surface_noise_share=None,
                    max_bad_morphology_share=None,
                )

    def test_audit_fails_on_final_sft_noise(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            _scaffold_output(root, split_manifest_override={"technical_literal_rows": 1, "surface_noise_rows": 1})
            with self.assertRaises(AuditError):
                run_audit(
                    output_dir=root,
                    min_sft_total=1,
                    min_same_type_markers=1,
                    min_three_beat_cases=0,
                    min_ordinal_cases=0,
                    min_exact_marker_identity_cases=0,
                    min_marked_object_morphology=0,
                    require_preference=False,
                    require_runtime_preference_origin=False,
                    max_source_reject_rate=None,
                    max_graph_pattern_share=None,
                    max_final_sft_pattern_share=None,
                    max_promoted_review_share=None,
                    max_technical_literal_share=0.0,
                    max_meta_language_share=None,
                    max_surface_noise_share=0.0,
                    max_bad_morphology_share=None,
                )

    def test_audit_fails_on_final_pattern_skew(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            _scaffold_output(root, split_manifest_override={"counts_by_pattern_name": {"dialogue_only": 2}})
            with self.assertRaises(AuditError):
                run_audit(
                    output_dir=root,
                    min_sft_total=1,
                    min_same_type_markers=1,
                    min_three_beat_cases=0,
                    min_ordinal_cases=0,
                    min_exact_marker_identity_cases=0,
                    min_marked_object_morphology=0,
                    require_preference=False,
                    require_runtime_preference_origin=False,
                    max_source_reject_rate=None,
                    max_graph_pattern_share=None,
                    max_final_sft_pattern_share=0.60,
                    max_promoted_review_share=None,
                    max_technical_literal_share=None,
                    max_meta_language_share=None,
                    max_surface_noise_share=None,
                    max_bad_morphology_share=None,
                )
