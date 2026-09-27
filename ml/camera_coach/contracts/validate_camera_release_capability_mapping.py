#!/usr/bin/env python3
"""Validate the DATA-002 release capability map against canonical inputs.

This is deliberately a small, dependency-free contract check. Canonical paths
and identifiers are pinned here; the mapping cannot make a fabricated copy of a
source file authoritative by pointing the validator at that copy.
"""

from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
MAP = ROOT / "ml/camera_coach/contracts/camera_release_capability_mapping_v1.json"
VALIDATOR_RELATIVE_PATH = "ml/camera_coach/contracts/validate_camera_release_capability_mapping.py"

CANONICAL = {
    "source_cases": {
        "path": "docs/cameraanalysis/case-coverage.v3-draft.json",
        "schema_id": "camera-case-coverage-v3-draft",
        "schema_version": "3.0.0-draft.1",
    },
    "operations_registry": {
        "path": "docs/cameraanalysis/operations-registry.v3-draft.json",
        "schema_id": "camera-operations-registry-v3-draft",
        "schema_version": "3.0.0-draft.1",
    },
    "release_label_contract": {
        "path": "ml/camera_coach/contracts/camera_release_label_v1.schema.json",
        "schema_id": "https://set-os.local/ml/camera_coach/contracts/camera-release-label-v1.schema.json",
        "schema_version": "1.0.0",
    },
    "model_contract": {
        "path": "ml/camera_coach/contracts/set_composition_net_v2.json",
        "contract_id": "SETCompositionNet",
        "contract_version": "setcompositionnet.v2",
    },
    "app_enums": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift",
    },
}

# This allowlist is intentionally explicit. A consumer key is not allowed to
# introduce an arbitrary path/symbol pair through the mapping JSON.
CONSUMER_ALLOWLIST = {
    "domain_contracts": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift",
        "symbols": (
            "enum IssueTypeV1",
            "enum TechnicalQualityIssueType",
            "enum TechnicalQualityActionType",
            "enum SemanticActionType",
        ),
    },
    "v3_contracts": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisV3Contracts.swift",
        "symbols": (
            "enum CameraAnalysisV3Contract",
            "enum CameraAnalysisV3ContractValidator",
            "static let operations",
        ),
    },
    "bounded_planner": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraBoundedActionPlanner.swift",
        "symbols": ("enum CameraBoundedActionPlanner", "static func plan("),
    },
    "safety_gate": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAdviceSafetyGate.swift",
        "symbols": (
            "enum CameraAdviceSafetyGate",
            "static func evaluateAdmissibility(",
            "static func evaluate(",
        ),
    },
    "overlay": {
        "path": "shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift",
        "symbols": ("struct CameraOverlayUXPresentation", "static func make("),
    },
    "copy": {
        "path": "shafinMultitool/Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift",
        # This exact owner matters: overlay copy must route through the typed
        # canonical-action lookup, not a parallel string table.
        "symbols": ("enum SETCameraCopy", "static func actionKey(forCanonicalActionID"),
    },
    "action_verifier": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/ActionVerifier.swift",
        "symbols": ("enum ActionVerifier", "static func verify("),
    },
    "movement_observer": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/UserMovementObserver.swift",
        "symbols": (
            "static func actionFamily(for actionID: String)",
            "private static func intent(for actionID: String)",
        ),
    },
    "coordinator": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CoachingEpisodeCoordinator.swift",
        "symbols": ("struct CoachingEpisodeCoordinator",),
    },
    "technical_quality": {
        "path": "shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift",
        "symbols": ("struct TechnicalQualityAnalyzer",),
    },
    "exposure_signals": {
        "path": "shafinMultitool/Multitool2Module/Models/CameraAnalysis/ExposureFeatureSignals.swift",
        "symbols": ("enum ExposureFeatureSignals",),
    },
    "camera_manager": {
        "path": "shafinMultitool/Multitool2Module/Services/Camera/CameraManager.swift",
        "symbols": ("func proControlsSnapshotAndWait()", "func applyProControl("),
    },
}

BEHAVIOR_OPERATION_REFS = {
    "selection": "selection",
    "evidence_only": "evidence_only",
    "state_only": "state_only",
    "review_compare": "review_compare",
    "feedback": "feedback",
    "квалифицированная операция для обнаруженной проблемы": "release_case_gate",
}
BEHAVIOR_CAPABILITY_REFS = {
    "selection": "selection",
    "evidence_only": "evidence_only",
    "state_only": "intent_state",
    "review_compare": "review_compare",
    "feedback": "feedback",
    "квалифицированная операция для обнаруженной проблемы": "release_case_gate",
}
VALID_CAPABILITY_STATUSES = {"blocked", "app_only", "deferred"}
VALID_CONSUMER_STATUSES = {"supported", "not_applicable", "unsupported"}
VALID_CONSUMER_ROLES = {"app_validator", "planner", "safety", "ui", "verification", "coordinator"}
VALID_BEHAVIOR_TOKENS = {
    "selection",
    "evidence_only",
    "state_only",
    "review_compare",
    "feedback",
    "qualified_operation",
}

# This is the set actually represented by ActionVerifier/UserMovementObserver.
# It intentionally excludes clean_lens, avoid_occlusion, reduce_iso_noise,
# change_camera_angle, removal, waiting, and moment-selection paths.
ACTION_VERIFIER_SUPPORTED = {
    "shift_frame_left",
    "shift_frame_right",
    "shift_frame_up",
    "shift_frame_down",
    "step_back",
    "step_closer",
    "lower_camera",
    "raise_camera",
    "level_horizon",
    "rotate_subject_toward_light",
    "move_subject_left",
    "move_subject_right",
    "move_subject_away_from_background",
    "move_object_left",
    "move_object_right",
    "move_object_forward",
    "move_object_back",
    "add_front_fill_light",
    "add_background_light",
    "remove_background_hotspot",
    "reduce_exposure",
    "increase_exposure",
    "refocus_subject",
    "stabilize_camera",
}
ACTION_VERIFIER_UNSUPPORTED = {
    "change_camera_angle",
    "remove_distracting_object",
    "wait_for_background_clearance",
    "reposition_prop_for_balance",
    "simplify_background",
    "keep_current_setup",
    "avoid_occlusion",
    "clean_lens",
    "reduce_iso_noise",
}

EXPECTED_HEAD_SUPPORT = {
    "scene_class_logits": "planned",
    "subjectness_roi_agreement_logits": "planned",
    "issue_logits": "research_only_current",
    "action_utility_logits": "research_only_current",
    "good_frame_probability": "planned",
    "abstention_probability": "planned",
    "risk_probability": "planned",
    "continuous_target_deltas": "research_only_current",
    "embedding": "not_a_release_target",
}

SOURCE_ROW_KEYS = (
    "case_id",
    "operation",
    "verification_predicate",
    "verifier",
    "status",
    "disposition",
    "operation_is_behaviour_not_operation",
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def add(errors: list[str], message: str) -> None:
    errors.append(message)


def camel_to_snake(value: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", value).lower()


def swift_enum_values(text: str, enum_name: str) -> list[str]:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\b.*?\n\}}", text, re.S)
    if not match:
        return []
    values: list[str] = []
    for line in match.group(0).splitlines():
        for item in re.finditer(
            r"\bcase\s+([A-Za-z][A-Za-z0-9_]*)(?:\s*=\s*\"([^\"]+)\")?",
            line,
        ):
            values.append(item.group(2) or camel_to_snake(item.group(1)))
    return values


def canonical_inputs() -> dict[str, Any]:
    inputs: dict[str, Any] = {}
    for section, spec in CANONICAL.items():
        path = ROOT / spec["path"]
        if section == "app_enums":
            inputs[section] = {"path": path, "text": path.read_text(encoding="utf-8")}
        else:
            inputs[section] = {"path": path, "data": read_json(path)}
    return inputs


def owners(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return value
    return []


def operation_actions(registry: dict[str, Any]) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for operation in registry.get("operations", []):
        axes = operation.get("maps_to_frozen_actions", {})
        result[operation.get("operation_id", "")] = set(axes.get("frozen", [])) | set(
            axes.get("technical", [])
        )
    return result


def source_projection(row: dict[str, Any]) -> dict[str, Any]:
    return {key: row[key] for key in SOURCE_ROW_KEYS if key in row}


def enum_values_from_head(model: dict[str, Any], head_name: str) -> list[str]:
    for head in model.get("outputs", {}).get("heads", []):
        if head.get("name") == head_name:
            return head.get("ordered_names") or []
    return []


def expected_case_refs(operation: str, registry_ids: set[str]) -> tuple[list[str], list[str]] | None:
    operation_refs: list[str] = []
    capability_refs: list[str] = []
    for token in (part.strip() for part in operation.split(" / ")):
        if token in registry_ids:
            operation_ref = token
            capability_ref = token
        elif token in BEHAVIOR_OPERATION_REFS:
            operation_ref = BEHAVIOR_OPERATION_REFS[token]
            capability_ref = BEHAVIOR_CAPABILITY_REFS[token]
        else:
            return None
        if operation_ref not in operation_refs:
            operation_refs.append(operation_ref)
        if capability_ref not in capability_refs:
            capability_refs.append(capability_ref)
    return operation_refs, capability_refs


def validate_consumer_record(
    capability_name: str,
    role: str,
    record: Any,
    consumer_texts: dict[str, str],
    errors: list[str],
) -> None:
    prefix = f"{capability_name}.consumer_support.{role}"
    if role not in VALID_CONSUMER_ROLES:
        add(errors, f"{prefix}: unknown consumer role")
    if not isinstance(record, dict):
        add(errors, f"{prefix}: record must be an object")
        return
    status = record.get("status")
    if status not in VALID_CONSUMER_STATUSES:
        add(errors, f"{prefix}: status must be supported/not_applicable/unsupported")
    owner_keys = owners(record.get("owner"))
    if not owner_keys or len(set(owner_keys)) != len(owner_keys):
        add(errors, f"{prefix}: owner must be one or more unique allowlisted keys")
    for owner in owner_keys:
        if owner not in CONSUMER_ALLOWLIST:
            add(errors, f"{prefix}: unknown owner key {owner}")
    symbols = record.get("symbols")
    if not isinstance(symbols, list) or not all(isinstance(symbol, str) and symbol for symbol in symbols):
        add(errors, f"{prefix}: symbols must be a string list")
        symbols = []
    if status == "supported":
        if not symbols:
            add(errors, f"{prefix}: supported record requires at least one owner symbol")
        if "reason" in record or "downstream_blocker" in record:
            add(errors, f"{prefix}: supported record cannot carry reason/blocker")
    elif status == "not_applicable":
        if not isinstance(record.get("reason"), str) or not record["reason"].strip():
            add(errors, f"{prefix}: not_applicable requires a reason")
        if "downstream_blocker" in record:
            add(errors, f"{prefix}: not_applicable cannot carry downstream_blocker")
    elif status == "unsupported":
        if not isinstance(record.get("reason"), str) or not record["reason"].strip():
            add(errors, f"{prefix}: unsupported requires a reason")
        blocker = record.get("downstream_blocker")
        if not isinstance(blocker, list) or not blocker or not all(
            isinstance(item, str) and item.strip() for item in blocker
        ):
            add(errors, f"{prefix}: unsupported requires a non-empty downstream_blocker list")
    for symbol in symbols:
        if not any(symbol in consumer_texts.get(owner, "") for owner in owner_keys):
            add(errors, f"{prefix}: symbol not found in pinned owner source: {symbol}")


def validate_action_dispositions(
    mapping: dict[str, Any],
    capabilities: dict[str, Any],
    canonical_action_ids: list[str],
    errors: list[str],
) -> None:
    ledger = mapping.get("action_dispositions")
    if not isinstance(ledger, dict) or set(ledger) != set(canonical_action_ids):
        add(errors, "action_dispositions must cover exactly all 33 DATA-001 action IDs")
        return
    graph_refs: dict[str, list[str]] = {action_id: [] for action_id in canonical_action_ids}
    for capability_name, capability in capabilities.items():
        for action_id in capability.get("release_label", {}).get("action_ids", []):
            graph_refs.setdefault(action_id, []).append(capability_name)
    for action_id in canonical_action_ids:
        entry = ledger[action_id]
        if not isinstance(entry, dict):
            add(errors, f"action_dispositions.{action_id}: entry must be an object")
            continue
        status = entry.get("status")
        refs = entry.get("capability_refs", [])
        if status == "mapped":
            if not isinstance(refs, list) or not refs:
                add(errors, f"action_dispositions.{action_id}: mapped action requires capability_refs")
                continue
            for capability_name in refs:
                capability = capabilities.get(capability_name)
                if not isinstance(capability, dict) or action_id not in capability.get("release_label", {}).get("action_ids", []):
                    add(errors, f"action_dispositions.{action_id}: capability_ref does not contain the action")
            if sorted(set(refs)) != sorted(set(graph_refs.get(action_id, []))):
                add(errors, f"action_dispositions.{action_id}: mapped refs differ from capability graph")
        elif status in {"unsupported", "deferred", "app_only"}:
            if refs:
                add(errors, f"action_dispositions.{action_id}: non-mapped action cannot carry capability_refs")
            if graph_refs.get(action_id):
                add(errors, f"action_dispositions.{action_id}: capability graph claims an action explicitly marked {status}")
            reason = entry.get("reason")
            dependencies = entry.get("tracker_dependencies")
            if not isinstance(reason, str) or not reason.strip():
                add(errors, f"action_dispositions.{action_id}: {status} requires a reason")
            if not isinstance(dependencies, list) or not dependencies or not all(
                isinstance(item, str) and item.strip() for item in dependencies
            ):
                add(errors, f"action_dispositions.{action_id}: {status} requires tracker_dependencies")
        else:
            add(errors, f"action_dispositions.{action_id}: invalid status {status}")


def validate_mapping(mapping: dict[str, Any], inputs: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if mapping.get("schema_id") != "camera-release-capability-mapping-v1":
        add(errors, "wrong mapping schema_id")
    if mapping.get("schema_version") != "1.0.0":
        add(errors, "wrong mapping schema_version")
    if mapping.get("status") != "mapping_complete_with_explicit_model_blockers":
        add(errors, "wrong mapping status")

    # The map must point to these exact files, not merely to files whose content
    # happens to be self-consistent with the map.
    for section, spec in CANONICAL.items():
        mapped = mapping.get(section)
        if not isinstance(mapped, dict):
            add(errors, f"missing {section} section")
            continue
        if mapped.get("path") != spec["path"]:
            add(errors, f"{section}: path is not the pinned canonical path")
        path = inputs[section]["path"]
        if mapped.get("sha256") != sha256(path):
            add(errors, f"{section}: sha256 mismatch against pinned path")

    source = inputs["source_cases"]["data"]
    registry = inputs["operations_registry"]["data"]
    label = inputs["release_label_contract"]["data"]
    model = inputs["model_contract"]["data"]
    swift = inputs["app_enums"]["text"]

    source_meta = mapping.get("source_cases", {})
    if source.get("schema_id") != CANONICAL["source_cases"]["schema_id"] or source.get("schema_version") != CANONICAL["source_cases"]["schema_version"]:
        add(errors, "canonical source case schema ID/version changed")
    if source_meta.get("schema_id") != CANONICAL["source_cases"]["schema_id"] or source_meta.get("schema_version") != CANONICAL["source_cases"]["schema_version"]:
        add(errors, "source_cases schema ID/version is not pinned")
    if source_meta.get("total_cases") != 68 or source.get("total_cases") != 68:
        add(errors, "canonical source must contain exactly 68 rows")
    source_rows = source.get("case_rows", [])
    if len(source_rows) != 68:
        add(errors, "canonical source case_rows length is not 68")
    if source_meta.get("case_rows") != [source_projection(row) for row in source_rows]:
        add(errors, "source_cases embedded case_rows differ from canonical source")
    if source_meta.get("declared_counts_by_status") != source.get("counts_by_status"):
        add(errors, "source declared counts were not preserved")
    derived_source_counts = dict(Counter(row.get("status") for row in source_rows))
    if source_meta.get("derived_counts_by_status") != derived_source_counts:
        add(errors, "source_cases derived counts are wrong")
    if mapping.get("derived_counts_by_case_status") != derived_source_counts:
        add(errors, "mapping derived case counts are wrong")

    operation_entries = operation_actions(registry)
    registry_ids = list(operation_entries)
    registry_meta = mapping.get("operations_registry", {})
    if registry.get("schema_id") != CANONICAL["operations_registry"]["schema_id"] or registry.get("schema_version") != CANONICAL["operations_registry"]["schema_version"]:
        add(errors, "canonical operations registry schema ID/version changed")
    if registry_meta.get("schema_id") != CANONICAL["operations_registry"]["schema_id"] or registry_meta.get("schema_version") != CANONICAL["operations_registry"]["schema_version"]:
        add(errors, "operations_registry schema ID/version is not pinned")
    if registry_meta.get("operation_ids") != registry_ids:
        add(errors, "operation registry IDs differ from pinned canonical registry")

    label_meta = mapping.get("release_label_contract", {})
    if label.get("$id") != CANONICAL["release_label_contract"]["schema_id"]:
        add(errors, "canonical release label $id changed")
    if label_meta.get("schema_id") != CANONICAL["release_label_contract"]["schema_id"] or label_meta.get("schema_version") != CANONICAL["release_label_contract"]["schema_version"]:
        add(errors, "release label schema ID/version is not pinned")
    issue_ids = label.get("$defs", {}).get("issueID", {}).get("enum", [])
    action_ids = label.get("$defs", {}).get("actionID", {}).get("enum", [])
    if label_meta.get("issue_ids") != issue_ids or label_meta.get("action_ids") != action_ids:
        add(errors, "DATA-001 issue/action catalogs differ from canonical schema")
    if label_meta.get("owner") != "DATA-001":
        add(errors, "release label owner is not DATA-001")

    app_meta = mapping.get("app_enums", {})
    if app_meta.get("path") != CANONICAL["app_enums"]["path"]:
        add(errors, "app enum path is not pinned")
    enum_values = {
        "issue_ids": swift_enum_values(swift, "IssueTypeV1"),
        "technical_issue_ids": swift_enum_values(swift, "TechnicalQualityIssueType"),
        "semantic_action_ids": swift_enum_values(swift, "SemanticActionType"),
        "technical_action_ids": swift_enum_values(swift, "TechnicalQualityActionType"),
    }
    expected_issue_head_names = enum_values_from_head(model, "issue_logits")
    expected_action_head_names = enum_values_from_head(model, "action_utility_logits")
    expected_issue_catalog = {
        issue_id: {
            "label_id": issue_id,
            "release_label_owner": "DATA-001",
            "trainer_head_ref": "issue_logits" if issue_id in expected_issue_head_names else None,
            "coreml_output_ref": "issue_logits" if issue_id in expected_issue_head_names else None,
            "support": "research_only_current" if issue_id in expected_issue_head_names else "app_only_current",
            "app_enum_ref": "IssueTypeV1" if issue_id in enum_values["issue_ids"] else "TechnicalQualityIssueType",
            "release_neural_admission": False,
        }
        for issue_id in issue_ids
    }
    expected_action_catalog = {
        action_id: {
            "label_id": action_id,
            "release_label_owner": "DATA-001",
            "trainer_head_ref": "action_utility_logits" if action_id in expected_action_head_names else None,
            "coreml_output_ref": "action_utility_logits" if action_id in expected_action_head_names else None,
            "support": "research_only_current" if action_id in expected_action_head_names else "app_only_current",
            "app_enum_ref": "SemanticActionType" if action_id in enum_values["semantic_action_ids"] else "TechnicalQualityActionType",
            "release_neural_admission": False,
        }
        for action_id in action_ids
    }
    if mapping.get("issue_catalog") != expected_issue_catalog or mapping.get("action_catalog") != expected_action_catalog:
        add(errors, "top-level issue/action catalogs differ from canonical DATA-001/app/model mapping")
    for key, values in enum_values.items():
        if app_meta.get(key) != values:
            add(errors, f"app enum {key} mismatch against pinned Swift source")
    if app_meta.get("accepted_action_ids") != action_ids:
        add(errors, "accepted action union mismatch")
    if set(enum_values["issue_ids"] + enum_values["technical_issue_ids"]) != set(issue_ids):
        add(errors, "Swift issue enum union mismatch")
    if set(enum_values["semantic_action_ids"] + enum_values["technical_action_ids"]) != set(action_ids):
        add(errors, "Swift action enum union mismatch")
    for key, enum_name in (
        ("issue_enum", "IssueTypeV1"),
        ("technical_issue_enum", "TechnicalQualityIssueType"),
        ("semantic_action_enum", "SemanticActionType"),
        ("technical_action_enum", "TechnicalQualityActionType"),
    ):
        if app_meta.get(key) != enum_name:
            add(errors, f"app enum declaration name changed for {key}")

    model_meta = mapping.get("model_contract", {})
    if model.get("contract_id") != CANONICAL["model_contract"]["contract_id"] or model.get("contract_version") != CANONICAL["model_contract"]["contract_version"]:
        add(errors, "canonical model contract ID/version changed")
    if model_meta.get("contract_id") != CANONICAL["model_contract"]["contract_id"] or model_meta.get("contract_version") != CANONICAL["model_contract"]["contract_version"]:
        add(errors, "model contract ID/version is not pinned")
    model_head_order = model.get("outputs", {}).get("head_order", [])
    if model_meta.get("head_order") != model_head_order:
        add(errors, "model head order mismatch")
    if not isinstance(model_meta.get("boundary"), str) or "no production" not in model_meta["boundary"].lower():
        add(errors, "model boundary disclaimer is missing or does not remain fail-closed")
    model_outputs = {head.get("name"): head for head in model.get("outputs", {}).get("heads", [])}
    trainer_heads = mapping.get("trainer_heads", {})
    coreml_outputs = mapping.get("coreml_outputs", {})
    if set(trainer_heads) != set(model_outputs) or set(coreml_outputs) != set(model_outputs):
        add(errors, "trainer/Core ML head sets differ from canonical model outputs")
    for name, expected_support in EXPECTED_HEAD_SUPPORT.items():
        head = trainer_heads.get(name, {})
        output = model_outputs.get(name, {})
        core = coreml_outputs.get(name, {})
        if name not in model_outputs:
            add(errors, f"missing canonical model head {name}")
            continue
        if head.get("shape") != output.get("shape") or core.get("shape") != output.get("shape"):
            add(errors, f"{name}: trainer/Core ML shape mismatch")
        if head.get("ordered_names") != output.get("ordered_names") or core.get("ordered_names") != output.get("ordered_names"):
            add(errors, f"{name}: ordered output names mismatch")
        if head.get("support") != expected_support or head.get("release_ready") is not False:
            add(errors, f"{name}: trainer support/release state is not pinned")
        if core.get("training_support") != expected_support or core.get("production_admitted") is not False:
            add(errors, f"{name}: Core ML support/admission state is not fail-closed")
        if core.get("contract_state") != "declared_current" or core.get("dtype") != "float32":
            add(errors, f"{name}: Core ML output state/dtype is not pinned")
        expected_ref = f"set_composition_net_v2.json#/outputs/heads/{name}"
        if core.get("source_ref") != expected_ref:
            add(errors, f"{name}: Core ML source_ref is fabricated or stale")

    # Consumer files are pinned independently of capability records.
    mapped_consumers = mapping.get("consumer_sources", {})
    consumer_texts: dict[str, str] = {}
    if set(mapped_consumers) != set(CONSUMER_ALLOWLIST):
        add(errors, "consumer source keys differ from the explicit allowlist")
    for key, spec in CONSUMER_ALLOWLIST.items():
        mapped = mapped_consumers.get(key, {})
        path = ROOT / spec["path"]
        if mapped.get("path") != spec["path"]:
            add(errors, f"consumer source {key}: path is not allowlisted")
        if not path.exists():
            add(errors, f"consumer source {key}: pinned file is missing")
            continue
        consumer_texts[key] = path.read_text(encoding="utf-8")
        if mapped.get("sha256") != sha256(path):
            add(errors, f"consumer source {key}: sha256 mismatch")
        if mapped.get("symbols") != list(spec["symbols"]):
            add(errors, f"consumer source {key}: symbol allowlist mismatch")
        for symbol in spec["symbols"]:
            if symbol not in consumer_texts[key]:
                add(errors, f"consumer source {key}: allowlisted symbol is absent: {symbol}")
        if any("SemanticTipPlanner" in symbol for symbol in mapped.get("symbols", [])):
            add(errors, "SemanticTipPlanner is not an allowlisted owner for DATA-002")

    capabilities = mapping.get("capabilities", {})
    operation_to_capability: dict[str, str] = {}
    for name, capability in capabilities.items():
        if not isinstance(capability, dict):
            add(errors, f"{name}: capability must be an object")
            continue
        status = capability.get("status")
        operation_ids_for_cap = capability.get("operation_ids", [])
        behavior_tokens = capability.get("behavior_tokens", [])
        if status not in VALID_CAPABILITY_STATUSES:
            add(errors, f"{name}: invalid capability status")
        if not isinstance(operation_ids_for_cap, list) or not all(isinstance(item, str) for item in operation_ids_for_cap):
            add(errors, f"{name}: operation_ids must be a string list")
            operation_ids_for_cap = []
        if not isinstance(behavior_tokens, list) or not all(isinstance(item, str) for item in behavior_tokens):
            add(errors, f"{name}: behavior_tokens must be a string list")
            behavior_tokens = []
        for operation_id in operation_ids_for_cap:
            if operation_id not in operation_entries:
                add(errors, f"{name}: unknown operation_id {operation_id}")
            elif operation_id in operation_to_capability:
                add(errors, f"operation {operation_id} is claimed by multiple capabilities")
            else:
                operation_to_capability[operation_id] = name
        for behavior in behavior_tokens:
            if behavior not in VALID_BEHAVIOR_TOKENS:
                add(errors, f"{name}: unknown behavior token {behavior}")
        if not operation_ids_for_cap and len(behavior_tokens) != 1:
            add(errors, f"{name}: behavior-only capability must name exactly one behavior token")
        if operation_ids_for_cap and behavior_tokens:
            add(errors, f"{name}: operation and behavior ownership cannot be mixed")
        release_label = capability.get("release_label", {})
        if release_label.get("owner") != "DATA-001":
            add(errors, f"{name}: release label owner is not DATA-001")
        capability_issue_ids = release_label.get("issue_ids", [])
        capability_action_ids = release_label.get("action_ids", [])
        if not set(capability_issue_ids) <= set(issue_ids):
            add(errors, f"{name}: issue outside DATA-001 catalog")
        if not set(capability_action_ids) <= set(action_ids):
            add(errors, f"{name}: action outside DATA-001 catalog")
        if len(capability_action_ids) != len(set(capability_action_ids)):
            add(errors, f"{name}: duplicate release action ID")

        # Every operation/action claim is tied to a canonical registry entry or
        # an explicitly named case-coverage behavior token.
        if len(operation_ids_for_cap) == 1:
            operation_id = operation_ids_for_cap[0]
            expected_owner = {
                "kind": "operations_registry",
                "path": CANONICAL["operations_registry"]["path"],
                "operation_id": operation_id,
                "field": "maps_to_frozen_actions",
            }
            if capability.get("source_owner") != expected_owner:
                add(errors, f"{name}: source_owner is not the canonical operation owner")
            if "operations[].maps_to_frozen_actions" not in str(capability.get("mapping_basis", "")):
                add(errors, f"{name}: mapping_basis does not identify the canonical operation field")
            allowed_actions = operation_entries.get(operation_id, set())
            if not set(capability_action_ids) <= allowed_actions:
                add(errors, f"{name}: action_ids promote a gap or an action from another operation")
            expected_relation = (
                "subset_of_registry_frozen_or_technical"
                if capability_action_ids
                else "no_frozen_equivalent_app_only_or_deferred"
            )
            if capability.get("action_relation") != expected_relation:
                add(errors, f"{name}: fabricated or wrong action_relation")
        else:
            behavior = behavior_tokens[0] if behavior_tokens else None
            expected_owner = {
                "kind": "case_coverage",
                "path": CANONICAL["source_cases"]["path"],
                "token": behavior,
                "field": "case_rows[].operation",
            }
            if capability.get("source_owner") != expected_owner:
                add(errors, f"{name}: source_owner is not the canonical behavior owner")
            if "Source behavior token" not in str(capability.get("mapping_basis", "")):
                add(errors, f"{name}: behavior mapping_basis is not explicit")
            if capability.get("action_relation") != "no_registry_operation":
                add(errors, f"{name}: behavior capability has fabricated action_relation")
            if capability_action_ids:
                add(errors, f"{name}: behavior capability cannot promote actions")

        verification_owner = capability.get("verification_owner")
        if not isinstance(verification_owner, str) or not verification_owner.strip():
            add(errors, f"{name}: verification_owner is missing")
        consumer_support = capability.get("consumer_support")
        if "app_consumers" in capability:
            add(errors, f"{name}: legacy app_consumers is not accepted")
        if status != "deferred" and not isinstance(consumer_support, dict):
            add(errors, f"{name}: non-deferred capability requires structured consumer_support")
        if isinstance(consumer_support, dict):
            for role, record in consumer_support.items():
                validate_consumer_record(name, role, record, consumer_texts, errors)

        if capability_action_ids:
            ui = consumer_support.get("ui") if isinstance(consumer_support, dict) else None
            ui_owners = owners(ui.get("owner")) if isinstance(ui, dict) else []
            ui_symbols = ui.get("symbols", []) if isinstance(ui, dict) else []
            if not isinstance(ui, dict) or ui.get("status") != "supported" or "copy" not in ui_owners or "static func actionKey(forCanonicalActionID" not in ui_symbols:
                add(errors, f"{name}: action-bearing capability lacks SETCameraCopy.actionKey UI owner")

        verification = consumer_support.get("verification") if isinstance(consumer_support, dict) else None
        verification_status = verification.get("status") if isinstance(verification, dict) else None
        unsupported_claims = set(capability_action_ids) & ACTION_VERIFIER_UNSUPPORTED
        if unsupported_claims:
            if verification_status not in {"unsupported", "not_applicable"}:
                add(errors, f"{name}: unsupported ActionVerifier action is claimed as supported")
        elif capability_action_ids and not set(capability_action_ids) - ACTION_VERIFIER_SUPPORTED:
            if verification_status != "supported":
                add(errors, f"{name}: handled ActionVerifier actions lack supported verification")
        if operation_ids_for_cap and operation_ids_for_cap[0] in {"change_lens", "select_capture_moment"}:
            if verification_status not in {"unsupported", "not_applicable"}:
                add(errors, f"{name}: change-lens/moment-selection must remain unsupported/incomparable")

        if status == "blocked":
            heads = capability.get("trainer_head_refs", [])
            outputs = capability.get("coreml_output_refs", [])
            if not heads or heads != outputs:
                add(errors, f"{name}: blocked capability lacks mirrored neural references")
            if not isinstance(capability.get("blocker"), str) or not capability["blocker"].strip():
                add(errors, f"{name}: blocked capability lacks an explicit blocker")
            if not isinstance(capability.get("tracker_dependencies"), list) or not capability["tracker_dependencies"]:
                add(errors, f"{name}: blocked capability lacks tracker dependencies")
        elif status == "app_only":
            if capability.get("trainer_head_refs") or capability.get("coreml_output_refs"):
                add(errors, f"{name}: app_only capability cannot claim neural refs")
            gate = capability.get("app_only_gate")
            if not isinstance(gate, dict):
                add(errors, f"{name}: app_only capability lacks app_only_gate")
            else:
                if not isinstance(gate.get("reason"), str) or not gate["reason"].strip():
                    add(errors, f"{name}: app_only gate requires a reason")
                if gate.get("owner_source") != "consumer_sources":
                    add(errors, f"{name}: app_only gate owner_source is not pinned")
                gate_owners = owners(gate.get("owner"))
                gate_symbols = gate.get("owner_symbols", [])
                if not gate_owners or any(owner not in CONSUMER_ALLOWLIST for owner in gate_owners):
                    add(errors, f"{name}: app_only gate has an unknown owner")
                if not isinstance(gate_symbols, list) or not all(isinstance(symbol, str) for symbol in gate_symbols):
                    add(errors, f"{name}: app_only gate owner_symbols must be a string list")
                for symbol in gate_symbols if isinstance(gate_symbols, list) else []:
                    if not any(symbol in consumer_texts.get(owner, "") for owner in gate_owners):
                        add(errors, f"{name}: app_only gate symbol is absent from owner source: {symbol}")
                if gate.get("tracker_dependencies") != capability.get("tracker_dependencies"):
                    add(errors, f"{name}: app_only gate dependencies differ from capability dependencies")
        elif status == "deferred":
            if capability.get("trainer_head_refs") or capability.get("coreml_output_refs"):
                add(errors, f"{name}: deferred capability cannot claim neural refs")
            if not isinstance(capability.get("deferred_reason"), str) or not capability["deferred_reason"].strip():
                add(errors, f"{name}: deferred capability lacks a reason")
            if not isinstance(capability.get("tracker_dependencies"), list) or not capability["tracker_dependencies"]:
                add(errors, f"{name}: deferred capability lacks tracker dependencies")

    if set(operation_to_capability) != set(registry_ids):
        add(errors, f"unmapped registry operations: {sorted(set(registry_ids) - set(operation_to_capability))}")
    expected_capability_counts = dict(Counter(capability.get("status") for capability in capabilities.values()))
    if mapping.get("capability_counts") != expected_capability_counts:
        add(errors, "capability_counts do not match capability statuses")
    if expected_capability_counts != {"blocked": 8, "app_only": 12, "deferred": 6}:
        add(errors, f"unexpected capability status counts: {expected_capability_counts}")
    validate_action_dispositions(mapping, capabilities, action_ids, errors)

    mapped_rows = mapping.get("cases", [])
    expected_ids = [row.get("case_id") for row in source_rows]
    actual_ids = [row.get("case_id") for row in mapped_rows]
    if len(mapped_rows) != 68 or actual_ids != expected_ids or len(set(actual_ids)) != 68:
        add(errors, "mapping cases are not the exact ordered 68/68 source ID set")
    for source_row, mapped_row in zip(source_rows, mapped_rows):
        if mapped_row.get("source") != source_projection(source_row):
            add(errors, f"{source_row.get('case_id')}: embedded source case_row differs")
            continue
        refs = expected_case_refs(source_row.get("operation", ""), set(registry_ids))
        if refs is None:
            add(errors, f"{source_row.get('case_id')}: unknown source operation/behavior token")
            continue
        operation_refs, capability_refs = refs
        if mapped_row.get("operation_refs") != operation_refs:
            add(errors, f"{source_row.get('case_id')}: operation references changed")
        if mapped_row.get("capability_refs") != capability_refs:
            add(errors, f"{source_row.get('case_id')}: capability references changed")
        statuses_for_case = mapped_row.get("capability_statuses")
        expected_statuses = {ref: capabilities.get(ref, {}).get("status") for ref in capability_refs}
        if statuses_for_case != expected_statuses:
            add(errors, f"{source_row.get('case_id')}: capability statuses are wrong")
        if any(ref not in capabilities for ref in capability_refs):
            add(errors, f"{source_row.get('case_id')}: capability reference is not declared")

    verification_meta = mapping.get("verification", {})
    if verification_meta.get("validator") != VALIDATOR_RELATIVE_PATH:
        add(errors, "verification validator path changed")
    if verification_meta.get("source_operation_predicates_preserved") is not True:
        add(errors, "verification does not require source operation/predicate preservation")
    if verification_meta.get("exact_case_set_required") != "68/68":
        add(errors, "verification does not require exact 68/68 case set")
    relation = mapping.get("mapping_relation", {})
    if relation.get("source") != "operations_registry.operations[].maps_to_frozen_actions" or relation.get("no_invented_substitutions") is not True:
        add(errors, "mapping relation is not pinned to the registry frozen/technical axes")
    if relation.get("source_owner") != "DATA-002; canonical registry and C04 operation qualification remain authoritative.":
        add(errors, "mapping relation source_owner changed")

    return errors


def run_negative_self_checks(mapping: dict[str, Any], inputs: dict[str, Any]) -> list[str]:
    """Make sure the validator fails on the four classes of fake mapping."""

    mutations: list[tuple[str, Any]] = [
        (
            "path substitution",
            lambda candidate: candidate["source_cases"].update({"path": "docs/fake.json"}),
        ),
        (
            "fabricated action relation",
            lambda candidate: candidate["capabilities"]["reframe_subject"].update(
                {"action_relation": "no_registry_operation"}
            ),
        ),
        (
            "fake consumer symbol",
            lambda candidate: candidate["capabilities"]["reframe_subject"]["consumer_support"]["planner"][
                "symbols"
            ].__setitem__(0, "static func fabricatedOwner("),
        ),
        (
            "deleted supported consumer symbols",
            lambda candidate: candidate["capabilities"]["release_case_gate"]["consumer_support"]["app_validator"].update(
                {"symbols": []}
            ),
        ),
        (
            "wrong capability status",
            lambda candidate: candidate["cases"][0]["capability_statuses"].update(
                {"reframe_subject": "app_only"}
            ),
        ),
        (
            "wrong capability count",
            lambda candidate: candidate["capability_counts"].update({"blocked": 999}),
        ),
    ]
    failures: list[str] = []
    for label, mutate in mutations:
        candidate = copy.deepcopy(mapping)
        mutate(candidate)
        if validate_mapping(candidate, inputs):
            failures.append(label)
    return failures


def main() -> int:
    mapping = read_json(MAP)
    inputs = canonical_inputs()
    errors = validate_mapping(mapping, inputs)
    negative_labels = run_negative_self_checks(mapping, inputs)
    if len(negative_labels) != 6:
        add(errors, f"negative self-checks failed: {negative_labels} (expected 6/6)")
    if errors:
        print("FAIL DATA-002 mapping validator")
        print("\n".join(f"- {error}" for error in errors))
        return 1

    source_rows = inputs["source_cases"]["data"]["case_rows"]
    derived_source_counts = dict(Counter(row["status"] for row in source_rows))
    capability_counts = dict(Counter(capability["status"] for capability in mapping["capabilities"].values()))
    blockers = [name for name, capability in mapping["capabilities"].items() if capability["status"] == "blocked"]
    deferred = [name for name, capability in mapping["capabilities"].items() if capability["status"] == "deferred"]
    print("PASS DATA-002 mapping validator")
    print("cases=68/68 exact ordered source IDs; embedded operation/predicate/verifier rows preserved")
    print(
        f"capabilities={capability_counts}; issues={len(mapping['release_label_contract']['issue_ids'])}; "
        f"actions={len(mapping['release_label_contract']['action_ids'])}; operations={len(mapping['operations_registry']['operation_ids'])}"
    )
    print(
        f"source_counts_declared={mapping['source_cases']['declared_counts_by_status']} "
        f"derived={derived_source_counts}"
    )
    print(f"consumer_sources={len(CONSUMER_ALLOWLIST)} allowlisted; action_dispositions=33/33; negative_self_checks=6/6")
    print(f"blocked={','.join(blockers)}")
    print(f"deferred={','.join(deferred)}")
    if mapping["source_cases"]["declared_counts_by_status"] != derived_source_counts:
        print("NOTE source counts_by_status declaration differs from row-derived counts; canonical source was preserved unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
