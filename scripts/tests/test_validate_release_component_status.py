from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/validate_release_component_status.py"
SPEC = importlib.util.spec_from_file_location("release_component_status", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
REAL_RECORD = REPO_ROOT / "docs/implementation/provenance/release-component-status.json"


class ReleaseComponentStatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="m12-033-component-status-")
        self.root = Path(self.temp_dir.name) / "repo"
        self.root.mkdir()
        self.record = json.loads(REAL_RECORD.read_text(encoding="utf-8"))
        inventory_path = self.root / self.record["source"]["inventory_path"]
        inventory_path.parent.mkdir(parents=True)
        shutil.copy2(REPO_ROOT / self.record["source"]["inventory_path"], inventory_path)
        for component in self.record["components"]:
            source_path = component["expected"]["source_path"]
            path = self.root / source_path
            path.mkdir(parents=True)
        for exclusion in self.record["explicit_exclusions"]:
            path = self.root / exclusion["path"]
            if path.suffix:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture\n")
            else:
                path.mkdir(parents=True, exist_ok=True)
        self.record_path = self.root / "status.json"
        self._write_record()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write_record(self) -> None:
        self.record_path.write_text(
            json.dumps(self.record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    def test_default_record_reports_each_pending_component_once(self) -> None:
        blockers = MODULE.validate_record(self.root, self.record_path)
        self.assertEqual(len(blockers), 5)
        self.assertEqual(
            {blocker["id"] for blocker in blockers}, MODULE.EXPECTED_COMPONENTS
        )

        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = MODULE.main(
                ["--repo-root", str(self.root), "--record", str(self.record_path)]
            )
        self.assertEqual(status, 1)
        output = stdout.getvalue()
        self.assertEqual(output.count("KNOWN_BLOCKER: "), 5)
        self.assertEqual(output.count("KNOWN_BLOCKER_COUNT="), 1)
        self.assertIn(
            f"KNOWN_BLOCKER_COUNT={len(MODULE.EXPECTED_COMPONENTS)}", output
        )
        self.assertIn("release blocked by 5 known provenance blocker(s)", stderr.getvalue())

    def test_verified_legal_and_replacement_states_unblock_release(self) -> None:
        for component in self.record["components"]:
            component["legal_state"] = "APPROVED"
            dependency = component["replacement_dependency"]
            if dependency is not None:
                dependency["status"] = "VERIFIED"
        self._write_record()

        self.assertEqual(MODULE.validate_record(self.root, self.record_path), [])
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            status = MODULE.main(
                ["--repo-root", str(self.root), "--record", str(self.record_path)]
            )
        self.assertEqual(status, 0)
        self.assertEqual(stdout.getvalue().count("KNOWN_BLOCKER_COUNT="), 1)
        self.assertIn("KNOWN_BLOCKER_COUNT=0", stdout.getvalue())

    def test_pending_legal_state_is_schema_valid_but_blocks(self) -> None:
        component = self.record["components"][0]
        component["legal_state"] = "PENDING"
        for other in self.record["components"][1:]:
            other["legal_state"] = "APPROVED"
            if other["replacement_dependency"] is not None:
                other["replacement_dependency"]["status"] = "VERIFIED"
        component["replacement_dependency"]["status"] = "VERIFIED"
        self._write_record()

        blockers = MODULE.validate_record(self.root, self.record_path)
        self.assertEqual([blocker["id"] for blocker in blockers], [component["id"]])
        self.assertEqual(blockers[0]["blocker"], "legal-state-pending")

    def test_unknown_disposition_fails_closed(self) -> None:
        self.record["components"][0]["disposition"] = "MAYBE"
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "disposition is unknown"):
            MODULE.validate_record(self.root, self.record_path)

    def test_missing_component_fails_closed(self) -> None:
        self.record["components"].pop()
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "coverage mismatch"):
            MODULE.validate_record(self.root, self.record_path)

    def test_missing_expected_path_fails_closed(self) -> None:
        source_path = self.record["components"][0]["expected"]["source_path"]
        shutil.rmtree(self.root / source_path)

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "source path is missing"):
            MODULE.validate_record(self.root, self.record_path)

    def test_missing_required_field_fails_closed(self) -> None:
        del self.record["components"][0]["legal_state"]
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "legal_state"):
            MODULE.validate_record(self.root, self.record_path)

    def test_unknown_field_fails_closed(self) -> None:
        self.record["components"][0]["not_a_contract_field"] = True
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "unknown field"):
            MODULE.validate_record(self.root, self.record_path)

    def test_bundle_membership_is_checked_when_app_is_supplied(self) -> None:
        app = self.root / "Built/shafinMultitool.app"
        app.mkdir(parents=True)
        for component in self.record["components"]:
            (app / component["expected"]["bundle_path"]).parent.mkdir(
                parents=True, exist_ok=True
            )
            (app / component["expected"]["bundle_path"]).write_bytes(b"bundle fixture")
        blockers = MODULE.validate_record(self.root, self.record_path, app)
        self.assertEqual(len(blockers), 5)
        (app / self.record["components"][0]["expected"]["bundle_path"]).unlink()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundle path is missing"):
            MODULE.validate_record(self.root, self.record_path, app)


if __name__ == "__main__":
    unittest.main()
