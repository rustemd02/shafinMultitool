"""DETR notices fail closed independently of unresolved model admission."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "detr_legal", Path(__file__).resolve().parents[1] / "validate_detr_legal.py"
)
owner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(owner)


class DETRLegalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.app = Path(self.temp.name) / "app"
        self.app.mkdir()
        self.record = self.root / owner.PROVENANCE_PATH
        self.record.parent.mkdir(parents=True)
        pins = {}
        record = {"schema": "setos-detr-source-and-notice-provenance-v1",
                  "component_id": "detr-segmentation-model"}
        for field, (source, bundle, _) in owner.NOTICE_PINS.items():
            data = ("fixture " + field + "\n").encode()
            digest = hashlib.sha256(data).hexdigest()
            pins[field] = (source, bundle, digest)
            record[field] = {"source_path": source, "bundle_path": bundle, "sha256": digest}
            path = self.root / source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            (self.app / bundle).write_bytes(data)
        self.record.write_text(json.dumps(record))
        for patch in (
            mock.patch.object(owner, "NOTICE_PINS", pins),
            mock.patch.object(owner, "PROVENANCE_SHA256",
                              hashlib.sha256(self.record.read_bytes()).hexdigest()),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def test_exact_source_and_bundle(self):
        self.assertEqual(owner.validate(self.root, self.app), 2)

    def test_missing_source_each_notice(self):
        for field, (source, _, _) in owner.NOTICE_PINS.items():
            with self.subTest(field=field):
                path = self.root / source
                original = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(ValueError, "missing/unsafe"):
                    owner.validate(self.root, self.app)
                path.write_bytes(original)

    def test_changed_source_each_notice_even_if_bundle_changed_to_match(self):
        for field, (source, bundle, _) in owner.NOTICE_PINS.items():
            with self.subTest(field=field):
                path, shipped = self.root / source, self.app / bundle
                original = path.read_bytes()
                path.write_bytes(b"changed")
                shipped.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                    owner.validate(self.root, self.app)
                path.write_bytes(original)
                shipped.write_bytes(original)

    def test_missing_bundle_each_notice(self):
        for field, (_, bundle, _) in owner.NOTICE_PINS.items():
            with self.subTest(field=field):
                path = self.app / bundle
                original = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(ValueError, "missing/unsafe"):
                    owner.validate(self.root, self.app)
                path.write_bytes(original)

    def test_changed_bundle_each_notice(self):
        for field, (_, bundle, _) in owner.NOTICE_PINS.items():
            with self.subTest(field=field):
                path = self.app / bundle
                original = path.read_bytes()
                path.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                    owner.validate(self.root, self.app)
                path.write_bytes(original)

    def test_record_content_change_is_not_self_approving(self):
        content = json.loads(self.record.read_text())
        content["admission"] = {"legal_state": "APPROVED"}
        self.record.write_text(json.dumps(content))
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            owner.validate(self.root, self.app)

    def test_empty_record_and_empty_notice_rejected(self):
        original = self.record.read_bytes()
        self.record.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            owner.validate(self.root, self.app)
        self.record.write_bytes(original)
        source = self.root / next(iter(owner.NOTICE_PINS.values()))[0]
        source.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            owner.validate(self.root, self.app)

    def test_bundle_symlink_rejected_even_to_correct_bytes(self):
        source, bundle, _ = owner.NOTICE_PINS["license"]
        path = self.app / bundle
        path.unlink()
        path.symlink_to(self.root / source)
        with self.assertRaisesRegex(ValueError, "missing/unsafe"):
            owner.validate(self.root, self.app)


if __name__ == "__main__":
    unittest.main()
