from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
from typing import Any

try:
    from dataset_builder.ingest import build_semantic_family_key, normalized_source_hash_v1, token_count
    from dataset_builder.renderer import canonical_json_string, render_preference_messages
except ModuleNotFoundError:  # pragma: no cover - package import path fallback
    from ..dataset_builder.ingest import build_semantic_family_key, normalized_source_hash_v1, token_count
    from ..dataset_builder.renderer import canonical_json_string, render_preference_messages

from .io import read_jsonl, write_json, write_jsonl


class Iter3CorpusBuildError(ValueError):
    """Raised when iter3 hard-set materialization violates contract assumptions."""


FORCE_INCLUDE_PATTERNS = {
    "open_then_pick_up_object",
    "ordinal_first_second_third",
    "same_type_two_marked_objects",
    "dialogue_then_pick_up_object_then_give_to_third_actor",
    "first_pick_up_object_then_give_to_third_actor",
    "toward_each_other_then_stop_near_marked_object_then_second_runs",
    "toward_each_other_then_pass_by_marked_object_then_second_runs",
    "toward_each_other_then_pass_by_object_then_second_runs",
}

MANUAL_REVIEW_PATTERNS = (
    "open_then_pick_up_object",
    "ordinal_first_second_third",
    "dialogue_then_pick_up_object_then_give_to_third_actor",
)

TARGETED_FAMILIES = {
    "exact_marker_identity",
    "give_to_third_actor",
    "open_then_pick_up",
    "ordinal",
    "three_beat",
}

DEFAULT_DELTA_SFT_MAX_FAMILY_SHARE = 0.50
GOLD_CHOSEN_MAX_SHARE = 0.55
GOLD_CHOSEN_MAX_FAMILY_SHARE = 0.60
MIN_MODEL_CHOSEN_SHARE = 0.25
MIN_MODEL_CHOSEN_PER_TARGETED_FAMILY = 2
MIN_TARGETED_FAMILY_CASES_FOR_MODEL_FLOOR = 4

DISAGREEMENT_FIELDS = (
    "json_valid",
    "schema_valid",
    "ordinal_binding_pass",
    "target_resolution_pass",
    "chronology_phase_pass",
    "action_recall_pass",
    "case_strict_success",
    "runtime_policy_decision",
)

_TARGET_REQUIRED_ACTIONS = {"approach", "passby", "pass_by", "pass-by", "look_at", "pick_up", "open", "give"}
_LEGACY_BEAT_FIELDS = {
    "type",
    "action",
    "actorId",
    "actor_id",
    "actorIds",
    "target",
    "targetId",
    "dialogue",
    "resultingText",
    "resultingDialogue",
    "resultingPose",
}


@dataclass(frozen=True)
class Iter3CorpusBuildRequest:
    eval_cases_jsonl: Path
    cir_jsonl: Path
    v7_case_results_jsonl: Path
    iter1_case_results_jsonl: Path
    iter2_case_results_jsonl: Path
    v7_predictions_jsonl: Path
    iter1_predictions_jsonl: Path
    iter2_predictions_jsonl: Path
    output_dir: Path
    seed: int
    iter2_vs_iter1_paired_jsonl: Path
    iter2_vs_v7_paired_jsonl: Path
    delta_sft_val_ratio: float = 0.10
    preference_val_ratio: float = 0.10
    max_simple_dialogue_share: float = 0.15
    min_family_counts: dict[str, int] | None = None
    manual_review_samples_per_pattern: int = 5
    delta_sft_max_family_share: float | None = DEFAULT_DELTA_SFT_MAX_FAMILY_SHARE


@dataclass(frozen=True)
class _ModelCaseView:
    model_id: str
    case_row: dict[str, Any]
    prediction_row: dict[str, Any] | None
    script: dict[str, Any] | None
    end_to_end_script: dict[str, Any] | None
    raw_output_json: dict[str, Any] | None
    canonical_ok: bool
    family_ok: bool
    eligible_for_chosen: bool
    semantic_tuple: tuple[int, ...]
    integrity_tuple: tuple[int, ...]
    degrade_tuple: tuple[int, ...]


@dataclass(frozen=True)
class _CaseSelection:
    eval_case_id: str
    sample_id: str
    pattern_name: str
    source_text: str
    critical_eval_tags: list[str]
    chosen_source: str
    chosen_json: dict[str, Any]
    rejected_source: str | None
    rejected_json: dict[str, Any] | None
    reason: str
    families: set[str]


def _stable_key(seed: int, tag: str, identifier: str) -> tuple[int, str]:
    digest = hashlib.sha256(f"{seed}|{tag}|{identifier}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16), identifier


def _normalize_action_type(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    lowered = raw.replace("-", "_").replace(" ", "_")
    return lowered.lower()


def _scripts_differ(left: dict[str, Any] | None, right: dict[str, Any] | None) -> bool:
    if left is None or right is None:
        return left is not right
    return canonical_json_string(left) != canonical_json_string(right)


def _script_actions(script: dict[str, Any]) -> list[tuple[int, dict[str, Any]]]:
    output: list[tuple[int, dict[str, Any]]] = []
    beats = script.get("beats")
    if not isinstance(beats, list):
        return output
    for beat_index, beat in enumerate(beats, start=1):
        if not isinstance(beat, dict):
            continue
        actions = beat.get("actions")
        if not isinstance(actions, list):
            continue
        for action in actions:
            if isinstance(action, dict):
                output.append((beat_index, action))
    return output


def _action_actor_id(action: dict[str, Any]) -> str:
    return str(action.get("actorId") or action.get("actor_id") or "").strip()


def _action_target_id(action: dict[str, Any]) -> str:
    return str(action.get("target") or action.get("targetId") or "").strip()


def _action_holding_object(action: dict[str, Any]) -> str:
    return str(action.get("holdingObject") or action.get("holding_object") or "").strip()


def _has_legacy_beat_level_actions(script: dict[str, Any]) -> bool:
    beats = script.get("beats")
    if not isinstance(beats, list):
        return False
    for beat in beats:
        if not isinstance(beat, dict):
            continue
        actions = beat.get("actions")
        if isinstance(actions, list) and actions:
            continue
        if any(field in beat for field in _LEGACY_BEAT_FIELDS):
            return True
    return False


def _schema_valid(script: dict[str, Any]) -> bool:
    if not isinstance(script, dict):
        return False
    actors = script.get("actors")
    objects = script.get("objects")
    beats = script.get("beats")
    relations = script.get("spatialRelations")
    if not isinstance(actors, list) or not isinstance(objects, list) or not isinstance(beats, list) or not isinstance(relations, list):
        return False

    actor_ids: set[str] = set()
    object_ids: set[str] = set()
    for actor in actors:
        if not isinstance(actor, dict):
            return False
        actor_id = str(actor.get("id") or "").strip()
        if not actor_id or actor_id in actor_ids:
            return False
        actor_ids.add(actor_id)
    for obj in objects:
        if not isinstance(obj, dict):
            return False
        object_id = str(obj.get("id") or "").strip()
        if not object_id or object_id in object_ids:
            return False
        object_ids.add(object_id)

    valid_targets = actor_ids | object_ids

    for rel in relations:
        if not isinstance(rel, dict):
            return False
        subject = str(rel.get("subject") or "").strip()
        object_id = str(rel.get("object") or "").strip()
        if not subject or subject not in valid_targets:
            return False
        if not object_id or object_id not in valid_targets:
            return False

    if not beats:
        return False
    for beat in beats:
        if not isinstance(beat, dict):
            return False
        if any(field in beat for field in _LEGACY_BEAT_FIELDS):
            return False
        actions = beat.get("actions")
        if not isinstance(actions, list) or not actions:
            return False
        for action in actions:
            if not isinstance(action, dict):
                return False
            actor_id = _action_actor_id(action)
            action_type = _normalize_action_type(action.get("type"))
            target_id = _action_target_id(action)
            holding_object = _action_holding_object(action)
            if not actor_id or actor_id not in actor_ids:
                return False
            if not action_type:
                return False
            if target_id and target_id not in valid_targets:
                return False
            if action_type in _TARGET_REQUIRED_ACTIONS and not target_id:
                return False
            if holding_object and holding_object not in object_ids:
                return False
            if action_type == "pick_up" and (not holding_object or holding_object != target_id):
                return False
            if action_type == "give":
                if not holding_object or target_id not in actor_ids:
                    return False
            if action_type == "talk" and not str(action.get("dialogue") or "").strip():
                return False
    if "actions" in script:
        return False
    return True


def _is_canonical_candidate(script: dict[str, Any] | None) -> bool:
    if not isinstance(script, dict):
        return False
    if _has_legacy_beat_level_actions(script):
        return False
    if len(_script_actions(script)) == 0:
        return False
    return _schema_valid(script)


def _family_set(*, pattern_name: str, semantic_tags: list[str], critical_eval_tags: list[str], pattern_family: str) -> set[str]:
    tags = {str(tag) for tag in semantic_tags}
    critical = {str(tag) for tag in critical_eval_tags}
    families: set[str] = set()
    if "ordinal_reference" in tags or "ordinal_cases" in critical or pattern_name.startswith("ordinal_"):
        families.add("ordinal")
    if "multi_beat" in tags or "three_beat_cases" in critical:
        families.add("three_beat")
    if "same_type_markers" in tags or "exact_marker_identity_cases" in critical or pattern_name == "same_type_two_marked_objects":
        families.add("exact_marker_identity")
    if "give_to_third_actor" in pattern_name:
        families.add("give_to_third_actor")
    if pattern_name == "open_then_pick_up_object":
        families.add("open_then_pick_up")
    if pattern_family == "dialogue" or pattern_name == "dialogue_only":
        families.add("simple_dialogue")
    return families


def _pattern_family_ok(pattern_name: str, script: dict[str, Any]) -> bool:
    actions = _script_actions(script)
    if pattern_name == "open_then_pick_up_object":
        if len(actions) < 2:
            return False
        beat_types: list[tuple[int, str, dict[str, Any]]] = [
            (beat_index, _normalize_action_type(action.get("type")), action)
            for beat_index, action in actions
        ]
        open_beat = next((beat for beat, action_type, _ in beat_types if action_type == "open"), None)
        pick_up = next(((beat, action) for beat, action_type, action in beat_types if action_type == "pick_up"), None)
        if open_beat is None or pick_up is None:
            return False
        return open_beat < pick_up[0]

    if pattern_name == "ordinal_first_second_third":
        has_approach = False
        has_look = False
        has_third = False
        for _, action in actions:
            action_type = _normalize_action_type(action.get("type"))
            actor_id = _action_actor_id(action)
            target_id = _action_target_id(action)
            if action_type == "approach" and actor_id == "actor_1":
                has_approach = True
            if action_type == "look_at" and actor_id == "actor_2" and target_id == "actor_1":
                has_look = True
            if action_type == "stand" and actor_id == "actor_3":
                has_third = True
        return has_approach and has_look and has_third

    if pattern_name in {
        "dialogue_then_pick_up_object_then_give_to_third_actor",
        "first_pick_up_object_then_give_to_third_actor",
        "second_pick_up_object_then_give_to_third_actor",
    }:
        pick_actor = {
            "dialogue_then_pick_up_object_then_give_to_third_actor": "actor_2",
            "first_pick_up_object_then_give_to_third_actor": "actor_1",
            "second_pick_up_object_then_give_to_third_actor": "actor_2",
        }[pattern_name]
        beats = script.get("beats")
        if not isinstance(beats, list) or not beats:
            return False
        pick_object = ""
        pick_beat_index = -1
        for beat_index, action in actions:
            if _normalize_action_type(action.get("type")) == "pick_up" and _action_actor_id(action) == pick_actor:
                pick_object = _action_holding_object(action) or _action_target_id(action)
                pick_beat_index = beat_index
                break
        if not pick_object or pick_beat_index < 0:
            return False
        final_actions = beats[-1].get("actions")
        if not isinstance(final_actions, list):
            return False
        for action in final_actions:
            if not isinstance(action, dict):
                continue
            if (
                _normalize_action_type(action.get("type")) == "give"
                and _action_actor_id(action) == pick_actor
                and _action_target_id(action) == "actor_3"
                and _action_holding_object(action) == pick_object
            ):
                if pattern_name == "dialogue_then_pick_up_object_then_give_to_third_actor":
                    first_actions = beats[0].get("actions")
                    return isinstance(first_actions, list) and any(
                        isinstance(item, dict) and _normalize_action_type(item.get("type")) == "talk"
                        for item in first_actions
                    )
                return True
        return False

    if pattern_name == "same_type_two_marked_objects":
        objects = script.get("objects")
        relations = script.get("spatialRelations")
        if not isinstance(objects, list) or not isinstance(relations, list):
            return False
        marked_ids = {
            str(item.get("id") or "").strip()
            for item in objects
            if isinstance(item, dict) and str(item.get("id") or "").startswith("object_marked_")
        }
        if len(marked_ids) < 2:
            return False
        actor_1_targets = {
            _action_target_id(action)
            for _, action in actions
            if _action_actor_id(action) == "actor_1" and _action_target_id(action) in marked_ids
        }
        actor_2_relations = {
            str(rel.get("object") or "").strip()
            for rel in relations
            if isinstance(rel, dict)
            and str(rel.get("subject") or "").strip() == "actor_2"
            and str(rel.get("object") or "").strip() in marked_ids
        }
        if not actor_1_targets or not actor_2_relations:
            return False
        return any(target not in actor_2_relations for target in actor_1_targets)

    return True


def _case_flag(case_row: dict[str, Any], name: str) -> bool:
    if name in {"json_valid", "schema_valid", "case_strict_success"}:
        return bool(case_row.get(name, False))
    if name == "runtime_policy_decision":
        return str(case_row.get(name, "")) == "accept"
    metric_flags = case_row.get("metric_flags")
    if not isinstance(metric_flags, dict):
        return False
    mapping = {
        "exact_marked_object_id_pass": "exact_marked_object_id_pass",
        "ordinal_binding_pass": "ordinal_binding_pass",
        "target_resolution_pass": "target_resolution_pass",
        "chronology_phase_pass": "chronology_phase_pass",
        "action_recall_pass": "action_recall_pass",
    }
    return bool(metric_flags.get(mapping[name], False))


def _decision_rank(value: Any) -> int:
    normalized = str(value or "").strip().lower()
    if normalized == "accept":
        return 2
    if normalized == "merge":
        return 1
    return 0


def _semantic_tuple(case_row: dict[str, Any]) -> tuple[int, ...]:
    return (
        int(_case_flag(case_row, "target_resolution_pass")),
        int(_case_flag(case_row, "chronology_phase_pass")),
        int(_case_flag(case_row, "action_recall_pass")),
        int(_case_flag(case_row, "case_strict_success")),
        int(_case_flag(case_row, "runtime_policy_decision")),
        int(_case_flag(case_row, "ordinal_binding_pass")),
        int(_case_flag(case_row, "schema_valid")),
        int(_case_flag(case_row, "json_valid")),
    )


def _integrity_tuple(case_row: dict[str, Any], *, eligible: bool) -> tuple[int, ...]:
    return (
        int(eligible),
        int(_case_flag(case_row, "json_valid")),
        int(_case_flag(case_row, "schema_valid")),
        int(_case_flag(case_row, "ordinal_binding_pass")),
        int(_case_flag(case_row, "target_resolution_pass")),
        int(_case_flag(case_row, "chronology_phase_pass")),
        int(_case_flag(case_row, "action_recall_pass")),
        int(_case_flag(case_row, "case_strict_success")),
        int(_case_flag(case_row, "runtime_policy_decision")),
    )


def _degrade_tuple(case_row: dict[str, Any], *, eligible: bool) -> tuple[int, ...]:
    return (
        int(not eligible),
        int(not _case_flag(case_row, "json_valid")),
        int(not _case_flag(case_row, "schema_valid")),
        int(not _case_flag(case_row, "ordinal_binding_pass")),
        int(not _case_flag(case_row, "target_resolution_pass")),
        int(not _case_flag(case_row, "chronology_phase_pass")),
        int(not _case_flag(case_row, "action_recall_pass")),
        int(not _case_flag(case_row, "case_strict_success")),
        int(not _case_flag(case_row, "runtime_policy_decision")),
    )


def _prediction_script(prediction_row: dict[str, Any] | None, *, field: str) -> dict[str, Any] | None:
    if not isinstance(prediction_row, dict):
        return None
    payload = prediction_row.get(field)
    return payload if isinstance(payload, dict) else None


def _load_rows_by_id(path: Path, *, key: str) -> dict[str, dict[str, Any]]:
    rows = read_jsonl(path)
    output: dict[str, dict[str, Any]] = {}
    for row in rows:
        identifier = str(row.get(key, "")).strip()
        if not identifier:
            raise Iter3CorpusBuildError(f"row missing {key} in {path}")
        if identifier in output:
            raise Iter3CorpusBuildError(f"duplicate {key}={identifier!r} in {path}")
        output[identifier] = row
    return output


def _load_prediction_rows_by_id(path: Path) -> dict[str, dict[str, Any]]:
    rows = read_jsonl(path)
    output: dict[str, dict[str, Any]] = {}
    required_fields = {"model_only_predicted_script", "end_to_end_predicted_script", "raw_output_json"}
    for row in rows:
        identifier = str(row.get("eval_case_id", "")).strip()
        if not identifier:
            raise Iter3CorpusBuildError(f"prediction row missing eval_case_id in {path}")
        if identifier in output:
            raise Iter3CorpusBuildError(f"duplicate eval_case_id={identifier!r} in {path}")
        missing = sorted(field for field in required_fields if field not in row)
        if missing:
            raise Iter3CorpusBuildError(
                f"prediction row {identifier!r} in {path} is missing dual-slice fields: {', '.join(missing)}"
            )
        output[identifier] = row
    return output


def _load_pairwise_rows_by_id(path: Path) -> dict[str, dict[str, Any]]:
    rows = read_jsonl(path)
    output: dict[str, dict[str, Any]] = {}
    for row in rows:
        identifier = str(row.get("eval_case_id", "")).strip()
        if not identifier:
            raise Iter3CorpusBuildError(f"pairwise row missing eval_case_id in {path}")
        if identifier in output:
            raise Iter3CorpusBuildError(f"duplicate eval_case_id={identifier!r} in {path}")
        output[identifier] = row
    return output


def _normalize_script(script: dict[str, Any], *, source_text: str) -> dict[str, Any]:
    output = dict(script)
    output["originalDescription"] = source_text
    return output


def _resolve_pattern_family(cir_record: dict[str, Any]) -> str:
    internal = cir_record.get("internal_metadata")
    if isinstance(internal, dict):
        pattern_family = internal.get("pattern_family")
        if isinstance(pattern_family, str) and pattern_family:
            return pattern_family
    return "unknown"


def _critical_eval_tags(eval_case: dict[str, Any], rows: list[dict[str, Any]]) -> list[str]:
    tags: set[str] = set()
    expectations = eval_case.get("eval_expectations")
    if isinstance(expectations, dict):
        critical = expectations.get("critical_eval_tags")
        if isinstance(critical, list):
            tags.update(str(item) for item in critical if str(item))
    for row in rows:
        bucket_tags = row.get("bucket_tags")
        if isinstance(bucket_tags, list):
            tags.update(str(item) for item in bucket_tags if str(item))
    return sorted(tags)


def _build_model_view(
    *,
    model_id: str,
    case_row: dict[str, Any],
    prediction_row: dict[str, Any] | None,
    pattern_name: str,
) -> _ModelCaseView:
    script = _prediction_script(prediction_row, field="model_only_predicted_script")
    end_to_end_script = _prediction_script(prediction_row, field="end_to_end_predicted_script")
    raw_output_json = _prediction_script(prediction_row, field="raw_output_json")
    canonical_ok = _is_canonical_candidate(script)
    family_ok = canonical_ok and _pattern_family_ok(pattern_name, script or {})
    eligible = canonical_ok and family_ok and bool(case_row.get("json_valid")) and bool(case_row.get("schema_valid"))
    return _ModelCaseView(
        model_id=model_id,
        case_row=case_row,
        prediction_row=prediction_row,
        script=script,
        end_to_end_script=end_to_end_script,
        raw_output_json=raw_output_json,
        canonical_ok=canonical_ok,
        family_ok=family_ok,
        eligible_for_chosen=eligible,
        semantic_tuple=_semantic_tuple(case_row),
        integrity_tuple=_integrity_tuple(case_row, eligible=eligible),
        degrade_tuple=_degrade_tuple(case_row, eligible=eligible),
    )


def _pairwise_row_supports_iter2(
    *,
    row: dict[str, Any] | None,
    baseline_view: _ModelCaseView,
    iter2_view: _ModelCaseView,
) -> bool:
    if not isinstance(row, dict):
        return False
    if str(row.get("winner", "")).strip() != "candidate":
        return False
    baseline_case = baseline_view.case_row
    iter2_case = iter2_view.case_row
    semantic_gain = any(
        int(_case_flag(iter2_case, metric_name)) > int(_case_flag(baseline_case, metric_name))
        for metric_name in (
            "exact_marked_object_id_pass",
            "target_resolution_pass",
            "chronology_phase_pass",
            "action_recall_pass",
            "case_strict_success",
        )
    )
    return (
        semantic_gain
        and
        int(bool(iter2_case.get("json_valid"))) >= int(bool(baseline_case.get("json_valid")))
        and int(bool(iter2_case.get("schema_valid"))) >= int(bool(baseline_case.get("schema_valid")))
        and int(_case_flag(iter2_case, "exact_marked_object_id_pass"))
        >= int(_case_flag(baseline_case, "exact_marked_object_id_pass"))
        and int(_case_flag(iter2_case, "ordinal_binding_pass")) >= int(_case_flag(baseline_case, "ordinal_binding_pass"))
        and _decision_rank(iter2_case.get("runtime_policy_decision"))
        >= _decision_rank(baseline_case.get("runtime_policy_decision"))
    )


def _pairwise_confirms_iter2_win(
    *,
    eval_case_id: str,
    v7_view: _ModelCaseView,
    iter1_view: _ModelCaseView,
    iter2_view: _ModelCaseView,
    iter2_vs_v7: dict[str, dict[str, Any]],
    iter2_vs_iter1: dict[str, dict[str, Any]],
) -> bool:
    return _pairwise_row_supports_iter2(
        row=iter2_vs_v7.get(eval_case_id),
        baseline_view=v7_view,
        iter2_view=iter2_view,
    ) and _pairwise_row_supports_iter2(
        row=iter2_vs_iter1.get(eval_case_id),
        baseline_view=iter1_view,
        iter2_view=iter2_view,
    )


def _select_case(
    *,
    eval_case: dict[str, Any],
    cir_record: dict[str, Any],
    model_views: dict[str, _ModelCaseView],
    critical_eval_tags: list[str],
    iter2_vs_v7: dict[str, dict[str, Any]],
    iter2_vs_iter1: dict[str, dict[str, Any]],
) -> _CaseSelection:
    sample_id = str(eval_case.get("sample_id") or "")
    pattern_name = str(cir_record.get("pattern_name") or sample_id.split("__", 1)[0] or "")
    pattern_family = _resolve_pattern_family(cir_record)
    semantic_tags = [str(item) for item in cir_record.get("semantic_tags", []) if str(item)]
    families = _family_set(
        pattern_name=pattern_name,
        semantic_tags=semantic_tags,
        critical_eval_tags=critical_eval_tags,
        pattern_family=pattern_family,
    )
    source_text = str(eval_case.get("source_text") or "").strip()
    if not source_text:
        raise Iter3CorpusBuildError(f"eval case missing source_text: {eval_case.get('eval_case_id')}")

    gold_target = eval_case.get("gold_target_json")
    if not isinstance(gold_target, dict):
        raise Iter3CorpusBuildError(f"eval case missing gold_target_json: {eval_case.get('eval_case_id')}")
    gold_target = _normalize_script(gold_target, source_text=source_text)

    v7 = model_views["dataset_v7"]
    iter1 = model_views["dataset_v7_orpo_iter1"]
    iter2 = model_views["dataset_v7_orpo_iter2"]

    other_best_semantic = max(v7.semantic_tuple, iter1.semantic_tuple)
    iter2_semantic_gain = iter2.semantic_tuple > other_best_semantic
    iter2_pairwise_confirmed = _pairwise_confirms_iter2_win(
        eval_case_id=str(eval_case["eval_case_id"]),
        v7_view=v7,
        iter1_view=iter1,
        iter2_view=iter2,
        iter2_vs_v7=iter2_vs_v7,
        iter2_vs_iter1=iter2_vs_iter1,
    )

    if iter2_semantic_gain and iter2_pairwise_confirmed and iter2.eligible_for_chosen:
        rejected_pool = [view for view in (v7, iter1) if view.script is not None]
        rejected = max(rejected_pool, key=lambda item: item.degrade_tuple) if rejected_pool else None
        return _CaseSelection(
            eval_case_id=str(eval_case["eval_case_id"]),
            sample_id=sample_id,
            pattern_name=pattern_name,
            source_text=source_text,
            critical_eval_tags=critical_eval_tags,
            chosen_source=iter2.model_id,
            chosen_json=_normalize_script(iter2.script or gold_target, source_text=source_text),
            rejected_source=rejected.model_id if rejected is not None else None,
            rejected_json=_normalize_script(rejected.script, source_text=source_text) if rejected and rejected.script else None,
            reason="iter2_semantic_gain_canonical",
            families=families,
        )

    if iter2_semantic_gain and iter2_pairwise_confirmed and not iter2.eligible_for_chosen:
        rejected_json = _normalize_script(iter2.script, source_text=source_text) if iter2.script else None
        return _CaseSelection(
            eval_case_id=str(eval_case["eval_case_id"]),
            sample_id=sample_id,
            pattern_name=pattern_name,
            source_text=source_text,
            critical_eval_tags=critical_eval_tags,
            chosen_source="gold_target_json",
            chosen_json=gold_target,
            rejected_source=iter2.model_id,
            rejected_json=rejected_json,
            reason="iter2_semantic_gain_noncanonical_fallback_to_gold",
            families=families,
        )

    eligible_views = [view for view in (v7, iter1, iter2) if view.eligible_for_chosen]
    if iter2_semantic_gain and not iter2_pairwise_confirmed:
        eligible_views = [view for view in eligible_views if view.model_id != "dataset_v7_orpo_iter2"]
    if eligible_views:
        chosen = max(eligible_views, key=lambda item: (item.integrity_tuple, item.semantic_tuple, item.model_id))
        rejected_pool = [view for view in (v7, iter1, iter2) if view.model_id != chosen.model_id and view.script is not None]
        rejected = max(rejected_pool, key=lambda item: item.degrade_tuple) if rejected_pool else None
        return _CaseSelection(
            eval_case_id=str(eval_case["eval_case_id"]),
            sample_id=sample_id,
            pattern_name=pattern_name,
            source_text=source_text,
            critical_eval_tags=critical_eval_tags,
            chosen_source=chosen.model_id,
            chosen_json=_normalize_script(chosen.script or gold_target, source_text=source_text),
            rejected_source=rejected.model_id if rejected is not None else None,
            rejected_json=_normalize_script(rejected.script, source_text=source_text) if rejected and rejected.script else None,
            reason=f"{chosen.model_id}_integrity_preserved",
            families=families,
        )

    rejected_pool = [view for view in (v7, iter1, iter2) if view.script is not None]
    rejected = max(rejected_pool, key=lambda item: item.degrade_tuple) if rejected_pool else None
    return _CaseSelection(
        eval_case_id=str(eval_case["eval_case_id"]),
        sample_id=sample_id,
        pattern_name=pattern_name,
        source_text=source_text,
        critical_eval_tags=critical_eval_tags,
        chosen_source="gold_target_json",
        chosen_json=gold_target,
        rejected_source=rejected.model_id if rejected is not None else None,
        rejected_json=_normalize_script(rejected.script, source_text=source_text) if rejected and rejected.script else None,
        reason="fallback_to_gold_no_eligible_model",
        families=families,
    )


def _disagreement(case_rows: list[dict[str, Any]]) -> bool:
    signatures: set[tuple[Any, ...]] = set()
    for row in case_rows:
        signatures.add(
            (
                bool(row.get("json_valid")),
                bool(row.get("schema_valid")),
                _case_flag(row, "ordinal_binding_pass"),
                _case_flag(row, "target_resolution_pass"),
                _case_flag(row, "chronology_phase_pass"),
                _case_flag(row, "action_recall_pass"),
                bool(row.get("case_strict_success")),
                str(row.get("runtime_policy_decision") or ""),
            )
        )
    return len(signatures) > 1


def _build_delta_sft_row(
    selection: _CaseSelection,
    *,
    cir_record: dict[str, Any],
) -> dict[str, Any]:
    messages = render_preference_messages(source_text=selection.source_text, cir_record=cir_record)
    assistant_content = canonical_json_string(selection.chosen_json)
    messages = [*messages, {"role": "assistant", "content": assistant_content}]
    normalized_source_hash = normalized_source_hash_v1(selection.source_text)
    pattern_family = _resolve_pattern_family(cir_record)
    semantic_tags = [str(item) for item in cir_record.get("semantic_tags", []) if str(item)]
    metadata = {
        "split": "",
        "task_type": "sft",
        "contract_version": str(cir_record.get("contract_version") or "sg_v7_contract_v1"),
        "correction_tier": "tier_b_deterministic_canonical"
        if selection.chosen_source == "gold_target_json"
        else "tier_iter3_curated_canonical",
        "difficulty_bucket": str(cir_record.get("difficulty_bucket") or ""),
        "graph_family_key": str(cir_record.get("graph_family_key") or ""),
        "graph_hash": str(cir_record.get("graph_hash") or ""),
        "normalized_source_hash": normalized_source_hash,
        "split_family_id": str(cir_record.get("graph_family_key") or ""),
        "sample_id": selection.sample_id,
        "pattern_name": selection.pattern_name,
        "pattern_family": pattern_family,
        "source_variant_key": str(cir_record.get("source_variant_key") or ""),
        "complexity_class": str(cir_record.get("complexity_class") or ""),
        "semantic_tags": semantic_tags,
        "critical_eval_tags": selection.critical_eval_tags,
        "source_text_token_count": token_count(selection.source_text),
        "target_json_token_count": token_count(assistant_content),
        "full_sequence_token_count": sum(token_count(str(message.get("content") or "")) for message in messages),
        "train_eligibility": "direct_sft",
        "validation_status": "accepted",
        "iter3_selection_source": selection.chosen_source,
        "iter3_selection_reason": selection.reason,
        "iter3_rejected_source": selection.rejected_source,
        "iter3_curated_case": True,
        "semantic_family_key": build_semantic_family_key(
            pattern_family=pattern_family,
            source_variant_key=str(cir_record.get("source_variant_key") or ""),
            difficulty_bucket=str(cir_record.get("difficulty_bucket") or ""),
            complexity_class=str(cir_record.get("complexity_class") or ""),
            semantic_tags=semantic_tags,
        ),
    }
    return {
        "sample_id": selection.sample_id,
        "task_type": "sft",
        "source_text": selection.source_text,
        "target_json": selection.chosen_json,
        "messages": messages,
        "critical_eval_tags": selection.critical_eval_tags,
        "packaging_metadata": metadata,
        "promoted_from_manual_review": False,
        "review_decision": None,
        "reviewed_at": None,
        "reviewer": "iter3_curator",
        "recoverability_score": 100,
        "source_text_quality_flags": [],
    }


def _build_preference_row(
    selection: _CaseSelection,
    *,
    cir_record: dict[str, Any],
) -> dict[str, Any] | None:
    if not isinstance(selection.rejected_json, dict):
        return None
    chosen = canonical_json_string(selection.chosen_json)
    rejected = canonical_json_string(selection.rejected_json)
    if chosen == rejected:
        return None
    messages = render_preference_messages(source_text=selection.source_text, cir_record=cir_record)
    normalized_source_hash = normalized_source_hash_v1(selection.source_text)
    pattern_family = _resolve_pattern_family(cir_record)
    semantic_tags = [str(item) for item in cir_record.get("semantic_tags", []) if str(item)]
    preference_id = f"iter3-pref-{selection.eval_case_id}"
    metadata = {
        "split": "",
        "task_type": "preference",
        "contract_version": str(cir_record.get("contract_version") or "sg_v7_contract_v1"),
        "preference_id": preference_id,
        "preference_origin": "iter3_disagreement_curated",
        "correction_tier": "tier_iter3_curated_canonical",
        "difficulty_bucket": str(cir_record.get("difficulty_bucket") or ""),
        "graph_family_key": str(cir_record.get("graph_family_key") or ""),
        "graph_hash": str(cir_record.get("graph_hash") or ""),
        "normalized_source_hash": normalized_source_hash,
        "split_family_id": str(cir_record.get("graph_family_key") or ""),
        "sample_id": selection.sample_id,
        "pattern_name": selection.pattern_name,
        "pattern_family": pattern_family,
        "source_variant_key": str(cir_record.get("source_variant_key") or ""),
        "complexity_class": str(cir_record.get("complexity_class") or ""),
        "semantic_tags": semantic_tags,
        "critical_eval_tags": selection.critical_eval_tags,
        "source_text_token_count": token_count(selection.source_text),
        "iter3_selection_source": selection.chosen_source,
        "iter3_selection_reason": selection.reason,
        "iter3_rejected_source": selection.rejected_source,
        "eval_case_id": selection.eval_case_id,
    }
    return {
        "preference_id": preference_id,
        "task_type": "preference",
        "messages": messages,
        "chosen": chosen,
        "rejected": rejected,
        "chosen_json": selection.chosen_json,
        "rejected_json": selection.rejected_json,
        "packaging_metadata": metadata,
        "source_text": selection.source_text,
    }


def _split_rows(
    rows: list[dict[str, Any]],
    *,
    id_key: str,
    val_ratio: float,
    seed: int,
    family_fn,
    reserve_families: set[str],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if not rows:
        return [], []
    if not 0.0 <= val_ratio < 1.0:
        raise Iter3CorpusBuildError(f"val_ratio must be in [0,1): {val_ratio!r}")
    desired_val = int(round(len(rows) * val_ratio))
    if desired_val <= 0:
        return sorted(rows, key=lambda row: str(row.get(id_key, ""))), []

    ordered = sorted(rows, key=lambda row: _stable_key(seed, f"split::{id_key}", str(row.get(id_key, ""))))
    reserved_ids: set[str] = set()
    val_rows: list[dict[str, Any]] = []

    for family in sorted(reserve_families):
        if len(val_rows) >= desired_val:
            break
        family_rows = [row for row in ordered if family in family_fn(row)]
        if len(family_rows) < 2:
            continue
        candidate = family_rows[0]
        identifier = str(candidate.get(id_key, ""))
        if identifier in reserved_ids:
            continue
        reserved_ids.add(identifier)
        val_rows.append(candidate)

    for row in ordered:
        if len(val_rows) >= desired_val:
            break
        identifier = str(row.get(id_key, ""))
        if identifier in reserved_ids:
            continue
        reserved_ids.add(identifier)
        val_rows.append(row)

    val_ids = {str(row.get(id_key, "")) for row in val_rows}
    train_rows = [row for row in ordered if str(row.get(id_key, "")) not in val_ids]
    return train_rows, val_rows


def _apply_preference_caps(
    rows: list[dict[str, Any]],
    *,
    seed: int,
    max_simple_dialogue_share: float,
) -> tuple[list[dict[str, Any]], int]:
    if not rows:
        return [], 0
    if not 0.0 < max_simple_dialogue_share <= 1.0:
        raise Iter3CorpusBuildError(
            f"max_simple_dialogue_share must be in (0,1], got {max_simple_dialogue_share!r}"
        )
    simple_rows = [
        row
        for row in rows
        if "simple_dialogue" in _family_set(
            pattern_name=str(row.get("packaging_metadata", {}).get("pattern_name") or ""),
            semantic_tags=list(row.get("packaging_metadata", {}).get("semantic_tags") or []),
            critical_eval_tags=list(row.get("packaging_metadata", {}).get("critical_eval_tags") or []),
            pattern_family=str(row.get("packaging_metadata", {}).get("pattern_family") or ""),
        )
    ]
    max_allowed = max(1, int(len(rows) * max_simple_dialogue_share))
    if len(simple_rows) <= max_allowed:
        return rows, 0
    ordered_simple = sorted(
        simple_rows,
        key=lambda row: _stable_key(seed, "iter3_simple_dialogue_cap", str(row.get("preference_id", ""))),
    )
    keep_ids = {str(row.get("preference_id", "")) for row in ordered_simple[:max_allowed]}
    simple_ids = {str(item.get("preference_id", "")) for item in simple_rows}
    kept = [
        row
        for row in rows
        if str(row.get("preference_id", "")) not in simple_ids or str(row.get("preference_id", "")) in keep_ids
    ]
    dropped = len(rows) - len(kept)
    return kept, dropped


def _family_counts(rows: list[dict[str, Any]], *, family_fn) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        for family in family_fn(row):
            counts[family] = counts.get(family, 0) + 1
    return counts


def _stable_order_rows(
    rows: list[dict[str, Any]],
    *,
    seed: int,
    tag: str,
    id_key: str,
) -> list[dict[str, Any]]:
    return sorted(
        rows,
        key=lambda row: _stable_key(seed, tag, str(row.get(id_key, ""))),
    )


def _apply_family_cap(
    rows: list[dict[str, Any]],
    *,
    id_key: str,
    seed: int,
    family_fn,
    max_family_share: float | None,
    protected_min_counts: dict[str, int] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    if not rows or max_family_share is None:
        return rows, {}
    max_share = float(max_family_share)
    if not 0 < max_share <= 1:
        raise Iter3CorpusBuildError(f"max_family_share must be in (0,1], got {max_share!r}")

    ordered_rows = _stable_order_rows(rows, seed=seed, tag=f"family_cap::{id_key}", id_key=id_key)
    row_by_id = {str(row.get(id_key, "")): row for row in ordered_rows}
    families_by_id = {row_id: family_fn(row) for row_id, row in row_by_id.items()}
    stable_rank = {row_id: index for index, row_id in enumerate(row_by_id.keys())}
    kept_ids = set(row_by_id.keys())
    protected = {str(name): int(value) for name, value in (protected_min_counts or {}).items()}
    dropped_by_family_cap: dict[str, int] = {}

    while True:
        retained_ids = [row_id for row_id in kept_ids if row_id in row_by_id]
        retained_total = len(retained_ids)
        if retained_total <= 0:
            break
        max_allowed = max(1, int(retained_total * max_share))

        current_family_counts: dict[str, int] = {}
        for row_id in retained_ids:
            for family in families_by_id.get(row_id, set()):
                current_family_counts[family] = current_family_counts.get(family, 0) + 1
        over_limit = [family for family, count in current_family_counts.items() if count > max_allowed]
        if not over_limit:
            break
        over_limit.sort(
            key=lambda family: (
                -(current_family_counts[family] - max_allowed),
                -current_family_counts[family],
                family,
            )
        )
        target_family = over_limit[0]
        over_limit_set = set(over_limit)
        candidates = []
        for row_id in retained_ids:
            row_families = families_by_id.get(row_id, set())
            if target_family not in row_families:
                continue
            if any(current_family_counts.get(family, 0) - 1 < protected.get(family, 0) for family in row_families):
                continue
            candidates.append(row_id)
        if not candidates:
            raise Iter3CorpusBuildError(
                "delta_sft_max_family_share could not identify a removable row without violating family floors: "
                f"family={target_family!r}, max_share={max_share}"
            )
        candidates.sort(
            key=lambda row_id: (
                len(families_by_id.get(row_id, set()) & over_limit_set),
                len(families_by_id.get(row_id, set())),
                stable_rank.get(row_id, -1),
                row_id,
            ),
            reverse=True,
        )
        victim_id = candidates[0]
        kept_ids.remove(victim_id)
        dropped_by_family_cap[target_family] = dropped_by_family_cap.get(target_family, 0) + 1

    kept_rows = sorted((row_by_id[row_id] for row_id in kept_ids), key=lambda row: str(row.get(id_key, "")))
    return kept_rows, dropped_by_family_cap


def _selection_family_counts(
    selections: list[_CaseSelection],
    *,
    source_name: str | None = None,
) -> dict[str, int]:
    counts: dict[str, int] = {}
    for selection in selections:
        if source_name is not None and selection.chosen_source != source_name:
            continue
        for family in selection.families:
            counts[family] = counts.get(family, 0) + 1
    return counts


def _targeted_family_gold_stats(selections: list[_CaseSelection]) -> tuple[dict[str, float], dict[str, int]]:
    total_by_family = _selection_family_counts(selections)
    gold_by_family = _selection_family_counts(selections, source_name="gold_target_json")
    share_by_family: dict[str, float] = {}
    for family in sorted(TARGETED_FAMILIES):
        total = total_by_family.get(family, 0)
        gold = gold_by_family.get(family, 0)
        share_by_family[family] = (gold / total) if total else 0.0
    return share_by_family, total_by_family


def _validate_transfer_quality(
    *,
    selections: list[_CaseSelection],
) -> list[str]:
    blockers: list[str] = []
    total = len(selections)
    if total <= 0:
        blockers.append("no_selected_cases")
        return blockers
    gold_count = sum(1 for selection in selections if selection.chosen_source == "gold_target_json")
    model_count = total - gold_count
    gold_share = gold_count / total
    model_share = model_count / total
    if gold_share > GOLD_CHOSEN_MAX_SHARE:
        blockers.append(
            f"gold_chosen_share_overall={gold_share:.3f}>{GOLD_CHOSEN_MAX_SHARE:.3f}"
        )
    if model_share < MIN_MODEL_CHOSEN_SHARE:
        blockers.append(
            f"model_chosen_share_overall={model_share:.3f}<{MIN_MODEL_CHOSEN_SHARE:.3f}"
        )

    gold_share_by_family, total_by_family = _targeted_family_gold_stats(selections)
    model_by_family = _selection_family_counts(selections)
    gold_by_family = _selection_family_counts(selections, source_name="gold_target_json")
    for family in sorted(TARGETED_FAMILIES):
        total_family = total_by_family.get(family, 0)
        gold_family = gold_by_family.get(family, 0)
        model_family = total_family - gold_family
        if total_family >= MIN_TARGETED_FAMILY_CASES_FOR_MODEL_FLOOR and gold_share_by_family[family] > GOLD_CHOSEN_MAX_FAMILY_SHARE:
            blockers.append(
                f"gold_chosen_share_by_family.{family}={gold_share_by_family[family]:.3f}>{GOLD_CHOSEN_MAX_FAMILY_SHARE:.3f}"
            )
        if total_family >= MIN_TARGETED_FAMILY_CASES_FOR_MODEL_FLOOR and model_family < MIN_MODEL_CHOSEN_PER_TARGETED_FAMILY:
            blockers.append(
                f"model_chosen_count_by_family.{family}={model_family}<{MIN_MODEL_CHOSEN_PER_TARGETED_FAMILY}"
            )
    return blockers


def _manual_review_samples(
    selections: list[_CaseSelection],
    *,
    limit_per_pattern: int,
    seed: int,
) -> dict[str, list[dict[str, Any]]]:
    output: dict[str, list[dict[str, Any]]] = {}
    for pattern_name in MANUAL_REVIEW_PATTERNS:
        matching = [
            selection
            for selection in selections
            if selection.pattern_name == pattern_name
        ]
        ordered = sorted(
            matching,
            key=lambda item: _stable_key(seed, f"manual_review::{pattern_name}", item.eval_case_id),
        )
        output[pattern_name] = [
            {
                "eval_case_id": item.eval_case_id,
                "sample_id": item.sample_id,
                "source_text": item.source_text,
                "chosen_source": item.chosen_source,
                "rejected_source": item.rejected_source,
                "reason": item.reason,
            }
            for item in ordered[:limit_per_pattern]
        ]
    return output


def build_iter3_corpus(request: Iter3CorpusBuildRequest) -> dict[str, Any]:
    eval_cases_by_id = _load_rows_by_id(request.eval_cases_jsonl, key="eval_case_id")
    cir_rows = read_jsonl(request.cir_jsonl)
    cir_by_sample = {str(row.get("sample_id") or ""): row for row in cir_rows}
    v7_case_rows = _load_rows_by_id(request.v7_case_results_jsonl, key="eval_case_id")
    iter1_case_rows = _load_rows_by_id(request.iter1_case_results_jsonl, key="eval_case_id")
    iter2_case_rows = _load_rows_by_id(request.iter2_case_results_jsonl, key="eval_case_id")
    v7_predictions = _load_prediction_rows_by_id(request.v7_predictions_jsonl)
    iter1_predictions = _load_prediction_rows_by_id(request.iter1_predictions_jsonl)
    iter2_predictions = _load_prediction_rows_by_id(request.iter2_predictions_jsonl)
    iter2_vs_iter1 = _load_pairwise_rows_by_id(request.iter2_vs_iter1_paired_jsonl)
    iter2_vs_v7 = _load_pairwise_rows_by_id(request.iter2_vs_v7_paired_jsonl)

    selected_cases: list[_CaseSelection] = []
    reason_counts: dict[str, int] = {}
    chosen_source_counts: dict[str, int] = {}
    rejected_source_counts: dict[str, int] = {}
    dropped_missing_cir: list[str] = []
    pairwise_cases_total = 0
    pairwise_iter2_confirmed_wins = 0
    pairwise_iter2_rejected_due_to_integrity = 0
    raw_vs_end_to_end_divergence_counts = {
        "dataset_v7": 0,
        "dataset_v7_orpo_iter1": 0,
        "dataset_v7_orpo_iter2": 0,
    }

    for eval_case_id in sorted(eval_cases_by_id.keys()):
        eval_case = eval_cases_by_id[eval_case_id]
        sample_id = str(eval_case.get("sample_id") or "")
        cir_record = cir_by_sample.get(sample_id)
        if cir_record is None:
            dropped_missing_cir.append(eval_case_id)
            continue
        pattern_name = str(cir_record.get("pattern_name") or sample_id.split("__", 1)[0] or "")
        case_rows = [
            v7_case_rows.get(eval_case_id),
            iter1_case_rows.get(eval_case_id),
            iter2_case_rows.get(eval_case_id),
        ]
        if any(row is None for row in case_rows):
            raise Iter3CorpusBuildError(f"missing case_results row for eval_case_id={eval_case_id!r}")
        case_rows = [row for row in case_rows if isinstance(row, dict)]
        critical_tags = _critical_eval_tags(eval_case, case_rows)
        include = (
            _disagreement(case_rows)
            or pattern_name in FORCE_INCLUDE_PATTERNS
            or "exact_marker_identity_cases" in critical_tags
        )
        if not include:
            continue
        model_views = {
            "dataset_v7": _build_model_view(
                model_id="dataset_v7",
                case_row=v7_case_rows[eval_case_id],
                prediction_row=v7_predictions.get(eval_case_id),
                pattern_name=pattern_name,
            ),
            "dataset_v7_orpo_iter1": _build_model_view(
                model_id="dataset_v7_orpo_iter1",
                case_row=iter1_case_rows[eval_case_id],
                prediction_row=iter1_predictions.get(eval_case_id),
                pattern_name=pattern_name,
            ),
            "dataset_v7_orpo_iter2": _build_model_view(
                model_id="dataset_v7_orpo_iter2",
                case_row=iter2_case_rows[eval_case_id],
                prediction_row=iter2_predictions.get(eval_case_id),
                pattern_name=pattern_name,
            ),
        }
        if eval_case_id in iter2_vs_iter1 and eval_case_id in iter2_vs_v7:
            pairwise_cases_total += 1
        for view in model_views.values():
            if _scripts_differ(view.script, view.end_to_end_script):
                raw_vs_end_to_end_divergence_counts[view.model_id] = (
                    raw_vs_end_to_end_divergence_counts.get(view.model_id, 0) + 1
                )
        if _pairwise_confirms_iter2_win(
            eval_case_id=eval_case_id,
            v7_view=model_views["dataset_v7"],
            iter1_view=model_views["dataset_v7_orpo_iter1"],
            iter2_view=model_views["dataset_v7_orpo_iter2"],
            iter2_vs_v7=iter2_vs_v7,
            iter2_vs_iter1=iter2_vs_iter1,
        ):
            pairwise_iter2_confirmed_wins += 1
        elif _pairwise_row_supports_iter2(
            row=iter2_vs_v7.get(eval_case_id),
            baseline_view=model_views["dataset_v7"],
            iter2_view=model_views["dataset_v7_orpo_iter2"],
        ) and _pairwise_row_supports_iter2(
            row=iter2_vs_iter1.get(eval_case_id),
            baseline_view=model_views["dataset_v7_orpo_iter1"],
            iter2_view=model_views["dataset_v7_orpo_iter2"],
        ) and not model_views["dataset_v7_orpo_iter2"].eligible_for_chosen:
            pairwise_iter2_rejected_due_to_integrity += 1
        selection = _select_case(
            eval_case=eval_case,
            cir_record=cir_record,
            model_views=model_views,
            critical_eval_tags=critical_tags,
            iter2_vs_v7=iter2_vs_v7,
            iter2_vs_iter1=iter2_vs_iter1,
        )
        selected_cases.append(selection)
        reason_counts[selection.reason] = reason_counts.get(selection.reason, 0) + 1
        chosen_source_counts[selection.chosen_source] = chosen_source_counts.get(selection.chosen_source, 0) + 1
        if selection.rejected_source:
            rejected_source_counts[selection.rejected_source] = rejected_source_counts.get(selection.rejected_source, 0) + 1

    transfer_quality_blockers = _validate_transfer_quality(selections=selected_cases)
    gold_share_by_family, total_selected_by_family = _targeted_family_gold_stats(selected_cases)
    gold_selected_by_family = _selection_family_counts(selected_cases, source_name="gold_target_json")
    gold_count = chosen_source_counts.get("gold_target_json", 0)
    model_count = len(selected_cases) - gold_count

    delta_rows = [_build_delta_sft_row(selection, cir_record=cir_by_sample[selection.sample_id]) for selection in selected_cases]
    preference_rows_raw = [
        _build_preference_row(selection, cir_record=cir_by_sample[selection.sample_id])
        for selection in selected_cases
    ]
    preference_rows = [row for row in preference_rows_raw if isinstance(row, dict)]
    dropped_missing_preference = len(preference_rows_raw) - len(preference_rows)
    preference_rows, dropped_simple_dialogue = _apply_preference_caps(
        preference_rows,
        seed=request.seed,
        max_simple_dialogue_share=request.max_simple_dialogue_share,
    )

    family_floor = request.min_family_counts if request.min_family_counts is not None else {
        "exact_marker_identity": 4,
        "three_beat": 8,
        "ordinal": 4,
        "give_to_third_actor": 4,
        "open_then_pick_up": 4,
    }

    def _row_families(row: dict[str, Any]) -> set[str]:
        meta = row.get("packaging_metadata", {})
        return _family_set(
            pattern_name=str(meta.get("pattern_name") or ""),
            semantic_tags=list(meta.get("semantic_tags") or []),
            critical_eval_tags=list(meta.get("critical_eval_tags") or []),
            pattern_family=str(meta.get("pattern_family") or ""),
        )

    delta_rows_before_family_cap = len(delta_rows)
    delta_rows, delta_dropped_by_family_cap = _apply_family_cap(
        delta_rows,
        id_key="sample_id",
        seed=request.seed,
        family_fn=_row_families,
        max_family_share=request.delta_sft_max_family_share,
        protected_min_counts=family_floor,
    )
    delta_family_counts = _family_counts(delta_rows, family_fn=_row_families)
    missing_delta_families = {
        family: (delta_family_counts.get(family, 0), required)
        for family, required in sorted(family_floor.items())
        if delta_family_counts.get(family, 0) < required
    }
    if missing_delta_families:
        details = ", ".join(
            f"{family}={current}<{required}"
            for family, (current, required) in missing_delta_families.items()
        )
        raise Iter3CorpusBuildError(f"iter3 delta_sft family coverage below configured minimum: {details}")

    preference_family_counts = _family_counts(preference_rows, family_fn=_row_families)
    missing_families = {
        family: (preference_family_counts.get(family, 0), required)
        for family, required in sorted(family_floor.items())
        if preference_family_counts.get(family, 0) < required
    }
    if missing_families:
        details = ", ".join(f"{family}={current}<{required}" for family, (current, required) in missing_families.items())
        raise Iter3CorpusBuildError(f"iter3 preference family coverage below configured minimum: {details}")

    delta_train, delta_val = _split_rows(
        delta_rows,
        id_key="sample_id",
        val_ratio=request.delta_sft_val_ratio,
        seed=request.seed,
        family_fn=_row_families,
        reserve_families={"exact_marker_identity", "three_beat", "ordinal", "give_to_third_actor", "open_then_pick_up"},
    )
    pref_train, pref_val = _split_rows(
        preference_rows,
        id_key="preference_id",
        val_ratio=request.preference_val_ratio,
        seed=request.seed,
        family_fn=_row_families,
        reserve_families={"exact_marker_identity", "three_beat", "ordinal", "give_to_third_actor", "open_then_pick_up"},
    )

    manifest = {
        "seed": request.seed,
        "prediction_source_policy": {
            "requires_dual_slice": True,
            "selection_slice": "model_only_predicted_script",
            "analysis_slice": "end_to_end_predicted_script",
            "legacy_predicted_script_allowed": False,
        },
        "inputs": {
            "eval_cases_jsonl": str(request.eval_cases_jsonl),
            "cir_jsonl": str(request.cir_jsonl),
            "v7_case_results_jsonl": str(request.v7_case_results_jsonl),
            "iter1_case_results_jsonl": str(request.iter1_case_results_jsonl),
            "iter2_case_results_jsonl": str(request.iter2_case_results_jsonl),
            "v7_predictions_jsonl": str(request.v7_predictions_jsonl),
            "iter1_predictions_jsonl": str(request.iter1_predictions_jsonl),
            "iter2_predictions_jsonl": str(request.iter2_predictions_jsonl),
            "iter2_vs_iter1_paired_jsonl": str(request.iter2_vs_iter1_paired_jsonl),
            "iter2_vs_v7_paired_jsonl": str(request.iter2_vs_v7_paired_jsonl),
        },
        "counts": {
            "selected_cases": len(selected_cases),
            "delta_sft_total": len(delta_rows),
            "delta_sft_total_before_family_cap": delta_rows_before_family_cap,
            "delta_sft_train": len(delta_train),
            "delta_sft_val": len(delta_val),
            "preference_total": len(preference_rows),
            "preference_train": len(pref_train),
            "preference_val": len(pref_val),
            "dropped_missing_cir": len(dropped_missing_cir),
            "dropped_missing_preference": dropped_missing_preference,
            "dropped_simple_dialogue": dropped_simple_dialogue,
        },
        "selection_reason_counts": reason_counts,
        "chosen_source_counts": chosen_source_counts,
        "rejected_source_counts": rejected_source_counts,
        "delta_family_counts": delta_family_counts,
        "delta_dropped_by_family_cap": delta_dropped_by_family_cap,
        "preference_family_counts": preference_family_counts,
        "pairwise_cases_total": pairwise_cases_total,
        "pairwise_iter2_confirmed_wins": pairwise_iter2_confirmed_wins,
        "pairwise_iter2_rejected_due_to_integrity": pairwise_iter2_rejected_due_to_integrity,
        "raw_vs_end_to_end_divergence_counts": raw_vs_end_to_end_divergence_counts,
        "gold_chosen_share_overall": (gold_count / len(selected_cases)) if selected_cases else 0.0,
        "model_chosen_share_overall": (model_count / len(selected_cases)) if selected_cases else 0.0,
        "gold_chosen_share_by_family": gold_share_by_family,
        "selection_family_counts": total_selected_by_family,
        "model_chosen_count_by_family": {
            family: total_selected_by_family.get(family, 0) - gold_selected_by_family.get(family, 0)
            for family in sorted(TARGETED_FAMILIES)
        },
        "configured_family_floors": family_floor,
        "delta_sft_max_family_share": request.delta_sft_max_family_share,
        "manual_review_patterns": list(MANUAL_REVIEW_PATTERNS),
        "force_include_patterns": sorted(FORCE_INCLUDE_PATTERNS),
        "dropped_missing_cir_case_ids": dropped_missing_cir,
        "gate_status": "fail" if transfer_quality_blockers else "pass",
        "gate_blockers": transfer_quality_blockers,
    }

    output_dir = request.output_dir
    review_samples = _manual_review_samples(
        selected_cases,
        limit_per_pattern=request.manual_review_samples_per_pattern,
        seed=request.seed,
    )
    write_json(review_samples, output_dir / "iter3_manual_review_samples.json")
    write_json(manifest, output_dir / "iter3_manifest.json")
    if transfer_quality_blockers:
        raise Iter3CorpusBuildError(
            "iter3 transfer quality gate failed: " + "; ".join(transfer_quality_blockers)
        )

    write_jsonl(delta_rows, output_dir / "iter3_delta_sft.jsonl")
    write_jsonl(delta_train, output_dir / "iter3_delta_sft_train.jsonl")
    write_jsonl(delta_val, output_dir / "iter3_delta_sft_val.jsonl")
    write_jsonl(preference_rows, output_dir / "iter3_preference.jsonl")
    write_jsonl(pref_train, output_dir / "iter3_preference_train.jsonl")
    write_jsonl(pref_val, output_dir / "iter3_preference_val.jsonl")
    return manifest
