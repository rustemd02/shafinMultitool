from __future__ import annotations

import json
import os
import re
import threading
from typing import Any

from jsonschema import Draft202012Validator

from .config import CriticBackend, CriticResult, ValidationRequest
from .critic_prompts import CRITIC_SYSTEM_PROMPT, build_critic_user_prompt, build_prompt_payload
from .recoverability import deterministic_beat_collapse, deterministic_chronology_cue_passed
from .taxonomy import REJECT_CODES


class SemanticCriticError(RuntimeError):
    pass


_CRITIC_BASE_PROPERTIES: dict[str, object] = {
    "verdict": {
        "type": "string",
        "enum": ["pass", "soft_fail", "hard_fail"],
    },
    "confidence": {
        "type": "number",
        "minimum": 0.0,
        "maximum": 1.0,
    },
    "findings": {
        "type": "array",
        "items": {"type": "string"},
    },
    "detected_failures": {
        "type": "array",
        "items": {
            "type": "string",
            "enum": sorted(REJECT_CODES),
        },
    },
    "chronology_preserved": {"type": "boolean"},
    "object_grounding_preserved": {"type": "boolean"},
    "ordinal_binding_preserved": {"type": "boolean"},
    "unsupported_action_preserved": {"type": "boolean"},
    "invented_content_present": {"type": "boolean"},
    "summary": {"type": "string"},
}

_CRITIC_BASE_REQUIRED = [
    "verdict",
    "confidence",
    "findings",
    "detected_failures",
    "chronology_preserved",
    "object_grounding_preserved",
    "ordinal_binding_preserved",
    "unsupported_action_preserved",
    "invented_content_present",
    "summary",
]

_CRITIC_BACKEND_SCHEMA: dict[str, object] = {
    "type": "object",
    "additionalProperties": False,
    "required": _CRITIC_BASE_REQUIRED,
    "properties": _CRITIC_BASE_PROPERTIES,
}

_CRITIC_RESULT_SCHEMA: dict[str, object] = {
    "type": "object",
    "additionalProperties": False,
    "required": _CRITIC_BASE_REQUIRED + ["artifact_id", "execution"],
    "properties": {
        **_CRITIC_BASE_PROPERTIES,
        "artifact_id": {"type": "string", "minLength": 1},
        "execution": {
            "type": "object",
            "additionalProperties": False,
            "required": ["temperature", "top_p", "max_output_tokens", "recomputed"],
            "properties": {
                "temperature": {"type": "number"},
                "top_p": {"type": "number"},
                "max_output_tokens": {"type": "integer", "minimum": 1},
                "recomputed": {"type": "boolean"},
            },
        },
    },
}

_OPENAI_RESPONSE_FORMAT = {
    "type": "json_schema",
    "json_schema": {
        "name": "sgv7_semantic_critic_v1",
        "strict": True,
        "schema": _CRITIC_BACKEND_SCHEMA,
    },
}


_JSON_FENCE_RE = re.compile(r"```(?:json)?\s*([\s\S]*?)\s*```", flags=re.IGNORECASE)
_COMPAT_LOG_LOCK = threading.Lock()
_COMPAT_LOG_PRINTED = False
_TLS = threading.local()


def _artifact_id(sample_id: str) -> str:
    return f"critic-{sample_id}-v1"


def _execution_payload(request: ValidationRequest, *, recomputed: bool) -> dict[str, object]:
    return {
        "temperature": request.critic_temperature,
        "top_p": request.critic_top_p,
        "max_output_tokens": request.critic_max_output_tokens,
        "recomputed": recomputed,
    }


def _validated_payload(payload: Any, *, schema: dict[str, object], context: str) -> dict[str, object]:
    if not isinstance(payload, dict):
        raise SemanticCriticError(f"{context} must be a JSON object")
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda item: list(item.path))
    if errors:
        error = errors[0]
        path = ".".join(str(part) for part in error.absolute_path) or "<root>"
        raise SemanticCriticError(f"{context} schema violation at {path}: {error.message}")
    return payload


def _decode_critic_payload(content: str, *, allow_salvage: bool) -> dict[str, object]:
    candidates: list[str] = []
    stripped = content.strip()
    if stripped:
        candidates.append(stripped)
    if allow_salvage:
        fenced = _JSON_FENCE_RE.findall(content)
        candidates.extend(chunk.strip() for chunk in fenced if chunk and chunk.strip())
        first_open = content.find("{")
        last_close = content.rfind("}")
        if first_open != -1 and last_close != -1 and last_close > first_open:
            candidates.append(content[first_open:last_close + 1].strip())

    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        try:
            payload = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            return payload
    raise SemanticCriticError("Critic backend returned non-JSON content")


def _map_failure_code(raw: str) -> str | None:
    value = raw.strip()
    if not value:
        return None
    if value in REJECT_CODES:
        return value
    low = value.lower()

    mappings: list[tuple[tuple[str, ...], str]] = [
        (("beat_count", "chronology", "схлопнул", "collapse", "beat"), "semantic_beat_collapse"),
        (("marked", "grounding", "объект", "object_grounding", "put_down_target"), "semantic_marked_object_lost"),
        (("ordinal", "перв", "втор", "трет"), "semantic_ordinal_anchor_lost"),
        (("unsupported", "described_action", "не поддерж", "must_keep_lemmas"), "semantic_unsupported_action_lost"),
        (("same_type", "disambiguation", "различ", "cue"), "semantic_same_type_disambiguation_lost"),
        (("invented dialogue", "придуман", "dialogue"), "semantic_invented_dialogue"),
        (("invented object", "лишний объект", "extra object"), "semantic_invented_object"),
        (("invented action", "лишнее действие", "extra action"), "semantic_invented_action"),
        (("exact marker", "marker_id", "id conflict"), "semantic_exact_marker_id_conflict"),
        (("recoverability", "borderline", "погранич"), "recoverability_borderline"),
        (("overcompressed", "сжат", "compression"), "recoverability_overcompressed"),
        (("too low", "низк", "low"), "recoverability_too_low"),
    ]
    for needles, mapped in mappings:
        if any(needle in low for needle in needles):
            return mapped
    return None


def _normalize_compat_payload(payload: dict[str, object]) -> dict[str, object]:
    normalized = dict(payload)

    # Some compatible endpoints occasionally emit a misspelled key `foundings`.
    if (
        ("findings" not in normalized or normalized.get("findings") in (None, "", []))
        and "foundings" in normalized
    ):
        normalized["findings"] = normalized.get("foundings")

    verdict = str(normalized.get("verdict", "")).strip().lower()
    if verdict not in {"pass", "soft_fail", "hard_fail"}:
        if "hard" in verdict:
            verdict = "hard_fail"
        elif "soft" in verdict:
            verdict = "soft_fail"
        else:
            verdict = "pass"
    normalized["verdict"] = verdict

    try:
        confidence = float(normalized.get("confidence", 0.5))
    except (TypeError, ValueError):
        confidence = 0.5
    normalized["confidence"] = max(0.0, min(1.0, confidence))

    findings = normalized.get("findings", [])
    if not isinstance(findings, list):
        findings = [str(findings)]
    normalized["findings"] = [str(item) for item in findings]

    raw_failures = normalized.get("detected_failures", [])
    if not isinstance(raw_failures, list):
        raw_failures = [raw_failures]
    mapped_failures: list[str] = []
    for item in raw_failures:
        mapped = _map_failure_code(str(item))
        if mapped and mapped not in mapped_failures:
            mapped_failures.append(mapped)
    normalized["detected_failures"] = mapped_failures

    def _normalize_boolish(value: object, *, default: bool) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return value != 0
        if value is None:
            return default
        text = str(value).strip().lower()
        if text in {"true", "1", "yes", "y", "да", "ok", "pass", "passed", "preserved", "fully", "complete"}:
            return True
        if text in {
            "false",
            "0",
            "no",
            "n",
            "нет",
            "uncertain",
            "unknown",
            "partial",
            "partially",
            "soft",
            "soft-fail",
            "soft_fail",
            "likely",
            "probably",
            "maybe",
            "n/a",
            "na",
            "none",
            "",
        }:
            return False
        return default

    default_preserved = (verdict == "pass")
    normalized["chronology_preserved"] = _normalize_boolish(
        normalized.get("chronology_preserved"),
        default=default_preserved,
    )
    normalized["object_grounding_preserved"] = _normalize_boolish(
        normalized.get("object_grounding_preserved"),
        default=default_preserved,
    )
    normalized["ordinal_binding_preserved"] = _normalize_boolish(
        normalized.get("ordinal_binding_preserved"),
        default=default_preserved,
    )
    normalized["unsupported_action_preserved"] = _normalize_boolish(
        normalized.get("unsupported_action_preserved"),
        default=default_preserved,
    )
    normalized["invented_content_present"] = _normalize_boolish(
        normalized.get("invented_content_present"),
        default=False,
    )

    if normalized.get("summary") is None:
        normalized["summary"] = ""
    normalized["summary"] = str(normalized.get("summary", ""))

    # Drop unknown keys from compatibility payloads before strict schema validation.
    cleaned: dict[str, object] = {}
    for key in _CRITIC_BASE_PROPERTIES:
        cleaned[key] = normalized.get(key)
    return cleaned


def _log_critic_raw_response(*, sample_id: object, reason: str, raw_content: str) -> None:
    enabled_raw = (os.environ.get("SGV7_LOG_CRITIC_RAW_RESPONSE", "1").strip().lower() in {"1", "true", "yes", "on"})
    if not enabled_raw:
        return
    max_chars_raw = (os.environ.get("SGV7_CRITIC_RAW_MAX_CHARS", "3000").strip() or "3000")
    try:
        max_chars = max(256, int(max_chars_raw))
    except ValueError:
        max_chars = 3000
    content = raw_content.strip()
    if len(content) > max_chars:
        content = content[:max_chars] + f"\n... [truncated, total_chars={len(raw_content)}]"
    with _COMPAT_LOG_LOCK:
        print(
            f"[critic][raw] sample_id={sample_id} reason={reason}\n"
            f"[critic][raw] --- begin ---\n{content}\n[critic][raw] --- end ---",
            flush=True,
        )


def _from_payload(payload: dict[str, object]) -> CriticResult:
    payload = _validated_payload(payload, schema=_CRITIC_RESULT_SCHEMA, context="Critic payload")
    return CriticResult(
        verdict=str(payload["verdict"]),  # type: ignore[arg-type]
        confidence=float(payload["confidence"]),
        findings=tuple(str(item) for item in payload["findings"]),
        detected_failures=tuple(str(item) for item in payload["detected_failures"]),
        chronology_preserved=bool(payload["chronology_preserved"]),
        object_grounding_preserved=bool(payload["object_grounding_preserved"]),
        ordinal_binding_preserved=bool(payload["ordinal_binding_preserved"]),
        unsupported_action_preserved=bool(payload["unsupported_action_preserved"]),
        invented_content_present=bool(payload["invented_content_present"]),
        summary=str(payload["summary"]),
        artifact_id=str(payload["artifact_id"]),
        execution=dict(payload["execution"]),
    )


def _persisted_critic_result(sample: dict[str, object], request: ValidationRequest) -> CriticResult | None:
    report = sample.get("validation_report")
    if not isinstance(report, dict):
        return None
    critic_keys = {
        "critic_artifact_id",
        "critic_execution",
        "critic_model",
        "critic_verdict",
        "critic_confidence",
        "critic_detected_failures",
        "critic_chronology_preserved",
        "critic_object_grounding_preserved",
        "critic_ordinal_binding_preserved",
        "critic_unsupported_action_preserved",
        "critic_invented_content_present",
        "critic_summary",
        "semantic_findings",
    }
    if not any(key in report for key in critic_keys):
        return None
    artifact_id = report.get("critic_artifact_id")
    execution = report.get("critic_execution")
    model_name = report.get("critic_model")
    verdict = report.get("critic_verdict")
    if not isinstance(artifact_id, str) or not isinstance(execution, dict) or not isinstance(model_name, str):
        raise SemanticCriticError("Persisted critic artifact is incomplete")
    expected_execution = _execution_payload(request, recomputed=False)
    if model_name != request.critic_model:
        raise SemanticCriticError("Persisted critic artifact model does not match the current validation request")
    if execution != expected_execution:
        raise SemanticCriticError("Persisted critic artifact execution does not match the current validation request")
    if not isinstance(verdict, str):
        raise SemanticCriticError("Persisted critic artifact is missing verdict")
    return _from_payload(
        {
            "artifact_id": artifact_id,
            "execution": expected_execution,
            "verdict": verdict,
            "confidence": report.get("critic_confidence", 1.0),
            "findings": report.get("semantic_findings", []),
            "detected_failures": report.get("critic_detected_failures", []),
            "chronology_preserved": report.get("critic_chronology_preserved", False),
            "object_grounding_preserved": report.get("critic_object_grounding_preserved", False),
            "ordinal_binding_preserved": report.get("critic_ordinal_binding_preserved", False),
            "unsupported_action_preserved": report.get("critic_unsupported_action_preserved", False),
            "invented_content_present": report.get("critic_invented_content_present", False),
            "summary": report.get("critic_summary", ""),
        }
    )


class HeuristicCritic:
    def __init__(self, *, request: ValidationRequest) -> None:
        self.request = request

    def evaluate(self, *, sample: dict[str, object], cir_record: dict[str, object], prompt_payload: dict[str, object]) -> CriticResult:
        source_text = str(sample.get("source_text", "")).lower()
        graph_constraints = sample.get("graph_constraints", {})
        failures: list[str] = []
        findings: list[str] = []

        required_aliases = {
            alias.lower()
            for obj in graph_constraints.get("marked_objects", [])
            if isinstance(obj, dict)
            for alias in obj.get("allowed_aliases", [])
            if isinstance(alias, str)
        }
        object_grounding_preserved = not required_aliases or any(alias in source_text for alias in required_aliases)
        if not object_grounding_preserved:
            failures.append("semantic_marked_object_lost")
            findings.append("Потерялось surface-grounding упоминание marked object.")

        required_ordinals = prompt_payload.get("required_ordinal_tokens", ())
        ordinal_binding_preserved = not required_ordinals or all(token.lower() in source_text for token in required_ordinals)
        if not ordinal_binding_preserved:
            failures.append("semantic_ordinal_anchor_lost")
            findings.append("Не сохранились required ordinal anchors.")

        critical_lemmas = [str(item).lower() for item in graph_constraints.get("must_keep_lemmas", [])]
        unsupported_action_preserved = not critical_lemmas or all(lemma in source_text for lemma in critical_lemmas)
        if not unsupported_action_preserved:
            failures.append("semantic_unsupported_action_lost")
            findings.append("Не сохранился critical unsupported action.")

        chronology_preserved = deterministic_chronology_cue_passed(sample, cir_record) and not deterministic_beat_collapse(
            cir_record,
            sample,
        )
        if not chronology_preserved:
            if deterministic_beat_collapse(cir_record, sample):
                failures.append("semantic_beat_collapse")
                findings.append("Сцена схлопнулась по chronology/beats.")
            else:
                failures.append("recoverability_borderline")
                findings.append("Chronology выглядит пограничной для recoverability.")

        has_talk = any(
            action.get("type") == "talk"
            for beat in cir_record.get("scene_graph", {}).get("beats", [])
            for action in beat.get("actions", [])
        )
        invented_content_present = not has_talk and ":" in source_text
        if invented_content_present:
            failures.append("semantic_invented_dialogue")
            findings.append("Появился invented dialogue.")

        same_type_conflict = bool(graph_constraints.get("same_type_marker_conflict"))
        if same_type_conflict:
            cues = {str(item).lower() for item in graph_constraints.get("required_disambiguation_cues", []) if isinstance(item, str)}
            if cues and not any(cue in source_text for cue in cues):
                failures.append("semantic_same_type_disambiguation_lost")
                findings.append("Не сохранился distinguishing cue для same-type markers.")

        hard_failures = {
            "semantic_marked_object_lost",
            "semantic_ordinal_anchor_lost",
            "semantic_unsupported_action_lost",
            "semantic_beat_collapse",
            "semantic_invented_dialogue",
            "semantic_same_type_disambiguation_lost",
            "semantic_exact_marker_id_conflict",
        }
        if hard_failures & set(failures):
            verdict = "hard_fail"
            confidence = 0.98
        elif failures:
            verdict = "soft_fail"
            confidence = 0.75
        else:
            verdict = "pass"
            confidence = 0.99
            findings.append("Critical semantics preserved.")

        return CriticResult(
            verdict=verdict,
            confidence=confidence,
            findings=tuple(findings),
            detected_failures=tuple(failures),
            chronology_preserved=chronology_preserved,
            object_grounding_preserved=object_grounding_preserved,
            ordinal_binding_preserved=ordinal_binding_preserved,
            unsupported_action_preserved=unsupported_action_preserved,
            invented_content_present=invented_content_present,
            summary=findings[0] if findings else "No issues detected.",
            artifact_id=_artifact_id(str(sample["sample_id"])),
            execution=_execution_payload(self.request, recomputed=False),
        )


class OpenAICritic:
    def __init__(self, *, request: ValidationRequest) -> None:
        self.request = request
        self._disable_response_format = (os.environ.get("SGV7_DISABLE_RESPONSE_FORMAT", "").strip().lower() in {"1", "true", "yes", "on"})
        try:
            from openai import OpenAI
        except ImportError as exc:
            raise SemanticCriticError("openai package is required for critic_backend=openai") from exc

        kwargs: dict[str, object] = {}
        api_key = (os.environ.get("OPENAI_API_KEY") or "").strip()
        if api_key:
            kwargs["api_key"] = api_key
        base_url = (os.environ.get("OPENAI_BASE_URL") or "").strip()
        if base_url:
            kwargs["base_url"] = base_url
        timeout_raw = (os.environ.get("SGV7_OPENAI_TIMEOUT_SECONDS") or "").strip()
        if timeout_raw:
            try:
                kwargs["timeout"] = float(timeout_raw)
            except ValueError as exc:
                raise SemanticCriticError(
                    f"SGV7_OPENAI_TIMEOUT_SECONDS must be numeric, got: {timeout_raw!r}"
                ) from exc
        else:
            kwargs["timeout"] = 60.0
        try:
            self._client = OpenAI(**kwargs)
        except Exception as exc:  # pragma: no cover - depends on local env configuration
            raise SemanticCriticError(f"OpenAI critic client init failed: {type(exc).__name__}: {exc}") from exc
        if self._disable_response_format:
            global _COMPAT_LOG_PRINTED
            with _COMPAT_LOG_LOCK:
                if not _COMPAT_LOG_PRINTED:
                    print(
                        "[critic] compatibility mode enabled: SGV7_DISABLE_RESPONSE_FORMAT=1 (json_schema response_format disabled)",
                        flush=True,
                    )
                    _COMPAT_LOG_PRINTED = True

    def evaluate(self, *, sample: dict[str, object], cir_record: dict[str, object], prompt_payload: dict[str, object]) -> CriticResult:
        system_prompt = CRITIC_SYSTEM_PROMPT
        if self._disable_response_format:
            system_prompt += (
                "\nТвой ответ ДОЛЖЕН быть одним JSON-объектом без markdown и комментариев. "
                "Ключи обязательны: verdict, confidence, findings, detected_failures, chronology_preserved, "
                "object_grounding_preserved, ordinal_binding_preserved, unsupported_action_preserved, "
                "invented_content_present, summary."
            )
        base_messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": build_critic_user_prompt(sample, cir_record)},
        ]
        request_kwargs: dict[str, object] = {
            "model": self.request.critic_model,
            "temperature": self.request.critic_temperature,
            "top_p": self.request.critic_top_p,
            "max_tokens": self.request.critic_max_output_tokens,
            "messages": base_messages,
        }
        if not self._disable_response_format:
            request_kwargs["response_format"] = _OPENAI_RESPONSE_FORMAT

        last_error: SemanticCriticError | None = None
        last_content = ""
        for attempt in (1, 2):
            attempt_kwargs = dict(request_kwargs)
            if attempt == 2 and self._disable_response_format:
                retry_messages = list(base_messages)
                retry_messages[0] = {
                    "role": "system",
                    "content": system_prompt
                    + "\nСЕЙЧАС СТРОГО: один компактный JSON-объект без переносов и markdown. "
                    "detected_failures: только коды из таксономии. findings: максимум 2 короткие строки. "
                    "summary: максимум 120 символов.",
                }
                attempt_kwargs["messages"] = retry_messages
                attempt_kwargs["max_tokens"] = max(
                    self.request.critic_max_output_tokens,
                    int(os.environ.get("SGV7_COMPAT_RETRY_MAX_TOKENS", "1200") or "1200"),
                )
                print(
                    f"[critic] retry attempt=2 sample_id={sample.get('sample_id')} after parse/schema failure",
                    flush=True,
                )

            try:
                response = self._client.chat.completions.create(**attempt_kwargs)
            except Exception as exc:  # pragma: no cover - backend errors depend on runtime/network
                last_error = SemanticCriticError(f"OpenAI critic request failed: {type(exc).__name__}: {exc}")
                break

            finish_reason = str(response.choices[0].finish_reason or "")
            content = (response.choices[0].message.content or "").strip()
            last_content = content
            try:
                payload = _decode_critic_payload(content, allow_salvage=self._disable_response_format)
                if self._disable_response_format:
                    payload = _normalize_compat_payload(payload)
                payload = _validated_payload(payload, schema=_CRITIC_BACKEND_SCHEMA, context="OpenAI critic response")
            except SemanticCriticError as exc:
                reason = str(exc)
                if finish_reason:
                    reason = f"{reason}; finish_reason={finish_reason}"
                _log_critic_raw_response(
                    sample_id=sample.get("sample_id"),
                    reason=reason,
                    raw_content=content or "<empty-response>",
                )
                last_error = SemanticCriticError(reason)
                if attempt == 1 and self._disable_response_format:
                    continue
                break

            payload["artifact_id"] = _artifact_id(str(sample["sample_id"]))
            payload["execution"] = _execution_payload(self.request, recomputed=False)
            return _from_payload(payload)

        if last_error is not None:
            raise last_error
        raise SemanticCriticError(
            f"OpenAI critic request failed with empty response for sample_id={sample.get('sample_id')}: {last_content[:120]}"
        )


def _default_backend(request: ValidationRequest) -> CriticBackend:
    if request.critic_backend == "openai":
        cache = getattr(_TLS, "backend_cache", None)
        if cache is None:
            cache = {}
            _TLS.backend_cache = cache
        key = ("openai", request.critic_model, request.critic_temperature, request.critic_top_p, request.critic_max_output_tokens)
        cached = cache.get(key)
        if cached is None:
            cached = OpenAICritic(request=request)
            cache[key] = cached
        return cached
    return HeuristicCritic(request=request)


def run_semantic_critic(
    sample: dict[str, object],
    request: ValidationRequest,
    *,
    cir_record: dict[str, object],
    backend: CriticBackend | None = None,
) -> CriticResult:
    persisted = _persisted_critic_result(sample, request)
    if persisted is not None:
        return persisted
    if not request.enable_critic:
        raise SemanticCriticError("Critic is disabled and no persisted critic artifact is available")
    try:
        payload = build_prompt_payload(sample, cir_record)
        selected_backend = backend or _default_backend(request)
        result = selected_backend.evaluate(sample=sample, cir_record=cir_record, prompt_payload=payload)
    except SemanticCriticError as exc:
        if request.critic_backend == "openai":
            # Fail-open to deterministic local critic instead of rejecting the sample
            # due to backend response formatting/transient API issues.
            print(
                f"[critic] OpenAI fallback -> heuristic for sample_id={sample.get('sample_id')}: {exc}",
                flush=True,
            )
            result = HeuristicCritic(request=request).evaluate(
                sample=sample,
                cir_record=cir_record,
                prompt_payload=payload,
            )
        else:
            raise
    if result.execution != _execution_payload(request, recomputed=False):
        raise SemanticCriticError("Critic backend returned mismatched execution payload")
    return result
