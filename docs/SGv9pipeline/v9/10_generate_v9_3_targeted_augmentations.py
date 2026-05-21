from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

try:
    from .datasets import build_v9_event_sft_rows, split_rows, write_jsonl
except ImportError:  # pragma: no cover
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[3]))
    from docs.SGv9pipeline.v9.datasets import build_v9_event_sft_rows, split_rows, write_jsonl


ACTORS = ["Дима", "Лиза", "Борис", "Яна", "Тимур", "Мила", "Катя", "Марат", "Олег", "Нина"]
OBJECTS = [
    ("блокнот", "блокнот"),
    ("конверт", "конверт"),
    ("папка", "папку"),
    ("карта", "карту"),
    ("планшет", "планшет"),
]
SURFACES = [("стол", "стол", "table"), ("стул", "стул", "chair"), ("стойка", "стойку", "counter")]
PLACES = [("шкаф", "cabinet"), ("киоск", "generic"), ("терминал", "generic")]
LINKERS = ["Потом", "После этого", "Затем", "А потом"]


def stable_hash(value: str, size: int = 8) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:size]


def actor(actor_id: str, ordinal: str, name: str) -> dict[str, Any]:
    return {"id": actor_id, "type": "human", "name": name, "labels": {"ordinal": ordinal}}


def obj(object_id: str, name: str, type_name: str = "generic", position: str = "center") -> dict[str, Any]:
    return {"id": object_id, "type": type_name, "name": name, "relative_position": position}


def action(
    action_id: str,
    actor_id: str,
    action_type: str,
    rank: int,
    *,
    target_id: str | None = None,
    holding_object: str | None = None,
    dialogue: str | None = None,
    resulting_pose: str = "standing",
) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": action_id,
        "actor_id": actor_id,
        "type": action_type,
        "resulting_pose": resulting_pose,
        "semantics": {"chronology_rank": rank},
    }
    if target_id:
        row["target_id"] = target_id
    if holding_object:
        row["holding_object"] = holding_object
    if dialogue:
        row["dialogue"] = dialogue
    return row


def beat(beat_id: str, phase: str, actions: list[dict[str, Any]]) -> dict[str, Any]:
    return {"id": beat_id, "phase": phase, "actions": actions}


def record(sample_id: str, pattern: str, text: str, tags: list[str], graph: dict[str, Any]) -> dict[str, Any]:
    return {
        "contract_version": "sg_v7_contract_v1",
        "cir_version": "sg_v9_3_targeted_cir_v1",
        "sample_id": sample_id,
        "graph_family_key": stable_hash(sample_id, 16),
        "pattern_name": pattern,
        "difficulty_bucket": "hard",
        "complexity_class": "targeted",
        "semantic_tags": sorted(set(tags + ["v9_3_targeted"])),
        "source_variant_key": "v9_3_targeted",
        "source_variant_text": text,
        "internal_metadata": {
            "canonical_source_template": text,
            "generator_name": "v9_3_targeted_augmentation_builder",
            "generator_version": "v1",
            "pattern_family": pattern,
        },
        "scene_graph": graph,
    }


def make_dialogue_put_down(index: int) -> dict[str, Any]:
    speaker = ACTORS[index % len(ACTORS)]
    actor_two = ACTORS[(index + 3) % len(ACTORS)]
    item_name, item_surface = OBJECTS[index % len(OBJECTS)]
    surface_name, surface_surface, surface_type = SURFACES[index % len(SURFACES)]
    linker = LINKERS[index % len(LINKERS)].lower()
    dialogue = f"Оставь {item_surface} здесь, потом подпишем."
    templates = [
        f"{speaker}: «{dialogue}», а второй актер {actor_two} кладет {item_surface} на {surface_surface}.",
        f"Первый актер говорит второму: «{dialogue}» {linker} второй кладет {item_surface} на {surface_surface}.",
        f"{speaker} говорит: «{dialogue}» {linker} {actor_two} аккуратно кладет {item_surface} на {surface_surface}.",
    ]
    text = templates[index % len(templates)]
    graph = {
        "actors": [actor("actor_1", "first", speaker), actor("actor_2", "second", actor_two)],
        "objects": [obj("object_1", item_name), obj("object_2", surface_name, surface_type, "left")],
        "beats": [
            beat("beat_1", "dialogue_exchange", [action("action_1", "actor_1", "talk", 1, target_id="actor_2", dialogue=dialogue)]),
            beat(
                "beat_2",
                "putdown_object",
                [action("action_2", "actor_2", "put_down", 2, target_id="object_2", holding_object="object_1")],
            ),
        ],
        "spatial_relations": [{"id": "rel_1", "subject": "object_1", "relation": "near", "object": "object_2"}],
        "reference_bindings": {"ordinal_map": {"first": "actor_1", "second": "actor_2"}},
        "must_preserve": ["dialogue_action_split", "put_down_not_collapsed_into_dialogue"],
    }
    return record(
        f"v9_3_dialogue_then_put_down_object__targeted__{index:04d}__{stable_hash(text)}",
        "dialogue_then_put_down_object",
        text,
        ["dialogue_action", "put_down", "two_actor", "coverage_missing"],
        graph,
    )


def make_three_actor_give(index: int) -> dict[str, Any]:
    first = ACTORS[index % len(ACTORS)]
    second = ACTORS[(index + 1) % len(ACTORS)]
    third = ACTORS[(index + 2) % len(ACTORS)]
    item_name, item_surface = OBJECTS[index % len(OBJECTS)]
    linker = LINKERS[index % len(LINKERS)]
    line_one = f"Отдай {item_surface} третьему."
    line_two = "Принял, передам."
    templates = [
        f"{first} говорит: «{line_one}», а {second} отвечает: «{line_two}». {linker} второй берёт {item_surface} и передаёт его {third}.",
        f"Первый актер говорит второму: «{line_one}» Второй отвечает: «{line_two}» {linker.lower()} второй берет {item_surface} и отдает третьему.",
        f"{first}: «{line_one}» {second}: «{line_two}» {linker} второй поднимает {item_surface}, затем передает его третьему актеру {third}.",
    ]
    text = templates[index % len(templates)]
    graph = {
        "actors": [
            actor("actor_1", "first", first),
            actor("actor_2", "second", second),
            actor("actor_3", "third", third),
        ],
        "objects": [obj("object_1", item_name)],
        "beats": [
            beat(
                "beat_1",
                "dialogue_exchange",
                [
                    action("action_1", "actor_1", "talk", 1, target_id="actor_2", dialogue=line_one),
                    action("action_2", "actor_2", "talk", 2, target_id="actor_1", dialogue=line_two),
                ],
            ),
            beat(
                "beat_2",
                "pickup_object",
                [action("action_3", "actor_2", "pick_up", 3, target_id="object_1", holding_object="object_1")],
            ),
            beat(
                "beat_3",
                "give_to_third",
                [action("action_4", "actor_2", "give", 4, target_id="actor_3", holding_object="object_1")],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {"ordinal_map": {"first": "actor_1", "second": "actor_2", "third": "actor_3"}},
        "must_preserve": ["three_actor_ordinal_binding", "give_target_actor_3", "holding_object_preserved"],
    }
    return record(
        f"v9_3_dialogue_pick_up_give_third__targeted__{index:04d}__{stable_hash(text)}",
        "dialogue_then_pick_up_object_then_give_to_third_actor",
        text,
        ["three_actor", "ordinal_cases", "pick_up", "give", "three_beat_cases"],
        graph,
    )


def make_three_actor_ordinal_status(index: int) -> dict[str, Any]:
    first = ACTORS[(index + 4) % len(ACTORS)]
    second = ACTORS[(index + 5) % len(ACTORS)]
    third = ACTORS[(index + 6) % len(ACTORS)]
    place_one, type_one = PLACES[index % len(PLACES)]
    place_two, type_two = PLACES[(index + 1) % len(PLACES)]
    templates = [
        f"Первый актер подходит к {place_one}, второй держится рядом, а третий остаётся у {place_two}.",
        f"{first} подходит к {place_one}; второй актер {second} смотрит на первого, третий {third} стоит у {place_two}.",
        f"Первый направляется к {place_one}, второй остается рядом с первым, а третий ждет около {place_two}.",
    ]
    text = templates[index % len(templates)]
    graph = {
        "actors": [
            actor("actor_1", "first", first),
            actor("actor_2", "second", second),
            actor("actor_3", "third", third),
        ],
        "objects": [obj("object_1", place_one, type_one, "left"), obj("object_2", place_two, type_two, "right")],
        "beats": [
            beat(
                "beat_1",
                "ordinal_status",
                [
                    action("action_1", "actor_1", "approach", 1, target_id="object_1", resulting_pose="walking"),
                    action("action_2", "actor_2", "look_at", 2, target_id="actor_1"),
                    action("action_3", "actor_3", "stand", 3),
                ],
            )
        ],
        "spatial_relations": [
            {"id": "rel_1", "subject": "actor_1", "relation": "near", "object": "object_1"},
            {"id": "rel_2", "subject": "actor_3", "relation": "near", "object": "object_2"},
        ],
        "reference_bindings": {"ordinal_map": {"first": "actor_1", "second": "actor_2", "third": "actor_3"}},
        "must_preserve": ["second_actor_look_at_first", "third_actor_stand_no_target"],
    }
    return record(
        f"v9_3_ordinal_first_second_third__targeted__{index:04d}__{stable_hash(text)}",
        "ordinal_first_second_third",
        text,
        ["three_actor", "ordinal_cases", "stand", "look_at", "approach"],
        graph,
    )


def validate_rows(rows: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for row in rows:
        sample_id = str(row.get("sample_id") or "")
        if not sample_id:
            errors.append("missing_sample_id")
        if sample_id in seen:
            errors.append(f"duplicate_sample_id:{sample_id}")
        seen.add(sample_id)
        if not str(row.get("source_variant_text") or "").strip():
            errors.append(f"{sample_id}:missing_source_text")
        if not row.get("scene_graph", {}).get("beats"):
            errors.append(f"{sample_id}:missing_beats")
    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dialogue-put-down-count", type=int, default=60)
    parser.add_argument("--three-actor-give-count", type=int, default=90)
    parser.add_argument("--three-actor-status-count", type=int, default=90)
    parser.add_argument("--val-fraction", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    cir_rows: list[dict[str, Any]] = []
    cir_rows.extend(make_dialogue_put_down(index) for index in range(args.dialogue_put_down_count))
    cir_rows.extend(make_three_actor_give(index) for index in range(args.three_actor_give_count))
    cir_rows.extend(make_three_actor_ordinal_status(index) for index in range(args.three_actor_status_count))
    errors = validate_rows(cir_rows)
    if errors:
        raise ValueError(json.dumps(errors[:30], ensure_ascii=False, indent=2))

    sft_rows = build_v9_event_sft_rows(cir_rows)
    for row in sft_rows:
        metadata = row.setdefault("packaging_metadata", {})
        metadata["v9_3_targeted"] = True
        metadata["v9_3_source"] = "synthetic_policy_corrected_failure_augmentation"
        metadata["v9_3_training_target"] = "sg_v9_event_table_v1"

    train_rows, val_rows = split_rows(sft_rows, key_field="split_family_id", val_fraction=args.val_fraction, seed=args.seed)
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(cir_rows, output_dir / "v9_3_augmented_cir.jsonl")
    write_jsonl(sft_rows, output_dir / "v9_3_augmented_event_sft_all.jsonl")
    write_jsonl(train_rows, output_dir / "v9_3_augmented_event_sft_train.jsonl")
    write_jsonl(val_rows, output_dir / "v9_3_augmented_event_sft_val.jsonl")

    manifest = {
        "contract_version": "sg_v9_3_augmented_targeted_manifest_v1",
        "generated_rows": len(cir_rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "cluster_counts": {
            "dialogue_put_down": args.dialogue_put_down_count,
            "three_actor_give": args.three_actor_give_count,
            "three_actor_ordinal_status": args.three_actor_status_count,
        },
        "source": "synthetic_targeted_augmentation_from_policy_corrected_failures",
        "validation_errors": errors,
    }
    (output_dir / "v9_3_augmented_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
