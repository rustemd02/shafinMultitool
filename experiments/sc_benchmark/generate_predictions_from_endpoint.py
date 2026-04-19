#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any
from urllib import error, request


SYSTEM_PROMPT = "Ты SceneScript parser. Верни только валидный JSON SceneScript без пояснений и без markdown."


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


def _norm_base_url(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized
    if normalized.endswith("/v1"):
        return normalized + "/chat/completions"
    if normalized.endswith("/v1/"):
        return normalized + "chat/completions"
    return normalized + "/v1/chat/completions"


def _extract_choice_text(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    message = first.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            chunks: list[str] = []
            for item in content:
                if isinstance(item, dict):
                    text = item.get("text")
                    if isinstance(text, str):
                        chunks.append(text)
            return "\n".join(chunks)
    text = first.get("text")
    if isinstance(text, str):
        return text
    return ""


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


def _first_json_object(text: str) -> dict[str, Any] | None:
    candidate = _strip_markdown_fence(text)
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


def _render_user_prompt(case: dict[str, Any], *, include_marked_objects: bool) -> str:
    source_text = str(case.get("source_text") or "").strip()
    lines = [
        "Task instruction:",
        "Сконвертируй source text в SceneScript JSON.",
        "",
        "Output contract:",
        "Верни только JSON c top-level полями actors, objects, beats, spatialRelations, originalDescription.",
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
    endpoint_url: str,
    api_key: str,
    model_name: str,
    seed: int,
    user_prompt: str,
    temperature: float,
    top_p: float,
    max_output_tokens: int,
    timeout_sec: int,
) -> str:
    payload = {
        "model": model_name,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": temperature,
        "top_p": top_p,
        "max_tokens": max_output_tokens,
        "seed": seed,
    }
    headers = {"Content-Type": "application/json"}
    if api_key.strip():
        headers["Authorization"] = f"Bearer {api_key.strip()}"
    req = request.Request(
        endpoint_url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with request.urlopen(req, timeout=timeout_sec) as resp:
        body = resp.read().decode("utf-8")
    parsed = json.loads(body)
    if not isinstance(parsed, dict):
        return ""
    return _extract_choice_text(parsed)


def _predict_single_case(
    *,
    case: dict[str, Any],
    endpoint_url: str,
    api_key: str,
    model_name: str,
    seed: int,
    temperature: float,
    top_p: float,
    max_output_tokens: int,
    timeout_sec: int,
    max_retries: int,
    retry_backoff_sec: float,
    include_marked_objects: bool,
) -> dict[str, Any]:
    eval_case_id = str(case.get("eval_case_id") or "").strip()
    if not eval_case_id:
        raise ValueError("eval_case_id is missing in eval case")
    user_prompt = _render_user_prompt(case, include_marked_objects=include_marked_objects)
    last_error = ""
    raw_text = ""
    for attempt in range(1, max_retries + 1):
        try:
            raw_text = _api_chat_completion(
                endpoint_url=endpoint_url,
                api_key=api_key,
                model_name=model_name,
                seed=seed,
                user_prompt=user_prompt,
                temperature=temperature,
                top_p=top_p,
                max_output_tokens=max_output_tokens,
                timeout_sec=timeout_sec,
            )
            break
        except (error.HTTPError, error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
            last_error = str(exc)
            if attempt < max_retries:
                time.sleep(retry_backoff_sec * attempt)
            else:
                raw_text = ""
    parsed = _first_json_object(raw_text)
    row: dict[str, Any] = {"eval_case_id": eval_case_id, "raw_output_text": raw_text}
    if isinstance(parsed, dict):
        row["predicted_script"] = parsed
        row["raw_output_json"] = parsed
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
        default=Path("/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/predictions_real_v1"),
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
    parser.add_argument("--resume", action="store_true", help="Skip already existing model/seed files.")
    parser.add_argument("--request-log-every", type=int, default=25)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    eval_bundle_dir = args.eval_bundle_dir.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    endpoint_url = _norm_base_url(args.api_base_url)
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
    print(f"[predict] cases={len(cases)} jobs={total_jobs} endpoint={endpoint_url}")

    for model_id in model_ids:
        serving_model = _model_name_for(model_id, model_map)
        for seed in seeds:
            out_path = output_dir / f"{model_id}_seed{seed}.jsonl"
            if args.resume and out_path.exists():
                print(f"[predict] skip existing: {out_path}")
                continue

            print(f"[predict] start model={model_id} serving_model={serving_model} seed={seed}")
            if args.dry_run:
                continue

            rows: list[dict[str, Any] | None] = [None] * len(cases)
            completed = 0
            with ThreadPoolExecutor(max_workers=max(1, args.workers)) as executor:
                futures = {
                    executor.submit(
                        _predict_single_case,
                        case=case,
                        endpoint_url=endpoint_url,
                        api_key=api_key,
                        model_name=serving_model,
                        seed=seed,
                        temperature=args.temperature,
                        top_p=args.top_p,
                        max_output_tokens=args.max_output_tokens,
                        timeout_sec=args.timeout_sec,
                        max_retries=args.max_retries,
                        retry_backoff_sec=args.retry_backoff_sec,
                        include_marked_objects=bool(args.include_marked_objects),
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
