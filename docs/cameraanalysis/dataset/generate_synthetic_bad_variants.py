#!/usr/bin/env python3
"""Generate paired synthetic bad variants for Camera Analysis evals.

The generator intentionally uses deterministic image operations rather than a
generative model. That keeps the benchmark auditable: each bad frame has a
parent image, a recipe name, exact parameters, and an expected coaching action.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps


REPO_ROOT = Path(__file__).resolve().parents[3]
INBOX_DIR = REPO_ROOT / "docs/cameraanalysis/dataset/inbox"
IMAGES_DIR = INBOX_DIR / "images"
QA_DIR = INBOX_DIR / "qa"
SOURCE_MANIFEST_PATH = INBOX_DIR / "apple_tv_press_trailer_sources_108_157.jsonl"
OUTPUT_START = 178
OUTPUT_COUNT = 30
SOURCE_OFFSET = 20
OUTPUT_END = OUTPUT_START + OUTPUT_COUNT - 1
VARIANT_MANIFEST_PATH = INBOX_DIR / f"synthetic_bad_variants_{OUTPUT_START}_{OUTPUT_END}.jsonl"
SYNTHETIC_LABELS_PATH = INBOX_DIR / "semantic_labels_synthetic_bad_v1.jsonl"
SYNTHETIC_LABELS_CSV_PATH = INBOX_DIR / "semantic_labels_synthetic_bad_v1.csv"
SYNTHETIC_SUMMARY_PATH = INBOX_DIR / "semantic_labels_synthetic_bad_v1_summary.md"
IMAGE_MANIFEST_JSONL_PATH = INBOX_DIR / "images_manifest.jsonl"
IMAGE_MANIFEST_CSV_PATH = INBOX_DIR / "images_manifest.csv"
CONTACT_SHEET_PATH = QA_DIR / f"contact_sheet_{OUTPUT_START}_{OUTPUT_END}_synthetic_bad.jpg"


@dataclass(frozen=True)
class Recipe:
    name: str
    apply: Callable[[Image.Image, random.Random], tuple[Image.Image, dict[str, float | int | str]]]
    scene_type: str
    problems: list[str]
    technical_defects: list[str]
    expected_actions: list[str]
    future_actions: list[str]
    forbidden_actions: list[str]
    live_tip: str
    pause_summary: str
    tags: list[str]
    confidence_target: str = "high"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n", encoding="utf-8")


def _fit_canvas(img: Image.Image, background: tuple[int, int, int] = (18, 18, 18)) -> Image.Image:
    canvas = Image.new("RGB", img.size, background)
    return canvas


def _rotate_crooked(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float]]:
    angle = rng.choice([-1, 1]) * rng.uniform(7.0, 11.0)
    rotated = img.rotate(angle, resample=Image.Resampling.BICUBIC, expand=False, fillcolor=(18, 18, 18))
    return rotated, {"angle_degrees": round(angle, 3)}


def _overexposed_hotspot(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float]]:
    bright = ImageEnhance.Brightness(img).enhance(rng.uniform(1.35, 1.6))
    bright = ImageEnhance.Contrast(bright).enhance(rng.uniform(1.12, 1.28))
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    w, h = img.size
    cx = rng.randint(int(w * 0.58), int(w * 0.88))
    cy = rng.randint(int(h * 0.12), int(h * 0.45))
    rx = rng.randint(int(w * 0.10), int(w * 0.18))
    ry = rng.randint(int(h * 0.12), int(h * 0.24))
    draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(255, 245, 210, 185))
    glare = overlay.filter(ImageFilter.GaussianBlur(radius=36))
    result = Image.alpha_composite(bright.convert("RGBA"), glare).convert("RGB")
    return result, {"hotspot_center_x": cx, "hotspot_center_y": cy, "hotspot_radius_x": rx, "hotspot_radius_y": ry}


def _underexposed_subject(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float]]:
    dark = ImageEnhance.Brightness(img).enhance(rng.uniform(0.38, 0.52))
    dark = ImageEnhance.Contrast(dark).enhance(rng.uniform(0.82, 0.96))
    w, h = img.size
    vignette = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(vignette)
    draw.ellipse((-int(w * 0.10), -int(h * 0.20), int(w * 1.10), int(h * 1.15)), fill=210)
    vignette = ImageOps.invert(vignette.filter(ImageFilter.GaussianBlur(radius=90)))
    black = Image.new("RGB", img.size, (0, 0, 0))
    result = Image.composite(dark, black, vignette.point(lambda p: min(180, p)))
    return result, {"brightness_factor": 0.45, "vignette_radius": 90}


def _motion_blur(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float | int]]:
    radius = rng.randint(8, 14)
    blurred = img.filter(ImageFilter.GaussianBlur(radius=radius * 0.45))
    shifted = ImageChops.offset(blurred, rng.choice([-radius, radius]), 0)
    result = Image.blend(blurred, shifted, 0.52)
    return result, {"blur_radius": radius, "axis": "horizontal"}


def _too_much_empty_space(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float]]:
    w, h = img.size
    bg = img.resize((max(1, w // 8), max(1, h // 8)), Image.Resampling.BICUBIC)
    bg = bg.resize(img.size, Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(radius=18))
    bg = ImageEnhance.Brightness(bg).enhance(0.62)
    scale = rng.uniform(0.46, 0.56)
    small = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
    x = rng.randint(int(w * 0.03), int(w * 0.13))
    y = rng.randint(int(h * 0.26), int(h * 0.42))
    result = bg.copy()
    result.paste(small, (x, y))
    return result, {"subject_scale": round(scale, 3), "paste_x": x, "paste_y": y}


def _background_clutter(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, int]]:
    result = img.convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    w, h = img.size
    colors = [
        (255, 52, 52, 160),
        (255, 224, 70, 165),
        (40, 210, 255, 150),
        (255, 255, 255, 135),
    ]
    count = 12
    for _ in range(count):
        x = rng.randint(int(w * 0.02), int(w * 0.90))
        y = rng.randint(int(h * 0.04), int(h * 0.88))
        size = rng.randint(42, 120)
        color = rng.choice(colors)
        if rng.random() < 0.5:
            draw.rectangle((x, y, x + size, y + int(size * 0.45)), fill=color)
        else:
            draw.ellipse((x, y, x + size, y + size), fill=color)
    result = Image.alpha_composite(result, overlay.filter(ImageFilter.GaussianBlur(radius=1.2))).convert("RGB")
    return result, {"clutter_objects": count}


def _edge_cutoff(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float]]:
    w, h = img.size
    crop_left = int(w * rng.uniform(0.18, 0.26))
    crop_right = int(w * rng.uniform(0.02, 0.06))
    crop_top = int(h * rng.uniform(0.02, 0.08))
    crop_bottom = int(h * rng.uniform(0.04, 0.10))
    cropped = img.crop((crop_left, crop_top, w - crop_right, h - crop_bottom))
    result = cropped.resize((w, h), Image.Resampling.BICUBIC)
    return result, {
        "crop_left_ratio": round(crop_left / w, 3),
        "crop_right_ratio": round(crop_right / w, 3),
        "crop_top_ratio": round(crop_top / h, 3),
        "crop_bottom_ratio": round(crop_bottom / h, 3),
    }


def _low_contrast_noise(img: Image.Image, rng: random.Random) -> tuple[Image.Image, dict[str, float]]:
    grayish = ImageEnhance.Color(img).enhance(0.45)
    grayish = ImageEnhance.Contrast(grayish).enhance(0.48)
    grayish = ImageEnhance.Brightness(grayish).enhance(0.72)
    noise = Image.effect_noise(img.size, rng.uniform(34.0, 48.0)).convert("L")
    noise_rgb = Image.merge("RGB", (noise, noise, noise))
    result = Image.blend(grayish, noise_rgb, 0.18)
    return result, {"noise_sigma": 42.0, "contrast_factor": 0.48}


RECIPES: list[Recipe] = [
    Recipe(
        name="crooked_horizon",
        apply=_rotate_crooked,
        scene_type="synthetic_bad_crooked_frame",
        problems=["горизонт или вертикали заметно завалены"],
        technical_defects=[],
        expected_actions=["level_horizon"],
        future_actions=[],
        forbidden_actions=["keep_current_setup", "step_closer"],
        live_tip="Горизонт завален — выровняй кадр перед снимком.",
        pause_summary="Синтетический дефект: кадр повернут, поэтому ожидается подсказка выровнять горизонт.",
        tags=["synthetic_bad", "paired_variant", "crooked_horizon"],
    ),
    Recipe(
        name="overexposed_hotspot",
        apply=_overexposed_hotspot,
        scene_type="synthetic_bad_hotspot",
        problems=["яркое пятно отвлекает от основного объекта", "светлые области перетянуты"],
        technical_defects=["overexposure"],
        expected_actions=["remove_background_hotspot", "change_camera_angle"],
        future_actions=["reduce_exposure"],
        forbidden_actions=["keep_current_setup"],
        live_tip="Яркое пятно спорит с объектом — смени угол или снизь экспозицию.",
        pause_summary="Синтетический дефект: добавлен пересвеченный hotspot, поэтому ожидается убрать источник блика или изменить угол.",
        tags=["synthetic_bad", "paired_variant", "overexposure", "hotspot"],
    ),
    Recipe(
        name="underexposed_subject",
        apply=_underexposed_subject,
        scene_type="synthetic_bad_underexposed_subject",
        problems=["объект теряется в темноте", "недостаточно света на основном объекте"],
        technical_defects=["underexposure"],
        expected_actions=["add_front_fill_light", "rotate_subject_toward_light"],
        future_actions=["increase_exposure"],
        forbidden_actions=["keep_current_setup"],
        live_tip="Объект слишком темный — разверни его к свету или добавь передний свет.",
        pause_summary="Синтетический дефект: затемнение и виньетка скрывают объект, поэтому ожидается добавить свет или поднять экспозицию.",
        tags=["synthetic_bad", "paired_variant", "underexposure", "low_light"],
    ),
    Recipe(
        name="motion_blur",
        apply=_motion_blur,
        scene_type="synthetic_bad_motion_blur",
        problems=["детали смазаны движением камеры"],
        technical_defects=["motion_blur"],
        expected_actions=[],
        future_actions=["stabilize_camera"],
        forbidden_actions=["keep_current_setup", "level_horizon", "step_closer"],
        live_tip="Кадр смазан — зафиксируй камеру перед снимком.",
        pause_summary="Синтетический дефект: добавлен motion blur, поэтому это техническая проблема стабилизации, а не композиции.",
        tags=["synthetic_bad", "paired_variant", "motion_blur", "technical_gate"],
        confidence_target="medium",
    ),
    Recipe(
        name="too_much_empty_space",
        apply=_too_much_empty_space,
        scene_type="synthetic_bad_subject_too_small",
        problems=["основной объект занимает слишком мало кадра", "слишком много пустого пространства"],
        technical_defects=[],
        expected_actions=["step_closer"],
        future_actions=[],
        forbidden_actions=["keep_current_setup", "step_back"],
        live_tip="Объект теряется — подойди ближе или кадрируй плотнее.",
        pause_summary="Синтетический дефект: seed-кадр уменьшен на фоне, поэтому ожидается подсказка подойти ближе.",
        tags=["synthetic_bad", "paired_variant", "subject_too_small"],
    ),
    Recipe(
        name="background_clutter",
        apply=_background_clutter,
        scene_type="synthetic_bad_cluttered_background",
        problems=["фон перегружен яркими отвлекающими элементами"],
        technical_defects=[],
        expected_actions=["simplify_background", "remove_distracting_object"],
        future_actions=[],
        forbidden_actions=["keep_current_setup"],
        live_tip="Фон перегружен — убери лишние объекты или смени точку съемки.",
        pause_summary="Синтетический дефект: добавлены яркие отвлекающие формы, поэтому ожидается упростить фон.",
        tags=["synthetic_bad", "paired_variant", "background_clutter"],
    ),
    Recipe(
        name="edge_cutoff",
        apply=_edge_cutoff,
        scene_type="synthetic_bad_edge_cutoff",
        problems=["важные части сцены прижаты к краю или обрезаны"],
        technical_defects=["avoid_occlusion"],
        expected_actions=["step_back", "shift_frame_right"],
        future_actions=["avoid_occlusion"],
        forbidden_actions=["keep_current_setup", "step_closer"],
        live_tip="Край кадра режет объект — отойди назад или смести кадр вправо.",
        pause_summary="Синтетический дефект: кадр агрессивно обрезан слева, поэтому ожидается отойти назад или сместить рамку.",
        tags=["synthetic_bad", "paired_variant", "edge_cutoff", "occlusion"],
    ),
    Recipe(
        name="low_contrast_noise",
        apply=_low_contrast_noise,
        scene_type="synthetic_bad_low_contrast_noise",
        problems=["низкий контраст мешает отделить объект от фона", "заметен цифровой шум"],
        technical_defects=["low_contrast", "noise"],
        expected_actions=[],
        future_actions=["reduce_iso_noise", "increase_exposure"],
        forbidden_actions=["keep_current_setup", "level_horizon", "step_closer"],
        live_tip="Кадр шумный и плоский — добавь света или снизь ISO.",
        pause_summary="Синтетический дефект: снижены контраст и яркость, добавлен шум; это техническая проблема света/ISO.",
        tags=["synthetic_bad", "paired_variant", "low_contrast", "noise", "technical_gate"],
        confidence_target="medium",
    ),
]


def _build_label(
    *,
    output_index: int,
    output_filename: str,
    variant_path: str,
    parent: dict,
    recipe: Recipe,
    sha256: str,
    width: int,
    height: int,
) -> dict:
    return {
        "record_id": f"ca_img_{output_index:03d}",
        "filename": output_filename,
        "image_path": variant_path,
        "source_bucket": "synthetic_bad_paired_apple_tv_press",
        "source_dataset": "apple_tv_press_synthetic_degradation_v1",
        "width": width,
        "height": height,
        "sha256": sha256,
        "quality_label": "bad",
        "scene_type": recipe.scene_type,
        "primary_subject": "основной объект исходного промо-кадра",
        "positive_factors": [],
        "problems": recipe.problems,
        "technical_quality_defects": recipe.technical_defects,
        "expected_live_tip": recipe.live_tip,
        "expected_pause_summary": recipe.pause_summary,
        "expected_semantic_actions": recipe.expected_actions,
        "future_needed_actions": recipe.future_actions,
        "forbidden_actions": recipe.forbidden_actions,
        "confidence_target": recipe.confidence_target,
        "demo_priority": output_index < 168,
        "eval_tags": recipe.tags + [f"parent_{parent['filename'].split('.')[0]}"],
        "review_status": "synthetic_recipe_needs_human_spot_check",
        "label_source": "deterministic_synthetic_bad_variant_generator_2026-06-04",
        "parent_record_id": parent["record_id"],
        "parent_filename": parent["filename"],
        "synthetic_recipe": recipe.name,
    }


def _update_image_manifests(rows: list[dict]) -> None:
    existing = []
    if IMAGE_MANIFEST_JSONL_PATH.exists():
        for row in _read_jsonl(IMAGE_MANIFEST_JSONL_PATH):
            if not (OUTPUT_START <= int(row.get("index", -1)) <= OUTPUT_END):
                existing.append(row)

    manifest_rows = [
        {
            "filename": row["filename"],
            "path": row["image_path"],
            "index": row["index"],
            "extension": ".jpg",
            "label_quality": "bad_synthetic",
            "source_dataset": "synthetic_bad_paired_apple_tv_press",
            "mos": "",
            "source_filename": row["parent_filename"],
        }
        for row in rows
    ]
    combined = existing + manifest_rows
    _write_jsonl(IMAGE_MANIFEST_JSONL_PATH, combined)

    with IMAGE_MANIFEST_CSV_PATH.open("w", encoding="utf-8", newline="") as handle:
        fieldnames = ["filename", "path", "index", "extension", "label_quality", "source_dataset", "mos", "source_filename"]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in combined:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def _write_labels_csv(labels: list[dict]) -> None:
    with SYNTHETIC_LABELS_CSV_PATH.open("w", encoding="utf-8", newline="") as handle:
        fieldnames = [
            "record_id",
            "filename",
            "quality_label",
            "scene_type",
            "synthetic_recipe",
            "parent_filename",
            "expected_semantic_actions",
            "future_needed_actions",
            "forbidden_actions",
            "confidence_target",
            "review_status",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for label in labels:
            writer.writerow(
                {
                    "record_id": label["record_id"],
                    "filename": label["filename"],
                    "quality_label": label["quality_label"],
                    "scene_type": label["scene_type"],
                    "synthetic_recipe": label["synthetic_recipe"],
                    "parent_filename": label["parent_filename"],
                    "expected_semantic_actions": "|".join(label["expected_semantic_actions"]),
                    "future_needed_actions": "|".join(label["future_needed_actions"]),
                    "forbidden_actions": "|".join(label["forbidden_actions"]),
                    "confidence_target": label["confidence_target"],
                    "review_status": label["review_status"],
                }
            )


def _write_summary(labels: list[dict]) -> None:
    counts: dict[str, int] = {}
    for label in labels:
        counts[label["synthetic_recipe"]] = counts.get(label["synthetic_recipe"], 0) + 1
    rows = "\n".join(f"- `{name}`: {count}" for name, count in sorted(counts.items()))
    SYNTHETIC_SUMMARY_PATH.write_text(
        "\n".join(
            [
                "# Synthetic Bad Labels v1",
                "",
                "Status: deterministic synthetic benchmark expansion.",
                "Created: 2026-06-04.",
                "",
                f"This label set covers `{OUTPUT_START}...{OUTPUT_END}`, generated from Apple TV Press seed frames.",
                "It is intentionally separate from `semantic_labels_v1.jsonl` so the original 107-record silver set remains stable.",
                "",
                "## Recipe Counts",
                "",
                rows,
                "",
                "## Boundary",
                "",
                "- These are paired stress cases, not organic camera captures.",
                "- The expected actions are derived from known synthetic recipes and must be spot-checked before calling them gold.",
                "- Technical-only cases intentionally use `future_needed_actions` without composition actions.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def _write_contact_sheet(labels: list[dict]) -> None:
    files = [IMAGES_DIR / label["filename"] for label in labels]
    thumb_w, thumb_h = 240, 135
    label_h = 30
    cols = 10
    rows = math.ceil(len(files) / cols)
    sheet = Image.new("RGB", (cols * thumb_w, rows * (thumb_h + label_h)), "white")
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(files):
        img = Image.open(path).convert("RGB")
        img.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = (index % cols) * thumb_w + (thumb_w - img.width) // 2
        y = (index // cols) * (thumb_h + label_h) + (thumb_h - img.height) // 2
        sheet.paste(img, (x, y))
        label = labels[index]["filename"].split(".")[0] + "_" + labels[index]["synthetic_recipe"]
        draw.text(
            ((index % cols) * thumb_w + 6, (index // cols) * (thumb_h + label_h) + thumb_h + 7),
            label[:32],
            fill=(0, 0, 0),
        )
    QA_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(CONTACT_SHEET_PATH, quality=92)


def generate() -> None:
    source_rows = _read_jsonl(SOURCE_MANIFEST_PATH)
    if len(source_rows) != 50:
        raise SystemExit(f"Expected 50 source rows, got {len(source_rows)}")

    variant_rows: list[dict] = []
    labels: list[dict] = []

    selected_source_rows = source_rows[SOURCE_OFFSET : SOURCE_OFFSET + OUTPUT_COUNT]
    if len(selected_source_rows) != OUTPUT_COUNT:
        raise SystemExit(f"Expected {OUTPUT_COUNT} selected source rows, got {len(selected_source_rows)}")

    for offset, parent in enumerate(selected_source_rows):
        source_path = IMAGES_DIR / parent["filename"]
        if not source_path.exists():
            raise SystemExit(f"Missing source image: {source_path}")

        output_index = OUTPUT_START + offset
        output_filename = f"{output_index:03d}.jpg"
        output_path = IMAGES_DIR / output_filename
        recipe = RECIPES[offset % len(RECIPES)]
        seed = 20260604 + output_index
        rng = random.Random(seed)

        image = Image.open(source_path).convert("RGB")
        result, params = recipe.apply(image, rng)
        result.save(output_path, quality=92, optimize=True)

        variant_path = f"docs/cameraanalysis/dataset/inbox/images/{output_filename}"
        sha = _sha256(output_path)
        width, height = result.size
        variant_rows.append(
            {
                "record_id": f"ca_img_{output_index:03d}",
                "filename": output_filename,
                "image_path": variant_path,
                "index": output_index,
                "parent_record_id": parent["record_id"],
                "parent_filename": parent["filename"],
                "parent_source_slug": parent["source_slug"],
                "parent_source_page_url": parent["source_page_url"],
                "synthetic_recipe": recipe.name,
                "synthetic_seed": seed,
                "recipe_parameters": params,
                "width": width,
                "height": height,
                "sha256": sha,
                "label_status": "synthetic_recipe_needs_human_spot_check",
                "collected_at": "2026-06-04",
            }
        )
        labels.append(
            _build_label(
                output_index=output_index,
                output_filename=output_filename,
                variant_path=variant_path,
                parent=parent,
                recipe=recipe,
                sha256=sha,
                width=width,
                height=height,
            )
        )

    _write_jsonl(VARIANT_MANIFEST_PATH, variant_rows)
    _write_jsonl(SYNTHETIC_LABELS_PATH, labels)
    _write_labels_csv(labels)
    _write_summary(labels)
    _update_image_manifests(variant_rows)
    _write_contact_sheet(labels)
    print(f"generated {len(labels)} synthetic bad variants")
    print(VARIANT_MANIFEST_PATH)
    print(SYNTHETIC_LABELS_PATH)
    print(CONTACT_SHEET_PATH)


if __name__ == "__main__":
    generate()
