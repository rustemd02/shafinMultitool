from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .io import read_jsonl


class InferenceError(ValueError):
    """Raised when prediction sources are malformed."""


@dataclass(frozen=True)
class InferenceRequest:
    cases: list[dict[str, Any]]
    checkpoint_id: str
    seed: int
    model_path: Path | None = None
    predictions_jsonl: Path | None = None


def _extract_predicted_script(row: dict[str, Any]) -> dict[str, Any] | None:
    if isinstance(row.get("predicted_script"), dict):
        return row["predicted_script"]
    if isinstance(row.get("raw_output_json"), dict):
        return row["raw_output_json"]
    return None


def _load_predictions(path: Path) -> dict[str, dict[str, Any]]:
    rows = read_jsonl(path)
    predictions: dict[str, dict[str, Any]] = {}
    for row in rows:
        case_id = str(row.get("eval_case_id", "")).strip()
        if not case_id:
            raise InferenceError(f"prediction row missing eval_case_id in {path}")
        if case_id in predictions:
            raise InferenceError(f"duplicate eval_case_id={case_id!r} in predictions")
        predictions[case_id] = row
    return predictions


def run_inference(request: InferenceRequest) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any] | None]]:
    raw_outputs: list[dict[str, Any]] = []
    predicted_by_case: dict[str, dict[str, Any] | None] = {}

    if request.predictions_jsonl is not None:
        external = _load_predictions(request.predictions_jsonl)
        for case in request.cases:
            case_id = str(case["eval_case_id"])
            row = external.get(case_id)
            if row is None:
                raise InferenceError(f"missing prediction for eval_case_id={case_id!r}")
            predicted_script = _extract_predicted_script(row)
            predicted_by_case[case_id] = predicted_script
            raw_outputs.append(
                {
                    "eval_case_id": case_id,
                    "checkpoint_id": request.checkpoint_id,
                    "inference_provider": "predictions_jsonl",
                    "raw_output_text": row.get("raw_output_text"),
                    "raw_output_json": row.get("raw_output_json", predicted_script),
                    "predicted_script": predicted_script,
                }
            )
        return raw_outputs, predicted_by_case

    # Fallback deterministic inference for harness validation/smoke runs.
    for case in request.cases:
        case_id = str(case["eval_case_id"])
        predicted_script = case.get("gold_target_json") if isinstance(case.get("gold_target_json"), dict) else None
        predicted_by_case[case_id] = predicted_script
        raw_outputs.append(
            {
                "eval_case_id": case_id,
                "checkpoint_id": request.checkpoint_id,
                "inference_provider": "oracle_from_gold_target",
                "model_path": str(request.model_path) if request.model_path is not None else None,
                "raw_output_text": None,
                "raw_output_json": predicted_script,
                "predicted_script": predicted_script,
            }
        )
    return raw_outputs, predicted_by_case
