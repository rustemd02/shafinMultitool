#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any


SYSTEM_PROMPT = "Ты SceneScript parser. Верни только валидный JSON SceneScript без пояснений и без markdown."
_THINK_BLOCK_RE = re.compile(r"<think\b[^>]*>.*?</think>", flags=re.IGNORECASE | re.DOTALL)
_THINK_OPEN_RE = re.compile(r"<think\b[^>]*>", flags=re.IGNORECASE)
_THINK_CLOSE_RE = re.compile(r"</think>", flags=re.IGNORECASE)
_TARGET_REQUIRED_ACTIONS = {"approach", "stop", "passby", "pass_by", "pass-by"}
_LEGACY_BEAT_FIELDS = {
    "type",
    "action",
    "actorId",
    "actor_id",
    "actorIds",
    "target",
    "targetId",
    "dialogue",
    "resultingText",
    "resultingDialogue",
    "resultingPose",
}


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON object expected: {path}")
    return payload


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if not raw:
                continue
            row = json.loads(raw)
            if isinstance(row, dict):
                rows.append(row)
    return rows


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def _model_family_dir(model_id: str) -> str:
    if model_id.startswith("dataset_v6"):
        return "v6"
    if model_id.startswith("dataset_v7"):
        return "v7"
    if model_id.startswith("base_"):
        return "base"
    return "other"


def _prediction_path(output_dir: Path, model_id: str, seed: int) -> Path:
    return output_dir / _model_family_dir(model_id) / f"{model_id}_seed{seed}.jsonl"


def _norm_base_url(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    return normalized


def _base_url_for_openai_client(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized[: -len("/chat/completions")]
    return normalized


def _build_openai_client(*, api_base_url: str, api_key: str, timeout_sec: int) -> Any:
    try:
        from openai import OpenAI
    except ImportError as exc:
        raise RuntimeError("openai package is required to run endpoint predictions") from exc

    kwargs: dict[str, Any] = {
        "base_url": _base_url_for_openai_client(api_base_url),
        "timeout": float(timeout_sec),
    }
    if api_key.strip():
        kwargs["api_key"] = api_key.strip()
    return OpenAI(**kwargs)


def _strip_markdown_fence(text: str) -> str:
    candidate = text.strip()
    if not candidate.startswith("```"):
        return candidate
    lines = candidate.splitlines()
    if len(lines) < 2:
        return candidate
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()


def _strip_think_tags(text: str) -> str:
    value = _THINK_BLOCK_RE.sub("", text)
    value = _THINK_OPEN_RE.sub("", value)
    value = _THINK_CLOSE_RE.sub("", value)
    return value


def _normalize_raw_output_text(text: str, *, strip_think_tags: bool) -> str:
    value = text
    if strip_think_tags:
        value = _strip_think_tags(value)
    return _strip_markdown_fence(value).strip()


def _first_json_object(text: str, *, strip_think_tags: bool) -> dict[str, Any] | None:
    candidate = _normalize_raw_output_text(text, strip_think_tags=strip_think_tags)
    try:
        parsed = json.loads(candidate)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    start = candidate.find("{")
    if start < 0:
        return None
    depth = 0
    in_string = False
    escape = False
    end = -1
    for idx in range(start, len(candidate)):
        ch = candidate[idx]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = idx
                break
    if end < 0:
        return None
    snippet = candidate[start : end + 1]
    try:
        parsed = json.loads(snippet)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        return None
    return None


def _normalize_action_type(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    lowered = raw.replace("-", "_").replace(" ", "_")
    if lowered.lower() == "passby":
        return "passby"
    return lowered.lower()


def _collect_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    top_level = script.get("actions")
    if isinstance(top_level, list):
        for payload in top_level:
            if isinstance(payload, dict):
                actions.append(payload)
    beats = script.get("beats")
    if isinstance(beats, list):
        for beat in beats:
            if not isinstance(beat, dict):
                continue
            beat_actions = beat.get("actions")
            if not isinstance(beat_actions, list):
                continue
            for payload in beat_actions:
                if isinstance(payload, dict):
                    actions.append(payload)
    return actions


def _action_refs(action: dict[str, Any]) -> tuple[str, str] | None:
    actor_camel = str(action.get("actorId") or "").strip()
    actor_snake = str(action.get("actor_id") or "").strip()
    if actor_camel and actor_snake and actor_camel != actor_snake:
        return None
    actor_id = actor_camel or actor_snake

    target_camel = str(action.get("targetId") or "").strip()
    target_plain = str(action.get("target") or "").strip()
    if target_camel and target_plain and target_camel != target_plain:
        return None
    target_id = target_plain or target_camel
    return actor_id, target_id


def _schema_valid(script: dict[str, Any]) -> bool:
    actors = script.get("actors")
    if not isinstance(actors, list):
        return False
    objects = script.get("objects")
    if not isinstance(objects, list):
        return False

    actor_ids: set[str] = set()
    object_ids: set[str] = set()
    for actor in actors:
        if not isinstance(actor, dict):
            return False
        actor_id = str(actor.get("id", "")).strip()
        if not actor_id or actor_id in actor_ids:
            return False
        actor_ids.add(actor_id)
    for obj in objects:
        if not isinstance(obj, dict):
            return False
        object_id = str(obj.get("id", "")).strip()
        if not object_id or object_id in object_ids:
            return False
        object_ids.add(object_id)

    valid_target_ids = actor_ids.union(object_ids)

    def _action_ok(action: dict[str, Any]) -> bool:
        refs = _action_refs(action)
        if refs is None:
            return False
        actor_id, target_id = refs
        if not actor_id or actor_id not in actor_ids:
            return False
        action_type = _normalize_action_type(action.get("type"))
        if not action_type:
            return False
        if target_id and target_id not in valid_target_ids:
            return False
        if action_type in _TARGET_REQUIRED_ACTIONS and not target_id:
            return False
        return True

    top_actions = script.get("actions")
    if top_actions is not None and not isinstance(top_actions, list):
        return False
    if isinstance(top_actions, list):
        for action in top_actions:
            if not isinstance(action, dict) or not _action_ok(action):
                return False

    beats = script.get("beats")
    if beats is not None and not isinstance(beats, list):
        return False
    if isinstance(beats, list):
        for beat in beats:
            if not isinstance(beat, dict):
                return False
            beat_actions = beat.get("actions")
            if beat_actions is not None and not isinstance(beat_actions, list):
                return False
            if isinstance(beat_actions, list):
                for action in beat_actions:
                    if not isinstance(action, dict) or not _action_ok(action):
                        return False
    return True


def _has_pred_actions_empty(script: dict[str, Any]) -> bool:
    return len(_collect_actions(script)) == 0


def _has_legacy_beat_level_actions(script: dict[str, Any]) -> bool:
    beats = script.get("beats")
    if not isinstance(beats, list):
        return False
    for beat in beats:
        if not isinstance(beat, dict):
            continue
        beat_actions = beat.get("actions")
        if isinstance(beat_actions, list) and beat_actions:
            continue
        if any(field in beat for field in _LEGACY_BEAT_FIELDS):
            return True
    return False


def _canonicalize_legacy_beats(script: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    candidate = copy.deepcopy(script)
    beats = candidate.get("beats")
    if not isinstance(beats, list):
        return candidate, False
    changed = False
    for beat_index, beat in enumerate(beats, start=1):
        if not isinstance(beat, dict):
            continue
        beat_actions = beat.get("actions")
        if isinstance(beat_actions, list) and beat_actions:
            continue

        action_type = str(beat.get("type") or beat.get("action") or "").strip()
        actor_id = str(beat.get("actorId") or beat.get("actor_id") or "").strip()
        actor_ids = beat.get("actorIds")
        if not actor_id and isinstance(actor_ids, list) and len(actor_ids) == 1:
            actor_id = str(actor_ids[0] or "").strip()
        if not actor_id:
            continue
        if not action_type:
            continue

        target_id = str(beat.get("target") or beat.get("targetId") or "").strip()
        dialogue = str(beat.get("dialogue") or beat.get("resultingDialogue") or beat.get("resultingText") or "").strip()
        resulting_pose = str(beat.get("resultingPose") or "").strip()

        action: dict[str, Any] = {
            "id": f"action_{beat_index}_1",
            "actorId": actor_id,
            "type": action_type,
        }
        if target_id:
            action["target"] = target_id
        if dialogue:
            action["dialogue"] = dialogue
        if resulting_pose:
            action["resultingPose"] = resulting_pose
        beat["actions"] = [action]
        for key in _LEGACY_BEAT_FIELDS:
            if key == "resultingPose":
                # keep resultingPose on action only
                beat.pop(key, None)
                continue
            if key in {"type", "action", "actorId", "actor_id", "actorIds", "target", "targetId", "dialogue", "resultingText", "resultingDialogue"}:
                beat.pop(key, None)
        changed = True
    return candidate, changed


def _build_repair_prompt(*, source_text: str, malformed_output: str) -> str:
    clipped_output = malformed_output.strip()
    if len(clipped_output) > 4000:
        clipped_output = clipped_output[:4000]
    return "\n".join(
        [
            "Task instruction:",
            "Исправь ответ модели в строгий SceneScript JSON.",
            "",
            "Critical constraints:",
            "- Верни только валидный JSON без markdown и без комментариев.",
            "- Top-level поля: actors, objects, beats, spatialRelations, originalDescription.",
            "- Каждое действие должно быть в beats[i].actions[j], а не в полях beat-level type/target/dialogue.",
            "- Не добавляй лишних сущностей и не меняй смысл source text.",
            "",
            "Source text:",
            source_text.strip(),
            "",
            "Malformed model output:",
            clipped_output,
        ]
    )


def _repair_with_llm(
    *,
    case: dict[str, Any],
    malformed_output: str,
    client: Any,
    model_name: str,
    seed: int,
    temperature: float,
    top_p: float,
    max_output_tokens: int,
    strip_think_tags: bool,
) -> dict[str, Any] | None:
    source_text = str(case.get("source_text") or "").strip()
    if not source_text:
        return None
    repair_prompt = _build_repair_prompt(source_text=source_text, malformed_output=malformed_output)
    repaired_text = _api_chat_completion(
        client=client,
        model_name=model_name,
        seed=seed + 100003,
        user_prompt=repair_prompt,
        temperature=temperature,
        top_p=top_p,
        max_output_tokens=max_output_tokens,
    )
    parsed = _first_json_object(repaired_text, strip_think_tags=strip_think_tags)
    if not isinstance(parsed, dict):
        return None
    if not _schema_valid(parsed):
        return None
    return parsed


def _render_user_prompt(case: dict[str, Any], *, include_marked_objects: bool) -> str:
    source_text = str(case.get("source_text") or "").strip()
    lines = [
        "Task instruction:",
        "Сконвертируй source text в SceneScript JSON.",
        "",
        "Output contract:",
        "Верни только JSON c top-level полями actors, objects, beats, spatialRelations, originalDescription.",
        "",
        "Strict structural rules:",
        "- Каждый beat обязан иметь массив actions.",
        "- Все действия должны быть только внутри beats[].actions[].",
        "- Нельзя использовать beat-level поля type/action/target/dialogue как единственный носитель действия.",
        "- Никакого markdown, объяснений и chain-of-thought.",
    ]
    if include_marked_objects:
        marked = case.get("marked_objects")
        if isinstance(marked, list) and marked:
            lines.extend(["", "Marked objects:"])
            for item in marked:
                if not isinstance(item, dict):
                    continue
                marker_id = str(item.get("id") or "").strip()
                marker_name = str(item.get("name") or marker_id or "-").strip()
                marker_type = str(item.get("type") or "generic").strip()
                lines.append(f"- id={marker_id}; name={marker_name}; type={marker_type}; aliases=-")
    lines.extend(["", "Source text:", source_text])
    return "\n".join(lines)


def _api_chat_completion(
    *,
    client: Any,
    model_name: str,
    seed: int,
    user_prompt: str,
    temperature: float,
    top_p: float,
    max_output_tokens: int,
) -> str:
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        temperature=temperature,
        top_p=top_p,
        max_tokens=max_output_tokens,
        seed=seed,
    )
    message = response.choices[0].message if response.choices else None
    if message is None:
        return ""
    content = message.content
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks: list[str] = []
        for item in content:
            if isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str):
                    chunks.append(text)
            else:
                text = getattr(item, "text", None)
                if isinstance(text, str):
                    chunks.append(text)
        return "\n".join(chunks)
    return str(content or "")


def _predict_single_case(
    *,
    case: dict[str, Any],
    client: Any,
    model_name: str,
    seed: int,
    temperature: float,
    top_p: float,
    max_output_tokens: int,
    timeout_sec: int,
    max_retries: int,
    retry_backoff_sec: float,
    include_marked_objects: bool,
    strip_think_tags: bool,
    canonical_repair: bool,
    fail_on_actions_empty: bool,
    report_slice: str,
) -> dict[str, Any]:
    eval_case_id = str(case.get("eval_case_id") or "").strip()
    if not eval_case_id:
        raise ValueError("eval_case_id is missing in eval case")
    user_prompt = _render_user_prompt(case, include_marked_objects=include_marked_objects)
    last_error = ""
    raw_text = ""
    raw_text_clean = ""
    for attempt in range(1, max_retries + 1):
        try:
            raw_text = _api_chat_completion(
                client=client,
                model_name=model_name,
                seed=seed,
                user_prompt=user_prompt,
                temperature=temperature,
                top_p=top_p,
                max_output_tokens=max_output_tokens,
            )
            raw_text_clean = _normalize_raw_output_text(raw_text, strip_think_tags=strip_think_tags)
            break
        except Exception as exc:
            last_error = str(exc)
            if attempt < max_retries:
                time.sleep(retry_backoff_sec * attempt)
            else:
                raw_text = ""
                raw_text_clean = ""

    reason_codes: list[str] = []
    model_only = _first_json_object(raw_text_clean, strip_think_tags=False) if raw_text_clean else None
    if model_only is None and raw_text_clean:
        reason_codes.append("json_parse_fail")

    end_to_end = copy.deepcopy(model_only) if isinstance(model_only, dict) else None
    repair_applied = False
    legacy_repaired = False
    repair_mode = "none"

    if canonical_repair:
        if end_to_end is None and raw_text_clean:
            repaired = _repair_with_llm(
                case=case,
                malformed_output=raw_text_clean,
                client=client,
                model_name=model_name,
                seed=seed,
                temperature=temperature,
                top_p=top_p,
                max_output_tokens=max_output_tokens,
                strip_think_tags=strip_think_tags,
            )
            if isinstance(repaired, dict):
                end_to_end = repaired
                repair_applied = True
                repair_mode = "llm_parse_repair"

        if isinstance(end_to_end, dict):
            if _has_legacy_beat_level_actions(end_to_end):
                repaired, changed = _canonicalize_legacy_beats(end_to_end)
                if changed:
                    end_to_end = repaired
                    legacy_repaired = True
                    repair_applied = True
                    repair_mode = "deterministic_legacy_repair"
                    reason_codes.append("legacy_beat_repaired")
            if _has_pred_actions_empty(end_to_end) and fail_on_actions_empty:
                reason_codes.append("pred_actions_empty")
                repaired = _repair_with_llm(
                    case=case,
                    malformed_output=raw_text_clean,
                    client=client,
                    model_name=model_name,
                    seed=seed,
                    temperature=temperature,
                    top_p=top_p,
                    max_output_tokens=max_output_tokens,
                    strip_think_tags=strip_think_tags,
                )
                if isinstance(repaired, dict) and not _has_pred_actions_empty(repaired):
                    end_to_end = repaired
                    repair_applied = True
                    repair_mode = "llm_actions_repair"
                    reason_codes = [code for code in reason_codes if code != "pred_actions_empty"]

            if not _schema_valid(end_to_end):
                reason_codes.append("schema_fail")
                end_to_end = None
            elif fail_on_actions_empty and _has_pred_actions_empty(end_to_end):
                reason_codes.append("pred_actions_empty")
                end_to_end = None

    if report_slice == "model_only":
        selected = model_only
    else:
        selected = end_to_end if isinstance(end_to_end, dict) else None

    if selected is None and report_slice == "end_to_end" and isinstance(model_only, dict) and not canonical_repair:
        selected = model_only

    row: dict[str, Any] = {
        "eval_case_id": eval_case_id,
        "raw_output_text": raw_text,
        "raw_output_text_clean": raw_text_clean,
        "slice_reason_codes": sorted(set(reason_codes)),
        "repair_applied": repair_applied,
        "repair_mode": repair_mode,
        "legacy_beat_repaired": legacy_repaired,
        "selected_slice": report_slice,
    }
    if report_slice == "both":
        row["model_only_predicted_script"] = model_only
        row["end_to_end_predicted_script"] = end_to_end

    # Keep raw_output_json aligned with "raw model parse" semantics.
    if isinstance(model_only, dict):
        row["raw_output_json"] = model_only
        row["model_only_output_json"] = model_only

    if isinstance(selected, dict):
        row["predicted_script"] = selected
        row["selected_predicted_script"] = selected
        row["model_only_schema_valid"] = _schema_valid(model_only) if isinstance(model_only, dict) else False
        row["end_to_end_schema_valid"] = _schema_valid(end_to_end) if isinstance(end_to_end, dict) else False
    elif last_error:
        row["error"] = last_error
    return row


def _model_name_for(model_id: str, model_map: dict[str, str]) -> str:
    value = model_map.get(model_id)
    if value is not None and value.strip():
        return value.strip()
    return model_id


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate predictions JSONL for scientific benchmark from OpenAI-compatible endpoint.")
    parser.add_argument(
        "--eval-bundle-dir",
        type=Path,
        default=Path("/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/predictions_real_v1_export"),
    )
    parser.add_argument("--models", default="base_qwen3_1_7b,dataset_v6,dataset_v7,dataset_v7_orpo")
    parser.add_argument("--seeds", default="42,43,44")
    parser.add_argument("--serving-model-map-json", type=Path, help="JSON object: {model_id: serving_model_name}")
    parser.add_argument("--api-base-url", default=os.environ.get("OPENAI_BASE_URL", "http://127.0.0.1:8000/v1"))
    parser.add_argument("--api-key-env", default="OPENAI_API_KEY")
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--max-output-tokens", type=int, default=2048)
    parser.add_argument("--timeout-sec", type=int, default=120)
    parser.add_argument("--max-retries", type=int, default=3)
    parser.add_argument("--retry-backoff-sec", type=float, default=2.0)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--include-marked-objects", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--strip-think-tags", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--canonical-repair", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument(
        "--report-slice",
        choices=("model_only", "end_to_end", "both"),
        default="both",
        help="Which inference slice should be materialized into predicted_script.",
    )
    parser.add_argument(
        "--fail-on-actions-empty",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Treat outputs with empty actions as unusable for benchmark predicted_script.",
    )
    parser.add_argument("--resume", action="store_true", help="Skip already existing model/seed files.")
    parser.add_argument("--request-log-every", type=int, default=25)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    eval_bundle_dir = args.eval_bundle_dir.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    api_base_url = _norm_base_url(args.api_base_url)
    model_ids = [item.strip() for item in args.models.split(",") if item.strip()]
    seeds = [int(item.strip()) for item in args.seeds.split(",") if item.strip()]
    if not model_ids:
        raise SystemExit("No models specified")
    if not seeds:
        raise SystemExit("No seeds specified")

    cases_path = eval_bundle_dir / "eval_cases.jsonl"
    if not cases_path.exists():
        raise SystemExit(f"Missing eval cases: {cases_path}")
    cases = _read_jsonl(cases_path)
    if not cases:
        raise SystemExit("Eval bundle has no cases")

    model_map: dict[str, str] = {}
    if args.serving_model_map_json:
        payload = _read_json(args.serving_model_map_json.expanduser().resolve())
        model_map = {str(k): str(v) for k, v in payload.items()}

    api_key = os.environ.get(args.api_key_env, "")
    if not args.dry_run and not api_key.strip():
        print(f"[predict] warning: env {args.api_key_env} is empty (assuming local endpoint without auth).")

    output_dir.mkdir(parents=True, exist_ok=True)
    total_jobs = len(model_ids) * len(seeds)
    print(f"[predict] cases={len(cases)} jobs={total_jobs} endpoint={api_base_url}")

    for model_id in model_ids:
        serving_model = _model_name_for(model_id, model_map)
        for seed in seeds:
            out_path = _prediction_path(output_dir, model_id, seed)
            if args.resume and out_path.exists():
                print(f"[predict] skip existing: {out_path}")
                continue

            print(f"[predict] start model={model_id} serving_model={serving_model} seed={seed}")
            if args.dry_run:
                continue

            client = _build_openai_client(
                api_base_url=str(api_base_url),
                api_key=api_key,
                timeout_sec=int(args.timeout_sec),
            )
            rows: list[dict[str, Any] | None] = [None] * len(cases)
            completed = 0
            with ThreadPoolExecutor(max_workers=max(1, args.workers)) as executor:
                futures = {
                    executor.submit(
                        _predict_single_case,
                        case=case,
                        client=client,
                        model_name=serving_model,
                        seed=seed,
                        temperature=args.temperature,
                        top_p=args.top_p,
                        max_output_tokens=args.max_output_tokens,
                        timeout_sec=args.timeout_sec,
                        max_retries=args.max_retries,
                        retry_backoff_sec=args.retry_backoff_sec,
                        include_marked_objects=bool(args.include_marked_objects),
                        strip_think_tags=bool(args.strip_think_tags),
                        canonical_repair=bool(args.canonical_repair),
                        fail_on_actions_empty=bool(args.fail_on_actions_empty),
                        report_slice=str(args.report_slice),
                    ): idx
                    for idx, case in enumerate(cases)
                }
                for future in as_completed(futures):
                    idx = futures[future]
                    try:
                        rows[idx] = future.result()
                    except Exception as exc:  # noqa: BLE001
                        case_id = str(cases[idx].get("eval_case_id") or "")
                        rows[idx] = {"eval_case_id": case_id, "raw_output_text": "", "error": str(exc)}
                    completed += 1
                    if completed % max(1, args.request_log_every) == 0 or completed == len(cases):
                        print(f"[predict] progress model={model_id} seed={seed} {completed}/{len(cases)}")

            final_rows = [row for row in rows if isinstance(row, dict)]
            _write_jsonl(out_path, final_rows)
            parseable = sum(1 for row in final_rows if isinstance(row.get("predicted_script"), dict))
            reason_counts: dict[str, int] = {}
            for row in final_rows:
                for code in row.get("slice_reason_codes", []):
                    key = str(code)
                    reason_counts[key] = reason_counts.get(key, 0) + 1
            slice_summary = {
                "model_id": model_id,
                "seed": seed,
                "total_rows": len(final_rows),
                "predicted_script_rows": parseable,
                "model_only_rows": sum(1 for row in final_rows if isinstance(row.get("model_only_predicted_script"), dict)),
                "end_to_end_rows": sum(1 for row in final_rows if isinstance(row.get("end_to_end_predicted_script"), dict)),
                "reason_counts": reason_counts,
                "report_slice": str(args.report_slice),
                "canonical_repair": bool(args.canonical_repair),
                "strip_think_tags": bool(args.strip_think_tags),
                "fail_on_actions_empty": bool(args.fail_on_actions_empty),
            }
            out_path.with_suffix(".slice_summary.json").write_text(
                json.dumps(slice_summary, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print(
                "[predict] done model={model} seed={seed} parseable={ok}/{total} file={path}".format(
                    model=model_id,
                    seed=seed,
                    ok=parseable,
                    total=len(final_rows),
                    path=out_path,
                )
            )

    print(f"[predict] completed. output_dir={output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
