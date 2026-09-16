#!/usr/bin/env python3
"""P02 freeze-receipt tests: silent drift vs. a versioned, impact-list change.

The tool separates two post-freeze edits:

* content changed while the recorded version did not -> **silent drift**, exit 1;
* content changed *and* the version/identifier changed -> **versioned change**,
  which we deliberately answer with **exit 2**, not 0.

Why exit 2 (and not 0 with a warning): P02 says a change after freeze requires a
version *and* an explicit impact list. A version bump alone is not acceptance, so
a green CI gate (exit 0) would let a frozen-contract edit pass exactly as the
silent case does. Exit 2 keeps it visibly non-green ("review: record the impact
list") while still being distinct from exit 1 ("this is silent drift").

Every test runs against a temp copy of a small tree, never the live repo, so the
suite is independent of the working tree's current edits.

Run: python3 -m pytest tools/tests/test_freeze_receipt.py -q
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/freeze_receipt.py"

FREEZE_SET = {
    "set_version": 1,
    "version_keys": ["schema_version", "contract_version", "$id"],
    "artifacts": [
        {"path": "contracts/*.json", "category": "model-contract"},
        {"path": "data/registry.json", "category": "registry"},
        {
            "path": "data/protocol.md",
            "category": "protocol",
            "version_regex": "schema_version=(v?[0-9][A-Za-z0-9._-]*)",
            "version_regex_key": "schema_version",
        },
    ],
}

CONTRACT_A = {"schema_version": "1.0.0", "payload": "one"}
REGISTRY = {"schema_version": "3.0.0-draft.1", "payload": 1}
PROTOCOL = "# protocol\n\nschema_version=v1.0.0 and text\n"


def _json(value) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


class FreezeReceiptTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "contracts").mkdir()
        (self.root / "data").mkdir()
        (self.root / "freeze_set.json").write_text(_json(FREEZE_SET), encoding="utf-8")
        (self.root / "contracts/a.json").write_text(_json(CONTRACT_A), encoding="utf-8")
        (self.root / "data/registry.json").write_text(_json(REGISTRY), encoding="utf-8")
        (self.root / "data/protocol.md").write_text(PROTOCOL, encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_tool(self, *args: str) -> subprocess.CompletedProcess:
        cmd = [
            sys.executable, str(TOOL),
            "--root", str(self.root),
            "--set", "freeze_set.json",
            *args,
        ]
        return subprocess.run(cmd, capture_output=True, text=True, cwd=REPO_ROOT)

    def write_receipt(self, receipt: str = "receipt.json") -> subprocess.CompletedProcess:
        result = self.run_tool("--receipt", receipt, "--write")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def check(self, receipt: str = "receipt.json") -> subprocess.CompletedProcess:
        return self.run_tool("--receipt", receipt, "--check")

    # (a) write then check on an unchanged tree -> exit 0
    def test_write_then_check_is_clean(self):
        self.write_receipt()
        receipt = json.loads((self.root / "receipt.json").read_text(encoding="utf-8"))
        self.assertEqual(receipt["artifact_count"], 3)
        for artifact in receipt["artifacts"]:
            self.assertRegex(artifact["sha256"], r"^[0-9a-f]{64}$")
            self.assertGreater(artifact["size_bytes"], 0)
        # the protocol has no JSON version key, but its inline schema_version is read
        protocol = next(a for a in receipt["artifacts"] if a["path"] == "data/protocol.md")
        self.assertEqual(protocol["version_value"], "v1.0.0")

        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no drift", result.stdout.lower())

    # (b) content change without a version change -> silent drift, exit 1
    def test_content_change_without_version_bump_is_silent_drift(self):
        self.write_receipt()
        changed = dict(CONTRACT_A, payload="two")
        (self.root / "contracts/a.json").write_text(_json(changed), encoding="utf-8")

        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("contracts/a.json", result.stdout)
        self.assertIn("silent drift", result.stdout)
        self.assertIn("silent_drift=1", result.stdout)

    # (c) same edit WITH a version bump -> explicit versioned change, exit 2
    #     Rationale for exit 2 over exit 0 is in the module docstring.
    def test_version_bump_is_not_silent_drift(self):
        self.write_receipt()
        bumped = dict(CONTRACT_A, schema_version="1.0.1", payload="two")
        (self.root / "contracts/a.json").write_text(_json(bumped), encoding="utf-8")

        result = self.check()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("silent_drift=0", result.stdout)
        self.assertIn("versioned_changes=1", result.stdout)
        self.assertIn("requires impact list", result.stdout)
        self.assertIn("contracts/a.json", result.stdout)
        # no silent-drift entry is emitted; the word only appears in the "not silent drift" note
        self.assertNotIn("silent drift (content changed", result.stdout)

    # (d) removed and added files are reported separately, both as drift
    def test_removed_file_is_reported(self):
        self.write_receipt()
        (self.root / "data/registry.json").unlink()

        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("removed", result.stdout)
        self.assertIn("data/registry.json", result.stdout)
        self.assertIn("removed=1", result.stdout)

    def test_added_file_is_reported(self):
        self.write_receipt()
        (self.root / "contracts/b.json").write_text(_json({"schema_version": "1.0.0"}), encoding="utf-8")

        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("added", result.stdout)
        self.assertIn("contracts/b.json", result.stdout)
        self.assertIn("added=1", result.stdout)

    # (e) the suite runs on a temp copy; the receipt points inside the temp tree
    def test_runs_on_temp_copy_not_live_tree(self):
        self.write_receipt()
        receipt_path = self.root / "receipt.json"
        self.assertTrue(receipt_path.is_file())
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertTrue(str(receipt["freeze_set"]).startswith(str(self.root.resolve())))
        self.assertEqual(sorted(a["path"] for a in receipt["artifacts"]),
                         ["contracts/a.json", "data/protocol.md", "data/registry.json"])
        # the live receipt is untouched by this temp-root run
        live = REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/freeze-receipt.json"
        self.assertFalse(str(receipt_path) == str(live))

    # bonus: --diff between two receipts reports a versioned change
    def test_diff_reports_versioned_change(self):
        self.write_receipt("before.json")
        bumped = dict(CONTRACT_A, schema_version="1.0.1", payload="two")
        (self.root / "contracts/a.json").write_text(_json(bumped), encoding="utf-8")
        self.write_receipt("after.json")

        result = self.run_tool("--receipt", "after.json", "--diff", "--against", "before.json")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("versioned: contracts/a.json", result.stdout)

        identical = self.run_tool("--receipt", "after.json", "--diff", "--against", "after.json")
        self.assertEqual(identical.returncode, 0, identical.stdout + identical.stderr)
        self.assertIn("IDENTICAL", identical.stdout)

    # (f) an empty comparison must not read as a clean freeze
    def test_empty_freeze_set_and_receipt_fail_closed_on_check(self):
        (self.root / "freeze_set.json").write_text(
            _json({"set_version": 1, "artifacts": []}), encoding="utf-8")
        (self.root / "receipt.json").write_text(
            _json({"artifact_count": 0, "artifacts": []}), encoding="utf-8")

        result = self.check()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("FAIL CLOSED", result.stdout)
        self.assertIn("nothing to verify", result.stdout)

    def test_two_empty_receipts_do_not_compare_as_identical(self):
        empty = _json({"artifact_count": 0, "artifacts": []})
        (self.root / "a.json").write_text(empty, encoding="utf-8")
        (self.root / "b.json").write_text(empty, encoding="utf-8")

        result = self.run_tool("--receipt", "a.json", "--diff", "--against", "b.json")
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("FAIL CLOSED", result.stdout)


if __name__ == "__main__":
    unittest.main()
