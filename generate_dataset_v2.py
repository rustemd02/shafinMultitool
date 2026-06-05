#!/usr/bin/env python3
"""
generate_dataset_v2.py — Генерация обучающего датасета SceneScript v2

Beat-система + Камера + Позы актёров + Привязка объектов

Использование:
    pip install openai pydantic
    export OPENAI_API_KEY=sk-...
    python generate_dataset_v2.py
"""

import json
import os
import random
import hashlib
from pathlib import Path
from typing import Optional
from pydantic import BaseModel, field_validator
from openai import OpenAI

# ─────────────────────────────────────────────
# Pydantic-модели для валидации SceneScript v2
# ─────────────────────────────────────────────

class Actor(BaseModel):
    id: str
    type: str

class Object(BaseModel):
    id: str
    type: str

    @field_validator("type")
    @classmethod
    def validate_type(cls, v):
        if v not in VALID_OBJECT_TYPES:
            # Превращаем в generic если тип неизвестен, либо выбрасываем ошибку
            return "generic"
        return v

class CameraSetup(BaseModel):
    shotType: str                           # wide, medium, close_up, extreme_close_up, over_shoulder, two_shot
    movement: Optional[str] = None          # static, pan_left, pan_right, dolly_in, dolly_out, tracking, ...
    target: Optional[str] = None            # actorId или objectId

class Action(BaseModel):
    actorId: str
    type: str
    target: Optional[str] = None
    direction: Optional[str] = None
    speed: Optional[str] = None
    resultingPose: Optional[str] = None     # standing, sitting, crouching, lying, walking, running
    holdingObject: Optional[str] = None     # objectId — что актёр держит после этого действия
    dialogue: Optional[str] = None          # Текст реплики, если type = "talk"

    @field_validator("type")
    @classmethod
    def validate_action_type(cls, v):
        if v not in VALID_ACTION_TYPES:
            raise ValueError(f"Недопустимый тип действия: {v}")
        return v

    @field_validator("resultingPose")
    @classmethod
    def validate_pose(cls, v):
        if v and v not in VALID_POSES:
            # Если это имя действия, пробуем маппить
            mapping = {
                "walk": "walking", "run": "running", "sit": "sitting",
                "crouch": "crouching", "lie_down": "lying", "stand": "standing"
            }
            return mapping.get(v, "standing")
        return v

class Beat(BaseModel):
    id: str
    actions: list[Action]
    camera: Optional[CameraSetup] = None    # Камера для этого кадра раскадровки
    minDuration: Optional[float] = None     # Минимальная длительность (для пауз)

class SpatialRelation(BaseModel):
    id: str
    subject: str
    relation: str
    object: str

class SceneScriptV2(BaseModel):
    actors: list[Actor]
    objects: list[Object]
    beats: list[Beat]
    spatialRelations: list[SpatialRelation]

    @field_validator("beats")
    @classmethod
    def at_least_one_beat(cls, v):
        if not v:
            raise ValueError("Должен быть хотя бы один beat")
        return v

# ─────────────────────────────
# Конфигурация
# ─────────────────────────────

TARGET_COUNT = 2000
OUTPUT_FILE = Path(__file__).resolve().parent / "data" / "legacy" / "dataset_finetune_v2.jsonl"
MODEL = "gpt-5.4-nano"

# Допустимые типы действий для валидации и промпта
VALID_ACTION_TYPES = {
    "walk", "run", "approach", "pass_by", "enter", "exit", "stand", "sit",
    "lie_down", "stop", "turn", "crouch", "look_at", "pick_up", "put_down",
    "open", "close", "give", "talk"
}

# Допустимые позы (resultingPose)
VALID_POSES = {"standing", "sitting", "crouching", "lying", "walking", "running"}

# Допустимые типы объектов (из SceneObject.ObjectType в Swift)
VALID_OBJECT_TYPES = {
    "table", "chair", "cabinet", "door", "couch", "bed", "window", "shelf", "tv", "generic"
}

SYSTEM_PROMPT_FOR_TRAINING = (
    "Ты парсер мизансцен для кинопроизводства. Преобразуй текстовое описание "
    "мизансцены на русском языке в JSON (SceneScript). Разбивай действия на "
    "хронологические такты (beats). Каждый beat — одновременные действия всех актёров. "
    "ВНИМАНИЕ! Разрешены ТОЛЬКО следующие типы действий (action.type): "
    f"{', '.join(sorted(VALID_ACTION_TYPES))}.\n"
    "Если в тексте есть 'прыгает' или 'хватает', заменяй их на 'run' или 'pick_up'. "
    "Выводи ТОЛЬКО валидный JSON, без пояснений."
)

GENERATION_SYSTEM_PROMPT = """Ты генератор обучающих данных для fine-tuning LLM-парсера мизансцен.

Для данного описания мизансцены — сгенерируй ВАЛИДНЫЙ JSON в формате SceneScript v2.

## Формат SceneScript v2

```json
{
  "actors": [{"id": "actor_1", "type": "human"}, ...],
  "objects": [{"id": "object_1", "type": "table"}, ...],
  "beats": [
    {
      "id": "beat_1",
      "actions": [
        {"actorId": "actor_1", "type": "walk", "direction": "toward_each_other", "target": "actor_2", "resultingPose": "walking"},
        {"actorId": "actor_2", "type": "walk", "direction": "toward_each_other", "target": "actor_1", "resultingPose": "walking"}
      ],
      "camera": {"shotType": "wide", "movement": "static"},
      "minDuration": null
    },
    {
      "id": "beat_2",
      "actions": [
        {"actorId": "actor_1", "type": "stop", "resultingPose": "standing"},
        {"actorId": "actor_2", "type": "pick_up", "target": "object_1", "holdingObject": "object_1", "resultingPose": "standing"}
      ],
      "camera": {"shotType": "medium", "movement": "dolly_in", "target": "actor_2"}
    },
    {
      "id": "beat_3",
      "actions": [
        {"actorId": "actor_1", "type": "walk", "direction": "forward", "target": "object_1", "resultingPose": "walking"},
        {"actorId": "actor_1", "type": "talk", "dialogue": "Подожди, я возьму это с собой.", "resultingPose": "walking"},
        {"actorId": "actor_2", "type": "look_at", "target": "actor_1", "resultingPose": "standing"}
      ],
      "camera": {"shotType": "over_shoulder", "movement": "tracking", "target": "actor_1"}
    }
  ],
  "spatialRelations": [
    {"id": "rel_1", "subject": "actor_1", "relation": "standing_near", "object": "object_1"}
  ]
}
```

## Правила beats:
1. **Beat = одна фаза сцены.** Все actions внутри beat происходят ОДНОВРЕМЕННО.
2. Последовательные фазы ("сначала... затем... потом...") — каждая = отдельный beat.
3. Если 2+ актёра делают что-то одновременно — их actions в ОДНОМ beat.
4. Если актёр не упомянут в фазе — НЕ добавляй пустое действие.
5. ID: "beat_1", "beat_2"...
6. Одна сцена = 1-8 beats (для диалогов может быть больше: каждая реплика + действие = отдельный beat).

## Правила камеры (camera):
1. Каждый beat ДОЛЖЕН иметь поле "camera" с минимум "shotType".
2. Выбирай крупность осмысленно:
   - "wide" — общий план, видно всё пространство (для начала сцены, панорам)
   - "medium" — средний план (разговоры, обычные действия)
   - "close_up" — крупный план лица/рук (эмоции, важные действия)
   - "extreme_close_up" — деталь (предмет, глаза, ключ в замке)
   - "over_shoulder" — через плечо одного актёра на другого (диалог)
   - "two_shot" — двойной план (оба актёра в кадре)
3. "movement" (опционально):
   - "static" — камера неподвижна
   - "pan_left"/"pan_right" — панорамирование
   - "dolly_in"/"dolly_out" — наезд/отъезд
   - "tracking" — слежение за персонажем
   - "crane_up"/"crane_down" — вертикальное движение
   - "tilt_up"/"tilt_down" — наклон камеры
4. "target" (опционально) — на кого направлена камера (actorId или objectId).

## Правила поз (resultingPose):
1. ЯВНО указывай `resultingPose` для КАЖДОГО действия (в какую позу переходит актёр ПОСЛЕ действия):
   - walk/approach/enter/exit/pass_by → "walking"
   - run → "running"
   - stand/stop/turn/give/open/close/look_at/put_down → "standing" (если до этого стоял) или "sitting" (если сидел)
   - sit → "sitting"
   - crouch → "crouching"
   - lie_down → "lying"
   - pick_up → сохранять текущую позу

## Правила holdingObject:
1. После "pick_up" с target=object_X — ОБЯЗАТЕЛЬНО указывай "holdingObject": "object_X"
2. Во всех ПОСЛЕДУЮЩИХ действиях (walk, stop, turn и т.д.) этого актёра — ПЕРЕНОСИ "holdingObject": "object_X", пока он его не отпустит.
3. Действия "put_down" (цель - объект) или "give" (цель - другой актёр) ОСВОБОЖДАЮТ руки → holdingObject = null (или просто не указывай поле).
4. ВАЖНО: Если Актёр 1 передаёт предмет Актёру 2 (type="give", target="actor_2"), то в этом же beat ТОЧНО должно быть действие для Актёра 2: type="pick_up", target="тот_самый_объект", holdingObject="тот_самый_объект".

## Правила диалогов (dialogue):
1. Если кто-то произносит реплику (или в описании есть диалог) — используй `"type": "talk"` и запиши текст в поле `"dialogue"`.
2. Пример: `{"actorId": "actor_1", "type": "talk", "dialogue": "Я знаю. Были заложники.", "resultingPose": "standing"}`
3. Актёр МОЖЕТ говорить одновременно с другими действиями! Например, если актёр идёт и говорит — в одном beat ставь и walk, и talk. Длительность beat определится автоматически.
4. resultingPose для talk — та поза, в которой актёр НАХОДИТСЯ во время реплики (standing, sitting, walking — любая).

## Правила minDuration:
1. Обычно null (длительность beat определяется автоматически: по расстоянию ходьбы или длине реплики).
2. Для драматических пауз ("долгая пауза", "ждёт 5 секунд", "тишина") — указать число в секундах (1.0-10.0).
3. НЕ нужно указывать minDuration для реплик — длительность посчитается из длины текста dialogue.

## Правила spatialRelations:
1. Можешь оставлять ключом "spatialRelations": [] (пустой массив).
2. Если хочешь указать отношение — используй строго поля: "id" (rel_1), "subject" (id того кто/что), "relation" (строка, например "standing_near", "on_top_of", "inside", "holding", "in_front_of"), "object" (id того относительно кого/чего).

## Допустимые типы:

## Допустимые типы (СТРОГО):

### actor.type:
human, tiger, lion, dog, cat, bird, generic

### object.type (ТОЛЬКО ЭТИ):
table, chair, cabinet, door, couch, bed, window, shelf, tv, generic
(Если предмет мелкий, например стакан, книга или ключ — ИСПОЛЬЗУЙ тип "generic")

### action.type:
walk, run, approach, pass_by, enter, exit, stand, sit, lie_down, stop, turn, crouch, look_at, pick_up, put_down, open, close, give, talk
ВНИМАНИЕ: СТРОЖАЙШЕ ЗАПРЕЩАЕТСЯ использовать другие action.type (никаких jump, grab, pull, hold, drop).

### action.resultingPose (ТОЛЬКО ЭТИ):
standing, sitting, crouching, lying, walking, running
(ЗАПРЕЩЕНО писать "pick_up" или "give" в поле resultingPose! Пиши только текущую физическую позу актёра.)

### action.direction:
left, right, forward, backward, toward_each_other, away_from_each_other, to_target

### action.speed:
slowly, quickly, carefully

## ВАЖНО:
- Выводи ТОЛЬКО JSON, без markdown, без пояснений
- Все actorId и target в actions ОБЯЗАНЫ ссылаться на существующие id из actors/objects
- target может быть actorId (взаимодействие между актёрами) или objectId
- Camera ОБЯЗАТЕЛЬНА для каждого beat
"""

# Промпты для генерации описаний сцен
SCENE_CATEGORIES = [
    {
        "name": "dialogue_shot_reverse",
        "weight": 15,
        "prompts": [
            "Два друга стоят у барной стойки и разговаривают, один жестикулирует со стаканом, другой кивает",
            "Муж и жена на кухне, она у плиты, он за столом, обсуждают планы на отпуск",
            "Двое студентов сидят в библиотеке друг напротив друга. Один шёпотом начинает говорить, второй отворачивается к книге",
            "Коллеги обсуждают проект у кулера, один облокачивается на стену"
        ]
    },
    {
        "name": "screenplay_dialogue",
        "weight": 14,
        "prompts": [
            "МАША сидит у окна. Входит ДИМА.\nДИМА: Ты получила письмо?\nМАША встаёт, подходит к столу, берёт конверт.\nМАША: Вот оно. Читай сам.",
            "ВРАЧ (перелистывая карту): Как вы себя чувствуете сегодня?\nПАЦИЕНТ (сидит на кушетке): Нного лучше, спасибо.",
            "АННА: Мы не можем так поступить!\nОна резко бьёт кулаком по столу.\nИВАН: Придётся.\nИван поворачивается и направляется к двери.",
            "АЛЕКСЕЙ (смеется): Ты серьёзно купил этот старый рыдвань?\nМИХАИЛ (закрывает капот): Он ещё нас переживёт!"
        ]
    },
    {
        "name": "chase_action",
        "weight": 12,
        "prompts": [
            "Человек выбегает из подъезда, второй бежит за ним по дворам",
            "Двое быстро бегут по длинному коридору, один сворачивает за угол, другой резко останавливается",
            "Женщина бежит к машине, распахивает дверь, мужчина подбегает и хватает её за руку"
        ]
    },
    {
        "name": "table_scene",
        "weight": 10,
        "prompts": [
            "Семья за ужином: отец во главе стола ест, мать подаёт блюдо на стол, сын встаёт со стула",
            "Друзья сидят за деревянным столом в кафе, один подсаживается с подносом",
            "Один встаёт из-за стола, берёт свою кружку и отходит к окну, второй остаётся сидеть"
        ]
    },
    {
        "name": "enter_and_discover",
        "weight": 8,
        "prompts": [
            "Человек заходит в антикварную лавку, осматривается, подходит к полке и видит старинные часы",
            "Студент открывает дверь аудитории, делает шаг внутрь, замирает, увидев сюрприз, и роняет сумку"
        ]
    },
    {
        "name": "interrogation",
        "weight": 3,
        "prompts": [
            "Подозреваемый сидит за железным столом. Полицейский обходит его со спины, останавливается и смотрит сверху вниз",
            "Офицер кладёт жёлтую папку на стол, садится напротив задержанного и открывает её"
        ]
    },
    {
        "name": "handoff_exchange",
        "weight": 6,
        "prompts": [
            "Один из них достаёт из кармана ключи, передаёт другому. Тот берёт их и прячет во внутренний карман",
            "Курьер подходит к двери, передаёт коробку пиццы, получатель забирает её и закрывает дверь",
            "Девушка передаёт баристе купюру, тот отдаёт ей стакан с кофе"
        ]
    },
    {
        "name": "walking_and_talking",
        "weight": 8,
        "prompts": [
            "Двое врачей быстро идут по коридору больницы, активно обсуждая диагноз пациента. Один резко останавливается у двери палаты",
            "Мужчина и женщина идут по улице бок о бок, разговаривая. Мужчина поворачивает в сторону переулка, женщина следует за ним"
        ]
    },
    {
        "name": "dramatic_entrance",
        "weight": 5,
        "prompts": [
            "Дверь с шумом открывается, в комнату быстро заходит охранник, все внутри резко поворачивают к нему головы",
            "Женщина распахивает дверь кабинета, решительным шагом подходит к столу, бросает документы и разворачивается"
        ]
    },
    {
        "name": "surveillance_follow",
        "weight": 4,
        "prompts": [
            "Один медленно идёт по тёмной улице не оглядываясь, второй человек крадётся за ним на приличном расстоянии",
            "Агент прячется за деревянной колонной, долго смотрит на объект, потом осторожно выходит в проём"
        ]
    },
    {
        "name": "emotional_scene",
        "weight": 5,
        "prompts": [
            "Девушка медленно подходит к парню, останавливается в метре от него, он поворачивается и смотрит ей в глаза",
            "Двое встречаются у здания вокзала, один подбегает и крепко обнимает другого"
        ]
    },
    {
        "name": "solo_procedural",
        "weight": 6,
        "prompts": [
            "Криминалист в перчатках внимательно осматривает комнату: подходит к столу, наклоняется, берёт пинцетом какой-то предмет",
            "Человек заходит в ванную, открывает кран, смотрит в зеркало, затем опирается двумя руками о раковину"
        ]
    },
    {
        "name": "simple_blocking",
        "weight": 3,
        "prompts": [
            "Один человек стоит у стены",
            "Актёр делает несколько шагов вперёд и останавливается",
            "Женщина садится на диван и закидывает ногу на ногу",
            "Двое стоят рядом молча"
        ]
    }
]


# Категории, в которых ОБЯЗАТЕЛЬНО должны быть реплики
DIALOGUE_CATEGORIES = {
    "dialogue_shot_reverse", "screenplay_dialogue", "walking_and_talking",
    "interrogation", "table_scene", "emotional_scene"
}


def _build_description_user_prompt(category: dict, seed_prompt: str) -> str:
    """Строит user-prompt для генерации описания с учётом категории."""
    base = f"Создай одно уникальное описание мизансцены, вдохновлённое этим примером (но НЕ копируй его): \"{seed_prompt}\"\nВНИМАНИЕ: Не перегружай сцену мелкими предметами. Максимум 3-5 значимых объектов, с которыми взаимодействуют актёры."
    
    if category["name"] in DIALOGUE_CATEGORIES:
        base += (
            "\nВАЖНО: описание ОБЯЗАТЕЛЬНО должно содержать прямую речь персонажей "
            "в формате «ИМЯ: реплика». Включи минимум 2 реплики разных персонажей. "
            "Между репликами должны быть физические действия."
        )
    elif category["name"] in {"chase_action", "surveillance_follow"}:
        base += "\nОписание должно быть динамичным, с быстрыми перемещениями. БЕЗ диалогов."
    
    return base


def generate_scene_description(client: OpenAI, category: dict) -> str:
    seed_prompt = random.choice(category["prompts"])
    response = client.chat.completions.create(
        model=MODEL,
        messages=[
            {
                "role": "system",
                "content": (
                    "Ты генератор описаний мизансцен для кино. Создавай разнообразные описания "
                    "сцен на русском языке. Варьируй стиль: режиссёрские ремарки, "
                    "сценарий с репликами (ИМЯ: текст), литературный стиль. "
                    "Описание должно содержать чёткие физические действия (перемещения, объекты). "
                    "Ответ — ТОЛЬКО само описание, без кавычек, без нумерации."
                )
            },
            {
                "role": "user",
                "content": _build_description_user_prompt(category, seed_prompt)
            }
        ]
    )
    return response.choices[0].message.content.strip()


def generate_scene_script(client: OpenAI, description: str) -> Optional[dict]:
    try:
        response = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": GENERATION_SYSTEM_PROMPT},
                {"role": "user", "content": f"Описание сцены: {description}\n\nСгенерируй ВАЛИДНЫЙ JSON-объект раскадровки (SceneScript v2). Начинай свой ответ строго с {{."}
            ]
        )
        raw = response.choices[0].message.content or ""
        raw = raw.strip()
        
        # Убираем возможный префикс или суффикс
        if raw.startswith("```json"):
            raw = raw[7:]
        elif raw.startswith("```"):
            raw = raw[3:]
        if raw.endswith("```"):
            raw = raw[:-3]
        raw = raw.strip()

        # Ищем начало JSON-объекта на случай болтливости модели
        start_idx = raw.find('{')
        end_idx = raw.rfind('}')
        if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
            raw = raw[start_idx:end_idx+1]

        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as je:
            print(f"  ❌ Ошибка JSON: {je}. Raw output: {repr(raw)[:200]}...")
            return None

        # Валидируем через Pydantic
        script = SceneScriptV2(**parsed)

        # Referential integrity
        actor_ids = {a.id for a in script.actors}
        object_ids = {o.id for o in script.objects}
        valid_targets = actor_ids | object_ids

        valid_action_types = {
            "walk", "run", "approach", "pass_by", "enter", "exit", "stand",
            "sit", "lie_down", "stop", "turn", "crouch", "look_at", "pick_up",
            "put_down", "open", "close", "give", "talk"
        }

        for beat in script.beats:
            # Проверка камеры
            if beat.camera is None:
                print(f"  ⚠️ beat '{beat.id}' без камеры, отклоняем")
                return None
            if beat.camera.target and beat.camera.target not in valid_targets:
                print(f"  ⚠️ camera.target '{beat.camera.target}' не найден, отклоняем")
                return None

            for action in beat.actions:
                if action.type not in valid_action_types:
                    print(f"  ⚠️ Недопустимый action.type '{action.type}', отклоняем")
                    return None
                if action.type == "talk" and not action.dialogue:
                    print(f"  ⚠️ action.type 'talk' без dialogue, отклоняем")
                    return None
                if action.actorId not in actor_ids:
                    print(f"  ⚠️ actorId '{action.actorId}' не найден, отклоняем")
                    return None
                if action.target and action.target not in valid_targets:
                    print(f"  ⚠️ target '{action.target}' не найден, отклоняем")
                    return None
                if action.holdingObject and action.holdingObject not in object_ids:
                    print(f"  ⚠️ holdingObject '{action.holdingObject}' не найден, отклоняем")
                    return None

        return parsed

    except Exception as e:
        print(f"  ❌ Ошибка генерации: {e}")
        return None


def format_training_row(description: str, scene_json: dict) -> dict:
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_FOR_TRAINING},
            {"role": "user", "content": description},
            {"role": "assistant", "content": json.dumps(scene_json, ensure_ascii=False)}
        ]
    }


def content_hash(description: str) -> str:
    return hashlib.md5(description.strip().lower().encode()).hexdigest()


def main():
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("❌ Установите OPENAI_API_KEY")
        return

    client = OpenAI(base_url="https://polza.ai/api/v1", api_key=api_key)

    existing_hashes = set()
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    row = json.loads(line)
                    desc = row["messages"][1]["content"]
                    existing_hashes.add(content_hash(desc))
                except:
                    pass
        print(f"📂 Найдено {len(existing_hashes)} существующих записей")

    weighted_categories = []
    for cat in SCENE_CATEGORIES:
        weighted_categories.extend([cat] * cat["weight"])

    generated = 0
    duplicates = 0
    errors = 0

    print(f"🚀 Начинаем генерацию {TARGET_COUNT} примеров...")

    with open(OUTPUT_FILE, "a", encoding="utf-8") as f:
        while generated < TARGET_COUNT:
            category = random.choice(weighted_categories)
            batch_label = f"[{generated+1}/{TARGET_COUNT}] ({category['name']})"

            try:
                description = generate_scene_description(client, category)
                if len(description) < 10:
                    print(f"  {batch_label} ❌ Пустое описание, пропускаем")
                    errors += 1
                    continue
            except Exception as e:
                print(f"  {batch_label} ❌ Ошибка генерации описания: {e}")
                errors += 1
                continue

            h = content_hash(description)
            if h in existing_hashes:
                duplicates += 1
                continue
            existing_hashes.add(h)

            print(f"  {batch_label} '{description[:80]}...'")
            scene_json = generate_scene_script(client, description)
            if scene_json is None:
                errors += 1
                continue
                
            objs_count = len(scene_json.get("objects", []))
            if objs_count > 8:
                print(f"  ⚠️ Слишком много объектов ({objs_count}), пропускаем для упрощения модели")
                errors += 1
                continue

            row = format_training_row(description, scene_json)
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            f.flush()

            beats = scene_json.get("beats", [])
            beats_count = len(beats)
            all_actions = [a for b in beats for a in b.get("actions", [])]
            actions_count = len(all_actions)
            has_camera = all(b.get("camera") for b in beats)
            talk_count = sum(1 for a in all_actions if a.get("type") == "talk")
            talk_info = f", 💬talk={talk_count}" if talk_count > 0 else ""
            print(f"  ✅ beats={beats_count}, actions={actions_count}, camera={'✅' if has_camera else '❌'}{talk_info}")

            generated += 1

            if generated % 50 == 0:
                print(f"\n📊 Прогресс: {generated}/{TARGET_COUNT} (ошибок: {errors}, дубликатов: {duplicates})\n")

    print(f"\n🎉 Готово!")
    print(f"  Сгенерировано: {generated}")
    print(f"  Ошибок: {errors}")
    print(f"  Дубликатов: {duplicates}")
    print(f"  Файл: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
