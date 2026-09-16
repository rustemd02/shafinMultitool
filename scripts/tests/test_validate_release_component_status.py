from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import plistlib
import shlex
import shutil
import subprocess
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
            if component["kind"] == "font":
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(REPO_ROOT / source_path, path)
            else:
                path.mkdir(parents=True)
        self.font_proof = json.loads((REPO_ROOT / MODULE.FONT_PROVENANCE_PATH).read_text())
        font_proof_path = self.root / MODULE.FONT_PROVENANCE_PATH
        font_proof_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO_ROOT / MODULE.FONT_PROVENANCE_PATH, font_proof_path)
        for font in self.font_proof["fonts"]:
            shutil.copy2(REPO_ROOT / font["notice_path"], self.root / font["notice_path"])
        shutil.copy2(REPO_ROOT / "shafinMultitool/Info.plist", self.root / "shafinMultitool/Info.plist")
        self.snapkit_proof = json.loads((REPO_ROOT / MODULE.SNAPKIT_PROVENANCE_PATH).read_text())
        shutil.copytree(REPO_ROOT / "Pods/SnapKit", self.root / "Pods/SnapKit", dirs_exist_ok=True)
        for source_path in (MODULE.SNAPKIT_PROVENANCE_PATH, "Podfile", "Podfile.lock", "Pods/Manifest.lock",
                            self.snapkit_proof["notice_source_path"], MODULE.SNAPKIT_ACKNOWLEDGEMENTS + ".plist",
                            MODULE.SNAPKIT_ACKNOWLEDGEMENTS + ".markdown"):
            destination = self.root / source_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO_ROOT / source_path, destination)
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
            if component["release_config_membership"]["Release"] == "bundled" and component["legal_state"] != "APPROVED"
        }
        self.assertEqual(len(blockers), len(bundled_ids))
        self.assertEqual(
            {blocker["id"] for blocker in blockers}, bundled_ids
        )
        self.assertFalse(any(blocker["kind"] == "font" for blocker in blockers))

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
        self._copy_font_bundle(app)
        shutil.copy2(self.root / self.snapkit_proof["notice_source_path"], app / self.snapkit_proof["notice_bundle_path"])
        blockers = MODULE.validate_record(self.root, self.record_path, app)
        self.assertEqual(
            len(blockers),
            sum(
                component["release_config_membership"]["Release"] == "bundled" and component["legal_state"] != "APPROVED"
                for component in self.record["components"]
            ),
        )
        bundle_path = self.record["components"][0]["expected"]["bundle_path"]
        assert bundle_path is not None
        (app / bundle_path).unlink()

        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundle path is missing"):
            MODULE.validate_record(self.root, self.record_path, app)

    def _copy_font_bundle(self, app: Path) -> None:
        app.mkdir(parents=True, exist_ok=True)
        for font in self.font_proof["fonts"]:
            shutil.copy2(self.root / font["source_path"], app / font["bundle_path"])
            shutil.copy2(self.root / font["notice_path"], app / font["notice_bundle_path"])
        shutil.copy2(self.root / "shafinMultitool/Info.plist", app / "Info.plist")

    def test_font_approval_requires_matching_notice_bytes(self) -> None:
        notice = self.root / self.font_proof["fonts"][0]["notice_path"]
        notice.write_bytes(b"a URL alone is not the admitted notice artifact")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "notice source SHA mismatch"):
            MODULE.validate_record(self.root, self.record_path)

    def test_font_approval_cannot_hide_replaced_binary(self) -> None:
        font = self.root / self.font_proof["fonts"][0]["source_path"]
        font.write_bytes(b"a different font with the same filename")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "font source SHA mismatch"):
            MODULE.validate_record(self.root, self.record_path)

    def test_font_proof_cannot_be_empty(self) -> None:
        self.font_proof["fonts"] = []
        (self.root / MODULE.FONT_PROVENANCE_PATH).write_text(json.dumps(self.font_proof))
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "font provenance is empty"):
            MODULE.validate_record(self.root, self.record_path)

    def test_font_proof_must_cover_every_declared_font(self) -> None:
        self.font_proof["fonts"].pop()
        (self.root / MODULE.FONT_PROVENANCE_PATH).write_text(json.dumps(self.font_proof))
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "cover exactly UIAppFonts"):
            MODULE.validate_record(self.root, self.record_path)

    def test_font_proof_requires_immutable_upstream(self) -> None:
        self.font_proof["upstream_commit"] = "main"
        (self.root / MODULE.FONT_PROVENANCE_PATH).write_text(json.dumps(self.font_proof))
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "immutable upstream"):
            MODULE.validate_record(self.root, self.record_path)

    def test_bundled_notice_must_exist_even_when_font_loads(self) -> None:
        app = self.root / "FontFixture.app"
        self._copy_font_bundle(app)
        self.assertEqual(len(MODULE.validate_font_provenance(self.root, app)), 5)
        (app / self.font_proof["fonts"][0]["notice_bundle_path"]).unlink()
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundled font notice is missing"):
            MODULE.validate_font_provenance(self.root, app)

    def test_bundled_notice_tampering_fails(self) -> None:
        app = self.root / "FontFixture.app"
        self._copy_font_bundle(app)
        (app / self.font_proof["fonts"][0]["notice_bundle_path"]).write_bytes(b"changed license")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundled font notice SHA mismatch"):
            MODULE.validate_font_provenance(self.root, app)

    def test_fonts_only_command_has_explicit_scope_and_fails_on_missing_evidence(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            status = MODULE.main(["--repo-root", str(self.root), "--fonts-only"])
        self.assertEqual(status, 0)
        self.assertIn("scope=source fonts=5 notices=5", stdout.getvalue())
        self.assertNotIn("KNOWN_BLOCKER_COUNT=0", stdout.getvalue())
        (self.root / MODULE.FONT_PROVENANCE_PATH).unlink()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(MODULE.main(["--repo-root", str(self.root), "--fonts-only"]), 1)

    def test_snapkit_exact_source_and_notice_proof(self) -> None:
        proof = MODULE.validate_snapkit_provenance(self.root)
        self.assertEqual((proof["version"], proof["source_file_count"], proof["license"]), ("5.7.1", 40, "MIT"))

    def test_snapkit_approval_cannot_bypass_missing_proof(self) -> None:
        next(row for row in self.record["components"] if row["id"] == "snapkit-dependency")["legal_state"] = "APPROVED"
        self._write_record()
        (self.root / MODULE.SNAPKIT_PROVENANCE_PATH).unlink()
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "SnapKit provenance file is missing"):
            MODULE.validate_record(self.root, self.record_path)

    def test_snapkit_same_version_does_not_hide_changed_source(self) -> None:
        path = self.root / "Pods/SnapKit/Sources/Constraint.swift"
        path.write_bytes(path.read_bytes() + b"\n// unverified modification\n")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "source tree SHA mismatch"):
            MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_extra_source_and_symlink_are_rejected(self) -> None:
        unexpected = self.root / "Pods/SnapKit/Sources/Unverified.swift"
        unexpected.write_bytes(b"// extra source")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "file coverage changed"):
            MODULE.validate_snapkit_provenance(self.root)
        unexpected.unlink()
        unexpected.symlink_to(self.root / "Podfile")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "symlink"):
            MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_lockfiles_must_match_installed_dependency(self) -> None:
        path = self.root / "Pods/Manifest.lock"
        path.write_bytes(path.read_bytes().replace(b"5.7.1", b"5.7.2"))
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "lockfiles differ"):
            MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_podfile_must_match_installed_lock(self) -> None:
        path = self.root / "Podfile"
        path.write_bytes(path.read_bytes() + b"\n# changed configuration\n")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "Podfile changed"):
            MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_acknowledgement_name_does_not_replace_full_notice(self) -> None:
        path = self.root / (MODULE.SNAPKIT_ACKNOWLEDGEMENTS + ".plist")
        value = plistlib.loads(path.read_bytes())
        next(row for row in value["PreferenceSpecifiers"] if row.get("Title") == "SnapKit")["FooterText"] = "SnapKit is MIT licensed"
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "complete exact MIT notice"):
            MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_duplicate_acknowledgement_is_rejected(self) -> None:
        path = self.root / (MODULE.SNAPKIT_ACKNOWLEDGEMENTS + ".plist")
        value = plistlib.loads(path.read_bytes())
        value["PreferenceSpecifiers"].append(next(row for row in value["PreferenceSpecifiers"] if row.get("Title") == "SnapKit"))
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "exactly once"):
            MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_requires_nonempty_immutable_proof(self) -> None:
        path = self.root / MODULE.SNAPKIT_PROVENANCE_PATH
        original = self.snapkit_proof.copy()
        for key, value in (("source_file_count", 0), ("upstream_commit", "master")):
            with self.subTest(key=key):
                proof = dict(original, **{key: value})
                path.write_text(json.dumps(proof))
                with self.assertRaises(MODULE.ComponentStatusValidationError):
                    MODULE.validate_snapkit_provenance(self.root)

    def test_snapkit_built_notice_missing_truncated_or_symlinked_fails(self) -> None:
        app = self.root / "SnapKitFixture.app"
        app.mkdir()
        notice = app / self.snapkit_proof["notice_bundle_path"]
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundled SnapKit MIT notice is missing"):
            MODULE.validate_snapkit_provenance(self.root, app)
        notice.write_bytes(b"SnapKit MIT")
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "bundled SnapKit MIT notice SHA mismatch"):
            MODULE.validate_snapkit_provenance(self.root, app)
        notice.unlink()
        notice.symlink_to(self.root / self.snapkit_proof["notice_source_path"])
        with self.assertRaisesRegex(MODULE.ComponentStatusValidationError, "symlink"):
            MODULE.validate_snapkit_provenance(self.root, app)

    def test_snapkit_scoped_cli_is_not_a_full_release_pass(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            self.assertEqual(MODULE.main(["--repo-root", str(self.root), "--snapkit-only"]), 0)
        self.assertIn("scope=source version=5.7.1 files=40 license=MIT", stdout.getvalue())
        self.assertNotIn("KNOWN_BLOCKER_COUNT=0", stdout.getvalue())

    @unittest.skipUnless(shutil.which("plutil"), "release acknowledgement shell integration requires plutil")
    def test_release_acknowledgement_stage_fails_without_packaged_notice(self) -> None:
        app = self.root / "SnapKitFixture.app"
        app.mkdir()
        shell_source = (REPO_ROOT / "scripts/validate_release_bundle.sh").read_text()
        function = "validate_acknowledgements() {" + shell_source.split("validate_acknowledgements() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        command = ("set -eu\n" + f"REPO_ROOT={shlex.quote(str(self.root))}\nAPP_ROOT={shlex.quote(str(app))}\n" +
                   f"COMPONENT_STATUS_VALIDATOR={shlex.quote(str(MODULE_PATH))}\n" +
                   'fail() { echo "FAIL $*" >&2; exit 1; }\nrequire_file() { test -f "$2" || fail "$1 missing"; }\n' +
                   function + "\nvalidate_acknowledgements\n")
        missing = subprocess.run(["bash", "-c", command], capture_output=True, text=True, check=False)
        self.assertNotEqual(missing.returncode, 0, missing.stdout + missing.stderr)
        self.assertNotIn("PASS CocoaPods acknowledgements", missing.stdout)
        self.assertIn("bundled SnapKit MIT notice is missing", missing.stderr)
        shutil.copy2(self.root / self.snapkit_proof["notice_source_path"], app / self.snapkit_proof["notice_bundle_path"])
        present = subprocess.run(["bash", "-c", command], capture_output=True, text=True, check=False)
        self.assertEqual(present.returncode, 0, present.stdout + present.stderr)
        self.assertIn("exact SnapKit MIT notice bundled", present.stdout)


if __name__ == "__main__":
    unittest.main()
