#!/usr/bin/env python3
"""annotate_fast — keyboard-first визард разметки «один вопрос за раз» (DATA-005/DATA-008 UX-итерация).

Причина появления: владелец (единственный аннотатор) отказался от annotate_gui —
«перегруженный, странные вещи типа слайдера "насколько сдвинуть"», а прошлый NL-апгрейд
(текст → контракт) страдал качеством. Этот инструмент отвечает принципу:

    человек отвечает ТОЛЬКО на вопросы, которые человек может надёжно оценить
    (кнопки/буквы/рамка мышью); ВСЕ числа машина выводит детерминированно;
    естественный язык хранится рядом (raw opinion), но НИКОГДА не конвертируется
    в метки — метки только явным выбором кнопок.

Поток (визард): одна большая картинка, крупные подписи, статус-строка
«12/106 · группа composition». Шаги:

  1. «Кадр в целом?» [1] хороший · [2] норм, но улучшить · [3] плохой
     [U] НЕ ПОНИМАЮ ЗАМЫСЕЛ · [S] пропуск.
       [1] → короткий confirm: Enter=сохранить keep (2 нажатия на кадр);
             любая issue-клавиша — «передумал» (после issues вердикт переспрашивается
             2/3/U: пара «issues + good» блокируется, см. tracker DATA-005).
       [3] → обязательный вопрос «это намеренный стиль?» Y/N;
             Y → keep + обязательная заметка (контракт ugly+keep требует note);
             N → обычный needs_fix путь.
       [U] → первоклассный путь: подсказка причины (4 варианта) + одна строка
             «что смущает?» (можно пусто) → unsure=true; экспорт — abstain
             с явной причиной. Аннотатор никогда не угадывает.
  2. issues: мульти-выбор одиночными клавишами (15 heads контракта в 3 группах,
     легенда на экране, выбранные подсвечены). Пробел/Enter — далее.
     Опционально рамка мышью для последней выбранной issue; [R] «весь кадр»,
     [X] «не могу указать» (X снижает confidence-бакет на один шаг — честно).
  3. action: шорт-лист (буквы) ТОЛЬКО релевантных действий — фильтрация выбранных
     issues через DATA-002 (camera_release_capability_mapping_v1.json,
     disposition=mapped, только поддержанные). Ничего релевантного нет →
     [N] «нет подходящего действия» (честное отсутствие → воздержание,
     unsupported_case; выбранные проблемы сохраняются в regions/заметке).
  4. «Насколько плохо?» [1] слегка · [2] заметно · [3] серьёзно
     → severity = 0.3 / 0.6 / 0.85 (машина).
  5. «Насколько уверен?» [1] уверен · [2] не очень → confidence = 0.9 / 0.6;
     при [X] максимум 0.6 / 0.45 (машина).
  6. Только для действий, двигающих объект (move_*/rotate_subject/remove/reposition):
     «Объект можно передвинуть?» [Y] movable/allowed · [N] immovable/denied ·
     [?] unknown/unknown. Остальным — movability=not_applicable, target auto.
  6a. Рамка главного объекта — только когда контракт релиза (camera_release_label_v1)
     требует resolvedTarget с регионом (schema allOf[6/7]); честное отклонение от
     «target=primary subject (auto)»: авто-таргет без человеческой рамки не проходит
     валидатор DATA-001, выдумывать регион машина отказывается.
  7. Заметка (опционально; обязательна для ugly+keep): свободный текст = raw opinion,
     НЕ источник меток. Экспорт требует непустое мнение — без него отклоняется.
  8. Enter — сохранить; Esc — шаг назад; B — предыдущий кадр (правки = новая
     append-only запись, старая не переписывается).

Защиты от ошибок аннотатора: dwell-time предупреждение (<1.5 сек на needs_fix кадре),
скрытые QC-сиды (5–7% очереди, отдельный qc.jsonl, отчёт --report-qc), санити-мапа
issue↔action перед сохранением, блок «issues + good», append-only, ничего не пишется
до Enter, session.json — закрыл и продолжил. Автозаполнение: record_id/ID/хеши/
evidence_refs/entity_ref; captured_at НЕ выдумывается (пусто если неизвестно —
экспорт такой записи честно отклоняется).

Никогда не спрашивается (машина выводит или отказывается): числа severity/confidence,
текст evidence-ref, текст entity_ref, source_family/frame_id, magnitude.

Хранилища (свои, в каталоге очереди): fast_labels.jsonl (v1-записи через
annotation_labels.build_label), fast_details.jsonl (машиные бакеты/регионы рядом),
qc.jsonl (результаты сидов), session.json (прогресс). queue.jsonl не модифицируется.

Экспорт: --export-out DIR строит conversion config (release_label_config.
build_conversion_config, файл не меняется) и вызывает release_label_adapter.py
convert+validate (subprocess, tmp в /tmp). REJECTED → показать и НЕ записывать.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
CONTRACTS = REPO / "ml" / "camera_coach" / "contracts"
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(CONTRACTS))

from annotation_labels import (  # noqa: E402
    ACTIONS as V1_ACTIONS,
    ISSUES as V1_ISSUES,
    KEEP_ACTION,
    build_label,
    load_labels,
    sha256_file,
    validate_label,
)
from release_label_config import ReleaseConfigError, build_conversion_config  # noqa: E402

V1_ISSUE_SET = frozenset(V1_ISSUES)
V1_ACTION_SET = frozenset(V1_ACTIONS)

SCHEMA_PATH = CONTRACTS / "camera_release_label_v1.schema.json"
MAPPING_PATH = CONTRACTS / "camera_release_capability_mapping_v1.json"

SESSION_SCHEMA = "camera-fast-annotate-session-v1"
DETAIL_SCHEMA = "camera-fast-annotate-detail-v1"
QC_SCHEMA = "camera-fast-annotate-qc-v1"

# --------------------------------------------------------------------------- #
# Машиные бакеты: человек жмёт кнопку, число выводит детерминированно.
# --------------------------------------------------------------------------- #

SEVERITY_BY_KEY = {"1": 0.3, "2": 0.6, "3": 0.85}
SEVERITY_LABELS = {"1": "слегка", "2": "заметно", "3": "серьёзно"}
CONFIDENCE_BY_KEY = {"1": 0.9, "2": 0.6}
CONFIDENCE_LABELS = {"1": "уверен", "2": "не очень"}
# «не могу указать» ([X]) снижает уверенность на один шаг.
CONFIDENCE_STEP_DOWN = {0.9: 0.6, 0.6: 0.45}

DWELL_WARN_SECONDS = 1.5

# 15 heads контракта в 3 группах с буквами. Буквы не пересекаются со
# служебными клавишами потока (1 2 3 U S B R X Y N W Esc Enter; навигация
# кадрами — B/→, мышью — рамки).
ISSUE_GROUPS: list[tuple[str, list[tuple[str, str, str]]]] = [
    ("Композиция и фон", [
        ("E", "subject_too_close_to_edge", "субъект у края"),
        ("P", "subject_not_prominent_enough", "субъект мелкий / незаметный"),
        ("C", "background_competes_with_subject", "фон спорит с субъектом"),
        ("L", "insufficient_look_space", "мало воздуха / пространства"),
        ("V", "frame_visually_overloaded", "кадр перегружен"),
        ("H", "horizon_distracts", "горизонт завален / отвлекает"),
    ]),
    ("Свет и читаемость", [
        ("K", "backlight_hides_subject", "контровой свет глушит субъект"),
        ("G", "overexposure", "пересвет"),
        ("D", "underexposure", "недосвет"),
        ("Q", "scene_has_no_clear_focus", "непонятно, что главное"),
    ]),
    ("Техника", [
        ("M", "motion_blur", "смаз от движения"),
        ("F", "defocus", "расфокус"),
        ("Z", "noise", "шум"),
        ("O", "occlusion", "субъект перекрыт"),
        ("T", "lens_smudge", "грязь / смаз на линзе"),
    ]),
]
ISSUE_KEYS: dict[str, str] = {key: head for _, rows in ISSUE_GROUPS for key, head, _ in rows}
ISSUE_TITLES: dict[str, str] = {head: title for _, rows in ISSUE_GROUPS for _, head, title in rows}
RELEASE_ISSUES = tuple(ISSUE_KEYS.values())
# 7 технических heads существуют только в release-контракте (15 heads, DATA-001):
# v1-хранилище (annotation_labels) и адаптер их не знают. Визард предлагает все 15
# (спека); v1-запись несёт только пересечение со словарём v1, полная правда — в
# fast_details.jsonl; экспорт записей, выходящих за v1-словарь, честно REJECTED.
RELEASE_ONLY_ISSUES = tuple(h for h in RELEASE_ISSUES if h not in V1_ISSUE_SET)

# issue → кандидаты-действия. ТОЛЬКО disposition=mapped из DATA-002 (проверяется
# тестом против реального mapping-файла): неподдержанные действия не предлагаются.
ISSUE_TO_ACTIONS: dict[str, list[str]] = {
    "subject_too_close_to_edge": [
        "shift_frame_left", "shift_frame_right", "shift_frame_up", "shift_frame_down", "step_back",
    ],
    "subject_not_prominent_enough": ["step_closer", "step_back"],
    "background_competes_with_subject": [
        "remove_distracting_object", "wait_for_background_clearance", "change_camera_angle",
        "move_subject_away_from_background",
        "move_object_left", "move_object_right", "move_object_forward", "move_object_back",
    ],
    "insufficient_look_space": [
        "shift_frame_left", "shift_frame_right", "shift_frame_up", "shift_frame_down",
        "change_camera_angle",
    ],
    "backlight_hides_subject": ["add_front_fill_light", "change_camera_angle"],
    "scene_has_no_clear_focus": ["step_closer", "change_camera_angle"],
    "frame_visually_overloaded": [
        "remove_distracting_object", "wait_for_background_clearance", "change_camera_angle",
        "step_back", "move_object_left", "move_object_right",
    ],
    "horizon_distracts": ["level_horizon", "change_camera_angle"],
    "motion_blur": ["stabilize_camera"],
    "defocus": ["refocus_subject"],
    "overexposure": ["reduce_exposure"],
    "underexposure": ["increase_exposure", "add_front_fill_light"],
    "noise": [],  # reduce_iso_noise не поддержан — честное «нет подходящего действия»
    "occlusion": ["avoid_occlusion", "wait_for_background_clearance"],
    "lens_smudge": [],  # clean_lens не поддержан — честное «нет подходящего действия»
}

ACTION_TITLES: dict[str, str] = {
    "shift_frame_left": "сдвинуть кадр влево",
    "shift_frame_right": "сдвинуть кадр вправо",
    "shift_frame_up": "сдвинуть кадр вверх",
    "shift_frame_down": "сдвинуть кадр вниз",
    "step_back": "шаг назад (субъект мельче)",
    "step_closer": "шаг ближе (субъект крупнее)",
    "lower_camera": "камеру ниже",
    "raise_camera": "камеру выше",
    "change_camera_angle": "изменить ракурс",
    "level_horizon": "выровнять горизонт",
    "rotate_subject_toward_light": "повернуть субъекта к свету",
    "move_subject_left": "субъекта левее",
    "move_subject_right": "субъекта правее",
    "move_subject_away_from_background": "субъекта дальше от фона",
    "move_object_left": "объект левее",
    "move_object_right": "объект правее",
    "move_object_forward": "объект ближе",
    "move_object_back": "объект дальше",
    "remove_distracting_object": "убрать мешающий объект",
    "reposition_prop_for_balance": "переставить предмет для баланса",
    "add_front_fill_light": "добавить заполняющий свет",
    "add_background_light": "добавить свет на фон",
    "remove_background_hotspot": "убрать хотспот на фоне",
    "simplify_background": "упростить фон",
    "wait_for_background_clearance": "подождать, пока фон очистится",
    "keep_current_setup": "оставить как есть",
    "stabilize_camera": "стабилизировать камеру",
    "refocus_subject": "навести фокус на субъект",
    "reduce_exposure": "убавить экспозицию",
    "increase_exposure": "добавить экспозицию",
    "avoid_occlusion": "избежать перекрытия",
    "clean_lens": "протереть линзу",
    "reduce_iso_noise": "убрать ISO-шум",
}

# Буквы для шорт-листа действий (не U/S/B/R/X/Y/N — служебные потока).
ACTION_KEY_POOL = "ACDEFGHIJKLMOQTVWZ"

# «НЕ ПОНИМАЮ ЗАМЫСЕЛ»: подсказки причин → enum причин воздержания из схемы.
UNSURE_REASONS: list[tuple[str, str, str]] = [
    ("1", "unsupported_case", "непонятна цель кадра"),
    ("2", "ambiguous_subject", "двусмысленный субъект"),
    ("3", "unqualified", "похоже на стиль, но не уверен"),
    ("4", "missing_evidence", "другое"),
]

VERDICT_KEYS: list[tuple[str, str, str]] = [
    ("1", "good", "хороший"),
    ("2", "borderline", "норм, но улучшить"),
    ("3", "ugly_fix", "плохой"),
    ("U", "unsure", "НЕ ПОНИМАЮ ЗАМЫСЕЛ"),
    ("S", "skip", "пропуск"),
]

MOVABILITY_ANSWERS = {
    "Y": ("movable", "allowed"),
    "N": ("immovable", "denied"),
    "?": ("unknown", "unknown"),
}


def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def _schema_condition_actions(schema: dict, index: int) -> set[str]:
    return set(schema["allOf"][index]["if"]["properties"]["action"]["properties"]["action_id"]["enum"])


def resolved_target_actions(schema: dict | None = None) -> set[str]:
    """Действия, для которых контракт требует resolvedTarget (identity=resolved + регион)."""
    return _schema_condition_actions(schema or load_schema(), 6)


def moving_actions(schema: dict | None = None) -> set[str]:
    """Действия-перемещения: дополнительно movability=movable/allowed."""
    return _schema_condition_actions(schema or load_schema(), 7)


def mapped_actions(mapping: dict | None = None) -> set[str]:
    """Действия с disposition=mapped из DATA-002 — только они предлагаются."""
    data = mapping if mapping is not None else json.loads(MAPPING_PATH.read_text(encoding="utf-8"))
    return {a for a, row in data["action_dispositions"].items() if row.get("status") == "mapped"}


# --------------------------------------------------------------------------- #
# Чистые функции: бакеты, шорт-лист, санити, таргет, evidence.
# --------------------------------------------------------------------------- #

def severity_value(key: str) -> float:
    if key not in SEVERITY_BY_KEY:
        raise ValueError(f"неизвестный бакет серьёзности: {key!r}")
    return SEVERITY_BY_KEY[key]


def confidence_value(key: str, cant_point: bool) -> float:
    if key not in CONFIDENCE_BY_KEY:
        raise ValueError(f"неизвестный бакет уверенности: {key!r}")
    value = CONFIDENCE_BY_KEY[key]
    if cant_point:
        value = CONFIDENCE_STEP_DOWN[value]
    return value


def candidate_actions(selected_issues: list[str], *, allowed: set[str] | None = None) -> list[str]:
    """Релевантные поддержанные действия: объединение по выбранным issues.

    Порядок стабилен: сначала действия, покрывающие больше выбранных проблем,
    затем по алфавиту — короткий список сверху самый релевантный.
    """
    pool = allowed if allowed is not None else mapped_actions()
    coverage: dict[str, int] = {}
    for issue in selected_issues:
        for action in ISSUE_TO_ACTIONS.get(issue, []):
            if action in pool:
                coverage[action] = coverage.get(action, 0) + 1
    return [a for a, _ in sorted(coverage.items(), key=lambda kv: (-kv[1], kv[0]))]


def assign_action_letters(actions: list[str]) -> list[tuple[str, str, str]]:
    """Буквы шорт-листа; при переполнении пула лишние (наименее релевантные) не показываются."""
    out: list[tuple[str, str, str]] = []
    for i, action in enumerate(actions[: len(ACTION_KEY_POOL)]):
        out.append((ACTION_KEY_POOL[i], action, ACTION_TITLES.get(action, action)))
    return out


def action_coverage_warnings(selected_issues: list[str], action: str) -> list[str]:
    """Санити issue↔action: выбранное действие не покрывает часть выбранных проблем.

    Классический пример спецификации — underexposure + level_horizon — попадает
    сюда ровно тем же механизмом (level_horizon не относится к underexposure).
    """
    covered = {i for i in selected_issues if action in ISSUE_TO_ACTIONS.get(i, [])}
    uncovered = [i for i in selected_issues if i not in covered]
    warnings: list[str] = []
    if not covered:
        warnings.append(
            f"действие {ACTION_TITLES.get(action, action)} не относится ни к одной "
            f"из выбранных проблем — проверь выбор"
        )
    elif uncovered:
        names = ", ".join(ISSUE_TITLES.get(i, i) for i in uncovered)
        warnings.append(
            f"действие «{ACTION_TITLES.get(action, action)}» не относится к: {names} "
            "(если это отдельная проблема — вернись и проверь)"
        )
    return warnings


def kind_for_action(action: str) -> str:
    """kind таргета выводится из словаря действий (машина, без вопросов)."""
    if action.startswith(("move_subject", "rotate_subject")):
        return "person"
    if action.startswith(("move_object", "remove_distracting", "reposition_prop")):
        return "object"
    return "object"  # generic: у схемы нет kind=unknown; отклонение описано в ресипте


def derive_target(
    *,
    action: str | None,
    verdict: str,
    subject_rect: list[float] | None,
    movability_answer: str | None,
) -> dict:
    """Таргет для экспорта: всё выводит машина из ответов человека.

    Отклонение от спеки (зафиксировано в ресипте): для действий из schema
    allOf[6] контракт требует identity_status=resolved + непустой регион, поэтому
    «target=primary subject (auto)» без человеческой рамки невозможно — шаг 6a
    спрашивает рамку; [R] «весь кадр» даёт регион [0,0,1,1].
    """
    if verdict in ("unsure", "no_action"):
        return {
            "entity_ref": "subject-1",
            "identity_status": "unknown",
            "kind": "object",
            "role": "context",
            "rect": subject_rect,
            "movability_status": "unknown",
            "movability_permission": "unknown",
        }
    if action is None or action == KEEP_ACTION:
        return {
            "entity_ref": "subject-1",
            "identity_status": "unknown",
            "kind": "object",
            "role": "context",
            "rect": None,
            "movability_status": "not_applicable",
            "movability_permission": "unknown",
        }
    resolved = action in resolved_target_actions()
    moving = action in moving_actions()
    if moving:
        status, permission = MOVABILITY_ANSWERS.get(movability_answer or "?", ("unknown", "unknown"))
        return {
            "entity_ref": "subject-1",
            "identity_status": "resolved",
            "kind": kind_for_action(action),
            "role": "target",
            "rect": subject_rect,
            "movability_status": status,
            "movability_permission": permission,
        }
    if resolved:
        return {
            "entity_ref": "subject-1",
            "identity_status": "resolved",
            "kind": kind_for_action(action),
            "role": "target",
            "rect": subject_rect if subject_rect is not None else [0.0, 0.0, 1.0, 1.0],
            "movability_status": "not_applicable",
            "movability_permission": "unknown",
        }
    # stabilize_camera / reduce_exposure / increase_exposure: resolvedTarget не требуется.
    return {
        "entity_ref": "subject-1",
        "identity_status": "unknown",
        "kind": kind_for_action(action),
        "role": "target",
        "rect": None,
        "movability_status": "not_applicable",
        "movability_permission": "unknown",
    }


def evidence_ref(record_id: str, index: int, has_rect: bool) -> str:
    """Машина: с рамкой «{record}.r{i}», без рамки «{record}.frame»."""
    return f"{record_id}.r{index}" if has_rect else f"{record_id}.frame"


def normalize_rect(x0: float, y0: float, x1: float, y1: float) -> list[float] | None:
    """Нормализованный [x,y,w,h] внутри [0,1]; вырожденная рамка → None."""
    x, y = min(x0, x1), min(y0, y1)
    w, h = abs(x1 - x0), abs(y1 - y0)
    x, y = max(0.0, min(1.0, x)), max(0.0, min(1.0, y))
    w = min(w, 1.0 - x)
    h = min(h, 1.0 - y)
    if w <= 0.001 or h <= 0.001:
        return None
    return [round(x, 4), round(y, 4), round(w, 4), round(h, 4)]


def dwell_warning(elapsed_seconds: float, verdict_key: str) -> bool:
    return verdict_key in ("2", "3") and elapsed_seconds < DWELL_WARN_SECONDS


# --------------------------------------------------------------------------- #
# Визард-автомат (чистый, без tkinter): GUI только показывает снапшот и шлёт события.
# --------------------------------------------------------------------------- #

STEP_VERDICT = "verdict"
STEP_STYLE = "style_check"
STEP_STYLE_NOTE = "style_note"
STEP_CONFIRM_KEEP = "confirm_keep"
STEP_UNSURE_REASON = "unsure_reason"
STEP_UNSURE_NOTE = "unsure_note"
STEP_ISSUES = "issues"
STEP_GAP_NOTE = "gap_note"
STEP_VERDICT_REVISIT = "verdict_revisit"
STEP_ACTION = "action"
STEP_NO_ACTION = "no_action_confirm"
STEP_SEVERITY = "severity"
STEP_CONFIDENCE = "confidence"
STEP_MOVABILITY = "movability"
STEP_MOVABILITY_WARN = "movability_warning"
STEP_TARGET_RECT = "target_rect"
STEP_NOTE = "note"
STEP_DONE = "done"

# Шаги со свободным текстом: GUI включает поле ввода и пропускает печать в визард.
NOTE_STEPS = (STEP_STYLE_NOTE, STEP_UNSURE_NOTE, STEP_GAP_NOTE, STEP_NOTE)


@dataclass
class IssueMark:
    head: str
    rect: list[float] | None = None      # рамка проблемы (человек, опционально)
    cant_point: bool = False             # [X] «не могу указать»
    frame_level: bool = True             # без рамки: evidence = «{record}.frame»


@dataclass
class SaveOutcome:
    kind: str                            # "save" | "skip"
    label: dict | None = None            # v1-запись (build_label)
    detail: dict | None = None           # машинные бакеты рядом (raw sidecar, не метки)


class FrameFlow:
    """Состояние одного кадра. События: key(), set_note(), set_draft_rect(), confirm_rect()."""

    def __init__(self, record: dict, *, annotator_id: str = "", restore: dict | None = None,
                 started: float | None = None, prefill_source: str | None = None):
        self.record = record
        self.annotator_id = annotator_id or str(record.get("_annotator_id") or "")
        self.started = started if started is not None else time.monotonic()
        self.history: list[str] = []
        self.step = STEP_VERDICT
        self.messages: list[str] = []
        self.prefill_source = prefill_source

        self.verdict_key: str | None = None
        self.verdict_revisited = False
        self.style_intentional: bool | None = None
        self.unsure_reason_key: str | None = None
        self.selected: list[IssueMark] = []
        self._last_toggled: str | None = None
        self.draft_rect: list[float] | None = None
        self.chosen_action: str | None = None
        self.no_action = False
        self.severity_key: str | None = None
        self.confidence_key: str | None = None
        self.movability_key: str | None = None
        self.subject_rect: list[float] | None = None
        self.note = ""
        self.contract_gap = False
        self.gap_note = ""
        self.outcome: SaveOutcome | None = None
        if restore:
            self._apply_restore(restore)

    # ------------------------------------------------------------------ utils
    def elapsed(self) -> float:
        return time.monotonic() - self.started

    def _go(self, step: str) -> None:
        self.history.append(self.step)
        self.step = step
        self.messages = []

    def back(self) -> None:
        if self.history:
            # уход с шага gap-заметки (Esc) снимает ФЛАГ, но текст сохраняем
            # в буфере: набранное не уничтожается никогда; повторное [A]
            # вернёт заметку целиком.
            if self.step == STEP_GAP_NOTE:
                self.contract_gap = False
            self.step = self.history.pop()
            self.messages = []
            # откат полустоящих выборов шага, на который вернулись
            if self.step == STEP_ACTION:
                self.chosen_action = None
                self.no_action = False
            elif self.step == STEP_ISSUES:
                self.selected = []
                self._last_toggled = None
                self.draft_rect = None
            elif self.step == STEP_VERDICT:
                self.verdict_key = None
            elif self.step == STEP_GAP_NOTE:
                # уход с шага gap-заметки (Esc) снимает флаг целиком
                self.contract_gap = False
                self.gap_note = ""
                self.note = ""

    def _mark(self, head: str) -> IssueMark | None:
        for mark in self.selected:
            if mark.head == head:
                return mark
        return None

    def _apply_restore(self, restore: dict) -> None:
        """Prefill последней сохранённой записью (B — просмотр/правка, новая запись при сохранении)."""
        label = restore.get("label") or {}
        detail = restore.get("detail") or {}
        beauty = label.get("beauty")
        improvement = label.get("improvement_needed")
        unsure = bool(label.get("unsure"))
        if unsure:
            self.verdict_key = "U"
            reason = detail.get("abstention_reason")
            for key, enum_val, _ in UNSURE_REASONS:
                if enum_val == reason:
                    self.unsure_reason_key = key
        elif improvement is False:
            self.verdict_key = "1"
            if beauty == "ugly":
                self.style_intentional = True
        elif improvement is True:
            self.verdict_key = "3" if beauty == "ugly" else "2"
        for head in label.get("issues") or []:
            self.selected.append(IssueMark(head=head))
            self._last_toggled = head
        self.chosen_action = detail.get("action")
        self.severity_key = detail.get("severity_key")
        self.confidence_key = detail.get("confidence_key")
        self.movability_key = detail.get("movability_key")
        self.subject_rect = detail.get("subject_rect")
        self.note = str(label.get("notes") or "")
        self.contract_gap = bool(detail.get("contract_gap"))
        self.gap_note = str(detail.get("gap_note") or "")
        rect_by_issue = detail.get("issue_rects") or {}
        for mark in self.selected:
            rect = rect_by_issue.get(mark.head)
            if isinstance(rect, list):
                mark.rect = rect
                mark.frame_level = False
        cant = set(detail.get("cant_point_issues") or [])
        for mark in self.selected:
            if mark.head in cant:
                mark.cant_point = True
                mark.frame_level = False

    # ---------------------------------------------------------------- snapshot
    def snapshot(self) -> dict:
        base = {
            "step": self.step,
            "status": "",
            "title": "",
            "options": [],           # [(key, label, active)]
            "legend": [],
            "warnings": list(self.messages),
            "note": self.note,
            "note_required": False,
            "rect_mode": None,       # "issue" | "subject" | None
            "draft_rect": self.draft_rect,
            "rects": self._visible_rects(),
            "done": self.outcome is not None,
        }
        return getattr(self, f"_snap_{self.step}", lambda: base)(base)

    def _visible_rects(self) -> list[dict]:
        out = []
        for mark in self.selected:
            if mark.rect:
                out.append({"rect": mark.rect, "color": "#ff5555", "tag": ISSUE_TITLES.get(mark.head, mark.head)})
        if self.subject_rect:
            out.append({"rect": self.subject_rect, "color": "#39c2ff", "tag": "объект действия"})
        return out

    def _snap_verdict(self, base: dict) -> dict:
        base["title"] = "Кадр в целом?"
        base["options"] = [(k, label, False) for k, _, label in VERDICT_KEYS]
        return base

    def _snap_style_check(self, base: dict) -> dict:
        base["title"] = "Это намеренный стиль (тёмный / силуэт / минимализм)?"
        base["options"] = [("Y", "да — оставить как есть (потребуется заметка)", False),
                           ("N", "нет — это дефект, чиним", False)]
        return base

    def _snap_style_note(self, base: dict) -> dict:
        base["title"] = "Какой это стиль? Одной строкой (обязательно)"
        base["note_required"] = True
        return base

    def _snap_confirm_keep(self, base: dict) -> dict:
        base["title"] = "Хороший кадр — сохранить keep?"
        base["options"] = [
            ("Enter", "сохранить keep (2 нажатия на кадр)", False),
            ("W", "добавить заметку перед сохранением", False),
        ]
        base["legend"] = [
            "передумал? нажми любую букву проблемы из списка:",
            "  " + " · ".join(f"[{k}] {t}" for k, _, t in ISSUE_GROUPS[0][1]),
            "  " + " · ".join(f"[{k}] {t}" for k, _, t in ISSUE_GROUPS[1][1]),
            "  " + " · ".join(f"[{k}] {t}" for k, _, t in ISSUE_GROUPS[2][1]),
        ]
        return base

    def _snap_unsure_reason(self, base: dict) -> dict:
        base["title"] = "Что именно непонятно? (воздержимся с явной причиной)"
        base["options"] = [(k, label, self.unsure_reason_key == k) for k, _, label in UNSURE_REASONS]
        return base

    def _snap_unsure_note(self, base: dict) -> dict:
        enum_val = dict((k, e) for k, e, _ in UNSURE_REASONS).get(self.unsure_reason_key or "", "")
        base["title"] = "Что смущает? Одной строкой (можно пусто — уже записана причина)"
        base["note"] = self.note or (f"не понимаю замысел: {enum_val}" if enum_val else "")
        return base

    def _snap_issues(self, base: dict) -> dict:
        base["title"] = "Что не так? (несколько; рамка мышью — к последней выбранной)"
        options: list[tuple[str, str, bool]] = []
        for group_name, rows in ISSUE_GROUPS:
            for key, head, title in rows:
                mark = self._mark(head)
                suffix = ""
                if mark:
                    if mark.rect:
                        suffix = "  [рамка]"
                    elif mark.cant_point:
                        suffix = "  [не могу указать]"
                    else:
                        suffix = "  [весь кадр]"
                options.append((key, title + suffix, bool(mark)))
        base["options"] = options
        base["legend"] = [
            f"рамка относится к: {ISSUE_TITLES.get(self._last_toggled, '— выбери проблему')}" if self._last_toggled
            else "сначала выбери проблему, потом рисуй рамку",
            "[R] весь кадр · [X] не могу указать (−уверенность) · рамка мышью на картинке",
            "[A] контрактом не выразить — флаг + заметка в gap-отчёт контракта",
        ]
        base["rect_mode"] = "issue"
        return base

    def _snap_gap_note(self, base: dict) -> dict:
        base["title"] = "Контрактом не выразить — что именно? (одной строкой; можно пусто)"
        base["note"] = self.gap_note
        base["legend"] = [
            "уйдёт в gap-отчёт контракта (--report-gaps); текст — raw opinion, НИКОГДА не метка",
            "если проблемы уже выбраны — продолжим с действием; если нет — сохранится как воздержание «кейс не поддержан»",
            "Esc — назад к проблемам (флаг снимется)",
        ]
        return base

    def _key_gap_note(self, key: str) -> None:
        if key in ("Enter", " "):
            self.gap_note = self.note.strip()
            # финальная заметка сыпет тем же текстом — НЕ просим писать заново:
            # на шаге note поле предзаполнено, Enter оставляет как есть.
            self.note = self.gap_note
            if self.selected:
                self._confirm_issue_rect()
                self.draft_rect = None
                self._go(STEP_ACTION)
            else:
                self._finish_gap()

    def _finish_gap(self) -> None:
        """[A] без выбранных проблем: чистое «контрактом не выразить».

        v1-кодирование — честное воздержание (unsure, причина unsupported_case):
        ни проблем, ни действий не выдумываем; текст остаётся raw opinion и
        попадает в gap-отчёт контракта (--report-gaps).
        """
        self.contract_gap = True
        label = build_label(
            record_id=self.record["record_id"],
            image_sha256=self.record["image_sha256"],
            annotator_id=self.annotator_id,
            beauty="unrated",
            improvement_needed=None,
            issues=[],
            actions=[],
            regions=[],
            unsure=True,
            notes=self.gap_note,
            image_path=self.record.get("image_path"),
            provenance=self.record.get("provenance"),
            review_mode=self.record.get("review_mode") if self.record.get("review_mode") in ("blind",) else None,
        )
        detail = {
            "detail_schema": DETAIL_SCHEMA,
            "record_id": self.record["record_id"],
            "verdict": "contract_gap",
            "verdict_key": self.verdict_key if self.verdict_key in ("1", "2", "3") else None,
            "nominal_verdict": self.verdict_key if self.verdict_key in ("1", "2", "3") else "U",
            "contract_gap": True,
            "gap_note": self.gap_note,
            "prefill_source": self.prefill_source,
            "selected_issues": [],
            "issue_rects": {},
            "cant_point_issues": [],
            "action": None,
            "no_supported_action": True,
            "abstention_reason": "unsupported_case",
            "severity_key": None,
            "confidence_key": None,
            "confidence_value": None,
            "movability_key": None,
            "subject_rect": self.subject_rect,
            "dwell_ms": int(self.elapsed() * 1000),
            "dwell_warning": False,
            "note": self.gap_note,
            "target": derive_target(action=None, verdict="unsure", subject_rect=self.subject_rect,
                                    movability_answer=None),
        }
        self.outcome = SaveOutcome(kind="save", label=label, detail=detail)
        self._go(STEP_DONE)

    def _snap_verdict_revisit(self, base: dict) -> dict:
        names = ", ".join(ISSUE_TITLES.get(m.head, m.head) for m in self.selected)
        base["title"] = f"Выбраны проблемы ({names}) — «хороший» больше не подходит"
        base["options"] = [("2", "норм, но улучшить", False), ("3", "плохой", False),
                           ("U", "НЕ ПОНИМАЮ ЗАМЫСЕЛ", False)]
        return base

    def _snap_action(self, base: dict) -> dict:
        base["title"] = "Одно действие (что советовать)?"
        letters = assign_action_letters(candidate_actions([m.head for m in self.selected]))
        base["options"] = [(k, label, False) for k, _, label in letters]
        if not letters:
            base["options"] = []
            base["title"] = "Для выбранных проблем нет поддержанных действий"
            base["legend"] = ["[N] нет подходящего действия (честное отсутствие)"]
        else:
            base["legend"] = ["[N] нет подходящего действия"]
        return base

    def _snap_no_action_confirm(self, base: dict) -> dict:
        names = ", ".join(ISSUE_TITLES.get(m.head, m.head) for m in self.selected)
        base["title"] = (f"Нет поддержанного действия для: {names}. "
                         "Сохранить честно как воздержание (abstain, «кейс не поддержан»)?")
        base["options"] = [("Enter", "да, воздержаться (проблемы останутся в рамках/заметке)", False),
                           ("Esc", "назад — выбрать другое действие", False)]
        return base

    def _snap_severity(self, base: dict) -> dict:
        base["title"] = "Насколько плохо?"
        base["options"] = [(k, label, self.severity_key == k) for k, label in SEVERITY_LABELS.items()]
        if dwell_warning(self.elapsed(), self.verdict_key or ""):
            base["warnings"] = base["warnings"] + [
                f"на кадре {self.elapsed():.1f} сек — точно всё посмотрел? (сохранение не блокируется)"
            ]
        return base

    def _snap_confidence(self, base: dict) -> dict:
        cant = any(m.cant_point for m in self.selected)
        cap = " · при [X] максимум 0.6 / 0.45" if cant else ""
        base["title"] = "Насколько уверен в разметке кадра?" + cap
        base["options"] = [(k, label, self.confidence_key == k) for k, label in CONFIDENCE_LABELS.items()]
        return base

    def _snap_movability(self, base: dict) -> dict:
        base["title"] = "Объект можно передвинуть/убрать?"
        base["options"] = [("Y", "можно", self.movability_key == "Y"),
                           ("N", "нельзя", self.movability_key == "N"),
                           ("?", "не знаю", self.movability_key == "?")]
        return base

    def _snap_movability_warning(self, base: dict) -> dict:
        base["title"] = ("Двигать нельзя — действие «передвинуть объект» неприменимо. "
                         "Лучше вернуться и выбрать другое действие.")
        base["options"] = [("Esc", "назад к выбору действия", False),
                           ("Enter", "всё равно продолжить (экспорт этой записи отклонится)", False)]
        return base

    def _snap_target_rect(self, base: dict) -> dict:
        moving = self.chosen_action in moving_actions()
        if moving:
            base["title"] = "Рамкой покажи ОБЪЕКТ действия (обязательно)"
            base["legend"] = ["рамка мышью → Enter"]
        else:
            base["title"] = "Рамкой покажи главный объект (для контракта действия)"
            base["legend"] = ["рамка мышью → Enter · [R] весь кадр"]
        base["rect_mode"] = "subject"
        return base

    def _snap_note(self, base: dict) -> dict:
        required = self.verdict_key == "3" and self.style_intentional
        if self.note.strip():
            base["title"] = "Заметка (уже написана — Enter оставить как есть, Esc дописать/править)"
        else:
            base["title"] = "Заметка своими словами" + (" (ОБЯЗАТЕЛЬНА — намеренный стиль)" if required else " (можно пусто)")
        base["legend"] = [
            "это raw opinion: хранится рядом, НИКОГДА не превращается в метки;",
            "экспорт release-label требует непустое мнение — без него запись будет отклонена",
        ]
        heads = [m.head for m in self.selected]
        beyond_v1 = [h for h in heads if h in RELEASE_ONLY_ISSUES]
        if beyond_v1 and not self.no_action:
            names = ", ".join(ISSUE_TITLES.get(h, h) for h in beyond_v1)
            base["warnings"].append(
                f"вне v1-словаря: {names} — сохранится в detail; "
                "экспорт release-label честно отклонит запись (v1/адаптер не знают этих heads)"
            )
            if self.chosen_action not in V1_ACTION_SET:
                base["warnings"].append(
                    "действие тоже вне v1-словаря: v1-записи не будет, только detail"
                )
        for warning in action_coverage_warnings([m.head for m in self.selected], self.chosen_action or ""):
            base["warnings"].append("санити: " + warning)
        return base

    def _snap_done(self, base: dict) -> dict:
        base["title"] = "Сохранено" if self.outcome else ""
        return base

    # ----------------------------------------------------------------- events
    def set_note(self, text: str) -> None:
        self.note = text

    def set_draft_rect(self, rect: list[float] | None) -> None:
        self.draft_rect = rect

    def key(self, key: str) -> None:
        handler = getattr(self, f"_key_{self.step}", None)
        if handler:
            handler(key)

    def enter(self) -> None:
        self.key("Enter")

    # verdict
    def _key_verdict(self, key: str) -> None:
        if key == "S":
            self.outcome = SaveOutcome(kind="skip")
            self._go(STEP_DONE)
            return
        if key in ("1", "2", "3", "U"):
            self.verdict_key = key
            self._go(
                {
                    "1": STEP_CONFIRM_KEEP,
                    "2": STEP_ISSUES,
                    "3": STEP_STYLE,
                    "U": STEP_UNSURE_REASON,
                }[key]
            )

    def _key_style_check(self, key: str) -> None:
        if key == "Y":
            self.style_intentional = True
            self._go(STEP_STYLE_NOTE)
        elif key == "N":
            self.style_intentional = False
            self._go(STEP_ISSUES)

    def _key_style_note(self, key: str) -> None:
        if key == "Enter":
            if not self.note.strip():
                self.messages = ["заметка обязательна: контракт ugly+keep требует объяснения (intentional mood)"]
                return
            self._finish_keep(beauty="ugly")

    def _key_confirm_keep(self, key: str) -> None:
        if key == "Enter":
            self._finish_keep(beauty="beautiful")
        elif key == "W":
            self._go(STEP_NOTE)
        elif key.upper() in ISSUE_KEYS:
            # «передумал»: уходим в проблемы; вердикт переспросим (блок good+issues).
            head = ISSUE_KEYS[key.upper()]
            if not self._mark(head):
                self.selected.append(IssueMark(head=head))
                self._last_toggled = head
            self.verdict_revisited = True
            self._go(STEP_ISSUES)

    def _key_unsure_reason(self, key: str) -> None:
        if key in dict((k, e) for k, e, _ in UNSURE_REASONS):
            self.unsure_reason_key = key
            self._go(STEP_UNSURE_NOTE)

    def _key_unsure_note(self, key: str) -> None:
        if key == "Enter":
            reason = dict((k, e) for k, e, _ in UNSURE_REASONS).get(self.unsure_reason_key or "", "missing_evidence")
            label_text = dict((k, t) for k, _, t in UNSURE_REASONS).get(self.unsure_reason_key or "", "")
            note = self.note.strip() or f"не понимаю замысел: {label_text or reason}"
            self.note = note
            self._finish_unsure(abstention_reason=reason, nominal_verdict="unsure")

    def _key_issues(self, key: str) -> None:
        upper = key.upper()
        if upper in ISSUE_KEYS:
            head = ISSUE_KEYS[upper]
            mark = self._mark(head)
            if mark:
                self.selected.remove(mark)
            else:
                self.selected.append(IssueMark(head=head))
            self._last_toggled = head if not mark else None
            if self._last_toggled is None:
                self._last_toggled = self.selected[-1].head if self.selected else None
            return
        if key == "R" and self._last_toggled:
            mark = self._mark(self._last_toggled)
            if mark:
                mark.rect = None
                mark.cant_point = False
                mark.frame_level = True
                self.draft_rect = None
            return
        if key == "X" and self._last_toggled:
            mark = self._mark(self._last_toggled)
            if mark:
                mark.rect = None
                mark.cant_point = True
                mark.frame_level = False
                self.draft_rect = None
            return
        if upper == "A":
            # «контрактом не выразить»: флаг + заметка в gap-отчёт. Буква A —
            # потому что G занята «пересветом» на этом же экране. Набранный
            # ранее текст НЕ стирается никогда (Esc тоже его сохраняет).
            self.contract_gap = True
            self._go(STEP_GAP_NOTE)
            return
        if key in ("Enter", " "):
            if not self.selected:
                self.messages = ["нужна хотя бы одна проблема — или Esc назад и выбери [U]/[S]"]
                return
            self._confirm_issue_rect()
            self.draft_rect = None
            if self.verdict_revisited:
                # блок «issues + good»: «хороший» больше недоступен, переспрашиваем 2/3/U
                self._go(STEP_VERDICT_REVISIT)
            else:
                self._go(STEP_ACTION)

    def _confirm_issue_rect(self) -> None:
        """Enter в шаге issues при нарисованной рамке прикрепляет её к последней issue."""
        if self.step == STEP_ISSUES and self.draft_rect and self._last_toggled:
            mark = self._mark(self._last_toggled)
            if mark:
                mark.rect = self.draft_rect
                mark.cant_point = False
                mark.frame_level = False
            self.draft_rect = None

    def _key_verdict_revisit(self, key: str) -> None:
        if key in ("2", "3"):
            self.verdict_key = key
            self.verdict_revisited = False
            self._go(STEP_ACTION)
        elif key == "U":
            self.verdict_revisited = False
            self._go(STEP_UNSURE_REASON)

    def _key_action(self, key: str) -> None:
        if key == "N":
            self.no_action = True
            self._go(STEP_NO_ACTION)
            return
        letters = assign_action_letters(candidate_actions([m.head for m in self.selected]))
        chosen = {k: a for k, a, _ in letters}
        if key in chosen:
            self.chosen_action = chosen[key]
            self._go(STEP_SEVERITY)

    def _key_no_action_confirm(self, key: str) -> None:
        if key == "Enter":
            note = self.note.strip() or (
                "нет поддержанного действия для: "
                + ", ".join(ISSUE_TITLES.get(m.head, m.head) for m in self.selected)
            )
            self.note = note
            self._finish_unsure(abstention_reason="unsupported_case", nominal_verdict=self.verdict_key or "2")
        # Esc → back() обрабатывает GUI

    def _key_severity(self, key: str) -> None:
        if key in SEVERITY_BY_KEY:
            self.severity_key = key
            self._go(STEP_CONFIDENCE)

    def _key_confidence(self, key: str) -> None:
        if key in CONFIDENCE_BY_KEY:
            self.confidence_key = key
            if self.no_action or self.chosen_action is None:
                self._go(STEP_NOTE)
            elif self.chosen_action in moving_actions():
                self._go(STEP_MOVABILITY)
            elif self.chosen_action in resolved_target_actions():
                self._go(STEP_TARGET_RECT)
            else:
                self._go(STEP_NOTE)

    def _key_movability(self, key: str) -> None:
        if key in MOVABILITY_ANSWERS:
            self.movability_key = key
            if key in ("N", "?"):
                self._go(STEP_MOVABILITY_WARN)
            else:
                self._go(STEP_TARGET_RECT)

    def _key_movability_warning(self, key: str) -> None:
        if key == "Enter":
            self._go(STEP_TARGET_RECT)

    def _key_target_rect(self, key: str) -> None:
        moving = self.chosen_action in moving_actions()
        if key == "Enter" and self.draft_rect:
            self.subject_rect = self.draft_rect
            self.draft_rect = None
            self._go(STEP_NOTE)
        elif key == "R" and not moving:
            self.subject_rect = None  # авто: регион [0,0,1,1] подставит derive_target
            self.draft_rect = None
            self._go(STEP_NOTE)

    def _key_note(self, key: str) -> None:
        if key == "Enter":
            if self.verdict_key == "3" and self.style_intentional and not self.note.strip():
                self.messages = ["заметка обязательна (intentional mood)"]
                return
            self._finish()

    # -------------------------------------------------------------- finishing
    def _finish_keep(self, *, beauty: str) -> None:
        label = build_label(
            record_id=self.record["record_id"],
            image_sha256=self.record["image_sha256"],
            annotator_id=self.annotator_id,
            beauty=beauty,
            improvement_needed=False,
            issues=[],
            actions=[KEEP_ACTION],
            regions=[],
            unsure=False,
            notes=self.note,
            image_path=self.record.get("image_path"),
            provenance=self.record.get("provenance"),
            review_mode=self.record.get("review_mode") if self.record.get("review_mode") in ("blind",) else None,
        )
        detail = {
            "detail_schema": DETAIL_SCHEMA,
            "record_id": self.record["record_id"],
            "verdict": "good",
            "verdict_key": self.verdict_key,
            "selected_issues": [],
            "action": KEEP_ACTION,
            "severity_key": None,
            "confidence_key": None,
            "confidence_value": None,
            "movability_key": None,
            "subject_rect": None,
            "dwell_ms": int(self.elapsed() * 1000),
            "dwell_warning": dwell_warning(self.elapsed(), self.verdict_key or ""),
            "note": self.note,
            "style_intentional": self.style_intentional,
            "target": derive_target(action=KEEP_ACTION, verdict="good", subject_rect=None,
                                    movability_answer=None),
        }
        self.outcome = SaveOutcome(kind="save", label=label, detail=detail)
        self._go(STEP_DONE)

    def _finish_unsure(self, *, abstention_reason: str, nominal_verdict: str) -> None:
        regions = [
            {"role": "problem", "rect": mark.rect, "label": ISSUE_TITLES.get(mark.head, mark.head)}
            for mark in self.selected if mark.rect
        ]
        label = build_label(
            record_id=self.record["record_id"],
            image_sha256=self.record["image_sha256"],
            annotator_id=self.annotator_id,
            beauty="unrated",
            improvement_needed=None,
            issues=[],
            actions=[],
            regions=regions,
            unsure=True,
            notes=self.note,
            image_path=self.record.get("image_path"),
            provenance=self.record.get("provenance"),
            review_mode=self.record.get("review_mode") if self.record.get("review_mode") in ("blind",) else None,
        )
        detail = {
            "detail_schema": DETAIL_SCHEMA,
            "record_id": self.record["record_id"],
            "verdict": "unsure",
            "verdict_key": nominal_verdict if nominal_verdict in ("1", "2", "3") else "U",
            "nominal_verdict": nominal_verdict,
            "selected_issues": [m.head for m in self.selected],
            "issue_rects": {m.head: m.rect for m in self.selected if m.rect},
            "cant_point_issues": [m.head for m in self.selected if m.cant_point],
            "action": None,
            "no_supported_action": abstention_reason == "unsupported_case",
            "abstention_reason": abstention_reason,
            "severity_key": None,
            "confidence_key": None,
            "confidence_value": None,
            "movability_key": None,
            "subject_rect": self.subject_rect,
            "dwell_ms": int(self.elapsed() * 1000),
            "dwell_warning": dwell_warning(self.elapsed(), nominal_verdict),
            "note": self.note,
            "contract_gap": self.contract_gap,
            "gap_note": self.gap_note if self.contract_gap else "",
            "prefill_source": self.prefill_source,
            "target": derive_target(action=None, verdict="unsure", subject_rect=self.subject_rect,
                                    movability_answer=None),
        }
        self.outcome = SaveOutcome(kind="save", label=label, detail=detail)
        self._go(STEP_DONE)

    def _finish(self) -> None:
        cant = any(m.cant_point for m in self.selected)
        conf = confidence_value(self.confidence_key or "2", cant)
        sev = severity_value(self.severity_key or "2")
        regions = []
        for mark in self.selected:
            if mark.rect:
                regions.append({"role": "problem", "rect": mark.rect,
                                "label": ISSUE_TITLES.get(mark.head, mark.head)})
        if self.subject_rect:
            regions.append({"role": "subject", "rect": self.subject_rect, "label": ""})
        beauty = "ugly" if self.verdict_key == "3" else "borderline"
        selected_heads = [m.head for m in self.selected]
        v1_issues = [h for h in selected_heads if h in V1_ISSUE_SET]
        action_in_v1 = self.chosen_action in V1_ACTION_SET

        label: dict | None
        if v1_issues and action_in_v1:
            # v1-словарь может закодировать вердикт (возможно подмножеством heads)
            label = build_label(
                record_id=self.record["record_id"],
                image_sha256=self.record["image_sha256"],
                annotator_id=self.annotator_id,
                beauty=beauty,
                improvement_needed=True,
                issues=v1_issues,
                actions=[self.chosen_action],
                regions=regions,
                unsure=False,
                notes=self.note,
                image_path=self.record.get("image_path"),
                provenance=self.record.get("provenance"),
                review_mode=self.record.get("review_mode") if self.record.get("review_mode") in ("blind",) else None,
            )
        else:
            # Технические heads / технические действия вне v1-словаря: решённый
            # needs_fix в v1 закодировать нельзя (improvement_needed=true требует
            # v1-issue и v1-action). Ничего не выдумываем: v1-записи нет, полная
            # правда — в detail; экспорт это честно покажет как REJECTED.
            label = None
        detail = {
            "detail_schema": DETAIL_SCHEMA,
            "record_id": self.record["record_id"],
            "verdict": "needs_fix",
            "verdict_key": self.verdict_key,
            "selected_issues": selected_heads,
            "v1_issues": v1_issues,
            "v1_label_written": label is not None,
            "v1_incomplete": label is not None and len(v1_issues) != len(selected_heads),
            "issue_rects": {m.head: m.rect for m in self.selected if m.rect},
            "cant_point_issues": [m.head for m in self.selected if m.cant_point],
            "severity_key": self.severity_key,
            "severity_value": sev,
            "confidence_key": self.confidence_key,
            "confidence_value": conf,
            "confidence_capped_by_cant_point": cant,
            "action": self.chosen_action,
            "action_issue_ids": selected_heads,
            "sanity_warnings": action_coverage_warnings(selected_heads, self.chosen_action or ""),
            "movability_key": self.movability_key,
            "subject_rect": self.subject_rect,
            "dwell_ms": int(self.elapsed() * 1000),
            "dwell_warning": dwell_warning(self.elapsed(), self.verdict_key or ""),
            "note": self.note,
            "contract_gap": self.contract_gap,
            "gap_note": self.gap_note if self.contract_gap else "",
            "prefill_source": self.prefill_source,
            "target": derive_target(action=self.chosen_action, verdict="needs_fix",
                                    subject_rect=self.subject_rect,
                                    movability_answer=self.movability_key),
        }
        self.outcome = SaveOutcome(kind="save", label=label, detail=detail)
        self._go(STEP_DONE)


def assemble_issue_evidence(detail: dict, *, label_issues: list[str] | None = None) -> dict[str, dict]:
    """Машина: evidence-бакеты для экспорта из деталей.

    ``label_issues`` — issues, реально вошедшие в v1-запись (экспорт идёт через
    v1→release цепочку, поэтому evidence собирается ровно по v1-подмножеству).
    """
    record_id = detail["record_id"]
    heads = list(label_issues) if label_issues is not None else list(detail.get("selected_issues") or [])
    rects = detail.get("issue_rects") or {}
    out: dict[str, dict] = {}
    for index, head in enumerate(heads):
        rect = rects.get(head)
        entry = {
            "severity": detail.get("severity_value"),
            "confidence": detail.get("confidence_value"),
            "evidence_refs": [evidence_ref(record_id, index, isinstance(rect, list))],
        }
        if isinstance(rect, list):
            entry["rect"] = rect
        out[head] = entry
    return out


# --------------------------------------------------------------------------- #
# Сид-план и согласие QC.
# --------------------------------------------------------------------------- #

def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def append_jsonl(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        import os as _os

        _os.fsync(handle.fileno())


def plan_seed_positions(queue_len: int, seeds_len: int) -> list[int]:
    """Детерминированные позиции вставки сидов: 5–7% очереди, равномерно.

    Возвращает индексы очереди, ПОСЛЕ которых вставляется сид.
    """
    if queue_len <= 0 or seeds_len <= 0:
        return []
    lower = max(1, math.floor(queue_len * 0.05))
    upper = max(1, math.ceil(queue_len * 0.07))
    target = min(max(round(queue_len * 0.06), lower), upper, seeds_len)
    if queue_len < 10:
        target = min(1, seeds_len)
    return [((k + 1) * queue_len) // (target + 1) for k in range(target)]


def interleave_seeds(queue: list[dict], seeds: list[dict]) -> list[dict]:
    """Сид-записи выглядят как обычные кадры очереди (одинаковые поля, без пометки)."""
    if not seeds:
        return list(queue)
    positions = plan_seed_positions(len(queue), len(seeds))
    items = list(queue)
    for seed_index, after in enumerate(positions):
        seed = dict(seeds[seed_index % len(seeds)])
        seed["_is_seed"] = True  # служебный флаг потребителя, в UI/файлы не попадает
        items.insert(after + seed_index + 1, seed)
    return items


def qc_entry(detail: dict, label: dict, expected: dict) -> dict:
    actual_issues = detail.get("selected_issues") or label.get("issues") or []
    actual_action = detail.get("action") if detail.get("action") != KEEP_ACTION else None
    if detail.get("verdict") == "unsure":
        actual_action = None
    return {
        "schema": QC_SCHEMA,
        "record_id": detail.get("record_id"),
        "expected": {
            "verdict": expected.get("expected_verdict"),
            "issue": expected.get("expected_issue"),
            "action": expected.get("expected_action"),
        },
        "actual": {
            "verdict": detail.get("verdict"),
            "issues": actual_issues,
            "action": actual_action,
        },
        "matched": {
            "verdict": detail.get("verdict") == expected.get("expected_verdict"),
            "issue": expected.get("expected_issue") in (actual_issues or []),
            "action": actual_action == expected.get("expected_action"),
        },
        "label": label,
        "detail": detail,
    }


def _latest_by_record(rows: list[dict]) -> dict[str, dict]:
    """Одна запись на кадр: повторная запись того же record_id — ревизия решения."""
    latest: dict[str, dict] = {}
    for row in rows:
        rid = str(row.get("record_id") or "").strip()
        if rid:
            latest[rid] = row
    return latest


def cohen_kappa(pairs: list[tuple[str, str]]) -> float | None:
    """Cohen's kappa по парам категорий; None, если сравнение не определено."""
    if len(pairs) < 2:
        return None
    categories = sorted({c for pair in pairs for c in pair})
    if len(categories) < 2:
        return None  # нет вариативности — kappa не определена
    n = len(pairs)
    observed = sum(1 for a, b in pairs if a == b) / n
    expected = sum((sum(1 for a, _ in pairs if a == c) / n)
                   * (sum(1 for _, b in pairs if b == c) / n) for c in categories)
    if expected >= 1.0:
        return None
    return (observed - expected) / (1 - expected)


def filter_only_ids(queue: list[dict], seeds: list[dict],
                    only_ids: set[str]) -> tuple[list[dict], list[dict], list[str]]:
    """Обход только выбранных записей (calibration subset, DATA-009).

    Возвращает (queue, seeds, missing): отсутствующие id — честный отказ, а не
    тихий пропуск — subset обязан быть полностью представлен в очереди.
    """
    known = {str(r.get("record_id") or "") for r in queue} | {str(s.get("record_id") or "") for s in seeds}
    missing = sorted(only_ids - known)
    return ([r for r in queue if str(r.get("record_id") or "") in only_ids],
            [s for s in seeds if str(s.get("record_id") or "") in only_ids],
            missing)


def reviewer_agreement_report(*, labels_a: list[dict], details_a: list[dict],
                              labels_b: list[dict], details_b: list[dict],
                              name_a: str = "reviewer-1", name_b: str = "reviewer-2") -> str:
    """Согласие двух независимых проходов — механика согласия, не качество и не gold.

    Правила независимости (как в pilot_agreement_report.py): assisted-запись не
    является независимым ратером; один ратер — одна запись на кадр (повторная
    запись — ревизия, в расчёт идёт последняя); оба прохода должны быть blind.
    """
    assisted = sum(1 for r in [*labels_a, *labels_b] if r.get("assisted"))
    lab_a = _latest_by_record([r for r in labels_a if not r.get("assisted")])
    lab_b = _latest_by_record([r for r in labels_b if not r.get("assisted")])
    det_a = _latest_by_record(details_a)
    det_b = _latest_by_record(details_b)
    common = sorted(set(lab_a) & set(lab_b))
    lines = [
        f"Согласие двух проходов: {name_a} vs {name_b} (blind, механика — не качество/gold)",
        f"  записей: {name_a} {len(lab_a)}, {name_b} {len(lab_b)}, общих {len(common)}"
        + (f"; assisted исключены: {assisted}" if assisted else ""),
    ]
    if not common:
        lines.append("  общих записей нет — согласие не измеряется")
        return "\n".join(lines)

    verdict_pairs: list[tuple[str, str]] = []
    action_pairs: list[tuple[object, object]] = []
    jaccards: list[float] = []
    issue_exact = 0
    no_detail = 0
    mismatches: list[tuple[str, str, str]] = []
    for rid in common:
        a, b = det_a.get(rid, {}), det_b.get(rid, {})
        if not a or not b:
            no_detail += 1
        va = str(a.get("verdict_key") or a.get("verdict") or "?")
        vb = str(b.get("verdict_key") or b.get("verdict") or "?")
        verdict_pairs.append((va, vb))
        if va != vb:
            mismatches.append((rid, va, vb))
        aa = a.get("action") if a.get("action") != KEEP_ACTION else None
        ab = b.get("action") if b.get("action") != KEEP_ACTION else None
        if aa or ab:
            action_pairs.append((aa, ab))
        issues_a = set(a.get("selected_issues") or lab_a[rid].get("issues") or [])
        issues_b = set(b.get("selected_issues") or lab_b[rid].get("issues") or [])
        if issues_a == issues_b:
            issue_exact += 1
        union = issues_a | issues_b
        if union:
            jaccards.append(len(issues_a & issues_b) / len(union))

    n = len(common)
    verdict_ok = sum(1 for a, b in verdict_pairs if a == b)
    kappa = cohen_kappa(verdict_pairs)
    lines.append(f"  verdict:  {verdict_ok}/{n} совпали = {verdict_ok / n:.0%}"
                 + (f", Cohen kappa {kappa:.2f}" if kappa is not None
                    else ", kappa не определена (нет вариативности)"))
    if action_pairs:
        action_ok = sum(1 for a, b in action_pairs if a == b)
        lines.append(f"  action:   {action_ok}/{len(action_pairs)} совпали "
                     "(кадры, где хоть один выбрал действие)")
    if jaccards:
        lines.append(f"  issues:   {issue_exact}/{n} множества совпали, "
                     f"средний Jaccard {sum(jaccards) / len(jaccards):.2f}")
    if no_detail:
        lines.append(f"  внимание: у {no_detail} пар(ы) нет detail хотя бы с одной стороны — "
                     "вердикт по ним неопределён (? в паре)")
    if mismatches:
        lines.append("  расхождения вердикта:")
        for rid, va, vb in mismatches[:20]:
            lines.append(f"    {rid}: {name_a} {va} vs {name_b} {vb}")
        if len(mismatches) > 20:
            lines.append(f"    … и ещё {len(mismatches) - 20}")
    lines.append("  правила: повторная запись одного ратера = ревизия (берётся последняя); "
                 "assisted не считается; оба прохода — blind, без показа чужих ответов.")
    return "\n".join(lines)


def gaps_report(detail_rows: list[dict]) -> str:
    """Gap-отчёт: записи «контрактом не выразить» — вход на доработку контракта v2."""
    gaps = [r for r in detail_rows if r.get("contract_gap")]
    if not gaps:
        return "gap-отчёт: пусто — все записи выразимы текущим контрактом"
    lines = [f"gap-отчёт: {len(gaps)} запис(ей) «контрактом не выразить» "
             "(на доработку контракта v2, см. data-quality-analysis-v1.md §4.6)", ""]
    for r in gaps:
        note = (r.get("gap_note") or "").strip() or "—"
        issues = ", ".join(r.get("selected_issues") or []) or "—"
        lines.append(f"- {r.get('record_id')} [{r.get('verdict')}]: {note} (issues: {issues})")
    return "\n".join(lines)


def agreement_report(qc_rows: list[dict]) -> str:
    if not qc_rows:
        return "QC: нет записанных результатов сидов (qc.jsonl пуст или отсутствует)."
    total = len(qc_rows)
    verdict_ok = sum(1 for r in qc_rows if r["matched"]["verdict"])
    issue_ok = sum(1 for r in qc_rows if r["matched"]["issue"])
    action_ok = sum(1 for r in qc_rows if r["matched"]["action"])
    lines = [
        f"QC agreement по {total} сидам:",
        f"  verdict  (needs_fix): {verdict_ok}/{total} = {verdict_ok / total:.0%}",
        f"  issue    (ожидаемая в выбранных): {issue_ok}/{total} = {issue_ok / total:.0%}",
        f"  action   (выбрано ожидаемое): {action_ok}/{total} = {action_ok / total:.0%}",
    ]
    mismatches = [r for r in qc_rows if not (r["matched"]["verdict"] and r["matched"]["issue"] and r["matched"]["action"])]
    if mismatches:
        lines.append("  расхождения:")
        for row in mismatches:
            lines.append(
                f"    {row['record_id']}: verdict {row['actual']['verdict']} "
                f"(ожидался {row['expected']['verdict']}), issues {row['actual']['issues']} "
                f"(ожидалась {row['expected']['issue']}), action {row['actual']['action']} "
                f"(ожидалось {row['expected']['action']})"
            )
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Сессия и хранилища.
# --------------------------------------------------------------------------- #

class FastSession:
    """session.json в каталоге очереди: закрыл и продолжил; queue.jsonl не меняется."""

    def __init__(self, path: Path):
        self.path = path

    def load(self) -> dict | None:
        if not self.path.exists():
            return None
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return None
        if data.get("schema") != SESSION_SCHEMA:
            return None
        return data

    def save(self, state: dict) -> None:
        payload = dict(state)
        payload["schema"] = SESSION_SCHEMA
        self.path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")


def build_session_state(*, queue_path: Path, seeds_path: Path | None, annotator_id: str,
                        queue: list[dict], seeds: list[dict]) -> dict:
    items = interleave_seeds(queue, seeds)
    return {
        "annotator_id": annotator_id,
        "queue_path": str(queue_path),
        "queue_sha256": sha256_file(queue_path),
        "seeds_path": str(seeds_path) if seeds_path else None,
        "seeds_sha256": sha256_file(seeds_path) if seeds_path and seeds_path.exists() else None,
        "record_ids": [r["record_id"] for r in items],
        "index": 0,
        "done": [],
        "skipped": [],
        "updated_at": None,
    }


def queue_identity_problems(*, queue: list[dict], seeds: list[dict], labels: list[dict],
                            details: list[dict]) -> list[str]:
    """Идентичность записи: record_id ↔ ровно один кадр; запись — своему кадру.

    Корневая причина ремонта 2026-09-27 (DATA-008): дубль record_id в очереди
    молча резолвился в ПОСЛЕДНЮЮ строку (``items_by_id`` — dict по id), вторая
    позиция обхода показывала чужой кадр и сохраняла ответ под чужим id.
    Любое нарушение 1:1 — отказ, а не «тихая последняя победа».
    """
    problems: list[str] = []
    by_id: dict[str, tuple[str, int, object]] = {}
    for source, rows in (("queue", queue), ("seeds", seeds)):
        for position, row in enumerate(rows, 1):
            rid = str(row.get("record_id") or "").strip()
            if not rid:
                problems.append(f"{source}[{position}]: пустой record_id")
                continue
            sha = row.get("image_sha256")
            seen = by_id.get(rid)
            if seen is None:
                by_id[rid] = (source, position, sha)
            elif seen[2] != sha:
                problems.append(
                    f"{rid}: один record_id — разные кадры "
                    f"({seen[0]}[{seen[1]}] sha {seen[2]} и {source}[{position}] sha {sha}); "
                    "нужен уникальный record_id на кадр")
            else:
                problems.append(f"{rid}: строка повторяется ({seen[0]}[{seen[1]}] и {source}[{position}])")
    for store, rows in (("fast_labels", labels), ("fast_details", details)):
        for position, row in enumerate(rows, 1):
            rid = str(row.get("record_id") or "").strip()
            seen = by_id.get(rid)
            if seen is None:
                problems.append(
                    f"{store}[{position}]: record_id {rid!r} отсутствует в этой очереди/сидах "
                    "(запись из другой очереди?)")
                continue
            sha = row.get("image_sha256")
            if sha and seen[2] and sha != seen[2]:
                problems.append(
                    f"{store}[{position}]: запись {rid!r} привязана к другому кадру "
                    f"(sha {sha} ≠ {seen[2]})")
    return problems


def latest_answers(record_id: str, labels: list[dict], details: list[dict]) -> dict | None:
    """Последняя сохранённая запись кадра (для префилла при просмотре назад)."""
    label = None
    for row in labels:
        if row.get("record_id") == record_id:
            label = row
    if label is None:
        return None
    detail = {}
    for row in details:
        if row.get("record_id") == record_id:
            detail = row
    return {"label": label, "detail": detail}


# --------------------------------------------------------------------------- #
# Экспорт release-label (fail-closed, как DATA-005).
# --------------------------------------------------------------------------- #

ADAPTER = TOOLS / "release_label_adapter.py"


def run_adapter(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(ADAPTER), *args], capture_output=True, text=True, timeout=180)


def export_labels(*, labels: list[dict], details: list[dict], queue_rows: list[dict],
                  seeds_rows: list[dict], out_dir: Path) -> dict:
    """По каждой записи: config → adapter convert → validate. REJECTED → показать и НЕ записывать."""
    import tempfile

    out_dir.mkdir(parents=True, exist_ok=True)
    queue_by_id = {r["record_id"]: r for r in queue_rows}
    seeds_by_id = {r["record_id"]: r for r in seeds_rows}
    detail_by_id: dict[str, dict] = {}
    for row in details:
        detail_by_id[row["record_id"]] = row

    exported: list[str] = []
    rejected: list[dict] = []
    for label in labels:
        record_id = label["record_id"]
        detail = detail_by_id.get(record_id, {})
        source = queue_by_id.get(record_id) or seeds_by_id.get(record_id) or {}
        if not source:
            # fail-closed (DATA-007): непривязанную запись нельзя экспортировать
            rejected.append({
                "record_id": record_id,
                "reason": "record_id отсутствует в этой очереди/сидах — запись не привязана к кадру",
            })
            continue
        source_sha = source.get("image_sha256")
        if source_sha and label.get("image_sha256") and source_sha != label.get("image_sha256"):
            rejected.append({
                "record_id": record_id,
                "reason": (f"запись привязана к другому кадру (sha {label.get('image_sha256')} "
                           f"≠ {source_sha}) — экспорт запрещён"),
            })
            continue
        if detail.get("v1_incomplete"):
            # v1-запись неполна (выход за 8-issue v1-словарь): экспорт молча
            # потерял бы heads — отказ до адаптера, запись уже сохранена в detail.
            beyond = [h for h in (detail.get("selected_issues") or []) if h not in V1_ISSUE_SET]
            rejected.append({
                "record_id": record_id,
                "reason": (f"выход за v1-словарь (heads только в release-контракте): {beyond}; "
                           "полная разметка сохранена в fast_details.jsonl"),
            })
            continue
        try:
            config = build_conversion_config(
                label,
                issue_evidence=(assemble_issue_evidence(detail, label_issues=list(label.get("issues") or []))
                                if detail.get("verdict") == "needs_fix" else None),
                target=detail.get("target") or derive_target(
                    action=detail.get("action"), verdict=detail.get("verdict") or "good",
                    subject_rect=detail.get("subject_rect"), movability_answer=detail.get("movability_key"),
                ),
                review_ids=[record_id],
                abstention_reason=detail.get("abstention_reason") if bool(label.get("unsure")) else None,
                captured_at=str(source.get("captured_at") or "").strip() or None,
                source_family_id=source.get("source_family_id"),
                frame_id=source.get("package_record_id") or record_id,
            )
        except ReleaseConfigError as exc:
            rejected.append({"record_id": record_id, "reason": str(exc)})
            continue

        with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
            tmp_dir = Path(tmp)
            review_file = tmp_dir / "review.json"
            config_file = tmp_dir / "config.json"
            review_file.write_text(json.dumps(label, ensure_ascii=False), encoding="utf-8")
            config_file.write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")
            out_file = out_dir / f"{config['release_record_id']}.json"
            converted = run_adapter("convert", "--review", str(review_file), "--config",
                                    str(config_file), "--out", str(out_file))
            if converted.returncode != 0:
                rejected.append({"record_id": record_id,
                                 "reason": converted.stderr.strip() or converted.stdout.strip()})
                if out_file.exists():
                    out_file.unlink()
                continue
            validated = run_adapter("validate", "--label", str(out_file))
            if validated.returncode != 0:
                rejected.append({"record_id": record_id,
                                 "reason": "validate: " + (validated.stdout.strip() or validated.stderr.strip())})
                if out_file.exists():
                    out_file.unlink()
                continue
            exported.append(config["release_record_id"])

    return {"exported": exported, "rejected": rejected}


# --------------------------------------------------------------------------- #
# GUI (тонкий tkinter-слой; вся логика выше — чистые функции/FSM).
# --------------------------------------------------------------------------- #

def run_gui(args: argparse.Namespace) -> int:
    import tkinter as tk

    queue_path: Path = args.queue
    queue = load_jsonl(queue_path)
    if not queue:
        print(f"очередь пуста или не читается: {queue_path}", file=sys.stderr)
        return 1
    queue_dir = queue_path.parent
    store_path = args.store or (queue_dir / "fast_labels.jsonl")
    details_path = args.details or (queue_dir / "fast_details.jsonl")
    qc_path = args.qc or (queue_dir / "qc.jsonl")
    seeds_path = args.seeds or (queue_dir / "seeds.jsonl")
    session_path = args.session or (queue_dir / "session.json")

    seeds = load_jsonl(seeds_path) if args.with_seeds else []
    identity = queue_identity_problems(queue=queue, seeds=load_jsonl(seeds_path),
                                       labels=load_labels(store_path),
                                       details=load_jsonl(details_path))
    if identity:
        # fail-closed: с дублем record_id вторая позиция молча показала бы чужой кадр
        print(f"ОТКАЗ: нарушена идентичность записей ({queue_path}):", file=sys.stderr)
        for problem in identity:
            print(f"  - {problem}", file=sys.stderr)
        return 2
    if getattr(args, "only_ids", None):
        wanted = {line.strip() for line in Path(args.only_ids).read_text(encoding="utf-8").splitlines()
                  if line.strip() and not line.strip().startswith("#")}
        queue, seeds, missing = filter_only_ids(queue, seeds, wanted)
        if missing:
            print(f"ОТКАЗ: --only-ids: нет в очереди/сидах: {', '.join(missing)}", file=sys.stderr)
            return 2
        if not queue:
            print("ОТКАЗ: --only-ids: выборка пуста", file=sys.stderr)
            return 2
    prefill_by_id = {}
    if getattr(args, "prefill", None):
        for row in load_jsonl(Path(args.prefill)):
            if row.get("record_id"):
                prefill_by_id[row["record_id"]] = row
    session = FastSession(session_path)
    state = session.load()
    fresh = build_session_state(queue_path=queue_path, seeds_path=seeds_path if seeds else None,
                                annotator_id=args.annotator_id, queue=queue, seeds=seeds)
    if state and state.get("queue_sha256") == fresh["queue_sha256"] and (
            state.get("seeds_sha256") == fresh["seeds_sha256"]):
        state["annotator_id"] = args.annotator_id
    else:
        state = fresh
    seed_ids = {s["record_id"] for s in seeds}
    items_by_id = {r["record_id"]: r for r in queue}
    seeds_by_id = {s["record_id"]: s for s in seeds}
    done = set(state.get("done") or [])
    skipped = set(state.get("skipped") or [])
    record_ids: list[str] = state["record_ids"]

    def record_for(rid: str) -> dict:
        row = dict(items_by_id.get(rid) or seeds_by_id.get(rid) or {})
        row["_annotator_id"] = args.annotator_id
        if rid in seed_ids:
            expected = {k: row.get(k) for k in ("expected_verdict", "expected_issue", "expected_action")}
            row["_seed_expected"] = expected
        return row

    def index_of_first_pending() -> int:
        for i, rid in enumerate(record_ids):
            if rid not in done and rid not in skipped:
                return i
        return len(record_ids) - 1 if record_ids else 0

    index = state.get("index") if state.get("index") is not None else 0
    if record_ids and record_ids[index] in done | skipped:
        index = index_of_first_pending()

    app = _FastApp(
        tk.Tk(),
        record_ids=record_ids,
        record_for=record_for,
        is_seed=lambda rid: rid in seed_ids,
        labels_path=store_path,
        details_path=details_path,
        qc_path=qc_path,
        seeds_by_id=seeds_by_id,
        on_progress=lambda i, d, s: (
            state.__setitem__("index", i),
            state.__setitem__("done", sorted(d)),
            state.__setitem__("skipped", sorted(s)),
            state.__setitem__("updated_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())),
            session.save(state),
        ),
        index=index,
        done=done,
        skipped=skipped,
        prefill_by_id=prefill_by_id,
    )
    app.root.mainloop()
    return 0


class _FastApp:
    """Большая картинка + один вопрос; клавиатура главная. Логика — в FrameFlow."""

    def __init__(self, root, *, record_ids, record_for, is_seed, labels_path, details_path,
                 qc_path, seeds_by_id, on_progress, index=0, done=None, skipped=None,
                 prefill_by_id=None):
        import tkinter as tk
        from tkinter import ttk

        self.tk_module = tk
        self.ttk = ttk
        self.root = root
        self.record_ids = record_ids
        self.record_for = record_for
        self.is_seed = is_seed
        self.labels_path = labels_path
        self.details_path = details_path
        self.qc_path = qc_path
        self.seeds_by_id = seeds_by_id
        self.on_progress = on_progress
        self.done = set(done or [])
        self.skipped = set(skipped or [])
        self.viewing_history = False
        self.prefill_by_id = dict(prefill_by_id or {})
        self.prefill_active = False

        root.title("annotate_fast — быстрая разметка")
        root.geometry("1500x950")
        self.status = tk.StringVar()
        self.title_text = tk.StringVar()
        self.body_text = tk.StringVar()
        self.hint_text = tk.StringVar()
        self.note_var = tk.StringVar()

        from tkinter import font as tkfont
        self.big = tkfont.Font(size=22, weight="bold")
        self.medium = tkfont.Font(size=16)

        self.canvas = tk.Canvas(root, bg="#101010", highlightthickness=0)
        self.canvas.pack(side="left", fill="both", expand=True)
        panel = ttk.Frame(root, padding=16)
        panel.pack(side="right", fill="both", expand=True)

        tk.Label(panel, textvariable=self.status, font=self.medium, foreground="#666").pack(anchor="w")
        tk.Label(panel, textvariable=self.title_text, font=self.big, wraplength=560,
                 justify="left").pack(anchor="w", pady=(8, 12))
        self.body_label = tk.Label(panel, textvariable=self.body_text, font=self.medium,
                                   wraplength=560, justify="left")
        self.body_label.pack(anchor="w", fill="x")
        self.note_entry = tk.Entry(panel, textvariable=self.note_var, font=self.medium)
        self.note_entry.pack(anchor="w", fill="x", pady=8)
        tk.Label(panel, textvariable=self.hint_text, font=self.medium, foreground="#888",
                 wraplength=560, justify="left").pack(side="bottom", anchor="w")

        self.image = None
        self.photo = None
        self.image_size = (1, 1)
        self.scale = 1.0
        self.offset = (0.0, 0.0)
        self._press_xy = None
        self._draft_pixels = None

        self.canvas.bind("<Button-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)
        self.canvas.bind("<Configure>", lambda _e: self._refit())
        for seq in ("<Key>", "<Return>", "<Escape>", "<space>", "<Key-?>", "<KP_Enter>"):
            root.bind(seq, self._on_key)

        self.index = index if record_ids else 0
        self.flow: FrameFlow | None = None
        self._load_frame()

    # ------------------------------------------------------------------ frames
    def _record_id(self) -> str:
        return self.record_ids[self.index]

    def _load_frame(self) -> None:
        record = self.record_for(self._record_id())
        rid = record["record_id"]
        labels = load_labels(self.labels_path)
        details = load_jsonl(self.details_path)
        restore = latest_answers(rid, labels, details)
        self.prefill_active = False
        prefill_source = None
        if self.viewing_history:
            pass  # просмотр собственной записи — restore уже готов
        elif restore is not None:
            restore = None  # кадр уже размечен, идём вперёд по очереди — чистый старт
        elif rid in self.prefill_by_id and rid not in self.done:
            # неподтверждённый кадр с предзаполнением (например, разбор talk-заметок):
            # ответы предвыбраны — задача аннотатора проверить и подтверждать Enter'ом
            pre = self.prefill_by_id[rid]
            restore = {"label": pre.get("label") or {}, "detail": pre.get("detail") or {}}
            prefill_source = str(pre.get("source") or "prefill")
            self.prefill_active = True
        self.flow = FrameFlow(record, annotator_id=str(record.get("_annotator_id") or ""),
                              restore=restore, prefill_source=prefill_source)
        self.viewing_history = False
        self._render_image()
        self._render()

    def _advance(self, outcome: SaveOutcome) -> None:
        rid = self._record_id()
        if outcome.kind == "skip":
            self.skipped.add(rid)
        elif outcome.detail is not None:
            if self.is_seed(rid):
                expected = self.seeds_by_id.get(rid, {})
                append_jsonl(self.qc_path, qc_entry(outcome.detail, outcome.label or {}, expected))
                self.done.add(rid)  # сид выполнен; в fast_labels не пишем
            else:
                # detail пишется всегда (полная 15-head правда); v1-запись — только
                # когда v1-словарь способен её закодировать (label не None).
                append_jsonl(self.details_path, outcome.detail)
                if outcome.label is not None:
                    from annotation_labels import append_label

                    append_label(self.labels_path, outcome.label)
                self.done.add(rid)
        if self.index < len(self.record_ids) - 1:
            self.index += 1
        self.on_progress(self.index, self.done, self.skipped)
        self._load_frame()

    def _nav_back(self) -> None:
        if self.index > 0:
            self.index -= 1
            self.viewing_history = True
            self._load_frame()

    def _nav_forward(self) -> None:
        if self.index < len(self.record_ids) - 1:
            self.index += 1
            self.viewing_history = self._record_id() in (self.done | self.skipped)
            self._load_frame()

    # ------------------------------------------------------------------ input
    # Русская раскладка: keysym печатной клавиши приходит кириллицей; переводим
    # по физическим позициям ЙЦУКЕН, чтобы буквенные горячие клавиши работали.
    CYRILLIC_TO_LATIN = {
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j",
        "л": "k", "д": "l", "я": "z", "ч": "x", "с": "c", "м": "v", "и": "n",
        "т": "m", "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y",
        "г": "u", "ш": "i", "щ": "o", "з": "p", "ь": "b",
    }

    def _on_key(self, event) -> str:
        if self.flow is None:
            return "break"
        sym = event.keysym
        # пока печатается заметка, буквы идут в поле ввода (event.widget — Entry),
        # а не в визард; Return/Escape по-прежнему управляют потоком
        if self.flow.step in NOTE_STEPS and (
                getattr(event, "widget", None) is self.note_entry
                or self.root.focus_get() is self.note_entry) \
                and sym not in ("Return", "KP_Enter", "Escape"):
            return None
        if sym == "Escape":
            if self.flow.step == STEP_NO_ACTION:
                self.flow.back()
                self.flow.no_action = False
            else:
                self.flow.back()
            self._render()
            return "break"
        if sym in ("B", "b") and self.flow.step == STEP_VERDICT:
            self._nav_back()
            return "break"
        if sym in ("Right",):
            self._nav_forward()
            return "break"
        if sym in ("Return", "KP_Enter"):
            self.flow.set_note(self.note_var.get())
            self.flow.enter()
        elif sym == "space":
            self.flow.key(" ")
        elif sym in ("question", "slash"):
            self.flow.key("?")
        elif sym in ("Up", "Down", "Left", "Shift_L", "Shift_R"):
            return "break"
        else:
            ch = sym if len(sym) == 1 else ""
            if ch:
                ch = self.CYRILLIC_TO_LATIN.get(ch, ch)
                self.flow.key(ch.upper())
        if self.flow.outcome is not None:
            self._advance(self.flow.outcome)
        else:
            if self.flow.step in NOTE_STEPS:
                self.note_var.set(self.flow.snapshot()["note"])
                self.note_entry.focus_set()
        self._render()
        return "break"

    def _on_press(self, event) -> None:
        self._press_xy = (event.x, event.y)
        self._draft_pixels = None

    def _on_drag(self, event) -> None:
        if self._press_xy is None:
            return
        self._draft_pixels = (self._press_xy[0], self._press_xy[1], event.x, event.y)
        self._draw_overlays()

    def _on_release(self, event) -> None:
        if self._press_xy is None or self.flow is None:
            return
        x0, y0 = self._press_xy
        snap = self.flow.snapshot()
        rect = self._pixels_to_rect(x0, y0, event.x, event.y)
        self._press_xy = None
        self._draft_pixels = None
        if rect is None:
            return
        if snap["rect_mode"] == "issue":
            self.flow.set_draft_rect(rect)
        elif snap["rect_mode"] == "subject":
            self.flow.set_draft_rect(rect)
        self._render()

    def _pixels_to_rect(self, x0: float, y0: float, x1: float, y1: float) -> list[float] | None:
        ix0 = (x0 - self.offset[0]) / self.scale
        iy0 = (y0 - self.offset[1]) / self.scale
        ix1 = (x1 - self.offset[0]) / self.scale
        iy1 = (y1 - self.offset[1]) / self.scale
        return normalize_rect(ix0 / self.image_size[0], iy0 / self.image_size[1],
                              ix1 / self.image_size[0], iy1 / self.image_size[1])

    # ------------------------------------------------------------------ render
    def _refit(self) -> None:
        """Пересчитать масштаб под текущий размер канваса и перерисовать всё."""
        if self.image is not None:
            self._fit()
        self._draw_overlays()

    def _render_image(self) -> None:
        self.canvas.delete("all")
        record = self.flow.record if self.flow else None
        if record is None:
            return
        path = Path(record.get("image_path") or "")
        if not path.exists():
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66", text=f"нет файла: {path}")
            return
        try:
            from PIL import Image, ImageOps, ImageTk
        except ImportError as exc:
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66", text=f"нет Pillow: {exc}")
            return
        with Image.open(path) as opened:
            image = ImageOps.exif_transpose(opened).convert("RGB")
        self.image = image
        self.image_size = image.size
        self._refit()
        self._render()

    def _fit(self) -> None:
        if self.image is None:
            return
        width = self.canvas.winfo_width()
        height = self.canvas.winfo_height()
        if width <= 1 or height <= 1:  # ещё не разложен — повторить, когда появится размер
            self.root.after_idle(self._refit)
            return
        from PIL import ImageTk

        pad = 8
        self.scale = min((width - 2 * pad) / self.image.width, (height - 2 * pad) / self.image.height)
        target = (max(1, int(self.image.width * self.scale)), max(1, int(self.image.height * self.scale)))
        self.offset = ((width - target[0]) / 2, (height - target[1]) / 2)
        self.photo = ImageTk.PhotoImage(self.image.resize(target))

    def _render(self) -> None:
        if self.flow is None:
            return
        snap = self.flow.snapshot()
        rid = self._record_id()
        record = self.flow.record
        group = record.get("strata_group") or "—"
        mode = " · просмотр прошлого кадра (правка = новая запись)" if self.viewing_history else ""
        pre = " · ПРЕДЗАПОЛНЕНО — проверь и подтверждай Enter" if self.prefill_active else ""
        done_count = len(self.done | self.skipped)
        self.status.set(f"{self.index + 1}/{len(self.record_ids)} · группа {group} · "
                        f"готово {done_count}{mode}{pre}")
        self.title_text.set(snap["title"])
        lines = []
        for key, label, active in snap["options"]:
            prefix = "▶ " if active else "  "
            lines.append(f"{prefix}[{key}] {label}")
        for warning in snap["warnings"]:
            lines.append(f"⚠ {warning}")
        for legend in snap["legend"]:
            lines.append(legend)
        self.body_text.set("\n".join(lines))
        note_step = snap["step"] in NOTE_STEPS
        self.note_entry.configure(state="normal" if note_step else "disabled")
        if not note_step:
            self.note_var.set("")
        self.hint_text.set("Enter — далее/сохранить · Esc — шаг назад · B — предыдущий кадр · "
                           "→ — вперёд · числа/буквы — ответ")
        self._draw_overlays()

    def _draw_overlays(self) -> None:
        self.canvas.delete("all")
        if self.photo is not None:
            self.canvas.create_image(self.offset[0], self.offset[1], anchor="nw", image=self.photo)
        if self.flow is None:
            return
        snap = self.flow.snapshot()
        boxes = list(snap["rects"])
        if snap["draft_rect"]:
            boxes.append({"rect": snap["draft_rect"], "color": "#ffd400", "tag": "черновик"})
        if self._draft_pixels:
            x0, y0, x1, y1 = self._draft_pixels
            self.canvas.create_rectangle(x0, y0, x1, y1, outline="#ffd400", width=3)
        for box in boxes:
            rect = box["rect"]
            x = self.offset[0] + rect[0] * self.scale * self.image_size[0]
            y = self.offset[1] + rect[1] * self.scale * self.image_size[1]
            w = rect[2] * self.scale * self.image_size[0]
            h = rect[3] * self.scale * self.image_size[1]
            self.canvas.create_rectangle(x, y, x + w, y + h, outline=box["color"], width=3)
            if box.get("tag"):
                self.canvas.create_text(x, max(4, y - 14), anchor="nw", fill=box["color"],
                                        text=box["tag"], font=self.medium)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--queue", type=Path, help="очередь (queue.jsonl); каталог очереди = рабочее хранилище")
    parser.add_argument("--annotator-id", help="идентификатор аннотатора")
    parser.add_argument("--store", type=Path, help="fast_labels.jsonl (по умолчанию: каталог очереди)")
    parser.add_argument("--details", type=Path, help="fast_details.jsonl (по умолчанию: каталог очереди)")
    parser.add_argument("--qc", type=Path, help="qc.jsonl (по умолчанию: каталог очереди)")
    parser.add_argument("--seeds", type=Path, help="seeds.jsonl (по умолчанию: каталог очереди)")
    parser.add_argument("--session", type=Path, help="session.json (по умолчанию: каталог очереди)")
    parser.add_argument("--no-seeds", dest="with_seeds", action="store_false",
                        help="не подмешивать QC-виды")
    parser.add_argument("--prefill", type=Path,
                        help="предзаполнение неподтверждённых кадров (jsonl: record_id/label/detail/source), "
                             "например разбор talk-заметок агентом — аннотатор только подтверждает")
    parser.add_argument("--only-ids", type=Path,
                        help="пройти только записи из файла (record_id по строке на строку; "
                             "# — комментарий); например calibration-subset-v1")
    parser.add_argument("--report-qc", action="store_true", help="напечатать отчёт согласия по сидам и выйти")
    parser.add_argument("--report-gaps", action="store_true",
                        help="напечатать gap-отчёт «контрактом не выразить» и выйти")
    parser.add_argument("--check-identity", action="store_true",
                        help="проверить 1:1 record_id↔кадр и привязку записей хранилища и выйти")
    parser.add_argument("--report-agreement", type=Path, metavar="SECOND_STORE",
                        help="согласие двух независимых проходов (второй store: fast_labels.r2.jsonl) и выйти")
    parser.add_argument("--second-details", type=Path,
                        help="detail-файл второго прохода (по умолчанию: имя SECOND_STORE с labels→details)")
    parser.add_argument("--export-out", type=Path, metavar="DIR",
                        help="экспортировать сохранённые записи в release-label (без GUI)")
    args = parser.parse_args(argv)

    if args.report_qc:
        qc_path = args.qc or ((args.queue.parent if args.queue else Path.cwd()) / "qc.jsonl")
        print(agreement_report(load_jsonl(qc_path)))
        return 0

    if args.report_gaps:
        details_path = args.details or ((args.queue.parent if args.queue else Path.cwd()) / "fast_details.jsonl")
        print(gaps_report(load_jsonl(details_path)))
        return 0

    if args.check_identity:
        if not args.queue:
            parser.error("--check-identity требует --queue")
        queue_dir = args.queue.parent
        problems = queue_identity_problems(
            queue=load_jsonl(args.queue),
            seeds=load_jsonl(args.seeds or (queue_dir / "seeds.jsonl")),
            labels=load_labels(args.store or (queue_dir / "fast_labels.jsonl")),
            details=load_jsonl(args.details or (queue_dir / "fast_details.jsonl")),
        )
        if problems:
            print(f"IDENTITY FAIL ({len(problems)}):")
            for problem in problems:
                print(f"  - {problem}")
            return 2
        print("IDENTITY OK: record_id ↔ кадр 1:1, записи привязаны к своим кадрам")
        return 0

    if args.report_agreement:
        queue_dir = args.queue.parent if args.queue else Path.cwd()
        first_labels = load_labels(args.store or (queue_dir / "fast_labels.jsonl"))
        first_details = load_jsonl(args.details or (queue_dir / "fast_details.jsonl"))
        second_labels = load_labels(args.report_agreement)
        second_name = args.report_agreement.name.replace("labels", "details")
        second_details_path = args.second_details or (args.report_agreement.parent / second_name)
        second_details = load_jsonl(second_details_path)
        name_a = "/".join(sorted({str(r.get("annotator_id") or "?") for r in first_labels})) or "reviewer-1"
        name_b = "/".join(sorted({str(r.get("annotator_id") or "?") for r in second_labels})) or "reviewer-2"
        print(reviewer_agreement_report(labels_a=first_labels, details_a=first_details,
                                        labels_b=second_labels, details_b=second_details,
                                        name_a=name_a, name_b=name_b))
        return 0

    if args.export_out:
        if not args.queue:
            parser.error("--export-out требует --queue")
        queue = load_jsonl(args.queue)
        queue_dir = args.queue.parent
        labels = load_labels(args.store or (queue_dir / "fast_labels.jsonl"))
        details = load_jsonl(args.details or (queue_dir / "fast_details.jsonl"))
        seeds = load_jsonl(args.seeds or (queue_dir / "seeds.jsonl"))
        result = export_labels(labels=labels, details=details, queue_rows=queue, seeds_rows=seeds,
                               out_dir=args.export_out)
        print(f"экспортировано (validate PASS): {len(result['exported'])}")
        for rid in result["exported"]:
            print(f"  OK {rid}")
        print(f"отклонено (ничего не записано): {len(result['rejected'])}")
        for row in result["rejected"]:
            print(f"  REJECTED {row['record_id']}: {row['reason']}")
        return 0 if not result["rejected"] else 2

    if not args.queue or not args.annotator_id:
        parser.error("нужны --queue и --annotator-id (или --report-qc / --report-gaps / --export-out DIR)")
    return run_gui(args)


if __name__ == "__main__":
    sys.exit(main())
