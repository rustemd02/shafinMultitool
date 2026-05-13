from __future__ import annotations

import argparse
import hashlib
import json
from itertools import product
from pathlib import Path
from typing import Any

try:
    from .datasets import build_v9_event_sft_rows, split_rows, write_jsonl
except ImportError:  # pragma: no cover
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[3]))
    from docs.SGv9pipeline.v9.datasets import build_v9_event_sft_rows, split_rows, write_jsonl


ACTOR_NAMES = [
    "Павел",
    "Ира",
    "Тимур",
    "Марина",
    "Глеб",
    "Анна",
    "Лера",
    "Роман",
    "Яна",
    "Борис",
    "Нина",
    "Олег",
]

DIALOGUE_LINES = [
    "Оставь {object_acc} здесь, потом подпишем.",
    "Положи {object_acc} сюда, потом разберем.",
    "Пусть {object_acc} пока полежит тут, позже посмотрим.",
    "Оставь {object_acc} на месте, потом вернемся к этому.",
]

OBJECT_ITEMS = [
    {"lemma": "конверт", "surface": "конверт", "type": "generic"},
    {"lemma": "папка", "surface": "папку", "type": "generic"},
    {"lemma": "коробка", "surface": "коробку", "type": "generic"},
    {"lemma": "планшет", "surface": "планшет", "type": "generic"},
    {"lemma": "ключ-карта", "surface": "ключ-карту", "type": "generic"},
    {"lemma": "пакет", "surface": "пакет", "type": "generic"},
]

SUPPORT_ITEMS = [
    {"lemma": "стол", "surface": "стол", "type": "table", "position": "right"},
    {"lemma": "полка", "surface": "полку", "type": "shelf", "position": "left"},
    {"lemma": "стойка", "surface": "стойку", "type": "counter", "position": "center"},
    {"lemma": "лавка", "surface": "лавку", "type": "bench", "position": "right"},
    {"lemma": "подоконник", "surface": "подоконник", "type": "window", "position": "left"},
    {"lemma": "шкаф", "surface": "шкаф", "type": "cabinet", "position": "center"},
]

CONTAINER_ITEMS = [
    {"lemma": "ящик", "surface": "ящик", "type": "cabinet", "position": "center"},
    {"lemma": "шкаф", "surface": "шкаф", "type": "cabinet", "position": "right"},
    {"lemma": "кейс", "surface": "кейс", "type": "cabinet", "position": "left"},
    {"lemma": "контейнер", "surface": "контейнер", "type": "cabinet", "position": "center"},
]

MARKED_OBJECTS = [
    {"name": "рабочий компьютер", "near_surface": "рабочим компьютером", "stop_surface": "рабочего компьютера", "look_surface": "рабочий компьютер", "aliases": ["компьютер", "рабочий компьютер"], "type": "generic"},
    {"name": "терминал", "near_surface": "терминалом", "stop_surface": "терминала", "look_surface": "терминал", "aliases": ["терминал"], "type": "generic"},
    {"name": "киоск", "near_surface": "киоском", "stop_surface": "киоска", "look_surface": "киоск", "aliases": ["киоск"], "type": "generic"},
    {"name": "стойка", "near_surface": "стойкой", "stop_surface": "стойки", "look_surface": "стойку", "aliases": ["стойка"], "type": "generic"},
    {"name": "колонна", "near_surface": "колонной", "stop_surface": "колонны", "look_surface": "колонну", "aliases": ["колонна"], "type": "generic"},
    {"name": "шкаф", "near_surface": "шкафом", "stop_surface": "шкафа", "look_surface": "шкаф", "aliases": ["шкаф"], "type": "generic"},
]

DESCRIBED_ACTIONS = [
    "поднимает ладонь в знак паузы",
    "напряженно смотрит по сторонам",
    "поправляет воротник и смотрит на объект",
    "коротко кивает, не сводя взгляда с объекта",
]

TEMPORAL_LINKERS = ["затем", "после этого", "а потом", "потом"]


def stable_hash(value: str, size: int = 8) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:size]


def actor_row(actor_id: str, ordinal: str, name: str) -> dict[str, Any]:
    return {
        "id": actor_id,
        "type": "human",
        "name": name,
        "labels": {"ordinal": ordinal},
    }


def object_row(object_id: str, lemma: str, type_name: str, position: str, *, aliases: list[str] | None = None, marked: bool = False) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": object_id,
        "type": type_name,
        "name": lemma,
        "relative_position": position,
    }
    if marked:
        marker_short_id = object_id.removeprefix("object_marked_")
        row["marker_binding"] = {
            "kind": "marked",
            "marker_short_id": marker_short_id,
            "mentioned_aliases": aliases or [lemma],
            "source_name": lemma,
        }
    else:
        row["marker_binding"] = {"kind": "unmarked"}
    return row


def action_row(
    action_id: str,
    actor_id: str,
    action_type: str,
    chronology_rank: int,
    *,
    target_id: str | None = None,
    holding_object: str | None = None,
    dialogue: str | None = None,
    described_text: str | None = None,
    resulting_pose: str = "standing",
    direction: str | None = None,
) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": action_id,
        "actor_id": actor_id,
        "type": action_type,
        "resulting_pose": resulting_pose,
        "semantics": {"chronology_rank": chronology_rank},
    }
    if target_id:
        row["target_id"] = target_id
    if holding_object:
        row["holding_object"] = holding_object
    if dialogue:
        row["dialogue"] = dialogue
    if direction:
        row["direction"] = direction
    if described_text:
        row["described_action"] = {
            "canonical_text": described_text,
            "fallback_text": f"*{described_text}*",
            "source_lemma_hint": described_text.split()[0],
        }
        row["semantics"]["is_unsupported_runtime_action"] = True
        row["semantics"]["must_preserve_in_source"] = True
    return row


def beat_row(beat_id: str, phase: str, actions: list[dict[str, Any]]) -> dict[str, Any]:
    return {"id": beat_id, "phase": phase, "actions": actions}


def base_record(
    *,
    sample_id: str,
    pattern_name: str,
    difficulty_bucket: str,
    source_text: str,
    semantic_tags: list[str],
    scene_graph: dict[str, Any],
) -> dict[str, Any]:
    family_key = stable_hash(sample_id, 16)
    return {
        "contract_version": "sg_v7_contract_v1",
        "cir_version": "sg_v9_targeted_cir_v1",
        "sample_id": sample_id,
        "graph_family_key": family_key,
        "pattern_name": pattern_name,
        "difficulty_bucket": difficulty_bucket,
        "complexity_class": "targeted",
        "semantic_tags": semantic_tags,
        "source_variant_key": "v9_2_targeted",
        "source_variant_text": source_text,
        "internal_metadata": {
            "canonical_source_template": source_text,
            "generator_name": "v9_2_targeted_augmentation_builder",
            "generator_version": "v1",
            "pattern_family": pattern_name,
        },
        "scene_graph": scene_graph,
    }


def make_dialogue_action_row(index: int) -> dict[str, Any]:
    speaker = ACTOR_NAMES[index % len(ACTOR_NAMES)]
    receiver = ACTOR_NAMES[(index + 5) % len(ACTOR_NAMES)]
    obj = OBJECT_ITEMS[index % len(OBJECT_ITEMS)]
    support = SUPPORT_ITEMS[(index // 2) % len(SUPPORT_ITEMS)]
    linker = TEMPORAL_LINKERS[index % len(TEMPORAL_LINKERS)]
    dialogue = DIALOGUE_LINES[index % len(DIALOGUE_LINES)].format(object_acc=obj["surface"])
    templates = [
        f"{speaker}: «{dialogue}» {linker} {receiver} кладет {obj['surface']} на {support['surface']}.",
        f"Первый актер, {speaker}, говорит: «{dialogue}», а второй актер {receiver} кладет {obj['surface']} на {support['surface']}.",
        f"{speaker} тихо говорит второму: «{dialogue}». {linker.capitalize()} {receiver} кладет {obj['surface']} на {support['surface']}.",
    ]
    source_text = templates[index % len(templates)]
    scene_graph = {
        "actors": [
            actor_row("actor_1", "first", speaker),
            actor_row("actor_2", "second", receiver),
        ],
        "objects": [
            object_row("object_1", obj["lemma"], obj["type"], "center"),
            object_row("object_2", support["lemma"], support["type"], support["position"]),
        ],
        "beats": [
            beat_row(
                "beat_1",
                "dialogue_exchange",
                [action_row("action_1", "actor_1", "talk", 1, target_id="actor_2", dialogue=dialogue)],
            ),
            beat_row(
                "beat_2",
                "putdown_object",
                [action_row("action_2", "actor_2", "put_down", 2, target_id="object_2", holding_object="object_1")],
            ),
        ],
        "spatial_relations": [{"id": "rel_1", "subject": "object_1", "relation": "near", "object": "object_2"}],
        "reference_bindings": {"ordinal_map": {"first": "actor_1", "second": "actor_2"}},
        "must_preserve": ["dialogue_then_put_down", "holding_object_preserved"],
    }
    return base_record(
        sample_id=f"v9_2_dialogue_then_put_down_object__targeted__{index:04d}__{stable_hash(source_text)}",
        pattern_name="dialogue_then_put_down_object",
        difficulty_bucket="hard",
        source_text=source_text,
        semantic_tags=["dialogue_action", "dialogue", "put_down", "two_actor", "v9_2_targeted"],
        scene_graph=scene_graph,
    )


def make_put_pick_row(index: int) -> dict[str, Any]:
    actor = ACTOR_NAMES[(index * 3) % len(ACTOR_NAMES)]
    obj = OBJECT_ITEMS[index % len(OBJECT_ITEMS)]
    if index % 2 == 0:
        container = CONTAINER_ITEMS[(index // 2) % len(CONTAINER_ITEMS)]
        linker = TEMPORAL_LINKERS[index % len(TEMPORAL_LINKERS)]
        source_text = f"{actor} открывает {container['surface']}, {linker} берет {obj['surface']}."
        scene_graph = {
            "actors": [actor_row("actor_1", "first", actor)],
            "objects": [
                object_row("object_1", container["lemma"], container["type"], container["position"]),
                object_row("object_2", obj["lemma"], obj["type"], "unknown"),
            ],
            "beats": [
                beat_row("beat_1", "open_object", [action_row("action_1", "actor_1", "open", 1, target_id="object_1")]),
                beat_row(
                    "beat_2",
                    "pickup_object",
                    [action_row("action_2", "actor_1", "pick_up", 2, target_id="object_2", holding_object="object_2")],
                ),
            ],
            "spatial_relations": [{"id": "rel_1", "subject": "object_2", "relation": "inside", "object": "object_1"}],
            "reference_bindings": {"ordinal_map": {"first": "actor_1"}},
            "must_preserve": ["open_before_pick_up", "pickup_target:object_2"],
        }
        pattern_name = "open_then_pick_up_object"
        tags = ["put_pick", "open", "pick_up", "single_actor", "v9_2_targeted"]
    else:
        support = SUPPORT_ITEMS[(index // 2) % len(SUPPORT_ITEMS)]
        linker = TEMPORAL_LINKERS[(index + 1) % len(TEMPORAL_LINKERS)]
        source_text = f"{actor} берет {obj['surface']}, {linker} ставит {obj['surface']} на {support['surface']}."
        scene_graph = {
            "actors": [actor_row("actor_1", "first", actor)],
            "objects": [
                object_row("object_1", obj["lemma"], obj["type"], "center"),
                object_row("object_2", support["lemma"], support["type"], support["position"]),
            ],
            "beats": [
                beat_row(
                    "beat_1",
                    "pickup_object",
                    [action_row("action_1", "actor_1", "pick_up", 1, target_id="object_1", holding_object="object_1")],
                ),
                beat_row(
                    "beat_2",
                    "putdown_object",
                    [action_row("action_2", "actor_1", "put_down", 2, target_id="object_2", holding_object="object_1")],
                ),
            ],
            "spatial_relations": [{"id": "rel_1", "subject": "object_1", "relation": "near", "object": "object_2"}],
            "reference_bindings": {"ordinal_map": {"first": "actor_1"}},
            "must_preserve": ["pick_up_before_put_down", "put_down_target:object_2"],
        }
        pattern_name = "pick_up_then_put_down_object"
        tags = ["put_pick", "pick_up", "put_down", "single_actor", "v9_2_targeted"]
    return base_record(
        sample_id=f"v9_2_{pattern_name}__targeted__{index:04d}__{stable_hash(source_text)}",
        pattern_name=pattern_name,
        difficulty_bucket="hard",
        source_text=source_text,
        semantic_tags=tags,
        scene_graph=scene_graph,
    )


def make_stop_near_row(index: int) -> dict[str, Any]:
    marked = MARKED_OBJECTS[index % len(MARKED_OBJECTS)]
    described = DESCRIBED_ACTIONS[index % len(DESCRIBED_ACTIONS)]
    actor_one = ACTOR_NAMES[(index + 2) % len(ACTOR_NAMES)]
    actor_two = ACTOR_NAMES[(index + 7) % len(ACTOR_NAMES)]
    marker_short_id = stable_hash(f"{marked['name']}::{index}")
    object_id = f"object_marked_{marker_short_id}"
    linker = TEMPORAL_LINKERS[index % len(TEMPORAL_LINKERS)]
    if index % 2 == 0:
        source_text = (
            f"{actor_one} и {actor_two} сначала идут навстречу друг другу, {linker} оба останавливаются рядом с {marked['near_surface']}, "
            f"после этого первый {described}."
        )
        beats = [
            beat_row(
                "beat_1",
                "toward_each_other",
                [
                    action_row("action_1", "actor_1", "walk", 1, target_id="actor_2", resulting_pose="walking", direction="toward_each_other"),
                    action_row("action_2", "actor_2", "walk", 2, target_id="actor_1", resulting_pose="walking", direction="toward_each_other"),
                ],
            ),
            beat_row(
                "beat_2",
                "stop_near_object",
                [
                    action_row("action_3", "actor_1", "stop", 3, target_id=object_id),
                    action_row("action_4", "actor_2", "stop", 4, target_id=object_id),
                ],
            ),
            beat_row(
                "beat_3",
                "first_described_action",
                [action_row("action_5", "actor_1", "described_action", 5, described_text=described)],
            ),
        ]
        must_preserve = ["collective_stop_near_object", "described_action_after_stop"]
        pattern_name = "stop_near_marked_object_then_first_described_action"
    else:
        source_text = (
            f"Оба актера идут навстречу друг другу, {linker} останавливаются у {marked['stop_surface']}, "
            f"а потом второй смотрит на {marked['look_surface']}."
        )
        beats = [
            beat_row(
                "beat_1",
                "toward_each_other",
                [
                    action_row("action_1", "actor_1", "walk", 1, target_id="actor_2", resulting_pose="walking", direction="toward_each_other"),
                    action_row("action_2", "actor_2", "walk", 2, target_id="actor_1", resulting_pose="walking", direction="toward_each_other"),
                ],
            ),
            beat_row(
                "beat_2",
                "stop_near_object",
                [
                    action_row("action_3", "actor_1", "stop", 3, target_id=object_id),
                    action_row("action_4", "actor_2", "stop", 4, target_id=object_id),
                ],
            ),
            beat_row(
                "beat_3",
                "second_look_at_object",
                [action_row("action_5", "actor_2", "look_at", 5, target_id=object_id)],
            ),
        ]
        must_preserve = ["collective_stop_near_object", "second_actor_followup"]
        pattern_name = "toward_each_other_then_stop_near_marked_object_then_second_looks"
    scene_graph = {
        "actors": [
            actor_row("actor_1", "first", actor_one),
            actor_row("actor_2", "second", actor_two),
        ],
        "objects": [object_row(object_id, marked["name"], marked["type"], "center", aliases=marked["aliases"], marked=True)],
        "beats": beats,
        "spatial_relations": [
            {"id": "rel_1", "subject": "actor_1", "relation": "near", "object": object_id},
            {"id": "rel_2", "subject": "actor_2", "relation": "near", "object": object_id},
        ],
        "reference_bindings": {
            "ordinal_map": {"first": "actor_1", "second": "actor_2"},
            "marked_object_ids": [object_id],
            "alias_to_object_id": {alias: object_id for alias in marked["aliases"]},
        },
        "must_preserve": must_preserve,
    }
    return base_record(
        sample_id=f"v9_2_{pattern_name}__targeted__{index:04d}__{stable_hash(source_text)}",
        pattern_name=pattern_name,
        difficulty_bucket="hard",
        source_text=source_text,
        semantic_tags=["stop_near", "movement", "marked_object", "two_actor", "v9_2_targeted"],
        scene_graph=scene_graph,
    )


def validate_rows(rows: list[dict[str, Any]]) -> list[str]:
    sample_ids: set[str] = set()
    errors: list[str] = []
    for row in rows:
        sample_id = str(row.get("sample_id") or "")
        if not sample_id:
            errors.append("missing_sample_id")
            continue
        if sample_id in sample_ids:
            errors.append(f"duplicate_sample_id:{sample_id}")
        sample_ids.add(sample_id)
        source_text = str(row.get("source_variant_text") or "")
        if not source_text:
            errors.append(f"{sample_id}:missing_source_text")
        beats = row.get("scene_graph", {}).get("beats", [])
        if not beats:
            errors.append(f"{sample_id}:missing_beats")
    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dialogue-action-count", type=int, default=84)
    parser.add_argument("--put-pick-count", type=int, default=84)
    parser.add_argument("--stop-near-count", type=int, default=84)
    parser.add_argument("--val-fraction", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    generated: list[dict[str, Any]] = []
    generated.extend(make_dialogue_action_row(index) for index in range(args.dialogue_action_count))
    generated.extend(make_put_pick_row(index) for index in range(args.put_pick_count))
    generated.extend(make_stop_near_row(index) for index in range(args.stop_near_count))

    errors = validate_rows(generated)
    if errors:
        raise ValueError(json.dumps(errors[:20], ensure_ascii=False, indent=2))

    sft_rows = build_v9_event_sft_rows(generated)
    for row in sft_rows:
        metadata = row.setdefault("packaging_metadata", {})
        metadata["v9_2_targeted"] = True
        metadata["v9_2_source"] = "synthetic_cluster_augmentation"
        metadata["v9_2_training_target"] = "sg_v9_event_table_v1"

    train_rows, val_rows = split_rows(
        sft_rows,
        key_field="split_family_id",
        val_fraction=args.val_fraction,
        seed=args.seed,
    )

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(generated, output_dir / "v9_2_augmented_cir.jsonl")
    write_jsonl(sft_rows, output_dir / "v9_2_augmented_event_sft_all.jsonl")
    write_jsonl(train_rows, output_dir / "v9_2_augmented_event_sft_train.jsonl")
    write_jsonl(val_rows, output_dir / "v9_2_augmented_event_sft_val.jsonl")

    cluster_counts = {
        "dialogue_action": args.dialogue_action_count,
        "put_pick": args.put_pick_count,
        "stop_near": args.stop_near_count,
    }
    manifest = {
        "contract_version": "sg_v9_2_augmented_targeted_manifest_v1",
        "generated_rows": len(generated),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "cluster_counts": cluster_counts,
        "source": "synthetic_targeted_augmentation",
        "validation_errors": errors,
    }
    (output_dir / "v9_2_augmented_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
