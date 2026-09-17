#!/usr/bin/env python3
"""Actual Xcode compilation and negative controls for localized release tables."""

import importlib.util
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "validate_release_localizations.py"
SPEC = importlib.util.spec_from_file_location("release_localizations", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def bilingual(english, russian):
    return {"localizations": {"en": unit(english), "ru": unit(russian)}}


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def catalog(strings):
    return {"sourceLanguage": "en", "version": "1.0", "strings": strings}


@unittest.skipUnless(sys.platform == "darwin" and Path("/usr/bin/xcrun").exists(), "requires the real Xcode string catalog compiler")
class CompiledLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.seed_directory = tempfile.TemporaryDirectory(prefix="localization-test-seed-")
        cls.seed = Path(cls.seed_directory.name).resolve()
        cls.seed_repo = cls.seed / "repo"
        cls.seed_resources = cls.seed_repo / gate.RESOURCE_ROOT
        cls.seed_resources.mkdir(parents=True)
        cls.seed_app = cls.seed / "Example.app"
        cls.seed_app.mkdir()
        write_json(cls.seed_resources / "InfoPlist.xcstrings", catalog({"CFBundleDisplayName": bilingual("Example", "Пример")}))
        strings = {"button": bilingual("Open", "Открыть"),
                   "only_source": {"localizations": {"en": unit("English fallback")}},
                   "implicit key": {}, "untranslated": {"shouldTranslate": False},
                   "empty": {"localizations": {"en": unit("English"), "ru": unit("", "new")}},
                   "format": bilingual('A quote " and \\ plus\n%2$@ %1$lld', 'Кавычка " и \\ плюс\n%2$@ %1$lld')}
        plurals = {"en": {"one": unit("%lld item"), "other": unit("%lld items")},
                   "ru": {"one": unit("%lld предмет"), "few": unit("%lld предмета"),
                          "many": unit("%lld предметов"), "other": unit("%lld предмета")}}
        strings["%lld items"] = {"localizations": {language: {"variations": {"plural": forms}} for language, forms in plurals.items()}}
        strings["items_for_name"] = {"localizations": {
            language: {**unit("%#@count@ for %2$@"), "substitutions": {
                "count": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": forms}}}}
            for language, forms in plurals.items()}}
        write_json(cls.seed_resources / "Localizable.xcstrings", catalog(strings))
        cls.compile_app(cls.seed_resources, cls.seed_app, "binary")

    @classmethod
    def tearDownClass(cls):
        cls.seed_directory.cleanup()

    @staticmethod
    def compile_app(resources, output, serialization):
        for table in gate.CATALOGS:
            subprocess.run(["/usr/bin/xcrun", "xcstringstool", "compile", str(resources / f"{table}.xcstrings"),
                            "--output-directory", str(output), "--serialization-format", serialization],
                           check=True, capture_output=True)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="localization-test-case-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo, self.app = self.root / "repo", self.root / "Example.app"
        shutil.copytree(self.seed_repo, self.repo)
        shutil.copytree(self.seed_app, self.app)
        self.resources = self.repo / gate.RESOURCE_ROOT

    def validate(self):
        return gate.validate_localizations(self.repo, self.app)

    def mutate_product(self, relative, mutate):
        path = self.app / relative
        data = plistlib.loads(path.read_bytes())
        mutate(data)
        path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))

    def assert_mismatch(self, token):
        report = self.validate()
        self.assertTrue(any(token in error for error in report["errors"]), report)
        return report

    def test_binary_plurals_substitutions_and_fallback_match(self):
        report = self.validate()
        self.assertEqual(report["errors"], [])
        self.assertEqual(len(report["products"]), 6)
        self.assertEqual(len(report["sources"]), 2)
        self.assertTrue(all(len(row["sha256"]) == 64 for row in report["sources"]))
        ru = plistlib.loads((self.app / "ru.lproj/Localizable.strings").read_bytes())
        self.assertNotIn("only_source", ru)
        self.assertNotIn("implicit key", ru)
        self.assertNotIn("untranslated", ru)
        self.assertEqual(ru["empty"], "")
        plural = plistlib.loads((self.app / "en.lproj/Localizable.stringsdict").read_bytes())
        self.assertEqual(plural["items_for_name"]["NSStringLocalizedFormatKey"], "%1$#@count@ for %2$@")

    def test_text_and_binary_serializations_compare_semantically(self):
        shutil.rmtree(self.app)
        self.app.mkdir()
        self.compile_app(self.resources, self.app, "text")
        self.assertEqual(self.validate()["errors"], [])

    def test_missing_locale(self):
        shutil.rmtree(self.app / "ru.lproj")
        self.assert_mismatch("missing localization product: ru.lproj/")

    def test_extra_empty_locale(self):
        (self.app / "fr.lproj").mkdir()
        with self.assertRaisesRegex(gate.ValidationError, "unexpected app locale directory: fr.lproj"):
            self.validate()

    def test_changed_locale(self):
        (self.app / "ru.lproj").rename(self.app / "ru-RU.lproj")
        with self.assertRaisesRegex(gate.ValidationError, "unexpected app locale directory: ru-RU.lproj"):
            self.validate()

    def test_missing_key(self):
        self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.pop("button"))
        self.assert_mismatch("missing_keys=1 extra_keys=0 changed_values=0")

    def test_extra_key(self):
        self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.update(extra="лишний"))
        self.assert_mismatch("missing_keys=0 extra_keys=1 changed_values=0")

    def test_changed_value(self):
        self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.update(button="Неверный текст"))
        self.assert_mismatch("missing_keys=0 extra_keys=0 changed_values=1")

    def test_changed_value_type(self):
        self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.update(button=1))
        self.assert_mismatch("changed_values=1")

    def test_missing_plural_product(self):
        (self.app / "ru.lproj/Localizable.stringsdict").unlink()
        self.assert_mismatch("missing localization product: ru.lproj/Localizable.stringsdict")

    def test_unexpected_stale_plural_product(self):
        (self.app / "ru.lproj/InfoPlist.stringsdict").write_bytes(plistlib.dumps({"old": "stale"}))
        self.assert_mismatch("unexpected localization product: ru.lproj/InfoPlist.stringsdict")

    def test_unexpected_unlocalized_root_table(self):
        (self.app / "Localizable.stringsdict").write_bytes(plistlib.dumps({"old": "stale"}))
        self.assert_mismatch("unexpected localization product: Localizable.stringsdict")

    def test_unexpected_nested_table(self):
        directory = self.app / "en.lproj/extra"
        directory.mkdir()
        (directory / "Localizable.strings").write_bytes(plistlib.dumps({"old": "stale"}))
        self.assert_mismatch("unexpected localization product: en.lproj/extra/Localizable.strings")

    def test_changed_plural_rule(self):
        self.mutate_product("ru.lproj/Localizable.stringsdict", lambda data: data["%lld items"]["value"].update(few="ошибка"))
        self.assert_mismatch("changed_values=1")

    def test_changed_substitution_format(self):
        self.mutate_product("en.lproj/Localizable.stringsdict", lambda data: data["items_for_name"].update(NSStringLocalizedFormatKey="%#@count@ for %2$@"))
        self.assert_mismatch("changed_values=1")

    def test_unexpected_fallback_entry_is_rejected(self):
        self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.update(only_source="English fallback"))
        self.assert_mismatch("extra_keys=1")

    def test_empty_bundle_dictionary(self):
        (self.app / "ru.lproj/Localizable.strings").write_bytes(plistlib.dumps({}))
        self.assert_mismatch("missing_keys=3")

    def test_malformed_bundle_plist(self):
        (self.app / "ru.lproj/Localizable.strings").write_bytes(b"this is not a property list")
        with self.assertRaisesRegex(gate.ValidationError, "localization tool failed"):
            self.validate()

    def test_malformed_xml_bundle_plist(self):
        (self.app / "ru.lproj/Localizable.strings").write_bytes(b'<?xml version="1.0"?><plist><dict></plist>')
        with self.assertRaisesRegex(gate.ValidationError, "localization tool failed"):
            self.validate()
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--repo-root", str(self.repo), "--app", str(self.app)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL LOCALIZATION:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_non_dictionary_bundle_plist(self):
        (self.app / "ru.lproj/Localizable.strings").write_bytes(plistlib.dumps(["bad"]))
        with self.assertRaisesRegex(gate.ValidationError, "not a string-keyed dictionary"):
            self.validate()

    def test_empty_source_is_rejected_before_vacuous_compile(self):
        write_json(self.resources / "Localizable.xcstrings", catalog({}))
        with self.assertRaisesRegex(gate.ValidationError, "must contain nonempty strings"):
            self.validate()

    def test_compiler_success_without_products_is_not_pass(self):
        write_json(self.resources / "Localizable.xcstrings", catalog({"implicit key": {}}))
        with self.assertRaisesRegex(gate.ValidationError, "compiler produced no en localization products"):
            self.validate()

    def test_missing_required_source_locale(self):
        write_json(self.resources / "Localizable.xcstrings", catalog({"key": {"localizations": {"en": unit("English")}}}))
        with self.assertRaisesRegex(gate.ValidationError, "compiler produced no ru localization products"):
            self.validate()

    def test_extra_source_locale(self):
        path = self.resources / "Localizable.xcstrings"
        document = json.loads(path.read_text())
        document["strings"]["button"]["localizations"]["fr"] = unit("Ouvrir")
        write_json(path, document)
        with self.assertRaisesRegex(gate.ValidationError, "unsupported source locales"):
            self.validate()

    def test_compiler_rejection_is_not_pass(self):
        path = self.resources / "Localizable.xcstrings"
        document = json.loads(path.read_text())
        document["strings"]["button"]["localizations"]["ru"]["stringUnit"]["value"] = ["not", "a string"]
        write_json(path, document)
        with self.assertRaisesRegex(gate.ValidationError, "localization tool failed"):
            self.validate()

    def test_duplicate_catalog_key_is_rejected(self):
        (self.resources / "Localizable.xcstrings").write_text('{"sourceLanguage":"en","strings":{"x":{},"x":{}},"version":"1.0"}')
        with self.assertRaisesRegex(gate.ValidationError, "duplicate catalog JSON key"):
            self.validate()

    def test_missing_source(self):
        (self.resources / "Localizable.xcstrings").unlink()
        with self.assertRaisesRegex(gate.ValidationError, "localization file is missing"):
            self.validate()

    def test_symlink_source(self):
        path = self.resources / "Localizable.xcstrings"
        path.unlink()
        path.symlink_to(self.seed_resources / "Localizable.xcstrings")
        with self.assertRaisesRegex(gate.ValidationError, "symlink is not an admitted"):
            self.validate()

    def test_symlink_locale(self):
        shutil.rmtree(self.app / "ru.lproj")
        (self.app / "ru.lproj").symlink_to(self.seed_app / "ru.lproj", target_is_directory=True)
        with self.assertRaisesRegex(gate.ValidationError, "invalid app localization directory"):
            self.validate()

    def test_source_mutation_during_check_is_rejected(self):
        compile_catalog = gate._compile_catalog

        def change_source(*args):
            compile_catalog(*args)
            path = self.resources / "Localizable.xcstrings"
            path.write_bytes(path.read_bytes() + b"\n")

        with mock.patch.object(gate, "_compile_catalog", side_effect=change_source):
            with self.assertRaisesRegex(gate.ValidationError, "source catalog changed during validation"):
                self.validate()

    def test_app_mutation_during_check_is_rejected(self):
        read_products = gate._app_products
        reads = 0

        def change_app(*args):
            nonlocal reads
            products = read_products(*args)
            reads += 1
            if reads == 1:
                self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.update(button="Изменилось"))
            return products

        with mock.patch.object(gate, "_app_products", side_effect=change_app):
            with self.assertRaisesRegex(gate.ValidationError, "app localization products changed during validation"):
                self.validate()

    def test_cli_missing_key_exits_nonzero_without_pass(self):
        self.mutate_product("ru.lproj/Localizable.strings", lambda data: data.pop("button"))
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--repo-root", str(self.repo), "--app", str(self.app)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing_keys=1", result.stderr)
        self.assertIn("LOCALIZATION_SOURCE:", result.stdout)
        self.assertNotIn("PASS localization", result.stdout)

    def test_cli_valid_products_exits_zero_and_records_sources(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--repo-root", str(self.repo), "--app", str(self.app)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS localization source/bundle equality", result.stdout)
        self.assertEqual(result.stdout.count("LOCALIZATION_SOURCE:"), 2)


if __name__ == "__main__":
    unittest.main()
