#!/usr/bin/env python3
"""Assist hints for the annotation tool.

The annotator asked for pre-selection so they only correct instead of creating
labels from nothing. These hints come from cheap, explainable image statistics
— never from the trained model, so no model output leaks into the label store.

Honesty rules:
  * hints are SUGGESTIONS: saving a record still stores the annotator's values;
  * a saved record that used hints is flagged (`assisted=true`,
    `assist_source=...`) so downstream training can weigh or exclude it;
  * a human score shipped with the frame (AVA/AADB mean score) may pre-select
    the beauty level — that is real human data, not a model guess.
"""

from __future__ import annotations

from pathlib import Path

ASSIST_SOURCE = "heuristics-v1"

# Human score bands for the pre-selected beauty level when the corpus provides
# one. AVA uses 1..10, AADB uses 0..1; callers pass `score` in that raw scale
# plus `scale`.
AVA_BANDS = ((6.0, "beautiful"), (4.5, "borderline"))
AADB_BANDS = ((0.62, "beautiful"), (0.38, "borderline"))


def beauty_from_score(score: float | None, scale: str) -> str | None:
    if score is None:
        return None
    bands = AVA_BANDS if scale == "ava" else AADB_BANDS if scale == "aadb" else None
    if bands is None:
        return None
    for threshold, level in bands:
        if score >= threshold:
            return level
    return "ugly"


def hints_for_image(path: Path) -> dict:
    """Return {'issues': [...], 'actions': [...], 'notes': str} or empty."""
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        return {"issues": [], "actions": [], "notes": "нет Pillow/numpy — подсказки недоступны"}

    try:
        with Image.open(path) as image:
            gray = image.convert("L").resize((256, 256))
            array = np.asarray(gray, dtype=np.float32) / 255.0
    except Exception:
        return {"issues": [], "actions": [], "notes": "кадр не читается"}

    issues: list[str] = []
    actions: list[str] = []
    notes: list[str] = []

    mean_luma = float(array.mean())
    if mean_luma < 0.22:
        issues.append("scene_has_no_clear_focus")
        actions.append("add_front_fill_light")
        notes.append(f"мало света (mean luma {mean_luma:.2f})")
    elif mean_luma > 0.78:
        issues.append("background_competes_with_subject")
        actions.append("remove_background_hotspot")
        notes.append(f"кадр пересвечен (mean luma {mean_luma:.2f})")

    # Texture/edge energy: flat frames carry no readable subject structure.
    gy, gx = np.gradient(array)
    energy = float(np.sqrt(gx * gx + gy * gy).mean())
    if energy < 0.012:
        if "scene_has_no_clear_focus" not in issues:
            issues.append("scene_has_no_clear_focus")
        notes.append(f"низкая детализация (edge energy {energy:.3f})")

    # Clutter: how much edge energy sits in the outer frame vs the centre.
    height, width = array.shape
    border = np.zeros_like(array, dtype=bool)
    border[: height // 5, :] = True
    border[-height // 5 :, :] = True
    border[:, : width // 5] = True
    border[:, -width // 5 :] = True
    gy_full, gx_full = np.gradient(array)
    magnitude = np.sqrt(gx_full * gx_full + gy_full * gy_full)
    border_ratio = float(magnitude[border].mean() / (magnitude.mean() + 1e-6))
    if border_ratio > 1.25:
        if "background_competes_with_subject" not in issues:
            issues.append("background_competes_with_subject")
        actions.append("simplify_background")
        notes.append(f"фон шумнее центра (border ratio {border_ratio:.2f})")

    actions = list(dict.fromkeys(actions))
    return {"issues": issues, "actions": actions, "notes": "; ".join(notes), "source": ASSIST_SOURCE}
