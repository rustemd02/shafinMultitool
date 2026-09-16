#!/usr/bin/env python3
"""Camera Coach annotation tool (human review; research-only input).

A small desktop app: it shows one candidate frame at a time and records what
you see — is it beautiful, is it fixable, what exactly is wrong, which action
would fix it, and where on the frame. You can also draw the problem area and
describe it in your own words; the free text pre-selects matching issue/action
boxes (suggestions only — you stay the source of truth).

Records are appended to the human-review store (see annotation_labels.py).
Use review_pipeline.py for any research export; this UI never creates automatic gold.

Run:
    python3 tools/camera_annotation/annotate_gui.py \
        --queue  <queue.jsonl> \
        --store  <labels.jsonl> \
        --annotator-id "rustem"

Build a queue first with build_annotation_queue.py.

Keys:  1/2/3 beauty · K keep/toggle fixing · U unsure · A assist · Enter save+next
       S skip · B back · Delete removes the selected region · Esc clears it
"""

from __future__ import annotations

import argparse
import json
import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

sys.path.insert(0, str(Path(__file__).resolve().parent))

from annotation_labels import (  # noqa: E402
    ACTIONS,
    BEAUTY_LEVELS,
    DELTAS,
    ISSUES,
    KEEP_ACTION,
    REGION_ROLES,
    append_label,
    build_label,
    load_labels,
    sha256_file,
)
from assist_hints import ASSIST_SOURCE, beauty_from_score, hints_for_image  # noqa: E402
from phrase_suggestions import suggest  # noqa: E402

ISSUE_LABELS_RU = {
    "subject_too_close_to_edge": "субъект у края кадра",
    "subject_not_prominent_enough": "субъект слишком мелкий",
    "background_competes_with_subject": "фон конкурирует с субъектом",
    "insufficient_look_space": "мало пространства по взгляду",
    "backlight_hides_subject": "контровой свет прячет субъект",
    "scene_has_no_clear_focus": "нет ясного фокуса",
    "frame_visually_overloaded": "кадр перегружен",
    "horizon_distracts": "горизонт мешает",
}

ACTION_LABELS_RU = {
    "shift_frame_left": "сдвинуть кадр влево",
    "shift_frame_right": "сдвинуть кадр вправо",
    "shift_frame_up": "сдвинуть кадр вверх",
    "shift_frame_down": "сдвинуть кадр вниз",
    "step_back": "шаг назад",
    "step_closer": "шаг ближе",
    "lower_camera": "опустить камеру",
    "raise_camera": "поднять камеру",
    "change_camera_angle": "сменить угол",
    "level_horizon": "выровнять горизонт",
    "rotate_subject_toward_light": "повернуть субъект к свету",
    "move_subject_left": "сместить субъект влево",
    "move_subject_right": "сместить субъект вправо",
    "move_subject_away_from_background": "отодвинуть субъект от фона",
    "move_object_left": "убрать объект влево",
    "move_object_right": "убрать объект вправо",
    "move_object_forward": "убрать объект вперёд",
    "move_object_back": "убрать объект назад",
    "remove_distracting_object": "убрать отвлекающий объект",
    "reposition_prop_for_balance": "переставить предмет для баланса",
    "add_front_fill_light": "добавить заполняющий свет",
    "add_background_light": "добавить свет на фон",
    "remove_background_hotspot": "убрать пересвет в фоне",
    "simplify_background": "упростить фон",
    "wait_for_background_clearance": "дождаться чистого фона",
    "keep_current_setup": "оставить как есть",
}

BEAUTY_LABELS_RU = {"beautiful": "красиво", "borderline": "пограничное", "ugly": "некрасиво"}

CAPTURE_INTENTS: tuple[str, ...] = (
    "natural",
    "silhouette",
    "low_key",
    "symmetry",
    "negative_space",
    "dutch_angle",
    "intentional_motion_blur",
    "handheld",
)
CAPTURE_INTENT_LABELS_RU = {
    "unknown": "не указано",
    "natural": "естественный кадр",
    "silhouette": "силуэт",
    "low_key": "low-key",
    "symmetry": "симметрия",
    "negative_space": "негативное пространство",
    "dutch_angle": "голландский угол",
    "intentional_motion_blur": "намеренный motion blur",
    "handheld": "съёмка с рук",
}
MATRIX_CLASSES: tuple[str, ...] = (
    "single_person",
    "two_people",
    "object_or_food",
    "interior",
    "street_or_landscape",
    "difficult_light",
    "already_good_frame",
)
MATRIX_CLASS_LABELS_RU = {
    "unknown": "не указано",
    "single_person": "один человек",
    "two_people": "два человека",
    "object_or_food": "объект или еда",
    "interior": "интерьер",
    "street_or_landscape": "улица или пейзаж",
    "difficult_light": "сложный свет",
    "already_good_frame": "уже хороший кадр",
}
REVIEW_MODES = {"blind", "assisted"}
EXIF_ORIENTATION_LABELS = {
    1: "обычное",
    2: "зеркально по горизонтали",
    3: "поворот 180°",
    4: "зеркально по вертикали",
    5: "зеркально + 90° против часовой",
    6: "поворот 90° по часовой",
    7: "зеркально + 90° по часовой",
    8: "поворот 90° против часовой",
}

# The five continuous axes of the frozen contract. An axis is only recorded when
# its checkbox is on: an unset axis stays masked, so "no direction given" never
# becomes "no change needed" (D02a).
DELTA_LABELS_RU = {
    "delta_x": "сдвиг по горизонтали",
    "delta_y": "сдвиг по вертикали",
    "scale_delta": "крупность",
    "light_delta": "свет",
    "horizon_delta": "горизонт",
}


def provenance_caption(record: dict) -> str:
    """What the annotator must see about the frame's rights status.

    The queue mixes CC-BY cinematic frames, the owner's own benchmark pack and
    research-only AVA frames; annotating them without seeing which is which is
    how research-only pixels end up looking like release data.
    """
    provenance = record.get("provenance") or {}
    parts = []
    if provenance.get("source"):
        parts.append(f"источник: {provenance['source']}")
    if provenance.get("license"):
        parts.append(f"лицензия: {provenance['license']}")
    if provenance.get("title"):
        parts.append(str(provenance["title"]))
    if provenance.get("timestamp_s") is not None:
        parts.append(f"t={provenance['timestamp_s']}s")
    return "  ·  ".join(parts) if parts else "права не указаны — трактовать как research-only"


class AnnotationApp:
    def __init__(self, root: tk.Tk, queue: list[dict], store: Path, annotator_id: str) -> None:
        self.root = root
        self.queue = queue
        self.store = store
        self.annotator_id = annotator_id
        self.index = 0

        self.region_draft: tuple[float, float, float, float] | None = None
        self.regions: list[dict] = []
        self.selected_region = 0
        self.photo: object | None = None
        self.scale = 1.0
        self.offset = (0.0, 0.0)
        self.image_size = (1, 1)
        self.image_orientation = 1
        self.image_ready = False
        self.source_verified = False
        self.source_error = ""

        self.beauty = tk.StringVar(value="")
        self.improvement_needed = tk.BooleanVar(value=True)
        self.unsure = tk.BooleanVar(value=False)
        self.notes = tk.StringVar(value="")
        self.capture_intent = tk.StringVar(value="unknown")
        self.matrix_class = tk.StringVar(value="unknown")
        self.region_label = tk.StringVar(value="")
        self.role = tk.StringVar(value=REGION_ROLES[0])
        self.roi_uncertain = tk.BooleanVar(value=False)
        self.human_confirmed = tk.BooleanVar(value=False)
        self.issue_vars: dict[str, tk.BooleanVar] = {}
        self.action_vars: dict[str, tk.BooleanVar] = {}
        self.forbidden_vars: dict[str, tk.BooleanVar] = {}
        self.delta_set: dict[str, tk.BooleanVar] = {}
        self.delta_value: dict[str, tk.DoubleVar] = {}
        self.status = tk.StringVar(value="")
        self.progress = tk.StringVar(value="")
        self.provenance = tk.StringVar(value="")
        self.record_caption = tk.StringVar(value="")
        self.image_info = tk.StringVar(value="")
        self.review_caption = tk.StringVar(value="")
        self.review_mode = "blind"
        self.teacher_proposal: dict | None = None
        self.teacher_proposal_id: str | None = None
        self.teacher_intent: str | None = None
        self.teacher_intent_matches = True
        self.teacher_caption = tk.StringVar(value="")
        self.assisted = False
        self.assist_sources: set[str] = set()
        self.saved_label: dict | None = None
        self.assist_button: ttk.Button | None = None
        self.suggestion_button: ttk.Button | None = None
        self.teacher_box: ttk.LabelFrame | None = None
        self.teacher_summary: tk.Text | None = None
        self.teacher_apply_button: ttk.Button | None = None

        self._build_layout()
        self._bind_keys()
        self.load_current()

    # ---------------------------------------------------------------- layout
    def _build_layout(self) -> None:
        self.root.title("Camera Coach — human review · research-only")
        self.root.geometry("1280x800")

        top = ttk.Frame(self.root, padding=6)
        top.pack(fill="x")
        ttk.Label(top, textvariable=self.status, font=("Helvetica", 12, "bold")).pack(side="left")
        ttk.Label(top, textvariable=self.progress).pack(side="left", padx=12)
        ttk.Button(top, text="Сохранить и далее (Enter)", command=self.save_current).pack(side="right")
        ttk.Button(top, text="Пропустить (S)", command=self.skip).pack(side="right", padx=4)
        ttk.Button(top, text="Назад (B)", command=self.back).pack(side="right", padx=4)

        body = ttk.Frame(self.root)
        body.pack(fill="both", expand=True)

        self.canvas = tk.Canvas(body, background="#111", highlightthickness=0)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.canvas.bind("<ButtonPress-1>", self.on_press)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.canvas.bind("<MouseWheel>", self.on_wheel)
        self.canvas.bind("<Button-4>", self.on_wheel)
        self.canvas.bind("<Button-5>", self.on_wheel)
        # The canvas has no real size until the window manager lays it out, so
        # the first render must wait for the first <Configure> instead of
        # scaling against a 1x1 canvas (which is why frames looked tiny).
        self.canvas.bind("<Configure>", self.on_canvas_resize)
        self.auto_fit = True

        panel_host = ttk.Frame(body, width=450)
        panel_host.pack(side="right", fill="y")
        panel_host.pack_propagate(False)
        panel_canvas = tk.Canvas(panel_host, highlightthickness=0, width=430)
        self.panel_canvas = panel_canvas
        scrollbar = ttk.Scrollbar(panel_host, orient="vertical", command=panel_canvas.yview)
        panel_canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        panel_canvas.pack(side="left", fill="both", expand=True)
        panel = ttk.Frame(panel_canvas, padding=8)
        panel_window = panel_canvas.create_window((0, 0), window=panel, anchor="nw")
        panel.bind(
            "<Configure>",
            lambda _event: panel_canvas.configure(scrollregion=panel_canvas.bbox("all")),
        )
        panel_canvas.bind(
            "<Configure>",
            lambda event: panel_canvas.itemconfigure(panel_window, width=event.width),
        )
        panel_canvas.bind("<MouseWheel>", lambda event: self._scroll_panel(panel_canvas, event))
        panel.bind("<MouseWheel>", lambda event: self._scroll_panel(panel_canvas, event))
        self.root.bind("<MouseWheel>", self._on_root_panel_wheel, add="+")
        self.root.bind("<Button-4>", self._on_root_panel_wheel, add="+")
        self.root.bind("<Button-5>", self._on_root_panel_wheel, add="+")
        self._build_panel(panel)

    def _build_panel(self, panel: ttk.Frame) -> None:
        rights_box = ttk.LabelFrame(panel, text="Права на кадр", padding=6)
        rights_box.pack(fill="x")
        ttk.Label(
            rights_box, textvariable=self.provenance, wraplength=390
        ).pack(anchor="w")
        ttk.Label(rights_box, textvariable=self.record_caption, wraplength=390).pack(anchor="w", pady=(4, 0))
        ttk.Label(rights_box, textvariable=self.image_info, wraplength=390).pack(
            anchor="w", pady=(4, 0)
        )
        ttk.Label(rights_box, textvariable=self.review_caption, wraplength=390).pack(
            anchor="w", pady=(4, 0)
        )

        beauty_box = ttk.LabelFrame(panel, text="Кадр", padding=6)
        beauty_box.pack(fill="x")
        for level in BEAUTY_LEVELS:
            ttk.Radiobutton(
                beauty_box, text=BEAUTY_LABELS_RU[level], value=level, variable=self.beauty
            ).pack(anchor="w")
        ttk.Label(beauty_box, text="Неуверенность позволяет сохранить unrated без выдуманных причин.",
                  wraplength=390).pack(anchor="w", pady=(3, 0))
        ttk.Checkbutton(
            beauty_box, text="Нужно улучшать (K — снять, если оставить как есть)",
            variable=self.improvement_needed, command=self.on_improvement_toggle,
        ).pack(anchor="w", pady=(4, 0))
        ttk.Checkbutton(beauty_box, text="Не уверен (U) — пропустить обучение этой записи",
                        variable=self.unsure, command=self.on_unsure_toggle).pack(anchor="w")

        intent_box = ttk.LabelFrame(panel, text="Замысел съёмки", padding=6)
        intent_box.pack(fill="x", pady=6)
        ttk.Label(intent_box, text="Выбери только явно известный intent; по умолчанию — не указано.",
                  wraplength=390).pack(anchor="w")
        intent_values = ["unknown", *CAPTURE_INTENTS]
        self.intent_combo = ttk.Combobox(
            intent_box,
            values=[CAPTURE_INTENT_LABELS_RU[value] for value in intent_values],
            state="readonly",
        )
        self.intent_combo.pack(fill="x", pady=(4, 0))
        self.intent_values = intent_values
        self.intent_combo.bind("<<ComboboxSelected>>", self.on_intent_selected)
        self._bind_input_shortcuts(self.intent_combo)
        ttk.Label(intent_box, text="Тип сцены (обязательно для решённой разметки):", wraplength=390).pack(
            anchor="w", pady=(6, 0)
        )
        self.matrix_values = ["unknown", *MATRIX_CLASSES]
        self.matrix_combo = ttk.Combobox(
            intent_box,
            values=[MATRIX_CLASS_LABELS_RU[value] for value in self.matrix_values],
            state="readonly",
        )
        self.matrix_combo.pack(fill="x", pady=(4, 0))
        self.matrix_combo.bind("<<ComboboxSelected>>", self.on_matrix_selected)
        self._bind_input_shortcuts(self.matrix_combo)

        issues_box = ttk.LabelFrame(panel, text="Что мешает", padding=6)
        issues_box.pack(fill="x", pady=6)
        for name in ISSUES:
            var = tk.BooleanVar(value=False)
            self.issue_vars[name] = var
            ttk.Checkbutton(issues_box, text=ISSUE_LABELS_RU[name], variable=var).pack(anchor="w")

        actions_box = ttk.LabelFrame(panel, text="Что сделать (можно несколько)", padding=6)
        actions_box.pack(fill="both", expand=True)
        grid = ttk.Frame(actions_box)
        grid.pack(fill="both", expand=True)
        for position, name in enumerate(ACTIONS):
            var = tk.BooleanVar(value=False)
            self.action_vars[name] = var
            forbidden = tk.BooleanVar(value=False)
            self.forbidden_vars[name] = forbidden
            cell = ttk.Frame(grid)
            cell.grid(row=position, column=0, sticky="w", padx=2)
            ttk.Checkbutton(cell, text=ACTION_LABELS_RU[name], variable=var).pack(side="left")
            ttk.Checkbutton(cell, text="нельзя", variable=forbidden).pack(side="left")
        ttk.Label(
            actions_box,
            text="Нельзя — явный forbidden-пример; пусто = маска, не отрицательный ответ.",
            wraplength=390,
        ).pack(anchor="w", pady=(4, 0))

        notes_box = ttk.LabelFrame(panel, text="Своими словами (переведётся в разметку)", padding=6)
        notes_box.pack(fill="x", pady=6)
        self.notes_entry = ttk.Entry(notes_box, textvariable=self.notes)
        self.notes_entry.pack(fill="x")
        self._bind_input_shortcuts(self.notes_entry, self._on_notes_return)
        self.suggestion_button = ttk.Button(
            notes_box, text="Разобрать текст в галочки (Enter)", command=self.apply_suggestions
        )
        self.suggestion_button.pack(
            fill="x", pady=(4, 0)
        )
        self.assist_button = ttk.Button(notes_box, text="Подсказать по кадру (A)", command=self.apply_assist)
        self.assist_button.pack(
            fill="x", pady=(4, 0)
        )

        self.teacher_box = ttk.LabelFrame(panel, text="Исследовательское предложение (не gold)", padding=6)
        self.teacher_box.pack(fill="x", pady=6)
        ttk.Label(
            self.teacher_box,
            textvariable=self.teacher_caption,
            wraplength=390,
        ).pack(anchor="w")
        self.teacher_summary = tk.Text(self.teacher_box, height=8, width=40, wrap="word", state="disabled")
        self.teacher_summary.pack(fill="x", pady=(4, 0))
        self._bind_input_shortcuts(self.teacher_summary)
        self.teacher_apply_button = ttk.Button(
            self.teacher_box, text="Применить предложение (проверить вручную)", command=self.apply_teacher_proposal
        )
        self.teacher_apply_button.pack(fill="x", pady=(4, 0))

        delta_box = ttk.LabelFrame(panel, text="Направление правки (необязательно)", padding=6)
        delta_box.pack(fill="x", pady=6)
        for name in DELTAS:
            row = ttk.Frame(delta_box)
            row.pack(fill="x")
            set_var = tk.BooleanVar(value=False)
            value_var = tk.DoubleVar(value=0.0)
            self.delta_set[name] = set_var
            self.delta_value[name] = value_var
            ttk.Checkbutton(row, text=DELTA_LABELS_RU[name], variable=set_var, width=24).pack(side="left")
            ttk.Scale(row, from_=-1.0, to=1.0, variable=value_var, orient="horizontal", length=150).pack(
                side="left", padx=4
            )
            ttk.Label(row, textvariable=value_var, width=5).pack(side="left")
        ttk.Label(
            delta_box,
            text="Галочка = направление задано. Без галочки ось остаётся неразмеченной (маска, не ноль).",
            wraplength=390,
        ).pack(anchor="w", pady=(4, 0))

        region_box = ttk.LabelFrame(panel, text="Области / ROI (рисуй мышью на кадре)", padding=6)
        region_box.pack(fill="x")
        ttk.Label(
            region_box,
            text="ROI субъекта нужен для conditional training. Если не уверен — отметь пропуск и сохрани без выдуманной области.",
            wraplength=390,
        ).pack(anchor="w")
        self.region_list = tk.Listbox(region_box, height=4)
        self.region_list.pack(fill="x")
        self.region_list.bind("<<ListboxSelect>>", self.on_region_select)
        row = ttk.Frame(region_box)
        row.pack(fill="x", pady=(4, 0))
        self.role_combo = ttk.Combobox(row, values=list(REGION_ROLES), textvariable=self.role, width=12,
                                       state="readonly")
        self.role_combo.pack(side="left")
        self._bind_input_shortcuts(self.role_combo)
        ttk.Button(row, text="Сменить роль", command=self.change_role).pack(side="left", padx=3)
        ttk.Button(row, text="Удалить (Del)", command=self.delete_region).pack(side="left")
        label_row = ttk.Frame(region_box)
        label_row.pack(fill="x", pady=(4, 0))
        ttk.Label(label_row, text="Имя объекта:").pack(side="left")
        self.region_label_entry = ttk.Entry(label_row, textvariable=self.region_label)
        self.region_label_entry.pack(side="left", fill="x", expand=True, padx=(4, 0))
        self._bind_input_shortcuts(self.region_label_entry)
        ttk.Button(region_box, text="Применить имя к области", command=self.change_region_label).pack(
            fill="x", pady=(4, 0)
        )
        ttk.Checkbutton(
            region_box,
            text="ROI субъекта: не уверен / пропустить",
            variable=self.roi_uncertain,
        ).pack(anchor="w", pady=(4, 0))

        ttk.Checkbutton(
            panel,
            text="Подтверждаю: это моё решение",
            variable=self.human_confirmed,
        ).pack(fill="x", pady=8)

    def _bind_input_shortcuts(self, widget, return_handler=None) -> None:
        """Keep top-level annotation shortcuts out of editable controls."""
        root_tag = str(self.root)
        widget.bindtags(tuple(tag for tag in widget.bindtags() if tag != root_tag))
        if return_handler is not None:
            widget.bind("<Return>", return_handler)
            widget.bind("<KP_Enter>", return_handler)

    def _on_notes_return(self, _event):
        self.apply_suggestions()
        return "break"

    def on_intent_selected(self, _event=None) -> None:
        index = self.intent_combo.current()
        if 0 <= index < len(self.intent_values):
            self.capture_intent.set(self.intent_values[index])
            self._update_teacher_intent_gate()

    def on_matrix_selected(self, _event=None) -> None:
        index = self.matrix_combo.current()
        if 0 <= index < len(self.matrix_values):
            self.matrix_class.set(self.matrix_values[index])

    def _set_intent_control(self, value: str | None) -> None:
        value = value if value in CAPTURE_INTENTS else "unknown"
        self.capture_intent.set(value)
        if hasattr(self, "intent_combo"):
            self.intent_combo.current(self.intent_values.index(value))
        self._update_teacher_intent_gate()

    def _set_matrix_control(self, value: str | None) -> None:
        value = value if value in MATRIX_CLASSES else "unknown"
        self.matrix_class.set(value)
        if hasattr(self, "matrix_combo"):
            self.matrix_combo.current(self.matrix_values.index(value))

    def _set_teacher_summary(self, proposal: dict | None) -> None:
        if self.teacher_summary is None:
            return
        summary = json.dumps(proposal, ensure_ascii=False, indent=2, sort_keys=True) if proposal else "нет предложения"
        self.teacher_summary.configure(state="normal")
        self.teacher_summary.delete("1.0", tk.END)
        self.teacher_summary.insert("1.0", summary)
        self.teacher_summary.configure(state="disabled")

    def _update_teacher_intent_gate(self) -> None:
        proposal = self.teacher_proposal
        if proposal is None:
            self.teacher_intent = None
            self.teacher_intent_matches = True
            self.teacher_caption.set("Предложение видно только в assisted; решение и сохранение всегда подтверждает человек.")
            if self.teacher_apply_button is not None:
                self.teacher_apply_button.state(["disabled"])
            return
        raw_intent = proposal.get("capture_intent")
        self.teacher_intent = raw_intent if isinstance(raw_intent, str) else None
        current = self.capture_intent.get()
        teacher_label = CAPTURE_INTENT_LABELS_RU.get(self.teacher_intent or "unknown", str(self.teacher_intent))
        current_label = CAPTURE_INTENT_LABELS_RU.get(current, current)
        self.teacher_intent_matches = self.teacher_intent in CAPTURE_INTENTS and current == self.teacher_intent
        if self.teacher_intent_matches:
            self.teacher_caption.set(
                f"Предложение видно только в assisted · исходный intent: {teacher_label}. "
                "Решение и сохранение всегда подтверждает человек."
            )
            if self.teacher_apply_button is not None:
                self.teacher_apply_button.state(["!disabled"])
        else:
            self.teacher_caption.set(
                f"Intent предложения: {teacher_label}; текущий intent: {current_label}. "
                f"Выбери {teacher_label}, чтобы применить; решение подтверждает человек."
            )
            if self.teacher_apply_button is not None:
                self.teacher_apply_button.state(["disabled"])

    def _scroll_panel(self, canvas: tk.Canvas, event) -> str:
        if getattr(event, "num", None) == 4:
            units = -1
        elif getattr(event, "num", None) == 5:
            units = 1
        else:
            delta = getattr(event, "delta", 0)
            raw_units = int(delta) if sys.platform == "darwin" else int(delta / 120)
            if raw_units == 0 and delta:
                raw_units = 1 if delta > 0 else -1
            units = max(-20, min(20, -raw_units))
        canvas.yview_scroll(units, "units")
        return "break"

    def _on_root_panel_wheel(self, event):
        widget_path = str(event.widget)
        panel_path = str(self.panel_canvas)
        if widget_path == panel_path or widget_path.startswith(panel_path + "."):
            return self._scroll_panel(self.panel_canvas, event)
        return None

    def _bind_keys(self) -> None:
        self.root.bind("<Key-1>", lambda _e: self.beauty.set("beautiful"))
        self.root.bind("<Key-2>", lambda _e: self.beauty.set("borderline"))
        self.root.bind("<Key-3>", lambda _e: self.beauty.set("ugly"))
        self.root.bind("<Key-k>", lambda _e: self.toggle_keep())
        self.root.bind("<Key-u>", lambda _e: self._toggle_unsure())
        self.root.bind("<Return>", lambda _e: self.save_current())
        self.root.bind("<Key-s>", lambda _e: self.skip())
        self.root.bind("<Key-b>", lambda _e: self.back())
        self.root.bind("<Key-f>", lambda _e: self.refit())
        self.root.bind("<Key-a>", lambda _e: self.apply_assist())
        self.root.bind("<Delete>", lambda _e: self.delete_region())
        self.root.bind("<Escape>", lambda _e: self.clear_draft())

    def refit(self) -> None:
        self.auto_fit = True
        self.render_image()

    # ------------------------------------------------------------ navigation
    @property
    def current(self) -> dict | None:
        return self.queue[self.index] if 0 <= self.index < len(self.queue) else None

    def _reset_controls(self) -> None:
        self.regions = []
        self.region_draft = None
        self.assisted = False
        self.assist_sources = set()
        self.saved_label = None
        self.beauty.set("")
        self.improvement_needed.set(True)
        self.unsure.set(False)
        self.notes.set("")
        self._set_intent_control(None)
        self._set_matrix_control(None)
        self.role.set(REGION_ROLES[0])
        self.region_label.set("")
        self.roi_uncertain.set(False)
        self.human_confirmed.set(False)
        for var in self.issue_vars.values():
            var.set(False)
        for var in self.action_vars.values():
            var.set(False)
        for var in self.forbidden_vars.values():
            var.set(False)
        for name in DELTAS:
            self.delta_set[name].set(False)
            self.delta_value[name].set(0.0)

    def _restore_label(self, label: dict) -> None:
        """Restore the latest saved human label when revisiting a frame."""
        if self.review_mode == "blind" and (
            label.get("review_mode") != "blind" or label.get("assisted")
            or label.get("assist_source") or label.get("teacher_proposal_id")
        ):
            raise ValueError("Нельзя восстановить подсказанную/неизвестную разметку как blind")
        self.saved_label = label
        self.assisted = self.review_mode == "assisted" and (self.assisted or bool(label.get("assisted")))
        if self.assisted and label.get("assist_source"):
            self.assist_sources.add(str(label["assist_source"]))
        beauty = label.get("beauty") or ""
        self.beauty.set(beauty)
        unsure = bool(label.get("unsure"))
        self.unsure.set(unsure)
        improvement = label.get("improvement_needed")
        self.improvement_needed.set(bool(improvement) if improvement is not None else False)
        self.notes.set(str(label.get("notes") or ""))
        self._set_intent_control(label.get("capture_intent"))
        self._set_matrix_control(label.get("matrix_class"))
        for name in self.issue_vars:
            self.issue_vars[name].set(name in (label.get("issues") or []))
        for name in self.action_vars:
            self.action_vars[name].set(name in (label.get("actions") or []))
            self.forbidden_vars[name].set(name in (label.get("forbidden_actions") or []))
        self.regions = [self._clip_region(region) for region in (label.get("regions") or [])]
        self.regions = [region for region in self.regions if region is not None]
        self.roi_uncertain.set(sum(region.get("role") == "subject" for region in self.regions) != 1)
        deltas = label.get("deltas") or {}
        for name in DELTAS:
            if name in deltas:
                self.delta_set[name].set(True)
                self.delta_value[name].set(float(deltas[name]))
        self.human_confirmed.set(True)

    def _apply_review_mode(self, record: dict) -> None:
        mode = record.get("review_mode")
        self.review_mode = mode if mode in REVIEW_MODES else "blind"
        if self.review_mode == "blind":
            self.review_caption.set("Режим: blind — priors, heuristics и teacher скрыты.")
            if self.assist_button is not None:
                self.assist_button.state(["disabled"])
            if self.suggestion_button is not None:
                self.suggestion_button.state(["disabled"])
            if self.teacher_box is not None:
                self.teacher_box.pack_forget()
            self.teacher_proposal = None
            self.teacher_proposal_id = None
            self.teacher_intent = None
            self.teacher_intent_matches = True
            return
        self.review_caption.set("Режим: assisted — подсказки только исследовательские, решение подтверждает человек.")
        if self.assist_button is not None:
            self.assist_button.state(["!disabled"])
        if self.suggestion_button is not None:
            self.suggestion_button.state(["!disabled"])
        proposal = record.get("teacher_proposal")
        if (not isinstance(proposal, dict)
                or (proposal.get("record_id") is not None and proposal.get("record_id") != record.get("record_id"))):
            self.teacher_proposal = None
        else:
            self.teacher_proposal = proposal
        proposal_id = self.teacher_proposal.get("proposal_id") if self.teacher_proposal else None
        if self.teacher_proposal is not None and not proposal_id:
            proposal_id = record.get("teacher_proposal_id")
        self.teacher_proposal_id = str(proposal_id) if proposal_id else None
        if self.teacher_proposal is not None:
            self.assisted = True
            self.assist_sources.add("teacher-proposal")
        self._set_teacher_summary(self.teacher_proposal)
        self._update_teacher_intent_gate()
        if self.teacher_box is not None and not self.teacher_box.winfo_ismapped():
            self.teacher_box.pack(fill="x", pady=6)

    def _latest_saved_label(self, record: dict) -> dict | None:
        expected = str(record.get("image_sha256") or "").lower()
        matches = [
            label for label in load_labels(self.store)
            if label.get("record_id") == record.get("record_id")
            and label.get("annotator_id") == self.annotator_id
            and str(label.get("image_sha256") or "").lower() == expected
        ]
        return matches[-1] if matches else None

    def _update_progress(self) -> None:
        queue_ids = {record.get("record_id") for record in self.queue}
        saved_ids = {
            label.get("record_id") for label in load_labels(self.store)
            if label.get("record_id") in queue_ids
            and label.get("annotator_id") == self.annotator_id
        }
        saved = len(saved_ids)
        self.progress.set(f"Прогресс {saved}/{len(self.queue)} · осталось {max(0, len(self.queue) - saved)}")

    def _verify_source(self) -> bool:
        record = self.current
        self.source_verified = False
        self.image_ready = False
        self.source_error = ""
        if record is None:
            return False
        path = Path(str(record.get("image_path") or ""))
        expected = str(record.get("image_sha256") or "").lower()
        if not path.is_file():
            self.source_error = f"нет файла: {path}"
            return False
        if not expected:
            self.source_error = "в очереди нет image_sha256 — сохранение запрещено"
            return False
        try:
            from PIL import Image

            with Image.open(path) as image:
                image.verify()
            actual = sha256_file(path).lower()
        except Exception as exc:  # noqa: BLE001 - admission check must explain source failures
            self.source_error = f"кадр не читается: {exc}"
            return False
        if actual != expected:
            self.source_error = "SHA кадра изменился: очередь не совпадает с файлом"
            return False
        self.source_verified = True
        self.image_ready = True
        return True

    def load_current(self) -> None:
        record = self.current
        if record is None:
            self.status.set(f"Готово: очередь {len(self.queue)} кадров")
            self.record_caption.set("")
            self._update_progress()
            self.canvas.delete("all")
            return
        self._reset_controls()
        self.auto_fit = True
        self._apply_review_mode(record)
        self._set_intent_control(record.get("capture_intent"))
        # Queue discovery tags are weak sampling hints, never scene labels.
        self._set_matrix_control(None)
        saved = self._latest_saved_label(record)
        if saved is not None:
            self._restore_label(saved)
        elif self.review_mode == "assisted":
            score = record.get("human_score")
            if score is not None:
                prior = beauty_from_score(score, record.get("score_scale", "ava"))
                if prior:
                    self.beauty.set(prior)
                    self.assisted = True
                    self.assist_sources.add("human-score")
                    self.review_caption.set(
                        self.review_caption.get()
                        + f" Оценка корпуса {score} → {prior}; это только подсказка, проверь её."
                    )
        record_id = str(record["record_id"])
        short_id = record_id if len(record_id) <= 24 else record_id[:21] + "…"
        self.status.set(f"[{self.index + 1}/{len(self.queue)}] {self.review_mode} · {short_id}")
        self.record_caption.set(f"record_id: {record_id} · файл: {Path(record['image_path']).name}")
        self.provenance.set(provenance_caption(record))
        self._verify_source()
        self.render_image()
        self.refresh_regions()
        self._update_progress()

    def save_current(self) -> None:
        record = self.current
        if record is None:
            return
        if not self.human_confirmed.get():
            messagebox.showwarning("Разметка", "Подтверди human review перед сохранением")
            return
        if not self._verify_source():
            messagebox.showerror("Не сохранено", self.source_error or "исходный кадр не прошёл проверку")
            return
        unsure = self.unsure.get()
        if unsure:
            beauty = "unrated"
            improvement_needed = None
            issues: list[str] = []
            actions: list[str] = []
            forbidden_actions: list[str] = []
        else:
            if self.matrix_class.get() not in MATRIX_CLASSES:
                messagebox.showwarning("Разметка", "Выбери тип сцены для решённой разметки")
                return
            beauty = self.beauty.get()
            if not beauty:
                messagebox.showwarning("Разметка", "Сначала выбери: красиво / пограничное / некрасиво")
                return
            improvement_needed = bool(self.improvement_needed.get())
            issues = [name for name, var in self.issue_vars.items() if var.get()]
            actions = [name for name, var in self.action_vars.items() if var.get()]
            forbidden_actions = [name for name, var in self.forbidden_vars.items() if var.get()]
            if not improvement_needed:
                issues = []
                actions = [KEEP_ACTION]
            overlap = sorted(set(actions) & set(forbidden_actions))
            if overlap:
                messagebox.showwarning("Разметка", f"Одно действие нельзя отметить и как можно, и как нельзя: {overlap}")
                return
            if improvement_needed and not actions:
                messagebox.showwarning("Разметка", "Отметь, что сделать (или сними галочку «нужно улучшать»)")
                return
            if improvement_needed and not issues:
                messagebox.showwarning("Разметка", "Отметь, что мешает кадру")
                return
        subject_count = sum(region.get("role") == "subject" for region in self.regions)
        if not unsure and not self.roi_uncertain.get() and subject_count != 1:
            messagebox.showwarning(
                "ROI субъекта",
                "Для решённой разметки отметь ровно одну область subject "
                "или включи «ROI субъекта: не уверен / пропустить»."
            )
            return
        regions = (
            [region for region in self.regions if region.get("role") != "subject"]
            if self.roi_uncertain.get() else list(self.regions)
        )
        try:
            path = Path(record["image_path"])
            deltas = {
                name: round(float(self.delta_value[name].get()), 2)
                for name in DELTAS
                if self.delta_set[name].get()
            }
            assist_source = "+".join(sorted(self.assist_sources)) if self.assist_sources else None
            label = build_label(
                record_id=record["record_id"],
                image_sha256=str(record["image_sha256"]),
                annotator_id=self.annotator_id,
                beauty=beauty,
                improvement_needed=improvement_needed,
                issues=issues,
                actions=actions,
                forbidden_actions=forbidden_actions,
                regions=regions,
                deltas=None if unsure else deltas or None,
                unsure=unsure,
                notes=self.notes.get().strip(),
                image_path=str(path),
                provenance=record.get("provenance"),
                assisted=self.assisted,
                assist_source=assist_source,
                human_score=record.get("human_score") if self.review_mode == "assisted" else None,
                capture_intent=(self.capture_intent.get()
                                if self.capture_intent.get() in CAPTURE_INTENTS else None),
                review_mode=self.review_mode,
                teacher_proposal_id=(self.teacher_proposal_id if self.review_mode == "assisted" else None),
                matrix_class=(self.matrix_class.get() if self.matrix_class.get() in MATRIX_CLASSES else None),
            )
            appended = append_label(self.store, label)
        except Exception as exc:  # noqa: BLE001 - surface any admission error to the annotator
            messagebox.showerror("Не сохранено", str(exc))
            return
        self.status.set(f"Сохранено ({appended} записей)")
        self.index += 1
        self.load_current()

    def skip(self) -> None:
        self.index = min(self.index + 1, len(self.queue))
        self.load_current()

    def back(self) -> None:
        self.index = max(self.index - 1, 0)
        self.load_current()

    # ------------------------------------------------------------- behaviour
    def _clear_deltas(self) -> None:
        for name in DELTAS:
            self.delta_set[name].set(False)
            self.delta_value[name].set(0.0)

    def on_improvement_toggle(self) -> None:
        if not self.improvement_needed.get():
            self._clear_deltas()
            for var in self.issue_vars.values():
                var.set(False)
            for name, var in self.action_vars.items():
                var.set(name == KEEP_ACTION)

    def on_unsure_toggle(self) -> None:
        if self.unsure.get():
            self.beauty.set("unrated")
        elif self.beauty.get() == "unrated":
            self.beauty.set("")

    def _toggle_unsure(self) -> None:
        self.unsure.set(not self.unsure.get())
        self.on_unsure_toggle()

    def toggle_keep(self) -> None:
        self.improvement_needed.set(not self.improvement_needed.get())
        self.on_improvement_toggle()

    def apply_assist(self) -> None:
        """Pre-select boxes from cheap image heuristics (flagged as assisted)."""
        record = self.current
        if record is None or self.review_mode != "assisted":
            return
        hints = hints_for_image(Path(record["image_path"]))
        self.assisted = True
        self.assist_sources.add(ASSIST_SOURCE)
        self.human_confirmed.set(False)
        if hints.get("issues") or hints.get("actions"):
            self._clear_deltas()
            self.improvement_needed.set(True)
            self.on_improvement_toggle()
            for name in hints["issues"]:
                if name in self.issue_vars:
                    self.issue_vars[name].set(True)
            for name in hints["actions"]:
                if name in self.action_vars:
                    self.action_vars[name].set(True)
                    self.forbidden_vars[name].set(False)
        if hints.get("notes"):
            self.notes.set(hints["notes"])
        self.status.set(self.status.get().split("   ·   подсказка")[0] + "   ·   подсказка применена")

    def apply_teacher_proposal(self) -> None:
        """Copy a research proposal into editable controls; never save it directly."""
        proposal = self.teacher_proposal
        if self.review_mode != "assisted" or not proposal:
            return
        if not self.teacher_intent_matches:
            self.status.set(
                self.status.get().split("   ·   teacher")[0]
                + "   ·   teacher: выбери исходный intent предложения"
            )
            return
        self.assisted = True
        self.assist_sources.add("teacher-proposal")
        self.human_confirmed.set(False)
        self._clear_deltas()
        beauty = proposal.get("beauty")
        if beauty in BEAUTY_LEVELS:
            self.unsure.set(False)
            self.beauty.set(beauty)
        elif beauty == "unrated":
            self.unsure.set(True)
            self.on_unsure_toggle()
        if isinstance(proposal.get("improvement_needed"), bool):
            self.improvement_needed.set(proposal["improvement_needed"])
            self.on_improvement_toggle()
        for var in self.issue_vars.values():
            var.set(False)
        for var in self.action_vars.values():
            var.set(False)
        for var in self.forbidden_vars.values():
            var.set(False)
        for name in proposal.get("issues") or []:
            if name in self.issue_vars:
                self.issue_vars[name].set(True)
        for name in proposal.get("actions") or []:
            if name in self.action_vars and self.improvement_needed.get() and name != KEEP_ACTION:
                self.action_vars[name].set(True)
        if proposal.get("notes") is not None:
            self.notes.set(str(proposal.get("notes") or ""))
        regions = [self._clip_region(region) for region in proposal.get("regions") or []]
        self.regions = [region for region in regions if region is not None]
        self.selected_region = max(0, len(self.regions) - 1)
        self._sync_region_fields()
        self.refresh_regions()
        self.status.set(self.status.get().split("   ·   teacher")[0] + "   ·   teacher: проверь и исправь вручную")

    def apply_suggestions(self) -> None:
        """Turn the free-text note into pre-selected boxes (suggestions only)."""
        if self.review_mode != "assisted":
            return
        suggestion = suggest(self.notes.get())
        if suggestion["keep"] or suggestion["issues"] or suggestion["actions"]:
            self._clear_deltas()
            self.assisted = True
            self.assist_sources.add("phrase-suggestions")
            self.human_confirmed.set(False)
        if suggestion["keep"]:
            # "задумано / настроение / силуэт" — confirm instead of fixing.
            self.improvement_needed.set(False)
            self.on_improvement_toggle()
            return
        if suggestion["issues"] or suggestion["actions"]:
            self.improvement_needed.set(True)
            self.on_improvement_toggle()
            for name in suggestion["issues"]:
                self.issue_vars[name].set(True)
            for name in suggestion["actions"]:
                self.action_vars[name].set(True)
                self.forbidden_vars[name].set(False)

    # ---------------------------------------------------------------- canvas
    def render_image(self) -> None:
        record = self.current
        self.canvas.delete("all")
        if record is None:
            return
        path = Path(record["image_path"])
        if not path.exists():
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66",
                                    text=f"нет файла: {path}")
            self.image_size = (1, 1)
            self.image_ready = False
            self.image_info.set(self.source_error or f"нет файла: {path}")
            return
        try:
            from PIL import Image, ImageOps, ImageTk  # imported lazily so --help works without Pillow
        except ImportError as exc:
            self.image_ready = False
            self.source_error = f"не установлен Pillow: {exc}"
            self.image_info.set(self.source_error)
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66", text=self.source_error)
            return

        source_error = self.source_error
        try:
            with Image.open(path) as opened:
                self.image_orientation = int(opened.getexif().get(274, 1) or 1)
                image = ImageOps.exif_transpose(opened).convert("RGB")
        except Exception as exc:  # noqa: BLE001 - show unreadable source in the canvas
            self.image_ready = False
            self.source_error = f"кадр не читается: {exc}"
            self.image_info.set(self.source_error)
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66", text=self.source_error)
            self.image_size = (1, 1)
            return
        self.image_ready = not source_error
        if source_error:
            self.image_info.set(
                f"{image.width}×{image.height} · EXIF {self.image_orientation}: "
                f"{EXIF_ORIENTATION_LABELS.get(self.image_orientation, 'неизвестно')} · {source_error}"
            )
        else:
            self.image_info.set(
                f"{image.width}×{image.height} · EXIF {self.image_orientation}: "
                f"{EXIF_ORIENTATION_LABELS.get(self.image_orientation, 'неизвестно')}"
            )
        self.image_size = image.size
        width = self.canvas.winfo_width()
        height = self.canvas.winfo_height()
        if width <= 1 or height <= 1:  # not laid out yet — retry once idle
            self.root.after_idle(self.render_image)
            return
        pad = 8
        if self.auto_fit:
            self.scale = min((width - 2 * pad) / image.width, (height - 2 * pad) / image.height)
        target = (max(1, int(image.width * self.scale)), max(1, int(image.height * self.scale)))
        self.offset = ((width - target[0]) / 2, (height - target[1]) / 2)
        self.photo = ImageTk.PhotoImage(image.resize(target))
        self.canvas.create_image(self.offset[0], self.offset[1], anchor="nw", image=self.photo)
        self.draw_regions()

    def on_canvas_resize(self, _event=None) -> None:
        """Keep the frame fitted when the window is resized or first shown."""
        if self.auto_fit:
            self.render_image()

    def on_wheel(self, event) -> str:
        record = self.current
        if record is None:
            return "break"
        self.auto_fit = False
        delta = getattr(event, "delta", 0)
        wheel_up = delta > 0 or getattr(event, "num", None) == 4
        self.scale *= 1.1 if wheel_up else 1 / 1.1
        self.scale = max(0.02, min(self.scale, 12.0))
        try:
            from PIL import Image, ImageOps, ImageTk
        except ImportError as exc:
            self.image_ready = False
            self.source_verified = False
            self.source_error = f"не установлен Pillow: {exc}"
            self.image_info.set(self.source_error)
            self.canvas.delete("all")
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66", text=self.source_error)
            return "break"

        try:
            with Image.open(record["image_path"]) as opened:
                image = ImageOps.exif_transpose(opened).convert("RGB")
        except Exception as exc:  # noqa: BLE001 - wheel should not crash on a changed file
            self.image_ready = False
            self.source_verified = False
            self.source_error = f"кадр не читается: {exc}"
            self.image_info.set(self.source_error)
            self.canvas.delete("all")
            self.canvas.create_text(20, 20, anchor="nw", fill="#f66", text=self.source_error)
            return "break"
        target = (max(1, int(image.width * self.scale)), max(1, int(image.height * self.scale)))
        self.photo = ImageTk.PhotoImage(image.resize(target))
        self.canvas.delete("all")
        self.offset = (
            max(8, min(self.offset[0], self.canvas.winfo_width() - target[0] - 8)),
            max(8, min(self.offset[1], self.canvas.winfo_height() - target[1] - 8)),
        )
        self.canvas.create_image(self.offset[0], self.offset[1], anchor="nw", image=self.photo)
        self.draw_regions()
        return "break"

    def to_image_xy(self, x: float, y: float) -> tuple[float, float]:
        return ((x - self.offset[0]) / self.scale, (y - self.offset[1]) / self.scale)

    def on_press(self, event) -> None:
        if self.current is None or self.image_size[0] <= 1 or self.image_size[1] <= 1:
            return
        ix, iy = self.to_image_xy(event.x, event.y)
        self.region_draft = (ix, iy, ix, iy)

    def on_drag(self, event) -> None:
        if self.region_draft is None:
            return
        ix, iy = self.to_image_xy(event.x, event.y)
        self.region_draft = (self.region_draft[0], self.region_draft[1], ix, iy)
        self.draw_regions()

    def on_release(self, event) -> None:
        if self.region_draft is None:
            return
        x0, y0, x1, y1 = self.region_draft
        self.region_draft = None
        left, right = sorted((x0, x1))
        top, bottom = sorted((y0, y1))
        width, height = self.image_size
        if width <= 1 or height <= 1:
            return
        # Clip in pixel space before converting to normalized coordinates so
        # an out-of-frame drag can never produce x+w or y+h greater than 1.
        left = max(0.0, min(float(width), left))
        right = max(0.0, min(float(width), right))
        top = max(0.0, min(float(height), top))
        bottom = max(0.0, min(float(height), bottom))
        rect = [
            left / width,
            top / height,
            (right - left) / width,
            (bottom - top) / height,
        ]
        if rect[2] < 0.01 or rect[3] < 0.01:
            return
        region = {"role": self.role.get(), "rect": [round(v, 4) for v in rect]}
        label = self.region_label.get().strip()
        if label:
            region["label"] = label
        self.regions.append(region)
        self.selected_region = len(self.regions) - 1
        self.refresh_regions()

    @staticmethod
    def _clip_region(region: dict) -> dict | None:
        if not isinstance(region, dict):
            return None
        rect = region.get("rect")
        if not isinstance(rect, (list, tuple)) or len(rect) != 4:
            return None
        try:
            x, y, w, h = (float(value) for value in rect)
        except (TypeError, ValueError):
            return None
        x = max(0.0, min(1.0, x))
        y = max(0.0, min(1.0, y))
        right = max(x, min(1.0, x + max(0.0, w)))
        bottom = max(y, min(1.0, y + max(0.0, h)))
        if right - x < 0.0001 or bottom - y < 0.0001:
            return None
        role = region.get("role") if region.get("role") in REGION_ROLES else "problem"
        clipped = {"role": role, "rect": [round(x, 4), round(y, 4), round(right - x, 4), round(bottom - y, 4)]}
        label = str(region.get("label") or "").strip()
        if label:
            clipped["label"] = label
        return clipped

    def _sync_region_fields(self) -> None:
        if 0 <= self.selected_region < len(self.regions):
            region = self.regions[self.selected_region]
            self.role.set(region.get("role", REGION_ROLES[0]))
            self.region_label.set(str(region.get("label") or ""))
        else:
            self.role.set(REGION_ROLES[0])
            self.region_label.set("")

    def draw_regions(self) -> None:
        self.canvas.delete("region")
        for index, region in enumerate(self.regions):
            x, y, w, h = region["rect"]
            box = (
                self.offset[0] + x * self.image_size[0] * self.scale,
                self.offset[1] + y * self.image_size[1] * self.scale,
                self.offset[0] + (x + w) * self.image_size[0] * self.scale,
                self.offset[1] + (y + h) * self.image_size[1] * self.scale,
            )
            colour = "#ff9f0a" if index == self.selected_region else "#30d158"
            self.canvas.create_rectangle(*box, outline=colour, width=2, tags="region")
            self.canvas.create_text(box[0] + 4, box[1] + 4, anchor="nw", fill=colour,
                                    text=f"{index}:{region['role']}"
                                    f"{(' · ' + region['label']) if region.get('label') else ''}", tags="region")
        if self.region_draft is not None:
            x0, y0, x1, y1 = self.region_draft
            self.canvas.create_rectangle(
                self.offset[0] + x0 * self.scale, self.offset[1] + y0 * self.scale,
                self.offset[0] + x1 * self.scale, self.offset[1] + y1 * self.scale,
                outline="#0a84ff", dash=(4, 2), tags="region",
            )

    def refresh_regions(self) -> None:
        self.region_list.delete(0, tk.END)
        for index, region in enumerate(self.regions):
            x, y, w, h = region["rect"]
            self.region_list.insert(
                tk.END, f"{index}. {region['role']}"
                f"{(' · ' + region['label']) if region.get('label') else ''}"
                f"  x={x:.2f} y={y:.2f} w={w:.2f} h={h:.2f}"
            )
        if self.regions and 0 <= self.selected_region < len(self.regions):
            self.region_list.selection_set(self.selected_region)
            self.region_list.see(self.selected_region)
            self._sync_region_fields()
        self.draw_regions()

    def on_region_select(self, _event=None) -> None:
        selection = self.region_list.curselection()
        if selection:
            self.selected_region = int(selection[0])
            self._sync_region_fields()
            self.draw_regions()

    def change_role(self) -> None:
        if 0 <= self.selected_region < len(self.regions):
            self.regions[self.selected_region]["role"] = self.role.get()
            self.refresh_regions()

    def change_region_label(self) -> None:
        if 0 <= self.selected_region < len(self.regions):
            label = self.region_label.get().strip()
            if label:
                self.regions[self.selected_region]["label"] = label
            else:
                self.regions[self.selected_region].pop("label", None)
            self.refresh_regions()

    def delete_region(self) -> None:
        if 0 <= self.selected_region < len(self.regions):
            self.regions.pop(self.selected_region)
            self.selected_region = max(0, self.selected_region - 1)
            self.refresh_regions()

    def clear_draft(self) -> None:
        self.region_draft = None
        self.draw_regions()


def load_queue(path: Path) -> list[dict]:
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--queue", type=Path, required=True)
    parser.add_argument("--store", type=Path, required=True)
    parser.add_argument("--annotator-id", required=True)
    parser.add_argument("--redo", action="store_true",
                        help="не пропускать уже размеченные записи")
    args = parser.parse_args(argv)

    queue = load_queue(args.queue)
    blind_ids = {r["record_id"] for r in queue if r.get("review_mode", "blind") == "blind"}
    for label in load_labels(args.store):
        if label.get("annotator_id") == args.annotator_id and label.get("record_id") in blind_ids:
            if (label.get("review_mode") != "blind" or label.get("assisted")
                    or label.get("assist_source") or label.get("teacher_proposal_id")):
                raise ValueError("История содержит подсказанную/неизвестную разметку: нельзя открывать её как blind")
    if not args.redo:
        done = {
            label.get("record_id")
            for label in load_labels(args.store)
            if label.get("annotator_id") == args.annotator_id
        }
        queue = [r for r in queue if r["record_id"] not in done]
    if not queue:
        print(f"нечего размечать: очередь пуста или всё уже размечено ({args.store})")
        return 0

    root = tk.Tk()
    AnnotationApp(root, queue, args.store, args.annotator_id)
    root.mainloop()

    summary = load_labels(args.store)
    print(f"в сторе {len(summary)} записей: {args.store}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
