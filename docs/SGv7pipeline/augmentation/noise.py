from __future__ import annotations

import re


def apply_noise_transform(text: str, transform_id: str) -> tuple[str, dict[str, object]] | None:
    if transform_id == "noise.double_space":
        match = re.search(r"(?<=\w) (?=\w)", text)
        if match:
            return (
                text[:match.start()] + "  " + text[match.end():],
                {
                    "transform_id": transform_id,
                    "class": "whitespace_noise",
                    "safety_level": "safe",
                    "slot_type": "whitespace_slot",
                    "slot_index": match.start(),
                    "before": " ",
                    "after": "  ",
                },
            )
    if transform_id == "noise.drop_final_punctuation":
        match = re.search(r"[.!?]\s*$", text)
        if match:
            return (
                text[:match.start()] + text[match.end():],
                {
                    "transform_id": transform_id,
                    "class": "punctuation_noise",
                    "safety_level": "safe",
                    "slot_type": "sentence_tail",
                    "slot_index": match.start(),
                    "before": match.group(0).strip(),
                    "after": "",
                },
            )
    if transform_id == "noise.drop_optional_comma":
        match = re.search(r",\s+", text)
        if match:
            return (
                text[:match.start()] + " " + text[match.end():],
                {
                    "transform_id": transform_id,
                    "class": "punctuation_noise",
                    "safety_level": "safe",
                    "slot_type": "punctuation_slot",
                    "slot_index": match.start(),
                    "before": ",",
                    "after": "",
                },
            )
    if transform_id == "noise.no_space_after_comma":
        match = re.search(r",\s+", text)
        if match:
            return (
                text[:match.start()] + "," + text[match.end():],
                {
                    "transform_id": transform_id,
                    "class": "punctuation_noise",
                    "safety_level": "safe",
                    "slot_type": "punctuation_slot",
                    "slot_index": match.start(),
                    "before": ", ",
                    "after": ",",
                },
            )
    return None
