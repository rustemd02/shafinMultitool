#!/usr/bin/env python3
"""build_fast_seeds — скрытые QC-сиды для annotate_fast из silver-пар DATA (research-only).

Читает манифест silver-пар (camera-silver-action-pair-v1) из
`local-data/SETOS/Datasets/camera-coach/silver-fit-20260918/` и строит seeds.jsonl
для очереди быстрой разметки: пары с однозначным аналитическим рецептом
(crop_translate / rotate_horizon / crop_zoom_in) становятся кадрами с известной
правдой — expected_verdict=needs_fix + expected_issue + expected_action.

Что считается «однозначным»:

- рецепт входит в белый список;
- positives таргетов пары строго совпадают с ожиданием рецепта
  (rotate_horizon → horizon_distracts + level_horizon;
   crop_zoom_in → subject_too_close_to_edge + step_back;
   crop_translate → subject_too_close_to_edge + shift_frame_{left,right,up,down}
   с положительным действием, взятым из самой пары);
- производный кадр (derivative — именно он показывается аннотатору: это
  «испорченная» версия) существует на диске и его sha256 совпадает с манифестом.

Отбор детерминированный: кандидаты сортируются по sha256 производного кадра,
баланс по рецептам (для 8 сидов: 3 translate / 3 rotate / 2 zoom). Ни случайности,
ни «dramatis personae» — если однозначных пар меньше 6, построение честно падает.

Сиды — аналитическая silver-правда (research_only, human_gold=false,
release_admissible=false); disagreement с ними — сигнал про аннотатора/инструмент,
не «ошибка», которую надо подгонять.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))

from annotation_labels import sha256_file  # noqa: E402

DEFAULT_PAIRS = Path(
    "/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/"
    "Datasets/camera-coach/silver-fit-20260918/pairs/pairs.jsonl"
)
DEFAULT_OUT = Path(
    "/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/"
    "annotation/pilot-20260923-strata-v1/seeds.jsonl"
)

KEEP_ACTION = "keep_current_setup"
ALLOWED_RECIPES = ("crop_translate", "rotate_horizon", "crop_zoom_in")
MIN_SEEDS = 6
MAX_SEEDS = 10
DEFAULT_COUNT = 8

# Ожидание рецепта: (issue, допустимые действия). Для crop_translate действие
# берётся из положительного таргета самой пары (edge бывает left/right/…).
RECIPE_EXPECTATION: dict[str, tuple[str, set[str]]] = {
    "rotate_horizon": ("horizon_distracts", {"level_horizon"}),
    "crop_zoom_in": ("subject_too_close_to_edge", {"step_back"}),
    "crop_translate": ("subject_too_close_to_edge", {
        "shift_frame_left", "shift_frame_right", "shift_frame_up", "shift_frame_down",
    }),
}
RECIPE_STRATA = {
    "crop_translate": "composition",
    "crop_zoom_in": "composition",
    "rotate_horizon": "composition",
}


def load_pairs(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def positives(targets: dict, head: str) -> list[str]:
    """Имена с value==1 (keep_current_setup не считается позитивом исправления)."""
    block = targets.get(head) or {}
    names = block.get("ordered_names") or []
    values = block.get("values") or []
    return [n for n, v in zip(names, values) if v == 1 and n != KEEP_ACTION]


def candidate_from_pair(row: dict, pairs_dir: Path) -> dict | None:
    """Однозначная пара → сид-кандидат; любое расхождение → None (пара пропускается)."""
    recipe = (row.get("recipe") or {}).get("name")
    if recipe not in ALLOWED_RECIPES:
        return None
    expected_issue, allowed_actions = RECIPE_EXPECTATION[recipe]

    issues = positives(row.get("targets") or {}, "issue")
    actions = positives(row.get("targets") or {}, "action")
    if issues != [expected_issue]:
        return None
    if len(actions) != 1 or actions[0] not in allowed_actions:
        return None

    derivative = row.get("derivative") or {}
    rel = derivative.get("relative_path")
    if not rel:
        return None
    image_path = pairs_dir / rel
    if not image_path.exists():
        return None
    if sha256_file(image_path) != derivative.get("sha256"):
        return None

    pair_id = row.get("pair_id") or image_path.stem
    return {
        "sort_key": derivative["sha256"],
        "item": {
            "record_id": f"qcseed-{pair_id}",
            "package_record_id": (row.get("source") or {}).get("source_record_id"),
            "source_family_id": row.get("source_family_id")
            or (row.get("source") or {}).get("source_id"),
            "frame_path": rel,
            "image_path": str(image_path),
            "image_sha256": derivative["sha256"],
            "content_sha256": derivative["sha256"],
            "width": derivative.get("width"),
            "height": derivative.get("height"),
            "strata_group": RECIPE_STRATA[recipe],
            "intentional_style_flag": False,
            "status": "pending_human_review",
            "review_mode": "blind",
            "expected_verdict": "needs_fix",
            "expected_issue": expected_issue,
            "expected_action": actions[0],
            "provenance": {
                "kind": "silver_pair_derivative",
                "recipe": recipe,
                "pair_id": pair_id,
                "license": ((row.get("source") or {}).get("license") or "research-only silver pair"),
                "origin": "silver-fit-20260918/pairs",
            },
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
        },
    }


def recipe_counts(total: int) -> dict[str, int]:
    """Баланс рецептов для N сидов: translate/rotate поровну, zoom — остаток."""
    if total >= 8:
        zoom = max(2, total // 4)
    else:
        zoom = max(1, total // 4)
    rest = total - zoom
    rotate = rest // 2
    translate = rest - rotate
    return {"crop_translate": translate, "rotate_horizon": rotate, "crop_zoom_in": zoom}


def build_seeds(pairs_paths: list[Path], *, count: int = DEFAULT_COUNT) -> list[dict]:
    if not MIN_SEEDS <= count <= MAX_SEEDS:
        raise SystemExit(f"--count должен быть {MIN_SEEDS}..{MAX_SEEDS}")
    by_recipe: dict[str, list[dict]] = {name: [] for name in ALLOWED_RECIPES}
    for path in pairs_paths:
        pairs_dir = path.parent
        for row in load_pairs(path):
            candidate = candidate_from_pair(row, pairs_dir)
            if candidate is not None:
                recipe = (row.get("recipe") or {}).get("name")
                by_recipe[recipe].append(candidate)

    for name in ALLOWED_RECIPES:
        by_recipe[name].sort(key=lambda c: c["sort_key"])

    wanted = recipe_counts(count)
    chosen: list[dict] = []
    for name in ALLOWED_RECIPES:
        available = by_recipe[name]
        if len(available) < wanted[name]:
            raise SystemExit(
                f"недостаточно однозначных пар рецепта {name}: нужно {wanted[name]}, "
                f"есть {len(available)} (минимум {MIN_SEEDS} сидов обязателен, "
                "подгонка/ослабление фильтра запрещены)"
            )
        chosen.extend(available[: wanted[name]])
    chosen.sort(key=lambda c: c["sort_key"])
    return [c["item"] for c in chosen]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pairs", type=Path, action="append", default=None,
                        help=f"манифест silver-пар (по умолчанию: {DEFAULT_PAIRS})")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"куда писать seeds.jsonl (по умолчанию: {DEFAULT_OUT})")
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT,
                        help=f"сколько сидов строить ({MIN_SEEDS}..{MAX_SEEDS}; по умолчанию {DEFAULT_COUNT})")
    args = parser.parse_args(argv)

    pairs_paths = args.pairs or [DEFAULT_PAIRS]
    for path in pairs_paths:
        if not path.exists():
            print(f"манифест пар не найден: {path}", file=sys.stderr)
            return 1
    seeds = build_seeds(pairs_paths, count=args.count)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as handle:
        for item in seeds:
            handle.write(json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n")

    by_issue: dict[str, int] = {}
    for item in seeds:
        by_issue[item["expected_issue"]] = by_issue.get(item["expected_issue"], 0) + 1
    print(f"seeds: {len(seeds)} → {args.out}")
    recipes: dict[str, int] = {}
    for item in seeds:
        recipes[item["provenance"]["recipe"]] = recipes.get(item["provenance"]["recipe"], 0) + 1
    for name, n in sorted(recipes.items()):
        print(f"  {name}: {n}")
    for issue, n in sorted(by_issue.items()):
        print(f"  issue {issue}: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
