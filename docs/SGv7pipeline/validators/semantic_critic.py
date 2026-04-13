from __future__ import annotations

import json
import os
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
        try:
            from openai import OpenAI
        except ImportError as exc:
            raise SemanticCriticError("openai package is required for critic_backend=openai") from exc

        kwargs: dict[str, object] = {}
        api_key = os.environ.get("OPENAI_API_KEY")
        if api_key:
            kwargs["api_key"] = api_key
        base_url = os.environ.get("OPENAI_BASE_URL")
        if base_url:
            kwargs["base_url"] = base_url
        self._client = OpenAI(**kwargs)

    def evaluate(self, *, sample: dict[str, object], cir_record: dict[str, object], prompt_payload: dict[str, object]) -> CriticResult:
        response = self._client.chat.completions.create(
            model=self.request.critic_model,
            temperature=self.request.critic_temperature,
            top_p=self.request.critic_top_p,
            max_tokens=self.request.critic_max_output_tokens,
            response_format=_OPENAI_RESPONSE_FORMAT,
            messages=[
                {"role": "system", "content": CRITIC_SYSTEM_PROMPT},
                {"role": "user", "content": build_critic_user_prompt(sample, cir_record)},
            ],
        )
        content = (response.choices[0].message.content or "").strip()
        try:
            payload = json.loads(content)
        except json.JSONDecodeError as exc:
            raise SemanticCriticError("Critic backend returned non-JSON content") from exc
        payload = _validated_payload(payload, schema=_CRITIC_BACKEND_SCHEMA, context="OpenAI critic response")
        payload["artifact_id"] = _artifact_id(str(sample["sample_id"]))
        payload["execution"] = _execution_payload(self.request, recomputed=False)
        return _from_payload(payload)


def _default_backend(request: ValidationRequest) -> CriticBackend:
    if request.critic_backend == "openai":
        return OpenAICritic(request=request)
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
    payload = build_prompt_payload(sample, cir_record)
    backend = backend or _default_backend(request)
    result = backend.evaluate(sample=sample, cir_record=cir_record, prompt_payload=payload)
    if result.execution != _execution_payload(request, recomputed=False):
        raise SemanticCriticError("Critic backend returned mismatched execution payload")
    return result
