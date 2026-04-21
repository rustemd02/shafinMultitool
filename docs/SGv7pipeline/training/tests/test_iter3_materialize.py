from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from cir_contract.contracts import serialize_to_scenescript
from pattern_library import generate_pattern_record
from training import Iter3CorpusBuildRequest, build_iter3_corpus


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _read_jsonl(path: Path) -> list[dict[str, object]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _eval_case(cir_record: dict[str, object], *, eval_case_id: str, source_text: str) -> dict[str, object]:
    return {
        "contract_version": str(cir_record.get("contract_version") or "sg_v7_contract_v1"),
        "difficulty_bucket": str(cir_record.get("difficulty_bucket") or "hard"),
        "eval_case_id": eval_case_id,
        "eval_expectations": {
            "critical_eval_tags": list(cir_record.get("semantic_tags") or []),
        },
        "eval_set": "synthetic_heldout",
        "gold_target_json": serialize_to_scenescript(cir_record, original_description=source_text),
        "graph_family_key": cir_record.get("graph_family_key"),
        "marked_objects": [],
        "runtime_policy_inputs": {},
        "sample_id": cir_record.get("sample_id"),
        "source_text": source_text,
    }


def _case_result(
    eval_case_id: str,
    *,
    json_valid: bool,
    schema_valid: bool,
    ordinal: bool,
    target: bool,
    chronology: bool,
    action: bool,
    strict: bool,
    runtime: str,
    bucket_tags: list[str],
    exact: bool = True,
) -> dict[str, object]:
    return {
        "eval_case_id": eval_case_id,
        "json_valid": json_valid,
        "schema_valid": schema_valid,
        "case_strict_success": strict,
        "runtime_policy_decision": runtime,
        "bucket_tags": bucket_tags,
        "metric_flags": {
            "exact_marked_object_id_pass": exact,
            "ordinal_binding_pass": ordinal,
            "target_resolution_pass": target,
            "chronology_phase_pass": chronology,
            "action_recall_pass": action,
        },
    }


def _prediction(
    eval_case_id: str,
    model_only: dict[str, object] | None,
    *,
    end_to_end: dict[str, object] | None = None,
    raw_output_json: dict[str, object] | None = None,
) -> dict[str, object]:
    return {
        "eval_case_id": eval_case_id,
        "predicted_script": end_to_end if end_to_end is not None else model_only,
        "model_only_predicted_script": model_only,
        "end_to_end_predicted_script": end_to_end if end_to_end is not None else model_only,
        "raw_output_json": raw_output_json if raw_output_json is not None else model_only,
    }


def _pairwise(eval_case_id: str, *, winner: str) -> dict[str, object]:
    return {
        "eval_case_id": eval_case_id,
        "winner": winner,
        "candidate_runtime_policy_decision": "accept" if winner == "candidate" else "reject",
        "baseline_runtime_policy_decision": "accept" if winner == "baseline" else "reject",
    }


def _legacy_single_open(script: dict[str, object]) -> dict[str, object]:
    return {
        "actors": script["actors"],
        "objects": script["objects"],
        "beats": [
            {
                "id": "beat_1",
                "type": "action",
                "action": "open",
                "actorId": "actor_1",
                "target": "object_1",
                "resultingPose": "standing",
            }
        ],
        "spatialRelations": script["spatialRelations"],
        "originalDescription": script["originalDescription"],
    }


def _legacy_full_handoff(script: dict[str, object]) -> dict[str, object]:
    return {
        "actors": script["actors"],
        "objects": script["objects"],
        "beats": [
            {
                "id": "beat_1",
                "type": "talk",
                "actorId": "actor_1",
                "target": "actor_2",
                "dialogue": "Передай объект третьему.",
                "resultingPose": "standing",
            },
            {
                "id": "beat_2",
                "type": "pick_up",
                "actorId": "actor_2",
                "target": "object_1",
                "resultingPose": "standing",
            },
            {
                "id": "beat_3",
                "type": "give",
                "actorId": "actor_2",
                "target": "actor_3",
                "resultingPose": "standing",
            },
        ],
        "spatialRelations": script["spatialRelations"],
        "originalDescription": script["originalDescription"],
    }


def _ordinal_target_drift(script: dict[str, object]) -> dict[str, object]:
    broken = json.loads(json.dumps(script))
    beats = broken["beats"]
    if len(beats) == 1 and beats[0]["actions"][1]["type"] == "look_at":
        beats[0]["actions"][1]["target"] = "object_1"
    return broken


class TestIter3Materialize(unittest.TestCase):
    def test_iter3_builds_curated_delta_sft_and_preference_sets(self) -> None:
        open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=101, source_variant_key="base")
        ordinal_cir = generate_pattern_record("ordinal_first_second_third", graph_seed=102, source_variant_key="base")
        handoff_cir = generate_pattern_record(
            "dialogue_then_pick_up_object_then_give_to_third_actor",
            graph_seed=103,
            source_variant_key="base",
        )

        open_case = _eval_case(
            open_cir,
            eval_case_id="case-open",
            source_text="Первый сначала открывает ящик, а потом берёт планшет.",
        )
        ordinal_case = _eval_case(
            ordinal_cir,
            eval_case_id="case-ordinal",
            source_text="Первый подходит к стойке, второй смотрит на первого, третий остаётся у колонны.",
        )
        handoff_case = _eval_case(
            handoff_cir,
            eval_case_id="case-handoff",
            source_text="Дима просит передать письмо третьему, потом второй берёт письмо и отдаёт его Лизе.",
        )

        open_gold = open_case["gold_target_json"]
        ordinal_gold = ordinal_case["gold_target_json"]
        handoff_gold = handoff_case["gold_target_json"]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            eval_cases = tmp / "eval_cases.jsonl"
            cir = tmp / "cir.jsonl"
            v7_case_results = tmp / "v7_case_results.jsonl"
            iter1_case_results = tmp / "iter1_case_results.jsonl"
            iter2_case_results = tmp / "iter2_case_results.jsonl"
            v7_predictions = tmp / "v7_predictions.jsonl"
            iter1_predictions = tmp / "iter1_predictions.jsonl"
            iter2_predictions = tmp / "iter2_predictions.jsonl"
            iter2_vs_iter1 = tmp / "iter2_vs_iter1.jsonl"
            iter2_vs_v7 = tmp / "iter2_vs_v7.jsonl"
            out = tmp / "out"

            _write_jsonl(eval_cases, [open_case, ordinal_case, handoff_case])
            _write_jsonl(cir, [open_cir, ordinal_cir, handoff_cir])

            _write_jsonl(
                v7_case_results,
                [
                    _case_result(
                        "case-open",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=True,
                        target=False,
                        chronology=False,
                        action=False,
                        strict=False,
                        runtime="reject",
                        bucket_tags=[],
                    ),
                    _case_result(
                        "case-ordinal",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=True,
                        target=True,
                        chronology=True,
                        action=True,
                        strict=True,
                        runtime="accept",
                        bucket_tags=["ordinal_cases"],
                    ),
                    _case_result(
                        "case-handoff",
                        json_valid=False,
                        schema_valid=False,
                        ordinal=False,
                        target=False,
                        chronology=False,
                        action=False,
                        strict=False,
                        runtime="reject",
                        bucket_tags=["three_beat_cases"],
                    ),
                ],
            )
            _write_jsonl(
                iter1_case_results,
                [
                    _case_result(
                        "case-open",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=True,
                        target=False,
                        chronology=False,
                        action=False,
                        strict=False,
                        runtime="reject",
                        bucket_tags=[],
                    ),
                    _case_result(
                        "case-ordinal",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=True,
                        target=False,
                        chronology=False,
                        action=False,
                        strict=False,
                        runtime="reject",
                        bucket_tags=["ordinal_cases"],
                    ),
                    _case_result(
                        "case-handoff",
                        json_valid=False,
                        schema_valid=False,
                        ordinal=False,
                        target=False,
                        chronology=False,
                        action=False,
                        strict=False,
                        runtime="reject",
                        bucket_tags=["three_beat_cases"],
                    ),
                ],
            )
            _write_jsonl(
                iter2_case_results,
                [
                    _case_result(
                        "case-open",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=True,
                        target=True,
                        chronology=True,
                        action=True,
                        strict=True,
                        runtime="accept",
                        bucket_tags=[],
                    ),
                    _case_result(
                        "case-ordinal",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=False,
                        target=False,
                        chronology=False,
                        action=True,
                        strict=False,
                        runtime="reject",
                        bucket_tags=["ordinal_cases"],
                    ),
                    _case_result(
                        "case-handoff",
                        json_valid=True,
                        schema_valid=True,
                        ordinal=True,
                        target=True,
                        chronology=True,
                        action=True,
                        strict=True,
                        runtime="accept",
                        bucket_tags=["three_beat_cases"],
                    ),
                ],
            )

            _write_jsonl(
                v7_predictions,
                [
                    _prediction("case-open", _legacy_single_open(open_gold)),
                    _prediction("case-ordinal", ordinal_gold),
                    _prediction("case-handoff", None),
                ],
            )
            _write_jsonl(
                iter1_predictions,
                [
                    _prediction("case-open", _legacy_single_open(open_gold)),
                    _prediction("case-ordinal", _legacy_single_open(open_gold)),  # irrelevant bad fallback
                    _prediction("case-handoff", None),
                ],
            )
            _write_jsonl(
                iter2_predictions,
                [
                    _prediction("case-open", open_gold),
                    _prediction("case-ordinal", _ordinal_target_drift(ordinal_gold)),
                    _prediction("case-handoff", _legacy_full_handoff(handoff_gold)),
                ],
            )
            _write_jsonl(
                iter2_vs_iter1,
                [
                    _pairwise("case-open", winner="candidate"),
                    _pairwise("case-ordinal", winner="baseline"),
                    _pairwise("case-handoff", winner="candidate"),
                ],
            )
            _write_jsonl(
                iter2_vs_v7,
                [
                    _pairwise("case-open", winner="candidate"),
                    _pairwise("case-ordinal", winner="baseline"),
                    _pairwise("case-handoff", winner="candidate"),
                ],
            )

            manifest = build_iter3_corpus(
                Iter3CorpusBuildRequest(
                    eval_cases_jsonl=eval_cases,
                    cir_jsonl=cir,
                    v7_case_results_jsonl=v7_case_results,
                    iter1_case_results_jsonl=iter1_case_results,
                    iter2_case_results_jsonl=iter2_case_results,
                    v7_predictions_jsonl=v7_predictions,
                    iter1_predictions_jsonl=iter1_predictions,
                    iter2_predictions_jsonl=iter2_predictions,
                    iter2_vs_iter1_paired_jsonl=iter2_vs_iter1,
                    iter2_vs_v7_paired_jsonl=iter2_vs_v7,
                    output_dir=out,
                    seed=20260421,
                    delta_sft_val_ratio=0.34,
                    preference_val_ratio=0.34,
                    min_family_counts={"three_beat": 1, "ordinal": 1, "give_to_third_actor": 1, "open_then_pick_up": 1},
                )
            )

            self.assertEqual(manifest["counts"]["selected_cases"], 3)
            self.assertEqual(manifest["counts"]["delta_sft_total"], 3)
            self.assertEqual(manifest["counts"]["preference_total"], 3)
            self.assertEqual(manifest["chosen_source_counts"]["dataset_v7_orpo_iter2"], 1)
            self.assertEqual(manifest["chosen_source_counts"]["dataset_v7"], 1)
            self.assertEqual(manifest["chosen_source_counts"]["gold_target_json"], 1)

            delta_rows = _read_jsonl(out / "iter3_delta_sft.jsonl")
            pref_rows = _read_jsonl(out / "iter3_preference.jsonl")
            by_case_delta = {
                row["packaging_metadata"]["iter3_selection_reason"]: row
                for row in delta_rows
            }
            by_case_pref = {
                row["packaging_metadata"]["iter3_selection_reason"]: row
                for row in pref_rows
            }

            open_row = by_case_delta["iter2_semantic_gain_canonical"]
            self.assertEqual(open_row["packaging_metadata"]["iter3_selection_source"], "dataset_v7_orpo_iter2")

            ordinal_row = by_case_delta["dataset_v7_integrity_preserved"]
            self.assertEqual(ordinal_row["packaging_metadata"]["iter3_selection_source"], "dataset_v7")

            handoff_row = by_case_delta["iter2_semantic_gain_noncanonical_fallback_to_gold"]
            self.assertEqual(handoff_row["packaging_metadata"]["iter3_selection_source"], "gold_target_json")

            handoff_pref = by_case_pref["iter2_semantic_gain_noncanonical_fallback_to_gold"]
            self.assertEqual(handoff_pref["packaging_metadata"]["iter3_rejected_source"], "dataset_v7_orpo_iter2")

            review_samples = json.loads((out / "iter3_manual_review_samples.json").read_text(encoding="utf-8"))
            self.assertEqual(len(review_samples["open_then_pick_up_object"]), 1)
            self.assertEqual(len(review_samples["ordinal_first_second_third"]), 1)
            self.assertEqual(len(review_samples["dialogue_then_pick_up_object_then_give_to_third_actor"]), 1)

    def test_iter3_requires_dual_slice_prediction_fields(self) -> None:
        open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=201, source_variant_key="base")
        open_case = _eval_case(
            open_cir,
            eval_case_id="case-open",
            source_text="Первый открывает ящик и потом берёт планшет.",
        )
        open_gold = open_case["gold_target_json"]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            eval_cases = tmp / "eval_cases.jsonl"
            cir = tmp / "cir.jsonl"
            v7_case_results = tmp / "v7_case_results.jsonl"
            iter1_case_results = tmp / "iter1_case_results.jsonl"
            iter2_case_results = tmp / "iter2_case_results.jsonl"
            v7_predictions = tmp / "v7_predictions.jsonl"
            iter1_predictions = tmp / "iter1_predictions.jsonl"
            iter2_predictions = tmp / "iter2_predictions.jsonl"
            iter2_vs_iter1 = tmp / "iter2_vs_iter1.jsonl"
            iter2_vs_v7 = tmp / "iter2_vs_v7.jsonl"

            _write_jsonl(eval_cases, [open_case])
            _write_jsonl(cir, [open_cir])
            rows = [
                _case_result(
                    "case-open",
                    json_valid=True,
                    schema_valid=True,
                    ordinal=True,
                    target=True,
                    chronology=True,
                    action=True,
                    strict=True,
                    runtime="accept",
                    bucket_tags=[],
                )
            ]
            _write_jsonl(v7_case_results, rows)
            _write_jsonl(iter1_case_results, rows)
            _write_jsonl(iter2_case_results, rows)
            _write_jsonl(v7_predictions, [{"eval_case_id": "case-open", "predicted_script": open_gold}])
            _write_jsonl(iter1_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter2_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter2_vs_iter1, [_pairwise("case-open", winner="candidate")])
            _write_jsonl(iter2_vs_v7, [_pairwise("case-open", winner="candidate")])

            with self.assertRaisesRegex(ValueError, "dual-slice fields"):
                build_iter3_corpus(
                    Iter3CorpusBuildRequest(
                        eval_cases_jsonl=eval_cases,
                        cir_jsonl=cir,
                        v7_case_results_jsonl=v7_case_results,
                        iter1_case_results_jsonl=iter1_case_results,
                        iter2_case_results_jsonl=iter2_case_results,
                        v7_predictions_jsonl=v7_predictions,
                        iter1_predictions_jsonl=iter1_predictions,
                        iter2_predictions_jsonl=iter2_predictions,
                        iter2_vs_iter1_paired_jsonl=iter2_vs_iter1,
                        iter2_vs_v7_paired_jsonl=iter2_vs_v7,
                        output_dir=tmp / "out",
                        seed=20260421,
                    )
                )

    def test_pairwise_can_block_iter2_selection(self) -> None:
        open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=301, source_variant_key="base")
        open_case = _eval_case(
            open_cir,
            eval_case_id="case-open",
            source_text="Первый открывает крышку и потом берёт папку.",
        )
        open_gold = open_case["gold_target_json"]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            eval_cases = tmp / "eval_cases.jsonl"
            cir = tmp / "cir.jsonl"
            v7_case_results = tmp / "v7_case_results.jsonl"
            iter1_case_results = tmp / "iter1_case_results.jsonl"
            iter2_case_results = tmp / "iter2_case_results.jsonl"
            v7_predictions = tmp / "v7_predictions.jsonl"
            iter1_predictions = tmp / "iter1_predictions.jsonl"
            iter2_predictions = tmp / "iter2_predictions.jsonl"
            iter2_vs_iter1 = tmp / "iter2_vs_iter1.jsonl"
            iter2_vs_v7 = tmp / "iter2_vs_v7.jsonl"
            out = tmp / "out"

            _write_jsonl(eval_cases, [open_case])
            _write_jsonl(cir, [open_cir])
            _write_jsonl(
                v7_case_results,
                [_case_result("case-open", json_valid=True, schema_valid=True, ordinal=True, target=True, chronology=True, action=True, strict=False, runtime="reject", bucket_tags=[])],
            )
            _write_jsonl(
                iter1_case_results,
                [_case_result("case-open", json_valid=True, schema_valid=True, ordinal=True, target=False, chronology=False, action=False, strict=False, runtime="reject", bucket_tags=[])],
            )
            _write_jsonl(
                iter2_case_results,
                [_case_result("case-open", json_valid=True, schema_valid=True, ordinal=True, target=True, chronology=True, action=True, strict=True, runtime="accept", bucket_tags=[])],
            )
            _write_jsonl(v7_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter1_predictions, [_prediction("case-open", _legacy_single_open(open_gold))])
            _write_jsonl(iter2_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter2_vs_iter1, [_pairwise("case-open", winner="candidate")])
            _write_jsonl(iter2_vs_v7, [_pairwise("case-open", winner="baseline")])

            manifest = build_iter3_corpus(
                Iter3CorpusBuildRequest(
                    eval_cases_jsonl=eval_cases,
                    cir_jsonl=cir,
                    v7_case_results_jsonl=v7_case_results,
                    iter1_case_results_jsonl=iter1_case_results,
                    iter2_case_results_jsonl=iter2_case_results,
                    v7_predictions_jsonl=v7_predictions,
                    iter1_predictions_jsonl=iter1_predictions,
                    iter2_predictions_jsonl=iter2_predictions,
                    iter2_vs_iter1_paired_jsonl=iter2_vs_iter1,
                        iter2_vs_v7_paired_jsonl=iter2_vs_v7,
                        output_dir=out,
                        seed=20260421,
                        min_family_counts={},
                    )
                )

            self.assertEqual(manifest["chosen_source_counts"]["dataset_v7"], 1)
            delta_rows = _read_jsonl(out / "iter3_delta_sft.jsonl")
            self.assertEqual(delta_rows[0]["packaging_metadata"]["iter3_selection_source"], "dataset_v7")

    def test_pairwise_runtime_only_gain_is_not_enough_for_iter2(self) -> None:
        open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=351, source_variant_key="base")
        open_case = _eval_case(
            open_cir,
            eval_case_id="case-open",
            source_text="Первый открывает крышку и потом берёт папку.",
        )
        open_gold = open_case["gold_target_json"]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            eval_cases = tmp / "eval_cases.jsonl"
            cir = tmp / "cir.jsonl"
            v7_case_results = tmp / "v7_case_results.jsonl"
            iter1_case_results = tmp / "iter1_case_results.jsonl"
            iter2_case_results = tmp / "iter2_case_results.jsonl"
            v7_predictions = tmp / "v7_predictions.jsonl"
            iter1_predictions = tmp / "iter1_predictions.jsonl"
            iter2_predictions = tmp / "iter2_predictions.jsonl"
            iter2_vs_iter1 = tmp / "iter2_vs_iter1.jsonl"
            iter2_vs_v7 = tmp / "iter2_vs_v7.jsonl"
            out = tmp / "out"

            _write_jsonl(eval_cases, [open_case])
            _write_jsonl(cir, [open_cir])
            stable_case = _case_result(
                "case-open",
                json_valid=True,
                schema_valid=True,
                exact=True,
                ordinal=True,
                target=True,
                chronology=True,
                action=True,
                strict=True,
                runtime="reject",
                bucket_tags=[],
            )
            runtime_only_gain = _case_result(
                "case-open",
                json_valid=True,
                schema_valid=True,
                exact=True,
                ordinal=True,
                target=True,
                chronology=True,
                action=True,
                strict=True,
                runtime="accept",
                bucket_tags=[],
            )
            _write_jsonl(v7_case_results, [stable_case])
            _write_jsonl(
                iter1_case_results,
                [
                    _case_result(
                        "case-open",
                        json_valid=True,
                        schema_valid=True,
                        exact=True,
                        ordinal=True,
                        target=False,
                        chronology=False,
                        action=False,
                        strict=False,
                        runtime="reject",
                        bucket_tags=[],
                    )
                ],
            )
            _write_jsonl(iter2_case_results, [runtime_only_gain])
            _write_jsonl(v7_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter1_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter2_predictions, [_prediction("case-open", open_gold)])
            _write_jsonl(iter2_vs_iter1, [_pairwise("case-open", winner="candidate")])
            _write_jsonl(iter2_vs_v7, [_pairwise("case-open", winner="candidate")])

            manifest = build_iter3_corpus(
                Iter3CorpusBuildRequest(
                    eval_cases_jsonl=eval_cases,
                    cir_jsonl=cir,
                    v7_case_results_jsonl=v7_case_results,
                    iter1_case_results_jsonl=iter1_case_results,
                    iter2_case_results_jsonl=iter2_case_results,
                    v7_predictions_jsonl=v7_predictions,
                    iter1_predictions_jsonl=iter1_predictions,
                    iter2_predictions_jsonl=iter2_predictions,
                    iter2_vs_iter1_paired_jsonl=iter2_vs_iter1,
                    iter2_vs_v7_paired_jsonl=iter2_vs_v7,
                    output_dir=out,
                    seed=20260421,
                    min_family_counts={},
                )
            )

            self.assertEqual(manifest["chosen_source_counts"].get("dataset_v7_orpo_iter2", 0), 0)
            self.assertEqual(manifest["chosen_source_counts"]["dataset_v7"], 1)
            delta_rows = _read_jsonl(out / "iter3_delta_sft.jsonl")
            self.assertEqual(delta_rows[0]["packaging_metadata"]["iter3_selection_source"], "dataset_v7")

    def test_iter3_fails_when_gold_dominates(self) -> None:
        open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=401, source_variant_key="base")
        open_case = _eval_case(
            open_cir,
            eval_case_id="case-open",
            source_text="Первый открывает шкафчик, а потом берёт планшет.",
        )
        open_gold = open_case["gold_target_json"]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            eval_cases = tmp / "eval_cases.jsonl"
            cir = tmp / "cir.jsonl"
            v7_case_results = tmp / "v7_case_results.jsonl"
            iter1_case_results = tmp / "iter1_case_results.jsonl"
            iter2_case_results = tmp / "iter2_case_results.jsonl"
            v7_predictions = tmp / "v7_predictions.jsonl"
            iter1_predictions = tmp / "iter1_predictions.jsonl"
            iter2_predictions = tmp / "iter2_predictions.jsonl"
            iter2_vs_iter1 = tmp / "iter2_vs_iter1.jsonl"
            iter2_vs_v7 = tmp / "iter2_vs_v7.jsonl"
            out = tmp / "out"

            _write_jsonl(eval_cases, [open_case])
            _write_jsonl(cir, [open_cir])
            bad_rows = [
                _case_result("case-open", json_valid=False, schema_valid=False, ordinal=False, target=False, chronology=False, action=False, strict=False, runtime="reject", bucket_tags=[])
            ]
            _write_jsonl(v7_case_results, bad_rows)
            _write_jsonl(iter1_case_results, bad_rows)
            _write_jsonl(iter2_case_results, bad_rows)
            _write_jsonl(v7_predictions, [_prediction("case-open", _legacy_single_open(open_gold))])
            _write_jsonl(iter1_predictions, [_prediction("case-open", _legacy_single_open(open_gold))])
            _write_jsonl(iter2_predictions, [_prediction("case-open", _legacy_single_open(open_gold))])
            _write_jsonl(iter2_vs_iter1, [_pairwise("case-open", winner="tie")])
            _write_jsonl(iter2_vs_v7, [_pairwise("case-open", winner="tie")])

            with self.assertRaisesRegex(ValueError, "gold_chosen_share_overall"):
                build_iter3_corpus(
                    Iter3CorpusBuildRequest(
                        eval_cases_jsonl=eval_cases,
                        cir_jsonl=cir,
                        v7_case_results_jsonl=v7_case_results,
                        iter1_case_results_jsonl=iter1_case_results,
                        iter2_case_results_jsonl=iter2_case_results,
                        v7_predictions_jsonl=v7_predictions,
                        iter1_predictions_jsonl=iter1_predictions,
                        iter2_predictions_jsonl=iter2_predictions,
                        iter2_vs_iter1_paired_jsonl=iter2_vs_iter1,
                        iter2_vs_v7_paired_jsonl=iter2_vs_v7,
                        output_dir=out,
                        seed=20260421,
                        min_family_counts={"open_then_pick_up": 1},
                    )
                )
            manifest = json.loads((out / "iter3_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["gate_status"], "fail")

    def test_iter3_fails_when_targeted_family_lacks_model_floor(self) -> None:
        cases = []
        cir_rows = []
        v7_case_rows = []
        iter1_case_rows = []
        iter2_case_rows = []
        v7_pred_rows = []
        iter1_pred_rows = []
        iter2_pred_rows = []
        pair_iter1_rows = []
        pair_v7_rows = []

        for index in range(4):
            open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=500 + index, source_variant_key="base")
            case_id = f"case-open-{index}"
            eval_case = _eval_case(
                open_cir,
                eval_case_id=case_id,
                source_text=f"Открытие {index}",
            )
            gold = eval_case["gold_target_json"]
            cases.append(eval_case)
            cir_rows.append(open_cir)
            if index == 0:
                v7_case_rows.append(_case_result(case_id, json_valid=True, schema_valid=True, ordinal=True, target=True, chronology=True, action=True, strict=True, runtime="accept", bucket_tags=[]))
                iter1_case_rows.append(_case_result(case_id, json_valid=False, schema_valid=False, ordinal=False, target=False, chronology=False, action=False, strict=False, runtime="reject", bucket_tags=[]))
                iter2_case_rows.append(_case_result(case_id, json_valid=True, schema_valid=True, ordinal=True, target=True, chronology=True, action=True, strict=True, runtime="accept", bucket_tags=[]))
                v7_pred_rows.append(_prediction(case_id, gold))
                iter1_pred_rows.append(_prediction(case_id, _legacy_single_open(gold)))
                iter2_pred_rows.append(_prediction(case_id, gold))
                pair_iter1_rows.append(_pairwise(case_id, winner="candidate"))
                pair_v7_rows.append(_pairwise(case_id, winner="baseline"))
            else:
                bad = _case_result(case_id, json_valid=False, schema_valid=False, ordinal=False, target=False, chronology=False, action=False, strict=False, runtime="reject", bucket_tags=[])
                v7_case_rows.append(bad)
                iter1_case_rows.append(bad)
                iter2_case_rows.append(bad)
                v7_pred_rows.append(_prediction(case_id, _legacy_single_open(gold)))
                iter1_pred_rows.append(_prediction(case_id, _legacy_single_open(gold)))
                iter2_pred_rows.append(_prediction(case_id, _legacy_single_open(gold)))
                pair_iter1_rows.append(_pairwise(case_id, winner="tie"))
                pair_v7_rows.append(_pairwise(case_id, winner="tie"))

        for index in range(4):
            ordinal_cir = generate_pattern_record("ordinal_first_second_third", graph_seed=600 + index, source_variant_key="base")
            case_id = f"case-ordinal-{index}"
            eval_case = _eval_case(
                ordinal_cir,
                eval_case_id=case_id,
                source_text=f"Ординалы {index}",
            )
            gold = eval_case["gold_target_json"]
            cases.append(eval_case)
            cir_rows.append(ordinal_cir)
            good = _case_result(case_id, json_valid=True, schema_valid=True, ordinal=True, target=True, chronology=True, action=True, strict=True, runtime="accept", bucket_tags=["ordinal_cases"])
            weak = _case_result(case_id, json_valid=True, schema_valid=True, ordinal=False, target=False, chronology=False, action=False, strict=False, runtime="reject", bucket_tags=["ordinal_cases"])
            v7_case_rows.append(good)
            iter1_case_rows.append(weak)
            iter2_case_rows.append(weak)
            v7_pred_rows.append(_prediction(case_id, gold))
            iter1_pred_rows.append(_prediction(case_id, _ordinal_target_drift(gold)))
            iter2_pred_rows.append(_prediction(case_id, _ordinal_target_drift(gold)))
            pair_iter1_rows.append(_pairwise(case_id, winner="baseline"))
            pair_v7_rows.append(_pairwise(case_id, winner="baseline"))

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            _write_jsonl(tmp / "eval_cases.jsonl", cases)
            _write_jsonl(tmp / "cir.jsonl", cir_rows)
            _write_jsonl(tmp / "v7_case_results.jsonl", v7_case_rows)
            _write_jsonl(tmp / "iter1_case_results.jsonl", iter1_case_rows)
            _write_jsonl(tmp / "iter2_case_results.jsonl", iter2_case_rows)
            _write_jsonl(tmp / "v7_predictions.jsonl", v7_pred_rows)
            _write_jsonl(tmp / "iter1_predictions.jsonl", iter1_pred_rows)
            _write_jsonl(tmp / "iter2_predictions.jsonl", iter2_pred_rows)
            _write_jsonl(tmp / "iter2_vs_iter1.jsonl", pair_iter1_rows)
            _write_jsonl(tmp / "iter2_vs_v7.jsonl", pair_v7_rows)

            with self.assertRaisesRegex(ValueError, "model_chosen_count_by_family.open_then_pick_up"):
                build_iter3_corpus(
                    Iter3CorpusBuildRequest(
                        eval_cases_jsonl=tmp / "eval_cases.jsonl",
                        cir_jsonl=tmp / "cir.jsonl",
                        v7_case_results_jsonl=tmp / "v7_case_results.jsonl",
                        iter1_case_results_jsonl=tmp / "iter1_case_results.jsonl",
                        iter2_case_results_jsonl=tmp / "iter2_case_results.jsonl",
                        v7_predictions_jsonl=tmp / "v7_predictions.jsonl",
                        iter1_predictions_jsonl=tmp / "iter1_predictions.jsonl",
                        iter2_predictions_jsonl=tmp / "iter2_predictions.jsonl",
                        iter2_vs_iter1_paired_jsonl=tmp / "iter2_vs_iter1.jsonl",
                        iter2_vs_v7_paired_jsonl=tmp / "iter2_vs_v7.jsonl",
                        output_dir=tmp / "out",
                        seed=20260421,
                        min_family_counts={"open_then_pick_up": 4, "ordinal": 4},
                    )
                )

    def test_iter3_applies_delta_sft_family_cap(self) -> None:
        cases = []
        cir_rows = []
        v7_case_rows = []
        iter1_case_rows = []
        iter2_case_rows = []
        v7_pred_rows = []
        iter1_pred_rows = []
        iter2_pred_rows = []
        pair_iter1_rows = []
        pair_v7_rows = []

        for index in range(4):
            ordinal_cir = generate_pattern_record("ordinal_first_second_third", graph_seed=700 + index, source_variant_key="base")
            case_id = f"case-ordinal-{index}"
            eval_case = _eval_case(
                ordinal_cir,
                eval_case_id=case_id,
                source_text=f"Ординалы {index}",
            )
            gold = eval_case["gold_target_json"]
            cases.append(eval_case)
            cir_rows.append(ordinal_cir)
            good = _case_result(
                case_id,
                json_valid=True,
                schema_valid=True,
                exact=True,
                ordinal=True,
                target=True,
                chronology=True,
                action=True,
                strict=True,
                runtime="accept",
                bucket_tags=["ordinal_cases"],
            )
            weak = _case_result(
                case_id,
                json_valid=True,
                schema_valid=True,
                exact=True,
                ordinal=False,
                target=False,
                chronology=False,
                action=False,
                strict=False,
                runtime="reject",
                bucket_tags=["ordinal_cases"],
            )
            v7_case_rows.append(good)
            iter1_case_rows.append(weak)
            iter2_case_rows.append(weak)
            v7_pred_rows.append(_prediction(case_id, gold))
            iter1_pred_rows.append(_prediction(case_id, _ordinal_target_drift(gold)))
            iter2_pred_rows.append(_prediction(case_id, _ordinal_target_drift(gold)))
            pair_iter1_rows.append(_pairwise(case_id, winner="baseline"))
            pair_v7_rows.append(_pairwise(case_id, winner="baseline"))

        for index in range(2):
            open_cir = generate_pattern_record("open_then_pick_up_object", graph_seed=800 + index, source_variant_key="base")
            case_id = f"case-open-{index}"
            eval_case = _eval_case(
                open_cir,
                eval_case_id=case_id,
                source_text=f"Открытие {index}",
            )
            gold = eval_case["gold_target_json"]
            cases.append(eval_case)
            cir_rows.append(open_cir)
            good = _case_result(
                case_id,
                json_valid=True,
                schema_valid=True,
                exact=True,
                ordinal=True,
                target=True,
                chronology=True,
                action=True,
                strict=True,
                runtime="accept",
                bucket_tags=[],
            )
            weak = _case_result(
                case_id,
                json_valid=False,
                schema_valid=False,
                exact=False,
                ordinal=False,
                target=False,
                chronology=False,
                action=False,
                strict=False,
                runtime="reject",
                bucket_tags=[],
            )
            v7_case_rows.append(good)
            iter1_case_rows.append(weak)
            iter2_case_rows.append(weak)
            v7_pred_rows.append(_prediction(case_id, gold))
            iter1_pred_rows.append(_prediction(case_id, _legacy_single_open(gold)))
            iter2_pred_rows.append(_prediction(case_id, _legacy_single_open(gold)))
            pair_iter1_rows.append(_pairwise(case_id, winner="baseline"))
            pair_v7_rows.append(_pairwise(case_id, winner="baseline"))

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            _write_jsonl(tmp / "eval_cases.jsonl", cases)
            _write_jsonl(tmp / "cir.jsonl", cir_rows)
            _write_jsonl(tmp / "v7_case_results.jsonl", v7_case_rows)
            _write_jsonl(tmp / "iter1_case_results.jsonl", iter1_case_rows)
            _write_jsonl(tmp / "iter2_case_results.jsonl", iter2_case_rows)
            _write_jsonl(tmp / "v7_predictions.jsonl", v7_pred_rows)
            _write_jsonl(tmp / "iter1_predictions.jsonl", iter1_pred_rows)
            _write_jsonl(tmp / "iter2_predictions.jsonl", iter2_pred_rows)
            _write_jsonl(tmp / "iter2_vs_iter1.jsonl", pair_iter1_rows)
            _write_jsonl(tmp / "iter2_vs_v7.jsonl", pair_v7_rows)

            manifest = build_iter3_corpus(
                Iter3CorpusBuildRequest(
                    eval_cases_jsonl=tmp / "eval_cases.jsonl",
                    cir_jsonl=tmp / "cir.jsonl",
                    v7_case_results_jsonl=tmp / "v7_case_results.jsonl",
                    iter1_case_results_jsonl=tmp / "iter1_case_results.jsonl",
                    iter2_case_results_jsonl=tmp / "iter2_case_results.jsonl",
                    v7_predictions_jsonl=tmp / "v7_predictions.jsonl",
                    iter1_predictions_jsonl=tmp / "iter1_predictions.jsonl",
                    iter2_predictions_jsonl=tmp / "iter2_predictions.jsonl",
                    iter2_vs_iter1_paired_jsonl=tmp / "iter2_vs_iter1.jsonl",
                    iter2_vs_v7_paired_jsonl=tmp / "iter2_vs_v7.jsonl",
                    output_dir=tmp / "out",
                    seed=20260421,
                    min_family_counts={"ordinal": 2, "open_then_pick_up": 2},
                    delta_sft_max_family_share=0.50,
                )
            )

            self.assertEqual(manifest["counts"]["delta_sft_total_before_family_cap"], 6)
            self.assertEqual(manifest["counts"]["delta_sft_total"], 4)
            self.assertEqual(manifest["delta_family_counts"]["ordinal"], 2)
            self.assertEqual(manifest["delta_family_counts"]["open_then_pick_up"], 2)
            self.assertEqual(manifest["delta_dropped_by_family_cap"]["ordinal"], 2)
