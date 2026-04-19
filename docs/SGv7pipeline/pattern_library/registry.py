from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Callable, Literal

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cir_contract.contracts import expected_sample_id
from cir_contract.contracts.cir_types import CIRRecord, SourceVariantKey
from .lexicon import (
    COMPUTER_MARKER_PROFILES,
    COMPUTER_OBLIQUE_FORMS,
    DIALOGUE_FIRST_TEMPLATES_BASE_FEMALE,
    DIALOGUE_FIRST_TEMPLATES_BASE_MALE,
    DIALOGUE_FIRST_TEMPLATES_COLLOQUIAL_FEMALE,
    DIALOGUE_FIRST_TEMPLATES_COLLOQUIAL_MALE,
    DIALOGUE_OBJECTS,
    DIALOGUE_SECOND_TEMPLATES_BASE,
    DIALOGUE_SECOND_TEMPLATES_COLLOQUIAL,
    DIALOGUE_THEN_PUT_DOWN_BASE_PAIRS,
    DIALOGUE_THEN_PUT_DOWN_MIX_PAIRS,
    DIALOGUE_THEN_PUT_DOWN_SURFACES,
    ENTER_THEN_PUT_DOWN_CARRIED,
    ENTER_THEN_PUT_DOWN_SURFACES,
    FEMALE_RUSSIAN_ACTOR_NAMES,
    HANDOFF_DIALOGUE_BASE_FIRST_TEMPLATES,
    HANDOFF_DIALOGUE_BASE_SECOND_TEMPLATES,
    HANDOFF_DIALOGUE_MIX_FIRST_TEMPLATES,
    HANDOFF_DIALOGUE_MIX_SECOND_TEMPLATES,
    HANDOFF_ITEM_PROFILES,
    OPEN_THEN_PICK_UP_CONTAINERS,
    OPEN_THEN_PICK_UP_ITEMS,
    PATTERN_SPEC_CANONICAL_TEMPLATES,
    PICK_UP_THEN_PUT_DOWN_ITEMS,
    PICK_UP_THEN_PUT_DOWN_SURFACES,
    RUSSIAN_ACTOR_NAMES,
    STOP_NEAR_FIRST_DESCRIBED_PROFILES,
    STOP_NEAR_THIRD_DESCRIBED_PROFILES,
    UNSUPPORTED_ACTION_DESCRIBED_PROFILES,
)


PATTERN_REGISTRY_VERSION = "sg_v7_pattern_library_v1"

DifficultyBucket = Literal["core", "hard"]
ComplexityClass = Literal["S", "M", "L"]
ObjectMode = Literal["none", "required_generic", "optional_generic", "required_marked", "required_same_type_marked_pair"]
RegistryPhase = Literal[
    "dialogue_exchange",
    "single_small_followup_action",
    "single_action",
    "mutual_walk_toward_each_other",
    "dual_stop_near_marked_object",
    "dual_pass_by_marked_object",
    "ordinal_focus_action",
    "single_described_action",
    "first_actor_described_action",
    "second_actor_runs",
    "same_type_marker_resolution",
    "open_object",
    "pickup_object",
    "putdown_object",
    "give_object",
    "third_actor_described_action",
]


@dataclass(frozen=True)
class PatternSpec:
    pattern_name: str
    pattern_family: str
    difficulty_bucket: DifficultyBucket
    default_share: int
    default_complexity_class: ComplexityClass
    allowed_source_variant_keys: tuple[SourceVariantKey, ...]
    required_actor_count: int
    required_object_mode: ObjectMode
    beat_blueprint: tuple[RegistryPhase, ...]
    required_semantics: tuple[str, ...]
    forbidden_collapses: tuple[str, ...]
    semantic_tags: tuple[str, ...]
    canonical_source_template: str
    builder: Callable[[int, SourceVariantKey], CIRRecord]

    def build(self, graph_seed: int, source_variant_key: SourceVariantKey | None = None) -> CIRRecord:
        variant = source_variant_key or self.allowed_source_variant_keys[0]
        if variant not in self.allowed_source_variant_keys:
            raise ValueError(
                f"{self.pattern_name} does not allow source_variant_key={variant!r}; "
                f"allowed={self.allowed_source_variant_keys}"
            )
        return self.builder(graph_seed, variant)


def _marker_short_id(pattern_name: str, graph_seed: int, slot: int) -> str:
    payload = f"{pattern_name}:{graph_seed}:{slot}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:8]


def _actor(actor_id: str, *, ordinal: str, name: str | None = None) -> dict:
    actor = {
        "id": actor_id,
        "type": "human",
        "labels": {
            "ordinal": ordinal,
        },
    }
    if name is not None:
        actor["name"] = name
    return actor


def _marked_object(
    *,
    pattern_name: str,
    graph_seed: int,
    slot: int,
    object_type: str,
    name: str,
    aliases: list[str],
    source_name: str | None = None,
    relative_position: str = "unknown",
) -> dict:
    short_id = _marker_short_id(pattern_name, graph_seed, slot)
    return {
        "id": f"object_marked_{short_id}",
        "type": object_type,
        "name": name,
        "relative_position": relative_position,
        "marker_binding": {
            "kind": "marked",
            "marker_short_id": short_id,
            "source_name": source_name or name,
            "mentioned_aliases": aliases,
        },
    }


def _unmarked_object(
    *,
    object_id: str,
    object_type: str,
    name: str,
    relative_position: str = "unknown",
) -> dict:
    return {
        "id": object_id,
        "type": object_type,
        "name": name,
        "relative_position": relative_position,
        "marker_binding": {
            "kind": "unmarked",
        },
    }


def _action(
    action_id: str,
    *,
    actor_id: str,
    action_type: str,
    resulting_pose: str,
    chronology_rank: int,
    target_id: str | None = None,
    direction: str | None = None,
    modifier: str | None = None,
    dialogue: str | None = None,
    described_action: dict | None = None,
    holding_object: str | None = None,
    is_unsupported_runtime_action: bool | None = None,
    must_preserve_in_source: bool | None = None,
) -> dict:
    semantics = {"chronology_rank": chronology_rank}
    if is_unsupported_runtime_action is not None:
        semantics["is_unsupported_runtime_action"] = is_unsupported_runtime_action
    if must_preserve_in_source is not None:
        semantics["must_preserve_in_source"] = must_preserve_in_source

    action = {
        "id": action_id,
        "actor_id": actor_id,
        "type": action_type,
        "resulting_pose": resulting_pose,
        "semantics": semantics,
    }
    if target_id is not None:
        action["target_id"] = target_id
    if direction is not None:
        action["direction"] = direction
    if modifier is not None:
        action["modifier"] = modifier
    if dialogue is not None:
        action["dialogue"] = dialogue
    if described_action is not None:
        action["described_action"] = described_action
    if holding_object is not None:
        action["holding_object"] = holding_object
    return action


def _beat(beat_id: str, *, phase: str, actions: list[dict]) -> dict:
    return {
        "id": beat_id,
        "phase": phase,
        "actions": actions,
    }


def _relation(relation_id: str, *, subject: str, relation: str, object_id: str) -> dict:
    return {
        "id": relation_id,
        "subject": subject,
        "relation": relation,
        "object": object_id,
    }


def _ordinal_map(actor_count: int) -> dict[str, str]:
    mapping = {"first": "actor_1"}
    if actor_count >= 2:
        mapping["second"] = "actor_2"
    if actor_count >= 3:
        mapping["third"] = "actor_3"
    return mapping


def _pattern_rng(pattern_name: str, graph_seed: int, variant: SourceVariantKey) -> random.Random:
    payload = f"{pattern_name}:{graph_seed}:{variant}".encode("utf-8")
    seed = int(hashlib.sha256(payload).hexdigest()[:16], 16)
    return random.Random(seed)


def _pick(rng: random.Random, options: list):
    return options[rng.randrange(len(options))]


def _handoff_pronoun(item_name_en: str) -> str:
    return {
        "folder": "её",
        "letter": "его",
        "key": "его",
        "tablet": "его",
        "badge": "его",
        "flash_drive": "её",
        "phone": "его",
        "envelope": "его",
        "notebook_item": "его",
        "box": "её",
        "package": "его",
        "bag": "его",
        "cup": "её",
        "paper": "его",
    }.get(item_name_en, "его")


_RUSSIAN_ACTOR_NAMES = RUSSIAN_ACTOR_NAMES
_FEMALE_RUSSIAN_ACTOR_NAMES = FEMALE_RUSSIAN_ACTOR_NAMES


def _sample_actor_names(rng: random.Random, count: int) -> tuple[str, ...]:
    if count <= 0:
        return tuple()
    if count <= len(_RUSSIAN_ACTOR_NAMES):
        return tuple(rng.sample(list(_RUSSIAN_ACTOR_NAMES), count))
    names = list(_RUSSIAN_ACTOR_NAMES)
    while len(names) < count:
        names.extend(_RUSSIAN_ACTOR_NAMES)
    rng.shuffle(names)
    return tuple(names[:count])


_DIALOGUE_OBJECTS = DIALOGUE_OBJECTS


def _sample_dialogue_lines(rng: random.Random, *, speaker_name: str, colloquial: bool) -> tuple[str, str]:
    obj = _pick(rng, list(_DIALOGUE_OBJECTS))
    feminine = speaker_name in _FEMALE_RUSSIAN_ACTOR_NAMES
    if colloquial:
        first_templates = (
            DIALOGUE_FIRST_TEMPLATES_COLLOQUIAL_FEMALE
            if feminine
            else DIALOGUE_FIRST_TEMPLATES_COLLOQUIAL_MALE
        )
        second_templates = DIALOGUE_SECOND_TEMPLATES_COLLOQUIAL
    else:
        first_templates = (
            DIALOGUE_FIRST_TEMPLATES_BASE_FEMALE
            if feminine
            else DIALOGUE_FIRST_TEMPLATES_BASE_MALE
        )
        second_templates = DIALOGUE_SECOND_TEMPLATES_BASE
    return _pick(rng, first_templates).format(obj=obj), _pick(rng, second_templates).format(obj=obj)


def _choose_walk_modifier(rng: random.Random) -> str | None:
    return _pick(rng, [None, "slowly", "quickly", "carefully"])


def _apply_modifier_if_any(actions: list[dict], modifier: str | None) -> None:
    if modifier is None:
        return
    for action in actions:
        action["modifier"] = modifier


def _lower_sentence_start(text: str) -> str:
    if not text:
        return text
    return text[:1].lower() + text[1:]


def _motion_intro_text(rng: random.Random, *, modifier_surface: str | None = None) -> str:
    if modifier_surface is None:
        return _pick(
            rng,
            [
                "2 актёра идут навстречу друг другу",
                "Два актёра идут навстречу друг другу",
                "Оба актёра идут навстречу друг другу",
            ],
        )
    return _pick(
        rng,
        [
            f"2 актёра {modifier_surface} идут навстречу друг другу",
            f"Два актёра {modifier_surface} идут навстречу друг другу",
            f"Оба актёра {modifier_surface} идут навстречу друг другу",
        ],
    )


def _single_phase_template(rng: random.Random, *, intro: str) -> str:
    return _pick(
        rng,
        [
            f"{intro}.",
            f"Сначала {_lower_sentence_start(intro)}.",
        ],
    )


def _two_phase_template(rng: random.Random, *, intro: str, continuation: str) -> str:
    return _pick(
        rng,
        [
            f"{intro} и {continuation}.",
            f"Сначала {_lower_sentence_start(intro)}, потом {continuation}.",
            f"{intro}, а потом {continuation}.",
        ],
    )


def _three_phase_template(rng: random.Random, *, intro: str, middle: str, ending: str) -> str:
    return _pick(
        rng,
        [
            f"Сначала {_lower_sentence_start(intro)}, затем {middle}, после этого {ending}.",
            f"{intro}, затем {middle}, а потом {ending}.",
            f"{intro}, после этого {middle}, и в конце {ending}.",
        ],
    )


def _ordinal_label_ru(actor_id: str, *, capitalized: bool = False) -> str:
    token = {
        "actor_1": "первый",
        "actor_2": "второй",
        "actor_3": "третий",
    }.get(actor_id, actor_id)
    return token.capitalize() if capitalized else token


def _inflect_person_name(name: str, case: str) -> str:
    if case not in {"accusative", "dative"}:
        return name
    lowered = name.lower()
    irregular = {
        "павел": {
            "accusative": "Павла",
            "dative": "Павлу",
        }
    }
    if lowered in irregular:
        return irregular[lowered][case]
    if lowered.endswith("ья"):
        stem = name[:-2]
        return stem + ("ью" if case == "accusative" else "ье")
    if lowered.endswith("а"):
        return name[:-1] + ("у" if case == "accusative" else "е")
    if lowered.endswith("я"):
        return name[:-1] + ("ю" if case == "accusative" else "е")
    if lowered.endswith("й"):
        return name[:-1] + ("я" if case == "accusative" else "ю")
    return name + ("а" if case == "accusative" else "у")


def _apply_ordinal_stress(actors: list[dict], must_preserve: list[str]) -> None:
    role_map = {"actor_1": "first_actor", "actor_2": "second_actor", "actor_3": "third_actor"}
    for actor in actors:
        actor["labels"]["surface_role"] = role_map[actor["id"]]
    must_preserve.append("ordinal_surface_stress")


def _morphology_profile(rng: random.Random, *, base_name: str, oblique_forms: list[str]) -> tuple[str, list[str], str]:
    chosen = _pick(rng, oblique_forms)
    aliases = [chosen, base_name]
    return chosen, aliases, chosen


def _computer_marker_profiles() -> list[tuple[str, list[str]]]:
    return [(name, list(aliases)) for name, aliases in COMPUTER_MARKER_PROFILES]


def _computer_oblique_forms(base_name: str, *, relation: str) -> list[str]:
    relation_key = "near" if relation == "near" else "pass_by"
    forms_by_name = COMPUTER_OBLIQUE_FORMS[relation_key]
    fallback = forms_by_name["pc"]
    return list(forms_by_name.get(base_name, fallback))


def _relation_surface_hint(rng: random.Random, *, base_name: str, relation: str) -> str:
    forms = _computer_oblique_forms(base_name, relation=relation)
    return _pick(rng, forms) if forms else base_name


def _preferred_surface_hint(aliases: list[str]) -> str:
    for alias in reversed(aliases):
        if any("а" <= ch.lower() <= "я" or ch.lower() == "ё" for ch in alias):
            return alias
    return aliases[-1] if aliases else ""


def _join_surface_phrase(prefix: str, surface_hint: str) -> str:
    lowered = surface_hint.strip().lower()
    if lowered.startswith(("у ", "около ", "рядом с ", "рядом со ", "мимо ", "возле ")):
        return surface_hint
    return f"{prefix} {surface_hint}".strip()


def _localize_walk_modifier(modifier: str | None) -> str | None:
    if modifier is None:
        return None
    return {
        "slowly": "не спеша",
        "quickly": "быстро",
        "carefully": "осторожно",
    }.get(modifier, modifier)


def _allocate_counts(specs: list[PatternSpec], total_records: int) -> dict[str, int]:
    total_weight = sum(spec.default_share for spec in specs)
    if total_weight <= 0:
        raise ValueError("total_weight must be positive")
    raw = []
    assigned = 0
    for spec in specs:
        ideal = total_records * spec.default_share / total_weight
        floor = int(ideal)
        assigned += floor
        raw.append((spec.pattern_name, floor, ideal - floor))

    remaining = total_records - assigned
    raw.sort(key=lambda item: (-item[2], item[0]))
    counts = {name: floor for name, floor, _ in raw}
    for name, _, _ in raw[:remaining]:
        counts[name] += 1
    return counts


def _top_level_record(
    *,
    pattern_name: str,
    pattern_family: str,
    difficulty_bucket: DifficultyBucket,
    graph_seed: int,
    source_variant_key: SourceVariantKey,
    scene_graph: dict,
    semantic_tags: tuple[str, ...],
    required_semantics: tuple[str, ...],
    forbidden_collapses: tuple[str, ...],
    beat_blueprint: tuple[RegistryPhase, ...],
    canonical_source_template: str,
) -> CIRRecord:
    budgets = {
        "actor_count": len(scene_graph["actors"]),
        "object_count": len(scene_graph["objects"]),
        "beat_count": len(scene_graph["beats"]),
        "action_count": sum(len(beat["actions"]) for beat in scene_graph["beats"]),
        "relation_count": len(scene_graph["spatial_relations"]),
    }
    if budgets["actor_count"] <= 2 and budgets["object_count"] <= 1 and budgets["beat_count"] <= 2 and budgets["action_count"] <= 3:
        complexity_class = "S"
    elif budgets["actor_count"] <= 2 and budgets["object_count"] <= 2 and budgets["beat_count"] <= 3 and budgets["action_count"] <= 5:
        complexity_class = "M"
    else:
        complexity_class = "L"

    record: CIRRecord = {
        "cir_version": "sg_v7_cir_v1",
        "contract_version": "sg_v7_contract_v1",
        "sample_id": "pending",
        "source_variant_key": source_variant_key,
        "pattern_name": pattern_name,
        "difficulty_bucket": difficulty_bucket,
        "complexity_class": complexity_class,
        "graph_seed": graph_seed,
        "scene_graph": scene_graph,
        "semantic_tags": list(semantic_tags),
        "determinism": {
            "id_policy": "canonical_v1",
            "ordering_policy": "stable_v1",
            "serializer": "deterministic_scene_script_v1",
            "phase_policy": "phase_enum_v1",
            "described_action_policy": "described_action_v1",
        },
        "budgets": budgets,
        "runtime_projection": {
            "target_schema": "SceneScript",
            "field_casing": "camelCase",
            "drop_internal_fields": True,
            "fill_original_description_from_source_variant": True,
            "described_action_source_text_policy": "canonical_text_to_sourceText",
            "top_level_optional_policy": "omit_all",
            "beat_optional_policy": "preserve_if_present_else_omit",
        },
        "internal_metadata": {
            "generator_name": PATTERN_REGISTRY_VERSION,
            "generator_version": PATTERN_REGISTRY_VERSION,
            "pattern_family": pattern_family,
            "registry_beat_blueprint": list(beat_blueprint),
            "canonical_source_template": canonical_source_template,
            "required_semantics": list(required_semantics),
            "forbidden_collapses": list(forbidden_collapses),
        },
    }
    record["sample_id"] = expected_sample_id(record)
    return record


def _dialogue_only(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("dialogue_only", graph_seed, variant)
    name_1, name_2 = _sample_actor_names(rng, 2)
    line_1, line_2 = _sample_dialogue_lines(rng, speaker_name=name_1, colloquial=(variant == "dialogue_mix"))
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
        ],
        "objects": [],
        "beats": [
            _beat(
                "beat_1",
                phase="dialogue_exchange",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="talk",
                        target_id="actor_2",
                        resulting_pose="standing",
                        chronology_rank=1,
                        dialogue=line_1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="talk",
                        target_id="actor_1",
                        resulting_pose="standing",
                        chronology_rank=2,
                        dialogue=line_2,
                    ),
                ],
            )
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "dialogue_text_exactness",
            "beat_count=1",
        ],
    }
    return _top_level_record(
        pattern_name="dialogue_only",
        pattern_family="dialogue",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("dialogue", "two_actor", "baseline"),
        required_semantics=("talk_only", "no_invented_objects"),
        forbidden_collapses=("invent_object", "split_single_dialogue_beat"),
        beat_blueprint=("dialogue_exchange",),
        canonical_source_template=f"{name_1.upper()}: {line_1} {name_2.upper()}: {line_2}",
    )


def _dialogue_then_small_action(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("dialogue_then_small_action", graph_seed, variant)
    name_1, name_2 = _sample_actor_names(rng, 2)
    line_1, line_2 = _sample_dialogue_lines(rng, speaker_name=name_1, colloquial=(variant == "dialogue_mix"))
    followup_options = [
        ("actor_1", "turn", "actor_2"),
        ("actor_2", "turn", "actor_1"),
        ("actor_1", "look_at", "actor_2"),
        ("actor_2", "look_at", "actor_1"),
    ]
    followup_actor, followup_type, followup_target = _pick(rng, followup_options)
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
        ],
        "objects": [],
        "beats": [
            _beat(
                "beat_1",
                phase="dialogue_exchange",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="talk",
                        target_id="actor_2",
                        resulting_pose="standing",
                        chronology_rank=1,
                        dialogue=line_1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="talk",
                        target_id="actor_1",
                        resulting_pose="standing",
                        chronology_rank=2,
                        dialogue=line_2,
                    ),
                ],
            ),
            _beat(
                "beat_2",
                phase="small_followup_action",
                actions=[
                    _action(
                        "action_3",
                        actor_id=followup_actor,
                        action_type=followup_type,
                        target_id=followup_target,
                        resulting_pose="standing",
                        chronology_rank=3,
                    )
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "beat_count=2",
            "dialogue_then_small_action",
        ],
    }
    return _top_level_record(
        pattern_name="dialogue_then_small_action",
        pattern_family="dialogue_followup",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("dialogue", "small_action", "chronology"),
        required_semantics=("two_beat_ordering", "small_followup_action"),
        forbidden_collapses=("single_talk_only_beat",),
        beat_blueprint=("dialogue_exchange", "single_small_followup_action"),
        canonical_source_template=(
            f"{name_1.upper()}: {line_1} {name_2.upper()}: {line_2} "
            f"{name_1 if followup_actor == 'actor_1' else name_2} "
            f"{'поворачивается к' if followup_type == 'turn' else 'смотрит на'} "
            f"{_inflect_person_name(name_2 if followup_target == 'actor_2' else name_1, 'dative' if followup_type == 'turn' else 'accusative')}."
        ),
    )


def _dialogue_then_put_down_object(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("dialogue_then_put_down_object", graph_seed, variant)
    dialogue_pairs = list(DIALOGUE_THEN_PUT_DOWN_BASE_PAIRS)
    dialogue_mix_pairs = list(DIALOGUE_THEN_PUT_DOWN_MIX_PAIRS)
    surface_profiles = list(DIALOGUE_THEN_PUT_DOWN_SURFACES)
    name_1, name_2 = _sample_actor_names(rng, 2)
    line, (item_name_en, item_name_ru_obj) = _pick(
        rng, dialogue_mix_pairs if variant == "dialogue_mix" else dialogue_pairs
    )
    surface_type, surface_name = _pick(rng, surface_profiles)
    speaker_actor = _pick(rng, ["actor_1", "actor_2"])
    putdown_actor = "actor_2" if speaker_actor == "actor_1" else "actor_1"
    item = _unmarked_object(object_id="object_1", object_type="generic", name=item_name_en, relative_position="center")
    surface = _unmarked_object(object_id="object_2", object_type=surface_type, name=surface_name, relative_position=_pick(rng, ["left", "center", "right"]))
    actors = [
        _actor("actor_1", ordinal="first", name=name_1),
        _actor("actor_2", ordinal="second", name=name_2),
    ]
    scene_graph = {
        "actors": actors,
        "objects": [item, surface],
        "beats": [
            _beat(
                "beat_1",
                phase="dialogue_exchange",
                actions=[
                    _action(
                        "action_1",
                        actor_id=speaker_actor,
                        action_type="talk",
                        target_id=putdown_actor,
                        resulting_pose="standing",
                        chronology_rank=1,
                        dialogue=line,
                    ),
                ],
            ),
            _beat(
                "beat_2",
                phase="putdown_object",
                actions=[
                    _action(
                        "action_2",
                        actor_id=putdown_actor,
                        action_type="put_down",
                        target_id=surface["id"],
                        resulting_pose="standing",
                        chronology_rank=2,
                        holding_object=item["id"],
                    ),
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject=item["id"], relation="near", object_id=surface["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "dialogue_then_put_down",
            f"put_down_target:{surface['id']}",
        ],
    }
    return _top_level_record(
        pattern_name="dialogue_then_put_down_object",
        pattern_family="dialogue_object_followup",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("dialogue", "object_placement", "two_actor"),
        required_semantics=("dialogue_precedes_put_down", "holding_object_preserved"),
        forbidden_collapses=("drop_put_down_followup", "talk_only_rewrite"),
        beat_blueprint=("dialogue_exchange", "putdown_object"),
        canonical_source_template=f"{name_1.upper() if speaker_actor == 'actor_1' else name_2.upper()}: {line} "
        f"{name_2 if putdown_actor == 'actor_2' else name_1} кладёт {item_name_ru_obj} на {surface_name}.",
    )


def _enter_then_put_down_object(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("enter_then_put_down_object", graph_seed, variant)
    carried_profiles = list(ENTER_THEN_PUT_DOWN_CARRIED)
    surface_profiles = list(ENTER_THEN_PUT_DOWN_SURFACES)
    actor_name = _sample_actor_names(rng, 1)[0]
    carried_name_en, carried_name_ru = _pick(rng, carried_profiles)
    surface_type, surface_name = _pick(rng, surface_profiles)
    carried = _unmarked_object(object_id="object_1", object_type="generic", name=carried_name_en, relative_position="center")
    surface = _unmarked_object(object_id="object_2", object_type=surface_type, name=surface_name, relative_position=_pick(rng, ["left", "center", "right"]))
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=actor_name),
        ],
        "objects": [carried, surface],
        "beats": [
            _beat(
                "beat_1",
                phase="single_action",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="enter",
                        resulting_pose="walking",
                        chronology_rank=1,
                    ),
                ],
            ),
            _beat(
                "beat_2",
                phase="putdown_object",
                actions=[
                    _action(
                        "action_2",
                        actor_id="actor_1",
                        action_type="put_down",
                        target_id=surface["id"],
                        resulting_pose="standing",
                        chronology_rank=2,
                        holding_object=carried["id"],
                    ),
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject=carried["id"], relation="near", object_id=surface["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(1),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "enter_before_put_down",
            f"put_down_target:{surface['id']}",
        ],
    }
    return _top_level_record(
        pattern_name="enter_then_put_down_object",
        pattern_family="object_placement",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("enter", "object_placement", "single_actor"),
        required_semantics=("enter_then_put_down", "holding_object_preserved"),
        forbidden_collapses=("drop_enter_phase",),
        beat_blueprint=("single_action", "putdown_object"),
        canonical_source_template=f"Актёр входит и ставит {carried_name_ru} на {surface_name}.",
    )


def _open_then_pick_up_object(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("open_then_pick_up_object", graph_seed, variant)
    container_profiles = list(OPEN_THEN_PICK_UP_CONTAINERS)
    item_profiles = list(OPEN_THEN_PICK_UP_ITEMS)
    actor_name = _sample_actor_names(rng, 1)[0]
    container_type, container_name = _pick(rng, container_profiles)
    item_name_en, item_name_ru = _pick(rng, item_profiles)
    container = _unmarked_object(object_id="object_1", object_type=container_type, name=container_name, relative_position=_pick(rng, ["left", "center", "right"]))
    item = _unmarked_object(object_id="object_2", object_type="generic", name=item_name_en, relative_position="unknown")
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=actor_name),
        ],
        "objects": [container, item],
        "beats": [
            _beat(
                "beat_1",
                phase="open_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="open",
                        target_id=container["id"],
                        resulting_pose="standing",
                        chronology_rank=1,
                    ),
                ],
            ),
            _beat(
                "beat_2",
                phase="pickup_object",
                actions=[
                    _action(
                        "action_2",
                        actor_id="actor_1",
                        action_type="pick_up",
                        target_id=item["id"],
                        resulting_pose="standing",
                        chronology_rank=2,
                        holding_object=item["id"],
                    ),
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject=item["id"], relation="inside", object_id=container["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(1),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "open_before_pick_up",
            f"pickup_target:{item['id']}",
        ],
    }
    return _top_level_record(
        pattern_name="open_then_pick_up_object",
        pattern_family="container_interaction",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("open", "pick_up", "single_actor", "container"),
        required_semantics=("open_precedes_pick_up", "inside_relation"),
        forbidden_collapses=("skip_open",),
        beat_blueprint=("open_object", "pickup_object"),
        canonical_source_template=f"Актёр открывает {container_name} и берёт {item_name_ru}.",
    )


def _pick_up_then_put_down_object(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("pick_up_then_put_down_object", graph_seed, variant)
    item_profiles = list(PICK_UP_THEN_PUT_DOWN_ITEMS)
    surface_profiles = list(PICK_UP_THEN_PUT_DOWN_SURFACES)
    actor_name = _sample_actor_names(rng, 1)[0]
    item_name_en, item_name_ru = _pick(rng, item_profiles)
    surface_type, surface_name = _pick(rng, surface_profiles)
    item = _unmarked_object(object_id="object_1", object_type="generic", name=item_name_en, relative_position="center")
    surface = _unmarked_object(object_id="object_2", object_type=surface_type, name=surface_name, relative_position=_pick(rng, ["left", "center", "right"]))
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=actor_name),
        ],
        "objects": [item, surface],
        "beats": [
            _beat(
                "beat_1",
                phase="pickup_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="pick_up",
                        target_id=item["id"],
                        resulting_pose="standing",
                        chronology_rank=1,
                        holding_object=item["id"],
                    ),
                ],
            ),
            _beat(
                "beat_2",
                phase="putdown_object",
                actions=[
                    _action(
                        "action_2",
                        actor_id="actor_1",
                        action_type="put_down",
                        target_id=surface["id"],
                        resulting_pose="standing",
                        chronology_rank=2,
                        holding_object=item["id"],
                    ),
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject=item["id"], relation="near", object_id=surface["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(1),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "pick_up_before_put_down",
            f"put_down_target:{surface['id']}",
        ],
    }
    return _top_level_record(
        pattern_name="pick_up_then_put_down_object",
        pattern_family="object_placement",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("pick_up", "put_down", "single_actor", "object_placement"),
        required_semantics=("pick_up_precedes_put_down", "holding_object_preserved"),
        forbidden_collapses=("drop_pick_up",),
        beat_blueprint=("pickup_object", "putdown_object"),
        canonical_source_template=f"Актёр берёт {item_name_ru} и кладёт на {surface_name}.",
    )


def _toward_each_other(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("toward_each_other", graph_seed, variant)
    modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(modifier)
    name_1, name_2 = _sample_actor_names(rng, 2)
    actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(actions, modifier)
    actors = [
        _actor("actor_1", ordinal="first", name=name_1),
        _actor("actor_2", ordinal="second", name=name_2),
    ]
    must_preserve = [
        "symmetric_toward_each_other",
    ]
    if variant == "ordinal_stress":
        _apply_ordinal_stress(actors, must_preserve)
    scene_graph = {
        "actors": actors,
        "objects": [],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=actions,
            )
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": must_preserve,
    }
    return _top_level_record(
        pattern_name="toward_each_other",
        pattern_family="motion_symmetry",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "symmetry", "two_actor"),
        required_semantics=("direction_toward_each_other", "dual_motion"),
        forbidden_collapses=("single_actor_walk", "direction_drop"),
        beat_blueprint=("mutual_walk_toward_each_other",),
        canonical_source_template=_single_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
        ),
    )


def _toward_each_other_then_stop_near_marked_object(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("toward_each_other_then_stop_near_marked_object", graph_seed, variant)
    base_object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, base_object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="near"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="near")
    laptop = _marked_object(
        pattern_name="toward_each_other_then_stop_near_marked_object",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    actors = [
        _actor("actor_1", ordinal="first"),
        _actor("actor_2", ordinal="second"),
    ]
    must_preserve = [
        "beat_count=2",
        f"must_ground_object:{laptop['id']}",
    ]
    if variant == "ordinal_stress":
        _apply_ordinal_stress(actors, must_preserve)
    if variant == "morphology_stress":
        must_preserve.append(f"morphology_surface:{surface_hint}")
    scene_graph = {
        "actors": actors,
        "objects": [laptop],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=walk_actions,
            ),
            _beat(
                "beat_2",
                phase="stop_near_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="stop",
                        target_id=laptop["id"],
                        resulting_pose="standing",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="stop",
                        target_id=laptop["id"],
                        resulting_pose="standing",
                        chronology_rank=4,
                    ),
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=laptop["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=laptop["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [laptop["id"]],
            "alias_to_object_id": {
                alias: laptop["id"] for alias in laptop["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": must_preserve,
    }
    return _top_level_record(
        pattern_name="toward_each_other_then_stop_near_marked_object",
        pattern_family="motion_object_grounding",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "stop_near_object"),
        required_semantics=("marked_object_grounding", "dual_stop_near_object"),
        forbidden_collapses=("one_beat_merge", "approach_instead_of_stop"),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object"),
        canonical_source_template=_two_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            continuation=f"останавливаются {_join_surface_phrase('около', surface_hint)}",
        ),
    )


def _toward_each_other_then_pass_by_marked_object(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("toward_each_other_then_pass_by_marked_object", graph_seed, variant)
    base_object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, base_object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="pass_by"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="pass_by")
    laptop = _marked_object(
        pattern_name="toward_each_other_then_pass_by_marked_object",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    actors = [
        _actor("actor_1", ordinal="first"),
        _actor("actor_2", ordinal="second"),
    ]
    must_preserve = [
        "beat_count=2",
        f"must_ground_object:{laptop['id']}",
        "pass_by_semantics",
    ]
    if variant == "ordinal_stress":
        _apply_ordinal_stress(actors, must_preserve)
    if variant == "morphology_stress":
        must_preserve.append(f"morphology_surface:{surface_hint}")
    scene_graph = {
        "actors": actors,
        "objects": [laptop],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=walk_actions,
            ),
            _beat(
                "beat_2",
                phase="pass_by_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="pass_by",
                        target_id=laptop["id"],
                        resulting_pose="walking",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="pass_by",
                        target_id=laptop["id"],
                        resulting_pose="walking",
                        chronology_rank=4,
                    ),
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [laptop["id"]],
            "alias_to_object_id": {
                alias: laptop["id"] for alias in laptop["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": must_preserve,
    }
    return _top_level_record(
        pattern_name="toward_each_other_then_pass_by_marked_object",
        pattern_family="motion_object_grounding",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "pass_by_object"),
        required_semantics=("marked_object_grounding", "dual_pass_by_object"),
        forbidden_collapses=("rewrite_pass_by_as_walk",),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_pass_by_marked_object"),
        canonical_source_template=_two_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            continuation=f"проходят {_join_surface_phrase('мимо', surface_hint)}",
        ),
    )


def _ordinal_first_second(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("ordinal_first_second", graph_seed, variant)
    object_options = [
        ("table", "стол", "столу"),
        ("chair", "стул", "стулу"),
        ("door", "дверь", "двери"),
        ("cabinet", "шкаф", "шкафу"),
        ("window", "окно", "окну"),
        ("generic", "монитор", "монитору"),
        ("generic", "терминал", "терминалу"),
        ("generic", "стойка", "стойке"),
        ("chair", "лавка", "лавке"),
        ("generic", "киоск", "киоску"),
        ("generic", "экран", "экрану"),
        ("generic", "панель", "панели"),
    ]
    name_1, name_2 = _sample_actor_names(rng, 2)
    object_type, object_name, object_dative = _pick(rng, object_options)
    table = _unmarked_object(object_id="object_1", object_type=object_type, name=object_name, relative_position=_pick(rng, ["left", "center", "right"]))
    action_1_type = "approach"
    action_2_type = "look_at"
    target_id = table["id"]
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
        ],
        "objects": [table],
        "beats": [
            _beat(
                "beat_1",
                phase="approach_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type=action_1_type,
                        target_id=target_id,
                        direction="to_target" if action_1_type == "approach" else None,
                        resulting_pose="walking" if action_1_type == "approach" else "standing",
                        chronology_rank=1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type=action_2_type,
                        target_id=target_id if action_2_type in {"look_at"} else ("actor_1" if action_2_type == "turn" else None),
                        resulting_pose="standing",
                        chronology_rank=2,
                    ),
                ],
            )
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "ordinal:first->actor_1",
            "ordinal:second->actor_2",
        ],
    }
    return _top_level_record(
        pattern_name="ordinal_first_second",
        pattern_family="ordinal_binding",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("ordinal_reference", "two_actor", "object_target"),
        required_semantics=("ordinal_map", "actor_role_stability"),
        forbidden_collapses=("actor_swap", "ordinal_drop"),
        beat_blueprint=("ordinal_focus_action",),
        canonical_source_template=_pick(
            rng,
            [
                f"Первый подходит к {object_dative}, второй смотрит на него.",
                f"Первый идёт к {object_dative}, а второй наблюдает за ним.",
                f"Сначала первый направляется к {object_dative}, а второй не сводит с него взгляда.",
            ],
        ),
    )


def _unsupported_action_described_action(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("unsupported_action_described_action", graph_seed, variant)
    described_profiles = list(UNSUPPORTED_ACTION_DESCRIBED_PROFILES)
    actor_name = _sample_actor_names(rng, 1)[0]
    object_type, object_name, canonical_text, fallback_text, lemma = _pick(rng, described_profiles)
    door = _unmarked_object(object_id="object_1", object_type=object_type, name=object_name, relative_position=_pick(rng, ["left", "center", "right"]))
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=actor_name),
        ],
        "objects": [door],
        "beats": [
            _beat(
                "beat_1",
                phase="single_action",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="described_action",
                        target_id=door["id"],
                        resulting_pose="standing",
                        chronology_rank=1,
                        described_action={
                            "canonical_text": canonical_text,
                            "fallback_text": fallback_text,
                            "source_lemma_hint": lemma,
                        },
                        is_unsupported_runtime_action=True,
                        must_preserve_in_source=True,
                    )
                ],
            )
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=door["id"])
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(1),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "described_action_required",
            "single_actor",
        ],
    }
    return _top_level_record(
        pattern_name="unsupported_action_described_action",
        pattern_family="unsupported_action",
        difficulty_bucket="core",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("described_action", "single_actor", "unsupported_action"),
        required_semantics=("unsupported_to_described_action", "must_preserve_source"),
        forbidden_collapses=("rewrite_to_talk", "rewrite_to_stand"),
        beat_blueprint=("single_described_action",),
        canonical_source_template=f"Актёр {canonical_text}.",
    )


def _stop_near_marked_object_then_first_described_action(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("stop_near_marked_object_then_first_described_action", graph_seed, variant)
    object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="near"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="near")
    described_profiles = list(STOP_NEAR_FIRST_DESCRIBED_PROFILES)
    canonical_text, fallback_text, lemma = _pick(rng, described_profiles)
    laptop = _marked_object(
        pattern_name="stop_near_marked_object_then_first_described_action",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first"),
            _actor("actor_2", ordinal="second"),
        ],
        "objects": [laptop],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=walk_actions,
            ),
            _beat(
                "beat_2",
                phase="stop_near_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="stop",
                        target_id=laptop["id"],
                        resulting_pose="standing",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="stop",
                        target_id=laptop["id"],
                        resulting_pose="standing",
                        chronology_rank=4,
                    ),
                ],
            ),
            _beat(
                "beat_3",
                phase="first_described_action",
                actions=[
                    _action(
                        "action_5",
                        actor_id="actor_1",
                        action_type="described_action",
                        resulting_pose="standing",
                        chronology_rank=5,
                        described_action={
                            "canonical_text": canonical_text,
                            "fallback_text": fallback_text,
                            "source_lemma_hint": lemma,
                        },
                        is_unsupported_runtime_action=True,
                        must_preserve_in_source=True,
                    )
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=laptop["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=laptop["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [laptop["id"]],
            "alias_to_object_id": {
                alias: laptop["id"] for alias in laptop["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": [
            "beat_count=3",
            f"must_ground_object:{laptop['id']}",
            "ordinal:first->actor_1",
            "action:action_5=described_action",
            *( [f"morphology_surface:{surface_hint}"] if variant == "morphology_stress" else [] ),
        ],
    }
    return _top_level_record(
        pattern_name="stop_near_marked_object_then_first_described_action",
        pattern_family="composed_marked_action",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "ordinal_reference", "described_action", "multi_beat"),
        required_semantics=("three_beat_chronology", "first_actor_described_action"),
        forbidden_collapses=("drop_stop_phase", "rewrite_described_action_to_talk"),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object", "first_actor_described_action"),
        canonical_source_template=_three_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            middle=f"оба останавливаются {_join_surface_phrase('у', surface_hint)}",
            ending=f"первый {canonical_text}",
        ),
    )


def _toward_each_other_then_pass_by_object_then_second_runs(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("toward_each_other_then_pass_by_object_then_second_runs", graph_seed, variant)
    object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="pass_by"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="pass_by")
    laptop = _marked_object(
        pattern_name="toward_each_other_then_pass_by_object_then_second_runs",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first"),
            _actor("actor_2", ordinal="second"),
        ],
        "objects": [laptop],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=walk_actions,
            ),
            _beat(
                "beat_2",
                phase="pass_by_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="pass_by",
                        target_id=laptop["id"],
                        resulting_pose="walking",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="pass_by",
                        target_id=laptop["id"],
                        resulting_pose="walking",
                        chronology_rank=4,
                    ),
                ],
            ),
            _beat(
                "beat_3",
                phase="single_action",
                actions=[
                    _action(
                        "action_5",
                        actor_id="actor_2",
                        action_type="run",
                        resulting_pose="running",
                        chronology_rank=5,
                        modifier=_pick(rng, [None, "quickly"]),
                    )
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [laptop["id"]],
            "alias_to_object_id": {
                alias: laptop["id"] for alias in laptop["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": [
            "beat_count=3",
            f"must_ground_object:{laptop['id']}",
            "actor_2_runs_in_final_beat",
            *( [f"morphology_surface:{surface_hint}"] if variant == "morphology_stress" else [] ),
        ],
    }
    return _top_level_record(
        pattern_name="toward_each_other_then_pass_by_object_then_second_runs",
        pattern_family="role_shift_motion",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"),
        required_semantics=("second_actor_runs", "pass_by_then_role_shift"),
        forbidden_collapses=("keep_both_walkers", "drop_final_run"),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_pass_by_marked_object", "second_actor_runs"),
        canonical_source_template=_three_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            middle=f"оба проходят {_join_surface_phrase('мимо', surface_hint)}",
            ending="второй начинает бежать",
        ),
    )


def _toward_each_other_then_stop_near_marked_object_then_second_runs(
    graph_seed: int, variant: SourceVariantKey
) -> CIRRecord:
    rng = _pattern_rng("toward_each_other_then_stop_near_marked_object_then_second_runs", graph_seed, variant)
    base_object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, base_object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="near"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="near")
    marker = _marked_object(
        pattern_name="toward_each_other_then_stop_near_marked_object_then_second_runs",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first"),
            _actor("actor_2", ordinal="second"),
        ],
        "objects": [marker],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=walk_actions,
            ),
            _beat(
                "beat_2",
                phase="stop_near_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="stop",
                        target_id=marker["id"],
                        resulting_pose="standing",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="stop",
                        target_id=marker["id"],
                        resulting_pose="standing",
                        chronology_rank=4,
                    ),
                ],
            ),
            _beat(
                "beat_3",
                phase="single_action",
                actions=[
                    _action(
                        "action_5",
                        actor_id="actor_2",
                        action_type="run",
                        resulting_pose="running",
                        chronology_rank=5,
                        modifier=_pick(rng, [None, "quickly"]),
                    )
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=marker["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=marker["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [marker["id"]],
            "alias_to_object_id": {
                alias: marker["id"] for alias in marker["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": [
            "beat_count=3",
            f"must_ground_object:{marker['id']}",
            "actor_2_runs_in_final_beat",
            "stop_phase_before_run",
            *([f"morphology_surface:{surface_hint}"] if variant == "morphology_stress" else []),
        ],
    }
    return _top_level_record(
        pattern_name="toward_each_other_then_stop_near_marked_object_then_second_runs",
        pattern_family="role_shift_motion",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"),
        required_semantics=("second_actor_runs", "stop_near_then_role_shift", "marked_object_grounding"),
        forbidden_collapses=("keep_both_stopped", "drop_final_run", "drop_stop_phase"),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object", "second_actor_runs"),
        canonical_source_template=_three_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            middle=f"оба останавливаются {_join_surface_phrase('у', surface_hint)}",
            ending="второй начинает бежать",
        ),
    )


def _toward_each_other_then_pass_by_marked_object_then_second_runs(
    graph_seed: int, variant: SourceVariantKey
) -> CIRRecord:
    rng = _pattern_rng("toward_each_other_then_pass_by_marked_object_then_second_runs", graph_seed, variant)
    base_object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, base_object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="pass_by"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="pass_by")
    marker = _marked_object(
        pattern_name="toward_each_other_then_pass_by_marked_object_then_second_runs",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first"),
            _actor("actor_2", ordinal="second"),
        ],
        "objects": [marker],
        "beats": [
            _beat(
                "beat_1",
                phase="toward_each_other",
                actions=walk_actions,
            ),
            _beat(
                "beat_2",
                phase="pass_by_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="pass_by",
                        target_id=marker["id"],
                        resulting_pose="walking",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="pass_by",
                        target_id=marker["id"],
                        resulting_pose="walking",
                        chronology_rank=4,
                    ),
                ],
            ),
            _beat(
                "beat_3",
                phase="single_action",
                actions=[
                    _action(
                        "action_5",
                        actor_id="actor_2",
                        action_type="run",
                        resulting_pose="running",
                        chronology_rank=5,
                        modifier=_pick(rng, [None, "quickly"]),
                    )
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [marker["id"]],
            "alias_to_object_id": {
                alias: marker["id"] for alias in marker["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": [
            "beat_count=3",
            f"must_ground_object:{marker['id']}",
            "pass_by_semantics",
            "actor_2_runs_in_final_beat",
            *([f"morphology_surface:{surface_hint}"] if variant == "morphology_stress" else []),
        ],
    }
    return _top_level_record(
        pattern_name="toward_each_other_then_pass_by_marked_object_then_second_runs",
        pattern_family="role_shift_motion",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"),
        required_semantics=("second_actor_runs", "pass_by_then_role_shift", "marked_object_grounding"),
        forbidden_collapses=("keep_both_walkers", "drop_final_run"),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_pass_by_marked_object", "second_actor_runs"),
        canonical_source_template=_three_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            middle=f"оба проходят {_join_surface_phrase('мимо', surface_hint)}",
            ending="второй начинает бежать",
        ),
    )


_SAME_TYPE_MARKER_PROFILES = (
    ("chair", "chair", "стул", "стулу", "стула"),
    ("table", "table", "стол", "столу", "стола"),
    ("generic", "monitor", "монитор", "монитору", "монитора"),
    ("generic", "terminal", "терминал", "терминалу", "терминала"),
    ("generic", "kiosk", "киоск", "киоску", "киоска"),
    ("cabinet", "cabinet", "шкаф", "шкафу", "шкафа"),
    ("shelf", "rack", "стеллаж", "стеллажу", "стеллажа"),
)


def _same_type_template(
    rng: random.Random,
    *,
    name_1: str,
    name_2: str,
    target_phrase: str,
    opposite_phrase: str,
) -> str:
    first_subject = _pick(
        rng,
        [
            f"Первый актёр {name_1}",
            f"{name_1}, первый актёр",
            f"Первый из актёров, {name_1}",
        ],
    )
    second_subject = _pick(
        rng,
        [
            f"второй актёр {name_2}",
            f"{name_2}, второй актёр",
            "второй актёр",
        ],
    )
    first_verb = _pick(rng, ["подходит к", "идёт к", "направляется к", "переходит к"])
    second_verb = _pick(rng, ["остаётся у", "ждёт у", "держится у", "останавливается у"])
    connector = _pick(rng, [", а ", ", затем ", ", после этого "])
    return f"{first_subject} {first_verb} {target_phrase}{connector}{second_subject} {second_verb} {opposite_phrase}."


def _same_type_two_marked_objects(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("same_type_two_marked_objects", graph_seed, variant)
    name_1, name_2 = _sample_actor_names(rng, 2)
    marker_type, marker_token, marker_source_name, target_noun_dative, opposite_noun_genitive = _pick(
        rng, list(_SAME_TYPE_MARKER_PROFILES)
    )
    left_name = f"left {marker_token}"
    right_name = f"right {marker_token}"
    left_aliases = [f"левый {marker_source_name}", left_name]
    right_aliases = [f"правый {marker_source_name}", right_name, f"тот {marker_source_name}"]
    left_object = _marked_object(
        pattern_name="same_type_two_marked_objects",
        graph_seed=graph_seed,
        slot=1,
        object_type=marker_type,
        name=left_name,
        aliases=left_aliases,
        source_name=marker_source_name,
        relative_position="left",
    )
    right_object = _marked_object(
        pattern_name="same_type_two_marked_objects",
        graph_seed=graph_seed,
        slot=2,
        object_type=marker_type,
        name=right_name,
        aliases=right_aliases,
        source_name=marker_source_name,
        relative_position="right",
    )
    target_object = _pick(rng, [left_object, right_object])
    opposite_object = right_object if target_object["id"] == left_object["id"] else left_object
    if target_object["id"] == right_object["id"]:
        target_side = "правому"
        opposite_side = "левого"
    else:
        target_side = "левому"
        opposite_side = "правого"
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
        ],
        "objects": [left_object, right_object],
        "beats": [
            _beat(
                "beat_1",
                phase="approach_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="approach",
                        target_id=target_object["id"],
                        direction="to_target",
                        resulting_pose="walking",
                        chronology_rank=1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="stand",
                        resulting_pose="standing",
                        chronology_rank=2,
                    ),
                ],
            )
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=target_object["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=opposite_object["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [left_object["id"], right_object["id"]],
            "alias_to_object_id": {
                **{alias: left_object["id"] for alias in left_object["marker_binding"]["mentioned_aliases"]},
                **{alias: right_object["id"] for alias in right_object["marker_binding"]["mentioned_aliases"]},
            },
        },
        "must_preserve": [
            "same_type_markers_present",
            f"must_ground_object:{target_object['id']}",
            f"second_actor_anchor:{opposite_object['id']}",
            "ordinal:first->actor_1",
            "ordinal:second->actor_2",
            "no_type_only_resolution",
        ],
    }
    return _top_level_record(
        pattern_name="same_type_two_marked_objects",
        pattern_family="marker_disambiguation",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("marked_object", "same_type_markers", "ordinal_reference", "grounding"),
        required_semantics=("two_marked_objects_same_type", "exact_marker_resolution"),
        forbidden_collapses=("type_only_resolution", "merge_markers"),
        beat_blueprint=("same_type_marker_resolution",),
        canonical_source_template=_same_type_template(
            rng,
            name_1=name_1,
            name_2=name_2,
            target_phrase=f"{target_side} {target_noun_dative}",
            opposite_phrase=f"{opposite_side} {opposite_noun_genitive}",
        ),
    )


def _same_type_two_marked_objects_left_right(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("same_type_two_marked_objects_left_right", graph_seed, variant)
    name_1, name_2 = _sample_actor_names(rng, 2)
    marker_type, marker_token, marker_source_name, target_noun_dative, opposite_noun_genitive = _pick(
        rng, list(_SAME_TYPE_MARKER_PROFILES)
    )
    left_name = f"left {marker_token}"
    right_name = f"right {marker_token}"
    left_aliases = [f"левый {marker_source_name}", left_name]
    right_aliases = [f"правый {marker_source_name}", right_name]
    left_object = _marked_object(
        pattern_name="same_type_two_marked_objects_left_right",
        graph_seed=graph_seed,
        slot=1,
        object_type=marker_type,
        name=left_name,
        aliases=left_aliases,
        source_name=marker_source_name,
        relative_position="left",
    )
    right_object = _marked_object(
        pattern_name="same_type_two_marked_objects_left_right",
        graph_seed=graph_seed,
        slot=2,
        object_type=marker_type,
        name=right_name,
        aliases=right_aliases,
        source_name=marker_source_name,
        relative_position="right",
    )
    target_object = _pick(rng, [left_object, right_object])
    opposite_object = right_object if target_object["id"] == left_object["id"] else left_object
    target_side = "левому" if target_object["id"] == left_object["id"] else "правому"
    opposite_side = "правого" if target_object["id"] == left_object["id"] else "левого"
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
        ],
        "objects": [left_object, right_object],
        "beats": [
            _beat(
                "beat_1",
                phase="approach_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="approach",
                        target_id=target_object["id"],
                        direction="to_target",
                        resulting_pose="walking",
                        chronology_rank=1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="stand",
                        resulting_pose="standing",
                        chronology_rank=2,
                    ),
                ],
            )
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=target_object["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=opposite_object["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [left_object["id"], right_object["id"]],
            "alias_to_object_id": {
                **{alias: left_object["id"] for alias in left_object["marker_binding"]["mentioned_aliases"]},
                **{alias: right_object["id"] for alias in right_object["marker_binding"]["mentioned_aliases"]},
            },
        },
        "must_preserve": [
            "same_type_markers_present",
            f"must_ground_object:{target_object['id']}",
            f"second_actor_anchor:{opposite_object['id']}",
            "ordinal:first->actor_1",
            "ordinal:second->actor_2",
            "marker_axis:left_right",
            "no_type_only_resolution",
        ],
    }
    return _top_level_record(
        pattern_name="same_type_two_marked_objects_left_right",
        pattern_family="marker_disambiguation",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("marked_object", "same_type_markers", "ordinal_reference", "grounding", "left_right"),
        required_semantics=("two_marked_objects_same_type", "exact_marker_resolution", "left_right_disambiguation"),
        forbidden_collapses=("type_only_resolution", "merge_markers", "drop_relative_side"),
        beat_blueprint=("same_type_marker_resolution",),
        canonical_source_template=_same_type_template(
            rng,
            name_1=name_1,
            name_2=name_2,
            target_phrase=f"{target_side} {target_noun_dative}",
            opposite_phrase=f"{opposite_side} {opposite_noun_genitive}",
        ),
    )


def _same_type_two_marked_objects_near_far(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("same_type_two_marked_objects_near_far", graph_seed, variant)
    name_1, name_2 = _sample_actor_names(rng, 2)
    marker_type, marker_token, marker_source_name, target_noun_dative, opposite_noun_genitive = _pick(
        rng, list(_SAME_TYPE_MARKER_PROFILES)
    )
    near_name = f"near {marker_token}"
    far_name = f"far {marker_token}"
    near_aliases = [f"ближний {marker_source_name}", near_name]
    far_aliases = [f"дальний {marker_source_name}", far_name]
    near_object = _marked_object(
        pattern_name="same_type_two_marked_objects_near_far",
        graph_seed=graph_seed,
        slot=1,
        object_type=marker_type,
        name=near_name,
        aliases=near_aliases,
        source_name=marker_source_name,
        relative_position="foreground",
    )
    far_object = _marked_object(
        pattern_name="same_type_two_marked_objects_near_far",
        graph_seed=graph_seed,
        slot=2,
        object_type=marker_type,
        name=far_name,
        aliases=far_aliases,
        source_name=marker_source_name,
        relative_position="background",
    )
    target_object = _pick(rng, [near_object, far_object])
    opposite_object = far_object if target_object["id"] == near_object["id"] else near_object
    target_depth = "ближнему" if target_object["id"] == near_object["id"] else "дальнему"
    opposite_depth = "дальнего" if target_object["id"] == near_object["id"] else "ближнего"
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
        ],
        "objects": [near_object, far_object],
        "beats": [
            _beat(
                "beat_1",
                phase="approach_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="approach",
                        target_id=target_object["id"],
                        direction="to_target",
                        resulting_pose="walking",
                        chronology_rank=1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="stand",
                        resulting_pose="standing",
                        chronology_rank=2,
                    ),
                ],
            )
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=target_object["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=opposite_object["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(2),
            "marked_object_ids": [near_object["id"], far_object["id"]],
            "alias_to_object_id": {
                **{alias: near_object["id"] for alias in near_object["marker_binding"]["mentioned_aliases"]},
                **{alias: far_object["id"] for alias in far_object["marker_binding"]["mentioned_aliases"]},
            },
        },
        "must_preserve": [
            "same_type_markers_present",
            f"must_ground_object:{target_object['id']}",
            f"second_actor_anchor:{opposite_object['id']}",
            "ordinal:first->actor_1",
            "ordinal:second->actor_2",
            "marker_axis:near_far",
            "no_type_only_resolution",
        ],
    }
    return _top_level_record(
        pattern_name="same_type_two_marked_objects_near_far",
        pattern_family="marker_disambiguation",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("marked_object", "same_type_markers", "ordinal_reference", "grounding", "near_far"),
        required_semantics=("two_marked_objects_same_type", "exact_marker_resolution", "near_far_disambiguation"),
        forbidden_collapses=("type_only_resolution", "merge_markers", "drop_relative_depth"),
        beat_blueprint=("same_type_marker_resolution",),
        canonical_source_template=_same_type_template(
            rng,
            name_1=name_1,
            name_2=name_2,
            target_phrase=f"{target_depth} {target_noun_dative}",
            opposite_phrase=f"{opposite_depth} {opposite_noun_genitive}",
        ),
    )


def _ordinal_first_second_third(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("ordinal_first_second_third", graph_seed, variant)
    primary_profiles = [
        ("table", "стол", "столу"),
        ("chair", "стул", "стулу"),
        ("cabinet", "шкаф", "шкафу"),
        ("generic", "стойка", "стойке"),
        ("generic", "терминал", "терминалу"),
        ("generic", "монитор", "монитору"),
        ("shelf", "стеллаж", "стеллажу"),
        ("chair", "лавка", "лавке"),
        ("generic", "панель", "панели"),
    ]
    anchor_profiles = [
        ("door", "дверь", "двери"),
        ("window", "окно", "окна"),
        ("shelf", "полка", "полки"),
        ("generic", "стена", "стены"),
        ("generic", "киоск", "киоска"),
        ("cabinet", "шкаф", "шкафа"),
        ("generic", "колонна", "колонны"),
    ]
    name_1, name_2, name_3 = _sample_actor_names(rng, 3)
    primary_type, primary_name, primary_dative = _pick(rng, primary_profiles)
    anchor_type, anchor_name, anchor_genitive = _pick(rng, anchor_profiles)
    primary_object = _unmarked_object(
        object_id="object_1",
        object_type=primary_type,
        name=primary_name,
        relative_position=_pick(rng, ["left", "center", "right"]),
    )
    anchor_object = _unmarked_object(
        object_id="object_2",
        object_type=anchor_type,
        name=anchor_name,
        relative_position=_pick(rng, ["left", "right", "background"]),
    )
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
            _actor("actor_3", ordinal="third", name=name_3),
        ],
        "objects": [primary_object, anchor_object],
        "beats": [
            _beat(
                "beat_1",
                phase="approach_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="approach",
                        target_id=primary_object["id"],
                        direction="to_target",
                        resulting_pose="walking",
                        chronology_rank=1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="look_at",
                        target_id="actor_1",
                        resulting_pose="standing",
                        chronology_rank=2,
                    ),
                    _action(
                        "action_3",
                        actor_id="actor_3",
                        action_type="stand",
                        resulting_pose="standing",
                        chronology_rank=3,
                    ),
                ],
            )
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=primary_object["id"]),
            _relation("rel_2", subject="actor_3", relation="near", object_id=anchor_object["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(3),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "ordinal:first->actor_1",
            "ordinal:second->actor_2",
            "ordinal:third->actor_3",
            f"third_actor_anchor:{anchor_object['id']}",
        ],
    }
    return _top_level_record(
        pattern_name="ordinal_first_second_third",
        pattern_family="three_actor_ordinal_binding",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("ordinal_reference", "three_actor", "asymmetry", "object_target"),
        required_semantics=("ordinal_map", "third_actor_binding", "three_actor_role_stability"),
        forbidden_collapses=("actor_swap", "ordinal_drop", "drop_third_actor"),
        beat_blueprint=("ordinal_focus_action",),
        canonical_source_template=_pick(
            rng,
            [
                f"Первый подходит к {primary_dative}, второй смотрит на первого, третий остаётся у {anchor_genitive}.",
                f"Первый идёт к {primary_dative}, второй следит за первым, третий ждёт у {anchor_genitive}.",
                f"Сначала первый направляется к {primary_dative}, второй смотрит на первого, а третий держится у {anchor_genitive}.",
            ],
        ),
    )


def _toward_each_other_then_stop_near_marked_object_then_third_actor_described_action(
    graph_seed: int,
    variant: SourceVariantKey,
) -> CIRRecord:
    rng = _pattern_rng("toward_each_other_then_stop_near_marked_object_then_third_actor_described_action", graph_seed, variant)
    object_profiles = _computer_marker_profiles()
    chosen_name, chosen_aliases = _pick(rng, object_profiles)
    canonical_source_name = chosen_name
    if variant == "morphology_stress":
        chosen_name, chosen_aliases, surface_hint = _morphology_profile(
            rng,
            base_name=chosen_name,
            oblique_forms=_computer_oblique_forms(canonical_source_name, relation="near"),
        )
    else:
        surface_hint = _relation_surface_hint(rng, base_name=canonical_source_name, relation="near")

    described_profiles = list(STOP_NEAR_THIRD_DESCRIBED_PROFILES)
    canonical_text, fallback_text, lemma = _pick(rng, described_profiles)
    marker = _marked_object(
        pattern_name="toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
        graph_seed=graph_seed,
        slot=1,
        object_type="generic",
        name=chosen_name,
        aliases=chosen_aliases,
        source_name=canonical_source_name,
        relative_position=_pick(rng, ["left", "right", "center", "unknown"]),
    )
    walk_modifier = _choose_walk_modifier(rng)
    modifier_surface = _localize_walk_modifier(walk_modifier)
    walk_actions = [
        _action(
            "action_1",
            actor_id="actor_1",
            action_type="walk",
            target_id="actor_2",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=1,
        ),
        _action(
            "action_2",
            actor_id="actor_2",
            action_type="walk",
            target_id="actor_1",
            direction="toward_each_other",
            resulting_pose="walking",
            chronology_rank=2,
        ),
    ]
    _apply_modifier_if_any(walk_actions, walk_modifier)
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first"),
            _actor("actor_2", ordinal="second"),
            _actor("actor_3", ordinal="third"),
        ],
        "objects": [marker],
        "beats": [
            _beat("beat_1", phase="toward_each_other", actions=walk_actions),
            _beat(
                "beat_2",
                phase="stop_near_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_1",
                        action_type="stop",
                        target_id=marker["id"],
                        resulting_pose="standing",
                        chronology_rank=3,
                    ),
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="stop",
                        target_id=marker["id"],
                        resulting_pose="standing",
                        chronology_rank=4,
                    ),
                    _action(
                        "action_5",
                        actor_id="actor_3",
                        action_type="stand",
                        resulting_pose="standing",
                        chronology_rank=5,
                    ),
                ],
            ),
            _beat(
                "beat_3",
                phase="third_described_action",
                actions=[
                    _action(
                        "action_6",
                        actor_id="actor_3",
                        action_type="described_action",
                        target_id=marker["id"],
                        resulting_pose="standing",
                        chronology_rank=6,
                        described_action={
                            "canonical_text": canonical_text,
                            "fallback_text": fallback_text,
                            "source_lemma_hint": lemma,
                        },
                        is_unsupported_runtime_action=True,
                        must_preserve_in_source=True,
                    )
                ],
            ),
        ],
        "spatial_relations": [
            _relation("rel_1", subject="actor_1", relation="near", object_id=marker["id"]),
            _relation("rel_2", subject="actor_2", relation="near", object_id=marker["id"]),
            _relation("rel_3", subject="actor_3", relation="near", object_id=marker["id"]),
        ],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(3),
            "marked_object_ids": [marker["id"]],
            "alias_to_object_id": {
                alias: marker["id"] for alias in marker["marker_binding"]["mentioned_aliases"]
            },
        },
        "must_preserve": [
            "beat_count=3",
            f"must_ground_object:{marker['id']}",
            "ordinal:third->actor_3",
            "action:action_6=described_action",
            "third_actor_terminal_action",
            *([f"morphology_surface:{surface_hint}"] if variant == "morphology_stress" else []),
        ],
    }
    return _top_level_record(
        pattern_name="toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
        pattern_family="three_actor_marked_action",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("movement", "marked_object", "three_actor", "described_action", "multi_beat"),
        required_semantics=("three_beat_chronology", "third_actor_described_action", "marked_object_grounding"),
        forbidden_collapses=("drop_third_actor", "rewrite_described_action_to_talk", "drop_stop_phase"),
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object", "third_actor_described_action"),
        canonical_source_template=_three_phase_template(
            rng,
            intro=_motion_intro_text(rng, modifier_surface=modifier_surface),
            middle=f"оба останавливаются {_join_surface_phrase('у', surface_hint)}",
            ending=f"третий {canonical_text}",
        ),
    )


def _dialogue_then_pick_up_object_then_give_to_third_actor(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("dialogue_then_pick_up_object_then_give_to_third_actor", graph_seed, variant)
    item_profiles = list(HANDOFF_ITEM_PROFILES)
    name_1, name_2, name_3 = _sample_actor_names(rng, 3)
    item_name_en, item_name_ru = _pick(rng, item_profiles)
    if variant == "dialogue_mix":
        line_1 = _pick(
            rng,
            [template.format(item=item_name_ru) for template in HANDOFF_DIALOGUE_MIX_FIRST_TEMPLATES],
        )
        line_2 = _pick(rng, list(HANDOFF_DIALOGUE_MIX_SECOND_TEMPLATES))
    else:
        line_1 = _pick(
            rng,
            [template.format(item=item_name_ru) for template in HANDOFF_DIALOGUE_BASE_FIRST_TEMPLATES],
        )
        line_2 = _pick(rng, list(HANDOFF_DIALOGUE_BASE_SECOND_TEMPLATES))
    item_pronoun = _handoff_pronoun(item_name_en)
    item = _unmarked_object(object_id="object_1", object_type="generic", name=item_name_en, relative_position="center")
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
            _actor("actor_3", ordinal="third", name=name_3),
        ],
        "objects": [item],
        "beats": [
            _beat(
                "beat_1",
                phase="dialogue_exchange",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="talk",
                        target_id="actor_2",
                        resulting_pose="standing",
                        chronology_rank=1,
                        dialogue=line_1,
                    ),
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="talk",
                        target_id="actor_1",
                        resulting_pose="standing",
                        chronology_rank=2,
                        dialogue=line_2,
                    ),
                ],
            ),
            _beat(
                "beat_2",
                phase="pickup_object",
                actions=[
                    _action(
                        "action_3",
                        actor_id="actor_2",
                        action_type="pick_up",
                        target_id=item["id"],
                        resulting_pose="standing",
                        chronology_rank=3,
                        holding_object=item["id"],
                    )
                ],
            ),
            _beat(
                "beat_3",
                phase="give_object",
                actions=[
                    _action(
                        "action_4",
                        actor_id="actor_2",
                        action_type="give",
                        target_id="actor_3",
                        resulting_pose="standing",
                        chronology_rank=4,
                        holding_object=item["id"],
                    )
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(3),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "beat_count=3",
            "ordinal:third->actor_3",
            f"handoff_object:{item['id']}",
            "final_target:actor_3",
        ],
    }
    return _top_level_record(
        pattern_name="dialogue_then_pick_up_object_then_give_to_third_actor",
        pattern_family="three_actor_handoff",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("dialogue", "pick_up", "give", "three_actor", "handoff"),
        required_semantics=("dialogue_precedes_pickup", "pickup_precedes_give", "third_actor_receives_object"),
        forbidden_collapses=("drop_give_phase", "rewrite_handoff_as_talk_only", "drop_third_actor"),
        beat_blueprint=("dialogue_exchange", "pickup_object", "give_object"),
        canonical_source_template=(
            f"{name_1.upper()}: {line_1} {name_2.upper()}: {line_2} "
            f"{name_2} берёт {item_name_ru} и передаёт {item_pronoun} третьему."
        ),
    )


def _first_pick_up_object_then_give_to_third_actor(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("first_pick_up_object_then_give_to_third_actor", graph_seed, variant)
    item_profiles = list(HANDOFF_ITEM_PROFILES)
    name_1, name_2, name_3 = _sample_actor_names(rng, 3)
    item_name_en, item_name_ru = _pick(rng, item_profiles)
    item_pronoun = _handoff_pronoun(item_name_en)
    item = _unmarked_object(object_id="object_1", object_type="generic", name=item_name_en, relative_position="center")
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
            _actor("actor_3", ordinal="third", name=name_3),
        ],
        "objects": [item],
        "beats": [
            _beat(
                "beat_1",
                phase="pickup_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_1",
                        action_type="pick_up",
                        target_id=item["id"],
                        resulting_pose="standing",
                        chronology_rank=1,
                        holding_object=item["id"],
                    )
                ],
            ),
            _beat(
                "beat_2",
                phase="give_object",
                actions=[
                    _action(
                        "action_2",
                        actor_id="actor_1",
                        action_type="give",
                        target_id="actor_3",
                        resulting_pose="standing",
                        chronology_rank=2,
                        holding_object=item["id"],
                    )
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(3),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "beat_count=2",
            "pickup_actor:actor_1",
            "give_actor:actor_1",
            "ordinal:third->actor_3",
            f"handoff_object:{item['id']}",
            "final_target:actor_3",
        ],
    }
    return _top_level_record(
        pattern_name="first_pick_up_object_then_give_to_third_actor",
        pattern_family="three_actor_handoff",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("pick_up", "give", "three_actor", "handoff", "ordinal_reference"),
        required_semantics=("pickup_precedes_give", "same_actor_completes_handoff", "third_actor_receives_object"),
        forbidden_collapses=("actor_swap_between_pickup_and_give", "drop_give_phase", "drop_third_actor"),
        beat_blueprint=("pickup_object", "give_object"),
        canonical_source_template=f"Первый берёт {item_name_ru} и передаёт {item_pronoun} третьему.",
    )


def _second_pick_up_object_then_give_to_third_actor(graph_seed: int, variant: SourceVariantKey) -> CIRRecord:
    rng = _pattern_rng("second_pick_up_object_then_give_to_third_actor", graph_seed, variant)
    item_profiles = list(HANDOFF_ITEM_PROFILES)
    name_1, name_2, name_3 = _sample_actor_names(rng, 3)
    item_name_en, item_name_ru = _pick(rng, item_profiles)
    item_pronoun = _handoff_pronoun(item_name_en)
    item = _unmarked_object(object_id="object_1", object_type="generic", name=item_name_en, relative_position="center")
    scene_graph = {
        "actors": [
            _actor("actor_1", ordinal="first", name=name_1),
            _actor("actor_2", ordinal="second", name=name_2),
            _actor("actor_3", ordinal="third", name=name_3),
        ],
        "objects": [item],
        "beats": [
            _beat(
                "beat_1",
                phase="pickup_object",
                actions=[
                    _action(
                        "action_1",
                        actor_id="actor_2",
                        action_type="pick_up",
                        target_id=item["id"],
                        resulting_pose="standing",
                        chronology_rank=1,
                        holding_object=item["id"],
                    )
                ],
            ),
            _beat(
                "beat_2",
                phase="give_object",
                actions=[
                    _action(
                        "action_2",
                        actor_id="actor_2",
                        action_type="give",
                        target_id="actor_3",
                        resulting_pose="standing",
                        chronology_rank=2,
                        holding_object=item["id"],
                    )
                ],
            ),
        ],
        "spatial_relations": [],
        "reference_bindings": {
            "ordinal_map": _ordinal_map(3),
            "marked_object_ids": [],
            "alias_to_object_id": {},
        },
        "must_preserve": [
            "beat_count=2",
            "pickup_actor:actor_2",
            "give_actor:actor_2",
            "ordinal:third->actor_3",
            f"handoff_object:{item['id']}",
            "final_target:actor_3",
        ],
    }
    return _top_level_record(
        pattern_name="second_pick_up_object_then_give_to_third_actor",
        pattern_family="three_actor_handoff",
        difficulty_bucket="hard",
        graph_seed=graph_seed,
        source_variant_key=variant,
        scene_graph=scene_graph,
        semantic_tags=("pick_up", "give", "three_actor", "handoff", "ordinal_reference"),
        required_semantics=("pickup_precedes_give", "same_actor_completes_handoff", "third_actor_receives_object"),
        forbidden_collapses=("actor_swap_between_pickup_and_give", "drop_give_phase", "drop_third_actor"),
        beat_blueprint=("pickup_object", "give_object"),
        canonical_source_template=f"Второй берёт {item_name_ru} и передаёт {item_pronoun} третьему.",
    )


PATTERN_REGISTRY: dict[str, PatternSpec] = {
    "dialogue_only": PatternSpec(
        pattern_name="dialogue_only",
        pattern_family="dialogue",
        difficulty_bucket="core",
        default_share=6,
        default_complexity_class="S",
        allowed_source_variant_keys=("base", "dialogue_mix"),
        required_actor_count=2,
        required_object_mode="none",
        beat_blueprint=("dialogue_exchange",),
        required_semantics=("talk_only", "no_invented_objects"),
        forbidden_collapses=("invent_object", "split_single_dialogue_beat"),
        semantic_tags=("dialogue", "two_actor", "baseline"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["dialogue_only"],
        builder=_dialogue_only,
    ),
    "dialogue_then_pick_up_object_then_give_to_third_actor": PatternSpec(
        pattern_name="dialogue_then_pick_up_object_then_give_to_third_actor",
        pattern_family="three_actor_handoff",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="L",
        allowed_source_variant_keys=("base", "dialogue_mix"),
        required_actor_count=3,
        required_object_mode="required_generic",
        beat_blueprint=("dialogue_exchange", "pickup_object", "give_object"),
        required_semantics=("dialogue_precedes_pickup", "pickup_precedes_give", "third_actor_receives_object"),
        forbidden_collapses=("drop_give_phase", "rewrite_handoff_as_talk_only", "drop_third_actor"),
        semantic_tags=("dialogue", "pick_up", "give", "three_actor", "handoff"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["dialogue_then_pick_up_object_then_give_to_third_actor"],
        builder=_dialogue_then_pick_up_object_then_give_to_third_actor,
    ),
    "first_pick_up_object_then_give_to_third_actor": PatternSpec(
        pattern_name="first_pick_up_object_then_give_to_third_actor",
        pattern_family="three_actor_handoff",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("base",),
        required_actor_count=3,
        required_object_mode="required_generic",
        beat_blueprint=("pickup_object", "give_object"),
        required_semantics=("pickup_precedes_give", "same_actor_completes_handoff", "third_actor_receives_object"),
        forbidden_collapses=("actor_swap_between_pickup_and_give", "drop_give_phase", "drop_third_actor"),
        semantic_tags=("pick_up", "give", "three_actor", "handoff", "ordinal_reference"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["first_pick_up_object_then_give_to_third_actor"],
        builder=_first_pick_up_object_then_give_to_third_actor,
    ),
    "dialogue_then_put_down_object": PatternSpec(
        pattern_name="dialogue_then_put_down_object",
        pattern_family="dialogue_object_followup",
        difficulty_bucket="core",
        default_share=6,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "dialogue_mix"),
        required_actor_count=2,
        required_object_mode="required_generic",
        beat_blueprint=("dialogue_exchange", "putdown_object"),
        required_semantics=("dialogue_precedes_put_down", "holding_object_preserved"),
        forbidden_collapses=("drop_put_down_followup", "talk_only_rewrite"),
        semantic_tags=("dialogue", "object_placement", "two_actor"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["dialogue_then_put_down_object"],
        builder=_dialogue_then_put_down_object,
    ),
    "dialogue_then_small_action": PatternSpec(
        pattern_name="dialogue_then_small_action",
        pattern_family="dialogue_followup",
        difficulty_bucket="core",
        default_share=5,
        default_complexity_class="S",
        allowed_source_variant_keys=("base", "dialogue_mix"),
        required_actor_count=2,
        required_object_mode="none",
        beat_blueprint=("dialogue_exchange", "single_small_followup_action"),
        required_semantics=("two_beat_ordering", "small_followup_action"),
        forbidden_collapses=("single_talk_only_beat",),
        semantic_tags=("dialogue", "small_action", "chronology"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["dialogue_then_small_action"],
        builder=_dialogue_then_small_action,
    ),
    "enter_then_put_down_object": PatternSpec(
        pattern_name="enter_then_put_down_object",
        pattern_family="object_placement",
        difficulty_bucket="core",
        default_share=5,
        default_complexity_class="M",
        allowed_source_variant_keys=("base",),
        required_actor_count=1,
        required_object_mode="required_generic",
        beat_blueprint=("single_action", "putdown_object"),
        required_semantics=("enter_then_put_down", "holding_object_preserved"),
        forbidden_collapses=("drop_enter_phase",),
        semantic_tags=("enter", "object_placement", "single_actor"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["enter_then_put_down_object"],
        builder=_enter_then_put_down_object,
    ),
    "open_then_pick_up_object": PatternSpec(
        pattern_name="open_then_pick_up_object",
        pattern_family="container_interaction",
        difficulty_bucket="core",
        default_share=8,
        default_complexity_class="M",
        allowed_source_variant_keys=("base",),
        required_actor_count=1,
        required_object_mode="required_generic",
        beat_blueprint=("open_object", "pickup_object"),
        required_semantics=("open_precedes_pick_up", "inside_relation"),
        forbidden_collapses=("skip_open",),
        semantic_tags=("open", "pick_up", "single_actor", "container"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["open_then_pick_up_object"],
        builder=_open_then_pick_up_object,
    ),
    "ordinal_first_second": PatternSpec(
        pattern_name="ordinal_first_second",
        pattern_family="ordinal_binding",
        difficulty_bucket="core",
        default_share=9,
        default_complexity_class="S",
        allowed_source_variant_keys=("base",),
        required_actor_count=2,
        required_object_mode="required_generic",
        beat_blueprint=("ordinal_focus_action",),
        required_semantics=("ordinal_map", "actor_role_stability"),
        forbidden_collapses=("actor_swap", "ordinal_drop"),
        semantic_tags=("ordinal_reference", "two_actor", "object_target"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["ordinal_first_second"],
        builder=_ordinal_first_second,
    ),
    "ordinal_first_second_third": PatternSpec(
        pattern_name="ordinal_first_second_third",
        pattern_family="three_actor_ordinal_binding",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="L",
        allowed_source_variant_keys=("base",),
        required_actor_count=3,
        required_object_mode="required_generic",
        beat_blueprint=("ordinal_focus_action",),
        required_semantics=("ordinal_map", "third_actor_binding", "three_actor_role_stability"),
        forbidden_collapses=("actor_swap", "ordinal_drop", "drop_third_actor"),
        semantic_tags=("ordinal_reference", "three_actor", "asymmetry", "object_target"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["ordinal_first_second_third"],
        builder=_ordinal_first_second_third,
    ),
    "pick_up_then_put_down_object": PatternSpec(
        pattern_name="pick_up_then_put_down_object",
        pattern_family="object_placement",
        difficulty_bucket="core",
        default_share=8,
        default_complexity_class="M",
        allowed_source_variant_keys=("base",),
        required_actor_count=1,
        required_object_mode="required_generic",
        beat_blueprint=("pickup_object", "putdown_object"),
        required_semantics=("pick_up_precedes_put_down", "holding_object_preserved"),
        forbidden_collapses=("drop_pick_up",),
        semantic_tags=("pick_up", "put_down", "single_actor", "object_placement"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["pick_up_then_put_down_object"],
        builder=_pick_up_then_put_down_object,
    ),
    "same_type_two_marked_objects": PatternSpec(
        pattern_name="same_type_two_marked_objects",
        pattern_family="marker_disambiguation",
        difficulty_bucket="hard",
        default_share=3,
        default_complexity_class="M",
        allowed_source_variant_keys=("same_type_marker_stress",),
        required_actor_count=2,
        required_object_mode="required_same_type_marked_pair",
        beat_blueprint=("same_type_marker_resolution",),
        required_semantics=("two_marked_objects_same_type", "exact_marker_resolution"),
        forbidden_collapses=("type_only_resolution", "merge_markers"),
        semantic_tags=("marked_object", "same_type_markers", "ordinal_reference", "grounding"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["same_type_two_marked_objects"],
        builder=_same_type_two_marked_objects,
    ),
    "same_type_two_marked_objects_left_right": PatternSpec(
        pattern_name="same_type_two_marked_objects_left_right",
        pattern_family="marker_disambiguation",
        difficulty_bucket="hard",
        default_share=3,
        default_complexity_class="M",
        allowed_source_variant_keys=("same_type_marker_stress",),
        required_actor_count=2,
        required_object_mode="required_same_type_marked_pair",
        beat_blueprint=("same_type_marker_resolution",),
        required_semantics=("two_marked_objects_same_type", "exact_marker_resolution", "left_right_disambiguation"),
        forbidden_collapses=("type_only_resolution", "merge_markers", "drop_relative_side"),
        semantic_tags=("marked_object", "same_type_markers", "ordinal_reference", "grounding", "left_right"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["same_type_two_marked_objects_left_right"],
        builder=_same_type_two_marked_objects_left_right,
    ),
    "same_type_two_marked_objects_near_far": PatternSpec(
        pattern_name="same_type_two_marked_objects_near_far",
        pattern_family="marker_disambiguation",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("same_type_marker_stress",),
        required_actor_count=2,
        required_object_mode="required_same_type_marked_pair",
        beat_blueprint=("same_type_marker_resolution",),
        required_semantics=("two_marked_objects_same_type", "exact_marker_resolution", "near_far_disambiguation"),
        forbidden_collapses=("type_only_resolution", "merge_markers", "drop_relative_depth"),
        semantic_tags=("marked_object", "same_type_markers", "ordinal_reference", "grounding", "near_far"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["same_type_two_marked_objects_near_far"],
        builder=_same_type_two_marked_objects_near_far,
    ),
    "stop_near_marked_object_then_first_described_action": PatternSpec(
        pattern_name="stop_near_marked_object_then_first_described_action",
        pattern_family="composed_marked_action",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "morphology_stress"),
        required_actor_count=2,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object", "first_actor_described_action"),
        required_semantics=("three_beat_chronology", "first_actor_described_action"),
        forbidden_collapses=("drop_stop_phase", "rewrite_described_action_to_talk"),
        semantic_tags=("movement", "marked_object", "ordinal_reference", "described_action", "multi_beat"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["stop_near_marked_object_then_first_described_action"],
        builder=_stop_near_marked_object_then_first_described_action,
    ),
    "toward_each_other": PatternSpec(
        pattern_name="toward_each_other",
        pattern_family="motion_symmetry",
        difficulty_bucket="core",
        default_share=4,
        default_complexity_class="S",
        allowed_source_variant_keys=("base", "ordinal_stress"),
        required_actor_count=2,
        required_object_mode="none",
        beat_blueprint=("mutual_walk_toward_each_other",),
        required_semantics=("direction_toward_each_other", "dual_motion"),
        forbidden_collapses=("single_actor_walk", "direction_drop"),
        semantic_tags=("movement", "symmetry", "two_actor"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other"],
        builder=_toward_each_other,
    ),
    "toward_each_other_then_pass_by_marked_object": PatternSpec(
        pattern_name="toward_each_other_then_pass_by_marked_object",
        pattern_family="motion_object_grounding",
        difficulty_bucket="core",
        default_share=9,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "ordinal_stress", "morphology_stress"),
        required_actor_count=2,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_pass_by_marked_object"),
        required_semantics=("marked_object_grounding", "dual_pass_by_object"),
        forbidden_collapses=("rewrite_pass_by_as_walk",),
        semantic_tags=("movement", "marked_object", "pass_by_object"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other_then_pass_by_marked_object"],
        builder=_toward_each_other_then_pass_by_marked_object,
    ),
    "toward_each_other_then_pass_by_object_then_second_runs": PatternSpec(
        pattern_name="toward_each_other_then_pass_by_object_then_second_runs",
        pattern_family="role_shift_motion",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "morphology_stress"),
        required_actor_count=2,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_pass_by_marked_object", "second_actor_runs"),
        required_semantics=("second_actor_runs", "pass_by_then_role_shift"),
        forbidden_collapses=("keep_both_walkers", "drop_final_run"),
        semantic_tags=("movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other_then_pass_by_object_then_second_runs"],
        builder=_toward_each_other_then_pass_by_object_then_second_runs,
    ),
    "toward_each_other_then_pass_by_marked_object_then_second_runs": PatternSpec(
        pattern_name="toward_each_other_then_pass_by_marked_object_then_second_runs",
        pattern_family="role_shift_motion",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "morphology_stress"),
        required_actor_count=2,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_pass_by_marked_object", "second_actor_runs"),
        required_semantics=("second_actor_runs", "pass_by_then_role_shift", "marked_object_grounding"),
        forbidden_collapses=("keep_both_walkers", "drop_final_run"),
        semantic_tags=("movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other_then_pass_by_marked_object_then_second_runs"],
        builder=_toward_each_other_then_pass_by_marked_object_then_second_runs,
    ),
    "toward_each_other_then_stop_near_marked_object_then_second_runs": PatternSpec(
        pattern_name="toward_each_other_then_stop_near_marked_object_then_second_runs",
        pattern_family="role_shift_motion",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "morphology_stress"),
        required_actor_count=2,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object", "second_actor_runs"),
        required_semantics=("second_actor_runs", "stop_near_then_role_shift", "marked_object_grounding"),
        forbidden_collapses=("keep_both_stopped", "drop_final_run", "drop_stop_phase"),
        semantic_tags=("movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other_then_stop_near_marked_object_then_second_runs"],
        builder=_toward_each_other_then_stop_near_marked_object_then_second_runs,
    ),
    "toward_each_other_then_stop_near_marked_object": PatternSpec(
        pattern_name="toward_each_other_then_stop_near_marked_object",
        pattern_family="motion_object_grounding",
        difficulty_bucket="core",
        default_share=10,
        default_complexity_class="M",
        allowed_source_variant_keys=("base", "ordinal_stress", "morphology_stress"),
        required_actor_count=2,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object"),
        required_semantics=("marked_object_grounding", "dual_stop_near_object"),
        forbidden_collapses=("one_beat_merge", "approach_instead_of_stop"),
        semantic_tags=("movement", "marked_object", "stop_near_object"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other_then_stop_near_marked_object"],
        builder=_toward_each_other_then_stop_near_marked_object,
    ),
    "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action": PatternSpec(
        pattern_name="toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
        pattern_family="three_actor_marked_action",
        difficulty_bucket="hard",
        default_share=1,
        default_complexity_class="L",
        allowed_source_variant_keys=("base", "morphology_stress"),
        required_actor_count=3,
        required_object_mode="required_marked",
        beat_blueprint=("mutual_walk_toward_each_other", "dual_stop_near_marked_object", "third_actor_described_action"),
        required_semantics=("three_beat_chronology", "third_actor_described_action", "marked_object_grounding"),
        forbidden_collapses=("drop_third_actor", "rewrite_described_action_to_talk", "drop_stop_phase"),
        semantic_tags=("movement", "marked_object", "three_actor", "described_action", "multi_beat"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["toward_each_other_then_stop_near_marked_object_then_third_actor_described_action"],
        builder=_toward_each_other_then_stop_near_marked_object_then_third_actor_described_action,
    ),
    "second_pick_up_object_then_give_to_third_actor": PatternSpec(
        pattern_name="second_pick_up_object_then_give_to_third_actor",
        pattern_family="three_actor_handoff",
        difficulty_bucket="hard",
        default_share=2,
        default_complexity_class="M",
        allowed_source_variant_keys=("base",),
        required_actor_count=3,
        required_object_mode="required_generic",
        beat_blueprint=("pickup_object", "give_object"),
        required_semantics=("pickup_precedes_give", "same_actor_completes_handoff", "third_actor_receives_object"),
        forbidden_collapses=("actor_swap_between_pickup_and_give", "drop_give_phase", "drop_third_actor"),
        semantic_tags=("pick_up", "give", "three_actor", "handoff", "ordinal_reference"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["second_pick_up_object_then_give_to_third_actor"],
        builder=_second_pick_up_object_then_give_to_third_actor,
    ),
    "unsupported_action_described_action": PatternSpec(
        pattern_name="unsupported_action_described_action",
        pattern_family="unsupported_action",
        difficulty_bucket="core",
        default_share=5,
        default_complexity_class="S",
        allowed_source_variant_keys=("base",),
        required_actor_count=1,
        required_object_mode="required_generic",
        beat_blueprint=("single_described_action",),
        required_semantics=("unsupported_to_described_action", "must_preserve_source"),
        forbidden_collapses=("rewrite_to_talk", "rewrite_to_stand"),
        semantic_tags=("described_action", "single_actor", "unsupported_action"),
        canonical_source_template=PATTERN_SPEC_CANONICAL_TEMPLATES["unsupported_action_described_action"],
        builder=_unsupported_action_described_action,
    ),
}


def list_pattern_names(*, difficulty_bucket: DifficultyBucket | None = None) -> list[str]:
    specs = sorted(PATTERN_REGISTRY.values(), key=lambda item: item.pattern_name)
    if difficulty_bucket is not None:
        specs = [spec for spec in specs if spec.difficulty_bucket == difficulty_bucket]
    return [spec.pattern_name for spec in specs]


def _variant_weight(spec: PatternSpec, variant: SourceVariantKey) -> int:
    semantic_tags = {str(tag) for tag in spec.semantic_tags}
    if variant == "base":
        if "marked_object" in semantic_tags and "morphology_stress" in spec.allowed_source_variant_keys:
            return 45
        if "ordinal_reference" in semantic_tags and "ordinal_stress" in spec.allowed_source_variant_keys:
            return 45
        return 60
    if variant == "ordinal_stress":
        if "ordinal_reference" in semantic_tags:
            return 30
        return 20
    if variant == "morphology_stress":
        if "marked_object" in semantic_tags:
            return 35
        return 15
    if variant == "dialogue_mix":
        return 8
    if variant == "same_type_marker_stress":
        return 100
    return 1


def _choose_variant(spec: PatternSpec, rng: random.Random) -> SourceVariantKey:
    allowed = list(spec.allowed_source_variant_keys)
    if len(allowed) == 1:
        return allowed[0]
    weights = [_variant_weight(spec, variant) for variant in allowed]
    total = sum(weights)
    needle = rng.randrange(total)
    seen = 0
    for variant, weight in zip(allowed, weights):
        seen += weight
        if needle < seen:
            return variant
    return allowed[-1]


def generate_pattern_record(
    pattern_name: str,
    *,
    graph_seed: int,
    source_variant_key: SourceVariantKey | None = None,
) -> CIRRecord:
    try:
        spec = PATTERN_REGISTRY[pattern_name]
    except KeyError as exc:
        raise KeyError(f"Unknown pattern_name={pattern_name!r}") from exc
    return spec.build(graph_seed, source_variant_key)


def enumerate_pattern_records(
    *,
    seed: int,
    difficulty_bucket: DifficultyBucket | None = None,
    pattern_names: list[str] | None = None,
    total_records: int | None = None,
) -> list[CIRRecord]:
    if pattern_names is not None:
        specs = [PATTERN_REGISTRY[name] for name in pattern_names]
    else:
        specs = sorted(PATTERN_REGISTRY.values(), key=lambda item: item.pattern_name)
    if difficulty_bucket is not None:
        specs = [spec for spec in specs if spec.difficulty_bucket == difficulty_bucket]
    if not specs:
        return []

    if total_records is None:
        total_records = sum(spec.default_share for spec in specs)
    if total_records <= 0:
        return []

    rng = random.Random(seed)
    counts = _allocate_counts(specs, total_records)
    records: list[CIRRecord] = []
    for spec in specs:
        for _ in range(counts[spec.pattern_name]):
            graph_seed = rng.randint(100, 999_999)
            variant = _choose_variant(spec, rng)
            records.append(spec.build(graph_seed, variant))
    rng.shuffle(records)
    return records
