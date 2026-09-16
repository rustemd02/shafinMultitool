#!/usr/bin/env python3
"""Negative controls for engineering archive evidence; no Xcode or signing."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("archive_build", ROOT / "tools/release/archive_build.py")
archive_build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive_build)


class ArchiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def make_archive(self, platform="iPhoneOS"):
        archive = self.root / "candidate.xcarchive"
        app = archive / "Products/Applications/shafinMultitool.app"
        app.mkdir(parents=True)
        (archive / "Info.plist").write_bytes(plistlib.dumps({
            "ApplicationProperties": {"ApplicationPath": "Applications/shafinMultitool.app"}}))
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "shafinMultitool",
            "CFBundleIdentifier": "com.vigvamcev-media.shafinMultitool",
            "CFBundleSupportedPlatforms": [platform]}))
        binary = app / "shafinMultitool"
        binary.write_bytes(b"fixture-only-not-a-real-Mach-O")
        binary.chmod(0o700)
        return archive, app

    def test_nonzero_build_cannot_pass_with_stale_product(self):
        self.assertEqual(archive_build.classify_result(65, True, {"app": "stale"}, 0),
                         "engineering_build_failed")

    def test_zero_build_without_product_cannot_pass(self):
        self.assertEqual(archive_build.classify_result(0, True, None, 0), "engineering_build_failed")

    def test_changed_sources_cannot_pass(self):
        self.assertEqual(archive_build.classify_result(0, False, {"app": "built"}, 0),
                         "engineering_build_failed")

    def test_admission_failure_retains_distinct_engineering_result(self):
        self.assertEqual(archive_build.classify_result(0, True, {"app": "built"}, 1),
                         "engineering_archive_built_release_validation_failed")

    def test_valid_unsigned_product_still_requires_distribution_and_acceptance(self):
        self.assertEqual(archive_build.classify_result(0, True, {"app": "built"}, 0),
                         "unsigned_archive_validated_distribution_and_acceptance_pending")

    def test_missing_archive_metadata_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "no archive Info"):
            archive_build.inspect_archive(self.root / "missing.xcarchive")

    def test_application_path_escape_is_rejected(self):
        archive, _ = self.make_archive()
        (archive / "Info.plist").write_bytes(plistlib.dumps({
            "ApplicationProperties": {"ApplicationPath": "../../outside.app"}}))
        with self.assertRaisesRegex(ValueError, "expected application"):
            archive_build.inspect_archive(archive)

    def test_simulator_archive_is_rejected(self):
        archive, _ = self.make_archive("iPhoneSimulator")
        with self.assertRaisesRegex(ValueError, "iPhoneOS device"):
            archive_build.inspect_archive(archive)

    def test_missing_empty_and_nonexecutable_binary_are_rejected(self):
        archive, app = self.make_archive()
        binary = app / "shafinMultitool"
        binary.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "missing, empty or not executable"):
            archive_build.inspect_archive(archive)
        binary.write_bytes(b"fixture")
        binary.chmod(0o600)
        with self.assertRaisesRegex(ValueError, "missing, empty or not executable"):
            archive_build.inspect_archive(archive)
        binary.unlink()
        with self.assertRaisesRegex(ValueError, "missing, empty or not executable"):
            archive_build.inspect_archive(archive)

    def test_input_symlink_cannot_hide_external_bytes(self):
        source = self.root / "source"
        source.mkdir()
        (self.root / "external").write_bytes(b"external")
        link = source / "link"
        link.symlink_to(self.root / "external")
        with self.assertRaisesRegex(ValueError, "escapes"):
            archive_build.file_identity(link, source)

    def test_main_records_zero_exit_empty_archive_as_failure(self):
        repo, output = self.root / "repo", self.root / "output"
        repo.mkdir()
        output.mkdir()
        identity = {"fingerprint": "fixture", "baseline_commit": "fixture"}
        with patch("sys.argv", ["archive_build.py", "--repo-root", str(repo),
                                "--output-parent", str(output)]), \
             patch.object(archive_build, "source_identity", return_value=(identity, b"", [])), \
             patch.object(archive_build.shutil, "disk_usage", return_value=type("Disk", (), {"free": 16 * 1024**3})()), \
             patch.object(archive_build.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            self.assertEqual(archive_build.main(), 2)
        runs = list(output.iterdir())
        self.assertEqual(len(runs), 1)
        receipt = json.loads((runs[0] / "receipt.json").read_text())
        self.assertEqual(receipt["build_exit"], 0)
        self.assertEqual(receipt["status"], "engineering_build_failed")
        self.assertFalse(receipt["artifact_present"])
        self.assertFalse(receipt["release_ready"])
        self.assertFalse(receipt["distribution_signed"])


if __name__ == "__main__":
    unittest.main()
