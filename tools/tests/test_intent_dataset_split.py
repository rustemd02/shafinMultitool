"""Split integrity for the M00 intent-dataset builder.

`build_intent_dataset.py` splits per label class with `cut = max(1, ...)`, so a class
holding a single record sends its only row to train. With one record per class the
entire corpus lands in train and the test side comes out **empty** — while the tool
still exited 0 and printed `train=N test=0`. A dataset whose test half is empty can
be "evaluated" on nothing, which is the emptiness failure this repository keeps
finding, so the run now fails instead.

The dump format is the INTENTDUMP line the instrumented replay emits; these fixtures
are synthetic and carry no project data.

Run: python3 -m pytest tools/tests/test_intent_dataset_split.py -q
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
BUILDER = REPO_ROOT / "ml/camera_coach/intent_pilot/build_intent_dataset.py"
MODULE = "ml.camera_coach.intent_pilot.build_intent_dataset"


def dump_line(index: int, label: str) -> str:
    return (f"INTENTDUMP|rec{index}|label={label}|target=0.5|verdict={label}|conf=0.9"
            f"|act=[]|issues=[]|NUM[a={index}.0,b=2.0]|SEM[k=v]")


def run(dump: Path, labels: Path, out: Path, *extra: str) -> tuple[int, str]:
    result = subprocess.run([sys.executable, "-m", MODULE, "--dump", str(dump),
                             "--labels", str(labels), "--out-dir", str(out), *extra],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
    return result.returncode, result.stdout + result.stderr


@pytest.fixture
def labels(tmp_path: Path) -> Path:
    """An empty curated-labels file: labels are optional enrichment, not the split."""
    path = tmp_path / "labels.jsonl"
    path.write_text("", encoding="utf-8")
    return path


def write_dump(path: Path, per_class: int) -> Path:
    lines = []
    index = 0
    for label in ("good", "bad"):
        for _ in range(per_class):
            index += 1
            lines.append(dump_line(index, label))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def test_an_empty_dump_is_refused(tmp_path: Path, labels: Path):
    empty = tmp_path / "empty.log"
    empty.write_text("", encoding="utf-8")
    code, output = run(empty, labels, tmp_path / "out")
    assert code != 0
    assert "no INTENTDUMP records" in output


def test_one_record_per_class_is_refused_rather_than_emitting_an_empty_test_side(
        tmp_path: Path, labels: Path):
    dump = write_dump(tmp_path / "degenerate.log", per_class=1)
    code, output = run(dump, labels, tmp_path / "out")
    assert code != 0, f"an empty test split was accepted: {output}"
    assert "empty test split" in output
    assert "class counts" in output, "the refusal should say how many records each class had"


def test_a_healthy_corpus_produces_both_sides(tmp_path: Path, labels: Path):
    dump = write_dump(tmp_path / "healthy.log", per_class=4)
    out = tmp_path / "out"
    code, output = run(dump, labels, out)
    assert code == 0, output
    train = [json.loads(line) for line in (out / "intent-dataset-train.jsonl").read_text().splitlines() if line]
    test = [json.loads(line) for line in (out / "intent-dataset-test.jsonl").read_text().splitlines() if line]
    assert train and test, f"one side is empty: train={len(train)} test={len(test)}"
    assert len(train) + len(test) == 8


def test_an_explicit_zero_test_fraction_is_still_allowed(tmp_path: Path, labels: Path):
    """The guard must not forbid a caller who deliberately asks for no test split."""
    dump = write_dump(tmp_path / "degenerate.log", per_class=1)
    code, output = run(dump, labels, tmp_path / "out", "--test-fraction", "0")
    assert code == 0, output


def test_the_same_seed_produces_the_same_split(tmp_path: Path, labels: Path):
    """Same seed => same records, same split, same features.

    Not byte equality: every record embeds `provenance.generated_at`, a wall-clock
    stamp, so two runs that straddle a second differ in that one field. Asserting
    byte equality passed only while both runs happened to land in the same second,
    which is a flaky assertion rather than a guarantee.
    """
    dump = write_dump(tmp_path / "healthy.log", per_class=4)
    first, second = tmp_path / "a", tmp_path / "b"
    assert run(dump, labels, first, "--seed", "7")[0] == 0
    assert run(dump, labels, second, "--seed", "7")[0] == 0

    def without_stamp(path: Path) -> list[dict]:
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
        for row in rows:
            provenance = dict(row.get("provenance") or {})
            provenance.pop("generated_at", None)
            row["provenance"] = provenance
        return rows

    for name in ("intent-dataset-train.jsonl", "intent-dataset-test.jsonl"):
        left, right = without_stamp(first / name), without_stamp(second / name)
        assert left == right, f"{name} differs in something other than the generation stamp"
        assert left, f"{name} is empty"
        assert all("generated_at" in (json.loads(line).get("provenance") or {})
                   for line in (first / name).read_text(encoding="utf-8").splitlines() if line), \
            "the generation stamp was not recorded at all"


def test_missing_curated_labels_become_null_and_are_not_invented(tmp_path: Path):
    """A label file that does not cover a record must leave the field absent, not filled."""
    dump = write_dump(tmp_path / "healthy.log", per_class=4)
    labels = tmp_path / "labels.jsonl"
    labels.write_text(json.dumps({"record_id": "rec1", "problems": ["x"]}) + "\n", encoding="utf-8")
    out = tmp_path / "out"
    code, output = run(dump, labels, out)
    assert code == 0, output
    rows = [json.loads(line) for line in (out / "intent-dataset-train.jsonl").read_text().splitlines() if line]
    unlabelled = [r for r in rows if r.get("record_id") != "rec1"]
    assert unlabelled, "fixture produced no unlabelled rows"
    assert all(r["curated_problems"] is None for r in unlabelled)
