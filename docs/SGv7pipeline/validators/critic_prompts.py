from __future__ import annotations

from source_generation.prompt_builder import extract_required_surface_anchors, summarize_graph_for_source_prompt


CRITIC_SYSTEM_PROMPT = "\n".join(
    [
        "Ты semantic critic для SG v7 dataset pipeline.",
        "Ты не переписываешь текст и не предлагаешь улучшения.",
        "Ты сравниваешь candidate source text с canonical graph constraints и отвечаешь только структурированным verdict.",
        "Считай hard-fail, если потеряны marked object grounding, recoverability-critical ordinal binding, chronology beats, unsupported action semantics или появились придуманные сущности.",
        "Считай soft-fail, если смысл в целом похож, но recoverability для qwen 1.5B стала сомнительной.",
        "Верни только JSON.",
    ]
)


def build_prompt_payload(sample: dict[str, object], cir_record: dict[str, object]) -> dict[str, object]:
    summary = summarize_graph_for_source_prompt(cir_record)
    anchors = extract_required_surface_anchors(cir_record)
    return {
        "source_text": str(sample.get("source_text", "")),
        "graph_summary": str(summary["graph_summary"]),
        "must_have_semantics": list(summary["must_keep_semantics"]),
        "must_not_have_semantics": list(summary["must_not_introduce"]),
        "marked_objects": sample.get("graph_constraints", {}).get("marked_objects", []),
        "ordinal_bindings": sample.get("graph_constraints", {}).get("ordinal_bindings", {}),
        "critical_lemmas": sample.get("graph_constraints", {}).get("must_keep_lemmas", []),
        "beat_outline": str(summary["beat_outline"]),
        "required_aliases": anchors["required_aliases"],
        "required_ordinal_tokens": anchors["required_ordinal_tokens"],
        "required_disambiguation_cues": anchors["required_disambiguation_cues"],
    }


def build_critic_user_prompt(sample: dict[str, object], cir_record: dict[str, object]) -> str:
    payload = build_prompt_payload(sample, cir_record)
    return "\n".join(
        [
            "Проверь candidate source text против canonical constraints.",
            "",
            "SOURCE_TEXT:",
            str(payload["source_text"]),
            "",
            "GRAPH_SUMMARY:",
            str(payload["graph_summary"]),
            "",
            "MUST_HAVE_SEMANTICS:",
            "\n".join(f"- {item}" for item in payload["must_have_semantics"]) or "- none",
            "",
            "MUST_NOT_HAVE_SEMANTICS:",
            "\n".join(f"- {item}" for item in payload["must_not_have_semantics"]) or "- none",
            "",
            "MARKED_OBJECTS:",
            str(payload["marked_objects"]),
            "",
            "ORDINAL_BINDINGS:",
            str(payload["ordinal_bindings"]),
            "",
            "CRITICAL_LEMMAS:",
            str(payload["critical_lemmas"]),
        ]
    )
