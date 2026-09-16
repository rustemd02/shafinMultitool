"""Invariants for the annotation-pilot sample builder and packet exporter.

Neither tool had a test. Both sit on the blind-pass integrity path: the builder
writes the annotator sample *and* the adjudicator key, and the exporter turns the
sample into what an annotator reads. If the key ever reached the sample, the pilot
would stop being blind — so the separation is asserted here rather than trusted.

`build_annotation_pilot.py` also defaults its output into the repository, so every
test passes `--out-dir` explicitly and nothing is written into the tree.

Run: python3 -m pytest tools/tests/test_annotation_pilot_packet.py -q
"""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
BUILDER = REPO_ROOT / "tools/camera_annotation/build_annotation_pilot.py"
EXPORTER = REPO_ROOT / "tools/camera_annotation/export_pilot_packet.py"

KEY_FIELDS = {"intended_verdict", "intended_reason", "focus"}


def run(script: Path, *args: str) -> tuple[int, str]:
    result = subprocess.run([sys.executable, str(script), *args],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
    return result.returncode, result.stdout + result.stderr


def build(out_dir: Path) -> tuple[list[dict], dict]:
    code, output = run(BUILDER, "--out-dir", str(out_dir))
    assert code == 0, output
    sample = [json.loads(line) for line
              in (out_dir / "pilot-sample-v1.jsonl").read_text(encoding="utf-8").splitlines()
              if line.strip()]
    key = json.loads((out_dir / "pilot-sample-v1-key.json").read_text(encoding="utf-8"))
    return sample, key


@pytest.fixture
def built(tmp_path: Path):
    return build(tmp_path / "pilot")


def test_the_sample_never_carries_the_adjudication_key(built):
    """One leaked key field per record would end the blind pass."""
    sample, key = built
    assert sample, "the builder produced an empty sample"
    leaked = [record["pilot_record_id"] for record in sample if KEY_FIELDS & set(record)]
    assert leaked == [], f"sample records carry key fields: {leaked}"
    assert key.get("adjudicator_only") is True
    assert key["entries"], "the key has no entries, so nothing could be adjudicated"


def test_the_sample_and_the_key_describe_the_same_records(built):
    sample, key = built
    assert [r["pilot_record_id"] for r in sample] == [e["pilot_record_id"] for e in key["entries"]]
    assert all(KEY_FIELDS <= set(entry) for entry in key["entries"]), "the key is missing its verdicts"


def test_the_builder_selection_is_deterministic(tmp_path: Path):
    """The chosen records must be reproducible; the recording time is not a selection.

    This test used to assert byte equality of the two files, which passed only when
    both builds landed in the same wall-clock second — `provenance.generated_at` is
    a timestamp. It failed a minute later, which is what a flaky assertion looks
    like. What is actually guaranteed is asserted instead: same records, same order,
    same content apart from the generation stamp.
    """
    first, _ = build(tmp_path / "a")
    second, _ = build(tmp_path / "b")

    assert [r["pilot_record_id"] for r in first] == [r["pilot_record_id"] for r in second]
    assert [r["case_id"] for r in first] == [r["case_id"] for r in second]

    def without_stamp(record: dict) -> dict:
        stripped = dict(record)
        provenance = dict(stripped["provenance"])
        provenance.pop("generated_at", None)
        stripped["provenance"] = provenance
        return stripped

    assert [without_stamp(r) for r in first] == [without_stamp(r) for r in second], (
        "the sample differs between builds in something other than the generation stamp")

    stamps = {r["provenance"]["generated_at"] for r in first + second}
    assert stamps, "no generation stamp was recorded at all"


def test_the_sample_is_labelled_synthetic_and_research_only(built):
    """A synthetic pilot must never read as human-gold evidence."""
    sample, _ = built
    provenance = sample[0]["provenance"]
    assert provenance["human_gold"] is False
    assert provenance["research_only"] is True
    assert provenance["origin"] == "ai_authored_synthetic_brief"


def test_the_exporter_refuses_an_empty_sample(tmp_path: Path):
    empty = tmp_path / "empty.jsonl"
    empty.write_text("", encoding="utf-8")
    code, output = run(EXPORTER, "--sample", str(empty), "--out-dir", str(tmp_path / "out"))
    assert code != 0, "an empty sample produced a packet"
    assert "no records" in output


def test_the_exporter_refuses_a_sample_that_leaks_key_fields(tmp_path: Path, built):
    sample, _ = built
    tampered = tmp_path / "tampered.jsonl"
    rows = [dict(record) for record in sample]
    rows[0]["intended_verdict"] = "bad"
    tampered.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    code, output = run(EXPORTER, "--sample", str(tampered), "--out-dir", str(tmp_path / "out"))
    assert code != 0, "the exporter accepted a leaking sample"
    assert "leaks" in output


def test_the_packet_contains_only_the_annotator_facing_columns(tmp_path: Path, built):
    sample, _ = built
    sample_path = tmp_path / "sample.jsonl"
    sample_path.write_text("\n".join(json.dumps(r) for r in sample) + "\n", encoding="utf-8")
    out = tmp_path / "out"
    code, output = run(EXPORTER, "--sample", str(sample_path), "--out-dir", str(out))
    assert code == 0, output
    with (out / "pilot-packet.csv").open(encoding="utf-8") as handle:
        header = next(csv.reader(handle))
    assert header == ["record_id", "case_id", "mode", "scenario", "advice"]
    blob = (out / "pilot-packet.md").read_text(encoding="utf-8")
    for field in KEY_FIELDS:
        assert field not in blob, f"the annotator packet mentions {field}"
