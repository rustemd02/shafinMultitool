"""Non-vacuity and liveness tests for `backend/schemas/validate_scene_job.py`.

That validator prints the same `PASS` whether it checked eleven fixtures or none:
with an empty (or missing) fixtures directory both globs return nothing, the
failure list stays empty, and it reports `PASS: 0 positive + 0 negative`. The
counts are therefore asserted as a precondition, not read as a summary.

Two tests go further than counting. A validator can report the right number of
fixtures and still not validate them, so one test breaks a positive fixture and
one renames a valid envelope as a negative: each must turn the run red. Those
pin the direction of both loops, not just their presence.

Run: python3 -m pytest backend/tests/test_validate_scene_job_fixtures.py -q
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "backend/schemas/validate_scene_job.py"
FIXTURES = REPO_ROOT / "backend/schemas/fixtures"


def run_validator(fixtures: Path) -> tuple[int, str]:
    result = subprocess.run([sys.executable, str(VALIDATOR), "--fixtures", str(fixtures)],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
    return result.returncode, result.stdout + result.stderr


class SceneJobFixtureTests(unittest.TestCase):
    def test_the_real_fixture_set_passes_and_reports_both_kinds(self):
        code, output = run_validator(FIXTURES)
        self.assertEqual(code, 0, output)
        self.assertIn("positive", output)
        self.assertIn("negative", output)
        self.assertNotIn("0 positive", output)
        self.assertNotIn("0 negative", output)

    def test_an_empty_fixtures_directory_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, output = run_validator(Path(tmp))
            self.assertNotEqual(code, 0, "an empty fixture set reported success")
            self.assertIn("fixtures are missing", output)

    def test_a_missing_fixtures_directory_is_refused(self):
        code, output = run_validator(Path(tempfile.gettempdir()) / "no-such-fixtures-dir-xyz")
        self.assertNotEqual(code, 0)
        self.assertIn("fixtures are missing", output)

    def test_positives_without_negatives_are_refused(self):
        """Without a negative the schema's rejection direction is unproven."""
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            for path in FIXTURES.glob("job-valid-*.json"):
                shutil.copy(path, target / path.name)
            code, output = run_validator(target)
            self.assertNotEqual(code, 0)
            self.assertIn("fixtures are missing", output)

    def test_negatives_without_positives_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            for path in FIXTURES.glob("job-invalid-*.json"):
                shutil.copy(path, target / path.name)
            code, output = run_validator(target)
            self.assertNotEqual(code, 0)
            self.assertIn("fixtures are missing", output)

    def test_a_broken_positive_fixture_turns_the_run_red(self):
        """Proves the positive loop validates instead of just counting files."""
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            for path in FIXTURES.glob("*.json"):
                shutil.copy(path, target / path.name)
            broken = target / "job-valid-pending.json"
            payload = json.loads(broken.read_text(encoding="utf-8"))
            payload["request_id"] = "not-a-uuid"
            broken.write_text(json.dumps(payload), encoding="utf-8")
            code, output = run_validator(target)
            self.assertNotEqual(code, 0, "a malformed positive fixture was accepted")
            self.assertIn("UNEXPECTED FAIL", output)

    def test_a_valid_envelope_named_as_a_negative_turns_the_run_red(self):
        """Proves the negative loop actually rejects, rather than trusting the filename."""
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            for path in FIXTURES.glob("*.json"):
                shutil.copy(path, target / path.name)
            shutil.copy(target / "job-valid-pending.json", target / "job-invalid-looks-valid.json")
            code, output = run_validator(target)
            self.assertNotEqual(code, 0, "a well-formed envelope passed as a negative fixture")
            self.assertIn("UNEXPECTED PASS", output)


if __name__ == "__main__":
    unittest.main()
