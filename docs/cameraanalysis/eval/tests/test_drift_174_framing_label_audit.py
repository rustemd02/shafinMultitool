from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-framing-label-audit"
)
ROWS = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-probe-instrumentation"
    / "m4-001-fullruntime-174-drift-r1-probe-instrumented.jsonl"
)
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)
FAMILY_KEYWORDS = {
    "occlusion": ["перекрыва", "прижат", "обрезан", "обреза", "закрыва", "помех", "передний план", "тесная", "режет"],
    "small_subject": ["слишком мал", "мало кадра", "пустого", "пустое", "пустоты"],
    "lighting": ["освещ", "темн", "пересвет", "вспышк", "ярк", "свет"],
    "focus": ["фокус", "резк", "смаз", "размыт"],
    "clutter": ["перегруж", "конкурир", "шумн"],
}


def _rows() -> dict[str, dict[str, dict]]:
    grouped: dict[str, dict[str, dict]] = {}
    for line in ROWS.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        grouped.setdefault(row["record_id"], {})[row.get("mode")] = row
    return grouped


def _labels() -> dict[str, dict]:
    return {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def _families(text: str) -> list[str]:
    lowered = text.lower()
    return sorted(
        family
        for family, keywords in FAMILY_KEYWORDS.items()
        if any(keyword in lowered for keyword in keywords)
    )


def _expected(rows: dict[str, dict[str, dict]], labels: dict[str, dict]) -> list[dict]:
    entries = []
    for record_id, label in labels.items():
        expected = set(label["expected_semantic_actions"] or [])
        framing = sorted({"step_back", "step_closer"} & expected)
        if not framing:
            continue
        action = "both" if len(framing) == 2 else framing[0]
        stated = _families(" | ".join(label.get("problems") or []))
        area = rows[record_id]["pause"]["debug_numeric_features"].get("subject_area_ratio") or 0
        implied = {"step_back": "occlusion", "step_closer": "small_subject", "both": "ambiguous"}[action]
        if implied == "ambiguous":
            classification = "ambiguous_expected_set"
        elif implied in stated:
            classification = "stated_problem_matches_action"
        elif not stated:
            classification = "no_stated_family"
        else:
            classification = "stated_problem_matches_a_different_family"
        if classification == "stated_problem_matches_action":
            recommendation = "keep"
        elif classification == "no_stated_family":
            recommendation = "add_explicit_wording"
        else:
            recommendation = "reword_or_replace"
        if action == "step_closer" and area >= 0.10:
            recommendation = "geometry_contradicts_expectation"
        entries.append(
            {
                "record_id": record_id,
                "expected_framing_actions": framing,
                "subject_area_ratio": round(area, 4),
                "stated_families": stated,
                "classification": classification,
                "recommendation": recommendation,
            }
        )
    return sorted(entries, key=lambda entry: entry["record_id"])


def test_audit_rows_match_the_committed_inputs() -> None:
    report = json.loads((LANE / "framing-label-audit.json").read_text(encoding="utf-8"))
    recomputed = _expected(_rows(), _labels())
    assert len(report["records"]) == len(recomputed)
    for reported, expected in zip(report["records"], recomputed):
        assert reported["record_id"] == expected["record_id"]
        assert reported["expected_framing_actions"] == expected["expected_framing_actions"]
        assert reported["subject_area_ratio"] == expected["subject_area_ratio"]
        assert reported["stated_families"] == expected["stated_families"]
        assert reported["classification"] == expected["classification"]
        assert reported["recommendation"] == expected["recommendation"]


def test_summary_counts_match_the_rows() -> None:
    report = json.loads((LANE / "framing-label-audit.json").read_text(encoding="utf-8"))
    entries = _expected(_rows(), _labels())
    classifications: dict[str, int] = {}
    recommendations: dict[str, int] = {}
    for entry in entries:
        classifications[entry["classification"]] = classifications.get(entry["classification"], 0) + 1
        recommendations[entry["recommendation"]] = recommendations.get(entry["recommendation"], 0) + 1
    summary = report["summary"]
    assert summary["records"] == len(entries)
    assert summary["classification"] == classifications
    assert summary["recommendations"] == recommendations
    assert summary["step_closer_records_with_area_below_0_10"] == sum(
        1
        for entry in entries
        if entry["expected_framing_actions"] == ["step_closer"] and entry["subject_area_ratio"] < 0.10
    )


def test_audit_keeps_the_geometry_contradictions_visible() -> None:
    report = json.loads((LANE / "framing-label-audit.json").read_text(encoding="utf-8"))
    contradictions = [
        entry
        for entry in report["records"]
        if entry["recommendation"] == "geometry_contradicts_expectation"
    ]
    assert [entry["record_id"] for entry in contradictions] == [
        "ca_img_080",
        "ca_img_212",
        "ca_img_236",
    ]
    assert "cannot be satisfied by any size signal" in report["implications"]["corpus"]
    assert report["verdict"].startswith("The framing class is a mix")


def test_manifest_pins_the_artifact() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
        assert path.stat().st_size == artifact["bytes"]
