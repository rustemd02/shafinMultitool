#!/usr/bin/env python3
"""Deterministic eval adapters for candidate and legacy baseline."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple


SUGGESTION_PRIORITY: Dict[str, int] = {
    "horizon": 0,
    "exposure": 1,
    "composition": 2,
    "lighting": 3,
    "lens": 4,
    "other": 5,
}

SUGGESTION_TO_ACTION: Dict[str, str] = {
    "horizon": "level_horizon",
    "exposure": "improve_front_light",
    "lighting": "improve_front_light",
    "composition": "move_frame_left",
    "lens": "increase_subject_size",
    "other": "change_angle",
}

SUGGESTION_TO_ISSUE: Dict[str, str] = {
    "horizon": "horizon_distracts",
    "composition": "subject_too_close_to_edge",
    "lighting": "subject_not_prominent_enough",
    "exposure": "subject_not_prominent_enough",
    "lens": "subject_not_prominent_enough",
    "other": "scene_has_no_clear_focus",
}

ISSUE_TO_ACTION: Dict[str, str] = {
    "subject_too_close_to_edge": "move_frame_left",
    "insufficient_look_space": "move_frame_left",
    "subject_not_prominent_enough": "increase_subject_size",
    "background_competes_with_subject": "reduce_background_distractions",
    "backlight_hides_subject": "improve_front_light",
    "scene_has_no_clear_focus": "change_angle",
    "frame_visually_overloaded": "change_angle",
    "horizon_distracts": "level_horizon",
}

ISSUE_TO_FIX_TYPE: Dict[str, str] = {
    "subject_too_close_to_edge": "reframing",
    "insufficient_look_space": "reframing",
    "subject_not_prominent_enough": "reframing",
    "background_competes_with_subject": "angle_adjustment",
    "backlight_hides_subject": "lighting_adjustment",
    "scene_has_no_clear_focus": "angle_adjustment",
    "frame_visually_overloaded": "angle_adjustment",
    "horizon_distracts": "horizon_correction",
}


def _pick(mapping: Dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in mapping:
            return mapping[key]
    return default


def _get_path(mapping: Dict[str, Any], paths: Sequence[Tuple[str, ...]], default: Any = None) -> Any:
    for path in paths:
        current: Any = mapping
        ok = True
        for key in path:
            if not isinstance(current, dict) or key not in current:
                ok = False
                break
            current = current[key]
        if ok:
            return current
    return default


def _as_float(value: Any, default: float = 0.0) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    return default


def _as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    return default


def _as_list(value: Any) -> List[Any]:
    return list(value) if isinstance(value, list) else []


def _mode_for_case(case: Dict[str, Any]) -> str:
    kind = case.get("case_kind")
    if kind == "single_frame_live" or kind == "live_sequence":
        return "live"
    return "pause"


def _frame_id_for_input(case: Dict[str, Any], frame: Optional[Dict[str, Any]] = None) -> str:
    if frame is not None:
        snapshot = _pick(frame, "featureSnapshot", "feature_snapshot", default={}) or {}
        return str(_pick(snapshot, "frameId", "frame_id", default=f"{case['eval_case_id']}_frame"))
    base_input = case.get("input", {})
    snapshot = _pick(base_input, "feature_snapshot", "featureSnapshot", default={}) or {}
    return str(_pick(snapshot, "frameId", "frame_id", default=f"{case['eval_case_id']}_frame"))


@dataclass
class LegacySuggestion:
    suggestion_type: str
    reason: str


class LegacyFeatureAdapter:
    """Deterministic map FrameFeatureSnapshot -> legacy CoachingFeatures-like dict."""

    @staticmethod
    def adapt(snapshot: Dict[str, Any]) -> Dict[str, Any]:
        composition = snapshot.get("composition", {})
        horizon = snapshot.get("horizon", {})
        lighting = snapshot.get("lighting", {})
        motion = snapshot.get("motion", {})
        subject = snapshot.get("subjectSignals", {})
        aesthetics = snapshot.get("aesthetics", {})

        return {
            "composition": {
                "horizontalOffset": _as_float(_pick(composition, "horizontalOffset", "horizontal_offset", default=0.0)),
                "verticalOffset": _as_float(_pick(composition, "verticalOffset", "vertical_offset", default=0.0)),
                "saliencyLeftRightBalance": _as_float(
                    _pick(composition, "saliencyLeftRightBalance", "saliency_left_right_balance", default=0.0)
                ),
                "saliencyTopBottomBalance": _as_float(
                    _pick(composition, "saliencyTopBottomBalance", "saliency_top_bottom_balance", default=0.0)
                ),
                "subjectAreaRatio": _as_float(_pick(composition, "subjectAreaRatio", "subject_area_ratio", default=0.0)),
            },
            "horizon": {
                "angle": _as_float(_pick(horizon, "angleDegrees", "angle_degrees", default=0.0)),
                "confidence": _as_float(_pick(horizon, "confidence", default=0.0)),
            },
            "lighting": {
                "backlightIndex": _as_float(_pick(lighting, "backlightIndex", "backlight_index", default=0.0)),
                "keyToFillRatio": _as_float(_pick(lighting, "keyToFillRatio", "key_to_fill_ratio", default=1.0), default=1.0),
                "exposureBiasHint": _as_float(_pick(lighting, "exposureBiasHint", "exposure_bias_hint", default=0.0)),
            },
            "motion": {
                "state": str(_pick(motion, "state", default="still")),
                "shakeLevel": _as_float(_pick(motion, "shakeLevel", "shake_level", default=0.0)),
            },
            "subject": {
                "isFace": _as_bool(_pick(subject, "faceDetected", "face_detected", default=False)),
                "isPerson": _as_bool(_pick(subject, "personDetected", "person_detected", default=False)),
                "count": int(_pick(subject, "personCount", "person_count", default=0) or 0),
                "objectName": _pick(subject, "topObjectLabel", "top_object_label", default=None),
            },
            "aestheticScore": _pick(aesthetics, "score", default=None),
        }


class LegacySuggestionEngineAdapter:
    """Small deterministic legacy emulator for eval baseline mode."""

    def __init__(self) -> None:
        self.horizon_threshold = 2.5
        self.composition_threshold = 0.15
        self.backlight_threshold = 0.35
        self.exposure_threshold = 0.25

    def ranked_suggestions(self, features: Dict[str, Any]) -> List[LegacySuggestion]:
        candidates = self._candidates(features)
        return sorted(candidates, key=lambda x: SUGGESTION_PRIORITY.get(x.suggestion_type, 999))

    def next_suggestion(self, features: Dict[str, Any]) -> Tuple[Optional[LegacySuggestion], str]:
        motion_state = str(_get_path(features, [("motion", "state")], default="still"))
        if motion_state != "still":
            return None, "hidden_due_to_motion"
        ranked = self.ranked_suggestions(features)
        if not ranked:
            return None, "no_suggestion"
        return ranked[0], "visible_suggestion"

    def _candidates(self, features: Dict[str, Any]) -> List[LegacySuggestion]:
        out: List[LegacySuggestion] = []
        exposure = _as_float(_get_path(features, [("lighting", "exposureBiasHint")], default=0.0))
        if abs(exposure) >= self.exposure_threshold:
            out.append(LegacySuggestion("exposure", "exposure_bias_threshold_crossed"))

        horizon_angle = _as_float(_get_path(features, [("horizon", "angle")], default=0.0))
        if abs(horizon_angle) >= self.horizon_threshold:
            out.append(LegacySuggestion("horizon", "horizon_threshold_crossed"))

        horizontal = _as_float(_get_path(features, [("composition", "horizontalOffset")], default=0.0))
        vertical = _as_float(_get_path(features, [("composition", "verticalOffset")], default=0.0))
        if abs(horizontal) >= self.composition_threshold or abs(vertical) >= self.composition_threshold * 1.3:
            out.append(LegacySuggestion("composition", "composition_offset_threshold_crossed"))

        backlight = _as_float(_get_path(features, [("lighting", "backlightIndex")], default=0.0))
        if backlight >= self.backlight_threshold:
            out.append(LegacySuggestion("lighting", "backlight_threshold_crossed"))

        subject_area = _as_float(_get_path(features, [("composition", "subjectAreaRatio")], default=0.0))
        if subject_area > 0.0 and subject_area < 0.08:
            out.append(LegacySuggestion("lens", "subject_area_too_small"))

        return out


class LegacyEvalAdapter:
    """Deterministic projection into eval-normalized output."""

    def project(
        self,
        case_id: str,
        mode: str,
        snapshot: Dict[str, Any],
        semantics: Dict[str, Any],
        suggestion: Optional[LegacySuggestion],
        fallback_state: str,
    ) -> Dict[str, Any]:
        suggestion_type = suggestion.suggestion_type if suggestion else None
        primary_action = SUGGESTION_TO_ACTION.get(suggestion_type) if suggestion_type else None
        issue_types = self._map_proxy_issues(suggestion_type, snapshot, semantics)
        proxy_verdict = self._map_proxy_verdict(mode, suggestion_type, fallback_state)

        trace_items: List[Dict[str, Any]] = []
        if suggestion_type is not None:
            issue_id = f"{case_id}:issue:{issue_types[0]}" if issue_types else None
            action_id = f"{case_id}:action:{primary_action}" if primary_action else None
            obs_id = f"{case_id}:trace:observation:{suggestion_type}"
            int_id = f"{case_id}:trace:interpretation:{suggestion_type}"
            rec_id = f"{case_id}:trace:recommendation:{suggestion_type}"
            summary_id = f"{case_id}:summary"

            trace_items.append(
                {
                    "id": obs_id,
                    "stage": "observation",
                    "sourceKind": "snapshot_signal",
                    "statement": f"legacy threshold crossed for {suggestion_type}",
                    "evidenceKeys": self._observation_evidence_for_suggestion(suggestion_type),
                    "dependsOn": [],
                    "links": [],
                }
            )
            trace_items.append(
                {
                    "id": int_id,
                    "stage": "interpretation",
                    "sourceKind": "deterministic_rule",
                    "statement": f"legacy heuristic raised {suggestion_type}",
                    "evidenceKeys": [f"rule.legacy.{suggestion_type}"],
                    "dependsOn": [obs_id],
                    "links": [{"kind": "issue", "refId": issue_id}] if issue_id else [],
                }
            )
            links = [{"kind": "summary", "refId": summary_id}]
            if action_id:
                links.append({"kind": "action", "refId": action_id})
            trace_items.append(
                {
                    "id": rec_id,
                    "stage": "recommendation",
                    "sourceKind": "planner_policy",
                    "statement": f"legacy primary action {primary_action or 'none'}",
                    "evidenceKeys": [f"planner.legacy.{suggestion_type}"],
                    "dependsOn": [int_id],
                    "links": links,
                }
            )

        issue_records: List[Dict[str, Any]] = []
        for issue_type in issue_types:
            issue_records.append(
                {
                    "id": f"{case_id}:issue:{issue_type}",
                    "type": issue_type,
                    "severity": 0.68,
                    "confidence": 0.72,
                    "suggestedFixTypes": [ISSUE_TO_FIX_TYPE.get(issue_type, "angle_adjustment")],
                }
            )

        summary_id = f"{case_id}:summary"
        critique = {
            "frameId": _pick(snapshot, "frameId", "frame_id", default=case_id),
            "mode": mode,
            "verdict": proxy_verdict,
            "verdictConfidence": 0.55 if fallback_state == "hidden_due_to_motion" else 0.64,
            "issues": issue_records,
            "strengths": [],
            "summary": {
                "id": summary_id,
                "shortVerdict": f"legacy {proxy_verdict}",
                "whyGood": "legacy no major issue" if proxy_verdict == "good" else None,
                "whyProblematic": "legacy heuristic found issues" if proxy_verdict != "good" else None,
            },
            "traceRefs": [item["id"] for item in trace_items if item["stage"] == "recommendation"],
            "fallbackUsed": fallback_state != "visible_suggestion",
        }

        action_record = None
        if primary_action is not None:
            linked_ids = [issue_records[0]["id"]] if issue_records else []
            action_record = {
                "id": f"{case_id}:action:{primary_action}",
                "actionType": primary_action,
                "linkedIssueIds": linked_ids,
                "expectedOutcome": f"legacy action: {primary_action}",
                "guardrail": {
                    "requiresStillCamera": mode == "live",
                    "minConfidence": 0.4,
                    "suppressWhenMoving": mode == "live",
                },
            }

        plan = {
            "frameId": critique["frameId"],
            "mode": mode,
            "inputVerdict": proxy_verdict,
            "primaryAction": action_record,
            "secondaryActions": [],
            "deferredActions": [],
            "noChangeRationale": "legacy no change" if action_record is None else None,
            "planConfidence": 0.58,
        }

        if fallback_state == "hidden_due_to_motion":
            hint_state = "hidden_due_to_motion"
            hint_action = None
        elif action_record is None and mode == "pause":
            hint_state = "confirm_good_frame"
            hint_action = None
        elif action_record is None:
            hint_state = "hidden_due_to_low_confidence"
            hint_action = None
        else:
            hint_state = "visible_action"
            hint_action = action_record["actionType"]

        return {
            "critique_report": critique,
            "recommendation_plan": plan,
            "explainability_trace": {
                "frameId": critique["frameId"],
                "mode": mode,
                "items": trace_items,
                "rootSummaryIds": [item["id"] for item in trace_items if item["stage"] == "recommendation"][:1],
            },
            "live_hint_projection": {"hintState": hint_state, "primaryAction": hint_action},
        }

    def _map_proxy_issues(
        self,
        suggestion_type: Optional[str],
        snapshot: Dict[str, Any],
        semantics: Dict[str, Any],
    ) -> List[str]:
        if suggestion_type is None:
            return []
        if suggestion_type == "composition":
            look_space = _get_path(
                semantics,
                [("readability", "lookSpaceAdequate"), ("readability", "look_space_adequate")],
                default=None,
            )
            subject_kind = _get_path(
                semantics,
                [("primarySubject", "kind"), ("primary_subject", "kind")],
                default="unknown",
            )
            if look_space is False and subject_kind in {"face", "person", "group"}:
                return ["insufficient_look_space"]
            return ["subject_too_close_to_edge"]
        if suggestion_type in {"lighting", "exposure"}:
            backlight = _get_path(snapshot, [("lighting", "backlightIndex"), ("lighting", "backlight_index")], default=0.0)
            if _as_float(backlight) >= 0.35:
                return ["backlight_hides_subject"]
            return ["subject_not_prominent_enough"]
        return [SUGGESTION_TO_ISSUE.get(suggestion_type, "scene_has_no_clear_focus")]

    def _map_proxy_verdict(self, mode: str, suggestion_type: Optional[str], fallback_state: str) -> str:
        if fallback_state == "hidden_due_to_motion":
            return "mixed"
        if suggestion_type is None:
            return "good"
        if suggestion_type in {"horizon", "composition", "lighting", "exposure"}:
            return "needs_fix"
        return "mixed"

    def _observation_evidence_for_suggestion(self, suggestion_type: str) -> List[str]:
        if suggestion_type == "horizon":
            return ["snapshot.horizon.angleDegrees", "snapshot.horizon.confidence"]
        if suggestion_type in {"lighting", "exposure"}:
            return ["snapshot.lighting.backlightIndex", "snapshot.lighting.exposureBiasHint"]
        if suggestion_type == "composition":
            return ["snapshot.composition.horizontalOffset", "snapshot.composition.verticalOffset"]
        return ["snapshot.composition.subjectAreaRatio"]


class LegacyBaselineRunner:
    """End-to-end baseline runner: FeatureAdapter + LegacySuggestionEngine + LegacyEvalAdapter."""

    def __init__(self) -> None:
        self.feature_adapter = LegacyFeatureAdapter()
        self.eval_adapter = LegacyEvalAdapter()

    def run_case(self, case: Dict[str, Any]) -> Dict[str, Any]:
        case_kind = case.get("case_kind")
        if case_kind == "live_sequence":
            return self._run_sequence_case(case)
        return self._run_single_frame_case(case)

    def _run_single_frame_case(self, case: Dict[str, Any]) -> Dict[str, Any]:
        mode = _mode_for_case(case)
        base_input = case.get("input", {})
        snapshot = _pick(base_input, "feature_snapshot", "featureSnapshot", default={}) or {}
        semantics = _pick(base_input, "scene_semantics", "sceneSemantics", default={}) or {}
        features = self.feature_adapter.adapt(snapshot)
        engine = LegacySuggestionEngineAdapter()

        if mode == "pause":
            ranked = engine.ranked_suggestions(features)
            suggestion = ranked[0] if ranked else None
            fallback_state = "visible_suggestion" if suggestion else "no_suggestion"
        else:
            suggestion, fallback_state = engine.next_suggestion(features)

        return self.eval_adapter.project(
            case_id=case["eval_case_id"],
            mode=mode,
            snapshot=snapshot,
            semantics=semantics,
            suggestion=suggestion,
            fallback_state=fallback_state,
        )

    def _run_sequence_case(self, case: Dict[str, Any]) -> Dict[str, Any]:
        mode = "live"
        engine = LegacySuggestionEngineAdapter()
        frame_outputs: List[Dict[str, Any]] = []
        final_output: Dict[str, Any] = {}

        for frame in sorted(case.get("sequence", []), key=lambda item: item.get("frameOrdinal", 0)):
            snapshot = _pick(frame, "featureSnapshot", "feature_snapshot", default={}) or {}
            semantics = _pick(frame, "sceneSemantics", "scene_semantics", default={}) or {}
            features = self.feature_adapter.adapt(snapshot)
            suggestion, fallback_state = engine.next_suggestion(features)
            projected = self.eval_adapter.project(
                case_id=f"{case['eval_case_id']}:f{frame.get('frameOrdinal', 0)}",
                mode=mode,
                snapshot=snapshot,
                semantics=semantics,
                suggestion=suggestion,
                fallback_state=fallback_state,
            )
            frame_outputs.append(
                {
                    "frameOrdinal": frame.get("frameOrdinal"),
                    "hintState": _get_path(projected, [("live_hint_projection", "hintState")], default=None),
                    "primaryAction": _get_path(projected, [("live_hint_projection", "primaryAction")], default=None),
                }
            )
            final_output = projected

        merged = dict(final_output)
        merged["frame_outputs"] = frame_outputs
        return merged


class CandidateDeterministicRunner:
    """Rule-based candidate simulator for local reproducible eval runs."""

    def run_case(self, case: Dict[str, Any]) -> Dict[str, Any]:
        case_kind = case.get("case_kind")
        if case_kind == "live_sequence":
            return self._run_sequence_case(case)
        mode = _mode_for_case(case)
        base_input = case.get("input", {})
        snapshot = _pick(base_input, "feature_snapshot", "featureSnapshot", default={}) or {}
        semantics = _pick(base_input, "scene_semantics", "sceneSemantics", default={}) or {}
        frame_id = _frame_id_for_input(case)
        return self._analyze_frame(case["eval_case_id"], frame_id, mode, snapshot, semantics)

    def _run_sequence_case(self, case: Dict[str, Any]) -> Dict[str, Any]:
        frame_outputs: List[Dict[str, Any]] = []
        final_output: Dict[str, Any] = {}
        for frame in sorted(case.get("sequence", []), key=lambda item: item.get("frameOrdinal", 0)):
            snapshot = _pick(frame, "featureSnapshot", "feature_snapshot", default={}) or {}
            semantics = _pick(frame, "sceneSemantics", "scene_semantics", default={}) or {}
            frame_id = _frame_id_for_input(case, frame=frame)
            case_frame_id = f"{case['eval_case_id']}:f{frame.get('frameOrdinal', 0)}"
            analyzed = self._analyze_frame(case_frame_id, frame_id, "live", snapshot, semantics)
            frame_outputs.append(
                {
                    "frameOrdinal": frame.get("frameOrdinal"),
                    "hintState": _get_path(analyzed, [("live_hint_projection", "hintState")], default=None),
                    "primaryAction": _get_path(analyzed, [("live_hint_projection", "primaryAction")], default=None),
                }
            )
            final_output = analyzed
        merged = dict(final_output)
        merged["frame_outputs"] = frame_outputs
        return merged

    def _analyze_frame(
        self,
        case_id: str,
        frame_id: str,
        mode: str,
        snapshot: Dict[str, Any],
        semantics: Dict[str, Any],
    ) -> Dict[str, Any]:
        issues = self._detect_issues(case_id, snapshot, semantics)
        strengths = self._detect_strengths(case_id, snapshot, semantics)
        fallback_used = self._fallback_used(snapshot)
        verdict = self._aggregate_verdict(issues, fallback_used)
        summary = self._build_summary(case_id, verdict, issues, strengths)
        action = self._build_primary_action(case_id, verdict, issues, snapshot, mode)
        plan = self._build_plan(frame_id, mode, verdict, action)
        trace = self._build_trace(frame_id, mode, summary["id"], issues, strengths, action)

        critique = {
            "frameId": frame_id,
            "mode": mode,
            "verdict": verdict,
            "verdictConfidence": 0.83 if verdict == "good" else 0.79,
            "issues": issues,
            "strengths": strengths,
            "summary": summary,
            "traceRefs": [item["id"] for item in trace["items"] if item["stage"] == "recommendation"],
            "fallbackUsed": fallback_used,
        }
        hint_state, hint_action = self._derive_hint(mode, snapshot, fallback_used, verdict, action)

        return {
            "critique_report": critique,
            "recommendation_plan": plan,
            "explainability_trace": trace,
            "live_hint_projection": {"hintState": hint_state, "primaryAction": hint_action},
        }

    def _detect_issues(
        self,
        case_id: str,
        snapshot: Dict[str, Any],
        semantics: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        composition = snapshot.get("composition", {})
        lighting = snapshot.get("lighting", {})
        horizon = snapshot.get("horizon", {})
        objects = snapshot.get("objects", {})
        readability = semantics.get("readability", {})
        dominance = semantics.get("dominance", {})
        primary_subject = semantics.get("primarySubject", {})
        subject_signals = snapshot.get("subjectSignals", {})

        issue_types: List[str] = []
        horizontal_offset = abs(_as_float(_pick(composition, "horizontalOffset", default=0.0)))
        edge_pressure = _as_float(_pick(readability, "edgePressureScore", default=0.0))
        if horizontal_offset >= 0.75 or edge_pressure >= 0.82:
            issue_types.append("subject_too_close_to_edge")

        look_space_adequate = _pick(readability, "lookSpaceAdequate", default=None)
        if look_space_adequate is False and _pick(primary_subject, "kind", default="unknown") in {"face", "person", "group"}:
            issue_types.append("insufficient_look_space")

        backlight = _as_float(_pick(lighting, "backlightIndex", default=0.0))
        if backlight >= 0.35:
            issue_types.append("backlight_hides_subject")

        focus_competition = _as_float(_pick(dominance, "focusCompetitionScore", default=0.0))
        has_clear_focus = _as_bool(_pick(dominance, "hasClearFocus", default=True), default=True)
        if not has_clear_focus or focus_competition >= 0.68:
            issue_types.append("scene_has_no_clear_focus")

        clutter = _as_float(_pick(dominance, "backgroundClutterScore", default=0.0))
        if clutter >= 0.68:
            issue_types.append("background_competes_with_subject")

        horizon_angle = abs(_as_float(_pick(horizon, "angleDegrees", default=0.0)))
        horizon_conf = _as_float(_pick(horizon, "confidence", default=0.0))
        if horizon_angle >= 2.0 and horizon_conf >= 0.7:
            issue_types.append("horizon_distracts")

        subject_area = _as_float(_pick(composition, "subjectAreaRatio", default=0.0))
        face_detected = _as_bool(_pick(subject_signals, "faceDetected", default=False))
        if subject_area > 0.0 and subject_area < 0.08 and not face_detected:
            issue_types.append("subject_not_prominent_enough")

        if int(_pick(objects, "totalCount", default=0) or 0) >= 8 and clutter >= 0.6:
            issue_types.append("frame_visually_overloaded")

        unique_types = sorted(set(issue_types))
        records: List[Dict[str, Any]] = []
        for issue_type in unique_types:
            confidence = 0.74 if issue_type in {"subject_too_close_to_edge", "backlight_hides_subject"} else 0.68
            severity = 0.72 if issue_type in {"subject_too_close_to_edge", "insufficient_look_space", "backlight_hides_subject"} else 0.58
            records.append(
                {
                    "id": f"{case_id}:issue:{issue_type}",
                    "type": issue_type,
                    "severity": severity,
                    "confidence": confidence,
                    "suggestedFixTypes": [ISSUE_TO_FIX_TYPE[issue_type]],
                }
            )
        return records

    def _detect_strengths(
        self,
        case_id: str,
        snapshot: Dict[str, Any],
        semantics: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        composition = snapshot.get("composition", {})
        lighting = snapshot.get("lighting", {})
        horizon = snapshot.get("horizon", {})
        readability = semantics.get("readability", {})
        dominance = semantics.get("dominance", {})

        strengths: Set[str] = set()
        if _as_float(_pick(readability, "separationScore", default=0.0)) >= 0.75:
            strengths.add("good_subject_isolation")
        if _as_bool(_pick(dominance, "hasClearFocus", default=False)) and _as_float(
            _pick(dominance, "focusCompetitionScore", default=1.0)
        ) <= 0.2:
            strengths.add("clear_focus_hierarchy")
        if _as_float(_pick(lighting, "backlightIndex", default=1.0)) < 0.3 and abs(
            _as_float(_pick(lighting, "exposureBiasHint", default=0.0))
        ) <= 0.15:
            strengths.add("good_light_emphasis")
        if abs(_as_float(_pick(horizon, "angleDegrees", default=0.0))) <= 0.8 and _as_float(
            _pick(horizon, "confidence", default=0.0)
        ) >= 0.8:
            strengths.add("stable_horizon_supports_scene")
        if abs(_as_float(_pick(composition, "horizontalOffset", default=1.0))) <= 0.18 and _as_float(
            _pick(readability, "edgePressureScore", default=1.0)
        ) <= 0.3:
            strengths.add("balanced_composition_for_scene")

        return [
            {
                "id": f"{case_id}:strength:{strength_type}",
                "type": strength_type,
                "confidence": 0.78,
            }
            for strength_type in sorted(strengths)
        ]

    def _fallback_used(self, snapshot: Dict[str, Any]) -> bool:
        technical_flags = set(_as_list(_pick(snapshot, "technicalFlags", "technical_flags", default=[])))
        return bool({"low_scene_confidence", "low_subject_confidence"} & technical_flags)

    def _aggregate_verdict(self, issues: List[Dict[str, Any]], fallback_used: bool) -> str:
        if not issues:
            return "mixed" if fallback_used else "good"
        strong_types = {
            "subject_too_close_to_edge",
            "insufficient_look_space",
            "backlight_hides_subject",
            "horizon_distracts",
        }
        if any(issue["type"] in strong_types for issue in issues):
            return "needs_fix"
        return "mixed"

    def _build_summary(
        self,
        case_id: str,
        verdict: str,
        issues: List[Dict[str, Any]],
        strengths: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        if verdict == "good":
            return {
                "id": f"{case_id}:summary",
                "shortVerdict": "Good frame with stable composition",
                "whyGood": "Subject remains clear with balanced focus and readable scene hierarchy.",
                "whyProblematic": None,
            }
        issue_names = ", ".join(issue["type"] for issue in issues[:3]) if issues else "weak signal"
        strength_names = ", ".join(strength["type"] for strength in strengths[:2])
        return {
            "id": f"{case_id}:summary",
            "shortVerdict": "Frame needs refinement",
            "whyGood": f"Still has strengths: {strength_names}" if strength_names else None,
            "whyProblematic": f"Main issues: {issue_names}",
        }

    def _build_primary_action(
        self,
        case_id: str,
        verdict: str,
        issues: List[Dict[str, Any]],
        snapshot: Dict[str, Any],
        mode: str,
    ) -> Optional[Dict[str, Any]]:
        motion = snapshot.get("motion", {})
        if mode == "live" and _pick(motion, "state", default="still") != "still":
            return None
        if verdict == "good":
            return {
                "id": f"{case_id}:action:leave_frame_as_is",
                "actionType": "leave_frame_as_is",
                "linkedIssueIds": [],
                "expectedOutcome": "Keep this framing.",
                "guardrail": {
                    "requiresStillCamera": mode == "live",
                    "minConfidence": 0.35,
                    "suppressWhenMoving": mode == "live",
                },
            }
        if not issues:
            return None

        by_priority = sorted(
            issues,
            key=lambda item: (
                0
                if item["type"] in {"subject_too_close_to_edge", "insufficient_look_space", "backlight_hides_subject"}
                else 1,
                -float(item.get("severity", 0.0)),
                item["type"],
            ),
        )
        issue = by_priority[0]
        action_type = ISSUE_TO_ACTION.get(issue["type"], "change_angle")
        if action_type in {"move_frame_left", "move_frame_right"}:
            horizontal_offset = _as_float(_get_path(snapshot, [("composition", "horizontalOffset")], default=0.0))
            action_type = "move_frame_left" if horizontal_offset > 0 else "move_frame_right"

        return {
            "id": f"{case_id}:action:{action_type}",
            "actionType": action_type,
            "linkedIssueIds": [issue["id"]],
            "expectedOutcome": f"Address {issue['type']}",
            "guardrail": {
                "requiresStillCamera": mode == "live",
                "minConfidence": 0.45,
                "suppressWhenMoving": mode == "live",
            },
        }

    def _build_plan(
        self,
        frame_id: str,
        mode: str,
        verdict: str,
        action: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]:
        return {
            "frameId": frame_id,
            "mode": mode,
            "inputVerdict": verdict,
            "primaryAction": action,
            "secondaryActions": [],
            "deferredActions": [],
            "noChangeRationale": "No corrective action needed." if action and action["actionType"] == "leave_frame_as_is" else None,
            "planConfidence": 0.82 if action else 0.55,
        }

    def _build_trace(
        self,
        frame_id: str,
        mode: str,
        summary_id: str,
        issues: List[Dict[str, Any]],
        strengths: List[Dict[str, Any]],
        action: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]:
        items: List[Dict[str, Any]] = []
        interp_ids: List[str] = []
        timestamp = 1000

        for issue in issues:
            obs_id = f"{issue['id']}:obs"
            int_id = f"{issue['id']}:int"
            items.append(
                {
                    "id": obs_id,
                    "frameId": frame_id,
                    "mode": mode,
                    "stage": "observation",
                    "sourceKind": "snapshot_signal",
                    "certainty": "deterministic",
                    "confidence": issue.get("confidence", 0.7),
                    "timestampMs": timestamp,
                    "statement": f"Observed signal for {issue['type']}",
                    "evidenceKeys": [f"snapshot.issue.{issue['type']}"],
                    "dependsOn": [],
                    "links": [],
                }
            )
            timestamp += 1
            items.append(
                {
                    "id": int_id,
                    "frameId": frame_id,
                    "mode": mode,
                    "stage": "interpretation",
                    "sourceKind": "deterministic_rule",
                    "certainty": "deterministic",
                    "confidence": issue.get("confidence", 0.7),
                    "timestampMs": timestamp,
                    "statement": f"Interpreted issue {issue['type']}",
                    "evidenceKeys": [f"rule.issue.{issue['type']}"],
                    "dependsOn": [obs_id],
                    "links": [{"kind": "issue", "refId": issue["id"]}],
                }
            )
            timestamp += 1
            interp_ids.append(int_id)

        for strength in strengths:
            obs_id = f"{strength['id']}:obs"
            int_id = f"{strength['id']}:int"
            items.append(
                {
                    "id": obs_id,
                    "frameId": frame_id,
                    "mode": mode,
                    "stage": "observation",
                    "sourceKind": "semantics_signal",
                    "certainty": "deterministic",
                    "confidence": strength.get("confidence", 0.7),
                    "timestampMs": timestamp,
                    "statement": f"Observed strength context {strength['type']}",
                    "evidenceKeys": [f"scene_semantics.strength.{strength['type']}"],
                    "dependsOn": [],
                    "links": [],
                }
            )
            timestamp += 1
            items.append(
                {
                    "id": int_id,
                    "frameId": frame_id,
                    "mode": mode,
                    "stage": "interpretation",
                    "sourceKind": "deterministic_rule",
                    "certainty": "deterministic",
                    "confidence": strength.get("confidence", 0.7),
                    "timestampMs": timestamp,
                    "statement": f"Interpreted strength {strength['type']}",
                    "evidenceKeys": [f"rule.strength.{strength['type']}"],
                    "dependsOn": [obs_id],
                    "links": [{"kind": "strength", "refId": strength["id"]}],
                }
            )
            timestamp += 1
            interp_ids.append(int_id)

        if action is not None:
            dependency = interp_ids[:1]
            if not dependency:
                obs_id = f"{summary_id}:obs"
                int_id = f"{summary_id}:int"
                items.append(
                    {
                        "id": obs_id,
                        "frameId": frame_id,
                        "mode": mode,
                        "stage": "observation",
                        "sourceKind": "snapshot_signal",
                        "certainty": "deterministic",
                        "confidence": 0.7,
                        "timestampMs": timestamp,
                        "statement": "Observed stable frame state",
                        "evidenceKeys": ["snapshot.motion.state"],
                        "dependsOn": [],
                        "links": [],
                    }
                )
                timestamp += 1
                items.append(
                    {
                        "id": int_id,
                        "frameId": frame_id,
                        "mode": mode,
                        "stage": "interpretation",
                        "sourceKind": "deterministic_rule",
                        "certainty": "deterministic",
                        "confidence": 0.7,
                        "timestampMs": timestamp,
                        "statement": "Interpreted no-change context",
                        "evidenceKeys": ["rule.no_change"],
                        "dependsOn": [obs_id],
                        "links": [],
                    }
                )
                timestamp += 1
                dependency = [int_id]

            links = [{"kind": "summary", "refId": summary_id}, {"kind": "action", "refId": action["id"]}]
            items.append(
                {
                    "id": f"{action['id']}:rec",
                    "frameId": frame_id,
                    "mode": mode,
                    "stage": "recommendation",
                    "sourceKind": "planner_policy",
                    "certainty": "deterministic",
                    "confidence": 0.78,
                    "timestampMs": timestamp,
                    "statement": f"Recommend {action['actionType']}",
                    "evidenceKeys": [f"planner.action.{action['actionType']}"],
                    "dependsOn": dependency,
                    "links": links,
                }
            )
            timestamp += 1

        if not any(link.get("kind") == "summary" for item in items for link in item.get("links", [])):
            root_interp_id = f"{summary_id}:int"
            items.append(
                {
                    "id": root_interp_id,
                    "frameId": frame_id,
                    "mode": mode,
                    "stage": "interpretation",
                    "sourceKind": "deterministic_rule",
                    "certainty": "deterministic",
                    "confidence": 0.72,
                    "timestampMs": timestamp,
                    "statement": "Summary interpretation",
                    "evidenceKeys": ["rule.summary"],
                    "dependsOn": [],
                    "links": [{"kind": "summary", "refId": summary_id}],
                }
            )

        root_ids = [item["id"] for item in items if any(link.get("kind") == "summary" for link in item.get("links", []))]
        return {"frameId": frame_id, "mode": mode, "items": items, "rootSummaryIds": root_ids[:1]}

    def _derive_hint(
        self,
        mode: str,
        snapshot: Dict[str, Any],
        fallback_used: bool,
        verdict: str,
        action: Optional[Dict[str, Any]],
    ) -> Tuple[str, Optional[str]]:
        if mode != "live":
            if action and action["actionType"] != "leave_frame_as_is":
                return "visible_action", action["actionType"]
            if verdict == "good":
                return "confirm_good_frame", "leave_frame_as_is"
            return "hidden_due_to_low_confidence", None

        motion_state = _get_path(snapshot, [("motion", "state")], default="still")
        if motion_state != "still":
            return "hidden_due_to_motion", None
        if fallback_used:
            return "hidden_due_to_low_confidence", None
        if action and action["actionType"] != "leave_frame_as_is":
            return "visible_action", action["actionType"]
        if verdict == "good":
            return "confirm_good_frame", "leave_frame_as_is"
        return "hidden_due_to_low_confidence", None
