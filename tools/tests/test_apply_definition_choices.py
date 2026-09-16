"""The owner's definition choices must apply mechanically, or not at all.

The ten `pending_definition` rows of §5.1 cannot be measured, and choosing a reading
is the owner's decision. `tools/release/apply_definition_choices.py` turns that into
one small file plus one command, and this suite pins the properties that make it safe
to run against the frozen policy:

* a complete, valid choice set applies: every chosen row becomes defined, the source
  names the option and its formula, the version bumps, and the impact list records
  what was chosen;
* an incomplete or unknown choice set changes nothing (the tests hash the policy
  before and after);
* a second application is refused, so a decision cannot be re-applied by accident;
* the packet itself is not rewritten: it stays the record of the finding.

Every test runs against a copy of the real policy in a temp directory; the frozen
artifact in the repository is never touched by this suite.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/apply_definition_choices.py"
REAL_POLICY = REPO_ROOT / "datasets/camera-coach/v1/evaluation-policy-v1.json"
PACKET = (REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release"
          / "definition-packet-5-1.json")


def _load():
    spec = importlib.util.spec_from_file_location("apply_definition_choices", TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["apply_definition_choices"] = module
    spec.loader.exec_module(module)
    return module


tool = _load()
packet = json.loads(PACKET.read_text(encoding="utf-8"))


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture()
def policy(tmp_path: Path) -> Path:
    target = tmp_path / "evaluation-policy-v1.json"
    shutil.copyfile(REAL_POLICY, target)
    return target


def _pending(path: Path) -> list[str]:
    rows = json.loads(path.read_text(encoding="utf-8"))["runbook_5_1_rows"]["rows"]
    return sorted(row for row, entry in rows.items()
                  if entry["definition_status"] == "pending_definition")


def _all_first_option() -> dict[str, str]:
    return {row: entry["options"][0]["id"] for row, entry in packet["rows"].items()}


def _write_choices(tmp_path: Path, choices: dict) -> Path:
    path = tmp_path / "choices.json"
    path.write_text(json.dumps(choices), encoding="utf-8")
    return path


def _run(policy: Path, choices: Path, tmp_path: Path, *extra: str):
    out = tmp_path / "receipt.json"
    code = tool.main(["--choices", str(choices), "--policy", str(policy), "--out", str(out), *extra])
    receipt = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
    return code, receipt


def test_the_packet_covers_exactly_the_pending_rows(policy: Path):
    assert sorted(packet["rows"]) == _pending(policy)


def test_a_complete_choice_set_defines_every_row(policy: Path, tmp_path: Path):
    before = json.loads(policy.read_text(encoding="utf-8"))["schema_version"]
    code, receipt = _run(policy, _write_choices(tmp_path, _all_first_option()), tmp_path)
    assert code == 0
    updated = json.loads(policy.read_text(encoding="utf-8"))
    assert _pending(policy) == []
    for row, option in packet["rows"].items():
        entry = updated["runbook_5_1_rows"]["rows"][row]
        assert entry["definition_status"] == "defined_by_owner_choice"
        assert option["options"][0]["id"] in entry["definition_source"]
        assert option["options"][0]["formula"] in entry["definition_source"]
    assert updated["schema_version"] != before
    assert updated["revision_history"][-1]["impact"].count("option") == len(packet["rows"])
    assert receipt["rows"]["direction_horizon_precision"]["option"] == \
        packet["rows"]["direction_horizon_precision"]["options"][0]["id"]


def test_the_packet_is_not_rewritten(policy: Path, tmp_path: Path):
    before = _sha(PACKET)
    _run(policy, _write_choices(tmp_path, _all_first_option()), tmp_path)
    assert _sha(PACKET) == before


def test_an_incomplete_choice_set_changes_nothing(policy: Path, tmp_path: Path):
    choices = _all_first_option()
    dropped = sorted(choices)[0]
    choices.pop(dropped)
    before = _sha(policy)
    code, _ = _run(policy, _write_choices(tmp_path, choices), tmp_path)
    assert code == 1
    assert _sha(policy) == before, "an incomplete choice set must not partially edit the policy"


def test_an_unknown_option_changes_nothing(policy: Path, tmp_path: Path, capsys):
    choices = _all_first_option()
    row = sorted(choices)[0]
    choices[row] = "Z"
    before = _sha(policy)
    code, _ = _run(policy, _write_choices(tmp_path, choices), tmp_path)
    assert code == 2
    assert "does not exist" in capsys.readouterr().err
    assert _sha(policy) == before


def test_a_choice_for_a_row_that_is_not_pending_is_refused(policy: Path, tmp_path: Path):
    choices = _all_first_option()
    choices["pass_rate"] = "A"
    before = _sha(policy)
    code, _ = _run(policy, _write_choices(tmp_path, choices), tmp_path)
    assert code == 1
    assert _sha(policy) == before


def test_applying_twice_is_refused(policy: Path, tmp_path: Path, capsys):
    choices = _write_choices(tmp_path, _all_first_option())
    assert _run(policy, choices, tmp_path)[0] == 0
    after_first = _sha(policy)
    code, _ = _run(policy, choices, tmp_path)
    assert code == 2
    assert "already applied" in capsys.readouterr().err
    assert _sha(policy) == after_first


def test_the_receipt_names_the_next_freeze_step(policy: Path, tmp_path: Path):
    _, receipt = _run(policy, _write_choices(tmp_path, _all_first_option()), tmp_path)
    assert "freeze_receipt.py --check" in receipt["next_step"]
    assert receipt["choices_sha256"]


def test_the_applied_policy_still_carries_every_row(policy: Path, tmp_path: Path):
    _run(policy, _write_choices(tmp_path, _all_first_option()), tmp_path)
    updated = json.loads(policy.read_text(encoding="utf-8"))
    assert len(updated["runbook_5_1_rows"]["rows"]) == 26
    assert updated["runbook_5_1_rows"]["decision_packet_applied"]["rows"] == sorted(packet["rows"])


def test_a_missing_choices_file_fails_closed(policy: Path, tmp_path: Path, capsys):
    code = tool.main(["--choices", str(tmp_path / "absent.json"), "--policy", str(policy)])
    assert code == 2
    assert "FAIL CLOSED" in capsys.readouterr().err
