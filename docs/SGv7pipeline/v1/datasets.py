from __future__ import annotations

import hashlib
import json
import random
from pathlib import Path
from typing import Any

try:
    from .contracts import ScriptDocumentStateRecord
except ImportError:  # pragma: no cover
    from contracts import ScriptDocumentStateRecord


CHUNK_DRAFT_SYSTEM_PROMPT = (
    "Ты SceneChunk planner. Верни только валидный JSON sg_scene_chunk_draft_v1 без пояснений."
)
CHUNK_PREFERENCE_SYSTEM_PROMPT = (
    "Ты critic chunk draft quality. Сравни два кандидата и верни только JSON verdict."
)


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


def write_jsonl(rows: list[dict[str, Any]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def extract_document_state(row: dict[str, Any]) -> ScriptDocumentStateRecord | None:
    for key in ("document_state", "documentState", "sg_script_document_v1", "script_document"):
        payload = row.get(key)
        if isinstance(payload, dict):
            return payload
    if isinstance(row.get("bundlePlan"), dict) and isinstance(row.get("sceneCandidates"), list):
        return row  # type: ignore[return-value]
    return None


def macro_scene_builder(document_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source_row in document_rows:
        document = extract_document_state(source_row)
        if not document:
            continue
        document_id = str(document.get("documentID") or "")
        for scene in document.get("sceneCandidates", []):
            if not isinstance(scene, dict):
                continue
            source_text = str(scene.get("sourceText") or "")
            rows.append(
                {
                    "document_id": document_id,
                    "scene_id": str(scene.get("id") or ""),
                    "scene_index": int(scene.get("sceneIndex") or 0),
                    "scene_heading": (scene.get("metadata") or {}).get("sceneHeading"),
                    "location_name": (scene.get("metadata") or {}).get("locationName"),
                    "is_implicit": bool(scene.get("isImplicit", False)),
                    "source_text": source_text,
                    "source_hash": normalized_source_hash(source_text),
                }
            )
    return rows


def chunk_anchor_builder(document_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source_row in document_rows:
        document = extract_document_state(source_row)
        if not document:
            continue
        document_id = str(document.get("documentID") or "")
        for scene in _iter_bundle_scenes(document):
            for chunk in scene.get("chunks", []):
                if not isinstance(chunk, dict):
                    continue
                rows.append(
                    {
                        "document_id": document_id,
                        "scene_id": str(scene.get("sceneID") or ""),
                        "chunk_id": str(chunk.get("chunkID") or ""),
                        "chunk_index": int(chunk.get("chunkIndex") or 0),
                        "source_text": str(chunk.get("sourceText") or ""),
                        "anchors": chunk.get("anchors") or {},
                    }
                )
    return rows


def entity_registry_builder(document_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source_row in document_rows:
        document = extract_document_state(source_row)
        if not document:
            continue
        document_id = str(document.get("documentID") or "")
        for state in document.get("stitchStates", []):
            if not isinstance(state, dict):
                continue
            rows.append(
                {
                    "document_id": document_id,
                    "scene_id": str(state.get("sceneID") or ""),
                    "scene_index": int(state.get("sceneIndex") or 0),
                    "registry_snapshot": state.get("registry") or {},
                    "continuity_diagnostics": state.get("continuityDiagnostics") or [],
                }
            )
    return rows


def chunk_patch_builder(document_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source_row in document_rows:
        document = extract_document_state(source_row)
        if not document:
            continue
        document_id = str(document.get("documentID") or "")
        stitch_states = {
            str(state.get("sceneID") or ""): state
            for state in document.get("stitchStates", [])
            if isinstance(state, dict)
        }
        draft_by_chunk_id = {
            str(draft.get("chunkID") or ""): draft
            for draft in source_row.get("scene_chunk_drafts", [])
            if isinstance(draft, dict)
        }
        for scene in _iter_bundle_scenes(document):
            scene_id = str(scene.get("sceneID") or "")
            registry = (stitch_states.get(scene_id) or {}).get("registry") or {}
            for chunk in scene.get("chunks", []):
                if not isinstance(chunk, dict):
                    continue
                chunk_id = str(chunk.get("chunkID") or "")
                assistant_payload = draft_by_chunk_id.get(chunk_id) or chunk
                rows.append(
                    {
                        "document_id": document_id,
                        "scene_id": scene_id,
                        "chunk_id": chunk_id,
                        "messages": [
                            {"role": "system", "content": CHUNK_DRAFT_SYSTEM_PROMPT},
                            {
                                "role": "user",
                                "content": json.dumps(
                                    {
                                        "contractVersion": "sg_scene_chunk_draft_v1",
                                        "source_text": chunk.get("sourceText") or "",
                                        "anchors": chunk.get("anchors") or {},
                                        "registry_snapshot": registry,
                                    },
                                    ensure_ascii=False,
                                ),
                            },
                            {
                                "role": "assistant",
                                "content": json.dumps(assistant_payload, ensure_ascii=False),
                            },
                        ],
                    }
                )
    return rows


def chunk_preference_builder(
    candidate_rows: list[dict[str, Any]],
    baseline_rows: list[dict[str, Any]],
    *,
    candidate_scores: dict[tuple[str, str, str], float] | None = None,
    baseline_scores: dict[tuple[str, str, str], float] | None = None,
) -> list[dict[str, Any]]:
    candidate_scores = candidate_scores or {}
    baseline_scores = baseline_scores or {}
    candidate_by_key = {_row_key(row): row for row in candidate_rows}
    baseline_by_key = {_row_key(row): row for row in baseline_rows}
    shared_keys = sorted(set(candidate_by_key) & set(baseline_by_key))

    rows: list[dict[str, Any]] = []
    for key in shared_keys:
        candidate = candidate_by_key[key]
        baseline = baseline_by_key[key]
        candidate_score = float(candidate_scores.get(key, candidate.get("score", 0.0) or 0.0))
        baseline_score = float(baseline_scores.get(key, baseline.get("score", 0.0) or 0.0))
        if candidate_score == baseline_score:
            continue
        chosen = candidate if candidate_score > baseline_score else baseline
        rejected = baseline if candidate_score > baseline_score else candidate
        rows.append(
            {
                "document_id": key[0],
                "scene_id": key[1],
                "chunk_id": key[2],
                "messages": [
                    {"role": "system", "content": CHUNK_PREFERENCE_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": json.dumps(
                            {
                                "document_id": key[0],
                                "scene_id": key[1],
                                "chunk_id": key[2],
                                "task": "Choose the better sg_scene_chunk_draft_v1 candidate.",
                            },
                            ensure_ascii=False,
                        ),
                    },
                ],
                "chosen": json.dumps(chosen, ensure_ascii=False),
                "rejected": json.dumps(rejected, ensure_ascii=False),
                "candidate_score": candidate_score,
                "baseline_score": baseline_score,
            }
        )
    return rows


def split_rows_by_document(
    rows: list[dict[str, Any]],
    *,
    val_fraction: float,
    seed: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    document_ids = sorted({str(row.get("document_id") or "") for row in rows if row.get("document_id")})
    rng = random.Random(seed)
    rng.shuffle(document_ids)
    val_count = min(max(1, int(round(len(document_ids) * val_fraction))), len(document_ids)) if document_ids else 0
    val_ids = set(document_ids[:val_count])
    train_rows = [row for row in rows if str(row.get("document_id") or "") not in val_ids]
    val_rows = [row for row in rows if str(row.get("document_id") or "") in val_ids]
    return train_rows, val_rows


def normalized_source_hash(text: str) -> str:
    normalized = " ".join(text.lower().split())
    return "nsh_" + hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:8]


def _iter_bundle_scenes(document: ScriptDocumentStateRecord) -> list[dict[str, Any]]:
    bundle_plan = document.get("bundlePlan") or {}
    scenes = bundle_plan.get("scenes", []) if isinstance(bundle_plan, dict) else []
    return [scene for scene in scenes if isinstance(scene, dict)]


def _row_key(row: dict[str, Any]) -> tuple[str, str, str]:
    return (
        str(row.get("document_id") or ""),
        str(row.get("scene_id") or ""),
        str(row.get("chunk_id") or ""),
    )

