from __future__ import annotations

from collections import Counter
from typing import Any

from cir_contract.contracts.cir_types import CIRRecord, ObjectNode

from .config import StyleBucket, VariantPlanItem
from .style_policy import STYLE_RULES


_EXACT_TRANSLATIONS = {
    "laptop": "ноутбук",
    "notebook": "ноутбук",
    "pc": "комп",
    "workstation": "рабочий компьютер",
    "left chair": "левый стул",
    "right chair": "правый стул",
    "that chair": "тот стул",
    "chair": "стул",
    "left table": "левый стол",
    "right table": "правый стол",
    "that table": "тот стол",
    "table": "стол",
    "door": "дверь",
    "cabinet": "шкаф",
    "tv": "телевизор",
    "anna": "Анна",
    "boris": "Борис",
    "lena": "Лена",
    "max": "Макс",
    "nina": "Нина",
    "oleg": "Олег",
}

_DESCRIBED_ACTION_TRANSLATIONS = {
    "starts smoking": "начинает курить",
    "smoke": "курить",
}

_DIALOGUE_TRANSLATIONS = {
    "I already sent the letter.": "Я уже отправила письмо.",
    "Then show me the attachment.": "Тогда покажи вложение.",
    "I already sent the file.": "Я уже отправила файл.",
    "Then show me the app.": "Тогда покажи приложение.",
}

_COLLOQUIAL_PREFERENCES = ("комп", "ноут", "телик", "компа")

_LEFT_FORMS = ("левый", "левого", "левому", "левом")
_RIGHT_FORMS = ("правый", "правого", "правому", "правом")

_NOUN_CASES = {
    "стул": ("стул", "стула", "стулу", "стулом"),
    "стол": ("стол", "стола", "столу", "столом"),
    "ноутбук": ("ноутбук", "ноутбука", "ноутбуку", "ноутбуком"),
    "комп": ("комп", "компа", "компу", "компом"),
    "компьютер": ("компьютер", "компьютера", "компьютеру", "компьютером"),
    "дверь": ("дверь", "двери", "двери", "дверью"),
    "шкаф": ("шкаф", "шкафа", "шкафу", "шкафом"),
    "телевизор": ("телевизор", "телевизора", "телевизору", "телевизором"),
}


def localize_surface(text: str) -> str:
    lowered = text.strip().lower()
    if lowered in _EXACT_TRANSLATIONS:
        return _EXACT_TRANSLATIONS[lowered]
    return text.strip()


def expand_surface_forms(text: str) -> list[str]:
    normalized = localize_surface(text).strip().lower()
    forms = {normalized}
    if not normalized:
        return []

    if normalized in _NOUN_CASES:
        forms.update(_NOUN_CASES[normalized])

    if normalized.startswith("левый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            noun_forms = _NOUN_CASES[noun]
            forms.add(f"левый {noun_forms[0]}")
            forms.add(f"левого {noun_forms[1]}")
            forms.add(f"левому {noun_forms[2]}")
    if normalized.startswith("правый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            noun_forms = _NOUN_CASES[noun]
            forms.add(f"правый {noun_forms[0]}")
            forms.add(f"правого {noun_forms[1]}")
            forms.add(f"правому {noun_forms[2]}")
    if normalized.startswith("тот "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            noun_forms = _NOUN_CASES[noun]
            forms.add(f"тот {noun_forms[0]}")
            forms.add(f"того {noun_forms[1]}")

    return sorted(forms)


def _metadata(record: CIRRecord) -> dict[str, object]:
    return dict(record.get("internal_metadata", {}))


def _canonical_source_template(record: CIRRecord) -> str:
    template = _metadata(record).get("canonical_source_template")
    if isinstance(template, str) and template.strip():
        return template.strip()
    return _fallback_canonical_source_template(record)


def _required_semantics(record: CIRRecord) -> list[str]:
    values = _metadata(record).get("required_semantics", [])
    if not isinstance(values, list):
        return []
    return [str(item) for item in values]


def _forbidden_collapses(record: CIRRecord) -> list[str]:
    values = _metadata(record).get("forbidden_collapses", [])
    if not isinstance(values, list):
        return []
    return [str(item) for item in values]


def _beat_summary(beat: dict[str, Any], record: CIRRecord) -> str:
    phase = beat.get("phase", "single_action")
    actions = beat.get("actions", [])
    bindings = record["scene_graph"]["reference_bindings"]["alias_to_object_id"]
    object_name_by_id = {}
    for obj in record["scene_graph"]["objects"]:
        localized_names = localized_object_aliases(obj)
        object_name_by_id[obj["id"]] = localized_names[0] if localized_names else obj["id"]

    if phase == "toward_each_other":
        return "actors move toward each other"
    if phase == "stop_near_object":
        target_id = next((action.get("target_id") for action in actions if action.get("target_id")), None)
        if target_id:
            return f"actors stop near {target_id} ({object_name_by_id.get(target_id, target_id)})"
        return "actors stop near the marked object"
    if phase == "pass_by_object":
        target_id = next((action.get("target_id") for action in actions if action.get("target_id")), None)
        if target_id:
            return f"actors pass by {target_id} ({object_name_by_id.get(target_id, target_id)})"
        return "actors pass by the marked object"
    if phase == "approach_object":
        first_action = actions[0] if actions else {}
        target_id = first_action.get("target_id")
        actor_id = first_action.get("actor_id", "actor_1")
        if target_id:
            return f"{actor_id} approaches {target_id} ({object_name_by_id.get(target_id, target_id)})"
    for action in actions:
        if action.get("type") == "described_action":
            payload = action.get("described_action", {})
            canonical = localize_described_action(str(payload.get("canonical_text", "described action")))
            return f"{action['actor_id']} performs described_action: {canonical}"
        if action.get("type") == "run":
            return f"{action['actor_id']} starts running"
        if action.get("type") == "talk":
            dialogue = action.get("dialogue", "")
            return f"{action['actor_id']} says: {dialogue}"
    return phase.replace("_", " ")


def localize_described_action(text: str) -> str:
    lowered = text.strip().lower()
    if lowered in _DESCRIBED_ACTION_TRANSLATIONS:
        return _DESCRIBED_ACTION_TRANSLATIONS[lowered]
    return text.strip()


def localize_dialogue(text: str) -> str:
    normalized = text.strip()
    if normalized in _DIALOGUE_TRANSLATIONS:
        return _DIALOGUE_TRANSLATIONS[normalized]
    return normalized


def localized_object_aliases(obj: ObjectNode) -> list[str]:
    aliases: list[str] = []
    name = obj.get("name")
    if isinstance(name, str) and name.strip():
        aliases.append(localize_surface(name))
    binding = obj.get("marker_binding", {})
    source_name = binding.get("source_name")
    if isinstance(source_name, str) and source_name.strip():
        aliases.append(localize_surface(source_name))
    for alias in binding.get("mentioned_aliases", []):
        if isinstance(alias, str) and alias.strip():
            aliases.append(localize_surface(alias))

    deduped: list[str] = []
    seen: set[str] = set()
    for alias in aliases:
        key = alias.lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(alias)
    return deduped


def _preferred_alias(obj: ObjectNode, *, style_bucket: StyleBucket) -> str:
    aliases = localized_object_aliases(obj)
    if not aliases:
        return obj["id"]
    if style_bucket == "colloquial":
        for alias in aliases:
            if alias.lower() in _COLLOQUIAL_PREFERENCES:
                return alias
    for alias in aliases:
        if alias.lower() not in _COLLOQUIAL_PREFERENCES:
            return alias
    return aliases[0]


def _target_marked_object_id(record: CIRRecord) -> str | None:
    for item in record["scene_graph"].get("must_preserve", []):
        if isinstance(item, str) and item.startswith("must_ground_object:"):
            return item.split(":", 1)[1]
    marked_ids = record["scene_graph"]["reference_bindings"].get("marked_object_ids", [])
    return marked_ids[0] if marked_ids else None


def _object_by_id(record: CIRRecord, object_id: str) -> ObjectNode | None:
    for obj in record["scene_graph"]["objects"]:
        if obj["id"] == object_id:
            return obj
    return None


def _best_object_noun(obj: ObjectNode) -> str:
    aliases = localized_object_aliases(obj)
    if not aliases:
        return obj["id"]
    for alias in aliases:
        lowered = alias.lower()
        if lowered in _NOUN_CASES or lowered.startswith(("левый ", "правый ", "тот ")):
            return alias.lower()
    return aliases[0].lower()


def _to_object_case(surface: str, case: str) -> str:
    normalized = surface.lower()
    if normalized.startswith("левый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            if case == "genitive":
                return f"левого {_NOUN_CASES[noun][1]}"
            if case == "dative":
                return f"левому {_NOUN_CASES[noun][2]}"
        return normalized
    if normalized.startswith("правый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            if case == "genitive":
                return f"правого {_NOUN_CASES[noun][1]}"
            if case == "dative":
                return f"правому {_NOUN_CASES[noun][2]}"
        return normalized
    if normalized in _NOUN_CASES:
        index = 1 if case == "genitive" else 2
        return _NOUN_CASES[normalized][index]
    return normalized


def _ordinal_ru(actor_id: str, *, capitalized: bool = False) -> str:
    mapping = {
        "actor_1": "первый",
        "actor_2": "второй",
        "actor_3": "третий",
    }
    token = mapping.get(actor_id, actor_id)
    return token.capitalize() if capitalized else token


def _ordinal_tokens(record: CIRRecord) -> list[str]:
    ordinal_map = record["scene_graph"]["reference_bindings"].get("ordinal_map", {})
    tokens = []
    for token in ("first", "second", "third"):
        if token in ordinal_map:
            tokens.append({"first": "первый", "second": "второй", "third": "третий"}[token])
    return tokens


def _conditional_required_ordinal_tokens(record: CIRRecord) -> list[str]:
    must_preserve = [item for item in record["scene_graph"].get("must_preserve", []) if isinstance(item, str)]
    ordinal_map = record["scene_graph"]["reference_bindings"].get("ordinal_map", {})
    actor_names = {
        actor["id"]: actor.get("name")
        for actor in record["scene_graph"]["actors"]
        if isinstance(actor.get("name"), str) and actor.get("name")
    }

    required: set[str] = set()
    explicit_map = {
        "ordinal:first->actor_1": "первый",
        "ordinal:second->actor_2": "второй",
        "ordinal:third->actor_3": "третий",
    }
    for item in must_preserve:
        if item in explicit_map:
            required.add(explicit_map[item])

    if record["pattern_name"].startswith("ordinal_"):
        required.update(_ordinal_tokens(record))

    actor_based_hints = {
        "actor_1": "первый",
        "actor_2": "второй",
        "actor_3": "третий",
    }
    for actor_id, token in actor_based_hints.items():
        if actor_id not in ordinal_map.values():
            continue
        if actor_id in actor_names:
            continue
        if any(actor_id in item for item in must_preserve):
            required.add(token)

    if len(record["scene_graph"]["actors"]) >= 3 and len(actor_names) < len(record["scene_graph"]["actors"]):
        required.update(_ordinal_tokens(record))

    ordered_tokens = [token for token in _ordinal_tokens(record) if token in required]
    return ordered_tokens


def _same_type_disambiguation_payload(record: CIRRecord) -> dict[str, object] | None:
    counts = Counter(obj["type"] for obj in record["scene_graph"]["objects"])
    if all(count < 2 for count in counts.values()):
        return None

    target_id = _target_marked_object_id(record)
    objects = [obj for obj in record["scene_graph"]["objects"] if counts[obj["type"]] >= 2]
    object_entries: list[dict[str, object]] = []
    for obj in objects:
        localized_aliases = localized_object_aliases(obj)
        preferred = localized_aliases[0] if localized_aliases else obj["id"]
        cues = set(expand_surface_forms(preferred))
        relative = obj.get("relative_position", "unknown")
        if relative == "left":
            noun = preferred.split(" ", 1)[-1]
            for adjective in _LEFT_FORMS:
                if noun in _NOUN_CASES:
                    noun_forms = _NOUN_CASES[noun]
                    cues.add(f"{adjective} {noun_forms[0]}")
                    cues.add(f"{adjective} {noun_forms[1]}")
                    cues.add(f"{adjective} {noun_forms[2]}")
        elif relative == "right":
            noun = preferred.split(" ", 1)[-1]
            for adjective in _RIGHT_FORMS:
                if noun in _NOUN_CASES:
                    noun_forms = _NOUN_CASES[noun]
                    cues.add(f"{adjective} {noun_forms[0]}")
                    cues.add(f"{adjective} {noun_forms[1]}")
                    cues.add(f"{adjective} {noun_forms[2]}")

        object_entries.append(
            {
                "id": obj["id"],
                "preferred_alias": preferred,
                "fallback_cues": sorted(cues),
                "is_target": obj["id"] == target_id,
            }
        )
    return {"target_object_id": target_id, "objects": object_entries}


def _fallback_canonical_source_template(record: CIRRecord) -> str:
    clauses: list[str] = []
    beats = record["scene_graph"]["beats"]
    for beat in beats:
        phase = beat.get("phase")
        actions = beat.get("actions", [])
        if phase == "toward_each_other":
            actor_count = len(record["scene_graph"]["actors"])
            clauses.append(f"{actor_count} актёра идут навстречу друг другу")
            continue
        if phase == "stop_near_object":
            target_id = next((action.get("target_id") for action in actions if action.get("target_id")), None)
            if target_id:
                obj = _object_by_id(record, target_id)
                if obj is not None:
                    clauses.append(f"останавливаются у {_to_object_case(_best_object_noun(obj), 'genitive')}")
                    continue
        if phase == "pass_by_object":
            target_id = next((action.get("target_id") for action in actions if action.get("target_id")), None)
            if target_id:
                obj = _object_by_id(record, target_id)
                if obj is not None:
                    clauses.append(f"проходят мимо {_to_object_case(_best_object_noun(obj), 'genitive')}")
                    continue
        if phase == "approach_object":
            primary = actions[0] if actions else None
            if primary and primary.get("target_id"):
                obj = _object_by_id(record, primary["target_id"])
                if obj is not None:
                    clauses.append(
                        f"{_ordinal_ru(primary['actor_id'], capitalized=True)} подходит к {_to_object_case(_best_object_noun(obj), 'dative')}"
                    )
            secondary_anchor = None
            for item in record["scene_graph"].get("must_preserve", []):
                if isinstance(item, str) and item.startswith("second_actor_anchor:"):
                    secondary_anchor = item.split(":", 1)[1]
            if secondary_anchor:
                opposite = _object_by_id(record, secondary_anchor)
                if opposite is not None:
                    clauses.append(f"второй остаётся у {_to_object_case(_best_object_noun(opposite), 'genitive')}")
            continue
        for action in actions:
            action_type = action.get("type")
            actor_id = action.get("actor_id", "actor_1")
            actor_name = next(
                (
                    actor.get("name")
                    for actor in record["scene_graph"]["actors"]
                    if actor["id"] == actor_id and isinstance(actor.get("name"), str) and actor.get("name")
                ),
                None,
            )
            actor_token = (
                localize_surface(actor_name)
                if actor_name is not None
                else _ordinal_ru(actor_id, capitalized=not clauses)
            )
            if action_type == "described_action":
                payload = action.get("described_action", {})
                clauses.append(f"{actor_token} {localize_described_action(str(payload.get('canonical_text', 'делает действие')))}")
            elif action_type == "run":
                clauses.append(f"{actor_token} начинает бежать")
            elif action_type == "talk":
                dialogue = str(action.get("dialogue", "")).strip()
                if dialogue:
                    clauses.append(f"{actor_token}: {localize_dialogue(dialogue)}")
            elif action_type == "stand" and len(record["scene_graph"]["actors"]) == 1:
                clauses.append(f"{actor_token} стоит")

    if not clauses:
        return f"Сцена по pattern {record['pattern_name']}."
    sentence = ", ".join(clauses)
    if not sentence.endswith("."):
        sentence += "."
    return sentence


def extract_required_surface_anchors(record: CIRRecord) -> dict[str, tuple[str, ...]]:
    required_aliases: set[str] = set()
    target_id = _target_marked_object_id(record)
    if target_id is not None:
        for obj in record["scene_graph"]["objects"]:
            if obj["id"] == target_id:
                for alias in localized_object_aliases(obj):
                    required_aliases.update(expand_surface_forms(alias))
                break

    for item in record["scene_graph"].get("must_preserve", []):
        if isinstance(item, str) and item.startswith("morphology_surface:"):
            surface = item.split(":", 1)[1].strip()
            if surface:
                required_aliases.add(surface.lower())

    disambiguation_payload = _same_type_disambiguation_payload(record)
    required_disambiguation_cues: set[str] = set()
    if disambiguation_payload is not None:
        for entry in disambiguation_payload["objects"]:
            if entry["is_target"]:
                required_disambiguation_cues.update(entry["fallback_cues"])

    return {
        "required_aliases": tuple(sorted(required_aliases)),
        "required_ordinal_tokens": tuple(_conditional_required_ordinal_tokens(record)),
        "required_disambiguation_cues": tuple(sorted(required_disambiguation_cues)),
    }


def summarize_graph_for_source_prompt(record: CIRRecord) -> dict[str, object]:
    beat_outline = [
        f"{index}. {_beat_summary(beat, record)}"
        for index, beat in enumerate(record["scene_graph"]["beats"], start=1)
    ]
    marked_objects = []
    for obj in record["scene_graph"]["objects"]:
        if obj["marker_binding"]["kind"] != "marked":
            continue
        aliases = localized_object_aliases(obj)
        marked_objects.append(
            {
                "id": obj["id"],
                "type": obj["type"],
                "preferred_aliases": aliases[:3],
                "surface_forms": sorted({form for alias in aliases for form in expand_surface_forms(alias)})[:6],
            }
        )

    payload = {
        "graph_summary": "\n".join(
            [
                f"pattern_name: {record['pattern_name']}",
                f"difficulty_bucket: {record['difficulty_bucket']}",
                f"semantic_tags: {', '.join(record['semantic_tags'])}",
                f"canonical_source_template_hint: {_canonical_source_template(record) or 'n/a'}",
            ]
        ),
        "beat_outline": "\n".join(beat_outline),
        "marked_object_block": marked_objects,
        "same_type_disambiguation_block": _same_type_disambiguation_payload(record),
        "must_keep_semantics": record["scene_graph"].get("must_preserve", []) + _required_semantics(record),
        "must_not_introduce": [
            "new object",
            "new beat",
            "new reason for action",
            "invented dialogue",
            *_forbidden_collapses(record),
        ],
        "ordinal_bindings": record["scene_graph"]["reference_bindings"].get("ordinal_map", {}),
        "canonical_source_template": _canonical_source_template(record),
    }
    payload.update(extract_required_surface_anchors(record))
    return payload


def _render_marked_object_block(block: list[dict[str, object]]) -> str:
    if not block:
        return "- none"
    lines: list[str] = []
    for entry in block:
        aliases = ", ".join(entry["preferred_aliases"])
        surface_forms = ", ".join(entry["surface_forms"])
        lines.extend(
            [
                f"- id: {entry['id']}",
                f"  type: {entry['type']}",
                f"  preferred_aliases: {aliases}",
                f"  allowed_surface_forms: {surface_forms}",
            ]
        )
    return "\n".join(lines)


def _render_same_type_disambiguation(block: dict[str, object] | None) -> str:
    if block is None:
        return "- none"
    lines = ["Same-type marker disambiguation:"]
    for entry in block["objects"]:
        target_suffix = " [target]" if entry["is_target"] else ""
        lines.append(f"- {entry['id']}: preferred alias \"{entry['preferred_alias']}\"{target_suffix}")
        lines.append("  fallback cues: " + ", ".join(entry["fallback_cues"][:6]))
    lines.append("- source must preserve one explicit distinguishing cue for the target object")
    return "\n".join(lines)


def _render_list(values: list[str] | tuple[str, ...]) -> str:
    if not values:
        return "- none"
    return "\n".join(f"- {value}" for value in values)


def build_source_prompt(plan_item: VariantPlanItem, previous_reject_reason: str | None = None) -> tuple[str, str]:
    payload = plan_item.prompt_payload
    system_prompt = "\n".join(
        [
            "Ты делаешь только controlled paraphrase русского пользовательского описания сцены.",
            "Ты не придумываешь новые события, объекты, роли, реплики или причины действий.",
            "Ты обязан сохранить chronology, actor bindings, ordinal references и exact grounding marked objects.",
            "Если действие не поддерживается каноническими action labels, ты не заменяешь его другим действием, а пересказываешь исходный смысл простыми словами.",
            "Верни только один русский source text без пояснений и без списка.",
        ]
    )
    user_lines = [
        f"Собери один {plan_item.style_bucket} вариант русского пользовательского описания сцены.",
        "",
        "Canonical graph summary:",
        str(payload["graph_summary"]),
        "",
        "Chronology to preserve:",
        str(payload["beat_outline"]),
        "",
        "Ordinal bindings:",
        str(payload["ordinal_bindings"]),
        "",
        "Marked objects:",
        _render_marked_object_block(payload["marked_object_block"]),
        "",
        "Same-type disambiguation:",
        _render_same_type_disambiguation(payload["same_type_disambiguation_block"]),
        "",
        "Must keep:",
        _render_list(payload["must_keep_semantics"]),
        "",
        "Must not introduce:",
        _render_list(payload["must_not_introduce"]),
        "",
        "Style rules for this bucket:",
        STYLE_RULES[plan_item.style_bucket],
        "",
        "Hard constraints:",
        "- не добавляй новые события",
        "- не добавляй новые объекты",
        "- не убирай marked object mention, если он есть в графе",
        "- не теряй слова первый/второй/третий, если ordinal binding нужен для recoverability",
        "- не схлопывай несколько beats в один расплывчатый факт",
        "- не превращай unsupported action в talk или в другое поддерживаемое действие",
        "- не пиши пояснений, списков и JSON",
        "",
        "Верни только один финальный source text на русском языке.",
    ]
    if previous_reject_reason:
        user_lines.extend(
            [
                "",
                "Предыдущий вариант был отклонён.",
                f"Причина: {previous_reject_reason}",
                "Сгенерируй новый вариант, сохранив те же semantic anchors.",
            ]
        )
    return system_prompt, "\n".join(user_lines)
