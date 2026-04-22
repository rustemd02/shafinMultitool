from __future__ import annotations

from statistics import mean
from typing import Any

try:
    from .datasets import extract_document_state
    from ..v8.compiler import compile_scene_plan_ir_with_notes
except ImportError:  # pragma: no cover
    from datasets import extract_document_state
    from docs.SGv7pipeline.v8.compiler import compile_scene_plan_ir_with_notes


def stitch_eval_artifacts_builder(
    *,
    eval_case_rows: list[dict[str, Any]],
    prediction_rows: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    predictions_by_id = {str(row.get("eval_case_id") or row.get("document_id") or ""): row for row in prediction_rows}
    chunk_rows: list[dict[str, Any]] = []
    scene_rows: list[dict[str, Any]] = []
    bundle_rows: list[dict[str, Any]] = []
    compiled_rows: list[dict[str, Any]] = []

    for eval_case in eval_case_rows:
        eval_case_id = str(eval_case.get("eval_case_id") or eval_case.get("document_id") or "")
        if not eval_case_id:
            continue
        prediction_row = predictions_by_id.get(eval_case_id, {})
        document = extract_document_state(prediction_row)
        if not document:
            continue

        bundle_plan = document.get("bundlePlan") or {}
        scenes = bundle_plan.get("scenes", []) if isinstance(bundle_plan, dict) else []
        active_index = int(bundle_plan.get("activeSceneIndex") or document.get("activeSceneIndex") or 0)
        active_scene = scenes[active_index] if 0 <= active_index < len(scenes) else (scenes[-1] if scenes else {})
        active_compiled = None
        active_compile_notes: list[str] = []

        for scene in scenes:
            scene_plan = scene.get("plan")
            if not isinstance(scene_plan, dict):
                continue
            compile_ok = False
            compile_notes: list[str] = []
            compiled_script = None
            try:
                compiled_script, compile_notes = compile_scene_plan_ir_with_notes(
                    scene_plan,
                    original_description=str(scene.get("sourceText") or ""),
                )
                compile_ok = True
            except ValueError as exc:
                compile_notes = [str(exc)]
            scene_rows.append(
                {
                    "eval_case_id": eval_case_id,
                    "scene_id": str(scene.get("sceneID") or ""),
                    "scene_index": int(scene.get("sceneIndex") or 0),
                    "chunk_count": len(scene.get("chunks", [])),
                    "stitch_success": compile_ok and bool(scene_plan.get("beats")),
                    "compile_ok": compile_ok,
                    "compile_notes": compile_notes,
                    "continuity_reason_codes": scene.get("diagnostics") or [],
                }
            )
            if active_scene is scene:
                active_compiled = compiled_script
                active_compile_notes = compile_notes

            for chunk in scene.get("chunks", []):
                if not isinstance(chunk, dict):
                    continue
                anchors = chunk.get("anchors") or {}
                beat_patch = chunk.get("beatPatch") or []
                chunk_rows.append(
                    {
                        "eval_case_id": eval_case_id,
                        "scene_id": str(scene.get("sceneID") or ""),
                        "chunk_id": str(chunk.get("chunkID") or ""),
                        "chunk_index": int(chunk.get("chunkIndex") or 0),
                        "chunk_parse_ok": isinstance(chunk.get("registryPatch"), dict),
                        "chunk_schema_valid": isinstance(anchors, dict) and isinstance(beat_patch, list),
                        "speaker_attribution_support": 1 if (anchors.get("speakerCues") or []) else 0,
                        "phase_signal_support": 1 if (anchors.get("chronologyCues") or anchors.get("sourceBundle", {}).get("phase_cues")) else 0,
                        "cross_chunk_pronoun_support": 1 if (anchors.get("pronounMentions") or []) else 0,
                        "reason_codes": chunk.get("reasonCodes") or [],
                    }
                )

        chunk_parse_rate = _ratio(row["chunk_parse_ok"] for row in chunk_rows if row["eval_case_id"] == eval_case_id)
        chunk_schema_valid_rate = _ratio(row["chunk_schema_valid"] for row in chunk_rows if row["eval_case_id"] == eval_case_id)
        stitch_success_rate = _ratio(row["stitch_success"] for row in scene_rows if row["eval_case_id"] == eval_case_id)
        scene_count_accuracy = 1.0 if len(scenes) == len(document.get("sceneCandidates", [])) else 0.0
        bundle_rows.append(
            {
                "eval_case_id": eval_case_id,
                "scene_count": len(scenes),
                "bundle_json_valid": isinstance(bundle_plan, dict) and isinstance(scenes, list),
                "scene_count_accuracy": scene_count_accuracy,
                "chunk_parse_rate": chunk_parse_rate,
                "chunk_schema_valid_rate": chunk_schema_valid_rate,
                "stitch_success_rate": stitch_success_rate,
            }
        )

        compiled_rows.append(
            {
                "eval_case_id": eval_case_id,
                "slice_reason_codes": list(dict.fromkeys((active_scene.get("diagnostics") or []) + active_compile_notes)) if isinstance(active_scene, dict) else active_compile_notes,
                "selected_slice": "bundle_active_scene",
                "bundle_plan": bundle_plan,
                "bundle_script": document.get("bundleScript"),
                "active_scene_plan": active_scene.get("plan") if isinstance(active_scene, dict) else None,
                "model_only_predicted_script": active_compiled if isinstance(active_compiled, dict) else None,
                "end_to_end_predicted_script": active_compiled if isinstance(active_compiled, dict) else None,
                "raw_output_json": active_compiled if isinstance(active_compiled, dict) else None,
                "predicted_script": active_compiled if isinstance(active_compiled, dict) else None,
                "selected_predicted_script": active_compiled if isinstance(active_compiled, dict) else None,
            }
        )

    return chunk_rows, scene_rows, bundle_rows, compiled_rows


def summarize_v1_eval_rows(rows: list[dict[str, Any]], *, model_id: str, metric_keys: list[str]) -> dict[str, Any]:
    summary: dict[str, Any] = {"model_id": model_id, "rows": len(rows)}
    for key in metric_keys:
        values = [float(row.get(key, 0.0) or 0.0) for row in rows]
        summary[key] = mean(values) if values else 0.0
    return summary


def _ratio(values: Any) -> float:
    values = list(values)
    if not values:
        return 0.0
    positives = sum(1 for value in values if bool(value))
    return positives / float(len(values))

