from __future__ import annotations

from .config import StyleBucket


TRACK4_STYLE_BUCKETS: tuple[StyleBucket, ...] = ("clean", "colloquial", "user_short")

STYLE_RULES: dict[StyleBucket, str] = {
    "clean": "\n".join(
        [
            "- короткий прямой русский",
            "- без намеренного шума",
            "- все ключевые semantic anchors остаются явными",
        ]
    ),
    "colloquial": "\n".join(
        [
            "- разговорная пользовательская формулировка",
            "- допустимы бытовые слова вроде комп/ноут/телик, если они не ломают grounding",
            "- не скрывай chronology за эллипсисом",
        ]
    ),
    "user_short": "\n".join(
        [
            "- 1-2 короткие фразы",
            "- допускается телеграфность",
            "- нельзя жертвовать ordinal и marked-object anchors ради краткости",
        ]
    ),
}

STYLE_LENGTH_LIMITS: dict[StyleBucket, int] = {
    "clean": 260,
    "colloquial": 260,
    "user_short": 170,
}

STYLE_RETRY_BUDGETS: dict[StyleBucket, int] = {
    "clean": 2,
    "colloquial": 2,
    "user_short": 2,
}


def planned_style_buckets(*, max_variants_per_graph: int | None = None) -> list[StyleBucket]:
    buckets = list(TRACK4_STYLE_BUCKETS)
    if max_variants_per_graph is None:
        return buckets
    if max_variants_per_graph <= 0:
        return []
    return buckets[:max_variants_per_graph]
