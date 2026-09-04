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
            if component["source_state"] == "absent":
                continue
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
        bundled_ids = {
            component["id"]
            for component in self.record["components"]
            if component["release_config_membership"]["Release"] == "bundled"
        }
        self.assertEqual(len(blockers), len(bundled_ids))
        self.assertEqual(
            {blocker["id"] for blocker in blockers}, bundled_ids
        )

        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = MODULE.main(
                ["--repo-root", str(self.root), "--record", str(self.record_path)]
            )
        self.assertEqual(status, 1)
        output = stdout.getvalue()
        self.assertEqual(output.count("KNOWN_BLOCKER: "), len(bundled_ids))
        self.assertEqual(output.count("KNOWN_BLOCKER_COUNT="), 1)
        self.assertIn(
            f"KNOWN_BLOCKER_COUNT={len(bundled_ids)}", output
        )
        self.assertIn(
            f"release blocked by {len(bundled_ids)} known provenance blocker(s)",
            stderr.getvalue(),
        )

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

    def test_deferred_release_membership_blocks_until_concretely_resolved(self) -> None:
        component = self.record["components"][0]
        component["legal_state"] = "APPROVED"
        component["release_config_membership"]["Release"] = "deferred"
        if component["replacement_dependency"] is not None:
            component["replacement_dependency"]["status"] = "VERIFIED"
        self._write_record()

        blockers = MODULE.validate_record(self.root, self.record_path)
        blocker = next(row for row in blockers if row["id"] == component["id"])
        self.assertEqual(blocker["blocker"], "release-membership-deferred")

    def test_unknown_disposition_fails_closed(self) -> None:
        self.record["components"][0]["disposition"] = "MAYBE"
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "disposition is unknown"):
            MODULE.validate_record(self.root, self.record_path)

    def test_missing_font_or_asset_component_fails_closed(self) -> None:
        original_components = copy.deepcopy(self.record["components"])
        for component_id in ("font-oswald-variable", "set-grain-texture"):
            with self.subTest(component_id=component_id):
                self.record["components"] = [
                    component
                    for component in original_components
                    if component["id"] != component_id
                ]
                self._write_record()
                with self.assertRaisesRegex(
                    MODULE.ComponentStatusValidationError, "coverage mismatch"
                ):
                    MODULE.validate_record(self.root, self.record_path)
        self.record["components"] = original_components
        self._write_record()

    def test_retrain_and_replace_dispositions_are_valid_only_with_dependency(self) -> None:
        for component in self.record["components"]:
            component["legal_state"] = "APPROVED"
            dependency = component["replacement_dependency"]
            if dependency is not None:
                dependency["status"] = "VERIFIED"
        detr = next(
            component
            for component in self.record["components"]
            if component["id"] == "detr-segmentation-model"
        )
        detr["disposition"] = "RETRAIN"
        circle = next(
            component
            for component in self.record["components"]
            if component["id"] == "circle-usdz"
        )
        circle["disposition"] = "REPLACE"
        circle["replacement_dependency"] = {
            "task": "M12-038",
            "status": "VERIFIED",
            "reason": "Verified replacement is available.",
        }
        self._write_record()

        self.assertEqual(MODULE.validate_record(self.root, self.record_path), [])

    def test_replacement_disposition_without_dependency_fails_closed(self) -> None:
        detr = next(
            component
            for component in self.record["components"]
            if component["id"] == "detr-segmentation-model"
        )
        detr["disposition"] = "REPLACE"
        detr["replacement_dependency"] = None
        self._write_record()

        with self.assertRaisesRegex(
            MODULE.ComponentStatusValidationError, "replacement_dependency.*must be an object"
        ):
            MODULE.validate_record(self.root, self.record_path)

    def test_duplicate_scope_value_fails_closed(self) -> None:
        self.record["components"][0]["scope"].append(
            self.record["components"][0]["scope"][0]
        )
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "duplicate value"):
            MODULE.validate_record(self.root, self.record_path)

    def test_unknown_scope_value_fails_closed(self) -> None:
        self.record["components"][0]["scope"] = ["GLOBAL"]
        self._write_record()

        with self.assertRaisesRegex(
            MODULE.ComponentStatusValidationError, r"scope\[0\].*unknown"
        ):
            MODULE.validate_record(self.root, self.record_path)

    def test_exclusion_duplicate_scope_value_fails_closed(self) -> None:
        exclusion = self.record["explicit_exclusions"][0]
        exclusion["scope"].append(exclusion["scope"][0])
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "duplicate value"):
            MODULE.validate_record(self.root, self.record_path)

    def test_deferred_exclusion_fails_closed(self) -> None:
        exclusion = self.record["explicit_exclusions"][0]
        exclusion["release_config_membership"]["Release"] = "deferred"
        self._write_record()

        with self.assertRaisesRegex(
            MODULE.ComponentStatusValidationError, "must have Release=excluded"
        ):
            MODULE.validate_record(self.root, self.record_path)

    def test_cross_family_duplicate_source_path_fails_closed(self) -> None:
        first, second = self.record["components"][:2]
        second["expected"]["source_path"] = first["expected"]["source_path"]
        self._write_record()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "duplicate component source path"):
            MODULE.validate_record(self.root, self.record_path)

    def test_component_and_exclusion_path_duplication_fails_closed(self) -> None:
        source_path = self.record["components"][0]["expected"]["source_path"]
        self.record["explicit_exclusions"][0]["path"] = source_path
        self._write_record()

        with self.assertRaisesRegex(
            MODULE.ComponentStatusValidationError, "both component and exclusion"
        ):
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
            bundle_path = component["expected"].get("bundle_path")
            if bundle_path is None:
                continue
            (app / bundle_path).parent.mkdir(
                parents=True, exist_ok=True
            )
            (app / bundle_path).write_bytes(b"bundle fixture")
        blockers = MODULE.validate_record(self.root, self.record_path, app)
        self.assertEqual(
            len(blockers),
            sum(
                component["release_config_membership"]["Release"] == "bundled"
                for component in self.record["components"]
            ),
        )
        bundle_path = self.record["components"][0]["expected"]["bundle_path"]
        assert bundle_path is not None
        (app / bundle_path).unlink()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundle path is missing"):
            MODULE.validate_record(self.root, self.record_path, app)


if __name__ == "__main__":
    unittest.main()
