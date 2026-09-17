#!/usr/bin/env python3
"""Mutation tests for the current authored USDZ identity gate, not visual quality."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

SOURCE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("procedural_ar_validator", SOURCE / "scripts/validate_procedural_ar_assets.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ProceduralARAssetProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="setos-ar-provenance-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "repo"
        self.app = Path(self.directory.name) / "Fixture.app"
        self.app.mkdir()
        self.record = json.loads((SOURCE / validator.RECORD).read_text())
        self.record_path = self.root / validator.RECORD
        for relative in [validator.GENERATOR, validator.NOTICE] + [a["source_path"] for a in self.record["assets"]]:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / relative, destination)
        self.record_path.parent.mkdir(parents=True, exist_ok=True)
        self.write_record()
        for row in self.record["assets"] + [self.record["notice"]]:
            shutil.copyfile(self.root / row["source_path"], self.app / row["bundle_path"])

    def write_record(self):
        self.record_path.write_text(json.dumps(self.record))

    def testSelectedSourceAndExactBundlePassWithTwoAssets(self):
        result = validator.validate(self.root, app_root=self.app)
        self.assertEqual(result["assets"], 2)
        self.assertTrue(result["source_verified"])
        self.assertTrue(result["bundle_verified"])

    def testMissingDuplicateAndEmptyAssetSetsCannotPass(self):
        original = copy.deepcopy(self.record["assets"])
        for rows in [[], original[:1], [original[0], original[0]]]:
            with self.subTest(count=len(rows)):
                self.record["assets"] = rows
                self.write_record()
                with self.assertRaises(validator.ValidationError): validator.validate(self.root)

    def testChangedSourceGeneratorOrNoticeCannotBorrowReceipt(self):
        for relative in [validator.GENERATOR, validator.NOTICE, self.record["assets"][0]["source_path"]]:
            with self.subTest(path=relative):
                path = self.root / relative
                previous = path.read_bytes()
                path.write_bytes(previous + b"changed")
                with self.assertRaisesRegex(validator.ValidationError, "SHA mismatch"):
                    validator.validate(self.root)
                path.write_bytes(previous)

    def testStaleValidResourceInBundleIsRejected(self):
        shutil.copyfile(self.app / "Circle.usdz", self.app / "Person.usdz")
        with self.assertRaisesRegex(validator.ValidationError, "SHA mismatch: Person.usdz"):
            validator.validate(self.root, app_root=self.app)

    def testMissingBundledAuthorshipNoticeIsRejected(self):
        (self.app / self.record["notice"]["bundle_path"]).unlink()
        with self.assertRaisesRegex(validator.ValidationError, "Missing file"):
            validator.validate(self.root, app_root=self.app)

    def testUnsafeRecordPathAndSymlinkAreRejected(self):
        self.record["assets"][0]["source_path"] = "../Circle.usdz"
        self.write_record()
        with self.assertRaisesRegex(validator.ValidationError, "Unexpected asset path"):
            validator.validate(self.root)
        self.record = json.loads((SOURCE / validator.RECORD).read_text())
        self.write_record()
        path = self.root / validator.GENERATOR
        path.unlink()
        path.symlink_to(SOURCE / validator.GENERATOR)
        with self.assertRaisesRegex(validator.ValidationError, "Symlink"):
            validator.validate(self.root)

    def testNonAlignedPackageIsRejectedEvenWithUpdatedOuterHash(self):
        asset = self.record["assets"][0]
        path = self.root / asset["source_path"]
        with zipfile.ZipFile(path) as archive:
            payload = archive.read(asset["member"]["path"])
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr(asset["member"]["path"], payload)
        path.write_bytes(stream.getvalue())
        asset["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        asset["bytes"] = path.stat().st_size
        self.write_record()
        with self.assertRaisesRegex(validator.ValidationError, "64-byte aligned"):
            validator.validate(self.root)

    def testAdditionalArchiveMemberIsRejectedEvenWithUpdatedOuterHash(self):
        asset = self.record["assets"][0]
        path = self.root / asset["source_path"]
        with zipfile.ZipFile(path, "a", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("unexpected.txt", "unrecorded")
        asset["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        asset["bytes"] = path.stat().st_size
        self.write_record()
        with self.assertRaisesRegex(validator.ValidationError, "exactly one"):
            validator.validate(self.root)


if __name__ == "__main__":
    unittest.main()
