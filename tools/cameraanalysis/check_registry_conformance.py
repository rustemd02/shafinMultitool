#!/usr/bin/env python3
"""P01 conformance check for the v3-draft operation registry and case coverage.

Verifies the review-round-4 invariants against the registries and the source
documents (03-domain-contracts.md N6/N9, camera-analysis-requirements-draft.md
§23.4). Exit code 0 only when every check passes.

Usage:
    python3 tools/cameraanalysis/check_registry_conformance.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OPS = ROOT / "docs/cameraanalysis/operations-registry.v3-draft.json"
COV = ROOT / "docs/cameraanalysis/case-coverage.v3-draft.json"
CONTRACTS = ROOT / "docs/cameraanalysis/03-domain-contracts.md"
REQS = ROOT / "docs/cameraanalysis/camera-analysis-requirements-draft.md"
CONTRACTS_SWIFT = ROOT / "shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift"

DESIRED = {"increase", "decrease", "inside_region", "preserve"}
EXPECTED_UNSUPPORTED = {"maintain_subject_zone", "smooth_camera_motion", "plan_motion_endpoints"}
GROUP_BUCKET = {"reframe_subject", "maintain_subject_zone"}
FRAME_GLOBAL = {"level_frame", "hold_steady", "clear_lens_obstruction"}
# polarity -> the desired value that contradicts it
CONTRADICTS = {"increase_is_better": "decrease", "decrease_is_better": "increase"}

failures: list[str] = []
checks = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not ok:
        failures.append(f"{name}: {detail}")


def load() -> tuple[dict, dict]:
    return json.loads(OPS.read_text(encoding="utf-8")), json.loads(COV.read_text(encoding="utf-8"))


def parse_234() -> dict[str, str]:
    md = REQS.read_text(encoding="utf-8")
    seg = md[md.index("### 23.4"):]
    rows: dict[str, str] = {}
    for line in seg.splitlines():
        if not line.startswith("| CC-"):
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if len(cells) >= 5:
            rows[cells[0]] = cells[3]
    return rows


def enum_values(enum_name: str) -> set[str]:
    """Raw string values of a Swift string enum — values, not case names.

    A case-name extractor can never match a snake_case catalog list, which is
    exactly how the earlier leak check passed vacuously (review round 4, C1).
    """
    text = CONTRACTS_SWIFT.read_text(encoding="utf-8")
    block = re.search(r"enum\s+" + re.escape(enum_name) + r"\s*:\s*String[^{]*\{(.*?)\n\}", text, re.S)
    if not block:
        return set()
    return set(re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', block.group(1)))


def main() -> int:
    ops, cov = load()
    op_rows = ops["operations"]
    cases = cov["case_rows"]
    vocab = ops["metric_vocabulary"]
    ops_by_id = {o["operation_id"]: o for o in op_rows}

    # 1. effect goals are concrete, enum-conformant and cite a known metric
    exhaustiveness_checked = 0
    with_instantiation = [o["operation_id"] for o in op_rows if o.get("effect_goal_instantiation")]
    for o in op_rows:
        oid = o["operation_id"]
        goal = o.get("effect_goal", {})
        check("effect_goal.desired", goal.get("desired") in DESIRED,
              f"{oid}: desired={goal.get('desired')!r} not in {sorted(DESIRED)}")
        check("effect_goal.metricID", goal.get("metricID") in vocab,
              f"{oid}: metricID={goal.get('metricID')!r} absent from metric_vocabulary")
        check("effect_goal.not_unspecified", "unspecified_in_source" not in json.dumps(goal, ensure_ascii=False),
              f"{oid}: effect_goal still contains unspecified_in_source")
        # `desired` is always a literal N6:718 value; payload-driven operations carry
        # effect_goal_instantiation.variants, which are checked exhaustively below.
        # polarity: the desired must not point away from the known improvement direction
        polarity = vocab.get(goal.get("metricID"), {}).get("polarity")
        if polarity in CONTRADICTS:
            check("effect_goal.polarity", goal.get("desired") != CONTRADICTS[polarity],
                  f"{oid}: desired={goal.get('desired')!r} contradicts metric polarity {polarity!r}")
            if goal.get("desired") == "preserve":
                check("effect_goal.preserve_basis", bool(o["effect_goal_resolution"].get("preserve_basis")),
                      f"{oid}: preserve on a known-polarity metric needs preserve_basis")
        # payload-driven templates: variants must be exhaustive, grounded in the payload text and polarity-consistent
        inst = o.get("effect_goal_instantiation")
        if inst:
            payload_text = o.get("payload_spec", "")
            seen_values: set[str] = set()
            seen_keys: set[str] = set()
            for v in inst.get("variants", []):
                where = v.get("when", {})
                seen_keys.update(where.keys())
                seen_values.update(str(x) for x in where.values() if not isinstance(x, bool))
                check("instantiation.variant_metric", v.get("metricID") in vocab,
                      f"{oid}: variant metric {v.get('metricID')!r} absent from metric_vocabulary")
                check("instantiation.variant_desired", v.get("desired") in DESIRED,
                      f"{oid}: variant desired {v.get('desired')!r} outside the N6:718 enum")
                vp = vocab.get(v.get("metricID"), {}).get("polarity")
                if vp in CONTRADICTS:
                    check("instantiation.variant_polarity", v.get("desired") != CONTRADICTS[vp],
                          f"{oid}: variant {where} desired={v.get('desired')!r} contradicts polarity {vp!r}")
                    if v.get("desired") == "preserve":
                        check("instantiation.variant_preserve_basis", bool(v.get("preserve_basis")),
                              f"{oid}: variant {where} preserve needs preserve_basis")
            # grounding: every referenced field must be named by the N6.1 payload spec,
            # and every enum value used must appear there too
            check("instantiation.grounded_in_payload",
                  all(k in payload_text for k in seen_keys) and all(sv in payload_text for sv in seen_values),
                  f"{oid}: fields {sorted(seen_keys)} / values {sorted(seen_values)} are not all named in the payload spec")
            # exhaustiveness is derived from the payload spec, not trusted from a flag (round-5 NR4)
            presence = inst.get("presence_branches")
            enum_field = inst.get("payload_enum_field")
            if enum_field:
                # the source table escapes its pipes: desired:larger\|smaller
                match = re.search(re.escape(enum_field) + r":([a-z_\\|]+)", payload_text)
                declared_enum = set(match.group(1).replace("\\", "").split("|")) if match else set()
                variant_values = {str(v["when"][enum_field]) for v in inst["variants"] if enum_field in v["when"]}
                check("instantiation.exhaustive_derived", declared_enum and declared_enum == variant_values,
                      f"{oid}: payload enum {sorted(declared_enum)} != variant values {sorted(variant_values)}")
                exhaustiveness_checked += 1
            elif presence:
                variant_fields = {k for v in inst["variants"] for k in v["when"]}
                check("instantiation.exhaustive_derived",
                      variant_fields == set(presence) and all(f in payload_text for f in presence),
                      f"{oid}: presence branches {sorted(variant_fields)} != declared {sorted(presence)}")
                exhaustiveness_checked += 1
            else:
                # Neither key means neither branch ran, so nothing was compared and the
                # operation would contribute one fewer check while still passing. Refuse
                # instead: an instantiation whose exhaustiveness cannot be derived has not
                # been checked, and dropping a key must not be a way to stop being checked.
                check("instantiation.exhaustiveness_derived",
                      False,
                      f"{oid}: effect_goal_instantiation declares neither payload_enum_field nor "
                      "presence_branches, so exhaustiveness cannot be derived from the payload spec")

    # every operation with variants must have contributed exactly one exhaustiveness check
    check("instantiation.exhaustiveness_covered",
          exhaustiveness_checked == len(with_instantiation),
          f"{exhaustiveness_checked} exhaustiveness checks for {len(with_instantiation)} operations "
          f"with variants ({sorted(with_instantiation)})")

    # 2. evidence prerequisites are per-operation
    pre = [o["evidence_prerequisite"] for o in op_rows]
    check("evidence_prerequisite.per_op", len(set(pre)) == len(op_rows),
          f"expected {len(op_rows)} distinct prerequisites, got {len(set(pre))}")
    for o in op_rows:
        check("evidence_prerequisite.not_generic", len(o["evidence_prerequisite"]) > 40 and "N6.1" in o["evidence_prerequisite"],
              f"{o['operation_id']}: {o['evidence_prerequisite'][:60]!r}")

    # 3. targetRefs buckets follow N6.1:747
    kinds = {o["operation_id"]: o["target_refs_rule"]["kind"] for o in op_rows}
    check("target_refs.group_bucket", {k for k, v in kinds.items() if v == "selected_group_allowed"} == GROUP_BUCKET,
          f"group bucket={sorted(k for k, v in kinds.items() if v == 'selected_group_allowed')}")
    check("target_refs.frame_global_bucket", {k for k, v in kinds.items() if v == "frame_global_empty_allowed"} == FRAME_GLOBAL,
          f"frame-global bucket={sorted(k for k, v in kinds.items() if v == 'frame_global_empty_allowed')}")
    check("target_refs.reposition_entity_single", kinds.get("reposition_entity") == "single_entity",
          "reposition_entity must be single_entity (N6.1:747 allows a group only for reframe/group/maintain)")
    for oid in ("reposition_camera", "smooth_camera_motion"):
        check("target_refs.not_frame_global", kinds.get(oid) == "unnamed_in_source",
              f"{oid}: {kinds.get(oid)} — N6.1:747 allows an empty targetRefs only for level/hold/clear_lens_obstruction")
    check("target_refs.gap_recorded", bool(ops.get("target_refs_buckets", {}).get("gap_in_source")),
          "the unnamed_in_source source gap must be recorded")

    # 4. admissibility is a single value with an actuator-backed basis
    unsupported = {o["operation_id"] for o in op_rows if o["admissibility"] == "unsupported"}
    check("admissibility.values", all(o["admissibility"] in {"qualified", "needs_user_input", "unsupported"} for o in op_rows),
          "admissibility must be one of the three N6.2 values")
    check("admissibility.unsupported_set", unsupported == EXPECTED_UNSUPPORTED,
          f"unsupported={sorted(unsupported)} expected={sorted(EXPECTED_UNSUPPORTED)}")
    for oid, actuator in (("set_capture_parameter", "CameraService.swift:851"),
                          ("change_lens", "ZoomControlView.swift:85"),
                          ("select_capture_moment", "N6.1:741")):
        check("admissibility.actuator_basis", actuator in ops_by_id[oid]["admissibility_basis"],
              f"{oid}: basis must cite {actuator}")
    for o in op_rows:
        check("admissibility.basis_present", len(o.get("admissibility_basis", "")) > 30,
              f"{o['operation_id']}: missing admissibility_basis")

    # 5. case prerequisites come from §23.4 verbatim
    e234 = parse_234()
    check("case.prerequisite.coverage", all(c["case_id"] in e234 for c in cases),
          "every case must appear in §23.4")
    mismatched = [c["case_id"] for c in cases
                  if e234.get(c["case_id"]) and c.get("prerequisite") != e234[c["case_id"]]]
    check("case.prerequisite.verbatim", not mismatched, f"mismatched: {mismatched}")
    check("case.prerequisite.not_unspecified",
          not [c["case_id"] for c in cases if c.get("prerequisite") == "unspecified_in_source"],
          "prerequisites must not stay unspecified")

    # 6. disposition is consistent with admissibility (N4)
    behaviour_tokens = set(ops["n9_operation_tokens"]["behaviours_not_operations"]) | {
        "review_compare", "квалифицированная операция для обнаруженной проблемы"}
    inconsistent = []
    for c in cases:
        named = [t.strip() for t in re.split(r"/|,", c.get("operation", "")) if t.strip()]
        ops_named = [t for t in named if t in ops_by_id]
        if not ops_named or any(t in behaviour_tokens for t in named):
            continue
        if all(ops_by_id[t]["admissibility"] == "unsupported" for t in ops_named):
            if c["disposition"] == "conditional_review":
                inconsistent.append(c["case_id"])
    check("case.disposition_vs_admissibility", not inconsistent,
          f"cases with a sole unsupported operation but conditional_review disposition: {inconsistent}")

    # 7. review semantics encode N6.2:755-757
    for key in ("action_proposal", "qualification_ref_rule", "scope_rule", "pre_admission",
                "live_projection", "review_has_no_active_action", "alternative_group"):
        check("review_semantics.key", key in ops["review_semantics"], f"missing review_semantics.{key}")

    # 8. reposition_camera points at the frozen change_camera_angle id
    frozen = ops_by_id["reposition_camera"]["maps_to_frozen_actions"]
    check("reposition_camera.frozen_id", "change_camera_angle" in frozen.get("frozen", []),
          "change_camera_angle must be in the frozen mapping")
    check("reposition_camera.no_false_gap", not frozen.get("gap"),
          "the translate_camera_laterally gap must be gone")
    check("reposition_camera.contract_citation",
          "2783" in json.dumps(frozen, ensure_ascii=False) and CONTRACTS_SWIFT.exists(),
          "the note must cite the frozen id line in CameraAnalysisDomainContracts.swift")

    # 9. audit candidates carry actuator evidence
    for c in ops["candidate_additions_from_audit"]:
        check("candidates.actuator_evidence", "actuator" in c.get("actuator_evidence", "").lower(),
              f"{c['candidate_id']}: missing actuator evidence")

    # 9b. the effect-goal resolution block must not contradict the vocabulary (round-5 NR1)
    for o in op_rows:
        oid = o["operation_id"]
        res = o["effect_goal_resolution"]
        declared = res.get("metric_polarity")
        actual = vocab.get(o["effect_goal"]["metricID"], {}).get("polarity")
        check("polarity.resolution_matches_vocabulary", declared == actual,
              f"{oid}: effect_goal_resolution.metric_polarity={declared!r} but vocabulary says {actual!r}")

    # 9c. guards are validated, not merely declared (round-5 NR1)
    aliases = {}
    for canonical, spec in ops.get("metric_aliases", {}).items():
        for alias in spec.get("aliases", []):
            aliases[alias] = canonical
    cases_by_id = {c["case_id"]: c for c in cases}
    for o in op_rows:
        oid = o["operation_id"]
        res = o["effect_goal_resolution"]
        guards = res.get("guard_metrics") or []
        basis = {b["metric"]: b for b in res.get("guard_basis", [])}
        for metric in guards:
            check("guard.in_vocabulary", metric in vocab or metric in aliases,
                  f"{oid}: guard {metric!r} is not a known metric")
            check("guard.has_basis", metric in basis, f"{oid}: guard {metric!r} has no guard_basis entry")
        for metric, entry in basis.items():
            case = cases_by_id.get(entry["n9_case"])
            check("guard.basis_case_exists", case is not None,
                  f"{oid}: guard_basis names unknown case {entry['n9_case']!r}")
            if case:
                check("guard.basis_token_in_n9_predicate", entry["n9_token"] in case["verification_predicate"],
                      f"{oid}: token {entry['n9_token']!r} is not in {entry['n9_case']} predicate "
                      f"({case['verification_predicate']!r})")
    # a guard must not be invented for an operation whose §N9 predicates never say "guard"
    guard_cases = {c["case_id"] for c in cases if "guard" in c["verification_predicate"]}
    for o in op_rows:
        if not (o["effect_goal_resolution"].get("guard_metrics") or []):
            continue
        named = {c["case_id"] for c in cases
                 if o["operation_id"] in [t.strip() for t in re.split(r"/", c["operation"])]}
        check("guard.only_where_source_says_guard", bool(named & guard_cases),
              f"{o['operation_id']}: guards declared but none of its §N9 predicates mentions a guard")

    # 9d. case_metrics must match a fresh derivation from the case registry
    ops_by_case: dict[str, list[dict]] = {}
    for c in cases:
        for token in re.split(r"/", c["operation"]):
            token = token.strip()
            if token in ops_by_id:
                ops_by_case.setdefault(token, []).append(c)
    for o in op_rows:
        derived = sorted({
            m for c in ops_by_case.get(o["operation_id"], []) for m in vocab
            if re.search(r"(?<![a-z_])" + re.escape(m) + r"(?![a-z_])", c["verification_predicate"])
        })
        check("case_metrics.not_stale", o["effect_goal_resolution"].get("case_metrics_from_n9") == derived,
              f"{o['operation_id']}: case_metrics_from_n9 does not match the derivation from the case registry")

    # 9e. every frozen entry must be a real semantic action value, every technical one a real technical value (round-5 NR2)
    semantic_values = enum_values("SemanticActionType")
    check("frozen.semantic_extractor_not_vacuous", len(semantic_values) >= 20,
          f"extractor found {len(semantic_values)} semantic raw values")
    technical_values_all = enum_values("TechnicalQualityActionType")
    bad_frozen, bad_technical = [], []
    for o in op_rows:
        mapping = o.get("maps_to_frozen_actions", {})
        for name in mapping.get("frozen", []):
            if name not in semantic_values:
                bad_frozen.append(f"{o['operation_id']}->{name}")
        for name in mapping.get("technical", []):
            if name not in technical_values_all:
                bad_technical.append(f"{o['operation_id']}->{name}")
    check("frozen.membership", not bad_frozen, f"frozen entries that are not SemanticActionType values: {bad_frozen}")
    check("frozen.technical_membership", not bad_technical,
          f"technical entries that are not TechnicalQualityActionType values: {bad_technical}")
    check("frozen.membership_selftest",
          "invented_id" not in semantic_values and bool(semantic_values),
          "negative control failed: an invented id would pass the membership check")

    # 10b. §N10:900 fixes the reposition_entity EffectGoal verbatim
    rep = ops_by_id["reposition_entity"]["effect_goal"]
    check("n10.reposition_entity_effect_goal", rep.get("metricID") == "contour_gap" and rep.get("desired") == "increase",
          f"§N10:900 says contour_gap/increase, registry has {rep.get('metricID')}/{rep.get('desired')}")
    joined = " ".join(ops["declared_invariants"])
    for needle in ("effect_goal is never unspecified_in_source",
                   "evidence_prerequisite is per-operation",
                   "unnamed_in_source",
                   "admissibility=unsupported must not carry disposition=conditional_review"):
        check("declared_invariants.round4", needle in joined, f"missing invariant: {needle!r}")

    # 11. no technical action id inside a semantic (frozen) list.
    #     The technical ids are the raw string VALUES of the technical enum, so the
    #     extractor reads values, not case names — a case-name extractor can never
    #     match a snake_case frozen list and would pass vacuously (review round 4, C1).
    text = CONTRACTS_SWIFT.read_text(encoding="utf-8")
    technical_values = enum_values("TechnicalQualityActionType")
    check("frozen.technical_extractor_not_vacuous", len(technical_values) >= 5,
          f"extractor found {len(technical_values)} technical raw values — the leak check would be vacuous")

    def leaks(entries: list[dict]) -> list[str]:
        found = []
        for e in entries:
            for name in e.get("maps_to_frozen_actions", {}).get("frozen", []):
                if name in technical_values:
                    found.append(f"{e['operation_id']}->{name}")
        return found

    check("frozen.technical_leak", not leaks(op_rows), f"technical ids inside semantic lists: {leaks(op_rows)}")
    # self-test: the check must actually fire on an injected violation (guarded so an
    # empty extractor reports the non-vacuity failure instead of crashing — round-5 NR5)
    if technical_values:
        control = leaks([{"operation_id": "control", "maps_to_frozen_actions": {"frozen": [sorted(technical_values)[0]]}}])
        check("frozen.technical_leak_selftest", bool(control),
              "negative control did not fire — the leak check is not proving anything")

    # 12. counts stay honest
    check("coverage.total", ops["coverage_summary"]["operations_total"] == len(op_rows) == 20,
          f"expected 20 operations, registry has {len(op_rows)}")
    check("coverage.cases", cov["total_cases"] == len(cases) == 68,
          f"expected 68 cases, registry has {len(cases)}")
    check("coverage.n9", cov["n9_coverage"] == ["68/68"] or cov["n9_coverage"] == "68/68"
          or (isinstance(cov["n9_coverage"], dict)
              and cov["n9_coverage"].get("cases_with_operation") == 68
              and cov["n9_coverage"].get("cases_with_predicate") == 68),
          f"n9_coverage={cov['n9_coverage']!r}")

    print(f"checks run: {checks}")
    if failures:
        print(f"FAIL ({len(failures)})")
        for f in failures:
            print("  -", f)
        return 1
    print("PASS — all registry conformance invariants hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
