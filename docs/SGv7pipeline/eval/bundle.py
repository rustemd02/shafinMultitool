from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .io import read_json, read_jsonl


class EvalBundleError(ValueError):
    """Raised when eval bundle contract is invalid."""


@dataclass(frozen=True)
class EvalBundle:
    bundle_dir: Path
    manifest: dict[str, Any]
    cases: list[dict[str, Any]]
    snapshot_paths: dict[str, Path]


DEFAULT_REQUIRED_SNAPSHOTS = [
    "prompt_contract_snapshot.json",
    "decoding_config_snapshot.json",
    "grammar_constraint_snapshot.json",
    "normalization_policy_snapshot.json",
    "runtime_policy_snapshot.json",
]

RUNTIME_ALLOWED_GOLD_TIERS = {
    "tier_a_human_gold",
    "tier_b_deterministic_canonical",
    "tier_c_reviewed_merge",
}


def _require_object(payload: Any, *, label: str) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise EvalBundleError(f"{label} must be an object")
    return payload


def _require_list(payload: Any, *, label: str) -> list[Any]:
    if not isinstance(payload, list):
        raise EvalBundleError(f"{label} must be a list")
    return payload


def _validate_case(case: dict[str, Any]) -> None:
    eval_case_id = str(case.get("eval_case_id", "")).strip()
    if not eval_case_id:
        raise EvalBundleError("eval case missing eval_case_id")

    eval_set = str(case.get("eval_set", "")).strip()
    if eval_set not in {"synthetic_heldout", "hard_heldout", "real_runtime"}:
        raise EvalBundleError(f"eval_case_id={eval_case_id} has unsupported eval_set={eval_set!r}")

    if not isinstance(case.get("gold_target_json"), dict):
        raise EvalBundleError(f"eval_case_id={eval_case_id} missing gold_target_json object")
    if not isinstance(case.get("rule_based_reference_json"), dict):
        raise EvalBundleError(f"eval_case_id={eval_case_id} missing rule_based_reference_json object")

    expectations = _require_object(case.get("eval_expectations"), label=f"eval_case_id={eval_case_id}.eval_expectations")
    _require_list(expectations.get("expected_marked_object_ids", []), label=f"eval_case_id={eval_case_id}.expected_marked_object_ids")
    _require_object(expectations.get("expected_ordinal_bindings", {}), label=f"eval_case_id={eval_case_id}.expected_ordinal_bindings")
    expected_actions = _require_list(expectations.get("expected_action_units", []), label=f"eval_case_id={eval_case_id}.expected_action_units")
    for idx, unit in enumerate(expected_actions, start=1):
        if not isinstance(unit, dict):
            raise EvalBundleError(f"eval_case_id={eval_case_id} expected_action_unit#{idx} must be object")
        if "phase_label" not in unit:
            raise EvalBundleError(f"eval_case_id={eval_case_id} expected_action_unit#{idx} missing phase_label")
    _require_list(expectations.get("expected_phase_sequence", []), label=f"eval_case_id={eval_case_id}.expected_phase_sequence")
    _require_list(expectations.get("critical_eval_tags", []), label=f"eval_case_id={eval_case_id}.critical_eval_tags")

    runtime_inputs = _require_object(case.get("runtime_policy_inputs"), label=f"eval_case_id={eval_case_id}.runtime_policy_inputs")
    required_runtime_fields = {
        "rule_confidence",
        "rule_object_count",
        "rule_action_count",
        "rule_has_dangling_targets",
        "rule_matched_marked_object_count",
        "mentioned_marked_object_ids",
    }
    missing_runtime_fields = [name for name in sorted(required_runtime_fields) if name not in runtime_inputs]
    if missing_runtime_fields:
        raise EvalBundleError(
            f"eval_case_id={eval_case_id} missing runtime_policy_inputs fields: {', '.join(missing_runtime_fields)}"
        )

    provenance = _require_object(case.get("provenance"), label=f"eval_case_id={eval_case_id}.provenance")
    if eval_set == "real_runtime":
        required_prov = {"correction_tier", "gold_source", "final_script_source", "review_status"}
        missing_prov = [name for name in sorted(required_prov) if name not in provenance]
        if missing_prov:
            raise EvalBundleError(
                f"eval_case_id={eval_case_id} missing provenance fields: {', '.join(missing_prov)}"
            )
        tier = str(provenance.get("correction_tier", ""))
        if tier not in RUNTIME_ALLOWED_GOLD_TIERS:
            raise EvalBundleError(
                f"eval_case_id={eval_case_id} correction_tier={tier!r} is not allowed for real_runtime gold eval"
            )


def load_eval_bundle(bundle_dir: Path) -> EvalBundle:
    manifest_path = bundle_dir / "eval_bundle_manifest.json"
    cases_path = bundle_dir / "eval_cases.jsonl"
    if not manifest_path.exists():
        raise EvalBundleError(f"missing required file: {manifest_path}")
    if not cases_path.exists():
        raise EvalBundleError(f"missing required file: {cases_path}")

    manifest = read_json(manifest_path)
    cases = read_jsonl(cases_path)
    if not cases:
        raise EvalBundleError("eval bundle cases are empty")

    required_snapshots = manifest.get("required_contract_snapshots", DEFAULT_REQUIRED_SNAPSHOTS)
    required_snapshots_list = _require_list(required_snapshots, label="manifest.required_contract_snapshots")
    snapshot_paths: dict[str, Path] = {}
    for snapshot_name in required_snapshots_list:
        name = str(snapshot_name)
        snapshot_path = bundle_dir / name
        if not snapshot_path.exists():
            raise EvalBundleError(f"missing required snapshot: {snapshot_path}")
        snapshot_paths[name] = snapshot_path

    seen_case_ids: set[str] = set()
    for case in cases:
        _validate_case(case)
        case_id = str(case["eval_case_id"])
        if case_id in seen_case_ids:
            raise EvalBundleError(f"duplicate eval_case_id={case_id!r}")
        seen_case_ids.add(case_id)

    return EvalBundle(
        bundle_dir=bundle_dir,
        manifest=manifest,
        cases=cases,
        snapshot_paths=snapshot_paths,
    )
