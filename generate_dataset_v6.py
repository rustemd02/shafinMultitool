#!/usr/bin/env python3
"""
generate_dataset_v6_chunk_realistic.py

LEGACY NOTE:
- этот генератор остаётся reference-only для pre-SG-v7 pipeline
- canonical SG v7 dataset path начинается с `generate_dataset_v7.py`
- любые post-hoc repair/autocorrection правила в этом файле не считаются частью canonical CIR contract

Генерация обучающего датасета SceneScript для локального парсера мизансцен,
с прицелом на реальные чанки, которые приложение будет получать после разбиения
ЦЕЛОГО сценария на фрагменты.

Ключевая идея v6 strict:
- генерировать не сразу короткий самодостаточный чанк,
  а длинный НЕсценовый непрерывный фрагмент одной сцены (8-14 строк)
- затем алгоритмически вырезать из него contiguous chunk на 2-5 строк/реплик,
  чаще из СЕРЕДИНЫ, а не из начала
- разрешать диалоговые чанки и куски, где нет повторной экспозиции локации
- жёстче отсекать стартовую статическую расстановку и overdramatic мусор

Это делает синтетику ближе к реальному поведению приложения:
пользователь загружает сценарий целиком, приложение режет его на фрагменты,
а локальная модель получает кусок уже идущей сцены, а не маленькую автономную зарисовку.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import re
import threading
import time
from typing import Optional, Iterator

from openai import OpenAI
from pydantic import BaseModel, ConfigDict, ValidationError, field_validator, model_validator


# ─────────────────────────────
# Конфигурация
# ─────────────────────────────

TARGET_COUNT = 1500
OUTPUT_FILE = "dataset_finetune_v6_strict.jsonl"
REJECTED_FILE = "dataset_finetune_v6_strict_rejected.jsonl"
FILTER_REVIEW_FILE = "dataset_finetune_v6_strict_filter_review.jsonl"
DEBUG_SELECTION_FILE = "dataset_finetune_v6_chunk_debug.jsonl"

SOURCE_MODEL = "gpt-5.4-nano"
JSON_MODEL = "gpt-5.4-nano"
# JSON_MODEL = "gpt-5.4-nano"
# SOURCE_MODEL = "gpt-5.4-mini"
# JSON_MODEL = "openai/gpt-oss-120b"
BASE_URL = "https://polza.ai/api/v1"

MAX_TOTAL_ATTEMPTS = 50000
MAX_JSON_ATTEMPTS_PER_SAMPLE = 4
MAX_SOURCE_SCENE_ATTEMPTS_PER_SAMPLE = 5
MAX_CHUNK_EXTRACTION_ATTEMPTS_PER_SOURCE = 20
RANDOM_SEED = 42

SOURCE_SCENE_MIN_UNITS = 8
SOURCE_SCENE_MAX_UNITS = 14
CHUNK_MIN_UNITS = 2
CHUNK_MAX_UNITS = 5

KEEP_STATIC_START_RATIO = 0.12

ID_RE = re.compile(r"^[a-z0-9_]+$")
DIALOGUE_LINE_RE = re.compile(r"^[A-Za-zА-ЯЁа-яё][^:\n]{0,30}:\s*.+$")

VALID_ACTOR_TYPES = {
    "human", "tiger", "lion", "dog", "cat", "bird", "generic"
}

VALID_OBJECT_TYPES = {
    "table", "chair", "cabinet", "door", "couch", "bed", "window", "shelf", "tv",
    "generic"
}

VALID_ACTION_TYPES = {
    "walk", "run", "approach", "pass_by", "enter", "exit", "stand", "sit",
    "lie_down", "stop", "turn", "crouch", "look_at", "pick_up", "put_down",
    "open", "close", "give", "talk", "described_action"
}

VALID_POSES = {
    "standing", "sitting", "crouching", "lying", "walking", "running"
}

VALID_SHOT_TYPES = {
    "wide", "medium", "close_up", "extreme_close_up", "over_shoulder", "two_shot"
}

VALID_CAMERA_MOVEMENTS = {
    "static", "pan_left", "pan_right", "tilt_up", "tilt_down",
    "dolly_in", "dolly_out", "tracking", "crane_up", "crane_down"
}

VALID_DIRECTIONS = {
    "left", "right", "forward", "backward",
    "toward_each_other", "away_from_each_other", "to_target"
}

VALID_MODIFIERS = {
    "slowly", "quickly", "carefully"
}

VALID_RELATIVE_POSITIONS = {
    "left", "right", "center", "background", "foreground", "unknown"
}

VALID_RELATION_TYPES = {
    "near", "in_front_of", "behind", "left_of", "right_of",
    "between", "pass_by", "inside", "outside"
}

VALID_INTERIOR_EXTERIOR = {
    "int", "ext", "mixed", "unknown"
}


# ─────────────────────────────
# Фильтрация и эвристики
# ─────────────────────────────

STATIC_START_PATTERNS = [
    r"^\s*[А-ЯЁA-Z][а-яёa-z]+(?:\s+[А-ЯЁA-Z][а-яёa-z]+)?\s+(молча\s+|всё ещё\s+|все еще\s+|по-прежнему\s+)?(стоит|сидит|лежит)\b",
    r"^\s*(Двое|Трое|Несколько|Оба)\s+(молча\s+)?(стоят|сидят|лежат)\b",
    r"^\s*[А-ЯЁA-Z][а-яёa-z]+(?:\s+[А-ЯЁA-Z][а-яёa-z]+)?\s+(остаётся|остается)\s+(стоять|сидеть|лежать)\b",
    r"^\s*(На кухне|В коридоре|У двери|За столом|У окна|На диване|На площадке)\s+[А-ЯЁA-Z][а-яёa-z]+(?:\s+[А-ЯЁA-Z][а-яёa-z]+)?\s+(стоит|сидит|лежит)\b",
    r"^\s*(За столом|У окна|У двери|В коридоре|На кухне|На диване|На площадке)\s+(стоит|сидит|лежит)\s+[А-ЯЁA-Z][а-яёa-z]+(?:\s+[А-ЯЁA-Z][а-яёa-z]+)?\b",
    r"^\s*[А-ЯЁA-Z][а-яёa-z]+(?:\s+[А-ЯЁA-Z][а-яёa-z]+)?\s+держит\b",
    r"^\s*[А-ЯЁA-Z][а-яёa-z]+(?:\s+[А-ЯЁA-Z][а-яёa-z]+)?\s+смотрит\b",
]

HARD_DRAMA_TERMS = [
    "швыр", "лома", "разбива", "бьёт", "бьет", "кидает в стену", "кидается",
    "с силой толка", "выхватыва", "вырыва", "хватает за", "рвёт рубашку",
    "рвет рубашку", "разносит", "опрокидывает", "бросает ноутбук", "швыряет бокал",
    "дёргает за волосы", "дергает за волосы", "бьёт кулаком", "бьет кулаком",
]

SOFT_DRAMA_TERMS = [
    "хватает", "толкает", "кричит", "орет", "орёт", "преграждает",
    "бросает", "резко", "на повышенных тонах", "рывком", "с грохотом",
    "перебивает", "отрывисто", "жестко", "жёстко", "смотрит в упор",
    "повышает голос", "не дает пройти", "не даёт пройти", "нависает",
    "делает шаг к нему", "делает шаг к ней", "почти бегом", "почти бегут",
]

ATMOSPHERE_TERMS = [
    "повисает тишина", "тусклый свет", "напряженная тишина",
    "напряжённая тишина", "в воздухе", "повисает пауза",
    "гнетущая тишина", "тягостная пауза", "повисает неловкая пауза",
]

CALM_ACTION_HINTS = [
    "подходит", "отходит", "оборачивается", "садится", "встает", "встаёт",
    "берёт", "берет", "кладёт", "кладет", "открывает", "закрывает", "ставит",
    "протягивает", "поворачивается", "убирает", "листает", "забирает",
    "поднимает", "опускает", "останавливается", "ждёт", "ждет", "передаёт",
    "передает", "показывает", "подвигает", "убавляет", "проверяет", "достает",
    "достаёт", "выходит", "входит", "спускается", "поднимается", "отвечает",
]

STATIC_VERBS = [
    "стоит", "сидит", "лежит", "ждет", "ждёт", "молчит", "смотрит", "держит",
    "остается", "остаётся",
]

ACTION_LIGHT_VERBS = [
    "подходит", "отходит", "открывает", "закрывает", "ставит", "берёт", "берет",
    "кладёт", "кладет", "протягивает", "оборачивается", "садится", "встаёт", "встает",
    "поворачивается", "убирает", "листает", "достаёт", "достает", "показывает",
    "подвигает", "отвечает", "спрашивает", "входит", "выходит", "останавливается",
]

META_LEAK_TERMS = [
    "уточните", "хотите ли вы", "могу сгенерировать", "вариант", "объяснение",
    "создай", "сгенерируй", "ответ —", "без пояснений", "пользователь",
]

SCENE_COMPLETION_TERMS = [
    "и уходит", "и выходит", "после чего уходит", "на этом разговор заканчивается",
    "оба замолкают", "сцена заканчивается",
]

PRONOUN_ACTOR_NAMES = {
    "он", "она", "они", "оно", "его", "её", "ее", "ему", "ей", "их",
    "неё", "нее", "сам", "сама",
}

PLACEHOLDER_DIALOGUES = {
    "...", "…", "-", "—", "--", "(...)", "({исходный кивок и подтверждение})",
}

ABSTRACT_OBJECT_TERMS = [
    "приложение", "закладка", "вкладка", "кнопка", "поле", "экран", "индикатор",
    "карман", "очередь", "номерок", "подпись", "строка", "цифра", "значение",
    "процент", "итого", "копия", "оригинал", "уголок бумаги", "скрин",
]

MICRO_ACTION_TYPES = {"look_at", "turn", "stand", "stop"}
MAX_REASONABLE_OBJECTS_PER_CHUNK = 4

CONTINUATION_START_MARKERS = [
    "тогда", "подожди", "нет", "не этот", "не туда", "не про это", "я же",
    "сейчас", "смотри", "ага", "ну", "только", "ещё", "еще", "опять",
    "здесь", "там", "вот", "этот", "эта", "эти", "второй", "первый",
    "снова", "пока", "ладно", "просто", "если что",
]

CONTINUATION_ANY_MARKERS = [
    "тогда", "ещё", "еще", "снова", "опять", "всё равно", "я же",
    "не этот", "не туда", "не про это", "второй", "первый", "дальше",
    "здесь", "там", "вот", "этот", "эта", "эти", "тот", "та",
]

RESOLUTION_END_MARKERS = [
    "договорились", "спасибо", "понял", "поняла", "хорошо, я пошел",
    "хорошо, я пошёл", "всё, идём", "все, идем", "всё, пошли",
    "все, пошли", "ладно, пошли", "я сейчас", "на этом всё",
]

CATEGORY_GROUNDING = {
    "kitchen_small_talk": {
        "prefer": ["чайник", "кружк", "холодиль", "контейнер", "термос", "завтрак", "кухон", "хлеб", "сыр"],
        "avoid": ["регистратур", "талон", "палат", "анализ", "касс", "перрон", "автобус"],
    },
    "hallway_entry": {
        "prefer": ["двер", "ключ", "пакет", "куртк", "коридор", "тумб", "прихож", "домофон"],
        "avoid": ["касс", "талон", "палат", "холодиль", "плита", "перрон"],
    },
    "office_deskwork": {
        "prefer": ["папк", "лист", "таблиц", "ноутбук", "файл", "отч", "цифр", "документ"],
        "avoid": ["автобус", "перрон", "касс", "палат", "кров", "чайник"],
    },
    "living_room_evening": {
        "prefer": ["диван", "пульт", "телевиз", "плед", "кресл", "тумб", "чай", "блокнот"],
        "avoid": ["регистратур", "талон", "касс", "перрон", "палат", "анализ"],
    },
    "stairwell_meeting": {
        "prefer": ["ступен", "площадк", "двер", "замок", "зуммер", "подъезд", "ключ"],
        "avoid": ["касс", "талон", "палат", "холодиль", "телевиз"],
    },
    "hospital_corridor_calm": {
        "prefer": ["коридор", "палат", "карт", "анализ", "медкарт", "кабинет", "врач", "медсестр"],
        "avoid": ["чайник", "холодиль", "касс", "лент", "подъезд"],
    },
    "clinic_reception": {
        "prefer": ["стойк", "талон", "запис", "регистрат", "паспорт", "кабинет", "посетител"],
        "avoid": ["чайник", "плита", "диван", "плед", "подъезд", "перрон"],
    },
    "apartment_packing_calm": {
        "prefer": ["чемодан", "рюкзак", "зарядк", "паспорт", "сумк", "шкаф", "одежд", "молни"],
        "avoid": ["регистратур", "талон", "касс", "перрон", "палат"],
    },
    "courtyard_daily": {
        "prefer": ["двор", "машин", "подъезд", "калитк", "пакет", "улиц", "лавк", "домофон"],
        "avoid": ["стол", "папк", "регистратур", "талон", "палат", "касс", "чайник"],
    },
    "school_corridor_calm": {
        "prefer": ["коридор", "журнал", "ученик", "учител", "класс", "окно", "тетрад", "ручк"],
        "avoid": ["регистратур", "талон", "палат", "пульт", "диван"],
    },
    "store_checkout_calm": {
        "prefer": ["касс", "лент", "пакет", "терминал", "товар", "ценник", "покупат", "продав"],
        "avoid": ["палат", "регистратур", "перрон", "автобус", "диван"],
    },
    "bus_stop_daily": {
        "prefer": ["остановк", "маршрут", "расписан", "автобус", "табличк", "перрон", "платформ"],
        "avoid": ["стол", "папк", "регистратур", "касс", "чайник", "палат"],
    },
    "unsupported_behavior_scene": {
        "prefer": ["машет", "кивает", "поцел", "тишин", "двер"],
        "avoid": ["касс", "талон", "анализ", "автобус"],
    },
}


# ─────────────────────────────
# Профили генерации непрерывных сцен и извлечения чанков
# ─────────────────────────────


SOURCE_FRAGMENT_MODES = [
    {
        "name": "dialogue_heavy",
        "weight": 22,
        "instruction": "Сделай фрагмент разговорным: несколько соседних строк могут быть чистыми репликами, но между ними иногда вставляй маленькие действия.",
    },
    {
        "name": "mixed_continuation",
        "weight": 30,
        "instruction": "Сделай фрагмент смешанным: короткие действия, обмен предметами, реплики, перемещения по комнате или коридору.",
    },
    {
        "name": "action_heavy",
        "weight": 14,
        "instruction": "Сделай фрагмент более действенным, но бытовым: сборы, открывание дверей, передача предметов, короткие реакции, без экшена.",
    },
    {
        "name": "pause_reaction",
        "weight": 10,
        "instruction": "Сделай фрагмент спокойным и немного паузным: короткие реакции, взгляды, мелкие действия, продолжение уже идущего разговора.",
    },
    {
        "name": "abrupt_middle",
        "weight": 14,
        "instruction": "Сделай фрагмент так, чтобы внутри него были 2-3 строки, звучащие как середина уже идущего разговора или действия: без повторного setup, с зависимостью от предыдущего контекста.",
    },
    {
        "name": "continuation_anaphora",
        "weight": 10,
        "instruction": "Добавь в фрагмент несколько контекстно-зависимых строк с продолжением мысли: 'тогда', 'не этот', 'я же про другое', 'подожди', 'второй лист', 'сейчас покажу'.",
    },
]

CHUNK_PROFILES = [
    {
        "name": "dialogue_continuation",
        "weight": 20,
        "need_dialogue": True,
        "min_dialogue_units": 2,
        "max_dialogue_units": 5,
        "prefer_start_dialogue": True,
        "prefer_middle": True,
        "allow_dialogue_only": True,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": True,
        "allow_local_resolution": False,
    },
    {
        "name": "dialogue_with_small_action",
        "weight": 20,
        "need_dialogue": True,
        "min_dialogue_units": 1,
        "max_dialogue_units": 4,
        "prefer_start_dialogue": False,
        "prefer_middle": True,
        "allow_dialogue_only": False,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": True,
        "allow_local_resolution": False,
    },
    {
        "name": "mid_scene_action",
        "weight": 18,
        "need_dialogue": False,
        "min_dialogue_units": 0,
        "max_dialogue_units": 1,
        "prefer_start_dialogue": False,
        "prefer_middle": True,
        "allow_dialogue_only": False,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": False,
        "allow_local_resolution": False,
    },
    {
        "name": "parallel_beat_mix",
        "weight": 16,
        "need_dialogue": False,
        "min_dialogue_units": 0,
        "max_dialogue_units": 3,
        "prefer_start_dialogue": False,
        "prefer_middle": True,
        "allow_dialogue_only": False,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": False,
        "allow_local_resolution": False,
    },
    {
        "name": "micro_transition",
        "weight": 8,
        "need_dialogue": False,
        "min_dialogue_units": 0,
        "max_dialogue_units": 2,
        "prefer_start_dialogue": False,
        "prefer_middle": False,
        "allow_dialogue_only": False,
        "require_context_before": True,
        "require_context_after": False,
        "prefer_abrupt_start": False,
        "allow_local_resolution": False,
    },
    {
        "name": "abrupt_dialogue_middle",
        "weight": 12,
        "need_dialogue": True,
        "min_dialogue_units": 2,
        "max_dialogue_units": 4,
        "prefer_start_dialogue": True,
        "prefer_middle": True,
        "allow_dialogue_only": True,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": True,
        "allow_local_resolution": False,
    },
    {
        "name": "continuation_without_setup",
        "weight": 10,
        "need_dialogue": False,
        "min_dialogue_units": 0,
        "max_dialogue_units": 3,
        "prefer_start_dialogue": False,
        "prefer_middle": True,
        "allow_dialogue_only": False,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": True,
        "allow_local_resolution": False,
    },
    {
        "name": "partial_action_followthrough",
        "weight": 8,
        "need_dialogue": False,
        "min_dialogue_units": 0,
        "max_dialogue_units": 2,
        "prefer_start_dialogue": False,
        "prefer_middle": True,
        "allow_dialogue_only": False,
        "require_context_before": True,
        "require_context_after": True,
        "prefer_abrupt_start": False,
        "allow_local_resolution": False,
    },
]



# ─────────────────────────────
# Pydantic-модели
# ─────────────────────────────

class Position3D(BaseModel):
    model_config = ConfigDict(extra="forbid")
    x: float
    y: float
    z: float


class SceneActor(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    type: str
    name: Optional[str] = None

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not v.startswith("actor_"):
            raise ValueError("SceneActor.id должен начинаться с actor_")
        if not ID_RE.fullmatch(v):
            raise ValueError("SceneActor.id содержит недопустимые символы")
        return v

    @field_validator("type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        if v not in VALID_ACTOR_TYPES:
            raise ValueError(f"Недопустимый actor.type: {v}")
        return v


class SceneObject(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    type: str
    name: Optional[str] = None
    detectedPosition: Optional[Position3D] = None
    relativePosition: str

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not v.startswith("object_"):
            raise ValueError("SceneObject.id должен начинаться с object_")
        if not ID_RE.fullmatch(v):
            raise ValueError("SceneObject.id содержит недопустимые символы")
        return v

    @field_validator("type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        if v not in VALID_OBJECT_TYPES:
            raise ValueError(f"Недопустимый object.type: {v}")
        return v

    @field_validator("relativePosition")
    @classmethod
    def validate_relative_position(cls, v: str) -> str:
        if v not in VALID_RELATIVE_POSITIONS:
            raise ValueError(f"Недопустимый relativePosition: {v}")
        return v


class CameraSetup(BaseModel):
    model_config = ConfigDict(extra="forbid")

    shotType: str
    movement: Optional[str] = None
    target: Optional[str] = None

    @field_validator("shotType")
    @classmethod
    def validate_shot_type(cls, v: str) -> str:
        if v not in VALID_SHOT_TYPES:
            raise ValueError(f"Недопустимый camera.shotType: {v}")
        return v

    @field_validator("movement")
    @classmethod
    def validate_movement(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_CAMERA_MOVEMENTS:
            raise ValueError(f"Недопустимый camera.movement: {v}")
        return v

    @field_validator("target")
    @classmethod
    def validate_target_format(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not ID_RE.fullmatch(v):
            raise ValueError("camera.target содержит недопустимые символы")
        return v


class SceneAction(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    actorId: str
    type: str
    target: Optional[str] = None
    direction: Optional[str] = None
    modifier: Optional[str] = None
    resultingPose: str
    holdingObject: Optional[str] = None
    dialogue: Optional[str] = None
    fallbackText: Optional[str] = None
    sourceText: Optional[str] = None

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not v.startswith("action_"):
            raise ValueError("SceneAction.id должен начинаться с action_")
        if not ID_RE.fullmatch(v):
            raise ValueError("SceneAction.id содержит недопустимые символы")
        return v

    @field_validator("actorId")
    @classmethod
    def validate_actor_id(cls, v: str) -> str:
        if not v.startswith("actor_"):
            raise ValueError("SceneAction.actorId должен начинаться с actor_")
        if not ID_RE.fullmatch(v):
            raise ValueError("SceneAction.actorId содержит недопустимые символы")
        return v

    @field_validator("type")
    @classmethod
    def validate_action_type(cls, v: str) -> str:
        if v not in VALID_ACTION_TYPES:
            raise ValueError(f"Недопустимый action.type: {v}")
        return v

    @field_validator("direction")
    @classmethod
    def validate_direction(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_DIRECTIONS:
            raise ValueError(f"Недопустимый action.direction: {v}")
        return v

    @field_validator("modifier")
    @classmethod
    def validate_modifier(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_MODIFIERS:
            raise ValueError(f"Недопустимый action.modifier: {v}")
        return v

    @field_validator("resultingPose")
    @classmethod
    def validate_pose(cls, v: str) -> str:
        if v not in VALID_POSES:
            raise ValueError(f"Недопустимый resultingPose: {v}")
        return v

    @field_validator("target")
    @classmethod
    def validate_target_format(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not ID_RE.fullmatch(v):
            raise ValueError("SceneAction.target содержит недопустимые символы")
        return v

    @field_validator("holdingObject")
    @classmethod
    def validate_holding_object(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            if not v.startswith("object_"):
                raise ValueError("holdingObject должен ссылаться на object_*")
            if not ID_RE.fullmatch(v):
                raise ValueError("holdingObject содержит недопустимые символы")
        return v

    @model_validator(mode="after")
    def validate_action_semantics(self):
        if self.type == "talk":
            if not self.dialogue or not self.dialogue.strip():
                raise ValueError("talk требует непустое dialogue")
            if self.fallbackText is not None:
                raise ValueError("talk не должен содержать fallbackText")
        else:
            if self.dialogue is not None and not self.dialogue.strip():
                raise ValueError("dialogue не должно быть пустой строкой")

        if self.type == "described_action":
            if not self.fallbackText or not self.fallbackText.strip():
                raise ValueError("described_action требует fallbackText")
            if not self.sourceText or not self.sourceText.strip():
                raise ValueError("described_action требует sourceText")
            if self.dialogue is not None:
                raise ValueError("described_action не должен содержать dialogue")
            if not self.fallbackText.startswith("*") or not self.fallbackText.endswith("*"):
                raise ValueError("fallbackText должен быть в формате *...*")
        else:
            if self.sourceText is not None and not self.sourceText.strip():
                raise ValueError("sourceText не должно быть пустой строкой")

        if self.direction is not None and self.type not in {"walk", "run", "approach", "pass_by"}:
            raise ValueError(f"direction недопустим для action.type={self.type}")

        if self.modifier is not None and self.type not in {"walk", "run", "approach", "pass_by", "described_action"}:
            raise ValueError(f"modifier недопустим для action.type={self.type}")

        if self.type in {"look_at", "pick_up", "open", "close", "approach"} and not self.target:
            raise ValueError(f"{self.type} требует target")

        if self.type == "give":
            if not self.target or not self.target.startswith("actor_"):
                raise ValueError("give требует target=actor_*")

        return self


class SceneBeat(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    actions: list[SceneAction]
    camera: Optional[CameraSetup] = None
    minDuration: Optional[float] = None

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not v.startswith("beat_"):
            raise ValueError("SceneBeat.id должен начинаться с beat_")
        if not ID_RE.fullmatch(v):
            raise ValueError("SceneBeat.id содержит недопустимые символы")
        return v

    @field_validator("actions")
    @classmethod
    def validate_actions(cls, v: list[SceneAction]) -> list[SceneAction]:
        if not v:
            raise ValueError("SceneBeat.actions не может быть пустым")
        return v

    @field_validator("minDuration")
    @classmethod
    def validate_min_duration(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and v < 0:
            raise ValueError("minDuration не может быть отрицательным")
        return v


class SpatialRelation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    subject: str
    relation: str
    object: str

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not v.startswith("rel_"):
            raise ValueError("SpatialRelation.id должен начинаться с rel_")
        if not ID_RE.fullmatch(v):
            raise ValueError("SpatialRelation.id содержит недопустимые символы")
        return v

    @field_validator("subject", "object")
    @classmethod
    def validate_ref(cls, v: str) -> str:
        if not ID_RE.fullmatch(v):
            raise ValueError("SpatialRelation содержит недопустимые id")
        return v

    @field_validator("relation")
    @classmethod
    def validate_relation(cls, v: str) -> str:
        if v not in VALID_RELATION_TYPES:
            raise ValueError(f"Недопустимый relation: {v}")
        return v


class SceneScript(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sceneHeading: Optional[str] = None
    locationName: Optional[str] = None
    interiorExterior: Optional[str] = None
    timeOfDay: Optional[str] = None
    actors: list[SceneActor]
    objects: list[SceneObject]
    beats: list[SceneBeat]
    spatialRelations: list[SpatialRelation]
    originalDescription: str

    @field_validator("interiorExterior")
    @classmethod
    def validate_ie(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_INTERIOR_EXTERIOR:
            raise ValueError(f"Недопустимый interiorExterior: {v}")
        return v

    @field_validator("actors")
    @classmethod
    def validate_actors(cls, v: list[SceneActor]) -> list[SceneActor]:
        if not v:
            raise ValueError("Должен быть хотя бы один actor")
        return v

    @field_validator("beats")
    @classmethod
    def validate_beats(cls, v: list[SceneBeat]) -> list[SceneBeat]:
        if not v:
            raise ValueError("Должен быть хотя бы один beat")
        return v

    @field_validator("originalDescription")
    @classmethod
    def validate_original_description(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("originalDescription не может быть пустым")
        return v.strip()

    @model_validator(mode="after")
    def validate_scene_limits(self):
        if len(self.actors) > 6:
            raise ValueError("Слишком много actors: максимум 6")
        if len(self.objects) > 8:
            raise ValueError("Слишком много objects: максимум 8")
        return self


# ─────────────────────────────
# Промпты
# ─────────────────────────────

SYSTEM_PROMPT_FOR_TRAINING = f"""Ты парсер мизансцен для кинопроизводства. Преобразуй чанк русского сценария в валидный JSON SceneScript.

Пользователь присылает ЧАНК — короткий contiguous-фрагмент одной сцены.
Это НЕ полная сцена, а кусок уже идущего эпизода. Он может быть:
- серединой разговора
- коротким фрагментом действий и перемещений
- диалогом с минимальными ремарками
- одним или несколькими соседними битами

Чанк обычно содержит 2-5 строк/предложений:
- действия и перемещения персонажей
- реплики в формате ИМЯ: текст
- взаимодействия с объектами
- короткие реакции и микродействия

Локация, время суток и заголовок сцены НЕ входят в чанк — они определяются на уровне приложения.

SceneBeat — смысловой временной блок. В один beat объединяй действия, которые происходят одновременно или почти одновременно в одном моменте внимания камеры.
Если один персонаж говорит, а второй параллельно двигает предмет, разворачивается к двери или подаёт папку, это может быть один beat.
Если начинается следующая микрофаза внимания, создавай новый beat.

КРИТИЧЕСКИ ВАЖНО:
- лучше недоразметить, чем додумать лишнее
- не выдумывай экспозицию, расстановку, объекты, действия и отношения, которых нет в чанке
- если чанк состоит только из реплик, это нормально: создавай actors и talk-actions без лишних объектов
- если строка описывает одно сложное действие, не дроби её на 3-5 микродействий без явной необходимости
- если в тексте нет реплики, не создавай talk c "..." или "—"
- заполняй actor.name ТОЛЬКО если в чанке есть явное собственное имя персонажа или устойчивый speaker label-имя
- если персонаж в narration назван как "мужчина", "женщина", "врач", "медсестра", "посетитель", "сосед", "продавец", "парень", "девушка" и т.п., НЕ используй это как name; оставь name пустым
- если персонаж обозначен как "он", "она", "они", НЕ используй это как name; оставь name пустым
- создавай object только для явно наблюдаемого физического предмета, важного для действия
- НЕ создавай отдельные objects для абстрактных и служебных сущностей: приложение, вкладка, поле, кнопка, копия, очередь, подпись, карман, цифра, значение, маршрут, время прибытия
- spatialRelations добавляй только если связь явно и полезно выражена в тексте
- если действие важно, но не входит в разрешённые action.type, используй described_action

Выводи ТОЛЬКО валидный JSON, без пояснений.

Структура:
{{
  "actors": [
    {{"id":"actor_1","type":"human","name":"Анна"}},
    {{"id":"actor_2","type":"human","name":"Борис"}}
  ],
  "objects": [],
  "beats": [
    {{
      "id":"beat_1",
      "actions":[
        {{"id":"action_1","actorId":"actor_1","type":"talk","resultingPose":"standing","dialogue":"Я уже отправила письмо."}},
        {{"id":"action_2","actorId":"actor_2","type":"talk","resultingPose":"sitting","dialogue":"Тогда покажи вложение."}}
      ],
      "camera": {{"shotType":"two_shot","movement":"static","target":"actor_1"}}
    }}
  ],
  "spatialRelations": [],
  "originalDescription": "АННА: Я уже отправила письмо. БОРИС: Тогда покажи вложение."
}}

Пример с БЕЗЫМЯННЫМИ ролями:
source:
ВРАЧ: Анализы уже в системе.
МЕДСЕСТРА: Я распечатаю их после обхода.

корректно:
- actors можно создать без name
- talk.dialogue должны совпадать с source
- не нужно придумывать объекты и дополнительные действия

Строгие правила:
1. Разрешённые actor.type: {", ".join(sorted(VALID_ACTOR_TYPES))}
2. Разрешённые object.type: {", ".join(sorted(VALID_OBJECT_TYPES))}
3. Разрешённые action.type: {", ".join(sorted(VALID_ACTION_TYPES))}
4. Разрешённые resultingPose: {", ".join(sorted(VALID_POSES))}
5. Разрешённые direction: {", ".join(sorted(VALID_DIRECTIONS))}
6. Разрешённые modifier: {", ".join(sorted(VALID_MODIFIERS))}
7. Разрешённые camera.shotType: {", ".join(sorted(VALID_SHOT_TYPES))}
8. Разрешённые camera.movement: {", ".join(sorted(VALID_CAMERA_MOVEMENTS))}
9. Разрешённые relativePosition: {", ".join(sorted(VALID_RELATIVE_POSITIONS))}
10. Разрешённые spatialRelations.relation: {", ".join(sorted(VALID_RELATION_TYPES))}
11. У каждого action ОБЯЗАТЕЛЬНО есть id, actorId, type, resultingPose.
12. У каждого object ОБЯЗАТЕЛЬНО есть relativePosition.
13. originalDescription ОБЯЗАТЕЛЬНО.
14. Если type=talk, обязательно dialogue. НЕ добавлять fallbackText/sourceText к talk.
15. Если действие важно, но не входит в разрешённые action.type, используй described_action с fallbackText (*...*) и sourceText.
16. НЕ добавляй sceneHeading, locationName, interiorExterior, timeOfDay — они не нужны для чанка.
17. Если имя персонажа "Лев", это НЕ лев-животное. Для обычного персонажа используй actor.type="human".
18. Не добавляй никаких лишних полей.
"""

GENERATION_SYSTEM_PROMPT = f"""Ты генератор обучающих данных для fine-tuning LLM-парсера чанков сцен.

Для входного ЧАНКА сгенерируй ВАЛИДНЫЙ JSON SceneScript, строго по схеме.
Чанк — это contiguous-фрагмент уже идущей сцены, а не полная мини-сцена.
Начинай ответ с {{ и заканчивай }}.

ВАЖНО:
- НЕ добавляй sceneHeading, locationName, interiorExterior, timeOfDay
- НЕ придумывай расстановку персонажей, если её нет в тексте
- НЕ придумывай новые реплики, новые действия, новые объекты и новые пространственные связи
- если чанк почти целиком диалоговый, это нормально: делай talk-действия и минимальную структуру
- beats должны отражать смысловые микрофазы внутри чанка, а не каждый глагол отдельно
- если строка описывает одно сложное действие, предпочитай один described_action или 1-2 действия максимум, а НЕ цепочку из 4-5 микродействий
- если в source нет слов персонажа, не создавай talk с "..." или "—"
- actor.name заполняй только собственным именем персонажа из source
- если в narration встречаются слова вроде "мужчина", "женщина", "врач", "медсестра", "посетитель", "сосед", "продавец", "парень", "девушка", НЕ используй их как actor.name по умолчанию
- если speaker обозначен как ОН/ОНА/Он/Она, НЕ записывай это в name; оставь name пустым
- если speaker label в реплике не является собственным именем, name тоже можно оставить пустым
- не создавай отдельные objects для абстрактных/UI сущностей: приложение, вкладка, поле, кнопка, карман, очередь, цифра, значение, копия, подпись, индикатор, маршрут, время прибытия
- если сомневаешься между "создать object" и "не создавать object", выбирай более простой вариант
- spatialRelations добавляй только если связь явно выражена в тексте и реально помогает сцене
- prefer under-parsing over over-parsing

=== ПРИМЕР 1: ДИАЛОГОВЫЙ ЧАНК ===
{{
  "actors": [
    {{"id":"actor_1","type":"human","name":"Анна"}},
    {{"id":"actor_2","type":"human","name":"Борис"}}
  ],
  "objects": [],
  "beats": [
    {{
      "id":"beat_1",
      "actions":[
        {{"id":"action_1","actorId":"actor_1","type":"talk","resultingPose":"standing","dialogue":"Я уже отправила письмо."}},
        {{"id":"action_2","actorId":"actor_2","type":"talk","resultingPose":"sitting","dialogue":"Тогда покажи вложение."}}
      ],
      "camera":{{"shotType":"two_shot","movement":"static","target":"actor_1"}}
    }}
  ],
  "spatialRelations": [],
  "originalDescription": "АННА: Я уже отправила письмо. БОРИС: Тогда покажи вложение."
}}

=== ПРИМЕР 2: ДИАЛОГ БЕЗ СОБСТВЕННЫХ ИМЁН ===
source:
ВРАЧ: Анализы уже в системе.
МЕДСЕСТРА: Я распечатаю их после обхода.

корректная идея:
- actors можно создать с пустым name
- objects: []
- talk.dialogue должны совпасть с source
- не нужно придумывать стол, папку, монитор, кнопку или дополнительные действия

=== ПРИМЕР 3: MID-SCENE CHUNK С ДЕЙСТВИЕМ ===
{{
  "actors": [
    {{"id":"actor_1","type":"human","name":"Анна"}},
    {{"id":"actor_2","type":"human","name":"Борис"}}
  ],
  "objects": [
    {{"id":"object_1","type":"table","name":"стол","detectedPosition":null,"relativePosition":"center"}},
    {{"id":"object_2","type":"generic","name":"папка","detectedPosition":null,"relativePosition":"center"}}
  ],
  "beats": [
    {{
      "id":"beat_1",
      "actions":[
        {{"id":"action_1","actorId":"actor_1","type":"put_down","target":"object_1","resultingPose":"standing","holdingObject":"object_2"}},
        {{"id":"action_2","actorId":"actor_2","type":"talk","resultingPose":"sitting","dialogue":"Покажи страницу с итогами."}}
      ],
      "camera":{{"shotType":"medium","movement":"static","target":"actor_1"}}
    }},
    {{
      "id":"beat_2",
      "actions":[
        {{"id":"action_3","actorId":"actor_1","type":"open","target":"object_2","resultingPose":"standing"}},
        {{"id":"action_4","actorId":"actor_1","type":"talk","resultingPose":"standing","dialogue":"Вот, я отметила цифру ручкой."}}
      ],
      "camera":{{"shotType":"over_shoulder","movement":"static","target":"actor_2"}}
    }}
  ],
  "spatialRelations": [
    {{"id":"rel_1","subject":"actor_1","relation":"near","object":"object_1"}},
    {{"id":"rel_2","subject":"object_2","relation":"near","object":"object_1"}}
  ],
  "originalDescription": "Анна кладёт папку на стол. БОРИС: Покажи страницу с итогами. Анна раскрывает папку. АННА: Вот, я отметила цифру ручкой."
}}

=== ПРАВИЛЬНОЕ УПРОЩЕНИЕ ===
Если source такой:
"Ольга открывает ноутбук и кликает по закладке."

НЕ надо создавать 4 объекта и 5 действий.
Лучше один из вариантов:
- object: ноутбук; action: open; второй action: described_action "*кликает по закладке*"
или
- object: ноутбук; один described_action по всей строке
Если не уверен, выбирай более простой вариант.

=== СТРОГИЕ ПРАВИЛА ===
- actor.type: {", ".join(sorted(VALID_ACTOR_TYPES))}
- object.type: {", ".join(sorted(VALID_OBJECT_TYPES))}
- action.type: {", ".join(sorted(VALID_ACTION_TYPES))}
- resultingPose: {", ".join(sorted(VALID_POSES))}
- direction: {", ".join(sorted(VALID_DIRECTIONS))}
- modifier: {", ".join(sorted(VALID_MODIFIERS))}
- camera.shotType: {", ".join(sorted(VALID_SHOT_TYPES))}
- camera.movement: {", ".join(sorted(VALID_CAMERA_MOVEMENTS))}
- relativePosition: {", ".join(sorted(VALID_RELATIVE_POSITIONS))}
ОБЯЗАТЕЛЬНЫЕ ПОЛЯ в каждом action:
- id (формат action_N)
- actorId (формат actor_N)
- type
- resultingPose

ЗАПРЕЩЕНО:
- использовать action.type вне списка
- использовать object.type вне списка (phone, key, bag, document -> generic, если не подходит ничего лучше)
- опускать resultingPose
- добавлять fallbackText/sourceText к talk
- добавлять dialogue к described_action
- опускать dialogue у talk
- опускать fallbackText/sourceText у described_action
- оборачивать JSON в {{"scene":...}}
- добавлять sceneHeading, locationName, interiorExterior, timeOfDay
- добавлять лишние поля
- создавать talk с "..." или "—"
- дублировать одну и ту же реплику дважды, если в source она одна
- создавать actors.name = "Он" / "Она" / "ОНИ"
- использовать actor.name = "Мужчина" / "Женщина" / "Посетитель" / "Сотрудница" / "Врач" / "Медсестра" по умолчанию, если в source нет явного собственного имени

ПРАВИЛА described_action:
- используй только если действие важно, но не входит в разрешённые action.type
- fallbackText в формате *действие*
- sourceText — исходный фрагмент
- если одна строка описывает сложное составное действие, described_action часто лучше, чем 3-5 микродействий

ПРАВИЛА talk:
- dialogue обязателен
- dialogue должен совпадать с репликой из source, а не быть выдуманным
- НЕ добавляй fallbackText и sourceText

ДРУГИЕ ПРАВИЛА:
- spatialRelations: [] если нет уверенных пространственных связей
- originalDescription обязателен
- direction и modifier разрешены ТОЛЬКО для walk, run, approach, pass_by
- для look_at, pick_up, open, close, approach обязателен target
"""

SOURCE_SCENE_SYSTEM_PROMPT = """Ты создаёшь НЕ короткий самодостаточный чанк, а более длинный непрерывный фрагмент одной сцены,
из которого потом приложение вырежет маленький contiguous-кусок.

Твоя задача: сгенерировать кусок одной сцены в стиле обычного российского сериала.
Это спокойная бытовая сцена: квартира, кухня, коридор, офис, лестничная площадка, регистратура, больничный коридор, магазин, двор.

Фрагмент должен выглядеть как часть уже идущего сценария:
- не нужно каждый раз заново объяснять, кто где стоит
- не нужно делать законченную мини-сцену с началом и финалом
- допустимы подряд идущие реплики без дополнительных ремарок
- допустимы микродействия между репликами
- допустимы куски, где 2-4 соседние строки — это просто продолжение разговора
- внутри фрагмента обязательно должны встречаться строки, которые ЗАВИСЯТ от предыдущего контекста и не выглядят как новый setup
- это НЕ драма и НЕ экшен по умолчанию

Строгие требования:
- 8-14 коротких строк
- каждая строка — либо одно наблюдаемое действие, либо одна реплика в формате ИМЯ: текст
- для реплик ПРЕДПОЧИТАЙ собственные имена как speaker labels: АННА:, БОРИС:, ЛЕРА:, ИГОРЬ:
- не используй speaker labels типа ОН:, ОНА:, МУЖЧИНА:, ЖЕНЩИНА:, ЧЕЛОВЕК:
- безымянные роли типа ВРАЧ:, МЕДСЕСТРА:, ПРОДАВЕЦ: допустимы редко и только когда это правда нужно по сцене
- НЕ добавляй заголовки сцен (ИНТ./ЭКСТ./INT./EXT.)
- НЕ добавляй описания атмосферы, света, музыки, внутренних состояний
- НЕ делай физическую агрессию, погром, швыряние вещей
- НЕ начинай фрагмент с чистой статичной экспозиции вроде "Анна сидит за столом"
- строки должны быть соседними внутри ОДНОЙ непрерывной сцены
- этот фрагмент потом будет нарезан на более короткие чанки 2-5 строк, поэтому внутри фрагмента должны встречаться:
  - обычные бытовые действия
  - куски уже идущего разговора
  - короткие переходы внимания
  - иногда почти диалоговый кусок без новых описаний
  - хотя бы 2 строки с continuation-feel, например: "Тогда смотри сюда.", "Нет, не этот лист.", "Подожди, я не про это.", "Я же тебе говорила."
- не завершай сцену явно: не подводи итог, не закрывай разговор финальной моралью, не делай ощущение законченного мини-сюжета
- не строй фрагмент как вопрос -> ответ -> решение -> конец; пусть разговор и действие продолжаются дальше за пределами видимого куска
- хотя бы один локальный микроэпизод внутри фрагмента должен тянуться ДАЛЬШЕ после предполагаемого вырезанного окна

Хорошо:
- Анна кладёт папку на стол.
- БОРИС: Я смотрел только первую страницу.
- Анна подвигает папку ближе к нему.
- БОРИС: Тогда открой письмо ещё раз.
- АННА: Нет, не этот лист.
- Борис перелистывает обратно.

Плохо:
- длинная экспозиция расстановки
- литературщина
- чрезмерная ссора
- полноценный завершённый сюжет за 8-14 строк
- ярлыки ОН:/ОНА:/МУЖЧИНА:/ЖЕНЩИНА:
"""


# ─────────────────────────────
# Категории сцен
# ─────────────────────────────

SCENE_CATEGORIES = [
    {
        "name": "kitchen_small_talk",
        "weight": 10,
        "dialogue_required": True,
        "prompts": [
            "Анна ставит чайник на стол и поворачивается к Борису. Разговор уже идёт, они обсуждают завтрак и кто куда опаздывает.",
            "Борис открывает холодильник, достаёт контейнер и показывает его Анне. Дальше идёт обычный бытовой обмен репликами.",
            "Женщина вытирает стол, кивает мужчине на кружки, он берёт одну и отвечает ей без пафоса.",
        ]
    },
    {
        "name": "hallway_entry",
        "weight": 9,
        "dialogue_required": True,
        "prompts": [
            "Борис ставит пакет у двери, окликает Анну из коридора, она отвечает из комнаты. Дальше сцена продолжается обычным домашним разговором.",
            "Анна снимает куртку у двери и протягивает Борису ключи. Они быстро обсуждают, кто пойдёт обратно.",
            "Парень придерживает дверь плечом, заглядывает в квартиру, девушка отвечает ему изнутри. Сцена уже идёт.",
        ]
    },
    {
        "name": "office_deskwork",
        "weight": 10,
        "dialogue_required": True,
        "prompts": [
            "Сотрудник кладёт папку на стол коллеги и указывает на нужную страницу. Между ними уже идёт рабочий разговор.",
            "Женщина листает распечатку, останавливается на одном месте и поворачивает документ к собеседнику. Разговор продолжается.",
            "Мужчина отодвигает ноутбук и просит коллегу ещё раз объяснить цифры. Затем они перебрасываются короткими репликами.",
        ]
    },
    {
        "name": "living_room_evening",
        "weight": 8,
        "dialogue_required": True,
        "prompts": [
            "Женщина убавляет звук телевизора и продолжает разговор с мужчиной на диване.",
            "Мужчина берёт пульт со стола, нажимает кнопку и поднимает взгляд на собеседницу. Их разговор уже идёт.",
            "Девушка складывает плед на кресло и спрашивает у парня, будет ли он чай. Потом разговор продолжается.",
        ]
    },
    {
        "name": "stairwell_meeting",
        "weight": 7,
        "dialogue_required": True,
        "prompts": [
            "Сосед останавливается на площадке, придерживая пакет, и окликает женщину у двери. Дальше короткий разговор между делом.",
            "Павел спускается на пару ступенек, оборачивается к соседке Лене и задаёт короткий вопрос. Это обычный проходной эпизод.",
            "Женщина достаёт ключи у двери, замечает соседа и отвечает через плечо. Разговор продолжается ещё несколькими репликами.",
        ]
    },
    {
        "name": "hospital_corridor_calm",
        "weight": 7,
        "dialogue_required": True,
        "prompts": [
            "Врач выходит в коридор с картой пациента и останавливает медсестру коротким вопросом. Дальше рабочие реплики и движения продолжаются.",
            "Медсестра закрывает дверь палаты и передаёт врачу папку. Сцена продолжается спокойным рабочим обменом.",
            "Двое врачей идут по коридору, один листает бумаги на ходу и показывает второму нужную строку.",
        ]
    },
    {
        "name": "clinic_reception",
        "weight": 7,
        "dialogue_required": True,
        "prompts": [
            "Лена у стойки протягивает паспорт сотруднице регистратуры и задаёт уточняющий вопрос. Дальше несколько рабочих реплик.",
            "Сотрудница поворачивает монитор к посетителю и показывает время записи. Разговор продолжается.",
            "Посетитель кладёт талон на стойку, а сотрудница быстро сверяет его со списком. Обычная спокойная сцена.",
        ]
    },
    {
        "name": "apartment_packing_calm",
        "weight": 8,
        "dialogue_required": False,
        "prompts": [
            "Женщина складывает одежду в чемодан, закрывает крышку и тянется за зарядкой на тумбочке. Это середина обычных сборов.",
            "Человек берёт паспорт со стола, убирает его в рюкзак и проверяет молнию на внешнем кармане.",
            "Девушка собирает косметику с полки в сумку, оглядывает комнату и выключает свет у двери.",
        ]
    },
    {
        "name": "courtyard_daily",
        "weight": 6,
        "dialogue_required": False,
        "prompts": [
            "Мужчина идёт к машине, проверяет карманы и останавливается у дверцы. Сцена продолжается ещё несколькими бытовыми действиями.",
            "Женщина выходит из подъезда с пакетом, замечает знакомого и замедляет шаг.",
            "Парень догоняет девушку во дворе, равняется с ней и показывает что-то на телефоне.",
        ]
    },
    {
        "name": "school_corridor_calm",
        "weight": 5,
        "dialogue_required": True,
        "prompts": [
            "Учитель выходит в коридор с журналом и подзывает двух учеников ближе. Дальше короткий спокойный разговор.",
            "Подросток убирает телефон в карман, пока одноклассник что-то быстро ему объясняет.",
            "Третий школьник подходит к двум у окна и задаёт вопрос. Разговор продолжается.",
        ]
    },
    {
        "name": "store_checkout_calm",
        "weight": 6,
        "dialogue_required": True,
        "prompts": [
            "Покупательница выкладывает товары на ленту и уточняет у продавца цену на один из них. Потом идут обычные короткие реплики.",
            "Продавец пододвигает пакет к покупателю и показывает на терминал.",
            "Мужчина подходит к кассе с одной упаковкой и спрашивает, принимает ли магазин карту.",
        ]
    },
    {
        "name": "bus_stop_daily",
        "weight": 5,
        "dialogue_required": True,
        "prompts": [
            "Игорь подходит к расписанию на остановке и спрашивает у Леры рядом, давно ли она ждёт автобус.",
            "Лера поправляет сумку на плече и показывает Игорю номер маршрута на табличке.",
            "Парень смотрит в телефон и зачитывает время прибытия, женщина отвечает ему короткой репликой.",
        ]
    },
    {
        "name": "unsupported_behavior_scene",
        "weight": 2,
        "dialogue_required": True,
        "prompts": [
            "Женщина коротко улыбается, посылает мужчине воздушный поцелуй и идёт к двери. Он удивлённо смотрит ей вслед и отвечает.",
            "Парень кивает на прощание, машет рукой и скрывается за углом. Девушка отвечает тем же и говорит ему пару слов.",
            "Мужчина прикладывает палец к губам, призывая к тишине. Второй послушно замирает и отвечает шёпотом.",
        ]
    },
]


# ─────────────────────────────
# Утилиты
# ─────────────────────────────

def compact_json(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def content_hash(text: str) -> str:
    return hashlib.md5(normalize_text(text).lower().encode("utf-8")).hexdigest()


def strip_code_fences(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith("```json"):
        raw = raw[7:]
    elif raw.startswith("```"):
        raw = raw[3:]
    if raw.endswith("```"):
        raw = raw[:-3]
    return raw.strip()


def extract_json_object(raw: str) -> str:
    raw = strip_code_fences(raw)
    start_idx = raw.find("{")
    end_idx = raw.rfind("}")
    if start_idx == -1 or end_idx == -1 or end_idx <= start_idx:
        raise ValueError("Не удалось извлечь JSON-объект из ответа модели")
    return raw[start_idx:end_idx + 1]


def choose_weighted(items: list[dict]) -> dict:
    weighted: list[dict] = []
    for item in items:
        weighted.extend([item] * item["weight"])
    return random.choice(weighted)


def record_reject(reason: str, text: str, raw_response: str | None = None, parsed: dict | None = None):
    payload = {
        "reason": reason,
        "text": text,
        "raw_response": raw_response,
        "parsed": parsed,
    }
    with open(REJECTED_FILE, "a", encoding="utf-8") as f:
        f.write(compact_json(payload) + "\n")


def count_hits(text: str, terms: list[str]) -> int:
    low = text.lower()
    return sum(1 for t in terms if t in low)


def split_into_units(text: str) -> list[str]:
    text = normalize_text(text)
    if "\n" in text:
        units = [line.strip() for line in text.split("\n") if line.strip()]
        if len(units) >= 2:
            return units

    parts = re.split(r"(?<=[.!?…])\s+", text)
    return [p.strip() for p in parts if p.strip()]


def join_units(units: list[str]) -> str:
    if not units:
        return ""
    if any(DIALOGUE_LINE_RE.match(u) for u in units):
        return "\n".join(units)
    return " ".join(units)


def is_dialogue_unit(unit: str) -> bool:
    return bool(DIALOGUE_LINE_RE.match(unit.strip()))


def normalize_actor_name(name: str | None) -> str | None:
    if name is None:
        return None
    value = normalize_text(str(name)).strip()
    if not value:
        return None
    value = value.replace("Ё", "Е").replace("ё", "е")
    return value


def is_pronoun_actor_name(name: str | None) -> bool:
    value = normalize_actor_name(name)
    if value is None:
        return False
    return value.lower() in PRONOUN_ACTOR_NAMES


def normalize_dialogue_text(text: str | None) -> str:
    if text is None:
        return ""
    value = normalize_text(str(text))
    value = value.replace("«", '"').replace("»", '"').replace("—", "-").replace("–", "-")
    value = re.sub(r"\s+", " ", value).strip(" \"'-.!?…,:;")
    return value.lower()


def extract_source_dialogue_texts(description: str) -> list[str]:
    texts: list[str] = []
    for unit in split_into_units(description):
        if is_dialogue_unit(unit):
            _, dialogue = unit.split(":", 1)
            norm = normalize_dialogue_text(dialogue)
            if norm:
                texts.append(norm)
    return texts


def object_name_is_too_abstract(name: str | None) -> bool:
    if not name:
        return False
    low = normalize_text(name).lower()
    return any(term in low for term in ABSTRACT_OBJECT_TERMS)


def has_static_start(unit: str) -> bool:
    return any(re.search(pattern, unit) for pattern in STATIC_START_PATTERNS)


def static_dynamic_scores(units: list[str]) -> tuple[int, int]:
    head = " ".join(units[:2]).lower()
    static_score = sum(head.count(v) for v in STATIC_VERBS)
    dynamic_score = sum(head.count(v) for v in ACTION_LIGHT_VERBS)
    return static_score, dynamic_score


def count_marker_hits(text: str, markers: list[str]) -> int:
    low = normalize_text(text).lower()
    return sum(1 for marker in markers if marker in low)


def source_matches_category_grounding(text: str, category_name: str) -> tuple[bool, dict]:
    grounding = CATEGORY_GROUNDING.get(category_name, {})
    prefer = grounding.get("prefer", [])
    avoid = grounding.get("avoid", [])
    low = normalize_text(text).lower()

    prefer_hits = sum(1 for term in prefer if term in low)
    avoid_hits = sum(1 for term in avoid if term in low)

    info = {
        "prefer_hits": prefer_hits,
        "avoid_hits": avoid_hits,
    }

    if avoid_hits >= 2 and prefer_hits == 0:
        return False, info
    return True, info


def evaluate_excerptness(candidate_units: list[str], start: int, length: int, total_units: int, profile: dict) -> tuple[bool, str, dict]:
    first = candidate_units[0] if candidate_units else ""
    last = candidate_units[-1] if candidate_units else ""
    context_before = start > 0
    context_after = (start + length) < total_units

    first_two_text = " ".join(candidate_units[:2])
    continuation_start_hits = count_marker_hits(first, CONTINUATION_START_MARKERS) + count_marker_hits(first_two_text, CONTINUATION_START_MARKERS)
    continuation_any_hits = count_marker_hits(" ".join(candidate_units), CONTINUATION_ANY_MARKERS)
    resolution_end_hits = count_marker_hits(last, RESOLUTION_END_MARKERS)

    info = {
        "context_before": context_before,
        "context_after": context_after,
        "continuation_start_hits": continuation_start_hits,
        "continuation_any_hits": continuation_any_hits,
        "resolution_end_hits": resolution_end_hits,
        "starts_with_dialogue": is_dialogue_unit(first),
        "start_index": start,
        "length": length,
        "total_units": total_units,
    }

    if profile.get("require_context_before") and not context_before:
        return False, "reject_edge_start", info
    if profile.get("require_context_after") and not context_after:
        return False, "reject_edge_end", info

    if profile.get("prefer_abrupt_start"):
        if not is_dialogue_unit(first) and continuation_start_hits == 0 and not context_before:
            return False, "reject_lacks_continuation_feel", info

    if not context_before and not context_after and continuation_any_hits == 0:
        return False, "reject_too_self_contained", info

    if resolution_end_hits >= 1 and not context_after and not profile.get("allow_local_resolution", False):
        return False, "reject_local_resolution", info

    return True, "ok", info


def record_chunk_debug(category_name: str, source_text: str, chunk_text: str, profile_name: str, start: int, length: int, total_units: int):
    payload = {
        "category": category_name,
        "profile": profile_name,
        "start_index": start,
        "length": length,
        "total_units": total_units,
        "source_fragment": source_text,
        "selected_chunk": chunk_text,
    }
    with open(DEBUG_SELECTION_FILE, "a", encoding="utf-8") as f:
        f.write(compact_json(payload) + "\n")


def classify_chunk_style(text: str) -> tuple[str, dict]:
    units = split_into_units(text)
    unit_count = len(units)
    dialogue_units = sum(1 for u in units if is_dialogue_unit(u))
    first_unit = units[0] if units else ""

    hard_drama = count_hits(text, HARD_DRAMA_TERMS)
    soft_drama = count_hits(text, SOFT_DRAMA_TERMS)
    atmosphere = count_hits(text, ATMOSPHERE_TERMS)
    calm_hits = count_hits(text, CALM_ACTION_HINTS)
    meta_hits = count_hits(text, META_LEAK_TERMS)
    completion_hits = count_hits(text, SCENE_COMPLETION_TERMS)
    static_start = bool(first_unit) and not is_dialogue_unit(first_unit) and has_static_start(first_unit)
    static_score, dynamic_score = static_dynamic_scores(units)

    info = {
        "unit_count": unit_count,
        "dialogue_units": dialogue_units,
        "static_start": static_start,
        "static_score": static_score,
        "dynamic_score": dynamic_score,
        "hard_drama": hard_drama,
        "soft_drama": soft_drama,
        "atmosphere": atmosphere,
        "calm_hits": calm_hits,
        "meta_hits": meta_hits,
        "completion_hits": completion_hits,
        "starts_with_dialogue": bool(first_unit) and is_dialogue_unit(first_unit),
    }

    if unit_count < CHUNK_MIN_UNITS or unit_count > CHUNK_MAX_UNITS:
        return "reject_bad_length", info
    if meta_hits >= 1:
        return "reject_meta", info
    if hard_drama >= 1:
        return "reject_hard_drama", info
    if atmosphere >= 1:
        return "reject_atmosphere", info
    if soft_drama >= 2:
        return "reject_overdramatic", info
    if soft_drama >= 1 and calm_hits == 0 and dialogue_units == 0:
        return "reject_overdramatic", info
    if static_start:
        return "reject_static_start", info
    if static_score >= 2 and dynamic_score == 0 and dialogue_units == 0:
        return "reject_static_heavy", info
    if completion_hits >= 2:
        return "reject_too_complete", info
    return "ok", info


def passes_chunk_filter(text: str, category: dict, profile: dict) -> tuple[bool, str, dict]:
    label, info = classify_chunk_style(text)
    if label != "ok":
        return False, label, info

    units = split_into_units(text)
    dialogue_units = sum(1 for u in units if is_dialogue_unit(u))
    non_dialogue_units = len(units) - dialogue_units

    if category["dialogue_required"] and dialogue_units < max(1, profile["min_dialogue_units"]):
        return False, "reject_missing_dialogue", info

    if not category["dialogue_required"] and dialogue_units > 1:
        return False, "reject_unwanted_dialogue", info

    if profile["need_dialogue"] and dialogue_units < profile["min_dialogue_units"]:
        return False, "reject_profile_dialogue_mismatch", info

    if dialogue_units > profile["max_dialogue_units"]:
        return False, "reject_too_much_dialogue_for_profile", info

    if profile["prefer_start_dialogue"] and not is_dialogue_unit(units[0]):
        return False, "reject_profile_start_mismatch", info

    if not profile["allow_dialogue_only"] and dialogue_units == len(units) and len(units) >= 2:
        return False, "reject_dialogue_only_for_profile", info

    if not category["dialogue_required"] and dialogue_units == 0 and non_dialogue_units >= 2:
        return True, "ok", info

    return True, "ok", info


def iter_json_objects_from_file(path: str) -> Iterator[dict]:
    decoder = json.JSONDecoder()
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            raw = line.strip()
            if not raw:
                continue
            try:
                yield json.loads(raw)
                continue
            except json.JSONDecodeError:
                pass

            idx = 0
            while idx < len(raw):
                tail = raw[idx:].lstrip()
                if not tail:
                    break
                obj, end = decoder.raw_decode(tail)
                consumed = len(raw[idx:]) - len(tail) + end
                yield obj
                idx += consumed


# ─────────────────────────────
# Семантическая валидация
# ─────────────────────────────

def validate_scene_semantics(script: SceneScript) -> list[str]:
    errors: list[str] = []

    actor_ids = [a.id for a in script.actors]
    object_ids = [o.id for o in script.objects]
    beat_ids = [b.id for b in script.beats]
    rel_ids = [r.id for r in script.spatialRelations]
    action_ids: list[str] = []

    if len(actor_ids) != len(set(actor_ids)):
        errors.append("Повторяющиеся actor.id")
    if len(object_ids) != len(set(object_ids)):
        errors.append("Повторяющиеся object.id")
    if len(beat_ids) != len(set(beat_ids)):
        errors.append("Повторяющиеся beat.id")
    if len(rel_ids) != len(set(rel_ids)):
        errors.append("Повторяющиеся spatialRelation.id")

    valid_targets = set(actor_ids) | set(object_ids)
    current_holding: dict[str, Optional[str]] = {aid: None for aid in actor_ids}

    for beat in script.beats:
        if beat.camera and beat.camera.target and beat.camera.target not in valid_targets:
            errors.append(f"{beat.id}: camera.target {beat.camera.target} не найден")

        for action in beat.actions:
            action_ids.append(action.id)

            if action.actorId not in actor_ids:
                errors.append(f"{beat.id}: actorId {action.actorId} не найден")

            if action.target and action.target not in valid_targets:
                errors.append(f"{beat.id}: target {action.target} не найден")

            if action.holdingObject and action.holdingObject not in object_ids:
                errors.append(f"{beat.id}: holdingObject {action.holdingObject} не найден")

            if action.type == "pick_up":
                if not action.target or action.target not in object_ids:
                    errors.append(f"{beat.id}: pick_up должен ссылаться на object_* через target")
                else:
                    if action.holdingObject != action.target:
                        errors.append(f"{beat.id}: pick_up требует holdingObject == target")
                    current_holding[action.actorId] = action.target
                continue

            if action.type in {"put_down", "give"}:
                expected = current_holding.get(action.actorId)
                if expected is None:
                    errors.append(f"{beat.id}: {action.actorId} делает {action.type}, ничего не держа")
                else:
                    if action.holdingObject != expected:
                        errors.append(f"{beat.id}: перед {action.type} actor должен держать {expected}")
                current_holding[action.actorId] = None
                continue

            expected = current_holding.get(action.actorId)
            if expected is None:
                if action.holdingObject is not None:
                    current_holding[action.actorId] = action.holdingObject
            else:
                if action.holdingObject != expected:
                    errors.append(f"{beat.id}: actor {action.actorId} потерял holdingObject {expected} в действии {action.type}")

            if action.type == "described_action":
                if action.dialogue is not None:
                    errors.append(f"{beat.id}: described_action не должен содержать dialogue")
                if not action.fallbackText:
                    errors.append(f"{beat.id}: described_action без fallbackText")
                if not action.sourceText:
                    errors.append(f"{beat.id}: described_action без sourceText")

    if len(action_ids) != len(set(action_ids)):
        errors.append("Повторяющиеся action.id")

    for rel in script.spatialRelations:
        if rel.subject not in valid_targets:
            errors.append(f"{rel.id}: subject {rel.subject} не найден")
        if rel.object not in valid_targets:
            errors.append(f"{rel.id}: object {rel.object} не найден")

    return errors


def validate_scene_dict(scene_dict: dict) -> list[str]:
    try:
        script = SceneScript(**scene_dict)
    except ValidationError as e:
        out: list[str] = []
        for err in e.errors():
            loc = " -> ".join(str(x) for x in err.get("loc", []))
            msg = err.get("msg", "Validation error")
            out.append(f"{loc}: {msg}")
        return out

    return validate_scene_semantics(script)


def validate_alignment_with_description(scene_dict: dict, description: str) -> list[str]:
    errors: list[str] = []

    units = split_into_units(description)
    source_dialogues = extract_source_dialogue_texts(description)
    source_dialogue_counter: dict[str, int] = {}
    for d in source_dialogues:
        source_dialogue_counter[d] = source_dialogue_counter.get(d, 0) + 1

    actors = scene_dict.get("actors", [])
    objects = scene_dict.get("objects", [])
    beats = scene_dict.get("beats", [])
    actions = [a for b in beats if isinstance(b, dict) for a in b.get("actions", []) if isinstance(a, dict)]
    talk_actions = [a for a in actions if a.get("type") == "talk"]

    if len(objects) > MAX_REASONABLE_OBJECTS_PER_CHUNK:
        errors.append(f"Слишком много objects для короткого чанка: {len(objects)}")

    if len(actions) > len(units) * 2 + 1:
        errors.append(f"Переизбыточное число actions относительно source: units={len(units)} actions={len(actions)}")

    if len(beats) > min(4, len(units)):
        errors.append(f"Слишком много beats относительно source: units={len(units)} beats={len(beats)}")

    if len(units) <= 2 and len(actions) >= 5:
        errors.append("Для очень короткого чанка actions слишком раздроблены")

    if len(units) == len(source_dialogues):
        non_talk_actions = [a for a in actions if a.get("type") != "talk"]
        if non_talk_actions:
            errors.append("Почти чисто диалоговый chunk не должен содержать лишние non-talk actions")
        if objects:
            errors.append("Почти чисто диалоговый chunk не должен содержать objects")

    for actor in actors:
        if not isinstance(actor, dict):
            continue
        name = actor.get("name")
        if is_pronoun_actor_name(name):
            errors.append(f"Недопустимое actor.name из местоимения: {name}")

    for obj in objects:
        if not isinstance(obj, dict):
            continue
        obj_name = obj.get("name")
        if object_name_is_too_abstract(obj_name):
            errors.append(f"Слишком абстрактный object.name: {obj_name}")

    placeholder_norms = {normalize_dialogue_text(x) for x in PLACEHOLDER_DIALOGUES}
    seen_talk_counter: dict[str, int] = {}
    for action in talk_actions:
        raw_dialogue = action.get("dialogue")
        norm_dialogue = normalize_dialogue_text(raw_dialogue)

        if not norm_dialogue:
            errors.append("talk без нормальной dialogue")
            continue

        if raw_dialogue in PLACEHOLDER_DIALOGUES or norm_dialogue in placeholder_norms:
            errors.append(f"talk содержит placeholder dialogue: {raw_dialogue}")
            continue

        if raw_dialogue and str(raw_dialogue).startswith("({"):
            errors.append(f"talk содержит служебный placeholder: {raw_dialogue}")
            continue

        matched = False
        for src in source_dialogues:
            if norm_dialogue == src or norm_dialogue in src or src in norm_dialogue:
                matched = True
                break
        if not matched:
            errors.append(f"talk dialogue не найдено в source: {raw_dialogue}")

        seen_talk_counter[norm_dialogue] = seen_talk_counter.get(norm_dialogue, 0) + 1

    if source_dialogues:
        for dlg, count in seen_talk_counter.items():
            src_count = source_dialogue_counter.get(dlg, 0)
            if src_count == 0:
                continue
            if count > src_count:
                errors.append(f"Реплика продублирована лишний раз: {dlg}")

    micro_count = sum(1 for a in actions if a.get("type") in MICRO_ACTION_TYPES)
    if micro_count >= max(3, len(units)) and len(talk_actions) < len(units):
        errors.append("Слишком много микродействий look_at/turn/stand/stop")

    return errors


# ─────────────────────────────
# Генерация исходного непрерывного фрагмента и извлечение чанка
# ─────────────────────────────

def _build_source_scene_user_prompt(category: dict, seed_prompt: str, mode: dict) -> str:
    grounding = CATEGORY_GROUNDING.get(category["name"], {})
    prefer_terms = grounding.get("prefer", [])
    avoid_terms = grounding.get("avoid", [])

    lines = [
        f'Создай один непрерывный фрагмент одной сцены, вдохновлённый этим примером, но НЕ копируй дословно: "{seed_prompt}"',
        f"Фрагмент должен содержать {SOURCE_SCENE_MIN_UNITS}-{SOURCE_SCENE_MAX_UNITS} коротких строк.",
        "Каждая строка — либо одно наблюдаемое действие, либо одна реплика в формате ИМЯ: текст.",
        "Это НЕ полная мини-сцена, а кусок уже идущего эпизода.",
        "Не нужно повторно объяснять локацию и расстановку персонажей в каждой строке.",
        "Фрагмент должен быть бытовым, реалистичным, сухим и пригодным для нарезки на chunks 2-5 строк.",
        mode["instruction"],
        "Не начинай с чистой статичной экспозиции вида 'кто-то стоит/сидит'.",
        "Не делай физическую агрессию, разрушения, швыряние предметов, крики и мыльную истерику.",
        "Без заголовков сцен, без атмосферы, без метафор, без внутренних состояний.",
        "Максимум 1-4 персонажа и 0-4 важных объекта во всём фрагменте.",
        "Для прямой речи предпочитай собственные имена как теги говорящих: АННА:, БОРИС:, ЛЕРА:, ИГОРЬ:.",
        "Не используй теги говорящих ОН:, ОНА:, МУЖЧИНА:, ЖЕНЩИНА:, ЧЕЛОВЕК:.",
        "Не завершай сцену явно и не делай из фрагмента маленький законченный сюжет.",
        "Внутри фрагмента обязательно сделай хотя бы 2 строки с ощущением продолжения, а не нового setup.",
        "Примеры правильного continuation-feel: 'Тогда смотри сюда.', 'Нет, не этот лист.', 'Подожди, я не про это.', 'Я же тебе говорила.'",
        "Не своди фрагмент к схеме вопрос -> ответ -> решение -> конец. Пусть разговор и действие продолжаются дальше.",
    ]

    if prefer_terms:
        lines.append("Держись предметного и локационного контекста этой категории. Предпочтительные слова/объекты: " + ", ".join(prefer_terms) + ".")
    if avoid_terms:
        lines.append("Избегай дрейфа в чужую категорию. По возможности НЕ используй слова/объекты: " + ", ".join(avoid_terms) + ".")

    if category["dialogue_required"]:
        lines.append("Во фрагменте обязательно должны быть прямые реплики, и местами они могут идти подряд.")
    else:
        lines.append("Сделай фрагмент преимущественно без прямой речи.")

    lines.append("Выводи только строки фрагмента, по одной на строке, без нумерации и без пояснений.")
    return "\n".join(lines)


def generate_source_scene_fragment(client: OpenAI, category: dict) -> str:
    last_reject_reason = ""

    for _ in range(MAX_SOURCE_SCENE_ATTEMPTS_PER_SAMPLE):
        seed_prompt = random.choice(category["prompts"])
        mode = choose_weighted(SOURCE_FRAGMENT_MODES)

        user_prompt = _build_source_scene_user_prompt(category, seed_prompt, mode)
        if last_reject_reason:
            user_prompt += (
                "\n\nПредыдущий вариант был отклонён."
                f"\nПричина: {last_reject_reason}"
                "\nСгенерируй новый вариант спокойнее, естественнее и ближе к середине уже идущей сцены."
            )

        response = client.chat.completions.create(
            model=SOURCE_MODEL,
            messages=[
                {"role": "system", "content": SOURCE_SCENE_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
        )

        text = normalize_text(response.choices[0].message.content or "")
        units = split_into_units(text)

        if len(units) < SOURCE_SCENE_MIN_UNITS or len(units) > SOURCE_SCENE_MAX_UNITS:
            last_reject_reason = "bad_source_length"
            record_reject(last_reject_reason, text)
            continue

        if has_static_start(units[0]) and not is_dialogue_unit(units[0]):
            last_reject_reason = "bad_source_static_start"
            record_reject(last_reject_reason, text)
            continue

        if count_hits(text, HARD_DRAMA_TERMS) >= 1:
            last_reject_reason = "bad_source_hard_drama"
            record_reject(last_reject_reason, text)
            continue

        if count_hits(text, ATMOSPHERE_TERMS) >= 1:
            last_reject_reason = "bad_source_atmosphere"
            record_reject(last_reject_reason, text)
            continue

        if count_hits(text, META_LEAK_TERMS) >= 1:
            last_reject_reason = "bad_source_meta"
            record_reject(last_reject_reason, text)
            continue

        grounding_ok, grounding_info = source_matches_category_grounding(text, category["name"])
        if not grounding_ok:
            last_reject_reason = f"bad_source_grounding:{grounding_info}"
            record_reject(last_reject_reason, text)
            continue

        if category["dialogue_required"]:
            dialogue_units = sum(1 for u in units if is_dialogue_unit(u))
            if dialogue_units < 2:
                last_reject_reason = "bad_source_missing_dialogue"
                record_reject(last_reject_reason, text)
                continue

        continuation_like = count_marker_hits(" ".join(units), CONTINUATION_ANY_MARKERS)
        if continuation_like == 0:
            last_reject_reason = "bad_source_no_continuation_markers"
            record_reject(last_reject_reason, text)
            continue

        return text

    raise ValueError(f"Не удалось получить хороший source fragment после {MAX_SOURCE_SCENE_ATTEMPTS_PER_SAMPLE} попыток")


def candidate_start_indices(num_units: int, prefer_middle: bool) -> list[int]:
    idxs = list(range(num_units))
    if not prefer_middle or num_units <= 4:
        random.shuffle(idxs)
        return idxs

    center = (num_units - 1) / 2
    weighted = sorted(idxs, key=lambda x: abs(x - center) + (0.8 if x == 0 else 0.0))
    top = weighted[: max(3, len(weighted) // 2)]
    rest = weighted[max(3, len(weighted) // 2):]
    random.shuffle(top)
    random.shuffle(rest)
    return top + rest


def try_extract_chunk_from_source(source_text: str, category: dict) -> tuple[Optional[str], str]:
    units = split_into_units(source_text)
    if len(units) < CHUNK_MIN_UNITS:
        return None, "source_too_short"

    last_reason = "no_candidate"

    for _ in range(MAX_CHUNK_EXTRACTION_ATTEMPTS_PER_SOURCE):
        profile = choose_weighted(CHUNK_PROFILES)
        starts = candidate_start_indices(len(units), profile["prefer_middle"])

        found_any_for_profile = False
        for start in starts:
            max_len = min(CHUNK_MAX_UNITS, len(units) - start)
            if max_len < CHUNK_MIN_UNITS:
                continue

            lengths = list(range(CHUNK_MIN_UNITS, max_len + 1))
            if profile["name"] in {"dialogue_continuation", "abrupt_dialogue_middle"}:
                lengths.sort(reverse=True)
            else:
                random.shuffle(lengths)

            for length in lengths:
                candidate_units = units[start:start + length]
                candidate_text = join_units(candidate_units)

                ok, label, _info = passes_chunk_filter(candidate_text, category, profile)
                if not ok:
                    found_any_for_profile = True
                    last_reason = label
                    continue

                excerpt_ok, excerpt_label, excerpt_info = evaluate_excerptness(
                    candidate_units=candidate_units,
                    start=start,
                    length=length,
                    total_units=len(units),
                    profile=profile,
                )
                if not excerpt_ok:
                    found_any_for_profile = True
                    last_reason = excerpt_label
                    continue

                record_chunk_debug(
                    category_name=category["name"],
                    source_text=source_text,
                    chunk_text=candidate_text,
                    profile_name=profile["name"],
                    start=start,
                    length=length,
                    total_units=len(units),
                )
                return candidate_text, "ok"

        if not found_any_for_profile:
            last_reason = "no_window_for_profile"

    return None, last_reason


def generate_scene_description(client: OpenAI, category: dict) -> str:
    last_reason = ""

    for _ in range(MAX_SOURCE_SCENE_ATTEMPTS_PER_SAMPLE):
        source_text = generate_source_scene_fragment(client, category)
        chunk_text, reason = try_extract_chunk_from_source(source_text, category)
        if chunk_text:
            return normalize_text(chunk_text)
        last_reason = reason
        record_reject(f"chunk_extract_{reason}", source_text)

    raise ValueError(f"Не удалось получить хороший chunk из непрерывного фрагмента. Последняя причина: {last_reason}")


# ─────────────────────────────
# Автоисправление распространённых ошибок LLM
# ─────────────────────────────

def autofix_scene_dict(d: dict, description: str) -> dict:
    if "scene" in d and isinstance(d["scene"], dict) and "actors" not in d:
        inner = d.pop("scene")
        for k, v in d.items():
            if k not in inner:
                inner[k] = v
        d = inner

    if "actors" not in d and "beats" in d and isinstance(d["beats"], list):
        for beat in d["beats"]:
            if isinstance(beat, dict):
                if "actors" in beat and "actors" not in d:
                    d["actors"] = beat.pop("actors")
                if "objects" in beat and "objects" not in d:
                    d["objects"] = beat.pop("objects")
                if "spatialRelations" in beat:
                    if "spatialRelations" not in d:
                        d["spatialRelations"] = beat.pop("spatialRelations")
                    else:
                        beat.pop("spatialRelations", None)
                for extra_key in ["actors", "objects", "dialogue", "spatialRelations"]:
                    beat.pop(extra_key, None)

    d.pop("id", None)
    d.pop("title", None)
    d.pop("description", None)
    d.pop("sceneHeading", None)
    d.pop("locationName", None)
    d.pop("interiorExterior", None)
    d.pop("timeOfDay", None)

    d.setdefault("spatialRelations", [])
    d.setdefault("originalDescription", description)
    d.setdefault("actors", [])
    d.setdefault("objects", [])
    d.setdefault("beats", [])

    for obj in d.get("objects", []):
        if isinstance(obj, dict):
            obj.setdefault("relativePosition", "unknown")
            if obj.get("type") not in VALID_OBJECT_TYPES:
                obj["type"] = "generic"

    for actor in d.get("actors", []):
        if isinstance(actor, dict):
            if actor.get("type") not in VALID_ACTOR_TYPES:
                actor["type"] = "human"
            if is_pronoun_actor_name(actor.get("name")):
                actor.pop("name", None)

    _ACTION_TYPE_MAP = {
        "hold": "described_action",
        "grab": "pick_up",
        "take": "pick_up",
        "drop": "put_down",
        "place": "put_down",
        "move": "walk",
        "sprint": "run",
        "speak": "talk",
        "say": "talk",
        "shout": "talk",
        "whisper": "talk",
        "gesture": "described_action",
        "wave": "described_action",
        "nod": "described_action",
        "shake": "described_action",
        "smile": "described_action",
        "kiss": "described_action",
        "hug": "described_action",
        "point": "described_action",
        "knock": "described_action",
        "push": "described_action",
        "pull": "described_action",
        "throw": "described_action",
        "catch": "described_action",
        "read": "described_action",
        "write": "described_action",
        "eat": "described_action",
        "drink": "described_action",
        "lean": "described_action",
        "wait": "stand",
        "pause": "stand",
        "freeze": "stand",
        "watch": "look_at",
        "stare": "look_at",
        "glance": "look_at",
        "enter_room": "enter",
        "leave": "exit",
        "leave_room": "exit",
        "sit_down": "sit",
        "stand_up": "stand",
        "get_up": "stand",
        "kneel": "crouch",
        "squat": "crouch",
    }

    _POSE_MAP = {
        "walk": "walking",
        "run": "running",
        "sit": "sitting",
        "stand": "standing",
        "crouch": "crouching",
        "lie_down": "lying",
    }

    for beat in d.get("beats", []):
        if not isinstance(beat, dict):
            continue
        for action in beat.get("actions", []):
            if not isinstance(action, dict):
                continue

            atype = action.get("type", "")

            if atype not in VALID_ACTION_TYPES:
                mapped = _ACTION_TYPE_MAP.get(atype, "described_action")
                if mapped == "described_action":
                    if not action.get("fallbackText"):
                        action["fallbackText"] = f"*{atype or 'действие'}*"
                    if not action.get("sourceText"):
                        action["sourceText"] = atype or "действие"
                action["type"] = mapped
                atype = mapped

            if "resultingPose" not in action or action["resultingPose"] not in VALID_POSES:
                action["resultingPose"] = _POSE_MAP.get(atype, "standing")

            if atype == "talk":
                action.pop("fallbackText", None)
                action.pop("sourceText", None)

            if atype == "described_action":
                action.pop("dialogue", None)
                if not action.get("fallbackText"):
                    action["fallbackText"] = "*действие*"
                if not action.get("sourceText"):
                    action["sourceText"] = action["fallbackText"].strip("* ")
                fb = action["fallbackText"]
                if not fb.startswith("*"):
                    fb = "*" + fb
                if not fb.endswith("*"):
                    fb = fb + "*"
                action["fallbackText"] = fb

            if action.get("direction") and action["direction"] not in VALID_DIRECTIONS:
                action.pop("direction", None)

            if action.get("modifier") and action["modifier"] not in VALID_MODIFIERS:
                action.pop("modifier", None)

            if action.get("direction") and atype not in {"walk", "run", "approach", "pass_by"}:
                action.pop("direction", None)
            if action.get("modifier") and atype not in {"walk", "run", "approach", "pass_by", "described_action"}:
                action.pop("modifier", None)

        cam = beat.get("camera")
        if isinstance(cam, dict):
            if cam.get("shotType") not in VALID_SHOT_TYPES:
                cam["shotType"] = "medium"
            if cam.get("movement") and cam["movement"] not in VALID_CAMERA_MOVEMENTS:
                cam.pop("movement", None)

        for extra_key in list(beat.keys()):
            if extra_key not in {"id", "actions", "camera", "minDuration"}:
                beat.pop(extra_key)

    current_holding: dict[str, str] = {}

    if "beats" in d and isinstance(d["beats"], list):
        for beat in d["beats"]:
            if not isinstance(beat, dict) or "actions" not in beat or not isinstance(beat["actions"], list):
                continue
            for a in beat["actions"]:
                if not isinstance(a, dict):
                    continue
                actor_id = a.get("actorId")
                if not actor_id:
                    continue

                if a.get("type") == "give":
                    target = a.get("target", "")
                    if target and not target.startswith("actor_"):
                        a["type"] = "put_down"

                act_type = a.get("type")
                if act_type == "pick_up":
                    target = a.get("target")
                    if target:
                        current_holding[actor_id] = target
                        a["holdingObject"] = target
                    continue

                if act_type in {"put_down", "give"}:
                    held = current_holding.get(actor_id)
                    if held:
                        a["holdingObject"] = held
                    current_holding.pop(actor_id, None)
                    continue

                held = current_holding.get(actor_id)
                if held:
                    a["holdingObject"] = held

    if "spatialRelations" in d and isinstance(d["spatialRelations"], list):
        for rel in d["spatialRelations"]:
            if not isinstance(rel, dict):
                continue
            r_val = rel.get("relation")
            if r_val == "in":
                rel["relation"] = "inside"
            elif r_val in {"on", "at", "by", "next_to"}:
                rel["relation"] = "near"

    return d


# ─────────────────────────────
# Генерация SceneScript JSON
# ─────────────────────────────

def generate_scene_script(client: OpenAI, description: str) -> Optional[dict]:
    last_error = ""

    for attempt in range(1, MAX_JSON_ATTEMPTS_PER_SAMPLE + 1):
        source_dialogues = extract_source_dialogue_texts(description)
        user_prompt = (
            "Описание сцены:\n"
            f"{description}\n\n"
            "Сгенерируй валидный JSON SceneScript. "
            "Начинай ответ строго с символа { и заканчивай символом }.\n"
            "Перед ответом проверь себя по чеклисту:\n"
            "- не выдумал ли ты новые реплики\n"
            "- нет ли talk с '...' или '—'\n"
            "- нет ли actor.name = Он/Она/Мужчина/Женщина/Посетитель/Сотрудница\n"
            "- не создал ли ты слишком много объектов\n"
            "- не создал ли ты абстрактные objects вроде приложения, вкладки, кармана, цифры, времени прибытия\n"
            "- не раздробил ли одну строку в 4-5 микродействий\n"
            "- dialogue в talk должны браться из source почти дословно\n"
            "- если нет явного собственного имени, лучше оставить actor.name пустым\n"
        )
        if source_dialogues:
            user_prompt += "Реплики из source:\n" + "\n".join(f"- {d}" for d in source_dialogues) + "\n"

        if last_error:
            user_prompt += (
                "\n\nПредыдущая попытка была отклонена по причинам:\n"
                f"{last_error}\n"
                "Сгенерируй корректный ответ заново. Не комментируй ошибки."
            )

        raw_response = None
        try:
            response = client.chat.completions.create(
                model=JSON_MODEL,
                messages=[
                    {"role": "system", "content": GENERATION_SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                ],
            )
            raw_response = response.choices[0].message.content or ""
            raw_response = raw_response.strip()

            raw_json = extract_json_object(raw_response)
            parsed = json.loads(raw_json)
            parsed = autofix_scene_dict(parsed, description)

            errors = validate_scene_dict(parsed)
            alignment_errors = validate_alignment_with_description(parsed, description)
            all_errors = errors + alignment_errors
            if all_errors:
                last_error = "; ".join(all_errors[:8])
                if attempt == MAX_JSON_ATTEMPTS_PER_SAMPLE:
                    record_reject(last_error, description, raw_response, parsed)
                continue

            return parsed

        except Exception as e:
            last_error = str(e)
            if attempt == MAX_JSON_ATTEMPTS_PER_SAMPLE:
                record_reject(last_error, description, raw_response, None)

    return None


# ─────────────────────────────
# Формат строки обучения
# ─────────────────────────────

def format_training_row(description: str, scene_json: dict) -> dict:
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_FOR_TRAINING},
            {"role": "user", "content": description},
            {"role": "assistant", "content": compact_json(scene_json)}
        ]
    }


# ─────────────────────────────
# Загрузка уже существующего датасета
# ─────────────────────────────

def load_existing_hashes(output_file: str) -> set[str]:
    hashes: set[str] = set()
    if not os.path.exists(output_file):
        return hashes

    for row in iter_json_objects_from_file(output_file):
        try:
            desc = row["messages"][1]["content"]
            hashes.add(content_hash(desc))
        except Exception:
            continue
    return hashes


def build_weighted_categories() -> list[dict]:
    weighted: list[dict] = []
    for cat in SCENE_CATEGORIES:
        weighted.extend([cat] * cat["weight"])
    return weighted


# ─────────────────────────────
# Фильтрация существующего датасета
# ─────────────────────────────

def filter_existing_dataset(
    input_path: str,
    output_path: str,
    review_path: str,
    keep_static_ratio: float = KEEP_STATIC_START_RATIO,
):
    seen_hashes: set[str] = set()

    counters = {
        "keep": 0,
        "keep_soft_static": 0,
        "drop_duplicate": 0,
        "drop_static_start": 0,
        "drop_static_heavy": 0,
        "drop_hard_drama": 0,
        "drop_atmosphere": 0,
        "drop_overdramatic": 0,
        "drop_bad_length": 0,
        "drop_meta": 0,
        "drop_too_complete": 0,
    }

    with open(output_path, "w", encoding="utf-8") as out_f, open(review_path, "w", encoding="utf-8") as review_f:
        for row in iter_json_objects_from_file(input_path):
            try:
                desc = normalize_text(row["messages"][1]["content"])
            except Exception:
                continue

            h = content_hash(desc)
            if h in seen_hashes:
                counters["drop_duplicate"] += 1
                continue
            seen_hashes.add(h)

            label, info = classify_chunk_style(desc)
            if label == "ok":
                try:
                    parsed = json.loads(row["messages"][2]["content"])
                    alignment_errors = validate_alignment_with_description(parsed, desc)
                except Exception:
                    alignment_errors = ["broken_assistant_json"]

                if not alignment_errors:
                    out_f.write(json.dumps(row, ensure_ascii=False) + "\n")
                    counters["keep"] += 1
                    continue

                review_f.write(json.dumps({
                    "label": "reject_alignment",
                    "description": desc,
                    "info": info,
                    "alignment_errors": alignment_errors,
                }, ensure_ascii=False) + "\n")
                counters["drop_overdramatic"] += 1
                continue

            if label == "reject_static_start":
                if random.random() < keep_static_ratio:
                    out_f.write(json.dumps(row, ensure_ascii=False) + "\n")
                    counters["keep_soft_static"] += 1
                else:
                    counters["drop_static_start"] += 1
                    review_f.write(json.dumps({
                        "label": label,
                        "description": desc,
                        "info": info,
                    }, ensure_ascii=False) + "\n")
                continue

            mapped_counter = {
                "reject_static_heavy": "drop_static_heavy",
                "reject_hard_drama": "drop_hard_drama",
                "reject_atmosphere": "drop_atmosphere",
                "reject_overdramatic": "drop_overdramatic",
                "reject_bad_length": "drop_bad_length",
                "reject_meta": "drop_meta",
                "reject_too_complete": "drop_too_complete",
            }.get(label)

            if mapped_counter is None:
                mapped_counter = "drop_overdramatic"

            counters[mapped_counter] += 1
            review_f.write(json.dumps({
                "label": label,
                "description": desc,
                "info": info,
            }, ensure_ascii=False) + "\n")

    print("✅ Фильтрация завершена")
    print(f"  Входной файл: {input_path}")
    print(f"  Очищенный файл: {output_path}")
    print(f"  Review-файл: {review_path}")
    print("  Статистика:")
    for k, v in counters.items():
        print(f"    {k}: {v}")


# ─────────────────────────────
# Глобальные переменные для трекинга (потокобезопасно)
# ─────────────────────────────

lock = threading.Lock()
generated_count = 0
duplicate_count = 0
error_count = 0
total_attempts_count = 0
existing_hashes_set: set[str] = set()


def sample_worker(client: OpenAI, weighted_categories: list[dict], out_f, start_time: float):
    global generated_count, duplicate_count, error_count, total_attempts_count

    with lock:
        if generated_count >= TARGET_COUNT:
            return
        total_attempts_count += 1

    category = random.choice(weighted_categories)

    try:
        description = generate_scene_description(client, category)
    except Exception as e:
        with lock:
            print(f"  [Error] ({category['name']}) ❌ Ошибка description: {e}")
            error_count += 1
        return

    description = normalize_text(description)
    if len(description) < 20:
        with lock:
            print(f"  [Error] ({category['name']}) ❌ Слишком короткое")
            record_reject("description_too_short", description)
            error_count += 1
        return

    desc_hash = content_hash(description)

    with lock:
        if desc_hash in existing_hashes_set:
            duplicate_count += 1
            return
        existing_hashes_set.add(desc_hash)
        current_idx = generated_count + 1
        preview = description.replace("\n", " | ")
        print(f"  [{current_idx}/{TARGET_COUNT}] ({category['name']}) '{preview[:120]}...'")

    scene_json = generate_scene_script(client, description)

    if scene_json is None:
        with lock:
            error_count += 1
            print(f"  [{current_idx}/{TARGET_COUNT}] ❌ SceneScript отклонён")
        return

    row = format_training_row(description, scene_json)
    serialized_row = compact_json(row)

    with lock:
        if generated_count >= TARGET_COUNT:
            return

        out_f.write(serialized_row + "\n")
        out_f.flush()

        generated_count += 1

        beats = scene_json.get("beats", [])
        all_actions = [a for b in beats for a in b.get("actions", [])]
        talk_count = sum(1 for a in all_actions if a.get("type") == "talk")
        described_count = sum(1 for a in all_actions if a.get("type") == "described_action")
        object_count = len(scene_json.get("objects", []))

        print(
            f"  ✅ [{generated_count}/{TARGET_COUNT}] beats={len(beats)}, actions={len(all_actions)}, "
            f"objects={object_count}, talk={talk_count}, described={described_count}"
        )

        if generated_count % 50 == 0:
            elapsed = time.time() - start_time
            print(
                f"\n📊 Прогресс: {generated_count}/{TARGET_COUNT} | "
                f"ошибок: {error_count} | дублей: {duplicate_count} | "
                f"попыток: {total_attempts_count} | время: {elapsed:.1f} сек\n"
            )


# ─────────────────────────────
# Main
# ─────────────────────────────

def main():
    global TARGET_COUNT, existing_hashes_set

    parser = argparse.ArgumentParser()
    parser.add_argument("--threads", type=int, default=4, help="Количество потоков")
    parser.add_argument("--count", type=int, default=TARGET_COUNT, help="Целевое количество примеров")
    parser.add_argument("--mode", choices=["generate", "filter"], default="generate", help="Режим работы")
    parser.add_argument("--input", type=str, default=OUTPUT_FILE, help="Входной JSONL для режима filter")
    parser.add_argument("--output", type=str, default=OUTPUT_FILE, help="Выходной JSONL")
    parser.add_argument("--review", type=str, default=FILTER_REVIEW_FILE, help="Review JSONL для режима filter")
    parser.add_argument("--keep-static-ratio", type=float, default=KEEP_STATIC_START_RATIO, help="Какую долю мягко-статичных стартов оставить")
    args = parser.parse_args()

    random.seed(RANDOM_SEED)

    if args.mode == "filter":
        filter_existing_dataset(
            input_path=args.input,
            output_path=args.output,
            review_path=args.review,
            keep_static_ratio=args.keep_static_ratio,
        )
        return

    TARGET_COUNT = args.count

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("❌ Установите OPENAI_API_KEY")
        return

    client = OpenAI(base_url=BASE_URL, api_key=api_key)

    existing_hashes_set = load_existing_hashes(args.output)
    if existing_hashes_set:
        print(f"📂 Найдено {len(existing_hashes_set)} существующих записей")

    weighted_categories = build_weighted_categories()
    start_time = time.time()

    print(f"🚀 Начинаем генерацию {TARGET_COUNT} примеров в {args.threads} потоках...")

    with open(args.output, "a", encoding="utf-8") as out_f:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.threads) as executor:
            while generated_count < TARGET_COUNT and total_attempts_count < MAX_TOTAL_ATTEMPTS:
                futures = [
                    executor.submit(sample_worker, client, weighted_categories, out_f, start_time)
                    for _ in range(args.threads * 2)
                ]
                concurrent.futures.wait(futures)

    elapsed = time.time() - start_time
    print(f"\n🎉 Готово за {elapsed:.1f} сек")
    print(f"  Сгенерировано: {generated_count}")
    print(f"  Ошибок: {error_count}")
    print(f"  Дубликатов: {duplicate_count}")
    print(f"  Попыток: {total_attempts_count}")
    print(f"  Время: {elapsed:.1f} сек")
    print(f"  Датасет: {args.output}")
    print(f"  Rejected: {REJECTED_FILE}")

    if generated_count < TARGET_COUNT:
        print("⚠️ Целевое количество не достигнуто. Это нормально при строгой валидации: лучше меньше, но чище.")


if __name__ == "__main__":
    main()
