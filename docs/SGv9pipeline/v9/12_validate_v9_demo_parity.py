from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


DEFAULT_CASE_IDS = {
    "dialogue_put_down": "syn-0030::dialogue_then_put_down_object__base__s895761__deabe8d2",
    "three_actor_give": "rt-0001::pref-rtf-rejected-dialogue_then_pick_up_object_then_give_to_third_actor__base__s225349__eea4feb1",
    "three_actor_ordinal_status": "hard-0021::ordinal_first_second_third__base__s186111__fc469b85",
}


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = line.strip()
            if payload:
                rows.append(json.loads(payload))
    return rows


def action_type(action: dict[str, Any]) -> str:
    return str(action.get("type") or action.get("actionType") or "").strip()


def actor_id(action: dict[str, Any]) -> str:
    return str(action.get("actorId") or action.get("actor_id") or action.get("actorSlot") or "").strip()


def target_id(action: dict[str, Any]) -> str:
    return str(action.get("target") or action.get("targetId") or action.get("target_id") or action.get("targetSlot") or "").strip()


def holding_object(action: dict[str, Any]) -> str:
    return str(action.get("holdingObject") or action.get("holding_object") or action.get("holdingObjectSlot") or "").strip()


def flatten_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    flat: list[dict[str, Any]] = []
    for beat_index, beat in enumerate(script.get("beats") or [], start=1):
        if not isinstance(beat, dict):
            continue
        for action in beat.get("actions") or []:
            if not isinstance(action, dict):
                continue
            row = dict(action)
            row["_beat_index"] = beat_index
            row["_beat_id"] = beat.get("id")
            flat.append(row)
    return flat


def find_action(actions: list[dict[str, Any]], *, actor: str, kind: str, target: str | None = None) -> dict[str, Any] | None:
    for action in actions:
        if actor_id(action) != actor:
            continue
        if action_type(action) != kind:
            continue
        if target is not None and target_id(action) != target:
            continue
        return action
    return None


def result(name: str, case_id: str, checks: list[tuple[str, bool]], script: dict[str, Any] | None) -> dict[str, Any]:
    failures = [label for label, ok in checks if not ok]
    return {
        "name": name,
        "eval_case_id": case_id,
        "pass": not failures,
        "failed_checks": failures,
        "prediction_action_count": len(flatten_actions(script or {})),
        "prediction_beat_count": len((script or {}).get("beats") or []),
    }


def validate_dialogue_put_down(case_id: str, script: dict[str, Any] | None) -> dict[str, Any]:
    actions = flatten_actions(script or {})
    talk = find_action(actions, actor="actor_1", kind="talk", target="actor_2")
    put_down = find_action(actions, actor="actor_2", kind="put_down", target="object_2")
    checks = [
        ("actor_1_talks_to_actor_2", talk is not None),
        ("actor_2_puts_down_to_object_2", put_down is not None),
        (
            "put_down_after_dialogue",
            talk is not None and put_down is not None and int(put_down["_beat_index"]) > int(talk["_beat_index"]),
        ),
    ]
    return result("dialogue_put_down", case_id, checks, script)


def validate_three_actor_give(case_id: str, script: dict[str, Any] | None) -> dict[str, Any]:
    actions = flatten_actions(script or {})
    talk_1 = find_action(actions, actor="actor_1", kind="talk", target="actor_2")
    talk_2 = find_action(actions, actor="actor_2", kind="talk", target="actor_1")
    pick = find_action(actions, actor="actor_2", kind="pick_up", target="object_1")
    give = find_action(actions, actor="actor_2", kind="give", target="actor_3")
    checks = [
        ("actor_1_talks_to_actor_2", talk_1 is not None),
        ("actor_2_talks_to_actor_1", talk_2 is not None),
        ("actor_2_picks_up_object_1", pick is not None),
        ("actor_2_gives_to_actor_3", give is not None),
        ("give_preserves_holding_object_1", give is not None and holding_object(give) == "object_1"),
        (
            "three_phase_order",
            talk_1 is not None
            and talk_2 is not None
            and pick is not None
            and give is not None
            and max(int(talk_1["_beat_index"]), int(talk_2["_beat_index"])) < int(pick["_beat_index"]) < int(give["_beat_index"]),
        ),
    ]
    return result("three_actor_give", case_id, checks, script)


def validate_three_actor_ordinal_status(case_id: str, script: dict[str, Any] | None) -> dict[str, Any]:
    actions = flatten_actions(script or {})
    approach = find_action(actions, actor="actor_1", kind="approach", target="object_1")
    look = find_action(actions, actor="actor_2", kind="look_at", target="actor_1")
    stand = find_action(actions, actor="actor_3", kind="stand")
    checks = [
        ("actor_1_approaches_object_1", approach is not None),
        ("actor_2_looks_at_actor_1", look is not None),
        ("actor_3_stands_without_required_target", stand is not None),
        ("single_beat_status_scene", len((script or {}).get("beats") or []) == 1),
    ]
    return result("three_actor_ordinal_status", case_id, checks, script)


VALIDATORS = {
    "dialogue_put_down": validate_dialogue_put_down,
    "three_actor_give": validate_three_actor_give,
    "three_actor_ordinal_status": validate_three_actor_ordinal_status,
}


def selected_script(row: dict[str, Any]) -> dict[str, Any] | None:
    for key in ("selected_predicted_script", "predicted_script", "end_to_end_predicted_script", "model_only_predicted_script"):
        value = row.get(key)
        if isinstance(value, dict):
            return value
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiled-predictions", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--case-map-json", type=Path)
    args = parser.parse_args()

    case_ids = dict(DEFAULT_CASE_IDS)
    if args.case_map_json:
        case_ids.update(json.loads(args.case_map_json.read_text(encoding="utf-8")))

    rows = read_jsonl(args.compiled_predictions)
    by_case = {str(row.get("eval_case_id") or ""): row for row in rows}
    results: list[dict[str, Any]] = []
    for name, case_id in case_ids.items():
        validator = VALIDATORS.get(name)
        if validator is None:
            raise ValueError(f"Unknown parity validator: {name}")
        row = by_case.get(case_id)
        script = selected_script(row or {})
        results.append(validator(case_id, script))

    output = {
        "compiled_predictions": str(args.compiled_predictions),
        "total": len(results),
        "passed": sum(1 for row in results if row["pass"]),
        "failed": sum(1 for row in results if not row["pass"]),
        "results": results,
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "demo_parity_results.json").write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(output, ensure_ascii=False, indent=2))
    if output["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
