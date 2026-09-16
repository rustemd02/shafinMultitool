from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
ANNOTATION_DIR = REPO_ROOT / "tools/camera_annotation"
if str(ANNOTATION_DIR) not in sys.path:
    sys.path.insert(0, str(ANNOTATION_DIR))

import annotate_camera as cam  # noqa: E402


def _spec(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _vote(record_id: str, annotator: str, verdict: str, **kw):
    return cam.build_vote(
        record_id=record_id,
        annotator_id=annotator,
        verdict=verdict,
        subject_state="selected",
        selected_subject_id="e1",
        region_ids=[],
        **kw,
    )


def test_assisted_vote_requires_a_source():
    with pytest.raises(cam.AdmissionError) as error:
        _vote("r1", "human", "good", assisted=True)
    assert "assist_source" in str(error.value)


def test_assisted_vote_records_its_source():
    vote = _vote("r1", "human", "good", assisted=True, assist_source="camera_assist_hints_v1")
    assert vote["assisted"] is True
    assert vote["assist_source"] == "camera_assist_hints_v1"


def test_report_refuses_independence_when_only_one_human_plus_assist(tmp_path: Path):
    """M3-022: one human + AI hints are not two independent annotators."""
    store = tmp_path / "store.jsonl"
    cam.append_record(store, _vote("r1", "human", "good"))
    cam.append_record(store, _vote("r1", "human", "good", assisted=True, assist_source="camera_assist_hints_v1"))
    report = _spec("pilot_agreement_report", ANNOTATION_DIR / "pilot_agreement_report.py")
    out = tmp_path / "report.md"
    sys.argv = ["pilot_agreement_report.py", "--store", str(store), "--out", str(out)]
    assert report.main() == 0
    text = out.read_text(encoding="utf-8")
    assert "НЕДОСТУПНО" in text, "a single human plus hints must not yield an independence claim"
    assert "Assisted-голоса" in text
    assert "независимых 1" in text
    assert "κ по записям ровно с 2 голосами" in text and "n/a" in text


def test_report_computes_agreement_for_two_independent_humans(tmp_path: Path):
    store = tmp_path / "store.jsonl"
    cam.append_record(store, _vote("r1", "a1", "good"))
    cam.append_record(store, _vote("r1", "a2", "good"))
    report = _spec("pilot_agreement_report", ANNOTATION_DIR / "pilot_agreement_report.py")
    out = tmp_path / "report.md"
    sys.argv = ["pilot_agreement_report.py", "--store", str(store), "--out", str(out)]
    assert report.main() == 0
    text = out.read_text(encoding="utf-8")
    assert "НЕДОСТУПНО" not in text
    assert "Независимых аннотаторов: 2" in text


# ------------------------------------- one rater is one rater, however often it votes
def _run_report(tmp_path: Path, rows: list[tuple[str, str, str]]):
    store = tmp_path / "store.jsonl"
    for record_id, annotator, verdict in rows:
        cam.append_record(store, _vote(record_id, annotator, verdict))
    report = _spec("pilot_agreement_report", ANNOTATION_DIR / "pilot_agreement_report.py")
    out, payload = tmp_path / "report.md", tmp_path / "report.json"
    code = report.main(["--store", str(store), "--out", str(out), "--json-out", str(payload)])
    return code, out.read_text(encoding="utf-8"), json.loads(payload.read_text(encoding="utf-8"))


def test_two_ids_without_a_shared_record_is_not_an_independent_panel(tmp_path: Path):
    """κ over one person agreeing with themselves is not inter-annotator agreement.

    Every record here is a single annotator voting twice, so no record has two
    different raters. Before the fix this printed a κ of 1.000 and named two
    "independent annotators" while measuring nothing but self-consistency.
    """
    code, text, payload = _run_report(tmp_path, [
        ("r1", "a1", "good"), ("r1", "a1", "good"),
        ("r2", "a2", "bad"), ("r2", "a2", "bad"),
    ])
    assert code == 0
    assert payload["independent_annotators"] == 2
    assert payload["records_with_two_distinct_annotators"] == 0
    assert payload["independent_ready"] is False
    assert payload["fleiss_kappa"] is None
    assert "НЕДОСТУПНО" in text
    assert "самосогласие" in text, "the reason must say what was actually being measured"
    assert "1.000" not in text


def test_a_repeated_vote_is_a_revision_not_a_third_rater(tmp_path: Path):
    code, text, payload = _run_report(tmp_path, [
        ("r1", "a1", "good"), ("r1", "a1", "good"), ("r1", "a2", "good"),
        ("r2", "a1", "bad"), ("r2", "a2", "bad"),
    ])
    assert code == 0
    assert payload["repeated_votes_replaced"] == 1
    assert payload["records_with_two_distinct_annotators"] == 2
    assert payload["independent_ready"] is True
    assert "Повторных голосов" in text


def test_a_hand_edited_verdict_is_refused_not_absorbed(tmp_path: Path, capsys):
    """A verdict outside the closed set must not silently leave the denominators."""
    store = tmp_path / "store.jsonl"
    vote = _vote("r1", "a1", "good")
    tampered = dict(vote, verdict="maybe")
    store.write_text(json.dumps(vote) + "\n" + json.dumps(tampered) + "\n", encoding="utf-8")
    report = _spec("pilot_agreement_report", ANNOTATION_DIR / "pilot_agreement_report.py")
    assert report.main(["--store", str(store)]) == 2
    assert "FAIL CLOSED" in capsys.readouterr().err


def test_a_pair_with_no_shared_records_reports_no_percentage(tmp_path: Path):
    _, text, _ = _run_report(tmp_path, [("r1", "a1", "good"), ("r2", "a2", "bad")])
    assert "n/a (нет общих записей)" in text
    assert "| 0% |" not in text
