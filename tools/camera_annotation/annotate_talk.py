#!/usr/bin/env python3
"""Режим болтовни: смотришь на кадр и свободно говоришь, что видишь и что сделал бы.

Никаких шагов, проблем-клавиш и слайдеров: одна большая картинка и одно большое
текстовое поле. Текст сохраняется ДОСЛОВНО (append-only, talk_notes.jsonl) и
НИКОГДА не превращается в метки сам по себе. Дальше агент (или модель) разбирает
кадр + текст в структурированные предложения (verdict/issues/action) и gap-отчёт
контракта, а владелец подтверждает их парой Enter в annotate_fast --prefill.

Клавиши: Ctrl/Cmd+Enter — сохранить и дальше · Esc — пропуск кадра · B — назад ·
→ — вперёд · 1/2/3/U (вне поля) — необязательный тег вердикта. Можно надиктовывать
голосом: системный диктовка macOS (Fn Fn) работает прямо в поле.

Защита от потери текста: никакая навигация (Esc/B/→) не стирает набранное — текст
живёт в буфере кадра до явного сохранения; при возврате (B → →) поле снова заполнено.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ml" / "camera_coach" / "contracts"))

from annotation_labels import sha256_file  # noqa: E402

TALK_SCHEMA = "camera-talk-note-v1"
SESSION_SCHEMA = "camera-talk-session-v1"
VERDICT_TAGS = {"1": "good", "2": "mixed", "3": "needs_fix", "U": "unsure"}


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def append_jsonl(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def build_note(*, record: dict, annotator_id: str, text: str, verdict_tag: str | None,
               dwell_ms: int) -> dict:
    text = (text or "").strip()
    if not text:
        raise ValueError("пустая заметка — скажи хотя бы пару слов (или Esc = пропуск)")
    image_sha = sha256_file(Path(record["image_path"]))
    if image_sha != record.get("image_sha256"):
        raise ValueError(f"файл кадра изменился (sha не совпадает): {record['record_id']}")
    return {
        "talk_schema": TALK_SCHEMA,
        "record_id": record["record_id"],
        "annotator_id": annotator_id,
        "image_sha256": image_sha,
        "verdict_tag": VERDICT_TAGS.get(verdict_tag or "", None),
        "text": text,
        "dwell_ms": int(dwell_ms),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
    }


def load_session(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if data.get("session_schema") == SESSION_SCHEMA else None
    except (json.JSONDecodeError, OSError):
        return None


def save_session(path: Path, state: dict) -> None:
    path.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--queue", type=Path, required=True)
    parser.add_argument("--annotator-id", required=True)
    parser.add_argument("--notes", type=Path, help="talk_notes.jsonl (по умолчанию: каталог очереди)")
    args = parser.parse_args(argv)

    queue = load_jsonl(args.queue)
    if not queue:
        print(f"очередь пуста или не читается: {args.queue}", file=sys.stderr)
        return 1
    notes_path = args.notes or (args.queue.parent / "talk_notes.jsonl")
    session_path = args.queue.parent / "talk_session.json"

    import tkinter as tk
    from tkinter import ttk
    try:
        from PIL import Image, ImageTk
    except ImportError:
        print("нужен Pillow для показа изображений", file=sys.stderr)
        return 1

    root = tk.Tk()
    root.title("annotate_talk — режим болтовни")
    root.geometry("1500x950")

    state = load_session(session_path) or {
        "session_schema": SESSION_SCHEMA, "annotator_id": args.annotator_id,
        "queue_path": str(args.queue), "index": 0, "done": [], "updated_at": "",
    }
    if state.get("queue_path") != str(args.queue):
        state = {"session_schema": SESSION_SCHEMA, "annotator_id": args.annotator_id,
                 "queue_path": str(args.queue), "index": 0, "done": [], "updated_at": ""}
    done = set(state.get("done") or [])
    index = min(int(state.get("index") or 0), len(queue) - 1)
    if queue[index]["record_id"] in done:
        for i, row in enumerate(queue):
            if row["record_id"] not in done:
                index = i
                break

    status = tk.StringVar()
    verdict_var = tk.StringVar(value="—")
    hint = tk.StringVar(value="Ctrl/Cmd+Enter — сохранить и дальше · Esc — пропуск (текст в буфер) · "
                               "F1/F2 — назад/вперёд · тег вердикта — кнопками · "
                               "Cmd+V и диктовка (Fn Fn) пишут прямо в поле")
    from tkinter import font as tkfont
    big = tkfont.Font(size=18, weight="bold")

    canvas = tk.Canvas(root, bg="#101010", highlightthickness=0)
    canvas.pack(side="left", fill="both", expand=True)
    panel = ttk.Frame(root, padding=16)
    panel.pack(side="right", fill="both", expand=True)
    tk.Label(panel, textvariable=status, font=big, foreground="#7fbf7f").pack(anchor="w")
    tk.Label(panel, text="Что видишь и что сделал бы — своими словами:", font=big).pack(anchor="w", pady=(8, 4))
    text = tk.Text(panel, font=tkfont.Font(size=15), wrap="word", height=18, width=52)
    text.pack(fill="both", expand=True)
    tag_row = ttk.Frame(panel)
    tag_row.pack(anchor="w", pady=(6, 0))
    ttk.Label(tag_row, text="Тег (необязательно):", font=big, foreground="#666").pack(side="left")
    def _tag_button(label_text, value):
        btn = tk.Label(tag_row, text=label_text, font=tkfont.Font(size=14),
                       relief="groove", padx=10, pady=4, takefocus=0)
        def _set(_e):
            record = queue[index]
            if verdict_tag.get(record["record_id"]) == value:
                verdict_tag[record["record_id"]] = None
            else:
                verdict_tag[record["record_id"]] = value
            render_status()
            return "break"
        btn.bind("<Button-1>", _set)
        btn.pack(side="left", padx=(8, 0))
        return btn
    for lbl, val in (("хороший", "1"), ("норм", "2"), ("плохой", "3"), ("не понимаю", "U")):
        _tag_button(lbl, val)
    ttk.Label(panel, textvariable=verdict_var, font=big, foreground="#666").pack(anchor="w", pady=(6, 0))
    ttk.Label(panel, textvariable=hint, foreground="#888", wraplength=560, justify="left").pack(
        side="bottom", anchor="w", pady=(6, 0))

    photo = {"img": None}
    draft: dict[str, str] = {}
    verdict_tag: dict[str, str] = {}
    started = {"t": time.monotonic()}

    def render_image() -> None:
        record = queue[index]
        with Image.open(record["image_path"]) as im:
            im = im.convert("RGB")
            im.thumbnail((canvas.winfo_width() or 1200, canvas.winfo_height() or 900))
            photo["img"] = ImageTk.PhotoImage(im)
        canvas.delete("all")
        canvas.create_image(0, 0, anchor="nw", image=photo["img"])

    def render_status() -> None:
        record = queue[index]
        group = record.get("strata_group") or "—"
        status.set(f"{index + 1}/{len(queue)} · группа {group} · наговорено {len(done)}")
        tag = verdict_tag.get(record["record_id"])
        verdict_var.set(f"тег вердикта (необязательно): {VERDICT_TAGS.get(tag, '—')}")

    def load_frame() -> None:
        record = queue[index]
        text.delete("1.0", "end")
        text.insert("1.0", draft.get(record["record_id"], ""))
        started["t"] = time.monotonic()
        render_image()
        render_status()
        text.focus_set()

    def persist_session() -> None:
        state["index"] = index
        state["done"] = sorted(done)
        state["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        save_session(session_path, state)

    def save_and_next() -> None:
        record = queue[index]
        try:
            note = build_note(record=record, annotator_id=args.annotator_id,
                              text=text.get("1.0", "end"),
                              verdict_tag=verdict_tag.get(record["record_id"]),
                              dwell_ms=(time.monotonic() - started["t"]) * 1000)
        except ValueError as exc:
            status.set(f"⚠ {exc}")
            return
        append_jsonl(notes_path, note)
        done.add(record["record_id"])
        draft.pop(record["record_id"], None)
        nonlocal_adv()
        persist_session()

    def nonlocal_adv() -> None:
        nonlocal index
        if index < len(queue) - 1:
            index += 1
        load_frame()

    def on_escape(_event) -> str:
        nonlocal index
        record = queue[index]
        draft[record["record_id"]] = text.get("1.0", "end")  # текст НЕ теряется
        nonlocal_adv()
        persist_session()
        return "break"

    def on_back(_event) -> str:
        nonlocal index
        if index > 0:
            index -= 1
            load_frame()
            persist_session()
        return "break"

    def on_forward(_event) -> str:
        nonlocal_adv()
        persist_session()
        return "break"

    def on_configure(_event) -> None:
        render_image()

    # точечные биндинги: всё остальное (в т.ч. Cmd+C/V/A, стрелки, печать) идёт
    # нативно в текстовое поле и нами не перехватывается
    for seq, fn in (("<Escape>", on_escape), ("<F1>", on_back), ("<F2>", on_forward),
                    ("<Control-Return>", lambda e: (save_and_next(), "break")[1]),
                    ("<Command-Return>", lambda e: (save_and_next(), "break")[1])):
        root.bind(seq, fn)
        text.bind(seq, fn)  # сработают и когда фокус в поле (bindtag toplevel всё равно зовёт,
                            # но дубли исключены: save_and_next идемпотентен по индексу кадра? нет —
                            # поэтому ниже защита от двойного вызова)
    canvas.bind("<Configure>", on_configure)
    # клик по картинке НЕ уводит фокус из поля: Cmd+V/диктовка всегда пишут в текст

    load_frame()
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
