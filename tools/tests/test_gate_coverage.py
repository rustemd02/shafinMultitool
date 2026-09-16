"""Does the release-gate instrument cover every acceptance row of the runbook?

`tools/release/check_candidate_gates.py` will decide the release gates, so a gate
that the runbook requires but the tool silently omits would be a false "all gates
passed". This suite parses the runbook's §5.1 acceptance table and asserts, in
both directions:

* every table row maps to at least one gate the tool actually produces;
* every gate the tool produces is either mapped to a table row or explicitly
  listed as a supplementary requirement from §5.1 prose / §5.2 / the owner's
  prohibitions.

Adding a row to the runbook without mapping it here fails the suite, and so does
adding a gate to the tool without deciding what requirement it serves.
"""

from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNBOOK = REPO_ROOT / "docs/aegis/plans/2026-09-13-setos-release-execution.md"
GATE_TOOL = REPO_ROOT / "tools/release/check_candidate_gates.py"

# runbook §5.1 table row (matched by substring) -> gate names it must produce
TABLE_MAPPING: dict[str, list[str]] = {
    "pass / expected-action hit": ["pass_rate", "expected_action_hit"],
    "forbidden violations / critical forbidden": ["forbidden_violations", "critical_forbidden"],
    "technical failure gate": ["technical_failure"],
    "каждая scene class / material organic source": ["scene_class_min", "material_organic_source_min"],
    "synthetic/adversarial bucket": ["synthetic_adversarial"],
    "confidence-band accuracy / abstention correctness / verification accuracy": [
        "confidence_band_accuracy", "abstention_correctness", "verification_accuracy"],
    "direction/horizon precision": ["direction_horizon_precision"],
    "light/exposure precision": ["light_exposure_precision"],
    "false improved": ["false_improved"],
    "wrong-direction false success / wrong-target false success": [
        "wrong_direction_false_success", "wrong_target_false_success"],
    "accepted coverage overall / ordinary / difficult light": [
        "accepted_coverage_overall", "accepted_coverage_ordinary", "accepted_coverage_difficult_light"],
    "human safe+executable / helpful / preference среди non-ties": [
        "human_safe_executable", "human_helpful", "human_preference_non_ties"],
    "human materially harmful / critical harm": ["human_materially_harmful", "human_critical_harm"],
}

# requirements that live in §5.1 prose, §5.2, or the owner's prohibitions rather
# than in the table
SUPPLEMENTARY_MAPPING: dict[str, list[str]] = {
    "§5.1 prose: FP_CORRECT on good frames <=2% with the one-sided 95% upper bound":
        ["fp_correct_on_good_frames"],
    "§5.1 prose: incomparable stays in the confusion matrix":
        ["confusion_matrix_integrity"],
    "§5.1 prose: neural >=5pp over the deterministic baseline, paired bootstrap lower >0":
        ["neural_gain_over_baseline"],
    "§5.2: quotas, per-class and per-action floors, gold independence and kappa":
        ["quotas", "per_class_floors", "per_action_floors", "gold_independence_and_kappa"],
    "owner prohibition: three trained heads do not make the rest trained":
        ["trained_heads_backed_by_evidence"],
    "owner prohibition: no fitting on test / evaluation on the locked split":
        ["split_disjointness"],
    "owner prohibition: credits do not clear research-only weights for the App Store":
        ["weight_lineage_release_cleared"],
}


def _gate_names() -> set[str]:
    spec = importlib.util.spec_from_file_location("candidate_gates", GATE_TOOL)
    module = importlib.util.module_from_spec(spec)
    sys.modules["candidate_gates"] = module
    spec.loader.exec_module(module)
    # the complete fixture from the gate suite exercises every gate path
    tests = importlib.util.spec_from_file_location(
        "gate_tests", REPO_ROOT / "tools/tests/test_candidate_gates.py")
    gate_tests = importlib.util.module_from_spec(tests)
    sys.modules["gate_tests"] = gate_tests
    tests.loader.exec_module(gate_tests)
    produced = module.evaluate(gate_tests._complete_manifest())
    return {gate.name for gate in produced}


def _table_rows() -> list[str]:
    text = RUNBOOK.read_text(encoding="utf-8")
    section = text[text.index("### 5.1"):text.index("### 5.2")]
    rows = []
    for line in section.splitlines():
        if not line.startswith("|") or re.match(r"^\|[-| ]+\|$", line):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if cells and cells[0] and cells[0] != "Метрика":
            rows.append(cells[0])
    return rows


def test_every_acceptance_row_is_mapped_to_a_produced_gate():
    produced = _gate_names()
    rows = _table_rows()
    assert rows, "the §5.1 acceptance table was not found — the parser needs updating"
    unmapped = []
    for row in rows:
        mapping = next((names for key, names in TABLE_MAPPING.items() if key in row), None)
        if mapping is None:
            unmapped.append(row)
            continue
        for name in mapping:
            assert name in produced, f"row {row!r} maps to gate {name!r}, which the tool does not produce"
    assert not unmapped, (
        "runbook §5.1 gained acceptance rows with no gate mapping: "
        f"{unmapped} — decide the gate for each before trusting a release verdict"
    )


def test_supplementary_requirements_are_produced():
    produced = _gate_names()
    for requirement, names in SUPPLEMENTARY_MAPPING.items():
        for name in names:
            assert name in produced, f"{requirement}: gate {name!r} is missing from the tool"


def test_no_gate_is_unnapped():
    """A gate nobody mapped is a requirement nobody stated — or a leftover."""
    produced = _gate_names()
    mapped = {name for names in TABLE_MAPPING.values() for name in names}
    mapped |= {name for names in SUPPLEMENTARY_MAPPING.values() for name in names}
    extra = sorted(produced - mapped)
    assert not extra, (
        f"the tool produces gates that no acceptance requirement covers: {extra} — "
        "map each to a runbook requirement or remove it"
    )


def test_mapping_uses_only_existing_gates():
    """Guards the mapping itself against typos."""
    produced = _gate_names()
    unknown = sorted({n for names in TABLE_MAPPING.values() for n in names} - produced)
    assert not unknown, f"mapping names gates that do not exist: {unknown}"


def test_the_runbook_table_still_has_the_expected_rows():
    """If §5.1 is restructured, the mapping must be revisited deliberately."""
    rows = _table_rows()
    assert len(rows) >= 13, f"expected at least 13 acceptance rows, found {len(rows)}: {rows}"
    for key in TABLE_MAPPING:
        assert any(key in row for row in rows), f"mapped row {key!r} disappeared from the runbook"
