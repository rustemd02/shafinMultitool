#!/usr/bin/env python3
"""Free-text → label suggestions for the annotation tool.

The annotator writes what they see in their own words ("лампа мешает лицу",
"темно и мутно"); this module maps those phrases onto the frozen issue/action
catalog so the GUI can pre-select boxes.

It is a SUGGESTION layer, never the source of truth: the annotator confirms or
corrects every box, and only their saved record becomes human-gold. The rule
table is deliberately small and readable so it can be extended from real notes.
"""

from __future__ import annotations

# phrase fragments (lowercase) -> issues to pre-select
ISSUE_PHRASES: list[tuple[tuple[str, ...], tuple[str, ...]]] = [
    (("меша", "отвлека", "лишн", "мусор"), ("frame_visually_overloaded",)),
    (("фон шумн", "шумн фон", "занят фон", "фон конкур", "пёстрый фон", "пестрый фон",
      "фон слишком", "занят", "загроможд", "нагружен фон"),
     ("background_competes_with_subject",)),
    (("контров", "свет сзади", "сзади свет", "против света"), ("backlight_hides_subject",)),
    (("мелк", "далеко", "маленьк", "не видно субъект"), ("subject_not_prominent_enough",)),
    (("у края", "край кадра", "обрезан", "режет"), ("subject_too_close_to_edge",)),
    (("горизонт", "завал", "наклон", "крив"), ("horizon_distracts",)),
    (("пространств", "взгляд", "смотрит в стену", "тесно"), ("insufficient_look_space",)),
    (("нет фокус", "непонятно на что", "разброс", "непонятно, что"), ("scene_has_no_clear_focus",)),
    (("перегруж", "много всего", "хаос"), ("frame_visually_overloaded",)),
    (("стекл", "блик", "отраж"), ("frame_visually_overloaded",)),
    (("темн", "недосвет", "тень"), ("scene_has_no_clear_focus",)),
    (("пересвет", "ярко", "засвеч", "выжжен"), ("background_competes_with_subject",)),
]

# phrase fragments -> actions to pre-select
ACTION_PHRASES: list[tuple[tuple[str, ...], tuple[str, ...]]] = [
    (("вправо", "направо"), ("shift_frame_right",)),
    (("влево", "налево"), ("shift_frame_left",)),
    (("вверх", "выше"), ("shift_frame_up",)),
    (("вниз", "ниже"), ("shift_frame_down",)),
    (("ближе", "приблиз"), ("step_closer",)),
    (("отойти", "дальше", "шаг назад"), ("step_back",)),
    (("угол", "ракурс", "разворот"), ("change_camera_angle",)),
    (("горизонт", "выровня"), ("level_horizon",)),
    (("к свету", "повернуть к свету", "разверни лицо"), ("rotate_subject_toward_light",)),
    (("убрать предмет", "убрать лампу", "убрать лишн", "убери", "убрать", "отвлека", "мешает"),
     ("remove_distracting_object",)),
    (("переставить", "поставить предмет", "баланс"), ("reposition_prop_for_balance",)),
    (("добавь свет", "заполняющий", "подсветить лицо", "темное лицо"), ("add_front_fill_light",)),
    (("свет на фон", "отделить от фона подсветкой"), ("add_background_light",)),
    (("пересвет", "блик", "яркое пятно"), ("remove_background_hotspot",)),
    (("упростить фон", "чистый фон", "размыть фон"), ("simplify_background",)),
    (("подождать", "пока пройдут", "дождаться"), ("wait_for_background_clearance",)),
    (("отодвинуть", "дальше от фона", "оторвать от фона"), ("move_subject_away_from_background",)),
    (("сдвинуть линию глаз", "сместить вправо"), ("move_subject_right",)),
    (("сместить влево"), ("move_subject_left",)),
    (("опустить камеру", "ниже камеру"), ("lower_camera",)),
    (("поднять камеру", "выше камеру"), ("raise_camera",)),
]

# phrases that mean "this is intentional — do not fix it"
KEEP_PHRASES: tuple[str, ...] = (
    "задумано", "намеренно", "настроение", "мрачн", "низкий ключ", "low key",
    "силуэт", "стилист", "специально", "mood", "оставить как есть", "так и надо",
)


def suggest(text: str) -> dict:
    """Return {'issues': [...], 'actions': [...], 'keep': bool} for a note."""
    lowered = (text or "").lower()
    issues: list[str] = []
    actions: list[str] = []
    if not lowered.strip():
        return {"issues": [], "actions": [], "keep": False}

    for fragments, mapped in ISSUE_PHRASES:
        if any(fragment in lowered for fragment in fragments):
            issues.extend(mapped)
    for fragments, mapped in ACTION_PHRASES:
        if any(fragment in lowered for fragment in fragments):
            actions.extend(mapped)

    keep = any(phrase in lowered for phrase in KEEP_PHRASES)
    if keep:
        return {"issues": [], "actions": [], "keep": True}

    dedup_issues = list(dict.fromkeys(issues))
    dedup_actions = list(dict.fromkeys(actions))
    if dedup_issues and not dedup_actions:
        # A defect was named without a direction: the annotator picks the fix.
        dedup_actions = []
    return {"issues": dedup_issues, "actions": dedup_actions, "keep": False}
