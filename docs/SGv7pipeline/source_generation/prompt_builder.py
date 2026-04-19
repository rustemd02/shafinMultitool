from __future__ import annotations

from collections import Counter
import re
from typing import Any

from cir_contract.contracts.cir_types import CIRRecord, ObjectNode

from .config import StyleBucket, VariantPlanItem
from .style_policy import STYLE_RULES


_EXACT_TRANSLATIONS = {
    "letter": "письмо",
    "key": "ключ",
    "laptop": "ноутбук",
    "notebook": "ноутбук",
    "pc": "комп",
    "workstation": "рабочий компьютер",
    "monitor": "монитор",
    "terminal": "терминал",
    "rack": "стеллаж",
    "counter": "стойка",
    "bench": "лавка",
    "kiosk": "киоск",
    "lamp": "лампа",
    "poster": "плакат",
    "sign": "табличка",
    "cart": "тележка",
    "panel": "панель",
    "screen": "экран",
    "window": "окно",
    "wall": "стена",
    "pillar": "колонна",
    "window_sill": "подоконник",
    "drawer": "ящик",
    "locker": "шкафчик",
    "box_container": "коробка",
    "case": "кейс",
    "tablet": "планшет",
    "flash_drive": "флешка",
    "badge": "бейдж",
    "phone": "телефон",
    "envelope": "конверт",
    "folder": "папка",
    "notebook_item": "блокнот",
    "box": "коробка",
    "backpack": "рюкзак",
    "cup": "кружка",
    "bag": "сумка",
    "package": "пакет",
    "paper": "лист",
    "папку": "папка",
    "кружку": "кружка",
    "сумку": "сумка",
    "коробку": "коробка",
    "флешку": "флешка",
    "стойку": "стойка",
    "лавку": "лавка",
    "лампу": "лампа",
    "табличку": "табличка",
    "тележку": "тележка",
    "полку": "полка",
    "тумбу": "тумба",
    "left chair": "левый стул",
    "right chair": "правый стул",
    "that chair": "тот стул",
    "chair": "стул",
    "left table": "левый стол",
    "right table": "правый стол",
    "near table": "ближний стол",
    "far table": "дальний стол",
    "near chair": "ближний стул",
    "far chair": "дальний стул",
    "left monitor": "левый монитор",
    "right monitor": "правый монитор",
    "near monitor": "ближний монитор",
    "far monitor": "дальний монитор",
    "left terminal": "левый терминал",
    "right terminal": "правый терминал",
    "near terminal": "ближний терминал",
    "far terminal": "дальний терминал",
    "left kiosk": "левый киоск",
    "right kiosk": "правый киоск",
    "near kiosk": "ближний киоск",
    "far kiosk": "дальний киоск",
    "left cabinet": "левый шкаф",
    "right cabinet": "правый шкаф",
    "near cabinet": "ближний шкаф",
    "far cabinet": "дальний шкаф",
    "left rack": "левый стеллаж",
    "right rack": "правый стеллаж",
    "near rack": "ближний стеллаж",
    "far rack": "дальний стеллаж",
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
    "ira": "Ира",
    "pavel": "Павел",
    "mila": "Мила",
}

_TOKEN_TRANSLATIONS = {
    "left": "левый",
    "right": "правый",
    "near": "ближний",
    "far": "дальний",
    "that": "тот",
    "letter": "письмо",
    "key": "ключ",
    "laptop": "ноутбук",
    "notebook": "ноутбук",
    "pc": "комп",
    "workstation": "рабочий компьютер",
    "monitor": "монитор",
    "terminal": "терминал",
    "rack": "стеллаж",
    "counter": "стойка",
    "bench": "лавка",
    "kiosk": "киоск",
    "lamp": "лампа",
    "poster": "плакат",
    "sign": "табличка",
    "cart": "тележка",
    "panel": "панель",
    "screen": "экран",
    "window": "окно",
    "wall": "стена",
    "pillar": "колонна",
    "door": "дверь",
    "cabinet": "шкаф",
    "tv": "телевизор",
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

_SLANGY_ALIASES = ("комп", "компа", "телик")

_LEFT_FORMS = ("левый", "левого", "левому", "левом")
_RIGHT_FORMS = ("правый", "правого", "правому", "правом")
_NEAR_FORMS = ("ближний", "ближнего", "ближнему", "ближнем")
_FAR_FORMS = ("дальний", "дальнего", "дальнему", "дальнем")
_ACTOR_ID_TOKEN_RE = re.compile(r"\bactor_[0-9]+\b", flags=re.IGNORECASE)
_MARKED_OBJECT_ID_TOKEN_RE = re.compile(r"\bobject_marked_[0-9a-z]+\b", flags=re.IGNORECASE)
_MIXED_SCRIPT_TOKEN_RE = re.compile(r"\b(?=\w*[A-Za-z])(?=\w*[А-Яа-яЁё])[A-Za-zА-Яа-яЁё]+\b")
_LATIN_LOOKALIKE_TO_CYRILLIC = str.maketrans(
    {
        "A": "А",
        "B": "В",
        "C": "С",
        "E": "Е",
        "H": "Н",
        "K": "К",
        "M": "М",
        "O": "О",
        "P": "Р",
        "T": "Т",
        "X": "Х",
        "Y": "У",
        "a": "а",
        "c": "с",
        "e": "е",
        "h": "н",
        "k": "к",
        "m": "м",
        "o": "о",
        "p": "р",
        "t": "т",
        "x": "х",
        "y": "у",
    }
)

_NOUN_CASES = {
    "стул": ("стул", "стула", "стулу", "стулом"),
    "стол": ("стол", "стола", "столу", "столом"),
    "ноутбук": ("ноутбук", "ноутбука", "ноутбуку", "ноутбуком"),
    "комп": ("комп", "компа", "компу", "компом"),
    "компьютер": ("компьютер", "компьютера", "компьютеру", "компьютером"),
    "дверь": ("дверь", "двери", "двери", "дверью"),
    "окно": ("окно", "окна", "окну", "окном"),
    "полка": ("полка", "полки", "полке", "полкой"),
    "шкаф": ("шкаф", "шкафа", "шкафу", "шкафом"),
    "тумба": ("тумба", "тумбы", "тумбе", "тумбой"),
    "шкафчик": ("шкафчик", "шкафчика", "шкафчику", "шкафчиком"),
    "телевизор": ("телевизор", "телевизора", "телевизору", "телевизором"),
    "монитор": ("монитор", "монитора", "монитору", "монитором"),
    "терминал": ("терминал", "терминала", "терминалу", "терминалом"),
    "стойка": ("стойка", "стойки", "стойке", "стойкой"),
    "лавка": ("лавка", "лавки", "лавке", "лавкой"),
    "экран": ("экран", "экрана", "экрану", "экраном"),
    "панель": ("панель", "панели", "панели", "панелью"),
    "стеллаж": ("стеллаж", "стеллажа", "стеллажу", "стеллажом"),
    "киоск": ("киоск", "киоска", "киоску", "киоском"),
    "лампа": ("лампа", "лампы", "лампе", "лампой"),
    "плакат": ("плакат", "плаката", "плакату", "плакатом"),
    "табличка": ("табличка", "таблички", "табличке", "табличкой"),
    "тележка": ("тележка", "тележки", "тележке", "тележкой"),
    "колонна": ("колонна", "колонны", "колонне", "колонной"),
    "стена": ("стена", "стены", "стене", "стеной"),
    "подоконник": ("подоконник", "подоконника", "подоконнику", "подоконником"),
    "ящик": ("ящик", "ящика", "ящику", "ящиком"),
    "кейс": ("кейс", "кейса", "кейсу", "кейсом"),
    "коробка": ("коробка", "коробки", "коробке", "коробкой"),
    "папка": ("папка", "папки", "папке", "папкой"),
    "кружка": ("кружка", "кружки", "кружке", "кружкой"),
    "сумка": ("сумка", "сумки", "сумке", "сумкой"),
    "пакет": ("пакет", "пакета", "пакету", "пакетом"),
    "лист": ("лист", "листа", "листу", "листом"),
    "планшет": ("планшет", "планшета", "планшету", "планшетом"),
    "флешка": ("флешка", "флешки", "флешке", "флешкой"),
    "бейдж": ("бейдж", "бейджа", "бейджу", "бейджем"),
    "блокнот": ("блокнот", "блокнота", "блокноту", "блокнотом"),
    "телефон": ("телефон", "телефона", "телефону", "телефоном"),
    "конверт": ("конверт", "конверта", "конверту", "конвертом"),
    "рюкзак": ("рюкзак", "рюкзака", "рюкзаку", "рюкзаком"),
}


def localize_surface(text: str) -> str:
    normalized = " ".join(
        part.translate(_LATIN_LOOKALIKE_TO_CYRILLIC) if _MIXED_SCRIPT_TOKEN_RE.search(part) else part
        for part in text.strip().split()
    )
    lowered = normalized.lower()
    if lowered in _EXACT_TRANSLATIONS:
        return _EXACT_TRANSLATIONS[lowered]
    parts = lowered.split()
    if len(parts) == 1 and lowered in _TOKEN_TRANSLATIONS:
        return _TOKEN_TRANSLATIONS[lowered]
    if len(parts) > 1:
        localized_parts = [_TOKEN_TRANSLATIONS.get(part, part) for part in parts]
        if localized_parts != parts:
            return " ".join(localized_parts)
    return normalized


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
    if normalized.startswith("ближний "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            noun_forms = _NOUN_CASES[noun]
            forms.add(f"ближний {noun_forms[0]}")
            forms.add(f"ближнего {noun_forms[1]}")
            forms.add(f"ближнему {noun_forms[2]}")
    if normalized.startswith("дальний "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            noun_forms = _NOUN_CASES[noun]
            forms.add(f"дальний {noun_forms[0]}")
            forms.add(f"дальнего {noun_forms[1]}")
            forms.add(f"дальнему {noun_forms[2]}")

    return sorted(forms)


def _metadata(record: CIRRecord) -> dict[str, object]:
    return dict(record.get("internal_metadata", {}))


def _canonical_source_template(record: CIRRecord) -> str:
    template = _metadata(record).get("canonical_source_template")
    if isinstance(template, str) and template.strip():
        return localize_surface(template.strip())
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
    object_name_by_id = {}
    for obj in record["scene_graph"]["objects"]:
        object_name_by_id[obj["id"]] = _preferred_alias(obj, style_bucket="clean")

    if phase == "toward_each_other":
        return "оба участника идут навстречу друг другу"
    if phase == "stop_near_object":
        target_id = next((action.get("target_id") for action in actions if action.get("target_id")), None)
        if target_id:
            return f"оба останавливаются у {_to_object_case(object_name_by_id.get(target_id, target_id), 'genitive')}"
        return "оба останавливаются рядом с предметом"
    if phase == "pass_by_object":
        target_id = next((action.get("target_id") for action in actions if action.get("target_id")), None)
        if target_id:
            return f"оба проходят мимо {_to_object_case(object_name_by_id.get(target_id, target_id), 'genitive')}"
        return "оба проходят мимо предмета"
    if phase == "open_object":
        action = actions[0] if actions else {}
        actor_id = str(action.get("actor_id", "actor_1"))
        target_alias = _action_object_alias(record, action)
        if target_alias:
            return (
                f"{_ordinal_ru(actor_id, capitalized=True)} открывает "
                f"{_to_object_case(target_alias, 'accusative')}"
            )
        return f"{_ordinal_ru(actor_id, capitalized=True)} открывает контейнер"
    if phase == "pickup_object":
        action = actions[0] if actions else {}
        actor_id = str(action.get("actor_id", "actor_1"))
        target_alias = _action_object_alias(record, action)
        if target_alias:
            return f"{_ordinal_ru(actor_id, capitalized=True)} берёт {_to_object_case(target_alias, 'accusative')}"
        return f"{_ordinal_ru(actor_id, capitalized=True)} берёт предмет"
    if phase == "putdown_object":
        summary = _putdown_summary(actions[0], record) if actions else None
        if summary is not None:
            return summary
        actor_id = str(actions[0].get("actor_id", "actor_1")) if actions else "actor_1"
        return f"{_ordinal_ru(actor_id, capitalized=True)} кладёт предмет"
    if phase == "give_object":
        summary = _give_summary(actions[0], record) if actions else None
        if summary is not None:
            return summary
        actor_id = str(actions[0].get("actor_id", "actor_1")) if actions else "actor_1"
        return f"{_ordinal_ru(actor_id, capitalized=True)} передаёт предмет"
    if phase == "approach_object":
        first_action = actions[0] if actions else {}
        target_id = first_action.get("target_id")
        actor_id = first_action.get("actor_id", "actor_1")
        if target_id:
            return (
                f"{_ordinal_ru(actor_id, capitalized=True)} подходит к "
                f"{_to_object_case(object_name_by_id.get(target_id, target_id), 'dative')}"
            )
    if phase == "dialogue_exchange":
        lines = [_talk_action_summary(action, record, capitalized=(idx == 0)) for idx, action in enumerate(actions[:2])]
        return " ".join(line for line in lines if line)
    if phase == "small_followup_action":
        for action in actions:
            summary = _non_dialogue_action_summary(action, record, capitalized=True)
            if summary is not None:
                return summary
        return "после разговора следует короткое действие"
    if phase in {"single_action", "first_described_action", "third_described_action"}:
        for action in actions:
            summary = _non_dialogue_action_summary(action, record, capitalized=True)
            if summary is not None:
                return summary
        return "следует отдельное действие"
    for action in actions:
        if action.get("type") == "talk":
            return _talk_action_summary(action, record, capitalized=True)
        summary = _non_dialogue_action_summary(action, record, capitalized=True)
        if summary is not None:
            return summary
    return "следующий шаг сцены"


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


def _is_prepositional_alias(alias: str) -> bool:
    lowered = alias.lower().strip()
    return lowered.startswith(("у ", "около ", "рядом с ", "мимо ", "возле "))


def _preferred_alias(obj: ObjectNode, *, style_bucket: StyleBucket) -> str:
    aliases = localized_object_aliases(obj)
    if not aliases:
        return obj["id"]
    non_prepositional = [alias for alias in aliases if not _is_prepositional_alias(alias)]
    if non_prepositional:
        aliases = non_prepositional
    if style_bucket == "colloquial":
        for alias in aliases:
            lowered = alias.lower()
            if lowered in _SLANGY_ALIASES:
                return alias
        for alias in aliases:
            if alias.lower() not in _SLANGY_ALIASES:
                return alias
    for alias in aliases:
        if alias.lower() not in _SLANGY_ALIASES:
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
        if _is_prepositional_alias(alias):
            continue
        lowered = alias.lower()
        if lowered in _NOUN_CASES or lowered.startswith(("левый ", "правый ", "тот ", "ближний ", "дальний ")):
            return alias.lower()
    for alias in aliases:
        if not _is_prepositional_alias(alias):
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
            if case == "accusative":
                return f"левый {_accusative_noun(noun)}"
        return normalized
    if normalized.startswith("правый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            if case == "genitive":
                return f"правого {_NOUN_CASES[noun][1]}"
            if case == "dative":
                return f"правому {_NOUN_CASES[noun][2]}"
            if case == "accusative":
                return f"правый {_accusative_noun(noun)}"
        return normalized
    if normalized.startswith("тот "):
        noun = normalized.split(" ", 1)[1]
        if case == "accusative":
            return f"тот {_accusative_noun(noun)}"
        return normalized
    if normalized.startswith("ближний "):
        noun = normalized.split(" ", 1)[1]
        if case == "accusative":
            return f"ближний {_accusative_noun(noun)}"
        return normalized
    if normalized.startswith("дальний "):
        noun = normalized.split(" ", 1)[1]
        if case == "accusative":
            return f"дальний {_accusative_noun(noun)}"
        return normalized
    if normalized in _NOUN_CASES:
        if case == "accusative":
            return _accusative_noun(normalized)
        index = 1 if case == "genitive" else 2
        return _NOUN_CASES[normalized][index]
    return normalized


def _accusative_noun(noun: str) -> str:
    if noun.endswith("а"):
        return noun[:-1] + "у"
    if noun.endswith("я"):
        return noun[:-1] + "ю"
    return noun


def _action_object_alias(
    record: CIRRecord,
    action: dict[str, Any],
    *,
    use_holding_object: bool = False,
    style_bucket: StyleBucket = "clean",
) -> str | None:
    key = "holding_object" if use_holding_object else "target_id"
    object_id = action.get(key)
    if not isinstance(object_id, str):
        return None
    obj = _object_by_id(record, object_id)
    if obj is None:
        return None
    return _preferred_alias(obj, style_bucket=style_bucket).lower()


def _putdown_summary(action: dict[str, Any], record: CIRRecord) -> str | None:
    held_alias = _action_object_alias(record, action, use_holding_object=True)
    target_alias = _action_object_alias(record, action)
    actor_id = str(action.get("actor_id", "actor_1"))
    if held_alias and target_alias:
        return (
            f"{_ordinal_ru(actor_id, capitalized=True)} кладёт "
            f"{_to_object_case(held_alias, 'accusative')} на {_to_object_case(target_alias, 'accusative')}"
        )
    if held_alias:
        return f"{_ordinal_ru(actor_id, capitalized=True)} кладёт {_to_object_case(held_alias, 'accusative')}"
    return None


def _give_summary(action: dict[str, Any], record: CIRRecord) -> str | None:
    held_alias = _action_object_alias(record, action, use_holding_object=True)
    actor_id = str(action.get("actor_id", "actor_1"))
    target_id = str(action.get("target_id", "actor_2"))
    if held_alias:
        return (
            f"{_ordinal_ru(actor_id, capitalized=True)} передаёт "
            f"{_to_object_case(held_alias, 'accusative')} {_actor_surface_label(record, target_id, case='dative')}"
        )
    return None


def _talk_action_summary(action: dict[str, Any], record: CIRRecord, *, capitalized: bool = True) -> str:
    actor_id = str(action.get("actor_id", "actor_1"))
    actor_name = next(
        (
            actor.get("name")
            for actor in record["scene_graph"]["actors"]
            if actor["id"] == actor_id and isinstance(actor.get("name"), str) and actor.get("name")
        ),
        None,
    )
    speaker = localize_surface(actor_name) if actor_name else _ordinal_ru(actor_id, capitalized=capitalized)
    dialogue = localize_dialogue(str(action.get("dialogue", "")).strip())
    return f"{speaker}: {dialogue}" if dialogue else f"{speaker} говорит"


def _ordinal_case_ru(actor_id: str, case: str, *, capitalized: bool = False) -> str:
    forms = {
        "actor_1": {
            "nominative": "первый",
            "accusative": "первого",
            "dative": "первому",
        },
        "actor_2": {
            "nominative": "второй",
            "accusative": "второго",
            "dative": "второму",
        },
        "actor_3": {
            "nominative": "третий",
            "accusative": "третьего",
            "dative": "третьему",
        },
    }
    token = forms.get(actor_id, {}).get(case, _ordinal_ru(actor_id))
    return token.capitalize() if capitalized else token


def _inflect_actor_name(name: str, case: str) -> str:
    lowered = name.lower()
    irregular = {
        "павел": {
            "nominative": "Павел",
            "accusative": "Павла",
            "dative": "Павлу",
        }
    }
    if lowered in irregular:
        irregular_forms = irregular[lowered]
        if case in irregular_forms:
            return irregular_forms[case]
        return irregular_forms.get("nominative", name)
    if case == "dative":
        if lowered.endswith("ия"):
            return name[:-2] + "ии"
        if lowered.endswith("ья"):
            return name[:-2] + "ье"
        if lowered.endswith("а"):
            return name[:-1] + "е"
        if lowered.endswith("я"):
            return name[:-1] + "е"
        if lowered.endswith("й"):
            return name[:-1] + "ю"
        if lowered.endswith("ь"):
            return name[:-1] + "ю"
        return name + "у"
    if case == "accusative":
        if lowered.endswith("ия"):
            return name[:-2] + "ию"
        if lowered.endswith("ья"):
            return name[:-2] + "ью"
        if lowered.endswith("а"):
            return name[:-1] + "у"
        if lowered.endswith("я"):
            return name[:-1] + "ю"
        if lowered.endswith("й"):
            return name[:-1] + "я"
        if lowered.endswith("ь"):
            return name[:-1] + "я"
        return name + "а"
    return name


def _actor_surface_label(
    record: CIRRecord,
    actor_id: str,
    *,
    case: str = "nominative",
    capitalized: bool = False,
) -> str:
    actor_name = next(
        (
            str(actor.get("name")).strip()
            for actor in record["scene_graph"]["actors"]
            if actor["id"] == actor_id and isinstance(actor.get("name"), str) and str(actor.get("name")).strip()
        ),
        "",
    )
    if actor_name:
        localized = localize_surface(actor_name)
        surface = _inflect_actor_name(localized, case)
        return surface.capitalize() if capitalized else surface
    if case == "nominative":
        return _ordinal_ru(actor_id, capitalized=capitalized)
    return _ordinal_case_ru(actor_id, case, capitalized=capitalized)


def _non_dialogue_action_summary(action: dict[str, Any], record: CIRRecord, *, capitalized: bool = True) -> str | None:
    actor_id = str(action.get("actor_id", "actor_1"))
    actor_token = _actor_surface_label(record, actor_id, capitalized=capitalized)
    action_type = str(action.get("type", "")).strip()
    if action_type == "enter":
        return f"{actor_token} входит"
    if action_type == "described_action":
        payload = action.get("described_action", {})
        canonical = localize_described_action(str(payload.get("canonical_text", "делает действие")))
        return f"{actor_token} {canonical}"
    if action_type == "run":
        return f"{actor_token} начинает бежать"
    if action_type == "look_at":
        target_id = str(action.get("target_id", "actor_1"))
        return f"{actor_token} смотрит на {_actor_surface_label(record, target_id, case='accusative')}"
    if action_type == "turn":
        target_id = str(action.get("target_id", "actor_2"))
        return f"{actor_token} поворачивается к {_actor_surface_label(record, target_id, case='dative')}"
    if action_type == "stand":
        target_id = action.get("target_id")
        if isinstance(target_id, str):
            obj = _object_by_id(record, target_id)
            if obj is not None:
                return f"{actor_token} остаётся у {_to_object_case(_best_object_noun(obj), 'genitive')}"
        return f"{actor_token} остаётся на месте"
    return None


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
    must_preserve = [item for item in record["scene_graph"].get("must_preserve", []) if isinstance(item, str)]
    has_near_far_axis = "marker_axis:near_far" in must_preserve

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
        elif has_near_far_axis and relative in {"foreground", "background"}:
            noun = preferred.split(" ", 1)[-1]
            adjective_forms = _NEAR_FORMS if relative == "foreground" else _FAR_FORMS
            for adjective in adjective_forms:
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
        if phase == "dialogue_exchange":
            for action in actions:
                if action.get("type") == "talk":
                    clauses.append(_talk_action_summary(action, record, capitalized=not clauses))
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
        if phase == "open_object":
            action = actions[0] if actions else {}
            actor_id = str(action.get("actor_id", "actor_1"))
            target_alias = _action_object_alias(record, action)
            if target_alias:
                clauses.append(
                    f"{_ordinal_ru(actor_id, capitalized=not clauses)} открывает "
                    f"{_to_object_case(target_alias, 'accusative')}"
                )
            else:
                clauses.append(f"{_ordinal_ru(actor_id, capitalized=not clauses)} открывает контейнер")
            continue
        if phase == "pickup_object":
            action = actions[0] if actions else {}
            actor_id = str(action.get("actor_id", "actor_1"))
            target_alias = _action_object_alias(record, action)
            if target_alias:
                clauses.append(
                    f"{_ordinal_ru(actor_id, capitalized=not clauses)} берёт {_to_object_case(target_alias, 'accusative')}"
                )
            else:
                clauses.append(f"{_ordinal_ru(actor_id, capitalized=not clauses)} берёт предмет")
            continue
        if phase == "putdown_object":
            summary = _putdown_summary(actions[0], record) if actions else None
            if summary is not None:
                clauses.append(summary)
            else:
                actor_id = str(actions[0].get("actor_id", "actor_1")) if actions else "actor_1"
                clauses.append(f"{_ordinal_ru(actor_id, capitalized=not clauses)} кладёт предмет")
            continue
        if phase == "give_object":
            summary = _give_summary(actions[0], record) if actions else None
            if summary is not None:
                clauses.append(summary)
            else:
                actor_id = str(actions[0].get("actor_id", "actor_1")) if actions else "actor_1"
                clauses.append(f"{_ordinal_ru(actor_id, capitalized=not clauses)} передаёт предмет")
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
        if phase == "small_followup_action":
            for action in actions:
                summary = _non_dialogue_action_summary(action, record, capitalized=not clauses)
                if summary is not None:
                    clauses.append(summary)
                    break
            continue
        if phase in {"single_action", "first_described_action", "third_described_action"}:
            for action in actions:
                summary = _non_dialogue_action_summary(action, record, capitalized=not clauses)
                if summary is not None:
                    clauses.append(summary)
                    break
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
        return "Сцена развивается в несколько последовательных шагов."
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


def _summary_aliases(obj: ObjectNode) -> list[str]:
    aliases = localized_object_aliases(obj)
    noun_like = [alias for alias in aliases if not _is_prepositional_alias(alias)]
    if noun_like:
        aliases = noun_like
    non_slang = [alias for alias in aliases if alias.lower() not in _SLANGY_ALIASES]
    if non_slang:
        aliases = non_slang
    return aliases[:3]


def summarize_graph_for_source_prompt(record: CIRRecord) -> dict[str, object]:
    beat_outline = [
        f"{index}. {_beat_summary(beat, record)}"
        for index, beat in enumerate(record["scene_graph"]["beats"], start=1)
    ]
    marked_objects = []
    scene_objects = []
    scene_aliases: list[str] = []
    for obj in record["scene_graph"]["objects"]:
        aliases = _summary_aliases(obj)
        if aliases:
            scene_objects.append(
                {
                    "id": obj["id"],
                    "type": obj["type"],
                    "preferred_aliases": aliases[:3],
                }
            )
            scene_aliases.append(aliases[0])
        if obj["marker_binding"]["kind"] != "marked":
            continue
        marked_objects.append(
            {
                "id": obj["id"],
                "type": obj["type"],
                "preferred_aliases": aliases[:3],
                "surface_forms": sorted({form for alias in aliases for form in expand_surface_forms(alias)})[:6],
            }
        )

    graph_summary_lines = [f"Участников в сцене: {len(record['scene_graph']['actors'])}."]
    graph_summary_lines.append(f"Канонический пример: {_canonical_source_template(record)}")
    if scene_aliases:
        graph_summary_lines.append(f"Обычные названия предметов: {', '.join(scene_aliases[:4])}.")
    if marked_objects:
        primary_aliases = ", ".join(marked_objects[0]["preferred_aliases"][:2])
        graph_summary_lines.append(f"Важно явно назвать предмет: {primary_aliases}.")
    graph_summary_lines.append(f"Смысл сцены: {_fallback_canonical_source_template(record)}")

    payload = {
        "graph_summary": "\n".join(graph_summary_lines),
        "beat_outline": "\n".join(beat_outline),
        "marked_object_block": marked_objects,
        "scene_object_block": scene_objects,
        "same_type_disambiguation_block": _same_type_disambiguation_payload(record),
        "must_keep_semantics": record["scene_graph"].get("must_preserve", []) + _required_semantics(record),
        "must_not_introduce": [
            "новый объект",
            "новый шаг сцены",
            "новую причину действия",
            "придуманный диалог",
            *[_humanize_forbidden_item(item) for item in _forbidden_collapses(record)],
        ],
        "ordinal_bindings": record["scene_graph"]["reference_bindings"].get("ordinal_map", {}),
        "canonical_source_template": _canonical_source_template(record),
    }
    payload.update(extract_required_surface_anchors(record))
    return payload


def _render_marked_object_block(block: list[dict[str, object]]) -> str:
    if not block:
        return "- нет отдельного предмета"
    lines: list[str] = []
    for entry in block:
        aliases = ", ".join(entry["preferred_aliases"])
        surface_forms = ", ".join(entry["surface_forms"])
        lines.extend(
            [
                f"- предмет: {aliases}",
                f"  допустимые формы: {surface_forms}",
            ]
        )
    return "\n".join(lines)


def _render_scene_object_block(block: list[dict[str, object]]) -> str:
    if not block:
        return "- нет отдельных предметов"
    lines: list[str] = []
    for entry in block:
        aliases = ", ".join(entry["preferred_aliases"])
        lines.append(f"- {aliases}")
    return "\n".join(lines)


def _render_same_type_disambiguation(block: dict[str, object] | None) -> str:
    if block is None:
        return "- нет пары одинаковых объектов"
    lines = ["- если объекты одного типа похожи друг на друга, не потеряй различение:"]
    for entry in block["objects"]:
        target_suffix = " [именно этот]" if entry["is_target"] else ""
        lines.append(f"  - {entry['preferred_alias']}{target_suffix}")
        lines.append("    подсказки различения: " + ", ".join(entry["fallback_cues"][:6]))
    lines.append("- в тексте должен остаться хотя бы один явный отличительный признак правильного объекта")
    return "\n".join(lines)


def _render_list(values: list[str] | tuple[str, ...]) -> str:
    if not values:
        return "- нет"
    return "\n".join(f"- {value}" for value in values)


def _humanize_forbidden_item(value: str) -> str:
    mapping = {
        "split_single_dialogue_beat": "не разбивай один разговор на несколько отдельных диалоговых кусков",
        "rewrite_handoff_as_talk_only": "не превращай взятие и передачу предмета только в разговор",
        "single_talk_only_beat": "не теряй короткое действие после разговора",
        "drop_enter_phase": "не пропускай фазу входа участника",
        "actor_swap": "не меняй, кто именно выполняет шаги сцены",
        "ordinal_drop": "не теряй указания «первый/второй/третий» там, где они важны",
        "drop_pick_up": "не пропускай действие, где предмет сначала берут",
        "rewrite_pass_by_as_walk": "не заменяй проход мимо предмета простой ходьбой без опорного предмета",
        "single_actor_walk": "не превращай совместное движение в движение одного человека",
        "direction_drop": "не теряй, что идут именно навстречу друг другу",
        "one_beat_merge": "не склеивай несколько шагов сцены в один расплывчатый факт",
        "approach_instead_of_stop": "не заменяй остановку простым подходом",
        "drop_stop_phase": "не пропускай фазу остановки",
        "drop_final_run": "не пропускай финальный бег",
        "keep_both_walkers": "не убирай одного из участников из движения",
        "keep_both_stopped": "не теряй, что оба сначала остановились",
        "rewrite_described_action_to_talk": "не заменяй нестандартное действие разговором",
        "rewrite_to_talk": "не заменяй действие разговором",
        "rewrite_to_stand": "не заменяй действие простым стоянием",
        "drop_third_actor": "не убирай третьего участника",
        "type_only_resolution": "не описывай только тип объекта без различающего признака",
        "merge_markers": "не сливай два похожих объекта в один",
        "drop_relative_side": "не теряй различие левый/правый",
        "drop_relative_depth": "не теряй различие ближний/дальний",
        "drop_put_down_followup": "не пропускай действие, где предмет кладут",
        "talk_only_rewrite": "не превращай сцену только в разговор",
        "skip_open": "не пропускай открытие предмета или контейнера",
        "actor_swap_between_pickup_and_give": "не меняй участника между тем, как он берёт и передаёт предмет",
        "invent_object": "не подменяй исходный предмет новым",
        "drop_give_phase": "не пропускай передачу предмета",
    }
    return mapping.get(value, "не теряй важное ограничение сцены")


def _humanize_semantic_anchor(item: str) -> str:
    value = str(item).strip()
    if value.startswith("beat_count="):
        count = value.split("=", 1)[1].strip()
        return f"сохрани {count} последовательных шага сцены без слияния"
    if value.startswith("must_ground_object:"):
        return "предмет должен быть явно назван обычным словом"
    if value.startswith("morphology_surface:"):
        surface = value.split(":", 1)[1].strip()
        return f"сохрани именно такую форму: {surface}" if surface else "сохрани нужную форму слова"
    if value.startswith("ordinal:first->"):
        return "сохрани ordinal ссылку «первый»"
    if value.startswith("ordinal:second->"):
        return "сохрани ordinal ссылку «второй»"
    if value.startswith("ordinal:third->"):
        return "сохрани ordinal ссылку «третий»"
    if value.startswith("second_actor_anchor:"):
        return "не теряй, возле какого именно предмета остаётся второй"
    if value.startswith("third_actor_anchor:"):
        return "не теряй, возле какого именно предмета остаётся третий"
    if value == "actor_2_runs_in_final_beat":
        return "в самом конце начинает бежать именно второй"
    if value.startswith("put_down_target:"):
        return "не подменяй предмет при действии «кладёт»"
    if value.startswith("pickup_target:"):
        return "не подменяй предмет при действии «берёт»"
    if value.startswith("handoff_object:"):
        return "передают именно тот же предмет, без подмены"
    if value == "holding_object_preserved":
        return "это должен быть тот же предмет, который держали до этого"
    if value == "inside_relation":
        return "сохрани связь «внутри/изнутри», если она есть"
    if value == "open_before_pick_up":
        return "сначала открывают, потом берут"
    if value == "direction_toward_each_other":
        return "сохрани, что оба идут именно друг к другу"
    if value == "dual_motion":
        return "сохрани движение обоих, а не одного"
    if value == "talk_only":
        return "оставь только разговор, без новых действий"
    if value == "dialogue_text_exactness":
        return "не теряй смысл самих реплик и их порядок"
    if value == "no_invented_objects":
        return "не добавляй новые предметы"
    if value == "two_beat_ordering":
        return "сохрани порядок из двух шагов"
    if value == "small_followup_action":
        return "не теряй короткое действие после разговора"
    if value == "dialogue_exchange":
        return "сохрани разговор и порядок реплик"
    if value == "dialogue_then_small_action":
        return "после разговора должно остаться короткое действие"
    if value == "dialogue_precedes_put_down":
        return "сначала звучит реплика, потом кладут предмет"
    if value == "enter_then_put_down":
        return "сначала входит участник, потом кладёт предмет"
    if value == "enter_before_put_down":
        return "сначала участник входит, а потом кладёт предмет"
    if value == "open_precedes_pick_up":
        return "сначала открывают, потом берут"
    if value == "pick_up_precedes_put_down":
        return "сначала берут предмет, потом кладут его"
    if value == "dialogue_then_put_down":
        return "разговор должен перейти именно в действие «кладёт»"
    if value == "pick_up_before_put_down":
        return "сначала предмет поднимают, а уже потом кладут"
    if value == "pass_by_semantics":
        return "сохрани, мимо какого именно предмета проходят"
    if value == "marked_object_grounding":
        return "не теряй явное название предмета"
    if value == "dual_stop_near_object":
        return "сохрани, что оба остановились рядом с одним и тем же предметом"
    if value == "dual_pass_by_object":
        return "сохрани, что мимо одного и того же предмета проходят оба"
    if value == "ordinal_map":
        return "не путай роли первого, второго и третьего"
    if value == "actor_role_stability":
        return "не меняй роли участников местами"
    if value == "third_actor_binding":
        return "не теряй привязку третьего участника"
    if value == "three_actor_role_stability":
        return "не путай роли трёх участников"
    if value == "three_beat_chronology":
        return "сохрани три шага по порядку"
    if value == "stop_phase_before_run":
        return "сначала должна быть остановка, и только потом бег"
    if value == "first_actor_described_action":
        return "в конце нестандартное действие делает именно первый"
    if value == "third_actor_described_action":
        return "в конце нестандартное действие делает именно третий"
    if value == "third_actor_terminal_action":
        return "в финале заметное действие делает именно третий"
    if value == "second_actor_runs":
        return "в конце начинает бежать именно второй"
    if value == "pass_by_then_role_shift":
        return "сначала проходят мимо предмета, потом действие меняется у второго"
    if value == "stop_near_then_role_shift":
        return "сначала останавливаются рядом с предметом, потом действие меняется у второго"
    if value == "ordinal_surface_stress":
        return "не заменяй слова «первый/второй/третий» чем-то расплывчатым"
    if value == "two_marked_objects_same_type":
        return "не перепутай два похожих объекта одного типа"
    if value == "symmetric_toward_each_other":
        return "оба участника должны двигаться симметрично навстречу друг другу"
    if value == "same_type_markers_present":
        return "в сцене есть два похожих объекта, их нужно различить"
    if value == "no_type_only_resolution":
        return "не описывай объект только по типу без уточнения"
    if value == "marker_axis:left_right":
        return "различай объекты по стороне: левый и правый"
    if value == "marker_axis:near_far":
        return "различай объекты по дистанции: ближний и дальний"
    if value == "exact_marker_resolution":
        return "выбери правильный объект и назови его с отличительным признаком"
    if value == "left_right_disambiguation":
        return "сохрани различение по левому и правому объекту"
    if value == "near_far_disambiguation":
        return "сохрани различение по ближнему и дальнему объекту"
    if value == "dialogue_precedes_pickup":
        return "сначала разговор, потом берут предмет"
    if value == "pickup_precedes_give":
        return "сначала берут предмет, потом передают"
    if value == "third_actor_receives_object":
        return "предмет в итоге получает именно третий"
    if value == "final_target:actor_3":
        return "финальное действие направлено на третьего участника"
    if value == "give_actor:actor_1":
        return "предмет передаёт именно первый"
    if value == "give_actor:actor_2":
        return "предмет передаёт именно второй"
    if value == "pickup_actor:actor_1":
        return "предмет сначала берёт именно первый"
    if value == "pickup_actor:actor_2":
        return "предмет сначала берёт именно второй"
    if value == "same_actor_completes_handoff":
        return "предмет забирает и передаёт один и тот же участник"
    if value == "unsupported_to_described_action":
        return "нестандартное действие перескажи простыми словами без подмены"
    if value == "must_preserve_source":
        return "сохрани исходный смысл как есть"
    if value == "described_action_required":
        return "обязательно оставь нестандартное действие в тексте"
    if value == "single_actor":
        return "в сцене действует один участник"
    if value.startswith("action:") and value.endswith("=described_action"):
        return "не заменяй финальное нестандартное действие обычным шаблонным глаголом"
    return "сохрани обязательный смысловой якорь сцены"


def _render_semantic_anchors(values: list[str] | tuple[str, ...]) -> str:
    if not values:
        return "- нет"
    return "\n".join(f"- {_humanize_semantic_anchor(value)}" for value in values)


def _render_ordinal_bindings(bindings: dict[str, str]) -> str:
    if not bindings:
        return "- нет"
    human_ordinal = {"first": "первый", "second": "второй", "third": "третий"}
    human_actor = {"actor_1": "первый актёр", "actor_2": "второй актёр", "actor_3": "третий актёр"}
    lines: list[str] = []
    for ordinal in ("first", "second", "third"):
        actor_id = str(bindings.get(ordinal, "")).strip()
        if not actor_id:
            continue
        lines.append(f"- {human_ordinal.get(ordinal, ordinal)} => {human_actor.get(actor_id, 'соответствующий актёр')}")
    return "\n".join(lines) if lines else "- нет"


def build_source_prompt(plan_item: VariantPlanItem, previous_reject_reason: str | None = None) -> tuple[str, str]:
    payload = plan_item.prompt_payload
    system_prompt = "\n".join(
        [
            "Ты пишешь одно естественное русское пользовательское описание сцены.",
            "Нельзя придумывать новые события, объекты, роли, реплики или причины действий.",
            "Нужно сохранить порядок шагов, привязку участников по словам «первый/второй/третий» и явное упоминание предмета, если он есть.",
            "Если в подсказке уже есть обычные названия предметов, лучше используй их, а не заменяй всё словами «предмет» или «контейнер».",
            "Если в сцене есть нестандартное действие, перескажи его простыми словами, а не заменяй другим действием.",
            "Верни только одну финальную фразу или 1-2 коротких фразы без пояснений, списка и JSON.",
        ]
    )
    user_lines = [
        f"Собери один {plan_item.style_bucket} вариант русского пользовательского описания сцены.",
        "",
        "Краткий смысл сцены:",
        str(payload["graph_summary"]),
        "",
        "Порядок шагов, который нельзя ломать:",
        str(payload["beat_outline"]),
        "",
        "Кого называют первым, вторым и третьим:",
        _render_ordinal_bindings(dict(payload["ordinal_bindings"])),
        "",
        "Предмет сцены:",
        _render_marked_object_block(payload["marked_object_block"]),
        "",
        "Какими обычными словами можно называть предметы сцены:",
        _render_scene_object_block(payload["scene_object_block"]),
        "",
        "Если есть похожие объекты:",
        _render_same_type_disambiguation(payload["same_type_disambiguation_block"]),
        "",
        "Что обязательно сохранить:",
        _render_semantic_anchors(payload["must_keep_semantics"]),
        "",
        "Чего нельзя добавлять:",
        _render_list(payload["must_not_introduce"]),
        "",
        "Правила стиля:",
        STYLE_RULES[plan_item.style_bucket],
        "",
        "Жёсткие ограничения:",
        "- не добавляй новые события",
        "- не добавляй новые объекты",
        "- не теряй предмет, если он есть",
        "- не теряй слова первый/второй/третий, если они нужны для понимания сцены",
        "- не склеивай несколько шагов сцены в один расплывчатый факт",
        "- не заменяй нестандартное действие разговором или другим более простым действием",
        "- не используй служебные идентификаторы и внутренние англоязычные теги пайплайна",
        "- не пиши пояснений, списков и JSON",
        "",
        "Верни только один финальный русский текст.",
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
